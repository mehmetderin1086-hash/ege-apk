import XCTest
@testable import Ritim

@MainActor
final class NativeScratchTests: XCTestCase {
    func testBackgroundTimeoutRetriesWithoutAlertAndIgnoresStaleCallbacks() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("timeout-\(UUID())")
        let media = base.appendingPathComponent("Media")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let entry = DownloadEntry(title: "Timeout", sourceURL: "https://www.youtube.com/watch?v=n0000000001", format: .mp3)
        try JSONEncoder().encode([entry]).write(to: base.appendingPathComponent("downloads.json"))
        try JSONSerialization.data(withJSONObject: ["isQueuePaused": true, "keepScreenAwake": false]).write(to: base.appendingPathComponent("downloads-settings.json"))
        let store = DownloadStore(library: LibraryStore(directory: media, seed: false), sessionIdentifier: "timeout.\(UUID())", downloadConfiguration: .ephemeral, initiallyForeground: false)
        // Drain restoration before simulating an OS delivery.
        try await Task.sleep(for: .milliseconds(100))
        let directory = base.appendingPathComponent("NativeDownloads/\(entry.id.uuidString)")
        let checkpoint = directory.appendingPathComponent("checkpoint")
        try FileManager.default.createDirectory(at: checkpoint, withIntermediateDirectories: true)
        let completed = checkpoint.appendingPathComponent("audio.m4a")
        try Data([1, 2, 3]).write(to: completed)
        let journal = directory.appendingPathComponent("background.json")
        for attempt in 0..<4 {
            let generation = UUID()
            try JSONSerialization.data(withJSONObject: ["generation": generation.uuidString, "pending": ["video"]]).write(to: journal)
            let part = NativeBackgroundPart(entryID: entry.id, generation: generation, kind: "video", codec: "h264", bitrate: 1000, resolution: 720, fileExtension: "mp4")
            store.nativeBackgroundFailed(part, error: URLError(.timedOut))
            let result = try XCTUnwrap(store.entries.first)
            XCTAssertNil(store.errorMessage)
            XCTAssertEqual(result.status, attempt < 3 ? .queued : .failed)
            XCTAssertEqual(result.retryCount, min(attempt + 1, 3))
            if attempt < 3 { XCTAssertGreaterThan(try XCTUnwrap(result.retryAfter), Date()) }
            XCTAssertEqual(try Data(contentsOf: completed), Data([1, 2, 3]))
            XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
            store.nativeBackgroundFailed(part, error: URLError(.cancelled))
            XCTAssertEqual(store.entries.first?.status, result.status)
            XCTAssertEqual(store.entries.first?.retryCount, result.retryCount)
        }
        let saved = try JSONDecoder().decode([DownloadEntry].self, from: Data(contentsOf: base.appendingPathComponent("downloads.json")))
        XCTAssertEqual(saved.first?.status, .failed)
        XCTAssertEqual(saved.first?.retryCount, 3)
    }

    func testKepceLiveDownloadForManualVerification() async throws {
        guard ProcessInfo.processInfo.environment["RITIM_TEST_LIVE_KEPCE"] == "1" else { throw XCTSkip("Canlı kaynak testi isteğe bağlıdır.") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kepce-live-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let entry = DownloadEntry(title: "Test", sourceURL: "https://www.youtube.com/watch?v=jNQXAC9IVRw", format: .mp3)
        let output = try await NativeYouTubeDownloader().download(entry: entry, directory: directory, metadata: { _ in }, progress: { _ in })
        XCTAssertEqual(UserDefaults.standard.string(forKey: "ritim.lastYouTubeResolver"), "kepce")
        XCTAssertEqual(output.pathExtension, "mp3")
        XCTAssertGreaterThan((try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0), 1000)
    }

    func testKepceLiveYouTubeForManualVerification() async throws {
        guard ProcessInfo.processInfo.environment["RITIM_TEST_LIVE_KEPCE"] == "1" else { throw XCTSkip("Canlı kaynak testi isteğe bağlıdır.") }
        let url = URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw")!
        let media = try await NativeYouTubeExtractor.resolveWithKepce(url: url, format: .mp3, quality: .standard)
        XCTAssertEqual(media.audio.fileExtension, "m4a")
        XCTAssertTrue(media.audio.url.host?.hasSuffix("googlevideo.com") == true)
    }

    func testCancelledKepceCallerDoesNotHoldItsQueueSlot() async {
        let work = Task { try await PythonMotoru.shared.cagir("version") }
        work.cancel()
        do { _ = try await work.value; XCTFail("Cancelled caller must stop") }
        catch is CancellationError { }
        catch { XCTFail("Expected cancellation: \(error)") }
    }

    func testBundledKepceEngineStartsAndReportsVersion() async throws {
        let version = try await PythonMotoru.shared.surum()
        XCTAssertFalse(version.yt_dlp.isEmpty)
        XCTAssertFalse(version.python.isEmpty)
    }

    func testReadyCheckpointConvertsWithoutResolvingOrDownloadingAgain() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("reuse-ready-\(UUID())")
        let media = base.appendingPathComponent("Media", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let entry = DownloadEntry(title: "Ready", sourceURL: "https://www.youtube.com/watch?v=n0000000001", format: .mp3)
        let dir = base.appendingPathComponent("NativeDownloads/\(entry.id.uuidString)/checkpoint", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "native-audio", withExtension: "m4a"))
        let temporary = dir.appendingPathComponent("source.tmp")
        try FileManager.default.copyItem(at: source, to: temporary)
        let stream = NativeYouTubeStream(url: URL(string: "https://media.googlevideo.com/file")!, headers: [:], fileExtension: "m4a", codec: "aac", bitrate: 128000, resolution: nil, includesAudio: true)
        _ = try NativeYouTubeDownloader.saveCheckpoint(dir, kind: "audio", entry: entry, stream: stream, downloaded: temporary)
        try JSONEncoder().encode([entry]).write(to: base.appendingPathComponent("downloads.json"))
        try JSONSerialization.data(withJSONObject: ["isQueuePaused": true, "keepScreenAwake": false]).write(to: base.appendingPathComponent("downloads-settings.json"))
        let store = DownloadStore(library: LibraryStore(directory: media, seed: false), sessionIdentifier: "reuse.\(UUID())", downloadConfiguration: .ephemeral, nativeDownloader: FailIfResolvedAgain())
        for _ in 0..<200 where store.isQueuePaused && store.entries.first?.status != .queued { try await Task.sleep(for: .milliseconds(20)) }
        store.resumeQueue()
        for _ in 0..<1000 where store.entries.first?.status != .completed && store.entries.first?.status != .failed { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(store.entries.first?.status, .completed, store.entries.first?.error ?? "")
    }

    func testRelaunchKeepsCompletedCheckpointForQueuedEntryAndRemovesPartialFile() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("checkpoint-restore-\(UUID())")
        let media = base.appendingPathComponent("Media", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let entry = DownloadEntry(title: "Test", sourceURL: "https://www.youtube.com/watch?v=n0000000001", format: .mp3)
        let dir = base.appendingPathComponent("NativeDownloads/\(entry.id.uuidString)/checkpoint", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stream = NativeYouTubeStream(url: URL(string: "https://media.googlevideo.com/file")!, headers: [:], fileExtension: "m4a", codec: "aac", bitrate: 128000, resolution: nil, includesAudio: true)
        let temp = dir.appendingPathComponent("finished")
        try Data(repeating: 1, count: 100).write(to: temp)
        _ = try NativeYouTubeDownloader.saveCheckpoint(dir, kind: "audio", entry: entry, stream: stream, downloaded: temp)
        let partial = dir.appendingPathComponent("video-incomplete.mp4")
        try Data(repeating: 2, count: 50).write(to: partial)
        let partialOutput = dir.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).mp3")
        try Data(repeating: 3, count: 50).write(to: partialOutput)
        try JSONEncoder().encode([entry]).write(to: base.appendingPathComponent("downloads.json"))
        try JSONSerialization.data(withJSONObject: ["isQueuePaused": true, "keepScreenAwake": true]).write(to: base.appendingPathComponent("downloads-settings.json"))
        let store = DownloadStore(library: LibraryStore(directory: media, seed: false), sessionIdentifier: "checkpoint.\(UUID())", downloadConfiguration: .ephemeral)
        for _ in 0..<100 where FileManager.default.fileExists(atPath: partial.path) { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialOutput.path))
        XCTAssertTrue(NativeYouTubeDownloader.checkpointMatches(dir, kind: "audio", entry: entry, stream: stream))
        store.cancel(entry)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testCompletedCheckpointMatchesOnlySameSourceAndUnchangedFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("checkpoint-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let entry = DownloadEntry(title: "Test", sourceURL: "https://www.youtube.com/watch?v=n0000000001", format: .mp3)
        let stream = NativeYouTubeStream(url: URL(string: "https://media.googlevideo.com/file?secret=temporary")!, headers: ["Authorization": "secret"], fileExtension: "m4a", codec: "aac", bitrate: 128000, resolution: nil, includesAudio: true)
        let downloaded = directory.appendingPathComponent("temporary")
        try Data(repeating: 7, count: 128).write(to: downloaded)
        let saved = try NativeYouTubeDownloader.saveCheckpoint(directory, kind: "audio", entry: entry, stream: stream, downloaded: downloaded)
        XCTAssertTrue(NativeYouTubeDownloader.checkpointMatches(directory, kind: "audio", entry: entry, stream: stream))
        let marker = try String(contentsOf: NativeYouTubeDownloader.checkpointURL(directory, kind: "audio"), encoding: .utf8)
        XCTAssertFalse(marker.contains("secret"))
        let changed = NativeYouTubeStream(url: stream.url, headers: [:], fileExtension: "m4a", codec: "aac", bitrate: 64000, resolution: nil, includesAudio: true)
        XCTAssertFalse(NativeYouTubeDownloader.checkpointMatches(directory, kind: "audio", entry: entry, stream: changed))
        try Data(repeating: 7, count: 10).write(to: saved)
        XCTAssertFalse(NativeYouTubeDownloader.checkpointMatches(directory, kind: "audio", entry: entry, stream: stream))
    }

    func testPausedStartupRemovesOnlyOrphanNativeScratchAndPreservesLibraryAndHistory() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("NativeScratchTests-\(UUID())")
        let media = base.appendingPathComponent("Media", isDirectory: true)
        let scratch = base.appendingPathComponent("NativeDownloads", isDirectory: true)
        let orphan = scratch.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try Data("unfinished source".utf8).write(to: orphan.appendingPathComponent("audio.m4a"))
        try Data("unfinished conversion".utf8).write(to: scratch.appendingPathComponent("partial.mp3"))

        let mediaBytes = Data("existing user media must remain unchanged".utf8)
        let existingFile = media.appendingPathComponent("existing.mp3")
        try mediaBytes.write(to: existingFile)
        let track = MediaTrack(title: "Existing track", fileName: existingFile.lastPathComponent, duration: 120,
                               fileSize: Int64(mediaBytes.count))
        let playlist = MediaPlaylist(name: "Existing playlist", trackIDs: [track.id])
        let libraryData = try JSONEncoder().encode(LibraryFixture(tracks: [track], playlists: [playlist], seeded: true))
        let libraryURL = base.appendingPathComponent("library.json")
        try libraryData.write(to: libraryURL)

        var completed = DownloadEntry(title: track.title, sourceURL: "https://www.youtube.com/watch?v=n0000000001", format: .mp3)
        completed.status = .completed; completed.progress = 1; completed.trackID = track.id
        var interrupted = DownloadEntry(title: "Interrupted", sourceURL: "https://www.youtube.com/watch?v=n0000000002", format: .mp3)
        interrupted.status = .preparing
        let originalEntries = [completed, interrupted]
        let historyURL = base.appendingPathComponent("downloads.json")
        try JSONEncoder().encode(originalEntries).write(to: historyURL)
        try JSONSerialization.data(withJSONObject: ["isQueuePaused": true, "keepScreenAwake": false])
            .write(to: base.appendingPathComponent("downloads-settings.json"))

        let library = LibraryStore(directory: media, seed: false)
        let store = DownloadStore(library: library, sessionIdentifier: "scratch.test.\(UUID())",
                                  downloadConfiguration: .ephemeral)
        let deadline = Date().addingTimeInterval(3)
        while store.entries.last?.status == .preparing, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.path))
        XCTAssertEqual(try Data(contentsOf: existingFile), mediaBytes)
        XCTAssertEqual(try Data(contentsOf: libraryURL), libraryData)
        XCTAssertEqual(library.tracks, [track])
        XCTAssertEqual(library.playlists.map(\.id), [playlist.id])
        XCTAssertEqual(library.playlists.first?.trackIDs, [track.id])
        XCTAssertTrue(store.isQueuePaused)
        XCTAssertEqual(store.runningCount, 0)
        XCTAssertEqual(store.entries.map(\.id), originalEntries.map(\.id))
        XCTAssertEqual(store.entries.first?.trackID, track.id)
        XCTAssertEqual(store.entries.first?.status, .completed)
        XCTAssertEqual(store.entries.last?.status, .queued)
        let saved = try JSONDecoder().decode([DownloadEntry].self, from: Data(contentsOf: historyURL))
        XCTAssertEqual(saved.map(\.id), originalEntries.map(\.id))
        XCTAssertEqual(saved.first?.trackID, track.id)
    }
}

private struct LibraryFixture: Codable {
    var tracks: [MediaTrack]
    var playlists: [MediaPlaylist]
    var seeded: Bool
}

private struct FailIfResolvedAgain: NativeDownloadProviding {
    func download(entry: DownloadEntry, directory: URL, metadata: @escaping @MainActor @Sendable (NativeYouTubeMedia) -> Void, progress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> URL {
        throw RitimError.message("A verified checkpoint must not be downloaded again")
    }
}
