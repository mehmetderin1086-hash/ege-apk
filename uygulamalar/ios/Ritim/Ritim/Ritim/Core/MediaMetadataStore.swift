import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers
import UIKit

struct EmbeddedMediaMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var artworkFileName: String?
    var discNumber: Int?
    var trackNumber: Int?
}

/// One metadata reader per library. Image decoding never runs on the main actor.
/// The explicit permit also serializes AVAsset loads across actor suspension points.
actor MediaMetadataStore {
    let directory: URL
    private var owner: UUID?
    private var waiters: [(UUID, CheckedContinuation<Void, Error>)] = []
    static let maximumArtworkBytes = 12 * 1_024 * 1_024
    static let maximumPixelSize = 768

    init(directory: URL) { self.directory = directory }

    func read(url: URL, trackID: UUID, includeArtwork: Bool = true) async throws -> EmbeddedMediaMetadata {
        let request = UUID()
        try await acquire(request)
        defer { release(request) }
        try Task.checkCancellation()
        let asset = AVURLAsset(url: url)
        return try await withTaskCancellationHandler {
            let items = try await asset.load(.commonMetadata)
            var result = EmbeddedMediaMetadata()
            for item in items {
                try Task.checkCancellation()
                if item.commonKey == .commonKeyTitle { result.title = clean(try? await item.load(.stringValue)) }
                if item.commonKey == .commonKeyArtist { result.artist = clean(try? await item.load(.stringValue)) }
                if item.commonKey == .commonKeyAlbumName { result.album = clean(try? await item.load(.stringValue)) }
            }
            let allItems = try await asset.load(.metadata)
            for item in allItems {
                let identifier = item.identifier?.rawValue.lowercased() ?? ""
                guard identifier.contains("trck") || identifier.contains("tpos") || identifier.contains("tracknumber") || identifier.contains("discnumber") else { continue }
                if let text = try? await item.load(.stringValue),
                   let first = text.split(separator: "/").first,
                   let number = Int(first.trimmingCharacters(in: .whitespaces)), number > 0 {
                    if identifier.contains("trck") || identifier.contains("tracknumber") { result.trackNumber = number }
                    else { result.discNumber = number }
                }
            }
            if includeArtwork {
                for item in items where item.commonKey == .commonKeyArtwork {
                    try Task.checkCancellation()
                    if let data = try? await item.load(.dataValue) {
                        try Task.checkCancellation()
                        if let name = try? cacheArtwork(data, trackID: trackID) {
                            result.artworkFileName = name
                            break
                        }
                    }
                }
            }
            if Task.isCancelled {
                removeArtwork(named: result.artworkFileName)
                throw CancellationError()
            }
            return result
        } onCancel: { asset.cancelLoading() }
    }

    func cacheArtwork(_ data: Data, trackID: UUID) throws -> String? {
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= Self.maximumArtworkBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0,
              width.doubleValue * height.doubleValue <= 100_000_000 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        try Task.checkCancellation()
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination), encoded.length <= 1_024 * 1_024 else { return nil }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "\(trackID.uuidString)-\(UUID().uuidString).jpg"
        try (encoded as Data).write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return name
    }

    func removeArtwork(named name: String?) {
        guard let url = Self.artworkURL(named: name, directory: directory) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated static func artworkURL(named name: String?, directory: URL) -> URL? {
        guard let name, name.range(of: #"^[A-Fa-f0-9-]{36,73}\.jpg$"#, options: .regularExpression) != nil else { return nil }
        return directory.appendingPathComponent(name)
    }

    private func clean(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return String(value.prefix(500))
    }

    private func acquire(_ id: UUID) async throws {
        try Task.checkCancellation()
        if owner == nil { owner = id; return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiters.append((id, continuation)) }
            }
        } onCancel: { Task { await self.cancelWaiter(id) } }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.0 == id }) else { return }
        waiters.remove(at: index).1.resume(throwing: CancellationError())
    }

    private func release(_ id: UUID) {
        guard owner == id else { return }
        if waiters.isEmpty { owner = nil }
        else {
            let next = waiters.removeFirst()
            owner = next.0
            next.1.resume()
        }
    }
}

actor MediaArtworkImages {
    static let shared = MediaArtworkImages()
    private let images = NSCache<NSURL, UIImage>()
    init() { images.totalCostLimit = 20 * 1_024 * 1_024 }

    func image(at url: URL) -> UIImage? {
        if let cached = images.object(forKey: url as NSURL) { return cached }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_024 * 1_024,
              let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: MediaMetadataStore.maximumPixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: decoded)
        images.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        return image
    }
}

struct MediaArtistGroup: Identifiable {
    let id: String
    let name: String
    let tracks: [MediaTrack]
}

struct MediaAlbumGroup: Identifiable {
    let id: String
    let name: String
    let artist: String
    let tracks: [MediaTrack]
}

enum MediaLibraryGrouping {
    static func key(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ").precomposedStringWithCanonicalMapping.lowercased()
    }

    static func artists(_ tracks: [MediaTrack]) -> [MediaArtistGroup] {
        Dictionary(grouping: tracks, by: { key($0.artist) }).map { id, tracks in
            MediaArtistGroup(id: id, name: tracks[0].artist, tracks: ordered(tracks))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func albums(_ tracks: [MediaTrack]) -> [MediaAlbumGroup] {
        let available = tracks.filter { !key($0.album ?? "").isEmpty }
        return Dictionary(grouping: available, by: albumID).map { id, tracks in
            MediaAlbumGroup(id: id, name: tracks[0].album ?? "", artist: tracks[0].artist, tracks: ordered(tracks))
        }.sorted { left, right in
            let order = left.name.localizedStandardCompare(right.name)
            return order == .orderedSame ? left.id < right.id : order == .orderedAscending
        }
    }

    static func albumID(_ track: MediaTrack) -> String {
        let artist = key(track.artist)
        return "\(artist.utf8.count):\(artist)\(key(track.album ?? ""))"
    }

    private static func ordered(_ tracks: [MediaTrack]) -> [MediaTrack] {
        let numbered = tracks.allSatisfy { $0.trackNumber != nil }
        return tracks.sorted { left, right in
            if numbered, let l = left.trackNumber, let r = right.trackNumber {
                let ld = left.discNumber ?? 1, rd = right.discNumber ?? 1
                if ld != rd { return ld < rd }
                if l != r { return l < r }
            }
            let order = left.title.localizedStandardCompare(right.title)
            return order == .orderedSame ? left.id.uuidString < right.id.uuidString : order == .orderedAscending
        }
    }
}
