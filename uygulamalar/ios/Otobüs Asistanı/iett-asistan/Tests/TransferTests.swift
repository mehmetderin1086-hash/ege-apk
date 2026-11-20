import CoreLocation
import Foundation
import Testing
@testable import IETTAsistan

struct TransferTests {
    @Test func multiRoundSearchFindsTwoTransfersAndHonorsRideLimit() throws {
        let a = route("A", [1, 2], lat0: 41.03, step: 0.01)
        let b = route("B", [2, 3], lat0: 41.02, step: 0.01)
        let c = route("C", [3, 4], lat0: 41.01, step: 0.01)
        let routes = [a, b, c]
        let short = TripPlanner.multiTransfer(origins: [(stop(1), 80)], destinations: [(stop(4), 160)], routes: routes, hats: [], maxRides: 2)
        #expect(short.isEmpty)
        let options = TripPlanner.multiTransfer(origins: [(stop(1), 80)], destinations: [(stop(4), 160)], routes: routes, hats: [], maxRides: 3)
        let result = try #require(options.first)
        #expect(result.legs.map(\.line) == ["A", "B", "C"])
        #expect(result.walks == [80, 0, 0, 160])
        #expect(abs(result.totalMinutes - (result.legs.reduce(0) { $0 + $1.rideMinutes } + 15)) < 0.01)
        #expect(TripPlanner.multiTransfer(origins: [(stop(4), 0)], destinations: [(stop(1), 0)], routes: routes, hats: []).isEmpty)
    }

    @Test func currentOriginAreaConnectsToTuzlaMarinaWithBundledRoutes() throws {
        let root = try #require(Bundle.main.url(forResource: "Seed", withExtension: nil)).appending(path: "guzergah")
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        let routes = try files.map { try JSONDecoder().decode(LineRoute.self, from: Data(contentsOf: $0)) }
        let stops = routes.flatMap { $0.stops.values.flatMap { $0 } }
        let origin = try #require(stops.first { $0.code == 218771 })
        let destination = try #require(stops.first { $0.code == 225872 })
        func durak(_ s: RouteStop) -> Durak { Durak(code: s.code, name: s.name, lat: s.lat, lon: s.lon) }
        let found = TripPlanner.multiTransfer(origins: [(durak(origin), 0)], destinations: [(durak(destination), 0)], routes: routes, hats: [])
        let best = try #require(found.first)
        #expect(best.legs.count >= 3 && best.legs.count <= 4)
        #expect(best.legs.first?.board.code == 218771 && best.legs.last?.alight.code == 225872)
        #expect(best.legs.allSatisfy { $0.stops > 0 })
        #expect(best.walks.dropFirst().dropLast().allSatisfy { $0 <= 250 })
    }
    @Test func itineraryGeometryUsesTheCorrectOccurrenceAndRejectsWrongDirection() throws {
        let loop = route("A", [1, 2, 1, 3, 4], lat0: 41.03, step: 0.001)
        let points = try #require(loop.stops["G"])
        let leg = TripLeg(line: "A", direction: "G", destination: "SON", board: points[2], alight: points[4], stops: 2, rideMeters: 300, rideMinutes: 5)
        #expect(leg.routeStops(in: loop).map(\.code) == [1, 3, 4])
        #expect(leg.routeStops(in: route("B", [1, 2, 1, 3, 4], lat0: 41.03, step: 0.001)).isEmpty)
        let reversed = TripLeg(line: "A", direction: "G", destination: "SON", board: points[4], alight: points[2], stops: 2, rideMeters: 300, rideMinutes: 5)
        #expect(reversed.routeStops(in: loop).isEmpty)
        let wrongDirection = TripLeg(line: "A", direction: "D", destination: "SON", board: points[2], alight: points[4], stops: 2, rideMeters: 300, rideMinutes: 5)
        #expect(wrongDirection.routeStops(in: loop).isEmpty)
    }

    @Test func itinerarySharingKeepsEveryLegWalkAndUncertainty() throws {
        let routes = [route("A", [1, 2], lat0: 41.03, step: 0.01), route("B", [2, 3], lat0: 41.02, step: 0.01), route("C", [3, 4], lat0: 41.01, step: 0.01)]
        let legs = routes.map { r in
            TripLeg(line: r.line, direction: "G", destination: r.destination("G"), board: r.stops["G"]!.first!, alight: r.stops["G"]!.last!, stops: 1, rideMeters: 1000, rideMinutes: 5)
        }
        let option = MultiTripOption(legs: legs, walks: [80, 120, 0, 160])
        let shared = ShareBuilder.itinerary(option, destination: stop(4))
        for line in ["1. A", "2. B", "3. C", "120 m", "160 m", "2 aktarma", "ilk aracı bekleme dahil değildir", "kuş uçuşudur", "Sefer saatlerini"] { #expect(shared.body.contains(line)) }
        #expect(shared.maps?.absoluteString.contains("q=S4") == true)
        #expect(shared.deep == nil) // Bir hat bağlantısını tüm yolculuk gibi sunma.
        let single = TransferOption(first: legs[0], second: legs[1], walkToBoard: 80, walkFromAlight: 160, transferWalkMeters: 120)
        #expect(single.itinerary.totalMinutes == single.totalMinutes)
        let direct = TripOption(line: "A", direction: "G", destination: "SON", board: legs[0].board, alight: legs[0].alight, stops: 1, rideMeters: 1000, rideMinutes: 5, walkToBoard: 80, walkFromAlight: 160)
        #expect(direct.itinerary.totalMinutes == direct.totalMinutes)
    }

    @MainActor @Test func locationMustBeRecentAndValid() {
        let now = Date(timeIntervalSince1970: 1000)
        func location(age: Double, accuracy: Double = 20) -> CLLocation {
            .init(coordinate: .init(latitude: 41, longitude: 29), altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: now.addingTimeInterval(-age))
        }
        #expect(AppModel.isUsableLocation(location(age: 30), now: now))
        #expect(!AppModel.isUsableLocation(location(age: 121), now: now))
        #expect(!AppModel.isUsableLocation(location(age: -121), now: now))
        #expect(!AppModel.isUsableLocation(location(age: 0, accuracy: -1), now: now))
        #expect(!AppModel.isUsableLocation(nil, now: now))
    }

    @Test func cancelledSearchStopsBeforeFetchingMoreLines() async {
        let search = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var requests = 0
            let lines: (Int) async -> [RouteStore.Entry] = { _ in requests += 1; return [] }
            let direct = await TripPlanner.direct(origins: [(stop(1), 0)], destinations: [(stop(2), 0)], lines: lines, route: { _ in nil }, hat: hat)
            let transfer = await TripPlanner.withTransfer(origins: [(stop(1), 0)], destinations: [(stop(2), 0)], lines: lines, route: { _ in nil }, hat: hat)
            #expect(direct.isEmpty && transfer.isEmpty && requests == 0)
        }
        await search.value
    }

    private func route(_ line: String, _ codes: [Int], lat0: Double, step: Double, lon: Double = 29.0) -> LineRoute {
        LineRoute(line: line, stops: ["G": codes.enumerated().map { RouteStop(seq: $0.offset + 1, code: $0.element, name: "S\($0.element)", lat: lat0 - Double($0.offset) * step, lon: lon) }], destinations: ["G": "SON-\(line)"])
    }
    private func stop(_ code: Int) -> Durak { Durak(code: code, name: "S\(code)", lat: 41, lon: 29) }
    private let hat = { (code: String) in Hat(code: code, name: "t", tariff: nil, lengthKm: 5, tripMinutes: 30) }

    @Test func findsOneTransferAndRespectsOrderAndSameLineRule() async {
        // A: 1-2-3-4, B: 9-3-5-6 (3'te kesişir), C: 3-1 (ters: 1'e giden), hedef 6.
        let a = route("A", [1, 2, 3, 4], lat0: 41.010, step: 0.002), b = route("B", [9, 3, 5, 6], lat0: 41.006, step: 0.002), c = route("C", [6, 3, 1], lat0: 41.0, step: 0.002)
        let routes = ["A": a, "B": b, "C": c]
        var index: [Int: [RouteStore.Entry]] = [:]
        for (line, r) in routes { for s in r.stops["G"]! { index[s.code, default: []].append(.init(line: line, direction: "G")) } }
        let options = await TripPlanner.withTransfer(origins: [(stop(1), 120)], destinations: [(stop(6), 90)], lines: { index[$0] ?? [] }, route: { routes[$0] }, hat: hat)
        #expect(options.count == 1, "\(options.map(\.id))")
        let option = options[0]
        #expect(option.first.line == "A" && option.second.line == "B" && option.first.alight.code == 3 && option.second.board.code == 3 && option.second.alight.code == 6)
        #expect(option.first.stops == 2 && option.second.stops == 2 && option.walkToBoard == 120 && option.walkFromAlight == 90)
        #expect(option.totalMinutes > option.first.rideMinutes + option.second.rideMinutes + TransferOption.assumedWait)
        // Hedefe B değil, yalnız ters yönde giden C varsa sonuç yok.
        let none = await TripPlanner.withTransfer(origins: [(stop(1), 0)], destinations: [(stop(9), 0)], lines: { index[$0] ?? [] }, route: { routes[$0] }, hat: hat)
        #expect(none.isEmpty)
        #expect(await TripPlanner.withTransfer(origins: [], destinations: [(stop(6), 0)], lines: { index[$0] ?? [] }, route: { routes[$0] }, hat: hat).isEmpty)
    }
    @Test func findsWalkingTransferBetweenDifferentStopsAndIncludesWalkingTime() async throws {
        let a = route("A", [1, 2], lat0: 41.010, step: 0.002)
        let b = route("B", [3, 4], lat0: 41.0079, step: 0.002)
        let routes = ["A": a, "B": b]
        let index: [Int: [RouteStore.Entry]] = [1: [.init(line: "A", direction: "G")], 2: [.init(line: "A", direction: "G")], 3: [.init(line: "B", direction: "G")], 4: [.init(line: "B", direction: "G")]]
        let options = await TripPlanner.withTransfer(origins: [(stop(1), 0)], destinations: [(stop(4), 0)], lines: { index[$0] ?? [] }, route: { routes[$0] }, hat: hat, transferStops: { s in s.code == 2 ? [(2, 0), (3, 120)] : [(s.code, 0)] })
        let result = try #require(options.first)
        #expect(result.first.alight.code == 2 && result.second.board.code == 3 && result.transferWalkMeters == 120)
        #expect(abs(result.totalMinutes - (result.first.rideMinutes + result.second.rideMinutes + TransferOption.assumedWait + 1.5)) < 0.001)
        #expect(ShareBuilder.transfer(result).body.contains("120 m"))
        let tooFar = await TripPlanner.withTransfer(origins: [(stop(1), 0)], destinations: [(stop(4), 0)], lines: { index[$0] ?? [] }, route: { routes[$0] }, hat: hat, transferStops: { s in s.code == 2 ? [(3, 251)] : [(s.code, 0)] })
        #expect(tooFar.isEmpty)
    }
    @Test func deepLinksRoundTrip() {
        let line = DeepLink.line("500T", stop: 301341)
        #expect(line.absoluteString == "iettasistan://line/500T?stop=301341")
        let parsed = DeepLink.parse(line)
        #expect(parsed?.kind == "line" && parsed?.id == "500T" && parsed?.stop == 301341)
        #expect(DeepLink.parse(DeepLink.stop(7))?.kind == "stop" && DeepLink.parse(DeepLink.stop(7))?.id == "7")
        #expect(DeepLink.parse(DeepLink.timetable("E-10"))?.id == "E-10")
        #expect(DeepLink.parse(URL(string: "https://example.com/line/500T")!) == nil)
        #expect(DeepLink.parse(URL(string: "iettasistan://line")!) == nil)
        #expect(Favorite(line: "14M", stopCode: 2, stopName: "X", lat: 1, lon: 2).deepLink.absoluteString == "iettasistan://line/14M?stop=2")
    }
    @Test func savedTripsEncodeAndKeepLocationOrigin() throws {
        let trips = [SavedTrip(name: "Ev → İş", fromCode: nil, fromName: "Konumum", toCode: 5, toName: "İş durağı"), SavedTrip(name: "Okul", fromCode: 3, fromName: "A", toCode: 9, toName: "B")]
        let back = try JSONDecoder().decode([SavedTrip].self, from: JSONEncoder().encode(trips))
        #expect(back == trips && back[0].fromCode == nil && back[0].id != back[1].id)
    }
}

struct LineSummaryTests {
    private func route() -> LineRoute {
        LineRoute(line: "X", stops: ["G": (0..<5).map { RouteStop(seq: $0 + 1, code: 100 + $0, name: "S\($0)", lat: 41.010 - Double($0) * 0.002, lon: 29.0) }], destinations: ["G": "SON"])
    }
    private func bus(_ id: String, lat: Double, dir: String = "G") -> Bus { Bus(plate: id, lat: lat, lon: 29.0, line: "X", routeCode: "X_\(dir)_D0", lastSeen: .now) }

    @Test func summaryCountsBusesAndPicksTheNearestStopWithItsEta() {
        let user = CLLocationCoordinate2D(latitude: 41.0061, longitude: 29.0)          // 3. durağa (S2: 41.006) ~11 m
        let summary = LineSummary.make(line: "X", buses: [bus("A", lat: 41.0095), bus("B", lat: 41.0005), bus("C", lat: 41.003, dir: "D")], route: route(), user: user)
        #expect(summary.total == 3 && summary.byDirection == ["G": 2, "D": 1])
        #expect(summary.stopCode == 102 && summary.stopName == "S2" && (summary.stopMeters ?? 999) < 30)
        #expect(summary.eta?.id == "A" && summary.eta?.stopsLeft != nil)                  // B durağı geçmiş, C ters yönde
    }
    @Test func summaryWithoutLocationOrRouteOnlyCounts() {
        let a = LineSummary.make(line: "X", buses: [bus("A", lat: 41.0)], route: route(), user: nil)
        #expect(a.total == 1 && a.stopName == nil && a.eta == nil)
        let b = LineSummary.make(line: "X", buses: [], route: nil, user: CLLocationCoordinate2D(latitude: 41, longitude: 29))
        #expect(b.total == 0 && b.stopCode == nil)
        // 2 km'den uzaktaysan durak önerilmez.
        let far = LineSummary.make(line: "X", buses: [bus("A", lat: 41.0)], route: route(), user: CLLocationCoordinate2D(latitude: 40.9, longitude: 29.2))
        #expect(far.stopName == nil && far.total == 1)
    }
}

struct LineTrackTests {
    @Test func tracksPlaceBusesAndTheUserStopAlongEachDirection() {
        let g = (0..<5).map { RouteStop(seq: $0 + 1, code: 100 + $0, name: "S\($0)", lat: 41.010 - Double($0) * 0.002, lon: 29.0) }
        let d = g.reversed().enumerated().map { RouteStop(seq: $0.offset + 1, code: $0.element.code, name: $0.element.name, lat: $0.element.lat, lon: 29.0) }
        let route = LineRoute(line: "X", stops: ["G": g, "D": d], destinations: ["G": "SON", "D": "BAŞ"])
        func bus(_ id: String, _ lat: Double, _ dir: String) -> Bus { Bus(plate: id, lat: lat, lon: 29.0, line: "X", routeCode: "X_\(dir)_D0", lastSeen: .now) }
        let user = CLLocationCoordinate2D(latitude: 41.006, longitude: 29.0)                  // 3. durak (kod 102), hat ortası
        let summary = LineSummary.make(line: "X", buses: [bus("A", 41.010, "G"), bus("B", 41.006, "G"), bus("C", 41.004, "D"), bus("U", 41.4, "G")], route: route, user: user)
        let tracks = Dictionary(uniqueKeysWithValues: summary.tracks.map { ($0.direction, $0) })
        #expect(summary.tracks.count == 2 && tracks["G"]?.buses.count == 2 && abs((tracks["G"]?.buses.first ?? 1) - 0) < 0.02 && abs((tracks["G"]?.buses.last ?? 0) - 0.5) < 0.02)
        #expect(tracks["D"]?.buses.count == 1 && abs((tracks["D"]?.buses.first ?? 0) - 0.25) < 0.03)          // dönüş 41.002 den başlar; 41.004 → yolun 1/4'ü
        #expect(abs((tracks["G"]?.user ?? 9) - 0.5) < 0.01 && abs((tracks["D"]?.user ?? 9) - 0.5) < 0.01 && tracks["G"]?.destination == "SON")
        // Konum yoksa şerit yine çizilir ama durak işareti olmaz.
        let noUser = LineSummary.make(line: "X", buses: [bus("A", 41.008, "G")], route: route, user: nil)
        #expect(noUser.tracks.count == 2 && noUser.tracks.allSatisfy { $0.user == nil } && noUser.total == 1)
    }
}
