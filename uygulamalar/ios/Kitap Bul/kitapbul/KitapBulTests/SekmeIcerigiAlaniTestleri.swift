import Testing
import CoreGraphics
@testable import _01

/// Sekme çubuğu payı ve tembel olmayan ızgaranın sütun hesabı (Aşama 1, GOR-1).
@MainActor
struct SekmeIcerigiAlaniTestleri {
    // iPhone Air ölçüleri: içerik 0–829, çubuk 829–912.
    private let alan = CGRect(x: 0, y: 0, width: 420, height: 829)

    @Test func bitisikCubukIcinPayAyrilir() {
        // Eski hesapta `intersects` bitişik çerçevelerde false döndüğü için pay 0'dı.
        let cubuk = CGRect(x: 0, y: 829, width: 420, height: 83)
        #expect(!cubuk.intersects(alan))
        #expect(SekmeCubuguPayi.ayrilacak(alan: alan, cubuk: cubuk) == 8)
    }

    @Test func ortusenCubukIcinOrtusmeVePayAyrilir() {
        let tamEkran = CGRect(x: 0, y: 0, width: 420, height: 912)
        let cubuk = CGRect(x: 0, y: 829, width: 420, height: 83)
        #expect(SekmeCubuguPayi.ayrilacak(alan: tamEkran, cubuk: cubuk) == 91)
    }

    @Test func uzaktakiCubukIcinPayAyrilmaz() {
        let asagida = CGRect(x: 0, y: 900, width: 420, height: 83)
        #expect(SekmeCubuguPayi.ayrilacak(alan: alan, cubuk: asagida) == 0)
        let yukarida = CGRect(x: 0, y: -100, width: 420, height: 50)
        #expect(SekmeCubuguPayi.ayrilacak(alan: alan, cubuk: yukarida) == 0)
    }

    @Test func payAlanYuksekliginiAsmaz() {
        let kisa = CGRect(x: 0, y: 0, width: 420, height: 4)
        let cubuk = CGRect(x: 0, y: 0, width: 420, height: 83)
        #expect(SekmeCubuguPayi.ayrilacak(alan: kisa, cubuk: cubuk) == 4)
    }

    @Test func sabitSutunluIzgaraGenisligiEsitBoler() {
        let olcu = EsitSutunIzgara(sutun: 3, yatayAralik: 10).sutunOlcusu(388)
        #expect(olcu.sayi == 3)
        #expect(abs(olcu.hucre - 122.666) < 0.01)
    }

    @Test func uyarlananIzgaraEnKucukGenisligeGoreSutunSecer() {
        // Ekle kartları: telefonda 3 sütun, erişilebilirlik boyutunda tek sütun.
        let telefon = EsitSutunIzgara(enKucukGenislik: 108, enBuyukGenislik: 180, yatayAralik: 8).sutunOlcusu(388)
        #expect(telefon.sayi == 3)
        #expect(telefon.hucre == 124)
        let buyukYazi = EsitSutunIzgara(enKucukGenislik: 230, yatayAralik: 8).sutunOlcusu(388)
        #expect(buyukYazi.sayi == 1)
        // Dar alanda en büyük genişlik sınırı uygulanır.
        let dar = EsitSutunIzgara(enKucukGenislik: 108, enBuyukGenislik: 180, yatayAralik: 8).sutunOlcusu(200)
        #expect(dar.sayi == 1)
        #expect(dar.hucre == 180)
    }

    @Test func sinirsizOneridenCokmez() {
        let olcu = EsitSutunIzgara(enKucukGenislik: 108, yatayAralik: 8).sutunOlcusu(.infinity)
        #expect(olcu.sayi == 1)
        #expect(olcu.hucre == 108)
        #expect(EsitSutunIzgara(sutun: 2).sutunOlcusu(nil).sayi == 2)
    }
}
