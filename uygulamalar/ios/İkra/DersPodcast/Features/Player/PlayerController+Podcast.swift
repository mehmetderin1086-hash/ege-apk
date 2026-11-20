import SwiftData

// Parçalar arası oynatıcı API'si (§5.3; imzalar donuk). Asıl işleyiş PlayerController.swift içinde.
extension PlayerController {
    /// #16: bölümü (gerekirse yükleyip) çalar; `time` verilirse oradan. Göz atma ekranları yalnız bunu çağırır.
    func play(_ episode: Episode, at time: Double?, context: ModelContext) {
        if self.episode?.id != episode.id {
            load(episode, context: context, autoplay: false)
            guard self.episode?.id == episode.id else { return }
        } else {
            endClipSession()
        }
        if let time { seek(to: time) }
        play()
    }

    /// #22/#33: kesitleri sırayla çalar; her kesitten sonra `onClipEnd` bitene dek bekler.
    func playClips(_ clips: [PodcastClip], context: ModelContext, onClipEnd: @escaping @MainActor (PodcastClip) async -> Void) {
        startClips(clips, context: context, onClipEnd: onClipEnd)
    }

    /// #41: sıranın sonuna ekler (aynı öğe iki kez girmez).
    func enqueue(_ item: PlaybackQueueItem) { addToQueue(item) }

    /// #41: listeyi sıra yapar ve ilkini hemen çalar.
    func playQueue(_ items: [PlaybackQueueItem], context: ModelContext) {
        setQueue(items)
        advanceQueue(context: context)
    }

    var upNext: [PlaybackQueueItem] { queue }

    /// #26: bölüm bitince çalınacak bölüm (önce sıra, sonra seri).
    func nextUp() -> Episode? { upcomingEpisode() }

    /// #26: sıradakini hemen çalar (`holdAutoplay` de kalkar).
    func playNext() { advanceQueue() }

    var isInInterlude: Bool { interludeActive }
}
