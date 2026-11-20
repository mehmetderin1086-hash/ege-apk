import Foundation
import Observation
import SwiftData
import UserNotifications

/// Takip edilen kanallardan gelen ("otomatik işle" açık) videoların kuyruğu: cihazda saklanır, uygulama açıkken sırayla işlenir (#2).
nonisolated struct QueuedImport: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var url: String
    var title: String
    var courseID: UUID?
    var addedAt: Date = .now
    var attempts: Int = 0

    /// Listede gösterilecek ad: başlık yoksa bağlantının kısa hâli.
    var displayTitle: String { title.isEmpty ? ImportLinks.shortName(url) : title }
}

enum AutoImportQueue {
    static let key = "youtube.autoQueue"
    static let maxAttempts = 2

    static var items: [QueuedImport] {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([QueuedImport].self, from: $0) } ?? []
    }

    private static func save(_ items: [QueuedImport]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: key)
    }

    /// Kuyruğa ekler; kuyrukta olan ya da kütüphanede bulunan videolar atlanır. Eklenen sayısını döndürür.
    @discardableResult
    static func enqueue(_ videos: [FeedVideo], courseID: UUID?, existing: [LessonKey] = []) -> Int {
        var current = items
        var added = 0
        for video in videos where !video.url.isEmpty {
            let key = ImportLinks.dedupeKey(video.url)
            if current.contains(where: { ImportLinks.dedupeKey($0.url) == key }) { continue }
            if LibraryDuplicates.existing(videoID: video.id, url: video.url, in: existing) != nil { continue }
            current.append(QueuedImport(url: video.url, title: video.title, courseID: courseID))
            added += 1
        }
        if added > 0 { save(current) }
        return added
    }

    static func update(_ item: QueuedImport) {
        save(items.map { $0.id == item.id ? item : $0 })
    }

    static func remove(_ id: UUID) {
        save(items.filter { $0.id != id })
    }

    /// Kuyruğu verilen sırayla yeniden yazar (hata politikası öğeyi sona taşıyınca).
    static func replaceAll(_ items: [QueuedImport]) { save(items) }

    static func clear() { save([]) }
}

/// Kuyruk hatasının türü: geçici/genel hata videoya ait değildir, deneme hakkı yakmaz.
nonisolated enum ImportFailureKind: Equatable, Sendable {
    /// Bağlantı yok, kota (429) ya da sunucu hatası (5xx): kuyruk bekler.
    case transient
    /// Oturum/erişim anahtarı (401): kuyruk bekler.
    case auth
    /// Videoya özgü (iş başarısız, bulunamadı, geçersiz istek): deneme hakkından düşer.
    case item
}

/// Kuyruk hata politikası (saf): hangi hata öğeyi düşürür, hangisi kuyruğu bekletir.
nonisolated enum ImportQueuePolicy {
    static let offlineReason = "Bağlantı yok; kuyruk bekliyor."

    private static func isNetwork(_ error: Error) -> Bool {
        error is URLError || (error as? APIError)?.code == "network"
    }

    static func kind(of error: Error) -> ImportFailureKind {
        if isNetwork(error) { return .transient }
        guard let api = error as? APIError else { return .item }
        if api.status == 429 || (500...599).contains(api.status) { return .transient }
        return api.status == 401 ? .auth : .item
    }

    /// Kuyruk beklerken gösterilecek neden: bağlantı hatasında sabit metin, kota/oturum/sunucu hatasında hatanın iletisi.
    static func pauseReason(for error: Error) -> String {
        isNetwork(error) ? offlineReason : (error as? APIError)?.message ?? error.localizedDescription
    }

    /// Geçici/oturum hatasında liste değişmez ve kuyruk durur. Öğe hatasında deneme sayısı artar: sınıra ulaşan öğe çıkar,
    /// ulaşmayan kuyruğun sonuna geçer (başta kalıp hemen yeniden denenmesin, öbür videoların önünü tıkamasın).
    static func applyFailure(_ items: [QueuedImport], id: UUID, kind: ImportFailureKind,
                             maxAttempts: Int) -> (items: [QueuedImport], stop: Bool) {
        guard kind == .item else { return (items, true) }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return (items, false) }
        var rest = items
        var failed = rest.remove(at: index)
        failed.attempts += 1
        if failed.attempts < maxAttempts { rest.append(failed) }
        return (rest, false)
    }

    /// Sunucu/karşı taraf hatası (5xx). Genel de olabilir (sunucu kapalı, YouTube engeli) videoya özgü de: sunucu, okuyamadığı
    /// videoda (ör. henüz yayınlanmamış prömiyer) başlatma isteğine 502 döner. Kuyruk bekler ama öğe sıranın sonuna geçer;
    /// başta kalsaydı tek video ötekilerin önünü süresiz tıkardı.
    static func isServerFailure(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return false }
        return (500...599).contains(api.status)
    }

    /// Öğeyi deneme hakkına dokunmadan kuyruğun sonuna alır; öğe yoksa liste değişmez.
    static func movedToEnd(_ items: [QueuedImport], id: UUID) -> [QueuedImport] {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return items }
        var rest = items
        let moved = rest.remove(at: index)
        rest.append(moved)
        return rest
    }
}

/// Kuyruğu uygulama açıkken sırayla işler: başlat → izle → ders olarak kaydet → (varsa) derse bağla.
@MainActor @Observable
final class ImportQueueRunner {
    private(set) var isRunning = false
    private(set) var currentTitle: String?
    private(set) var progress = 0.0
    private(set) var step = ""
    private(set) var queued = AutoImportQueue.items.count
    private(set) var done = 0
    private(set) var failures: [String] = []
    /// Kuyruk geçici bir nedenle (bağlantı, kota, oturum) bekliyorsa nedeni; öğeler kuyrukta kalır.
    private(set) var pausedReason: String?

    /// Şu an işlenen kuyruk öğesi (çalışmıyorsa nil).
    private(set) var activeItemID: UUID?

    private var task: Task<Void, Never>?
    private var activeJobId: String?

    func refreshCount() { queued = AutoImportQueue.items.count }

    /// Bekleyen bir öğeyi kuyruktan çıkarır (yalnız kuyruk kaydı; kütüphanedeki dersler etkilenmez).
    /// Şu an işlenen öğe çıkarılamaz (önce durdurulmalı): false döner.
    @discardableResult
    func remove(_ id: UUID) -> Bool {
        guard id != activeItemID else { return false }
        AutoImportQueue.remove(id)
        refreshCount()
        if queued == 0, !isRunning { pausedReason = nil }
        return true
    }

    /// Kuyruk boş değilse ve çalışmıyorsa başlatır.
    func kick(context: ModelContext) {
        refreshCount()
        guard task == nil else { return }
        pausedReason = nil
        guard queued > 0 else { return }
        isRunning = true
        failures = []
        task = Task {
            await process(context: context)
            isRunning = false
            currentTitle = nil
            activeItemID = nil
            task = nil
            refreshCount()
        }
    }

    /// Durdurur; sunucudaki iş de iptal edilir, kuyruk öğesi kalır.
    func stop() {
        task?.cancel()
        if let id = activeJobId {
            activeJobId = nil
            // Yerel kayıt hemen silinir (durdurulan iş "Yarım kalan işlemler"de takılı kalmasın); sunucu iptali arka planda.
            LessonImporter.forget(id)
            Task { _ = await YouTubeImportView.cancelOnServer(id) }
        }
    }

    private func process(context: ModelContext) async {
        while let item = AutoImportQueue.items.first, !Task.isCancelled {
            activeItemID = item.id
            currentTitle = item.displayTitle
            progress = 0
            step = "Başlatılıyor"
            let keys = ((try? context.fetch(FetchDescriptor<VideoLesson>())) ?? []).map { LessonKey(id: $0.id, videoID: $0.videoID, url: $0.url) }
            // Kütüphanede varsa (elle eklenmiş) tekrar işleme.
            if LibraryDuplicates.existing(videoID: nil, url: item.url, in: keys) != nil {
                AutoImportQueue.remove(item.id)
                refreshCount()
                continue
            }
            do {
                // Daha önce başlamış (uygulama kapanmış) bir iş varsa onu sürdür.
                let jobId: String
                if let pending = YouTubePendingJobs.all.first(where: { $0.url == item.url }) {
                    jobId = pending.jobId
                } else {
                    let request = YouTubeStartRequest(url: item.url, mode: .auto, language: nil, translateTo: nil, start: nil, end: nil,
                                                      keyframes: true, notes: true,
                                                      allowOther: ImportLinks.needsAllowOther(item.url) ? true : nil)
                    jobId = try await LessonImporter.start(request, url: item.url, title: currentTitle ?? item.url)
                }
                activeJobId = jobId
                defer { activeJobId = nil }
                var hooks = LessonImporter.Hooks()
                hooks.progress = { [weak self] value, text in self?.progress = value; self?.step = text }
                hooks.jobChanged = { [weak self] id in self?.activeJobId = id }
                hooks.willSave = { [weak self] in self?.activeJobId = nil }
                let lesson = try await LessonImporter.follow(jobId: jobId, url: item.url, title: currentTitle ?? item.url,
                                                             preview: nil, context: context, hooks: hooks)
                if let courseID = item.courseID { lesson.courseID = courseID; try? context.save() }
                AutoImportQueue.remove(item.id)
                done += 1
                await Self.notifyReady(lesson.title)
            } catch is CancellationError {
                return
            } catch {
                let kind = ImportQueuePolicy.kind(of: error)
                let outcome = ImportQueuePolicy.applyFailure(AutoImportQueue.items, id: item.id, kind: kind,
                                                             maxAttempts: AutoImportQueue.maxAttempts)
                // Bağlantı/kota/oturum hatasında kalan öğeleri denemenin anlamı yok: kuyruk olduğu gibi bekler.
                if outcome.stop {
                    let reason = ImportQueuePolicy.pauseReason(for: error)
                    if ImportQueuePolicy.isServerFailure(error) {
                        // Hata bu videoya özgü olabilir: sıradaki başlatmada öbür videolar denensin, hangi videoda kaldığı görünsün.
                        AutoImportQueue.replaceAll(ImportQueuePolicy.movedToEnd(outcome.items, id: item.id))
                        pausedReason = "\(currentTitle ?? item.url): \(reason)"
                    } else {
                        pausedReason = reason
                    }
                    return
                }
                AutoImportQueue.replaceAll(outcome.items)
                failures.append("\(currentTitle ?? item.url): \(error.localizedDescription)")
            }
            refreshCount()
        }
    }

    private static func notifyReady(_ title: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Ders hazır"
        content.body = title
        content.sound = .default
        content.userInfo = ["route": "videos"]
        try? await center.add(UNNotificationRequest(identifier: "queue-\(UUID().uuidString)", content: content, trigger: nil))
    }
}
