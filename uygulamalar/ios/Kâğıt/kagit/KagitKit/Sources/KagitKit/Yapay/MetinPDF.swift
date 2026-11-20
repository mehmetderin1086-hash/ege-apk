import CoreGraphics
import Foundation

/// Akışlı sayfa yerleşimi: gruplar (bölünmez bloklar) sayfalara dizilir. Sınav, özet ve çeviri PDF'leri bunu kullanır.
struct AkisOgesi {
    enum Tur {
        case metin(String)
        /// İki sütunlu satır (eşleştirme).
        case cift(String, String)
        /// Cevap yazmak için n çizgi.
        case cizgiler(Int)
        case bosluk(CGFloat)
    }
    var tur: Tur
    var punto: CGFloat = 11
    var kalin = false
    var girinti: CGFloat = 0
    var sonrasi: CGFloat = 4

    var yaziTipi: String { kalin ? "Helvetica-Bold" : "Helvetica" }

    func yukseklik(genislik: CGFloat) -> CGFloat {
        switch tur {
        case .metin(let s):
            return PDFCizim.paragrafYuksekligi(s, genislik: genislik - girinti, punto: punto, yaziTipi: yaziTipi) * 1.22 + sonrasi
        case .cift(let a, let b):
            let w = (genislik - girinti) / 2 - 8
            return max(PDFCizim.paragrafYuksekligi(a, genislik: w, punto: punto, yaziTipi: yaziTipi),
                       PDFCizim.paragrafYuksekligi(b, genislik: w, punto: punto, yaziTipi: yaziTipi)) * 1.22 + sonrasi
        case .cizgiler(let n):
            return CGFloat(n) * 22 + sonrasi
        case .bosluk(let h):
            return h
        }
    }
}

struct AkisYerlesimi {
    var sayfa: Int
    /// Ögenin üst kenarı (PDF koordinatı).
    var ustY: CGFloat
    var x: CGFloat
    var genislik: CGFloat
    var oge: AkisOgesi
    var yukseklik: CGFloat
}

enum AkisSayfalama {

    /// Gruplar bölünmeden sayfaya sığdırılır; sığmazsa yeni sayfa açılır.
    static func yerlestir(_ gruplar: [[AkisOgesi]], sayfa: CGSize, kenar: CGFloat, ilkSayfaUst: CGFloat,
                          altBosluk: CGFloat = 40) -> (yerlesimler: [AkisYerlesimi], sayfaSayisi: Int) {
        let genislik = sayfa.width - 2 * kenar
        let ustSinir = sayfa.height - kenar
        let altSinir = kenar + altBosluk - 20
        var sonuc: [AkisYerlesimi] = []
        var no = 0
        var bas = ustSinir - ilkSayfaUst
        var y = bas

        for grup in gruplar {
            let yuks = grup.map { $0.yukseklik(genislik: genislik) }
            let toplam = yuks.reduce(0, +)
            // Grup kalan yere sığmıyorsa (ve sayfa başında değilsek) yeni sayfa aç.
            if y - toplam < altSinir, y != bas { no += 1; bas = ustSinir; y = ustSinir }
            for (o, h) in zip(grup, yuks) {
                // Sayfaya hiç sığmayan dev grup öge öge bölünür.
                if y - h < altSinir, y != bas { no += 1; bas = ustSinir; y = ustSinir }
                sonuc.append(AkisYerlesimi(sayfa: no, ustY: y, x: kenar, genislik: genislik, oge: o, yukseklik: h))
                y -= h
            }
        }
        return (sonuc, no + 1)
    }

    static func ciz(_ y: AkisYerlesimi, _ ctx: CGContext) {
        let o = y.oge
        let x = y.x + o.girinti
        switch o.tur {
        case .metin(let s):
            let h = y.yukseklik - o.sonrasi
            PDFCizim.paragraf(s, ctx, kutu: CGRect(x: x, y: y.ustY - h - 2, width: y.genislik - o.girinti, height: h + 4),
                              punto: o.punto, yaziTipi: o.yaziTipi, satirAraligi: 1.22)
        case .cift(let a, let b):
            let w = (y.genislik - o.girinti) / 2 - 8
            let h = y.yukseklik - o.sonrasi
            PDFCizim.paragraf(a, ctx, kutu: CGRect(x: x, y: y.ustY - h - 2, width: w, height: h + 4), punto: o.punto,
                              yaziTipi: o.yaziTipi, satirAraligi: 1.22)
            PDFCizim.paragraf(b, ctx, kutu: CGRect(x: x + w + 16, y: y.ustY - h - 2, width: w, height: h + 4),
                              punto: o.punto, yaziTipi: o.yaziTipi, satirAraligi: 1.22)
        case .cizgiler(let n):
            ctx.saveGState()
            ctx.setStrokeColor(CGColor(gray: 0.6, alpha: 1))
            ctx.setLineWidth(0.5)
            for i in 1...max(n, 1) {
                let yy = y.ustY - CGFloat(i) * 22 + 4
                ctx.move(to: CGPoint(x: x, y: yy))
                ctx.addLine(to: CGPoint(x: y.x + y.genislik, y: yy))
            }
            ctx.strokePath()
            ctx.restoreGState()
        case .bosluk:
            break
        }
    }

    /// Sayfa altına “n / N” numarası.
    static func sayfaNo(_ ctx: CGContext, sayfa: CGSize, no: Int, toplam: Int) {
        PDFCizim.metin("\(no) / \(toplam)", ctx, nokta: CGPoint(x: sayfa.width / 2, y: 28), punto: 9,
                       renk: CGColor(gray: 0.4, alpha: 1), hiza: .orta)
    }
}

/// Düz metni (özet, çeviri) başlıklı, sayfalı bir PDF'e dökmek.
public enum MetinPDF {

    /// - Parameter govde: Boş satırla ayrılmış paragraflar; “- ” ile başlayan satırlar madde, “# ” ile başlayanlar başlık sayılır.
    public static func uret(baslik: String, altBaslik: String? = nil, govde: String,
                            boyut: PDFCizim.Boyut = .a4, punto: CGFloat = 11) -> Data {
        let sayfa = boyut.boyut
        var gruplar: [[AkisOgesi]] = []
        for satir in govde.components(separatedBy: "\n") {
            let t = satir.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            let dilimler = Parcalayici.birimler(t, sinir: 1400)
            for (i, d) in dilimler.enumerated() {
                if t.hasPrefix("# ") || t.hasPrefix("## ") {
                    let yazi = d.drop(while: { $0 == "#" || $0 == " " })
                    gruplar.append([AkisOgesi(tur: .metin(String(yazi)), punto: punto + 2, kalin: true, sonrasi: 6)])
                } else if t.hasPrefix("- ") || t.hasPrefix("• ") || t.hasPrefix("* ") {
                    let yazi = i == 0 ? "•  " + d.dropFirst(2) : String(d)
                    gruplar.append([AkisOgesi(tur: .metin(yazi), punto: punto, girinti: 12, sonrasi: 4)])
                } else {
                    gruplar.append([AkisOgesi(tur: .metin(d), punto: punto, sonrasi: 7)])
                }
            }
        }
        let kenar: CGFloat = 56
        let baslikYuk: CGFloat = altBaslik == nil ? 40 : 58
        let (yer, adet) = AkisSayfalama.yerlestir(gruplar, sayfa: sayfa, kenar: kenar, ilkSayfaUst: baslikYuk)
        let y = PDFCizim.Yazici(baslik: baslik)
        for no in 0..<adet {
            y.sayfa(CGRect(origin: .zero, size: sayfa)) { ctx in
                if no == 0 {
                    PDFCizim.metin(baslik, ctx, nokta: CGPoint(x: kenar, y: sayfa.height - kenar - 16), punto: 18, kalin: true)
                    if let altBaslik {
                        PDFCizim.metin(altBaslik, ctx, nokta: CGPoint(x: kenar, y: sayfa.height - kenar - 34), punto: 10,
                                       renk: CGColor(gray: 0.4, alpha: 1))
                    }
                }
                for yy in yer where yy.sayfa == no { AkisSayfalama.ciz(yy, ctx) }
                AkisSayfalama.sayfaNo(ctx, sayfa: sayfa, no: no + 1, toplam: adet)
            }
        }
        return y.bitir()
    }
}
