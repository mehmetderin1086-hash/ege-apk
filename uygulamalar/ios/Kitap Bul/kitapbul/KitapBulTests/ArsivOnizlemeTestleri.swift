import Testing
import Foundation
import SwiftData
@testable import _01

@MainActor
@Suite(.serialized)
struct ArsivOnizlemeTestleri {
    private func isolated(_ operation: (URL, ModelContext) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archive-preview-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let students = StudentStore.directoryOverride, members = MemberStore.directoryOverride
        let history = LoanHistoryStore.directoryOverride, support = ArchiveSettings.directoryOverride
        let sessions = ScanSessionStore.directoryOverride, fields = FieldMaintenanceStore.directoryOverride
        let preferences = ArchiveSettings.snapshot()
        StudentStore.directoryOverride = directory; MemberStore.directoryOverride = directory
        LoanHistoryStore.directoryOverride = directory; ArchiveSettings.directoryOverride = directory
        ScanSessionStore.directoryOverride = directory.appendingPathComponent("sessions")
        FieldMaintenanceStore.directoryOverride = nil; LoanHistoryStore.invalidateCache()
        defer {
            StudentStore.directoryOverride = students; MemberStore.directoryOverride = members
            LoanHistoryStore.directoryOverride = history; ArchiveSettings.directoryOverride = support
            ScanSessionStore.directoryOverride = sessions; FieldMaintenanceStore.directoryOverride = fields
            LoanHistoryStore.invalidateCache()
            for key in ArchiveSettings.allowedKeys { UserDefaults.standard.removeObject(forKey: key) }
            try? ArchiveSettings.restore(preferences)
            try? FileManager.default.removeItem(at: directory)
        }
        let context = ModelContext(try KitapVeritabani.makeContainer(inMemory: true)); context.autosaveEnabled = false
        try operation(directory, context)
    }
    private func bytes(in directory: URL) throws -> [String: Data] {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        return try Dictionary(uniqueKeysWithValues: urls.filter { try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true }
            .map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }
    private func data(_ contents: ArchiveContents) throws -> Data { try FullArchive.buildVerified(contents) }
    private func jsonString(_ value: String) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed) }

    @Test func previewDoesNotWriteMetadataPreferencesOrLiveDatabase() throws {
        try isolated { directory, context in
            let existing = CatalogBook(book: Book(title: "Mevcut", author: "Yazar", coverData: Data([1])))
            context.insert(existing); try context.save()
            let student = Student(name: "Mevcut öğrenci", number: "101", className: "7-A")
            try StudentStore.replaceAllVerified([student])
            UserDefaults.standard.set("Mevcut okul", forKey: "schoolName")
            let filesBefore = try bytes(in: directory), preferencesBefore = ArchiveSettings.snapshot()
            let before = try ArchiveImportCoordinator.fingerprint(FullArchive.snapshot(context: context))
            let incoming = ArchiveContents(books: [Book(title: "Yeni", author: "Y")], students: [Student(name: "Yeni", number: "102")],
                                           settings: ["schoolName": try jsonString("Arşiv okulu")])
            let preview = try ArchiveImportCoordinator.prepare(data: data(incoming), context: context, restoreSettings: true)
            #expect(preview.rows.first { $0.id == "books" }?.after == 2)
            #expect(preview.rows.first { $0.id == "students" }?.after == 2)
            #expect(try bytes(in: directory) == filesBefore)
            #expect(ArchiveSettings.snapshot() == preferencesBefore)
            #expect(try ArchiveImportCoordinator.fingerprint(FullArchive.snapshot(context: context)) == before)
            #expect(!context.hasChanges)
        }
    }

    @Test func applyPreservesCurrentCoverBorrowerAndHistoryAndVerifiesFullBackup() throws {
        try isolated { directory, context in
            let book = CatalogBook(book: Book(title: "Mevcut eser", author: "Yazar", quantity: 2, coverData: Data([1, 2, 3])))
            let student = Student(name: "Ali", number: "5", className: "7-A")
            let member = Member(name: "Öğretmen", memberNumber: "M1")
            try StudentStore.replaceAllVerified([student]); try MemberStore.replaceAllVerified([member])
            let copy = BookCopy(bookID: book.id, accessionCode: "D1")
            let loan = ActiveLoan(bookID: book.id, bookTitleSnapshot: book.title, studentName: member.name, studentClass: "", dueDate: .now)
            loan.memberID = member.id; loan.copyID = copy.id; loan.identitySource = "member"
            let event = LoanEvent(bookID: book.id, bookTitle: book.title, person: member.name, kind: .lent, date: .now, memberID: member.id)
            context.insert(book); context.insert(copy); context.insert(loan); try context.save(); try LoanHistoryStore.replaceAll([event])
            let before = try FullArchive.snapshot(context: context)
            var duplicate = book.book; duplicate.title = "Eski arşiv başlığı"; duplicate.coverData = Data([9])
            let newStudent = Student(name: "Yeni öğrenci", number: "6", className: "7-B")
            let incoming = ArchiveContents(books: [duplicate, Book(title: "Yeni eser", author: "Y")], students: [newStudent])
            let preview = try ArchiveImportCoordinator.prepare(data: data(incoming), context: context)
            let receipt = try ArchiveImportCoordinator.apply(preview, context: context, backupDirectory: directory.appendingPathComponent("backups"))
            let backup = try FullArchive.readValidated(from: receipt.backupURL)
            #expect(try ArchiveImportCoordinator.fingerprint(backup) == ArchiveImportCoordinator.fingerprint(before))
            #expect(try context.fetchCount(FetchDescriptor<CatalogBook>()) == 2)
            #expect(book.title == "Mevcut eser" && book.coverData == Data([1, 2, 3]))
            #expect(try context.fetch(FetchDescriptor<ActiveLoan>()).first?.memberID == member.id)
            #expect(try context.fetch(FetchDescriptor<ActiveLoan>()).first?.copyID == copy.id)
            #expect(try StudentStore.allVerified().map(\.id).contains(student.id))
            #expect(try StudentStore.allVerified().map(\.id).contains(newStudent.id))
            #expect(try LoanHistoryStore.allVerified().map(\.id) == [event.id])
            #expect(try ArchiveImportCoordinator.fingerprint(FullArchive.snapshot(context: context)) == ArchiveImportCoordinator.fingerprint(preview.expected))
        }
    }

    @Test func stalePreviewRejectsChangedStudentWithoutMutationOrBackup() throws {
        try isolated { directory, context in
            let student = Student(name: "Ali", number: "1", className: "7-A")
            try StudentStore.replaceAllVerified([student])
            let preview = try ArchiveImportCoordinator.prepare(data: data(ArchiveContents(books: [Book(title: "Yeni", author: "Y")])), context: context)
            var changed = student; changed.number = "2"; try StudentStore.replaceAllVerified([changed])
            let backupRoot = directory.appendingPathComponent("backups")
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try ArchiveImportCoordinator.apply(preview, context: context, backupDirectory: backupRoot)
            }
            #expect(try context.fetchCount(FetchDescriptor<CatalogBook>()) == 0)
            #expect(try StudentStore.allVerified() == [changed])
            #expect(!FileManager.default.fileExists(atPath: backupRoot.path))
        }
    }

    @Test func failedPostVerificationRollsBackExactRawFilesPreferencesAndInsertedModels() throws {
        try isolated { directory, context in
            let book = CatalogBook(book: Book(title: "Mevcut", author: "Y", coverData: Data([1])))
            context.insert(book); try context.save()
            // Ham JSON biçimi de aynı geri gelmeli; yalnız eşdeğer yeniden kodlama yeterli değil.
            let raw = Data("[ { \"id\": \"00000000-0000-0000-0000-000000000001\", \"name\": \"Ali\", \"number\": \"1\", \"className\": \"7-A\" } ]".utf8)
            try raw.write(to: #require(StudentStore.storageURL))
            UserDefaults.standard.set("Eski okul", forKey: "schoolName")
            let before = try FullArchive.snapshot(context: context)
            let incoming = ArchiveContents(books: [Book(title: "Yeni", author: "Y")], students: [Student(name: "Yeni öğrenci")], settings: ["schoolName": try jsonString("Yeni okul")])
            let preview = try ArchiveImportCoordinator.prepare(data: data(incoming), context: context, restoreSettings: true)
            var retainedBackup: URL?
            do {
                _ = try ArchiveImportCoordinator.apply(preview, context: context, backupDirectory: directory.appendingPathComponent("backups")) { trialContext in
                    book.title = "Doğrulama sırasında değişen eser"; book.coverData = Data([9])
                    book.addedAt = .distantFuture
                    try trialContext.save()
                    try StudentStore.replaceAllVerified([Student(name: "Yanlış kişi")])
                    throw SchoolLibraryService.OperationError(message: "Kapsam hatası simülasyonu")
                }
                Issue.record("Hata enjeksiyonu reddedilmeliydi")
            } catch let error as ArchiveImportCoordinator.ApplyError { retainedBackup = error.backupURL }
            #expect(try Data(contentsOf: #require(StudentStore.storageURL)) == raw)
            #expect(UserDefaults.standard.string(forKey: "schoolName") == "Eski okul")
            #expect(try ArchiveImportCoordinator.fingerprint(FullArchive.snapshot(context: context)) == ArchiveImportCoordinator.fingerprint(before))
            let backup = try FullArchive.readValidated(from: #require(retainedBackup))
            #expect(backup.books.map(\.id) == [book.id])
            let memberURL = try #require(MemberStore.storageURL)
            let graduateURL = try #require(GraduatedStudentStore.storageURL)
            #expect(!FileManager.default.fileExists(atPath: memberURL.path))
            #expect(!FileManager.default.fileExists(atPath: graduateURL.path))
        }
    }

    @Test func unavailableBackupDestinationPreventsAnyLiveWrite() throws {
        try isolated { directory, context in
            let preview = try ArchiveImportCoordinator.prepare(data: data(ArchiveContents(books: [Book(title: "Yeni", author: "Y")])), context: context)
            let blocker = directory.appendingPathComponent("not-a-directory")
            try Data([1]).write(to: blocker)
            do { _ = try ArchiveImportCoordinator.apply(preview, context: context, backupDirectory: blocker); Issue.record("Yedek yazılamıyorken uygulanmamalı") }
            catch { }
            #expect(try context.fetchCount(FetchDescriptor<CatalogBook>()) == 0)
            let studentURL = try #require(StudentStore.storageURL)
            #expect(!FileManager.default.fileExists(atPath: studentURL.path))
        }
    }

    @Test func existingLoanHistoryRejectsOldOperationalStateDuringPreview() throws {
        try isolated { _, context in
            let old = CatalogBook(book: Book(title: "Mevcut", author: "Y"))
            context.insert(old); try context.save()
            try LoanHistoryStore.replaceAll([LoanEvent(bookID: old.id, bookTitle: old.title, person: "A", kind: .returned, date: .now)])
            let incomingBook = Book(title: "Eski arşiv", author: "Y")
            let loan = ArchivedLoan(id: UUID(), bookID: incomingBook.id, bookTitleSnapshot: incomingBook.title, studentName: "B", studentClass: "7-A", loanedAt: .now, dueDate: .now)
            let before = try ArchiveImportCoordinator.fingerprint(FullArchive.snapshot(context: context))
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try ArchiveImportCoordinator.prepare(data: data(ArchiveContents(books: [incomingBook], activeLoans: [loan])), context: context)
            }
            #expect(try ArchiveImportCoordinator.fingerprint(FullArchive.snapshot(context: context)) == before)
        }
    }

    @Test func legacyLoanTrialUsesIncomingPeopleWithoutWritingThemAndMigratesOnce() throws {
        try isolated { directory, context in
            let book = Book(title: "Eski tekil", author: "Y", loanedTo: "Ali", loanDueDate: Date(timeIntervalSince1970: 1_800_000_000))
            let first = Student(name: "Ali", number: "1", className: "7-A"), second = Student(name: "Ali", number: "2", className: "7-B")
            let incoming = ArchiveContents(books: [book], students: [first, second])
            let fixed = Date(timeIntervalSince1970: 1_799_000_000)
            let preview = try ArchiveImportCoordinator.prepare(data: data(incoming), context: context, now: fixed)
            let again = try ArchiveImportCoordinator.prepare(data: data(incoming), context: context, now: fixed)
            #expect(preview.migratedLoans == 1 && preview.expected.activeLoans.first?.needsIdentityReview == true)
            #expect(preview.expected.activeLoans.first?.studentID == nil)
            #expect(preview.expected.activeLoans.first?.id == again.expected.activeLoans.first?.id)
            #expect(try StudentStore.allVerified().isEmpty)
            _ = try ArchiveImportCoordinator.apply(preview, context: context, backupDirectory: directory.appendingPathComponent("backups"))
            #expect(try SchoolLibraryService.migrateLegacyLoans(context: context) == 0)
            #expect(try context.fetchCount(FetchDescriptor<ActiveLoan>()) == 1)
            #expect(try context.fetch(FetchDescriptor<CatalogBook>()).first?.loanedTo == nil)
        }
    }

    @Test func safeSettingsRequireExplicitOptIn() throws {
        try isolated { directory, context in
            UserDefaults.standard.set("Mevcut okul", forKey: "schoolName")
            let incoming = ArchiveContents(settings: ["schoolName": try jsonString("Arşiv okulu")])
            let preserved = try ArchiveImportCoordinator.prepare(data: data(incoming), context: context)
            _ = try ArchiveImportCoordinator.apply(preserved, context: context, backupDirectory: directory.appendingPathComponent("backups"))
            #expect(UserDefaults.standard.string(forKey: "schoolName") == "Mevcut okul")
            let selected = try ArchiveImportCoordinator.prepare(data: data(incoming), context: context, restoreSettings: true)
            _ = try ArchiveImportCoordinator.apply(selected, context: context, backupDirectory: directory.appendingPathComponent("backups"))
            #expect(UserDefaults.standard.string(forKey: "schoolName") == "Arşiv okulu")
        }
    }

    @Test func archiveMergePreservesBothFieldUndoJournals() throws {
        try isolated { directory, context in
            let oldBook = CatalogBook(book: Book(title: "Eski", author: "Yeni ad"))
            context.insert(oldBook); try context.save()
            var existing = FieldMaintenanceReceipt(field: .author, changes: [FieldMaintenanceChange(bookID: oldBook.id, title: oldBook.title, before: "Eski ad", after: "Yeni ad", beforeEvidence: nil, afterEvidence: nil)])
            existing.state = .committed
            try FieldMaintenanceStore.replaceVerified([existing])
            let newBook = Book(title: "Yeni", author: "Yeni yazar")
            var imported = FieldMaintenanceReceipt(field: .author, changes: [FieldMaintenanceChange(bookID: newBook.id, title: newBook.title, before: "Eski yazar", after: "Yeni yazar", beforeEvidence: nil, afterEvidence: nil)])
            imported.state = .committed
            let incoming = ArchiveContents(books: [newBook], supportingFiles: [FieldMaintenanceStore.fileName: try FieldMaintenanceStore.encode([imported])])
            let preview = try ArchiveImportCoordinator.prepare(data: data(incoming), context: context)
            _ = try ArchiveImportCoordinator.apply(preview, context: context, backupDirectory: directory.appendingPathComponent("backups"))
            #expect(Set(try FieldMaintenanceStore.allVerified().map(\.id)) == Set([existing.id, imported.id]))
        }
    }

    @Test func reservationWithMissingOrWrongBookCopyIsRejectedBeforeTrial() throws {
        try isolated { _, context in
            let book = Book(title: "A", author: "Y"), other = Book(title: "B", author: "Y")
            let reservation = Reservation(bookID: book.id, bookTitleSnapshot: book.title, studentName: "Ali", studentClass: "7-A")
            reservation.copyID = UUID()
            let missing = ArchiveContents(books: [book], reservations: [ArchivedReservation(reservation)])
            #expect(throws: FullArchive.ValidationError.self) { try ArchiveImportCoordinator.prepare(data: data(missing), context: context) }
            let copy = BookCopy(bookID: other.id)
            reservation.copyID = copy.id
            let wrong = ArchiveContents(books: [book, other], copies: [ArchivedCopy(copy)], reservations: [ArchivedReservation(reservation)])
            #expect(throws: FullArchive.ValidationError.self) { try ArchiveImportCoordinator.prepare(data: data(wrong), context: context) }
            let remainingBooks = try context.fetchCount(FetchDescriptor<CatalogBook>())
            #expect(remainingBooks == 0)
        }
    }

    @Test func importedPhysicalCopiesCannotExceedCurrentWinsQuantity() throws {
        try isolated { _, context in
            let current = CatalogBook(book: Book(title: "Mevcut eser", author: "Y", quantity: 1))
            context.insert(current); try context.save()
            var archived = current.book; archived.quantity = 2
            let first = BookCopy(bookID: current.id, accessionCode: "D1"), second = BookCopy(bookID: current.id, accessionCode: "D2")
            let incoming = ArchiveContents(books: [archived], copies: [ArchivedCopy(first), ArchivedCopy(second)])
            #expect(throws: SchoolLibraryService.OperationError.self) { try ArchiveImportCoordinator.prepare(data: data(incoming), context: context) }
            #expect(current.quantity == 1)
            #expect(try context.fetchCount(FetchDescriptor<BookCopy>()) == 0)
        }
    }

    @Test func preexistingInvalidStockCanBePreservedButCannotBecomeWorse() throws {
        try isolated { _, context in
            let current = CatalogBook(book: Book(title: "Eski tutarsızlık", author: "Y", quantity: 1))
            let first = BookCopy(bookID: current.id), second = BookCopy(bookID: current.id)
            context.insert(current); context.insert(first); context.insert(second); try context.save()
            let preserved = ArchiveContents(books: [current.book])
            #expect(try ArchiveImportCoordinator.prepare(data: data(preserved), context: context).expected.copies.count == 2)
            let third = BookCopy(bookID: current.id)
            let worse = ArchiveContents(books: [current.book], copies: [ArchivedCopy(third)])
            #expect(throws: SchoolLibraryService.OperationError.self) { try ArchiveImportCoordinator.prepare(data: data(worse), context: context) }
            #expect(try context.fetchCount(FetchDescriptor<BookCopy>()) == 2)
        }
    }

    @Test func newUnidentifiedLoanCannotBorrowTrackedLostRepairOrWithdrawnCapacity() throws {
        try isolated { _, context in
            for status in ["Kayıp", "Onarımda", "Düşüldü"] {
                let book = CatalogBook(book: Book(title: "Fiziksel \(status)", author: "Y", quantity: 1))
                let copy = BookCopy(bookID: book.id, status: status)
                context.insert(book); context.insert(copy); try context.save()
                let loan = ArchivedLoan(id: UUID(), bookID: book.id, bookTitleSnapshot: book.title, studentName: "Ali", studentClass: "7-A", loanedAt: .now, dueDate: .now)
                let incoming = ArchiveContents(books: [book.book], activeLoans: [loan])
                #expect(throws: SchoolLibraryService.OperationError.self) { try ArchiveImportCoordinator.prepare(data: data(incoming), context: context) }
            }
            let count = try context.fetchCount(FetchDescriptor<ActiveLoan>())
            #expect(count == 0)
        }
    }
}
