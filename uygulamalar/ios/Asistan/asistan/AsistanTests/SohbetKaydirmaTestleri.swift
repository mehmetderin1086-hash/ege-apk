import Testing
import Foundation
@testable import Asistan

/// P1.7: "↓" düğmesindeki "yeni" noktası ve sohbet içi aramada eşleşmeler arası gezinme (saf yardımcılar).
@Suite("P1.7 sohbet kaydırma ve arama gezinmesi")
@MainActor
struct SohbetKaydirmaTestleri {

    // MARK: Yeni noktası

    @Test("Altta iken nokta hep sönük")
    func alttaNoktaYok() {
        #expect(!SohbetEkrani.yeniNoktasi(onceki: false, alttaMi: true, icerikGeldi: true))
        #expect(!SohbetEkrani.yeniNoktasi(onceki: true, alttaMi: true, icerikGeldi: true))
        #expect(!SohbetEkrani.yeniNoktasi(onceki: true, alttaMi: true, icerikGeldi: false))
    }

    @Test("Yukarıdayken içerik gelince yanar, kalır; alta inince söner")
    func yukaridaNoktaYanar() {
        var nokta = SohbetEkrani.yeniNoktasi(onceki: false, alttaMi: false, icerikGeldi: false)
        #expect(!nokta)
        nokta = SohbetEkrani.yeniNoktasi(onceki: nokta, alttaMi: false, icerikGeldi: true)
        #expect(nokta)
        // İçerik gelmese de yukarıda kaldıkça söner değil.
        nokta = SohbetEkrani.yeniNoktasi(onceki: nokta, alttaMi: false, icerikGeldi: false)
        #expect(nokta)
        nokta = SohbetEkrani.yeniNoktasi(onceki: nokta, alttaMi: true, icerikGeldi: false)
        #expect(!nokta)
    }

    // MARK: Arama eşleşmeleri

    @Test("Türkçe büyük/küçük harf duyarsız eşleşir")
    func buyukKucukHarf() {
        let a = UUID(), b = UUID()
        let ogeler: [(id: UUID, metin: String)] = [(id: a, metin: "Sesim geliyor mu?"), (id: b, metin: "Evet, DUYUYORUM.")]
        #expect(SohbetEkrani.aramaEslesmeleri(ogeler, sorgu: "duyuyorum") == [b])
        #expect(SohbetEkrani.aramaEslesmeleri(ogeler, sorgu: "evet, duyuyorum") == [b])
        #expect(SohbetEkrani.aramaEslesmeleri(ogeler, sorgu: "GELEN").isEmpty)
    }

    @Test("Boş sorgu boş liste verir")
    func bosSorgu() {
        let ogeler: [(id: UUID, metin: String)] = [(id: UUID(), metin: "mitoz")]
        #expect(SohbetEkrani.aramaEslesmeleri(ogeler, sorgu: "").isEmpty)
        #expect(SohbetEkrani.aramaEslesmeleri([], sorgu: "mitoz").isEmpty)
    }

    @Test("Eşleşmeler sohbet sırasını korur")
    func siraKorunur() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let ogeler: [(id: UUID, metin: String)] = [
            (id: a, metin: "Mitoz bölünme"), (id: b, metin: "Mayoz nedir?"),
            (id: c, metin: "mitoz evreleri"), (id: d, metin: "Hücre döngüsünde MiTOZ")
        ]
        #expect(SohbetEkrani.aramaEslesmeleri(ogeler, sorgu: "mitoz") == [a, c, d])
    }

    // MARK: Gezinme adımı ve sınırlama

    @Test("Adım dairesel döner; adet 0 iken 0")
    func aramaAdimi() {
        #expect(SohbetEkrani.aramaAdimi(2, adet: 3, ileri: true) == 0)
        #expect(SohbetEkrani.aramaAdimi(0, adet: 3, ileri: false) == 2)
        #expect(SohbetEkrani.aramaAdimi(0, adet: 3, ileri: true) == 1)
        #expect(SohbetEkrani.aramaAdimi(2, adet: 3, ileri: false) == 1)
        #expect(SohbetEkrani.aramaAdimi(0, adet: 1, ileri: true) == 0)
        #expect(SohbetEkrani.aramaAdimi(0, adet: 0, ileri: true) == 0)
        #expect(SohbetEkrani.aramaAdimi(4, adet: 0, ileri: false) == 0)
    }

    @Test("Sıra eşleşme sayısına sınırlanır (dizi taşmaz)")
    func aramaSinirla() {
        #expect(SohbetEkrani.aramaSinirla(5, adet: 3) == 2)
        #expect(SohbetEkrani.aramaSinirla(0, adet: 0) == 0)
        #expect(SohbetEkrani.aramaSinirla(3, adet: 0) == 0)
        #expect(SohbetEkrani.aramaSinirla(-1, adet: 3) == 0)
        #expect(SohbetEkrani.aramaSinirla(1, adet: 3) == 1)
    }
}
