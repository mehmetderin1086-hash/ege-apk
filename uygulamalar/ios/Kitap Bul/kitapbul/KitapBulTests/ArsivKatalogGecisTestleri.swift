import Testing
import Foundation
import SwiftData
@testable import _01

@MainActor
@Suite(.serialized)
struct ArsivKatalogGecisTestleri {
    private func isolated(_ action: (URL, ModelContext) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archive-switch-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oldStudents = StudentStore.directoryOverride, oldMembers = MemberStore.directoryOverride
        let oldHistory = LoanHistoryStore.directoryOverride, oldSupport = ArchiveSettings.directoryOverride
        let oldSessions = ScanSessionStore.directoryOverride, oldFields = FieldMaintenanceStore.directoryOverride
        let preferences = ArchiveSettings.snapshot(), pointer = UserDefaults.standard.object(forKey: StoreRecovery.selectedStoreKey)
        let oldJournalPaths = ArchiveSwitchJournal.pathsOverride
        let shared = KitapVeritabani.shared, receipt = LibraryStoreSwitchStatus.shared.receipt
        StudentStore.directoryOverride = directory; MemberStore.directoryOverride = directory
        LoanHistoryStore.directoryOverride = directory; ArchiveSettings.directoryOverride = directory
        ScanSessionStore.directoryOverride = directory.appendingPathComponent("sessions"); FieldMaintenanceStore.directoryOverride = nil
        LoanHistoryStore.invalidateCache()
        ArchiveSwitchJournal.pathsOverride = ArchiveSwitchJournal.Paths(journalURL: directory.appendingPathComponent("switch-journal.json"),
            backupRoot: directory.appendingPathComponent("backups", isDirectory: true),
            recoveredRoot: directory.appendingPathComponent("stores", isDirectory: true))
        UserDefaults.standard.removeObject(forKey: StoreRecovery.selectedStoreKey)
        defer {
            ArchiveSwitchJournal.pathsOverride = oldJournalPaths
            StudentStore.directoryOverride = oldStudents; MemberStore.directoryOverride = oldMembers
            LoanHistoryStore.directoryOverride = oldHistory; ArchiveSettings.directoryOverride = oldSupport
            ScanSessionStore.directoryOverride = oldSessions; FieldMaintenanceStore.directoryOverride = oldFields
            LoanHistoryStore.invalidateCache(); KitapVeritabani.shared = shared; LibraryStoreSwitchStatus.shared.receipt = receipt
            for key in ArchiveSettings.allowedKeys { UserDefaults.standard.removeObject(forKey: key) }
            try? ArchiveSettings.restore(preferences)
            if let pointer { UserDefaults.standard.set(pointer, forKey: StoreRecovery.selectedStoreKey) }
            else { UserDefaults.standard.removeObject(forKey: StoreRecovery.selectedStoreKey) }
            try? FileManager.default.removeItem(at: directory)
        }
        let context = ModelContext(try KitapVeritabani.makeContainer(inMemory: true)); context.autosaveEnabled = false
        try action(directory, context)
    }
    private func archive(_ contents: ArchiveContents) throws -> Data { try FullArchive.buildVerified(contents) }

    @Test func separatePreviewDoesNotMutateLiveFilesPreferencesOrPointer() throws {
        try isolated { directory, context in
            let existing = CatalogBook(book: Book(title: "Önceki", author: "Y"))
            context.insert(existing); try context.save()
            let before = try ArchiveImportCoordinator.fingerprint(FullArchive.snapshot(context: context))
            let oldPointer = UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey)
            let beforeFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            let student = Student(name: "Yeni", number: "200", className: "7-A"), book = Book(title: "Arşiv", author: "Y")
            let reservation = Reservation(bookID: book.id, bookTitleSnapshot: book.title, studentName: student.name, studentClass: student.className)
            reservation.studentID = student.id; reservation.identitySource = "student"
            let contents = ArchiveContents(books: [book], reservations: [ArchivedReservation(reservation)], students: [student])
            let preview = try ArchiveSwitchCoordinator.prepare(data: archive(contents), context: context)
            #expect(preview.expected.books.map(\.id) == [book.id])
            #expect(preview.expected.reservations.first?.notifiedAt != nil)
            #expect(try ArchiveImportCoordinator.fingerprint(FullArchive.snapshot(context: context)) == before)
            #expect(UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey) == oldPointer)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == beforeFiles)
        }
    }

    @Test func exactNewStateActivatesWithTypedIDsWhileOldDatabaseAndPendingEventRemain() throws {
        try isolated { directory, context in
            let oldBook = CatalogBook(book: Book(title: "Önceki katalog", author: "Y", coverData: Data([1])))
            let oldLoan = ActiveLoan(bookID: oldBook.id, bookTitleSnapshot: oldBook.title, studentName: "Eski kişi", studentClass: "", dueDate: .now)
            let pendingEvent = LoanEvent(bookID: oldBook.id, bookTitle: oldBook.title, person: oldLoan.studentName, kind: .lent, date: .now, loanID: oldLoan.id)
            context.insert(oldBook); context.insert(oldLoan); context.insert(try LibraryEventOutbox(event: pendingEvent)); try context.save()
            UserDefaults.standard.set("Mevcut okul", forKey: "schoolName")
            let before = try FullArchive.snapshot(context: context)
            let book = Book(title: "Yeni katalog", author: "Y", quantity: 2, coverData: Data([2]))
            let member = Member(name: "Aynı isim", memberNumber: "M2", kind: .teacher)
            let student = Student(name: "Aynı isim", number: "S2", className: "7-A")
            let copy = BookCopy(bookID: book.id, accessionCode: "N1")
            let loan = ActiveLoan(bookID: book.id, bookTitleSnapshot: book.title, studentName: member.name, studentClass: "", dueDate: .now)
            loan.memberID = member.id; loan.identitySource = "member"; loan.copyID = copy.id
            let reservation = Reservation(bookID: book.id, bookTitleSnapshot: book.title, studentName: student.name, studentClass: student.className)
            reservation.studentID = student.id; reservation.identitySource = "student"; reservation.studentNumberSnapshot = student.number
            let incoming = ArchiveContents(books: [book], activeLoans: [ArchivedLoan(loan)], copies: [ArchivedCopy(copy)],
                                           reservations: [ArchivedReservation(reservation)], students: [student], members: [member])
            let preview = try ArchiveSwitchCoordinator.prepare(data: archive(incoming), context: context)
            var activation: LibraryStoreActivation?
            let receipt = try ArchiveSwitchCoordinator.apply(preview, context: context, backupDirectory: directory.appendingPathComponent("backups"), publish: { activation = $0 })
            let restored = try #require(activation).container
            let selectedPath = try #require(UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey))
            #expect(FileManager.default.fileExists(atPath: selectedPath))
            #expect(try restored.mainContext.fetch(FetchDescriptor<CatalogBook>()).map(\.id) == [book.id])
            #expect(try restored.mainContext.fetch(FetchDescriptor<ActiveLoan>()).first?.memberID == member.id)
            #expect(try restored.mainContext.fetch(FetchDescriptor<ActiveLoan>()).first?.copyID == copy.id)
            #expect(try StudentStore.allVerified() == [student])
            #expect(try MemberStore.allVerified() == [member])
            #expect(UserDefaults.standard.string(forKey: "schoolName") == "Mevcut okul")
            #expect(try context.fetch(FetchDescriptor<CatalogBook>()).map(\.id) == [oldBook.id])
            #expect(try context.fetchCount(FetchDescriptor<LibraryEventOutbox>()) == 1)
            let backup = try FullArchive.readValidated(from: receipt.backupURL)
            #expect(try ArchiveImportCoordinator.fingerprint(backup) == ArchiveImportCoordinator.fingerprint(before))
            #expect(backup.loanEvents.contains { $0.id == pendingEvent.id })
            #expect(try ArchiveImportCoordinator.fingerprint(FullArchive.snapshot(context: restored.mainContext)) == ArchiveImportCoordinator.fingerprint(preview.expected))
        }
    }

    @Test func oldVerifiedBackupCanBeOpenedAgainFromTheSameNormalService() throws {
        try isolated { directory, context in
            let original = CatalogBook(book: Book(title: "Geri dönülecek", author: "Y"))
            context.insert(original); try context.save()
            let preview = try ArchiveSwitchCoordinator.prepare(data: archive(ArchiveContents(books: [Book(title: "Başka katalog", author: "Y")])), context: context)
            var first: LibraryStoreActivation?
            let receipt = try ArchiveSwitchCoordinator.apply(preview, context: context, backupDirectory: directory.appendingPathComponent("backups"), publish: { first = $0 })
            let firstStore = try #require(first).container
            let returnPreview = try ArchiveSwitchCoordinator.prepare(data: Data(contentsOf: receipt.backupURL), context: firstStore.mainContext)
            var second: LibraryStoreActivation?
            _ = try ArchiveSwitchCoordinator.apply(returnPreview, context: firstStore.mainContext, backupDirectory: directory.appendingPathComponent("backups"), publish: { second = $0 })
            let secondStore = try #require(second).container
            #expect(try secondStore.mainContext.fetch(FetchDescriptor<CatalogBook>()).map(\.id) == [original.id])
            #expect(try context.fetch(FetchDescriptor<CatalogBook>()).map(\.id) == [original.id])
        }
    }

    @Test func failureAfterPointerBeforeUIPublishRestoresMetadataPointerAndOldContext() throws {
        try isolated { directory, context in
            let student = Student(name: "Eski öğrenci", number: "1", className: "7-A")
            try StudentStore.replaceAllVerified([student]); UserDefaults.standard.set("Eski okul", forKey: "schoolName")
            let oldPointer = UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey)
            let before = try ArchiveImportCoordinator.fingerprint(FullArchive.snapshot(context: context))
            let incoming = ArchiveContents(books: [Book(title: "Yeni", author: "Y")], students: [Student(name: "Yeni öğrenci")])
            let preview = try ArchiveSwitchCoordinator.prepare(data: archive(incoming), context: context)
            var published = false
            #expect(throws: ArchiveImportCoordinator.ApplyError.self) {
                try ArchiveSwitchCoordinator.apply(preview, context: context, backupDirectory: directory.appendingPathComponent("backups"), beforePublish: { _ in
                    throw SchoolLibraryService.OperationError(message: "Aktivasyon kapısı simülasyonu")
                }, publish: { _ in published = true })
            }
            #expect(!published)
            #expect(UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey) == oldPointer)
            #expect(try StudentStore.allVerified() == [student])
            #expect(try ArchiveImportCoordinator.fingerprint(FullArchive.snapshot(context: context)) == before)
        }
    }

    @Test func stalePreviewAndUnwritableBackupCannotActivate() throws {
        try isolated { directory, context in
            let incoming = ArchiveContents(books: [Book(title: "Arşiv", author: "Y")])
            let preview = try ArchiveSwitchCoordinator.prepare(data: archive(incoming), context: context)
            try StudentStore.replaceAllVerified([Student(name: "Sonradan değişen")])
            var published = false
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try ArchiveSwitchCoordinator.apply(preview, context: context, publish: { _ in published = true })
            }
            let fresh = try ArchiveSwitchCoordinator.prepare(data: archive(incoming), context: context)
            let blocker = directory.appendingPathComponent("file"); try Data([1]).write(to: blocker)
            do { _ = try ArchiveSwitchCoordinator.apply(fresh, context: context, backupDirectory: blocker, publish: { _ in published = true }); Issue.record("Yedek yazılmadan aktivasyon olmamalı") } catch { }
            #expect(!published)
            let count = try context.fetchCount(FetchDescriptor<CatalogBook>())
            #expect(count == 0)
        }
    }
}
