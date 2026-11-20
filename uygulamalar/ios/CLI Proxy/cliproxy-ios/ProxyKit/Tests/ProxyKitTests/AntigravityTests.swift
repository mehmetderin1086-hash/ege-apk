import Foundation
import Testing
@testable import ProxyKit

enum AGFixtures {
    static let sse = """
    data: {"response": {"candidates": [{"content": {"role": "model","parts": [{"text": ""}]}}],"usageMetadata": {"promptTokenCount": 401,"candidatesTokenCount": 5}}}

    data: {"response": {"candidates": [{"content": {"role": "model","parts": [{"thought": true, "text": "düşünüyorum"}]}}]}}

    data: {"response": {"candidates": [{"content": {"role": "model","parts": [{"text": "Görselin rengi kırmızı."}]}}]}}

    data: {"response": {"candidates": [{"content": {"role": "model","parts": [{"functionCall": {"name": "hava", "args": {"sehir": "İzmir"}, "id": "toolu_vrtx_1"}}]},"finishReason": "STOP"}],"usageMetadata": {"promptTokenCount": 401,"candidatesTokenCount": 88}}}


    """
}

func antigravityState() -> ProxyState {
    var s = sampleState()
    s.oauth.append(OAuthAccount(id: "m@gmail.com", provider: .antigravity, label: "m@gmail.com", accessToken: "ya29.AG", refreshToken: "1//RT",
                                expiresAt: Date().addingTimeInterval(3000), metadata: ["project": "aicode-consumers"], refreshOwner: .telefon))
    return s
}

@Suite struct AntigravityTests {
    @Test func govdeCevirisi() throws {
        let body = try JSON.parse(Data("""
        {"model":"antigravity-claude-opus-5-5","max_tokens":100,"system":"Kısa yaz",
         "messages":[{"role":"user","content":[{"type":"text","text":"Bak"},{"type":"image","source":{"type":"base64","media_type":"image/png","data":"QUJD"}}]},
          {"role":"assistant","content":[{"type":"text","text":"Bakıyorum"},{"type":"tool_use","id":"t1","name":"hava","input":{"sehir":"İzmir"}}]},
          {"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"22 derece"},{"type":"text","text":"Teşekkürler"}]}],
         "tools":[{"name":"hava","input_schema":{"$schema":"x","type":"object","additionalProperties":false,"properties":{"sehir":{"type":"string"}}}}]}
        """.utf8))
        let c = try Inbound.anthropic(body)
        let b = Antigravity.body(c, model: "claude-opus-5-5-high", thinking: nil, project: "aicode-consumers")
        #expect(b["project"] == "aicode-consumers" && b["model"] == "claude-opus-5-5-high" && b["userAgent"] == "antigravity")
        let req = b["request"]!
        #expect(req["systemInstruction"]?["parts"]?[0]?["text"] == "Kısa yaz")
        let contents = req["contents"]!.array!
        #expect(contents.map { $0["role"]?.string ?? "" } == ["user", "model", "user"])     // tool sonucu + metin tek user içeriği
        #expect(contents[0]["parts"]?[1]?["inlineData"]?["mimeType"] == "image/png")
        #expect(contents[1]["parts"]?[1]?["functionCall"]?["args"]?["sehir"] == "İzmir")
        #expect(contents[2]["parts"]?[0]?["functionResponse"]?["name"] == "hava")
        #expect(contents[2]["parts"]?[0]?["functionResponse"]?["id"] == "t1")
        #expect(contents[2]["parts"]?[1]?["text"] == "Teşekkürler")
        let params = req["tools"]?[0]?["functionDeclarations"]?[0]?["parameters"]
        #expect(params?["$schema"] == nil && params?["additionalProperties"] == nil && params?["type"] == "object")
        #expect(req["generationConfig"]?["maxOutputTokens"]?.int == 100)
        #expect(req["generationConfig"]?["thinkingConfig"] == nil)      // Claude modeline Gemini düşünme ayarı gitmez
    }

    @Test func geminiDusunmeDuzeyi() throws {
        let c = try Inbound.openAIChat(try JSON.parse(Data(#"{"model":"gemini-3.8-flash-low","messages":[{"role":"user","content":"x"}]}"#.utf8)))
        let t = try #require(Antigravity.target("gemini-3.8-flash-low"))
        let b = Antigravity.body(c, model: t.model, thinking: t.thinking, project: "p")
        #expect(b["model"] == "gemini-3.8-flash-tiered")
        #expect(b["request"]?["generationConfig"]?["thinkingConfig"]?["thinkingLevel"] == "low")
    }

    @Test func akisCozumu() throws {
        var p = SSEParser(); var d = GeminiDecoder(); var ev: [CEvent] = []
        for e in p.feed(Data(AGFixtures.sse.utf8)) { ev += try d.decode(e) }
        ev += d.end()
        #expect(ev.contains(.thinking("düşünüyorum")))
        #expect(ev.contains(.text("Görselin rengi kırmızı.")))
        #expect(ev.contains(.toolStart(index: 0, id: "toolu_vrtx_1", name: "hava")))
        #expect(ev.last == .finish(reason: "tool_calls", usage: CUsage(input: 401, output: 88)))
    }

    @Test func yonlendirme() {
        let withAG = ModelRouter(state: antigravityState())
        #expect(withAG.resolve("antigravity-claude-opus-5-5") == .antigravity(model: "claude-opus-5-5-high", thinking: nil))
        #expect(withAG.resolve("gemini-3.8-flash-medium") == .antigravity(model: "gemini-3.8-flash-tiered", thinking: "medium"))
        #expect(withAG.resolve("antigravity-gpt-oss-120b-medium") == .antigravity(model: "gpt-oss-120b-medium", thinking: nil))
        #expect(withAG.resolve("gemini-4-argon") == .remote)                 // Argon yalnız sunucudaki agy'de
        #expect(withAG.resolve("antigravity-gemini-image") == .remote)       // görsel üretim sunucuda
        #expect(withAG.localModels().map(\.id).contains("antigravity-claude-sonnet-5-5"))
        let without = ModelRouter(state: sampleState())
        #expect(without.resolve("antigravity-claude-opus-5-5") == .remote)    // hesap yoksa eskisi gibi sunucu
    }

    @Test func motorYoluVeTelefonYenilemesi() async throws {
        let t = MockTransport()
        t.on(urlContains: "oauth2.googleapis.com/token", body: #"{"access_token":"ya29.YENI","expires_in":3599}"#)
        t.onSSE(urlContains: "daily-cloudcode-pa.googleapis.com/v1internal:streamGenerateContent", AGFixtures.sse)
        var s = antigravityState()
        let i = s.oauth.firstIndex { $0.provider == .antigravity }!
        s.oauth[i].expiresAt = Date().addingTimeInterval(20)     // yenileme gereksin
        let e = try await makeEngine(s, t)
        let r = await e.handle(post("/v1/messages", #"{"model":"antigravity-claude-sonnet-5-5","max_tokens":50,"messages":[{"role":"user","content":"x"}]}"#))
        #expect(r.status == 200)
        let j = try JSON.parse(Data(try await collectString(r).utf8))
        #expect(j["content"]?[0]?["text"] == "Görselin rengi kırmızı.")
        #expect(j["content"]?[1]?["type"] == "tool_use")
        #expect(j["model"] == "antigravity-claude-sonnet-5-5")
        let tok = try #require(t.requests(containing: "oauth2.googleapis.com").first)
        let form = String(decoding: tok.httpBody ?? Data(), as: UTF8.self)
        #expect(form.contains("client_id=1071006060591") && form.contains("refresh_token=1//RT") || form.contains("refresh_token=1%2F%2FRT"))
        let up = try #require(t.requests(containing: "streamGenerateContent").first)
        #expect(up.value(forHTTPHeaderField: "Authorization") == "Bearer ya29.YENI")
        #expect(up.jsonBody["model"] == "claude-sonnet-5-5-high" && up.jsonBody["project"] == "aicode-consumers")
        #expect(await e.log.records.first?.route == "Antigravity (telefon)")
        #expect(t.requests(containing: "x/oauth-access").isEmpty)        // Antigravity sunucudan eşitlenmez
    }

    @Test func kotaDolunvaSunucuyaDuser() async throws {
        let t = MockTransport()
        t.on(urlContains: "streamGenerateContent", status: 429, body: #"{"error":{"code":429,"message":"Resource exhausted","status":"RESOURCE_EXHAUSTED"}}"#)
        t.on(urlContains: "sunucu.example/dersdas/claude/v1/chat/completions", body: #"{"choices":[{"message":{"content":"köprüden"}}]}"#)
        let e = try await makeEngine(antigravityState(), t)
        let r = await e.handle(post("/v1/chat/completions", #"{"model":"antigravity-claude-opus-5-5","messages":[{"role":"user","content":"x"}]}"#))
        #expect(try await collectString(r).contains("köprüden"))
    }

    @Test func paketteTelefonYeniler() throws {
        let json = #"{"surum":1,"oauth":[{"provider":"antigravity","id":"m@gmail.com","enabled":true,"access_token":"ya29","refresh_token":"1//x","expires_at":"2026-10-17T12:25:35.377111439+03:00","metadata":{"project":"aicode-consumers"}}],"api_anahtarlari":[]}"#
        var s = ProxyState()
        _ = BundleImporter.apply(try BundleImporter.decode(Data(json.utf8)), to: &s)
        #expect(s.oauth.first?.refreshOwner == .telefon)
        #expect(s.oauth.first?.expiresAt == BundleImporter.date("2026-10-17T09:25:35.377Z"))
    }
}

@Suite struct GeminiKrediIkameTests {
    @Test func krediBitinceAntigravityFlash() async throws {
        let t = MockTransport()
        t.on(urlContains: "googleapis.com/v1beta/openai/chat/completions", status: 402, body: #"[{"error":{"code":402,"message":"Your prepayment credits are depleted."}}]"#)
        t.onSSE(urlContains: "daily-cloudcode-pa.googleapis.com", AGFixtures.sse)
        let e = try await makeEngine(antigravityState(), t)
        let r = await e.handle(post("/v1/messages", #"{"model":"dersdas-gemini-ocr","max_tokens":50,"messages":[{"role":"user","content":"oku"}]}"#))
        #expect(r.status == 200)
        #expect(try await collectString(r).contains("kırmızı"))
        #expect(t.requests(containing: "daily-cloudcode-pa").first?.jsonBody["model"] == "gemini-3.8-flash-tiered")
        #expect(t.requests(containing: "sunucu.example").isEmpty)
    }

    @Test func ikameYalnizMetinFlash() {
        #expect(Antigravity.substitute(forGeminiModel: "gemini-3.8-flash")?.model == "gemini-3.8-flash-tiered")
        #expect(Antigravity.substitute(forGeminiModel: "gemini-3.1-flash-lite")?.model == "gemini-3.5-flash-lite")
        #expect(Antigravity.substitute(forGeminiModel: "gemini-3-pro-image") == nil)
        #expect(Antigravity.substitute(forGeminiModel: "gemini-3.8-flash-tts") == nil)
        #expect(Antigravity.substitute(forGeminiModel: "gemini-pro-latest") == nil)
    }

    @Test func antigravityYoksaEskiDavranis() async throws {
        let t = MockTransport()
        t.on(urlContains: "googleapis.com/v1beta/openai/chat/completions", status: 402, body: #"{"error":{"message":"credits depleted"}}"#)
        var s = sampleState(); s.remote.enabled = false
        let e = try await makeEngine(s, t)
        let r = await e.handle(post("/v1/chat/completions", #"{"model":"dersdas-gemini-ocr","messages":[{"role":"user","content":"x"}]}"#))
        #expect(r.status == 402)
    }
}
