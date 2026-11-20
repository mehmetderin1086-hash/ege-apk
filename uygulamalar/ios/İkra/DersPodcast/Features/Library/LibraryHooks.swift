import Foundation
import SwiftData

/// P7 olay dinleyicileri (#42 Koç görevini otomatik tamamlama, #44 akış, #49 yedek tetiği, #50 silinmiş bölüm bağları).
enum LibraryHooks {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        PodcastEvent.observe(PodcastEvent.audioChanged) { info in
            retryFeedRemovals()
            guard let id = info.episodeID, PodcastFeed.published.contains(id), let episode = episode(id) else { return }
            Task { await PodcastFeed.republishIfNeeded(episode) }
        }
        PodcastEvent.observe(PodcastEvent.episodeReady) { _ in
            retryFeedRemovals()
            Task { await MacBackup.runIfDue(context: AppDataStore.container.mainContext) }
        }
        PodcastEvent.observe(PodcastEvent.episodeDeleted) { info in
            guard let id = info.episodeID else { return }
            unlink(deleted: id, context: AppDataStore.container.mainContext)
            // Başarısız çıkarma `pendingRemovals`'a yazılır; yükleme sürerken silinen bölümü `publish` kendisi geri çıkarır.
            if PodcastFeed.published.contains(id) || PodcastFeed.mine.contains(id) { Task { await PodcastFeed.removeDeleted(id: id) } }
        }
        // Açılış: önceki oturumda akıştan çıkarılamayan silinmiş bölümler (sunucu durumu yüklensin diye biraz sonra).
        Task {
            try? await Task.sleep(for: .seconds(20))
            retryFeedRemovals()
        }
    }

    private static func retryFeedRemovals() {
        guard !PodcastFeed.pendingRemovals.isEmpty else { return }
        Task { await PodcastFeed.retryPendingRemovals() }
    }

    private static func episode(_ id: UUID) -> Episode? {
        var d = FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? AppDataStore.container.mainContext.fetch(d).first
    }

    /// #50: silinen bölüme bağlı ödev bağı ve türev bölümlerin ana bölüm bağı temizlenir; silinen bölüm bir serideyse
    /// kalanların sırası kapanır (olay yalnız kimlik taşıdığı için bütün seriler denetlenir).
    static func unlink(deleted id: UUID, context: ModelContext) {
        var changed = false
        for a in (try? context.fetch(FetchDescriptor<Assignment>(predicate: #Predicate { $0.episodeID == id }))) ?? [] {
            a.episodeID = nil
            changed = true
        }
        for e in (try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.parentEpisodeID == id }))) ?? [] {
            e.parentEpisodeID = nil
            changed = true
        }
        if SeriesOps.closeGaps(context: context, excluding: id) { changed = true }
        if changed { try? context.save() }
    }
}
