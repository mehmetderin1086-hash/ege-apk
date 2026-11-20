import Foundation

// Kütüphane ve altyapı uçları (sunucu: /v1/youtube/feed, /v1/media/*, /v1/files/{id}, PUT /v1/upload/{id},
// /v1/youtube/search, /v1/youtube/tags, genişleyen /v1/library-ask). Çözümleme sunucu sürümleri arasında toleranslıdır.

nonisolated private struct Ack: Decodable, Sendable {
    init(from decoder: Decoder) throws {}
}

// MARK: - Kanal/oynatma listesi akışı (#2)

nonisolated struct YouTubeFeedRequest: Encodable, Sendable {
    var url: String
}

nonisolated struct FeedVideo: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var url: String
    var title: String
    var duration: Double?
    var uploadDate: String?

    init(id: String, url: String, title: String, duration: Double? = nil, uploadDate: String? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.duration = duration
        self.uploadDate = uploadDate
    }

    private enum CodingKeys: String, CodingKey { case id, url, title, duration, uploadDate }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? YouTubeLink.videoID(url) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        duration = try c.decodeIfPresent(Double.self, forKey: .duration)
        uploadDate = try c.decodeIfPresent(String.self, forKey: .uploadDate)
    }
}

nonisolated struct YouTubeFeed: Decodable, Sendable {
    var title: String
    var url: String
    var videos: [FeedVideo]

    private enum CodingKeys: String, CodingKey { case title, url, videos }

    init(title: String = "", url: String = "", videos: [FeedVideo] = []) {
        self.title = title
        self.url = url
        self.videos = videos
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        videos = try c.decodeIfPresent([FeedVideo].self, forKey: .videos) ?? []
    }
}

// MARK: - Medya işleri: çevrimdışı video, altyazılı video (#14, #36)

nonisolated enum MediaKind: String, Codable, Sendable {
    case video, subtitled
}

nonisolated struct MediaStartRequest: Encodable, Sendable {
    var kind: MediaKind
    var url: String
    var quality: Int? = nil
    var srt: String? = nil
    var lessonTitle: String? = nil
    var allowOther: Bool? = nil
}

nonisolated struct MediaStartResponse: Decodable, Sendable {
    var jobId: String
}

nonisolated struct MediaJobRequest: Encodable, Sendable {
    var jobId: String
}

nonisolated enum MediaJobState: String, Sendable {
    case queued, running, done, error, canceled

    init(raw: String) {
        switch raw.lowercased() {
        case "queued": self = .queued
        case "done": self = .done
        case "error": self = .error
        case "canceled", "cancelled": self = .canceled
        // Bilinmeyen ara durumlar "çalışıyor" sayılır.
        default: self = .running
        }
    }

    var isFinished: Bool { self == .done || self == .error || self == .canceled }
}

nonisolated struct MediaStatus: Decodable, Sendable {
    var state: MediaJobState
    var progress: Double
    var message: String
    var fileId: String?
    var bytes: Int64?
    var error: String?
    /// Sunucunun uyarıları (ör. altyazı yumuşak iz olarak eklendi); iş yine de başarılıdır.
    var warnings: [String] = []

    private enum CodingKeys: String, CodingKey { case state, progress, message, fileId, bytes, error, warnings }

    init(state: MediaJobState, progress: Double = 0, message: String = "", fileId: String? = nil, bytes: Int64? = nil, error: String? = nil,
         warnings: [String] = []) {
        self.state = state
        self.progress = progress
        self.message = message
        self.fileId = fileId
        self.bytes = bytes
        self.error = error
        self.warnings = warnings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = MediaJobState(raw: try c.decodeIfPresent(String.self, forKey: .state) ?? "running")
        progress = min(max(try c.decodeIfPresent(Double.self, forKey: .progress) ?? 0, 0), 1)
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        fileId = try c.decodeIfPresent(String.self, forKey: .fileId)
        bytes = try c.decodeIfPresent(Int64.self, forKey: .bytes)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        warnings = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}

// MARK: - Dosya aktarımı (ilerleme izleme)

/// Yükleme/indirme görevinin bayt ilerlemesi (URLSession görev vekili; değerler kilitle okunur, arayüz yoklar).
nonisolated final class TransferMonitor: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        lock.withLock { self.task = task }
    }

    /// 0...1; beklenen bilinmiyorsa 0.
    var uploadFraction: Double {
        lock.withLock {
            guard let task, task.countOfBytesExpectedToSend > 0 else { return 0 }
            return min(1, Double(task.countOfBytesSent) / Double(task.countOfBytesExpectedToSend))
        }
    }

    var downloadFraction: Double {
        lock.withLock {
            guard let task, task.countOfBytesExpectedToReceive > 0 else { return 0 }
            return min(1, Double(task.countOfBytesReceived) / Double(task.countOfBytesExpectedToReceive))
        }
    }

    var receivedBytes: Int64 { lock.withLock { task?.countOfBytesReceived ?? 0 } }
}

nonisolated enum FileTransfer {
    /// Büyük dosyalar: istek boşta kalma süresi 10 dk, toplam 1 saat.
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// `fileId`/`uploadId` yalnız rastgele kimliktir (UUID ya da 32 hex): yol olarak kullanılamaz.
    static func isValidID(_ id: String) -> Bool {
        (id.count == 32 || id.count == 36) && id.allSatisfy { $0.isHexDigit || $0 == "-" }
    }

    /// Sunucunun hata gövdesinden ({"error":{"message"}}) okunabilir ileti; yoksa genel.
    static func errorMessage(from data: Data, status: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any], let message = error["message"] as? String, !message.isEmpty {
            return message
        }
        return "Sunucu hatası (\(status)). Lütfen tekrar dene."
    }
}

// MARK: - Arama ve etiket (#38, #40)

nonisolated struct LessonSearchEntry: Encodable, Sendable {
    var id: String
    var title: String
    var chapters: [VideoChapter]
    var keyPoints: [NoteKeyPoint]
}

nonisolated struct YouTubeSearchRequest: Encodable, Sendable {
    var question: String
    var lessons: [LessonSearchEntry]
}

nonisolated struct AISearchHit: Decodable, Hashable, Sendable {
    var lessonId: String
    var time: Double
    var reason: String

    private enum CodingKeys: String, CodingKey { case lessonId, time, reason }

    init(lessonId: String, time: Double, reason: String) {
        self.lessonId = lessonId
        self.time = time
        self.reason = reason
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lessonId = try c.decodeIfPresent(String.self, forKey: .lessonId) ?? ""
        time = try c.decodeIfPresent(Double.self, forKey: .time) ?? 0
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
    }
}

nonisolated struct YouTubeSearchResponse: Decodable, Sendable {
    var results: [AISearchHit]

    private enum CodingKeys: String, CodingKey { case results }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        results = try c.decodeIfPresent([AISearchHit].self, forKey: .results) ?? []
    }
}

nonisolated struct YouTubeTagsRequest: Encodable, Sendable {
    var title: String
    var summary: String
}

nonisolated struct YouTubeTagsResponse: Decodable, Sendable {
    var subject: String
    var topics: [String]

    private enum CodingKeys: String, CodingKey { case subject, topics }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
        topics = try c.decodeIfPresent([String].self, forKey: .topics) ?? []
    }
}

// MARK: - Kütüphane geneli Sor (#39)

nonisolated struct LibraryAskVideoParagraph: Encodable, Sendable {
    var start: Double
    var text: String
}

nonisolated struct LibraryAskVideo: Encodable, Sendable {
    var id: String
    var title: String
    var paragraphs: [LibraryAskVideoParagraph]
}

/// Mevcut `LibraryAskRequest`'in video dersleri de taşıyan sürümü (`videos` boşsa gönderilmez).
nonisolated struct LibraryAskRequestV2: Encodable, Sendable {
    var question: String
    var language: String
    var episodes: [LibraryAskEpisode]
    var videos: [LibraryAskVideo]?
}

/// Atıf: podcast bölümü (`episodeId`, bölüm sırası) ya da video dersi (`kind: "video"`, `id`, `time`).
nonisolated struct LibraryCitationV2: Decodable, Hashable, Sendable {
    var kind: String
    var episodeId: UUID?
    var videoId: UUID?
    var chapterIndex: Int?
    var time: Double?
    var quote: String

    var isVideo: Bool { kind == "video" }

    private enum CodingKeys: String, CodingKey { case kind, id, episodeId, chapterIndex, time, quote }

    init(kind: String = "episode", episodeId: UUID? = nil, videoId: UUID? = nil, chapterIndex: Int? = nil, time: Double? = nil, quote: String = "") {
        self.kind = kind
        self.episodeId = episodeId
        self.videoId = videoId
        self.chapterIndex = chapterIndex
        self.time = time
        self.quote = quote
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "episode"
        let rawID = try c.decodeIfPresent(String.self, forKey: .id)
        let rawEpisode = try c.decodeIfPresent(String.self, forKey: .episodeId)
        if kind == "video" {
            videoId = rawID.flatMap(UUID.init(uuidString:))
        } else {
            episodeId = (rawEpisode ?? rawID).flatMap(UUID.init(uuidString:))
        }
        chapterIndex = try c.decodeIfPresent(Int.self, forKey: .chapterIndex)
        time = try c.decodeIfPresent(Double.self, forKey: .time)
        quote = try c.decodeIfPresent(String.self, forKey: .quote) ?? ""
    }
}

nonisolated struct LibraryAnswerV2: Decodable, Sendable {
    var answer: String
    var citations: [LibraryCitationV2]

    private enum CodingKeys: String, CodingKey { case answer, citations }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        answer = try c.decodeIfPresent(String.self, forKey: .answer) ?? ""
        // Çözülemeyen tek bir atıf tüm cevabı düşürmesin.
        citations = (try? c.decodeIfPresent([LibraryCitationV2].self, forKey: .citations)) ?? []
    }
}

// MARK: - İstemci

extension APIClient {
    @concurrent
    nonisolated func youtubeFeed(url: String) async throws -> YouTubeFeed {
        try await post("/v1/youtube/feed", YouTubeFeedRequest(url: url))
    }

    @concurrent
    nonisolated func mediaStart(_ request: MediaStartRequest) async throws -> String {
        let response: MediaStartResponse = try await post("/v1/media/start", request)
        return response.jobId
    }

    @concurrent
    nonisolated func mediaStatus(jobId: String) async throws -> MediaStatus {
        try await post("/v1/media/status", MediaJobRequest(jobId: jobId))
    }

    /// İptal en iyi çabayla yapılır; hata yutulur (iş zaten bitmiş/unutulmuş olabilir).
    @concurrent
    nonisolated func mediaCancel(jobId: String) async {
        let _: Ack? = try? await post("/v1/media/cancel", MediaJobRequest(jobId: jobId))
    }

    @concurrent
    nonisolated func youtubeSearch(_ request: YouTubeSearchRequest) async throws -> [AISearchHit] {
        let response: YouTubeSearchResponse = try await post("/v1/youtube/search", request)
        return response.results
    }

    @concurrent
    nonisolated func youtubeTags(_ request: YouTubeTagsRequest) async throws -> YouTubeTagsResponse {
        try await post("/v1/youtube/tags", request)
    }

    @concurrent
    nonisolated func libraryAsk(_ request: LibraryAskRequestV2) async throws -> LibraryAnswerV2 {
        try await post("/v1/library-ask", request)
    }

    /// `GET /v1/files/{id}`: dosya diske akıtılır (bellekte tutulmaz) ve `destination`'a taşınır. İlerleme `monitor`dan okunur.
    @concurrent
    nonisolated func downloadFile(id: String, to destination: URL, monitor: TransferMonitor? = nil) async throws {
        guard FileTransfer.isValidID(id) else {
            throw APIError(status: 0, code: "bad_file", message: "Sunucu geçersiz bir dosya kimliği gönderdi.")
        }
        guard let token = PersonalToken.current, !token.isEmpty else {
            throw APIError(status: 401, code: "unauthorized", message: "Sunucu erişim anahtarı girilmemiş. Ayarlar → Sunucu bölümünden ekle.")
        }
        let install = InstallID.current.uuidString.lowercased()
        let temp: URL
        let response: URLResponse
        do {
            var request = URLRequest(url: Config.apiBaseURL.appending(path: "/v1/files/\(id)"))
            request.setValue(token, forHTTPHeaderField: "x-personal-token")
            request.setValue(install, forHTTPHeaderField: "X-Install-Id")
            (temp, response) = try await FileTransfer.session.download(for: request, delegate: monitor)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.network(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = (try? Data(contentsOf: temp, options: .mappedIfSafe)) ?? Data()
            try? FileManager.default.removeItem(at: temp)
            throw APIError(status: status, code: status == 404 ? "not_found" : "http_\(status)",
                           message: status == 404 ? "Dosya sunucuda artık yok (24 saat sonra silinir). İşi yeniden başlat."
                                                  : FileTransfer.errorMessage(from: body.prefix(4096), status: status))
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: temp.path)[.size] as? Int64) ?? 0
        guard size > 0 else {
            try? FileManager.default.removeItem(at: temp)
            throw APIError(status: status, code: "empty", message: "İndirilen dosya boş geldi.")
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
    }

    /// `PUT /v1/upload/{id}`: dosya gövdesi diskten gönderilir (belleğe alınmaz). Sunucunun saydığı bayt sayısını döndürür.
    @concurrent
    nonisolated func uploadRecording(file: URL, id: String, contentType: String, monitor: TransferMonitor? = nil) async throws -> Int64 {
        guard FileTransfer.isValidID(id) else {
            throw APIError(status: 0, code: "bad_file", message: "Geçersiz yükleme kimliği.")
        }
        guard let token = PersonalToken.current, !token.isEmpty else {
            throw APIError(status: 401, code: "unauthorized", message: "Sunucu erişim anahtarı girilmemiş. Ayarlar → Sunucu bölümünden ekle.")
        }
        let install = InstallID.current.uuidString.lowercased()
        let data: Data
        let response: URLResponse
        do {
            var request = URLRequest(url: Config.apiBaseURL.appending(path: "/v1/upload/\(id.lowercased())"))
            request.httpMethod = "PUT"
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            request.setValue(token, forHTTPHeaderField: "x-personal-token")
            request.setValue(install, forHTTPHeaderField: "X-Install-Id")
            (data, response) = try await FileTransfer.session.upload(for: request, fromFile: file, delegate: monitor)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.network(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError(status: status, code: status == 413 ? "too_large" : "http_\(status)",
                           message: status == 413 ? "Dosya 500 MB sınırını aşıyor."
                                                  : FileTransfer.errorMessage(from: data.prefix(4096), status: status))
        }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["bytes"] as? NSNumber)?.int64Value ?? 0
    }
}
