import Foundation
import Testing
@testable import IETTAsistan

struct WidgetDataTests {
    @Test func favoritesRoundTripThroughSharedDefaultsAndOldFieldsStillDecode() throws {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let list = [Favorite(line: "500T", stopCode: 301341, stopName: "4.LEVENT METRO", lat: 41.08, lon: 29.0, alertMinutes: 5)]
        SharedStore.save(list, to: defaults)
        #expect(SharedStore.loadFavorites(from: defaults) == list)
        // alertMinutes alanı olmayan eski kayıt okunabilmeli.
        let old = Data(#"[{"line":"14M","stopCode":1,"stopName":"X","lat":41,"lon":29}]"#.utf8)
        #expect(try JSONDecoder().decode([Favorite].self, from: old).first?.alertMinutes == nil)
    }
    @Test func snapshotLoadsLiveDataForARealRouteStop() async throws {
        let folder = URL.temporaryDirectory.appending(path: "w-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RouteStore(folder: folder)
        let route = try await store.route("500T")
        let stop = try #require(route.stops[route.directions[0]]?.last)
        let favorite = Favorite(line: "500T", stopCode: stop.code, stopName: stop.name, lat: stop.lat, lon: stop.lon)
        let rows = await FavoriteSnapshot.load([favorite], store: store)
        #expect(rows.count == 1 && rows[0].favorite == favorite)
        if let eta = rows[0].eta { #expect(eta.minutes >= 0 && eta.minutes < 600) }
    }
}
