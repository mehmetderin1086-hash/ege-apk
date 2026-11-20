import Foundation
import Testing
@testable import IETTAsistan

/// Gerçek İETT servisine bağlanır (ağ gerekir). Servis yanıtının biçimi değişirse uygulama bozulmadan önce burada yakalanır.
struct MetroLiveAPITests {
    @Test func metroStationsDecodeFromOfficialService() async throws {
        let snapshot = try await RailStationStore.shared.refresh()
        #expect(snapshot.stations.count > 100)
        #expect(snapshot.stations.contains { $0.LineName == "M2" && $0.coordinate != nil })
        #expect(snapshot.stations.contains { $0.LineName == "T1" })
        #expect(await RailStationStore.shared.cached()?.stations.count == snapshot.stations.count)
        let statuses = try await RailStationStore.shared.serviceStatuses()
        #expect(statuses.allSatisfy { !$0.LineName.isEmpty && !$0.Description.isEmpty })
    }
}

struct LiveAPITests {
    @Test func linesStopsBusesTimetableAndNoticesDecode() async throws {
        let client = IETTClient()
        let lines = try await client.lines()
        #expect(lines.count > 500 && lines.contains { $0.code == "500T" })
        let cache = URL.temporaryDirectory.appending(path: "durak-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cache) }
        let stops = try await client.stops(cache: cache)
        #expect(stops.count > 10_000)
        #expect(stops.allSatisfy { (40.0...42.5).contains($0.lat) && (27.5...30.5).contains($0.lon) })
        // Disk önbelleği aynı veriyi geri verir.
        #expect(try await client.stops(cache: cache).count == stops.count)
        let trips = try await client.timetable(line: "500T")
        #expect(!trips.isEmpty && trips.allSatisfy { $0.time.contains(":") })
        #expect(!Timetable.departures(trips, direction: "G").isEmpty)
        let buses = try await client.buses(line: "500T")
        #expect(buses.allSatisfy { $0.line == "500T" && !$0.direction.isEmpty })
        _ = try await client.notices()
        // Bilinmeyen hat sunucu hatası yerine boş liste vermeli ya da anlaşılır hata fırlatmalı.
        do { _ = try await client.buses(line: "YOKHAT") } catch { #expect(error is IETTError) }
    }
    @Test func liveRouteHasOrderedStopsOnBothDirectionsAndFeedsEngine() async throws {
        let route = try await IETTClient().route(line: "500T")
        #expect(route.directions.count == 2)
        for direction in route.directions {
            let stops = try #require(route.stops[direction])
            #expect(stops.count > 30 && stops.map(\.seq) == stops.map(\.seq).sorted() && !route.destination(direction).isEmpty)
        }
        // Gerçek canlı araçlar: son durağa kalan yol hattın uzunluğundan büyük olamaz.
        let buses = try await IETTClient().buses(line: "500T")
        for direction in route.directions {
            let last = try #require(route.stops[direction]?.last)
            let geometry = RouteGeometry(stops: route.stops[direction]!)
            for eta in RouteETAEngine.etas(buses: buses, route: route, stopCode: last.code, tracker: LiveTracker()) { #expect(eta.distance <= geometry.length + 100) }
        }
    }
    @MainActor @Test func assistantAnswersFromLiveData() async throws {
        let model = AppModel(); await model.load()
        #expect(model.lines.count > 500 && model.stops.count > 10_000)
        let brain = TransitBrain(model: model)
        let status = await brain.lineStatus("500t")
        #expect(status.contains("500T") && status.contains("TUZLA"), "\(status)")
        #expect(model.searchStops("kadıköy çarşı").first?.name == "KADIKÖY ÇARŞI")
        #expect(model.searchStops("ihsaniye iskele").first?.district == "Üsküdar")   // aksan/büyük harf duyarsız
        #expect(brain.findLines("tuzla").contains("500T"))
    }
}
