import Foundation

// MARK: - Ortak ara biçim

public enum CPart: Sendable, Equatable {
    case text(String)
    case image(String)   // http(s) adresi ya da data: URL
}

public struct CToolCall: Sendable, Equatable {
    public var id: String
    public var name: String
    public var arguments: String
}

public struct CMessage: Sendable, Equatable {
    public enum Role: String, Sendable { case user, assistant, tool }
    public var role: Role
    public var parts: [CPart] = []
    public var toolCalls: [CToolCall] = []
    public var toolCallId: String? = nil

    public var text: String {
        parts.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined()
    }
}

public struct CTool: Sendable, Equatable {
    public var name: String
    public var description: String?
    public var parameters: JSON
}

public struct CRequest: Sendable, Equatable {
    public var model: String
    public var system: [String] = []
    public var messages: [CMessage] = []
    public var maxTokens: Int?
    public var temperature: Double?
    public var topP: Double?
    public var stop: [String] = []
    public var stream = false
    public var includeUsage = false
    public var tools: [CTool] = []
    /// OpenAI biçiminde: "auto" | "none" | "required" | {"type":"function","function":{"name":..}}
    public var toolChoice: JSON?
    /// OpenAI response_format
    public var responseFormat: JSON?
    public var reasoningEffort: String?
}

public struct CUsage: Sendable, Equatable {
    public var input = 0
    public var output = 0
    /// Anthropic prompt önbelleğinden okunan / yazılan giriş tokenları (varsa).
    public var cacheRead = 0
    public var cacheWrite = 0
    public var total: Int { input + output }
}

public enum CEvent: Sendable, Equatable {
    case text(String)
    case thinking(String)
    case toolStart(index: Int, id: String, name: String)
    case toolArgs(index: Int, String)
    /// reason: "stop" | "length" | "tool_calls"
    case finish(reason: String, usage: CUsage)
}

// MARK: - Yardımcılar

func contentParts(_ v: JSON?) -> [CPart] {
    guard let v else { return [] }
    if let s = v.string { return s.isEmpty ? [] : [.text(s)] }
    var out: [CPart] = []
    for p in v.array ?? [] {
        switch p["type"]?.string {
        case "text", "input_text", "output_text":
            if let t = p["text"]?.string { out.append(.text(t)) }
        case "image_url":
            if let u = p["image_url"]?["url"]?.string ?? p["image_url"]?.string { out.append(.image(u)) }
        case "input_image":
            if let u = p["image_url"]?.string { out.append(.image(u)) }
        case "image":
            let src = p["source"]
            if src?["type"]?.string == "base64", let d = src?["data"]?.string {
                out.append(.image("data:\(src?["media_type"]?.string ?? "image/png");base64,\(d)"))
            } else if let u = src?["url"]?.string {
                out.append(.image(u))
            }
        default:
            if let t = p["text"]?.string { out.append(.text(t)) }
        }
    }
    return out
}

func textOf(_ v: JSON?) -> String {
    contentParts(v).compactMap { if case .text(let t) = $0 { t } else { nil } }.joined(separator: "\n")
}

func parseArgs(_ s: String) -> JSON {
    (try? JSON.parse(Data(s.utf8))).flatMap { $0.object != nil ? $0 : nil } ?? .object([:])
}

func splitDataURL(_ u: String) -> (mime: String, data: String)? {
    guard u.hasPrefix("data:"), let comma = u.firstIndex(of: ",") else { return nil }
    let header = u[u.index(u.startIndex, offsetBy: 5)..<comma]
    let mime = header.split(separator: ";").first.map(String.init) ?? "image/png"
    return (mime, String(u[u.index(after: comma)...]))
}

// MARK: - Gelen istekleri ayrıştırma

public enum Inbound {
    /// OpenAI /v1/chat/completions gövdesi
    public static func openAIChat(_ b: JSON) throws -> CRequest {
        guard let model = b["model"]?.string else { throw ProxyError.badRequest("model alanı gerekli") }
        guard let msgs = b["messages"]?.array else { throw ProxyError.badRequest("messages alanı gerekli") }
        var r = CRequest(model: model)
        for m in msgs {
            let role = m["role"]?.string ?? "user"
            switch role {
            case "system", "developer":
                let t = textOf(m["content"]); if !t.isEmpty { r.system.append(t) }
            case "tool", "function":
                r.messages.append(CMessage(role: .tool, parts: [.text(textOf(m["content"]))],
                                           toolCallId: m["tool_call_id"]?.string ?? m["name"]?.string ?? ""))
            case "assistant":
                var msg = CMessage(role: .assistant, parts: contentParts(m["content"]))
                for tc in m["tool_calls"]?.array ?? [] {
                    msg.toolCalls.append(CToolCall(id: tc["id"]?.string ?? UUID().uuidString,
                                                   name: tc["function"]?["name"]?.string ?? "",
                                                   arguments: tc["function"]?["arguments"]?.string ?? "{}"))
                }
                r.messages.append(msg)
            default:
                r.messages.append(CMessage(role: .user, parts: contentParts(m["content"])))
            }
        }
        r.maxTokens = b["max_completion_tokens"]?.int ?? b["max_tokens"]?.int
        r.temperature = b["temperature"]?.double
        r.topP = b["top_p"]?.double
        if let s = b["stop"]?.string { r.stop = [s] } else { r.stop = b["stop"]?.array?.compactMap(\.string) ?? [] }
        r.stream = b["stream"]?.bool ?? false
        r.includeUsage = b["stream_options"]?["include_usage"]?.bool ?? false
        for t in b["tools"]?.array ?? [] {
            let f = t["function"] ?? t
            guard let name = f["name"]?.string else { continue }
            r.tools.append(CTool(name: name, description: f["description"]?.string,
                                 parameters: f["parameters"] ?? ["type": "object", "properties": [:]]))
        }
        r.toolChoice = b["tool_choice"]
        r.responseFormat = b["response_format"]
        r.reasoningEffort = b["reasoning_effort"]?.string
        return r
    }

    /// Anthropic /v1/messages gövdesi
    public static func anthropic(_ b: JSON) throws -> CRequest {
        guard let model = b["model"]?.string else { throw ProxyError.badRequest("model alanı gerekli") }
        var r = CRequest(model: model)
        r.reasoningEffort = b["output_config"]?["effort"]?.string
        if let s = b["system"]?.string { if !s.isEmpty { r.system = [s] } }
        else if let arr = b["system"]?.array { r.system = arr.compactMap { $0["text"]?.string }.filter { !$0.isEmpty } }
        for m in b["messages"]?.array ?? [] {
            let role = m["role"]?.string ?? "user"
            if let s = m["content"]?.string {
                r.messages.append(CMessage(role: role == "assistant" ? .assistant : .user, parts: [.text(s)]))
                continue
            }
            var parts: [CPart] = []
            var calls: [CToolCall] = []
            for blk in m["content"]?.array ?? [] {
                switch blk["type"]?.string {
                case "tool_use":
                    calls.append(CToolCall(id: blk["id"]?.string ?? "", name: blk["name"]?.string ?? "",
                                           arguments: (blk["input"] ?? .object([:])).text()))
                case "tool_result":
                    var t = textOf(blk["content"])
                    if blk["is_error"]?.bool == true { t = "HATA: " + t }
                    r.messages.append(CMessage(role: .tool, parts: [.text(t)], toolCallId: blk["tool_use_id"]?.string ?? ""))
                case "thinking", "redacted_thinking":
                    continue
                default:
                    parts.append(contentsOf: contentParts(.array([blk])))
                }
            }
            if role == "assistant" {
                if !parts.isEmpty || !calls.isEmpty { r.messages.append(CMessage(role: .assistant, parts: parts, toolCalls: calls)) }
            } else if !parts.isEmpty {
                r.messages.append(CMessage(role: .user, parts: parts))
            }
        }
        r.maxTokens = b["max_tokens"]?.int
        r.temperature = b["temperature"]?.double
        r.topP = b["top_p"]?.double
        r.stop = b["stop_sequences"]?.array?.compactMap(\.string) ?? []
        r.stream = b["stream"]?.bool ?? false
        r.includeUsage = true
        for t in b["tools"]?.array ?? [] {
            guard let name = t["name"]?.string, t["input_schema"] != nil || t["type"] == nil else { continue }
            r.tools.append(CTool(name: name, description: t["description"]?.string,
                                 parameters: t["input_schema"] ?? ["type": "object", "properties": [:]]))
        }
        if let tc = b["tool_choice"] {
            switch tc["type"]?.string {
            case "auto": r.toolChoice = "auto"
            case "any": r.toolChoice = "required"
            case "none": r.toolChoice = "none"
            case "tool": r.toolChoice = ["type": "function", "function": ["name": .str(tc["name"]?.string)]]
            default: break
            }
        }
        if let of = b["output_format"], of["type"]?.string == "json_schema" {
            r.responseFormat = ["type": "json_schema", "json_schema": ["name": "cikti", "schema": of["schema"] ?? [:], "strict": true]]
        }
        return r
    }
}

// MARK: - Upstream gövdeleri

public enum Outbound {
    public static let claudeCodeIdentity = "You are Claude Code, Anthropic's official CLI for Claude."

    /// Anthropic Messages gövdesi (OAuth kimlik bloğu yürütücüde eklenir)
    public static func anthropic(_ r: CRequest) -> JSON {
        var messages: [JSON] = []
        var pendingResults: [JSON] = []
        func flush() {
            if !pendingResults.isEmpty { messages.append(["role": "user", "content": .array(pendingResults)]); pendingResults = [] }
        }
        for m in r.messages {
            if m.role == .tool {
                pendingResults.append(["type": "tool_result", "tool_use_id": .string(m.toolCallId ?? ""), "content": .string(m.text)])
                continue
            }
            flush()
            var blocks: [JSON] = []
            for p in m.parts {
                switch p {
                case .text(let t): if !t.isEmpty { blocks.append(["type": "text", "text": .string(t)]) }
                case .image(let u):
                    if let d = splitDataURL(u) {
                        blocks.append(["type": "image", "source": ["type": "base64", "media_type": .string(d.mime), "data": .string(d.data)]])
                    } else {
                        blocks.append(["type": "image", "source": ["type": "url", "url": .string(u)]])
                    }
                }
            }
            for tc in m.toolCalls {
                blocks.append(["type": "tool_use", "id": .string(tc.id), "name": .string(tc.name), "input": parseArgs(tc.arguments)])
            }
            if blocks.isEmpty { blocks.append(["type": "text", "text": "..."]) }
            messages.append(["role": .string(m.role == .assistant ? "assistant" : "user"), "content": .array(blocks)])
        }
        flush()
        var b: JSON = ["model": .string(r.model), "messages": .array(messages), "max_tokens": .int(r.maxTokens ?? 8192)]
        if !r.system.isEmpty { b["system"] = .array(r.system.map { ["type": "text", "text": .string($0)] }) }
        if let effort = r.reasoningEffort { b["output_config"] = ["effort": .string(effort)] }
        if let t = r.temperature { b["temperature"] = .number(t) } else if let p = r.topP { b["top_p"] = .number(p) }
        if !r.stop.isEmpty { b["stop_sequences"] = .array(r.stop.map { .string($0) }) }
        if !r.tools.isEmpty {
            b["tools"] = .array(r.tools.map { ["name": .string($0.name), "description": .string($0.description ?? ""), "input_schema": $0.parameters] })
        }
        if let tc = r.toolChoice {
            if let s = tc.string {
                switch s {
                case "required": b["tool_choice"] = ["type": "any"]
                case "none": b["tool_choice"] = ["type": "none"]
                default: b["tool_choice"] = ["type": "auto"]
                }
            } else if let n = tc["function"]?["name"]?.string {
                b["tool_choice"] = ["type": "tool", "name": .string(n)]
            }
        }
        b["stream"] = true
        return b
    }

    /// ChatGPT Codex (Responses API) gövdesi
    public static func responses(_ r: CRequest, forCodex: Bool) -> JSON {
        var input: [JSON] = []
        for m in r.messages {
            switch m.role {
            case .tool:
                input.append(["type": "function_call_output", "call_id": .string(m.toolCallId ?? ""), "output": .string(m.text)])
            case .user, .assistant:
                if !m.parts.isEmpty {
                    let hasImage = m.parts.contains { if case .image = $0 { true } else { false } }
                    let content: JSON
                    if !hasImage || m.role == .assistant {
                        content = .string(m.text)
                    } else {
                        content = .array(m.parts.map {
                            switch $0 {
                            case .text(let t): ["type": "input_text", "text": .string(t)]
                            case .image(let u): ["type": "input_image", "image_url": .string(u)]
                            }
                        })
                    }
                    input.append(["role": .string(m.role.rawValue), "content": content])
                }
                for tc in m.toolCalls {
                    input.append(["type": "function_call", "call_id": .string(tc.id), "name": .string(tc.name), "arguments": .string(tc.arguments.isEmpty ? "{}" : tc.arguments)])
                }
            }
        }
        var b: JSON = ["model": .string(r.model), "input": .array(input), "store": false, "stream": true]
        b["instructions"] = .string(r.system.joined(separator: "\n\n"))
        if !forCodex {
            if let m = r.maxTokens { b["max_output_tokens"] = .int(m) }
            if let t = r.temperature { b["temperature"] = .number(t) }
            if let p = r.topP { b["top_p"] = .number(p) }
        }
        if !r.tools.isEmpty {
            b["tools"] = .array(r.tools.map { ["type": "function", "name": .string($0.name), "description": .string($0.description ?? ""), "parameters": $0.parameters] })
        }
        if let tc = r.toolChoice {
            if let s = tc.string { b["tool_choice"] = .string(s) }
            else if let n = tc["function"]?["name"]?.string { b["tool_choice"] = ["type": "function", "name": .string(n)] }
        }
        if let rf = r.responseFormat {
            switch rf["type"]?.string {
            case "json_schema":
                let js = rf["json_schema"] ?? [:]
                var f: JSON = ["type": "json_schema", "name": .string(js["name"]?.string ?? "cikti"), "schema": js["schema"] ?? [:]]
                if let s = js["strict"]?.bool { f["strict"] = .bool(s) }
                b["text"] = ["format": f]
            case "json_object":
                b["text"] = ["format": ["type": "json_object"]]
            default: break
            }
        }
        if let e = r.reasoningEffort { b["reasoning"] = ["effort": .string(e)] }
        return b
    }

    /// OpenAI uyumlu /chat/completions gövdesi (OpenAI API, Gemini uyumlu uç)
    public static func openAIChat(_ r: CRequest, upstreamModel: String) -> JSON {
        var msgs: [JSON] = []
        if !r.system.isEmpty { msgs.append(["role": "system", "content": .string(r.system.joined(separator: "\n\n"))]) }
        for m in r.messages {
            switch m.role {
            case .tool:
                msgs.append(["role": "tool", "tool_call_id": .string(m.toolCallId ?? ""), "content": .string(m.text)])
            case .assistant:
                var j: JSON = ["role": "assistant", "content": m.parts.isEmpty ? .null : .string(m.text)]
                if !m.toolCalls.isEmpty {
                    j["tool_calls"] = .array(m.toolCalls.map {
                        ["id": .string($0.id), "type": "function", "function": ["name": .string($0.name), "arguments": .string($0.arguments)]]
                    })
                }
                msgs.append(j)
            case .user:
                let hasImage = m.parts.contains { if case .image = $0 { true } else { false } }
                if hasImage {
                    msgs.append(["role": "user", "content": .array(m.parts.map {
                        switch $0 {
                        case .text(let t): ["type": "text", "text": .string(t)]
                        case .image(let u): ["type": "image_url", "image_url": ["url": .string(u)]]
                        }
                    })])
                } else {
                    msgs.append(["role": "user", "content": .string(m.text)])
                }
            }
        }
        var b: JSON = ["model": .string(upstreamModel), "messages": .array(msgs), "stream": true,
                       "stream_options": ["include_usage": true]]
        if let m = r.maxTokens { b["max_tokens"] = .int(m) }
        if let t = r.temperature { b["temperature"] = .number(t) }
        if let p = r.topP { b["top_p"] = .number(p) }
        if !r.stop.isEmpty { b["stop"] = .array(r.stop.map { .string($0) }) }
        if !r.tools.isEmpty {
            b["tools"] = .array(r.tools.map { ["type": "function", "function": ["name": .string($0.name), "description": .string($0.description ?? ""), "parameters": $0.parameters]] })
        }
        if let tc = r.toolChoice { b["tool_choice"] = tc }
        if let rf = r.responseFormat { b["response_format"] = rf }
        if let e = r.reasoningEffort { b["reasoning_effort"] = .string(e) }
        return b
    }
}
