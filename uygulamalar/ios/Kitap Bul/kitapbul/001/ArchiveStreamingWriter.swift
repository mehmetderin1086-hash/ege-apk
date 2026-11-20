import Foundation
import CryptoKit
import SwiftData
import Darwin

/// Only the writer can issue this immutable proof after every page and metadata
/// check. Source/context objects never enter it or cross to the writer actor.
nonisolated struct ArchiveStreamingPublication: Sendable {
    let target: URL
    let temporary: URL
    let temporarySeal: ArchiveBackgroundWork.FileSeal
    let targetSeal: ArchiveBackgroundWork.FileSeal?
    let statistics: ArchiveStreamingWriter.Statistics
    fileprivate init(target: URL, temporary: URL, temporarySeal: ArchiveBackgroundWork.FileSeal,
                     targetSeal: ArchiveBackgroundWork.FileSeal?, statistics: ArchiveStreamingWriter.Statistics) {
        self.target = target; self.temporary = temporary; self.temporarySeal = temporarySeal
        self.targetSeal = targetSeal; self.statistics = statistics
    }

    /// MainActor source recheck and cheap POSIX rename share one uninterrupted
    /// turn. No await can admit a late same-ID quantity/loan/metadata mutation.
    @MainActor func commit(recheck: () throws -> Void) throws -> ArchiveStreamingWriter.Statistics {
        try Task.checkCancellation()
        guard try ArchiveBackgroundWork.FileSeal.capture(temporary) == temporarySeal,
              try ArchiveBackgroundWork.FileSeal.capture(target) == targetSeal else { throw Self.stale() }
        try recheck()
        guard rename(temporary.path, target.path) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        // Publication is the last failure boundary. No throwing work follows it.
        return statistics
    }
    private static func stale() -> FullArchive.ValidationError {
        .init(message: "Günlük arşiv yayımlanmadan önce geçici dosya veya önceki yedek değişti; önceki dosya korundu.")
    }
}


/// The file handle, ZIP state, JSON encoder and hashes never leave this actor.
/// The caller reads ModelContext and shared stores on MainActor, then sends
/// immutable pages. Only the lightweight catalogue is retained after each page.
actor ArchiveStreamingWriter {
    nonisolated struct Statistics: Sendable {
        let pages: Int
        let maximumPageSize: Int
        let operationsStayedOffMain: Bool
    }

    private enum Phase { case created, writing, finalized, prepared, published, aborted }
    private let target: URL
    private let temporary: URL
    private let expectedIDs: Set<UUID>
    private var phase: Phase = .created
    private var handle: FileHandle?
    private var zip: ZIPWriter?
    private var hashes: [String: String] = [:]
    private var lightBooks: [Book] = []
    private var seenIDs = Set<UUID>()
    private var pages = 0
    private var maximumPageSize = 0
    private var stayedOffMain = true
    private var bookFingerprints: [UUID: Data] = [:]
    private var verifiedIDs = Set<UUID>()
    private var baselineMetadata: ArchiveContents?

    init(target: URL, temporary: URL, expectedIDs: Set<UUID>) {
        self.target = target; self.temporary = temporary; self.expectedIDs = expectedIDs
    }

    func start() throws {
        noteExecutor()
        try Task.checkCancellation()
        guard phase == .created, !expectedIDs.isEmpty,
              target.deletingLastPathComponent() == temporary.deletingLastPathComponent(),
              target != temporary else { throw failure("Günlük arşiv yazıcısı geçersiz veya daha önce başlatılmış.") }
        try FileManager.default.createDirectory(at: temporary.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let file = try FileHandle(forWritingTo: temporary)
        handle = file; zip = ZIPWriter(fileHandle: file)
        lightBooks.reserveCapacity(expectedIDs.count)
        phase = .writing
    }

    func appendPage(_ page: [Book]) throws {
        noteExecutor()
        try Task.checkCancellation()
        guard phase == .writing, !page.isEmpty, page.count <= 100 else {
            throw failure("Günlük arşiv sayfası 1–100 eser içermeli.")
        }
        let ids = Set(page.map(\.id))
        guard ids.count == page.count, ids.isSubset(of: expectedIDs), seenIDs.isDisjoint(with: ids) else {
            throw failure("Katalog yedek hazırlanırken değişti; tekrarlanan veya beklenmeyen eser yayımlanmadı.")
        }
        for var book in page {
            bookFingerprints[book.id] = try fingerprint(book)
            let id = book.id.uuidString
            if let cover = book.coverData { try add(name: "kapaklar/\(id).png", data: cover) }
            if let back = book.backCoverData { try add(name: "arka/\(id).jpg", data: back) }
            if let imprint = book.imprintData { try add(name: "kunye/\(id).jpg", data: imprint) }
            book.coverData = nil; book.backCoverData = nil; book.imprintData = nil
            lightBooks.append(book)
        }
        seenIDs.formUnion(ids)
        pages += 1; maximumPageSize = max(maximumPageSize, page.count)
    }

    /// Only metadata is accepted here: taking a FullArchive snapshot with every
    /// cover would undo the bounded page flow and is deliberately rejected.
    func finalize(metadata: ArchiveContents) throws {
        noteExecutor()
        try Task.checkCancellation()
        guard phase == .writing, metadata.books.isEmpty,
              seenIDs == expectedIDs, lightBooks.count == expectedIDs.count else {
            throw failure("Günlük arşivin katalog sayfaları veya metadata kapsamı eksik.")
        }
        baselineMetadata = metadata
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        func write<T: Encodable>(_ name: String, _ value: T) throws {
            try add(name: name, data: encoder.encode(value))
        }
        try write("katalog.json", lightBooks)
        try write("odunc-gecmisi.json", metadata.loanEvents)
        try write("etkin-oduncler.json", metadata.activeLoans)
        try write("nushalar.json", metadata.copies)
        try write("rezervasyonlar.json", metadata.reservations)
        try write("ogrenciler.json", metadata.students)
        try write("mezunlar.json", metadata.graduatedStudents)
        try write("uyeler.json", metadata.members)
        try write("ayarlar.json", metadata.settings.filter { ArchiveSettings.allowedKeys.contains($0.key) })
        try write("destek-dosyalari.json", metadata.supportingFiles.filter { ArchiveSettings.supportingFileNames.contains($0.key) })
        try write("tarama-makbuzlari.json", metadata.scanReceipts)
        try write("tarama-oturumlari.json", metadata.scanSessions)
        try write("katalog-birlestirme-geri-al.json", metadata.mergeUndoRecords)
        guard var current = zip,
              current.add(name: "manifest.json", data: try encoder.encode(ArchiveManifest(version: 2, hashes: hashes))),
              current.skippedCount == 0 else { throw zip?.writeError ?? failure("Günlük arşiv ZIP sınırını aştı veya manifest yazılamadı.") }
        _ = current.finalize(); zip = current
        if let error = current.writeError { throw error }
        guard let handle else { throw failure("Günlük arşivin dosyası açılamadı.") }
        try handle.synchronize(); try handle.close(); self.handle = nil
        phase = .finalized
    }

    /// The live context is re-read in bounded pages. Hashing every archived
    /// book field and all three image blobs happens here, away from MainActor.
    func verifyPage(_ page: [Book]) throws {
        noteExecutor(); try Task.checkCancellation()
        guard phase == .finalized, !page.isEmpty, page.count <= 100 else { throw failure("Günlük arşiv değer karşılaştırması geçersiz sayfa aldı.") }
        let ids = Set(page.map(\.id))
        guard ids.count == page.count, ids.isSubset(of: expectedIDs), verifiedIDs.isDisjoint(with: ids) else {
            throw failure("Katalog doğrulama sayfaları hazırlanırken değişti; önceki arşiv korundu.")
        }
        for book in page {
            guard try fingerprint(book) == bookFingerprints[book.id] else {
                throw failure("Aynı kimlikli kitap adedi, alanı veya kapağı değişti. Yeni günlük arşiv yayımlanmadı.")
            }
        }
        verifiedIDs.formUnion(ids)
    }

    /// Immutable file/seal proof can be consumed on MainActor without yielding.
    /// The actor has finalized ZIP/JSON/SHA and compared the complete metadata.
    func preparePublication(currentMetadata: ArchiveContents, expectedTargetSeal: ArchiveBackgroundWork.FileSeal?) throws -> ArchiveStreamingPublication {
        noteExecutor(); try Task.checkCancellation()
        guard phase == .finalized, verifiedIDs == expectedIDs, let baselineMetadata,
              currentMetadata.books.isEmpty, try ArchiveLiveState.same(baselineMetadata, currentMetadata),
              try ArchiveBackgroundWork.FileSeal.capture(target) == expectedTargetSeal,
              let seal = try ArchiveBackgroundWork.FileSeal.capture(temporary), seal.size > 0 else {
            throw failure("Günlük arşivin kitap/ödünç/makbuz/metadata kapsamı veya hedefi değişti; önceki arşiv korundu.")
        }
        phase = .prepared
        return ArchiveStreamingPublication(target: target, temporary: temporary, temporarySeal: seal,
            targetSeal: expectedTargetSeal, statistics: Statistics(pages: pages, maximumPageSize: maximumPageSize, operationsStayedOffMain: stayedOffMain))
    }

    /// Default Date encoding retains sub-second values for the live-state proof;
    /// ZIP interchange dates remain ISO8601 for compatibility. Image hashes are
    /// fed directly, avoiding temporary Base64 copies of a cover-filled page.
    private func fingerprint(_ value: Book) throws -> Data {
        var light = value
        light.coverData = nil; light.backCoverData = nil; light.imprintData = nil
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        var hash = SHA256(); hash.update(data: try encoder.encode(light))
        for image in [value.coverData, value.backCoverData, value.imprintData] {
            hash.update(data: Data([image == nil ? 0 : 1]))
            if let image { hash.update(data: Data(SHA256.hash(data: image))) }
        }
        return Data(hash.finalize())
    }

#if DEBUG
    /// Yalnız birim testleri için eski yayım yolu. Üretim `preparePublication` + `commit` (rename)
    /// kullanır; bu yol Release derlemesine girmez ki testler yanlış güven vermesin.
    func publish() throws -> Statistics {
        noteExecutor()
        try Task.checkCancellation()
        guard phase == .finalized else { throw failure("Tamamlanmamış günlük arşiv yayımlanamaz.") }
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
        } else { try FileManager.default.moveItem(at: temporary, to: target) }
        phase = .published
        return Statistics(pages: pages, maximumPageSize: maximumPageSize, operationsStayedOffMain: stayedOffMain)
    }
#endif

    func abort() {
        noteExecutor()
        guard phase != .published else { return }
        try? handle?.close(); handle = nil; zip = nil
        try? FileManager.default.removeItem(at: temporary)
        phase = .aborted
    }

    private func noteExecutor() { stayedOffMain = stayedOffMain && !Thread.isMainThread }
    private func failure(_ message: String) -> FullArchive.ValidationError { .init(message: message) }
    private func add(name: String, data: Data) throws {
        guard hashes[name] == nil, var current = zip else { throw failure("Günlük arşiv girişi tekrarlanıyor veya dosya kapalı.") }
        guard current.add(name: name, data: data) else { throw current.writeError ?? failure("Günlük arşivin bir dosyası yazılamadı.") }
        zip = current
        hashes[name] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Paths are resolved on MainActor. This worker neither reads a shared pointer
/// nor accesses a ModelContext/global metadata store.
nonisolated enum ArchiveFileBackgroundWork {
    struct TechnicalBackup: Sendable { let data: Data; let fileCount: Int; let ranOffMain: Bool }
    struct DecodedArchive: Sendable { let contents: ArchiveContents; let ranOffMain: Bool }

    @concurrent static func technicalBackup(paths: [URL]) async throws -> TechnicalBackup {
        try Task.checkCancellation()
        var zip = ZIPWriter(), count = 0
        for url in paths where FileManager.default.fileExists(atPath: url.path) {
            try Task.checkCancellation()
            guard zip.add(name: "depo/" + url.lastPathComponent, data: try Data(contentsOf: url)) else {
                throw zip.writeError ?? CocoaError(.fileWriteOutOfSpace)
            }
            count += 1
        }
        guard count > 0 else { throw FullArchive.ValidationError(message: "Dışa aktarılacak özgün depo dosyası bulunamadı; boş teknik yedek oluşturulmadı.") }
        guard zip.add(name: "BILGI.txt", data: Data("Bu dosya açılmayan deponun teknik yedeğidir. Tam sistem arşivi değildir; eski dosya korunmuştur.".utf8)) else {
            throw zip.writeError ?? CocoaError(.fileWriteOutOfSpace)
        }
        let data = zip.finalize()
        if let error = zip.writeError { throw error }
        try Task.checkCancellation()
        return TechnicalBackup(data: data, fileCount: count, ranOffMain: ArchiveBackgroundWork.isOffMainThread())
    }

    /// Özgün depo dosyaları (`.store`, `-wal`, `-shm`) ile SwiftData'nın harici veri klasörünü
    /// (`.<ad>_SUPPORT/_EXTERNAL_DATA/...`, büyük kapak blobları) birlikte yedekler.
    /// Klasik ZIP'in 4 GB sınırına yaklaşılırsa sessizce eksik yedek vermek yerine hata verir.
    @concurrent static func technicalBackup(store: URL) async throws -> TechnicalBackup {
        try Task.checkCancellation()
        return try buildTechnicalBackup(store: store)
    }

    /// Eşzamanlı çekirdek; testler doğrudan çağırır.
    static func buildTechnicalBackup(store: URL) throws -> TechnicalBackup {
        let fileManager = FileManager.default
        var files: [(name: String, url: URL, bytes: Int)] = []
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: store.path + suffix)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            files.append(("depo/" + url.lastPathComponent, url, try fileSize(url)))
        }
        let storeFiles = files.count
        guard storeFiles > 0 else {
            throw FullArchive.ValidationError(message: "Dışa aktarılacak özgün depo dosyası bulunamadı; boş teknik yedek oluşturulmadı.")
        }
        // SwiftData/Core Data harici verisi: <klasör>/.<depoAdı uzantısız>_SUPPORT/...
        let supportName = "." + store.deletingPathExtension().lastPathComponent + "_SUPPORT"
        let supportRoot = store.deletingLastPathComponent().appendingPathComponent(supportName, isDirectory: true)
        var supportCount = 0, supportBytes = 0
        if fileManager.fileExists(atPath: supportRoot.path) {
            let rootPath = supportRoot.standardizedFileURL.resolvingSymlinksInPath().path
            guard let walker = fileManager.enumerator(at: supportRoot, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else {
                throw CocoaError(.fileReadUnknown)
            }
            for case let url as URL in walker {
                try Task.checkCancellation()
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                if values.isSymbolicLink == true { continue }
                guard values.isRegularFile == true else { continue }
                let path = url.standardizedFileURL.resolvingSymlinksInPath().path
                guard path.hasPrefix(rootPath + "/") else { continue }
                let relative = String(path.dropFirst(rootPath.count + 1))
                files.append(("depo/_SUPPORT/" + relative, url, values.fileSize ?? 0))
                supportCount += 1; supportBytes += values.fileSize ?? 0
            }
        }
        let total = files.reduce(0) { $0 + $1.bytes }
        // Giriş başına başlık payı + güvenlik aralığı: 4 GB'a yaklaşan yedek bozuk ZIP üretmesin.
        let limit = ZIPWriter.maxArchiveSize - 64 * 1_048_576 - files.count * 200
        guard total <= limit, files.count < ZIPWriter.maxEntryCount else {
            throw FullArchive.ValidationError(message: "Depo ve harici verisi klasik ZIP'in 4 GB sınırına yaklaşıyor (\(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))). Eksik teknik yedek oluşturulmadı; Dosyalar uygulamasından depo klasörünü elle kopyalayın.")
        }
        var zip = ZIPWriter()
        for file in files {
            try Task.checkCancellation()
            guard zip.add(name: file.name, data: try Data(contentsOf: file.url)) else {
                throw zip.writeError ?? CocoaError(.fileWriteOutOfSpace)
            }
        }
        let info = """
        Bu dosya açılmayan deponun teknik yedeğidir. Tam sistem arşivi değildir; eski dosya korunmuştur.
        Depo dosyaları: \(storeFiles)
        Harici veri (_SUPPORT) dosyaları: \(supportCount) (\(ByteCountFormatter.string(fromByteCount: Int64(supportBytes), countStyle: .file)))
        Toplam: \(files.count) dosya, \(total) bayt (\(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)))
        Kapsam: \(supportCount > 0 ? "depo + harici veri" : "yalnız depo (harici veri klasörü yok)")
        """
        guard zip.add(name: "BILGI.txt", data: Data(info.utf8)) else { throw zip.writeError ?? CocoaError(.fileWriteOutOfSpace) }
        let data = zip.finalize()
        if let error = zip.writeError { throw error }
        return TechnicalBackup(data: data, fileCount: files.count, ranOffMain: ArchiveBackgroundWork.isOffMainThread())
    }

    private static func fileSize(_ url: URL) throws -> Int {
        try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    }

    @concurrent static func readValidated(from url: URL) async throws -> DecodedArchive {
        try Task.checkCancellation()
        let contents = try FullArchive.readValidated(from: url)
        try Task.checkCancellation()
        return DecodedArchive(contents: contents, ranOffMain: ArchiveBackgroundWork.isOffMainThread())
    }
}

@MainActor
extension AutoArchive {
    /// Production keeps ModelContext and the shared JSON/settings stores on
    /// MainActor; only detached value pages/metadata are handed to the writer.
    /// The default Hooks value must be constructed inside this MainActor body;
    /// default argument expressions are evaluated in the caller's context.
    static func writeStreaming(context: ModelContext, expectedCount: Int, target: URL, temporary: URL) async throws {
        try await writeStreaming(context: context, expectedCount: expectedCount, target: target, temporary: temporary,
            hooks: StreamingHooks())
    }

    /// Elle dışa aktarma için akışlı yazım: katalog sayısını kendisi okur, hedefe yalnız doğrulanmış
    /// tam dosyayı yayımlar ve hedef adresini döndürür. Hata ya da iptalde geçici dosya silinir,
    /// önceki hedef dosya korunur. `temporary`, `target` ile aynı klasörde olmalıdır.
    @discardableResult
    static func writeStreaming(context: ModelContext, target: URL, temporary: URL) async throws -> URL {
        let count = try context.fetchCount(FetchDescriptor<CatalogBook>())
        guard count > 0 else { throw FullArchive.ValidationError(message: "Katalog boş; dışa aktarılacak arşiv yazılmadı.") }
        try await writeStreaming(context: context, expectedCount: count, target: target, temporary: temporary,
                                 hooks: testHooks ?? StreamingHooks())
        return target
    }

    static func writeStreaming(context: ModelContext, expectedCount: Int, target: URL, temporary: URL,
                               hooks: StreamingHooks) async throws {
        // Yazım sürerken süpürücü bu geçici dosyaya dokunmaz.
        activeTemporaries.insert(temporary.standardizedFileURL)
        defer { activeTemporaries.remove(temporary.standardizedFileURL) }
        let captureRaw = hooks.rawMetadataPlan ?? { try ArchiveImportCoordinator.captureRawMetadataPlan() }
        let readMetadata = hooks.metadataSnapshot ?? { try metadataSnapshot(context: context) }
        let captureStoreIdentity = hooks.storeIdentitySnapshot ?? { ArchiveStreamingLiveProof.StoreIdentity.current() }
        let liveProof = try ArchiveStreamingLiveProof(context: context, captureRaw: captureRaw, captureStoreIdentity: captureStoreIdentity)
        let ids = Set(try context.fetch(FetchDescriptor<CatalogBook>()).map(\.id))
        guard ids.count == expectedCount else { throw CocoaError(.fileReadCorruptFile) }
        let metadata = try readMetadata()
        let previousTarget = try ArchiveBackgroundWork.FileSeal.capture(target)
        try liveProof.requireUnchanged(context: context)
        let writer = ArchiveStreamingWriter(target: target, temporary: temporary, expectedIDs: ids)
        do {
            try await writer.start()
            try liveProof.requireUnchanged(context: context)
            var offset = 0
            while offset < expectedCount {
                try Task.checkCancellation()
                var descriptor = FetchDescriptor<CatalogBook>(sortBy: [SortDescriptor(\.addedAt), SortDescriptor(\.id)])
                descriptor.fetchOffset = offset; descriptor.fetchLimit = 100
                let page = try context.fetch(descriptor).map(\.book)
                guard !page.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                try await writer.appendPage(page)
                offset += page.count
                try hooks.afterPageWritten?(offset)
                try liveProof.requireUnchanged(context: context)
            }
            try requireCatalogueIDs(ids, context: context)
            try await writer.finalize(metadata: metadata)
            try liveProof.requireUnchanged(context: context)
            // Verify values (including quantity/cover/evidence), not just IDs.
            // No second all-cover snapshot is retained; each DTO page is <=100.
            offset = 0
            while offset < expectedCount {
                var descriptor = FetchDescriptor<CatalogBook>(sortBy: [SortDescriptor(\.addedAt), SortDescriptor(\.id)])
                descriptor.fetchOffset = offset; descriptor.fetchLimit = 100
                let page = try context.fetch(descriptor).map(\.book)
                guard !page.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                try await writer.verifyPage(page)
                offset += page.count
                try liveProof.requireUnchanged(context: context)
            }
            let currentMetadata = try readMetadata()
            let publication = try await writer.preparePublication(currentMetadata: currentMetadata, expectedTargetSeal: previousTarget)
            try hooks.beforePublication?()
            // Last await is above. Source revision/path/seals/settings recheck
            // and atomic rename are now one uninterrupted MainActor operation.
            let statistics = try publication.commit {
                try requireCatalogueIDs(ids, context: context)
                try liveProof.requireUnchanged(context: context)
            }
            hooks.onPublished?(statistics)
        } catch {
            await writer.abort()
            throw error
        }
    }

    private static func requireCatalogueIDs(_ ids: Set<UUID>, context: ModelContext) throws {
        guard Set(try context.fetch(FetchDescriptor<CatalogBook>()).map(\.id)) == ids else {
            throw FullArchive.ValidationError(message: "Katalog yedek hazırlanırken değişti; kısmi günlük arşiv yayımlanmadı.")
        }
    }

    private static func metadataSnapshot(context: ModelContext) throws -> ArchiveContents {
        ArchiveContents(loanEvents: try SchoolLibraryService.historySnapshot(context: context),
            activeLoans: try context.fetch(FetchDescriptor<ActiveLoan>()).map(ArchivedLoan.init),
            copies: try context.fetch(FetchDescriptor<BookCopy>()).map(ArchivedCopy.init),
            reservations: try context.fetch(FetchDescriptor<Reservation>()).map(ArchivedReservation.init),
            students: try StudentStore.allVerified(), members: try MemberStore.allVerified(), settings: ArchiveSettings.snapshot(),
            supportingFiles: try ArchiveSettings.supportingFilesVerified(),
            scanReceipts: try context.fetch(FetchDescriptor<ScanWriteReceipt>()).map(ArchivedScanReceipt.init),
            scanSessions: try ScanSessionStore.allVerified(), graduatedStudents: try GraduatedStudentStore.allVerified(),
            mergeUndoRecords: try context.fetch(FetchDescriptor<CatalogMergeUndoRecord>()).map(ArchivedCatalogMergeUndo.init))
    }
}
