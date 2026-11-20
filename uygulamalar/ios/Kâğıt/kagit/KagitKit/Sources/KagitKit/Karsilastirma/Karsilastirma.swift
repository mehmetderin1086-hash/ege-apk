import CoreGraphics
import Foundation
import PDFKit

public struct SayfaFarki: Sendable, Equatable {
    /// 1 tabanlı sayfa numarası.
    public let sayfa: Int
    public let eklenen: [String]
    public let silinen: [String]
    /// Farklı piksellerin oranı (0...1); sayfa yalnız birinde varsa 1.
    public let gorselFark: Double
    public let yalnizA: Bool
    public let yalnizB: Bool

    public var metinFarkiVar: Bool { !eklenen.isEmpty || !silinen.isEmpty }
    public var farkliMi: Bool { metinFarkiVar || gorselFark >= PDFKarsilastirma.gorselEsik || yalnizA || yalnizB }
}

public struct KarsilastirmaSonucu: Sendable {
    public let sayfaA: Int
    public let sayfaB: Int
    public let farklar: [SayfaFarki]
    /// Rapor PDF'i (istenmişse).
    public let rapor: URL?

    public var farkliSayfalar: [SayfaFarki] { farklar.filter(\.farkliMi) }
    public var ozdesMi: Bool { farkliSayfalar.isEmpty }
    public var toplamEklenen: Int { farklar.reduce(0) { $0 + $1.eklenen.count } }
    public var toplamSilinen: Int { farklar.reduce(0) { $0 + $1.silinen.count } }
    public var ortalamaGorselFark: Double {
        farklar.isEmpty ? 0 : farklar.reduce(0) { $0 + $1.gorselFark } / Double(farklar.count)
    }
}

/// İki PDF'i sayfa sayfa karşılaştırır: metin satırı farkı + görsel piksel farkı.
public enum PDFKarsilastirma {

    /// Bu orandan küçük görsel fark gürültü sayılır.
    public static let gorselEsik = 0.002

    public static func karsilastir(_ a: URL, _ b: URL, parolaA: String? = nil, parolaB: String? = nil,
                                   raporYaz: Bool = true, gorselFark: Bool = true,
                                   ilerleme: Ilerleme? = nil) throws -> KarsilastirmaSonucu {
        let da = try Belge.ac(a, parola: parolaA), db = try Belge.ac(b, parola: parolaB)
        let n = max(da.pageCount, db.pageCount)
        guard n > 0 else { throw KagitHata.bosGirdi }
        var farklar: [SayfaFarki] = []
        var kucukResimler: [Int: CGImage] = [:]
        for i in 0..<n {
            try iptalDenetle()
            autoreleasepool {
                let pa = i < da.pageCount ? da.page(at: i) : nil
                let pb = i < db.pageCount ? db.page(at: i) : nil
                let la = pa.map(satirlar) ?? [], lb = pb.map(satirlar) ?? []
                let fark = lb.difference(from: la)
                var silinen: [String] = [], eklenen: [String] = []
                for degisim in fark {
                    switch degisim {
                    case .remove(let o, let s, _): _ = o; silinen.append(s)
                    case .insert(let o, let s, _): _ = o; eklenen.append(s)
                    }
                }
                var oran = 0.0
                if let pa, let pb {
                    if gorselFark, let (o, resim) = piksellerFarki(pa, pb) {
                        oran = o
                        if raporYaz, o >= gorselEsik { kucukResimler[i] = resim }
                    }
                } else {
                    oran = 1
                }
                farklar.append(SayfaFarki(sayfa: i + 1, eklenen: eklenen, silinen: silinen, gorselFark: oran,
                                          yalnizA: pb == nil, yalnizB: pa == nil))
            }
            ilerleme?(Double(i + 1) / Double(n) * (raporYaz ? 0.85 : 1))
        }
        var rapor: URL?
        if raporYaz {
            rapor = try raporUret(a: a, b: b, sayfaA: da.pageCount, sayfaB: db.pageCount, farklar: farklar, resimler: kucukResimler)
            ilerleme?(1)
        }
        return KarsilastirmaSonucu(sayfaA: da.pageCount, sayfaB: db.pageCount, farklar: farklar, rapor: rapor)
    }

    static func satirlar(_ s: PDFPage) -> [String] {
        (s.string ?? "").components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
            .filter { !$0.isEmpty }
    }

    /// İki sayfayı ortak bir tuvale çizip farklı piksel oranını ve kırmızı işaretli bir kopyayı verir.
    static func piksellerFarki(_ a: PDFPage, _ b: PDFPage) -> (Double, CGImage)? {
        let ga = IsYardimcisi.gorunenBoyut(a)
        guard ga.width > 0, ga.height > 0 else { return nil }
        let w = 360, h = max(1, Int((360 * ga.height / ga.width).rounded()))
        guard let ia = tuval(a, w, h), let ib = tuval(b, w, h) else { return nil }
        var fark = 0
        var cikti = [UInt8](repeating: 255, count: w * h * 4)
        for p in 0..<(w * h) {
            let o = p * 4
            let d = abs(Int(ia[o]) - Int(ib[o])) + abs(Int(ia[o + 1]) - Int(ib[o + 1])) + abs(Int(ia[o + 2]) - Int(ib[o + 2]))
            if d > 96 {
                fark += 1
                cikti[o] = 220; cikti[o + 1] = 30; cikti[o + 2] = 30
            } else {
                // Soluk gri: özgün sayfa
                let g = UInt8(min(255, 150 + Int(ib[o]) * 105 / 255))
                cikti[o] = g; cikti[o + 1] = g; cikti[o + 2] = g
            }
        }
        let oran = Double(fark) / Double(w * h)
        guard let ctx = CGContext(data: &cikti, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let img = ctx.makeImage() else { return nil }
        return (oran, img)
    }

    private static func tuval(_ s: PDFPage, _ w: Int, _ h: Int) -> [UInt8]? {
        var bellek = [UInt8](repeating: 255, count: w * h * 4)
        guard let ctx = CGContext(data: &bellek, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        IsYardimcisi.sigdirCiz(s, ctx, hedef: CGRect(x: 0, y: 0, width: w, height: h))
        return bellek
    }

    // MARK: Rapor

    private enum Oge {
        case baslik(String)
        case satir(String, CGColor)
        case gorsel(CGImage)
        case bosluk(CGFloat)
    }

    private static func raporUret(a: URL, b: URL, sayfaA: Int, sayfaB: Int, farklar: [SayfaFarki], resimler: [Int: CGImage]) throws -> URL {
        let yesil = CGColor(red: 0.05, green: 0.5, blue: 0.2, alpha: 1)
        let kirmizi = CGColor(red: 0.78, green: 0.1, blue: 0.1, alpha: 1)
        let siyah = CGColor(gray: 0.1, alpha: 1)
        let gri = CGColor(gray: 0.4, alpha: 1)
        let farkli = farklar.filter(\.farkliMi)

        var ogeler: [Oge] = [
            .baslik("PDF karşılaştırma raporu"),
            .satir("Eski (A): \(a.lastPathComponent) · \(sayfaA) sayfa", siyah),
            .satir("Yeni (B): \(b.lastPathComponent) · \(sayfaB) sayfa", siyah),
            .bosluk(6),
        ]
        if farkli.isEmpty {
            ogeler.append(.satir("İki belge arasında fark bulunmadı.", yesil))
        } else {
            let ek = farklar.reduce(0) { $0 + $1.eklenen.count }, sil = farklar.reduce(0) { $0 + $1.silinen.count }
            ogeler.append(.satir("\(farkli.count) sayfada fark var · \(ek) satır eklendi · \(sil) satır silindi", siyah))
            ogeler.append(.satir("Yeşil + : B'de eklenen satır · Kırmızı − : A'dan silinen satır · Kırmızı görsel: farklı pikseller", gri))
        }
        for f in farkli {
            ogeler.append(.bosluk(8))
            var baslik = "Sayfa \(f.sayfa)"
            if f.yalnizA { baslik += " — yalnız A'da var" }
            else if f.yalnizB { baslik += " — yalnız B'de var" }
            else { baslik += " — görsel fark %\(String(format: "%.1f", f.gorselFark * 100))" }
            ogeler.append(.baslik(baslik))
            for s in f.silinen.prefix(80) { ogeler.append(.satir("− " + s, kirmizi)) }
            for s in f.eklenen.prefix(80) { ogeler.append(.satir("+ " + s, yesil)) }
            let fazla = max(0, f.silinen.count - 80) + max(0, f.eklenen.count - 80)
            if fazla > 0 { ogeler.append(.satir("… ve \(fazla) satır daha", gri)) }
            if let r = resimler[f.sayfa - 1] { ogeler.append(.gorsel(r)) }
        }

        let kutu = CGRect(origin: .zero, size: PDFCizim.Boyut.a4.boyut)
        let kenar: CGFloat = 50, genislik = kutu.width - 2 * kenar
        func yukseklik(_ o: Oge) -> CGFloat {
            switch o {
            case .baslik: 26
            case .satir(let t, _): PDFCizim.paragrafYuksekligi(t, genislik: genislik, punto: 9.5) + 3
            case .gorsel(let g): min(220, genislik * CGFloat(g.height) / CGFloat(g.width) * 0.45) + 6
            case .bosluk(let h): h
            }
        }
        let y = PDFCizim.Yazici(baslik: "Karşılaştırma raporu")
        var i = 0
        var sayfaSayisi = 0
        while i < ogeler.count {
            y.sayfa(kutu) { ctx in
                var imlec = kutu.height - kenar
                var bu = 0
                while i < ogeler.count {
                    let o = ogeler[i]
                    let h = yukseklik(o)
                    if imlec - h < kenar, bu > 0 { break }
                    switch o {
                    case .baslik(let t):
                        PDFCizim.metin(t, ctx, nokta: CGPoint(x: kenar, y: imlec - 16), punto: 14, kalin: true)
                    case .satir(let t, let renk):
                        PDFCizim.paragraf(t, ctx, kutu: CGRect(x: kenar, y: imlec - h + 3, width: genislik, height: h - 3),
                                          punto: 9.5, renk: renk)
                    case .gorsel(let g):
                        let gh = h - 6
                        let gw = gh * CGFloat(g.width) / CGFloat(g.height)
                        ctx.draw(g, in: CGRect(x: kenar, y: imlec - gh - 3, width: gw, height: gh))
                    case .bosluk: break
                    }
                    imlec -= h
                    i += 1
                    bu += 1
                }
            }
            sayfaSayisi += 1
            if sayfaSayisi > 400 { break }
        }
        let hedef = Gecici.dosya("Karşılaştırma raporu.pdf")
        try Belge.yaz(y.bitir(), hedef, beklenenSayfa: sayfaSayisi)
        return hedef
    }
}
