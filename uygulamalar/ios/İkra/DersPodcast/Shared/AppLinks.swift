import Foundation

/// kocum:// bağlantılarının tek üretici ve ayrıştırıcısı (uygulama ve widget eklentisi).
nonisolated enum AppLink: Hashable, Sendable {
    case episode(UUID, time: Double?, play: Bool)
    case generation(UUID)
    case route(String)

    static let scheme = "kocum"

    var url: URL {
        var c = URLComponents()
        c.scheme = Self.scheme
        switch self {
        case let .episode(id, time, play):
            c.host = "episode"
            c.path = "/" + id.uuidString
            var items: [URLQueryItem] = []
            if let time { items.append(URLQueryItem(name: "t", value: String(Int(max(0, time).rounded(.down))))) }
            if play { items.append(URLQueryItem(name: "play", value: "1")) }
            c.queryItems = items.isEmpty ? nil : items
        case let .generation(id):
            c.host = "generation"
            c.path = "/" + id.uuidString
        case let .route(name):
            c.host = "route"
            c.path = "/" + name
        }
        return c.url ?? URL(string: "kocum://route/library")!
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host() else { return nil }
        let value = url.pathComponents.dropFirst().first ?? ""
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        switch host {
        case "episode":
            guard let id = UUID(uuidString: value) else { return nil }
            let time = query.first { $0.name == "t" }?.value.flatMap(Double.init)
            self = .episode(id, time: time, play: query.contains { $0.name == "play" && $0.value == "1" })
        case "generation":
            guard let id = UUID(uuidString: value) else { return nil }
            self = .generation(id)
        case "route":
            guard !value.isEmpty else { return nil }
            self = .route(value)
        default:
            return nil
        }
    }
}
