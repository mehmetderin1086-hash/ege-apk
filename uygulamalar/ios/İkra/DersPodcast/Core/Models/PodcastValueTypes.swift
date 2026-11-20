import Foundation

/// #47: üretim süresi ve maliyet kartı.
nonisolated struct GenerationStats: Codable, Hashable, Sendable {
    var engine: String
    var scriptModel: String?
    var startedAt: Date
    var scriptSeconds: Double?
    var voiceSeconds: Double?
    var mixSeconds: Double?
    var characters: Int
    var scenes: Int
    var retakes: Int
    var estimatedCostUSD: Double
}

/// #13: kalite kapısından ikinci kez geçemeyen sahne (küresel sahne indeksi).
nonisolated struct AudioIssue: Codable, Hashable, Sendable {
    var scene: Int
    var reasons: [String]
}

/// #22/#33: çalınacak kesit.
nonisolated struct PodcastClip: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var episodeID: UUID
    var start: Double
    var end: Double
    var reason: String
    var questionKey: String?
}

/// #41/#46: oynatma kuyruğu öğesi. `.audio` dosyası `BriefingFiles.directory` altındadır.
nonisolated enum PlaybackQueueItem: Codable, Hashable, Sendable {
    case episode(UUID)
    case audio(fileName: String, title: String)
}

/// #6: kaynak sayfa metni (1 tabanlı sayfa).
nonisolated struct PageText: Codable, Hashable, Sendable {
    var page: Int
    var text: String
}

/// #35: konu ağacı etiketi.
nonisolated struct TopicTag: Codable, Hashable, Sendable {
    var subject: String
    var unit: String
    var topic: String
    var chapterIndex: Int?
}

nonisolated enum BriefingFiles {
    static var directory: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Briefings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
