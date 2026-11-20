import CoreGraphics
import CoreText
import Foundation
import PDFKit
#if canImport(UIKit)
import UIKit
#endif

/// TXT, RTF, HTML ve Markdown dosyalarını cihazda PDF'e çevirir.
/// DOCX/XLSX/PPTX/ODT için sunucu gerekir (`PDFStudioIstemcisi`).
public enum MetindenPDF {

    public static let desteklenenUzantilar: Set<String> = ["txt", "text", "md", "markdown", "rtf", "html", "htm"]
    public static let sunucuUzantilari: Set<String> = ["docx", "doc", "xlsx", "xls", "pptx", "ppt", "odt", "ods", "odp"]

    public static func yerelMi(_ url: URL) -> Bool { desteklenenUzantilar.contains(url.pathExtension.lowercased()) }

    public static func cevir(_ giris: URL, kagit: PDFCizim.Boyut = .a4, punto: Double = 12) async throws -> URL {
        let erisim = giris.startAccessingSecurityScopedResource()
        defer { if erisim { giris.stopAccessingSecurityScopedResource() } }
        let veri = try Data(contentsOf: giris)
        let uzanti = giris.pathExtension.lowercased()
        let ad = giris.deletingPathExtension().lastPathComponent
        let metin = Self.metinOlarak(veri)
        let kutu = CGRect(origin: .zero, size: kagit.boyut)
        let pdf: Data
        switch uzanti {
        case "txt", "text":
            pdf = try sayfala(duzMetin(metin, punto: CGFloat(punto)), kutu: kutu, baslik: ad)
        case "md", "markdown":
            pdf = try sayfala(markdownMetni(metin, punto: CGFloat(punto)), kutu: kutu, baslik: ad)
        case "rtf":
            guard let ats = try? NSAttributedString(data: veri, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                    documentAttributes: nil), ats.length > 0 else {
                throw KagitHata.acilamadi(giris.lastPathComponent)
            }
            pdf = try sayfala(ats, kutu: kutu, baslik: ad)
        case "html", "htm":
            pdf = try await htmlPDF(metin, kutu: kutu, baslik: ad, punto: punto)
        default:
            throw KagitHata.desteklenmiyor("“.\(uzanti)” dosyaları cihazda PDF'e çevrilemez. Office dosyaları için sunucuyu açın.")
        }
        let hedef = Gecici.dosya("\(ad).pdf")
        try Belge.yaz(pdf, hedef)
        return hedef
    }

    /// Düz metni PDF'e çevirir (kullanıcının yazdığı/yapıştırdığı metin için).
    public static func metindenPDF(_ metin: String, ad: String = "Metin", kagit: PDFCizim.Boyut = .a4, punto: Double = 12) throws -> URL {
        let pdf = try sayfala(duzMetin(metin, punto: CGFloat(punto)), kutu: CGRect(origin: .zero, size: kagit.boyut), baslik: ad)
        let hedef = Gecici.dosya("\(ad).pdf")
        try Belge.yaz(pdf, hedef)
        return hedef
    }

    static func metinOlarak(_ veri: Data) -> String {
        if let s = String(data: veri, encoding: .utf8) { return s }
        if let s = String(data: veri, encoding: .windowsCP1254) { return s }
        return String(decoding: veri, as: UTF8.self)
    }

    // MARK: CoreText sayfalama

    private static let yaziTipiAnahtari = NSAttributedString.Key(kCTFontAttributeName as String)
    private static let renkAnahtari = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
    private static let stilAnahtari = NSAttributedString.Key(kCTParagraphStyleAttributeName as String)

    private static func stil(bosluk: CGFloat = 0, satir: CGFloat = 2) -> CTParagraphStyle {
        var b = bosluk, s = satir
        let ayarlar = [
            CTParagraphStyleSetting(spec: .paragraphSpacing, valueSize: MemoryLayout<CGFloat>.size, value: &b),
            CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<CGFloat>.size, value: &s),
        ]
        return CTParagraphStyleCreate(ayarlar, ayarlar.count)
    }

    static func duzMetin(_ metin: String, punto: CGFloat) -> NSAttributedString {
        let font = CTFontCreateWithName("Helvetica" as CFString, punto, nil)
        let temiz = metin.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\t", with: "    ")
        return NSAttributedString(string: temiz, attributes: [yaziTipiAnahtari: font, renkAnahtari: CGColor(gray: 0, alpha: 1),
                                                              stilAnahtari: stil()])
    }

    /// Bir `NSAttributedString`'i A4 vb. sayfalara bölerek vektör PDF üretir.
    static func sayfala(_ ats: NSAttributedString, kutu: CGRect, baslik: String, kenar: CGFloat = 54) throws -> Data {
        guard ats.length > 0 else { throw KagitHata.genel("Dosyada metin yok.") }
        let kurucu = CTFramesetterCreateWithAttributedString(ats)
        let alan = kutu.insetBy(dx: kenar, dy: kenar)
        let y = PDFCizim.Yazici(baslik: baslik)
        var konum = 0
        var sayfa = 0
        while konum < ats.length {
            try iptalDenetle()
            let cerceve = CTFramesetterCreateFrame(kurucu, CFRange(location: konum, length: 0),
                                                   CGPath(rect: alan, transform: nil), nil)
            let gorunen = CTFrameGetVisibleStringRange(cerceve)
            guard gorunen.length > 0 else { break }
            y.sayfa(kutu) { ctx in
                ctx.textMatrix = .identity
                CTFrameDraw(cerceve, ctx)
            }
            konum += gorunen.length
            sayfa += 1
            if sayfa > 2000 { throw KagitHata.genel("Belge çok uzun (2000 sayfadan fazla).") }
        }
        return y.bitir()
    }

    // MARK: Markdown

    static func markdownMetni(_ md: String, punto: CGFloat) -> NSAttributedString {
        let sonuc = NSMutableAttributedString()
        let siyah = CGColor(gray: 0, alpha: 1)

        func font(_ boyut: CGFloat, kalin: Bool = false, italik: Bool = false, mono: Bool = false) -> CTFont {
            let ad: String
            if mono { ad = kalin ? "Courier-Bold" : "Courier" }
            else if kalin && italik { ad = "Helvetica-BoldOblique" }
            else if kalin { ad = "Helvetica-Bold" }
            else if italik { ad = "Helvetica-Oblique" }
            else { ad = "Helvetica" }
            return CTFontCreateWithName(ad as CFString, boyut, nil)
        }
        func ekle(_ s: String, _ f: CTFont, bosluk: CGFloat = 0, renk: CGColor? = nil) {
            sonuc.append(NSAttributedString(string: s, attributes: [yaziTipiAnahtari: f, renkAnahtari: renk ?? siyah,
                                                                    stilAnahtari: stil(bosluk: bosluk)]))
        }
        /// **kalın**, *italik*, `kod` işaretlerini çözer.
        func satirIci(_ s: String, boyut: CGFloat, kalinTaban: Bool = false, italikTaban: Bool = false, bosluk: CGFloat) {
            var kalin = kalinTaban, italik = italikTaban, kod = false
            var tampon = ""
            func bosalt() {
                if !tampon.isEmpty { ekle(tampon, font(boyut, kalin: kalin, italik: italik, mono: kod), bosluk: bosluk); tampon = "" }
            }
            let linkli = s.replacingOccurrences(of: #"\[([^\]]+)\]\(([^)]+)\)"#, with: "$1 ($2)", options: .regularExpression)
            let c = Array(linkli)
            var i = 0
            while i < c.count {
                if c[i] == "`" { bosalt(); kod.toggle(); i += 1; continue }
                if !kod, c[i] == "*", i + 1 < c.count, c[i + 1] == "*" { bosalt(); kalin.toggle(); i += 2; continue }
                if !kod, c[i] == "_", i + 1 < c.count, c[i + 1] == "_" { bosalt(); kalin.toggle(); i += 2; continue }
                if !kod, c[i] == "*", i + 1 < c.count, c[i + 1] != " " || italik { bosalt(); italik.toggle(); i += 1; continue }
                tampon.append(c[i]); i += 1
            }
            bosalt()
        }

        var kodBlogu = false
        var paragraf: [String] = []
        func paragrafiBitir() {
            guard !paragraf.isEmpty else { return }
            satirIci(paragraf.joined(separator: " "), boyut: punto, bosluk: punto * 0.6)
            ekle("\n", font(punto), bosluk: punto * 0.6)
            paragraf = []
        }
        for ham in md.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let satir = ham.replacingOccurrences(of: "\t", with: "    ")
            if satir.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                paragrafiBitir(); kodBlogu.toggle(); continue
            }
            if kodBlogu { ekle(satir + "\n", font(punto * 0.9, mono: true), renk: CGColor(gray: 0.2, alpha: 1)); continue }
            let kirp = satir.trimmingCharacters(in: .whitespaces)
            if kirp.isEmpty { paragrafiBitir(); continue }
            if let m = kirp.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                paragrafiBitir()
                let seviye = kirp[m].filter { $0 == "#" }.count
                let carpan: [CGFloat] = [2.0, 1.6, 1.35, 1.2, 1.1, 1.0]
                let b = punto * carpan[seviye - 1]
                satirIci(String(kirp[m.upperBound...]), boyut: b, kalinTaban: true, bosluk: b * 0.5)
                ekle("\n", font(b, kalin: true), bosluk: b * 0.5)
                continue
            }
            if kirp.range(of: #"^(-{3,}|\*{3,}|_{3,})$"#, options: .regularExpression) != nil {
                paragrafiBitir()
                ekle(String(repeating: "─", count: 40) + "\n", font(punto), bosluk: punto * 0.6, renk: CGColor(gray: 0.6, alpha: 1))
                continue
            }
            if let m = kirp.range(of: #"^([-*+]|\d+[.)])\s+"#, options: .regularExpression) {
                paragrafiBitir()
                let isaret = String(kirp[m]).trimmingCharacters(in: .whitespaces)
                let on = isaret.first?.isNumber == true ? isaret + " " : "•  "
                let girinti = String(repeating: " ", count: (satir.prefix { $0 == " " }.count / 2) * 2)
                satirIci(girinti + on + kirp[m.upperBound...], boyut: punto, bosluk: punto * 0.25)
                ekle("\n", font(punto), bosluk: punto * 0.25)
                continue
            }
            if kirp.hasPrefix(">") {
                paragrafiBitir()
                let icerik = kirp.drop { $0 == ">" || $0 == " " }
                satirIci("│ " + icerik, boyut: punto, italikTaban: true, bosluk: punto * 0.3)
                ekle("\n", font(punto), bosluk: punto * 0.3)
                continue
            }
            paragraf.append(kirp)
        }
        paragrafiBitir()
        return sonuc
    }

    // MARK: HTML

    static func htmlPDF(_ html: String, kutu: CGRect, baslik: String, punto: Double) async throws -> Data {
        #if canImport(UIKit)
        let sarili = "<style>body{font-family:Helvetica;font-size:\(Int(punto))pt;}</style>" + html
        let veri = await MainActor.run { () -> Data? in htmlPDFiOS(sarili, kutu: kutu, baslik: baslik) }
        guard let veri, !veri.isEmpty else { throw KagitHata.genel("HTML sayfaya dökülemedi.") }
        return veri
        #else
        return try sayfala(duzMetin(htmlDuzMetin(html), punto: CGFloat(punto)), kutu: kutu, baslik: baslik)
        #endif
    }

    #if canImport(UIKit)
    @MainActor
    private static func htmlPDFiOS(_ html: String, kutu: CGRect, baslik: String) -> Data? {
        let bicimleyici = UIMarkupTextPrintFormatter(markupText: html)
        bicimleyici.perPageContentInsets = UIEdgeInsets(top: 54, left: 54, bottom: 54, right: 54)
        let r = UIPrintPageRenderer()
        r.addPrintFormatter(bicimleyici, startingAtPageAt: 0)
        r.setValue(NSValue(cgRect: kutu), forKey: "paperRect")
        r.setValue(NSValue(cgRect: kutu), forKey: "printableRect")
        let veri = NSMutableData()
        UIGraphicsBeginPDFContextToData(veri, kutu, [kCGPDFContextTitle as String: baslik])
        r.prepare(forDrawingPages: NSRange(location: 0, length: r.numberOfPages))
        for i in 0..<r.numberOfPages {
            UIGraphicsBeginPDFPage()
            r.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return veri as Data
    }
    #endif

    /// HTML'den etiketleri atar (UIKit olmayan ortamlar ve testler için yedek).
    static func htmlDuzMetin(_ html: String) -> String {
        var s = html
        for etiket in ["script", "style"] {
            s = s.replacingOccurrences(of: "<\(etiket)[^>]*>[\\s\\S]*?</\(etiket)>", with: "", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<br\\s*/?>|</p>|</div>|</h[1-6]>|</li>|</tr>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (a, b) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        return s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
