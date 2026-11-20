import AVFoundation
import Combine
import Foundation

struct LyricLine: Codable, Equatable, Identifiable, Sendable {
    var id: Int
    var time: Double
    var text: String
}

struct TrackLyrics: Codable, Equatable, Sendable {
    var trackID: UUID
    var rawText: String
    var plainText: String
    var lines: [LyricLine]
    var sourceName: String
    var sourceURL: String?
    /// Additional user adjustment in seconds; positive values show lyrics later.
    var offset: Double = 0
    var savedAt = Date()
    var isInstrumental = false
    var hasUserEdits = false

    func activeLine(at elapsed: Double) -> LyricLine? {
        guard elapsed.isFinite else { return nil }
        let position = elapsed - offset
        var low = 0, high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].time <= position { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? lines[low - 1] : nil
    }
}

struct LyricsCandidate: Equatable, Identifiable, Sendable {
    var id: Int
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var hasSynced: Bool
    var isInstrumental: Bool
}

enum LyricsError: LocalizedError {
    case tooLarge, empty, invalidFile, unavailable, invalidResponse, notFound, rateLimited(Int), cannotSave
    var errorDescription: String? {
        switch self {
        case .tooLarge: return "Şarkı sözü dosyası fazla büyük. En fazla 512 KB metin kullan."
        case .empty: return "Kaydetmek için şarkı sözü veya zamanlı LRC satırı ekle."
        case .invalidFile: return "Bu dosya okunamadı. UTF-8 veya UTF-16 biçiminde .lrc ya da .txt seç."
        case .unavailable: return "Şarkı sözü servisine ulaşılamadı. Kayıtlı sözler çevrimdışı kullanılabilir."
        case .invalidResponse: return "Şarkı sözü servisi geçerli bir yanıt göndermedi."
        case .notFound: return "Bu kayıt için şarkı sözü bulunamadı. Farklı bir adla ara veya kendi sözlerini ekle."
        case .rateLimited(let seconds): return "Şarkı sözü servisi meşgul. Yaklaşık \(seconds) saniye sonra yeniden dene."
        case .cannotSave: return "Şarkı sözleri kaydedilemedi. Aygıttaki boş alanı ve dosya erişimini kontrol et."
        }
    }
}

enum LRCParser {
    static let maxTextBytes = 512 * 1_024
    private static let timestamps = try! NSRegularExpression(pattern: #"\[(\d{1,4}):([0-5]\d)(?:[.:](\d{1,3}))?\]"#)
    private static let metadata = try! NSRegularExpression(pattern: #"^\[(ar|ti|al|by|re|ve|length|offset):.*\]$"#, options: .caseInsensitive)
    private static let offsetTag = try! NSRegularExpression(pattern: #"^\[offset:\s*([+-]?\d+)\s*\]$"#, options: .caseInsensitive)

    static func parse(_ raw: String) throws -> (plainText: String, lines: [LyricLine]) {
        guard raw.utf8.count <= maxTextBytes else { throw LyricsError.tooLarge }
        let text = raw.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var plain: [String] = [], timed: [(Double, String, Int)] = []
        var offset = 0.0, expandedBytes = 0
        for row in text.components(separatedBy: "\n") {
            let row = row.trimmingCharacters(in: .whitespaces)
            let ns = row as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let tag = offsetTag.firstMatch(in: row, range: range),
               let milliseconds = Double(ns.substring(with: tag.range(at: 1))), milliseconds.isFinite {
                offset = min(86_400, max(-86_400, milliseconds / 1_000))
                continue
            }
            if metadata.firstMatch(in: row, range: range) != nil { continue }
            let matches = timestamps.matches(in: row, range: range)
            var times: [Double] = [], end = 0
            for match in matches {
                guard ns.substring(with: NSRange(location: end, length: match.range.location - end))
                    .trimmingCharacters(in: .whitespaces).isEmpty else { break }
                let minutes = Double(ns.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: match.range(at: 2))) ?? 0
                let fraction = match.range(at: 3).location == NSNotFound ? 0 : Double("0." + ns.substring(with: match.range(at: 3))) ?? 0
                times.append(minutes * 60 + seconds + fraction)
                end = NSMaxRange(match.range)
            }
            let content = ns.substring(from: end).trimmingCharacters(in: .whitespaces)
            plain.append(content)
            for time in times {
                expandedBytes += content.utf8.count
                guard timed.count < 10_000, expandedBytes <= maxTextBytes * 2 else { throw LyricsError.tooLarge }
                timed.append((time, content, timed.count))
            }
        }
        // LRC's positive metadata offset advances lyrics. The separate user
        // adjustment intentionally uses positive values to delay the display.
        let adjusted: [(Double, String, Int)] = timed.map { row in
            (max(0, row.0 - offset), row.1, row.2)
        }
        let sorted = adjusted.sorted { left, right in
            if left.0 == right.0 { return left.2 < right.2 }
            return left.0 < right.0
        }
        return (plain.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                sorted.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) })
    }
}

private struct LRCLIBRecord: Decodable, Sendable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: Double?
    let instrumental: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?
    var candidate: LyricsCandidate {
        LyricsCandidate(id: id, title: trackName, artist: artistName, album: albumName ?? "",
                        duration: duration?.isFinite == true ? max(0, duration ?? 0) : 0,
                        hasSynced: syncedLyrics?.isEmpty == false, isInstrumental: instrumental == true)
    }
}

/// Conservative identity checks; variant labels are never silently stripped.
enum LyricsMatching {
    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    static func title(for track: MediaTrack) -> String {
        var value = track.title.replacingOccurrences(of: #"\s*[\(\[]\s*(official\s+(music\s+)?(video|audio|lyric(s)?(\s+video)?)|lyrics?|audio|hd|4k)\s*[\)\]]"#,
                                                     with: "", options: [.regularExpression, .caseInsensitive])
        for separator in [" - ", " – ", " — "] {
            if let range = value.range(of: separator), normalized(String(value[..<range.lowerBound])) == normalized(artist(for: track)) {
                value = String(value[range.upperBound...]); break
            }
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func artist(for track: MediaTrack) -> String {
        track.artist.replacingOccurrences(of: #"\s+-\s+Topic$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func canAutomaticallyLookUp(_ track: MediaTrack) -> Bool {
        let artist = normalized(artist(for: track))
        return !normalized(title(for: track)).isEmpty && !artist.isEmpty &&
            !["Bilinmeyen sanatçı", "Unknown artist", "YouTube", "Various artists"].map(normalized).contains(artist) &&
            track.duration.isFinite && (1...3_600).contains(track.duration) &&
            !hasVariant(track.title) && !hasVariant(track.album ?? "")
    }
    static func isSafeMatch(_ candidate: LyricsCandidate, for track: MediaTrack) -> Bool {
        canAutomaticallyLookUp(track) && normalized(candidate.title) == normalized(title(for: track)) &&
            normalized(candidate.artist) == normalized(artist(for: track)) &&
            candidate.duration > 0 && abs(candidate.duration - track.duration) <= 2 &&
            !hasVariant(candidate.title + " " + candidate.album)
    }
    private static func hasVariant(_ text: String) -> Bool {
        let words = Set(normalized(text).split(separator: " ").map(String.init))
        return !words.isDisjoint(with: ["live", "remix", "remaster", "remastered", "acoustic", "karaoke", "cover", "slowed", "reverb", "sped", "extended", "concert", "mix", "version", "canli", "canlı"])
    }
}

private final class LyricsRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && request.url?.host == "lrclib.net" ? request : nil)
    }
}

/// LRCLIB requires sequential requests, a short delay, and honoring Retry-After.
private actor LyricsAPI {
    private let session: URLSession
    private let redirectPolicy = LyricsRedirectPolicy()
    private var owner: UUID?
    private var waiters: [(UUID, CheckedContinuation<UUID, Error>)] = []
    private var nextRequest = Date.distantPast
    private var blockedUntil = Date.distantPast
    static let bodyLimit = 2 * 1_024 * 1_024

    init(session: URLSession) { self.session = session }

    func request(path: String, query: [URLQueryItem] = []) async throws -> Data {
        let id = try await acquire()
        defer { nextRequest = Date().addingTimeInterval(0.3); release(id) }
        try Task.checkCancellation()
        if blockedUntil > Date() { throw LyricsError.rateLimited(max(1, Int(ceil(blockedUntil.timeIntervalSinceNow)))) }
        let delay = nextRequest.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        var components = URLComponents(string: "https://lrclib.net" + path)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Ritim/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.8") (com.mehmetderin.ritim; https://lrclib.net)", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request, delegate: redirectPolicy)
        guard let http = response as? HTTPURLResponse else { throw LyricsError.invalidResponse }
        if http.statusCode == 429 || http.statusCode == 503 {
            let seconds = Self.retryDelay(http.value(forHTTPHeaderField: "Retry-After"))
            blockedUntil = Date().addingTimeInterval(seconds)
            throw LyricsError.rateLimited(Int(ceil(seconds)))
        }
        if http.statusCode == 404 { throw LyricsError.notFound }
        guard http.statusCode == 200, http.url?.host == "lrclib.net",
              http.mimeType?.lowercased().contains("json") == true else { throw LyricsError.invalidResponse }
        guard response.expectedContentLength <= Int64(Self.bodyLimit) else { throw LyricsError.tooLarge }
        var data = Data()
        data.reserveCapacity(min(Self.bodyLimit, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            if data.count % 4_096 == 0 { try Task.checkCancellation() }
            guard data.count < Self.bodyLimit else { throw LyricsError.tooLarge }
            data.append(byte)
        }
        try Task.checkCancellation()
        return data
    }

    private static func retryDelay(_ header: String?) -> TimeInterval {
        if let header, let seconds = Double(header), seconds.isFinite { return min(86_400, max(1, seconds)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        if let header, let date = formatter.date(from: header) { return min(86_400, max(1, date.timeIntervalSinceNow)) }
        return 60
    }

    private func acquire() async throws -> UUID {
        try Task.checkCancellation()
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else if owner == nil { owner = id; continuation.resume(returning: id) }
                else { waiters.append((id, continuation)) }
            }
        } onCancel: { Task { await self.cancelWaiting(id) } }
    }
    private func cancelWaiting(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.0 == id }) else { return }
        waiters.remove(at: index).1.resume(throwing: CancellationError())
    }
    private func release(_ id: UUID) {
        guard owner == id else { return }
        guard !waiters.isEmpty else { owner = nil; return }
        let next = waiters.removeFirst(); owner = next.0; next.1.resume(returning: next.0)
    }
}

@MainActor
final class LyricsStore: ObservableObject {
    static let maxTextBytes = LRCParser.maxTextBytes
    @Published private(set) var currentTrackID: UUID?
    @Published private(set) var current: TrackLyrics?
    @Published private(set) var isLoading = false
    @Published private(set) var isSearching = false
    @Published private(set) var candidates: [LyricsCandidate] = []
    @Published var errorMessage: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var isUsingCachedLyrics = false

    private struct Cache: Codable {
        var version = 1
        var trackID: UUID
        var signature: String
        var automatic: TrackLyrics?
        var user: TrackLyrics?
        var offset: Double = 0
        var checkedAt: Date?
    }
    private let directory: URL
    private let api: LyricsAPI
    private let networkEnabled: Bool
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var generation = UUID()
    private var searchGeneration = UUID()
    private var unreadableIDs = Set<UUID>()
    private var protectedIDs = Set<UUID>()

    init(directory: URL, session: URLSession? = nil, networkEnabled: Bool = true) {
        self.directory = directory
        #if DEBUG
        self.networkEnabled = networkEnabled && ProcessInfo.processInfo.environment["RITIM_UI_TEST_LYRICS_OFFLINE"] != "1"
        #else
        self.networkEnabled = networkEnabled
        #endif
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.urlCache = nil
        self.api = LyricsAPI(session: session ?? URLSession(configuration: configuration))
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { errorMessage = LyricsError.cannotSave.localizedDescription }
    }

    func load(for track: MediaTrack, fileURL: URL? = nil, refresh: Bool = false) async {
        invalidateLoad()
        invalidateSearch()
        currentTrackID = track.id
        errorMessage = nil; statusMessage = nil; candidates = []
        current = record(for: track)
        isUsingCachedLyrics = current != nil
        if current?.hasUserEdits == true || (current != nil && !refresh) { return }
        if !refresh, let cache = readCache(for: track), cache.signature == signature(track),
           let checked = cache.checkedAt, Date().timeIntervalSince(checked) < 86_400, current == nil {
            statusMessage = LyricsError.notFound.localizedDescription
            return
        }
        let requestGeneration = generation
        isLoading = true
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == requestGeneration { self.isLoading = false; self.loadTask = nil } }
            do {
                if let fileURL, fileURL.isFileURL, let embedded = try await self.embeddedLyrics(fileURL) {
                    try Task.checkCancellation()
                    guard self.isCurrent(track.id, requestGeneration) else { return }
                    try self.saveAutomatic(raw: embedded, plain: nil, instrumental: false, sourceName: "Dosyanın içindeki sözler", sourceURL: nil, for: track)
                    return
                }
                try Task.checkCancellation()
                guard self.networkEnabled else { self.statusMessage = "Çevrimdışı: LRC/TXT dosyası ekleyebilir veya sözleri yapıştırabilirsin."; return }
                guard LyricsMatching.canAutomaticallyLookUp(track) else {
                    self.statusMessage = "Kesin eşleştirme için parça ve sanatçı adı gerekli. Ara veya kendi sözlerini ekle."
                    return
                }
                let data = try await self.api.request(path: "/api/get", query: [
                    URLQueryItem(name: "track_name", value: LyricsMatching.title(for: track)),
                    URLQueryItem(name: "artist_name", value: LyricsMatching.artist(for: track)),
                    URLQueryItem(name: "duration", value: String(track.duration))
                ])
                let result = try JSONDecoder().decode(LRCLIBRecord.self, from: data)
                try Task.checkCancellation()
                guard self.isCurrent(track.id, requestGeneration) else { return }
                guard result.id > 0, LyricsMatching.isSafeMatch(result.candidate, for: track) else {
                    self.statusMessage = "Kesin eşleşme bulunamadı. Arama sonuçlarından doğru kaydı seçebilirsin."
                    return
                }
                try self.save(result, for: track)
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled, self.isCurrent(track.id, requestGeneration) else { return }
                if case LyricsError.notFound = error {
                    self.statusMessage = error.localizedDescription
                    if self.current == nil {
                        var cache = self.readCache(for: track) ?? self.emptyCache(track)
                        cache.checkedAt = Date()
                        try? self.write(cache, prune: true)
                    }
                } else { self.errorMessage = self.publicMessage(error) }
            }
        }
        loadTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    func search(query: String) async {
        invalidateSearch(); invalidateLoad()
        errorMessage = nil; candidates = []
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        guard networkEnabled else { statusMessage = "Çevrimdışı arama kullanılamıyor. Kendi LRC/TXT dosyanı ekleyebilirsin."; return }
        let requestGeneration = searchGeneration, trackID = currentTrackID
        isSearching = true
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if self.searchGeneration == requestGeneration { self.isSearching = false; self.searchTask = nil } }
            do {
                let data = try await self.api.request(path: "/api/search", query: [URLQueryItem(name: "q", value: String(query.prefix(300)))])
                let records = try JSONDecoder().decode([LRCLIBRecord].self, from: data)
                try Task.checkCancellation()
                guard self.searchGeneration == requestGeneration, self.currentTrackID == trackID else { return }
                var seen = Set<Int>()
                self.candidates = records.filter { $0.id > 0 && seen.insert($0.id).inserted }.prefix(20).map(\.candidate)
                self.statusMessage = self.candidates.isEmpty ? "Arama sonucu bulunamadı." : "Parça, sanatçı ve süreyi karşılaştırarak doğru kaydı seç."
            } catch is CancellationError { }
            catch {
                if !Task.isCancelled, self.searchGeneration == requestGeneration, self.currentTrackID == trackID { self.errorMessage = self.publicMessage(error) }
            }
        }
        searchTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    func choose(_ candidate: LyricsCandidate, for track: MediaTrack) async {
        guard currentTrackID == track.id, candidate.id > 0, networkEnabled else { return }
        invalidateLoad(); invalidateSearch()
        let requestGeneration = generation
        errorMessage = nil; isLoading = true
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == requestGeneration { self.isLoading = false; self.loadTask = nil } }
            do {
                let data = try await self.api.request(path: "/api/get/\(candidate.id)")
                let record = try JSONDecoder().decode(LRCLIBRecord.self, from: data)
                try Task.checkCancellation()
                guard self.isCurrent(track.id, requestGeneration) else { return }
                guard record.id == candidate.id else { throw LyricsError.invalidResponse }
                try self.save(record, for: track, replaceUser: true)
                self.candidates = []
            } catch is CancellationError { }
            catch { if !Task.isCancelled, self.isCurrent(track.id, requestGeneration) { self.errorMessage = self.publicMessage(error) } }
        }
        loadTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    func saveUserLyrics(_ text: String, for track: MediaTrack, sourceName: String? = nil) throws {
        let parsed = try LRCParser.parse(text)
        guard !parsed.plainText.isEmpty else { throw LyricsError.empty }
        var cache = readCache(for: track) ?? emptyCache(track)
        cache.user = TrackLyrics(trackID: track.id, rawText: text, plainText: parsed.plainText, lines: parsed.lines,
                                 sourceName: String((sourceName ?? "Kendi sözlerin").prefix(160)), sourceURL: nil, hasUserEdits: true)
        try write(cache)
        if currentTrackID == track.id { invalidateLoad(); invalidateSearch(); show(cache, for: track); errorMessage = nil }
    }

    func importLyrics(from url: URL, for track: MediaTrack) throws {
        guard url.isFileURL, ["lrc", "txt"].contains(url.pathExtension.lowercased()) else { throw LyricsError.invalidFile }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maxTextBytes + 1) ?? Data()
        guard data.count <= Self.maxTextBytes else { throw LyricsError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { throw LyricsError.invalidFile }
        try saveUserLyrics(text, for: track, sourceName: url.lastPathComponent)
    }

    func setOffset(_ seconds: Double, for track: MediaTrack) throws {
        guard seconds.isFinite else { return }
        var cache = readCache(for: track) ?? emptyCache(track)
        cache.offset = min(30, max(-30, seconds))
        try write(cache)
        if currentTrackID == track.id { show(cache, for: track) }
    }

    func removeUserLyrics(for track: MediaTrack) throws {
        guard var cache = readCache(for: track) else { return }
        cache.user = nil; cache.offset = 0
        try write(cache)
        if currentTrackID == track.id { invalidateLoad(); show(cache, for: track) }
    }

    func record(for track: MediaTrack) -> TrackLyrics? {
        guard let cache = readCache(for: track) else { return nil }
        return effective(cache, for: track)
    }

    private func embeddedLyrics(_ url: URL) async throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.metadata) else { return nil }
        for item in metadata where item.identifier == .iTunesMetadataLyrics || item.identifier == .id3MetadataUnsynchronizedLyric {
            try Task.checkCancellation()
            if let text = try? await item.load(.stringValue), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               text.utf8.count <= Self.maxTextBytes { return text }
        }
        return nil
    }

    private func save(_ record: LRCLIBRecord, for track: MediaTrack, replaceUser: Bool = false) throws {
        let synced = record.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines)
        let plain = record.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines)
        try saveAutomatic(raw: synced?.isEmpty == false ? synced! : (plain ?? ""), plain: plain,
                          instrumental: record.instrumental == true, sourceName: "LRCLIB",
                          sourceURL: "https://lrclib.net/api/get/\(record.id)", for: track, replaceUser: replaceUser)
    }

    private func saveAutomatic(raw: String, plain: String?, instrumental: Bool, sourceName: String,
                               sourceURL: String?, for track: MediaTrack, replaceUser: Bool = false) throws {
        let parsed = try LRCParser.parse(raw)
        guard instrumental || !parsed.plainText.isEmpty else { throw LyricsError.notFound }
        guard (plain?.utf8.count ?? 0) <= Self.maxTextBytes else { throw LyricsError.tooLarge }
        var cache = readCache(for: track) ?? emptyCache(track)
        cache.signature = signature(track)
        cache.automatic = TrackLyrics(trackID: track.id, rawText: raw, plainText: plain?.isEmpty == false ? plain! : parsed.plainText,
                                      lines: instrumental ? [] : parsed.lines, sourceName: sourceName, sourceURL: sourceURL,
                                      isInstrumental: instrumental)
        if replaceUser { cache.user = nil }
        cache.checkedAt = Date()
        try write(cache, prune: true)
        show(cache, for: track)
        isUsingCachedLyrics = false
    }

    private func signature(_ track: MediaTrack) -> String {
        "\(track.title)|\(track.artist)|\(track.album ?? "")|\(track.duration.isFinite ? track.duration : 0)"
    }
    private func emptyCache(_ track: MediaTrack) -> Cache { Cache(trackID: track.id, signature: signature(track)) }
    private func cacheURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("json") }
    private func effective(_ cache: Cache, for track: MediaTrack) -> TrackLyrics? {
        var result = cache.user ?? (cache.signature == signature(track) ? cache.automatic : nil)
        result?.offset = cache.offset
        return result
    }
    private func show(_ cache: Cache, for track: MediaTrack) {
        guard currentTrackID == track.id else { return }
        current = effective(cache, for: track)
        isUsingCachedLyrics = current != nil
        statusMessage = current == nil ? nil : (current?.isInstrumental == true ? "Bu kayıt enstrümantal; şarkı sözü içermiyor." : nil)
    }

    private func readCache(for track: MediaTrack) -> Cache? {
        let url = cacheURL(track.id)
        guard !unreadableIDs.contains(track.id), FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 4 * 1_024 * 1_024 else { throw LyricsError.tooLarge }
            let cache = try JSONDecoder().decode(Cache.self, from: Data(contentsOf: url))
            guard cache.version == 1, cache.trackID == track.id, cache.offset.isFinite, abs(cache.offset) <= 30 else {
                throw LyricsError.invalidFile
            }
            for record in [cache.automatic, cache.user].compactMap({ $0 }) {
                guard valid(record, for: track.id) else { throw LyricsError.invalidFile }
            }
            return cache
        } catch {
            unreadableIDs.insert(track.id)
            let backup = directory.appendingPathComponent("\(track.id.uuidString)-recovery-\(UUID().uuidString).json")
            do { try FileManager.default.copyItem(at: url, to: backup) }
            catch { protectedIDs.insert(track.id) }
            errorMessage = "Kayıtlı şarkı sözleri okunamadı. Önceki dosya kurtarma için korundu."
            return nil
        }
    }

    private func valid(_ record: TrackLyrics, for id: UUID) -> Bool {
        guard record.trackID == id, record.rawText.utf8.count <= Self.maxTextBytes,
              record.plainText.utf8.count <= Self.maxTextBytes, record.lines.count <= 10_000 else { return false }
        var previous = 0.0
        var identifiers = Set<Int>()
        for line in record.lines {
            guard line.time.isFinite, line.time >= previous, identifiers.insert(line.id).inserted else { return false }
            previous = line.time
        }
        return true
    }

    private func write(_ cache: Cache, prune: Bool = false) throws {
        guard !protectedIDs.contains(cache.trackID) else { throw LyricsError.cannotSave }
        do {
            let data = try JSONEncoder().encode(cache)
            guard data.count <= 4 * 1_024 * 1_024 else { throw LyricsError.tooLarge }
            try data.write(to: cacheURL(cache.trackID), options: .atomic)
            unreadableIDs.remove(cache.trackID)
            if prune { pruneAutomaticCache(keeping: cache.trackID) }
        } catch let error as LyricsError { throw error }
        catch { throw LyricsError.cannotSave }
    }

    private func pruneAutomaticCache(keeping id: UUID) {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        var rows: [(URL, Int, Date)] = []
        for url in urls where url.pathExtension == "json" && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize, size <= 4 * 1_024 * 1_024,
                  let data = try? Data(contentsOf: url), let cache = try? JSONDecoder().decode(Cache.self, from: data),
                  cache.version == 1, cache.trackID == UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  cache.user == nil else { continue }
            rows.append((url, size, values.contentModificationDate ?? .distantPast))
        }
        var bytes = rows.reduce(0) { $0 + $1.1 }, count = rows.count
        for row in rows.sorted(by: { $0.2 < $1.2 }) where row.0 != cacheURL(id) {
            guard count > 100 || bytes > 16 * 1_024 * 1_024 else { break }
            do { try FileManager.default.removeItem(at: row.0); bytes -= row.1; count -= 1 } catch { }
        }
    }

    private func invalidateLoad() { generation = UUID(); loadTask?.cancel(); loadTask = nil; isLoading = false }
    private func invalidateSearch() { searchGeneration = UUID(); searchTask?.cancel(); searchTask = nil; isSearching = false }
    private func isCurrent(_ id: UUID, _ token: UUID) -> Bool { currentTrackID == id && generation == token }
    private func publicMessage(_ error: Error) -> String {
        if let error = error as? LyricsError { return error.localizedDescription }
        return LyricsError.unavailable.localizedDescription
    }
}
