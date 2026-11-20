import Foundation

/// XLSX hücresi.
public enum XlsxHucre: Sendable, Hashable {
    case metin(String)
    case kalin(String)
    case sayi(Double)
    case bos
}

/// Tek sayfalı, biçimsiz ama Excel/Numbers'ın açtığı küçük XLSX yazıcı.
public enum XlsxYazici {

    public static func yaz(sayfaAdi: String = "Sayfa1", satirlar: [[XlsxHucre]], sutunGenislikleri: [Double] = []) -> Data {
        var zip = ZipYazici()
        zip.ekle("[Content_Types].xml", metin: """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>
        """)
        zip.ekle("_rels/.rels", metin: """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
        """)
        zip.ekle("xl/workbook.xml", metin: """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="\(kacis(String(sayfaAdi.prefix(31))))" sheetId="1" r:id="rId1"/></sheets></workbook>
        """)
        zip.ekle("xl/_rels/workbook.xml.rels", metin: """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
        """)
        zip.ekle("xl/styles.xml", metin: """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs></styleSheet>
        """)

        var sayfa = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        if !sutunGenislikleri.isEmpty {
            sayfa += "<cols>" + sutunGenislikleri.enumerated().map {
                "<col min=\"\($0.offset + 1)\" max=\"\($0.offset + 1)\" width=\"\($0.element)\" customWidth=\"1\"/>"
            }.joined() + "</cols>"
        }
        sayfa += "<sheetData>"
        for (r, satir) in satirlar.enumerated() {
            sayfa += "<row r=\"\(r + 1)\">"
            for (c, h) in satir.enumerated() {
                let ref = "\(sutunHarfi(c))\(r + 1)"
                switch h {
                case .metin(let s): sayfa += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(kacis(s))</t></is></c>"
                case .kalin(let s): sayfa += "<c r=\"\(ref)\" t=\"inlineStr\" s=\"1\"><is><t xml:space=\"preserve\">\(kacis(s))</t></is></c>"
                case .sayi(let d): sayfa += "<c r=\"\(ref)\"><v>\(BicimYardimci.sayi(d).replacingOccurrences(of: ",", with: "."))</v></c>"
                case .bos: break
                }
            }
            sayfa += "</row>"
        }
        sayfa += "</sheetData></worksheet>"
        zip.ekle("xl/worksheets/sheet1.xml", metin: sayfa)
        return zip.bitir()
    }

    static func sutunHarfi(_ i: Int) -> String {
        var n = i + 1
        var s = ""
        while n > 0 {
            n -= 1
            s = String(UnicodeScalar(UInt8(65 + n % 26))) + s
            n /= 26
        }
        return s
    }

    static func kacis(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
