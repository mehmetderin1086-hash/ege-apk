import CoreGraphics
import Foundation
import PDFKit

/// Tohumlu, tekrarlanabilir rastgele sayı üretici (SplitMix64).
public struct TohumluUretec: RandomNumberGenerator {
    var durum: UInt64
    public init(tohum: UInt64) { durum = tohum &+ 0x9E37_79B9_7F4A_7C15 }
    public mutating func next() -> UInt64 {
        durum = durum &+ 0x9E37_79B9_7F4A_7C15
        var z = durum
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public struct KitapcikAyari: Sendable {
    public var sutun: Int = 2
    public var tohum: UInt64 = 1
    public var sayfa: PDFCizim.Boyut = .a4
    public var sinavAdi = ""
    public var baslik = OkulBasligi()
    /// Orijinal soru numarası → doğru şık harfi.
    public var anahtar: [Int: String] = [:]
    /// Sorular yeniden numaralansın (örtü + yeni numara).
    public var yenidenNumarala = true

    public init() {}
}

public struct KitapcikSonucu: Sendable {
    public var a: Data
    public var b: Data
    /// Cevap anahtarı sayfaları (A ve B ayrı sayfalarda); anahtar girilmediyse nil.
    public var anahtarPDF: Data?
    /// B kitapçığındaki sırayla orijinal soru numaraları.
    public var bSirasi: [Int]
    /// Yeni numara (1 tabanlı sıra) → harf.
    public var anahtarA: [Int: String]
    public var anahtarB: [Int: String]
}

public enum Kitapcik {

    /// 0..<n karıştırması (tohumla tekrarlanabilir).
    public static func karistir(sayi n: Int, tohum: UInt64) -> [Int] {
        var u = TohumluUretec(tohum: tohum)
        var s = Array(0..<n)
        s.shuffle(using: &u)
        return s
    }

    /// B için karışım: kimliğe çok benzemesin (yerinde kalan soru sayısı en çok n/4+1).
    public static func bSirasi(sayi n: Int, tohum: UInt64) -> [Int] {
        guard n > 1 else { return Array(0..<n) }
        var enIyi = karistir(sayi: n, tohum: tohum)
        func yerinde(_ s: [Int]) -> Int { zip(s, 0..<n).filter { $0 == $1 }.count }
        var deneme: UInt64 = 1
        while yerinde(enIyi) > n / 4 + (n < 4 ? 0 : 1), deneme < 60 {
            enIyi = karistir(sayi: n, tohum: tohum &+ deneme &* 7919)
            deneme += 1
        }
        if enIyi == Array(0..<n) { enIyi = Array(enIyi.dropFirst()) + [0] }
        return enIyi
    }

    /// Yeni sıradaki cevap anahtarı: yeni numara (1 tabanlı) → harf. `sira[j]` = j. yerdeki sorunun orijinal indeksi (0 tabanlı).
    public static func anahtarEsle(sira: [Int], anahtar: [Int: String], numaralar: [Int]) -> [Int: String] {
        var sonuc: [Int: String] = [:]
        for (j, eski) in sira.enumerated() {
            if let harf = anahtar[numaralar[eski]] { sonuc[j + 1] = harf }
        }
        return sonuc
    }

    // MARK: Üretim

    /// A ve B kitapçıklarını (ve anahtar sayfalarını) üretir.
    public static func uret(kaynak: Data, bolgeler: [SoruBolgesi], ayar: KitapcikAyari) throws -> KitapcikSonucu {
        guard let belge = PDFDocument(data: kaynak), !bolgeler.isEmpty else { throw KagitHata.bosGirdi }
        let n = bolgeler.count
        let siraA = Array(0..<n)
        let siraB = bSirasi(sayi: n, tohum: ayar.tohum)
        let numaralar = bolgeler.map(\.numara)

        let a = try tekKitapcik(belge, bolgeler: bolgeler, sira: siraA, tur: "A", ayar: ayar)
        let b = try tekKitapcik(belge, bolgeler: bolgeler, sira: siraB, tur: "B", ayar: ayar)
        let ka = anahtarEsle(sira: siraA, anahtar: ayar.anahtar, numaralar: numaralar)
        let kb = anahtarEsle(sira: siraB, anahtar: ayar.anahtar, numaralar: numaralar)
        var anahtarPDF: Data?
        if !ayar.anahtar.isEmpty {
            anahtarPDF = AnahtarSayfasi.uret(baslik: ayar.baslik, sinavAdi: ayar.sinavAdi, tablolar: [("A Kitapçığı", ka, n), ("B Kitapçığı", kb, n)])
        }
        return KitapcikSonucu(a: a, b: b, anahtarPDF: anahtarPDF, bSirasi: siraB.map { numaralar[$0] },
                              anahtarA: ka, anahtarB: kb)
    }

    struct Yer {
        var sayfa: Int
        var sutun: Int
        var ust: CGFloat        // üst kenar (PDF y)
        var olcek: CGFloat
        var soruSirasi: Int     // bolgeler dizisindeki indeks
        var yeniNo: Int
    }

    static func tekKitapcik(_ belge: PDFDocument, bolgeler: [SoruBolgesi], sira: [Int], tur: String, ayar: KitapcikAyari) throws -> Data {
        let boyut = ayar.sayfa.boyut
        let kenar: CGFloat = 36
        let bosluk: CGFloat = 18
        let sutun = max(1, min(ayar.sutun, 2))
        let sw = (boyut.width - 2 * kenar - bosluk * CGFloat(sutun - 1)) / CGFloat(sutun)
        let baslikYuk = ayar.baslik.yukseklik(ogrenciKutulari: true)
        let ilkUst = boyut.height - kenar + 14 - baslikYuk - 8
        let digerUst = boyut.height - kenar - 14
        let alt = kenar + 14
        let aralik: CGFloat = 10

        var yerler: [Yer] = []
        var sayfa = 0, s = 0
        var y = ilkUst
        for (j, bi) in sira.enumerated() {
            let b = bolgeler[bi]
            let enGenis = b.parcalar.map(\.kutu.width).max() ?? sw
            var olcek = min(1, sw / max(enGenis, 1))
            let sutunUst = sayfa == 0 ? ilkUst : digerUst
            // Bir sütuna hiç sığmayan soru küçültülür
            let tamYuk = b.toplamYukseklik * olcek
            if tamYuk > sutunUst - alt { olcek *= (sutunUst - alt) / tamYuk }
            let h = b.toplamYukseklik * olcek
            if y - h < alt {
                s += 1
                if s >= sutun { s = 0; sayfa += 1 }
                y = sayfa == 0 ? ilkUst : digerUst
            }
            yerler.append(Yer(sayfa: sayfa, sutun: s, ust: y, olcek: olcek, soruSirasi: bi, yeniNo: j + 1))
            y -= h + aralik
        }
        let sayfaSayisi = (yerler.last?.sayfa ?? 0) + 1

        let yazici = PDFCizim.Yazici(baslik: "\(ayar.sinavAdi) — \(tur) Kitapçığı")
        for p in 0..<sayfaSayisi {
            yazici.sayfa(CGRect(origin: .zero, size: boyut)) { ctx in
                if p == 0 {
                    ayar.baslik.ciz(ctx, ustSol: CGPoint(x: kenar, y: boyut.height - kenar + 14), genislik: boyut.width - 2 * kenar,
                                    sinavAdi: ayar.sinavAdi, kitapcik: tur, ogrenciKutulari: true)
                } else {
                    PDFCizim.metin("\(ayar.sinavAdi)  ·  \(tur) Kitapçığı", ctx, nokta: CGPoint(x: kenar, y: boyut.height - kenar + 2),
                                   punto: 9, renk: CGColor(gray: 0.35, alpha: 1))
                }
                if sutun == 2 {
                    ctx.saveGState()
                    ctx.setStrokeColor(CGColor(gray: 0.7, alpha: 1))
                    ctx.setLineWidth(0.5)
                    let x = kenar + sw + bosluk / 2
                    ctx.move(to: CGPoint(x: x, y: alt))
                    ctx.addLine(to: CGPoint(x: x, y: p == 0 ? ilkUst : digerUst))
                    ctx.strokePath()
                    ctx.restoreGState()
                }
                for yer in yerler where yer.sayfa == p {
                    let b = bolgeler[yer.soruSirasi]
                    let x0 = kenar + CGFloat(yer.sutun) * (sw + bosluk)
                    var yy = yer.ust
                    for (k, parca) in b.parcalar.enumerated() {
                        guard let kaynakSayfa = belge.page(at: parca.sayfa) else { continue }
                        let r = parca.kutu
                        let h = r.height * yer.olcek
                        let hedef = CGRect(x: x0, y: yy - h, width: r.width * yer.olcek, height: h)
                        ctx.saveGState()
                        ctx.clip(to: hedef)
                        ctx.translateBy(x: x0 - r.minX * yer.olcek, y: yy - r.maxY * yer.olcek)
                        ctx.scaleBy(x: yer.olcek, y: yer.olcek)
                        kaynakSayfa.draw(with: .cropBox, to: ctx)
                        ctx.restoreGState()
                        if k == 0, ayar.yenidenNumarala, let nk = b.numaraKutusu {
                            numaraDegistir(ctx, eski: nk, bolge: r, hedefX: x0, hedefUst: yy, olcek: yer.olcek, yeniNo: yer.yeniNo)
                        }
                        yy -= h
                    }
                }
                let altYazi = "\(tur) Kitapçığı  ·  \(p + 1) / \(sayfaSayisi)"
                PDFCizim.metin(altYazi, ctx, nokta: CGPoint(x: boyut.width / 2, y: 22), punto: 9,
                               renk: CGColor(gray: 0.35, alpha: 1), hiza: .orta)
            }
        }
        return yazici.bitir()
    }

    /// Eski numarayı beyazla örter, yenisini aynı yere yazar.
    static func numaraDegistir(_ ctx: CGContext, eski: CGRect, bolge: CGRect, hedefX: CGFloat, hedefUst: CGFloat,
                               olcek: CGFloat, yeniNo: Int) {
        let kx = hedefX + (eski.minX - bolge.minX) * olcek
        let ky = hedefUst - (bolge.maxY - eski.minY) * olcek
        let kutu = CGRect(x: kx, y: ky, width: eski.width * olcek, height: eski.height * olcek)
        ctx.saveGState()
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(kutu.insetBy(dx: -1, dy: -0.5))
        ctx.restoreGState()
        let yazi = "\(yeniNo)."
        var punto = max(kutu.height / 1.2, 6)
        let g = PDFCizim.genislik(yazi, punto: punto, yaziTipi: "Helvetica-Bold")
        if g > kutu.width + 2 { punto = max(punto * (kutu.width + 2) / g, punto * 0.7) }
        PDFCizim.metin(yazi, ctx, nokta: CGPoint(x: kutu.minX, y: kutu.minY + kutu.height * 0.2), punto: punto, kalin: true)
    }
}

/// Cevap anahtarı sayfaları: kitapçık başına ayrı sayfa.
enum AnahtarSayfasi {
    static func uret(baslik: OkulBasligi, sinavAdi: String, tablolar: [(ad: String, anahtar: [Int: String], sayi: Int)]) -> Data {
        let boyut = PDFCizim.Boyut.a4.boyut
        let y = PDFCizim.Yazici(baslik: "\(sinavAdi) — Cevap Anahtarı")
        for t in tablolar {
            y.sayfa(CGRect(origin: .zero, size: boyut)) { ctx in
                let kenar: CGFloat = 48
                let h = baslik.ciz(ctx, ustSol: CGPoint(x: kenar, y: boyut.height - 36), genislik: boyut.width - 2 * kenar,
                                   sinavAdi: "\(sinavAdi) — CEVAP ANAHTARI", kitapcik: String(t.ad.prefix(1)), ogrenciKutulari: false)
                var yy = boyut.height - 36 - h - 28
                PDFCizim.metin(t.ad, ctx, nokta: CGPoint(x: kenar, y: yy), punto: 14, kalin: true)
                yy -= 30
                let sutunSayisi = 5
                let w = (boyut.width - 2 * kenar) / CGFloat(sutunSayisi)
                let satirSayisi = Int(ceil(Double(t.sayi) / Double(sutunSayisi)))
                // Soldan sağa değil, sütun sütun doldur (1-10 ilk sütun) okunması kolay olsun
                for no in 1...max(t.sayi, 1) {
                    let k = (no - 1) / max(satirSayisi, 1)
                    let r = (no - 1) % max(satirSayisi, 1)
                    let harf = t.anahtar[no] ?? "—"
                    PDFCizim.metin("\(no).", ctx, nokta: CGPoint(x: kenar + CGFloat(k) * w, y: yy - CGFloat(r) * 22), punto: 12)
                    PDFCizim.metin(harf, ctx, nokta: CGPoint(x: kenar + CGFloat(k) * w + 34, y: yy - CGFloat(r) * 22), punto: 12, kalin: true)
                }
            }
        }
        return y.bitir()
    }
}
