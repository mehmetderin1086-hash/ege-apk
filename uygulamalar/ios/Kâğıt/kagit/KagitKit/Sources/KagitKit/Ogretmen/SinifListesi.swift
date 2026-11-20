import Foundation
import PDFKit

public struct Ogrenci: Codable, Hashable, Sendable, Identifiable {
    public var id = UUID()
    /// Okul numarası (boş olabilir).
    public var no: String
    /// “Ad Soyad”
    public var ad: String

    public init(no: String, ad: String) {
        self.no = no
        self.ad = ad
    }

    /// “123 Ayşe Yılmaz”
    public var tamAd: String { no.isEmpty ? ad : "\(no) \(ad)" }
}

public struct Sinif: Codable, Hashable, Sendable, Identifiable {
    public var id = UUID()
    public var ad: String
    public var ogrenciler: [Ogrenci]

    public init(ad: String, ogrenciler: [Ogrenci] = []) {
        self.ad = ad
        self.ogrenciler = ogrenciler
    }
}

/// Sınıf listelerini Application Support'ta JSON olarak saklar.
public struct SinifDeposu: Sendable {
    public let dosya: URL

    public init(dosya: URL? = nil) {
        if let dosya {
            self.dosya = dosya
        } else {
            let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            self.dosya = d.appendingPathComponent("siniflar.json")
        }
    }

    public func yukle() -> [Sinif] {
        guard let v = try? Data(contentsOf: dosya) else { return [] }
        return (try? JSONDecoder().decode([Sinif].self, from: v)) ?? []
    }

    public func kaydet(_ siniflar: [Sinif]) throws {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(siniflar).write(to: dosya, options: .atomic)
    }
}

/// Yapıştırılan metin, CSV, XLSX ve metinli PDF'ten öğrenci listesi çıkarır.
public enum SinifAyristirici {

    private static let cinsiyet: Set<String> = ["e", "k", "erkek", "kiz", "kız"]

    /// Tek satırdan öğrenci: “123 Ayşe Yılmaz”, “1 123 AYŞE YILMAZ K”, “Ayşe Yılmaz 123”, “123;Ayşe;Yılmaz”.
    public static func satir(_ ham: String, numaraZorunlu: Bool = false) -> Ogrenci? {
        var s = ham
        for ayirici in ["\t", ";", ",", "|"] { s = s.replacingOccurrences(of: ayirici, with: " ") }
        var parcalar = s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        parcalar = parcalar.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }.filter { !$0.isEmpty }
        guard !parcalar.isEmpty else { return nil }

        func sayisal(_ p: String) -> Bool {
            let t = p.trimmingCharacters(in: CharacterSet(charactersIn: ".)"))
            return !t.isEmpty && t.allSatisfy(\.isNumber) && t.count <= 7
        }

        var sayilar: [String] = []
        // Baştaki sayılar: [sıra] no
        while let ilk = parcalar.first, sayisal(ilk), sayilar.count < 2 {
            sayilar.append(ilk.trimmingCharacters(in: CharacterSet(charactersIn: ".)")))
            parcalar.removeFirst()
        }
        // Sondaki sayı (Ad Soyad 123)
        if sayilar.isEmpty, let son = parcalar.last, sayisal(son), parcalar.count >= 2 {
            sayilar.append(son)
            parcalar.removeLast()
        }
        // e-Okul: sıra no + okul no ise ikincisi okul numarasıdır; yalnız bir sayı varsa o numaradır.
        let no = sayilar.count >= 2 ? sayilar[1] : (sayilar.first ?? "")

        // Sondaki cinsiyet sütunu
        if parcalar.count >= 3, let son = parcalar.last, cinsiyet.contains(TurkceMetin.kucuk(son)) { parcalar.removeLast() }
        let adParcalari = parcalar.filter { p in p.contains(where: \.isLetter) && !p.contains(where: \.isNumber) }
        guard adParcalari.count == parcalar.count, !adParcalari.isEmpty else { return nil }
        if adParcalari.count == 1, no.isEmpty { return nil }   // tek sözcük ve numarasız: büyük olasılıkla başlık/gürültü
        if numaraZorunlu, no.isEmpty { return nil }
        let ad = duzgunAd(adParcalari.joined(separator: " "))
        let ozel: Set<String> = ["ogrenci", "ad", "adi", "soyad", "soyadi", "sira", "no", "numara", "sinif", "sinifi", "cinsiyet", "liste", "listesi", "okul", "ogretmen", "sayfa", "tarih"]
        if adParcalari.contains(where: { ozel.contains(TurkceMetin.anahtar($0)) }) { return nil }
        return Ogrenci(no: no, ad: ad)
    }

    /// “AYŞE YILMAZ” → “Ayşe Yılmaz”
    static func duzgunAd(_ s: String) -> String {
        let harfler = s.filter(\.isLetter)
        let hepsiBuyuk = !harfler.isEmpty && harfler == TurkceMetin.buyuk(harfler)
        let hepsiKucuk = !harfler.isEmpty && harfler == TurkceMetin.kucuk(harfler)
        guard hepsiBuyuk || hepsiKucuk else { return s }
        return s.capitalized(with: TurkceMetin.yerel)
    }

    /// Satır satır metin.
    public static func metin(_ s: String, numaraZorunlu: Bool = false) -> [Ogrenci] {
        benzersiz(s.components(separatedBy: .newlines).compactMap { satir($0, numaraZorunlu: numaraZorunlu) })
    }

    /// CSV: tırnaklı alanlar desteklenir; başlık satırı kendiliğinden elenir.
    public static func csv(_ s: String) -> [Ogrenci] {
        var satirlar: [String] = []
        for ham in s.components(separatedBy: .newlines) {
            var alanlar: [String] = []
            var simdiki = ""
            var tirnakta = false
            let ayirici: Character = ham.contains(";") ? ";" : (ham.contains("\t") ? "\t" : ",")
            for c in ham {
                if c == "\"" { tirnakta.toggle() }
                else if c == ayirici, !tirnakta { alanlar.append(simdiki); simdiki = "" }
                else { simdiki.append(c) }
            }
            alanlar.append(simdiki)
            satirlar.append(alanlar.joined(separator: " "))
        }
        return benzersiz(satirlar.compactMap { satir($0) })
    }

    /// XLSX: sharedStrings + ilk sayfa.
    public static func xlsx(_ veri: Data) -> [Ogrenci] {
        benzersiz(XLSXOkuyucu.satirlar(veri).compactMap { satir($0.joined(separator: " ")) })
    }

    /// Metinli PDF (e-Okul sınıf listesi gibi). Metin yoksa OCR denenir.
    public static func pdf(veri: Data) async -> [Ogrenci] {
        guard let belge = PDFDocument(data: veri) else { return [] }
        var metinler: [String] = []
        for i in 0..<belge.pageCount {
            if let s = belge.page(at: i)?.string, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metinler.append(s)
            } else if let sayfa = belge.page(at: i), let satirlar = try? await MetinTanima.tani(sayfa: sayfa, dpi: 200) {
                metinler.append(MetinTanima.metin(satirlar))
            }
        }
        // PDF metninde sıra/numara çoğu zaman aynı satırda gelir; numarasız satırlar gürültü sayılır.
        return benzersiz(metinler.joined(separator: "\n").components(separatedBy: .newlines)
            .compactMap { satir($0, numaraZorunlu: true) })
    }

    /// Aynı numaralı yinelenenleri ele (numarasızlar ad ile).
    static func benzersiz(_ liste: [Ogrenci]) -> [Ogrenci] {
        var gorulen = Set<String>()
        return liste.filter { o in
            let k = o.no.isEmpty ? "ad:" + TurkceMetin.anahtar(o.ad) : "no:" + o.no
            return gorulen.insert(k).inserted
        }
    }

    /// Dosya uzantısına göre içe aktarır.
    public static func dosya(_ veri: Data, uzanti: String) async -> [Ogrenci] {
        switch uzanti.lowercased() {
        case "xlsx": return xlsx(veri)
        case "pdf": return await pdf(veri: veri)
        case "csv", "tsv": return csv(String(decoding: veri, as: UTF8.self))
        default: return metin(String(decoding: veri, as: UTF8.self))
        }
    }
}

/// XLSX'ten ilk sayfanın hücre metinlerini satır satır okur.
enum XLSXOkuyucu {
    static func satirlar(_ veri: Data) -> [[String]] {
        let dosyalar = ZipOkuyucu.ac(veri)
        var paylasilan: [String] = []
        if let v = dosyalar["xl/sharedStrings.xml"] {
            let k = PaylasilanDizgiler()
            k.coz(v)
            paylasilan = k.dizgiler
        }
        let sayfaAdi = dosyalar.keys.filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }.sorted().first
        guard let sayfaAdi, let sayfa = dosyalar[sayfaAdi] else { return [] }
        let k = SayfaOkuyucu(paylasilan: paylasilan)
        k.coz(sayfa)
        return k.satirlar
    }

    final class PaylasilanDizgiler: NSObject, XMLParserDelegate {
        var dizgiler: [String] = []
        private var simdiki = ""
        private var icinde = false
        private var siIcinde = false

        func coz(_ v: Data) {
            let p = XMLParser(data: v)
            p.delegate = self
            p.parse()
        }
        func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            if e == "si" { siIcinde = true; simdiki = "" }
            if e == "t", siIcinde { icinde = true }
        }
        func parser(_ parser: XMLParser, foundCharacters s: String) { if icinde { simdiki += s } }
        func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
            if e == "t" { icinde = false }
            if e == "si" { dizgiler.append(simdiki); siIcinde = false }
        }
    }

    final class SayfaOkuyucu: NSObject, XMLParserDelegate {
        let paylasilan: [String]
        var satirlar: [[String]] = []
        private var satir: [(kol: Int, deger: String)] = []
        private var tur = ""
        private var kol = 0
        private var deger = ""
        private var degerIcinde = false

        init(paylasilan: [String]) { self.paylasilan = paylasilan }

        func coz(_ v: Data) {
            let p = XMLParser(data: v)
            p.delegate = self
            p.parse()
        }

        /// “C12” → 2 (0 tabanlı sütun)
        static func sutunNo(_ r: String) -> Int {
            var n = 0
            for c in r.unicodeScalars where c.value >= 65 && c.value <= 90 { n = n * 26 + Int(c.value - 64) }
            return max(n - 1, 0)
        }

        func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
            switch e {
            case "row": satir = []
            case "c": tur = a["t"] ?? ""; kol = Self.sutunNo(a["r"] ?? ""); deger = ""
            case "v", "t": degerIcinde = true
            default: break
            }
        }
        func parser(_ parser: XMLParser, foundCharacters s: String) { if degerIcinde { deger += s } }
        func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
            switch e {
            case "v", "t": degerIcinde = false
            case "c":
                var d = deger
                if tur == "s", let i = Int(deger.trimmingCharacters(in: .whitespaces)), i < paylasilan.count { d = paylasilan[i] }
                // Sayısal hücre “123.0” gelebilir
                if tur.isEmpty, d.hasSuffix(".0") { d = String(d.dropLast(2)) }
                satir.append((kol, d))
            case "row":
                satirlar.append(satir.sorted { $0.kol < $1.kol }.map(\.deger))
            default: break
            }
        }
    }
}
