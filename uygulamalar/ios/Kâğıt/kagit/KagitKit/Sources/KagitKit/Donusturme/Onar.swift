import Foundation
import PDFKit

/// Bozuk PDF'leri onarma: PDFium'la açıp yeniden yazar, PDFKit'le doğrular.
public enum PDFOnar {

    public struct Sonuc: Sendable {
        public let cikti: URL
        public let sayfaSayisi: Int
        /// Kullanılan yöntem (ileti için).
        public let yontem: String
    }

    public static func onar(_ giris: URL, parola: String? = nil) throws -> Sonuc {
        let erisim = giris.startAccessingSecurityScopedResource()
        defer { if erisim { giris.stopAccessingSecurityScopedResource() } }
        let veri = try Data(contentsOf: giris)
        let hedef = IsYardimcisi.cikti(giris, "onarıldı")

        // 1) PDFium: yapı bozukluklarını (xref, akış uzunlukları) kendi tarayıcısıyla toparlar.
        var pdfiumHatasi: Error?
        do {
            let p = try PdfiumBelge(veri: veri, parola: parola)
            let yeni = try p.kaydet()
            if let kontrol = PDFDocument(data: yeni), !kontrol.isLocked, kontrol.pageCount > 0 {
                try Belge.yaz(yeni, hedef, beklenenSayfa: kontrol.pageCount)
                return Sonuc(cikti: hedef, sayfaSayisi: kontrol.pageCount, yontem: "PDFium ile yeniden yazıldı")
            }
        } catch {
            pdfiumHatasi = error
        }

        // 2) PDFKit: açılabilen sayfaları yeniden derle.
        if let kaynak = PDFDocument(data: veri) {
            if kaynak.isLocked {
                guard let parola, kaynak.unlock(withPassword: parola) else { throw KagitHata.parolaGerekli }
            }
            if kaynak.pageCount > 0 {
                let yeni = IsYardimcisi.belge(kaynak, indeksler: Array(0..<kaynak.pageCount))
                try Belge.kaydet(yeni, hedef)
                return Sonuc(cikti: hedef, sayfaSayisi: yeni.pageCount, yontem: "PDFKit ile yeniden derlendi")
            }
        }
        throw KagitHata.genel("Bu dosya onarılamadı" + (pdfiumHatasi.map { " (\(($0 as? LocalizedError)?.errorDescription ?? $0.localizedDescription))" } ?? "") + ".")
    }
}
