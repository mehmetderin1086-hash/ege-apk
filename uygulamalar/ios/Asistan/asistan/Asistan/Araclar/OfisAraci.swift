import Foundation
import FoundationModels
import UIKit

nonisolated enum OfisOlusturucu {
    struct Icerik: Sendable {
        let baslik: String
        let paragraflar: [String]
        let tablo: ExcelOlusturucu.Tablo?
        let slaytlar: [(baslik: String, maddeler: [String])]
        /// Paragraf biçimleri (`paragraflar` ile paralel); boşsa bütün paragraflar düz (eski çıktı bayt bayt aynı).
        var bicimler: [ParagrafBicimi] = []
    }

    /// `paragraphs` öğesi nesne verilince: {"text", "align": "left|center|right|both", "bold": true, "indent": true}.
    nonisolated struct ParagrafBicimi: Sendable, Equatable {
        var hiza: String? = nil      // left | center | right | both (iki yana yaslı)
        var kalin = false
        var girinti = false          // ilk satır girintisi 709 twip (1,25 cm)
        var duzMu: Bool { hiza == nil && !kalin && !girinti }

        static let hizalar: Set<String> = ["left", "center", "right", "both"]
        /// Nesne paragrafın biçimi; tanınmayan hizalama yok sayılır.
        static func coz(_ s: [String: Any]) -> ParagrafBicimi {
            let h = (s["align"] as? String)?.lowercased().trimmingCharacters(in: .whitespaces)
            func evet(_ v: Any?) -> Bool { (v as? Bool) ?? ((v as? NSNumber)?.boolValue ?? false) }
            return ParagrafBicimi(hiza: h.flatMap { hizalar.contains($0) ? $0 : ($0 == "justify" ? "both" : nil) },
                                  kalin: evet(s["bold"]), girinti: evet(s["indent"]))
        }
    }

    static func icerik(_ json: String) throws -> Icerik {
        guard json.utf8.count <= 1_000_000,
              let data = json.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IndirmeHatasi.metin("Ofis içeriği geçerli bir JSON nesnesi ve en fazla 1 MB olmalı.")
        }
        func metin(_ value: Any?) -> String { String((value as? String ?? "").prefix(10_000)) }
        let baslik = metin(root["title"])
        let hamParagraflar = (root["paragraphs"] as? [Any] ?? []).prefix(300)
        // Öğe metin YA DA {"text", "align", "bold", "indent"} nesnesi olabilir.
        let paragraflar = hamParagraflar.map { ($0 as? [String: Any]).map { metin($0["text"]) } ?? metin($0) }
        let bicimler = hamParagraflar.contains { $0 is [String: Any] }
            ? hamParagraflar.map { ($0 as? [String: Any]).map(ParagrafBicimi.coz) ?? ParagrafBicimi() } : []
        var tablo: ExcelOlusturucu.Tablo?
        if let t = root["table"] as? [String: Any],
           let d = try? JSONSerialization.data(withJSONObject: t),
           let s = String(data: d, encoding: .utf8) { tablo = try ExcelOlusturucu.tablo(s) }
        let slaytlar: [(String, [String])] = (root["slides"] as? [[String: Any]] ?? []).prefix(60).map {
            (metin($0["title"]), ($0["body"] as? [Any] ?? []).prefix(20).map { metin($0) })
        }
        guard !baslik.isEmpty || !paragraflar.isEmpty || tablo != nil || !slaytlar.isEmpty else {
            throw IndirmeHatasi.metin("Başlık, paragraphs, table veya slides alanlarından en az biri gerekli.")
        }
        return Icerik(baslik: baslik, paragraflar: paragraflar, tablo: tablo, slaytlar: slaytlar, bicimler: bicimler)
    }

    /// `resmi`: Resmî Yazışma Yönetmeliği düzeni (2,5 cm kenar, Times New Roman 12 pt, tek satır aralığı, kenarlıklı tablo).
    /// Biçimsiz ve resmi olmayan girdi eski çıktıyı bayt bayt aynı üretir.
    static func docx(_ i: Icerik, resmi: Bool = false) -> Data {
        var body = ""
        if !i.baslik.isEmpty { body += paragraph(i.baslik, style: "Title") }
        if i.bicimler.isEmpty && !resmi {
            body += i.paragraflar.map { paragraph($0) }.joined()
        } else {
            body += i.paragraflar.enumerated().map { n, p in
                bicimliParagraf(p, n < i.bicimler.count ? i.bicimler[n] : ParagrafBicimi())
            }.joined()
        }
        if let t = i.tablo {
            body += "<w:tbl>" + (resmi ? resmiTabloOzellikleri : "") + ([t.sutunlar] + t.satirlar).map { row in
                "<w:tr>" + row.map { "<w:tc><w:p><w:r><w:t xml:space=\"preserve\">\(xml($0))</w:t></w:r></w:p></w:tc>" }.joined() + "</w:tr>"
            }.joined() + "</w:tbl>"
        }
        return resmi ? docxPaketi(govde: body, kenar: resmiKenar, stiller: resmiStiller) : docxPaketi(govde: body)
    }

    /// Biçimli paragraf: ilk satır girintisi (709), hizalama (`w:jc`), kalın (`w:b`); satır sonları `w:br` olur.
    /// Biçimsiz ve tek satırlı paragraf `paragraph(_:)` ile aynıdır.
    static func bicimliParagraf(_ s: String, _ b: ParagrafBicimi) -> String {
        let satirlar = s.components(separatedBy: "\n")
        if b.duzMu && satirlar.count == 1 { return paragraph(s) }
        var pPr = ""
        if b.girinti { pPr += "<w:ind w:firstLine=\"709\"/>" }
        if let h = b.hiza { pPr += "<w:jc w:val=\"\(h)\"/>" }
        let rPr = b.kalin ? "<w:rPr><w:b/></w:rPr>" : ""
        let metin = satirlar.map { "<w:t xml:space=\"preserve\">\(xml($0))</w:t>" }.joined(separator: "<w:br/>")
        return "<w:p>" + (pPr.isEmpty ? "" : "<w:pPr>\(pPr)</w:pPr>") + "<w:r>\(rPr)\(metin)</w:r></w:p>"
    }

    /// Resmî yazı kenar boşluğu: 2,5 cm = 1418 twip.
    static let resmiKenar = 1418
    /// Resmî düzen stilleri: Normal Times New Roman 12 pt, tek satır aralığı, paragraf sonrası 6 nk; Title ortalı kalın 12 pt.
    static let resmiStiller = xmlHeader + #"<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman" w:eastAsia="Times New Roman"/><w:sz w:val="24"/><w:szCs w:val="24"/><w:lang w:val="tr-TR"/></w:rPr></w:rPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:pPr><w:spacing w:before="0" w:after="120" w:line="240" w:lineRule="auto"/></w:pPr><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:pPr><w:jc w:val="center"/></w:pPr><w:rPr><w:b/><w:sz w:val="24"/></w:rPr></w:style></w:styles>"#
    /// Resmî düzende tablo (ör. tutanak imza tablosu) tam genişlik ve tek çizgi kenarlıklı.
    static let resmiTabloOzellikleri = #"<w:tblPr><w:tblW w:w="5000" w:type="pct"/><w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="000000"/><w:left w:val="single" w:sz="4" w:space="0" w:color="000000"/><w:bottom w:val="single" w:sz="4" w:space="0" w:color="000000"/><w:right w:val="single" w:sz="4" w:space="0" w:color="000000"/><w:insideH w:val="single" w:sz="4" w:space="0" w:color="000000"/><w:insideV w:val="single" w:sz="4" w:space="0" w:color="000000"/></w:tblBorders></w:tblPr>"#

    /// Varsayılan `word/styles.xml` (Normal 11 pt, Title kalın 18 pt). Başka düzenler kendi stil metnini verir.
    static let varsayilanStiller = xmlHeader + #"<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:rPr><w:sz w:val="22"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="36"/></w:rPr></w:style></w:styles>"#

    /// `word/document.xml`: A4 sayfa, dört kenarda `kenar` twip (1440 = 2,54 cm) boşluk; `govde` w:body içeriğidir.
    static func belgeXML(govde: String, kenar: Int = 1440) -> String {
        xmlHeader + #"<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>"# + govde + #"<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="\#(kenar)" w:right="\#(kenar)" w:bottom="\#(kenar)" w:left="\#(kenar)"/></w:sectPr></w:body></w:document>"#
    }

    /// DOCX paketleyicisi (ZipYazici zaman damgası yazmaz; aynı girdi bayt bayt aynı çıktıyı verir).
    static func docxPaketi(govde: String, kenar: Int = 1440, stiller: String = varsayilanStiller) -> Data {
        ZipYazici.olustur([
            ("[Content_Types].xml", Data((xmlHeader + #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>"#).utf8)),
            ("_rels/.rels", Data((xmlHeader + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>"#).utf8)),
            ("word/document.xml", Data(belgeXML(govde: govde, kenar: kenar).utf8)),
            ("word/styles.xml", Data(stiller.utf8))
        ])
    }

    static func pptx(_ i: Icerik) -> Data {
        let slides = i.slaytlar.isEmpty ? [(i.baslik, i.paragraflar)] : i.slaytlar
        var files: [(String, Data)] = []
        let overrides = slides.indices.map { #"<Override PartName="/ppt/slides/slide\#($0 + 1).xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>"# }.joined()
        files.append(("[Content_Types].xml", Data((xmlHeader + #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/><Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/><Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>"# + overrides + "</Types>").utf8)))
        files.append(("_rels/.rels", Data((xmlHeader + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/></Relationships>"#).utf8)))
        let ids = slides.indices.map { #"<p:sldId id="\#(256 + $0)" r:id="rId\#($0 + 2)"/>"# }.joined()
        files.append(("ppt/presentation.xml", Data((xmlHeader + #"<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst>"# + ids + #"</p:sldIdLst><p:sldSz cx="12192000" cy="6858000"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>"#).utf8)))
        var rels = #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>"#
        for n in slides.indices { rels += #"<Relationship Id="rId\#(n + 2)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide\#(n + 1).xml"/>"# }
        files.append(("ppt/_rels/presentation.xml.rels", Data((xmlHeader + rels + "</Relationships>").utf8)))
        files.append(("ppt/slideMasters/slideMaster1.xml", Data((xmlHeader + #"<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld><p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/><p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>"#).utf8)))
        files.append(("ppt/slideMasters/_rels/slideMaster1.xml.rels", Data((xmlHeader + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/></Relationships>"#).utf8)))
        files.append(("ppt/slideLayouts/slideLayout1.xml", Data((xmlHeader + #"<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld></p:sldLayout>"#).utf8)))
        files.append(("ppt/slideLayouts/_rels/slideLayout1.xml.rels", Data((xmlHeader + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/></Relationships>"#).utf8)))
        files.append(("ppt/theme/theme1.xml", Data((xmlHeader + #"<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Asistan"><a:themeElements><a:clrScheme name="Office"><a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1><a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="44546A"/></a:dk2><a:lt2><a:srgbClr val="E7E6E6"/></a:lt2><a:accent1><a:srgbClr val="5B4BEA"/></a:accent1><a:accent2><a:srgbClr val="ED7D31"/></a:accent2><a:accent3><a:srgbClr val="A5A5A5"/></a:accent3><a:accent4><a:srgbClr val="FFC000"/></a:accent4><a:accent5><a:srgbClr val="4472C4"/></a:accent5><a:accent6><a:srgbClr val="70AD47"/></a:accent6><a:hlink><a:srgbClr val="0563C1"/></a:hlink><a:folHlink><a:srgbClr val="954F72"/></a:folHlink></a:clrScheme><a:fontScheme name="Office"><a:majorFont><a:latin typeface="Aptos Display"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont><a:minorFont><a:latin typeface="Aptos"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme><a:fmtScheme name="Office"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="12700"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="19050"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>"#).utf8)))
        for (index, slide) in slides.enumerated() {
            files.append(("ppt/slides/slide\(index + 1).xml", Data(slideXML(title: slide.0, body: slide.1).utf8)))
            files.append(("ppt/slides/_rels/slide\(index + 1).xml.rels", Data((xmlHeader + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/></Relationships>"#).utf8)))
        }
        return ZipYazici.olustur(files)
    }

    /// Ana aktöre bağlı değil: UIGraphicsPDFRenderer/NSLayoutManager başlıklarında UI aktörü yok, nesneler yerel.
    /// Uzun PDF arayüzü dondurmasın diye çağıranlar `Task.detached` içinde üretir.
    /// `resmi`: 2,5 cm kenar, Times New Roman 12 pt; paragraf biçimleri (hizalama, kalın, girinti) her iki düzende uygulanır.
    static func pdf(_ i: Icerik, resmi: Bool = false) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        // Eski düzen: sol 48, genişlik 499, üst 56, alt sınır 790. Resmî: dört kenar 2,5 cm ≈ 71 pt.
        let sol: CGFloat = resmi ? 71 : 48, genislik: CGFloat = resmi ? 453 : 499
        let ust: CGFloat = resmi ? 71 : 56, alt: CGFloat = resmi ? 771 : 790
        let normalYazi = resmi ? (UIFont(name: "TimesNewRomanPSMT", size: 12) ?? .systemFont(ofSize: 12)) : .systemFont(ofSize: 12)
        let kalinYazi = resmi ? (UIFont(name: "TimesNewRomanPS-BoldMT", size: 12) ?? .boldSystemFont(ofSize: 12)) : .boldSystemFont(ofSize: 12)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { ctx in
            var y: CGFloat = ust
            func newPage() { ctx.beginPage(); y = ust }
            func draw(_ text: String, font: UIFont, gap: CGFloat = 12, bicim: ParagrafBicimi? = nil) {
                if y > alt - 30 { newPage() }
                // Sabit siyah: dinamik UIColor.label karanlık modda beyaza çözülür, beyaz sayfada yazı görünmez.
                var attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
                if let b = bicim, !b.duzMu {
                    let stil = NSMutableParagraphStyle()
                    switch b.hiza {
                    case "center": stil.alignment = .center
                    case "right": stil.alignment = .right
                    case "both": stil.alignment = .justified
                    default: stil.alignment = .left
                    }
                    if b.girinti { stil.firstLineHeadIndent = 35.4 }   // 709 twip = 1,25 cm
                    attr[.paragraphStyle] = stil
                }
                let secenek: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
                let size = (text as NSString).boundingRect(with: CGSize(width: genislik, height: CGFloat.greatestFiniteMagnitude), options: secenek, attributes: attr, context: nil).integral
                if y + size.height <= alt {
                    (text as NSString).draw(with: CGRect(x: sol, y: y, width: genislik, height: size.height + 8), options: secenek, attributes: attr, context: nil)
                    y += size.height + gap
                    return
                }
                if size.height <= alt - ust {   // tam sayfaya sığıyorsa bölmeden yeni sayfaya al
                    newPage()
                    (text as NSString).draw(with: CGRect(x: sol, y: y, width: genislik, height: size.height + 8), options: secenek, attributes: attr, context: nil)
                    y += size.height + gap
                    return
                }
                // Sayfadan uzun paragraf: satır sınırlarını yerleşim yöneticisi bulur, her sayfaya sığan parça ayrı çizilir (metin kesilmez).
                let depo = NSTextStorage(string: text, attributes: attr)
                let yerlesim = NSLayoutManager()
                depo.addLayoutManager(yerlesim)
                var sayfa = 0
                while sayfa < 1_000 {
                    sayfa += 1
                    let kap = NSTextContainer(size: CGSize(width: genislik, height: alt - y))
                    kap.lineFragmentPadding = 0
                    yerlesim.addTextContainer(kap)
                    let glifler = yerlesim.glyphRange(for: kap)
                    if glifler.length == 0 { newPage(); continue }
                    let karakterler = yerlesim.characterRange(forGlyphRange: glifler, actualGlyphRange: nil)
                    let parca = (text as NSString).substring(with: karakterler)
                    let yukseklik = ceil(yerlesim.usedRect(for: kap).height)
                    (parca as NSString).draw(with: CGRect(x: sol, y: y, width: genislik, height: yukseklik + 8), options: secenek, attributes: attr, context: nil)
                    if NSMaxRange(glifler) >= yerlesim.numberOfGlyphs { y += yukseklik + gap; break }
                    newPage()
                }
            }
            newPage()
            if !i.baslik.isEmpty {
                if resmi { draw(i.baslik, font: kalinYazi, gap: 14, bicim: ParagrafBicimi(hiza: "center", kalin: true)) }
                else { draw(i.baslik, font: .boldSystemFont(ofSize: 24), gap: 22) }
            }
            for (n, p) in i.paragraflar.enumerated() {
                let b = n < i.bicimler.count ? i.bicimler[n] : nil
                draw(p, font: b?.kalin == true ? kalinYazi : normalYazi, gap: resmi ? 6 : 12, bicim: b)
            }
            // Yalnız slaytlarla istenen PDF boş kalmasın (dönüştürmede slaytlar paragraflardan türediği için yalnız paragraf yokken).
            if i.paragraflar.isEmpty {
                for s in i.slaytlar {
                    if !s.baslik.isEmpty { draw(s.baslik, font: .boldSystemFont(ofSize: 18), gap: 8) }
                    for m in s.maddeler { draw("• " + m, font: .systemFont(ofSize: 12), gap: 6) }
                }
            }
            if let t = i.tablo { for row in [t.sutunlar] + t.satirlar { draw(row.joined(separator: "  |  "), font: .monospacedSystemFont(ofSize: 9, weight: .regular), gap: 5) } }
        }
    }

    static func metin(_ i: Icerik, tur: String) throws -> Data {
        if tur == "json" {
            return try JSONSerialization.data(withJSONObject: ["title": i.baslik, "paragraphs": i.paragraflar], options: [.prettyPrinted, .sortedKeys])
        }
        if tur == "csv", let t = i.tablo {
            return Data(([t.sutunlar] + t.satirlar).map { $0.map(csv).joined(separator: ",") }.joined(separator: "\n").utf8)
        }
        let prefix = tur == "md" && !i.baslik.isEmpty ? "# \(i.baslik)\n\n" : (i.baslik.isEmpty ? "" : i.baslik + "\n\n")
        return Data((prefix + i.paragraflar.joined(separator: "\n\n")).utf8)
    }

    static let xmlHeader = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
    static func paragraph(_ s: String, style: String? = nil) -> String { "<w:p>" + (style.map { "<w:pPr><w:pStyle w:val=\"\($0)\"/></w:pPr>" } ?? "") + "<w:r><w:t xml:space=\"preserve\">\(xml(s))</w:t></w:r></w:p>" }
    static func xml(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;") }
    private static func csv(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    private static func slideXML(title: String, body: [String]) -> String {
        let titleShape = shape(id: 2, name: "Başlık", x: 685800, y: 457200, w: 10820400, h: 1143000, text: title, size: 2800, bold: true)
        let bodyShape = shape(id: 3, name: "İçerik", x: 914400, y: 1828800, w: 10363200, h: 4114800, text: body.map { "• " + $0 }.joined(separator: "\n"), size: 1800, bold: false)
        return xmlHeader + #"<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>"# + titleShape + bodyShape + "</p:spTree></p:cSld></p:sld>"
    }
    private static func shape(id: Int, name: String, x: Int, y: Int, w: Int, h: Int, text: String, size: Int, bold: Bool) -> String {
        let runs = text.split(separator: "\n", omittingEmptySubsequences: false).map { #"<a:p><a:r><a:rPr lang="tr-TR" sz="\#(size)" b="\#(bold ? 1 : 0)"/><a:t>\#(xml(String($0)))</a:t></a:r></a:p>"# }.joined()
        return #"<p:sp><p:nvSpPr><p:cNvPr id="\#(id)" name="\#(name)"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="\#(x)" y="\#(y)"/><a:ext cx="\#(w)" cy="\#(h)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr><p:txBody><a:bodyPr wrap="square"/><a:lstStyle/>\#(runs)</p:txBody></p:sp>"#
    }
}

@MainActor struct OfisAraci: Tool {
    let name = "ofisBelgesiOlustur"
    let description = "Gerçek DOCX, XLSX, PPTX, PDF, TXT, Markdown, CSV veya JSON dosyası oluşturur. Eklenen mevcut belgenin düzenlenmiş içeriğini yeni bir dosyaya yazmak için de kullanılır; özgün dosyanın üzerine yazmaz."
    @Generable struct Arguments {
        @Guide(description: "Dosya türü: docx, xlsx, pptx, pdf, txt, md, csv veya json") var tur: String
        @Guide(description: "Dosya adı; uzantı yazılmazsa eklenir") var dosyaAdi: String
        @Guide(description: "JSON: title, paragraphs; isteğe bağlı table {columns,rows}; PPTX için slides [{title,body}]. paragraphs öğesi metin ya da {\"text\", \"align\": \"left|center|right|both\", \"bold\": true, \"indent\": true} nesnesi olabilir") var icerikJSON: String
        @Guide(description: "İsteğe bağlı düzen: 'resmi' = Resmî Yazışma Yönetmeliği düzeni (DOCX/PDF: 2,5 cm kenar, Times New Roman 12 pt, tek satır aralığı; resmî yazı, tutanak, dilekçe); boşsa düz belge") var duzen: String?
    }
    func call(arguments a: Arguments) async throws -> String {
        let tur = a.tur.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["docx", "xlsx", "pptx", "pdf", "txt", "md", "csv", "json"].contains(tur) else { throw IndirmeHatasi.metin("Desteklenen türler: DOCX, XLSX, PPTX, PDF, TXT, Markdown, CSV ve JSON.") }
        // P4.7: sürüşte belge üretilmez; kullanıcının asıl isteği ertelenir (yoksa bu özet), araba bağlantısı kesilince hatırlatılır.
        if let not = SurusKipi.ortak.belgeyiErtele(ozet: "\(a.dosyaAdi) adlı \(tur.uppercased()) belgesini hazırla") { return not }
        let i = try OfisOlusturucu.icerik(a.icerikJSON)
        // 'resmi': Resmî Yazışma Yönetmeliği düzeni (DYS/EBYS'ye gönderim ve e-imza yok; yalnız taslak dosya).
        let resmi = a.duzen?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == "resmi"
        let data: Data
        switch tur {
        case "docx": data = OfisOlusturucu.docx(i, resmi: resmi)
        case "xlsx":
            guard let t = i.tablo else { throw IndirmeHatasi.metin("XLSX için table.columns ve table.rows gerekli.") }
            data = ExcelOlusturucu.xlsx(t)
        case "pptx": data = OfisOlusturucu.pptx(i)
        case "pdf": data = await Task.detached(priority: .userInitiated) { OfisOlusturucu.pdf(i, resmi: resmi) }.value
        default: data = try OfisOlusturucu.metin(i, tur: tur)
        }
        var name = IndirmeYoneticisi.dosyaAdi(a.dosyaAdi)
        if !name.lowercased().hasSuffix(".\(tur)") { name += ".\(tur)" }
        let url = IndirmeYoneticisi.klasor.appending(path: UUID().uuidString + "-" + name)
        try data.write(to: url, options: .atomic)
        IndirmeYoneticisi.ortak.yerelDosyaEkle(url: url, gorunenAd: name)
        EkDefteri.ortak.ekle(MesajEki(tur: .dosya(url: url, ad: name)))
        return "\(tur.uppercased()) dosyası oluşturuldu: \(name). Özgün bir belge eklenmişse onun üzerine yazılmadı; bu yeni kopyadır. Kullanıcı mesajdaki dosya kartından açıp paylaşabilir."
    }
}
