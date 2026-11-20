import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import KagitKit

/// Test girdisi: numaralı örnek PDF dosyası.
func ornekDosya(_ sayfa: Int, ad: String = "ornek.pdf") throws -> URL {
    let u = Ornek.gecici(ad)
    try Ornek.pdf((1...sayfa).map { ["Sayfa \($0)"] }).write(to: u)
    return u
}

func sayfaMetinleri(_ u: URL) throws -> [String] {
    let b = try Belge.ac(u)
    return (0..<b.pageCount).map { b.page(at: $0)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
}

/// Sayfadaki beyaz olmayan piksellerin görünen uzaydaki sınır kutusu (oran olarak 0...1, sol üst köken).
func icerikOranlari(_ s: PDFPage, esik: UInt8 = 200) -> CGRect? {
    guard let img = PDFCizim.goruntu(s, dpi: 36) else { return nil }
    let w = img.width, h = img.height
    var m = [UInt8](repeating: 0, count: w * h * 4)
    let c = CGContext(data: &m, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    var x0 = w, y0 = h, x1 = -1, y1 = -1
    for y in 0..<h { for x in 0..<w where min(m[(y * w + x) * 4], m[(y * w + x) * 4 + 1], m[(y * w + x) * 4 + 2]) < esik {
        x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
    } }
    guard x1 >= x0 else { return nil }
    return CGRect(x: Double(x0) / Double(w), y: Double(y0) / Double(h),
                  width: Double(x1 - x0 + 1) / Double(w), height: Double(y1 - y0 + 1) / Double(h))
}

@Suite struct ModulASayfaTestleri {

    @Test func birlestirYerImiylePDFKit() throws {
        let a = try ornekDosya(2, ad: "Birinci.pdf"), b = try ornekDosya(3, ad: "İkinci.pdf")
        let c = try SayfaIslemleri.birlestir([a, b])
        let d = try Belge.ac(c)
        #expect(d.pageCount == 5)
        #expect(d.outlineRoot?.numberOfChildren == 2)
        #expect(d.outlineRoot?.child(at: 1)?.label == "İkinci")
        #expect(d.outlineRoot?.child(at: 1)?.destination?.page == d.page(at: 2))
        let bYok = try Belge.ac(try SayfaIslemleri.birlestir([a, b], yerImi: false))
        #expect(bYok.outlineRoot == nil || bYok.outlineRoot?.numberOfChildren == 0)
    }

    @Test func birlestirBosGirdiHata() {
        #expect(throws: KagitHata.bosGirdi) { try SayfaIslemleri.birlestir([]) }
    }

    @Test func bolAraliklarVeHerN() throws {
        let u = try ornekDosya(7)
        let p = try SayfaIslemleri.bol(u, kip: .araliklar(["1-2", "5-"]))
        #expect(p.count == 2)
        #expect(try Belge.ac(p[0]).pageCount == 2)
        #expect(try sayfaMetinleri(p[1]) == ["Sayfa 5", "Sayfa 6", "Sayfa 7"])
        let n = try SayfaIslemleri.bol(u, kip: .herNSayfada(3))
        #expect(n.map { (try? Belge.ac($0).pageCount) ?? 0 } == [3, 3, 1])
        let t = try SayfaIslemleri.bol(u, kip: .tekTek)
        #expect(t.count == 7)
    }

    @Test func bolBoyutSiniri() throws {
        // Her sayfada küçük bir görüntü: sayfa başına birkaç KB
        let y = PDFCizim.Yazici()
        for i in 0..<12 {
            y.sayfa(CGRect(x: 0, y: 0, width: 300, height: 300)) { ctx in
                var rastgele = SystemRandomNumberGenerator()
                var piksel = [UInt8](repeating: 0, count: 120 * 120 * 4)
                for k in 0..<piksel.count { piksel[k] = UInt8.random(in: 0...255, using: &rastgele) }
                let img = CGContext(data: &piksel, width: 120, height: 120, bitsPerComponent: 8, bytesPerRow: 480,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!.makeImage()!
                ctx.draw(img, in: CGRect(x: 10, y: 10, width: 280, height: 280))
                PDFCizim.metin("Sayfa \(i + 1)", ctx, nokta: CGPoint(x: 20, y: 280), punto: 12)
            }
        }
        let u = Ornek.gecici("buyuk.pdf")
        try y.bitir().write(to: u)
        let toplam = IsYardimcisi.dosyaBoyutu(u)
        let sinir = toplam / 3
        let parcalar = try SayfaIslemleri.bol(u, kip: .boyutSiniri(sinir))
        #expect(parcalar.count >= 3)
        for p in parcalar { #expect(IsYardimcisi.dosyaBoyutu(p) <= sinir) }
        #expect(try parcalar.reduce(0) { $0 + (try Belge.ac($1).pageCount) } == 12)
    }

    @Test func cikarVeSil() throws {
        let u = try ornekDosya(6)
        #expect(try sayfaMetinleri(SayfaIslemleri.sayfaCikar(u, aralik: "2, 4-5")) == ["Sayfa 2", "Sayfa 4", "Sayfa 5"])
        #expect(try sayfaMetinleri(SayfaIslemleri.sayfaSil(u, aralik: "1-3")) == ["Sayfa 4", "Sayfa 5", "Sayfa 6"])
        #expect(throws: KagitHata.self) { try SayfaIslemleri.sayfaSil(u, aralik: "hepsi") }
        #expect(throws: KagitHata.self) { try SayfaIslemleri.sayfaCikar(u, aralik: "9") }
    }

    @Test func dondurAraligi() throws {
        let u = try ornekDosya(3)
        let d = try Belge.ac(SayfaIslemleri.dondur(u, aralik: "2-3", derece: 90))
        #expect(d.page(at: 0)?.rotation == 0)
        #expect(d.page(at: 1)?.rotation == 90)
        let e = try Belge.ac(SayfaIslemleri.dondur(u, derece: -90))
        #expect(e.page(at: 0)?.rotation == 270)
        #expect(throws: KagitHata.self) { try SayfaIslemleri.dondur(u, derece: 45) }
    }

    @Test func siralaKipleri() throws {
        let u = try ornekDosya(5)
        #expect(try sayfaMetinleri(SayfaIslemleri.sirala(u, kip: .tersCevir)[0]).first == "Sayfa 5")
        #expect(try sayfaMetinleri(SayfaIslemleri.sirala(u, kip: .yalnizTekler)[0]) == ["Sayfa 1", "Sayfa 3", "Sayfa 5"])
        #expect(try sayfaMetinleri(SayfaIslemleri.sirala(u, kip: .yalnizCiftler)[0]) == ["Sayfa 2", "Sayfa 4"])
        #expect(try SayfaIslemleri.sirala(u, kip: .tekVeCiftAyir).count == 2)
    }

    @Test func harmanlaCiftTarama() throws {
        // Ön yüzler: 1,3,5; arka yüzler ters sırada taranmış: 6,4,2
        let on = Ornek.gecici("on.pdf"), arka = Ornek.gecici("arka.pdf")
        try Ornek.pdf([["Sayfa 1"], ["Sayfa 3"], ["Sayfa 5"]]).write(to: on)
        try Ornek.pdf([["Sayfa 6"], ["Sayfa 4"], ["Sayfa 2"]]).write(to: arka)
        let h = try SayfaIslemleri.harmanla(onYuzler: on, arkaYuzler: arka)
        #expect(try sayfaMetinleri(h) == (1...6).map { "Sayfa \($0)" })
        // Tek dosya: ilk yarı ön, ikinci yarı ters arka
        let tek = Ornek.gecici("tek.pdf")
        try Ornek.pdf([["Sayfa 1"], ["Sayfa 3"], ["Sayfa 5"], ["Sayfa 6"], ["Sayfa 4"], ["Sayfa 2"]]).write(to: tek)
        #expect(try sayfaMetinleri(SayfaIslemleri.harmanlaTekDosya(tek)) == (1...6).map { "Sayfa \($0)" })
        #expect(throws: KagitHata.self) { try SayfaIslemleri.harmanlaTekDosya(ornekDosya(3)) }
    }

    @Test func bosSayfaKonumlari() throws {
        let u = try ornekDosya(3)
        #expect(try sayfaMetinleri(SayfaIslemleri.bosSayfaEkle(u, konum: .basa)) == ["", "Sayfa 1", "Sayfa 2", "Sayfa 3"])
        #expect(try sayfaMetinleri(SayfaIslemleri.bosSayfaEkle(u, konum: .sona, sayi: 2)).suffix(2) == ["", ""])
        #expect(try Belge.ac(SayfaIslemleri.bosSayfaEkle(u, konum: .herSayfadanSonra)).pageCount == 6)
        let r = try sayfaMetinleri(SayfaIslemleri.bosSayfaEkle(u, konum: .aralikSonrasi("2")))
        #expect(r == ["Sayfa 1", "Sayfa 2", "", "Sayfa 3"])
    }

    @Test func boyutlandirA5() throws {
        let u = try ornekDosya(2)
        let c = try Belge.ac(SayfaIslemleri.boyutlandir(u, hedef: .a5))
        let b = c.page(at: 0)!.bounds(for: .cropBox)
        #expect(abs(b.width - 419.53) < 0.1 && abs(b.height - 595.28) < 0.1)
        #expect(c.page(at: 1)?.string?.contains("Sayfa 2") == true)
        // Yatay sayfa yatay kalır
        let yatay = Ornek.gecici("yatay.pdf")
        try Ornek.pdf([["Yatay"]], boyut: CGSize(width: 842, height: 595)).write(to: yatay)
        let ys = try Belge.ac(SayfaIslemleri.boyutlandir(yatay, hedef: .letter)).page(at: 0)!.bounds(for: .cropBox)
        #expect(ys.width > ys.height)
    }

    @Test func kenarKirpOtomatikKucultur() throws {
        let u = try ornekDosya(1)
        let c = try Belge.ac(SayfaIslemleri_kirp(u))
        let s = c.page(at: 0)!
        let kutu = s.bounds(for: .cropBox)
        #expect(kutu.width < 595 * 0.8)
        #expect(kutu.height < 842 * 0.2)
        #expect(s.string?.contains("Sayfa 1") == true)
        // Kırpılan sayfada içerik kenara yakın olmalı
        let o = icerikOranlari(s)!
        #expect(o.minX < 0.2 && o.minY < 0.4)
    }

    @Test func kenarKirpDondurulmusSayfa() throws {
        let u = try ornekDosya(1)
        let d = try SayfaIslemleri.dondur(u, derece: 90)
        let c = try Belge.ac(SayfaYerlesimi.kenarKirp(d, kip: .otomatik(pay: 6)))
        let s = c.page(at: 0)!
        #expect(s.rotation == 90)
        let o = icerikOranlari(s)!
        // Kırpma sonrası içerik sayfayı kabaca doldurmalı (yön hatası olsa kenarda kalırdı)
        #expect(o.width > 0.45 && o.height > 0.6)
        let kb = s.bounds(for: .cropBox)
        #expect(kb.width < 100 && kb.height < 40)   // ham uzayda yatay metin: geniş > yüksek
    }

    @Test func kenarKirpElle() throws {
        let u = try ornekDosya(1)
        let c = try Belge.ac(SayfaYerlesimi.kenarKirp(u, kip: .elle(ust: 100, alt: 50, sol: 20, sag: 30)))
        let b = c.page(at: 0)!.bounds(for: .cropBox)
        #expect(abs(b.width - (595.28 - 50)) < 1 && abs(b.height - (841.89 - 150)) < 1)
    }

    @Test func nUpDuzenleri() throws {
        let u = try ornekDosya(10)
        for (m, kagit) in [(2, 5), (4, 3), (6, 2), (9, 2)] {
            let c = try Belge.ac(SayfaYerlesimi.nUp(u, sayfaBasina: m))
            #expect(c.pageCount == kagit)
        }
        let c = try Belge.ac(SayfaYerlesimi.nUp(u, sayfaBasina: 4, kenarCizgisi: false))
        let metin = c.page(at: 0)?.string ?? ""
        for i in 1...4 { #expect(metin.contains("Sayfa \(i)")) }
        let b = c.page(at: 0)!.bounds(for: .cropBox)
        #expect(b.width < b.height)
        let iki = try Belge.ac(SayfaYerlesimi.nUp(u, sayfaBasina: 2)).page(at: 0)!.bounds(for: .cropBox)
        #expect(iki.width > iki.height)
        #expect(throws: KagitHata.self) { try SayfaYerlesimi.nUp(u, sayfaBasina: 3) }
    }

    @Test func kitapcikSirasi() {
        // 8 sayfa: ön/arka yüzler (1-tabanlı): 8|1, 2|7, 6|3, 4|5
        let s = SayfaYerlesimi.kitapcikSirasi(sayfaSayisi: 8).map { [$0.0 + 1, $0.1 + 1] }
        #expect(s == [[8, 1], [2, 7], [6, 3], [4, 5]])
        // 5 sayfa → 8'e tamamlanır, eksikler -1
        let e = SayfaYerlesimi.kitapcikSirasi(sayfaSayisi: 5)
        #expect(e.count == 4)
        #expect(e[0].0 == -1 && e[0].1 == 0)
    }

    @Test func kitapcikBaskiUretir() throws {
        let u = try ornekDosya(6)
        let k = try Belge.ac(SayfaYerlesimi.kitapcikBaski(u))
        #expect(k.pageCount == 4)   // 6 → 8 sayfa → 4 yüz
        let kutu = k.page(at: 0)!.bounds(for: .cropBox)
        #expect(kutu.width > kutu.height)
        let ilk = k.page(at: 0)?.string ?? ""
        #expect(ilk.contains("Sayfa 1"))
        let a5 = try Belge.ac(SayfaYerlesimi.kitapcikBaski(u, kip: .ikiYukari))
        #expect(a5.pageCount == 3)
    }
}

func SayfaIslemleri_kirp(_ u: URL) throws -> URL {
    try SayfaYerlesimi.kenarKirp(u, kip: .otomatik(pay: 10))
}
