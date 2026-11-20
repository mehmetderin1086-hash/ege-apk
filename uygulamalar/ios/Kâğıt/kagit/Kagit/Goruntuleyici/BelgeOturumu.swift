import KagitKit
import PDFKit
import SwiftUI

/// Belge ekranının kipleri. Her kipin alt araç çubuğu ayrı dosyada tanımlanır.
enum BelgeKipi: String, CaseIterable, Identifiable {
    case oku, isaretle, duzenle, imzala, sayfalar, ogretmen, yapay
    var id: String { rawValue }

    var ad: String {
        switch self {
        case .oku: "Oku"
        case .isaretle: "İşaretle"
        case .duzenle: "Düzenle"
        case .imzala: "Doldur & İmzala"
        case .sayfalar: "Sayfalar"
        case .ogretmen: "Öğretmen"
        case .yapay: "Yapay Zekâ"
        }
    }

    var simge: String {
        switch self {
        case .oku: "book"
        case .isaretle: "highlighter"
        case .duzenle: "character.cursor.ibeam"
        case .imzala: "signature"
        case .sayfalar: "square.grid.3x2"
        case .ogretmen: "checkmark.seal"
        case .yapay: "sparkles"
        }
    }
}

/// Açık bir belgenin düzenleme oturumu. Görünüm ile kip araç çubukları arasındaki ortak durum.
///
/// - `belge` yalnız ana iş parçacığında kullanılır (PDFView'e bağlı).
/// - Arka plan işleri için `veriAl()` ile bağımsız kopya alınır, sonuç `belgeyiDegistir(_:)` ile geri konur.
@Observable
final class BelgeOturumu {
    let oge: KitaplikOgesi
    var url: URL { oge.url }

    private(set) var belge: PDFDocument?
    var parola: String?
    var parolaGerekli = false
    /// Kaydedilmemiş değişiklik var mı.
    var degisti = false
    var kip: BelgeKipi = .oku
    var seciliSayfa = 0
    var calisiyor: String?
    var ileti: Ileti?

    /// PDFView'e erişim (PDFGorunumu bağlar).
    @ObservationIgnored weak var pdfView: PDFView?

    /// Ayarlanınca PDF üzerindeki dokunuşlar bu işleyiciye gider (damga/metin yerleştirme vb.).
    /// Parametreler: sayfa, sayfa koordinatında nokta. `nil` iken PDFView normal davranır.
    @ObservationIgnored var dokunusIsleyici: ((PDFPage, CGPoint) -> Void)? {
        didSet { dokunusEtkin = dokunusIsleyici != nil }
    }
    private(set) var dokunusEtkin = false

    /// Kendi geri alma yığınımız (PDFKit programatik açıklamaları kaydetmez).
    let geriAlma = UndoManager()
    var geriAlinabilir = false
    var yinelenebilir = false

    /// Okuma görünümü ayarları.
    var gorunumKipi: PDFDisplayMode = .singlePageContinuous
    var yatayKaydirma = false
    var okumaRengi: OkumaRengi = .normal

    enum OkumaRengi: String, CaseIterable, Identifiable {
        case normal, sepya, gece
        var id: String { rawValue }
        var ad: String { switch self { case .normal: "Normal"; case .sepya: "Sepya"; case .gece: "Gece" } }
    }

    private var surumYedegiAlindi = false

    /// Modül B: işaretleme/düzenleme durumu (seçili açıklama, araçlar, sayfa katmanı).
    @ObservationIgnored private(set) var duzenleyici: DuzenleyiciDurumu!

    init(oge: KitaplikOgesi) {
        self.oge = oge
        geriAlma.groupsByEvent = false
        duzenleyici = DuzenleyiciDurumu(oturum: self)
    }

    // MARK: Yükleme

    func yukle() {
        guard belge == nil else { return }
        guard let b = PDFDocument(url: url) else {
            ileti = Ileti(KagitHata.acilamadi(oge.tamAd))
            return
        }
        if b.isLocked {
            if let parola, b.unlock(withPassword: parola) {
                belge = b
            } else {
                parolaGerekli = true
            }
        } else {
            belge = b
        }
    }

    func kilidiAc(_ p: String) -> Bool {
        guard let b = PDFDocument(url: url), b.unlock(withPassword: p) else { return false }
        parola = p
        parolaGerekli = false
        belge = b
        return true
    }

    // MARK: Değişiklik kaydı

    /// Geri alınabilir bir değişiklik uygular. `yap` ve `geriAl` ana iş parçacığında çalışır.
    func degistir(_ ad: String, yap: @escaping () -> Void, geriAl: @escaping () -> Void) {
        yap()
        geriAlma.registerUndo(withTarget: self) { o in
            o.degistir(ad, yap: geriAl, geriAl: yap)
        }
        geriAlma.setActionName(ad)
        isaretle()
    }

    func aciklamaEkle(_ a: PDFAnnotation, _ sayfa: PDFPage, ad: String = "Ekle") {
        degistir(ad, yap: { sayfa.addAnnotation(a) }, geriAl: { sayfa.removeAnnotation(a) })
    }

    func aciklamaSil(_ a: PDFAnnotation) {
        guard let sayfa = a.page else { return }
        degistir("Sil", yap: { sayfa.removeAnnotation(a) }, geriAl: { sayfa.addAnnotation(a) })
    }

    func geriAl() { geriAlma.undo(); durumGuncelle() }
    func yinele() { geriAlma.redo(); durumGuncelle() }

    func isaretle() {
        degisti = true
        durumGuncelle()
    }

    private func durumGuncelle() {
        geriAlinabilir = geriAlma.canUndo
        yinelenebilir = geriAlma.canRedo
        pdfView?.setNeedsDisplay()
        if let s = pdfView?.currentPage { pdfView?.annotationsChanged(on: s) }
    }

    // MARK: Arka plan işleri için

    /// Belgenin bağımsız bir kopyası (arka plan işleri ve PDFium için).
    func veriAl() throws -> Data {
        try veriUret(KayitSecenekleri(kullaniciParolasi: parola, sahipParolasi: parola))
    }

    /// Kayıt hattı (modül B): bekleyen kalem çizgilerini açıklamaya çevirir, damga/örtüleri içeriğe işler,
    /// form alanları için /AcroForm yamasını uygular.
    private func veriUret(_ secenekler: KayitSecenekleri) throws -> Data {
        guard let belge else { throw KagitHata.bosGirdi }
        duzenleyici.kayitOncesi()
        return try KayitIsleme.veri(belge, secenekler: secenekler)
    }

    /// Belgeyi yeni veriyle değiştirir (ör. PDFium ile metin düzenlendikten sonra). Geri alınabilir.
    func belgeyiDegistir(_ veri: Data, ad: String = "Düzenle") throws {
        guard let yeni = PDFDocument(data: veri) else { throw KagitHata.dogrulamaBasarisiz("yeni belge açılamadı") }
        if yeni.isLocked, let parola { _ = yeni.unlock(withPassword: parola) }
        guard let eski = belge else { return }
        let sayfa = seciliSayfa
        degistir(ad, yap: { [weak self] in self?.belgeKoy(yeni, sayfa: sayfa) },
                 geriAl: { [weak self] in self?.belgeKoy(eski, sayfa: sayfa) })
    }

    private func belgeKoy(_ b: PDFDocument, sayfa: Int) {
        duzenleyici.belgeDegisti()
        belge = b
        pdfView?.document = b
        if let s = b.page(at: min(sayfa, max(b.pageCount - 1, 0))) { pdfView?.go(to: s) }
    }

    /// Sayfa yapısı değişince (ekle/sil/taşı) görünümü tazeler.
    func sayfalarDegisti() {
        pdfView?.layoutDocumentView()
        isaretle()
    }

    // MARK: Kaydetme

    /// Yerinde kaydeder. İlk kayıttan önce özgün dosyanın sürüm yedeğini alır.
    func kaydet(secenekler: KayitSecenekleri? = nil) async -> Bool {
        guard let belge else { return false }
        calisiyor = "Kaydediliyor…"
        defer { calisiyor = nil }
        do {
            if !surumYedegiAlindi {
                SurumDeposu.yedekle(url)
                surumYedegiAlindi = true
            }
            var s = secenekler ?? KayitSecenekleri()
            if let parola, s.kullaniciParolasi == nil { s.kullaniciParolasi = parola; s.sahipParolasi = parola }
            let veri = try veriUret(s)
            let hedef = url
            let sayfa = belge.pageCount
            let parola = s.kullaniciParolasi
            try await Task.detached { try Belge.yaz(veri, hedef, beklenenSayfa: sayfa, parola: parola) }.value
            degisti = false
            return true
        } catch {
            ileti = Ileti(error)
            return false
        }
    }

    /// Kopyasını geçici dosyaya yazar (paylaşım / "farklı kaydet" için).
    func kopyaYaz(ad: String? = nil, secenekler: KayitSecenekleri = .init()) throws -> URL {
        guard let belge else { throw KagitHata.bosGirdi }
        let hedef = Gecici.dosya("\(ad ?? oge.ad).pdf")
        try Belge.yaz(try veriUret(secenekler), hedef, beklenenSayfa: belge.pageCount, parola: secenekler.kullaniciParolasi)
        return hedef
    }
}

/// Belgelerin önceki sürümleri (ilk kayıttan önce alınır; belge başına son 5 sürüm).
enum SurumDeposu {
    static var kok: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Surumler", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func klasor(_ url: URL) -> URL {
        let anahtar = String(url.standardizedFileURL.path.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }, radix: 36)
        let k = kok.appendingPathComponent(anahtar, isDirectory: true)
        try? FileManager.default.createDirectory(at: k, withIntermediateDirectories: true)
        return k
    }

    static func yedekle(_ url: URL) {
        let k = klasor(url)
        let bicim = DateFormatter()
        bicim.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"
        let hedef = k.appendingPathComponent("\(bicim.string(from: Date())).pdf")
        try? FileManager.default.copyItem(at: url, to: hedef)
        let hepsi = surumler(url)
        for eski in hepsi.dropFirst(5) { try? FileManager.default.removeItem(at: eski.url) }
    }

    static func surumler(_ url: URL) -> [(url: URL, tarih: Date)] {
        let k = klasor(url)
        // copyItem özgün oluşturma tarihini korur; sıralama dosya adındaki damgaya göre yapılır.
        let bicim = DateFormatter()
        bicim.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"
        let dosyalar = (try? FileManager.default.contentsOfDirectory(at: k, includingPropertiesForKeys: nil)) ?? []
        return dosyalar.map { ($0, bicim.date(from: $0.deletingPathExtension().lastPathComponent) ?? .distantPast) }
            .sorted { $0.tarih > $1.tarih }
    }

    static func geriYukle(_ surum: URL, _ hedef: URL) throws {
        yedekle(hedef)
        let veri = try Data(contentsOf: surum)
        try Belge.yaz(veri, hedef)
    }
}
