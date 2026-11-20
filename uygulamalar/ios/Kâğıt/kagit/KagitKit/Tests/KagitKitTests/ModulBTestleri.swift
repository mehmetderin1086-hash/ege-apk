import CoreGraphics
import Foundation
import PDFKit
import Testing
import pdfium
@testable import KagitKit

@Suite struct MetinSatiriTestleri {
    @Test func satirlariTabanCizgisineGoreGruplar() throws {
        let pdf = Ornek.pdf([["Birinci satır", "İkinci satır ğüşıöç", "Üçüncü"]])
        let b = try PdfiumBelge(veri: pdf)
        let satirlar = MetinGruplayici.satirlar(try b.metinNesneleri(sayfa: 0))
        #expect(satirlar.count == 3)
        #expect(satirlar.map(\.metin) == ["Birinci satır", "İkinci satır ğüşıöç", "Üçüncü"])
        // Yukarıdan aşağı sıralı
        #expect(satirlar[0].tabanY > satirlar[1].tabanY)
        // PDFCizim ilk satırı y = yükseklik - 100'e koyar
        let beklenen = PDFCizim.Boyut.a4.boyut.height - 100
        #expect(abs(satirlar[0].tabanY - beklenen) < 2)
    }

    @Test func ayniSatirdakiUzakParcalarAyriSatirOlur() throws {
        let boyut = PDFCizim.Boyut.a4.boyut
        let y = PDFCizim.Yazici(baslik: "T")
        y.sayfa(CGRect(origin: .zero, size: boyut)) { ctx in
            PDFCizim.metin("Sol", ctx, nokta: CGPoint(x: 72, y: 600), punto: 14)
            PDFCizim.metin("Kelime", ctx, nokta: CGPoint(x: 110, y: 600), punto: 14)
            PDFCizim.metin("Sağ sütun", ctx, nokta: CGPoint(x: 400, y: 600), punto: 14)
        }
        let b = try PdfiumBelge(veri: y.bitir())
        let satirlar = MetinGruplayici.satirlar(try b.metinNesneleri(sayfa: 0))
        #expect(satirlar.count == 2)
        #expect(satirlar.contains { $0.metin.contains("Sağ sütun") })
        #expect(satirlar.contains { $0.metin.hasPrefix("Sol") })
    }

    @Test func noktadakiSatiriBulur() throws {
        let b = try PdfiumBelge(veri: Ornek.pdf([["Alfa", "Beta", "Gama"]]))
        let satirlar = MetinGruplayici.satirlar(try b.metinNesneleri(sayfa: 0))
        let ikinci = satirlar[1]
        let bulunan = MetinGruplayici.satir(satirlar, noktasinda: CGPoint(x: ikinci.kutu.midX, y: ikinci.kutu.midY))
        #expect(bulunan?.metin == "Beta")
        #expect(MetinGruplayici.satir(satirlar, noktasinda: CGPoint(x: 500, y: 20)) == nil)
    }

    @Test func bloklarYakinSatirlariToplar() throws {
        let boyut = PDFCizim.Boyut.a4.boyut
        let y = PDFCizim.Yazici(baslik: "T")
        y.sayfa(CGRect(origin: .zero, size: boyut)) { ctx in
            for (i, s) in ["bir", "iki", "üç"].enumerated() {
                PDFCizim.metin(s, ctx, nokta: CGPoint(x: 72, y: 700 - CGFloat(i) * 18), punto: 12)
            }
            PDFCizim.metin("ayrı blok", ctx, nokta: CGPoint(x: 72, y: 500), punto: 12)
        }
        let b = try PdfiumBelge(veri: y.bitir())
        let satirlar = MetinGruplayici.satirlar(try b.metinNesneleri(sayfa: 0))
        let bloklar = MetinGruplayici.bloklar(satirlar)
        #expect(bloklar.count == 2)
        #expect(bloklar.map { $0.satirlar.count }.sorted() == [1, 3])
    }

    @Test func turkceDuzenleKaydetYenidenAc() throws {
        let pdf = Ornek.pdf([["Eski başlık", "Dokunulmayan satır"]])
        let b = try PdfiumBelge(veri: pdf)
        let satirlar = MetinGruplayici.satirlar(try b.metinNesneleri(sayfa: 0))
        let hedef = try #require(satirlar.first { $0.metin == "Eski başlık" })
        let yeni = "Çalışkan öğrenci ığüşİ ÇÖ"
        try b.satiriDegistir(sayfa: 0, satir: hedef, yeniMetin: yeni, punto: 18, yaziTipi: .sansKalin, renk: .mavi)
        let veri = try b.kaydet()

        let acilan = try #require(PDFDocument(data: veri))
        let metin = acilan.string ?? ""
        #expect(metin.contains(yeni))
        #expect(!metin.contains("Eski başlık"))
        #expect(metin.contains("Dokunulmayan satır"))

        // Yeniden gruplanınca yeni satır aynı taban çizgisinde
        let b2 = try PdfiumBelge(veri: veri)
        let yeniSatirlar = MetinGruplayici.satirlar(try b2.metinNesneleri(sayfa: 0))
        let bulunan = try #require(yeniSatirlar.first { $0.metin == yeni })
        #expect(abs(bulunan.tabanY - hedef.tabanY) < 1)
        #expect(abs(bulunan.punto - 18) < 0.5)
    }
}

@Suite struct SayfaIslemleriTestleri {
    @Test func siralama() {
        #expect(BelgeSayfaIslemleri.siralama(sayi: 5, tasinacak: [3], hedef: 1) == [0, 3, 1, 2, 4])
        #expect(BelgeSayfaIslemleri.siralama(sayi: 5, tasinacak: [0, 1], hedef: 5) == [2, 3, 4, 0, 1])
        #expect(BelgeSayfaIslemleri.siralama(sayi: 5, tasinacak: [4], hedef: 0) == [4, 0, 1, 2, 3])
        // Kendi bloğunun içine bırakmak sırayı değiştirmez
        #expect(BelgeSayfaIslemleri.siralama(sayi: 4, tasinacak: [1, 2], hedef: 2) == [0, 1, 2, 3])
        let s = BelgeSayfaIslemleri.siralama(sayi: 6, tasinacak: [1, 4], hedef: 3)
        #expect(BelgeSayfaIslemleri.tersSira(s).count == 6)
        #expect(zip(s, BelgeSayfaIslemleri.tersSira(s)).allSatisfy { BelgeSayfaIslemleri.tersSira(s)[$0.0] == s.firstIndex(of: $0.0)! })
    }

    private func etiketler(_ b: PDFDocument) -> [String] {
        (0..<b.pageCount).map { ($0 < b.pageCount ? b.page(at: $0)?.string ?? "" : "").trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    @Test func siralaVeGeriAl() {
        let b = Ornek.numarali(5)
        let sira = BelgeSayfaIslemleri.siralama(sayi: 5, tasinacak: [3], hedef: 1)
        BelgeSayfaIslemleri.sirala(b, yeniSira: sira)
        #expect(etiketler(b) == ["Sayfa 1", "Sayfa 4", "Sayfa 2", "Sayfa 3", "Sayfa 5"])
        BelgeSayfaIslemleri.sirala(b, yeniSira: BelgeSayfaIslemleri.tersSira(sira))
        #expect(etiketler(b) == (1...5).map { "Sayfa \($0)" })
    }

    @Test func silCogaltDondurCikar() throws {
        let b = Ornek.numarali(4)
        let silinen = BelgeSayfaIslemleri.sil(b, indeksler: [1, 2])
        #expect(etiketler(b) == ["Sayfa 1", "Sayfa 4"])
        BelgeSayfaIslemleri.geriKoy(b, silinen)
        #expect(etiketler(b) == (1...4).map { "Sayfa \($0)" })

        let eklenen = BelgeSayfaIslemleri.cogalt(b, indeksler: [0, 2])
        #expect(eklenen.count == 2)
        #expect(etiketler(b) == ["Sayfa 1", "Sayfa 1", "Sayfa 2", "Sayfa 3", "Sayfa 3", "Sayfa 4"])

        BelgeSayfaIslemleri.dondur(b, indeksler: [0], derece: 90)
        BelgeSayfaIslemleri.dondur(b, indeksler: [0], derece: 90)
        #expect(b.page(at: 0)?.rotation == 180)
        BelgeSayfaIslemleri.dondur(b, indeksler: [0], derece: -270)
        #expect(b.page(at: 0)?.rotation == 270)

        let veri = try BelgeSayfaIslemleri.cikar(b, indeksler: [5, 2])
        let c = try #require(PDFDocument(data: veri))
        #expect(c.pageCount == 2)
        #expect(etiketler(c) == ["Sayfa 2", "Sayfa 4"])
        #expect(throws: KagitHata.self) { try BelgeSayfaIslemleri.cikar(b, indeksler: []) }
    }

    @Test func bosSayfaKomsununBoyutunda() {
        let b = Ornek.numarali(1)
        let bos = BelgeSayfaIslemleri.bosSayfa(boyut: b.page(at: 0))
        #expect(bos.bounds(for: .mediaBox).size == b.page(at: 0)?.bounds(for: .mediaBox).size)
        b.insert(bos, at: 1)
        #expect(b.pageCount == 2)
        #expect(BelgeSayfaIslemleri.bosSayfa(boyut: nil).bounds(for: .mediaBox).size == PDFCizim.Boyut.a4.boyut)
    }
}

@Suite struct AcroFormTestleri {
    private func formluBelge() -> PDFDocument {
        let b = Ornek.belge([["Form"]])
        let s = b.page(at: 0)!
        let ad = PDFAnnotation(bounds: CGRect(x: 50, y: 700, width: 200, height: 24), forType: .widget, withProperties: nil)
        ad.widgetFieldType = .text
        ad.fieldName = "ad"
        ad.widgetStringValue = "Ayşe"
        s.addAnnotation(ad)
        let onay = PDFAnnotation(bounds: CGRect(x: 50, y: 650, width: 20, height: 20), forType: .widget, withProperties: nil)
        onay.widgetFieldType = .button
        onay.widgetControlType = .checkBoxControl
        onay.fieldName = "onay"
        s.addAnnotation(onay)
        return b
    }

    private func alanSayisi(_ veri: Data) -> Int? {
        guard let sağlayıcı = CGDataProvider(data: veri as CFData), let cg = CGPDFDocument(sağlayıcı),
              let katalog = cg.catalog else { return nil }
        var acro: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(katalog, "AcroForm", &acro), let acro else { return nil }
        var alanlar: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(acro, "Fields", &alanlar), let alanlar else { return nil }
        return CGPDFArrayGetCount(alanlar)
    }

    @Test func yamaAcroFormEkler() throws {
        let ham = try #require(formluBelge().dataRepresentation())
        #expect(alanSayisi(ham) == nil)
        #expect(AcroFormYamasi.gerekliMi(ham))

        let yamali = AcroFormYamasi.uygula(ham)
        #expect(yamali.count > ham.count)
        #expect(Array(yamali.prefix(ham.count)) == Array(ham))   // artımlı: özgün bayt dizisi korunur
        #expect(alanSayisi(yamali) == 2)
        #expect(!AcroFormYamasi.gerekliMi(yamali))

        // PDFKit hâlâ iki alanı okuyor ve değerleri duruyor
        let acilan = try #require(PDFDocument(data: yamali))
        let alanlar = acilan.page(at: 0)!.annotations.filter { $0.type == "Widget" }
        #expect(alanlar.count == 2)
        #expect(alanlar.contains { $0.fieldName == "ad" && $0.widgetStringValue == "Ayşe" })

        // PDFium form olarak tanıyor (yama öncesi tanımıyordu)
        let once = try PdfiumBelge(veri: ham)
        let sonra = try PdfiumBelge(veri: yamali)
        #expect(FPDF_GetFormType(once.belge) == 0)
        #expect(FPDF_GetFormType(sonra.belge) == 1)

        // İkinci kez uygulamak değiştirmez
        #expect(AcroFormYamasi.uygula(yamali) == yamali)
    }

    @Test func yamaliPdfYenidenKaydedilebilir() throws {
        let yamali = AcroFormYamasi.uygula(try #require(formluBelge().dataRepresentation()))
        let acilan = try #require(PDFDocument(data: yamali))
        let tekrar = try #require(acilan.dataRepresentation())
        #expect(PDFDocument(data: tekrar)?.pageCount == 1)
    }

    @Test func widgetsizBelgeDegismez() throws {
        let v = Ornek.pdf([["düz"]])
        #expect(AcroFormYamasi.uygula(v) == v)
    }

    @Test func kayitHattiYamayiUygular() throws {
        let veri = try KayitIsleme.veri(formluBelge())
        #expect(alanSayisi(veri) == 2)
    }
}

@Suite struct DamgaVeAciklamaTestleri {
    @Test func damgaKayitta_icerigeIslenir() throws {
        let b = Ornek.belge([["Sayfa"]])
        let sayfa = try #require(b.page(at: 0))
        let tanim = DamgaTanimi(metin: "ONAYLANDI", renk: .yesil)
        let boyut = tanim.varsayilanBoyut()
        let damga = KagitDamgasi(bounds: CGRect(origin: CGPoint(x: 100, y: 400), size: boyut), tanim: tanim)
        sayfa.addAnnotation(damga)
        let ortu = KagitDamgasi(bounds: CGRect(x: 72, y: 700, width: 100, height: 20), tanim: DamgaTanimi(tur: .ortu, renk: .beyaz))
        sayfa.addAnnotation(ortu)

        let veri = try KayitIsleme.veri(b)
        // Bellekteki belge bozulmadı: damgalar yerinde
        #expect(sayfa.annotations.filter { $0 is KagitDamgasi }.count == 2)

        let acilan = try #require(PDFDocument(data: veri))
        #expect(acilan.page(at: 0)!.annotations.filter { $0.type == "Stamp" }.isEmpty)
        let p = try PdfiumBelge(veri: veri)
        let nesneler = try p.nesneler(sayfa: 0)
        #expect(nesneler.contains { $0.tur == .gorsel })
        #expect(nesneler.contains { $0.tur == .yol })
        // Damganın bulunduğu yerde görünür piksel var
        let ilkSayfa = try #require(acilan.page(at: 0))
        let goruntu = try #require(PDFCizim.goruntu(ilkSayfa, dpi: 72))
        let yukseklik = goruntu.height
        let sol = Int(damga.bounds.midX), ust = yukseklik - Int(damga.bounds.midY)
        #expect(piksel(goruntu, x: Int(damga.bounds.minX) + 3, y: yukseklik - Int(damga.bounds.midY)) != nil)
        _ = (sol, ust)
    }

    /// Damga çerçevesinin sol kenarında beyaz olmayan piksel var mı.
    private func piksel(_ g: CGImage, x: Int, y: Int) -> Bool? {
        guard let veri = g.dataProvider?.data, let ptr = CFDataGetBytePtr(veri) else { return nil }
        let bayt = g.bitsPerPixel / 8
        for dx in -4...6 {
            for dy in -3...3 {
                let i = (y + dy) * g.bytesPerRow + (x + dx) * bayt
                if ptr[i] < 200 || ptr[i + 1] < 200 || ptr[i + 2] < 200 { return true }
            }
        }
        return nil
    }

    @Test func gorselDamgasiPdfiumIleEklenir() throws {
        let tanim = DamgaTanimi(metin: "X", renk: .mavi)
        let g = try #require(tanim.goruntu(boyut: CGSize(width: 80, height: 40)))
        let png = try #require(PDFCizim.kodla(g, tur: .png))
        let b = Ornek.belge([["Sayfa"]])
        b.page(at: 0)!.addAnnotation(KagitDamgasi(bounds: CGRect(x: 50, y: 300, width: 80, height: 40),
                                                  tanim: DamgaTanimi(tur: .gorsel, gorselVeri: png)))
        let veri = try KayitIsleme.veri(b)
        let p = try PdfiumBelge(veri: veri)
        #expect(try p.nesneler(sayfa: 0).contains { $0.tur == .gorsel })
    }

    @Test func aciklamalarKaydedilipOkunur() throws {
        let b = Ornek.belge([["Vurgulanacak metin burada", "ikinci"]])
        let s = try #require(b.page(at: 0))
        let satir = CGRect(x: 72, y: 700, width: 200, height: 16)
        for tur in AciklamaFabrikasi.MetinIsareti.allCases {
            let a = try #require(AciklamaFabrikasi.metinIsareti(tur, satirlar: [satir, satir.offsetBy(dx: 0, dy: -30)], renk: .kirmizi.opaklikla(0.5)))
            s.addAnnotation(a)
        }
        s.addAnnotation(AciklamaFabrikasi.sekil(.dikdortgen, a: CGPoint(x: 50, y: 400), b: CGPoint(x: 150, y: 450), renk: .mavi, kalinlik: 2, dolgu: RGBA.mavi.opaklikla(0.2)))
        s.addAnnotation(AciklamaFabrikasi.sekil(.daire, a: CGPoint(x: 200, y: 400), b: CGPoint(x: 260, y: 450), renk: .yesil, kalinlik: 3))
        s.addAnnotation(AciklamaFabrikasi.sekil(.ok, a: CGPoint(x: 50, y: 300), b: CGPoint(x: 150, y: 350), renk: .kirmizi, kalinlik: 2))
        s.addAnnotation(AciklamaFabrikasi.sekil(.cizgi, a: CGPoint(x: 50, y: 250), b: CGPoint(x: 150, y: 250), renk: .siyah, kalinlik: 1))
        s.addAnnotation(AciklamaFabrikasi.metinKutusu(CGRect(x: 72, y: 500, width: 200, height: 30), metin: "Çok güzel ğüşıİ", punto: 14, renk: .siyah))
        s.addAnnotation(AciklamaFabrikasi.not(CGPoint(x: 400, y: 600), metin: "Kontrol et"))
        let cizim = try #require(AciklamaFabrikasi.murekkep(yollar: [[CGPoint(x: 300, y: 300), CGPoint(x: 320, y: 340), CGPoint(x: 360, y: 310)]], renk: .kirmizi, kalinlik: 3))
        s.addAnnotation(cizim)
        s.addAnnotation(AciklamaFabrikasi.baglanti(kutu: CGRect(x: 72, y: 100, width: 100, height: 20), url: URL(string: "https://example.com")!))

        let veri = try KayitIsleme.veri(b)
        let acilan = try #require(PDFDocument(data: veri))
        let ilk = try #require(acilan.page(at: 0))
        let tipler = Set(ilk.annotations.compactMap(\.type))
        for beklenen in ["Highlight", "Underline", "StrikeOut", "Ink", "Square", "Circle", "Line", "FreeText", "Text", "Link"] {
            #expect(tipler.contains(beklenen), "eksik: \(beklenen)")
        }
        let metinKutusu = acilan.page(at: 0)!.annotations.first { $0.type == "FreeText" }
        #expect(metinKutusu?.contents == "Çok güzel ğüşıİ")
    }

    @Test func seyreltmeUclariKorur() {
        let n = (0..<100).map { CGPoint(x: CGFloat($0) * 0.1, y: 0) }
        let s = AciklamaFabrikasi.seyrelt(n, aralik: 1)
        #expect(s.first == n.first && s.last == n.last)
        #expect(s.count < n.count)
    }

    @Test func hazirDamgalarTurkceHarfliDir() {
        #expect(DamgaTanimi.hazirlar.map(\.metin) == ["ONAYLANDI", "TASLAK", "GİZLİ", "ÖRNEK", "CEVAP ANAHTARI", "İNCELENDİ"])
        let t = DamgaTanimi.tarihDamgasi(tarih: Date(timeIntervalSince1970: 1_790_000_000), ad: "Ali")
        #expect(t.altMetin == "Ali")
        #expect(t.metin == t.metin.uppercased(with: Locale(identifier: "tr_TR")))
    }
}

@Suite struct DuzenlemeAraclariTestleri {
    private func karisikBelge() throws -> URL {
        let b = Ornek.belge([["Düzleştirilecek metin"]])
        let s = b.page(at: 0)!
        let vurgu = try #require(AciklamaFabrikasi.metinIsareti(.vurgu, satirlar: [CGRect(x: 72, y: 700, width: 150, height: 16)], renk: .kirmizi.opaklikla(0.5)))
        s.addAnnotation(vurgu)
        s.addAnnotation(AciklamaFabrikasi.sekil(.dikdortgen, a: CGPoint(x: 50, y: 400), b: CGPoint(x: 150, y: 450), renk: .mavi, kalinlik: 2))
        s.addAnnotation(AciklamaFabrikasi.baglanti(kutu: CGRect(x: 72, y: 100, width: 100, height: 20), url: URL(string: "https://example.com")!))
        let w = PDFAnnotation(bounds: CGRect(x: 50, y: 600, width: 200, height: 24), forType: .widget, withProperties: nil)
        w.widgetFieldType = .text
        w.fieldName = "ad"
        w.widgetStringValue = "Değer"
        s.addAnnotation(w)
        let u = Ornek.gecici("karisik-\(UUID().uuidString).pdf")
        try Belge.kaydet(b, u)
        return u
    }

    @Test func duzlestirAciklamaVeFormuIcerigeIsler() throws {
        let u = try karisikBelge()
        let veri = try DuzenlemeAraclari.duzlestir(url: u)
        let c = try #require(PDFDocument(data: veri))
        let kalan = c.page(at: 0)!.annotations.compactMap(\.type)
        #expect(!kalan.contains("Highlight"))
        #expect(!kalan.contains("Square"))
        #expect(!kalan.contains("Widget"))
        #expect((c.string ?? "").contains("Düzleştirilecek metin"))
        let p = try PdfiumBelge(veri: veri)
        #expect(try p.nesneler(sayfa: 0).contains { !$0.tur.isDisjoint(with: [.yol, .form]) })
    }

    @Test func aciklamalariKaldirBaglantiVeFormuKorur() throws {
        let u = try karisikBelge()
        let (veri, n) = try DuzenlemeAraclari.aciklamalariKaldir(url: u)
        #expect(n == 2)
        let kalan = try #require(PDFDocument(data: veri)).page(at: 0)!.annotations.compactMap(\.type)
        #expect(Set(kalan) == ["Link", "Widget"])
        let (hepsi, m) = try DuzenlemeAraclari.aciklamalariKaldir(url: u, baglantilariKoru: false, formlariKoru: false)
        #expect(m == 4)
        #expect(try #require(PDFDocument(data: hepsi)).page(at: 0)!.annotations.isEmpty)
    }
}
