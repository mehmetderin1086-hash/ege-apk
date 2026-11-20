import Foundation
import Testing
@testable import IETTAsistan

struct TimetableTests {
    private func trip(_ time: String, _ day: String = "I", _ direction: String = "G") -> PlannedTrip {
        PlannedTrip(line: "X", direction: direction, dayType: day, time: time)
    }
    @Test func timesAreFilteredDedupedAndSortedIncludingPastMidnight() {
        let trips = [trip("10:15"), trip("09:05"), trip("10:15"), trip("24:10"), trip("23:50"), trip("11:00", "C"), trip("12:00", "I", "D")]
        #expect(Timetable.times(trips, dayType: "I", direction: "G") == [545, 615, 1430, 1450])
        #expect(Timetable.times(trips, dayType: "C", direction: "G") == [660])
        #expect(Timetable.times(trips, dayType: "I", direction: "D") == [720])
        #expect(Timetable.times(trips, dayType: "I", direction: "") == [545, 615, 720, 1430, 1450])
        #expect(Timetable.format(1450) == "00:10" && Timetable.format(545) == "09:05")
    }
    @Test func groupsByHourAndSummarises() {
        let times = [350, 365, 380, 395, 420, 600]   // 05:50 06:05 06:20 06:35 07:00 10:00
        let rows = Timetable.byHour(times)
        #expect(rows.map(\.hour) == [5, 6, 7, 10] && rows[1].minutes == [5, 20, 35])
        let summary = try! #require(Timetable.summary(times))
        #expect(summary.first == 350 && summary.last == 600 && summary.count == 6 && summary.shortestGap == 15 && summary.longestGap == 180)
        #expect(abs(summary.averageGap! - 50) < 0.001)
        #expect(Timetable.summary([]) == nil)
        #expect(Timetable.summary([400])?.averageGap == nil)
    }
    @Test func nextDepartureAndStopOffset() {
        let times = [350, 365, 380]
        #expect(Timetable.nextIndex(times, nowMinutes: 360) == 1)
        #expect(Timetable.nextIndex(times, nowMinutes: 365) == 1)      // tam o dakikada kalkan hâlâ "sıradaki"
        #expect(Timetable.nextIndex(times, nowMinutes: 381) == nil)
        #expect(Timetable.offsetMinutes(tripMinutes: 120, stopAlong: 5000, routeLength: 20000) == 30)
        #expect(Timetable.offsetMinutes(tripMinutes: 120, stopAlong: 99999, routeLength: 20000) == 120)
        #expect(Timetable.offsetMinutes(tripMinutes: nil, stopAlong: 1, routeLength: 10) == nil)
        #expect(Timetable.offsetMinutes(tripMinutes: 60, stopAlong: 1, routeLength: 0) == nil)
    }

    /// Ağa hiç çıkmayan istemci: çevrimdışı davranışı sınamak için.
    final class OfflineProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var hits = 0
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() { Self.hits += 1; client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
        override func stopLoading() {}
    }
    private func offlineClient() -> IETTClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineProtocol.self]
        return IETTClient(session: URLSession(configuration: configuration))
    }
    @Test func freshDiskCacheSkipsTheNetworkAndStaleCacheSurvivesOffline() async throws {
        let folder = URL.temporaryDirectory.appending(path: "sefer-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let trips = [trip("10:15"), trip("10:30")]
        try JSONEncoder().encode(trips).write(to: folder.appending(path: "X.json"))
        let client = offlineClient(), before = OfflineProtocol.hits
        // Taze kopya: ağa gidilmez.
        #expect(try await client.timetable(line: "X", cacheFolder: folder) == trips)
        #expect(OfflineProtocol.hits == before)
        // Bayat kopya + ağ yok: eski kopya döner (çevrimdışı bakılabilir).
        #expect(try await client.timetable(line: "X", cacheFolder: folder, maxAge: 0) == trips)
        #expect(OfflineProtocol.hits > before)
        // Hiç kopya yoksa hata verir.
        await #expect(throws: (any Error).self) { try await client.timetable(line: "YOK", cacheFolder: folder) }
    }
    @Test func staleStopCacheSurvivesOfflineAndMissingCacheFails() async throws {
        let cache = URL.temporaryDirectory.appending(path: "durak-offline-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cache) }
        let saved = [Durak(code: 42, name: "Deneme", lat: 41, lon: 29)]
        try JSONEncoder().encode(saved).write(to: cache)
        let client = offlineClient()
        #expect(try await client.stops(cache: cache, maxAge: 0) == saved)
        try FileManager.default.removeItem(at: cache)
        await #expect(throws: (any Error).self) { try await client.stops(cache: cache, maxAge: 0) }
    }
}
