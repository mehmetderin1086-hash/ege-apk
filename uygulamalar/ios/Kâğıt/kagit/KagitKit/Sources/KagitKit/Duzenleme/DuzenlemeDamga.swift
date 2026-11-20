import CoreGraphics
import Foundation
import PDFKit

/// Damganın içeriği: hazır/özel metin damgası, görsel (imza, fotoğraf) ya da örtü kutusu.
public struct DamgaTanimi: Codable, Sendable, Hashable, Identifiable {
    public enum Tur: String, Codable, Sendable { case metin, gorsel, ortu }

    public var id: UUID
    public var tur: Tur
    /// Damga metni (büyük harf), `tur == .metin` için.
    public var metin: String
    /// Metnin altındaki küçük satır (tarih, ad).
    public var altMetin: String?
    public var renk: RGBA
    public var cerceve: Bool
    /// PNG verisi, `tur == .gorsel` için.
    public var gorselVeri: Data?

    public init(id: UUID = UUID(), tur: Tur = .metin, metin: String = "", altMetin: String? = nil,
                renk: RGBA = .kirmizi, cerceve: Bool = true, gorselVeri: Data? = nil) {
        self.id = id
        self.tur = tur
        self.metin = metin
        self.altMetin = altMetin
        self.renk = renk
        self.cerceve = cerceve
        self.gorselVeri = gorselVeri
    }

    /// Hazır damgalar.
    public static let hazirlar: [DamgaTanimi] = [
        ("ONAYLANDI", RGBA.yesil), ("TASLAK", RGBA.mavi), ("GİZLİ", RGBA.kirmizi),
        ("ÖRNEK", RGBA(0.9, 0.5, 0.05)), ("CEVAP ANAHTARI", RGBA(0.45, 0.2, 0.7)), ("İNCELENDİ", RGBA.yesil),
    ].map { DamgaTanimi(metin: $0.0, renk: $0.1) }

    /// Bugünün tarihini (ve varsa adı) taşıyan damga.
    public static func tarihDamgasi(tarih: Date = Date(), ad: String = "") -> DamgaTanimi {
        let bicim = DateFormatter()
        bicim.locale = Locale(identifier: "tr_TR")
        bicim.dateFormat = "d MMMM yyyy"
        return DamgaTanimi(metin: bicim.string(from: tarih).uppercased(with: Locale(identifier: "tr_TR")),
                           altMetin: ad.isEmpty ? nil : ad, renk: .mavi)
    }

    /// Varsayılan boyut (puan) — metin uzunluğuna göre.
    public func varsayilanBoyut() -> CGSize {
        switch tur {
        case .metin:
            let punto: CGFloat = 22
            let g = PDFCizim.genislik(metin, punto: punto, yaziTipi: "Helvetica-Bold") + 28
            return CGSize(width: max(g, 90), height: altMetin == nil ? 40 : 56)
        case .gorsel:
            guard let v = gorselVeri, let r = PDFCizim.goruntuYukle(v, enBuyukKenar: 512) else { return CGSize(width: 120, height: 60) }
            let oran = CGFloat(r.width) / CGFloat(max(r.height, 1))
            let g: CGFloat = 140
            return CGSize(width: g, height: g / max(oran, 0.05))
        case .ortu:
            return CGSize(width: 120, height: 24)
        }
    }

    /// Damgayı `kutu` içine çizer (CTM sayfa koordinatındadır; kutu ctx koordinatındaki yeri).
    public func ciz(_ ctx: CGContext, kutu: CGRect) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        switch tur {
        case .ortu:
            ctx.setFillColor(renk.cgColor)
            ctx.fill(kutu)
        case .gorsel:
            guard let v = gorselVeri, let r = PDFCizim.goruntuYukle(v) else { return }
            ctx.interpolationQuality = .high
            ctx.draw(r, in: kutu)
        case .metin:
            let kalinlik = max(1.5, min(kutu.height * 0.06, 3))
            if cerceve {
                ctx.setStrokeColor(renk.cgColor)
                ctx.setLineWidth(kalinlik)
                let yol = CGPath(roundedRect: kutu.insetBy(dx: kalinlik / 2, dy: kalinlik / 2),
                                 cornerWidth: 5, cornerHeight: 5, transform: nil)
                ctx.addPath(yol)
                ctx.strokePath()
            }
            let ana = altMetin == nil ? kutu.height * 0.55 : kutu.height * 0.4
            var punto = ana
            let ic = kutu.width - 16
            let g = PDFCizim.genislik(metin, punto: punto, yaziTipi: "Helvetica-Bold")
            if g > ic, g > 0 { punto *= ic / g }
            let yOrta = altMetin == nil ? kutu.midY - punto * 0.35 : kutu.midY + kutu.height * 0.05
            PDFCizim.metin(metin, ctx, nokta: CGPoint(x: kutu.midX, y: yOrta), punto: punto, renk: renk.cgColor,
                           yaziTipi: "Helvetica", hiza: .orta, kalin: true)
            if let altMetin {
                let kucuk = min(kutu.height * 0.22, 11)
                PDFCizim.metin(altMetin, ctx, nokta: CGPoint(x: kutu.midX, y: kutu.minY + kutu.height * 0.14),
                               punto: kucuk, renk: renk.cgColor, hiza: .orta)
            }
        }
    }

    /// Damganın saydam zeminli yüksek çözünürlüklü görüntüsü (kayıtta içeriğe işlemek için).
    public func goruntu(boyut: CGSize, olcek: CGFloat = 4) -> CGImage? {
        let g = max(1, Int((boyut.width * olcek).rounded())), y = max(1, Int((boyut.height * olcek).rounded()))
        guard let ctx = CGContext(data: nil, width: g, height: y, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: olcek, y: olcek)
        ciz(ctx, kutu: CGRect(origin: .zero, size: boyut))
        return ctx.makeImage()
    }
}

/// Sayfada görünen, taşınıp yeniden boyutlandırılabilen damga. Kaydederken PDFKit'in alt sınıf çizimini
/// saklamasına güvenilmez: `DamgaIsleme.veri` bu açıklamaları sayfa içeriğine işler.
public final class KagitDamgasi: PDFAnnotation {
    public var tanim: DamgaTanimi = DamgaTanimi()

    public init(bounds: CGRect, tanim: DamgaTanimi) {
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
        self.tanim = tanim
        userName = tanim.tur == .ortu ? Isaret.ortu : Isaret.damga(tanim.metin)
    }

    public override init(bounds: CGRect, forType annotationType: PDFAnnotationSubtype, withProperties properties: [AnyHashable: Any]?) {
        super.init(bounds: bounds, forType: annotationType, withProperties: properties)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public override func draw(with box: PDFDisplayBox, in context: CGContext) {
        tanim.ciz(context, kutu: bounds)
    }
}

/// Kayıt öncesi dönüşüm: `KagitDamgasi` açıklamalarını sayfa içeriğine (PDFium) işler.
public enum DamgaIsleme {

    /// Belgenin kayıt verisi. Belgede `KagitDamgasi` varsa bunlar geçici olarak çıkarılır, veri
    /// üretilir, damgalar PDFium ile içeriğe yazılır ve belge özgün hâline döner.
    public static func veri(_ belge: PDFDocument, secenekler: KayitSecenekleri = .init()) throws -> Data {
        var damgalar: [(sayfa: Int, damga: KagitDamgasi)] = []
        for i in 0..<belge.pageCount {
            guard let s = belge.page(at: i) else { continue }
            for a in s.annotations {
                if let d = a as? KagitDamgasi { damgalar.append((i, d)) }
            }
        }
        guard !damgalar.isEmpty else { return try Belge.veri(belge, secenekler: secenekler) }

        for (i, d) in damgalar { belge.page(at: i)?.removeAnnotation(d) }
        let ham: Data
        do {
            ham = try Belge.veri(belge, secenekler: secenekler)
        } catch {
            for (i, d) in damgalar { belge.page(at: i)?.addAnnotation(d) }
            throw error
        }
        for (i, d) in damgalar { belge.page(at: i)?.addAnnotation(d) }

        // Parola korumalı veriyi PDFium'a açabilmek için parola gerekir.
        let pdfium = try PdfiumBelge(veri: ham, parola: secenekler.kullaniciParolasi)
        for (i, d) in damgalar {
            let kutu = d.bounds
            switch d.tanim.tur {
            case .ortu:
                try pdfium.ortuEkle(sayfa: i, kutu: kutu, renk: d.tanim.renk)
            case .metin, .gorsel:
                guard let g = d.tanim.goruntu(boyut: kutu.size) else { continue }
                try pdfium.gorselEkle(sayfa: i, goruntu: g, kutu: kutu)
            }
        }
        let cikti = try pdfium.kaydet()
        // PDFium güvenliği kaldırarak yazar: parola/izin isteniyorsa PDFKit ile yeniden korur.
        guard secenekler.kullaniciParolasi != nil || secenekler.sahipParolasi != nil || secenekler.izinler != nil else { return cikti }
        guard let yeni = PDFDocument(data: cikti) else { throw KagitHata.dogrulamaBasarisiz("damgalı çıktı açılamadı") }
        return try Belge.veri(yeni, secenekler: secenekler)
    }
}
