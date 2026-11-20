import XCTest
@testable import Ritim

final class SmartCollectionsTests: XCTestCase {
    func testCollectionsUpdateFromLibraryStateAndExcludeVideoAndFutureDates() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var unheard = MediaTrack(title: "Yeni", fileName: "one.m4a")
        unheard.addedAt = now.addingTimeInterval(-60)
        var oldFavorite = MediaTrack(title: "Eski", fileName: "two.m4a")
        oldFavorite.addedAt = now.addingTimeInterval(-90 * 86_400)
        oldFavorite.isFavorite = true
        oldFavorite.playCount = 4
        oldFavorite.lastPlayedAt = now.addingTimeInterval(-15 * 86_400)
        var recentFavorite = oldFavorite
        recentFavorite.id = UUID(); recentFavorite.title = "Bugün"
        recentFavorite.lastPlayedAt = now.addingTimeInterval(-30)
        var video = unheard
        video.id = UUID(); video.kind = .video
        var future = unheard
        future.id = UUID(); future.addedAt = now.addingTimeInterval(60)
        let library = [oldFavorite, unheard, recentFavorite, video, future]
        XCTAssertEqual(SmartCollection.recent.tracks(in: library, now: now).map(\.id), [unheard.id])
        XCTAssertEqual(SmartCollection.rediscover.tracks(in: library, now: now).map(\.id), [oldFavorite.id])
        XCTAssertEqual(SmartCollection.history.tracks(in: library, now: now).map(\.id), [recentFavorite.id, oldFavorite.id])
        XCTAssertEqual(Set(SmartCollection.unheard.tracks(in: library, now: now).map(\.id)), Set([unheard.id, future.id]))
        unheard.playCount = 1
        unheard.lastPlayedAt = now
        XCTAssertTrue(SmartCollection.unheard.tracks(in: [unheard], now: now).isEmpty)
        oldFavorite.isFavorite = false
        XCTAssertTrue(SmartCollection.rediscover.tracks(in: [oldFavorite], now: now).isEmpty)
    }
}
