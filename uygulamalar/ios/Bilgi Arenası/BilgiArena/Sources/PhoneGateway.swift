import Foundation
import ProxyKit

/// App-local boundary: remote configuration never reaches the engine.
enum PhonePolicy {
    static let hosts: Set<String> = [
        "api.anthropic.com", "platform.claude.com", "console.anthropic.com", "claude.ai",
        "chatgpt.com", "auth.openai.com", "api.openai.com",
        "texttospeech.googleapis.com", "generativelanguage.googleapis.com", "oauth2.googleapis.com", "daily-cloudcode-pa.googleapis.com",
        "cloudcode-pa.googleapis.com", "daily-cloudcode-pa.sandbox.googleapis.com",
        "api.x.ai", "api.mistral.ai", "api.groq.com", "api.deepseek.com", "api.cohere.com",
        "dashscope.aliyuncs.com", "dashscope-intl.aliyuncs.com", "portal.qwen.ai", "chat.qwen.ai",
        "openrouter.ai"
    ]
    static func allows(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", let host = url.host?.lowercased(), url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return false }
        return hosts.contains(host) || host.range(of:"^[a-z0-9-]{2,40}\\.tts\\.speech\\.microsoft\\.com$",options:.regularExpression) != nil
    }
    static func localState(_ original: ProxyState) -> ProxyState {
        var state = original
        state.remote = RemoteProxy(enabled: false, fallbackOnError: false)
        state.fallbacks = [:]
        state.apiProviders = state.apiProviders.filter { allows(URL(string: $0.baseURL)) }
        // Keep live generation independent of shared cache and budget settings.
        state.tasarruf.yanitOnbellegi = false
        return state
    }
}

/// Only refreshed token fields are merged back; the CLI Proxy app's settings stay intact.
struct PhoneAccountStore: SecretStore {
    let shared: any SecretStore
    init(shared: any SecretStore = KeychainSecretStore(accessGroup: KeychainSecretStore.sharedGroup)) { self.shared = shared }
    static func decode(_ data: Data) throws -> ProxyState { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return try d.decode(ProxyState.self, from: data) }
    static func encode(_ state: ProxyState) throws -> Data { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return try e.encode(state) }
    func load() throws -> Data? {
        guard let data = try shared.load() else { return nil }
        return try Self.encode(PhonePolicy.localState(Self.decode(data)))
    }
    func save(_ data: Data) throws {
        let updated = try Self.decode(data)
        guard let currentData = try shared.load() else { throw QuizError("CLI Proxy hesap kasası bulunamadı. Önce CLI Proxy uygulamasında hesap ekle.") }
        var current = try Self.decode(currentData)
        for new in updated.oauth {
            guard let i = current.oauth.firstIndex(where: { $0.qualifiedId == new.qualifiedId }), current.oauth[i].refreshOwner == .telefon else { continue }
            // A concurrent refresh in another app wins over an older token.
            if let existing = current.oauth[i].expiresAt, let incoming = new.expiresAt, existing > incoming { continue }
            current.oauth[i].accessToken = new.accessToken
            current.oauth[i].refreshToken = new.refreshToken
            current.oauth[i].expiresAt = new.expiresAt
            current.oauth[i].metadata = new.metadata
        }
        try shared.save(Self.encode(current))
    }
    func clear() throws { throw QuizError("Ortak hesaplar Bilgi Arenası içinden silinemez.") }
}

final class PhoneRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
actor PhoneTraffic {
    static let shared = PhoneTraffic()
    private var hosts: [String: Int] = [:]
    func record(_ host: String) { hosts[host, default: 0] += 1 }
    func snapshot() -> [String: Int] { hosts }
}
struct PhoneTransport: HTTPTransport {
    private let base: URLSessionTransport
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 70; config.timeoutIntervalForResource = 150
        base = URLSessionTransport(session: URLSession(configuration: config, delegate: PhoneRedirectGuard(), delegateQueue: nil))
    }
    func send(_ request: URLRequest) async throws -> UpstreamResponse {
        guard PhonePolicy.allows(request.url) else { throw ProxyError.badRequest("Bu bağlantı iPhone sağlayıcı listesinde bulunmuyor. VPS yönlendirmesi engellendi.") }
        try Task.checkCancellation()
        await PhoneTraffic.shared.record(request.url?.host ?? "")
        var bounded = request; bounded.timeoutInterval = min(request.timeoutInterval, 70)
        return try await base.send(bounded)
    }
}

struct PhoneModel: Identifiable, Codable, Equatable {
    let id: String
    let owner: String
    var family: String {
        if id.contains("claude") { return "Claude" }
        if id.contains("gpt") || id.contains("codex") { return "ChatGPT" }
        if id.contains("gemini") { return "Gemini" }
        if id.contains("qwen") { return "Qwen" }
        if id.contains("grok") { return "Grok" }
        return owner
    }
    var textCapable: Bool { !["image", "imagine", "tts", "audio", "embedding", "whisper", "live", "transcri", "ocr"].contains { id.lowercased().contains($0) } }
}
struct ModelCheck: Codable, Identifiable {
    var id: String { model }
    let model: String
    let date: Date
    let success: Bool
    let milliseconds: Int
    let status: String
}
struct PhoneInventory: Codable {
    let accountCount: Int
    let expiringAccounts: Int
    let providerCount: Int
    let models: [PhoneModel]
    let serverDisabled: Bool
}

actor PhoneGateway {
    static let shared = PhoneGateway()
    private let vault: Vault
    private let engine: ProxyEngine
    private var lastFailure: String?
    #if DEBUG
    private var lastContent: String?
    func contentDiagnostic() -> String? { lastContent }
    struct ProxyVoiceProof: Codable {
        let kind: String
        var model: String?; var route: String?; var status: Int?
        var audioBytes = 0; var textCharacters = 0; var note: String?
    }
    /// Exercise the same on-device ProxyEngine used by CLI Proxy, with server fallback disabled.
    func probeProxyVoice(_ kind: String) async -> ProxyVoiceProof {
        var proof = ProxyVoiceProof(kind:kind)
        var state = await vault.reload()
        var target = engine
        do {
            if kind == "claude-api" {
                guard state.apiProviders.contains(where:{ $0.enabled && $0.kind == .anthropic && !$0.apiKey.isEmpty }) else {
                    proof.note = "CLI Proxy kasasında etkin Claude API sağlayıcısı yok."; return proof
                }
                // Test API access without changing shared OAuth/routing preferences.
                state.oauth = []; state.remote = .init(enabled:false,fallbackOnError:false); state.fallbacks = [:]
                target = ProxyEngine(vault:Vault(store:MemorySecretStore(try PhoneAccountStore.encode(state))),transport:PhoneTransport())
            }
            let router = ModelRouter(state:state)
            let catalog = router.localModels().map(\.id)
            let model: String
            var method = "POST", path = "/v1/chat/completions", query: [String:String] = [:], payload: [String:Any] = [:]
            if kind == "openai-live" || kind == "gemini-live" {
                model = kind == "openai-live" ? "gpt-realtime-2.1-mini" : "gemini-3.8-live"
                method = "GET"; path = kind == "openai-live" ? "/v1/realtime" : "/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
                query = ["model":model]
            } else {
                let candidates = kind == "codex" ? ["gpt-6-luna","gpt-6.1-sol"] : kind == "antigravity" ? ["gemini-3.8-flash","gemini-3.8-flash-tiered"] : ["claude-sonnet-5-5","claude-haiku-4-5"]
                guard let selected = candidates.first(where:catalog.contains) else { proof.note = "Bu ailede bağlı yerel model yok."; return proof }
                model = selected
                payload = ["model":model,"stream":false,"max_tokens":96,"messages":[["role":"user","content":"Sadece Hazırım de. Ses destekleniyorsa sesli yanıtla."]],"modalities":["text","audio"],"audio":["voice":"alloy","format":"wav"]]
                if kind == "codex" { payload["reasoning_effort"] = "low" }
            }
            proof.model = model; proof.route = router.resolve(model).description
            var headers = ["authorization":"Bearer "+state.localKey,"x-cliproxy-allow-fallback":"false","x-proxy-cache":"off"]
            if method == "GET" { headers["upgrade"] = "websocket"; headers["connection"] = "Upgrade"; headers["sec-websocket-version"] = "13"; headers["sec-websocket-key"] = Data(repeating:1,count:16).base64EncodedString() }
            let response = await target.handle(.init(method:method,path:path,query:query,headers:headers,body:try JSONSerialization.data(withJSONObject:payload)))
            proof.status = response.status
            var data = Data()
            for try await part in response.body { data += part; guard data.count <= 2_000_000 else { throw QuizError("Kabul yanıtı boyut sınırını aştı.") } }
            if let json = try JSONSerialization.jsonObject(with:data) as? [String:Any], let choices = json["choices"] as? [[String:Any]], let message = choices.first?["message"] as? [String:Any] {
                proof.textCharacters = (message["content"] as? String)?.count ?? 0
                if let audio = message["audio"] as? [String:Any], let encoded = audio["data"] as? String { proof.audioBytes = Data(base64Encoded:encoded)?.count ?? 0 }
            }
            proof.note = response.status == 404 && method == "GET" ? "Telefon CLI Proxy motorunda bu WebSocket ucu yok." : proof.audioBytes > 0 ? "Ses verisi alındı; oynatma ayrıca doğrulanmalı." : (200..<300).contains(response.status) ? "İstek kabul edildi, ses verisi dönmedi; canlı ses başarısı değil." : "İstek HTTP \(response.status) döndürdü; canlı ses alınamadı."
        } catch { proof.note = "Telefon CLI Proxy denemesi tamamlanamadı." }
        return proof
    }
    #endif
    func diagnostic() -> String? { lastFailure }
    init(store: any SecretStore = PhoneAccountStore(), transport: any HTTPTransport = PhoneTransport()) {
        vault = Vault(store: store)
        engine = ProxyEngine(vault: vault, transport: transport)
    }
    func inventory() async throws -> PhoneInventory {
        let state = await vault.reload()
        if await vault.lockedReason != nil { throw QuizError("CLI Proxy ortak hesap kasası okunamadı. Uygulamayı açıp hesapları kontrol et.") }
        let models = ModelRouter(state: state).localModels().map { PhoneModel(id: $0.id, owner: $0.owner) }.sorted { $0.id < $1.id }
        return PhoneInventory(accountCount: state.oauth.filter(\.enabled).count,
                              expiringAccounts: state.oauth.filter { $0.enabled && $0.expiresSoon() && $0.refreshOwner == .sunucu }.count,
                              providerCount: state.apiProviders.filter(\.enabled).count, models: models,
                              serverDisabled: !state.remote.isUsable && state.remote.baseURL.isEmpty)
    }
    func liveConnection(_ engine: QuizLiveEngine) async throws -> QuizLiveConnection {
        let state = await vault.reload()
        let host = engine == .openAI ? "api.openai.com" : "generativelanguage.googleapis.com"
        guard engine != .chained, let provider = state.apiProviders.first(where:{ $0.enabled && URL(string:$0.baseURL)?.host == host && !$0.apiKey.isEmpty }) else { throw QuizError("CLI Proxy kasasında bu canlı sağlayıcı için API bağlantısı yok.") }
        let model = engine == .openAI ? "gpt-realtime-2.1-mini" : (provider.models.first { $0.contains("live") && !$0.contains("transcribe") } ?? "gemini-3.8-live")
        var request: URLRequest
        if engine == .openAI {
            var parts = URLComponents(string:"wss://api.openai.com/v1/realtime")!; parts.queryItems = [.init(name:"model",value:model)]
            request = URLRequest(url:parts.url!,timeoutInterval:12); request.setValue("Bearer "+provider.apiKey,forHTTPHeaderField:"Authorization")
        } else {
            var parts = URLComponents(string:"wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")!
            parts.queryItems = [.init(name:"key",value:provider.apiKey)]; request = URLRequest(url:parts.url!,timeoutInterval:12)
        }
        return QuizLiveConnection(request:request,model:model)
    }
    func googleSpeechToken(account: String) async throws -> String {
        let state = await vault.reload()
        guard var value = state.oauth.first(where:{ $0.enabled && ($0.provider == .gemini || $0.provider == .antigravity) && (account.isEmpty || $0.metadata["email"] == account) }) else { throw QuizError("CLI Proxy içinde Google ses hesabı bulunamadı.") }
        if value.expiresSoon() {
            // Google refresh tokens are non-rotating; keep shared ownership unchanged.
            value = try await OAuthClient(transport:PhoneTransport()).refreshedGoogleAccount(value)
            let updated = value
            try await vault.updateAccount(value.qualifiedId) { $0.accessToken = updated.accessToken; $0.refreshToken = updated.refreshToken; $0.expiresAt = updated.expiresAt }
        }
        return value.accessToken
    }
    func speech(model: String, voice: String, text: String, language: String) async throws -> Data {
        let state = await vault.reload()
        guard ModelRouter(state:state).localModels().contains(where:{ $0.id == model }) else { throw QuizError("Bu ses modeli CLI Proxy hesabında bulunmuyor.") }
        let router = ModelRouter(state:state)
        if case .api(let name) = router.resolve(model), let provider = router.provider(name), provider.kind == .geminiNative {
            return try await geminiSpeech(provider:provider,model:model,voice:voice,text:text,language:language)
        }
        let body = try JSONSerialization.data(withJSONObject:["model":model,"voice":voice,"input":text,"response_format":"mp3","instructions":"Read exactly the supplied text in "+language+". Speak clearly and naturally."])
        let request = ProxyRequest(method:"POST",path:"/v1/audio/speech",headers:["authorization":"Bearer "+state.localKey,"x-cliproxy-allow-fallback":"false"],body:body)
        let response = await engine.handle(request)
        guard response.status == 200 else { throw QuizError(response.status == 429 ? "CLI Proxy ses kotası veya API kredisi yetersiz (HTTP 429). Başka soru sesi seçebilirsin." : "CLI Proxy ses isteği tamamlanamadı (HTTP \(response.status)).") }
        var data = Data()
        for try await chunk in response.body { try Task.checkCancellation(); data.append(chunk); guard data.count <= 12_000_000 else { throw QuizError("Ses dosyası boyut sınırını aştı.") } }
        return data
    }
    private func geminiSpeech(provider: APIKeyProvider, model: String, voice: String, text: String, language: String) async throws -> Data {
        let upstream = provider.upstreamModel(model)
        guard upstream.range(of:"^[A-Za-z0-9._-]+$",options:.regularExpression) != nil, let base = URL(string:provider.baseURL), base.host == "generativelanguage.googleapis.com" else { throw QuizError("Gemini ses sağlayıcısı desteklenmiyor.") }
        let root = base.path.contains("v1") ? base : base.appendingPathComponent("v1beta")
        let url = root.appendingPathComponent("models/"+upstream+":generateContent")
        var request = URLRequest(url:url,timeoutInterval:60); request.httpMethod = "POST"
        request.setValue(provider.apiKey,forHTTPHeaderField:"x-goog-api-key"); request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody = try Self.geminiSpeechBody(text:text,language:language,voice:voice)
        let response = try await PhoneTransport().send(request)
        guard response.status == 200 else { throw QuizError(response.status == 402 ? "Gemini ses API kredisi yetersiz (HTTP 402). Chirp veya Azure seçebilirsin." : "Gemini ses isteği tamamlanamadı (HTTP \(response.status)).") }
        return try Self.geminiAudio(try await response.collect(limit:16_000_000))
    }
    static func geminiSpeechBody(text: String, language: String, voice: String) throws -> Data {
        guard QuestionVoiceAPI.chirpVoices.contains(voice) else { throw QuizError("Gemini için Kore veya Puck gibi bir Gemini sesi seç.") }
        return try JSONSerialization.data(withJSONObject:["contents":[["role":"user","parts":[["text":text]]]],"generationConfig":["responseModalities":["AUDIO"],"speechConfig":["languageCode":language,"voiceConfig":["prebuiltVoiceConfig":["voiceName":voice]]]]])
    }
    static func geminiAudio(_ data: Data) throws -> Data {
        guard let json = try JSONSerialization.jsonObject(with:data) as? [String:Any], let candidates = json["candidates"] as? [[String:Any]], let content = candidates.first?["content"] as? [String:Any], let parts = content["parts"] as? [[String:Any]], let inline = parts.compactMap({ $0["inlineData"] as? [String:Any] }).first, let encoded = inline["data"] as? String, let audio = Data(base64Encoded:encoded), audio.count > 100, let mime = inline["mimeType"] as? String else { throw QuizError("Gemini geçerli ses döndürmedi.") }
        if QuestionVoiceAPI.validAudio(audio) { return audio }
        guard mime.hasPrefix("audio/L16") || mime.hasPrefix("audio/pcm"), audio.count.isMultiple(of:2), audio.count <= 12_000_000 else { throw QuizError("Gemini ses biçimi desteklenmiyor.") }
        let ratePart = mime.components(separatedBy:";").first { $0.trimmingCharacters(in:.whitespaces).hasPrefix("rate=") }
        let rate = ratePart.flatMap { Int($0.trimmingCharacters(in:.whitespaces).dropFirst(5)) } ?? 24000
        guard [16000,22050,24000,44100,48000].contains(rate) else { throw QuizError("Gemini ses hızı desteklenmiyor.") }
        var wav = Data("RIFF".utf8)
        func put<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of:&little) { wav.append(contentsOf:$0) } }
        put(UInt32(audio.count+36)); wav.append(Data("WAVEfmt ".utf8)); put(UInt32(16)); put(UInt16(1)); put(UInt16(1)); put(UInt32(rate)); put(UInt32(rate*2)); put(UInt16(2)); put(UInt16(16)); wav.append(Data("data".utf8)); put(UInt32(audio.count)); wav.append(audio); return wav
    }
    func chat(model: String, system: String, user: String, maxTokens: Int = 6500) async throws -> String {
        do { return try await chatOnce(model: model, system: system, user: user, maxTokens: maxTokens) }
        catch {
            try Task.checkCancellation()
            let message = (error as? QuizError)?.message ?? ""
            guard message.contains("HTTP 502") || message.contains("HTTP 504") else { throw error }
            try await Task.sleep(nanoseconds: 500_000_000)
            return try await chatOnce(model: model, system: system, user: user, maxTokens: maxTokens)
        }
    }
    private func chatOnce(model: String, system: String, user: String, maxTokens: Int) async throws -> String {
        let state = await vault.reload()
        guard ModelRouter(state: state).localModels().contains(where: { $0.id == model }) else { throw QuizError("Bu model için iPhone'da bağlı hesap bulunamadı. CLI Proxy hesaplarını kontrol et.") }
        var payload: [String: Any] = ["model":model,"messages":[["role":"system","content":system],["role":"user","content":user]],"max_tokens":maxTokens,"stream":false]
        if model.hasPrefix("gpt-") { payload["reasoning_effort"] = "low" }
        let request = ProxyRequest(method: "POST", path: "/v1/chat/completions", headers: ["authorization":"Bearer " + state.localKey,"x-proxy-cache":"off","x-cliproxy-allow-fallback":"false"], body: try JSONSerialization.data(withJSONObject: payload))
        try Task.checkCancellation()
        let response = await engine.handle(request)
        var data = Data()
        for try await chunk in response.body {
            try Task.checkCancellation(); data.append(chunk)
            guard data.count <= 1_000_000 else { throw QuizError("Model yanıtı boyut sınırını aştı.") }
        }
        guard (200..<300).contains(response.status) else {
            #if DEBUG
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let e = json["error"] as? [String: Any], var text = e["message"] as? String {
                let secrets = state.oauth.flatMap { [$0.accessToken, $0.refreshToken ?? ""] } + state.apiProviders.map(\.apiKey) + [state.localKey]
                for secret in secrets where !secret.isEmpty { text = text.replacingOccurrences(of: secret, with: "[gizli]") }
                text = text.replacingOccurrences(of: #"https?://[^\s]+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+"#, with: "[adres]", options: .regularExpression)
                lastFailure = String(text.prefix(400))
            }
            #endif
            throw QuizError(Self.errorMessage(response.status))
        }
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = value["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String, !content.isEmpty else { throw QuizError("Model okunabilir bir metin döndürmedi.") }
        #if DEBUG
        lastContent = String(content.prefix(100_000))
        #endif
        return content
    }
    static func errorMessage(_ status: Int) -> String {
        switch status {
        case 401,403: return "Model oturumu veya yetkisi geçersiz. iPhone'daki CLI Proxy uygulamasında hesabı yenile."
        case 429: return "Modelin kullanım sınırına ulaşıldı. Başka bir model seç veya daha sonra dene."
        case 400,404: return "Bu model bu hesapta soru üretimini desteklemiyor veya artık sunulmuyor."
        case 503: return "iPhone'da kullanılabilir hesap yok ya da erişim belirteci yenilenmeli. CLI Proxy hesaplarını kontrol et."
        default: return "iPhone model isteği tamamlanamadı (HTTP \(status))."
        }
    }
    func probe(_ model: String) async -> ModelCheck {
        let start = Date()
        do {
            _ = try await chat(model: model, system: "Kısa bir bağlantı testi yapılıyor. Tek kelime Türkçe yanıt ver.", user: "Hazır yaz.", maxTokens: 512)
            return ModelCheck(model: model, date: Date(), success: true, milliseconds: Int(Date().timeIntervalSince(start)*1000), status: "Yanıt doğrulandı")
        } catch {
            if (error as? QuizError)?.message == "Model okunabilir bir metin döndürmedi.", !Task.isCancelled {
                do {
                    _ = try await chat(model: model, system: "Bağlantı testi. Kısa Türkçe cevap ver.", user: "Hazır yaz.", maxTokens: 1600)
                    return ModelCheck(model: model, date: Date(), success: true, milliseconds: Int(Date().timeIntervalSince(start)*1000), status: "Yanıt doğrulandı")
                } catch { }
            }
            return ModelCheck(model: model, date: Date(), success: false, milliseconds: Int(Date().timeIntervalSince(start)*1000), status: error is CancellationError ? "İptal edildi" : (error as? QuizError)?.message ?? "Sağlayıcı bağlantısı tamamlanamadı")
        }
    }
}
