import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Platformdan bağımsız (UIKit/AppKit'siz) PDF üretme ve sayfa görüntüleme yardımcıları.
public enum PDFCizim {

    /// Standart sayfa boyutları (punto, 1/72 inç).
    public enum Boyut: String, CaseIterable, Sendable, Identifiable {
        case a4, a5, a3, letter, legal
        public var id: String { rawValue }
        public var ad: String {
            switch self {
            case .a4: "A4"
            case .a5: "A5"
            case .a3: "A3"
            case .letter: "Letter"
            case .legal: "Legal"
            }
        }
        public var boyut: CGSize {
            switch self {
            case .a4: CGSize(width: 595.28, height: 841.89)
            case .a5: CGSize(width: 419.53, height: 595.28)
            case .a3: CGSize(width: 841.89, height: 1190.55)
            case .letter: CGSize(width: 612, height: 792)
            case .legal: CGSize(width: 612, height: 1008)
            }
        }
        public func yonlu(yatay: Bool) -> CGSize {
            yatay ? CGSize(width: boyut.height, height: boyut.width) : boyut
        }
    }

    /// Sayfa sayfa PDF üreten yazıcı. Kullanım: `let y = Yazici(); y.sayfa(kutu) { ctx in … }; y.bitir()`
    public final class Yazici {
        private let veri = NSMutableData()
        private let ctx: CGContext
        private var bitti = false

        public init(baslik: String? = nil, yazar: String? = nil) {
            let tuketici = CGDataConsumer(data: veri as CFMutableData)!
            var bilgi: [CFString: Any] = [kCGPDFContextCreator: "Kâğıt"]
            if let baslik { bilgi[kCGPDFContextTitle] = baslik }
            if let yazar { bilgi[kCGPDFContextAuthor] = yazar }
            var kutu = CGRect(origin: .zero, size: Boyut.a4.boyut)
            ctx = CGContext(consumer: tuketici, mediaBox: &kutu, bilgi as CFDictionary)!
        }

        /// Yeni sayfa açar; çizim kapanışında koordinatlar PDF düzenindedir (sol alt köşe 0,0).
        public func sayfa(_ kutu: CGRect, _ ciz: (CGContext) throws -> Void) rethrows {
            var k = kutu
            let sozluk = [kCGPDFContextMediaBox: Data(bytes: &k, count: MemoryLayout<CGRect>.size)] as CFDictionary
            ctx.beginPDFPage(sozluk)
            ctx.saveGState()
            defer { ctx.restoreGState(); ctx.endPDFPage() }
            try ciz(ctx)
        }

        /// Var olan bir PDF sayfasını vektör olarak çizer (döndürme hesaba katılır).
        public func sayfaKopyala(_ sayfa: PDFPage, kutu: PDFDisplayBox = .cropBox, ustCizim: ((CGContext, CGRect) -> Void)? = nil) {
            let sinir = sayfa.bounds(for: kutu)
            let donuk = sayfa.rotation % 180 != 0
            let boyut = donuk ? CGSize(width: sinir.height, height: sinir.width) : sinir.size
            self.sayfa(CGRect(origin: .zero, size: boyut)) { c in
                sayfa.draw(with: kutu, to: c)
                ustCizim?(c, CGRect(origin: .zero, size: boyut))
            }
        }

        public func bitir() -> Data {
            if !bitti { ctx.closePDF(); bitti = true }
            return veri as Data
        }
    }

    /// Sayfayı verilen dpi'de beyaz zemin üzerine görüntüye çevirir.
    public static func goruntu(_ sayfa: PDFPage, dpi: CGFloat = 150, kutu: PDFDisplayBox = .cropBox,
                               saydam: Bool = false) -> CGImage? {
        let sinir = sayfa.bounds(for: kutu)
        let donuk = sayfa.rotation % 180 != 0
        let boyut = donuk ? CGSize(width: sinir.height, height: sinir.width) : sinir.size
        let olcek = dpi / 72
        let g = max(1, Int((boyut.width * olcek).rounded())), y = max(1, Int((boyut.height * olcek).rounded()))
        guard g * y <= 12_000 * 12_000,
              let ctx = CGContext(data: nil, width: g, height: y, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if !saydam {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: g, height: y))
        }
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: olcek, y: olcek)
        sayfa.draw(with: kutu, to: ctx)
        return ctx.makeImage()
    }

    /// CGImage'ı JPEG/PNG/HEIC verisine çevirir.
    public static func kodla(_ goruntu: CGImage, tur: UTType = .jpeg, kalite: Double = 0.85) -> Data? {
        let veri = NSMutableData()
        guard let hedef = CGImageDestinationCreateWithData(veri, tur.identifier as CFString, 1, nil) else { return nil }
        let secenek = [kCGImageDestinationLossyCompressionQuality: kalite] as CFDictionary
        CGImageDestinationAddImage(hedef, goruntu, secenek)
        guard CGImageDestinationFinalize(hedef) else { return nil }
        return veri as Data
    }

    /// Dosya/veriden CGImage (EXIF yönü uygulanmış hâliyle).
    public static func goruntuYukle(_ veri: Data, enBuyukKenar: CGFloat? = nil) -> CGImage? {
        guard let kaynak = CGImageSourceCreateWithData(veri as CFData, nil) else { return nil }
        var secenek: [CFString: Any] = [kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceShouldCacheImmediately: true]
        if let enBuyukKenar {
            secenek[kCGImageSourceThumbnailMaxPixelSize] = enBuyukKenar
        } else if let ozellik = CGImageSourceCopyPropertiesAtIndex(kaynak, 0, nil) as? [CFString: Any],
                  let g = ozellik[kCGImagePropertyPixelWidth] as? CGFloat,
                  let y = ozellik[kCGImagePropertyPixelHeight] as? CGFloat {
            secenek[kCGImageSourceThumbnailMaxPixelSize] = max(g, y)
        }
        return CGImageSourceCreateThumbnailAtIndex(kaynak, 0, secenek as CFDictionary)
    }

    // MARK: - Metin çizimi (CoreText)

    public enum Hiza: Sendable { case sol, orta, sag }

    /// Tek satır metin çizer. `nokta` taban çizgisinin hizaya göre başlangıcıdır.
    /// Not: metin çıkarımı bozulmasın diye sistem fontu yerine Helvetica kullanılır (ölçüldü).
    @discardableResult
    public static func metin(_ s: String, _ ctx: CGContext, nokta: CGPoint, punto: CGFloat,
                             renk: CGColor = CGColor(gray: 0, alpha: 1), yaziTipi: String = "Helvetica",
                             hiza: Hiza = .sol, kalin: Bool = false) -> CGRect {
        let ad = kalin ? "\(yaziTipi)-Bold" : yaziTipi
        let font = CTFontCreateWithName(ad as CFString, punto, nil)
        let nitelik: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): renk,
        ]
        let satir = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: nitelik))
        let genislik = CGFloat(CTLineGetTypographicBounds(satir, nil, nil, nil))
        var x = nokta.x
        switch hiza {
        case .sol: break
        case .orta: x -= genislik / 2
        case .sag: x -= genislik
        }
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: x, y: nokta.y)
        CTLineDraw(satir, ctx)
        ctx.restoreGState()
        return CGRect(x: x, y: nokta.y - punto * 0.25, width: genislik, height: punto * 1.2)
    }

    /// Metnin tek satır genişliği.
    public static func genislik(_ s: String, punto: CGFloat, yaziTipi: String = "Helvetica") -> CGFloat {
        let font = CTFontCreateWithName(yaziTipi as CFString, punto, nil)
        let nitelik = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        let satir = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: nitelik))
        return CGFloat(CTLineGetTypographicBounds(satir, nil, nil, nil))
    }

    /// Kutuya sözcük kaydırmalı paragraf çizer; sığmayan metnin kalanını döndürür.
    @discardableResult
    public static func paragraf(_ s: String, _ ctx: CGContext, kutu: CGRect, punto: CGFloat,
                                renk: CGColor = CGColor(gray: 0, alpha: 1), yaziTipi: String = "Helvetica",
                                satirAraligi: CGFloat = 1.25, hiza: CTTextAlignment = .natural) -> String {
        let font = CTFontCreateWithName(yaziTipi as CFString, punto, nil)
        var hizalama = hiza
        var aralik = punto * (satirAraligi - 1)
        let ayarlar = [
            CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: &hizalama),
            CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<CGFloat>.size, value: &aralik),
        ]
        let stil = CTParagraphStyleCreate(ayarlar, ayarlar.count)
        let nitelik: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): renk,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): stil,
        ]
        let ats = NSAttributedString(string: s, attributes: nitelik)
        let kurucu = CTFramesetterCreateWithAttributedString(ats)
        let yol = CGPath(rect: kutu, transform: nil)
        let cerceve = CTFramesetterCreateFrame(kurucu, CFRange(location: 0, length: 0), yol, nil)
        ctx.saveGState()
        ctx.textMatrix = .identity
        CTFrameDraw(cerceve, ctx)
        ctx.restoreGState()
        let gorunen = CTFrameGetVisibleStringRange(cerceve)
        let ns = s as NSString
        let bitis = gorunen.location + gorunen.length
        return bitis >= ns.length ? "" : ns.substring(from: bitis).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Paragrafın verilen genişlikte kaplayacağı yükseklik.
    public static func paragrafYuksekligi(_ s: String, genislik: CGFloat, punto: CGFloat,
                                          yaziTipi: String = "Helvetica") -> CGFloat {
        let font = CTFontCreateWithName(yaziTipi as CFString, punto, nil)
        let ats = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let kurucu = CTFramesetterCreateWithAttributedString(ats)
        let boyut = CTFramesetterSuggestFrameSizeWithConstraints(kurucu, CFRange(location: 0, length: 0), nil,
                                                                 CGSize(width: genislik, height: .greatestFiniteMagnitude), nil)
        return ceil(boyut.height)
    }
}

/// Geçici çalışma dosyaları: her iş kendi klasöründe.
public enum Gecici {
    public static var kok: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Kagit", isDirectory: true)
    }

    /// Yeni, boş bir iş klasörü.
    public static func klasor() -> URL {
        let u = kok.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// Yeni iş klasöründe verilen adla dosya yolu.
    public static func dosya(_ ad: String) -> URL {
        klasor().appendingPathComponent(TurkceMetin.dosyaAdi(ad))
    }

    /// Bir günden eski geçici klasörleri temizler.
    public static func temizle() {
        let fm = FileManager.default
        guard let icerik = try? fm.contentsOfDirectory(at: kok, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let sinir = Date().addingTimeInterval(-86_400)
        for u in icerik {
            let tarih = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if tarih < sinir { try? fm.removeItem(at: u) }
        }
    }
}
