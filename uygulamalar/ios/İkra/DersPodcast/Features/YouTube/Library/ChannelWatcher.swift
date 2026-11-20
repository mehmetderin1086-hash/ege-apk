import SwiftData
import SwiftUI
import UserNotifications

/// #2: Takip edilen kanal/oynatma listelerini kontrol eder; yeni video → yerel bildirim, `autoProcess` ise kuyruğa.
@MainActor
enum ChannelWatcher {
    /// Açılışta bir kanalı bu süreden sık yoklamaz.
    static let minInterval: TimeInterval = 30 * 60

    /// Arka plan görevinde bir turda en fazla bu kadar kanal (iOS'un kısa süresine sığsın diye).
    static let backgroundChannelLimit = 3

    /// Tüm kanalları kontrol eder; bulunan yeni video sayısını döndürür. `minInterval` 0 ise zorla (elle "Şimdi kontrol et").
    /// `limit`: yalnız en eski kontrol edilen kanallardan bu kadarı (arka plan yolu). Görev iptal edilirse sonuç işlenmez ve bildirim atılmaz:
    /// kanal "görülmemiş" kalır, bir sonraki turda yeniden bulunur.
    @discardableResult
    static func checkAll(context: ModelContext, minInterval: TimeInterval = ChannelWatcher.minInterval, notify: Bool = true,
                         limit: Int? = nil) async -> Int {
        await checkAllDetailed(context: context, minInterval: minInterval, notify: notify, limit: limit).found
    }

    /// `checkAll` ile aynı tur; ayrıca kaç kanalın kontrol edilemediğini ve ilk hatayı bildirir (elle kontrolde hata
    /// "Yeni video yok" diye görünmesin). Aralığı dolmadığı için atlanan kanal ne kontrol edilmiş ne başarısız sayılır.
    static func checkAllDetailed(context: ModelContext, minInterval: TimeInterval = ChannelWatcher.minInterval, notify: Bool = true,
                                 limit: Int? = nil) async -> ChannelCheckSummary {
        var summary = ChannelCheckSummary()
        var channels = (try? context.fetch(FetchDescriptor<FollowedChannel>())) ?? []
        guard !channels.isEmpty else { return summary }
        if let limit {
            let picked = Set(FeedDiff.oldestFirst(channels.map { ($0.id, $0.lastChecked) }, limit: limit))
            channels = channels.filter { picked.contains($0.id) }
        }
        let keys = ((try? context.fetch(FetchDescriptor<VideoLesson>())) ?? []).map { LessonKey(id: $0.id, videoID: $0.videoID, url: $0.url) }
        for channel in channels {
            if Task.isCancelled { break }
            if minInterval > 0, let last = channel.lastChecked, Date.now.timeIntervalSince(last) < minInterval { continue }
            let feed: YouTubeFeed
            do {
                feed = try await APIClient.shared.youtubeFeed(url: channel.url)
            } catch is CancellationError {
                break
            } catch {
                summary.failed += 1
                if summary.firstError == nil { summary.firstError = (error as? APIError)?.message ?? error.localizedDescription }
                continue
            }
            // Süre dolduysa (iptal) sonuç işlenmez: bilinenler güncellenmezse yeni videolar sonraki turda yine bulunur.
            if Task.isCancelled { break }
            // Kontrol sürerken kanal silinmiş olabilir.
            guard channel.modelContext != nil, !channel.isDeleted else { continue }
            // Bilinen video kimliği yoksa (yeni takip, boş liste) mevcutlar "görülmüş" sayılır: bildirim ve kuyruk yok.
            let first = FeedDiff.isFirstCheck(known: channel.knownVideoIDs)
            let fresh = FeedDiff.newVideos(known: channel.knownVideoIDs, feed: feed.videos, isFirstCheck: first)
            channel.knownVideoIDs = FeedDiff.updatedKnown(known: channel.knownVideoIDs, feed: feed.videos)
            channel.lastChecked = .now
            if channel.title.isEmpty, !feed.title.isEmpty { channel.title = feed.title }
            try? context.save()
            summary.checked += 1
            guard !fresh.isEmpty else { continue }
            summary.found += fresh.count
            if channel.autoProcess { AutoImportQueue.enqueue(fresh, courseID: channel.courseID, existing: keys) }
            if notify, !Task.isCancelled { await postNotification(channel: channel.title.isEmpty ? feed.title : channel.title, videos: fresh, id: channel.id) }
        }
        return summary
    }

    private static func postNotification(channel: String, videos: [FeedVideo], id: UUID) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = channel.isEmpty ? "Yeni video" : "Yeni video: \(channel)"
        content.body = FeedDiff.notificationBody(channel: channel, videos: videos)
        content.sound = .default
        content.userInfo = ["route": "channels"]
        let request = UNNotificationRequest(identifier: "channel-\(id.uuidString)-\(videos.first?.id ?? "")", content: content, trigger: nil)
        try? await center.add(request)
    }

    /// Bildirim iznini ister (kanal eklenirken bir kez); verilmişse true.
    static func requestNotificationPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}
