import Testing
import Foundation
import CoreGraphics
@testable import _01

@MainActor
struct RafDilimlemeTestleri {
    @Test func satirlarDuzeltilir() {
        // Sınır dışı kırpılır, ince satır atılır, büyük ölçüde örtüşenler birleşir, sıralanır
        let sonuc = RafDilimleyici.duzelt([0.5...0.7, -0.2...0.3, 0.1...0.32, 0.9...0.92])
        #expect(sonuc == [0.0...0.32, 0.5...0.7])
        // Hiç geçerli satır yoksa tüm fotoğraf
        #expect(RafDilimleyici.duzelt([]) == [0...1])
        #expect(RafDilimleyici.duzelt([0.5...0.51]) == [0...1])
    }

    @Test func degenVeHafifOrtusenSatirlarAyriKalir() {
        // Boşluk doldurma tam değen satırlar üretir; model komşu rafları hafif örtüşük verebilir
        let degen: [ClosedRange<Double>] = [0...0.33, 0.33...0.66, 0.66...1]
        #expect(RafDilimleyici.duzelt(degen) == degen)
        let hafif: [ClosedRange<Double>] = [0.1...0.34, 0.32...0.6]
        #expect(RafDilimleyici.duzelt(hafif) == hafif)
        // İkinci uygulama sonucu değiştirmez (dilimAlanlari yeniden çağırır)
        #expect(RafDilimleyici.duzelt(RafDilimleyici.duzelt(hafif)) == hafif)
    }

    @Test func kacirilanRafBosluktanYakalanirVeDilimlenir() {
        // 0.4–0.65 arası boşluk (0.25) ortanca satır yüksekliğinin (0.15) %90'ından büyük → satır eklenir
        let satirlar: [ClosedRange<Double>] = [0.05...0.2, 0.25...0.4, 0.65...0.8]
        let dolu = RafDilimleyici.bosluklariDoldur(satirlar)
        #expect(dolu == [0.05...0.2, 0.25...0.4, 0.4...0.65, 0.65...0.8])
        // Dilimleme eklenen satırı geri birleştirmez; değen satırların kesitleri (pay yüzünden) piksel paylaşır
        let dilimler = RafDilimleyici.dilimAlanlari(genislik: 4284, yukseklik: 5712, satirlar: dolu)
        #expect(Set(dilimler.map(\.satir)).count == 4)
        #expect(dilimler.first { $0.satir == 0 }?.ustBindirmeli == false)
        #expect(dilimler.first { $0.satir == 2 }?.ustBindirmeli == true)
        // Arada geniş raf tahtası olan satırların kesitleri ayrıktır
        let ayrik = RafDilimleyici.dilimAlanlari(genislik: 4284, yukseklik: 5712, satirlar: [0.1...0.3, 0.4...0.6])
        #expect(ayrik.allSatisfy { !$0.ustBindirmeli })
        // Küçük raf tahtası boşlukları eklenmez; tek satırda değişiklik yok
        #expect(RafDilimleyici.bosluklariDoldur([0.1...0.3, 0.35...0.55]) == [0.1...0.3, 0.35...0.55])
        #expect(RafDilimleyici.bosluklariDoldur([0.3...0.7]) == [0.3...0.7])
    }

    @Test func kucukFotografDilimlenmez() {
        #expect(!RafDilimleyici.dilimlemeGerekli(genislik: 1600, yukseklik: 1200))
        #expect(RafDilimleyici.dilimlemeGerekli(genislik: 5712, yukseklik: 4284))
        #expect(RafDilimleyici.dilimlemeGerekli(genislik: 1200, yukseklik: 3000))
        #expect(RafDilimleyici.dilimAlanlari(genislik: 1600, yukseklik: 1200, satirlar: [0...1]).count == 1)
        #expect(RafDilimleyici.dilimAlanlari(genislik: 0, yukseklik: 10, satirlar: [0...1]).isEmpty)
    }

    @Test func tekRafGenisFotografSeritlereBolunur() {
        // 5712 px genişlik, hedef 2200 → 3 şerit; tek satır
        let dilimler = RafDilimleyici.dilimAlanlari(genislik: 5712, yukseklik: 4284, satirlar: [0.35...0.75])
        let alanlar = dilimler.map(\.alan)
        #expect(alanlar.count == 3)
        #expect(dilimler.map(\.sutun) == [0, 1, 2])
        #expect(dilimler.allSatisfy { $0.satir == 0 })
        // Şeritler tüm genişliği kaplar ve bindirir
        #expect(alanlar.first?.minX == 0)
        #expect(alanlar.last?.maxX == 5712)
        #expect(alanlar[0].maxX > alanlar[1].minX)
        // Satırın üstüne/altına pay eklenir ama fotoğraf dışına çıkmaz
        #expect(alanlar.allSatisfy { $0.minY >= 0 && $0.maxY <= 4284 })
        #expect(alanlar[0].minY < 0.35 * 4284)
    }

    @Test func dolapFotografiDilimButcesineSigar() {
        // 5 raf × gereken 2 şerit = 10 ≤ 10 → her raf 2 şeritle okunur (yazılar küçülmez)
        let besRaf: [ClosedRange<Double>] = [0.05...0.2, 0.25...0.4, 0.45...0.6, 0.65...0.8, 0.85...0.97]
        let dilimler = RafDilimleyici.dilimAlanlari(genislik: 4284, yukseklik: 5712, satirlar: besRaf)
        #expect(dilimler.count == 10)
        #expect(dilimler.allSatisfy { Int($0.alan.width) < 4284 })
        #expect(Set(dilimler.map(\.satir)) == Set(0..<5))
        // 6 raf → bütçe 10/6 = 1 şerit, hiçbir raf atlanmaz
        let altiRaf: [ClosedRange<Double>] = [0.02...0.16, 0.18...0.32, 0.34...0.48, 0.5...0.64, 0.66...0.8, 0.82...0.96]
        let alti = RafDilimleyici.dilimAlanlari(genislik: 4284, yukseklik: 5712, satirlar: altiRaf)
        #expect(alti.count == 6)
        #expect(alti.allSatisfy { Int($0.alan.width) == 4284 })
        // 12 raf → en ince komşular birleştirilip 10'a iner; toplam bütçe aşılmaz
        let onIkiRaf = (0..<12).map { Double($0) * 0.08...Double($0) * 0.08 + 0.06 }
        let onIki = RafDilimleyici.dilimAlanlari(genislik: 4284, yukseklik: 5712, satirlar: onIkiRaf)
        #expect(onIki.count == 10)
        #expect(RafDilimleyici.satirlariSinirla(onIkiRaf, enFazla: 3).count == 3)
    }

    @Test func rafEtiketindenNumaraCozulur() {
        #expect(ShelfScanEngine.shelfNumber(from: "6 TÜRK EDEBİYATI") == "6")
        #expect(ShelfScanEngine.shelfNumber(from: "Dünya Edebiyatı 12") == "12")
        #expect(ShelfScanEngine.shelfNumber(from: "TÜRK EDEBİYATI") == nil)
        #expect(ShelfScanEngine.shelfNumber(from: nil) == nil)
    }

    @Test func birdenCokEtiketOtomatikDoldurmaz() {
        var sonuc = ShelfScanResult()
        sonuc.shelfLabels = ["6 TÜRK EDEBİYATI"]
        #expect(sonuc.shelfLabel == "6 TÜRK EDEBİYATI")
        #expect(sonuc.shelfNumber == "6")
        sonuc.shelfLabels = ["6 TÜRK EDEBİYATI", "7 TÜRK EDEBİYATI"]
        #expect(sonuc.shelfLabel == nil)
        #expect(sonuc.shelfNumber == nil)
        sonuc.cabinetLabels = ["B"]
        #expect(sonuc.cabinetLabel == "B")
        // Tek etiket ama fotoğrafta 5 raf: etiket yalnız bir rafa ait, otomatik doldurma yok
        sonuc.shelfLabels = ["6 TÜRK EDEBİYATI"]
        sonuc.satirSayisi = 5
        #expect(!sonuc.rafOtomatikDolabilir)
        sonuc.satirSayisi = 1
        #expect(sonuc.rafOtomatikDolabilir)
    }

    @Test func ayniKitapKontrolu() {
        let a = GeminiBookFields(title: "Sefiller 1. Cilt", author: "Victor Hugo")
        let b = GeminiBookFields(title: "Sefiller 2. Cilt", author: "Victor Hugo")
        #expect(!ShelfScanEngine.isSameBook(a, b))
        var c1 = GeminiBookFields(title: "Sefiller", author: "Victor Hugo")
        c1.volume = "1"
        var c2 = GeminiBookFields(title: "Sefiller", author: "Victor Hugo")
        c2.volume = "2"
        #expect(!ShelfScanEngine.isSameBook(c1, c2))
        let d = GeminiBookFields(title: "Sefiller", author: "Victor Hugo")
        #expect(ShelfScanEngine.isSameBook(c1, d))
        #expect(!ShelfScanEngine.isSameBook(GeminiBookFields(title: "Şiirler", author: "Ahmet Haşim"),
                                            GeminiBookFields(title: "Şiirler", author: "Yahya Kemal")))
    }

    @Test func komsuDilimlerdeNushaToplanmaz() {
        var sinekli = GeminiBookFields(title: "Sinekli Bakkal", author: "Halide Edib Adıvar")
        sinekli.copies = 3
        var sinekliTekrar = GeminiBookFields(title: "Sinekli Bakkal", author: "Halide Edib Adıvar")
        sinekliTekrar.confidence = 0.95
        let cezmi = GeminiBookFields(title: "Cezmi", author: "Namık Kemal")
        var cezmiKomsu = GeminiBookFields(title: "Cezmi", author: "Namık Kemal")
        cezmiKomsu.copies = 2
        let siirler1 = GeminiBookFields(title: "Şiirler", author: "Ahmet Haşim")
        let siirler2 = GeminiBookFields(title: "Şiirler", author: "Yahya Kemal")

        let sonuc = ShelfScanEngine.merged(tiles: [
            [sinekli, sinekliTekrar, cezmi, siirler1],
            [cezmiKomsu, siirler2]
        ])
        #expect(sonuc.count == 4)
        // Aynı dilimde tekrar → nüshalar toplanır (3 + 1), daha emin kayıt tutulur
        let s = sonuc.first { $0.title == "Sinekli Bakkal" }
        #expect(s?.copies == 4)
        #expect(s?.confidence == 0.95)
        // Komşu dilimde 2 görüldü, önceki dilimde 1: yalnız aşan kısım eklenir → 2
        #expect(sonuc.first { $0.title == "Cezmi" }?.copies == 2)
        #expect(sonuc.filter { $0.title == "Şiirler" }.count == 2)
    }

    @Test func komsuDilimAsanKismiEkler() {
        // Raf 0: A×1. Raf 2 şerit 0: A×1 (uzak raf, ayrı nüsha → 2). Raf 2 şerit 1: A×2
        // (biri bindirmedeki aynı sırt, biri yeni) → yalnız aşan 1 eklenir → 3
        let a1 = GeminiBookFields(title: "Araba Sevdası", author: "Recaizade Mahmut Ekrem")
        var a2 = GeminiBookFields(title: "Araba Sevdası", author: "Recaizade Mahmut Ekrem")
        a2.copies = 2
        let tiles = [
            ShelfScanEngine.DilimSonucu(books: [a1], foto: 0, satir: 0, sutun: 0),
            ShelfScanEngine.DilimSonucu(books: [a1], foto: 0, satir: 2, sutun: 0),
            ShelfScanEngine.DilimSonucu(books: [a2], foto: 0, satir: 2, sutun: 1)
        ]
        #expect(ShelfScanEngine.merged(tiles: tiles).first?.copies == 3)
    }

    @Test func uzakDilimlerdeNushaToplanir() {
        var vatan = GeminiBookFields(title: "Vatan Yahut Silistre", author: "Namık Kemal")
        vatan.copies = 4
        var vatanAltRaf = GeminiBookFields(title: "Vatan Yahut Silistre", author: "Namık Kemal")
        vatanAltRaf.copies = 2
        let ustRaf = ShelfScanEngine.DilimSonucu(books: [vatan], foto: 0, satir: 0, sutun: 0)
        let ikiAltRaf = ShelfScanEngine.DilimSonucu(books: [vatanAltRaf], foto: 0, satir: 2, sutun: 0)
        let baskaFoto = ShelfScanEngine.DilimSonucu(books: [vatanAltRaf], foto: 1, satir: 0, sutun: 0)
        // İki raf aşağısı ve başka fotoğraf gerçekten ayrı nüshalardır: 4 + 2 + 2
        #expect(ShelfScanEngine.merged(tiles: [ustRaf, ikiAltRaf, baskaFoto]).first?.copies == 8)
        // Aynı rafta komşu olmayan (2 şerit uzak) dilimler de ayrı nüsha sayılır
        let uzakSerit = ShelfScanEngine.DilimSonucu(books: [vatanAltRaf], foto: 0, satir: 0, sutun: 2)
        #expect(ShelfScanEngine.merged(tiles: [ustRaf, uzakSerit]).first?.copies == 6)
        // Hemen alt raf, kesitler piksel paylaşıyor: 2 ≤ 4 → aşan kısım yok → 4
        let hemenAlt = ShelfScanEngine.DilimSonucu(books: [vatanAltRaf], foto: 0, satir: 1, sutun: 0, ustBindirmeli: true)
        #expect(ShelfScanEngine.merged(tiles: [ustRaf, hemenAlt]).first?.copies == 4)
        // Hemen alt raf ama kesitler ayrık (raf tahtası arada): ayrı nüshalar → 6
        let ayrikAlt = ShelfScanEngine.DilimSonucu(books: [vatanAltRaf], foto: 0, satir: 1, sutun: 0, ustBindirmeli: false)
        #expect(ShelfScanEngine.merged(tiles: [ustRaf, ayrikAlt]).first?.copies == 6)
        // Çapraz dilim (alt raf, yan şerit) komşu değildir → 6
        let capraz = ShelfScanEngine.DilimSonucu(books: [vatanAltRaf], foto: 0, satir: 1, sutun: 1, ustBindirmeli: true)
        #expect(ShelfScanEngine.merged(tiles: [ustRaf, capraz]).first?.copies == 6)
        // Nüsha toplamı 99'u aşmaz
        var cok = GeminiBookFields(title: "Vatan Yahut Silistre", author: "Namık Kemal")
        cok.copies = Int.max
        #expect(ShelfScanEngine.merged(tiles: [[cok, cok]]).first?.copies == 99)
    }

    @Test func nushaSayisiKaydaAdetOlurVeToplamHesaplanir() {
        var alanlar = GeminiBookFields(title: "Vatan Yahut Silistre", author: "Namık Kemal")
        alanlar.copies = 6
        let kaydi = SesliKitapKaydi(fields: alanlar, cabinet: "B", shelf: "6")
        #expect(kaydi.quantity == 6)
        #expect(kaydi.shelf == "6")
        var sonuc = ShelfScanResult()
        sonuc.books = [alanlar, GeminiBookFields(title: "Cezmi")]
        sonuc.shelfLabels = ["6 TÜRK EDEBİYATI"]
        #expect(sonuc.totalCopies == 7)
        #expect(sonuc.shelfNumber == "6")
    }

    @Test func kitapAlanlariEsnekCozulur() throws {
        // Gemini sayfa sayısını sayı, nüshayı metin, ISBN'i sayı döndürse de kayıt düşmez
        let json = """
        {"books": [{"title": "Cezmi", "author": "Namık Kemal", "pageCount": 320, "copies": "2",
                    "confidence": "0,7", "isbn": 9786053607021, "publicationYear": 2019, "volume": null}],
         "shelfLabel": "6 TÜRK EDEBİYATI"}
        """
        let yanit = try JSONDecoder().decode(ShelfScanReply.self, from: Data(json.utf8))
        let kitap = try #require(yanit.books.first)
        #expect(kitap.pageCount == "320")
        #expect(kitap.copies == 2)
        #expect(kitap.confidence == 0.7)
        #expect(kitap.isbn == "9786053607021")
        #expect(kitap.publicationYear == "2019")
        #expect(kitap.volume == nil)
        #expect(yanit.shelfLabel == "6 TÜRK EDEBİYATI")
        // Yeniden kodlamada değerler düz yazılır, nil alanlar atlanır
        let encoded = String(decoding: try JSONEncoder().encode(kitap), as: UTF8.self)
        #expect(encoded.contains("\"pageCount\":\"320\""))
        #expect(!encoded.contains("volume"))
    }
}
