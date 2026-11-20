import CryptoKit
import Foundation
import Observation

nonisolated struct OfflineModelManifest: Decodable, Sendable {
    struct File: Decodable, Sendable {
        let path: String
        let size: Int64
        let hash: String
        let hashKind: String
    }
    let repository: String
    let revision: String
    /// Dosyalar Hugging Face yerine buradan iner (İkra sunucusu; EMA-TTS ONNX dışa aktarımı gibi kendi yayınladığımız modeller).
    var baseURL: String? = nil
    let files: [File]
    var size: Int64 { files.reduce(0) { $0 + $1.size } }
}

nonisolated enum OfflineModelCatalog {
    static let engines: [SpeechEngine] = [.supertonic, .piper, .ema]
    static let manifests: [String: OfflineModelManifest] = {
        guard let url = Bundle.main.url(forResource: "OfflineSpeechManifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode([String: OfflineModelManifest].self, from: data) else { return [:] }
        return result
    }()
    static func manifest(_ engine: SpeechEngine) throws -> OfflineModelManifest {
        guard let manifest = manifests[engine.rawValue], !manifest.files.isEmpty else {
            throw OfflineSpeechError.message("Ses modeli listesi okunamadı. Uygulamayı güncelleyin.")
        }
        return manifest
    }
    static var root: URL { URL.applicationSupportDirectory.appending(path: "OfflineSpeech", directoryHint: .isDirectory) }
    static func engineRoot(_ engine: SpeechEngine) -> URL { root.appending(path: engine.rawValue, directoryHint: .isDirectory) }
    static func directory(_ engine: SpeechEngine) -> URL {
        engineRoot(engine).appending(path: engine == .supertonic ? "supertonic-3-coreml" : engine == .ema ? "ema-tts" : "piper-tr", directoryHint: .isDirectory)
    }
    static func ready(_ engine: SpeechEngine) -> Bool {
        guard let manifest = try? manifest(engine) else { return false }
        return ready(manifest, directory: directory(engine))
    }
    static func ready(_ manifest: OfflineModelManifest, directory: URL) -> Bool {
        guard let marker = try? String(contentsOf: directory.appending(path: ".ready"), encoding: .utf8),
              marker == manifest.revision else { return false }
        return manifest.files.allSatisfy { file in
            let attrs = try? FileManager.default.attributesOfItem(atPath: directory.appending(path: file.path).path)
            return (attrs?[.size] as? NSNumber)?.int64Value == file.size
        }
    }
    static func sizeLabel(_ engine: SpeechEngine) -> String {
        guard let manifest = try? manifest(engine) else { return "" }
        return ByteCountFormatter.string(fromByteCount: manifest.size, countStyle: .file)
    }
    static func validate(_ file: OfflineModelManifest.File, at url: URL) throws {
        guard !file.path.hasPrefix("/"), !file.path.split(separator: "/").contains("..") else {
            throw OfflineSpeechError.message("Geçersiz model dosyası.")
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attrs[.size] as? NSNumber)?.int64Value == file.size else { throw OfflineSpeechError.corruptDownload }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var sha256 = SHA256()
        var git = Insecure.SHA1()
        git.update(data: Data("blob \(file.size)\0".utf8))
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            if file.hashKind == "sha256" { sha256.update(data: data) } else { git.update(data: data) }
        }
        let hash = file.hashKind == "sha256"
            ? sha256.finalize().map { String(format: "%02x", $0) }.joined()
            : git.finalize().map { String(format: "%02x", $0) }.joined()
        guard hash == file.hash else { throw OfflineSpeechError.corruptDownload }
    }
}

nonisolated enum OfflineSpeechError: LocalizedError {
    case message(String), corruptDownload, noAudio
    var errorDescription: String? {
        switch self {
        case .message(let message): message
        case .corruptDownload: "Ses modeli tam indirilemedi veya dosya doğrulanamadı. Yeniden indirmeyi deneyin."
        case .noAudio: "Ses modeli geçerli ses üretemedi. Hazır sahneler korundu; yeniden deneyebilirsiniz."
        }
    }
}

nonisolated private final class SpeechDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let update: @Sendable (Int64) -> Void
    init(update: @escaping @Sendable (Int64) -> Void) { self.update = update }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) { update(totalBytesWritten) }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

/// Madde 50: hizalayıcı modeli de (`DeviceAlignerModel`) bu aktarımı kullanır.
nonisolated enum SpeechModelTransfer {
    @concurrent static func download(_ manifest: OfflineModelManifest, to directory: URL,
                         progress: @escaping @Sendable (String, Int64) -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        // Resume at verified file boundaries. Incomplete URLSession downloads
        // never become model files and a ready marker is committed only at the end.
        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = manifest.files.makeIterator()
            func enqueue() {
                guard let file = iterator.next() else { return }
                group.addTask {
                    let fm = FileManager()
                    try Task.checkCancellation()
                    guard !file.path.hasPrefix("/"), !file.path.split(separator: "/").contains("..") else { throw OfflineSpeechError.corruptDownload }
                    let target = directory.appending(path: file.path)
                    if fm.fileExists(atPath: target.path), (try? OfflineModelCatalog.validate(file, at: target)) != nil {
                        progress(file.path, file.size); return
                    }
                    let remote = URL(string: manifest.baseURL.map { "\($0)/\(file.path)" } ?? "https://huggingface.co/\(manifest.repository)/resolve/\(manifest.revision)/\(file.path)")!
                    let delegate = SpeechDownloadProgress { progress(file.path, min($0, file.size)) }
                    var request = URLRequest(url: remote)
                    request.timeoutInterval = 180
                    let (temporary, response) = try await URLSession.shared.download(for: request, delegate: delegate)
                    defer { try? fm.removeItem(at: temporary) }
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        throw OfflineSpeechError.message("Model indirmesi tamamlanamadı. İnternet bağlantısını kontrol edip tekrar deneyin.")
                    }
                    try OfflineModelCatalog.validate(file, at: temporary)
                    try Task.checkCancellation()
                    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                    try fm.moveItem(at: temporary, to: target)
                    progress(file.path, file.size)
                }
            }
            for _ in 0..<4 { enqueue() }
            while try await group.next() != nil { enqueue() }
        }
        try Task.checkCancellation()
        try manifest.revision.write(to: directory.appending(path: ".ready"), atomically: true, encoding: .utf8)
    }
}

@Observable
final class OfflineSpeechModels {
    static let shared = OfflineSpeechModels()
    struct State: Equatable {
        var ready = false
        var downloading = false
        var removing = false
        var progress: Double = 0
        var message: String?
    }
    private(set) var states: [SpeechEngine: State] = [:]
    @ObservationIgnored private var tasks: [SpeechEngine: Task<Void, Never>] = [:]
    @ObservationIgnored private var received: [SpeechEngine: [String: Int64]] = [:]
    @ObservationIgnored private var generations: [SpeechEngine: UUID] = [:]

    init() { refresh() }
    func state(_ engine: SpeechEngine) -> State { states[engine] ?? State() }
    func refresh() {
        for engine in OfflineModelCatalog.engines where tasks[engine] == nil {
            states[engine, default: State()].ready = OfflineModelCatalog.ready(engine)
        }
    }
    func download(_ engine: SpeechEngine) {
        guard tasks[engine] == nil, !state(engine).removing else { return }
        let generation = UUID()
        generations[engine] = generation
        states[engine] = State(downloading: true)
        received[engine] = [:]
        tasks[engine] = Task { [weak self] in
            guard let self else { return }
            do {
                let manifest = try OfflineModelCatalog.manifest(engine)
                try FileManager.default.createDirectory(at: OfflineModelCatalog.root, withIntermediateDirectories: true)
                let available = try OfflineModelCatalog.root.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? Int64.max
                let missing = manifest.files.reduce(Int64(0)) { total, file in
                    let attrs = try? FileManager.default.attributesOfItem(atPath: OfflineModelCatalog.directory(engine).appending(path: file.path).path)
                    return total + ((attrs?[.size] as? NSNumber)?.int64Value == file.size ? 0 : file.size)
                }
                guard available > missing + 150_000_000 else {
                    throw OfflineSpeechError.message("Model için telefonda yaklaşık \(OfflineModelCatalog.sizeLabel(engine)) ve ek çalışma alanı gerekiyor.")
                }
                try await SpeechModelTransfer.download(manifest, to: OfflineModelCatalog.directory(engine)) { [weak self] path, bytes in
                    Task { @MainActor in
                        guard let self, self.generations[engine] == generation, self.tasks[engine] != nil else { return }
                        self.received[engine, default: [:]][path] = bytes
                        let total = self.received[engine, default: [:]].values.reduce(0, +)
                        self.states[engine, default: State()].progress = min(1, Double(total) / Double(max(manifest.size, 1)))
                    }
                }
                try Task.checkCancellation()
                states[engine] = State(ready: true, progress: 1)
                // İndirme tercihi değiştirmez. Açık seçim yoksa AppVoice zaten hazır EMA modelini varsayılan kullanır.
                // Kullanıcı indirme sürerken başka ses seçmiş olabilir.
            } catch is CancellationError {
                states[engine] = State(message: "İndirme durduruldu. İndirilen dosyalardan devam edebilirsin.")
            } catch {
                states[engine] = State(message: Task.isCancelled ? "İndirme durduruldu. İndirilen dosyalardan devam edebilirsin." : error.localizedDescription)
            }
            tasks[engine] = nil
        }
    }
    func cancel(_ engine: SpeechEngine) { tasks[engine]?.cancel() }
    func waitForDownload(_ engine: SpeechEngine) async { await tasks[engine]?.value }
    func remove(_ engine: SpeechEngine) async {
        guard !state(engine).removing else { return }
        tasks[engine]?.cancel()
        await tasks[engine]?.value
        states[engine] = State(removing: true)
        try? FileManager.default.removeItem(at: OfflineModelCatalog.directory(engine).appending(path: ".ready"))
        await NeuralSpeechRenderer.shared.unload()
        do {
            let directory = OfflineModelCatalog.engineRoot(engine)
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
            states[engine] = State()
        } catch { states[engine] = State(message: error.localizedDescription) }
    }
}
