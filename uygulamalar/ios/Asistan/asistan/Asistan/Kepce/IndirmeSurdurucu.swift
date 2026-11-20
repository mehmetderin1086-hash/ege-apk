import Foundation
import BackgroundTasks

/// Motorlu (Kepçe) indirme için iOS'tan "sürdürülen işlem" ister (BGContinuedProcessingTask, madde O2):
/// ekran kilitlenince ya da başka uygulamaya geçilince indirme ~30 sn'lik `ArkaPlanGorevi` yedeğinden uzun sürer,
/// ilerleme sistem arayüzünde "İndiriliyor" olarak görünür. Her indirme kendi sistem görevini ister.
///
/// Kimlik her istekte YENİ UUID'dir (kayıt id'si değil): `motorluTekrar` aynı kayıt id'siyle yeniden başlar ve
/// aynı kimliği ikinci kez `register` etmek çöker (bkz. Nabiz.kaydol). Strateji `.queue`: sistem şu an veremiyorsa
/// (ör. başka bir sürdürülen görev varken) istek kuyruğa girer, o arada `ArkaPlanGorevi` yedeği sürer.
///
/// Süre dolunca (ya da kullanıcı sistem arayüzünden durdurunca) indirme İPTAL EDİLMEZ: iptal çalışma klasörünü
/// siler (`MotorluIndirici.klasorSilinmeli`). Süreç askıya alınırsa AkisIndirici hata verir, kayıt 'failed' olur
/// ve "Yeniden dene" kalan parçalardan sürer.
@MainActor
final class IndirmeSurdurucu {
    static let ortak = IndirmeSurdurucu()
    /// Kayıt id'si → sistemin başlattığı görev.
    private var gorevler: [UUID: BGContinuedProcessingTask] = [:]
    /// Gönderilmiş ama sistemin henüz başlatmadığı istekler: sistem kimliği → kayıt id'si.
    private var bekleyen: [String: UUID] = [:]
    /// Süren (istenmiş ya da başlamış) görev sayısı; testler ve tanı için.
    var etkinSayisi: Int { gorevler.count + bekleyen.count }

    static let baslik = "İndiriliyor"

    /// Tek parça kimlik (`onek.indir-<UUID>`): Info.plist'teki `com.mehmetderin.asistan.gorev.*` joker kimliğine uyar.
    nonisolated static func yeniKimlik() -> String {
        ArkaPlanSurdurucu.onek + ".indir-" + UUID().uuidString
    }

    /// Kayıt görev başına, göndermeden hemen önce (kayıtsız gönderim assertion ile çöker).
    /// Kapanış sistem kuyruğunda çağrılır; @Sendable olmalı (MainActor varsayılan yalıtım tuzağı).
    nonisolated static func kaydol(_ kimlik: String) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: kimlik, using: nil) { @Sendable gorev in
            // expirationHandler başlatma kapanışı dönmeden atanmalı; Task içinde atanırsa sistem geç kalmış sayar.
            let gorevKimligi = gorev.identifier
            gorev.expirationHandler = { @Sendable in
                Task { @MainActor in IndirmeSurdurucu.ortak.suresiDoldu(kimlik: gorevKimligi) }
            }
            nonisolated(unsafe) let g = gorev
            Task { @MainActor in
                guard let s = g as? BGContinuedProcessingTask else { g.setTaskCompleted(success: false); return }
                IndirmeSurdurucu.ortak.basladi(s)
            }
        }
    }

    /// Motorlu indirme başlarken (uygulama öndeyken) çağrılır.
    func baslat(_ id: UUID, ad: String) {
        // Aynı kayıt için kalmış istek/görev varsa önce kapat (yeniden deneme yeni görev ister).
        if gorevler[id] != nil || bekleyen.values.contains(id) { bitir(id, basarili: false) }
        let kimlik = Self.yeniKimlik()
        bekleyen[kimlik] = id
        guard Self.kaydol(kimlik) else {
            bekleyen[kimlik] = nil
            TaniGunlugu.yaz("İNDİRME GÖREVİ kaydedilemedi")
            return
        }
        let r = BGContinuedProcessingTaskRequest(identifier: kimlik, title: Self.baslik, subtitle: String(ad.prefix(60)))
        r.strategy = .queue
        do { try BGTaskScheduler.shared.submit(r) } catch {
            bekleyen[kimlik] = nil
            TaniGunlugu.yaz("İNDİRME GÖREVİ istenemedi: \(error.localizedDescription)")
        }
    }

    private func basladi(_ g: BGContinuedProcessingTask) {
        // İndirme bu arada bittiyse (ya da istek eskiyse) görevi hemen kapat.
        guard let id = bekleyen.removeValue(forKey: g.identifier) else {
            g.progress.completedUnitCount = g.progress.totalUnitCount
            g.setTaskCompleted(success: true)
            return
        }
        gorevler[id] = g
        g.progress.totalUnitCount = 100
        g.progress.completedUnitCount = 1
    }

    /// Bayt ilerlemesini sistem göstergesine yansıtır.
    func ilerle(_ id: UUID, alinan: Int64, toplam: Int64) {
        guard let g = gorevler[id] else { return }
        let b = Self.birimler(alinan: alinan, toplam: toplam)
        g.progress.totalUnitCount = b.toplam
        g.progress.completedUnitCount = b.tamamlanan
    }

    /// Aşama değişti (ör. "Birleştiriliyor…"): alt başlık güncellenir; birleştirmede ilerleme %97'ye çekilir
    /// (bu aşama bayt bildirmez, sistem görevi bayat saymasın).
    func asama(_ id: UUID, _ metin: String) {
        guard let g = gorevler[id] else { return }
        g.updateTitle(Self.baslik, subtitle: metin)
        if metin.hasPrefix("Birleştir") {
            let toplam = max(g.progress.totalUnitCount, 1)
            g.progress.completedUnitCount = max(g.progress.completedUnitCount, toplam * 97 / 100)
        }
    }

    /// Medya adı çözülünce alt başlığa yazılır.
    func adiGuncelle(_ id: UUID, _ ad: String) {
        guard let g = gorevler[id] else { return }
        g.updateTitle(Self.baslik, subtitle: String(ad.prefix(60)))
    }

    /// Birleştirme (dışa aktarma) sürerken ilerlemeyi %97'den %99'a doğru ilerletir; oran 0...1. Her çağrı en az 1 birim
    /// ekler, böylece dışa aktarma oran bildirmese de sistem görevi bayat sayılıp zorla sonlandırılmaz.
    func birlestirmeIlerle(_ id: UUID, oran: Double) {
        guard let g = gorevler[id] else { return }
        let toplam = max(g.progress.totalUnitCount, 1)
        let taban = toplam * 97 / 100, tavan = max(taban, toplam * 99 / 100)
        let hedef = taban + Int64(Double(tavan - taban) * min(max(oran, 0), 1))
        g.progress.completedUnitCount = min(tavan, max(hedef, g.progress.completedUnitCount + 1))
    }

    /// İndirme bittiğinde (başarılı, başarısız ya da iptal): sistem görevini kapatır, bekleyen isteği unutur.
    func bitir(_ id: UUID, basarili: Bool) {
        if let g = gorevler.removeValue(forKey: id) {
            g.progress.completedUnitCount = g.progress.totalUnitCount
            g.setTaskCompleted(success: basarili)
        }
        for (kimlik, kayit) in bekleyen where kayit == id {
            bekleyen[kimlik] = nil
            // Kuyrukta kalmış istek sonradan başlayıp boşuna sistem görevi tutmasın.
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: kimlik)
        }
    }

    /// Sistem süreyi bitirdi: yalnız sistem görevi kapanır, indirme iptal edilmez (parçalar korunur).
    /// Görev henüz `basladi` ile benimsenmediyse bekleyen kayıt silinir; `basladi` onu hemen kapatır.
    private func suresiDoldu(kimlik: String) {
        TaniGunlugu.yaz("İNDİRME GÖREVİ süresi doldu")
        if let (id, g) = gorevler.first(where: { $0.value.identifier == kimlik }) {
            gorevler[id] = nil
            g.setTaskCompleted(success: false)
        } else {
            bekleyen[kimlik] = nil
        }
    }

    /// Sistem göstergesi birimleri. Toplam biliniyorsa bayt (0...toplam'a sıkıştırılmış); bilinmiyorsa 100 üzerinden
    /// her 5 MB'ta bir birim, en çok 90 (bilinmeyen boyutta da ilerleme ilerlesin, sistem görevi bayat saymasın).
    nonisolated static func birimler(alinan: Int64, toplam: Int64) -> (tamamlanan: Int64, toplam: Int64) {
        if toplam > 0 { return (min(max(alinan, 0), toplam), toplam) }
        return (min(90, 1 + max(alinan, 0) / 5_000_000), 100)
    }
}
