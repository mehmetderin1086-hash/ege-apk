import Testing
import Foundation
import FoundationModels
@testable import Asistan

/// P3.10-arıza: arıza anahtarları (saf çekirdek + kalıcılık), sınama kayıt tablosu ve sahte sunucunun geçiş kipi.
/// Ağa (yalnız 127.0.0.1), izne ya da gerçek modele çıkmaz. Her test kendi geçici UserDefaults suite'ini ve kendi
/// sunucu örneklerini kullanır; `ArizaDeposu.ortak` ve `SahteModelSunucusu.gecis` tekillerine dokunulmaz.
@Suite("P3.10 arıza modu")
struct Gelistirme_P3_10_ariza_Testleri {

    private func geciciDepo() -> (ArizaDeposu, UserDefaults, String) {
        let ad = "asistan.ariza.test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: ad)!
        return (ArizaDeposu(depo: d), d, ad)
    }

    private func geciciKlasor() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appending(path: "sinama-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    // MARK: Anahtarlar

    @Test func ikiTekrarIkiKezTetiklenirUcuncusuTetiklenmez() {
        let (a, d, ad) = geciciDepo(); defer { d.removePersistentDomain(forName: ad) }
        a.ac(.modelKota429, tekrar: 2)
        #expect(a.etkin(.modelKota429))
        #expect(a.tuket(.modelKota429))
        #expect(a.tuket(.modelKota429))
        #expect(!a.tuket(.modelKota429))
        #expect(!a.etkin(.modelKota429), "kalan 0'da kapanır")
        #expect(!a.tuket(.sttHatasi), "açılmamış arıza tetiklenmez")
    }

    @Test func suresiGecmisKayitEtkinDegil() {
        let (a, d, ad) = geciciDepo(); defer { d.removePersistentDomain(forName: ad) }
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        a.ac(.agYok, tekrar: -1, sure: 60, simdi: t0)
        #expect(a.etkin(.agYok, simdi: t0.addingTimeInterval(59)))
        #expect(!a.etkin(.agYok, simdi: t0.addingTimeInterval(61)))
        #expect(!a.tuket(.agYok, simdi: t0.addingTimeInterval(30)), "süresi geçen kayıt silindi, geri gelmez")
    }

    @Test func hepsiniKapatModelArizasiniDusurur() {
        let (a, d, ad) = geciciDepo(); defer { d.removePersistentDomain(forName: ad) }
        a.ac(.aracHatasi)
        #expect(!a.modelArizasiVar, "araç hatası model arızası değil")
        a.ac(.akisYarida, tekrar: 3)
        #expect(a.modelArizasiVar)
        #expect(a.herhangiEtkin)
        a.hepsiniKapat()
        #expect(!a.modelArizasiVar)
        #expect(!a.herhangiEtkin)
        #expect(d.data(forKey: ArizaDeposu.anahtar) == nil, "boş durum kalıcı anahtarı siler")
    }

    @Test func durumUserDefaultsTaKalicidir() {
        let (a, d, ad) = geciciDepo(); defer { d.removePersistentDomain(forName: ad) }
        a.ac(.modelSunucu500, tekrar: 3)
        _ = a.tuket(.modelSunucu500)
        let yeniden = ArizaDeposu(depo: d)
        #expect(yeniden.kayitlar()[.modelSunucu500]?.kalan == 2, "yeniden açılışta kalan sayı korunur")
        a.kapat(.modelSunucu500)
        #expect(ArizaDeposu(depo: d).kayitlar().isEmpty)
    }

    @Test func durumGuncelleSinirsiziAzaltmaz() {
        let simdi = Date()
        let d: [ArizaTuru: ArizaDeposu.Kayit] = [.sttHatasi: .init(kalan: ArizaDeposu.sinirsiz, bitis: simdi.addingTimeInterval(100)),
                                                 .aracHatasi: .init(kalan: 1, bitis: simdi.addingTimeInterval(100)),
                                                 .agYok: .init(kalan: 5, bitis: simdi.addingTimeInterval(-1))]
        let (s1, d1) = ArizaDeposu.durumGuncelle(d, tuket: .sttHatasi, simdi: simdi)
        #expect(s1)
        #expect(d1[.sttHatasi]?.kalan == ArizaDeposu.sinirsiz)
        #expect(d1[.agYok] == nil, "süresi geçen kayıt temizlenir")
        let (s2, d2) = ArizaDeposu.durumGuncelle(d1, tuket: .aracHatasi, simdi: simdi)
        #expect(s2)
        #expect(d2[.aracHatasi] == nil, "son tekrar kaydı kapatır")
        let (s3, _) = ArizaDeposu.durumGuncelle(d2, tuket: .aracHatasi, simdi: simdi)
        #expect(!s3)
    }

    @Test func turlerinAdlariVeSiniflari() {
        #expect(ArizaTuru.allCases.count == 8)
        #expect(ArizaTuru.allCases.allSatisfy { !$0.ad.isEmpty })
        #expect(Set(ArizaTuru.allCases.filter(\.modelArizasi)) == [.modelKota429, .modelSunucu500, .akisYarida, .ilkParcaGec])
        #expect(ArizaTuru.allCases.filter(\.eylem) == [.yerelSunucuOlu])
        #expect(ArizaHatasi.arac("Saat").errorDescription == "arıza modu — Saat yapay olarak başarısız")
    }

    // MARK: Sınama kayıtları

    @Test func ozetleBasariVeSure() {
        let a = SinamaKaydi.ozetle(ad: "ofis-sinama", json: ["tamamlandi": true, "hata": ""])
        #expect(a.basarili)
        let b = SinamaKaydi.ozetle(ad: "ofis-sinama", json: ["tamamlandi": true, "hata": "x"])
        #expect(!b.basarili)
        #expect(b.ozet.contains("x"))
        let c = SinamaKaydi.ozetle(ad: "hiz", json: ["tamamlandi": true, "sureMs": 1500])
        #expect(c.sureSn == 1.5)
        let e = SinamaKaydi.ozetle(ad: "hiz", json: ["tamamlandi": false, "toplamSn": 2.25, "sureSaniye": 9])
        #expect(!e.basarili)
        #expect(e.sureSn == 2.25, "toplamSn önce gelir")
        #expect(SinamaKaydi.ozetle(ad: "x", json: ["tamamlandi": true, "sureSaniye": 4]).sureSn == 4)
        #expect(SinamaKaydi.ozetle(ad: "x", json: [:]).sureSn == nil)
    }

    @Test func ekleOkuBozukSatiriAtlar() throws {
        let k = try geciciKlasor(); defer { try? FileManager.default.removeItem(at: k) }
        SinamaKaydi.ekle(SinamaKaydi(ad: "bir", surum: "1.0 (1)", basarili: true, sureSn: 1, ozet: "Tamam"), klasor: k)
        let url = k.appending(path: SinamaKaydi.dosyaAdi)
        let h = try FileHandle(forWritingTo: url); try h.seekToEnd(); try h.write(contentsOf: Data("{bozuk satır\n".utf8)); try h.close()
        SinamaKaydi.ekle(SinamaKaydi(ad: "iki", surum: "1.0 (1)", basarili: false, ozet: "Hata"), klasor: k)
        let okunan = SinamaKaydi.oku(klasor: k)
        #expect(okunan.map(\.ad) == ["bir", "iki"])
        #expect(okunan.first?.sureSn == 1)
        #expect(okunan.last?.basarili == false)
    }

    @Test func besYuzSinirindaKirpilir() throws {
        let k = try geciciKlasor(); defer { try? FileManager.default.removeItem(at: k) }
        let kayitlar = (0..<(SinamaKaydi.enFazla + 20)).map { SinamaKaydi(ad: "s\($0)", surum: "t", basarili: true, ozet: "") }
        SinamaKaydi.ekle(kayitlar, klasor: k)
        SinamaKaydi.ekle(SinamaKaydi(ad: "son", surum: "t", basarili: true, ozet: ""), klasor: k)
        let okunan = SinamaKaydi.oku(klasor: k)
        #expect(okunan.count == SinamaKaydi.enFazla)
        #expect(okunan.last?.ad == "son")
        #expect(okunan.first?.ad == "s21", "en eski satırlar kırpılır")
    }

    @Test func raporlarIceAktarilirBirKez() throws {
        let k = try geciciKlasor(); defer { try? FileManager.default.removeItem(at: k) }
        let rapor = try JSONSerialization.data(withJSONObject: ["tamamlandi": true, "hata": "", "toplamSn": 3.5])
        try rapor.write(to: k.appending(path: "asistan-ilk-metin-sinama.json"))
        try Data("bozuk".utf8).write(to: k.appending(path: "asistan-bozuk.json"))
        try Data("{}".utf8).write(to: k.appending(path: "baska.json"))
        #expect(SinamaKaydi.iceAktar(klasor: k) == 1)
        #expect(SinamaKaydi.iceAktar(klasor: k) == 0, "aynı rapor ikinci kez eklenmez")
        let okunan = SinamaKaydi.oku(klasor: k)
        #expect(okunan.map(\.ad) == ["ilk-metin-sinama"])
        #expect(okunan.first?.basarili == true)
        #expect(okunan.first?.sureSn == 3.5)
        #expect(SinamaKaydi.hamRapor(ad: "ilk-metin-sinama", klasor: k)?.contains("toplamSn") == true)
        #expect(SinamaKaydi.raporAdi("asistan-.json") == nil)
    }

    // MARK: Geçiş kipi (yalnız 127.0.0.1)

    private func modelIstegi(_ taban: URL, yol: String = "v1/messages", akis: Bool = false) -> URLRequest {
        var r = URLRequest(url: taban.appending(path: yol), timeoutInterval: 10)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("Bearer sahte", forHTTPHeaderField: "Authorization")
        r.httpBody = Data(#"{"model":"claude-haiku-4-5","stream":\#(akis),"max_tokens":64,"messages":[{"role":"user","content":"Merhaba"}]}"#.utf8)
        return r
    }

    @Test(.timeLimit(.minutes(1)))
    func gecis429IlkIstekteSonrakiHedefe() async throws {
        let (a, d, ad) = geciciDepo(); defer { d.removePersistentDomain(forName: ad) }
        let hedef = SahteModelSunucusu()
        let hedefURL = try await hedef.baslat(senaryo: .yerlesik)
        defer { hedef.durdur() }
        let gecis = SahteModelSunucusu()
        let url = try await gecis.baslatGecis(hedef: hedefURL, ariza: a)
        defer { gecis.durdur() }
        #expect(url != hedefURL)
        a.ac(.modelKota429, tekrar: 1)
        let oturum = URLSession(configuration: .ephemeral)
        defer { oturum.invalidateAndCancel() }

        let (v1, y1) = try await oturum.data(for: modelIstegi(url))
        let h1 = try #require(y1 as? HTTPURLResponse)
        #expect(h1.statusCode == 429)
        #expect(h1.value(forHTTPHeaderField: "retry-after") == "30")
        let n1 = try #require(try JSONSerialization.jsonObject(with: v1) as? [String: Any])
        #expect((n1["error"] as? [String: Any])?["type"] as? String == "rate_limit_error")
        #expect(hedef.istekGunlugu.isEmpty, "arızalı istek hedefe gitmez")

        let (v2, y2) = try await oturum.data(for: modelIstegi(url))
        #expect((y2 as? HTTPURLResponse)?.statusCode == 200)
        let n2 = try #require(try JSONSerialization.jsonObject(with: v2) as? [String: Any])
        #expect(n2["type"] as? String == "message", "hedefin yanıtı iletilir")
        #expect(hedef.istekGunlugu.count == 1)
        #expect(hedef.istekGunlugu.first?.yol == "/v1/messages")

        // GET /v1/models hiç arızalanmaz (canlılık ve model listesi).
        a.ac(.modelSunucu500, tekrar: -1)
        let (_, y3) = try await oturum.data(from: url.appending(path: "v1/models"))
        #expect((y3 as? HTTPURLResponse)?.statusCode == 200)
        #expect(SahteModelSunucusu.gecis.tabanURL == nil, "ayrı örnek geçiş tekilini başlatmamalı")
    }

    @Test(.timeLimit(.minutes(1)))
    func gecis500OpenAIBicimindeDoner() async throws {
        let (a, d, ad) = geciciDepo(); defer { d.removePersistentDomain(forName: ad) }
        let hedef = SahteModelSunucusu()
        let hedefURL = try await hedef.baslat(senaryo: .yerlesik)
        defer { hedef.durdur() }
        let gecis = SahteModelSunucusu()
        let url = try await gecis.baslatGecis(hedef: hedefURL, ariza: a)
        defer { gecis.durdur() }
        a.ac(.modelSunucu500)
        let oturum = URLSession(configuration: .ephemeral)
        defer { oturum.invalidateAndCancel() }
        let (v, y) = try await oturum.data(for: modelIstegi(url, yol: "v1/chat/completions"))
        #expect((y as? HTTPURLResponse)?.statusCode == 500)
        let n = try #require(try JSONSerialization.jsonObject(with: v) as? [String: Any])
        #expect((n["error"] as? [String: Any])?["type"] as? String == "server_error")
    }

    @Test(.timeLimit(.minutes(1)))
    func akisYaridaKesilir() async throws {
        let (a, d, ad) = geciciDepo(); defer { d.removePersistentDomain(forName: ad) }
        let hedef = SahteModelSunucusu()
        let hedefURL = try await hedef.baslat(senaryo: .yerlesik)
        defer { hedef.durdur() }
        let gecis = SahteModelSunucusu()
        let url = try await gecis.baslatGecis(hedef: hedefURL, ariza: a)
        defer { gecis.durdur() }
        let oturum = URLSession(configuration: .ephemeral)
        defer { oturum.invalidateAndCancel() }

        func satirlar() async -> [String] {
            var s: [String] = []
            do {
                let (baytlar, _) = try await oturum.bytes(for: modelIstegi(url, akis: true))
                for try await satir in baytlar.lines { s.append(satir) }
            } catch {}   // kesik akışta istemci hata alabilir; gelen satırlar yeterli
            return s
        }

        let tam = await satirlar()
        #expect(tam.contains { $0.contains("message_stop") }, "arıza yokken akış tam gelir")
        a.ac(.akisYarida)
        let kesik = await satirlar()
        #expect(!kesik.contains { $0.contains("message_stop") }, "akış bitmeden kesilmeli")
        #expect(kesik.contains { $0.contains("message_start") }, "ilk olaylar iletilmiş olmalı")
    }

    @Test(.timeLimit(.minutes(1)))
    func ilkParcaGecikir() async throws {
        let (a, d, ad) = geciciDepo(); defer { d.removePersistentDomain(forName: ad) }
        let hedef = SahteModelSunucusu()
        let hedefURL = try await hedef.baslat(senaryo: .yerlesik)
        defer { hedef.durdur() }
        let gecis = SahteModelSunucusu()
        let url = try await gecis.baslatGecis(hedef: hedefURL, ariza: a, ilkParcaGecikmesi: .milliseconds(600))
        defer { gecis.durdur() }
        a.ac(.ilkParcaGec)
        let oturum = URLSession(configuration: .ephemeral)
        defer { oturum.invalidateAndCancel() }
        let bas = Date()
        let (_, y) = try await oturum.data(for: modelIstegi(url))
        #expect((y as? HTTPURLResponse)?.statusCode == 200)
        #expect(Date().timeIntervalSince(bas) >= 0.55, "gecikme uygulanmalı")
        #expect(!a.etkin(.ilkParcaGec), "tek tekrar harcandı")
    }

    // MARK: Araç arızası (GorevGunlugu.IzlenenArac kancası)

    /// Kanca `IzlenenArac.call` içindeki `do` bloğundadır: adım "Hata" olarak kapanır, model `hataSonucu` metnini alır.
    @MainActor @Test(.timeLimit(.minutes(1)))
    func aracHatasiHataSonucuDondururVeAdimiIsaretler() async throws {
        let (a, d, ad) = geciciDepo(); defer { d.removePersistentDomain(forName: ad) }
        a.ac(.aracHatasi, tekrar: 1)
        let g = GorevGunlugu()
        let arac = IzlenenArac(asil: SaatAraci(), gunluk: g)
        let bos = try SaatAraci.Arguments(try GeneratedContent(json: "{}"))
        let sonuc = try await ArizaAnahtarlari.$gecerli.withValue(a) {
            try await arac.call(arguments: bos)
        }
        #expect(sonuc.hasPrefix("Araç çalışmadı:"), "sonuç: \(sonuc)")
        #expect(sonuc.contains("arıza modu"))
        #expect(g.adimlar.last?.durum == "Hata")
        #expect(!a.etkin(.aracHatasi), "tek tekrar harcandı")
        // İkinci çağrı olağan sonuç verir.
        let ikinci = try await ArizaAnahtarlari.$gecerli.withValue(a) { try await arac.call(arguments: bos) }
        #expect(ikinci.hasPrefix("Şu an:"))
    }
}
