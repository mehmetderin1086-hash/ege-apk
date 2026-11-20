import Foundation
import PDFKit

/// Düzenlenebilir belge üst verisi.
public struct UstVeri: Sendable, Equatable {
    public var baslik = ""
    public var yazar = ""
    public var konu = ""
    public var anahtarSozcukler: [String] = []
    public var olusturan = ""
    public var uretici = ""
    public var olusturma: Date?
    public var degistirme: Date?

    public init() {}

    public var bos: Bool {
        baslik.isEmpty && yazar.isEmpty && konu.isEmpty && anahtarSozcukler.isEmpty && olusturan.isEmpty && uretici.isEmpty
    }
}

/// Üst veri temizleme/yazma sonucu.
public struct UstVeriRaporu: Sendable, Equatable {
    public enum Yontem: String, Sendable { case pdfKit, baytYamasi, yenidenKurma }
    /// XMP akışı çıktıda bulunamıyor.
    public var xmpTemiz: Bool
    public var yontem: Yontem
    /// Kullanıcıya gösterilecek açıklama.
    public var aciklama: String
}

public enum UstVeriIslemleri {

    public static func oku(_ belge: PDFDocument) -> UstVeri {
        var u = UstVeri()
        let a = belge.documentAttributes ?? [:]
        u.baslik = a[PDFDocumentAttribute.titleAttribute] as? String ?? ""
        u.yazar = a[PDFDocumentAttribute.authorAttribute] as? String ?? ""
        u.konu = a[PDFDocumentAttribute.subjectAttribute] as? String ?? ""
        u.olusturan = a[PDFDocumentAttribute.creatorAttribute] as? String ?? ""
        u.uretici = a[PDFDocumentAttribute.producerAttribute] as? String ?? ""
        if let k = a[PDFDocumentAttribute.keywordsAttribute] as? [String] {
            u.anahtarSozcukler = k
        } else if let k = a[PDFDocumentAttribute.keywordsAttribute] as? String {
            u.anahtarSozcukler = k.split(whereSeparator: { ",;".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }
        }
        u.olusturma = a[PDFDocumentAttribute.creationDateAttribute] as? Date
        u.degistirme = a[PDFDocumentAttribute.modificationDateAttribute] as? Date
        return u
    }

    public static func oku(veri: Data, parola: String? = nil) throws -> UstVeri {
        oku(try Belge.ac(veri: veri, parola: parola))
    }

    /// Alanları yazar. Eski XMP akışı (güncel olmayan değerler taşıyacağından) kaldırılır.
    public static func yaz(veri: Data, parola: String? = nil, ustVeri: UstVeri) throws -> (veri: Data, rapor: UstVeriRaporu) {
        let belge = try Belge.ac(veri: veri, parola: parola)
        var a: [AnyHashable: Any] = [:]
        if !ustVeri.baslik.isEmpty { a[PDFDocumentAttribute.titleAttribute] = ustVeri.baslik }
        if !ustVeri.yazar.isEmpty { a[PDFDocumentAttribute.authorAttribute] = ustVeri.yazar }
        if !ustVeri.konu.isEmpty { a[PDFDocumentAttribute.subjectAttribute] = ustVeri.konu }
        if !ustVeri.olusturan.isEmpty { a[PDFDocumentAttribute.creatorAttribute] = ustVeri.olusturan }
        if !ustVeri.anahtarSozcukler.isEmpty { a[PDFDocumentAttribute.keywordsAttribute] = ustVeri.anahtarSozcukler }
        if let t = ustVeri.olusturma { a[PDFDocumentAttribute.creationDateAttribute] = t }
        a[PDFDocumentAttribute.modificationDateAttribute] = Date()
        belge.documentAttributes = a
        let cikti = try Belge.veri(belge, secenekler: korumaSecenekleri(belge, parola))
        return try xmpTemizle(cikti, parola: parola)
    }

    /// Bütün üst veriyi (Info sözlüğü + XMP) siler.
    public static func hepsiniTemizle(veri: Data, parola: String? = nil) throws -> (veri: Data, rapor: UstVeriRaporu) {
        let belge = try Belge.ac(veri: veri, parola: parola)
        belge.documentAttributes = [:]
        let cikti = try Belge.veri(belge, secenekler: korumaSecenekleri(belge, parola))
        return try xmpTemizle(cikti, parola: parola)
    }

    /// Parolalı belgenin parolasını koruyarak yazmak için.
    static func korumaSecenekleri(_ belge: PDFDocument, _ parola: String?) -> KayitSecenekleri {
        guard belge.isEncrypted, let parola, !parola.isEmpty else { return .init() }
        return KayitSecenekleri(kullaniciParolasi: parola, sahipParolasi: parola)
    }

    // MARK: - XMP

    /// PDF baytlarında XMP paketi var mı (sıkıştırılmamış akışlar için).
    public static func xmpVarMi(_ veri: Data) -> Bool {
        let s = String(decoding: veri, as: UTF8.self)
        return s.contains("<x:xmpmeta") || s.contains("<?xpacket") || s.contains("/Type /Metadata") || s.contains("/Type/Metadata")
            || s.contains("/Metadata ") && s.range(of: #"/Metadata\s+\d+\s+\d+\s+R"#, options: .regularExpression) != nil
    }

    /// PDFKit `documentAttributes` temizlemesi XMP akışını silmiyor (ölçüldü). Çıktıdaki /Metadata
    /// akışlarının içeriği boşluk baytlarıyla ezilir, katalogdaki anahtar etkisizleştirilir
    /// (bayt uzunlukları değişmediği için xref geçerli kalır). Olmazsa sayfalar yeni bir PDF'e
    /// aktarılır (köprüler ve yer imleri kaybolur) ve rapor bunu söyler.
    static func xmpTemizle(_ veri: Data, parola: String?) throws -> (veri: Data, rapor: UstVeriRaporu) {
        guard xmpVarMi(veri) else {
            return (veri, UstVeriRaporu(xmpTemiz: true, yontem: .pdfKit, aciklama: "XMP üst verisi yok."))
        }
        // Şifreli çıktıda baytlar yamalanamaz.
        if let k = PDFDocument(data: veri), k.isEncrypted {
            return (veri, UstVeriRaporu(xmpTemiz: false, yontem: .pdfKit,
                                        aciklama: "Parolalı dosyada XMP temizlenemedi. Önce parolayı kaldırın, temizleyin, sonra parola koyun."))
        }
        var yama = veri
        let yamali = metadataAkislariniEz(&yama)
        if yamali, !xmpVarMi(yama), PDFDocument(data: yama) != nil {
            return (yama, UstVeriRaporu(xmpTemiz: true, yontem: .baytYamasi,
                                        aciklama: "PDFKit XMP üst verisini silemediği için dosyadaki XMP akışı doğrudan temizlendi."))
        }
        // Son çare: sayfaları yeni bir PDF'e aktar.
        guard let belge = PDFDocument(data: veri) else { throw KagitHata.acilamadi("belge") }
        let yazici = PDFCizim.Yazici()
        for i in 0..<belge.pageCount {
            if let s = belge.page(at: i) { yazici.sayfaKopyala(s) }
        }
        let yeni = yazici.bitir()
        guard PDFDocument(data: yeni)?.pageCount == belge.pageCount else {
            throw KagitHata.dogrulamaBasarisiz("üst veri temizlenirken sayfa sayısı değişti")
        }
        return (yeni, UstVeriRaporu(xmpTemiz: !xmpVarMi(yeni), yontem: .yenidenKurma,
                                    aciklama: "XMP başka yolla silinemedi; sayfalar yeni bir PDF'e aktarıldı. Köprüler, yer imleri ve form alanları korunmadı."))
    }

    /// Latin-1 (1 bayt = 1 karakter) görünümünde /Metadata akışlarını bulup içlerini boşlukla doldurur.
    static func metadataAkislariniEz(_ veri: inout Data) -> Bool {
        var bayt = [UInt8](veri)
        guard let l1 = String(bytes: bayt, encoding: .isoLatin1) else { return false }
        let ns = l1 as NSString
        var degisti = false

        // Hedef nesne numaraları: katalog/sayfadaki "/Metadata N G R" başvuruları + "/Type /Metadata" sözlükleri.
        var numaralar = Set<Int>()
        if let ifade = try? NSRegularExpression(pattern: #"/Metadata\s+(\d+)\s+\d+\s+R"#) {
            for m in ifade.matches(in: l1, range: NSRange(location: 0, length: ns.length)) {
                numaralar.insert(Int(ns.substring(with: m.range(at: 1))) ?? -1)
                // Anahtarı etkisizleştir (aynı uzunlukta).
                let anahtar = NSRange(location: m.range.location, length: 9)
                for k in 0..<9 { bayt[anahtar.location + k] = Array("/KagitXmp".utf8)[k] }
                degisti = true
            }
        }
        guard let nesne = try? NSRegularExpression(pattern: #"(\d+)\s+(\d+)\s+obj"#) else { return degisti }
        for m in nesne.matches(in: l1, range: NSRange(location: 0, length: ns.length)) {
            let no = Int(ns.substring(with: m.range(at: 1))) ?? -2
            let basla = m.range.location + m.range.length
            let bitisAra = ns.range(of: "endobj", options: [], range: NSRange(location: basla, length: ns.length - basla))
            guard bitisAra.location != NSNotFound else { continue }
            let govde = NSRange(location: basla, length: bitisAra.location - basla)
            let sozluk = ns.substring(with: NSRange(location: govde.location, length: min(govde.length, 300)))
            let metadataMi = sozluk.range(of: #"/Type\s*/Metadata"#, options: .regularExpression) != nil
            guard numaralar.contains(no) || metadataMi else { continue }
            let ak = ns.range(of: "stream", options: [], range: govde)
            guard ak.location != NSNotFound else { continue }
            var icBas = ak.location + ak.length
            if icBas < bayt.count, bayt[icBas] == 0x0D { icBas += 1 }
            if icBas < bayt.count, bayt[icBas] == 0x0A { icBas += 1 }
            let son = ns.range(of: "endstream", options: [], range: NSRange(location: icBas, length: bitisAra.location - icBas))
            guard son.location != NSNotFound else { continue }
            for k in icBas..<son.location { bayt[k] = 0x20 }
            // Nesnenin kendi türünü de etkisizleştir.
            if let t = ns.range(of: "/Metadata", options: [], range: NSRange(location: govde.location, length: ak.location - govde.location)) as NSRange?,
               t.location != NSNotFound {
                for k in 0..<9 { bayt[t.location + k] = Array("/KagitXmp".utf8)[k] }
            }
            degisti = true
        }
        if degisti { veri = Data(bayt) }
        return degisti
    }
}
