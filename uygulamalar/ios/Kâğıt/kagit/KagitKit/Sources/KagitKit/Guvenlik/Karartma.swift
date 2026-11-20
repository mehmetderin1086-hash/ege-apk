import CoreGraphics
import Foundation
import PDFKit

/// Hazır karartma desenleri.
public enum HazirDesen: String, CaseIterable, Sendable, Identifiable {
    case tcKimlik, telefon, eposta, iban, tarih

    public var id: String { rawValue }

    public var ad: String {
        switch self {
        case .tcKimlik: "T.C. kimlik no"
        case .telefon: "Telefon"
        case .eposta: "E-posta"
        case .iban: "IBAN"
        case .tarih: "Tarih"
        }
    }

    public var ifade: String {
        switch self {
        case .tcKimlik: #"(?<![\d])[1-9]\d{10}(?![\d])"#
        case .telefon: #"(?<![\d])(?:\+?90[\s.\-]?|0)?\(?[2-5]\d{2}\)?[\s.\-]?\d{3}[\s.\-]?\d{2}[\s.\-]?\d{2}(?![\d])"#
        case .eposta: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#
        case .iban: #"\b[A-Z]{2}\d{2}(?:\s?[A-Z0-9]{4}){3,7}(?:\s?[A-Z0-9]{1,3})?\b"#
        case .tarih: #"(?<![\d])(?:0?[1-9]|[12]\d|3[01])[./\-](?:0?[1-9]|1[0-2])[./\-](?:19|20)?\d{2}(?![\d])"#
        }
    }

    /// Eşleşmenin gerçekten bu türden olup olmadığını denetler (yanlış pozitifleri azaltır).
    public func dogrula(_ s: String) -> Bool {
        switch self {
        case .tcKimlik: return Self.tcGecerli(s)
        case .iban: return Self.ibanGecerli(s)
        default: return true
        }
    }

    static func tcGecerli(_ s: String) -> Bool {
        let d = s.compactMap { $0.wholeNumberValue }
        guard d.count == 11, s.count == 11, d[0] != 0 else { return false }
        let tek = d[0] + d[2] + d[4] + d[6] + d[8]
        let cift = d[1] + d[3] + d[5] + d[7]
        let onuncu = ((tek * 7 - cift) % 10 + 10) % 10
        guard onuncu == d[9] else { return false }
        return d[0...9].reduce(0, +) % 10 == d[10]
    }

    static func ibanGecerli(_ s: String) -> Bool {
        let temiz = s.filter { !$0.isWhitespace }.uppercased()
        guard temiz.count >= 15, temiz.count <= 34 else { return false }
        let donuk = String(temiz.dropFirst(4)) + String(temiz.prefix(4))
        var kalan = 0
        for c in donuk {
            guard let ascii = c.asciiValue else { return false }
            let sayi: Int
            switch ascii {
            case 48...57: sayi = Int(ascii) - 48
            case 65...90: sayi = Int(ascii) - 55
            default: return false
            }
            kalan = sayi >= 10 ? (kalan * 100 + sayi) % 97 : (kalan * 10 + sayi) % 97
        }
        return kalan == 1
    }
}

/// Neyin karartılacağını tarif eden kural.
public enum KarartmaKurali: Sendable, Equatable {
    /// Sözcük ya da ifade (boşluklar satır sonlarını da eşler).
    case ifade(String, buyukKucukDuyarli: Bool = false)
    /// Düzenli ifade (ICU).
    case duzenliIfade(String, buyukKucukDuyarli: Bool = false)
    case hazir(HazirDesen)

    func derle() throws -> (NSRegularExpression, HazirDesen?) {
        switch self {
        case .ifade(let s, let duyarli):
            let parcalar = s.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }
            guard !parcalar.isEmpty else { throw KagitHata.genel("Boş ifade karartılamaz.") }
            return (try NSRegularExpression(pattern: parcalar.joined(separator: #"\s+"#),
                                            options: duyarli ? [] : [.caseInsensitive]), nil)
        case .duzenliIfade(let s, let duyarli):
            do {
                return (try NSRegularExpression(pattern: s, options: duyarli ? [] : [.caseInsensitive]), nil)
            } catch {
                throw KagitHata.genel("Düzenli ifade geçersiz: \(s)")
            }
        case .hazir(let d):
            return (try NSRegularExpression(pattern: d.ifade, options: []), d)
        }
    }
}

/// Karartılacak bir bölge. `kutu`, sayfanın EKRANDAKİ (kırpma kutusu + döndürme uygulanmış) görünümünde
/// punto cinsinden, sol alt köşe başlangıçlıdır; `Karartma.ekranBoyutu` ile aynı uzay.
public struct KarartmaBolgesi: Sendable, Equatable, Identifiable {
    public var id: String { "\(sayfa):\(Int(kutu.minX)):\(Int(kutu.minY)):\(Int(kutu.width)):\(Int(kutu.height))" }
    public var sayfa: Int
    public var kutu: CGRect
    /// Eşleşen metin (elle çizilen bölgede nil).
    public var metin: String?

    public init(sayfa: Int, kutu: CGRect, metin: String? = nil) {
        self.sayfa = sayfa
        self.kutu = kutu
        self.metin = metin
    }
}

public struct KarartmaSecenekleri: Sendable {
    /// Rasterleştirme çözünürlüğü (200-300).
    public var dpi: CGFloat = 250
    /// Kalan metin için görünmez OCR katmanı ekle (karartılan alan görüntüde siyah olduğundan okunmaz).
    public var kalanMetinIcinOCR = true
    /// Karartılmayan sayfalardaki bütün açıklamaları da sil.
    public var aciklamalariSil = true
    /// Belge üst verisini (Info + XMP) temizle.
    public var ustVeriyiTemizle = true
    /// Yer imlerini (başlık metni sızdırabilir) sil.
    public var yerImleriniSil = true
    /// Kutunun her yönde genişletileceği pay (punto).
    public var kenarPayi: CGFloat = 2
    public var diller: [String] = MetinTanima.varsayilanDiller
    public var jpegKalitesi: Double = 0.85

    public init() {}
}

public struct KarartmaRaporu: Sendable, Equatable {
    public var karartilanBolge = 0
    public var degisenSayfalar: [Int] = []
    public var silinenAciklama = 0
    public var ustVeri: UstVeriRaporu?
}

/// Gerçek karartma: etkilenen sayfalar rasterleştirilir, siyah kutular piksele basılır, sayfa görüntü
/// olarak değiştirilir. Özgün metin nesneleri çıktıda bulunmaz.
public enum Karartma {

    // MARK: - Uzay dönüşümleri

    /// Sayfanın ekrandaki boyutu (punto): kırpma kutusu, döndürme dahil.
    public static func ekranBoyutu(_ sayfa: PDFPage) -> CGSize {
        let k = sayfa.bounds(for: .cropBox)
        return sayfa.rotation % 180 != 0 ? CGSize(width: k.height, height: k.width) : k.size
    }

    /// Sayfa uzayındaki (PDFKit) dikdörtgeni ekran uzayına çevirir.
    public static func ekranKutusu(_ r: CGRect, sayfa: PDFPage) -> CGRect {
        let k = sayfa.bounds(for: .cropBox)
        let rot = ((sayfa.rotation % 360) + 360) % 360
        func don(_ p: CGPoint) -> CGPoint {
            let x = p.x - k.minX, y = p.y - k.minY
            switch rot {
            case 90: return CGPoint(x: y, y: k.width - x)
            case 180: return CGPoint(x: k.width - x, y: k.height - y)
            case 270: return CGPoint(x: k.height - y, y: x)
            default: return CGPoint(x: x, y: y)
            }
        }
        let a = don(CGPoint(x: r.minX, y: r.minY)), b = don(CGPoint(x: r.maxX, y: r.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // MARK: - Arama

    /// Kurallara uyan bölgeleri bulur. Metin katmanı olan sayfalarda PDF metni, olmayanlarda OCR kullanılır.
    public static func bul(veri: Data, parola: String? = nil, kurallar: [KarartmaKurali],
                           ocrDiller: [String] = MetinTanima.varsayilanDiller,
                           ilerleme: Ilerleme? = nil) async throws -> [KarartmaBolgesi] {
        let belge = try Belge.ac(veri: veri, parola: parola)
        let derlenmis = try kurallar.map { try $0.derle() }
        guard !derlenmis.isEmpty else { return [] }
        var sonuc: [KarartmaBolgesi] = []
        for i in 0..<belge.pageCount {
            try iptalDenetle()
            guard let sayfa = belge.page(at: i) else { continue }
            if AranabilirPDF.metniVarMi(sayfa) {
                sonuc += metinSayfasindaBul(sayfa, indeks: i, derlenmis)
            } else if let goruntu = PDFCizim.goruntu(sayfa, dpi: 200) {
                let satirlar = try await MetinTanima.taniAyrintili(goruntu, diller: ocrDiller)
                sonuc += ocrSatirlarindaBul(satirlar, sayfa: sayfa, indeks: i, derlenmis)
            }
            ilerleme?(Double(i + 1) / Double(belge.pageCount))
        }
        return tekillestir(sonuc)
    }

    static func metinSayfasindaBul(_ sayfa: PDFPage, indeks: Int,
                                   _ kurallar: [(NSRegularExpression, HazirDesen?)]) -> [KarartmaBolgesi] {
        let metin = sayfa.string ?? ""
        let ns = metin as NSString
        var sonuc: [KarartmaBolgesi] = []
        for (ifade, desen) in kurallar {
            for m in ifade.matches(in: metin, range: NSRange(location: 0, length: ns.length)) {
                let eslesen = ns.substring(with: m.range)
                if let desen, !desen.dogrula(eslesen) { continue }
                guard let secim = sayfa.selection(for: m.range) else { continue }
                for satir in secim.selectionsByLine() {
                    let r = satir.bounds(for: sayfa)
                    guard r.width > 0, r.height > 0 else { continue }
                    sonuc.append(KarartmaBolgesi(sayfa: indeks, kutu: ekranKutusu(r, sayfa: sayfa), metin: eslesen))
                }
            }
        }
        return sonuc
    }

    static func ocrSatirlarindaBul(_ satirlar: [OCRAyrintiliSatir], sayfa: PDFPage, indeks: Int,
                                   _ kurallar: [(NSRegularExpression, HazirDesen?)]) -> [KarartmaBolgesi] {
        let boyut = ekranBoyutu(sayfa)
        var sonuc: [KarartmaBolgesi] = []
        for satir in satirlar {
            let ns = satir.metin as NSString
            for (ifade, desen) in kurallar {
                for m in ifade.matches(in: satir.metin, range: NSRange(location: 0, length: ns.length)) {
                    let eslesen = ns.substring(with: m.range)
                    if let desen, !desen.dogrula(eslesen) { continue }
                    let n = satir.kutu(aralik: m.range) ?? satir.kutu
                    sonuc.append(KarartmaBolgesi(
                        sayfa: indeks,
                        kutu: CGRect(x: n.minX * boyut.width, y: n.minY * boyut.height,
                                     width: n.width * boyut.width, height: n.height * boyut.height),
                        metin: eslesen))
                }
            }
        }
        return sonuc
    }

    static func tekillestir(_ b: [KarartmaBolgesi]) -> [KarartmaBolgesi] {
        var gorulen = Set<String>()
        return b.filter { gorulen.insert($0.id).inserted }
    }

    // MARK: - Uygulama

    /// Bölgeleri karartır. Çıktıda karartılan sayfaların metin nesneleri yoktur; doğrulama başarısızsa hata verir.
    public static func uygula(veri: Data, parola: String? = nil, bolgeler: [KarartmaBolgesi],
                              secenekler: KarartmaSecenekleri = .init(),
                              ilerleme: Ilerleme? = nil) async throws -> (veri: Data, rapor: KarartmaRaporu) {
        guard !bolgeler.isEmpty else { throw KagitHata.genel("Karartılacak bölge yok.") }
        let belge = try Belge.ac(veri: veri, parola: parola)
        var rapor = KarartmaRaporu(karartilanBolge: bolgeler.count)
        let gruplar = Dictionary(grouping: bolgeler, by: \.sayfa)
        let sayfalar = gruplar.keys.sorted()
        for i in sayfalar where i < 0 || i >= belge.pageCount {
            throw KagitHata.genel("Geçersiz sayfa: \(i + 1)")
        }

        for (adim, i) in sayfalar.enumerated() {
            try iptalDenetle()
            guard let sayfa = belge.page(at: i), let kutular = gruplar[i] else { continue }
            let boyut = ekranBoyutu(sayfa)
            guard let ham = PDFCizim.goruntu(sayfa, dpi: secenekler.dpi) else {
                throw KagitHata.genel("Sayfa \(i + 1) rasterleştirilemedi.")
            }
            let kara = try siyahBas(ham, kutular: kutular.map(\.kutu), boyut: boyut, pay: secenekler.kenarPayi)
            let satirlar = secenekler.kalanMetinIcinOCR
                ? ((try? await MetinTanima.tani(kara, diller: secenekler.diller)) ?? []) : []
            let jpeg = PDFCizim.kodla(kara, tur: .jpeg, kalite: secenekler.jpegKalitesi)
            let sayfaVeri = AranabilirPDF.gorselSayfaPDF(kara, jpeg: jpeg, boyut: boyut, satirlar: satirlar)
            guard let yeni = PDFDocument(data: sayfaVeri)?.page(at: 0) else {
                throw KagitHata.genel("Karartılmış sayfa \(i + 1) oluşturulamadı.")
            }
            belge.insert(yeni, at: i)
            belge.removePage(at: i + 1)
            rapor.degisenSayfalar.append(i)
            ilerleme?(Double(adim + 1) / Double(sayfalar.count) * 0.9)
        }

        // Karartılmayan sayfalardaki sızıntılar: açıklamalar, form değerleri, yer imleri.
        let yasakli = Set(bolgeler.compactMap(\.metin).map { TurkceMetin.anahtar($0) }.filter { !$0.isEmpty })
        let degisenler = Set(rapor.degisenSayfalar)
        for i in 0..<belge.pageCount where !degisenler.contains(i) {
            guard let sayfa = belge.page(at: i) else { continue }
            for a in sayfa.annotations {
                let metinler = [a.contents, a.widgetStringValue, a.userName].compactMap { $0 }.map { TurkceMetin.anahtar($0) }
                let sizar = metinler.contains { m in yasakli.contains { m.contains($0) } }
                if secenekler.aciklamalariSil && a.type != "Link" || sizar {
                    sayfa.removeAnnotation(a)
                    rapor.silinenAciklama += 1
                }
            }
        }
        if secenekler.yerImleriniSil { belge.outlineRoot = nil }
        if secenekler.ustVeriyiTemizle { belge.documentAttributes = [:] }

        var cikti = try Belge.veri(belge, secenekler: UstVeriIslemleri.korumaSecenekleri(belge, parola))
        if secenekler.ustVeriyiTemizle {
            let (temiz, ur) = try UstVeriIslemleri.xmpTemizle(cikti, parola: parola)
            cikti = temiz
            rapor.ustVeri = ur
        }
        try dogrula(cikti, parola: parola, sayfalar: rapor.degisenSayfalar, yasakli: yasakli, sayfaSayisi: belge.pageCount)
        ilerleme?(1)
        return (cikti, rapor)
    }

    /// Arama kurallarıyla ve/veya elle çizilmiş bölgelerle tek adımda karartır.
    public static func karart(veri: Data, parola: String? = nil, kurallar: [KarartmaKurali],
                              elleBolgeler: [KarartmaBolgesi] = [],
                              secenekler: KarartmaSecenekleri = .init(),
                              ilerleme: Ilerleme? = nil) async throws -> (veri: Data, rapor: KarartmaRaporu) {
        let bulunan = try await bul(veri: veri, parola: parola, kurallar: kurallar, ocrDiller: secenekler.diller)
        return try await uygula(veri: veri, parola: parola, bolgeler: bulunan + elleBolgeler,
                                secenekler: secenekler, ilerleme: ilerleme)
    }

    /// Siyah kutuları piksellere basar.
    static func siyahBas(_ ham: CGImage, kutular: [CGRect], boyut: CGSize, pay: CGFloat) throws -> CGImage {
        guard let ctx = CGContext(data: nil, width: ham.width, height: ham.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw KagitHata.genel("Görüntü bağlamı oluşturulamadı.")
        }
        ctx.draw(ham, in: CGRect(x: 0, y: 0, width: ham.width, height: ham.height))
        let sx = CGFloat(ham.width) / boyut.width, sy = CGFloat(ham.height) / boyut.height
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        for k in kutular {
            let r = k.insetBy(dx: -pay, dy: -pay)
            ctx.fill(CGRect(x: r.minX * sx, y: r.minY * sy, width: r.width * sx, height: r.height * sy).integral)
        }
        guard let sonuc = ctx.makeImage() else { throw KagitHata.genel("Karartılmış görüntü üretilemedi.") }
        return sonuc
    }

    /// Çıktıyı yeniden açıp karartılan sayfalarda yasaklı metin kalmadığını doğrular.
    static func dogrula(_ veri: Data, parola: String?, sayfalar: [Int], yasakli: Set<String>, sayfaSayisi: Int) throws {
        guard let belge = PDFDocument(data: veri) else { throw KagitHata.dogrulamaBasarisiz("çıktı açılamıyor") }
        if belge.isLocked {
            guard let parola, belge.unlock(withPassword: parola) else { throw KagitHata.dogrulamaBasarisiz("çıktı açılamıyor") }
        }
        guard belge.pageCount == sayfaSayisi else { throw KagitHata.dogrulamaBasarisiz("sayfa sayısı değişti") }
        for i in sayfalar {
            let s = TurkceMetin.anahtar(belge.page(at: i)?.string ?? "")
            for y in yasakli where s.contains(y) {
                throw KagitHata.dogrulamaBasarisiz("karartılan metin sayfa \(i + 1)'de hâlâ bulunuyor")
            }
        }
    }
}
