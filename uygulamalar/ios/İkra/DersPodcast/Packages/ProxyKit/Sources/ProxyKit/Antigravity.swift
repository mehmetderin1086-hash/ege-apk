import Foundation

/// Antigravity: Google Code Assist arka ucu (`v1internal:streamGenerateContent`), Gemini istek biçimi.
/// Aynı hesap Claude Opus/Sonnet 5.5, Gemini 3.x Flash ve GPT-OSS sunar.
public enum Antigravity {
    /// Hesabın `fetchAvailableModels` listesi (17 Eki 2026). Gemini 4 Argon ve 3.1 Pro burada yok: onları sunucudaki
    /// `agy` kendi iç çözümlemesiyle sunar, bu yüzden sunucuda kalırlar.
    public static let models = ["claude-opus-5-5-high", "claude-opus-5-5-medium", "claude-opus-5-5-low",
                                "claude-sonnet-5-5-high", "claude-sonnet-5-5-medium", "claude-sonnet-5-5-low",
                                "gemini-3.8-flash-tiered", "gemini-3-flash", "gemini-3-flash-agent", "gemini-3.5-flash-low",
                                "gemini-3.5-flash-extra-low", "gemini-3.5-flash-lite", "gemini-3.1-flash-lite", "gemini-2.5-pro",
                                "gpt-oss-120b-medium"]

    /// İstemci model adından Antigravity modeline (ve Gemini düşünme düzeyine).
    public static func target(_ model: String) -> (model: String, thinking: String?)? {
        switch model {
        case "antigravity-claude-opus-5-5": return ("claude-opus-5-5-high", nil)
        case "antigravity-claude-sonnet-5-5": return ("claude-sonnet-5-5-high", nil)
        case "gemini-3.8-flash": return ("gemini-3.8-flash-tiered", nil)
        case "gemini-3.8-flash-high": return ("gemini-3.8-flash-tiered", "high")
        case "gemini-3.8-flash-medium": return ("gemini-3.8-flash-tiered", "medium")
        case "gemini-3.8-flash-low": return ("gemini-3.8-flash-tiered", "low")
        default:
            if model.hasPrefix("antigravity-") {
                let id = String(model.dropFirst("antigravity-".count))
                if models.contains(id) { return (id, nil) }
            }
            return nil
        }
    }

    /// Gemini API anahtarı ödeme/kota hatası verdiğinde aynı isteğin gidebileceği Antigravity modeli (abonelikle gelir).
    /// Yalnız metin Flash ailesi: görsel, ses, canlı ve Pro modellerinin eşdeğeri yok.
    public static func substitute(forGeminiModel upstream: String) -> (model: String, thinking: String?)? {
        let m = upstream.lowercased()
        guard m.hasPrefix("gemini"), m.contains("flash"),
              !["image", "tts", "live", "audio", "embedding"].contains(where: { m.contains($0) }) else { return nil }
        if m.contains("lite") { return ("gemini-3.5-flash-lite", nil) }
        return ("gemini-3.8-flash-tiered", nil)
    }

    /// Telefonda sunulan Antigravity model adları (sunucudaki adlar + kademeli adlar)
    public static var clientModels: [String] {
        ["antigravity-claude-opus-5-5", "antigravity-claude-sonnet-5-5",
         "gemini-3.8-flash", "gemini-3.8-flash-high", "gemini-3.8-flash-medium", "gemini-3.8-flash-low"]
            + models.map { "antigravity-" + $0 }
    }

    /// JSON şemasından Gemini'nin kabul etmediği anahtarları ayıklar.
    static func cleanSchema(_ j: JSON) -> JSON {
        switch j {
        case .object(let o):
            var out: [String: JSON] = [:]
            for (k, v) in o where !["$schema", "$id", "additionalProperties", "$defs", "definitions"].contains(k) { out[k] = cleanSchema(v) }
            return .object(out)
        case .array(let a): return .array(a.map(cleanSchema))
        default: return j
        }
    }

    /// Ortak ara biçimden Code Assist sarmalayıcısına.
    public static func body(_ r: CRequest, model: String, thinking: String?, project: String, signatures: [String: String] = [:]) -> JSON {
        var names: [String: String] = [:]
        for m in r.messages { for tc in m.toolCalls { names[tc.id] = tc.name } }
        var contents: [JSON] = []
        func push(_ role: String, _ parts: [JSON]) {
            guard !parts.isEmpty else { return }
            // Ardışık aynı rol tek içerikte birleşir (Claude dönüşümlü sıra ister).
            if case .object(var last)? = contents.last, last["role"]?.string == role, case .array(let old)? = last["parts"] {
                last["parts"] = .array(old + parts)
                contents[contents.count - 1] = .object(last)
            } else {
                contents.append(["role": .string(role), "parts": .array(parts)])
            }
        }
        for m in r.messages {
            switch m.role {
            case .tool:
                let id = m.toolCallId ?? ""
                push("user", [["functionResponse": ["name": .string(names[id] ?? "arac"), "id": .string(id), "response": ["output": .string(m.text)]]]])
            case .user, .assistant:
                var parts: [JSON] = m.parts.compactMap { p in
                    switch p {
                    case .text(let t): return t.isEmpty ? nil : ["text": .string(t)]
                    case .image(let u):
                        if let d = splitDataURL(u) { return ["inlineData": ["mimeType": .string(d.mime), "data": .string(d.data)]] }
                        return ["fileData": ["fileUri": .string(u), "mimeType": "image/jpeg"]]
                    }
                }
                for tc in m.toolCalls {
                    var part: JSON = ["functionCall": ["name": .string(tc.name), "args": parseArgs(tc.arguments), "id": .string(tc.id)]]
                    if let signature = signatures[tc.id] { part["thoughtSignature"] = .string(signature) }
                    parts.append(part)
                }
                push(m.role == .assistant ? "model" : "user", parts)
            }
        }
        var gen: JSON = ["maxOutputTokens": .int(r.maxTokens ?? 8192)]
        if let t = r.temperature { gen["temperature"] = .number(t) }
        if let p = r.topP { gen["topP"] = .number(p) }
        if !r.stop.isEmpty { gen["stopSequences"] = .array(r.stop.map { .string($0) }) }
        if let level = thinking ?? r.reasoningEffort, model.hasPrefix("gemini") { gen["thinkingConfig"] = ["thinkingLevel": .string(level)] }
        if r.responseFormat?["type"]?.string == "json_schema" || r.responseFormat?["type"]?.string == "json_object" {
            gen["responseMimeType"] = "application/json"
        }
        var req: JSON = ["contents": .array(contents), "generationConfig": gen]
        if !r.system.isEmpty { req["systemInstruction"] = ["parts": .array(r.system.map { ["text": .string($0)] })] }
        if !r.tools.isEmpty {
            req["tools"] = [["functionDeclarations": .array(r.tools.map {
                ["name": .string($0.name), "description": .string($0.description ?? ""), "parameters": cleanSchema($0.parameters)]
            })]]
            if let tc = r.toolChoice {
                var mode = "AUTO"
                if tc.string == "required" { mode = "ANY" } else if tc.string == "none" { mode = "NONE" }
                var fc: JSON = ["mode": .string(mode)]
                if let n = tc["function"]?["name"]?.string { fc = ["mode": "ANY", "allowedFunctionNames": [.string(n)]] }
                req["toolConfig"] = ["functionCallingConfig": fc]
            }
        }
        return ["project": .string(project), "model": .string(model), "userAgent": "antigravity", "requestType": "agent",
                "requestId": .string("agent-" + UUID().uuidString.lowercased()), "request": req]
    }
}

/// Code Assist SSE akışı → ortak olaylar. `finish` akış sonunda verilir (son parçada kullanım güncellenir).
public struct GeminiDecoder: StreamDecoder {
    var usage = CUsage()
    var reason = "stop"
    var toolCount = 0
    var finished = false
    var saveSignature: (@Sendable (String, String) -> Void)?
    public init() {}
    init(saveSignature: @escaping @Sendable (String, String) -> Void) { self.saveSignature = saveSignature }

    public mutating func decode(_ e: SSEEvent) throws -> [CEvent] {
        guard let j = try? JSON.parse(Data(e.data.utf8)) else { return [] }
        if j["error"] != nil { throw upstreamError(j, fallback: "Antigravity akış hatası") }
        let resp = j["response"] ?? j
        if let u = resp["usageMetadata"] {
            usage = CUsage(input: u["promptTokenCount"]?.int ?? usage.input, output: (u["candidatesTokenCount"]?.int ?? 0) + (u["thoughtsTokenCount"]?.int ?? 0))
        }
        var out: [CEvent] = []
        for c in resp["candidates"]?.array ?? [] {
            for p in c["content"]?["parts"]?.array ?? [] {
                if let fc = p["functionCall"] {
                    let idx = toolCount; toolCount += 1
                    let id = fc["id"]?.string ?? "call_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
                    if let signature = p["thoughtSignature"]?.string { saveSignature?(id, signature) }
                    out.append(.toolStart(index: idx, id: id, name: fc["name"]?.string ?? ""))
                    out.append(.toolArgs(index: idx, (fc["args"] ?? .object([:])).text()))
                } else if let t = p["text"]?.string, !t.isEmpty {
                    out.append(p["thought"]?.bool == true ? .thinking(t) : .text(t))
                }
            }
            switch c["finishReason"]?.string {
            case "MAX_TOKENS": reason = "length"
            case "SAFETY", "RECITATION", "PROHIBITED_CONTENT": reason = "stop"
            default: break
            }
        }
        return out
    }

    public mutating func end() -> [CEvent] {
        if finished { return [] }
        finished = true
        return [.finish(reason: toolCount > 0 ? "tool_calls" : reason, usage: usage)]
    }
}

/// Opaque provider signatures stay only in this engine's bounded memory, never logs or disk.
final class GeminiSignatureCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var order: [String] = []
    func save(model: String, id: String, signature: String) {
        guard signature.utf8.count <= 65_536 else { return }
        lock.withLock {
            let key = model + ":" + id
            if values[key] == nil { order.append(key) }
            values[key] = signature
            while order.count > 256 { values.removeValue(forKey: order.removeFirst()) }
        }
    }
    func signatures(model: String, ids: [String]) -> [String: String] {
        lock.withLock {
            var result: [String: String] = [:]
            for id in ids { if let value = values[model + ":" + id] { result[id] = value } }
            return result
        }
    }
}
