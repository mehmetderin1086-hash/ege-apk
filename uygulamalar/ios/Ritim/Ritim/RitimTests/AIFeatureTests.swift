import XCTest
@testable import Ritim

/// Scripted AI client: records each request and answers with the next queued reply.
private final class ScriptedAIClient: AIChatting {
    struct Call { let task: AITask; let prompt: String; let context: [String: Any]; let trackIDs: [String] }
    var calls: [Call] = []
    var replies: [(AITask, [String: Any]) -> [String: Any]] = []
    var failure: Error?
    var modelOverride: String?
    /// When set, answers by task instead of consuming `replies` in order.
    var handler: ((AITask, [String: Any]) -> [String: Any])?
    var delays: [AITask: Duration] = [:]

    func models(connection: AIConnectionSettings, token: String) async throws -> [AIModel] {
        [AIModel(id: "first", name: "First", provider: "Test")]
    }

    func chat(connection: AIConnectionSettings, token: String, model: String, prompt: String,
              history: [[String: String]], tracks: [[String: Any]], context: [String: Any], task: AITask) async throws -> AIChatReply {
        let ids = tracks.compactMap { $0["id"] as? String }
        calls.append(Call(task: task, prompt: prompt, context: context, trackIDs: ids))
        if let failure { throw failure }
        if let delay = delays[task] { try await Task.sleep(for: delay) }
        if let handler {
            let content = String(decoding: try JSONSerialization.data(withJSONObject: handler(task, context)), as: UTF8.self)
            return try DirectAIClient.normalize(content, model: modelOverride ?? model, allowedIDs: Set(ids.compactMap(UUID.init(uuidString:))))
        }
        let builder = replies.isEmpty ? { _, _ in ["reply": "Tamam", "search_queries": [String]()] } : replies.removeFirst()
        let value = builder(task, context)
        let content = String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
        return try DirectAIClient.normalize(content, model: modelOverride ?? model, allowedIDs: Set(ids.compactMap(UUID.init(uuidString:))))
    }
}

@MainActor
final class AIFeatureTests: XCTestCase {
    private func makeStores(client: ScriptedAIClient, directory: URL? = nil) throws -> (AIAssistantStore, LibraryStore, PlaybackStore, URL) {
        let dir = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("AIFeature-\(UUID())")
        if directory == nil {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        }
        let library = LibraryStore(directory: dir.appendingPathComponent("Media"))
        let playback = PlaybackStore(library: library)
        addTeardownBlock { playback.stop() }
        let connection = AIConnectionSettings(baseURL: "https://ai.test.invalid/v1", defaultModelID: "first")
        let assistant = AIAssistantStore(directory: dir, connection: connection, tokenProvider: { "token" }, client: client)
        return (assistant, library, playback, dir)
    }

    private func reply(_ text: String, ids: [UUID], action: String = "none", queries: [String] = []) -> [String: Any] {
        ["reply": text, "playlist": ["name": "Liste", "track_ids": ids.map(\.uuidString)], "search_queries": queries, "action": action]
    }

    func testNormalizeParsesActionAndIgnoresUnknownOrPlaylistlessActions() throws {
        let id = UUID()
        func content(_ value: [String: Any]) -> String { String(decoding: try! JSONSerialization.data(withJSONObject: value), as: UTF8.self) }
        let play = try DirectAIClient.normalize(content(reply("Çalıyorum", ids: [id], action: "PLAY")), model: "m", allowedIDs: [id])
        XCTAssertEqual(play.action, .play)
        let queue = try DirectAIClient.normalize(content(reply("Ekledim", ids: [id], action: "queue_next")), model: "m", allowedIDs: [id])
        XCTAssertEqual(queue.action, .queueNext)
        let unknown = try DirectAIClient.normalize(content(reply("x", ids: [id], action: "download_everything")), model: "m", allowedIDs: [id])
        XCTAssertEqual(unknown.action, .none)
        let noList = try DirectAIClient.normalize(content(["reply": "x", "playlist": NSNull(), "search_queries": [String](), "action": "play"]),
                                                  model: "m", allowedIDs: [id])
        XCTAssertEqual(noList.action, .none, "Liste yokken eylem uygulanmamalı")
        let legacy = try DirectAIClient.normalize(content(["reply": "x", "playlist": NSNull(), "search_queries": [String]()]), model: "m", allowedIDs: [])
        XCTAssertEqual(legacy.action, .none, "Eski yanıt biçimi geçerli kalmalı")
    }

    func testContextCarriesTimeNowPlayingRecentAndExclusionsWithoutFiles() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 21, minute: 15))!
        var old = MediaTrack(title: "Eski", fileName: "a.m4a"); old.lastPlayedAt = now.addingTimeInterval(-3600)
        var fresh = MediaTrack(title: "Yeni", fileName: "b.m4a"); fresh.lastPlayedAt = now.addingTimeInterval(-60)
        let never = MediaTrack(title: "Hiç", fileName: "c.m4a")
        let context = AIContextBuilder.make(now: now, calendar: calendar, library: [old, fresh, never],
                                            playlists: [MediaPlaylist(name: "Akşam", trackIDs: [old.id])],
                                            current: fresh, queue: [fresh, old], exclude: [never.id])
        XCTAssertEqual(context["day_part"] as? String, "akşam")
        XCTAssertEqual(context["local_time"] as? String, "Salı 21:15")
        XCTAssertEqual(context["recent_ids"] as? [String], [fresh.id.uuidString, old.id.uuidString])
        XCTAssertEqual((context["now_playing"] as? [String: Any])?["title"] as? String, "Yeni")
        XCTAssertEqual(context["exclude_ids"] as? [String], [never.id.uuidString])
        XCTAssertEqual(context["queue_ids"] as? [String], [fresh.id.uuidString, old.id.uuidString])
        let encoded = String(decoding: try! JSONSerialization.data(withJSONObject: context), as: UTF8.self)
        XCTAssertFalse(encoded.contains(".m4a"), "Dosya adları modele gönderilmemeli")
    }

    func testDayPartBoundariesAndPresetsFollowTheClock() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func part(_ hour: Int) -> AIDayPart { AIDayPart(date: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: hour))!, calendar: calendar) }
        XCTAssertEqual([4, 5, 10, 11, 13, 14, 17, 18, 22, 23].map { part($0) },
                       [.night, .morning, .morning, .noon, .noon, .afternoon, .afternoon, .evening, .evening, .night])
        XCTAssertEqual(part(23).presets.first?.id, "sleep")
        XCTAssertEqual(part(7).presets.first?.id, "wake")
        for part in AIDayPart.allCases { XCTAssertEqual(Set(part.presets.map(\.id)).count, part.presets.count) }
    }

    func testChatPlayActionStartsLocalPlaybackAndQueueActionKeepsCurrentTrack() async throws {
        let client = ScriptedAIClient()
        let (assistant, library, playback, _) = try makeStores(client: client)
        await assistant.loadModels()
        let ids = library.tracks.map(\.id)
        client.replies = [{ _, _ in self.reply("Çalıyorum", ids: [ids[1], ids[2]], action: "play") }]
        await assistant.send("Sakin bir şey çal", library: library, playback: playback)
        XCTAssertNil(assistant.errorMessage)
        XCTAssertEqual(playback.current?.id, ids[1])
        XCTAssertEqual(playback.queue.map(\.id), [ids[1], ids[2]])
        XCTAssertEqual(assistant.messages.last?.appliedNote, "Çalmaya başladı · 2 parça")
        XCTAssertEqual(client.calls.last?.task, .chat)

        client.replies = [{ _, _ in self.reply("Sıraya ekledim", ids: [ids[0]], action: "queue_next") }]
        await assistant.send("Bunu sıraya ekle", library: library, playback: playback)
        XCTAssertEqual(playback.current?.id, ids[1], "Sıraya ekleme çalan parçayı değiştirmemeli")
        XCTAssertEqual(playback.queue.map(\.id), [ids[1], ids[0], ids[2]])
        XCTAssertEqual((client.calls.last?.context["now_playing"] as? [String: Any])?["id"] as? String, ids[1].uuidString)
        XCTAssertTrue(library.playlists.isEmpty, "Eylemler kitaplığı değiştirmemeli")
    }

    func testQueueActionDuringDJExtendsTheSetInsteadOfStoppingIt() async throws {
        let client = ScriptedAIClient()
        let (assistant, library, playback, _) = try makeStores(client: client)
        await assistant.loadModels()
        let ids = library.tracks.map(\.id)
        client.handler = { task, _ in
            switch task {
            case .dj: return self.reply("DJ", ids: [ids[0], ids[1]], action: "play")
            case .chat: return self.reply("Ekledim", ids: [ids[2]], action: "queue_next")
            // The pending continuation proposes the same track the chat just queued.
            default: return self.reply("Devam", ids: [ids[2]], action: "queue_next")
            }
        }
        client.delays[.djContinue] = .milliseconds(500)
        await assistant.startDJ(mood: "Odak", library: library, playback: playback)
        await assistant.send("Şunu da sıraya ekle", library: library, playback: playback)
        XCTAssertEqual(assistant.dj?.trackIDs, [ids[0], ids[1], ids[2]])
        try await waitUntil { client.calls.contains { $0.task == .djContinue } && assistant.dj?.isExtending == false }
        XCTAssertEqual(assistant.dj?.trackIDs, [ids[0], ids[1], ids[2]], "Bekleyen DJ yanıtı aynı parçayı tekrar eklememeli")
        XCTAssertEqual(playback.queue.map(\.id), [ids[0], ids[2], ids[1]], "Kullanıcının sıradaki seçimi yer değiştirmemeli")
        playback.next()
        try await waitUntil { playback.current?.id == ids[2] }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNotNil(assistant.dj, "Sohbetle eklenen parça DJ'i durdurmamalı")
    }

    func testSingleTrackDJSetExtendsImmediatelyAndContinuesAfterTheLastTrackEnds() async throws {
        let client = ScriptedAIClient()
        let (assistant, library, playback, _) = try makeStores(client: client)
        await assistant.loadModels()
        let ids = library.tracks.map(\.id)
        client.handler = { task, _ in
            task == .dj ? self.reply("Tek parça", ids: [ids[0]], action: "play") : self.reply("Devam", ids: [ids[1]], action: "queue_next")
        }
        // The model answers only after the single track has already finished.
        client.delays[.djContinue] = .seconds(3)
        await assistant.startDJ(mood: "Kısa", library: library, playback: playback)
        XCTAssertEqual(playback.current?.id, ids[0])
        try await waitUntil { assistant.dj?.isExtending == true }
        try await waitUntil(timeout: 8) { playback.duration > 1 }
        playback.seek(to: playback.duration - 0.4)
        try await waitUntil(timeout: 8) { !playback.isPlaying }
        XCTAssertEqual(playback.current?.id, ids[0], "Set bittiğinde oynatıcı son parçada durur")
        try await waitUntil(timeout: 8) { playback.current?.id == ids[1] }
        XCTAssertTrue(playback.isPlaying, "Geç gelen DJ devamı çalmayı sürdürmeli")
        XCTAssertEqual(assistant.dj?.trackIDs, [ids[0], ids[1]])
    }

    func testChatWithoutPlaybackOnlyProposesAndHistorySurvivesRelaunchUntilCleared() async throws {
        let client = ScriptedAIClient()
        let (assistant, library, _, dir) = try makeStores(client: client)
        await assistant.loadModels()
        let ids = library.tracks.map(\.id)
        client.replies = [{ _, _ in self.reply("Öneri", ids: [ids[0]], action: "play", queries: ["sakin piyano"]) }]
        await assistant.send("Liste", library: library)
        XCTAssertNil(assistant.messages.last?.appliedNote)
        XCTAssertEqual(assistant.messages.count, 2)

        let (restored, _, _, _) = try makeStores(client: ScriptedAIClient(), directory: dir)
        XCTAssertEqual(restored.messages.map(\.role), ["user", "assistant"])
        XCTAssertEqual(restored.messages.last?.playlist?.trackIDs, [ids[0]])
        XCTAssertEqual(restored.messages.last?.searchQueries, ["sakin piyano"])
        restored.clearConversation()
        let (cleared, _, _, _) = try makeStores(client: ScriptedAIClient(), directory: dir)
        XCTAssertTrue(cleared.messages.isEmpty)
    }

    func testDJPlaysSetExtendsWithoutRepeatsAndStopsWhenListenerTakesOver() async throws {
        let client = ScriptedAIClient()
        let (assistant, library, playback, _) = try makeStores(client: client)
        await assistant.loadModels()
        let ids = library.tracks.map(\.id)
        var excludedOnFirstContinue: Set<String>?
        client.handler = { task, context in
            if task == .dj { return self.reply("DJ yayında", ids: [ids[0], ids[1]], action: "play") }
            if excludedOnFirstContinue == nil { excludedOnFirstContinue = Set(context["exclude_ids"] as? [String] ?? []) }
            // Offers an already played track plus one new track.
            return self.reply("Devam", ids: [ids[0], ids[2]], action: "queue_next")
        }
        await assistant.startDJ(mood: "Akşam sakinliği", library: library, playback: playback)
        XCTAssertEqual(playback.current?.id, ids[0])
        XCTAssertFalse(playback.shuffleEnabled)
        try await waitUntil { assistant.dj?.trackIDs.count == 3 && assistant.dj?.isExtending == false }
        XCTAssertEqual(excludedOnFirstContinue, Set([ids[0], ids[1]].map(\.uuidString)), "Devam isteği setteki parçaları dışlamalı")
        XCTAssertEqual(assistant.dj?.trackIDs, [ids[0], ids[1], ids[2]], "Zaten setteki parça tekrar eklenmemeli")
        XCTAssertEqual(playback.queue.map(\.id), [ids[0], ids[1], ids[2]])
        XCTAssertEqual(assistant.dj?.note, "Devam")
        XCTAssertEqual(Array(client.calls.map(\.task).prefix(2)), [.dj, .djContinue])
    }

    func testDJStopsWhenListenerPlaysATrackOutsideTheSet() async throws {
        let client = ScriptedAIClient()
        let (assistant, library, playback, _) = try makeStores(client: client)
        await assistant.loadModels()
        let ids = library.tracks.map(\.id)
        client.handler = { task, _ in
            task == .dj ? self.reply("DJ yayında", ids: [ids[0], ids[1]], action: "play") : ["reply": "Yok", "search_queries": [String]()]
        }
        await assistant.startDJ(mood: "Odak", library: library, playback: playback)
        XCTAssertNotNil(assistant.dj)
        try await waitUntil { assistant.dj?.isExtending == false && client.calls.count == 2 }
        let outsider = library.tracks[2]
        playback.play(outsider, in: [outsider])
        try await waitUntil { assistant.dj == nil }
        XCTAssertEqual(assistant.djMessage, "Başka bir parça seçtin; AI DJ durdu.")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(client.calls.count, 2, "DJ durunca yeni istek atılmamalı")
    }

    func testDJFailureKeepsPlaybackUntouchedAndReportsFriendlyError() async throws {
        let client = ScriptedAIClient()
        let (assistant, library, playback, _) = try makeStores(client: client)
        await assistant.loadModels()
        client.failure = URLError(.timedOut)
        await assistant.startDJ(mood: "Enerji", library: library, playback: playback)
        XCTAssertNil(assistant.dj)
        XCTAssertNil(playback.current)
        XCTAssertEqual(assistant.djMessage, "Model zamanında yanıt vermedi. Tekrar dene veya başka model seç.")
        XCTAssertEqual(assistant.selectedModel?.availability, "error")
    }

    func testFeatureRejectsDifferentModelReply() async throws {
        let client = ScriptedAIClient()
        let (assistant, library, playback, _) = try makeStores(client: client)
        await assistant.loadModels()
        client.modelOverride = "other"
        let ids = library.tracks.map(\.id)
        client.replies = [{ _, _ in self.reply("x", ids: ids, action: "play") }]
        await assistant.startDJ(mood: "Enerji", library: library, playback: playback)
        XCTAssertNil(assistant.dj)
        XCTAssertNil(playback.current)
        XCTAssertTrue(assistant.djMessage?.contains("farklı bir model") == true)
    }

    func testInsightExcludesCurrentTrackIsCachedAndPersisted() async throws {
        let client = ScriptedAIClient()
        let (assistant, library, playback, dir) = try makeStores(client: client)
        await assistant.loadModels()
        let tracks = library.tracks
        client.replies = [{ _, _ in self.reply("Sakin bir parça.", ids: [tracks[0].id, tracks[1].id], queries: ["benzer"]) }]
        await assistant.loadInsight(for: tracks[0], library: library, playback: playback)
        let insight = try XCTUnwrap(assistant.insights[tracks[0].id])
        XCTAssertEqual(insight.text, "Sakin bir parça.")
        XCTAssertEqual(insight.similarIDs, [tracks[1].id], "Çalan parça kendi benzeri olmamalı")
        XCTAssertEqual(client.calls.first?.task, .insight)
        await assistant.loadInsight(for: tracks[0], library: library, playback: playback)
        XCTAssertEqual(client.calls.count, 1, "Önbellekteki not için yeniden istek atılmamalı")

        let (restored, _, _, _) = try makeStores(client: ScriptedAIClient(), directory: dir)
        XCTAssertEqual(restored.insights[tracks[0].id]?.similarIDs, [tracks[1].id])
    }

    func testDailyMixIsGeneratedOncePerDayAndRespectsTheProactiveSwitch() async throws {
        let client = ScriptedAIClient()
        let (assistant, library, playback, dir) = try makeStores(client: client)
        let ids = library.tracks.map(\.id)
        client.replies = [{ _, _ in self.reply("Günün notu", ids: ids) }]
        await assistant.prepareProactive(library: library, playback: playback)
        let mix = try XCTUnwrap(assistant.dailyMix)
        XCTAssertEqual(mix.trackIDs, ids)
        XCTAssertTrue(mix.isFresh())
        XCTAssertEqual(client.calls.map(\.task), [.daily])
        await assistant.prepareProactive(library: library, playback: playback)
        XCTAssertEqual(client.calls.count, 1, "Aynı gün ikinci kez model çağrılmamalı")

        let (restored, _, _, _) = try makeStores(client: client, directory: dir)
        XCTAssertEqual(restored.dailyMix, mix)
        restored.proactiveEnabled = false
        let (disabled, _, _, _) = try makeStores(client: client, directory: dir)
        XCTAssertFalse(disabled.proactiveEnabled, "Kapalı tercih kalıcı olmalı")

        let failing = ScriptedAIClient()
        failing.failure = URLError(.notConnectedToInternet)
        let (offline, offlineLibrary, offlinePlayback, _) = try makeStores(client: failing)
        await offline.prepareProactive(library: offlineLibrary, playback: offlinePlayback)
        XCTAssertNotNil(offline.dailyError)
        await offline.prepareProactive(library: offlineLibrary, playback: offlinePlayback)
        XCTAssertEqual(failing.calls.count, 1, "Hatadan sonra her ana sayfa ziyaretinde yeniden istenmemeli")

        let yesterday = AIDailyMix(title: "t", note: "n", trackIDs: ids, model: "first",
                                   createdAt: Date().addingTimeInterval(-86_400 * 2), dayPart: "sabah")
        XCTAssertFalse(yesterday.isFresh())
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("Koşul zamanında sağlanmadı"); return }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func video(_ query: String, _ index: Int) -> PlaylistItem {
        let letters = query.unicodeScalars.filter { $0.isASCII && CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
        let id = String((letters + "xxxxxxxxx").prefix(9)) + "_\(index)"
        return PlaylistItem(id: id, url: "https://www.youtube.com/watch?v=\(id)", title: "\(query) \(index)", artist: "Kanal", duration: 200, index: index)
    }

    private func discoverStore(client: ScriptedAIClient, searched: @escaping (String) -> Void) throws -> (AIAssistantStore, LibraryStore) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AIDiscover-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let library = LibraryStore(directory: dir.appendingPathComponent("Media"))
        let shared = Self.video("Ortak Parca", 0)
        let assistant = AIAssistantStore(directory: dir, connection: AIConnectionSettings(baseURL: "https://ai.test.invalid/v1", defaultModelID: "first"),
                                         tokenProvider: { "token" }, searchProvider: { query in
            await MainActor.run { searched(query) }
            return [Self.video(query, 0), Self.video(query, 1), shared]
        }, client: client)
        return (assistant, library)
    }

    func testFindMoreAddsNewAnglesOnceAndStopsWhenExhausted() async throws {
        var searched: [String] = []
        let (assistant, _) = try discoverStore(client: ScriptedAIClient()) { searched.append($0) }
        await assistant.search("Tarkan")
        XCTAssertTrue(assistant.canFindMore)
        let before = assistant.searchResults.count
        await assistant.findMore()
        XCTAssertEqual(Array(assistant.searchQueries.suffix(3)), ["Tarkan canlı", "Tarkan akustik", "Tarkan remix"])
        XCTAssertGreaterThan(assistant.searchResults.count, before)
        await assistant.findMore()
        await assistant.findMore()
        XCTAssertEqual(Set(assistant.searchQueries).count, assistant.searchQueries.count, "Aynı açı iki kez aranmamalı")
        XCTAssertFalse(assistant.canFindMore, "Açılar bitince düğme kapanmalı")
        XCTAssertEqual(searched.filter { $0 == "Tarkan canlı" }.count, 1)
    }

    func testDiscoverRunsTheUserQueryAndTheModelsSimilarSearchesWithoutDuplicates() async throws {
        let client = ScriptedAIClient()
        client.handler = { task, _ in
            ["reply": "Benzer aramalar", "playlist": NSNull(), "action": "none",
             "search_queries": task == .discover ? ["barış manço", "Cem Karaca", "Erkin Koray"] : [String]()]
        }
        var searched: [String] = []
        let (assistant, library) = try discoverStore(client: client) { searched.append($0) }
        await assistant.loadModels()
        await assistant.discover("Barış Manço", library: library)

        XCTAssertEqual(client.calls.last?.task, .discover)
        XCTAssertEqual(client.calls.last?.prompt, "Barış Manço")
        XCTAssertEqual(assistant.searchQueries, ["Barış Manço", "Cem Karaca", "Erkin Koray"], "Aynı arama tekrar edilmemeli")
        XCTAssertEqual(Set(searched), ["Barış Manço", "Cem Karaca", "Erkin Koray"])
        XCTAssertEqual(assistant.searchResults.map(\.title), ["Barış Manço 0", "Barış Manço 1", "Ortak Parca 0",
                                                             "Cem Karaca 0", "Cem Karaca 1", "Erkin Koray 0", "Erkin Koray 1"],
                       "Kullanıcının araması önce gelmeli, ortak sonuç bir kez görünmeli")
        XCTAssertEqual(assistant.searchSources["CemKaraca_0"], "Cem Karaca")
        XCTAssertEqual(assistant.searchSources["OrtakParc_0"], "Barış Manço")
        XCTAssertFalse(assistant.isSearching); XCTAssertFalse(assistant.isExpandingSearch)
        XCTAssertNil(assistant.searchNote)
    }

    func testDiscoverFallsBackToTheUserQueryWhenTheModelFails() async throws {
        let client = ScriptedAIClient()
        var searched: [String] = []
        let (assistant, library) = try discoverStore(client: client) { searched.append($0) }
        await assistant.loadModels()
        client.failure = RitimError.message("kota")
        await assistant.discover("lo-fi çalışma", library: library)
        XCTAssertEqual(searched, ["lo-fi çalışma"])
        XCTAssertEqual(assistant.searchResults.count, 3)
        XCTAssertTrue(assistant.searchNote?.contains("yalnız senin araman") == true)
        XCTAssertNil(assistant.errorMessage, "Model hatası arama sonuçlarını engellememeli")
    }

    func testChatAskingForYouTubeRunsTheProposedSearches() async throws {
        let client = ScriptedAIClient()
        client.handler = { _, _ in ["reply": "YouTube'da şunlara bak", "playlist": NSNull(), "action": "none",
                                    "search_queries": ["Tarkan Kuzu Kuzu", "Tarkan Şımarık"]] }
        var searched: [String] = []
        let (assistant, library) = try discoverStore(client: client) { searched.append($0) }
        await assistant.loadModels()
        await assistant.send("YouTube'da Tarkan şarkıları bul", library: library)
        try await waitUntil { !assistant.searchResults.isEmpty && !assistant.isSearching }
        XCTAssertEqual(Set(searched), ["Tarkan Kuzu Kuzu", "Tarkan Şımarık"])
        XCTAssertEqual(assistant.searchQueries, ["Tarkan Kuzu Kuzu", "Tarkan Şımarık"])

        searched = []
        await assistant.send("Bunları yorumla", library: library)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(searched.isEmpty, "Arama niyeti yokken YouTube'a gidilmemeli")
    }
}

extension AIFeatureTests {
    func testRecommendationExclusionsPersistAndCanBeReset() throws {
        let client = ScriptedAIClient()
        let (assistant, library, _, directory) = try makeStores(client: client)
        let id = try XCTUnwrap(library.tracks.first?.id)
        assistant.excludeRecommendation([id])
        let (restored, _, _, _) = try makeStores(client: client, directory: directory)
        XCTAssertTrue(restored.excludedTrackIDs.contains(id))
        restored.resetRecommendationExclusions()
        XCTAssertTrue(restored.excludedTrackIDs.isEmpty)
    }
}
