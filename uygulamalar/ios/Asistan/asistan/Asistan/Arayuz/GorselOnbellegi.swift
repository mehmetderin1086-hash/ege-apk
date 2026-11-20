import SwiftUI
import ImageIO
import UIKit

/// P3.9: eski sohbet fotoğrafları için küçük resim önbelleği. Sohbet açılışında fotoğraflar tam boy
/// `UIImage(contentsOfFile:)` ile ana iş parçacığında çözülmez; ImageIO ile istenen kenara küçültülmüş hâli
/// ana iş parçacığı dışında üretilir ve bellekte (NSCache, ≤300 görsel / ≤48 MB) tutulur. Tam boy yalnız büyütülünce yüklenir.
@MainActor
enum GorselOnbellegi {
    static let kucukler: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 300
        c.totalCostLimit = 48 * 1024 * 1024
        return c
    }()

    /// Görseli ana aktör dışına taşımak için kutu (UIImage değişmez; yalnız okunur).
    nonisolated struct Kutu: @unchecked Sendable { let resim: UIImage? }

    static func anahtar(_ url: URL, kenarPx: Int) -> NSString { "\(url.path)#\(kenarPx)" as NSString }

    /// Büyük kenarı en çok `kenarPx` piksel olan küçük resim (EXIF yönü uygulanmış). Dosya yoksa ya da çözülemezse nil.
    static func kucuk(_ url: URL, kenarPx: Int) async -> UIImage? {
        let a = anahtar(url, kenarPx: kenarPx)
        if let r = kucukler.object(forKey: a) { return r }
        let kutu = await Task.detached(priority: .userInitiated) { Kutu(resim: Self.kucukUret(url, kenarPx: kenarPx)) }.value
        guard let r = kutu.resim else { return nil }
        let px = (r.cgImage.map { $0.width * $0.height }) ?? Int(r.size.width * r.size.height * r.scale * r.scale)
        kucukler.setObject(r, forKey: a, cost: px * 4)
        return r
    }

    /// Tam boy görsel (büyütme ve yeniden üretim için); önbelleğe alınmaz, ana iş parçacığı dışında çözülür.
    static func tamBoy(_ url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { () -> Kutu in
            guard let veri = try? Data(contentsOf: url), let r = UIImage(data: veri) else { return Kutu(resim: nil) }
            return Kutu(resim: r.preparingForDisplay() ?? r)
        }.value.resim
    }

    nonisolated static func kucukUret(_ url: URL, kenarPx: Int) -> UIImage? {
        guard let kaynak = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let secenek: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, kenarPx),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(kaynak, 0, secenek as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Kalıcı fotoğrafın küçük resmi: yüklenene kadar aynı boyutta yer tutucu (yerleşim zıplamaz).
/// Dokununca (VoiceOver'da etkinleştirince) `buyut` tam boy görseli açar.
struct KucukGorsel: View {
    let url: URL
    /// Kare çerçevenin kenarı (pt); küçük resim ekran ölçeğine göre piksel olarak istenir.
    let kenar: CGFloat
    var buyut: ((URL) -> Void)? = nil
    @State private var resim: UIImage?
    @State private var yuklenemedi = false
    @Environment(\.displayScale) private var olcek

    var body: some View {
        ZStack {
            if let resim {
                Image(uiImage: resim).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12).fill(.quaternary)
                Image(systemName: yuklenemedi ? "photo.badge.exclamationmark" : "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: kenar, height: kenar)
        .clipShape(.rect(cornerRadius: 12))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(yuklenemedi ? "Fotoğraf bulunamadı" : "Eklenen fotoğraf")
        .accessibilityHint("Büyütmek için çift dokun")
        .accessibilityIdentifier("mesaj-resmi")
        .onTapGesture(count: 2) { if !yuklenemedi { buyut?(url) } }
        .accessibilityAction { if !yuklenemedi { buyut?(url) } }
        .task(id: url) {
            let r = await GorselOnbellegi.kucuk(url, kenarPx: Int((kenar * max(1, olcek)).rounded()))
            resim = r
            yuklenemedi = r == nil
        }
    }
}
