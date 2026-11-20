import SwiftUI

/// Pusula: kuzey işaretli halka içinde, verilen yöne dönen büyük ok (yay animasyonlu).
struct CompassArrow: View {
    let bearing: Double?
    var size: CGFloat = 78
    var color: Color = Theme.accent
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.12))
            Circle().stroke(color.opacity(0.45), lineWidth: 2.5)
            ForEach(0..<4, id: \.self) { i in
                let letter = ["K", "D", "G", "B"][i], angle = Double(i) * 90 * .pi / 180
                Text(letter).font(.system(size: size * 0.15, weight: .heavy, design: .rounded)).foregroundStyle(i == 0 ? Color.red : Color.primary.opacity(0.55))
                    .offset(x: size * 0.40 * CGFloat(sin(angle)), y: -size * 0.40 * CGFloat(cos(angle)))
            }
            if let bearing {
                Image(systemName: "location.north.fill").font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(color)
                    .rotationEffect(.degrees(bearing)).shadow(color: color.opacity(0.4), radius: 3)
            } else { Image(systemName: "questionmark").font(.title2).foregroundStyle(.secondary) }
        }
        .frame(width: size, height: size)
        .animation(.spring(duration: 0.9, bounce: 0.35), value: bearing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bearing.map { "Yön: \(CompassText.heading($0))" } ?? "Yön bilinmiyor")
    }
}

/// Büyük yön etiketi: "→ BOĞAZKÖY YÖNÜ" ya da "SON DURAK". Boşsa görünmez.
struct DirectionTag: View {
    let text: String
    var large = true
    var body: some View {
        let clean = text.trimmingCharacters(in: .whitespaces)
        if !clean.isEmpty {
            let isLast = fold(clean).contains("son durak")
            HStack(spacing: 6) {
                Image(systemName: isLast ? "flag.checkered" : "arrow.right.circle.fill").font(large ? .body.weight(.bold) : .caption.weight(.bold))
                Text(isLast ? "SON DURAK" : "\(clean) YÖNÜ").font(large ? .callout.weight(.heavy) : .caption.weight(.heavy)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, large ? 12 : 8).padding(.vertical, large ? 7 : 4)
            .background((isLast ? Color.orange : Theme.accent).opacity(0.16), in: .capsule)
            .foregroundStyle(isLast ? Color(red: 0.75, green: 0.36, blue: 0) : Color(red: 0.05, green: 0.30, blue: 0.80))
            .accessibilityLabel(isLast ? "Son durak" : "Yön: \(clean)")
        }
    }
}

/// Durak ekranının yön paneli: tabela yönü ve güzergâhlardan hesaplanan her yön için pusula, varış, açıklama ve o yönde geçen hatlar.
struct StopDirectionPanel: View {
    let stop: Durak
    @Environment(AppModel.self) private var model
    @State private var groups: [StopDirectionInfo] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Yön bilgisi", systemImage: "arrow.triangle.turn.up.right.diamond.fill").font(.title3.weight(.heavy))
            if !stop.direction.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Durak tabelası").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    DirectionTag(text: stop.direction)
                }
            }
            if groups.isEmpty {
                Text(loaded ? "Bu durak için güzergâh yönü bulunamadı." : "Güzergâh yönleri yükleniyor…").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                HStack(alignment: .center, spacing: 16) {
                    CompassArrow(bearing: group.bearing, size: 84)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("→ \(group.destination)").font(.title2.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                        if let bearing = group.bearing {
                            Text(CompassText.heading(bearing)).font(.headline.weight(.bold)).foregroundStyle(.primary.opacity(0.8))
                            Text("Pusula: \(CompassText.name(bearing)) · \(Int(bearing.rounded()) % 360)°").font(.subheadline.weight(.medium).monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Text("Bu yönde geçen hatlar").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        LineBadgeRow(lines: group.lines, stopCode: stop.code)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14).background(Theme.accent.opacity(0.07), in: .rect(cornerRadius: 18))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibility(group))
                .cascadeIn(index)
            }
        }
        .card()
        .task {
            var seen = Set<String>(), entries: [RouteStore.Entry] = []
            for e in await model.linesAtStop(stop.code) where seen.insert(e.line + e.direction).inserted { entries.append(e) }
            var routes: [String: LineRoute] = [:]
            for line in Set(entries.map(\.line)).prefix(40) { routes[line] = await model.route(line) }
            withAnimation(.spring(duration: 0.5)) { groups = StopDirections.make(stopCode: stop.code, entries: entries, routes: routes); loaded = true }
        }
    }

    private func accessibility(_ group: StopDirectionInfo) -> String {
        let heading = group.bearing.map { CompassText.heading($0) } ?? ""
        let lines = group.lines.joined(separator: ", ")
        return "\(group.destination) yönü, \(heading), hatlar: \(lines)"
    }
}

/// Bir yönde geçen hat rozetleri (dokununca hat ekranı o durakla açılır).
struct LineBadgeRow: View {
    let lines: [String]
    let stopCode: Int
    var body: some View {
        FlowRow(spacing: 6) {
            ForEach(lines, id: \.self) { code in
                NavigationLink(value: Route.line(code: code, stop: stopCode)) { LineBadge(code: code) }.buttonStyle(.plain)
            }
        }
    }
}
