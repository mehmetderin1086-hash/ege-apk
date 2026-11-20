import SwiftUI

/// Sekine tasarım token'ları. Hardcode renk/font yasağı (CLAUDE.md): tüm renkler
/// ve ölçüler buradan gelir. Sıcak, sakin, dini bir estetik; koyu/açık tema uyumlu.
/// Vurgu renkleri seçili `ColorTheme`'den gelir (81 çağrı yeri değişmez).
enum Palette {
    /// Ana vurgu — seçili temaya göre.
    static var accent: Color { dynamic(light: hex(ColorTheme.current.accent.0),
                                       dark: hex(ColorTheme.current.accent.1)) }
    /// İkincil vurgu (altın) — seçili temaya göre.
    static var gold: Color { dynamic(light: hex(ColorTheme.current.gold.0),
                                     dark: hex(ColorTheme.current.gold.1)) }

    static var background: Color { dynamic(light: hex(ColorTheme.current.background.0), dark: hex(ColorTheme.current.background.1)) }
    static var card: Color { dynamic(light: hex(0xFFFFFF), dark: hex(0x24282B)) }
    /// Aktif satır zemini — seçili temaya uyumlu.
    static var cardActive: Color { dynamic(light: hex(ColorTheme.current.accentSoft.0),
                                           dark: hex(ColorTheme.current.accentSoft.1)) }

    static let onAccent = dynamic(light: hex(0xFFFFFF), dark: hex(0x111111))
    static let textPrimary = dynamic(light: hex(0x1A1C18), dark: hex(0xF2F1EA))
    static var textSecondary: Color { ColorTheme.highContrast ? textPrimary : dynamic(light: hex(0x5C5F57), dark: hex(0xB6B9AE)) }
    static let separator = dynamic(light: hex(0xE3DED3), dark: hex(0x2C2F27))

    static func swatch(_ value: UInt) -> Color { Color(uiColor: hex(value)) }

    // MARK: helpers
    private static func hex(_ value: UInt) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1)
    }
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

/// Ölçek-duyarlı tipografi. Yaşlı kullanıcı için ayarlardan büyütülebilir;
/// ayrıca Dynamic Type'a saygı duyar.
struct SekineFont {
    static func countdown(_ scale: FontScale) -> Font {
        .system(size: 56 * scale.multiplier, weight: .bold, design: .rounded)
            .monospacedDigit()
    }
    static func hugeTime(_ scale: FontScale) -> Font {
        .system(size: 40 * scale.multiplier, weight: .semibold, design: .rounded)
    }
    static func title(_ scale: FontScale) -> Font {
        .system(size: 22 * scale.multiplier, weight: .semibold, design: .rounded)
    }
    static func row(_ scale: FontScale) -> Font {
        .system(size: 20 * scale.multiplier, weight: .medium, design: .rounded)
    }
    static func caption(_ scale: FontScale) -> Font {
        .system(size: 15 * scale.multiplier, weight: .regular, design: .rounded)
    }
}

/// İki farklı somut `ButtonStyle` arasında çalışma zamanında (ör. bir koşula göre) seçim
/// yapabilmek için tip-silici sarmalayıcı. SwiftUI'de `condition ? StyleA() : StyleB()`
/// derlenmez (`some ButtonStyle` iki farklı somut tipi birleştiremez); bu, standart çözüm.
struct AnyButtonStyleBox: ButtonStyle {
    private let makeBodyClosure: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) {
        makeBodyClosure = { AnyView(style.makeBody(configuration: $0)) }
    }
    func makeBody(configuration: Configuration) -> some View {
        makeBodyClosure(configuration)
    }
}

extension View {
    /// Kart görünümü (yumuşak köşe, hafif gölge).
    func sekineCard(active: Bool = false) -> some View {
        self
            .background(active ? Palette.cardActive : Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: EzanDesign.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: EzanDesign.cardRadius, style: .continuous)
                    .strokeBorder(active ? Palette.accent.opacity(0.35) : Palette.separator.opacity(0.45), lineWidth: ColorTheme.cardStyle == "outlined" ? 2 : 1)
            )
    }
}

// Shared visual language for the daily dashboard and discovery screens.
enum EzanDesign {
    static var forest: Color { Palette.swatch(ColorTheme.current.hero.0) }
    static var forestLight: Color { Palette.swatch(ColorTheme.current.hero.1) }
    static var gold: Color { Palette.swatch(ColorTheme.current.gold.1) }
    static var cardRadius: CGFloat { ColorTheme.cardStyle == "compact" ? 12 : 24 }
    static var heroGradient: LinearGradient { LinearGradient(colors: [forestLight, forest], startPoint: .topLeading, endPoint: .bottomTrailing) }

}

struct EzanPattern: View {
    @AppStorage("appearance.pattern", store: ColorTheme.preferences) private var visible = true
    var body: some View {
        Canvas { context, size in
            guard visible else { return }
            for row in 0..<8 {
                for column in 0..<9 {
                    let x = CGFloat(column) * 54 + (row.isMultiple(of: 2) ? 0 : 27)
                    let y = CGFloat(row) * 54
                    var path = Path()
                    for point in 0..<8 {
                        let angle = Double(point) * .pi / 4
                        let p = CGPoint(x: x + cos(angle) * 24, y: y + sin(angle) * 24)
                        if point == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    path.closeSubpath()
                    context.stroke(path, with: .color(.white.opacity(0.065)), lineWidth: 0.7)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct EzanPageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow.uppercased(with: Locale(identifier: "tr_TR")))
                .font(.system(size: 10, weight: .bold)).tracking(2.8).foregroundStyle(Palette.accent)
            Text(title).font(.system(.largeTitle, design: .serif).weight(.semibold)).foregroundStyle(Palette.textPrimary)
            Text(subtitle).font(.subheadline).foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EzanSectionTitle: View {
    let title: String
    var detail: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(.title3, design: .serif).weight(.semibold)).foregroundStyle(Palette.textPrimary)
            Spacer()
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(Palette.textSecondary) }
        }
    }
}

struct EzanFeatureLabel: View {
    let title: String
    let subtitle: String
    let icon: String
    var tint: Color = Palette.accent
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.title3).foregroundStyle(tint)
                .frame(width: 46, height: 46).background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.textSecondary)
        }
        .padding(16).sekineCard()
    }
}

struct EzanPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
