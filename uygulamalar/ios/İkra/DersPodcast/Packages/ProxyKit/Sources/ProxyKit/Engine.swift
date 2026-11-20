import Foundation

public struct ProxyRequest: Sendable {
    public var method: String
    public var path: String
    public var query: [String: String]
    public var headers: [String: String]   // küçük harfli anahtarlar
    public var body: Data

    public init(method: String, path: String, query: [String: String] = [:], headers: [String: String] = [:], body: Data = Data()) {
        self.method = method.uppercased(); self.path = path; self.query = query
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        self.body = body
    }
    public func header(_ n: String) -> String? { headers[n.lowercased()] }
}

public struct ProxyResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: AsyncThrowingStream<Data, Error>
    public var streaming: Bool

    public static func json(_ j: JSON, status: Int = 200) -> ProxyResponse {
        let d = j.data()
        return ProxyResponse(status: status, headers: ["Content-Type": "application/json"],
                             body: AsyncThrowingStream { c in c.yield(d); c.finish() }, streaming: false)
    }
    public static func error(_ e: ProxyError, anthropic: Bool = false) -> ProxyResponse {
        let msg = e.localizedDescription
        if anthropic {
            let type = e.status == 401 ? "authentication_error" : e.status == 429 ? "rate_limit_error" : e.status == 400 ? "invalid_request_error" : e.status == 404 ? "not_found_error" : "api_error"
            return .json(["type": "error", "error": ["type": .string(type), "message": .string(msg)]], status: e.status)
        }
        return .json(["error": ["message": .string(msg), "type": "cliproxy_error", "code": .int(e.status)]], status: e.status)
    }
}

/// Telefondaki vekil motoru: sunucudaki CLI Proxy API'nin uçlarını karşılar.
public final class ProxyEngine: Sendable {
    public let vault: Vault
    public let tokens: TokenManager
    public let log: UsageLog
    let transport: HTTPTransport
    let remoteModels = RemoteModelCache()
    public let onbellek = YanitOnbellegi()
    public let kota = KotaDurumu()
    public let sayac = SayacDeposu()
    let tekil = Tekillestirici()
    let geminiSignatures = GeminiSignatureCache()

    static let anthropicVersion = "2023-06-01"
    static let oauthBeta = "oauth-2025-04-20,claude-code-20250219"
    static let claudeURL = "https://api.anthropic.com/v1/messages"
    static let codexURL = "https://chatgpt.com/backend-api/codex/responses"
    static let googleRoot = "https://generativelanguage.googleapis.com"
    /// Telefonda karşılanan (gövdesinde "model" olan) uçlar
    public static let modelEndpoints: Set<String> = ["/v1/chat/completions", "/v1/messages", "/v1/messages/count_tokens", "/v1/responses",
                                                     "/v1/audio/speech", "/v1/images/generations", "/v1/embeddings"]

    public init(vault: Vault, transport: HTTPTransport = URLSessionTransport(), log: UsageLog = UsageLog()) {
        self.vault = vault
        self.transport = transport
        self.log = log
        self.tokens = TokenManager(vault: vault, transport: transport)
    }

    // MARK: giriş noktası

    public func handle(_ req: ProxyRequest) async -> ProxyResponse {
        let isAnthropic = req.path.hasSuffix("/messages") || req.path.hasSuffix("/count_tokens")
        if req.method == "OPTIONS" {
            return ProxyResponse(status: 204, headers: ["Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "*", "Access-Control-Allow-Methods": "GET, POST, OPTIONS"], body: AsyncThrowingStream { $0.finish() }, streaming: false)
        }
        if req.path == "/healthz" || req.path == "/readyz" || req.path == "/" {
            return .json(["durum": "hazır", "uygulama": "CLI Proxy (iPhone)"])
        }
        await vault.reloadIfStale()
        let state = await vault.state
        guard authorized(req, state) else {
            return .error(.unauthorized("Geçersiz ya da eksik API anahtarı"), anthropic: isAnthropic)
        }
        do {
            return try await dispatch(req, state)
        } catch let e as ProxyError {
            return .error(e, anthropic: isAnthropic)
        } catch {
            return .error(.upstream(status: 502, message: error.localizedDescription), anthropic: isAnthropic)
        }
    }

    func authorized(_ req: ProxyRequest, _ s: ProxyState) -> Bool {
        var token = req.header("x-api-key") ?? req.header("x-goog-api-key") ?? req.query["key"]
        if let a = req.header("authorization"), a.lowercased().hasPrefix("bearer ") { token = String(a.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
        guard let token, !token.isEmpty else { return false }
        if token == s.localKey { return true }
        let h = ClientKey.hash(token)
        return s.clientKeys.contains { $0.enabled && $0.sha256 == h }
    }

    // MARK: yönlendirme

    func dispatch(_ req: ProxyRequest, _ s: ProxyState) async throws -> ProxyResponse {
        let router = ModelRouter(state: s)
        let p = req.path.hasPrefix("/v1/v1/") ? String(req.path.dropFirst(3)) : req.path

        if req.method == "GET" && p == "/v1/models" { return .json(await modelList(s, router)) }

        // Gemini yerel uçları
        if p.hasPrefix("/v1beta/") || p.hasPrefix("/v1alpha/") {
            return try await withFallback(req, s, model: geminiModel(p, req.body) ?? "gemini", route: .api("gemini")) {
                try await self.geminiNative(req, p, s, router)
            }
        }

        guard req.method == "POST", Self.modelEndpoints.contains(p) else {
            // Model uçları dışındaki her şey (ör. sunucudaki math/ders/kaynak servisleri) olduğu gibi sunucuya gider.
            if s.remote.isUsable { return try await remotePassthrough(req, s, model: "-") }
            throw ProxyError.notFound("Uç bulunamadı: \(req.method) \(p)")
        }
        let body: JSON
        do { body = try JSON.parse(req.body) } catch { throw ProxyError.badRequest("Gövde JSON değil") }
        guard let model = body["model"]?.string else { throw ProxyError.badRequest("model alanı gerekli") }
        let route = router.resolve(model)

        let (kisa, lider) = try await tasarrufOnKontrol(req, s, p, body, model: model)
        if let kisa { return kisa }
        let anahtar = YanitOnbellegi.uygun(body, istekBasligi: req.header("x-proxy-cache")) && s.tasarruf.yanitOnbellegi && p != "/v1/messages/count_tokens"
            && p != "/v1/embeddings" && p != "/v1/audio/speech" && p != "/v1/images/generations"
            ? YanitOnbellegi.anahtar(path: p, body: req.body) : nil
        let sonuc: ProxyResponse
        do { sonuc = try await dispatchIc(req, s, p, body, model: model, route: route, router: router) } catch {
            if lider, let anahtar { await tekil.bitir(anahtar, nil) }   // bekleyenler askıda kalmasın
            throw error
        }
        return await onbellegeAl(sonuc, anahtar: anahtar, ttl: s.tasarruf.onbellekSuresi, tekil: lider)
    }

    func dispatchIc(_ req: ProxyRequest, _ s: ProxyState, _ p: String, _ body: JSON, model: String, route: Route, router: ModelRouter) async throws -> ProxyResponse {
        return try await withFallback(req, s, model: model, route: route) {
            switch (p, route) {
            case (_, .remote):
                return try await self.remotePassthrough(req, s, model: model)
            case ("/v1/chat/completions", .antigravity(let up, let think)):
                return try await self.antigravityCanonical(try Inbound.openAIChat(body), model: up, thinking: think, out: .openAI, path: p)
            case ("/v1/messages", .antigravity(let up, let think)):
                return try await self.antigravityCanonical(try Inbound.anthropic(body), model: up, thinking: think, out: .anthropic, path: p)
            case ("/v1/chat/completions", .claude):
                return try await self.claudeCanonical(try Inbound.openAIChat(body), out: .openAI, path: p)
            case ("/v1/chat/completions", .codex):
                return try await self.codexCanonical(try Inbound.openAIChat(body), out: .openAI, path: p)
            case ("/v1/chat/completions", .api(let name)):
                let prov = try self.need(router, name)
                do { return try await self.apiPassthrough(req, body, provider: prov, endpoint: "/chat/completions", model: model) }
                catch let e as ProxyError {
                    guard let sub = self.antigravitySubstitute(prov, model, e, router) else { throw e }
                    return try await self.antigravityCanonical(try Inbound.openAIChat(body), model: sub.model, thinking: sub.thinking, out: .openAI, path: p)
                }
            case ("/v1/messages", .claude):
                return try await self.claudePassthrough(req, body, path: p, countTokens: false)
            case ("/v1/messages", .codex):
                return try await self.codexCanonical(try Inbound.anthropic(body), out: .anthropic, path: p)
            case ("/v1/messages", .api(let name)):
                let prov = try self.need(router, name)
                do { return try await self.apiCanonical(try Inbound.anthropic(body), provider: prov, path: p) }
                catch let e as ProxyError {
                    guard let sub = self.antigravitySubstitute(prov, model, e, router) else { throw e }
                    return try await self.antigravityCanonical(try Inbound.anthropic(body), model: sub.model, thinking: sub.thinking, out: .anthropic, path: p)
                }
            case ("/v1/messages/count_tokens", .claude):
                return try await self.claudePassthrough(req, body, path: p, countTokens: true)
            case ("/v1/messages/count_tokens", _):
                let c = try Inbound.anthropic(body)
                let chars = c.system.joined().count + c.messages.reduce(0) { $0 + $1.text.count }
                return .json(["input_tokens": .int(max(1, chars / 4))])
            case ("/v1/responses", .codex):
                return try await self.codexResponsesPassthrough(body, path: p)
            case ("/v1/responses", .api(let name)):
                return try await self.apiPassthrough(req, body, provider: try self.need(router, name), endpoint: "/responses", model: model)
            case ("/v1/audio/speech", .api(let name)), ("/v1/images/generations", .api(let name)), ("/v1/embeddings", .api(let name)):
                return try await self.apiPassthrough(req, body, provider: try self.need(router, name), endpoint: String(p.dropFirst(3)), model: model)
            default:
                if s.remote.isUsable { return try await self.remotePassthrough(req, s, model: model) }
                throw ProxyError.notFound("\(model) için telefonda \(p) desteklenmiyor; sunucu bağlantısı kapalı")
            }
        }
    }

    // MARK: tasarruf

    /// Konuşmayı tanıyan kararlı anahtar: model + sistem istemi + ilk kullanıcı mesajı (sonraki turlarda değişmez).
    static func konusmaAnahtari(_ body: JSON) -> String? {
        guard let m = body["messages"]?.array ?? body["input"]?.array, !m.isEmpty else { return nil }
        let ilk = m.first(where: { $0["role"]?.string == "user" }).map { String(String(decoding: $0.data(), as: UTF8.self).prefix(2000)) } ?? ""
        let sistem = body["system"].map { String(String(decoding: $0.data(), as: UTF8.self).prefix(4000)) } ?? ""
        return YanitOnbellegi.anahtar(path: body["model"]?.string ?? "-", body: Data((sistem + "|" + ilk).utf8))
    }

    public struct TasarrufDurumu: Sendable {
        public let sayaclar: TasarrufSayaclari
        public let kota: [String: KotaDurumu.Hesap]
        public let bugunToken: Int
        public let onbellekBoyutu: Int
    }
    public func tasarrufDurumu() async -> TasarrufDurumu {
        TasarrufDurumu(sayaclar: await sayac.sayaclar, kota: await kota.hesaplar, bugunToken: GunlukButce.kullanilan(await log.records), onbellekBoyutu: await onbellek.sayi)
    }

    /// Upstream'e gitmeden önce: günlük token bütçesi, yanıt önbelleği, eş zamanlı aynı isteği bekleme.
    /// Dönüş: (hazır yanıt ya da nil, bu istek tekilleştirme lideri mi).
    func tasarrufOnKontrol(_ req: ProxyRequest, _ s: ProxyState, _ p: String, _ body: JSON, model: String) async throws -> (ProxyResponse?, Bool) {
        let t = s.tasarruf
        if t.gunlukTokenSiniri > 0, p != "/v1/messages/count_tokens" {
            let kullanilan = GunlukButce.kullanilan(await log.records)
            if kullanilan >= t.gunlukTokenSiniri {
                await sayac.degistir { $0.butceReddi += 1 }
                throw ProxyError.upstream(status: 429, message: "Günlük token bütçesi doldu (\(kullanilan)/\(t.gunlukTokenSiniri)). CLI Proxy → Tasarruf'tan sınırı artırabilir ya da yarın tekrar deneyebilirsin.")
            }
        }
        guard t.yanitOnbellegi, p != "/v1/messages/count_tokens", p != "/v1/embeddings", p != "/v1/audio/speech", p != "/v1/images/generations",
              YanitOnbellegi.uygun(body, istekBasligi: req.header("x-proxy-cache")) else { return (nil, false) }
        let k = YanitOnbellegi.anahtar(path: p, body: req.body)
        if let r = await onbellek.al(k, sure: TimeInterval(t.onbellekSuresi)) {
            await sayac.degistir { $0.onbellekIsabeti += 1; $0.tasarrufEdilenToken += r.tahminiToken }
            return (Self.kayittanYanit(r, onbellekten: true), false)
        }
        guard t.esZamanliTekillestirme else { return (nil, false) }
        if await tekil.liderMi(k) { return (nil, true) }
        if let r = await tekil.bekle(k) {
            await sayac.degistir { $0.tekillestirilen += 1; $0.tasarrufEdilenToken += r.tahminiToken }
            return (Self.kayittanYanit(r, onbellekten: false), false)
        }
        return (nil, false)   // lider başarısız oldu: kendi isteğini normal yürüt
    }

    static func kayittanYanit(_ r: YanitOnbellegi.Kayit, onbellekten: Bool) -> ProxyResponse {
        var h = r.basliklar; h["X-Proxy-Cache"] = onbellekten ? "HIT" : "COALESCED"
        let govde = r.govde
        let akis = (h["Content-Type"] ?? "").contains("event-stream")
        return ProxyResponse(status: r.durum, headers: h, body: AsyncThrowingStream { c in c.yield(govde); c.finish() }, streaming: akis)
    }

    /// Yanıtı geçirirken kopyasını biriktirir; akış bitince (200 ise) önbelleğe yazar ve bekleyenlere dağıtır.
    func onbellegeAl(_ r: ProxyResponse, anahtar: String?, ttl: Int, tekil esZamanli: Bool) async -> ProxyResponse {
        guard let k = anahtar else { return r }
        guard r.status == 200 else { if esZamanli { await tekil.bitir(k, nil) }; return r }
        let onbellek = self.onbellek, tekil = self.tekil, sayac = self.sayac
        let basliklar = r.headers
        let kaynak = r.body
        let yeni = AsyncThrowingStream<Data, Error> { c in
            let is_ = Task {
                var toplam = Data(); var tamam = false
                do {
                    for try await parca in kaynak { toplam.append(parca); c.yield(parca) }
                    tamam = true
                    c.finish()
                } catch { c.finish(throwing: error) }
                // Hatalı akış (ör. "error" olayı içeren) önbelleğe yazılmaz.
                let temiz = tamam && !(String(data: toplam.prefix(4096), encoding: .utf8)?.contains("\"error\"") ?? false)
                let kayit = temiz ? YanitOnbellegi.Kayit(durum: 200, basliklar: basliklar, govde: toplam, tahminiToken: max(1, toplam.count / 4), zaman: .now) : nil
                if let kayit { await onbellek.yaz(k, kayit); await sayac.degistir { $0.onbellegeYazilanYanit += 1 } }
                if esZamanli { await tekil.bitir(k, kayit) }
            }
            c.onTermination = { _ in is_.cancel() }
        }
        return ProxyResponse(status: r.status, headers: r.headers.merging(["X-Proxy-Cache": "MISS"]) { $1 }, body: yeni, streaming: r.streaming)
    }

    /// Google API anahtarı ödeme (402), izin/kota (403) ya da sınır (429) verdiyse ve telefonda Antigravity hesabı varsa,
    /// Flash ailesindeki istek Antigravity'nin eşdeğer modeline gider.
    func antigravitySubstitute(_ p: APIKeyProvider, _ model: String, _ e: ProxyError, _ r: ModelRouter) -> (model: String, thinking: String?)? {
        guard [402, 403, 429].contains(e.status), p.baseURL.contains("googleapis.com"), r.hasAntigravity else { return nil }
        return Antigravity.substitute(forGeminiModel: p.upstreamModel(model))
    }

    func need(_ r: ModelRouter, _ name: String) throws -> APIKeyProvider {
        guard let p = r.provider(name), p.enabled else { throw ProxyError.noAccount("\(name) sağlayıcısı telefonda yok") }
        return p
    }

    /// Telefondaki yol hata verirse (hesap yok, 401/429/5xx, ağ) isteği sunucuya düşürür.
    func withFallback(_ req: ProxyRequest, _ s: ProxyState, model: String, route: Route,
                      _ body: @Sendable () async throws -> ProxyResponse) async throws -> ProxyResponse {
        let start = Date()
        do {
            return try await body()
        } catch let e as ProxyError {
            guard route != .remote, e.isFallbackWorthy, s.remote.isUsable, s.remote.fallbackOnError else {
                await record(req.path, model, route, e.status, start, error: e.localizedDescription)
                throw e
            }
            await record(req.path, model, route, e.status, start, error: e.localizedDescription + " → sunucuya düşüldü")
            return try await remotePassthrough(req, s, model: model, fellBack: true)
        } catch let e as URLError {
            guard route != .remote, s.remote.isUsable, s.remote.fallbackOnError else {
                throw ProxyError.upstream(status: 502, message: "Ağ hatası: \(e.localizedDescription)")
            }
            await record(req.path, model, route, 502, start, error: "Ağ hatası → sunucuya düşüldü")
            return try await remotePassthrough(req, s, model: model, fellBack: true)
        }
    }

    func record(_ path: String, _ model: String, _ route: Route, _ status: Int, _ start: Date,
                usage: CUsage = CUsage(), error: String? = nil, fellBack: Bool = false) async {
        if usage.cacheRead > 0 || usage.cacheWrite > 0 {
            await sayac.degistir { $0.promptOnbellekOkunan += usage.cacheRead; $0.promptOnbellekYazilan += usage.cacheWrite }
        }
        await log.add(UsageRecord(path: path, model: model, route: route.description, status: status,
                                  millis: Int(Date().timeIntervalSince(start) * 1000),
                                  inputTokens: usage.input, outputTokens: usage.output, error: error, fellBack: fellBack))
    }

    // MARK: Claude

    func claudeHeaders(_ a: OAuthAccount, clientBeta: String? = nil, version: String? = nil) -> [String: String] {
        var beta = Self.oauthBeta
        if let c = clientBeta, !c.isEmpty {
            let extra = c.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !beta.contains($0) }
            if !extra.isEmpty { beta += "," + extra.joined(separator: ",") }
        }
        return ["Authorization": "Bearer \(a.accessToken)", "anthropic-version": version ?? Self.anthropicVersion,
                "anthropic-beta": beta, "Content-Type": "application/json", "Accept": "application/json, text/event-stream"]
    }

    static func injectIdentity(_ body: JSON) -> JSON {
        var b = body
        let id: JSON = ["type": "text", "text": .string(Outbound.claudeCodeIdentity)]
        if let arr = b["system"]?.array {
            if arr.first?["text"]?.string?.hasPrefix(Outbound.claudeCodeIdentity) == true { return b }
            b["system"] = .array([id] + arr)
        } else if let s = b["system"]?.string, !s.trimmingCharacters(in: .whitespaces).isEmpty {
            if s.hasPrefix(Outbound.claudeCodeIdentity) { return b }
            b["system"] = .array([id, ["type": "text", "text": .string(s)]])
        } else {
            b["system"] = .array([id])
        }
        return b
    }

    /// Hesap havuzu üzerinde deneme döngüsü: yenileme hatası ya da ikinci 401'de hesap atlanır, 401'de AYNI hesap
    /// bir kez zorla yenilenir, sınır/aşırı yük kodlarında hesap dinlendirilip sıradakine geçilir.
    func withOAuth(_ provider: OAuthProviderKind, cooldown: [Int: TimeInterval], yapiskan: String? = nil, model: String? = nil,
                   _ send: (OAuthAccount) async throws -> UpstreamResponse) async throws -> (UpstreamResponse, OAuthAccount) {
        var exclude = Set<String>()
        var last: ProxyError?
        // Kota koruması: başlıklardan doluluğu eşiği aşan hesaplar, başka uygun hesap kalıyorsa baştan atlanır.
        let esik = Double(await vault.state.tasarruf.kotaKorumaYuzdesi) / 100
        if esik > 0 {
            let hesaplar = await vault.state.oauth.filter { $0.provider == provider && $0.enabled }
            var dolu: [String] = []
            for h in hesaplar { if let d = await kota.doluluk(h.qualifiedId), d >= esik { dolu.append(h.qualifiedId) } }
            if !dolu.isEmpty, dolu.count < hesaplar.count { exclude.formUnion(dolu); await sayac.degistir { $0.kotaAtlama += dolu.count } }
        }
        for _ in 0..<6 {
            let picked: OAuthAccount
            do { picked = try await tokens.pick(provider, exclude: exclude, tercih: yapiskan, model: model) } catch { throw last ?? error }
            var a: OAuthAccount
            do { a = try await tokens.fresh(picked) } catch {
                last = (error as? ProxyError) ?? .upstream(status: 401, message: error.localizedDescription)
                exclude.insert(picked.qualifiedId); continue
            }
            var resp = try await send(a)
            if resp.status == 401 {
                _ = try? await resp.collect(limit: 1 << 20)
                do { a = try await tokens.fresh(a, force: true); resp = try await send(a) } catch {
                    last = (error as? ProxyError) ?? .upstream(status: 401, message: error.localizedDescription)
                    exclude.insert(a.qualifiedId); continue
                }
            }
            await kota.isle(hesap: a.qualifiedId, basliklar: resp.headers)
            if resp.status == 200 { await tokens.basarili(a); if let yapiskan { await tokens.yapiskanlikKaydet(yapiskan, hesap: a.qualifiedId) }; return (resp, a) }
            let err = await errorFrom(resp, fallback: "\(provider.title) HTTP \(resp.status)")
            last = err
            if let wait = cooldown[resp.status] {
                let retryAfter = Double(resp.header("retry-after") ?? "")
                // Harcama/aylık sınır 429'u: yeniden denemek anlamsız, hesap/model uzun süre dinlenir. Aksi hâlde Retry-After ya da üstel geri çekilme.
                let harcama = resp.status == 429 && UpstreamYardimci.harcamaSiniri(err.localizedDescription)
                await tokens.coolDown(a, model: resp.status == 429 ? model : nil, taban: wait, retryAfter: retryAfter, uzun: harcama)
                exclude.insert(a.qualifiedId); continue
            }
            if resp.status == 401 { exclude.insert(a.qualifiedId); continue }
            throw err
        }
        throw last ?? ProxyError.noAccount("Telefonda açık \(provider.title) hesabı yok")
    }

    /// Claude isteğinin hangi kimlikle gittiği (günlük yolu için)
    enum ClaudeVia: Sendable {
        case oauth(OAuthAccount)
        case apiKey(APIKeyProvider)
        var route: Route { switch self { case .oauth: .claude; case .apiKey(let p): .api(p.name) } }
    }

    /// Claude API anahtarı başlıkları: OAuth beta'ları gönderilmez, istemcinin beta'sı olduğu gibi geçer.
    func claudeAPIHeaders(_ p: APIKeyProvider, clientBeta: String?, version: String?) -> [String: String] {
        var h = ["x-api-key": p.apiKey, "anthropic-version": version ?? Self.anthropicVersion,
                 "Content-Type": "application/json", "Accept": "application/json, text/event-stream"]
        if let c = clientBeta, !c.isEmpty { h["anthropic-beta"] = c }
        return h
    }

    /// Claude API sağlayıcısının /v1/messages adresi (base_url "/v1" ile bitiyorsa yeniden eklenmez)
    static func claudeAPIURL(_ p: APIKeyProvider, countTokens: Bool) -> String {
        let root = p.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return root + (root.hasSuffix("/v1") ? "/messages" : "/v1/messages") + (countTokens ? "/count_tokens" : "")
    }

    func claudeRequest(_ url: String, headers: [String: String], _ payload: Data) -> URLRequest {
        var r = URLRequest(url: URL(string: url)!)
        r.httpMethod = "POST"
        r.timeoutInterval = 600
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        r.httpBody = payload
        return r
    }

    /// Claude'a istek: önce OAuth (abonelik) hesapları; hesap yoksa ya da hepsi 401/403/429/5xx ile düşerse
    /// Claude API anahtarlı sağlayıcılar sırayla denenir. API anahtarında Claude Code kimliği eklenmez.
    func sendClaude(_ gelen: JSON, countTokens: Bool = false, clientBeta: String? = nil, version: String? = nil) async throws -> (UpstreamResponse, ClaudeVia) {
        // Otomatik prompt önbelleği: tekrarlayan uzun sistem istemi/araç/konuşma önekleri 5 dk boyunca ~%90 ucuz okunur.
        var body = gelen
        if !countTokens, await vault.state.tasarruf.kirpmaAcik {
            let (b, n) = AracCiktisiKirpici.uygula(body)
            if n > 0 { body = b; await sayac.degistir { $0.kirpilanAracCiktisi += n } }
        }
        if !countTokens, await vault.state.tasarruf.otomatikPromptOnbellegi {
            let (b, n) = PromptOnbellegi.uygula(body)
            if n > 0 { body = b }
        }
        let apiProviders = ModelRouter(state: await vault.state).claudeAPIProviders
        var last: ProxyError?
        do {
            let url = countTokens ? Self.claudeURL + "/count_tokens" : Self.claudeURL
            let payload = Self.injectIdentity(body).data()
            let (resp, a) = try await withOAuth(.claude, cooldown: [429: 60, 529: 30], yapiskan: Self.konusmaAnahtari(body), model: body["model"]?.string) { a in
                try await transport.send(claudeRequest(url, headers: claudeHeaders(a, clientBeta: clientBeta, version: version), payload))
            }
            return (resp, .oauth(a))
        } catch let e as ProxyError where !apiProviders.isEmpty && e.isFallbackWorthy {
            last = e
        }
        let payload = body.data()
        for p in apiProviders {
            let resp = try await transport.send(claudeRequest(Self.claudeAPIURL(p, countTokens: countTokens),
                                                              headers: claudeAPIHeaders(p, clientBeta: clientBeta, version: version), payload))
            if resp.status == 200 { return (resp, .apiKey(p)) }
            let err = await errorFrom(resp, fallback: "\(p.name) HTTP \(resp.status)")
            guard err.isFallbackWorthy else { throw err }
            last = err
        }
        throw last ?? ProxyError.noAccount("Telefonda açık Claude hesabı ya da Claude API anahtarı yok")
    }

    func claudePassthrough(_ req: ProxyRequest, _ body: JSON, path: String, countTokens: Bool) async throws -> ProxyResponse {
        let start = Date()
        let model = body["model"]?.string ?? "?"
        var b = body
        if countTokens { b["max_tokens"] = nil; b["stream"] = nil }
        let (resp, via) = try await sendClaude(b, countTokens: countTokens, clientBeta: req.header("anthropic-beta"), version: req.header("anthropic-version"))
        let route = via.route
        let streaming = body["stream"]?.bool == true && !countTokens
        if !streaming {
            let data = try await resp.collect()
            let j = try? JSON.parse(data)
            let u = j?["usage"]
            await record(path, model, route, 200, start, usage: CUsage(input: u?["input_tokens"]?.int ?? j?["input_tokens"]?.int ?? 0, output: u?["output_tokens"]?.int ?? 0,
                                                                       cacheRead: u?["cache_read_input_tokens"]?.int ?? 0, cacheWrite: u?["cache_creation_input_tokens"]?.int ?? 0))
            return ProxyResponse(status: 200, headers: ["Content-Type": "application/json"], body: AsyncThrowingStream { c in c.yield(data); c.finish() }, streaming: false)
        }
        // Akışı olduğu gibi aktar, kullanım için yan kopyayı çöz.
        let log = self
        let stream = AsyncThrowingStream<Data, Error> { c in
            let task = Task {
                var parser = SSEParser(); var dec = AnthropicDecoder(); var usage = CUsage(); var status = 200; var errText: String?
                do {
                    for try await chunk in resp.body {
                        c.yield(chunk)
                        for e in parser.feed(chunk) {
                            do { for ev in try dec.decode(e) { if case .finish(_, let u) = ev { usage = u } } }
                            catch { errText = error.localizedDescription; status = 502 }
                        }
                    }
                    c.finish()
                } catch {
                    errText = error.localizedDescription; status = 502
                    c.yield(sseData(["type": "error", "error": ["type": "api_error", "message": .string(error.localizedDescription)]], event: "error"))
                    c.finish()
                }
                await log.record(path, model, route, status, start, usage: usage, error: errText)
            }
            c.onTermination = { _ in task.cancel() }
        }
        return ProxyResponse(status: 200, headers: ["Content-Type": "text/event-stream", "Cache-Control": "no-cache"], body: stream, streaming: true)
    }

    enum OutFormat { case openAI, anthropic }

    func claudeCanonical(_ c: CRequest, out: OutFormat, path: String) async throws -> ProxyResponse {
        let start = Date()
        let (resp, via) = try await sendClaude(Outbound.anthropic(c))
        return try await pipe(resp, decoder: AnthropicDecoder(), c: c, out: out, route: via.route, path: path, start: start)
    }

    // MARK: Codex

    func sendCodex(_ body: JSON) async throws -> UpstreamResponse {
        let acik = await vault.state.tasarruf.openAIAnahtariAcik
        var b = acik ? UpstreamYardimci.onbellekAnahtariEkle(body, anahtar: Self.konusmaAnahtari(codexKonusma(body))) : body
        do { return try await codexGonder(b) } catch let e as ProxyError where acik && body["prompt_cache_key"] == nil && UpstreamYardimci.alanReddi(e.status, e.localizedDescription) {
            b = body   // sağlayıcı alanı tanımıyor: çıkarıp yeniden dene
            return try await codexGonder(b)
        }
    }

    /// Codex gövdesini konuşma anahtarı için messages biçimine benzetir (instructions + ilk girdi).
    func codexKonusma(_ b: JSON) -> JSON {
        var j: JSON = ["model": b["model"] ?? .string("codex"), "system": b["instructions"] ?? .string("")]
        let girdi = b["input"]
        let ilk: JSON = girdi?.array?.first ?? girdi ?? .string("")
        j["messages"] = .array([["role": "user", "content": ilk]])
        return j
    }

    func codexGonder(_ body: JSON) async throws -> UpstreamResponse {
        var b = body
        b["stream"] = true; b["store"] = false
        for k in ["max_output_tokens", "temperature", "top_p", "max_tokens"] { b[k] = nil }
        if b["instructions"] == nil { b["instructions"] = "" }
        let payload = b.data()
        return try await withOAuth(.codex, cooldown: [429: 600, 403: 600], model: b["model"]?.string) { a in
            var r = URLRequest(url: URL(string: Self.codexURL)!)
            r.httpMethod = "POST"
            r.timeoutInterval = 600
            r.setValue("Bearer \(a.accessToken)", forHTTPHeaderField: "Authorization")
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            r.setValue(OAuthConstants.Codex.originator, forHTTPHeaderField: "originator")
            r.setValue(OAuthConstants.Codex.originator, forHTTPHeaderField: "User-Agent")
            if let acc = a.metadata["account_id"] { r.setValue(acc, forHTTPHeaderField: "ChatGPT-Account-ID") }
            r.httpBody = payload
            return try await transport.send(r)
        }.0
    }

    func codexCanonical(_ c: CRequest, out: OutFormat, path: String) async throws -> ProxyResponse {
        let start = Date()
        let resp = try await sendCodex(Outbound.responses(c, forCodex: true))
        return try await pipe(resp, decoder: ResponsesDecoder(), c: c, out: out, route: .codex, path: path, start: start)
    }

    func codexResponsesPassthrough(_ body: JSON, path: String) async throws -> ProxyResponse {
        let start = Date()
        let model = body["model"]?.string ?? "?"
        let resp = try await sendCodex(body)
        if body["stream"]?.bool == true {
            let me = self
            let stream = AsyncThrowingStream<Data, Error> { c in
                let task = Task {
                    var parser = SSEParser(); var dec = ResponsesDecoder(); var usage = CUsage(); var err: String?
                    do {
                        for try await chunk in resp.body {
                            c.yield(chunk)
                            for e in parser.feed(chunk) { if let evs = try? dec.decode(e) { for ev in evs { if case .finish(_, let u) = ev { usage = u } } } }
                        }
                        c.finish()
                    } catch { err = error.localizedDescription; c.finish(throwing: error) }
                    await me.record(path, model, .codex, err == nil ? 200 : 502, start, usage: usage, error: err)
                }
                c.onTermination = { _ in task.cancel() }
            }
            return ProxyResponse(status: 200, headers: ["Content-Type": "text/event-stream", "Cache-Control": "no-cache"], body: stream, streaming: true)
        }
        // Akışsız istemci: olaylardan tam yanıtı kur.
        var parser = SSEParser()
        var items: [Int: JSON] = [:]
        var final: JSON?
        for try await chunk in resp.body {
            for e in parser.feed(chunk) {
                guard let j = try? JSON.parse(Data(e.data.utf8)) else { continue }
                switch j["type"]?.string {
                case "response.output_item.done": if let it = j["item"] { items[j["output_index"]?.int ?? items.count] = it }
                case "response.completed", "response.incomplete": final = j["response"]
                case "response.failed", "error": throw upstreamError(j["response"] ?? j, fallback: "Codex yanıtı tamamlanmadı")
                default: break
                }
            }
        }
        guard var f = final else { throw ProxyError.upstream(status: 502, message: "Codex akışı tamamlanmadan bitti") }
        if (f["output"]?.array ?? []).isEmpty { f["output"] = .array(items.keys.sorted().compactMap { items[$0] }) }
        let u = f["usage"]
        await record(path, model, .codex, 200, start, usage: CUsage(input: u?["input_tokens"]?.int ?? 0, output: u?["output_tokens"]?.int ?? 0))
        return .json(f)
    }

    // MARK: Antigravity

    func antigravityCanonical(_ c: CRequest, model: String, thinking: String?, out: OutFormat, path: String) async throws -> ProxyResponse {
        let start = Date()
        let (resp, _) = try await withOAuth(.antigravity, cooldown: [429: 60, 503: 30]) { a in
            var r = URLRequest(url: URL(string: OAuthConstants.Antigravity.base + ":streamGenerateContent?alt=sse")!)
            r.httpMethod = "POST"
            r.timeoutInterval = 600
            r.setValue("Bearer \(a.accessToken)", forHTTPHeaderField: "Authorization")
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            r.setValue(OAuthConstants.Antigravity.userAgent, forHTTPHeaderField: "User-Agent")
            let project = a.metadata["project"] ?? OAuthConstants.Antigravity.defaultProject
            let signatures = self.geminiSignatures.signatures(model: model, ids: c.messages.flatMap { $0.toolCalls.map(\.id) })
            r.httpBody = Antigravity.body(c, model: model, thinking: thinking, project: project, signatures: signatures).data()
            return try await self.transport.send(r)
        }
        let cache = geminiSignatures
        let decoder = GeminiDecoder { id, signature in cache.save(model: model, id: id, signature: signature) }
        return try await pipe(resp, decoder: decoder, c: c, out: out, route: .antigravity(model: model, thinking: thinking), path: path, start: start)
    }

    // MARK: API anahtarlı sağlayıcılar (OpenAI, Gemini uyumlu uç)

    func apiRequest(_ p: APIKeyProvider, endpoint: String, body: JSON, accept: String? = nil) async throws -> UpstreamResponse {
        var base = p.baseURL
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + endpoint) else { throw ProxyError.badRequest("Sağlayıcı adresi geçersiz") }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 600
        r.setValue("Bearer \(p.apiKey)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accept { r.setValue(accept, forHTTPHeaderField: "Accept") }
        var b = body
        let model = b["model"]?.string ?? ""
        let up = p.upstreamModel(model)
        b["model"] = .string(up)
        for k in p.filterParams[model] ?? p.filterParams[up] ?? [] { b[k] = nil }
        // OpenAI'ye kararlı prompt_cache_key (yalnız resmî api.openai.com; reddedilirse alan çıkarılıp bir kez yeniden denenir).
        let openAIAcik = await vault.state.tasarruf.openAIAnahtariAcik
        let anahtarli = p.baseURL.contains("api.openai.com") && endpoint != "/embeddings" && endpoint != "/audio/speech" && endpoint != "/images/generations"
            && b["prompt_cache_key"] == nil && openAIAcik
        var govde = b
        if anahtarli { govde = UpstreamYardimci.onbellekAnahtariEkle(b, anahtar: Self.konusmaAnahtari(b)) }
        r.httpBody = govde.data()
        var resp = try await transport.send(r)
        if anahtarli, resp.status == 400 {
            let hata = await errorFrom(resp, fallback: "")
            if UpstreamYardimci.alanReddi(hata.status, hata.localizedDescription) {
                r.httpBody = b.data(); resp = try await transport.send(r)
            } else { throw hata }
        }
        guard (200..<300).contains(resp.status) else { throw await errorFrom(resp, fallback: "\(p.name) HTTP \(resp.status)") }
        return resp
    }

    func apiPassthrough(_ req: ProxyRequest, _ body: JSON, provider p: APIKeyProvider, endpoint: String, model: String) async throws -> ProxyResponse {
        let start = Date()
        var b = body
        let streaming = b["stream"]?.bool == true
        if streaming && endpoint == "/chat/completions" && b["stream_options"] == nil { b["stream_options"] = ["include_usage": true] }
        let resp = try await apiRequest(p, endpoint: endpoint, body: b, accept: streaming ? "text/event-stream" : nil)
        let route = Route.api(p.name)
        let ctype = resp.header("content-type") ?? (streaming ? "text/event-stream" : "application/json")
        if !streaming {
            let data = try await resp.collect()
            let u = (try? JSON.parse(data))?["usage"]
            await record(req.path, model, route, resp.status, start,
                         usage: CUsage(input: u?["prompt_tokens"]?.int ?? u?["input_tokens"]?.int ?? 0, output: u?["completion_tokens"]?.int ?? u?["output_tokens"]?.int ?? 0))
            // istemciye kendi adıyla dön
            var out = data
            if ctype.contains("json"), var j = try? JSON.parse(data), j["model"] != nil { j["model"] = .string(model); out = j.data() }
            return ProxyResponse(status: resp.status, headers: ["Content-Type": ctype], body: AsyncThrowingStream { c in c.yield(out); c.finish() }, streaming: false)
        }
        let me = self
        let stream = AsyncThrowingStream<Data, Error> { c in
            let task = Task {
                var parser = SSEParser(); var dec = OpenAIChatDecoder(); var usage = CUsage(); var err: String?
                do {
                    for try await chunk in resp.body {
                        c.yield(chunk)
                        for e in parser.feed(chunk) { if let evs = try? dec.decode(e) { for ev in evs { if case .finish(_, let u) = ev { usage = u } } } }
                    }
                    if usage.total == 0 { for ev in dec.end() { if case .finish(_, let u) = ev { usage = u } } }
                    c.finish()
                } catch { err = error.localizedDescription; c.finish(throwing: error) }
                await me.record(req.path, model, route, err == nil ? 200 : 502, start, usage: usage, error: err)
            }
            c.onTermination = { _ in task.cancel() }
        }
        return ProxyResponse(status: 200, headers: ["Content-Type": ctype, "Cache-Control": "no-cache"], body: stream, streaming: true)
    }

    func apiCanonical(_ c: CRequest, provider p: APIKeyProvider, path: String) async throws -> ProxyResponse {
        let start = Date()
        // OpenAI function tools use Responses; newer reasoning models reject this combination on Chat Completions.
        if URL(string: p.baseURL)?.host?.lowercased() == "api.openai.com" {
            let resp = try await apiRequest(p, endpoint: "/responses", body: Outbound.responses(c, forCodex: false), accept: "text/event-stream")
            return try await pipe(resp, decoder: ResponsesDecoder(), c: c, out: .anthropic, route: .api(p.name), path: path, start: start)
        }
        let resp = try await apiRequest(p, endpoint: "/chat/completions", body: Outbound.openAIChat(c, upstreamModel: c.model), accept: "text/event-stream")
        return try await pipe(resp, decoder: OpenAIChatDecoder(), c: c, out: .anthropic, route: .api(p.name), path: path, start: start)
    }

    // MARK: Gemini yerel uçları

    func geminiModel(_ path: String, _ body: Data) -> String? {
        if let r = path.range(of: "/models/") {
            let rest = path[r.upperBound...]
            return String(rest.split(separator: ":").first ?? Substring(rest))
        }
        return (try? JSON.parse(body))?["model"]?.string
    }

    func geminiNative(_ req: ProxyRequest, _ path: String, _ s: ProxyState, _ router: ModelRouter) async throws -> ProxyResponse {
        let start = Date()
        let model = geminiModel(path, req.body)
        let route = model.map { router.resolve($0) } ?? .remote
        let google = s.apiProviders.filter { $0.enabled && $0.baseURL.contains("googleapis.com") }
        var provider: APIKeyProvider?
        // Görsel/canlı modeller sohbet uçlarında sunucuya gider ama Google'ın yerel ucunda doğrudan çalışır.
        if let m = model { provider = google.first(where: { $0.models.contains(m) || $0.aliases[m] != nil }) }
        if provider == nil, case .api(let n) = route, let p = google.first(where: { $0.name == n }) { provider = p }
        if provider == nil, model == nil || path.hasPrefix("/v1alpha/") { provider = google.first(where: { $0.kind == .geminiNative }) ?? google.first }
        guard let p = provider else {
            if s.remote.isUsable { return try await remotePassthrough(req, s, model: model ?? "gemini") }
            throw ProxyError.noAccount("Bu Gemini modeli için telefonda anahtar yok")
        }
        var upPath = path
        var body = req.body
        if let m = model {
            let up = p.upstreamModel(m)
            if up != m { upPath = upPath.replacingOccurrences(of: "/models/\(m)", with: "/models/\(up)") }
            if var j = try? JSON.parse(req.body), j["model"]?.string == m { j["model"] = .string(up); body = j.data() }
        }
        var comps = URLComponents(string: Self.googleRoot + upPath)!
        let q = req.query.filter { $0.key != "key" }
        if !q.isEmpty { comps.queryItems = q.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var r = URLRequest(url: comps.url!)
        r.httpMethod = req.method
        r.timeoutInterval = 600
        r.setValue(p.apiKey, forHTTPHeaderField: "x-goog-api-key")
        r.setValue(req.header("content-type") ?? "application/json", forHTTPHeaderField: "Content-Type")
        if req.method != "GET" { r.httpBody = body }
        let resp = try await transport.send(r)
        guard (200..<300).contains(resp.status) else { throw await errorFrom(resp, fallback: "Gemini HTTP \(resp.status)") }
        await record(path, model ?? "gemini", .api(p.name), resp.status, start)
        let ct = resp.header("content-type") ?? "application/json"
        return ProxyResponse(status: resp.status, headers: ["Content-Type": ct], body: resp.body, streaming: ct.contains("event-stream"))
    }

    // MARK: Sunucuya aktarma

    func remotePassthrough(_ req: ProxyRequest, _ s: ProxyState, model: String, fellBack: Bool = false) async throws -> ProxyResponse {
        guard s.remote.isUsable else { throw ProxyError.noAccount("\(model) yalnız sunucuda çalışır; sunucu bağlantısı kapalı") }
        let start = Date()
        var path = req.path
        let urlString: String
        if path.hasPrefix("/v1beta/") || path.hasPrefix("/v1alpha/") {
            urlString = s.remote.rootURL + path     // köke eklenir
        } else {
            if path.hasPrefix("/v1/") { path = String(path.dropFirst(3)) }
            var base = s.remote.baseURL
            while base.hasSuffix("/") { base.removeLast() }
            urlString = base + path
        }
        var comps = URLComponents(string: urlString)!
        let q = req.query.filter { $0.key != "key" }
        if !q.isEmpty { comps.queryItems = q.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = comps.url else { throw ProxyError.badRequest("Sunucu adresi geçersiz") }
        var r = URLRequest(url: url)
        r.httpMethod = req.method
        r.timeoutInterval = 900
        for h in ["content-type", "accept", "anthropic-version", "anthropic-beta", "openai-beta"] {
            if let v = req.header(h) { r.setValue(v, forHTTPHeaderField: h) }
        }
        if !s.remote.personalToken.isEmpty { r.setValue(s.remote.personalToken, forHTTPHeaderField: "X-Personal-Token") }
        if req.method != "GET" { r.httpBody = req.body }
        let resp: UpstreamResponse
        do { resp = try await transport.send(r) } catch {
            await record(req.path, model, .remote, 502, start, error: error.localizedDescription, fellBack: fellBack)
            throw ProxyError.remoteFailed("Sunucuya ulaşılamadı: \(error.localizedDescription)")
        }
        await record(req.path, model, .remote, resp.status, start, error: resp.status >= 400 ? "Sunucu HTTP \(resp.status)" : nil, fellBack: fellBack)
        let ct = resp.header("content-type") ?? "application/json"
        return ProxyResponse(status: resp.status, headers: ["Content-Type": ct], body: resp.body, streaming: ct.contains("event-stream"))
    }

    // MARK: Ortak akış borusu

    func pipe<D: StreamDecoder>(_ resp: UpstreamResponse, decoder: D, c: CRequest, out: OutFormat, route: Route, path: String, start: Date) async throws -> ProxyResponse {
        let me = self
        if !c.stream {
            // Akışsız istemci: önce tamamını topla. Akış içinde gelen hata (aşırı yük, sınır) doğru HTTP durumuyla
            // fırlatılır; böylece istemci 200 + hata gövdesi görmez ve gerekirse sunucuya düşülür.
            var parser = SSEParser(); var dec = decoder; var agg = Aggregate()
            for try await chunk in resp.body { for e in parser.feed(chunk) { for ev in try dec.decode(e) { agg.add(ev) } } }
            for e in parser.finish() { for ev in try dec.decode(e) { agg.add(ev) } }
            for ev in dec.end() { agg.add(ev) }
            let j: JSON = out == .openAI ? OpenAIChatEncoder(model: c.model, includeUsage: false).full(agg) : AnthropicEncoder(model: c.model).full(agg)
            await record(path, c.model, route, 200, start, usage: agg.usage)
            return .json(j)
        }
        let stream = AsyncThrowingStream<Data, Error> { cont in
            let task = Task {
                var parser = SSEParser(); var dec = decoder
                var oe = OpenAIChatEncoder(model: c.model, includeUsage: c.includeUsage)
                var ae = AnthropicEncoder(model: c.model)
                var usage = CUsage(); var finished = false
                func emit(_ ev: CEvent) {
                    if case .finish(_, let u) = ev { usage = u; finished = true }
                    cont.yield(out == .openAI ? oe.encode(ev) : ae.encode(ev))
                }
                do {
                    for try await chunk in resp.body { for e in parser.feed(chunk) { for ev in try dec.decode(e) { emit(ev) } } }
                    for e in parser.finish() { for ev in try dec.decode(e) { emit(ev) } }
                    if !finished { for ev in dec.end() { emit(ev) } }
                    cont.finish()
                    await me.record(path, c.model, route, 200, start, usage: usage)
                } catch {
                    let pe = (error as? ProxyError) ?? .upstream(status: 502, message: error.localizedDescription)
                    if out == .openAI {
                        cont.yield(sseData(ProxyResponse.errorJSON(pe, anthropic: false)))
                        cont.yield(Data("data: [DONE]\n\n".utf8))
                    } else {
                        cont.yield(sseData(ProxyResponse.errorJSON(pe, anthropic: true), event: "error"))
                    }
                    cont.finish()
                    await me.record(path, c.model, route, pe.status, start, error: pe.localizedDescription)
                }
            }
            cont.onTermination = { _ in task.cancel() }
        }
        return ProxyResponse(status: 200, headers: ["Content-Type": "text/event-stream", "Cache-Control": "no-cache"], body: stream, streaming: true)
    }

    func errorFrom(_ resp: UpstreamResponse, fallback: String) async -> ProxyError {
        let data = (try? await resp.collect(limit: 1 << 20)) ?? Data()
        let j = try? JSON.parse(data)
        var msg = j?["error"]?["message"]?.string ?? j?["error"]?.string ?? j?["detail"]?.string ?? j?["message"]?.string
        if msg == nil, !data.isEmpty { msg = String(decoding: data.prefix(300), as: UTF8.self) }
        return .upstream(status: resp.status, message: msg ?? fallback)
    }

    // MARK: Model listesi

    func modelList(_ s: ProxyState, _ router: ModelRouter) async -> JSON {
        let created = JSON.int(Int(Date().timeIntervalSince1970))
        var data: [JSON] = router.localModels().map { ["id": .string($0.id), "object": "model", "created": created, "owned_by": .string($0.owner)] }
        var seen = Set(router.localModels().map(\.id))
        if s.remote.isUsable {
            for m in await remoteModels.get(s, transport: transport) where !seen.contains(m) {
                seen.insert(m)
                data.append(["id": .string(m), "object": "model", "created": created, "owned_by": "sunucu"])
            }
        }
        return ["object": "list", "data": .array(data)]
    }
}

extension ProxyResponse {
    static func errorJSON(_ e: ProxyError, anthropic: Bool) -> JSON {
        if anthropic { return ["type": "error", "error": ["type": "api_error", "message": .string(e.localizedDescription)]] }
        return ["error": ["message": .string(e.localizedDescription), "type": "upstream_error", "code": .int(e.status)]]
    }
}

/// Sunucunun model listesini kısa süre önbellekte tutar.
actor RemoteModelCache {
    var cached: [String] = []
    var at: Date = .distantPast

    func get(_ s: ProxyState, transport: HTTPTransport) async -> [String] {
        if Date().timeIntervalSince(at) < 300, !cached.isEmpty { return cached }
        var base = s.remote.baseURL
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/models") else { return cached }
        var r = URLRequest(url: url)
        r.timeoutInterval = 15
        r.setValue(s.remote.personalToken, forHTTPHeaderField: "X-Personal-Token")
        guard let resp = try? await transport.send(r), resp.status == 200,
              let d = try? await resp.collect(), let list = (try? JSON.parse(d))?["data"]?.array else { return cached }
        cached = list.compactMap { $0["id"]?.string }
        at = Date()
        return cached
    }

    func invalidate() { at = .distantPast }
}
