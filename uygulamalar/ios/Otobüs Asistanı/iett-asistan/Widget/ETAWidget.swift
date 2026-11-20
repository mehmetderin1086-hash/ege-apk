import SwiftUI
import WidgetKit

struct ETAEntry: TimelineEntry {
    let date: Date
    let rows: [FavoriteSnapshot]
}

struct ETAProvider: TimelineProvider {
    func placeholder(in context: Context) -> ETAEntry {
        ETAEntry(date: .now, rows: [.init(favorite: .init(line: "500T", stopCode: 1, stopName: "4.LEVENT METRO", lat: 41, lon: 29), eta: .init(id: "C-1", minutes: 4, distance: 900, state: .approaching, speedKmh: 18, stopsLeft: 3))])
    }
    func getSnapshot(in context: Context, completion: @escaping (ETAEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        Task { completion(ETAEntry(date: .now, rows: await FavoriteSnapshot.load(Array(SharedStore.loadFavorites().prefix(3))))) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ETAEntry>) -> Void) {
        Task {
            let rows = await FavoriteSnapshot.load(Array(SharedStore.loadFavorites().prefix(4)))
            // İETT kotası (saatte 100) uygulamayla ortaktır: widget 10 dk'da bir ister; kota doluysa eski veriyle kalır.
            completion(Timeline(entries: [ETAEntry(date: .now, rows: rows)], policy: .after(Date().addingTimeInterval(600))))
        }
    }
}

struct ETARow: View {
    let row: FavoriteSnapshot
    var compact = false
    var body: some View {
        Link(destination: row.favorite.deepLink) { content }
    }
    private var content: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(row.favorite.line).font(.headline.monospaced())
                Text(row.favorite.stopName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(row.eta.map(minutesText) ?? "—").font(compact ? .headline : .title3.bold()).foregroundStyle(color)
        }
    }
    private var color: Color { row.eta == nil ? .secondary : row.eta!.state == .estimated ? .orange : .green }
    private func minutesText(_ eta: BusETA) -> String {
        switch eta.state {
        case .atStop: "Durakta"
        default: eta.wholeMinutes <= 0 ? "Şimdi" : (eta.state == .estimated ? "~" : "") + "\(eta.wholeMinutes) dk"
        }
    }
}

struct ETAWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: ETAEntry
    var body: some View {
        Group {
            if entry.rows.isEmpty {
                VStack(spacing: 4) { Image(systemName: "bus.fill"); Text("Uygulamada bir durak takibe al").font(.caption).multilineTextAlignment(.center) }
            } else {
                switch family {
                case .systemSmall:
                    let row = entry.rows[0]
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.favorite.line).font(.headline.monospaced())
                        Text(row.favorite.stopName).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        Spacer(minLength: 0)
                        if let eta = row.eta {
                            Text(eta.state == .atStop ? "Durakta" : eta.wholeMinutes <= 0 ? "Şimdi" : "\(eta.wholeMinutes)").font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(.green).minimumScaleFactor(0.5)
                            if eta.state != .atStop, eta.wholeMinutes > 0 { Text(eta.stopsLeft.flatMap { $0 > 0 ? "dk · \($0) durak" : nil } ?? "dk").font(.caption).foregroundStyle(.secondary) }
                        } else { Text("Araç yok").font(.title3).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).widgetURL(row.favorite.deepLink)
                case .accessoryRectangular:
                    VStack(alignment: .leading) { ForEach(entry.rows.prefix(2)) { ETARow(row: $0, compact: true) } }
                default:
                    VStack(spacing: 6) { ForEach(entry.rows.prefix(4)) { ETARow(row: $0) } ; Spacer(minLength: 0); Text(entry.date, style: .time).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing) }
                }
            }
        }
        .containerBackground(for: .widget) {
            if family == .accessoryRectangular { Color.clear }
            else { LinearGradient(colors: [Color(red: 0.04, green: 0.12, blue: 0.32), Color(red: 0.10, green: 0.40, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing) }
        }
        .environment(\.colorScheme, family == .accessoryRectangular ? colorScheme : .dark)
    }
}

@main struct ETAWidgetBundle: WidgetBundle {
    var body: some Widget { ETAWidget() }
}

struct ETAWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ETAWidget", provider: ETAProvider()) { ETAWidgetView(entry: $0) }
            .configurationDisplayName("Otobüs dakikası")
            .description("Takip ettiğin duraklara otobüsün kaç dakikada geleceğini gösterir.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
