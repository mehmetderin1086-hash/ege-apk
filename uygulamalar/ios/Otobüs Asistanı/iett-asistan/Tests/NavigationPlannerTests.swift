import Foundation
import Testing
@testable import IETTAsistan

@MainActor struct NavigationTests {
    @Test func backForwardAndHomeKeepAConsistentHistory() {
        let nav = Navigator()
        nav.push(.line(code: "500T", stop: nil)); nav.pushedBySystem(old: [], new: nav.path)
        nav.push(.stop(code: 1)); nav.pushedBySystem(old: [.line(code: "500T", stop: nil)], new: nav.path)
        #expect(nav.canBack && !nav.canForward && nav.path.count == 2)
        nav.back()
        #expect(nav.path == [.line(code: "500T", stop: nil)] && nav.forward == [.stop(code: 1)])
        nav.pathChanged(old: [.line(code: "500T", stop: nil), .stop(code: 1)], new: nav.path)   // programatik değişiklik ileriyi bozmaz
        #expect(nav.canForward)
        nav.goForward()
        nav.pathChanged(old: [.line(code: "500T", stop: nil)], new: nav.path)
        #expect(nav.path.count == 2 && !nav.canForward)
        nav.home()
        nav.pathChanged(old: [.line(code: "500T", stop: nil), .stop(code: 1)], new: [])
        #expect(nav.path.isEmpty && nav.forward.count == 2)
        nav.goForward(); nav.pathChanged(old: [], new: nav.path)
        #expect(nav.path == [.line(code: "500T", stop: nil)])      // sırayla: önce hat, sonra durak
        nav.goForward(); nav.pathChanged(old: [.line(code: "500T", stop: nil)], new: nav.path)
        #expect(nav.path.last == .stop(code: 1) && !nav.canForward)
    }
    @Test func systemSwipeBackFeedsTheForwardStackAndNewPushClearsIt() {
        let nav = Navigator()
        nav.path = [.notes, .settings]
        nav.pathChanged(old: [.notes, .settings], new: [.notes])      // kenardan kaydırma
        #expect(nav.forward == [.settings])
        nav.path = [.notes, .stop(code: 9)]
        nav.pathChanged(old: [.notes], new: nav.path)                   // yeni sayfa açılınca ileri silinir
        #expect(nav.forward.isEmpty)
    }
}
private extension Navigator { func pushedBySystem(old: [Route], new: [Route]) { pathChanged(old: old, new: new) } }

struct PlannerTests {
    @Test func bundledRouteFindsKumkapiToEminonuMisirCarsisi() async throws {
        let folder = try #require(Bundle.main.url(forResource: "Seed", withExtension: nil))
        let data = try Data(contentsOf: folder.appending(path: "guzergah/BN1.json"))
        let route = try JSONDecoder().decode(LineRoute.self, from: data)
        let all = try #require(route.stops["G"])
        let board = try #require(all.first { $0.code == 105192 })
        let target = try #require(all.first { $0.code == 105401 })
        func durak(_ value: RouteStop) -> Durak { Durak(code: value.code, name: value.name, lat: value.lat, lon: value.lon) }
        let entry = RouteStore.Entry(line: "BN1", direction: "G")
        let result = await TripPlanner.direct(origins: [(durak(board), 0)], destinations: [(durak(target), 0)], lines: { _ in [entry] }, route: { _ in route }, hat: { _ in nil })
        #expect(result.first?.line == "BN1" && result.first?.alight.code == 105401)
    }
    /// Kuzeyden güneye: A(41.010) B C D(41.004) E(41.000) — hat X yön G; hat Y yalnız ters yönde.
    private func route(_ line: String, _ direction: String, codes: [Int], lats: [Double]) -> LineRoute {
        LineRoute(line: line, stops: [direction: zip(codes, lats).enumerated().map { RouteStop(seq: $0.offset + 1, code: $0.element.0, name: "S\($0.element.0)", lat: $0.element.1, lon: 29.0) }], destinations: [direction: "SON-\(line)"])
    }
    private func stop(_ code: Int, _ lat: Double) -> Durak { Durak(code: code, name: "S\(code)", lat: lat, lon: 29.0) }

    @Test func findsDirectLinesOnlyWhenBoardingComesBeforeAlighting() async {
        let x = route("X", "G", codes: [1, 2, 3, 4, 5], lats: [41.010, 41.008, 41.006, 41.004, 41.002])
        let y = route("Y", "G", codes: [5, 4, 3, 2, 1], lats: [41.002, 41.004, 41.006, 41.008, 41.010])   // ters sıra: 1'den 5'e gitmez
        let index: [Int: [RouteStore.Entry]] = [1: [.init(line: "X", direction: "G"), .init(line: "Y", direction: "G")], 2: [.init(line: "X", direction: "G")],
                                                4: [.init(line: "X", direction: "G"), .init(line: "Y", direction: "G")], 5: [.init(line: "Y", direction: "G")]]
        let routes = ["X": x, "Y": y]
        let options = await TripPlanner.direct(
            origins: [(stop(1, 41.010), 100), (stop(2, 41.008), 700)], destinations: [(stop(4, 41.004), 60), (stop(5, 41.002), 400)],
            lines: { index[$0] ?? [] }, route: { routes[$0] }, hat: { code in Hat(code: code, name: "t", tariff: nil, lengthKm: 1, tripMinutes: 20) })
        #expect(options.map(\.line) == ["X"], "\(options.map(\.line))")              // Y: biniş (1) inişten (4) sonra → olmaz
        let option = options[0]
        #expect(option.board.code == 1 && option.alight.code == 4 && option.stops == 3)
        #expect(option.walkToBoard == 100 && option.walkFromAlight == 60)
        #expect(abs(option.rideMeters - 666) < 10 && option.rideMinutes >= 1 && option.totalMinutes > option.rideMinutes)
    }
    @Test func picksTheFasterBoardingPairAndSortsByTotalTime() async {
        let x = route("X", "G", codes: [1, 2, 3, 4], lats: [41.010, 41.008, 41.006, 41.004])
        let z = route("Z", "G", codes: [1, 4], lats: [41.010, 41.004])
        let index: [Int: [RouteStore.Entry]] = [1: [.init(line: "X", direction: "G"), .init(line: "Z", direction: "G")], 2: [.init(line: "X", direction: "G")], 4: [.init(line: "X", direction: "G"), .init(line: "Z", direction: "G")]]
        let routes = ["X": x, "Z": z]
        // X için 2. durak (yürüyüş 50 m) 1. duraktan (500 m) daha iyi.
        let options = await TripPlanner.direct(origins: [(stop(1, 41.010), 500), (stop(2, 41.008), 50)], destinations: [(stop(4, 41.004), 0)],
                                               lines: { index[$0] ?? [] }, route: { routes[$0] }, hat: { _ in Hat(code: "x", name: "t", tariff: nil, lengthKm: 1, tripMinutes: 30) })
        let byLine = Dictionary(uniqueKeysWithValues: options.map { ($0.line, $0) })
        #expect(byLine["X"]?.board.code == 2 && byLine["Z"]?.board.code == 1)
        #expect(options.map(\.totalMinutes) == options.map(\.totalMinutes).sorted())
        let none = await TripPlanner.direct(origins: [], destinations: [(stop(4, 41.004), 0)], lines: { index[$0] ?? [] }, route: { routes[$0] }, hat: { _ in nil })
        #expect(none.isEmpty)
    }
    @MainActor @Test func assistantHandlesScheduleQuestionsAndFollowUps() {
        let lines = [Hat(code: "500T", name: "TUZLA"), Hat(code: "14M", name: "X")]
        #expect(LocalAssistant.parse("500T sefer saatleri", lines: lines) == .schedule("500T"))
        #expect(LocalAssistant.parse("14m ilk sefer kaçta?", lines: lines) == .schedule("14M"))
        #expect(LocalAssistant.parse("peki sefer saatleri?", lines: lines, context: "500T") == .schedule("500T"))
        #expect(LocalAssistant.parse("peki duyuru var mı", lines: lines, context: "14M") == .notices("14M"))
        #expect(LocalAssistant.parse("sefer saatleri", lines: lines) != .schedule("500T"))                // bağlam yoksa tahmin yok
        #expect(LocalAssistant.parse("500T kaç dk durağa", lines: lines) != .schedule("500T"))
    }
}
