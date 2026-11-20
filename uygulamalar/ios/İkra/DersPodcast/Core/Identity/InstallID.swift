import Foundation
import Security

/// Keychain'de küçük metin değerleri (yalnızca bu cihazda, ilk kilit açılışından sonra erişilebilir).
nonisolated enum KeychainStore {
    private static let service = "com.mehmetderin.derspodcast"

    static func string(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var query = baseQuery(account)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

/// Anonim kurulum kimliği (sunucudaki günlük sayaçlar için).
nonisolated enum InstallID {
    private static let account = "install-id"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: UUID?

    static var current: UUID {
        lock.withLock {
            if let cached { return cached }
            let id = KeychainStore.string(account).flatMap(UUID.init(uuidString:)) ?? {
                let new = UUID()
                KeychainStore.set(new.uuidString.lowercased(), for: account)
                return new
            }()
            cached = id
            return id
        }
    }
}

nonisolated extension InstallID {
    /// Başka bir kurulumun kimliğini devralır. Sunucu soru kaynaklarını kurulum kimliğine bağlar: Ders Video, Oku'dan
    /// taşınan soruların kaynaklarına ancak Oku'nun kimliğiyle ulaşabilir.
    static func adopt(_ id: UUID) {
        lock.withLock {
            KeychainStore.set(id.uuidString.lowercased(), for: account)
            cached = id
        }
    }
}

/// Claude API anahtarı: uygulama Claude'u doğrudan Anthropic API'sinden çağırır. Keychain'deki değer; yoksa derlemeye gömülü
/// (git dışı Secrets.xcconfig) anahtar. Anahtar yalnız ağ köprüsünde, Anthropic'e giden istekte kullanılır.
nonisolated enum ClaudeKey {
    private static let account = "claude-api-key"

    static var current: String? {
        if let stored = KeychainStore.string(account), !stored.isEmpty { return stored }
        let bundled = (Bundle.main.object(forInfoDictionaryKey: "BundledClaudeAPIKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return bundled.isEmpty || bundled.hasPrefix("$(") ? nil : bundled
    }

    static func set(_ key: String?) {
        KeychainStore.set(key?.trimmingCharacters(in: .whitespacesAndNewlines), for: account)
        // Yeni anahtar hemen denensin: eski anahtar yüzünden süren askı kaldırılır.
        Backend.resumeEngine()
    }
    /// Keychain'de anahtar yoksa derlemeye gömülü anahtar oraya alınır: anahtarı pakete koymayan sürümler (Release) de
    /// çalışmayı sürdürür; Keychain kaydı uygulama silinip kurulsa da kalır.
    static func seedFromBundleIfNeeded() {
        guard KeychainStore.string(account)?.isEmpty != false else { return }
        let bundled = (Bundle.main.object(forInfoDictionaryKey: "BundledClaudeAPIKey") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !bundled.isEmpty, !bundled.hasPrefix("$(") else { return }
        KeychainStore.set(bundled, for: account)
    }
    /// Keychain'de kayıtlı bir anahtar var mı (gömülü anahtar sayılmaz).
    static var stored: Bool { KeychainStore.string(account)?.isEmpty == false }
}

/// Kişisel sunucuya erişim anahtarı (`X-Personal-Token`). Sunucu ilk açılışta üretip konsola yazar.
nonisolated enum PersonalToken {
    private static let account = "personal-token"

    /// Keychain'deki değer; yoksa derlemeye gömülü (Secrets.xcconfig) anahtar.
    static var current: String? {
        if let stored = KeychainStore.string(account), !stored.isEmpty { return stored }
        let bundled = (Bundle.main.object(forInfoDictionaryKey: "BundledPersonalToken") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return bundled.isEmpty || bundled.hasPrefix("$(") ? nil : bundled
    }

    static func set(_ token: String?) {
        KeychainStore.set(token?.trimmingCharacters(in: .whitespacesAndNewlines), for: account)
    }
}
