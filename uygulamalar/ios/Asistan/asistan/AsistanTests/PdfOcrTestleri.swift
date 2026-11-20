import Testing
import Foundation
import PDFKit
import UIKit
@testable import Asistan

@Suite("Taranmış PDF için yerel OCR") @MainActor
struct PdfOcrTestleri {
    // MARK: Yardımcılar

    /// Büyük, siyah-beyaz metin görüntüsü.
    static func metinGoruntusu(_ yazi: String) -> UIImage {
        let boyut = CGSize(width: 1600, height: 600)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true
        return UIGraphicsImageRenderer(size: boyut, format: f).image { r in
            UIColor.white.setFill(); r.fill(CGRect(origin: .zero, size: boyut))
            (yazi as NSString).draw(in: CGRect(x: 80, y: 200, width: 1440, height: 200),
                                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: 150), .foregroundColor: UIColor.black])
        }
    }

    /// Metin katmanı OLMAYAN PDF: her sayfa yalnız bir görüntü. `yazilar[i]` nil ise boş (beyaz) sayfa.
    static func taranmisPdf(_ yazilar: [String?]) -> PDFDocument {
        let sayfa = CGRect(x: 0, y: 0, width: 595, height: 842)
        let veri = UIGraphicsPDFRenderer(bounds: sayfa).pdfData { ctx in
            for y in yazilar {
                ctx.beginPage()
                guard let y else { continue }
                metinGoruntusu(y).draw(in: CGRect(x: 20, y: 200, width: 555, height: 208))
            }
        }
        return PDFDocument(data: veri)!
    }

    /// Metin katmanı OLAN PDF.
    static func metinliPdf(_ yazi: String) -> PDFDocument {
        let veri = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)).pdfData { ctx in
            ctx.beginPage()
            (yazi as NSString).draw(at: CGPoint(x: 40, y: 80), withAttributes: [.font: UIFont(name: "Helvetica", size: 18)!])
        }
        return PDFDocument(data: veri)!
    }

    static func satir(_ metin: String, x: CGFloat, y: CGFloat, g: Float = 0.9, w: CGFloat = 0.2, h: CGFloat = 0.03) -> PdfOcr.Satir {
        .init(metin: metin, guven: g, kutu: CGRect(x: x, y: y, width: w, height: h))
    }

    // MARK: Saf mantık

    @Test func okumaSirasiUsttenAltaDizer() {
        let girdi = [Self.satir("alt", x: 0.1, y: 0.1), Self.satir("orta", x: 0.1, y: 0.5), Self.satir("ust", x: 0.1, y: 0.9)]
        #expect(PdfOcr.okumaSirasi(girdi).map(\.metin) == ["ust", "orta", "alt"])
    }

    @Test func okumaSirasiAyniHizadaSoldanSagaDizer() {
        // Sağdaki parça biraz daha yüksekte (Vision gürültüsü) ama aynı satırda sayılmalı.
        let girdi = [Self.satir("sag", x: 0.6, y: 0.502), Self.satir("sol", x: 0.1, y: 0.5), Self.satir("ust", x: 0.1, y: 0.9)]
        #expect(PdfOcr.okumaSirasi(girdi).map(\.metin) == ["ust", "sol", "sag"])
    }

    @Test func okumaSirasiBosVeTekGirdiyiKorur() {
        #expect(PdfOcr.okumaSirasi([]).isEmpty)
        let tek = [Self.satir("a", x: 0, y: 0)]
        #expect(PdfOcr.okumaSirasi(tek) == tek)
    }

    @Test func sayfaMetniAyniHizayiBosluklaFarkliHizayiSatirlaBirlestirir() {
        let girdi = [Self.satir("2", x: 0.5, y: 0.5), Self.satir("1)", x: 0.1, y: 0.5), Self.satir("Sonraki", x: 0.1, y: 0.2), Self.satir("   ", x: 0.1, y: 0.1)]
        #expect(PdfOcr.sayfaMetni(girdi) == "1) 2\nSonraki")
        #expect(PdfOcr.sayfaMetni([]) == "")
    }

    @Test func guvenOzetiOrtalamaVeDusukOraniHesaplar() {
        let o = PdfOcr.guvenOzeti([1.0, 0.8, 0.3, 0.1], esik: 0.5)
        #expect(abs((o.ortalama ?? 0) - 0.55) < 1e-6)
        #expect(o.dusukOran == 0.5)
    }

    @Test func guvenOzetiBosVeGecersizDegerleriDuzgunIsler() {
        let bos = PdfOcr.guvenOzeti([], esik: 0.5)
        #expect(bos.ortalama == nil && bos.dusukOran == 0)
        let kirli = PdfOcr.guvenOzeti([.nan, 2.0, -1.0], esik: 0.5)
        #expect(kirli.ortalama == 0.5)
        #expect(kirli.dusukOran == 0.5)
    }

    @Test func pikselBoyutuA4Icin250DpiOlcekler() {
        let b = PdfOcr.pikselBoyutu(sayfa: CGSize(width: 595, height: 842), dpi: 250, azami: 10_000)
        #expect(b.width == (595 * 250 / 72.0).rounded())
        #expect(b.height == (842 * 250 / 72.0).rounded())
    }

    @Test func pikselBoyutuUzunKenariSinirlar() {
        let b = PdfOcr.pikselBoyutu(sayfa: CGSize(width: 595, height: 842), dpi: 300, azami: 3000)
        #expect(max(b.width, b.height) <= 3000)
        #expect(abs(b.width / b.height - 595.0 / 842.0) < 0.01)
    }

    @Test func pikselBoyutuGecersizGirdideSifirDoner() {
        #expect(PdfOcr.pikselBoyutu(sayfa: .zero, dpi: 250, azami: 3000) == .zero)
        #expect(PdfOcr.pikselBoyutu(sayfa: CGSize(width: 100, height: 100), dpi: 0, azami: 3000) == .zero)
    }

    @Test func notOcrIbaresiniVeOrtalamaGuveniIcerir() {
        let s = PdfOcr.Sonuc(sayfalar: [.init(indeks: 0, metin: "x", satirSayisi: 4, ortalamaGuven: 0.874, dusukGuvenOrani: 0.25, hata: nil)],
                             sinirYuzundenAtlanan: 0, sureYuzundenAtlanan: 0)
        let n = PdfOcr.not(s)
        #expect(n.contains("OCR ile okundu, hata olabilir"))
        #expect(n.contains("Ortalama güven %87"))
        #expect(n.contains("%25"))
    }

    @Test func notSinirSureVeHataliSayfalariBildirir() {
        let s = PdfOcr.Sonuc(sayfalar: [.init(indeks: 4, metin: "", satirSayisi: 0, ortalamaGuven: nil, dusukGuvenOrani: 0, hata: "bozuk")],
                             sinirYuzundenAtlanan: 7, sureYuzundenAtlanan: 3)
        let n = PdfOcr.not(s)
        #expect(n.contains("7 sayfa atlandı") && n.contains("3 sayfa atlandı"))
        #expect(n.contains("5"))
        #expect(s.sureAsildi && s.metinliSayfalar.isEmpty && s.hataliSayfalar.count == 1)
    }

    // MARK: Gerçek PDF + Vision

    @Test func metinsizGoruntuSayfasiOcrIleOkunur() throws {
        let pdf = Self.taranmisPdf(["BIYOLOJI SINAVI"])
        let metinKatmani = (pdf.page(at: 0)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(metinKatmani.isEmpty, "test PDF'i metin katmanı taşımamalı")
        let s = try PdfOcr.oku(pdf, sayfalar: [0])
        let sayfa = try #require(s.sayfalar.first)
        #expect(sayfa.hata == nil)
        #expect(sayfa.metin.uppercased().contains("SINAV"), "OCR çıktısı: \(sayfa.metin)")
        #expect((sayfa.ortalamaGuven ?? 0) > 0.3)
    }

    @Test func bosSayfaMetinVermezAmaHataDaVermez() throws {
        let s = try PdfOcr.oku(Self.taranmisPdf([nil]), sayfalar: [0])
        #expect(s.sayfalar.count == 1)
        #expect(s.sayfalar[0].hata == nil)
        #expect(s.sayfalar[0].metin.isEmpty)
        #expect(s.metinliSayfalar.isEmpty)
        #expect(s.ortalamaGuven == nil)
    }

    @Test func gecersizSayfaIndeksiDigerSayfalariDurdurmaz() throws {
        let s = try PdfOcr.oku(Self.taranmisPdf(["BIYOLOJI SINAVI"]), sayfalar: [9, 0])
        #expect(s.sayfalar.count == 2)
        #expect(s.sayfalar[0].hata != nil)
        #expect(s.sayfalar[1].hata == nil)
    }

    @Test func sayfaSiniriAsilanSayfalariAtlarVeSayar() throws {
        var ayar = PdfOcr.Ayar(); ayar.azamiSayfa = 2
        let s = try PdfOcr.oku(Self.taranmisPdf([nil, nil, nil, nil, nil]), sayfalar: [0, 1, 2, 3, 4], ayar: ayar)
        #expect(s.sayfalar.count == 2)
        #expect(s.sinirYuzundenAtlanan == 3)
        #expect(PdfOcr.Ayar.varsayilan.azamiSayfa == 60)
    }

    @Test func sureButcesiDolunca_kalanSayfalarAtlanir() throws {
        var ayar = PdfOcr.Ayar(); ayar.sureButcesi = 0
        let s = try PdfOcr.oku(Self.taranmisPdf([nil, nil, nil]), sayfalar: [0, 1, 2], ayar: ayar)
        #expect(s.sayfalar.isEmpty)
        #expect(s.sureYuzundenAtlanan == 3)
        #expect(s.sureAsildi)
    }

    @Test func ilerlemeHerSayfadaBildirilir() throws {
        nonisolated final class Kayit: @unchecked Sendable { let kilit = NSLock(); var liste: [[Int]] = []
            func ekle(_ a: Int, _ b: Int) { kilit.lock(); liste.append([a, b]); kilit.unlock() } }
        let kayit = Kayit()
        _ = try PdfOcr.oku(Self.taranmisPdf([nil, nil]), sayfalar: [0, 1], ilerleme: { kayit.ekle($0, $1) })
        #expect(kayit.liste == [[1, 2], [2, 2]])
    }

    @Test func iptalCancellationErrorFirlatir() async {
        nonisolated(unsafe) let pdf = Self.taranmisPdf([nil, nil])
        let gorev = Task.detached { () -> Bool in
            while !Task.isCancelled { await Task.yield() }
            do { _ = try PdfOcr.oku(pdf, sayfalar: [0, 1]); return false } catch is CancellationError { return true } catch { return false }
        }
        gorev.cancel()
        #expect(await gorev.value)
    }

    // MARK: Çalışma alanı akışı

    @Test func pdfMetniOcrAcikkenTaranmisSayfayiOkurVeNotEkler() throws {
        let veri = try #require(Self.taranmisPdf(["BIYOLOJI SINAVI"]).dataRepresentation())
        let metin = try CalismaSunucusu.pdfMetni(veri, ocr: true)
        #expect(metin.contains("[Sayfa 1]"))
        #expect(metin.uppercased().contains("SINAV"), "çıktı: \(metin)")
        #expect(metin.contains("OCR ile okundu, hata olabilir"))
    }

    @Test func pdfMetniOcrKapaliykenEskiDavranisiKorur() throws {
        let veri = try #require(Self.taranmisPdf(["BIYOLOJI SINAVI"]).dataRepresentation())
        #expect(throws: CalismaHatasi.self) { try CalismaSunucusu.pdfMetni(veri) }
    }

    @Test func pdfMetniKarisikSayfalardaSayfaSirasiniKorur() throws {
        let belge = Self.metinliPdf("Metin katmanli sayfa")
        let taranmis = Self.taranmisPdf(["BIYOLOJI SINAVI"])
        let birlesik = PDFDocument()
        birlesik.insert(try #require(taranmis.page(at: 0)?.copy() as? PDFPage), at: 0)
        birlesik.insert(try #require(belge.page(at: 0)?.copy() as? PDFPage), at: 1)
        let metin = try CalismaSunucusu.pdfMetni(try #require(birlesik.dataRepresentation()), ocr: true)
        let bir = try #require(metin.range(of: "[Sayfa 1]")), iki = try #require(metin.range(of: "[Sayfa 2]"))
        #expect(bir.lowerBound < iki.lowerBound)
        #expect(metin.contains("Metin katmanli sayfa"), "PDF çıktısı: \(metin)")
    }

    @Test func pdfMetniOcrAcikkenBosSayfaOnaMetinBulamazsaHataVerir() throws {
        let veri = try #require(Self.taranmisPdf([nil]).dataRepresentation())
        #expect(throws: CalismaHatasi.self) { try CalismaSunucusu.pdfMetni(veri, ocr: true) }
    }
}
