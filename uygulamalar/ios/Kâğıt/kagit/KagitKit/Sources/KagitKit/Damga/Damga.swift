import CoreGraphics
import CoreText
import Foundation
import PDFKit

/// Filigran ayarları.
public struct FiligranAyari: Sendable {
    public enum Tur: Sendable { case metin(String), gorsel(Data) }

    public var tur: Tur
    public var punto: Double = 60
    public var renk: RGBA = RGBA(0.5, 0.5, 0.5)
    public var opaklik: Double = 0.3
    /// Saat yönünün tersi, derece.
    public var aci: Double = 45
    /// Sayfayı döşer; kapalıysa ortalar.
    public var doseme = false
    /// Önde (içeriğin üstünde) ya da arkada.
    public var onde = true
    /// Görsel filigranın sayfa genişliğine oranı.
    public var gorselOlcek: Double = 0.5
    public var kalin = true
    public var aralik = ""

    public init(tur: Tur) { self.tur = tur }
}

/// Sayfa kenarındaki 6 konum.
public enum DamgaKonumu: String, CaseIterable, Sendable, Identifiable {
    case ustSol, ustOrta, ustSag, altSol, altOrta, altSag
    public var id: String { rawValue }
    public var ad: String {
        switch self {
        case .ustSol: "Üst sol"
        case .ustOrta: "Üst orta"
        case .ustSag: "Üst sağ"
        case .altSol: "Alt sol"
        case .altOrta: "Alt orta"
        case .altSag: "Alt sağ"
        }
    }
}

public struct NumaraAyari: Sendable {
    public var konum: DamgaKonumu = .altOrta
    /// "{n}", "{n}/{N}", "Sayfa {n}" …
    public var bicim = "{n}"
    public var baslangic = 1
    public var ilkSayfayiAtla = false
    public var punto: Double = 11
    public var renk: RGBA = .siyah
    public var aralik = ""
    public init() {}
}

public struct BilgiAyari: Sendable {
    public var alanlar: [DamgaKonumu: String] = [:]
    public var baslangic = 1
    public var ilkSayfayiAtla = false
    public var punto: Double = 10
    public var renk: RGBA = RGBA(0.25, 0.25, 0.25)
    public var aralik = ""
    public init() {}
}

/// Filigran, sayfa numarası, üst/alt bilgi. Sayfalar yeniden çizilir (metin vektör kalır);
/// bağlantılar ve form alanları bu işlemde korunmaz.
public enum DamgaIslemleri {

    // MARK: Filigran

    public static func filigran(_ giris: URL, ayar: FiligranAyari, parola: String? = nil, ilerleme: Ilerleme? = nil) throws -> URL {
        let b = try Belge.ac(giris, parola: parola)
        let secili = Set(try SayfaAraligi.coz(ayar.aralik, sayfaSayisi: b.pageCount))
        var gorsel: CGImage?
        if case .gorsel(let d) = ayar.tur {
            gorsel = PDFCizim.goruntuYukle(d, enBuyukKenar: 1600)
            guard gorsel != nil else { throw KagitHata.genel("Filigran görseli açılamadı.") }
        }
        if case .metin(let m) = ayar.tur, m.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw KagitHata.genel("Filigran metni boş.")
        }
        let y = PDFCizim.Yazici(baslik: giris.deletingPathExtension().lastPathComponent)
        for i in 0..<b.pageCount {
            try iptalDenetle()
            autoreleasepool {
                guard let s = b.page(at: i) else { return }
                guard secili.contains(i) else { y.sayfaKopyala(s); return }
                let g = IsYardimcisi.gorunenBoyut(s)
                let kutu = CGRect(origin: .zero, size: g)
                y.sayfa(kutu) { ctx in
                    if !ayar.onde { filigranCiz(ctx, kutu, ayar, gorsel) }
                    s.draw(with: .cropBox, to: ctx)
                    if ayar.onde { filigranCiz(ctx, kutu, ayar, gorsel) }
                }
            }
            ilerleme?(Double(i + 1) / Double(b.pageCount))
        }
        return try SayfaIslemleri.yazVeri(y.bitir(), IsYardimcisi.cikti(giris, "filigranlı"), sayfa: b.pageCount)
    }

    private static func filigranCiz(_ ctx: CGContext, _ kutu: CGRect, _ a: FiligranAyari, _ gorsel: CGImage?) {
        ctx.saveGState()
        ctx.setAlpha(CGFloat(min(max(a.opaklik, 0.02), 1)))
        let radyan = CGFloat(a.aci) * .pi / 180

        // Tek parçanın boyutu ve çizimi (merkez 0,0)
        let (pg, py): (CGFloat, CGFloat)
        let ciz: (CGContext) -> Void
        switch a.tur {
        case .metin(let m):
            let punto = CGFloat(a.punto)
            pg = PDFCizim.genislik(m, punto: punto, yaziTipi: a.kalin ? "Helvetica-Bold" : "Helvetica")
            py = punto
            ciz = { c in
                PDFCizim.metin(m, c, nokta: CGPoint(x: 0, y: -punto * 0.35), punto: punto, renk: a.renk.cgColor,
                               hiza: .orta, kalin: a.kalin)
            }
        case .gorsel:
            guard let gorsel else { ctx.restoreGState(); return }
            let w = kutu.width * CGFloat(a.gorselOlcek)
            let h = w * CGFloat(gorsel.height) / CGFloat(gorsel.width)
            (pg, py) = (w, h)
            ciz = { c in c.draw(gorsel, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h)) }
        }

        if a.doseme {
            let adimX = pg * 1.5 + 30, adimY = py * 3 + 30
            let yaricap = hypot(kutu.width, kutu.height) / 2
            ctx.translateBy(x: kutu.midX, y: kutu.midY)
            ctx.rotate(by: radyan)
            var sayac = 0
            var yy = -yaricap
            while yy <= yaricap, sayac < 4000 {
                var xx = -yaricap
                // Satırlara kayık yerleşim
                if Int(((yy + yaricap) / adimY).rounded()) % 2 == 1 { xx += adimX / 2 }
                while xx <= yaricap, sayac < 4000 {
                    ctx.saveGState()
                    ctx.translateBy(x: xx, y: yy)
                    ciz(ctx)
                    ctx.restoreGState()
                    xx += adimX
                    sayac += 1
                }
                yy += adimY
            }
        } else {
            ctx.translateBy(x: kutu.midX, y: kutu.midY)
            ctx.rotate(by: radyan)
            ciz(ctx)
        }
        ctx.restoreGState()
    }

    // MARK: Sayfa numarası / üst-alt bilgi

    public static func sayfaNumarasi(_ giris: URL, ayar: NumaraAyari, parola: String? = nil, ilerleme: Ilerleme? = nil) throws -> URL {
        var b = BilgiAyari()
        b.alanlar = [ayar.konum: ayar.bicim]
        b.baslangic = ayar.baslangic
        b.ilkSayfayiAtla = ayar.ilkSayfayiAtla
        b.punto = ayar.punto
        b.renk = ayar.renk
        b.aralik = ayar.aralik
        return try bilgiYaz(giris, ayar: b, ek: "numaralı", parola: parola, ilerleme: ilerleme)
    }

    public static func ustAltBilgi(_ giris: URL, ayar: BilgiAyari, parola: String? = nil, ilerleme: Ilerleme? = nil) throws -> URL {
        try bilgiYaz(giris, ayar: ayar, ek: "bilgili", parola: parola, ilerleme: ilerleme)
    }

    /// Yer tutucuları doldurur: {n} sayfa numarası, {N} son numara, {tarih}, {dosya}.
    public static func yerTutucu(_ metin: String, n: Int, son: Int, dosya: String, tarih: String) -> String {
        metin.replacingOccurrences(of: "{n}", with: "\(n)")
            .replacingOccurrences(of: "{N}", with: "\(son)")
            .replacingOccurrences(of: "{tarih}", with: tarih)
            .replacingOccurrences(of: "{dosya}", with: dosya)
    }

    private static func bilgiYaz(_ giris: URL, ayar: BilgiAyari, ek: String, parola: String?, ilerleme: Ilerleme?) throws -> URL {
        let b = try Belge.ac(giris, parola: parola)
        let n = b.pageCount
        let secili = Set(try SayfaAraligi.coz(ayar.aralik, sayfaSayisi: n))
        let dosya = giris.deletingPathExtension().lastPathComponent
        let bicim = DateFormatter()
        bicim.locale = TurkceMetin.yerel
        bicim.dateFormat = "dd.MM.yyyy"
        let tarih = bicim.string(from: Date())
        // Numaralanan sayfalar: seçili ve (ilk sayfa atlanmıyorsa)
        let numarali = (0..<n).filter { secili.contains($0) && !(ayar.ilkSayfayiAtla && $0 == 0) }
        let sonNo = ayar.baslangic + max(0, numarali.count - 1)
        let y = PDFCizim.Yazici(baslik: dosya)
        let kenar: CGFloat = 28
        let punto = CGFloat(ayar.punto)
        for i in 0..<n {
            try iptalDenetle()
            autoreleasepool {
                guard let s = b.page(at: i) else { return }
                guard let sira = numarali.firstIndex(of: i) else { y.sayfaKopyala(s); return }
                let no = ayar.baslangic + sira
                let kutu = CGRect(origin: .zero, size: IsYardimcisi.gorunenBoyut(s))
                y.sayfa(kutu) { ctx in
                    s.draw(with: .cropBox, to: ctx)
                    for (konum, sablon) in ayar.alanlar where !sablon.isEmpty {
                        let m = yerTutucu(sablon, n: no, son: sonNo, dosya: dosya, tarih: tarih)
                        let ust = konum == .ustSol || konum == .ustOrta || konum == .ustSag
                        let hiza: PDFCizim.Hiza = (konum == .ustSol || konum == .altSol) ? .sol
                            : (konum == .ustSag || konum == .altSag) ? .sag : .orta
                        let x: CGFloat = hiza == .sol ? kenar : hiza == .sag ? kutu.width - kenar : kutu.midX
                        let yy: CGFloat = ust ? kutu.height - kenar - punto * 0.8 : kenar
                        PDFCizim.metin(m, ctx, nokta: CGPoint(x: x, y: yy), punto: punto, renk: ayar.renk.cgColor, hiza: hiza)
                    }
                }
            }
            ilerleme?(Double(i + 1) / Double(n))
        }
        return try SayfaIslemleri.yazVeri(y.bitir(), IsYardimcisi.cikti(giris, ek), sayfa: n)
    }
}
