import Foundation
import Testing
@testable import Asistan

@Suite("Ücretsiz servisler")
struct UcretsizServisTestleri {
    @Test func paraVeUlkeKodlariTurkceAdlariKabulEder() {
        #expect(UcretsizServisAraci.paraKodu("TL") == "TRY")
        #expect(UcretsizServisAraci.paraKodu("Amerikan doları") == "USD")
        #expect(UcretsizServisAraci.paraKodu("sterlin") == "GBP")
        #expect(UcretsizServisAraci.paraKodu("US$") == "")
        #expect(UcretsizServisAraci.ulkeKodu("Türkiye") == "TR")
        #expect(UcretsizServisAraci.ulkeKodu("Almanya") == "DE")
    }

    @Test func dovizDonusumuKurVeTarihIcerir() {
        let y = UcretsizServisAraci.DovizYaniti(date: "2026-10-20", base: "TRY", quote: "USD", rate: 0.02)
        let m = UcretsizServisAraci.dovizMetni(y, miktar: 100)
        #expect(m.contains("100 TRY = 2 USD"))
        #expect(m.contains("2026-10-20"))
        #expect(m.contains("alış/satış kuru değil"))
    }

    @Test func dunyaBankasiUlkeleriAyiklanir() throws {
        let veri = Data(#"[{"page":1},[{"id":"TUR","iso2Code":"TR","name":"Turkiye","region":{"value":"Europe & Central Asia"},"incomeLevel":{"value":"Upper middle income"},"capitalCity":"Ankara"},{"id":"WLD","iso2Code":"1W","name":"World","region":{"value":"Aggregates"},"incomeLevel":{"value":"Aggregates"},"capitalCity":""}]]"#.utf8)
        let ulkeler = try UcretsizServisAraci.ulkeleriCoz(veri)
        #expect(ulkeler == [.init(kod2: "TR", kod3: "TUR", ad: "Turkiye", baskent: "Ankara", bolge: "Europe & Central Asia", gelir: "Upper middle income")])
        #expect(UcretsizServisAraci.ulkeMetni(ulkeler[0]).contains("Başkent: Ankara"))
    }

    @Test func kitapVeTatilCiktilariSinirliVeKaynakli() {
        let kitaplar = UcretsizServisAraci.KitapYaniti(numFound: 1, docs: [
            .init(key: "/works/OL1W", title: "İnce Memed", author_name: ["Yaşar Kemal"], first_publish_year: 1955, language: ["tur"], isbn: ["123"]),
        ])
        let kitap = UcretsizServisAraci.kitapMetni(kitaplar, sorgu: "İnce Memed")
        #expect(kitap.contains("Yaşar Kemal"))
        #expect(kitap.contains("https://openlibrary.org/works/OL1W"))
        let tatil = UcretsizServisAraci.tatilMetni([.init(date: "2026-10-29", localName: "Cumhuriyet Bayramı", name: "Republic Day")], kod: "TR", yil: 2026)
        #expect(tatil.contains("2026-10-29: Cumhuriyet Bayramı"))
    }

    @MainActor @Test func aracKayitliVeSaltOkunur() {
        #expect(AracKaydi.adlar.contains("ucretsizServis"))
        #expect(KanitTamponu.veriAraclari.contains("ucretsizServis"))
        #expect(!GorevGunlugu.yanEtkiliMi("ucretsizServis", islem: "doviz"))
        #expect(!CanliHizliIstemci.uygun("100 dolar kaç TL"))
        #expect(!CanliHizliIstemci.uygun("Almanya resmi tatilleri"))
    }
}

@Suite("Ücretsiz servisler canlı", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
struct UcretsizServisCanliTestleri {
    @Test func dortAnahtarsizHizmetCalisir() async throws {
        let arac = UcretsizServisAraci()
        let doviz = try await arac.call(arguments: .init(islem: "doviz", sorgu: nil, kaynakPara: "TRY", hedefPara: "USD", miktar: 100, ulkeKodu: nil, yil: nil))
        #expect(doviz.contains("Frankfurter"))
        let ulke = try await arac.call(arguments: .init(islem: "ulke", sorgu: "TR", kaynakPara: nil, hedefPara: nil, miktar: nil, ulkeKodu: nil, yil: nil))
        #expect(ulke.contains("Ankara"))
        let kitap = try await arac.call(arguments: .init(islem: "kitap", sorgu: "İnce Memed", kaynakPara: nil, hedefPara: nil, miktar: nil, ulkeKodu: nil, yil: nil))
        #expect(kitap.contains("Yaşar Kemal"))
        let tatil = try await arac.call(arguments: .init(islem: "tatil", sorgu: nil, kaynakPara: nil, hedefPara: nil, miktar: nil, ulkeKodu: "TR", yil: 2026))
        #expect(tatil.contains("Cumhuriyet Bayramı"))
    }
}
