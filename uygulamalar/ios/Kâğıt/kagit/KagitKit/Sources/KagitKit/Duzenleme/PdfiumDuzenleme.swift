import CoreGraphics
import Foundation
import pdfium

/// PDFium ile içerik düzeyinde düzenleme: satır değiştirme, örtü ve görsel ekleme.
extension PdfiumBelge {

    /// Metin satırını değiştirir: eski nesneleri siler, yeni metni aynı taban çizgisine yazar.
    /// Döndürülen değer yeni metnin kutusudur.
    @discardableResult
    public func satiriDegistir(sayfa i: Int, satir: DuzenlemeSatiri, yeniMetin: String, punto: CGFloat? = nil,
                               yaziTipi: GomuluYaziTipi? = nil, renk: RGBA? = nil) throws -> CGRect {
        let tip = yaziTipi ?? GomuluYaziTipi.eslestir(satir.yaziTipiAdi)
        try nesneleriSil(sayfa: i, indeksler: satir.indeksler)
        let metin = yeniMetin.trimmingCharacters(in: .newlines)
        guard !metin.isEmpty else { return .null }
        let taban = CGPoint(x: satir.nesneler.map(\.taban.x).min() ?? satir.solX, y: satir.tabanY)
        return try metinEkle(sayfa: i, metin: metin, taban: taban, punto: punto ?? satir.punto,
                             yaziTipi: tip, renk: renk ?? satir.renk)
    }

    /// Dolgulu dikdörtgen (beyaz örtü / düzeltme kutusu) ekler; sayfa içeriğinin üstüne çizilir.
    public func ortuEkle(sayfa i: Int, kutu: CGRect, renk: RGBA = .beyaz) throws {
        try sayfada(i, degistir: true) { sayfa in
            guard let nesne = FPDFPageObj_CreateNewRect(Float(kutu.minX), Float(kutu.minY),
                                                        Float(kutu.width), Float(kutu.height)) else {
                throw KagitHata.pdfium("dikdörtgen oluşturulamadı")
            }
            _ = FPDFPageObj_SetFillColor(nesne, UInt32(renk.r * 255), UInt32(renk.g * 255),
                                         UInt32(renk.b * 255), UInt32(renk.a * 255))
            _ = FPDFPath_SetDrawMode(nesne, 1, 0)
            FPDFPage_InsertObject(sayfa, nesne)
        }
    }

    /// Görseli sayfa içeriğine `kutu` içine (PDF koordinatları) yerleştirir. Alfa korunur.
    public func gorselEkle(sayfa i: Int, goruntu: CGImage, kutu: CGRect) throws {
        let genislik = goruntu.width, yukseklik = goruntu.height
        guard genislik > 0, yukseklik > 0 else { throw KagitHata.bosGirdi }
        let satirBayti = genislik * 4
        var pikseller = [UInt8](repeating: 0, count: satirBayti * yukseklik)
        let cizildi = pikseller.withUnsafeMutableBytes { tampon -> Bool in
            guard let ctx = CGContext(data: tampon.baseAddress, width: genislik, height: yukseklik, bitsPerComponent: 8,
                                      bytesPerRow: satirBayti, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
            else { return false }
            ctx.draw(goruntu, in: CGRect(x: 0, y: 0, width: genislik, height: yukseklik))
            return true
        }
        guard cizildi else { throw KagitHata.pdfium("görsel çizilemedi") }
        // PDFium BGRA'yı düz (premultiply'sız) alfa ister.
        var k = 0
        while k < pikseller.count {
            let a = Int(pikseller[k + 3])
            if a > 0 && a < 255 {
                pikseller[k] = UInt8(min(255, Int(pikseller[k]) * 255 / a))
                pikseller[k + 1] = UInt8(min(255, Int(pikseller[k + 1]) * 255 / a))
                pikseller[k + 2] = UInt8(min(255, Int(pikseller[k + 2]) * 255 / a))
            }
            k += 4
        }
        try sayfada(i, degistir: true) { sayfa in
            try pikseller.withUnsafeMutableBytes { tampon in
                guard let bitmap = FPDFBitmap_CreateEx(Int32(genislik), Int32(yukseklik), 4, tampon.baseAddress, Int32(satirBayti)) else {
                    throw KagitHata.pdfium("bitmap oluşturulamadı")
                }
                defer { FPDFBitmap_Destroy(bitmap) }
                guard let nesne = FPDFPageObj_NewImageObj(belge) else { throw KagitHata.pdfium("görsel nesnesi oluşturulamadı") }
                guard FPDFImageObj_SetBitmap(nil, 0, nesne, bitmap) != 0 else {
                    FPDFPageObj_Destroy(nesne)
                    throw KagitHata.pdfium("görsel yüklenemedi")
                }
                _ = FPDFImageObj_SetMatrix(nesne, Double(kutu.width), 0, 0, Double(kutu.height), Double(kutu.minX), Double(kutu.minY))
                FPDFPage_InsertObject(sayfa, nesne)
            }
        }
    }
}
