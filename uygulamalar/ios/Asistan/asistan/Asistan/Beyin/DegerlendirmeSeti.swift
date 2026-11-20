import Foundation
import Observation

/// P3.3: değerlendirme setinin bir örneği. Başlangıç seti `AsistanTests/Veri/DegerlendirmeSeti.json`'dadır;
/// telefonda balon menüsündeki "Değerlendirme setine ekle" ile yenileri birikir (Application Support/degerlendirme.json)
/// ve Ayarlar → Kalite ve değerlendirme ekranından JSON olarak paylaşılır.
nonisolated struct DegerlendirmeOrnegi: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var istek: String
    /// `YolTahmini.yollar` değerlerinden biri.
    var beklenenYol: String
    /// "low" / "medium" / "high"; nil ise çaba denetlenmez.
    var beklenenCaba: String? = nil
    /// Araçsız yarışa (hızlı yol) uygunluk beklentisi; nil ise denetlenmez.
    var hizliUygun: Bool? = nil
    /// Canlı (kuru çalışma) turda AjanDefteri adımlarında geçmesi beklenen araç adları (`Tool.name`).
    var beklenenAraclar: [String] = []
    /// "Yaptım" bekçisi için örnek yanıt; varsa `EylemIddiasi.denetle(_, basariliAraclar: [])` sonucu `eylemIddiasiBeklenir` ile eşleşmeli.
    var ornekYanit: String? = nil
    var eylemIddiasiBeklenir: Bool? = nil
    var not: String? = nil
    var eklenme = Date()

    init(istek: String, beklenenYol: String, beklenenCaba: String? = nil, hizliUygun: Bool? = nil, beklenenAraclar: [String] = [],
         ornekYanit: String? = nil, eylemIddiasiBeklenir: Bool? = nil, not: String? = nil, eklenme: Date = Date()) {
        self.istek = istek; self.beklenenYol = beklenenYol; self.beklenenCaba = beklenenCaba; self.hizliUygun = hizliUygun
        self.beklenenAraclar = beklenenAraclar; self.ornekYanit = ornekYanit; self.eylemIddiasiBeklenir = eylemIddiasiBeklenir
        self.not = not; self.eklenme = eklenme
    }

    enum CodingKeys: String, CodingKey {
        case id, istek, beklenenYol, beklenenCaba, hizliUygun, beklenenAraclar, ornekYanit, eylemIddiasiBeklenir, not, eklenme
    }

    /// Elle yazılan başlangıç setinde yalnız `istek` ve `beklenenYol` zorunludur.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        istek = try c.decode(String.self, forKey: .istek)
        beklenenYol = try c.decode(String.self, forKey: .beklenenYol)
        beklenenCaba = try c.decodeIfPresent(String.self, forKey: .beklenenCaba)
        hizliUygun = try c.decodeIfPresent(Bool.self, forKey: .hizliUygun)
        beklenenAraclar = try c.decodeIfPresent([String].self, forKey: .beklenenAraclar) ?? []
        ornekYanit = try c.decodeIfPresent(String.self, forKey: .ornekYanit)
        eylemIddiasiBeklenir = try c.decodeIfPresent(Bool.self, forKey: .eylemIddiasiBeklenir)
        not = try c.decodeIfPresent(String.self, forKey: .not)
        eklenme = try c.decodeIfPresent(Date.self, forKey: .eklenme) ?? Date(timeIntervalSince1970: 0)
    }
}

/// P3.3: `gonder` yönlendirme sırasının yan etkisiz taklidi (ağ, model, araç çağrısı yok).
/// Sıra `Beyin.gonder` ile aynıdır: yerel (kısa yanıt, saat, yerel komut) → muzik → (kip seçimi) yarış →
/// atölye → sunucu (kod) → doğrudan araştırma → zincir. Varsayılan ayarlar varsayılır: otomatik model ve kip,
/// araç politikaları "otomatik", çaba "auto", web araması açık. Önceki konuşmaya bağlı devam kararları (`devamKipi`)
/// ve çalışma anındaki düşüşler (yarışın [ARAMA] işareti, müzikte sonuç yok) taklit edilmez.
nonisolated enum YolTahmini {
    /// `Beyin.sonYonlendirme` değerleri (gonder sırasıyla).
    static let yollar = ["yerel", "muzik", "yaris", "atolye", "sunucu", "arastirma", "zincir"]

    struct Sonuc: Equatable, Sendable {
        let yol: String
        let caba: DusunmeSecimi.Caba
        let hizliUygun: Bool
        let kip: CalismaKipi
    }

    static func tahmin(_ metin: String, ekVar: Bool = false, sunucuGorevleri: Bool = true,
                       webArama: Bool = true) -> Sonuc {
        let t = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        let kip = AtolyeYonlendirme.hizli(t, ekVar: ekVar) ?? AtolyeYonlendirme.yerel(t, ekVar: ekVar)
        let caba = DusunmeSecimi.sec(t, ayar: "auto", kip: kip, belgeBoyutu: 0, gorsel: ekVar)
        let hizli = Beyin.yarisAdayiMi(t, kip: kip, caba: caba, ekVar: ekVar, otomatik: true, yalnizAnahtar: false)
        func sonuc(_ yol: String) -> Sonuc { Sonuc(yol: yol, caba: caba, hizliUygun: hizli, kip: kip) }
        // yerelYanitDene + yerelKomutDene
        if !ekVar, HizliModelSecimi.yerelKisaYanit(t) != nil || HizliModelSecimi.yerelSaat(t) != nil || YerelKomut.coz(t) != nil {
            return sonuc("yerel")
        }
        // muzikDene
        if !ekVar, Beyin.muzikIstegi(t) != nil { return sonuc("muzik") }
        // paralelYarisDene
        if hizli { return sonuc("yaris") }
        // atolyeYonlendir
        if [.gorsel, .arsiv, .belge].contains(kip) { return sonuc("atolye") }
        // sunucuKodlamaDene
        if kip == .kod, sunucuGorevleri, !ekVar { return sonuc("sunucu") }
        // dogrudanArastirmaDene
        if kip == .arastirma, webArama, !ekVar, HizliModelSecimi.dogrudanArastirma(t) { return sonuc("arastirma") }
        return sonuc("zincir")
    }
}

/// P3.3: telefonda toplanan değerlendirme örnekleri (Application Support/degerlendirme.json; testte geçici dosya).
@MainActor @Observable
final class DegerlendirmeDeposu {
    static let ortak = DegerlendirmeDeposu()

    private(set) var ornekler: [DegerlendirmeOrnegi] = []
    let dosya: URL

    init(dosya: URL? = nil) {
        if let dosya {
            self.dosya = dosya
        } else if OnayKapisi.testte {
            self.dosya = FileManager.default.temporaryDirectory.appendingPathComponent("degerlendirme-\(UUID().uuidString).json")
        } else {
            let taban = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
            self.dosya = taban.appendingPathComponent("degerlendirme.json")
        }
        ornekler = (try? Data(contentsOf: self.dosya)).flatMap { try? Self.coz($0) } ?? []
    }

    var hepsi: [DegerlendirmeOrnegi] { ornekler }

    func ekle(_ o: DegerlendirmeOrnegi) {
        ornekler.append(o)
        yaz()
    }

    func sil(_ id: UUID) {
        ornekler.removeAll { $0.id == id }
        yaz()
    }

    func hepsiniSil() {
        ornekler = []
        yaz()
    }

    /// Paylaşım için geçici kopya (Ayarlar → Kalite ve değerlendirme → Dışa aktar). Kopya eşzamanlı yazılır: ShareLink hemen okur.
    func disaAktar() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("degerlendirme-seti.json")
        try? Self.kodla(ornekler).write(to: url, options: .atomic)
        return url
    }

    nonisolated static func kodla(_ o: [DegerlendirmeOrnegi]) throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(o)
    }

    nonisolated static func coz(_ veri: Data) throws -> [DegerlendirmeOrnegi] {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode([DegerlendirmeOrnegi].self, from: veri)
    }

    nonisolated private static let yazmaKuyrugu = DispatchQueue(label: "asistan.degerlendirme-deposu", qos: .utility)

    /// Yazımlar tek seri kuyrukta, sırayla (AjanDefteri deseni).
    private func yaz() {
        let v = ornekler, url = dosya
        Self.yazmaKuyrugu.async { try? Self.kodla(v).write(to: url, options: .atomic) }
    }

    /// Test: bekleyen yazımların bitmesini bekler.
    nonisolated static func yazimlariBekle() { yazmaKuyrugu.sync {} }
}
