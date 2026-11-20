import SwiftUI

/// İkra renk sistemi (17 Eki 2026): yalnız mavi ve sarı tonları. Mavi–sarı ikilisi kırmızı–yeşil renk körlüğünde de
/// ayırt edilir; yazı her zaman zeminiyle en az 4.5:1 kontrastta (sarı zeminde lacivert, mavi zeminde beyaz yazı).
enum Theme {
    static let navy = Color(red: 0.039, green: 0.122, blue: 0.290)      // #0A1F4A
    static let blue = Color(red: 0.082, green: 0.329, blue: 0.800)      // #1554CC
    static let sky = Color(red: 0.235, green: 0.557, blue: 0.965)       // #3C8EF6
    static let yellow = Color(red: 1.000, green: 0.835, blue: 0.290)    // #FFD54A
    static let amber = Color(red: 0.961, green: 0.651, blue: 0.000)     // #F5A600

    /// Birincil yüzey: lacivertten maviye.
    static let gradient = LinearGradient(colors: [navy, blue], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Vurgu yüzeyi: sarıdan kehribara (üstündeki yazı lacivert olmalı).
    static let warmGradient = LinearGradient(colors: [yellow, amber], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let cardRadius: CGFloat = 20

    /// Kart ve satır kenarlığı: açıkta mavi-gri, koyuda açık mavi. Yüksek kontrast açıkken kalınlaşır (`okuSurface`).
    static let border = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.45, green: 0.58, blue: 0.85, alpha: 0.45)
                                           : UIColor(red: 0.16, green: 0.30, blue: 0.58, alpha: 0.22)
    })

    static func hostColor(_ speaker: Speaker) -> Color {
        switch speaker {
        case .a: blue
        case .b: amber
        case .c: sky   // #9 konuk uzman
        }
    }
}

/// Görme kolaylığı tercihleri (Ayarlar › Görünüm ve görme kolaylığı). Kökte uygulanır, bütün ekranlara yayılır.
enum VisionPrefs {
    static let textSizeKey = "vision.textSize"
    static let boldKey = "vision.bold"
    static let contrastKey = "vision.highContrast"

    /// 0: iPhone ayarı, 1: büyük (varsayılan), 2: çok büyük.
    static func range(_ level: Int) -> ClosedRange<DynamicTypeSize> {
        switch level {
        case 0: .xSmall ... .accessibility5
        case 2: .xxxLarge ... .accessibility5
        default: .xLarge ... .accessibility5
        }
    }
}

/// Bölüm kapak görseli: başlıktan türetilen renkli, sabit desen.
struct EpisodeArtwork: View {
    var title: String
    var size: CGFloat = 56
    var cover: VisualCover?

    var body: some View {
        if let cover {
            GeneratedCoverView(cover: cover, size: size)
        } else {
        let seed = title.unicodeScalars.reduce(UInt32(7)) { $0 &* 31 &+ $1.value }
        let hue = Double(seed % 360) / 360
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.65, brightness: 0.9),
                                          Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.75, brightness: 0.7)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "waveform")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
    }
}

struct GeneratedCoverView: View {
    var cover: VisualCover
    var size: CGFloat

    private var colors: [Color] {
        switch cover.theme {
        case "forest": [.init(red: 0.03, green: 0.19, blue: 0.18), .mint]
        case "plum": [.init(red: 0.19, green: 0.06, blue: 0.30), .pink]
        case "ember": [.init(red: 0.25, green: 0.10, blue: 0.07), .orange]
        default: [.init(red: 0.03, green: 0.13, blue: 0.27), .cyan]
        }
    }

    var body: some View {
        Group {
            if let encoded = cover.imageData, let image = GeneratedImageCache.image(encoded) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                legacyArtwork
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cover.accessibilityLabel)
    }

    private var legacyArtwork: some View {
        ZStack {
            colors[0]
            Canvas { context, canvas in
                let w = canvas.width
                for i in 0..<5 {
                    var path = Path()
                    let n = CGFloat(i)
                    if cover.motif == "layers" {
                        path.addRoundedRect(in: CGRect(x: w * (0.15 + n * 0.08), y: w * (0.08 + n * 0.06), width: w * 0.7, height: w * 0.40), cornerSize: CGSize(width: w * 0.06, height: w * 0.06))
                    } else if cover.motif == "waves" {
                        path.move(to: CGPoint(x: -w * 0.1, y: w * (0.15 + n * 0.10)))
                        path.addCurve(to: CGPoint(x: w * 1.1, y: w * (0.15 + n * 0.10)), control1: CGPoint(x: w * 0.3, y: -w * 0.25), control2: CGPoint(x: w * 0.6, y: w * 0.9))
                    } else if cover.motif == "network" {
                        let point = CGPoint(x: w * (0.15 + n * 0.18), y: w * (i % 2 == 0 ? 0.2 : 0.5))
                        path.move(to: CGPoint(x: w * 0.5, y: w * 0.35))
                        path.addLine(to: point)
                        path.addEllipse(in: CGRect(x: point.x - w * 0.035, y: point.y - w * 0.035, width: w * 0.07, height: w * 0.07))
                    } else {
                        path.addEllipse(in: CGRect(x: w * (0.15 + n * 0.08), y: w * (0.03 + n * 0.05), width: w * (0.8 - n * 0.12), height: w * (0.8 - n * 0.12)))
                    }
                    context.stroke(path, with: .color(colors[1].opacity(0.18 + Double(i) * 0.09)), lineWidth: max(1, size * 0.006))
                }
            }
            VStack(alignment: .leading, spacing: size * 0.035) {
                if size >= 180 {
                    Text("OKU").font(.system(size: size * 0.034, weight: .bold, design: .rounded)).tracking(2)
                    Spacer(minLength: 0)
                }
                Image(systemName: cover.symbol).font(.system(size: size * (size >= 180 ? 0.18 : 0.40), weight: .medium))
                    .foregroundStyle(colors[1])
                if size >= 180 {
                    Text(cover.title).font(.system(size: size * 0.075, weight: .bold, design: .rounded)).lineLimit(3).minimumScaleFactor(0.8)
                    Text(cover.subtitle).font(.system(size: size * 0.038)).lineLimit(3).opacity(0.85)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: size >= 180 ? .leading : .center)
            .padding(size * 0.085)
            .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cover.accessibilityLabel)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var enabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .frame(minHeight: 24)
            .background(enabled ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.gray.opacity(0.35)),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.yellow.opacity(configuration.isPressed ? 0.9 : 0), lineWidth: 3) }
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension Double {
    /// 125 → "2:05", 3725 → "1:02:05"
    var clockText: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    var minutesText: String {
        let minutes = Int((self / 60).rounded())
        return minutes < 1 ? "1 dk'dan kısa" : "\(minutes) dk"
    }
}

/// Oku'nun ortak ekran başlığı: metin küçülmez, dekoratif simge VoiceOver'a girmez.
struct OkuScreenIntro: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let eyebrow: String
    let title: String
    let subtitle: String
    var symbol = "sparkle"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !typeSize.isAccessibilitySize {
            HStack {
                Text(eyebrow.uppercased(with: Locale(identifier: "tr_TR")))
                    .font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(Color.accentColor)
                Spacer(minLength: 8)
                Image(systemName: symbol).font(.title2).foregroundStyle(Color.accentColor).accessibilityHidden(true)
            }
            }
            Text(title.replacingOccurrences(of: "\n", with: " ")).font(.system(.title2, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
    }
}

/// Tek eylemli kart; başlık ve açıklama birlikte seslendirilir.
struct OkuActionLabel: View {
    let title: String
    let detail: String
    let symbol: String
    var prominent = false
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title2.weight(.medium))
                .frame(width: 44, height: 44)
                .background((prominent ? Color.white : Color.accentColor).opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(prominent ? Color.white.opacity(0.9) : Color.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold)).accessibilityHidden(true)
        }
        .foregroundStyle(prominent ? Color.white : Color.primary)
        .padding(18).frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .background(prominent ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                    in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay { RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1) }
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .combine)
    }
}

/// Sıkışan bölmeli seçiciler büyük yazıda menüye dönüşür; seçili değer ve tüm seçenekler erişilebilir kalır.
struct AccessiblePickerStyle: ViewModifier {
    @Environment(\.dynamicTypeSize) private var size
    func body(content: Content) -> some View {
        if size >= .xxxLarge {
            content.pickerStyle(.menu).frame(minHeight: 44)
        } else {
            content.pickerStyle(.segmented)
        }
    }
}

// MARK: - Oku workspace design

extension Theme {
    /// Uygulama zemini: açıkta çok açık mavi, koyuda koyu lacivert.
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.035, green: 0.063, blue: 0.125, alpha: 1)
            : UIColor(red: 0.945, green: 0.961, blue: 0.988, alpha: 1)
    })
    /// Kart yüzeyi: açıkta beyaz, koyuda lacivert-gri.
    static let card = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.075, green: 0.118, blue: 0.212, alpha: 1)
            : UIColor.white
    })
}

struct OkuSectionHeading: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
            if let detail { Text(detail).font(.subheadline).foregroundStyle(.primary.opacity(0.72)) }
        }.fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Consistent, fully wrapping destination row. Status is stated in text as well as colour.
struct OkuRouteLabel: View {
    let title: String
    let detail: String
    let symbol: String
    var tint: Color = .accentColor
    var showsChevron = true
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3.weight(.semibold))
                .foregroundStyle(tint).frame(width: 44, height: 44)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline.weight(.bold)).foregroundStyle(.primary)
                if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(.primary.opacity(0.72)) }
            }.fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.right").font(.caption.weight(.bold))
                    .foregroundStyle(.secondary).padding(.top, 14).accessibilityHidden(true)
            }
        }.frame(minHeight: 48).padding(16)
            .contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}

private struct OkuSurface: ViewModifier {
    @AppStorage(VisionPrefs.contrastKey) private var highContrast = true
    func body(content: Content) -> some View {
        content.background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(highContrast ? Theme.border.opacity(2.2) : Theme.border, lineWidth: highContrast ? 2 : 1) }
    }
}

extension View {
    func okuSurface() -> some View { modifier(OkuSurface()) }
}

struct OkuSettingsButton: View {
    @Environment(AppState.self) private var app
    /// Verilirse Ayarlar o modülün bölümünde açılır.
    var module: AppState.MainTab?
    var body: some View {
        Button("Ayarlar", systemImage: "slider.horizontal.3") {
            if let module { app.settingsRoute = .module(module) } else { app.selectedTab = .settings }
        }
            .accessibilityHint("Görünüm, ses, bağlantı ve veri ayarlarını açar")
    }
}


/// Decode once for repeated library/mini-player renders; bounded in-memory cache.
@MainActor enum GeneratedImageCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        cache.countLimit = 12
        return cache
    }()
    static func image(_ encoded: String) -> UIImage? {
        let key = encoded as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = Data(base64Encoded: encoded), let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * 4))
        return image
    }
}

/// Kökte uygulanan görme kolaylığı: yazı boyutu kademesi, kalın yazı ve UIKit bileşenlerinin mavi–sarı görünümü.
/// Sistemdeki daha büyük yazı ve kalın metin tercihleri her zaman geçerli kalır (yalnız alt sınır yükseltilir).
struct VisionRoot: ViewModifier {
    @AppStorage(VisionPrefs.textSizeKey) private var textSize = 1
    @AppStorage(VisionPrefs.boldKey) private var bold = true
    @Environment(\.legibilityWeight) private var systemWeight

    func body(content: Content) -> some View {
        content
            .dynamicTypeSize(VisionPrefs.range(textSize))
            .environment(\.legibilityWeight, bold ? .bold : systemWeight)
            .onAppear { VisionRoot.applyAppearance() }
    }

    /// Gezinme başlıkları kalın ve lacivert/beyaz; seçim kontrollerinde seçili bölüm sarı, yazısı lacivert ve kalın.
    @MainActor static func applyAppearance() {
        let title = UIColor { $0.userInterfaceStyle == .dark ? .white : UIColor(red: 0.039, green: 0.122, blue: 0.290, alpha: 1) }
        // Opak gezinme çubuğu: kayan içerik yarı saydam çubuğun altında yazıyla üst üste binmesin; alt kenarda belirgin çizgi.
        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.035, green: 0.063, blue: 0.125, alpha: 1)
                                                                         : UIColor(red: 0.945, green: 0.961, blue: 0.988, alpha: 1) }
        bar.shadowColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.45, green: 0.58, blue: 0.85, alpha: 0.6)
                                                                     : UIColor(red: 0.16, green: 0.30, blue: 0.58, alpha: 0.35) }
        bar.titleTextAttributes = [.foregroundColor: title, .font: UIFont.preferredFont(forTextStyle: .headline).withWeight(.bold)]
        bar.largeTitleTextAttributes = [.foregroundColor: title, .font: UIFont.preferredFont(forTextStyle: .largeTitle).withWeight(.heavy)]
        let nav = UINavigationBar.appearance()
        nav.standardAppearance = bar
        nav.compactAppearance = bar
        // En üstte (kaydırılmamışken) sistemin kenar görünümü kalır: büyük başlık orada çizilir; kaydırınca opak çubuk gelir.
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.titleTextAttributes = bar.titleTextAttributes
        edge.largeTitleTextAttributes = bar.largeTitleTextAttributes
        nav.scrollEdgeAppearance = edge
        let segment = UISegmentedControl.appearance()
        segment.selectedSegmentTintColor = UIColor(red: 1, green: 0.835, blue: 0.29, alpha: 1)
        segment.setTitleTextAttributes([.foregroundColor: UIColor(red: 0.039, green: 0.122, blue: 0.290, alpha: 1),
                                        .font: UIFont.preferredFont(forTextStyle: .subheadline).withWeight(.bold)], for: .selected)
        segment.setTitleTextAttributes([.font: UIFont.preferredFont(forTextStyle: .subheadline).withWeight(.semibold)], for: .normal)
        UIPageControl.appearance().currentPageIndicatorTintColor = UIColor(red: 0.082, green: 0.329, blue: 0.8, alpha: 1)
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        UIFont.systemFont(ofSize: pointSize, weight: weight)
    }
}

extension Theme {
    /// Yazı ve simge için mavi: açıkta koyu mavi, koyuda açık mavi (her iki zeminde en az 4.5:1).
    nonisolated static let blueInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.50, green: 0.70, blue: 1.0, alpha: 1)
                                           : UIColor(red: 0.082, green: 0.329, blue: 0.800, alpha: 1)
    })
    /// Yazı ve simge için sarı: açıkta koyu kehribar (beyazda okunur), koyuda parlak sarı.
    nonisolated static let goldInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 1.0, green: 0.835, blue: 0.29, alpha: 1)
                                           : UIColor(red: 0.60, green: 0.40, blue: 0.0, alpha: 1)
    })
}
