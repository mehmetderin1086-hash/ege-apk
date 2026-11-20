import Foundation
import CoreGraphics
import CoreText
import UniformTypeIdentifiers
import SwiftUI

/// Seçili kitaplar için A4 sayfada etiket grid'i üretir: yer numarası (kategori +
/// yazar baş harfi), kitap adı, demirbaş kodu ve ISBN barkodu. Yazdırıp kitap
/// sırtına/iç kapağına yapıştırmak için tasarlandı.
nonisolated enum SpineLabelBuilder {
    struct LabelInfo: Sendable {
        let callNumber: String
        let title: String
        let accessionCode: String
        let barcodeValue: String
        /// Renk bandı için kategori
        var category: String = ""
        /// Büyük şablonda QR (kitabı uygulamada açar)
        var bookID: UUID? = nil
    }

    private static let pageWidth: CGFloat = 595
    private static let pageHeight: CGFloat = 842
    private static let margin: CGFloat = 24
    static func callNumber(category: String?, author: String, location: String? = nil) -> String {
        // Yer numarası Dewey biçimindeyse standart yer numarası: "813.4 / ALİ"
        if let dewey = EtiketRengi.dewey(location) {
            let authorPart = author.split(separator: " ").last.map { String($0.prefix(3)).uppercased(with: Locale(identifier: "tr_TR")) } ?? "___"
            return "\(dewey) / \(authorPart)"
        }
        return legacyCallNumber(category: category, author: author)
    }

    private static func legacyCallNumber(category: String?, author: String) -> String {
        let categoryPart = (category?.trimmingCharacters(in: .whitespaces))
            .flatMap { $0.isEmpty ? nil : $0.prefix(3).uppercased(with: Locale(identifier: "tr_TR")) } ?? "GEN"
        let authorPart = author
            .split(separator: " ")
            .last
            .map { String($0.prefix(3)).uppercased(with: Locale(identifier: "tr_TR")) } ?? "___"
        return "\(categoryPart) / \(authorPart)"
    }

    static func build(_ labels: [LabelInfo], template: EtiketSablonu = EtiketSablonu.kayitli,
                      profile: LibraryPrintProfile = LibraryPrintProfile.load(LibraryPrintProfile.labelsKey)) -> Data {
        let margin = profile.margin
        let offset = profile.offset
        let columns = template.izgara.sutun
        let rows = template.izgara.satir
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data),
              var box = Optional(CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { return Data() }

        let cellWidth = (pageWidth - margin * 2) / CGFloat(columns)
        let cellHeight = (pageHeight - margin * 2) / CGFloat(rows)
        let perPage = columns * rows

        var index = 0
        while index < labels.count {
            context.beginPDFPage(nil)
            if index == 0 { profile.drawRuler(in: context, pageHeight: pageHeight) }
            for slot in 0..<perPage where index < labels.count {
                let col = slot % columns
                let row = slot / columns
                let x = margin + CGFloat(col) * cellWidth + offset.width
                let yTop = pageHeight - margin - CGFloat(row) * cellHeight - offset.height
                let rect = CGRect(x: x, y: yTop - cellHeight, width: cellWidth, height: cellHeight)
                switch template {
                case .standart: draw(labels[index], in: rect, context: context)
                case .sirt: drawSpine(labels[index], in: rect, context: context)
                case .buyuk: drawLarge(labels[index], in: rect, context: context)
                }
                index += 1
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    private static func draw(_ label: LabelInfo, in rect: CGRect, context: CGContext) {
        context.setStrokeColor(CGColor(gray: 0.7, alpha: 1))
        context.setLineWidth(0.5)
        context.stroke(rect.insetBy(dx: 3, dy: 3))

        var cursor = rect.maxY - 10

        cursor = drawText(label.callNumber, size: 11, bold: true, x: rect.minX + 8, y: cursor, maxWidth: rect.width - 16, context: context)
        cursor = drawText(label.title, size: 8, bold: false, x: rect.minX + 8, y: cursor - 2, maxWidth: rect.width - 16, context: context, maxLines: 2)

        if !label.accessionCode.isEmpty {
            cursor = drawText(label.accessionCode, size: 7, bold: false, x: rect.minX + 8, y: cursor - 2, maxWidth: rect.width - 16, context: context)
        }

        if !label.barcodeValue.isEmpty, let image = InternalBarcode.barcodeImage(for: label.barcodeValue) {
            let barcodeHeight: CGFloat = 20
            let barcodeWidth = min(rect.width - 16, barcodeHeight * CGFloat(image.width) / CGFloat(image.height))
            let barcodeRect = CGRect(
                x: rect.minX + 8,
                y: rect.minY + 4,
                width: barcodeWidth,
                height: barcodeHeight
            )
            context.interpolationQuality = .none
            context.draw(image, in: barcodeRect)
        }
    }

    /// Sırt etiketi: üstte kategori renk bandı, iri yer numarası, altta kısa ad.
    private static func drawSpine(_ label: LabelInfo, in rect: CGRect, context: CGContext) {
        let inner = rect.insetBy(dx: 3, dy: 3)
        context.setStrokeColor(CGColor(gray: 0.7, alpha: 1))
        context.setLineWidth(0.5)
        context.stroke(inner)
        let band = CGRect(x: inner.minX, y: inner.maxY - 9, width: inner.width, height: 9)
        context.setFillColor(EtiketRengi.renk(for: label.category))
        context.fill(band)
        let parts = label.callNumber.components(separatedBy: " / ")
        var cursor = band.minY - 2
        cursor = drawText(parts.first ?? label.callNumber, size: 12, bold: true, x: inner.minX + 5, y: cursor,
                          maxWidth: inner.width - 10, context: context)
        if parts.count > 1 {
            cursor = drawText(parts[1], size: 11, bold: true, x: inner.minX + 5, y: cursor, maxWidth: inner.width - 10, context: context)
        }
        _ = drawText(label.title, size: 6, bold: false, x: inner.minX + 5, y: cursor - 1, maxWidth: inner.width - 10, context: context)
    }

    /// Büyük etiket: standart içerik + sağda QR (kitabı uygulamada açar) + renk bandı.
    private static func drawLarge(_ label: LabelInfo, in rect: CGRect, context: CGContext) {
        let inner = rect.insetBy(dx: 4, dy: 4)
        context.setFillColor(EtiketRengi.renk(for: label.category))
        context.fill(CGRect(x: inner.minX, y: inner.minY, width: 6, height: inner.height))
        let qrSize = min(inner.height - 12, inner.width * 0.34)
        if let id = label.bookID, let qr = KitapQR.goruntu(KitapQR.url(for: id).absoluteString) {
            context.interpolationQuality = .none
            context.draw(qr, in: CGRect(x: inner.maxX - qrSize - 4, y: inner.midY - qrSize / 2, width: qrSize, height: qrSize))
        }
        let textRect = CGRect(x: inner.minX + 8, y: inner.minY, width: inner.width - qrSize - 16, height: inner.height)
        draw(label, in: textRect, context: context)
    }

    @discardableResult
    private static func drawText(
        _ text: String, size: CGFloat, bold: Bool, x: CGFloat, y: CGFloat, maxWidth: CGFloat,
        context: CGContext, maxLines: Int = 1
    ) -> CGFloat {
        let font = CTFontCreateWithName((bold ? "HelveticaNeue-Bold" : "HelveticaNeue") as CFString, size, nil)
        let attributes = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1)
        ] as CFDictionary
        guard let attributed = CFAttributedStringCreate(nil, text as CFString, attributes) else {
            return y - size - 2
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: x, y: 0, width: maxWidth, height: size * CGFloat(maxLines) * 1.3), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)

        context.saveGState()
        context.translateBy(x: 0, y: y - size * 1.1 * CGFloat(maxLines))
        CTFrameDraw(frame, context)
        context.restoreGState()

        return y - size * 1.3 * CGFloat(maxLines) - 2
    }
}
