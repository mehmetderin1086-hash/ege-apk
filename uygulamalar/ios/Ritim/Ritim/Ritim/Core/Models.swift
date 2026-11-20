import Foundation

enum MediaKind: String, Codable, CaseIterable { case audio, video }

struct MediaTrack: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var artist = "Bilinmeyen sanatçı"
    var kind: MediaKind = .audio
    var fileName: String
    var duration: Double = 0
    var addedAt = Date()
    var isFavorite = false
    var playCount = 0
    var lastPlayedAt: Date?
    var sourceURL: String?
    var fileSize: Int64 = 0
    var downloadQuality: DownloadQuality?
    // Import provenance survives a crash between the library and queue journals.
    var downloadEntryID: UUID?
    // Optional so libraries saved before embedded metadata remain readable.
    var album: String?
    var artworkFileName: String?
    var discNumber: Int?
    var trackNumber: Int?
    var colorIndex: Int { Int(id.uuid.0) % 6 }
    var subtitle: String { artist }
}

struct MediaPlaylist: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var trackIDs: [UUID] = []
    var createdAt = Date()
    // Pending slots preserve source order while concurrent downloads finish.
    // Resolved slots refer only to existing tracks; playback still uses trackIDs.
    var downloadOrder: [PlaylistDownloadSlot]?
    var isPinned: Bool?
    var detail: String?
    var coverTrackID: UUID?
}

struct PlaylistDownloadSlot: Codable, Hashable {
    var entryID: UUID?
    var trackID: UUID?
}

enum DownloadFormat: String, Codable, CaseIterable, Identifiable {
    case mp3, mp4
    var id: String { rawValue }
}

enum DownloadQuality: String, Codable, CaseIterable, Identifiable {
    case standard, highest
    var id: String { rawValue }
    var title: String { self == .highest ? "En yüksek" : "Standart" }
    func detail(for format: DownloadFormat) -> String {
        switch (self, format) {
        case (.standard, .mp3): "192 kbps MP3"
        case (.highest, .mp3): "320 kbps MP3"
        case (.standard, .mp4): "Kaynakta varsa 1080p"
        case (.highest, .mp4): "iPhone’a uygun en yüksek video kalitesi"
        }
    }
}

enum DownloadStatus: String, Codable {
    case queued, preparing, downloading, completed, failed, cancelled
    var title: String {
        switch self {
        case .queued: "Sırada"
        case .preparing: "Hazırlanıyor"
        case .downloading: "İndiriliyor"
        case .completed: "Kütüphaneye eklendi"
        case .failed: "İndirilemedi"
        case .cancelled: "İptal edildi"
        }
    }
}

struct DownloadEntry: Identifiable, Codable {
    var id = UUID()
    var title: String
    var sourceURL: String
    var format: DownloadFormat
    var quality: DownloadQuality?
    var progress: Double = 0
    var status: DownloadStatus = .queued
    var error: String?
    var serverID: String?
    var trackID: UUID?
    var artist: String?
    var serverBaseURL: String?
    var batchID: UUID?
    var batchName: String?
    var playlistID: UUID?
    var additionalPlaylistIDs: [UUID]?
    var serverAcknowledged: Bool?
    var resolvedQuality: String?
    var qualityNote: String?
    var priority: Int?
    var stage: DownloadStage?
    var retryCount: Int?
    var retryAfter: Date?
    var receivedBytes: Int64?
    var expectedBytes: Int64?
    var bytesPerSecond: Double?
    var isActive: Bool { [.queued, .preparing, .downloading].contains(status) }
    // Journals written before quality selection used the standard profile.
    var effectiveQuality: DownloadQuality { quality ?? .standard }
}

struct PlaylistItem: Codable, Identifiable, Hashable {
    var id: String
    var url: String
    var title: String
    var artist: String
    var duration: Double?
    var index: Int
}

struct PlaylistPreview: Codable {
    var id: String
    var status: String
    var title: String
    var items: [PlaylistItem]
    var skipped: Int
    var truncated: Bool
    var error: String?
}

enum RitimError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

enum MediaURLPolicy {
    static let extensions: Set<String> = ["mp3", "mp4", "m4a", "mov", "wav", "aiff", "aif", "aac", "caf"]
    static func isYouTube(_ url: URL) -> Bool {
        ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be", "www.youtu.be"].contains(url.host?.lowercased() ?? "")
    }
    static func validatedInput(_ string: String) throws -> URL {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else {
            throw RitimError.message("Geçerli bir HTTPS YouTube veya medya bağlantısı gir.")
        }
        guard isYouTube(url) || extensions.contains(url.pathExtension.lowercased()) else {
            throw RitimError.message("YouTube bağlantısı veya MP3, MP4, M4A, WAV gibi doğrudan bir medya dosyası kullan.")
        }
        return url
    }
    static func isPlaylist(_ url: URL) -> Bool {
        isYouTube(url) && URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "list" && !($0.value ?? "").isEmpty }) == true
    }
    static func canonicalInput(_ string: String) throws -> URL {
        let url = try validatedInput(string)
        guard isYouTube(url) else { return url }
        guard !isPlaylist(url) else {
            throw RitimError.message("Oynatma listesi bağlantısını Oynatma listesi bölümünde çözümleyip parçaları seç.")
        }
        let parts = url.path.split(separator: "/").map(String.init)
        let id: String?
        if (url.host?.lowercased() ?? "").hasSuffix("youtu.be") { id = parts.first }
        else if parts.first == "watch" {
            id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value
        } else if let first = parts.first, ["shorts", "embed", "live"].contains(first), parts.count == 2 { id = parts[1] }
        else { id = nil }
        guard let id, id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else {
            throw RitimError.message("Tek bir YouTube video bağlantısı gir; kanal bağlantıları indirme listesine eklenemez.")
        }
        return URL(string: "https://www.youtube.com/watch?v=\(id)")!
    }
    /// The one video behind a link, ignoring the playlist or Mix it was shared from (watch?v=…&list=…).
    static func singleVideo(_ string: String) throws -> URL {
        let url = try validatedInput(string)
        guard isYouTube(url), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return try canonicalInput(string) }
        components.queryItems = components.queryItems?.filter { !["list", "index", "start_radio"].contains($0.name) }
        return try canonicalInput(components.url?.absoluteString ?? string)
    }
    static func downloadKey(_ string: String, format: DownloadFormat, quality: DownloadQuality? = nil) -> String? {
        guard let url = try? canonicalInput(string) else { return nil }
        let key = url.absoluteString + "|" + format.rawValue
        return isYouTube(url) ? key + "|" + (quality ?? .standard).rawValue : key
    }
    static func validatedPlaylist(_ string: String) throws -> URL {
        let url = try validatedInput(string)
        guard isPlaylist(url), ["/playlist", "/watch"].contains(url.path),
              let list = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "list" })?.value,
              list.range(of: "^[A-Za-z0-9_-]{10,200}$", options: .regularExpression) != nil else {
            throw RitimError.message("Geçerli bir YouTube oynatma listesi bağlantısı gir. Kanal bağlantıları desteklenmiyor.")
        }
        return URL(string: "https://www.youtube.com/playlist?list=\(list)")!
    }
    static func validatedServer(_ string: String) throws -> URL {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased(), url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { throw RitimError.message("Sunucu adresini kontrol et.") }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = labels.compactMap { Int($0) }
        let privateIP = labels.count == 4 && octets.count == 4 && octets.allSatisfy({ (0...255).contains($0) }) &&
            (octets[0] == 10 || (octets[0] == 192 && octets[1] == 168) || (octets[0] == 172 && (16...31).contains(octets[1])))
        let local = host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local") || privateIP
        guard url.scheme == "https" || (url.scheme == "http" && local) else {
            throw RitimError.message("Uzak sunucuda HTTPS kullan. HTTP yalnızca yerel ağ için kullanılabilir.")
        }
        return url
    }
}


enum DownloadStage: String, Codable {
    case resolving, transferring, converting, saving
    var title: String {
        switch self {
        case .resolving: "Bağlantı hazırlanıyor"
        case .transferring: "Kaynak aktarılıyor"
        case .converting: "Medya hazırlanıyor"
        case .saving: "Kitaplığa kaydediliyor"
        }
    }
}

/// Pure policy: lowering the limit never cancels an existing transfer.
enum DownloadResourcePolicy {
    static func limit(requested: Int, thermal: ProcessInfo.ThermalState, lowPower: Bool) -> Int {
        switch thermal {
        case .critical: return 0
        case .serious: return min(requested, 2)
        default: return lowPower ? min(requested, 4) : requested
        }
    }
}

enum LibrarySearch {
    static func key(_ value: String) -> String {
        value.lowercased(with: Locale(identifier: "tr_TR"))
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
    }
    static func matches(_ track: MediaTrack, query: String) -> Bool {
        let words = key(query).split(whereSeparator: \.isWhitespace)
        let content = key([track.title, track.artist, track.album ?? ""].joined(separator: " "))
        return words.allSatisfy { content.contains($0) }
    }
}


enum DownloadRetryPolicy {
    static func delay(error: Error, attempt: Int) -> TimeInterval? {
        let error = error as NSError
        guard attempt < 3, error.domain == NSURLErrorDomain,
              [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet,
               NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed].contains(error.code) else { return nil }
        return [5.0, 15.0, 45.0][max(0, attempt)]
    }
}


struct PlaybackStallMonitor {
    enum Action { case none, recover, stop }
    private var trackID: UUID?
    private var position: Double = 0
    private var progressedAt: TimeInterval = 0
    private var attempted = false
    mutating func sample(track: UUID, position: Double, now: TimeInterval, eligible: Bool) -> Action {
        if trackID != track { trackID = track; self.position = position; progressedAt = now; attempted = false }
        guard eligible, position.isFinite else { self.position = position; progressedAt = now; return .none }
        if abs(position - self.position) > 0.1 { self.position = position; progressedAt = now; return .none }
        guard now - progressedAt >= 10 else { return .none }
        progressedAt = now
        if attempted { return .stop }
        attempted = true
        return .recover
    }
}
