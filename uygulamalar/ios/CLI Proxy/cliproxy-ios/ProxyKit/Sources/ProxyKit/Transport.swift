import Foundation

public struct UpstreamResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: AsyncThrowingStream<Data, Error>

    public init(status: Int, headers: [String: String], body: AsyncThrowingStream<Data, Error>) {
        self.status = status; self.headers = headers; self.body = body
    }

    public func collect(limit: Int = 64 << 20) async throws -> Data {
        var out = Data()
        for try await chunk in body {
            out.append(chunk)
            if out.count > limit { throw ProxyError.upstream(status: 502, message: "Upstream yanıtı çok büyük") }
        }
        return out
    }

    public func header(_ name: String) -> String? {
        let n = name.lowercased()
        return headers.first { $0.key.lowercased() == n }?.value
    }

    public static func fixed(status: Int, headers: [String: String] = ["Content-Type": "application/json"], data: Data) -> UpstreamResponse {
        UpstreamResponse(status: status, headers: headers, body: AsyncThrowingStream { c in
            if !data.isEmpty { c.yield(data) }
            c.finish()
        })
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> UpstreamResponse
}

/// URLSession tabanlı taşıyıcı. Gövdeyi satır sonlarında boşaltır, böylece SSE
/// olayları gecikmeden iletilir.
public final class URLSessionTransport: HTTPTransport {
    let session: URLSession
    public init(session: URLSession? = nil) {
        if let session { self.session = session } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 600
            cfg.timeoutIntervalForResource = 3600
            cfg.waitsForConnectivity = false
            self.session = URLSession(configuration: cfg)
        }
    }

    public func send(_ request: URLRequest) async throws -> UpstreamResponse {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProxyError.upstream(status: 502, message: "Geçersiz upstream yanıtı")
        }
        var headers: [String: String] = [:]
        for (k, v) in http.allHeaderFields { headers["\(k)"] = "\(v)" }
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            let task = Task {
                var buf = Data()
                buf.reserveCapacity(16384)
                do {
                    for try await byte in bytes {
                        buf.append(byte)
                        if byte == 0x0A || buf.count >= 16384 {
                            continuation.yield(buf)
                            buf = Data()
                            buf.reserveCapacity(16384)
                        }
                    }
                    if !buf.isEmpty { continuation.yield(buf) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return UpstreamResponse(status: http.statusCode, headers: headers, body: stream)
    }
}

// MARK: - SSE

public struct SSEEvent: Sendable, Equatable {
    public var event: String?
    public var data: String
}

public struct SSEParser: Sendable {
    private var buffer = Data()
    public init() {}

    public mutating func feed(_ data: Data) -> [SSEEvent] {
        buffer.append(data)
        var events: [SSEEvent] = []
        while let range = Self.separator(in: buffer) {
            let block = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            if let e = Self.parse(block) { events.append(e) }
        }
        return events
    }

    public mutating func finish() -> [SSEEvent] {
        defer { buffer.removeAll() }
        guard !buffer.isEmpty, let e = Self.parse(buffer) else { return [] }
        return [e]
    }

    static func separator(in d: Data) -> Range<Data.Index>? {
        let a = d.range(of: Data([0x0A, 0x0A]))
        let b = d.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A]))
        switch (a, b) {
        case let (x?, y?): return x.lowerBound < y.lowerBound ? x : y
        case let (x?, nil): return x
        case let (nil, y?): return y
        default: return nil
        }
    }

    static func parse(_ block: Data) -> SSEEvent? {
        let text = String(decoding: block, as: UTF8.self)
        var event: String?
        var lines: [String] = []
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if line.isEmpty || line.hasPrefix(":") { continue }
            if line.hasPrefix("event:") {
                event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                var v = String(line.dropFirst(5))
                if v.hasPrefix(" ") { v.removeFirst() }
                lines.append(v)
            }
        }
        if lines.isEmpty && event == nil { return nil }
        return SSEEvent(event: event, data: lines.joined(separator: "\n"))
    }
}

public func sseData(_ json: JSON, event: String? = nil) -> Data {
    var s = ""
    if let event { s += "event: \(event)\n" }
    s += "data: \(json.text())\n\n"
    return Data(s.utf8)
}

// MARK: - Hatalar

public enum ProxyError: Error, LocalizedError, Sendable {
    case badRequest(String)
    case unauthorized(String)
    case notFound(String)
    case upstream(status: Int, message: String)
    case noAccount(String)
    /// Sunucuya aktarma başarısız (yeniden sunucuya düşmenin anlamı yok)
    case remoteFailed(String)

    public var status: Int {
        switch self {
        case .badRequest: 400
        case .unauthorized: 401
        case .notFound: 404
        case .upstream(let s, _): s
        case .noAccount: 503
        case .remoteFailed: 502
        }
    }
    public var errorDescription: String? {
        switch self {
        case .badRequest(let m), .unauthorized(let m), .notFound(let m), .noAccount(let m), .remoteFailed(let m): m
        case .upstream(_, let m): m
        }
    }
    /// Sunucu yedeğine düşmeyi haklı kılan hata mı?
    public var isFallbackWorthy: Bool {
        switch self {
        case .noAccount: true
        case .upstream(let s, _): s == 401 || s == 403 || s == 408 || s == 429 || s >= 500
        default: false
        }
    }
}
