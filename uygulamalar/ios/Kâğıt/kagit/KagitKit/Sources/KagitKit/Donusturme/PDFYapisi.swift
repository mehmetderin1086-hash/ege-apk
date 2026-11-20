import CoreGraphics
import Foundation
import PDFKit

/// PDF'ten çıkarılan düzen bloğu.
public enum PDFBlok: Sendable, Equatable {
    case baslik(Int, String)
    case paragraf(String)
    case madde(String)
    /// Yeni sayfa başladı (1 tabanlı).
    case sayfa(Int)
}

/// XML/HTML için kaçış ve geçersiz karakter temizliği.
enum XMLYardimcisi {
    static func kacis(_ s: String) -> String {
        var cikti = ""
        cikti.reserveCapacity(s.utf16.count)
        for u in s.unicodeScalars {
            switch u {
            case "&": cikti += "&amp;"
            case "<": cikti += "&lt;"
            case ">": cikti += "&gt;"
            case "\"": cikti += "&quot;"
            case "\t", "\n", "\r": cikti.unicodeScalars.append(u)
            default:
                if u.value >= 0x20, !(0xD800...0xDFFF).contains(u.value), u.value != 0xFFFE, u.value != 0xFFFF {
                    cikti.unicodeScalars.append(u)
                }
            }
        }
        return cikti
    }
}

/// Yazı tipi boyutu/kalınlığına bakarak başlık-paragraf-madde yapısı çıkarır; metin, Markdown, HTML ve EPUB üretir.
public enum PDFYapisi {

    private struct Satir {
        var metin: String
        var boyut: CGFloat
        var kalinOrani: Double
    }

    // MARK: Yapı çıkarımı

    public static func cikar(_ b: PDFDocument, sayfalar: [Int]? = nil, ilerleme: Ilerleme? = nil) throws -> [PDFBlok] {
        let idx = sayfalar ?? Array(0..<b.pageCount)
        // 1) Satırlar
        var tumSatirlar: [[Satir]] = []
        var boyutAgirligi: [Int: Int] = [:]
        for (k, i) in idx.enumerated() {
            try iptalDenetle()
            autoreleasepool {
                let s = b.page(at: i).map(satirlar) ?? []
                for x in s { boyutAgirligi[Int((x.boyut * 2).rounded()), default: 0] += x.metin.count }
                tumSatirlar.append(s)
            }
            ilerleme?(Double(k + 1) / Double(idx.count) * 0.5)
        }
        let govde = CGFloat(boyutAgirligi.max { $0.value < $1.value }?.key ?? 24) / 2
        // 2) Bloklar
        var bloklar: [PDFBlok] = []
        for (k, s) in tumSatirlar.enumerated() {
            try iptalDenetle()
            bloklar.append(.sayfa(idx[k] + 1))
            bloklar += bloklaraCevir(s, govde: govde)
            ilerleme?(0.5 + Double(k + 1) / Double(tumSatirlar.count) * 0.5)
        }
        return bloklar
    }

    private static func satirlar(_ sayfa: PDFPage) -> [Satir] {
        guard let ats = sayfa.attributedString, ats.length > 0 else {
            return (sayfa.string ?? "").components(separatedBy: .newlines).filter { !$0.isEmpty }
                .map { Satir(metin: $0, boyut: 12, kalinOrani: 0) }
        }
        let tam = ats.string as NSString
        var sonuc: [Satir] = []
        var metin = "", enBuyuk: CGFloat = 0, kalinSayi = 0, toplam = 0
        func bitir() {
            let t = metin.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty {
                sonuc.append(Satir(metin: t, boyut: enBuyuk, kalinOrani: toplam > 0 ? Double(kalinSayi) / Double(toplam) : 0))
            }
            metin = ""; enBuyuk = 0; kalinSayi = 0; toplam = 0
        }
        ats.enumerateAttributes(in: NSRange(location: 0, length: ats.length), options: []) { nitelik, aralik, _ in
            let font = nitelik[NSAttributedString.Key("NSFont")] as? NSObject
            let boyut = (font?.value(forKey: "pointSize") as? CGFloat) ?? 12
            let fontAdi = ((font?.value(forKey: "fontName") as? String) ?? "").lowercased()
            let kalin = fontAdi.contains("bold") || fontAdi.contains("black") || fontAdi.contains("heavy")
            let parca = tam.substring(with: aralik)
            let satirlar = parca.components(separatedBy: CharacterSet.newlines)
            for (n, p) in satirlar.enumerated() {
                if n > 0 { bitir() }
                guard !p.isEmpty else { continue }
                metin += p
                let sayi = p.trimmingCharacters(in: .whitespaces).count
                if sayi > 0 { enBuyuk = max(enBuyuk, boyut) }
                toplam += sayi
                if kalin { kalinSayi += sayi }
            }
        }
        bitir()
        return sonuc
    }

    private static func bloklaraCevir(_ s: [Satir], govde: CGFloat) -> [PDFBlok] {
        guard !s.isEmpty else { return [] }
        let enUzun = max(1, s.map { $0.metin.count }.max() ?? 1)
        var bloklar: [PDFBlok] = []
        var paragraf = ""
        var oncekiUzunluk = 0
        func paragrafiBitir() {
            let t = paragraf.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { bloklar.append(.paragraf(t)) }
            paragraf = ""
        }
        for satir in s {
            let t = satir.metin
            let oran = satir.boyut / max(govde, 1)
            let sonKarakter = t.last
            let basliktaMi: Int? = {
                if oran >= 1.15, t.count <= 140 { return oran >= 1.7 ? 1 : (oran >= 1.35 ? 2 : 3) }
                if satir.kalinOrani >= 0.7, t.count <= 70, oran >= 0.95, sonKarakter != ".", sonKarakter != ",", sonKarakter != ";" { return 3 }
                return nil
            }()
            if let seviye = basliktaMi {
                paragrafiBitir()
                // Ardışık aynı seviye başlık satırlarını birleştir (çok satırlı başlık)
                if case .baslik(let s0, let onceki)? = bloklar.last, s0 == seviye, paragraf.isEmpty {
                    bloklar[bloklar.count - 1] = .baslik(seviye, onceki + " " + t)
                } else {
                    bloklar.append(.baslik(seviye, t))
                }
                oncekiUzunluk = 0
                continue
            }
            if let m = t.range(of: #"^([•▪◦●·\-–—*]|\d{1,3}[.)])\s+"#, options: .regularExpression) {
                paragrafiBitir()
                bloklar.append(.madde(String(t[m.upperBound...])))
                oncekiUzunluk = t.count
                continue
            }
            // Önceki satır kısaysa ve cümle bitirdiyse yeni paragraf
            if !paragraf.isEmpty, Double(oncekiUzunluk) < Double(enUzun) * 0.6,
               let son = paragraf.last, ".!?:…".contains(son) {
                paragrafiBitir()
            }
            // Madde devam satırı: önceki blok madde ve paragraf boşsa maddeye ekle
            if paragraf.isEmpty, case .madde(let m)? = bloklar.last, Double(oncekiUzunluk) >= Double(enUzun) * 0.5,
               !(m.last.map { ".!?:".contains($0) } ?? false) {
                bloklar[bloklar.count - 1] = .madde(m + " " + t)
                oncekiUzunluk = t.count
                continue
            }
            if paragraf.isEmpty {
                paragraf = t
            } else if paragraf.hasSuffix("-"), let ilk = t.first, ilk.isLowercase {
                paragraf.removeLast()
                paragraf += t
            } else {
                paragraf += " " + t
            }
            oncekiUzunluk = t.count
        }
        paragrafiBitir()
        return bloklar
    }

    // MARK: Düz metin

    /// Sayfa metinlerini birleştirir. Taranmış (metinsiz) sayfa varsa `bosSayfalar` döner.
    public static func duzMetin(_ giris: URL, aralik: String = "", parola: String? = nil,
                                sayfaAyirici: Bool = false) throws -> (metin: String, bosSayfalar: [Int]) {
        let b = try Belge.ac(giris, parola: parola)
        let idx = try SayfaAraligi.coz(aralik, sayfaSayisi: b.pageCount)
        var parcalar: [String] = []
        var bos: [Int] = []
        for i in idx {
            try iptalDenetle()
            let t = (b.page(at: i)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { bos.append(i) }
            parcalar.append(sayfaAyirici ? "— Sayfa \(i + 1) —\n\(t)" : t)
        }
        return (parcalar.joined(separator: "\n\n"), bos)
    }

    public static func pdftenMetin(_ giris: URL, aralik: String = "", parola: String? = nil, sayfaAyirici: Bool = false) throws -> URL {
        let (metin, bos) = try duzMetin(giris, aralik: aralik, parola: parola, sayfaAyirici: sayfaAyirici)
        guard !metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw metinYokHatasi(bos.count) }
        let hedef = IsYardimcisi.cikti(giris, "", uzanti: "txt")
        try Data(metin.utf8).write(to: hedef)
        return hedef
    }

    static func metinYokHatasi(_ n: Int) -> KagitHata {
        KagitHata.genel("Bu PDF'te seçilebilir metin yok (taranmış olabilir). Önce “OCR” ile aranabilir yapın.")
    }

    // MARK: Markdown / HTML

    private static func bloklari(_ giris: URL, aralik: String, parola: String?, ilerleme: Ilerleme?) throws -> (PDFDocument, [PDFBlok]) {
        let b = try Belge.ac(giris, parola: parola)
        let idx = try SayfaAraligi.coz(aralik, sayfaSayisi: b.pageCount)
        let bl = try cikar(b, sayfalar: idx, ilerleme: ilerleme)
        guard bl.contains(where: { if case .sayfa = $0 { false } else { true } }) else { throw metinYokHatasi(idx.count) }
        return (b, bl)
    }

    public static func markdown(_ bloklar: [PDFBlok]) -> String {
        var s = ""
        for b in bloklar {
            switch b {
            case .baslik(let n, let t): s += "\n" + String(repeating: "#", count: n) + " " + t + "\n\n"
            case .paragraf(let t): s += t + "\n\n"
            case .madde(let t): s += "- " + t + "\n"
            case .sayfa: s += "\n"
            }
        }
        return s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    public static func pdftenMarkdown(_ giris: URL, aralik: String = "", parola: String? = nil, ilerleme: Ilerleme? = nil) throws -> URL {
        let (_, bl) = try bloklari(giris, aralik: aralik, parola: parola, ilerleme: ilerleme)
        let hedef = IsYardimcisi.cikti(giris, "", uzanti: "md")
        try Data(markdown(bl).utf8).write(to: hedef)
        return hedef
    }

    /// Bloklardan gövde HTML'i (üst düzey etiketler: h1-h3, p, ul/li).
    static func govdeHTML(_ bloklar: [PDFBlok], sayfaIsareti: Bool = false) -> String {
        var s = ""
        var listede = false
        func listeyiKapat() { if listede { s += "</ul>\n"; listede = false } }
        for b in bloklar {
            if case .madde(let t) = b {
                if !listede { s += "<ul>\n"; listede = true }
                s += "<li>\(XMLYardimcisi.kacis(t))</li>\n"
                continue
            }
            listeyiKapat()
            switch b {
            case .baslik(let n, let t): s += "<h\(n)>\(XMLYardimcisi.kacis(t))</h\(n)>\n"
            case .paragraf(let t): s += "<p>\(XMLYardimcisi.kacis(t))</p>\n"
            case .sayfa(let n): if sayfaIsareti { s += "<hr id=\"sayfa\(n)\"/>\n" }
            case .madde: break
            }
        }
        listeyiKapat()
        return s
    }

    public static func html(baslik: String, bloklar: [PDFBlok]) -> String {
        """
        <!DOCTYPE html>
        <html lang="tr"><head><meta charset="utf-8"><title>\(XMLYardimcisi.kacis(baslik))</title>
        <style>body{font-family:-apple-system,Helvetica,sans-serif;max-width:46em;margin:2em auto;padding:0 1em;line-height:1.55}</style>
        </head><body>
        \(govdeHTML(bloklar, sayfaIsareti: true))</body></html>
        """
    }

    public static func pdftenHTML(_ giris: URL, aralik: String = "", parola: String? = nil, ilerleme: Ilerleme? = nil) throws -> URL {
        let (_, bl) = try bloklari(giris, aralik: aralik, parola: parola, ilerleme: ilerleme)
        let hedef = IsYardimcisi.cikti(giris, "", uzanti: "html")
        let ad = giris.deletingPathExtension().lastPathComponent
        try Data(html(baslik: ad, bloklar: bl).utf8).write(to: hedef)
        return hedef
    }

    // MARK: EPUB

    public static func pdftenEPUB(_ giris: URL, aralik: String = "", parola: String? = nil, ilerleme: Ilerleme? = nil) throws -> URL {
        let (b, bl) = try bloklari(giris, aralik: aralik, parola: parola, ilerleme: ilerleme)
        let ad = (b.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? giris.deletingPathExtension().lastPathComponent
        let hedef = IsYardimcisi.cikti(giris, "", uzanti: "epub")
        try Data(epub(baslik: ad, yazar: b.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String, bloklar: bl))
            .write(to: hedef)
        return hedef
    }

    /// Bloklardan EPUB 3 paketi (ZIP) üretir.
    public static func epub(baslik: String, yazar: String? = nil, bloklar: [PDFBlok]) -> Data {
        // Bölümlere ayır: >1 adet h1 varsa h1'lerde, yoksa h2'lerde, yoksa 12 sayfada bir.
        let h1 = bloklar.filter { if case .baslik(1, _) = $0 { true } else { false } }.count
        let h2 = bloklar.filter { if case .baslik(2, _) = $0 { true } else { false } }.count
        let bolmeSeviyesi: Int? = h1 > 1 ? 1 : (h2 > 1 ? 2 : nil)
        var bolumler: [(baslik: String, bloklar: [PDFBlok])] = []
        var sayfaSayaci = 0
        for blok in bloklar {
            if case .sayfa = blok { sayfaSayaci += 1 }
            var yeni = false
            var yeniBaslik = ""
            if let sev = bolmeSeviyesi, case .baslik(let n, let t) = blok, n == sev {
                yeni = true; yeniBaslik = t
            } else if bolmeSeviyesi == nil, case .sayfa = blok, sayfaSayaci > 1, (sayfaSayaci - 1) % 12 == 0 {
                yeni = true; yeniBaslik = "Bölüm \(bolumler.count + 1)"
            }
            let sonBos = bolumler.last.map { $0.bloklar.allSatisfy { if case .sayfa = $0 { true } else { false } } } ?? false
            if yeni, sonBos, !bolumler.isEmpty {
                bolumler[bolumler.count - 1].baslik = yeniBaslik
            } else if yeni || bolumler.isEmpty {
                bolumler.append((yeni ? yeniBaslik : (baslik), []))
            }
            bolumler[bolumler.count - 1].bloklar.append(blok)
        }
        if bolumler.isEmpty { bolumler = [(baslik, [])] }

        var z = ZipYazici()
        z.ekle("mimetype", metin: "application/epub+zip", sakla: true)
        z.ekle("META-INF/container.xml", metin: """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
        """)
        var manifest = "<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>\n<item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>\n"
        var omurga = ""
        var navListe = "", ncxNokta = ""
        for (i, bolum) in bolumler.enumerated() {
            let dosya = "bolum\(i + 1).xhtml"
            manifest += "<item id=\"b\(i + 1)\" href=\"\(dosya)\" media-type=\"application/xhtml+xml\"/>\n"
            omurga += "<itemref idref=\"b\(i + 1)\"/>\n"
            navListe += "<li><a href=\"\(dosya)\">\(XMLYardimcisi.kacis(bolum.baslik))</a></li>\n"
            ncxNokta += "<navPoint id=\"n\(i + 1)\" playOrder=\"\(i + 1)\"><navLabel><text>\(XMLYardimcisi.kacis(bolum.baslik))</text></navLabel><content src=\"\(dosya)\"/></navPoint>\n"
            z.ekle("OEBPS/\(dosya)", metin: """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="tr" lang="tr"><head><meta charset="utf-8"/><title>\(XMLYardimcisi.kacis(bolum.baslik))</title></head>
            <body>
            \(govdeHTML(bolum.bloklar).replacingOccurrences(of: "<hr id=\"", with: "<hr id=\""))</body></html>
            """)
        }
        let kimlik = "urn:uuid:\(UUID().uuidString)"
        let tarih = ISO8601DateFormatter().string(from: Date())
        z.ekle("OEBPS/content.opf", metin: """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="kimlik">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="kimlik">\(kimlik)</dc:identifier>
        <dc:title>\(XMLYardimcisi.kacis(baslik))</dc:title>
        <dc:creator>\(XMLYardimcisi.kacis(yazar ?? "Bilinmiyor"))</dc:creator>
        <dc:language>tr</dc:language>
        <meta property="dcterms:modified">\(tarih)</meta>
        </metadata>
        <manifest>
        \(manifest)</manifest>
        <spine toc="ncx">
        \(omurga)</spine>
        </package>
        """)
        z.ekle("OEBPS/nav.xhtml", metin: """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="tr" lang="tr"><head><meta charset="utf-8"/><title>İçindekiler</title></head>
        <body><nav epub:type="toc" id="toc"><h1>İçindekiler</h1><ol>
        \(navListe)</ol></nav></body></html>
        """)
        z.ekle("OEBPS/toc.ncx", metin: """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
        <head><meta name="dtb:uid" content="\(kimlik)"/></head>
        <docTitle><text>\(XMLYardimcisi.kacis(baslik))</text></docTitle>
        <navMap>
        \(ncxNokta)</navMap></ncx>
        """)
        return z.bitir()
    }
}
