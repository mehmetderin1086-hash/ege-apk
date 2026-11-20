import CryptoKit
import Foundation

/// #8: büyük PDF'lerin işlenmiş hâli (metin, OCR, sayfa görselleri) Caches altında tutulur.
/// Anahtar: dosyanın SHA256'sı + sayfa aralığı + yöntem; dosya değişirse yeniden hesaplanır.
nonisolated enum PayloadCache {
    struct Part: Codable, Equatable, Sendable {
        /// "text" | "image"
        var kind: String
        var name: String
        var text: String?
        var data: Data?

        var payload: SourcePayload? {
            switch kind {
            case "text": text.map { .text($0, name: name) }
            case "image": data.map { .image(data: $0, name: name) }
            default: nil
            }
        }
    }

    static let version = "v1"
    static let maxBytes: Int64 = 400 * 1024 * 1024

    static var directory: URL {
        let dir = URL.cachesDirectory.appending(path: "PayloadCache", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// "<sha256>-<ilk>-<son>|all-<yöntem>-v1"
    static func key(fileHash: String, range: ClosedRange<Int>?, method: String) -> String {
        let pages = range.map { "\($0.lowerBound)-\($0.upperBound)" } ?? "all"
        return "\(fileHash)-\(pages)-\(method)-\(version)"
    }

    /// Dosyayı parça parça okuyarak SHA256 (büyük PDF belleğe alınmaz).
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func load(_ key: String) -> [Part]? {
        let url = directory.appending(path: key + ".json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: url.path)
        return try? JSONDecoder().decode([Part].self, from: data)
    }

    static func store(_ parts: [Part], key: String) {
        guard let data = try? JSONEncoder().encode(parts) else { return }
        try? data.write(to: directory.appending(path: key + ".json"), options: .atomic)
        prune()
    }

    /// En eski kullanılan girdiler silinerek toplam boyut sınırda tutulur.
    static func prune(maxBytes: Int64 = maxBytes) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
        let items = files.compactMap { url -> (URL, Int64, Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 > $1.2 }
        var total: Int64 = 0
        for (url, size, _) in items {
            total += size
            if total > maxBytes { try? FileManager.default.removeItem(at: url) }
        }
    }

    static var totalBytes: Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}
