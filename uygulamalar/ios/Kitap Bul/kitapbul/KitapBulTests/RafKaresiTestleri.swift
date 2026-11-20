import Testing
import Foundation
import CoreGraphics
@testable import _01

@MainActor
struct RafKaresiTestleri {
    @Test func barkodISBNBaskinVeTekil() {
        let gemini = [
            AlgilananKitap(isbn: "978-605-360-702-1", title: "Sokrates'in Savunması", author: "Platon", side: "back"),
            AlgilananKitap(isbn: "9786053607021", title: "Sokratesin Savunmasi", author: "Platon", side: "back"),
            AlgilananKitap(isbn: "9786053607038", title: "İnsan Neyle Yaşar?", author: "Tolstoy", side: "back")
        ]
        // 9789755705859 yalnız barkoddan okundu; 9786053607021 her iki kaynakta da var
        let sonuc = CokluKitapAlgilayici.birlestir(barkodlar: ["9789755705859", "9786053607021"], gemini: gemini)
        #expect(sonuc.map(\.isbn) == ["9786053607021", "9786053607038", "9789755705859"])
        // Gemini kaydındaki tire/boşluk temizlenir, ad korunur; aynı karedeki ikinci kayıt nüsha olur
        #expect(sonuc[0].title == "Sokrates'in Savunması")
        #expect(sonuc[0].nusha == 2)
        // Barkodla doğrulanan kayıt işaretlenir; konumsuz barkod fazladan nüsha eklemez
        #expect(sonuc[0].barkodlu)
        #expect(!sonuc[1].barkodlu)
        #expect(sonuc[2].side == "back")
        #expect(sonuc[2].nusha == 1)
        #expect(sonuc[2].barkodlu)
    }

    @Test func gecersizISBNliKayitAdiylaKalir() {
        let gemini = [
            AlgilananKitap(isbn: "9786053607000", title: "Fareler ve İnsanlar", author: "John Steinbeck", side: "front")
        ]
        let sonuc = CokluKitapAlgilayici.birlestir(barkodlar: [], gemini: gemini)
        #expect(sonuc.count == 1)
        #expect(sonuc[0].isbn == nil)
        #expect(sonuc[0].title == "Fareler ve İnsanlar")
    }

    @Test func kitapOlmayanBarkodAtilir() {
        // Geçerli EAN-13 ama 978/979 ile başlamıyor (ürün barkodu): kitap sayılmaz
        #expect(CokluKitapAlgilayici.kitapISBN("8690000000005") == nil)
        #expect(CokluKitapAlgilayici.kitapISBN("978-605-360-702-1") == "9786053607021")
        let sonuc = CokluKitapAlgilayici.birlestir(barkodlar: ["8690000000005"], gemini: [])
        #expect(sonuc.isEmpty)
    }

    @Test func benzerAdliISBNsizKayitNushaOlur() {
        let gemini = [
            AlgilananKitap(isbn: "9786053607021", title: "Sokrates'in Savunması", author: "Platon"),
            AlgilananKitap(isbn: nil, title: "Sokratesin Savunması", author: "Platon"),
            AlgilananKitap(isbn: nil, title: "Suç ve Ceza", author: "Dostoyevski"),
            AlgilananKitap(isbn: nil, title: "   ", author: "Adsız")
        ]
        let sonuc = CokluKitapAlgilayici.birlestir(barkodlar: [], gemini: gemini)
        #expect(sonuc.count == 2)
        #expect(sonuc[0].nusha == 2)
        #expect(sonuc[1].title == "Suç ve Ceza")
    }

    @Test func ciltNumarasiFarkliKitaplarBirlesmez() {
        let gemini = [
            AlgilananKitap(isbn: nil, title: "Sefiller 1. Cilt", author: "Victor Hugo"),
            AlgilananKitap(isbn: nil, title: "Sefiller 2. Cilt", author: "Victor Hugo")
        ]
        #expect(CokluKitapAlgilayici.birlestir(barkodlar: [], gemini: gemini).count == 2)
        #expect(!CatalogMatcher.isSimilarTitle("Sefiller 1. Cilt", "Sefiller 2. Cilt"))
        #expect(!CatalogMatcher.isSimilarTitle("Sefiller I", "Sefiller II"))
        #expect(CatalogMatcher.isSimilarTitle("Sokrates'in Savunması", "Sokratesin Savunmasi"))
        #expect(CatalogMatcher.isSimilarTitle("Sefiller 2. Cilt", "Sefiller 2 Cilt"))
    }

    @Test func karelerTekillestirilirNushaToplanmaz() {
        // Aynı kitap iki karede de çekilmiş: nüsha 1 kalır
        let birinciKare = [AlgilananKitap(isbn: "9786053607021"), AlgilananKitap(isbn: nil, title: "Suç ve Ceza", author: "Dostoyevski")]
        let ikinciKare = [AlgilananKitap(isbn: "9786053607021"), AlgilananKitap(isbn: nil, title: "Suç ve Ceza", author: "Dostoyevski")]
        let sonuc = CokluKitapAlgilayici.tekillestir(birinciKare + ikinciKare)
        #expect(sonuc.count == 2)
        #expect(sonuc.allSatisfy { $0.nusha == 1 })
    }

    @Test func barkodKutusunaGoreKaydaBaglanir() {
        // Sol alttaki kitabın ISBN'i Gemini tarafından yanlış (geçersiz) okunmuş; barkod doğrusunu verir
        let gemini = [
            AlgilananKitap(isbn: "9789755705850", title: "Fareler ve İnsanlar", author: "John Steinbeck", side: "back", box: [500, 0, 1000, 300]),
            AlgilananKitap(isbn: nil, title: "Sefiller", author: "Victor Hugo", side: "back", box: [0, 600, 500, 1000])
        ]
        let barkodlar = [
            BarkodBulgusu(isbn: "9789755705859", merkez: CGPoint(x: 0.15, y: 0.75)),
            BarkodBulgusu(isbn: "9786053607021", merkez: CGPoint(x: 0.8, y: 0.25))
        ]
        let sonuc = CokluKitapAlgilayici.birlestir(barkodlar: barkodlar, gemini: gemini)
        #expect(sonuc.count == 2)
        #expect(sonuc.first { $0.title == "Fareler ve İnsanlar" }?.isbn == "9789755705859")
        #expect(sonuc.first { $0.title == "Sefiller" }?.isbn == "9786053607021")
        #expect(sonuc.allSatisfy { $0.barkodlu })
    }

    @Test func kutuDisiBarkodAyriKayitOlur() {
        let gemini = [AlgilananKitap(isbn: nil, title: "Sefiller", author: "Victor Hugo", side: "front", box: [0, 0, 300, 300])]
        // Kutudan ve kenar payından çok uzak bir barkod: bağlanmaz, ISBN'li kayıt olur
        let barkodlar = [BarkodBulgusu(isbn: "9786053607038", merkez: CGPoint(x: 0.9, y: 0.9))]
        let sonuc = CokluKitapAlgilayici.birlestir(barkodlar: barkodlar, gemini: gemini)
        #expect(sonuc.count == 2)
        let barkodKaydi = sonuc.first { $0.isbn == "9786053607038" }
        #expect(barkodKaydi?.temizAd.isEmpty == true)
        // Sanal kutu barkodun çevresindedir (aynı karede ayrı kitap olduğu anlaşılsın)
        #expect(barkodKaydi?.kutu?.contains(CGPoint(x: 0.9, y: 0.9)) == true)
        #expect(sonuc.contains { $0.title == "Sefiller" && $0.isbn == nil })
        // Kutu kenarına yakın (%6 içinde) barkod ön yüz kaydına BAĞLANMAZ (ön yüzde barkod görünmez)…
        let yakin = [BarkodBulgusu(isbn: "9786053607038", merkez: CGPoint(x: 0.35, y: 0.15))]
        let onYuz = CokluKitapAlgilayici.birlestir(barkodlar: yakin, gemini: gemini)
        #expect(onYuz.count == 2)
        #expect(onYuz.first { $0.title == "Sefiller" }?.isbn == nil)
        // …arka yüz kaydına bağlanır
        var arka = gemini
        arka[0].side = "back"
        #expect(CokluKitapAlgilayici.birlestir(barkodlar: yakin, gemini: arka).first?.isbn == "9786053607038")
    }

    @Test func komsudanKopyalananMetinISBNGuvenilmez() {
        // A'nın barkodu okundu ve A'ya bağlandı; B'nin metninde de aynı numara var (kopyalanmış):
        // B ayrı bir kitaptır, A'ya nüsha olarak eklenmez, adıyla ISBN'siz kalır
        let gemini = [
            AlgilananKitap(isbn: "9786053607021", title: "Sokrates'in Savunması", author: "Platon", side: "back", box: [0, 0, 500, 500]),
            AlgilananKitap(isbn: "9786053607021", title: "Devlet", author: "Platon", side: "back", box: [0, 500, 500, 1000])
        ]
        let barkodlar = [BarkodBulgusu(isbn: "9786053607021", merkez: CGPoint(x: 0.25, y: 0.25))]
        let sonuc = CokluKitapAlgilayici.birlestir(barkodlar: barkodlar, gemini: gemini)
        #expect(sonuc.count == 2)
        let sokrates = sonuc.first { $0.title == "Sokrates'in Savunması" }
        #expect(sokrates?.nusha == 1)
        #expect(sokrates?.barkodlu == true)
        let devlet = sonuc.first { $0.title == "Devlet" }
        #expect(devlet?.isbn == nil)
        #expect(devlet?.barkodlu == false)
        // Barkod hiç okunmadıysa (konumsuz/yok) iki metin ISBN'i eskisi gibi nüsha sayılır
        #expect(CokluKitapAlgilayici.birlestir(barkodlar: [], gemini: gemini).first?.nusha == 2)
    }

    @Test func modelBarkodDogrulamasiniTaklitEdemez() throws {
        let json = """
        {"books": [{"title": "X", "isbn": "9786053607021", "barkodlu": true, "photoIndex": 3}]}
        """
        let yanit = try JSONDecoder().decode(CokluKitapAlgilayici.Yanit.self, from: Data(json.utf8))
        #expect(yanit.books[0].barkodlu == false)
        #expect(yanit.books[0].photoIndex == nil)
        // Saçma büyük nüsha 99'a kırpılır
        var kayit = AlgilananKitap(title: "Y", copies: Int.max)
        #expect(kayit.nusha == 99)
        kayit.copies = -4
        #expect(kayit.nusha == 1)
    }

    @Test func kutusuKaymisKitabinBarkoduHayaletNushaUretmez() {
        // Gemini ISBN'i metinden doğru okumuş ama kutuyu dar çizmiş; barkod kutunun epey dışında kalmış
        let gemini = [AlgilananKitap(isbn: "9786053607021", title: "Sokrates'in Savunması", author: "Platon", side: "back", box: [0, 0, 400, 250])]
        let barkodlar = [BarkodBulgusu(isbn: "9786053607021", merkez: CGPoint(x: 0.45, y: 0.55))]
        let sonuc = CokluKitapAlgilayici.birlestir(barkodlar: barkodlar, gemini: gemini)
        #expect(sonuc.count == 1)
        #expect(sonuc[0].nusha == 1)
        #expect(sonuc[0].barkodlu)
    }

    @Test func barkodOnYuzYerineYakinArkaYuzeBaglanir() {
        // Arka yüz A'nın kutusu barkodunu az farkla kaçırmış; komşu ön yüz C'nin kutusu barkodu içeriyor.
        // Ön yüzde barkod görünmez: barkod A'ya bağlanmalı, C kendi kimliğini korumalı.
        let gemini = [
            AlgilananKitap(isbn: nil, title: nil, side: "back", box: [0, 0, 500, 500]),
            AlgilananKitap(isbn: nil, title: "Sefiller", author: "Victor Hugo", side: "front", box: [0, 500, 500, 1000])
        ]
        let barkodlar = [BarkodBulgusu(isbn: "9786053607021", merkez: CGPoint(x: 0.53, y: 0.25))]
        let sonuc = CokluKitapAlgilayici.birlestir(barkodlar: barkodlar, gemini: gemini)
        #expect(sonuc.count == 2)
        #expect(sonuc.first { $0.isbn == "9786053607021" }?.side == "back")
        #expect(sonuc.first { $0.title == "Sefiller" }?.isbn == nil)
        // Aynı noktayı iki arka yüz kutusu içeriyorsa merkeze yakın olan kazanır
        let ikiArka = [
            AlgilananKitap(isbn: nil, title: "Büyük", side: "back", box: [0, 0, 1000, 1000]),
            AlgilananKitap(isbn: nil, title: "Küçük", side: "back", box: [400, 400, 600, 600])
        ]
        let ortadaki = CokluKitapAlgilayici.birlestir(barkodlar: [BarkodBulgusu(isbn: "9786053607021", merkez: CGPoint(x: 0.5, y: 0.5))], gemini: ikiArka)
        #expect(ortadaki.first { $0.isbn == "9786053607021" }?.title == "Küçük")
    }

    @Test func ikiKonumdakiAyniISBNIkiNushaSayilir() {
        // Masada aynı kitaptan iki nüsha, ikisinin de barkodu okunmuş, Gemini ikisini de kutulamış
        let gemini = [
            AlgilananKitap(isbn: nil, title: "Sokrates'in Savunması", author: "Platon", side: "back", box: [0, 0, 500, 500]),
            AlgilananKitap(isbn: nil, title: "Sokrates'in Savunması", author: "Platon", side: "back", box: [500, 500, 1000, 1000])
        ]
        let barkodlar = [
            BarkodBulgusu(isbn: "9786053607021", merkez: CGPoint(x: 0.25, y: 0.25)),
            BarkodBulgusu(isbn: "9786053607021", merkez: CGPoint(x: 0.75, y: 0.75))
        ]
        let sonuc = CokluKitapAlgilayici.birlestir(barkodlar: barkodlar, gemini: gemini)
        #expect(sonuc.count == 1)
        #expect(sonuc[0].nusha == 2)
        // Gemini yalnız birini kutulamışsa ikinci barkod yine ayrı nüsha sayılır (barkod sayısı = 2)
        let tekKayit = CokluKitapAlgilayici.birlestir(barkodlar: barkodlar, gemini: [gemini[0]])
        #expect(tekKayit.count == 1)
        #expect(tekKayit[0].nusha == 2)
    }

    @Test func ciftAlgilananBarkodTekKalir() {
        let bulgular = [
            BarkodBulgusu(isbn: "9786053607021", merkez: CGPoint(x: 0.30, y: 0.30)),
            BarkodBulgusu(isbn: "9786053607021", merkez: CGPoint(x: 0.31, y: 0.30)),
            BarkodBulgusu(isbn: "9786053607021", merkez: CGPoint(x: 0.70, y: 0.30))
        ]
        #expect(CokluKitapAlgilayici.tekil(bulgular).count == 2)
    }

    @Test func visionMerkeziOrijinalKareyeCevrilir() {
        // Vision sol alt kökenli: üst sol köşedeki kutu (y yüksek) → sol üst kökende (0.1, 0.1)
        let ustSol = CGRect(x: 0, y: 0.8, width: 0.2, height: 0.2)
        let duz = CokluKitapAlgilayici.merkezOrijinale(ustSol, dondurulmus: false)
        #expect(abs(duz.x - 0.1) < 1e-9 && abs(duz.y - 0.1) < 1e-9)
        // 90° döndürülmüş analizde sağ üst köşe, orijinalin sol üst köşesidir
        let sagUst = CGRect(x: 0.9, y: 0.9, width: 0.1, height: 0.1)
        let merkez = CokluKitapAlgilayici.merkezOrijinale(sagUst, dondurulmus: true)
        #expect(abs(merkez.x - 0.05) < 1e-9 && abs(merkez.y - 0.05) < 1e-9)
        // Kenara uzaklık: içerde 0, dışarıda en yakın kenara dik uzaklık
        let kutu = CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2)
        #expect(CokluKitapAlgilayici.kenaraUzaklik(CGPoint(x: 0.3, y: 0.3), kutu) == 0)
        #expect(abs(CokluKitapAlgilayici.kenaraUzaklik(CGPoint(x: 0.45, y: 0.3), kutu) - 0.05) < 1e-9)
    }

    @Test func esnekJSONCozulur() throws {
        // Gemini ISBN'i sayı, güveni metin, kutuyu metin dizisi döndürse de kare kaybolmaz
        let json = """
        {"books": [
          {"isbn": 9786053607021, "title": "Sokrates'in Savunması", "confidence": "0,8", "box_2d": ["10", "20", "500", "600"], "side": "back"},
          {"isbn": null, "title": "Sefiller", "confidence": 0.95, "box_2d": [0, 600, 500, 1000], "copies": "2"},
          {"title": "Bozuk", "copies": "1e400", "confidence": "nan", "box_2d": ["0", "0", "abc", "1"]}
        ]}
        """
        let yanit = try JSONDecoder().decode(CokluKitapAlgilayici.Yanit.self, from: Data(json.utf8))
        #expect(yanit.books.count == 3)
        #expect(yanit.books[0].isbn == "9786053607021")
        #expect(yanit.books[0].confidence == 0.8)
        #expect(yanit.books[0].kutu == CGRect(x: 0.02, y: 0.01, width: 0.58, height: 0.49))
        #expect(yanit.books[1].isbn == nil)
        #expect(yanit.books[1].copies == 2)
        #expect(yanit.books[1].onYuz == false)
        // Sonsuz/NaN değerler çökmez, nil olur
        #expect(yanit.books[2].copies == nil)
        #expect(yanit.books[2].confidence == nil)
        #expect(yanit.books[2].kutu == nil)
    }
}
