import Testing
import Foundation
import PDFKit
@testable import _01

@MainActor
struct TextbookReadingReportTestleri {
    private let day = Date(timeIntervalSince1970: 1_800_000_000)
    private func scope() -> TextbookReportFilter { TextbookReportFilter(start: day.addingTimeInterval(-100), end: day.addingTimeInterval(100)) }
    private func event(_ book: UUID, _ loan: UUID?, person: String, kind: LoanEvent.Kind, offset: Double = 0,
                       className: String = "7/A", number: String = "101", period: String = "2026 / 1", condition: String? = nil, recipientID: UUID? = nil) -> LoanEvent {
        LoanEvent(bookID: book, bookTitle: "Türkçe Kitabı", person: person, kind: kind, date: day.addingTimeInterval(offset),
            studentID: recipientID ?? loan, classSnapshot: className, loanKind: "textbook", periodSnapshot: period,
            returnedCondition: condition, loanID: loan, studentNumberSnapshot: number)
    }

    @Test func ayniEserinIadesiBaskaOgrencininTesliminiKapatmaz() {
        let book = UUID(), one = UUID(), two = UUID()
        let events = [event(book, one, person: "Ali", kind: .lent, offset: -50), event(book, two, person: "Ali", kind: .lent, offset: -40, number: "102"),
            event(book, two, person: "Ali", kind: .returned, offset: 20, number: "102", condition: "Yıpranmış")]
        let rows = TextbookReportEngine.snapshot(events: events, loans: [], copies: [], filter: scope()).rows
        #expect(rows.count == 2)
        #expect(rows.first { $0.loanID == one }?.status == "Henüz iade edilmedi")
        #expect(rows.first { $0.loanID == one }?.returnedAt == nil)
        #expect(rows.first { $0.loanID == two }?.status == "İade alındı")
        #expect(rows.first { $0.loanID == two }?.condition == "Yıpranmış")
    }

    @Test func tarihselTeslimSinifiNumarasiVeDonemiKorunur() {
        let book = UUID(), loan = UUID()
        let events = [event(book, loan, person: "Ayşe", kind: .lent, offset: -50),
            event(book, loan, person: "Ayşe Yeni Ad", kind: .returned, offset: 20, className: "8/B", number: "999", period: "2027 / 2")]
        var filter = scope(); filter.className = "7/A"; filter.period = "2026 / 1"; filter.query = "101"
        let row = TextbookReportEngine.snapshot(events: events, loans: [], copies: [], filter: filter).rows.first
        #expect(row?.person == "Ayşe")
        #expect(row?.studentNumber == "101")
        #expect(row?.className == "7/A")
        #expect(row?.status == "İade alındı")
        filter.className = "8/B"
        #expect(TextbookReportEngine.snapshot(events: events, loans: [], copies: [], filter: filter).rows.isEmpty)
    }

    @Test func bitisTarihindenSonrakiIadeOncekiDurumuDegistirmez() {
        let book = UUID(), loan = UUID(), closed = UUID(), lost = UUID()
        let events = [event(book, loan, person: "A", kind: .lent, offset: -500), event(book, loan, person: "A", kind: .returned, offset: 200),
            event(book, closed, person: "B", kind: .lent, offset: -500), event(book, closed, person: "B", kind: .returned, offset: -300),
            event(book, lost, person: "C", kind: .lent, offset: -500), event(book, lost, person: "C", kind: .lost, offset: 10)]
        let rows = TextbookReportEngine.snapshot(events: events, loans: [], copies: [], filter: scope()).rows
        #expect(rows.count == 2)
        #expect(rows.first { $0.loanID == loan }?.status == "Henüz iade edilmedi")
        #expect(rows.first { $0.loanID == lost }?.status == "Kayıp bildirildi")
    }

    @Test func kimliksizVeCelisenEskiHareketlerTahminleBirlestirilmez() {
        let book = UUID(), loan = UUID()
        let events = [event(book, nil, person: "Ali", kind: .lent), event(book, nil, person: "Ali", kind: .returned),
            event(book, loan, person: "Ali", kind: .lent), event(UUID(), loan, person: "Ali", kind: .returned)]
        let rows = TextbookReportEngine.snapshot(events: events, loans: [], copies: [], filter: scope()).rows
        #expect(rows.count == 3)
        #expect(rows.allSatisfy { $0.status == "Eşleştirme gerekli" })
        #expect(rows.filter { $0.loanID == nil }.count == 2)
    }

    @Test func farkliKisiNushaVeYanlisSiraliHareketlerFailClosed() {
        let book = UUID(), loan = UUID()
        let delivered = event(book, loan, person: "A", kind: .lent, offset: -50)
        var wrongStudent = event(book, loan, person: "A", kind: .returned, offset: 20, recipientID: UUID())
        for terminal in [wrongStudent] {
            let row = TextbookReportEngine.snapshot(events: [delivered, terminal], loans: [], copies: [], filter: scope()).rows.first
            #expect(row?.status == "Eşleştirme gerekli" && row?.returnedAt == nil)
        }
        wrongStudent.studentID = nil; wrongStudent.memberID = loan
        #expect(TextbookReportEngine.snapshot(events: [delivered, wrongStudent], loans: [], copies: [], filter: scope()).rows.first?.status == "Eşleştirme gerekli")
        var wrongCopy = event(book, loan, person: "A", kind: .returned, offset: 20); wrongCopy.copyID = UUID()
        let cases = [[delivered, wrongCopy], [delivered, event(book, loan, person: "A", kind: .returned, offset: -70)],
                     [delivered, event(book, loan, person: "A", kind: .lent, offset: 10)],
                     [delivered, event(book, loan, person: "A", kind: .returned, offset: 10), event(book, loan, person: "A", kind: .lost, offset: 20)]]
        for events in cases {
            #expect(TextbookReportEngine.snapshot(events: events, loans: [], copies: [], filter: scope()).rows.first?.status == "Eşleştirme gerekli")
        }
    }

    @Test func acikKimlikDuzeltmesiZinciriGecerliKilarTeslimSinifiKorunur() throws {
        let book = UUID(), loanID = UUID(), correctedID = UUID(), copyID = UUID()
        let delivery = event(book, loanID, person: "Eski Ad", kind: .lent, offset: -50)
        var correction = event(book, loanID, person: "Doğru Ad", kind: .identityCorrected, offset: 0, className: "8/B", number: "999", recipientID: correctedID)
        let previous = ActiveLoan(bookID: book, bookTitleSnapshot: delivery.bookTitle, studentName: delivery.person, studentClass: delivery.classSnapshot ?? "", dueDate: day)
        previous.id = loanID; previous.studentID = delivery.studentID; previous.kind = "textbook"
        correction.identityCorrectionBefore = try JSONEncoder().encode(ArchivedLoan(previous)); correction.copyID = copyID
        var returned = event(book, loanID, person: correction.person, kind: .returned, offset: 20, recipientID: correctedID); returned.copyID = copyID
        let row = TextbookReportEngine.snapshot(events: [delivery, correction, returned], loans: [], copies: [], filter: scope()).rows.first
        #expect(row?.status == "İade alındı" && row?.person == "Doğru Ad")
        #expect(row?.className == "7/A" && row?.studentNumber == "101")
        correction.identityCorrectionBefore = nil
        #expect(TextbookReportEngine.snapshot(events: [delivery, correction, returned], loans: [], copies: [], filter: scope()).rows.first?.status == "Eşleştirme gerekli")
    }

    @Test func cizelgeUcBicimdeAyniDetayiVeTurkceMetniTasir() throws {
        let book = UUID(), loan = UUID()
        let events = [event(book, loan, person: "Şule Çığ", kind: .lent), event(book, loan, person: "Şule Çığ", kind: .returned, offset: 10, condition: "Onarım gerekli")]
        let value = TextbookReportEngine.snapshot(events: events, loans: [], copies: [], filter: scope(), now: day)
        #expect(value.rows.allSatisfy { $0.fields.count == TextbookReportEngine.headers.count })
        let csv = String(decoding: ReportTableExporter.csv(value.table), as: UTF8.self)
        let entries = ZIPReader.entries(in: ReportTableExporter.excel(value.table))
        let xml = String(decoding: try #require(entries.first { $0.name == "xl/worksheets/sheet1.xml" }).data, as: UTF8.self)
        let data = PDFReportBuilder.build(title: "DERS KİTABI ÇİZELGESİ", subtitle: "Örnek Okul", sections: value.sections,
            signatures: ["Kütüphane Sorumlusu", "Okul Müdürü"])
        let pdf = try #require(PDFDocument(data: data))
        let pdfText = (pdf.string ?? "").components(separatedBy: .whitespacesAndNewlines).joined()
        for text in ["Şule Çığ", "101", loan.uuidString, "Onarım gerekli", "2026 / 1"] {
            #expect(csv.contains(text)); #expect(xml.contains(text))
            // Dar PDF sütununda uzun UUID satıra bölünebilir; bütün kimlik yine bulunmalı.
            #expect(pdfText.contains(text.components(separatedBy: .whitespacesAndNewlines).joined()))
        }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("PlanQA")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("DersKitabiCizelgesi-Prova.pdf"))
    }

    @Test func iadeTamamlananOkumaDegildirKimlikVeDersKitabiAyriTutulur() {
        let student = UUID(), book = UUID()
        let events = [
            LoanEvent(bookID: book, bookTitle: "A", person: "Ali", kind: .returned, date: day, studentID: student),
            LoanEvent(bookID: UUID(), bookTitle: "B", person: "Ali", kind: .returned, date: day, studentID: student, readingCompleted: false),
            LoanEvent(bookID: UUID(), bookTitle: "C", person: "Ali", kind: .returned, date: day, studentID: student, loanKind: "textbook", readingCompleted: true),
            LoanEvent(bookID: UUID(), bookTitle: "D", person: "Ali", kind: .returned, date: day, readingCompleted: true),
            LoanEvent(bookID: UUID(), bookTitle: "E", person: "Ali", kind: .returned, date: day, studentID: student, readingCompleted: true)]
        #expect(OkumaPuani.puan(for: student, events: events) == 10)
        #expect(OkumaPuani.siralama(events).first?.kitapSayisi == 1)
    }

    @Test func eskiGecmisinEksikOkumaAlaniBilinmiyorOlarakAcilir() throws {
        let event = LoanEvent(bookID: UUID(), bookTitle: "Eser", person: "Ali", kind: .returned, date: day, studentID: UUID())
        let data = try JSONEncoder().encode(event)
        let restored = try JSONDecoder().decode(LoanEvent.self, from: data)
        #expect(restored.readingCompleted == nil)
        #expect(OkumaPuani.siralama([restored]).isEmpty)
    }
}
