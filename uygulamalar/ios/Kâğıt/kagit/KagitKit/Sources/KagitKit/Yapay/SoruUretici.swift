import Foundation

public enum SoruTuru: String, Codable, CaseIterable, Sendable, Identifiable {
    case coktanSecmeli = "coktan_secmeli"
    case dogruYanlis = "dogru_yanlis"
    case bosluk = "bosluk_doldurma"
    case acikUclu = "acik_uclu"
    case eslestirme = "eslestirme"

    public var id: String { rawValue }
    public var ad: String {
        switch self {
        case .coktanSecmeli: "Çoktan seçmeli"
        case .dogruYanlis: "Doğru-yanlış"
        case .bosluk: "Boşluk doldurma"
        case .acikUclu: "Açık uçlu"
        case .eslestirme: "Eşleştirme"
        }
    }

    /// Sınav kâğıdında bölüm başlığı.
    public var bolumAdi: String {
        switch self {
        case .coktanSecmeli: "Aşağıdaki soruların doğru cevabını işaretleyiniz."
        case .dogruYanlis: "Aşağıdaki ifadeler doğruysa (D), yanlışsa (Y) yazınız."
        case .bosluk: "Aşağıdaki cümlelerde boş bırakılan yerleri uygun ifadelerle doldurunuz."
        case .acikUclu: "Aşağıdaki soruları kısaca yanıtlayınız."
        case .eslestirme: "Aşağıdaki kavramları karşılıklarıyla eşleştiriniz."
        }
    }

    static func coz(_ s: String) -> SoruTuru? {
        let k = TurkceMetin.anahtar(s)
        if let t = SoruTuru(rawValue: s) { return t }
        if k.contains("coktan") || k.contains("test") { return .coktanSecmeli }
        if k.contains("dogru") || k.contains("yanlis") { return .dogruYanlis }
        if k.contains("bosluk") { return .bosluk }
        if k.contains("acik") || k.contains("klasik") { return .acikUclu }
        if k.contains("eslestirme") || k.contains("eslesme") { return .eslestirme }
        return nil
    }
}

public struct EslesmeCifti: Codable, Hashable, Sendable {
    public var sol: String
    public var sag: String
    public init(sol: String, sag: String) { self.sol = sol; self.sag = sag }
}

/// Yapay zekânın ürettiği (ve öğretmenin düzenleyebildiği) tek soru.
public struct UretilenSoru: Codable, Hashable, Sendable, Identifiable {
    public var id = UUID()
    public var tur: SoruTuru
    public var metin: String
    /// Çoktan seçmelide A-E şıkları (öndeki “A)” olmadan).
    public var secenekler: [String] = []
    /// Çoktan seçmeli: "A"-"E"; doğru-yanlış: "Doğru"/"Yanlış"; boşluk/açık uçlu: beklenen yanıt.
    public var dogru: String
    public var aciklama: String = ""
    public var ciftler: [EslesmeCifti] = []

    enum CodingKeys: String, CodingKey { case tur, metin, secenekler, dogru, aciklama, ciftler }

    public init(tur: SoruTuru, metin: String, secenekler: [String] = [], dogru: String,
                aciklama: String = "", ciftler: [EslesmeCifti] = []) {
        self.tur = tur
        self.metin = metin
        self.secenekler = secenekler
        self.dogru = dogru
        self.aciklama = aciklama
        self.ciftler = ciftler
    }
}

public enum SoruZorlugu: String, CaseIterable, Sendable, Identifiable {
    case kolay, orta, zor, karisik
    public var id: String { rawValue }
    public var ad: String {
        switch self {
        case .kolay: "Kolay"
        case .orta: "Orta"
        case .zor: "Zor"
        case .karisik: "Karışık"
        }
    }
}

public struct SoruIstegi: Sendable {
    /// Tür başına istenen soru sayısı.
    public var adetler: [SoruTuru: Int]
    public var zorluk: SoruZorlugu
    /// Örn. "9. sınıf".
    public var sinif: String
    public var konu: String

    public init(adetler: [SoruTuru: Int], zorluk: SoruZorlugu = .orta, sinif: String = "9. sınıf", konu: String = "") {
        self.adetler = adetler
        self.zorluk = zorluk
        self.sinif = sinif
        self.konu = konu
    }
    public var toplam: Int { adetler.values.reduce(0, +) }
}

/// Modelden gelen ham soru (esnek anahtar adları).
struct HamSoru: Decodable {
    var tur: String?
    var metin: String
    var secenekler: [String]
    var dogru: String
    var aciklama: String
    var ciftler: [EslesmeCifti]

    struct Anahtar: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from d: Decoder) throws {
        let k = try d.container(keyedBy: Anahtar.self)
        func metinAl(_ adlar: [String]) -> String? {
            for a in adlar {
                if let key = Anahtar(stringValue: a) {
                    if let s = try? k.decodeIfPresent(String.self, forKey: key) { return s }
                    if let n = try? k.decodeIfPresent(Int.self, forKey: key) { return String(n) }
                }
            }
            return nil
        }
        tur = metinAl(["tur", "tür", "type"])
        metin = metinAl(["soru", "metin", "soru_metni", "question"]) ?? ""
        dogru = metinAl(["dogru", "doğru", "cevap", "dogru_cevap", "answer"]) ?? ""
        aciklama = metinAl(["aciklama", "açıklama", "cozum", "çözüm", "explanation"]) ?? ""
        var sec: [String] = []
        for a in ["secenekler", "seçenekler", "siklar", "şıklar", "options"] {
            if let key = Anahtar(stringValue: a), let l = try? k.decodeIfPresent([String].self, forKey: key) { sec = l; break }
            if let key = Anahtar(stringValue: a), let sz = try? k.decodeIfPresent([String: String].self, forKey: key) {
                sec = sz.sorted { $0.key < $1.key }.map(\.value); break
            }
        }
        secenekler = sec
        var cf: [EslesmeCifti] = []
        for a in ["ciftler", "çiftler", "eslestirme", "eşleştirme", "pairs"] {
            if let key = Anahtar(stringValue: a), let l = try? k.decodeIfPresent([EslesmeCifti].self, forKey: key) { cf = l; break }
        }
        ciftler = cf
    }
}

private struct SorularKabi: Decodable { var sorular: [HamSoru] }

public enum SoruDogrulama {

    /// Modelin JSON yanıtını ayrıştırır ve geçersiz soruları eler.
    public static func ayristir(_ ham: String, varsayilanTur: SoruTuru) throws -> [UretilenSoru] {
        let liste: [HamSoru]
        if let kabi = try? JSONAyikla.coz(SorularKabi.self, ham) {
            liste = kabi.sorular
        } else {
            liste = try JSONAyikla.coz([HamSoru].self, ham)
        }
        return liste.compactMap { dogrula($0, varsayilan: varsayilanTur) }
    }

    static func sikTemizle(_ s: String) -> String {
        s.replacingOccurrences(of: #"^\s*\(?[A-Ea-e][\)\.\:]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func dogrula(_ h: HamSoru, varsayilan: SoruTuru) -> UretilenSoru? {
        let tur = h.tur.flatMap(SoruTuru.coz) ?? varsayilan
        let metin = h.metin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard metin.count >= 8 else { return nil }
        let aciklama = h.aciklama.trimmingCharacters(in: .whitespacesAndNewlines)
        let dogru = h.dogru.trimmingCharacters(in: .whitespacesAndNewlines)
        switch tur {
        case .coktanSecmeli:
            let sec = h.secenekler.map(sikTemizle)
            guard sec.count == 5, sec.allSatisfy({ !$0.isEmpty }), Set(sec.map(TurkceMetin.anahtar)).count == 5 else { return nil }
            guard let harf = dogru.uppercased().first(where: { "ABCDE".contains($0) }),
                  dogru.count <= 3 || dogru.uppercased().hasPrefix(String(harf)) else { return nil }
            return UretilenSoru(tur: tur, metin: metin, secenekler: sec, dogru: String(harf), aciklama: aciklama)
        case .dogruYanlis:
            let k = TurkceMetin.anahtar(dogru)
            let d: String
            if ["dogru", "d", "true", "evet"].contains(k) { d = "Doğru" }
            else if ["yanlis", "y", "false", "hayir"].contains(k) { d = "Yanlış" }
            else { return nil }
            return UretilenSoru(tur: tur, metin: metin, dogru: d, aciklama: aciklama)
        case .bosluk:
            guard !dogru.isEmpty else { return nil }
            var m = metin.replacingOccurrences(of: #"[_\.…]{3,}"#, with: "________", options: .regularExpression)
            if !m.contains("________") { return nil }
            m = m.replacingOccurrences(of: "(________)", with: "________")
            return UretilenSoru(tur: tur, metin: m, dogru: dogru, aciklama: aciklama)
        case .acikUclu:
            guard !dogru.isEmpty else { return nil }
            return UretilenSoru(tur: tur, metin: metin, dogru: dogru, aciklama: aciklama)
        case .eslestirme:
            let c = h.ciftler.map { EslesmeCifti(sol: $0.sol.trimmingCharacters(in: .whitespacesAndNewlines),
                                                  sag: $0.sag.trimmingCharacters(in: .whitespacesAndNewlines)) }
            guard c.count >= 3, c.count <= 8, c.allSatisfy({ !$0.sol.isEmpty && !$0.sag.isEmpty }) else { return nil }
            return UretilenSoru(tur: tur, metin: metin, dogru: "", aciklama: aciklama, ciftler: c)
        }
    }
}

/// PDF metninden soru üretir.
public enum SoruUretici {

    static func tursel(_ t: SoruTuru, adet: Int) -> String {
        switch t {
        case .coktanSecmeli:
            return """
            \(adet) adet ÇOKTAN SEÇMELİ soru yaz. Her sorunun TAM 5 şıkkı (A, B, C, D, E) olsun, yalnızca biri doğru olsun; çeldiriciler inandırıcı olsun, “hepsi” / “hiçbiri” kullanma. MEB ve YKS üslubunda yaz.
            Biçim: {"tur":"coktan_secmeli","soru":"...","secenekler":["...","...","...","...","..."],"dogru":"C","aciklama":"..."}
            “secenekler” içinde “A)” gibi harf ön eki yazma.
            """
        case .dogruYanlis:
            return """
            \(adet) adet DOĞRU-YANLIŞ ifadesi yaz (yaklaşık yarısı yanlış olsun).
            Biçim: {"tur":"dogru_yanlis","soru":"ifade","dogru":"Doğru","aciklama":"..."}  (dogru yalnızca "Doğru" ya da "Yanlış")
            """
        case .bosluk:
            return """
            \(adet) adet BOŞLUK DOLDURMA sorusu yaz. Boşluğu "________" ile göster, her cümlede bir boşluk olsun.
            Biçim: {"tur":"bosluk_doldurma","soru":"... ________ ...","dogru":"beklenen sözcük","aciklama":"..."}
            """
        case .acikUclu:
            return """
            \(adet) adet AÇIK UÇLU soru yaz. “dogru” alanına örnek yanıt/puanlama anahtarını yaz.
            Biçim: {"tur":"acik_uclu","soru":"...","dogru":"örnek yanıt","aciklama":""}
            """
        case .eslestirme:
            return """
            \(adet) adet EŞLEŞTİRME sorusu yaz; her soruda 5 çift (sol: kavram, sağ: karşılığı) olsun.
            Biçim: {"tur":"eslestirme","soru":"Aşağıdaki kavramları eşleştiriniz.","ciftler":[{"sol":"...","sag":"..."}],"aciklama":""}
            """
        }
    }

    /// Kaynak metinden, bağlama sığacak ve konuya uygun bölümü seçer.
    static func kaynakSec(_ sayfalar: [Int: String], konu: String, sinir: Int) -> String {
        let tam = BelgeMetni.birlestir(sayfalar, etiketli: false)
        if tam.count <= sinir { return tam }
        let parcalar = Parcalayici.parcala(sayfalar, hedef: max(sinir / 6, 600))
        var secilen: [BelgeParcasi] = []
        if !konu.trimmingCharacters(in: .whitespaces).isEmpty {
            secilen = BM25Dizin(parcalar: parcalar).ara(konu, en: 12).map(\.parca)
        }
        if secilen.isEmpty {
            // Konu yoksa belgeyi eşit aralıklarla örnekle
            let adim = max(1, parcalar.count / 6)
            secilen = stride(from: 0, to: parcalar.count, by: adim).map { parcalar[$0] }
        }
        var boy = 0
        var kullan: [BelgeParcasi] = []
        for p in secilen where boy + p.metin.count <= sinir {
            kullan.append(p); boy += p.metin.count
        }
        if kullan.isEmpty, let p = secilen.first { return String(p.metin.prefix(sinir)) }
        return kullan.sorted { $0.sayfaBas < $1.sayfaBas }.map(\.metin).joined(separator: "\n\n")
    }

    public static func uret(sayfalar: [Int: String], istek: SoruIstegi, yz: YapayZeka,
                            ilerleme: Ilerleme? = nil) async throws -> [UretilenSoru] {
        guard !sayfalar.isEmpty else { throw KagitHata.yapayZeka("Soru üretilecek metin bulunamadı.") }
        guard istek.toplam > 0 else { throw KagitHata.bosGirdi }
        let kaynak = kaynakSec(sayfalar, konu: istek.konu, sinir: max(Int(Double(yz.baglamSiniri) * 0.6), 1500))
        let turler = SoruTuru.allCases.filter { (istek.adetler[$0] ?? 0) > 0 }
        var hepsi: [UretilenSoru] = []
        for (i, tur) in turler.enumerated() {
            try iptalDenetle()
            let adet = istek.adetler[tur] ?? 0
            var uretilen: [UretilenSoru] = []
            for deneme in 0..<2 {
                let eksik = adet - uretilen.count
                if eksik <= 0 { break }
                let varOlanlar = uretilen.isEmpty ? "" : "\nBunlardan FARKLI sorular yaz; daha önce yazdıkların: " + uretilen.map(\.metin).joined(separator: " | ")
                let konuSatiri = istek.konu.isEmpty ? "" : "Konu odağı: \(istek.konu).\n"
                let istem = """
                Aşağıdaki ders metnine dayanarak \(istek.sinif) düzeyinde biyoloji soruları hazırla. Zorluk: \(istek.zorluk.ad.lowercased(with: TurkceMetin.yerel)).
                \(konuSatiri)Sorular yalnızca metindeki bilgiye dayansın, tek doğru cevabı olsun, Türkçe yazım kurallarına uysun.
                \(tursel(tur, adet: eksik))\(varOlanlar)

                YANIT: yalnızca {"sorular":[...]} biçiminde geçerli JSON ver; JSON dışında hiçbir şey yazma.

                METİN:
                \(kaynak)
                """
                do {
                    let y = try await yz.yanit(YapayIstek(sistem: "Sen deneyimli bir Türk lise biyoloji öğretmenisin ve sınav sorusu hazırlıyorsun. Yalnızca istenen JSON'u üret.",
                                                           kullanici: istem, azamiToken: 6000, sicaklik: deneme == 0 ? 0.5 : 0.8))
                    uretilen += try SoruDogrulama.ayristir(y.metin, varsayilanTur: tur).filter { $0.tur == tur }.prefix(eksik)
                } catch let h as KagitHata where h == .iptal {
                    throw h
                } catch {
                    if deneme == 1, uretilen.isEmpty { throw error }
                }
            }
            hepsi += uretilen
            ilerleme?(Double(i + 1) / Double(turler.count))
        }
        guard !hepsi.isEmpty else { throw KagitHata.yapayZeka("Geçerli soru üretilemedi. Metni ya da ayarları değiştirip yeniden deneyin.") }
        return hepsi
    }
}
