import SwiftUI

enum Theme {
    static let accent = Color(red: 0.10, green: 0.45, blue: 1.0)
    static let deep = Color(red: 0.04, green: 0.12, blue: 0.32)
    /// Hat koduna göre kararlı renk: aynı hat her ekranda aynı renkte görünür.
    static func color(for line: String) -> Color {
        var hash: UInt64 = 1469598103934665603
        for byte in line.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.62, brightness: 0.84)
    }
    static func etaColor(_ eta: BusETA?) -> Color {
        guard let eta else { return .secondary }
        if eta.state == .atStop { return .green }
        return eta.state == .estimated ? .orange : eta.minutes <= 2 ? Color(red: 1, green: 0.45, blue: 0.2) : .green
    }
}

struct LineBadge: View {
    let code: String
    var body: some View {
        let color = Theme.color(for: code)
        Text(code).font(.system(.headline, design: .rounded).weight(.heavy)).foregroundStyle(.white)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 11))
            .shadow(color: color.opacity(0.4), radius: 5, y: 2)
    }
}

extension View {
    func card() -> some View {
        padding(16).background(.regularMaterial, in: .rect(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

/// Ekran arka planı: yumuşak degrade ve bulanık renk lekeleri.
struct AuroraBackground: View {
    @State private var drift = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)], startPoint: .top, endPoint: .bottom)
            Circle().fill(Theme.accent.opacity(0.38)).frame(width: 340).blur(radius: 70).offset(x: drift ? -90 : -40, y: drift ? -260 : -300)
            Circle().fill(Color.purple.opacity(0.28)).frame(width: 300).blur(radius: 70).offset(x: drift ? 120 : 80, y: drift ? 240 : 300)
            Circle().fill(Color.orange.opacity(0.20)).frame(width: 260).blur(radius: 80).offset(x: drift ? 130 : 90, y: drift ? -200 : -250)
            Circle().fill(Color.teal.opacity(0.22)).frame(width: 260).blur(radius: 80).offset(x: drift ? -120 : -80, y: drift ? 300 : 240)
        }
        .ignoresSafeArea()
        .onAppear { withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true } }
    }
}

/// Canlı veri göstergesi: yayılan halka.
struct LiveDot: View {
    var color: Color = .green
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.5), lineWidth: 2).frame(width: 10, height: 10).scaleEffect(pulse ? 2.4 : 1).opacity(pulse ? 0 : 0.9)
            Circle().fill(color).frame(width: 8, height: 8)
        }
        .frame(width: 22, height: 22)
        .onAppear { withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true } }
    }
}

/// Varış halkası: kalan süreye göre dolar (20 dk ve üzeri boş, durakta tam). Canlı veri seyrek geldiğinden her saniye
/// hesaplanma anından beri geçen süre düşülür; değer değişince akıcı geçer.
struct ETARing: View {
    let eta: BusETA?
    var size: CGFloat = 84
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ring(minutes: eta?.minutes(at: context.date))
        }
    }
    private func ring(minutes: Double?) -> some View {
        let color = Theme.etaColor(eta)
        let progress: Double = {
            guard let eta, let minutes else { return 0 }
            return eta.state == .atStop ? 1 : max(0.04, 1 - min(minutes, 20) / 20)
        }()
        let whole = Int((minutes ?? 0).rounded())
        return ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: size * 0.12)
            Circle().trim(from: 0, to: progress)
                .stroke(AngularGradient(colors: [color.opacity(0.5), color], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(progress, 0.05))),
                        style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                if let eta {
                    switch eta.state {
                    case .atStop: Image(systemName: "checkmark.circle.fill").font(.system(size: size * 0.34)).symbolEffect(.bounce, value: eta.id)
                    default:
                        if whole <= 0 { Image(systemName: "bus.fill").font(.system(size: size * 0.3)).symbolEffect(.pulse) }
                        else {
                            Text("\(whole)").font(.system(size: size * 0.38, weight: .heavy, design: .rounded)).contentTransition(.numericText(value: Double(whole)))
                            Text(eta.state == .estimated ? "dk ~" : "dk").font(.system(size: size * 0.16, weight: .semibold, design: .rounded)).opacity(0.7)
                        }
                    }
                } else { Image(systemName: "moon.zzz.fill").font(.system(size: size * 0.3)).foregroundStyle(.secondary) }
            }
            .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .animation(.spring(duration: 0.8, bounce: 0.25), value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(eta == nil ? "Yaklaşan araç yok" : eta!.state == .atStop ? "Araç durakta" : whole <= 0 ? "Araç yaklaşıyor" : "\(whole) dakika")
    }
}

/// Durağa yaklaşan otobüs: raya sığmış küçük yol; otobüs simgesi durağa doğru kayar.
struct ApproachTrack: View {
    let eta: BusETA?
    private var fraction: Double {
        guard let eta else { return 0 }
        return eta.state == .atStop ? 1 : max(0.02, 1 - min(eta.distance, 3000) / 3000)
    }
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width - 26
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.18)).frame(height: 6).padding(.horizontal, 13)
                Capsule().fill(LinearGradient(colors: [Theme.accent.opacity(0.2), Theme.etaColor(eta)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, width * fraction), height: 6).padding(.leading, 13)
                HStack { Spacer(); Image(systemName: "mappin.circle.fill").font(.title3).foregroundStyle(Theme.accent) }
                if eta != nil {
                    Image(systemName: "bus.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .padding(5).background(Theme.etaColor(eta), in: .circle).shadow(radius: 2)
                        .offset(x: width * fraction)
                }
            }
            .animation(.spring(duration: 1.2, bounce: 0.2), value: fraction)
        }
        .frame(height: 28)
    }
}

/// Boş ekran: yolda giden otobüs.
struct DrivingBus: View {
    @State private var go = false
    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.25)).frame(height: 4)
                Image(systemName: "bus.fill").font(.system(size: 34)).foregroundStyle(Theme.accent)
                    .offset(x: go ? 210 : -10).rotationEffect(.degrees(go ? 0 : 0))
            }
            .frame(width: 260).clipped()
        }
        .onAppear { withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: false)) { go = true } }
    }
}

struct TypingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate * 6
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    Circle().fill(.secondary).frame(width: 8, height: 8).offset(y: sin(t + Double(index) * 0.8) * -4)
                }
            }
        }
        .padding(12).background(.regularMaterial, in: .capsule)
    }
}

extension View {
    /// Kaynak kart: açılan sayfa bu karttan büyüyerek gelir (iOS yakınlaştırma geçişi).
    func zoomSource(id: String) -> some View { modifier(ZoomSource(id: id)) }
    /// Kartlar sırayla yukarı kayarak belirir; sayfa açılışına hareket katar.
    func cascadeIn(_ index: Int) -> some View { modifier(CascadeIn(index: index)) }
}
struct ZoomSource: ViewModifier {
    let id: String
    @Environment(\.zoomNamespace) private var namespace
    func body(content: Content) -> some View {
        if let namespace { content.matchedTransitionSource(id: id, in: namespace) } else { content }
    }
}
struct CascadeIn: ViewModifier {
    let index: Int
    @State private var shown = false
    func body(content: Content) -> some View {
        content.opacity(shown ? 1 : 0).offset(y: shown ? 0 : 26).scaleEffect(shown ? 1 : 0.97)
            .onAppear { withAnimation(.spring(duration: 0.55, bounce: 0.25).delay(Double(min(index, 8)) * 0.06)) { shown = true } }
    }
}
