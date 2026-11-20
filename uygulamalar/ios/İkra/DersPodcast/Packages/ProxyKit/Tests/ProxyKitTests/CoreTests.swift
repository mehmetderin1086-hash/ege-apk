import Foundation
import Testing
@testable import ProxyKit

@Suite struct JSONTests {
    @Test func boolSayiAyrimi() throws {
        let j = try JSON.parse(Data(#"{"a":true,"b":1,"c":1.5,"d":"x","e":null,"f":[1,false]}"#.utf8))
        #expect(j["a"] == .bool(true))
        #expect(j["b"]?.int == 1)
        #expect(j["c"]?.double == 1.5)
        #expect(j["e"]?.isNull == true)
        #expect(j["f"]?[1] == .bool(false))
        #expect(j.text().contains(#""b":1"#))
    }
}

@Suite struct SSEParserTests {
    @Test func parcaliVeCRLF() {
        var p = SSEParser()
        var out: [SSEEvent] = []
        out += p.feed(Data("event: a\r\ndata: {\"x\"".utf8))
        #expect(out.isEmpty)
        out += p.feed(Data(":1}\r\n\r\ndata: iki\n".utf8))
        out += p.feed(Data("data: satir\n\n: yorum\n\n".utf8))
        #expect(out == [SSEEvent(event: "a", data: #"{"x":1}"#), SSEEvent(event: nil, data: "iki\nsatir")])
    }
}

@Suite struct TranslationTests {
    @Test func openAIdenAnthropica() throws {
        let body = try JSON.parse(Data("""
        {"model":"claude-opus-5-5","max_tokens":100,"tool_choice":"required",
         "messages":[{"role":"system","content":"Kısa yaz"},
          {"role":"user","content":[{"type":"text","text":"Bu ne?"},{"type":"image_url","image_url":{"url":"data:image/jpeg;base64,QUJD"}}]},
          {"role":"assistant","content":null,"tool_calls":[{"id":"c1","type":"function","function":{"name":"bak","arguments":"{\\"a\\":1}"}}]},
          {"role":"tool","tool_call_id":"c1","content":"sonuç"},
          {"role":"user","content":"devam"}],
         "tools":[{"type":"function","function":{"name":"bak","parameters":{"type":"object"}}}]}
        """.utf8))
        let c = try Inbound.openAIChat(body)
        let a = Outbound.anthropic(c)
        #expect(a["system"]?[0]?["text"] == "Kısa yaz")
        #expect(a["max_tokens"]?.int == 100)
        #expect(a["tool_choice"]?["type"] == "any")
        let msgs = a["messages"]!.array!
        #expect(msgs.count == 4)
        #expect(msgs[0]["content"]?[1]?["source"]?["media_type"] == "image/jpeg")
        #expect(msgs[0]["content"]?[1]?["source"]?["data"] == "QUJD")
        #expect(msgs[1]["content"]?[0]?["type"] == "tool_use")
        #expect(msgs[1]["content"]?[0]?["input"]?["a"]?.int == 1)
        #expect(msgs[2]["content"]?[0]?["type"] == "tool_result")
        #expect(msgs[2]["role"] == "user")
        #expect(msgs[3]["content"]?[0]?["text"] == "devam")
    }

    @Test func anthropictenResponsesa() throws {
        let body = try JSON.parse(Data("""
        {"model":"gpt-5.5","max_tokens":50,"system":[{"type":"text","text":"Sen öğretmensin"}],
         "messages":[{"role":"user","content":[{"type":"text","text":"Çiz"},{"type":"image","source":{"type":"base64","media_type":"image/png","data":"WFla"}}]},
          {"role":"assistant","content":[{"type":"thinking","thinking":"..."},{"type":"text","text":"Bakıyorum"},{"type":"tool_use","id":"t1","name":"olc","input":{"x":2}}]},
          {"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":[{"type":"text","text":"42"}]},{"type":"text","text":"tamam"}]}],
         "tools":[{"name":"olc","input_schema":{"type":"object"}}],"tool_choice":{"type":"tool","name":"olc"}}
        """.utf8))
        let c = try Inbound.anthropic(body)
        let r = Outbound.responses(c, forCodex: true)
        #expect(r["instructions"] == "Sen öğretmensin")
        #expect(r["max_output_tokens"] == nil)
        let input = r["input"]!.array!
        #expect(input[0]["content"]?[1]?["type"] == "input_image")
        #expect(input[0]["content"]?[1]?["image_url"] == "data:image/png;base64,WFla")
        #expect(input[1]["content"] == "Bakıyorum")
        #expect(input[2]["type"] == "function_call")
        #expect(input[2]["arguments"]?.string?.contains("\"x\":2") == true)
        #expect(input[3]["type"] == "function_call_output")
        #expect(input[3]["output"] == "42")
        #expect(input[4]["content"] == "tamam")
        #expect(r["tool_choice"]?["name"] == "olc")
        #expect(r["tools"]?[0]?["name"] == "olc")
    }

    @Test func jsonSemaResponsesa() throws {
        let c = try Inbound.openAIChat(try JSON.parse(Data(#"{"model":"gpt-5.5","messages":[{"role":"user","content":"x"}],"response_format":{"type":"json_schema","json_schema":{"name":"s","schema":{"type":"object"},"strict":true}}}"#.utf8)))
        let r = Outbound.responses(c, forCodex: true)
        #expect(r["text"]?["format"]?["type"] == "json_schema")
        #expect(r["text"]?["format"]?["name"] == "s")
        #expect(r["instructions"] == "")
    }
}

@Suite struct StreamTests {
    func decode<D: StreamDecoder>(_ text: String, _ d: D, chunk: Int = 5) throws -> [CEvent] {
        var dec = d; var p = SSEParser(); var out: [CEvent] = []
        let data = Data(text.utf8); var i = 0
        while i < data.count {
            for e in p.feed(data.subdata(in: i..<min(data.count, i + chunk))) { out += try dec.decode(e) }
            i += chunk
        }
        for e in p.finish() { out += try dec.decode(e) }
        out += dec.end()
        return out
    }

    @Test func anthropicCozumu() throws {
        let ev = try decode(Fixtures.anthropicSSE, AnthropicDecoder())
        #expect(ev.contains(.text("Merhaba")))
        #expect(ev.contains(.toolStart(index: 0, id: "toolu_9", name: "hava")))
        #expect(ev.last == .finish(reason: "tool_calls", usage: CUsage(input: 12, output: 20)))
        var agg = Aggregate(); ev.forEach { agg.add($0) }
        let full = OpenAIChatEncoder(model: "claude-opus-5-5", includeUsage: false).full(agg)
        #expect(full["choices"]?[0]?["message"]?["content"] == "Merhaba dünya")
        #expect(full["choices"]?[0]?["message"]?["tool_calls"]?[0]?["function"]?["arguments"] == #"{"sehir":"İzmir"}"#)
        #expect(full["choices"]?[0]?["finish_reason"] == "tool_calls")
        #expect(full["usage"]?["total_tokens"]?.int == 32)
    }

    @Test func openAIAkisKodlayici() throws {
        let ev = try decode(Fixtures.anthropicSSE, AnthropicDecoder())
        var enc = OpenAIChatEncoder(model: "m", includeUsage: true)
        let out = String(decoding: ev.reduce(Data()) { $0 + enc.encode($1) }, as: UTF8.self)
        #expect(out.contains(#""role":"assistant""#))
        #expect(out.contains(#""content":" dünya""#))
        #expect(out.contains(#""finish_reason":"tool_calls""#))
        #expect(out.contains(#""prompt_tokens":12"#))
        #expect(out.hasSuffix("data: [DONE]\n\n"))
    }

    @Test func responsesdenAnthropica() throws {
        let ev = try decode(Fixtures.responsesSSE, ResponsesDecoder())
        #expect(ev.filter { if case .text = $0 { true } else { false } }.count == 2)   // done öğesi metni tekrarlamaz
        var enc = AnthropicEncoder(model: "gpt-5.5")
        let out = String(decoding: ev.reduce(Data()) { $0 + enc.encode($1) }, as: UTF8.self)
        let types = out.components(separatedBy: "\n").filter { $0.hasPrefix("event: ") }.map { String($0.dropFirst(7)) }
        #expect(types == ["message_start", "content_block_start", "content_block_delta", "content_block_delta", "content_block_stop",
                          "content_block_start", "content_block_delta", "content_block_stop", "message_delta", "message_stop"])
        #expect(out.contains(#""stop_reason":"tool_use""#))
        var agg = Aggregate(); ev.forEach { agg.add($0) }
        let full = AnthropicEncoder(model: "gpt-5.5").full(agg)
        #expect(full["content"]?[0]?["text"] == "Selam!")
        #expect(full["content"]?[1]?["input"]?["q"]?.int == 1)
        #expect(full["usage"]?["output_tokens"]?.int == 3)
    }

    @Test func openAIAkisCozumu() throws {
        let ev = try decode(Fixtures.openAISSE, OpenAIChatDecoder())
        #expect(ev == [.text("Gemini"), .text(" yanıtı"), .finish(reason: "stop", usage: CUsage(input: 4, output: 2))])
    }

    @Test func akisHatasi() {
        var d = AnthropicDecoder()
        #expect(throws: ProxyError.self) {
            _ = try d.decode(SSEEvent(event: "error", data: #"{"type":"error","error":{"type":"overloaded_error","message":"Yoğun"}}"#))
        }
    }
}

@Suite struct RouterTests {
    @Test func sunucuTablosuylaYonlendirme() {
        let r = ModelRouter(state: sampleState())
        #expect(r.resolve("claude-opus-5-5") == .claude)
        #expect(r.resolve("gpt-5.5") == .codex)
        #expect(r.resolve("gpt-6-sol") == .api("openai-api"))
        #expect(r.resolve("gpt-4o-mini-tts") == .api("openai-api"))
        #expect(r.resolve("dersdas-gemini-ocr") == .api("gemini-script"))
        #expect(r.resolve("gemini-3.8-flash-tts") == .api("gemini-tts"))
        #expect(r.resolve("gemini-4-argon") == .remote)
        #expect(r.resolve("antigravity-claude-opus-5-5") == .remote)
        #expect(r.resolve("qwen2.5-math-1.5b-instruct") == .remote)
        #expect(r.resolve("gpt-image-2.5-flare") == .remote)
        #expect(r.resolve("gemini-2.5-flash") == .remote)     // gemini OAuth sağlayıcısı telefonda yürütülmüyor
        #expect(r.resolve("bilinmeyen") == .remote)
    }

    @Test func desen() {
        #expect(globMatch("gpt-*", "gpt-5.5"))
        #expect(globMatch("*-live", "gemini-3.8-live"))
        #expect(!globMatch("claude-*", "xclaude-1"))
        #expect(globMatch("o?-*", "o3-mini"))
    }

    @Test func yerelModelListesi() {
        let ids = ModelRouter(state: sampleState()).localModels().map(\.id)
        #expect(ids.contains("claude-opus-5-5"))
        #expect(ids.contains("gpt-5.5"))
        #expect(ids.contains("dersdas-gemini-ocr"))
        #expect(!ids.contains("gemini-4-argon"))
    }
}

@Suite struct BundleTests {
    static let sample = """
    {"surum":1,"olusturma":"2026-10-17T10:00:00+00:00","kaynak":"82.29.179.131",
     "oauth":[{"provider":"claude","id":"claude-default","label":"claude-account","enabled":true,"access_token":"sk-ant-oat01-A","refresh_token":"sk-ant-ort01-B","expires_at":"2026-10-17T17:33:01.123456+00:00","scopes":["user:inference"],"metadata":{"label":"claude-account"}},
              {"provider":"codex","id":"9cad1b59","enabled":true,"access_token":"eyJ","refresh_token":"rt","expires_at":"2026-10-25T00:00:00+00:00","metadata":{"account_id":"acc","email":"m@icloud.com","plan":"plus","sayi":3}},
              {"provider":"bilinmez","id":"x","enabled":true,"access_token":"a"}],
     "api_anahtarlari":[{"name":"openai-api","kind":"openai","base_url":"https://api.openai.com/v1","api_key":"sk-o","models":["gpt-6-sol"],"filter":{"gpt-6-sol":["max_tokens"]}},
                        {"name":"gemini-tts","kind":"gemini-native","base_url":"https://generativelanguage.googleapis.com","api_key":"g","models":["gemini-3.8-flash-tts"]}],
     "istemci_anahtarlari":[{"name":"Dersdas Questions","sha256":"abc","enabled":true}],
     "yonlendirme":[["gemini-4-argon","gemini-pro-account"],["claude-*","claude"]],
     "yedekler":{"gemini-2.5-pro":["gemini-2.5-flash"]},"varsayilan_model":"gemini-3.1-flash-lite",
     "uzak":{"base_url":"https://alan/dersdas/claude/v1","personal_token":"pt","sync_token":"st"}}
    """

    @Test func iceAktar() throws {
        let b = try BundleImporter.decode(Data(Self.sample.utf8))
        var s = ProxyState()
        let sum = BundleImporter.apply(b, to: &s)
        #expect(sum.oauth == 2)
        #expect(s.oauth.first { $0.provider == .claude }?.expiresAt != nil)
        #expect(s.oauth.first { $0.provider == .codex }?.metadata["sayi"] == "3")
        #expect(s.oauth.first { $0.provider == .codex }?.label == "m@icloud.com")
        #expect(s.oauth.allSatisfy { $0.refreshOwner == .sunucu })
        #expect(s.apiProviders.count == 2 && s.apiProviders[1].kind == .geminiNative)
        #expect(s.routing == [RouteRule(pattern: "gemini-4-argon", target: "gemini-pro-account"), RouteRule(pattern: "claude-*", target: "claude")])
        #expect(s.remote.isUsable && s.remote.rootURL == "https://alan/dersdas/claude")
        // ikinci içe aktarma: sahiplik seçimi korunur, kopya oluşmaz
        s.oauth[0].refreshOwner = .telefon
        _ = BundleImporter.apply(b, to: &s)
        #expect(s.oauth.count == 2)
        #expect(s.oauth.first { $0.provider == .claude }?.refreshOwner == .telefon)
    }

    @Test func surumReddi() {
        #expect(throws: BundleError.self) { try BundleImporter.decode(Data(#"{"surum":2,"oauth":[],"api_anahtarlari":[]}"#.utf8)) }
    }

    @Test func kasaKalicilik() async throws {
        let store = MemorySecretStore()
        let v1 = Vault(store: store)
        try await v1.update { $0.localKey = "kalici" }
        let v2 = Vault(store: store)
        #expect(await v2.state.localKey == "kalici")
    }
}

@Suite struct GorselModelTests {
    @Test func sohbetteSunucuyaGider() {
        let r = ModelRouter(state: sampleState())
        #expect(r.resolve("gemini-3-pro-image") == .remote)
        #expect(r.resolve("gemini-3.1-flash-image") == .remote)
    }
}
