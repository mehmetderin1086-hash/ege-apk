import Foundation

nonisolated struct APIError: LocalizedError, Sendable {
    var status: Int
    var code: String
    var message: String
    var retryAfter: Double?
    /// Sunucunun/motorun makinece okunan ek nedeni ("claude_unavailable", "claude_unreachable").
    var reason: String? = nil

    var errorDescription: String? { message }
    /// Claude hesabı isteği kabul etmedi (kredi, kullanım sınırı, anahtar, yoğunluk) ya da motor çalışmıyor: bir süre yedek yol kullanılır.
    var claudeUnavailable: Bool { reason == "claude_unavailable" }
    /// Uygulama içi Claude bu isteği yanıtlayamadı (hesap kabul etmedi ya da bağlantı kurulamadı): aynı istek yedek yoldan denenebilir.
    var canUseBackup: Bool { claudeUnavailable || reason == "claude_unreachable" }
    /// Yedek yol (sunucu) hiç yanıt veremedi: bağlantı yok ya da erişim anahtarı eksik/geçersiz.
    var isBackupUnreachable: Bool { code == "network" || isUnauthorized }
    var isUnauthorized: Bool { status == 401 }
    var needsLongQuotaPause: Bool { status == 429 && (retryAfter ?? 0) > 900 }

    static func network(_ error: Error) -> APIError {
        let urlError = error as? URLError
        let message: String = switch urlError?.code {
        case .notConnectedToInternet?: "İnternet bağlantısı yok."
        case .timedOut?: "Sunucu zamanında yanıt vermedi. Lütfen tekrar dene."
        case .cannotConnectToHost?, .cannotFindHost?: "Sunucuya ulaşılamadı."
        default: "Bağlantı hatası: \(error.localizedDescription)"
        }
        return APIError(status: 0, code: "network", message: message)
    }
}

// MARK: - İstek/yanıt tipleri

nonisolated enum SourcePayload: Encodable, Sendable {
    case pdf(data: Data, name: String)
    case image(data: Data, name: String)
    case text(String, name: String)

    private enum Keys: String, CodingKey { case kind, mimeType, data, text, name }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case let .pdf(data, name):
            try c.encode("pdf", forKey: .kind)
            try c.encode("application/pdf", forKey: .mimeType)
            try c.encode(data.base64EncodedString(), forKey: .data)
            try c.encode(name, forKey: .name)
        case let .image(data, name):
            try c.encode("image", forKey: .kind)
            try c.encode("image/jpeg", forKey: .mimeType)
            try c.encode(data.base64EncodedString(), forKey: .data)
            try c.encode(name, forKey: .name)
        case let .text(text, name):
            try c.encode("text", forKey: .kind)
            try c.encode(text, forKey: .text)
            try c.encode(name, forKey: .name)
        }
    }

    var byteCount: Int {
        switch self {
        case let .pdf(data, _), let .image(data, _): data.count
        case let .text(text, _): text.utf8.count
        }
    }
}

nonisolated struct ScriptRequest: Encodable, Sendable {
    var settings: PodcastSettings
    var sources: [SourcePayload]
}

nonisolated struct ScriptResponse: Decodable, Sendable {
    var jobToken: String
    var script: PodcastScript
    /// #47: senaryoyu yazan model (sunucu bildirirse).
    var model: String? = nil
    /// Senaryoyu uygulama içi motor yazdı: `jobToken` motorun kendi belirtecidir, sunucudaki seslendirme onu tanımaz.
    var local: Bool? = nil
    /// Sunucudaki seslendirmede kullanılabilen iş belirteci; senaryoyu motor yazdıysa yoktur (seslendirmeden önce sunucudan
    /// ses işi istenir).
    var serverJobToken: String? { local == true ? nil : jobToken }
}

nonisolated struct ServerStatus: Decodable, Sendable {
    struct Counts: Decodable, Sendable, Equatable { var podcasts: Int; var questions: Int; var study: Int; var tools: Int? = nil }
    /// Sunucudaki XTTS (SesLab) sesleri; `cloned`: yalnız referans kaydıyla klonlanmış (eğitilmemiş) ses.
    struct XttsVoice: Codable, Sendable, Equatable, Identifiable { var id: String; var name: String; var cloned: Bool? }
    /// `engines`: SesLab'da kurulu motorlar ("xtts", "chatterbox", "voxcpm", "trendyol"); eski sunucu bildirmez.
    /// `mac`: kullanıcının Mac'indeki SesLab o an bağlı mı (XTTS ve Chatterbox V3 orada üretilir; kapalıysa sunucuda).
    /// `macEngines`: Mac bağlıyken orada üretilen motorlar (seçicide "· Mac" olarak görünür).
    struct Xtts: Decodable, Sendable { var voices: [XttsVoice]; var engines: [String]?; var mac: Bool?; var macEngines: [String]? }
    struct TTS: Decodable, Sendable { var xtts: Xtts? }
    var ok: Bool?
    var tts: TTS?
    var today: Counts?
    var limits: Counts?
    var features: [String]?
}

nonisolated struct TTSTurn: Encodable, Sendable {
    var speaker: Speaker
    var text: String
    var style: String
}

nonisolated struct TTSRequest: Encodable, Sendable {
    var jobToken: String
    var sceneIndex: Int
    var turns: [TTSTurn]
    /// Telaffuz sözlüğü (sunucu seslendirmeden önce uygular; iş belirteci asıl metinle doğrulanır).
    var replacements: [Pronunciation]?
    /// #13: >0 ise sunucu önbelleği atlar.
    var take: Int?
}

nonisolated struct AudioJobRequest: Encodable, Sendable {
    var script: PodcastScript
    var settings: PodcastSettings
    var previousJobToken: String?
    /// "full" | "edit"
    var purpose: String?
}
nonisolated struct AudioJobResponse: Decodable, Sendable {
    var jobToken: String
}

nonisolated struct TTSResponse: Decodable, Sendable {
    var audio: String
    var durationSec: Double
    /// Ses sunucunun önbelleğinden geldi (aynı metin, ses ve telaffuz sözlüğüyle daha önce üretilmiş).
    var cached: Bool?
    /// Turların (cümlelerin) ses içindeki yerleri, sn (madde 3); eski sunucuda yok.
    var turns: [TurnTime]?
    /// Sunucuda hizalanmış kelime zamanları (madde 12): söylenen biçimin her kelimesi; eski sunucuda yok.
    var words: [WordTime]?
}
/// Hizalanmış bir kelime: başlangıç, bitiş (sn), güven skoru (0'a yakın iyi; nil: hizalanamadı, komşulardan dolduruldu).
nonisolated struct WordTime: Codable, Sendable, Equatable {
    var word: String; var start: Double; var end: Double; var score: Double?; var interpolated: Bool?
}
/// Bir turun (cümlenin) seste başladığı ve bittiği an (sn).
nonisolated struct TurnTime: Codable, Sendable, Equatable {
    var start: Double; var end: Double
}

nonisolated struct StudyRequest: Encodable, Sendable {
    var title: String
    var sourceNotes: String
    var level: String
    var quizCount: Int
    var flashcardCount: Int
    var conceptCount: Int?
    var transcript: String?
}

/// Sesli soru isteği: bölümün bağlamı, kip, önceki soru-cevaplar ve (oturum sırasında eklenen) soru.
nonisolated struct VoiceAskRequest: Encodable, Sendable {
    var title: String
    var sourceNotes: String
    var chapterTitle: String
    var chapterText: String
    var host: Host
    /// "ask" | "teach"
    var mode: String?
    var history: [LiveQA]?
    /// Kullanıcının yazıya dökülmüş sorusu (ya da "Bana anlat" kipinde anlatımı). Günlük hak her soruda sunucuda düşer.
    var question: String = ""
}

nonisolated struct LiveQA: Codable, Hashable, Sendable { var q: String; var a: String }

nonisolated struct VoiceAskResponse: Decodable, Sendable {
    var answer: String
}

/// Ana Sayfa asistanı: soru (yazılı ya da yazıya dökülmüş), önceki konuşma ve telefonun kısa durum özeti.
nonisolated struct AssistantRequest: Encodable, Sendable {
    struct Attachment: Encodable, Sendable { var name: String; var kind: String }
    var message: String
    var history: [LiveQA]
    var context: String
    /// Kullanıcının eklediği dosyalar (yalnız ad ve tür; içerik telefonda kalır, modül işler).
    var attachments: [Attachment] = []
}

/// Asistanın sözlü cevabı ve uygulamada yapılacak eylem (kapalı liste: none, open, route, settings, textSize, import, topicVideo, play, scan).
nonisolated struct AssistantResponse: Decodable, Sendable {
    struct Action: Decodable, Sendable, Equatable { var type: String; var target: String?; var text: String? }
    var say: String
    var action: Action
}

nonisolated private struct EmptyBody: Codable, Sendable {}
nonisolated struct ErrorEnvelope: Decodable, Sendable {
    struct Body: Decodable, Sendable { var code: String; var message: String; var reason: String? }
    var error: Body
}

// MARK: - İstemci

nonisolated struct APIClient: Sendable {
    static let shared = APIClient()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600   // 60 dk'lık senaryo birkaç dakika sürebilir
        config.timeoutIntervalForResource = 900
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Ders sesi indirme: sunucu aynı anda tek ses indirir (öncekinin bitmesini bekletir, en fazla 10 dk) ve kendi
    /// indirmesi de 10 dk sürebilir; bu sürede hiç bayt gelmez. Ardından ~160 MB'a varan yanıt akar.
    static let longRequestTimeout: TimeInterval = 1800
    static let longResourceTimeout: TimeInterval = 3600

    private let longSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIClient.longRequestTimeout
        config.timeoutIntervalForResource = APIClient.longResourceTimeout
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    func status() async throws -> ServerStatus {
        do {
            var status: ServerStatus = try await post("/v1/status", EmptyBody())
            // Senaryoyu uygulama yazar: sunucunun kalıcı senaryo işleri kullanılmaz (istek `/v1/script` ile uygulama içinde işlenir).
            if Backend.engineReady { status.features?.removeAll { $0 == "scriptJobs" } }
            return status
        } catch let error as APIError where error.code == "network" && Backend.engineReady {
            // Sunucuya ulaşılamıyor: Claude'a dayanan özellikler uygulama içinde çalışmayı sürdürür.
            return try await EmbeddedEngine.shared.call("/v1/status", EmptyBody())
        }
    }

    func scriptModels() async throws -> ScriptModelCatalog {
        try await post("/v1/script-models", EmptyBody())
    }

    func script(_ request: ScriptRequest) async throws -> ScriptResponse {
        try await post("/v1/script", request)
    }

    func audioJob(_ request: AudioJobRequest) async throws -> AudioJobResponse {
        try await post("/v1/audio-job", request)
    }

    /// `readings`: "Claude + Chirp"te sahne için hazırlanan okunuşlar; telaffuz sözlüğüne eklenir (kullanıcının kayıtları önceliklidir).
    func remoteTTS(_ request: TTSRequest, engine: SpeechEngine, readings: [Pronunciation] = []) async throws -> TTSResponse {
        let path: String
        switch engine {
        // "Claude + Chirp"te de sesi Chirp üretir; Claude'un payı `readings`'tir.
        case .chirp, .claude: path = "/v1/chirp-tts"
        case .azure: path = "/v1/azure-tts"
        case .xtts: path = "/v1/xtts-tts"
        case .edge: path = "/v1/edge-tts"
        case .huggingface: path = "/v1/huggingface-tts"
        case .apple, .supertonic, .piper, .ema: throw APIError(status: 400, code: "provider", message: "Bu motorun sesi iPhone’da üretilir.")
        }
        // SesLab CPU'da üretir: uzun sahne dakikalarca bayt göndermeden hazırlanır.
        return try await post(path, Pronunciations.attach(to: request, adding: readings), longRunning: engine == .xtts)
    }

    /// "Claude + Chirp": sahnedeki formül, simge ve kısaltmaların okunuşları (uygulama içinde, Claude ile). Metin değişmez; okunuşlar
    /// sahnenin seslendirme isteğine telaffuz sözlüğü olarak eklenir.
    func speechReadings(_ turns: [TTSTurn], language: PodcastLanguage) async throws -> [Pronunciation] {
        struct Request: Encodable, Sendable { var turns: [TTSTurn]; var lang: String }
        struct Response: Decodable, Sendable { var readings: [Pronunciation] }
        let response: Response = try await post("/v1/speech-readings", Request(turns: turns, lang: language.rawValue))
        return response.readings
    }

    func chirpTTS(_ request: TTSRequest) async throws -> TTSResponse {
        try await post("/v1/chirp-tts", Pronunciations.attach(to: request))
    }

    func study(_ request: StudyRequest) async throws -> StudyPack {
        try await post("/v1/study", request)
    }

    /// Sesli soru: soru cihazda yazıya dökülür, cevabı sunucuda Claude yazar.
    func voiceAsk(_ request: VoiceAskRequest) async throws -> VoiceAskResponse {
        try await post("/v1/voice-ask", request)
    }

    func assistant(_ request: AssistantRequest) async throws -> AssistantResponse {
        try await post("/v1/assistant", request)
    }

    /// `delegate`: görev düzeyinde URLSession vekili (ör. indirme ilerlemesi); verilmezse oturumunki.
    /// `longRunning`: yanıtı dakikalarca bayt göndermeden hazırlanan istekler (ders sesi) için uzun zaman aşımlı oturum.
    func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String, _ body: Body, delegate: (any URLSessionTaskDelegate)? = nil, longRunning: Bool = false
    ) async throws -> Response {
        guard Backend.usesEngine(path) else { return try await server(path, body, delegate: delegate, longRunning: longRunning) }
        do {
            return try await EmbeddedEngine.shared.call(path, body)
        } catch let engineError as APIError where engineError.canUseBackup {
            // Uygulama içi Claude yanıt veremedi: istek yedeğe (sunucu) gider. Sorun hesaptaysa motor bir süre askıdadır (bkz.
            // `EmbeddedEngine.shared`); yalnız bağlantı koptuysa (ör. uygulama arka plana alındı) sonraki istek yine uygulama içinde denenir.
            do {
                return try await server(path, body, delegate: delegate, longRunning: longRunning)
            } catch let error as APIError where error.isBackupUnreachable {
                // Yedeğe de ulaşılamadı: asıl neden (ör. kredi bitti) gösterilir, "sunucuya ulaşılamadı" değil.
                throw engineError
            }
        }
    }

    /// İsteği sunucuya gönderir.
    private func server<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String, _ body: Body, delegate: (any URLSessionTaskDelegate)?, longRunning: Bool
    ) async throws -> Response {
        var request = URLRequest(url: Config.apiBaseURL.appending(path: path))
        if longRunning { request.timeoutInterval = Self.longRequestTimeout }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if QSModelPlan.astraOnly { request.setValue("astra-only", forHTTPHeaderField: "X-Ikra-Model-Policy") }
        request.setValue(InstallID.current.uuidString.lowercased(), forHTTPHeaderField: "X-Install-Id")
        guard let token = PersonalToken.current, !token.isEmpty else {
            throw APIError(status: 401, code: "unauthorized", message: "Sunucu erişim anahtarı girilmemiş. Ayarlar → Sunucu bölümünden ekle.")
        }
        request.setValue(token, forHTTPHeaderField: "X-Personal-Token")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await (longRunning ? longSession : session).data(for: request, delegate: delegate)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.network(error)
        }

        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let retryAfter = (http?.value(forHTTPHeaderField: "Retry-After")).flatMap(Double.init)
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                throw APIError(status: status, code: envelope.error.code, message: envelope.error.message, retryAfter: retryAfter, reason: envelope.error.reason)
            }
            throw APIError(status: status, code: "http_\(status)", message: "Sunucu hatası (\(status)). Lütfen tekrar dene.")
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError(status: status, code: "decode", message: "Sunucudan beklenmeyen yanıt geldi.")
        }
    }

}
