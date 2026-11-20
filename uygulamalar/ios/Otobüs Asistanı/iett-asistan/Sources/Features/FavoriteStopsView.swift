import SwiftUI

/// Favori (yıldızlı) duraklar: hat bağımsız; her durakta uğrayan hatlar, panoda gösterme ve kaldırma.
struct FavoriteStopsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("board.stop") private var boardStop = 0
    var body: some View {
        List {
            if model.favoriteStopList.isEmpty {
                ContentUnavailableView("Favori durağın yok", systemImage: "star", description: Text("Bir durak ekranındaki ★ düğmesine dokun. Favori duraklar asistanın hazır sorularında, panoda ve widget'ta kullanılır."))
                    .listRowBackground(Color.clear)
            }
            ForEach(Array(model.favoriteStopList.enumerated()), id: \.element.id) { index, stop in
                NavigationLink(value: Route.stop(code: stop.code)) { FavoriteStopRow(stop: stop, isBoard: boardStop == stop.code) }
                    .swipeActions(edge: .trailing) { Button("Kaldır", systemImage: "star.slash", role: .destructive) { withAnimation(.spring) { model.toggleFavoriteStop(stop.code) } } }
                    .swipeActions(edge: .leading) { Button("Panoda göster", systemImage: "display") { boardStop = stop.code }.tint(.indigo) }
                    .cascadeIn(index)
            }
            if !model.favoriteStopList.isEmpty { Text("Sağa kaydır: panoda göster · sola kaydır: kaldır").font(.caption).foregroundStyle(.secondary).listRowBackground(Color.clear) }
        }
        .scrollContentBackground(.hidden).background { AuroraBackground() }
        .navigationTitle("Favori duraklar").navigationBarTitleDisplayMode(.inline)
    }
}

struct FavoriteStopRow: View {
    let stop: Durak
    var isBoard = false
    @Environment(AppModel.self) private var model
    @State private var lines: [String] = []
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill").foregroundStyle(.yellow).font(.title3)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(stop.name).font(.title3.weight(.bold)).lineLimit(2)
                    if isBoard { Label("Pano", systemImage: "display").labelStyle(.iconOnly).font(.caption).foregroundStyle(.indigo) }
                }
                if !stop.district.isEmpty { Text(stop.district).font(.subheadline.weight(.medium)).foregroundStyle(.secondary) }
                DirectionTag(text: stop.direction)
                if !lines.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 5) { ForEach(lines.prefix(10), id: \.self) { LineBadge(code: $0).scaleEffect(0.8, anchor: .leading) } } }.frame(height: 30)
                }
            }
        }
        .task {
            var seen = Set<String>()
            lines = await model.linesAtStop(stop.code).compactMap { seen.insert($0.line).inserted ? $0.line : nil }
        }
    }
}
