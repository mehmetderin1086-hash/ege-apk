import CoreLocation
import Foundation
import Testing
@testable import IETTAsistan

struct RouteTests {
    private func table(_ rows: [(dir: String, name: String, seq: Int, code: Int, lat: Double)]) -> Data {
        let body = rows.map { "<Table><HATKODU>X</HATKODU><YON>\($0.dir)</YON><YON_ADI>\($0.dir == "G" ? "SON" : "BAŞ")</YON_ADI><SIRANO>\($0.seq)</SIRANO><DURAKKODU>\($0.code)</DURAKKODU><DURAKADI>\($0.name)</DURAKADI><XKOORDINATI>29.000000</XKOORDINATI><YKOORDINATI>\($0.lat)</YKOORDINATI></Table>" }.joined()
        return Data("<soap:Envelope xmlns:soap=\"x\"><soap:Body><R><Result><NewDataSet xmlns=\"\">\(body)</NewDataSet></Result></R></soap:Body></soap:Envelope>".utf8)
    }
    /// Kuzeyden güneye: 41.010 → 41.000, 0,002° ≈ 222 m aralıkla 6 durak.
    private func route() throws -> LineRoute {
        let lats = [41.010, 41.008, 41.006, 41.004, 41.002, 41.000]
        let rows = lats.enumerated().map { (dir: "G", name: "D\($0.offset + 1)", seq: $0.offset + 1, code: 100 + $0.offset, lat: $0.element) }
        // Sıra bozuk gelse de sıralanmalı.
        return try LineRoute.parse(line: "X", soap: table(rows.reversed()))
    }
    private func bus(_ id: String, lat: Double, direction: String = "G", at: Date = .now) -> Bus {
        Bus(plate: id, lat: lat, lon: 29.0, line: "X", routeCode: "X_\(direction)_D0", lastSeen: at)
    }

    @Test func parsesOrderedStopsPerDirection() throws {
        let route = try route()
        #expect(route.directions == ["G"] && route.stops["G"]?.map(\.seq) == [1, 2, 3, 4, 5, 6])
        #expect(route.destination("G") == "SON" && route.stopIndex(code: 103, direction: "G") == 3)
        #expect(route.directions(serving: 999).isEmpty)
        #expect(throws: IETTError.self) { try LineRoute.parse(line: "X", soap: Data("<a><faultstring>Hata</faultstring></a>".utf8)) }
    }
    @Test func projectionMeasuresAlongTheRoute() throws {
        let geometry = RouteGeometry(stops: try route().stops["G"]!)
        let p = geometry.project(.init(latitude: 41.007, longitude: 29.0001))!
        #expect(abs(p.along - 333) < 15 && p.off < 15, "\(p)")   // 1. duraktan 333 m
        #expect(abs(geometry.length - 1110) < 10)
    }
    @Test func etaCountsStopsLeftAndDropsPassedBuses() throws {
        let route = try route(), tracker = LiveTracker(), now = Date()
        // Durak 5 (kod 104, 41.002). Araç A 41.009'da (1. ve 2. durak arası), B durağı geçmiş, C ters yönde.
        let buses = [bus("A", lat: 41.009), bus("B", lat: 41.0005), bus("C", lat: 41.008, direction: "D")]
        let etas = RouteETAEngine.etas(buses: buses, route: route, stopCode: 104, tracker: tracker, now: now)
        #expect(etas.map(\.id) == ["A"] , "\(etas)")
        #expect(etas[0].stopsLeft == 4 && etas[0].state == .approaching && abs(etas[0].distance - 777) < 20)
        #expect(abs(etas[0].minutes - 777 / 5.0 / 60) < 0.1, "\(etas[0].minutes)")   // varsayılan 5 m/s
        // Durakta olan araç
        #expect(RouteETAEngine.etas(buses: [bus("D", lat: 41.0021)], route: route, stopCode: 104, tracker: tracker, now: now).first?.state == .atStop)
        // Hattan 2 km uzakta (garaj/sapma) araç göz ardı edilir.
        #expect(RouteETAEngine.etas(buses: [Bus(plate: "E", lat: 41.009, lon: 29.03, line: "X", routeCode: "X_G_D0")], route: route, stopCode: 104, tracker: tracker, now: now).isEmpty)
    }
    @Test func measuredSpeedMovesTheEstimate() throws {
        let route = try route(), tracker = LiveTracker(), now = Date()
        tracker.ingest([bus("A", lat: 41.0100, at: now.addingTimeInterval(-60))], now: now.addingTimeInterval(-60))
        tracker.ingest([bus("A", lat: 41.0060, at: now)], now: now)     // 444 m / 60 s ≈ 7,4 m/s
        let fast = RouteETAEngine.etas(buses: [bus("A", lat: 41.0060, at: now)], route: route, stopCode: 105, tracker: tracker, now: now)[0].minutes
        let slow = RouteETAEngine.etas(buses: [bus("A", lat: 41.0060, at: now)], route: route, stopCode: 105, tracker: LiveTracker(), now: now)[0].minutes
        #expect(fast < slow, "hızlı \(fast) yavaş \(slow)")
    }
    @Test func routeStoreCachesToDiskAndBuildsStopIndex() async throws {
        let folder = URL.temporaryDirectory.appending(path: "rs-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let route = try route(), data = try JSONEncoder().encode(route)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appending(path: "X.json"))
        let store = RouteStore(folder: folder)
        #expect(try await store.route("X") == route)                  // ağa gitmeden diskten
        await store.buildIndex(lines: ["X"])
        #expect(await store.lines(atStop: 103) == [.init(line: "X", direction: "G")])
        let reopened = RouteStore(folder: folder)
        let indexed = await reopened.hasIndex(), first = await reopened.lines(atStop: 100)
        #expect(indexed && first.count == 1)
    }
    @Test func seedCopiesMissingRoutesOnlyAndFeedsTheIndex() async throws {
        let root = URL.temporaryDirectory.appending(path: "seed-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appending(path: "bundle"), folder = root.appending(path: "store")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let route = try route(), newer = LineRoute(line: "Y", stops: route.stops, destinations: ["G": "ESKI"])
        try JSONEncoder().encode(route).write(to: bundle.appending(path: "X.json"))
        try JSONEncoder().encode(newer).write(to: bundle.appending(path: "Y.json"))
        let store = RouteStore(folder: folder)
        try JSONEncoder().encode(LineRoute(line: "Y", stops: route.stops, destinations: ["G": "YENI"])).write(to: folder.appending(path: "Y.json"))
        #expect(await store.seed(from: bundle) == 1)                       // yalnız eksik X; mevcut Y'ye dokunulmadı
        #expect(try await store.route("Y").destination("G") == "YENI")
        await store.buildIndex(lines: ["X", "Y"])
        #expect(await store.lines(atStop: 102).map(\.line) == ["X", "Y"])
        #expect(await store.seed(from: nil) == 0)
    }
    @MainActor @Test func assistantUnderstandsStopLineQuestion() {
        let lines = [Hat(code: "500T", name: "TUZLA")]
        #expect(LocalAssistant.parse("Kadıköy çarşı durağından hangi hatlar geçer?", lines: lines) == .stopLines("kadikoy carsi"))
    }
}
