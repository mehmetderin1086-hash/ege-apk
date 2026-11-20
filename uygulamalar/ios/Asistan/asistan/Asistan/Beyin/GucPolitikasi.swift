import Foundation
import Observation

/// P3.9: termal durum ve Düşük Güç kipine göre arka plan işlerini kısan tek karar noktası.
/// Etkiledikleri: yerel sunucu bekçisinin yoklama aralığı (`TelefonProxy.bekciAyarla`), paralel yarışın genişliği
/// (`ParalelYaris.genislik`, `termalAgir`/`dusukGuc`) ve 'Hey Asistan' uyandırma beklemesi (`SesOturumu.uyandirmayiBaslat`).
/// Live ve sesli kipe dokunulmaz; kullanıcının başlattığı iş kesilmez, yalnız kendiliğinden süren beklemeler kısılır.
@MainActor @Observable
final class GucPolitikasi {
    nonisolated struct Karar: Equatable, Sendable {
        let bekciAraligi: Duration
        let uyandirmaAcik: Bool
    }

    static let ortak = GucPolitikasi()
    private(set) var termal: ProcessInfo.ThermalState
    private(set) var dusukGuc: Bool
    /// Ağır termal durum (serious/critical): yarış teke iner.
    var termalAgir: Bool { termal == .serious || termal == .critical }
    var karar: Karar { Self.karar(termal: termal, dusukGuc: dusukGuc) }
    /// Karar değişince (AsistanApp.init bağlar): uyandırma beklemesi ve bekçi yeniden ayarlanır.
    @ObservationIgnored var degisti: ((Karar) -> Void)?
    @ObservationIgnored private var gozlemciler: [any NSObjectProtocol] = []

    init(gozle: Bool = true) {
        termal = ProcessInfo.processInfo.thermalState
        dusukGuc = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard gozle else { return }
        // Bildirimler herhangi bir iş parçacığından gelebilir: kapanış @Sendable, ana kuyrukta koşar ve ana aktöre
        // `assumeIsolated` ile geçer (AGENTS: sistem kuyruğundan çağrılan kapanış MainActor'a bağlı olamaz).
        let merkez = NotificationCenter.default
        for ad in [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            gozlemciler.append(merkez.addObserver(forName: ad, object: nil, queue: .main) { @Sendable [weak self] _ in
                MainActor.assumeIsolated { self?.yenile() }
            })
        }
    }

    /// Sistem durumunu yeniden okur; karar değiştiyse günlüğe yazar ve `degisti`'yi çağırır.
    func yenile() {
        guncelle(termal: ProcessInfo.processInfo.thermalState, dusukGuc: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    /// Sınanabilir çekirdek: yeni değerleri uygular; karar değişirse `degisti` bir kez çağrılır.
    func guncelle(termal yeniTermal: ProcessInfo.ThermalState, dusukGuc yeniDusukGuc: Bool) {
        let eski = karar
        guard yeniTermal != termal || yeniDusukGuc != dusukGuc else { return }
        termal = yeniTermal; dusukGuc = yeniDusukGuc
        let yeni = karar
        TaniGunlugu.yaz("GÜÇ termal=\(Self.termalAdi(termal)) düşükGüç=\(dusukGuc) bekçi=\(yeni.bekciAraligi.components.seconds)sn uyandırma=\(yeni.uyandirmaAcik ? "açık" : "kapalı")")
        if yeni != eski { degisti?(yeni) }
    }

    /// Saf karar tablosu: olağan → 15 sn, uyandırma açık; Düşük Güç → 45 sn, açık; serious → 45 sn (Düşük Güç de açıksa
    /// uyandırma kapalı); critical → 90 sn, uyandırma kapalı.
    nonisolated static func karar(termal: ProcessInfo.ThermalState, dusukGuc: Bool) -> Karar {
        switch termal {
        case .critical: return Karar(bekciAraligi: .seconds(90), uyandirmaAcik: false)
        case .serious: return Karar(bekciAraligi: .seconds(45), uyandirmaAcik: !dusukGuc)
        default: return Karar(bekciAraligi: dusukGuc ? .seconds(45) : .seconds(15), uyandirmaAcik: true)
        }
    }

    nonisolated static func termalAdi(_ t: ProcessInfo.ThermalState) -> String {
        switch t {
        case .nominal: "olağan"
        case .fair: "ılık"
        case .serious: "sıcak"
        case .critical: "kritik"
        @unknown default: "bilinmiyor"
        }
    }

    /// Sağlık ekranı 'Güç' satırı: durum ve etkin kısıtlar (Düşük Veri `AgIzleyici`'den gelir).
    func ozet(dusukVeri: Bool) -> (metin: String, kisitli: Bool) {
        let k = karar
        var kisitlar: [String] = []
        if dusukVeri || termalAgir { kisitlar.append("yarış tek model") } else if dusukGuc { kisitlar.append("yarış en çok 2 model") }
        if k.bekciAraligi > .seconds(15) { kisitlar.append("bekçi \(k.bekciAraligi.components.seconds) sn") }
        if !k.uyandirmaAcik { kisitlar.append("'Hey Asistan' beklemesi kapalı") }
        let durum = "Termal: \(Self.termalAdi(termal)) · Düşük Güç: \(dusukGuc ? "açık" : "kapalı") · Düşük Veri: \(dusukVeri ? "açık" : "kapalı")"
        return (kisitlar.isEmpty ? durum : durum + "\nKısıt: " + kisitlar.joined(separator: ", "), !kisitlar.isEmpty)
    }
}
