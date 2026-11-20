import CoreGraphics
import Foundation
import PDFKit

/// PDF'ten Word / Excel / PowerPoint (cihazda, yaklaşık). Daha iyi düzen için `PDFStudioIstemcisi`.
public enum PDFOffice {

    // MARK: Word

    /// Sayfa metni + punto sezgisiyle başlık/paragraf/madde + gömülü görseller. Metni olmayan (taranmış) sayfa görüntü olarak eklenir.
    public static func pdftenWord(_ giris: URL, aralik: String = "", parola: String? = nil, ilerleme: Ilerleme? = nil) throws -> URL {
        let b = try Belge.ac(giris, parola: parola)
        let idx = try SayfaAraligi.coz(aralik, sayfaSayisi: b.pageCount)
        let bloklar = try PDFYapisi.cikar(b, sayfalar: idx) { ilerleme?($0 * 0.4) }
        let gorseller = try PDFGorsel.gomuluGorseller(giris, aralik: aralik, enAz: 48, bicim: .jpeg, kalite: 0.85, parola: parola) {
            ilerleme?(0.4 + $0 * 0.3)
        }
        var sayfaGorselleri: [Int: [PDFGorsel.GomuluGorsel]] = [:]
        for g in gorseller { sayfaGorselleri[g.sayfa + 1, default: []].append(g) }

        // Bloklari sayfaya göre grupla
        var sayfaBloklari: [(no: Int, bloklar: [PDFBlok])] = []
        for blok in bloklar {
            if case .sayfa(let n) = blok { sayfaBloklari.append((n, [])) }
            else if !sayfaBloklari.isEmpty { sayfaBloklari[sayfaBloklari.count - 1].bloklar.append(blok) }
        }
        var ogeler: [OfficeYazici.DocxOge] = []
        for (k, s) in sayfaBloklari.enumerated() {
            try iptalDenetle()
            if k > 0 { ogeler.append(.sayfaSonu) }
            for blok in s.bloklar {
                switch blok {
                case .baslik(let n, let t): ogeler.append(.baslik(n, t))
                case .paragraf(let t): ogeler.append(.paragraf(t))
                case .madde(let t): ogeler.append(.madde(t))
                case .sayfa: break
                }
            }
            let resimler = sayfaGorselleri[s.no] ?? []
            for g in resimler {
                ogeler.append(.resim(.init(veri: g.veri, uzanti: g.uzanti, genislikPx: g.genislik, yukseklikPx: g.yukseklik)))
            }
            if s.bloklar.isEmpty, resimler.isEmpty {
                try autoreleasepool {
                    guard let sayfa = b.page(at: s.no - 1), let img = PDFCizim.goruntu(sayfa, dpi: 130),
                          let jpeg = PDFCizim.kodla(img, tur: .jpeg, kalite: 0.8) else { return }
                    ogeler.append(.resim(.init(veri: jpeg, uzanti: "jpg", genislikPx: img.width, yukseklikPx: img.height)))
                }
            }
            ilerleme?(0.7 + Double(k + 1) / Double(sayfaBloklari.count) * 0.3)
        }
        let ad = giris.deletingPathExtension().lastPathComponent
        let hedef = IsYardimcisi.cikti(giris, "", uzanti: "docx")
        try OfficeYazici.docx(ogeler, baslik: ad).write(to: hedef)
        return hedef
    }

    // MARK: Excel

    struct Parca {
        var x: CGFloat
        var sag: CGFloat
        var punto: CGFloat
        var metin: String
    }

    /// Metin nesnelerini satırlara, sol kenar kümelerini sütunlara dönüştürür.
    static func tablo(_ nesneler: [PdfiumBelge.MetinNesnesi]) -> [[OfficeYazici.Hucre?]] {
        let ogeler = nesneler.filter { !$0.metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.kutu.midY > $1.kutu.midY }
        guard !ogeler.isEmpty else { return [] }
        // Satırlar
        var satirlar: [(ortY: CGFloat, ogeler: [PdfiumBelge.MetinNesnesi])] = []
        for o in ogeler {
            let tol = max(2, o.punto * 0.5)
            if let i = satirlar.indices.last(where: { abs(satirlar[$0].ortY - o.kutu.midY) < tol }) {
                satirlar[i].ogeler.append(o)
                satirlar[i].ortY = satirlar[i].ogeler.map(\.kutu.midY).reduce(0, +) / CGFloat(satirlar[i].ogeler.count)
            } else {
                satirlar.append((o.kutu.midY, [o]))
            }
        }
        // Yakın parçaları birleştir
        var birlesik: [[Parca]] = []
        for s in satirlar {
            var parcalar: [Parca] = []
            for o in s.ogeler.sorted(by: { $0.kutu.minX < $1.kutu.minX }) {
                let yeni = Parca(x: o.kutu.minX, sag: o.kutu.maxX, punto: max(o.punto, 1), metin: o.metin.trimmingCharacters(in: .whitespaces))
                if var son = parcalar.last, yeni.x - son.sag < son.punto * 0.45 {
                    son.metin += (yeni.x - son.sag > son.punto * 0.12 ? " " : "") + yeni.metin
                    son.sag = max(son.sag, yeni.sag)
                    parcalar[parcalar.count - 1] = son
                } else {
                    parcalar.append(yeni)
                }
            }
            birlesik.append(parcalar)
        }
        // Sütun çapaları: sol kenar kümeleri
        let tol: CGFloat = 8
        let xler = birlesik.flatMap { $0.map(\.x) }.sorted()
        var capalar: [CGFloat] = []
        var oncekiX: CGFloat = -.infinity
        for x in xler {
            if x - oncekiX > tol { capalar.append(x) }
            oncekiX = x
        }
        var sonuc: [[OfficeYazici.Hucre?]] = []
        for s in birlesik {
            var satir = [OfficeYazici.Hucre?](repeating: nil, count: capalar.count)
            var metinler = [String?](repeating: nil, count: capalar.count)
            for p in s {
                let c = capalar.lastIndex(where: { $0 <= p.x + tol }) ?? 0
                metinler[c] = metinler[c].map { $0 + " " + p.metin } ?? p.metin
            }
            for (c, m) in metinler.enumerated() { if let m { satir[c] = hucre(m) } }
            sonuc.append(satir)
        }
        return sonuc
    }

    static func hucre(_ m: String) -> OfficeYazici.Hucre {
        let t = m.trimmingCharacters(in: .whitespaces)
        if t.range(of: #"^-?(0|[1-9]\d{0,14})([.,]\d+)?$"#, options: .regularExpression) != nil,
           let d = Double(t.replacingOccurrences(of: ",", with: ".")) {
            return .sayi(d)
        }
        return .metin(m)
    }

    public static func pdftenExcel(_ giris: URL, aralik: String = "", parola: String? = nil, ilerleme: Ilerleme? = nil) throws -> URL {
        let erisim = giris.startAccessingSecurityScopedResource()
        defer { if erisim { giris.stopAccessingSecurityScopedResource() } }
        let veri = try Data(contentsOf: giris)
        let pdfium = try PdfiumBelge(veri: veri, parola: parola)
        let idx = try SayfaAraligi.coz(aralik, sayfaSayisi: pdfium.sayfaSayisi)
        var sayfalar: [OfficeYazici.Sayfa] = []
        var dolu = false
        for (k, i) in idx.enumerated() {
            try iptalDenetle()
            try autoreleasepool {
                let satirlar = tablo(try pdfium.metinNesneleri(sayfa: i))
                if satirlar.isEmpty {
                    sayfalar.append(.init(ad: OfficeYazici.sayfaAdi("Sayfa \(i + 1)", mevcut: sayfalar.map(\.ad)),
                                          satirlar: [[.metin("Bu sayfada metin yok (taranmış olabilir).")]]))
                } else {
                    dolu = true
                    sayfalar.append(.init(ad: OfficeYazici.sayfaAdi("Sayfa \(i + 1)", mevcut: sayfalar.map(\.ad)), satirlar: satirlar))
                }
            }
            ilerleme?(Double(k + 1) / Double(idx.count))
        }
        guard dolu else { throw PDFYapisi.metinYokHatasi(idx.count) }
        let hedef = IsYardimcisi.cikti(giris, "", uzanti: "xlsx")
        try OfficeYazici.xlsx(sayfalar).write(to: hedef)
        return hedef
    }

    // MARK: PowerPoint

    /// Her sayfa bir slayt (sayfa görüntüsü).
    public static func pdftenPowerPoint(_ giris: URL, aralik: String = "", dpi: Int = 130, parola: String? = nil,
                                        ilerleme: Ilerleme? = nil) throws -> URL {
        let b = try Belge.ac(giris, parola: parola)
        let idx = try SayfaAraligi.coz(aralik, sayfaSayisi: b.pageCount)
        var slaytlar: [OfficeYazici.Slayt] = []
        for (k, i) in idx.enumerated() {
            try iptalDenetle()
            try autoreleasepool {
                guard let s = b.page(at: i), let img = PDFCizim.goruntu(s, dpi: CGFloat(dpi)),
                      let jpeg = PDFCizim.kodla(img, tur: .jpeg, kalite: 0.82) else {
                    throw KagitHata.genel("Sayfa \(i + 1) görüntüye çevrilemedi.")
                }
                slaytlar.append(.init(jpeg: jpeg, genislikPx: img.width, yukseklikPx: img.height))
            }
            ilerleme?(Double(k + 1) / Double(idx.count))
        }
        let hedef = IsYardimcisi.cikti(giris, "", uzanti: "pptx")
        try OfficeYazici.pptx(slaytlar).write(to: hedef)
        return hedef
    }
}
