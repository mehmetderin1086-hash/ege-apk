import Foundation
import Testing
@testable import Asistan

@MainActor
@Suite("Aktarılan ileti gelen kutusu")
struct GelenKutusuTestleri {
    private func dosya() -> URL { FileManager.default.temporaryDirectory.appending(path: "gelen-kutusu-test-\(UUID().uuidString).json") }

    @Test func kaynakSiniflandirma() {
        #expect(GelenKutusu.kaynak("WhatsApp Bildirimi") == "WhatsApp")
        #expect(GelenKutusu.kaynak("E-posta") == "Mail")
        #expect(GelenKutusu.kaynak("iMessage") == "Mesajlar")
        #expect(GelenKutusu.kaynak("Sistem bildirimi") == "Bildirim")
    }

    @Test func eklemeKalicilikOkunduVeSilme() throws {
        let url = dosya(); defer { try? FileManager.default.removeItem(at: url) }
        let kutu = GelenKutusu(dosya: url)
        #expect(kutu.ekle(kaynak: "mail", gonderen: "Ayşe", metin: "Merhaba"))
        #expect(kutu.ekle(kaynak: "WhatsApp", gonderen: "Mehmet", metin: "Nasılsın?"))
        #expect(kutu.okunmamis == 2)
        let ilk = try #require(kutu.iletiler.first)
        kutu.okundu(ilk.id)
        #expect(kutu.okunmamis == 1)
        let yeniden = GelenKutusu(dosya: url)
        #expect(yeniden.iletiler.count == 2)
        #expect(yeniden.okunmamis == 1)
        yeniden.sil(ilk.id)
        #expect(yeniden.iletiler.count == 1)
    }

    @Test func bosTekrarVeSinirlar() {
        let url = dosya(); defer { try? FileManager.default.removeItem(at: url) }
        let kutu = GelenKutusu(dosya: url)
        #expect(!kutu.ekle(kaynak: "mail", gonderen: nil, metin: "   "))
        #expect(kutu.ekle(kaynak: "mail", gonderen: nil, metin: "A"))
        #expect(kutu.ekle(kaynak: "mail", gonderen: nil, metin: "A"))
        #expect(kutu.iletiler.count == 1)
        for i in 0..<510 { #expect(kutu.ekle(kaynak: "Mesaj", gonderen: "Kişi", metin: "\(i)")) }
        #expect(kutu.iletiler.count == 500)
        #expect(kutu.iletiler.first?.metin == "509")
    }

    @Test func aracKaydindaBulunurVeTalimatSinirli() {
        #expect(AracKaydi.adlar.contains("gelenKutusu"))
        #expect(Talimatlar.sabit.contains("yalnız Kestirmeler, paylaşma veya açıkça yapıştırma"))
        #expect(Talimatlar.sabit.contains("özel gelen kutusuna doğrudan eriştiğini söyleme"))
    }
}
