import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision

/// Taranan sayfa filtreleri.
public enum TaramaFiltresi: String, CaseIterable, Sendable, Identifiable {
    case ozgun, otomatikRenk, gri, siyahBeyaz, fotograf
    public var id: String { rawValue }
    public var ad: String {
        switch self {
        case .ozgun: "Özgün"
        case .otomatikRenk: "Otomatik renk"
        case .gri: "Gri"
        case .siyahBeyaz: "Siyah-beyaz"
        case .fotograf: "Fotoğraf"
        }
    }
}

/// Dört köşe. Koordinatlar görüntüye göre normalize (0...1) ve ÜST SOL köşe başlangıçlıdır
/// (arayüz koordinatlarıyla aynı).
public struct Dortgen: Sendable, Equatable {
    public var ustSol: CGPoint
    public var ustSag: CGPoint
    public var altSag: CGPoint
    public var altSol: CGPoint

    public init(ustSol: CGPoint, ustSag: CGPoint, altSag: CGPoint, altSol: CGPoint) {
        self.ustSol = ustSol; self.ustSag = ustSag; self.altSag = altSag; self.altSol = altSol
    }

    public static let tam = Dortgen(ustSol: CGPoint(x: 0, y: 0), ustSag: CGPoint(x: 1, y: 0),
                                    altSag: CGPoint(x: 1, y: 1), altSol: CGPoint(x: 0, y: 1))

    /// Köşeler sırayla: üst sol, üst sağ, alt sağ, alt sol.
    public var koseler: [CGPoint] { [ustSol, ustSag, altSag, altSol] }

    /// Çokgen alanı (normalize birim kare = 1).
    public var alan: Double {
        let k = koseler
        var a = 0.0
        for i in 0..<4 {
            let p = k[i], q = k[(i + 1) % 4]
            a += Double(p.x * q.y - q.x * p.y)
        }
        return abs(a) / 2
    }

    /// Dışbükey ve yeterince büyük mü (perspektif düzeltmesi için güvenli).
    public var gecerli: Bool {
        guard alan > 0.02 else { return false }
        let k = koseler
        var isaret = 0
        for i in 0..<4 {
            let a = k[i], b = k[(i + 1) % 4], c = k[(i + 2) % 4]
            let z = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if z == 0 { return false }
            let s = z > 0 ? 1 : -1
            if isaret == 0 { isaret = s } else if isaret != s { return false }
        }
        return true
    }
}

/// Tarama görüntü işlemleri (CoreImage + Vision): filtre, döndürme, perspektif düzeltme, köşe algılama.
public enum TaramaIslemleri {
    nonisolated(unsafe) static let baglam = CIContext(options: [.cacheIntermediates: false])
    static let renkUzayi = CGColorSpace(name: CGColorSpace.sRGB)!

    // MARK: - Filtreler

    public static func uygula(_ goruntu: CGImage, filtre: TaramaFiltresi, golgeTemizle: Bool = false) -> CGImage {
        var ci = CIImage(cgImage: goruntu)
        let kapsam = ci.extent
        switch filtre {
        case .ozgun:
            if golgeTemizle { ci = golge(ci) }
        case .otomatikRenk:
            ci = golge(ci)
            ci = seviyeler(ci, alt: 0.0, ust: 0.96)
            ci = renkAyari(ci, doygunluk: 1.12, kontrast: 1.08, parlaklik: 0)
        case .gri:
            ci = renkAyari(ci, doygunluk: 0, kontrast: 1, parlaklik: 0)
            ci = golge(ci)
            ci = seviyeler(ci, alt: 0.04, ust: 0.95)
        case .siyahBeyaz:
            ci = renkAyari(ci, doygunluk: 0, kontrast: 1, parlaklik: 0)
            // Uyarlamalı eşik: yerel ortalamaya bölüp (gölge/aydınlık farkını yok eder) keskin eşik uygula.
            ci = golge(ci)
            ci = seviyeler(ci, alt: 0.60, ust: 0.84)
        case .fotograf:
            for f in ci.autoAdjustmentFilters(options: [.redEye: false]) {
                f.setValue(ci, forKey: kCIInputImageKey)
                if let o = f.outputImage { ci = o }
            }
            if golgeTemizle { ci = golge(ci) }
        }
        guard let cikti = baglam.createCGImage(ci, from: kapsam, format: .RGBA8, colorSpace: renkUzayi) else { return goruntu }
        return (filtre == .gri || filtre == .siyahBeyaz) ? griya(cikti) ?? cikti : cikti
    }

    /// Gölge / eşitsiz aydınlatma giderme: görüntüyü kendi geniş bulanıklığına böler.
    static func golge(_ ci: CIImage) -> CIImage {
        let kapsam = ci.extent
        let sigma = max(kapsam.width, kapsam.height) / 24
        let arka = ci.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: kapsam)
        let f = CIFilter.divideBlendMode()
        // CIDivideBlendMode: inputImage ÷ backgroundImage değil, yönü ters (arka plan ÷ girdi) çalışır;
        // bu yüzden girdi=bulanık, arka plan=özgün verilir (sonuç = özgün ÷ bulanık, `TaramaIslemleriTestleri` ölçer).
        f.inputImage = arka
        f.backgroundImage = ci
        return (f.outputImage ?? ci).cropped(to: kapsam)
    }

    static func renkAyari(_ ci: CIImage, doygunluk: Float, kontrast: Float, parlaklik: Float) -> CIImage {
        let f = CIFilter.colorControls()
        f.inputImage = ci
        f.saturation = doygunluk
        f.contrast = kontrast
        f.brightness = parlaklik
        return f.outputImage ?? ci
    }

    /// Doğrusal seviye: `alt` ve altı siyah, `ust` ve üstü beyaz.
    static func seviyeler(_ ci: CIImage, alt: CGFloat, ust: CGFloat) -> CIImage {
        let a = 1 / (ust - alt)
        let b = -alt * a
        let f = CIFilter.colorMatrix()
        f.inputImage = ci
        f.rVector = CIVector(x: a, y: 0, z: 0, w: 0)
        f.gVector = CIVector(x: 0, y: a, z: 0, w: 0)
        f.bVector = CIVector(x: 0, y: 0, z: a, w: 0)
        f.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        f.biasVector = CIVector(x: b, y: b, z: b, w: 0)
        return f.outputImage ?? ci
    }

    static func griya(_ g: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: g.width, height: g.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(g, in: CGRect(x: 0, y: 0, width: g.width, height: g.height))
        return ctx.makeImage()
    }

    // MARK: - Döndürme, boyut

    /// Saat yönünde 90'ın katı kadar döndürür.
    public static func dondur(_ goruntu: CGImage, derece: Int) -> CGImage {
        let d = ((derece % 360) + 360) % 360
        guard d != 0 else { return goruntu }
        let yon: CGImagePropertyOrientation = d == 90 ? .right : (d == 180 ? .down : .left)
        let ci = CIImage(cgImage: goruntu).oriented(yon)
        return baglam.createCGImage(ci, from: ci.extent, format: .RGBA8, colorSpace: renkUzayi) ?? goruntu
    }

    /// En uzun kenarı `enBuyukKenar` pikseli aşmayacak biçimde küçültür (büyütmez).
    public static func kucult(_ goruntu: CGImage, enBuyukKenar: CGFloat) -> CGImage {
        let uzun = CGFloat(max(goruntu.width, goruntu.height))
        guard uzun > enBuyukKenar else { return goruntu }
        let o = enBuyukKenar / uzun
        let g = max(1, Int((CGFloat(goruntu.width) * o).rounded())), y = max(1, Int((CGFloat(goruntu.height) * o).rounded()))
        guard let ctx = CGContext(data: nil, width: g, height: y, bitsPerComponent: 8, bytesPerRow: 0, space: renkUzayi,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return goruntu }
        ctx.interpolationQuality = .high
        ctx.draw(goruntu, in: CGRect(x: 0, y: 0, width: g, height: y))
        return ctx.makeImage() ?? goruntu
    }

    // MARK: - Kırpma / perspektif

    /// Dörtgenin içini düzleştirip dikdörtgen yapar (CIPerspectiveCorrection). Dörtgen tüm
    /// görüntüyse görüntü olduğu gibi döner.
    public static func perspektifDuzelt(_ goruntu: CGImage, dortgen: Dortgen) -> CGImage {
        guard dortgen != .tam, dortgen.gecerli else { return goruntu }
        let g = CGFloat(goruntu.width), y = CGFloat(goruntu.height)
        func nokta(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * g, y: (1 - p.y) * y) }
        let f = CIFilter.perspectiveCorrection()
        f.inputImage = CIImage(cgImage: goruntu)
        f.topLeft = nokta(dortgen.ustSol)
        f.topRight = nokta(dortgen.ustSag)
        f.bottomRight = nokta(dortgen.altSag)
        f.bottomLeft = nokta(dortgen.altSol)
        guard let cikti = f.outputImage, cikti.extent.width > 1, cikti.extent.height > 1,
              let sonuc = baglam.createCGImage(cikti, from: cikti.extent, format: .RGBA8, colorSpace: renkUzayi) else { return goruntu }
        return sonuc
    }

    /// Belgenin dört köşesini bulur (Vision belge bölütleme; olmazsa dikdörtgen algılama).
    public static func kenarlariBul(_ goruntu: CGImage) async -> Dortgen? {
        func don(_ ul: CGPoint, _ ur: CGPoint, _ lr: CGPoint, _ ll: CGPoint) -> Dortgen? {
            // Vision: sol alt köken → üst sol köken
            let d = Dortgen(ustSol: CGPoint(x: ul.x, y: 1 - ul.y), ustSag: CGPoint(x: ur.x, y: 1 - ur.y),
                            altSag: CGPoint(x: lr.x, y: 1 - lr.y), altSol: CGPoint(x: ll.x, y: 1 - ll.y))
            return d.gecerli ? d : nil
        }
        if let gozlem = try? await DetectDocumentSegmentationRequest().perform(on: goruntu),
           let d = don(gozlem.topLeft.cgPoint, gozlem.topRight.cgPoint, gozlem.bottomRight.cgPoint, gozlem.bottomLeft.cgPoint) {
            return d
        }
        var istek = DetectRectanglesRequest()
        istek.maximumObservations = 1
        istek.minimumAspectRatio = 0.3
        istek.minimumSize = 0.25
        istek.minimumConfidence = 0.5
        if let r = try? await istek.perform(on: goruntu).first,
           let d = don(r.topLeft.cgPoint, r.topRight.cgPoint, r.bottomRight.cgPoint, r.bottomLeft.cgPoint) {
            return d
        }
        return nil
    }

    // MARK: - Ad önerisi

    /// OCR'ın ilk anlamlı satırı + tarih: "Fatura No 2026 - 2026-10-27".
    public static func adOner(satirlar: [OCRSatiri], tarih: Date = Date()) -> String {
        let bicim = DateFormatter()
        bicim.locale = Locale(identifier: "en_US_POSIX")
        bicim.dateFormat = "yyyy-MM-dd"
        let gun = bicim.string(from: tarih)
        for s in satirlar {
            let t = s.metin.trimmingCharacters(in: .whitespacesAndNewlines)
            let harf = t.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            guard harf >= 4, Double(harf) / Double(max(t.count, 1)) >= 0.4 else { continue }
            var ad = String(t.prefix(40)).trimmingCharacters(in: .whitespaces)
            if let son = ad.split(separator: " ").last, ad.count >= 40, son.count < 3 { ad = ad.replacingOccurrences(of: " \(son)", with: "") }
            return "\(TurkceMetin.dosyaAdi(ad, varsayilan: "Tarama")) \(gun)"
        }
        bicim.dateFormat = "yyyy-MM-dd HH.mm"
        return "Tarama \(bicim.string(from: tarih))"
    }
}
