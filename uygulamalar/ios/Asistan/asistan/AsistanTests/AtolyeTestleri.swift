import Foundation
import Testing
@testable import Asistan

@Suite("Otomatik atölye") @MainActor
struct AtolyeTestleri {
    @Test func yerelSecimAgIstemedenDogruIslereGider() {
        #expect(AtolyeYonlendirme.yerel("Python ile CSV toplamı hesaplayan fonksiyon yaz") == .kod)
        #expect(AtolyeYonlendirme.yerel("Uzayda kütüphanenin suluboya resmini çiz") == .gorsel)
        #expect(AtolyeYonlendirme.yerel("Python nedir?") == .sohbet)
        #expect(AtolyeYonlendirme.yerel("Barış Manço'dan Gülpembe şarkısını aç") == .sohbet)
        #expect(AtolyeYonlendirme.yerel("Bana doğum günü mesajı hazırla") == .yazi)
        #expect(AtolyeYonlendirme.yerel("Resim üretme, açıklama metni yaz") == .yazi)
        #expect(AtolyeYonlendirme.yerel("Kitapyurdu'da Simyacı'nın bütününü bul Excel dosyasında ver") == .arastirma)
        #expect(!HizliModelSecimi.dogrudanArastirma("Kitapyurdu'da Simyacı'nın bütününü bul Excel dosyasında ver"))
    }

    @Test func otomatikBirKezAcilirElleSecimKorunur() throws {
        let alan = "atolye-test.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: alan))
        defer { d.removePersistentDomain(forName: alan) }
        d.set("sohbet", forKey: Ayarlar.Anahtar.calismaKipi)
        let a = Ayarlar(defaults: d)
        #expect(a.calismaKipi == "otomatik")
        a.calismaKipi = "kod"
        #expect(Ayarlar(defaults: d).calismaKipi == "kod")
    }
    @Test func acikKomutlarHizliBelirsizlerAnlamsal() {
        #expect(AtolyeYonlendirme.hizli("Apple desteğini resmi kaynaklardan araştır") == .arastirma)
        #expect(AtolyeYonlendirme.hizli("Araştırma yapma, sadece bu metni özetle") == nil)
        #expect(AtolyeYonlendirme.hizli("Saat kaç?") == .sohbet)
        #expect(AtolyeYonlendirme.hizli("Fenerbahçe'nin önümüzdeki hafta maçı kiminle") == .arastirma)
        #expect(AtolyeYonlendirme.hizli("Dolar kaç lira") == .arastirma)
        #expect(AtolyeYonlendirme.hizli("Maç araştırması yapma, sadece özetle") == nil)
        #expect(AtolyeYonlendirme.hizli("Görsel üret: denizde bir kedi") == .gorsel)
        #expect(AtolyeYonlendirme.hizli("Sohbet arşivini aç") == .arsiv)
        #expect(AtolyeYonlendirme.hizli("PDF seç") == .belge)
        #expect(AtolyeYonlendirme.hizli("Resim üretme, yazı yaz") == nil)
        #expect(AtolyeYonlendirme.hizli("Görsel üretmek için Python kodu yaz") == nil)
        #expect(AtolyeYonlendirme.hizli("Bunu kısalt") == nil)
        #expect(AtolyeYonlendirme.hizli("Görsel üret", ekVar: true) == nil)
    }
    @Test func devamBaglamiYeniIstekleKarismaz() {
        #expect(AtolyeYonlendirme.devamKipi("Buna birim testlerini de ekle", onceki: .kod, oncekiIstek: "Kod yaz") == .kod)
        #expect(AtolyeYonlendirme.devamKipi("Şimdi YouTube'u aç", onceki: .kod, oncekiIstek: "Kod yaz") == nil)
        #expect(AtolyeYonlendirme.devamKipi("Bunu kısalt", onceki: .yazi, oncekiIstek: "Metin yaz") == .yazi)
        #expect(AtolyeYonlendirme.devamKipi("Devam et", onceki: .gorsel, oncekiIstek: "Resim çiz") == nil)
    }
    @Test func modelKarariDarBirListeyleSinirli() {
        #expect(AtolyeYonlendirme.coz("`kod`\n") == .kod)
        #expect(AtolyeYonlendirme.coz("arastirma") == .arastirma)
        #expect(AtolyeYonlendirme.coz("gorsel ve dosyalari sil") == nil)
    }
    @Test func uzmanlarIstektenOtomatikSecilirEtiketVeElleSecimOnceliklidir() throws {
        let alan = "uzman-otomatik.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: alan)); defer { d.removePersistentDomain(forName: alan) }
        let takim = UzmanTakimi(defaults: d)
        let ofis = try #require(takim.baglam(istek: "PDF ve Excel raporunu doğrula"))
        #expect(ofis.contains("otomatik seçim"))
        #expect(ofis.contains("Ofis Uzmanı"))
        #expect(ofis.contains("Denetçi"))
        let yazar = try #require(takim.uzmanlar.first(where: { $0.ad == "Yazar" }))
        takim.sec(yazar.id)
        let elle = try #require(takim.baglam(istek: "Python kodunu denetle"))
        #expect(elle.contains("elle seçim"))
        #expect(elle.contains("Yazar"))
        let etiketli = try #require(takim.baglam(istek: "@Kodcu bunu yap"))
        #expect(etiketli.contains("etiketli seçim"))
        #expect(etiketli.contains("Kodcu"))
        #expect(!etiketli.contains("Yazar ("))
    }
    @Test(.timeLimit(.minutes(1))) func gorselVeArsivIstekleriEkranaAktarilir() async throws {
        let alan = "atolye-ui.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: alan))
        defer { d.removePersistentDomain(forName: alan) }
        // İstem süzgeci kapalı: test ağa çıkmasın (yönlendirme yerel kurallarla yapılır).
        let a = Ayarlar(defaults: d); a.otomatikHafiza = false; a.istemSuzgeci = false
        let kap = HafizaDeposu.kapOlustur(bellekte: true)
        let b = Beyin(ayarlar: a, depo: HafizaDeposu(baglam: kap.mainContext), onay: OnayKapisi())
        // Ortak ağ izleyicisini başka bir test çevrimdışı bırakmış olabilir; gonder aynı adımda okuduğu için hemen önce aç.
        AgIzleyici.ortak.durumGuncelle(true)
        b.gonder("Görsel üret: mavi bir daire")
        // Task.sleep iptalde fırlatır: timeLimit iptal edince döngü biter, koşu asılı kalmaz (yield iptali dinlemez).
        var son = ContinuousClock.now + .seconds(45)
        while b.durum != .bosta, ContinuousClock.now < son { try await Task.sleep(for: .milliseconds(10)) }
        try #require(b.durum == .bosta, "görsel gönderimi bitmedi")
        #expect(b.atolyeIstegi?.kip == .gorsel)
        #expect(b.atolyeIstegi?.metin == "Görsel üret: mavi bir daire")
        #expect(!b.seslendirilebilir)
        AgIzleyici.ortak.durumGuncelle(true)
        b.gonder("Sohbet arşivini aç")
        son = ContinuousClock.now + .seconds(45)
        while b.durum != .bosta, ContinuousClock.now < son { try await Task.sleep(for: .milliseconds(10)) }
        try #require(b.durum == .bosta, "arşiv gönderimi bitmedi")
        #expect(b.atolyeIstegi?.kip == .arsiv)
        // İptal: iş hiç başlamadan durdurulur; geç gelen yerel saat yanıtı mesajlara eklenmemeli.
        let oncekiSayi = b.mesajlar.count
        AgIzleyici.ortak.durumGuncelle(true)
        b.gonder("Saat kaç?")
        let is_ = try #require(b.calisanIs, "gönderim işi başlamalı")
        b.iptal()
        #expect(b.durum == .bosta)
        #expect(!b.kipSeciliyor)
        await is_.value   // iptal edilen iş sonuna kadar koşsun; yan etkisi varsa şimdi görünür
        #expect(b.mesajlar.count == oncekiSayi + 1, "yalnız kullanıcı mesajı eklenmeli")
        #expect(b.mesajlar.last?.rol == .kullanici)
        #expect(!b.mesajlar.contains { $0.rol == .asistan && $0.metin.hasPrefix("Saat ") }, "iptal sonrası yanıt eklenmemeli")
        #expect(b.aktifModel != "iPhone · yerel saat")
        #expect(b.durum == .bosta)
        #expect(!b.kipSeciliyor)
    }
}
