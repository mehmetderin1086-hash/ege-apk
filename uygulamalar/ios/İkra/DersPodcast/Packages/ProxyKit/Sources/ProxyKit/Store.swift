import Foundation
import CryptoKit
import Security

// MARK: - Kalıcı veri modeli

public enum OAuthProviderKind: String, Codable, Sendable, CaseIterable {
    case claude, codex, gemini, antigravity
    public var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "ChatGPT / Codex"
        case .gemini: "Gemini (OAuth)"
        case .antigravity: "Antigravity"
        }
    }
    /// Yenileme belirtecini döndürmeyen sağlayıcı (Google): telefon kendisi yenileyebilir, sunucuyla çakışmaz.
    public var rotatesRefreshToken: Bool { self == .claude || self == .codex }
}

/// OAuth yenileme belirtecinin sahibi. Aynı hesabı iki yer yenilerse rotasyon
/// yüzünden biri düşer; bu yüzden tek sahip olmalı.
public enum RefreshOwner: String, Codable, Sendable {
    case sunucu   // erişim belirteci sunucudaki eşitleme ucundan çekilir
    case telefon  // telefon kendisi yeniler (sunucudaki kopya kapatılmalı)
}

public struct OAuthAccount: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var provider: OAuthProviderKind
    public var label: String
    public var enabled: Bool
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?
    public var scopes: [String]
    public var metadata: [String: String]
    public var refreshOwner: RefreshOwner
    public var lastError: String?

    public init(id: String, provider: OAuthProviderKind, label: String, enabled: Bool = true,
                accessToken: String, refreshToken: String?, expiresAt: Date?, scopes: [String] = [],
                metadata: [String: String] = [:], refreshOwner: RefreshOwner = .sunucu, lastError: String? = nil) {
        self.id = id; self.provider = provider; self.label = label; self.enabled = enabled
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiresAt = expiresAt
        self.scopes = scopes; self.metadata = metadata; self.refreshOwner = refreshOwner; self.lastError = lastError
    }

    public var qualifiedId: String { "\(provider.rawValue):\(id)" }

    public func expiresSoon(within seconds: TimeInterval = 120, now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) <= seconds
    }
}

public enum APIProviderKind: String, Codable, Sendable {
    case openAICompatible   // /chat/completions, /responses, /audio/speech ...
    case geminiNative       // generativelanguage.googleapis.com yerel uçları
    case anthropic          // api.anthropic.com /v1/messages, x-api-key ile (Claude OAuth'un yedeği ya da tek kaynağı)

    /// Eski sürümlerin bilmediği bir tür ortak kasadan okunursa çökmek yerine OpenAI uyumlu sayılır.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = APIProviderKind(rawValue: raw) ?? .openAICompatible
    }

    public var title: String {
        switch self {
        case .openAICompatible: "OpenAI uyumlu"
        case .geminiNative: "Gemini yerel uç"
        case .anthropic: "Claude API"
        }
    }
}

public struct APIKeyProvider: Codable, Sendable, Identifiable, Equatable {
    public var id: String { name }
    public var name: String
    public var kind: APIProviderKind
    public var baseURL: String
    public var apiKey: String
    public var models: [String]
    /// istemci adı → upstream model adı (ör. dersdas-gemini-ocr → gemini-3.8-flash)
    public var aliases: [String: String]
    /// bu modellere giden gövdeden çıkarılacak alanlar (sunucudaki payload.filter)
    public var filterParams: [String: [String]]
    public var enabled: Bool

    public init(name: String, kind: APIProviderKind, baseURL: String, apiKey: String, models: [String],
                aliases: [String: String] = [:], filterParams: [String: [String]] = [:], enabled: Bool = true) {
        self.name = name; self.kind = kind; self.baseURL = baseURL; self.apiKey = apiKey
        self.models = models; self.aliases = aliases; self.filterParams = filterParams; self.enabled = enabled
    }

    public func upstreamModel(_ model: String) -> String { aliases[model] ?? model }
}

public struct ClientKey: Codable, Sendable, Identifiable, Equatable {
    public var id: String { sha256 }
    public var name: String
    public var sha256: String
    public var enabled: Bool
    public init(name: String, sha256: String, enabled: Bool = true) {
        self.name = name; self.sha256 = sha256; self.enabled = enabled
    }
    public static func hash(_ raw: String) -> String {
        SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public struct RemoteProxy: Codable, Sendable, Equatable {
    /// ör. https://alanadi/dersdas/claude/v1 (sonunda /v1 olan taban)
    public var baseURL: String
    public var personalToken: String
    public var syncToken: String
    public var enabled: Bool
    /// telefondaki yol başarısız olursa isteği sunucuya düşür
    public var fallbackOnError: Bool
    public init(baseURL: String = "", personalToken: String = "", syncToken: String = "",
                enabled: Bool = false, fallbackOnError: Bool = true) {
        self.baseURL = baseURL; self.personalToken = personalToken; self.syncToken = syncToken
        self.enabled = enabled; self.fallbackOnError = fallbackOnError
    }
    public var isUsable: Bool { enabled && !baseURL.isEmpty }
    /// kök (…/v1 olmadan) — Gemini yerel yolları /v1beta/... köke eklenir
    public var rootURL: String {
        var s = baseURL
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix("/v1") { s.removeLast(3) }
        return s
    }
}

public struct ProxyState: Codable, Sendable, Equatable {
    public var oauth: [OAuthAccount] = []
    public var apiProviders: [APIKeyProvider] = []
    public var clientKeys: [ClientKey] = []
    /// telefona özgü yerel anahtar (düz metin; kullanıcıya gösterilir)
    public var localKey: String = ProxyState.newLocalKey()
    public var routing: [RouteRule] = []
    public var fallbacks: [String: [String]] = [:]
    public var defaultModel: String?
    public var remote: RemoteProxy = RemoteProxy()
    public var importedAt: Date?
    public var importSource: String?
    /// Eski kayıtlarda yoktur (isteğe bağlı → decodeIfPresent); `tasarruf` varsayılanı verir.
    public var tasarrufAyari: TasarrufAyarlari?
    public var tasarruf: TasarrufAyarlari {
        get { tasarrufAyari ?? TasarrufAyarlari() }
        set { tasarrufAyari = newValue }
    }

    public init() {}

    public static func newLocalKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return "sk-iphone-" + Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public struct RouteRule: Codable, Sendable, Equatable {
    public var pattern: String
    public var target: String
    public init(pattern: String, target: String) { self.pattern = pattern; self.target = target }
}

// MARK: - Saklama

public protocol SecretStore: Sendable {
    func load() throws -> Data?
    func save(_ data: Data) throws
    func clear() throws
}

public final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var blob: Data?
    public init(_ initial: Data? = nil) { blob = initial }
    public func load() throws -> Data? { lock.withLock { blob } }
    public func save(_ data: Data) throws { lock.withLock { blob = data } }
    public func clear() throws { lock.withLock { blob = nil } }
}

/// Bütün durum tek bir Keychain kaydında (JSON) saklanır.
/// `accessGroup` verilirse kayıt o ortak grupta tutulur; aynı ekibin öbür uygulamaları (İkra) da okuyabilir.
public struct KeychainSecretStore: SecretStore {
    /// CLI Proxy ile İkra'nın paylaştığı Keychain grubu (ekip öneki + ad). İki uygulamanın yetkisinde de bulunmalı.
    public static let sharedGroup = "838FF89FZ8.com.mehmetderin.ortak"

    let service: String
    let account: String
    let accessGroup: String?
    public init(service: String = "com.mehmetderin.cliproxy", account: String = "durum", accessGroup: String? = nil) {
        self.service = service; self.account = account; self.accessGroup = accessGroup
    }
    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
    private var query: [String: Any] {
        var q = baseQuery
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }
    private func read(_ q0: [String: Any]) throws -> Data? {
        var q = q0
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let st = SecItemCopyMatching(q as CFDictionary, &out)
        if st == errSecItemNotFound { return nil }
        guard st == errSecSuccess else { throw StoreError.keychain(st) }
        return out as? Data
    }
    public func load() throws -> Data? {
        if let d = try read(query) { return d }
        // Göç: ortak gruba geçmeden önce uygulamanın kendi grubuna yazılmış kayıt
        guard accessGroup != nil, let legacy = try? read(baseQuery) else { return nil }
        try save(legacy)
        if try read(query) != nil { _ = legacyDelete() }
        return legacy
    }
    /// Ortak grup dışındaki eski kaydı siler (ortak kayıt yazıldıktan sonra).
    private func legacyDelete() -> OSStatus {
        // Grup belirtilmeyen silme bütün grupları etkiler; bu yüzden eski kaydı yalnız kendi grubu dışında ararız.
        var q = baseQuery
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let items = out as? [[String: Any]] else { return errSecItemNotFound }
        var last: OSStatus = errSecSuccess
        for item in items {
            guard let g = item[kSecAttrAccessGroup as String] as? String, g != accessGroup else { continue }
            var d = baseQuery
            d[kSecAttrAccessGroup as String] = g
            last = SecItemDelete(d as CFDictionary)
        }
        return last
    }
    public func save(_ data: Data) throws {
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let st = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if st == errSecItemNotFound {
            var q = query
            attrs.forEach { q[$0.key] = $0.value }
            let add = SecItemAdd(q as CFDictionary, nil)
            guard add == errSecSuccess else { throw StoreError.keychain(add) }
        } else if st != errSecSuccess {
            throw StoreError.keychain(st)
        }
    }
    public func clear() throws {
        let st = SecItemDelete(query as CFDictionary)
        guard st == errSecSuccess || st == errSecItemNotFound else { throw StoreError.keychain(st) }
    }
}

public enum StoreError: Error, LocalizedError {
    case keychain(OSStatus)
    case locked(String)
    public var errorDescription: String? {
        switch self {
        case .keychain(let s): "Keychain hatası (\(s))"
        case .locked(let r): "\(r) — veri korunuyor, değişiklik kaydedilmedi"
        }
    }
}

// MARK: - İleriye dönük çözme: yeni alanlar eksikse varsayılan kullanılır

extension ProxyState {
    enum CodingKeys: String, CodingKey {
        case oauth, apiProviders, clientKeys, localKey, routing, fallbacks, defaultModel, remote, importedAt, importSource, tasarrufAyari
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        oauth = try c.decodeIfPresent([OAuthAccount].self, forKey: .oauth) ?? []
        apiProviders = try c.decodeIfPresent([APIKeyProvider].self, forKey: .apiProviders) ?? []
        clientKeys = try c.decodeIfPresent([ClientKey].self, forKey: .clientKeys) ?? []
        localKey = try c.decodeIfPresent(String.self, forKey: .localKey) ?? localKey
        routing = try c.decodeIfPresent([RouteRule].self, forKey: .routing) ?? []
        fallbacks = try c.decodeIfPresent([String: [String]].self, forKey: .fallbacks) ?? [:]
        defaultModel = try c.decodeIfPresent(String.self, forKey: .defaultModel)
        remote = try c.decodeIfPresent(RemoteProxy.self, forKey: .remote) ?? RemoteProxy()
        importedAt = try c.decodeIfPresent(Date.self, forKey: .importedAt)
        importSource = try c.decodeIfPresent(String.self, forKey: .importSource)
        tasarrufAyari = try c.decodeIfPresent(TasarrufAyarlari.self, forKey: .tasarrufAyari)
    }
}

extension OAuthAccount {
    enum CodingKeys: String, CodingKey {
        case id, provider, label, enabled, accessToken, refreshToken, expiresAt, scopes, metadata, refreshOwner, lastError
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  provider: try c.decode(OAuthProviderKind.self, forKey: .provider),
                  label: try c.decodeIfPresent(String.self, forKey: .label) ?? "",
                  enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
                  accessToken: try c.decode(String.self, forKey: .accessToken),
                  refreshToken: try c.decodeIfPresent(String.self, forKey: .refreshToken),
                  expiresAt: try c.decodeIfPresent(Date.self, forKey: .expiresAt),
                  scopes: try c.decodeIfPresent([String].self, forKey: .scopes) ?? [],
                  metadata: try c.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:],
                  refreshOwner: try c.decodeIfPresent(RefreshOwner.self, forKey: .refreshOwner) ?? .sunucu,
                  lastError: try c.decodeIfPresent(String.self, forKey: .lastError))
    }
}

extension RemoteProxy {
    enum CodingKeys: String, CodingKey { case baseURL, personalToken, syncToken, enabled, fallbackOnError }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(baseURL: try c.decodeIfPresent(String.self, forKey: .baseURL) ?? "",
                  personalToken: try c.decodeIfPresent(String.self, forKey: .personalToken) ?? "",
                  syncToken: try c.decodeIfPresent(String.self, forKey: .syncToken) ?? "",
                  enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
                  fallbackOnError: try c.decodeIfPresent(Bool.self, forKey: .fallbackOnError) ?? true)
    }
}

public extension ProxyState {
    /// Ortak kasadaki ham veriyi çözer (İkra'nın hızlı "kasa dolu mu" denetimi için).
    static func decode(_ data: Data) -> ProxyState? { try? Vault.decoder.decode(ProxyState.self, from: data) }
    /// Telefonda karşılanabilecek en az bir açık hesap ya da anahtar var mı
    var hasUsableAccounts: Bool { oauth.contains(where: \.enabled) || apiProviders.contains(where: \.enabled) }
}

/// Durumun tek yetkili sahibi. Bütün okuma/yazma buradan geçer.
public actor Vault {
    private let store: SecretStore
    public private(set) var state: ProxyState
    private var observers: [UUID: @Sendable (ProxyState) -> Void] = [:]

    /// Kayıt var ama okunamadıysa (Keychain geçici hatası, çözülemeyen biçim) yazma kilitlenir; boş durum
    /// gerçek kaydın üstüne yazılıp bütün hesapları silmesin.
    public private(set) var lockedReason: String?

    public init(store: SecretStore) {
        self.store = store
        do {
            if let data = try store.load() {
                do { state = try Vault.decoder.decode(ProxyState.self, from: data) }
                catch { state = ProxyState(); lockedReason = "Kasa çözülemedi: \(error.localizedDescription)" }
            } else {
                state = ProxyState()
            }
        } catch {
            state = ProxyState()
            lockedReason = "Kasa okunamadı: \(error.localizedDescription)"
        }
    }

    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    private var loadedAt = Date()

    /// Depodaki güncel durumu okur (başka uygulama — CLI Proxy ya da İkra — yazmış olabilir).
    @discardableResult
    public func reload() -> ProxyState {
        loadedAt = Date()
        if let data = try? store.load(), let s = try? Vault.decoder.decode(ProxyState.self, from: data) {
            lockedReason = nil
            if s != state {
                state = s
                for o in observers.values { o(s) }
            }
        }
        return state
    }

    /// Son okumadan bu yana `maxAge` geçtiyse yeniden okur.
    public func reloadIfStale(maxAge: TimeInterval = 2) {
        if Date().timeIntervalSince(loadedAt) > maxAge { reload() }
    }

    public func update(_ body: @Sendable (inout ProxyState) -> Void) throws {
        reload()   // yazmadan önce öbür uygulamanın değişikliklerini al, ezme
        if let lockedReason { throw StoreError.locked(lockedReason) }
        var s = state
        body(&s)
        try store.save(try Vault.encoder.encode(s))
        state = s
        for o in observers.values { o(s) }
    }

    public func updateAccount(_ qualifiedId: String, _ body: @Sendable (inout OAuthAccount) -> Void) throws {
        try update { s in
            if let i = s.oauth.firstIndex(where: { $0.qualifiedId == qualifiedId }) { body(&s.oauth[i]) }
        }
    }

    @discardableResult
    public func observe(_ fn: @escaping @Sendable (ProxyState) -> Void) -> UUID {
        let id = UUID()
        observers[id] = fn
        fn(state)
        return id
    }

    public func reset() throws {
        try store.clear()
        lockedReason = nil
        state = ProxyState()
        for o in observers.values { o(state) }
    }
}
