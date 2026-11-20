import Foundation

public enum Route: Sendable, Equatable, CustomStringConvertible {
    case claude
    case codex
    case api(String)
    case antigravity(model: String, thinking: String?)
    case remote

    public var description: String {
        switch self {
        case .claude: "Claude (telefon)"
        case .codex: "Codex (telefon)"
        case .api(let n): "\(n) (telefon)"
        case .antigravity: "Antigravity (telefon)"
        case .remote: "Sunucu"
        }
    }
}

public enum ModelCatalog {
    public static let claude = ["claude-sonnet-5-5", "claude-opus-5-5", "claude-fable-5-1", "claude-opus-5", "claude-sonnet-5",
                                "claude-fable-5", "claude-opus-4-8", "claude-opus-4-7", "claude-sonnet-4-6", "claude-opus-4-6",
                                "claude-opus-4-5", "claude-sonnet-4-5", "claude-haiku-4-5"]
    public static let codex = ["gpt-6.1-sol", "gpt-6-astra", "gpt-6-sol", "gpt-6-luna", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5"]
    /// Telefonda yürütücüsü olmayan, her zaman sunucuya giden modeller (alt süreç/yerel model/görsel aracı gerektirir).
    public static let remoteOnly = ["antigravity-*", "gpt-image-*", "qwen*", "*-live", "*-image", "*-image-*"]
}

/// fnmatch benzeri basit desen eşleştirme (* ve ?)
public func globMatch(_ pattern: String, _ s: String) -> Bool {
    let p = Array(pattern), t = Array(s)
    var pi = 0, ti = 0, star = -1, mark = 0
    while ti < t.count {
        if pi < p.count && (p[pi] == "?" || p[pi] == t[ti]) { pi += 1; ti += 1 }
        else if pi < p.count && p[pi] == "*" { star = pi; mark = ti; pi += 1 }
        else if star >= 0 { pi = star + 1; mark += 1; ti = mark }
        else { return false }
    }
    while pi < p.count && p[pi] == "*" { pi += 1 }
    return pi == p.count
}

public struct ModelRouter: Sendable {
    public let state: ProxyState
    public init(state: ProxyState) { self.state = state }

    func target(_ name: String) -> Route {
        switch name {
        case "claude": return .claude
        case "codex": return .codex
        default:
            if state.apiProviders.contains(where: { $0.name == name && $0.enabled }) { return .api(name) }
            return .remote
        }
    }

    /// Modelin gideceği yol. Önce tam eşleşen kurallar, sonra desenler (sunucudaki sırayla).
    var hasAntigravity: Bool { state.oauth.contains { $0.provider == .antigravity && $0.enabled } }
    var hasCodex: Bool { state.oauth.contains { $0.provider == .codex && $0.enabled } }
    /// Claude modelleri telefonda karşılanabilir mi: OAuth hesabı ya da Claude API anahtarı
    var hasClaude: Bool {
        state.oauth.contains { $0.provider == .claude && $0.enabled } || !claudeAPIProviders.isEmpty
    }
    /// Claude API anahtarlı sağlayıcılar (OAuth başarısızsa ya da yoksa sırayla denenir)
    public var claudeAPIProviders: [APIKeyProvider] { state.apiProviders.filter { $0.enabled && $0.kind == .anthropic } }

    public func resolve(_ model: String) -> Route {
        // Antigravity hesabı telefondaysa onun modelleri (sunucuda gemini-pro-account köprüsüne gidenler dahil) doğrudan çağrılır.
        if hasAntigravity, let t = Antigravity.target(model) { return .antigravity(model: t.model, thinking: t.thinking) }
        if ModelCatalog.remoteOnly.contains(where: { globMatch($0, model) }) { return .remote }
        if let r = state.routing.first(where: { $0.pattern == model }) { return target(r.target) }
        if let p = state.apiProviders.first(where: { $0.enabled && $0.kind != .anthropic && ($0.models.contains(model) || $0.aliases[model] != nil) }) {
            return .api(p.name)
        }
        if let r = state.routing.first(where: { $0.pattern.contains("*") || $0.pattern.contains("?") ? globMatch($0.pattern, model) : false }) {
            return target(r.target)
        }
        if model.hasPrefix("claude-") { return .claude }
        if model.hasPrefix("gpt-") || model.hasPrefix("o1") || model.hasPrefix("o3") || model.hasPrefix("codex") { return .codex }
        return .remote
    }

    public func provider(_ name: String) -> APIKeyProvider? { state.apiProviders.first { $0.name == name } }

    /// Telefonda doğrudan sunulabilen modeller (hesabı/anahtarı olanlar)
    public func localModels() -> [(id: String, owner: String)] {
        var out: [(String, String)] = []
        var seen = Set<String>()
        func add(_ id: String, _ owner: String) {
            guard !seen.contains(id), resolve(id) != .remote else { return }
            seen.insert(id); out.append((id, owner))
        }
        if hasClaude { ModelCatalog.claude.forEach { add($0, "anthropic") } }
        if state.oauth.contains(where: { $0.provider == .codex && $0.enabled }) { ModelCatalog.codex.forEach { add($0, "openai") } }
        if hasAntigravity { Antigravity.clientModels.forEach { add($0, "antigravity") } }
        for p in state.apiProviders where p.enabled {
            if p.kind == .anthropic { p.models.forEach { add($0, "anthropic") }; continue }
            p.models.forEach { add($0, p.name) }
            p.aliases.keys.sorted().forEach { add($0, p.name) }
        }
        return out
    }
}
