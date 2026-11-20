import Foundation
import Security
import ImageIO
import UniformTypeIdentifiers
import Observation
import Network

// MARK: - Anahtar deposu

/// Gemini API anahtarı. Kullanıcının Ayarlar'dan girdiği anahtar Keychain'de tutulur;
/// anahtar yoksa doğrudan Gemini istekleri kapalıdır; proxy ayrıca kullanılabilir.
///
/// Erişim anahtarları uygulama paketine eklenmez.
nonisolated enum GeminiKeyStore {
    private static let service = "com.mehmetderin.kitapkatalogu.gemini"
    private static let account = "apiKey"

    /// Eski çağıranlarla uyumluluk; paket içinde erişim anahtarı bulunmaz.
    static let bundledKey = ""

    /// Etkin anahtar yalnızca bu cihazın Keychain kaydından gelir.
    static var activeKey: String {
        let custom = loadCustomKey()
        return custom
    }

    static var isUsingBundledKey: Bool { false }

    /// Anahtar değişince (kaydet/sil) gönderilir; `GeminiDurumu` dinler.
    static let didChangeNotification = Notification.Name("GeminiKeyStore.didChange")

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedHasKey: Bool?
    nonisolated(unsafe) private static var lastReadBlocked = false

    /// Anahtar var mı? Yalnız varlık bilgisi Keychain'den bir kez okunur (veri çekilmez) ve önbelleklenir.
    /// Cihaz ilk kilit açılmadan önce Keychain okunamazsa (errSecInteractionNotAllowed) sonuç önbelleğe
    /// ALINMAZ ve `isReadBlocked` doğru olur; kilit açılınca bir sonraki okuma gerçeği bulur.
    static var hasKey: Bool {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let cachedHasKey { return cachedHasKey }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            lastReadBlocked = false; cachedHasKey = true; return true
        case errSecItemNotFound:
            lastReadBlocked = false; cachedHasKey = false; return false
        default:
            lastReadBlocked = true
            return false
        }
    }

    /// Son okuma Keychain kilitliyken denendiği için sonuçsuz kaldı mı?
    static var isReadBlocked: Bool {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return lastReadBlocked
    }

    static func invalidateKeyCache() {
        cacheLock.lock()
        cachedHasKey = nil
        lastReadBlocked = false
        cacheLock.unlock()
    }

    static func loadCustomKey() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { return "" }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "Anahtar güvenli depoya kaydedilemedi (\(status)). Önceki anahtar korunmuştur."
        }
    }

    /// Var olan anahtar yerinde güncellenir; hata halinde önce silinmez.
    static func saveCustomKeyVerified(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        defer {
            invalidateKeyCache()
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
        if trimmed.isEmpty {
            let status = SecItemDelete(base as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        let values: [String: Any] = [kSecValueData as String: Data(trimmed.utf8)]
        let updated = SecItemUpdate(base as CFDictionary, values as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw KeychainError(status: updated) }
        var insert = base
        insert[kSecValueData as String] = Data(trimmed.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    /// Eski çağıranlar için uyumluluk. Kullanıcıya sonuç gösteren akışlar throwing API kullanır.
    static func saveCustomKey(_ key: String) {
        do { try saveCustomKeyVerified(key) }
        catch { NSLog("Gemini güvenli depo yazımı başarısız") }
    }

}

// MARK: - Modeller ve ayarlar

/// Kullanılabilir Gemini modelleri (2026-09 itibarıyla anahtarın eriştiği liste).
nonisolated enum GeminiModel: String, CaseIterable, Identifiable, Sendable {
    case flash = "gemini-3.8-flash"
    case flashLite = "gemini-3.5-flash-lite"
    case pro = "gemini-3.1-pro-preview"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flash: "Gemini 3.8 Flash (önerilen)"
        case .flashLite: "Gemini 3.5 Flash Lite (hızlı/ekonomik)"
        case .pro: "Gemini 3.1 Pro (en güçlü, yavaş)"
        }
    }
}

/// Yapay zekâ ayarları — `UserDefaults` üzerinden, SwiftUI `@AppStorage` ile aynı anahtarlar.
nonisolated enum GeminiSettings {
    static let enabledKey = "geminiEnabled"
    static let ocrEnabledKey = "geminiOCREnabled"
    static let modelKey = "geminiModel"
    static let voiceRepliesKey = "geminiVoiceReplies"
    /// Kullanıcı, verilerin (soru, fotoğraf, katalog özeti) Google Gemini'ye gönderileceğini
    /// bir kez onaylamalı (App Store 5.1.2 / KVKK). Onay yoksa hiçbir AI isteği çıkmaz.
    static let consentKey = "geminiConsentGiven"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static var hasConsent: Bool {
        UserDefaults.standard.bool(forKey: consentKey)
    }

    /// Ayar, paylaşım onayı ve güvenli erişim birlikte gerekir.
    static var hasCredentials: Bool { proxyBaseURL != nil || GeminiKeyStore.hasKey }
    static var isActive: Bool { isEnabled && hasConsent && hasCredentials }

    static var statusDescription: String {
        if !isEnabled { return "Yapay zekâ kapalı" }
        if !hasConsent { return "Veri paylaşım onayı bekleniyor" }
        if !hasCredentials { return "Gemini kurulumu gerekli" }
        if GeminiUsage.isOverLimit() { return "Aylık istek sınırı doldu" }
        return "Gemini hazır"
    }

    static var isOCREnabled: Bool {
        isActive && (UserDefaults.standard.object(forKey: ocrEnabledKey) as? Bool ?? true)
    }

    static var model: GeminiModel {
        GeminiModel(rawValue: UserDefaults.standard.string(forKey: modelKey) ?? "") ?? .flash
    }

    static var voiceRepliesEnabled: Bool {
        UserDefaults.standard.object(forKey: voiceRepliesKey) as? Bool ?? true
    }
}

// MARK: - Gözlemlenebilir durum (önbellekli)

/// Ayar, onay ve anahtar varlığının tek, gözlemlenebilir kaynağı. Keychain ve UserDefaults okumaları
/// burada önbelleklenir; arayüz (`statusCard`, rozetler) her çizimde Keychain'e dokunmaz.
/// Statik `GeminiSettings` API'si korunur ve aynı önbelleği (`GeminiKeyStore.hasKey`) kullanır.
@MainActor @Observable
final class GeminiDurumu {
    static let shared = GeminiDurumu()

    private(set) var isEnabled = true
    private(set) var hasConsent = false
    private(set) var hasKey = false
    private(set) var hasProxy = false
    /// Keychain cihaz ilk kez kilit açılmadan okunmak istendi; anahtar var olabilir.
    private(set) var keyReadBlocked = false

    var hasCredentials: Bool { hasProxy || hasKey }
    var isActive: Bool { isEnabled && hasConsent && hasCredentials }

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = NotificationCenter.default
        for name in [UserDefaults.didChangeNotification, GeminiKeyStore.didChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    func refresh() {
        let enabled = GeminiSettings.isEnabled
        let consent = GeminiSettings.hasConsent
        let proxy = GeminiSettings.proxyBaseURL != nil
        let key = GeminiKeyStore.hasKey
        let blocked = GeminiKeyStore.isReadBlocked
        // Değişmeyen değeri yeniden yazmak gözlemcileri boşuna uyandırır
        if isEnabled != enabled { isEnabled = enabled }
        if hasConsent != consent { hasConsent = consent }
        if hasProxy != proxy { hasProxy = proxy }
        if hasKey != key { hasKey = key }
        if keyReadBlocked != blocked { keyReadBlocked = blocked }
    }
}

// MARK: - Erişilebilirlik probu

/// Google'a ulaşılabiliyor mu? Okul ağı Google'ı engelleyebilir; her istek 60 sn beklemesin diye
/// ön plana gelince ve ilk AI isteğinden önce 3 sn'lik HEAD probu çalışır.
@MainActor @Observable
final class GeminiReachability {
    static let shared = GeminiReachability()

    enum Durum: Equatable, Sendable {
        case bilinmiyor, ulasilabilir, cevrimdisi, engelliYavas

        var etiket: String {
            switch self {
            case .bilinmiyor: "Bağlantı denetlenmedi"
            case .ulasilabilir: "Gemini’ye ulaşılabiliyor"
            case .cevrimdisi: "Bağlantı yok"
            case .engelliYavas: "Gemini engelli ya da çok yavaş"
            }
        }
    }

    private(set) var durum: Durum = .bilinmiyor
    private(set) var lastProbe: Date?
    /// NWPathMonitor: ağ yolu hiç yoksa prob beklenmeden çevrimdışı sayılır.
    private(set) var pathAvailable = true
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var inFlight: Task<Durum, Never>?

    nonisolated static let probeTimeout: TimeInterval = 3
    nonisolated static let freshness: TimeInterval = 60

    /// Engelliyken: HD ses atlanır, OCR tek kısa denemeyle yetinir, asistan yerel yanıt verir.
    var isBlockedOrOffline: Bool { durum == .engelliYavas || durum == .cevrimdisi }
    /// Engelliyken OCR tek denemeyle ve en çok bu kadar saniye bekler.
    nonisolated static let blockedOCRTimeout: TimeInterval = 8
    /// HD ses kısa yanıtlar içindir; 6 sn'de gelmezse cihaz sesine düşülür.
    nonisolated static let ttsTimeout: TimeInterval = 6

    func startMonitoring() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pathAvailable = available
                if !available {
                    self.durum = .cevrimdisi
                } else if self.durum == .cevrimdisi {
                    // Bağlantı döndü: eski "çevrimdışı" sonucu bayat, bir sonraki istek yeniden yoklar
                    self.durum = .bilinmiyor
                    self.lastProbe = nil
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "kitapbul.gemini.path"))
        self.monitor = monitor
    }

    /// Sonuç tazeyse (60 sn) probu atlar.
    @discardableResult
    func probeIfStale(session: URLSession? = nil, now: Date = .now) async -> Durum {
        if let lastProbe, now.timeIntervalSince(lastProbe) < Self.freshness, durum != .bilinmiyor { return durum }
        return await probe(session: session, now: now)
    }

    @discardableResult
    func probe(session: URLSession? = nil, now: Date = .now) async -> Durum {
        if let inFlight { return await inFlight.value }
        guard pathAvailable else { durum = .cevrimdisi; lastProbe = now; return durum }
        let target = GeminiSettings.proxyBaseURL ?? URL(string: "https://generativelanguage.googleapis.com/")!
        let task = Task { await Self.classify(url: target, session: session) }
        inFlight = task
        let result = await task.value
        inFlight = nil
        durum = result
        lastProbe = now
        return result
    }

    /// Ağ yanıtı (herhangi bir HTTP durumu) = ulaşılabilir; zaman aşımı/bağlanamama = engelli ya da yavaş.
    nonisolated static func classify(url: URL, session: URLSession? = nil) async -> Durum {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = probeTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let session = session ?? {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = probeTimeout
            config.waitsForConnectivity = false
            return URLSession(configuration: config)
        }()
        do {
            let (_, response) = try await session.data(for: request)
            return response is HTTPURLResponse ? .ulasilabilir : .engelliYavas
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff: return .cevrimdisi
            case .cancelled: return .bilinmiyor
            default: return .engelliYavas
            }
        } catch {
            return .bilinmiyor
        }
    }
}

// MARK: - İstek / yanıt tipleri (Gemini REST API)

nonisolated struct GeminiPart: Codable, Sendable {
    struct InlineData: Codable, Sendable {
        var mimeType: String
        var data: String
    }

    var text: String?
    var inlineData: InlineData?
    /// Düşünme (thinking) parçaları yanıtta `thought: true` ile gelir; metne katılmaz.
    var thought: Bool?

    init(text: String) {
        self.text = text
    }

    init(imageData: Data, mimeType: String = "image/jpeg") {
        inlineData = InlineData(mimeType: mimeType, data: imageData.base64EncodedString())
    }
}

nonisolated struct GeminiContent: Codable, Sendable {
    var role: String?
    var parts: [GeminiPart]
}

nonisolated struct GeminiGenerationConfig: Codable, Sendable {
    struct SpeechConfig: Codable, Sendable {
        struct VoiceConfig: Codable, Sendable {
            struct Prebuilt: Codable, Sendable { var voiceName: String }
            var prebuiltVoiceConfig: Prebuilt
        }
        var voiceConfig: VoiceConfig
    }

    var temperature: Double?
    var maxOutputTokens: Int?
    var responseMimeType: String?
    /// TTS için ["AUDIO"].
    var responseModalities: [String]?
    var speechConfig: SpeechConfig?
    var thinkingConfig: ThinkingConfig?

    struct ThinkingConfig: Codable, Sendable, Equatable { var thinkingBudget: Int }
}

/// İsteğin düşünme (thinking) bütçesi. Çıkarım işlerinde kapalı tutmak gecikmeyi ve jetonu düşürür.
nonisolated enum GeminiThinking: Sendable, Equatable {
    /// OCR, raf dilimi, dikte, kategori eşleme, tamamlama: düşünme kapalı (Pro kapatılamaz, en düşük bütçe).
    case off
    /// Asistan sohbeti, koleksiyon analizi: modelin kendi kararı.
    case auto

    static let proMinimumBudget = 128

    func config(for model: GeminiModel) -> GeminiGenerationConfig.ThinkingConfig? {
        switch self {
        case .auto: nil
        case .off: .init(thinkingBudget: model == .pro ? Self.proMinimumBudget : 0)
        }
    }
}

/// `thinkingConfig` alanını reddeden (400) modeller bir kez öğrenilir; sonraki istekler alanı hiç göndermez.
nonisolated enum GeminiThinkingSupport {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var unsupported: Set<String> = []

    static func isUnsupported(_ model: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return unsupported.contains(model)
    }

    static func markUnsupported(_ model: String) {
        lock.lock(); defer { lock.unlock() }
        unsupported.insert(model)
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        unsupported.removeAll()
    }
}

// MARK: - Gemini TTS (HD sesler)

/// Gemini TTS'in hazır sesleri. Hepsi çok dilli (Türkçe okur); karakter notları rehber niteliğinde.
nonisolated enum GeminiTTSVoice: String, CaseIterable, Identifiable, Sendable {
    case kore = "Kore"
    case aoede = "Aoede"
    case leda = "Leda"
    case zephyr = "Zephyr"
    case puck = "Puck"
    case charon = "Charon"
    case fenrir = "Fenrir"
    case orus = "Orus"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kore: "Kore — kadın, net ve sakin (önerilen)"
        case .aoede: "Aoede — kadın, rahat"
        case .leda: "Leda — kadın, genç ve canlı"
        case .zephyr: "Zephyr — kadın, parlak"
        case .puck: "Puck — erkek, enerjik"
        case .charon: "Charon — erkek, bilgilendirici"
        case .fenrir: "Fenrir — erkek, heyecanlı"
        case .orus: "Orus — erkek, kararlı"
        }
    }
}

nonisolated extension GeminiSettings {
    static let ttsEnabledKey = "geminiTTSEnabled"
    static let ttsVoiceKey = "geminiTTSVoice"

    /// Sesli yanıtlar Gemini HD sesle mi okunsun? (Kapalıysa/çevrimdışıysa cihaz sesi.)
    static var isTTSEnabled: Bool {
        isActive && (UserDefaults.standard.object(forKey: ttsEnabledKey) as? Bool ?? true)
    }

    static var ttsVoice: GeminiTTSVoice {
        GeminiTTSVoice(rawValue: UserDefaults.standard.string(forKey: ttsVoiceKey) ?? "") ?? .kore
    }

    /// Hızlı mod: Gemini emin ve ISBN doğrulanmışsa tarama sonucu onaysız kaydedilir.
    static let quickSaveKey = "geminiQuickSave"
    /// Konuşma tanıma cihaz üstünde (internetsiz) çalışsın.
    static let speechOnDeviceKey = "speechOnDevice"
    /// Sesli kayıtta uzun cümle yerine kısa onay (tık + titreşim); şüpheli alan varsa yine konuşur.
    static let briefConfirmKey = "voiceEntryBriefConfirm"
    /// Gemini isteklerini kendi sunucunuza (vekil) yönlendirmek için taban adres; boşsa doğrudan Google.
    static let proxyURLKey = "geminiProxyURL"

    static var isQuickSaveEnabled: Bool {
        isActive && UserDefaults.standard.bool(forKey: quickSaveKey)
    }

    static var prefersOnDeviceSpeech: Bool {
        UserDefaults.standard.bool(forKey: speechOnDeviceKey)
    }

    static var prefersBriefConfirm: Bool {
        UserDefaults.standard.bool(forKey: briefConfirmKey)
    }

    /// Vekil sunucu adresi (ör. https://okul.example.com/gemini/). Geçersizse yoksayılır.
    static var proxyBaseURL: URL? {
        let raw = UserDefaults.standard.string(forKey: proxyURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty, let url = URL(string: raw.hasSuffix("/") ? raw : raw + "/"),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        let scheme = url.scheme?.lowercased()
        let local = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())
        guard scheme == "https" || (scheme == "http" && local) else { return nil }
        return url
    }
}

// MARK: - Kullanım sayacı (aylık istek/jeton)

/// Aylık istek ve jeton sayacı (Ayarlar'da gösterilir; maliyet takibi için).
nonisolated enum GeminiUsage {
    private static let key = "geminiUsage"
    private static let lock = NSRecursiveLock()

    static let ttsModelName = "gemini-3.8-flash-tts"

    /// Tek modelin aylık kullanımı (TTS de ayrı bir kalemdir).
    struct ModelUsage: Codable, Sendable, Equatable {
        var requests: Int = 0
        var promptTokens: Int = 0
        var outputTokens: Int = 0
    }

    struct Snapshot: Codable, Sendable, Equatable {
        var month: String           // "2026-09"
        var requests: Int = 0
        var promptTokens: Int = 0
        var outputTokens: Int = 0
        var failures: Int = 0
        /// Yeniden denemeler `requests`e eklenmez; aylık sınırı tüketmez.
        var retries: Int = 0
        var byModel: [String: ModelUsage] = [:]

        init(month: String, requests: Int = 0, promptTokens: Int = 0, outputTokens: Int = 0,
             failures: Int = 0, retries: Int = 0, byModel: [String: ModelUsage] = [:]) {
            self.month = month
            self.requests = requests
            self.promptTokens = promptTokens
            self.outputTokens = outputTokens
            self.failures = failures
            self.retries = retries
            self.byModel = byModel
        }

        /// Eski kayıtlarda `retries`/`byModel` yoktur.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            month = try c.decode(String.self, forKey: .month)
            requests = try c.decodeIfPresent(Int.self, forKey: .requests) ?? 0
            promptTokens = try c.decodeIfPresent(Int.self, forKey: .promptTokens) ?? 0
            outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
            failures = try c.decodeIfPresent(Int.self, forKey: .failures) ?? 0
            retries = try c.decodeIfPresent(Int.self, forKey: .retries) ?? 0
            byModel = try c.decodeIfPresent([String: ModelUsage].self, forKey: .byModel) ?? [:]
        }

        var tts: ModelUsage { byModel[GeminiUsage.ttsModelName] ?? ModelUsage() }
    }

    static func currentMonth(_ date: Date = .now) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    static func load() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        let month = currentMonth()
        if let data = UserDefaults.standard.data(forKey: key),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
           snapshot.month == month {
            return snapshot
        }
        return Snapshot(month: month)
    }

    static func record(promptTokens: Int, outputTokens: Int, failed: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        var snapshot = load()
        snapshot.requests += 1
        snapshot.promptTokens += max(0, promptTokens)
        snapshot.outputTokens += max(0, outputTokens)
        if failed { snapshot.failures += 1 }
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Birden çok raf dilimi aynı anda başlasa da aylık kapı tek kez ve atomik okunur.
    /// Aylık sınır dolduysa fırlatır ve hiçbir sayaç değiştirmez (çağıran `finishRequest` çağırmamalı).
    /// `isRetry`: aynı mantıksal isteğin yeniden denemesi; sınırı yeniden denetlemez, `retries`a yazılır.
    static func beginRequest(isRetry: Bool = false, model: String? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        var snapshot = load()
        if isRetry {
            snapshot.retries += 1
        } else {
            guard !isOverLimit(snapshot) else { throw GeminiError.limitReached(monthlyLimit) }
            snapshot.requests += 1
            if let model { snapshot.byModel[model, default: ModelUsage()].requests += 1 }
        }
        if let data = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func finishRequest(promptTokens: Int, outputTokens: Int, failed: Bool = false, model: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        var snapshot = load()
        snapshot.promptTokens += max(0, promptTokens)
        snapshot.outputTokens += max(0, outputTokens)
        if failed { snapshot.failures += 1 }
        if let model {
            snapshot.byModel[model, default: ModelUsage()].promptTokens += max(0, promptTokens)
            snapshot.byModel[model, default: ModelUsage()].outputTokens += max(0, outputTokens)
        }
        if let data = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: Aylık sınır ve tahmini maliyet

    static let limitKey = "geminiMonthlyRequestLimit"
    static let inputPriceKey = "geminiInputPricePerMillion"
    static let outputPriceKey = "geminiOutputPricePerMillion"
    /// Varsayılan fiyatlar (ABD doları / 1M jeton) yalnız tahmin içindir; Ayarlar'dan güncellenebilir.
    static let defaultInputPrice = 0.30
    static let defaultOutputPrice = 2.50

    /// 0 = sınırsız
    static var monthlyLimit: Int {
        max(0, UserDefaults.standard.integer(forKey: limitKey))
    }

    static func isOverLimit(_ snapshot: Snapshot = load(), limit: Int = monthlyLimit) -> Bool {
        limit > 0 && snapshot.requests >= limit
    }

    /// Model başına tahmini maliyet. Fiyatlar doğrulanmadı: arayüzde "tahmini" etiketiyle gösterilir.
    /// Model kırılımı olmayan (eski) jetonlar genel fiyatla hesaplanır.
    static let costLabel = "Tahmini"

    static func estimatedCostByModel(_ snapshot: Snapshot = load()) -> [(model: String, usd: Double)] {
        snapshot.byModel
            .map { name, usage in
                (model: name, usd: estimatedCostUSD(Snapshot(month: snapshot.month, promptTokens: usage.promptTokens, outputTokens: usage.outputTokens)))
            }
            .sorted { $0.model < $1.model }
    }

    static func estimatedCostUSD(_ snapshot: Snapshot = load(),
                                 inputPrice: Double? = nil, outputPrice: Double? = nil) -> Double {
        let defaults = UserDefaults.standard
        let inPrice = inputPrice ?? (defaults.object(forKey: inputPriceKey) as? Double ?? defaultInputPrice)
        let outPrice = outputPrice ?? (defaults.object(forKey: outputPriceKey) as? Double ?? defaultOutputPrice)
        return Double(snapshot.promptTokens) / 1_000_000 * inPrice + Double(snapshot.outputTokens) / 1_000_000 * outPrice
    }
}

nonisolated struct GeminiRequest: Codable, Sendable {
    var contents: [GeminiContent]
    var systemInstruction: GeminiContent?
    var generationConfig: GeminiGenerationConfig?
}

nonisolated struct GeminiResponse: Decodable, Sendable {
    /// Yanıt içeriği: MAX_TOKENS gibi durumlarda `content` boş `{}` gelebilir,
    /// bu yüzden `parts` isteğe bağlı çözülür.
    struct Content: Decodable, Sendable {
        var role: String?
        var parts: [GeminiPart]?
    }
    struct Candidate: Decodable, Sendable {
        var content: Content?
        var finishReason: String?
    }
    struct PromptFeedback: Decodable, Sendable {
        var blockReason: String?
    }
    struct APIError: Decodable, Sendable {
        var code: Int?
        var message: String?
        var status: String?
    }

    struct UsageMetadata: Decodable, Sendable {
        var promptTokenCount: Int?
        var candidatesTokenCount: Int?
        var thoughtsTokenCount: Int?
        var totalTokenCount: Int?
    }

    var candidates: [Candidate]?
    var promptFeedback: PromptFeedback?
    var usageMetadata: UsageMetadata?
    var error: APIError?

    /// Düşünme parçaları hariç, ilk adayın metni.
    var text: String {
        guard let parts = candidates?.first?.content?.parts else { return "" }
        return parts
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined()
    }

    var finishReason: String? { candidates?.first?.finishReason }
}

nonisolated enum GeminiError: LocalizedError, Sendable {
    case missingKey
    case disabled
    case consentRequired
    case http(Int, String)
    case blocked(String)
    case emptyResponse(String?)
    case decoding(String)
    case network(String)
    case limitReached(Int)

    var errorDescription: String? {
        switch self {
        case .missingKey: "Gemini API anahtarı girilmemiş. Ayarlar > Yapay Zekâ bölümünden ekleyin."
        case .disabled: "Yapay zekâ özellikleri ayarlardan kapatılmış."
        case .consentRequired: "Yapay zekâ kullanımı için veri paylaşım onayı gerekli. Ayarlar › Yapay Zekâ bölümünden onay verin."
        case .http(let code, let message):
            switch code {
            case 400: "Gemini isteği reddedildi: \(message)"
            case 401, 403: "Gemini API anahtarı geçersiz ya da yetkisiz (\(code))."
            case 429: "Gemini kullanım sınırı aşıldı; biraz bekleyip yeniden deneyin."
            case 500...599: "Gemini sunucusu geçici olarak yanıt vermiyor (\(code))."
            default: "Gemini hatası (\(code)): \(message)"
            }
        case .blocked(let reason): "İçerik güvenlik filtresi tarafından engellendi (\(reason))."
        case .emptyResponse(let reason):
            switch reason {
            case "MAX_TOKENS": "Yanıt uzunluk sınırına takıldı; daha kısa bir istek deneyin."
            case "SAFETY", "RECITATION": "Gemini bu içerik için yanıt üretmedi (\(reason ?? "")). "
            case .some(let value): "Gemini boş yanıt döndürdü (\(value))."
            case .none: "Gemini boş yanıt döndürdü."
            }
        case .decoding(let detail): "Gemini yanıtı çözümlenemedi: \(detail.prefix(160))"
        case .network(let detail): "Ağ hatası: \(detail)"
        case .limitReached(let limit): "Bu ayki yapay zekâ sınırına (\(limit) istek) ulaşıldı. Ayarlar > Yapay Zekâ bölümünden sınırı artırabilirsiniz."
        }
    }
}

// MARK: - İstemci

/// Gemini Developer API (generativelanguage.googleapis.com) istemcisi.
/// Tüm çağrılar arka planda çalışır; 429/5xx'te kısa bekleyip bir kez daha dener.
nonisolated final class GeminiClient: Sendable {
    static let shared = GeminiClient()

    private let session: URLSession
    /// Yeniden denemeler arasındaki taban bekleme (sn); testler sıfırlar.
    private let retryBaseDelay: TimeInterval
    static let maxExpandedOutputTokens = 16_384
    private static let googleBaseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/")!

    /// Vekil sunucu ayarlıysa istekler oraya gider (anahtar vekilde tutulabilir); yoksa Google.

    init(session: URLSession? = nil, retryBaseDelay: TimeInterval = 2.5) {
        self.retryBaseDelay = retryBaseDelay
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 120
            // Bağlantı yoksa beklemeden hata ver: tarama akışı Vision sonucuna hemen düşer
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }

    /// Serbest metin yanıtı.
    /// - Parameters:
    ///   - timeout: Bu isteğin üst süresi (sn). OCR gibi bekletmemesi gereken akışlar kısa verir.
    ///   - maxAttempts: 429/5xx/ağ hatasında toplam deneme sayısı.
    ///   - thinking: Düşünme bütçesi. Çıkarım/OCR işlerinde `.off` (varsayılan), sohbet ve analizde `.auto`.
    func generateText(
        prompt: String,
        system: String? = nil,
        images: [Data] = [],
        history: [GeminiContent] = [],
        model: GeminiModel? = nil,
        temperature: Double = 0.4,
        maxOutputTokens: Int = 4096,
        json: Bool = false,
        timeout: TimeInterval = 60,
        maxAttempts: Int = 3,
        thinking: GeminiThinking = .off
    ) async throws -> String {
        guard GeminiSettings.isEnabled else { throw GeminiError.disabled }
        guard GeminiSettings.hasConsent else { throw GeminiError.consentRequired }
        guard !GeminiUsage.isOverLimit() else { throw GeminiError.limitReached(GeminiUsage.monthlyLimit) }
        let key = GeminiKeyStore.activeKey
        let proxyURL = GeminiSettings.proxyBaseURL
        guard !key.isEmpty || proxyURL != nil else { throw GeminiError.missingKey }

        var parts: [GeminiPart] = images.map { GeminiPart(imageData: $0) }
        parts.append(GeminiPart(text: prompt))
        let contents = history + [GeminiContent(role: "user", parts: parts)]
        let systemInstruction = system.map { GeminiContent(role: nil, parts: [GeminiPart(text: $0)]) }

        let resolvedModel = model ?? GeminiSettings.model
        let modelName = resolvedModel.rawValue
        var thinkingConfig = GeminiThinkingSupport.isUnsupported(modelName) ? nil : thinking.config(for: resolvedModel)
        var outputBudget = maxOutputTokens
        func encodeBody() throws -> Data {
            try JSONEncoder().encode(GeminiRequest(
                contents: contents,
                systemInstruction: systemInstruction,
                generationConfig: GeminiGenerationConfig(
                    temperature: temperature,
                    maxOutputTokens: outputBudget,
                    responseMimeType: json ? "application/json" : nil,
                    thinkingConfig: thinkingConfig
                )
            ))
        }

        let url = (proxyURL ?? Self.googleBaseURL).appendingPathComponent("\(modelName):generateContent")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if proxyURL == nil {
            urlRequest.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        }

        var lastError: GeminiError = .emptyResponse(nil)
        var attempt = 0
        var requestStarted = false
        var droppedThinking = false
        var expandedBudget = false
        while attempt < max(1, maxAttempts) {
            // Ücretsiz yeniden denemeler (alan düşürme, jeton bütçesi) bu sayacı geri alır.
            defer { attempt += 1 }
            if attempt > 0 {
                try await Task.sleep(for: .seconds(Double(attempt) * retryBaseDelay))
            }
            try Task.checkCancellation()
            // Sınır yalnız ilk denemede denetlenir; yeniden denemeler ayrı sayılır
            try GeminiUsage.beginRequest(isRetry: requestStarted, model: modelName)
            requestStarted = true
            urlRequest.httpBody = try encodeBody()
            var recorded = false
            func finish(_ decoded: GeminiResponse?, failed: Bool) {
                GeminiUsage.finishRequest(
                    promptTokens: decoded?.usageMetadata?.promptTokenCount ?? 0,
                    outputTokens: (decoded?.usageMetadata?.candidatesTokenCount ?? 0) + (decoded?.usageMetadata?.thoughtsTokenCount ?? 0),
                    failed: failed, model: modelName)
                recorded = true
            }
            do {
                let (data, response) = try await session.data(for: urlRequest)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let decoded = try? JSONDecoder().decode(GeminiResponse.self, from: data)

                if status == 429 || (500...599).contains(status) {
                    finish(decoded, failed: true)
                    lastError = .http(status, decoded?.error?.message ?? "")
                    continue
                }
                guard (200...299).contains(status) else {
                    // Model thinkingConfig alanını tanımıyorsa (400) alan düşürülüp bir kez daha denenir
                    if status == 400, thinkingConfig != nil, !droppedThinking {
                        droppedThinking = true
                        thinkingConfig = nil
                        finish(decoded, failed: true)
                        attempt -= 1
                        continue
                    }
                    let message = decoded?.error?.message
                        ?? String(decoding: data.prefix(300), as: UTF8.self)
                    throw GeminiError.http(status, message)
                }
                guard let decoded else {
                    throw GeminiError.decoding(String(decoding: data.prefix(160), as: UTF8.self))
                }
                if droppedThinking { GeminiThinkingSupport.markUnsupported(modelName) }
                let invalid = decoded.promptFeedback?.blockReason != nil
                    || decoded.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || (json && decoded.finishReason == "MAX_TOKENS")
                finish(decoded, failed: invalid)
                if let reason = decoded.promptFeedback?.blockReason {
                    throw GeminiError.blocked(reason)
                }
                // JSON yarıda kesildiyse jeton bütçesi bir kez ikiye katlanıp yeniden denenir
                if json, decoded.finishReason == "MAX_TOKENS", !expandedBudget {
                    expandedBudget = true
                    outputBudget = min(outputBudget * 2, Self.maxExpandedOutputTokens)
                    attempt -= 1
                    continue
                }
                let text = decoded.text
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw GeminiError.emptyResponse(decoded.finishReason)
                }
                if json, decoded.finishReason == "MAX_TOKENS" {
                    throw GeminiError.emptyResponse("MAX_TOKENS")
                }
                return text
            } catch let error as GeminiError {
                if !recorded { finish(nil, failed: true) }
                throw error
            } catch is CancellationError {
                if !recorded { finish(nil, failed: true) }
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                if !recorded { finish(nil, failed: true) }
                throw CancellationError()
            } catch let error as URLError where error.code == .notConnectedToInternet
                        || error.code == .dataNotAllowed || error.code == .internationalRoamingOff {
                if !recorded { finish(nil, failed: true) }
                // Bağlantı yokken tekrar denemek yalnızca bekletir
                throw GeminiError.network("İnternet bağlantısı yok.")
            } catch {
                if !recorded { finish(nil, failed: true) }
                lastError = .network(error.localizedDescription)
                continue
            }
        }
        throw lastError
    }

    /// Metni Gemini TTS ile seslendirir; WAV (24 kHz, 16 bit, mono) verisi döner.
    /// Model: gemini-3.8-flash-tts. Uzun metinler kısaltılır (sesli yanıt zaten kısadır).
    func synthesizeSpeech(
        _ text: String,
        voice: GeminiTTSVoice? = nil,
        timeout: TimeInterval = 20
    ) async throws -> Data {
        guard GeminiSettings.isEnabled else { throw GeminiError.disabled }
        guard GeminiSettings.hasConsent else { throw GeminiError.consentRequired }
        guard !GeminiUsage.isOverLimit() else { throw GeminiError.limitReached(GeminiUsage.monthlyLimit) }
        let key = GeminiKeyStore.activeKey
        let proxyURL = GeminiSettings.proxyBaseURL
        guard !key.isEmpty || proxyURL != nil else { throw GeminiError.missingKey }

        let spoken = String(text.prefix(1200))
        let request = GeminiRequest(
            contents: [GeminiContent(role: "user", parts: [GeminiPart(text: spoken)])],
            systemInstruction: nil,
            generationConfig: GeminiGenerationConfig(
                responseModalities: ["AUDIO"],
                speechConfig: .init(voiceConfig: .init(prebuiltVoiceConfig: .init(
                    voiceName: (voice ?? GeminiSettings.ttsVoice).rawValue
                )))
            )
        )
        let url = (proxyURL ?? Self.googleBaseURL).appendingPathComponent("\(GeminiUsage.ttsModelName):generateContent")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if proxyURL == nil {
            urlRequest.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        }
        urlRequest.httpBody = try JSONEncoder().encode(request)

        try GeminiUsage.beginRequest(model: GeminiUsage.ttsModelName)
        var promptTokens = 0, outputTokens = 0, succeeded = false
        defer { GeminiUsage.finishRequest(promptTokens: promptTokens, outputTokens: outputTokens, failed: !succeeded, model: GeminiUsage.ttsModelName) }
        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let decoded = try? JSONDecoder().decode(GeminiResponse.self, from: data)
        promptTokens = decoded?.usageMetadata?.promptTokenCount ?? 0
        outputTokens = decoded?.usageMetadata?.candidatesTokenCount ?? 0
        guard (200...299).contains(status) else { throw GeminiError.http(status, decoded?.error?.message ?? "") }
        guard let inline = decoded?.candidates?.first?.content?.parts?
                .compactMap(\.inlineData).first,
              inline.mimeType.hasPrefix("audio/"),
              let audio = Data(base64Encoded: inline.data), !audio.isEmpty else {
            throw GeminiError.emptyResponse(decoded?.finishReason)
        }
        succeeded = true
        return Self.ensureWAVHeader(audio, mimeType: inline.mimeType)
    }

    /// API bazen başlıksız PCM (audio/L16;rate=24000) döndürür; AVAudioPlayer için WAV başlığı eklenir.
    nonisolated static func ensureWAVHeader(_ audio: Data, mimeType: String) -> Data {
        if audio.count >= 4, audio.prefix(4) == Data("RIFF".utf8) { return audio }
        let rate = mimeType.split(separator: ";")
            .compactMap { part -> UInt32? in
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("rate=") else { return nil }
                return UInt32(trimmed.dropFirst(5))
            }
            .first ?? 24_000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = rate * UInt32(channels) * UInt32(bitsPerSample / 8)
        var header = Data()
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) } }
        header.append(contentsOf: Array("RIFF".utf8))
        append32(UInt32(clamping: 36 + audio.count))
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8))
        append32(16)
        append16(1)                      // PCM
        append16(channels)
        append32(rate)
        append32(byteRate)
        append16(channels * bitsPerSample / 8)
        append16(bitsPerSample)
        header.append(contentsOf: Array("data".utf8))
        append32(UInt32(clamping: audio.count))
        return header + audio
    }

    /// JSON yanıtı ister, kod çitlerini temizler ve verilen tipe çözer.
    func generateJSON<T: Decodable>(
        _ type: T.Type,
        prompt: String,
        system: String? = nil,
        images: [Data] = [],
        history: [GeminiContent] = [],
        model: GeminiModel? = nil,
        temperature: Double = 0.2,
        maxOutputTokens: Int = 4096,
        timeout: TimeInterval = 60,
        maxAttempts: Int = 3,
        thinking: GeminiThinking = .off
    ) async throws -> T {
        let raw = try await generateText(
            prompt: prompt, system: system, images: images, history: history,
            model: model, temperature: temperature, maxOutputTokens: maxOutputTokens, json: true,
            timeout: timeout, maxAttempts: maxAttempts, thinking: thinking
        )
        return try GeminiJSON.decode(type, from: raw)
    }
}

// MARK: - JSON yardımcıları

/// Modelin döndürdüğü metinden JSON'u güvenle ayıklar: ```json çitleri, baştaki/sondaki
/// açıklama cümleleri ve tek tırnak gibi küçük bozukluklar temizlenir.
nonisolated enum GeminiJSON {
    static func extract(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            // ```json\n ... \n```
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
            if let fenceEnd = cleaned.range(of: "```", options: .backwards) {
                cleaned = String(cleaned[..<fenceEnd.lowerBound])
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Metnin içine gömülü JSON: ilk { veya [ ile son } veya ] arasını al
        let openers: Set<Character> = ["{", "["]
        if let first = cleaned.firstIndex(where: { openers.contains($0) }) {
            let opener = cleaned[first]
            let closer: Character = opener == "{" ? "}" : "]"
            if let last = cleaned.lastIndex(of: closer), last > first {
                cleaned = String(cleaned[first...last])
            }
        }
        return cleaned
    }

    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let decoder = JSONDecoder()
        // Önce ham metni dene (responseMimeType=json ile çoğunlukla saf JSON gelir);
        // olmazsa çit/açıklama temizliğiyle yeniden dene.
        if let direct = try? decoder.decode(type, from: Data(text.utf8)) {
            return direct
        }
        let json = extract(from: text)
        do {
            return try decoder.decode(type, from: Data(json.utf8))
        } catch {
            throw GeminiError.decoding("\(error.localizedDescription) — \(json.prefix(120))")
        }
    }
}

// MARK: - Görüntü hazırlama

/// Fotoğrafı Gemini'ye göndermeden önce küçültüp JPEG'e çevirir: kapak fotoğrafı
/// 12 MP yerine ~1.6 MP olarak gider, jeton ve süre onda birine iner.
nonisolated enum GeminiImagePreparer {
    static func jpegData(from data: Data, maxPixel: Int = 1600, quality: Double = 0.82) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
