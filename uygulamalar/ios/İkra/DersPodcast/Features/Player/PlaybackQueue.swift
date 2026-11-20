import SwiftData
import SwiftUI

/// #41: "Sıradakiler" kuyruğunun saklanması (`player.queue`, JSON `[PlaybackQueueItem]`).
nonisolated enum PlaybackQueue {
    static let key = "player.queue"
    /// Kuyruk sınırı (eski öğeler düşmez; fazlası eklenmez).
    static let limit = 50

    static func decode(_ data: Data?) -> [PlaybackQueueItem] {
        data.flatMap { try? JSONDecoder().decode([PlaybackQueueItem].self, from: $0) } ?? []
    }

    static func encode(_ items: [PlaybackQueueItem]) -> Data? {
        items.isEmpty ? nil : try? JSONEncoder().encode(items)
    }

    static func load(_ defaults: UserDefaults = .standard) -> [PlaybackQueueItem] {
        decode(defaults.data(forKey: key))
    }

    static func save(_ items: [PlaybackQueueItem], _ defaults: UserDefaults = .standard) {
        if let data = encode(items) { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    /// Aynı öğe ikinci kez eklenmez; sınır aşılmaz.
    static func appending(_ item: PlaybackQueueItem, to items: [PlaybackQueueItem]) -> [PlaybackQueueItem] {
        guard !items.contains(item), items.count < limit else { return items }
        return items + [item]
    }

    static func removing(episodeID: UUID, from items: [PlaybackQueueItem]) -> [PlaybackQueueItem] {
        items.filter { $0 != .episode(episodeID) }
    }
}

/// Seride sıradaki bölüm (saf; test edilir). Seri sıraları boşluklu olabilir (1, 2, 4, 5): bölüm silinince ya da başka
/// seriye taşınınca kalanlar yeniden numaralanmaz.
nonisolated enum SeriesOrder {
    typealias Member = (id: UUID, index: Int, status: EpisodeStatus)

    /// `index`'ten sonraki en küçük sıradaki hazır bölüm. Üretimi süren bölüm atlanmaz (sırası beklenir: nil),
    /// başarısız olan atlanır. Aynı sırayı paylaşan bölümlerden ilk hazır olan seçilir.
    static func next(after index: Int, members: [Member]) -> UUID? {
        let later = members.filter { $0.index > index }
        for step in Set(later.map { $0.index }).sorted() {
            var generating = false
            for member in later where member.index == step {
                switch member.status {
                case .ready: return member.id
                case .generating: generating = true
                case .failed: break
                }
            }
            if generating { return nil }
        }
        return nil
    }
}

/// Mini oynatıcıdaki "Sıradakiler" listesi.
struct UpNextSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var episodes: [Episode]

    var body: some View {
        NavigationStack {
            Group {
                if player.upNext.isEmpty {
                    ContentUnavailableView("Sırada bölüm yok", systemImage: "list.bullet",
                                           description: Text("Bölüm sayfasındaki ••• düğmesinden \"Sıraya ekle\"yi seç."))
                } else {
                    List {
                        Section {
                            ForEach(Array(player.upNext.enumerated()), id: \.offset) { _, item in
                                Label(title(item), systemImage: icon(item))
                                    .lineLimit(2)
                            }
                            .onDelete { player.removeFromQueue(at: $0) }
                        } footer: {
                            Text("Çalan bölüm bitince sıradaki kendiliğinden başlar.")
                        }
                    }
                }
            }
            .navigationTitle("Sıradakiler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
                if !player.upNext.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Şimdi çal") {
                            player.playNext()
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Sırayı temizle", role: .destructive) { player.setQueue([]) }
                    }
                }
            }
        }
    }

    private func title(_ item: PlaybackQueueItem) -> String {
        switch item {
        case let .episode(id): episodes.first { $0.id == id }?.title ?? "Silinmiş bölüm"
        case let .audio(_, title): title
        }
    }

    private func icon(_ item: PlaybackQueueItem) -> String {
        switch item {
        case .episode: "waveform"
        case .audio: "sun.max"
        }
    }
}
