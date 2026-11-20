import SwiftUI

/// Hat şeridi: güzergâh bir çubuk, araçlar üzerinde kayan otobüs simgeleri (veri geldikçe yay animasyonuyla ilerler), sana en yakın durak kırmızı iğne.
struct LineTrackBar: View {
    let track: LineSummary.Track
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.right").font(.caption2.weight(.heavy)).foregroundStyle(color)
                Text(track.destination.isEmpty ? (track.direction == "G" ? "Gidiş" : "Dönüş") : track.destination).font(.caption.weight(.bold)).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(track.buses.count) araç").font(.caption2.weight(.heavy)).foregroundStyle(track.buses.isEmpty ? Color.secondary : color).contentTransition(.numericText(value: Double(track.buses.count)))
            }
            GeometryReader { geo in
                let width = geo.size.width, usable = max(1, width - 26)
                ZStack(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: [color.opacity(0.55), color.opacity(0.15)], startPoint: .leading, endPoint: .trailing)).frame(height: 9).padding(.horizontal, 3)
                    // Durak işaretleri
                    ForEach(0..<9, id: \.self) { i in Circle().fill(.white.opacity(0.75)).frame(width: 3.5, height: 3.5).offset(x: 13 + usable * CGFloat(i + 1) / 10 - 2) }
                    if let user = track.user {
                        Image(systemName: "mappin.circle.fill").font(.system(size: 20)).foregroundStyle(.red, .white).shadow(radius: 1)
                            .offset(x: 3 + user * usable, y: -1).symbolEffect(.bounce, options: .repeat(.periodic(delay: 3)))
                    }
                    ForEach(Array(track.buses.enumerated()), id: \.offset) { _, fraction in
                        BusDot(color: color).offset(x: 2 + CGFloat(fraction) * usable)
                    }
                }
                .animation(.spring(duration: 1.4, bounce: 0.2), value: track.buses)
            }
            .frame(height: 28)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.destination) yönü, \(track.buses.count) araç yolda")
    }
}

/// Nabız atan otobüs noktası.
struct BusDot: View {
    let color: Color
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.55), lineWidth: 2).frame(width: 22, height: 22).scaleEffect(pulse ? 1.9 : 1).opacity(pulse ? 0 : 0.9)
            Circle().fill(color.gradient).frame(width: 22, height: 22).overlay(Circle().stroke(.white, lineWidth: 1.5)).shadow(color: color.opacity(0.5), radius: 3)
            Image(systemName: "bus.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
        }
        .onAppear { withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) { pulse = true } }
    }
}

/// Favori durak kartı: durak adına göre renkli degrade, parlayan yıldız, hat rozetleri sırayla belirir, altta sürekli akan otobüs.
struct FavoriteStopCard: View {
    let stop: Durak
    @Environment(AppModel.self) private var model
    @State private var lines: [String] = []
    @State private var shown = false

    var body: some View {
        let color = Theme.color(for: stop.name)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "star.fill").foregroundStyle(.yellow).symbolEffect(.pulse, options: .repeating).shadow(color: .yellow.opacity(0.6), radius: 4)
                Spacer()
                if !lines.isEmpty { Text("\(lines.count) hat").font(.caption2.weight(.heavy)).padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.28), in: .capsule) }
            }
            Text(stop.name).font(.system(.headline, design: .rounded).weight(.heavy)).lineLimit(2).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            if !stop.district.isEmpty { Text(stop.district).font(.footnote.weight(.semibold)).opacity(0.9).lineLimit(1) }
            if !stop.direction.isEmpty {
                Label(fold(stop.direction).contains("son durak") ? "SON DURAK" : "\(stop.direction) YÖNÜ", systemImage: "arrow.right.circle.fill").font(.footnote.weight(.heavy)).lineLimit(2)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(.white.opacity(0.28), in: .capsule)
            }
            HStack(spacing: 5) {
                ForEach(Array(lines.prefix(4).enumerated()), id: \.element) { index, line in
                    Text(line).font(.caption2.weight(.heavy)).padding(.horizontal, 7).padding(.vertical, 3).background(.white.opacity(0.3), in: .rect(cornerRadius: 6))
                        .scaleEffect(shown ? 1 : 0.3).opacity(shown ? 1 : 0).animation(.spring(duration: 0.5, bounce: 0.5).delay(Double(index) * 0.08), value: shown)
                }
                if lines.count > 4 { Text("+\(lines.count - 4)").font(.caption2.weight(.heavy)) }
            }.frame(minHeight: 20)
            MiniRoad()
        }
        .foregroundStyle(.white)
        .padding(14).frame(width: 190, alignment: .leading)
        .background(LinearGradient(colors: [color, color.opacity(0.65), Color.black.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.25), lineWidth: 1))
        .shadow(color: color.opacity(0.4), radius: 10, y: 5)
        .task {
            var seen = Set<String>()
            lines = await model.linesAtStop(stop.code).compactMap { seen.insert($0.line).inserted ? $0.line : nil }
            withAnimation { shown = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Favori durak \(stop.name), \(lines.count) hat")
    }
}

/// Sürekli akan küçük yol ve otobüs.
struct MiniRoad: View {
    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geo in
                let t = context.date.timeIntervalSinceReferenceDate * 0.22
                let x = CGFloat(t - floor(t)) * (geo.size.width + 24) - 12
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.28)).frame(height: 3).offset(y: 9)
                    Image(systemName: "bus.fill").font(.system(size: 14, weight: .bold)).offset(x: x)
                }
            }
        }.frame(height: 18).clipped()
    }
}

/// Saate göre değişen, hareketli karşılama başlığı.
struct GreetingHeader: View {
    private var info: (text: String, symbol: String, colors: [Color]) {
        switch IETTDates.calendar.component(.hour, from: .now) {
        case 5..<12: ("Günaydın", "sun.max.fill", [.yellow, .orange])
        case 12..<18: ("İyi günler", "cloud.sun.fill", [.cyan, .yellow])
        case 18..<22: ("İyi akşamlar", "sunset.fill", [.orange, .pink])
        default: ("İyi geceler", "moon.stars.fill", [.indigo, .purple])
        }
    }
    var body: some View {
        let i = info
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 12) {
                Image(systemName: i.symbol).symbolRenderingMode(.multicolor).font(.system(size: 30))
                    .rotationEffect(.degrees(i.symbol == "sun.max.fill" ? t * 20 : sin(t) * 6))
                    .scaleEffect(1 + 0.05 * sin(t * 2))
                VStack(alignment: .leading, spacing: 0) {
                    Text(i.text).font(.system(.title3, design: .rounded).weight(.heavy)).foregroundStyle(LinearGradient(colors: i.colors, startPoint: .leading, endPoint: .trailing))
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "tr_TR")))).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }
}

/// Kritik uyarı çerçevesi için yumuşak nabız.
struct PulsingStroke: ViewModifier {
    let color: Color, active: Bool
    @State private var on = false
    func body(content: Content) -> some View {
        content.overlay(RoundedRectangle(cornerRadius: 20).stroke(color.opacity(active ? (on ? 0.95 : 0.35) : 0.6), lineWidth: active ? 2.5 : 1.5))
            .onAppear { if active { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true } } }
    }
}
