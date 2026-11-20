import SwiftUI

/// #39/#40: kütüphane satırları. Seri tek kartta toplanır; türev bölümler (tekrar, eksik kapatma, videodan, "Farkı ne?")
/// ana bölümün altına katlanır. Ana bölüm listede yoksa türev kendi satırında görünür.
nonisolated enum LibraryRow: Hashable, Sendable, Identifiable {
    case episode(UUID, children: [UUID])
    case series(UUID)

    var id: String {
        switch self {
        case let .episode(id, _): "e-\(id)"
        case let .series(id): "s-\(id)"
        }
    }
}

nonisolated enum LibraryGrouping {
    /// `ordered`: filtre ve sıralamadan geçmiş liste. `collapseSeries`: seri bölümleri tek kart olur (seri ilk göründüğü yerde).
    /// Türev yalnız kendi `.episode` satırı olacak bir atanın altına katlanır: seri kartına dönen ana bölümün türevi
    /// (ör. seri bölümünün "Hızlı tekrar"ı) kendi satırında kalır; zincir (türevin türevi) en üstteki satıra katlanır.
    static func rows(_ ordered: [EpisodeListItem], collapseSeries: Bool) -> [LibraryRow] {
        let byID = Dictionary(ordered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func inSeriesCard(_ item: EpisodeListItem) -> Bool { collapseSeries && item.seriesID != nil }
        var hostCache: [UUID: UUID?] = [:]
        /// Katlanacağı satır (yoksa nil = kendi satırı ya da seri kartı).
        func host(of item: EpisodeListItem, visiting: Set<UUID> = []) -> UUID? {
            if let cached = hostCache[item.id] { return cached }
            var result: UUID?
            if !inSeriesCard(item), let parentID = item.parentID, parentID != item.id, !visiting.contains(parentID),
               let parent = byID[parentID], !inSeriesCard(parent) {
                result = host(of: parent, visiting: visiting.union([item.id])) ?? parentID
            }
            hostCache[item.id] = result
            return result
        }
        var children: [UUID: [UUID]] = [:]
        var folded = Set<UUID>()
        for item in ordered {
            guard let target = host(of: item) else { continue }
            children[target, default: []].append(item.id)
            folded.insert(item.id)
        }
        var seenSeries = Set<UUID>()
        var rows: [LibraryRow] = []
        for item in ordered where !folded.contains(item.id) {
            if collapseSeries, let series = item.seriesID {
                if seenSeries.insert(series).inserted { rows.append(.series(series)) }
                continue
            }
            rows.append(.episode(item.id, children: children[item.id] ?? []))
        }
        return rows
    }
}

nonisolated enum DerivedKind {
    static func title(_ kind: String?) -> String? {
        switch kind {
        case "recap": "Tekrar"
        case "gap": "Eksik kapatma"
        case "weekly": "Haftalık tekrar"
        case "video": "Videodan"
        case "discriminate": "Farkı ne?"
        default: nil
        }
    }

    static func symbol(_ kind: String?) -> String {
        switch kind {
        case "video": "play.rectangle"
        case "discriminate": "arrow.left.arrow.right"
        case "gap": "puzzlepiece"
        default: "arrow.triangle.2.circlepath"
        }
    }
}

/// Türev rozeti ("Tekrar", "Videodan" …).
struct DerivedBadge: View {
    var kind: String?

    var body: some View {
        if let title = DerivedKind.title(kind) {
            Label(title, systemImage: DerivedKind.symbol(kind))
                .font(.caption2.bold())
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
                .foregroundStyle(.tint)
                .lineLimit(1)
        }
    }
}

/// Ana bölümün altına katlanmış türevler.
struct DerivedChildren<Row: View>: View {
    var ids: [UUID]
    @ViewBuilder var row: (UUID) -> Row
    @State private var expanded = false

    var body: some View {
        if !ids.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    Label(expanded ? "Türevleri gizle" : "\(ids.count) türev bölüm", systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .padding(.leading, 18)
                if expanded {
                    ForEach(ids, id: \.self) { id in
                        row(id).padding(.leading, 18)
                    }
                }
            }
        }
    }
}
