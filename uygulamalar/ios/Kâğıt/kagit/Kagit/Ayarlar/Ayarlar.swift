import Foundation
import SwiftUI

/// Uygulama ayarları (UserDefaults'ta saklanır). Modüller kendi ayarlarını
/// `UserDefaults` anahtarlarıyla (ör. "yapay.kaynak") kendi dosyalarında tutabilir.
@Observable
final class Ayarlar {
    static let paylasilan = Ayarlar()
    private let d = UserDefaults.standard

    /// Belge kapatılırken değişiklikler sormadan kaydedilsin.
    var otomatikKaydet: Bool { didSet { d.set(otomatikKaydet, forKey: "otomatikKaydet") } }
    /// VPS dönüşüm sunucusu kullanılabilir mi (Office ↔ PDF).
    var sunucuEtkin: Bool { didSet { d.set(sunucuEtkin, forKey: "sunucuEtkin") } }
    /// Bulut yapay zekâ (Claude vekili) kullanılabilir mi.
    var bulutYapayZeka: Bool { didSet { d.set(bulutYapayZeka, forKey: "bulutYapayZeka") } }
    /// Face ID ile kilit.
    var kilitEtkin: Bool { didSet { d.set(kilitEtkin, forKey: "kilitEtkin") } }
    /// Yeni belgelerde yazar adı (imza/damga/üst veri).
    var yazarAdi: String { didSet { d.set(yazarAdi, forKey: "yazarAdi") } }

    init() {
        d.register(defaults: ["otomatikKaydet": true, "sunucuEtkin": false, "bulutYapayZeka": false, "kilitEtkin": false])
        otomatikKaydet = d.bool(forKey: "otomatikKaydet")
        sunucuEtkin = d.bool(forKey: "sunucuEtkin")
        bulutYapayZeka = d.bool(forKey: "bulutYapayZeka")
        kilitEtkin = d.bool(forKey: "kilitEtkin")
        yazarAdi = d.string(forKey: "yazarAdi") ?? ""
    }
}
