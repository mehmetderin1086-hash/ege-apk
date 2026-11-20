import Foundation

/// Hesap seçimi, belirteç tazeliği ve geçici dinlendirme.
/// - `telefon` sahipli hesap: süresi dolmak üzereyse burada yenilenir.
/// - `sunucu` sahipli hesap: güncel erişim belirteci sunucunun eşitleme ucundan çekilir;
///   böylece yenileme belirteci rotasyonu iki yeri birbirine düşürmez.
public actor TokenManager {
    let vault: Vault
    let oauth: OAuthClient
    let transport: HTTPTransport
    private var cooldowns: [String: Date] = [:]
    /// "hesap|model" → bitiş (model düzeyinde soğuma: Opus kotası bitince aynı hesapta Haiku sürer).
    private var modelCooldowns: [String: Date] = [:]
    private var ardisikHata: [String: Int] = [:]
    private var inflight: [String: Task<OAuthAccount, Error>] = [:]
    private var syncTask: Task<Void, Error>?
    private var lastSync: Date?
    private var rr: [OAuthProviderKind: Int] = [:]

    public init(vault: Vault, transport: HTTPTransport) {
        self.vault = vault
        self.transport = transport
        self.oauth = OAuthClient(transport: transport)
    }

    /// İstek için uygun hesap. `exclude` ile bir önceki denemede düşen hesap atlanır.
    public func account(for provider: OAuthProviderKind, exclude: Set<String> = [], force: Bool = false) async throws -> OAuthAccount {
        try await fresh(try await pick(provider, exclude: exclude), force: force)
    }

    /// Yenilemeden hesap seçer (dinlenmede olmayanlar önce, sırayla).
    /// Konuşma → hesap yapışkanlığı: aynı sistem istemi/ilk mesaj aynı hesapta kalır (Anthropic prompt önbelleği hesap bazlıdır;
    /// round-robin her istekte önbelleği bozardı). Hesap soğuma/dışlama durumundaysa başka hesaba geçilir ve yapışkanlık güncellenir.
    var yapiskan: [String: String] = [:]
    var yapiskanSira: [String] = []
    public func yapiskanlikKaydet(_ anahtar: String, hesap: String) {
        if yapiskan[anahtar] == nil { yapiskanSira.append(anahtar); if yapiskanSira.count > 256 { yapiskan[yapiskanSira.removeFirst()] = nil } }
        yapiskan[anahtar] = hesap
    }

    public func pick(_ provider: OAuthProviderKind, exclude: Set<String> = [], tercih anahtar: String? = nil, model: String? = nil) async throws -> OAuthAccount {
        let now = Date()
        let state = await vault.state
        let all = state.oauth.filter { $0.provider == provider && $0.enabled && !exclude.contains($0.qualifiedId) }
        guard !all.isEmpty else { throw ProxyError.noAccount("Telefonda açık \(provider.title) hesabı yok") }
        let ready = all.filter { hesap in
            let modelBitis = model.map { modelCooldowns["\(hesap.qualifiedId)|\($0)"] ?? .distantPast } ?? .distantPast
            return (cooldowns[hesap.qualifiedId] ?? .distantPast) <= now && modelBitis <= now
        }
        if let anahtar, let id = yapiskan[anahtar], let a = ready.first(where: { $0.qualifiedId == id }) { return a }
        let pool = ready.isEmpty ? all : ready
        // "Birini bitir": hazır olan ilk hesap (sıra sabit); biri soğuyunca sıradakine geçilir.
        if state.tasarruf.strateji == .birBitir { return pool[0] }
        let i = (rr[provider] ?? 0) % pool.count
        rr[provider] = i + 1
        return pool[i]
    }

    public func fresh(_ a: OAuthAccount, force: Bool = false) async throws -> OAuthAccount {
        if !force && !a.expiresSoon() { return a }
        switch a.refreshOwner {
        case .sunucu:
            try await syncFromServer(force: true)
            guard let updated = await vault.state.oauth.first(where: { $0.qualifiedId == a.qualifiedId }) else {
                throw ProxyError.noAccount("\(a.label) sunucuda bulunamadı")
            }
            if updated.expiresSoon(within: 30) {
                throw ProxyError.upstream(status: 401, message: "\(a.label): sunucudan güncel belirteç alınamadı")
            }
            return updated
        case .telefon:
            if let t = inflight[a.qualifiedId] { return try await t.value }
            // Aynı kasayı paylaşan öbür uygulama az önce yenilemiş olabilir; rotasyonlu belirteci ikinci kez harcama.
            if let cur = await vault.reload().oauth.first(where: { $0.qualifiedId == a.qualifiedId }),
               cur.accessToken != a.accessToken, !cur.expiresSoon(), !force {
                return cur
            }
            let latest = await vault.state.oauth.first(where: { $0.qualifiedId == a.qualifiedId }) ?? a
            let task = Task { [oauth, vault] () throws -> OAuthAccount in
                let a = latest
                do {
                    let r = try await oauth.refresh(a)
                    var b = a
                    b.accessToken = r.accessToken
                    b.refreshToken = r.refreshToken ?? a.refreshToken
                    b.expiresAt = r.expiresAt
                    if let s = r.scopes { b.scopes = s }
                    b.lastError = nil
                    if a.provider == .codex {
                        let m = OAuthClient.codexMetadata(idToken: r.idToken, accessToken: r.accessToken)
                        b.metadata.merge(m) { _, new in new }
                    }
                    let snapshot = b
                    // Yalnız belirteç alanları yazılır: yenileme sürerken kullanıcının değiştirdiği etkinlik/sahiplik korunur.
                    do {
                        try await vault.updateAccount(a.qualifiedId) {
                            $0.accessToken = snapshot.accessToken; $0.refreshToken = snapshot.refreshToken
                            $0.expiresAt = snapshot.expiresAt; $0.scopes = snapshot.scopes
                            $0.metadata = snapshot.metadata; $0.lastError = nil
                        }
                    } catch {
                        // Keychain yazılamadı: döndürülmüş yeni belirteç en azından bu oturumda kullanılır.
                        b.lastError = "Yeni belirteç kaydedilemedi: \(error.localizedDescription)"
                    }
                    return b
                } catch {
                    let msg = error.localizedDescription
                    try? await vault.updateAccount(a.qualifiedId) { $0.lastError = msg }
                    throw error
                }
            }
            inflight[a.qualifiedId] = task
            defer { inflight[a.qualifiedId] = nil }
            return try await task.value
        }
    }

    public func coolDown(_ a: OAuthAccount, seconds: TimeInterval) {
        cooldowns[a.qualifiedId] = Date().addingTimeInterval(seconds)
    }

    /// Hesap/model soğutma: `model` verilirse yalnız o model (diğer modeller aynı hesapta sürer). Süre mutlak zamanla tutulur.
    /// `retryAfter` yoksa ardışık hata sayısına göre üstel artar (taban × 2^(n-1), üst sınır 30 dk).
    public func coolDown(_ a: OAuthAccount, model: String?, taban: TimeInterval, retryAfter: TimeInterval? = nil, uzun: Bool = false) {
        let n = (ardisikHata[a.qualifiedId] ?? 0) + 1
        ardisikHata[a.qualifiedId] = n
        let sure = uzun ? 86_400 : (retryAfter ?? min(1800, taban * pow(2, Double(min(n - 1, 6)))))
        let bitis = Date().addingTimeInterval(sure)
        if let model { modelCooldowns["\(a.qualifiedId)|\(model)"] = bitis } else { cooldowns[a.qualifiedId] = bitis }
    }
    public func basarili(_ a: OAuthAccount) { ardisikHata[a.qualifiedId] = nil }
    public func modelSoguma(_ a: OAuthAccount, model: String) -> TimeInterval {
        max(0, (modelCooldowns["\(a.qualifiedId)|\(model)"] ?? .distantPast).timeIntervalSinceNow)
    }

    public func cooldownRemaining(_ qualifiedId: String) -> TimeInterval {
        max(0, (cooldowns[qualifiedId] ?? .distantPast).timeIntervalSinceNow)
    }

    /// Sunucunun `/x/oauth-access` ucundan sunucu sahipli hesapların güncel erişim belirteçlerini alır.
    public func syncFromServer(force: Bool = false) async throws {
        if !force, let lastSync, Date().timeIntervalSince(lastSync) < 20 { return }
        if let t = syncTask { return try await t.value }
        let task = Task { [vault, transport] in
            let remote = await vault.state.remote
            guard !remote.baseURL.isEmpty, !remote.syncToken.isEmpty else {
                throw ProxyError.noAccount("Sunucu eşitleme bilgisi yok (paket içe aktarılmadı)")
            }
            var base = remote.baseURL
            while base.hasSuffix("/") { base.removeLast() }
            guard let url = URL(string: base + "/x/oauth-access") else { throw ProxyError.badRequest("Sunucu adresi geçersiz") }
            var r = URLRequest(url: url)
            r.timeoutInterval = 15
            r.setValue(remote.personalToken, forHTTPHeaderField: "X-Personal-Token")
            r.setValue(remote.syncToken, forHTTPHeaderField: "X-Sync-Token")
            // İlk bağlantı ara sıra asılı kalabiliyor (canlı sınamada görüldü): kısa zaman aşımı + bir yeniden deneme.
            var resp: UpstreamResponse
            var data: Data
            do {
                resp = try await transport.send(r)
                data = try await resp.collect(limit: 1 << 20)
            } catch {
                resp = try await transport.send(r)
                data = try await resp.collect(limit: 1 << 20)
            }
            guard resp.status == 200, let list = (try? JSON.parse(data))?["accounts"]?.array else {
                throw ProxyError.upstream(status: resp.status == 200 ? 502 : resp.status,
                                          message: "Sunucu eşitlemesi başarısız (HTTP \(resp.status))")
            }
            try await vault.update { s in
                for item in list {
                    guard let p = item["provider"]?.string.flatMap(OAuthProviderKind.init(rawValue:)),
                          let id = item["id"]?.string, let at = item["access_token"]?.string,
                          let i = s.oauth.firstIndex(where: { $0.provider == p && $0.id == id && $0.refreshOwner == .sunucu })
                    else { continue }
                    s.oauth[i].accessToken = at
                    s.oauth[i].expiresAt = BundleImporter.date(item["expires_at"]?.string)
                    s.oauth[i].lastError = nil
                    for (k, v) in item["metadata"]?.object ?? [:] { if let x = v.string { s.oauth[i].metadata[k] = x } }
                }
            }
        }
        syncTask = task
        defer { syncTask = nil }
        try await task.value
        lastSync = Date()
    }
}
