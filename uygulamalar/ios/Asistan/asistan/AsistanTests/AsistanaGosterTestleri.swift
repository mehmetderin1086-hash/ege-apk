import Foundation
import Testing
@testable import Asistan

/// P1.11 "Asistan'a göster" kestirmesi: saf hazırlık, eski istek.json uyumu, dış kaynak kararı, varsayılan istem.
@Suite("Asistan'a göster (P1.11)") struct AsistanaGosterTestleri {
    @Test func dokuzDosyaReddedilir() {
        let girdiler = (0..<9).map { _ in (ad: "a.png", uzanti: Optional("png"), veri: Data([1])) }
        guard case .failure(let h) = GosterHazirlik.hazirla(girdiler) else { Issue.record("9 dosya kabul edildi"); return }
        #expect(h == .cokFazlaDosya)
        #expect(h.errorDescription?.contains("8") == true)
        let sekiz = Array(girdiler.prefix(8))
        guard case .success(let s) = GosterHazirlik.hazirla(sekiz) else { Issue.record("8 dosya reddedildi"); return }
        #expect(s.count == 8)
    }

    @Test func kirkBirMegabaytReddedilir() {
        let buyuk = [(ad: "b.pdf", uzanti: Optional("pdf"), veri: Data(count: 41 * 1024 * 1024))]
        guard case .failure(let h) = GosterHazirlik.hazirla(buyuk) else { Issue.record("41 MB kabul edildi"); return }
        #expect(h == .cokBuyuk)
        #expect(h.errorDescription?.contains("40 MB") == true)
        // Sınırın tam üstü değil, toplam: 2 × 20 MB + 1 bayt reddedilir.
        let iki = [(ad: "a", uzanti: Optional<String>.none, veri: Data(count: 20 * 1024 * 1024)),
                   (ad: "b", uzanti: Optional<String>.none, veri: Data(count: 20 * 1024 * 1024 + 1))]
        guard case .failure = GosterHazirlik.hazirla(iki) else { Issue.record("toplam sınır uygulanmadı"); return }
    }

    @Test func bosAdUzantiliAdOlur() {
        let girdiler = [(ad: "", uzanti: Optional("png"), veri: Data([1])),
                        (ad: "  ", uzanti: Optional<String>.none, veri: Data([2])),
                        (ad: "Rapor.pdf", uzanti: Optional("pdf"), veri: Data([3])),
                        (ad: "Ekran", uzanti: Optional("jpeg"), veri: Data([4]))]
        guard case .success(let s) = GosterHazirlik.hazirla(girdiler) else { Issue.record("hazırlık başarısız"); return }
        #expect(s.map { $0.ad } == ["ekran-1.png", "ekran-2.dat", "Rapor.pdf", "Ekran.jpeg"])
        #expect(s.map { $0.veri } == [Data([1]), Data([2]), Data([3]), Data([4])])
    }

    @Test func eskiIstekJsonCozulur() throws {
        // Paylaşım uzantısının bugüne dek yazdığı biçim: kaynak anahtarı yok.
        let eski = try JSONEncoder().encode(PaylasimKutusu.Istek(istem: "Özetle", metin: "m", dosyalar: ["0-a.png"]))
        var sozluk = try #require(JSONSerialization.jsonObject(with: eski) as? [String: Any])
        sozluk.removeValue(forKey: "kaynak")
        let veri = try JSONSerialization.data(withJSONObject: sozluk)
        let i = try JSONDecoder().decode(PaylasimKutusu.Istek.self, from: veri)
        #expect(i.kaynak == nil)
        #expect(i.istem == "Özetle" && i.dosyalar == ["0-a.png"])
        // Yeni alan gidip geliyor.
        let yeni = PaylasimKutusu.Istek(istem: "", kaynak: PaylasimKutusu.gosterKaynagi)
        let geri = try JSONDecoder().decode(PaylasimKutusu.Istek.self, from: JSONEncoder().encode(yeni))
        #expect(geri == yeni && geri.kaynak == "goster")
    }

    @Test func disKaynakKarari() {
        #expect(PaylasimKutusu.disKaynakMi(.init(istem: "x")))
        #expect(!PaylasimKutusu.disKaynakMi(.init(istem: "x", kaynak: PaylasimKutusu.gosterKaynagi)))
        #expect(PaylasimKutusu.disKaynakMi(.init(istem: "x", kaynak: "baska")))
    }

    @Test func varsayilanIstem() {
        let goster = PaylasimKutusu.istemMetni(.init(istem: "  ", kaynak: PaylasimKutusu.gosterKaynagi))
        #expect(goster.hasPrefix("Bu ekran görüntüsünde/dosyada ne var?"))
        #expect(PaylasimKutusu.istemMetni(.init(istem: " ")).hasPrefix("Bunu incele"))
        #expect(PaylasimKutusu.istemMetni(.init(istem: "Bu ne?", kaynak: PaylasimKutusu.gosterKaynagi)) == "Bu ne?")
    }
}
