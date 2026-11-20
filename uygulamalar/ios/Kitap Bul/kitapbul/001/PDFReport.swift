import Foundation
import CoreGraphics
import CoreText
import UniformTypeIdentifiers
import SwiftUI

/// Basit, imzaya uygun PDF tutanak üretici (sayım ve ödünç raporları için).
/// A4 sayfa düzeni, başlık, tarih, tablo satırları ve imza alanı içerir.
nonisolated enum PDFReportBuilder {
    private static let pageWidth: CGFloat = 595   // A4 @72dpi
    private static let pageHeight: CGFloat = 842
    private static let margin: CGFloat = 40

    struct Section {
        let title: String
        /// Her satır: sol taraf (açıklama) ve sağ taraf (değer)
        let rows: [(String, String)]
    }

    /// - Parameter signatures: İmza alanları (ör. sayım komisyonu üyeleri). Boşsa tek "Sayım Görevlisi" alanı.
    static func build(title: String, subtitle: String, sections: [Section], signatures: [String] = []) -> Data {
        let data = NSMutableData()
        // Yerel kopya: paylaşılan statik değişkeni `&` ile vermek, aynı anda iki
        // arka plan raporu üretilirken veri yarışı olurdu.
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(
                consumer: consumer,
                mediaBox: &mediaBox,
                nil
              ) else { return Data() }

        var cursor = pageHeight - margin
        context.beginPDFPage(nil)
        cursor = draw(title, size: 18, bold: true, at: cursor, in: context)
        cursor -= 6
        cursor = draw(subtitle, size: 10, bold: false, at: cursor, in: context)
        cursor -= 14

        for section in sections {
            let contentWidth = pageWidth - margin * 2
            let sectionHeight = section.rows.reduce(CGFloat(lines(section.title, size: 13, bold: true, width: contentWidth).count) * 19 + 16) { height, row in
                let leftWidth = row.1.isEmpty ? contentWidth : contentWidth * 0.64
                let rightWidth = contentWidth - leftWidth - 12
                return height + CGFloat(max(lines(row.0, size: 10, bold: false, width: leftWidth).count,
                    row.1.isEmpty ? 0 : lines(row.1, size: 10, bold: false, width: rightWidth).count)) * 14 + 2
            }
            if cursor < margin + 80 || (sectionHeight <= pageHeight - margin * 2 && cursor - sectionHeight < margin) {
                context.endPDFPage()
                context.beginPDFPage(nil)
                cursor = pageHeight - margin
            }
            cursor = draw(section.title, size: 13, bold: true, at: cursor, in: context)
            cursor -= 4

            if section.rows.isEmpty {
                cursor = draw("(kayıt yok)", size: 10, bold: false, at: cursor, in: context)
            }
            for row in section.rows {
                let leftWidth = row.1.isEmpty ? pageWidth - margin * 2 : (pageWidth - margin * 2) * 0.64
                let rightWidth = pageWidth - margin * 2 - leftWidth - 12
                let leftLines = lines(row.0, size: 10, bold: false, width: leftWidth)
                let rightLines = row.1.isEmpty ? [] : lines(row.1, size: 10, bold: false, width: rightWidth)
                let lineCount = max(leftLines.count, rightLines.count)
                let rowHeight = CGFloat(lineCount) * 14 + 2
                if rowHeight <= pageHeight - margin * 2, cursor - rowHeight < margin {
                    context.endPDFPage()
                    context.beginPDFPage(nil)
                    cursor = pageHeight - margin
                    cursor = draw(String(section.title.prefix(160)) + " (devam)", size: 13, bold: true, at: cursor, in: context) - 4
                }
                for index in 0..<lineCount {
                    if cursor < margin + 14 {
                        context.endPDFPage(); context.beginPDFPage(nil); cursor = pageHeight - margin
                        cursor = draw(String(section.title.prefix(160)) + " (devam)", size: 13, bold: true, at: cursor, in: context) - 4
                    }
                    if leftLines.indices.contains(index) {
                        context.textPosition = CGPoint(x: margin, y: cursor - 10)
                        CTLineDraw(leftLines[index], context)
                    }
                    if rightLines.indices.contains(index) {
                        let width = CTLineGetTypographicBounds(rightLines[index], nil, nil, nil)
                        context.textPosition = CGPoint(x: pageWidth - margin - CGFloat(width), y: cursor - 10)
                        CTLineDraw(rightLines[index], context)
                    }
                    cursor -= 14
                }
                cursor -= 2
            }
            cursor -= 12
        }

        // İmza alanı
        if cursor < margin + 90 {
            context.endPDFPage()
            context.beginPDFPage(nil)
            cursor = pageHeight - margin
        }
        cursor -= 30
        if signatures.isEmpty {
            _ = draw("Sayım Görevlisi: ............................        İmza: ............................",
                     size: 10, bold: false, at: cursor, in: context)
        } else {
            for signature in signatures {
                if cursor < margin + 30 {
                    context.endPDFPage()
                    context.beginPDFPage(nil)
                    cursor = pageHeight - margin
                }
                cursor = draw("\(signature): ....................................        İmza: ....................",
                              size: 10, bold: false, at: cursor, in: context)
                cursor -= 18
            }
        }

        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private static func draw(
        _ text: String, size: CGFloat, bold: Bool, at y: CGFloat, in context: CGContext
    ) -> CGFloat {
        var cursor = y
        for line in lines(text, size: size, bold: bold, width: pageWidth - margin * 2) {
            if cursor < margin + size + 6 {
                context.endPDFPage(); context.beginPDFPage(nil); cursor = pageHeight - margin
            }
            context.textPosition = CGPoint(x: margin, y: cursor - size)
            CTLineDraw(line, context); cursor -= size + 6
        }
        return cursor
    }

    private static func lines(_ text: String, size: CGFloat, bold: Bool, width: CGFloat) -> [CTLine] {
        let font = CTFontCreateWithName(
            (bold ? "HelveticaNeue-Bold" : "HelveticaNeue") as CFString, size, nil
        )
        let attributes = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1)
        ] as CFDictionary
        guard let attributed = CFAttributedStringCreate(nil, text as CFString, attributes) else {
            return []
        }
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let length = CFAttributedStringGetLength(attributed)
        var offset = 0, result: [CTLine] = []
        while offset < length {
            let count = max(1, CTTypesetterSuggestLineBreak(typesetter, offset, Double(width)))
            result.append(CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: min(count, length - offset))))
            offset += count
        }
        return result
    }
}

/// PDF dosyasını dışa aktarmak için belge sarmalayıcı.
struct PDFDocumentFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
