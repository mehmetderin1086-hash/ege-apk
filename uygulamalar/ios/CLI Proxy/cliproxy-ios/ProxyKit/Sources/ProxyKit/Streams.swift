import Foundation

// MARK: - Upstream akış çözücüleri (SSE → CEvent)

public protocol StreamDecoder: Sendable {
    mutating func decode(_ e: SSEEvent) throws -> [CEvent]
    /// akış finish olmadan biterse
    mutating func end() -> [CEvent]
}

func upstreamError(_ j: JSON?, fallback: String, status: Int = 502) -> ProxyError {
    let e = j?["error"]
    let msg = e?["message"]?.string ?? e?.string ?? j?["message"]?.string ?? j?["response"]?["error"]?["message"]?.string ?? fallback
    let type = e?["type"]?.string ?? e?["code"]?.string ?? ""
    var s = status
    if type.contains("overloaded") { s = 529 } else if type.contains("rate_limit") || msg.lowercased().contains("usage limit") { s = 429 }
    return .upstream(status: s, message: msg)
}

public struct AnthropicDecoder: StreamDecoder {
    var usage = CUsage()
    var blockToTool: [Int: Int] = [:]
    var toolCount = 0
    var stopReason: String?
    var finished = false
    public init() {}

    public mutating func decode(_ e: SSEEvent) throws -> [CEvent] {
        guard let j = try? JSON.parse(Data(e.data.utf8)) else { return [] }
        switch j["type"]?.string ?? e.event {
        case "message_start":
            let u = j["message"]?["usage"]
            usage.input = (u?["input_tokens"]?.int ?? 0) + (u?["cache_read_input_tokens"]?.int ?? 0) + (u?["cache_creation_input_tokens"]?.int ?? 0)
            usage.cacheRead = u?["cache_read_input_tokens"]?.int ?? 0
            usage.cacheWrite = u?["cache_creation_input_tokens"]?.int ?? 0
            usage.output = u?["output_tokens"]?.int ?? 0
        case "content_block_start":
            let b = j["content_block"]
            if b?["type"]?.string == "tool_use" {
                let idx = toolCount; toolCount += 1
                blockToTool[j["index"]?.int ?? 0] = idx
                return [.toolStart(index: idx, id: b?["id"]?.string ?? "", name: b?["name"]?.string ?? "")]
            }
        case "content_block_delta":
            let d = j["delta"]
            switch d?["type"]?.string {
            case "text_delta": if let t = d?["text"]?.string, !t.isEmpty { return [.text(t)] }
            case "thinking_delta": if let t = d?["thinking"]?.string, !t.isEmpty { return [.thinking(t)] }
            case "input_json_delta":
                if let idx = blockToTool[j["index"]?.int ?? -1], let p = d?["partial_json"]?.string, !p.isEmpty { return [.toolArgs(index: idx, p)] }
            default: break
            }
        case "message_delta":
            if let s = j["delta"]?["stop_reason"]?.string { stopReason = s }
            if let o = j["usage"]?["output_tokens"]?.int { usage.output = o }
            if let i = j["usage"]?["input_tokens"]?.int, i > 0, usage.input == 0 { usage.input = i }
        case "message_stop":
            finished = true
            let map = ["end_turn": "stop", "max_tokens": "length", "stop_sequence": "stop", "tool_use": "tool_calls", "pause_turn": "stop", "refusal": "stop"]
            return [.finish(reason: map[stopReason ?? "end_turn"] ?? "stop", usage: usage)]
        case "error":
            throw upstreamError(j, fallback: "Claude akış hatası")
        default: break
        }
        return []
    }

    public mutating func end() -> [CEvent] {
        finished ? [] : [.finish(reason: toolCount > 0 ? "tool_calls" : "stop", usage: usage)]
    }
}

public struct ResponsesDecoder: StreamDecoder {
    var tools: [String: Int] = [:]
    var toolCount = 0
    var finished = false
    var sawText = false
    public init() {}

    public mutating func decode(_ e: SSEEvent) throws -> [CEvent] {
        if e.data == "[DONE]" { return [] }
        guard let j = try? JSON.parse(Data(e.data.utf8)) else { return [] }
        switch j["type"]?.string ?? e.event ?? "" {
        case "response.output_text.delta":
            if let t = j["delta"]?.string, !t.isEmpty { sawText = true; return [.text(t)] }
        case "response.reasoning_summary_text.delta", "response.reasoning_text.delta":
            if let t = j["delta"]?.string, !t.isEmpty { return [.thinking(t)] }
        case "response.output_item.added":
            let item = j["item"]
            if item?["type"]?.string == "function_call" {
                let callId = item?["call_id"]?.string ?? item?["id"]?.string ?? ""
                let idx = toolCount; toolCount += 1
                tools[callId] = idx
                if let iid = item?["id"]?.string { tools[iid] = idx }
                return [.toolStart(index: idx, id: callId, name: item?["name"]?.string ?? "")]
            }
        case "response.function_call_arguments.delta":
            let key = j["item_id"]?.string ?? ""
            if let idx = tools[key], let d = j["delta"]?.string, !d.isEmpty { return [.toolArgs(index: idx, d)] }
        case "response.output_item.done":
            // metin deltası gelmeden tamamlanan mesaj (nadir) — metni bir kerede ver
            let item = j["item"]
            if !sawText, item?["type"]?.string == "message" {
                let t = (item?["content"]?.array ?? []).compactMap { $0["text"]?.string }.joined()
                if !t.isEmpty { sawText = true; return [.text(t)] }
            }
        case "response.completed", "response.incomplete":
            finished = true
            let u = j["response"]?["usage"]
            let usage = CUsage(input: u?["input_tokens"]?.int ?? 0, output: u?["output_tokens"]?.int ?? 0)
            let incomplete = (j["type"]?.string == "response.incomplete")
            return [.finish(reason: toolCount > 0 ? "tool_calls" : (incomplete ? "length" : "stop"), usage: usage)]
        case "response.failed", "error":
            throw upstreamError(j["response"] ?? j, fallback: "Codex yanıtı tamamlanmadı")
        default: break
        }
        return []
    }

    public mutating func end() -> [CEvent] {
        finished ? [] : [.finish(reason: toolCount > 0 ? "tool_calls" : "stop", usage: CUsage())]
    }
}

public struct OpenAIChatDecoder: StreamDecoder {
    var started: Set<Int> = []
    var idToIndex: [String: Int] = [:]
    var lastIndex = 0
    var finishReason: String?
    var usage = CUsage()
    var finished = false
    public init() {}

    public mutating func decode(_ e: SSEEvent) throws -> [CEvent] {
        if e.data == "[DONE]" { return end() }
        guard let j = try? JSON.parse(Data(e.data.utf8)) else { return [] }
        if j["error"] != nil { throw upstreamError(j, fallback: "Upstream akış hatası") }
        if let u = j["usage"], !u.isNull {
            usage = CUsage(input: u["prompt_tokens"]?.int ?? 0, output: u["completion_tokens"]?.int ?? 0)
        }
        var out: [CEvent] = []
        for c in j["choices"]?.array ?? [] {
            let d = c["delta"] ?? c["message"]
            if let t = d?["reasoning_content"]?.string ?? d?["reasoning"]?.string, !t.isEmpty { out.append(.thinking(t)) }
            if let t = d?["content"]?.string, !t.isEmpty { out.append(.text(t)) }
            for tc in d?["tool_calls"]?.array ?? [] {
                // Bazı uyumlu uçlar (Gemini) `index` göndermez: yeni `id` yeni araç, id'siz parça son araca aittir.
                var idx: Int
                if let i = tc["index"]?.int { idx = i }
                else if let id = tc["id"]?.string { idx = idToIndex[id] ?? (started.max().map { $0 + 1 } ?? 0) }
                else { idx = lastIndex }
                if let id = tc["id"]?.string { idToIndex[id] = idx }
                lastIndex = idx
                if !started.contains(idx) {
                    started.insert(idx)
                    out.append(.toolStart(index: idx, id: tc["id"]?.string ?? "call_\(idx)", name: tc["function"]?["name"]?.string ?? ""))
                }
                if let a = tc["function"]?["arguments"]?.string, !a.isEmpty { out.append(.toolArgs(index: idx, a)) }
            }
            if let f = c["finish_reason"]?.string { finishReason = f }
        }
        return out
    }

    public mutating func end() -> [CEvent] {
        if finished { return [] }
        finished = true
        let r = finishReason == "length" ? "length" : (finishReason == "tool_calls" || !started.isEmpty ? "tool_calls" : "stop")
        return [.finish(reason: r, usage: usage)]
    }
}

// MARK: - Toplayıcı (akışsız yanıtlar için)

public struct Aggregate: Sendable {
    public var text = ""
    public var thinking = ""
    public var tools: [(id: String, name: String, args: String)] = []
    public var reason = "stop"
    public var usage = CUsage()
    public init() {}

    public mutating func add(_ e: CEvent) {
        switch e {
        case .text(let t): text += t
        case .thinking(let t): thinking += t
        case .toolStart(let i, let id, let name):
            while tools.count <= i { tools.append(("", "", "")) }
            tools[i] = (id, name, "")
        case .toolArgs(let i, let a):
            while tools.count <= i { tools.append(("", "", "")) }
            tools[i].args += a
        case .finish(let r, let u): reason = r; usage = u
        }
    }
}

// MARK: - İstemciye dönen biçimler

public struct OpenAIChatEncoder: Sendable {
    let id: String
    let model: String
    let created = Int(Date().timeIntervalSince1970)
    let includeUsage: Bool
    var sentRole = false

    public init(model: String, includeUsage: Bool) {
        self.model = model
        self.includeUsage = includeUsage
        self.id = "chatcmpl-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24).lowercased()
    }

    func chunk(_ delta: JSON, finish: String? = nil) -> Data {
        sseData(["id": .string(id), "object": "chat.completion.chunk", "created": .int(created), "model": .string(model),
                 "choices": [["index": 0, "delta": delta, "finish_reason": .str(finish)]]])
    }

    public mutating func encode(_ e: CEvent) -> Data {
        var out = Data()
        if !sentRole { sentRole = true; out.append(chunk(["role": "assistant", "content": ""])) }
        switch e {
        case .text(let t): out.append(chunk(["content": .string(t)]))
        case .thinking(let t): out.append(chunk(["reasoning_content": .string(t)]))
        case .toolStart(let i, let tid, let name):
            out.append(chunk(["tool_calls": [["index": .int(i), "id": .string(tid), "type": "function", "function": ["name": .string(name), "arguments": ""]]]]))
        case .toolArgs(let i, let a):
            out.append(chunk(["tool_calls": [["index": .int(i), "function": ["arguments": .string(a)]]]]))
        case .finish(let r, let u):
            out.append(chunk([:], finish: r))
            if includeUsage {
                out.append(sseData(["id": .string(id), "object": "chat.completion.chunk", "created": .int(created), "model": .string(model), "choices": [],
                                    "usage": ["prompt_tokens": .int(u.input), "completion_tokens": .int(u.output), "total_tokens": .int(u.total)]]))
            }
            out.append(Data("data: [DONE]\n\n".utf8))
        }
        return out
    }

    public func full(_ a: Aggregate) -> JSON {
        var msg: JSON = ["role": "assistant", "content": a.text.isEmpty && !a.tools.isEmpty ? .null : .string(a.text)]
        if !a.thinking.isEmpty { msg["reasoning_content"] = .string(a.thinking) }
        if !a.tools.isEmpty {
            msg["tool_calls"] = .array(a.tools.map { ["id": .string($0.id), "type": "function", "function": ["name": .string($0.name), "arguments": .string($0.args.isEmpty ? "{}" : $0.args)]] })
        }
        return ["id": .string(id), "object": "chat.completion", "created": .int(created), "model": .string(model),
                "choices": [["index": 0, "message": msg, "finish_reason": .string(a.reason)]],
                "usage": ["prompt_tokens": .int(a.usage.input), "completion_tokens": .int(a.usage.output), "total_tokens": .int(a.usage.total)]]
    }
}

public struct AnthropicEncoder: Sendable {
    let id = "msg_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(24)
    let model: String
    var started = false
    var blockIndex = -1
    var openKind: String?   // "text" | "tool"
    var openTool: Int?

    public init(model: String) { self.model = model }

    static let stopMap = ["stop": "end_turn", "length": "max_tokens", "tool_calls": "tool_use"]

    mutating func close(_ out: inout Data) {
        if openKind != nil {
            out.append(sseData(["type": "content_block_stop", "index": .int(blockIndex)], event: "content_block_stop"))
            openKind = nil; openTool = nil
        }
    }

    public mutating func encode(_ e: CEvent) -> Data {
        var out = Data()
        if !started {
            started = true
            out.append(sseData(["type": "message_start", "message": [
                "id": .string(id), "type": "message", "role": "assistant", "model": .string(model), "content": [],
                "stop_reason": nil, "stop_sequence": nil, "usage": ["input_tokens": 0, "output_tokens": 0]]], event: "message_start"))
        }
        switch e {
        case .thinking: break
        case .text(let t):
            if openKind != "text" {
                close(&out); blockIndex += 1; openKind = "text"
                out.append(sseData(["type": "content_block_start", "index": .int(blockIndex), "content_block": ["type": "text", "text": ""]], event: "content_block_start"))
            }
            out.append(sseData(["type": "content_block_delta", "index": .int(blockIndex), "delta": ["type": "text_delta", "text": .string(t)]], event: "content_block_delta"))
        case .toolStart(let i, let tid, let name):
            close(&out); blockIndex += 1; openKind = "tool"; openTool = i
            out.append(sseData(["type": "content_block_start", "index": .int(blockIndex), "content_block": ["type": "tool_use", "id": .string(tid.isEmpty ? "toolu_\(i)" : tid), "name": .string(name), "input": [:]]], event: "content_block_start"))
        case .toolArgs(let i, let a):
            if openKind == "tool", openTool == i {
                out.append(sseData(["type": "content_block_delta", "index": .int(blockIndex), "delta": ["type": "input_json_delta", "partial_json": .string(a)]], event: "content_block_delta"))
            }
        case .finish(let r, let u):
            close(&out)
            out.append(sseData(["type": "message_delta", "delta": ["stop_reason": .string(Self.stopMap[r] ?? "end_turn"), "stop_sequence": nil],
                                "usage": ["input_tokens": .int(u.input), "output_tokens": .int(u.output)]], event: "message_delta"))
            out.append(sseData(["type": "message_stop"], event: "message_stop"))
        }
        return out
    }

    public func full(_ a: Aggregate) -> JSON {
        var content: [JSON] = []
        if !a.text.isEmpty { content.append(["type": "text", "text": .string(a.text)]) }
        for (i, t) in a.tools.enumerated() {
            content.append(["type": "tool_use", "id": .string(t.id.isEmpty ? "toolu_\(i)" : t.id), "name": .string(t.name), "input": parseArgs(t.args)])
        }
        return ["id": .string(id), "type": "message", "role": "assistant", "model": .string(model), "content": .array(content),
                "stop_reason": .string(Self.stopMap[a.reason] ?? "end_turn"), "stop_sequence": nil,
                "usage": ["input_tokens": .int(a.usage.input), "output_tokens": .int(a.usage.output)]]
    }
}
