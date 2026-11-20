import Foundation
import SwiftData

/// Uygulamanın tek `ModelContainer`'ı: sahne ve arka plan görevleri (kanal kontrolü) aynı depoyu kullanır.
enum AppDataStore {
    static let modelTypes: [any PersistentModel.Type] = [
        Episode.self, Bookmark.self, ReviewCard.self, ListeningDay.self, SourceDocument.self, QueuedRequest.self,
        Course.self, Lesson.self, Assignment.self, StudySession.self, MistakeEntry.self, CornellNote.self,
        VideoLesson.self, FollowedChannel.self, TimedNote.self,
        RecallAttempt.self, EpisodeProbe.self, LiveExchange.self,
    ]

    /// Şema her değiştiğinde artırılır; göçten önce depo bir kez kopyalanır.
    static let schemaTag = "learning-source1"

    /// Deponun yeri açıkça verilir: uygulamada App Group yetkisi varken (Ders Video'ya veri bırakmak için eklendi)
    /// SwiftData adressiz depoyu kendiliğinden ortak klasöre taşır; o zaman kütüphane boş açılır ve depo Ders Video ile
    /// paylaşılırdı. Depo her zaman uygulamanın kendi klasöründedir.
    nonisolated static var storeURL: URL { URL.applicationSupportDirectory.appending(path: "default.store") }

    static let container: ModelContainer = {
        StoreSnapshot.takeOnce(tag: schemaTag)
        do {
            let schema = Schema(modelTypes)
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL)])
        } catch {
            fatalError("Veri deposu açılamadı: \(error)")
        }
    }()
}

/// Göç öncesi güvenlik kopyası: Application Support/StoreBackup-<tag>/ (etiket başına bir kez).
nonisolated enum StoreSnapshot {
    static func takeOnce(tag: String) {
        let fm = FileManager.default
        let base = URL.applicationSupportDirectory
        let target = base.appending(path: "StoreBackup-\(tag)", directoryHint: .isDirectory)
        guard !fm.fileExists(atPath: target.path),
              fm.fileExists(atPath: base.appending(path: "default.store").path) else { return }
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        for name in ["default.store", "default.store-wal", "default.store-shm"] {
            let source = base.appending(path: name)
            if fm.fileExists(atPath: source.path) { try? fm.copyItem(at: source, to: target.appending(path: name)) }
        }
    }
}
