import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public struct GorselPDFAyari: Sendable, Equatable {
    public enum SayfaBoyutu: String, CaseIterable, Sendable, Identifiable {
        case gorselBoyutu, a4, letter
        public var id: String { rawValue }
        public var ad: String {
            switch self {
            case .gorselBoyutu: "Görsel boyutu"
            case .a4: "A4"
            case .letter: "Letter"
            }
        }
    }
    public enum Yon: String, CaseIterable, Sendable, Identifiable {
        case otomatik, dikey, yatay
        public var id: String { rawValue }
        public var ad: String {
            switch self {
            case .otomatik: "Otomatik"
            case .dikey: "Dikey"
            case .yatay: "Yatay"
            }
        }
    }

    public var sayfaBoyutu: SayfaBoyutu = .a4
    public var yon: Yon = .otomatik
    /// Punto.
    public var kenarBosluk: Double = 0
    /// true: sığdır (kırpmadan), false: doldur (taşanı kırpar).
    public var sigdir = true
    public var jpegKalite: Double = 0.85

    public init() {}
}

public enum BosPDFDeseni: String, CaseIterable, Sendable, Identifiable {
    case bos, cizgili, kareli, noktali, milimetrik
    public var id: String { rawValue }
    public var ad: String {
        switch self {
        case .bos: "Boş"
        case .cizgili: "Çizgili"
        case .kareli: "Kareli"
        case .noktali: "Noktalı"
        case .milimetrik: "Milimetrik"
        }
    }
}

public enum GorselPDF {

    /// Görselleri (JPEG, PNG, HEIC…) sırayla sayfalara yerleştirip tek PDF yapar.
    public static func gorseldenPDF(_ girdiler: [URL], ayar: GorselPDFAyari = .init(), ad: String? = nil,
                                    ilerleme: Ilerleme? = nil) throws -> URL {
        guard !girdiler.isEmpty else { throw KagitHata.bosGirdi }
        let y = PDFCizim.Yazici(baslik: ad)
        var yazilan = 0
        for (i, u) in girdiler.enumerated() {
            try iptalDenetle()
            try autoreleasepool {
                let erisim = u.startAccessingSecurityScopedResource()
                defer { if erisim { u.stopAccessingSecurityScopedResource() } }
                guard let veri = try? Data(contentsOf: u) else { throw KagitHata.acilamadi(u.lastPathComponent) }
                guard let img = PDFCizim.goruntuYukle(veri) else {
                    throw KagitHata.genel("“\(u.lastPathComponent)” görsel olarak açılamadı.")
                }
                // JPEG olarak kodla: PDF'e DCT olarak gömülür (boyut küçük kalır).
                guard let jpeg = PDFCizim.kodla(flatten(img), tur: .jpeg, kalite: ayar.jpegKalite),
                      let kaynak = CGImageSourceCreateWithData(jpeg as CFData, nil),
                      let gomulecek = CGImageSourceCreateImageAtIndex(kaynak, 0, nil) else {
                    throw KagitHata.genel("“\(u.lastPathComponent)” işlenemedi.")
                }
                let gw = CGFloat(img.width), gh = CGFloat(img.height)
                let sayfa = sayfaKutusu(gorsel: CGSize(width: gw, height: gh), ayar: ayar)
                let alan = sayfa.insetBy(dx: CGFloat(ayar.kenarBosluk), dy: CGFloat(ayar.kenarBosluk))
                y.sayfa(sayfa) { ctx in
                    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                    ctx.fill(sayfa)
                    let o = ayar.sigdir ? min(alan.width / gw, alan.height / gh) : max(alan.width / gw, alan.height / gh)
                    let w = gw * o, h = gh * o
                    ctx.saveGState()
                    ctx.clip(to: alan)
                    ctx.draw(gomulecek, in: CGRect(x: alan.midX - w / 2, y: alan.midY - h / 2, width: w, height: h))
                    ctx.restoreGState()
                }
                yazilan += 1
            }
            ilerleme?(Double(i + 1) / Double(girdiler.count))
        }
        let dosyaAdi = ad ?? (girdiler.count == 1 ? girdiler[0].deletingPathExtension().lastPathComponent : "Görseller")
        let hedef = Gecici.dosya("\(dosyaAdi).pdf")
        try Belge.yaz(y.bitir(), hedef, beklenenSayfa: yazilan)
        return hedef
    }

    /// Saydam görseli beyaz zemine yatırır (JPEG alfa taşımaz).
    private static func flatten(_ img: CGImage) -> CGImage {
        guard let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return img }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: img.width, height: img.height))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return ctx.makeImage() ?? img
    }

    static func sayfaKutusu(gorsel: CGSize, ayar: GorselPDFAyari) -> CGRect {
        let yatayGorsel = gorsel.width > gorsel.height
        switch ayar.sayfaBoyutu {
        case .gorselBoyutu:
            // 150 dpi varsay, en uzun kenarı 1200 puntoyla sınırla
            var w = gorsel.width * 72 / 150, h = gorsel.height * 72 / 150
            let k = max(w, h)
            if k > 1200 { w *= 1200 / k; h *= 1200 / k }
            w = max(w, 100); h = max(h, 100)
            return CGRect(x: 0, y: 0, width: w + CGFloat(ayar.kenarBosluk) * 2, height: h + CGFloat(ayar.kenarBosluk) * 2)
        case .a4, .letter:
            let b: PDFCizim.Boyut = ayar.sayfaBoyutu == .a4 ? .a4 : .letter
            let yatay: Bool
            switch ayar.yon {
            case .otomatik: yatay = yatayGorsel
            case .dikey: yatay = false
            case .yatay: yatay = true
            }
            return CGRect(origin: .zero, size: b.yonlu(yatay: yatay))
        }
    }

    // MARK: Boş PDF

    public static func bosPDF(boyut: PDFCizim.Boyut = .a4, yatay: Bool = false, sayfaSayisi: Int = 1,
                              desen: BosPDFDeseni = .bos, ad: String = "Boş PDF") throws -> URL {
        guard (1...500).contains(sayfaSayisi) else { throw KagitHata.genel("Sayfa sayısı 1 ile 500 arasında olmalı.") }
        let kutu = CGRect(origin: .zero, size: boyut.yonlu(yatay: yatay))
        let y = PDFCizim.Yazici(baslik: ad)
        for _ in 0..<sayfaSayisi {
            y.sayfa(kutu) { ctx in deseniCiz(ctx, kutu, desen) }
        }
        let hedef = Gecici.dosya("\(ad).pdf")
        try Belge.yaz(y.bitir(), hedef, beklenenSayfa: sayfaSayisi)
        return hedef
    }

    private static func deseniCiz(_ ctx: CGContext, _ k: CGRect, _ desen: BosPDFDeseni) {
        let gri = CGColor(gray: 0.72, alpha: 1)
        ctx.setStrokeColor(gri)
        ctx.setFillColor(CGColor(gray: 0.55, alpha: 1))
        switch desen {
        case .bos: break
        case .cizgili:
            let adim: CGFloat = 25.5
            ctx.setLineWidth(0.5)
            var yy = k.height - 56.7
            while yy > 28 { ctx.move(to: CGPoint(x: 36, y: yy)); ctx.addLine(to: CGPoint(x: k.width - 36, y: yy)); yy -= adim }
            ctx.strokePath()
        case .kareli:
            let adim: CGFloat = 14.17   // 5 mm
            ctx.setLineWidth(0.4)
            var x = adim * 2
            while x < k.width - adim { ctx.move(to: CGPoint(x: x, y: adim)); ctx.addLine(to: CGPoint(x: x, y: k.height - adim)); x += adim }
            var yy = adim
            while yy < k.height - adim { ctx.move(to: CGPoint(x: adim * 2, y: yy)); ctx.addLine(to: CGPoint(x: x - adim, y: yy)); yy += adim }
            ctx.strokePath()
        case .noktali:
            let adim: CGFloat = 14.17
            var yy = adim * 2
            while yy < k.height - adim {
                var x = adim * 2
                while x < k.width - adim { ctx.fillEllipse(in: CGRect(x: x - 0.6, y: yy - 0.6, width: 1.2, height: 1.2)); x += adim }
                yy += adim
            }
        case .milimetrik:
            let mm: CGFloat = 72 / 25.4
            let sol = (k.width.truncatingRemainder(dividingBy: mm * 10)) / 2
            let alt = (k.height.truncatingRemainder(dividingBy: mm * 10)) / 2
            var i = 0
            var x = sol
            while x <= k.width + 0.1 {
                ctx.setLineWidth(i % 10 == 0 ? 0.6 : (i % 5 == 0 ? 0.35 : 0.18))
                ctx.move(to: CGPoint(x: x, y: alt)); ctx.addLine(to: CGPoint(x: x, y: k.height - alt))
                ctx.strokePath()
                x += mm; i += 1
            }
            i = 0
            var yy = alt
            while yy <= k.height + 0.1 {
                ctx.setLineWidth(i % 10 == 0 ? 0.6 : (i % 5 == 0 ? 0.35 : 0.18))
                ctx.move(to: CGPoint(x: sol, y: yy)); ctx.addLine(to: CGPoint(x: k.width - sol, y: yy))
                ctx.strokePath()
                yy += mm; i += 1
            }
        }
    }
}
