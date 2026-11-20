import Foundation

/// Sunucudaki `telefon-paketi.py` betiğinin ürettiği taşıma paketi (sürüm 1).
public struct MigrationBundle: Codable, Sendable {
    public struct OAuth: Codable, Sendable {
        public var provider: String
        public var id: String
        public var label: String?
        public var enabled: Bool
        public var access_token: String
        public var refresh_token: String?
        public var expires_at: String?
        public var scopes: [String]?
        public var metadata: [String: JSON]?
    }
    public struct APIKey: Codable, Sendable {
        public var name: String
        public var kind: String              // "openai" | "gemini-native" | "anthropic"
        public var base_url: String
        public var api_key: String
        public var models: [String]
        public var aliases: [String: String]?
        public var filter: [String: [String]]?
        public var enabled: Bool?
    }
    public struct Client: Codable, Sendable {
        public var name: String
        public var sha256: String
        public var enabled: Bool
    }
    public struct Remote: Codable, Sendable {
        public var base_url: String
        public var personal_token: String?
        public var sync_token: String?
    }
    public var surum: Int
    public var olusturma: String?
    public var kaynak: String?
    public var oauth: [OAuth]
    public var api_anahtarlari: [APIKey]
    public var istemci_anahtarlari: [Client]?
    public var yonlendirme: [[String]]?       // [[desen, hedef], ...] sıra korunur
    public var yedekler: [String: [String]]?
    public var varsayilan_model: String?
    public var uzak: Remote?
}

public struct ImportSummary: Sendable, Equatable {
    public var oauth: Int
    public var apiProviders: Int
    public var clientKeys: Int
    public var routes: Int
    public var remote: Bool
    public var text: String {
        "\(oauth) OAuth hesabı, \(apiProviders) API sağlayıcısı, \(clientKeys) istemci anahtarı, \(routes) yönlendirme kuralı"
            + (remote ? ", sunucu bağlantısı" : "")
    }
}

public enum BundleError: Error, LocalizedError {
    case unsupported(Int)
    case invalid(String)
    public var errorDescription: String? {
        switch self {
        case .unsupported(let v): "Desteklenmeyen paket sürümü: \(v)"
        case .invalid(let s): "Geçersiz paket: \(s)"
        }
    }
}

public enum BundleImporter {
    public static func decode(_ data: Data) throws -> MigrationBundle {
        let b: MigrationBundle
        do { b = try JSONDecoder().decode(MigrationBundle.self, from: data) }
        catch { throw BundleError.invalid(error.localizedDescription) }
        guard b.surum == 1 else { throw BundleError.unsupported(b.surum) }
        return b
    }

    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        // Python isoformat: 2026-10-17T09:33:01.123456+00:00 (mikrosaniye)
        let trimmed = s.replacingOccurrences(of: #"\.(\d{3})\d+"#, with: ".$1", options: .regularExpression)
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: trimmed) { return d }
        // Saat dilimi yoksa (Python naive isoformat) UTC kabul et
        if trimmed.range(of: #"(Z|[+-]\d{2}:?\d{2})$"#, options: .regularExpression) == nil {
            return date(trimmed + "+00:00")
        }
        return nil
    }

    /// Paketi mevcut durumla birleştirir. Var olan hesabın sahiplik seçimi korunur.
    public static func apply(_ b: MigrationBundle, to s: inout ProxyState, now: Date = Date()) -> ImportSummary {
        var oauthCount = 0
        for o in b.oauth {
            guard let kind = OAuthProviderKind(rawValue: o.provider) else { continue }
            var meta: [String: String] = [:]
            for (k, v) in o.metadata ?? [:] {
                switch v {
                case .string(let x): meta[k] = x
                case .number, .bool: meta[k] = v.text()
                default: continue
                }
            }
            let existing = s.oauth.first { $0.provider == kind && $0.id == o.id }
            if var keep = existing, keep.refreshOwner == .telefon {
                // Telefon bu hesabı yeniliyor: sunucudaki kopyanın belirteci rotasyonla geçersizdir, telefondakini koru.
                keep.label = o.label ?? meta["email"] ?? keep.label
                keep.metadata.merge(meta) { _, new in new }
                s.oauth.removeAll { $0.provider == kind && $0.id == o.id }
                s.oauth.append(keep)
                oauthCount += 1
                continue
            }
            let acc = OAuthAccount(
                id: o.id, provider: kind,
                label: o.label ?? meta["email"] ?? meta["label"] ?? o.id,
                enabled: o.enabled,
                accessToken: o.access_token, refreshToken: o.refresh_token,
                expiresAt: date(o.expires_at), scopes: o.scopes ?? [], metadata: meta,
                refreshOwner: existing?.refreshOwner ?? (kind.rotatesRefreshToken ? .sunucu : .telefon))
            s.oauth.removeAll { $0.provider == kind && $0.id == o.id }
            s.oauth.append(acc)
            oauthCount += 1
        }
        for a in b.api_anahtarlari {
            let kind: APIProviderKind = switch a.kind { case "gemini-native": .geminiNative; case "anthropic": .anthropic; default: .openAICompatible }
            let models = kind == .anthropic && a.models.isEmpty ? ModelCatalog.claude : a.models
            s.apiProviders.removeAll { $0.name == a.name }
            s.apiProviders.append(APIKeyProvider(
                name: a.name, kind: kind, baseURL: a.base_url, apiKey: a.api_key, models: models,
                aliases: a.aliases ?? [:], filterParams: a.filter ?? [:], enabled: a.enabled ?? true))
        }
        for c in b.istemci_anahtarlari ?? [] {
            s.clientKeys.removeAll { $0.sha256 == c.sha256 }
            s.clientKeys.append(ClientKey(name: c.name, sha256: c.sha256, enabled: c.enabled))
        }
        if let r = b.yonlendirme {
            s.routing = r.compactMap { $0.count == 2 ? RouteRule(pattern: $0[0], target: $0[1]) : nil }
        }
        if let f = b.yedekler { s.fallbacks = f }
        if let d = b.varsayilan_model { s.defaultModel = d }
        if let u = b.uzak {
            s.remote.baseURL = u.base_url
            if let t = u.personal_token { s.remote.personalToken = t }
            if let t = u.sync_token { s.remote.syncToken = t }
            s.remote.enabled = true
        }
        s.importedAt = now
        s.importSource = b.kaynak
        return ImportSummary(oauth: oauthCount, apiProviders: b.api_anahtarlari.count,
                             clientKeys: b.istemci_anahtarlari?.count ?? 0,
                             routes: b.yonlendirme?.count ?? 0, remote: b.uzak != nil)
    }
}
