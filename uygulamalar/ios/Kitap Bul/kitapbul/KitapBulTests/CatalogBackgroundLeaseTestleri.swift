import Foundation
import SwiftData
import Testing
@testable import _01

@MainActor
@Suite(.serialized)
struct CatalogBackgroundLeaseTestleri {
    @MainActor private struct Fixture {
        let old: ModelContainer
        let active: ModelContainer
        let oldBook: CatalogBook
        let newBook: CatalogBook
        var context: ModelContext { old.mainContext }
    }

    private func fixture(cover: Bool) throws -> Fixture {
        let schema = Schema([CatalogBook.self, ActiveLoan.self, BookCopy.self, Reservation.self,
                             ScanWriteReceipt.self, LibraryEventOutbox.self, CatalogMergeUndoRecord.self])
        let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let active = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let oldBook = CatalogBook(book: Book(title: "Eski katalog kitabı", author: "Yazar", quantity: 1,
            coverData: cover ? Data([1, 2, 3]) : nil))
        let newBook = CatalogBook(book: Book(title: "Yeni katalog kitabı", author: "Yazar", quantity: 4))
        old.mainContext.insert(oldBook); active.mainContext.insert(newBook)
        try old.mainContext.save(); try active.mainContext.save()
        return Fixture(old: old, active: active, oldBook: oldBook, newBook: newBook)
    }

    @Test func delayedCoverCannotChangePreviousStoreOrRemoveNewCatalogueQueue() async throws {
        let f = try fixture(cover: true)
        let oldLock = YetkiDurumu.shared.kilitEtkin
        YetkiDurumu.shared.kilitEtkin = false
        defer { YetkiDurumu.shared.kilitEtkin = oldLock }
        let oldSnapshot = f.oldBook.book, newSnapshot = f.newBook.book
        let initialGeneration = UUID()
        let lease = try ActiveCatalogLease.capture(context: f.context, activeContainer: f.old, generation: initialGeneration)
        var active = f.old, generation = initialGeneration
        var queue = [f.oldBook.id], providerCalled = false, cleanupCalled = false
        let provider = EnrichmentQueue.ProcessProvider(pending: { queue }, removeCompleted: { completed in
            cleanupCalled = true; queue.removeAll { completed.contains($0) }
        }, recognizeCover: { _ in
            providerCalled = true
            await Task.yield()
            // The replacement has its own queue; an overlapping book ID must
            // remain too. This simulates actual activation during the request.
            active = f.active; generation = UUID(); queue = [f.newBook.id, f.oldBook.id]
            return GeminiBookFields(publisher: "Sağlayıcı", language: "Türkçe", category: "Roman", summary: "Özet", isBook: true)
        }, completeText: { _ in Issue.record("Expired cover request reached text completion"); return [] })
        await EnrichmentQueue.process(context: f.context, requireCurrent: {
            try lease.require(context: f.context, activeContainer: active, generation: generation)
        }, provider: provider)
        #expect(providerCalled && !cleanupCalled)
        #expect(queue == [f.newBook.id, f.oldBook.id])
        #expect(f.oldBook.book == oldSnapshot && f.newBook.book == newSnapshot)
        #expect(!f.context.hasChanges && !f.active.mainContext.hasChanges)
    }

    @Test func delayedTextBatchCannotWriteOldModelsOrCleanReplacementQueue() async throws {
        let f = try fixture(cover: false)
        let oldLock = YetkiDurumu.shared.kilitEtkin
        YetkiDurumu.shared.kilitEtkin = false
        defer { YetkiDurumu.shared.kilitEtkin = oldLock }
        let before = f.oldBook.book
        let originalGeneration = UUID()
        let lease = try ActiveCatalogLease.capture(context: f.context, activeContainer: f.old, generation: originalGeneration)
        var active = f.old, generation = originalGeneration
        var queue = [f.oldBook.id], textCalled = false, cleanupCalled = false
        let provider = EnrichmentQueue.ProcessProvider(pending: { queue }, removeCompleted: { completed in
            cleanupCalled = true; queue.removeAll { completed.contains($0) }
        }, recognizeCover: { _ in Issue.record("Book without cover entered cover recognizer"); return GeminiBookFields() },
        completeText: { books in
            textCalled = true
            #expect(books.map(\.id) == [f.oldBook.id])
            await Task.yield()
            active = f.active; generation = UUID(); queue = [f.newBook.id]
            return [AICompletionItem(index: 0, category: "Roman", language: "Türkçe", summary: "Geç gelen özet")]
        })
        await EnrichmentQueue.process(context: f.context, requireCurrent: {
            try lease.require(context: f.context, activeContainer: active, generation: generation)
        }, provider: provider)
        #expect(textCalled && !cleanupCalled && queue == [f.newBook.id])
        #expect(f.oldBook.book == before && f.newBook.quantity == 4)
        #expect(!f.context.hasChanges)
    }

    @Test func currentLeasePersistsCoverAndCleansOnlyCompletedIDs() async throws {
        let f = try fixture(cover: true)
        let oldLock = YetkiDurumu.shared.kilitEtkin
        YetkiDurumu.shared.kilitEtkin = false
        defer { YetkiDurumu.shared.kilitEtkin = oldLock }
        let generation = UUID()
        let lease = try ActiveCatalogLease.capture(context: f.context, activeContainer: f.old, generation: generation)
        var queue = [f.oldBook.id], cleaned = Set<UUID>()
        let provider = EnrichmentQueue.ProcessProvider(pending: { queue }, removeCompleted: { completed in
            cleaned = completed; queue.removeAll { completed.contains($0) }
        }, recognizeCover: { _ in
            GeminiBookFields(publisher: "Sağlayıcı", language: "Türkçe", category: "Roman", summary: "Özet", isBook: true)
        }, completeText: { _ in Issue.record("Complete cover unnecessarily reached text completion"); return [] })
        await EnrichmentQueue.process(context: f.context, requireCurrent: {
            try lease.require(context: f.context, activeContainer: f.old, generation: generation)
        }, provider: provider)
        #expect(f.oldBook.publisher == "Sağlayıcı" && f.oldBook.notes == "Özet")
        #expect(queue.isEmpty && cleaned == [f.oldBook.id])
        #expect(!f.context.hasChanges && f.newBook.publisher == nil)
    }

    @Test func defaultNilCheckerPreservesIsolatedBackgroundServiceContract() async throws {
        let f = try fixture(cover: false)
        let oldLock = YetkiDurumu.shared.kilitEtkin
        YetkiDurumu.shared.kilitEtkin = false
        defer { YetkiDurumu.shared.kilitEtkin = oldLock }
        var completedIDs = Set<UUID>()
        let provider = EnrichmentQueue.ProcessProvider(pending: { [f.oldBook.id] }, removeCompleted: { completedIDs = $0 },
            recognizeCover: { _ in GeminiBookFields() }, completeText: { _ in
                [AICompletionItem(index: 0, category: "Roman", language: "Türkçe", summary: "İzole tamamlandı")]
            })
        await EnrichmentQueue.process(context: f.context, provider: provider)
        #expect(f.oldBook.notes == "İzole tamamlandı" && completedIDs == [f.oldBook.id])
        #expect(f.newBook.notes.isEmpty)
    }

    @MainActor private final class Pause<Value: Sendable> {
        var waiting = false
        private var continuation: CheckedContinuation<Value, Never>?
        func value() async -> Value {
            await withCheckedContinuation { continuation in
                self.continuation = continuation; waiting = true
            }
        }
        func resume(_ value: Value) { continuation?.resume(returning: value); continuation = nil }
    }

    @Test func replacementCanRunWhileOldProviderWaitsAndOldDeferCannotUnlockIt() async throws {
        let f = try fixture(cover: true)
        let oldLock = YetkiDurumu.shared.kilitEtkin
        YetkiDurumu.shared.kilitEtkin = false
        defer { YetkiDurumu.shared.kilitEtkin = oldLock }
        f.newBook.coverData = Data([4, 5, 6]); try f.active.mainContext.save()
        let oldPause = Pause<GeminiBookFields>(), newPause = Pause<GeminiBookFields>()
        let initialGeneration = UUID()
        let oldLease = try ActiveCatalogLease.capture(context: f.context, activeContainer: f.old, generation: initialGeneration)
        var active = f.old, generation = initialGeneration
        var oldCleanup = false, newCleanup = false, duplicateCalls = 0
        let oldProvider = EnrichmentQueue.ProcessProvider(pending: { [f.oldBook.id] }, removeCompleted: { _ in oldCleanup = true },
            recognizeCover: { _ in await oldPause.value() }, completeText: { _ in [] })
        let oldTask = Task { @MainActor in
            await EnrichmentQueue.process(context: f.context, requireCurrent: {
                try oldLease.require(context: f.context, activeContainer: active, generation: generation)
            }, provider: oldProvider)
        }
        for _ in 0..<1000 { if oldPause.waiting { break }; await Task.yield() }
        guard oldPause.waiting else { await oldTask.value; Issue.record("Old provider never started"); return }
        active = f.active; generation = UUID()
        let newContext = f.active.mainContext
        let newLease = try ActiveCatalogLease.capture(context: newContext, activeContainer: active, generation: generation)
        let newProvider = EnrichmentQueue.ProcessProvider(pending: { [f.newBook.id] }, removeCompleted: { _ in newCleanup = true },
            recognizeCover: { _ in await newPause.value() }, completeText: { _ in [] })
        let newTask = Task { @MainActor in
            await EnrichmentQueue.process(context: newContext, requireCurrent: {
                try newLease.require(context: newContext, activeContainer: active, generation: generation)
            }, provider: newProvider)
        }
        for _ in 0..<1000 { if newPause.waiting { break }; await Task.yield() }
        guard newPause.waiting else {
            oldPause.resume(GeminiBookFields()); await oldTask.value; await newTask.value
            Issue.record("New catalog was blocked by the previous provider"); return
        }
        oldPause.resume(GeminiBookFields(publisher: "Eski geç sonuç", isBook: true))
        await oldTask.value // old defer runs while the new operation is still waiting
        let duplicateProvider = EnrichmentQueue.ProcessProvider(pending: { [f.newBook.id] }, removeCompleted: { _ in },
            recognizeCover: { _ in duplicateCalls += 1; return GeminiBookFields(publisher: "Üçüncü", isBook: true) },
            completeText: { _ in [] })
        await EnrichmentQueue.process(context: newContext, requireCurrent: {
            try newLease.require(context: newContext, activeContainer: active, generation: generation)
        }, provider: duplicateProvider)
        newPause.resume(GeminiBookFields(publisher: "Yeni sonuç", language: "Türkçe", category: "Roman", summary: "Özet", isBook: true))
        await newTask.value
        #expect(!oldCleanup && newCleanup && duplicateCalls == 0)
        #expect(f.oldBook.publisher == nil && f.newBook.publisher == "Yeni sonuç")
        #expect(!f.context.hasChanges && !newContext.hasChanges)
    }
}
