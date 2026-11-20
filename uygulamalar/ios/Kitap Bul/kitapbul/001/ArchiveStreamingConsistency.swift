import Foundation
import SwiftData
import Darwin

/// Notification delivery is synchronous on the saving executor. Only immutable
/// container identity is inspected, never model fields or a worker-owned context.
/// The counter catches same-UUID saves in both disk and in-memory containers.
nonisolated final class ArchiveSaveRevision: @unchecked Sendable {
    private let lock = NSLock()
    private var count: UInt64 = 0
    private var observer: NSObjectProtocol?
    init(container: ModelContainer) {
        observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { [weak self] notification in
            guard let self, let saved = notification.object as? ModelContext, saved.container === container else { return }
            self.lock.lock(); self.count &+= 1; self.lock.unlock()
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    var value: UInt64 { lock.lock(); defer { lock.unlock() }; return count }
}

/// Cheap final revision proof supplements worker-side equality: no archive
/// compression, cover hashing, JSON decoding or full metadata file read happens
/// between the final stale gate and the atomic publication rename.
@MainActor
struct ArchiveStreamingLiveProof {
    struct StoreIdentity: Equatable {
        let container: ObjectIdentifier?
        let selectedStorePath: String?
        static func current() -> StoreIdentity {
            .init(container: KitapVeritabani.shared.map(ObjectIdentifier.init),
                  selectedStorePath: UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey))
        }
    }
    private let revision: ArchiveSaveRevision
    private let savedRevision: UInt64
    private let databaseFiles: [ArchiveBackgroundWork.RawMetadata.Source]
    private let raw: ArchiveBackgroundWork.RawMetadata
    private let captureRaw: () throws -> ArchiveBackgroundWork.RawMetadata
    private let container: ModelContainer
    private let storeIdentity: StoreIdentity
    private let captureStoreIdentity: () -> StoreIdentity

    init(context: ModelContext, captureRaw: @escaping () throws -> ArchiveBackgroundWork.RawMetadata,
         captureStoreIdentity: @escaping () -> StoreIdentity) throws {
        guard !context.hasChanges else { throw Self.stale() }
        container = context.container
        let observedRevision = ArchiveSaveRevision(container: context.container)
        revision = observedRevision
        savedRevision = observedRevision.value
        var urls: [URL] = []
        for configuration in context.container.configurations where !configuration.isStoredInMemoryOnly {
            urls += [configuration.url, URL(fileURLWithPath: configuration.url.path + "-wal")]
        }
        databaseFiles = try urls.map { .init(url: $0, seal: try ArchiveBackgroundWork.FileSeal.capture($0)) }
        self.captureRaw = captureRaw
        raw = try captureRaw()
        self.captureStoreIdentity = captureStoreIdentity
        storeIdentity = captureStoreIdentity()
    }

    func requireUnchanged(context: ModelContext) throws {
        try Task.checkCancellation()
        guard context.container === container, !context.hasChanges, revision.value == savedRevision,
              captureStoreIdentity() == storeIdentity else { throw Self.stale() }
        for file in databaseFiles {
            guard try ArchiveBackgroundWork.FileSeal.capture(file.url) == file.seal else { throw Self.stale() }
        }
        let current = try captureRaw()
        func seals(_ value: ArchiveBackgroundWork.RawMetadata) throws -> [String: ArchiveBackgroundWork.FileSeal?] {
            var result: [String: ArchiveBackgroundWork.FileSeal?] = [:]
            for source in value.sources {
                let path = source.url.standardizedFileURL.path
                if result.keys.contains(path) {
                    guard result[path]! == source.seal else { throw Self.stale() }
                    continue
                }
                // Dictionary subscript assigning nil removes a key, so keep the
                // optional value as a present entry (missing-file proof included).
                result.updateValue(source.seal, forKey: path)
            }
            return result
        }
        guard current.settings == raw.settings, try seals(current) == seals(raw) else { throw Self.stale() }
    }

    private static func stale() -> FullArchive.ValidationError {
        .init(message: "Katalog adedi, kitap alanları, ödünç veya yedek kapsamı hazırlanırken değişti. Yeni günlük arşiv yayımlanmadı; önceki arşiv korundu.")
    }
}


@MainActor
extension AutoArchive {
    struct StreamingHooks {
        var afterPageWritten: ((Int) throws -> Void)?
        var beforePublication: (() throws -> Void)?
        var metadataSnapshot: (() throws -> ArchiveContents)?
        var rawMetadataPlan: (() throws -> ArchiveBackgroundWork.RawMetadata)?
        var storeIdentitySnapshot: (() -> ArchiveStreamingLiveProof.StoreIdentity)?
        var onPublished: ((ArchiveStreamingWriter.Statistics) -> Void)?
    }
}
