import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import KagitKit

/// Modül C testlerinin ortak yardımcıları.
enum ModulC {
    /// Büyük puntolu metin sayfalarını görüntüye çevirip (taranmış gibi) döndürür.
    static func taramaGoruntusu(_ satirlar: [String], punto: CGFloat = 30, dpi: CGFloat = 200) -> CGImage {
        let y = PDFCizim.Yazici()
        let boyut = PDFCizim.Boyut.a4.boyut
        y.sayfa(CGRect(origin: .zero, size: boyut)) { ctx in
            for (i, s) in satirlar.enumerated() {
                PDFCizim.metin(s, ctx, nokta: CGPoint(x: 60, y: boyut.height - 120 - CGFloat(i) * 60), punto: punto)
            }
        }
        let belge = PDFDocument(data: y.bitir())!
        return PDFCizim.goruntu(belge.page(at: 0)!, dpi: dpi)!
    }

    /// Sıkıştırılmamış içerik akışlı, elle yazılmış PDF (ham bayt aramasına uygun).
    static func hamPDF(_ icerik: String, xmp: String? = nil, yazar: String? = nil) -> Data {
        var s = "%PDF-1.4\n"
        s += "1 0 obj << /Type /Catalog /Pages 2 0 R" + (xmp != nil ? " /Metadata 6 0 R" : "") + " >> endobj\n"
        s += "2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n"
        s += "3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >> endobj\n"
        s += "4 0 obj << /Length \(icerik.utf8.count) >>\nstream\n\(icerik)\nendstream\nendobj\n"
        s += "5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n"
        if let xmp {
            s += "6 0 obj << /Type /Metadata /Subtype /XML /Length \(xmp.utf8.count) >>\nstream\n\(xmp)\nendstream\nendobj\n"
        }
        s += "7 0 obj << /Author (\(yazar ?? "")) /Title (Gizli Baslik) >> endobj\n"
        s += "trailer << /Root 1 0 R /Info 7 0 R /Size 8 >>\n%%EOF\n"
        return Data(s.utf8)
    }

    static func bayttaVar(_ veri: Data, _ aranan: String) -> Bool {
        veri.range(of: Data(aranan.utf8)) != nil
    }
}

@Suite struct ModulCOCRTestleri {
    @Test func gorselPDFAranabilirOlur() async throws {
        let g = ModulC.taramaGoruntusu(["Çalışkan öğrenciler gönderi", "Biyoloji sınavı"])
        let veri = try await AranabilirPDF.gorsellerdenPDF([g], baslik: "Deneme")
        let belge = try #require(PDFDocument(data: veri))
        #expect(belge.pageCount == 1)
        let metin = belge.string ?? ""
        #expect(TurkceMetin.anahtar(metin).contains("ogrenciler"), "OCR metni: \(metin)")
        #expect(TurkceMetin.anahtar(metin).contains("biyoloji"))
        // Görünmez katman aranabilir olmalı
        #expect(!belge.findString("Biyoloji", withOptions: .caseInsensitive).isEmpty)
        #expect(!belge.findString("gönderi", withOptions: .caseInsensitive).isEmpty)
    }

    @Test func ocrKapaliysaMetinYok() async throws {
        let g = ModulC.taramaGoruntusu(["Merhaba dünya"])
        var s = AranabilirSecenekleri()
        s.ocr = false
        let veri = try await AranabilirPDF.gorsellerdenPDF([g], secenekler: s)
        #expect(PDFDocument(data: veri)?.page(at: 0).map(AranabilirPDF.metniVarMi) == false)
    }

    @Test func gorselBoyutuVeJPEGMakul() async throws {
        let g = ModulC.taramaGoruntusu(["Boyut denemesi"])
        let veri = try await AranabilirPDF.gorsellerdenPDF([g])
        // 1654x2339 piksel; Flate yerine JPEG gömülmeli.
        #expect(veri.count < 400_000, "boyut: \(veri.count)")
    }

    @Test func karmaPDFdeSadeceMetinsizSayfalaraKatmanEklenir() async throws {
        // Sayfa 1: gerçek metin. Sayfa 2: yalnız görüntü.
        let metinli = Ornek.pdf([["Birinci sayfa vektör metni"]])
        let tarama = try await AranabilirPDF.gorsellerdenPDF([ModulC.taramaGoruntusu(["Kırmızı elma ağacı"])],
                                                             secenekler: { var s = AranabilirSecenekleri(); s.ocr = false; return s }())
        let birlesik = PDFDocument(data: metinli)!
        birlesik.insert(PDFDocument(data: tarama)!.page(at: 0)!, at: 1)
        let girdi = try #require(birlesik.dataRepresentation())

        let (cikti, rapor) = try await AranabilirPDF.yap(veri: girdi)
        #expect(rapor.toplamSayfa == 2)
        #expect(rapor.islenen == 1)
        #expect(rapor.atlanan == 1)
        let belge = try #require(PDFDocument(data: cikti))
        #expect(belge.pageCount == 2)
        #expect(belge.page(at: 0)?.string?.contains("Birinci sayfa") == true)
        let ikinci = belge.page(at: 1)?.string ?? ""
        #expect(TurkceMetin.anahtar(ikinci).contains("kirmizi elma"), "OCR: \(ikinci)")
        #expect(!belge.findString("ağacı", withOptions: .caseInsensitive).isEmpty)
    }

    @Test func zatenAranabilirseDegismez() async throws {
        let girdi = Ornek.pdf([["Zaten metinli belge"]])
        let (cikti, rapor) = try await AranabilirPDF.yap(veri: girdi)
        #expect(rapor.islenen == 0)
        #expect(cikti == girdi)
    }

    @Test func belgeYapisiMetniCikarir() async throws {
        let g = ModulC.taramaGoruntusu(["Öğretmen çantası notları"])
        let yapi = try await BelgeYapisi.cikar(g)
        #expect(TurkceMetin.anahtar(yapi.metin).contains("ogretmen"), "metin: \(yapi.metin)")
    }

    @Test func ayrintiliOCRSozcukKutulariVerir() async throws {
        let g = ModulC.taramaGoruntusu(["Merhaba dünya"])
        let satirlar = try await MetinTanima.taniAyrintili(g)
        let s = try #require(satirlar.first)
        #expect(s.kelimeler.count == 2)
        let k = try #require(s.kutu(aralik: s.kelimeler[1].aralik))
        #expect(k.minX > s.kelimeler[0].kutu.minX)
    }
}

@Suite struct TaramaIslemleriTestleri {
    /// Sol yarısı gölgeli (koyu gri zemin), üstünde siyah çizgi olan sahte sayfa.
    static func golgeliSayfa() -> CGImage {
        let g = 400, y = 400
        let ctx = CGContext(data: nil, width: g, height: y, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.95, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: g, height: y))
        ctx.setFillColor(CGColor(gray: 0.55, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: g / 2, height: y))
        ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
        ctx.fill(CGRect(x: 50, y: 195, width: 100, height: 6))     // gölgede çizgi
        ctx.fill(CGRect(x: 250, y: 195, width: 100, height: 6))    // aydınlıkta çizgi
        return ctx.makeImage()!
    }

    static func piksel(_ g: CGImage, _ x: Int, _ y: Int) -> Int {
        let ctx = CGContext(data: nil, width: g.width, height: g.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.draw(g, in: CGRect(x: 0, y: 0, width: g.width, height: g.height))
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        // bitmap üst satırdan başlar
        return Int(p[(g.height - 1 - y) * ctx.bytesPerRow + x])
    }

    @Test func siyahBeyazGolgeyiYokEderMetniKorur() {
        let sonuc = TaramaIslemleri.uygula(Self.golgeliSayfa(), filtre: .siyahBeyaz)
        // Gölgedeki zemin de aydınlıktaki zemin de beyaz olmalı
        #expect(Self.piksel(sonuc, 20, 100) > 230, "gölgeli zemin: \(Self.piksel(sonuc, 20, 100))")
        #expect(Self.piksel(sonuc, 380, 100) > 230)
        // Çizgiler siyah kalmalı (gölgede olan dahil)
        #expect(Self.piksel(sonuc, 100, 200) < 60, "gölgedeki çizgi: \(Self.piksel(sonuc, 100, 200))")
        #expect(Self.piksel(sonuc, 300, 200) < 60)
    }

    @Test func golgeTemizlemeOzgundeDeCalisir() {
        let sonuc = TaramaIslemleri.uygula(Self.golgeliSayfa(), filtre: .ozgun, golgeTemizle: true)
        #expect(Self.piksel(sonuc, 20, 100) > 200, "zemin: \(Self.piksel(sonuc, 20, 100))")
        let aynen = TaramaIslemleri.uygula(Self.golgeliSayfa(), filtre: .ozgun)
        #expect(Self.piksel(aynen, 20, 100) < 160)
    }

    @Test func hepsiFiltreBoyutuKorur() {
        let g = Self.golgeliSayfa()
        for f in TaramaFiltresi.allCases {
            let s = TaramaIslemleri.uygula(g, filtre: f)
            #expect(s.width == g.width && s.height == g.height, "\(f)")
        }
    }

    @Test func dondurmeBoyutlariniDegistirir() throws {
        let ctx = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let g = ctx.makeImage()!
        let d = TaramaIslemleri.dondur(g, derece: 90)
        #expect(d.width == 100 && d.height == 200)
        #expect(TaramaIslemleri.dondur(g, derece: 180).width == 200)
        #expect(TaramaIslemleri.dondur(g, derece: 270).height == 200)
        #expect(TaramaIslemleri.dondur(g, derece: 0).width == 200)
    }

    @Test func perspektifDuzeltmeEgikBelgeyiDikdortgenYapar() {
        // Siyah zemin üzerinde eğik beyaz dörtgen
        let g = 600, y = 400
        let ctx = CGContext(data: nil, width: g, height: y, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: g, height: y))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.move(to: CGPoint(x: 100, y: 350)); ctx.addLine(to: CGPoint(x: 500, y: 330))
        ctx.addLine(to: CGPoint(x: 520, y: 60)); ctx.addLine(to: CGPoint(x: 80, y: 40)); ctx.fillPath()
        let img = ctx.makeImage()!
        let dortgen = Dortgen(ustSol: CGPoint(x: 100.0 / 600, y: 50.0 / 400), ustSag: CGPoint(x: 500.0 / 600, y: 70.0 / 400),
                              altSag: CGPoint(x: 520.0 / 600, y: 340.0 / 400), altSol: CGPoint(x: 80.0 / 600, y: 360.0 / 400))
        #expect(dortgen.gecerli)
        let duz = TaramaIslemleri.perspektifDuzelt(img, dortgen: dortgen)
        #expect(duz.width > 300 && duz.height > 200)
        // Orta pikseller beyaz, köşeye yakın pikseller de beyaz (siyah zemin kırpıldı)
        #expect(Self.piksel(duz, 6, 6) > 200)
        #expect(Self.piksel(duz, duz.width - 7, duz.height - 7) > 200)
        #expect(TaramaIslemleri.perspektifDuzelt(img, dortgen: .tam).width == 600)
    }

    @Test func gecersizDortgenReddedilir() {
        let bow = Dortgen(ustSol: CGPoint(x: 0, y: 0), ustSag: CGPoint(x: 1, y: 1), altSag: CGPoint(x: 1, y: 0), altSol: CGPoint(x: 0, y: 1))
        #expect(!bow.gecerli)
        #expect(Dortgen.tam.gecerli)
        #expect(abs(Dortgen.tam.alan - 1) < 1e-9)
    }

    @Test func adOnerisiIlkAnlamliSatiriKullanir() {
        let s = [OCRSatiri(metin: "12", kutu: .zero, guven: 1), OCRSatiri(metin: "Fatura No: 2026/55", kutu: .zero, guven: 1)]
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let ad = TaramaIslemleri.adOner(satirlar: s, tarih: t)
        #expect(ad.hasPrefix("Fatura No"))
        #expect(ad.contains("2027") || ad.contains("2026"))
        #expect(TaramaIslemleri.adOner(satirlar: [], tarih: t).hasPrefix("Tarama "))
    }

    @Test func kucultmeEnBuyukKenariSinirlar() {
        let g = Self.golgeliSayfa()
        #expect(TaramaIslemleri.kucult(g, enBuyukKenar: 100).width == 100)
        #expect(TaramaIslemleri.kucult(g, enBuyukKenar: 1000).width == 400)
    }
}
