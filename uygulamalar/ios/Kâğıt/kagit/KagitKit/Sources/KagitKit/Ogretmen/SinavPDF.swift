import CoreGraphics
import Foundation

/// Üretilen sorulardan sınav kâğıdı ve cevap anahtarı PDF'i.
public enum SinavPDF {

    static let turSirasi: [SoruTuru] = [.coktanSecmeli, .dogruYanlis, .bosluk, .eslestirme, .acikUclu]

    /// Sınav sırası: türe göre gruplanmış; kendi içinde verilen sıra korunur.
    public static func sirala(_ sorular: [UretilenSoru]) -> [UretilenSoru] {
        turSirasi.flatMap { t in sorular.filter { $0.tur == t } }
    }

    static func harf(_ i: Int) -> String { String(UnicodeScalar(UInt8(65 + i))) }

    /// Eşleştirmede sağ sütun sırası: sol i'nin karşılığı, gösterilen listede (i+2) % n yerinde değil — kaydırılmış.
    static func sagSira(_ n: Int) -> [Int] { (0..<n).map { ($0 + 2) % n } }

    /// Eşleştirme cevabı: “1-C, 2-A …”
    public static func eslestirmeCevabi(_ s: UretilenSoru) -> String {
        let n = s.ciftler.count
        let sira = sagSira(n)    // gösterilen j. satırdaki sağ öge = ciftler[sira[j]].sag
        var harfler: [String] = []
        for i in 0..<n {
            let j = sira.firstIndex(of: i) ?? i
            harfler.append("\(i + 1)-\(harf(j))")
        }
        return harfler.joined(separator: ", ")
    }

    static func soruGrubu(_ s: UretilenSoru, no: Int) -> [AkisOgesi] {
        var g: [AkisOgesi] = []
        switch s.tur {
        case .coktanSecmeli:
            g.append(AkisOgesi(tur: .metin("\(no). \(s.metin)"), punto: 11, sonrasi: 4))
            let sec = s.secenekler.enumerated().map { "\(harf($0.offset))) \($0.element)" }
            if (s.secenekler.map(\.count).max() ?? 0) <= 28 {
                var i = 0
                while i < sec.count {
                    g.append(AkisOgesi(tur: .cift(sec[i], i + 1 < sec.count ? sec[i + 1] : ""), punto: 10.5, girinti: 14, sonrasi: 2))
                    i += 2
                }
            } else {
                for t in sec { g.append(AkisOgesi(tur: .metin(t), punto: 10.5, girinti: 14, sonrasi: 2)) }
            }
            g[g.count - 1].sonrasi = 10
        case .dogruYanlis:
            g.append(AkisOgesi(tur: .metin("(......)  \(no). \(s.metin)"), punto: 11, sonrasi: 10))
        case .bosluk:
            g.append(AkisOgesi(tur: .metin("\(no). \(s.metin)"), punto: 11, sonrasi: 10))
        case .acikUclu:
            g.append(AkisOgesi(tur: .metin("\(no). \(s.metin)"), punto: 11, sonrasi: 2))
            g.append(AkisOgesi(tur: .cizgiler(3), sonrasi: 8))
        case .eslestirme:
            g.append(AkisOgesi(tur: .metin("\(no). \(s.metin)"), punto: 11, sonrasi: 4))
            let sira = sagSira(s.ciftler.count)
            for i in 0..<s.ciftler.count {
                g.append(AkisOgesi(tur: .cift("\(i + 1). \(s.ciftler[i].sol)", "\(harf(i)). \(s.ciftler[sira[i]].sag)"),
                                   punto: 10.5, girinti: 14, sonrasi: 3))
            }
            g[g.count - 1].sonrasi = 10
        }
        return g
    }

    /// Sınav kâğıdı.
    public static func sinav(sorular: [UretilenSoru], baslik: OkulBasligi, sinavAdi: String) -> Data {
        let sirali = sirala(sorular)
        var gruplar: [[AkisOgesi]] = []
        var onceki: SoruTuru?
        for (i, s) in sirali.enumerated() {
            var g = soruGrubu(s, no: i + 1)
            if s.tur != onceki {
                g.insert(AkisOgesi(tur: .metin(s.tur.bolumAdi), punto: 10.5, kalin: true, sonrasi: 6), at: 0)
                onceki = s.tur
            }
            gruplar.append(g)
        }
        let boyut = PDFCizim.Boyut.a4.boyut
        let kenar: CGFloat = 40
        let basYuk = baslik.yukseklik(ogrenciKutulari: true)
        let (yer, adet) = AkisSayfalama.yerlestir(gruplar, sayfa: boyut, kenar: kenar, ilkSayfaUst: basYuk + 10)
        let y = PDFCizim.Yazici(baslik: sinavAdi)
        for no in 0..<adet {
            y.sayfa(CGRect(origin: .zero, size: boyut)) { ctx in
                if no == 0 {
                    baslik.ciz(ctx, ustSol: CGPoint(x: kenar, y: boyut.height - kenar + 6), genislik: boyut.width - 2 * kenar,
                               sinavAdi: sinavAdi, ogrenciKutulari: true)
                }
                for yy in yer where yy.sayfa == no { AkisSayfalama.ciz(yy, ctx) }
                AkisSayfalama.sayfaNo(ctx, sayfa: boyut, no: no + 1, toplam: adet)
            }
        }
        return y.bitir()
    }

    /// Cevap anahtarı; `aciklamali` ise her sorunun çözüm notu da yazılır.
    public static func anahtar(sorular: [UretilenSoru], baslik: OkulBasligi, sinavAdi: String, aciklamali: Bool) -> Data {
        let sirali = sirala(sorular)
        var gruplar: [[AkisOgesi]] = []
        for (i, s) in sirali.enumerated() {
            let no = i + 1
            var cevap: String
            switch s.tur {
            case .coktanSecmeli:
                let idx = "ABCDE".firstIndex(of: Character(s.dogru.uppercased())).map { "ABCDE".distance(from: "ABCDE".startIndex, to: $0) }
                cevap = s.dogru.uppercased() + (idx.flatMap { s.secenekler.indices.contains($0) ? ") " + s.secenekler[$0] : nil } ?? "")
            case .dogruYanlis, .bosluk, .acikUclu: cevap = s.dogru
            case .eslestirme: cevap = eslestirmeCevabi(s)
            }
            var g = [AkisOgesi(tur: .metin("\(no). \(cevap)"), punto: 11, kalin: false, sonrasi: aciklamali ? 2 : 5)]
            if aciklamali {
                g.append(AkisOgesi(tur: .metin("Soru: \(s.metin)"), punto: 9.5, girinti: 14, sonrasi: 2))
                if !s.aciklama.isEmpty { g.append(AkisOgesi(tur: .metin("Çözüm: \(s.aciklama)"), punto: 9.5, girinti: 14, sonrasi: 2)) }
                g[g.count - 1].sonrasi = 8
            }
            gruplar.append(g)
        }
        let boyut = PDFCizim.Boyut.a4.boyut
        let kenar: CGFloat = 48
        let basYuk = baslik.yukseklik(ogrenciKutulari: false)
        let (yer, adet) = AkisSayfalama.yerlestir(gruplar, sayfa: boyut, kenar: kenar, ilkSayfaUst: basYuk + 20)
        let y = PDFCizim.Yazici(baslik: "\(sinavAdi) — Cevap Anahtarı")
        for no in 0..<adet {
            y.sayfa(CGRect(origin: .zero, size: boyut)) { ctx in
                if no == 0 {
                    baslik.ciz(ctx, ustSol: CGPoint(x: kenar, y: boyut.height - kenar + 14), genislik: boyut.width - 2 * kenar,
                               sinavAdi: "\(sinavAdi) — CEVAP ANAHTARI", ogrenciKutulari: false)
                }
                for yy in yer where yy.sayfa == no { AkisSayfalama.ciz(yy, ctx) }
                AkisSayfalama.sayfaNo(ctx, sayfa: boyut, no: no + 1, toplam: adet)
            }
        }
        return y.bitir()
    }
}
