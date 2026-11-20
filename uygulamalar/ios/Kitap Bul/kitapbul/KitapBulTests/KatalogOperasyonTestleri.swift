import Testing
import Foundation
import SwiftData
@testable import _01

@MainActor
@Suite(.serialized)
struct KatalogOperasyonTestleri {
    private func context() throws -> ModelContext { ModelContext(try KitapVeritabani.makeContainer(inMemory: true)) }

    private func isolatedMetadata(_ operation: () throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("library-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oldStudents = StudentStore.directoryOverride, oldMembers = MemberStore.directoryOverride
        let oldHistory = LoanHistoryStore.directoryOverride, oldSupport = ArchiveSettings.directoryOverride
        let oldSessions = ScanSessionStore.directoryOverride, oldRules = GradeLoanRuleStore.directoryOverride
        let oldInventory = InventorySessionStore.directoryOverride
        let events = LoanHistoryStore.all
        StudentStore.directoryOverride = directory; MemberStore.directoryOverride = directory
        LoanHistoryStore.directoryOverride = directory; ArchiveSettings.directoryOverride = directory
        ScanSessionStore.directoryOverride = directory.appendingPathComponent("TaramaOturumlari")
        GradeLoanRuleStore.directoryOverride = directory
        InventorySessionStore.directoryOverride = directory
        try LoanHistoryStore.replaceAll([])
        defer {
            try? LoanHistoryStore.replaceAll(events)
            StudentStore.directoryOverride = oldStudents; MemberStore.directoryOverride = oldMembers
            LoanHistoryStore.directoryOverride = oldHistory; ArchiveSettings.directoryOverride = oldSupport
            ScanSessionStore.directoryOverride = oldSessions; GradeLoanRuleStore.directoryOverride = oldRules
            InventorySessionStore.directoryOverride = oldInventory
            try? FileManager.default.removeItem(at: directory)
        }
        try operation()
    }

    @Test func physicalStatusesReduceAvailability() {
        let book = CatalogBook(book: Book(title: "Eser", author: "Yazar", quantity: 3))
        let one = BookCopy(bookID: book.id, accessionCode: "1")
        let two = BookCopy(bookID: book.id, accessionCode: "2", status: "Kayıp")
        let three = BookCopy(bookID: book.id, accessionCode: "3")
        let loan = ActiveLoan(bookID: book.id, bookTitleSnapshot: book.title, studentName: "A", studentClass: "5-A", dueDate: .now)
        loan.copyID = one.id
        let state = SchoolLibraryService.stock(for: book, loans: [loan], copies: [one, two, three])
        #expect(state.total == 3)
        #expect(state.loaned == 1)
        #expect(state.lost == 1)
        #expect(state.available == 1)
        three.status = "Onarımda"
        #expect(SchoolLibraryService.stock(for: book, loans: [loan], copies: [one, two, three]).available == 0)
    }

    @Test func readyReservationHoldsStockUntilExpiry() {
        let book = CatalogBook(book: Book(title: "Eser", author: "Y", quantity: 1))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reservation = Reservation(bookID: book.id, bookTitleSnapshot: book.title, studentName: "B", studentClass: "5-A")
        reservation.notifiedAt = now; reservation.expiresAt = now.addingTimeInterval(48 * 3600)
        let held = SchoolLibraryService.stock(for: book, loans: [], reservations: [reservation], now: now)
        #expect(held.available == 0 && held.reserved == 1)
        let expired = SchoolLibraryService.stock(for: book, loans: [], reservations: [reservation], now: now.addingTimeInterval(49 * 3600))
        #expect(expired.available == 1 && expired.reserved == 0)
    }

    @Test func textbooksCannotExceedStock() throws {
        try isolatedMetadata {
            let context = try context()
            let book = CatalogBook(book: Book(title: "Biyoloji", author: "", quantity: 1, isTextbook: true))
            context.insert(book); try context.save()
            _ = try SchoolLibraryService.lend(book: book, person: "A", className: "9-A", context: context, kind: "textbook")
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try SchoolLibraryService.lend(book: book, person: "B", className: "9-A", context: context, kind: "textbook")
            }
            #expect(try context.fetchCount(FetchDescriptor<ActiveLoan>()) == 1)
            #expect(LoanHistoryStore.all.count == 1)
            #expect(LoanHistoryStore.all.first?.loanKind == "textbook")
        }
    }

    @Test func identicalNamesRequireExactStudentChoice() throws {
        try isolatedMetadata {
            let first = Student(name: "Ali Yılmaz", number: "1", className: "5-A")
            let second = Student(name: "Ali Yılmaz", number: "2", className: "5-B")
            try StudentStore.replaceAllVerified([first, second])
            #expect(throws: SchoolLibraryService.OperationError.self) { try SchoolLibraryService.resolvedStudent(name: "Ali Yılmaz", className: "") }
            #expect(try SchoolLibraryService.resolvedStudent(name: "Ali Yılmaz", className: "5-B")?.id == second.id)
        }
    }

    @Test func legacyMigrationIsIdempotentAndFlagsAmbiguity() throws {
        try isolatedMetadata {
            try StudentStore.replaceAllVerified([Student(name: "Ali", className: "5-A"), Student(name: "Ali", className: "5-B")])
            let context = try context()
            let book = CatalogBook(book: Book(title: "Eser", author: "Y", loanedTo: "Ali", loanDueDate: .now))
            context.insert(book); try context.save()
            #expect(try SchoolLibraryService.migrateLegacyLoans(context: context) == 1)
            #expect(try SchoolLibraryService.migrateLegacyLoans(context: context) == 0)
            let loans = try context.fetch(FetchDescriptor<ActiveLoan>())
            #expect(loans.count == 1)
            #expect(loans.first?.studentID == nil)
            #expect(loans.first?.needsIdentityReview == true)
            #expect(book.loanedTo == nil)
        }
    }

    @Test func completeArchiveRetainsPhysicalAndPersonIDs() throws {
        let context = try context()
        let book = CatalogBook(book: Book(title: "Eser", author: "Y", quantity: 1, backCoverData: Data([7]), imprintData: Data([8])))
        let copy = BookCopy(bookID: book.id, accessionCode: "D-1", condition: "Yeni")
        let student = Student(name: "A", className: "5-A")
        let loan = ActiveLoan(bookID: book.id, bookTitleSnapshot: book.title, studentName: student.name, studentClass: student.className, dueDate: .now)
        loan.copyID = copy.id; loan.studentID = student.id
        let reservation = Reservation(bookID: book.id, bookTitleSnapshot: book.title, studentName: "B", studentClass: "5-B")
        context.insert(book); context.insert(copy); context.insert(loan); context.insert(reservation); try context.save()
        let contents = ArchiveContents(books: [book.book], activeLoans: [ArchivedLoan(loan)], copies: [ArchivedCopy(copy)],
                                       reservations: [ArchivedReservation(reservation)], students: [student], members: [Member(name: "Öğretmen")])
        let restored = try FullArchive.readValidated(data: FullArchive.build(contents))
        #expect(restored.books.first?.backCoverData == Data([7]))
        #expect(restored.books.first?.imprintData == Data([8]))
        #expect(restored.copies.first?.id == copy.id)
        #expect(restored.activeLoans.first?.copyID == copy.id)
        #expect(restored.activeLoans.first?.studentID == student.id)
        #expect(restored.reservations.first?.id == reservation.id)
        #expect(restored.students.first?.id == student.id)
        #expect(restored.members.count == 1)
    }

    @Test func mergeMovesAllBookRelationships() throws {
        try isolatedMetadata {
            let context = try context()
            let first = CatalogBook(book: Book(title: "Eser", author: "Y", quantity: 1))
            let second = CatalogBook(book: Book(title: "Eser", author: "Y", publisher: "P", quantity: 2))
            let copy = BookCopy(bookID: first.id, accessionCode: "D-1")
            let loan = ActiveLoan(bookID: first.id, bookTitleSnapshot: first.title, studentName: "A", studentClass: "5-A", dueDate: .now)
            let reservation = Reservation(bookID: first.id, bookTitleSnapshot: first.title, studentName: "B", studentClass: "5-A")
            context.insert(first); context.insert(second); context.insert(copy); context.insert(loan); context.insert(reservation)
            try context.save()
            let primary = try CatalogMaintenance.merge([first, second], context: context)
            #expect(try context.fetchCount(FetchDescriptor<CatalogBook>()) == 1)
            #expect(primary.quantity == 3)
            #expect(copy.bookID == primary.id)
            #expect(loan.bookID == primary.id)
            #expect(reservation.bookID == primary.id)
        }
    }

    @Test func differentValidEditionsCannotMerge() throws {
        let context = try context()
        let first = CatalogBook(book: Book(title: "Eser", author: "Y", isbn: "9789750718434"))
        let second = CatalogBook(book: Book(title: "Eser", author: "Y", isbn: "9786053607021"))
        #expect(ISBNFormatter.isValidISBN13(first.isbn ?? ""))
        #expect(ISBNFormatter.isValidISBN13(second.isbn ?? ""))
        context.insert(first); context.insert(second); try context.save()
        #expect(throws: SchoolLibraryService.OperationError.self) { try CatalogMaintenance.merge([first, second], context: context) }
        #expect(try context.fetchCount(FetchDescriptor<CatalogBook>()) == 2)
    }

    @Test func corruptionCannotSilentlyDropOperationalRecords() throws {
        var writer = ZIPWriter()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        writer.add(name: "katalog.json", data: try encoder.encode([Book(title: "Eser", author: "Y")]))
        writer.add(name: "nushalar.json", data: Data("broken".utf8))
        #expect(throws: (any Error).self) { try FullArchive.readValidated(data: writer.finalize()) }
    }

    @Test func roleGateBlocksMergeBeforeMutation() throws {
        let role = YetkiDurumu.shared
        let oldLock = role.kilitEtkin
        role.kilitEtkin = true; role.gorevliyeGec()
        defer { role.kilitEtkin = oldLock }
        let context = try context()
        let first = CatalogBook(book: Book(title: "Eser", author: "Y"))
        let second = CatalogBook(book: Book(title: "Eser", author: "Y"))
        context.insert(first); context.insert(second); try context.save()
        #expect(throws: SchoolLibraryService.OperationError.self) { try CatalogMaintenance.merge([first, second], context: context) }
        #expect(try context.fetchCount(FetchDescriptor<CatalogBook>()) == 2)
    }
    @Test func failedHistoryWriteKeepsCommittedLoanInDurableOutbox() throws {
        try isolatedMetadata {
            let context = try context()
            let book = CatalogBook(book: Book(title: "Eser", author: "Y"))
            context.insert(book); try context.save()
            let previousDirectory = LoanHistoryStore.directoryOverride
            let blocked = previousDirectory!.appendingPathComponent("blocked")
            try Data([1]).write(to: blocked)
            LoanHistoryStore.directoryOverride = blocked
            let loan = try SchoolLibraryService.lend(book: book, person: "A", className: "", context: context)
            #expect(try context.fetchCount(FetchDescriptor<ActiveLoan>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<LibraryEventOutbox>()) == 1)
            #expect(SchoolLibraryService.pendingHistoryWarning != nil)
            #expect(try SchoolLibraryService.historySnapshot(context: context).count == 1)
            LoanHistoryStore.directoryOverride = previousDirectory
            try SchoolLibraryService.flushHistoryOutbox(context: context)
            #expect(LoanHistoryStore.all.count == 1)
            #expect(LoanHistoryStore.all.first?.bookID == loan.bookID)
            let fresh = ModelContext(context.container)
            #expect(try fresh.fetchCount(FetchDescriptor<LibraryEventOutbox>()) == 0)
            #expect(SchoolLibraryService.pendingHistoryWarning == nil)
        }
    }

    @Test func historyFlushAfterInterruptedAcknowledgementIsIdempotent() throws {
        try isolatedMetadata {
            let context = try context()
            let event = LoanEvent(bookID: UUID(), bookTitle: "Eser", person: "A", kind: .lent, date: .now)
            try LoanHistoryStore.recordVerified(event)
            context.insert(try LibraryEventOutbox(event: event)); try context.save()
            try SchoolLibraryService.flushHistoryOutbox(context: context)
            try SchoolLibraryService.flushHistoryOutbox(context: context)
            #expect(LoanHistoryStore.all.count == 1)
            #expect(LoanHistoryStore.all.first?.id == event.id)
            #expect(try ModelContext(context.container).fetchCount(FetchDescriptor<LibraryEventOutbox>()) == 0)
        }
    }

    @Test func corruptMetadataCannotBeSilentlyOverwritten() throws {
        try isolatedMetadata {
            let students = StudentStore.storageURL!
            let corrupt = Data("broken-existing-json".utf8)
            try corrupt.write(to: students)
            #expect(throws: (any Error).self) { try StudentStore.addVerified(Student(name: "A", number: "1", className: "5-A")) }
            #expect(try Data(contentsOf: students) == corrupt)
            #expect(throws: (any Error).self) { try FullArchive.snapshot(context: context()) }
        }
    }

    @Test func historyDoesNotDiscardOlderSchoolYears() throws {
        try isolatedMetadata {
            let id = UUID()
            let events = (0..<5001).map { index in
                LoanEvent(bookID: id, bookTitle: "Eser", person: "A", kind: .lent, date: Date(timeIntervalSince1970: Double(index)))
            }
            try LoanHistoryStore.replaceAll(events)
            try LoanHistoryStore.recordVerified(LoanEvent(bookID: id, bookTitle: "Eser", person: "B", kind: .returned, date: .now))
            #expect(LoanHistoryStore.all.count == 5002)
            #expect(LoanHistoryStore.all.contains { $0.id == events[0].id })
        }
    }

    @Test func sameNameReadingScoresRemainSeparate() {
        let first = UUID(), second = UUID(), book = UUID()
        let events = [
            LoanEvent(bookID: book, bookTitle: "Eser", person: "Ali", kind: .returned, date: .now, studentID: first, classSnapshot: "5-A", readingCompleted: true),
            LoanEvent(bookID: book, bookTitle: "Eser", person: "Ali", kind: .returned, date: .now, wasLate: true, studentID: second, classSnapshot: "5-B", readingCompleted: true)
        ]
        #expect(OkumaPuani.siralama(events).count == 2)
        #expect(OkumaPuani.puan(for: first, events: events) == 10)
        #expect(OkumaPuani.puan(for: second, events: events) == 3)
        #expect(OkumaPuani.puan(for: "Ali", events: events) == 0)
    }

    @Test func readingCompletionIsExplicitAndNeverAddedForTextbooks() throws {
        try isolatedMetadata {
            let context = try context()
            let student = Student(name: "Örnek Öğrenci", number: "123", className: "7/A")
            try StudentStore.replaceAllVerified([student])
            let library = CatalogBook(book: Book(title: "Roman", author: "Y", quantity: 1))
            let textbook = CatalogBook(book: Book(title: "Ders kitabı", author: "Y", quantity: 1, isTextbook: true))
            context.insert(library); context.insert(textbook); try context.save()
            let one = try SchoolLibraryService.lend(book: library, person: student.name, className: student.className, context: context, studentID: student.id)
            let oneID = one.id
            _ = try SchoolLibraryService.returnLoan(one, context: context)
            #expect(OkumaPuani.siralama(try SchoolLibraryService.historySnapshot(context: context)).isEmpty)
            let two = try SchoolLibraryService.lend(book: library, person: student.name, className: student.className, context: context, studentID: student.id)
            let twoID = two.id
            _ = try SchoolLibraryService.returnLoan(two, context: context, readingCompleted: true)
            let three = try SchoolLibraryService.lend(book: textbook, person: student.name, className: student.className, context: context, studentID: student.id, kind: "textbook")
            let threeID = three.id
            _ = try SchoolLibraryService.returnLoan(three, context: context, readingCompleted: true)
            let events = try SchoolLibraryService.historySnapshot(context: context)
            #expect(events.first { $0.loanID == oneID && $0.kind == .returned }?.readingCompleted == nil)
            #expect(events.first { $0.loanID == twoID && $0.kind == .returned }?.readingCompleted == true)
            #expect(events.first { $0.loanID == threeID && $0.kind == .returned }?.readingCompleted == nil)
            #expect(OkumaPuani.puan(for: student.id, events: events) == 10)
            let roundTrip = try JSONDecoder().decode([LoanEvent].self, from: JSONEncoder().encode(events))
            #expect(OkumaPuani.puan(for: student.id, events: roundTrip) == 10)
        }
    }

    @Test func malformedCatalogRowCannotBecomeEmptySuccessfulRestore() throws {
        var writer = ZIPWriter()
        writer.add(name: "katalog.json", data: Data("[{\"title\":null}]".utf8))
        #expect(throws: FullArchive.ValidationError.self) { try FullArchive.readValidated(data: writer.finalize()) }
    }

    @Test func scanReceiptSurvivesFullArchive() throws {
        let book = Book(title: "Eser", author: "Y")
        let receipt = ScanWriteReceipt(operationID: UUID(), bookID: book.id, addedCopies: 2, inserted: false)
        let contents = ArchiveContents(books: [book], scanReceipts: [ArchivedScanReceipt(receipt)])
        let restored = try FullArchive.readValidated(data: FullArchive.build(contents))
        #expect(restored.scanReceipts.first?.operationID == receipt.operationID)
        #expect(restored.scanReceipts.first?.addedCopies == 2)
    }


    @Test func missingSelectedRecoveryStoreCannotOpenAnEmptyReplacement() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: StoreRecovery.selectedStoreKey)
        defer {
            if let previous { defaults.set(previous, forKey: StoreRecovery.selectedStoreKey) }
            else { defaults.removeObject(forKey: StoreRecovery.selectedStoreKey) }
        }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let missing = root.appendingPathComponent("RecoveredStores/missing-\(UUID().uuidString).store")
        defaults.set(missing.path, forKey: StoreRecovery.selectedStoreKey)
        #expect(throws: SchoolLibraryService.OperationError.self) { try StoreRecovery.validatedSelectedStoreURL() }
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        #expect(throws: SchoolLibraryService.OperationError.self) { try StoreRecovery.selectedStoreURL }
    }

    @Test func invalidSelectedRecoveryPathCannotFallBackToDefaultStore() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: StoreRecovery.selectedStoreKey)
        defer {
            if let previous { defaults.set(previous, forKey: StoreRecovery.selectedStoreKey) }
            else { defaults.removeObject(forKey: StoreRecovery.selectedStoreKey) }
        }
        defaults.set("/tmp/untrusted-library.store", forKey: StoreRecovery.selectedStoreKey)
        #expect(throws: SchoolLibraryService.OperationError.self) { try StoreRecovery.validatedSelectedStoreURL() }
        defaults.removeObject(forKey: StoreRecovery.selectedStoreKey)
        #expect(try StoreRecovery.validatedSelectedStoreURL() == nil)
    }

    @Test func failedRecoveryGateRestoresRawMetadataAndPreservesPointer() throws {
        try isolatedMetadata {
            let defaults = UserDefaults.standard
            let previous = defaults.object(forKey: StoreRecovery.selectedStoreKey)
            defer {
                if let previous { defaults.set(previous, forKey: StoreRecovery.selectedStoreKey) }
                else { defaults.removeObject(forKey: StoreRecovery.selectedStoreKey) }
            }
            let original = Data("existing-corrupt-student-json".utf8)
            let studentURL = StudentStore.storageURL!
            try original.write(to: studentURL)
            let originalMember = Member(name: "Önceki Üye")
            try MemberStore.replaceAllVerified([originalMember])
            let oldHistory = LoanEvent(bookID: UUID(), bookTitle: "Önceki", person: "A", kind: .returned, date: .now)
            try LoanHistoryStore.replaceAll([oldHistory])
            let beforePointer = "preserved-invalid-pointer"
            defaults.set(beforePointer, forKey: StoreRecovery.selectedStoreKey)
            let incoming = ArchiveContents(books: [Book(title: "Kurtarılan", author: "Y")], students: [Student(name: "Yeni", className: "5-A")])
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try StoreRecovery.restore(incoming, verify: { _ in throw SchoolLibraryService.OperationError(message: "Doğrulama kapısı hatası") })
            }
            #expect(try Data(contentsOf: studentURL) == original)
            #expect(try MemberStore.allVerified().map(\.id) == [originalMember.id])
            #expect(try LoanHistoryStore.allVerified().map(\.id) == [oldHistory.id])
            #expect(defaults.string(forKey: StoreRecovery.selectedStoreKey) == beforePointer)
        }
    }

    @Test func recoveryConvertsLegacyLoanBeforeActivatingValidatedStore() throws {
        try isolatedMetadata {
            let defaults = UserDefaults.standard
            let previous = defaults.object(forKey: StoreRecovery.selectedStoreKey)
            defer {
                if let previous { defaults.set(previous, forKey: StoreRecovery.selectedStoreKey) }
                else { defaults.removeObject(forKey: StoreRecovery.selectedStoreKey) }
            }
            let student = Student(name: "Ali", number: "1", className: "5-A")
            let book = Book(title: "Eski Ödünç", author: "Y", loanedTo: student.name, loanDueDate: .now)
            let recovered = try StoreRecovery.restore(ArchiveContents(books: [book], students: [student]))
            let context = recovered.mainContext
            #expect(try context.fetchCount(FetchDescriptor<ActiveLoan>()) == 1)
            #expect(try context.fetch(FetchDescriptor<ActiveLoan>()).first?.studentID == student.id)
            #expect(try context.fetch(FetchDescriptor<CatalogBook>()).first?.loanedTo == nil)
            #expect(try StoreRecovery.validatedSelectedStoreURL() != nil)
        }
    }


    @Test func repeatedLoanOperationCreatesOneLoanAndClosedReplayIsRejected() throws {
        try isolatedMetadata {
            let context = try context()
            let book = CatalogBook(book: Book(title: "Eser", author: "Y", quantity: 3))
            context.insert(book); try context.save()
            let operation = UUID()
            let first = try SchoolLibraryService.lend(book: book, person: "A", className: "5-A", context: context, operationID: operation)
            let retry = try SchoolLibraryService.lend(book: book, person: "A", className: "5-A", context: context, operationID: operation)
            #expect(first.id == operation && retry.id == first.id)
            #expect(try context.fetchCount(FetchDescriptor<ActiveLoan>()) == 1)
            #expect(LoanHistoryStore.all.filter { $0.id == operation }.count == 1)
            _ = try SchoolLibraryService.returnLoan(first, context: context)
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try SchoolLibraryService.lend(book: book, person: "A", className: "5-A", context: context, operationID: operation)
            }
            #expect(try context.fetchCount(FetchDescriptor<ActiveLoan>()) == 0)
        }
    }

    @Test func sameLoanOperationCannotChangeItsPersonOrBook() throws {
        try isolatedMetadata {
            let context = try context()
            let first = CatalogBook(book: Book(title: "Bir", author: "Y", quantity: 3))
            let second = CatalogBook(book: Book(title: "İki", author: "Y", quantity: 3))
            context.insert(first); context.insert(second); try context.save()
            let operation = UUID()
            _ = try SchoolLibraryService.lend(book: first, person: "A", className: "5-A", context: context, operationID: operation)
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try SchoolLibraryService.lend(book: first, person: "B", className: "5-A", context: context, operationID: operation)
            }
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try SchoolLibraryService.lend(book: second, person: "A", className: "5-A", context: context, operationID: operation)
            }
            #expect(try context.fetchCount(FetchDescriptor<ActiveLoan>()) == 1)
        }
    }

    @Test func explicitMemberNeverBorrowsAStudentsIdentityOrReservation() throws {
        try isolatedMetadata {
            let student = Student(name: "Ali", number: "1", className: "5-A")
            let member = Member(name: "Ali", memberNumber: "U-1")
            try StudentStore.replaceAllVerified([student]); try MemberStore.replaceAllVerified([member])
            let context = try context()
            let heldBook = CatalogBook(book: Book(title: "Ayrılmış", author: "Y"))
            let freeBook = CatalogBook(book: Book(title: "Serbest", author: "Y"))
            let hold = Reservation(bookID: heldBook.id, bookTitleSnapshot: heldBook.title, studentName: student.name, studentClass: student.className)
            hold.studentID = student.id; hold.notifiedAt = .now; hold.expiresAt = Date.now.addingTimeInterval(86_400)
            context.insert(heldBook); context.insert(freeBook); context.insert(hold); try context.save()
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try SchoolLibraryService.lend(book: heldBook, person: member.name, className: "", context: context, memberID: member.id)
            }
            #expect(!hold.isClosed)
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try SchoolLibraryService.lend(book: freeBook, person: "Ali", className: "5-A", context: context)
            }
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try SchoolLibraryService.lend(book: freeBook, person: "Ali", className: "5-A", context: context, studentID: student.id, memberID: member.id)
            }
            let memberLoan = try SchoolLibraryService.lend(book: freeBook, person: "Ali", className: "5-A", context: context, memberID: member.id)
            #expect(memberLoan.memberID == member.id && memberLoan.studentID == nil)
            #expect(memberLoan.studentClass.isEmpty && memberLoan.identitySource == "member")
            let studentLoan = try SchoolLibraryService.lend(book: heldBook, person: student.name, className: student.className, context: context, studentID: student.id)
            #expect(studentLoan.studentID == student.id && studentLoan.memberID == nil)
            #expect(hold.isClosed)
        }
    }

    @Test func sameNameMembersAndStudentHaveIndependentQuotaAndExactReturns() throws {
        try isolatedMetadata {
            let defaults = UserDefaults.standard
            let previousLimit = defaults.object(forKey: OduncKotasi.genelSinirAnahtari)
            let previousBlock = defaults.object(forKey: OduncKotasi.gecikmeEngeliAnahtari)
            defaults.set(1, forKey: OduncKotasi.genelSinirAnahtari); defaults.set(false, forKey: OduncKotasi.gecikmeEngeliAnahtari)
            defer {
                if let previousLimit { defaults.set(previousLimit, forKey: OduncKotasi.genelSinirAnahtari) } else { defaults.removeObject(forKey: OduncKotasi.genelSinirAnahtari) }
                if let previousBlock { defaults.set(previousBlock, forKey: OduncKotasi.gecikmeEngeliAnahtari) } else { defaults.removeObject(forKey: OduncKotasi.gecikmeEngeliAnahtari) }
            }
            let first = Member(name: "Ali", memberNumber: "U-1"), second = Member(name: "Ali", memberNumber: "U-2")
            let student = Student(name: "Ali", number: "1", className: "5-A")
            try MemberStore.replaceAllVerified([first, second]); try StudentStore.replaceAllVerified([student])
            let context = try context()
            let book = CatalogBook(book: Book(title: "Eser", author: "Y", quantity: 4))
            context.insert(book); try context.save()
            _ = try SchoolLibraryService.lend(book: book, person: first.name, className: "", context: context, memberID: first.id)
            _ = try SchoolLibraryService.lend(book: book, person: second.name, className: "", context: context, memberID: second.id)
            _ = try SchoolLibraryService.lend(book: book, person: student.name, className: student.className, context: context, studentID: student.id)
            #expect(throws: OduncMerkezi.OduncHatasi.self) {
                try SchoolLibraryService.lend(book: book, person: first.name, className: "", context: context, memberID: first.id)
            }
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try SchoolLibraryService.giveBack(book: book, person: "Ali", context: context)
            }
            _ = try SchoolLibraryService.giveBack(book: book, person: second.name, context: context, memberID: second.id)
            let active = try context.fetch(FetchDescriptor<ActiveLoan>())
            #expect(active.count == 2)
            #expect(active.contains { $0.memberID == first.id })
            #expect(active.contains { $0.studentID == student.id })
            #expect(!active.contains { $0.memberID == second.id })
            _ = try SchoolLibraryService.giveBack(book: book, person: student.name, studentID: student.id, context: context, readingCompleted: true)
            #expect(LoanHistoryStore.events(for: student.id).count == 2)
            #expect(OkumaPuani.siralama(LoanHistoryStore.all).count == 1)
            #expect(OkumaPuani.puan(for: student.id, events: LoanHistoryStore.all) == 10)
            #expect(LoanHistoryStore.people().count == 3)
        }
    }

    @Test func manualIdentityRemainsManualAcrossLegacyMigration() throws {
        try isolatedMetadata {
            let student = Student(name: "Ali", number: "1", className: "5-A")
            try StudentStore.replaceAllVerified([student])
            try MemberStore.replaceAllVerified([Member(name: "Ali", memberNumber: "U-1")])
            let context = try context()
            let book = CatalogBook(book: Book(title: "Elle", author: "Y", quantity: 2))
            context.insert(book); try context.save()
            let loan = try SchoolLibraryService.lend(book: book, person: "Ali", className: "5-A", context: context, resolveKnownStudent: false)
            #expect(loan.studentID == nil && loan.memberID == nil && loan.identitySource == "manual")
            #expect(loan.needsIdentityReview)
            #expect(try SchoolLibraryService.migrateLegacyLoans(context: context) == 0)
            #expect(loan.studentID == nil && loan.memberID == nil && loan.identitySource == "manual")
            _ = try SchoolLibraryService.giveBack(book: book, person: "Ali", className: "5-A", context: context, loanID: loan.id)
            #expect(OkumaPuani.siralama(LoanHistoryStore.all).isEmpty)
        }
    }

    @Test func memberArchivePreservesIdentityAndBlocksActiveMemberDeletion() throws {
        try isolatedMetadata {
            let member = Member(name: "Ali", memberNumber: "U-1")
            try MemberStore.replaceAllVerified([member])
            let context = try context()
            let book = CatalogBook(book: Book(title: "Eser", author: "Y"))
            context.insert(book); try context.save()
            let loan = try SchoolLibraryService.lend(book: book, person: member.name, className: "", context: context, memberID: member.id)
            let contents = try FullArchive.snapshot(context: context)
            let restored = try FullArchive.readValidated(data: FullArchive.buildVerified(contents))
            #expect(restored.activeLoans.first?.memberID == member.id)
            #expect(restored.activeLoans.first?.identitySource == "member")
            #expect(restored.activeLoans.first?.makeActiveLoan().memberID == member.id)
            #expect(restored.loanEvents.first?.memberID == member.id)
            #expect(throws: SchoolLibraryService.OperationError.self) { try MemberStore.removeVerified(id: member.id, context: context) }
            #expect(try MemberStore.allVerified().map(\.id) == [member.id])
            _ = try SchoolLibraryService.returnLoan(loan, context: context)
            try MemberStore.removeVerified(id: member.id, context: context)
            #expect(try MemberStore.allVerified().isEmpty)
            #expect(LoanHistoryStore.all.filter { $0.memberID == member.id }.count == 2)
        }
    }

    @Test func legacyNameSharedByMemberAndStudentIsFlaggedWithoutGuessing() throws {
        try isolatedMetadata {
            try StudentStore.replaceAllVerified([Student(name: "Ali", number: "1", className: "5-A")])
            try MemberStore.replaceAllVerified([Member(name: "Ali", memberNumber: "U-1")])
            let context = try context()
            let book = CatalogBook(book: Book(title: "Eski", author: "Y", loanedTo: "Ali", loanDueDate: .now))
            context.insert(book); try context.save()
            #expect(try SchoolLibraryService.migrateLegacyLoans(context: context) == 1)
            let loan = try context.fetch(FetchDescriptor<ActiveLoan>()).first
            #expect(loan?.studentID == nil && loan?.memberID == nil)
            #expect(loan?.needsIdentityReview == true && loan?.identitySource == "legacy")
        }
    }

    @Test func oldArchiveCannotReopenReturnedLoanInLiveCatalog() throws {
        try isolatedMetadata {
            let context = try context()
            let book = CatalogBook(book: Book(title: "Canlı", author: "Y", quantity: 2))
            context.insert(book); try context.save()
            let loan = try SchoolLibraryService.lend(book: book, person: "A", className: "", context: context)
            let old = try FullArchive.snapshot(context: context)
            _ = try SchoolLibraryService.returnLoan(loan, context: context)
            let historyIDs = Set(LoanHistoryStore.all.map(\.id))
            #expect(throws: SchoolLibraryService.OperationError.self) { try ArchiveLoanRestorer.restoreAll(old, context: context) }
            #expect(try context.fetchCount(FetchDescriptor<ActiveLoan>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<CatalogBook>()) == 1)
            #expect(Set(LoanHistoryStore.all.map(\.id)) == historyIDs)
        }
    }

    @Test func archiveRejectsDuplicateActivePhysicalCopyBeforeMutation() throws {
        try isolatedMetadata {
            let book = Book(title: "Eser", author: "Y", quantity: 2)
            let copy = BookCopy(bookID: book.id, accessionCode: "D-1")
            let first = ActiveLoan(bookID: book.id, bookTitleSnapshot: book.title, studentName: "A", studentClass: "", dueDate: .now)
            let second = ActiveLoan(bookID: book.id, bookTitleSnapshot: book.title, studentName: "B", studentClass: "", dueDate: .now)
            first.copyID = copy.id; second.copyID = copy.id
            let contents = ArchiveContents(books: [book], activeLoans: [ArchivedLoan(first), ArchivedLoan(second)], copies: [ArchivedCopy(copy)])
            #expect(throws: FullArchive.ValidationError.self) { try FullArchive.readValidated(data: FullArchive.buildVerified(contents)) }
            let context = try context()
            #expect(throws: SchoolLibraryService.OperationError.self) { try ArchiveLoanRestorer.restoreAll(contents, context: context) }
            #expect(try context.fetchCount(FetchDescriptor<CatalogBook>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<ActiveLoan>()) == 0)
        }
    }

    @Test func graduationArchiveAndRecallPreserveUUIDAndOpenDebt() throws {
        try isolatedMetadata {
            let senior = Student(name: "Mezun", number: "12", className: "12-A")
            let junior = Student(name: "Devam", number: "5", className: "5-A")
            try StudentStore.replaceAllVerified([senior, junior])
            let context = try context()
            let book = CatalogBook(book: Book(title: "Borçlu kitap", author: "Y"))
            context.insert(book); try context.save()
            let loan = try SchoolLibraryService.lend(book: book, person: senior.name, className: senior.className, context: context, studentID: senior.id)
            let result = try SinifAtlatma.uygulaVerified(SinifAtlatma.plan([senior, junior], sonKademe: 12), context: context)
            #expect(result.mezun == 1 && result.atlayan == 1)
            #expect(try StudentStore.allVerified().map(\.id) == [junior.id])
            #expect(try GraduatedStudentStore.allVerified().first?.student == senior)
            #expect(loan.studentID == senior.id && loan.studentClass == "Mezun")
            let restored = try FullArchive.readValidated(data: FullArchive.buildVerified(FullArchive.snapshot(context: context)))
            #expect(restored.graduatedStudents.first?.id == senior.id)
            #expect(restored.activeLoans.first?.studentID == senior.id)
            try GraduatedStudentStore.recall(id: senior.id, className: "Hazırlık", context: context)
            #expect(try StudentStore.allVerified().contains { $0.id == senior.id && $0.className == "Hazırlık" })
            #expect(try GraduatedStudentStore.allVerified().isEmpty)
            #expect(loan.studentID == senior.id && loan.studentClass == "Hazırlık")
            #expect(LoanHistoryStore.events(for: senior.id).first?.classSnapshot == "12-A")
        }
    }

    @Test func invalidGraduateRecallAndCorruptGraduateBookDoNotMutateStudents() throws {
        try isolatedMetadata {
            let student = Student(name: "Mezun", className: "12-A")
            try GraduatedStudentStore.replaceAllVerified([.init(student: student, graduatedAt: .now)])
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try GraduatedStudentStore.recall(id: student.id, className: " ", context: context())
            }
            #expect(try StudentStore.allVerified().isEmpty)
            let data = Data("broken-graduate-book".utf8)
            try data.write(to: GraduatedStudentStore.storageURL!)
            #expect(throws: (any Error).self) { try SinifAtlatma.uygulaVerified([], context: context()) }
            #expect(try Data(contentsOf: GraduatedStudentStore.storageURL!) == data)
        }
    }

    @Test func inventorySnapshotSurvivesNewLoansAndArchiveRoundtrip() throws {
        try isolatedMetadata {
            let context = try context()
            let book = CatalogBook(book: Book(title: "Sayım", author: "Y", quantity: 5))
            let lost = BookCopy(bookID: book.id, accessionCode: "K", status: "Kayıp")
            let repair = BookCopy(bookID: book.id, accessionCode: "O", status: "Onarımda")
            let withdrawn = BookCopy(bookID: book.id, accessionCode: "D", status: "Düşüldü")
            context.insert(book); context.insert(lost); context.insert(repair); context.insert(withdrawn); try context.save()
            let frozen = InventorySnapshot.capture(books: [book], loans: [], copies: [lost, repair, withdrawn], reservations: [], location: "Tümü")
            #expect(frozen.first?.stock.available == 2)
            #expect(frozen.first?.stock.lost == 1 && frozen.first?.stock.repair == 1 && frozen.first?.stock.withdrawn == 1)
            try InventorySessionStore.saveVerified(.init(location: "Tümü", startedAt: .now, expected: frozen))
            _ = try SchoolLibraryService.lend(book: book, person: "A", className: "", context: context)
            #expect(SchoolLibraryService.stock(for: book, context: context).available == 1)
            #expect(try InventorySessionStore.loadVerified().expected?.first?.stock.available == 2)
            let archive = try FullArchive.readValidated(data: FullArchive.buildVerified(FullArchive.snapshot(context: context)))
            let data = try #require(archive.supportingFiles["SayimOturumu.json"])
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            #expect(try decoder.decode(InventorySession.self, from: data).expected?.first?.stock.available == 2)
        }
    }

    @Test func corruptInventorySessionCannotBeSilentlyReplaced() throws {
        try isolatedMetadata {
            let url = InventorySessionStore.directoryOverride!.appendingPathComponent("SayimOturumu.json")
            let broken = Data("invalid-existing-inventory".utf8); try broken.write(to: url)
            #expect(throws: (any Error).self) { try InventorySessionStore.saveVerified(.init()) }
            #expect(try Data(contentsOf: url) == broken)
        }
    }

    @Test func textbookBatchReturnPreservesPeriodAndRepairStockAndFailedSelections() throws {
        try isolatedMetadata {
            let context = try context()
            let book = CatalogBook(book: Book(title: "Ders", author: "Y", quantity: 2, isTextbook: true))
            context.insert(book); try context.save()
            let first = try SchoolLibraryService.lend(book: book, person: "A", className: "9-A", context: context, kind: "textbook", periodSnapshot: "2026–2027")
            let second = try SchoolLibraryService.lend(book: book, person: "B", className: "9-A", context: context, kind: "textbook", periodSnapshot: "2026–2027")
            let hold = Reservation(bookID: book.id, bookTitleSnapshot: book.title, studentName: "C", studentClass: "9-A")
            context.insert(hold); try context.save()
            let result = try TextbookOperations.collect(loanIDs: [first.id, second.id], conditions: [first.id: "Onarım gerekli", second.id: "Geçersiz"], context: context)
            #expect(result.collectedIDs == [first.id])
            #expect(result.failures.keys.contains(second.id))
            #expect(try context.fetchCount(FetchDescriptor<ActiveLoan>()) == 1)
            #expect(SchoolLibraryService.stock(for: book, context: context).repair == 1)
            #expect(SchoolLibraryService.stock(for: book, context: context).available == 0)
            #expect(hold.notifiedAt == nil)
            let returned = try #require(LoanHistoryStore.all.first { $0.kind == .returned })
            #expect(returned.periodSnapshot == "2026–2027" && returned.returnedCondition == "Onarım gerekli")
            #expect(OkumaPuani.siralama(LoanHistoryStore.all).isEmpty)
            let archive = try FullArchive.readValidated(data: FullArchive.buildVerified(FullArchive.snapshot(context: context)))
            #expect(archive.activeLoans.first?.periodSnapshot == "2026–2027")
            #expect(archive.loanEvents.contains { $0.returnedCondition == "Onarım gerekli" && $0.periodSnapshot == "2026–2027" })
        }
    }

    @Test func replacementHistoryOutboxUpdatesExistingEventIdempotently() throws {
        try isolatedMetadata {
            let context = try context()
            let original = LoanEvent(bookID: UUID(), bookTitle: "Eski", person: "A", kind: .lent, date: .now)
            try LoanHistoryStore.replaceAll([original])
            var changed = original; changed.bookID = UUID(); changed.bookTitle = "Birleşmiş"
            context.insert(try LibraryEventOutbox(event: changed, replacesExisting: true)); try context.save()
            #expect(try SchoolLibraryService.historySnapshot(context: context).first?.bookID == changed.bookID)
            try SchoolLibraryService.flushHistoryOutbox(context: context)
            try SchoolLibraryService.flushHistoryOutbox(context: context)
            #expect(LoanHistoryStore.all.count == 1 && LoanHistoryStore.all.first?.bookID == changed.bookID)
        }
    }

    @Test func reservationExpiryCancellationAndDeliveryRemainDistinctInArchive() throws {
        try isolatedMetadata {
            let context = try context(), now = Date.now
            let student = Student(name: "A", number: "1", className: "5-A")
            try StudentStore.replaceAllVerified([student])
            let book = CatalogBook(book: Book(title: "Sıra", author: "Y"))
            let expired = Reservation(bookID: book.id, bookTitleSnapshot: book.title, studentName: "Eski", studentClass: "5-A")
            expired.notifiedAt = now.addingTimeInterval(-86_400); expired.expiresAt = now.addingTimeInterval(-1)
            let waiting = Reservation(bookID: book.id, bookTitleSnapshot: book.title, studentName: "Bekleyen", studentClass: "5-A")
            context.insert(book); context.insert(expired); context.insert(waiting); try context.save()
            _ = try SchoolLibraryService.refreshReservations(context: context, now: now)
            #expect(expired.isClosed && expired.closureKind == "expired" && expired.closedAt != nil)
            #expect(waiting.notifiedAt != nil && !waiting.isClosed)
            try SchoolLibraryService.cancelReservation(waiting, context: context, now: now)
            #expect(waiting.isClosed && waiting.closureKind == "cancelled" && waiting.closedAt != nil)
            #expect(throws: SchoolLibraryService.OperationError.self) { try SchoolLibraryService.cancelReservation(waiting, context: context) }
            let own = Reservation(bookID: book.id, bookTitleSnapshot: book.title, studentName: student.name, studentClass: student.className)
            own.studentID = student.id; own.notifiedAt = now; own.expiresAt = now.addingTimeInterval(86_400)
            context.insert(own); try context.save()
            _ = try SchoolLibraryService.lend(book: book, person: student.name, className: student.className, context: context, studentID: student.id)
            #expect(own.isClosed && own.closureKind == "delivered" && own.closedAt != nil)
            let archive = try FullArchive.readValidated(data: FullArchive.buildVerified(FullArchive.snapshot(context: context)))
            #expect(Set(archive.reservations.compactMap(\.closureKind)) == ["expired", "cancelled", "delivered"])
            #expect(archive.reservations.allSatisfy { $0.closedAt != nil })
        }
    }

    @Test func manifestCannotPermitUnhashedExtraOperationalContent() throws {
        let contents = ArchiveContents(books: [Book(title: "Eser", author: "Y")])
        var zip = ZIPWriter()
        let source = try FullArchive.buildVerified(contents)
        for entry in ZIPReader.entries(in: source) { zip.add(name: entry.name, data: entry.data) }
        zip.add(name: "dogrulanmamis-icerik.json", data: Data("[]".utf8))
        #expect(throws: FullArchive.ValidationError.self) { try FullArchive.readValidated(data: zip.finalize()) }
    }

    @Test func studentImportReportsRowsAndRequiresExplicitIdentityChoice() throws {
        try isolatedMetadata {
            let existing = Student(name: "Ali", number: "17", className: "5-A")
            try StudentStore.replaceAllVerified([existing])
            let preview = try StudentImportService.preview(rows: [["Ad", "No", "Sınıf"], ["Ali", "17", "6-A"], ["", "18", "6-A"], ["Veli", "19", ""]],
                mapping: .init(nameColumn: 0, numberColumn: 1, classColumn: 2))
            #expect(preview.errors.map(\.line) == [3, 4])
            // Tek aday + aynı okul numarası: kimlik varsayılan olarak korunur, karar sorulmaz (Dolaşım turu).
            #expect(preview.conflicts.isEmpty && preview.autoUpdates.count == 1)
            let context = try context()
            let result = try StudentImportService.apply(preview, context: context)
            #expect(result.added == 0 && result.updated == 1 && result.skipped == 2)
            #expect(try StudentStore.allVerified().first?.id == existing.id)
            #expect(try StudentStore.allVerified().first?.className == "6-A")
        }
    }

    @Test func importUndoSurvivesReloadPreservesUUIDAndUnrelatedStudents() throws {
        try isolatedMetadata {
            let existing = Student(name: "Ali", number: "17", className: "5-A")
            try StudentStore.replaceAllVerified([existing])
            let preview = try StudentImportService.preview(rows: [["Ali", "17", "6-A"], ["Ayşe", "18", "5-A"]],
                mapping: .init(nameColumn: 0, numberColumn: 1, classColumn: 2, hasHeader: false))
            let context = try context()
            _ = try StudentImportService.apply(preview, resolutions: [1: .update(existing.id)], context: context)
            let unrelated = Student(name: "Başka", number: "90", className: "7-A")
            _ = try StudentStore.addVerified(unrelated)
            #expect(try StudentImportStore.allVerified().last?.affectedIDs.count == 2)
            #expect(try StudentImportService.undoLast(context: context) == 2)
            #expect(Set(try StudentStore.allVerified().map(\.id)) == [existing.id, unrelated.id])
            #expect(try StudentStore.allVerified().first(where: { $0.id == existing.id }) == existing)
            #expect(try StudentImportStore.allVerified().last?.state == "undone")
        }
    }

    @Test func importUndoBlocksLiveDebtAndStaleStudentEdits() throws {
        try isolatedMetadata {
            let preview = try StudentImportService.preview(rows: [["Ayşe", "18", "5-A"]], mapping: .init(nameColumn: 0, numberColumn: 1, classColumn: 2, hasHeader: false))
            let context = try context()
            _ = try StudentImportService.apply(preview, context: context)
            let student = try #require(StudentStore.allVerified().first)
            let book = CatalogBook(book: Book(title: "Eser", author: "Y")); context.insert(book); try context.save()
            let loan = try SchoolLibraryService.lend(book: book, person: student.name, className: student.className, context: context, studentID: student.id)
            #expect(throws: SchoolLibraryService.OperationError.self) { try StudentImportService.undoLast(context: context) }
            #expect(try StudentStore.allVerified().count == 1)
            _ = try SchoolLibraryService.returnLoan(loan, context: context)
            var renamed = student; renamed.name = "Ayşe Yeni"
            try StudentStore.replaceAllVerified([renamed])
            #expect(throws: SchoolLibraryService.OperationError.self) { try StudentImportService.undoLast(context: context) }
            #expect(try StudentStore.allVerified().first?.name == "Ayşe Yeni")
        }
    }

    @Test func preparedImportAndJournalArchiveRemainRecoverable() throws {
        try isolatedMetadata {
            let before = Student(name: "Ali", number: "17", className: "5-A")
            var after = before; after.className = "6-A"
            let receipt = StudentImportReceipt(before: [before], after: [after], affectedIDs: [before.id])
            try StudentImportStore.replaceAllVerified([receipt]); try StudentStore.replaceAllVerified([after])
            let context = try context()
            let archive = try FullArchive.readValidated(data: FullArchive.buildVerified(FullArchive.snapshot(context: context)))
            let encoded = try #require(archive.supportingFiles[StudentImportStore.fileName])
            #expect(try StudentImportStore.validate(encoded).first?.id == receipt.id)
            #expect(try StudentImportService.undoLast(context: context) == 1)
            #expect(try StudentStore.allVerified() == [before])
        }
    }

    @Test func separateCopyLocationsCountAndMoveOnlyTheIdentifiedCopy() throws {
        let context = try context()
        let book = CatalogBook(book: Book(title: "Eser", author: "Y", location: "Dolap A • Raf 1", quantity: 2, shelf: "1", cabinet: "A"))
        let one = BookCopy(bookID: book.id, accessionCode: "D-1")
        let two = BookCopy(bookID: book.id, accessionCode: "D-2", cabinet: "B", shelf: "2")
        context.insert(book); context.insert(one); context.insert(two); try context.save()
        let full = InventorySnapshot.capture(books: [book], loans: [], copies: [one, two], reservations: [], location: "Tümü")
        let atA = InventorySnapshot.capture(books: [book], loans: [], copies: [one, two], reservations: [], location: one.effectivePlace(for: book))
        #expect(atA.first?.stock.total == 1 && atA.first?.stock.available == 1)
        #expect(atA.first?.copies.map(\.id) == [one.id])
        let session = InventorySession(scanned: ["copy:" + two.id.uuidString: 1], location: "Dolap A • Raf 1", expected: atA,
            name: "Denetim", operatorName: "Görevli", method: "Benzersiz demirbaş",
            observations: [.init(bookID: book.id, copyID: two.id, operatorName: "Görevli", method: "Demirbaş", observedLocation: "Dolap A • Raf 1", outsideScope: true)], catalogSnapshot: full)
        let preview = try InventoryMoveService.preview(session: session, location: "Dolap C • Raf 3", cabinet: "C", shelf: "3", context: context)
        #expect(preview.eligible.map(\.id) == [two.id])
        #expect(try InventoryMoveService.apply(preview, selectedIDs: [two.id], context: context) == 1)
        #expect(two.cabinet == "C" && two.shelf == "3")
        #expect(book.location == "Dolap A • Raf 1" && one.cabinet == nil)
        let dto = ArchivedCopy(two)
        #expect(dto.makeModel().effectivePlace(for: book) == "Dolap C · Raf 3")
    }

    /// Ayraç " • " iken başlamış sayımdaki nüsha yeri, yeni " · " biçimiyle "değişti" sayılmaz.
    @Test func eskiAyracliSayimNushasiTasinabilir() throws {
        let context = try context()
        let book = CatalogBook(book: Book(title: "Eser", author: "Y", quantity: 2, shelf: "1", cabinet: "A"))
        let two = BookCopy(bookID: book.id, accessionCode: "D-2", cabinet: "B", shelf: "2")
        context.insert(book); context.insert(two); try context.save()
        #expect(two.effectivePlace(for: book) == "Dolap B · Raf 2")
        var eski = InventorySnapshot.capture(books: [book], loans: [], copies: [two], reservations: [], location: "Tümü")
        eski[0].copies[0].location = "Dolap B • Raf 2"
        let session = InventorySession(scanned: ["copy:" + two.id.uuidString: 1], location: "Dolap A • Raf 1", expected: eski,
            name: "Denetim", operatorName: "Görevli", method: "Benzersiz demirbaş",
            observations: [.init(bookID: book.id, copyID: two.id, operatorName: "Görevli", method: "Demirbaş", observedLocation: "Dolap A • Raf 1", outsideScope: true)], catalogSnapshot: eski)
        let preview = try InventoryMoveService.preview(session: session, location: "Dolap C · Raf 3", cabinet: "C", shelf: "3", context: context)
        #expect(preview.eligible.map(\.id) == [two.id])
        #expect(preview.candidates.first?.sourcePlace == "Dolap B · Raf 2")
    }

    /// Eski ayraçla kaydedilmiş sayım konumu bugünkü seçeneğe taşınır; listede bulunan serbest yer adı korunur.
    @Test func eskiAyracliSayimKonumuTasinir() {
        let secenekler = ["Tümü", "Dolap 3 · Raf 2", "Salon • Pencere"]
        #expect(InventorySnapshot.guncelKonum("Dolap 3 • Raf 2", secenekler: secenekler) == "Dolap 3 · Raf 2")
        #expect(InventorySnapshot.guncelKonum("Salon • Pencere", secenekler: secenekler) == "Salon • Pencere")
        #expect(InventorySnapshot.guncelKonum("Dolap 9 • Raf 1", secenekler: secenekler) == "Dolap 9 • Raf 1")
        #expect(InventorySnapshot.guncelKonum("Tümü", secenekler: secenekler) == "Tümü")
    }

    @Test func inventoryMoveRejectsNewDebtAndRollsBackFailedSave() throws {
        let context = try context()
        let book = CatalogBook(book: Book(title: "Eser", author: "Y", location: "A", quantity: 1))
        let copy = BookCopy(bookID: book.id, accessionCode: "D-1"); context.insert(book); context.insert(copy); try context.save()
        let full = InventorySnapshot.capture(books: [book], loans: [], copies: [copy], reservations: [], location: "Tümü")
        let session = InventorySession(scanned: ["copy:" + copy.id.uuidString: 1], location: "B", expected: [], observations: [
            .init(bookID: book.id, copyID: copy.id, operatorName: "Görevli", method: "Demirbaş", observedLocation: "B", outsideScope: true)], catalogSnapshot: full)
        let preview = try InventoryMoveService.preview(session: session, location: "B", cabinet: "B", context: context)
        #expect(throws: CocoaError.self) { try InventoryMoveService.apply(preview, selectedIDs: [copy.id], context: context, persist: { throw CocoaError(.fileWriteOutOfSpace) }) }
        #expect(copy.cabinet == nil && book.location == "A")
        let loan = ActiveLoan(bookID: book.id, bookTitleSnapshot: book.title, studentName: "X", studentClass: "5-A", dueDate: .now)
        loan.copyID = copy.id; context.insert(loan); try context.save()
        #expect(throws: SchoolLibraryService.OperationError.self) { try InventoryMoveService.apply(preview, selectedIDs: [copy.id], context: context) }
        #expect(copy.cabinet == nil)
        let blocked = try InventoryMoveService.preview(session: session, location: "B", cabinet: "B", context: context)
        #expect(blocked.eligible.isEmpty && blocked.candidates.first?.reason != nil)
    }

    @Test func aggregateInventoryMoveRequiresAllCopiesAndSessionRoundtripKeepsEvidence() throws {
        try isolatedMetadata {
            let context = try context()
            let book = CatalogBook(book: Book(title: "Eser", author: "Y", location: "A", quantity: 3))
            context.insert(book); try context.save()
            let full = InventorySnapshot.capture(books: [book], loans: [], copies: [], reservations: [], location: "Tümü")
            var session = InventorySession(scanned: ["outside:" + book.id.uuidString: 1], location: "B", expected: [], name: "Ekim",
                operatorName: "Görevli", method: "ISBN nüsha sayımı", observations: [.init(bookID: book.id, operatorName: "Görevli", method: "ISBN", observedLocation: "B", outsideScope: true)], catalogSnapshot: full)
            #expect(try InventoryMoveService.preview(session: session, location: "B", context: context).eligible.isEmpty)
            session.scanned["outside:" + book.id.uuidString] = 3
            try InventorySessionStore.saveVerified(session)
            let read = try InventorySessionStore.loadVerified()
            #expect(read.name == "Ekim" && read.operatorName == "Görevli" && read.observations?.first?.outsideScope == true)
            let preview = try InventoryMoveService.preview(session: read, location: "B", context: context)
            #expect(try InventoryMoveService.apply(preview, selectedIDs: [book.id], context: context) == 1)
            #expect(book.location == "B")
        }
    }

    @Test func corruptGradeRulesFailClosedInsteadOfUsingDefaults() throws {
        try isolatedMetadata {
            let url = try #require(GradeLoanRuleStore.storageURL)
            try Data("bad-json".utf8).write(to: url)
            #expect(throws: DecodingError.self) { try GradeLoanRuleStore.allVerified() }
            let bad = [GradeLoanRule(gradePrefix: "5", maxConcurrentLoans: 100, loanDurationDays: 366)]
            #expect(throws: SchoolLibraryService.OperationError.self) { try GradeLoanRuleStore.saveVerified(bad) }
            #expect(try String(contentsOf: url, encoding: .utf8) == "bad-json")
        }
    }

    @Test func quotedCSVAndInterruptedPreparedImportKeepStudentState() throws {
        try isolatedMetadata {
            let rows = OgrenciCSVEslestirme.satirlar(Data("Ad;No;Sınıf\n\"Ali; Veli\";1;5-A\n\"Ayşe \"\"Yeni\"\"\";2;5-A".utf8))
            #expect(rows[1] == ["Ali; Veli", "1", "5-A"])
            #expect(rows[2] == ["Ayşe \"Yeni\"", "2", "5-A"])
            let student = Student(name: "Ali", number: "1", className: "5-A")
            var after = student; after.className = "6-A"
            try StudentStore.replaceAllVerified([student])
            try StudentImportStore.replaceAllVerified([.init(before: [student], after: [after], affectedIDs: [student.id])])
            #expect(try StudentImportService.undoLast(context: context()) == 0)
            #expect(try StudentStore.allVerified() == [student])
            #expect(try StudentImportStore.allVerified().last?.state == "undone")
        }
    }

    @Test func scopedInventoryCannotCountAnUnassignedLegacyLoanAsAvailable() {
        let book = CatalogBook(book: Book(title: "Eser", author: "Y", location: "Dolap A • Raf 1", quantity: 2, shelf: "1", cabinet: "A"))
        let one = BookCopy(bookID: book.id, accessionCode: "D-1")
        let two = BookCopy(bookID: book.id, accessionCode: "D-2", cabinet: "B", shelf: "2")
        let loan = ActiveLoan(bookID: book.id, bookTitleSnapshot: book.title, studentName: "Eski", studentClass: "", dueDate: .now)
        let scoped = InventorySnapshot.capture(books: [book], loans: [loan], copies: [one, two], reservations: [], location: two.effectivePlace(for: book))
        #expect(scoped.first?.stock.total == 1)
        #expect(scoped.first?.stock.loaned == 1 && scoped.first?.stock.available == 0)
        #expect(scoped.first?.unresolvedLoans == 1)
        let full = InventorySnapshot.capture(books: [book], loans: [loan], copies: [one, two], reservations: [], location: "Tümü")
        #expect(full.first?.stock.available == 1 && full.first?.unresolvedLoans == nil)
    }

}
