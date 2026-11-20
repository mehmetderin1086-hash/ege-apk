import Foundation
import Testing
@testable import Asistan

/// Gerçek sitelerde web okuma çekirdeği (modele çıkmaz, ücretsiz). Yalnız ASISTAN_CANLI=1 ile koşar.
@Suite("Canlı web okuma", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1")) @MainActor
struct WebGucuCanliTestleri {
    @Test(arguments: [
        "https://tr.wikipedia.org/wiki/Mitoz",
        "https://www.meb.gov.tr/",
        "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf",
        "https://developer.apple.com/documentation/foundationmodels",
        "https://www.trthaber.com/",
    ])
    func gercek_sayfa_okunur(_ adres: String) async throws {
        await SayfaOnbellegi.ortak.temizle()
        let basla = Date()
        // JavaScript ile dolan sayfa (Apple belgeleri) gerçek kullanımdaki gibi tarayıcı yedeğiyle okunur.
        let p = try await SayfaOkuyucu.oku(try #require(URL(string: adres)), tarayiciYedegi: adres.contains("developer.apple.com"))
        let cikti = WebOkuma.bicimle(p, odak: nil, sinir: 6000)
        print("CANLI OKUMA \(adres) \(Int(Date().timeIntervalSince(basla) * 1000)) ms · başlık: \(p.baslik) · metin \(p.metin.count) · yapısal \(p.yapisal.count) · gömülü \(p.gomulu.count)\n\(cikti.prefix(900))\n---")
        #expect(p.metin.count + p.gomulu.count >= 20)
        #expect(!cikti.contains("Ã"), "kodlama bozuk (UTF-8 çift çözüm)")
        #expect(!cikti.contains("&amp;") && !cikti.contains("&#"), "çözülmemiş varlık")
        #expect(!p.metin.contains("  "), "çift boşluk")
    }

    @Test func yedek_arama_motoru_sonuc_verir() async throws {
        let r = await YedekArama.listele("mitoz bölünme evreleri")
        print("YEDEK ARAMA:", r.prefix(5).map { "\($0.baslik) — \($0.url.absoluteString)" })
        #expect(r.count >= 3)
    }

    @Test func robots_ve_sitemap_okunur() async throws {
        let r = await VeriKaziAraci.robots(host: "www.wikipedia.org")
        print("ROBOTS kural:", r.kurallar.count, "sitemap:", r.sitemaplar)
        let s = await VeriKaziAraci.sitemapAdresleri([try #require(URL(string: "https://www.apple.com/sitemap.xml"))], site: "apple.com")
        print("SITEMAP adres sayısı:", s.count, s.prefix(3))
        #expect(s.count > 10)
    }
}
