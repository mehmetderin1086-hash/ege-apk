import Foundation
import Testing
@testable import IETTAsistan

struct StopDirectionTests {
    private func route(_ line: String, dest: String, codes: [Int], lat0: Double, dLat: Double, dLon: Double) -> LineRoute {
        LineRoute(line: line, stops: ["G": codes.enumerated().map { RouteStop(seq: $0.offset + 1, code: $0.element, name: "S\($0.element)", lat: lat0 + Double($0.offset) * dLat, lon: 29.0 + Double($0.offset) * dLon) }], destinations: ["G": dest])
    }
    @Test func compassNamesCoverAllEightDirectionsAndWrapAround() {
        #expect(CompassText.name(0) == "Kuzey" && CompassText.name(44) == "Kuzeydoğu" && CompassText.name(90) == "Doğu" && CompassText.name(180) == "Güney" && CompassText.name(270) == "Batı")
        #expect(CompassText.name(350) == "Kuzey" && CompassText.name(359.9) == "Kuzey" && CompassText.name(-10) == "Kuzey" && CompassText.name(225) == "Güneybatı" && CompassText.name(315) == "Kuzeybatı")
        #expect(CompassText.heading(135) == "Güneydoğuya doğru" && CompassText.heading(0) == "Kuzeye doğru" && CompassText.heading(270) == "Batıya doğru")
    }
    @Test func groupsLinesByDestinationAndDirectionSector() {
        // Durak 2: A ve B kuzeye (aynı varış), C güneye (başka varış), D kuzeye ama başka varış.
        let routes = ["A": route("A", dest: "BEYKOZ", codes: [1, 2, 3], lat0: 41.0, dLat: 0.002, dLon: 0),
                      "B": route("B", dest: "BEYKOZ", codes: [9, 2, 8], lat0: 41.0, dLat: 0.002, dLon: 0),
                      "C": route("C", dest: "KADIKÖY", codes: [5, 2, 6], lat0: 41.004, dLat: -0.002, dLon: 0),
                      "D": route("D", dest: "ÜSKÜDAR", codes: [7, 2, 4], lat0: 41.0, dLat: 0.002, dLon: 0)]
        let entries = ["A", "B", "C", "D"].map { RouteStore.Entry(line: $0, direction: "G") }
        let groups = StopDirections.make(stopCode: 2, entries: entries, routes: routes)
        #expect(groups.count == 3)
        #expect(groups[0].destination == "BEYKOZ" && groups[0].lines == ["A", "B"] && groups[0].compass == "Kuzey")
        let south = groups.first { $0.destination == "KADIKÖY" }
        #expect(south?.compass == "Güney" && south?.lines == ["C"])
        #expect(groups.contains { $0.destination == "ÜSKÜDAR" && $0.lines == ["D"] })
    }
    @Test func lastStopUsesThePreviousSegmentAndUnknownRoutesAreSkipped() {
        let routes = ["E": route("E", dest: "SON", codes: [1, 2, 3], lat0: 41.0, dLat: 0.0, dLon: 0.003)]   // doğuya
        let atEnd = StopDirections.make(stopCode: 3, entries: [.init(line: "E", direction: "G")], routes: routes)
        #expect(atEnd.count == 1 && atEnd[0].compass == "Doğu")
        #expect(StopDirections.make(stopCode: 99, entries: [.init(line: "E", direction: "G")], routes: routes).isEmpty)
        #expect(StopDirections.make(stopCode: 2, entries: [.init(line: "YOK", direction: "G")], routes: routes).isEmpty)
    }
    @Test func averageBearingHandlesTheNorthWrapAround() {
        // 350° ve 10° yönlü iki hat aynı sektörde birleşmez ama her biri kendi yönünü korur; ortalama sınırda 0 civarı olmalı.
        let a = route("A", dest: "X", codes: [1, 2, 3], lat0: 41.0, dLat: 0.002, dLon: -0.0003), b = route("B", dest: "X", codes: [4, 2, 5], lat0: 41.0, dLat: 0.002, dLon: 0.0003)
        let groups = StopDirections.make(stopCode: 2, entries: [.init(line: "A", direction: "G"), .init(line: "B", direction: "G")], routes: ["A": a, "B": b])
        #expect(groups.allSatisfy { $0.compass == "Kuzey" })
    }
}
