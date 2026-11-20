import XCTest
@testable import Ritim

@MainActor
final class ListeningStoreTests: XCTestCase {
    private final class Clock {
        var date: Date
        var uptime: TimeInterval = 100
        init(_ date: Date) { self.date = date }
        func advance(_ seconds: TimeInterval) {
            date = date.addingTimeInterval(seconds)
            uptime += seconds
        }
    }

    private func workspace() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ListeningTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func calendar(_ zone: String = "Europe/Istanbul") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    private func store(_ directory: URL, clock: Clock, calendar: Calendar? = nil) -> ListeningStore {
        ListeningStore(directory: directory, calendar: calendar ?? self.calendar(),
                       now: { clock.date }, uptime: { clock.uptime })
    }

    func testOnlyActualPlayingCountsAcrossPauseBufferAndTrackChange() throws {
        let clock = Clock(date("2026-10-26T12:00:00Z"))
        let store = store(try workspace(), clock: clock)
        let first = UUID(), second = UUID()
        store.updatePlayback(trackID: first, isPlaying: false)
        clock.advance(20)
        store.tick()
        XCTAssertTrue(store.days.isEmpty)
        store.updatePlayback(trackID: first, isPlaying: true)
        clock.advance(10)
        store.tick()
        clock.advance(2)
        store.updatePlayback(trackID: first, isPlaying: false) // pause or buffering
        clock.advance(20)
        store.tick()
        XCTAssertEqual(store.totalSeconds(days: 1, now: clock.date), 12, accuracy: 0.001)
        store.updatePlayback(trackID: first, isPlaying: true)
        clock.advance(7)
        store.updatePlayback(trackID: second, isPlaying: true)
        clock.advance(4)
        store.updatePlayback(trackID: nil, isPlaying: false)
        clock.advance(20)
        store.tick()
        let day = try XCTUnwrap(store.days.first)
        XCTAssertEqual(day.seconds, 23, accuracy: 0.001)
        XCTAssertEqual(day.trackSeconds[first.uuidString], 19)
        XCTAssertEqual(day.trackSeconds[second.uuidString], 4)
    }

    func testSeekTimeIsExcludedAndMediaPositionCannotInflateListening() throws {
        let clock = Clock(date("2026-10-26T12:00:00Z"))
        let store = store(try workspace(), clock: clock)
        let track = UUID()
        store.updatePlayback(trackID: track, isPlaying: true)
        clock.advance(1)
        // AVPlayer may report playing during a seek; explicit seek suppression still wins.
        store.updatePlayback(trackID: track, isPlaying: true, isSeeking: true)
        clock.advance(40)
        store.tick()
        store.updatePlayback(trackID: track, isPlaying: true)
        clock.advance(2)
        store.updatePlayback(trackID: track, isPlaying: false)
        XCTAssertEqual(store.totalSeconds(days: 1, now: clock.date), 3, accuracy: 0.001)
        // There is deliberately no elapsed-media or playback-rate input to the ledger.
    }

    func testPersistenceIsThrottledAndBackgroundFlushKeepsActivePlayback() throws {
        let directory = try workspace()
        let clock = Clock(date("2026-10-26T12:00:00Z"))
        let store = store(directory, clock: clock)
        store.updatePlayback(trackID: UUID(), isPlaying: true)
        clock.advance(7)
        store.tick()
        clock.advance(7)
        store.tick()
        let file = directory.appendingPathComponent("listening.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        clock.advance(1)
        store.tick()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        clock.advance(3)
        store.flush() // Entering background persists, but audio may keep playing.
        XCTAssertEqual(self.store(directory, clock: clock).totalSeconds(days: 1, now: clock.date), 18, accuracy: 0.001)
        clock.advance(5)
        store.flush()
        let reloaded = self.store(directory, clock: clock)
        XCTAssertEqual(reloaded.totalSeconds(days: 1, now: clock.date), 23, accuracy: 0.001)
        clock.advance(100)
        reloaded.tick() // Restart does not inherit a stale active session.
        XCTAssertEqual(reloaded.totalSeconds(days: 1, now: clock.date), 23, accuracy: 0.001)
    }

    func testLocalMidnightSplitsDurationAndZeroFillsMissingDays() throws {
        let clock = Clock(date("2026-10-26T20:59:55Z")) // 23:59:55 Istanbul
        let store = store(try workspace(), clock: clock)
        store.updatePlayback(trackID: UUID(), isPlaying: true)
        clock.advance(10)
        store.updatePlayback(trackID: nil, isPlaying: false)
        let days = store.recentDays(count: 7, now: clock.date)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.prefix(5).map(\.seconds), [0, 0, 0, 0, 0])
        XCTAssertEqual(days[5].seconds, 5, accuracy: 0.001)
        XCTAssertEqual(days[6].seconds, 5, accuracy: 0.001)
        XCTAssertEqual(store.totalSeconds(days: 1, now: clock.date), 5, accuracy: 0.001)
        XCTAssertEqual(store.totalSeconds(days: 7, now: clock.date), 10, accuracy: 0.001)
        XCTAssertTrue(store.recentDays(count: 0, now: clock.date).isEmpty)
    }

    func testDaylightSavingUsesCalendarBoundariesInsteadOfTwentyFourHours() throws {
        let zone = calendar("America/New_York")
        let clock = Clock(date("2026-03-09T03:59:55Z")) // 23:59:55 at the end of the 23-hour day.
        let store = store(try workspace(), clock: clock, calendar: zone)
        store.updatePlayback(trackID: UUID(), isPlaying: true)
        clock.advance(10)
        store.updatePlayback(trackID: nil, isPlaying: false)
        let days = store.recentDays(count: 2, now: clock.date)
        XCTAssertEqual(days[0].seconds, 5, accuracy: 0.001)
        XCTAssertEqual(days[1].seconds, 5, accuracy: 0.001)
        XCTAssertEqual(days[1].dayStart.timeIntervalSince(days[0].dayStart), 23 * 3600, accuracy: 0.001)
    }

    func testLongUnobservedGapCannotCountDelayedPauseOrProcessSuspension() throws {
        let clock = Clock(date("2026-10-26T12:00:00Z"))
        let store = store(try workspace(), clock: clock)
        let track = UUID()
        store.updatePlayback(trackID: track, isPlaying: true)
        clock.advance(5)
        store.tick()
        clock.advance(120)
        store.tick() // No heartbeats: whether the player remained playing is unknown.
        clock.advance(3)
        store.updatePlayback(trackID: track, isPlaying: false)
        XCTAssertEqual(store.totalSeconds(days: 1, now: clock.date), 8, accuracy: 0.001)
    }

    func testWallClockAdjustmentDoesNotAddListeningHours() throws {
        let clock = Clock(date("2026-10-26T12:00:00Z"))
        let store = store(try workspace(), clock: clock)
        store.updatePlayback(trackID: UUID(), isPlaying: true)
        clock.advance(10)
        clock.date = clock.date.addingTimeInterval(7200)
        store.tick()
        clock.advance(5)
        clock.date = clock.date.addingTimeInterval(-10800)
        store.updatePlayback(trackID: nil, isPlaying: false)
        XCTAssertEqual(store.totalSeconds(days: 1, now: clock.date), 15, accuracy: 0.001)
    }

    func testRetentionPrunesOldDaysAndRemainsBoundedAfterLongInterval() throws {
        let directory = try workspace()
        let clock = Clock(date("2025-01-01T12:00:00Z"))
        let store = store(directory, clock: clock)
        store.updatePlayback(trackID: UUID(), isPlaying: true)
        clock.advance(1)
        store.updatePlayback(trackID: nil, isPlaying: false)
        clock.advance(367 * 24 * 3600)
        store.updatePlayback(trackID: UUID(), isPlaying: true)
        clock.advance(2)
        store.updatePlayback(trackID: nil, isPlaying: false)
        XCTAssertEqual(store.days.count, 1)
        XCTAssertEqual(store.days.first?.seconds, 2)
        XCTAssertEqual(store.recentDays(count: 1000, now: clock.date).count, 366)
        XCTAssertEqual(self.store(directory, clock: clock).days.count, 1)
    }

    func testUnreadableStateIsPreservedBeforeNewHistoryIsWritten() throws {
        let directory = try workspace()
        let original = Data("broken history, preserve me".utf8)
        let file = directory.appendingPathComponent("listening.json")
        try original.write(to: file)
        let clock = Clock(date("2026-10-26T12:00:00Z"))
        let store = store(directory, clock: clock)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.days.isEmpty)
        store.updatePlayback(trackID: UUID(), isPlaying: true)
        clock.advance(5)
        store.updatePlayback(trackID: nil, isPlaying: false)
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix("listening-corrupt-") })
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertEqual(self.store(directory, clock: clock).totalSeconds(days: 1, now: clock.date), 5, accuracy: 0.001)
    }

    func testSeparateLibraryDirectoriesNeverShareListeningHistory() throws {
        let clock = Clock(date("2026-10-26T12:00:00Z"))
        let first = store(try workspace(), clock: clock)
        let second = store(try workspace(), clock: clock)
        first.updatePlayback(trackID: UUID(), isPlaying: true)
        clock.advance(9)
        first.flush()
        XCTAssertEqual(first.totalSeconds(days: 1, now: clock.date), 9, accuracy: 0.001)
        XCTAssertEqual(second.totalSeconds(days: 1, now: clock.date), 0)
    }
}
