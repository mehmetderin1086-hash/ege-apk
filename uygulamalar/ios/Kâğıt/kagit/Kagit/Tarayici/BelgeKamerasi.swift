import SwiftUI
import VisionKit

/// VisionKit belge kamerası. Tarama bitince sayfa görüntülerini verir.
struct BelgeKamerasi: UIViewControllerRepresentable {
    /// nil: kullanıcı vazgeçti ya da hata oldu.
    let bitti: ([CGImage]?) -> Void

    static var desteklenir: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let k = VNDocumentCameraViewController()
        k.delegate = context.coordinator
        return k
    }

    func updateUIViewController(_ k: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Koordinator { Koordinator(bitti: bitti) }

    final class Koordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let bitti: ([CGImage]?) -> Void
        init(bitti: @escaping ([CGImage]?) -> Void) { self.bitti = bitti }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            var sonuc: [CGImage] = []
            for i in 0..<scan.pageCount {
                if let g = scan.imageOfPage(at: i).cgImage { sonuc.append(g) }
            }
            bitti(sonuc)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            bitti(nil)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            bitti(nil)
        }
    }
}
