import Foundation
import Observation

/// Kullanıcı ayarları (UserDefaults'ta saklanır).
@Observable final class Ayarlar {
    static let shared = Ayarlar()
    private let d = UserDefaults.standard

    /// Videoda en yüksek çözünürlük; 0 = cihazın oynatabildiği en iyisi.
    var enFazlaCozunurluk: Int { didSet { d.set(enFazlaCozunurluk, forKey: "enFazlaCozunurluk") } }
    /// Paylaşım menüsünden ya da hızlı indirmeden gelen bağlantıda varsayılan tür.
    var hizliTur: IndirmeTuru { didSet { d.set(hizliTur.rawValue, forKey: "hizliTur") } }
    var esZamanli: Int { didSet { d.set(esZamanli, forKey: "esZamanli") } }
    var baglantiSayisi: Int { didSet { d.set(baglantiSayisi, forKey: "baglantiSayisi") } }
    var fotograflaraKaydet: Bool { didSet { d.set(fotograflaraKaydet, forKey: "fotograflaraKaydet") } }
    /// Varsayılan altyazı dili ("" = altyazı indirme).
    var altyaziDili: String { didSet { d.set(altyaziDili, forKey: "altyaziDili") } }
    var otomatikAltyazi: Bool { didSet { d.set(otomatikAltyazi, forKey: "otomatikAltyazi") } }
    var bildirim: Bool { didSet { d.set(bildirim, forKey: "bildirim") } }
    var panoyuIzle: Bool { didSet { d.set(panoyuIzle, forKey: "panoyuIzle") } }
    var tercihEdilenSesDili: String { didSet { d.set(tercihEdilenSesDili, forKey: "tercihEdilenSesDili") } }
    /// Liste indirmelerinde liste adıyla alt klasör ve sıra numaralı dosya adı.
    var listeKlasoru: Bool { didSet { d.set(listeKlasoru, forKey: "listeKlasoru") } }
    var listeNumarala: Bool { didSet { d.set(listeNumarala, forKey: "listeNumarala") } }
    /// Kütüphanede ya da sırada olan videoları yeniden indirme.
    var indirilenleriAtla: Bool { didSet { d.set(indirilenleriAtla, forKey: "indirilenleriAtla") } }

    private init() {
        d.register(defaults: ["enFazlaCozunurluk": 1080, "hizliTur": IndirmeTuru.video.rawValue, "esZamanli": 3, "baglantiSayisi": 4,
                              "fotograflaraKaydet": false, "altyaziDili": "", "otomatikAltyazi": true, "bildirim": true, "panoyuIzle": true,
                              "tercihEdilenSesDili": "", "listeKlasoru": true, "listeNumarala": false, "indirilenleriAtla": true])
        enFazlaCozunurluk = d.integer(forKey: "enFazlaCozunurluk")
        hizliTur = IndirmeTuru(rawValue: d.string(forKey: "hizliTur") ?? "") ?? .video
        esZamanli = min(8, max(1, d.integer(forKey: "esZamanli")))
        baglantiSayisi = min(8, max(1, d.integer(forKey: "baglantiSayisi")))
        fotograflaraKaydet = d.bool(forKey: "fotograflaraKaydet")
        altyaziDili = d.string(forKey: "altyaziDili") ?? ""
        otomatikAltyazi = d.bool(forKey: "otomatikAltyazi")
        bildirim = d.bool(forKey: "bildirim")
        panoyuIzle = d.bool(forKey: "panoyuIzle")
        tercihEdilenSesDili = d.string(forKey: "tercihEdilenSesDili") ?? ""
        listeKlasoru = d.bool(forKey: "listeKlasoru")
        listeNumarala = d.bool(forKey: "listeNumarala")
        indirilenleriAtla = d.bool(forKey: "indirilenleriAtla")
    }

    static let cozunurlukler = [0, 2160, 1440, 1080, 720, 480, 360, 240]
    static func cozunurlukAdi(_ c: Int) -> String { c == 0 ? "En iyi" : "\(c)p" }
}
