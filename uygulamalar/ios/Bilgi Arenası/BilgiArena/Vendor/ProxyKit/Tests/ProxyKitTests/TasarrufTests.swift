import Foundation
import Testing
@testable import ProxyKit

@Suite struct TasarrufTests {
    static func uzun(_ n: Int) -> String { String(repeating: "Türkçe uzun sistem talimatı satırı. ", count: n) }

    @Test func promptOnbellegiKesmeNoktalariEkler() throws {
        let b: JSON = ["model": "claude-opus-5-5", "system": .string(Self.uzun(150)),
                       "tools": [["name": "a", "input_schema": ["type": "object"]], ["name": "b", "description": .string(Self.uzun(120)), "input_schema": ["type": "object"]]],
                       "messages": [["role": "user", "content": "merhaba"]]]
        let (y, n) = PromptOnbellegi.uygula(b)
        #expect(n == 3)
        #expect(y["system"]?[0]?["cache_control"]?["type"] == "ephemeral", "sistem dizeden bloğa çevrilip işaretlenir")
        #expect(y["tools"]?[1]?["cache_control"] != nil && y["tools"]?[0]?["cache_control"] == nil, "yalnız son araç")
        #expect(y["messages"]?[0]?["content"]?[0]?["cache_control"] != nil && y["messages"]?[0]?["content"]?[0]?["text"] == "merhaba")
    }
    @Test func kisaIstekVeMevcutIsaretDegismez() {
        let kisa: JSON = ["model": "x", "system": "kısa", "messages": [["role": "user", "content": "selam"]]]
        #expect(PromptOnbellegi.uygula(kisa).1 == 0)
        let var_: JSON = ["system": [["type": "text", "text": .string(Self.uzun(200)), "cache_control": ["type": "ephemeral"]]], "messages": [["role": "user", "content": "x"]]]
        #expect(PromptOnbellegi.uygula(var_).1 == 0, "istemci kendi işaretini koyduysa dokunulmaz")
        let bos: JSON = ["system": .string(Self.uzun(200)), "messages": []]
        #expect(PromptOnbellegi.uygula(bos).1 == 0)
    }
    @Test func dusunmeBloguIsaretlenmez() {
        let b: JSON = ["system": .string(Self.uzun(200)), "messages": [["role": "assistant", "content": [["type": "thinking", "thinking": "..."], ["type": "text", "text": .string(Self.uzun(30))]]]]]
        let (y, _) = PromptOnbellegi.uygula(b)
        #expect(y["messages"]?[0]?["content"]?[0]?["cache_control"] == nil && y["messages"]?[0]?["content"]?[1]?["cache_control"] != nil)
    }
    @Test func onbellekAnahtariSiraDegisseAyni() {
        let a = YanitOnbellegi.anahtar(path: "/v1/messages", body: Data(#"{"model":"m","temperature":0,"x":1}"#.utf8))
        let b = YanitOnbellegi.anahtar(path: "/v1/messages", body: Data(#"{"x":1,"temperature":0,"model":"m"}"#.utf8))
        let c = YanitOnbellegi.anahtar(path: "/v1/messages", body: Data(#"{"x":2,"temperature":0,"model":"m"}"#.utf8))
        #expect(a == b && a != c)
    }
    @Test func onbellekUygunlugu() {
        #expect(YanitOnbellegi.uygun(["temperature": 0], istekBasligi: nil))
        #expect(!YanitOnbellegi.uygun(["temperature": 0.7], istekBasligi: nil))
        #expect(!YanitOnbellegi.uygun([:], istekBasligi: nil), "sıcaklık yoksa yeniden üretim bozulmasın")
        #expect(YanitOnbellegi.uygun([:], istekBasligi: "1") && !YanitOnbellegi.uygun(["temperature": 0], istekBasligi: "no"))
    }
    @Test func kotaBasliklarindanDoluluk() {
        let h = KotaDurumu.coz(["anthropic-ratelimit-unified-5h-utilization": "0.42", "anthropic-ratelimit-unified-7d-utilization": "0.91", "content-type": "x"])
        #expect(h.doluluk == 0.91 && h.basliklar.count == 2)
        let c = KotaDurumu.coz(["x-codex-primary-used-percent": "97.5", "x-codex-primary-reset-after-seconds": "3600"])
        #expect(c.doluluk == 0.975 && c.sifirlanma != nil)
        let k = KotaDurumu.coz(["anthropic-ratelimit-requests-limit": "100", "anthropic-ratelimit-requests-remaining": "5"])
        #expect(abs((k.doluluk ?? 0) - 0.95) < 0.001)
    }
    @Test func gunlukButceYalnizBugunuSayar() {
        var d = UsageRecord(path: "/v1/messages", model: "m", route: "r", status: 200, millis: 1, inputTokens: 100, outputTokens: 50)
        var dun = d; dun.date = Date().addingTimeInterval(-86400 * 2)
        var hata = d; hata.status = 500
        #expect(GunlukButce.kullanilan([d, dun, hata]) == 150)
        d.status = 200
    }

    @Test func ayniIstekOnbellektenGelirUpstreamBirKez() async throws {
        let t = MockTransport()
        t.onSSE(urlContains: "api.anthropic.com/v1/messages", Fixtures.anthropicSSE)
        let e = try await makeEngine(sampleState(), t)
        let govde = #"{"model":"claude-opus-5-5","temperature":0,"messages":[{"role":"user","content":"selam"}]}"#
        let r1 = await e.handle(post("/v1/chat/completions", govde))
        let s1 = try await collectString(r1)
        try await Task.sleep(for: .milliseconds(100))
        let r2 = await e.handle(post("/v1/chat/completions", govde))
        let s2 = try await collectString(r2)
        #expect(r1.headers["X-Proxy-Cache"] == "MISS" && r2.headers["X-Proxy-Cache"] == "HIT")
        #expect(s1 == s2 && t.requests(containing: "anthropic.com").count == 1)
        let d = await e.tasarrufDurumu()
        #expect(d.sayaclar.onbellekIsabeti == 1 && d.sayaclar.tasarrufEdilenToken > 0)
    }
    @Test func sicaklikYoksaOnbellekYok() async throws {
        let t = MockTransport()
        t.onSSE(urlContains: "api.anthropic.com/v1/messages", Fixtures.anthropicSSE)
        let e = try await makeEngine(sampleState(), t)
        let govde = #"{"model":"claude-opus-5-5","messages":[{"role":"user","content":"selam"}]}"#
        _ = try await collectString(await e.handle(post("/v1/chat/completions", govde)))
        _ = try await collectString(await e.handle(post("/v1/chat/completions", govde)))
        #expect(t.requests(containing: "anthropic.com").count == 2)
    }
    @Test func gunlukButceAsilincaReddeder() async throws {
        let t = MockTransport()
        t.onSSE(urlContains: "api.anthropic.com/v1/messages", Fixtures.anthropicSSE)
        var s = sampleState()
        var ayar = TasarrufAyarlari(); ayar.gunlukTokenSiniri = 10; s.tasarruf = ayar
        let e = try await makeEngine(s, t)
        let govde = #"{"model":"claude-opus-5-5","messages":[{"role":"user","content":"selam"}]}"#
        let r1 = await e.handle(post("/v1/chat/completions", govde)); _ = try await collectString(r1)
        try await Task.sleep(for: .milliseconds(150))   // kullanım kaydı akış bitince yazılır
        let r2 = await e.handle(post("/v1/chat/completions", govde))
        #expect(r1.status == 200 && r2.status == 429)
        #expect(try await collectString(r2).contains("Günlük token bütçesi"))
    }
    @Test func claudeGovdesineOnbellekIsaretiGider() async throws {
        let t = MockTransport()
        t.onSSE(urlContains: "api.anthropic.com/v1/messages", Fixtures.anthropicSSE)
        let e = try await makeEngine(sampleState(), t)
        let sistem = Self.uzun(150).replacingOccurrences(of: "\"", with: "")
        _ = try await collectString(await e.handle(post("/v1/messages", #"{"model":"claude-opus-5-5","max_tokens":50,"system":"\#(sistem)","messages":[{"role":"user","content":"selam"}]}"#)))
        let up = t.requests(containing: "anthropic.com").first!
        let sys = up.jsonBody["system"]?.array ?? []
        #expect(sys.contains { $0["cache_control"] != nil }, "upstream'e giden sistem istemi işaretlenmiş olmalı")
    }
    @Test func konusmaAnahtariSonrakiTurdaDegismez() {
        let a: JSON = ["model": "m", "system": "S", "messages": [["role": "user", "content": "ilk"]]]
        let b: JSON = ["model": "m", "system": "S", "messages": [["role": "user", "content": "ilk"], ["role": "assistant", "content": "ok"], ["role": "user", "content": "ikinci"]]]
        let c: JSON = ["model": "m", "system": "S", "messages": [["role": "user", "content": "başka konuşma"]]]
        #expect(ProxyEngine.konusmaAnahtari(a) == ProxyEngine.konusmaAnahtari(b) && ProxyEngine.konusmaAnahtari(a) != ProxyEngine.konusmaAnahtari(c))
    }
}

@Suite struct TasarrufKayitTests {
    @Test func ayarlarKasadaSaklanirEskiKayitVarsayilanAlir() throws {
        var s = ProxyState(); var a = TasarrufAyarlari(); a.gunlukTokenSiniri = 123; a.yanitOnbellegi = false; s.tasarruf = a
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let geri = ProxyState.decode(try enc.encode(s))
        #expect(geri?.tasarruf.gunlukTokenSiniri == 123 && geri?.tasarruf.yanitOnbellegi == false)
        let eski = ProxyState.decode(Data(#"{"oauth":[],"apiProviders":[],"clientKeys":[]}"#.utf8))
        #expect(eski?.tasarruf == TasarrufAyarlari(), "alanı olmayan eski kayıt varsayılan alır")
    }
}

@Suite struct TasarrufIkinciTurTests {
    @Test func aracCiktisiKirpmaKararliVeSonMesajlariKorur() {
        let uzun = String(repeating: "satır içeriği\n", count: 800)
        func tur(_ i: Int) -> [JSON] { [["role": "assistant", "content": [["type": "tool_use", "id": .string("t\(i)"), "name": "oku", "input": [:]]]],
                                         ["role": "user", "content": [["type": "tool_result", "tool_use_id": .string("t\(i)"), "content": .string(uzun)]]]] }
        let b: JSON = ["messages": .array(([["role": "user", "content": "başla"]] as [JSON]) + tur(1) + tur(2) + tur(3))]
        let (y, n) = AracCiktisiKirpici.uygula(b)
        #expect(n == 1, "son 4 mesajdan öncekiler kısalır (yalnız ilk sonuç), sonuncular korunur")
        let ilk = y["messages"]?[2]?["content"]?[0]?["content"]?.string ?? ""
        #expect(ilk.count < uzun.count && ilk.contains("karakter kırpıldı") && ilk.hasPrefix("satır içeriği"))
        #expect(y["messages"]?[4]?["content"]?[0]?["content"]?.string == .some(uzun) && y["messages"]?[6]?["content"]?[0]?["content"]?.string == .some(uzun), "korunan sonuçlar aynen")
        #expect(AracCiktisiKirpici.uygula(y).0 == y || AracCiktisiKirpici.uygula(y).1 == 0, "ikinci geçiş aynı çıktıyı verir (kararlı)")
        #expect(y["messages"]?[1]?["content"]?[0]?["tool_use_id"] == "t1" || y["messages"]?[2]?["content"]?[0]?["tool_use_id"] == "t1")
    }
    @Test func harcamaSiniriAyrimiVeAlanReddi() {
        #expect(UpstreamYardimci.harcamaSiniri("You have reached your specified API usage limits: enforced_spend_limit_reached"))
        #expect(UpstreamYardimci.harcamaSiniri("{\"type\":\"usage_limit_reached\"}"))
        #expect(!UpstreamYardimci.harcamaSiniri("Number of request tokens has exceeded your per-minute rate limit"))
        #expect(UpstreamYardimci.alanReddi(400, "Unknown parameter: 'prompt_cache_key'."))
        #expect(!UpstreamYardimci.alanReddi(400, "model not found") && !UpstreamYardimci.alanReddi(429, "prompt_cache_key"))
        let b = UpstreamYardimci.onbellekAnahtariEkle(["model": "x"], anahtar: "abcdefghijklmnopqrstuvwxyz0123456789")
        #expect(b["prompt_cache_key"]?.string?.hasPrefix("cp-") == true)
        #expect(UpstreamYardimci.onbellekAnahtariEkle(["prompt_cache_key": "kendi"], anahtar: "x")["prompt_cache_key"] == "kendi")
    }
    @Test func modelDuzeyindeSogumaDigerModeliEtkilemez() async throws {
        let e = try await makeEngine(sampleState(), MockTransport())
        let a = try await e.tokens.pick(.claude)
        await e.tokens.coolDown(a, model: "claude-opus-5-5", taban: 60)
        #expect(await e.tokens.modelSoguma(a, model: "claude-opus-5-5") > 30)
        #expect(await e.tokens.modelSoguma(a, model: "claude-haiku-4-5") == 0)
        // tek hesap olduğundan havuz boş kalsa da seçim hata vermez (en az kötü seçenek)
        _ = try await e.tokens.pick(.claude, model: "claude-opus-5-5")
        await e.tokens.coolDown(a, model: "claude-opus-5-5", taban: 60)
        #expect(await e.tokens.modelSoguma(a, model: "claude-opus-5-5") > 90, "ardışık hata → üstel artış")
        await e.tokens.basarili(a)
    }
    @Test func birBitirStratejisiIlkHazirHesabiSecer() async throws {
        var s = sampleState()
        s.oauth.append(OAuthAccount(id: "ikinci", provider: .claude, label: "Yedek", accessToken: "sk-ant-oat01-Y", refreshToken: "r", expiresAt: Date().addingTimeInterval(3600), refreshOwner: .telefon))
        var ayar = TasarrufAyarlari(); ayar.hesapStratejisi = .birBitir; s.tasarruf = ayar
        let e = try await makeEngine(s, MockTransport())
        let a1 = try await e.tokens.pick(.claude), a2 = try await e.tokens.pick(.claude)
        #expect(a1.id == "claude-default" && a2.id == "claude-default", "round-robin değil: aynı hesap")
        await e.tokens.coolDown(a1, seconds: 60)
        #expect(try await e.tokens.pick(.claude).id == "ikinci", "soğuyunca sıradaki hesap")
    }
    @Test func openAIIstegineOnbellekAnahtariEklenirReddedilinceCikar() async throws {
        let t = MockTransport()
        t.on { r in
            guard r.url?.absoluteString.contains("api.openai.com") == true else { return nil }
            if r.jsonBody["prompt_cache_key"] != nil {
                return .fixed(status: 400, headers: ["Content-Type": "application/json"], data: Data(#"{"error":{"message":"Unknown parameter: 'prompt_cache_key'."}}"#.utf8))
            }
            return .fixed(status: 200, headers: ["Content-Type": "application/json"], data: Data(#"{"choices":[{"message":{"role":"assistant","content":"tamam"}}],"usage":{"prompt_tokens":3,"completion_tokens":1}}"#.utf8))
        }
        let e = try await makeEngine(sampleState(), t)
        let r = await e.handle(post("/v1/chat/completions", #"{"model":"gpt-6.1-sol","messages":[{"role":"user","content":"selam"}]}"#))
        #expect(r.status == 200)
        let istekler = t.requests(containing: "api.openai.com")
        #expect(istekler.count == 2 && istekler[0].jsonBody["prompt_cache_key"] != nil && istekler[1].jsonBody["prompt_cache_key"] == nil, "alan reddedilince çıkarılıp yeniden denendi")
    }
    @Test func eskiKayitVeYeniAlanlarKasada() throws {
        var s = ProxyState(); var a = TasarrufAyarlari(); a.hesapStratejisi = .birBitir; a.aracCiktisiKirpma = true; a.openAIOnbellekAnahtari = false; s.tasarruf = a
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let g = ProxyState.decode(try enc.encode(s))
        #expect(g?.tasarruf.strateji == .birBitir && g?.tasarruf.kirpmaAcik == true && g?.tasarruf.openAIAnahtariAcik == false)
        #expect(TasarrufAyarlari().strateji == .sirayla && !TasarrufAyarlari().kirpmaAcik && TasarrufAyarlari().openAIAnahtariAcik, "varsayılanlar")
    }
}
