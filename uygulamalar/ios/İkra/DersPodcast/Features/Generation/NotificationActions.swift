import Foundation
import SwiftData
import UIKit
import UserNotifications

/// #46: üretim bildirimleri ve eylemleri. userInfo `episodeID` (UUID dizgisi) taşır.
enum NotificationActions {
    nonisolated static let readyCategory = "podcast.ready"
    nonisolated static let stalledCategory = "podcast.stalled"

    nonisolated static let listenAction = "listen"
    nonisolated static let enqueueAction = "enqueue"
    nonisolated static let resumeAction = "resume"

    static func registerCategories() {
        let listen = UNNotificationAction(identifier: listenAction, title: "Dinle", options: [.foreground])
        // Arka planda yalnız kuyruğa yazar (~30 sn sınırı).
        let enqueue = UNNotificationAction(identifier: enqueueAction, title: "Sıraya ekle", options: [])
        let resume = UNNotificationAction(identifier: resumeAction, title: "Devam et", options: [.foreground])
        let ready = UNNotificationCategory(identifier: readyCategory, actions: [listen, enqueue], intentIdentifiers: [], options: [])
        let stalled = UNNotificationCategory(identifier: stalledCategory, actions: [resume], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([ready, stalled])
    }

    /// true = işlendi (rota işlenmez).
    static func handle(actionIdentifier: String, episodeID: UUID?) async -> Bool {
        guard let id = episodeID else { return false }
        switch actionIdentifier {
        case listenAction:
            guard let app = AppState.current else { return false }
            app.open(id, play: true)
            return true
        case enqueueAction:
            enqueueForPlayback(id)
            return true
        case resumeAction:
            resumeGeneration(id)
            AppState.current?.open(id)
            return true
        case UNNotificationDefaultActionIdentifier:
            guard let app = AppState.current else { return false }
            app.open(id)
            return true
        default:
            return false
        }
    }

    // MARK: - Gönderim

    /// Bildirim içeriği (saf; test edilir).
    nonisolated struct Content: Equatable, Sendable {
        var title: String
        var body: String
        var category: String
        var userInfo: [String: String]
    }

    /// `failed`: kalıcı hata (kuyruk işi ya da bölüm düştü); "Devam et" yine elle yeniden dener.
    nonisolated enum Kind: Sendable { case ready, stalled(String), failed(String), approval }

    nonisolated static func content(_ kind: Kind, episodeID: UUID, title: String) -> Content {
        let info = ["episodeID": episodeID.uuidString]
        switch kind {
        case .ready:
            return Content(title: "Bölüm hazır", body: title, category: readyCategory, userInfo: info)
        case let .stalled(reason):
            return Content(title: "Üretim duraklatıldı", body: "\(title): \(reason)", category: stalledCategory, userInfo: info)
        case let .failed(reason):
            return Content(title: "Podcast oluşturulamadı", body: "\(title): \(reason)", category: stalledCategory, userInfo: info)
        case .approval:
            return Content(title: "Senaryo hazır, onay bekliyor", body: title, category: stalledCategory, userInfo: info)
        }
    }

    /// Yalnız uygulama ön planda değilken gönderilir (ön planda ekran zaten gösteriyor).
    static func post(_ kind: Kind, episodeID: UUID, title: String) {
        guard UIApplication.shared.applicationState != .active else { return }
        let c = content(kind, episodeID: episodeID, title: title)
        let content = UNMutableNotificationContent()
        content.title = c.title
        content.body = c.body
        content.sound = .default
        content.categoryIdentifier = c.category
        content.userInfo = c.userInfo
        let request = UNNotificationRequest(identifier: "generation.\(episodeID.uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Eylemler

    /// "Sıraya ekle": oynatıcı varsa onun kuyruğuna; uygulama arka planda yeni açıldıysa doğrudan kalıcı kuyruğa.
    private static func enqueueForPlayback(_ id: UUID) {
        if let player = AppState.current?.player {
            player.enqueue(.episode(id))
            return
        }
        let key = "player.queue"
        var items = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([PlaybackQueueItem].self, from: $0) } ?? []
        guard !items.contains(.episode(id)) else { return }
        items.append(.episode(id))
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: key)
    }

    /// "Devam et": duraklatılan bölüm ya da kuyruk isteği sürdürülür.
    private static func resumeGeneration(_ id: UUID) {
        guard let generator = AppState.current?.generator else { return }
        let context = AppDataStore.container.mainContext
        if let episode = try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })).first {
            guard !episode.needsApproval else { return }
            if episode.canResume { generator.resume(episode, context: context) }
            else if episode.status == .failed, episode.script != nil { generator.recoverAudio(episode, context: context) }
        } else {
            generator.retryNow(id, context: context)
        }
    }
}
