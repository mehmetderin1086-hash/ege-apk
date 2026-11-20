import Foundation
import Network
import Testing
@testable import ProxyKit

/// Kod incelemesinde çıkan bulguların regresyon testleri
@Suite(.serialized) struct ReviewRegressionTests {
    @Test func negatifUzunlukCokertmez() async throws {
        let e = try await makeEngine(sampleState(), MockTransport())
        let server = LocalHTTPServer(engine: e)
        let port = UInt16.random(in: 60001...62000)
        try server.start(port: port, lan: false)
        defer { server.stop() }
        for _ in 0..<50 { if case .running = server.state { break }; try await Task.sleep(for: .milliseconds(20)) }
        for raw in ["POST /v1/models HTTP/1.1\r\nContent-Length: -5\r\n\r\n",
                    "POST /v1/models HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n-1\r\nab\r\n0\r\n\r\n",
                    "POST /v1/models HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n7FFFFFFFFFFFFFFF\r\nab\r\n"] {
            let reply = try await rawRequest(port: port, raw)
            #expect(reply.hasPrefix("HTTP/1.1 400"), "yanıt: \(reply.prefix(40))")
        }
    }

    func rawRequest(port: UInt16, _ text: String) async throws -> String {
        let c = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        c.start(queue: .global())
        try await c.sendData(Data(text.utf8))
        var out = Data()
        while let d = try await c.receiveChunk() { out.append(d); if out.count > 10 { break } }
        c.cancel()
        return String(decoding: out, as: UTF8.self)
    }

    @Test func yenidenIceAktarmaTelefonBelirteciniKorur() throws {
        let b = try BundleImporter.decode(Data(BundleTests.sample.utf8))
        var s = ProxyState()
        _ = BundleImporter.apply(b, to: &s)
        let i = s.oauth.firstIndex { $0.provider == .claude }!
        s.oauth[i].refreshOwner = .telefon
        s.oauth[i].accessToken = "TELEFON-AT"; s.oauth[i].refreshToken = "TELEFON-RT"; s.oauth[i].enabled = false
        _ = BundleImporter.apply(b, to: &s)
        let c = s.oauth.first { $0.provider == .claude }!
        #expect(c.accessToken == "TELEFON-AT" && c.refreshToken == "TELEFON-RT" && !c.enabled)
    }

    @Test func dortYuzBirAyniHesabiZorlaYeniler() async throws {
        let t = MockTransport()
        var s = sampleState(claudeOwner: .telefon)
        s.oauth.append(OAuthAccount(id: "ikinci", provider: .claude, label: "Y", accessToken: "Y-AT", refreshToken: "Y-RT",
                                    expiresAt: Date().addingTimeInterval(3600), refreshOwner: .telefon))
        t.on(urlContains: "oauth/token", body: #"{"access_token":"X-YENI","refresh_token":"X-RT2","expires_in":3600}"#)
        t.on { r in
            guard r.url?.host == "api.anthropic.com" else { return nil }
            let ok = r.value(forHTTPHeaderField: "Authorization") == "Bearer X-YENI"
            return ok ? .fixed(status: 200, data: Data(#"{"type":"message","content":[],"usage":{"input_tokens":1,"output_tokens":1}}"#.utf8))
                      : .fixed(status: 401, data: Data(#"{"type":"error","error":{"type":"authentication_error","message":"expired"}}"#.utf8))
        }
        let e = try await makeEngine(s, t)
        let r = await e.handle(post("/v1/messages", #"{"model":"claude-opus-5-5","max_tokens":5,"messages":[{"role":"user","content":"x"}]}"#))
        #expect(r.status == 200)
        let tok = t.requests(containing: "oauth/token")
        #expect(tok.count == 1)
        #expect(tok.first?.jsonBody["refresh_token"] == "sk-ant-ort01-R")   // 401 alan hesabın (X) belirteci, Y değil
    }

    @Test func yenilemeHatasiOburHesabiDener() async throws {
        let t = MockTransport()
        var s = sampleState(claudeOwner: .telefon, expires: Date().addingTimeInterval(10))
        s.oauth.append(OAuthAccount(id: "ikinci", provider: .claude, label: "Y", accessToken: "Y-AT", refreshToken: "Y-RT",
                                    expiresAt: Date().addingTimeInterval(3600), refreshOwner: .telefon))
        t.on(urlContains: "oauth/token", status: 400, body: #"{"error":"invalid_grant"}"#)
        t.onSSE(urlContains: "api.anthropic.com", Fixtures.anthropicSSE)
        var st = s; st.remote.enabled = false
        let e = try await makeEngine(st, t)
        let r = await e.handle(post("/v1/chat/completions", #"{"model":"claude-opus-5-5","messages":[{"role":"user","content":"x"}]}"#))
        #expect(r.status == 200)
        #expect(t.requests(containing: "anthropic.com").last?.value(forHTTPHeaderField: "Authorization") == "Bearer Y-AT")
    }

    @Test func akissizAkisIciHataSunucuyaDuser() async throws {
        let t = MockTransport()
        t.onSSE(urlContains: "api.anthropic.com", "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"usage\":{}}}\n\nevent: error\ndata: {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"Overloaded\"}}\n\n")
        t.on(urlContains: "sunucu.example/dersdas/claude/v1/chat/completions", body: #"{"choices":[{"message":{"content":"sunucudan"}}]}"#)
        let e = try await makeEngine(sampleState(), t)
        let r = await e.handle(post("/v1/chat/completions", #"{"model":"claude-opus-5-5","messages":[{"role":"user","content":"x"}]}"#))
        #expect(r.status == 200)
        #expect(try await collectString(r).contains("sunucudan"))
    }

    @Test func sunucuHatasiIkinciKezGonderilmez() async throws {
        let t = MockTransport()   // sunucuya bağlantı yok → URLError
        let e = try await makeEngine(sampleState(), t)
        let r = await e.handle(post("/v1/chat/completions", #"{"model":"gemini-4-argon","messages":[]}"#))
        #expect(r.status == 502)
        #expect(t.requests(containing: "sunucu.example").count == 1)
    }

    @Test func cozulemeyenKasaYazmayaKilitlenir() async throws {
        let store = MemorySecretStore(Data(#"{"oauth":"bozuk"}"#.utf8))
        let v = Vault(store: store)
        #expect(await v.lockedReason != nil)
        await #expect(throws: StoreError.self) { try await v.update { $0.localKey = "x" } }
        #expect(try store.load() == Data(#"{"oauth":"bozuk"}"#.utf8))   // gerçek kayıt ezilmedi
    }

    @Test func eksikAlanliEskiKayitCozulur() throws {
        let old = #"{"oauth":[{"id":"a","provider":"claude","accessToken":"t"}],"localKey":"k"}"#
        let s = try #require(ProxyState.decode(Data(old.utf8)))
        #expect(s.localKey == "k" && s.oauth.first?.refreshOwner == .sunucu && s.remote.fallbackOnError)
    }

    @Test func buyukSayiCokertmez() throws {
        let j = try JSON.parse(Data(#"{"a":1e300,"b":-1e20,"c":42}"#.utf8))
        #expect(j["a"]?.int == nil && j["b"]?.int == nil && j["c"]?.int == 42)
    }

    @Test func indekssizAracCagrilari() throws {
        var d = OpenAIChatDecoder()
        let ev = try d.decode(SSEEvent(event: nil, data: #"{"choices":[{"delta":{"tool_calls":[{"id":"c1","function":{"name":"a","arguments":"{\"x\":1}"}},{"id":"c2","function":{"name":"b","arguments":"{\"y\":2}"}}]}}]}"#))
        var agg = Aggregate(); ev.forEach { agg.add($0) }
        #expect(agg.tools.count == 2)
        #expect(agg.tools[1].name == "b" && agg.tools[1].args == #"{"y":2}"#)
    }

    @Test func saatDilimsizTarih() {
        let d = BundleImporter.date("2026-10-17T14:33:16.110008")
        #expect(d == BundleImporter.date("2026-10-17T14:33:16.110Z"))
        #expect(d != nil)
    }
}
