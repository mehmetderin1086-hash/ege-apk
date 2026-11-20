import Foundation
import Combine

struct AIModel: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let provider: String
    var availability: String?
    var note: String?

    var providerGroup: String {
        if id.hasPrefix("antigravity-") { return "Antigravity" }
        if id.hasPrefix("gpt-") { return "ChatGPT" }
        if id.hasPrefix("claude-") { return "Claude" }
        if id.hasPrefix("gemini-") { return "Gemini" }
        if id.hasPrefix("qwen") { return "Qwen" }
        return provider
    }
}

struct AIPlaylistProposal: Codable, Equatable {
    let name: String
    let trackIDs: [UUID]
    enum CodingKeys: String, CodingKey { case name; case trackIDs = "track_ids" }
}

struct AIMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    let role: String
    let content: String
    var model: String?
    var playlist: AIPlaylistProposal?
    var searchQueries: [String] = []
    var action: AIAction = .none
    /// What the app actually did for this reply, shown under the message.
    var appliedNote: String?
    var createdAt = Date()

    init(role: String, content: String, model: String? = nil, playlist: AIPlaylistProposal? = nil,
         searchQueries: [String] = [], action: AIAction = .none, appliedNote: String? = nil) {
        self.role = role; self.content = content; self.model = model; self.playlist = playlist
        self.searchQueries = searchQueries; self.action = action; self.appliedNote = appliedNote
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try c.decode(String.self, forKey: .role)
        content = try c.decode(String.self, forKey: .content)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        playlist = try c.decodeIfPresent(AIPlaylistProposal.self, forKey: .playlist)
        searchQueries = try c.decodeIfPresent([String].self, forKey: .searchQueries) ?? []
        action = try c.decodeIfPresent(AIAction.self, forKey: .action) ?? .none
        appliedNote = try c.decodeIfPresent(String.self, forKey: .appliedNote)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

/// A running AI DJ set. The store extends the queue before it runs out.
struct AIDJSession: Equatable {
    let mood: String
    var note: String
    var trackIDs: [UUID]
    var played: Set<UUID> = []
    var isExtending = false
    var extensions = 0
}

private final class AIServiceDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // An authenticated service never needs redirects; keep the pairing key at its original endpoint.
        completionHandler(nil)
    }
}

@MainActor
final class AIAssistantStore: ObservableObject {
    @Published private(set) var models: [AIModel] = []
    @Published var selectedModelID = "" { didSet { saveSelection() } }
    @Published private(set) var messages: [AIMessage] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingModels = false
    @Published var errorMessage: String?
    @Published private(set) var searchResults: [PlaylistItem] = []
    @Published private(set) var isSearching = false
    @Published private(set) var searchQuery: String?
    /// Every query behind the current results: the user's own first, then the model's similar ones.
    @Published private(set) var searchQueries: [String] = []
    /// Which query surfaced each result (video id → query).
    @Published private(set) var searchSources: [String: String] = [:]
    @Published private(set) var isExpandingSearch = false
    @Published private(set) var searchNote: String?
    @Published var actionMessage: String?
    @Published private(set) var dj: AIDJSession?
    @Published private(set) var djLoading = false
    @Published var djMessage: String?
    @Published private(set) var insights: [UUID: AITrackInsight] = [:]
    @Published private(set) var insightLoading: UUID?
    @Published var insightError: String?
    @Published private(set) var dailyMix: AIDailyMix?
    @Published private(set) var dailyLoading = false
    @Published var dailyError: String?
    @Published var proactiveEnabled = true { didSet { if oldValue != proactiveEnabled { saveSelection() } } }
    var selectedModel: AIModel? { models.first { $0.id == selectedModelID } }
    /// The assistant can act now: a model is chosen and a key exists.
    var isReady: Bool { selectedModel != nil && hasAccessToken }

    @Published private(set) var connection: AIConnectionSettings
    private let client: AIChatting
    private let tokenProvider: (() -> String)?
    private let searchProvider: (String) async throws -> [PlaylistItem]
    var hasAccessToken: Bool { !accessToken.isEmpty }
    private var accessToken: String { tokenProvider?() ?? AssistantCredentials.read(for: connection) }
    private let settingsURL: URL
    private var chatTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var catalogGeneration = UUID()
    private var chatGeneration = UUID()
    private var searchGeneration = UUID()
    private var createdLists: [String: UUID] = [:]
    private let historyURL: URL
    private let insightsURL: URL
    private let dailyURL: URL
    private let exclusionsURL: URL
    @Published private(set) var excludedTrackIDs: Set<UUID> = []
    private var djGeneration = UUID()
    private var insightGeneration = UUID()
    private var dailyGeneration = UUID()
    private var djObservation: AnyCancellable?
    /// Automatic daily requests back off after a failure instead of retrying on every visit.
    private var lastAutomaticDailyAttempt: Date?
    private var restoringSettings = false
    private struct Settings: Codable { let selectedModelID: String; var proactiveEnabled: Bool? }
    init(directory: URL, session: URLSession? = nil, connection: AIConnectionSettings? = nil,
         tokenProvider: (() -> String)? = nil, searchProvider: ((String) async throws -> [PlaylistItem])? = nil,
         client: AIChatting? = nil) {
        let restored = UserDefaults.standard.data(forKey: AIConnectionSettings.storageKey)
            .flatMap { try? JSONDecoder().decode(AIConnectionSettings.self, from: $0) }
        self.connection = connection ?? restored ?? .empty
        self.tokenProvider = tokenProvider
        self.searchProvider = searchProvider ?? { try await NativeYouTubeCatalog().search(query: $0, limit: 50) }
        settingsURL = directory.appendingPathComponent("assistant-settings.json")
        historyURL = directory.appendingPathComponent("assistant-history.json")
        insightsURL = directory.appendingPathComponent("assistant-insights.json")
        dailyURL = directory.appendingPathComponent("assistant-daily.json")
        exclusionsURL = directory.appendingPathComponent("assistant-exclusions.json")
        if let data = try? Data(contentsOf: exclusionsURL), let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data) { excludedTrackIDs = ids }
        let apiSession: URLSession
        if let session { apiSession = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 160
            configuration.timeoutIntervalForResource = 180
            configuration.urlCache = nil
            apiSession = URLSession(configuration: configuration, delegate: AIServiceDelegate(), delegateQueue: nil)
        }
        self.client = client ?? DirectAIClient(session: apiSession)
        if let data = try? Data(contentsOf: settingsURL), let settings = try? JSONDecoder().decode(Settings.self, from: data) {
            restoringSettings = true
            selectedModelID = settings.selectedModelID
            proactiveEnabled = settings.proactiveEnabled ?? true
            restoringSettings = false
        }
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: historyURL), let saved = try? decoder.decode([AIMessage].self, from: data) {
            messages = Array(saved.suffix(40))
        }
        if let data = try? Data(contentsOf: insightsURL), let saved = try? decoder.decode([AITrackInsight].self, from: data) {
            insights = Dictionary(saved.map { ($0.trackID, $0) }, uniquingKeysWith: { first, _ in first })
        }
        if let data = try? Data(contentsOf: dailyURL), let saved = try? decoder.decode(AIDailyMix.self, from: data) {
            dailyMix = saved
        }
        #if DEBUG
        // Provisioning is injected by the pairing tool; no credential is in the bundle or settings JSON.
        if connection == nil, let raw = ProcessInfo.processInfo.environment["RITIM_AI_CONFIGURATION"],
           let data = raw.data(using: .utf8) {
            do {
                let imported = try JSONDecoder().decode(AIConnectionSettings.self, from: data)
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let token = object?["api_key"] as? String, !token.isEmpty else {
                    throw RitimError.message("Asistan eşleştirme anahtarı eksik.")
                }
                try updateConnection(imported, token: token)
            } catch { errorMessage = "Asistan bağlantısı güvenli alana kaydedilemedi." }
        }
        #endif
    }

    func updateConnection(_ value: AIConnectionSettings, token: String?) throws {
        _ = try value.validatedURL()
        let changed = value.credentialAccount != connection.credentialAccount
        if let token {
            try AssistantCredentials.save(token.trimmingCharacters(in: .whitespacesAndNewlines), for: value)
        } else if changed {
            throw RitimError.message("Yeni asistan adresinin erişim anahtarını gir.")
        }
        let encoded = try JSONEncoder().encode(value)
        UserDefaults.standard.set(encoded, forKey: AIConnectionSettings.storageKey)
        cancel(); stopDJ(); cancelInsight()
        dailyGeneration = UUID(); dailyLoading = false
        catalogGeneration = UUID()
        isLoadingModels = false
        connection = value
        models = []
        errorMessage = nil
    }

    func loadModels() async {
        guard !isLoadingModels else { return }
        isLoadingModels = true
        let generation = UUID(); catalogGeneration = generation
        let requestedConnection = connection
        defer { if catalogGeneration == generation { isLoadingModels = false } }
        do {
            let available = try await client.models(connection: requestedConnection, token: accessToken)
            try Task.checkCancellation()
            guard catalogGeneration == generation else { return }
            models = available
            if selectedModelID.isEmpty { selectedModelID = connection.defaultModelID ?? "" }
            if selectedModel == nil { errorMessage = "Kullanmak istediğin modeli seç. Önceki seçimin şu an listede olmayabilir." }
            else { errorMessage = nil }
        } catch {
            guard catalogGeneration == generation, !Task.isCancelled else { return }
            errorMessage = friendly(error)
        }
    }

    func send(_ prompt: String, library: LibraryStore, playback: PlaybackStore? = nil) async {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isLoading, !text.isEmpty else { return }
        guard text.count <= 4000 else { errorMessage = "Mesajını 4.000 karakterle sınırla."; return }
        guard selectedModel != nil else { errorMessage = "Önce kullanılabilir bir model seç."; return }
        let model = selectedModelID
        let tracks = Array(library.tracks.filter { !excludedTrackIDs.contains($0.id) }.prefix(500))
        // Repeating a failed request should not duplicate the last user message.
        if messages.last?.role == "user", messages.last?.content == text { messages.removeLast() }
        let history = messages.suffix(12).map { ["role": $0.role, "content": String($0.content.prefix(4000))] }
        let trackData = Self.trackPayload(tracks)
        let context = AIContextBuilder.make(library: library.tracks, playlists: library.playlists,
                                            current: playback?.current, queue: playback?.queue ?? [])
        messages.append(AIMessage(role: "user", content: text))
        if messages.count > 40 { messages.removeFirst(messages.count - 40) }
        errorMessage = nil; actionMessage = nil; isLoading = true
        let generation = UUID(); chatGeneration = generation
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if self.chatGeneration == generation { self.isLoading = false; self.chatTask = nil } }
            do {
                let reply = try await self.client.chat(connection: self.connection, token: self.accessToken,
                                                       model: model, prompt: text, history: history, tracks: trackData,
                                                       context: context, task: .chat)
                try Task.checkCancellation()
                guard self.chatGeneration == generation else { return }
                guard reply.model == model else { throw RitimError.message("Sunucu farklı bir model döndürdü. Yanıt kullanılmadı; modeli kontrol et.") }
                let allowed = Set(tracks.map(\.id)).intersection(library.tracks.map(\.id))
                var proposal: AIPlaylistProposal?
                if let candidate = reply.playlist {
                    var seen = Set<UUID>()
                    let ids = candidate.trackIDs.filter { allowed.contains($0) && seen.insert($0).inserted }
                    if !ids.isEmpty {
                        proposal = AIPlaylistProposal(name: String(candidate.name.prefix(80)), trackIDs: Array(ids.prefix(100)))
                    }
                }
                let action = proposal == nil ? AIAction.none : reply.action
                var note: String?
                if let proposal, let playback, action != .none {
                    note = self.apply(action, proposal: proposal, library: library, playback: playback)
                }
                self.messages.append(AIMessage(role: "assistant", content: String(reply.reply.prefix(12000)), model: model,
                                               playlist: proposal, searchQueries: Array(reply.searchQueries.prefix(3)).map { String($0.prefix(160)) },
                                               action: action, appliedNote: note))
                self.saveHistory()
                self.markModel(model, ok: true)
                // "YouTube'da … bul/indir" runs the proposed searches right away; results stay selectable for download.
                if Self.wantsYouTubeSearch(text), !reply.searchQueries.isEmpty {
                    let queries = Array(reply.searchQueries.prefix(3))
                    Task { [weak self] in await self?.searchAll(queries) }
                }
            } catch {
                guard self.chatGeneration == generation, !Task.isCancelled else { return }
                self.markModel(model, ok: false)
                self.errorMessage = self.friendly(error)
            }
        }
        chatTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    func excludeRecommendation(_ ids: [UUID]) {
        let before = excludedTrackIDs
        excludedTrackIDs.formUnion(ids)
        do { try JSONEncoder().encode(excludedTrackIDs).write(to: exclusionsURL, options: .atomic) }
        catch { excludedTrackIDs = before; errorMessage = "Öneri tercihi kaydedilemedi." }
    }
    func resetRecommendationExclusions() {
        let before = excludedTrackIDs
        excludedTrackIDs = []
        do { try JSONEncoder().encode(excludedTrackIDs).write(to: exclusionsURL, options: .atomic) }
        catch { excludedTrackIDs = before; errorMessage = "Öneri tercihi kaydedilemedi." }
    }

    func cancel() {
        chatGeneration = UUID(); chatTask?.cancel(); chatTask = nil; isLoading = false
        searchGeneration = UUID(); searchTask?.cancel(); searchTask = nil; isSearching = false
    }

    func clearConversation() {
        cancel(); messages = []; clearSearch(); errorMessage = nil; actionMessage = nil; createdLists = [:]
        if FileManager.default.fileExists(atPath: historyURL.path) {
            do { try FileManager.default.removeItem(at: historyURL) }
            catch { errorMessage = "Sohbet geçmişi cihazdan silinemedi. Tekrar dene." }
        }
    }

    /// Searches YouTube for exactly this text.
    func search(_ query: String) async {
        await runSearch(queries: [query], expandFrom: nil)
    }

    /// Searches YouTube for the text and, when a model is ready, for similar searches it proposes.
    /// Results from the user's own query appear first and arrive before the model answers.
    func discover(_ query: String, library: LibraryStore) async {
        await runSearch(queries: [query], expandFrom: library)
    }

    var canFindMore: Bool {
        !isSearching && searchQuery?.isEmpty == false && searchResults.count < Self.maxSearchResults && !nextMoreQueries().isEmpty
    }

    private func nextMoreQueries() -> [String] {
        guard let base = searchQuery else { return [] }
        let used = Set(searchQueries.map { $0.lowercased() })
        return Self.moreSuffixes.map { "\(base) \($0)" }.filter { !used.contains($0.lowercased()) }
    }

    /// Searches three more angles of the same query and appends what is new.
    func findMore() async {
        guard canFindMore else { return }
        let queries = Array(nextMoreQueries().prefix(3))
        let generation = searchGeneration
        isSearching = true
        defer { isSearching = false }
        searchQueries += queries
        let provider = searchProvider
        let batches = await withTaskGroup(of: (Int, [PlaylistItem]).self) { group in
            for (index, query) in queries.enumerated() { group.addTask { (index, (try? await provider(query)) ?? []) } }
            var found: [Int: [PlaylistItem]] = [:]
            for await (index, items) in group { found[index] = items }
            return found
        }
        guard searchGeneration == generation else { return }
        for (index, query) in queries.enumerated() { appendResults(batches[index] ?? [], from: query, limit: 20, generation: generation) }
    }

    /// Runs several searches (e.g. those a chat reply proposed) as one result list.
    func searchAll(_ queries: [String]) async {
        await runSearch(queries: queries, expandFrom: nil)
    }

    static let maxSearchResults = 200
    /// Extra angles for "daha fazla bul"; each round uses the next unused ones.
    private static let moreSuffixes = ["canlı", "akustik", "remix", "cover", "tam albüm", "klip", "en iyi", "yeni"]

    nonisolated static func wantsYouTubeSearch(_ prompt: String) -> Bool {
        let words = prompt.lowercased(with: Locale(identifier: "tr_TR"))
            .components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        return words.contains { word in
            ["youtube", "ara", "arat", "bul", "keşfet", "video", "klip"].contains(word)
                || ["youtube", "indir", "videosu", "videoları", "klibi", "aranacak"].contains { word.hasPrefix($0) }
        }
    }

    private func runSearch(queries input: [String], expandFrom library: LibraryStore?) async {
        var seenQueries = Set<String>()
        let queries = input.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)) }
            .filter { !$0.isEmpty && seenQueries.insert($0.lowercased()).inserted }
        guard let primary = queries.first else { return }
        searchTask?.cancel()
        let generation = UUID(); searchGeneration = generation
        let expand = library != nil && isReady
        isSearching = true; errorMessage = nil; searchQuery = primary; searchResults = []
        searchQueries = queries; searchSources = [:]; searchNote = nil; isExpandingSearch = expand
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if self.searchGeneration == generation { self.isSearching = false; self.isExpandingSearch = false; self.searchTask = nil } }
            async let similar: [String] = expand ? self.similarQueries(for: primary, library: library!) : []
            var firstError: Error?
            do {
                self.appendResults(try await self.searchProvider(primary), from: primary, limit: 50, generation: generation)
            } catch { firstError = error }
            guard !Task.isCancelled, self.searchGeneration == generation else { return }
            let proposed = await similar
            guard !Task.isCancelled, self.searchGeneration == generation else { return }
            self.isExpandingSearch = false
            var seen = Set(queries.prefix(1).map { $0.lowercased() })
            let extra = (Array(queries.dropFirst()) + proposed).filter { seen.insert($0.lowercased()).inserted }.prefix(4)
            if !proposed.isEmpty { self.searchQueries = queries + proposed.filter { query in !queries.contains { $0.caseInsensitiveCompare(query) == .orderedSame } } }
            // Similar searches run together; each keeps its own place so the list order is stable.
            let batches = await withTaskGroup(of: (Int, [PlaylistItem]?).self) { group in
                for (index, query) in extra.enumerated() {
                    let provider = self.searchProvider
                    group.addTask { (index, try? await provider(query)) }
                }
                var found: [Int: [PlaylistItem]] = [:]
                for await (index, items) in group { found[index] = items ?? [] }
                return found
            }
            guard !Task.isCancelled, self.searchGeneration == generation else { return }
            for (index, query) in extra.enumerated() {
                self.appendResults(batches[index] ?? [], from: query, limit: 20, generation: generation)
            }
            if self.searchResults.isEmpty, let firstError { self.errorMessage = self.friendly(firstError) }
        }
        searchTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    private func appendResults(_ items: [PlaylistItem], from query: String, limit: Int, generation: UUID) {
        guard searchGeneration == generation else { return }
        var known = Set(searchResults.map(\.url))
        var added = 0
        for item in items where added < limit && searchResults.count < Self.maxSearchResults {
            guard let url = try? MediaURLPolicy.canonicalInput(item.url), MediaURLPolicy.isYouTube(url), known.insert(url.absoluteString).inserted else { continue }
            var validated = item; validated.url = url.absoluteString; validated.index = searchResults.count
            searchResults.append(validated); searchSources[item.id] = query; added += 1
        }
    }

    /// The model's similar searches; an empty list (with a note) when it is unavailable.
    private func similarQueries(for query: String, library: LibraryStore) async -> [String] {
        guard let model = selectedModel?.id, hasAccessToken else { return [] }
        let context = AIContextBuilder.make(library: library.tracks, playlists: library.playlists, current: nil, queue: [], exclude: [])
        do {
            let reply = try await client.chat(connection: connection, token: accessToken, model: model, prompt: query, history: [],
                                              tracks: Self.trackPayload(Array(library.tracks.prefix(150))), context: context, task: .discover)
            guard reply.model == model else {
                searchNote = "Sunucu farklı bir model döndürdü; yalnız senin araman gösteriliyor."
                return []
            }
            markModel(model, ok: true)
            let proposed = reply.searchQueries.map { String($0.prefix(160)) }
                .filter { $0.caseInsensitiveCompare(query) != .orderedSame && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if proposed.isEmpty { searchNote = "Yapay zekâ benzer arama önermedi." }
            return Array(proposed.prefix(3))
        } catch {
            if !(error is CancellationError) && !Task.isCancelled {
                markModel(model, ok: false)
                searchNote = "Yapay zekâ benzer arama öneremedi; yalnız senin araman gösteriliyor."
            }
            return []
        }
    }

    func clearSearch() {
        searchGeneration = UUID(); searchTask?.cancel(); searchTask = nil; isSearching = false; isExpandingSearch = false
        searchResults = []; searchQuery = nil; searchQueries = []; searchSources = [:]; searchNote = nil
    }

    func createPlaylist(_ proposal: AIPlaylistProposal, library: LibraryStore) {
        let key = proposal.name + proposal.trackIDs.map(\.uuidString).joined()
        if let id = createdLists[key], library.playlists.contains(where: { $0.id == id }) {
            actionMessage = "Bu liste kitaplığına zaten eklendi."; return
        }
        do {
            let playlist = try library.createPlaylist(name: proposal.name, trackIDs: proposal.trackIDs)
            createdLists[key] = playlist.id
            actionMessage = "\(playlist.name) · \(playlist.trackIDs.count) parça kitaplığına eklendi."
        } catch { errorMessage = error.localizedDescription }
    }

    private func saveSelection() {
        guard !restoringSettings else { return }
        do {
            try JSONEncoder().encode(Settings(selectedModelID: selectedModelID, proactiveEnabled: proactiveEnabled))
                .write(to: settingsURL, options: .atomic)
        } catch { errorMessage = "Model seçimi kaydedilemedi." }
    }

    // MARK: - Proactive AI features

    /// Runs one request for a feature and validates it the same way chat replies are validated.
    private func featureRequest(_ task: AITask, prompt: String, library: LibraryStore, playback: PlaybackStore?,
                                exclude: [UUID] = []) async throws -> (AIChatReply, AIPlaylistProposal?) {
        guard let model = selectedModel?.id else { throw RitimError.message("Önce Asistan sekmesinden bir model seç.") }
        guard hasAccessToken else { throw RitimError.message("Asistan bağlantısına erişim anahtarını ekle.") }
        let tracks = Array(library.tracks.filter { !excludedTrackIDs.contains($0.id) }.prefix(500))
        guard !tracks.isEmpty else { throw RitimError.message("Önce kitaplığına parça ekle.") }
        let context = AIContextBuilder.make(library: library.tracks, playlists: library.playlists,
                                            current: playback?.current, queue: playback?.queue ?? [], exclude: Array(Set(exclude).union(excludedTrackIDs)))
        do {
            let reply = try await client.chat(connection: connection, token: accessToken, model: model, prompt: prompt,
                                              history: [], tracks: Self.trackPayload(tracks), context: context, task: task)
            try Task.checkCancellation()
            guard reply.model == model else { throw RitimError.message("Sunucu farklı bir model döndürdü. Yanıt kullanılmadı; modeli kontrol et.") }
            let allowed = Set(library.tracks.map(\.id)).subtracting(exclude).subtracting(excludedTrackIDs)
            var proposal: AIPlaylistProposal?
            if let candidate = reply.playlist {
                var seen = Set<UUID>()
                let ids = candidate.trackIDs.filter { allowed.contains($0) && seen.insert($0).inserted }
                if !ids.isEmpty { proposal = AIPlaylistProposal(name: String(candidate.name.prefix(80)), trackIDs: Array(ids.prefix(100))) }
            }
            markModel(model, ok: true)
            return (reply, proposal)
        } catch {
            if !(error is CancellationError) && !Task.isCancelled { markModel(model, ok: false) }
            throw error
        }
    }

    /// Starts an AI DJ set: the model picks an ordered set, the app plays it and keeps it going.
    func startDJ(mood: String, library: LibraryStore, playback: PlaybackStore) async {
        let text = String(mood.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !text.isEmpty, !djLoading else { return }
        stopDJ()
        let generation = UUID(); djGeneration = generation
        djLoading = true; djMessage = nil
        defer { if djGeneration == generation { djLoading = false } }
        do {
            let (reply, proposal) = try await featureRequest(.dj, prompt: text, library: library, playback: playback)
            guard djGeneration == generation else { return }
            guard let proposal else { djMessage = "Model bu ruh hâline uygun parça seçemedi. Başka bir ruh hâli dene."; return }
            let tracks = proposal.trackIDs.compactMap { id in library.tracks.first { $0.id == id } }
            guard let first = tracks.first else { return }
            playback.shuffleEnabled = false
            playback.play(first, in: tracks)
            dj = AIDJSession(mood: text, note: String(reply.reply.prefix(400)), trackIDs: tracks.map(\.id), played: [first.id])
            observeDJ(library: library, playback: playback)
            // A short set may already be near its end; extend without waiting for a track change.
            extendDJIfNeeded(library: library, playback: playback)
        } catch {
            guard djGeneration == generation, !Task.isCancelled else { return }
            djMessage = friendly(error)
        }
    }

    func stopDJ() {
        djGeneration = UUID(); djObservation = nil; dj = nil; djLoading = false
    }

    private func observeDJ(library: LibraryStore, playback: PlaybackStore) {
        // Library edits republish the same track (play counts); only a real track change counts.
        djObservation = playback.$current.removeDuplicates { $0?.id == $1?.id }.dropFirst().receive(on: DispatchQueue.main).sink { [weak self, weak library, weak playback] current in
            guard let self, let library, let playback, var session = self.dj else { return }
            guard let current else { return }
            // Playing something outside the set hands control back to the listener.
            guard session.trackIDs.contains(current.id) else {
                self.stopDJ(); self.djMessage = "Başka bir parça seçtin; AI DJ durdu."; return
            }
            session.played.insert(current.id)
            self.dj = session
            self.extendDJIfNeeded(library: library, playback: playback)
        }
    }

    /// Two tracks of headroom leave time for a slow model before the set runs dry.
    private func extendDJIfNeeded(library: LibraryStore, playback: PlaybackStore) {
        guard let session = dj, !session.isExtending, session.extensions < 20, let current = playback.current else { return }
        let index = playback.queue.firstIndex { $0.id == current.id } ?? 0
        if playback.queue.count - index - 1 <= 2 { Task { await self.extendDJ(library: library, playback: playback) } }
    }

    /// Queues tracks next; while a DJ set runs they join the set so playing them does not stop it.
    func queueNext(_ tracks: [MediaTrack], playback: PlaybackStore) {
        tracks.reversed().forEach { playback.enqueueNext($0) }
        if var session = dj {
            session.trackIDs += tracks.map(\.id).filter { !session.trackIDs.contains($0) }
            dj = session
        }
    }

    /// Appends new picks before the set runs out. Never repeats tracks from this set.
    func extendDJ(library: LibraryStore, playback: PlaybackStore) async {
        guard var session = dj, !session.isExtending, session.extensions < 20 else { return }
        session.isExtending = true; dj = session
        let generation = djGeneration
        do {
            let (reply, proposal) = try await featureRequest(.djContinue, prompt: session.mood, library: library,
                                                             playback: playback, exclude: session.trackIDs)
            guard djGeneration == generation, var latest = dj else { return }
            latest.isExtending = false
            // The set or queue may have changed while the model answered (chat, AI note); never re-add those.
            let taken = Set(latest.trackIDs).union(playback.queue.map(\.id))
            let added = (proposal?.trackIDs ?? []).filter { !taken.contains($0) }
                .compactMap { id in library.tracks.first { $0.id == id } }
            if added.isEmpty {
                latest.extensions = 20
                dj = latest
                djMessage = "Kitaplığında bu hava için yeni parça kalmadı. Set bitince DJ duracak."
                return
            }
            // If the last track already finished while waiting, playback stopped at its end: continue the set.
            let finished = !playback.isPlaying && playback.duration > 0 && playback.elapsed >= playback.duration - 0.5
                && playback.queue.last?.id == playback.current?.id
            added.forEach { playback.enqueue($0) }
            latest.trackIDs += added.map(\.id)
            latest.extensions += 1
            latest.note = String(reply.reply.prefix(400))
            dj = latest
            if finished { playback.next() }
        } catch {
            guard djGeneration == generation, var latest = dj else { return }
            latest.isExtending = false; dj = latest
            djMessage = friendly(error)
        }
    }

    /// A short note about the playing track plus similar picks from the library.
    func loadInsight(for track: MediaTrack, library: LibraryStore, playback: PlaybackStore?, force: Bool = false) async {
        if !force, insights[track.id] != nil { return }
        guard insightLoading != track.id else { return }
        let generation = UUID(); insightGeneration = generation
        insightLoading = track.id; insightError = nil
        defer { if insightGeneration == generation { insightLoading = nil } }
        let prompt = "Şimdi çalan parça: \(track.title) — \(track.artist)"
        do {
            let (reply, proposal) = try await featureRequest(.insight, prompt: String(prompt.prefix(500)), library: library,
                                                             playback: playback, exclude: [track.id])
            guard insightGeneration == generation else { return }
            insights[track.id] = AITrackInsight(trackID: track.id, text: String(reply.reply.prefix(1200)),
                                                similarIDs: Array((proposal?.trackIDs ?? []).prefix(5)),
                                                searchQueries: Array(reply.searchQueries.prefix(3)),
                                                model: reply.model, createdAt: Date())
            saveInsights()
        } catch {
            guard insightGeneration == generation, !Task.isCancelled else { return }
            insightError = friendly(error)
        }
    }

    func cancelInsight() { insightGeneration = UUID(); insightLoading = nil }

    /// Called from the home screen. Loads the catalog when needed and refreshes the
    /// daily mix at most once per day unless the listener asks for a new one.
    func prepareProactive(library: LibraryStore, playback: PlaybackStore?) async {
        guard proactiveEnabled, hasAccessToken, !library.tracks.isEmpty else { return }
        if dailyMix?.isFresh() == true { return }
        if let last = lastAutomaticDailyAttempt, Date().timeIntervalSince(last) < 30 * 60 { return }
        if models.isEmpty { await loadModels() }
        guard selectedModel != nil else { return }
        lastAutomaticDailyAttempt = Date()
        await refreshDaily(library: library, playback: playback)
    }

    func refreshDaily(library: LibraryStore, playback: PlaybackStore?) async {
        guard !dailyLoading else { return }
        let generation = UUID(); dailyGeneration = generation
        dailyLoading = true; dailyError = nil
        defer { if dailyGeneration == generation { dailyLoading = false } }
        let part = AIDayPart(date: Date())
        do {
            let (reply, proposal) = try await featureRequest(.daily, prompt: "Bugünün \(part.rawValue) karışımı", library: library, playback: playback)
            guard dailyGeneration == generation else { return }
            guard let proposal else { dailyError = "Model bugün için liste seçemedi. Yeniden dene."; return }
            dailyMix = AIDailyMix(title: proposal.name, note: String(reply.reply.prefix(400)), trackIDs: proposal.trackIDs,
                                  model: reply.model, createdAt: Date(), dayPart: part.rawValue)
            if let data = try? JSONEncoder().encode(dailyMix) { try? data.write(to: dailyURL, options: .atomic) }
        } catch {
            guard dailyGeneration == generation, !Task.isCancelled else { return }
            dailyError = friendly(error)
        }
    }

    /// Applies a local playback action and returns what happened, for the message footer.
    private func apply(_ action: AIAction, proposal: AIPlaylistProposal, library: LibraryStore, playback: PlaybackStore) -> String? {
        let tracks = proposal.trackIDs.compactMap { id in library.tracks.first { $0.id == id } }
        guard let first = tracks.first else { return nil }
        switch action {
        case .none: return nil
        case .play:
            if dj != nil { stopDJ() }
            playback.play(first, in: tracks)
            return "Çalmaya başladı · \(tracks.count) parça"
        case .queueNext:
            queueNext(tracks, playback: playback)
            return "Sıradaki olarak eklendi · \(tracks.count) parça"
        }
    }

    private func markModel(_ model: String, ok: Bool) {
        if let index = models.firstIndex(where: { $0.id == model }) { models[index].availability = ok ? "verified" : "error" }
    }

    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(Array(messages.suffix(40)))
            try data.write(to: historyURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { actionMessage = "Sohbet bu cihaza kaydedilemedi; uygulama kapanınca kaybolabilir." }
    }

    private func saveInsights() {
        let recent = insights.values.sorted { $0.createdAt > $1.createdAt }.prefix(100)
        if recent.count < insights.count { insights = Dictionary(recent.map { ($0.trackID, $0) }, uniquingKeysWith: { first, _ in first }) }
        guard let data = try? JSONEncoder().encode(Array(recent)) else { return }
        try? data.write(to: insightsURL, options: .atomic)
    }

    static func trackPayload(_ tracks: [MediaTrack]) -> [[String: Any]] {
        tracks.map {
            ["id": $0.id.uuidString, "title": String($0.title.prefix(200)), "artist": String($0.artist.prefix(200)),
             "is_favorite": $0.isFavorite, "play_count": $0.playCount,
             "duration": $0.duration.isFinite ? $0.duration : 0]
        }
    }

    private func friendly(_ error: Error) -> String {
        if let error = error as? URLError {
            if error.code == .timedOut { return "Model zamanında yanıt vermedi. Tekrar dene veya başka model seç." }
            return "İnternete veya CLIProxy bağlantısına ulaşılamadı. iPhone’un internet bağlantısını kontrol et."
        }
        if error is DecodingError { return "Yapay zekâ yanıtı okunamadı. Tekrar dene." }
        return error.localizedDescription
    }
}
