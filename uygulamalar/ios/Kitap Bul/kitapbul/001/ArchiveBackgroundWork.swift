import Foundation
import Darwin

/// Only immutable archive values and captured paths cross this boundary.
/// No ModelContext, shared store override, UserDefaults or observable UI state is read here.
nonisolated enum ArchiveBackgroundWork {
    /// Synchronous instrumentation runs on the caller's current thread. It does
    /// not choose an executor or replace actor isolation; worker probes retain
    /// their real Thread measurement without inspecting Thread in async bodies.
    static func isOffMainThread() -> Bool { !Thread.isMainThread }

    static func recordWorkerStart(_ probe: (@Sendable (Bool) -> Void)?) {
        probe?(isOffMainThread())
    }
    struct ValidatedContents: Sendable {
        let contents: ArchiveContents
        fileprivate init(_ contents: ArchiveContents) { self.contents = contents }
    }
    struct Decoded: Sendable {
        let incoming: ArchiveContents
        let beforeFingerprint: String
    }
    struct RawMetadata: Sendable {
        struct Source: Sendable { let url: URL; let seal: FileSeal? }
        let sources: [Source]
        let settings: [String: Data]
    }
    struct FileSeal: Sendable, Equatable {
        let size: UInt64
        let inode: UInt64
        let device: UInt64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64
        static func capture(_ url: URL) throws -> FileSeal? {
            var value = stat()
            let result = url.withUnsafeFileSystemRepresentation { path in
                path.map { lstat($0, &value) } ?? -1
            }
            if result != 0 {
                if errno == ENOENT { return nil }
                throw CocoaError(.fileReadUnknown)
            }
            guard (value.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), value.st_size >= 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return FileSeal(size: UInt64(value.st_size), inode: UInt64(value.st_ino), device: UInt64(bitPattern: Int64(value.st_dev)),
                modifiedSeconds: Int64(value.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(value.st_mtimespec.tv_nsec),
                changedSeconds: Int64(value.st_ctimespec.tv_sec), changedNanoseconds: Int64(value.st_ctimespec.tv_nsec))
        }
    }
    struct Backup: Sendable {
        let directory: URL
        let backupURL: URL
    }

    // Ağır işler `@concurrent` çalışır: ana aktörden ayrılır ama `Task.detached`'ın aksine çağıranın
    // iptalini devralır. Çağıran Task iptal edilince bir sonraki `checkCancellation` işi bırakır ve
    // yarım yazılan geçici dosya bu işlevlerin kendi hata yolunda ya da `AutoArchive.run` içinde silinir.
    @concurrent static func decode(_ data: Data, before: ArchiveContents) async throws -> Decoded {
        try Task.checkCancellation()
        return Decoded(incoming: try FullArchive.readValidated(data: data),
                       beforeFingerprint: try ArchiveImportCoordinator.fingerprint(before))
    }

    @concurrent static func buildArchive(_ contents: ArchiveContents) async throws -> Data {
        try Task.checkCancellation()
        return try FullArchive.buildVerified(contents)
    }

    @concurrent static func read(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        return try Data(contentsOf: url)
    }

    @concurrent static func readValidatedInput(from url: URL) async throws -> Data {
        try Task.checkCancellation()
        let data = try Data(contentsOf: url)
        _ = try FullArchive.readValidated(data: data)
        try Task.checkCancellation()
        return data
    }

    @concurrent static func validate(_ contents: ArchiveContents,
                         didStart: (@Sendable (Bool) -> Void)? = nil) async throws -> ValidatedContents {
        recordWorkerStart(didStart)
        try Task.checkCancellation()
        return try validateSync(contents)
    }

    /// Existing synchronous test/API behavior uses the same full validation.
    static func validateSync(_ contents: ArchiveContents) throws -> ValidatedContents {
        _ = try FullArchive.readValidated(data: FullArchive.buildVerified(contents))
        return ValidatedContents(contents)
    }

    @concurrent static func fingerprint(_ contents: ArchiveContents) async throws -> String {
        try Task.checkCancellation()
        return try ArchiveImportCoordinator.fingerprint(contents)
    }

    @concurrent static func backup(before: ArchiveContents, incoming: ArchiveContents,
                       fingerprint: String, directory: URL, raw: RawMetadata,
                       didStart: (@Sendable (Bool) -> Void)? = nil) async throws -> Backup {
        recordWorkerStart(didStart)
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let backup = directory.appendingPathComponent("Islem-Oncesi-Tam-Arsiv.zip")
        try FullArchive.buildVerified(before).write(to: backup, options: .atomic)
        let readBack = try FullArchive.readValidated(from: backup)
        guard try ArchiveImportCoordinator.fingerprint(readBack) == fingerprint else {
            throw FullArchive.ValidationError(message: "İşlem öncesi tam yedek tekrar okunarak doğrulanamadı; canlı veri değiştirilmedi.")
        }
        try Task.checkCancellation()
        try FullArchive.buildVerified(incoming).write(to: directory.appendingPathComponent("Secilen-Arsiv.zip"), options: .atomic)
        try capture(raw, at: directory)
        try Task.checkCancellation()
        return Backup(directory: directory, backupURL: backup)
    }

    private static func capture(_ raw: RawMetadata, at directory: URL) throws {
        var seen = Set<String>(), index: [String: String] = [:]
        for (offset, source) in raw.sources.enumerated() where seen.insert(source.url.standardizedFileURL.path).inserted {
            let url = source.url
            guard try FileSeal.capture(url) == source.seal else { throw staleMetadata() }
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                let name = "\(offset)-" + url.lastPathComponent
                let target = directory.appendingPathComponent(name)
                try data.write(to: target, options: .atomic)
                guard try Data(contentsOf: target) == data else { throw CocoaError(.fileReadCorruptFile) }
                index[name] = url.standardizedFileURL.path
            }
        }
        try JSONEncoder().encode(index).write(to: directory.appendingPathComponent("dosya-dizini.json"), options: .atomic)
        try JSONEncoder().encode(raw.settings).write(to: directory.appendingPathComponent("onceki-ayarlar.json"), options: .atomic)
        try requireRawUnchanged(raw)
    }
    static func requireRawUnchanged(_ raw: RawMetadata) throws {
        for source in raw.sources {
            guard try FileSeal.capture(source.url) == source.seal else { throw staleMetadata() }
        }
    }
    private static func staleMetadata() -> FullArchive.ValidationError {
        .init(message: "Yedek hazırlanırken kişi/geçmiş/tarama dosyası değişti. Yeni önizleme gerekir; canlı veri değiştirilmedi.")
    }
}

/// Structural comparison uses values/bytes, never ZIP compression or hashing.
/// It checks all archived fields, including image bytes, IDs, source evidence and sessions.
nonisolated enum ArchiveLiveState {
    static func same(_ lhs: ArchiveContents, _ rhs: ArchiveContents) throws -> Bool {
        func ordered<T>(_ values: [T], by key: KeyPath<T, UUID>) -> [T] {
            values.sorted { $0[keyPath: key].uuidString < $1[keyPath: key].uuidString }
        }
        func sameJSON(_ a: [String: Data], _ b: [String: Data]) throws -> Bool {
            guard Set(a.keys) == Set(b.keys) else { return false }
            for key in a.keys {
                guard let left = a[key], let right = b[key] else { return false }
                if left == right { continue }
                guard let leftObject = try? JSONSerialization.jsonObject(with: left, options: .fragmentsAllowed),
                      let rightObject = try? JSONSerialization.jsonObject(with: right, options: .fragmentsAllowed),
                      let value = leftObject as? NSObject, value.isEqual(rightObject) else { return false }
            }
            return true
        }
        guard ordered(lhs.books, by: \.id) == ordered(rhs.books, by: \.id)
            && ordered(lhs.loanEvents, by: \.id) == ordered(rhs.loanEvents, by: \.id)
            && ordered(lhs.activeLoans, by: \.id) == ordered(rhs.activeLoans, by: \.id)
            && ordered(lhs.copies, by: \.id) == ordered(rhs.copies, by: \.id)
            && ordered(lhs.reservations, by: \.id) == ordered(rhs.reservations, by: \.id)
            && ordered(lhs.students, by: \.id) == ordered(rhs.students, by: \.id)
            && ordered(lhs.members, by: \.id) == ordered(rhs.members, by: \.id)
            && ordered(lhs.scanReceipts, by: \.operationID) == ordered(rhs.scanReceipts, by: \.operationID)
            && ordered(lhs.scanSessions, by: \.id) == ordered(rhs.scanSessions, by: \.id)
            && ordered(lhs.graduatedStudents, by: \.id) == ordered(rhs.graduatedStudents, by: \.id)
            && ordered(lhs.mergeUndoRecords, by: \.id) == ordered(rhs.mergeUndoRecords, by: \.id) else { return false }
        return try sameJSON(lhs.settings, rhs.settings) && sameJSON(lhs.supportingFiles, rhs.supportingFiles)
    }
}

@MainActor
enum ArchiveUIOperationGate {
    private static var active: UUID?
    static func begin() throws -> UUID {
        guard active == nil else { throw SchoolLibraryService.OperationError(message: "Bir arşiv işlemi sürüyor. Tamamlanmasını bekleyin.") }
        let token = UUID(); active = token; return token
    }
    static func end(_ token: UUID) { if active == token { active = nil } }
}
