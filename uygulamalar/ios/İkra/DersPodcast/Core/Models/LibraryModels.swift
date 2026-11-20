import Foundation
import SwiftData

/// Günlük dinleme süresi (istatistik ve seri için). `day` = yyyy-MM-dd (yerel saat).
@Model
final class ListeningDay {
    @Attribute(.unique) var day: String = ""
    var seconds: Double = 0
    var episodesData: Data?

    init(day: String) { self.day = day }

    static func key(for date: Date = .now) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Belge kütüphanesi: kullanıcının yüklediği kaynakların kalıcı kopyası.
@Model
final class SourceDocument {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    /// "pdf", "text", "image"
    var kindRaw: String = "pdf"
    var fileName: String = ""
    var pageCount: Int = 0
    var addedAt: Date = Date.now
    var lastUsedAt: Date = Date.now

    init(name: String, kind: String, fileName: String, pageCount: Int) {
        self.name = name
        kindRaw = kind
        self.fileName = fileName
        self.pageCount = pageCount
    }

    var url: URL { DocumentStore.directory.appending(path: fileName) }
}

/// Sunucuya ulaşılamazken eklenen podcast istekleri; bağlantı gelince sırayla üretilir.
@Model
final class QueuedRequest {
    @Attribute(.unique) var id: UUID = UUID()
    var createdAt: Date = Date.now
    var documentIDs: [UUID] = []
    var settingsData: Data = Data()
    var title: String = ""
    var lastError: String?
    var attempts: Int = 0
    /// #3: sunucudaki senaryo işi; nil = henüz gönderilmedi.
    /// Not: `id` = ileride oluşacak Episode.id = sunucuya giden clientRequestId.
    var serverJobID: String?
    /// "waiting" | "uploading" | "scripting" | "needsRetry" | "failed"
    var stateRaw: String = "waiting"
    var progressText: String?
    var nextRetryAt: Date?
    var sourceNames: [String] = []

    init(documentIDs: [UUID], settings: PodcastSettings, title: String) {
        self.documentIDs = documentIDs
        settingsData = (try? JSONEncoder().encode(settings)) ?? Data()
        self.title = title
    }

    var settings: PodcastSettings? { try? JSONDecoder().decode(PodcastSettings.self, from: settingsData) }
}

nonisolated enum DocumentStore {
    static var directory: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Documents", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Sunucu araç yanıtları

nonisolated struct LessonSlide: Codable, Hashable, Sendable {
    var chapterIndex: Int
    var title: String
    var bullets: [String]
    var formula: String?
    var symbol: String
}

nonisolated struct ScriptIssue: Codable, Hashable, Sendable {
    var index: Int
    var severity: String   // "uydurma" | "hatali" | "belirsiz"
    var reason: String
    var correction: String?
    var quote: String?
    var page: Int?
    var fixedAt: Date?
}

nonisolated struct Evaluation: Codable, Hashable, Sendable {
    var score: Int
    var verdict: String    // "dogru" | "kismen" | "yanlis"
    var feedback: String
    var missing: [String]
    var errors: [String]
    var followUp: String?
}

nonisolated struct VocabItem: Codable, Hashable, Sendable {
    var term: String
    var translation: String
    var example: String
    var exampleTranslation: String
}

nonisolated struct ExtractResult: Codable, Hashable, Sendable {
    var title: String
    var text: String
    var warnings: [String]
}
