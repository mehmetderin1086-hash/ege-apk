import SwiftUI
import CoreGraphics
import CoreText
import UniformTypeIdentifiers

/// Öğrenci kütüphane kartı basımı: her öğrenci için ad, sınıf, okul numarası ve
/// barkod içeren kart; A4 sayfada 2×5 düzeninde PDF olarak çıkar. Kiosk modunda
/// öğrenci kartını okutarak hızlı ödünç almak için kullanılır.
struct StudentCardsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedClass = "Tümü"
    @State private var isExporting = false
    @State private var pdfData = Data()
    @State private var isPreparing = false

    private var classNames: [String] { ["Tümü"] + StudentStore.classNames() }
    private var students: [Student] {
        selectedClass == "Tümü" ? StudentStore.all() : StudentStore.students(in: selectedClass)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Sınıf", selection: $selectedClass) {
                        ForEach(classNames, id: \.self) { Text($0).tag($0) }
                    }
                    LabeledContent("Kart sayısı", value: "\(students.count)")
                } footer: {
                    Text("Kart barkodu öğrencinin sabit kimliğini taşır; ad/sınıf/numara görünürlüğü Raporlar > Baskı Profilleri üzerinden seçilir.")
                }

                Section("Öğrenciler") {
                    if students.isEmpty {
                        Text("Bu sınıfta öğrenci yok.").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(students.prefix(50)) { student in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(student.name).font(.subheadline.weight(.medium))
                            Text([student.className, student.number.isEmpty ? nil : "No: \(student.number)"]
                                .compactMap { $0 }
                                .joined(separator: " • "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if students.count > 50 {
                        Text("… ve \(students.count - 50) öğrenci daha (PDF'te tamamı yer alır)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Öğrenci Kartları")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        prepare()
                    } label: {
                        Label(isPreparing ? "Hazırlanıyor…" : "PDF", systemImage: "doc.richtext")
                    }
                    .disabled(students.isEmpty || isPreparing)
                }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: PDFDocumentFile(data: pdfData),
                contentType: .pdf,
                defaultFilename: "Ogrenci-Kartlari"
            ) { _ in }
        }
    }

    private func prepare() {
        isPreparing = true
        let cards = students.map {
            StudentCardBuilder.CardInfo(
                name: $0.name,
                className: $0.className,
                number: $0.number,
                barcodeValue: StudentCardBuilder.barcodeValue(for: $0)
            )
        }
        Task { @MainActor in
            defer { isPreparing = false }
            pdfData = await Task.detached(priority: .userInitiated) {
                StudentCardBuilder.build(cards)
            }.value
            isExporting = true
        }
    }
}

/// Öğrenci kartı PDF üretici (A4, 2 sütun × 5 satır).
nonisolated enum StudentCardBuilder {
    struct CardInfo: Sendable {
        let name: String
        let className: String
        let number: String
        let barcodeValue: String
    }

    private static let pageWidth: CGFloat = 595
    private static let pageHeight: CGFloat = 842
    private static let margin: CGFloat = 30
    private static let columns = 2
    private static let rows = 5

    /// Kart barkodu öğrenci UUID'sini taşır; aynı adlı/numaralı öğrencilere ayrı kimlik verir.
    static func barcodeValue(for student: Student) -> String {
        "OGRID" + student.id.uuidString.replacingOccurrences(of: "-", with: "")
    }

    static func build(_ cards: [CardInfo], profile: LibraryPrintProfile = LibraryPrintProfile.load(LibraryPrintProfile.studentKey)) -> Data {
        let margin = profile.margin
        let offset = profile.offset
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { return Data() }

        let cellWidth = (pageWidth - margin * 2) / CGFloat(columns)
        let cellHeight = (pageHeight - margin * 2) / CGFloat(rows)
        let perPage = columns * rows

        var index = 0
        while index < cards.count {
            context.beginPDFPage(nil)
            if index == 0 { profile.drawRuler(in: context, pageHeight: pageHeight) }
            for slot in 0..<perPage where index < cards.count {
                let col = slot % columns
                let row = slot / columns
                let rect = CGRect(
                    x: margin + CGFloat(col) * cellWidth + offset.width,
                    y: pageHeight - margin - CGFloat(row + 1) * cellHeight - offset.height,
                    width: cellWidth,
                    height: cellHeight
                )
                draw(cards[index], in: rect, context: context, profile: profile)
                index += 1
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    private static func draw(_ card: CardInfo, in rect: CGRect, context: CGContext, profile: LibraryPrintProfile) {
        let inner = rect.insetBy(dx: 8, dy: 8)
        context.setStrokeColor(CGColor(gray: 0.6, alpha: 1))
        context.setLineWidth(1)
        context.stroke(inner)

        var cursor = inner.maxY - 18
        cursor = text("KÜTÜPHANE KARTI", size: 8, bold: true, x: inner.minX + 12, y: cursor, context: context)
        cursor -= 6
        let shownName = profile.showStudentName ? card.name : card.name.split(separator: " ").compactMap { $0.first.map { String($0) + "." } }.joined(separator: " ")
        cursor = text(shownName, size: 13, bold: true, x: inner.minX + 12, y: cursor, context: context, maxWidth: inner.width - 24)
        if profile.showStudentClass { cursor = text(card.className, size: 10, bold: false, x: inner.minX + 12, y: cursor, context: context, maxWidth: inner.width - 24) }
        if profile.showStudentNumber, !card.number.isEmpty {
            cursor = text("No: \(card.number)", size: 9, bold: false, x: inner.minX + 12, y: cursor, context: context, maxWidth: inner.width - 24)
        }

        if let image = InternalBarcode.barcodeImage(for: card.barcodeValue) {
            let height: CGFloat = 28
            let width = min(inner.width - 24, height * CGFloat(image.width) / CGFloat(image.height))
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: inner.minX + 12, y: inner.minY + 10, width: width, height: height))
        }
    }

    @discardableResult
    private static func text(
        _ string: String, size: CGFloat, bold: Bool, x: CGFloat, y: CGFloat, context: CGContext,
        maxWidth: CGFloat = 240
    ) -> CGFloat {
        let font = CTFontCreateWithName((bold ? "HelveticaNeue-Bold" : "HelveticaNeue") as CFString, size, nil)
        let attributes = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1)
        ] as CFDictionary
        guard let attributed = CFAttributedStringCreate(nil, string as CFString, attributes) else {
            return y - size - 3
        }
        let line = CTLineCreateWithAttributedString(attributed)
        let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        let fitted = CTLineCreateTruncatedLine(line, Double(maxWidth), .end, token) ?? line
        context.textPosition = CGPoint(x: x, y: y - size)
        CTLineDraw(fitted, context)
        return y - size - 5
    }
}
