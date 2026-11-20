import Testing
import Foundation
@testable import _01

/// Künye kaynak zinciri: "kitap yok" ile "kaynaklara ulaşılamadı" ayrımı (ağa çıkmadan).
@MainActor
struct KunyeKaynakTestleri {
    @Test func hicbirKaynakYanitVermediyseUlasilamadi() {
        #expect(KaynakDurumu(yanitVeren: 0, ulasilamayan: 3).hicbirineUlasilamadi)
        #expect(!KaynakDurumu(yanitVeren: 1, ulasilamayan: 2).hicbirineUlasilamadi)
        #expect(KaynakDurumu(yanitVeren: 1, ulasilamayan: 2).kismenUlasilamadi)
        #expect(!KaynakDurumu(yanitVeren: 3, ulasilamayan: 0).kismenUlasilamadi)
        #expect(!KaynakDurumu().hicbirineUlasilamadi, "Hiç kaynak denenmediyse erişim sorunu sayılmaz")
    }

    @Test func bulunamadiMesajiNedeniAyirir() throws {
        var kayit = AmazonBookMetadata()
        kayit.title = "Kürk Mantolu Madonna"
        let bulundu = KunyeSonucu(meta: kayit, durum: KaynakDurumu(yanitVeren: 1, ulasilamayan: 1))
        #expect(bulundu.bulunamadiMesaji == nil && !bulundu.erisimSorunuVar, "Kayıt geldiyse erişim sorunu söylenmez")

        let yok = KunyeSonucu(meta: nil, durum: KaynakDurumu(yanitVeren: 3, ulasilamayan: 0))
        let kismen = KunyeSonucu(meta: nil, durum: KaynakDurumu(yanitVeren: 1, ulasilamayan: 2))
        let hic = KunyeSonucu(meta: nil, durum: KaynakDurumu(yanitVeren: 0, ulasilamayan: 3))
        #expect(!yok.erisimSorunuVar && kismen.erisimSorunuVar && hic.erisimSorunuVar)
        let mesajlar = try [yok, kismen, hic].map { try #require($0.bulunamadiMesaji) }
        #expect(Set(mesajlar).count == 3, "Üç durum ayrı söylenir")
        #expect(mesajlar[0].contains("bulunamadı") && !mesajlar[0].contains("ulaşılamadı"))
        // Amazon engelli + Google kotada + OpenLibrary "yok": kesin "kitap yok" denmez
        #expect(mesajlar[1].contains("Bazı") && mesajlar[1].contains("ulaşılamadı"))
        #expect(mesajlar[2].hasPrefix("Çevrimiçi kaynaklara ulaşılamadı"))
    }

    @Test func amazonRobotSayfasiTaninir() {
        let robot = """
        <html><body><form method="get" action="/errors/validateCaptcha">
        <p>Enter the characters you see below</p>
        <p>Sorry, we just need to make sure you're not a robot. api-services-support@amazon.com</p>
        </form></body></html>
        """
        let urun = "<html><body><span id=\"productTitle\">Kürk Mantolu Madonna</span></body></html>"
        #expect(AmazonBookScraper.isRobotCheck(html: robot))
        #expect(!AmazonBookScraper.isRobotCheck(html: urun))
        #expect(!AmazonBookScraper.isRobotCheck(html: ""))
    }

    @Test func yenidenDenemeKaliciHatayiFirlatir() async {
        var deneme = 0
        await #expect(throws: URLError.self) {
            _ = try await BookMetadataService.withRetryThrowing { () async throws -> Int? in
                deneme += 1
                throw URLError(.badServerResponse)
            }
        }
        #expect(deneme == 1, "Kalıcı hatada boşuna beklenmez")

        let bos: Int? = await BookMetadataService.withRetry { nil }
        #expect(bos == nil)
        let dolu: Int? = await BookMetadataService.withRetry { 7 }
        #expect(dolu == 7)
    }
}
