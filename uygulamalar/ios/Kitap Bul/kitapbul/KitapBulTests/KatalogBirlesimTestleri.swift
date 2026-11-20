import Testing
import Foundation
import SwiftData
@testable import _01

@MainActor
@Suite(.serialized)
struct KatalogBirlesimTestleri {
    private struct DiskFailure: Error {}

    private func isolated(_ work: (ModelContext) throws -> Void) throws {
        let container = try KitapVeritabani.makeContainer(inMemory: true)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        context.autosaveEnabled = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let oldHistory = LoanHistoryStore.directoryOverride
        let oldStudents = StudentStore.directoryOverride
        let oldMembers = MemberStore.directoryOverride
        LoanHistoryStore.directoryOverride = directory
        StudentStore.directoryOverride = directory
        MemberStore.directoryOverride = directory
        LoanHistoryStore.invalidateCache()
        defer {
            LoanHistoryStore.directoryOverride = oldHistory
            StudentStore.directoryOverride = oldStudents
            MemberStore.directoryOverride = oldMembers
            LoanHistoryStore.invalidateCache()
            try? FileManager.default.removeItem(at: directory)
        }
        try work(context)
    }

    @Test func birlestirmeGeriAlincaKimliklerStokKilitVeIliskilerGeriDoner() throws {
        try isolated { context in
            var firstBook = Book(title: "Aynı Eser", author: "Yazar", publisher: "Yayınevi", quantity: 2, shelf: "2", cabinet: "B")
            firstBook.fieldMetadata = BookFieldMetadata.encode(["notes": .init(source: "manual", isLocked: true)])
            let first = CatalogBook(book: firstBook)
            let second = CatalogBook(book: Book(title: "Aynı Eser", author: "Yazar", quantity: 3, shelf: "2", cabinet: "B"))
            context.insert(first); context.insert(second)
            let loan = ActiveLoan(bookID: second.id, bookTitleSnapshot: second.title, studentName: "Ali", studentClass: "5/A", dueDate: .now)
            let copy = BookCopy(bookID: second.id, accessionCode: "N-2", status: "Onarımda")
            let reservation = Reservation(bookID: second.id, bookTitleSnapshot: second.title, studentName: "Veli", studentClass: "5/A")
            let receipt = ScanWriteReceipt(operationID: UUID(), bookID: second.id, addedCopies: 2, inserted: false)
            context.insert(loan); context.insert(copy); context.insert(reservation); context.insert(receipt)
            let event = LoanEvent(bookID: second.id, bookTitle: second.title, person: "Ali", kind: .lent, date: .now)
            context.insert(try LibraryEventOutbox(event: event))
            try context.save()
            let before = [first.id: first.book, second.id: second.book]
            let oldLoanID = loan.id, oldCopyID = copy.id, oldReservationID = reservation.id, oldReceiptID = receipt.id
            let secondaryID = second.id
            let primary = try CatalogMaintenance.merge([first, second], context: context)
            #expect(primary.quantity == 5)
            #expect(try context.fetchCount(FetchDescriptor<CatalogMergeUndoRecord>()) == 1)
            #expect(try context.fetch(FetchDescriptor<BookCopy>()).first?.bookID == primary.id)
            #expect(try SchoolLibraryService.historySnapshot(context: context).first?.bookID == primary.id)
            #expect(try CatalogMaintenance.undoLastMerge(context: context) == 2)
            let restored = try context.fetch(FetchDescriptor<CatalogBook>())
            #expect(restored.count == 2)
            for book in restored { #expect(book.book == before[book.id]) }
            #expect(try context.fetch(FetchDescriptor<ActiveLoan>()).first { $0.id == oldLoanID }?.bookID == secondaryID)
            #expect(try context.fetch(FetchDescriptor<BookCopy>()).first { $0.id == oldCopyID }?.bookID == secondaryID)
            #expect(try context.fetch(FetchDescriptor<Reservation>()).first { $0.id == oldReservationID }?.bookID == secondaryID)
            #expect(try context.fetch(FetchDescriptor<ScanWriteReceipt>()).first { $0.id == oldReceiptID }?.bookID == secondaryID)
            #expect(try SchoolLibraryService.historySnapshot(context: context).first?.bookID == secondaryID)
            #expect(try CatalogMaintenance.latestUndoRecord(context: context) == nil)
        }
    }

    @Test func farkliYerNushalariBirlesinceYerKorunurVeGeriAlmadaMirasGeriDoner() throws {
        try isolated { context in
            let first = CatalogBook(book: Book(title: "Eser", author: "Y", publisher: "P", quantity: 1, shelf: "1", cabinet: "A"))
            let second = CatalogBook(book: Book(title: "Eser", author: "Y", quantity: 1, shelf: "2", cabinet: "B"))
            context.insert(first); context.insert(second); try context.save()
            let preview = CatalogSaveEngine.preview(second.book, catalog: [first])
            #expect(preview.requiresChoice)
            #expect(throws: SchoolLibraryService.OperationError.self) { try CatalogMaintenance.merge([first, second], context: context) }
            let one = BookCopy(bookID: first.id), two = BookCopy(bookID: second.id)
            context.insert(one); context.insert(two); try context.save()
            let oneID = one.id, twoID = two.id
            _ = try CatalogMaintenance.merge([first, second], context: context)
            let mergedCopies = try context.fetch(FetchDescriptor<BookCopy>())
            #expect(mergedCopies.first { $0.id == oneID }?.cabinet == "A")
            #expect(mergedCopies.first { $0.id == twoID }?.cabinet == "B")
            #expect(mergedCopies.first { $0.id == twoID }?.shelf == "2")
            _ = try CatalogMaintenance.undoLastMerge(context: context)
            let restored = try context.fetch(FetchDescriptor<BookCopy>())
            #expect(restored.first { $0.id == oneID }?.cabinet == nil)
            #expect(restored.first { $0.id == twoID }?.cabinet == nil)
        }
    }

    @Test func birlestirmeSonrasiYeniOduncVeyaMakbuzGeriAlmayiDurdurur() throws {
        try isolated { context in
            let first = CatalogBook(book: Book(title: "Eser", author: "Y", quantity: 2))
            let second = CatalogBook(book: Book(title: "Eser", author: "Y", quantity: 3))
            context.insert(first); context.insert(second); try context.save()
            let merged = try CatalogMaintenance.merge([first, second], context: context)
            let newLoan = ActiveLoan(bookID: merged.id, bookTitleSnapshot: merged.title, studentName: "Yeni kişi", studentClass: "", dueDate: .now)
            context.insert(newLoan); try context.save()
            #expect(throws: SchoolLibraryService.OperationError.self) { try CatalogMaintenance.undoLastMerge(context: context) }
            #expect(merged.quantity == 5)
            context.delete(newLoan); try context.save()
            context.insert(ScanWriteReceipt(operationID: UUID(), bookID: merged.id, addedCopies: 1, inserted: false))
            try context.save()
            #expect(throws: SchoolLibraryService.OperationError.self) { try CatalogMaintenance.undoLastMerge(context: context) }
            #expect(try context.fetchCount(FetchDescriptor<CatalogBook>()) == 1)
        }
    }

    @Test func birlestirmeDiskHatasindaKitaplarVeGeriAlmaDefteriAtomikKalir() throws {
        try isolated { context in
            let first = CatalogBook(book: Book(title: "Eser", author: "Y", quantity: 2))
            let second = CatalogBook(book: Book(title: "Eser", author: "Y", quantity: 3))
            let ids = Set([first.id, second.id])
            context.insert(first); context.insert(second); try context.save()
            #expect(throws: DiskFailure.self) {
                try CatalogMaintenance.merge([first, second], context: context, persist: { throw DiskFailure() })
            }
            let books = try context.fetch(FetchDescriptor<CatalogBook>())
            #expect(Set(books.map(\.id)) == ids)
            #expect(books.compactMap(\.quantity).reduce(0, +) == 5)
            #expect(try context.fetchCount(FetchDescriptor<CatalogMergeUndoRecord>()) == 0)
        }
    }

    @Test func legacyOduncDonusumuGeriAlincaEskiAlanVeTekKimlikKorunur() throws {
        try isolated { context in
            let first = CatalogBook(book: Book(title: "Eser", author: "Y", quantity: 2, loanedTo: "Ali", loanDueDate: .now))
            let second = CatalogBook(book: Book(title: "Eser", author: "Y", quantity: 1))
            let firstID = first.id
            context.insert(first); context.insert(second); try context.save()
            _ = try CatalogMaintenance.merge([first, second], context: context)
            #expect(try context.fetchCount(FetchDescriptor<ActiveLoan>()) == 1)
            _ = try CatalogMaintenance.undoLastMerge(context: context)
            #expect(try context.fetchCount(FetchDescriptor<ActiveLoan>()) == 0)
            #expect(try context.fetch(FetchDescriptor<CatalogBook>()).first { $0.id == firstID }?.loanedTo == "Ali")
        }
    }

    @Test func eksikISBNliBaskiOtomatikArtmazAcikKararGerekir() throws {
        try isolated { context in
            let existing = CatalogBook(book: Book(title: "Eser", author: "Yazar", isbn: "9780140449136", quantity: 2))
            context.insert(existing); try context.save()
            let incoming = Book(title: "Eser", author: "Yazar", quantity: 4)
            let preview = CatalogSaveEngine.preview(incoming, catalog: [existing])
            #expect(preview.requiresChoice)
            #expect(throws: CatalogSaveEngine.EditionReviewRequired.self) {
                try CatalogSaveEngine.save(incoming, context: context, catalog: [existing])
            }
            #expect(existing.quantity == 2)
            let saved = try CatalogSaveEngine.save(incoming, context: context, catalog: [existing], decision: .mergeInto(existing.id))
            guard case .merged(_, let delta) = saved else { Issue.record("Seçilen kayda nüsha eklenmeli"); return }
            #expect(delta == 4)
            #expect(existing.quantity == 6)
        }
    }

    @Test func ayriBaskiSecimiVeFarkliISBNGuvenliKalir() throws {
        try isolated { context in
            let existing = CatalogBook(book: Book(title: "Eser", author: "Yazar", isbn: "9780140449136", quantity: 2))
            context.insert(existing); try context.save()
            let separate = Book(title: "Eser", author: "Yazar", quantity: 4)
            _ = try CatalogSaveEngine.save(separate, context: context, catalog: [existing], decision: .keepSeparate)
            #expect(existing.quantity == 2)
            #expect(try context.fetchCount(FetchDescriptor<CatalogBook>()) == 2)
            let otherISBN = Book(title: "Eser", author: "Yazar", isbn: "9780140449266")
            #expect(!CatalogSaveEngine.canMerge(otherISBN, into: existing.book))
            #expect(throws: CatalogSaveEngine.SaveError.self) {
                try CatalogSaveEngine.save(otherISBN, context: context, catalog: [existing], decision: .mergeInto(existing.id))
            }
        }
    }

    @Test func ayniISBNdeFarkliCiltBirlesmez() throws {
        try isolated { context in
            let existing = CatalogBook(book: Book(title: "Eser", author: "Y", isbn: "9780140449136", volume: 1))
            context.insert(existing); try context.save()
            let incoming = Book(title: "Eser", author: "Y", isbn: "9780140449136", volume: 2)
            #expect(!CatalogSaveEngine.sameEdition(existing, incoming))
            #expect(!CatalogSaveEngine.canMerge(incoming, into: existing.book))
            _ = try CatalogSaveEngine.save(incoming, context: context, catalog: [existing])
            #expect(try context.fetchCount(FetchDescriptor<CatalogBook>()) == 2)
        }
    }
    @Test func eklemeGeriAlincaYalnizEklenenKonumVeAlanKanitiDoner() throws {
        try isolated { context in
            let book = CatalogBook(book: Book(title: "Eser", author: "Y", quantity: 3))
            context.insert(book); try context.save()
            let incoming = Book(title: "Eser", author: "Y", quantity: 4, shelf: "6", cabinet: "B")
            _ = try CatalogSaveEngine.save(incoming, context: context, catalog: [book], source: "voice")
            #expect(book.quantity == 7)
            #expect(book.shelf == "6")
            var laterEdit = book.book
            laterEdit.notes = "Daha sonra yazılan not"
            _ = try CatalogSaveEngine.save(laterEdit, context: context, catalog: [book], source: "manual")
            try CatalogSaveEngine.undo(insertedIDs: [], mergedCopies: [book.id: 4], catalog: [book], context: context, operationIDs: [incoming.id])
            #expect(book.quantity == 3)
            #expect(book.cabinet == nil)
            #expect(book.shelf == nil)
            #expect(book.notes == "Daha sonra yazılan not")
            #expect(BookFieldMetadata.isLocked("notes", on: book))
            #expect(BookFieldMetadata.decode(book.fieldMetadata)["shelf"] == nil)
        }
    }

    @Test func konumSonradanDegismisseEklemeGeriAlmasiKismiDegisiklikYapmaz() throws {
        try isolated { context in
            let book = CatalogBook(book: Book(title: "Eser", author: "Y", quantity: 3))
            context.insert(book); try context.save()
            let incoming = Book(title: "Eser", author: "Y", quantity: 4, shelf: "6")
            _ = try CatalogSaveEngine.save(incoming, context: context, catalog: [book], source: "voice")
            var later = book.book; later.shelf = "9"
            _ = try CatalogSaveEngine.save(later, context: context, catalog: [book])
            #expect(throws: CatalogSaveEngine.SaveError.self) {
                try CatalogSaveEngine.undo(insertedIDs: [], mergedCopies: [book.id: 4], catalog: [book], context: context, operationIDs: [incoming.id])
            }
            #expect(book.quantity == 7)
            #expect(book.shelf == "9")
            #expect(try context.fetchCount(FetchDescriptor<ScanWriteReceipt>()) == 1)
        }
    }

    @Test func bosAmaKilitliKonumNushaEklerkenDoldurulmaz() throws {
        try isolated { context in
            var original = Book(title: "Eser", author: "Y", quantity: 3)
            original.fieldMetadata = BookFieldMetadata.encode(["shelf": .init(source: "manual", isLocked: true)])
            let book = CatalogBook(book: original)
            context.insert(book); try context.save()
            let incoming = Book(title: "Eser", author: "Y", quantity: 4, shelf: "6")
            _ = try CatalogSaveEngine.save(incoming, context: context, catalog: [book], source: "voice")
            #expect(book.quantity == 7)
            #expect(book.shelf == nil)
            try CatalogSaveEngine.undo(insertedIDs: [], mergedCopies: [book.id: 4], catalog: [book], context: context, operationIDs: [incoming.id])
            #expect(book.quantity == 3)
            #expect(BookFieldMetadata.isLocked("shelf", on: book))
        }
    }

}
