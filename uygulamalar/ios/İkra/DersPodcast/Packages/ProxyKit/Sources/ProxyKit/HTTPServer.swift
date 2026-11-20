import Foundation
import Network

// MARK: - NWConnection async yardımcıları

extension NWConnection {
    func receiveChunk(max: Int = 65536) async throws -> Data? {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data?, Error>) in
            receive(minimumIncompleteLength: 1, maximumLength: max) { data, _, complete, error in
                if let error { cont.resume(throwing: error) }
                else if let data, !data.isEmpty { cont.resume(returning: data) }
                else if complete { cont.resume(returning: nil) }
                else { cont.resume(returning: Data()) }
            }
        }
    }

    func sendData(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            send(content: data, completion: .contentProcessed { e in
                if let e { cont.resume(throwing: e) } else { cont.resume() }
            })
        }
    }
}

// MARK: - Basit HTTP/1.1 istek okuyucu

struct HTTPRequestReader {
    var buffer = Data()
    static let maxHeader = 64 * 1024
    static let maxBody = 96 * 1024 * 1024

    struct Head { var method: String; var target: String; var headers: [String: String] }

    static func parseHead(_ d: Data) throws -> Head {
        let text = String(decoding: d, as: UTF8.self)
        var lines = text.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { throw ProxyError.badRequest("Boş istek") }
        let reqLine = lines.removeFirst().split(separator: " ")
        guard reqLine.count >= 2 else { throw ProxyError.badRequest("Geçersiz istek satırı") }
        var headers: [String: String] = [:]
        for l in lines where !l.isEmpty {
            guard let c = l.firstIndex(of: ":") else { continue }
            headers[l[..<c].trimmingCharacters(in: .whitespaces).lowercased()] = l[l.index(after: c)...].trimmingCharacters(in: .whitespaces)
        }
        return Head(method: String(reqLine[0]), target: String(reqLine[1]), headers: headers)
    }

    /// Bağlantıdan tek bir isteği okur. Bağlantı istek gelmeden kapanırsa nil döner.
    static func read(_ c: NWConnection) async throws -> ProxyRequest? {
        var buf = Data()
        let sep = Data("\r\n\r\n".utf8)
        var headEnd: Range<Data.Index>?
        while headEnd == nil {
            guard let chunk = try await c.receiveChunk() else { return nil }
            buf.append(chunk)
            headEnd = buf.range(of: sep)
            if headEnd == nil && buf.count > maxHeader { throw ProxyError.badRequest("Başlık çok büyük") }
        }
        let head = try parseHead(buf.subdata(in: buf.startIndex..<headEnd!.lowerBound))
        var body = buf.subdata(in: headEnd!.upperBound..<buf.endIndex)
        if head.headers["expect"]?.lowercased() == "100-continue" {
            try await c.sendData(Data("HTTP/1.1 100 Continue\r\n\r\n".utf8))
        }
        if head.headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            body = try await readChunked(c, initial: body)
        } else {
            let raw = head.headers["content-length"]?.trimmingCharacters(in: .whitespaces) ?? "0"
            guard let len = Int(raw), len >= 0 else { throw ProxyError.badRequest("Geçersiz Content-Length") }
            guard len <= maxBody else { throw ProxyError.badRequest("Gövde çok büyük") }
            while body.count < len {
                guard let chunk = try await c.receiveChunk(max: 1 << 20) else { break }
                body.append(chunk)
            }
            if body.count > len { body = body.prefix(len) }
        }
        var path = head.target
        var query: [String: String] = [:]
        if let comps = URLComponents(string: "http://x" + head.target) {
            path = comps.percentEncodedPath.isEmpty ? "/" : (comps.path.isEmpty ? "/" : comps.path)
            for i in comps.queryItems ?? [] { query[i.name] = i.value ?? "" }
        }
        // Gemini yolları ":" içerir (models/x:generateContent); path çözümü bunu korur.
        return ProxyRequest(method: head.method, path: path, query: query, headers: head.headers, body: body)
    }

    static func readChunked(_ c: NWConnection, initial: Data) async throws -> Data {
        var raw = initial
        var out = Data()
        var idx = raw.startIndex
        func need(_ n: Int) async throws {
            while raw.endIndex - idx < n {
                guard let chunk = try await c.receiveChunk(max: 1 << 20) else { throw ProxyError.badRequest("Parçalı gövde yarım kaldı") }
                raw.append(chunk)
            }
        }
        while true {
            var lineEnd: Range<Data.Index>?
            while lineEnd == nil {
                lineEnd = raw.range(of: Data("\r\n".utf8), in: idx..<raw.endIndex)
                if lineEnd == nil {
                    guard let chunk = try await c.receiveChunk(max: 1 << 20) else { throw ProxyError.badRequest("Parçalı gövde yarım kaldı") }
                    raw.append(chunk)
                }
            }
            let sizeText = String(decoding: raw[idx..<lineEnd!.lowerBound], as: UTF8.self).split(separator: ";").first ?? "0"
            guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16), size >= 0,
                  size <= maxBody - out.count else { throw ProxyError.badRequest("Parça boyutu geçersiz ya da çok büyük") }
            idx = lineEnd!.upperBound
            if size == 0 { break }
            try await need(size + 2)
            out.append(raw[idx..<(idx + size)])
            idx += size + 2
            guard out.count <= maxBody else { throw ProxyError.badRequest("Gövde çok büyük") }
        }
        return out
    }
}

func statusText(_ s: Int) -> String {
    switch s {
    case 200: "OK"; case 201: "Created"; case 204: "No Content"; case 400: "Bad Request"; case 401: "Unauthorized"
    case 403: "Forbidden"; case 404: "Not Found"; case 429: "Too Many Requests"; case 500: "Internal Server Error"
    case 502: "Bad Gateway"; case 503: "Service Unavailable"; case 529: "Overloaded"; default: "Status"
    }
}

// MARK: - Yerel vekil sunucusu

public final class LocalHTTPServer: @unchecked Sendable {
    public enum State: Sendable, Equatable { case stopped, starting, running(port: UInt16), failed(String) }

    let engine: ProxyEngine
    let queue = DispatchQueue(label: "cliproxy.http")
    private let lock = NSLock()
    private var listener: NWListener?
    private var _state: State = .stopped
    private var activeConnections = 0
    public var onStateChange: (@Sendable (State) -> Void)?

    public init(engine: ProxyEngine) { self.engine = engine }

    public var state: State { lock.withLock { _state } }
    public var connections: Int { lock.withLock { activeConnections } }

    private func set(_ s: State) {
        lock.withLock { _state = s }
        onStateChange?(s)
    }

    /// `lan == false` iken yalnız bu cihazdan (127.0.0.1) erişilebilir.
    public func start(port: UInt16, lan: Bool) throws {
        stop()
        set(.starting)
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let p = NWEndpoint.Port(rawValue: port) else { throw ProxyError.badRequest("Geçersiz port") }
        let l: NWListener
        if lan {
            l = try NWListener(using: params, on: p)
        } else {
            // Yalnız bu cihaz: açıkça 127.0.0.1'e bağlan (arayüz kısıtı soketi yine *:port açıyordu).
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: p)
            l = try NWListener(using: params)
        }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.stateUpdateHandler = { [weak self] st in
            switch st {
            case .ready: self?.set(.running(port: l.port?.rawValue ?? port))
            case .failed(let e): self?.set(.failed(e.localizedDescription)); l.cancel()
            default: break
            }
        }
        lock.withLock { listener = l }
        l.start(queue: queue)
    }

    public func stop() {
        let l = lock.withLock { () -> NWListener? in let x = listener; listener = nil; return x }
        l?.cancel()
        set(.stopped)
    }

    private func accept(_ c: NWConnection) {
        lock.withLock { activeConnections += 1 }
        c.start(queue: queue)
        Task { [engine, weak self] in
            await LocalHTTPServer.serve(c, engine: engine)
            c.cancel()
            self?.lock.withLock { self?.activeConnections -= 1 }
        }
    }

    static func serve(_ c: NWConnection, engine: ProxyEngine) async {
        let resp: ProxyResponse
        do {
            guard let req = try await HTTPRequestReader.read(c) else { return }
            resp = await engine.handle(req)
        } catch let e as ProxyError {
            resp = .error(e)
        } catch {
            return
        }
        await write(resp, to: c)
    }

    static func write(_ resp: ProxyResponse, to c: NWConnection) async {
        var head = "HTTP/1.1 \(resp.status) \(statusText(resp.status))\r\n"
        var headers = resp.headers
        headers["Connection"] = "close"
        headers["Server"] = "CLIProxy-iPhone"
        headers["Access-Control-Allow-Origin"] = headers["Access-Control-Allow-Origin"] ?? "*"
        do {
            if resp.streaming {
                headers["Transfer-Encoding"] = "chunked"
                headers["X-Accel-Buffering"] = "no"
                for (k, v) in headers { head += "\(k): \(v)\r\n" }
                try await c.sendData(Data((head + "\r\n").utf8))
                for try await chunk in resp.body where !chunk.isEmpty {
                    var frame = Data(String(chunk.count, radix: 16).utf8)
                    frame.append(contentsOf: [0x0D, 0x0A]); frame.append(chunk); frame.append(contentsOf: [0x0D, 0x0A])
                    try await c.sendData(frame)
                }
                try await c.sendData(Data("0\r\n\r\n".utf8))
            } else {
                var body = Data()
                for try await chunk in resp.body { body.append(chunk) }
                headers["Content-Length"] = "\(body.count)"
                for (k, v) in headers { head += "\(k): \(v)\r\n" }
                var out = Data((head + "\r\n").utf8)
                out.append(body)
                try await c.sendData(out)
            }
        } catch {
            // istemci koptu; akış sonlandırılınca upstream görevi de iptal olur
        }
    }
}

// MARK: - Codex OAuth dönüş dinleyicisi (localhost:1455)

/// Codex girişi `http://localhost:1455/auth/callback` adresine döner. Uygulama
/// ön plandayken bu dinleyici adresi yakalar ve tarayıcıya "tamam" sayfası gösterir.
public final class OAuthCallbackListener: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "cliproxy.oauth-callback")
    private let lock = NSLock()
    private var delivered = false

    public init() {}

    public func start(port: UInt16 = OAuthConstants.Codex.port, path: String = "/auth/callback",
                      onCallback: @escaping @Sendable (URL) -> Void) throws {
        stop()
        delivered = false
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] c in
            c.start(queue: self?.queue ?? .global())
            Task {
                guard let req = try? await HTTPRequestReader.read(c) else { c.cancel(); return }
                let html: String
                if req.path == path, req.query["code"] != nil || req.query["error"] != nil {
                    var comps = URLComponents(string: "http://localhost:\(port)\(path)")!
                    comps.queryItems = req.query.map { URLQueryItem(name: $0.key, value: $0.value) }
                    let first = self?.lock.withLock { () -> Bool in let f = !(self?.delivered ?? true); self?.delivered = true; return f } ?? false
                    if first, let u = comps.url { onCallback(u) }
                    html = "<html><head><meta name=viewport content='width=device-width'><meta charset=utf-8></head><body style='font-family:-apple-system;text-align:center;padding-top:30vh'><h2>Giriş tamamlandı</h2><p>CLI Proxy uygulamasına dönebilirsiniz.</p></body></html>"
                } else {
                    html = "<html><body>Bekleniyor…</body></html>"
                }
                let body = Data(html.utf8)
                var out = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
                out.append(body)
                try? await c.sendData(out)
                c.cancel()
            }
        }
        lock.withLock { listener = l }
        l.start(queue: queue)
    }

    public func stop() {
        let l = lock.withLock { () -> NWListener? in let x = listener; listener = nil; return x }
        l?.cancel()
    }
}

// MARK: - Ağ adresi

public enum NetworkInfo {
    /// Wi-Fi (en0) IPv4 adresi — LAN erişiminde gösterilir.
    public static func wifiAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var result: String?
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name == "en0" || (result == nil && name.hasPrefix("en")) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result = String(decoding: host.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                if name == "en0" { break }
            }
        }
        return result
    }
}
