import KagitKit
import PDFKit
import PencilKit
import SwiftUI
import UIKit

/// Düzenle kipindeki araçlar.
enum DuzenleAraci: String, CaseIterable, Identifiable {
    case metniDuzenle, metinEkle, ortu, baglanti, gorsel
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .metniDuzenle: "Metni düzenle"
        case .metinEkle: "Metin ekle"
        case .ortu: "Beyaz örtü"
        case .baglanti: "Bağlantı"
        case .gorsel: "Görsel"
        }
    }
    var simge: String {
        switch self {
        case .metniDuzenle: "character.cursor.ibeam"
        case .metinEkle: "plus.rectangle.on.rectangle"
        case .ortu: "rectangle.fill"
        case .baglanti: "link"
        case .gorsel: "photo.badge.plus"
        }
    }
}

/// Sayfa katmanının (overlay) o anki etkileşim biçimi.
enum SayfaEtkilesimi: Equatable {
    case yok, kalem, surukle, secim
}

/// Sürüklenerek çizilen nesne türü (önizleme için).
enum SuruklemeTuru: Equatable {
    case sekil(AciklamaFabrikasi.SekilTuru)
    case kutu
}

/// Sayfaya dokunarak yerleştirilecek öğe.
struct Yerlestirme {
    let ad: String
    var tekSefer = true
    let ekle: (PDFPage, CGPoint) -> Void
}

/// Açılan düzenleme sayfaları.
enum DuzenleIstegi: Identifiable {
    case kutuEkle(PDFPage, CGPoint)
    case kutuDuzenle(PDFAnnotation)
    case notEkle(PDFPage, CGPoint)
    case notDuzenle(PDFAnnotation)
    case pdfiumMetinEkle(Int, CGPoint)
    case pdfiumSatir(Int, DuzenlemeSatiri)
    case baglanti(PDFPage, CGRect)
    case alanListesi(PDFPage, CGPoint)

    var id: String {
        switch self {
        case .kutuEkle: "kutuEkle"
        case .kutuDuzenle: "kutuDuzenle"
        case .notEkle: "notEkle"
        case .notDuzenle: "notDuzenle"
        case .pdfiumMetinEkle: "pdfiumMetinEkle"
        case .pdfiumSatir(let i, let s): "pdfiumSatir-\(i)-\(s.id)"
        case .baglanti: "baglanti"
        case .alanListesi: "alanListesi"
        }
    }
}

/// Açıklamanın geri alınabilir anlık görüntüsü (taşıma, boyutlandırma, renk değiştirme).
struct AciklamaAni {
    var bounds: CGRect
    var renk: UIColor
    var yaziRengi: UIColor
    var yollar: [UIBezierPath]?
    var baslangic: CGPoint
    var bitis: CGPoint
    var tanim: DamgaTanimi?
    var icerik: String?

    init(_ a: PDFAnnotation) {
        bounds = a.bounds
        renk = a.color
        yaziRengi = a.fontColor ?? .black
        yollar = a.type == "Ink" ? (a.paths ?? []).map { $0.copy() as! UIBezierPath } : nil
        baslangic = a.startPoint
        bitis = a.endPoint
        tanim = (a as? KagitDamgasi)?.tanim
        icerik = a.contents
    }

    func uygula(_ a: PDFAnnotation) {
        a.bounds = bounds
        a.color = renk
        if a.type == "FreeText" { a.fontColor = yaziRengi }
        if let yollar, a.type == "Ink" {
            for p in a.paths ?? [] { a.remove(p) }
            for p in yollar { a.add(p.copy() as! UIBezierPath) }
        }
        if a.type == "Line" {
            a.startPoint = baslangic
            a.endPoint = bitis
        }
        if let d = a as? KagitDamgasi, let tanim { d.tanim = tanim }
        if a.type == "FreeText" || a.type == "Text", a.contents != icerik { a.contents = icerik }
    }
}

/// Bir belge oturumunun işaretleme/düzenleme durumu: araçlar, seçili açıklama, kalem ve PDFium işleri.
@Observable
final class DuzenleyiciDurumu {
    @ObservationIgnored weak var oturum: BelgeOturumu?
    let ayarlar = IsaretAyarlari()
    @ObservationIgnored let katman = SayfaKatmani()

    var arac: IsaretAraci = .sec {
        didSet { if arac != oldValue { aracDegisti() } }
    }
    var duzenleAraci: DuzenleAraci = .metniDuzenle {
        didSet { if duzenleAraci != oldValue { aracDegisti() } }
    }
    var secili: PDFAnnotation? {
        didSet { katman.yenile() }
    }
    var vurgu: (sayfa: PDFPage, kutu: CGRect)? {
        didSet { katman.yenile() }
    }
    var alanlariVurgula = false {
        didSet { katman.yenile() }
    }
    var yerlestirme: Yerlestirme? {
        didSet { dokunusuKur() }
    }
    var istek: DuzenleIstegi?
    /// Sayfa yapısı değişince arttırılır (sayfa düzenleyici küçük resimleri için).
    var sayfaSurumu = 0
    var metinSecimiVar = false
    var damgaSeciciAcik = false
    var gorselSeciciAcik = false
    var duzenleGorselSeciciAcik = false
    var aciklamaListesiAcik = false
    var imzaCizimAcik = false

    @ObservationIgnored private var secimGorevi: Task<Void, Never>?
    @ObservationIgnored private var alanIndeksi = -1
    @ObservationIgnored private var hareketAni: AciklamaAni?
    @ObservationIgnored private var pdfiumOnbellegi: (anahtar: ObjectIdentifier, belge: PdfiumBelge)?
    @ObservationIgnored private var satirOnbellegi: [Int: [DuzenlemeSatiri]] = [:]

    init(oturum: BelgeOturumu) {
        self.oturum = oturum
        katman.durum = self
    }

    // MARK: Etkileşim durumu

    var etkilesim: SayfaEtkilesimi {
        guard let oturum else { return .yok }
        switch oturum.kip {
        case .isaretle:
            if arac.kalemMi { return .kalem }
            if arac.sekil != nil { return .surukle }
            return arac == .sec ? .secim : .yok
        case .duzenle:
            return duzenleAraci == .ortu || duzenleAraci == .baglanti ? .surukle : .yok
        case .imzala:
            return .secim
        default:
            return .yok
        }
    }

    var suruklemeTuru: SuruklemeTuru {
        if let s = arac.sekil, oturum?.kip == .isaretle { return .sekil(s) }
        return .kutu
    }

    // MARK: Kip yaşam döngüsü

    func kipAcildi() {
        dokunusuKur()
        katman.yenile()
        kaydirmaAyarla()
    }

    func kipKapandi() {
        kalemiTamamla()
        secili = nil
        vurgu = nil
        alanlariVurgula = false
        yerlestirme = nil
        oturum?.dokunusIsleyici = nil
        katman.yenile()
        kaydirmaAyarla()
    }

    func belgeDegisti() {
        secili = nil
        vurgu = nil
        pdfiumOnbellegi = nil
        satirOnbellegi = [:]
        alanIndeksi = -1
        sayfaSurumu += 1
    }

    private func aracDegisti() {
        kalemiTamamla()
        ayarlar.varsayilanlar(arac)
        if etkilesim != .secim { secili = nil }
        vurgu = nil
        dokunusuKur()
        katman.yenile()
        kaydirmaAyarla()
    }

    /// Kaydetmeden önce: bekleyen kalem çizgilerini açıklamaya çevir.
    func kayitOncesi() {
        kalemiTamamla()
    }

    func kalemiTamamla() {
        katman.bekleyenleriIsle()
    }

    /// Kalem ya da sürükleyerek çizim açıkken sayfa kaydırma iki parmakla yapılır.
    func kaydirmaAyarla() {
        guard let v = oturum?.pdfView, let k = Self.kaydirici(v) else { return }
        let e = etkilesim
        k.panGestureRecognizer.minimumNumberOfTouches = (e == .surukle || (e == .kalem && !ayarlar.yalnizPencil)) ? 2 : 1
    }

    private static func kaydirici(_ v: UIView) -> UIScrollView? {
        if let s = v as? UIScrollView, !(s is PKCanvasView) { return s }
        for a in v.subviews { if let s = kaydirici(a) { return s } }
        return nil
    }

    // MARK: Dokunuş işleyicisi

    func dokunusuKur() {
        guard let oturum else { return }
        if let y = yerlestirme {
            oturum.dokunusIsleyici = { [weak self] sayfa, p in
                guard let self, let y = self.yerlestirme else { return }
                y.ekle(sayfa, p)
                if y.tekSefer { self.yerlestirme = nil }
            }
            _ = y
            return
        }
        switch oturum.kip {
        case .isaretle:
            switch arac {
            case .sec:
                oturum.dokunusIsleyici = { [weak self] s, p in self?.secimDokunusu(s, p) }
            case .silgi:
                oturum.dokunusIsleyici = { [weak self] s, p in self?.silgiDokunusu(s, p) }
            case .metinKutusu:
                oturum.dokunusIsleyici = { [weak self] s, p in self?.istek = .kutuEkle(s, p) }
            case .not:
                oturum.dokunusIsleyici = { [weak self] s, p in self?.istek = .notEkle(s, p) }
            case .damga:
                oturum.dokunusIsleyici = nil
            default:
                oturum.dokunusIsleyici = nil
            }
        case .duzenle:
            switch duzenleAraci {
            case .metniDuzenle:
                oturum.dokunusIsleyici = { [weak self] s, p in self?.metinDokunusu(s, p) }
            case .metinEkle:
                oturum.dokunusIsleyici = { [weak self] s, p in
                    guard let self, let b = self.oturum?.belge else { return }
                    self.istek = .pdfiumMetinEkle(b.index(for: s), p)
                }
            default:
                oturum.dokunusIsleyici = nil
            }
        case .imzala:
            oturum.dokunusIsleyici = { [weak self] s, p in self?.secimDokunusu(s, p) }
        default:
            oturum.dokunusIsleyici = nil
        }
    }

    // MARK: Seçim

    func seciliOlabilir(_ a: PDFAnnotation) -> Bool {
        AciklamaFabrikasi.duzenlenebilir(a) && a.type != "Link"
    }

    func aciklamaBul(_ sayfa: PDFPage, _ p: CGPoint) -> PDFAnnotation? {
        sayfa.annotations.reversed().first { seciliOlabilir($0) && isabet($0, p) }
    }

    private func isabet(_ a: PDFAnnotation, _ p: CGPoint) -> Bool {
        let t = a.type ?? ""
        if ["Highlight", "Underline", "StrikeOut"].contains(t), let q = a.quadrilateralPoints, q.count >= 4 {
            let noktalar = q.map(\.cgPointValue)
            for i in stride(from: 0, to: noktalar.count - 3, by: 4) {
                let grup = noktalar[i..<(i + 4)]
                let xs = grup.map(\.x), ys = grup.map(\.y)
                guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { continue }
                let r = CGRect(x: a.bounds.minX + x0, y: a.bounds.minY + y0, width: x1 - x0, height: y1 - y0).insetBy(dx: -3, dy: -3)
                if r.contains(p) { return true }
            }
            return false
        }
        return a.bounds.insetBy(dx: -6, dy: -6).contains(p)
    }

    func secimDokunusu(_ sayfa: PDFPage, _ p: CGPoint) {
        if let a = aciklamaBul(sayfa, p) {
            if a === secili, a.type == "FreeText" || a.type == "Text" {
                seciliyiDuzenle()
            } else {
                secili = a
            }
        } else {
            secili = nil
        }
    }

    func silgiDokunusu(_ sayfa: PDFPage, _ p: CGPoint) {
        guard let a = aciklamaBul(sayfa, p) else { return }
        if a === secili { secili = nil }
        oturum?.aciklamaSil(a)
    }

    func seciliyiDuzenle() {
        guard let a = secili else { return }
        switch a.type {
        case "FreeText": istek = .kutuDuzenle(a)
        case "Text": istek = .notDuzenle(a)
        default: break
        }
    }

    func seciliyiSil() {
        guard let a = secili else { return }
        secili = nil
        oturum?.aciklamaSil(a)
    }

    func seciliyiKopyala() {
        guard let a = secili, let sayfa = a.page, let k = AciklamaFabrikasi.kopyala(a) else { return }
        oturum?.aciklamaEkle(k, sayfa, ad: "Kopyala")
        secili = k
    }

    func seciliRengiDegistir(_ r: RGBA) {
        guard let a = secili else { return }
        ayarlar.renkSec(r)
        degisiklik("Renk", a) {
            if let d = a as? KagitDamgasi {
                var t = d.tanim
                t.renk = r.opaklikla(d.tanim.renk.a)
                d.tanim = t
            } else if a.type == "FreeText" {
                a.fontColor = r.platformRengi
            } else if ["Highlight"].contains(a.type) {
                a.color = r.opaklikla(ayarlar.opaklik).platformRengi
            } else {
                a.color = r.opaklikla(a.color.cgColor.alpha).platformRengi
            }
        }
    }

    /// Açıklamayı değiştirir ve değişikliği tek adımda geri alınabilir yapar.
    func degisiklik(_ ad: String, _ a: PDFAnnotation, _ degistir: () -> Void) {
        let once = AciklamaAni(a)
        degistir()
        let sonra = AciklamaAni(a)
        oturum?.degistir(ad, yap: { sonra.uygula(a) }, geriAl: { once.uygula(a) })
        yenileSayfa(a.page)
    }

    func yenileSayfa(_ s: PDFPage?) {
        if let s { oturum?.pdfView?.annotationsChanged(on: s) }
        katman.yenile()
    }

    // MARK: Taşıma / boyutlandırma (katmandan)

    func hareketBasladi(_ a: PDFAnnotation) { hareketAni = AciklamaAni(a) }

    func hareketSurdur(_ a: PDFAnnotation, yeni: CGRect) {
        guard let ani = hareketAni else { return }
        let eski = ani.bounds
        a.bounds = yeni
        let sx = eski.width > 0 ? yeni.width / eski.width : 1
        let sy = eski.height > 0 ? yeni.height / eski.height : 1
        if let yollar = ani.yollar, a.type == "Ink" {
            for p in a.paths ?? [] { a.remove(p) }
            for p in yollar {
                let k = p.copy() as! UIBezierPath
                k.apply(CGAffineTransform(scaleX: sx, y: sy))
                a.add(k)
            }
        }
        if a.type == "Line" {
            a.startPoint = CGPoint(x: ani.baslangic.x * sx, y: ani.baslangic.y * sy)
            a.endPoint = CGPoint(x: ani.bitis.x * sx, y: ani.bitis.y * sy)
        }
        if let s = a.page { oturum?.pdfView?.annotationsChanged(on: s) }
    }

    func hareketBitti(_ a: PDFAnnotation) {
        guard let once = hareketAni else { return }
        hareketAni = nil
        let sonra = AciklamaAni(a)
        guard once.bounds != sonra.bounds else { return }
        oturum?.degistir("Taşı", yap: { sonra.uygula(a) }, geriAl: { once.uygula(a) })
        yenileSayfa(a.page)
    }

    /// Yeniden boyutlandırma yalnız bu türlerde anlamlı (işaretlerde yalnız taşıma).
    func boyutlandirilabilir(_ a: PDFAnnotation) -> Bool {
        !["Highlight", "Underline", "StrikeOut", "Text"].contains(a.type ?? "")
    }

    func oraniKorur(_ a: PDFAnnotation) -> Bool {
        (a as? KagitDamgasi).map { $0.tanim.tur == .gorsel } ?? false
    }

    // MARK: Kalem

    func kalemCizgileri(_ sayfa: PDFPage, yollar: [[CGPoint]], fosforlu: Bool) {
        guard let oturum else { return }
        let renk = ayarlar.etkinRenk(fosforlu ? .fosforlu : .kalem)
        let kalinlik = CGFloat(ayarlar.kalinlik)
        let liste = yollar.compactMap {
            AciklamaFabrikasi.murekkep(yollar: [AciklamaFabrikasi.seyrelt($0)], renk: renk, kalinlik: kalinlik)
        }
        guard !liste.isEmpty else { return }
        oturum.degistir("Çiz", yap: { for a in liste { sayfa.addAnnotation(a) } },
                        geriAl: { for a in liste { sayfa.removeAnnotation(a) } })
    }

    // MARK: Metin işaretleri (seçimden)

    func secimDegisti() {
        guard let oturum, oturum.kip == .isaretle, let v = oturum.pdfView else { return }
        let var_ = !(v.currentSelection?.string ?? "").isEmpty
        if metinSecimiVar != var_ { metinSecimiVar = var_ }
        guard var_, let tur = arac.metinIsareti else { return }
        secimGorevi?.cancel()
        let ilk = v.currentSelection?.string
        secimGorevi = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self, self.oturum?.pdfView?.currentSelection?.string == ilk else { return }
            self.secimdenIsaretle(tur)
        }
    }

    func secimdenIsaretle(_ tur: AciklamaFabrikasi.MetinIsareti) {
        guard let oturum, let v = oturum.pdfView, let secim = v.currentSelection else { return }
        var sayfaKutulari: [(PDFPage, [CGRect])] = []
        for satir in secim.selectionsByLine() {
            for sayfa in satir.pages {
                let k = satir.bounds(for: sayfa)
                guard !k.isEmpty else { continue }
                if let i = sayfaKutulari.firstIndex(where: { $0.0 === sayfa }) { sayfaKutulari[i].1.append(k) }
                else { sayfaKutulari.append((sayfa, [k])) }
            }
        }
        let renk = ayarlar.etkinRenk(arac.metinIsareti == nil ? .vurgu : arac)
        let liste = sayfaKutulari.compactMap { sayfa, kutular -> (PDFPage, PDFAnnotation)? in
            AciklamaFabrikasi.metinIsareti(tur, satirlar: kutular, renk: renk).map { (sayfa, $0) }
        }
        guard !liste.isEmpty else { return }
        let ad = IsaretAraci.allCases.first { $0.metinIsareti == tur }?.ad ?? "İşaret"
        oturum.degistir(ad, yap: { for (s, a) in liste { s.addAnnotation(a) } },
                        geriAl: { for (s, a) in liste { s.removeAnnotation(a) } })
        v.clearSelection()
        metinSecimiVar = false
    }

    // MARK: Sürükleyerek çizim

    func surukleBitti(_ sayfa: PDFPage, a: CGPoint, b: CGPoint) {
        guard hypot(a.x - b.x, a.y - b.y) > 4, let oturum else { return }
        if oturum.kip == .duzenle {
            let kutu = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            switch duzenleAraci {
            case .ortu:
                let d = KagitDamgasi(bounds: kutu, tanim: DamgaTanimi(tur: .ortu, renk: .beyaz))
                oturum.aciklamaEkle(d, sayfa, ad: "Örtü")
                secili = d
            case .baglanti:
                istek = .baglanti(sayfa, kutu)
            default: break
            }
            return
        }
        guard let tur = arac.sekil else { return }
        let renk = ayarlar.etkinRenk(arac)
        let dolgu: RGBA? = ayarlar.dolgu ? renk.opaklikla(0.25) : nil
        let s = AciklamaFabrikasi.sekil(tur, a: a, b: b, renk: renk, kalinlik: CGFloat(ayarlar.kalinlik), dolgu: dolgu)
        oturum.aciklamaEkle(s, sayfa, ad: arac.ad)
    }

    // MARK: Metin kutusu / not

    func kutuEkle(_ sayfa: PDFPage, nokta: CGPoint, metin: String, punto: CGFloat, renk: RGBA, kalin: Bool, hiza: NSTextAlignment) {
        guard !metin.isEmpty, let oturum else { return }
        let boyut = AciklamaFabrikasi.metinKutusuBoyutu(metin, punto: punto)
        let kutu = sayfaIcine(CGRect(x: nokta.x, y: nokta.y - boyut.height, width: boyut.width, height: boyut.height), sayfa)
        let a = AciklamaFabrikasi.metinKutusu(kutu, metin: metin, punto: punto, renk: renk, kalin: kalin, hiza: hiza)
        oturum.aciklamaEkle(a, sayfa, ad: "Metin")
        secili = a
    }

    func kutuGuncelle(_ a: PDFAnnotation, metin: String, punto: CGFloat, renk: RGBA, kalin: Bool, hiza: NSTextAlignment) {
        degisiklik("Metin", a) {
            a.contents = metin
            a.font = kalin ? UIFont.boldSystemFont(ofSize: punto) : UIFont.systemFont(ofSize: punto)
            a.fontColor = renk.platformRengi
            a.alignment = hiza
            let boyut = AciklamaFabrikasi.metinKutusuBoyutu(metin, punto: punto, enGenislik: max(a.bounds.width, 120))
            a.bounds = CGRect(x: a.bounds.minX, y: a.bounds.maxY - boyut.height, width: max(a.bounds.width, boyut.width), height: boyut.height)
        }
    }

    func notEkle(_ sayfa: PDFPage, nokta: CGPoint, metin: String) {
        guard let oturum else { return }
        let a = AciklamaFabrikasi.not(nokta, metin: metin, renk: ayarlar.renk)
        oturum.aciklamaEkle(a, sayfa, ad: "Not")
    }

    func sayfaIcine(_ k: CGRect, _ sayfa: PDFPage) -> CGRect {
        let s = sayfa.bounds(for: .cropBox)
        var r = k
        r.origin.x = min(max(r.origin.x, s.minX), max(s.maxX - r.width, s.minX))
        r.origin.y = min(max(r.origin.y, s.minY), max(s.maxY - r.height, s.minY))
        return r
    }

    // MARK: Damga / imza / görsel

    func damgaYerlestirmeyiBaslat(_ t: DamgaTanimi, ad: String? = nil, tekSefer: Bool = true) {
        yerlestirme = Yerlestirme(ad: ad ?? (t.metin.isEmpty ? "Damga" : t.metin), tekSefer: tekSefer) { [weak self] s, p in
            self?.damgaEkle(t, sayfa: s, merkez: p)
        }
    }

    @discardableResult
    func damgaEkle(_ t: DamgaTanimi, sayfa: PDFPage, merkez p: CGPoint, boyut: CGSize? = nil) -> KagitDamgasi? {
        guard let oturum else { return nil }
        let b = boyut ?? t.varsayilanBoyut()
        let kutu = sayfaIcine(CGRect(x: p.x - b.width / 2, y: p.y - b.height / 2, width: b.width, height: b.height), sayfa)
        let d = KagitDamgasi(bounds: kutu, tanim: t)
        oturum.aciklamaEkle(d, sayfa, ad: t.tur == .gorsel ? "Görsel" : "Damga")
        secili = d
        return d
    }

    /// Görünür sayfanın ortası.
    func gorunenMerkez() -> (PDFPage, CGPoint)? {
        guard let v = oturum?.pdfView else { return nil }
        let orta = CGPoint(x: v.bounds.midX, y: v.bounds.midY)
        guard let s = v.page(for: orta, nearest: true) ?? v.currentPage else { return nil }
        return (s, v.convert(orta, to: s))
    }

    func gorselDamgasi(_ url: URL) -> DamgaTanimi? {
        let erisim = url.startAccessingSecurityScopedResource()
        defer { if erisim { url.stopAccessingSecurityScopedResource() } }
        guard let veri = try? Data(contentsOf: url), let g = PDFCizim.goruntuYukle(veri, enBuyukKenar: 1800) else { return nil }
        let alfa = g.alphaInfo != .none && g.alphaInfo != .noneSkipFirst && g.alphaInfo != .noneSkipLast
        guard let kod = PDFCizim.kodla(g, tur: alfa ? .png : .jpeg, kalite: 0.85) else { return nil }
        return DamgaTanimi(tur: .gorsel, metin: url.deletingPathExtension().lastPathComponent, gorselVeri: kod)
    }

    func gorselEkleOrtaya(_ url: URL) {
        guard let t = gorselDamgasi(url), let (s, p) = gorunenMerkez() else {
            oturum?.ileti = Ileti(baslik: "Görsel", metin: "Görsel eklenemedi.")
            return
        }
        damgaEkle(t, sayfa: s, merkez: p)
    }

    // MARK: PDFium işleri

    /// PDFium ile içerik düzenler: belgenin kopyası arka planda açılır, sonuç geri alınabilir şekilde konur.
    func pdfiumIsle(_ ad: String, _ islem: @escaping @Sendable (PdfiumBelge) throws -> Void) {
        guard let oturum, oturum.calisiyor == nil else { return }
        let veri: Data
        do { veri = try oturum.veriAl() } catch { oturum.ileti = Ileti(error); return }
        let parola = oturum.parola
        oturum.calisiyor = "\(ad)…"
        Task {
            defer { oturum.calisiyor = nil }
            do {
                let yeni = try await Task.detached(priority: .userInitiated) { () throws -> Data in
                    let b = try PdfiumBelge(veri: veri, parola: parola)
                    try islem(b)
                    return try b.kaydet()
                }.value
                try oturum.belgeyiDegistir(yeni, ad: ad)
            } catch {
                oturum.ileti = Ileti(error)
            }
        }
    }

    private func pdfiumBelgesi() async throws -> PdfiumBelge {
        guard let oturum, let belge = oturum.belge else { throw KagitHata.bosGirdi }
        let anahtar = ObjectIdentifier(belge)
        if let o = pdfiumOnbellegi, o.anahtar == anahtar { return o.belge }
        let veri = try oturum.veriAl()
        let parola = oturum.parola
        let b = try await Task.detached { try PdfiumBelge(veri: veri, parola: parola) }.value
        pdfiumOnbellegi = (anahtar, b)
        return b
    }

    func satirlariAl(_ sayfa: Int) async throws -> [DuzenlemeSatiri] {
        if let s = satirOnbellegi[sayfa] { return s }
        let b = try await pdfiumBelgesi()
        let satirlar = try await Task.detached { MetinGruplayici.satirlar(try b.metinNesneleri(sayfa: sayfa)) }.value
        satirOnbellegi[sayfa] = satirlar
        return satirlar
    }

    func metinDokunusu(_ sayfa: PDFPage, _ p: CGPoint) {
        guard let oturum, let belge = oturum.belge else { return }
        let i = belge.index(for: sayfa)
        Task {
            do {
                let satirlar = try await satirlariAl(i)
                if let s = MetinGruplayici.satir(satirlar, noktasinda: p) {
                    vurgu = (sayfa, s.kutu)
                    istek = .pdfiumSatir(i, s)
                } else {
                    vurgu = nil
                    oturum.ileti = Ileti(baslik: "Metin bulunamadı",
                                         metin: satirlar.isEmpty
                                            ? "Bu sayfada düzenlenebilir metin yok. Taranmış sayfalarda önce OCR uygulayın."
                                            : "Bu noktada metin yok. Bir metin satırına dokunun.", hata: false)
                }
            } catch {
                oturum.ileti = Ileti(error)
            }
        }
    }

    func satiriDegistir(sayfa: Int, satir: DuzenlemeSatiri, metin: String, punto: CGFloat, yaziTipi: GomuluYaziTipi, renk: RGBA) {
        vurgu = nil
        pdfiumIsle("Metin düzenle") { b in
            try b.satiriDegistir(sayfa: sayfa, satir: satir, yeniMetin: metin, punto: punto, yaziTipi: yaziTipi, renk: renk)
        }
    }

    func pdfiumMetinEkle(sayfa: Int, taban: CGPoint, metin: String, punto: CGFloat, yaziTipi: GomuluYaziTipi, renk: RGBA) {
        pdfiumIsle("Metin ekle") { b in
            try b.metinEkle(sayfa: sayfa, metin: metin, taban: taban, punto: punto, yaziTipi: yaziTipi, renk: renk)
        }
    }

    /// Görseli PDF içeriğine yerleştirir (dokunulan noktaya ortalı).
    func pdfiumGorselEkle(_ url: URL, sayfa: PDFPage, merkez: CGPoint) {
        guard let belge = oturum?.belge else { return }
        let i = belge.index(for: sayfa)
        let erisim = url.startAccessingSecurityScopedResource()
        defer { if erisim { url.stopAccessingSecurityScopedResource() } }
        guard let veri = try? Data(contentsOf: url), let g = PDFCizim.goruntuYukle(veri, enBuyukKenar: 2400) else {
            oturum?.ileti = Ileti(baslik: "Görsel", metin: "Görsel okunamadı.")
            return
        }
        let sayfaKutusu = sayfa.bounds(for: .cropBox)
        let genislik = min(sayfaKutusu.width * 0.4, CGFloat(g.width))
        let yukseklik = genislik * CGFloat(g.height) / CGFloat(max(g.width, 1))
        let kutu = sayfaIcine(CGRect(x: merkez.x - genislik / 2, y: merkez.y - yukseklik / 2, width: genislik, height: yukseklik), sayfa)
        let resim = g
        pdfiumIsle("Görsel ekle") { b in try b.gorselEkle(sayfa: i, goruntu: resim, kutu: kutu) }
    }

    // MARK: Bağlantı

    func baglantiEkle(_ sayfa: PDFPage, kutu: CGRect, url: URL?, hedefSayfa: Int?) {
        guard let oturum, let belge = oturum.belge else { return }
        let a: PDFAnnotation
        if let url {
            a = AciklamaFabrikasi.baglanti(kutu: kutu, url: url)
        } else if let n = hedefSayfa, let hedef = belge.page(at: n - 1) {
            a = AciklamaFabrikasi.baglanti(kutu: kutu, hedef: hedef)
        } else {
            oturum.ileti = Ileti(baslik: "Bağlantı", metin: "Geçerli bir adres ya da sayfa numarası girin.")
            return
        }
        oturum.aciklamaEkle(a, sayfa, ad: "Bağlantı")
    }

    // MARK: Form alanları

    func formAlanlari() -> [(sayfa: PDFPage, alan: PDFAnnotation)] {
        guard let belge = oturum?.belge else { return [] }
        var sonuc: [(PDFPage, PDFAnnotation)] = []
        for i in 0..<belge.pageCount {
            guard let s = belge.page(at: i) else { continue }
            let alanlar = s.annotations.filter { $0.type == "Widget" }
                .sorted { $0.bounds.maxY != $1.bounds.maxY ? $0.bounds.maxY > $1.bounds.maxY : $0.bounds.minX < $1.bounds.minX }
            sonuc.append(contentsOf: alanlar.map { (s, $0) })
        }
        return sonuc
    }

    func sonrakiAlan(geri: Bool = false) {
        let alanlar = formAlanlari()
        guard !alanlar.isEmpty else {
            oturum?.ileti = Ileti(baslik: "Form", metin: "Bu belgede form alanı yok. Alan eklemek için \"Alan ekle\" menüsünü kullanın.", hata: false)
            return
        }
        alanIndeksi = geri ? (alanIndeksi - 1 + alanlar.count) % alanlar.count : (alanIndeksi + 1) % alanlar.count
        let (s, a) = alanlar[alanIndeksi]
        oturum?.pdfView?.go(to: a.bounds.insetBy(dx: -60, dy: -60), on: s)
        vurgu = (s, a.bounds)
    }

    enum AlanTuru: String, CaseIterable, Identifiable {
        case metin, onay, liste
        var id: String { rawValue }
        var ad: String { switch self { case .metin: "Metin alanı"; case .onay: "Onay kutusu"; case .liste: "Açılır liste" } }
        var simge: String { switch self { case .metin: "character.textbox"; case .onay: "checkmark.square"; case .liste: "list.bullet.rectangle" } }
    }

    func alanYerlestirmeyiBaslat(_ tur: AlanTuru, secenekler: [String] = []) {
        yerlestirme = Yerlestirme(ad: tur.ad, tekSefer: true) { [weak self] s, p in
            self?.alanOlustur(tur, sayfa: s, nokta: p, secenekler: secenekler)
        }
    }

    func alanOlustur(_ tur: AlanTuru, sayfa: PDFPage, nokta p: CGPoint, secenekler: [String]) {
        guard let oturum else { return }
        let boyut = tur == .onay ? CGSize(width: 18, height: 18) : CGSize(width: 160, height: 24)
        let kutu = sayfaIcine(CGRect(x: p.x - boyut.width / 2, y: p.y - boyut.height / 2, width: boyut.width, height: boyut.height), sayfa)
        let w = PDFAnnotation(bounds: kutu, forType: .widget, withProperties: nil)
        switch tur {
        case .metin:
            w.widgetFieldType = .text
        case .onay:
            w.widgetFieldType = .button
            w.widgetControlType = .checkBoxControl
            w.buttonWidgetState = .offState
        case .liste:
            w.widgetFieldType = .choice
            w.isListChoice = false
            w.choices = secenekler.isEmpty ? ["Seçenek 1", "Seçenek 2"] : secenekler
        }
        let mevcut = formAlanlari().count + 1
        w.fieldName = "alan\(mevcut)-\(UUID().uuidString.prefix(4))"
        w.font = UIFont.systemFont(ofSize: 12)
        w.fontColor = .black
        w.color = .darkGray
        let kenar = PDFBorder()
        kenar.lineWidth = 0.8
        w.border = kenar
        oturum.aciklamaEkle(w, sayfa, ad: "Form alanı")
    }

    // MARK: Yardımcılar

    func ileti(_ metin: String, baslik: String = "Bilgi") {
        oturum?.ileti = Ileti(baslik: baslik, metin: metin, hata: false)
    }
}
