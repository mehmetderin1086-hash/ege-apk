import CoreGraphics
import Foundation
import PDFKit

/// Kenar kırpma biçimi.
public enum KirpmaKipi: Sendable, Equatable {
    /// Beyaz kenarları otomatik bulur; içerik çevresinde `pay` punto boşluk bırakır.
    case otomatik(pay: Double)
    /// Her kenardan verilen punto kadar içeri kırpar (görünen yöne göre).
    case elle(ust: Double, alt: Double, sol: Double, sag: Double)
}

/// Kâğıt başına çok sayfa ve kitapçık baskı düzenleri.
public enum SayfaYerlesimi {

    // MARK: Kenar kırp

    public static func kenarKirp(_ giris: URL, kip: KirpmaKipi, aralik: String = "", parola: String? = nil,
                                 ilerleme: Ilerleme? = nil) throws -> URL {
        let b = try Belge.ac(giris, parola: parola)
        let idx = try SayfaAraligi.coz(aralik, sayfaSayisi: b.pageCount)
        for (k, i) in idx.enumerated() {
            try iptalDenetle()
            autoreleasepool {
                guard let s = b.page(at: i) else { return }
                let kutu = s.bounds(for: .cropBox)
                var yeni: CGRect
                switch kip {
                case .otomatik(let pay):
                    yeni = icerikKutusu(s, pay: pay) ?? kutu
                case .elle(let ust, let alt, let sol, let sag):
                    // Görünen yöne göre boşlukları döndürmeden önceki (ham) uzaya çevir.
                    yeni = hamKutu(gorunen: gorunenKirp(IsYardimcisi.gorunenBoyut(s), ust: ust, alt: alt, sol: sol, sag: sag), sayfa: s)
                }
                yeni = yeni.intersection(kutu)
                guard yeni.width >= 8, yeni.height >= 8 else { return }
                s.setBounds(yeni, for: .cropBox)
                s.setBounds(yeni, for: .mediaBox)
            }
            ilerleme?(Double(k + 1) / Double(idx.count))
        }
        return try IsYardimcisi.yaz(b, IsYardimcisi.cikti(giris, "kırpıldı"))
    }

    private static func gorunenKirp(_ g: CGSize, ust: Double, alt: Double, sol: Double, sag: Double) -> CGRect {
        CGRect(x: sol, y: alt, width: max(0, g.width - sol - sag), height: max(0, g.height - ust - alt))
    }

    /// Görünen (döndürülmüş, sol alt köken) dikdörtgeni sayfanın ham koordinatına çevirir.
    static func hamKutu(gorunen r: CGRect, sayfa: PDFPage) -> CGRect {
        let kutu = sayfa.bounds(for: .cropBox)
        let w = kutu.width, h = kutu.height
        func ham(_ vx: CGFloat, _ vy: CGFloat) -> CGPoint {
            switch ((sayfa.rotation % 360) + 360) % 360 {
            case 90: CGPoint(x: w - vy, y: vx)
            case 180: CGPoint(x: w - vx, y: h - vy)
            case 270: CGPoint(x: vy, y: h - vx)
            default: CGPoint(x: vx, y: vy)
            }
        }
        let a = ham(r.minX, r.minY), c = ham(r.maxX, r.maxY)
        return CGRect(x: kutu.minX + min(a.x, c.x), y: kutu.minY + min(a.y, c.y),
                      width: abs(a.x - c.x), height: abs(a.y - c.y))
    }

    /// Sayfayı düşük çözünürlükte çizip beyaz olmayan piksellerin sınır kutusunu bulur (ham koordinat).
    static func icerikKutusu(_ sayfa: PDFPage, pay: Double) -> CGRect? {
        let dpi: CGFloat = 60
        guard let img = PDFCizim.goruntu(sayfa, dpi: dpi) else { return nil }
        let w = img.width, h = img.height
        var bellek = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &bellek, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                let p = (y * w + x) * 4
                if bellek[p] < 245 || bellek[p + 1] < 245 || bellek[p + 2] < 245 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // Bellek satır 0 = görüntünün üstü. Görünen uzay: sol alt köken.
        let o = 72 / dpi
        let vx0 = CGFloat(minX) * o - pay, vx1 = CGFloat(maxX + 1) * o + pay
        let vy0 = CGFloat(h - 1 - maxY) * o - pay, vy1 = CGFloat(h - minY) * o + pay
        let gorunen = CGRect(x: vx0, y: vy0, width: vx1 - vx0, height: vy1 - vy0)
        return hamKutu(gorunen: gorunen, sayfa: sayfa)
    }

    // MARK: Kâğıt başına N sayfa

    /// Kâğıt başına 2, 4, 6 ya da 9 sayfa. 2 ve 6 yatay, 4 ve 9 dikey kâğıtta düzenlenir.
    public static func nUp(_ giris: URL, sayfaBasina: Int, kenarCizgisi: Bool = true, kagit: PDFCizim.Boyut = .a4,
                           parola: String? = nil, ilerleme: Ilerleme? = nil) throws -> URL {
        let (sutun, satir, yatay): (Int, Int, Bool)
        switch sayfaBasina {
        case 2: (sutun, satir, yatay) = (2, 1, true)
        case 4: (sutun, satir, yatay) = (2, 2, false)
        case 6: (sutun, satir, yatay) = (3, 2, true)
        case 9: (sutun, satir, yatay) = (3, 3, false)
        default: throw KagitHata.genel("Kâğıt başına 2, 4, 6 ya da 9 sayfa seçilebilir.")
        }
        let b = try Belge.ac(giris, parola: parola)
        let n = b.pageCount
        guard n > 0 else { throw KagitHata.bosGirdi }
        let kutu = CGRect(origin: .zero, size: kagit.yonlu(yatay: yatay))
        let y = PDFCizim.Yazici(baslik: giris.deletingPathExtension().lastPathComponent)
        let kenar: CGFloat = 18, bosluk: CGFloat = 8
        let hucreG = (kutu.width - 2 * kenar - CGFloat(sutun - 1) * bosluk) / CGFloat(sutun)
        let hucreY = (kutu.height - 2 * kenar - CGFloat(satir - 1) * bosluk) / CGFloat(satir)
        let kagitSayisi = (n + sayfaBasina - 1) / sayfaBasina
        for k in 0..<kagitSayisi {
            try iptalDenetle()
            autoreleasepool {
                y.sayfa(kutu) { ctx in
                    for h in 0..<sayfaBasina {
                        guard let s = b.page(at: k * sayfaBasina + h) else { continue }
                        let c = h % sutun, r = h / sutun
                        let hucre = CGRect(x: kenar + CGFloat(c) * (hucreG + bosluk),
                                           y: kutu.height - kenar - CGFloat(r + 1) * hucreY - CGFloat(r) * bosluk,
                                           width: hucreG, height: hucreY)
                        let g = IsYardimcisi.gorunenBoyut(s)
                        let o = min(hucre.width / g.width, hucre.height / g.height)
                        let hedef = CGRect(x: hucre.midX - g.width * o / 2, y: hucre.midY - g.height * o / 2,
                                           width: g.width * o, height: g.height * o)
                        IsYardimcisi.sigdirCiz(s, ctx, hedef: hedef)
                        if kenarCizgisi {
                            ctx.setStrokeColor(CGColor(gray: 0.55, alpha: 1))
                            ctx.setLineWidth(0.6)
                            ctx.stroke(hedef)
                        }
                    }
                }
            }
            ilerleme?(Double(k + 1) / Double(kagitSayisi))
        }
        return try SayfaIslemleri.yazVeri(y.bitir(), IsYardimcisi.cikti(giris, "\(sayfaBasina) sayfa bir kâğıtta"), sayfa: kagitSayisi)
    }

    // MARK: Kitapçık

    public enum KitapcikKipi: Sendable, Equatable {
        /// A4 kâğıda katlamalı kitapçık (ortadan katlanıp zımbalanır), çift taraflı baskı, kısa kenardan çevir.
        case katlamali
        /// Ardışık iki sayfa yan yana (A5 + A5 → A4 yatay), kitapçık sırası olmadan.
        case ikiYukari
    }

    /// Katlamalı kitapçık için kâğıt yüzlerinin sayfa sırası (0 tabanlı; -1 = boş). Her çift: (sol, sağ).
    public static func kitapcikSirasi(sayfaSayisi n: Int) -> [(Int, Int)] {
        let toplam = (n + 3) / 4 * 4
        func s(_ i: Int) -> Int { i < n ? i : -1 }
        var yuzler: [(Int, Int)] = []
        for k in 0..<(toplam / 4) {
            yuzler.append((s(toplam - 1 - 2 * k), s(2 * k)))
            yuzler.append((s(2 * k + 1), s(toplam - 2 - 2 * k)))
        }
        return yuzler
    }

    public static func kitapcikBaski(_ giris: URL, kip: KitapcikKipi = .katlamali, kagit: PDFCizim.Boyut = .a4,
                                     parola: String? = nil, ilerleme: Ilerleme? = nil) throws -> URL {
        let b = try Belge.ac(giris, parola: parola)
        let n = b.pageCount
        guard n > 0 else { throw KagitHata.bosGirdi }
        let yuzler: [(Int, Int)]
        switch kip {
        case .katlamali: yuzler = kitapcikSirasi(sayfaSayisi: n)
        case .ikiYukari:
            yuzler = stride(from: 0, to: n, by: 2).map { ($0, $0 + 1 < n ? $0 + 1 : -1) }
        }
        let kutu = CGRect(origin: .zero, size: kagit.yonlu(yatay: true))
        let yarim = kutu.width / 2
        let y = PDFCizim.Yazici(baslik: giris.deletingPathExtension().lastPathComponent)
        for (k, yuz) in yuzler.enumerated() {
            try iptalDenetle()
            autoreleasepool {
                y.sayfa(kutu) { ctx in
                    for (j, idx) in [yuz.0, yuz.1].enumerated() where idx >= 0 {
                        guard let s = b.page(at: idx) else { continue }
                        let hucre = CGRect(x: CGFloat(j) * yarim, y: 0, width: yarim, height: kutu.height).insetBy(dx: 6, dy: 6)
                        let g = IsYardimcisi.gorunenBoyut(s)
                        let o = min(hucre.width / g.width, hucre.height / g.height)
                        let hedef = CGRect(x: hucre.midX - g.width * o / 2, y: hucre.midY - g.height * o / 2,
                                           width: g.width * o, height: g.height * o)
                        IsYardimcisi.sigdirCiz(s, ctx, hedef: hedef)
                    }
                }
            }
            ilerleme?(Double(k + 1) / Double(yuzler.count))
        }
        let ek = kip == .katlamali ? "kitapçık" : "iki yukarı"
        return try SayfaIslemleri.yazVeri(y.bitir(), IsYardimcisi.cikti(giris, ek), sayfa: yuzler.count)
    }
}
