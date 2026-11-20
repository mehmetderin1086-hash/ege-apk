import BackgroundTasks
import Foundation
import UIKit
import UserNotifications

/// Kullanıcı uygulamadan çıksa da indirmenin sürmesi için iOS'un "sürdürülen işlem" görevi
/// (BGContinuedProcessingTask). Sistem ilerlemeyi kilit ekranında ve Dinamik Ada'da gösterir.
@Observable final class ArkaPlan {
    static let shared = ArkaPlan()

    private var gorev: BGContinuedProcessingTask?
    private var bekleyenKimlik: String?
    var durdurulsun: (() -> Void)?
    /// Görev başlatılınca hâlâ etkin indirme var mı? (Yoksa görev hemen kapatılır.)
    var etkinIsVar: () -> Bool = { false }

    var etkin: Bool { gorev != nil || bekleyenKimlik != nil }

    /// Etkin indirme başlayınca çağrılır; görev zaten varsa bir şey yapmaz.
    func basla(baslik: String) {
        guard !etkin, UIApplication.shared.applicationState != .background else { return }
        let kimlik = "com.mehmetderin.kepce.indir.\(UUID().uuidString)"
        let kayitli = BGTaskScheduler.shared.register(forTaskWithIdentifier: kimlik, using: .main) { [weak self] gorev in
            MainActor.assumeIsolated {
                guard let self, let gorev = gorev as? BGContinuedProcessingTask else { return }
                self.bekleyenKimlik = nil
                // İş görev başlamadan bittiyse Dinamik Ada'da asılı kalmasın.
                guard self.etkinIsVar() else { return gorev.setTaskCompleted(success: true) }
                self.gorev = gorev
                gorev.progress.totalUnitCount = 1000
                gorev.expirationHandler = { [weak self] in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            guard let self else { return }
                            self.gorev?.setTaskCompleted(success: false)
                            self.gorev = nil
                            self.durdurulsun?()
                        }
                    }
                }
            }
        }
        guard kayitli else { return }
        let istek = BGContinuedProcessingTaskRequest(identifier: kimlik, title: "Kepçe indiriyor", subtitle: baslik)
        istek.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(istek)
            bekleyenKimlik = kimlik
        } catch {
            bekleyenKimlik = nil
        }
    }

    func guncelle(ilerleme: Double, baslik: String, altBaslik: String) {
        guard let gorev else { return }
        gorev.progress.completedUnitCount = Int64(max(0, min(1, ilerleme)) * 1000)
        gorev.updateTitle(baslik, subtitle: altBaslik)
    }

    func bitir(basarili: Bool = true) {
        gorev?.setTaskCompleted(success: basarili)
        gorev = nil
        bekleyenKimlik = nil
    }

    // MARK: Bildirimler

    func bildirimIzni() {
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
    }

    func bildir(baslik: String, metin: String) {
        guard Ayarlar.shared.bildirim, UIApplication.shared.applicationState != .active else { return }
        let icerik = UNMutableNotificationContent()
        icerik.title = baslik
        icerik.body = metin
        icerik.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: icerik, trigger: nil))
    }
}
