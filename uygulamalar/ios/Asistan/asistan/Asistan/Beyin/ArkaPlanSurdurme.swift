import Foundation
import BackgroundTasks
import UserNotifications
import UIKit

/// Uzun arka plan görevleri (madde 2): uzun sürecek istek başlarken iOS'tan "sürdürülen işlem" ister
/// (BGContinuedProcessingTask; ilerleme sistem arayüzünde görünür), uygulama arka plandayken yanıt biterse bildirim gönderir.
@MainActor
final class ArkaPlanSurdurucu {
    static let ortak = ArkaPlanSurdurucu()
    nonisolated static let onek = "com.mehmetderin.asistan.gorev"
    private var gorev: BGContinuedProcessingTask?
    private var bekleyenBaslik: String?
    /// Bu istek için gönderilen sistem görevi kimliği; eski istekten gelen görev benimsenmez.
    private var bekleyenKimlik: String?
    private(set) var istendi = false

    /// Kayıt görev başına, göndermeden hemen önce yapılır (sürdürülen işlem görevleri açılış sonrası kaydedilebilir).
    /// Kayıtsız gönderim BGTaskScheduler'da assertion ile çöker; kayıt başarısızsa görev hiç gönderilmez.
    /// Kapanış sistem kuyruğunda çağrılır; @Sendable olmalı (MainActor varsayılan yalıtım tuzağı).
    nonisolated static func kaydol(_ kimlik: String) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: kimlik, using: nil) { @Sendable gorev in
            // expirationHandler başlatma kapanışı dönmeden atanmalı; Task içinde atanırsa sistem geç kalmış sayar.
            let gorevKimligi = gorev.identifier
            gorev.expirationHandler = { @Sendable in
                Task { @MainActor in
                    let o = ArkaPlanSurdurucu.ortak
                    if o.bekleyenKimlik == gorevKimligi { o.kapat(basarili: false) }
                }
            }
            nonisolated(unsafe) let g = gorev
            Task { @MainActor in
                guard let s = g as? BGContinuedProcessingTask else { g.setTaskCompleted(success: false); return }
                ArkaPlanSurdurucu.ortak.basladi(s)
            }
        }
    }

    /// Uzun görev başında (uygulama öndeyken) çağrılır.
    func baslat(_ istek: String) {
        guard !istendi else { return }
        istendi = true
        let baslik = "Asistan çalışıyor"
        bekleyenBaslik = String(istek.prefix(60))
        let kimlik = "\(Self.onek).\(UUID().uuidString)"
        bekleyenKimlik = kimlik
        guard Self.kaydol(kimlik) else { istendi = false; TaniGunlugu.yaz("ARKA PLAN GÖREVİ kaydedilemedi"); return }
        let r = BGContinuedProcessingTaskRequest(identifier: kimlik, title: baslik, subtitle: bekleyenBaslik ?? "")
        r.strategy = .queue
        do { try BGTaskScheduler.shared.submit(r) } catch {
            istendi = false
            TaniGunlugu.yaz("ARKA PLAN GÖREVİ istenemedi: \(error.localizedDescription)")
        }
    }

    private func basladi(_ g: BGContinuedProcessingTask) {
        // Görev bu arada bittiyse ya da başka (eski) isteğe aitse hemen kapat.
        guard istendi, g.identifier == bekleyenKimlik else { g.progress.completedUnitCount = g.progress.totalUnitCount; g.setTaskCompleted(success: true); return }
        gorev = g
        g.progress.totalUnitCount = 100
        g.progress.completedUnitCount = 5
    }

    /// Ajan adımı ilerledikçe (araç çağrıları) ilerleme çubuğunu günceller.
    func ilerle(adim: Int) {
        guard let g = gorev else { return }
        g.progress.completedUnitCount = Int64(min(90, 10 + adim * 12))
        g.updateTitle("Asistan çalışıyor", subtitle: "\(bekleyenBaslik ?? "") · \(adim) adım")
    }

    /// Yanıt bittiğinde (başarılı ya da değil): sistem görevini kapatır; uygulama arka plandaysa bildirim gönderir.
    func bitti(_ yanit: String?, hata: String? = nil) {
        let arkaPlanda = UIApplication.shared.applicationState != .active
        kapat(basarili: hata == nil)
        guard arkaPlanda, let ozet = (hata ?? yanit)?.trimmingCharacters(in: .whitespacesAndNewlines), !ozet.isEmpty else { return }
        let c = UNMutableNotificationContent()
        c.title = hata == nil ? "Asistan yanıtı hazır" : "Asistan görevi tamamlanamadı"
        c.body = String(YanitBicimi.duzelt(ozet).prefix(180))
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "yanit-\(UUID().uuidString)", content: c, trigger: nil))
    }

    private func kapat(basarili: Bool) {
        if let g = gorev {
            g.progress.completedUnitCount = 100
            g.setTaskCompleted(success: basarili)
        }
        gorev = nil; istendi = false; bekleyenBaslik = nil; bekleyenKimlik = nil
    }

    /// Uzun sürmesi beklenen istek: yüksek çaba, araştırma/kod kipi ya da "bitince haber ver" denmiş.
    nonisolated static func uzunMu(_ istek: String, caba: DusunmeSecimi.Caba, kip: CalismaKipi) -> Bool {
        let s = istek.lowercased()
        return caba == .high || kip == .arastirma || kip == .kod || s.contains("bitince haber") || s.contains("bitince bildir") || s.contains("arka planda")
    }
}
