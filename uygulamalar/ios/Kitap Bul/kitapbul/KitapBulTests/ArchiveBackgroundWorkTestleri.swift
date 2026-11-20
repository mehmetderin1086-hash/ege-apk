import Foundation
import Darwin
import SwiftData
import Testing
@testable import _01

nonisolated private final class ArchiveThreadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var offMain = false
    func record(_ value: Bool) { lock.withLock { offMain = value } }
    var value: Bool { lock.withLock { offMain } }
}

@MainActor
@Suite(.serialized)
struct ArchiveBackgroundWorkTestleri {
    @Test func largeBackupKeepsEveryCoverAndDoesTheRealCodecIOOffMain() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("archive-worker-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cover = Data(repeating: 37, count: 262_144)
        let books = (0..<64).map { Book(title: "Büyük arşiv \($0)", author: "Test", coverData: cover) }
        let before = ArchiveContents(books: books)
        let fingerprint = try ArchiveImportCoordinator.fingerprint(before)
        let probe = ArchiveThreadProbe()
        let backup = try await ArchiveBackgroundWork.backup(before: before, incoming: before,
            fingerprint: fingerprint, directory: root,
            raw: ArchiveBackgroundWork.RawMetadata(sources: [], settings: [:]), didStart: { probe.record($0) })
        let restored = try await Task.detached { try FullArchive.readValidated(from: backup.backupURL) }.value
        #expect(probe.value)
        #expect(restored.books.count == 64)
        #expect(Set(restored.books.map(\.id)) == Set(books.map(\.id)))
        #expect(restored.books.allSatisfy { $0.coverData == cover })
    }

    @Test func rawMetadataInPlaceChangeWithRestoredMtimeIsStillStale() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("archive-source-seal-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("kisiler.json")
        try Data("1234".utf8).write(to: url)
        let capturedBefore = try ArchiveBackgroundWork.FileSeal.capture(url)
        let before = try #require(capturedBefore)
        var original = stat()
        let readResult = url.withUnsafeFileSystemRepresentation { path in path.map { lstat($0, &original) } ?? -1 }
        #expect(readResult == 0)
        let raw = ArchiveBackgroundWork.RawMetadata(sources: [.init(url: url, seal: before)], settings: [:])
        let handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: Data("4321".utf8)); try handle.synchronize()
        var times = [original.st_atimespec, original.st_mtimespec]
        let timeResult = times.withUnsafeMutableBufferPointer { futimens(handle.fileDescriptor, $0.baseAddress) }
        try handle.close()
        #expect(timeResult == 0)
        let capturedAfter = try ArchiveBackgroundWork.FileSeal.capture(url)
        let after = try #require(capturedAfter)
        #expect(before.inode == after.inode && before.size == after.size)
        #expect(before.modifiedSeconds == after.modifiedSeconds && before.modifiedNanoseconds == after.modifiedNanoseconds)
        #expect(before.changedSeconds != after.changedSeconds || before.changedNanoseconds != after.changedNanoseconds)
        #expect(throws: FullArchive.ValidationError.self) { try ArchiveBackgroundWork.requireRawUnchanged(raw) }
    }

    @Test func equalCountsCannotHideAChangedCoverOrCompletedReadingFlag() throws {
        let book = Book(title: "Eser", author: "Yazar", coverData: Data([1, 2, 3]))
        let event = LoanEvent(bookID: book.id, bookTitle: book.title, person: "Okur", kind: .returned, date: Date(timeIntervalSince1970: 1000))
        let before = ArchiveContents(books: [book], loanEvents: [event])
        var changed = before
        changed.books[0].coverData = Data([4, 5, 6])
        let coverSame = try ArchiveLiveState.same(before, changed)
        #expect(!coverSame)
        changed = before; changed.loanEvents[0].readingCompleted = true
        let readingSame = try ArchiveLiveState.same(before, changed)
        #expect(!readingSame)
    }

    @Test(arguments: [false, true])
    func finalMainActorGateRejectsASavedEditWithoutChangingCounts(fromAnotherContext: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("archive-final-gate-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let students = StudentStore.directoryOverride, members = MemberStore.directoryOverride
        let history = LoanHistoryStore.directoryOverride, support = ArchiveSettings.directoryOverride
        let sessions = ScanSessionStore.directoryOverride, fields = FieldMaintenanceStore.directoryOverride
        let oldRoleLock = YetkiDurumu.shared.kilitEtkin
        StudentStore.directoryOverride = root; MemberStore.directoryOverride = root
        LoanHistoryStore.directoryOverride = root; ArchiveSettings.directoryOverride = root
        ScanSessionStore.directoryOverride = root.appendingPathComponent("sessions")
        FieldMaintenanceStore.directoryOverride = nil; LoanHistoryStore.invalidateCache()
        YetkiDurumu.shared.kilitEtkin = false
        defer {
            StudentStore.directoryOverride = students; MemberStore.directoryOverride = members
            LoanHistoryStore.directoryOverride = history; ArchiveSettings.directoryOverride = support
            ScanSessionStore.directoryOverride = sessions; FieldMaintenanceStore.directoryOverride = fields
            YetkiDurumu.shared.kilitEtkin = oldRoleLock; LoanHistoryStore.invalidateCache()
            try? FileManager.default.removeItem(at: root)
        }
        let container = try KitapVeritabani.makeContainer(inMemory: true)
        let context = ModelContext(container); context.autosaveEnabled = false
        let book = CatalogBook(book: Book(title: "Önce", author: "Yazar")); context.insert(book); try context.save()
        let before = try FullArchive.snapshot(context: context)
        let writerContext = fromAnotherContext ? ModelContext(container) : context
        let models = try writerContext.fetch(FetchDescriptor<CatalogBook>())
        let edited = try #require(models.first)
        edited.title = "Sonra"; try writerContext.save()
        var rejected = false
        do { try ArchiveImportCoordinator.requireUnchanged(before, context: context) }
        catch let error as SchoolLibraryService.OperationError { rejected = error.message.contains("değişti") }
        #expect(rejected)
        let persisted = try ModelContext(container).fetch(FetchDescriptor<CatalogBook>())
        #expect(persisted.first?.title == "Sonra")
        let count = try context.fetchCount(FetchDescriptor<CatalogBook>())
        #expect(count == 1)
    }
}
