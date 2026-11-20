import SwiftUI

struct SyncBanner: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if model.syncTotal > 0, model.syncDone < model.syncTotal {
            VStack(alignment: .leading, spacing: 4) {
                Label("Hat güzergâhları indiriliyor (bir kereye mahsus)", systemImage: "arrow.down.circle").font(.footnote.bold())
                ProgressView(value: Double(model.syncDone), total: Double(max(1, model.syncTotal)))
                Text("\(model.syncDone)/\(model.syncTotal) hat · bitince durakta tüm hatlar canlı listelenir").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct StopArrival: Identifiable, Hashable {
    let line: String, direction: String, destination: String, eta: BusETA?
    var id: String { line + direction }
}

/// Durağa uğrayan bütün hatlar ve her birinin canlı varış süresi (hat veritabanı indirildikten sonra).
struct StopDetailView: View {
    let stop: Durak
    @Environment(AppModel.self) private var model
    @State private var arrivals: [StopArrival] = []
    @State private var passing: [PassingEntry] = []
    @State private var loaded = false
    @State private var query = ""
    private var found: [Hat] {
        let needle = fold(query); guard !needle.isEmpty else { return [] }
        return model.lines.filter { fold($0.code).hasPrefix(needle) || fold($0.name).contains(needle) }.prefix(20).map { $0 }
    }
    var body: some View {
        List {
            Section { SyncBanner() }.listRowBackground(Color.clear)
            Section { StopDirectionPanel(stop: stop) }.listRowBackground(Color.clear).listRowInsets(.init(top: 6, leading: 0, bottom: 6, trailing: 0))
            Section("Durak bilgisi") {
                Text(stop.name).font(.headline)
                info("Durak kodu", String(stop.code), "number")
                info("İlçe", stop.district, "building.2")
                info("Yön", stop.direction, "arrow.triangle.turn.up.right.diamond")
                info("Tip", stop.kind, "signpost.right")
                info("Akıllı durak", stop.kind.isEmpty && stop.physical.isEmpty ? "" : (stop.smart ? "Var" : "Yok"), "display")
                info("Fiziki durum", stop.physical.capitalized, "house")
                info("Engelli kullanımı", stop.accessibility.isEmpty ? "" : (stop.accessibility.lowercased().contains("uygun degil") || stop.accessibility.lowercased().contains("uygun değil") ? "Uygun değil" : stop.accessibility.capitalized), "figure.roll")
                if let here = model.location?.coordinate { info("Size uzaklık", "\(Int(here.distance(to: stop.coordinate))) m", "location") }
                info("Konum", String(format: "%.5f, %.5f", stop.lat, stop.lon), "mappin")
            }
            Section { NoteCard(key: "stop:\(stop.code)", title: "Bu durak için notum") }.listRowBackground(Color.clear).listRowInsets(.init())
            Section("Sefer saatleri · bu duraktaki tahmini geçişler") {
                if passing.isEmpty { Text(loaded ? "Hat bilgisi henüz yok." : "Yükleniyor…").foregroundStyle(.secondary) }
                ForEach(passing, id: \.id) { entry in StopLineTimes(entry: entry, stop: stop) }
            }
            Section("Durağa uğrayan hatlar · canlı") {
                if arrivals.isEmpty { Text(loaded ? "Hat bilgisi henüz yok; indirme sürüyorsa biraz bekle ya da aşağıdan hat ekle." : "Yükleniyor…").foregroundStyle(.secondary) }
                ForEach(arrivals) { arrival in
                    NavigationLink(value: Route.line(code: arrival.line, stop: stop.code)) {
                        HStack(spacing: 12) {
                            Text(arrival.line).font(.headline.monospaced()).frame(width: 62, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("→ " + arrival.destination).font(.subheadline).lineLimit(1)
                                if let left = arrival.eta?.stopsLeft, left > 0 { Text("\(left) durak kaldı").font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(arrival.eta?.text ?? "—").font(.title3.bold()).foregroundStyle(arrival.eta == nil ? Color.secondary : Color.green).contentTransition(.numericText())
                        }
                    }
                    .swipeActions { Button("Takip et", systemImage: "plus") { model.toggleFavorite(line: arrival.line, stop: stop); Task { await model.refreshFavorites() } }.tint(.blue) }
                }
            }
            Section("Takip edilen hatlar") {
                let mine = model.favorites.filter { $0.stopCode == stop.code }
                if mine.isEmpty { Text("Hat satırını sola kaydırıp “Takip et”e dokun.").foregroundStyle(.secondary) }
                ForEach(mine) { favorite in
                    HStack { Text(favorite.line).font(.headline); Spacer(); ETABadge(eta: model.favoriteETAs[favorite.id]?.first).scaleEffect(0.8) }
                        .swipeActions { Button("Sil", role: .destructive) { model.remove(favorite) } }
                }
            }
            Section("Hat ekle (elle)") {
                TextField("Hat kodu (örn. 14M)", text: $query).textInputAutocapitalization(.characters).autocorrectionDisabled()
                ForEach(found) { hat in
                    Button { model.toggleFavorite(line: hat.code, stop: stop); Task { await model.refreshFavorites() } } label: {
                        HStack { Text(hat.code).font(.headline.monospaced()); Text(hat.name).font(.caption).foregroundStyle(.secondary).lineLimit(1); Spacer()
                            if model.isFavorite(line: hat.code, stop: stop.code) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) } }
                    }
                }
            }
        }
        .navigationTitle("Durak")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareIconButton(label: "Durağı paylaş") { ShareBuilder.stopArrivals(stop, rows: arrivals.map { ($0.line, $0.destination, ShareBuilder.etaText($0.eta)) }) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { withAnimation(.spring) { model.toggleFavoriteStop(stop.code) } } label: {
                    Image(systemName: model.isFavoriteStop(stop.code) ? "star.fill" : "star").foregroundStyle(model.isFavoriteStop(stop.code) ? Color.yellow : Color.accentColor)
                        .symbolEffect(.bounce, value: model.isFavoriteStop(stop.code))
                }
                .accessibilityLabel(model.isFavoriteStop(stop.code) ? "Favori duraktan çıkar" : "Favori durak yap")
                .sensoryFeedback(.success, trigger: model.isFavoriteStop(stop.code))
            }
        }
        .task(id: model.routeIndexReady) {
            model.noteVisit(stop: stop.code)
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    @ViewBuilder private func info(_ title: String, _ value: String, _ icon: String) -> some View {
        if !value.isEmpty { LabeledContent { Text(value).multilineTextAlignment(.trailing) } label: { Label(title, systemImage: icon).foregroundStyle(.secondary) }.font(.subheadline) }
    }

    private func load() async {
        let entries = await model.linesAtStop(stop.code)
        var seen = Set<String>(), unique: [RouteStore.Entry] = []
        for entry in entries where seen.insert(entry.line + entry.direction).inserted { unique.append(entry) }
        passing = unique.prefix(30).map { PassingEntry(line: $0.line, direction: $0.direction) }
        let wanted = Array(unique.prefix(40))
        var busesByLine: [String: [Bus]] = [:]
        await withTaskGroup(of: (String, [Bus]).self) { group in
            for line in Set(wanted.map(\.line)) { group.addTask { (line, await model.buses(line: line)) } }
            for await (line, buses) in group { busesByLine[line] = buses }
        }
        var list: [StopArrival] = []
        for entry in wanted {
            let route = await model.route(entry.line)
            let all = route.map { RouteETAEngine.etas(buses: (busesByLine[entry.line] ?? []).filter { $0.direction == entry.direction }, route: $0, stopCode: stop.code, hat: model.line(entry.line), tracker: model.tracker) } ?? []
            list.append(.init(line: entry.line, direction: entry.direction, destination: route?.destination(entry.direction) ?? "", eta: all.first))
        }
        arrivals = list.sorted { ($0.eta?.minutes ?? .infinity, $0.line) < ($1.eta?.minutes ?? .infinity, $1.line) }
        loaded = true
    }
}

struct PassingEntry: Identifiable, Hashable {
    let line: String, direction: String
    var id: String { line + "|" + direction }
}

/// Bir hattın bu duraktan geçiş saatleri: sıradaki tahmini geçişler; açılınca bugünkü hepsi. Sefer saatleri tembel yüklenir.
struct StopLineTimes: View {
    let entry: PassingEntry
    let stop: Durak
    @Environment(AppModel.self) private var model
    @State private var trips: [PlannedTrip] = []
    @State private var route: LineRoute?
    @State private var loaded = false
    @State private var open = false

    private var times: [Int] { Timetable.times(trips, dayType: IETTDates.dayType(), direction: entry.direction) }
    private var entries: [Timetable.Entry] { Timetable.entries(trips, dayType: IETTDates.dayType(), direction: entry.direction) }
    private var offset: Int {
        guard let route, let stops = route.stops[entry.direction], let index = route.stopIndex(code: stop.code, direction: entry.direction), let hat = model.line(entry.line) else { return 0 }
        let geometry = RouteGeometry(stops: stops)
        return Timetable.offsetMinutes(tripMinutes: hat.tripMinutes, stopAlong: geometry.cumulative[index], routeLength: geometry.length) ?? 0
    }
    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            let now = Timetable.nowMinutes()
            if entries.isEmpty { Text(loaded ? "Bugün için sefer verisi yok." : "Yükleniyor…").font(.caption).foregroundStyle(.secondary) }
            else {
                FlowRow(spacing: 6) {
                    ForEach(entries) { item in
                        let t = item.minutes + offset
                        HStack(spacing: 2) {
                            Text(Timetable.format(t)).font(.caption.monospacedDigit())
                            if let m = item.markerText { Text(m).font(.system(size: 8, weight: .bold)) }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.color(for: entry.line).opacity(t >= now ? 0.2 : 0.06), in: .capsule)
                        .foregroundStyle(item.isOHO ? Color.red.opacity(t >= now ? 1 : 0.4) : (t >= now ? Color.primary : Color.secondary.opacity(0.5)))
                    }
                }
                if entries.contains(where: \.isOHO) { Text("Kırmızı: ÖHO · siyah: İETT · (-1) gibi işaretler farklı güzergâhtan çıkan seferler").font(.caption2).foregroundStyle(.secondary) }
                if let hat = model.line(entry.line) {
                    NavigationLink(value: Route.timetable(code: entry.line, direction: entry.direction, stop: stop.code)) { Label("Tam sefer saatleri", systemImage: "clock") }.font(.footnote.weight(.semibold))
                }
            }
        } label: {
            HStack(spacing: 10) {
                LineBadge(code: entry.line)
                VStack(alignment: .leading, spacing: 1) {
                    Text("→ " + (route?.destination(entry.direction) ?? entry.direction)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    let next = Timetable.upcoming(times, offset: offset, nowMinutes: Timetable.nowMinutes(), count: 3)
                    Text(next.isEmpty ? (loaded ? "Bugün sefer kalmadı" : "…") : next.map(Timetable.format).joined(separator: " · ")).font(.subheadline.monospacedDigit().weight(.semibold))
                }
            }
        }
        .task { guard !loaded else { return }; async let t = model.timetable(line: entry.line), r = model.route(entry.line); (trips, route) = await (t, r); loaded = true }
    }
}
