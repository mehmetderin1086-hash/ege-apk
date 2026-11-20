import Foundation
import UIKit
import Testing
import SwiftData
@testable import Asistan

@Suite("Görünüm profilleri") @MainActor
struct GorunumTestleri {
    @Test func tumHazirProfillerKayipsizTasinir() throws {
        // P1.6: tek hazır görünüm seti sohbet temalarıdır.
        for h in SohbetTemasi.hazirlar {
            var p = GorunumTercihleri(); p.sohbet = h; p.renk = SohbetTemaAyarlari.vurgu(h.ad)
            #expect(try GorunumTercihleri.coz(p.veri()) == p, "\(h.ad)")
        }
    }
    @Test func bozukProfilVeSinirDisiDegerReddedilir() throws {
        var p = GorunumTercihleri(); p.yaziOlcegi = 1000
        #expect(throws: (any Error).self) { try GorunumTercihleri.coz(JSONEncoder().encode(p)) }
        p.yaziOlcegi = 1; p.renk = "not-a-color"
        #expect(throws: (any Error).self) { try p.dogrula() }
        p.renk = "F47863"; p.surum = 99
        #expect(throws: (any Error).self) { try p.dogrula() }
        #expect(throws: (any Error).self) { try GorunumTercihleri.coz(Data(repeating: 32, count: 16001)) }
    }
    @Test func gorunumKalicidirDigerAyarlarKorunur() throws {
        let ad = "gorunum-test.\(UUID())"; let d = try #require(UserDefaults(suiteName: ad))
        defer { d.removePersistentDomain(forName: ad) }
        var gece = GorunumTercihleri(); gece.tema = .koyu; gece.sohbet = .gece; gece.renk = SohbetTemaAyarlari.vurgu("Gece")
        let a = Ayarlar(defaults: d); a.gorunum = gece; a.sesKimligi = "azure:Elif"; a.caba = "auto"
        let yeni = Ayarlar(defaults: d)
        #expect(yeni.gorunum == a.gorunum)
        #expect(yeni.sesKimligi == "azure:Elif" && yeni.caba == "auto" && yeni.modelKimligi == "claude-opus-5-5")
        let json = String(decoding: try a.gorunum.veri(), as: UTF8.self)
        #expect(!json.contains("azure") && !json.contains("claude") && !json.contains("token"))
        d.set(Data("broken".utf8), forKey: "ayar.gorunumV1")
        #expect(Ayarlar(defaults: d).gorunum == GorunumTercihleri())
    }
}

@Suite("Kişisel alan kalıcılığı") @MainActor
struct KisiselAlanTestleri {
    private func konum() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "test.json")
    }
    @Test func komutEkleDuzenleSiralaSilVeYenidenAc() throws {
        let url = try konum(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let alan = KisiselAlan(dosya: url)
        var k = HazirKomut(baslik: "Kendi komutum", metin: "Yalnız taslak")
        #expect(alan.komutKaydet(k)); k.metin = "Değişti"; #expect(alan.komutKaydet(k))
        alan.tasi(IndexSet(integer: 6), hedef: 0)
        let yeni = KisiselAlan(dosya: url)
        #expect(yeni.icerik.komutlar.first == k)
        yeni.komutSil(k.id)
        #expect(KisiselAlan(dosya: url).icerik.komutlar.count == 6)
    }
    @Test func yanitlarTekrarlanmazVeSilmeKalici() throws {
        let url = try konum(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let alan = KisiselAlan(dosya: url)
        #expect(alan.yanitKaydet("Yanıt")); #expect(alan.yanitKaydet("Yanıt"))
        #expect(alan.icerik.yanitlar.count == 1)
        let yeni = KisiselAlan(dosya: url)
        #expect(yeni.kayitli("Yanıt"))
        yeni.yanitSil(try #require(yeni.icerik.yanitlar.first?.id))
        #expect(KisiselAlan(dosya: url).icerik.yanitlar.isEmpty)
    }
    @Test func bozukDosyaUzerineYazilmazVeKayitHatasiGorunur() throws {
        let url = try konum(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let veri = Data("not valid json".utf8); try veri.write(to: url)
        let alan = KisiselAlan(dosya: url)
        #expect(alan.hata != nil); #expect(!alan.yanitKaydet("Yeni"))
        #expect(try Data(contentsOf: url) == veri)
        let yok = KisiselAlan(dosya: url.appending(path: "missing/file.json"))
        #expect(!yok.yanitKaydet("Kaybolmamalı")); #expect(yok.icerik.yanitlar.isEmpty); #expect(yok.hata != nil)
    }
    @Test func sinirlarBoslukVeHareket() throws {
        let url = try konum(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let alan = KisiselAlan(dosya: url)
        #expect(!alan.komutKaydet(.init(baslik: "  ", metin: "test")))
        #expect(!alan.komutKaydet(.init(baslik: "Uzun", metin: String(repeating: "x", count: 4001))))
        #expect(!alan.yanitKaydet("\n  "))
        let ilk = alan.icerik.komutlar[0]; alan.tasi(IndexSet(integer: 0), hedef: 6)
        #expect(alan.icerik.komutlar.last == ilk)
        alan.tasi(IndexSet(integer: 99), hedef: 0)
        #expect(alan.icerik.komutlar.count == 6)
    }
    @Test func yedekTasimaVeGecersizYedekMevcutIcerigiKorur() throws {
        let kaynakURL = try konum(); let hedefURL = try konum()
        defer { try? FileManager.default.removeItem(at: kaynakURL.deletingLastPathComponent()); try? FileManager.default.removeItem(at: hedefURL.deletingLastPathComponent()) }
        let kaynak = KisiselAlan(dosya: kaynakURL)
        #expect(kaynak.komutKaydet(.init(baslik: "Yedek", metin: "Taşınacak komut")))
        let veri = try kaynak.yedekVerisi()
        let hedef = KisiselAlan(dosya: hedefURL)
        #expect(hedef.yedegiYukle(veri))
        #expect(hedef.icerik.komutlar.last?.baslik == "Yedek")
        let onceki = hedef.icerik
        #expect(!hedef.yedegiYukle(Data("bozuk".utf8)))
        #expect(hedef.icerik == onceki)
    }
}

@Suite("Fotoğraf düzenleme işlemleri") @MainActor
struct FotoIslemTestleri {
    private func resim(_ w: CGFloat, _ h: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: FotoIslem.bicim()).image { c in
            UIColor.red.setFill(); c.fill(CGRect(x: 0, y: 0, width: w / 2, height: h))
            UIColor.blue.setFill(); c.fill(CGRect(x: w / 2, y: 0, width: w / 2, height: h))
        }
    }

    @Test func kirpmaPikselOraninaUyar() {
        let k = FotoIslem.kirp(resim(400, 200), CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        #expect(k.cgImage?.width == 200 && k.cgImage?.height == 100)
    }
    @Test func tamCerceveVeTasanKirpmaGuvenli() {
        let r = resim(100, 50)
        #expect(FotoIslem.kirp(r, CGRect(x: 0, y: 0, width: 1, height: 1)) === r)
        let tasan = FotoIslem.kirp(r, CGRect(x: 0.5, y: 0.5, width: 2, height: 2))
        #expect(tasan.cgImage?.width == 50 && tasan.cgImage?.height == 25)
    }
    @Test func dondurmeEnBoyuDegistirir() {
        let d = FotoIslem.dondur(resim(300, 100))
        #expect(d.size == CGSize(width: 100, height: 300))
    }
    @Test func sigdirmaOraniKorur() {
        #expect(FotoIslem.sigdir(CGSize(width: 400, height: 200), CGSize(width: 100, height: 100)) == CGSize(width: 100, height: 50))
        #expect(FotoIslem.sigdir(.zero, CGSize(width: 100, height: 100)) == .zero)
    }
    @Test func kucultmeEkranOlceginiKullanmaz() {
        let cg = resim(4000, 2000).kucultulmus(1280)
        #expect(cg?.width == 1280 && cg?.height == 640)
    }
    @Test func taranmisSayfaDahaBuyukGonderilir() {
        #expect(GorselEk(resim: resim(10, 10), tur: .sayfa).kenar > GorselEk(resim: resim(10, 10)).kenar)
    }
}

@Suite("Araç hatası sunumu") @MainActor
struct AracHatasiTestleri {
    struct Hata: LocalizedError { var errorDescription: String? { "Klasör yok." } }
    @Test func aracHatasiModeleSonucOlarakDoner() {
        let m = IzlenenArac<DosyaAraci>.hataSonucu(Hata())
        #expect(m.contains("Klasör yok.") && m.contains("teknik ayrıntı gösterme"))
    }
    @Test func sarmalHatadaYalnizAsilNedenGosterilir() {
        struct Sarmal: LocalizedError { var errorDescription: String? { "An error occurred while invoking the tool: X(asil: Y) Underlying error: Önce klasör seç." } }
        #expect(Beyin.hataMetni(Sarmal()) == "Önce klasör seç.")
    }
}

@Suite("Sohbet teması") @MainActor
struct SohbetTemasiTestleri {
    @Test func eskiProfilClaudeTemasiylaAcilir() throws {
        // sohbet alanı olmayan eski kayıt çözülebilmeli; tema Claude'a düşer.
        var eski = GorunumTercihleri(); eski.sohbet = nil
        let veri = try JSONEncoder().encode(eski)
        let cozulen = try GorunumTercihleri.coz(veri)
        #expect(cozulen.sohbet == nil && cozulen.sohbetTemasi == .karma)   // 20 Eki 2026: varsayılan Karma
    }
    @Test func hazirTemalarGecerliVeTasinir() throws {
        for h in SohbetTemasi.hazirlar {
            #expect(h.gecerli(), "\(h.ad)")
            var g = GorunumTercihleri(); g.sohbet = h
            #expect(try GorunumTercihleri.coz(g.veri()).sohbetTemasi == h)
        }
    }
    @Test func gecersizRenkProfiliReddedilir() {
        var g = GorunumTercihleri(); var t = SohbetTemasi.claude; t.acik.zemin = "zzz"; g.sohbet = t
        #expect(throws: (any Error).self) { try g.veri() }
        var k = SohbetTemasi.telegram; k.kose = 90
        #expect(!k.gecerli())
    }
    @Test func ayarDegisinceEtkinTemaGuncellenir() {
        let d = UserDefaults(suiteName: "tema-test-\(UUID().uuidString)")!
        let a = Ayarlar(defaults: d)
        #expect(SohbetTemaDeposu.ortak.tema == .karma && a.gorunum.renk == "D97757")
        a.gorunum.sohbet = .telegram
        #expect(SohbetTemaDeposu.ortak.tema == .telegram)
        a.gorunum.sohbet = .claude
    }
}

@Suite("Model kısa adları") @MainActor
struct ModelKisaAdTestleri {
    @Test func kisaAdlarOkunur() {
        #expect(TelefonProxy.Model.kisaAd("claude-opus-5-5") == "Opus 5.5")
        #expect(TelefonProxy.Model.kisaAd("claude-haiku-4-5") == "Haiku 4.5")
        #expect(TelefonProxy.Model.kisaAd("gpt-6.1-sol") == "GPT 6.1 Sol")
        #expect(TelefonProxy.Model.kisaAd("gemini-3.8-flash") == "Gemini 3.8 Flash")
        #expect(TelefonProxy.Model.kisaAd("antigravity-claude-sonnet-5-5-low") == "Sonnet 5.5 Low · AG")
    }
}

@Suite("Ajan katmanı") @MainActor
struct AjanKatmaniTestleri {
    private func defter() -> AjanDefteri {
        AjanDefteri(defaults: UserDefaults(suiteName: "ajan-\(UUID().uuidString)")!, dosya: FileManager.default.temporaryDirectory.appending(path: "ajan-\(UUID().uuidString).json"))
    }
    @Test func izinPolitikasiVeButce() {
        let d = defter()
        #expect(d.karar("takvim") == .gec)
        d.politikaAta("takvim", .kapali); #expect(d.karar("takvim") == .kapali)
        d.politikaAta("takvim", .sor); #expect(d.karar("takvim") == .sor)
        d.politikaAta("takvim", .otomatik); #expect(d.politika("takvim") == .otomatik)
        d.adimButcesi = 2; d.gorevBaslat("x")
        #expect(d.karar("a") == .gec); #expect(d.karar("b") == .gec); #expect(d.karar("c") == .butceDoldu)
        d.gorevBaslat("y"); #expect(d.karar("a") == .gec, "her istekte bütçe sıfırlanır")
        d.adimButcesi = 1; d.gorevBaslat("z"); _ = d.karar("web")
        #expect(d.karar("web") == .butceDoldu && d.karar("ofisBelgesiOlustur") == .gec && d.karar("excelOlustur") == .gec, "çıktı araçları bütçeden muaf")
        #expect(d.kalanButce == 0)
    }
    @Test func gorevKaydiAdimlariTutar() {
        let d = defter()
        d.gorevBaslat("Takvimi düzenle")
        let a = d.adimBaslat("takvim"); d.adimBitir(a, durum: "Tamam")
        d.gorevBitir(model: "claude-sonnet-5-5", sonuc: "Bitti", durum: "Tamamlandı")
        #expect(d.gorevler.first?.adimlar.map(\.durum) == ["Tamam"])
        #expect(d.gorevler.first?.durum == "Tamamlandı" && d.gorevler.first?.model == "claude-sonnet-5-5")
    }
    @Test func pahaliModelButcesi() {
        let d = defter()
        #expect(d.butceyeGoreSuz(["claude-opus-5-5", "claude-sonnet-5-5"], zorla: nil).count == 2, "sınırsız")
        d.pahaliGunlukSinir = 1
        d.gorevBaslat("a"); d.gorevBitir(model: "claude-opus-5-5", sonuc: "", durum: "Tamamlandı")
        #expect(d.butceyeGoreSuz(["claude-opus-5-5", "claude-sonnet-5-5"], zorla: nil) == ["claude-sonnet-5-5"])
        #expect(d.butceyeGoreSuz(["claude-opus-5-5"], zorla: nil) == ["claude-opus-5-5"], "yalnız pahalı varsa liste korunur")
        #expect(d.butceyeGoreSuz(["claude-fable-5-1", "gpt-6.1-sol"], zorla: "claude-fable-5-1") == ["claude-fable-5-1", "gpt-6.1-sol"], "elle yeniden üretim hariç")
    }
    @Test func sayisalSaglama() {
        #expect(SayiSaglama.denetle("12 × 7 = 84 ve 15 + 27 = 42").isEmpty)
        let b = SayiSaglama.denetle("Toplam: 125 + 38 = 153 eder.")
        #expect(b.count == 1 && b[0].contains("163"))
        #expect(SayiSaglama.denetle("22 / 7 = 3,14").isEmpty, "yuvarlama hata değil")
        #expect(SayiSaglama.denetle("1.250 + 250 = 1.500").isEmpty, "binlik ayırıcılı sayı atlanır")
    }
    @Test func denetimNotuVeBeceriTaslagi() {
        #expect(Beyin.denetimNotu("TAMAM") == nil)
        #expect(Beyin.denetimNotu("DÜZELTME: 29 Ekim Çarşamba değil Perşembe.") == "Denetim: 29 Ekim Çarşamba değil Perşembe.")
        let b = Beyin.beceriTaslagi("AD: Haftalık Rapor\nACIKLAMA: Haftalık durum raporu hazırlar.\nADIMLAR:\n1. Takvime bak\n2. Özetle")
        #expect(b?.ad == "haftalik-rapor" && b?.icerik.contains("Takvime bak") == true)
        #expect(Beyin.elestirmenGerekli(yanit: String(repeating: "a", count: 200) + " 2026 12 34", caba: .low, canliSes: false))
        #expect(!Beyin.elestirmenGerekli(yanit: "Merhaba!", caba: .high, canliSes: false))
    }
    @Test func tetikIstemiVeAltAjanTuru() {
        let t = Tetik(ad: "Ders", tur: .takvim, istem: "{etkinlik} için not ver")
        #expect(t.istem(etkinlik: "Biyoloji 10-A") == "Biyoloji 10-A için not ver")
        #expect(AltAjanAraci.gorevCoz("arac: Yarın Ankara'da hava?") == .init(tur: "arac", istek: "Yarın Ankara'da hava?"))
        #expect(AltAjanAraci.gorevCoz("araştır: nüfus") == .init(tur: "arastir", istek: "nüfus"))
        #expect(GecmisAramaAraci.genislemeTemizle("harcama, maliyet;\ngider, x, para!") == "harcama maliyet gider para")
    }
    @Test func projeTalimati() {
        var p = Proje(ad: "Okul"); p.baglam = "Cumhuriyet Lisesi"; p.notlar = ["Sınavlar Kasım'da"]
        #expect(p.talimat.contains("Etkin proje: Okul") && p.talimat.contains("Sınavlar Kasım'da"))
    }
}

@Suite("Tarayıcı ajanı ve paylaşım") @MainActor
struct TarayiciVePaylasimTestleri {
    @Test func sayfaOkunurAlanDoldurulurTiklanir() async {
        let t = TarayiciOturumu()
        t.web.loadHTMLString("""
        <html><head><title>Deneme</title></head><body><h1>Kayıt formu</h1>
        <input id="ad" placeholder="Adınız"><button id="b" onclick="document.title='tiklandi:'+document.getElementById('ad').value">Devam</button>
        <a href="#x">Yardım</a></body></html>
        """, baseURL: URL(string: "https://ornek.test/"))
        await t.yuklemeyiBekle(sinir: 10)
        let d = await t.durum()
        #expect(d.contains("Başlık: Deneme") && d.contains("Kayıt formu"))
        #expect(d.contains("1. input") && d.contains("Adınız") && d.contains("2. button") && d.contains("Devam") && d.contains("3. a"))
        #expect(await t.js(TarayiciOturumu.yazJS(1, "Mehmet \"ö\"")) as? Bool == true)
        #expect(await t.js(TarayiciOturumu.tiklaJS(2)) as? Bool == true)
        #expect(await t.js("document.title") as? String == "tiklandi:Mehmet \"ö\"")
        #expect(await t.js(TarayiciOturumu.ogeMetniJS(99)) as? String == nil)
    }
    @Test func riskliAdimlarTaninir() {
        #expect(TarayiciOturumu.riskli("Siparişi onayla submit"))
        #expect(TarayiciOturumu.riskli("Ödemeyi tamamla"))
        #expect(TarayiciOturumu.riskli("Hesabı sil"))
        #expect(!TarayiciOturumu.riskli("Devam"))
        #expect(!TarayiciOturumu.riskli("Yardım"))
    }
    @Test func paylasimIstemi() {
        var i = PaylasimKutusu.Istek(istem: "Özetle"); i.baglanti = "https://a.com"; i.metin = "uzun metin"
        let s = PaylasimKutusu.istemMetni(i)
        #expect(s.hasPrefix("Özetle") && s.contains("Bağlantı: https://a.com") && s.contains("[Paylaşılan metin"))
        #expect(PaylasimKutusu.istemMetni(.init(istem: " ")).hasPrefix("Bunu incele"))
    }
    @Test func zorunluOnayTesteDiyalogAcmaz() async {
        let o = OnayKapisi(); o.otomatikKarar = true
        #expect(await o.iste(baslik: "x", ayrinti: "y", zorunlu: true), "test sürecinde zorunlu onay da otomatik karara uyar")
    }
    @Test func goruntuMesajiBicimi() {
        let m = OpenAIRealtimeMesajlari.goruntuMesaji(Data([1, 2, 3]))
        let icerik = ((m["item"] as? [String: Any])?["content"] as? [[String: Any]])?.first
        #expect(m["type"] as? String == "conversation.item.create")
        #expect(icerik?["type"] as? String == "input_image" && (icerik?["image_url"] as? String)?.hasPrefix("data:image/jpeg;base64,") == true)
    }
}

@Suite("İnceleme regresyonları") @MainActor
struct IncelemeRegresyonTestleri {
    @Test func sayisalSaglamaKesirVeOncelikteYanlisAlarmVermez() {
        #expect(SayiSaglama.denetle("Aa × Aa için 1/2 × 1/2 = 1/4 olasılık").isEmpty)
        #expect(SayiSaglama.denetle("2 + 3 × 4 = 14").isEmpty)
        #expect(SayiSaglama.denetle("Sonuç 3 × 4 = 13 çıkar.").count == 1, "tek başına yanlış işlem yine yakalanır")
    }
    @Test func turkceBuyukHarfliRiskliDugmeler() {
        #expect(TarayiciOturumu.riskli("SİL"))
        #expect(TarayiciOturumu.riskli("SİPARİŞİ TAMAMLA"))
        #expect(TarayiciOturumu.riskli("Hemen Al"))
        #expect(TarayiciOturumu.riskli("Complete purchase"))
        #expect(!TarayiciOturumu.riskli("SONRAKİ SAYFA"))
    }
    @Test func kestirmeYalnizKendiIstegininYanitiniAlir() async {
        let k = GorevKopru.ortak
        let bekleyen = Task { await k.calistir("kestirme-test-\(UUID())", sinir: 5) }
        try? await Task.sleep(for: .milliseconds(100))
        k.bitti("başka sohbetin özel yanıtı", nesil: 999_999)   // eşleşmeyen nesil: yok sayılmalı
        if let b = k.beklenen { k.kabul(b, nesil: 4242) }
        k.bitti("doğru yanıt", nesil: 4242)
        #expect(await bekleyen.value == "doğru yanıt")
    }
    @Test func projeAyrintisiNotlariEzmez() {
        let d = ProjeDeposu(dosya: FileManager.default.temporaryDirectory.appending(path: "p-\(UUID()).json"), defaults: UserDefaults(suiteName: "p-\(UUID())")!)
        let p = d.ekle("Okul")!; d.aktifKimlik = p.id
        _ = d.notEkle("ilk")
        let eskiKopya = d.projeler[0]          // ekran açılırken alınan kopya
        _ = d.notEkle("ajanın notu")            // ekran açıkken eklenen
        d.adBaglamGuncelle(eskiKopya.id, ad: "Okul 2", baglam: "yeni bağlam")
        #expect(d.projeler[0].notlar == ["ilk", "ajanın notu"] && d.projeler[0].ad == "Okul 2")
    }
}

@Suite("Arka plan sürdürme") @MainActor
struct ArkaPlanSurdurmeTestleri {
    @Test func acilistanSonraGorevIstemekCokertmez() {
        // Kayıtsız gönderim BGTaskScheduler'da assertion ile çöküyordu (19 Eki); görev başına kayıt + gönderim güvenli olmalı.
        ArkaPlanSurdurucu.ortak.baslat("bitince haber ver: test görevi")
        ArkaPlanSurdurucu.ortak.ilerle(adim: 2)
        ArkaPlanSurdurucu.ortak.bitti("tamam")
        #expect(!ArkaPlanSurdurucu.ortak.istendi)
        #expect(ArkaPlanSurdurucu.uzunMu("bunu araştır, bitince haber ver", caba: .low, kip: .sohbet))
        #expect(!ArkaPlanSurdurucu.uzunMu("selam", caba: .low, kip: .sohbet))
    }
}

@Suite("Veri kazıma ve önizleme") @MainActor
struct VeriKazimaTestleri {
    let kaynak = URL(string: "https://ornek.com/liste/")!
    let html = """
    <html><body><nav>menü</nav><table><caption>Fiyat listesi</caption><tr><th>Ürün</th><th>Fiyat</th></tr>
    <tr><td><b>Elma</b></td><td>12&nbsp;TL</td></tr><tr><td>Armut</td><td>15 TL</td></tr></table>
    <table><tr><td>tek</td></tr></table>
    <a href="/dosya/rapor.pdf">2025 Raporu</a> <a href="belge.docx">Belge</a> <a href="http://kotu.com/x.pdf">http</a>
    <a href="/sayfa/2" rel="next">Sonraki</a><script>var x=1</script><p>Görünür paragraf</p></body></html>
    """
    @Test func htmlTablosuBasliklariylaCikarilir() {
        let t = Kaziyici.tablolar(html)
        #expect(t.count == 1, "tek sütunlu tablo atlanır")
        #expect(t[0].baslik == "Fiyat listesi" && t[0].sutunlar == ["Ürün", "Fiyat"])
        #expect(t[0].satirlar == [["Elma", "12 TL"], ["Armut", "15 TL"]])
    }
    @Test func baglantilarMutlakHttpsVeSuzulur() {
        let b = Kaziyici.baglantilar(html, kaynak: kaynak)
        #expect(b.contains { $0.url.absoluteString == "https://ornek.com/dosya/rapor.pdf" && $0.metin == "2025 Raporu" })
        #expect(!b.contains { $0.url.scheme == "http" }, "http atlanır")
        #expect(Kaziyici.suz(b, "pdf").map(\.url.lastPathComponent) == ["rapor.pdf"])
        #expect(Kaziyici.suz(b, "pdf,docx").count == 2)
        #expect(Kaziyici.suz(b, "rapor").count == 1, "sözcük süzgeci")
    }
    @Test func sonrakiSayfaVeGorunurMetin() {
        #expect(Kaziyici.sonrakiSayfa(html, kaynak: kaynak)?.absoluteString == "https://ornek.com/sayfa/2")
        let m = Kaziyici.gorunurMetin(html)
        #expect(m.contains("Görünür paragraf") && !m.contains("var x") && !m.contains("menü"))
    }
    @Test func alanTablosuVeCsv() {
        let t = Kaziyici.alanTablosu("İşte: [{\"ad\":\"Kalem\",\"fiyat\":5},{\"Ad\":\"Defter\",\"fiyat\":\"20\"}] bitti", alanlar: ["ad", "fiyat"])
        #expect(t?.satirlar == [["Kalem", "5"], ["Defter", "20"]])
        #expect(Kaziyici.alanTablosu("yok", alanlar: ["ad"]) == nil)
        let csv = String(decoding: Kaziyici.csv(.init(baslik: "x", sutunlar: ["a", "b"], satirlar: [["1", "x\"y"]])), as: UTF8.self)
        #expect(csv.contains("\"a\";\"b\"") && csv.contains("\"x\"\"y\""))
    }
    @Test func ekDefteriKaynaklariBirlestirir() {
        let d = EkDefteri()
        d.ekle(MesajEki(tur: .kaynaklar(["https://a.com", "https://b.com"])))
        d.ekle(MesajEki(tur: .kaynaklar(["https://b.com", "https://c.com"])))
        d.ekle(MesajEki(tur: .indirme(UUID())))
        let ekler = d.al()
        #expect(ekler.count == 2 && d.bekleyen.isEmpty)
        if case .kaynaklar(let k) = ekler[0].tur { #expect(k == ["https://a.com", "https://b.com", "https://c.com"]) } else { Issue.record("kaynak kartı yok") }
        #expect(EkDefteri.kaynaklar("Yanıt\nKaynaklar:\nhttps://x.com/a\nhttps://y.org\nnot") == ["https://x.com/a", "https://y.org"])
    }
    @Test func aramaSorgusuKurulur() {
        #expect(WebArastirici.sorguKur("kayıt takvimi", site: "https://www.meb.gov.tr/duyuru", guncel: true).contains("site:www.meb.gov.tr"))
        #expect(WebArastirici.sorguKur("x", site: "", guncel: false) == "x")
    }
}

@Suite("Medya kazıma") @MainActor
struct MedyaKazimaTestleri {
    @Test func herTurMedyaBulunur() {
        let html = """
        <html><head><meta property="og:image" content="https://cdn.ornek.com/kapak.jpg"><meta property="og:video" content="https://cdn.ornek.com/tanitim.mp4"></head><body>
        <img src="/foto/buyuk.png" alt="Hücre çizimi" width="800"><img src="/ikon.png" width="16"><img src="data:image/png;base64,AAA"><img src="/logo.svg">
        <video src="https://v.ornek.com/ders.mp4" title="Ders videosu"></video><audio><source src="/ses/bolum1.mp3" type="audio/mpeg"></audio>
        <iframe src="https://www.youtube.com/embed/dQw4w9WgXcQ" title="YouTube"></iframe>
        <a href="https://youtu.be/abc123">Kısa</a><a href="/kitap/biyoloji.epub">Biyoloji kitabı</a><a href="/belge.pdf">Rapor</a><a href="/canli.m3u8">Canlı</a>
        <enclosure url="https://pod.ornek.com/b2.m4a" type="audio/mp4"/></body></html>
        """
        let m = Kaziyici.medya(html, kaynak: URL(string: "https://ornek.com/sayfa")!)
        func var_(_ t: MedyaOgesi.Tur, _ son: String) -> Bool { m.contains { $0.tur == t && $0.url.absoluteString.hasSuffix(son) } }
        #expect(var_(.gorsel, "kapak.jpg") && var_(.gorsel, "foto/buyuk.png"))
        #expect(!m.contains { $0.url.absoluteString.hasSuffix("ikon.png") || $0.url.absoluteString.hasSuffix("logo.svg") || $0.url.scheme == "data" }, "küçük/svg/data atlanır")
        #expect(var_(.video, "tanitim.mp4") && var_(.video, "ders.mp4") && var_(.video, "canli.m3u8"))
        #expect(var_(.ses, "bolum1.mp3") && var_(.ses, "b2.m4a"))
        #expect(var_(.youtube, "dQw4w9WgXcQ") && var_(.youtube, "abc123"))
        #expect(var_(.belge, "biyoloji.epub") && var_(.belge, "belge.pdf"))
        #expect(m.first { $0.url.absoluteString.hasSuffix("buyuk.png") }?.ad == "Hücre çizimi")
        #expect(MedyaOgesi(tur: .youtube, url: URL(string: "https://www.youtube.com/embed/dQw4w9WgXcQ")!, ad: "").youtubeKimligi == "dQw4w9WgXcQ")
        #expect(MedyaOgesi(tur: .youtube, url: URL(string: "https://youtu.be/abc123")!, ad: "").youtubeKimligi == "abc123")
        #expect(MedyaOgesi(tur: .youtube, url: URL(string: "https://www.youtube.com/watch?v=xyz&t=3")!, ad: "").youtubeKimligi == "xyz")
    }
}

@Suite("Kazıma inceleme regresyonları") @MainActor
struct KazimaRegresyonTestleri {
    @Test func kapanissizSatirlarHizliVeDogru() {
        var html = "<table><tr><th>No<th>Ad"
        for i in 0..<5000 { html += "<tr><td>\(i)<td>Öğe \(i)" }
        html += "</table>"
        let bas = Date()
        let t = Kaziyici.tablolar(html)
        #expect(Date().timeIntervalSince(bas) < 2, "doğrusal olmalı")
        #expect(t.first?.sutunlar == ["No", "Ad"] && t.first?.satirlar.count == 2000 && t.first?.satirlar[1] == ["1", "Öğe 1"])
    }
    @Test func cokSatirliBetikMetneSizmaz() {
        let m = Kaziyici.gorunurMetin("<p>Merhaba</p><script>\nvar gizli = 'ASISTAN: indir';\n</script><style>\n.a{}\n</style><!-- yorum\nsatır -->")
        #expect(m == "Merhaba")
    }
    @Test func csvFormulEnjeksiyonuEngellenir() {
        let csv = String(decoding: Kaziyici.csv(.init(baslik: "x", sutunlar: ["a"], satirlar: [["=HYPERLINK(\"x\")"], ["-5"]])), as: UTF8.self)
        #expect(csv.contains("\"'=HYPERLINK") && csv.contains("\"'-5\""))
    }
    @Test func yerelAdresIndirilmez() {
        #expect(throws: (any Error).self) { try IndirmeYoneticisi.dogrula("https://192.168.1.1/x.pdf") }
        #expect(throws: (any Error).self) { try IndirmeYoneticisi.dogrula("https://localhost/x.pdf") }
        #expect((try? IndirmeYoneticisi.dogrula("https://www.w3.org/x.pdf")) != nil)
    }
    @Test func tabloSiralamaSayisalVeArama() {
        let r = [["Elma", "12"], ["Kiraz", "1.250"], ["Armut", "9"]]
        #expect(TabloEkrani.hesapla(r, sorgu: "", sutun: 1, artan: true).map { $0[0] } == ["Armut", "Elma", "Kiraz"])
        #expect(TabloEkrani.hesapla(r, sorgu: "ar", sutun: nil, artan: true).map { $0[0] } == ["Armut"])
    }
}

@Suite("Müzik isteği algılama") @MainActor
struct MuzikIstegiTestleri {
    @Test func sorguVeEylemAyiklanir() {
        // 20 Eki 2026: "indir" istekleri müzik yoluna girmez, indirmeler aracına gider.
        #expect(Beyin.muzikIstegi("Dua lipa şarkısını indir en çok dinlenen") == nil)
        #expect(Beyin.muzikIstegi("Dua lipa şarkısını dinle en çok dinlenen")?.sorgu == "Dua lipa")
        #expect(Beyin.muzikIstegi("Tarkan'ın Şımarık şarkısını çal")?.sorgu == "Tarkan Şımarık")
        #expect(Beyin.muzikIstegi("Tarkan'ın Şımarık şarkısını çal")?.cal == true)
        #expect(Beyin.muzikIstegi("Bugün hava nasıl?") == nil)
        #expect(Beyin.muzikIstegi("https://a.com/sarki.mp3 indir") == nil)
        #expect(Beyin.muzikIstegi("şarkı indir") == nil, "sorgu yoksa normal yol")
    }
}

@Suite("Konuşma bağlamı") @MainActor
struct KonusmaBaglamiTestleri {
    private func beyin() -> Beyin {
        let d = UserDefaults(suiteName: "baglam-\(UUID())")!
        let kap = HafizaDeposu.paylasilanKap
        return Beyin(ayarlar: Ayarlar(defaults: d), depo: HafizaDeposu(baglam: kap.mainContext), onay: OnayKapisi())
    }
    @Test func tazeOturumEkrandakiKonusmayiTasir() {
        let b = beyin()
        b.mesajlar = [Beyin.Goruntu(rol: .kullanici, metin: "Adım Mehmet, 10-A sınıfına girerim"),
                      Beyin.Goruntu(rol: .asistan, metin: "Tamam Mehmet.", ekler: [MesajEki(tur: .dosya(url: URL(filePath: "/tmp/x.pdf"), ad: "tarife.pdf"))]),
                      Beyin.Goruntu(rol: .kullanici, metin: "Hangi sınıfa girerim?")]   // güncel istek
        let g = b.mesajlardanGecmis()
        #expect(g.count == 2, "tek soru-yanıt çifti")
        let metin = g.map { "\($0)" }.joined()
        #expect(metin.contains("10-A") && metin.contains("tarife.pdf"), "ek notu da taşınır")
        #expect(!metin.contains("Hangi sınıfa"), "güncel istek geçmişe girmez")
    }
    @Test func iptalSonrasiBaglamKaybolmaz() {
        let b = beyin()
        b.mesajlar = [Beyin.Goruntu(rol: .kullanici, metin: "a"), Beyin.Goruntu(rol: .asistan, metin: "b"), Beyin.Goruntu(rol: .kullanici, metin: "c")]
        b.disGecmis = []                         // iptal/yeni oturum durumu
        #expect(!b.mesajlardanGecmis().isEmpty)
    }
}

@Suite("Hata metinleri") @MainActor
struct HataMetniTestleri {
    @Test func zamanAsimiTurkceGelir() {
        let m = Beyin.hataMetni(URLError(.timedOut))
        #expect(m.contains("zamanında yanıt vermedi") && !m.contains("timed out"))
    }
}

@Suite("Kalıcı mesaj ekleri") @MainActor
struct KaliciEkTestleri {
    @Test func kartlarKodlanipAyniGeriGelir() {
        let dosya = IndirmeYoneticisi.klasor.appending(path: "ABC-tarife.pdf")
        let id = UUID()
        let ekler = [MesajEki(tur: .dosya(url: dosya, ad: "tarife.pdf")),
                     MesajEki(tur: .indirme(id)),
                     MesajEki(tur: .tablo(baslik: "Fiyatlar", sutunlar: ["a", "b"], satirlar: (0..<500).map { ["\($0)", "x"] }, kaynak: "https://a.com", dosya: dosya)),
                     MesajEki(tur: .kaynaklar(["https://a.com", "https://b.com"])),
                     MesajEki(tur: .medya([MedyaOgesi(tur: .youtube, url: URL(string: "https://youtu.be/x1")!, ad: "Klip"), MedyaOgesi(tur: .belge, url: URL(string: "https://a.com/k.pdf")!, ad: "Kitap")]))]
        let veri = EkKalici.kodla(ekler)
        #expect(veri != nil)
        let geri = EkKalici.coz(veri)
        #expect(geri.count == 5)
        if case .dosya(let u, let ad) = geri[0].tur { #expect(u == dosya && ad == "tarife.pdf") } else { Issue.record("dosya") }
        if case .indirme(let k) = geri[1].tur { #expect(k == id) } else { Issue.record("indirme") }
        if case .tablo(_, _, let r, let k, let d) = geri[2].tur { #expect(r.count == EkKalici.enFazlaSatir && k == "https://a.com" && d == dosya) } else { Issue.record("tablo") }
        if case .medya(let m) = geri[4].tur { #expect(m.map(\.tur) == [.youtube, .belge]) } else { Issue.record("medya") }
        let ham = String(decoding: veri ?? Data(), as: UTF8.self)
        #expect(ham.contains("I:ABC-tarife.pdf") && !ham.contains("/Documents/"), "kap yolu değil, göreli ad saklanır")
    }
    @Test func bosVeBozukVeriGuvenli() {
        #expect(EkKalici.kodla([]) == nil && EkKalici.coz(nil).isEmpty && EkKalici.coz(Data("bozuk".utf8)).isEmpty)
    }
    @Test func eskiSohbetAcilincaKartlarVeFotograflarGeriGelir() throws {
        let d = UserDefaults(suiteName: "kalici-\(UUID())")!
        let depo = HafizaDeposu(baglam: HafizaDeposu.paylasilanKap.mainContext)
        let b = Beyin(ayarlar: Ayarlar(defaults: d), depo: depo, onay: OnayKapisi())
        let s = depo.sohbetOlustur()
        let ad = EkKalici.gorselleriKaydet([UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20)).image { c in UIColor.red.setFill(); c.fill(CGRect(x: 0, y: 0, width: 40, height: 20)) }])
        depo.ekle(.kullanici, "📷 Bu ne?", sohbet: s, gorselAdlari: ad)
        depo.ekle(.asistan, "Kırmızı bir şerit.", sohbet: s, ekler: [MesajEki(tur: .kaynaklar(["https://a.com"])), MesajEki(tur: .dosya(url: IndirmeYoneticisi.klasor.appending(path: "x.pdf"), ad: "x.pdf"))])
        b.sohbetiAc(s)
        #expect(b.mesajlar.count == 2)
        #expect(b.mesajlar[0].resimler.isEmpty && b.mesajlar[0].gorselAdlari == ad && FileManager.default.fileExists(atPath: EkKalici.gorselURL(ad[0]).path), "fotoğraf adla geri geldi (P3.9: küçük resim balonda yüklenir)")
        #expect(b.mesajlar[1].ekler.count == 2, "kartlar geri geldi")
    }
}

@Suite("Hafıza veritabanı") @MainActor
struct HafizaVeritabaniTestleri {
    nonisolated(unsafe) private static var kaplar: [ModelContainer] = []   // context'ten uzun yaşamalı (yoksa SwiftData çöker)
    private func depo() -> HafizaDeposu {
        let k = HafizaDeposu.kapOlustur(bellekte: true); Self.kaplar.append(k)
        return HafizaDeposu(baglam: k.mainContext)
    }

    @Test func indeksTurkceOnekliBM25() {
        let ix = HafizaIndeksi(bellekte: true)
        ix.ekle(tur: .mesaj, kimlik: "1", sohbet: "A", metin: "Çocuklarım için Beykoz'daki okulları araştırıyorum")
        ix.ekle(tur: .mesaj, kimlik: "2", sohbet: "B", metin: "Yarın hava durumu nasıl olacak")
        ix.ekle(tur: .olgu, kimlik: "3", metin: "Kullanıcı Beykoz'da oturuyor")
        let r = ix.ara("OKULLAR hakkında", tur: .mesaj)
        #expect(r.map(\.kimlik) == ["1"] && r[0].metin.contains("Çocuklarım"), "Türkçe büyük harf/ek farkı ve özgün metin")
        #expect(ix.ara("okul", tur: .mesaj).map(\.kimlik) == ["1"], "kök önek eşleşir")
        #expect(ix.ara("beykoz", tur: .olgu).map(\.kimlik) == ["3"])
        #expect(ix.ara("Beykoz", tur: .mesaj, haricSohbet: "A").isEmpty, "bu sohbet hariç")
        ix.sil(kimlik: "1"); #expect(ix.ara("okul", tur: .mesaj).isEmpty)
        ix.sohbetiSil("B"); #expect(ix.say(tur: .mesaj) == 0)
    }
    @Test func terimlerDurakVeKisaSozcukleriAtar() {
        #expect(HafizaIndeksi.terimler("Bana en çok sevdiğim yemeği söyle") == ["sevdigim", "yemegi", "soyle"])
        #expect(HafizaIndeksi.terimler("ve bu de").isEmpty)
    }
    @Test func olguBicimiVeKategoriTahmini() {
        let c = OlguBicimi.coz("[tercih:4] Kullanıcı çayı şekersiz içer")
        #expect(c.kategori == .tercih && c.onem == 4 && c.metin == "Kullanıcı çayı şekersiz içer")
        #expect(OlguBicimi.coz("Düz olgu").kategori == nil && OlguBicimi.coz("[bilinmez:9] x").onem == 5)
        #expect(OlguKategorisi.tahmin("Kullanıcının eşi Ayşe") == .kisi && OlguKategorisi.tahmin("Fıstığa alerjisi var") == .saglik && OlguKategorisi.tahmin("Beykoz'da oturuyor") == .yer)
        #expect(OlguBicimi.benzerlik("Kullanıcı Beykoz'da oturuyor", "Kullanıcı Beykoz'da yaşıyor") > 0.3)
    }
    @Test func yakinKopyaGuncellenirSabitKorunur() throws {
        let d = depo()
        let ilk = d.hatirlaZengin("Kullanıcı Beykoz Cumhuriyet Mahallesi'nde oturuyor", kaynak: "cikarim", kategori: .yer, onem: 3)
        let ikinci = d.hatirlaZengin("[yer:4] Kullanıcı Beykoz Cumhuriyet Mahallesi'nde evde oturuyor", kaynak: "cikarim")
        #expect(d.olgular().count == 1 && ikinci?.kimlik == ilk?.kimlik, "yakın kopya güncellenir, çoğalmaz")
        #expect(d.olgular()[0].metin.contains("evde") && d.olgular()[0].onem == 4)
        d.olguAyarla(d.olgular()[0].kimlik, sabit: true)
        _ = d.hatirlaZengin("Kullanıcı Beykoz Cumhuriyet Mahallesi'nde apartmanda oturuyor", kaynak: "cikarim")
        #expect(d.olgular().count == 2 && d.olgular().first { $0.sabit == true }?.metin.contains("evde") == true, "sabitlenene dokunulmaz")
    }
    @Test func geriCagirmaOnemVeGecmisSohbetleri() throws {
        HafizaIndeksi.ortak.temizle()
        let d = depo()
        let s1 = d.sohbetOlustur(), s2 = d.sohbetOlustur()
        d.ekle(.kullanici, "Kedimin adı Pamuk, veteriner randevusu perşembe", sohbet: s1)
        d.ekle(.kullanici, "Bugün hava çok güzel", sohbet: s2)
        _ = d.hatirlaZengin("[kisi:5] Kullanıcının kedisi Pamuk", kaynak: "kullanici")
        _ = d.hatirlaZengin("[tercih:2] Kullanıcı kediyi mamayla besler", kaynak: "cikarim")
        // Talimata zaten giren olgular varsayılan olarak düşülür (60'tan az olguda hepsi talimatta); burada sıralama sınanır.
        let g = d.geriCagir("Pamuk için veteriner", haricSohbet: s2.kimlik, talimattakileriDus: false)
        #expect(g.olgular.first?.metin.contains("Pamuk") == true && (g.olgular.first?.kullanimSayisi ?? 0) == 1, "ilgili ve önemli olgu önde, kullanım işlenir")
        #expect(g.parcalar.contains { $0.metin.contains("veteriner") }, "geçmiş sohbetten parça")
        let metin = HafizaDeposu.geriCagirmaMetni(g)
        #expect(metin.contains("[Hafıza notu") && metin.contains("[Geçmiş sohbetlerden"))
        #expect(d.talimatOlgulari().first?.contains("Pamuk") == true, "talimatta önemli olgu başta, kategori etiketiyle")
        #expect(d.talimatOlgulari().first?.hasPrefix("[Kişi]") == true)
    }
    @Test func senkronEksikleriTamamlarSilinenleriDusurur() async throws {
        HafizaIndeksi.ortak.temizle()
        let d = depo()
        let s = d.sohbetOlustur()
        d.ekle(.kullanici, "Matematik sınavı cuma günü", sohbet: s)
        HafizaIndeksi.ortak.temizle()                 // indeks kayboldu
        #expect(HafizaIndeksi.ortak.ara("matematik").isEmpty)
        await d.indeksiSenkronla()
        #expect(HafizaIndeksi.ortak.ara("matematik").count == 1, "SwiftData'dan yeniden kuruldu")
        d.sohbetSil(s)
        #expect(HafizaIndeksi.ortak.ara("matematik").isEmpty)
    }
    @Test func yinelenenleriBirlestirir() {
        let d = depo()
        for m in ["Kullanıcı sabahları sade kahve içer", "Sabahları sade kahve içer kullanıcı", "Kullanıcının kedisi Pamuk"] { _ = d.hatirla(m, kaynak: "cikarim") }
        #expect(d.yinelenenleriBirlestir() == 1 && d.olgular().count == 2)
    }
}

@Suite("Yedek model güvenliği") @MainActor
struct YedekModelGuvenligiTestleri {
    @Test func okumaAraclariYedekDenemeyiEngellemez() {
        for ad in ["veriKazi", "webSayfaOku", "webArastir", "gecmisAra"] { #expect(GorevGunlugu.saltOkunurAraclar.contains(ad), "\(ad) salt okunur sayılmalı") }
        for ad in ["iletisim", "takvim", "hatirlatici", "indirmeler", "ofisBelgesiOlustur", "tarayici"] { #expect(!GorevGunlugu.saltOkunurAraclar.contains(ad), "\(ad) yan etkili sayılmalı") }
    }
}
