import Foundation

nonisolated enum ReportTableExporter {
    /// Hücre türü: metin her zaman metin kalır (formül ön eki korumalı); sayı ve tarih Excel'de gerçek sayı hücresidir.
    enum Cell: Equatable, Sendable {
        case text(String)
        case number(Double)
        case date(Date)

        static func int(_ value: Int) -> Cell { .number(Double(value)) }
        /// CSV ve PDF'te görünen metin; sayı tam sayıysa ondalıksız yazılır.
        var display: String {
            switch self {
            case .text(let value): return value
            case .number(let value): return value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(value)
            case .date(let value): return value.formatted(date: .numeric, time: .shortened)
            }
        }
    }

    struct Sheet: Sendable {
        var name: String
        var rows: [[Cell]]
        init(name: String, rows: [[Cell]]) { self.name = name; self.rows = rows }
        init(name: String, text: [[String]]) { self.init(name: name, rows: text.map { $0.map(Cell.text) }) }
    }

    static func csv(_ rows: [[String]]) -> Data {
        let text = rows.map { row in row.map { value in
            let value = value.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            let protected = ["=", "+", "-", "@"].contains(where: { trimmed.hasPrefix($0) }) ? "'" + value : value
            return "\"" + protected.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }.joined(separator: ";") }.joined(separator: "\r\n")
        return Data(("\u{FEFF}" + text).utf8)
    }

    /// Çok sayfalı tabloyu tek CSV'ye açar: her sayfa için büyük harfli başlık satırı, tablo ve boş satır.
    static func csv(sheets: [Sheet]) -> Data {
        var rows: [[String]] = []
        for (index, sheet) in sheets.enumerated() {
            if index > 0 { rows.append([]) }
            rows.append([sheet.name.uppercased(with: Locale(identifier: "tr_TR"))])
            rows.append(contentsOf: sheet.rows.map { $0.map(\.display) })
        }
        return csv(rows)
    }

    static func excel(_ rows: [[String]]) -> Data {
        excel(sheets: [Sheet(name: "Dönem Raporu", text: rows)])
    }

    static func excel(sheets: [Sheet]) -> Data {
        let sheets = sheets.isEmpty ? [Sheet(name: "Rapor", rows: [])] : sheets
        let hasDates = sheets.contains { $0.rows.contains { $0.contains { if case .date = $0 { return true } else { return false } } } }
        var zip = ZIPWriter()
        let sheetOverrides = sheets.indices.map { "<Override PartName=\"/xl/worksheets/sheet\($0 + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>" }.joined()
        let stylesOverride = hasDates ? "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>" : ""
        zip.add(name: "[Content_Types].xml", text: """
        <?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\(sheetOverrides)\(stylesOverride)</Types>
        """)
        zip.add(name: "_rels/.rels", text: """
        <?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
        """)
        var usedNames = Set<String>()
        let sheetEntries = sheets.enumerated().map { index, sheet in
            "<sheet name=\"\(attribute(uniqueSheetName(sheet.name, used: &usedNames)))\" sheetId=\"\(index + 1)\" r:id=\"rId\(index + 1)\"/>"
        }.joined()
        zip.add(name: "xl/workbook.xml", text: """
        <?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>\(sheetEntries)</sheets></workbook>
        """)
        let sheetRelationships = sheets.indices.map { "<Relationship Id=\"rId\($0 + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0 + 1).xml\"/>" }.joined()
        let stylesRelationship = hasDates ? "<Relationship Id=\"rId\(sheets.count + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>" : ""
        zip.add(name: "xl/_rels/workbook.xml.rels", text: """
        <?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(sheetRelationships)\(stylesRelationship)</Relationships>
        """)
        if hasDates {
            // Tarih hücreleri stil 1'i (gg.aa.yyyy ss:dd) kullanır; sayı değerinin kendisi Excel seri günüdür.
            zip.add(name: "xl/styles.xml", text: """
            <?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1"><numFmt numFmtId="164" formatCode="dd\\.mm\\.yyyy\\ hh:mm"/></numFmts><fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs></styleSheet>
            """)
        }
        for (sheetIndex, sheet) in sheets.enumerated() {
            let body = sheet.rows.enumerated().map { index, row in
                "<row r=\"\(index + 1)\">" + row.enumerated().map { column, cell in
                    let reference = "\(columnName(column))\(index + 1)"
                    switch cell {
                    case .text(let value):
                        return "<c r=\"\(reference)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xml(value))</t></is></c>"
                    case .number(let value):
                        return "<c r=\"\(reference)\" t=\"n\"><v>\(numberText(value))</v></c>"
                    case .date(let value):
                        return "<c r=\"\(reference)\" s=\"1\" t=\"n\"><v>\(excelSerial(value))</v></c>"
                    }
                }.joined() + "</row>"
            }.joined()
            zip.add(name: "xl/worksheets/sheet\(sheetIndex + 1).xml", text: """
            <?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols><col min="1" max="2" width="42" customWidth="1"/><col min="3" max="3" width="28" customWidth="1"/></cols><sheetData>\(body)</sheetData></worksheet>
            """)
        }
        return zip.finalize()
    }

    /// Excel sayfa adı: en çok 31 karakter, `[]:*?/\` yasak, sayfa adları benzersiz.
    private static func uniqueSheetName(_ name: String, used: inout Set<String>) -> String {
        let cleaned = String(String(name.map { "[]:*?/\\".contains($0) ? " " : $0 }).trimmingCharacters(in: .whitespaces).prefix(31))
        let base = cleaned.isEmpty ? "Sayfa" : cleaned
        var candidate = base, counter = 2
        while used.contains(candidate.lowercased()) {
            let suffix = " \(counter)"
            candidate = String(base.prefix(31 - suffix.count)) + suffix
            counter += 1
        }
        used.insert(candidate.lowercased())
        return candidate
    }
    private static func excelSerial(_ date: Date) -> String {
        // 1899-12-30 başlangıçlı seri gün; saat dilimi yerel takvimle gösterilsin diye yerel fark eklenir.
        let local = date.timeIntervalSince1970 + Double(TimeZone.current.secondsFromGMT(for: date))
        return String(format: "%.6f", local / 86400 + 25569)
    }
    private static func columnName(_ index: Int) -> String {
        var result = "", number = index + 1
        while number > 0 { number -= 1; result = String(UnicodeScalar(65 + number % 26)!) + result; number /= 26 }
        return result
    }
    private static func xml(_ value: String) -> String {
        String(value.unicodeScalars.filter { $0.value == 9 || $0.value == 10 || $0.value == 13 || ($0.value >= 32 && $0.value != 0xFFFE && $0.value != 0xFFFF) })
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
    private static func attribute(_ value: String) -> String { xml(value).replacingOccurrences(of: "\"", with: "&quot;") }
    /// XML'e giren sayı metni: ondalık nokta, bilimsel gösterim yok.
    private static func numberText(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(format: "%.10g", value)
    }
}
