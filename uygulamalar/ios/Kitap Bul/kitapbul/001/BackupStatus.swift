import Foundation
import CryptoKit

nonisolated struct VerifiedBackupExport: Codable, Sendable, Equatable {
    var verifiedAt: Date
    var fileName: String
    var targetName: String
    var bytes: Int
    var sha256: String
    var books: Int
    var copies: Int
    var students: Int
    var activeLoans: Int
}

nonisolated struct BackupExportStatus: Codable, Sendable, Equatable {
    var lastAttempt: Date?
    var lastFailure: String?
    var lastSuccess: VerifiedBackupExport?
}

/// Dosyalar'da seçilen hedefe gerçekten yazılmış ZIP doğrulanmadan başarı tarihi değişmez.
nonisolated enum BackupExportVerifier {
    /// Dosyayı 1 MB'lık parçalarla okuyup SHA-256 ve bayt sayısını döndürür; dosya belleğe alınmaz.
    static func chunkedDigest(of url: URL) throws -> (sha256: String, bytes: Int) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256(), bytes = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            bytes += chunk.count; digest.update(data: chunk)
        }
        return (digest.finalize().map { String(format: "%02x", $0) }.joined(), bytes)
    }

    /// Büyük arşivler için: beklenen içerik de DOSYADIR (`expectedURL`, örn. akışla yazılmış geçici ZIP).
    /// İkisi de parça parça okunur; hedefteki dosya beklenenle bayt bayt aynı değilse başarı yazılmaz.
    static func verify(url: URL, expectedURL: URL, now: Date = .now) throws -> VerifiedBackupExport {
        let contents = try FullArchive.readValidated(from: expectedURL)
        let written = try chunkedDigest(of: url)
        let expected = try chunkedDigest(of: expectedURL)
        guard written.bytes == expected.bytes, written.sha256 == expected.sha256 else {
            throw FullArchive.ValidationError(message: "Seçilen hedefteki arşiv, hazırlanan tam yedekle aynı değil. Başarı tarihi güncellenmedi.")
        }
        return VerifiedBackupExport(verifiedAt: now, fileName: url.lastPathComponent,
            targetName: url.deletingLastPathComponent().lastPathComponent, bytes: written.bytes, sha256: written.sha256,
            books: contents.books.count, copies: contents.books.reduce(0) { $0 + max(0, $1.quantity ?? 1) },
            students: contents.students.count, activeLoans: contents.activeLoans.count)
    }

    static func verify(url: URL, expectedData: Data, now: Date = .now) throws -> VerifiedBackupExport {
        let contents = try FullArchive.readValidated(data: expectedData)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256(), bytes = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            bytes += chunk.count; digest.update(data: chunk)
        }
        let writtenHash = digest.finalize().map { String(format: "%02x", $0) }.joined()
        let expectedHash = SHA256.hash(data: expectedData).map { String(format: "%02x", $0) }.joined()
        guard bytes == expectedData.count, writtenHash == expectedHash else {
            throw FullArchive.ValidationError(message: "Seçilen hedefteki arşiv, hazırlanan tam yedekle aynı değil. Başarı tarihi güncellenmedi.")
        }
        return VerifiedBackupExport(verifiedAt: now, fileName: url.lastPathComponent,
            targetName: url.deletingLastPathComponent().lastPathComponent, bytes: bytes, sha256: writtenHash,
            books: contents.books.count, copies: contents.books.reduce(0) { $0 + max(0, $1.quantity ?? 1) },
            students: contents.students.count, activeLoans: contents.activeLoans.count)
    }
}

@MainActor enum BackupExportStatusStore {
    static var storageURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("YedekDurumu.json")
    }
    static func load(from url: URL? = nil) throws -> BackupExportStatus {
        guard let url = url ?? storageURL else { throw CocoaError(.fileNoSuchFile) }
        guard FileManager.default.fileExists(atPath: url.path) else { return BackupExportStatus() }
        return try JSONDecoder().decode(BackupExportStatus.self, from: Data(contentsOf: url))
    }
    static func recordAttempt(now: Date = .now, at url: URL? = nil) throws {
        var status = try load(from: url); status.lastAttempt = now; status.lastFailure = nil
        try save(status, at: url)
    }
    static func recordSuccess(_ receipt: VerifiedBackupExport, at url: URL? = nil) throws {
        var status = try load(from: url); status.lastAttempt = receipt.verifiedAt
        status.lastFailure = nil; status.lastSuccess = receipt; try save(status, at: url)
    }
    static func recordFailure(_ message: String, now: Date = .now, at url: URL? = nil) throws {
        var status = try load(from: url); status.lastAttempt = now; status.lastFailure = message
        try save(status, at: url)
    }
    private static func save(_ status: BackupExportStatus, at url: URL?) throws {
        guard let url = url ?? storageURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(status).write(to: url, options: .atomic)
    }
}
