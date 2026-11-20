import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import Ikra

// Ses/model alanı iyileştirmeleri: blob önbelleği, cihaz ses listesi, tekil kelime senkronu, yarıda kesilen sahne
// değişimi, boşta model bırakma, sesli okuma aç/kapa.

private func tone(_ seconds: Double, sampleRate: Int = 24_000) -> [Int16] {
    (0..<Int(seconds * Double(sampleRate))).map { Int16(9000 * sin(2 * .pi * 220 * Double($0) / Double(sampleRate))) }
}

private func tempDir() throws -> URL {
    let dir = URL.temporaryDirectory.appending(path: "ses-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func writeWAV(_ seconds: Double, _ url: URL) throws -> URL {
    try WAV.encode(PCMClip(samples: tone(seconds), sampleRate: 24_000)).write(to: url)
    return url
}

private func wavSeconds(_ url: URL) throws -> Double { try WAV.parse(Data(contentsOf: url)).duration }

private func script(_ title: String) -> PodcastScript {
    PodcastScript(title: title, summary: "", keyPoints: [], chapters: [
        ScriptChapter(title: "Bir", scenes: [ScriptScene(turns: [ScriptTurn(speaker: .a, text: "Merhaba", style: "", sourcePage: nil)])]),
    ], sourceNotes: "")
}

private func figure(_ id: String, caption: String = "Şekil") -> SourceFigure {
    SourceFigure(id: id, kind: "figure", caption: caption, page: 1, documentName: "Kitap")
}

/// Koşul sağlanana kadar (en çok `seconds`) kısa aralıklarla bekler.
@MainActor
private func eventually(seconds: Double = 5, _ condition: () async -> Bool) async -> Bool {
    let deadline = Date.now.addingTimeInterval(seconds)
    while Date.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}

nonisolated private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var flags: [Bool] = []
    var value: Int { lock.withLock { count } }
    var cancelledFlags: [Bool] { lock.withLock { flags } }
    @discardableResult func increment() -> Int { lock.withLock { count += 1; return count } }
    func note(cancelled: Bool) { lock.withLock { flags.append(cancelled) } }
}

extension NeuralSpeechRenderer {
    /// Sayacı kurup hemen iptal eder. Tek aktör adımı: iki çağrının arasına ana aktörün gecikmesi (ve sürenin
    /// dolması) giremez.
    fileprivate func scheduleThenCancelIdleUnload() {
        scheduleIdleUnload()
        cancelIdleUnload()
    }
}

@MainActor
@Suite(.serialized)
struct ImproveSesTests {
    // MARK: Madde 1 — blob önbelleği

    @Test func scriptIsDecodedOncePerDataAndFollowsDirectWrites() throws {
        let episode = Episode(script: script("Bir"), settings: PodcastSettings(), sourceNames: [], jobToken: "")
        let cache = EpisodeBlobCache.shared
        let id = episode.id
        #expect(episode.script?.title == "Bir")
        #expect(episode.script?.title == "Bir")
        #expect(cache.decodeCount(for: id, "script") == 1)
        #expect(episode.settings == PodcastSettings())
        #expect(episode.canResume)
        #expect(cache.decodeCount(for: id, "script") == 1 && cache.decodeCount(for: id, "settings") == 1)
        // Blob doğrudan değişince (sahne düzenleme, geri alma) eski değer dönmez.
        episode.scriptData = try JSONEncoder().encode(script("İki"))
        #expect(episode.script?.title == "İki")
        #expect(episode.script?.title == "İki")
        #expect(cache.decodeCount(for: id, "script") == 2)
        // Bölüm silinince kayıtları da gider.
        EpisodeFiles.remove(episode: id)
        #expect(cache.decodeCount(for: id, "script") == 0)
        #expect(episode.script?.title == "İki")
    }

    @Test func settersPrimeTheCacheAndKeepTheStoredForm() throws {
        let episode = Episode(script: script("T"), settings: PodcastSettings(), sourceNames: [], jobToken: "")
        let cache = EpisodeBlobCache.shared
        let id = episode.id
        let timeline = Timeline(chapters: [TimedChapter(id: 0, title: "Bir", start: 0)],
                                turns: [TimedTurn(id: 0, chapterIndex: 0, speaker: .a, text: "Merhaba", sourcePage: 3, start: 0.1, end: 2.35)],
                                duration: 2.35, thinkPauses: [ThinkPause(turnID: 0, start: 1, end: 1.5)], sceneStarts: [0])
        episode.timeline = timeline
        #expect(episode.timeline == timeline)
        #expect(cache.decodeCount(for: id, "timeline") == 0)
        // Saklanan Data eskisi gibi çözülebilir biçimde (şema ve yedek aynı blobu görür).
        let stored = try #require(episode.timelineData)
        #expect(try JSONDecoder().decode(Timeline.self, from: stored) == timeline)
        episode.timeline = nil
        #expect(episode.timelineData == nil && episode.timeline == nil)

        let issues = [AudioIssue(scene: 2, reasons: ["kısa"])]
        episode.audioIssues = issues
        #expect(episode.audioIssues == issues && episode.audioIssuesData != nil)
        episode.audioIssues = []
        #expect(episode.audioIssues.isEmpty && episode.audioIssuesData == nil)
        episode.topics = [TopicTag(subject: "Biyoloji", unit: "Hücre", topic: "Zar", chapterIndex: 0)]
        #expect(episode.topics.map(\.topic) == ["Zar"])
        #expect(cache.decodeCount(for: id, "audioIssues") == 0 && cache.decodeCount(for: id, "topics") == 0)

        // Konu haritası: kendi blobu yoksa çalışma paketindeki kavramlar.
        let concept = Concept(name: "Osmoz", definition: "Suyun geçişi", related: [], sourcePage: nil)
        episode.study = StudyPack(quiz: [], flashcards: [], concepts: [concept])
        #expect(episode.concepts == [concept])
        let own = Concept(name: "Difüzyon", definition: "Yayılma", related: ["Osmoz"], sourcePage: 4)
        episode.concepts = [own]
        #expect(episode.concepts == [own])
        #expect(cache.decodeCount(for: id, "study") == 0 && cache.decodeCount(for: id, "concepts") == 0)
        // Aynı baytlar başka bir Data olarak geri yazılırsa (içerik karşılaştırılır) yine çözülmez; farklı bayt bir kez çözülür.
        episode.studyData = episode.studyData.map { Data(Array($0)) }
        #expect(episode.study?.concepts == [concept] && cache.decodeCount(for: id, "study") == 0)
        episode.studyData = try JSONEncoder().encode(StudyPack(quiz: [], flashcards: [Flashcard(front: "Ön", back: "Arka")]))
        #expect(episode.study?.flashcards.count == 1 && episode.study?.concepts == nil)
        #expect(cache.decodeCount(for: id, "study") == 1)
        EpisodeBlobCache.shared.remove(id)
    }

    @Test func corruptBlobIsTriedOnce() {
        let episode = Episode(script: script("T"), settings: PodcastSettings(), sourceNames: [], jobToken: "")
        let cache = EpisodeBlobCache.shared
        episode.studyData = Data("bozuk".utf8)
        #expect(episode.study == nil)
        #expect(episode.study == nil)
        #expect(cache.decodeCount(for: episode.id, "study") == 1)
        #expect(episode.concepts.isEmpty)
        EpisodeBlobCache.shared.remove(episode.id)
    }

    @Test func cacheIsBoundedByCountAndBytesAndDropsTheLeastRecentlyUsed() throws {
        let data = try JSONEncoder().encode(script("Sınır"))
        let cache = EpisodeBlobCache(limit: 8)
        let ids = (0..<200).map { _ in UUID() }
        for id in ids {
            let value: PodcastScript? = cache.value(id, "script", data)
            #expect(value?.title == "Sınır")
            // İlk bölüm her adımda yeniden okunur: en son kullanılanlar arasında kalır.
            let first: PodcastScript? = cache.value(ids[0], "script", data)
            #expect(first != nil)
        }
        #expect(cache.count <= 8)
        #expect(cache.decodeCount == 200)                       // ilk bölüm hiç düşmedi
        let evicted: PodcastScript? = cache.value(ids[1], "script", data)
        #expect(evicted != nil && cache.decodeCount == 201)     // eskiler düştü
        cache.remove(ids[0])
        let again: PodcastScript? = cache.value(ids[0], "script", data)
        #expect(again != nil && cache.decodeCount == 202)

        let small = EpisodeBlobCache(limit: 100, byteLimit: data.count * 3)
        for id in ids.prefix(20) {
            let value: PodcastScript? = small.value(id, "script", data)
            #expect(value != nil)
        }
        #expect(small.count == 3)
        // Tek başına sınırı aşan blob da saklanır (her okumada yeniden çözülmez).
        let tiny = EpisodeBlobCache(limit: 100, byteLimit: 1)
        let a: PodcastScript? = tiny.value(ids[0], "script", data)
        let b: PodcastScript? = tiny.value(ids[0], "script", data)
        #expect(a != nil && b != nil && tiny.count == 1 && tiny.decodeCount == 1)
        // Aynı anahtarda başka tür istenirse yanlış değer dönmez; doğru tür sonra yine çözülür.
        let wrong: [Concept]? = tiny.value(ids[0], "script", data)
        let right: PodcastScript? = tiny.value(ids[0], "script", data)
        #expect(wrong == nil && right?.title == "Sınır")
    }

    @Test func figureListFollowsTheFileStamp() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let url = EpisodeFiles.figuresURL(for: id, root: root)
        let cache = EpisodeBlobCache()
        // Dosya yok: okumadan boş; klasör oluşturulmaz.
        #expect(cache.figures(id, at: url).isEmpty)
        #expect(cache.fileReadCount == 0)
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode([figure("a")]).write(to: url, options: .atomic)
        #expect(cache.figures(id, at: url) == [figure("a")])
        #expect(cache.figures(id, at: url) == [figure("a")])
        #expect(cache.fileReadCount == 1)
        // Dışarıdan değişti (yedekten geri yükleme): yeni içerik.
        try JSONEncoder().encode([figure("a"), figure("b", caption: "Tablo")]).write(to: url, options: .atomic)
        #expect(cache.figures(id, at: url).map(\.id) == ["a", "b"])
        #expect(cache.fileReadCount == 2)
        // Yazan taraf listeyi verirse dosya yeniden açılmaz.
        try JSONEncoder().encode([figure("c")]).write(to: url, options: .atomic)
        cache.storeFigures(id, [figure("c")], at: url)
        #expect(cache.figures(id, at: url) == [figure("c")])
        #expect(cache.fileReadCount == 2)
        // Bozuk dosya boş liste; her okumada yeniden denenmez.
        try Data("bozuk dosya içeriği".utf8).write(to: url, options: .atomic)
        #expect(cache.figures(id, at: url).isEmpty && cache.figures(id, at: url).isEmpty)
        #expect(cache.fileReadCount == 3)
        try FileManager.default.removeItem(at: url)
        #expect(cache.figures(id, at: url).isEmpty)
        #expect(cache.figureListCount == 0)
    }

    @Test func episodeFiguresRoundTripWithoutCreatingTheFolderOnRead() throws {
        let episode = Episode(script: script("T"), settings: PodcastSettings(), sourceNames: [], jobToken: "")
        let id = episode.id
        defer { EpisodeFiles.remove(episode: id) }
        let url = EpisodeFiles.figuresURL(for: id)
        #expect(episode.sourceFigures.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        episode.sourceFigures = [figure("a")]
        #expect(episode.sourceFigures == [figure("a")])
        #expect(try JSONDecoder().decode([SourceFigure].self, from: Data(contentsOf: url)) == [figure("a")])
        #expect(url.path == episode.directory.appending(path: "figures.json").path)
        try JSONEncoder().encode([figure("a"), figure("b")]).write(to: url, options: .atomic)
        #expect(episode.sourceFigures.map(\.id) == ["a", "b"])
        episode.sourceFigures = []
        #expect(episode.sourceFigures.isEmpty && FileManager.default.fileExists(atPath: url.path))
        try FileManager.default.removeItem(at: url)
        #expect(episode.sourceFigures.isEmpty)
    }

    // MARK: Madde 2 — cihaz ses listesi

    @Test func deviceVoiceListIsLoadedOnceUntilItChanges() async {
        let original = SpeechVoiceCatalog.loader
        var calls = 0
        SpeechVoiceCatalog.loader = {
            calls += 1
            return original()
        }
        SpeechVoiceCatalog.invalidate()
        defer {
            SpeechVoiceCatalog.loader = original
            SpeechVoiceCatalog.invalidate()
        }
        let ranked = DeviceSpeech.voices()
        _ = DeviceSpeech.qualityDescription(speaker: .a)
        _ = DeviceSpeech.qualityDescription(speaker: .b)
        let best = SpeechOut.bestVoice(for: "tr-TR")
        _ = DeviceSpeech.voices(language: "en-US")
        #expect(calls == 1)
        // Sıra ve seçim eskisiyle aynı.
        let turkish = original().filter { $0.language == "tr-TR" }
        let expected = turkish.sorted {
            $0.quality.rawValue == $1.quality.rawValue ? $0.identifier < $1.identifier : $0.quality.rawValue > $1.quality.rawValue
        }
        #expect(ranked.map(\.identifier) == expected.map(\.identifier))
        let expectedBest = turkish.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "tr-TR")
        #expect(best?.identifier == expectedBest?.identifier)

        SpeechVoiceCatalog.invalidate()
        _ = DeviceSpeech.voices()
        _ = DeviceSpeech.voices()
        #expect(calls == 2)
        // Sistem "sesler değişti" deyince (kullanıcı ses indirdi) bir sonraki soruda yeniden okunur.
        NotificationCenter.default.post(name: AVSpeechSynthesizer.availableVoicesDidChangeNotification, object: nil)
        let reloaded = await eventually(seconds: 2) {
            _ = DeviceSpeech.voices()
            return calls == 3
        }
        #expect(reloaded)
    }

    // MARK: Madde 3 — tekil iş

    @Test func inFlightSharesOneRunPerKey() async {
        let flight = InFlight<String, Int>()
        let counter = LockedCounter()
        let gate = OnceValue<Int>()
        let work: @Sendable () async -> Int = {
            counter.increment()
            return await gate.wait()
        }
        let a = Task { await flight.run("k", work) }
        #expect(await eventually { flight.waiters(for: "k") == 1 })
        let b = Task { await flight.run("k", work) }
        #expect(await eventually { flight.waiters(for: "k") == 2 })
        // Başka anahtar ayrı iş.
        let c = Task { await flight.run("başka", work) }
        #expect(await eventually { counter.value == 2 })
        gate.resolve(7)
        let (x, y, z) = (await a.value, await b.value, await c.value)
        #expect(x == 7 && y == 7 && z == 7)
        #expect(counter.value == 2)
        // İş bitince kayıt silinir: aynı anahtar yeniden çalışır.
        #expect(flight.waiters(for: "k") == 0)
        #expect(await flight.run("k", work) == 7)
        #expect(counter.value == 3)
    }

    @Test func inFlightCancelsTheWorkOnlyWhenEveryWaiterLeft() async {
        let flight = InFlight<String, Int>()
        let counter = LockedCounter()
        let gate = OnceValue<Int>()
        let a = Task {
            await flight.run("k") {
                counter.increment()
                let value = await gate.wait()
                counter.note(cancelled: Task.isCancelled)
                return value
            }
        }
        #expect(await eventually { flight.waiters(for: "k") == 1 })
        let b = Task { await flight.run("k") { -1 } }
        #expect(await eventually { flight.waiters(for: "k") == 2 })
        // Bekleyenlerden biri vazgeçti: iş sürer ve tamamlanır.
        a.cancel()
        #expect(await eventually { flight.waiters(for: "k") == 1 })
        gate.resolve(5)
        #expect(await a.value == 5)
        #expect(await b.value == 5)
        #expect(counter.value == 1 && counter.cancelledFlags == [false])

        // İkisi de vazgeçti: iş iptal edilir; iptal edilen iş kapanırken gelen yeni çağrı ona katılmaz.
        let stop = OnceValue<Int>()
        let work: @Sendable () async -> Int = {
            counter.increment()
            let deadline = Date.now.addingTimeInterval(5)
            while !Task.isCancelled, Date.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
            counter.note(cancelled: Task.isCancelled)
            return await stop.wait()
        }
        let c = Task { await flight.run("iptal", work) }
        #expect(await eventually { flight.waiters(for: "iptal") == 1 })
        let d = Task { await flight.run("iptal", work) }
        #expect(await eventually { flight.waiters(for: "iptal") == 2 })
        c.cancel()
        d.cancel()
        #expect(await eventually { counter.cancelledFlags == [false, true] })
        #expect(flight.waiters(for: "iptal") == 0)
        let fresh = Task { await flight.run("iptal") { 9 } }
        #expect(await fresh.value == 9)
        stop.resolve(0)
        #expect(await c.value == 0)
        #expect(await d.value == 0)
    }

    /// İnceleme bulgusu: iptal edilen bekleyen, iş başkası için sürerken askıda kalıyordu (kapanan görünüm bölümü
    /// "hazırlanıyor" sayılı bırakıyor, yeniden açılan görünüm zamanları almıyordu).
    @Test func inFlightReleasesACancelledWaiterWhileTheWorkGoesOnForTheOthers() async {
        let flight = InFlight<String, Int>()
        let counter = LockedCounter()
        let gate = OnceValue<Int>()
        let work: @Sendable () async -> Int = {
            counter.increment()
            let value = await gate.wait()
            counter.note(cancelled: Task.isCancelled)
            return value
        }
        // Hiç iptal edilmeyen bekleyen (üretim bitişi) ve bölümü açan görünüm.
        let keeper = Task { await flight.run("k", ifCancelled: -1, work) }
        #expect(await eventually { flight.waiters(for: "k") == 1 })
        let left = OnceValue<Int>()
        let view = Task { left.resolve(await flight.run("k", ifCancelled: -1, work)) }
        #expect(await eventually { flight.waiters(for: "k") == 2 })
        // Görünüm kapandı: iş bitmeden (kapı kapalıyken) döner; iş öteki bekleyen için sürer.
        view.cancel()
        #expect(await eventually { left.isResolved })
        #expect(!gate.isResolved && flight.waiters(for: "k") == 1)
        // Yeniden açılan görünüm süren işe katılır ve sonucunu alır; iş bir kez çalışır, iptal görmez.
        let reopened = Task { await flight.run("k", ifCancelled: -1, work) }
        #expect(await eventually { flight.waiters(for: "k") == 2 })
        gate.resolve(5)
        #expect(await keeper.value == 5)
        #expect(await reopened.value == 5)
        #expect(await left.wait() == -1)
        #expect(counter.value == 1 && counter.cancelledFlags == [false])

        // Tek bekleyen iptal edilirse iş iptal edilir; bekleyen işin kapanmasını da beklemez.
        let closing = OnceValue<Int>()
        let alone = OnceValue<Int>()
        let lone = Task {
            alone.resolve(await flight.run("tek", ifCancelled: -1) {
                let deadline = Date.now.addingTimeInterval(5)
                while !Task.isCancelled, Date.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
                counter.note(cancelled: Task.isCancelled)
                return await closing.wait()
            })
        }
        #expect(await eventually { flight.waiters(for: "tek") == 1 })
        lone.cancel()
        #expect(await eventually { alone.isResolved })
        #expect(await eventually { counter.cancelledFlags == [false, true] })
        #expect(!closing.isResolved && flight.waiters(for: "tek") == 0)
        closing.resolve(0)
        #expect(await alone.wait() == -1)
    }

    @Test func wordSyncFlightKeyFollowsTheAudioFile() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        let audio = dir.appending(path: "podcast.m4a")
        // Ses okunamıyorsa yalnız bölüm.
        #expect(WordSync.flightKey(episodeID: id, audioURL: audio) == id.uuidString)
        try Data(repeating: 1, count: 10).write(to: audio)
        let first = WordSync.flightKey(episodeID: id, audioURL: audio)
        #expect(first.hasPrefix(id.uuidString + "|podcast.m4a|10|"))
        #expect(WordSync.flightKey(episodeID: id, audioURL: audio) == first)
        #expect(WordSync.flightKey(episodeID: UUID(), audioURL: audio) != first)
        // Ses değişti: eski sese ait işe katılınmaz.
        try Data(repeating: 2, count: 11).write(to: audio)
        #expect(WordSync.flightKey(episodeID: id, audioURL: audio) != first)
    }

    // MARK: Madde 4 — yarıda kesilen sahne değişimi

    @Test func interruptedReplaceIsRolledBackButALiveOneIsLeftAlone() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "masters")
        let id = UUID()
        let fm = FileManager.default
        let urls = try [1.0, 2.0, 1.5].enumerated().map { try writeWAV($1, dir.appending(path: "s\($0).wav")) }
        try SceneMasters.store(episodeID: id, scenes: urls, root: root)
        let folder = SceneMasters.directory(id, root: root)
        let pending = folder.appending(path: SceneMasters.pendingName)
        let info = folder.appending(path: SceneMasters.pendingInfoName)
        let undo = folder.appending(path: SceneMasters.undoName)
        func seconds(_ scene: Int) throws -> Double { try wavSeconds(SceneMasters.url(id, scene: scene, root: root)) }

        // Önceki başarılı düzenleme: geri alma kopyası (sahne 0'ın 1 sn'lik özgün hâli) ve yan dosya kalmaz.
        try SceneMasters.replace(id, scene: 0, with: try writeWAV(4, dir.appending(path: "e0.wav")), root: root)
        #expect(fm.fileExists(atPath: info.path))
        SceneMasters.commitReplace(id, root: root)
        #expect(fm.fileExists(atPath: undo.path) && !fm.fileExists(atPath: pending.path) && !fm.fileExists(atPath: info.path))

        // Yeniden birleştirme sürerken (aynı süreç) sorulursa değişime dokunulmaz.
        try SceneMasters.replace(id, scene: 1, with: try writeWAV(5, dir.appending(path: "e1.wav")), root: root)
        #expect(SceneMasters.isComplete(id, scenes: 3, root: root))
        #expect(abs(try seconds(1) - 5) < 0.01)
        #expect(fm.fileExists(atPath: pending.path) && fm.fileExists(atPath: info.path))
        #expect(!SceneMasters.recoverInterrupted(id, root: root))

        // Uygulama o sırada sonlandı: açılışta sahne eski hâline döner, önceki geri alma kopyası yerinde kalır.
        SceneMasters.simulateRelaunch(id, root: root)
        #expect(SceneMasters.isComplete(id, scenes: 3, root: root))
        #expect(abs(try seconds(1) - 2) < 0.01)
        #expect(abs(try seconds(0) - 4) < 0.01)
        #expect(!fm.fileExists(atPath: pending.path) && !fm.fileExists(atPath: info.path))
        #expect(abs(try wavSeconds(undo) - 1) < 0.01)
        #expect(!SceneMasters.recoverInterrupted(id, root: root))

        // Geri alınan değişim ve tek başına kalan yan dosya iz bırakmaz.
        try SceneMasters.replace(id, scene: 2, with: try writeWAV(3, dir.appending(path: "e2.wav")), root: root)
        SceneMasters.rollbackReplace(id, scene: 2, root: root)
        #expect(abs(try seconds(2) - 1.5) < 0.01 && !fm.fileExists(atPath: info.path))
        try Data(#"{"scene":2}"#.utf8).write(to: info)
        #expect(SceneMasters.isComplete(id, scenes: 3, root: root))
        #expect(!fm.fileExists(atPath: info.path))
        #expect(abs(try seconds(2) - 1.5) < 0.01)
    }

    @Test func pendingSceneWithoutItsIndexInvalidatesTheMasters() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "masters")
        let id = UUID()
        let urls = try [1.0, 2.0].enumerated().map { try writeWAV($1, dir.appending(path: "s\($0).wav")) }
        try SceneMasters.store(episodeID: id, scenes: urls, root: root)
        let folder = SceneMasters.directory(id, root: root)
        // Eski sürümden kalan bekleyen dosya: hangi sahne olduğu bilinmez, kopyalara güvenilmez.
        try FileManager.default.copyItem(at: urls[0], to: folder.appending(path: SceneMasters.pendingName))
        #expect(!SceneMasters.isComplete(id, scenes: 2, root: root))
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        // Kopyalar yokken değişim hata verir (çağıran m4a yoluna düşer) ve süren değişim kaydı kalmaz.
        #expect(throws: (any Error).self) { try SceneMasters.replace(id, scene: 0, with: urls[1], root: root) }
        #expect(!SceneMasters.recoverInterrupted(id, root: root))
    }

    @Test func undoAfterAnInterruptedSecondEditOfTheSameSceneRestoresTheOriginal() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "masters")
        let id = UUID()
        let urls = try [1.0, 2.0].enumerated().map { try writeWAV($1, dir.appending(path: "s\($0).wav")) }
        try SceneMasters.store(episodeID: id, scenes: urls, root: root)
        func seconds(_ scene: Int) throws -> Double { try wavSeconds(SceneMasters.url(id, scene: scene, root: root)) }
        try SceneMasters.replace(id, scene: 1, with: try writeWAV(3, dir.appending(path: "first.wav")), root: root)
        SceneMasters.commitReplace(id, root: root)
        try SceneMasters.replace(id, scene: 1, with: try writeWAV(4, dir.appending(path: "second.wav")), root: root)
        SceneMasters.simulateRelaunch(id, root: root)
        // Geri al: önce yarım değişim (4 sn → 3 sn), sonra ilk düzenlemenin kopyası (3 sn → özgün 2 sn).
        #expect(SceneMasters.restoreUndo(id, scene: 1, root: root))
        #expect(abs(try seconds(1) - 2) < 0.01)
        #expect(SceneMasters.isComplete(id, scenes: 2, root: root))
        #expect(abs(try seconds(1) - 2) < 0.01)
        #expect(!FileManager.default.fileExists(atPath: SceneMasters.directory(id, root: root).appending(path: SceneMasters.pendingName).path))
    }

    // MARK: Madde 5 — boşta model bırakma

    #if DEBUG
    // Sayaç 0,05 sn ve ana aktör bundan uzun oyalanabilir: kurma ile sonraki adım arasında "hâlâ yüklü" beklentisi
    // yok, kurma + iptal tek aktör adımında; geri kalan beklemeler yalnız üst sınır.
    @Test func residentModelIsReleasedWhenIdleUnlessTheTimerIsCancelled() async {
        let renderer = NeuralSpeechRenderer(idleSeconds: 0.05)
        var resident = await renderer.isResident
        #expect(!resident)
        await renderer.scheduleIdleUnload()          // yüklü model yokken sayaç kurulmaz
        await renderer.markResidentForTesting()
        await renderer.scheduleIdleUnload()
        #expect(await eventually(seconds: 5) { await !renderer.isResident })

        // `cancelIdleUnload` kurulan sayacı iptal eder: süre dolsa da bırakılmaz.
        await renderer.markResidentForTesting()
        await renderer.scheduleThenCancelIdleUnload()
        try? await Task.sleep(for: .milliseconds(300))
        resident = await renderer.isResident
        #expect(resident)
        // Bellek uyarısı yolu: boştaysa hemen.
        await renderer.unloadIfIdle()
        resident = await renderer.isResident
        #expect(!resident)
    }

    /// `scene()` bağlantısı: sahne bitince (hata verse de) sayaç kurulur; burada elle `scheduleIdleUnload` çağrılmaz.
    /// Girişteki iptal ayrıca sınanmıyor: gözlenebilir etkisi yok (sahne sürerken `unloadIfIdle` zaten bırakmaz).
    @Test func sceneArmsTheIdleTimerWhenItEnds() async {
        let renderer = NeuralSpeechRenderer(idleSeconds: 0.05)
        await renderer.markResidentForTesting()
        // Cihaz motoru olmayan ayar: model dosyasına bakılmadan hata verir.
        let settings = PodcastSettings(speechProvider: SpeechEngine.apple.rawValue)
        await #expect(throws: OfflineSpeechError.self) { _ = try await renderer.scene(turns: [], settings: settings) }
        #expect(await eventually(seconds: 5) { await !renderer.isResident })
    }
    #endif

    // MARK: Madde 6 — sesli okuma

    @Test(.timeLimit(.minutes(1))) func speakingTogglesOnTheSameTextSkipsEmptyTextAndStopsOnCancel() async {
        let out = SpeechOut()
        defer { out.stop() }
        await out.speak("")
        await out.speak("  \n ")
        #expect(!out.isSpeaking)

        let long = String(repeating: "Hücre canlıların temel yapı birimidir. ", count: 40)
        let first = Task { await out.speak(long) }
        #expect(await eventually { out.isSpeaking })
        // Aynı metinle ikinci istek ("Sesli oku"ya yeniden dokunma): susar ve hemen döner; ilk çağrı da döner.
        await out.speak(long)
        #expect(!out.isSpeaking)
        await first.value

        // Görev iptali (görünüm kapandı): okuma susar.
        let second = Task { await out.speak(long) }
        #expect(await eventually { out.isSpeaking })
        second.cancel()
        await second.value
        #expect(!out.isSpeaking)

        // İptal edilmiş görev yeni okuma başlatmaz; başka metin öncekini kesip okur.
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await out.speak(long)
        }
        await cancelled.value
        #expect(!out.isSpeaking)
        let third = Task { await out.speak(long) }
        #expect(await eventually { out.isSpeaking && out.spokenText == long })
        let other = Task { await out.speak("Kısa bir cümle daha.") }
        #expect(await eventually { out.spokenText == "Kısa bir cümle daha." })
        await third.value
        out.stop()
        await other.value
        #expect(!out.isSpeaking)
    }

    // MARK: Madde 8 — kayıt sürerken kapanan tanıma görevi

    @Test func textOfARestartedTaskContinuesAfterTheCommittedText() {
        #expect(SpeechCaptureIO.join("", "a") == "a")
        #expect(SpeechCaptureIO.join("Merhaba.", "nasılsın") == "Merhaba. nasılsın")
        #expect(SpeechCaptureIO.join("abc", "abc def") == "abc def")
        #expect(SpeechCaptureIO.join("abc", "") == "abc")   // yeni görev henüz sonuç vermedi: metin geri gitmez
        #expect(SpeechCaptureIO.join("", "") == "")
        #expect(SpeechCaptureIO.join("Merhaba. ", "nasılsın") == "Merhaba. nasılsın")   // çift boşluk olmaz
    }

    @Test func endedTaskIsRestartedUnlessNothingWasHeardOrTheLimitIsReached() {
        // Hiç metin gelmeden hata (ör. cihazda Dikte kapalı): yeniden denenmez, kullanıcıya bildirilir.
        #expect(!SpeechCaptureIO.shouldRestart(hadError: true, text: "", restarts: 0))
        #expect(!SpeechCaptureIO.shouldRestart(hadError: true, text: " \n", restarts: 0))
        // Metin varken hata ya da son sonuç: tanıma yeni görevle sürer.
        #expect(SpeechCaptureIO.shouldRestart(hadError: true, text: "Merhaba.", restarts: 0))
        #expect(SpeechCaptureIO.shouldRestart(hadError: false, text: "Merhaba.", restarts: 3))
        #expect(SpeechCaptureIO.shouldRestart(hadError: false, text: "", restarts: 0))   // sessizlikte kesinleşme
        #expect(SpeechCaptureIO.shouldRestart(hadError: false, text: "Merhaba.", restarts: SpeechCaptureIO.maxRestarts - 1))
        #expect(!SpeechCaptureIO.shouldRestart(hadError: false, text: "Merhaba.", restarts: SpeechCaptureIO.maxRestarts))
        #expect(!SpeechCaptureIO.shouldRestart(hadError: true, text: "Merhaba.", restarts: SpeechCaptureIO.maxRestarts))
    }

    @Test func restartWaitsOutTheMinimumInterval() {
        #expect(SpeechCaptureIO.restartDelay(elapsed: 30) == 0)   // olağan durum: hemen kurulur
        #expect(SpeechCaptureIO.restartDelay(elapsed: 1) == 0)
        #expect(abs(SpeechCaptureIO.restartDelay(elapsed: 0.25) - 0.75) < 1e-9)
        #expect(SpeechCaptureIO.restartDelay(elapsed: 0) == SpeechCaptureIO.minRestartInterval)
        #expect(SpeechCaptureIO.restartDelay(elapsed: -5) == SpeechCaptureIO.minRestartInterval)   // saat geri gitse de sınırlı
    }

    @Test func cancelWithoutARecordingIsHarmless() async {
        let recorder = SpeechRecorder()
        recorder.cancel()
        recorder.cancel()
        #expect(!recorder.isRecording && !recorder.isStopping && recorder.error == nil && recorder.transcript.isEmpty)
        #expect(await recorder.stop().isEmpty)
    }

    #if DEBUG
    /// İnceleme bulgusu: "Konuşma tanıma durdu" iletisi kayıt bittikten sonra da (bir sonraki kayda kadar) duruyordu.
    @Test func recognitionStoppedMessageEndsWithTheRecordingButStartErrorsStay() async {
        let recorder = SpeechRecorder()
        recorder.setErrorForTesting(SpeechRecorder.recognitionStoppedMessage)
        recorder.cancel()
        #expect(recorder.error == nil)
        recorder.setErrorForTesting(SpeechRecorder.recognitionStoppedMessage)
        await recorder.stop()
        #expect(recorder.error == nil)
        // Başlangıç hataları (izin yok gibi kalıcı durumlar) bir sonraki `start`a kadar kalır.
        let denied = "Mikrofon izni verilmedi."
        recorder.setErrorForTesting(denied)
        recorder.cancel()
        await recorder.stop()
        #expect(recorder.error == denied)
    }
    #endif
}
