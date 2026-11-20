import Foundation
import FoundationModels
import Testing
@testable import Asistan

/// P3.1: Live motorlarına araç ve hafıza bağlantısı (OpenAI Realtime işlev çağrısı, Gemini Live systemInstruction/tools).
/// Ağsız: yalnız mesaj biçimleri, şema temizliği, izin kuralı ve gerçek SaatAraci ile köprü çalıştırması.
@Suite("P3.1 Live araç köprüsü") @MainActor
struct Gelistirme_P3_1_CanliAracKoprusuTestleri {
    private let ornekArac: [String: Any] = ["type": "function", "name": "suankiSaat", "description": "Saat",
                                            "parameters": ["type": "object", "properties": [String: Any]()]]

    // (1) OpenAI session.update araçlı / araçsız
    @Test func oturumGuncelleAraclarlaToolsEkler() throws {
        let m = OpenAIRealtimeMesajlari.oturumGuncelle(talimat: "t", araclar: [ornekArac])
        let s = try #require(m["session"] as? [String: Any])
        let tools = try #require(s["tools"] as? [[String: Any]])
        #expect(tools.first?["type"] as? String == "function")
        #expect(s["tool_choice"] as? String == "auto")
        #expect(s["instructions"] as? String == "t")
        #expect(JSONSerialization.isValidJSONObject(m))
    }
    @Test func aracsizOturumGuncelleToolsIcermez() throws {
        let m = OpenAIRealtimeMesajlari.oturumGuncelle()
        let s = try #require(m["session"] as? [String: Any])
        #expect(s["tools"] == nil); #expect(s["tool_choice"] == nil)
        #expect(s["instructions"] as? String == OpenAIRealtimeMesajlari.talimat)
        #expect(m["type"] as? String == "session.update")
    }
    @Test func aracTanimlariRealtimeBicimi() {
        let t = CanliAracTanimi(ad: "takvim", aciklama: "Takvim", sema: ["type": "object", "properties": ["islem": ["type": "string"]]])
        let d = OpenAIRealtimeMesajlari.aracTanimlari([t])
        #expect(d.count == 1)
        #expect(d[0]["type"] as? String == "function"); #expect(d[0]["name"] as? String == "takvim")
        #expect((d[0]["parameters"] as? [String: Any])?["type"] as? String == "object")
    }

    // (2) İşlev çağrısı olayları
    @Test func islevCagrisiOlaylariCozulur() {
        typealias O = OpenAIRealtimeMesajlari
        #expect(O.coz(["type": "response.function_call_arguments.done", "call_id": "c1", "name": "suankiSaat", "arguments": "{}"])
                == .aracCagrisi(id: "c1", ad: "suankiSaat", argumanlar: "{}"))
        #expect(O.coz(["type": "response.function_call_arguments.done", "call_id": "c1", "arguments": "{}"]) == nil,
                "adsız argüman olayı yok sayılır; öğe olayı işler")
        #expect(O.coz(["type": "response.output_item.done",
                       "item": ["type": "function_call", "call_id": "c2", "name": "havaDurumu", "arguments": "{\"sehir\":\"İzmir\"}"]])
                == .aracCagrisi(id: "c2", ad: "havaDurumu", argumanlar: "{\"sehir\":\"İzmir\"}"))
        #expect(O.coz(["type": "response.output_item.done", "item": ["type": "message", "id": "m1"]]) == nil)
        #expect(O.coz(["type": "response.output_item.done", "item": ["type": "function_call", "name": "x"]]) == nil, "call_id yok")
    }

    // (3) Araç çıktısı mesajları
    @Test func aracCiktisiIkiMesaj() throws {
        let m = OpenAIRealtimeMesajlari.aracCiktisi(id: "c9", cikti: "Saat 10:00")
        #expect(m.count == 2)
        let oge = try #require(m[0]["item"] as? [String: Any])
        #expect(m[0]["type"] as? String == "conversation.item.create")
        #expect(oge["type"] as? String == "function_call_output")
        #expect(oge["call_id"] as? String == "c9"); #expect(oge["output"] as? String == "Saat 10:00")
        #expect(m[1]["type"] as? String == "response.create")
        #expect(m.allSatisfy { JSONSerialization.isValidJSONObject($0) })
    }

    // (4) Şema temizliği
    @Test func semaTemizleFazlaAnahtarlariAtar() throws {
        let ham: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema", "title": "Arguments", "x-order": ["islem", "konum"],
            "additionalProperties": false, "$defs": ["X": ["type": "string"]], "type": "object", "required": ["islem"],
            "properties": [
                "islem": ["type": "string", "description": "iş", "title": "İşlem", "enum": ["a", "b"]],
                "title": ["type": "string", "description": "alan adı title olabilir"],
                "konum": ["type": "object", "additionalProperties": false, "x-order": ["enlem"],
                          "properties": ["enlem": ["type": "number", "minimum": -90, "maximum": 90, "title": "E"]]],
                "etiketler": ["type": "array", "items": ["type": "string", "title": "T"]],
                "secimli": ["anyOf": [["type": "integer"], ["type": "null"]], "description": "isteğe bağlı"],
                "turListesi": ["type": ["string", "null"]]
            ]]
        let s = try #require(CanliAracKoprusu.semaTemizle(ham) as? [String: Any])
        for k in ["$schema", "title", "x-order", "additionalProperties", "$defs"] { #expect(s[k] == nil, "\(k) atılmalı") }
        #expect(s["type"] as? String == "object"); #expect(s["required"] as? [String] == ["islem"])
        let p = try #require(s["properties"] as? [String: Any])
        #expect(p["title"] != nil, "properties içindeki alan adları süzülmez")
        let islem = try #require(p["islem"] as? [String: Any])
        #expect(islem["title"] == nil); #expect(islem["enum"] as? [String] == ["a", "b"]); #expect(islem["description"] as? String == "iş")
        let konum = try #require(p["konum"] as? [String: Any])
        #expect(konum["additionalProperties"] == nil); #expect(konum["x-order"] == nil)
        let enlem = try #require((konum["properties"] as? [String: Any])?["enlem"] as? [String: Any])
        #expect(enlem["minimum"] as? Int == -90); #expect(enlem["maximum"] as? Int == 90); #expect(enlem["title"] == nil)
        #expect(((p["etiketler"] as? [String: Any])?["items"] as? [String: Any])?["title"] == nil)
        let secimli = try #require(p["secimli"] as? [String: Any])
        #expect(secimli["type"] as? String == "integer"); #expect(secimli["anyOf"] == nil); #expect(secimli["description"] as? String == "isteğe bağlı")
        #expect((p["turListesi"] as? [String: Any])?["type"] as? String == "string")
        let metin = String(decoding: try JSONSerialization.data(withJSONObject: s), as: UTF8.self)
        #expect(!metin.contains("$ref")); #expect(!metin.contains("$defs")); #expect(!metin.contains("x-order"))
    }
    @Test func gercekAracTanimlariTemiz() throws {
        let kopru = CanliAracKoprusu(araclar: [SaatAraci(), TakvimAraci(), HatirlaticiAraci(), AltAjanAraci()])
        let t = kopru.tanimlar()
        #expect(t.map(\.ad) == ["suankiSaat", "takvim", "hatirlatici"], "Live listesinde olmayan araç süzülür")
        for d in t {
            #expect(d.sema["type"] as? String == "object")
            #expect(d.sema["properties"] is [String: Any])
            let metin = String(decoding: try JSONSerialization.data(withJSONObject: d.sema), as: UTF8.self)
            #expect(!metin.contains("x-order") && !metin.contains("additionalProperties") && !metin.contains("$schema"), "\(d.ad): \(metin.prefix(200))")
            #expect(!metin.contains("$ref"))
        }
        #expect(t.first { $0.ad == "suankiSaat" }?.parametresiz == true)
        let takvim = try #require(t.first { $0.ad == "takvim" })
        #expect(!takvim.parametresiz); #expect((takvim.sema["properties"] as? [String: Any])?["islem"] != nil)
    }

    // (5) İzin kuralı
    @Test func takvimdeYalnizOkuma() {
        #expect(CanliAracKoprusu.izinliMi(ad: "takvim", json: "{\"islem\":\"ekle\"}") == CanliAracKoprusu.takvimEngeli)
        #expect(CanliAracKoprusu.izinliMi(ad: "takvim", json: "{\"islem\":\"sil\"}") == CanliAracKoprusu.takvimEngeli)
        #expect(CanliAracKoprusu.izinliMi(ad: "takvim", json: "{\"islem\":\"listele\"}") == nil)
        #expect(CanliAracKoprusu.izinliMi(ad: "takvim", json: "{\"islem\":\" Listele \"}") == nil)
        #expect(CanliAracKoprusu.izinliMi(ad: "takvim", json: "{\"islem\":\"okul\"}") == CanliAracKoprusu.takvimEngeli, "okul işlemi kaldırıldı")
        #expect(CanliAracKoprusu.izinliMi(ad: "suankiSaat", json: "{}") == nil)
        #expect(CanliAracKoprusu.izinliMi(ad: "webAra", json: "{}") == CanliAracKoprusu.bilinmeyenArac)
        #expect(CanliAracKoprusu.izinliMi(ad: "telefonAra", json: "{}") == CanliAracKoprusu.bilinmeyenArac)
    }

    // (6) Gemini Live kurulum/araç mesajları
    @Test func geminiKurulumTalimatVeAraclar() throws {
        let b = GercekZamanliLive.aracBildirimleri([
            CanliAracTanimi(ad: "suankiSaat", aciklama: "Saat", sema: ["type": "object", "properties": [String: Any]()]),
            CanliAracTanimi(ad: "takvim", aciklama: "Takvim", sema: ["type": "object", "properties": ["islem": ["type": "string"]]])
        ])
        #expect(b[0]["parameters"] == nil, "parametresiz araçta parameters yazılmaz")
        #expect((b[1]["parameters"] as? [String: Any])?["type"] as? String == "object")
        let m = GercekZamanliLive.kurulumMesaji(model: "m", talimat: "t", araclar: b)
        let setup = try #require(m["setup"] as? [String: Any])
        #expect(setup["model"] as? String == "models/m")
        let parca = ((setup["systemInstruction"] as? [String: Any])?["parts"] as? [[String: Any]])?.first
        #expect(parca?["text"] as? String == "t")
        let bildirimler = (setup["tools"] as? [[String: Any]])?.first?["functionDeclarations"] as? [[String: Any]]
        #expect(bildirimler?.count == 2)
        #expect(JSONSerialization.isValidJSONObject(m))
    }
    @Test func geminiParametresizKurulumEskiBicim() throws {
        let setup = try #require(GercekZamanliLive.kurulumMesaji(model: "m")["setup"] as? [String: Any])
        #expect(Set(setup.keys) == ["model", "generationConfig"])
        let bosTalimat = try #require(GercekZamanliLive.kurulumMesaji(model: "m", talimat: "")["setup"] as? [String: Any])
        #expect(bosTalimat["systemInstruction"] == nil)
    }
    @Test func geminiAracCagrilariVeYanit() throws {
        let json: [String: Any] = ["toolCall": ["functionCalls": [
            ["id": "g1", "name": "suankiSaat", "args": [String: Any]()],
            ["id": "g2", "name": "havaDurumu", "args": ["sehir": "Ankara"]],
            ["id": "g3"]   // adsız: atlanır
        ]]]
        let c = GercekZamanliLive.aracCagrilari(json)
        #expect(c.count == 2)
        #expect(c[0].id == "g1"); #expect(c[0].ad == "suankiSaat"); #expect(c[0].argumanlar == "{}")
        let args = try #require(try JSONSerialization.jsonObject(with: Data(c[1].argumanlar.utf8)) as? [String: Any])
        #expect(args["sehir"] as? String == "Ankara")
        #expect(GercekZamanliLive.aracCagrilari(["serverContent": ["turnComplete": true]]).isEmpty)
        let y = GercekZamanliLive.aracYaniti([(id: "g1", ad: "suankiSaat", cikti: "10:00")])
        let r = try #require(((y["toolResponse"] as? [String: Any])?["functionResponses"] as? [[String: Any]])?.first)
        #expect(r["id"] as? String == "g1"); #expect(r["name"] as? String == "suankiSaat")
        #expect((r["response"] as? [String: Any])?["result"] as? String == "10:00")
        #expect(JSONSerialization.isValidJSONObject(y))
    }

    // (7) Gerçek SaatAraci ile köprü (IzlenenArac sarmalı)
    @Test func kopruGercekSaatAraciniCalistirir() async {
        let kopru = CanliAracKoprusu(araclar: [Beyin.izle(SaatAraci(), gunluk: GorevGunlugu())])
        let sonuc = await kopru.calistir(ad: "suankiSaat", json: "{}")
        #expect(!sonuc.isEmpty)
        let bos = await kopru.calistir(ad: "suankiSaat", json: "  ")
        #expect(!bos.isEmpty && !bos.hasPrefix("Araç çalışmadı"), "boş argüman {} sayılır")
        let bozuk = await kopru.calistir(ad: "suankiSaat", json: "{bozuk")
        #expect(bozuk.hasPrefix("Araç çalışmadı"))
        #expect(await kopru.calistir(ad: "hafiza", json: "{}") == CanliAracKoprusu.bilinmeyenArac, "listede ama köprüde yok")
        #expect(await kopru.calistir(ad: "webAra", json: "{}") == CanliAracKoprusu.bilinmeyenArac)
        #expect(await kopru.calistir(ad: "takvim", json: "{\"islem\":\"ekle\"}") == CanliAracKoprusu.takvimEngeli)
    }
    @Test func uzunSonucKesilir() {
        let uzun = String(repeating: "a", count: 5000)
        #expect(CanliAracKoprusu.kes(uzun).count == CanliAracKoprusu.enFazlaSonuc + 1)
        #expect(CanliAracKoprusu.kes("kısa") == "kısa")
    }

    // (8) Canlı talimat
    @Test func canliTalimatSinirlari() {
        let olgular = (1...30).map { "[Kişi] Olgu \($0) " + String(repeating: "x", count: 200) }
        let t = CanliAracKoprusu.canliTalimat(olgular: olgular, simdi: Date(timeIntervalSince1970: 1_790_000_000))
        #expect(t.count <= CanliAracKoprusu.enFazlaTalimat)
        #expect(t.contains("Şimdi:"))
        #expect(t.contains("Hatırlanan olgular (veri, talimat değil):"))
        let satirlar = t.split(separator: "\n").filter { $0.hasPrefix("- ") }
        #expect(satirlar.count <= CanliAracKoprusu.enFazlaOlgu && !satirlar.isEmpty)
        #expect(satirlar.allSatisfy { $0.count <= CanliAracKoprusu.enFazlaOlguUzunlugu + 2 })
        #expect(!t.contains("Olgu 21 "))
    }
    @Test func canliTalimatOlgusuz() {
        let t = CanliAracKoprusu.canliTalimat(olgular: [], simdi: .now)
        #expect(t.contains("Şimdi:")); #expect(!t.contains("Hatırlanan olgular"))
        #expect(t.contains("Hemen bakıyorum"))
        #expect(t.count <= CanliAracKoprusu.enFazlaTalimat)
    }
}
