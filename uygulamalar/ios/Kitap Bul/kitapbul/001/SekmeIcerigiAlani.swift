import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Telefonda sekme çubuğuyla örtüşen görünüm alanını sınırlar.
/// iPad ve diğer platformlarda mevcut yerleşim korunur.
private struct SekmeIcerigiAlani: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var bottomOverlap: CGFloat = 0

    /// Kenardan sekme kaydırma her sekme içeriğine tek yerden eklenir; ekranlar ayrıca eklemez.
    func body(content: Content) -> some View {
        alan(content).kenardanSekmeKaydir()
    }

    @ViewBuilder
    private func alan(_ content: Content) -> some View {
#if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone && sizeClass == .compact {
            GeometryReader { geometry in
                content
                    .frame(width: geometry.size.width,
                           height: max(0, geometry.size.height - bottomOverlap), alignment: .top)
                    .clipped()
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .background {
                SekmeCubuguOlcumu { overlap in
                    guard abs(overlap - bottomOverlap) > 0.5 else { return }
                    bottomOverlap = overlap
                }
            }
            .background(Color(.systemGroupedBackground))
        } else {
            content
        }
#else
        content
#endif
    }
}

extension View {
    func sekmeninOkunurIcerikAlani() -> some View { modifier(SekmeIcerigiAlani()) }
}

#if os(iOS)
/// Public UIKit ilişkileriyle çubuğun konumunu küçültülmeyen dış alanda okur.
private struct SekmeCubuguOlcumu: UIViewRepresentable {
    let onOverlap: (CGFloat) -> Void

    func makeUIView(context: Context) -> OlcumGorunumu {
        let view = OlcumGorunumu()
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.onOverlap = onOverlap
        return view
    }

    func updateUIView(_ uiView: OlcumGorunumu, context: Context) {
        uiView.onOverlap = onOverlap
        uiView.requestMeasurement()
    }

    final class OlcumGorunumu: UIView {
        var onOverlap: ((CGFloat) -> Void)?
        private var measurementPending = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            requestMeasurement()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            requestMeasurement()
        }

        func requestMeasurement() {
            guard !measurementPending else { return }
            measurementPending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.measurementPending = false
                self.measureTabBar()
            }
        }

        private func measureTabBar() {
            guard window != nil, bounds.height > 0 else { return }
            var responder: UIResponder? = self
            var tabController: UITabBarController?
            while let current = responder {
                if let controller = current as? UIViewController,
                   let found = controller as? UITabBarController ?? controller.tabBarController {
                    tabController = found
                    break
                }
                responder = current.next
            }
            guard let bar = tabController?.tabBar, !bar.isHidden, bar.alpha > 0,
                  bar.window === window else {
                onOverlap?(0)
                return
            }
            onOverlap?(SekmeCubuguPayi.ayrilacak(alan: bounds, cubuk: bar.convert(bar.bounds, to: self)))
        }
    }
}
#endif

/// Sekme içeriğinin altında sekme çubuğu için ayrılacak yükseklik.
enum SekmeCubuguPayi {
    /// Çubuk alanın alt kenarına tam bitişikken `CGRect.intersects` false döner; eski hesap bu
    /// durumda hiç yer ayırmıyordu ve kaydırma alanı çubuğun arkasına uzanıyordu. Çubuk alana
    /// değiyor ya da onu kesiyorsa örtüşmenin üstüne 8 pt pay bırakılır.
    static func ayrilacak(alan bounds: CGRect, cubuk frame: CGRect) -> CGFloat {
        let overlap = max(0, bounds.maxY - frame.minY)
        let degiyor = frame.minY <= bounds.maxY + 0.5 && frame.maxY > bounds.minY
        return degiyor ? min(bounds.height, overlap + 8) : 0
    }
}
