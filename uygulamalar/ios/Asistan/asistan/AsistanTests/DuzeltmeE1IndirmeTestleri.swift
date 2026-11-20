import Foundation
import Testing
@testable import Asistan

/// İndirme eşleşmesi, 'ekle' türü, arama hata iletisi ve son adres denetimi (ağsız, saf mantık).
@Suite("E1-indirme düzeltmeleri")
struct DuzeltmeE1IndirmeTestleri {
    let kuran = "Kur'an-ı Kerim Meali"

    // MARK: Sayı kapısı (bulgu 34)

    @Test func tekHaneliSayiZorunlu() {
        let istek = "Vav Radyo Kur'an meali Ayhan Kaya 5. cüz"
        #expect(IndirmeEslesme.puan(istek: istek, baslik: "\(kuran) 1. Cüz - Ayhan Kaya", kanal: "Vav Radyo") <= 0.3)
        #expect(IndirmeEslesme.puan(istek: istek, baslik: "\(kuran) 15. Cüz - Ayhan Kaya", kanal: "Vav Radyo") <= 0.3)
        #expect(IndirmeEslesme.puan(istek: istek, baslik: "\(kuran) 5. Cüz - Ayhan Kaya", kanal: "Vav Radyo") >= IndirmeEslesme.esik)
    }

    @Test func ekliSiraSayisiRakamaIner() {
        let istek = "Vav Radyo Kur'an meali Ayhan Kaya 15'inci cüz"
        #expect(IndirmeEslesme.puan(istek: istek, baslik: "\(kuran) 1. Cüz - Ayhan Kaya", kanal: "Vav Radyo") <= 0.3)
        #expect(IndirmeEslesme.puan(istek: istek, baslik: "\(kuran) 15. Cüz - Ayhan Kaya", kanal: "Vav Radyo") >= IndirmeEslesme.esik)
        let bitisik = "Vav Radyo Kur'an meali Ayhan Kaya 15inci cüzü"
        #expect(IndirmeEslesme.puan(istek: bitisik, baslik: "\(kuran) 1. Cüz - Ayhan Kaya", kanal: "Vav Radyo") <= 0.3)
        #expect(IndirmeEslesme.puan(istek: bitisik, baslik: "\(kuran) 15. Cüz - Ayhan Kaya", kanal: "Vav Radyo") >= IndirmeEslesme.esik)
    }

    @Test func simgelerSayiAyiklar() {
        #expect(IndirmeEslesme.simgeler("15'inci 5’te 15inci 15.") == ["15", "5", "15", "15"])
        // Genel rakam+harf ayrıştırması yok: "2pac" sahte sayı kapısı açmaz, "4k" dolgu.
        #expect(IndirmeEslesme.simgeler("2pac 4k") == ["2pac"])
        #expect(IndirmeEslesme.puan(istek: "Dua Lipa Houdini official video 4k", baslik: "Dua Lipa - Houdini (Official Music Video)", kanal: "Dua Lipa") == 1)
    }

    // MARK: Betimleyici/çekimli dolgu (bulgu 151)

    @Test func betimleyiciSozcuklerPuanaKatilmaz() {
        let houdini = "Dua Lipa - Houdini (Official Music Video)"
        #expect(IndirmeEslesme.puan(istek: "Dua Lipa Houdini", baslik: houdini, kanal: "Dua Lipa") >= IndirmeEslesme.esik)
        #expect(IndirmeEslesme.puan(istek: "Dua Lipa Houdini müzik videosu", baslik: houdini, kanal: "Dua Lipa") >= IndirmeEslesme.esik)
        #expect(IndirmeEslesme.puan(istek: "Sezen Aksu Gidiyorum şarkısını", baslik: "Sezen Aksu - Gidiyorum (Official Audio)", kanal: "Sezen Aksu") >= IndirmeEslesme.esik)
        #expect(IndirmeEslesme.puan(istek: "Tarkan Kuzu Kuzu klibini", baslik: "Tarkan - Kuzu Kuzu", kanal: "Tarkan") >= IndirmeEslesme.esik)
        #expect(IndirmeEslesme.puan(istek: "Tarkan en çok dinlenen popüler şarkı Kuzu Kuzu", baslik: "Tarkan - Kuzu Kuzu", kanal: "Tarkan") >= IndirmeEslesme.esik)
    }

    @Test func yanlisSarkiYineEsikAltinda() {
        let p = IndirmeEslesme.puan(istek: "Dua Lipa Houdini müzik videosu", baslik: "Dua Lipa - Levitating (Official Music Video)", kanal: "Dua Lipa")
        #expect(p < IndirmeEslesme.esik)
    }

    // MARK: Süzgeç kısıtları (bulgu 108)

    @Test func kisitMetniEtiketleriAtar() {
        #expect(IndirmeEslesme.kisitMetni(["kaynak: Vav Radyo", "okuyucu: Ayhan Kaya", "15. cüz"]) == "Vav Radyo Ayhan Kaya 15.")
        // Biçim/dil kısıtları başlıkta aranmaz; tümüyle küçük harfli kısıtın bütün sözcükleri alınır.
        #expect(IndirmeEslesme.kisitMetni(["dil: Türkçe", "dosya türü: MP4", "okuyucu: ayhan kaya"]) == "ayhan kaya")
        #expect(IndirmeEslesme.kisitMetni([]).isEmpty)
    }

    @Test func kisitlarKisaltilmisSorguyuDenetler() {
        let deger = "Kuran meali 15. cüz"
        let kisitlar = ["kaynak: Vav Radyo", "okuyucu: Ayhan Kaya", "15. cüz"]
        let yanlis = IndirmeEslesme.puan(istek: deger, kisitlar: kisitlar, baslik: "\(kuran) 15. Cüz - Köksal Engür", kanal: "Vav Radyo")
        let dogru = IndirmeEslesme.puan(istek: deger, kisitlar: kisitlar, baslik: "\(kuran) 15. Cüz - Ayhan Kaya", kanal: "Vav Radyo")
        #expect(yanlis < IndirmeEslesme.esik)
        #expect(dogru >= IndirmeEslesme.esik)
        let a = IndirmeEslesme.Aday(baslik: "\(kuran) 15. Cüz - Köksal Engür", kanal: "Vav Radyo", sure: nil, url: "https://youtube.com/a", puan: yanlis)
        #expect(IndirmeEslesme.sec(istek: deger, adaylar: [a]).secilen == nil)
    }

    @Test func kisitsizPuanEskisiyleAyni() {
        for (b, k) in [("\(kuran) 15. Cüz - Köksal Engür", "Vav Radyo"), ("Dua Lipa - Houdini", "Dua Lipa"), ("1. Cüz", "Mazlum Kiper")] {
            #expect(IndirmeEslesme.puan(istek: "Kuran meali 15. cüz", kisitlar: [], baslik: b, kanal: k)
                    == IndirmeEslesme.puan(istek: "Kuran meali 15. cüz", baslik: b, kanal: k))
        }
    }

    @Test func etiketliVeEtiketsizKisitAyniPuan() {
        let b = "\(kuran) 15. Cüz - Köksal Engür", k = "Vav Radyo"
        let etiketli = IndirmeEslesme.puan(istek: "Kuran meali 15. cüz", kisitlar: ["kaynak: Vav Radyo", "okuyucu: Ayhan Kaya", "15. cüz"], baslik: b, kanal: k)
        let etiketsiz = IndirmeEslesme.puan(istek: "Kuran meali 15. cüz", kisitlar: ["Vav Radyo", "Ayhan Kaya", "15. cüz"], baslik: b, kanal: k)
        #expect(etiketli == etiketsiz)
    }

    @Test func bicimKisitiDogruAdayiDusurmez() {
        let p = IndirmeEslesme.puan(istek: "Dua Lipa Houdini", kisitlar: ["sanatçı: Dua Lipa", "şarkı: Houdini", "dosya türü: video"],
                                    baslik: "Dua Lipa - Houdini (Official Music Video)", kanal: "Dua Lipa")
        #expect(p >= IndirmeEslesme.esik)
    }

    // MARK: 'ekle' türü ve arama hatası (bulgu 119, 80/97)

    @Test func ekleTuruIndirgenir() {
        #expect(IndirmeAraci.ekleTuru("pdf") == "file")
        #expect(IndirmeAraci.ekleTuru("file") == "file")
        #expect(IndirmeAraci.ekleTuru(" MP4 ") == "video")
        #expect(IndirmeAraci.ekleTuru("video") == "video")
        #expect(IndirmeAraci.ekleTuru("ses") == "audio")
        #expect(IndirmeAraci.ekleTuru("m4a") == "audio")
    }

    @Test func aramaHatasiSonucYoklugundanAyrilir() {
        let m = IndirmeAraci.aramaHatasiMetni("VPN açıksa kapatıp yeniden dene.")
        #expect(m.hasPrefix("İNDİRİLMEDİ"))
        #expect(m.contains("VPN açıksa"))
        #expect(!m.contains("bulunamadı"))
    }

    // MARK: Son adres denetimi (bulgu 117) — ağsız: IP sabitleri ve reddedilen adlar DNS'e gitmez

    @Test func sonAdresIcAgaGidemez() {
        #expect(!IndirmeTemsilcisi.sonAdresGuvenli(nil))
        #expect(!IndirmeTemsilcisi.sonAdresGuvenli(URL(string: "https://192.168.1.1/x")))
        #expect(!IndirmeTemsilcisi.sonAdresGuvenli(URL(string: "http://93.184.215.14/x")))
        #expect(!IndirmeTemsilcisi.sonAdresGuvenli(URL(string: "https://localhost/x")))
        #expect(!IndirmeTemsilcisi.sonAdresGuvenli(URL(string: "https://10.0.0.5/dosya.pdf")))
        #expect(IndirmeTemsilcisi.sonAdresGuvenli(URL(string: "https://93.184.215.14/dosya.pdf")))
    }
}

@Suite("Dosya adı Unicode")
struct DosyaAdiUnicodeTestleri {
    @Test func ayrisikTurkceAdBozulmaz() {
        // Dosya sistemi adları NFD gelir: "İ" = "I" + U+0307; eskiden "I_ki" oluyordu.
        let nfd = "Ödev İki şçğü.pdf".decomposedStringWithCanonicalMapping
        let ad = IndirmeYoneticisi.dosyaAdi(nfd)
        #expect(ad == "Ödev İki şçğü.pdf")
        #expect(!ad.contains("_"))
    }
}
