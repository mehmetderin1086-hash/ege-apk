import XCTest
import AVFoundation
import UIKit
@testable import Ritim

@MainActor
final class PlaybackTests: XCTestCase {
    func testLoopCyclesAndSleepAtTrackEndStopsInsteadOfAdvancing() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        let tracks = fixture.library.tracks
        let playback = fixture.playback
        tracks.forEach { playback.enqueue($0) }
        playback.cycleLoop()
        XCTAssertEqual(playback.loopStart, 0)
        XCTAssertNil(playback.loopEnd, "Aynı noktada B işaretlenmemeli")
        playback.cycleLoop()
        XCTAssertNil(playback.loopStart, "Geçersiz B, döngüyü temizlemeli")
        playback.cycleLoop()
        playback.next()
        XCTAssertNil(playback.loopStart, "Parça değişince döngü sıfırlanmalı")

        let second = playback.current?.id
        playback.setSleepAtTrackEnd(true)
        XCTAssertTrue(playback.sleepAtTrackEnd)
        playback.setSleepTimer(minutes: 15)
        XCTAssertFalse(playback.sleepAtTrackEnd, "Saat zamanlayıcısı parça sonu seçimini değiştirmeli")
        playback.setSleepAtTrackEnd(true)
        playback.setSleepAtTrackEnd(false)
        XCTAssertFalse(playback.sleepAtTrackEnd)
        XCTAssertEqual(playback.current?.id, second)
        playback.skip(by: -15)
        XCTAssertEqual(playback.elapsed, 0)
    }

    func testPlayNextMovesExistingEntryWithoutInterruptingAndPersistsShufflePriority() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        let tracks = fixture.library.tracks
        let playback = fixture.playback
        tracks.forEach { playback.enqueue($0) }
        playback.shuffleEnabled = true
        let activeItem = playback.player.currentItem
        playback.enqueueNext(tracks[2])
        XCTAssertEqual(playback.queue.map(\.id), [tracks[0].id, tracks[2].id, tracks[1].id])
        XCTAssertTrue(playback.player.currentItem === activeItem)
        XCTAssertFalse(playback.isPlaying)
        playback.enqueueNext(tracks[2])
        XCTAssertEqual(playback.queue.count, 3)

        let restored = fixture.relaunch()
        XCTAssertFalse(restored.isPlaying)
        restored.next()
        XCTAssertEqual(restored.current?.id, tracks[2].id)
        restored.next()
        XCTAssertEqual(restored.current?.id, tracks[1].id)
    }

    func testEnqueueAtEndMovesAnExistingItemAndNextHandlesEmptyQueue() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        let tracks = fixture.library.tracks
        let playback = fixture.playback
        playback.enqueueNext(tracks[0])
        XCTAssertEqual(playback.current?.id, tracks[0].id)
        XCTAssertFalse(playback.isPlaying)
        playback.enqueue(tracks[1]); playback.enqueue(tracks[2])
        let activeItem = playback.player.currentItem
        playback.enqueue(tracks[1])
        XCTAssertEqual(playback.queue.map(\.id), [tracks[0].id, tracks[2].id, tracks[1].id])
        XCTAssertTrue(playback.player.currentItem === activeItem)
        playback.enqueueNext(tracks[0])
        XCTAssertEqual(playback.queue.count, 3)
        playback.next()
        XCTAssertEqual(playback.current?.id, tracks[2].id)
    }

    func testQueueMovementPreservesSelectionAndDeduplicatesTracks() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        let tracks = fixture.library.tracks
        let player = fixture.playback
        player.play(tracks[0], in: [tracks[0], tracks[1], tracks[0], tracks[2]])
        XCTAssertEqual(player.queue.map(\.id), tracks.map(\.id))

        player.moveQueue(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(player.queue.map(\.id), [tracks[2].id, tracks[0].id, tracks[1].id])
        XCTAssertEqual(player.current?.id, tracks[0].id)
        player.enqueue(tracks[0])
        XCTAssertEqual(player.queue.count, 3)

        // Removing a different item must neither replace the AVPlayer nor restart selection.
        let item = player.player.currentItem
        player.removeFromQueue(at: IndexSet(integer: 0))
        XCTAssertEqual(player.queue.map(\.id), [tracks[0].id, tracks[1].id])
        XCTAssertTrue(player.player.currentItem === item)
    }

    func testRemovingSelectedTrackAdvancesWhilePreservingPauseThenClears() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        let tracks = fixture.library.tracks
        let playback = fixture.playback
        let stablePlayer = playback.player
        playback.play(tracks[1], in: tracks)
        playback.togglePlayPause()
        XCTAssertFalse(playback.isPlaying)

        playback.removeFromQueue(at: IndexSet(integer: 1))
        XCTAssertEqual(playback.current?.id, tracks[2].id)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertTrue(playback.player === stablePlayer)

        // Multi-selection deletion must use the next surviving track, even when
        // earlier rows were removed in the same edit.
        playback.play(tracks[1], in: tracks)
        playback.removeFromQueue(at: IndexSet([0, 1]))
        XCTAssertEqual(playback.current?.id, tracks[2].id)

        playback.removeFromQueue(at: IndexSet(integersIn: 0..<2))
        XCTAssertNil(playback.current)
        XCTAssertTrue(playback.queue.isEmpty)
        XCTAssertNil(playback.player.currentItem)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertTrue(playback.player === stablePlayer)
    }

    func testShuffleVisitsEveryTrackBeforeRepeatAndSupportsBackNavigation() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        let tracks = fixture.library.tracks
        let playback = fixture.playback
        playback.shuffleEnabled = true
        playback.play(tracks[0], in: tracks)
        var visited = [try XCTUnwrap(playback.current?.id)]
        playback.next()
        visited.append(try XCTUnwrap(playback.current?.id))
        playback.next()
        visited.append(try XCTUnwrap(playback.current?.id))
        XCTAssertEqual(Set(visited), Set(tracks.map(\.id)))

        playback.next()
        XCTAssertEqual(playback.current?.id, visited.last)
        XCTAssertFalse(playback.isPlaying, "An exhausted queue with repeat off should pause.")

        playback.cycleRepeatMode()
        XCTAssertEqual(playback.repeatMode, .all)
        playback.next()
        XCTAssertNotEqual(playback.current?.id, visited.last)
        playback.previous()
        XCTAssertEqual(playback.current?.id, visited.last)
    }

    func testRelaunchRestoresQueuePositionAndPreferencesWithoutAutoplay() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        let tracks = fixture.library.tracks
        tracks.forEach { fixture.playback.enqueue($0) }
        fixture.playback.moveQueue(from: IndexSet(integer: 2), to: 0)
        fixture.playback.setRate(1.5)
        fixture.playback.cycleRepeatMode()
        fixture.playback.cycleRepeatMode()
        fixture.playback.shuffleEnabled = true
        // This seek may precede item readiness. It must still be saved immediately.
        fixture.playback.seek(to: 3.5)
        XCTAssertEqual(try fixture.savedPosition(), 3.5, accuracy: 0.01)

        let restored = fixture.relaunch()
        XCTAssertEqual(restored.current?.id, tracks[0].id)
        XCTAssertEqual(restored.queue.map(\.id), [tracks[2].id, tracks[0].id, tracks[1].id])
        XCTAssertEqual(restored.elapsed, 3.5, accuracy: 0.01)
        XCTAssertEqual(restored.playbackRate, 1.5)
        XCTAssertEqual(restored.repeatMode, .one)
        XCTAssertTrue(restored.shuffleEnabled)
        XCTAssertFalse(restored.isPlaying)
        XCTAssertEqual(restored.player.rate, 0)

        try await waitUntil { abs(restored.player.currentTime().seconds - 3.5) < 0.05 }
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(restored.elapsed, 3.5, accuracy: 0.05)
        XCTAssertEqual(try fixture.savedPosition(), 3.5, accuracy: 0.05)
        XCTAssertEqual(restored.player.rate, 0)
        XCTAssertFalse(restored.isPlaying)
        XCTAssertTrue(fixture.library.tracks.allSatisfy { $0.playCount == 0 })
    }

    func testRapidSeeksPreserveTheLatestPositionAcrossRelaunch() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        fixture.playback.enqueue(fixture.library.tracks[0])
        fixture.playback.seek(to: 6)
        fixture.playback.seek(to: 1)
        fixture.playback.seek(to: 4.25)
        XCTAssertEqual(try fixture.savedPosition(), 4.25, accuracy: 0.01)

        let restored = fixture.relaunch()
        XCTAssertEqual(restored.elapsed, 4.25, accuracy: 0.01)
        try await waitUntil { abs(restored.player.currentTime().seconds - 4.25) < 0.05 }
        restored.seek(to: 7)
        restored.seek(to: 2)
        restored.seek(to: 5.25)
        try await waitUntil { abs(restored.player.currentTime().seconds - 5.25) < 0.05 }
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(restored.elapsed, 5.25, accuracy: 0.05)
        XCTAssertEqual(try fixture.savedPosition(), 5.25, accuracy: 0.05)
        XCTAssertFalse(restored.isPlaying)

        // Native VideoPlayer transport controls seek directly on the shared AVPlayer.
        let completed = await restored.player.seek(to: CMTime(seconds: 1.25, preferredTimescale: 600),
                                                   toleranceBefore: .zero, toleranceAfter: .zero)
        XCTAssertTrue(completed)
        try await waitUntil { abs(((try? fixture.savedPosition()) ?? -1) - 1.25) < 0.05 }
    }

    func testRelaunchPreservesShuffleHistoryAndUnplayedTracks() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        let tracks = fixture.library.tracks
        tracks.forEach { fixture.playback.enqueue($0) }
        fixture.playback.shuffleEnabled = true
        fixture.playback.next()
        fixture.playback.togglePlayPause()
        let second = try XCTUnwrap(fixture.playback.current?.id)
        let third = try XCTUnwrap(tracks.first { $0.id != tracks[0].id && $0.id != second }?.id)

        let restored = fixture.relaunch()
        XCTAssertFalse(restored.isPlaying)
        restored.previous()
        XCTAssertEqual(restored.current?.id, tracks[0].id)
        restored.next()
        XCTAssertEqual(restored.current?.id, second)
        restored.next()
        XCTAssertEqual(restored.current?.id, third)
        restored.next()
        XCTAssertFalse(restored.isPlaying, "Relaunch must not refill the consumed shuffle bag.")
        XCTAssertEqual(restored.current?.id, third)
    }

    func testRelaunchSkipsDeletedAndUnavailableTracksAndResetsReplacementPosition() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        let tracks = fixture.library.tracks
        fixture.playback.play(tracks[1], in: tracks)
        fixture.playback.togglePlayPause()
        fixture.playback.seek(to: 5)
        try FileManager.default.removeItem(at: fixture.library.url(for: tracks[1]))
        fixture.library.delete(tracks[0])

        let restored = fixture.relaunch()
        XCTAssertEqual(restored.queue.map(\.id), [tracks[2].id])
        XCTAssertEqual(restored.current?.id, tracks[2].id)
        XCTAssertEqual(restored.elapsed, 0)
        XCTAssertFalse(restored.isPlaying)
        XCTAssertEqual(restored.player.rate, 0)
    }

    func testUnavailableLibraryDoesNotReplaceTheSavedSession() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        fixture.playback.enqueue(fixture.library.tracks[0])
        fixture.playback.seek(to: 4)
        let saved = try Data(contentsOf: fixture.sessionURL)
        let libraryURL = fixture.directory.appendingPathComponent("library.json")
        try Data("damaged library".utf8).write(to: libraryURL)
        let unavailable = LibraryStore(directory: fixture.library.directory, seed: false)
        XCTAssertNotNil(unavailable.errorMessage)

        let restored = fixture.relaunch(library: unavailable)
        XCTAssertNil(restored.current)
        XCTAssertTrue(restored.queue.isEmpty)
        XCTAssertFalse(restored.isPlaying)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(try Data(contentsOf: fixture.sessionURL), saved)
    }

    func testCorruptSessionsArePreservedBeforeSavingANewSession() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        let damaged = Data("not a playback session".utf8)
        try damaged.write(to: fixture.sessionURL)
        let restored = fixture.relaunch()
        XCTAssertNil(restored.current)
        XCTAssertFalse(restored.isPlaying)
        XCTAssertNotNil(restored.errorMessage)
        XCTAssertEqual(try Data(contentsOf: fixture.sessionURL), damaged)
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix("playback-session-corrupt-") })
        XCTAssertEqual(try Data(contentsOf: backup), damaged)

        restored.enqueue(fixture.library.tracks[0])
        XCTAssertEqual(try fixture.savedPosition(), 0)
        XCTAssertEqual(try Data(contentsOf: backup), damaged)
        restored.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.sessionURL.path))
        XCTAssertEqual(try Data(contentsOf: backup), damaged)
        XCTAssertNil(fixture.relaunch().current)
    }

    func testPlaybackCheckpointsAreThrottledAndPauseAndBackgroundFlushImmediately() async throws {
        let clock = Clock()
        let fixture = try await Fixture(uptime: { clock.time })
        defer { fixture.cleanUp() }
        fixture.playback.play(fixture.library.tracks[0], in: fixture.library.tracks)
        // The library publishes playCount before its queued playback subscriber
        // refreshes current and force-saves the session. Capture after that save.
        try await waitUntil { fixture.playback.elapsed > 0.25 && (fixture.playback.current?.playCount ?? 0) > 0 }
        let saved = try Data(contentsOf: fixture.sessionURL)
        clock.time += 5
        let firstPosition = fixture.playback.elapsed
        try await waitUntil { fixture.playback.elapsed > firstPosition + 0.6 }
        XCTAssertEqual(try Data(contentsOf: fixture.sessionURL), saved, "Ordinary heartbeats must not write every half second.")

        clock.time += 5
        try await waitUntil { (try? Data(contentsOf: fixture.sessionURL)) != saved }
        fixture.playback.togglePlayPause()
        XCTAssertFalse(fixture.playback.isPlaying)
        XCTAssertEqual(try fixture.savedPosition(), fixture.playback.player.currentTime().seconds, accuracy: 0.05)

        let pausedPosition = try fixture.savedPosition()
        fixture.playback.togglePlayPause()
        try await waitUntil { fixture.playback.elapsed > pausedPosition + 0.6 }
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        try await waitUntil { ((try? fixture.savedPosition()) ?? 0) > pausedPosition + 0.5 }
        XCTAssertTrue(fixture.playback.isPlaying, "A background checkpoint must leave background audio playing.")
        let restored = fixture.relaunch()
        XCTAssertGreaterThan(restored.elapsed, pausedPosition + 0.5)
        XCTAssertFalse(restored.isPlaying)
    }

    func testInterruptionResumesAfterSystemPauseButRespectsUserPause() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        let playback = fixture.playback
        playback.play(fixture.library.tracks[0], in: fixture.library.tracks)
        try await waitUntil { playback.player.timeControlStatus == .playing && playback.elapsed > 0.3 }
        // AVPlayer may report the system's pause before the interruption arrives.
        playback.player.pause()
        try await waitUntil { !playback.isPlaying }
        playback.handleInterruption(.began)
        playback.handleInterruption(.ended, options: .shouldResume)
        try await waitUntil { playback.player.timeControlStatus == .playing }

        playback.handleInterruption(.began)
        playback.togglePlayPause() // User cancels the automatic resume.
        playback.handleInterruption(.ended, options: .shouldResume)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.player.rate, 0)
    }

    func testNativeVideoPauseIsNotAutomaticallyResumedAfterInterruption() async throws {
        let fixture = try await Fixture(videoFirst: true)
        defer { fixture.cleanUp() }
        let video = fixture.library.tracks[0]
        let playback = fixture.playback
        playback.play(video, in: [video])
        try await waitUntil { playback.player.timeControlStatus == .playing && playback.elapsed > 0.3 }
        playback.player.pause()
        try await waitUntil { !playback.isPlaying }
        playback.handleInterruption(.began)
        playback.handleInterruption(.ended, options: .shouldResume)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(playback.player.rate, 0)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(4)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), "Timed out waiting for the local player.", file: file, line: line)
    }

    @MainActor
    private final class Clock { var time: TimeInterval = 100 }

    /// Tests exercise real local AVPlayerItems. Each test has an isolated persisted library.
    @MainActor
    private final class Fixture {
        let directory: URL
        let library: LibraryStore
        var playback: PlaybackStore
        let uptime: () -> TimeInterval
        var sessionURL: URL { directory.appendingPathComponent("playback-session.json") }

        init(uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, videoFirst: Bool = false) async throws {
            self.uptime = uptime
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("PlaybackTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let source = directory.appendingPathComponent("silence.wav")
            try Self.wav().write(to: source)
            let setup = LibraryStore(directory: directory.appendingPathComponent("Media", isDirectory: true), seed: false)
            for name in ["A", "B", "C"] {
                _ = try await setup.importDownloadedFile(source, title: name, artist: "Test", sourceURL: nil)
            }
            if videoFirst {
                let stateURL = directory.appendingPathComponent("library.json")
                var state = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any])
                var savedTracks = try XCTUnwrap(state["tracks"] as? [[String: Any]])
                savedTracks[0]["kind"] = "video"
                state["tracks"] = savedTracks
                try JSONSerialization.data(withJSONObject: state).write(to: stateURL, options: .atomic)
            }
            library = videoFirst ? LibraryStore(directory: setup.directory, seed: false) : setup
            playback = PlaybackStore(library: library, uptime: uptime)
            playback.player.volume = 0
        }

        func relaunch(library replacement: LibraryStore? = nil) -> PlaybackStore {
            // Releasing the old store models process exit without calling explicit stop,
            // which intentionally clears the user's saved session.
            playback = PlaybackStore(library: replacement ?? library, uptime: uptime)
            playback.player.volume = 0
            return playback
        }

        func savedPosition() throws -> Double {
            let state = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: sessionURL)) as? [String: Any])
            return try XCTUnwrap(state["elapsed"] as? Double)
        }

        func cleanUp() {
            playback.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        private static func wav() -> Data {
            let sampleRate: UInt32 = 8_000
            let byteCount = sampleRate * 2 * 8
            var data = Data()
            func text(_ string: String) { data.append(contentsOf: string.utf8) }
            func number<T: FixedWidthInteger>(_ value: T) {
                var littleEndian = value.littleEndian
                withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
            }
            text("RIFF"); number(UInt32(36) + byteCount); text("WAVE")
            text("fmt "); number(UInt32(16)); number(UInt16(1)); number(UInt16(1))
            number(sampleRate); number(sampleRate * 2); number(UInt16(2)); number(UInt16(16))
            text("data"); number(byteCount)
            data.append(Data(repeating: 0, count: Int(byteCount)))
            return data
        }
    }
}

extension PlaybackTests {
    func testStallMonitorOnlyRetriesOnceAndIgnoresIntentionalPause() {
        var monitor = PlaybackStallMonitor()
        let track = UUID()
        XCTAssertEqual(monitor.sample(track: track, position: 5, now: 0, eligible: true), .none)
        XCTAssertEqual(monitor.sample(track: track, position: 5, now: 11, eligible: false), .none)
        XCTAssertEqual(monitor.sample(track: track, position: 5, now: 12, eligible: true), .none)
        XCTAssertEqual(monitor.sample(track: track, position: 5, now: 23, eligible: true), .recover)
        XCTAssertEqual(monitor.sample(track: track, position: 5, now: 34, eligible: true), .stop)
        XCTAssertEqual(monitor.sample(track: UUID(), position: 0, now: 35, eligible: true), .none)
    }
}
