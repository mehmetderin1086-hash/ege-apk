import Foundation
import Testing
import ClaudeForFoundationModels
import UIKit
@testable import Asistan

@Suite("Telefon entegrasyonu")
@MainActor
struct TelefonTestleri {
    @Test func spotifyOnayiOkunabilirVeOynatmaIddiaEtmez() throws {
        let url = try #require(URL(string: "https://open.spotify.com/search/Bar%C4%B1%C5%9F%20Man%C3%A7o%20G%C3%BClpembe"))
        let metin = UygulamaAcAraci.onayMetni(url)
        #expect(metin.contains("Barış Manço Gülpembe"))
        #expect(metin.contains("open.spotify.com"))
        #expect(metin.contains("otomatik çalmayabilir"))
    }

    @Test func webSonucundaGercekAramaVeKaynakGerekir() throws {
        let sahte = Data(#"{"output":[{"type":"message","content":[{"type":"output_text","text":"Baktım."}]}]}"#.utf8)
        #expect(throws: WebArastirici.Hata.self) { try WebArastirici.coz(sahte) }
        let gercek = Data(#"{"output":[{"type":"web_search_call","status":"completed","action":{"sources":[{"url":"https://support.apple.com/"}]}},{"type":"message","content":[{"type":"output_text","text":"Kaynaklı sonuç"}]}]}"#.utf8)
        #expect(try WebArastirici.coz(gercek).contains("https://support.apple.com/"))
        let atifli = Data(#"{"output":[{"type":"web_search_call","status":"completed","action":{"sources":[{"url":"https://example.com/unrelated"}]}},{"type":"message","content":[{"type":"output_text","text":"Sonuç","annotations":[{"type":"url_citation","url":"https://support.apple.com/120421"}]}]}]}"#.utf8)
        let sonuc = try WebArastirici.coz(atifli)
        #expect(sonuc.contains("https://support.apple.com/120421"))
        #expect(!sonuc.contains("unrelated"))
    }
    @Test func webKaynaklariResmiDogrudanAdresleriOneAlir() {
        let kaynaklar = WebArastirici.kaynaklariSirala([
            "https://ornek.com/yazi",
            "https://ccn.web.tr/web-api/iframe-proxy?url=https://support.apple.com/120421",
            "https://support.apple.com/tr-tr/120421",
            "https://ornek.com/yazi"
        ])
        #expect(kaynaklar == [
            "https://support.apple.com/tr-tr/120421",
            "https://ornek.com/yazi",
            "https://ccn.web.tr/web-api/iframe-proxy?url=https://support.apple.com/120421"
        ])
    }
    @Test func taranmisPDFMetniOkunur() throws {
        let dosya = FileManager.default.temporaryDirectory.appending(path: "asistan-ocr-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: dosya) }
        let boyut = CGSize(width: 600, height: 800)
        let resim = UIGraphicsImageRenderer(size: boyut).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: boyut))
            ("ASISTAN BELGE TESTI 12345" as NSString).draw(at: CGPoint(x: 30, y: 80), withAttributes: [.font: UIFont.systemFont(ofSize: 26), .foregroundColor: UIColor.black])
        }
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: boyut)).pdfData { ctx in
            ctx.beginPage(); resim.draw(at: .zero)
        }
        try pdf.write(to: dosya)
        let okunan = try BelgeOkuyucu.oku(dosya)
        #expect(okunan.metin.contains("12345"))
        #expect(okunan.metin.contains("[Sayfa 1]"))
    }
    @Test func secilenSaglayiciSessizceClaudeOlmaz() {
        for id in ["gpt-6.1-sol", "gemini-3.8-flash", "grok-test"] { #expect(ClaudeModel.sabit(id).id == id) }
        #expect(ClaudeModel.sabit("claude-opus-5-5").id == "claude-opus-5-5")
    }
    @Test func gorselVeSesModelleriSohbettenAyrilir() {
        #expect(TelefonProxy.Model(id: "gpt-6.1-sol").sohbet)
        #expect(TelefonProxy.Model(id: "gemini-3.8-flash").aile == "Gemini")
        #expect(!TelefonProxy.Model(id: "gpt-image-2").sohbet)
        #expect(!TelefonProxy.Model(id: "gemini-live").sohbet)
        #expect(TelefonProxy.Model(id: "grok-4").aile == "Grok")
    }
    @Test func belgeIcerigiVeSiniri() throws {
        let dosya = FileManager.default.temporaryDirectory.appending(path: "asistan-belge-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: dosya) }
        try String(repeating: "Türkçe bilgi. ", count: 5000).write(to: dosya, atomically: true, encoding: .utf8)
        let belge = try BelgeOkuyucu.oku(dosya)
        #expect(belge.metin.count == 50_000)
        #expect(!belge.not.isEmpty)
        #expect(belge.metin.hasPrefix("Türkçe bilgi."))
    }
    @Test func tamSifirMikrofonDortSaniyedeAlgilanir() {
        var s = MikrofonSinyali()
        for _ in 0..<15 { let engelli = s.engelli(tepe: 0); #expect(!engelli) }
        let engelli = s.engelli(tepe: 0)
        #expect(engelli)
    }
    @Test func normalSessizlikVeKisikSesMikrofonHatasiSayilmaz() {
        var s = MikrofonSinyali()
        for _ in 0..<14 { _ = s.engelli(tepe: 0) }
        let engelli = s.engelli(tepe: 0.000001)
        #expect(!engelli)
        #expect(s.sifirPencere == 0)
        for _ in 0..<50 { let engelli = s.engelli(tepe: 0.00001); #expect(!engelli) }
    }
    @Test func telefonHesabiOnceliklidirVeSunucuYedegiVardir() {
        let z = ModelZinciri(vekilVar: true, anahtarVar: true, yalnizAnahtar: false, telefonVar: true)
        #expect(z.adimlar(model: "claude-opus-5-5").map(\.yol) == [.telefon, .vekil, .anahtar])
    }
    @Test func acikAnahtarSecimiKorunur() {
        let z = ModelZinciri(vekilVar: true, anahtarVar: true, yalnizAnahtar: true, telefonVar: true)
        #expect(z.adimlar(model: "m").map(\.yol) == [.anahtar])
    }
    @Test func webAdresininHarfleriVeSorgusuKorunur() throws {
        let adres = "https://example.com/BuyukDosya?Token=AbC123"
        #expect(try #require(TelefonAdresleri.web(adres)).absoluteString == adres)
        #expect(TelefonAdresleri.web("https://kullanici:sifre@example.com") == nil)
        #expect(TelefonAdresleri.web("javascript:alert(1)") == nil)
        #expect(TelefonAdresleri.web("https://") == nil)
    }
    @Test func turkceUygulamaAdlari() {
        #expect(TelefonAdresleri.ad("  FOTOĞRAFLAR ") == "fotograflar")
        #expect(TelefonAdresleri.ad("Kısayollar") == "kisayollar")
        #expect(TelefonAdresleri.ad("İNSTAGRAM") == "instagram")
    }
    @Test func kestirmeOzelKarakterleriKaybolmaz() throws {
        let url = try #require(TelefonAdresleri.kisayol("Ev & İş", girdi: "A+B & C? Türkçe"))
        let c = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(c.queryItems?.first(where: { $0.name == "name" })?.value == "Ev & İş")
        #expect(c.queryItems?.first(where: { $0.name == "text" })?.value == "A+B & C? Türkçe")
        #expect(TelefonAdresleri.kisayol("  ") == nil)
    }
    @Test func kestirmeKaydiGuncellenirVeKalir() throws {
        let alan = "kestirme.test.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: alan))
        defer { d.removePersistentDomain(forName: alan) }
        let k = TelefonKestirmeleri(defaults: d)
        k.kaydet(ad: "İş", kestirme: "Ofisi aç")
        k.kaydet(ad: "iş", kestirme: "Ofis modu")
        #expect(k.kayitlar.count == 1)
        #expect(TelefonKestirmeleri(defaults: d).bul("İŞ")?.kestirme == "Ofis modu")
        k.sil(try #require(k.kayitlar.first).id)
        #expect(TelefonKestirmeleri(defaults: d).kayitlar.isEmpty)
    }
    @Test func iptalBekleyenOnayiKapatir() async {
        let o = OnayKapisi()
        let t = Task { await o.iste(baslik: "İşlem", ayrinti: "") }
        while o.bekleyen == nil { await Task.yield() }
        t.cancel()
        #expect(await t.value == false)
        #expect(o.bekleyen == nil)
    }
    @Test func acikKomutlarIcinUygulamaOnayiOtomatiklestirilebilir() async {
        let onay = OnayKapisi()
        onay.otomatikKarar = true
        #expect(await onay.iste(baslik: "Ara", ayrinti: "Kişi") == true)
        #expect(onay.bekleyen == nil)
    }
}
