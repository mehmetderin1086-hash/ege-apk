import Foundation
import Network
import Observation
import UIKit

/// Kopmaya karşı koruma yardımcıları: ağ izleme, geçici hata ayrımı, arka plan görevi.

/// Geçici (kısa kopma/gecikme türü) hatalar bir kez yeniden denenir ve rota/model boşuna askıya alınmaz.
nonisolated enum GeciciHata {
    static let urlKodlari: Set<Int> = [
        NSURLErrorTimedOut, NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost,
        NSURLErrorNotConnectedToInternet, NSURLErrorDNSLookupFailed, NSURLErrorCannotFindHost,
        NSURLErrorSecureConnectionFailed, NSURLErrorDataNotAllowed,
    ]
    static func mi(_ hata: any Error) -> Bool {
        if hata is CancellationError { return false }
        let ns = hata as NSError
        if ns.domain == NSURLErrorDomain { return urlKodlari.contains(ns.code) }
        let a = String(describing: hata).lowercased()
        // Geçici sunucu/ağ geçidi hataları.
        return ["502", "503", "504", "bad gateway", "service unavailable", "gateway timeout", "connection reset", "broken pipe"].contains { a.contains($0) }
    }
}

/// Ağ durumu: çevrimdışıyken gönderilen mesaj kuyruğa alınır, bağlantı gelince otomatik gider.
@MainActor @Observable
final class AgIzleyici {
    static let ortak = AgIzleyici()
    private(set) var cevrimici = true
    /// P3.7: Düşük Veri kipi (NWPath.isConstrained): paralel yarış teke iner.
    private(set) var dusukVeri = false
    /// Hücresel ya da kişisel erişim noktası (NWPath.isExpensive).
    private(set) var pahali = false
    /// "wifi" / "hucresel" / "kablolu" / "diger".
    private(set) var arayuz = "diger"
    /// true = bağlantı geri geldi, false = koptu.
    var degisti: ((Bool) -> Void)?
    private let izleyici = NWPathMonitor()

    init(baslat: Bool = true) {
        guard baslat else { return }
        // Sistem kuyruğundan çağrılır: kapanış @Sendable, durum ana aktöre taşınır.
        izleyici.pathUpdateHandler = { @Sendable [weak self] yol in
            let c = yol.status == .satisfied
            let dusuk = yol.isConstrained, pahali = yol.isExpensive
            let ad = Self.arayuzAdi(wifi: yol.usesInterfaceType(.wifi), hucresel: yol.usesInterfaceType(.cellular),
                                    kablolu: yol.usesInterfaceType(.wiredEthernet))
            Task { @MainActor in self?.yolGuncelle(cevrimici: c, dusukVeri: dusuk, pahali: pahali, arayuz: ad) }
        }
        izleyici.start(queue: DispatchQueue(label: "asistan.ag-izleyici"))
    }

    nonisolated static func arayuzAdi(wifi: Bool, hucresel: Bool, kablolu: Bool) -> String {
        wifi ? "wifi" : hucresel ? "hucresel" : kablolu ? "kablolu" : "diger"
    }

    func durumGuncelle(_ c: Bool) {
        guard c != cevrimici else { return }
        cevrimici = c
        TaniGunlugu.yaz("AĞ \(c ? "geri geldi" : "koptu")")
        degisti?(c)
    }

    /// Yol değişimi: çevrimiçi durumu `durumGuncelle` ile (Beyin'in `degisti` kapanışı), öbür alanlar burada;
    /// herhangi biri değişince `.agYoluDegisti` yayınlanır (BaglantiDurumu yeniden yoklar).
    func yolGuncelle(cevrimici c: Bool, dusukVeri d: Bool, pahali p: Bool, arayuz a: String) {
        let farkli = c != cevrimici || d != dusukVeri || p != pahali || a != arayuz
        if d != dusukVeri { TaniGunlugu.yaz("AĞ düşük veri \(d ? "açık" : "kapalı")") }
        dusukVeri = d; pahali = p; arayuz = a
        durumGuncelle(c)
        if farkli { NotificationCenter.default.post(name: .agYoluDegisti, object: nil) }
    }
}

extension Notification.Name {
    /// P3.7: ağ yolu (çevrimiçi, düşük veri, pahalı, arayüz) değişti.
    static let agYoluDegisti = Notification.Name("asistan.agYoluDegisti")
}

/// Çalışan istek, uygulama kısa süre arka plana gitse de (seçici, kamera, bildirim) tamamlanabilsin diye.
@MainActor
final class ArkaPlanGorevi {
    private var kimlik = UIBackgroundTaskIdentifier.invalid
    var aktif: Bool { kimlik != .invalid }

    func baslat(_ ad: String) {
        guard kimlik == .invalid else { return }
        kimlik = UIApplication.shared.beginBackgroundTask(withName: ad) { [weak self] in
            TaniGunlugu.yaz("ARKA PLAN GÖREVİ SÜRESİ DOLDU")
            self?.bitir()
        }
    }
    func bitir() {
        guard kimlik != .invalid else { return }
        UIApplication.shared.endBackgroundTask(kimlik)
        kimlik = .invalid
    }
}

/// Akış zaman aşımı kararı: ilk metin gelene kadar `ilkMetinButcesi`, ilerleme (yeni metin ya da araç etkinliği)
/// görüldükten sonra `ilerlemeSonrasiButce` boşta kalma toleransı. İlerleme sayacı sıfırlar; araç çalışırken sayılmaz.
nonisolated struct AkisBekcisi {
    static let ilerlemeSonrasiButce: TimeInterval = 30
    let ilkMetinButcesi: TimeInterval
    private(set) var bosGecen: TimeInterval = 0
    private var sonUzunluk = 0
    private var sonArac = 0

    init(ilkMetinButcesi: TimeInterval) { self.ilkMetinButcesi = ilkMetinButcesi }

    /// true = zaman aşımı.
    mutating func adim(uzunluk: Int, aracSayisi: Int, aracCalisiyor: Bool, aralik: TimeInterval = 0.5) -> Bool {
        if uzunluk != sonUzunluk || aracSayisi != sonArac {
            bosGecen = 0; sonUzunluk = uzunluk; sonArac = aracSayisi
        } else if !aracCalisiyor {
            bosGecen += aralik
        }
        let ilerledi = uzunluk > 0 || aracSayisi > 0
        let butce = ilerledi ? max(ilkMetinButcesi, Self.ilerlemeSonrasiButce) : ilkMetinButcesi
        return bosGecen >= butce
    }
}
