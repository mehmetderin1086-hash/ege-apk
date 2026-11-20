import Foundation

// MARK: - /v1/figure-map

nonisolated struct FigureMapRequest: Encodable, Sendable {
    struct Fig: Encodable, Sendable { var id: String; var caption: String; var page: Int }
    struct Turn: Encodable, Sendable { var index: Int; var text: String }
    struct Chapter: Encodable, Sendable { var index: Int; var title: String; var turns: [Turn] }
    var figures: [Fig]
    var chapters: [Chapter]
}

nonisolated struct FigureMapEntry: Codable, Hashable, Sendable {
    var figureId: String
    var chapterIndex: Int
    var turnIndex: Int?
    var confidence: Double
}

nonisolated struct FigureMapResponse: Decodable, Sendable { var map: [FigureMapEntry] }

// MARK: - /v1/verify-deck

nonisolated struct VerifyDeckRequest: Encodable, Sendable {
    struct Slide: Encodable, Sendable {
        struct Stat: Encodable, Sendable { var value: String; var label: String }
        var index: Int; var title: String; var bullets: [String]?; var stat: Stat?; var table: DeckTable?
    }
    var sourceNotes: String
    var slides: [Slide]
}

nonisolated struct DeckIssue: Codable, Hashable, Sendable {
    var slideIndex: Int
    var text: String
    var kind: String
    var note: String
}

nonisolated struct VerifyDeckResponse: Decodable, Sendable { var issues: [DeckIssue] }

// MARK: - /v1/topics (#35, `learn2`)

nonisolated struct TopicsRequest: Encodable, Sendable {
    struct Chapter: Encodable, Hashable, Sendable { var i: Int; var title: String }
    struct Item: Encodable, Hashable, Sendable {
        var id: String
        var title: String
        var course: String?
        var chapters: [Chapter]
        /// ≤30
        var concepts: [String]
    }
    /// ≤60
    var episodes: [Item]
}

nonisolated struct TopicsResponse: Codable, Hashable, Sendable {
    struct Ref: Codable, Hashable, Sendable {
        var episodeId: String
        var chapter: Int?
    }
    struct Topic: Codable, Hashable, Sendable { var name: String; var refs: [Ref] }
    struct Unit: Codable, Hashable, Sendable { var name: String; var topics: [Topic] }
    struct Subject: Codable, Hashable, Sendable { var name: String; var units: [Unit] }
    struct Confusable: Codable, Hashable, Sendable {
        var a: String
        var b: String
        var why: String
        var refs: [Ref]
    }
    var subjects: [Subject]
    var confusables: [Confusable]

    init(subjects: [Subject], confusables: [Confusable]) {
        self.subjects = subjects
        self.confusables = confusables
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subjects = (try? c.decode([Subject].self, forKey: .subjects)) ?? []
        confusables = (try? c.decode([Confusable].self, forKey: .confusables)) ?? []
    }
}

extension APIClient {
    func figureMap(_ request: FigureMapRequest) async throws -> [FigureMapEntry] {
        let r: FigureMapResponse = try await post("/v1/figure-map", request)
        return r.map
    }
    func verifyDeck(_ request: VerifyDeckRequest) async throws -> [DeckIssue] {
        let r: VerifyDeckResponse = try await post("/v1/verify-deck", request)
        return r.issues
    }
    func topics(_ request: TopicsRequest) async throws -> TopicsResponse { try await post("/v1/topics", request) }
}
