import Foundation

/// Parçalar arası olay bilgisi (Sendable anlık görüntü).
nonisolated struct PodcastEventInfo: Sendable {
    var episodeID: UUID?
    var chapter: Int?
    var count: Int?
    var sleepTimer: Bool
}

/// Olaylar ana iş parçacığında, eşzamanlı yayılır. Yeni ad yalnız ana oturum ekler.
enum PodcastEvent {
    static let chapterFinished = Notification.Name("podcast.chapterFinished")
    static let episodeFinished = Notification.Name("podcast.episodeFinished")
    static let episodeReady = Notification.Name("podcast.episodeReady")
    static let audioChanged = Notification.Name("podcast.audioChanged")
    static let episodeDeleted = Notification.Name("podcast.episodeDeleted")
    static let reviewFinished = Notification.Name("study.reviewFinished")
    static let recallRecorded = Notification.Name("study.recallRecorded")

    static func post(_ name: Notification.Name, episodeID: UUID? = nil, chapter: Int? = nil, count: Int? = nil, sleepTimer: Bool = false) {
        var info: [String: Any] = ["sleepTimer": sleepTimer]
        if let episodeID { info["episodeID"] = episodeID }
        if let chapter { info["chapter"] = chapter }
        if let count { info["count"] = count }
        NotificationCenter.default.post(name: name, object: nil, userInfo: info)
    }

    /// Kalıcı dinleyici (yayın ana iş parçacığındadır; kapanış eşzamanlı çalışır).
    @discardableResult
    static func observe(_ name: Notification.Name, _ handler: @escaping @MainActor (PodcastEventInfo) -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { note in
            let u = note.userInfo
            let info = PodcastEventInfo(episodeID: u?["episodeID"] as? UUID, chapter: u?["chapter"] as? Int,
                                        count: u?["count"] as? Int, sleepTimer: u?["sleepTimer"] as? Bool ?? false)
            MainActor.assumeIsolated { handler(info) }
        }
    }
}
