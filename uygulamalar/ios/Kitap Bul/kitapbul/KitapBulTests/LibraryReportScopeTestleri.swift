import Testing
import Foundation
import SwiftData
import PDFKit
@testable import _01

@MainActor
struct LibraryReportScopeTestleri {
    private let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12))!
    private func book(_ title: String, category: String = "Roman", cabinet: String = "A", shelf: String = "1", quantity: Int = 1) -> CatalogBook {
        CatalogBook(book: Book(title: title, author: "Örnek Yazar", category: category, quantity: quantity, shelf: shelf, cabinet: cabinet))
    }
    private func scope() -> LibraryReportFilter {
        LibraryReportFilter(start: date.addingTimeInterval(-60), end: date.addingTimeInterval(60), academicPeriodLabel: "2026–2027 / 1. dönem")
    }

    @Test func ayniAdliOgretmenVeVeliKimligiVeGecmisTuruAyrilir() throws {
        let title = book("Türkçe eser"), teacher = UUID(), guardian = UUID(), student = UUID()
        let events = [
            LoanEvent(bookID: title.id, bookTitle: title.title, person: "Aynı Ad", kind: .lent, date: date, memberID: teacher, memberKindSnapshot: "teacher"),
            LoanEvent(bookID: title.id, bookTitle: title.title, person: "Aynı Ad", kind: .lent, date: date, memberID: guardian, memberKindSnapshot: "guardian"),
            LoanEvent(bookID: title.id, bookTitle: title.title, person: "Aynı Ad", kind: .lent, date: date, studentID: student, classSnapshot: "7/A"),
            LoanEvent(bookID: title.id, bookTitle: title.title, person: "Aynı Ad", kind: .lent, date: date, identitySource: "manual", classSnapshot: "7/A")]
        var filter = scope(); filter.readerKind = .teacher
        // Üyenin güncel türü değişse de hareketin öğretmen snapshot'ı korunur.
        let teacherEvents = LibraryReportEngine.filteredEvents(events, bookIDs: [title.id], filter: filter, memberKinds: [teacher: "guardian"])
        #expect(teacherEvents.map(\.memberID) == [teacher])
        filter.readerKind = .guardian
        #expect(LibraryReportEngine.filteredEvents(events, bookIDs: [title.id], filter: filter).map(\.memberID) == [guardian])
        filter.readerKind = .student
        #expect(LibraryReportEngine.filteredEvents(events, bookIDs: [title.id], filter: filter).map(\.studentID) == [student])
        filter.readerKind = .manual
        #expect(LibraryReportEngine.filteredEvents(events, bookIDs: [title.id], filter: filter).count == 1)
    }

    @Test func donemKategoriDolapRafVeTarihBirlikteUygulanir() throws {
        let selected = book("Seçilen"), other = book("Başka", category: "Bilim", cabinet: "B", shelf: "2")
        var filter = scope(); filter.category = "Roman"; filter.cabinet = "A"; filter.shelf = "1"
        let events = [
            LoanEvent(bookID: selected.id, bookTitle: selected.title, person: "Örnek", kind: .lent, date: date),
            LoanEvent(bookID: other.id, bookTitle: other.title, person: "Örnek", kind: .lent, date: date),
            LoanEvent(bookID: selected.id, bookTitle: selected.title, person: "Örnek", kind: .lent, date: date.addingTimeInterval(-120))]
        let snapshot = try LibraryReportEngine.snapshot(books: [selected, other], events: events, loans: [], copies: [], reservations: [], filter: filter, now: date)
        #expect(snapshot.books.map(\.id) == [selected.id])
        #expect(snapshot.events.count == 1)
        #expect(snapshot.filter.scopeDescription.contains("2026–2027 / 1. dönem"))
    }

    @Test func ayniAdliOgrencilerVeTarihselSinifBirbirineKarismaz() throws {
        let title = book("Eser"), one = UUID(), two = UUID()
        let events = [
            LoanEvent(bookID: title.id, bookTitle: title.title, person: "Örnek Öğrenci", kind: .returned, date: date, studentID: one, classSnapshot: "7/A", readingCompleted: true),
            LoanEvent(bookID: title.id, bookTitle: title.title, person: "Örnek Öğrenci", kind: .returned, date: date, studentID: two, classSnapshot: "8/B", readingCompleted: true)]
        var filter = scope(); filter.className = "7/A"
        let snapshot = try LibraryReportEngine.snapshot(books: [title], events: events, loans: [], copies: [], reservations: [], filter: filter, now: date)
        #expect(snapshot.events.map(\.studentID) == [one])
        let ranking = snapshot.sections.first { $0.title == "En Çok Okuyan 10 Öğrenci" }?.rows ?? []
        #expect(ranking.count == 1)
        #expect(ranking[0].0.contains(one.uuidString))
        #expect(!ranking[0].0.contains(two.uuidString))
        #expect(ranking[0].0.contains("7/A"))
    }

    @Test func DersKitabiVeUzatmaOkumaSayisiniSisirmez() throws {
        let library = book("Roman"), textbook = book("Ders Kitabı"), student = UUID()
        let events = [
            LoanEvent(bookID: library.id, bookTitle: library.title, person: "Örnek", kind: .lent, date: date, studentID: student, classSnapshot: "7/A", loanKind: "library"),
            LoanEvent(bookID: library.id, bookTitle: library.title, person: "Örnek", kind: .extended, date: date, studentID: student, classSnapshot: "7/A", loanKind: "library"),
            LoanEvent(bookID: textbook.id, bookTitle: textbook.title, person: "Örnek", kind: .lent, date: date, studentID: student, classSnapshot: "7/A", loanKind: "textbook"),
            LoanEvent(bookID: textbook.id, bookTitle: textbook.title, person: "Örnek", kind: .returned, date: date, studentID: student, classSnapshot: "7/A", loanKind: "textbook")]
        let snapshot = try LibraryReportEngine.snapshot(books: [library, textbook], events: events, loans: [], copies: [], reservations: [], filter: scope(), now: date)
        let rows = snapshot.sections.flatMap(\.rows)
        #expect(rows.first { $0.0 == "Ödünç verilen" }?.1 == "2")
        #expect(rows.first { $0.0 == "Süre uzatılan" }?.1 == "1")
        #expect(snapshot.sections.first { $0.title == "En Çok Ödünç Verilen 10 Eser" }?.rows.map { $0.0 } == [library.title])
        #expect(RaporMotoru.enCokOkunanlar(events: events, now: date) == [library.id])
        #expect(OkumaPuani.siralama(events).isEmpty)
    }

    @Test func ayniSnapshotPDFCSVExcelIceriginiVerir() throws {
        let title = book("Şeker, Çığ ve Öğrencinin Öyküsü")
        let snapshot = try LibraryReportEngine.snapshot(books: [title], events: [], loans: [], copies: [], reservations: [], filter: scope(), now: date)
        let document = snapshot.document(title: "KÜTÜPHANE RAPORU", schoolName: "Örnek Okul")
        let expectedRows = document.sections.flatMap { section in section.rows.map { [section.title, $0.0, $0.1] } }
        #expect(Array(document.table.dropFirst(3)) == expectedRows)
        let csv = String(decoding: ReportTableExporter.csv(document.table), as: UTF8.self)
        let entries = ZIPReader.entries(in: ReportTableExporter.excel(document.table))
        let sheet = try #require(entries.first { $0.name == "xl/worksheets/sheet1.xml" })
        let excelXML = String(decoding: sheet.data, as: UTF8.self)
        let pdf = try #require(PDFDocument(data: PDFReportBuilder.build(title: document.title, subtitle: document.subtitle, sections: document.sections)))
        for value in ["Örnek Okul", "2026–2027 / 1. dönem", "Tüm okurlar", "Kayıtlı eser"] {
            #expect(csv.contains(value)); #expect(excelXML.contains(value)); #expect(pdf.string?.contains(value) == true)
        }
    }

    @Test func demirbasGercekNushaKimligiKonumuVeOduncBaginiKorur() {
        let title = book("Aynı eserin nüshaları", quantity: 3)
        let inherited = BookCopy(bookID: title.id, accessionCode: "D-01")
        let moved = BookCopy(bookID: title.id, accessionCode: "D-02", status: "Onarımda", cabinet: "B", shelf: "4")
        let loan = ActiveLoan(bookID: title.id, bookTitleSnapshot: title.title, studentName: "Örnek Okur", studentClass: "7/A", dueDate: date)
        loan.copyID = inherited.id
        let rows = CopyRegisterEngine.rows(books: [title], copies: [inherited, moved], loans: [loan])
        #expect(Set(rows.map(\.id)) == [inherited.id, moved.id])
        #expect(rows.first { $0.id == inherited.id }?.activeLoans.contains(loan.id.uuidString) == true)
        #expect(rows.first { $0.id == inherited.id }?.cabinet == "A")
        #expect(rows.first { $0.id == moved.id }?.cabinet == "B")
        #expect(rows.first { $0.id == moved.id }?.shelf == "4")
        #expect(rows.first { $0.id == moved.id }?.status == "Onarımda")
        #expect(CopyRegisterEngine.untracked(books: [title], copies: [inherited, moved]).first?.count == 1)
        #expect(rows.allSatisfy { $0.fields.count == CopyRegisterEngine.headers.count })
    }

    @Test func ayniEserinIkiFizikselKonumuRaporVeDemirbastaTekNushaSayilir() throws {
        let title = book("Aynı Eser", cabinet: "A", shelf: "1", quantity: 2)
        let copyA = BookCopy(bookID: title.id, accessionCode: "A-01")
        let copyB = BookCopy(bookID: title.id, accessionCode: "B-02", cabinet: "B", shelf: "2")
        let loanA = ActiveLoan(bookID: title.id, bookTitleSnapshot: title.title, studentName: "Örnek A", studentClass: "7/A", dueDate: date)
        let loanB = ActiveLoan(bookID: title.id, bookTitleSnapshot: title.title, studentName: "Örnek B", studentClass: "7/A", dueDate: date)
        loanA.copyID = copyA.id; loanB.copyID = copyB.id
        let events = [
            LoanEvent(bookID: title.id, bookTitle: title.title, person: "Örnek A", kind: .lent, date: date, copyID: copyA.id),
            LoanEvent(bookID: title.id, bookTitle: title.title, person: "Örnek B", kind: .lent, date: date, copyID: copyB.id),
            LoanEvent(bookID: title.id, bookTitle: title.title, person: "Eski kimliksiz hareket", kind: .lent, date: date)]
        var filter = scope(); filter.cabinet = "B"; filter.shelf = "2"
        let snapshot = try LibraryReportEngine.snapshot(books: [title], events: events, loans: [loanA, loanB], copies: [copyA, copyB], reservations: [], filter: filter, now: date)
        #expect(snapshot.books.map(\.id) == [title.id])
        #expect(snapshot.copies.map(\.id) == [copyB.id])
        #expect(snapshot.stock[title.id]?.total == 1)
        #expect(snapshot.stock[title.id]?.loaned == 1)
        #expect(snapshot.loans.map(\.id) == [loanB.id])
        #expect(snapshot.events.map(\.copyID) == [copyB.id])
        #expect(title.quantity == 2) // Geçici kapsam hesabı kalıcı eser adedini değiştiremez.
        let document = snapshot.document(title: "KONUM RAPORU", schoolName: "Örnek Okul")
        #expect(document.table.contains(["Genel Durum", "Toplam nüsha", "1"]))
        let csv = String(decoding: ReportTableExporter.csv(document.table), as: UTF8.self)
        #expect(csv.contains("\"Toplam nüsha\";\"1\""))
        let pdf = try #require(PDFDocument(data: PDFReportBuilder.build(title: document.title, subtitle: document.subtitle, sections: document.sections)))
        #expect(pdf.string?.contains("Toplam nüsha") == true)
        let register = CopyRegisterEngine.rows(books: [title], copies: [copyA, copyB], loans: [loanA, loanB], filter: filter)
        #expect(register.map(\.id) == [copyB.id])
        #expect(CopyRegisterEngine.untracked(books: [title], copies: [copyA, copyB], filter: filter).isEmpty)
    }

    @Test func tekilKimliksizAdetYalnizEserKonumundaSayilir() throws {
        let title = book("Üç Adet", cabinet: "A", shelf: "1", quantity: 3)
        let copyA = BookCopy(bookID: title.id)
        let copyB = BookCopy(bookID: title.id, cabinet: "B", shelf: "2")
        var a = scope(); a.cabinet = "A"; a.shelf = "1"
        var b = scope(); b.cabinet = "B"; b.shelf = "2"
        #expect(LibraryReportEngine.scopedQuantity(for: title, copies: [copyA, copyB], filter: a) == 2)
        #expect(LibraryReportEngine.scopedQuantity(for: title, copies: [copyA, copyB], filter: b) == 1)
        #expect(CopyRegisterEngine.untracked(books: [title], copies: [copyA, copyB], filter: a).first?.count == 1)
        #expect(CopyRegisterEngine.untracked(books: [title], copies: [copyA, copyB], filter: b).isEmpty)
    }

    @Test func konumuBilinmeyenOduncBaskaRafiKesinMusaitGostermezVeCiftDusulmez() throws {
        let title = book("İki Raflı Eser", cabinet: "A", shelf: "1", quantity: 2)
        let copyA = BookCopy(bookID: title.id), copyB = BookCopy(bookID: title.id, cabinet: "B", shelf: "2")
        let unknown = ActiveLoan(bookID: title.id, bookTitleSnapshot: title.title, studentName: "Örnek Okur", studentClass: "7/A", dueDate: date)
        var b = scope(); b.cabinet = "B"; b.shelf = "2"
        let snapshotB = try LibraryReportEngine.snapshot(books: [title], events: [], loans: [unknown], copies: [copyA, copyB], reservations: [], filter: b, now: date)
        #expect(snapshotB.stock[title.id]?.total == 1)
        #expect(snapshotB.stock[title.id]?.available == 0)
        #expect(snapshotB.unresolvedLoanCounts[title.id] == 1)
        #expect(snapshotB.loans.isEmpty) // Hareket filtresinde belgeli parent A fallback korunur.
        #expect(snapshotB.sections.contains { $0.title == "Konumu belirsiz etkin ödünçler" })
        #expect(snapshotB.document(title: "RAPOR", schoolName: "Örnek").table.contains(["Genel Durum", "Şu an verilebilir nüsha (seçili koleksiyon)", "0"]))
        var a = scope(); a.cabinet = "A"; a.shelf = "1"
        let snapshotA = try LibraryReportEngine.snapshot(books: [title], events: [], loans: [unknown], copies: [copyA, copyB], reservations: [], filter: a, now: date)
        #expect(snapshotA.stock[title.id]?.loaned == 1)
        #expect(snapshotA.stock[title.id]?.available == 0) // Parent fallback ile zaten sayılmış ödünç yeniden düşülmez.
        unknown.copyID = copyB.id
        let resolved = try LibraryReportEngine.snapshot(books: [title], events: [], loans: [unknown], copies: [copyA, copyB], reservations: [], filter: b, now: date)
        #expect(resolved.unresolvedLoanCounts.isEmpty)
        #expect(resolved.stock[title.id]?.loaned == 1)
        #expect(resolved.stock[title.id]?.available == 0)
    }

    @Test func tersTarihAraligiRaporUretmez() {
        var filter = scope(); filter.start = filter.end.addingTimeInterval(1)
        #expect(throws: SchoolLibraryService.OperationError.self) {
            try LibraryReportEngine.snapshot(books: [], events: [], loans: [], copies: [], reservations: [], filter: filter)
        }
    }
}
