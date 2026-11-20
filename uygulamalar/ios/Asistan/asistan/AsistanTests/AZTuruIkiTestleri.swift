import Foundation
import PDFKit
import Testing
@testable import Asistan

/// 28 Ekim A–Z ikinci tur: sohbet eki OCR'ı, tekrar kartı akışı, her yerde ara derinliği.
@MainActor
@Suite struct AZTuruIkiTestleri {
    private func geciciPdf(_ belge: PDFDocument) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "az2-\(UUID().uuidString).pdf")
        try #require(belge.dataRepresentation()).write(to: url)
        return url
    }

    @Test func sohbet_eki_taranmis_sayfayi_okur_ve_ocr_notu_ekler() throws {
        let metinli = PdfOcrTestleri.metinliPdf("Metin katmanli ikinci sayfa")
        let taranmis = PdfOcrTestleri.taranmisPdf(["BIYOLOJI SINAVI"])
        let birlesik = PDFDocument()
        birlesik.insert(try #require(taranmis.page(at: 0)?.copy() as? PDFPage), at: 0)
        birlesik.insert(try #require(metinli.page(at: 0)?.copy() as? PDFPage), at: 1)
        let url = try geciciPdf(birlesik); defer { try? FileManager.default.removeItem(at: url) }
        let b = try BelgeOkuyucu.oku(url)
        let bir = try #require(b.metin.range(of: "[Sayfa 1]")), iki = try #require(b.metin.range(of: "[Sayfa 2]"))
        #expect(bir.lowerBound < iki.lowerBound)
        #expect(b.metin.uppercased().contains("SINAV"), "OCR çıktısı: \(b.metin)")
        #expect(b.metin.contains("Metin katmanli ikinci sayfa"))
        #expect(b.not.contains("OCR ile okundu"))
    }

    @Test func metinli_pdf_ocr_calistirmaz() throws {
        let url = try geciciPdf(PdfOcrTestleri.metinliPdf("Yalniz metin katmani olan bir sayfa")); defer { try? FileManager.default.removeItem(at: url) }
        let b = try BelgeOkuyucu.oku(url)
        #expect(!b.not.contains("OCR"))
        #expect(BelgeOkuyucu.metinKatmaniYok(" 3 \n"))
        #expect(!BelgeOkuyucu.metinKatmaniYok("Hücre zarı seçici geçirgendir ve madde alışverişini düzenler."))
    }

    @Test func sohbet_derinindeki_mesaj_aramaya_katilir() {
        let a = UUID(), b = UUID()
        let dizin = AramaDizini(ogeler: [
            AramaOgesi(hedef: .sohbet(a), baslik: "Biyoloji dersi", govde: "giriş"),
            AramaOgesi(hedef: .sohbet(b), baslik: "Mitokondri soruları", govde: ""),
        ])
        let c = BirlesikArama.ara("mitokondri", dizin: dizin)
        #expect(c.sonuclar.map(\.oge.hedef) == [.sohbet(b)])   // dizin yalnız başlıkta buldu
        let eslesmeler = [(sohbet: a, metin: "Bugün mitokondri hücrenin enerji santrali diye anlattım.", yedekOzet: ""),
                          (sohbet: b, metin: "mitokondri", yedekOzet: ""),
                          (sohbet: UUID(), metin: "mitokondri", yedekOzet: "")]   // dizinde olmayan sohbet atlanır
        let k = BirlesikArama.mesajEslesmeleriniKat(c, eslesmeler: eslesmeler, dizin: dizin, sorgu: "mitokondri")
        #expect(k.sonuclar.map(\.oge.hedef) == [.sohbet(b), .sohbet(a)])
        #expect(k.sonuclar.last?.ozet.contains("mitokondri") == true)
        #expect(k.sonuclar.last?.ozetVurgulari.isEmpty == false)
        let suzulmus = BirlesikArama.mesajEslesmeleriniKat(c, eslesmeler: eslesmeler, dizin: dizin, sorgu: "mitokondri", turler: [.tuval])
        #expect(suzulmus.sonuclar.count == c.sonuclar.count)
    }

    @Test func dondurulmus_taranmis_sayfa_ocr_ile_okunur() throws {
        let pdf = PdfOcrTestleri.taranmisPdf(["BIYOLOJI SINAVI"])
        let sayfa = try #require(pdf.page(at: 0))
        sayfa.rotation = 90
        #expect(PdfOcr.donmusBoyut(sayfa.bounds(for: .mediaBox), rotation: 90).width > PdfOcr.donmusBoyut(sayfa.bounds(for: .mediaBox), rotation: 0).width)
        // Döndürülmüş dikey sayfa yatay görüntü vermeli (tuval dikey kalırsa çizim kırpılır).
        let cg = try #require(PdfOcr.goruntu(sayfa, ayar: .varsayilan))
        #expect(cg.width > cg.height, "döndürülmüş sayfa görüntüsü \(cg.width)×\(cg.height)")
        let s = try PdfOcr.oku(pdf, sayfalar: [0])
        let metin = try #require(s.sayfalar.first).metin.uppercased()
        #expect(metin.contains("SINAV"), "döndürülmüş sayfa OCR çıktısı: \(metin)")
    }

    @Test func bos_kapak_sayfasi_ocr_notu_birakmaz() throws {
        let bos = PdfOcrTestleri.taranmisPdf([nil])
        let metinli = PdfOcrTestleri.metinliPdf("Metin katmanli sayfa uzun bir cumle")
        let birlesik = PDFDocument()
        birlesik.insert(try #require(bos.page(at: 0)?.copy() as? PDFPage), at: 0)
        birlesik.insert(try #require(metinli.page(at: 0)?.copy() as? PDFPage), at: 1)
        let url = try geciciPdf(birlesik); defer { try? FileManager.default.removeItem(at: url) }
        let b = try BelgeOkuyucu.oku(url)
        #expect(!b.not.contains("OCR"), "boş sayfa için OCR notu: \(b.not)")
        #expect(b.metin.contains("[Sayfa 2]"))
    }

    @Test func mesaj_eslesmesi_butun_terimleri_ister() {
        let a = UUID()
        let dizin = AramaDizini(ogeler: [AramaOgesi(hedef: .sohbet(a), baslik: "Sohbet", govde: "")])
        let k = BirlesikArama.mesajEslesmeleriniKat(AramaCikti(), eslesmeler: [(sohbet: a, metin: "Hücre bölünmesi anlatıldı.", yedekOzet: "")],
                                                    dizin: dizin, sorgu: "mitoz bölünme")
        #expect(k.sonuclar.isEmpty)
    }
}

