import SwiftUI

/// #37: kütüphane filtre çipleri.
nonisolated enum LibraryFilter: String, CaseIterable, Identifiable, Sendable {
    case all, inProgress, unplayed, failed, review
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Tümü"
        case .inProgress: "Yarım"
        case .unplayed: "Dinlenmemiş"
        case .failed: "Başarısız"
        case .review: "Tekrar"
        }
    }
}

/// #37: sıralama seçenekleri.
nonisolated enum LibrarySort: String, CaseIterable, Identifiable, Sendable {
    case newest, oldest, recentlyPlayed, title, longest
    static let key = "library.sort"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .newest: "En yeni"
        case .oldest: "En eski"
        case .recentlyPlayed: "Son dinlenen"
        case .title: "Ada göre"
        case .longest: "En uzun"
        }
    }
}

/// Filtre ve sıralama için bölümün anlık görüntüsü (test edilebilir, SwiftData'sız).
nonisolated struct EpisodeListItem: Hashable, Sendable {
    var id: UUID
    var title: String
    var createdAt: Date
    var lastPlayedAt: Date?
    var duration: Double
    var lastPosition: Double
    var isFinished: Bool
    var statusRaw: String
    /// Bu bölümden tekrar zamanı gelmiş kart var.
    var hasDueCards: Bool = false
    var derivedKind: String?
    var parentID: UUID?
    var seriesID: UUID?
    var seriesIndex: Int = 0
}

extension EpisodeListItem {
    init(_ e: Episode, dueEpisodes: Set<UUID> = []) {
        self.init(id: e.id, title: e.title, createdAt: e.createdAt, lastPlayedAt: e.lastPlayedAt, duration: e.duration,
                  lastPosition: e.lastPosition, isFinished: e.isFinished, statusRaw: e.statusRaw, hasDueCards: dueEpisodes.contains(e.id),
                  derivedKind: e.derivedKind, parentID: e.parentEpisodeID, seriesID: e.seriesID, seriesIndex: e.seriesIndex)
    }
}

nonisolated enum LibraryQuery {
    /// Tekrar türleri (türev rozetinde de kullanılır).
    static let reviewKinds: Set<String> = ["recap", "gap", "weekly"]

    static func matches(_ i: EpisodeListItem, _ filter: LibraryFilter) -> Bool {
        let ready = i.statusRaw == "ready"
        switch filter {
        case .all: return true
        case .inProgress: return ready && !i.isFinished && i.lastPosition > 5
        case .unplayed: return ready && !i.isFinished && i.lastPosition <= 5
        case .failed: return i.statusRaw == "failed"
        case .review: return i.hasDueCards || reviewKinds.contains(i.derivedKind ?? "")
        }
    }

    static func sorted(_ items: [EpisodeListItem], by sort: LibrarySort) -> [EpisodeListItem] {
        switch sort {
        case .newest: items.sorted { $0.createdAt > $1.createdAt }
        case .oldest: items.sorted { $0.createdAt < $1.createdAt }
        case .recentlyPlayed: items.sorted { ($0.lastPlayedAt ?? .distantPast, $0.createdAt) > ($1.lastPlayedAt ?? .distantPast, $1.createdAt) }
        case .title: items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .longest: items.sorted { $0.duration > $1.duration }
        }
    }

    /// Filtre + sıralama → kimlik sırası.
    static func ids(_ items: [EpisodeListItem], filter: LibraryFilter, sort: LibrarySort) -> [UUID] {
        sorted(items.filter { matches($0, filter) }, by: sort).map(\.id)
    }
}

/// #37: başlık, kaynak adı ve transkriptte arama (katlama `LibrarySearch.fold` ile aynı: ı ≈ i, aksan yok).
nonisolated enum EpisodeSearch {
    struct Doc: Sendable {
        var id: UUID
        var title: String
        var sources: [String]
        var timelineData: Data?
    }

    enum Field: String, Sendable { case title, source, transcript }

    struct Hit: Hashable, Sendable, Identifiable {
        var episodeID: UUID
        var title: String
        var field: Field
        /// Transkript eşleşmesinde turun başlangıcı (sn).
        var time: Double?
        var snippet: String
        var id: String { "\(episodeID)|\(field.rawValue)|\(time ?? -1)|\(snippet.hashValue)" }
    }

    static let maxPerEpisode = 3
    static let maxHits = 80

    /// Dizinde tutulan transkript turu: metin bir kez katlanır.
    struct IndexedTurn: Sendable {
        var start: Double
        var text: String
        var folded: String
    }

    /// Aramada transkript dışındaki alanlar (ana aktörde ucuzca toplanır).
    struct Meta: Sendable {
        var id: UUID
        var title: String
        var sources: [String]
    }

    static func indexTurns(_ timelineData: Data?) -> [IndexedTurn] {
        guard let timelineData, let timeline = try? JSONDecoder().decode(Timeline.self, from: timelineData) else { return [] }
        return timeline.turns.map { IndexedTurn(start: $0.start, text: $0.text, folded: LibrarySearch.fold($0.text)) }
    }

    static func search(_ query: String, in docs: [Doc]) -> [Hit] {
        let turns = Dictionary(docs.map { ($0.id, indexTurns($0.timelineData)) }, uniquingKeysWith: { first, _ in first })
        return search(query, metas: docs.map { Meta(id: $0.id, title: $0.title, sources: $0.sources) }, turns: turns)
    }

    static func search(_ query: String, metas: [Meta], turns: [UUID: [IndexedTurn]]) -> [Hit] {
        let tokens = LibrarySearch.tokens(query)
        guard !tokens.isEmpty else { return [] }
        var hits: [Hit] = []
        for doc in metas {
            var mine: [Hit] = []
            if LibrarySearch.matches(text: doc.title, tokens: tokens) {
                mine.append(Hit(episodeID: doc.id, title: doc.title, field: .title, time: nil, snippet: doc.title))
            }
            if let source = doc.sources.first(where: { LibrarySearch.matches(text: $0, tokens: tokens) }) {
                mine.append(Hit(episodeID: doc.id, title: doc.title, field: .source, time: nil, snippet: source))
            }
            for turn in turns[doc.id] ?? [] where mine.count < maxPerEpisode {
                guard tokens.allSatisfy({ turn.folded.contains($0) }) else { continue }
                mine.append(Hit(episodeID: doc.id, title: doc.title, field: .transcript, time: turn.start,
                                snippet: LibrarySearch.snippet(text: turn.text, folded: turn.folded, tokens: tokens, radius: 50)))
            }
            hits += mine.prefix(maxPerEpisode)
            if hits.count >= maxHits { break }
        }
        return Array(hits.prefix(maxHits))
    }
}

/// #37: katlanmış transkript dizini; çözme, katlama ve tarama ana iş parçacığı dışında yapılır.
actor EpisodeSearchStore {
    private var turns: [UUID: [EpisodeSearch.IndexedTurn]] = [:]

    /// `changed`: yeni ya da sesi değişen bölümlerin ham çizelgesi (yeniden dizinlenir). Listede olmayan bölüm dizinden düşer.
    func search(_ query: String, metas: [EpisodeSearch.Meta], changed: [(id: UUID, data: Data?)]) -> [EpisodeSearch.Hit] {
        for item in changed { turns[item.id] = EpisodeSearch.indexTurns(item.data) }
        let live = Set(metas.map(\.id))
        if turns.count > live.count || turns.keys.contains(where: { !live.contains($0) }) {
            turns = turns.filter { live.contains($0.key) }
        }
        return EpisodeSearch.search(query, metas: metas, turns: turns)
    }

    var indexedEpisodes: Int { turns.count }
}

/// Kütüphane araması için önbellek: transkript (`timelineData`) yalnız yeni ya da değişen bölümde ana aktörde okunur
/// (sürüm: durum, ses sürümü, süre, sahne sayısı); sonraki aramalar yalnız başlık ve kaynak adlarını toplar.
final class EpisodeSearchIndex {
    struct Entry {
        var meta: EpisodeSearch.Meta
        var version: Int
        var timelineData: () -> Data?
    }

    private var versions: [UUID: Int] = [:]
    let store = EpisodeSearchStore()
    /// Son aramada transkripti okunan bölüm sayısı.
    private(set) var lastReads = 0

    func search(_ query: String, entries: [Entry]) async -> [EpisodeSearch.Hit] {
        var changed: [(id: UUID, data: Data?)] = []
        var live: [UUID: Int] = [:]
        for entry in entries {
            live[entry.meta.id] = entry.version
            if versions[entry.meta.id] != entry.version { changed.append((entry.meta.id, entry.timelineData())) }
        }
        // Görev iptal edilse de başlayan aktör çağrısı değişiklikleri işler; sürümler şimdi güncellenebilir.
        versions = live
        lastReads = changed.count
        return await store.search(query, metas: entries.map(\.meta), changed: changed)
    }

    func search(_ query: String, episodes: [Episode]) async -> [EpisodeSearch.Hit] {
        await search(query, entries: episodes.map { e in
            Entry(meta: EpisodeSearch.Meta(id: e.id, title: e.title, sources: e.sourceNames),
                  version: Self.version(status: e.statusRaw, audioRevision: e.audioRevision, duration: e.duration, scenesDone: e.scenesDone),
                  timelineData: { e.timelineData })
        })
    }

    static func version(status: String, audioRevision: Int, duration: Double, scenesDone: Int) -> Int {
        var h = Hasher()
        h.combine(status)
        h.combine(audioRevision)
        h.combine(duration)
        h.combine(scenesDone)
        return h.finalize()
    }
}

// MARK: - Görünümler

/// Filtre çipleri (dar ekranda yatay kaydırılır). Sıralama `LibrarySortMenu` ile başlık satırındadır.
struct LibraryFilterBar: View {
    @Binding var filter: LibraryFilter
    var counts: [LibraryFilter: Int]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryFilter.allCases) { f in
                    let n = counts[f] ?? 0
                    if f == .all || n > 0 || filter == f {
                        Button {
                            filter = f
                        } label: {
                            Text(f == .all ? f.title : "\(f.title) \(n)")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 36)
                                .background(filter == f ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(.background.secondary), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .accessibilityAddTraits(filter == f ? .isSelected : [])
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// Sıralama menüsü: çip kaydırıcısının dışında, her genişlikte görünür. Etiket sığmazsa yalnız simge kalır.
struct LibrarySortMenu: View {
    @Binding var sort: LibrarySort

    var body: some View {
        Menu {
            Picker("Sıralama", selection: $sort) {
                ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
            }
        } label: {
            ViewThatFits(in: .horizontal) {
                Label(sort.title, systemImage: "arrow.up.arrow.down").lineLimit(1)
                Image(systemName: "arrow.up.arrow.down")
            }
            .font(.subheadline)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Sıralama: \(sort.title)")
    }
}

/// Arama sonuçları: dokununca bölüm (transkriptte eşleşmişse o andan) açılır.
struct EpisodeSearchResults: View {
    var hits: [EpisodeSearch.Hit]
    var searching: Bool
    var open: (EpisodeSearch.Hit) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if searching { ProgressView().frame(maxWidth: .infinity) }
            if hits.isEmpty, !searching {
                Text("Eşleşme yok.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(hits) { hit in
                Button { open(hit) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: hit.field == .transcript ? "text.quote" : hit.field == .source ? "doc" : "waveform")
                            .foregroundStyle(.tint)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hit.title).font(.subheadline.bold()).lineLimit(2)
                            if hit.field != .title {
                                Text(hit.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                            if let time = hit.time {
                                Text(time.clockText).font(.caption2.monospacedDigit()).foregroundStyle(.tint)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
