import Testing
import Foundation
import UIKit
@testable import _01

@MainActor
struct TaramaYardimciTestleri {
    @Test func isbnYerDegistirmeVeKarisanRakamOnerilir() {
        // Doğrusu 9789750718434; 4 ve 3 yer değiştirmiş
        let oneriler = ISBNOnarici.oneriler("9789750718443")
        #expect(oneriler.contains("9789750718434"))
        #expect(oneriler.count <= 4)
        #expect(oneriler.allSatisfy { ISBNFormatter.isValidISBN13($0) })
        // Harf karışmış (o → 0 değil, atılır): 12 rakam kalır, kontrol basamağı tamamlanır
        #expect(ISBNOnarici.oneriler("978975071o84").allSatisfy { ISBNFormatter.isValidISBN13($0) })
    }

    @Test func eksikKontrolBasamagiTamamlanir() {
        #expect(ISBNOnarici.oneriler("978975071843") == ["9789750718434"])
        #expect(ISBNOnarici.oneriler("12345").isEmpty)
        // Zaten geçerli ISBN kendisini öneri olarak döndürmez
        #expect(!ISBNOnarici.oneriler("9789750718434").contains("9789750718434"))
    }

    @Test func karisanRakamOnarilir() {
        // 7. hane 5 yerine 6 okunmuş: 978976...
        let bozuk = "9789760718434"
        #expect(!ISBNFormatter.isValidISBN13(bozuk))
        #expect(ISBNOnarici.oneriler(bozuk, enFazla: 20).contains("9789750718434"))
    }

    @Test func fotoGruplariGuvenliHaleGelir() {
        #expect(GeminiFotoGruplayici.duzelt([[0, 1], [1, 2], [7]], adet: 4) == [[0, 1], [2], [3]])
        #expect(GeminiFotoGruplayici.duzelt([], adet: 2) == [[0], [1]])
    }

    @Test func seriSayacAraliklari() {
        #expect(!SeriTaramaSesi.duyurulmali(0))
        #expect(!SeriTaramaSesi.duyurulmali(9))
        #expect(SeriTaramaSesi.duyurulmali(10))
        #expect(SeriTaramaSesi.duyurulmali(30))
    }

    @Test func taslakDiskeYazilipOkunur() {
        let dosya = FileManager.default.temporaryDirectory.appendingPathComponent("taslak-\(UUID()).json")
        TaslakDeposu.dosyaOverride = dosya
        defer {
            TaslakDeposu.dosyaOverride = nil
            try? FileManager.default.removeItem(at: dosya)
        }
        TaslakDeposu.kaydet([Book(title: "Yarım", author: "Kayıt", coverData: Data([7]), series: "S", volume: 2)])
        let geri = TaslakDeposu.yukle()
        #expect(geri.first?.title == "Yarım")
        #expect(geri.first?.coverData == Data([7]))
        #expect(geri.first?.volume == 2)
        TaslakDeposu.temizle()
        #expect(TaslakDeposu.sayi == 0)
    }

    @Test func rafTaramasiTekrarlariAyiklar() {
        var a = GeminiBookFields(title: "Küçük Prens")
        a.confidence = 0.5
        var b = GeminiBookFields(title: "Kucuk Prens")
        b.confidence = 0.9
        let c = GeminiBookFields(title: "Simyacı")
        let sonuc = ShelfScanEngine.deduplicated([a, c, b])
        #expect(sonuc.count == 2)
        #expect(sonuc.first?.confidence == 0.9)
    }

    @Test func arkaKapakAlanlariNormalizeVeBirlesir() {
        var alanlar = GeminiBookFields(title: "Harry Potter ve Sırlar Odası", isBook: true)
        alanlar.series = " Harry Potter "
        alanlar.volume = "2. kitap"
        alanlar.tags = ["Büyü", " dostluk ", "", "okul", "macera", "fazla"]
        alanlar.readingLevel = "Ortaokul"
        alanlar.contentWarning = "  "
        let temiz = GeminiBookRecognizer.normalized(alanlar)
        #expect(temiz.series == "Harry Potter")
        #expect(temiz.volume == "2")
        #expect(temiz.tags == ["büyü", "dostluk", "okul", "macera"])
        #expect(temiz.contentWarning == nil)

        var gecersiz = alanlar
        gecersiz.readingLevel = "Üniversite"
        #expect(GeminiBookRecognizer.normalized(gecersiz).readingLevel == nil)

        var taslak = BookDraft()
        taslak.tags = "elle girilen"
        GeminiBookRecognizer.merge(temiz, into: &taslak)
        #expect(taslak.series == "Harry Potter")
        #expect(taslak.volume == 2)
        #expect(taslak.readingLevel == "Ortaokul")
        #expect(taslak.tags == "elle girilen")   // kullanıcının girdiği korunur
    }

    @Test func egikKapakDuzeltilir() async throws {
        // Siyah zemin üzerinde beyaz, hafif eğik bir dörtgen (kapak)
        let resim = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800)).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
            let yol = UIBezierPath()
            yol.move(to: CGPoint(x: 120, y: 90))
            yol.addLine(to: CGPoint(x: 500, y: 130))
            yol.addLine(to: CGPoint(x: 470, y: 700))
            yol.addLine(to: CGPoint(x: 90, y: 660))
            yol.close()
            UIColor.white.setFill()
            yol.fill()
        }
        let png = try #require(resim.pngData())
        let duz = try #require(await KapakDuzeltici.duzelt(png))
        let cikti = try #require(UIImage(data: duz))
        // Düzeltilmiş görüntü dikey (kapak oranında) ve zeminden kırpılmış olmalı
        #expect(cikti.size.height > cikti.size.width)
        #expect(cikti.size.width < resim.size.width * resim.scale)   // piksel cinsinden kırpılmış

        // Dörtgen olmayan (düz renk) görüntüde nil
        let bos = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        let bosPNG = try #require(bos.pngData())
        #expect(await KapakDuzeltici.duzelt(bosPNG) == nil)
    }
}
