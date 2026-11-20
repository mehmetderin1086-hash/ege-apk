import Testing
import Foundation
@testable import Asistan

/// P2.10: yazıyla söylenen Türkçe sayılar (yalnız karşılaştırma için) rakama iner; kullanıcının rakam/özel ad kısıtları
/// süzgeç olmasa da indirme eşleşmesine girer; dosya/indirme yanıtı kısıtı karşılamıyorsa "Uyuşmazlık" notu düşülür.
@Suite("P2.10 Türkçe sayı ve kısıt denetimi")
@MainActor
struct Gelistirme_P2_10_TurkceSayiTestleri {
    let kuran = "Kur'an-ı Kerim Meali"

    // MARK: TurkceSayi.normalize

    @Test func cokSozcukluSayilarToplanir() {
        #expect(TurkceSayi.normalize("on besinci cuz") == "15. cuz")
        #expect(TurkceSayi.normalize("yuz otuz sekiz") == "138")
        #expect(TurkceSayi.normalize("iki bin yirmi alti") == "2026")
        #expect(TurkceSayi.normalize("bin bir gece") == "1001 gece")
        #expect(TurkceSayi.normalize("yuzuncu yil") == "100. yil")
    }

    @Test func saatVeBucukKaliplari() {
        #expect(TurkceSayi.normalize("saat on dort otuz") == "saat 14.30")
        #expect(TurkceSayi.normalize("saat iki bes") == "saat 2.05")
        #expect(TurkceSayi.normalize("uc bucuk") == "3,5")
        #expect(TurkceSayi.normalize("bir bucuk saat") == "1,5 saat")
        #expect(TurkceSayi.normalize("iki bucukta") == "2.30")
        #expect(TurkceSayi.normalize("ikiyi ceyrek gece") == "2.15")
        #expect(TurkceSayi.normalize("on biri ceyrek gece") == "11.15")
        #expect(TurkceSayi.normalize("dorde ceyrek var") == "3.45")
    }

    @Test func halEkiYalnizDizininSonundaTaninir() {
        #expect(TurkceSayi.normalize("on beste") == "15'te")
        #expect(TurkceSayi.normalize("saat yedide") == "saat 7'de")
        // Tek başına ekli biçimler eş seslidir: "beste" (müzik), "onda" (zamir).
        #expect(TurkceSayi.normalize("beste") == "beste")
        #expect(TurkceSayi.normalize("onda var") == "onda var")
        #expect(TurkceSayi.normalize("sezen aksu bestesi") == "sezen aksu bestesi")
    }

    @Test func tekSozcukYalnizSayaclaCevrilir() {
        #expect(TurkceSayi.normalize("bir gun") == "bir gun")
        #expect(TurkceSayi.normalize("live on stage") == "live on stage")
        #expect(TurkceSayi.normalize("on cuz") == "10 cuz")
        #expect(TurkceSayi.normalize("yemek yedi") == "yemek yedi")
        #expect(TurkceSayi.normalize("yedi gun") == "7 gun")
        #expect(TurkceSayi.normalize("masanin alti") == "masanin alti")
        // Rakamla yazılmış ekli sayılara dokunulmaz (IndirmeEslesme kendi ayıklar).
        #expect(TurkceSayi.normalize("15'inci 5’te") == "15'inci 5’te")
    }

    @Test func cokSozcukluSayilarYalnizYalinDiziler() {
        #expect(TurkceSayi.cokSozcukluSayilar("yuz otuz sekiz iett seferleri") == [138])
        #expect(TurkceSayi.cokSozcukluSayilar("iki hattin saatleri").isEmpty)
        #expect(TurkceSayi.cokSozcukluSayilar("on besinci cuz").isEmpty, "sıra sayısı hat kodu değil")
        #expect(TurkceSayi.cokSozcukluSayilar("saat on dort otuz").isEmpty, "saat kalıbı hat kodu değil")
        #expect(TurkceSayi.cokSozcukluSayilar("yirmi dort saat").isEmpty, "hat dışı sayaçlı dizi hat kodu değil")
    }

    // MARK: İndirme eşleşmesi

    @Test func yaziylaSiraSayisiEslesmeyeGirer() {
        let istek = "Kur'an meali Ayhan Kaya on beşinci cüz"
        #expect(IndirmeEslesme.puan(istek: istek, baslik: "\(kuran) 1. Cüz — Ayhan Kaya", kanal: "Vav Radyo") <= 0.3)
        #expect(IndirmeEslesme.puan(istek: istek, baslik: "\(kuran) 15. Cüz Ayhan Kaya", kanal: "Vav Radyo") >= IndirmeEslesme.esik)
    }

    @Test func varOlanEslesmeDavranisiKorunur() {
        #expect(IndirmeEslesme.simgeler("15'inci 5’te 15inci 15.") == ["15", "5", "15", "15"])
        #expect(IndirmeEslesme.puan(istek: "Sezen Aksu Gidiyorum şarkısını", baslik: "Sezen Aksu - Gidiyorum (Official Audio)", kanal: "Sezen Aksu")
                >= IndirmeEslesme.esik)
        #expect(IndirmeEslesme.puan(istek: "Live on stage Tarkan", baslik: "Tarkan - Live on Stage", kanal: "Tarkan") >= IndirmeEslesme.esik)
    }

    // MARK: Kısıtlar

    @Test func yerelKisitlarRakamVeOzelAdAlir() {
        let k = KisitDenetimi.yerelKisitlar("Vav radyo kuran meali Ayhan kaya 15. Çöz indir")
        #expect(k.contains("15"))
        #expect(k.contains("Ayhan"))
        #expect(!k.contains("Çöz"), "dikte hatası kısa sözcük kısıt olmamalı")
        #expect(KisitDenetimi.yerelKisitlar("kuran meali on beşinci cüz indir").contains("15"))
        // Saat ve iş sözcükleri kısıt değildir; cümle başı büyük harf özel ad sayılmaz.
        let s = KisitDenetimi.yerelKisitlar("Yarın saat 9'da toplantı. Sonra Excel tablosu Kaydet")
        #expect(!s.contains("9") && !s.contains("Sonra") && !s.contains("Excel") && !s.contains("Kaydet"))
        #expect(KisitDenetimi.yerelKisitlar("a b c d e f g 1 2 3 4 5 6 7 8").count <= 6)
    }

    @Test func etkinKisitlarSuzgeciOnceler() {
        let ham = "Vav radyo kuran meali Ayhan kaya 15. Çöz indir"
        let suzgecli = IstemSuzgeci.etkinKisitlariSec(suzgec: ["15. cüz", "okuyucu: Ayhan Kaya", " "], ham: ham)
        #expect(suzgecli == ["15. cüz", "okuyucu: Ayhan Kaya"])
        #expect(!suzgecli.contains("Çöz"))
        let yerel = IstemSuzgeci.etkinKisitlariSec(suzgec: [], ham: ham)
        #expect(yerel.contains("15") && yerel.contains("Ayhan") && !yerel.contains("Çöz"))
    }

    @Test func eksikKisitlarBulunur() {
        #expect(KisitDenetimi.eksikKisitlar(kisitlar: ["15. cüz"], metinler: ["1. Cüz dosyası"]) == ["15"])
        #expect(KisitDenetimi.eksikKisitlar(kisitlar: ["15. cüz"], metinler: ["15. Cüz dosyası"]).isEmpty)
        #expect(KisitDenetimi.eksikKisitlar(kisitlar: ["15. cüz"], metinler: ["on beşinci cüz indirildi"]).isEmpty)
        #expect(KisitDenetimi.eksikKisitlar(kisitlar: ["okuyucu: Ayhan Kaya", "15"], metinler: ["15. Cüz — Mazlum Kiper"]) == ["Ayhan", "Kaya"])
        #expect(KisitDenetimi.eksikKisitlar(kisitlar: [], metinler: ["x"]).isEmpty)
        #expect(KisitDenetimi.eksikKisitlar(kisitlar: ["dil: Türkçe", "sadece ses"], metinler: ["x"]).isEmpty)
    }

    @Test func ekAdlariYalnizDosyaVeIndirmede() {
        let url = URL(fileURLWithPath: "/tmp/15. Cüz.mp3")
        let adlar = KisitDenetimi.ekAdlari([MesajEki(tur: .dosya(url: url, ad: "15. Cüz.mp3")), MesajEki(tur: .indirme(UUID()))], kayitlar: [])
        #expect(adlar == ["15. Cüz.mp3", "15. Cüz.mp3"])
        #expect(KisitDenetimi.ekAdlari([MesajEki(tur: .kaynaklar(["https://ornek.com"]))], kayitlar: []) == nil)
        #expect(KisitDenetimi.ekAdlari([], kayitlar: []) == nil)
    }

    @Test func uyusmazlikNotuKontrolSatirinaDuser() {
        let alan = "p210.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: alan)!
        defer { ud.removePersistentDomain(forName: alan) }
        let b = Beyin(ayarlar: Ayarlar(defaults: ud), depo: HafizaDeposu(baglam: HafizaTestleri.kap.mainContext), onay: OnayKapisi())
        let eskiSon = IstemSuzgeci.son, eskiHam = IstemSuzgeci.sonHam
        defer { IstemSuzgeci.son = eskiSon; IstemSuzgeci.sonHam = eskiHam }
        IstemSuzgeci.son = nil
        IstemSuzgeci.sonHam = "Kuran meali Ayhan Kaya on beşinci cüz indir"
        b.aktifModel = "claude-sonnet-5-5"
        let ek = MesajEki(tur: .dosya(url: URL(fileURLWithPath: "/tmp/1. Cüz.mp3"), ad: "1. Cüz — Ayhan Kaya.mp3"))
        b.mesajlar.append(Beyin.Goruntu(rol: .asistan, metin: "Dosyayı indirdim.", ekler: [ek]))
        let id = b.mesajlar[b.mesajlar.count - 1].id
        b.kisitUyusmazliginiDenetle(id, yanit: "Dosyayı indirdim.", ekler: [ek])
        let not = b.mesajlar.last?.kontrol ?? ""
        #expect(not.contains("Uyuşmazlık") && not.contains("15") && not.contains("Yanlış olabilir"))

        // Doğru dosya, eki olmayan yanıt ve cihaz içi model not üretmez.
        let dogru = MesajEki(tur: .dosya(url: URL(fileURLWithPath: "/tmp/15.mp3"), ad: "15. Cüz — Ayhan Kaya.mp3"))
        b.mesajlar.append(Beyin.Goruntu(rol: .asistan, metin: "Tamam.", ekler: [dogru]))
        let id2 = b.mesajlar[b.mesajlar.count - 1].id
        b.kisitUyusmazliginiDenetle(id2, yanit: "Tamam.", ekler: [dogru])
        b.kisitUyusmazliginiDenetle(id2, yanit: "Tamam.", ekler: [])
        b.aktifModel = "iPhone (Apple Intelligence)"
        b.kisitUyusmazliginiDenetle(id2, yanit: "Tamam.", ekler: [ek])
        #expect(b.mesajlar.last?.kontrol == nil)
    }
}
