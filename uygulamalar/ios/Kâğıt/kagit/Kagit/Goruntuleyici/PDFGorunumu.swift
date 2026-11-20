import PDFKit
import SwiftUI
import UIKit

/// PDFKit `PDFView` sarmalayıcısı. Oturuma bağlanır; dokunuş işleyicisi tanımlıysa
/// dokunuşları sayfa koordinatına çevirip ona iletir.
struct PDFGorunumu: UIViewRepresentable {
    let oturum: BelgeOturumu
    var baslangicSayfasi: Int?

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = oturum.gorunumKipi
        v.displayDirection = oturum.yatayKaydirma ? .horizontal : .vertical
        v.displaysPageBreaks = true
        v.pageShadowsEnabled = true
        v.backgroundColor = .secondarySystemBackground
        v.isFindInteractionEnabled = true
        v.pageOverlayViewProvider = oturum.duzenleyici.katman
        v.document = oturum.belge
        oturum.pdfView = v
        if let s = baslangicSayfasi, let sayfa = oturum.belge?.page(at: s) { v.go(to: sayfa) }

        let dokunus = UITapGestureRecognizer(target: context.coordinator, action: #selector(Koordinator.dokunuldu(_:)))
        dokunus.delegate = context.coordinator
        v.addGestureRecognizer(dokunus)
        context.coordinator.dokunus = dokunus

        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Koordinator.sayfaDegisti(_:)),
                                               name: .PDFViewPageChanged, object: v)
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {
        if v.document !== oturum.belge { v.document = oturum.belge }
        if v.displayMode != oturum.gorunumKipi { v.displayMode = oturum.gorunumKipi; v.autoScales = true }
        let yon: PDFDisplayDirection = oturum.yatayKaydirma ? .horizontal : .vertical
        if v.displayDirection != yon { v.displayDirection = yon; v.autoScales = true }
        context.coordinator.dokunus?.isEnabled = oturum.dokunusEtkin
    }

    func makeCoordinator() -> Koordinator { Koordinator(oturum: oturum) }

    final class Koordinator: NSObject, UIGestureRecognizerDelegate {
        let oturum: BelgeOturumu
        weak var dokunus: UITapGestureRecognizer?

        init(oturum: BelgeOturumu) { self.oturum = oturum }

        @objc func dokunuldu(_ g: UITapGestureRecognizer) {
            guard let v = g.view as? PDFView, let isleyici = oturum.dokunusIsleyici else { return }
            let nokta = g.location(in: v)
            guard let sayfa = v.page(for: nokta, nearest: true) else { return }
            isleyici(sayfa, v.convert(nokta, to: sayfa))
        }

        @objc func sayfaDegisti(_ n: Notification) {
            guard let v = n.object as? PDFView, let s = v.currentPage, let b = v.document else { return }
            let i = b.index(for: s)
            if oturum.seciliSayfa != i { oturum.seciliSayfa = i }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
