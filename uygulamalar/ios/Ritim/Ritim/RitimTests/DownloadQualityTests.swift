import XCTest
@testable import Ritim

private final class QualityNativeDownloader: NativeDownloadProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [DownloadEntry] = []
    var entries: [DownloadEntry] { lock.withLock { captured } }
    func download(entry: DownloadEntry, directory: URL,
                  metadata: @escaping @MainActor @Sendable (NativeYouTubeMedia) -> Void,
                  progress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> URL {
        lock.withLock { captured.append(entry) }
        try await Task.sleep(for: .milliseconds(20))
        throw RitimError.message("native quality fixture")
    }
}

@MainActor
final class DownloadQualityTests: XCTestCase {
    private let video = "https://www.youtube.com/watch?v=v0000000000"
    private func workspace() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("QualityTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        return base
    }
    private func store(at base: URL, native: QualityNativeDownloader = QualityNativeDownloader()) throws -> DownloadStore {
        if !FileManager.default.fileExists(atPath: base.appendingPathComponent("downloads-settings.json").path) {
            try JSONSerialization.data(withJSONObject: ["isQueuePaused": true, "keepScreenAwake": true])
                .write(to: base.appendingPathComponent("downloads-settings.json"))
        }
        // Quality fixtures exercise foreground native work independently of the XCTest host's app state.
        return DownloadStore(library: LibraryStore(directory: base.appendingPathComponent("Media"), seed: false),
                             sessionIdentifier: "quality.test.\(UUID().uuidString)", downloadConfiguration: .ephemeral,
                             nativeDownloader: native, initiallyForeground: true)
    }
    private func eventually(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    func testLegacyModelsDecodeWithoutChangingQualityOrIdentity() throws {
        let track = MediaTrack(title: "Önceki dosya", fileName: "old.mp3", sourceURL: video)
        var trackJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(track)) as? [String: Any])
        trackJSON.removeValue(forKey: "downloadQuality")
        let restoredTrack = try JSONDecoder().decode(MediaTrack.self, from: JSONSerialization.data(withJSONObject: trackJSON))
        XCTAssertEqual(restoredTrack.id, track.id)
        XCTAssertNil(restoredTrack.downloadQuality)
        let entry = DownloadEntry(title: "Eski kuyruk", sourceURL: video, format: .mp3)
        var entryJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        entryJSON.removeValue(forKey: "quality")
        let restoredEntry = try JSONDecoder().decode(DownloadEntry.self, from: JSONSerialization.data(withJSONObject: entryJSON))
        XCTAssertEqual(restoredEntry.id, entry.id)
        XCTAssertNil(restoredEntry.quality)
        XCTAssertEqual(restoredEntry.effectiveQuality, .standard)
    }


    func testDefaultHighestMigratesAndPreferencePersistsPerLibrary() throws {
        let base = try workspace()
        let store = try store(at: base)
        XCTAssertEqual(store.downloadQuality, .highest)
        store.downloadQuality = .standard
        let restored = try self.store(at: base)
        XCTAssertEqual(restored.downloadQuality, .standard)
        XCTAssertEqual(try self.store(at: workspace()).downloadQuality, .highest)
    }


    func testQueueCapturesQualityAndSeparatesYouTubeProfilesButNotDirectFiles() throws {
        let base = try workspace()
        let store = try store(at: base)
        store.start(url: video, format: .mp3)
        store.downloadQuality = .standard
        store.start(url: "https://youtu.be/v0000000000?t=30", format: .mp3)
        store.start(url: video, format: .mp3)
        store.start(url: "https://example.com/original.mp3", format: .mp3)
        store.downloadQuality = .highest
        store.start(url: "https://example.com/original.mp3", format: .mp3)
        XCTAssertEqual(store.entries.count, 3)
        XCTAssertEqual(store.entries[0].quality, .highest)
        XCTAssertEqual(store.entries[1].quality, .standard)
        XCTAssertNil(store.entries[2].quality)
        let restored = try self.store(at: base)
        XCTAssertEqual(restored.entries.map(\.quality), [.highest, .standard, nil])
        XCTAssertEqual(restored.entries.map(\.id), store.entries.map(\.id))
    }


    func testLegacyLibraryAllowsExplicitHighestCopyAndPreservesOriginal() throws {
        let base = try workspace(), media = base.appendingPathComponent("Media")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        let track = MediaTrack(title: "192 kbps kopya", fileName: "original.mp3", sourceURL: video)
        let original = Data([1, 2, 3])
        try original.write(to: media.appendingPathComponent(track.fileName))
        let trackJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(track))
        try JSONSerialization.data(withJSONObject: ["tracks": [trackJSON], "playlists": [], "seeded": true])
            .write(to: base.appendingPathComponent("library.json"))
        let store = try store(at: base)
        store.start(url: video, format: .mp3)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.quality, .highest)
        store.downloadQuality = .standard
        store.start(url: video, format: .mp3)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertTrue(store.bulkNotice?.contains("1 zaten mevcut") == true)
        let library = LibraryStore(directory: media, seed: false)
        XCTAssertEqual(library.tracks.map(\.id), [track.id])
        XCTAssertEqual(try Data(contentsOf: media.appendingPathComponent(track.fileName)), original)
    }


    func testRetryKeepsCapturedQualityAfterPreferenceChanges() async throws {
        let base = try workspace()
        let store = try store(at: base)
        store.start(url: video, format: .mp3)
        let entry = try XCTUnwrap(store.entries.first)
        store.failed(entry.id, message: "fixture")
        store.downloadQuality = .standard
        store.retry(entry)
        XCTAssertEqual(store.entries.first?.quality, .highest)
        XCTAssertEqual(store.entries.first?.status, .queued)
    }


    func testImportedQualityPersistsOnlyForYouTubeSources() async throws {
        let base = try workspace(), directory = base.appendingPathComponent("Media")
        let library = LibraryStore(directory: directory, seed: false)
        let source = try XCTUnwrap(Bundle.main.url(forResource: "gece-yolu", withExtension: "m4a"))
        let youtube = try await library.importDownloadedFile(source, title: "Highest", artist: "Test", sourceURL: video, downloadQuality: .highest)
        let direct = try await library.importDownloadedFile(source, title: "Original", artist: "Test", sourceURL: "https://example.com/song.m4a", downloadQuality: .highest)
        let restored = LibraryStore(directory: directory, seed: false)
        XCTAssertEqual(restored.tracks.first { $0.id == youtube.id }?.downloadQuality, .highest)
        XCTAssertNil(restored.tracks.first { $0.id == direct.id }?.downloadQuality)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.url(for: youtube).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.url(for: direct).path))
    }
    func testHighestAndStandardReachNativeEngineWithoutMacConfiguration() async throws {
        let native = QualityNativeDownloader()
        let store = try store(at: workspace(), native: native)
        store.start(url: video, format: .mp3)
        store.downloadQuality = .standard
        store.start(url: video, format: .mp3)
        store.resumeQueue()
        let finished = await eventually { store.failedCount == 2 }
        XCTAssertTrue(finished)
        XCTAssertEqual(Set(native.entries.map(\.effectiveQuality)), Set([.standard, .highest]))
        XCTAssertTrue(native.entries.allSatisfy { $0.serverID == nil && $0.serverBaseURL == nil })
        XCTAssertTrue(store.entries.allSatisfy { $0.error == "native quality fixture" })
    }

    func testQueuedVideoQualityIsCapturedBeforePreferenceChanges() async throws {
        let native = QualityNativeDownloader()
        let store = try store(at: workspace(), native: native)
        store.enqueueText((0..<4).map { "https://youtu.be/v000000000\($0)" }.joined(separator: "\n"), format: .mp4, batchName: "Quality")
        store.downloadQuality = .standard
        store.resumeQueue()
        let finished = await eventually { store.failedCount == 4 }
        XCTAssertTrue(finished)
        XCTAssertEqual(native.entries.count, 4)
        XCTAssertTrue(native.entries.allSatisfy { $0.quality == .highest && $0.format == .mp4 })
        XCTAssertTrue(store.entries.allSatisfy { $0.error == "native quality fixture" })
    }

    func testRetryUsesCapturedQualityInNativeEngineAfterChangingPreference() async throws {
        let native = QualityNativeDownloader()
        let store = try store(at: workspace(), native: native)
        store.start(url: video, format: .mp4)
        store.resumeQueue()
        let failed = await eventually { store.failedCount == 1 }
        XCTAssertTrue(failed)
        let entry = try XCTUnwrap(store.entries.first)
        store.downloadQuality = .standard
        store.retry(entry)
        let retried = await eventually { native.entries.count == 2 && store.failedCount == 1 }
        XCTAssertTrue(retried)
        XCTAssertEqual(native.entries.map(\.id), [entry.id, entry.id])
        XCTAssertEqual(native.entries.map(\.effectiveQuality), [.highest, .highest])
        XCTAssertEqual(store.entries.count, 1)
    }

    func testLegacyActiveServerJobRetainsOriginalStandardQualityDuringNativeMigration() async throws {
        let base = try workspace()
        var entry = DownloadEntry(title: "Eski indirme", sourceURL: video, format: .mp3)
        entry.status = .preparing; entry.serverID = "old-job"; entry.serverBaseURL = "http://Mac.local:8765"
        try JSONEncoder().encode([entry]).write(to: base.appendingPathComponent("downloads.json"))
        let native = QualityNativeDownloader()
        let store = try store(at: base, native: native)
        XCTAssertEqual(store.downloadQuality, .highest)
        store.resumeQueue()
        let finished = await eventually { store.failedCount == 1 }
        XCTAssertTrue(finished)
        XCTAssertEqual(native.entries.first?.id, entry.id)
        XCTAssertEqual(native.entries.first?.effectiveQuality, .standard)
        XCTAssertNil(native.entries.first?.serverID)
        XCTAssertNil(native.entries.first?.serverBaseURL)
    }

}
