import CoreGraphics
import Foundation

/// Asgari DOCX / XLSX / PPTX yazıcıları (`ZipYazici` üzerinde).
enum OfficeYazici {

    static let xmlBaslik = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"

    // MARK: DOCX

    struct DocxResim {
        let veri: Data
        let uzanti: String       // jpg | png
        let genislikPx: Int
        let yukseklikPx: Int
    }

    enum DocxOge {
        case baslik(Int, String)
        case paragraf(String)
        case madde(String)
        case resim(DocxResim)
        case sayfaSonu
    }

    static func docx(_ ogeler: [DocxOge], baslik: String) -> Data {
        var z = ZipYazici()
        z.ekle("[Content_Types].xml", metin: xmlBaslik + """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="jpg" ContentType="image/jpeg"/><Default Extension="png" ContentType="image/png"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/></Types>
        """)
        z.ekle("_rels/.rels", metin: xmlBaslik + """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>
        """)
        z.ekle("docProps/core.xml", metin: xmlBaslik + """
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>\(XMLYardimcisi.kacis(baslik))</dc:title><dc:creator>Kâğıt</dc:creator></cp:coreProperties>
        """)
        z.ekle("word/styles.xml", metin: xmlBaslik + stilXML)

        var iliskiler = "<Relationship Id=\"rIdStil\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        var govde = ""
        var resimNo = 0
        let enEMU = 6_100_000.0, boyEMU = 8_000_000.0   // metin alanı: ~16,9 x 22,2 cm
        for oge in ogeler {
            switch oge {
            case .baslik(let n, let t):
                govde += "<w:p><w:pPr><w:pStyle w:val=\"Heading\(min(max(n, 1), 3))\"/></w:pPr>\(kosu(t))</w:p>"
            case .paragraf(let t):
                govde += "<w:p>\(kosu(t))</w:p>"
            case .madde(let t):
                govde += "<w:p><w:pPr><w:pStyle w:val=\"ListParagraph\"/></w:pPr>\(kosu("• " + t))</w:p>"
            case .sayfaSonu:
                govde += "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>"
            case .resim(let r):
                resimNo += 1
                let dosya = "img\(resimNo).\(r.uzanti)"
                z.ekle("word/media/\(dosya)", r.veri, sakla: true)
                iliskiler += "<Relationship Id=\"rIdR\(resimNo)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(dosya)\"/>"
                var cx = Double(r.genislikPx) * 9525 * 0.75, cy = Double(r.yukseklikPx) * 9525 * 0.75   // 96 dpi
                let o = min(1, enEMU / cx, boyEMU / cy)
                cx *= o; cy *= o
                govde += resimXML(no: resimNo, cx: Int(cx), cy: Int(cy), dosya: dosya)
            }
        }
        if govde.isEmpty { govde = "<w:p/>" }
        z.ekle("word/_rels/document.xml.rels", metin: xmlBaslik + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(iliskiler)</Relationships>")
        z.ekle("word/document.xml", metin: xmlBaslik + """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>\(govde)<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>
        """)
        return z.bitir()
    }

    private static func kosu(_ t: String) -> String {
        "<w:r><w:t xml:space=\"preserve\">\(XMLYardimcisi.kacis(t))</w:t></w:r>"
    }

    private static func resimXML(no: Int, cx: Int, cy: Int, dosya: String) -> String {
        """
        <w:p><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(cx)" cy="\(cy)"/><wp:docPr id="\(no)" name="Resim \(no)"/><wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="\(no)" name="\(dosya)"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="rIdR\(no)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
        """
    }

    private static let stilXML = """
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/><w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="tr-TR"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="360" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="36"/><w:szCs w:val="36"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="280" w:after="100"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="30"/><w:szCs w:val="30"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="200" w:after="80"/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:sz w:val="26"/><w:szCs w:val="26"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:after="60"/><w:ind w:left="567" w:hanging="283"/></w:pPr></w:style></w:styles>
    """

    // MARK: XLSX

    enum Hucre {
        case metin(String)
        case sayi(Double)
    }

    struct Sayfa {
        var ad: String
        var satirlar: [[Hucre?]]
    }

    static func sutunHarfi(_ i: Int) -> String {
        var n = i + 1, s = ""
        while n > 0 { let r = (n - 1) % 26; s = String(UnicodeScalar(UInt8(65 + r))) + s; n = (n - 1) / 26 }
        return s
    }

    static func sayfaAdi(_ ad: String, mevcut: [String]) -> String {
        var t = ad.components(separatedBy: CharacterSet(charactersIn: "[]:*?/\\")).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if t.isEmpty { t = "Sayfa" }
        t = String(t.prefix(31))
        var aday = t, k = 2
        while mevcut.contains(where: { $0.lowercased() == aday.lowercased() }) {
            let ek = " (\(k))"
            aday = String(t.prefix(31 - ek.count)) + ek
            k += 1
        }
        return aday
    }

    static func xlsx(_ sayfalar: [Sayfa]) -> Data {
        let sayfalar = sayfalar.isEmpty ? [Sayfa(ad: "Sayfa1", satirlar: [])] : sayfalar
        var z = ZipYazici()
        var tipler = "", iliskiler = "", sayfaListesi = ""
        for (i, s) in sayfalar.enumerated() {
            let n = i + 1
            tipler += "<Override PartName=\"/xl/worksheets/sheet\(n).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
            iliskiler += "<Relationship Id=\"rId\(n)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(n).xml\"/>"
            sayfaListesi += "<sheet name=\"\(XMLYardimcisi.kacis(s.ad))\" sheetId=\"\(n)\" r:id=\"rId\(n)\"/>"
            var xml = xmlBaslik + "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>"
            for (r, satir) in s.satirlar.enumerated() {
                var hucreler = ""
                for (c, h) in satir.enumerated() {
                    guard let h else { continue }
                    let adres = "\(sutunHarfi(c))\(r + 1)"
                    switch h {
                    case .metin(let t):
                        hucreler += "<c r=\"\(adres)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(XMLYardimcisi.kacis(t))</t></is></c>"
                    case .sayi(let d):
                        hucreler += "<c r=\"\(adres)\"><v>\(d)</v></c>"
                    }
                }
                if !hucreler.isEmpty { xml += "<row r=\"\(r + 1)\">\(hucreler)</row>" }
            }
            xml += "</sheetData></worksheet>"
            z.ekle("xl/worksheets/sheet\(n).xml", metin: xml)
        }
        let stilNo = sayfalar.count + 1
        iliskiler += "<Relationship Id=\"rId\(stilNo)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        z.ekle("[Content_Types].xml", metin: xmlBaslik + """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\(tipler)</Types>
        """)
        z.ekle("_rels/.rels", metin: xmlBaslik + """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
        """)
        z.ekle("xl/workbook.xml", metin: xmlBaslik + """
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>\(sayfaListesi)</sheets></workbook>
        """)
        z.ekle("xl/_rels/workbook.xml.rels", metin: xmlBaslik + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(iliskiler)</Relationships>")
        z.ekle("xl/styles.xml", metin: xmlBaslik + """
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
        """)
        return z.bitir()
    }

    // MARK: PPTX

    struct Slayt {
        let jpeg: Data
        let genislikPx: Int
        let yukseklikPx: Int
    }

    static func pptx(_ slaytlar: [Slayt]) -> Data {
        let ns = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\""
        let grup = "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"
        let ilk = slaytlar.first
        let oran0 = ilk.map { Double($0.genislikPx) / Double(max($0.yukseklikPx, 1)) } ?? (16.0 / 9.0)
        // Yatay sayfa: 13,33 inç genişlik; dikey sayfa: 7,5 inç yükseklik (PowerPoint sınırları içinde)
        let sw = oran0 >= 1 ? 12_192_000 : Int(6_858_000 * oran0)
        let sh = oran0 >= 1 ? Int(12_192_000 / oran0) : 6_858_000
        var z = ZipYazici()
        var tipler = "", sunumIliski = "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"slideMasters/slideMaster1.xml\"/>"
        var slaytKimlikleri = ""
        for (i, s) in slaytlar.enumerated() {
            let n = i + 1
            tipler += "<Override PartName=\"/ppt/slides/slide\(n).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>"
            sunumIliski += "<Relationship Id=\"rId\(n + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide\(n).xml\"/>"
            slaytKimlikleri += "<p:sldId id=\"\(255 + n)\" r:id=\"rId\(n + 1)\"/>"
            z.ekle("ppt/media/image\(n).jpg", s.jpeg, sakla: true)
            let oran = Double(s.genislikPx) / Double(max(s.yukseklikPx, 1))
            var w = sw, h = Int(Double(sw) / oran)
            if h > sh { h = sh; w = Int(Double(sh) * oran) }
            let x = (sw - w) / 2, y = (sh - h) / 2
            z.ekle("ppt/slides/slide\(n).xml", metin: xmlBaslik + """
            <p:sld \(ns)><p:cSld><p:spTree>\(grup)<p:pic><p:nvPicPr><p:cNvPr id="2" name="Sayfa \(n)"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed="rId2"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x="\(x)" y="\(y)"/><a:ext cx="\(w)" cy="\(h)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>
            """)
            z.ekle("ppt/slides/_rels/slide\(n).xml.rels", metin: xmlBaslik + """
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image\(n).jpg"/></Relationships>
            """)
        }
        let temaNo = slaytlar.count + 2
        sunumIliski += "<Relationship Id=\"rId\(temaNo)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme\" Target=\"theme/theme1.xml\"/>"
        z.ekle("[Content_Types].xml", metin: xmlBaslik + """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="jpg" ContentType="image/jpeg"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/><Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/><Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>\(tipler)</Types>
        """)
        z.ekle("_rels/.rels", metin: xmlBaslik + """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/></Relationships>
        """)
        z.ekle("ppt/presentation.xml", metin: xmlBaslik + """
        <p:presentation \(ns)><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst>\(slaytKimlikleri)</p:sldIdLst><p:sldSz cx="\(sw)" cy="\(sh)"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>
        """)
        z.ekle("ppt/_rels/presentation.xml.rels", metin: xmlBaslik + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(sunumIliski)</Relationships>")
        z.ekle("ppt/slideMasters/slideMaster1.xml", metin: xmlBaslik + """
        <p:sldMaster \(ns)><p:cSld><p:spTree>\(grup)</p:spTree></p:cSld><p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/><p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>
        """)
        z.ekle("ppt/slideMasters/_rels/slideMaster1.xml.rels", metin: xmlBaslik + """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/></Relationships>
        """)
        z.ekle("ppt/slideLayouts/slideLayout1.xml", metin: xmlBaslik + """
        <p:sldLayout \(ns) type="blank" preserve="1"><p:cSld name="Boş"><p:spTree>\(grup)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>
        """)
        z.ekle("ppt/slideLayouts/_rels/slideLayout1.xml.rels", metin: xmlBaslik + """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/></Relationships>
        """)
        z.ekle("ppt/theme/theme1.xml", metin: xmlBaslik + tema)
        return z.bitir()
    }

    private static var tema: String {
        let dolgu = String(repeating: "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>", count: 3)
        let cizgi = String(repeating: "<a:ln w=\"9525\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln>", count: 3)
        let efekt = String(repeating: "<a:effectStyle><a:effectLst/></a:effectStyle>", count: 3)
        let yaziTipi = "<a:latin typeface=\"Calibri\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/>"
        return """
        <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Kagit"><a:themeElements><a:clrScheme name="Kagit"><a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1><a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="1F2937"/></a:dk2><a:lt2><a:srgbClr val="F3F4F6"/></a:lt2><a:accent1><a:srgbClr val="2563EB"/></a:accent1><a:accent2><a:srgbClr val="DC2626"/></a:accent2><a:accent3><a:srgbClr val="16A34A"/></a:accent3><a:accent4><a:srgbClr val="D97706"/></a:accent4><a:accent5><a:srgbClr val="7C3AED"/></a:accent5><a:accent6><a:srgbClr val="0891B2"/></a:accent6><a:hlink><a:srgbClr val="2563EB"/></a:hlink><a:folHlink><a:srgbClr val="7C3AED"/></a:folHlink></a:clrScheme><a:fontScheme name="Kagit"><a:majorFont>\(yaziTipi)</a:majorFont><a:minorFont>\(yaziTipi)</a:minorFont></a:fontScheme><a:fmtScheme name="Kagit"><a:fillStyleLst>\(dolgu)</a:fillStyleLst><a:lnStyleLst>\(cizgi)</a:lnStyleLst><a:effectStyleLst>\(efekt)</a:effectStyleLst><a:bgFillStyleLst>\(dolgu)</a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>
        """
    }
}
