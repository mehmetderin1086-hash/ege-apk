import ImageIO
import KagitKit
import PDFKit
import QuickLook
import SwiftUI
import UIKit

/// Belge küçük resimleri: bellek önbelleği + arka planda üretim.
enum KucukResim {
    nonisolated(unsafe) private static let onbellek: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 300
        return c
    }()

    static func anahtar(_ url: URL, _ tarih: Date, _ boyut: CGFloat) -> NSString {
        "\(url.path)|\(tarih.timeIntervalSince1970)|\(Int(boyut))" as NSString
    }

    static func hazir(_ url: URL, _ tarih: Date, _ boyut: CGFloat) -> UIImage? {
        onbellek.object(forKey: anahtar(url, tarih, boyut))
    }

    static func uret(_ url: URL, tarih: Date, boyut: CGFloat, sayfa: Int = 0) async -> UIImage? {
        let k = anahtar(url, tarih, boyut) as String + "|\(sayfa)"
        if let r = onbellek.object(forKey: k as NSString) { return r }
        let olcek = await MainActor.run { UITraitCollection.current.displayScale }
        let resim: UIImage? = await Task.detached(priority: .utility) {
            let piksel = boyut * max(olcek, 2)
            let uzanti = url.pathExtension.lowercased()
            if uzanti == "pdf" {
                guard let belge = PDFDocument(url: url), !belge.isLocked, let s = belge.page(at: min(sayfa, max(belge.pageCount - 1, 0))) else { return nil }
                return s.thumbnail(of: CGSize(width: piksel, height: piksel * 1.414), for: .cropBox)
            }
            if let kaynak = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cg = CGImageSourceCreateThumbnailAtIndex(kaynak, 0, [
                   kCGImageSourceCreateThumbnailFromImageAlways: true,
                   kCGImageSourceCreateThumbnailWithTransform: true,
                   kCGImageSourceThumbnailMaxPixelSize: piksel,
               ] as CFDictionary) {
                return UIImage(cgImage: cg)
            }
            return nil
        }.value
        if let resim { onbellek.setObject(resim, forKey: k as NSString) }
        return resim
    }

    /// PDF olmayan belge türleri için simge.
    static func simge(_ uzanti: String) -> String {
        switch uzanti {
        case "doc", "docx", "rtf", "odt", "pages": "doc.richtext"
        case "xls", "xlsx", "csv", "numbers", "ods": "tablecells"
        case "ppt", "pptx", "key", "odp": "rectangle.on.rectangle"
        case "txt", "md", "markdown": "doc.plaintext"
        case "html", "htm": "globe"
        case "epub": "book"
        case "zip": "doc.zipper"
        default: "doc"
        }
    }
}

/// Kitaplık ögesinin küçük resmi (PDF ilk sayfası, görsel ya da tür simgesi).
struct KucukResimGorunumu: View {
    let oge: KitaplikOgesi
    var boyut: CGFloat = 56
    @State private var resim: UIImage?

    var body: some View {
        ZStack {
            if oge.klasorMu {
                Image(systemName: "folder.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(.blue.gradient)
                    .padding(boyut * 0.12)
            } else if let resim {
                Image(uiImage: resim)
                    .resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.secondarySystemBackground))
                    .overlay {
                        Image(systemName: oge.pdfMi ? "doc.text" : KucukResim.simge(oge.uzanti))
                            .font(.system(size: boyut * 0.32))
                            .foregroundStyle(.secondary)
                    }
                    .aspectRatio(0.72, contentMode: .fit)
            }
        }
        .frame(width: boyut, height: boyut * 1.3)
        .task(id: "\(oge.yol)\(oge.degistirilme.timeIntervalSince1970)") {
            guard !oge.klasorMu, oge.pdfMi || oge.gorselMi else { return }
            resim = KucukResim.hazir(oge.url, oge.degistirilme, boyut)
            if resim == nil { resim = await KucukResim.uret(oge.url, tarih: oge.degistirilme, boyut: boyut) }
        }
    }
}

/// PDF olmayan dosyalar için Quick Look önizlemesi.
struct HizliBakis: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let q = QLPreviewController()
        q.dataSource = context.coordinator
        return q
    }

    func updateUIViewController(_ q: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Kaynak { Kaynak(url: url) }

    final class Kaynak: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            url as NSURL
        }
    }
}
