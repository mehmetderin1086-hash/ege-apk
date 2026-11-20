import XCTest
@testable import Ritim

final class DownloadPolicyTests: XCTestCase {
    @MainActor
    func testHistoryWriteFailureRollsBackBeforeSchedulingDownload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DownloadTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = LibraryStore(directory: directory.appendingPathComponent("Media", isDirectory: true), seed: false)
        let store = DownloadStore(library: library, sessionIdentifier: "com.mehmetderin.ritim.tests.\(UUID().uuidString)")
        // A directory at the journal path deterministically rejects the atomic file write.
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("downloads.json"), withIntermediateDirectories: true)
        store.start(url: "https://example.com/song.mp3", format: .mp3)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(store.errorMessage?.contains("kaydedilemedi") == true)
    }

    func testEquivalentEndpointSpellingKeepsExistingJobsUsable() throws {
        let stored = try XCTUnwrap(URL(string: "https://EXAMPLE.com:443/ritim/"))
        let configured = try XCTUnwrap(URL(string: "https://example.com/ritim"))
        XCTAssertTrue(ServiceEndpointPolicy.matches(stored, configured))
        XCTAssertTrue(ServiceEndpointPolicy.matches(
            try XCTUnwrap(URL(string: "http://studio.local:80/")),
            try XCTUnwrap(URL(string: "http://studio.local"))))
    }

    func testChangedServiceCannotReceiveTheCurrentServicesToken() throws {
        let configured = try XCTUnwrap(URL(string: "https://media.example.com/ritim"))
        for oldEndpoint in [
            "https://old.example.com/ritim",
            "http://media.example.com/ritim",
            "https://media.example.com:8443/ritim",
            "https://media.example.com/another-service",
            "https://media.example.com/ritim/nested"
        ] {
            XCTAssertFalse(ServiceEndpointPolicy.matches(try XCTUnwrap(URL(string: oldEndpoint)), configured), oldEndpoint)
        }
    }
}

extension DownloadPolicyTests {
    func testResourcePolicyProtectsPlaybackAndKeepsRequestedLimit() {
        XCTAssertEqual(DownloadResourcePolicy.limit(requested: 10, thermal: .nominal, lowPower: false), 10)
        XCTAssertEqual(DownloadResourcePolicy.limit(requested: 10, thermal: .serious, lowPower: false), 2)
        XCTAssertEqual(DownloadResourcePolicy.limit(requested: 10, thermal: .critical, lowPower: false), 0)
        XCTAssertEqual(DownloadResourcePolicy.limit(requested: 10, thermal: .nominal, lowPower: true), 4)
        XCTAssertEqual(DownloadResourcePolicy.limit(requested: 2, thermal: .nominal, lowPower: true), 2)
    }
    func testOldDownloadJournalDefaultsAndNewFieldsRoundTrip() throws {
        let entry = DownloadEntry(title: "Eski", sourceURL: "https://example.com/a.mp3", format: .mp3)
        let data = try JSONEncoder().encode(entry)
        var restored = try JSONDecoder().decode(DownloadEntry.self, from: data)
        XCTAssertNil(restored.priority)
        XCTAssertNil(restored.stage)
        restored.priority = 1; restored.stage = .converting
        let result = try JSONDecoder().decode(DownloadEntry.self, from: JSONEncoder().encode(restored))
        XCTAssertEqual(result.priority, 1)
        XCTAssertEqual(result.stage, .converting)
    }
}

extension DownloadPolicyTests {
    func testRetryOnlyTransientNetworkErrorsAndCapsAttempts() {
        XCTAssertEqual(DownloadRetryPolicy.delay(error: URLError(.timedOut), attempt: 0), 5)
        XCTAssertEqual(DownloadRetryPolicy.delay(error: URLError(.networkConnectionLost), attempt: 1), 15)
        XCTAssertEqual(DownloadRetryPolicy.delay(error: URLError(.notConnectedToInternet), attempt: 2), 45)
        XCTAssertNil(DownloadRetryPolicy.delay(error: URLError(.timedOut), attempt: 3))
        XCTAssertNil(DownloadRetryPolicy.delay(error: URLError(.cancelled), attempt: 0))
        XCTAssertNil(DownloadRetryPolicy.delay(error: RitimError.message("Özel video"), attempt: 0))
    }
}
