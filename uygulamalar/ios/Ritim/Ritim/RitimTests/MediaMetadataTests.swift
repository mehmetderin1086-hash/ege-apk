import AVFoundation
import ImageIO
import UIKit
import XCTest
@testable import Ritim

@MainActor
final class MediaMetadataTests: XCTestCase {
    private func workspace() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("Metadata-\(UUID())")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        return base
    }

    private func cover() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2048, height: 1024), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2048, height: 1024))
        }
        return try XCTUnwrap(image.pngData())
    }

    private func taggedFile(in base: URL) async throws -> URL {
        let input = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "native-audio", withExtension: "m4a"))
        let output = base.appendingPathComponent("tagged.m4a")
        let exporter = try XCTUnwrap(AVAssetExportSession(asset: AVURLAsset(url: input), presetName: AVAssetExportPresetAppleM4A))
        func string(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as NSString
            return item
        }
        let art = AVMutableMetadataItem()
        art.identifier = .iTunesMetadataCoverArt
        art.value = try cover() as NSData
        art.dataType = kCMMetadataBaseDataType_PNG as String
        exporter.metadata = [string(.iTunesMetadataSongName, "Gömülü başlık"),
                             string(.iTunesMetadataArtist, "Gömülü sanatçı"),
                             string(.iTunesMetadataAlbum, "Gece Albümü"), art]
        exporter.outputURL = output
        exporter.outputFileType = .m4a
        await exporter.export()
        guard exporter.status == .completed else { throw exporter.error ?? RitimError.message("Test dosyası üretilemedi") }
        return output
    }

    private func writeLegacyLibrary(base: URL, source: URL) throws -> MediaTrack {
        let directory = base.appendingPathComponent("Media")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("existing.m4a")
        try FileManager.default.copyItem(at: source, to: destination)
        let track = MediaTrack(title: "Kullanıcının başlığı", artist: "Kullanıcının sanatçısı", fileName: destination.lastPathComponent,
                               duration: 4, isFavorite: true, playCount: 17, fileSize: Int64(try Data(contentsOf: source).count))
        let encodedTrack = try JSONSerialization.jsonObject(with: JSONEncoder().encode(track))
        let playlist = MediaPlaylist(name: "Korunan liste", trackIDs: [track.id])
        let encodedPlaylist = try JSONSerialization.jsonObject(with: JSONEncoder().encode(playlist))
        let state: [String: Any] = ["tracks": [encodedTrack], "playlists": [encodedPlaylist], "seeded": true]
        try JSONSerialization.data(withJSONObject: state).write(to: base.appendingPathComponent("library.json"))
        return track
    }

    func testOlderTrackJSONDecodesWithoutAlbumAndArtwork() throws {
        let track = MediaTrack(title: "Eski parça", artist: "Sanatçı", fileName: "song.mp3", playCount: 8)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(track)) as? [String: Any])
        json.removeValue(forKey: "album")
        json.removeValue(forKey: "artworkFileName")
        let decoded = try JSONDecoder().decode(MediaTrack.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.id, track.id)
        XCTAssertEqual(decoded.playCount, 8)
        XCTAssertNil(decoded.album)
        XCTAssertNil(decoded.artworkFileName)
    }

    func testEmbeddedAlbumAndThumbnailSurviveRealImportAndReload() async throws {
        let base = try workspace()
        let source = try await taggedFile(in: base)
        let library = LibraryStore(directory: base.appendingPathComponent("Media"), seed: false, metadataScanningAllowed: { true })
        let track = try await library.importDownloadedFile(source, title: "Seçilen başlık", artist: "Seçilen sanatçı", sourceURL: nil)
        XCTAssertEqual(track.title, "Seçilen başlık")
        XCTAssertEqual(track.artist, "Seçilen sanatçı")
        XCTAssertEqual(track.album, "Gece Albümü")
        let artwork = try XCTUnwrap(library.artworkURL(for: track))
        let image = try XCTUnwrap(CGImageSourceCreateWithURL(artwork as CFURL, nil))
        let dimensions = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any])
        XCTAssertEqual((dimensions[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 768)
        XCTAssertEqual((dimensions[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, 384)
        let reloaded = LibraryStore(directory: library.directory, seed: false)
        XCTAssertEqual(reloaded.tracks.first?.album, track.album)
        XCTAssertEqual(reloaded.tracks.first?.artworkFileName, track.artworkFileName)
        library.delete(track)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artwork.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testExplicitScanPreservesUserNamesFavoritesCountsAndPlaylist() async throws {
        let base = try workspace()
        let source = try await taggedFile(in: base)
        let original = try writeLegacyLibrary(base: base, source: source)
        let library = LibraryStore(directory: base.appendingPathComponent("Media"), seed: false, metadataScanningAllowed: { true })
        XCTAssertNil(library.tracks.first?.album, "Opening the library must not scan files")
        await library.scanEmbeddedMetadata()
        let updated = try XCTUnwrap(library.tracks.first)
        XCTAssertEqual(updated.title, original.title)
        XCTAssertEqual(updated.artist, original.artist)
        XCTAssertEqual(updated.isFavorite, original.isFavorite)
        XCTAssertEqual(updated.playCount, original.playCount)
        XCTAssertEqual(updated.album, "Gece Albümü")
        XCTAssertNotNil(updated.artworkFileName)
        XCTAssertEqual(library.playlists.first?.trackIDs, [original.id])
        XCTAssertEqual(library.metadataScanProgress, 1)
        XCTAssertFalse(library.isScanningMetadata)
    }

    func testForegroundLossBeforeCommitLeavesLibraryUnchangedAndRemovesNewCover() async throws {
        let base = try workspace()
        let source = try await taggedFile(in: base)
        _ = try writeLegacyLibrary(base: base, source: source)
        let before = try Data(contentsOf: base.appendingPathComponent("library.json"))
        var foregroundChecks = 0
        let library = LibraryStore(directory: base.appendingPathComponent("Media"), seed: false, metadataScanningAllowed: {
            foregroundChecks += 1
            return foregroundChecks <= 2 // Start and first read allowed; foreground is lost during the awaited read.
        })
        await library.scanEmbeddedMetadata()
        XCTAssertEqual(try Data(contentsOf: base.appendingPathComponent("library.json")), before)
        XCTAssertNil(library.tracks.first?.album)
        XCTAssertNil(library.tracks.first?.artworkFileName)
        XCTAssertFalse(library.isScanningMetadata)
        XCTAssertTrue((try? FileManager.default.contentsOfDirectory(atPath: library.artworkDirectory.path).isEmpty) ?? true)
    }

    func testArtworkRejectsInvalidOversizedAndEscapingPaths() async throws {
        let base = try workspace()
        let store = MediaMetadataStore(directory: base)
        let invalid = try await store.cacheArtwork(Data("not an image".utf8), trackID: UUID())
        let oversized = try await store.cacheArtwork(Data(repeating: 0, count: MediaMetadataStore.maximumArtworkBytes + 1), trackID: UUID())
        XCTAssertNil(invalid)
        XCTAssertNil(oversized)
        XCTAssertNil(MediaMetadataStore.artworkURL(named: "../private.jpg", directory: base))
        XCTAssertNil(MediaMetadataStore.artworkURL(named: "/tmp/cover.jpg", directory: base))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: base.path).isEmpty)
    }

    func testAlbumsWithSameNameFromDifferentArtistsStaySeparateAndIDsStayStable() {
        let first = MediaTrack(title: "B", artist: "Artist A", fileName: "a.mp3", album: "Collection")
        let second = MediaTrack(title: "A", artist: "Artist B", fileName: "b.mp3", album: "Collection")
        let third = MediaTrack(title: "C", artist: "Artist A", fileName: "c.mp3", album: " collection ")
        let unknown = MediaTrack(title: "Single", artist: "Artist A", fileName: "d.mp3")
        let albums = MediaLibraryGrouping.albums([first, second, third, unknown])
        XCTAssertEqual(albums.count, 2)
        XCTAssertEqual(Set(albums.map(\.id)), Set(MediaLibraryGrouping.albums([third, second, first]).map(\.id)))
        XCTAssertEqual(albums.first { $0.artist == "Artist A" }?.tracks.count, 2)
        XCTAssertEqual(MediaLibraryGrouping.artists([first, second, third, unknown]).count, 2)
    }
}
