import AVFoundation
import Foundation

/// Sahne WAV'larını tek bir AAC (m4a) dosyasında birleştirir ve transkript zaman çizelgesini üretir.
nonisolated enum AudioStitcher {
    struct SceneInput: Sendable {
        var url: URL
        var chapterIndex: Int
        var turns: [ScriptTurn]
        /// #20: kalite kapısından gelen kelime başlangıçları (sahneye göre sn); nil = yok.
        var wordTimes: [[Double]]? = nil
    }

    static let sceneGap = 0.35
    static let chapterGap = 0.9
    /// #23: düşünme payı (toplam 3–8 sn); tur sınırı ±0,6 sn içinde ≥120 ms'lik gerçek sessizliğe oturmalı.
    static let thinkRange = 3.0...8.0
    static let thinkSnapWindow = 0.6
    static let thinkMinSilence = 0.12
    /// Kelime zamanı yokken konuşmacı değişimi sayılan en kısa sessizlik (virgül duraklaması bundan kısadır).
    static let thinkSpeakerSilence = 0.25
    /// Kelime zamanı varken cevabın ilk kelimesi ile sessizliğin sonu arasındaki en büyük fark.
    static let thinkWordTolerance = 0.3
    /// Payın başında tondan önceki kısa sessizlik.
    static let thinkToneDelay = 0.25

    enum StitchError: LocalizedError {
        case empty
        var errorDescription: String? { "Birleştirilecek ses bulunamadı." }
    }

    /// Sahne içi yerleşim: düşünme payları eklenmiş klip ve tur aralıkları (sahne başına göre sn).
    struct SceneLayout: Sendable {
        var clip: PCMClip
        var ranges: [Range]
        var pauses: [Pause]
        /// Eklenen paylar (ekleme öncesi sahne zamanı, uzunluk); kelime zamanlarını kaydırmak için.
        var insertions: [Insertion]

        struct Range: Sendable, Equatable { var start: Double; var end: Double }
        struct Pause: Sendable, Equatable { var turn: Int; var start: Double; var end: Double }
        struct Insertion: Sendable, Equatable { var at: Double; var length: Double }

        /// Ekleme öncesi sahne zamanını ekleme sonrasına çevirir.
        func shifted(_ t: Double) -> Double {
            t + insertions.reduce(0) { $1.at <= t + 1e-6 ? $0 + $1.length : $0 }
        }
    }

    /// Ağır iş: ana iş parçacığı dışında çalışır. `design` = seviye eşitleme ve ses kimliği müziği.
    /// Sahnelerden biri `wordTimes` taşıyorsa `word_times.json` çıktının yanına (çıktının damgasıyla) yazılır;
    /// taşımıyorsa eskisi silinir.
    @concurrent
    static func stitch(scenes: [SceneInput], chapterTitles: [String], output: URL,
                       design: Bool = SoundDesign.isEnabled, identity: SoundIdentity = .current) async throws -> Timeline {
        guard !scenes.isEmpty else { throw StitchError.empty }
        try? FileManager.default.removeItem(at: output)

        let firstClip = try WAV.parse(Data(contentsOf: scenes[0].url))
        let sampleRate = firstClip.sampleRate
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: QualityMode.bitrate(sampleRate: Double(sampleRate)),
            AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue,
        ]
        let file = try AVAudioFile(forWriting: output, settings: settings, commonFormat: .pcmFormatInt16, interleaved: true)
        let music: SoundIdentity = design ? identity : .yok

        var cursor = 0.0
        var turns: [TimedTurn] = []
        var chapters: [TimedChapter] = []
        var pauses: [ThinkPause] = []
        var sceneStarts: [Double] = []
        var words: [Int: [Double]] = [:]
        var previousChapter: Int?
        var introTail: ArraySlice<Int16>?

        if let intro = music.intro(sampleRate: sampleRate) {
            let lead = min(intro.samples.count, Int(music.introLead * Double(sampleRate)))
            let head = PCMClip(samples: Array(intro.samples[..<lead]), sampleRate: sampleRate)
            try write(head, to: file)
            cursor += head.duration
            introTail = intro.samples[lead...]
        }
        let transition = music.transition(sampleRate: sampleRate)

        for (index, scene) in scenes.enumerated() {
            try Task.checkCancellation()
            var raw = index == 0 ? firstClip : try WAV.parse(Data(contentsOf: scene.url))
            if raw.sampleRate != sampleRate { raw = raw.resampled(to: sampleRate) }
            let kept = trimmedRange(raw)
            let trimStart = Double(kept.lowerBound) / Double(sampleRate)
            let trimmed = PCMClip(samples: Array(raw.samples[kept]), sampleRate: sampleRate)
            var placed = layout(design ? Mastering.master(trimmed) : trimmed, turns: scene.turns,
                                wordTimes: scene.wordTimes?.map { $0.map { $0 - trimStart } })

            if let previous = previousChapter {
                let gap: PCMClip
                if previous == scene.chapterIndex {
                    gap = .silence(seconds: sceneGap, sampleRate: sampleRate)
                } else if let transition {
                    gap = transition
                } else {
                    gap = .silence(seconds: chapterGap, sampleRate: sampleRate)
                }
                try write(gap, to: file)
                cursor += gap.duration
            }
            if previousChapter != scene.chapterIndex {
                let title = chapterTitles.indices.contains(scene.chapterIndex) ? chapterTitles[scene.chapterIndex] : ""
                chapters.append(TimedChapter(id: chapters.count, title: title, start: cursor))
            }
            previousChapter = scene.chapterIndex
            if let tail = introTail {
                placed.clip = SoundIdentity.mixUnderSpeech(placed.clip, music: tail)
                introTail = nil
            }

            sceneStarts.append(cursor)
            let firstTurn = turns.count
            for (turn, range) in zip(scene.turns, placed.ranges) {
                turns.append(TimedTurn(
                    id: turns.count, chapterIndex: scene.chapterIndex, speaker: turn.speaker,
                    text: turn.text, sourcePage: turn.sourcePage,
                    start: cursor + range.start, end: cursor + range.end))
            }
            for pause in placed.pauses {
                pauses.append(ThinkPause(turnID: firstTurn + pause.turn, start: cursor + pause.start, end: cursor + pause.end))
            }
            if let wordTimes = scene.wordTimes {
                for (k, times) in wordTimes.enumerated() where k < scene.turns.count && !times.isEmpty {
                    words[firstTurn + k] = times.map { cursor + placed.shifted(max(0, $0 - trimStart)) }
                }
            }
            try write(placed.clip, to: file)
            cursor += placed.clip.duration
        }
        if let outro = music.outro(sampleRate: sampleRate) {
            try write(outro, to: file)
            cursor += outro.duration
        }

        // Dosya kapanınca boyutu/zamanı kesinleşir; kelime zamanları bu sesin damgasıyla yazılır (sonraki "ses değişti"
        // bildirimi aynı sese ait zamanları silmez).
        file.close()
        WordSync.save(words, to: output.deletingLastPathComponent().appending(path: WordSync.fileName),
                      audio: WordSync.AudioStamp(of: output))
        return Timeline(chapters: chapters, turns: turns, duration: cursor, thinkPauses: pauses, sceneStarts: sceneStarts)
    }

    /// #23: soru turlarının bitişine düşünme payı (sessizlik + `ThinkTone`) ekler. Sahnenin son turu sahne sonunda
    /// biter; ara turlarda sınırdan emin olunamıyorsa (`thinkBoundary` nil) o soru için pay eklenmez: cevabın
    /// ortasına pay koymaktansa hiç koymamak.
    /// `trailingPause == false` → son turun payı eklenmez (sahne düzenlemede o pay sahnenin dışında korunur).
    /// `wordTimes`: kalite kapısının tur başına kelime başlangıçları (bu klibe göre sn); varsa sınırı onlar belirler.
    static func layout(_ clip: PCMClip, turns: [ScriptTurn], trailingPause: Bool = true, wordTimes: [[Double]]? = nil) -> SceneLayout {
        var ranges = SilenceAligner.turnRanges(clip: clip, characterCounts: turns.map { $0.text.count })
            .map { SceneLayout.Range(start: $0.start, end: $0.end) }
        let duration = clip.duration
        var cuts: [(turn: Int, at: Double, seconds: Double)] = []
        var runs: [(start: Double, end: Double)]?
        for (i, turn) in turns.enumerated() where i < ranges.count {
            guard let think = turn.think, think > 0 else { continue }
            let seconds = min(thinkRange.upperBound, max(thinkRange.lowerBound, think))
            if i == ranges.count - 1 {
                if trailingPause, duration > 0 { cuts.append((i, duration, seconds)) }
                continue
            }
            if runs == nil { runs = SilenceAligner.silenceRuns(clip: clip, minSeconds: thinkMinSilence) }
            guard let at = thinkBoundary(after: i, ranges: ranges, runs: runs!, wordTimes: wordTimes),
                  at > ranges[i].start + 0.05, at < ranges[i + 1].end - 0.05 else { continue }
            ranges[i].end = at
            ranges[i + 1].start = at
            cuts.append((i, at, seconds))
        }
        guard !cuts.isEmpty else { return SceneLayout(clip: clip, ranges: ranges, pauses: [], insertions: []) }

        let rate = clip.sampleRate
        let tone = ThinkTone.clip(sampleRate: rate)
        var samples: [Int16] = []
        samples.reserveCapacity(clip.samples.count + cuts.reduce(0) { $0 + Int($1.seconds * Double(rate)) })
        var copied = 0
        var pauses: [SceneLayout.Pause] = []
        var insertions: [SceneLayout.Insertion] = []
        for cut in cuts.sorted(by: { $0.at < $1.at }) {
            let index = min(clip.samples.count, max(copied, Int((cut.at * Double(rate)).rounded())))
            samples += clip.samples[copied..<index]
            copied = index
            let start = Double(samples.count) / Double(rate)
            let segment = PCMClip.silence(seconds: thinkToneDelay, sampleRate: rate)
                .appending(tone)
                .appending(.silence(seconds: max(0, cut.seconds - thinkToneDelay - tone.duration), sampleRate: rate))
            samples += segment.samples
            pauses.append(.init(turn: cut.turn, start: start, end: start + segment.duration))
            insertions.append(.init(at: cut.at, length: segment.duration))
        }
        samples += clip.samples[copied...]
        let shiftedRanges = ranges.map { r in
            SceneLayout.Range(start: r.start + insertions.reduce(0) { $1.at <= r.start + 1e-6 ? $0 + $1.length : $0 },
                              end: r.end + insertions.reduce(0) { $1.at < r.end - 1e-6 ? $0 + $1.length : $0 })
        }
        return SceneLayout(clip: PCMClip(samples: samples, sampleRate: rate), ranges: shiftedRanges, pauses: pauses, insertions: insertions)
    }

    /// #23: soru turu `i` ile cevabı arasındaki sınır (seçilen sessizliğin ortası); güven düşükse nil.
    /// `SilenceAligner.turnRanges` sınırı zaten en yakın sessizliğe oturttuğu için "yakında sessizlik var" yetmez:
    /// - Kelime zamanları varsa: sorunun son kelimesinden sonra başlayıp cevabın ilk kelimesine `thinkWordTolerance`
    ///   içinde biten sessizlik. Yoksa zamanlar sınırla uyuşmuyor demektir → nil.
    /// - Yoksa: tahmini sınırın ±`thinkSnapWindow` içindeki en uzun sessizlik; ≥ `thinkSpeakerSilence` olmalı ve iki
    ///   turun tahmini aralığındaki diğer her sessizlikten belirgin biçimde uzun olmalı (virgül ya da cümle arası
    ///   duraklamasına, yani cevabın ortasına pay konmasın).
    static func thinkBoundary(after i: Int, ranges: [SceneLayout.Range], runs: [(start: Double, end: Double)],
                              wordTimes: [[Double]]?) -> Double? {
        guard i >= 0, ranges.indices.contains(i + 1) else { return nil }
        func length(_ r: (start: Double, end: Double)) -> Double { r.end - r.start }
        if let words = wordTimes, words.indices.contains(i + 1), let next = words[i + 1].first {
            let last = words.indices.contains(i) ? (words[i].last ?? ranges[i].start) : ranges[i].start
            guard let run = runs.filter({ $0.start > last && abs($0.end - next) <= thinkWordTolerance })
                .min(by: { abs($0.end - next) < abs($1.end - next) }) else { return nil }
            return (run.start + run.end) / 2
        }
        let boundary = ranges[i].end
        let lo = ranges[i].start, hi = ranges[i + 1].end
        let inside = runs.filter { $0.start > lo + 0.02 && $0.end < hi - 0.02 }
        func distance(_ r: (start: Double, end: Double)) -> Double {
            boundary < r.start ? r.start - boundary : boundary > r.end ? boundary - r.end : 0
        }
        guard let best = inside.filter({ distance($0) <= thinkSnapWindow }).max(by: { length($0) < length($1) }),
              length(best) >= thinkSpeakerSilence,
              inside.allSatisfy({ ($0.start == best.start && $0.end == best.end) || length($0) < length(best) - 0.02 })
        else { return nil }
        return (best.start + best.end) / 2
    }

    /// Baştaki/sondaki uzun sessizlik dışında kalan örnek aralığı (0,1 sn pay bırakılır).
    static func trimmedRange(_ clip: PCMClip, threshold: Int16 = 200, keep: Double = 0.1) -> Swift.Range<Int> {
        let samples = clip.samples
        guard let first = samples.firstIndex(where: { abs(Int32($0)) > Int32(threshold) }),
              let last = samples.lastIndex(where: { abs(Int32($0)) > Int32(threshold) }) else { return 0..<samples.count }
        let pad = Int(keep * Double(clip.sampleRate))
        return max(0, first - pad)..<min(samples.count, last + 1 + pad)
    }

    /// Baştaki/sondaki uzun sessizliği 0,1 sn'ye indirir.
    static func trimEdges(_ clip: PCMClip, threshold: Int16 = 200, keep: Double = 0.1) -> PCMClip {
        PCMClip(samples: Array(clip.samples[trimmedRange(clip, threshold: threshold, keep: keep)]), sampleRate: clip.sampleRate)
    }

    private static func write(_ clip: PCMClip, to file: AVAudioFile) throws {
        guard !clip.samples.isEmpty else { return }
        let format = file.processingFormat
        let chunk = 48_000
        var offset = 0
        while offset < clip.samples.count {
            let count = min(chunk, clip.samples.count - offset)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { return }
            buffer.frameLength = AVAudioFrameCount(count)
            clip.samples.withUnsafeBufferPointer { src in
                buffer.int16ChannelData![0].update(from: src.baseAddress! + offset, count: count)
            }
            try file.write(from: buffer)
            offset += count
        }
    }
}

/// Ses tasarımı anahtarı (Ayarlar): seviye eşitleme (`Mastering`) ve ses kimliği müziği (`SoundIdentity`).
nonisolated enum SoundDesign {
    static let key = "soundDesign"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

nonisolated extension PCMClip {
    func appending(_ other: PCMClip) -> PCMClip { PCMClip(samples: samples + other.samples, sampleRate: sampleRate) }

    /// Doğrusal aradeğerlemeyle örnekleme hızı dönüşümü (motorlar karışırsa süre bozulmasın).
    func resampled(to rate: Int) -> PCMClip {
        guard rate != sampleRate, rate > 0, !samples.isEmpty else { return self }
        let count = Int((Double(samples.count) * Double(rate) / Double(sampleRate)).rounded())
        let ratio = Double(sampleRate) / Double(rate)
        var out = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            let x = Double(i) * ratio
            let j = min(samples.count - 1, Int(x))
            let k = min(samples.count - 1, j + 1)
            let f = x - Double(j)
            out[i] = Int16((Double(samples[j]) * (1 - f) + Double(samples[k]) * f).rounded())
        }
        return PCMClip(samples: out, sampleRate: rate)
    }
}
