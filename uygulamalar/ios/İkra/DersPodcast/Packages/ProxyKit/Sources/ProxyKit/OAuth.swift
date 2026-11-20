import Foundation
import CryptoKit
import Security

/// Resmî CLI'lardan türetilmiş OAuth sabitleri (sunucudaki vekille aynı).
public enum OAuthConstants {
    public enum Claude {
        public static let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
        public static let authorize = "https://claude.com/cai/oauth/authorize"
        public static let token = "https://platform.claude.com/v1/oauth/token"
        public static let redirect = "https://platform.claude.com/oauth/code/callback"
        public static let scopes = ["org:create_api_key", "user:profile", "user:inference",
                                    "user:sessions:claude_code", "user:mcp_servers", "user:file_upload"]
        public static var refreshScopes: [String] { scopes.filter { $0 != "org:create_api_key" } }
    }
    public enum Codex {
        public static let clientId = "app_EMoamEEZ73f0CkXaXp7hrann"
        public static let authorize = "https://auth.openai.com/oauth/authorize"
        public static let token = "https://auth.openai.com/oauth/token"
        public static let port: UInt16 = 1455
        public static let redirect = "http://localhost:1455/auth/callback"
        public static let scopes = ["openid", "profile", "email", "offline_access",
                                    "api.connectors.read", "api.connectors.invoke"]
        public static let originator = "codex_cli_rs"
    }
    /// Antigravity (Google) — sunucudaki `agy` CLI'nin OAuth istemcisi ve Code Assist arka ucu (17 Eki 2026'da yoklandı).
    public enum Antigravity {
        public static let clientId = ProcessInfo.processInfo.environment["ANTIGRAVITY_GOOGLE_CLIENT_ID"] ?? ""
        public static let clientSecret = ProcessInfo.processInfo.environment["ANTIGRAVITY_GOOGLE_CLIENT_SECRET"] ?? ""
        public static let token = "https://oauth2.googleapis.com/token"
        public static let base = "https://daily-cloudcode-pa.googleapis.com/v1internal"
        public static let defaultProject = "aicode-consumers"
        public static let userAgent = "antigravity/1.0.0 darwin/arm64"
    }
    public enum Gemini {
        public static let clientId = ProcessInfo.processInfo.environment["GEMINI_GOOGLE_CLIENT_ID"] ?? ""
        public static let clientSecret = ProcessInfo.processInfo.environment["GEMINI_GOOGLE_CLIENT_SECRET"] ?? ""
        public static let token = "https://oauth2.googleapis.com/token"
    }
}

public struct PKCE: Sendable {
    public let verifier: String
    public let challenge: String
    public let state: String

    public init() {
        verifier = PKCE.random(32)
        challenge = PKCE.b64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        state = PKCE.random(32)
    }
    static func random(_ n: Int) -> String {
        var b = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &b)
        return b64url(Data(b))
    }
    static func b64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

public enum JWT {
    public static func claims(_ token: String?) -> [String: JSON] {
        guard let token, case let parts = token.split(separator: "."), parts.count >= 2 else { return [:] }
        var s = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let d = Data(base64Encoded: s), let j = try? JSON.parse(d) else { return [:] }
        return j.object ?? [:]
    }
}

struct TokenResult: Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var scopes: [String]?
    var idToken: String?
    var accountId: String? = nil
    var email: String? = nil
}

/// OAuth giriş ve yenileme istekleri.
public struct OAuthClient: Sendable {
    let transport: HTTPTransport
    public init(transport: HTTPTransport) { self.transport = transport }

    // MARK: giriş adresleri

    public static func claudeAuthorizeURL(_ p: PKCE) -> URL {
        var c = URLComponents(string: OAuthConstants.Claude.authorize)!
        c.queryItems = [
            .init(name: "code", value: "true"),
            .init(name: "client_id", value: OAuthConstants.Claude.clientId),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: OAuthConstants.Claude.redirect),
            .init(name: "scope", value: OAuthConstants.Claude.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: p.challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: p.state),
        ]
        return c.url!
    }

    public static func codexAuthorizeURL(_ p: PKCE) -> URL {
        var c = URLComponents(string: OAuthConstants.Codex.authorize)!
        c.queryItems = [
            .init(name: "client_id", value: OAuthConstants.Codex.clientId),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: OAuthConstants.Codex.redirect),
            .init(name: "scope", value: OAuthConstants.Codex.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: p.challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: p.state),
            .init(name: "id_token_add_organizations", value: "true"),
            .init(name: "codex_cli_simplified_flow", value: "true"),
            .init(name: "originator", value: OAuthConstants.Codex.originator),
        ]
        return c.url!
    }

    /// Claude sayfasının verdiği `kod#state` değerini ya da tam dönüş adresini çözer.
    public static func parseClaudeCode(_ raw: String) -> (code: String, state: String?) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let c = URLComponents(string: t), let items = c.queryItems,
           let code = items.first(where: { $0.name == "code" })?.value {
            return (code, items.first(where: { $0.name == "state" })?.value ?? c.fragment)
        }
        let parts = t.split(separator: "#", maxSplits: 1).map(String.init)
        return (parts.first ?? t, parts.count > 1 ? parts[1] : nil)
    }

    /// Codex dönüş adresinden kodu çıkarır (state doğrulanır).
    public static func parseCodexCallback(_ raw: String, expectedState: String) throws -> String {
        guard let c = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let items = c.queryItems else { throw ProxyError.badRequest("Dönüş adresi okunamadı") }
        if let e = items.first(where: { $0.name == "error" })?.value {
            throw ProxyError.badRequest("OpenAI girişi reddetti: \(e)")
        }
        guard items.first(where: { $0.name == "state" })?.value == expectedState else {
            throw ProxyError.badRequest("Güvenlik durumu (state) tutmuyor; girişi yeniden başlatın")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw ProxyError.badRequest("Dönüş adresinde kod yok")
        }
        return code
    }

    // MARK: kod takası

    public func exchangeClaude(code: String, state: String?, pkce: PKCE) async throws -> OAuthAccount {
        let body: JSON = [
            "grant_type": "authorization_code", "client_id": .string(OAuthConstants.Claude.clientId),
            "code": .string(code), "state": .string(state ?? pkce.state),
            "redirect_uri": .string(OAuthConstants.Claude.redirect), "code_verifier": .string(pkce.verifier),
        ]
        let t = try await post(OAuthConstants.Claude.token, json: body, fallbackScopes: OAuthConstants.Claude.scopes)
        // Kimlik hesabın kendisinden: ikinci bir Claude girişi ilk hesabı (ve onun döndürülmüş belirtecini) ezmesin.
        var meta: [String: String] = [:]
        if let e = t.email { meta["email"] = e }
        return OAuthAccount(id: t.accountId ?? "claude-" + UUID().uuidString.prefix(8).lowercased(), provider: .claude,
                            label: t.email ?? "Claude (telefon girişi)",
                            accessToken: t.accessToken, refreshToken: t.refreshToken, expiresAt: t.expiresAt,
                            scopes: t.scopes ?? OAuthConstants.Claude.scopes, metadata: meta, refreshOwner: .telefon)
    }

    public func exchangeCodex(code: String, pkce: PKCE) async throws -> OAuthAccount {
        let t = try await post(OAuthConstants.Codex.token, form: [
            "grant_type": "authorization_code", "client_id": OAuthConstants.Codex.clientId,
            "code": code, "code_verifier": pkce.verifier, "redirect_uri": OAuthConstants.Codex.redirect,
        ], fallbackScopes: OAuthConstants.Codex.scopes)
        let meta = OAuthClient.codexMetadata(idToken: t.idToken, accessToken: t.accessToken)
        let id = meta["account_id"] ?? meta["email"] ?? "codex-iphone"
        return OAuthAccount(id: id, provider: .codex, label: meta["email"] ?? "ChatGPT hesabı",
                            accessToken: t.accessToken, refreshToken: t.refreshToken, expiresAt: t.expiresAt,
                            scopes: OAuthConstants.Codex.scopes, metadata: meta, refreshOwner: .telefon)
    }

    public static func codexMetadata(idToken: String?, accessToken: String?) -> [String: String] {
        var meta: [String: String] = [:]
        let idc = JWT.claims(idToken)
        let ac = JWT.claims(accessToken)
        let auth = idc["https://api.openai.com/auth"]?.object ?? ac["https://api.openai.com/auth"]?.object ?? [:]
        if let a = auth["chatgpt_account_id"]?.string { meta["account_id"] = a }
        if let p = auth["chatgpt_plan_type"]?.string { meta["plan"] = p }
        if let e = idc["email"]?.string ?? ac["https://api.openai.com/profile"]?["email"]?.string { meta["email"] = e }
        return meta
    }

    // MARK: yenileme (yalnız telefon sahibi olan hesaplar)

    func refresh(_ a: OAuthAccount) async throws -> TokenResult {
        guard let rt = a.refreshToken, !rt.isEmpty else {
            throw ProxyError.upstream(status: 401, message: "\(a.provider.title): yenileme belirteci yok, yeniden giriş gerekli")
        }
        switch a.provider {
        case .claude:
            let scopes = a.scopes.isEmpty ? OAuthConstants.Claude.refreshScopes : a.scopes
            return try await post(OAuthConstants.Claude.token, json: [
                "grant_type": "refresh_token", "client_id": .string(OAuthConstants.Claude.clientId),
                "refresh_token": .string(rt), "scope": .string(scopes.joined(separator: " ")),
            ], fallbackScopes: scopes, keepRefresh: rt)
        case .codex:
            return try await post(OAuthConstants.Codex.token, form: [
                "grant_type": "refresh_token", "client_id": OAuthConstants.Codex.clientId, "refresh_token": rt,
            ], fallbackScopes: a.scopes, keepRefresh: rt)
        case .antigravity:
            return try await post(OAuthConstants.Antigravity.token, form: [
                "grant_type": "refresh_token", "client_id": OAuthConstants.Antigravity.clientId,
                "client_secret": OAuthConstants.Antigravity.clientSecret, "refresh_token": rt,
            ], fallbackScopes: a.scopes, keepRefresh: rt)
        case .gemini:
            return try await post(OAuthConstants.Gemini.token, form: [
                "grant_type": "refresh_token", "client_id": OAuthConstants.Gemini.clientId,
                "client_secret": OAuthConstants.Gemini.clientSecret, "refresh_token": rt,
            ], fallbackScopes: a.scopes, keepRefresh: rt)
        }
    }

    // MARK: yardımcılar

    private func post(_ url: String, json: JSON? = nil, form: [String: String]? = nil,
                      fallbackScopes: [String], keepRefresh: String? = nil) async throws -> TokenResult {
        var r = URLRequest(url: URL(string: url)!)
        r.httpMethod = "POST"
        r.timeoutInterval = 30
        if let json {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = json.data()
        } else if let form {
            r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var c = URLComponents()
            c.queryItems = form.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            r.httpBody = Data((c.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        }
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        let resp = try await transport.send(r)
        let data = try await resp.collect(limit: 1 << 20)
        let body = (try? JSON.parse(data)) ?? .null
        guard (200..<300).contains(resp.status), let at = body["access_token"]?.string else {
            let err = body["error_description"]?.string ?? body["error"]?.string
                ?? body["error"]?["message"]?.string ?? "HTTP \(resp.status)"
            throw ProxyError.upstream(status: resp.status == 400 ? 401 : resp.status,
                                      message: "OAuth belirteç hatası: \(err)")
        }
        var scopes: [String]? = nil
        if let s = body["scope"]?.string { scopes = s.split(separator: " ").map(String.init) }
        else if let a = body["scope"]?.array { scopes = a.compactMap(\.string) }
        let exp = body["expires_in"]?.double.map { Date().addingTimeInterval($0) }
        return TokenResult(accessToken: at, refreshToken: body["refresh_token"]?.string ?? keepRefresh,
                           expiresAt: exp, scopes: scopes ?? fallbackScopes, idToken: body["id_token"]?.string,
                           accountId: body["account"]?["uuid"]?.string, email: body["account"]?["email_address"]?.string)
    }
}
