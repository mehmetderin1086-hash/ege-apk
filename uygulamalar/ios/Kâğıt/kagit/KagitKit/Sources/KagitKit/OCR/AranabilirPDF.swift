import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit

/// Aranabilir PDF üretimi: görüntü sayfalarının üstüne görünmez bir metin katmanı bindirir.
public struct AranabilirSecenekleri: Sendable {
    /// OCR dilleri (Vision kodları).
    public var diller: [String] = MetinTanima.varsayilanDiller
    /// OCR için sayfa çözünürlüğü.
    public var ocrDpi: CGFloat = 200
    /// Hızlı (daha az doğru) tanıma.
    public var hizli = false
    /// Görüntülerin JPEG kalitesi (0...1).
    public var jpegKalitesi: Double = 0.8
    /// Zaten metni olan sayfalara dokunma.
    public var metniOlanlariAtla = true
    /// Görüntüden PDF yaparken OCR katmanı eklensin.
    public var ocr = true

    public init() {}
}

/// `AranabilirPDF.yap` sonucu.
public struct AranabilirRapor: Sendable, Equatable {
    public var toplamSayfa = 0
    public var islenen = 0
    public var atlanan = 0
    public var tanimananSatir = 0
}

public enum AranabilirPDF {

    /// Sayfanın seçilebilir/aranabilir gerçek metni var mı (en az birkaç harf).
    public static func metniVarMi(_ sayfa: PDFPage) -> Bool {
        let s = sayfa.string ?? ""
        return s.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count >= 3
    }

    // MARK: - Görünmez katman

    /// Satırları, kutularına yatay ölçekle oturtarak görünmez (render mode 3) metin olarak çizer.
    /// `boyut` sayfa boyutu (punto); satır kutuları görüntüye göre normalize.
    public static func gorunmezMetinCiz(_ satirlar: [OCRSatiri], ctx: CGContext, boyut: CGSize) {
        for s in satirlar {
            let metin = s.metin.trimmingCharacters(in: .whitespaces)
            guard !metin.isEmpty, s.kutu.width > 0, s.kutu.height > 0 else { continue }
            let kutu = CGRect(x: s.kutu.minX * boyut.width, y: s.kutu.minY * boyut.height,
                              width: s.kutu.width * boyut.width, height: s.kutu.height * boyut.height)
            let punto = max(2, kutu.height * 0.8)
            let font = CTFontCreateWithName("Helvetica" as CFString, punto, nil)
            let nitelik: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
            ]
            let satir = CTLineCreateWithAttributedString(NSAttributedString(string: metin, attributes: nitelik))
            let genislik = CGFloat(CTLineGetTypographicBounds(satir, nil, nil, nil))
            guard genislik > 0 else { continue }
            let olcek = kutu.width / genislik
            ctx.saveGState()
            ctx.setTextDrawingMode(.invisible)
            ctx.textMatrix = CGAffineTransform(a: olcek, b: 0, c: 0, d: 1, tx: kutu.minX, ty: kutu.minY + kutu.height * 0.2)
            CTLineDraw(satir, ctx)
            ctx.restoreGState()
        }
    }

    /// Görüntü + (isteğe bağlı) görünmez metinden tek sayfalık PDF verisi.
    /// `jpeg` verilirse görüntü yeniden kodlanmadan (DCT) gömülür.
    public static func gorselSayfaPDF(_ goruntu: CGImage, jpeg: Data? = nil, boyut: CGSize,
                                      satirlar: [OCRSatiri]) -> Data {
        let yazici = PDFCizim.Yazici()
        sayfayiEkle(yazici, goruntu, jpeg: jpeg, boyut: boyut, satirlar: satirlar)
        return yazici.bitir()
    }

    static func sayfayiEkle(_ yazici: PDFCizim.Yazici, _ goruntu: CGImage, jpeg: Data?, boyut: CGSize, satirlar: [OCRSatiri]) {
        let cizilecek: CGImage = jpeg.flatMap(jpegGoruntusu) ?? goruntu
        yazici.sayfa(CGRect(origin: .zero, size: boyut)) { ctx in
            ctx.interpolationQuality = .high
            ctx.draw(cizilecek, in: CGRect(origin: .zero, size: boyut))
            gorunmezMetinCiz(satirlar, ctx: ctx, boyut: boyut)
        }
    }

    static func jpegGoruntusu(_ veri: Data) -> CGImage? {
        guard let saglayici = CGDataProvider(data: veri as CFData) else { return nil }
        return CGImage(jpegDataProviderSource: saglayici, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Görüntüyü A4'e sığacak en büyük boyuta ölçekler (en-boy oranı korunur, kenar boşluğu yok).
    public static func a4Sigdir(piksel: CGSize) -> CGSize {
        guard piksel.width > 0, piksel.height > 0 else { return PDFCizim.Boyut.a4.boyut }
        let yatay = piksel.width > piksel.height
        let a4 = PDFCizim.Boyut.a4.yonlu(yatay: yatay)
        let o = min(a4.width / piksel.width, a4.height / piksel.height)
        return CGSize(width: (piksel.width * o).rounded(), height: (piksel.height * o).rounded())
    }

    // MARK: - Görsellerden PDF

    /// Görsellerden (her biri bir sayfa) PDF üretir. `secenekler.ocr` açıksa görünmez metin katmanı eklenir.
    public static func gorsellerdenPDF(_ goruntuler: [CGImage], baslik: String? = nil,
                                       secenekler: AranabilirSecenekleri = .init(),
                                       ilerleme: Ilerleme? = nil) async throws -> Data {
        guard !goruntuler.isEmpty else { throw KagitHata.bosGirdi }
        let yazici = PDFCizim.Yazici(baslik: baslik)
        for (i, g) in goruntuler.enumerated() {
            try iptalDenetle()
            let boyut = a4Sigdir(piksel: CGSize(width: g.width, height: g.height))
            var satirlar: [OCRSatiri] = []
            if secenekler.ocr {
                satirlar = (try? await MetinTanima.tani(g, diller: secenekler.diller, hizli: secenekler.hizli)) ?? []
            }
            let jpeg = PDFCizim.kodla(g, tur: .jpeg, kalite: secenekler.jpegKalitesi)
            sayfayiEkle(yazici, g, jpeg: jpeg, boyut: boyut, satirlar: satirlar)
            ilerleme?(Double(i + 1) / Double(goruntuler.count))
        }
        return yazici.bitir()
    }

    // MARK: - Var olan PDF'i aranabilir yapma

    /// PDF'i aranabilir yapar: metni olmayan sayfalara (ya da `sayfalar` ile seçilenlere) görünmez
    /// OCR katmanı ekler. Metni olan sayfalar `metniOlanlariAtla` açıkken olduğu gibi kalır.
    public static func yap(veri: Data, parola: String? = nil, sayfalar: [Int]? = nil,
                           secenekler: AranabilirSecenekleri = .init(),
                           ilerleme: Ilerleme? = nil) async throws -> (veri: Data, rapor: AranabilirRapor) {
        let belge = try Belge.ac(veri: veri, parola: parola)
        var rapor = AranabilirRapor(toplamSayfa: belge.pageCount)
        let hedefler = sayfalar ?? Array(0..<belge.pageCount)
        guard belge.pageCount > 0 else { throw KagitHata.bosGirdi }

        for (adim, i) in hedefler.enumerated() {
            try iptalDenetle()
            guard i >= 0, i < belge.pageCount, let sayfa = belge.page(at: i) else { continue }
            if secenekler.metniOlanlariAtla && metniVarMi(sayfa) {
                rapor.atlanan += 1
                ilerleme?(Double(adim + 1) / Double(hedefler.count))
                continue
            }
            guard let goruntu = PDFCizim.goruntu(sayfa, dpi: secenekler.ocrDpi) else {
                rapor.atlanan += 1
                continue
            }
            let satirlar = try await MetinTanima.tani(goruntu, diller: secenekler.diller, hizli: secenekler.hizli)
            rapor.tanimananSatir += satirlar.count
            try katmanEkle(belge, sayfaIndeksi: i, satirlar: satirlar)
            rapor.islenen += 1
            ilerleme?(Double(adim + 1) / Double(hedefler.count))
        }
        if rapor.islenen == 0 { return (veri, rapor) }
        return (try Belge.veri(belge), rapor)
    }

    /// Sayfayı, özgün içeriği + görünmez metinle yeniden kurup yerine koyar. Açıklamalar korunur.
    static func katmanEkle(_ belge: PDFDocument, sayfaIndeksi i: Int, satirlar: [OCRSatiri]) throws {
        guard let eski = belge.page(at: i) else { return }
        let aciklamalar = eski.annotations
        let onceki = eski.displaysAnnotations
        eski.displaysAnnotations = false
        defer { eski.displaysAnnotations = onceki }

        let yazici = PDFCizim.Yazici()
        yazici.sayfaKopyala(eski) { ctx, kutu in
            gorunmezMetinCiz(satirlar, ctx: ctx, boyut: kutu.size)
        }
        guard let yeniBelge = PDFDocument(data: yazici.bitir()), let yeni = yeniBelge.page(at: 0) else {
            throw KagitHata.genel("OCR katmanı oluşturulamadı (sayfa \(i + 1))")
        }
        for a in aciklamalar {
            guard let kopya = a.copy() as? PDFAnnotation else { continue }
            yeni.addAnnotation(kopya)
        }
        belge.insert(yeni, at: i)
        belge.removePage(at: i + 1)
    }
}
