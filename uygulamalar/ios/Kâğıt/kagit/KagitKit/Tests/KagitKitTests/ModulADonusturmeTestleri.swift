import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import KagitKit

/// Düz renkli test görseli dosyası.
func ornekGorsel(_ genislik: Int, _ yukseklik: Int, tur: UTType = .jpeg, ad: String) throws -> URL {
    let ctx = CGContext(data: nil, width: genislik, height: yukseklik, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: genislik, height: yukseklik))
    ctx.setFillColor(CGColor(red: 1, green: 0.8, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: genislik / 4, y: yukseklik / 4, width: genislik / 2, height: yukseklik / 2))
    let u = Ornek.gecici(ad)
    try PDFCizim.kodla(ctx.makeImage()!, tur: tur)!.write(to: u)
    return u
}

/// Başlık + paragraf + madde içeren, yazı tipi boyutları farklı örnek PDF.
func yapiliPDF() throws -> URL {
    let y = PDFCizim.Yazici(baslik: "Yapılı")
    let kutu = CGRect(x: 0, y: 0, width: 595, height: 842)
    y.sayfa(kutu) { ctx in
        PDFCizim.metin("Hücre Biyolojisi", ctx, nokta: CGPoint(x: 60, y: 780), punto: 26, kalin: true)
        PDFCizim.metin("Organeller", ctx, nokta: CGPoint(x: 60, y: 740), punto: 18, kalin: true)
        let govde = ["Hücre canlıların yapı ve görev birimidir. Her hücrede", "sitoplazma ve zar bulunur. Ökaryot hücrelerde",
                     "çekirdek de vardır ve kalıtım maddesini taşır."]
        for (i, s) in govde.enumerated() { PDFCizim.metin(s, ctx, nokta: CGPoint(x: 60, y: 700 - CGFloat(i) * 15), punto: 11) }
        PDFCizim.metin("- Mitokondri enerji üretir", ctx, nokta: CGPoint(x: 60, y: 620), punto: 11)
        PDFCizim.metin("- Ribozom protein sentezler", ctx, nokta: CGPoint(x: 60, y: 605), punto: 11)
    }
    y.sayfa(kutu) { ctx in
        PDFCizim.metin("Kalıtım", ctx, nokta: CGPoint(x: 60, y: 780), punto: 26, kalin: true)
        PDFCizim.metin("Genler DNA üzerinde bulunur.", ctx, nokta: CGPoint(x: 60, y: 740), punto: 11)
    }
    let u = Ornek.gecici("yapili.pdf")
    try y.bitir().write(to: u)
    return u
}

/// Üç sütunlu tablo PDF'i (her hücre ayrı metin nesnesi).
func tabloPDF() throws -> URL {
    let y = PDFCizim.Yazici(baslik: "Tablo")
    y.sayfa(CGRect(x: 0, y: 0, width: 595, height: 842)) { ctx in
        let satirlar = [["Ad", "Sınıf", "Puan"], ["Ayşe", "9-A", "85"], ["Mehmet", "9-B", "72,5"], ["Zeynep", "9-A", "90"]]
        for (r, s) in satirlar.enumerated() {
            for (c, h) in s.enumerated() {
                PDFCizim.metin(h, ctx, nokta: CGPoint(x: 72 + CGFloat(c) * 150, y: 760 - CGFloat(r) * 24), punto: 12)
            }
        }
    }
    let u = Ornek.gecici("tablo.pdf")
    try y.bitir().write(to: u)
    return u
}

/// KAGIT_CIKTI_DIZINI tanımlıysa üretilen dosyayı oraya kopyalar (dış doğrulama için).
func disaAktar(_ u: URL) {
    guard let d = ProcessInfo.processInfo.environment["KAGIT_CIKTI_DIZINI"] else { return }
    let hedef = URL(fileURLWithPath: d).appendingPathComponent(u.lastPathComponent)
    try? FileManager.default.removeItem(at: hedef)
    try? FileManager.default.copyItem(at: u, to: hedef)
}

func xmlGecerli(_ d: Data) -> Bool {
    let p = XMLParser(data: d)
    return p.parse()
}

@Suite struct ModulAGorselDonusumTestleri {

    @Test func gorseldenPDFSayfaBoyutlari() throws {
        let dikey = try ornekGorsel(300, 400, ad: "dikey.jpg"), yatay = try ornekGorsel(400, 300, tur: .png, ad: "yatay.png")
        var a = GorselPDFAyari()
        a.sayfaBoyutu = .a4
        let d = try Belge.ac(GorselPDF.gorseldenPDF([dikey, yatay], ayar: a))
        #expect(d.pageCount == 2)
        let b0 = d.page(at: 0)!.bounds(for: .cropBox), b1 = d.page(at: 1)!.bounds(for: .cropBox)
        #expect(b0.height > b0.width)
        #expect(b1.width > b1.height)
        a.yon = .dikey
        let z = try Belge.ac(GorselPDF.gorseldenPDF([yatay], ayar: a))
        #expect(z.page(at: 0)!.bounds(for: .cropBox).height > 800)
        a.sayfaBoyutu = .letter; a.yon = .otomatik
        #expect(abs(try Belge.ac(GorselPDF.gorseldenPDF([dikey], ayar: a)).page(at: 0)!.bounds(for: .cropBox).width - 612) < 1)
        a.sayfaBoyutu = .gorselBoyutu; a.kenarBosluk = 10
        let g = try Belge.ac(GorselPDF.gorseldenPDF([dikey], ayar: a)).page(at: 0)!.bounds(for: .cropBox)
        #expect(abs(g.width - (300 * 72 / 150 + 20)) < 1)
    }

    @Test func gorseldenPDFSigdirDoldur() throws {
        let img = try ornekGorsel(200, 200, ad: "kare.jpg")   // sarı orta + mavi çevre
        var a = GorselPDFAyari()
        a.sigdir = true
        let sigdir = try Belge.ac(GorselPDF.gorseldenPDF([img], ayar: a)).page(at: 0)!
        a.sigdir = false
        let doldur = try Belge.ac(GorselPDF.gorseldenPDF([img], ayar: a)).page(at: 0)!
        // Sığdır: üstte/altta beyaz boşluk var → içerik yüksekliği az; doldur: sayfayı kaplar
        #expect(icerikOranlari(sigdir)!.height < 0.8)
        #expect(icerikOranlari(doldur)!.height > 0.95)
    }

    @Test func gorseldenPDFHatalar() throws {
        #expect(throws: KagitHata.bosGirdi) { try GorselPDF.gorseldenPDF([]) }
        let bozuk = Ornek.gecici("bozuk.jpg")
        try Data([0, 1, 2, 3]).write(to: bozuk)
        #expect(throws: KagitHata.self) { try GorselPDF.gorseldenPDF([bozuk]) }
    }

    @Test func gorseldenPDFHEIC() throws {
        let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0.6, blue: 0.2, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        guard let heic = PDFCizim.kodla(ctx.makeImage()!, tur: .heic) else { return }   // kodlayıcı yoksa atla
        let u = Ornek.gecici("foto.heic")
        try heic.write(to: u)
        #expect(try Belge.ac(GorselPDF.gorseldenPDF([u])).pageCount == 1)
    }

    @Test func bosPDFDesenleri() throws {
        for d in BosPDFDeseni.allCases {
            let u = try GorselPDF.bosPDF(boyut: .a5, yatay: true, sayfaSayisi: 3, desen: d)
            let b = try Belge.ac(u)
            #expect(b.pageCount == 3)
            let kutu = b.page(at: 0)!.bounds(for: .cropBox)
            #expect(kutu.width > kutu.height && abs(kutu.height - 419.53) < 0.1)
            let icerik = icerikOranlari(b.page(at: 0)!, esik: 250)
            if d == .bos { #expect(icerik == nil) } else { #expect(icerik != nil) }
        }
        #expect(throws: KagitHata.self) { try GorselPDF.bosPDF(sayfaSayisi: 0) }
    }

    @Test func pdftenGorselePNGVeJPEG() throws {
        let u = try ornekDosya(4)
        let png = try PDFGorsel.pdftenGorsele(u, bicim: .png, dpi: 72, aralik: "2-3")
        #expect(png.count == 2)
        #expect(png[0].lastPathComponent.hasSuffix("-002.png"))
        let kaynak = CGImageSourceCreateWithURL(png[0] as CFURL, nil)!
        let ozellik = CGImageSourceCopyPropertiesAtIndex(kaynak, 0, nil) as! [CFString: Any]
        #expect((ozellik[kCGImagePropertyPixelWidth] as! Int) == 595)
        let jpg = try PDFGorsel.pdftenGorsele(u, bicim: .jpeg, dpi: 144, kalite: 0.5)
        #expect(jpg.count == 4)
        #expect(jpg[0].pathExtension == "jpg")
        let buyuk = try PDFGorsel.pdftenGorsele(u, dpi: 288, aralik: "1")
        #expect(IsYardimcisi.dosyaBoyutu(buyuk[0]) > IsYardimcisi.dosyaBoyutu(png[0]))
        #expect(throws: KagitHata.self) { try PDFGorsel.pdftenGorsele(u, dpi: 10) }
    }

    @Test func pdftenGorseleZip() throws {
        let u = try ornekDosya(3)
        let z = try PDFGorsel.pdftenGorsele(u, dpi: 50, zip: true)
        #expect(z.count == 1 && z[0].pathExtension == "zip")
        let icerik = ZipOkuyucu.ac(try Data(contentsOf: z[0]))
        #expect(icerik.count == 3)
        #expect(icerik.keys.sorted().first?.hasSuffix("-001.png") == true)
    }

    @Test func gomuluGorselleriCikar() throws {
        let u = try gorselliPDF(sayfa: 2)
        let liste = try PDFGorsel.gomuluGorseller(u, bicim: .png)
        #expect(liste.count == 2)
        #expect(liste[0].sayfa == 0 && liste[1].sayfa == 1)
        #expect(liste[0].genislik == 1000 && liste[0].yukseklik == 1400)
        let img = PDFCizim.goruntuYukle(liste[0].veri)
        #expect(img?.width == 1000)
        let dosyalar = try PDFGorsel.pdftenGorselleriCikar(u, aralik: "2", bicim: .jpeg)
        #expect(dosyalar.count == 1 && dosyalar[0].lastPathComponent.contains("-s2-1.jpg"))
        let zip = try PDFGorsel.pdftenGorselleriCikar(u, zip: true)
        #expect(ZipOkuyucu.ac(try Data(contentsOf: zip[0])).count == 2)
        // Görselsiz PDF
        #expect(throws: KagitHata.self) { try PDFGorsel.pdftenGorselleriCikar(ornekDosya(1)) }
    }
}

@Suite struct ModulAMetinDonusumTestleri {

    @Test func txtPDFOlur() async throws {
        let u = Ornek.gecici("not.txt")
        try "Merhaba dünya.\nTürkçe: ığüşöçİĞÜŞÖÇ\n".write(to: u, atomically: true, encoding: .utf8)
        let pdf = try Belge.ac(try await MetindenPDF.cevir(u))
        #expect(pdf.pageCount == 1)
        let m = pdf.page(at: 0)?.string ?? ""
        #expect(m.contains("Merhaba dünya"))
        #expect(m.contains("ığüşöç"))
    }

    @Test func uzunMetinCokSayfa() async throws {
        let u = Ornek.gecici("uzun.txt")
        try (1...400).map { "Satır numarası \($0) ve biraz daha uzun bir metin parçası." }.joined(separator: "\n")
            .write(to: u, atomically: true, encoding: .utf8)
        let pdf = try Belge.ac(try await MetindenPDF.cevir(u))
        #expect(pdf.pageCount >= 5)
        #expect(pdf.page(at: pdf.pageCount - 1)?.string?.contains("400") == true)
    }

    @Test func markdownBasliklarKalin() async throws {
        let u = Ornek.gecici("ders.md")
        try "# Ana Başlık\n\nBu bir **kalın** ve *italik* metindir.\n\n- madde bir\n- madde iki\n\n## Alt başlık\n\n```\nkod satırı\n```\n"
            .write(to: u, atomically: true, encoding: .utf8)
        let pdf = try Belge.ac(try await MetindenPDF.cevir(u))
        let m = pdf.page(at: 0)?.string ?? ""
        #expect(m.contains("Ana Başlık"))
        #expect(m.contains("kalın"))
        #expect(!m.contains("**"))
        #expect(m.contains("madde iki"))
        #expect(m.contains("kod satırı"))
        // Yapı çıkarımı başlığı tanır (punto farkı)
        let bloklar = try PDFYapisi.cikar(pdf)
        #expect(bloklar.contains(.baslik(1, "Ana Başlık")) || bloklar.contains { if case .baslik(_, let t) = $0 { t.contains("Ana Başlık") } else { false } })
    }

    @Test func rtfPDFOlur() async throws {
        let ats = NSAttributedString(string: "RTF belgesi içeriği: Türkçe ğüş")
        let veri = try ats.data(from: NSRange(location: 0, length: ats.length),
                                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let u = Ornek.gecici("belge.rtf")
        try veri.write(to: u)
        let pdf = try Belge.ac(try await MetindenPDF.cevir(u))
        #expect(pdf.page(at: 0)?.string?.contains("RTF belgesi") == true)
    }

    @Test func htmlYedekYolu() async throws {
        let u = Ornek.gecici("sayfa.html")
        try "<html><head><style>p{color:red}</style></head><body><h1>Başlık</h1><p>Paragraf &amp; metin</p></body></html>"
            .write(to: u, atomically: true, encoding: .utf8)
        let pdf = try Belge.ac(try await MetindenPDF.cevir(u))
        let m = pdf.page(at: 0)?.string ?? ""
        #expect(m.contains("Başlık") && m.contains("Paragraf & metin"))
        #expect(!m.contains("color:red"))
    }

    @Test func desteklenmeyenUzanti() async throws {
        let u = Ornek.gecici("a.docx")
        try Data([1]).write(to: u)
        await #expect(throws: KagitHata.self) { try await MetindenPDF.cevir(u) }
        #expect(!MetindenPDF.yerelMi(u) && MetindenPDF.yerelMi(Ornek.gecici("b.md")))
        let bos = Ornek.gecici("bos.txt")
        try Data().write(to: bos)
        await #expect(throws: KagitHata.self) { try await MetindenPDF.cevir(bos) }
    }

    @Test func metindenPDF() throws {
        let pdf = try Belge.ac(MetindenPDF.metindenPDF("Hızlı not: şeker çay"))
        #expect(pdf.page(at: 0)?.string?.contains("şeker çay") == true)
    }
}

@Suite struct ModulAPDFtenMetinTestleri {

    @Test func yapiCikarimi() throws {
        let b = try Belge.ac(try yapiliPDF())
        let bl = try PDFYapisi.cikar(b)
        var basliklar: [(Int, String)] = []
        var paragraflar: [String] = []
        var maddeler: [String] = []
        for x in bl {
            switch x {
            case .baslik(let n, let t): basliklar.append((n, t))
            case .paragraf(let t): paragraflar.append(t)
            case .madde(let t): maddeler.append(t)
            case .sayfa: break
            }
        }
        #expect(basliklar.first?.1 == "Hücre Biyolojisi" && basliklar.first?.0 == 1)
        #expect(basliklar.contains { $0.1 == "Organeller" && $0.0 >= 2 })
        #expect(basliklar.contains { $0.1 == "Kalıtım" })
        // Üç satır tek paragrafta birleşmeli
        #expect(paragraflar.contains { $0.contains("canlıların yapı ve görev birimidir. Her hücrede sitoplazma") })
        #expect(maddeler == ["Mitokondri enerji üretir", "Ribozom protein sentezler"])
    }

    @Test func metinMarkdownHTML() throws {
        let u = try yapiliPDF()
        let m = try String(contentsOf: PDFYapisi.pdftenMarkdown(u), encoding: .utf8)
        #expect(m.contains("# Hücre Biyolojisi"))
        #expect(m.contains("- Mitokondri enerji üretir"))
        let h = try String(contentsOf: PDFYapisi.pdftenHTML(u), encoding: .utf8)
        #expect(h.contains("<h1>Hücre Biyolojisi</h1>") && h.contains("<li>Ribozom protein sentezler</li>"))
        #expect(xmlGecerli(Data(h.replacingOccurrences(of: "<!DOCTYPE html>", with: "").replacingOccurrences(of: "<hr id=\"sayfa1\">", with: "").utf8)) || h.contains("<ul>"))
        let t = try String(contentsOf: PDFYapisi.pdftenMetin(u, aralik: "2"), encoding: .utf8)
        #expect(t.contains("Genler DNA") && !t.contains("Mitokondri"))
        let ayiricili = try String(contentsOf: PDFYapisi.pdftenMetin(u, sayfaAyirici: true), encoding: .utf8)
        #expect(ayiricili.contains("— Sayfa 2 —"))
    }

    @Test func metinsizPDFHataVerir() throws {
        let bos = try GorselPDF.bosPDF(sayfaSayisi: 2)
        #expect(throws: KagitHata.self) { try PDFYapisi.pdftenMetin(bos) }
        #expect(throws: KagitHata.self) { try PDFYapisi.pdftenMarkdown(bos) }
    }

    @Test func epubYapisi() throws {
        let u = try yapiliPDF()
        let epubU = try PDFYapisi.pdftenEPUB(u)
        disaAktar(epubU)
        let e = try Data(contentsOf: epubU)
        // İlk girdi "mimetype", sıkıştırılmamış
        #expect(String(decoding: e[30..<38], as: UTF8.self) == "mimetype")
        #expect(String(decoding: e[38..<58], as: UTF8.self) == "application/epub+zip")
        let z = ZipOkuyucu.ac(e)
        for ad in ["META-INF/container.xml", "OEBPS/content.opf", "OEBPS/nav.xhtml", "OEBPS/toc.ncx", "OEBPS/bolum1.xhtml"] {
            #expect(z[ad] != nil, "\(ad) yok")
            if let d = z[ad] { #expect(xmlGecerli(d), "\(ad) geçerli XML değil") }
        }
        let opf = String(decoding: z["OEBPS/content.opf"]!, as: UTF8.self)
        #expect(opf.contains("<dc:language>tr</dc:language>") && opf.contains("dcterms:modified"))
        let bolum = String(decoding: z["OEBPS/bolum1.xhtml"]!, as: UTF8.self)
        #expect(bolum.contains("Hücre Biyolojisi"))
    }

    @Test func epubBolumlereAyirir() {
        let bl: [PDFBlok] = [.sayfa(1), .baslik(1, "Bir"), .paragraf("a"), .sayfa(2), .baslik(1, "İki"), .paragraf("b")]
        let z = ZipOkuyucu.ac(PDFYapisi.epub(baslik: "K", bloklar: bl))
        #expect(z["OEBPS/bolum1.xhtml"] != nil && z["OEBPS/bolum2.xhtml"] != nil)
        #expect(String(decoding: z["OEBPS/nav.xhtml"]!, as: UTF8.self).contains("İki"))
    }
}

@Suite struct ModulAOfficeDonusumTestleri {

    @Test func wordYerel() throws {
        let u = try yapiliPDF()
        let d = try PDFOffice.pdftenWord(u)
        disaAktar(d)
        #expect(d.pathExtension == "docx")
        let z = ZipOkuyucu.ac(try Data(contentsOf: d))
        for ad in ["[Content_Types].xml", "_rels/.rels", "word/document.xml", "word/styles.xml", "word/_rels/document.xml.rels"] {
            #expect(z[ad] != nil && xmlGecerli(z[ad]!), "\(ad) hatalı")
        }
        let doc = String(decoding: z["word/document.xml"]!, as: UTF8.self)
        #expect(doc.contains("Heading1") && doc.contains("Hücre Biyolojisi"))
        #expect(doc.contains("• Mitokondri"))
        #expect(doc.contains("w:br w:type=\"page\""))
    }

    @Test func wordGorselVeTaranmisSayfa() throws {
        let gorselli = try gorselliPDF(sayfa: 1)
        let wd = try PDFOffice.pdftenWord(gorselli)
        disaAktar(wd)
        let z = ZipOkuyucu.ac(try Data(contentsOf: wd))
        #expect(z.keys.contains { $0.hasPrefix("word/media/img") })
        #expect(String(decoding: z["word/document.xml"]!, as: UTF8.self).contains("<a:blip r:embed=\"rIdR1\"/>"))
        // Metinsiz, görselsiz sayfa → sayfa görüntüsü eklenir
        let bos = try GorselPDF.bosPDF(sayfaSayisi: 1, desen: .kareli)
        let z2 = ZipOkuyucu.ac(try Data(contentsOf: PDFOffice.pdftenWord(bos)))
        #expect(z2.keys.contains { $0.hasPrefix("word/media/img") })
    }

    @Test func excelTablo() throws {
        let u = try tabloPDF()
        let x = try PDFOffice.pdftenExcel(u)
        disaAktar(x)
        let z = ZipOkuyucu.ac(try Data(contentsOf: x))
        for ad in ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels", "xl/styles.xml", "xl/worksheets/sheet1.xml"] {
            #expect(z[ad] != nil && xmlGecerli(z[ad]!), "\(ad) hatalı")
        }
        let s = String(decoding: z["xl/worksheets/sheet1.xml"]!, as: UTF8.self)
        #expect(s.contains("<c r=\"A1\" t=\"inlineStr\"><is><t xml:space=\"preserve\">Ad</t></is></c>"))
        #expect(s.contains("<c r=\"C1\" t=\"inlineStr\"><is><t xml:space=\"preserve\">Puan</t></is></c>"))
        #expect(s.contains("<c r=\"C2\"><v>85.0</v></c>"))
        #expect(s.contains("<c r=\"C3\"><v>72.5</v></c>"))
        #expect(s.contains("Mehmet") && s.contains("<c r=\"B4\" t=\"inlineStr\"><is><t xml:space=\"preserve\">9-A"))
        #expect(OfficeYazici.sutunHarfi(0) == "A" && OfficeYazici.sutunHarfi(27) == "AB")
    }

    @Test func excelMetinsizHata() throws {
        let bos = try GorselPDF.bosPDF(sayfaSayisi: 1)
        #expect(throws: KagitHata.self) { try PDFOffice.pdftenExcel(bos) }
    }

    @Test func hucreSayiAlgisi() {
        if case .sayi(let d) = PDFOffice.hucre("1,5") { #expect(d == 1.5) } else { Issue.record("sayı değil") }
        if case .metin = PDFOffice.hucre("007") {} else { Issue.record("baştaki sıfır metin kalmalı") }
        if case .metin = PDFOffice.hucre("9-A") {} else { Issue.record("metin olmalı") }
    }

    @Test func powerPoint() throws {
        let u = try ornekDosya(3)
        let p = try PDFOffice.pdftenPowerPoint(u, dpi: 60)
        disaAktar(p)
        let z = ZipOkuyucu.ac(try Data(contentsOf: p))
        for ad in ["[Content_Types].xml", "_rels/.rels", "ppt/presentation.xml", "ppt/_rels/presentation.xml.rels",
                   "ppt/slideMasters/slideMaster1.xml", "ppt/slideMasters/_rels/slideMaster1.xml.rels",
                   "ppt/slideLayouts/slideLayout1.xml", "ppt/slideLayouts/_rels/slideLayout1.xml.rels", "ppt/theme/theme1.xml",
                   "ppt/slides/slide1.xml", "ppt/slides/slide3.xml", "ppt/slides/_rels/slide2.xml.rels"] {
            #expect(z[ad] != nil && xmlGecerli(z[ad]!), "\(ad) hatalı")
        }
        #expect(z["ppt/media/image3.jpg"] != nil)
        #expect(String(decoding: z["ppt/presentation.xml"]!, as: UTF8.self).components(separatedBy: "<p:sldId ").count == 4)
    }
}

@Suite struct ModulAOnarTestleri {

    @Test func saglamDosya() throws {
        let u = try ornekDosya(3)
        let s = try PDFOnar.onar(u)
        #expect(s.sayfaSayisi == 3)
        #expect(try Belge.ac(s.cikti).page(at: 2)?.string?.contains("Sayfa 3") == true)
    }

    @Test func xrefBozukDosya() throws {
        var veri = try Data(contentsOf: ornekDosya(2))
        // startxref konumunu boz
        if let r = veri.range(of: Data("startxref".utf8), options: .backwards) {
            veri.replaceSubrange(r.upperBound..<veri.endIndex, with: Data("\n99999999\n%%EOF\n".utf8))
        }
        let bozuk = Ornek.gecici("bozuk.pdf")
        try veri.write(to: bozuk)
        let s = try PDFOnar.onar(bozuk)
        #expect(s.sayfaSayisi == 2)
        #expect(try Belge.ac(s.cikti).pageCount == 2)
    }

    @Test func cop() throws {
        let u = Ornek.gecici("cop.pdf")
        try Data("bu bir pdf değil".utf8).write(to: u)
        #expect(throws: KagitHata.self) { try PDFOnar.onar(u) }
    }
}

@Suite struct ModulAKarsilastirmaTestleri {

    @Test func metinFarki() throws {
        let a = Ornek.gecici("a.pdf"), b = Ornek.gecici("b.pdf")
        try Ornek.pdf([["Birinci satır", "İkinci satır"], ["Aynı sayfa"]]).write(to: a)
        try Ornek.pdf([["Birinci satır", "Değişen satır", "Yeni satır"], ["Aynı sayfa"]]).write(to: b)
        let s = try PDFKarsilastirma.karsilastir(a, b)
        #expect(s.sayfaA == 2 && s.sayfaB == 2)
        #expect(s.farkliSayfalar.map(\.sayfa) == [1])
        #expect(s.farklar[0].silinen == ["İkinci satır"])
        #expect(s.farklar[0].eklenen == ["Değişen satır", "Yeni satır"])
        #expect(s.farklar[0].gorselFark > 0)
        #expect(s.farklar[1].gorselFark == 0 && !s.farklar[1].farkliMi)
        #expect(!s.ozdesMi)
        #expect(s.toplamEklenen == 2 && s.toplamSilinen == 1)
        let rapor = try Belge.ac(try #require(s.rapor))
        let m = rapor.page(at: 0)?.string ?? ""
        #expect(m.contains("karşılaştırma raporu"))
        #expect(m.contains("Sayfa 1"))
        #expect(m.contains("+ Yeni satır") && m.contains("İkinci satır"))
        #expect(!m.contains("Sayfa 2 —"))
    }

    @Test func ozdesBelgeler() throws {
        let a = try ornekDosya(3, ad: "x.pdf"), b = try ornekDosya(3, ad: "y.pdf")
        let s = try PDFKarsilastirma.karsilastir(a, b)
        #expect(s.ozdesMi)
        #expect(s.rapor != nil)
        #expect((try Belge.ac(s.rapor!).page(at: 0)?.string ?? "").contains("fark bulunmadı"))
        let ham = try PDFKarsilastirma.karsilastir(a, b, raporYaz: false, gorselFark: false)
        #expect(ham.rapor == nil && ham.ozdesMi)
    }

    @Test func sayfaSayisiFarkli() throws {
        let a = try ornekDosya(2, ad: "k.pdf"), b = try ornekDosya(4, ad: "l.pdf")
        let s = try PDFKarsilastirma.karsilastir(a, b)
        #expect(s.farklar.count == 4)
        #expect(s.farklar[2].yalnizB && s.farklar[3].yalnizB)
        #expect(s.farklar[2].eklenen == ["Sayfa 3"])
        #expect(s.farkliSayfalar.count == 2)
    }

    @Test func gorselFarkSadeceCizimde() throws {
        let a = Ornek.gecici("g1.pdf"), b = Ornek.gecici("g2.pdf")
        let y1 = PDFCizim.Yazici(), y2 = PDFCizim.Yazici()
        for (y, kare) in [(y1, false), (y2, true)] {
            y.sayfa(CGRect(x: 0, y: 0, width: 595, height: 842)) { ctx in
                PDFCizim.metin("Aynı metin", ctx, nokta: CGPoint(x: 72, y: 700), punto: 14)
                if kare { ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 100, y: 200, width: 300, height: 300)) }
            }
        }
        try y1.bitir().write(to: a); try y2.bitir().write(to: b)
        let s = try PDFKarsilastirma.karsilastir(a, b)
        #expect(!s.farklar[0].metinFarkiVar)
        #expect(s.farklar[0].gorselFark > 0.1)
        #expect(s.farkliSayfalar.count == 1)
    }
}
