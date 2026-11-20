import Foundation

/// `kocum://` bağlantılarının tek yönlendiricisi (#45/#46). Üretme ve ayrıştırma `AppLink`'tedir.
enum DeepLink {
    /// Döner: bağlantı tanındı mı.
    @discardableResult static func handle(_ url: URL) -> Bool {
        guard let link = AppLink(url: url) else { return false }
        open(link)
        return true
    }

    static func open(_ link: AppLink) {
        guard let app = AppState.current else { return }
        apply(link, to: app)
    }

    /// Bölüm → kütüphanede aç (istenirse o ana git/çal); üretim → aynı kimlikle aç (bölüm yoksa bekleme ekranı);
    /// Eski koç rotası → Çalış sekmesi; diğer rotalar var olan `pendingRoute` yolundan.
    static func apply(_ link: AppLink, to app: AppState) {
        switch link {
        case let .episode(id, time, play):
            app.open(id, at: time, play: play)
        case let .generation(id):
            app.open(id)
        case .route("coach"):
            // Eski bağlantılar (koçluk kaldırıldı): Çalış sekmesi açılır.
            app.selectedTab = .study
        case let .route(name):
            app.pendingRoute = name
        }
    }
}
