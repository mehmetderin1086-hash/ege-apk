import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import pdfium

public enum GorselBicimi: String, CaseIterable, Sendable, Identifiable {
    case png, jpeg
    public var id: String { rawValue }
    public var ad: String { self == .png ? "PNG" : "JPEG" }
    public var uzanti: String { self == .png ? "png" : "jpg" }
    var tur: UTType { self == .png ? .png : .jpeg }
}

/// PDF'ten görsele: sayfaları görüntüye çevirme ve gömülü görselleri çıkarma.
public enum PDFGorsel {

    /// Sayfaları görüntü dosyalarına çevirir. `zip` doğruysa tek ZIP döner.
    public static func pdftenGorsele(_ giris: URL, bicim: GorselBicimi = .png, dpi: Int = 150, aralik: String = "",
                                     kalite: Double = 0.85, zip: Bool = false, parola: String? = nil,
                                     ilerleme: Ilerleme? = nil) throws -> [URL] {
        guard (36...600).contains(dpi) else { throw KagitHata.genel("Çözünürlük 36 ile 600 dpi arasında olmalı.") }
        let b = try Belge.ac(giris, parola: parola)
        let idx = try SayfaAraligi.coz(aralik, sayfaSayisi: b.pageCount)
        let ad = giris.deletingPathExtension().lastPathComponent
        let klasor = Gecici.klasor()
        let basamak = max(3, String(b.pageCount).count)
        var dosyalar: [(String, Data)] = []
        var cikti: [URL] = []
        for (k, i) in idx.enumerated() {
            try iptalDenetle()
            try autoreleasepool {
                guard let s = b.page(at: i), let img = PDFCizim.goruntu(s, dpi: CGFloat(dpi)),
                      let veri = PDFCizim.kodla(img, tur: bicim.tur, kalite: kalite) else {
                    throw KagitHata.genel("Sayfa \(i + 1) görüntüye çevrilemedi. Çözünürlüğü düşürmeyi deneyin.")
                }
                let dosyaAdi = "\(TurkceMetin.dosyaAdi(ad))-\(String(format: "%0\(basamak)d", i + 1)).\(bicim.uzanti)"
                if zip {
                    dosyalar.append((dosyaAdi, veri))
                } else {
                    let u = klasor.appendingPathComponent(dosyaAdi)
                    try veri.write(to: u)
                    cikti.append(u)
                }
            }
            ilerleme?(Double(k + 1) / Double(idx.count))
        }
        if zip {
            var z = ZipYazici()
            for (a, v) in dosyalar { z.ekle(a, v, sakla: true) }
            let u = klasor.appendingPathComponent("\(TurkceMetin.dosyaAdi(ad)) görselleri.zip")
            try z.bitir().write(to: u)
            return [u]
        }
        return cikti
    }

    // MARK: Gömülü görselleri çıkar

    public struct GomuluGorsel: Sendable {
        public let sayfa: Int          // 0 tabanlı
        public let sira: Int           // sayfa içi
        public let genislik: Int
        public let yukseklik: Int
        public let veri: Data          // PNG ya da JPEG
        public let uzanti: String
    }

    /// Sayfalardaki gömülü görselleri (PDFium ile) çıkarır. `enAz`: kısa kenarı bundan küçük görseller atlanır.
    public static func gomuluGorseller(_ giris: URL, aralik: String = "", enAz: Int = 24, bicim: GorselBicimi = .png,
                                       kalite: Double = 0.9, parola: String? = nil,
                                       ilerleme: Ilerleme? = nil) throws -> [GomuluGorsel] {
        let erisim = giris.startAccessingSecurityScopedResource()
        defer { if erisim { giris.stopAccessingSecurityScopedResource() } }
        let veri = try Data(contentsOf: giris)
        let sayi = try Belge.ac(veri: veri, ad: giris.lastPathComponent, parola: parola).pageCount
        let idx = try SayfaAraligi.coz(aralik, sayfaSayisi: sayi)

        let tampon = UnsafeMutableRawPointer.allocate(byteCount: max(veri.count, 1), alignment: 16)
        defer { tampon.deallocate() }
        veri.withUnsafeBytes { if let k = $0.baseAddress { tampon.copyMemory(from: k, byteCount: veri.count) } }
        let belge: FPDF_DOCUMENT? = PdfiumKilit.calistir { FPDF_LoadMemDocument64(tampon, veri.count, parola) }
        guard let belge else { throw KagitHata.acilamadi(giris.lastPathComponent) }
        defer { PdfiumKilit.calistir { FPDF_CloseDocument(belge) } }

        var sonuc: [GomuluGorsel] = []
        for (k, i) in idx.enumerated() {
            try iptalDenetle()
            try autoreleasepool {
                try PdfiumKilit.calistir {
                    guard let sayfa = FPDF_LoadPage(belge, Int32(i)) else { throw KagitHata.pdfium("sayfa \(i + 1) yüklenemedi") }
                    defer { FPDF_ClosePage(sayfa) }
                    var sira = 0
                    func tara(adet: Int, al: (Int) -> FPDF_PAGEOBJECT?) {
                        for j in 0..<adet {
                            guard let nesne = al(j) else { continue }
                            switch FPDFPageObj_GetType(nesne) {
                            case 3:
                                if let g = gorselAl(belge, sayfa, nesne, enAz: enAz, bicim: bicim, kalite: kalite) {
                                    sonuc.append(GomuluGorsel(sayfa: i, sira: sira, genislik: g.0, yukseklik: g.1,
                                                              veri: g.2, uzanti: bicim.uzanti))
                                    sira += 1
                                }
                            case 5:
                                let n = Int(FPDFFormObj_CountObjects(nesne))
                                tara(adet: n) { FPDFFormObj_GetObject(nesne, UInt(max(0, $0))) }
                            default: break
                            }
                        }
                    }
                    tara(adet: Int(FPDFPage_CountObjects(sayfa))) { FPDFPage_GetObject(sayfa, Int32($0)) }
                }
            }
            ilerleme?(Double(k + 1) / Double(idx.count))
        }
        return sonuc
    }

    /// Gömülü görselleri dosyalara (ya da ZIP'e) yazar.
    public static func pdftenGorselleriCikar(_ giris: URL, aralik: String = "", bicim: GorselBicimi = .png, zip: Bool = false,
                                             parola: String? = nil, ilerleme: Ilerleme? = nil) throws -> [URL] {
        let liste = try gomuluGorseller(giris, aralik: aralik, bicim: bicim, parola: parola, ilerleme: ilerleme)
        guard !liste.isEmpty else {
            throw KagitHata.genel("Bu PDF'te çıkarılabilir gömülü görsel bulunamadı. Sayfaları görüntüye çevirmeyi deneyin.")
        }
        let ad = TurkceMetin.dosyaAdi(giris.deletingPathExtension().lastPathComponent)
        let klasor = Gecici.klasor()
        func dosyaAdi(_ g: GomuluGorsel) -> String { "\(ad)-s\(g.sayfa + 1)-\(g.sira + 1).\(g.uzanti)" }
        if zip {
            var z = ZipYazici()
            for g in liste { z.ekle(dosyaAdi(g), g.veri, sakla: true) }
            let u = klasor.appendingPathComponent("\(ad) gömülü görseller.zip")
            try z.bitir().write(to: u)
            return [u]
        }
        return try liste.map { g in
            let u = klasor.appendingPathComponent(dosyaAdi(g))
            try g.veri.write(to: u)
            return u
        }
    }

    // MARK: PDFium bitmap → görüntü

    private static func gorselAl(_ belge: FPDF_DOCUMENT, _ sayfa: FPDF_PAGE, _ nesne: FPDF_PAGEOBJECT,
                                 enAz: Int, bicim: GorselBicimi, kalite: Double) -> (Int, Int, Data)? {
        let bitmap = FPDFImageObj_GetBitmap(nesne) ?? FPDFImageObj_GetRenderedBitmap(belge, sayfa, nesne)
        guard let bitmap else { return nil }
        defer { FPDFBitmap_Destroy(bitmap) }
        let w = Int(FPDFBitmap_GetWidth(bitmap)), h = Int(FPDFBitmap_GetHeight(bitmap))
        guard w > 0, h > 0, min(w, h) >= enAz, w * h <= 100_000_000,
              let kaynak = FPDFBitmap_GetBuffer(bitmap) else { return nil }
        let adim = Int(FPDFBitmap_GetStride(bitmap))
        let format = Int(FPDFBitmap_GetFormat(bitmap))
        let bytlar = kaynak.assumingMemoryBound(to: UInt8.self)
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        var alfaVar = false
        for y in 0..<h {
            for x in 0..<w {
                let o = (y * w + x) * 4
                switch format {
                case 1:   // Gray
                    let v = bytlar[y * adim + x]
                    rgba[o] = v; rgba[o + 1] = v; rgba[o + 2] = v
                case 2:   // BGR
                    let p = y * adim + x * 3
                    rgba[o] = bytlar[p + 2]; rgba[o + 1] = bytlar[p + 1]; rgba[o + 2] = bytlar[p]
                default:  // BGRx / BGRA
                    let p = y * adim + x * 4
                    let a = format == 3 ? 255 : bytlar[p + 3]
                    if a != 255 { alfaVar = true }
                    // premultiplied olarak ver
                    let carp = format == 4 ? Int(a) : 255
                    rgba[o] = UInt8(Int(bytlar[p + 2]) * carp / 255)
                    rgba[o + 1] = UInt8(Int(bytlar[p + 1]) * carp / 255)
                    rgba[o + 2] = UInt8(Int(bytlar[p]) * carp / 255)
                    rgba[o + 3] = a
                }
            }
        }
        let bilgi = (format == 4 || format == 5) && alfaVar ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast
        guard let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: bilgi.rawValue),
              var img = ctx.makeImage() else { return nil }
        // JPEG alfa taşımaz: saydamlığı beyaza yatır.
        let tur = bicim
        if tur == .jpeg, alfaVar, let zemin = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            zemin.setFillColor(CGColor(gray: 1, alpha: 1))
            zemin.fill(CGRect(x: 0, y: 0, width: w, height: h))
            zemin.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            if let d = zemin.makeImage() { img = d }
        }
        guard let veri = PDFCizim.kodla(img, tur: tur.tur, kalite: kalite) else { return nil }
        return (w, h, veri)
    }
}
