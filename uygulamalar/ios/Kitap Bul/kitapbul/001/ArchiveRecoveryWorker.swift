import Foundation
import CryptoKit

/// Recovery workers receive immutable values and explicit private paths only.
/// They never read live pointers, global metadata stores or ModelContexts.
nonisolated enum ArchiveRecoveryWorker {
    /// Thread inspection is synchronous instrumentation, not a substitute for
    /// actor isolation. Async callers enter this pure worker helper explicitly.
    static func recordWorkerStart(_ probe: (@Sendable (Bool) -> Void)?) {
        ArchiveBackgroundWork.recordWorkerStart(probe)
    }
    static let selectedName = "Secilen-Dogrulanmis-Arsiv.zip"
    static let markerName = "Onceki-Gecis-Gunlugu.bin"
    static let pointerName = "onceki-depo-isaretcisi.json"
    struct EmergencyProof: Sendable {
        let contents: ArchiveContents
        let directory: URL
        let backupRoot: URL
        let fingerprint: String
        let hashes: [String: String]
        let seals: [String: ArchiveSwitchLeaseWorker.FileSeal]
        let originalMarker: Data?
        let originalPointer: Data?
        let ranOffMain: Bool

        func validateCurrent(backupRoot expected: URL) throws {
            let mandatory: Set<String> = [ArchiveRecoveryWorker.selectedName, ArchiveRecoveryWorker.pointerName,
                                         "dosya-dizini.json", "onceki-ayarlar.json"]
            guard expected.standardizedFileURL.resolvingSymlinksInPath() == backupRoot,
                  directory.standardizedFileURL.resolvingSymlinksInPath() == directory,
                  directory.path.hasPrefix(backupRoot.path + "/"), Set(hashes.keys) == Set(seals.keys),
                  mandatory.isSubset(of: Set(hashes.keys)),
                  (originalMarker != nil) == (hashes[ArchiveRecoveryWorker.markerName] != nil) else {
                throw ArchiveSwitchLeaseWorker.Failure(message: "Acil kurtarma izninin özel dosya kapsamı veya yolu değişmiş.")
            }
            for (name, seal) in seals {
                guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"),
                      directory.appendingPathComponent(name).standardizedFileURL.path == seal.path else {
                    throw ArchiveSwitchLeaseWorker.Failure(message: "Acil kurtarma dosyası özel dizinden çıkıyor.")
                }
                try seal.validateCurrent()
            }
        }
    }

    /// Distinct from normal switch proofs: the original DB may be corrupt and
    /// cannot be exported. Its raw globals and pointer still receive full SHA
    /// coverage, while the user's selected replacement ZIP is fully validated.
    static func prepareEmergency(contents: ArchiveContents, marker: Data?, pointer: Data?,
        raw: ArchiveBackgroundWork.RawMetadata, directory rawDirectory: URL,
        backupRoot rawRoot: URL) throws -> EmergencyProof {
        try Task.checkCancellation()
        let root = rawRoot.standardizedFileURL.resolvingSymlinksInPath()
        let directory = rawDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard directory.path.hasPrefix(root.path + "/"), marker.map({ $0.count <= 1_048_576 }) ?? true else {
            throw ArchiveSwitchLeaseWorker.Failure(message: "Acil kurtarma özel yedek yolu veya eski marker boyutu güvenli değil.")
        }
        let archive = try FullArchive.buildVerified(contents)
        _ = try FullArchive.readValidated(data: archive)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try archive.write(to: directory.appendingPathComponent(selectedName), options: .atomic)
        if let marker { try marker.write(to: directory.appendingPathComponent(markerName), options: .atomic) }
        try JSONEncoder().encode(pointer.map { ["object": $0] } ?? [:])
            .write(to: directory.appendingPathComponent(pointerName), options: .atomic)
        var seen = Set<String>(), index: [String: String] = [:]
        for (offset, source) in raw.sources.enumerated() where seen.insert(source.url.standardizedFileURL.path).inserted {
            try Task.checkCancellation()
            guard try ArchiveBackgroundWork.FileSeal.capture(source.url) == source.seal else { throw stale() }
            if let seal = source.seal {
                let data = try Data(contentsOf: source.url)
                guard try ArchiveBackgroundWork.FileSeal.capture(source.url) == seal else { throw stale() }
                let name = "\(offset)-" + source.url.lastPathComponent
                try data.write(to: directory.appendingPathComponent(name), options: .atomic)
                guard try Data(contentsOf: directory.appendingPathComponent(name)) == data else { throw CocoaError(.fileReadCorruptFile) }
                index[name] = source.url.standardizedFileURL.path
            }
        }
        try JSONEncoder().encode(index).write(to: directory.appendingPathComponent("dosya-dizini.json"), options: .atomic)
        try JSONEncoder().encode(raw.settings).write(to: directory.appendingPathComponent("onceki-ayarlar.json"), options: .atomic)
        try ArchiveBackgroundWork.requireRawUnchanged(raw)
        let fingerprint = try ArchiveImportCoordinator.fingerprint(FullArchive.readValidated(data: archive))
        return try verifyEmergency(directory: directory, backupRoot: root, fingerprint: fingerprint)
    }

    /// Used at cold startup. No paths or old raw bytes are trusted merely because
    /// a marker claims them: every indexed private file is SHA checked first.
    static func verifyEmergency(directory rawDirectory: URL, backupRoot rawRoot: URL,
        fingerprint: String, expectedHashes: [String: String]? = nil) throws -> EmergencyProof {
        try Task.checkCancellation()
        let root = rawRoot.standardizedFileURL.resolvingSymlinksInPath()
        let directory = rawDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard directory.path.hasPrefix(root.path + "/"),
              (try directory.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else { throw stale() }
        func read(_ name: String) throws -> (Data, ArchiveSwitchLeaseWorker.FileSeal) {
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\") else { throw stale() }
            let url = directory.appendingPathComponent(name)
            guard url.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent() == directory else { throw stale() }
            let seal = try ArchiveSwitchLeaseWorker.FileSeal.capture(url)
            let data = try Data(contentsOf: url); try seal.validateCurrent()
            return (data, seal)
        }
        let indexItem = try read("dosya-dizini.json")
        let index = try JSONDecoder().decode([String: String].self, from: indexItem.0)
        var required = Set(index.keys).union([selectedName, pointerName, "dosya-dizini.json", "onceki-ayarlar.json"])
        let hasMarker = expectedHashes.map { $0[markerName] != nil } ?? FileManager.default.fileExists(atPath: directory.appendingPathComponent(markerName).path)
        if hasMarker { required.insert(markerName) }
        guard expectedHashes.map({ Set($0.keys) == required }) ?? true,
              index.values.allSatisfy({ $0.hasPrefix("/") }), Set(index.values).count == index.count else { throw stale() }
        var hashes: [String: String] = [:], seals: [String: ArchiveSwitchLeaseWorker.FileSeal] = [:]
        var selected = Data(), pointer = Data(), originalMarker: Data?
        for name in required.sorted() {
            try Task.checkCancellation()
            let item = name == "dosya-dizini.json" ? indexItem : try read(name)
            let hash = digest(item.0)
            guard expectedHashes.map({ $0[name] == hash }) ?? true else { throw stale() }
            hashes[name] = hash; seals[name] = item.1
            if name == selectedName { selected = item.0 }
            if name == pointerName { pointer = item.0 }
            if name == markerName { originalMarker = item.0 }
            if name == "onceki-ayarlar.json" { _ = try JSONDecoder().decode([String: Data].self, from: item.0) }
        }
        let pointerObject = try JSONDecoder().decode([String: Data].self, from: pointer)
        guard Set(pointerObject.keys).isSubset(of: ["object"]), originalMarker.map({ $0.count <= 1_048_576 }) ?? true else { throw stale() }
        if let data = pointerObject["object"] { _ = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) }
        let contents = try FullArchive.readValidated(data: selected)
        guard try ArchiveImportCoordinator.fingerprint(contents) == fingerprint else { throw stale() }
        let proof = EmergencyProof(contents: contents, directory: directory, backupRoot: root,
            fingerprint: fingerprint, hashes: hashes, seals: seals, originalMarker: originalMarker,
            originalPointer: pointerObject["object"], ranOffMain: !Thread.isMainThread)
        try proof.validateCurrent(backupRoot: root); return proof
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func stale() -> ArchiveSwitchLeaseWorker.Failure {
        .init(message: "Acil kurtarmanın doğrulanan ham dosya, pointer veya seçilen ZIP kapsamı değişmiş; hiçbir canlı dosya yazılmadı.")
    }
}
