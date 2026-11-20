import AVFoundation
import XCTest
@testable import Ritim

private final class LyricsProtocol: URLProtocol, @unchecked Sendable {
    struct Reply {
        var status = 200
        var body: Data
        var headers = ["Content-Type": "application/json"]
        var delay: TimeInterval = 0
    }
    private static let lock = NSLock()
    private static var handler: ((URLRequest) -> Reply)?
    private static var captured: [URLRequest] = []
    private let stateLock = NSRecursiveLock()
    private var stopped = false
    static func configure(_ handler: @escaping (URLRequest) -> Reply) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler; captured = []
    }
    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return captured
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.captured.append(request)
        let handler = Self.handler
        Self.lock.unlock()
        let reply = handler?(request) ?? Reply(status: 404, body: Data())
        DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { [self] in
            stateLock.lock(); defer { stateLock.unlock() }
            guard !stopped else { return }
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                           httpVersion: "HTTP/1.1", headerFields: reply.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { stateLock.lock(); stopped = true; stateLock.unlock() }
}

@MainActor
final class LyricsTests: XCTestCase {
    // These original fixture lines belong to the test, not to a provider catalog.
    private let originalLRC = "[00:01.00]Yeni gün burada\n[00:02.50]Deniz bugün sakin"
    private func track(_ title: String = "Yeni Gün", artist: String = "Ritim", duration: Double = 180) -> MediaTrack {
        MediaTrack(title: title, artist: artist, fileName: "fixture.m4a", duration: duration)
    }
    private func workspace() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LyricsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
    private func store(at directory: URL? = nil, handler: @escaping (URLRequest) -> LyricsProtocol.Reply) throws -> LyricsStore {
        LyricsProtocol.configure(handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsProtocol.self]
        let session = URLSession(configuration: configuration)
        addTeardownBlock { session.invalidateAndCancel() }
        return LyricsStore(directory: try directory ?? workspace(), session: session)
    }
    private func record(id: Int = 10, title: String = "Yeni Gün", artist: String = "Ritim", album: String = "Deneme",
                        duration: Double = 180, synced: String? = nil, plain: String? = nil, instrumental: Bool = false) -> [String: Any] {
        var value: [String: Any] = ["id": id, "trackName": title, "artistName": artist, "albumName": album,
                                    "duration": duration, "instrumental": instrumental]
        value["syncedLyrics"] = synced
        value["plainLyrics"] = plain
        return value
    }
    private func json(_ value: Any) -> Data { try! JSONSerialization.data(withJSONObject: value) }
    private func waitForRequestCount(_ count: Int) async throws {
        for _ in 0..<200 {
            if LyricsProtocol.requests.count >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected request did not start")
    }

    func testParserMultipleTimestampsFractionsStableSortAndMetadata() throws {
        let parsed = try LRCParser.parse("\u{FEFF}[ar:Ritim]\r\n[ti:Deneme]\r\n[00:03.125][00:01.5]İlk satır\n[00:01.50]İkinci satır\n[00:02:25]\n[offset:+500]")
        XCTAssertEqual(parsed.lines.map(\.time), [1, 1, 1.75, 2.625])
        XCTAssertEqual(parsed.lines.map(\.text), ["İlk satır", "İkinci satır", "", "İlk satır"])
        XCTAssertEqual(parsed.lines.map(\.id), [0, 1, 2, 3])
        XCTAssertFalse(parsed.plainText.contains("[ar:"))
        XCTAssertFalse(parsed.plainText.contains("[offset:"))
    }

    func testMetadataOffsetAdvancesAndUserOffsetDelaysIndependently() throws {
        let parsed = try LRCParser.parse("[00:00.20]Başlangıç\n[00:02.00]Devam\n[offset:500]")
        XCTAssertEqual(parsed.lines.map(\.time), [0, 1.5])
        var value = TrackLyrics(trackID: UUID(), rawText: "", plainText: "", lines: parsed.lines, sourceName: "Test", sourceURL: nil)
        value.offset = 1
        XCTAssertNil(value.activeLine(at: 0.99))
        XCTAssertEqual(value.activeLine(at: 1)?.id, 0)
        XCTAssertEqual(value.activeLine(at: 2.49)?.id, 0)
        XCTAssertEqual(value.activeLine(at: 2.5)?.id, 1)
        XCTAssertNil(value.activeLine(at: .nan))
        XCTAssertEqual(try LRCParser.parse("[offset:-500]\n[00:02.00]Devam").lines.first?.time, 2.5)
    }

    func testPlainTextEmptyAndMalformedTimestampStates() throws {
        XCTAssertTrue(try LRCParser.parse("Düz sözler\nİkinci satır").lines.isEmpty)
        XCTAssertEqual(try LRCParser.parse("[ar:Sanatçı]\n[ti:Başlık]").plainText, "")
        XCTAssertTrue(try LRCParser.parse("[00:70.1]Geçersiz zaman").lines.isEmpty)
        let parsed = try LRCParser.parse("[00:01]Ses\n[00:02]\n[00:03]Yeni ses")
        let value = TrackLyrics(trackID: UUID(), rawText: "", plainText: "", lines: parsed.lines, sourceName: "Test", sourceURL: nil)
        XCTAssertEqual(value.activeLine(at: 2.5)?.text, "")
        XCTAssertThrowsError(try LRCParser.parse(String(repeating: "a", count: LyricsStore.maxTextBytes + 1)))
    }

    func testPasteOffsetAndOfflineRelaunchPreserveRawTextPerTrack() async throws {
        let directory = try workspace(), first = track(), second = track("Başka Gün")
        let initial = LyricsStore(directory: directory, networkEnabled: false)
        await initial.load(for: first)
        try initial.saveUserLyrics(originalLRC, for: first)
        try initial.setOffset(80, for: first)
        XCTAssertEqual(initial.current?.offset, 30)
        try initial.setOffset(-80, for: first)
        XCTAssertEqual(initial.current?.offset, -30)
        try initial.setOffset(0.75, for: first)
        try initial.setOffset(.nan, for: first)
        let offline = LyricsStore(directory: directory, networkEnabled: false)
        await offline.load(for: first)
        XCTAssertEqual(offline.current?.rawText, originalLRC)
        XCTAssertEqual(offline.current?.lines.count, 2)
        XCTAssertEqual(offline.current?.offset, 0.75)
        XCTAssertTrue(offline.current?.hasUserEdits == true)
        XCTAssertTrue(offline.isUsingCachedLyrics)
        XCTAssertNil(offline.record(for: second))
        XCTAssertFalse(offline.isLoading)
    }

    func testFileImportSupportsUTF16AndRejectsOversizedOrWrongExtension() async throws {
        let directory = try workspace(), item = track()
        let value = LyricsStore(directory: directory.appendingPathComponent("Cache"), networkEnabled: false)
        await value.load(for: item)
        let file = directory.appendingPathComponent("özgün.lrc")
        try XCTUnwrap(originalLRC.data(using: .utf16)).write(to: file)
        try value.importLyrics(from: file, for: item)
        XCTAssertEqual(value.current?.rawText, originalLRC)
        XCTAssertEqual(value.current?.sourceName, file.lastPathComponent)
        let large = directory.appendingPathComponent("large.txt")
        try Data(repeating: 65, count: LyricsStore.maxTextBytes + 1).write(to: large)
        XCTAssertThrowsError(try value.importLyrics(from: large, for: item))
        XCTAssertThrowsError(try value.importLyrics(from: file.deletingPathExtension().appendingPathExtension("pdf"), for: item))
        XCTAssertThrowsError(try value.saveUserLyrics("[ar:Ritim]", for: item))
        XCTAssertEqual(value.current?.rawText, originalLRC)
    }

    func testSafeMatchingRejectsVariantsArtistsAndDurationMismatch() {
        let item = track("Ritim - Yeni Gün (Official Lyric Video)", artist: "Ritim - Topic")
        let candidate = LyricsCandidate(id: 1, title: "Yeni Gün", artist: "Ritim", album: "Deneme", duration: 182, hasSynced: true, isInstrumental: false)
        XCTAssertTrue(LyricsMatching.isSafeMatch(candidate, for: item))
        for title in ["Yeni Gün (Live)", "Yeni Gün Remix", "Yeni Gün (Canlı)", "Yeni Gün Acoustic"] {
            XCTAssertFalse(LyricsMatching.canAutomaticallyLookUp(track(title)), title)
        }
        var wrong = candidate; wrong.artist = "Başka Sanatçı"
        XCTAssertFalse(LyricsMatching.isSafeMatch(wrong, for: item))
        wrong = candidate; wrong.duration = 182.01
        XCTAssertFalse(LyricsMatching.isSafeMatch(wrong, for: item))
        wrong = candidate; wrong.album = "Live Sessions"
        XCTAssertFalse(LyricsMatching.isSafeMatch(wrong, for: item))
        XCTAssertFalse(LyricsMatching.canAutomaticallyLookUp(track(artist: "Bilinmeyen sanatçı")))
        XCTAssertFalse(LyricsMatching.canAutomaticallyLookUp(track(duration: .nan)))
        var liveAlbum = track(); liveAlbum.album = "Live in Ankara"
        XCTAssertFalse(LyricsMatching.canAutomaticallyLookUp(liveAlbum))
    }

    func testAutomaticFetchCachesAndUserRemovalRestoresProviderRecord() async throws {
        let directory = try workspace(), item = track()
        let body = json(record(synced: originalLRC))
        let value = try store(at: directory) { _ in .init(body: body) }
        await value.load(for: item)
        XCTAssertEqual(value.current?.sourceName, "LRCLIB")
        XCTAssertEqual(value.current?.lines.count, 2)
        XCTAssertEqual(LyricsProtocol.requests.count, 1)
        let request = try XCTUnwrap(LyricsProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/api/get")
        XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.contains("Ritim/") == true)
        XCTAssertLessThanOrEqual(request.timeoutInterval, 15)
        try value.saveUserLyrics("Kendi özgün metnim", for: item)
        await value.load(for: item, refresh: true)
        XCTAssertEqual(LyricsProtocol.requests.count, 1)
        XCTAssertTrue(value.current?.hasUserEdits == true)
        try value.removeUserLyrics(for: item)
        XCTAssertEqual(value.current?.sourceName, "LRCLIB")
        let offline = LyricsStore(directory: directory, networkEnabled: false)
        await offline.load(for: item)
        XCTAssertEqual(offline.current?.lines.count, 2)
        var renamed = item; renamed.title = "Farklı kayıt"
        XCTAssertNil(offline.record(for: renamed))
        var albumChanged = item; albumChanged.album = "Live in Ankara"
        XCTAssertNil(offline.record(for: albumChanged))
        try offline.saveUserLyrics("Kullanıcının seçtiği özgün sözler", for: item)
        XCTAssertTrue(offline.record(for: albumChanged)?.hasUserEdits == true)
    }

    func testAutomaticMismatchIsNeverAttached() async throws {
        let item = track(), body = json(record(artist: "Başka Sanatçı", synced: originalLRC))
        let value = try store { _ in .init(body: body) }
        await value.load(for: item)
        XCTAssertNil(value.current)
        XCTAssertNil(value.record(for: item))
        XCTAssertNotNil(value.statusMessage)
    }

    func testPlainAndInstrumentalProviderRecordsHaveNoTimedLines() async throws {
        let item = track(), plain = json(record(plain: "Özgün düz satır"))
        let value = try store { _ in .init(body: plain) }
        await value.load(for: item)
        XCTAssertEqual(value.current?.plainText, "Özgün düz satır")
        XCTAssertTrue(value.current?.lines.isEmpty == true)
        let instrumental = json(record(instrumental: true))
        LyricsProtocol.configure { _ in .init(body: instrumental) }
        await value.load(for: item, refresh: true)
        XCTAssertTrue(value.current?.isInstrumental == true)
        XCTAssertTrue(value.current?.plainText.isEmpty == true)
        XCTAssertTrue(value.current?.lines.isEmpty == true)
    }

    func testManualSearchRequiresChoiceAndAcceptsExplicitVariant() async throws {
        let item = track("Yeni Gün Live"), result = record(title: "Yeni Gün (Live)", synced: originalLRC)
        let searchData = json([result]), selectedData = json(result)
        let value = try store { request in .init(body: request.url?.path == "/api/search" ? searchData : selectedData) }
        await value.load(for: item)
        XCTAssertTrue(LyricsProtocol.requests.isEmpty)
        await value.search(query: "Yeni Gün Live")
        XCTAssertEqual(value.candidates.count, 1)
        XCTAssertNil(value.current)
        await value.choose(try XCTUnwrap(value.candidates.first), for: item)
        XCTAssertEqual(value.current?.sourceName, "LRCLIB")
        XCTAssertEqual(value.current?.lines.count, 2)
        XCTAssertEqual(LyricsProtocol.requests.last?.url?.path, "/api/get/10")
    }

    func testSlowOldTrackCannotOverwriteNewTrackOrPersistStaleResponse() async throws {
        let directory = try workspace(), first = track(), second = track("İkinci Gün")
        let firstBody = json(record(synced: originalLRC)), secondBody = json(record(title: second.title, synced: originalLRC))
        let value = try store(at: directory) { request in
            let title = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "track_name" }?.value
            return .init(body: title == first.title ? firstBody : secondBody, delay: title == first.title ? 0.6 : 0)
        }
        let pending = Task { await value.load(for: first) }
        try await waitForRequestCount(1)
        await value.load(for: second)
        await pending.value
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(value.currentTrackID, second.id)
        XCTAssertEqual(value.current?.trackID, second.id)
        XCTAssertNil(value.record(for: first))
        XCTAssertFalse(value.isLoading)
    }

    func testUserPasteCancelsPendingProviderAndRemainsAuthoritative() async throws {
        let item = track(), body = json(record(synced: originalLRC))
        let value = try store { _ in .init(body: body, delay: 0.4) }
        let pending = Task { await value.load(for: item) }
        try await waitForRequestCount(1)
        try value.saveUserLyrics("Benim özgün satırım", for: item)
        await pending.value
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(value.current?.plainText, "Benim özgün satırım")
        XCTAssertTrue(value.current?.hasUserEdits == true)
        XCTAssertFalse(value.isLoading)
    }

    func testSearchResponseIsDiscardedWhenTrackChanges() async throws {
        let first = track("Bir Live"), second = track("İki Live"), body = json([record(synced: originalLRC)])
        let value = try store { _ in .init(body: body, delay: 0.4) }
        await value.load(for: first)
        let pending = Task { await value.search(query: "Yeni Gün") }
        try await waitForRequestCount(1)
        await value.load(for: second)
        await pending.value
        XCTAssertEqual(value.currentTrackID, second.id)
        XCTAssertTrue(value.candidates.isEmpty)
        XCTAssertFalse(value.isSearching)
    }

    func testRetryAfterPreventsImmediateSecondRequest() async throws {
        let value = try store { _ in .init(status: 429, body: Data(), headers: ["Retry-After": "120"]) }
        await value.search(query: "ilk")
        XCTAssertNotNil(value.errorMessage)
        await value.search(query: "ikinci")
        XCTAssertEqual(LyricsProtocol.requests.count, 1)
        XCTAssertTrue(value.errorMessage?.contains("saniye") == true)
        XCTAssertFalse(value.isSearching)
    }

    func testMissingResultIsNegativelyCachedButRefreshRetries() async throws {
        let item = track(), value = try store { _ in .init(status: 404, body: Data()) }
        await value.load(for: item)
        await value.load(for: item)
        XCTAssertEqual(LyricsProtocol.requests.count, 1)
        await value.load(for: item, refresh: true)
        XCTAssertEqual(LyricsProtocol.requests.count, 2)
        XCTAssertNil(value.current)
    }

    func testRetryAfterHTTPDateOnUnavailableServiceIsHonored() async throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        let header = formatter.string(from: Date().addingTimeInterval(120))
        let value = try store { _ in .init(status: 503, body: Data(), headers: ["Retry-After": header]) }
        await value.search(query: "ilk")
        await value.search(query: "ikinci")
        XCTAssertEqual(LyricsProtocol.requests.count, 1)
        XCTAssertNotNil(value.errorMessage)
    }

    func testOversizedHTTPBodyAndInvalidJSONDoNotCreateRecords() async throws {
        let item = track()
        let value = try store { _ in .init(body: Data(), headers: ["Content-Type": "application/json", "Content-Length": "2097153"]) }
        await value.load(for: item)
        XCTAssertNil(value.current)
        XCTAssertNotNil(value.errorMessage)
        LyricsProtocol.configure { _ in .init(body: Data("{broken".utf8)) }
        await value.load(for: item, refresh: true)
        XCTAssertNil(value.current)
        XCTAssertNil(value.record(for: item))
        XCTAssertNotNil(value.errorMessage)
    }

    func testCorruptCacheIsPreservedBeforeNewUserSave() async throws {
        let directory = try workspace(), item = track()
        let file = directory.appendingPathComponent(item.id.uuidString).appendingPathExtension("json")
        let original = Data("incomplete cache".utf8)
        try original.write(to: file)
        let value = LyricsStore(directory: directory, networkEnabled: false)
        await value.load(for: item)
        XCTAssertNil(value.current)
        XCTAssertEqual(try Data(contentsOf: file), original)
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.lastPathComponent.contains("-recovery-") })
        try value.saveUserLyrics(originalLRC, for: item)
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertEqual(value.record(for: item)?.lines.count, 2)
    }

    func testEmbeddedLyricsAreReadAndSavedWithoutNetwork() async throws {
        let directory = try workspace(), item = track()
        let source = try XCTUnwrap(Bundle.main.url(forResource: "gece-yolu", withExtension: "m4a"))
        let output = directory.appendingPathComponent("embedded.m4a")
        let exporter = try XCTUnwrap(AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetPassthrough))
        let metadata = AVMutableMetadataItem()
        metadata.identifier = .iTunesMetadataLyrics
        metadata.value = originalLRC as NSString
        exporter.metadata = [metadata]
        exporter.outputURL = output; exporter.outputFileType = .m4a
        await exporter.export()
        XCTAssertEqual(exporter.status, .completed)
        let value = LyricsStore(directory: directory.appendingPathComponent("Cache"), networkEnabled: false)
        await value.load(for: item, fileURL: output)
        XCTAssertEqual(value.current?.sourceName, "Dosyanın içindeki sözler")
        XCTAssertEqual(value.current?.lines.count, 2)
        XCTAssertNil(value.current?.sourceURL)
    }

    func testLiveLRCLIBFetchAndOfflineReload() async throws {
        guard ProcessInfo.processInfo.environment["RITIM_TEST_LIVE_LYRICS"] == "1" else {
            throw XCTSkip("Opt-in provider integration test; ordinary tests remain offline")
        }
        let directory = try workspace()
        let item = track("Easy On Me", artist: "Adele", duration: 225)
        let value = LyricsStore(directory: directory, networkEnabled: true)
        await value.load(for: item, refresh: true)
        // Never include provider lyric text in assertion diagnostics or logs.
        XCTAssertNil(value.errorMessage)
        XCTAssertTrue(value.current != nil)
        XCTAssertEqual(value.current?.trackID, item.id)
        XCTAssertEqual(value.current?.sourceName, "LRCLIB")
        XCTAssertGreaterThan(value.current?.lines.count ?? 0, 0)
        XCTAssertTrue(value.current?.sourceURL?.hasPrefix("https://lrclib.net/api/get/") == true)
        let count = value.current?.lines.count
        let offline = LyricsStore(directory: directory, networkEnabled: false)
        await offline.load(for: item)
        XCTAssertEqual(offline.current?.trackID, item.id)
        XCTAssertEqual(offline.current?.sourceName, "LRCLIB")
        XCTAssertEqual(offline.current?.lines.count, count)
        XCTAssertTrue(offline.isUsingCachedLyrics)
        XCTAssertFalse(offline.isLoading)
    }
}
