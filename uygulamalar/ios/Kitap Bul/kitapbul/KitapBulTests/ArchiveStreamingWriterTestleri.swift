import Foundation
import Testing
@testable import _01

@MainActor
struct ArchiveStreamingWriterTestleri {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("daily-worker-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func pagesJSONHashesAndPublicationRunOffMainAndRoundTripCompleteMetadata() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("daily.zip"), temporary = directory.appendingPathComponent("writing.tmp")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var books: [Book] = []
        for index in 0..<205 {
            let cover = Data([UInt8(index % 255)])
            let back: Data? = index == 7 ? Data([9, 9]) : nil
            let imprint: Data? = index == 7 ? Data([8]) : nil
            let book = Book(title: "Akış Eseri \(index)", author: "Yazar", quantity: 2,
                            coverData: cover, backCoverData: back, imprintData: imprint,
                            fieldMetadata: "{}", addedAt: date)
            books.append(book)
        }
        let student = Student(name: "Akış Okuru", number: "202", className: "7/A")
        let copy = ArchivedCopy(id: UUID(), bookID: books[0].id, accessionCode: "D-202", condition: "İyi", status: "Rafta",
                                note: "", addedAt: date, cabinet: "4", shelf: "2")
        let loan = ArchivedLoan(id: UUID(), bookID: books[0].id, bookTitleSnapshot: books[0].title,
            studentName: student.name, studentClass: student.className, loanedAt: date,
            dueDate: date.addingTimeInterval(86_400), studentID: student.id, identitySource: "student",
            studentNumberSnapshot: student.number, copyID: copy.id, needsIdentityReview: false, kind: "library")
        var event = LoanEvent(bookID: books[0].id, bookTitle: books[0].title, person: student.name, kind: .lent,
                              date: date, dueDate: loan.dueDate)
        event.studentID = student.id; event.copyID = copy.id; event.loanID = loan.id
        event.studentNumberSnapshot = student.number; event.classSnapshot = student.className
        var session = ScanSession(kind: .barcode, title: "Eski kaynak oturumu")
        session.createdAt = date; session.updatedAt = date
        let receipt = ArchivedScanReceipt(id: UUID(), operationID: UUID(), bookID: books[7].id,
            addedCopies: 2, inserted: true, createdAt: date, beforeBookData: nil, afterBookData: Data("{}".utf8))
        let undo = ArchivedCatalogMergeUndo(id: UUID(), payload: Data("{}".utf8), createdAt: date, undoneAt: nil)
        let metadata = ArchiveContents(loanEvents: [event], activeLoans: [loan], copies: [copy], students: [student],
            settings: ["schoolName": Data("\"Akış Okulu\"".utf8)], scanReceipts: [receipt], scanSessions: [session], mergeUndoRecords: [undo])
        let writer = ArchiveStreamingWriter(target: target, temporary: temporary, expectedIDs: Set(books.map(\.id)))
        try await writer.start()
        for start in stride(from: 0, to: books.count, by: 100) {
            try await writer.appendPage(Array(books[start..<min(start + 100, books.count)]))
        }
        try await writer.finalize(metadata: metadata)
        for start in stride(from: 0, to: books.count, by: 100) {
            try await writer.verifyPage(Array(books[start..<min(start + 100, books.count)]))
        }
        let publication = try await writer.preparePublication(currentMetadata: metadata,
            expectedTargetSeal: try ArchiveBackgroundWork.FileSeal.capture(target))
        let statistics = try publication.commit { }
        #expect(statistics.pages == 3 && statistics.maximumPageSize == 100)
        #expect(statistics.operationsStayedOffMain)
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
        let restored = try FullArchive.readValidated(from: target)
        #expect(restored.books == books)
        #expect(restored.activeLoans == [loan] && restored.loanEvents == [event] && restored.copies == [copy])
        #expect(restored.students == [student] && restored.settings == metadata.settings)
        #expect(restored.scanReceipts == [receipt] && restored.scanSessions == [session] && restored.mergeUndoRecords == [undo])
    }

    @Test func missingOrRepeatedPageCannotPublishOverPreviousCompleteArchive() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("daily.zip"), temporary = directory.appendingPathComponent("writing.tmp")
        let previous = try FullArchive.buildVerified(ArchiveContents(books: [Book(title: "Önceki güvenli arşiv", author: "Y")]))
        try previous.write(to: target)
        let first = Book(title: "İlk", author: "Y", coverData: Data([1]))
        let second = Book(title: "Eksik sayfa", author: "Y", coverData: Data([2]))
        let writer = ArchiveStreamingWriter(target: target, temporary: temporary, expectedIDs: [first.id, second.id])
        try await writer.start(); try await writer.appendPage([first])
        do { try await writer.appendPage([first]); Issue.record("Tekrarlanan fiziksel sayfa kabul edilmemeli") }
        catch is FullArchive.ValidationError { }
        do { try await writer.finalize(metadata: ArchiveContents()); Issue.record("Eksik eserle tam arşiv oluşturulmamalı") }
        catch is FullArchive.ValidationError { }
        do { _ = try await writer.preparePublication(currentMetadata: ArchiveContents(), expectedTargetSeal: try ArchiveBackgroundWork.FileSeal.capture(target)); Issue.record("Eksik arşiv önceki dosyanın yerini alamaz") }
        catch is FullArchive.ValidationError { }
        await writer.abort()
        #expect(try Data(contentsOf: target) == previous)
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
        #expect(try FullArchive.readValidated(from: target).books.first?.title == "Önceki güvenli arşiv")
    }

    @Test func pageBoundAndAccidentalAllCoverSnapshotAreRejectedWithoutPublication() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("daily.zip"), temporary = directory.appendingPathComponent("writing.tmp")
        let books = (0..<101).map { Book(title: "B\($0)", author: "Y", coverData: Data([3])) }
        let writer = ArchiveStreamingWriter(target: target, temporary: temporary, expectedIDs: Set(books.map(\.id)))
        try await writer.start()
        do { try await writer.appendPage(books); Issue.record("101 kapaklı eser tek worker sayfası olamaz") }
        catch is FullArchive.ValidationError { }
        try await writer.appendPage(Array(books.prefix(100))); try await writer.appendPage([books[100]])
        do { try await writer.finalize(metadata: ArchiveContents(books: books)); Issue.record("Bütün kapaklı snapshot streaming metadata yerine kullanılamaz") }
        catch is FullArchive.ValidationError { }
        await writer.abort()
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test func technicalBackupAndRecoveryZIPDecodeUseWorkersAndRejectCorruptInput() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("original.store"), wal = directory.appendingPathComponent("original.store-wal")
        let sqlite = Data("SQLite format 3\0technical-original".utf8), walData = Data([4, 5, 6])
        try sqlite.write(to: store); try walData.write(to: wal)
        let result = try await ArchiveFileBackgroundWork.technicalBackup(paths: [store, wal, directory.appendingPathComponent("missing-shm")])
        #expect(result.ranOffMain && result.fileCount == 2)
        let entries = ZIPReader.entries(in: result.data)
        #expect(entries.first { $0.name == "depo/original.store" }?.data == sqlite)
        #expect(entries.first { $0.name == "depo/original.store-wal" }?.data == walData)
        #expect(entries.contains { $0.name == "BILGI.txt" })
        let book = Book(title: "Doğrulanmış kaynak", author: "Y", addedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let zip = directory.appendingPathComponent("selected.zip")
        try FullArchive.buildVerified(ArchiveContents(books: [book])).write(to: zip)
        let decoded = try await ArchiveFileBackgroundWork.readValidated(from: zip)
        #expect(decoded.ranOffMain && decoded.contents.books == [book])
        try Data("bozuk zip".utf8).write(to: zip)
        do { _ = try await ArchiveFileBackgroundWork.readValidated(from: zip); Issue.record("Bozuk kurtarma kaynağı kullanılamaz") }
        catch { }
        #expect(try Data(contentsOf: store) == sqlite && Data(contentsOf: wal) == walData)
    }
}
