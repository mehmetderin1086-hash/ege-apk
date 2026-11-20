import Testing
import Foundation
@testable import _01

@MainActor struct BackupStatusTestleri {
    @Test func writtenBackupMustMatchBeforeSuccessIsRecorded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let book = Book(title: "Tam Yedek", author: "", quantity: 3)
        let data = try FullArchive.buildVerified(ArchiveContents(books: [book]))
        let file = root.appendingPathComponent("Tam.zip"), statusFile = root.appendingPathComponent("Durum.json")
        try data.write(to: file)
        let firstDate = Date(timeIntervalSince1970: 100)
        let receipt = try BackupExportVerifier.verify(url: file, expectedData: data, now: firstDate)
        #expect(receipt.books == 1 && receipt.copies == 3)
        try BackupExportStatusStore.recordSuccess(receipt, at: statusFile)
        try Data("yarım dosya".utf8).write(to: file)
        #expect(throws: Error.self) { try BackupExportVerifier.verify(url: file, expectedData: data) }
        try BackupExportStatusStore.recordFailure("Hedef doğrulanamadı", now: Date(timeIntervalSince1970: 200), at: statusFile)
        let status = try BackupExportStatusStore.load(from: statusFile)
        #expect(status.lastSuccess?.verifiedAt == firstDate)
        #expect(status.lastFailure == "Hedef doğrulanamadı")
        #expect(status.lastAttempt == Date(timeIntervalSince1970: 200))
    }
    @Test func corruptStatusIsReportedAndNotSilentlyReplaced() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let corrupt = Data("bozuk".utf8); try corrupt.write(to: file)
        #expect(throws: Error.self) { try BackupExportStatusStore.recordAttempt(at: file) }
        #expect(try Data(contentsOf: file) == corrupt)
    }
}
