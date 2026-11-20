import KagitKit
import PDFKit
import PencilKit
import UIKit

/// `PDFView.pageOverlayViewProvider`: her görünen sayfaya bir katman (kalem tuvali, sürükleyerek çizim,
/// seçili açıklamanın tutamaçları, vurgular) ekler. Katman yalnız gerektiğinde dokunuşları yakalar.
final class SayfaKatmani: NSObject, PDFPageOverlayViewProvider {
    weak var durum: DuzenleyiciDurumu?
    private let gorunumler = NSHashTable<SayfaKatmaniGorunumu>.weakObjects()

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(secimDegisti), name: .PDFViewSelectionChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(olcekDegisti), name: .PDFViewScaleChanged, object: nil)
    }

    @objc private func secimDegisti(_ n: Notification) {
        guard let v = n.object as? PDFView, v === durum?.oturum?.pdfView else { return }
        durum?.secimDegisti()
    }

    @objc private func olcekDegisti(_ n: Notification) {
        guard let v = n.object as? PDFView, v === durum?.oturum?.pdfView else { return }
        yenile()
    }

    func yenile() {
        for g in gorunumler.allObjects { g.guncelle() }
    }

    func bekleyenleriIsle() {
        for g in gorunumler.allObjects { g.kalemiIsle() }
    }

    // MARK: PDFPageOverlayViewProvider

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        let g = SayfaKatmaniGorunumu(sayfa: page, durum: durum)
        gorunumler.add(g)
        return g
    }

    func pdfView(_ pdfView: PDFView, willDisplayOverlayView overlayView: UIView, for page: PDFPage) {
        (overlayView as? SayfaKatmaniGorunumu)?.guncelle()
    }

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        (overlayView as? SayfaKatmaniGorunumu)?.kalemiIsle()
    }
}

/// Tek sayfanın katmanı. Koordinatlar: katman sol üst köşeli ve sayfa kutusu boyutunda; PDF sayfa uzayına
/// `sayfaNoktasi` / `katmanNoktasi` ile çevrilir.
final class SayfaKatmaniGorunumu: UIView, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
    let sayfa: PDFPage
    weak var durum: DuzenleyiciDurumu?
    private let kutu: CGRect
    private var kanvas: PKCanvasView?
    private let pan = UIPanGestureRecognizer()
    private let ciftDokunus = UITapGestureRecognizer()
    private let onizleme = CAShapeLayer()
    private var kalemGorevi: Task<Void, Never>?

    private enum Tutamac { case govde, solUst, sagUst, solAlt, sagAlt }
    private var tutamac: Tutamac?
    private var baslangicKutusu: CGRect = .zero
    private var baslangicNoktasi: CGPoint = .zero
    private var surukleBaslangici: CGPoint?

    init(sayfa: PDFPage, durum: DuzenleyiciDurumu?) {
        self.sayfa = sayfa
        self.durum = durum
        self.kutu = sayfa.bounds(for: .cropBox)
        super.init(frame: CGRect(origin: .zero, size: kutu.size))
        backgroundColor = .clear
        isOpaque = false
        overrideUserInterfaceStyle = .light

        onizleme.fillColor = UIColor.systemBlue.withAlphaComponent(0.12).cgColor
        onizleme.strokeColor = UIColor.systemBlue.cgColor
        onizleme.lineWidth = 1.5
        onizleme.lineDashPattern = [6, 4]
        layer.addSublayer(onizleme)

        pan.addTarget(self, action: #selector(suruklendi(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        addGestureRecognizer(pan)

        ciftDokunus.numberOfTapsRequired = 2
        ciftDokunus.addTarget(self, action: #selector(ciftDokunuldu))
        ciftDokunus.delegate = self
        addGestureRecognizer(ciftDokunus)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmaz") }

    // MARK: Koordinatlar

    private func sayfaNoktasi(_ p: CGPoint) -> CGPoint {
        CGPoint(x: kutu.minX + p.x, y: kutu.maxY - p.y)
    }

    private func katmanKutusu(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX - kutu.minX, y: kutu.maxY - r.maxY, width: r.width, height: r.height)
    }

    private var olcek: CGFloat { max(durum?.oturum?.pdfView?.scaleFactor ?? 1, 0.1) }

    private var seciliBuSayfada: PDFAnnotation? {
        guard let a = durum?.secili, a.page === sayfa else { return nil }
        return a
    }

    // MARK: Durum

    func guncelle() {
        guard let durum else { return }
        switch durum.etkilesim {
        case .kalem: kanvasKur()
        default:
            if kanvas != nil { kalemiIsle(); kanvasKaldir() }
        }
        pan.isEnabled = durum.etkilesim == .surukle || (durum.etkilesim == .secim && seciliBuSayfada != nil)
        ciftDokunus.isEnabled = durum.etkilesim == .secim && seciliBuSayfada != nil
        if durum.etkilesim != .surukle { onizleme.path = nil }
        setNeedsDisplay()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { guncelle() }
    }

    // MARK: Dokunuş yakalama

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point), let durum else { return nil }
        switch durum.etkilesim {
        case .yok: return nil
        case .kalem: return super.hitTest(point, with: event)
        case .surukle: return self
        case .secim:
            guard let a = seciliBuSayfada else { return nil }
            let k = katmanKutusu(a.bounds).insetBy(dx: -22 / olcek, dy: -22 / olcek)
            return k.contains(point) ? self : nil
        }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool {
        false
    }

    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let durum else { return false }
        if g === pan, durum.etkilesim == .secim {
            return tutamacBul(pan.location(in: self)) != nil
        }
        return true
    }

    // MARK: Çizim

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let durum else { return }
        let o = olcek

        if durum.alanlariVurgula {
            for a in sayfa.annotations where a.type == "Widget" {
                let k = katmanKutusu(a.bounds)
                ctx.setFillColor(UIColor.systemBlue.withAlphaComponent(0.16).cgColor)
                ctx.fill(k)
                ctx.setStrokeColor(UIColor.systemBlue.cgColor)
                ctx.setLineWidth(1 / o)
                ctx.stroke(k)
            }
        }
        if let v = durum.vurgu, v.sayfa === sayfa {
            let k = katmanKutusu(v.kutu).insetBy(dx: -2, dy: -2)
            ctx.setFillColor(UIColor.systemYellow.withAlphaComponent(0.3).cgColor)
            ctx.fill(k)
            ctx.setStrokeColor(UIColor.systemOrange.cgColor)
            ctx.setLineWidth(1.5 / o)
            ctx.stroke(k)
        }
        if let a = seciliBuSayfada {
            let k = katmanKutusu(a.bounds)
            ctx.setStrokeColor(UIColor.systemBlue.cgColor)
            ctx.setLineWidth(1.5 / o)
            ctx.setLineDash(phase: 0, lengths: [5 / o, 3 / o])
            ctx.stroke(k)
            ctx.setLineDash(phase: 0, lengths: [])
            if durum.boyutlandirilabilir(a) {
                for p in koseler(k) {
                    let r = CGRect(x: p.x - 6 / o, y: p.y - 6 / o, width: 12 / o, height: 12 / o)
                    ctx.setFillColor(UIColor.white.cgColor)
                    ctx.fillEllipse(in: r)
                    ctx.setStrokeColor(UIColor.systemBlue.cgColor)
                    ctx.setLineWidth(2 / o)
                    ctx.strokeEllipse(in: r)
                }
            }
        }
    }

    private func koseler(_ k: CGRect) -> [CGPoint] {
        [CGPoint(x: k.minX, y: k.minY), CGPoint(x: k.maxX, y: k.minY), CGPoint(x: k.minX, y: k.maxY), CGPoint(x: k.maxX, y: k.maxY)]
    }

    // MARK: Seçim hareketleri

    private func tutamacBul(_ p: CGPoint) -> Tutamac? {
        guard let a = seciliBuSayfada, let durum else { return nil }
        let k = katmanKutusu(a.bounds)
        if durum.boyutlandirilabilir(a) {
            let yaricap = 24 / olcek
            let ad: [Tutamac] = [.solUst, .sagUst, .solAlt, .sagAlt]
            for (t, c) in zip(ad, koseler(k)) where hypot(p.x - c.x, p.y - c.y) <= yaricap { return t }
        }
        return k.insetBy(dx: -10 / olcek, dy: -10 / olcek).contains(p) ? .govde : nil
    }

    @objc private func suruklendi(_ g: UIPanGestureRecognizer) {
        guard let durum else { return }
        let p = g.location(in: self)
        switch durum.etkilesim {
        case .surukle: surukleCizim(g, p, durum)
        case .secim: secimSurukle(g, p, durum)
        default: break
        }
    }

    private func surukleCizim(_ g: UIPanGestureRecognizer, _ p: CGPoint, _ durum: DuzenleyiciDurumu) {
        switch g.state {
        case .began:
            surukleBaslangici = g.location(in: self).applying(.identity)
            // began konumu parmağın ilk hareketten sonraki yeri; başlangıcı çeviriden geri hesapla
            let t = g.translation(in: self)
            surukleBaslangici = CGPoint(x: p.x - t.x, y: p.y - t.y)
            onizleCiz(p)
        case .changed:
            onizleCiz(p)
        case .ended:
            if let b = surukleBaslangici { durum.surukleBitti(sayfa, a: sayfaNoktasi(b), b: sayfaNoktasi(p)) }
            surukleBaslangici = nil
            onizleme.path = nil
        default:
            surukleBaslangici = nil
            onizleme.path = nil
        }
    }

    private func onizleCiz(_ p: CGPoint) {
        guard let b = surukleBaslangici, let durum else { return }
        let r = CGRect(x: min(b.x, p.x), y: min(b.y, p.y), width: abs(b.x - p.x), height: abs(b.y - p.y))
        let yol = UIBezierPath()
        switch durum.suruklemeTuru {
        case .kutu, .sekil(.dikdortgen): yol.append(UIBezierPath(rect: r))
        case .sekil(.daire): yol.append(UIBezierPath(ovalIn: r))
        case .sekil(.cizgi), .sekil(.ok):
            yol.move(to: b)
            yol.addLine(to: p)
        }
        onizleme.lineWidth = 1.5 / olcek
        onizleme.lineDashPattern = [6 / olcek as NSNumber, 4 / olcek as NSNumber]
        onizleme.path = yol.cgPath
    }

    private func secimSurukle(_ g: UIPanGestureRecognizer, _ p: CGPoint, _ durum: DuzenleyiciDurumu) {
        guard let a = seciliBuSayfada else { return }
        switch g.state {
        case .began:
            let t = g.translation(in: self)
            let baslangic = CGPoint(x: p.x - t.x, y: p.y - t.y)
            tutamac = tutamacBul(baslangic)
            baslangicKutusu = a.bounds
            baslangicNoktasi = baslangic
            durum.hareketBasladi(a)
        case .changed:
            guard let tutamac else { return }
            let dx = p.x - baslangicNoktasi.x
            let dy = -(p.y - baslangicNoktasi.y)      // sayfa uzayında y yukarı
            durum.hareketSurdur(a, yeni: yeniKutu(tutamac, dx: dx, dy: dy, a: a, durum: durum))
            setNeedsDisplay()
        case .ended, .cancelled, .failed:
            durum.hareketBitti(a)
            tutamac = nil
            setNeedsDisplay()
        default: break
        }
    }

    private func yeniKutu(_ t: Tutamac, dx: CGFloat, dy: CGFloat, a: PDFAnnotation, durum: DuzenleyiciDurumu) -> CGRect {
        var r = baslangicKutusu
        let en: CGFloat = 12
        switch t {
        case .govde:
            r.origin.x += dx
            r.origin.y += dy
            let s = kutu
            r.origin.x = min(max(r.origin.x, s.minX - r.width + 20), s.maxX - 20)
            r.origin.y = min(max(r.origin.y, s.minY - r.height + 20), s.maxY - 20)
            return r
        case .solUst:
            r = CGRect(x: r.minX + dx, y: r.minY, width: r.width - dx, height: r.height + dy)
        case .sagUst:
            r = CGRect(x: r.minX, y: r.minY, width: r.width + dx, height: r.height + dy)
        case .solAlt:
            r = CGRect(x: r.minX + dx, y: r.minY + dy, width: r.width - dx, height: r.height - dy)
        case .sagAlt:
            r = CGRect(x: r.minX, y: r.minY + dy, width: r.width + dx, height: r.height - dy)
        }
        if durum.oraniKorur(a), baslangicKutusu.height > 0 {
            let oran = baslangicKutusu.width / baslangicKutusu.height
            let genislik = max(r.width, en)
            let yukseklik = genislik / oran
            switch t {
            case .solUst: r = CGRect(x: baslangicKutusu.maxX - genislik, y: baslangicKutusu.minY, width: genislik, height: yukseklik)
            case .sagUst: r = CGRect(x: baslangicKutusu.minX, y: baslangicKutusu.minY, width: genislik, height: yukseklik)
            case .solAlt: r = CGRect(x: baslangicKutusu.maxX - genislik, y: baslangicKutusu.maxY - yukseklik, width: genislik, height: yukseklik)
            default: r = CGRect(x: baslangicKutusu.minX, y: baslangicKutusu.maxY - yukseklik, width: genislik, height: yukseklik)
            }
        }
        if r.width < en { r.size.width = en }
        if r.height < en { r.size.height = en }
        return r
    }

    @objc private func ciftDokunuldu() {
        guard let a = seciliBuSayfada, a.type == "FreeText" || a.type == "Text" else { return }
        durum?.seciliyiDuzenle()
    }

    // MARK: Kalem (PencilKit)

    private func kanvasKur() {
        guard let durum else { return }
        let k: PKCanvasView
        if let kanvas { k = kanvas } else {
            k = PKCanvasView(frame: bounds)
            k.backgroundColor = .clear
            k.isOpaque = false
            k.isScrollEnabled = false
            k.overrideUserInterfaceStyle = .light
            k.delegate = self
            k.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            insertSubview(k, at: 0)
            kanvas = k
        }
        k.drawingPolicy = durum.ayarlar.yalnizPencil ? .pencilOnly : .anyInput
        let fosforlu = durum.arac == .fosforlu
        let renk = durum.ayarlar.renk
        k.tool = PKInkingTool(fosforlu ? .marker : .pen, color: renk.platformRengi.withAlphaComponent(1),
                              width: CGFloat(durum.ayarlar.kalinlik))
    }

    private func kanvasKaldir() {
        kanvas?.removeFromSuperview()
        kanvas = nil
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !canvasView.drawing.strokes.isEmpty else { return }
        kalemGorevi?.cancel()
        kalemGorevi = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.kalemiIsle()
        }
    }

    /// Tuvaldaki çizgileri vektör mürekkep açıklamalarına çevirir.
    func kalemiIsle() {
        kalemGorevi?.cancel()
        guard let kanvas, let durum, !kanvas.drawing.strokes.isEmpty else { return }
        let yollar: [[CGPoint]] = kanvas.drawing.strokes.map { s in
            s.path.interpolatedPoints(by: .distance(3)).map { sayfaNoktasi($0.location.applying(s.transform)) }
        }
        kanvas.drawing = PKDrawing()
        durum.kalemCizgileri(sayfa, yollar: yollar, fosforlu: durum.arac == .fosforlu)
    }
}
