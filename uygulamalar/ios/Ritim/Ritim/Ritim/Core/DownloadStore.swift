import Foundation
import Combine
import Security
import UIKit
import BackgroundTasks

private func downloadEntryID(_ description: String?) -> UUID? {
    guard let first = description?.split(separator: ":").first else { return nil }
    return UUID(uuidString: String(first))
}

/// Task descriptions contain only selection metadata, never the signed media URL.
private struct NativeBackgroundJournal: Codable {
    var generation: UUID
    var pending: Set<String>
}

struct NativeBackgroundPart: Codable {
    let entryID: UUID
    let generation: UUID
    let kind: String
    let codec: String
    let bitrate: Int
    let resolution: Int?
    let fileExtension: String

    var description: String {
        let data = (try? JSONEncoder().encode(self)) ?? Data()
        return "\(entryID.uuidString):native:\(data.base64EncodedString())"
    }
    static func parse(_ description: String?) -> NativeBackgroundPart? {
        guard let description else { return nil }
        let parts = description.split(separator: ":", maxSplits: 2)
        guard parts.count == 3, parts[1] == "native", let id = UUID(uuidString: String(parts[0])),
              let data = Data(base64Encoded: String(parts[2])), let part = try? JSONDecoder().decode(Self.self, from: data),
              part.entryID == id, ["audio", "video"].contains(part.kind),
              part.fileExtension == (part.kind == "audio" ? "m4a" : "mp4") else { return nil }
        return part
    }
}

enum ServiceEndpointPolicy {
    static func matches(_ lhs: URL, _ rhs: URL) -> Bool {
        let leftScheme = lhs.scheme?.lowercased()
        let rightScheme = rhs.scheme?.lowercased()
        let leftPort = lhs.port ?? (leftScheme == "https" ? 443 : 80)
        let rightPort = rhs.port ?? (rightScheme == "https" ? 443 : 80)
        return leftScheme == rightScheme && lhs.host?.lowercased() == rhs.host?.lowercased() &&
            leftPort == rightPort && normalizedPath(lhs) == normalizedPath(rhs)
    }

    private static func normalizedPath(_ url: URL) -> String {
        var path = URLComponents(url: url.standardized, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? url.path
        while path.hasSuffix("/") { path.removeLast() }
        return path
    }
}

enum SecureSettings {
    static func readToken() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.mehmetderin.ritim", kSecAttrAccount as String: "download-token", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func saveToken(_ value: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.mehmetderin.ritim", kSecAttrAccount as String: "download-token"]
        if value.isEmpty { SecItemDelete(query as CFDictionary); return }
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            var create = query; attributes.forEach { create[$0.key] = $0.value }
            guard SecItemAdd(create as CFDictionary, nil) == errSecSuccess else { throw RitimError.message("Sunucu anahtarı güvenli alana kaydedilemedi.") }
        } else if update != errSecSuccess { throw RitimError.message("Sunucu anahtarı güncellenemedi.") }
    }
}

final class BackgroundDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var owner: DownloadStore?
    private let eventLock = NSLock()
    private var pendingEvents = 0
    private var pendingIDs: [UUID: Int] = [:]
    private var finishEventsRequested = false

    func pendingDeliveryIDs(afterDraining queue: OperationQueue) async -> Set<UUID> {
        await withCheckedContinuation { continuation in
            queue.addBarrierBlock {
                self.eventLock.lock()
                let ids = Set(self.pendingIDs.keys)
                self.eventLock.unlock()
                continuation.resume(returning: ids)
            }
        }
    }

    // URLSession's last delegate callback can arrive while AVAsset metadata is
    // still loading. Keep the OS completion handler pending until files and
    // history have been committed, including failure/cancellation callbacks.
    private func deliver(_ id: UUID, operation: @escaping @MainActor () async -> Void) {
        eventLock.lock()
        pendingEvents += 1
        pendingIDs[id, default: 0] += 1
        eventLock.unlock()
        Task { @MainActor in
            await operation()
            self.eventFinished(id)
        }
    }
    private func eventFinished(_ id: UUID) {
        eventLock.lock()
        pendingEvents -= 1
        let remaining = (pendingIDs[id] ?? 1) - 1
        if remaining == 0 { pendingIDs.removeValue(forKey: id) } else { pendingIDs[id] = remaining }
        let shouldFinish = finishEventsRequested && pendingEvents == 0
        if shouldFinish { finishEventsRequested = false }
        eventLock.unlock()
        if shouldFinish { completeBackgroundEvents() }
    }
    private func completeBackgroundEvents() {
        Task { @MainActor in
            let completion = DownloadStore.backgroundCompletion
            DownloadStore.backgroundCompletion = nil
            completion?()
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let native = NativeBackgroundPart.parse(downloadTask.taskDescription) != nil
        let limit: Int64 = native ? NativeYouTubeDownloader.fileLimit : 1_073_741_824
        if totalBytesWritten > limit || totalBytesExpectedToWrite > limit { downloadTask.cancel(); return }
        if native { return }
        guard let id = downloadEntryID(downloadTask.taskDescription) else { return }
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        Task { @MainActor in self.owner?.updateTransfer(id, received: totalBytesWritten, expected: totalBytesExpectedToWrite, progress: progress, token: downloadTask.taskDescription) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadEntryID(downloadTask.taskDescription) else { return }
        if let part = NativeBackgroundPart.parse(downloadTask.taskDescription) {
            let response = downloadTask.response as? HTTPURLResponse
            let host = response?.url?.host?.lowercased() ?? ""
            let mime = response?.mimeType?.lowercased() ?? ""
            guard response?.statusCode == 200, response?.url?.scheme?.lowercased() == "https",
                  host == "googlevideo.com" || host.hasSuffix(".googlevideo.com"),
                  mime != "text/html", mime != "application/json", mime != "text/plain" else {
                deliver(id) { self.owner?.nativeBackgroundFailed(part, error: RitimError.message("YouTube arka plan aktarımı doğrulanamadı.")) }
                return
            }
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("ritim-native-\(UUID().uuidString)")
            do {
                try FileManager.default.moveItem(at: location, to: staging)
                deliver(id) {
                    guard let owner = self.owner else { try? FileManager.default.removeItem(at: staging); return }
                    await owner.nativeBackgroundReceived(part, file: staging)
                }
            } catch { deliver(id) { self.owner?.nativeBackgroundFailed(part, error: error) } }
            return
        }
        guard let response = downloadTask.response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            deliver(id) { self.owner?.failed(id, message: "Sunucu dosyayı gönderemedi (HTTP \((downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0)).", token: downloadTask.taskDescription) }; return
        }
        let mime = response.mimeType?.lowercased() ?? ""
        guard mime != "text/html", mime != "application/json", mime != "text/plain" else {
            deliver(id) { self.owner?.failed(id, message: "Bağlantı bir medya dosyası yerine web sayfası döndürdü.", token: downloadTask.taskDescription) }; return
        }
        var ext = URL(fileURLWithPath: response.suggestedFilename ?? "").pathExtension.lowercased()
        if !MediaURLPolicy.extensions.contains(ext) { ext = downloadTask.originalRequest?.url?.pathExtension.lowercased() ?? "" }
        if !MediaURLPolicy.extensions.contains(ext) {
            ext = ["audio/mpeg": "mp3", "video/mp4": "mp4", "audio/mp4": "m4a", "audio/wav": "wav", "audio/x-wav": "wav"][mime] ?? "mp4"
        }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("ritim-\(UUID().uuidString).\(ext)")
        do {
            try FileManager.default.moveItem(at: location, to: staging)
            deliver(id) {
                guard let owner = self.owner else { try? FileManager.default.removeItem(at: staging); return }
                await owner.receive(id, file: staging, token: downloadTask.taskDescription)
            }
        } catch { deliver(id) { self.owner?.failed(id, message: error.localizedDescription, token: downloadTask.taskDescription) } }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = downloadEntryID(task.taskDescription) else { return }
        if let part = NativeBackgroundPart.parse(task.taskDescription) {
            deliver(id) { self.owner?.nativeBackgroundFailed(part, error: error) }
            return
        }
        deliver(id) {
            if (error as NSError).code != NSURLErrorCancelled { self.owner?.networkFailed(id, error: error, token: task.taskDescription) }
            else { self.owner?.taskCancelled(id, token: task.taskDescription) }
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // The authenticated service endpoint returns files directly. Background
        // sessions may follow redirects without invoking this callback, so this
        // callback alone is not a credential-isolation guarantee.
        guard task.originalRequest?.value(forHTTPHeaderField: "Authorization") == nil,
              request.url?.scheme?.lowercased() == "https" else { completionHandler(nil); return }
        completionHandler(request)
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        eventLock.lock()
        finishEventsRequested = true
        let shouldFinish = pendingEvents == 0
        if shouldFinish { finishEventsRequested = false }
        eventLock.unlock()
        if shouldFinish { completeBackgroundEvents() }
    }
}

@MainActor
final class DownloadStore: ObservableObject {
    static let processingIdentifier = "com.mehmetderin.ritim.processing"
    static weak var activeInstance: DownloadStore?
    static var backgroundCompletion: (() -> Void)?
    static let queueLimit = 5_000
    static let pipelineLimit = 6
    static let concurrencyOptions = [2, 4, 6, 10, 20, 50, 100]
    @Published private(set) var entries: [DownloadEntry] = []
    @Published var errorMessage: String?
    @Published private(set) var playlistPreview: PlaylistPreview?
    @Published private(set) var isResolvingPlaylist = false
    @Published var bulkNotice: String?
    @Published private(set) var isQueuePaused = false
    @Published var keepScreenAwake = true { didSet { saveSettings() } }
    @Published var downloadQuality: DownloadQuality = .highest { didSet { saveSettings() } }
    @Published var maxConcurrentDownloads = 10 {
        didSet {
            if !Self.concurrencyOptions.contains(maxConcurrentDownloads) { maxConcurrentDownloads = 4 }
            saveSettings()
            // Existing preparations/transfers finish when the selected limit decreases.
            pump()
        }
    }
    @Published private var pipelineIDs: Set<UUID> = []
    var runningCount: Int { pipelineIDs.count }
    var pendingCount: Int { entries.filter { $0.isActive && !pipelineIDs.contains($0.id) }.count }
    var completedCount: Int { entries.filter { $0.status == .completed }.count }
    var failedCount: Int { entries.filter { $0.status == .failed }.count }
    private let library: LibraryStore
    private let stateURL: URL
    private let settingsURL: URL
    private var nativeScratchRoot: URL {
        library.directory.deletingLastPathComponent().appendingPathComponent("NativeDownloads", isDirectory: true)
    }
    private let nativeDownloader: any NativeDownloadProviding
    private let catalog: NativeYouTubeCatalog
    private let delegate = BackgroundDownloadDelegate()
    private let delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.mehmetderin.ritim.download-events"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var session: URLSession!
    private var resourceObservers: [NSObjectProtocol] = []
    private var shortReadyStreak = 0
    private var retryWakeTask: Task<Void, Never>?
    private var progressTimes: [UUID: TimeInterval] = [:]
    private var transferSamples: [UUID: (bytes: Int64, total: Int64, time: TimeInterval, started: TimeInterval, speed: Double)] = [:]
    @Published private(set) var resourceLimit: Int = 100
    var effectiveConcurrency: Int { min(maxConcurrentDownloads, resourceLimit) }
    var resourceWaitMessage: String? {
        if resourceLimit == 0 { return "Cihazın soğuması bekleniyor" }
        if resourceLimit < maxConcurrentDownloads { return "Müzik ve pil için yeni işler yavaşlatıldı" }
        return nil
    }
    private func refreshResourcePolicy() {
        resourceLimit = DownloadResourcePolicy.limit(requested: 100, thermal: ProcessInfo.processInfo.thermalState,
                                                     lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        pump()
    }
    deinit { retryWakeTask?.cancel(); resourceObservers.forEach(NotificationCenter.default.removeObserver) }

    func prioritize(ids: Set<UUID>) {
        let original = entries
        for i in entries.indices where entries[i].status == .queued && ids.contains(entries[i].id) { entries[i].priority = 1 }
        guard save() else { entries = original; return }
        pump()
    }
    func prioritize(_ entry: DownloadEntry) {
        guard entry.status == .queued else { return }
        set(entry.id) { $0.priority = ($0.priority ?? 0) == 0 ? 1 : 0 }
        pump()
    }

    private var pollers: [UUID: Task<Void, Never>] = [:]
    private var transferTokens: [UUID: String] = [:]
    private var restoreTask: Task<Void, Never>?
    private var isRestoring = true
    private var isForeground: Bool
    private var historyWritable = true
    private var resolverTask: Task<Void, Never>?
    private var resolverGeneration = UUID()
    private var cancellingIDs: Set<UUID> = []
    private var resolvedNativeMedia: [UUID: NativeYouTubeMedia] = [:]
    private let backgroundNativeEnabled: Bool
    private let productionBackgroundSession: Bool
    private var continuedTask: BGTask?
    private var continuedPendingID: String?
    private var continuedInitialCount = 0
    private var backgroundProcessingTask: BGProcessingTask?
    private var backgroundProcessingIDs: Set<UUID> = []
    private var quickBackgroundID: UUID?
    private var quickBackgroundAssertion: UIBackgroundTaskIdentifier = .invalid
    private var transitionAssertion: UIBackgroundTaskIdentifier = .invalid
    private var transitionGeneration = UUID()
    private struct Settings: Codable {
        var isQueuePaused: Bool
        var keepScreenAwake: Bool
        // Optional for journals created before the concurrency setting existed.
        var maxConcurrentDownloads: Int?
        var downloadQuality: DownloadQuality?
    }
    init(library: LibraryStore, sessionIdentifier: String = "com.mehmetderin.ritim.downloads",
         downloadConfiguration: URLSessionConfiguration? = nil,
         nativeDownloader: any NativeDownloadProviding = NativeYouTubeDownloader(),
         catalog: NativeYouTubeCatalog = NativeYouTubeCatalog(),
         initiallyForeground: Bool? = nil, allowNativeBackgroundHandoff: Bool? = nil) {
        self.library = library
        self.backgroundNativeEnabled = allowNativeBackgroundHandoff ?? (downloadConfiguration == nil)
        self.productionBackgroundSession = downloadConfiguration == nil
        self.nativeDownloader = nativeDownloader
        self.catalog = catalog
        // URLSession can relaunch us in the background just to deliver a file.
        // Such a launch must never also start in-process extraction or encoding.
        self.isForeground = initiallyForeground ?? (UIApplication.shared.applicationState == .active)
        stateURL = library.directory.deletingLastPathComponent().appendingPathComponent("downloads.json")
        settingsURL = library.directory.deletingLastPathComponent().appendingPathComponent("downloads-settings.json")
        if let data = try? Data(contentsOf: settingsURL), let settings = try? JSONDecoder().decode(Settings.self, from: data) {
            isQueuePaused = settings.isQueuePaused; keepScreenAwake = settings.keepScreenAwake
            let configuredLimit = settings.maxConcurrentDownloads ?? 4
            maxConcurrentDownloads = Self.concurrencyOptions.contains(configuredLimit) ? configuredLimit : 4
            downloadQuality = settings.downloadQuality ?? .highest
        }
        if FileManager.default.fileExists(atPath: stateURL.path) {
            do { entries = try JSONDecoder().decode([DownloadEntry].self, from: Data(contentsOf: stateURL)) }
            catch {
                let backup = stateURL.deletingLastPathComponent().appendingPathComponent("downloads-recovery-\(UUID().uuidString).json")
                do {
                    try FileManager.default.copyItem(at: stateURL, to: backup)
                    errorMessage = "İndirme geçmişi okunamadı. Eski dosyanın kurtarma kopyası saklandı; yeni geçmiş kullanılacak."
                } catch {
                    historyWritable = false
                    errorMessage = "İndirme geçmişi okunamadı ve kurtarma kopyası oluşturulamadı. Dosyalarınızı korumak için yeni indirmeler durduruldu."
                }
            }
        }
        let configuration = downloadConfiguration ?? URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        configuration.isDiscretionary = false
        if downloadConfiguration == nil { configuration.sessionSendsLaunchEvents = true }
        configuration.httpMaximumConnectionsPerHost = Self.pipelineLimit
        configuration.timeoutIntervalForResource = 7200
        delegate.owner = self
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: delegateQueue)
        if downloadConfiguration == nil { Self.activeInstance = self }
        if downloadConfiguration == nil {
            refreshResourcePolicy()
            for name in [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
                resourceObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.refreshResourcePolicy() }
                })
            }
        }
        restoreTask = Task { [weak self] in await self?.restore() }
    }

    func start(url string: String, format: DownloadFormat) {
        let previousCount = entries.filter(\.isActive).count
        enqueueText(string, format: format, batchName: "Tek indirme")
        if entries.filter(\.isActive).count == previousCount, let bulkNotice { errorMessage = bulkNotice }
    }

    func enqueueText(_ text: String, format: DownloadFormat, batchName: String) {
        let inputs = text.split(whereSeparator: \.isWhitespace).map(String.init)
        enqueue(inputs.map { ($0, nil, nil) }, format: format, batchName: batchName, playlistID: nil)
    }

    func enqueuePlaylist(items: [PlaylistItem], title: String, format: DownloadFormat) {
        guard !items.isEmpty else { bulkNotice = "Önce en az bir parça seç."; return }
        let name = String((title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "YouTube listesi" : title).prefix(80))
        var playlist = library.playlists.first { $0.name == name }
        if playlist == nil { library.createPlaylist(name: name); playlist = library.playlists.last { $0.name == name } }
        guard let playlist else { errorMessage = library.errorMessage ?? "Yerel oynatma listesi oluşturulamadı."; return }
        enqueue(items.sorted { $0.index < $1.index }.map { ($0.url, $0.title, $0.artist) }, format: format, batchName: name, playlistID: playlist.id)
    }

    private func enqueue(_ inputs: [(String, String?, String?)], format: DownloadFormat, batchName: String, playlistID: UUID?) {
        guard historyWritable else { errorMessage = "İndirme geçmişi güvenle kaydedilemiyor. Aygıttaki boş alanı ve dosya erişimini kontrol et."; return }
        guard !inputs.isEmpty else { bulkNotice = "En az bir HTTPS medya veya YouTube video bağlantısı gir."; return }
        let before = entries
        let batchID = UUID()
        var accepted = 0, duplicate = 0, invalid = 0, overflow = 0
        var problems: [String] = []
        var remaining = max(0, Self.queueLimit - entries.filter(\.isActive).count)
        var known: [String: UUID] = [:]
        for entry in entries where entry.isActive {
            if let key = MediaURLPolicy.downloadKey(entry.sourceURL, format: entry.format, quality: entry.quality) { known[key] = entry.id }
        }
        var reusable: [String: UUID] = [:]
        for entry in entries where !entry.isActive && entry.status != .completed && !cancellingIDs.contains(entry.id) {
            if let key = MediaURLPolicy.downloadKey(entry.sourceURL, format: entry.format, quality: entry.quality), reusable[key] == nil {
                reusable[key] = entry.id
            }
        }
        var tracks: [String: MediaTrack] = [:]
        for track in library.tracks {
            guard let source = track.sourceURL, let trackFormat = DownloadFormat(rawValue: URL(fileURLWithPath: track.fileName).pathExtension.lowercased()),
                  let key = MediaURLPolicy.downloadKey(source, format: trackFormat, quality: track.downloadQuality), FileManager.default.fileExists(atPath: library.url(for: track).path) else { continue }
            tracks[key] = track
        }
        var playlistSlots: [PlaylistDownloadSlot] = []
        for (offset, input) in inputs.enumerated() {
            do {
                let url = try MediaURLPolicy.canonicalInput(input.0)
                let quality: DownloadQuality? = MediaURLPolicy.isYouTube(url) ? downloadQuality : nil
                guard let key = MediaURLPolicy.downloadKey(url.absoluteString, format: format, quality: quality) else { continue }
                if let track = tracks[key] {
                    duplicate += 1; playlistSlots.append(PlaylistDownloadSlot(trackID: track.id)); continue
                }
                if let existingID = known[key], let index = entries.firstIndex(where: { $0.id == existingID }) {
                    duplicate += 1
                    if let playlistID { attachPlaylist(playlistID, to: &entries[index]) }
                    playlistSlots.append(PlaylistDownloadSlot(entryID: existingID))
                    continue
                }
                guard remaining > 0 else { overflow += 1; continue }
                var entry = DownloadEntry(title: input.1?.isEmpty == false ? input.1! : (MediaURLPolicy.isYouTube(url) ? "YouTube • \(format.rawValue.uppercased())" : url.deletingPathExtension().lastPathComponent), sourceURL: url.absoluteString, format: format, quality: quality)
                entry.artist = input.2
                entry.batchID = batchID; entry.batchName = String(batchName.prefix(80)); entry.playlistID = playlistID
                // Reuse terminal rows; remove+append makes retries join the FIFO tail.
                if let reusableID = reusable.removeValue(forKey: key), let old = entries.firstIndex(where: { $0.id == reusableID }) {
                    entry.id = entries[old].id
                    entries.remove(at: old)
                }
                known[key] = entry.id; entries.append(entry)
                playlistSlots.append(PlaylistDownloadSlot(entryID: entry.id))
                accepted += 1; remaining -= 1
            } catch {
                invalid += 1
                if problems.count < 3 { problems.append("\(offset + 1). bağlantı: \(error.localizedDescription)") }
            }
        }
        if let playlistID {
            do { try library.reserveDownloadOrder(playlistSlots, in: playlistID) }
            catch { entries = before; errorMessage = "Oynatma listesi sırası kaydedilemedi: \(error.localizedDescription)"; return }
        }
        guard save() else { entries = before; prunePlaylistReservations(); return }
        prunePlaylistReservations()
        bulkNotice = "\(accepted) sıraya eklendi • \(duplicate) zaten mevcut • \(invalid) geçersiz • \(overflow) sınırı aştı (en fazla \(Self.queueLimit) bekleyen)." + (problems.isEmpty ? "" : "\n" + problems.joined(separator: "\n"))
        if accepted > 0 && !isQueuePaused { requestContinuedTaskForUserAction() }
        pump()
    }

    private func attachPlaylist(_ playlistID: UUID, to entry: inout DownloadEntry) {
        if entry.playlistID == nil { entry.playlistID = playlistID }
        else if entry.playlistID != playlistID && !(entry.additionalPlaylistIDs ?? []).contains(playlistID) {
            entry.additionalPlaylistIDs = (entry.additionalPlaylistIDs ?? []) + [playlistID]
        }
    }
    func pauseQueue() { isQueuePaused = true; finishContinuedTask(success: false); saveSettings() }
    func resumeQueue() {
        isQueuePaused = false
        requestContinuedTaskForUserAction()
        // A failed disk write may have interrupted scheduling before a network task existed.
        for i in entries.indices where entries[i].isActive && !pipelineIDs.contains(entries[i].id) && !cancellingIDs.contains(entries[i].id) { entries[i].status = .queued }
        guard save() else { return }
        saveSettings(); pump()
    }
    func applicationDidBecomeActive() {
        isForeground = true
        endBackgroundTransition(transitionGeneration)
        pump()
    }
    func applicationDidEnterBackground() {
        isForeground = false
        if continuedTask != nil { return }
        cancelPlaylistResolution()
        let transitioning = Set(pollers.keys).subtracting(backgroundProcessingIDs).subtracting(quickBackgroundID.map { [$0] } ?? [])
        beginBackgroundTransition(transitioning)
        var changed = false
        // Background audio does not grant a CPU budget for LAME/YouTube work.
        // Stop native jobs immediately, not at beginBackgroundTask expiration.
        // Keep their slots until the cancelled task has closed files and removed
        // scratch; a quick foreground transition must not overlap two attempts.
        for (id, task) in pollers {
            if backgroundProcessingIDs.contains(id) || quickBackgroundID == id { continue }
            transferTokens.removeValue(forKey: id)
            let media = resolvedNativeMedia.removeValue(forKey: id)
            let entry = entries.first { $0.id == id && $0.isActive }
            let handingOff = backgroundNativeEnabled && media != nil && entry != nil
            if handingOff { cancellingIDs.insert(id) }
            task.cancel()
            if let index = entries.firstIndex(where: { $0.id == id && $0.isActive }) {
                entries[index].status = handingOff ? .downloading : .queued
                entries[index].progress = 0
                entries[index].error = nil
                changed = true
            }
            if let media, let entry, handingOff {
                startNativeBackgroundHandoff(entry, media: media, oldTask: task)
            }
        }
        if changed { save() }
        scheduleBackgroundProcessing()
        startQuickBackgroundConversionIfPossible()
        // Direct media transfers use background URLSession and remain running.
    }

    // Cancellation and handoff are asynchronous. Keep the process alive just
    // long enough for those jobs to release their slots before checking the
    // completed-source queue. Never start a second job in an occupied slot.
    private func beginBackgroundTransition(_ ids: Set<UUID>) {
        guard productionBackgroundSession, !ids.isEmpty else { return }
        endBackgroundTransition(transitionGeneration)
        let generation = UUID()
        transitionGeneration = generation
        transitionAssertion = UIApplication.shared.beginBackgroundTask(withName: "Ritim indirme geçişi") { [weak self] in
            Task { @MainActor in self?.endBackgroundTransition(generation) }
        }
        guard transitionAssertion != .invalid else { return }
        Task { [weak self] in
            let deadline = Date().addingTimeInterval(15)
            while let self, self.transitionGeneration == generation, self.transitionAssertion != .invalid,
                  Date() < deadline,
                  ids.contains(where: { self.pollers[$0] != nil || self.cancellingIDs.contains($0) }) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let self, self.transitionGeneration == generation, self.transitionAssertion != .invalid else { return }
            self.startQuickBackgroundConversionIfPossible()
            self.endBackgroundTransition(generation)
        }
    }

    private func endBackgroundTransition(_ generation: UUID) {
        guard transitionGeneration == generation, transitionAssertion != .invalid else { return }
        let assertion = transitionAssertion
        transitionAssertion = .invalid
        UIApplication.shared.endBackgroundTask(assertion)
    }

    private func nativeJournalURL(_ id: UUID) -> URL {
        nativeScratchRoot.appendingPathComponent(id.uuidString, isDirectory: true).appendingPathComponent("background.json")
    }
    private func readNativeJournal(_ id: UUID) -> NativeBackgroundJournal? {
        guard let data = try? Data(contentsOf: nativeJournalURL(id)) else { return nil }
        return try? JSONDecoder().decode(NativeBackgroundJournal.self, from: data)
    }
    private func writeNativeJournal(_ journal: NativeBackgroundJournal, id: UUID) throws {
        let url = nativeJournalURL(id)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(journal).write(to: url, options: .atomic)
    }

    private func startNativeBackgroundHandoff(_ entry: DownloadEntry, media: NativeYouTubeMedia, oldTask: Task<Void, Never>) {
        let id = entry.id
        let generation = UUID()
        let sources: [(String, NativeYouTubeStream)] = [("audio", media.audio)] + (media.video.map { [("video", $0)] } ?? [])
        let checkpoint = nativeScratchRoot.appendingPathComponent(id.uuidString).appendingPathComponent("checkpoint")
        let required = sources.filter { !NativeYouTubeDownloader.checkpointMatches(checkpoint, kind: $0.0, entry: entry, stream: $0.1) }
        do {
            try writeNativeJournal(NativeBackgroundJournal(generation: generation, pending: Set(required.map(\.0))), id: id)
            for (kind, stream) in required {
                let part = NativeBackgroundPart(entryID: id, generation: generation, kind: kind, codec: stream.codec,
                                                bitrate: stream.bitrate, resolution: stream.resolution, fileExtension: stream.fileExtension)
                let task = session.downloadTask(with: stream.request)
                task.taskDescription = part.description
                task.resume()
            }
        } catch {
            try? FileManager.default.removeItem(at: nativeJournalURL(id))
            errorMessage = "Arka plan aktarımı başlatılamadı: \(error.localizedDescription)"
        }
        Task { [weak self] in
            await oldTask.value
            guard let self else { return }
            cancellingIDs.remove(id)
            guard let journal = readNativeJournal(id), journal.generation == generation, !journal.pending.isEmpty else {
                try? FileManager.default.removeItem(at: nativeJournalURL(id))
                if let index = entries.firstIndex(where: { $0.id == id && $0.isActive }) { entries[index].status = .queued; save() }
                finishPipeline(id)
                scheduleBackgroundProcessing()
                return
            }
        }
    }

    fileprivate func nativeBackgroundReceived(_ part: NativeBackgroundPart, file: URL) async {
        defer { try? FileManager.default.removeItem(at: file) }
        await pollers[part.entryID]?.value
        guard var journal = readNativeJournal(part.entryID), journal.generation == part.generation,
              journal.pending.contains(part.kind), let entry = entries.first(where: { $0.id == part.entryID && $0.isActive }) else { return }
        do {
            let dir = nativeScratchRoot.appendingPathComponent(part.entryID.uuidString).appendingPathComponent("checkpoint")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let stream = NativeYouTubeStream(url: URL(string: "https://googlevideo.com/")!, headers: [:], fileExtension: part.fileExtension,
                                             codec: part.codec, bitrate: part.bitrate, resolution: part.resolution, includesAudio: part.kind == "audio")
            _ = try NativeYouTubeDownloader.saveCheckpoint(dir, kind: part.kind, entry: entry, stream: stream, downloaded: file)
            journal.pending.remove(part.kind)
            try writeNativeJournal(journal, id: part.entryID)
            if journal.pending.isEmpty { finishNativeBackground(part.entryID, generation: part.generation) }
        } catch { nativeBackgroundFailed(part, error: error) }
    }

    func nativeBackgroundFailed(_ part: NativeBackgroundPart, error: Error) {
        guard let journal = readNativeJournal(part.entryID), journal.generation == part.generation else { return }
        // Invalidate before cancelling sibling tasks: their late callbacks must
        // not consume another retry or affect the next transfer generation.
        do { try FileManager.default.removeItem(at: nativeJournalURL(part.entryID)) }
        catch { errorMessage = "Aktarım kurtarma kaydı güncellenemedi: \(error.localizedDescription)"; return }
        Task { [weak self] in
            guard let self else { return }
            for task in await session.allTasks {
                guard let other = NativeBackgroundPart.parse(task.taskDescription), other.entryID == part.entryID,
                      other.generation == part.generation else { continue }
                task.cancel()
            }
        }
        // Preserve completed checkpoints and use the same bounded backoff as
        // foreground transfers. Network errors belong to the download row.
        networkFailed(part.entryID, error: error)
        scheduleBackgroundProcessing()
    }

    private func finishNativeBackground(_ id: UUID, generation: UUID) {
        guard readNativeJournal(id)?.generation == generation else { return }
        try? FileManager.default.removeItem(at: nativeJournalURL(id))
        if let index = entries.firstIndex(where: { $0.id == id && $0.isActive }) {
            entries[index].status = .queued; entries[index].progress = 0; save()
        }
        if !cancellingIDs.contains(id) { finishPipeline(id) }
        scheduleBackgroundProcessing()
    }

    // Requested only by a foreground user action. If iOS declines or expires it,
    // the existing background handoff and checkpoint recovery remain in charge.
    private func requestContinuedTaskForUserAction() {
        guard #available(iOS 26.0, *), productionBackgroundSession, isForeground,
              continuedTask == nil, continuedPendingID == nil,
              entries.contains(where: { $0.isActive }) else { return }
        func record(_ state: String) {
            UserDefaults.standard.set(state, forKey: "ritim.continuedDecision")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "ritim.continuedDecisionTime")
        }
        record("registering")
        let id = "com.mehmetderin.ritim.continued.\(UUID().uuidString)"
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let self, let task = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
                guard self.continuedPendingID == id, !self.isQueuePaused,
                      self.entries.contains(where: { $0.isActive }) else { task.setTaskCompleted(success: false); return }
                self.continuedPendingID = nil
                self.continuedTask = task
                UserDefaults.standard.set("running", forKey: "ritim.continuedDecision")
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "ritim.continuedDecisionTime")
                task.progress.totalUnitCount = 1_000_000
                task.expirationHandler = { [weak self] in
                    Task { @MainActor in
                        guard let self, self.continuedTask === task else { return }
                        self.continuedTask = nil
                        UserDefaults.standard.set("expired", forKey: "ritim.continuedDecision")
                        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "ritim.continuedDecisionTime")
                        task.setTaskCompleted(success: false)
                        if !self.isForeground { self.applicationDidEnterBackground() }
                    }
                }
                self.updateContinuedProgress()
                self.pump()
            }
        }
        guard registered else { record("registration-failed"); return }
        let request = BGContinuedProcessingTaskRequest(identifier: id, title: "Ritim indiriyor", subtitle: "İndirme kuyruğu hazırlanıyor")
        request.strategy = .fail
        continuedInitialCount = entries.filter(\.isActive).count
        continuedPendingID = id
        do { try BGTaskScheduler.shared.submit(request); record("submitted") }
        catch { continuedPendingID = nil; record("submission-failed-\((error as NSError).code)") }
    }

    private func finishContinuedTask(success: Bool) {
        if let id = continuedPendingID { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: id) }
        continuedPendingID = nil
        continuedTask?.setTaskCompleted(success: success)
        continuedTask = nil
    }

    private func updateContinuedProgress() {
        guard #available(iOS 26.0, *), let task = continuedTask as? BGContinuedProcessingTask else { return }
        let active = entries.filter(\.isActive)
        guard !active.isEmpty else { finishContinuedTask(success: true); return }
        let total = max(continuedInitialCount, active.count, 1)
        let progress = Double(total - active.count) + active.reduce(0.0) { $0 + min(1, max(0, $1.progress)) }
        task.progress.completedUnitCount = Int64(min(999_999, max(0, progress / Double(total) * 1_000_000)))
    }

    private func scheduleBackgroundProcessing() {
        guard backgroundNativeEnabled, !isForeground, !isQueuePaused, entries.contains(where: {
            $0.status == .queued && URL(string: $0.sourceURL).map(MediaURLPolicy.isYouTube) == true
        }) else { return }
        let request = BGProcessingTaskRequest(identifier: Self.processingIdentifier)
        // Completed checkpoints can be converted without a network connection.
        request.requiresNetworkConnectivity = false
        do { try BGTaskScheduler.shared.submit(request) }
        catch { bulkNotice = "Hazır dosyalar uygulama açıldığında tamamlanacak." }
    }

    // UIKit grants a short finishing window immediately after backgrounding or
    // a background URLSession delivery. Use only one small source and cap CPU
    // time; the normal BGProcessing task handles longer work when scheduled.
    private func startQuickBackgroundConversionIfPossible() {
        guard productionBackgroundSession, !isForeground else { return }
        func skip(_ reason: String) {
            UserDefaults.standard.set(reason, forKey: "ritim.shortBackgroundDecision")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "ritim.shortBackgroundDecisionTime")
        }
        guard !isQueuePaused else { skip("paused"); return }
        guard resourceLimit > 0 else { skip("thermal"); return }
        guard !isRestoring else { skip("restoring"); return }
        guard backgroundProcessingTask == nil, quickBackgroundID == nil else { skip("already-processing"); return }
        guard UIApplication.shared.applicationState == .background else { skip("not-background"); return }
        let last = UserDefaults.standard.double(forKey: "ritim.lastShortBackgroundConversion")
        guard Date().timeIntervalSince1970 - last >= 90 else { skip("cooldown"); return }
        var diagnostics: [String: Int] = [:]
        func count(_ reason: String) { diagnostics[reason, default: 0] += 1 }
        let candidates: [(DownloadEntry, URL, URL?, Int)] = entries.compactMap { entry in
            guard let source = URL(string: entry.sourceURL), MediaURLPolicy.isYouTube(source) else { return nil }
            let dir = nativeScratchRoot.appendingPathComponent(entry.id.uuidString).appendingPathComponent("checkpoint")
            // Restrict diagnostics to entries that have a checkpoint marker; do not record media identities.
            guard FileManager.default.fileExists(atPath: NativeYouTubeDownloader.checkpointURL(dir, kind: "audio").path) else { return nil }
            guard entry.status == .queued, (entry.retryAfter ?? .distantPast) <= Date() else { count("status-\(entry.status.rawValue)"); return nil }
            guard !pipelineIDs.contains(entry.id) else {
                count("pipeline-busy")
                count(pollers[entry.id] == nil ? "busy-no-poller" : "busy-poller")
                if cancellingIDs.contains(entry.id) { count("busy-cancelling") }
                if readNativeJournal(entry.id) != nil { count("busy-journal") }
                return nil
            }
            guard !cancellingIDs.contains(entry.id) else { count("cancelling"); return nil }
            guard let audio = NativeYouTubeDownloader.verifiedCheckpoint(dir, kind: "audio", entry: entry) else {
                do { _ = try Data(contentsOf: NativeYouTubeDownloader.checkpointURL(dir, kind: "audio")); count("checkpoint-invalid") }
                catch { count("marker-read-error-\((error as NSError).code)") }
                return nil
            }
            guard let size = try? audio.resourceValues(forKeys: [.fileSizeKey]).fileSize else { count("size-unreadable"); return nil }
            guard size <= 10 * 1_024 * 1_024 else { count("too-large"); return nil }
            let video = NativeYouTubeDownloader.verifiedCheckpoint(dir, kind: "video", entry: entry)
            guard entry.format != .mp4 || video != nil else { count("video-unavailable"); return nil }
            count("ready")
            return (entry, audio, video, size)
        }
        UserDefaults.standard.set(diagnostics, forKey: "ritim.shortBackgroundCandidates")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "ritim.shortBackgroundCandidatesTime")
        guard let (entry, audio, video, _) = candidates.min(by: { $0.3 < $1.3 }) else { skip("no-ready-source"); return }
        let id = entry.id
        let assertion = UIApplication.shared.beginBackgroundTask(withName: "Ritim kısa dönüşüm") { [weak self] in
            Task { @MainActor in self?.pollers[id]?.cancel() }
        }
        guard assertion != .invalid else { skip("no-system-time"); return }
        quickBackgroundAssertion = assertion
        quickBackgroundID = id
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "ritim.lastShortBackgroundConversion")
        UserDefaults.standard.set("started", forKey: "ritim.shortBackgroundDecision")
        UserDefaults.standard.set("started", forKey: "ritim.shortBackgroundOutcome")
        pipelineIDs.insert(id)
        let token = id.uuidString + ":" + UUID().uuidString
        transferTokens[id] = token
        guard set(id, update: { $0.status = .downloading; $0.progress = 0.75 }) else {
            quickBackgroundID = nil; quickBackgroundAssertion = .invalid
            UIApplication.shared.endBackgroundTask(assertion)
            finishPipeline(id)
            return
        }
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled, let self, self.quickBackgroundID == id else { return }
            self.pollers[id]?.cancel()
        }
        pollers[id] = Task { [weak self] in
            guard let self else { timeout.cancel(); return }
            defer {
                timeout.cancel()
                pollers.removeValue(forKey: id)
                quickBackgroundID = nil
                if quickBackgroundAssertion == assertion {
                    quickBackgroundAssertion = .invalid
                    UIApplication.shared.endBackgroundTask(assertion)
                }
                scheduleBackgroundProcessing()
            }
            do {
                let directory = nativeScratchRoot.appendingPathComponent(id.uuidString, isDirectory: true)
                let output = try await NativeMediaConverter.convert(audio: audio, video: video, format: entry.format,
                                                                    quality: entry.effectiveQuality, outputDirectory: directory) { [weak self] value in
                    Task { @MainActor in self?.updateProgress(id, progress: 0.75 + value * 0.23, token: token) }
                }
                defer { try? FileManager.default.removeItem(at: output) }
                try Task.checkCancellation()
                timeout.cancel()
                await receive(id, file: output, token: token)
                if entries.contains(where: { $0.id == id && $0.status == .completed }) {
                    UserDefaults.standard.set("completed", forKey: "ritim.shortBackgroundOutcome")
                    try? FileManager.default.removeItem(at: directory)
                } else { UserDefaults.standard.set("import-failed", forKey: "ritim.shortBackgroundOutcome") }
            } catch is CancellationError {
                UserDefaults.standard.set("interrupted", forKey: "ritim.shortBackgroundOutcome")
                if accepts(id, token: token), let index = entries.firstIndex(where: { $0.id == id && $0.isActive }) {
                    entries[index].status = .queued; entries[index].progress = 0; save()
                }
                if !cancellingIDs.contains(id) { finishPipeline(id) }
                scheduleBackgroundProcessing()
            } catch {
                UserDefaults.standard.set("failed", forKey: "ritim.shortBackgroundOutcome")
                if accepts(id, token: token) { failed(id, message: error.localizedDescription, token: token) }
            }
        }
    }

    func runBackgroundProcessing(_ task: BGProcessingTask) {
        guard backgroundProcessingTask == nil, quickBackgroundID == nil else { task.setTaskCompleted(success: false); return }
        backgroundProcessingTask = task
        task.expirationHandler = { [weak self] in
            Task { @MainActor in self?.expireBackgroundProcessing() }
        }
        Task { [weak self] in
            guard let self else { task.setTaskCompleted(success: false); return }
            while isRestoring && backgroundProcessingTask != nil { try? await Task.sleep(for: .milliseconds(100)) }
            guard backgroundProcessingTask != nil else { return }
            pump()
            while backgroundProcessingTask != nil && !backgroundProcessingIDs.isEmpty {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard let current = backgroundProcessingTask else { return }
            backgroundProcessingTask = nil
            current.setTaskCompleted(success: true)
            scheduleBackgroundProcessing()
        }
    }

    private func expireBackgroundProcessing() {
        guard let task = backgroundProcessingTask else { return }
        backgroundProcessingTask = nil
        for id in backgroundProcessingIDs {
            transferTokens.removeValue(forKey: id)
            pollers[id]?.cancel()
            if let index = entries.firstIndex(where: { $0.id == id && $0.isActive }) {
                entries[index].status = .queued; entries[index].progress = 0
            }
        }
        if !backgroundProcessingIDs.isEmpty { save() }
        backgroundProcessingIDs.removeAll()
        task.setTaskCompleted(success: false)
        scheduleBackgroundProcessing()
    }
    func cancelAll(ids: Set<UUID>? = nil) {
        let original = entries
        let active = entries.filter { $0.isActive && (ids?.contains($0.id) ?? true) }
        let selected = Set(active.map(\.id))
        for i in entries.indices where selected.contains(entries[i].id) { entries[i].status = .cancelled }
        guard save() else { entries = original; return }
        // Queued rows have no network task. Only occupied pipelines need cancellation work.
        for entry in active {
            if pipelineIDs.contains(entry.id) || entry.serverID != nil { cancelRunning(entry) }
            else { try? FileManager.default.removeItem(at: nativeScratchRoot.appendingPathComponent(entry.id.uuidString, isDirectory: true)) }
        }
    }
    func retryFailed(ids: Set<UUID>? = nil) {
        let original = entries
        var remaining = max(0, Self.queueLimit - entries.filter(\.isActive).count)
        var known = Set(entries.filter(\.isActive).compactMap { MediaURLPolicy.downloadKey($0.sourceURL, format: $0.format, quality: $0.quality) })
        var retrying: [DownloadEntry] = []
        var retryIDs: Set<UUID> = []
        for old in entries where (old.status == .failed || (ids != nil && old.status == .cancelled)) && (ids?.contains(old.id) ?? true) && remaining > 0 {
            guard let key = MediaURLPolicy.downloadKey(old.sourceURL, format: old.format, quality: old.quality), !known.contains(key) else { continue }
            var entry = old
            resetForRetry(&entry)
            retrying.append(entry); retryIDs.insert(entry.id); known.insert(key); remaining -= 1
        }
        entries.removeAll { retryIDs.contains($0.id) }; entries.append(contentsOf: retrying)
        guard save() else { entries = original; return }
        pump()
    }
    func cancel(_ entry: DownloadEntry) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }), entries[i].isActive else { return }
        let current = entries[i]
        entries[i].status = .cancelled
        guard save() else { entries[i] = current; return }
        if pipelineIDs.contains(current.id) || current.serverID != nil { cancelRunning(current) }
        else { try? FileManager.default.removeItem(at: nativeScratchRoot.appendingPathComponent(current.id.uuidString, isDirectory: true)) }
    }
    private func cancelRunning(_ current: DownloadEntry) {
        let hadPipeline = pipelineIDs.contains(current.id)
        cancellingIDs.insert(current.id)
        let currentPoller = pollers[current.id]
        currentPoller?.cancel()
        transferTokens.removeValue(forKey: current.id)
        Task { [weak self] in
            guard let self else { return }
            await currentPoller?.value
            for task in await session.allTasks where downloadEntryID(task.taskDescription) == current.id { task.cancel() }
            try? FileManager.default.removeItem(at: nativeScratchRoot.appendingPathComponent(current.id.uuidString, isDirectory: true))
            cancellingIDs.remove(current.id)
            if hadPipeline { finishPipeline(current.id) } else { pump() }
        }
    }
    func retry(_ entry: DownloadEntry) { requeue(entry.id, schedule: true) }
    private func requeue(_ id: UUID, schedule: Bool) {
        guard let index = entries.firstIndex(where: { $0.id == id }), [.failed, .cancelled].contains(entries[index].status) else { return }
        guard entries.filter(\.isActive).count < Self.queueLimit else { bulkNotice = "Kuyruk dolu. En fazla \(Self.queueLimit) bekleyen indirme olabilir."; return }
        let original = entries
        var entry = entries.remove(at: index)
        if let key = MediaURLPolicy.downloadKey(entry.sourceURL, format: entry.format, quality: entry.quality), entries.contains(where: { $0.isActive && MediaURLPolicy.downloadKey($0.sourceURL, format: $0.format, quality: $0.quality) == key }) { entries = original; return }
        resetForRetry(&entry)
        entries.append(entry)
        guard save() else { entries = original; return }
        if schedule { pump() }
    }
    private func resetForRetry(_ entry: inout DownloadEntry) {
        entry.status = .queued; entry.progress = 0; entry.error = nil; entry.serverID = nil; entry.trackID = nil; entry.serverAcknowledged = nil
        entry.serverBaseURL = nil; entry.resolvedQuality = nil; entry.qualityNote = nil
        entry.stage = nil; entry.retryCount = nil; entry.retryAfter = nil; entry.receivedBytes = nil; entry.expectedBytes = nil; entry.bytesPerSecond = nil
    }
    func clearFinished() {
        let before = entries
        entries.removeAll { !$0.isActive && !($0.status == .completed && $0.serverID != nil && $0.serverAcknowledged != true) && !cancellingIDs.contains($0.id) }
        if !save() { entries = before } else { prunePlaylistReservations() }
    }

    private func prunePlaylistReservations() {
        var retained: [UUID: Set<UUID>] = [:]
        for entry in entries {
            retained[entry.id, default: []].formUnion([entry.playlistID].compactMap { $0 } + (entry.additionalPlaylistIDs ?? []))
        }
        do { try library.pruneDownloadReservations(retained: retained) }
        catch { errorMessage = "Oynatma listesi sırası kaydedilemedi: \(error.localizedDescription)" }
    }

    func resolvePlaylist(url: String) async {
        cancelPlaylistResolution()
        let generation = UUID()
        resolverGeneration = generation
        playlistPreview = nil; isResolvingPlaylist = true
        resolverTask = Task { [weak self] in
            guard let self else { return }
            defer { if resolverGeneration == generation { isResolvingPlaylist = false; resolverTask = nil } }
            do {
                let preview: PlaylistPreview
                let notice: String
                if let input = try? MediaURLPolicy.validatedPlaylist(url) {
                    preview = try await catalog.resolvePlaylist(url: input, limit: Self.queueLimit)
                    notice = "\(preview.items.count) parça bulundu. İndirmek istediklerini seç."
                } else if let video = try? MediaURLPolicy.singleVideo(url), MediaURLPolicy.isYouTube(video) {
                    // A single video pasted here is shown as a one-item list instead of an error.
                    let item = await catalog.video(url: video)
                    preview = PlaylistPreview(id: "video-" + item.id, status: "completed", title: item.title, items: [item],
                                              skipped: 0, truncated: false, error: nil)
                    notice = "Bu tek bir video bağlantısı; seçili olarak gösterildi, hemen indirebilirsin."
                } else {
                    _ = try MediaURLPolicy.validatedPlaylist(url)
                    return
                }
                try Task.checkCancellation()
                guard resolverGeneration == generation else { return }
                playlistPreview = preview
                bulkNotice = notice
            } catch is CancellationError { }
            catch { if resolverGeneration == generation { bulkNotice = error.localizedDescription } }
        }
        await resolverTask?.value
    }
    func cancelPlaylistResolution() {
        resolverGeneration = UUID()
        resolverTask?.cancel(); resolverTask = nil; isResolvingPlaylist = false
    }

    private func restore() async {
        let tasks = await session.allTasks
        let deliveringIDs = await delegate.pendingDeliveryIDs(afterDraining: delegateQueue)
        let nativeTaskIDs = Set(tasks.compactMap { NativeBackgroundPart.parse($0.taskDescription)?.entryID })
        // Keep completed source checkpoints for active jobs; discard all other
        // scratch. Permanent Media and journals are in separate directories.
        let scratch = nativeScratchRoot
        if scratch.standardizedFileURL.path != library.directory.standardizedFileURL.path,
           FileManager.default.fileExists(atPath: scratch.path) {
            do {
                let active = Set(entries.filter(\.isActive).map { $0.id.uuidString })
                for child in try FileManager.default.contentsOfDirectory(at: scratch, includingPropertiesForKeys: nil) {
                    let checkpoint = child.appendingPathComponent("checkpoint", isDirectory: true)
                    let hasMarker = ["audio", "video"].contains { FileManager.default.fileExists(atPath: NativeYouTubeDownloader.checkpointURL(checkpoint, kind: $0).path) }
                    let id = UUID(uuidString: child.lastPathComponent)
                    let hasNativeWork = id.map { nativeTaskIDs.contains($0) || deliveringIDs.contains($0) } ?? false
                    if !active.contains(child.lastPathComponent) || (!hasMarker && !hasNativeWork) { try FileManager.default.removeItem(at: child) }
                    else {
                        // Interrupted conversions leave UUID-named outputs in this
                        // scratch folder. They are incomplete and can be rebuilt
                        // from the preserved checkpoint; never touch Media files.
                        for file in (try? FileManager.default.contentsOfDirectory(at: child, includingPropertiesForKeys: nil)) ?? [] {
                            if ["mp3", "mp4"].contains(file.pathExtension.lowercased()), UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil {
                                try FileManager.default.removeItem(at: file)
                            }
                        }
                        for file in (try? FileManager.default.contentsOfDirectory(at: checkpoint, includingPropertiesForKeys: nil)) ?? [] {
                            if !["audio.m4a", "video.mp4", "audio.checkpoint.json", "video.checkpoint.json"].contains(file.lastPathComponent) {
                                try FileManager.default.removeItem(at: file)
                            }
                        }
                    }
                }
                if try FileManager.default.contentsOfDirectory(atPath: scratch.path).isEmpty { try FileManager.default.removeItem(at: scratch) }
            }
            catch { errorMessage = "Yarım kalan indirme dosyaları temizlenemedi: \(error.localizedDescription)" }
        }
        for task in tasks {
            guard let id = downloadEntryID(task.taskDescription), let entry = entries.first(where: { $0.id == id && $0.isActive }),
                  entry.serverID == nil else { task.cancel(); continue }
            if let part = NativeBackgroundPart.parse(task.taskDescription) {
                guard let journal = readNativeJournal(id), journal.generation == part.generation, journal.pending.contains(part.kind) else { task.cancel(); continue }
                pipelineIDs.insert(id)
                continue
            }
            pipelineIDs.insert(id); transferTokens[id] = task.taskDescription
        }
        // A process can die after the journal write but before every system
        // task has been created. Never leave that incomplete handoff stuck.
        for entry in entries where entry.isActive {
            guard let journal = readNativeJournal(entry.id), !deliveringIDs.contains(entry.id) else { continue }
            let matching = tasks.compactMap { task -> NativeBackgroundPart? in
                guard let part = NativeBackgroundPart.parse(task.taskDescription), part.entryID == entry.id,
                      part.generation == journal.generation else { return nil }
                return part
            }
            if !journal.pending.isSubset(of: Set(matching.map(\.kind))) {
                for task in tasks where NativeBackgroundPart.parse(task.taskDescription)?.entryID == entry.id { task.cancel() }
                try? FileManager.default.removeItem(at: nativeJournalURL(entry.id))
                pipelineIDs.remove(entry.id)
            }
        }
        for i in entries.indices {
            if entries[i].isActive, entries[i].serverID != nil {
                entries[i].serverID = nil; entries[i].serverBaseURL = nil
                entries[i].status = .queued; entries[i].progress = 0
            } else if entries[i].status == .completed, entries[i].serverID != nil {
                // Old server cleanup is retired; the permanent iPhone file stays untouched.
                entries[i].serverAcknowledged = true
            }
        }
        let stillActiveIDs = Set(entries.filter(\.isActive).map(\.id))
        pipelineIDs.formIntersection(stillActiveIDs)
        pipelineIDs.formUnion(deliveringIDs.intersection(stillActiveIDs))
        // A library import is committed before downloads.json. Recover only
        // exact, playable imports from that gap; completed rows are left alone
        // so later user edits/removals from playlists are never resurrected.
        let interrupted = entries.filter { $0.isActive && !pipelineIDs.contains($0.id) }
        for entry in interrupted {
            guard let track = await library.recoveredDownload(for: entry),
                  let index = entries.firstIndex(where: { $0.id == entry.id && $0.isActive }),
                  !pipelineIDs.contains(entry.id) else { continue }
            do {
                try library.completeRecoveredDownload(track, entry: entries[index])
                entries[index].trackID = track.id; entries[index].status = .completed
                entries[index].progress = 1; entries[index].error = nil
                entries[index].serverAcknowledged = entries[index].serverID == nil ? nil : true
            } catch {
                // Retain the imported file and pause; retrying the transfer
                // here could duplicate data when the library is unwritable.
                isQueuePaused = true
                errorMessage = "Tamamlanan indirme kaydı kurtarılamadı: \(error.localizedDescription)"
            }
        }
        for i in entries.indices where entries[i].isActive && !pipelineIDs.contains(entries[i].id) { entries[i].status = .queued }
        save()
        prunePlaylistReservations()
        isRestoring = false
        pump()
        scheduleBackgroundProcessing()
        startQuickBackgroundConversionIfPossible()
    }

    private func pump() {
        scheduleRetryWake()
        guard !isRestoring, !isQueuePaused, historyWritable else { return }
        // Finish short, already-downloaded sources first; long conversions no
        // longer block every small item behind the single encoder permit.
        var readySizes: [UUID: Int] = [:]
        let indexed = entries.filter { $0.status == .queued }.reduce(into: [UUID: DownloadEntry]()) { $0[$1.id] = $1 }
        for directory in (try? FileManager.default.contentsOfDirectory(at: nativeScratchRoot, includingPropertiesForKeys: nil)) ?? [] {
            guard let id = UUID(uuidString: directory.lastPathComponent), let entry = indexed[id] else { continue }
            let checkpoint = directory.appendingPathComponent("checkpoint", isDirectory: true)
            guard let audio = NativeYouTubeDownloader.verifiedCheckpoint(checkpoint, kind: "audio", entry: entry),
                  let size = try? audio.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= 10 * 1_024 * 1_024,
                  entry.format != .mp4 || NativeYouTubeDownloader.verifiedCheckpoint(checkpoint, kind: "video", entry: entry) != nil else { continue }
            readySizes[id] = size
        }
        while pipelineIDs.count < effectiveConcurrency {
            let eligible = entries.filter {
                guard $0.status == .queued && ($0.retryAfter ?? .distantPast) <= Date() && !pipelineIDs.contains($0.id) && !cancellingIDs.contains($0.id) else { return false }
                guard !isForeground else { return true }
                guard let url = URL(string: $0.sourceURL) else { return true }
                if MediaURLPolicy.isYouTube(url) { return backgroundProcessingTask != nil || continuedTask != nil }
                return true
            }
            let highestPriority = eligible.map { $0.priority ?? 0 }.max() ?? 0
            let candidates = eligible.filter { ($0.priority ?? 0) == highestPriority }
            let short = candidates.filter { readySizes[$0.id] != nil }.min { readySizes[$0.id]! < readySizes[$1.id]! }
            guard let entry = (shortReadyStreak < 3 ? short : nil) ?? candidates.first else { break }
            shortReadyStreak = short?.id == entry.id && shortReadyStreak < 3 ? shortReadyStreak + 1 : 0
            pipelineIDs.insert(entry.id)
            if !isForeground, backgroundProcessingTask != nil, let url = URL(string: entry.sourceURL), MediaURLPolicy.isYouTube(url) {
                backgroundProcessingIDs.insert(entry.id)
            }
            guard set(entry.id, update: { $0.status = .preparing; $0.stage = .resolving }) else { pipelineIDs.remove(entry.id); break }
            if let url = URL(string: entry.sourceURL), MediaURLPolicy.isYouTube(url) { prepare(entry.id) }
            else if let url = try? MediaURLPolicy.canonicalInput(entry.sourceURL) { transfer(entry.id, request: URLRequest(url: url)) }
            else { failed(entry.id, message: "Kaydedilmiş medya bağlantısı geçersiz.") }
        }
    }
    private func finishPipeline(_ id: UUID) {
        progressTimes.removeValue(forKey: id); transferSamples.removeValue(forKey: id)
        pipelineIDs.remove(id); transferTokens.removeValue(forKey: id); resolvedNativeMedia.removeValue(forKey: id); backgroundProcessingIDs.remove(id)
        pump()
        updateContinuedProgress()
        startQuickBackgroundConversionIfPossible()
    }

    private func prepare(_ id: UUID) {
        guard pollers[id] == nil else { return }
        let token = id.uuidString + ":" + UUID().uuidString
        transferTokens[id] = token
        pollers[id] = Task { [weak self] in
            guard let self else { return }
            defer {
                pollers.removeValue(forKey: id)
                if Task.isCancelled, !cancellingIDs.contains(id) { finishPipeline(id) }
            }
            do {
                // A background notification can cancel a scheduled poller before
                // its body first runs. Do not recreate its invalidated token.
                try Task.checkCancellation()
                guard (isForeground || backgroundProcessingIDs.contains(id) || continuedTask != nil), accepts(id, token: token) else { return }
                guard let entry = entries.first(where: { $0.id == id }), entry.isActive else { return }
                if let available = try? library.directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
                   available < 256 * 1_024 * 1_024 {
                    pauseQueue()
                    throw RitimError.message("İndirmek ve dönüştürmek için en az 256 MB boş alan gerekli.")
                }
                let directory = nativeScratchRoot.appendingPathComponent(id.uuidString, isDirectory: true)
                // A background interruption may leave a complete source for reuse.
                defer {
                    let preserve = (Task.isCancelled || entries.contains { $0.id == id && $0.retryAfter != nil }) && entries.contains { $0.id == id && $0.isActive } &&
                        (readNativeJournal(id) != nil || !cancellingIDs.contains(id))
                    if !preserve { try? FileManager.default.removeItem(at: directory) }
                }
                let checkpoint = directory.appendingPathComponent("checkpoint", isDirectory: true)
                let audio = NativeYouTubeDownloader.verifiedCheckpoint(checkpoint, kind: "audio", entry: entry)
                let video = NativeYouTubeDownloader.verifiedCheckpoint(checkpoint, kind: "video", entry: entry)
                let output: URL
                if let audio, entry.format != .mp4 || video != nil {
                    // A verified local source needs no fresh YouTube extraction or network transfer.
                    output = try await NativeMediaConverter.convert(audio: audio, video: video, format: entry.format,
                                                                    quality: entry.effectiveQuality, outputDirectory: directory) { [weak self] value in
                        Task { @MainActor in self?.updateProgress(id, progress: 0.75 + value * 0.23, token: token) }
                    }
                } else {
                    var provider = nativeDownloader
                    if var native = provider as? NativeYouTubeDownloader {
                        native.transferMetrics = { [weak self] bytes, total in self?.recordTransferBytes(id, received: bytes, expected: total, token: token) }
                        provider = native
                    }
                    output = try await provider.download(entry: entry, directory: directory, metadata: { [weak self] media in
                        guard let self, self.accepts(id, token: token), self.entries.contains(where: { $0.id == id && $0.isActive }) else { return }
                        self.resolvedNativeMedia[id] = media
                        self.set(id) {
                            $0.title = media.title; $0.artist = media.artist; $0.status = .downloading; $0.stage = .transferring
                            $0.resolvedQuality = entry.format == .mp3 ? entry.effectiveQuality.detail(for: .mp3) : "\(media.actualResolution ?? 0)p • iPhone’da hazırlandı"
                            $0.qualityNote = media.qualityNote
                        }
                    }, progress: { [weak self] value in self?.updateProgress(id, progress: value, token: token) })
                }
                try Task.checkCancellation()
                await receive(id, file: output, token: token)
            } catch is CancellationError { }
            catch { if !Task.isCancelled { networkFailed(id, error: error, token: token) } }
        }
    }
    private func transfer(_ id: UUID, request: URLRequest) {
        guard entries.first(where: { $0.id == id })?.isActive == true else { return }
        guard set(id, update: { $0.status = .downloading; $0.stage = .transferring }) else { failed(id, message: "Aktarım durumu kaydedilemedi."); return }
        if let available = try? library.directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           available < 128 * 1_024 * 1_024 {
            pauseQueue()
            failed(id, message: "Aygıtta 128 MB'dan az boş alan var. Yer açıp kuyruğu sürdür ve bu dosyayı yeniden dene.")
            return
        }
        let token = id.uuidString + ":" + UUID().uuidString
        transferTokens[id] = token
        let task = session.downloadTask(with: request); task.taskDescription = token; task.resume()
    }
    private func accepts(_ id: UUID, token: String?) -> Bool {
        if let token, transferTokens[id] == nil, isRestoring, entries.contains(where: { $0.id == id && $0.isActive }) {
            transferTokens[id] = token; pipelineIDs.insert(id)
        }
        return token == nil || transferTokens[id] == token
    }
    private func scheduleRetryWake() {
        retryWakeTask?.cancel(); retryWakeTask = nil
        guard !isQueuePaused, let date = entries.filter({ $0.status == .queued }).compactMap(\.retryAfter).filter({ $0 > Date() }).min() else { return }
        retryWakeTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0.1, date.timeIntervalSinceNow))) }
            catch { return }
            self?.pump()
        }
    }
    func networkFailed(_ id: UUID, error: Error, token: String? = nil) {
        guard accepts(id, token: token), let entry = entries.first(where: { $0.id == id }), entry.isActive else { return }
        guard let delay = DownloadRetryPolicy.delay(error: error, attempt: entry.retryCount ?? 0) else {
            failed(id, message: error.localizedDescription, token: token); return
        }
        guard set(id, update: {
            $0.status = .queued; $0.stage = nil; $0.progress = 0
            $0.retryCount = (entry.retryCount ?? 0) + 1
            $0.retryAfter = Date().addingTimeInterval(delay)
            $0.error = "Bağlantı kesildi. Yeniden deneme \($0.retryCount ?? 1)/3 bekleniyor."
        }) else { failed(id, message: "Yeniden deneme kaydedilemedi.", token: token); return }
        finishPipeline(id)
    }
    private func recordTransferBytes(_ id: UUID, received: Int64, expected: Int64, token: String?) {
        guard accepts(id, token: token), let index = entries.firstIndex(where: { $0.id == id }), entries[index].isActive else { return }
        let now = ProcessInfo.processInfo.systemUptime
        var sample = transferSamples[id]
        if let previous = sample, received < previous.bytes || expected != previous.total { sample = nil }
        if let previous = sample, now - previous.time < 0.25, received != expected { return }
        entries[index].receivedBytes = max(0, received)
        entries[index].expectedBytes = expected > 0 ? expected : nil
        let elapsed = sample.map { now - $0.time } ?? 0
        let rate = elapsed > 0 ? Double(max(0, received - (sample?.bytes ?? 0))) / elapsed : 0
        let speed = sample.map { $0.speed > 0 ? $0.speed * 0.7 + rate * 0.3 : rate } ?? 0
        let started = sample?.started ?? now
        entries[index].bytesPerSecond = now - started >= 2 && speed > 0 ? speed : nil
        transferSamples[id] = (received, expected, now, started, speed)
    }
    func updateTransfer(_ id: UUID, received: Int64, expected: Int64, progress: Double, token: String? = nil) {
        guard accepts(id, token: token), let i = entries.firstIndex(where: { $0.id == id }), entries[i].isActive else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard progress >= 1 || now - (progressTimes[id] ?? 0) >= 0.25 else { return }
        recordTransferBytes(id, received: received, expected: expected, token: token)
        updateProgress(id, progress: progress, token: token)
    }
    func updateProgress(_ id: UUID, progress: Double, token: String? = nil) {
        guard accepts(id, token: token), let i = entries.firstIndex(where: { $0.id == id }), entries[i].isActive else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard progress >= 1 || now - (progressTimes[id] ?? 0) >= 0.25 else { return }
        progressTimes[id] = now
        entries[i].progress = entries[i].serverID == nil ? min(1, max(0, progress)) : 0.8 + min(1, max(0, progress)) * 0.2
        if entries[i].serverID == nil, let url = URL(string: entries[i].sourceURL), MediaURLPolicy.isYouTube(url), progress >= 0.75 {
            entries[i].stage = .converting
        }
        updateContinuedProgress()
    }
    func receive(_ id: UUID, file: URL, token: String? = nil) async {
        defer { try? FileManager.default.removeItem(at: file) }
        guard accepts(id, token: token), let entry = entries.first(where: { $0.id == id }), entry.isActive else { return }
        do {
            guard set(id, update: { $0.stage = .saving }) else { throw RitimError.message("İşlem kaydı yazılamadı.") }
            let fileSize = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if let available = try? library.directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
               available < Int64(fileSize) + 64 * 1_024 * 1_024 {
                pauseQueue()
                throw RitimError.message("Dosyayı kütüphaneye kaydetmek için yeterli boş alan yok. Yer açıp yeniden dene.")
            }
            let playlistIDs = [entry.playlistID].compactMap { $0 } + (entry.additionalPlaylistIDs ?? [])
            let track = try await library.importDownloadedFile(file, title: entry.title, artist: entry.artist, sourceURL: entry.sourceURL,
                                                              downloadQuality: entry.quality, downloadEntryID: id, playlistIDs: playlistIDs)
            guard accepts(id, token: token), let current = entries.first(where: { $0.id == id }), current.isActive else { library.delete(track); return }
            set(id) { $0.trackID = track.id; $0.status = .completed; $0.progress = 1; $0.error = nil; $0.serverAcknowledged = entry.serverID == nil ? nil : false }
            finishPipeline(id)
        } catch { failed(id, message: error.localizedDescription, token: token) }
    }
    func failed(_ id: UUID, message: String, token: String? = nil) {
        guard accepts(id, token: token), let entry = entries.first(where: { $0.id == id }), entry.isActive else { return }
        set(id) { $0.status = .failed; $0.error = message }
        finishPipeline(id)
    }
    func taskCancelled(_ id: UUID, token: String? = nil) { failed(id, message: "Aktarım durdu veya 1 GB sınırı aşıldı. Yeniden dene.", token: token) }

    @discardableResult
    private func set(_ id: UUID, update: (inout DownloadEntry) -> Void) -> Bool {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return false }
        update(&entries[i]); return save()
    }
    private func saveSettings() {
        do { try JSONEncoder().encode(Settings(isQueuePaused: isQueuePaused, keepScreenAwake: keepScreenAwake, maxConcurrentDownloads: maxConcurrentDownloads, downloadQuality: downloadQuality)).write(to: settingsURL, options: .atomic) }
        catch { errorMessage = "Kuyruk ayarları kaydedilemedi: \(error.localizedDescription)" }
    }
    @discardableResult
    private func save() -> Bool {
        guard historyWritable else { return false }
        let beforePruning = entries
        do {
            // Preserve all unfinished and unacknowledged rows. Only disposable terminal history is bounded.
            var discardable = entries.filter { !$0.isActive && !($0.status == .completed && $0.serverID != nil && $0.serverAcknowledged != true) && !cancellingIDs.contains($0.id) }.count - 2_000
            if discardable > 0 {
                entries.removeAll { entry in
                    guard discardable > 0, !entry.isActive, !(entry.status == .completed && entry.serverID != nil && entry.serverAcknowledged != true), !cancellingIDs.contains(entry.id) else { return false }
                    discardable -= 1; return true
                }
            }
            try JSONEncoder().encode(entries).write(to: stateURL, options: .atomic)
            return true
        } catch {
            entries = beforePruning
            isQueuePaused = true
            saveSettings()
            errorMessage = "İndirme geçmişi kaydedilemedi; kuyruk duraklatıldı: \(error.localizedDescription)"
            return false
        }
    }
}
