import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import KagitKit

/// Taranmış belgeyi taklit eden: rastgele gürültülü büyük görüntülü sayfalar.
func gorselliPDF(sayfa: Int) throws -> URL {
    let y = PDFCizim.Yazici()
    for i in 0..<sayfa {
        y.sayfa(CGRect(x: 0, y: 0, width: 595, height: 842)) { ctx in
            var piksel = [UInt8](repeating: 0, count: 1000 * 1400 * 4)
            for k in stride(from: 0, to: piksel.count, by: 4) {
                let v = UInt8((k / 4 % 1000 / 8 + i * 5) % 200) &+ UInt8.random(in: 0...40)
                piksel[k] = v; piksel[k + 1] = v &+ 10; piksel[k + 2] = v &+ 20; piksel[k + 3] = 255
            }
            let img = CGContext(data: &piksel, width: 1000, height: 1400, bitsPerComponent: 8, bytesPerRow: 4000,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!.makeImage()!
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: 595, height: 842))
            PDFCizim.metin("Tarama \(i + 1)", ctx, nokta: CGPoint(x: 60, y: 780), punto: 20)
        }
    }
    let u = Ornek.gecici("tarama.pdf")
    try y.bitir().write(to: u)
    return u
}

@Suite struct ModulADamgaTestleri {

    @Test func metinFiligranArkadaVeOnde() throws {
        let u = try ornekDosya(3)
        var a = FiligranAyari(tur: .metin("TASLAK"))
        a.aralik = "1-2"
        let c = try Belge.ac(DamgaIslemleri.filigran(u, ayar: a))
        #expect(c.pageCount == 3)
        #expect(c.page(at: 0)?.string?.contains("TASLAK") == true)
        #expect(c.page(at: 0)?.string?.contains("Sayfa 1") == true)
        #expect(c.page(at: 2)?.string?.contains("TASLAK") == false)
        a.onde = false
        a.doseme = true
        a.aralik = ""
        let d = try Belge.ac(DamgaIslemleri.filigran(u, ayar: a))
        #expect(d.page(at: 2)?.string?.contains("TASLAK") == true)
        #expect(d.page(at: 1)?.string?.contains("Sayfa 2") == true)
    }

    @Test func filigranPikselleriDegistirir() throws {
        let u = try ornekDosya(1)
        let onceki = try Belge.ac(u).page(at: 0)!
        var a = FiligranAyari(tur: .metin("GİZLİ"))
        a.opaklik = 0.8; a.punto = 120; a.renk = .kirmizi
        let sonra = try Belge.ac(DamgaIslemleri.filigran(u, ayar: a)).page(at: 0)!
        let g1 = PDFCizim.goruntu(onceki, dpi: 30)!, g2 = PDFCizim.goruntu(sonra, dpi: 30)!
        #expect(g1.dataProvider?.data != g2.dataProvider?.data)
        #expect(icerikOranlari(sonra)!.width > icerikOranlari(onceki)!.width)
    }

    @Test func gorselFiligran() throws {
        let u = try ornekDosya(1)
        let ctx = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        let png = PDFCizim.kodla(ctx.makeImage()!, tur: .png)!
        var a = FiligranAyari(tur: .gorsel(png))
        a.aci = 0; a.opaklik = 1; a.gorselOlcek = 0.4
        let sonra = try Belge.ac(DamgaIslemleri.filigran(u, ayar: a)).page(at: 0)!
        let o = icerikOranlari(sonra)!
        #expect(o.width > 0.3)
        #expect(throws: KagitHata.self) { try DamgaIslemleri.filigran(u, ayar: FiligranAyari(tur: .gorsel(Data([1, 2, 3])))) }
        #expect(throws: KagitHata.self) { try DamgaIslemleri.filigran(u, ayar: FiligranAyari(tur: .metin("  "))) }
    }

    @Test func sayfaNumarasiBicimleri() throws {
        let u = try ornekDosya(4)
        var a = NumaraAyari()
        a.bicim = "{n}/{N}"
        let c = try Belge.ac(DamgaIslemleri.sayfaNumarasi(u, ayar: a))
        #expect(c.page(at: 0)?.string?.contains("1/4") == true)
        #expect(c.page(at: 3)?.string?.contains("4/4") == true)
        a.bicim = "Sayfa {n}"; a.baslangic = 5; a.ilkSayfayiAtla = true; a.konum = .ustSag
        let d = try Belge.ac(DamgaIslemleri.sayfaNumarasi(u, ayar: a))
        #expect(d.page(at: 0)?.string?.contains("Sayfa 5") == false)
        #expect(d.page(at: 1)?.string?.contains("Sayfa 5") == true)
        #expect(d.page(at: 3)?.string?.contains("Sayfa 7") == true)
    }

    @Test func ustAltBilgiYerTutucular() throws {
        let u = try ornekDosya(2, ad: "Ders Notu.pdf")
        var a = BilgiAyari()
        a.alanlar = [.ustSol: "{dosya}", .ustSag: "{tarih}", .altOrta: "{n} / {N}"]
        let c = try Belge.ac(DamgaIslemleri.ustAltBilgi(u, ayar: a))
        let m = c.page(at: 1)?.string ?? ""
        #expect(m.contains("Ders Notu"))
        #expect(m.contains("2 / 2"))
        let bicim = DateFormatter(); bicim.dateFormat = "dd.MM.yyyy"
        #expect(m.contains(bicim.string(from: Date())))
        #expect(DamgaIslemleri.yerTutucu("{n}-{N}", n: 3, son: 9, dosya: "x", tarih: "t") == "3-9")
    }
}

@Suite struct ModulASikistirmaTestleri {

    @Test func vektorYolMetniKorur() throws {
        let u = try gorselliPDF(sayfa: 2)
        let s = try Sikistirma.sikistir(u, ayar: .onAyar(.orta))
        #expect(s.kuculdu)
        #expect(s.ciktiBoyu < s.girdiBoyu)
        let c = try Belge.ac(s.cikti)
        #expect(c.pageCount == 2)
        #expect(c.page(at: 0)?.string?.contains("Tarama 1") == true)
        #expect(s.ileti.contains("küçüldü"))
    }

    @Test func rasterYolDahaKucukVeSayfaSayisiKorunur() throws {
        let u = try gorselliPDF(sayfa: 2)
        let s = try Sikistirma.sikistir(u, ayar: .onAyar(.yuksek))
        #expect(s.kuculdu && s.kullanilanYol == .rasterlestir)
        #expect(Double(s.ciktiBoyu) < Double(s.girdiBoyu) * 0.6)
        let c = try Belge.ac(s.cikti)
        #expect(c.pageCount == 2)
        let b = c.page(at: 0)!.bounds(for: .cropBox)
        #expect(abs(b.width - 595) < 1)
    }

    @Test func ozelDpiKaliteEtkili() throws {
        let u = try gorselliPDF(sayfa: 1)
        let iyi = try Sikistirma.sikistir(u, ayar: SikistirmaAyari(yol: .rasterlestir, dpi: 150, jpegKalite: 0.9))
        let kotu = try Sikistirma.sikistir(u, ayar: SikistirmaAyari(yol: .rasterlestir, dpi: 72, jpegKalite: 0.3))
        #expect(kotu.ciktiBoyu < iyi.ciktiBoyu)
    }

    @Test func zatenKucukOlanGirdiyiKorur() throws {
        let u = try ornekDosya(1)
        let s = try Sikistirma.sikistir(u, ayar: .onAyar(.yuksek))
        #expect(!s.kuculdu)
        #expect(s.cikti == u)
        #expect(s.ileti.contains("korundu"))
    }

    @Test func hedefBoyutKademeli() throws {
        let u = try gorselliPDF(sayfa: 3)
        let girdi = IsYardimcisi.dosyaBoyutu(u)
        var a = SikistirmaAyari.onAyar(.epostayaSigdir)
        a.hedefBayt = girdi / 8
        let s = try Sikistirma.sikistir(u, ayar: a)
        #expect(s.kuculdu)
        #expect(s.ciktiBoyu <= girdi / 8)
        #expect(s.hedefeUlasti)
        #expect(try Belge.ac(s.cikti).pageCount == 3)
    }
}
