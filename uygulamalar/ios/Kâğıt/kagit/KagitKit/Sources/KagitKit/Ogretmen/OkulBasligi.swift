import CoreGraphics
import Foundation
import PDFKit

/// Sınav kâğıdı başlığı şablonu (okul adı, ders, öğretmen, yıl, isteğe bağlı logo).
public struct OkulBasligi: Codable, Hashable, Sendable {
    public var okulAdi = ""
    public var ders = "Biyoloji"
    public var ogretmen = ""
    public var egitimYili = ""
    /// PNG/JPEG verisi.
    public var logo: Data?

    public init(okulAdi: String = "", ders: String = "Biyoloji", ogretmen: String = "",
                egitimYili: String = "", logo: Data? = nil) {
        self.okulAdi = okulAdi
        self.ders = ders
        self.ogretmen = ogretmen
        self.egitimYili = egitimYili
        self.logo = logo
    }

    /// “2026-2027” (eylülden sonrası yeni yıl).
    public static func varsayilanYil(_ tarih: Date = Date()) -> String {
        let t = Calendar.current.dateComponents([.year, .month], from: tarih)
        let y = t.year ?? 2026
        let bas = (t.month ?? 1) >= 9 ? y : y - 1
        return "\(bas)-\(bas + 1)"
    }

    public var bosMu: Bool { okulAdi.isEmpty && ders.isEmpty && ogretmen.isEmpty && egitimYili.isEmpty }

    // MARK: Çizim

    /// Başlığın kapladığı yükseklik.
    public func yukseklik(ogrenciKutulari: Bool) -> CGFloat {
        16 + 48 + (ogrenciKutulari ? 34 : 0) + 8
    }

    /// Başlığı `ust` noktasından aşağı doğru çizer; kapladığı yüksekliği döndürür.
    @discardableResult
    public func ciz(_ ctx: CGContext, ustSol: CGPoint, genislik: CGFloat, sinavAdi: String,
                    kitapcik: String? = nil, ogrenciKutulari: Bool = true) -> CGFloat {
        let h = yukseklik(ogrenciKutulari: ogrenciKutulari)
        let siyah = CGColor(gray: 0, alpha: 1)
        let gri = CGColor(gray: 0.35, alpha: 1)
        var solKenar = ustSol.x
        var sagKenar = ustSol.x + genislik
        let blokUst = ustSol.y - 14

        // Logo
        if let logo, let img = PDFCizim.goruntuYukle(logo, enBuyukKenar: 300) {
            let oran = CGFloat(img.width) / CGFloat(max(img.height, 1))
            let kutu = CGRect(x: ustSol.x, y: blokUst - 46, width: min(46 * oran, 70), height: 46)
            ctx.draw(img, in: kutu)
            solKenar = kutu.maxX + 8
        }
        // Kitapçık rozeti
        if let kitapcik {
            let kutu = CGRect(x: ustSol.x + genislik - 46, y: blokUst - 46, width: 46, height: 46)
            ctx.saveGState()
            ctx.setLineWidth(1.6)
            ctx.setStrokeColor(siyah)
            ctx.stroke(kutu)
            ctx.restoreGState()
            PDFCizim.metin(kitapcik, ctx, nokta: CGPoint(x: kutu.midX, y: kutu.minY + 12), punto: 26, hiza: .orta, kalin: true)
            sagKenar = kutu.minX - 8
        }
        let merkez = (solKenar + sagKenar) / 2
        let alan = max(sagKenar - solKenar, 100)

        func sigdir(_ s: String, punto: CGFloat, kalin: Bool) -> CGFloat {
            var p = punto
            let ad = kalin ? "Helvetica-Bold" : "Helvetica"
            while p > 7, PDFCizim.genislik(s, punto: p, yaziTipi: ad) > alan { p -= 0.5 }
            return p
        }

        var y = blokUst - 10
        if !okulAdi.isEmpty {
            let s = TurkceMetin.buyuk(okulAdi)
            PDFCizim.metin(s, ctx, nokta: CGPoint(x: merkez, y: y), punto: sigdir(s, punto: 13, kalin: true), hiza: .orta, kalin: true)
            y -= 15
        }
        var ikinci: [String] = []
        if !egitimYili.isEmpty { ikinci.append("\(egitimYili) EĞİTİM-ÖĞRETİM YILI") }
        if !ders.isEmpty { ikinci.append(TurkceMetin.buyuk(ders) + " DERSİ") }
        if !ikinci.isEmpty {
            let s = ikinci.joined(separator: "  ")
            PDFCizim.metin(s, ctx, nokta: CGPoint(x: merkez, y: y), punto: sigdir(s, punto: 10, kalin: false), renk: gri, hiza: .orta)
            y -= 14
        }
        if !sinavAdi.isEmpty {
            PDFCizim.metin(sinavAdi, ctx, nokta: CGPoint(x: merkez, y: y), punto: sigdir(sinavAdi, punto: 11.5, kalin: true), hiza: .orta, kalin: true)
        }

        var alt = blokUst - 48
        if ogrenciKutulari {
            alt -= 8
            let etiketler: [(String, CGFloat)] = [("Adı Soyadı:", 0.50), ("No:", 0.14), ("Sınıf:", 0.14), ("Puan:", 0.14)]
            var x = ustSol.x
            let bosluk: CGFloat = 8
            let kullanilabilir = genislik - bosluk * CGFloat(etiketler.count - 1)
            ctx.saveGState()
            ctx.setStrokeColor(siyah)
            ctx.setLineWidth(0.6)
            for (etiket, oran) in etiketler {
                let w = kullanilabilir * oran / 0.92
                PDFCizim.metin(etiket, ctx, nokta: CGPoint(x: x, y: alt - 9), punto: 9.5, kalin: true)
                let e = PDFCizim.genislik(etiket, punto: 9.5, yaziTipi: "Helvetica-Bold") + 3
                ctx.move(to: CGPoint(x: x + e, y: alt - 11))
                ctx.addLine(to: CGPoint(x: x + w, y: alt - 11))
                ctx.strokePath()
                x += w + bosluk
            }
            ctx.restoreGState()
            alt -= 24
        }
        // Ayırıcı çizgi
        ctx.saveGState()
        ctx.setStrokeColor(siyah)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: ustSol.x, y: ustSol.y - h + 4))
        ctx.addLine(to: CGPoint(x: ustSol.x + genislik, y: ustSol.y - h + 4))
        ctx.strokePath()
        ctx.restoreGState()
        _ = alt
        return h
    }
}

/// Ayarlardaki varsayılan hazır yorum damgaları.
public enum HazirYorumlar {
    public static let varsayilan = ["Aferin!", "Tekrar et", "Birimi yaz", "Güzel", "İşlem hatası", "Eksik",
                                    "Kısmen doğru", "Açıklayınız", "Okunaklı yaz", "Formülü yaz"]
}

/// Var olan bir PDF'in sayfalarına okul başlığı ekler.
public enum BaslikEkleyici {
    public struct Secenek: Sendable {
        public var sayfalar: [Int]          // 0 tabanlı; boşsa yalnız ilk sayfa
        public var yerAc: Bool              // içeriği küçültüp başlığa yer aç
        public var ogrenciKutulari: Bool
        public var sinavAdi: String

        public init(sayfalar: [Int] = [0], yerAc: Bool = true, ogrenciKutulari: Bool = true, sinavAdi: String = "") {
            self.sayfalar = sayfalar
            self.yerAc = yerAc
            self.ogrenciKutulari = ogrenciKutulari
            self.sinavAdi = sinavAdi
        }
    }

    public static func ekle(veri: Data, baslik: OkulBasligi, secenek: Secenek) throws -> Data {
        guard let belge = PDFDocument(data: veri), belge.pageCount > 0 else { throw KagitHata.bosGirdi }
        let hedef = Set(secenek.sayfalar)
        let yazici = PDFCizim.Yazici(baslik: belge.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
        for i in 0..<belge.pageCount {
            guard let sayfa = belge.page(at: i) else { continue }
            if !hedef.contains(i) {
                yazici.sayfaKopyala(sayfa)
                continue
            }
            let sinir = sayfa.bounds(for: .cropBox)
            let donuk = sayfa.rotation % 180 != 0
            let boyut = donuk ? CGSize(width: sinir.height, height: sinir.width) : sinir.size
            let h = baslik.yukseklik(ogrenciKutulari: secenek.ogrenciKutulari)
            let kenar: CGFloat = 28
            yazici.sayfa(CGRect(origin: .zero, size: boyut)) { ctx in
                if secenek.yerAc {
                    let olcek = max((boyut.height - h - 12) / boyut.height, 0.5)
                    ctx.saveGState()
                    ctx.translateBy(x: (boyut.width - boyut.width * olcek) / 2, y: 0)
                    ctx.scaleBy(x: olcek, y: olcek)
                    sayfa.draw(with: .cropBox, to: ctx)
                    ctx.restoreGState()
                } else {
                    sayfa.draw(with: .cropBox, to: ctx)
                    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                    ctx.fill(CGRect(x: 0, y: boyut.height - h - 12, width: boyut.width, height: h + 12))
                }
                baslik.ciz(ctx, ustSol: CGPoint(x: kenar, y: boyut.height - 6), genislik: boyut.width - 2 * kenar,
                           sinavAdi: secenek.sinavAdi, ogrenciKutulari: secenek.ogrenciKutulari)
            }
        }
        return yazici.bitir()
    }
}
