import SwiftUI

/// Hattı takibe alma penceresi: yön seç, durağa dokun; sana en yakın durak önerilir; takibe alınca bildirim ön ayarı sunulur.
struct FollowSheet: View {
    let hat: Hat
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var route: LineRoute?
    @State private var direction = "G"
    @State private var query = ""
    @State private var justFollowed: Favorite?
    @State private var failed = false

    private var stops: [RouteStop] {
        let all = route?.stops[direction] ?? []
        let needle = fold(query)
        return needle.isEmpty ? all : all.filter { fold($0.name).contains(needle) }
    }
    /// Seçili yönde konuma en yakın durak (en çok 1,5 km).
    private var nearest: RouteStop? {
        guard let here = model.location?.coordinate, let all = route?.stops[direction] else { return nil }
        return all.map { ($0, here.distance(to: $0.coordinate)) }.filter { $0.1 <= 1500 }.min { $0.1 < $1.1 }?.0
    }
    private func distance(_ stop: RouteStop) -> String? { model.location.map { let m = Int($0.coordinate.distance(to: stop.coordinate)); return m < 1000 ? "\(m) m" : String(format: "%.1f km", Double(m) / 1000) } }
    private func favorite(_ stop: RouteStop) -> Favorite? { model.favorites.first { $0.line == hat.code && $0.stopCode == stop.code } }
    private func toggle(_ stop: RouteStop) {
        let durak = model.stop(code: stop.code) ?? Durak(code: stop.code, name: stop.name, lat: stop.lat, lon: stop.lon)
        let was = model.isFavorite(line: hat.code, stop: stop.code)
        withAnimation(.spring(duration: 0.4)) { model.toggleFavorite(line: hat.code, stop: durak) }
        Task { await model.refreshFavorites() }
        justFollowed = was ? nil : favorite(stop) ?? Favorite(line: hat.code, stopCode: stop.code, stopName: stop.name, lat: stop.lat, lon: stop.lon)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) { LineBadge(code: hat.code); Text(hat.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                    if let route, route.directions.count > 1 {
                        Picker("Yön", selection: $direction.animation(.spring(duration: 0.4))) { ForEach(route.directions, id: \.self) { Text("→ " + route.destination($0)).tag($0) } }.pickerStyle(.segmented)
                    }
                }
                Section {
                    Button { withAnimation(.spring) { model.toggleFollow(line: hat.code) } } label: {
                        Label(model.isFollowing(line: hat.code) ? "Tüm hat takipte (bırakmak için dokun)" : "Tüm hattı takip et (durak seçmeden)", systemImage: model.isFollowing(line: hat.code) ? "checkmark.circle.fill" : "bus.doubledecker.fill")
                            .font(.subheadline.weight(.bold)).foregroundStyle(model.isFollowing(line: hat.code) ? .green : Theme.accent)
                    }
                } footer: { Text("Hat takibi: yoldaki araç sayısı ve sana en yakın durağa varış Takip sekmesinde görünür. Aşağıdan belirli bir durağı da takibe alabilirsin.") }
                if let justFollowed {
                    Section {
                        Label("\(justFollowed.stopName) takibe alındı", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.subheadline.weight(.semibold))
                        HStack {
                            Text("Bildirim:").font(.footnote).foregroundStyle(.secondary)
                            ForEach([("Sabah", AlertRule.morning), ("Akşam", AlertRule.evening)], id: \.0) { item in
                                Button(item.0) { model.setRule(item.1, for: justFollowed) }.buttonStyle(.bordered).controlSize(.small)
                            }
                            Button("Yok") { model.setRule(nil, for: justFollowed) }.buttonStyle(.bordered).controlSize(.small).tint(.gray)
                        }
                        if model.rule(for: justFollowed)?.enabled == true { Label("Bildirim açık (ayrıntı: Takip › karta uzun bas)", systemImage: "bell.fill").font(.caption).foregroundStyle(.orange) }
                    }.transition(.move(edge: .top).combined(with: .opacity))
                }
                if let nearest, query.isEmpty {
                    Section("Sana en yakın durak") { row(nearest, highlight: true) }
                }
                Section(route == nil ? (failed ? "Duraklar yüklenemedi" : "Duraklar yükleniyor…") : "Duraklar (\(stops.count))") {
                    ForEach(stops) { row($0, highlight: false) }
                }
            }
            .searchable(text: $query, prompt: "Durak ara")
            .navigationTitle("Takip et").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Bitti") { dismiss() }.bold() } }
            .task {
                model.requestLocation()
                route = await model.route(hat.code); failed = route == nil
                if let first = route?.directions.first, !(route?.directions.contains(direction) ?? true) { direction = first }
            }
            .sensoryFeedback(.success, trigger: model.favorites.count)
        }
        .presentationDetents([.large])
    }

    private func row(_ stop: RouteStop, highlight: Bool) -> some View {
        let followed = model.isFavorite(line: hat.code, stop: stop.code)
        return Button { toggle(stop) } label: {
            HStack(spacing: 12) {
                Text("\(stop.seq)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
                VStack(alignment: .leading, spacing: 1) {
                    Text(stop.name).font(highlight ? .headline : .subheadline).foregroundStyle(.primary)
                    if let d = distance(stop) { Text(d + " uzakta").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Label(followed ? "Takipte" : "Takip et", systemImage: followed ? "checkmark.circle.fill" : "plus.circle")
                    .font(.footnote.weight(.semibold)).labelStyle(.titleAndIcon).foregroundStyle(followed ? .green : Theme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 6).background((followed ? Color.green : Theme.accent).opacity(0.14), in: .capsule)
            }
        }.buttonStyle(.plain)
    }
}
