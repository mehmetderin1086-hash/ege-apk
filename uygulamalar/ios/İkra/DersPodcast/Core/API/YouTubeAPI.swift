import Foundation

// YouTube Ders Stüdyosu uçları (sunucu: /v1/youtube/info, /start, /status, /cancel, /ask, /audio). Alan adları sözleşmeyle birebir.
// Çözümleme sunucu sürümleri arasında sağlam olsun diye diziler eksikse boş, metinler eksikse "" kabul edilir.

// MARK: - Video bilgisi

nonisolated struct VideoChapter: Codable, Hashable, Sendable {
    var title: String
    var start: Double
}

nonisolated struct CaptionTrack: Codable, Hashable, Sendable {
    var lang: String
    var name: String
    var auto: Bool
}

nonisolated struct VideoInfo: Codable, Hashable, Sendable {
    var id: String
    var url: String
    var title: String
    var channel: String
    var duration: Double
    var thumbnail: String?
    var chapters: [VideoChapter]
    var captions: [CaptionTrack]
    var language: String?
    /// Gömülü oynatmaya izin var mı (yt-dlp playable_in_embed). Eski sunucu yanıtlarında yok → `isEmbeddable` true sayar.
    var embeddable: Bool? = nil
    /// "youtube" | "vimeo" | "dailymotion" | "other" (eski sunucu yanıtlarında yok).
    var platform: String? = nil
}

nonisolated extension VideoInfo {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? "https://www.youtube.com/watch?v=\(id)"
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        channel = try c.decodeIfPresent(String.self, forKey: .channel) ?? ""
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        thumbnail = try c.decodeIfPresent(String.self, forKey: .thumbnail)
        chapters = try c.decodeIfPresent([VideoChapter].self, forKey: .chapters) ?? []
        captions = try c.decodeIfPresent([CaptionTrack].self, forKey: .captions) ?? []
        language = try c.decodeIfPresent(String.self, forKey: .language)
        embeddable = try c.decodeIfPresent(Bool.self, forKey: .embeddable)
        platform = try c.decodeIfPresent(String.self, forKey: .platform)
    }

    /// Bilinmiyorsa gömülebilir kabul edilir.
    var isEmbeddable: Bool { embeddable ?? true }

    /// Elle hazırlanmış altyazılar (otomatik olmayanlar).
    var manualCaptions: [CaptionTrack] { captions.filter { !$0.auto } }
    var hasCaptions: Bool { !captions.isEmpty }
}

nonisolated struct PlaylistEntry: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var duration: Double?
    var url: String
}

nonisolated struct PlaylistInfo: Codable, Hashable, Sendable {
    var id: String
    var title: String
    var entries: [PlaylistEntry]
}

nonisolated extension PlaylistInfo {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        entries = try c.decodeIfPresent([PlaylistEntry].self, forKey: .entries) ?? []
    }
}

nonisolated struct YouTubeInfoRequest: Encodable, Sendable {
    var url: String
    /// Izinli alan listesi dışındaki https adresleri için kullanıcı onayı ("Bu siteyi dene").
    var allowOther: Bool? = nil
}

nonisolated struct YouTubeInfoResponse: Codable, Hashable, Sendable {
    var kind: String          // "video" | "playlist"
    var video: VideoInfo?
    var playlist: PlaylistInfo?

    var isPlaylist: Bool { kind == "playlist" && playlist != nil }
}

// MARK: - İş başlatma ve durum

nonisolated enum TranscriptMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto, captions, ai
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: "Otomatik"
        case .captions: "Yalnızca altyazı"
        case .ai: "Yapay zekâ"
        }
    }
    var detail: String {
        switch self {
        case .auto: "Altyazı varsa kullanılır, yoksa ses yapay zekâ ile yazıya dökülür."
        case .captions: "Yalnızca YouTube altyazısı; altyazı yoksa iş durur."
        case .ai: "Ses doğrudan yapay zekâ ile yazıya dökülür (daha yavaş, altyazısız videolarda en iyisi)."
        }
    }
}

nonisolated struct YouTubeStartRequest: Codable, Sendable, Hashable {
    var url: String
    var mode: TranscriptMode
    var language: String?
    var translateTo: String?
    var start: Double?
    var end: Double?
    var keyframes: Bool
    var notes: Bool
    /// Sınıf kaydı: `PUT /v1/upload/{id}` ile yüklenen dosyanın kimliği; verilirse `url` gönderilmez, `title` kullanılır.
    var uploadId: String? = nil
    var title: String? = nil
    var allowOther: Bool? = nil

    private enum CodingKeys: String, CodingKey {
        case url, mode, language, translateTo, start, end, keyframes, notes, uploadId, title, allowOther
    }
}

nonisolated extension YouTubeStartRequest {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        mode = try c.decodeIfPresent(TranscriptMode.self, forKey: .mode) ?? .auto
        language = try c.decodeIfPresent(String.self, forKey: .language)
        translateTo = try c.decodeIfPresent(String.self, forKey: .translateTo)
        start = try c.decodeIfPresent(Double.self, forKey: .start)
        end = try c.decodeIfPresent(Double.self, forKey: .end)
        keyframes = try c.decodeIfPresent(Bool.self, forKey: .keyframes) ?? false
        notes = try c.decodeIfPresent(Bool.self, forKey: .notes) ?? true
        uploadId = try c.decodeIfPresent(String.self, forKey: .uploadId)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        allowOther = try c.decodeIfPresent(Bool.self, forKey: .allowOther)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Yükleme kimliği varsa `url` gönderilmez (sözleşme: url yerine uploadId + title).
        if uploadId == nil { try c.encode(url, forKey: .url) }
        try c.encode(mode, forKey: .mode)
        try c.encodeIfPresent(language, forKey: .language)
        try c.encodeIfPresent(translateTo, forKey: .translateTo)
        try c.encodeIfPresent(start, forKey: .start)
        try c.encodeIfPresent(end, forKey: .end)
        try c.encode(keyframes, forKey: .keyframes)
        try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(uploadId, forKey: .uploadId)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(allowOther, forKey: .allowOther)
    }
}

nonisolated struct YouTubeStartResponse: Decodable, Sendable {
    var jobId: String
}

nonisolated struct YouTubeStatusRequest: Encodable, Sendable {
    var jobId: String
}

nonisolated enum YouTubeJobState: String, Codable, Sendable {
    case queued, running, done, error, cancelled
}

nonisolated struct YouTubeJobStatus: Decodable, Sendable {
    var state: YouTubeJobState
    var progress: Double
    var step: String
    var error: String?
    var result: VideoTranscript?

    private enum CodingKeys: String, CodingKey { case state, progress, step, error, result }

    init(state: YouTubeJobState, progress: Double = 0, step: String = "", error: String? = nil, result: VideoTranscript? = nil) {
        self.state = state
        self.progress = progress
        self.step = step
        self.error = error
        self.result = result
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(String.self, forKey: .state)
        // Bilinmeyen ara durumlar (sunucu yeni adım eklerse) "çalışıyor" sayılır.
        state = YouTubeJobState(rawValue: raw) ?? .running
        progress = min(max(try c.decodeIfPresent(Double.self, forKey: .progress) ?? 0, 0), 1)
        step = try c.decodeIfPresent(String.self, forKey: .step) ?? ""
        error = try c.decodeIfPresent(String.self, forKey: .error)
        result = try c.decodeIfPresent(VideoTranscript.self, forKey: .result)
    }
}

// MARK: - İptal

nonisolated struct YouTubeCancelRequest: Encodable, Sendable {
    var jobId: String
}

nonisolated struct YouTubeCancelResponse: Decodable, Sendable {
    var ok: Bool
    /// "cancelled" | "done" | "error" (iş iptalden önce bitmiş olabilir).
    var state: YouTubeJobState

    private enum CodingKeys: String, CodingKey { case ok, state }

    init(ok: Bool = true, state: YouTubeJobState) {
        self.ok = ok
        self.state = state
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? true
        let raw = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        // Bilinmeyen değer: iş hâlâ sürüyor sayılır (bekleyen listesinde kalır).
        state = YouTubeJobState(rawValue: raw) ?? .running
    }
}

/// İptal isteğinin sonucu: sunucunun bildirdiği durum, iş yok (404) ya da sunucuya ulaşılamadı.
nonisolated enum YouTubeCancelResult: Equatable, Sendable {
    case state(YouTubeJobState)
    case notFound
    case unreachable
}

// MARK: - Ses (uygulama içi dinleme)

nonisolated struct YouTubeAudioRequest: Encodable, Sendable {
    var url: String
    /// İzinli alan listesi dışındaki siteler: ders içe aktarılırken kullanıcı onaylamıştı.
    var allowOther: Bool? = nil
}

/// Sunucu yanıtı: base64 m4a. Büyük olabilir (en fazla ~120 MB ses); çözme ana iş parçacığı dışında yapılır.
nonisolated struct YouTubeAudioResponse: Decodable, Sendable {
    var audio: String
    var mimeType: String
    var duration: Double
    var bytes: Int

    private enum CodingKeys: String, CodingKey { case audio, mimeType, duration, bytes }

    init(audio: String, mimeType: String = "audio/mp4", duration: Double = 0, bytes: Int = 0) {
        self.audio = audio
        self.mimeType = mimeType
        self.duration = duration
        self.bytes = bytes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        audio = try c.decodeIfPresent(String.self, forKey: .audio) ?? ""
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType) ?? "audio/mp4"
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        bytes = try c.decodeIfPresent(Int.self, forKey: .bytes) ?? 0
    }

    /// iPhone'da oynatılabilen kapsayıcılar (m4a/AAC). webm/opus kabul edilmez.
    static func isPlayable(mimeType: String) -> Bool {
        let base = mimeType.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        return ["audio/mp4", "audio/m4a", "audio/x-m4a", "audio/aac", "audio/mp4a-latm"].contains(base)
    }

    /// base64 → ses verisi ("data:" önekini de kabul eder). Boş, bozuk ya da oynatılamayan biçimde hata.
    func decoded() throws -> YouTubeAudio {
        guard Self.isPlayable(mimeType: mimeType) else {
            throw APIError(status: 0, code: "format", message: "Bu videonun sesi iPhone’da oynatılabilir biçimde alınamadı.")
        }
        var base64 = Substring(audio)
        if base64.hasPrefix("data:"), let comma = base64.firstIndex(of: ",") { base64 = base64[base64.index(after: comma)...] }
        guard let data = Data(base64Encoded: String(base64), options: .ignoreUnknownCharacters), !data.isEmpty else {
            throw APIError(status: 0, code: "decode", message: "Ses verisi çözülemedi.")
        }
        return YouTubeAudio(data: data, mimeType: mimeType, duration: duration)
    }
}

/// Çözülmüş ses (dosyaya yazılmaya hazır).
nonisolated struct YouTubeAudio: Sendable {
    var data: Data
    var mimeType: String
    var duration: Double
}

/// Ses indirmesinin bayt ilerlemesi. Sunucu sesi YouTube'dan alıp hazırlayana kadar hiç bayt gelmez (alınan 0);
/// yanıt akmaya başlayınca alınan/beklenen bilinir. URLSession görev vekili; değerler kilitle okunur.
nonisolated final class TransferProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        lock.withLock { self.task = task }
    }

    /// (alınan, beklenen) bayt; beklenen bilinmiyorsa ≤ 0.
    var bytes: (received: Int64, expected: Int64) {
        lock.withLock { (task?.countOfBytesReceived ?? 0, task?.countOfBytesExpectedToReceive ?? 0) }
    }
}

// MARK: - Transkript

nonisolated struct TranscriptSegment: Codable, Hashable, Sendable {
    var start: Double
    var end: Double
    var text: String
    /// Kelime başlama zamanları (sn, mutlak); `text` boşlukla bölünmüş kelime sayısı kadar. Yalnızca kelime zamanlı altyazıda var.
    var w: [Double]? = nil
}

nonisolated struct TranscriptParagraph: Codable, Hashable, Sendable {
    var start: Double
    var end: Double
    var text: String
}

nonisolated struct TranscriptTranslation: Codable, Hashable, Sendable {
    var language: String
    var paragraphs: [TranscriptParagraph]
}

nonisolated struct NoteKeyPoint: Codable, Hashable, Sendable {
    var text: String
    var time: Double
}

nonisolated struct NoteConcept: Codable, Hashable, Sendable {
    var name: String
    var definition: String
    var time: Double
}

nonisolated struct NoteFormula: Codable, Hashable, Sendable {
    var name: String
    var expression: String
    var meaning: String
    var time: Double
}

nonisolated struct NoteQuestion: Codable, Hashable, Sendable {
    var question: String
    var answer: String
    var time: Double
}

nonisolated struct LectureNotes: Codable, Hashable, Sendable {
    var summary: String
    var keyPoints: [NoteKeyPoint]
    var concepts: [NoteConcept]
    var formulas: [NoteFormula]
    var questions: [NoteQuestion]
    var examTips: [String]
}

nonisolated extension LectureNotes {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        keyPoints = try c.decodeIfPresent([NoteKeyPoint].self, forKey: .keyPoints) ?? []
        concepts = try c.decodeIfPresent([NoteConcept].self, forKey: .concepts) ?? []
        formulas = try c.decodeIfPresent([NoteFormula].self, forKey: .formulas) ?? []
        questions = try c.decodeIfPresent([NoteQuestion].self, forKey: .questions) ?? []
        examTips = try c.decodeIfPresent([String].self, forKey: .examTips) ?? []
    }
}

nonisolated struct Keyframe: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var time: Double
    /// base64 JPEG. Cihazda kaydedilirken boşaltılır; görsel `VideoFiles.keyframeURL` dosyasındadır.
    var image: String
    var caption: String
    var text: String
}

nonisolated extension Keyframe {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        time = try c.decodeIfPresent(Double.self, forKey: .time) ?? 0
        image = try c.decodeIfPresent(String.self, forKey: .image) ?? ""
        caption = try c.decodeIfPresent(String.self, forKey: .caption) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
    }
}

nonisolated struct VideoTranscript: Codable, Hashable, Sendable {
    var video: VideoInfo
    var source: String               // "captions" | "auto-captions" | "ai"
    var language: String
    var segments: [TranscriptSegment]
    var paragraphs: [TranscriptParagraph]
    var chapters: [VideoChapter]
    var translation: TranscriptTranslation?
    var notes: LectureNotes?
    var keyframes: [Keyframe]
    var warnings: [String]
}

nonisolated extension VideoTranscript {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        video = try c.decode(VideoInfo.self, forKey: .video)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "ai"
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? (video.language ?? "")
        segments = try c.decodeIfPresent([TranscriptSegment].self, forKey: .segments) ?? []
        paragraphs = try c.decodeIfPresent([TranscriptParagraph].self, forKey: .paragraphs) ?? []
        chapters = try c.decodeIfPresent([VideoChapter].self, forKey: .chapters) ?? video.chapters
        translation = try c.decodeIfPresent(TranscriptTranslation.self, forKey: .translation)
        notes = try c.decodeIfPresent(LectureNotes.self, forKey: .notes)
        keyframes = try c.decodeIfPresent([Keyframe].self, forKey: .keyframes) ?? []
        warnings = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }

    /// Kaynağın Türkçe adı (rozetlerde).
    static func sourceTitle(_ source: String) -> String {
        switch source {
        case "captions": "Altyazı"
        case "auto-captions": "Otomatik altyazı"
        case "ai": "Yapay zekâ"
        default: source
        }
    }

    /// Görseller dosyaya yazıldıktan sonra kaydedilecek hâl: base64 alanları boş.
    var withoutImages: VideoTranscript {
        var copy = self
        copy.keyframes = keyframes.map { var k = $0; k.image = ""; return k }
        return copy
    }

    /// Düz metin (bölüm başlıklarıyla); podcast kaynağı, paylaşım veya kütüphaneye sor için.
    func plainText(includeTimes: Bool = false) -> String {
        let sortedChapters = chapters.sorted { $0.start < $1.start }
        var lines: [String] = []
        var nextChapter = 0
        for p in paragraphs {
            while nextChapter < sortedChapters.count, sortedChapters[nextChapter].start <= p.start + 0.5 {
                lines.append("\n## \(sortedChapters[nextChapter].title)")
                nextChapter += 1
            }
            lines.append(includeTimes ? "[\(VideoTime.string(p.start))] \(p.text)" : p.text)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Videoya sor

nonisolated struct AskParagraph: Codable, Hashable, Sendable {
    var start: Double
    var text: String
}

nonisolated struct YouTubeAskRequest: Encodable, Sendable {
    var title: String
    var question: String
    var paragraphs: [AskParagraph]

    static let maxQuestion = 500
    static let maxTotalCharacters = 400_000

    /// Sunucu sınırlarına kırpılmış istek (soru ≤ 500, paragraflar toplam ≤ 400.000 karakter).
    static func make(title: String, question: String, paragraphs: [TranscriptParagraph]) -> YouTubeAskRequest {
        var budget = maxTotalCharacters
        var kept: [AskParagraph] = []
        for p in paragraphs {
            guard budget > 0 else { break }
            let text = String(p.text.prefix(budget))
            budget -= text.count
            kept.append(AskParagraph(start: p.start, text: text))
        }
        return YouTubeAskRequest(title: title,
                                 question: String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxQuestion)),
                                 paragraphs: kept)
    }
}

nonisolated struct AskCitation: Codable, Hashable, Sendable {
    var time: Double
    var quote: String
}

nonisolated struct YouTubeAskResponse: Codable, Hashable, Sendable {
    var answer: String
    var citations: [AskCitation]
}

nonisolated extension YouTubeAskResponse {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        answer = try c.decodeIfPresent(String.self, forKey: .answer) ?? ""
        citations = try c.decodeIfPresent([AskCitation].self, forKey: .citations) ?? []
    }
}

// MARK: - İstemci

extension APIClient {
    // @concurrent: büyük yanıtlar (base64 kareler) ana iş parçacığı dışında çözülür.
    @concurrent
    nonisolated func youtubeInfo(url: String, allowOther: Bool = false) async throws -> YouTubeInfoResponse {
        try await post("/v1/youtube/info", YouTubeInfoRequest(url: url, allowOther: allowOther ? true : nil))
    }

    @concurrent
    nonisolated func youtubeStart(_ request: YouTubeStartRequest) async throws -> String {
        let response: YouTubeStartResponse = try await post("/v1/youtube/start", request)
        return response.jobId
    }

    @concurrent
    nonisolated func youtubeStatus(jobId: String) async throws -> YouTubeJobStatus {
        try await post("/v1/youtube/status", YouTubeStatusRequest(jobId: jobId))
    }

    @concurrent
    nonisolated func youtubeAsk(_ request: YouTubeAskRequest) async throws -> YouTubeAskResponse {
        try await post("/v1/youtube/ask", request)
    }

    /// Çalışan ya da sıradaki işi durdurur. Bilinmeyen iş → APIError 404.
    @concurrent
    nonisolated func youtubeCancel(jobId: String) async throws -> YouTubeCancelResponse {
        try await post("/v1/youtube/cancel", YouTubeCancelRequest(jobId: jobId))
    }

    /// Dersin sesini (m4a) indirir; JSON ve base64 çözme ana iş parçacığı dışında. `progress` bayt ilerlemesini izlemek için.
    @concurrent
    nonisolated func youtubeAudio(url: String, progress: TransferProgress? = nil) async throws -> YouTubeAudio {
        let response: YouTubeAudioResponse
        do {
            // Uzun zaman aşımı: sunucu tek indirme kilidinde bekletip sesi hazırlarken hiç bayt göndermez.
            response = try await post("/v1/youtube/audio",
                                      YouTubeAudioRequest(url: url, allowOther: ImportLinks.needsAllowOther(url) ? true : nil),
                                      delegate: progress, longRunning: true)
        } catch let error as APIError where error.status == 413 && error.code.hasPrefix("http_") {
            throw APIError(status: 413, code: "too_large", message: "Video 3 saatten uzun; sesi uygulamaya indirilemiyor.")
        }
        return try response.decoded()
    }
}
