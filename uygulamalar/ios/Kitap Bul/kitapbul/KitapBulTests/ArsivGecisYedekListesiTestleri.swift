import Testing
import Foundation
import SwiftData
@testable import _01

@MainActor
@Suite(.serialized)
struct ArsivGecisYedekListesiTestleri {
    private func isolated(_ action: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("switch-backup-list-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try action(root)
    }

    private func contents() -> ArchiveContents {
        let book = Book(title: "Önceki katalog", author: "Yazar", quantity: 2, coverData: Data([1, 2, 3]))
        let student = Student(name: "Öğrenci", number: "12", className: "7-A")
        let member = Member(name: "Üye", memberNumber: "M2", kind: .teacher)
        let copy = BookCopy(bookID: book.id, accessionCode: "DEM-1")
        let loan = ActiveLoan(bookID: book.id, bookTitleSnapshot: book.title, studentName: student.name,
                              studentClass: student.className, dueDate: Date(timeIntervalSince1970: 2_000_000_000))
        loan.copyID = copy.id; loan.studentID = student.id; loan.studentNumberSnapshot = student.number; loan.identitySource = "student"
        let reservation = Reservation(bookID: book.id, bookTitleSnapshot: book.title, studentName: member.name, studentClass: "")
        reservation.memberID = member.id; reservation.identitySource = "member"
        let event = LoanEvent(bookID: book.id, bookTitle: book.title, person: student.name, kind: .lent,
                              date: Date(timeIntervalSince1970: 1_900_000_000), studentID: student.id, copyID: copy.id,
                              classSnapshot: student.className, loanID: loan.id, studentNumberSnapshot: student.number)
        return ArchiveContents(books: [book], loanEvents: [event], activeLoans: [ArchivedLoan(loan)], copies: [ArchivedCopy(copy)],
                               reservations: [ArchivedReservation(reservation)], students: [student], members: [member])
    }

    @discardableResult
    private func save(_ contents: ArchiveContents, at root: URL, state: String = "dogrulandi", transformReport: ((String) -> String)? = nil) throws -> URL {
        let directory = root.appendingPathComponent("switch-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FullArchive.buildVerified(contents).write(to: directory.appendingPathComponent("Islem-Oncesi-Tam-Arsiv.zip"), options: .atomic)
        let rows = ArchiveImportCoordinator.scope(before: contents, incoming: ArchiveContents(), after: ArchiveContents())
        let report = (["Ayrı katalog açma: " + state, "Önceki DB silinmez."]
                      + rows.map { "\($0.title): önce \($0.before), seçilen arşiv \($0.incoming), yeni katalog \($0.after)" }).joined(separator: "\n")
        try Data((transformReport?(report) ?? report).utf8).write(to: directory.appendingPathComponent("Katalog-Gecisi-Kapsam.txt"), options: .atomic)
        return directory
    }

    @Test func persistedFullBackupIsRediscoveredWithoutAnyInMemoryReceipt() throws {
        try isolated { root in
            let original = contents()
            try save(original, at: root)
            let first = try ArchiveSwitchBackupStore.listing(root: root)
            let entry = try #require(first.entries.first)
            #expect(first.entries.count == 1 && first.failures.isEmpty)
            #expect(entry.books == 1 && entry.copies == 1 && entry.loans == 1)
            #expect(entry.students == 1 && entry.members == 1 && entry.events == 1)
            let second = try ArchiveSwitchBackupStore.listing(root: root)
            #expect(second.entries.map(\.id) == first.entries.map(\.id))
            let reopened = try FullArchive.readValidated(from: entry.backupURL)
            #expect(reopened.books.first?.id == original.books.first?.id)
            #expect(reopened.activeLoans.first?.studentID == original.students.first?.id)
            #expect(reopened.reservations.first?.memberID == original.members.first?.id)
            #expect(reopened.copies.first?.id == original.copies.first?.id)
        }
    }

    @Test func corruptSiblingIsReportedWhileValidBackupRemainsAccessible() throws {
        try isolated { root in
            let good = try save(contents(), at: root)
            let bad = try save(contents(), at: root)
            try Data([0, 1, 2]).write(to: bad.appendingPathComponent("Islem-Oncesi-Tam-Arsiv.zip"), options: .atomic)
            let listing = try ArchiveSwitchBackupStore.listing(root: root)
            #expect(listing.entries.map(\.id) == [good.lastPathComponent])
            #expect(listing.failures.count == 1)
            #expect(listing.failures.first?.contains(bad.lastPathComponent) == true)
        }
    }

    @Test func scopeReportMismatchCannotExposeUnverifiedBackup() throws {
        try isolated { root in
            try save(contents(), at: root, transformReport: { $0.replacingOccurrences(of: "Eser: önce 1", with: "Eser: önce 999") })
            let listing = try ArchiveSwitchBackupStore.listing(root: root)
            #expect(listing.entries.isEmpty && listing.failures.count == 1)
        }
    }

    @Test func incompleteTransitionIsNeverLabelledSuccessful() throws {
        try isolated { root in
            for state in ["hazir", "geri_alindi", "geri_alma_bekliyor"] { try save(contents(), at: root, state: state) }
            let listing = try ArchiveSwitchBackupStore.listing(root: root)
            #expect(Set(listing.entries.map(\.state)) == Set(["hazir", "geri_alindi", "geri_alma_bekliyor"]))
            #expect(listing.entries.allSatisfy { $0.state != "dogrulandi" })
            #expect(listing.failures.isEmpty)
        }
    }

    @Test func symlinkedZIPCannotEscapeTheBackupDirectory() throws {
        try isolated { root in
            let directory = try save(contents(), at: root)
            let zip = directory.appendingPathComponent("Islem-Oncesi-Tam-Arsiv.zip")
            let other = root.appendingPathComponent("outside.zip")
            try FileManager.default.copyItem(at: zip, to: other)
            try FileManager.default.removeItem(at: zip)
            try FileManager.default.createSymbolicLink(at: zip, withDestinationURL: other)
            let listing = try ArchiveSwitchBackupStore.listing(root: root)
            #expect(listing.entries.isEmpty && listing.failures.count == 1)
        }
    }

    @Test func absentBackupRootIsReadOnlyAndEmpty() throws {
        try isolated { root in
            let missing = root.appendingPathComponent("not-created", isDirectory: true)
            let listing = try ArchiveSwitchBackupStore.listing(root: missing)
            #expect(listing.entries.isEmpty && listing.failures.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: missing.path))
        }
    }
}
