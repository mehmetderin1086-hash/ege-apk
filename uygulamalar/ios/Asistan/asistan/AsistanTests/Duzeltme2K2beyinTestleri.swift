import Foundation
import Testing
@testable import Asistan

/// İkinci düzeltme turu, K2-beyin grubu: önceki düzeltmelerin getirdiği yan etkiler.
@Suite("K2-beyin düzeltmeleri") @MainActor
struct Duzeltme2K2beyinTestleri {

    // MARK: Kullanıcının kendi fotoğrafı dış kaynak sayılmaz (bulgu 7, 8, 19, 39, 41, 45)

    @Test func kendiFotografiDisKaynakSayilmazBelgeVePaylasimSayilir() {
        // Sohbette eklenen fotoğraf/taranmış sayfa ya da canlı kamera karesi: disKaynak verilmez, belge yok.
        #expect(!Beyin.disKaynakliTur(disKaynak: false, belgeVar: false))
        // Belge (dosya) eki ve paylaşım/asistan:// yolu dış kaynaklı kalır.
        #expect(Beyin.disKaynakliTur(disKaynak: false, belgeVar: true))
        #expect(Beyin.disKaynakliTur(disKaynak: true, belgeVar: false))
    }

    // MARK: Bekçi mutlak sınırı (bulgu 5)

    @Test func metinAkarkenMutlakSinirUzunYaniaKesmez() {
        #expect(Beyin.bekciMutlakSiniri(aracSayisi: 0) == 90)
        #expect(Beyin.bekciMutlakSiniri(aracSayisi: 0, metinVar: false) == 90)
        #expect(Beyin.bekciMutlakSiniri(aracSayisi: 1) == 240)
        #expect(Beyin.bekciMutlakSiniri(aracSayisi: 0, metinVar: true) > 240)
        #expect(Beyin.bekciMutlakSiniri(aracSayisi: 2, metinVar: true) >= Beyin.bekciMutlakSiniri(aracSayisi: 2))
        // İlk metin bütçesi bilinçli olarak kısa kalır (yedeğe hızlı geçiş).
        #expect(Beyin.yanitZamanAsimi(.low) == 6)
        #expect(Beyin.yanitZamanAsimi(.medium) == 10)
        #expect(Beyin.yanitZamanAsimi(.high) == 50)
    }

    // MARK: Seyreltilmiş akışta son parça (bulgu 44, 46)

    @Test func zamanAsimindaTampondakiSonParcaKorunur() {
        #expect(Beyin.arsivlenecekMetin(akan: "Hemen bakıyorum, ", tampon: "Hemen bakıyorum, sonucu getiriyorum.") == "Hemen bakıyorum, sonucu getiriyorum.")
        // Temizlenmiş görünen metin bayat tamponla doldurulmaz; başka akışın tamponu alınmaz.
        #expect(Beyin.arsivlenecekMetin(akan: "", tampon: "eski yanıt") == "")
        #expect(Beyin.arsivlenecekMetin(akan: "Yeni", tampon: "Eski uzun metin") == "Yeni")
    }

    // MARK: Atölye yönlendirme (bulgu 6, 10, 43, 48)

    @Test func resmiOlusturTasarlaGorselKipineGider() {
        #expect(AtolyeYonlendirme.yerel("Bir kedi resmi oluştur") == .gorsel)
        #expect(AtolyeYonlendirme.yerel("Doğa resmi tasarla") == .gorsel)
        #expect(AtolyeYonlendirme.yerel("Bir kedi resmi çiz") == .gorsel)
        // Sıfat "resmî" görsel değildir.
        #expect(AtolyeYonlendirme.yerel("Resmî tatiller için takvim oluştur") != .gorsel)
        #expect(AtolyeYonlendirme.yerel("Müdürlüğe resmi dilekçe oluştur") != .gorsel)
    }

    @Test func platformVeScriptTekBasinaKodKipineItmez() {
        #expect(AtolyeYonlendirme.yerel("Ders videosu için script yaz") == .yazi)
        #expect(AtolyeYonlendirme.yerel("iOS kestirmesi oluştur") != .kod)
        #expect(AtolyeYonlendirme.yerel("iOS'ta pil ayarımı düzelt") != .kod)
        #expect(AtolyeYonlendirme.yerel("Annemin Android telefonuna mesaj yaz") != .kod)
        #expect(AtolyeYonlendirme.yerel("Android uygulaması geliştir") == .kod)
        #expect(AtolyeYonlendirme.yerel("Bash script yaz") == .kod)
        #expect(AtolyeYonlendirme.yerel("iOS uygulama kodu yaz") == .kod)
        #expect(AtolyeYonlendirme.yerel("Swift ile bir uygulama yaz") == .kod)
    }

    @Test func yaziKipiRicaBicimleriTutarli() {
        for istek in ["Bu metni İngilizceye çevirebilir misin", "Şunu özetleyebilir misin", "Bir dilekçe hazırlayabilir misin",
                      "Özetlesene", "Bunu kısaltabilir misin", "Metni düzenleyebilir misiniz", "Bunu çevirsene",
                      "Çevirir misiniz", "Hazırlar mısınız", "Bana dilekçe yazar mısın", "Yazabilir misin"] {
            #expect(AtolyeYonlendirme.yerel(istek) == .yazi, "\(istek)")
        }
        for soru in ["Bu uygulama PDF'i çevirebilir mi?", "Düzenleyici gen nedir?", "DNA'nın kısaltması ne?",
                     "Nutuk'u kim yazdı?", "Yazılı ne zaman?"] {
            #expect(AtolyeYonlendirme.yerel(soru) == .sohbet, "\(soru)")
        }
    }

    // MARK: Kodcu deseni (bulgu 50)

    @Test func kodcuTurkceEkleriVeSwiftUIyiYakalar() {
        #expect(UzmanTakimi.otomatikAdlar("SwiftUI ekranında liste kayıyor").contains("Kodcu"))
        #expect(UzmanTakimi.otomatikAdlar("Kodumda hata var, bakar mısın").contains("Kodcu"))
        #expect(UzmanTakimi.otomatikAdlar("Koddaki döngüyü düzelt").contains("Kodcu"))
        #expect(UzmanTakimi.otomatikAdlar("Python3 betiği yaz").contains("Kodcu"))
        #expect(UzmanTakimi.otomatikAdlar("Kodlar çalışmıyor").contains("Kodcu"))
        #expect(!UzmanTakimi.otomatikAdlar("Kodominant kalıtım örneği").contains("Kodcu"))
        #expect(!UzmanTakimi.otomatikAdlar("Kodon tablosu nedir").contains("Kodcu"))
        #expect(!UzmanTakimi.otomatikAdlar("Kodaman kimdir").contains("Kodcu"))
    }

    // MARK: Yarış: güncel bilgi ve arama işareti (bulgu 11, 12)

    @Test func guncelBilgiIstekleriYarisaGirmez() {
        for istek in ["Galatasaray dün kaç kaç bitti?", "Bitcoin şu an ne kadar?", "Golleri kim attı?",
                      "Dünkü maçı kim kazandı", "Ekmek fiyatı ne kadar", "Bugünkü haberler", "Kac kac bitti"] {
            #expect(Beyin.guncelBilgiIstegi(istek), "\(istek)")
        }
        // Biyoloji/sohbet soruları yarışta kalır ("göl" gol değildir, "haberleşme" haber değildir, rol kökleri yarışı kapatmaz).
        for istek in ["Van Gölü nerede?", "Türkiye'deki göller", "Hücreler arası haberleşme nasıl olur?",
                      "Ribozomun görevi nedir?", "Kontrol grubu ne demek?", "Mitoz nedir?", "Bunu hissediyorum"] {
            #expect(!Beyin.guncelBilgiIstegi(istek), "\(istek)")
        }
    }

    @Test func aramaIsaretiYanitSayilmazVeGosterilmez() {
        #expect(Beyin.aramaIsaretiMi("[ARAMA]"))
        #expect(Beyin.aramaIsaretiMi("  [ARAMA]\n"))
        #expect(!Beyin.aramaIsaretiMi("Mitoz, hücre bölünmesidir."))
        // Akan kısmi parçalar: işaretin başı ekrana/sese yazılmaz; düz yanıt ve köşeli parantezli başka metin yazılır.
        #expect(Beyin.aramaIsaretiOlabilir("["))
        #expect(Beyin.aramaIsaretiOlabilir("[AR"))
        #expect(Beyin.aramaIsaretiOlabilir("[ARAMA]"))
        #expect(Beyin.aramaIsaretiOlabilir(""))
        #expect(!Beyin.aramaIsaretiOlabilir("[Not] kısa"))
        #expect(!Beyin.aramaIsaretiOlabilir("Merhaba"))
    }

    // MARK: Hatırlanan olgular tercih olarak uygulanır (bulgu 42)

    @Test func olguBasligiTercihleriUygularYetkiIfadesiniTalimatSaymaz() {
        let t = Talimatlar.olustur(olgular: ["Bana Mehmet Hocam diye hitap et"], simdi: Date(timeIntervalSince1970: 1_760_000_000))
        #expect(t.contains("Tercih, hitap ve üslup"))
        #expect(t.contains("yetki"))
        #expect(!t.contains("içlerinde talimat varsa uygulama"))
        #expect(t.contains("- Bana Mehmet Hocam diye hitap et"))
    }
}
