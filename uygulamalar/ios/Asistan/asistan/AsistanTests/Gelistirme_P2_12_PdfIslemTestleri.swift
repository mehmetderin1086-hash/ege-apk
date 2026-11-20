import Foundation
import Testing
import PDFKit
import PencilKit
import UIKit
import FoundationModels
@testable import Asistan

/// P2.12: pdfIslem aracı ve PdfIslemci (ağsız; örnek PDF'ler UIGraphicsPDFRenderer ile bellekte üretilir).
@Suite("P2.12 PDF iş akışı") @MainActor
struct Gelistirme_P2_12_PdfIslemTestleri {

    // MARK: Yardımcılar

    /// Her sayfada "Sayfa N" ve yeterince uzun metin (OCR'a düşmesin).
    /// `isaret`: sol üst çeyrekte büyük siyah dikdörtgen (yön karşılaştırması için).
    private func ornekPdf(_ sayfa: Int, boyut: CGSize = CGSize(width: 595, height: 842), isaret: Bool = false) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: boyut)).pdfData { c in
            for i in 1...max(1, sayfa) {
                c.beginPage()
                if isaret { UIColor.black.setFill(); c.fill(CGRect(x: 40, y: 120, width: 220, height: 300)) }
                ("Sayfa \(i) — bu sayfada okunacak kadar uzun bir örnek metin bulunuyor." as NSString)
                    .draw(at: CGPoint(x: 40, y: 60), withAttributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.black])
            }
        }
    }

    private func geciciDosya(_ veri: Data, uzanti: String = "pdf") throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("p212-\(UUID().uuidString).\(uzanti)")
        try veri.write(to: u)
        return u
    }

    private func belge(_ sayfa: Int) throws -> PDFDocument { try #require(PDFDocument(data: ornekPdf(sayfa))) }

    /// Bellekte imza: saydam zeminde kırmızı dikdörtgen.
    private func imzaGorseli() -> CGImage {
        let bicim = UIGraphicsImageRendererFormat(); bicim.scale = 1; bicim.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 200, height: 80), format: bicim).image { c in
            UIColor.red.setFill(); c.fill(CGRect(x: 10, y: 10, width: 180, height: 60))
        }.cgImage!
    }

    /// Gürültülü görselli tek sayfalık PDF (sıkıştırma testleri).
    /// 2000 px gürültü küçük sayfaya çizilir: 150 dpi rasterleştirme belirgin küçültür (Catalyst'te ölçüldü: 12 MB → ~1 MB).
    private func gurultuluPdf(_ n: Int = 2000) -> Data {
        var t: UInt64 = 12345
        let c = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let p = c.data!.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(n * n * 4) { t = t &* 6364136223846793005 &+ 1442695040888963407; p[i] = UInt8(truncatingIfNeeded: t >> 33) }
        let resim = UIImage(cgImage: c.makeImage()!)
        return UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)).pdfData { c in
            c.beginPage(); resim.draw(in: CGRect(x: 20, y: 20, width: 555, height: 800))
        }
    }

    /// Görüntüyü gri ızgarada koyu/açık örüntüye çevirir (yön karşılaştırması için).
    private func oruntu(_ g: CGImage, adim: Int = 12) -> [Bool] {
        let w = 120, h = 120
        let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        c.setFillColor(gray: 1, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
        c.draw(g, in: CGRect(x: 0, y: 0, width: w, height: h))
        let p = c.data!.assumingMemoryBound(to: UInt8.self)
        var o: [Bool] = []
        for y in stride(from: adim / 2, to: h, by: adim) { for x in stride(from: adim / 2, to: w, by: adim) { o.append(p[y * c.bytesPerRow + x] < 128) } }
        return o
    }

    // MARK: (a) aralıklar

    @Test func araliklarCozulur() throws {
        #expect(try PdfIslemci.araliklar("1-3,5", sayfaSayisi: 10) == [[0, 1, 2, 4]])
        #expect(try PdfIslemci.araliklar("1-2;4", sayfaSayisi: 10) == [[0, 1], [3]])
        #expect(try PdfIslemci.araliklar(" 2 – 3 ", sayfaSayisi: 3) == [[1, 2]])
        #expect(throws: PdfIslemci.Hata.self) { try PdfIslemci.araliklar("3-1", sayfaSayisi: 10) }
        #expect(throws: PdfIslemci.Hata.self) { try PdfIslemci.araliklar("0", sayfaSayisi: 10) }
        #expect(throws: PdfIslemci.Hata.self) { try PdfIslemci.araliklar("11", sayfaSayisi: 10) }
        #expect(throws: PdfIslemci.Hata.self) { try PdfIslemci.araliklar("", sayfaSayisi: 10) }
        #expect(throws: PdfIslemci.Hata.self) { try PdfIslemci.araliklar("1-2;", sayfaSayisi: 10) }
        #expect(throws: PdfIslemci.Hata.self) { try PdfIslemci.araliklar("a-b", sayfaSayisi: 10) }
    }

    // MARK: (b) birleştir

    @Test func birlestirSayfalariToplarVeGorseliA4Yapar() throws {
        let a = try geciciDosya(ornekPdf(2)), b = try geciciDosya(ornekPdf(3))
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        #expect(try PdfIslemci.birlestir([.pdf(a), .pdf(b)]).pageCount == 5)

        let png = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).image { c in UIColor.blue.setFill(); c.fill(CGRect(x: 0, y: 0, width: 400, height: 300)) }.pngData()!
        let g = try geciciDosya(png, uzanti: "png")
        defer { try? FileManager.default.removeItem(at: g) }
        let d = try PdfIslemci.birlestir([.pdf(a), .gorsel(g)])
        #expect(d.pageCount == 3)
        let s = try #require(d.page(at: 2)).bounds(for: .mediaBox)
        #expect(abs(s.width - 595) < 1 && abs(s.height - 842) < 1)
    }

    @Test func birlestir300SayfayiAsamaz() throws {
        let u = try geciciDosya(ornekPdf(301, boyut: CGSize(width: 100, height: 100)))
        defer { try? FileManager.default.removeItem(at: u) }
        #expect(throws: PdfIslemci.Hata.cokSayfa) { try PdfIslemci.birlestir([.pdf(u)]) }
    }

    // MARK: (c) böl

    @Test func bolGruplaraAyirir() throws {
        let d = try belge(5)
        let parcalar = PdfIslemci.bol(d, gruplar: [[0, 1], [4]])
        #expect(parcalar.map(\.pageCount) == [2, 1])
        #expect(parcalar[0].page(at: 1)?.string?.contains("Sayfa 2") == true)
        #expect(parcalar[1].page(at: 0)?.string?.contains("Sayfa 5") == true)
    }

    // MARK: (d) döndür

    @Test func dondurAciyiBirikirir() throws {
        let d = try belge(2)
        try PdfIslemci.dondur(d, sayfalar: [0], derece: 90)
        #expect(d.page(at: 0)?.rotation == 90 && d.page(at: 1)?.rotation == 0)
        try PdfIslemci.dondur(d, sayfalar: nil, derece: 270)
        try PdfIslemci.dondur(d, sayfalar: nil, derece: 180)
        #expect(d.page(at: 1)?.rotation == 90)
        try PdfIslemci.dondur(d, sayfalar: [1], derece: -90)
        #expect(d.page(at: 1)?.rotation == 0)
        #expect(throws: PdfIslemci.Hata.derece) { try PdfIslemci.dondur(d, sayfalar: nil, derece: 45) }
    }

    // MARK: (e) parola

    @Test func parolaliPdfAcilmaz() throws {
        let d = try belge(1)
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("p212-parola-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: u) }
        #expect(d.write(to: u, withOptions: [.userPasswordOption: "x", .ownerPasswordOption: "y"]))
        #expect(throws: PdfIslemci.Hata.parolali) { try PdfIslemci.ac(u) }
    }

    // MARK: (f) sıkıştır

    @Test func sikistirKucultur() throws {
        let veri = gurultuluPdf()
        let u = try geciciDosya(veri)
        defer { try? FileManager.default.removeItem(at: u) }
        let (kucuk, _) = try PdfIslemci.sikistir(u, hedefMB: nil)
        #expect(kucuk.count < veri.count)
        #expect(PDFDocument(data: kucuk)?.pageCount == 1)
        // Ulaşılamaz hedef: rasterleştirme yolu denenir, not boş kalmaz.
        let (_, not) = try PdfIslemci.sikistir(u, hedefMB: 0.001)
        #expect(!not.isEmpty)
    }

    @Test func rasterlestirmeMetinKatmaniniSiler() throws {
        let d = try belge(2)
        let v = try #require(PdfIslemci.rasterlestir(d, kalite: 0.45))
        let r = try #require(PDFDocument(data: v))
        #expect(r.pageCount == 2)
        let kalanMetin = (r.page(at: 0)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(kalanMetin.isEmpty)
        let gurultuVerisi = gurultuluPdf()
        let gurultu = try #require(PDFDocument(data: gurultuVerisi))
        let rv = try #require(PdfIslemci.rasterlestir(gurultu, kalite: 0.3))
        #expect(rv.count < gurultuVerisi.count)
    }

    // MARK: (g) form

    @Test func formAlanlariListelenirVeDoldurulur() throws {
        let d = try belge(1)
        let p = try #require(d.page(at: 0))
        let metin = PDFAnnotation(bounds: CGRect(x: 40, y: 600, width: 200, height: 24), forType: .widget, withProperties: nil)
        metin.widgetFieldType = .text; metin.fieldName = "ad"
        let kutu = PDFAnnotation(bounds: CGRect(x: 40, y: 560, width: 18, height: 18), forType: .widget, withProperties: nil)
        kutu.widgetFieldType = .button; kutu.widgetControlType = .checkBoxControl; kutu.fieldName = "onay"
        p.addAnnotation(metin); p.addAnnotation(kutu)

        let alanlar = PdfIslemci.alanlar(d)
        #expect(Set(alanlar.map(\.ad)) == ["ad", "onay"])
        #expect(alanlar.first { $0.ad == "ad" }?.tur == "metin")
        #expect(alanlar.first { $0.ad == "onay" }?.tur == "onay kutusu")

        let (dolan, bulunamayan) = PdfIslemci.doldur(d, ["AD": "Ali Veli", "onay": "evet", "yok": "x"])
        #expect(dolan == 2)
        #expect(bulunamayan == ["yok"])
        #expect(metin.widgetStringValue == "Ali Veli")
        #expect(kutu.buttonWidgetState == .onState)
        _ = PdfIslemci.doldur(d, ["onay": "hayır"])
        #expect(kutu.buttonWidgetState == .offState)
        #expect(PdfIslemci.alanlar(try belge(1)).isEmpty)
    }

    @Test func degerlerJSONDuzNesne() {
        #expect(PdfAraci.degerler(#"{"ad":"Ali","yas":17,"onay":true}"#) == ["ad": "Ali", "yas": "17", "onay": "evet"])
        #expect(PdfAraci.degerler("[1,2]") == nil)
        #expect(PdfAraci.degerler(nil) == nil)
    }

    // MARK: (h) imza çerçevesi

    @Test func cerceveSayfaIcindeVeKenarPayli() {
        let sayfa = CGRect(x: 0, y: 0, width: 595, height: 842)
        let r = PdfIslemci.cerceve(.sagAlt, sayfa: sayfa, imza: CGSize(width: 200, height: 80))
        #expect(sayfa.contains(r))
        #expect(abs(sayfa.maxX - r.maxX - 36) < 0.01 && abs(sayfa.maxY - r.maxY - 36) < 0.01)
        #expect(abs(r.width - 140) < 0.01 && abs(r.height - 56) < 0.01)
        for k in PdfIslemci.ImzaKonumu.allCases { #expect(sayfa.contains(PdfIslemci.cerceve(k, sayfa: sayfa, imza: CGSize(width: 10, height: 400)))) }
        let ust = PdfIslemci.cerceve(.sagUst, sayfa: sayfa, imza: CGSize(width: 200, height: 80))
        #expect(abs(ust.minY - 36) < 0.01)
    }

    @Test func imzaKonumuCozulur() {
        #expect(PdfIslemci.ImzaKonumu.coz("sağ alt") == .sagAlt)
        #expect(PdfIslemci.ImzaKonumu.coz("sol_alt") == .solAlt)
        #expect(PdfIslemci.ImzaKonumu.coz("ortaAlt") == .ortaAlt)
        #expect(PdfIslemci.ImzaKonumu.coz("Sağ Üst") == .sagUst)
        #expect(PdfIslemci.ImzaKonumu.coz(nil) == .sagAlt)
    }

    // MARK: (i) imzala

    @Test func imzalaSayfaSayisiniKorurVeYonuBozmaz() throws {
        let d = try #require(PDFDocument(data: ornekPdf(3, isaret: true)))
        // Döndürülmüş sayfa yeniden çizilirken yönü korunmalı.
        try PdfIslemci.dondur(d, sayfalar: [0], derece: 90)
        let once = try #require(d.page(at: 0)).thumbnail(of: CGSize(width: 300, height: 300), for: .mediaBox).cgImage!
        let v = try PdfIslemci.imzala(d, imza: imzaGorseli(), sayfa: 2, konum: .sagAlt)
        let r = try #require(PDFDocument(data: v))
        #expect(r.pageCount == 3)
        let ilk = try #require(r.page(at: 0))
        let b = PdfIslemci.gorunenBoyut(ilk)
        #expect(abs(b.width - 842) < 1 && abs(b.height - 595) < 1)
        let sonra = ilk.thumbnail(of: CGSize(width: 300, height: 300), for: .mediaBox).cgImage!
        let a1 = oruntu(once), a2 = oruntu(sonra)
        let fark = zip(a1, a2).filter { $0 != $1 }.count
        #expect(fark <= 3, "döndürülmüş sayfa yeniden çizilince değişti: \(fark) fark")
        // Vektör metin korunur.
        #expect(r.page(at: 1)?.string?.contains("Sayfa 2") == true)
        #expect(PdfIslemci.onizleme(v, sayfa: 2) != nil)
        #expect(throws: PdfIslemci.Hata.self) { try PdfIslemci.imzala(d, imza: imzaGorseli(), sayfa: 3, konum: .sagAlt) }
    }

    // MARK: (j) kaynak çözümü

    @Test func kaynakKimlikleriCozulurVeKacisReddedilir() throws {
        let klasor = FileManager.default.temporaryDirectory.appendingPathComponent("p212-indir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: klasor) }
        try ornekPdf(1).write(to: klasor.appendingPathComponent("abc.pdf"))
        var k = IndirmeKaydi(adres: "https://local.invalid/abc.pdf", tur: "file", ad: "abc.pdf"); k.durum = "done"; k.dosya = "abc.pdf"
        var kacis = IndirmeKaydi(adres: "https://local.invalid/x", tur: "file"); kacis.dosya = "../abc.pdf"

        let c1 = try PdfKaynaklari.coz("indirme:\(k.id.uuidString)", indirmeler: [k, kacis], indirmeKlasoru: klasor)
        #expect(c1 == [.pdf(klasor.appendingPathComponent("abc.pdf").standardizedFileURL)])
        let c2 = try PdfKaynaklari.coz(liste: "\(k.id.uuidString), indirme:\(k.id.uuidString)", indirmeler: [k], indirmeKlasoru: klasor)
        #expect(c2.count == 2)

        #expect(throws: PdfKaynaklari.Hata.klasorDisi("indirme:\(kacis.id.uuidString)")) {
            try PdfKaynaklari.coz("indirme:\(kacis.id.uuidString)", indirmeler: [k, kacis], indirmeKlasoru: klasor)
        }
        #expect(throws: PdfKaynaklari.Hata.self) { try PdfKaynaklari.coz("indirme:\(UUID().uuidString)", indirmeler: [k], indirmeKlasoru: klasor) }
        #expect(throws: PdfKaynaklari.Hata.self) { try PdfKaynaklari.coz("ek:../../etc/passwd", indirmeler: [], indirmeKlasoru: klasor) }
        #expect(throws: PdfKaynaklari.Hata.self) { try PdfKaynaklari.coz("ek:\(UUID().uuidString)", indirmeler: [], indirmeKlasoru: klasor) }
        #expect(throws: PdfKaynaklari.Hata.bos) { try PdfKaynaklari.coz(liste: " , ", indirmeler: [], indirmeKlasoru: klasor) }
        #expect(PdfKaynaklari.gorunenAd(URL(fileURLWithPath: "/x/\(UUID().uuidString)-Ödev.pdf")) == "Ödev")
    }

    // MARK: (k) araç: imza onaysız dosya oluşturmaz

    @Test func imzaOnaylanmazsaDosyaOlusmaz() async throws {
        let kimlik = UUID().uuidString
        try FileManager.default.createDirectory(at: BelgeOkuyucu.ekKlasoru, withIntermediateDirectories: true)
        let ek = BelgeOkuyucu.ekKlasoru.appendingPathComponent("\(kimlik)-Dilekce.pdf")
        try ornekPdf(2).write(to: ek)
        defer { try? FileManager.default.removeItem(at: ek) }

        let onay = OnayKapisi(zorunluOtomatikKararaUyar: true); onay.otomatikKarar = false
        let gorsel = imzaGorseli()
        let arac = PdfAraci(onay: onay, imzaSaglayici: { gorsel })
        let kayitSayisi = IndirmeYoneticisi.ortak.kayitlar.count
        let dosyaSayisi = (try? FileManager.default.contentsOfDirectory(atPath: IndirmeYoneticisi.klasor.path).count) ?? 0
        let sonuc = try await arac.call(arguments: .init(islem: "imzala", kaynaklar: "ek:\(kimlik)", sayfalar: "2", konum: "sağ alt"))
        #expect(sonuc.contains("onaylamadı"))
        #expect(IndirmeYoneticisi.ortak.kayitlar.count == kayitSayisi)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: IndirmeYoneticisi.klasor.path).count) ?? 0) == dosyaSayisi)

        let imzasiz = PdfAraci(onay: onay, imzaSaglayici: { nil })
        let s2 = try await imzasiz.call(arguments: .init(islem: "imzala", kaynaklar: "ek:\(kimlik)"))
        #expect(s2.contains("İmzam"))
        let s3 = try await arac.call(arguments: .init(islem: "uydur", kaynaklar: "ek:\(kimlik)"))
        #expect(s3.contains("İşlem geçersiz"))
        let s4 = try await arac.call(arguments: .init(islem: "bilgi", kaynaklar: "ek:\(kimlik)"))
        #expect(s4.contains("2 sayfa"))
        let s5 = try await arac.call(arguments: .init(islem: "bol", kaynaklar: "indirme:\(UUID().uuidString)", sayfalar: "1"))
        #expect(s5.contains("listele"))
    }

    // MARK: (l) ek kopyası

    @Test func belgeOkuyucuEkKopyasiYaratir() throws {
        let u = try geciciDosya(ornekPdf(1))
        defer { try? FileManager.default.removeItem(at: u) }
        let o = try BelgeOkuyucu.oku(u, ekKopyasi: true)
        let kimlik = try #require(o.ekKimligi)
        #expect(kimlik.hasPrefix("ek:"))
        #expect(o.not.contains(kimlik))
        let kopya = try #require(BelgeOkuyucu.ekDosyasi(String(kimlik.dropFirst(3))))
        defer { try? FileManager.default.removeItem(at: kopya) }
        #expect(FileManager.default.fileExists(atPath: kopya.path))
        #expect(try PdfKaynaklari.coz(kimlik, indirmeler: []) == [.pdf(kopya)])
        // Var olan çağrı biçimi kopya yaratmaz.
        #expect(try BelgeOkuyucu.oku(u).ekKimligi == nil)
    }

    @Test func eskiEkKopyalariBudanir() throws {
        try FileManager.default.createDirectory(at: BelgeOkuyucu.ekKlasoru, withIntermediateDirectories: true)
        let eski = BelgeOkuyucu.ekKlasoru.appendingPathComponent("\(UUID().uuidString)-eski.pdf")
        let yeni = BelgeOkuyucu.ekKlasoru.appendingPathComponent("\(UUID().uuidString)-yeni.pdf")
        try Data("x".utf8).write(to: eski); try Data("y".utf8).write(to: yeni)
        defer { try? FileManager.default.removeItem(at: eski); try? FileManager.default.removeItem(at: yeni) }
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-8 * 86_400)], ofItemAtPath: eski.path)
        BelgeOkuyucu.eskiEkleriBuda(gun: 7)
        #expect(!FileManager.default.fileExists(atPath: eski.path))
        #expect(FileManager.default.fileExists(atPath: yeni.path))
    }

    // MARK: (m) şema ve kayıt

    @Test func aracSemasiDuz() throws {
        let a = PdfAraci(onay: OnayKapisi())
        #expect(a.name == "pdfIslem")
        let s = String(decoding: try JSONEncoder().encode(a.parameters), as: UTF8.self)
        #expect(!s.contains("$ref") && !s.contains("$defs"))
        let arg = try PdfAraci.Arguments(try GeneratedContent(json: #"{"islem":"bilgi","kaynaklar":"gorsel:son"}"#))
        #expect(arg.islem == "bilgi" && arg.sayfalar == nil && arg.hedefMB == nil)
        #expect(AjanDefteri.butceMuaf.contains("pdfIslem"))
    }

    // MARK: Onay kapısı önizlemesi ve imza deposu

    @Test func onayIstegiOnizlemeyiTasir() async throws {
        let onay = OnayKapisi(zorunluOtomatikKararaUyar: false)
        let url = URL(fileURLWithPath: "/tmp/onizleme.png")
        let gorev = Task { await onay.iste(baslik: "İmza eklensin mi?", ayrinti: "x", zorunlu: true, onizleme: url) }
        for _ in 0..<200 where onay.bekleyen == nil { try await Task.sleep(for: .milliseconds(10)) }
        let istek = try #require(onay.bekleyen)
        #expect(istek.onizleme == url)
        onay.yanitla(true, id: istek.id)
        #expect(await gorev.value)
    }

    @Test func imzaDeposuGeciciDosyayla() throws {
        let dosya = FileManager.default.temporaryDirectory.appendingPathComponent("p212-imza-\(UUID().uuidString)/imza.png")
        defer { try? FileManager.default.removeItem(at: dosya.deletingLastPathComponent()) }
        #expect(ImzaDeposu.png(PKDrawing()) == nil)
        #expect(throws: (any Error).self) { try ImzaDeposu.kaydet(PKDrawing(), dosya: dosya) }
        #expect(ImzaDeposu.yukle(dosya: dosya) == nil)
        try ImzaDeposu.kaydet(png: UIImage(cgImage: imzaGorseli()).pngData()!, dosya: dosya)
        #expect(ImzaDeposu.varMi(dosya: dosya))
        #expect(ImzaDeposu.yukle(dosya: dosya)?.width == 200)
        ImzaDeposu.sil(dosya: dosya)
        #expect(ImzaDeposu.yukle(dosya: dosya) == nil)
    }
}
