import XCTest
@testable import Ritim

/// Scripted network: each request gets the next step (an HTTP reply or a URL error).
private final class ScriptProtocol: URLProtocol, @unchecked Sendable {
    enum Step { case reply(status: Int, headers: [String: String], body: Data), fail(URLError.Code) }
    private static let lock = NSLock()
    private static var handler: ((URLRequest) -> Step)?
    static func handle(_ next: ((URLRequest) -> Step)?) { lock.withLock { handler = next } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        switch Self.lock.withLock({ Self.handler })?(request) ?? .fail(.badServerResponse) {
        case .fail(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .reply(let status, let headers, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { }
}

private final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func add(_ value: String) { lock.withLock { values.append(value) } }
    var all: [String] { lock.withLock { values } }
}

final class YouTubeReliabilityTests: XCTestCase {
    override func tearDown() { ScriptProtocol.handle(nil); super.tearDown() }

    private func stream(_ name: String) -> NativeYouTubeStream {
        NativeYouTubeStream(url: URL(string: "https://rr1.googlevideo.com/\(name)")!, headers: [:], fileExtension: "m4a",
                            codec: "mp4a.40.2", bitrate: 128_000, resolution: nil, includesAudio: true)
    }

    private func destination() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("YTRel-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.appendingPathComponent("audio.m4a")
    }

    private static func range(_ request: URLRequest) -> (Int, Int) {
        let value = request.value(forHTTPHeaderField: "Range")!.dropFirst(6).split(separator: "-")
        return (Int(value[0])!, Int(value[1])!)
    }

    func testTransferRetriesDroppedConnectionAndResumesWithRefreshedURLAfterExpiry() async throws {
        let payload = Data((0..<3_145_728).map { UInt8($0 % 251) })
        let log = Log()
        ScriptProtocol.handle { request in
            let path = request.url!.path, (start, end) = Self.range(request)
            log.add("\(path) \(start)")
            let attempts = log.all.filter { $0 == "\(path) \(start)" }.count
            // First range drops once; the second range's old URL has expired.
            if path == "/old", start == 0, attempts == 1 { return .fail(.networkConnectionLost) }
            if path == "/old", start > 0 { return .reply(status: 403, headers: [:], body: Data()) }
            let last = min(end, payload.count - 1)
            return .reply(status: 206, headers: ["Content-Range": "bytes \(start)-\(last)/\(payload.count)"],
                          body: payload.subdata(in: start..<(last + 1)))
        }
        let refreshes = Log(), delays = Log()
        let fresh = stream("fresh")
        let output = try await NativeYouTubeDownloader().transfer(stream("old"), to: try destination(),
                                                                  refresh: { refreshes.add("refresh"); return fresh },
                                                                  chunkSize: 2 * 1_024 * 1_024, parallel: 1, initialChunkSize: 2 * 1_024 * 1_024,
                                                                  retryDelay: { delays.add("\($0)") },
                                                                  protocolClasses: [ScriptProtocol.self]) { _ in }
        XCTAssertEqual(try Data(contentsOf: output), payload, "Kesinti ve bağlantı tazelemesi baytları bozmamalı")
        XCTAssertEqual(refreshes.all.count, 1)
        XCTAssertEqual(delays.all, ["0"])
        XCTAssertEqual(log.all, ["/old 0", "/old 0", "/old 2097152", "/fresh 2097152"], "Tazelenen bağlantı kaldığı yerden devam etmeli")
    }

    func testParallelRangesAssembleTheFileInOrderAndReportMonotonicProgress() async throws {
        var bytes = [UInt8](repeating: 0, count: 9_437_184 + 12_345)
        for index in bytes.indices { bytes[index] = UInt8(truncatingIfNeeded: index % 253) }
        let payload = Data(bytes)
        let starts = Log()
        ScriptProtocol.handle { request in
            let (start, end) = Self.range(request)
            starts.add("\(start)")
            let last = min(end, payload.count - 1)
            return .reply(status: 206, headers: ["Content-Range": "bytes \(start)-\(last)/\(payload.count)"],
                          body: payload.subdata(in: start..<(last + 1)))
        }
        let seen = Log()
        let output = try await NativeYouTubeDownloader().transfer(stream("p"), to: try destination(), chunkSize: 2 * 1_024 * 1_024, parallel: 3, initialChunkSize: 2 * 1_024 * 1_024,
                                                                  retryDelay: { _ in }, protocolClasses: [ScriptProtocol.self]) { seen.add("\($0)") }
        XCTAssertEqual(try Data(contentsOf: output), payload, "Paralel parçalar doğru sırayla birleşmeli")
        XCTAssertEqual(starts.all.count, 5, "9,01 MiB, 2 MiB’lık 5 aralık")
        let values = seen.all.compactMap(Double.init)
        XCTAssertEqual(values, values.sorted(), "İlerleme geri gitmemeli")
        XCTAssertEqual(values.last, 1)
    }

    func testSmallInitialRangeStartsParallelTransferEarlier() async throws {
        let payload = Data(repeating: 42, count: 5 * 1_024 * 1_024)
        let requests = Log()
        ScriptProtocol.handle { request in
            let (start, end) = Self.range(request)
            requests.add("\(start)-\(end)")
            let last = min(end, payload.count - 1)
            return .reply(status: 206, headers: ["Content-Range": "bytes \(start)-\(last)/\(payload.count)"], body: payload.subdata(in: start..<(last + 1)))
        }
        let output = try await NativeYouTubeDownloader().transfer(stream("p"), to: try destination(), protocolClasses: [ScriptProtocol.self]) { _ in }
        XCTAssertEqual(try Data(contentsOf: output), payload)
        XCTAssertEqual(requests.all.first, "0-262143")
        XCTAssertEqual(requests.all.count, 3)
    }

    func testTransferGivesAClearMessageAfterRepeatedDrops() async throws {
        ScriptProtocol.handle { _ in .fail(.timedOut) }
        let delays = Log()
        do {
            _ = try await NativeYouTubeDownloader().transfer(stream("old"), to: try destination(), retryDelay: { delays.add("\($0)") },
                                                             protocolClasses: [ScriptProtocol.self]) { _ in }
            XCTFail("Sürekli kopan bağlantı hata vermeli")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("\(NativeYouTubeDownloader.maxAttempts) denemede"), error.localizedDescription)
        }
        XCTAssertEqual(delays.all, ["0", "1", "2"])
    }

    func testExpiredURLWithoutRefreshFailsWithStatus() async throws {
        ScriptProtocol.handle { _ in .reply(status: 403, headers: [:], body: Data()) }
        do {
            _ = try await NativeYouTubeDownloader().transfer(stream("old"), to: try destination(), retryDelay: { _ in },
                                                             protocolClasses: [ScriptProtocol.self]) { _ in }
            XCTFail("403 hata vermeli")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("HTTP 403"), error.localizedDescription)
        }
    }

    func testVideoSharedFromAPlaylistOrMixIsThatVideoOnlyWhenAskedExplicitly() throws {
        for link in ["https://www.youtube.com/watch?v=QSGRKOG-SHQ&list=RDQSGRKOG-SHQ&start_radio=1",
                     "https://youtu.be/QSGRKOG-SHQ?list=PL1234567890ab&si=x"] {
            XCTAssertEqual(try MediaURLPolicy.singleVideo(link).absoluteString, "https://www.youtube.com/watch?v=QSGRKOG-SHQ")
            XCTAssertThrowsError(try MediaURLPolicy.canonicalInput(link), "Doğrudan alanda liste bağlantısı sessizce tek videoya dönmemeli")
        }
        XCTAssertThrowsError(try MediaURLPolicy.singleVideo("https://www.youtube.com/playlist?list=PL1234567890ab"))
    }

    func testYouTubeSearchIntentIsDetectedOnlyForSearchWords() {
        for prompt in ["YouTube'da Barış Manço bul", "Tarkan şarkılarını indir", "lo-fi video ara", "bana yeni klip keşfet"] {
            XCTAssertTrue(AIAssistantStore.wantsYouTubeSearch(prompt), prompt)
        }
        for prompt in ["Kitaplığımdan sakin bir şey çal", "Arada bir hareketli parça ekle", "Dinleme alışkanlıklarımı yorumla"] {
            XCTAssertFalse(AIAssistantStore.wantsYouTubeSearch(prompt), prompt)
        }
    }

    @MainActor
    func testPlaylistModeAcceptsASingleVideoLink() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("YTSingle-\(UUID())")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        try JSONSerialization.data(withJSONObject: ["isQueuePaused": true]).write(to: base.appendingPathComponent("downloads-settings.json"))
        ScriptProtocol.handle { request in
            guard request.url!.path == "/oembed" else { return .fail(.badURL) }
            return .reply(status: 200, headers: ["Content-Type": "application/json"],
                          body: try! JSONSerialization.data(withJSONObject: ["title": "Tükenir", "author_name": "ONEARTH Records"]))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptProtocol.self]
        let store = DownloadStore(library: LibraryStore(directory: base.appendingPathComponent("Media"), seed: false),
                                  sessionIdentifier: "single.test.\(UUID().uuidString)", downloadConfiguration: configuration,
                                  catalog: NativeYouTubeCatalog(session: URLSession(configuration: configuration)),
                                  initiallyForeground: true)
        await store.resolvePlaylist(url: "https://youtu.be/QSGRKOG-SHQ?si=drr36l2RZiprVaUz")
        let preview = try XCTUnwrap(store.playlistPreview, store.bulkNotice ?? "önizleme yok")
        XCTAssertEqual(preview.items.map(\.id), ["QSGRKOG-SHQ"])
        XCTAssertEqual(preview.items.first?.title, "Tükenir")
        XCTAssertEqual(preview.items.first?.url, "https://www.youtube.com/watch?v=QSGRKOG-SHQ")
        XCTAssertTrue(store.bulkNotice?.contains("tek bir video") == true)

        await store.resolvePlaylist(url: "https://www.youtube.com/@kanal")
        XCTAssertNil(store.playlistPreview)
        XCTAssertTrue(store.bulkNotice?.contains("oynatma listesi") == true, store.bulkNotice ?? "")
    }
}
