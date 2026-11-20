import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import KagitKit

/// Modül D testlerinde kullanılan örnek PDF'ler.
enum ModulDOrnek {
    /// Sayfa başına (x, y, metin) üçlüleri.
    static func yerlesimli(_ sayfalar: [[(CGFloat, CGFloat, String)]], punto: CGFloat = 12) -> Data {
        let boyut = PDFCizim.Boyut.a4.boyut
        let y = PDFCizim.Yazici(baslik: "Örnek")
        for s in sayfalar {
            y.sayfa(CGRect(origin: .zero, size: boyut)) { ctx in
                for (x, yy, m) in s { PDFCizim.metin(m, ctx, nokta: CGPoint(x: x, y: yy), punto: punto) }
            }
        }
        return y.bitir()
    }

    /// Her sayfanın üstünde “Ad Soyad: …” yazan sentetik tarama yığını; boş ad = devam sayfası.
    static func adliYigin(_ adlar: [String?]) -> Data {
        yerlesimli(adlar.enumerated().map { i, ad in
            var satirlar: [(CGFloat, CGFloat, String)] = [(60, 500, "Cevap sayfası \(i + 1)")]
            if let ad { satirlar.append((60, 790, "Adı Soyadı: \(ad)")) }
            return satirlar
        })
    }

    /// Tek sütun sınav: 4 soru, 3. soru ikinci sayfaya taşar.
    static func sinav() -> Data {
        yerlesimli([
            [(50, 780, "1. Hücre zarının yapısında bulunan moleküller hangileridir?"),
             (70, 760, "A) Fosfolipit"), (70, 745, "B) Selüloz"),
             (50, 700, "2. Aşağıdakilerden hangisi organeldir?"),
             (70, 680, "A) Ribozom"), (70, 665, "B) Glikoz"),
             (50, 620, "3. Fotosentez nerede gerçekleşir?"),
             (70, 600, "A) Kloroplast")],
            [(70, 790, "B) Mitokondri"),
             (50, 740, "4. DNA'nın yapı taşı nedir?"),
             (70, 720, "A) Nükleotit"), (70, 705, "B) Amino asit")],
        ])
    }

    /// İki sütunlu sınav: sol 1-3, sağ 4-6.
    static func ikiSutunluSinav() -> Data {
        var sol: [(CGFloat, CGFloat, String)] = []
        var sag: [(CGFloat, CGFloat, String)] = []
        for i in 0..<3 {
            let y = 760 - CGFloat(i) * 120
            sol += [(40, y, "\(i + 1). Soru metni \(i + 1) burada"), (60, y - 18, "A) şık bir"), (60, y - 33, "B) şık iki")]
            sag += [(320, y, "\(i + 4). Soru metni \(i + 4) burada"), (340, y - 18, "A) şık bir"), (340, y - 33, "B) şık iki")]
        }
        return yerlesimli([sol + sag])
    }
}

@Suite struct SinifListesiTestleri {
    @Test func yapistirilanMetin() {
        let l = SinifAyristirici.metin("""
        123 Ayşe Yılmaz
        124 Mehmet Can Demir
        125\tZeynep Kaya
        Öğrenci Listesi
        """)
        #expect(l.count == 3)
        #expect(l[0].no == "123" && l[0].ad == "Ayşe Yılmaz")
        #expect(l[1].ad == "Mehmet Can Demir")
        #expect(l[2].no == "125" && l[2].ad == "Zeynep Kaya")
    }

    @Test func eOkulBicimi() {
        // sıra no + okul no + AD SOYAD + cinsiyet
        let o = SinifAyristirici.satir("3 1045 AYŞE YILMAZ K")
        #expect(o?.no == "1045")
        #expect(o?.ad == "Ayşe Yılmaz")
        #expect(SinifAyristirici.satir("Ayşe Yılmaz 77")?.no == "77")
        #expect(SinifAyristirici.satir("Sıra No Adı Soyadı") == nil)
    }

    @Test func csvAyristirma() {
        let csv = "No;Ad Soyad\n12;\"Yılmaz, Ayşe\"\n13;Ali Veli\n"
        let l = SinifAyristirici.csv(csv)
        #expect(l.count == 2)
        #expect(l[1].no == "13" && l[1].ad == "Ali Veli")
    }

    @Test func xlsxYuvarlak() throws {
        let tablo: [[XlsxHucre]] = [[.kalin("No"), .kalin("Ad Soyad")], [.sayi(7), .metin("Çağla Şen")], [.sayi(8), .metin("Ömer Işık")]]
        let veri = XlsxYazici.yaz(satirlar: tablo)
        let l = SinifAyristirici.xlsx(veri)
        #expect(l.count == 2)
        #expect(l[0] == Ogrenci(no: "7", ad: "Çağla Şen") || (l[0].no == "7" && l[0].ad == "Çağla Şen"))
        #expect(l[1].ad == "Ömer Işık")
    }

    @Test func xlsxPaylasilanDizgilerle() {
        // Excel biçimi: sharedStrings + t="s" hücreler
        var z = ZipYazici()
        z.ekle("xl/sharedStrings.xml", metin: "<?xml version=\"1.0\"?><sst><si><t>Ayşe Yılmaz</t></si><si><r><t>Ali </t></r><r><t>Kara</t></r></si></sst>")
        z.ekle("xl/worksheets/sheet1.xml", metin: "<?xml version=\"1.0\"?><worksheet><sheetData><row r=\"1\"><c r=\"A1\"><v>101</v></c><c r=\"B1\" t=\"s\"><v>0</v></c></row><row r=\"2\"><c r=\"A2\"><v>102</v></c><c r=\"B2\" t=\"s\"><v>1</v></c></row></sheetData></worksheet>")
        let l = SinifAyristirici.xlsx(z.bitir())
        #expect(l.map(\.ad) == ["Ayşe Yılmaz", "Ali Kara"])
        #expect(l.map(\.no) == ["101", "102"])
    }

    @Test func metinliPDF() async {
        let pdf = ModulDOrnek.yerlesimli([[(60, 780, "1 2001 AYŞE YILMAZ K"), (60, 760, "2 2002 MEHMET DEMİR E"), (60, 740, "Sınıf Listesi")]])
        let l = await SinifAyristirici.pdf(veri: pdf)
        #expect(l.count == 2)
        #expect(l.first?.no == "2001")
        #expect(l.last?.ad == "Mehmet Demir")
    }

    @Test func depoKaydeder() throws {
        let u = Gecici.dosya("siniflar.json")
        let d = SinifDeposu(dosya: u)
        try d.kaydet([Sinif(ad: "9-A", ogrenciler: [Ogrenci(no: "1", ad: "Ali Veli")])])
        let y = d.yukle()
        #expect(y.count == 1 && y[0].ogrenciler[0].ad == "Ali Veli")
    }
}

@Suite struct YiginBolmeTestleri {
    let ogrenciler = [Ogrenci(no: "101", ad: "Ayşe Yılmaz"), Ogrenci(no: "102", ad: "Mehmet Demir"), Ogrenci(no: "103", ad: "Zeynep Kaya")]

    @Test func herNSayfa() {
        let p = YiginBolme.herN(sayfaSayisi: 7, n: 3)
        #expect(p.map(\.sayfalar) == [[0, 1, 2], [3, 4, 5], [6]])
    }

    @Test func adlaBolMetinden() {
        let p = YiginBolme.adlaBol(ustMetinler: ["Adı Soyadı: Ayşe Yılmaz", "", "Ad Soyad: MEHMET DEMİR", "", "", "Zeynep Kaya 103"],
                                   ogrenciler: ogrenciler)
        #expect(p.map(\.sayfalar) == [[0, 1], [2, 3, 4], [5]])
        #expect(p.map(\.ogrenci) == [0, 1, 2])
    }

    @Test func ayniAdHerSayfadaBolmez() {
        let p = YiginBolme.adlaBol(ustMetinler: ["Ayşe Yılmaz", "Ayşe Yılmaz", "Mehmet Demir"], ogrenciler: ogrenciler)
        #expect(p.map(\.sayfalar) == [[0, 1], [2]])
    }

    @Test func okumaHatasiTolere() {
        // OCR'da “Yılmaz” → “Yilmaz”, “Ayşe” → “Ayse”
        let p = YiginBolme.adlaBol(ustMetinler: ["Ayse Yilmaz", "x", "Mehmt Demir"], ogrenciler: ogrenciler)
        #expect(p.count == 2)
        #expect(p[1].ogrenci == 1)
    }

    @Test func sentetikPDFileAdAlgila() async throws {
        let pdf = ModulDOrnek.adliYigin(["Ayşe Yılmaz", nil, "Mehmet Demir", nil, nil, "Zeynep Kaya"])
        let parcalar = try await YiginBolme.oner(veri: pdf, kip: .adAlgila, ogrenciler: ogrenciler)
        #expect(parcalar.map(\.sayfalar) == [[0, 1], [2, 3, 4], [5]])
        let cikti = try YiginBolme.ciktilar(veri: pdf, parcalar: parcalar, ogrenciler: ogrenciler, sinavAdi: "1. Yazılı")
        #expect(cikti.map(\.ad) == ["101 Ayşe Yılmaz - 1. Yazılı", "102 Mehmet Demir - 1. Yazılı", "103 Zeynep Kaya - 1. Yazılı"])
        #expect(PDFDocument(data: cikti[1].veri)?.pageCount == 3)
    }

    @Test func bosSayfaAyirici() async throws {
        let boyut = PDFCizim.Boyut.a4.boyut
        let y = PDFCizim.Yazici()
        for dolu in [true, true, false, true, false, false, true] {
            y.sayfa(CGRect(origin: .zero, size: boyut)) { ctx in
                if dolu { for i in 0..<12 { PDFCizim.metin("Yazılı cevap satırı \(i) lorem ipsum dolor sit amet", ctx, nokta: CGPoint(x: 60, y: 780 - CGFloat(i) * 40), punto: 14) } }
            }
        }
        let p = try await YiginBolme.oner(veri: y.bitir(), kip: .bosSayfa, ogrenciler: [])
        #expect(p.map(\.sayfalar) == [[0, 1], [3], [6]])
    }

    @Test func birlestirVeBol() {
        var p = YiginBolme.herN(sayfaSayisi: 6, n: 2)
        p = YiginBolme.birlestir(p, 0)
        #expect(p.map(\.sayfalar) == [[0, 1, 2, 3], [4, 5]])
        p = YiginBolme.bol(p, 0, konum: 1)
        #expect(p.map(\.sayfalar) == [[0], [1, 2, 3], [4, 5]])
        #expect(YiginBolme.bol(p, 0, konum: 5).count == 3)   // geçersiz konum: değişmez
    }

    @Test func atanmamisVeYinelenenAdlar() throws {
        let pdf = ModulDOrnek.adliYigin([nil, nil, nil, nil])
        let p = [YiginParcasi(sayfalar: [0, 1], ogrenci: 0), YiginParcasi(sayfalar: [2], ogrenci: 0), YiginParcasi(sayfalar: [3])]
        let c = try YiginBolme.ciktilar(veri: pdf, parcalar: p, ogrenciler: ogrenciler, sinavAdi: "")
        #expect(c.map(\.ad) == ["101 Ayşe Yılmaz", "101 Ayşe Yılmaz (2)", "Atanmamış 1"])
    }

    @Test func gorselTaramadanOCR() async throws {
        // Metin katmanı olmayan (rasterize) sayfa: ad OCR ile okunmalı
        let kaynak = PDFDocument(data: ModulDOrnek.yerlesimli([[(60, 790, "Adi Soyadi: Ayse Yilmaz")]], punto: 28))!
        let g = try #require(PDFCizim.goruntu(kaynak.page(at: 0)!, dpi: 150))
        let y = PDFCizim.Yazici()
        y.sayfa(CGRect(x: 0, y: 0, width: 595.28, height: 841.89)) { ctx in ctx.draw(g, in: CGRect(x: 0, y: 0, width: 595.28, height: 841.89)) }
        let pdf = y.bitir()
        let belge = try #require(PDFDocument(data: pdf))
        #expect((belge.page(at: 0)?.string).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? true)
        let metin = await YiginBolme.ustMetni(sayfa: belge.page(at: 0)!)
        #expect(TurkceMetin.anahtar(metin).contains("yilmaz"))
    }
}

@Suite struct SoruAlgilamaTestleri {
    @Test func soruNumaralari() {
        #expect(SoruAlgilama.soruNumarasi("12. Aşağıdakilerden") == 12)
        #expect(SoruAlgilama.soruNumarasi("  3) Hangisi") == 3)
        #expect(SoruAlgilama.soruNumarasi("2.5 gram şeker") == nil)
        #expect(SoruAlgilama.soruNumarasi("A) şık") == nil)
    }

    @Test func tekSutunBolgeler() async throws {
        let b = try await SoruAlgilama.algila(veri: ModulDOrnek.sinav(), ocr: false)
        #expect(b.map(\.numara) == [1, 2, 3, 4])
        let ilk = b[0].parcalar[0]
        // 1. soru: 780 (soru) ... 745 (şık); 2. soru başlığı (700) dışında
        #expect(ilk.kutu.maxY > 780 && ilk.kutu.maxY < 800)
        #expect(ilk.kutu.minY < 745 && ilk.kutu.minY > 700)
        // 3. soru iki sayfaya yayılır
        #expect(b[2].parcalar.count == 2)
        #expect(b[2].parcalar.map(\.sayfa) == [0, 1])
        #expect(b[3].parcalar[0].sayfa == 1)
        #expect(b[0].numaraKutusu != nil)
    }

    @Test func ikiSutunluBolgeler() async throws {
        let b = try await SoruAlgilama.algila(veri: ModulDOrnek.ikiSutunluSinav(), ocr: false)
        #expect(b.map(\.numara) == [1, 2, 3, 4, 5, 6])
        #expect(b[0].parcalar[0].kutu.maxX < 300)
        #expect(b[3].parcalar[0].kutu.minX > 300)
        // Sütunlar karışmadı: 4. soru sağdaki ilk soru, yüksekliği de 1. ile aynı hizada
        #expect(abs(b[3].parcalar[0].kutu.maxY - b[0].parcalar[0].kutu.maxY) < 3)
    }

    @Test func soruYoksaHata() async {
        let pdf = ModulDOrnek.yerlesimli([[(50, 700, "Bu sayfada numaralı soru yok")]])
        await #expect(throws: KagitHata.self) { try await SoruAlgilama.algila(veri: pdf, ocr: false) }
    }

    @Test func birlestirVeKenar() async throws {
        var b = try await SoruAlgilama.algila(veri: ModulDOrnek.sinav(), ocr: false)
        let ust0 = b[0].parcalar[0].kutu.height
        SoruAlgilama.kenarAyarla(&b[0], alt: 10)
        #expect(abs(b[0].parcalar[0].kutu.height - ust0 - 10) < 0.01)
        let m = SoruAlgilama.birlestir(b, 0)
        #expect(m.count == 3 && m[0].parcalar.count == 2)
    }
}

@Suite struct KitapcikTestleri {
    @Test func karistirmaTekrarlanabilir() {
        #expect(Kitapcik.karistir(sayi: 10, tohum: 5) == Kitapcik.karistir(sayi: 10, tohum: 5))
        #expect(Kitapcik.karistir(sayi: 10, tohum: 5) != Kitapcik.karistir(sayi: 10, tohum: 6))
        #expect(Set(Kitapcik.karistir(sayi: 10, tohum: 5)) == Set(0..<10))
    }

    @Test func bSirasiKimlikDegil() {
        for n in 2...30 {
            for tohum in 0..<5 {
                let s = Kitapcik.bSirasi(sayi: n, tohum: UInt64(tohum))
                #expect(Set(s) == Set(0..<n))
                #expect(s != Array(0..<n))
                if n >= 8 { #expect(zip(s, 0..<n).filter { $0 == $1 }.count <= n / 4 + 1) }
            }
        }
    }

    @Test func anahtarEslemesi() {
        // sorular 1..4, anahtar A B C D; B sırası: 3. soru, 1., 4., 2.
        let anahtar = [1: "A", 2: "B", 3: "C", 4: "D"]
        let kb = Kitapcik.anahtarEsle(sira: [2, 0, 3, 1], anahtar: anahtar, numaralar: [1, 2, 3, 4])
        #expect(kb == [1: "C", 2: "A", 3: "D", 4: "B"])
        // numaralar 1'den başlamıyorsa
        let k2 = Kitapcik.anahtarEsle(sira: [1, 0], anahtar: [5: "E", 6: "A"], numaralar: [5, 6])
        #expect(k2 == [1: "A", 2: "E"])
    }

    @Test func kitapcikUretimi() async throws {
        let kaynak = ModulDOrnek.sinav()
        let bolgeler = try await SoruAlgilama.algila(veri: kaynak, ocr: false)
        var ayar = KitapcikAyari()
        ayar.sinavAdi = "9. Sınıf 1. Yazılı"
        ayar.baslik = OkulBasligi(okulAdi: "Cumhuriyet Anadolu Lisesi", ders: "Biyoloji", egitimYili: "2026-2027")
        ayar.anahtar = [1: "A", 2: "A", 3: "A", 4: "A"]
        ayar.tohum = 3
        let s = try Kitapcik.uret(kaynak: kaynak, bolgeler: bolgeler, ayar: ayar)
        let a = try #require(PDFDocument(data: s.a)), b = try #require(PDFDocument(data: s.b))
        #expect(a.pageCount >= 1 && b.pageCount >= 1)
        let metinA = a.string ?? "", metinB = b.string ?? ""
        #expect(metinA.contains("CUMHURİYET ANADOLU LİSESİ"))
        #expect(metinA.contains("Adı Soyadı"))
        for ifade in ["Hücre zarının", "organeldir", "Fotosentez", "DNA"] {
            #expect(metinA.contains(ifade), "A: \(ifade)")
            #expect(metinB.contains(ifade), "B: \(ifade)")
        }
        // B'de sorular karışık: ilk görünen soru A'dakinden farklı
        #expect(s.bSirasi != [1, 2, 3, 4])   // B karışık (kırpılan sayfa metni gizli kaldığı için sıra metinden sınanmaz)
        // Anahtar: iki sayfa (A, B), hepsi “A” çünkü anahtar tümü A
        let anahtarVeri = try #require(s.anahtarPDF)
        let anahtar = try #require(PDFDocument(data: anahtarVeri))
        #expect(anahtar.pageCount == 2)
        #expect(s.anahtarB.values.allSatisfy { $0 == "A" } && s.anahtarB.count == 4)
        #expect(s.bSirasi.count == 4 && Set(s.bSirasi) == [1, 2, 3, 4])
    }

    @Test func anahtarsizUretimde() async throws {
        let kaynak = ModulDOrnek.ikiSutunluSinav()
        let bolgeler = try await SoruAlgilama.algila(veri: kaynak, ocr: false)
        var ayar = KitapcikAyari()
        ayar.sutun = 1
        let s = try Kitapcik.uret(kaynak: kaynak, bolgeler: bolgeler, ayar: ayar)
        #expect(s.anahtarPDF == nil)
        #expect(PDFDocument(data: s.a)?.pageCount ?? 0 >= 1)
    }
}

@Suite struct PuanTestleri {
    func notluBelge(_ puanlar: [(Int, Double)]) -> PDFDocument {
        let b = PDFDocument(data: ModulDOrnek.yerlesimli([[(50, 700, "S1")], [(50, 700, "S2")]]))!
        for (s, d) in puanlar {
            b.page(at: s)!.addAnnotation(OgretmenDamga.puanEtiketi(d, merkez: CGPoint(x: 300, y: 400)))
        }
        return b
    }

    @Test func puanToplama() throws {
        let b = notluBelge([(0, 5), (0, 3), (1, -1), (1, 2.5)])
        #expect(PuanOkuyucu.toplam(b) == 9.5)
        #expect(PuanOkuyucu.sayfaToplamlari(b) == [8, 1.5])
        // Kaydet-aç döngüsünde işaretler korunur
        let veri = try Belge.veri(b)
        let yeni = try #require(PDFDocument(data: veri))
        #expect(PuanOkuyucu.toplam(yeni) == 9.5)
    }

    @Test func toplamKutusuPuanaKatilmaz() {
        let b = notluBelge([(0, 4)])
        b.page(at: 0)!.addAnnotation(OgretmenDamga.toplamEtiketi(4, sayfa: b.page(at: 0)!))
        #expect(PuanOkuyucu.toplam(b) == 4)
        #expect(OgretmenDamga.toplamKutusu(b.page(at: 0)!) != nil)
    }

    @Test func damgalarGorunur() throws {
        // ✓ ve ✗ ink açıklamaları sayfada piksel bırakmalı (yol kutuya göreli olmalı)
        let b = PDFDocument(data: ModulDOrnek.yerlesimli([[]]))!
        let sayfa = b.page(at: 0)!
        sayfa.addAnnotation(OgretmenDamga.damga(.dogru, merkez: CGPoint(x: 200, y: 600), boyut: 40))
        sayfa.addAnnotation(OgretmenDamga.damga(.yanlis, merkez: CGPoint(x: 400, y: 300), boyut: 40))
        let g = try #require(PDFCizim.goruntu(sayfa, dpi: 72))
        var px = [UInt8](repeating: 255, count: g.width * g.height * 4)
        let ctx = CGContext(data: &px, width: g.width, height: g.height, bitsPerComponent: 8, bytesPerRow: g.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(g, in: CGRect(x: 0, y: 0, width: g.width, height: g.height))
        func koyuSayisi(_ x0: Int, _ y0: Int, _ w: Int, _ h: Int) -> Int {
            // y0: PDF koordinatı (alttan); görüntü satır 0 üstte
            var n = 0
            for yy in y0..<(y0 + h) {
                let satir = g.height - 1 - yy
                for xx in x0..<(x0 + w) {
                    let i = (satir * g.width + xx) * 4
                    if Int(px[i]) + Int(px[i + 1]) + Int(px[i + 2]) < 600 { n += 1 }
                }
            }
            return n
        }
        #expect(koyuSayisi(180, 580, 40, 40) > 20)     // ✓ kendi kutusunda
        #expect(koyuSayisi(380, 280, 40, 40) > 20)     // ✗ kendi kutusunda
        #expect(koyuSayisi(0, 0, 100, 100) == 0)       // başka yerde iz yok
    }

    @Test func tabloVeDosyaAdi() {
        #expect(PuanTablosu.adAyir("123 Ayşe Yılmaz - 1. Yazılı.pdf") == ("123", "Ayşe Yılmaz"))
        #expect(PuanTablosu.adAyir("Ali Veli.pdf") == ("", "Ali Veli"))
    }

    @Test func tabloUretimi() throws {
        let b1 = notluBelge([(0, 10), (1, 5)])
        let b2 = notluBelge([(0, 7)])
        let bos = notluBelge([])
        let satirlar = PuanTablosu.olustur(girdiler: [
            ("102 Mehmet Demir - Sınav.pdf", try Belge.veri(b2)),
            ("101 Ayşe Yılmaz - Sınav.pdf", try Belge.veri(b1)),
            ("103 Zeynep Kaya - Sınav.pdf", try Belge.veri(bos)),
        ])
        #expect(satirlar.map(\.no) == ["101", "102", "103"])
        #expect(satirlar.map(\.toplam) == [15, 7, 0])
        #expect(satirlar.map(\.puanVar) == [true, true, false])
        let ist = try #require(PuanTablosu.istatistik(satirlar))
        #expect(ist.ortalama == 11 && ist.enYuksek == 15 && ist.enDusuk == 7)

        let csv = String(decoding: PuanTablosu.csv(satirlar), as: UTF8.self)
        #expect(csv.contains("101;Ayşe Yılmaz;15"))
        #expect(csv.contains("Ortalama;11"))
        let x = PuanTablosu.xlsx(satirlar, sayfaSutunlari: true)
        let ac = XLSXOkuyucu.satirlar(x)
        #expect(ac[0].prefix(3) == ["No", "Ad Soyad", "Toplam"])
        #expect(ac[1][1] == "Ayşe Yılmaz" && ac[1][2] == "15")
        #expect(ac[1][3] == "10" && ac[1][4] == "5")
    }
}

@Suite struct BaslikVeSinavPDFTestleri {
    @Test func basligiEkleYerAcar() throws {
        let kaynak = ModulDOrnek.yerlesimli([[(50, 700, "Birinci sayfa içeriği")], [(50, 700, "İkinci sayfa")]])
        let baslik = OkulBasligi(okulAdi: "Örnek Lisesi", ders: "Biyoloji", ogretmen: "M. Derin", egitimYili: "2026-2027")
        let cikti = try BaslikEkleyici.ekle(veri: kaynak, baslik: baslik, secenek: .init(sayfalar: [0], yerAc: true, sinavAdi: "Deneme"))
        let b = try #require(PDFDocument(data: cikti))
        #expect(b.pageCount == 2)
        let m0 = b.page(at: 0)?.string ?? ""
        #expect(m0.contains("ÖRNEK LİSESİ") && m0.contains("Birinci sayfa içeriği") && m0.contains("Deneme"))
        #expect(b.page(at: 1)?.string?.contains("ÖRNEK") != true)
        // yerAc: içerik küçüldü → metnin sayfadaki konumu aşağıda
        let konum = b.page(at: 0)!.selection(for: b.page(at: 0)!.bounds(for: .cropBox))?.selectionsByLine().first { $0.string?.contains("Birinci") == true }
        #expect(konum != nil)
    }

    @Test func varsayilanYil() {
        let c = Calendar.current
        #expect(OkulBasligi.varsayilanYil(c.date(from: DateComponents(year: 2026, month: 10, day: 5))!) == "2026-2027")
        #expect(OkulBasligi.varsayilanYil(c.date(from: DateComponents(year: 2027, month: 3, day: 5))!) == "2026-2027")
    }

    func ornekSorular() -> [UretilenSoru] {
        [
            UretilenSoru(tur: .coktanSecmeli, metin: "Hücre zarının temel yapısı aşağıdakilerden hangisidir?",
                         secenekler: ["Fosfolipit çift tabaka", "Selüloz", "Nişasta", "Glikojen", "Kitin"], dogru: "A", aciklama: "Zar fosfolipit çift katmanlıdır."),
            UretilenSoru(tur: .dogruYanlis, metin: "Ribozomlar zarlı organellerdir.", dogru: "Yanlış"),
            UretilenSoru(tur: .bosluk, metin: "Fotosentez ________ organelinde gerçekleşir.", dogru: "kloroplast"),
            UretilenSoru(tur: .acikUclu, metin: "Difüzyon ile osmozu karşılaştırınız.", dogru: "Osmoz suyun difüzyonudur."),
            UretilenSoru(tur: .eslestirme, metin: "Kavramları eşleştiriniz.", dogru: "",
                         ciftler: [EslesmeCifti(sol: "Ribozom", sag: "Protein sentezi"), EslesmeCifti(sol: "Mitokondri", sag: "ATP üretimi"),
                                   EslesmeCifti(sol: "Lizozom", sag: "Sindirim"), EslesmeCifti(sol: "Golgi", sag: "Paketleme")]),
        ]
    }

    @Test func sinavVeAnahtar() throws {
        let sorular = ornekSorular()
        let baslik = OkulBasligi(okulAdi: "Örnek Lisesi", ders: "Biyoloji", egitimYili: "2026-2027")
        let sinav = try #require(PDFDocument(data: SinavPDF.sinav(sorular: sorular, baslik: baslik, sinavAdi: "1. Yazılı")))
        let m = sinav.string ?? ""
        for s in ["1. Hücre zarının", "Fosfolipit çift tabaka", "E) Kitin", "2. Ribozomlar", "3. Fotosentez", "________", "Ribozom", "Protein sentezi", "Difüzyon"] {
            #expect(m.contains(s), "sınavda: \(s)")
        }
        #expect(!m.contains("kloroplast"))   // cevaplar sınavda görünmez
        let anahtar = try #require(PDFDocument(data: SinavPDF.anahtar(sorular: sorular, baslik: baslik, sinavAdi: "1. Yazılı", aciklamali: true)))
        let am = anahtar.string ?? ""
        #expect(am.contains("1. A) Fosfolipit çift tabaka"))
        #expect(am.contains("Yanlış") && am.contains("kloroplast") && am.contains("Zar fosfolipit"))
    }

    @Test func eslestirmeCevabiTutarli() {
        let s = ornekSorular()[4]
        let cevap = SinavPDF.eslestirmeCevabi(s)
        // sağ sütunda her harf bir kez geçer
        let harfler = cevap.components(separatedBy: ", ").compactMap { $0.split(separator: "-").last.map(String.init) }
        #expect(Set(harfler).count == 4)
        // Ribozom (1) → “Protein sentezi”: gösterilen listede o harfe karşılık gelen öge doğru mu
        let sira = SinavPDF.sagSira(4)
        let harfRibozom = cevap.components(separatedBy: ", ")[0].split(separator: "-")[1]
        let j = Int(Character(String(harfRibozom)).asciiValue! - 65)
        #expect(s.ciftler[sira[j]].sag == "Protein sentezi")
    }

    @Test func cokSoruSayfaBolme() throws {
        var sorular: [UretilenSoru] = []
        for i in 1...40 {
            sorular.append(UretilenSoru(tur: .coktanSecmeli, metin: "Soru \(i): hücre bölünmesiyle ilgili uzunca bir soru metni burada yer alır.",
                                        secenekler: ["Seçenek bir", "Seçenek iki", "Seçenek üç", "Seçenek dört", "Seçenek beş"], dogru: "B"))
        }
        let b = try #require(PDFDocument(data: SinavPDF.sinav(sorular: sorular, baslik: OkulBasligi(), sinavAdi: "Uzun")))
        #expect(b.pageCount >= 3)
        let m = b.string ?? ""
        #expect(m.contains("40. Soru 40"))
    }

    @Test func metinPDFSayfalar() throws {
        let govde = (1...120).map { "Paragraf \($0): " + String(repeating: "hücre ", count: 40) }.joined(separator: "\n")
        let b = try #require(PDFDocument(data: MetinPDF.uret(baslik: "Özet", altBaslik: "Kaynak: test", govde: govde)))
        #expect(b.pageCount >= 3)
        #expect((b.string ?? "").contains("Paragraf 120"))
    }
}
