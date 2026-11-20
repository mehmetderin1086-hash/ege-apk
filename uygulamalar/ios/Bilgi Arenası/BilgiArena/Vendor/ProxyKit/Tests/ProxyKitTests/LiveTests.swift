import Foundation
import Testing
@testable import ProxyKit

/// Gerçek hesaplarla canlı sınama. Yalnız CLIPROXY_CANLI_PAKET ortam değişkeni bir paket dosyasını gösteriyorsa çalışır.
/// Hesaplar "sunucu yeniler" kipinde kalır: bu test hiçbir yenileme belirtecini kullanmaz.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CLIPROXY_CANLI_PAKET"] != nil))
struct LiveTests {
    static func engine() async throws -> ProxyEngine {
        let path = ProcessInfo.processInfo.environment["CLIPROXY_CANLI_PAKET"]!
        let b = try BundleImporter.decode(try Data(contentsOf: URL(fileURLWithPath: path)))
        var s = ProxyState()
        _ = BundleImporter.apply(b, to: &s)
        s.localKey = "canli"
        s.remote.fallbackOnError = false        // telefondaki yolun kendisini ölç
        #expect(s.oauth.filter { $0.provider.rotatesRefreshToken }.allSatisfy { $0.refreshOwner == .sunucu })
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        return ProxyEngine(vault: Vault(store: MemorySecretStore(try enc.encode(s))))
    }

    /// Hesabın kendi durumu (kullanım sınırı, kredi bitti): yol çalışıyor, upstream reddediyor.
    func accountState(_ s: String) -> Bool { s.contains("usage limit") || s.contains("prepayment credits") }

    func call(_ e: ProxyEngine, _ path: String, _ body: String) async throws -> (Int, String, UsageRecord?) {
        let t0 = Date()
        let r = await e.handle(ProxyRequest(method: "POST", path: path, headers: ["authorization": "Bearer canli", "content-type": "application/json"], body: Data(body.utf8)))
        let s = try await collectString(r)
        try await Task.sleep(for: .milliseconds(100))
        let rec = await e.log.records.first
        print("CANLI \(path) → \(r.status) \(Int(Date().timeIntervalSince(t0) * 1000)) ms yol=\(rec?.route ?? "-") çıktı=\(s.prefix(160).replacingOccurrences(of: "\n", with: " "))")
        return (r.status, s, rec)
    }

    @Test func sunucuEsitleme() async throws {
        let e = try await Self.engine()
        try await e.tokens.syncFromServer(force: true)
        let st = await e.vault.state
        let claude = try #require(st.oauth.first { $0.provider == .claude })
        #expect(!claude.expiresSoon(within: 300))
    }

    @Test func claudeOpenAI() async throws {
        let e = try await Self.engine()
        let (st, s, rec) = try await call(e, "/v1/chat/completions", #"{"model":"claude-haiku-4-5","max_tokens":30,"messages":[{"role":"user","content":"Sadece 'tamam' yaz."}]}"#)
        #expect(st == 200)
        #expect(s.lowercased().contains("tamam"))
        #expect(rec?.route == "Claude (telefon)")
    }

    @Test func claudeAnthropicAkis() async throws {
        let e = try await Self.engine()
        let (st, s, _) = try await call(e, "/v1/messages", #"{"model":"claude-sonnet-5-5","max_tokens":40,"stream":true,"messages":[{"role":"user","content":"1'den 3'e kadar say."}]}"#)
        #expect(st == 200)
        #expect(s.contains("message_stop"))
    }

    @Test func codexAnthropic() async throws {
        let e = try await Self.engine()
        let (st, s, rec) = try await call(e, "/v1/messages", #"{"model":"gpt-6-astra","max_tokens":50,"messages":[{"role":"user","content":"Sadece 'evet' yaz."}]}"#)
        #expect(st == 200 && s.lowercased().contains("evet") || accountState(s))
        #expect(rec?.route == "Codex (telefon)")
    }

    @Test func codexOpenAIAkis() async throws {
        let e = try await Self.engine()
        let (st, s, _) = try await call(e, "/v1/chat/completions", #"{"model":"gpt-6-astra","stream":true,"messages":[{"role":"system","content":"Türkçe yanıt ver."},{"role":"user","content":"Merhaba de."}]}"#)
        #expect(st == 200 && s.contains("[DONE]") || accountState(s))
    }

    @Test func geminiTakmaAd() async throws {
        let e = try await Self.engine()
        let (st, s, rec) = try await call(e, "/v1/messages", #"{"model":"dersdas-gemini-ocr","max_tokens":50,"messages":[{"role":"user","content":"Sadece 'hazır' yaz."}]}"#)
        #expect(st == 200 && s.lowercased().contains("haz") || accountState(s))
        #expect(!s.contains("dersdas-gemini-ocr is not found"))     // takma ad çevrildi
        #expect(rec?.route == "gemini-script (telefon)")
    }

    @Test func sunucuyaOzelModel() async throws {
        let e = try await Self.engine()
        let (st, s, rec) = try await call(e, "/v1/chat/completions", #"{"model":"gemini-4-argon-low","max_tokens":30,"messages":[{"role":"user","content":"Sadece 'ok' yaz."}]}"#)
        #expect(st == 200)
        #expect(s.lowercased().contains("ok"))
        #expect(rec?.route == "Sunucu")
    }

    @Test func antigravityClaude() async throws {
        let e = try await Self.engine()
        let (st, s, rec) = try await call(e, "/v1/messages", #"{"model":"antigravity-claude-opus-5-5","max_tokens":40,"messages":[{"role":"user","content":"Sadece 'tamam' yaz."}]}"#)
        #expect(st == 200 && s.lowercased().contains("tamam"))
        #expect(rec?.route == "Antigravity (telefon)")
    }

    @Test func antigravityGeminiAkis() async throws {
        let e = try await Self.engine()
        let (st, s, rec) = try await call(e, "/v1/chat/completions", #"{"model":"gemini-3.8-flash-low","stream":true,"messages":[{"role":"system","content":"Büyük harfle yaz."},{"role":"user","content":"Başkent?"}]}"#)
        #expect(st == 200 && s.contains("[DONE]") && s.contains("ANKARA"))
        #expect(rec?.route == "Antigravity (telefon)")
    }

    @Test func antigravityYenileme() async throws {
        let e = try await Self.engine()
        let a = try #require(await e.vault.state.oauth.first { $0.provider == .antigravity })
        let f = try await e.tokens.fresh(a, force: true)
        #expect(f.accessToken != a.accessToken && f.refreshToken == a.refreshToken && !f.expiresSoon(within: 3000))
    }

    @Test func modelListesi() async throws {
        let e = try await Self.engine()
        let r = await e.handle(ProxyRequest(method: "GET", path: "/v1/models", headers: ["authorization": "Bearer canli"]))
        let ids = (try JSON.parse(Data(try await collectString(r).utf8)))["data"]!.array!.compactMap { $0["id"]?.string }
        print("CANLI modeller: \(ids.count) → \(ids.prefix(12))")
        #expect(ids.contains("claude-opus-5-5") && ids.contains("gemini-4-argon"))
    }
}
