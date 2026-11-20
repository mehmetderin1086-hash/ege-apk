import Foundation
import Testing
@testable import Asistan

/// P1.3 "Yaptım" bekçisi: yapılmamış işe "yaptım" diyen yanıtı yakalayan saf mantık (ağ/izin/model gerekmez).
struct Gelistirme_P1_3_EylemIddiasiTestleri {
    @Test func kurIddiasiAracYokkenYakalanir() {
        let yanit = "Hatırlatıcını yarın 09.00'a kurdum. Başka bir şey ister misin?"
        #expect(EylemIddiasi.denetle(yanit, basariliAraclar: [])?.ad == "kur")
        #expect(EylemIddiasi.denetle(yanit, basariliAraclar: ["hatirlatici"]) == nil)
    }

    @Test func gonderIddiasiIlgisizAracIleYakalanir() {
        #expect(EylemIddiasi.denetle("Mesajı Ahmet'e gönderdim.", basariliAraclar: ["kisiler"])?.ad == "gonder")
        #expect(EylemIddiasi.denetle("Mesajı Ahmet'e gönderdim.", basariliAraclar: ["iletisim"]) == nil)
    }

    @Test func altAjanHerAiledeSayilir() {
        #expect(EylemIddiasi.denetle("Takvimine ekledim.", basariliAraclar: ["altAjanlar"]) == nil)
    }

    @Test func dosyaKuraliDosyaSozcuguIster() {
        #expect(EylemIddiasi.denetle("Ders planını hazırladım: giriş, gelişme, sonuç.", basariliAraclar: []) == nil)
        #expect(EylemIddiasi.denetle("Senin için bir tablo hazırladım:", basariliAraclar: []) == nil)
        #expect(EylemIddiasi.denetle("PDF dosyasını hazırladım", basariliAraclar: [])?.ad == "dosya")
        #expect(EylemIddiasi.denetle("PDF dosyasını hazırladım", basariliAraclar: ["ofisBelgesiOlustur"]) == nil)
    }

    @Test func olumsuzVeIstekBicimleriSayilmaz() {
        #expect(EylemIddiasi.denetle("Hatırlatıcıyı kuramadım, izin gerekiyor.", basariliAraclar: []) == nil)
        #expect(EylemIddiasi.denetle("Takvime ekleyemedim.", basariliAraclar: []) == nil)
        #expect(EylemIddiasi.denetle("Mesajı göndermemi ister misin?", basariliAraclar: []) == nil)
    }

    @Test func edilgenVeUcuncuSahisBilgiYanitlariSayilmaz() {
        #expect(EylemIddiasi.denetle("Türkiye Cumhuriyeti 1923'te kuruldu.", basariliAraclar: []) == nil)
        #expect(EylemIddiasi.denetle("Apollo 11 Ay'a gönderildi.", basariliAraclar: []) == nil)
        #expect(EylemIddiasi.denetle("Bu rekor 1998'de kaydedildi.", basariliAraclar: []) == nil)
    }

    @Test func yalnizIlkIkiCumleyeBakilir() {
        let yanit = "Mitoz bir hücre bölünmesidir. İki özdeş hücre oluşur. Sonra notlarına ekledim."
        #expect(EylemIddiasi.denetle(yanit, basariliAraclar: []) == nil)
        #expect(EylemIddiasi.denetle("Mitoz bölünmedir. Notlarına ekledim.", basariliAraclar: [])?.ad == "ekle")
    }

    @Test func sayidakiNoktaCumleBolmez() {
        #expect(EylemIddiasi.cumleler("Saat 09.30'da. İkinci.") == ["Saat 09.30'da.", "İkinci."])
        #expect(EylemIddiasi.ilkIkiCumle("Bir. İki! Üç?") == "Bir. İki!")
    }

    @Test func ikiNoktaIleBitenTanitimCumlesiSayilmaz() {
        #expect(EylemIddiasi.denetle("Programını şöyle ayarladım:\n- 08.00 kalk", basariliAraclar: []) == nil)
    }

    @Test func supheliBaslangicKokleri() {
        #expect(EylemIddiasi.supheliBaslangic("Tamam, kurd"))
        #expect(EylemIddiasi.supheliBaslangic("Şarkıyı çalıyor"))
        #expect(!EylemIddiasi.supheliBaslangic("Mitoz"))
    }

    @Test func akistaTutmaKarari() {
        // Bitmemiş şüpheli cümle tutulur, cümle iddiasız biterse bırakılır.
        #expect(EylemIddiasi.akistaTut("Tamam, hatırlatıcını kurd"))
        #expect(!EylemIddiasi.akistaTut("Tamam, hatırlatıcının kurduğu düzen şöyle."))
        // Kesin iddia hep tutulur.
        #expect(EylemIddiasi.akistaTut("Hatırlatıcını kurdum"))
        #expect(EylemIddiasi.akistaTut("Hatırlatıcını kurdum. Yarın 9'da çalacak ve sonra"))
        // Şüphesiz metin ve 80 karakteri aşan açık cümle tutulmaz.
        #expect(!EylemIddiasi.akistaTut("Mitoz bölünmesinde"))
        #expect(!EylemIddiasi.akistaTut(String(repeating: "uzun ", count: 20) + "hazirlad"))
        // İlk iki cümle bittiyse sonraki şüpheli kök beklemez.
        #expect(!EylemIddiasi.akistaTut("Bir. İki. Sonra kurd"))
    }

    @Test func anlatiIstegiTaninir() {
        #expect(EylemIddiasi.anlatiIstegi("Bana kısa bir hikaye yaz"))
        #expect(EylemIddiasi.anlatiIstegi("Bir masal anlat"))
        #expect(!EylemIddiasi.anlatiIstegi("Yarın 9'a hatırlatıcı kur"))
    }
}
