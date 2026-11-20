import AVFoundation
import Foundation

/// Hazır bölümde tek sahneyi değiştirir (öneri 3). Dosya parça parça okunur/yazılır; belleğe tamamı alınmaz.
nonisolated enum AudioEditor {
    enum EditError: LocalizedError {
        case sceneNotFound
        var errorDescription: String? { "Sahne transkriptte bulunamadı." }
    }

    /// Bir turun (Timeline.turns indeksi) ait olduğu düz sahne indeksi.
    static func sceneIndex(forTurn turnIndex: Int, script: PodcastScript) -> Int? {
        var cursor = 0
        for (sceneIndex, item) in script.flatScenes.enumerated() {
            let count = item.scene.turns.count
            if turnIndex < cursor + count { return sceneIndex }
            cursor += count
        }
        return nil
    }

    /// Sahnenin tur aralığı (Timeline.turns içinde).
    static func turnRange(ofScene sceneIndex: Int, script: PodcastScript) -> Range<Int>? {
        var cursor = 0
        for (index, item) in script.flatScenes.enumerated() {
            let count = item.scene.turns.count
            if index == sceneIndex { return cursor..<(cursor + count) }
            cursor += count
        }
        return nil
    }

    @concurrent
    /// `master`: yeni sahneye mastering uygulanır mı (bölüm üretimdeki ses tasarımı kararı; verilmezse genel ayar).
    static func replaceScene(audio url: URL, timeline: Timeline, script: PodcastScript, sceneIndex: Int,
                             newTurns: [ScriptTurn], newClip rawClip: PCMClip,
                             master: Bool = SoundDesign.isEnabled) async throws -> Timeline {
        guard let range = turnRange(ofScene: sceneIndex, script: script), range.upperBound <= timeline.turns.count,
              !range.isEmpty else { throw EditError.sceneNotFound }
        let oldStart = timeline.turns[range.lowerBound].start
        let oldEnd = timeline.turns[range.upperBound - 1].end

        let reader = try AVAudioFile(forReading: url)
        let format = reader.processingFormat           // Float32, kayıt hızında (24 kHz mono)
        let rate = format.sampleRate
        let temp = url.deletingLastPathComponent().appending(path: "podcast-edit-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temp) }
        try? FileManager.default.removeItem(at: temp)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
                                       AVNumberOfChannelsKey: Int(format.channelCount), AVEncoderBitRateKey: QualityMode.bitrate(sampleRate: rate)]
        let writer = try AVAudioFile(forWriting: temp, settings: settings, commonFormat: .pcmFormatFloat32,
                                     interleaved: format.isInterleaved)

        func copy(from start: AVAudioFramePosition, to end: AVAudioFramePosition) throws {
            reader.framePosition = start
            var remaining = max(0, end - start)
            while remaining > 0 {
                let chunk = AVAudioFrameCount(min(remaining, 48_000))
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return }
                try reader.read(into: buffer, frameCount: chunk)
                if buffer.frameLength == 0 { return }
                try writer.write(from: buffer)
                remaining -= AVAudioFramePosition(buffer.frameLength)
            }
        }

        let startFrame = AVAudioFramePosition((oldStart * rate).rounded())
        let endFrame = min(reader.length, AVAudioFramePosition((oldEnd * rate).rounded()))
        try copy(from: 0, to: startFrame)

        // Yeni sahne: kenar sessizliği kırpılır, eşitlenir (#15), iç düşünme payları eklenir (#23), hedef hıza dönüştürülür.
        // Sahnenin son turundan sonraki pay ve sahne aralıkları değişen aralığın dışında kalır (korunur).
        let trimmed = AudioStitcher.trimEdges(rawClip)
        let placed = AudioStitcher.layout(master ? Mastering.master(trimmed) : trimmed, turns: newTurns, trailingPause: false)
        let clip = placed.clip
        let resampled = try resample(clip, to: format)
        try writer.write(from: resampled)
        let newDuration = Double(resampled.frameLength) / rate

        try copy(from: endFrame, to: reader.length)

        // Zaman çizelgesi: önceki turlar aynı, yeni turlar hizalanır, sonrakiler kaydırılır.
        let delta = newDuration - (oldEnd - oldStart)
        let scale = newDuration / max(clip.duration, 0.001)
        let chapterIndex = timeline.turns[range.lowerBound].chapterIndex
        var turns = Array(timeline.turns[..<range.lowerBound])
        for (turn, r) in zip(newTurns, placed.ranges) {
            turns.append(TimedTurn(id: 0, chapterIndex: chapterIndex, speaker: turn.speaker, text: turn.text,
                                   sourcePage: turn.sourcePage, start: oldStart + r.start * scale, end: oldStart + r.end * scale))
        }
        for var turn in timeline.turns[range.upperBound...] {
            turn.start += delta
            turn.end += delta
            turns.append(turn)
        }
        for i in turns.indices { turns[i].id = i }
        let chapters = timeline.chapters.map { chapter -> TimedChapter in
            var c = chapter
            if c.start > oldStart + 0.01 { c.start += delta }
            return c
        }
        let pauses = shiftPauses(timeline.thinkPauses, range: range, oldEnd: oldEnd, delta: delta, newCount: newTurns.count)
            + placed.pauses.map { ThinkPause(turnID: range.lowerBound + $0.turn, start: oldStart + $0.start * scale, end: oldStart + $0.end * scale) }
        let sceneStarts = timeline.sceneStarts?.map { $0 > oldStart + 0.01 ? $0 + delta : $0 }

        // m4a'nın moov kutusu kapatılırken yazılır: değiştirmeden önce dosyaları kapat.
        writer.close()
        reader.close()
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
        return Timeline(chapters: chapters, turns: turns, duration: max(0, timeline.duration + delta),
                        thinkPauses: timeline.thinkPauses == nil && pauses.isEmpty ? nil : pauses.sorted { $0.start < $1.start },
                        sceneStarts: sceneStarts)
    }

    /// Sahne değişiminde düşünme payları: öncekiler aynı, sahnenin iç payları düşer (yenileri eklenir),
    /// sahne sonundaki pay ve sonrakiler kaydırılır, tur kimlikleri yeni tur sayısına göre güncellenir.
    static func shiftPauses(_ pauses: [ThinkPause]?, range: Range<Int>, oldEnd: Double, delta: Double, newCount: Int) -> [ThinkPause] {
        (pauses ?? []).compactMap { p in
            var q = p
            if p.turnID < range.lowerBound { return p }
            if p.turnID >= range.upperBound {
                q.turnID += newCount - range.count
            } else if p.start >= oldEnd - 0.01, newCount > 0 {
                q.turnID = range.lowerBound + newCount - 1
            } else {
                return nil
            }
            q.start += delta
            q.end += delta
            return q
        }
    }

    /// Konu çıkarılırken silinecek aralık: konunun başından sonraki konunun başına kadar. Son konuda son turun sonuna
    /// kadar (kapanış korunur); son turlara bağlı düşünme payı (#23) varsa o da aralığa girer, yoksa payın sessizliği
    /// ve tonu zaman çizelgesinde karşılığı olmadan kapanıştan önce kalırdı.
    static func chapterCut(_ timeline: Timeline, chapterIndex: Int) -> ClosedRange<Double>? {
        guard let chapter = timeline.chapters.first(where: { $0.id == chapterIndex }) else { return nil }
        let start = chapter.start
        if let next = timeline.chapters.filter({ $0.start > start + 0.01 }).map(\.start).min() { return start...max(start, next) }
        let turns = timeline.turns.filter { $0.chapterIndex == chapterIndex }
        let ids = Set(turns.map(\.id))
        let turnEnd = turns.map(\.end).max() ?? timeline.duration
        let pauseEnd = (timeline.thinkPauses ?? []).filter { ids.contains($0.turnID) }.map(\.end).max() ?? 0
        return start...max(start, min(timeline.duration, max(turnEnd, pauseEnd)))
    }

    /// Öneri 10: bir konuyu (bölümü) sesten çıkarır; sonraki konular ve turlar kaydırılır, indeksler yeniden numaralanır.
    /// Silinen aralık: konunun başından bir sonraki konunun başına kadar (son konuda: son turun sonuna kadar; kapanış korunur).
    @concurrent
    static func removeChapter(audio url: URL, timeline: Timeline, chapterIndex: Int) async throws -> (timeline: Timeline, removed: ClosedRange<Double>) {
        guard let cut = chapterCut(timeline, chapterIndex: chapterIndex), timeline.chapters.count > 1 else { throw EditError.sceneNotFound }
        let start = cut.lowerBound, end = cut.upperBound
        let reader = try AVAudioFile(forReading: url)
        let format = reader.processingFormat
        let rate = format.sampleRate
        let temp = url.deletingLastPathComponent().appending(path: "podcast-cut-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temp) }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
                                       AVNumberOfChannelsKey: Int(format.channelCount), AVEncoderBitRateKey: QualityMode.bitrate(sampleRate: rate)]
        let writer = try AVAudioFile(forWriting: temp, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved)
        func copy(_ from: AVAudioFramePosition, _ to: AVAudioFramePosition) throws {
            reader.framePosition = from
            var remaining = max(0, to - from)
            while remaining > 0 {
                let chunk = AVAudioFrameCount(min(remaining, 48_000))
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return }
                try reader.read(into: buffer, frameCount: chunk)
                if buffer.frameLength == 0 { return }
                try writer.write(from: buffer)
                remaining -= AVAudioFramePosition(buffer.frameLength)
            }
        }
        try copy(0, AVAudioFramePosition((start * rate).rounded()))
        try copy(min(reader.length, AVAudioFramePosition((end * rate).rounded())), reader.length)
        writer.close()
        reader.close()
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)

        let delta = end - start
        var turns: [TimedTurn] = []
        var newID: [Int: Int] = [:]
        for var turn in timeline.turns where turn.chapterIndex != chapterIndex {
            if turn.start >= end - 0.01 { turn.start -= delta; turn.end -= delta }
            if turn.chapterIndex > chapterIndex { turn.chapterIndex -= 1 }
            newID[turn.id] = turns.count
            turn.id = turns.count
            turns.append(turn)
        }
        // #23/#10: düşünme payları ve sahne başlangıçları da kayar; silinen konununkiler düşer.
        let pauses = timeline.thinkPauses?.compactMap { p -> ThinkPause? in
            guard let id = newID[p.turnID], p.start < start - 0.01 || p.start >= end - 0.01 else { return nil }
            var q = p
            q.turnID = id
            if q.start >= end - 0.01 { q.start -= delta; q.end -= delta }
            return q
        }
        let sceneStarts = timeline.sceneStarts?.compactMap { s -> Double? in
            if s >= start - 0.01, s < end - 0.01 { return nil }
            return s >= end - 0.01 ? s - delta : s
        }
        var chapters: [TimedChapter] = []
        for var c in timeline.chapters where c.id != chapterIndex {
            if c.start >= end - 0.01 { c.start -= delta }
            c.id = chapters.count
            chapters.append(c)
        }
        return (Timeline(chapters: chapters, turns: turns, duration: max(0, timeline.duration - delta),
                         thinkPauses: pauses, sceneStarts: sceneStarts), start...end)
    }

    /// Int16 klibi yazıcının işleme biçimine (Float32, aynı/ farklı hız) çevirir.
    private static func resample(_ clip: PCMClip, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(clip.sampleRate), channels: 1, interleaved: false)!
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(clip.samples.count)) else {
            throw EditError.sceneNotFound
        }
        input.frameLength = AVAudioFrameCount(clip.samples.count)
        let out = input.floatChannelData![0]
        for (i, s) in clip.samples.enumerated() { out[i] = Float(s) / 32768 }
        if source.sampleRate == format.sampleRate, format.channelCount == 1, !format.isInterleaved { return input }

        guard let converter = AVAudioConverter(from: source, to: format) else { throw EditError.sceneNotFound }
        let capacity = AVAudioFrameCount(Double(input.frameLength) * format.sampleRate / source.sampleRate + 1024)
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { throw EditError.sceneNotFound }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed { status.pointee = .endOfStream; return nil }
            consumed = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        return output
    }
}
