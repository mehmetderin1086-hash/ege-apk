import Foundation
import SwiftData
import Testing
@testable import _01

/// Real streaming production entry, in-memory database and isolated files.
/// Shared student/history/settings directories are never overridden.
@MainActor
@Suite(.serialized)
struct DailyArchiveConsistencyTestleri {
    @MainActor private struct Fixture {
        let directory: URL
        let target: URL
        let temporary: URL
        let previous: Data
        let container: ModelContainer
        let first: CatalogBook
        let student: Student
        let support: URL
        var context: ModelContext { container.mainContext }

        func metadata() throws -> ArchiveContents {
            let loans = try context.fetch(FetchDescriptor<ActiveLoan>())
            let receipts = try context.fetch(FetchDescriptor<ScanWriteReceipt>())
            let pending = try context.fetch(FetchDescriptor<LibraryEventOutbox>())
            let events = try pending.map { try $0.decodedEvent() }
            return ArchiveContents(loanEvents: events, activeLoans: loans.map(ArchivedLoan.init),
                students: [student], supportingFiles: ["OCRDuzeltmeleri.json": try Data(contentsOf: support)],
                scanReceipts: receipts.map(ArchivedScanReceipt.init))
        }

        func raw() throws -> ArchiveBackgroundWork.RawMetadata {
            .init(sources: [.init(url: support, seal: try ArchiveBackgroundWork.FileSeal.capture(support))], settings: [:])
        }

        func assertOldArchiveAndLiveBook() throws {
            let bytes = try Data(contentsOf: target)
            let restored = try FullArchive.readValidated(from: target)
            let count = try context.fetchCount(FetchDescriptor<CatalogBook>())
            #expect(bytes == previous)
            #expect(restored.books.first?.title == "Önceki doğrulanmış günlük arşiv")
            #expect(count == 101)
            #expect(!FileManager.default.fileExists(atPath: temporary.path))
        }
    }

    private func fixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("daily-consistency-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("daily.zip")
        let temporary = directory.appendingPathComponent("writing.tmp")
        let support = directory.appendingPathComponent("OCRDuzeltmeleri.json")
        try Data("{}".utf8).write(to: support)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let previous = try FullArchive.buildVerified(ArchiveContents(books: [
            Book(title: "Önceki doğrulanmış günlük arşiv", author: "Yazar", addedAt: date)
        ]))
        try previous.write(to: target)
        let schema = Schema([CatalogBook.self, ActiveLoan.self, BookCopy.self, Reservation.self,
                             ScanWriteReceipt.self, LibraryEventOutbox.self, CatalogMergeUndoRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        var first: CatalogBook?
        for index in 0..<101 {
            let model = CatalogBook(book: Book(title: "Canlı eser \(index)", author: "Yazar", quantity: 1,
                coverData: Data([UInt8(index % 255)]), addedAt: date.addingTimeInterval(Double(index))))
            if index == 0 { first = model }
            container.mainContext.insert(model)
        }
        try container.mainContext.save()
        let firstModel = try #require(first)
        return Fixture(directory: directory, target: target, temporary: temporary, previous: previous,
            container: container, first: firstModel, student: Student(name: "Kimlikli okur", number: "42", className: "7/A"), support: support)
    }

    @Test func sameIDQuantityAndReceiptCommitAfterFirstPageCannotPublishMixedState() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        var changed = false, published = false
        var hooks = AutoArchive.StreamingHooks()
        hooks.metadataSnapshot = { try f.metadata() }; hooks.rawMetadataPlan = { try f.raw() }
        hooks.storeIdentitySnapshot = { .init(container: ObjectIdentifier(f.container), selectedStorePath: nil) }
        hooks.onPublished = { _ in published = true }
        hooks.afterPageWritten = { count in
            guard count == 100, !changed else { return }
            changed = true
            f.first.quantity = 3
            f.context.insert(ScanWriteReceipt(operationID: UUID(), bookID: f.first.id, addedCopies: 2, inserted: false))
            try f.context.save()
        }
        do {
            try await AutoArchive.writeStreaming(context: f.context, expectedCount: 101, target: f.target, temporary: f.temporary, hooks: hooks)
            Issue.record("Eski adet ve yeni makbuz içeren günlük arşiv yayımlanamaz")
        } catch is FullArchive.ValidationError { }
        let receipts = try f.context.fetch(FetchDescriptor<ScanWriteReceipt>())
        #expect(changed && !published)
        #expect(f.first.quantity == 3 && receipts.count == 1 && receipts.first?.addedCopies == 2)
        try f.assertOldArchiveAndLiveBook()
    }

    @Test func newLoanAndDurableHistoryAfterFirstPageCannotPublishPreviousMetadata() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        var changed = false, published = false
        var hooks = AutoArchive.StreamingHooks()
        hooks.metadataSnapshot = { try f.metadata() }; hooks.rawMetadataPlan = { try f.raw() }
        hooks.storeIdentitySnapshot = { .init(container: ObjectIdentifier(f.container), selectedStorePath: nil) }
        hooks.onPublished = { _ in published = true }
        hooks.afterPageWritten = { count in
            guard count == 100, !changed else { return }
            changed = true
            let loan = ActiveLoan(bookID: f.first.id, bookTitleSnapshot: f.first.title,
                studentName: f.student.name, studentClass: f.student.className,
                dueDate: Date(timeIntervalSince1970: 1_700_086_400))
            loan.studentID = f.student.id; loan.identitySource = "student"
            var event = LoanEvent(bookID: f.first.id, bookTitle: f.first.title, person: f.student.name,
                kind: .lent, date: Date(timeIntervalSince1970: 1_700_000_000), dueDate: loan.dueDate)
            event.studentID = f.student.id; event.loanID = loan.id; event.classSnapshot = f.student.className
            f.context.insert(loan); f.context.insert(try LibraryEventOutbox(event: event))
            try f.context.save()
        }
        do {
            try await AutoArchive.writeStreaming(context: f.context, expectedCount: 101, target: f.target, temporary: f.temporary, hooks: hooks)
            Issue.record("Ödünç ve dayanıklı geçmiş değişimi yok sayılarak arşiv yayımlanamaz")
        } catch is FullArchive.ValidationError { }
        let loans = try f.context.fetch(FetchDescriptor<ActiveLoan>())
        let outbox = try f.context.fetch(FetchDescriptor<LibraryEventOutbox>())
        #expect(changed && !published)
        #expect(loans.count == 1 && loans.first?.studentID == f.student.id && outbox.count == 1)
        #expect(f.first.quantity == 1)
        try f.assertOldArchiveAndLiveBook()
    }

    @Test func finalMetadataDriftAfterWorkerPreparedProofCannotPublish() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        var finalHookRan = false, published = false
        let changedData = Data("{\"düzeltme\":\"yeni bilgi\"}".utf8)
        var hooks = AutoArchive.StreamingHooks()
        hooks.metadataSnapshot = { try f.metadata() }; hooks.rawMetadataPlan = { try f.raw() }
        hooks.storeIdentitySnapshot = { .init(container: ObjectIdentifier(f.container), selectedStorePath: nil) }
        hooks.onPublished = { _ in published = true }
        hooks.beforePublication = {
            finalHookRan = true
            try changedData.write(to: f.support, options: .atomic)
        }
        do {
            try await AutoArchive.writeStreaming(context: f.context, expectedCount: 101, target: f.target, temporary: f.temporary, hooks: hooks)
            Issue.record("Worker kanıtından sonra değişen destek dosyasıyla günlük arşiv yayımlanamaz")
        } catch is FullArchive.ValidationError { }
        let liveSupport = try Data(contentsOf: f.support)
        #expect(finalHookRan && !published && liveSupport == changedData)
        #expect(f.first.quantity == 1)
        try f.assertOldArchiveAndLiveBook()
    }

    @Test func workerComparesSameIDValuesAndKeepsPreviousArchive() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        let archived = f.first.book
        let writer = ArchiveStreamingWriter(target: f.target, temporary: f.temporary, expectedIDs: [archived.id])
        try await writer.start(); try await writer.appendPage([archived])
        try await writer.finalize(metadata: ArchiveContents())
        var changed = archived; changed.quantity = 3
        do {
            try await writer.verifyPage([changed])
            Issue.record("UUID kümesi aynı olsa da adet değişimi worker tarafından reddedilmeli")
        } catch is FullArchive.ValidationError { }
        await writer.abort()
        try f.assertOldArchiveAndLiveBook()
    }

    @Test(arguments: [false, true])
    func finalSameIDSaveAfterWorkerProofCannotPublishInMemoryContainer(fromAnotherContext: Bool) async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        var finalHookRan = false, published = false
        var hooks = AutoArchive.StreamingHooks()
        hooks.metadataSnapshot = { try f.metadata() }; hooks.rawMetadataPlan = { try f.raw() }
        hooks.storeIdentitySnapshot = { .init(container: ObjectIdentifier(f.container), selectedStorePath: nil) }
        hooks.onPublished = { _ in published = true }
        hooks.beforePublication = {
            finalHookRan = true
            let saving = fromAnotherContext ? ModelContext(f.container) : f.context
            let record = try #require(try saving.fetch(FetchDescriptor<CatalogBook>()).first { $0.id == f.first.id })
            record.title = "Son worker dönüşünden sonra değişen ad"
            try saving.save()
        }
        do {
            try await AutoArchive.writeStreaming(context: f.context, expectedCount: 101, target: f.target, temporary: f.temporary, hooks: hooks)
            Issue.record("Son await sonrası aynı kimlikli kaydetme MainActor kapısında reddedilmeli")
        } catch is FullArchive.ValidationError { }
        #expect(finalHookRan && !published)
        let saved = try #require(try ModelContext(f.container).fetch(FetchDescriptor<CatalogBook>()).first { $0.id == f.first.id })
        #expect(saved.title == "Son worker dönüşünden sonra değişen ad")
        try f.assertOldArchiveAndLiveBook()
    }

    @Test func stableLiveCataloguePublishesCompleteArchiveWithBoundedPages() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        var statistics: ArchiveStreamingWriter.Statistics?
        var hooks = AutoArchive.StreamingHooks()
        hooks.metadataSnapshot = { try f.metadata() }; hooks.rawMetadataPlan = { try f.raw() }
        hooks.storeIdentitySnapshot = { .init(container: ObjectIdentifier(f.container), selectedStorePath: nil) }
        hooks.onPublished = { statistics = $0 }
        try await AutoArchive.writeStreaming(context: f.context, expectedCount: 101, target: f.target, temporary: f.temporary, hooks: hooks)
        let restored = try FullArchive.readValidated(from: f.target)
        #expect(statistics?.pages == 2 && statistics?.maximumPageSize == 100)
        #expect(statistics?.operationsStayedOffMain == true)
        #expect(restored.books.count == 101 && Set(restored.books.map(\.id)).count == 101)
        #expect(restored.books.allSatisfy { $0.quantity == 1 && $0.coverData?.count == 1 })
        #expect(restored.students.first?.id == f.student.id)
        #expect(restored.supportingFiles["OCRDuzeltmeleri.json"] == Data("{}".utf8))
        #expect(!FileManager.default.fileExists(atPath: f.temporary.path))
        #expect(try Data(contentsOf: f.target) != f.previous)
    }
}
