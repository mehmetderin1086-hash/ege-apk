import CoreGraphics
import Foundation

/// Bir sayfadaki aynı taban çizgisinde duran metin nesnelerinin oluşturduğu satır (PDF koordinatları).
public struct DuzenlemeSatiri: Sendable, Hashable, Identifiable {
    public var id: Int { nesneler.first?.indeks ?? -1 }
    public let nesneler: [PdfiumBelge.MetinNesnesi]
    public let metin: String
    public let kutu: CGRect
    /// Satırın taban çizgisi (PDF y değeri).
    public let tabanY: CGFloat
    public let punto: CGFloat
    public let yaziTipiAdi: String
    public let renk: RGBA

    public var indeksler: [Int] { nesneler.map(\.indeks) }
    public var solX: CGFloat { kutu.minX }
}

/// Satırlardan oluşan blok (paragraf).
public struct MetinBlogu: Sendable, Hashable {
    public let satirlar: [DuzenlemeSatiri]
    public var metin: String { satirlar.map(\.metin).joined(separator: "\n") }
    public var kutu: CGRect { satirlar.map(\.kutu).reduce(CGRect.null) { $0.union($1) } }
}

/// `PdfiumBelge.metinNesneleri` çıktısını taban çizgisine göre satır ve bloklara gruplar.
public enum MetinGruplayici {

    /// Aynı satırdaki iki nesne arasındaki boşluk bu puntonun katından büyükse ayrı satır parçası (sütun) sayılır.
    static let sutunBosluguKatsayisi: CGFloat = 2.5
    static let tabanToleransi: CGFloat = 0.3

    public static func satirlar(_ nesneler: [PdfiumBelge.MetinNesnesi]) -> [DuzenlemeSatiri] {
        let adaylar = nesneler.filter { !$0.kutu.isNull && !$0.metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        // Yukarıdan aşağı (PDF'te büyük y üstte), sonra soldan sağa.
        let sirali = adaylar.sorted { $0.taban.y != $1.taban.y ? $0.taban.y > $1.taban.y : $0.taban.x < $1.taban.x }

        var seritler: [[PdfiumBelge.MetinNesnesi]] = []
        for n in sirali {
            let tolerans = max(n.punto, 1) * tabanToleransi
            if let i = seritler.firstIndex(where: { abs(ortalamaTaban($0) - n.taban.y) <= tolerans }) {
                seritler[i].append(n)
            } else {
                seritler.append([n])
            }
        }

        var sonuc: [DuzenlemeSatiri] = []
        for serit in seritler {
            let soldan = serit.sorted { $0.taban.x < $1.taban.x }
            var parca: [PdfiumBelge.MetinNesnesi] = []
            for n in soldan {
                if let son = parca.last {
                    let bosluk = n.kutu.minX - son.kutu.maxX
                    if bosluk > max(son.punto, n.punto) * sutunBosluguKatsayisi {
                        sonuc.append(satir(parca))
                        parca = []
                    }
                }
                parca.append(n)
            }
            if !parca.isEmpty { sonuc.append(satir(parca)) }
        }
        return sonuc.sorted { $0.tabanY != $1.tabanY ? $0.tabanY > $1.tabanY : $0.solX < $1.solX }
    }

    private static func ortalamaTaban(_ s: [PdfiumBelge.MetinNesnesi]) -> CGFloat {
        s.reduce(0) { $0 + $1.taban.y } / CGFloat(max(s.count, 1))
    }

    private static func satir(_ parca: [PdfiumBelge.MetinNesnesi]) -> DuzenlemeSatiri {
        var metin = ""
        for (i, n) in parca.enumerated() {
            if i > 0 {
                let onceki = parca[i - 1]
                let bosluk = n.kutu.minX - onceki.kutu.maxX
                let kenarBosluk = onceki.metin.last?.isWhitespace == true || n.metin.first?.isWhitespace == true
                if !kenarBosluk && bosluk > max(n.punto, 1) * 0.15 { metin += " " }
            }
            metin += n.metin
        }
        let enBuyuk = parca.max { $0.kutu.width < $1.kutu.width } ?? parca[0]
        return DuzenlemeSatiri(
            nesneler: parca,
            metin: metin.split(whereSeparator: { $0.isWhitespace }).joined(separator: " "),
            kutu: parca.reduce(CGRect.null) { $0.union($1.kutu) },
            tabanY: ortalamaTaban(parca),
            punto: enBuyuk.punto,
            yaziTipiAdi: enBuyuk.yaziTipiAdi,
            renk: enBuyuk.renk)
    }

    /// Verilen noktadaki (ya da en yakın) satır. `tolerans` PDF birimidir.
    public static func satir(_ satirlar: [DuzenlemeSatiri], noktasinda p: CGPoint, tolerans: CGFloat = 8) -> DuzenlemeSatiri? {
        let icinde = satirlar.filter { $0.kutu.insetBy(dx: -tolerans / 2, dy: -tolerans / 2).contains(p) }
        if let en = icinde.min(by: { abs($0.tabanY - p.y) < abs($1.tabanY - p.y) }) { return en }
        let yakin = satirlar.map { ($0, uzaklik($0.kutu, p)) }.filter { $0.1 <= tolerans }
        return yakin.min { $0.1 < $1.1 }?.0
    }

    private static func uzaklik(_ r: CGRect, _ p: CGPoint) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return hypot(dx, dy)
    }

    /// Satırları paragraf bloklarına toplar: sol kenar benzer ve satır aralığı punto × 1,8'den küçükse aynı blok.
    public static func bloklar(_ satirlar: [DuzenlemeSatiri]) -> [MetinBlogu] {
        let sirali = satirlar.sorted { $0.tabanY > $1.tabanY }
        var bloklar: [[DuzenlemeSatiri]] = []
        for s in sirali {
            if let i = bloklar.lastIndex(where: { blok in
                guard let son = blok.last else { return false }
                let aralik = son.tabanY - s.tabanY
                let punto = max(son.punto, s.punto)
                return aralik > 0 && aralik <= punto * 1.8 && abs(son.solX - s.solX) <= punto * 1.5
                    && abs(son.punto - s.punto) <= 1.5
            }) {
                bloklar[i].append(s)
            } else {
                bloklar.append([s])
            }
        }
        return bloklar.map { MetinBlogu(satirlar: $0) }
    }

    public static func blok(_ bloklar: [MetinBlogu], icinde satir: DuzenlemeSatiri) -> MetinBlogu? {
        bloklar.first { $0.satirlar.contains { $0.id == satir.id } }
    }
}
