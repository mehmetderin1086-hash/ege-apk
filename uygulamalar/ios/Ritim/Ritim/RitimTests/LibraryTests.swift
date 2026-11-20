import XCTest
@testable import Ritim

@MainActor
final class LibraryTests: XCTestCase {
    private func workspace() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        return base
    }
    func testRealMediaImportPersistencePlaylistAndDeletion() async throws {
        let base = try workspace()
        let library = LibraryStore(directory: base.appendingPathComponent("Media"), seed: false)
        let source = try XCTUnwrap(Bundle.main.url(forResource: "gece-yolu", withExtension: "m4a"))
        let track = try await library.importDownloadedFile(source, title: "Test", artist: "Ritim", sourceURL: nil)
        XCTAssertGreaterThan(track.duration, 30)
        XCTAssertGreaterThan(track.fileSize, 0)
        XCTAssertEqual(track.kind, .audio)
        library.toggleFavorite(track)
        library.createPlaylist(name: "Yolculuk")
        let playlist = try XCTUnwrap(library.playlists.first)
        library.add(track, to: playlist); library.add(track, to: playlist)
        XCTAssertEqual(library.tracks(in: playlist).count, 1)
        let reloaded = LibraryStore(directory: base.appendingPathComponent("Media"), seed: false)
        XCTAssertEqual(reloaded.tracks.count, 1)
        XCTAssertTrue(try XCTUnwrap(reloaded.tracks.first).isFavorite)
        XCTAssertEqual(reloaded.tracks(in: playlist).count, 1)
        reloaded.delete(track)
        XCTAssertTrue(reloaded.tracks.isEmpty)
        XCTAssertTrue(reloaded.tracks(in: playlist).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reloaded.url(for: track).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testBatchAddPreservesOrderDeduplicatesAndKeepsPendingDownloadSlots() throws {
        let base = try workspace()
        let library = LibraryStore(directory: base.appendingPathComponent("Media"))
        let tracks = library.tracks
        XCTAssertGreaterThanOrEqual(tracks.count, 3)
        let playlist = try library.createPlaylist(name: "Toplu", trackIDs: [tracks[0].id])
        let pendingID = UUID()
        try library.reserveDownloadOrder([PlaylistDownloadSlot(entryID: pendingID)], in: playlist.id)
        XCTAssertTrue(library.add([tracks[2], tracks[0], tracks[1], tracks[2]], to: playlist))
        let reloaded = LibraryStore(directory: base.appendingPathComponent("Media"), seed: false)
        let saved = try XCTUnwrap(reloaded.playlists.first { $0.id == playlist.id })
        XCTAssertEqual(saved.trackIDs, [tracks[0].id, tracks[2].id, tracks[1].id])
        XCTAssertTrue(saved.downloadOrder?.contains { $0.entryID == pendingID } == true)
    }
    func testCancelledImportPreservesReservedPlaylistSlotAndRemovesOnlyNewCopy() async throws {
        let base = try workspace()
        let library = LibraryStore(directory: base.appendingPathComponent("Media"), seed: false)
        let source = try XCTUnwrap(Bundle.main.url(forResource: "gece-yolu", withExtension: "m4a"))
        library.createPlaylist(name: "Bekleyen indirme")
        let playlist = try XCTUnwrap(library.playlists.first)
        let entryID = UUID()
        try library.reserveDownloadOrder([PlaylistDownloadSlot(entryID: entryID)], in: playlist.id)
        let before = try Data(contentsOf: base.appendingPathComponent("library.json"))
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await library.importDownloadedFile(source, title: "İptal", artist: nil, sourceURL: nil,
                                                          downloadEntryID: entryID, playlistIDs: [playlist.id])
        }
        do { _ = try await task.value; XCTFail("Cancelled import must not commit") } catch { }
        XCTAssertTrue(library.tracks.isEmpty)
        XCTAssertEqual(try Data(contentsOf: base.appendingPathComponent("library.json")), before)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: library.directory.path).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testInvalidMediaRollsBackFilesAndState() async throws {
        let base = try workspace()
        let source = base.appendingPathComponent("invalid.mp3")
        try Data("<html>not media</html>".utf8).write(to: source)
        let library = LibraryStore(directory: base.appendingPathComponent("Media"), seed: false)
        do { _ = try await library.importDownloadedFile(source, title: nil, artist: nil, sourceURL: nil); XCTFail("Invalid file accepted") } catch { }
        XCTAssertTrue(library.tracks.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: library.directory.path).isEmpty)
    }
    func testDamagedLibraryIsPreserved() throws {
        let base = try workspace()
        let state = base.appendingPathComponent("library.json")
        let invalid = Data("incomplete".utf8)
        try invalid.write(to: state)
        let library = LibraryStore(directory: base.appendingPathComponent("Media"), seed: false)
        XCTAssertNotNil(library.errorMessage)
        XCTAssertEqual(try Data(contentsOf: state), invalid)
        library.createPlaylist(name: "Must not overwrite damaged state")
        XCTAssertEqual(try Data(contentsOf: state), invalid)
        XCTAssertTrue(library.playlists.isEmpty)
    }
    func testURLValidationDoesNotTrustHostSubstringsOrUnsafeSchemes() throws {
        XCTAssertTrue(MediaURLPolicy.isYouTube(try XCTUnwrap(URL(string: "https://youtu.be/BaW_jenozKc"))))
        XCTAssertFalse(MediaURLPolicy.isYouTube(try XCTUnwrap(URL(string: "https://youtube.com.evil.invalid/test.mp4"))))
        for input in ["file:///private/test.mp3", "http://example.com/test.mp3", "https://user:secret@example.com/test.mp3", "https://example.com/page"] {
            XCTAssertThrowsError(try MediaURLPolicy.validatedInput(input), input)
        }
        XCTAssertNoThrow(try MediaURLPolicy.validatedInput("https://example.com/song.mp3?download=1"))
        XCTAssertThrowsError(try MediaURLPolicy.validatedServer("http://example.com:8765"))
        XCTAssertThrowsError(try MediaURLPolicy.validatedServer("http://192.168.999.5:8765"))
        XCTAssertThrowsError(try MediaURLPolicy.validatedServer("http://10.0.0.1.example.com:8765"))
        XCTAssertThrowsError(try MediaURLPolicy.validatedServer("http://192.foo.168.1.2.example:8765"))
        XCTAssertNoThrow(try MediaURLPolicy.validatedServer("http://Mac.local:8765"))
        XCTAssertNoThrow(try MediaURLPolicy.validatedServer("https://music.example.com"))
    }
}

extension LibraryTests {
    func testBackupRoundTripIsIdempotentAndPreservesExistingLibrary() async throws {
        let base = try workspace()
        let original = LibraryStore(directory: base.appendingPathComponent("source/Media"), seed: false)
        let source = try XCTUnwrap(Bundle.main.url(forResource: "gece-yolu", withExtension: "m4a"))
        let track = try await original.importDownloadedFile(source, title: "Yedek", artist: "Ritim", sourceURL: nil)
        original.setFavorites([track.id], value: true)
        let playlist = try original.createPlaylist(name: "Sabit", trackIDs: [track.id])
        original.togglePinned(playlist)
        let backup = try await original.exportBackup(includeMedia: true)
        defer { try? FileManager.default.removeItem(at: backup) }
        let restored = LibraryStore(directory: base.appendingPathComponent("target/Media"), seed: false)
        let firstCount = try await restored.restoreBackup(backup)
        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(restored.tracks.first?.id, track.id)
        XCTAssertEqual(restored.tracks.first?.isFavorite, true)
        XCTAssertEqual(restored.playlists.first?.isPinned, true)
        XCTAssertEqual(restored.playlists.first?.trackIDs, [track.id])
        let secondCount = try await restored.restoreBackup(backup)
        XCTAssertEqual(secondCount, 0)
        XCTAssertEqual(restored.tracks.count, 1)
        XCTAssertEqual(restored.playlists.count, 1)
        let reload = LibraryStore(directory: base.appendingPathComponent("target/Media"), seed: false)
        XCTAssertEqual(reload.tracks, restored.tracks)
    }

    func testCorruptBackupDoesNotChangeLibrary() async throws {
        let base = try workspace()
        let library = LibraryStore(directory: base.appendingPathComponent("Media"), seed: false)
        let source = try XCTUnwrap(Bundle.main.url(forResource: "gece-yolu", withExtension: "m4a"))
        _ = try await library.importDownloadedFile(source, title: "Korunacak", artist: "Ritim", sourceURL: nil)
        let before = library.tracks
        let backup = try await library.exportBackup(includeMedia: true)
        defer { try? FileManager.default.removeItem(at: backup) }
        var data = try Data(contentsOf: backup)
        data[data.count - 1] ^= 0xff
        try data.write(to: backup)
        do { _ = try await library.restoreBackup(backup); XCTFail("Corrupt digest must fail") }
        catch { XCTAssertEqual(library.tracks, before) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.url(for: before[0]).path))
    }

    func testMetadataBackupNeverCreatesMissingMedia() async throws {
        let base = try workspace()
        let source = LibraryStore(directory: base.appendingPathComponent("source/Media"), seed: true)
        let backup = try await source.exportBackup(includeMedia: false)
        defer { try? FileManager.default.removeItem(at: backup) }
        let target = LibraryStore(directory: base.appendingPathComponent("target/Media"), seed: false)
        let count = try await target.restoreBackup(backup)
        XCTAssertEqual(count, 0)
        XCTAssertTrue(target.tracks.isEmpty)
    }

    func testTurkishMultiWordSearchAndBatchFavorites() throws {
        let base = try workspace()
        let library = LibraryStore(directory: base.appendingPathComponent("Media"), seed: true)
        let ids = Set(library.tracks.map(\.id))
        library.setFavorites(ids, value: true)
        XCTAssertTrue(library.tracks.allSatisfy(\.isFavorite))
        library.setFavorites(ids, value: false)
        XCTAssertTrue(library.tracks.allSatisfy { !$0.isFavorite })
        var track = MediaTrack(title: "IŞIK", artist: "Şebnem", fileName: "test.mp3")
        track.album = "İstanbul"
        XCTAssertTrue(LibrarySearch.matches(track, query: "isik sebnem istanbul"))
        XCTAssertFalse(LibrarySearch.matches(track, query: "isik başka"))
    }
}

extension LibraryTests {
    func testBatchMetadataAndPlaylistDetailsSurviveReload() throws {
        let base = try workspace()
        let library = LibraryStore(directory: base.appendingPathComponent("Media"), seed: true)
        let original = try XCTUnwrap(library.tracks.first)
        library.updateMetadata([original.id], artist: "", album: "Yeni albüm")
        XCTAssertEqual(library.tracks.first?.artist, original.artist)
        XCTAssertEqual(library.tracks.first?.album, "Yeni albüm")
        let playlist = try library.createPlaylist(name: "Önce", trackIDs: [original.id])
        library.updatePlaylist(playlist.id, name: "Sonra", detail: "Açıklama")
        library.setPlaylistCover(playlist, trackID: original.id)
        let restored = LibraryStore(directory: library.directory, seed: false)
        XCTAssertEqual(restored.playlists.first?.name, "Sonra")
        XCTAssertEqual(restored.playlists.first?.detail, "Açıklama")
        XCTAssertEqual(restored.playlists.first?.coverTrackID, original.id)
    }
}

extension LibraryTests {
    func testRestoringSameContentUnderDifferentIdentityDoesNotDuplicateMedia() async throws {
        let base = try workspace()
        let first = LibraryStore(directory: base.appendingPathComponent("source/Media"), seed: false)
        let second = LibraryStore(directory: base.appendingPathComponent("target/Media"), seed: false)
        let source = try XCTUnwrap(Bundle.main.url(forResource: "gece-yolu", withExtension: "m4a"))
        _ = try await first.importDownloadedFile(source, title: "Yedek başlığı", artist: "A", sourceURL: nil)
        let existing = try await second.importDownloadedFile(source, title: "Benim başlığım", artist: "B", sourceURL: nil)
        let backup = try await first.exportBackup(includeMedia: true)
        defer { try? FileManager.default.removeItem(at: backup) }
        let count = try await second.restoreBackup(backup)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(second.tracks.map(\.id), [existing.id])
        XCTAssertEqual(second.tracks.first?.title, "Benim başlığım")
    }
}
