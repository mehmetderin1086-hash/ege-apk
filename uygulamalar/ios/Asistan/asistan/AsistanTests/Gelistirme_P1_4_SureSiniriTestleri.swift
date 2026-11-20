import Foundation
import Testing
@testable import Asistan

/// P1.4 süre sınırı: ortak WKWebView sıra kilidi (SiraKilidi / TarayiciOturumu.sirayla), bırakılabilir veri kazıma,
/// alt ajan görev sınırı, MCP argüman çözümü ve web araması sınırları. Ağ, izin ya da gerçek model gerekmez.
@Suite("P1.4 süre sınırı") @MainActor
struct Gelistirme_P1_4_SureSiniriTestleri {

    // MARK: SiraKilidi

    @Test func siraKilidiFifo() async {
        let k = SiraKilidi()
        let kayit = P14Kayit()
        let ilk = await k.al()
        var gorevler: [Task<Void, Never>] = []
        for n in 1...3 {
            gorevler.append(Task { @MainActor in
                let b = await k.al()
                kayit.sira.append(n)
                try? await Task.sleep(for: .milliseconds(20))
                k.birak(b)
            })
            // Sıraya giriş sırası kesinleşsin.
            #expect(await p14Bekle { k.bekleyenSayisi == n })
        }
        k.birak(ilk)
        for g in gorevler { await g.value }
        #expect(kayit.sira == [1, 2, 3])
        #expect(!k.dolu)
    }

    @Test func siraKilidiAsilaniDevralir() async throws {
        let k = SiraKilidi()
        let kayit = P14Kayit()
        k.zorlaDevraldi = { kayit.zorla += 1 }
        let eski = await k.al()   // hiç bırakmayan sahip
        let t0 = Date()
        let ikinci = await k.al(enFazla: .milliseconds(300))
        let gecen = Date().timeIntervalSince(t0)
        #expect(gecen >= 0.25, "sahibin süresi dolmadan devralınmamalı")
        #expect(gecen < 4, "süresi dolan sahip devralınmalı, sonsuz beklenmemeli (\(gecen))")
        #expect(kayit.zorla == 1)
        #expect(k.gecerli(ikinci))
        #expect(!k.gecerli(eski))

        let ucuncu = Task { @MainActor in
            let b = await k.al()
            kayit.sira.append(3)
            k.birak(b)
        }
        #expect(await p14Bekle { k.bekleyenSayisi == 1 })
        k.birak(eski)   // geçersiz bilet: kilidi çözmez
        try await Task.sleep(for: .milliseconds(150))
        #expect(kayit.sira.isEmpty, "eski bilet üçüncüyü salmamalı")
        #expect(k.bekleyenSayisi == 1)
        k.birak(ikinci)
        await ucuncu.value
        #expect(kayit.sira == [3])
        #expect(!k.dolu)
    }

    @Test func siraKilidiIptalEdilenBekleyenSiradanCikar() async {
        let k = SiraKilidi()
        let sahip = await k.al()
        let g = Task { @MainActor in await k.al() }
        #expect(await p14Bekle { k.bekleyenSayisi == 1 })
        g.cancel()
        let b = await g.value
        #expect(!k.gecerli(b), "iptal edilen bekleyen kilidi almış sayılmamalı")
        #expect(k.bekleyenSayisi == 0)
        k.birak(b)   // etkisiz
        #expect(k.gecerli(sahip))
        k.birak(sahip)
        #expect(!k.dolu)
    }

    // MARK: sirayla + sureSinirli

    @Test func birakilanIsKilitSirasindaBekler() async throws {
        let t = TarayiciOturumu()
        let kayit = P14Kayit()
        let t0 = Date()
        // İptali dinlemeyen 1 sn'lik iş kilit altında; süre sınırı 0,2 sn.
        let r: Int? = try await sureSinirli(0.2) { @MainActor in
            try await t.sirayla {
                await p14YokSayanBekle(1.0)
                kayit.sira.append(1)
                return 1
            }
        }
        #expect(r == nil)
        #expect(kayit.sira.isEmpty, "çağıran bırakılan işi beklememeli: iş henüz bitmemişken döndü")
        #expect(t.kilit.dolu, "bırakılan iş kilidi hâlâ tutmalı")
        // Sonraki iş kilidi ancak bırakılan iş bitince alır (aynı görünümde iki gezinme çakışmaz).
        let ikinciBaslangic = try await t.sirayla { () -> Date in
            kayit.sira.append(2)
            return Date()
        }
        #expect(kayit.sira == [1, 2])
        #expect(ikinciBaslangic.timeIntervalSince(t0) >= 0.9)
        #expect(!t.kilit.dolu)
    }

    @Test func siraylaIptalEdilmisGorevdeIsiKosturmaz() async {
        let t = TarayiciOturumu()
        let kayit = P14Kayit()
        let g = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await t.sirayla { kayit.sira.append(1); return 1 }
        }
        let sonuc = await g.result
        #expect(throws: CancellationError.self) { try sonuc.get() }
        #expect(kayit.sira.isEmpty)
        #expect(!t.kilit.dolu)
    }

    // MARK: Tarayıcı ajanı: onay kilidin dışında, sonra sayfa yeniden doğrulanır

    @Test func tiklaOnaySirasindaSayfaDegisirseUygulanmaz() async throws {
        let t = TarayiciOturumu()
        t.web.loadHTMLString("""
        <html><head><title>A</title></head><body><button onclick="document.title='tiklandi'">Gönder</button></body></html>
        """, baseURL: URL(string: "https://ornek.test/a"))
        await t.yuklemeyiBekle(sinir: 10)
        _ = await t.durum()   // öğe numaraları
        let onay = OnayKapisi(zorunluOtomatikKararaUyar: false)
        let arac = TarayiciAraci(onay: onay, oturum: t)
        let gorev = Task { @MainActor in try await arac.call(arguments: .init(islem: "tikla", deger: "", no: 1)) }
        #expect(await p14Bekle { onay.bekleyen != nil }, "riskli düğme onay istemeli")
        #expect(!t.kilit.dolu, "onay beklenirken kilit tutulmamalı")
        // Onay beklenirken başka bir iş (veri kazıma gibi) aynı görünümde başka sayfaya gider.
        try await t.sirayla {
            t.web.loadHTMLString("""
            <html><head><title>B</title></head><body><button onclick="document.title='tiklandi'">Sil</button></body></html>
            """, baseURL: URL(string: "https://ornek.test/b"))
            await t.yuklemeyiBekle(sinir: 10)
            _ = await t.durum()
        }
        onay.yanitla(true)
        let sonuc = try await gorev.value
        #expect(sonuc.contains("Sayfa bu arada değişti"))
        #expect(await t.js("document.title") as? String == "B", "onaylanan tıklama yanlış sayfaya uygulanmamalı")
    }

    @Test func yazSayfaAyniysaOnaydanSonraUygulanir() async throws {
        let t = TarayiciOturumu()
        t.web.loadHTMLString("""
        <html><head><title>Form</title></head><body><input id="ad" placeholder="Adınız"></body></html>
        """, baseURL: URL(string: "https://ornek.test/form"))
        await t.yuklemeyiBekle(sinir: 10)
        _ = await t.durum()
        let onay = OnayKapisi(zorunluOtomatikKararaUyar: false)
        let arac = TarayiciAraci(onay: onay, oturum: t)
        let gorev = Task { @MainActor in try await arac.call(arguments: .init(islem: "yaz", deger: "Mehmet", no: 1)) }
        #expect(await p14Bekle { onay.bekleyen != nil })
        onay.yanitla(true)
        let sonuc = try await gorev.value
        #expect(sonuc.contains("alana yazıldı"))
        #expect(await t.js("document.getElementById('ad').value") as? String == "Mehmet")
    }

    // MARK: Alt ajan görev sınırı

    @Test func altAjanGorevSiniri() async {
        let t0 = Date()
        let s = await AltAjanlar.calistir([.init(tur: "dusun", istek: "a"), .init(tur: "arastir", istek: "b")],
                                          dusun: { _ in await p14YokSayanBekle(5); return "geç" },
                                          arastir: { "A:\($0)" }, sinir: 1)
        let gecen = Date().timeIntervalSince(t0)
        #expect(s[0].contains("saniyede bitmedi"))
        #expect(s[1] == "A:b", "biten görev etkilenmemeli")
        #expect(gecen < 4, "iptali dinlemeyen alt görev (5 sn) beklenmemeli (\(gecen))")
    }

    // MARK: MCP

    @Test func mcpArgumanMetniAgsizCozulur() async throws {
        #expect(try McpIstemci.argumanCoz("").isEmpty)
        #expect(try McpIstemci.argumanCoz("  ").isEmpty)
        #expect(try McpIstemci.argumanCoz(" {\"a\": 1} ")["a"] as? Int == 1)
        #expect(throws: McpIstemci.Hata.self) { try McpIstemci.argumanCoz("[1, 2]") }
        #expect(throws: McpIstemci.Hata.self) { try McpIstemci.argumanCoz("bozuk") }
        // Geçersiz argüman ağa çıkmadan hata verir.
        let s = McpSunucu(ad: "deneme", url: "https://mcp.ornek.invalid/mcp")
        await #expect(throws: McpIstemci.Hata.self) { try await McpIstemci.cagir(s, arac: "x", argumanMetni: "{bozuk") }
        #expect(McpIstemci.Hata.arguman.errorDescription?.contains("JSON") == true)
        #expect(McpAraci.cagriZamanAsimi.contains("kullanıcıya sor"))
        #expect(McpAraci.cagriSiniri == 60 && McpAraci.listeSiniri == 30)
    }

    // MARK: Web araması

    @Test func webZamanAsimiCabayaGore() {
        #expect(WebArastirici.zamanAsimi(.low) == 35)
        #expect(WebArastirici.zamanAsimi(.medium) == 55)
        #expect(WebArastirici.zamanAsimi(.high) == 90)
        // Dış sınır yüksek çabalı aramayı kesmemeli; derin arama bölme (15) + yüksek çabalı yedek (90) sığmalı.
        #expect(WebAraci.derinSinir >= 15 + WebArastirici.zamanAsimi(.high))
    }
}

@MainActor final class P14Kayit {
    var sira: [Int] = []
    var zorla = 0
}

/// İptali tümüyle yok sayan bekleme (seri kuyruktaki iş gibi).
nonisolated func p14YokSayanBekle(_ sn: Double) async {
    await withCheckedContinuation { (d: CheckedContinuation<Void, Never>) in
        DispatchQueue.global().asyncAfter(deadline: .now() + sn) { @Sendable in d.resume() }
    }
}

/// Koşul sağlanana kadar (en çok `enFazla` sn) bekler; Swift Testing'de zaman sınırı olmadığından sınırlı döngü.
@MainActor func p14Bekle(enFazla: Double = 5, _ kosul: () -> Bool) async -> Bool {
    let son = Date().addingTimeInterval(enFazla)
    while !kosul() {
        if Date() > son { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}
