import Testing
import Foundation
@testable import Asistan

/// P2.3: tek durum şeridi (DurumSecici), hata sözlüğü (HataSozlugu) ve Beyin'in yeniden deneme durumu.
/// Ağ, izin ve gerçek model gerektirmez.
@Suite("P2.3 durum şeridi ve hata sözlüğü")
@MainActor
struct Gelistirme_P2_3_DurumSeridiTestleri {
    struct AciklamaliHata: LocalizedError {
        let m: String
        var errorDescription: String? { m }
    }

    let temizlik = TestTemizligi()

    func beyin(kuyruk: CevrimdisiKuyruk? = nil) -> Beyin {
        let ud = temizlik.suit("p23")
        let k = OnayKapisi(); k.otomatikKarar = false
        return Beyin(ayarlar: Ayarlar(defaults: ud), depo: HafizaDeposu(baglam: HafizaTestleri.kap.mainContext), onay: k,
                     modelVitesi: ModelVitesi(defaults: ud), kuyruk: kuyruk)
    }

    // MARK: HataSozlugu

    @Test func vekileBaglanamamaBaglantiTuruVeKodluMetin() {
        let h = URLError(.cannotConnectToHost)
        #expect(HataSozlugu.tur(h) == .baglanti)
        #expect(HataSozlugu.metin(h).contains("-1004"))
        #expect(Beyin.hataMetni(h) == HataSozlugu.metin(h))
    }

    @Test func internetYokVeDigerBaglantiMetinleri() {
        #expect(HataSozlugu.metin(URLError(.notConnectedToInternet)) == HataSozlugu.internetYokMetni)
        #expect(HataSozlugu.tur(URLError(.notConnectedToInternet)) == .baglanti)
        // Öbür bağlantı kodları eski genel metni korur (UI testlerinin "hata yok" denetimi bu metne bakar).
        #expect(HataSozlugu.metin(URLError(.networkConnectionLost)) == "Bağlantı yok ya da sunucuya ulaşılamadı.")
    }

    @Test func zamanAsimiTuru() {
        #expect(HataSozlugu.tur(URLError(.timedOut)) == .zamanAsimi)
        let m = HataSozlugu.metin(URLError(.timedOut))
        #expect(m.contains("zamanında yanıt vermedi") && !m.contains("timed out"))
    }

    @Test func saglayiciKodlariTureVeMetneCevrilir() {
        let yetki = AciklamaliHata(m: "HTTP 401 Unauthorized")
        #expect(HataSozlugu.tur(yetki) == .yetki)
        #expect(HataSozlugu.metin(yetki) == HataSozlugu.yetkiMetni)
        let kota = AciklamaliHata(m: "429 Too Many Requests")
        #expect(HataSozlugu.tur(kota) == .kota)
        #expect(HataSozlugu.metin(kota) == HataSozlugu.kotaMetni)
        let sunucu = AciklamaliHata(m: "502 Bad Gateway")
        #expect(HataSozlugu.tur(sunucu) == .sunucu)
        #expect(HataSozlugu.metin(sunucu) == HataSozlugu.sunucuMetni)
        #expect(HataSozlugu.tur(AciklamaliHata(m: "Forbidden (403)")) == .yetki)
    }

    @Test func sayiIcindekiKodlarYanlisTurUretmez() {
        let h = AciklamaliHata(m: "Metin 1500 karakter sınırını aştı")
        #expect(HataSozlugu.tur(h) == .bilinmeyen)
        #expect(HataSozlugu.metin(h) == "Hata: Metin 1500 karakter sınırını aştı")
        #expect(HataSozlugu.tur(AciklamaliHata(m: "kod 4010 döndü")) == .bilinmeyen)
        #expect(HataSozlugu.tur(AciklamaliHata(m: "sıra 14290")) == .bilinmeyen)
    }

    @Test func sarmalAracHatasindaAsilNedenKalir() {
        let h = AciklamaliHata(m: "An error occurred while invoking the tool: X(asil: Y) Underlying error: Önce klasör seç.")
        #expect(Beyin.hataMetni(h) == "Önce klasör seç.")
        #expect(HataSozlugu.tur(h) == .bilinmeyen)
        let kotali = AciklamaliHata(m: "An error occurred while invoking the tool: X Underlying error: HTTP 429 rate limit")
        #expect(HataSozlugu.tur(kotali) == .kota)
    }

    @Test func bosHataBilinmeyenMetni() {
        #expect(HataSozlugu.metin(nil) == "Bilinmeyen hata.")
    }

    // MARK: DurumSecici

    func adaylar(sonHata: String? = nil, tur: HataTuru? = nil, cevrimici: Bool = true, not: String? = nil, bekleyen: Int = 0,
                 kota: String? = nil, ses: String? = nil, kisisel: String? = nil, mikrofon: String? = nil, izinYok: Bool = false) -> [DurumBildirimi] {
        DurumSecici.adaylar(sonHata: sonHata, hataTuru: tur, cevrimici: cevrimici, cevrimdisiNotu: not, bekleyenSayisi: bekleyen,
                            kota: kota, sesHatasi: ses, kisiselHata: kisisel, mikrofonHatasi: mikrofon, mikrofonIzniYok: izinYok)
    }

    @Test func modelHatasiCevrimdisindanOnceGelir() {
        let a = adaylar(sonHata: "Model kullanım sınırında (429).", tur: .kota, cevrimici: false, not: "Bağlantı yok.", bekleyen: 2)
        let s = DurumSecici.sec(a, kapatilanlar: [])
        #expect(s.0?.tur == .modelHatasi)
        #expect(s.ek == 1)
    }

    @Test func oncelikSirasiAdaySirasindanBagimsiz() {
        let a = adaylar(kota: "Kota uyarısı", ses: "Ses hatası", mikrofon: "Mikrofon açılamadı")
        let s = DurumSecici.sec(a.reversed(), kapatilanlar: [])
        #expect(s.0?.tur == .mikrofon)
        #expect(s.ek == 2)
    }

    @Test func kapatilanAtlanir() {
        let a = adaylar(sonHata: "Hata: x", tur: .bilinmeyen, cevrimici: false)
        let model = a.first { $0.tur == .modelHatasi }!
        let s = DurumSecici.sec(a, kapatilanlar: [model.id])
        #expect(s.0?.tur == .cevrimdisi)
        #expect(s.ek == 0)
    }

    @Test func adayYoksaNil() {
        let s = DurumSecici.sec(adaylar(), kapatilanlar: [])
        #expect(s.0 == nil)
        #expect(s.ek == 0)
        let hepsiKapali = adaylar(kota: "k")
        #expect(DurumSecici.sec(hepsiKapali, kapatilanlar: Set(hepsiKapali.map(\.id))).0 == nil)
    }

    @Test func eylemListeleri() {
        let baglanti = adaylar(sonHata: "Yerel vekile bağlanılamadı (-1004)", tur: .baglanti).first!
        #expect(baglanti.eylemler == [.yenidenDene, .baskaModel, .baglantiyiSina])
        let yetki = adaylar(sonHata: "401", tur: .yetki).first!
        #expect(yetki.eylemler.contains(.baglantiyiSina))
        let kota = adaylar(sonHata: "429", tur: .kota).first!
        #expect(kota.eylemler == [.yenidenDene, .baskaModel])
        let izinsiz = adaylar(mikrofon: "Mikrofon açılamadı", izinYok: true).first!
        #expect(izinsiz.tur == .mikrofon && izinsiz.eylemler == [.ayarlariAc])
        let mikrofon = adaylar(mikrofon: "Mikrofon açılamadı").first!
        #expect(mikrofon.eylemler == [.mikrofonuYenidenBaslat])
        #expect(adaylar(cevrimici: false, bekleyen: 3).first!.eylemler == [.bekleyenleriIptal])
        #expect(adaylar(cevrimici: false).first!.eylemler.isEmpty)
        #expect(adaylar(kota: "Kota").first!.eylemler == [.baskaModel])
    }

    @Test func kimlikTurVeMetindenOlusur() {
        let a = DurumBildirimi(tur: .ses, metin: "Ses yok", simge: "speaker.slash")
        let b = DurumBildirimi(tur: .kisisel, metin: "Ses yok", simge: "x")
        #expect(a.id != b.id)
        #expect(a.id == DurumBildirimi(tur: .ses, metin: "Ses yok", simge: "y").id)
    }

    @Test func bosMetinliHataAdayOlmaz() {
        #expect(adaylar(sonHata: "  ", kota: "", ses: "", kisisel: "").isEmpty)
    }

    // MARK: Beyin

    @Test func bekleyenleriIptalKuyruguVeNotuTemizler() {
        let q = CevrimdisiKuyruk(klasor: temizlik.gecici(FileManager.default.temporaryDirectory.appending(path: "p23-kuyruk-\(UUID().uuidString)", directoryHint: .isDirectory)))
        let b = beyin(kuyruk: q)
        _ = q.ekle(metin: "bir", gorseller: [], belge: nil, canliSes: false, disKaynak: false)
        _ = q.ekle(metin: "iki", gorseller: [], belge: nil, canliSes: false, disKaynak: false)
        b.cevrimdisiNotu = "Bağlantı yok. 2 mesaj bekliyor."
        #expect(b.bekleyenGonderiler.count == 2)
        b.bekleyenleriIptal()
        #expect(b.bekleyenGonderiler.isEmpty)
        #expect(b.cevrimdisiNotu == nil)
    }

    @Test func yanEtkiliAdimSonrasiHataTuruIsaretlenir() {
        let b = beyin()
        _ = b.gorevler.baslat("takvim")   // salt okunur listede değil: yan etkili
        b.bitir(hata: "Sağlayıcı geçici hata verdi (5xx). Yeniden dene.", tur: .sunucu, nesil: b.nesil)
        #expect(b.sonTurYanEtkili)
        #expect(b.sonHataTuru == .sunucu)
        b.yeniSohbet()
        #expect(!b.sonTurYanEtkili)
        #expect(b.sonHataTuru == nil)
    }

    @Test func saltOkunurAdimYanEtkiSayilmaz() {
        let b = beyin()
        _ = b.gorevler.baslat("suankiSaat")
        b.bitir(hata: "Hata: x", nesil: b.nesil)
        #expect(!b.sonTurYanEtkili)
        #expect(b.sonHataTuru == .bilinmeyen)   // tür verilmezse bilinmeyen
        b.bitir(hata: nil, tur: .kota, nesil: b.nesil)
        #expect(b.sonHataTuru == nil)           // hata yoksa tür de yok
    }

    @Test func kullaniciMesajiYokkenYenidenDenemeBirSeyYapmaz() {
        let b = beyin()
        let once = b.nesil
        b.yenidenDene(model: "claude-opus-5-5")
        #expect(b.nesil == once)
        #expect(b.mesajlar.isEmpty)
        #expect(b.zorlananModel == nil)
    }
}
