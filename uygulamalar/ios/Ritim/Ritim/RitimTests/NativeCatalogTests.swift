import XCTest
@testable import Ritim

final class NativeCatalogTests: XCTestCase {
    private func catalog() -> NativeYouTubeCatalog {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NativeCatalogProtocol.self]
        let session = URLSession(configuration: configuration)
        addTeardownBlock { session.invalidateAndCancel(); NativeCatalogProtocol.handle(nil) }
        return NativeYouTubeCatalog(session: session)
    }

    private static func row(_ number: Int, playable: Bool = true, key: String = "playlistVideoRenderer") -> [String: Any] {
        [key: ["videoId": String(format: "n%010d", number), "title": ["runs": [["text": "Parça \(number)"]]],
               "shortBylineText": ["simpleText": "Sanatçı"], "lengthText": ["simpleText": "1:02:03"], "isPlayable": playable]]
    }

    private static func continuation(_ token: String) -> [String: Any] {
        ["continuationItemRenderer": ["continuationEndpoint": ["continuationCommand": ["token": token]]]]
    }

    private static func html(_ object: [String: Any]) throws -> Data {
        let json = String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
        return Data("<script>var ytInitialData = \(json);</script><script>{\"INNERTUBE_CLIENT_VERSION\":\"2.test\"}</script>".utf8)
    }

    func testInitialDataHandlesEscapedQuotesBackslashesAndBracesInsideStrings() throws {
        let title = #"A } { \"quote\" \\ ending"#
        let expected: [String: Any] = ["title": title, "nested": ["value": "}", "number": 3]]
        let data = try Self.html(expected)
        let parsed = try XCTUnwrap(NativeYouTubeCatalog.initialData(String(decoding: data, as: UTF8.self)))
        XCTAssertEqual(parsed["title"] as? String, title)
        XCTAssertEqual((parsed["nested"] as? [String: Any])?["number"] as? Int, 3)
        XCTAssertNotNil(NativeYouTubeCatalog.initialData(#"window["ytInitialData"] = {"ok":true};"#))
        XCTAssertNil(NativeYouTubeCatalog.initialData("var ytInitialData = {broken"))
    }

    func testRowsPreserveOrderAndRejectUnavailableOrUnsupportedIDs() {
        var rows = [Self.row(2), Self.row(1), Self.row(2), Self.row(3, playable: false)]
        rows.append(["playlistVideoRenderer": ["videoId": "https://evil.example/a", "title": ["simpleText": "Bad"]]])
        rows.append(["playlistVideoRenderer": ["videoId": "short", "title": ["simpleText": "Bad"]]])
        let result = NativeYouTubeCatalog.items(in: ["contents": rows], renderers: ["playlistVideoRenderer"])
        XCTAssertEqual(result.map(\.id), ["n0000000002", "n0000000001"])
        XCTAssertEqual(result.map(\.index), [0, 1])
        XCTAssertEqual(result.first?.duration, 3_723)
        XCTAssertTrue(result.allSatisfy { $0.url.hasPrefix("https://www.youtube.com/watch?v=") })
    }

    func testFinitePlaylistContinuesAcrossPageContainingOnlyUnavailableRows() async throws {
        let client = catalog()
        let requests = NativeCatalogRequests()
        let first = try Self.html(["playlistVideoListRenderer": ["contents": [Self.row(1), Self.continuation("page-a")]]])
        NativeCatalogProtocol.handle { request in
            requests.add(request)
            if request.httpMethod != "POST" { return .init(body: first) }
            let count = requests.all.filter { $0.httpMethod == "POST" }.count
            let rows: [[String: Any]] = count == 1
                ? [Self.row(9, playable: false), Self.continuation("page-b")]
                : [Self.row(2)]
            return .json(["onResponseReceivedActions": [["appendContinuationItemsAction": ["continuationItems": rows]]]])
        }
        let preview = try await client.resolvePlaylist(url: URL(string: "https://www.youtube.com/playlist?list=PLnativeTest")!)
        XCTAssertEqual(preview.items.map(\.id), ["n0000000001", "n0000000002"])
        XCTAssertEqual(requests.all.count, 3)
        XCTAssertFalse(preview.truncated)
    }

    func testRepeatedContinuationStopsWithoutInfiniteRequestsAndDeduplicates() async throws {
        let client = catalog()
        let requests = NativeCatalogRequests()
        let first = try Self.html(["playlistVideoListRenderer": ["contents": [Self.row(1), Self.continuation("same")]]])
        NativeCatalogProtocol.handle { request in
            requests.add(request)
            if request.httpMethod != "POST" { return .init(body: first) }
            return .json(["continuationContents": ["contents": [Self.row(1), Self.row(2), Self.continuation("same")]]])
        }
        let preview = try await client.resolvePlaylist(url: URL(string: "https://www.youtube.com/playlist?list=PLnativeTest")!)
        XCTAssertEqual(preview.items.map(\.id), ["n0000000001", "n0000000002"])
        XCTAssertEqual(requests.all.count, 2)
        XCTAssertEqual(preview.skipped, 1)
    }

    func testInfiniteMixStopsAtRepeatedPageAndMarksTruncated() async throws {
        let client = catalog()
        let requests = NativeCatalogRequests()
        let panel: [String: Any] = ["title": "Mix", "contents": [Self.row(1, key: "playlistPanelVideoRenderer"), Self.row(2, key: "playlistPanelVideoRenderer")]]
        let root: [String: Any] = ["contents": ["twoColumnWatchNextResults": ["playlist": ["playlist": panel]]]]
        let first = try Self.html(root)
        NativeCatalogProtocol.handle { request in
            requests.add(request)
            return request.httpMethod == "POST" ? .json(root) : .init(body: first)
        }
        let preview = try await client.resolvePlaylist(url: URL(string: "https://youtube.com/playlist?list=RDnativeTest")!)
        XCTAssertEqual(preview.items.count, 2)
        XCTAssertEqual(preview.title, "Mix")
        XCTAssertTrue(preview.truncated)
        XCTAssertEqual(requests.all.count, 2)
        XCTAssertEqual(requests.all.last?.url?.path, "/youtubei/v1/next")
    }

    func testSearchEncodesQueryAndOnlyReturnsValidatedVideoLinks() async throws {
        let client = catalog()
        let requests = NativeCatalogRequests()
        let first = try Self.html(["contents": [Self.row(1, key: "videoRenderer"), Self.row(2, key: "videoRenderer"),
                                              ["videoRenderer": ["videoId": "../unsafe", "title": ["simpleText": "Bad"]]]]])
        NativeCatalogProtocol.handle { request in requests.add(request); return .init(body: first) }
        let query = "https://outside.example/?a=1&b=2 Türkçe"
        let found = try await client.search(query: query, limit: 1)
        XCTAssertEqual(found.count, 1)
        let request = try XCTUnwrap(requests.all.first)
        XCTAssertEqual(request.url?.host, "www.youtube.com")
        XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, query)
        XCTAssertEqual(found[0].url, "https://www.youtube.com/watch?v=n0000000001")
    }

    func testUnsupportedPlaylistHostIsRejectedBeforeAnyRequest() async throws {
        let client = catalog()
        let requests = NativeCatalogRequests()
        NativeCatalogProtocol.handle { request in requests.add(request); return .init(status: 500, body: Data()) }
        do {
            _ = try await client.resolvePlaylist(url: URL(string: "https://youtube.com.evil.example/playlist?list=PLnativeTest")!)
            XCTFail("Unsupported host must fail before networking")
        } catch { }
        XCTAssertTrue(requests.all.isEmpty)
    }

    func testContentRangeParsesAndRejectsInvalidBounds() throws {
        let range = try XCTUnwrap(NativeYouTubeDownloader.contentRange("bytes 0-1048575/2097152"))
        XCTAssertEqual(range.start, 0)
        XCTAssertEqual(range.end, 1_048_575)
        XCTAssertEqual(range.total, 2_097_152)
        for invalid in [nil, "bytes */100", "bytes 10-9/100", "bytes -1-5/10", "items 0-1/2", "bytes 0-1/0", "bytes 0-100/100", "bytes 0-1/*", "bytes 0-999999999999999999999/2"] as [String?] {
            XCTAssertNil(NativeYouTubeDownloader.contentRange(invalid), "Accepted invalid range: \(invalid ?? "nil")")
        }
    }
}

private final class NativeCatalogRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URLRequest] = []
    func add(_ request: URLRequest) { lock.withLock { stored.append(request) } }
    var all: [URLRequest] { lock.withLock { stored } }
}

private final class NativeCatalogProtocol: URLProtocol, @unchecked Sendable {
    struct Reply {
        var status = 200
        var body: Data
        static func json(_ object: [String: Any]) -> Self {
            .init(body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
        }
    }
    private static let lock = NSLock()
    private static var handler: ((URLRequest) -> Reply)?
    static func handle(_ next: ((URLRequest) -> Reply)?) { lock.withLock { handler = next } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let result = Self.lock.withLock { Self.handler }?(request) ?? Reply(status: 500, body: Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: result.status, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
