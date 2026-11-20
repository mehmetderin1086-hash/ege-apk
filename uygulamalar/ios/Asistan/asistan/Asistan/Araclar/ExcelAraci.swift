import Foundation
import FoundationModels

nonisolated enum ExcelOlusturucu {
    struct Tablo: Equatable { let sutunlar: [String]; let satirlar: [[String]] }

    static func tablo(_ json: String) throws -> Tablo {
        guard json.utf8.count <= 1_000_000,
              let data = json.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawColumns = root["columns"] as? [Any],
              let rawRows = root["rows"] as? [[Any]],
              (1...20).contains(rawColumns.count), rawRows.count <= 500 else {
            throw IndirmeHatasi.metin("Excel tablosu 1–20 sütun, en fazla 500 satır ve 1 MB JSON olmalı.")
        }
        func metin(_ value: Any) -> String {
            if value is NSNull { return "" }
            if let s = value as? String { return String(s.prefix(2_000)) }
            if let n = value as? NSNumber { return n.stringValue }
            return String(String(describing: value).prefix(2_000))
        }
        let columns = rawColumns.map(metin)
        guard columns.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw IndirmeHatasi.metin("Excel sütun adları boş olamaz.")
        }
        let rows = rawRows.map { row in (0..<columns.count).map { $0 < row.count ? metin(row[$0]) : "" } }
        return Tablo(sutunlar: columns, satirlar: rows)
    }

    static func xlsx(_ table: Tablo) -> Data {
        let allRows = [table.sutunlar] + table.satirlar
        var sheet = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"/></sheetViews><sheetFormatPr defaultRowHeight="15"/><sheetData>"#
        for (rowIndex, row) in allRows.enumerated() {
            sheet += "<row r=\"\(rowIndex + 1)\">"
            for (columnIndex, value) in row.enumerated() {
                let ref = columnName(columnIndex) + String(rowIndex + 1)
                let style = rowIndex == 0 ? " s=\"1\"" : ""
                sheet += "<c r=\"\(ref)\" t=\"inlineStr\"\(style)><is><t xml:space=\"preserve\">\(xml(value))</t></is></c>"
            }
            sheet += "</row>"
        }
        sheet += "</sheetData><autoFilter ref=\"A1:\(columnName(max(0, table.sutunlar.count - 1)))\(allRows.count)\"/></worksheet>"
        let files: [(String, String)] = [
            ("[Content_Types].xml", #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>"#),
            ("_rels/.rels", #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>"#),
            ("xl/workbook.xml", #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sonuçlar" sheetId="1" r:id="rId1"/></sheets></workbook>"#),
            ("xl/_rels/workbook.xml.rels", #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>"#),
            ("xl/styles.xml", #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Aptos"/></font><font><b/><sz val="11"/><name val="Aptos"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs></styleSheet>"#),
            ("xl/worksheets/sheet1.xml", sheet)
        ]
        return ZipYazici.olustur(files.map { ($0.0, Data($0.1.utf8)) })
    }

    private static func columnName(_ index: Int) -> String {
        var n = index + 1, result = ""
        while n > 0 { n -= 1; result = String(UnicodeScalar(65 + n % 26)!) + result; n /= 26 }
        return result
    }
    private static func xml(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

nonisolated enum ZipYazici {
    private struct Entry { let name: Data; let crc: UInt32; let size: UInt32; let offset: UInt32 }
    static func olustur(_ files: [(String, Data)]) -> Data {
        var result = Data(), entries: [Entry] = []
        for (nameString, content) in files {
            let name = Data(nameString.utf8), offset = UInt32(result.count), crc = crc32(content), size = UInt32(content.count)
            result.le(UInt32(0x04034b50)); result.le(UInt16(20)); result.le(UInt16(0x0800)); result.le(UInt16(0)); result.le(UInt16(0)); result.le(UInt16(0))
            result.le(crc); result.le(size); result.le(size); result.le(UInt16(name.count)); result.le(UInt16(0)); result.append(name); result.append(content)
            entries.append(Entry(name: name, crc: crc, size: size, offset: offset))
        }
        let centralOffset = UInt32(result.count)
        for e in entries {
            result.le(UInt32(0x02014b50)); result.le(UInt16(20)); result.le(UInt16(20)); result.le(UInt16(0x0800)); result.le(UInt16(0)); result.le(UInt16(0)); result.le(UInt16(0))
            result.le(e.crc); result.le(e.size); result.le(e.size); result.le(UInt16(e.name.count)); result.le(UInt16(0)); result.le(UInt16(0)); result.le(UInt16(0)); result.le(UInt16(0)); result.le(UInt32(0)); result.le(e.offset); result.append(e.name)
        }
        let centralSize = UInt32(result.count) - centralOffset
        result.le(UInt32(0x06054b50)); result.le(UInt16(0)); result.le(UInt16(0)); result.le(UInt16(entries.count)); result.le(UInt16(entries.count)); result.le(centralSize); result.le(centralOffset); result.le(UInt16(0))
        return result
    }
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data { crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0) } }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    nonisolated mutating func le<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}

@MainActor struct ExcelAraci: Tool {
    let name = "excelOlustur"
    let description = "Araştırılmış veya kullanıcıca verilmiş satırlardan gerçek .xlsx Excel dosyası oluşturur. Web verisini kendisi bulmaz; güncel veri gerekiyorsa önce webArastir kullan. Kaynakta bulunmayan satırları uydurma. Dosya İndirmeler ekranına eklenir."
    @Generable struct Arguments {
        @Guide(description: "Dosya adı; .xlsx yazılmasa da eklenir") var dosyaAdi: String
        @Guide(description: "JSON nesnesi: columns dizi sütun adları, rows dizi satırlar. En fazla 20 sütun ve 500 satır") var tabloJSON: String
    }
    func call(arguments a: Arguments) async throws -> String {
        // P4.7: sürüşte dosya üretilmez; kullanıcının asıl isteği ertelenir (yoksa bu özet), araba bağlantısı kesilince hatırlatılır.
        if let not = SurusKipi.ortak.belgeyiErtele(ozet: "\(a.dosyaAdi) adlı Excel tablosunu hazırla") { return not }
        let table = try ExcelOlusturucu.tablo(a.tabloJSON)
        var name = IndirmeYoneticisi.dosyaAdi(a.dosyaAdi)
        if !name.lowercased().hasSuffix(".xlsx") { name += ".xlsx" }
        let unique = UUID().uuidString + "-" + name
        let url = IndirmeYoneticisi.klasor.appending(path: unique)
        try ExcelOlusturucu.xlsx(table).write(to: url, options: .atomic)
        IndirmeYoneticisi.ortak.yerelDosyaEkle(url: url, gorunenAd: name)
        EkDefteri.ortak.ekle(MesajEki(tur: .dosya(url: url, ad: name)))
        return "Excel dosyası oluşturuldu: \(name). \(table.satirlar.count) veri satırı var. Kullanıcı mesajdaki dosya kartından açıp paylaşabilir."
    }
}
