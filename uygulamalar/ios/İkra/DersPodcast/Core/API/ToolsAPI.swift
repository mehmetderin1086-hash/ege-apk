import Foundation

// Yapay zekâ (Claude) tabanlı yardımcı uçlar (sunucu: /v1/extract, /v1/rewrite-scene, /v1/evaluate, /v1/verify-script, /v1/vocab, /v1/slides).

nonisolated struct ExtractImage: Encodable, Sendable {
    var data: String
    var mimeType: String
}

nonisolated struct ExtractRequest: Encodable, Sendable {
    var kind: String            // "url" | "youtube" | "audio" | "images"
    var url: String?
    var data: String?
    var mimeType: String?
    var images: [ExtractImage]?
    var handwriting: Bool?
}

nonisolated struct RewriteSettings: Encodable, Sendable {
    var level: PodcastLevel
    var tone: PodcastTone
    var format: PodcastFormat
    var language: PodcastLanguage
    var hostA: Host
    var hostB: Host
    var pace: PodcastPace?
    var depth: PodcastDepth?
    var guest: Host?
}

nonisolated struct RewriteSceneRequest: Encodable, Sendable {
    var title: String
    var sourceNotes: String
    var chapterTitle: String
    var before: String?
    var after: String?
    var scene: ScriptScene
    var instruction: String
    var settings: RewriteSettings
    var pages: [PageText]?
}

nonisolated struct RewriteSceneResponse: Decodable, Sendable { var turns: [ScriptTurn] }

nonisolated struct EvaluateRequest: Encodable, Sendable {
    var mode: String            // "answer" | "explain"
    var prompt: String
    var expected: String?
    var sourceNotes: String
    var response: String
    var language: String
}

/// `page`: turun dayandığı kaynak sayfa; sunucu her parçaya yalnız ilgili sayfaları koyar (`pagesFor`).
nonisolated struct VerifyTurn: Encodable, Sendable {
    var index: Int
    var text: String
    var page: Int? = nil

    /// Sunucu sınırı: metin ≤ 2000 UTF-16 birimi; sayfa pozitif.
    static func make(index: Int, text: String, page: Int?) -> VerifyTurn {
        VerifyTurn(index: index, text: ServerText.prefix(text, 2000), page: page.flatMap { $0 > 0 ? $0 : nil })
    }
}
nonisolated struct VerifyRequest: Encodable, Sendable { var sourceNotes: String; var turns: [VerifyTurn]; var pages: [PageText]? = nil }
nonisolated struct VerifyResponse: Decodable, Sendable { var issues: [ScriptIssue] }

nonisolated struct VocabRequest: Encodable, Sendable { var text: String; var targetLang: String; var count: Int }
nonisolated struct VocabResponse: Decodable, Sendable { var items: [VocabItem] }

nonisolated struct SlideChapter: Encodable, Sendable { var title: String; var text: String }
nonisolated struct SlidesRequest: Encodable, Sendable { var title: String; var sourceNotes: String; var chapters: [SlideChapter] }
nonisolated struct SlidesResponse: Decodable, Sendable { var slides: [LessonSlide] }

extension APIClient {
    func extract(_ request: ExtractRequest) async throws -> ExtractResult {
        try await post("/v1/extract", request)
    }

    func rewriteScene(_ request: RewriteSceneRequest) async throws -> [ScriptTurn] {
        let response: RewriteSceneResponse = try await post("/v1/rewrite-scene", request)
        return response.turns
    }

    func evaluate(_ request: EvaluateRequest) async throws -> Evaluation {
        try await post("/v1/evaluate", request)
    }

    func verifyScript(_ request: VerifyRequest) async throws -> [ScriptIssue] {
        let response: VerifyResponse = try await post("/v1/verify-script", request)
        return response.issues
    }

    func vocab(_ request: VocabRequest) async throws -> [VocabItem] {
        let response: VocabResponse = try await post("/v1/vocab", request)
        return response.items
    }

    func slides(_ request: SlidesRequest) async throws -> [LessonSlide] {
        let response: SlidesResponse = try await post("/v1/slides", request)
        return response.slides
    }
}

// MARK: - Kütüphaneye soru (öneri 12)

nonisolated struct LibraryAskChapter: Encodable, Sendable { var index: Int; var title: String }
nonisolated struct LibraryAskEpisode: Encodable, Sendable { var id: UUID; var title: String; var notes: String; var chapters: [LibraryAskChapter] }
nonisolated struct LibraryAskRequest: Encodable, Sendable { var question: String; var language: String; var episodes: [LibraryAskEpisode] }
nonisolated struct LibraryCitation: Decodable, Sendable, Hashable { var episodeId: UUID; var chapterIndex: Int?; var quote: String }
nonisolated struct LibraryAnswer: Decodable, Sendable { var answer: String; var citations: [LibraryCitation] }

// MARK: - Kişisel podcast akışı (öneri 8)

nonisolated struct FeedChapter: Encodable, Sendable { var title: String; var start: Double }
nonisolated struct FeedMetaRequest: Encodable, Sendable {
    var id: UUID; var title: String; var description: String; var durationSec: Double; var createdAt: String; var chapters: [FeedChapter]
}
nonisolated struct FeedRemoveRequest: Encodable, Sendable { var id: UUID }
nonisolated struct FeedInfo: Decodable, Sendable {
    struct Item: Decodable, Sendable { var id: UUID; var title: String; var createdAt: String }
    var feedPath: String
    var episodes: [Item]
}
nonisolated private struct OKBody: Decodable, Sendable { var ok: Bool }
nonisolated private struct Empty: Encodable, Sendable {}

extension APIClient {
    func libraryAsk(_ request: LibraryAskRequest) async throws -> LibraryAnswer {
        try await post("/v1/library-ask", request)
    }

    func feedInfo() async throws -> FeedInfo { try await post("/v1/feed/info", Empty()) }

    func feedRemove(_ id: UUID) async throws { let _: OKBody = try await post("/v1/feed/remove", FeedRemoveRequest(id: id)) }

    /// Sesi ham gövde olarak yükler (PUT), ardından meta bilgiyi gönderir.
    func feedPublish(audio: URL, meta: FeedMetaRequest) async throws {
        var request = URLRequest(url: Config.apiBaseURL.appending(path: "/v1/feed/audio/\(meta.id.uuidString.lowercased())"))
        request.httpMethod = "PUT"
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        guard let token = PersonalToken.current else { throw APIError(status: 401, code: "unauthorized", message: "Erişim anahtarı yok.") }
        request.setValue(token, forHTTPHeaderField: "X-Personal-Token")
        request.timeoutInterval = 600
        let (_, response) = try await URLSession.shared.upload(for: request, fromFile: audio)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError(status: status, code: "upload", message: "Ses akışa yüklenemedi (\(status)).")
        }
        let _: OKBody = try await post("/v1/feed/meta", meta)
    }
}
