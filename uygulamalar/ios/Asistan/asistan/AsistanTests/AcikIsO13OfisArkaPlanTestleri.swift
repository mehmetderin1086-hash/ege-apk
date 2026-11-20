import Testing
import Foundation
import PDFKit
@testable import Asistan

/// O13: PDF dahil ofis dönüştürme ana aktör dışında üretilir (uzun PDF'te arayüz donmaz).
@MainActor @Suite("O13 ofis dönüştürme arka planda")
struct AcikIsO13OfisArkaPlanTestleri {
    /// Eşzamanlı bağlamda `Thread.isMainThread` kullanılamadığı için eşzamanlı yardımcı.
    nonisolated private static func anaIsParcacigindaMi() -> Bool { Thread.isMainThread }

    private func icerik(paragraf sayi: Int, baslik: String = "Mitoz") -> OfisOlusturucu.Icerik {
        let paragraflar = (1...sayi).map { "Paragraf \($0): hücre bölünmesi evreleri sırayla anlatılır." }
        return .init(baslik: baslik, paragraflar: paragraflar, tablo: nil, slaytlar: [])
    }

    // (a) Ana aktör dışında üretilen PDF açılır, başlık metinde geçer.
    @Test func pdfArkaPlandaUretilirVeAcilir() async throws {
        // Başlıkta "i" yok: Türkçe yerelde PDFKit metin çıkarımı sistem fontundaki "i" glifini "!" okuyor (çizim doğru, çıkarım yanlış).
        let i = icerik(paragraf: 3, baslik: "Mayoz")
        let (veri, anada) = await Task.detached(priority: .userInitiated) {
            (OfisOlusturucu.pdf(i), Self.anaIsParcacigindaMi())
        }.value
        #expect(!anada)
        let belge = try #require(PDFDocument(data: veri))
        #expect(belge.pageCount >= 1)
        #expect(belge.string?.contains("Mayoz") == true)
    }

    // (b) 300 paragraflık içerik arka planda çok sayfalı PDF olur, son paragraf kaybolmaz.
    @Test func uzunIcerikArkaPlandaCokSayfaliPdf() async throws {
        let i = icerik(paragraf: 300)
        let veri = await Task.detached(priority: .userInitiated) { OfisOlusturucu.pdf(i) }.value
        let belge = try #require(PDFDocument(data: veri))
        #expect(belge.pageCount >= 5)
        #expect(belge.string?.contains("Paragraf 300") == true)
    }

    // Dönüştürücünün arka plan yolu PDF'i artık reddetmez; doğrudan üretimle aynı sayfa sayısını verir.
    @Test func arkaPlanVerisiPdfUretir() async throws {
        let i = icerik(paragraf: 40)
        let veri = try await Task.detached(priority: .userInitiated) { try OfisDonusturucu.arkaPlanVerisi(i, hedef: "pdf") }.value
        let belge = try #require(PDFDocument(data: veri))
        let dogrudan = try #require(PDFDocument(data: OfisOlusturucu.pdf(i)))
        #expect(belge.pageCount == dogrudan.pageCount)
    }

    // (c) Ekranın yolu PDF'i İndirmeler'e yazar ve listeye ekler; test kaydını (dosyasıyla) siler.
    @Test func donusturNotluPdfDosyasiYazar() async throws {
        let yonetici = IndirmeYoneticisi.ortak   // klasörü oluşturur
        let metin = (1...60).map { "Satir \($0) Mitoz evresi" }.joined(separator: "\n")
        let belge = OkunanBelge(ad: "O13-Sinama.docx", metin: metin, not: "")
        let (url, not) = try await OfisDonusturucu.donusturNotlu(belge, hedef: "pdf")
        defer {
            if let k = yonetici.kayitlar.first(where: { $0.dosya == url.lastPathComponent }) { yonetici.sil(k) }
            try? FileManager.default.removeItem(at: url)
        }
        #expect(not.isEmpty)
        #expect(url.pathExtension == "pdf")
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(yonetici.kayitlar.contains { $0.dosya == url.lastPathComponent })
        let pdf = try #require(PDFDocument(url: url))
        #expect(pdf.pageCount >= 1)
        #expect(pdf.string?.contains("Satir 60") == true)
    }
}
