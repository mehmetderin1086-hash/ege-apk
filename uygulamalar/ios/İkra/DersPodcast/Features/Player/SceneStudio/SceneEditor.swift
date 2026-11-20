import Foundation
import SwiftData

/// #10 sahne stüdyosu: tek sahnenin seslendirilmesi, bölüme yerleştirilmesi ve geri alınması.
/// Tek giriş noktası `replace`; stüdyo önizleme için `render` + `applyRendered` kullanır.
enum SceneEditor {
    nonisolated static let undoAudioName = "podcast-undo.m4a"
    nonisolated static let undoStateName = "podcast-undo.json"
    /// Düzenleme sürerken alınan yedek; yalnız düzenleme başarılı olunca `undoAudioName` olur.
    nonisolated static let pendingAudioName = "podcast-undo-pending.m4a"
    /// Sunucu sınırı (`audioJob` şeması ve TTS): tur başına en çok bu kadar UTF-16 birimi.
    nonisolated static let maxTurnLength = 1500

    /// Geri alma için düzenleme öncesi durum.
    nonisolated struct UndoState: Codable, Sendable {
        var sceneIndex: Int
        var scriptData: Data
        var timelineData: Data?
        var duration: Double
        var audioFileName: String
        var bookmarks: [String: Double]
        var masterBackup: Bool
        /// Tur indeksine bağlı veriler (şekil eşlemesi, çalışma paketi soruları); eski kayıtlarda yok.
        var turnRefs: TurnRefs?
        /// Bölüm sesinde an tutan diğer kayıtlar (kart, hata, canlı soru) "tür:kimlik" → eski zaman.
        var times: [String: Double]?
        /// Düzenleme SONRASI ses sürümü. Bölümün sesi başka bir yoldan değişince (yeniden üretim, konu çıkarma,
        /// önceki sese dönüş) uyuşmaz; geri alma kaydı düşer.
        var audioRevision: Int?

        /// Yalnız bu düzenlemenin hemen ardından (ses başka yoldan değişmeden) geri alınabilir.
        func isValid(currentRevision: Int) -> Bool { audioRevision == currentRevision }
    }

    /// Düzenlemede kayan küresel tur indeksleri: sahne `sceneStart`'tan başlar, `oldCount` tur `newCount` tur oldu.
    /// Geri almada veri düzenlemeden beri değişmediyse (`…After` ile aynı) önceki hâli yazılır; değiştiyse (ör. eşleme
    /// yeniden alındı) indeksler ters yönde kaydırılır.
    nonisolated struct TurnRefs: Codable, Sendable {
        var sceneStart: Int
        var oldCount: Int
        var newCount: Int
        var figureMapBefore: [FigureMapEntry]?
        var figureMapAfter: [FigureMapEntry]?
        var studyBefore: StudyPack?
        var studyAfter: StudyPack?

        var oldRange: Range<Int> { sceneStart..<(sceneStart + oldCount) }
        var newRange: Range<Int> { sceneStart..<(sceneStart + newCount) }
    }

    nonisolated static var sceneChangedError: APIError {
        APIError(status: 0, code: "state", message: "Sahne bu arada değişti (konu çıkarıldı ya da düzeltme uygulandı). Stüdyoyu kapatıp yeniden aç.")
    }

    /// Tek sahneyi yeni turlarla değiştirir: seslendirir ve bölüme yerleştirir (kilit altında).
    /// `expected`: çağıranın gördüğü sahne turları; kilit alındığında sahne başkaysa (`sceneChangedError`) uygulanmaz.
    static func replace(_ episode: Episode, sceneIndex: Int, turns: [ScriptTurn], expected: [ScriptTurn]? = nil,
                        context: ModelContext, generator: GenerationCoordinator) async throws {
        try await generator.withEditLock(episode) {
            try checkScene(episode, sceneIndex: sceneIndex, expected: expected)
            let wav = try await render(episode, sceneIndex: sceneIndex, turns: turns)
            defer { try? FileManager.default.removeItem(at: wav) }
            try await apply(episode, sceneIndex: sceneIndex, turns: turns, wav: wav, expected: expected, context: context)
        }
    }

    /// Önceden seslendirilmiş sahneyi kilit altında uygular (stüdyoda "Uygula"). Seslendirme kilit dışında yapıldığı
    /// için `expected` (stüdyonun açılıştaki turları) zorunlu: arada sahne değiştiyse (konu çıkarıldı, düz indeksler
    /// kaydı, düzeltme uygulandı) yeni ses başka bir sahnenin üstüne yazılmaz.
    static func applyRendered(_ episode: Episode, sceneIndex: Int, turns: [ScriptTurn], wav: URL, expected: [ScriptTurn],
                              context: ModelContext, generator: GenerationCoordinator) async throws {
        try await generator.withEditLock(episode) {
            try await apply(episode, sceneIndex: sceneIndex, turns: turns, wav: wav, expected: expected, context: context)
        }
    }

    /// Sahne hâlâ çağıranın gördüğü turları mı taşıyor?
    static func checkScene(_ episode: Episode, sceneIndex: Int, expected: [ScriptTurn]?) throws {
        guard let expected else { return }
        guard episode.script?.flatScenes[safeScene: sceneIndex]?.scene.turns == expected else { throw sceneChangedError }
    }

    /// Turların sunucu sınırına uyup uymadığı: aşan ilk turun sırası (1'den) ve uzunluğu.
    nonisolated static func overLimit(_ turns: [ScriptTurn]) -> (index: Int, length: Int)? {
        for (i, turn) in turns.enumerated() {
            let length = turn.text.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
            if length > maxTurnLength { return (i + 1, length) }
        }
        return nil
    }

    // MARK: Seslendirme

    /// Yalnız sahneyi seslendirir; bölüm değişmez. Sunucu motorunda `purpose: "edit"` (podcast hakkı düşmez),
    /// cihaz içinde metin önce `SpeakableText.prepare` (sözlük → okunuş) ile hazırlanır.
    static func render(_ episode: Episode, sceneIndex: Int, turns: [ScriptTurn]) async throws -> URL {
        guard let original = episode.script, let settings = episode.settings,
              original.flatScenes.indices.contains(sceneIndex) else { throw stateError }
        if let over = overLimit(turns) {
            throw APIError(status: 0, code: "invalid", message: "\(over.index). tur çok uzun (\(over.length)/\(maxTurnLength) karakter). Kısalt ya da ikiye böl.")
        }
        let script = replacing(original, sceneIndex: sceneIndex, turns: turns)
        let data: Data
        if settings.usesServerSpeech {
            let job = try await APIClient.shared.audioJob(AudioJobRequest(script: script, settings: settings,
                                                                          previousJobToken: episode.jobToken, purpose: "edit"))
            let request = TTSRequest(jobToken: job.jobToken, sceneIndex: sceneIndex,
                                     turns: turns.map { TTSTurn(speaker: $0.speaker, text: $0.text, style: $0.style) })
            // "Claude + Chirp": düzenlenen sahnenin okunuşları yeniden hazırlanır; hazırlanamazsa sahne düz Chirp ile gelir
            // (düzenleyen sonucu uygulamadan önce dinler).
            let readings = settings.engine == .claude
                ? ((try? await APIClient.shared.speechReadings(request.turns, language: settings.language)) ?? []) : []
            try Task.checkCancellation()
            let response = try await APIClient.shared.remoteTTS(request, engine: settings.engine, readings: readings)
            guard let decoded = Data(base64Encoded: response.audio) else {
                throw APIError(status: 0, code: "audio", message: "Ses yanıtı okunamadı.")
            }
            _ = try WAV.parse(decoded)
            data = decoded
        } else {
            let prepared = SpeakableText.prepare(turns, language: settings.language, dictionary: Pronunciations.all)
            data = WAV.encode(try await LocalSpeech.scene(turns: prepared.turns, settings: settings))
        }
        try Task.checkCancellation()
        let url = episode.directory.appending(path: "studio-scene-\(sceneIndex)-\(UUID().uuidString.prefix(8)).wav")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: Uygulama

    /// Hazır WAV'ı bölüme uygular (kilit çağıranda). `SceneMasters` tamsa kayıpsız yeniden birleştirme (üretimdeki ses
    /// tasarımıyla), değilse ya da kullanılamazsa m4a içinde akış hâlinde değiştirme. Yer imleri kayar, doğrulama
    /// sıfırlanır, kelime senkronu geçersizleşir. Oynatıcı kapatılmaz: dosya atomik değişir, `audioChanged` olayıyla
    /// oynatıcı aynı konumdan yeniden yüklenir. Geri alma kaydı yalnız düzenleme başarılı olunca yazılır.
    static func apply(_ episode: Episode, sceneIndex: Int, turns: [ScriptTurn], wav: URL, expected: [ScriptTurn]? = nil,
                      context: ModelContext) async throws {
        try checkScene(episode, sceneIndex: sceneIndex, expected: expected)
        guard let original = episode.script, let settings = episode.settings, let timeline = episode.timeline,
              let audioURL = episode.audioURL, let oldRange = AudioEditor.turnRange(ofScene: sceneIndex, script: original),
              oldRange.upperBound <= timeline.turns.count, !turns.isEmpty else { throw stateError }
        let script = replacing(original, sceneIndex: sceneIndex, turns: turns)
        guard let newRange = AudioEditor.turnRange(ofScene: sceneIndex, script: script) else { throw stateError }
        let clip = try WAV.parse(Data(contentsOf: wav))

        let id = episode.id
        let fm = FileManager.default
        let directory = episode.directory
        // Geri alma yedeği önce geçici adla (APFS'de kopya yer tutmaz); önceki düzenlemenin kaydı bozulmaz.
        let pendingAudio = directory.appending(path: pendingAudioName)
        try? fm.removeItem(at: pendingAudio)
        try fm.copyItem(at: audioURL, to: pendingAudio)
        let marks = (try? context.fetch(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.episodeID == id }))) ?? []
        let records = timedRecords(id, context: context)
        var undo = UndoState(sceneIndex: sceneIndex, scriptData: episode.scriptData, timelineData: episode.timelineData,
                             duration: episode.duration, audioFileName: audioURL.lastPathComponent,
                             bookmarks: Dictionary(uniqueKeysWithValues: marks.map { ($0.id.uuidString, $0.time) }),
                             masterBackup: false,
                             times: Dictionary(records.compactMap { r in r.get().map { (r.key, $0) } }, uniquingKeysWith: { a, _ in a }))

        // Üretimdeki ses tasarımı ve kimliği (bugünkü genel ayar değil); kopyalar silinmeden önce okunur.
        let options = SceneMasters.stitchOptions(id, episodeIdentity: settings.soundIdentity)
        let newTimeline: Timeline
        do {
            if SceneMasters.isComplete(id, scenes: original.flatScenes.count) {
                do {
                    newTimeline = try await restitch(episode, script: script, sceneIndex: sceneIndex, wav: wav,
                                                     options: options, audioURL: audioURL)
                    undo.masterBackup = true
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Kopyalar kullanılamadı (eksik/bozuk dosya): m4a yoluna düş, kopyalar bir daha denenmesin.
                    SceneMasters.invalidate(id)
                    newTimeline = try await AudioEditor.replaceScene(audio: audioURL, timeline: timeline, script: original,
                                                                     sceneIndex: sceneIndex, newTurns: turns, newClip: clip,
                                                                     master: options.design)
                }
            } else {
                // Eksik ya da sayısı tutmayan kopya bir sonraki düzenlemede de yanlış olur.
                if SceneMasters.exists(id) { SceneMasters.invalidate(id) }
                newTimeline = try await AudioEditor.replaceScene(audio: audioURL, timeline: timeline, script: original,
                                                                 sceneIndex: sceneIndex, newTurns: turns, newClip: clip,
                                                                 master: options.design)
            }
        } catch {
            try? fm.removeItem(at: pendingAudio)
            throw error
        }

        for mark in marks {
            mark.time = remap(mark.time, old: timeline, new: newTimeline, oldRange: oldRange, newRange: newRange)
        }
        for record in records {
            if let time = record.get() { record.set(remap(time, old: timeline, new: newTimeline, oldRange: oldRange, newRange: newRange)) }
        }
        // #10: küresel tur indeksi tutan veriler (şekil eşlemesi, soru → "Bu kısmı dinle") sahnenin tur sayısı kadar kayar.
        var refs = TurnRefs(sceneStart: oldRange.lowerBound, oldCount: oldRange.count, newCount: newRange.count,
                            figureMapBefore: episode.figureMap, studyBefore: episode.study)
        let shifted = remapTurnRefs(figureMap: refs.figureMapBefore, study: refs.studyBefore, oldRange: oldRange, newRange: newRange)
        if let map = shifted.figureMap, map != refs.figureMapBefore { episode.figureMap = map }
        if let study = shifted.study, study != refs.studyBefore { episode.study = study }
        refs.figureMapAfter = shifted.figureMap
        refs.studyAfter = shifted.study
        undo.turnRefs = refs
        episode.scriptData = (try? JSONEncoder().encode(script)) ?? episode.scriptData
        // #13: yeniden seslendirilen sahnenin eski ses uyarısı geçersiz.
        episode.audioIssues = episode.audioIssues.filter { $0.scene != sceneIndex }
        finish(episode, timeline: newTimeline, context: context)
        undo.audioRevision = episode.audioRevision
        commitUndo(undo, pendingAudio: pendingAudio, directory: directory)
    }

    /// Kayıpsız yol: sahne kopyası değişir, bölüm üretimdeki ses tasarımıyla yeniden birleştirilir. Hata olursa
    /// sahne kopyası eski hâline döner (önceki geri alma kopyası korunur).
    private static func restitch(_ episode: Episode, script: PodcastScript, sceneIndex: Int, wav: URL,
                                 options: (design: Bool, identity: SoundIdentity), audioURL: URL) async throws -> Timeline {
        let id = episode.id
        let fm = FileManager.default
        try SceneMasters.replace(id, scene: sceneIndex, with: wav)
        let temp = episode.directory.appending(path: "podcast-restitch.m4a")
        defer { try? fm.removeItem(at: temp) }
        let inputs = script.flatScenes.enumerated().map { index, item in
            AudioStitcher.SceneInput(url: SceneMasters.url(id, scene: index), chapterIndex: item.chapterIndex, turns: item.scene.turns)
        }
        do {
            let timeline = try await AudioStitcher.stitch(scenes: inputs, chapterTitles: script.chapters.map(\.title), output: temp,
                                                          design: options.design, identity: options.identity)
            try Task.checkCancellation()
            _ = try fm.replaceItemAt(audioURL, withItemAt: temp)
            SceneMasters.commitReplace(id)
            return timeline
        } catch {
            SceneMasters.rollbackReplace(id, scene: sceneIndex)
            throw error
        }
    }

    /// Başarılı düzenlemenin geri alma kaydı: geçici yedek kalıcı ada taşınır, durum yeni ses sürümüyle yazılır.
    /// Yedek tam bölüm boyundadır: cihaz yedeğine (iCloud/Finder) girmez.
    private static func commitUndo(_ state: UndoState, pendingAudio: URL, directory: URL) {
        let fm = FileManager.default
        var undoAudio = directory.appending(path: undoAudioName)
        do {
            try? fm.removeItem(at: undoAudio)
            try fm.moveItem(at: pendingAudio, to: undoAudio)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? undoAudio.setResourceValues(values)
            try JSONEncoder().encode(state).write(to: directory.appending(path: undoStateName), options: .atomic)
        } catch {
            try? fm.removeItem(at: pendingAudio)
            clearUndo(directory: directory)
        }
    }

    // MARK: Geri alma

    static func canUndo(_ episode: Episode) -> Bool { validUndoState(episode) != nil }

    static func undoState(_ episode: Episode) -> UndoState? {
        (try? Data(contentsOf: episode.directory.appending(path: undoStateName))).flatMap { try? JSONDecoder().decode(UndoState.self, from: $0) }
    }

    /// Geçerli geri alma kaydı; ses o düzenlemeden sonra başka yoldan değiştiyse (sürüm uyuşmuyor) ya da yedek eksikse
    /// kayıt silinir ve nil döner.
    static func validUndoState(_ episode: Episode) -> UndoState? {
        let fm = FileManager.default
        let directory = episode.directory
        let stateURL = directory.appending(path: undoStateName), audioURL = directory.appending(path: undoAudioName)
        guard fm.fileExists(atPath: stateURL.path) || fm.fileExists(atPath: audioURL.path) else { return nil }
        guard let state = undoState(episode), state.isValid(currentRevision: episode.audioRevision),
              fm.fileExists(atPath: audioURL.path) else {
            clearUndo(directory: directory)
            return nil
        }
        return state
    }

    /// Ses değişen her yolda `WordSync.invalidate` üzerinden de çağrılır (yeniden üretim, konu çıkarma, önceki sese dönüş).
    nonisolated static func clearUndo(directory: URL) {
        try? FileManager.default.removeItem(at: directory.appending(path: undoStateName))
        try? FileManager.default.removeItem(at: directory.appending(path: undoAudioName))
    }

    /// Son sahne düzenlemesini geri alır (ses, senaryo, zaman çizelgesi, yer imleri).
    static func undo(_ episode: Episode, context: ModelContext, generator: GenerationCoordinator) async throws {
        try await generator.withEditLock(episode) {
            guard let state = validUndoState(episode) else {
                throw APIError(status: 0, code: "state", message: "Geri alınacak düzenleme kalmadı; bölümün sesi bu arada değişti.")
            }
            let fm = FileManager.default
            let directory = episode.directory
            let target = directory.appending(path: state.audioFileName)
            _ = try fm.replaceItemAt(target, withItemAt: directory.appending(path: undoAudioName))
            // Sahne kopyaları da düzenleme öncesine döner; dönemezse kayıpsız yol bir daha kullanılmaz (m4a ile tutarsız olur).
            if !state.masterBackup || !SceneMasters.restoreUndo(episode.id, scene: state.sceneIndex) {
                SceneMasters.invalidate(episode.id)
            }
            let id = episode.id
            let marks = (try? context.fetch(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.episodeID == id }))) ?? []
            for mark in marks { if let time = state.bookmarks[mark.id.uuidString] { mark.time = time } }
            if let times = state.times {
                for record in timedRecords(id, context: context) { if let time = times[record.key] { record.set(time) } }
            }
            if let refs = state.turnRefs {
                // Düzenlemeden beri değişmediyse önceki hâl; değiştiyse (yeniden alındı) indeksler ters yönde kayar.
                let reverse = remapTurnRefs(figureMap: episode.figureMap, study: episode.study,
                                            oldRange: refs.newRange, newRange: refs.oldRange)
                let map = episode.figureMap
                if map != refs.figureMapAfter { episode.figureMap = reverse.figureMap }
                else if map != refs.figureMapBefore { episode.figureMap = refs.figureMapBefore }
                let study = episode.study
                if study != refs.studyAfter { if reverse.study != study { episode.study = reverse.study } }
                else if study != refs.studyBefore { episode.study = refs.studyBefore }
            }
            episode.scriptData = state.scriptData
            episode.audioFileName = state.audioFileName
            episode.timelineData = state.timelineData
            episode.duration = state.duration
            clearUndo(directory: directory)
            finish(episode, timeline: nil, context: context)
        }
    }

    // MARK: Yardımcılar

    /// Ses değişen her yolun ortak sonu: doğrulama sıfırlanır, sürüm artar, kelime senkronu silinir, olay yayılır.
    private static func finish(_ episode: Episode, timeline: Timeline?, context: ModelContext) {
        if let timeline {
            episode.timeline = timeline
            episode.duration = timeline.duration
        }
        episode.verification = nil
        episode.audioRevision += 1
        WordSync.invalidate(episode.id)
        try? context.save()
        PodcastEvent.post(PodcastEvent.audioChanged, episodeID: episode.id)
    }

    static func replacing(_ script: PodcastScript, sceneIndex: Int, turns: [ScriptTurn]) -> PodcastScript {
        var script = script
        var flat = 0
        for c in script.chapters.indices {
            for s in script.chapters[c].scenes.indices {
                if flat == sceneIndex { script.chapters[c].scenes[s].turns = turns; return script }
                flat += 1
            }
        }
        return script
    }

    /// Bir zamanı düzenleme sonrası zaman çizelgesine taşır: önceki turlarda aynı tur, sonrakilerde kaydırılmış tur
    /// (turdan uzaklık korunur), düzenlenen sahnede sahne içi oran.
    nonisolated static func remap(_ time: Double, old: Timeline, new: Timeline, oldRange: Range<Int>, newRange: Range<Int>) -> Double {
        guard let i = old.turnIndex(at: time), old.turns.indices.contains(i) else { return time }
        let offset = time - old.turns[i].start
        if i < oldRange.lowerBound {
            guard new.turns.indices.contains(i) else { return time }
            return new.turns[i].start + offset
        }
        if i >= oldRange.upperBound {
            let j = i + newRange.count - oldRange.count
            guard new.turns.indices.contains(j) else { return time }
            return new.turns[j].start + offset
        }
        guard newRange.upperBound <= new.turns.count, !newRange.isEmpty else { return time }
        let oldStart = old.turns[oldRange.lowerBound].start, oldEnd = old.turns[oldRange.upperBound - 1].end
        let newStart = new.turns[newRange.lowerBound].start, newEnd = new.turns[newRange.upperBound - 1].end
        let ratio = min(1, max(0, (time - oldStart) / max(oldEnd - oldStart, 0.01)))
        return newStart + ratio * (newEnd - newStart)
    }

    /// Küresel tur indeksi: sahneden öncekiler aynı, sonrakiler tur farkı kadar kayar, sahnenin içindekiler yeni sahnede
    /// aynı orandaki tura gider (4 → 2 tur: 0,1 → 0; 2,3 → 1).
    nonisolated static func remapTurn(_ index: Int, oldRange: Range<Int>, newRange: Range<Int>) -> Int {
        if index < oldRange.lowerBound { return index }
        if index >= oldRange.upperBound { return index + newRange.count - oldRange.count }
        guard !oldRange.isEmpty, !newRange.isEmpty else { return newRange.lowerBound }
        return newRange.lowerBound + (index - oldRange.lowerBound) * newRange.count / oldRange.count
    }

    /// Şekil eşlemesi ve çalışma paketi sorularındaki `turnIndex`'leri kaydırır (bölüm/konu indeksi değişmez).
    nonisolated static func remapTurnRefs(figureMap: [FigureMapEntry]?, study: StudyPack?, oldRange: Range<Int>,
                                          newRange: Range<Int>) -> (figureMap: [FigureMapEntry]?, study: StudyPack?) {
        let map = figureMap?.map { entry -> FigureMapEntry in
            var e = entry
            e.turnIndex = entry.turnIndex.map { remapTurn($0, oldRange: oldRange, newRange: newRange) }
            return e
        }
        var pack = study
        if let quiz = study?.quiz {
            pack?.quiz = quiz.map { item in
                var q = item
                q.turnIndex = item.turnIndex.map { remapTurn($0, oldRange: oldRange, newRange: newRange) }
                return q
            }
        }
        return (map, pack)
    }

    /// Bölüm sesinde an tutan, yer imi dışındaki kayıtlar: tekrar kartı, hata defteri, canlı soru.
    private struct TimedRecord {
        var key: String
        var get: () -> Double?
        var set: (Double) -> Void
    }

    private static func timedRecords(_ id: UUID, context: ModelContext) -> [TimedRecord] {
        let optionalID: UUID? = id
        var records: [TimedRecord] = []
        for card in (try? context.fetch(FetchDescriptor<ReviewCard>(predicate: #Predicate { $0.episodeID == id }))) ?? [] {
            records.append(TimedRecord(key: "card:\(card.id.uuidString)", get: { card.episodeTime }, set: { card.episodeTime = $0 }))
        }
        for entry in (try? context.fetch(FetchDescriptor<MistakeEntry>(predicate: #Predicate { $0.episodeID == optionalID }))) ?? [] {
            records.append(TimedRecord(key: "mistake:\(entry.id.uuidString)", get: { entry.podcastTime }, set: { entry.podcastTime = $0 }))
        }
        for exchange in (try? context.fetch(FetchDescriptor<LiveExchange>(predicate: #Predicate { $0.episodeID == optionalID }))) ?? [] {
            records.append(TimedRecord(key: "live:\(exchange.id.uuidString)", get: { exchange.time }, set: { exchange.time = $0 }))
        }
        return records
    }

    /// Sahnenin bölüm sesindeki aralığı (eski hâlini dinlemek için).
    static func sceneTimeRange(_ episode: Episode, sceneIndex: Int) -> ClosedRange<Double>? {
        guard let script = episode.script, let timeline = episode.timeline,
              let range = AudioEditor.turnRange(ofScene: sceneIndex, script: script),
              !range.isEmpty, range.upperBound <= timeline.turns.count else { return nil }
        let start = timeline.turns[range.lowerBound].start, end = timeline.turns[range.upperBound - 1].end
        return start...max(start, end)
    }

    /// #10: yeniden yazma bölümün kendi tempo, derinlik ve konuğunu, varsa kaynak sayfalarını kullanır.
    static func rewrite(_ episode: Episode, sceneIndex: Int, turns: [ScriptTurn], instruction: String,
                        context: ModelContext) async throws -> [ScriptTurn] {
        guard let script = episode.script, let settings = episode.settings,
              let item = script.flatScenes[safeScene: sceneIndex] else { throw stateError }
        let flat = script.flatScenes
        let before = flat[safeScene: sceneIndex - 1]?.scene.turns.map(\.text).joined(separator: " ")
        let after = flat[safeScene: sceneIndex + 1]?.scene.turns.map(\.text).joined(separator: " ")
        let chapter = script.chapters.indices.contains(item.chapterIndex) ? script.chapters[item.chapterIndex] : nil
        let pageNumbers = Array(Set((chapter?.sourcePages ?? []) + turns.compactMap(\.sourcePage))).sorted()
        let pages = pageNumbers.isEmpty ? [] : await SourcePages.texts(for: episode, pages: pageNumbers, maxChars: 12_000, context: context)
        return try await APIClient.shared.rewriteScene(RewriteSceneRequest(
            title: script.title, sourceNotes: String(script.sourceNotes.prefix(15_000)),
            chapterTitle: chapter?.title ?? "",
            before: before.map { String($0.prefix(2000)) }, after: after.map { String($0.prefix(2000)) },
            scene: ScriptScene(turns: turns), instruction: String(instruction.prefix(300)),
            settings: RewriteSettings(level: settings.level, tone: settings.tone, format: settings.format,
                                      language: settings.language, hostA: settings.hostA, hostB: settings.hostB,
                                      pace: settings.pace, depth: settings.depth, guest: settings.guest),
            pages: pages.isEmpty ? nil : Array(pages.prefix(40))))
    }

    private static var stateError: APIError { APIError(status: 0, code: "state", message: "Bölüm hazır değil.") }
}

nonisolated extension Array {
    /// Sahne stüdyosu için güvenli indeks (başka parçaların yardımcılarına bağlanmamak için ayrı ad).
    subscript(safeScene index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
