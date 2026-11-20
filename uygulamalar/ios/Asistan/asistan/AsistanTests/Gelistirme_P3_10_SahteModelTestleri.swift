import Testing
import Foundation
@testable import Asistan

/// P3.10: hermetik test altyapısı — sahte senaryo, SSE üreticileri, HTTP ayrıştırıcısı ve yerel sahte model sunucusu.
/// Ağa (yalnız 127.0.0.1), izne ya da gerçek modele çıkmaz. Bütünleşik testler `SahteModelSunucusu.ortak`ı DEĞİL
/// kendi örneklerini kullanır: TelefonProxy.taban öbür testler için değişmez.
@Suite("P3.10 sahte model")
struct Gelistirme_P3_10_SahteModelTestleri {

    // MARK: SSE üreticileri

    @Test func openaiParcalariParcaCozIleOzgunMetniVerir() {
        let metin = "Fotosentez, bitkilerin ışık enerjisiyle besin üretmesidir. İkinci cümle burada."
        let satirlar = SahteSSE.openai(metin: metin, model: "gpt-6.1-sol")
            .flatMap { $0.components(separatedBy: "\n") }.filter { !$0.isEmpty }
        let birlesik = satirlar.compactMap(ParalelYaris.parcaCoz).joined()
        #expect(birlesik == metin)
        #expect(ParalelYaris.bitisMi(satirlar.last ?? ""))
        #expect(satirlar.contains { ParalelYaris.bitisMi($0) && $0 != "data: [DONE]" }, "finish_reason satırı da bitiş sayılmalı")
        #expect(satirlar.allSatisfy { ParalelYaris.hataMetni($0) == nil })
    }

    private func olaylar(_ cerceveler: [String]) -> [[String: Any]] {
        cerceveler.compactMap { c -> [String: Any]? in
            guard let satir = c.components(separatedBy: "\n").first(where: { $0.hasPrefix("data:") }) else { return nil }
            let yuk = satir.dropFirst(5).trimmingCharacters(in: .whitespaces)
            return (try? JSONSerialization.jsonObject(with: Data(yuk.utf8))) as? [String: Any]
        }
    }

    @Test func anthropicOlaySirasiVeMetin() {
        let metin = "Yedi artı beş on iki eder, yani 12."
        let cerceveler = SahteSSE.anthropic(metin: metin, model: "claude-sonnet-5-5")
        #expect(cerceveler.allSatisfy { $0.hasPrefix("event: ") && $0.hasSuffix("\n\n") })
        let o = olaylar(cerceveler)
        #expect(o.count == cerceveler.count, "her çerçevede geçerli JSON olmalı")
        let turler = o.compactMap { $0["type"] as? String }
        #expect(turler.first == "message_start")
        #expect(turler.last == "message_stop")
        #expect(Array(turler.prefix(2)) == ["message_start", "content_block_start"])
        #expect(Array(turler.suffix(3)) == ["content_block_stop", "message_delta", "message_stop"])
        #expect(turler.dropFirst(2).dropLast(3).allSatisfy { $0 == "content_block_delta" })
        let metinler = o.compactMap { ($0["delta"] as? [String: Any]).flatMap { $0["type"] as? String == "text_delta" ? $0["text"] as? String : nil } }
        #expect(metinler.joined() == metin)
        let delta = o.first { $0["type"] as? String == "message_delta" }?["delta"] as? [String: Any]
        #expect(delta?["stop_reason"] as? String == "end_turn")
        // İstemci message_start.message.usage.output_tokens ve message_delta.usage.output_tokens'ı zorunlu çözer.
        let bas = o.first?["message"] as? [String: Any]
        #expect((bas?["usage"] as? [String: Any])?["output_tokens"] != nil)
        #expect((o.first { $0["type"] as? String == "message_delta" }?["usage"] as? [String: Any])?["output_tokens"] != nil)
    }

    @Test func aracCagrisiParcalariGecerliJSONaBirlesir() throws {
        let girdi = #"{"islem":"ara","sorgu":"yedi artı beş"}"#
        let o = olaylar(SahteSSE.anthropicAracCagrisi(ad: "suankiSaat", girdiJSON: girdi))
        let blok = o.first { $0["type"] as? String == "content_block_start" }?["content_block"] as? [String: Any]
        #expect(blok?["type"] as? String == "tool_use")
        #expect(blok?["name"] as? String == "suankiSaat")
        let parcalar = o.compactMap { ($0["delta"] as? [String: Any]).flatMap { $0["type"] as? String == "input_json_delta" ? $0["partial_json"] as? String : nil } }
        #expect(parcalar.count >= 2, "girdi en az iki parçada gelmeli")
        let nesne = try #require(try JSONSerialization.jsonObject(with: Data(parcalar.joined().utf8)) as? [String: Any])
        #expect(nesne["islem"] as? String == "ara")
        #expect(nesne["sorgu"] as? String == "yedi artı beş")
        let delta = o.first { $0["type"] as? String == "message_delta" }?["delta"] as? [String: Any]
        #expect(delta?["stop_reason"] as? String == "tool_use")
    }

    @Test func hataGovdesiIkiBicimiDeTasir() throws {
        let n = try #require(try JSONSerialization.jsonObject(with: Data(SahteSSE.hata(durum: 429).utf8)) as? [String: Any])
        #expect(n["type"] as? String == "error")
        let e = n["error"] as? [String: Any]
        #expect(e?["type"] as? String == "rate_limit_error")
        #expect((e?["message"] as? String)?.isEmpty == false)
    }

    // MARK: HTTP ayrıştırıcısı

    @Test func ayristiriciEksikGovdedeNilTamdaIstek() throws {
        let govde = #"{"model":"claude-haiku-4-5","stream":true,"messages":[{"role":"user","content":"Merhaba"}]}"#
        let gb = Data(govde.utf8)
        let baslik = "POST /v1/chat/completions?x=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: \(gb.count)\r\n\r\n"
        var veri = Data(baslik.utf8)
        veri.append(gb.prefix(10))
        #expect(SahteHTTP.ayristir(veri) == nil, "gövde Content-Length kadar gelmeden istek tamam sayılmamalı")
        #expect(SahteHTTP.ayristir(Data("POST /v1/messages HTTP/1.1\r\nContent-Le".utf8)) == nil, "başlık bitmeden nil")
        veri.append(gb.dropFirst(10))
        let istek = try #require(SahteHTTP.ayristir(veri))
        #expect(istek.yontem == "POST")
        #expect(istek.yol == "/v1/chat/completions")
        #expect(istek.basliklar["content-type"] == "application/json")
        #expect(istek.govde == gb)
    }

    @Test func govdesizGetIstegi() throws {
        let istek = try #require(SahteHTTP.ayristir(Data("GET /v1/models HTTP/1.1\r\nHost: x\r\n\r\n".utf8)))
        #expect(istek.yontem == "GET")
        #expect(istek.yol == "/v1/models")
        #expect(istek.govde.isEmpty)
    }

    // MARK: Senaryo

    @Test func bozukJSONdaYerlesikSenaryo() {
        #expect(SahteSenaryo.ortamdan(["ASISTAN_SAHTE_SENARYO": "{bozuk"]) == .yerlesik)
        #expect(SahteSenaryo.ortamdan([:]) == .yerlesik)
        #expect(SahteSenaryo.ortamdan(["ASISTAN_SAHTE_SENARYO": "   "]) == .yerlesik)
    }

    @Test func kismiJSONYerlesikKurallariArkayaEkler() {
        let s = SahteSenaryo.ortamdan(["ASISTAN_SAHTE_SENARYO": #"{"kurallar":[{"icerir":"yedi artı beş","model":"claude-haiku-4-5","durum":429}]}"#])
        #expect(s.kurallar.count == SahteSenaryo.yerlesikKurallar.count + 1)
        #expect(s.modeller == SahteSenaryo.yerlesikModeller)
        #expect(s.kural(sonKullaniciMetni: "Yedi artı beş?", model: "claude-haiku-4-5").durum == 429)
        #expect(s.yanitMetni(s.kural(sonKullaniciMetni: "Yedi artı beş?", model: "gpt-6.1-sol")) == "12", "model süzgeci öbür modeli etkilememeli")
        // Kodla-çöz gidiş-dönüşü kuralları ikilemez.
        let tekrar = try? JSONDecoder().decode(SahteSenaryo.self, from: JSONEncoder().encode(s))
        #expect(tekrar == s)
    }

    @Test func turkceKatlamaylaKuralEslesir() {
        let s = SahteSenaryo.yerlesik
        #expect(s.yanitMetni(s.kural(sonKullaniciMetni: "YEDİ ARTI BEŞ kaç?")) == "12")
        #expect(s.yanitMetni(s.kural(sonKullaniciMetni: "yedi arti bes kac")) == "12")
        #expect(s.yanitMetni(s.kural(sonKullaniciMetni: "Bugün nasılsın?")) == "Sahte yanıt.")
        #expect(s.kural(sonKullaniciMetni: "Galatasaray'ın maçı").gecikmeMs == 3000)
    }

    @Test func baglamKuraliYalnizGecmisteVarsaUyar() {
        let s = SahteSenaryo.yerlesik
        #expect(s.yanitMetni(s.kural(sonKullaniciMetni: "Peki kaç yaşındaydı?")) == "Sahte yanıt.", "bağlam yokken bilmemeli")
        #expect(s.yanitMetni(s.kural(sonKullaniciMetni: "Peki kaç yaşındaydı?", gecmis: "Benim kedimin adı Pamuk ve 3 yaşında."))
                .contains("Bağlamdan: Pamuk"))
    }

    @Test func konusmaCozumuAnthropicVeOpenAI() {
        let anthropic: [String: Any] = ["system": "Kip: hikaye", "messages": [
            ["role": "user", "content": "Kedimin adı Pamuk."],
            ["role": "assistant", "content": [["type": "text", "text": "Tamam."]]],
            ["role": "user", "content": [["type": "text", "text": "Adı neydi?\n[Bu istek için uygulamanın seçtiği çalışma kipi: hikaye]"]]],
        ]]
        let a = SahteKonusma.coz(anthropic)
        #expect(a.son == "Adı neydi?", "arkaya eklenen bağlam blokları kurala girmez")
        #expect(a.gecmis.contains("Pamuk"))
        #expect(!a.aracSonucu)
        let arac: [String: Any] = ["messages": [["role": "user", "content": [["type": "tool_result", "tool_use_id": "x", "content": "ok"]]]]]
        #expect(SahteKonusma.coz(arac).aracSonucu)
        let openai: [String: Any] = ["messages": [["role": "system", "content": "fotosentez hakkında sistem"], ["role": "user", "content": "Merhaba"]]]
        let o = SahteKonusma.coz(openai)
        #expect(o.son == "Merhaba")
        #expect(!o.gecmis.contains("fotosentez"), "sistem satırı geçmiş sayılmaz")
    }

    @Test func hermetikBayraklarOlaganKosudaKapali() {
        // Birim testi barındırıcısı `--sahte-model` ile açılmaz: uygulamanın küresel yolu gerçek kalır.
        #expect(!SahteModelSunucusu.etkin)
        #expect(!HermetikKip.sahteModel)
        #expect(!HermetikKip.animasyonsuz)
    }

    // MARK: Bütünleşik (yalnız 127.0.0.1)

    @Test(.timeLimit(.minutes(1)))
    func yarisSahteSunucudanYanitAlir() async throws {
        let s = SahteModelSunucusu()
        let url = try await s.baslat(senaryo: .yerlesik)
        defer { s.durdur() }
        #expect(url.host() == "127.0.0.1")
        let bas = Date()
        let r = try await ParalelYaris.yaris(taban: url, anahtar: "sahte", modeller: ["claude-haiku-4-5"], sistem: "Kısa yanıtla.",
                                             mesajlar: [.init(rol: "user", metin: "Yedi artı beş kaç?")], ilkMetinSiniri: 5) { _, _ in }
        #expect(r.metin == "12")
        #expect(r.model == "claude-haiku-4-5")
        #expect(Date().timeIntervalSince(bas) < 5, "yerel sahte yanıt 5 sn içinde gelmeli")
        #expect(s.istekGunlugu.contains { $0.yol == "/v1/chat/completions" && $0.model == "claude-haiku-4-5" && $0.metin.hasPrefix("Yedi artı beş") })
        #expect(SahteModelSunucusu.ortak.tabanURL == nil, "ayrı örnek ortak tekili başlatmamalı")
    }

    @Test(.timeLimit(.minutes(1)))
    func kotaHatasindaIkinciModelKazanir() async throws {
        let senaryo = SahteSenaryo.ortamdan(["ASISTAN_SAHTE_SENARYO": #"{"kurallar":[{"icerir":"yedi","model":"claude-haiku-4-5","durum":429}]}"#])
        let s = SahteModelSunucusu()
        let url = try await s.baslat(senaryo: senaryo)
        defer { s.durdur() }
        let r = try await ParalelYaris.yaris(taban: url, anahtar: "sahte", modeller: ["claude-haiku-4-5", "gpt-6.1-sol"], sistem: "",
                                             mesajlar: [.init(rol: "user", metin: "Yedi artı beş kaç?")], ilkMetinSiniri: 5) { _, _ in }
        #expect(r.model == "gpt-6.1-sol")
        #expect(r.metin == "12")
        // Tek model 429'daysa yarış hata verir (çağıran yedek yola düşer).
        await #expect(throws: (any Error).self) {
            _ = try await ParalelYaris.yaris(taban: url, anahtar: "sahte", modeller: ["claude-haiku-4-5"], sistem: "",
                                             mesajlar: [.init(rol: "user", metin: "Yedi artı beş kaç?")], ilkMetinSiniri: 5) { _, _ in }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func modellerVeBilinmeyenYol() async throws {
        let s = SahteModelSunucusu()
        let url = try await s.baslat(senaryo: .yerlesik)
        defer { s.durdur() }
        let oturum = URLSession(configuration: .ephemeral)
        defer { oturum.invalidateAndCancel() }
        let (veri, yanit) = try await oturum.data(from: url.appending(path: "v1/models"))
        #expect((yanit as? HTTPURLResponse)?.statusCode == 200)
        let n = try #require(try JSONSerialization.jsonObject(with: veri) as? [String: Any])
        let kimlikler = ((n["data"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
        #expect(kimlikler.contains("claude-opus-5-5"))
        #expect(Set(ParalelYaris.antigravityModeller).isSubset(of: Set(kimlikler)))
        var r = URLRequest(url: url.appending(path: "v1/responses")); r.httpMethod = "POST"; r.httpBody = Data("{}".utf8)
        let (_, y2) = try await oturum.data(for: r)
        #expect((y2 as? HTTPURLResponse)?.statusCode == 404)
    }

    @Test(.timeLimit(.minutes(1)))
    func claudeIstemcisiAkisiOkur() async throws {
        let s = SahteModelSunucusu()
        let url = try await s.baslat(senaryo: .yerlesik)
        defer { s.durdur() }
        let metin = try await SahteModelSinama.claudeAkisi(taban: url, istem: "Yedi artı beş kaç eder?")
        #expect(metin.contains("12"))
        #expect(s.istekGunlugu.contains { $0.yol == "/v1/messages" })
    }
}
