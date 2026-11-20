import CoreGraphics
import Foundation
import PDFKit

/// Sayfa/damga/sıkıştırma işlevlerinin ortak yardımcıları (iç kullanım).
enum IsYardimcisi {
    /// "<ad> (<ek>).pdf" biçiminde, yeni bir geçici iş klasöründe çıktı yolu.
    static func cikti(_ giris: URL, _ ek: String, uzanti: String = "pdf") -> URL {
        let ad = giris.deletingPathExtension().lastPathComponent
        return Gecici.dosya(ek.isEmpty ? "\(ad).\(uzanti)" : "\(ad) (\(ek)).\(uzanti)")
    }

    /// Verilen sayfaların kopyalarından yeni belge. Kaynak belge çağıran tarafta canlı tutulmalıdır.
    static func belge(_ kaynak: PDFDocument, indeksler: [Int]) -> PDFDocument {
        let yeni = PDFDocument()
        var k = 0
        while k < indeksler.count {
            autoreleasepool {
                let son = min(indeksler.count, k + 50)
                for i in indeksler[k..<son] {
                    if let s = kaynak.page(at: i) { yeni.insert(Belge.sayfaKopyasi(s), at: yeni.pageCount) }
                }
                k = son
            }
        }
        return yeni
    }

    /// Verilen boyutta boş PDF sayfası.
    static func bosSayfa(_ boyut: CGSize) -> PDFPage? {
        let y = PDFCizim.Yazici()
        y.sayfa(CGRect(origin: .zero, size: boyut)) { _ in }
        return PDFDocument(data: y.bitir())?.page(at: 0)
    }

    /// Sayfanın döndürme sonrası görünen boyutu.
    static func gorunenBoyut(_ s: PDFPage, kutu: PDFDisplayBox = .cropBox) -> CGSize {
        let b = s.bounds(for: kutu)
        return s.rotation % 180 != 0 ? CGSize(width: b.height, height: b.width) : b.size
    }

    /// Belgeyi doğrulayarak yazar ve çıktı URL'sini döndürür.
    @discardableResult
    static func yaz(_ belge: PDFDocument, _ hedef: URL, secenekler: KayitSecenekleri = .init()) throws -> URL {
        try Belge.kaydet(belge, hedef, secenekler: secenekler)
        return hedef
    }

    static func dosyaBoyutu(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    /// Sayfa kutusunu (kenara göre) çıktı sayfasına sığdıran dönüşüm ile çizer.
    static func sigdirCiz(_ sayfa: PDFPage, _ ctx: CGContext, hedef: CGRect, doldur: Bool = false) {
        let g = gorunenBoyut(sayfa)
        guard g.width > 0, g.height > 0 else { return }
        let o = doldur ? max(hedef.width / g.width, hedef.height / g.height)
                       : min(hedef.width / g.width, hedef.height / g.height)
        let w = g.width * o, h = g.height * o
        ctx.saveGState()
        ctx.clip(to: hedef)
        ctx.translateBy(x: hedef.midX - w / 2, y: hedef.midY - h / 2)
        ctx.scaleBy(x: o, y: o)
        sayfa.draw(with: .cropBox, to: ctx)
        ctx.restoreGState()
    }
}
