import Foundation
import SwiftData
import Testing
@testable import Ikra

/// P3: üretim, kuyruk, arka plan, bildirimler, tanı.
@MainActor
struct PodcastGenerationTests {
    private func script(chapters: [[Int]]) -> PodcastScript {
        // chapters[c][s] = sahnedeki tur sayısı
        PodcastScript(title: "Hücre", summary: "Özet", keyPoints: ["Zar"],
                      chapters: chapters.enumerated().map { ci, scenes in
                          ScriptChapter(title: "Konu \(ci + 1)", scenes: scenes.enumerated().map { si, count in
                              ScriptScene(turns: (0..<count).map { ti in
                                  ScriptTurn(speaker: ti % 2 == 0 ? .a : .b, text: "c\(ci)s\(si)t\(ti)", style: "")
                              })
                          })
                      },
                      sourceNotes: "Notlar")
    }

    // MARK: - #1 yönergeler ve seri

    @Test func effectiveWritesDirectivesAndKeepsUserInstruction() {
        var s = PodcastSettings()
        s.customInstructions = "Formülleri adım adım açıkla."
        s.language = .en
        let e = NewPodcastView.effective(s, compare: true, sourceNames: ["A", "B"], narrateFigures: true, bilingual: true, schoolExam: false)
        #expect(e.customInstructions == "Formülleri adım adım açıkla.")
        #expect(e.directives.count == 3)
        #expect(e.directives[0].hasPrefix("KAYNAK KARŞILAŞTIRMASI"))
        #expect(e.format == .tartisma)
        // İki kez uygulamak çoğaltmaz.
        #expect(NewPodcastView.effective(e, compare: true, sourceNames: ["A", "B"], narrateFigures: true, bilingual: true, schoolExam: false).directives.count == 3)
    }

    @Test func serverSettingsKeepUserInstructionSeparateOnPodcast2() {
        var s = NewPodcastView.effective(PodcastSettings(), compare: false, sourceNames: ["A"], narrateFigures: true, bilingual: false, schoolExam: false)
        s.customInstructions = String(repeating: "a", count: 480)
        s = NewPodcastView.seriesSettings(s, seriesID: UUID(), name: "Biyoloji", index: 2, total: 4,
                                          previousTitles: ["Hücre"], previousKeyPoints: ["Zar seçici geçirgendir"])
        let server = ServerSettings.prepare(s, podcast2: true)
        #expect(server.customInstructions?.count == 480)
        #expect(server.directives.count == 1)
        #expect(server.series?.index == 2)
    }

    @Test func oldServerMergesAndClipsTo500() {
        var s = NewPodcastView.effective(PodcastSettings(), compare: true, sourceNames: ["A", "B"], narrateFigures: true, bilingual: false, schoolExam: false)
        s.customInstructions = "Kısa tut."
        s = NewPodcastView.seriesSettings(s, seriesID: UUID(), name: "Seri", index: 1, total: 3, previousTitles: [], previousKeyPoints: [])
        let server = ServerSettings.prepare(s, podcast2: false)
        let merged = server.customInstructions ?? ""
        #expect(merged.count <= 500)
        #expect(merged.hasPrefix("Kısa tut."))
        #expect(merged.contains("serisinin 1/3"))
        #expect(server.directives.isEmpty)
        #expect(server.series == nil)
        #expect(server.guest == nil)
    }

    @Test func clientClippingLimits() {
        var s = PodcastSettings(speechProvider: "chirp")
        s.customInstructions = String(repeating: "x", count: 700)
        s.directives = (0..<10).map { _ in String(repeating: "d", count: 1000) }
        s.series = SeriesContext(id: UUID(), name: String(repeating: "n", count: 200), index: 31, total: 40,
                                 previousTitles: (0..<40).map { "T\($0)" + String(repeating: "t", count: 200) },
                                 previousKeyPoints: (0..<20).map { "K\($0)" + String(repeating: "k", count: 400) })
        s.guest = Host(name: String(repeating: "g", count: 30), voice: "Charon")
        let p = ServerSettings.prepare(s, podcast2: true)
        #expect(p.customInstructions!.count <= 500)
        #expect(p.directives.count == 8)
        #expect(p.directives.allSatisfy { $0.count <= 800 })
        #expect(p.series!.name.count <= 120)
        #expect(p.series!.previousTitles.count == 30)
        #expect(p.series!.previousTitles.allSatisfy { $0.count <= 160 })
        #expect(p.series!.previousTitles.first!.hasPrefix("T10"))   // en yeniler kalır
        #expect(p.series!.previousKeyPoints.count == 12)
        #expect(p.series!.previousKeyPoints.allSatisfy { $0.count <= 300 })
        #expect(p.guest?.name.count == 20)
        // Konuk A ile aynı sesse ya da motor desteklemiyorsa gönderilmez.
        s.guest = Host(name: "Deniz", voice: s.hostA.voice)
        #expect(ServerSettings.prepare(s, podcast2: true).guest == nil)
        s.guest = Host(name: "Deniz", voice: "Charon")
        s.speechProvider = "edge"
        #expect(ServerSettings.prepare(s, podcast2: true).guest == nil)
    }

    @Test func queuedSeriesRequestKeepsSeriesContext() throws {
        let container = try ModelContainer(for: QueuedRequest.self, SourceDocument.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let seriesID = UUID()
        let settings = NewPodcastView.seriesSettings(PodcastSettings(), seriesID: seriesID, name: "Biyoloji", index: 3, total: 5,
                                                     previousTitles: ["Hücre", "Doku"], previousKeyPoints: ["Zar"])
        let source = ImportedSource(name: "Organlar", kind: .text(String(repeating: "Organ sistemleri. ", count: 5)))
        let request = OfflineQueue.insert(sources: [source], settings: settings, context: context, state: QueueState.waiting)
        let stored = try #require(try context.fetch(FetchDescriptor<QueuedRequest>()).first)
        #expect(stored.id == request.id)
        #expect(stored.settings?.series?.id == seriesID)
        #expect(stored.settings?.series?.index == 3)
        #expect(stored.settings?.series?.previousTitles == ["Hücre", "Doku"])
        #expect(stored.sourceNames == ["Organlar"])
        #expect(stored.title.hasPrefix("Biyoloji · 3/5"))
        for id in stored.documentIDs { if let doc = DocumentLibrary.fetch(id, context: context) { DocumentLibrary.delete(doc, context: context) } }

        // Bölüm oluşunca seri kimliği atanır.
        let episode = Episode(id: stored.id, script: script(chapters: [[2]]), settings: stored.settings!, sourceNames: ["Organlar"], jobToken: "t")
        episode.applyContext(from: stored.settings!)
        #expect(episode.id == request.id)
        #expect(episode.seriesID == seriesID)
        #expect(episode.seriesIndex == 3)
    }

    @Test func lastSettingsAreReusableAndMaxQualityDoesNotOverrideSaved() throws {
        var saved = PodcastSettings(speechProvider: "claude")
        saved.depth = .ozet
        saved.focus = "Mitoz"
        saved.directives = ["X"]
        saved.series = SeriesContext(id: UUID(), name: "S", index: 1, total: 2, previousTitles: [], previousKeyPoints: [])
        let data = try JSONEncoder().encode(saved)
        let initial = NewPodcastView.initialSettings(saved: data, maxQuality: true)
        #expect(initial.depth == .ozet)          // #50: kayıtlı ayar ezilmez
        #expect(initial.speechProvider == "claude")
        #expect(initial.directives.isEmpty)
        #expect(initial.series == nil)
        #expect(initial.focus == nil)
        let fresh = NewPodcastView.initialSettings(saved: Data(), maxQuality: true)
        #expect(fresh.depth == .derin)
        #expect(fresh.extras.recapQuestions)
        #expect(NewPodcastView.initialSettings(saved: Data(), maxQuality: false).depth == PodcastSettings().depth)
    }

    // MARK: - #4 yeniden deneme

    @Test func retrySchedule() {
        #expect((0..<6).map { RetryPolicy.delay(attempt: $0, retryAfter: nil) } == [30, 120, 300, 900, 900, 900])
        #expect(RetryPolicy.delay(attempt: 0, retryAfter: 42) == 42)
        #expect(RetryPolicy.delay(attempt: 2, retryAfter: 1) == 5)
        #expect(RetryPolicy.delay(attempt: 0, retryAfter: 100_000) == 6 * 3600)
        #expect(RetryPolicy.isRetryable(APIError(status: 0, code: "network", message: "")))
        #expect(RetryPolicy.isRetryable(APIError(status: 429, code: "rate_limited", message: "")))
        #expect(RetryPolicy.isRetryable(APIError(status: 503, code: "http_503", message: "")))
        #expect(!RetryPolicy.isRetryable(APIError(status: 400, code: "bad_request", message: "")))
        #expect(!RetryPolicy.isRetryable(APIError(status: 401, code: "unauthorized", message: "")))
        #expect(!RetryPolicy.isRetryable(CancellationError()))
        #expect(RetryPolicy.isFatalForAudio(APIError(status: 403, code: "job_token_invalid", message: "")))
        // İş hatası: retryAfter varsa kota (yeniden denenir), bilinmeyen hata kalıcı.
        #expect(RetryPolicy.isRetryable(ScriptJobClient.jobError(.init(code: "quota", message: "", retryAfterSec: 60))))
        #expect(!RetryPolicy.isRetryable(ScriptJobClient.jobError(.init(code: "bad_source", message: "", retryAfterSec: nil))))
    }

    // MARK: - #3 ilerleme

    @Test func progressTextAndFractions() {
        let p = ScriptProgress(stage: "chapters", chaptersDone: 6, chaptersTotal: 14)
        #expect(p.text == "Plan çıkarıldı · Konu 6/14")
        #expect(GenerationProgress.text(script: p, scenesDone: 18, scenesTotal: 52) == "Plan çıkarıldı · Konu 6/14 · Sahne 18/52")
        #expect(GenerationProgress.text(script: nil, scenesDone: 3, scenesTotal: 10) == "Sahne 3/10")
        #expect(ScriptProgress(stage: "plan").text == "Plan çıkarılıyor")

        typealias Phase = GenerationCoordinator.Phase
        let ordered: [Phase] = [.preparing, .uploading, .writingScript(ScriptProgress(stage: "plan")),
                                .writingScript(ScriptProgress(stage: "chapters", chaptersDone: 3, chaptersTotal: 10)),
                                .writingScript(ScriptProgress(stage: "chapters", chaptersDone: 9, chaptersTotal: 10)),
                                .writingScript(ScriptProgress(stage: "check")),
                                .voicing(done: 0, total: 10), .voicing(done: 5, total: 10), .mixing]
        let fractions = ordered.map(\.fraction)
        #expect(fractions == fractions.sorted())
        #expect(Set(fractions).count == fractions.count)
        #expect(fractions.allSatisfy { $0 > 0 && $0 < 1 })
        // Sabit 0.12 yok: konu ilerledikçe oran artar.
        #expect(Phase.writingScript(ScriptProgress(stage: "chapters", chaptersDone: 1, chaptersTotal: 2)).draftFraction
                < Phase.writingScript(ScriptProgress(stage: "chapters", chaptersDone: 2, chaptersTotal: 2)).draftFraction)
        #expect(Phase.voicing(done: 18, total: 52).progressText == "Sahne 18/52")
    }

    @Test func statusDecodesIntoProgress() throws {
        let json = #"{"jobId":"j1","state":"running","stage":"chapters","chaptersTotal":12,"chaptersDone":4,"chapterErrors":[],"plan":{"title":"T","chapters":[{"title":"A","targetMinutes":5}]},"prerender":{"done":2,"total":30},"updatedAt":"2026-10-04T10:00:00Z"}"#
        let status = try JSONDecoder().decode(ScriptJobStatus.self, from: Data(json.utf8))
        let p = ScriptProgress(status: status)
        #expect(p.chaptersDone == 4 && p.chaptersTotal == 12)
        #expect(p.scenesDone == 2 && p.scenesTotal == 30)
        let minimal = try JSONDecoder().decode(ScriptJobStatus.self, from: Data(#"{"jobId":"j","state":"queued"}"#.utf8))
        #expect(ScriptProgress(status: minimal).stage == "plan")
        let error = try JSONDecoder().decode(ScriptJobStatus.self, from: Data(#"{"jobId":"j","state":"error","error":{"code":"quota","message":"Kota","retryAfterSec":30}}"#.utf8))
        #expect(error.error?.retryAfterSec == 30)
    }

    @Test func startRequestEncodesLowercasedClientID() throws {
        let id = UUID()
        let request = ScriptStartRequest(clientRequestId: id.uuidString.lowercased(), settings: PodcastSettings(),
                                         sources: [.text("Metin", name: "Not")], prerender: ScriptPrerender(engine: "chirp", replacements: nil))
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(object["clientRequestId"] as? String == id.uuidString.lowercased())
        #expect((object["prerender"] as? [String: Any])?["engine"] as? String == "chirp")
        #expect((object["sources"] as? [[String: Any]])?.first?["kind"] as? String == "text")
    }

    // MARK: - #50 eşzamanlı taslaklar

    @Test func concurrentDraftsDoNotEraseEachOther() {
        let generator = GenerationCoordinator()
        let a = UUID(), b = UUID()
        generator.setDraft(a, .preparing)
        generator.setDraft(b, .writingScript(ScriptProgress(stage: "chapters", chaptersDone: 1, chaptersTotal: 4)))
        #expect(generator.drafts.count == 2)
        #expect(generator.draftPhase == .writingScript(ScriptProgress(stage: "chapters", chaptersDone: 1, chaptersTotal: 4)))
        #expect(generator.hasActiveWork)
        generator.endDraft(a)
        #expect(generator.drafts[b] != nil)
        #expect(generator.draftPhase != nil)
        #expect(generator.progressText(for: b) == "Plan çıkarıldı · Konu 1/4")
        generator.endDraft(b)
        #expect(generator.draftPhase == nil)
        #expect(generator.progressText(for: b) == nil)
    }

    // MARK: - #8 önbellek ve OCR kararı

    @Test func payloadCacheKeyAndOCRDecision() throws {
        let k1 = PayloadCache.key(fileHash: "abc", range: 3...9, method: "img")
        #expect(k1 == "abc-3-9-img-v1")
        #expect(PayloadCache.key(fileHash: "abc", range: nil, method: "img") == "abc-all-img-v1")
        #expect(k1 != PayloadCache.key(fileHash: "abc", range: 3...10, method: "img"))
        #expect(k1 != PayloadCache.key(fileHash: "abd", range: 3...9, method: "img"))
        #expect(k1 != PayloadCache.key(fileHash: "abc", range: 3...9, method: "ocr"))

        let file = URL.temporaryDirectory.appending(path: "hash-\(UUID().uuidString).txt")
        try Data("abc".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try PayloadCache.sha256(of: file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

        #expect(DocumentLoader.scanStrategy(imagesSoFar: 0, scannedPages: Config.maxImages) == "img")
        #expect(DocumentLoader.scanStrategy(imagesSoFar: 5, scannedPages: Config.maxImages - 4) == "ocr")
        #expect(DocumentLoader.scanStrategy(imagesSoFar: 0, scannedPages: 60) == "ocr")
    }

    @Test func payloadCacheRoundTrip() {
        let key = "test-\(UUID().uuidString)"
        let parts = [PayloadCache.Part(kind: "text", name: "Kitap", text: "[Sayfa 1]\nMetin"),
                     PayloadCache.Part(kind: "image", name: "Kitap — sayfa 2", data: Data([1, 2, 3]))]
        PayloadCache.store(parts, key: key)
        defer { try? FileManager.default.removeItem(at: PayloadCache.directory.appending(path: key + ".json")) }
        #expect(PayloadCache.load(key) == parts)
        if case let .image(_, name)? = parts[1].payload { #expect(name.hasSuffix("— sayfa 2")) } else { Issue.record("görsel parça") }
    }

    @Test func sourcePageBudget() {
        #expect(SourcePages.normalized([3, 1, 3, 0, -2]) == [1, 3])
        let pages = [PageText(page: 1, text: String(repeating: "a", count: 7000)), PageText(page: 2, text: "bbbb"), PageText(page: 3, text: "cc")]
        let out = SourcePages.budgeted(pages, maxChars: 6003)
        #expect(out.map(\.page) == [1, 2])
        #expect(out[0].text.count == 6000)   // sayfa başına 6000
        #expect(out[1].text == "bbb")
    }

    // MARK: - #43 profiller

    @Test func profilesEncodeAndUpsert() throws {
        var s = PodcastSettings(speechProvider: "chirp")
        s.durationMin = 30
        s.directives = ["bölüme özgü"]
        s.series = SeriesContext(id: UUID(), name: "S", index: 1, total: 2, previousTitles: [], previousKeyPoints: [])
        var list = PodcastProfiles.upserting([], name: "Sabah", settings: s)
        list = PodcastProfiles.upserting(list, name: "Sınav", settings: PodcastSettings())
        list = PodcastProfiles.upserting(list, name: "Sabah", settings: s)
        #expect(list.map(\.name) == ["Sabah", "Sınav"])
        #expect(list[0].settings.durationMin == 30)
        #expect(list[0].settings.series == nil)
        #expect(list[0].settings.directives.isEmpty)
        let decoded = try JSONDecoder().decode([PodcastProfile].self, from: JSONEncoder().encode(list))
        #expect(decoded == list)
        var many: [PodcastProfile] = []
        for i in 0..<25 { many = PodcastProfiles.upserting(many, name: "P\(i)", settings: s) }
        #expect(many.count == PodcastProfiles.maxCount)
        #expect(many.first?.name == "P24")
    }

    @Test func quickSettingsProfileKeepsContext() {
        var base = PodcastSettings()
        base.derivation = Derivation(kind: "video", parentEpisodeID: UUID())
        base.directives = ["Farkı ne?"]
        var profile = PodcastSettings(speechProvider: "claude")
        profile.durationMin = 45
        let merged = QuickSettingsSheet.applying(profile, keepingContextOf: base)
        #expect(merged.durationMin == 45)
        #expect(merged.speechProvider == "claude")
        #expect(merged.derivation == base.derivation)
        #expect(merged.directives == ["Farkı ne?"])
    }

    // MARK: - #46 bildirimler

    @Test func notificationUserInfoMatchesAppLink() throws {
        let id = UUID()
        let ready = NotificationActions.content(.ready, episodeID: id, title: "Hücre")
        #expect(ready.category == NotificationActions.readyCategory)
        let parsed = try #require(ready.userInfo["episodeID"].flatMap(UUID.init(uuidString:)))
        #expect(parsed == id)
        #expect(AppLink(url: AppLink.generation(parsed).url) == .generation(id))
        #expect(AppLink(url: AppLink.episode(parsed, time: nil, play: true).url) == .episode(id, time: nil, play: true))
        #expect(NotificationActions.content(.stalled("Ağ yok"), episodeID: id, title: "T").category == NotificationActions.stalledCategory)
        #expect(NotificationActions.content(.approval, episodeID: id, title: "T").title == "Senaryo hazır, onay bekliyor")
    }

    @Test func unknownNotificationActionIsNotHandled() async {
        #expect(await NotificationActions.handle(actionIdentifier: "başka", episodeID: UUID()) == false)
        #expect(await NotificationActions.handle(actionIdentifier: NotificationActions.listenAction, episodeID: nil) == false)
    }

    // MARK: - #4 açılışta sürdürme

    @Test func launchPlanKeepsApprovalAndRetries() {
        let approval = UUID(), running = UUID(), broken = UUID(), ready = UUID()
        let uploading = UUID(), waiting = UUID(), retry = UUID(), live = UUID()
        let plan = GenerationQueue.launchPlan(
            episodes: [.init(id: approval, status: .generating, canResume: true, needsApproval: true),
                       .init(id: running, status: .generating, canResume: true, needsApproval: false),
                       .init(id: broken, status: .generating, canResume: false, needsApproval: false),
                       .init(id: ready, status: .ready, canResume: false, needsApproval: false)],
            requests: [.init(id: uploading, state: QueueState.uploading), .init(id: waiting, state: QueueState.waiting),
                       .init(id: retry, state: QueueState.needsRetry), .init(id: live, state: QueueState.scripting)],
            scripting: [live])
        #expect(plan.resume == [running])
        #expect(plan.expire == [broken])
        #expect(!plan.expire.contains(approval) && !plan.resume.contains(approval))
        #expect(plan.requeue == [uploading])
        #expect(plan.keepActivities == [running, live])
    }

    // MARK: - #5/#7 senaryo düzenleme

    @Test func globalTurnAndSceneIndices() {
        let s = script(chapters: [[2, 3], [1]])
        #expect(ScriptEditing.locate(0, in: s)! == (0, 0))
        #expect(ScriptEditing.locate(4, in: s)! == (1, 2))
        #expect(ScriptEditing.locate(5, in: s)! == (2, 0))
        #expect(ScriptEditing.locate(6, in: s) == nil)
        #expect(ScriptEditing.chapterAndScene(2, in: s)! == (1, 0))
        let fixed = ScriptEditing.applyFixes([FixedTurn(index: 3, text: "Düzeltildi", style: "sakin"), FixedTurn(index: 99, text: "x", style: nil)], to: s)
        let turns = ScriptEditing.allTurns(fixed)
        #expect(turns[3].text == "Düzeltildi")
        #expect(turns[3].style == "sakin")
        #expect(turns[3].speaker == ScriptEditing.allTurns(s)[3].speaker)
        #expect(turns.count == 6)
        let replaced = ScriptEditing.replacingScene(2, with: [ScriptTurn(speaker: .b, text: "Yeni", style: "")], in: s)
        #expect(replaced.chapters[1].scenes[0].turns.map(\.text) == ["Yeni"])
    }

    @Test func referencedPagesCollectChapterAndTurnPages() {
        var s = script(chapters: [[1], [1]])
        s.chapters[0].sourcePages = [4, 2]
        s.chapters[1].scenes[0].turns[0].sourcePage = 7
        #expect(ScriptEditing.referencedPages(s) == [2, 4, 7])
    }

    // MARK: - #47 karne

    @Test func costAndDurationFormatting() {
        // Yalnız Chirp HD ücretlidir; sunucu sesleri (XTTS), cihaz içi sesler ve abonelikle yazılan senaryo ek ücret sayılmaz.
        #expect(GenerationCost.estimate(engine: .apple, characters: 10_000) == 0)
        #expect(GenerationCost.estimate(engine: .chirp, characters: 100_000) == 3)
        #expect(GenerationCost.estimate(engine: .xtts, characters: 100_000) == 0 && GenerationCost.estimate(engine: .supertonic, characters: 100_000) == 0)
        #expect(GenerationStatsCard.duration(45) == "45 sn")
        #expect(GenerationStatsCard.duration(80) == "1 dk 20 sn")
        #expect(GenerationStatsCard.duration(120) == "2 dk")
        #expect(GenerationStatsCard.duration(3900) == "1 sa 5 dk")
        #expect(GenerationStatsCard.cost(0) == "Ücretsiz")
        #expect(FailedEpisodeView.preservedText(ready: 34, total: 52) == "Senaryo kayıtlı · 34/52 sahne hazır")
    }

    // MARK: - #48 temizlik

    @Test func orphanFolderRules() {
        let now = Date.now
        let known = UUID(), queued = UUID(), orphan = UUID(), fresh = UUID()
        let folders: [(name: String, modified: Date)] = [
            (known.uuidString, now.addingTimeInterval(-90_000)), (queued.uuidString, now.addingTimeInterval(-90_000)),
            (orphan.uuidString, now.addingTimeInterval(-90_000)), (fresh.uuidString, now.addingTimeInterval(-3600)),
            ("Briefings", now.addingTimeInterval(-900_000))]
        #expect(OrphanCleanup.orphans(folders: folders, episodeIDs: [known], requestIDs: [queued], now: now, restoring: false) == [orphan.uuidString])
        #expect(OrphanCleanup.orphans(folders: folders, episodeIDs: [], requestIDs: [], now: now, restoring: true).isEmpty)
    }

    @Test func queuedPageRangesRoundTrip() {
        let requestID = UUID(), doc = UUID()
        var source = ImportedSource(name: "Kitap", kind: .text("x"))
        source.pageRange = 5...9
        QueuedPageRanges.save([source], documentIDs: [doc], for: requestID)
        defer { QueuedPageRanges.clear(requestID) }
        var loaded = ImportedSource(name: "Kitap", kind: .text("x"))
        loaded.documentID = doc
        #expect(QueuedPageRanges.apply(to: [loaded], for: requestID).first?.pageRange == 5...9)
    }

    @Test func queuedPageRangesStayAlignedWhenFirstSourceFailsToPersist() {
        let requestID = UUID(), second = UUID()
        var a = ImportedSource(name: "A", kind: .text("x")); a.pageRange = 1...3
        var b = ImportedSource(name: "B", kind: .text("y")); b.pageRange = 10...12
        // İlk kaynağın kopyası başarısız (nil): ikincinin aralığı kendi belgesine yazılır.
        QueuedPageRanges.save([a, b], documentIDs: [nil, second], for: requestID)
        defer { QueuedPageRanges.clear(requestID) }
        var loaded = ImportedSource(name: "B", kind: .text("y"))
        loaded.documentID = second
        #expect(QueuedPageRanges.apply(to: [loaded], for: requestID).first?.pageRange == 10...12)
    }

    @Test func restoringFlagAndFinalOrphanCheck() {
        let now = Date.now
        #expect(OrphanCleanup.isRestoring(true))
        #expect(!OrphanCleanup.isRestoring(nil))
        #expect(OrphanCleanup.isRestoring(now.addingTimeInterval(-60), now: now))
        #expect(!OrphanCleanup.isRestoring(now.addingTimeInterval(-3 * 3600), now: now))   // takılı kalmış bayrak
        let restored = UUID(), orphan = UUID()
        // Aday listesi çıkarıldıktan sonra geri yükleme bölüm ekledi: son denetimde düşer.
        #expect(OrphanCleanup.stillOrphans([restored.uuidString, orphan.uuidString, "Briefings"], episodeIDs: [restored], requestIDs: [])
                == [orphan.uuidString])
    }

    // MARK: - İnceleme düzeltmeleri

    private func decodeStatus(_ json: String) throws -> ScriptJobStatus {
        try JSONDecoder().decode(ScriptJobStatus.self, from: Data(json.utf8))
    }

    @Test func finishedJobIsReleasedSoNextAttemptOpensNewJob() async throws {
        let failed = try decodeStatus(#"{"jobId":"old","state":"error","error":{"code":"upstream_error","message":"Model yanıt vermedi."}}"#)
        let canceled = try decodeStatus(#"{"jobId":"new","state":"canceled"}"#)
        var jobs: [String?] = []
        var starts = 0
        let api = ScriptJobAPI(start: { _ in starts += 1; return "new" },
                               status: { id in id == "old" ? failed : canceled },
                               result: { _ in throw CancellationError() })
        let start = ScriptStartRequest(clientRequestId: "c", settings: PodcastSettings(), sources: [.text("x", name: "n")], prerender: nil)
        // 1) Biten (error) iş bırakılır; hata geçici sayılır (upstream_error → 503, otomatik yeniden denenir).
        do {
            _ = try await ScriptJobClient.run(existingJobID: "old", api: api, makeStart: { start }, onJob: { jobs.append($0) }, onProgress: { _ in })
            Issue.record("hata bekleniyordu")
        } catch {
            #expect(RetryPolicy.isRetryable(error))
            #expect((error as? APIError)?.status == 503)
        }
        #expect(jobs == [nil])
        #expect(starts == 0)
        // 2) Sonraki deneme iş kimliği olmadan başlar → aynı istek kimliğiyle YENİ iş; iptal edilen iş de bırakılır.
        do {
            _ = try await ScriptJobClient.run(existingJobID: nil, api: api, makeStart: { start }, onJob: { jobs.append($0) }, onProgress: { _ in })
            Issue.record("hata bekleniyordu")
        } catch {
            #expect((error as? APIError)?.code == "canceled")
        }
        #expect(starts == 1)
        #expect(jobs == [nil, "new", nil])
    }

    @Test func jobErrorCodesMatchServerErrorCodes() {
        func mapped(_ code: String, after: Double? = nil) -> APIError {
            ScriptJobClient.jobError(.init(code: code, message: "m", retryAfterSec: after))
        }
        for code in ["upstream_error", "internal", "server_restarted"] {
            #expect(mapped(code).status == 503)
            #expect(RetryPolicy.isRetryable(mapped(code)))
        }
        #expect(mapped("rate_limited").status == 429)
        #expect(mapped("daily_limit").status == 429)
        #expect(mapped("rate_limited", after: 40).retryAfter == 40)
        #expect(mapped("content_blocked").status == 422)
        #expect(mapped("invalid_request").status == 400)
        #expect(mapped("budget_exceeded").status == 403)
        #expect(!RetryPolicy.isRetryable(mapped("content_blocked")))
        #expect(!RetryPolicy.isRetryable(mapped("conflict")))
        // Süreğen sunucu hatası sonsuz denenmez; ağ ve kota her zaman beklenir.
        #expect(RetryPolicy.shouldAutoRetry(mapped("internal"), attempts: RetryPolicy.maxServerAttempts - 1))
        #expect(!RetryPolicy.shouldAutoRetry(mapped("internal"), attempts: RetryPolicy.maxServerAttempts))
        #expect(RetryPolicy.shouldAutoRetry(mapped("rate_limited"), attempts: 50))
        #expect(RetryPolicy.shouldAutoRetry(APIError(status: 0, code: "network", message: ""), attempts: 50))
    }

    @Test func seriesWaitsForEarlierEpisodeInQueue() {
        let series = UUID(), other = UUID()
        let first = UUID(), second = UUID(), third = UUID(), lone = UUID()
        let items: [OfflineQueue.SeriesItem] = [
            .init(id: first, seriesID: series, index: 2, failed: false),
            .init(id: second, seriesID: series, index: 3, failed: false),
            .init(id: third, seriesID: series, index: 4, failed: false),
            .init(id: lone, seriesID: other, index: 5, failed: false)]
        #expect(OfflineQueue.blockedBySeries(items) == [second, third])
        // Başarısız önceki bölüm sonrakileri kilitlemez.
        var failedFirst = items
        failedFirst[0].failed = true
        #expect(OfflineQueue.blockedBySeries(failedFirst) == [third])
        #expect(OfflineQueue.blockedBySeries(Array(items.dropFirst())) == [third])
    }

    @Test func seriesContextPicksUpEpisodesWrittenWhileQueued() {
        let series = SeriesContext(id: UUID(), name: "Biyoloji", index: 4, total: 5, previousTitles: ["Hücre"], previousKeyPoints: ["Zar"])
        let refreshed = OfflineQueue.refreshedSeries(series, earlier: [
            (index: 3, title: "Organlar", keyPoints: ["Kalp dört odalıdır."]),
            (index: 2, title: "Doku", keyPoints: ["Epitel"])])
        #expect(refreshed.previousTitles == ["Hücre", "Doku", "Organlar"])
        #expect(refreshed.previousKeyPoints == ["Kalp dört odalıdır."])
        #expect(OfflineQueue.refreshedSeries(series, earlier: []) == series)
    }

    @Test func retriedChapterMapsWeakScenesToLocalOrder() {
        func chapter(_ title: String, _ scenes: Int) -> ScriptChapter {
            ScriptChapter(title: title, scenes: (0..<scenes).map { s in
                ScriptScene(turns: [ScriptTurn(speaker: .a, text: "\(title) sahne \(s) bir iki", style: "")])
            })
        }
        func quality(words: Int, weak: [Int], errors: [ChapterError]) -> ScriptQualityReport {
            ScriptQualityReport(targetMinutes: 10, estimatedMinutes: 10, words: words, findings: [],
                                weakScenes: weak.map { WeakScene(scene: $0, reasons: ["r\($0)"]) }, chapterErrors: errors)
        }
        // Sunucu: [A(2), B, C, X(2)]; yerelde A silindi → [B, C], C'nin sahnesi zayıf (yerel 1).
        var local = PodcastScript(title: "T", summary: "", keyPoints: [], chapters: [chapter("B", 1), chapter("C", 1)], sourceNotes: "")
        local.quality = quality(words: 400, weak: [1], errors: [ChapterError(index: 3, title: "X", message: "zaman aşımı")])
        var fresh = PodcastScript(title: "T", summary: "", keyPoints: [],
                                  chapters: [chapter("A", 2), chapter("B", 1), chapter("C", 1), chapter("X", 2)], sourceNotes: "")
        fresh.quality = quality(words: 999, weak: [3, 5], errors: [])
        let merged = ScriptEditing.mergeRetriedChapter(fresh.chapters[3], serverIndex: 3, into: local, fresh: fresh)
        #expect(merged.chapters.map(\.title) == ["B", "C", "X"])
        // C yerelde 1'de kalır; X'in 2. sahnesi (sunucu 5) yerelde 3 olur. Sunucu indeksleri (3) yerele taşınmaz.
        #expect(merged.quality?.weakScenes.map(\.scene) == [1, 3])
        #expect(merged.quality?.weakScenes.first?.reasons == ["r1"])
        #expect(merged.quality?.chapterErrors.isEmpty == true)
        // Kelime ve süre yerel senaryodan: 4 sahne × 5 kelime = 20; oran 10 dk / 400 kelime.
        #expect(merged.quality?.words == 20)
        #expect(merged.quality?.estimatedMinutes == 0.5)
    }

    @Test func pulseCreepsTowardCeilingWithoutReachingIt() {
        var level = 0.1
        for _ in 0..<500 { level = PulseMath.next(level, toward: 0.2) }
        #expect(level < 0.2 && level >= 0.197)
        #expect(PulseMath.next(0.1, toward: 0.2) > 0.1)
        #expect(PulseMath.next(0.3, toward: 0.2) == 0.3)   // geri gitmez
    }

    @Test func rehearsalCarriesToneStyle() throws {
        #expect(VoiceRehearsal.style(tone: .akademik, speaker: .a) == "sakin, ciddi")
        #expect(VoiceRehearsal.style(tone: .eglenceli, speaker: .b) == "meraklı, neşeli, canlı")
        let request = SpeakRequest(engine: "edge", voice: "Emel", pace: .hizli, style: VoiceRehearsal.style(tone: .sinav, speaker: .a),
                                   text: "Merhaba", replacements: nil)
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(object["style"] as? String == "net, tempolu")
        for tone in PodcastTone.allCases { #expect(VoiceRehearsal.style(tone: tone, speaker: .b).count <= 120) }
    }

    // MARK: - İnceleme düzeltmeleri

    @Test func serverLimitsAreMeasuredInUTF16() {
        // Emoji 2 UTF-16 birimi; bölünmez.
        #expect(ServerText.prefix("ab😀c", 3) == "ab")
        #expect(ServerText.prefix("ab😀c", 4) == "ab😀")
        #expect(ServerText.prefix("kısa", 10) == "kısa")
        #expect(ServerText.prefix("abc", 0) == "")
        // PDFKit'in ayrışık (NFD) "ş"si birleşik biçime getirilir: 1 birim.
        let nfd = "s\u{0327}"
        #expect(nfd.utf16.count == 2)
        #expect(ServerText.prefix(String(repeating: nfd, count: 10), 100).utf16.count == 10)
        var s = PodcastSettings(speechProvider: "chirp")
        s.customInstructions = String(repeating: "😀", count: 400)   // 400 karakter, 800 UTF-16
        s.directives = [String(repeating: "😀", count: 700)]
        s.series = SeriesContext(id: UUID(), name: String(repeating: "😀", count: 100), index: 1, total: 2,
                                 previousTitles: [String(repeating: "😀", count: 150)], previousKeyPoints: [])
        s.guest = Host(name: String(repeating: "😀", count: 15), voice: "Charon")
        let p = ServerSettings.prepare(s, podcast2: true)
        #expect(p.customInstructions!.utf16.count <= 500)
        #expect(p.directives.allSatisfy { $0.utf16.count <= 800 })
        #expect(p.series!.name.utf16.count <= 120)
        #expect(p.series!.previousTitles.allSatisfy { $0.utf16.count <= 160 })
        #expect(p.guest!.name.utf16.count <= 20)
        let old = ServerSettings.prepare(s, podcast2: false)
        #expect(old.customInstructions!.utf16.count <= 500)
        // Sayfa bütçesi de UTF-16 ile: 6000 sınırı ve toplam.
        let pages = [PageText(page: 1, text: String(repeating: "😀", count: 4000)), PageText(page: 2, text: String(repeating: nfd, count: 10))]
        let out = SourcePages.budgeted(pages, maxChars: 6004)
        #expect(out[0].text.utf16.count == 6000)
        #expect(out[1].text.utf16.count == 4)
    }

    @Test func polishIsAppliedByChapterKeyAndDroppedWhenChapterGone() throws {
        let local = script(chapters: [[1, 1], [2, 1]])   // Konu 1: sahne 0,1 · Konu 2: sahne 2,3
        let key = try #require(ScriptEditing.sceneKey(3, in: local))
        #expect(key.title == "Konu 2" && key.scene == 1)
        let original = local.flatScenes[3].scene
        let turns = [ScriptTurn(speaker: .a, text: "Cilalı", style: "")]
        // İstek sürerken ilk konu silindi: sahne artık küresel 1.
        var edited = local
        edited.chapters.removeFirst()
        let applied = try #require(ScriptEditing.applyingPolish(turns, key: key, original: original, in: edited))
        #expect(applied.scene == 1)
        #expect(applied.script.chapters[0].scenes[1].turns.map(\.text) == ["Cilalı"])
        #expect(applied.script.chapters[0].scenes[0] == edited.chapters[0].scenes[0])   // başka sahne ezilmez
        // Konu silindiyse ya da sahne değiştiyse sonuç atılır.
        var gone = local
        gone.chapters.removeLast()
        #expect(ScriptEditing.applyingPolish(turns, key: key, original: original, in: gone) == nil)
        let changed = ScriptEditing.replacingScene(3, with: [ScriptTurn(speaker: .b, text: "başka", style: "")], in: local)
        #expect(ScriptEditing.applyingPolish(turns, key: key, original: original, in: changed) == nil)
    }

    @Test func retriedChapterIsNeverPickedByPlanIndexAlone() {
        func chapter(_ title: String) -> ScriptChapter {
            ScriptChapter(title: title, scenes: [ScriptScene(turns: [ScriptTurn(speaker: .a, text: title, style: "")])])
        }
        func report(_ errors: [ChapterError]) -> ScriptQualityReport {
            ScriptQualityReport(targetMinutes: 10, estimatedMinutes: 10, words: 1, findings: [], weakScenes: [], chapterErrors: errors)
        }
        let error = ChapterError(index: 2, title: "C", message: "zaman aşımı")
        let local = PodcastScript(title: "T", summary: "", keyPoints: [], chapters: [chapter("A"), chapter("B"), chapter("D")], sourceNotes: "")
        // Sunucu yine yazamadı: senaryo yalnız yazılabilmiş konular (plan 3. konu D, fresh'te indeks 2).
        var stillFailing = PodcastScript(title: "T", summary: "", keyPoints: [], chapters: [chapter("A"), chapter("B"), chapter("D")], sourceNotes: "")
        stillFailing.quality = report([ChapterError(index: 2, title: "C", message: "yine olmadı")])
        #expect(ScriptEditing.retriedChapter(for: error, in: stillFailing, local: local) == nil)
        // Başlıkla eşlenir.
        var fresh = PodcastScript(title: "T", summary: "", keyPoints: [], chapters: [chapter("A"), chapter("B"), chapter("C"), chapter("D")], sourceNotes: "")
        fresh.quality = report([])
        #expect(ScriptEditing.retriedChapter(for: error, in: fresh, local: local)?.title == "C")
        // Başlık değiştiyse plan sırası, öbür yazılamayan konular düşülerek çevrilir (A yazılamadı → C fresh'te 1).
        var renamed = PodcastScript(title: "T", summary: "", keyPoints: [], chapters: [chapter("B"), chapter("C2"), chapter("D")], sourceNotes: "")
        renamed.quality = report([ChapterError(index: 0, title: "A", message: "x")])
        #expect(ScriptEditing.retriedChapter(for: error, in: renamed, local: local)?.title == "C2")
        // O sırada yerelde zaten olan bir konu çıkarsa (yanlış eşleşme) kullanılmaz.
        var shifted = PodcastScript(title: "T", summary: "", keyPoints: [], chapters: [chapter("A"), chapter("B"), chapter("D")], sourceNotes: "")
        shifted.quality = report([])
        #expect(ScriptEditing.retriedChapter(for: error, in: shifted, local: local) == nil)
    }

    @Test func fixingSomeTurnsKeepsOtherVerificationIssues() {
        let issues = [ScriptIssue(index: 1, severity: "hatali", reason: "a", correction: nil, quote: nil, page: 2, fixedAt: nil),
                      ScriptIssue(index: 4, severity: "uydurma", reason: "b", correction: "c", quote: nil, page: nil, fixedAt: nil)]
        let date = Date(timeIntervalSince1970: 100)
        let marked = ScriptEditing.markingFixed(issues, turns: [4], at: date)
        #expect(marked?.count == 2)
        #expect(marked?[0].fixedAt == nil)
        #expect(marked?[1].fixedAt == date)
        #expect(ScriptEditing.markingFixed(nil, turns: [1]) == nil)
    }

    @Test func verifyAndFixRequestsCarrySourcePageAndRespectLimits() throws {
        let verify = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            VerifyTurn.make(index: 3, text: String(repeating: "😀", count: 1500), page: 7))) as? [String: Any])
        #expect(verify["page"] as? Int == 7)
        #expect((verify["text"] as? String)?.utf16.count == 2000)
        let noPage = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            VerifyTurn.make(index: 0, text: "a", page: 0))) as? [String: Any])
        #expect(noPage["page"] == nil)

        let issue = ScriptIssue(index: 2, severity: "hatali", reason: String(repeating: "😀", count: 400),
                                correction: String(repeating: "é", count: 2000), quote: nil, page: nil, fixedAt: nil)
        let turn = ScriptTurn(speaker: .b, text: "Mitokondri hücrenin enerji santralidir.", style: "sakin", sourcePage: 5)
        let fix = try #require(FixTurnsTurn.make(index: 2, turn: turn, issue: issue))
        #expect(fix.sourcePage == 5)
        #expect(fix.issue.reason.utf16.count <= 600)
        #expect((fix.issue.correction?.utf16.count ?? 0) <= 1500)
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(fix)) as? [String: Any])
        #expect(object["sourcePage"] as? Int == 5)
        // Sunucu sınırını aşan tur kırpılarak gönderilmez (düzeltme turun geri kalanını silerdi).
        let long = ScriptTurn(speaker: .a, text: String(repeating: "a", count: 1501), style: "")
        #expect(FixTurnsTurn.make(index: 0, turn: long, issue: issue) == nil)
    }

    @Test func retryingWithAdoptedDocumentIDsDoesNotDuplicateDocuments() throws {
        let container = try ModelContainer(for: QueuedRequest.self, SourceDocument.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        var sources = [ImportedSource(name: "Notlar", kind: .text(String(repeating: "Hücre zarı. ", count: 5))),
                       ImportedSource(name: "Ek", kind: .text(String(repeating: "Doku. ", count: 5)))]
        var adopted: [UUID?] = []
        let first = OfflineQueue.insert(sources: sources, settings: PodcastSettings(), context: context, state: QueueState.uploading,
                                        onDocuments: { adopted = $0 })
        #expect(adopted.count == 2 && adopted.allSatisfy { $0 != nil })
        sources = NewPodcastView.adoptingDocumentIDs(adopted, for: sources, in: sources)
        #expect(sources.map(\.documentID) == adopted)
        // Kalıcı hata: istek silinir; yeniden deneme aynı belgeleri kullanır.
        context.delete(first)
        let second = OfflineQueue.insert(sources: sources, settings: PodcastSettings(), context: context, state: QueueState.uploading)
        #expect(second.documentIDs == adopted.compactMap { $0 })
        #expect(try context.fetch(FetchDescriptor<SourceDocument>()).count == 2)
        for doc in try context.fetch(FetchDescriptor<SourceDocument>()) { DocumentLibrary.delete(doc, context: context) }
        // Başka kaynaklara dokunulmaz; eşleşmeyen kimlik atlanır.
        let other = ImportedSource(name: "Başka", kind: .text("x"))
        #expect(NewPodcastView.adoptingDocumentIDs([UUID()], for: [other], in: sources) == sources)
    }

    @Test func permanentFailureNotificationAndLiveActivityFraction() throws {
        let id = UUID()
        let failed = NotificationActions.content(.failed("İçerik engellendi."), episodeID: id, title: "Hücre")
        #expect(failed.title == "Podcast oluşturulamadı")
        #expect(failed.body == "Hücre: İçerik engellendi.")
        #expect(failed.category == NotificationActions.stalledCategory)
        // Eski durum (oran alanı yok) çözülür; yeni durum gerçek oranı taşır (senaryo bitince %100 görünmez).
        let old = try JSONDecoder().decode(GenerationActivityAttributes.ContentState.self,
                                           from: Data(#"{"phase":"Seslendiriliyor","done":1,"total":4,"finished":false}"#.utf8))
        #expect(old.fraction == nil)
        let scripted = GenerationCoordinator.Phase.writingScript(ScriptProgress(stage: "chapters", chaptersDone: 14, chaptersTotal: 14))
        #expect(scripted.fraction <= 0.45)
        let state = GenerationActivityAttributes.ContentState(phase: "Senaryo yazılıyor", done: 14, total: 14, finished: false,
                                                              detail: nil, fraction: scripted.fraction)
        let decoded = try JSONDecoder().decode(GenerationActivityAttributes.ContentState.self, from: JSONEncoder().encode(state))
        #expect(decoded.fraction == scripted.fraction)
    }
}

/// Uygulamadaki bütün sesler podcastte de seçilebilir (17 Eki 2026): Chirp, "Claude + Chirp", SesLab (XTTS), Apple, Supertonic ve
/// Piper; Edge ve Hugging Face sunulmaz. "Claude + Chirp"te Claude okunuşları hazırlar; sesi yine Chirp üretir.
@MainActor
struct SpeechEngineChoiceTests {
    @Test func everyAppVoiceEngineIsOffered() {
        #expect(SpeechEngine.offered == [.azure, .chirp, .claude, .xtts, .apple, .supertonic, .piper, .ema])
        #expect(!SpeechEngine.offered.contains(.edge) && !SpeechEngine.offered.contains(.huggingface))
        // Konuk sesi yalnız Chirp'le seslendirilen motorlarda.
        #expect(SpeechEngine.offered.filter(\.supportsGuest) == [.chirp, .claude])
        #expect(SpeechEngine.claude.title.contains(QSModelPlan.astraOnly ? "Astra" : "Claude") && SpeechEngine.claude.title.contains("Chirp"))
        #expect(SpeechEngine.claude.voiceLabel(.a) == SpeechEngine.chirp.voiceLabel(.a) && SpeechEngine.claude.voiceLabel(.b) == SpeechEngine.chirp.voiceLabel(.b))
        // Öbür motorlar kendilerini üretir; yalnız "Claude + Chirp"in sesi başka motordan gelir.
        #expect(SpeechEngine.allCases.filter { $0.voicedBy != $0 } == [.claude])
    }

    /// Sunulmayan motor yeni bölüme sızmaz: son ayarlar, profil ve kuyruk hep sunulan bir motorla sonuçlanır. Daha önce
    /// seslendirilmiş bölümün kaydı ise olduğu gibi okunur (sahne düzenleme ve maliyet istatistikleri tutarlı kalır).
    @Test func removedEnginesNeverReachNewAudioButOldEpisodesKeepTheirs() throws {
        // Kaldırılan "gemini" sunucu seslerine (XTTS) döner; o artık sunulur.
        #expect(PodcastSettings(speechProvider: "gemini").forNewAudio.speechProvider == "xtts")
        for removed in ["edge", "huggingface", "bilinmeyen"] {
            var old = PodcastSettings(speechProvider: removed)
            old.durationMin = 30
            #expect(old.forNewAudio.speechProvider == "chirp", "\(removed) yeni seste Chirp olmalı")
            #expect(old.reusable.engine == .chirp)
            // Motor dışındaki ayarlar korunur.
            #expect(old.forNewAudio.durationMin == 30)
            let last = NewPodcastView.initialSettings(saved: try JSONEncoder().encode(old), maxQuality: false)
            #expect(last.engine == .chirp)
            #expect(QuickSettingsSheet.applying(old, keepingContextOf: PodcastSettings()).engine == .chirp)
        }
        for kept in SpeechEngine.offered {
            let settings = PodcastSettings(speechProvider: kept.rawValue)
            #expect(settings.forNewAudio == settings && settings.reusable.engine == kept)
        }
        // Eski bölümün kaydı çözümlenirken motoru değişmez.
        let stored = try JSONDecoder().decode(PodcastSettings.self, from: Data(#"{"speechProvider":"edge"}"#.utf8))
        #expect(stored.engine == .edge)
    }

    @Test func queuedRequestsAlwaysCarryAnOfferedEngine() throws {
        let container = try ModelContainer(for: QueuedRequest.self, SourceDocument.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let source = ImportedSource(name: "Not", kind: .text(String(repeating: "Hücre zarı seçici geçirgendir. ", count: 5)))
        let request = OfflineQueue.insert(sources: [source], settings: PodcastSettings(speechProvider: "edge"), context: context, state: QueueState.waiting)
        #expect(request.settings?.engine == .chirp)
        let piper = OfflineQueue.insert(sources: [source], settings: PodcastSettings(speechProvider: "piper"), context: context, state: QueueState.waiting)
        #expect(piper.settings?.engine == .piper)
        let chosen = OfflineQueue.insert(sources: [source], settings: PodcastSettings(speechProvider: "claude"), context: context, state: QueueState.waiting)
        #expect(chosen.settings?.engine == .claude)
    }

    @Test func claudeChirpBehavesLikeChirpEverywhereButPreparation() {
        let chirp = PodcastSettings(speechProvider: "chirp"), claude = PodcastSettings(speechProvider: "claude")
        #expect(claude.usesServerSpeech && claude.usesChirp)
        #expect(GenerationCost.estimate(engine: .claude, characters: 100_000) == GenerationCost.estimate(engine: .chirp, characters: 100_000))
        #expect(SceneQualityGate.rateBounds(.claude) == SceneQualityGate.rateBounds(.chirp))
        // Okunuş hazırlığı uygulama içinde (Claude API ile) yapılır.
        #expect(Backend.enginePaths.contains("/v1/speech-readings"))
        // Sahne, Claude'un okunuşlarıyla istenir: sunucunun önceden ürettiği düz Chirp sesi kullanılmazdı, bu yüzden istenmez.
        #expect(GenerationCoordinator.prerender(for: claude) == nil)
        // Sahne dosyaları motor başına ayrıdır: düz Chirp sesi "Claude + Chirp" bölümünde yeniden kullanılmaz.
        let episode = Episode(script: PodcastScript(title: "T", summary: "", keyPoints: [], chapters: [], sourceNotes: ""), settings: chirp, sourceNames: [], jobToken: "")
        #expect(GenerationCoordinator.sceneURL(episode, settings: chirp, index: 0) != GenerationCoordinator.sceneURL(episode, settings: claude, index: 0))
    }

    @Test func readingsFollowTheUsersOwnPronunciations() {
        let own = [Pronunciation(from: "DNA", to: "di en ey"), Pronunciation(from: "sklera", to: "sk-le-ra")]
        let readings = [Pronunciation(from: "dna", to: "de ne a"), Pronunciation(from: "CO2", to: "karbondioksit"),
                        Pronunciation(from: String(repeating: "x", count: 61), to: "uzun"), Pronunciation(from: " ", to: "boş")]
        let merged = Pronunciations.merged(own, with: readings)
        // Aynı sözcükte kullanıcının kaydı kalır; sunucunun kabul etmeyeceği okunuş eklenmez.
        #expect(merged == [own[0], own[1], readings[1]])
        #expect(Pronunciations.merged(own, with: []) == own)
        // Liste sunucu sınırını aşmaz ve kullanıcının kayıtları öndedir.
        let full = (0..<Pronunciations.limit).map { Pronunciation(from: "kelime\($0)", to: "okunuş") }
        #expect(Pronunciations.merged(full, with: readings) == full)
        let request = Pronunciations.attach(to: TTSRequest(jobToken: "t", sceneIndex: 0, turns: []), adding: [readings[1]])
        #expect(request.replacements?.contains(readings[1]) == true)
    }
}
