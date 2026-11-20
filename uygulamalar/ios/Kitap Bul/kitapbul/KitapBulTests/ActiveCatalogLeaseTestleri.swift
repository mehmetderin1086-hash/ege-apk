import Foundation
import SwiftData
import Testing
@testable import _01

@MainActor
@Suite(.serialized)
struct ActiveCatalogLeaseTestleri {
    @MainActor private struct Fixture {
        let directory: URL
        let old: ModelContainer
        let active: ModelContainer
        let oldBook: CatalogBook
        let currentBook: CatalogBook
        let sessionURL: URL
        let originalSession: Data
        var oldContext: ModelContext { old.mainContext }
        var activeContext: ModelContext { active.mainContext }
    }

    private func fixture() throws -> Fixture {
        let schema = Schema([CatalogBook.self, ActiveLoan.self, BookCopy.self, Reservation.self,
                             ScanWriteReceipt.self, LibraryEventOutbox.self, CatalogMergeUndoRecord.self])
        let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let active = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let oldBook = CatalogBook(book: Book(title: "Eski katalog", author: "Yazar", quantity: 1))
        let current = CatalogBook(book: Book(title: "Etkin katalog", author: "Başka yazar", quantity: 7))
        old.mainContext.insert(oldBook); active.mainContext.insert(current)
        try old.mainContext.save(); try active.mainContext.save()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("active-catalog-lease-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("current-session.json")
        let session = ScanSession(kind: .photo, title: "Etkin katalog oturumu")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(session)
        try bytes.write(to: url, options: .atomic)
        return Fixture(directory: directory, old: old, active: active, oldBook: oldBook,
                       currentBook: current, sessionURL: url, originalSession: bytes)
    }

    /// Real database/receipt writes plus an isolated session file are behind the
    /// same synchronous lease boundary as ContentView.saveBook. No global path,
    /// shared container, preferences, or role is overridden by this suite.
    private func commit(_ book: Book, lease: ActiveCatalogLease, context: ModelContext,
                        active: ModelContainer?, generation: UUID, sessionURL: URL) throws -> SaveOutcome {
        try lease.perform(context: context, activeContainer: active, generation: generation) {
            let catalog = try context.fetch(FetchDescriptor<CatalogBook>())
            let outcome = try CatalogSaveEngine.save(book, context: context, catalog: catalog, source: "ocr")
            var session = ScanSession(kind: .photo, title: "İşçi sonucu")
            session.savedOperationIDs = [book.id]
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(session).write(to: sessionURL, options: .atomic)
            return outcome
        }
    }

    @Test func providerResultAfterActivationCannotWriteOldDatabaseOrCurrentSession() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        let generation = UUID()
        let lease = try ActiveCatalogLease.capture(context: f.oldContext, activeContainer: f.old, generation: generation)
        let result = await Task.detached { Book(title: "Geciken sağlayıcı sonucu", author: "OCR", quantity: 2) }.value
        let newGeneration = UUID() // activation occurs while the provider was suspended
        var reportedSuccess = false
        do {
            let outcome = try commit(result, lease: lease, context: f.oldContext,
                active: f.active, generation: newGeneration, sessionURL: f.sessionURL)
            reportedSuccess = outcome.succeeded
            Issue.record("Expired worker unexpectedly committed")
        } catch { #expect(error is ActiveCatalogLease.Expired) }
        let oldBooks = try f.oldContext.fetch(FetchDescriptor<CatalogBook>())
        let newBooks = try f.activeContext.fetch(FetchDescriptor<CatalogBook>())
        let oldReceipts = try f.oldContext.fetchCount(FetchDescriptor<ScanWriteReceipt>())
        let newReceipts = try f.activeContext.fetchCount(FetchDescriptor<ScanWriteReceipt>())
        let sessionBytes = try Data(contentsOf: f.sessionURL)
        #expect(!reportedSuccess)
        #expect(oldBooks.map(\.id) == [f.oldBook.id] && oldBooks.first?.quantity == 1)
        #expect(newBooks.map(\.id) == [f.currentBook.id] && newBooks.first?.quantity == 7)
        #expect(oldReceipts == 0 && newReceipts == 0)
        #expect(sessionBytes == f.originalSession)
    }

    @Test func returningToSameContainerDoesNotRenewPreviousGeneration() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        let lease = try ActiveCatalogLease.capture(context: f.oldContext, activeContainer: f.old, generation: UUID())
        #expect(throws: ActiveCatalogLease.Expired.self) {
            try commit(Book(title: "Eski ekran sonucu", author: "OCR"), lease: lease,
                context: f.oldContext, active: f.old, generation: UUID(), sessionURL: f.sessionURL)
        }
        let receipts = try f.oldContext.fetchCount(FetchDescriptor<ScanWriteReceipt>())
        let bytes = try Data(contentsOf: f.sessionURL)
        #expect(receipts == 0 && bytes == f.originalSession)
    }

    @Test func cancelledTaskCannotCommitOrReportSuccessInSameCatalog() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        let generation = UUID()
        let lease = try ActiveCatalogLease.capture(context: f.oldContext, activeContainer: f.old, generation: generation)
        let task = Task { @MainActor in
            try commit(Book(title: "İptal edilen sonuç", author: "OCR"), lease: lease,
                context: f.oldContext, active: f.old, generation: generation, sessionURL: f.sessionURL)
        }
        task.cancel()
        switch await task.result {
        case .success: Issue.record("Cancelled work reported success")
        case .failure(let error): #expect(error is CancellationError)
        }
        let count = try f.oldContext.fetchCount(FetchDescriptor<CatalogBook>())
        let receipts = try f.oldContext.fetchCount(FetchDescriptor<ScanWriteReceipt>())
        let bytes = try Data(contentsOf: f.sessionURL)
        #expect(count == 1 && receipts == 0 && bytes == f.originalSession)
    }

    @Test func currentGenerationCanCommitBookReceiptAndSession() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        let generation = UUID()
        let lease = try ActiveCatalogLease.capture(context: f.activeContext, activeContainer: f.active, generation: generation)
        let incoming = Book(title: "Yeni kitap", author: "Yeni yazar", quantity: 3)
        let outcome = try commit(incoming, lease: lease, context: f.activeContext,
            active: f.active, generation: generation, sessionURL: f.sessionURL)
        let saved = try f.activeContext.fetch(FetchDescriptor<CatalogBook>()).first { $0.id == incoming.id }
        let receipt = try CatalogSaveEngine.receipt(for: incoming.id, context: f.activeContext)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(ScanSession.self, from: Data(contentsOf: f.sessionURL))
        #expect(outcome.succeeded)
        #expect(saved?.quantity == 3 && receipt?.bookID == incoming.id)
        #expect(session.savedOperationIDs == [incoming.id])
    }

    @Test func isolatedTrialServiceIsUsableWithoutAnActiveUILease() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        let incoming = Book(title: "İzole deneme", author: "Yazar")
        let catalog = try f.oldContext.fetch(FetchDescriptor<CatalogBook>())
        let outcome = try CatalogSaveEngine.save(incoming, context: f.oldContext, catalog: catalog)
        let count = try f.oldContext.fetchCount(FetchDescriptor<CatalogBook>())
        #expect(outcome.succeeded && count == 2)
    }

    @Test func aContextCannotCaptureWhenItsContainerIsNotTheActiveCatalog() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.directory) }
        #expect(throws: ActiveCatalogLease.Expired.self) {
            try ActiveCatalogLease.capture(context: f.oldContext, activeContainer: f.active, generation: UUID())
        }
        #expect(throws: ActiveCatalogLease.Expired.self) {
            try ActiveCatalogLease.capture(context: f.oldContext, activeContainer: nil, generation: UUID())
        }
    }
}
