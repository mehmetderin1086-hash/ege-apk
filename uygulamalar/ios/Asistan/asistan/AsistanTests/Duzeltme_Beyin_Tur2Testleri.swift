import Testing
import Foundation
@testable import Asistan

/// İkinci inceleme turu düzeltmeleri (beyin alanı): iddia ailesi eşlemesi, oylama uygunluğu, birimli kısıt,
/// DNS hata kapsamı, -1004 metni ve tanı paketinde ham istem. Ağ, izin ya da model gerektirmez.
@Suite("Beyin tur 2 düzeltmeleri")
struct Duzeltme_Beyin_Tur2Testleri {
    @Test func iddiaAileleriDogruAraclaEslenir() {
        #expect(EylemIddiasi.denetle("Zamanlayıcıyı başlattım.", basariliAraclar: ["zamanlayici"]) == nil)
        #expect(EylemIddiasi.denetle("İndirmeyi başlattım.", basariliAraclar: ["indirmeler"]) == nil)
        #expect(EylemIddiasi.denetle("Kaydı sunucuya ekledim.", basariliAraclar: ["mcp"]) == nil)
        #expect(EylemIddiasi.denetle("Projeyi kurdum.", basariliAraclar: ["proje"]) == nil)
        #expect(EylemIddiasi.denetle("Zamanlayıcıyı başlattım.", basariliAraclar: ["hafiza"])?.ad == "ac")
    }

    @Test func birimliMiktarKisitSayilmaz() {
        #expect(KisitDenetimi.yerelKisitlar("3 sayfalık rapor yaz").isEmpty)
        #expect(KisitDenetimi.yerelKisitlar("on dakikalık bir özet hazırla").isEmpty)
        #expect(KisitDenetimi.yerelKisitlar("5 maddelik liste çıkar").isEmpty)
        #expect(KisitDenetimi.yerelKisitlar("kuran meali 15. cüz indir").contains("15"))
        #expect(KisitDenetimi.birimliMiktarMi("3 sayfalık"))
        #expect(!KisitDenetimi.birimliMiktarMi("15. cüz"))
        #expect(IstemSuzgeci.etkinKisitlariSec(suzgec: ["3 sayfalık", "Ayhan"], ham: "x") == ["Ayhan"])
    }

    @Test func dnsHatasiRotayiKapatmaz() {
        #expect(ModelZinciri.sinifla(URLError(.cannotFindHost), yol: .vekil).kapsam == .istek)
        #expect(ModelZinciri.sinifla(URLError(.dnsLookupFailed), yol: .telefon).kapsam == .istek)
        #expect(ModelZinciri.sinifla(URLError(.cannotConnectToHost), yol: .telefon).kapsam == .rota(30))
    }

    @Test func vekilMetniYalnizTelefonYolundaGecerli() {
        let h = URLError(.cannotConnectToHost)
        #expect(HataSozlugu.metin(h) == HataSozlugu.vekilMetni)
        #expect(HataSozlugu.metin(h, sonYol: .telefon) == HataSozlugu.vekilMetni)
        #expect(HataSozlugu.metin(h, sonYol: .vekil) == HataSozlugu.baglantiMetni)
        #expect(HataSozlugu.metin(h, sonYol: .anahtar) == HataSozlugu.baglantiMetni)
    }

    @Test func taniPaketindeHamIstemGizlenir() {
        let satir = "2026-10-20T10:00:00Z INFO [r=ab] İSTEK kip=oto uzunluk=12 görsel=0 belge=false metin: gizli veli mesajı"
        let temiz = TaniPaketi.istekMetniniGizle(satir)
        #expect(!temiz.contains("gizli"))
        #expect(temiz.hasSuffix("metin: ‹17 karakter›"))
        let baska = "2026-10-20T10:00:00Z INFO MODEL HATA x metin: ab"
        #expect(TaniPaketi.istekMetniniGizle(baska) == baska)
    }
}
