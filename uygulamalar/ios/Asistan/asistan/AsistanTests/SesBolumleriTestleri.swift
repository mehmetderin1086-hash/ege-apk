import Testing
import Foundation
@testable import Asistan

/// Sesli anlatım oynatıcısının saf mantığı: ayrıştırma, tahmini zaman damgaları, ikili arama, sınırlamalar, uyku sayacı.
@Suite("Ses bölümleri")
struct SesBolumleriTestleri {
    private let iki = "**Konuşmacı 1:** Merhaba, bugün hücreyi anlatacağız.\n\nKaynak: k1\n\n**Konuşmacı 2:** Hücre canlının temel birimidir.\n\nKaynak: k2"

    // MARK: Ayrıştırma

    @Test func bosTranskriptBosPlanVerir() {
        let p = SesBolumleri.coz(transkript: "", sure: 120)
        #expect(p.satirlar.isEmpty && p.bolumler.isEmpty)
        #expect(p.sure == 120)
        #expect(SesBolumleri.aktifSatir(zaman: 5, plan: p) == nil)
        #expect(SesBolumleri.aktifBolum(zaman: 5, plan: p) == nil)
    }

    @Test func yalnizBosluklarBosPlanVerir() {
        #expect(SesBolumleri.coz(transkript: " \n\n \r\n\t\n", sure: 10).satirlar.isEmpty)
    }

    @Test func konusmaciVeKaynakSatirlariAyrilir() {
        let p = SesBolumleri.coz(transkript: iki, sure: 60)
        #expect(p.satirlar.count == 2)
        #expect(p.satirlar[0].konusmaci == "Konuşmacı 1")
        #expect(p.satirlar[1].konusmaci == "Konuşmacı 2")
        #expect(p.satirlar[0].metin == "Merhaba, bugün hücreyi anlatacağız.")
        #expect(!p.satirlar.contains { $0.metin.contains("Kaynak") })
    }

    @Test func tekKonusmaciOnSozuSeslendirilmez() {
        let t = "Katalogda tek uygun ses bulundu; tek anlatıcı kullanıldı.\n\n**Konuşmacı 1:** Merhaba.\n\nKaynak: a"
        let p = SesBolumleri.coz(transkript: t, sure: 10)
        #expect(p.satirlar.count == 1)
        #expect(p.satirlar[0].metin == "Merhaba.")
    }

    @Test func konusmacisizMetinTekSatirOlur() {
        let p = SesBolumleri.coz(transkript: "Düz bir anlatım metni var burada.", sure: 30)
        #expect(p.satirlar.count == 1)
        #expect(p.satirlar[0].konusmaci == nil)
    }

    @Test func turkceKarakterlerKorunur() {
        let p = SesBolumleri.coz(transkript: "**Anlatıcı:** İğne yapraklı ağaçlar, çiçeksiz şüphesiz öğrenilir.", sure: 10)
        #expect(p.satirlar[0].konusmaci == "Anlatıcı")
        #expect(p.satirlar[0].metin == "İğne yapraklı ağaçlar, çiçeksiz şüphesiz öğrenilir.")
    }

    @Test func turkceBuyukHarfliKonusmaciAditaninir() {
        let (ad, metin) = SesBolumleri.konusmaciAyir("Çağla: Selam")
        #expect(ad == "Çağla" && metin == "Selam")
        let (ad2, _) = SesBolumleri.konusmaciAyir("İpek: Selam")
        #expect(ad2 == "İpek")
    }

    @Test func konusmaciOlmayanIkiNoktaMetindeKalir() {
        let (ad, metin) = SesBolumleri.konusmaciAyir("saat 10:30 gibi başlayacağız")
        #expect(ad == nil)
        #expect(metin == "saat 10:30 gibi başlayacağız")
        let (ad2, m2) = SesBolumleri.konusmaciAyir("https://ornek.com adresine bak")
        #expect(ad2 == nil && m2.hasPrefix("https"))
    }

    @Test func crlfSatirSonlariDesteklenir() {
        let p = SesBolumleri.coz(transkript: iki.replacingOccurrences(of: "\n", with: "\r\n"), sure: 40)
        #expect(p.satirlar.count == 2)
    }

    // MARK: Bölümler

    @Test func baslikliTranskriptBolumleriniKorur() {
        let t = "# Giriş\n\n**Konuşmacı 1:** Bir.\n\n## Hücre Zarı\n\n**Konuşmacı 2:** İki.\n\n**Konuşmacı 1:** Üç."
        let p = SesBolumleri.coz(transkript: t, sure: 90)
        #expect(p.bolumler.map(\.baslik) == ["Giriş", "Hücre Zarı"])
        #expect(p.bolumler[0].ilkSatir == 0 && p.bolumler[0].sonSatir == 1)
        #expect(p.bolumler[1].ilkSatir == 1 && p.bolumler[1].sonSatir == 3)
        #expect(p.satirlar[2].bolum == 1)
    }

    @Test func parcaBasliklariBolumOlur() {
        let t = "Parça 1\n\n**Konuşmacı 1:** Merhaba.\n\nParça 2: Mitoz\n\n**Konuşmacı 1:** Devam."
        let p = SesBolumleri.coz(transkript: t, sure: 20)
        #expect(p.bolumler.map(\.baslik) == ["Parça 1", "Parça 2: Mitoz"])
    }

    @Test func parcaIleBaslayanCumleBaslikSayilmaz() {
        let t = "Bölüm 2'de hücre bölünmesini anlatıyorum."
        let p = SesBolumleri.coz(transkript: t, sure: 20)
        #expect(p.satirlar.count == 1)
        #expect(p.bolumler.count == 1)
    }

    @Test func basliktenOnceMetinGirisBolumuOlur() {
        let t = "**Konuşmacı 1:** Önce giriş.\n\n# Konu\n\n**Konuşmacı 1:** Sonra konu."
        let p = SesBolumleri.coz(transkript: t, sure: 20)
        #expect(p.bolumler.map(\.baslik) == ["Giriş", "Konu"])
    }

    @Test func bosBaslikBolumuAtlanir() {
        let t = "# Boş\n\n# Dolu\n\n**Konuşmacı 1:** Metin."
        let p = SesBolumleri.coz(transkript: t, sure: 20)
        #expect(p.bolumler.map(\.baslik) == ["Dolu"])
    }

    @Test func kisaBasliksizAnlatimTekBolumdur() {
        let p = SesBolumleri.coz(transkript: iki, sure: 120)
        #expect(p.bolumler.count == 1)
        #expect(p.bolumler[0].baslik == "Anlatım")
    }

    @Test func uzunBasliksizAnlatimOtomatikBolunur() {
        let satirlar = (1...20).map { "**Konuşmacı \($0 % 2 + 1):** " + String(repeating: "söz ", count: 30) }
        let p = SesBolumleri.coz(transkript: satirlar.joined(separator: "\n\n"), sure: 1200)
        #expect(p.bolumler.count >= 3)
        #expect(p.bolumler.first?.baslik == "Bölüm 1")
        for b in p.bolumler.dropFirst() { #expect(b.baslik.hasPrefix("Bölüm ")) }
        #expect(p.bolumler.map(\.sonSatir).last == 20)
    }

    // MARK: Zaman damgaları

    @Test func zamanlarSureyiTamKaplar() {
        let p = SesBolumleri.coz(transkript: iki, sure: 77.5)
        #expect(p.satirlar.first?.baslangic == 0)
        #expect(p.satirlar.last?.bitis == 77.5)
        #expect(p.satirlar[0].bitis == p.satirlar[1].baslangic)
        #expect(p.tahmini)
    }

    @Test func zamanlarKarakterOrantilidir() {
        let t = "**Konuşmacı 1:** aaaa\n\n**Konuşmacı 2:** aaaaaaaaaaaa"   // 4 ve 12 karakter
        let p = SesBolumleri.coz(transkript: t, sure: 160)
        #expect(abs(p.satirlar[0].bitis - 40) < 1e-9)
    }

    @Test func parcaSayisiEsitseAraSessizlikAgirligiEklenir() {
        let t = "**Konuşmacı 1:** aaaa\n\n**Konuşmacı 2:** aaaaaaaaaaaa"
        let a = SesBolumleri.coz(transkript: t, sure: 160, parcaSayisi: 2)
        let b = SesBolumleri.coz(transkript: t, sure: 160, parcaSayisi: 5)   // uyuşmuyor: yok sayılır
        #expect(a.satirlar[0].bitis > b.satirlar[0].bitis)
        #expect(abs(b.satirlar[0].bitis - 40) < 1e-9)
    }

    @Test func sureSifirVeSonsuzGuvenliyle() {
        for s in [0.0, -5, .nan, .infinity] {
            let p = SesBolumleri.coz(transkript: iki, sure: s)
            #expect(p.sure == 0)
            #expect(p.satirlar.allSatisfy { $0.baslangic == 0 && $0.bitis == 0 })
            #expect(SesBolumleri.aktifSatir(zaman: 0, plan: p) == 0)
        }
    }

    @Test func cokUzunTekSatirSorunsuzIslenir() {
        let uzun = "**Konuşmacı 1:** " + String(repeating: "ğ", count: 200_000)
        let p = SesBolumleri.coz(transkript: uzun, sure: 3600)
        #expect(p.satirlar.count == 1)
        #expect(p.satirlar[0].metin.count == 200_000)
        #expect(p.satirlar[0].bitis == 3600)
    }

    // MARK: İkili arama ve aktif satır

    @Test func ikiliAramaKenarlari() {
        let b = [0.0, 10, 20, 30]
        #expect(SesBolumleri.sonBaslayan(zaman: -1, baslangiclar: b) == 0)
        #expect(SesBolumleri.sonBaslayan(zaman: 0, baslangiclar: b) == 0)
        #expect(SesBolumleri.sonBaslayan(zaman: 9.999, baslangiclar: b) == 0)
        #expect(SesBolumleri.sonBaslayan(zaman: 10, baslangiclar: b) == 1)
        #expect(SesBolumleri.sonBaslayan(zaman: 29.9, baslangiclar: b) == 2)
        #expect(SesBolumleri.sonBaslayan(zaman: 30, baslangiclar: b) == 3)
        #expect(SesBolumleri.sonBaslayan(zaman: 9999, baslangiclar: b) == 3)
        #expect(SesBolumleri.sonBaslayan(zaman: .nan, baslangiclar: b) == 0)
        #expect(SesBolumleri.sonBaslayan(zaman: 5, baslangiclar: []) == nil)
        #expect(SesBolumleri.sonBaslayan(zaman: 5, baslangiclar: [0]) == 0)
    }

    @Test func ikiliAramaDogrusalAramaylaUyusur() {
        let b = (0..<257).map { Double($0) * 1.5 }
        for z in stride(from: -2.0, through: 400, by: 0.37) {
            let beklenen = b.lastIndex(where: { $0 <= z }) ?? 0
            #expect(SesBolumleri.sonBaslayan(zaman: z, baslangiclar: b) == beklenen)
        }
    }

    @Test func aktifSatirSinirZamanlarindaDegisir() {
        let p = SesBolumleri.coz(transkript: iki, sure: 100)
        let sinir = p.satirlar[1].baslangic
        #expect(SesBolumleri.aktifSatir(zaman: sinir - 0.001, plan: p) == 0)
        #expect(SesBolumleri.aktifSatir(zaman: sinir, plan: p) == 1)
        #expect(SesBolumleri.aktifSatir(zaman: 100, plan: p) == 1)
        #expect(SesBolumleri.aktifBolum(zaman: 100, plan: p) == 0)
    }

    // MARK: Hız, atlama, devam

    @Test func hizSinirlanir() {
        #expect(SesBolumleri.hizSinirla(0.1) == 0.75)
        #expect(SesBolumleri.hizSinirla(5) == 2)
        #expect(SesBolumleri.hizSinirla(1.3) == 1.3)
        #expect(SesBolumleri.hizSinirla(.nan) == 1)
        #expect(SesBolumleri.hizSinirla(-1) == 0.75)
    }

    @Test func hizAdimlariUclardaSabitKalir() {
        #expect(SesBolumleri.hizAdimi(2, ileri: true) == 2)
        #expect(SesBolumleri.hizAdimi(0.75, ileri: false) == 0.75)
        #expect(SesBolumleri.hizAdimi(1, ileri: true) == 1.25)
        #expect(SesBolumleri.hizAdimi(1, ileri: false) == 0.75)
        #expect(SesBolumleri.hizAdimi(1.3, ileri: true) == 1.5)   // en yakın adım 1.25
    }

    @Test func atlamaSureAraliginaSikisir() {
        #expect(SesBolumleri.atla(zaman: 10, fark: -15, sure: 100) == 0)
        #expect(SesBolumleri.atla(zaman: 95, fark: 15, sure: 100) == 100)
        #expect(SesBolumleri.atla(zaman: 50, fark: 15, sure: 100) == 65)
        #expect(SesBolumleri.atla(zaman: 3, fark: -15, sure: 0) == 0)
        #expect(SesBolumleri.atla(zaman: 3, fark: 15, sure: 0) == 18)   // süre bilinmiyor: üst sınır yok
        #expect(SesBolumleri.atla(zaman: .nan, fark: 15, sure: 100) == 15)
    }

    @Test func devamZamaniKurallari() {
        #expect(SesBolumleri.devamZamani(kayitli: nil, sure: 100) == 0)
        #expect(SesBolumleri.devamZamani(kayitli: 2, sure: 100) == 0)       // çok başta
        #expect(SesBolumleri.devamZamani(kayitli: 50, sure: 100) == 50)
        #expect(SesBolumleri.devamZamani(kayitli: 98, sure: 100) == 0)      // bitişe yakın: baştan
        #expect(SesBolumleri.devamZamani(kayitli: .nan, sure: 100) == 0)
        #expect(SesBolumleri.devamAnahtari("g1") != SesBolumleri.devamAnahtari("g2"))
    }

    @Test func bolumGezinmeHedefleri() {
        let t = "# A\n\n**Konuşmacı 1:** aaaa\n\n# B\n\n**Konuşmacı 1:** aaaa\n\n# C\n\n**Konuşmacı 1:** aaaa"
        let p = SesBolumleri.coz(transkript: t, sure: 90)   // 30 sn'lik üç bölüm
        #expect(SesBolumleri.sonrakiBolumHedefi(zaman: 5, plan: p) == 30)
        #expect(SesBolumleri.sonrakiBolumHedefi(zaman: 80, plan: p) == nil)
        #expect(SesBolumleri.oncekiBolumHedefi(zaman: 45, plan: p) == 30)   // bölüm içindeyse başına
        #expect(SesBolumleri.oncekiBolumHedefi(zaman: 31, plan: p) == 0)    // ilk 3 sn: bir öncekine
        #expect(SesBolumleri.oncekiBolumHedefi(zaman: 1, plan: p) == 0)
    }

    @Test func zamanMetniBicimi() {
        #expect(SesBolumleri.zamanMetni(0) == "0:00")
        #expect(SesBolumleri.zamanMetni(65.9) == "1:05")
        #expect(SesBolumleri.zamanMetni(3600) == "1:00:00")
        #expect(SesBolumleri.zamanMetni(-4) == "0:00")
        #expect(SesBolumleri.zamanMetni(.nan) == "0:00")
    }

    // MARK: Uyku sayacı

    @Test func dakikaSayaciSuresiDoluncaDurdurur() {
        var s = UykuSayaci(secenek: .dakika(15))
        #expect(s.kalan == 900)
        let erkenBitti = s.ilerlet(gecen: 899, zaman: 0)
        #expect(!erkenBitti)
        let suresiDoldu = s.ilerlet(gecen: 1, zaman: 0)
        #expect(suresiDoldu)
        #expect(s.kalan == 0)
    }

    @Test func kapaliSayacHicDurdurmaz() {
        var s = UykuSayaci(secenek: .kapali)
        let durdu = s.ilerlet(gecen: 1e9, zaman: 1e9)
        #expect(!durdu)
    }

    @Test func bolumSonuSayaciBitisteDurdurur() {
        var s = UykuSayaci(secenek: .bolumSonu, bolumBitisi: 30)
        let erkenBitti = s.ilerlet(gecen: 1, zaman: 29)
        #expect(!erkenBitti)
        let bolumBitti = s.ilerlet(gecen: 1, zaman: 29.8)
        #expect(bolumBitti)
        var yok = UykuSayaci(secenek: .bolumSonu, bolumBitisi: nil)
        let hedefsizDurdu = yok.ilerlet(gecen: 1, zaman: 100)
        #expect(!hedefsizDurdu)
    }

    @Test func negatifVeGecersizGecenSureyiBozmaz() {
        var s = UykuSayaci(secenek: .dakika(15))
        let negatifDurdu = s.ilerlet(gecen: -50, zaman: 0)
        #expect(!negatifDurdu)
        let gecersizDurdu = s.ilerlet(gecen: .nan, zaman: 0)
        #expect(!gecersizDurdu)
        #expect(s.kalan == 900)
    }

    @Test func uykuSecenekEtiketleri() {
        #expect(UykuSecenegi.secenekler.count == 5)
        #expect(UykuSecenegi.dakika(30).etiket == "30 dakika")
        #expect(UykuSecenegi.bolumSonu.etiket == "Bölüm sonu")
    }
}
