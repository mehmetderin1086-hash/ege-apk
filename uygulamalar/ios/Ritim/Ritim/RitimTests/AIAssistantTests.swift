import XCTest
@testable import Ritim

private final class AIProtocol: URLProtocol, @unchecked Sendable {
    struct Reply { var status = 200; let body: [String: Any]; var delay: TimeInterval = 0 }
    static let lock = NSLock()
    static var handler: ((URLRequest) -> Reply)?
    private let stateLock = NSLock()
    private var stopped = false
    static func handle(_ action: @escaping (URLRequest) -> Reply) { lock.withLock { handler = action } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let result = Self.lock.withLock { Self.handler?(request) } ?? Reply(status: 500, body: [:])
        DispatchQueue.global().asyncAfter(deadline: .now() + result.delay) { [self] in
            guard !stateLock.withLock({ stopped }) else { return }
            let response = HTTPURLResponse(url: request.url!, statusCode: result.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: result.body))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { stateLock.withLock { stopped = true } }
}

@MainActor
final class AIAssistantTests: XCTestCase {
    private let catalog: [String: Any] = ["data": [["id": "first"], ["id": "second"]]]
    private var connection: AIConnectionSettings {
        AIConnectionSettings(baseURL: "https://ai.test.invalid/v1", authHeader: "X-Personal-Token", authScheme: "",
                             defaultModelID: "first", models: [AIModel(id: "first", name: "First", provider: "ChatGPT"),
                                                              AIModel(id: "second", name: "Second", provider: "Claude")])
    }

    private func completion(model: String = "first", reply: String = "Bu listeyi öneriyorum.", playlist: [String: Any]? = nil,
                            queries: [String] = []) -> [String: Any] {
        let value: [String: Any] = ["reply": reply, "playlist": playlist ?? NSNull(), "search_queries": queries]
        let content = String(decoding: try! JSONSerialization.data(withJSONObject: value), as: UTF8.self)
        return ["model": model, "choices": [["message": ["content": content]]]]
    }

    private func setupStores(search: ((String) async throws -> [PlaylistItem])? = nil) throws -> (AIAssistantStore, LibraryStore, URL, URLSession) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AITests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let library = LibraryStore(directory: directory.appendingPathComponent("Media"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIProtocol.self]
        let session = URLSession(configuration: configuration)
        let assistant = AIAssistantStore(directory: directory, session: session, connection: connection,
                                         tokenProvider: { "fixture-personal-gateway-token" }, searchProvider: search)
        return (assistant, library, directory, session)
    }

    func testDirectHTTPSPlaylistPreviewFiltersIDsAndOnlyExplicitCreationChangesLibrary() async throws {
        let (assistant, library, directory, _) = try setupStores()
        let ids = library.tracks.map(\.id)
        XCTAssertFalse(ids.isEmpty)
        let catalog = catalog
        let response = completion(playlist: ["name": "Sakin", "track_ids": [ids[0].uuidString, UUID().uuidString, ids[0].uuidString]])
        AIProtocol.handle { request in
            XCTAssertEqual(request.url?.host, "ai.test.invalid")
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Personal-Token"), "fixture-personal-gateway-token")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-CLIProxy-Allow-Fallback"), "false")
            if request.url!.path.hasSuffix("models") { return .init(body: catalog) }
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            return .init(body: response)
        }
        await assistant.loadModels()
        await assistant.send("Sakin liste", library: library)
        XCTAssertNil(assistant.errorMessage)
        let proposal = try XCTUnwrap(assistant.messages.last?.playlist)
        XCTAssertEqual(proposal.trackIDs, [ids[0]])
        XCTAssertTrue(library.playlists.isEmpty)
        assistant.createPlaylist(proposal, library: library)
        assistant.createPlaylist(proposal, library: library)
        XCTAssertEqual(library.playlists.count, 1)
        let reloaded = LibraryStore(directory: directory.appendingPathComponent("Media"), seed: false)
        XCTAssertEqual(reloaded.playlists[0].trackIDs, [ids[0]])
        XCTAssertEqual(reloaded.tracks.map(\.id), ids)
    }

    func testExplicitModelPersistsAndUnavailableSelectionDoesNotSilentlyFallback() async throws {
        let (assistant, _, directory, session) = try setupStores()
        let catalog = catalog
        AIProtocol.handle { _ in .init(body: catalog) }
        await assistant.loadModels()
        assistant.selectedModelID = "second"
        let restored = AIAssistantStore(directory: directory, session: session, connection: connection,
                                        tokenProvider: { "fixture-personal-gateway-token" })
        await restored.loadModels()
        XCTAssertEqual(restored.selectedModelID, "second")
        AIProtocol.handle { _ in .init(body: ["data": [["id": "first"]]]) }
        await restored.loadModels()
        XCTAssertEqual(restored.selectedModelID, "second")
        XCTAssertNil(restored.selectedModel)
        XCTAssertNotNil(restored.errorMessage)
    }

    func testLiveCatalogExpandsPairingMetadataWithoutOfferingNonChatModels() async throws {
        let (assistant, _, _, _) = try setupStores()
        let liveIDs = ["first", "gpt-6.1-sol", "gpt-6-astra", "claude-opus-5-5", "gemini-4-argon",
                       "gemini-4-argon-high", "antigravity-claude-sonnet-5-5", "qwen2.5-math-1.5b-instruct"]
        let excluded = ["gpt-image-2.5-flare", "gemini-3.8-flash-tts", "gemini-3.8-live", "dersdas-gemini-ocr",
                        "dersdas-gemini-tools", "dersdas-gemini-verifier", "text-embedding-3-small", "whisper-1",
                        "antigravity-gemini-image", "gpt-realtime", "sora-2", "omni-moderation-latest"]
        AIProtocol.handle { _ in .init(body: ["data": (liveIDs + excluded + ["first", "", "bad\nmodel"]).map { ["id": $0] }]) }
        await assistant.loadModels()
        XCTAssertNil(assistant.errorMessage)
        XCTAssertEqual(assistant.models.map(\.id), liveIDs)
        XCTAssertEqual(assistant.selectedModelID, "first")
        XCTAssertEqual(assistant.models.first?.name, "First", "Eşleştirme adları korunmalı; yeni modelleri gizlememeli")
        XCTAssertFalse(assistant.models.contains { $0.id == "second" }, "Sunucuda olmayan metadata modeli eklenmemeli")
        XCTAssertEqual(assistant.models.first { $0.id == "gpt-6.1-sol" }?.name, "GPT-6.1 Sol")
        XCTAssertEqual(assistant.models.first { $0.id == "claude-opus-5-5" }?.name, "Claude Opus 5.5")
        XCTAssertEqual(assistant.models.first { $0.id == "gemini-4-argon" }?.providerGroup, "Gemini")
        XCTAssertEqual(assistant.models.first { $0.id == "antigravity-claude-sonnet-5-5" }?.providerGroup, "Antigravity")
        XCTAssertTrue(assistant.models.allSatisfy { $0.availability == "unknown" }, "Katalogda olmak gerçek yanıt doğrulaması değildir")
    }

    func testNewlyDiscoveredModelSelectionPersistsAndChatRequiresThatExactModel() async throws {
        let (assistant, library, directory, session) = try setupStores()
        let liveCatalog: [String: Any] = ["data": [["id": "first"], ["id": "gpt-6.1-sol"]]]
        let matching = completion(model: "gpt-6.1-sol")
        AIProtocol.handle { request in
            request.url!.path.hasSuffix("models") ? .init(body: liveCatalog) : .init(body: matching)
        }
        await assistant.loadModels()
        assistant.selectedModelID = "gpt-6.1-sol"
        await assistant.send("Bir müzik önerisi", library: library)
        XCTAssertNil(assistant.errorMessage)
        XCTAssertEqual(assistant.messages.last?.model, "gpt-6.1-sol")
        XCTAssertEqual(assistant.selectedModel?.availability, "verified")
        let restored = AIAssistantStore(directory: directory, session: session, connection: connection,
                                        tokenProvider: { "fixture-personal-gateway-token" })
        await restored.loadModels()
        XCTAssertEqual(restored.selectedModelID, "gpt-6.1-sol")
        XCTAssertNotNil(restored.selectedModel)
        let mismatch = completion(model: "first")
        AIProtocol.handle { _ in .init(body: mismatch) }
        // The earlier reply is restored from chat history; the mismatched reply must not be added.
        let repliesBefore = restored.messages.filter { $0.role == "assistant" }.count
        XCTAssertEqual(repliesBefore, 1)
        await restored.send("Bir müzik önerisi", library: library)
        XCTAssertTrue(restored.errorMessage?.contains("farklı bir model") == true)
        XCTAssertEqual(restored.messages.filter { $0.role == "assistant" }.count, repliesBefore)
        XCTAssertEqual(restored.selectedModelID, "gpt-6.1-sol")
    }

    func testCatalogDoesNotTruncateAfterOneHundredToolRowsOrTrustStaleVerifiedFlags() {
        let tools = (0..<110).map { ["id": "tool-\($0)-image"] }
        let models = DirectAIClient.chatModels(tools + [["id": "claude-opus-5-5"]],
                                              overrides: [AIModel(id: "claude-opus-5-5", name: "Opus", provider: "Claude", availability: "verified")])
        XCTAssertEqual(models.map(\.id), ["claude-opus-5-5"])
        XCTAssertEqual(models.first?.availability, "unknown")
    }

    func testWrongModelAndQuotaFailWithoutFallbackOrUpstreamSecretLeak() async throws {
        let (assistant, library, _, _) = try setupStores()
        let catalog = catalog, response = completion(model: "second")
        AIProtocol.handle { request in
            request.url!.path.hasSuffix("models") ? .init(body: catalog) : .init(body: response)
        }
        await assistant.loadModels()
        await assistant.send("Liste yap", library: library)
        XCTAssertTrue(assistant.errorMessage?.contains("farklı bir model") == true)
        XCTAssertFalse(assistant.messages.contains { $0.role == "assistant" })
        AIProtocol.handle { _ in .init(status: 429, body: ["error": "private-provider-account-secret"]) }
        await assistant.send("Liste yap", library: library)
        XCTAssertTrue(assistant.errorMessage?.contains("kullanım sınırına") == true)
        XCTAssertFalse(assistant.errorMessage?.contains("private-provider") == true)
        XCTAssertEqual(assistant.selectedModelID, "first")
        XCTAssertEqual(assistant.messages.count, 1)
        XCTAssertTrue(library.playlists.isEmpty)
    }

    func testPreviouslySuccessfulModelLosesVerifiedStatusWhenNextRequestHitsQuotaOrBilling() async throws {
        let (assistant, library, _, _) = try setupStores()
        let catalog = catalog, response = completion()
        AIProtocol.handle { request in
            request.url!.path.hasSuffix("models") ? .init(body: catalog) : .init(body: response)
        }
        await assistant.loadModels()
        await assistant.send("İlk öneri", library: library)
        XCTAssertEqual(assistant.selectedModel?.availability, "verified")
        XCTAssertEqual(assistant.messages.filter { $0.role == "assistant" }.count, 1)

        AIProtocol.handle { _ in .init(status: 429, body: ["error": "private-provider-account-secret"]) }
        await assistant.send("İkinci öneri", library: library)
        XCTAssertEqual(assistant.selectedModel?.availability, "error")
        XCTAssertEqual(assistant.errorMessage, "Seçili modelin kullanım sınırına ulaşıldı. Daha sonra dene veya başka model seç.")
        XCTAssertEqual(assistant.selectedModelID, "first")
        XCTAssertEqual(assistant.messages.filter { $0.role == "assistant" }.count, 1)

        AIProtocol.handle { _ in .init(status: 402, body: ["error": "private-billing-secret"]) }
        await assistant.send("Üçüncü öneri", library: library)
        XCTAssertEqual(assistant.selectedModel?.availability, "error")
        XCTAssertEqual(assistant.errorMessage, "Seçili modelin hesabında yeterli bakiye yok veya ödeme gerekiyor. CLIProxy hesabının bakiye ve faturalandırma durumunu kontrol et ya da başka model seç.")
        XCTAssertEqual(assistant.selectedModelID, "first")
        XCTAssertEqual(assistant.messages.filter { $0.role == "assistant" }.count, 1)
    }

    func testClearingCancelsLateResponseAndNativeSearchDiscardsInvalidLinks() async throws {
        let json = """
        [{"id":"1","url":"https://www.youtube.com/watch?v=gHKT4uU8Zng","title":"Real","artist":"Test","index":1},
         {"id":"2","url":"https://evil.invalid/song.mp3","title":"Invalid","artist":"Test","index":2},
         {"id":"3","url":"https://youtu.be/gHKT4uU8Zng","title":"Duplicate","artist":"Test","index":3}]
        """
        let items = try JSONDecoder().decode([PlaylistItem].self, from: Data(json.utf8))
        let (assistant, library, _, _) = try setupStores(search: { query in XCTAssertEqual(query, "Test"); return items })
        let catalog = catalog, response = completion(reply: "Late")
        AIProtocol.handle { request in
            request.url!.path.hasSuffix("models") ? .init(body: catalog) : .init(body: response, delay: 0.4)
        }
        await assistant.loadModels()
        let task = Task { await assistant.send("Test", library: library) }
        try await Task.sleep(for: .milliseconds(80))
        assistant.clearConversation()
        await task.value
        XCTAssertTrue(assistant.messages.isEmpty)
        XCTAssertFalse(assistant.isLoading)
        AIProtocol.handle { _ in XCTFail("Native search must not use the assistant or Mac gateway"); return .init(body: [:]) }
        await assistant.search("Test")
        XCTAssertEqual(assistant.searchResults.count, 1)
        XCTAssertEqual(assistant.searchResults.first?.title, "Real")
    }

    func testAtomicPlaylistRejectsMissingTracksWithoutWriting() throws {
        let (_, library, _, _) = try setupStores()
        XCTAssertThrowsError(try library.createPlaylist(name: "Missing", trackIDs: [UUID()]))
        XCTAssertTrue(library.playlists.isEmpty)
    }

    func testMissingConnectionIsActionableAndMissingDefaultDoesNotChooseAnotherModel() async throws {
        let (_, _, directory, session) = try setupStores()
        let missing = AIAssistantStore(directory: directory, session: session, connection: .empty, tokenProvider: { "" })
        AIProtocol.handle { _ in XCTFail("An invalid endpoint must not send a request"); return .init(body: [:]) }
        await missing.loadModels()
        XCTAssertTrue(missing.errorMessage?.contains("HTTPS") == true)
        var settings = connection
        settings.defaultModelID = nil
        let configured = AIAssistantStore(directory: directory, session: session, connection: settings, tokenProvider: { "test-token" })
        AIProtocol.handle { _ in .init(body: ["data": [["id": "second"]]]) }
        await configured.loadModels()
        XCTAssertEqual(configured.models.count, 1)
        XCTAssertEqual(configured.selectedModelID, "")
        XCTAssertTrue(configured.errorMessage?.contains("modeli seç") == true)
    }

    func testConnectionRejectsPlainHTTPEmbeddedCredentialsQueriesAndHeaderInjection() throws {
        for address in ["http://localhost:8765", "http://example.com/v1", "https://user:pass@example.com/v1", "https://example.com/v1?key=secret", "https://example.com/v1#fragment"] {
            XCTAssertThrowsError(try AIConnectionSettings(baseURL: address).validatedURL())
        }
        var value = connection
        value.authHeader = "Host"
        XCTAssertThrowsError(try value.validatedURL())
        value.authHeader = "X-Personal-Token"
        value.authScheme = "Bearer\r\nBad"
        XCTAssertThrowsError(try value.validatedURL())
    }

    func testCredentialIsBoundToEndpointAndNotSerializedIntoSettings() throws {
        var value = connection
        value.baseURL = "https://\(UUID().uuidString.lowercased()).example.invalid/v1"
        try AssistantCredentials.save("fixture-key", for: value)
        defer { try? AssistantCredentials.save("", for: value) }
        XCTAssertEqual(AssistantCredentials.read(for: value), "fixture-key")
        var changed = value
        changed.baseURL += "/other"
        XCTAssertEqual(AssistantCredentials.read(for: changed), "")
        let encoded = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        XCTAssertFalse(encoded.contains("fixture-key"))
        XCTAssertFalse(encoded.contains("api_key"))
    }

    func testReplyNormalizationRejectsBadJSONFiltersUnknownIDsAndURLSuggestions() throws {
        let id = UUID()
        let content = """
        ```json
        {"reply":"Merhaba","playlist":{"name":" ","track_ids":["\(id)","\(UUID())","\(id)","invalid"]},"search_queries":[" Adele  Easy ","Adele Easy","https://evil.invalid","www.bad.invalid","Radiohead"]}
        ```
        """
        let reply = try DirectAIClient.normalize(content, model: "first", allowedIDs: [id])
        XCTAssertEqual(reply.playlist?.trackIDs, [id])
        XCTAssertEqual(reply.playlist?.name, "Ritim önerisi")
        XCTAssertEqual(reply.searchQueries, ["Adele Easy", "Radiohead"])
        for bad in ["plain text", "{}", "{\"reply\":\"\"}", "{\"reply\":\"x\",\"search_queries\":[2]}"] {
            XCTAssertThrowsError(try DirectAIClient.normalize(bad, model: "first", allowedIDs: []))
        }
    }
}
