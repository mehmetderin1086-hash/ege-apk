import CoreGraphics
import Foundation
import PDFKit

/// Dosya düzeyinde düzenleme araçlarının mantığı (araç ekranları arka planda çağırır).
public enum DuzenlemeAraclari {

    /// Açıklamaları ve form alanlarını sayfa içeriğine işler: önce PDFKit `burnIn`, sonra PDFium düzleştirme
    /// (PDFKit'in çizmediği form alanları için).
    public static func duzlestir(_ belge: PDFDocument, parola: String? = nil) throws -> Data {
        let ara = try Belge.veri(belge, secenekler: KayitSecenekleri(aciklamalariGom: true))
        let pdfium = try PdfiumBelge(veri: ara)
        for i in 0..<pdfium.sayfaSayisi { try pdfium.duzlestir(sayfa: i) }
        var cikti = try pdfium.kaydet()
        guard let kontrol = PDFDocument(data: cikti), kontrol.pageCount == belge.pageCount else {
            throw KagitHata.dogrulamaBasarisiz("düzleştirilmiş çıktı sayfa sayısı tutmuyor")
        }
        if let parola {
            // PDFium güvenliği kaldırarak yazar; özgün koruma geri konur.
            cikti = try Belge.veri(kontrol, secenekler: KayitSecenekleri(kullaniciParolasi: parola, sahipParolasi: parola))
        }
        return cikti
    }

    /// Dosyadan düzleştirir.
    public static func duzlestir(url: URL, parola: String? = nil) throws -> Data {
        try duzlestir(try Belge.ac(url, parola: parola), parola: parola)
    }

    /// İşaretleme açıklamalarını (vurgu, çizim, şekil, not, damga…) kaldırır. Bağlantılar ve form alanları
    /// varsayılan olarak korunur. Kaldırılan sayısını da döndürür.
    public static func aciklamalariKaldir(_ belge: PDFDocument, baglantilariKoru: Bool = true,
                                          formlariKoru: Bool = true) -> Int {
        var sayi = 0
        for i in 0..<belge.pageCount {
            guard let sayfa = belge.page(at: i) else { continue }
            for a in sayfa.annotations {
                let tur = a.type ?? ""
                if tur == "Link" && baglantilariKoru { continue }
                if tur == "Widget" && formlariKoru { continue }
                sayfa.removeAnnotation(a)
                sayi += 1
            }
        }
        return sayi
    }

    /// Dosyadan açıklamaları kaldırıp yeni veri üretir.
    public static func aciklamalariKaldir(url: URL, parola: String? = nil, baglantilariKoru: Bool = true,
                                          formlariKoru: Bool = true) throws -> (veri: Data, kaldirilan: Int) {
        let belge = try Belge.ac(url, parola: parola)
        let n = aciklamalariKaldir(belge, baglantilariKoru: baglantilariKoru, formlariKoru: formlariKoru)
        var s = KayitSecenekleri()
        if let parola { s.kullaniciParolasi = parola; s.sahipParolasi = parola }
        return (try Belge.veri(belge, secenekler: s), n)
    }
}
