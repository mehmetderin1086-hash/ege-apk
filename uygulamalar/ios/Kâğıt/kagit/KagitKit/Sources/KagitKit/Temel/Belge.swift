import CoreGraphics
import Foundation
import PDFKit

/// PDF dosyası yaşam döngüsü: açma, güvenli kaydetme, doğrulama.
///
/// Kural: `PDFDocument` hiçbir zaman iş parçacıkları arasında paylaşılmaz. Arka plan
/// işlerinde her iş kendi belgesini URL ya da `Data`'dan açar, sonucu dosyaya yazar.
public enum Belge {

    /// URL'den PDF açar. Parola korumalıysa verilen parolayla kilidi açar.
    public static func ac(_ url: URL, parola: String? = nil) throws -> PDFDocument {
        let erisim = url.startAccessingSecurityScopedResource()
        defer { if erisim { url.stopAccessingSecurityScopedResource() } }
        guard let belge = PDFDocument(url: url) else {
            throw KagitHata.acilamadi(url.lastPathComponent)
        }
        try kilitAc(belge, parola: parola)
        return belge
    }

    /// Bellekteki veriden PDF açar.
    public static func ac(veri: Data, ad: String = "belge", parola: String? = nil) throws -> PDFDocument {
        guard let belge = PDFDocument(data: veri) else { throw KagitHata.acilamadi(ad) }
        try kilitAc(belge, parola: parola)
        return belge
    }

    static func kilitAc(_ belge: PDFDocument, parola: String?) throws {
        guard belge.isLocked else { return }
        guard let parola, !parola.isEmpty else { throw KagitHata.parolaGerekli }
        if !belge.unlock(withPassword: parola) { throw KagitHata.parolaYanlis }
    }

    /// Dosya parola istiyor mu? (Açmadan önce arayüzde sormak için.)
    public static func parolaIstiyorMu(_ url: URL) -> Bool {
        let erisim = url.startAccessingSecurityScopedResource()
        defer { if erisim { url.stopAccessingSecurityScopedResource() } }
        return PDFDocument(url: url)?.isLocked ?? false
    }

    /// Güvenli kayıt: geçici dosyaya yazar, yeniden açıp doğrular, sonra hedefi atomik
    /// olarak değiştirir. Doğrulama başarısızsa hedefe dokunulmaz.
    public static func kaydet(_ belge: PDFDocument, _ hedef: URL, secenekler: KayitSecenekleri = .init()) throws {
        let veri = try veri(belge, secenekler: secenekler)
        try yaz(veri, hedef, beklenenSayfa: belge.pageCount, parola: secenekler.kullaniciParolasi)
    }

    /// Belgeyi seçeneklerle PDF verisine çevirir ve doğrular.
    public static func veri(_ belge: PDFDocument, secenekler: KayitSecenekleri = .init()) throws -> Data {
        anonimlestir(belge)
        ios27KayitDuzeltmesi(belge)
        let veri: Data?
        let s = secenekler.pdfKitSecenekleri
        if s.isEmpty {
            veri = belge.dataRepresentation()
        } else {
            veri = belge.dataRepresentation(options: s)
        }
        guard let veri, !veri.isEmpty else { throw KagitHata.kaydedilemedi("PDF verisi üretilemedi") }
        return veri
    }

    /// Hazır PDF verisini doğrulayıp hedefe atomik olarak yazar.
    public static func yaz(_ veri: Data, _ hedef: URL, beklenenSayfa: Int? = nil, parola: String? = nil) throws {
        guard let kontrol = PDFDocument(data: veri) else {
            throw KagitHata.dogrulamaBasarisiz("çıktı PDF olarak açılmıyor")
        }
        if kontrol.isLocked {
            guard let parola, kontrol.unlock(withPassword: parola) else {
                throw KagitHata.dogrulamaBasarisiz("şifreli çıktı açılamadı")
            }
        }
        if let beklenenSayfa, kontrol.pageCount != beklenenSayfa {
            throw KagitHata.dogrulamaBasarisiz("sayfa sayısı \(beklenenSayfa) yerine \(kontrol.pageCount)")
        }
        let fm = FileManager.default
        let erisim = hedef.startAccessingSecurityScopedResource()
        defer { if erisim { hedef.stopAccessingSecurityScopedResource() } }
        try fm.createDirectory(at: hedef.deletingLastPathComponent(), withIntermediateDirectories: true)
        let gecici = hedef.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).kagit-gecici")
        do {
            try veri.write(to: gecici, options: .atomic)
            if fm.fileExists(atPath: hedef.path) {
                _ = try fm.replaceItemAt(hedef, withItemAt: gecici)
            } else {
                try fm.moveItem(at: gecici, to: hedef)
            }
        } catch {
            try? fm.removeItem(at: gecici)
            throw KagitHata.kaydedilemedi(error.localizedDescription)
        }
    }

    /// PDFKit açıklamalara sistem kullanıcı adını (/T) yazar; Kâğıt'ın kendi işaretleri
    /// ("kagit:" ile başlayanlar) dışındakileri temizler.
    static func anonimlestir(_ belge: PDFDocument) {
        for i in 0..<belge.pageCount {
            guard let sayfa = belge.page(at: i) else { continue }
            for a in sayfa.annotations {
                if let ad = a.userName, !ad.hasPrefix(Isaret.onek) { a.userName = "" }
            }
        }
    }

    /// iOS 27 PDFKit hatası: bellekte kurulan içindekiler ve bağlantı hedefleri kayıtta
    /// düşüyor. Sahte bir sayfa ekleyip silmek serileştiriciyi doğru yola sokuyor
    /// (macOS 27.2'de ölçüldü, Apple forumu 844399).
    static func ios27KayitDuzeltmesi(_ belge: PDFDocument) {
        guard belge.pageCount > 0, belge.outlineRoot != nil || belgedeBaglantiVar(belge) else { return }
        let dolgu = PDFPage()
        belge.insert(dolgu, at: belge.pageCount)
        belge.removePage(at: belge.pageCount - 1)
    }

    static func belgedeBaglantiVar(_ belge: PDFDocument) -> Bool {
        for i in 0..<belge.pageCount {
            if belge.page(at: i)?.annotations.contains(where: { $0.type == "Link" }) == true { return true }
        }
        return false
    }

    /// Yeni boş belge.
    public static func bos() -> PDFDocument { PDFDocument() }

    /// Sayfaları başka bir belgeden kopyalar (kaynak belge bozulmasın diye kopya alır).
    public static func sayfaKopyasi(_ sayfa: PDFPage) -> PDFPage {
        (sayfa.copy() as? PDFPage) ?? sayfa
    }
}

/// `PDFDocument.write` seçeneklerinin Türkçe karşılığı.
public struct KayitSecenekleri: Sendable, Equatable {
    public var kullaniciParolasi: String?
    public var sahipParolasi: String?
    public var izinler: Izinler?
    /// Açıklamaları sayfa içeriğine işler (düzleştirme). iOS 27'de pikselleşmeyi de önler.
    public var aciklamalariGom: Bool
    /// Yalnız `aciklamalariGom` ile birlikte etkilidir (ölçüldü).
    public var gorselleriJPEG: Bool
    /// Yalnız `aciklamalariGom` ile birlikte etkilidir; görselleri ~144 dpi'ye indirir.
    public var ekranIcinOptimize: Bool

    public init(kullaniciParolasi: String? = nil, sahipParolasi: String? = nil, izinler: Izinler? = nil,
                aciklamalariGom: Bool = false, gorselleriJPEG: Bool = false, ekranIcinOptimize: Bool = false) {
        self.kullaniciParolasi = kullaniciParolasi
        self.sahipParolasi = sahipParolasi
        self.izinler = izinler
        self.aciklamalariGom = aciklamalariGom
        self.gorselleriJPEG = gorselleriJPEG
        self.ekranIcinOptimize = ekranIcinOptimize
    }

    var pdfKitSecenekleri: [PDFDocumentWriteOption: Any] {
        var s: [PDFDocumentWriteOption: Any] = [:]
        if let p = kullaniciParolasi, !p.isEmpty { s[.userPasswordOption] = p }
        if let p = sahipParolasi, !p.isEmpty { s[.ownerPasswordOption] = p }
        if let izinler { s[.accessPermissionsOption] = NSNumber(value: izinler.pdfKitHam) }
        if aciklamalariGom { s[.burnInAnnotationsOption] = true }
        if gorselleriJPEG { s[.saveImagesAsJPEGOption] = true }
        if ekranIcinOptimize { s[.optimizeImagesForScreenOption] = true }
        return s
    }
}

/// PDF erişim izinleri (sahip parolası olan belgelerde uygulanır).
public struct Izinler: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let yazdirma = Izinler(rawValue: 1 << 0)
    public static let yuksekKaliteYazdirma = Izinler(rawValue: 1 << 1)
    public static let degistirme = Izinler(rawValue: 1 << 2)
    public static let kopyalama = Izinler(rawValue: 1 << 3)
    public static let aciklama = Izinler(rawValue: 1 << 4)
    public static let formDoldurma = Izinler(rawValue: 1 << 5)
    public static let sayfaBirlestirme = Izinler(rawValue: 1 << 6)
    public static let erisilebilirlik = Izinler(rawValue: 1 << 7)
    public static let hepsi: Izinler = [.yazdirma, .yuksekKaliteYazdirma, .degistirme, .kopyalama,
                                        .aciklama, .formDoldurma, .sayfaBirlestirme, .erisilebilirlik]

    /// PDFKit `PDFAccessPermissions` bit maskesi (NS_ENUM olduğu için elle kurulur).
    var pdfKitHam: UInt {
        var p: UInt = 0
        if contains(.yazdirma) { p |= 1 << 0 }
        if contains(.yuksekKaliteYazdirma) { p |= 1 << 1 }
        if contains(.degistirme) { p |= 1 << 2 }
        if contains(.sayfaBirlestirme) { p |= 1 << 3 }
        if contains(.kopyalama) { p |= 1 << 4 }
        if contains(.erisilebilirlik) { p |= 1 << 5 }
        if contains(.aciklama) { p |= 1 << 6 }
        if contains(.formDoldurma) { p |= 1 << 7 }
        return p
    }
}

/// Kâğıt'ın açıklamalara koyduğu makine okunur işaretler (PDF'te /T alanı).
/// Örnek: "kagit:puan:5", "kagit:damga:dogru", "kagit:imza".
public enum Isaret {
    public static let onek = "kagit:"

    public static func puan(_ deger: Double) -> String {
        "\(onek)puan:\(BicimYardimci.sayi(deger))"
    }
    public static func damga(_ ad: String) -> String { "\(onek)damga:\(ad)" }
    public static let imza = "\(onek)imza"
    public static let ortu = "\(onek)ortu"
    public static let metinDuzenleme = "\(onek)metin"

    /// "kagit:puan:2.5" → 2.5
    public static func puanDegeri(_ isaret: String?) -> Double? {
        guard let isaret, isaret.hasPrefix("\(onek)puan:") else { return nil }
        return Double(isaret.dropFirst("\(onek)puan:".count).replacingOccurrences(of: ",", with: "."))
    }
}

public enum BicimYardimci {
    /// 5 → "5", 2.5 → "2.5"
    public static func sayi(_ d: Double) -> String {
        d.rounded() == d ? String(Int(d)) : String(format: "%.2f", d)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }

    /// Bayt sayısını okunur biçime çevirir (1,4 MB).
    public static func boyut(_ bayt: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bayt, countStyle: .file)
    }
}
