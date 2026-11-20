import CoreGraphics
import Foundation
import pdfium

/// PDFium iş parçacığı güvenli değildir: bütün çağrılar bu özyinelemeli kilitle sıralanır.
enum PdfiumKilit {
    static let kilit = NSRecursiveLock()
    nonisolated(unsafe) static var hazir = false

    static func calistir<T>(_ govde: () throws -> T) rethrows -> T {
        kilit.lock()
        defer { kilit.unlock() }
        if !hazir {
            var ayar = FPDF_LIBRARY_CONFIG()
            ayar.version = 2
            FPDF_InitLibraryWithConfig(&ayar)
            hazir = true
        }
        return try govde()
    }
}

/// Uygulamayla birlikte gelen, Türkçe harfleri kapsayan gömülebilir yazı tipleri (Noto, OFL).
public enum GomuluYaziTipi: String, CaseIterable, Sendable {
    case sans = "NotoSans-Regular"
    case sansKalin = "NotoSans-Bold"
    case sansItalik = "NotoSans-Italic"
    case serif = "NotoSerif-Regular"
    case serifKalin = "NotoSerif-Bold"
    case mono = "NotoSansMono-Regular"

    public var ad: String {
        switch self {
        case .sans: "Sans"
        case .sansKalin: "Sans Kalın"
        case .sansItalik: "Sans İtalik"
        case .serif: "Serif"
        case .serifKalin: "Serif Kalın"
        case .mono: "Eş aralıklı"
        }
    }

    public var veri: Data? {
        guard let url = Bundle.module.url(forResource: rawValue, withExtension: "ttf", subdirectory: "Yazitipleri") else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Özgün yazı tipi adına en yakın gömülü yazı tipi (ör. "ABCDEF+TimesNewRoman-Bold" → serifKalin).
    public static func eslestir(_ ozgunAd: String, kalin: Bool = false, italik: Bool = false) -> GomuluYaziTipi {
        let a = ozgunAd.lowercased()
        let k = kalin || a.contains("bold") || a.contains("black") || a.contains("heavy") || a.contains("semibold")
        let i = italik || a.contains("italic") || a.contains("oblique")
        if a.contains("mono") || a.contains("courier") || a.contains("consol") { return .mono }
        let serifMi = a.contains("times") || a.contains("serif") && !a.contains("sans") || a.contains("georgia")
            || a.contains("garamond") || a.contains("cambria") || a.contains("book") || a.contains("minion")
        if serifMi { return k ? .serifKalin : .serif }
        if k { return .sansKalin }
        if i { return .sansItalik }
        return .sans
    }
}

/// RGBA renk (0...1), `Sendable` ve kodlanabilir.
public struct RGBA: Sendable, Hashable, Codable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    public static let siyah = RGBA(0, 0, 0)
    public static let beyaz = RGBA(1, 1, 1)
    public static let kirmizi = RGBA(0.86, 0.12, 0.12)
    public static let mavi = RGBA(0.1, 0.35, 0.85)
    public static let yesil = RGBA(0.1, 0.6, 0.25)
    public var cgColor: CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
}

/// PDFium ile açılmış bir belge: içerik nesnesi düzeyinde düzenleme (metin değiştirme,
/// gerçek silme, düzleştirme) ve kaydetme. Bütün yöntemler kilit altında çalışır.
public final class PdfiumBelge: @unchecked Sendable {

    /// Sayfadaki bir metin nesnesi (PDF koordinatları: sol alt köşe 0,0).
    public struct MetinNesnesi: Sendable, Hashable, Identifiable {
        public var id: Int { indeks }
        public let indeks: Int
        public let metin: String
        public let kutu: CGRect
        /// Görünen punto (Tf boyutu × dönüşüm ölçeği).
        public let punto: CGFloat
        public let yaziTipiAdi: String
        public let renk: RGBA
        public let gomulu: Bool
        /// Taban çizgisinin sol noktası (nesne matrisinin öteleme bileşeni).
        public let taban: CGPoint
    }

    /// Nesne türleri (PDFium FPDF_PAGEOBJ_*).
    public struct NesneTuru: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let metin = NesneTuru(rawValue: 1 << 1)
        public static let yol = NesneTuru(rawValue: 1 << 2)
        public static let gorsel = NesneTuru(rawValue: 1 << 3)
        public static let golge = NesneTuru(rawValue: 1 << 4)
        public static let form = NesneTuru(rawValue: 1 << 5)
        public static let hepsi: NesneTuru = [.metin, .yol, .gorsel, .golge, .form]
    }

    private let tampon: UnsafeMutableRawPointer
    let belge: FPDF_DOCUMENT
    var yaziTipleri: [GomuluYaziTipi: FPDF_FONT] = [:]

    public init(veri: Data, parola: String? = nil) throws {
        let boy = max(veri.count, 1)
        let t = UnsafeMutableRawPointer.allocate(byteCount: boy, alignment: 16)
        veri.withUnsafeBytes { kaynak in
            if let k = kaynak.baseAddress { t.copyMemory(from: k, byteCount: veri.count) }
        }
        tampon = t
        let sonuc: (FPDF_DOCUMENT?, UInt) = PdfiumKilit.calistir {
            let d = FPDF_LoadMemDocument64(t, veri.count, parola)
            return (d, d == nil ? FPDF_GetLastError() : 0)
        }
        guard let d = sonuc.0 else {
            tampon.deallocate()
            switch sonuc.1 {
            case 4: throw (parola?.isEmpty ?? true) ? KagitHata.parolaGerekli : KagitHata.parolaYanlis
            case 6: throw KagitHata.desteklenmiyor("bu PDF'in güvenlik yöntemi")
            default: throw KagitHata.pdfium("belge açılamadı (kod \(sonuc.1))")
            }
        }
        belge = d
    }

    public convenience init(url: URL, parola: String? = nil) throws {
        let erisim = url.startAccessingSecurityScopedResource()
        defer { if erisim { url.stopAccessingSecurityScopedResource() } }
        try self.init(veri: try Data(contentsOf: url), parola: parola)
    }

    deinit {
        let d = belge
        let fontlar = Array(yaziTipleri.values)
        PdfiumKilit.calistir {
            for f in fontlar { FPDFFont_Close(f) }
            FPDF_CloseDocument(d)
        }
        tampon.deallocate()
    }

    public var sayfaSayisi: Int { PdfiumKilit.calistir { Int(FPDF_GetPageCount(belge)) } }

    public func sayfaBoyutu(_ i: Int) -> CGSize {
        PdfiumKilit.calistir {
            var b = FS_SIZEF()
            _ = FPDF_GetPageSizeByIndexF(belge, Int32(i), &b)
            return CGSize(width: CGFloat(b.width), height: CGFloat(b.height))
        }
    }

    // MARK: - Sayfa erişimi

    func sayfada<T>(_ i: Int, degistir: Bool = false, _ govde: (FPDF_PAGE) throws -> T) throws -> T {
        try PdfiumKilit.calistir {
            guard i >= 0, i < Int(FPDF_GetPageCount(belge)), let sayfa = FPDF_LoadPage(belge, Int32(i)) else {
                throw KagitHata.pdfium("sayfa \(i + 1) yüklenemedi")
            }
            defer { FPDF_ClosePage(sayfa) }
            let sonuc = try govde(sayfa)
            if degistir, FPDFPage_GenerateContent(sayfa) == 0 {
                throw KagitHata.pdfium("sayfa içeriği yeniden üretilemedi")
            }
            return sonuc
        }
    }

    private static func tur(_ nesne: FPDF_PAGEOBJECT) -> NesneTuru {
        switch FPDFPageObj_GetType(nesne) {
        case 1: .metin
        case 2: .yol
        case 3: .gorsel
        case 4: .golge
        case 5: .form
        default: []
        }
    }

    static func sinir(_ nesne: FPDF_PAGEOBJECT) -> CGRect {
        var l: Float = 0, b: Float = 0, r: Float = 0, t: Float = 0
        guard FPDFPageObj_GetBounds(nesne, &l, &b, &r, &t) != 0 else { return .null }
        return CGRect(x: CGFloat(l), y: CGFloat(b), width: CGFloat(r - l), height: CGFloat(t - b))
    }

    // MARK: - Okuma

    /// Sayfadaki bütün metin nesneleri (çizim sırasıyla).
    public func metinNesneleri(sayfa i: Int) throws -> [MetinNesnesi] {
        try sayfada(i) { sayfa in
            guard let metinSayfasi = FPDFText_LoadPage(sayfa) else { return [] }
            defer { FPDFText_ClosePage(metinSayfasi) }
            var sonuc: [MetinNesnesi] = []
            let n = FPDFPage_CountObjects(sayfa)
            for k in 0..<n {
                guard let nesne = FPDFPage_GetObject(sayfa, k), FPDFPageObj_GetType(nesne) == 1 else { continue }
                let boy = FPDFTextObj_GetText(nesne, metinSayfasi, nil, 0)
                var metin = ""
                if boy > 2 {
                    var tampon = [UInt16](repeating: 0, count: Int(boy) / 2 + 1)
                    _ = FPDFTextObj_GetText(nesne, metinSayfasi, &tampon, boy)
                    if let son = tampon.firstIndex(of: 0) { tampon.removeSubrange(son...) }
                    metin = String(decoding: tampon, as: UTF16.self)
                }
                var punto: Float = 0
                _ = FPDFTextObj_GetFontSize(nesne, &punto)
                var m = FS_MATRIX()
                _ = FPDFPageObj_GetMatrix(nesne, &m)
                let olcek = sqrt(abs(Double(m.a * m.d - m.b * m.c)))
                var ad = ""
                var gomulu = false
                if let font = FPDFTextObj_GetFont(nesne) {
                    let n = FPDFFont_GetBaseFontName(font, nil, 0)
                    if n > 1 {
                        var t = [CChar](repeating: 0, count: n)
                        _ = FPDFFont_GetBaseFontName(font, &t, n)
                        ad = String(cString: t)
                    }
                    gomulu = FPDFFont_GetIsEmbedded(font) == 1
                }
                var r: UInt32 = 0, g: UInt32 = 0, b: UInt32 = 0, a: UInt32 = 255
                _ = FPDFPageObj_GetFillColor(nesne, &r, &g, &b, &a)
                sonuc.append(MetinNesnesi(
                    indeks: Int(k), metin: metin, kutu: Self.sinir(nesne),
                    punto: CGFloat(Double(punto) * (olcek > 0 ? olcek : 1)), yaziTipiAdi: ad,
                    renk: RGBA(Double(r) / 255, Double(g) / 255, Double(b) / 255, Double(a) / 255),
                    gomulu: gomulu, taban: CGPoint(x: CGFloat(m.e), y: CGFloat(m.f))))
            }
            return sonuc
        }
    }

    /// Sayfadaki nesnelerin türleri ve sınırları (karartma/inceleme için).
    public func nesneler(sayfa i: Int) throws -> [(indeks: Int, tur: NesneTuru, kutu: CGRect)] {
        try sayfada(i) { sayfa in
            (0..<FPDFPage_CountObjects(sayfa)).compactMap { k in
                guard let nesne = FPDFPage_GetObject(sayfa, k) else { return nil }
                return (Int(k), Self.tur(nesne), Self.sinir(nesne))
            }
        }
    }

    // MARK: - Değiştirme

    /// Verilen indeksteki nesneleri sayfa içeriğinden kalıcı olarak siler.
    public func nesneleriSil(sayfa i: Int, indeksler: [Int]) throws {
        guard !indeksler.isEmpty else { return }
        try sayfada(i, degistir: true) { sayfa in
            for k in Set(indeksler).sorted(by: >) {
                guard let nesne = FPDFPage_GetObject(sayfa, Int32(k)) else { continue }
                if FPDFPage_RemoveObject(sayfa, nesne) != 0 { FPDFPageObj_Destroy(nesne) }
            }
        }
    }

    /// Kutuyla kesişen (verilen türdeki) nesneleri siler; silinen sayısını döndürür.
    /// Not: metin nesnesi kısmen kesişse de bütünüyle silinir.
    @discardableResult
    public func kutudakileriSil(sayfa i: Int, kutular: [CGRect], turler: NesneTuru = .hepsi) throws -> Int {
        let silinecek = try nesneler(sayfa: i).filter { n in
            !n.tur.isDisjoint(with: turler) && kutular.contains { $0.intersects(n.kutu) }
        }.map(\.indeks)
        try nesneleriSil(sayfa: i, indeksler: silinecek)
        return silinecek.count
    }

    func yaziTipi(_ y: GomuluYaziTipi) throws -> FPDF_FONT {
        if let f = yaziTipleri[y] { return f }
        guard let veri = y.veri else { throw KagitHata.pdfium("yazı tipi bulunamadı: \(y.rawValue)") }
        let f: FPDF_FONT? = veri.withUnsafeBytes { tampon in
            // cid = 1 (Identity-H): Türkçe harfler için şart (ölçüldü).
            FPDFText_LoadFont(belge, tampon.bindMemory(to: UInt8.self).baseAddress, UInt32(veri.count),
                              Int32(FPDF_FONT_TRUETYPE), 1)
        }
        guard let f else { throw KagitHata.pdfium("yazı tipi yüklenemedi: \(y.rawValue)") }
        yaziTipleri[y] = f
        return f
    }

    /// Sayfaya yeni metin nesnesi ekler. `taban` taban çizgisinin sol noktasıdır.
    /// Döndürülen değer eklenen metnin yaklaşık kutusudur.
    @discardableResult
    public func metinEkle(sayfa i: Int, metin: String, taban: CGPoint, punto: CGFloat,
                          yaziTipi y: GomuluYaziTipi = .sans, renk: RGBA = .siyah) throws -> CGRect {
        try sayfada(i, degistir: true) { sayfa in
            let font = try yaziTipi(y)
            guard let nesne = FPDFPageObj_CreateTextObj(belge, font, Float(punto)) else {
                throw KagitHata.pdfium("metin nesnesi oluşturulamadı")
            }
            var birimler = Array(metin.utf16) + [0]
            _ = birimler.withUnsafeMutableBufferPointer { FPDFText_SetText(nesne, $0.baseAddress) }
            _ = FPDFPageObj_SetFillColor(nesne, UInt32(renk.r * 255), UInt32(renk.g * 255),
                                         UInt32(renk.b * 255), UInt32(renk.a * 255))
            FPDFPageObj_Transform(nesne, 1, 0, 0, 1, Double(taban.x), Double(taban.y))
            FPDFPage_InsertObject(sayfa, nesne)
            return Self.sinir(nesne)
        }
    }

    /// Sayfadaki açıklamaları ve form alanlarını içeriğe işler (düzleştirme).
    public func duzlestir(sayfa i: Int) throws {
        try PdfiumKilit.calistir {
            guard let sayfa = FPDF_LoadPage(belge, Int32(i)) else { throw KagitHata.pdfium("sayfa yüklenemedi") }
            defer { FPDF_ClosePage(sayfa) }
            _ = FPDFPage_Flatten(sayfa, 1)
        }
    }

    // MARK: - Kaydetme

    nonisolated(unsafe) private static var yazilan = Data()

    /// Belgenin tam (artımsız) kopyasını üretir.
    public func kaydet() throws -> Data {
        try PdfiumKilit.calistir {
            Self.yazilan = Data()
            var yazici = FPDF_FILEWRITE()
            yazici.version = 1
            yazici.WriteBlock = { _, veri, boy in
                if let veri { PdfiumBelge.yazilan.append(veri.assumingMemoryBound(to: UInt8.self), count: Int(boy)) }
                return 1
            }
            guard FPDF_SaveAsCopy(belge, &yazici, 2) != 0 else { throw KagitHata.pdfium("kaydedilemedi") }
            let sonuc = Self.yazilan
            Self.yazilan = Data()
            return sonuc
        }
    }
}
