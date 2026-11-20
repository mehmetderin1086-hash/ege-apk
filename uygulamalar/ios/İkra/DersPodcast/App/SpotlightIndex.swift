import AppIntents
import CoreSpotlight
import SwiftData

/// #43: bölümler (`EpisodeEntity`, Kısayollar ile ortak) ve konuları (ayrı öğe) Spotlight'ta aranır.
/// Konuya dokununca `AppLink` açılır; yönlendirme `DeepLink`'tedir.
enum SpotlightIndex {
    static func chapterDomain(_ id: UUID) -> String { "chapter.\(id.uuidString)" }

    static func handle(_ activity: NSUserActivity) {
        guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let link = link(for: identifier) else { return }
        DeepLink.open(link)
    }

    /// Öğe kimliği: konu öğelerinde `kocum://` bağlantısı, bölüm varlığında UUID.
    static func link(for identifier: String) -> AppLink? {
        if let url = URL(string: identifier), let link = AppLink(url: url) { return link }
        if let id = UUID(uuidString: identifier) { return .episode(id, time: nil, play: false) }
        return nil
    }

    /// Bir konu öğesinin (Sendable) içeriği; `CSSearchableItem` dizinleme sırasında kurulur.
    nonisolated struct ChapterEntry: Sendable, Equatable {
        var identifier: String
        var domain: String
        var title: String
        var detail: String
        var keywords: [String]
    }

    /// Bölümün konuları: her biri o konunun başından çalan bağlantı.
    static func chapterEntries(for episode: Episode) -> [ChapterEntry] {
        guard let timeline = episode.timeline, timeline.chapters.count > 1 else { return [] }
        let keywords = [episode.title, episode.seriesTitle].compactMap { $0 } + episode.sourceNames
        return timeline.chapters.map { chapter in
            ChapterEntry(identifier: AppLink.episode(episode.id, time: chapter.start, play: true).url.absoluteString,
                         domain: chapterDomain(episode.id), title: chapter.title,
                         detail: "\(episode.title) · Konu \(chapter.id + 1) · \(chapter.start.clockText)", keywords: keywords)
        }
    }

    private nonisolated static func item(_ entry: ChapterEntry) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .audio)
        attributes.title = entry.title
        attributes.contentDescription = entry.detail
        attributes.keywords = entry.keywords
        return CSSearchableItem(uniqueIdentifier: entry.identifier, domainIdentifier: entry.domain, attributeSet: attributes)
    }

    /// Açılış tazelemesi: yalnız imzası değişen bölümler yeniden dizinlenir (zaman çizelgesi ana iş parçacığında
    /// çözülür; büyük kütüphanede her açılışta hepsini çözmek takılma yapar). Haftada bir hepsi tazelenir.
    static func reindex(context: ModelContext, store: UserDefaults = .standard) {
        let ready = EpisodeStatus.ready.rawValue
        let episodes = (try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.statusRaw == ready }))) ?? []
        let changed = changedEpisodes(episodes, store: store)
        submit(changed)
        if !changed.isEmpty { DersPodcastShortcuts.updateAppShortcutParameters() }
    }

    /// Bölüm hazır oldu ya da sesi/konuları değişti (`episodeReady`, `audioChanged`).
    static func index(episodeID id: UUID, context: ModelContext, store: UserDefaults = .standard) {
        guard let episode = try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })).first,
              episode.status == .ready else { return }
        var signatures = storedSignatures(store)
        signatures[id.uuidString] = signature(episode)
        store.set(signatures, forKey: signatureKey)
        submit([episode])
        DersPodcastShortcuts.updateAppShortcutParameters()
    }

    static func remove(episodeID id: UUID, store: UserDefaults = .standard) {
        var signatures = storedSignatures(store)
        signatures[id.uuidString] = nil
        store.set(signatures, forKey: signatureKey)
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [chapterDomain(id)]) { @Sendable _ in }
        Task { try? await CSSearchableIndex.default().deleteAppEntities(identifiedBy: [id], ofType: EpisodeEntity.self) }
        DersPodcastShortcuts.updateAppShortcutParameters()
    }

    // MARK: - Değişim imzası

    static let signatureKey = "p5.spotlight.signatures"
    static let fullRefreshKey = "p5.spotlight.fullRefreshAt"
    static let fullRefreshInterval: TimeInterval = 7 * 86_400

    /// Dizine giren her şeyi etkileyen alanlar (ses/konu değişimi `audioRevision` ve zaman çizelgesi boyutuyla görünür).
    static func signature(_ episode: Episode) -> String {
        [String(episode.audioRevision), String(episode.timelineData?.count ?? 0), episode.title,
         episode.seriesTitle ?? "", String(episode.seriesIndex), episode.sourceNames.joined(separator: "|")]
            .joined(separator: "\u{1F}")
    }

    /// İmzası değişen (ya da süresi dolmuş tam tazelemede tümü) bölümler; imzaları kaydeder, gidenleri unutur.
    static func changedEpisodes(_ episodes: [Episode], store: UserDefaults, now: Date = .now) -> [Episode] {
        let old = storedSignatures(store)
        let full = (store.object(forKey: fullRefreshKey) as? Date).map { now.timeIntervalSince($0) > fullRefreshInterval } ?? true
        var next: [String: String] = [:]
        var changed: [Episode] = []
        for episode in episodes {
            let key = episode.id.uuidString
            let value = signature(episode)
            next[key] = value
            if full || old[key] != value { changed.append(episode) }
        }
        store.set(next, forKey: signatureKey)
        if full { store.set(now, forKey: fullRefreshKey) }
        return changed
    }

    private static func storedSignatures(_ store: UserDefaults) -> [String: String] {
        store.dictionary(forKey: signatureKey) as? [String: String] ?? [:]
    }

    private static func submit(_ episodes: [Episode]) {
        guard !episodes.isEmpty else { return }
        let entities = episodes.map(EpisodeEntity.init)
        let domains = episodes.map { chapterDomain($0.id) }
        let entries = episodes.flatMap(chapterEntries)
        Task { await replace(domains: domains, entries: entries, entities: entities) }
    }

    /// Önce bölümün eski konu öğeleri silinir: konu çıkarılınca ya da sahne düzenlenince başlangıçlar kayar;
    /// eski öğe (kimliği eski zamanı taşır) Spotlight'ta kalıp yanlış yere götürmesin.
    private nonisolated static func replace(domains: [String], entries: [ChapterEntry], entities: [EpisodeEntity]) async {
        let index = CSSearchableIndex.default()
        try? await index.deleteSearchableItems(withDomainIdentifiers: domains)
        if !entries.isEmpty { try? await index.indexSearchableItems(entries.map(item)) }
        try? await index.indexAppEntities(entities)
    }
}
