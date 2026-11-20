import XCTest
@testable import Ritim

private final class BulkProtocol: URLProtocol, @unchecked Sendable {
    struct Reply { var status = 200; var body: Data; var delay: TimeInterval = 0; var mime = "application/json" }
    private static let lock = NSLock()
    private static var responseHandler: ((URLRequest) -> Reply)?
    static func handle(_ handler: @escaping (URLRequest) -> Reply) { lock.withLock { responseHandler = handler } }
    private let stopLock = NSLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let handler = Self.lock.withLock { Self.responseHandler }
        let result = handler?(request) ?? Reply(status: 500, body: Data())
        DispatchQueue.global().asyncAfter(deadline: .now() + result.delay) { [self] in
            guard !stopLock.withLock({ stopped }) else { return }
            let response = HTTPURLResponse(url: request.url!, statusCode: result.status, httpVersion: nil, headerFields: ["Content-Type": result.mime])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { stopLock.withLock { stopped = true } }
}

private struct HandoffNativeDownloader: NativeDownloadProviding {
    func download(entry: DownloadEntry, directory: URL,
                  metadata: @escaping @MainActor @Sendable (NativeYouTubeMedia) -> Void,
                  progress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> URL {
        let audio = NativeYouTubeStream(url: URL(string: "https://media.googlevideo.com/test")!, headers: [:], fileExtension: "m4a", codec: "aac", bitrate: 128000, resolution: nil, includesAudio: true)
        let video = entry.format == .mp4 ? NativeYouTubeStream(url: URL(string: "https://media.googlevideo.com/video")!, headers: [:], fileExtension: "mp4", codec: "avc1", bitrate: 512000, resolution: 720, includesAudio: false) : nil
        await metadata(NativeYouTubeMedia(title: "Test", artist: "Test", audio: audio, video: video, actualResolution: video?.resolution, sourceHighestResolution: video?.resolution, sourceAudioBitrate: 128000))
        try await Task.sleep(for: .seconds(30))
        throw CancellationError()
    }
}

private final class BulkRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func add(_ value: String) { lock.withLock { values.append(value) } }
    var all: [String] { lock.withLock { values } }
}


private final class BulkNativeDownloader: NativeDownloadProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var received: [DownloadEntry] = []
    private var active = 0
    private var peak = 0
    private var cancellations = 0
    let delay: TimeInterval
    let source: URL?
    let ignoreCancellation: Bool
    let delaysByURL: [String: TimeInterval]
    let cancellationCleanupDelay: TimeInterval
    init(delay: TimeInterval = 0.35, source: URL? = nil, ignoreCancellation: Bool = false,
         delaysByURL: [String: TimeInterval] = [:], cancellationCleanupDelay: TimeInterval = 0) {
        self.delay = delay; self.source = source; self.ignoreCancellation = ignoreCancellation; self.delaysByURL = delaysByURL
        self.cancellationCleanupDelay = cancellationCleanupDelay
    }
    var entries: [DownloadEntry] { lock.withLock { received } }
    var peakActive: Int { lock.withLock { peak } }
    var cancelledCount: Int { lock.withLock { cancellations } }
    func download(entry: DownloadEntry, directory: URL,
                  metadata: @escaping @MainActor @Sendable (NativeYouTubeMedia) -> Void,
                  progress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> URL {
        let number = lock.withLock { () -> Int in
            received.append(entry); active += 1; peak = max(peak, active); return received.count
        }
        defer { lock.withLock { active -= 1 } }
        do { try await Task.sleep(for: .seconds(delaysByURL[entry.sourceURL] ?? delay)) }
        catch {
            lock.withLock { cancellations += 1 }
            // Model an encoder unwinding/closing files after observing cancellation.
            // The store must retain its pipeline slot until this actually returns.
            if cancellationCleanupDelay > 0 {
                try? await Task.detached { [cancellationCleanupDelay] in
                    try await Task.sleep(for: .seconds(cancellationCleanupDelay))
                }.value
            }
            if !ignoreCancellation { throw error }
        }
        if !ignoreCancellation { try Task.checkCancellation() }
        guard let source else { throw RitimError.message("native fixture completed") }
        let stream = NativeYouTubeStream(url: URL(string: "https://media.googlevideo.com/file")!, headers: [:],
                                        fileExtension: "m4a", codec: "mp4a.40.2", bitrate: 128000, resolution: nil, includesAudio: true)
        await metadata(NativeYouTubeMedia(title: "Native \(number)", artist: "Test", audio: stream, video: nil,
                                        actualResolution: nil, sourceHighestResolution: nil, sourceAudioBitrate: 128000))
        await progress(0.75)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("fixture-\(UUID().uuidString).m4a")
        try FileManager.default.copyItem(at: source, to: output)
        return output
    }
}

@MainActor
final class BulkDownloadTests: XCTestCase {
    private func workspace() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("BulkTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        return base
    }
    private func store(at base: URL, paused: Bool = true, native: BulkNativeDownloader = BulkNativeDownloader(),
                       initiallyForeground: Bool = true) throws -> DownloadStore {
        if !FileManager.default.fileExists(atPath: base.appendingPathComponent("downloads-settings.json").path) {
            try JSONSerialization.data(withJSONObject: ["isQueuePaused": paused, "keepScreenAwake": true]).write(to: base.appendingPathComponent("downloads-settings.json"))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BulkProtocol.self]
        let store = DownloadStore(library: LibraryStore(directory: base.appendingPathComponent("Media"), seed: false),
                                  sessionIdentifier: "bulk.test.\(UUID().uuidString)", downloadConfiguration: configuration,
                                  nativeDownloader: native, catalog: NativeYouTubeCatalog(session: URLSession(configuration: configuration)),
                                  initiallyForeground: initiallyForeground)
        store.downloadQuality = .standard
        return store
    }
    private func video(_ i: Int) -> String { "https://www.youtube.com/watch?v=" + String(format: "v%010d", i) }
    private func items(_ count: Int) -> [PlaylistItem] {
        (0..<count).map { PlaylistItem(id: String(format: "v%010d", $0), url: video($0), title: "Parça \($0)", artist: "Test", duration: 60, index: $0) }
    }
    private func eventually(_ condition: @escaping @MainActor () -> Bool, timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
    private func json(_ value: Any) -> Data { try! JSONSerialization.data(withJSONObject: value) }
    private func playlistPage(_ count: Int, title: String) -> Data {
        let rows: [[String: Any]] = items(count).map {
            ["playlistVideoRenderer": ["videoId": $0.id, "title": ["simpleText": $0.title],
                                       "shortBylineText": ["simpleText": $0.artist], "lengthText": ["simpleText": "1:00"]]]
        }
        let object: [String: Any] = ["metadata": ["playlistMetadataRenderer": ["title": title]],
                                     "contents": ["playlistVideoListRenderer": ["contents": rows]]]
        return Data(("<script>var ytInitialData = " + String(data: json(object), encoding: .utf8)! + ";</script>").utf8)
    }

    func testFiveThousandQueuePersistsInOrderAndReportsDuplicatesInvalidAndLimit() async throws {
        let base = try workspace()
        let store = try store(at: base)
        let first = (0..<500).map(video).joined(separator: "\n")
        store.enqueueText(first, format: .mp3, batchName: "İlk 500")
        XCTAssertEqual(store.pendingCount, 500)
        XCTAssertEqual(store.runningCount, 0)
        let more = (500..<5_005).map(video).joined(separator: " ")
        store.enqueueText(more + "\nhttps://youtu.be/v0000000000?t=5\ninvalid", format: .mp3, batchName: "İkinci grup")
        XCTAssertEqual(store.entries.count, 5_000)
        XCTAssertTrue(store.bulkNotice?.contains("1 zaten mevcut") == true)
        XCTAssertTrue(store.bulkNotice?.contains("1 geçersiz") == true)
        XCTAssertTrue(store.bulkNotice?.contains("5 sınırı aştı") == true)
        let saved = try JSONDecoder().decode([DownloadEntry].self, from: Data(contentsOf: base.appendingPathComponent("downloads.json")))
        XCTAssertEqual(saved.map(\.sourceURL), (0..<5_000).map(video))
        let restored = try self.store(at: base)
        XCTAssertEqual(restored.entries.map(\.id), store.entries.map(\.id))
        XCTAssertEqual(restored.pendingCount, 5_000)
        XCTAssertTrue(restored.isQueuePaused)
        let restoredStayedPaused = await eventually { restored.runningCount == 0 }
        XCTAssertTrue(restoredStayedPaused)
    }


    func testCanonicalFormatDedupeMixValidationAndActionableSinglePlaylist() throws {
        let store = try store(at: workspace())
        store.enqueueText("https://youtu.be/BaW_jenozKc?t=30 https://m.youtube.com/watch?v=BaW_jenozKc&feature=shared https://youtube.com/shorts/BaW_jenozKc", format: .mp3, batchName: "A")
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.sourceURL, "https://www.youtube.com/watch?v=BaW_jenozKc")
        store.enqueueText("https://youtu.be/BaW_jenozKc", format: .mp4, batchName: "B")
        XCTAssertEqual(store.entries.count, 2)
        store.start(url: "https://www.youtube.com/watch?v=BaW_jenozKc&list=PL1234567890", format: .mp3)
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertTrue(store.errorMessage?.contains("Oynatma listesi") == true)
        XCTAssertNoThrow(try MediaURLPolicy.validatedPlaylist("https://youtube.com/playlist?list=RDEMabcdefghijklmnop&si=shared"))
        XCTAssertThrowsError(try MediaURLPolicy.canonicalInput("https://youtube.com/@channel"))
        XCTAssertThrowsError(try MediaURLPolicy.validatedPlaylist("https://youtube.com/@channel?list=PL1234567890"))
    }


    func testCancelThousandAndRetryReuseRowsWithoutAffectingCapacity() async throws {
        let store = try store(at: workspace())
        store.enqueueText((0..<1_000).map(video).joined(separator: "\n"), format: .mp3, batchName: "1000")
        let first = try XCTUnwrap(store.entries.first)
        store.cancelAll()
        XCTAssertEqual(store.entries.filter { $0.status == .cancelled }.count, 1_000)
        XCTAssertEqual(store.pendingCount, 0)
        store.retry(first)
        XCTAssertEqual(store.entries.count, 1_000)
        XCTAssertEqual(store.entries.last?.id, first.id)
        XCTAssertEqual(store.pendingCount, 1)
        store.retry(first)
        XCTAssertEqual(store.pendingCount, 1)
        store.enqueueText(video(1), format: .mp3, batchName: "Retry via text")
        XCTAssertEqual(store.entries.count, 1_000)
        XCTAssertEqual(store.entries.last?.sourceURL, video(1))
        XCTAssertEqual(store.pendingCount, 2)
    }


    func testLegacyHistoryDecodesAndPauseSettingsArePerLibrary() async throws {
        let base = try workspace()
        let legacy: [[String: Any]] = [["id": UUID().uuidString, "title": "Eski parça", "sourceURL": video(1), "format": "mp3", "progress": 0, "status": "queued"]]
        try json(legacy).write(to: base.appendingPathComponent("downloads.json"))
        let first = try store(at: base)
        first.keepScreenAwake = false
        let restored = try store(at: base)
        XCTAssertEqual(restored.entries.first?.title, "Eski parça")
        XCTAssertNil(restored.entries.first?.batchID)
        XCTAssertFalse(restored.keepScreenAwake)
        XCTAssertTrue(restored.isQueuePaused)
        let separate = try store(at: workspace(), paused: false)
        XCTAssertFalse(separate.isQueuePaused)
        XCTAssertTrue(separate.keepScreenAwake)
    }


    func testLibrarySourceDedupeSurvivesClearedHistoryAndLinksExistingTrack() throws {
        let base = try workspace()
        let directory = base.appendingPathComponent("Media")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let track = MediaTrack(title: "Mevcut", fileName: "existing.mp3", sourceURL: "https://youtu.be/v0000000000")
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent(track.fileName))
        let encoded = try JSONEncoder().encode(track)
        let trackJSON = try JSONSerialization.jsonObject(with: encoded)
        try json(["tracks": [trackJSON], "playlists": [], "seeded": true]).write(to: base.appendingPathComponent("library.json"))
        let store = try store(at: base)
        store.enqueuePlaylist(items: items(2), title: "Mevcut + Yeni", format: .mp3)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.sourceURL, video(1))
        let restored = LibraryStore(directory: directory, seed: false)
        XCTAssertEqual(restored.playlists.first?.trackIDs, [track.id])
    }


    func testConcurrencyPreferenceMigratesPersistsPerLibraryAndBoundsInvalidValues() throws {
        let base = try workspace()
        let first = try store(at: base)
        XCTAssertEqual(first.maxConcurrentDownloads, 4, "Old settings without a limit use the new default")
        first.enqueueText((0..<20).map(video).joined(separator: "\n"), format: .mp3, batchName: "Saved queue")
        first.maxConcurrentDownloads = 6
        let restored = try store(at: base)
        XCTAssertEqual(restored.maxConcurrentDownloads, 6)
        XCTAssertTrue(restored.isQueuePaused)
        XCTAssertEqual(restored.runningCount, 0)
        XCTAssertEqual(restored.entries.map(\.id), first.entries.map(\.id))
        let separate = try store(at: workspace())
        XCTAssertEqual(separate.maxConcurrentDownloads, 4)
        restored.maxConcurrentDownloads = 99
        XCTAssertEqual(restored.maxConcurrentDownloads, 4)
        let bounded = try store(at: base)
        XCTAssertEqual(bounded.maxConcurrentDownloads, 4)
        XCTAssertEqual(bounded.pendingCount, 20)
    }

    func testTwoPipelinesPauseFinishFIFOAndResumeAfterNativeFailures() async throws {
        let native = BulkNativeDownloader()
        let store = try store(at: workspace(), native: native)
        store.maxConcurrentDownloads = 2
        store.enqueueText((0..<5).map(video).joined(separator: "\n"), format: .mp3, batchName: "Five")
        store.resumeQueue()
        let started = await eventually { native.entries.count == 2 }
        XCTAssertTrue(started)
        XCTAssertEqual(store.runningCount, 2)
        XCTAssertEqual(Set(native.entries.map(\.sourceURL)), Set([video(0), video(1)]))
        store.pauseQueue()
        let finished = await eventually { store.failedCount == 2 && store.runningCount == 0 }
        XCTAssertTrue(finished)
        XCTAssertEqual(native.entries.count, 2)
        XCTAssertEqual(store.pendingCount, 3)
        store.resumeQueue()
        let allFailed = await eventually { store.failedCount == 5 }
        XCTAssertTrue(allFailed)
        XCTAssertEqual(store.runningCount, 0)
        XCTAssertEqual(Set(native.entries.prefix(4).map(\.sourceURL)), Set((0..<4).map(video)))
        XCTAssertEqual(native.entries.last?.sourceURL, video(4))
        let ids = Set(store.entries.map(\.id))
        store.retryFailed()
        let failedAgain = await eventually { store.failedCount == 5 && native.entries.count == 10 }
        XCTAssertTrue(failedAgain)
        XCTAssertEqual(Set(store.entries.map(\.id)), ids)
        XCTAssertEqual(store.entries.count, 5)
        XCTAssertLessThanOrEqual(native.peakActive, 2)
    }

    func testNativeFailuresFreeSlotsWithoutServiceCredentials() async throws {
        let requests = BulkRequests()
        BulkProtocol.handle { request in requests.add(request.url!.absoluteString); return .init(status: 503, body: Data()) }
        let native = BulkNativeDownloader(delay: 0.05)
        let store = try store(at: workspace(), native: native)
        store.enqueueText((0..<7).map(video).joined(separator: "\n"), format: .mp3, batchName: "Native")
        store.resumeQueue()
        let finished = await eventually { store.failedCount == 7 }
        XCTAssertTrue(finished)
        XCTAssertEqual(store.runningCount, 0)
        XCTAssertEqual(store.entries.count, 7)
        XCTAssertEqual(native.entries.count, 7)
        XCTAssertTrue(requests.all.isEmpty, "Native jobs must never contact a Mac job or capability endpoint")
        XCTAssertTrue(store.entries.allSatisfy { $0.error == "native fixture completed" })
    }

    func testDirectYouTubeDiscovery500ItemsCreatesPlaylistInSourceOrder() async throws {
        let data = playlistPage(500, title: "500 Parça")
        let requests = BulkRequests()
        BulkProtocol.handle { request in requests.add(request.url!.absoluteString); return .init(body: data) }
        let base = try workspace()
        let store = try store(at: base)
        await store.resolvePlaylist(url: "https://www.youtube.com/playlist?list=PL123456789012345")
        XCTAssertFalse(store.isResolvingPlaylist)
        let preview = try XCTUnwrap(store.playlistPreview)
        XCTAssertEqual(preview.items.count, 500)
        XCTAssertEqual(preview.title, "500 Parça")
        XCTAssertEqual(requests.all.count, 1)
        XCTAssertEqual(URL(string: requests.all[0])?.host, "www.youtube.com")
        store.enqueuePlaylist(items: Array(preview.items.reversed()), title: preview.title, format: .mp4)
        XCTAssertEqual(store.entries.map(\.sourceURL), (0..<500).map(video))
        XCTAssertEqual(Set(store.entries.compactMap(\.playlistID)).count, 1)
        let library = LibraryStore(directory: base.appendingPathComponent("Media"), seed: false)
        XCTAssertEqual(library.playlists.first?.name, "500 Parça")
    }

    func testResolverFailureAndCancellationDoNotLeaveBusyState() async throws {
        BulkProtocol.handle { _ in .init(status: 503, body: Data()) }
        let store = try store(at: workspace())
        await store.resolvePlaylist(url: "https://youtube.com/playlist?list=PL123456789012345")
        XCTAssertFalse(store.isResolvingPlaylist)
        XCTAssertTrue(store.bulkNotice?.contains("YouTube") == true)
        let data = playlistPage(1, title: "Delayed")
        BulkProtocol.handle { _ in .init(body: data, delay: 1) }
        let task = Task { await store.resolvePlaylist(url: "https://youtube.com/playlist?list=PL123456789012345") }
        let resolving = await eventually { store.isResolvingPlaylist }
        XCTAssertTrue(resolving)
        store.cancelPlaylistResolution()
        await task.value
        XCTAssertFalse(store.isResolvingPlaylist)
        XCTAssertTrue(store.playlistPreview == nil || store.playlistPreview?.status == "cancelled")
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testDurableNativeImportDoesNotRequireServerAcknowledgement() async throws {
        let base = try workspace()
        let source = try XCTUnwrap(Bundle.main.url(forResource: "gece-yolu", withExtension: "m4a"))
        let native = BulkNativeDownloader(delay: 0.01, source: source)
        let store = try store(at: base, native: native)
        store.enqueuePlaylist(items: items(1), title: "Native liste", format: .mp3)
        store.resumeQueue()
        let completed = await eventually { store.completedCount == 1 }
        XCTAssertTrue(completed)
        let saved = try JSONDecoder().decode([DownloadEntry].self, from: Data(contentsOf: base.appendingPathComponent("downloads.json")))
        XCTAssertEqual(saved.first?.status, .completed)
        XCTAssertNil(saved.first?.serverID)
        let library = LibraryStore(directory: base.appendingPathComponent("Media"), seed: false)
        let track = try XCTUnwrap(library.tracks.first)
        XCTAssertEqual(track.id, saved.first?.trackID)
        XCTAssertEqual(library.playlists.first?.trackIDs, [track.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.url(for: track).path))
        store.clearFinished()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.url(for: track).path))
    }

    func testLegacyServerHistoryMigratesWithoutNetworkOrDeletingLibrary() async throws {
        let base = try workspace(), directory = base.appendingPathComponent("Media")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let track = MediaTrack(title: "Mac ile indirildi", fileName: "old.mp3", sourceURL: video(0))
        let bytes = Data([1, 2, 3]); try bytes.write(to: directory.appendingPathComponent(track.fileName))
        let trackJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(track))
        try json(["tracks": [trackJSON], "playlists": [], "seeded": true]).write(to: base.appendingPathComponent("library.json"))
        var complete = DownloadEntry(title: track.title, sourceURL: video(0), format: .mp3)
        complete.status = .completed; complete.progress = 1; complete.trackID = track.id
        complete.serverID = "old-complete"; complete.serverBaseURL = "http://Mac.local:8765"; complete.serverAcknowledged = false
        var active = DownloadEntry(title: "Yarım kaldı", sourceURL: video(1), format: .mp4)
        active.status = .preparing; active.serverID = "old-active"; active.serverBaseURL = complete.serverBaseURL
        try JSONEncoder().encode([complete, active]).write(to: base.appendingPathComponent("downloads.json"))
        let requests = BulkRequests()
        BulkProtocol.handle { request in requests.add(request.url!.absoluteString); return .init(status: 503, body: Data()) }
        let store = try store(at: base)
        let restored = await eventually { store.entries.last?.status == .queued }
        XCTAssertTrue(restored)
        XCTAssertEqual(store.entries.map(\.id), [complete.id, active.id])
        XCTAssertNil(store.entries.last?.serverID)
        XCTAssertTrue(requests.all.isEmpty)
        store.clearFinished()
        XCTAssertEqual(store.entries.map(\.id), [active.id])
        let library = LibraryStore(directory: directory, seed: false)
        XCTAssertEqual(library.tracks.map(\.id), [track.id])
        XCTAssertEqual(try Data(contentsOf: library.url(for: track)), bytes)
    }

    func testImmediateRetryWhileNativePreparationCancelsDoesNotStrandPipeline() async throws {
        let native = BulkNativeDownloader()
        let store = try store(at: workspace(), native: native)
        store.maxConcurrentDownloads = 2
        store.enqueueText([video(0), video(1)].joined(separator: "\n"), format: .mp3, batchName: "Cancel race")
        let first = try XCTUnwrap(store.entries.first)
        store.resumeQueue()
        let began = await eventually { native.entries.count == 2 }
        XCTAssertTrue(began)
        store.cancel(first)
        store.retry(first)
        let finished = await eventually { store.failedCount == 2 && store.runningCount == 0 }
        XCTAssertTrue(finished)
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.pendingCount, 0)
        XCTAssertEqual(native.entries.count, 3)
        XCTAssertEqual(native.cancelledCount, 1)
    }

    func testCancelledNativeCallbackCannotImportOrOverwriteRetriedEntry() async throws {
        let base = try workspace()
        let source = try XCTUnwrap(Bundle.main.url(forResource: "gece-yolu", withExtension: "m4a"))
        let native = BulkNativeDownloader(delay: 0.25, source: source, ignoreCancellation: true)
        let store = try store(at: base, native: native)
        store.start(url: video(0), format: .mp3)
        let first = try XCTUnwrap(store.entries.first)
        store.resumeQueue()
        let began = await eventually { native.entries.count == 1 }
        XCTAssertTrue(began)
        store.cancel(first); store.retry(first)
        let finished = await eventually { store.completedCount == 1 && store.runningCount == 0 }
        XCTAssertTrue(finished)
        XCTAssertEqual(native.entries.count, 2)
        XCTAssertEqual(store.entries.first?.title, "Native 2")
        let library = LibraryStore(directory: base.appendingPathComponent("Media"), seed: false)
        XCTAssertEqual(library.tracks.count, 1)
        XCTAssertEqual(library.tracks.first?.title, "Native 2")
    }

    func testSixPipelinesRaiseImmediatelyLowerWithoutCancellationAndHonorPause() async throws {
        let native = BulkNativeDownloader(delay: 0.6)
        let store = try store(at: workspace(), native: native)
        store.maxConcurrentDownloads = 2
        store.enqueueText((0..<10).map(video).joined(separator: "\n"), format: .mp3, batchName: "Concurrency")
        store.resumeQueue()
        let firstTwo = await eventually { native.entries.count == 2 }
        XCTAssertTrue(firstTwo); XCTAssertEqual(store.runningCount, 2)
        store.maxConcurrentDownloads = 6
        let firstSix = await eventually { native.entries.count == 6 }
        XCTAssertTrue(firstSix); XCTAssertEqual(store.runningCount, 6)
        XCTAssertEqual(store.pendingCount, 4)
        XCTAssertEqual(Set(native.entries.map(\.sourceURL)), Set((0..<6).map(video)))
        store.maxConcurrentDownloads = 2
        XCTAssertEqual(store.runningCount, 6)
        let nextPair = await eventually { native.entries.count == 8 }
        XCTAssertTrue(nextPair); XCTAssertEqual(store.runningCount, 2)
        XCTAssertEqual(Set(native.entries.suffix(2).map(\.sourceURL)), Set([video(6), video(7)]))
        XCTAssertEqual(native.cancelledCount, 0)
        store.pauseQueue()
        let paused = await eventually { store.failedCount == 8 && store.runningCount == 0 }
        XCTAssertTrue(paused); XCTAssertEqual(store.pendingCount, 2)
        store.maxConcurrentDownloads = 6
        XCTAssertEqual(store.runningCount, 0)
        store.resumeQueue()
        let allFinished = await eventually { store.failedCount == 10 && store.runningCount == 0 }
        XCTAssertTrue(allFinished); XCTAssertEqual(native.entries.count, 10)
        XCTAssertEqual(native.peakActive, 6)
    }

    func testHundredQueueSlotsStartOnceAndCancelSafely() async throws {
        let native = BulkNativeDownloader(delay: 30)
        let store = try store(at: workspace(), native: native)
        store.maxConcurrentDownloads = 100
        store.enqueueText((0..<120).map(video).joined(separator: "\n"), format: .mp3, batchName: "Large batch")
        store.resumeQueue()
        let started = await eventually({ native.entries.count == 100 }, timeout: 15)
        XCTAssertTrue(started)
        XCTAssertEqual(store.runningCount, 100)
        XCTAssertEqual(store.pendingCount, 20)
        XCTAssertEqual(Set(native.entries.map(\.sourceURL)).count, 100)
        store.cancelAll()
        let drained = await eventually({ store.runningCount == 0 }, timeout: 15)
        XCTAssertTrue(drained)
    }

    func testBackgroundImmediatelyCancelsNativeWorkAndForegroundRestartsQueuedEntries() async throws {
        let native = BulkNativeDownloader(delay: 1)
        let base = try workspace()
        let store = try store(at: base, native: native)
        store.maxConcurrentDownloads = 2
        store.enqueueText((0..<5).map(video).joined(separator: "\n"), format: .mp3, batchName: "Lifecycle")
        store.resumeQueue()
        let firstPair = await eventually { native.entries.count == 2 }
        XCTAssertTrue(firstPair)
        let ids = store.entries.map(\.id)
        store.applicationDidEnterBackground()
        XCTAssertTrue(store.entries.allSatisfy { $0.status == .queued && $0.progress == 0 })
        let drained = await eventually({ native.cancelledCount == 2 && store.runningCount == 0 }, timeout: 0.5)
        XCTAssertTrue(drained)
        XCTAssertEqual(store.failedCount, 0)
        XCTAssertEqual(native.entries.count, 2)
        XCTAssertEqual(store.pendingCount, 5)
        store.resumeQueue()
        store.maxConcurrentDownloads = 6
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(native.entries.count, 2, "Settings/resume must not restart native work in background.")
        let saved = try JSONDecoder().decode([DownloadEntry].self, from: Data(contentsOf: base.appendingPathComponent("downloads.json")))
        XCTAssertEqual(saved.map(\.id), ids)
        XCTAssertTrue(saved.allSatisfy { $0.status == .queued })
        store.maxConcurrentDownloads = 2
        store.applicationDidBecomeActive()
        let resumed = await eventually { store.failedCount == 5 && store.runningCount == 0 }
        XCTAssertTrue(resumed)
        XCTAssertEqual(native.entries.count, 7)
        XCTAssertEqual(store.entries.map(\.id), ids)
        XCTAssertLessThanOrEqual(native.peakActive, 2)
    }

    func testRapidBackgroundForegroundWaitsForNativeCleanupAndRejectsLateCallbacks() async throws {
        let base = try workspace()
        let source = try XCTUnwrap(Bundle.main.url(forResource: "gece-yolu", withExtension: "m4a"))
        let native = BulkNativeDownloader(delay: 0.3, source: source, ignoreCancellation: true,
                                          cancellationCleanupDelay: 0.25)
        let store = try store(at: base, native: native)
        store.enqueuePlaylist(items: items(1), title: "Sıra korunmalı", format: .mp3)
        let id = try XCTUnwrap(store.entries.first?.id)
        store.resumeQueue()
        let started = await eventually { native.entries.count == 1 }
        XCTAssertTrue(started)
        store.applicationDidEnterBackground()
        store.applicationDidBecomeActive()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(native.entries.count, 1, "The cancelled attempt still owns its scratch and pipeline slot.")
        XCTAssertEqual(store.runningCount, 1)
        XCTAssertEqual(store.entries.first?.status, .queued)
        XCTAssertEqual(store.entries.first?.progress, 0)
        let finished = await eventually { store.completedCount == 1 && store.runningCount == 0 }
        XCTAssertTrue(finished)
        XCTAssertEqual(native.entries.count, 2)
        XCTAssertEqual(native.peakActive, 1)
        XCTAssertEqual(native.cancelledCount, 1)
        XCTAssertEqual(store.entries.map(\.id), [id])
        XCTAssertEqual(store.entries.first?.title, "Native 2")
        let library = LibraryStore(directory: base.appendingPathComponent("Media"), seed: false)
        XCTAssertEqual(library.tracks.count, 1)
        XCTAssertEqual(library.tracks.first?.title, "Native 2")
        XCTAssertEqual(library.playlists.first?.trackIDs, library.tracks.map(\.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("NativeDownloads/\(id.uuidString)").path))
    }

    func testBackgroundRelaunchCannotStartNativeWorkUntilForegroundAndHonorsManualPause() async throws {
        let base = try workspace()
        let native = BulkNativeDownloader(delay: 0.1)
        let entries = (0..<3).map { DownloadEntry(title: "Queued \($0)", sourceURL: video($0), format: .mp3) }
        try JSONEncoder().encode(entries).write(to: base.appendingPathComponent("downloads.json"))
        let store = try store(at: base, paused: false, native: native, initiallyForeground: false)
        try await Task.sleep(for: .milliseconds(150))
        store.resumeQueue()
        store.maxConcurrentDownloads = 6
        XCTAssertEqual(store.runningCount, 0)
        XCTAssertTrue(native.entries.isEmpty)
        XCTAssertEqual(store.entries.map(\.id), entries.map(\.id))
        store.pauseQueue()
        store.applicationDidBecomeActive()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(native.entries.isEmpty, "Foregrounding must not override the user's queue pause.")
        store.resumeQueue()
        let resumed = await eventually { store.failedCount == 3 && store.runningCount == 0 }
        XCTAssertTrue(resumed)
        XCTAssertEqual(native.entries.count, 3)
    }

    func testBackgroundBeforeScheduledNativeTaskRunsCannotRecreateItsTokenOrStartWork() async throws {
        let native = BulkNativeDownloader(delay: 0.05)
        let store = try store(at: workspace(), native: native)
        try await Task.sleep(for: .milliseconds(100))
        store.enqueueText((0..<3).map(video).joined(separator: "\n"), format: .mp3, batchName: "Scheduling race")
        store.resumeQueue()
        // Stay on the same main-actor turn so poller bodies have not run yet.
        store.applicationDidEnterBackground()
        let drained = await eventually { store.runningCount == 0 }
        XCTAssertTrue(drained)
        XCTAssertTrue(native.entries.isEmpty)
        XCTAssertTrue(store.entries.allSatisfy { $0.status == .queued })
        store.applicationDidBecomeActive()
        let resumed = await eventually { store.failedCount == 3 && store.runningCount == 0 }
        XCTAssertTrue(resumed)
        XCTAssertEqual(native.entries.count, 3)
    }

    func testBackgroundCancelsNativeWorkButLeavesDirectURLSessionTransferRunning() async throws {
        let requests = BulkRequests()
        BulkProtocol.handle { request in requests.add(request.url!.absoluteString); return .init(status: 503, body: Data(), delay: 10) }
        let native = BulkNativeDownloader(delay: 10)
        let store = try store(at: workspace(), native: native)
        store.maxConcurrentDownloads = 2
        let direct = "https://example.com/direct.m4a"
        store.enqueueText([video(0), direct].joined(separator: "\n"), format: .mp3, batchName: "Mixed")
        store.resumeQueue()
        let started = await eventually { native.entries.count == 1 && requests.all.contains(direct) }
        XCTAssertTrue(started)
        store.applicationDidEnterBackground()
        let cancelled = await eventually({ native.cancelledCount == 1 && store.runningCount == 1 }, timeout: 0.5)
        XCTAssertTrue(cancelled)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(store.entries.first(where: { $0.sourceURL == direct })?.status, .downloading)
        XCTAssertEqual(store.entries.first(where: { $0.sourceURL == self.video(0) })?.status, .queued)
        XCTAssertEqual(store.runningCount, 1)
        store.cancelAll()
        let cleaned = await eventually { store.runningCount == 0 }
        XCTAssertTrue(cleaned)
    }

    func testBackgroundRelaunchSchedulesDirectTransferPastQueuedYouTube() async throws {
        let requests = BulkRequests()
        BulkProtocol.handle { request in requests.add(request.url!.absoluteString); return .init(status: 503, body: Data(), delay: 10) }
        let base = try workspace()
        let direct = "https://example.com/background.m4a"
        let entries = [DownloadEntry(title: "YouTube", sourceURL: video(0), format: .mp3),
                       DownloadEntry(title: "Direct", sourceURL: direct, format: .mp3)]
        try JSONEncoder().encode(entries).write(to: base.appendingPathComponent("downloads.json"))
        let native = BulkNativeDownloader(delay: 10)
        let store = try store(at: base, paused: false, native: native, initiallyForeground: false)
        let started = await eventually { requests.all.contains(direct) }
        XCTAssertTrue(started)
        XCTAssertTrue(native.entries.isEmpty)
        XCTAssertEqual(store.entries.first(where: { $0.sourceURL == self.video(0) })?.status, .queued)
        store.cancelAll()
    }

    func testNativeBackgroundHandoffSavesCompletedSourceAndLeavesConversionQueued() async throws {
        let base = try workspace()
        let requests = BulkRequests()
        BulkProtocol.handle { request in
            requests.add(request.url!.absoluteString)
            return .init(body: Data(repeating: 9, count: 128), mime: "audio/mp4")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BulkProtocol.self]
        try JSONSerialization.data(withJSONObject: ["isQueuePaused": true, "keepScreenAwake": true]).write(to: base.appendingPathComponent("downloads-settings.json"))
        let store = DownloadStore(library: LibraryStore(directory: base.appendingPathComponent("Media"), seed: false),
                                  sessionIdentifier: "handoff.\(UUID())", downloadConfiguration: configuration,
                                  nativeDownloader: HandoffNativeDownloader(), initiallyForeground: true,
                                  allowNativeBackgroundHandoff: true)
        store.enqueueText(video(0), format: .mp3, batchName: "Handoff")
        store.resumeQueue()
        let ready = await eventually { store.entries.first?.status == .downloading }
        XCTAssertTrue(ready)
        let entry = try XCTUnwrap(store.entries.first)
        store.applicationDidEnterBackground()
        let checkpoint = base.appendingPathComponent("NativeDownloads/\(entry.id.uuidString)/checkpoint/audio.checkpoint.json")
        let delivered = await eventually { FileManager.default.fileExists(atPath: checkpoint.path) && store.runningCount == 0 }
        XCTAssertTrue(delivered)
        XCTAssertEqual(requests.all, ["https://media.googlevideo.com/test"])
        XCTAssertEqual(store.entries.first?.status, .queued, "Conversion must wait for foreground")
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkpoint.deletingLastPathComponent().appendingPathComponent("audio.m4a").path))
        store.cancelAll()
    }

    func testNativeVideoHandoffWaitsForBothSources() async throws {
        let base = try workspace()
        BulkProtocol.handle { request in
            .init(body: Data(repeating: 9, count: 128), delay: request.url?.path == "/video" ? 0.2 : 0, mime: "video/mp4")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BulkProtocol.self]
        try JSONSerialization.data(withJSONObject: ["isQueuePaused": true, "keepScreenAwake": true]).write(to: base.appendingPathComponent("downloads-settings.json"))
        let store = DownloadStore(library: LibraryStore(directory: base.appendingPathComponent("Media"), seed: false),
                                  sessionIdentifier: "handoff-video.\(UUID())", downloadConfiguration: configuration,
                                  nativeDownloader: HandoffNativeDownloader(), initiallyForeground: true, allowNativeBackgroundHandoff: true)
        store.enqueueText(video(0), format: .mp4, batchName: "Handoff")
        store.resumeQueue()
        let ready = await eventually { store.entries.first?.status == .downloading }
        XCTAssertTrue(ready)
        let entry = try XCTUnwrap(store.entries.first)
        store.applicationDidEnterBackground()
        let dir = base.appendingPathComponent("NativeDownloads/\(entry.id.uuidString)/checkpoint")
        let audioReady = await eventually { FileManager.default.fileExists(atPath: dir.appendingPathComponent("audio.checkpoint.json").path) }
        XCTAssertTrue(audioReady)
        XCTAssertEqual(store.runningCount, 1)
        let videoReady = await eventually { FileManager.default.fileExists(atPath: dir.appendingPathComponent("video.checkpoint.json").path) && store.runningCount == 0 }
        XCTAssertTrue(videoReady)
        XCTAssertEqual(store.entries.first?.status, .queued)
        store.cancelAll()
    }

    func testInterruptedLibraryCommitRecoversWithoutRedownloadAndDoesNotResurrectManualPlaylistRemoval() async throws {
        let base = try workspace(), media = base.appendingPathComponent("Media")
        let source = try XCTUnwrap(Bundle.main.url(forResource: "gece-yolu", withExtension: "m4a"))
        let library = LibraryStore(directory: media, seed: false)
        library.createPlaylist(name: "Kurtarılan liste")
        let playlist = try XCTUnwrap(library.playlists.first)
        var interrupted = DownloadEntry(title: "Tamamlanmış dosya", sourceURL: "https://example.com/recovered.m4a", format: .mp3)
        interrupted.status = .downloading; interrupted.playlistID = playlist.id
        let track = try await library.importDownloadedFile(source, title: interrupted.title, artist: "Test", sourceURL: interrupted.sourceURL,
                                                          downloadEntryID: interrupted.id)
        let bytes = try Data(contentsOf: library.url(for: track))
        try JSONEncoder().encode([interrupted]).write(to: base.appendingPathComponent("downloads.json"))
        let requests = BulkRequests()
        BulkProtocol.handle { request in requests.add(request.url!.absoluteString); return .init(status: 503, body: Data()) }
        let store = try store(at: base, paused: false)
        let recovered = await eventually { store.completedCount == 1 }
        XCTAssertTrue(recovered)
        XCTAssertEqual(store.entries.first?.trackID, track.id)
        XCTAssertEqual(store.runningCount, 0)
        XCTAssertTrue(requests.all.isEmpty)
        let restored = LibraryStore(directory: media, seed: false)
        XCTAssertEqual(restored.tracks.map(\.id), [track.id])
        XCTAssertEqual(restored.playlists.first?.trackIDs, [track.id])
        XCTAssertEqual(try Data(contentsOf: restored.url(for: track)), bytes)
        restored.remove(track, from: playlist)
        let relaunched = try self.store(at: base)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(relaunched.completedCount, 1)
        XCTAssertEqual(LibraryStore(directory: media, seed: false).playlists.first?.trackIDs, [])
    }

    func testRecoveryRejectsMissingChangedAndUnrelatedFilesWithoutDeletingLibrary() async throws {
        let base = try workspace(), media = base.appendingPathComponent("Media")
        let source = try XCTUnwrap(Bundle.main.url(forResource: "gece-yolu", withExtension: "m4a"))
        let library = LibraryStore(directory: media, seed: false)
        var pending: [DownloadEntry] = []
        var savedTracks: [MediaTrack] = []
        for index in 0..<4 {
            var entry = DownloadEntry(title: "Interrupted \(index)", sourceURL: "https://example.com/\(index).m4a", format: .mp3)
            entry.status = .downloading
            let track = try await library.importDownloadedFile(source, title: entry.title, artist: nil,
                                                              sourceURL: index == 3 ? "https://example.com/unrelated.m4a" : entry.sourceURL,
                                                              downloadEntryID: index == 2 ? nil : entry.id)
            pending.append(entry); savedTracks.append(track)
        }
        try FileManager.default.removeItem(at: library.url(for: savedTracks[0]))
        try Data("changed incomplete file".utf8).write(to: library.url(for: savedTracks[1]))
        let originalLibrary = try Data(contentsOf: base.appendingPathComponent("library.json"))
        try JSONEncoder().encode(pending).write(to: base.appendingPathComponent("downloads.json"))
        let store = try store(at: base)
        let restored = await eventually { store.entries.allSatisfy { $0.status == .queued } }
        XCTAssertTrue(restored)
        XCTAssertEqual(store.completedCount, 0)
        XCTAssertEqual(store.runningCount, 0)
        XCTAssertEqual(try Data(contentsOf: base.appendingPathComponent("library.json")), originalLibrary)
        XCTAssertEqual(LibraryStore(directory: media, seed: false).tracks.map(\.id), library.tracks.map(\.id))
    }

    func testConcurrentPlaylistCompletionKeepsEachSourceOrderAfterClearingFinishedHistory() async throws {
        let base = try workspace(), media = base.appendingPathComponent("Media")
        let source = try XCTUnwrap(Bundle.main.url(forResource: "gece-yolu", withExtension: "m4a"))
        let native = BulkNativeDownloader(delay: 0.15, source: source,
                                          delaysByURL: [video(0): 1.2, video(1): 0.01, video(2): 0.15])
        let store = try store(at: base, native: native)
        store.maxConcurrentDownloads = 2
        store.enqueuePlaylist(items: items(3), title: "Kaynak sırası", format: .mp3)
        var reversed = Array(items(3).reversed())
        for index in reversed.indices { reversed[index].index = index }
        store.enqueuePlaylist(items: reversed, title: "Ters kaynak sırası", format: .mp3)
        store.resumeQueue()
        let secondFinishedFirst = await eventually { store.entries.first(where: { $0.sourceURL == self.video(1) })?.status == .completed }
        XCTAssertTrue(secondFinishedFirst)
        XCTAssertNotEqual(store.entries.first(where: { $0.sourceURL == video(0) })?.status, .completed)
        store.clearFinished()
        let drained = await eventually { store.runningCount == 0 && store.pendingCount == 0 }
        XCTAssertTrue(drained)
        XCTAssertEqual(native.entries.count, 3)
        let library = LibraryStore(directory: media, seed: false)
        let forward = try XCTUnwrap(library.playlists.first { $0.name == "Kaynak sırası" })
        let backward = try XCTUnwrap(library.playlists.first { $0.name == "Ters kaynak sırası" })
        XCTAssertEqual(library.tracks(in: forward).compactMap(\.sourceURL), (0..<3).map(video))
        XCTAssertEqual(library.tracks(in: backward).compactMap(\.sourceURL), (0..<3).reversed().map(video))
        XCTAssertNil(forward.downloadOrder)
        XCTAssertNil(backward.downloadOrder)
        XCTAssertEqual(library.tracks.count, 3)
    }

    func testPendingPlaylistSlotsPreserveManualRemovalAndArePrunedWithCancelledHistory() async throws {
        let base = try workspace(), media = base.appendingPathComponent("Media")
        let source = try XCTUnwrap(Bundle.main.url(forResource: "gece-yolu", withExtension: "m4a"))
        let library = LibraryStore(directory: media, seed: false)
        let existing = try await library.importDownloadedFile(source, title: "Mevcut", artist: nil, sourceURL: nil)
        library.createPlaylist(name: "Düzenlenen liste")
        let playlist = try XCTUnwrap(library.playlists.first)
        library.add(existing, to: playlist)
        let store = try self.store(at: base)
        store.enqueuePlaylist(items: items(2), title: playlist.name, format: .mp3)
        try await Task.sleep(for: .milliseconds(100))
        let editing = LibraryStore(directory: media, seed: false)
        editing.remove(existing, from: playlist)
        XCTAssertTrue(editing.playlists.first?.trackIDs.isEmpty == true)
        let slot = try XCTUnwrap(editing.playlists.first?.downloadOrder?.first?.entryID)
        let downloaded = try await editing.importDownloadedFile(source, title: "Yeni", artist: nil, sourceURL: video(0), downloadEntryID: slot)
        XCTAssertEqual(editing.playlists.first?.trackIDs, [downloaded.id])
        // A relaunch uses the manually edited durable order, not a stale LibraryStore.
        let relaunched = try self.store(at: base)
        try await Task.sleep(for: .milliseconds(100))
        relaunched.cancelAll(); relaunched.clearFinished()
        let result = LibraryStore(directory: media, seed: false)
        XCTAssertEqual(result.playlists.first?.trackIDs, [downloaded.id])
        XCTAssertNil(result.playlists.first?.downloadOrder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url(for: existing).path))
    }

}

extension BulkDownloadTests {
    func testSelectedQueueActionsPreserveOtherJobsAndPersistPriority() async throws {
        let base = try workspace()
        let queue = try store(at: base)
        queue.enqueueText((0..<5).map(video).joined(separator: "\n"), format: .mp3, batchName: "Seçim")
        let originalIDs = queue.entries.map(\.id)
        queue.prioritize(ids: [originalIDs[4]])
        XCTAssertEqual(queue.entries.last?.priority, 1)
        queue.cancelAll(ids: [originalIDs[0], originalIDs[1]])
        XCTAssertEqual(queue.entries.filter { $0.status == .cancelled }.count, 2)
        XCTAssertEqual(queue.entries.filter(\.isActive).count, 3)
        queue.retryFailed(ids: [originalIDs[0]])
        XCTAssertEqual(queue.entries.filter { $0.status == .cancelled }.count, 1)
        XCTAssertEqual(Set(queue.entries.map(\.id)), Set(originalIDs))
        let restored = try store(at: base)
        XCTAssertEqual(restored.entries.first(where: { $0.id == originalIDs[4] })?.priority, 1)
    }
}
