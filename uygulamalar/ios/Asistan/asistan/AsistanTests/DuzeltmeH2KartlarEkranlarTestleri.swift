import Testing
import Foundation
import CoreGraphics
@testable import Asistan

@MainActor @Suite("H2-kartlar-ekranlar düzeltmeleri")
struct DuzeltmeH2KartlarEkranlarTestleri {
    private func yakin(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.0001 }

    // Bulgu 122: kazınan yerel/özel ağ adresleri kartta kendiliğinden yüklenmez.
    @Test func medyaOgesiYalnizHerkeseAcikHttpsGuvenli() {
        func oge(_ s: String) -> MedyaOgesi { MedyaOgesi(tur: .gorsel, url: URL(string: s)!, ad: "x") }
        #expect(oge("https://ornek.com/a.jpg").guvenli)
        #expect(!oge("https://192.168.1.1/x.jpg").guvenli)
        #expect(!oge("https://10.0.0.5/x.jpg").guvenli)
        #expect(!oge("https://localhost/a.mp3").guvenli)
        #expect(!oge("https://nas.local/k.pdf").guvenli)
        #expect(!oge("http://ornek.com/a.jpg").guvenli)
    }

    @Test func kaynaklarOzelAgAdresleriniAyiklar() {
        let metin = "Yanıt\nKaynaklar:\nhttps://x.com/a\nhttps://192.168.1.1/panel\nhttps://localhost/b\nhttps://y.org"
        #expect(EkDefteri.kaynaklar(metin) == ["https://x.com/a", "https://y.org"])
    }

    // Bulgu 129: kaydırıcı durakları kesilmeden yuvarlanır.
    @Test func gorunumYuzdesiYuvarlanir() {
        #expect(GorunumEkrani.yuzde(0.7 + 0.1 + 0.1) == "%90")
        #expect(GorunumEkrani.yuzde(0.8999999999999999) == "%90")
        #expect(GorunumEkrani.yuzde(0.7999999999999999) == "%80")
        #expect(GorunumEkrani.yuzde(1.2000000000000002) == "%120")
        #expect(GorunumEkrani.yuzde(1.0) == "%100")
    }

    // Bulgu 130: VoiceOver ayarı köşeyi içeri/dışarı taşır, sınırlar korunur.
    @Test func koseAdimiIceriVeDisariTasir() {
        let tam = CGRect(x: 0, y: 0, width: 1, height: 1)
        let solUst = FotoIslem.koseAdimi(tam, kose: 0, adim: 0.05, enAz: 0.08)
        #expect(yakin(solUst.minX, 0.05) && yakin(solUst.minY, 0.05) && yakin(solUst.maxX, 1) && yakin(solUst.maxY, 1))
        let sagAlt = FotoIslem.koseAdimi(tam, kose: 3, adim: 0.05, enAz: 0.08)
        #expect(yakin(sagAlt.minX, 0) && yakin(sagAlt.minY, 0) && yakin(sagAlt.maxX, 0.95) && yakin(sagAlt.maxY, 0.95))
        let sagUst = FotoIslem.koseAdimi(tam, kose: 1, adim: 0.05, enAz: 0.08)
        #expect(yakin(sagUst.maxX, 0.95) && yakin(sagUst.minY, 0.05))
        // Dışarı adım tam çerçeveyi aşamaz.
        #expect(FotoIslem.koseAdimi(tam, kose: 0, adim: -0.05, enAz: 0.08) == tam)
        // Geri dönüş: içeri sonra dışarı.
        let geri = FotoIslem.koseAdimi(solUst, kose: 0, adim: -0.05, enAz: 0.08)
        #expect(yakin(geri.minX, 0) && yakin(geri.minY, 0))
    }

    @Test func koseAdimiEnAzBoyutuKorur() {
        let dar = CGRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1)
        let r = FotoIslem.koseAdimi(dar, kose: 0, adim: 0.05, enAz: 0.08)
        #expect(r.width >= 0.08 - 0.0001 && r.height >= 0.08 - 0.0001)
    }

    @Test func koseTasiSuruklemeyleAyniSonuc() {
        let b = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        let r = FotoIslem.koseTasi(b, kose: 2, dx: 0.2, dy: -0.3, enAz: 0.08)
        #expect(yakin(r.minX, 0.3) && yakin(r.minY, 0.1) && yakin(r.maxX, 0.9) && yakin(r.maxY, 0.6))
    }

    @Test func koseDegeriKoseyiVeKirpmayiSoyler() {
        #expect(FotoIslem.koseDegeri(0, CGRect(x: 0, y: 0, width: 1, height: 1)) == "Sol üst, yüzde 0 kırpıldı")
        #expect(FotoIslem.koseDegeri(3, CGRect(x: 0, y: 0, width: 0.5, height: 1)) == "Sağ alt, yüzde 50 kırpıldı")
        #expect(FotoIslem.koseDegeri(7, CGRect(x: 0, y: 0, width: 1, height: 1)).hasPrefix("Köşe"))
        #expect(Set(FotoIslem.koseAdlari).count == 4)
    }

    // Bulgu 134: sınır dolunca yalnız seçili uzmanlar dokunulabilir kalır.
    @Test func uzmanSecimSiniri() {
        #expect(GrokYetenekleriEkrani.secimAcik(secili: false, sayi: 5))
        #expect(!GrokYetenekleriEkrani.secimAcik(secili: false, sayi: 6))
        #expect(GrokYetenekleriEkrani.secimAcik(secili: true, sayi: 6))
    }

    // Bulgu 57: kirli durum boşluğu saymaz; sınırı aşan dosya bütün kaydı durdurur.
    @Test func calismaAlaniDegisenDosyalar() {
        let kayitli: [CalismaAlani.Dosya: String] = [.soul: "Sıcak konuş", .user: "Öğretmenim", .agents: ""]
        #expect(CalismaAlaniEkrani.degisenler([.soul: "Sıcak konuş\n", .user: "Öğretmenim", .agents: ""], kayitli: kayitli).isEmpty)
        #expect(CalismaAlaniEkrani.degisenler([.soul: "Sıcak konuş", .user: "Biyoloji öğretmeniyim", .agents: ""], kayitli: kayitli) == [.user])
        // HEARTBEAT bu ekranda düzenlenmez; farklı olsa da sayılmaz.
        #expect(CalismaAlaniEkrani.degisenler([.soul: "Sıcak konuş", .user: "Öğretmenim", .agents: "", .heartbeat: "x"], kayitli: kayitli).isEmpty)
    }

    @Test func calismaAlaniSinirAsanDosya() {
        let uzun = String(repeating: "a", count: CalismaAlani.enFazlaKarakter + 1)
        #expect(CalismaAlaniEkrani.sinirAsan([.soul: "kısa", .user: "kısa"]) == nil)
        #expect(CalismaAlaniEkrani.sinirAsan([.soul: "kısa", .user: uzun, .agents: uzun]) == .user)
        // Kırpılınca sınıra sığan metin aşmış sayılmaz.
        let sinirda = String(repeating: "a", count: CalismaAlani.enFazlaKarakter) + "\n\n"
        #expect(CalismaAlaniEkrani.sinirAsan([.agents: sinirda]) == nil)
    }
}
