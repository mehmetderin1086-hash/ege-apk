import Foundation

public struct UsageRecord: Codable, Sendable, Identifiable, Equatable {
    public var id = UUID()
    public var date = Date()
    public var path: String
    public var model: String
    public var route: String
    public var status: Int
    public var millis: Int
    public var inputTokens: Int
    public var outputTokens: Int
    public var error: String?
    public var fellBack = false
}

public actor UsageLog {
    public private(set) var records: [UsageRecord] = []
    let file: URL?
    let limit: Int
    private var observers: [UUID: @Sendable ([UsageRecord]) -> Void] = [:]

    public init(file: URL? = nil, limit: Int = 500) {
        self.file = file
        self.limit = limit
        if let file, let d = try? Data(contentsOf: file) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            records = (try? dec.decode([UsageRecord].self, from: d)) ?? []
        }
    }

    public func add(_ r: UsageRecord) {
        records.insert(r, at: 0)
        if records.count > limit { records.removeLast(records.count - limit) }
        if let file {
            let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
            try? enc.encode(records).write(to: file, options: .atomic)
        }
        for o in observers.values { o(records) }
    }

    @discardableResult
    public func observe(_ fn: @escaping @Sendable ([UsageRecord]) -> Void) -> UUID {
        let id = UUID(); observers[id] = fn; fn(records); return id
    }

    public func clear() {
        records = []
        if let file { try? FileManager.default.removeItem(at: file) }
        for o in observers.values { o(records) }
    }
}
