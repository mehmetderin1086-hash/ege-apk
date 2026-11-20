import SwiftData
import SwiftUI

/// Öneri 8: bölümleri Mac'teki sunucuda kişisel bir podcast akışında (RSS) yayımlar.
/// Apple Podcasts / Overcast bu akışa abone olur; Apple Watch ve CarPlay'de de dinlenir.
enum PodcastFeed {
    static let autoKey = "feed.autoPublish"
    private static let publishedKey = "feed.published"
    /// #44: akışa en son gönderilen ses sürümü (bölüm kimliği → `Episode.audioRevision`).
    private static let revisionsKey = "feed.revisions"
    /// Cihazda silinmiş ama akıştan çıkarılamamış bölümler (ağ yoktu); sonraki fırsatta yeniden denenir.
    static let pendingRemovalsKey = "feed.pendingRemovals"
    /// Bu kurulumun akışa eklediği bölümler. Sunucu listesindeki yabancı (ör. yeniden kurulumdan önceki) bölümler
    /// cihazda yok diye akıştan silinmez; yalnız buradakiler ve `pendingRemovals` temizlenir.
    static let mineKey = "feed.mine"
    /// Akıştaki bölümler (`published`) değişti: kütüphane satırındaki "Akışta" simgesi kendiliğinden güncellenir.
    static let changed = Notification.Name("feed.publishedChanged")

    static var published: Set<UUID> {
        get { ids(publishedKey) }
        set { setIDs(newValue, publishedKey) }
    }

    static var pendingRemovals: Set<UUID> {
        get { ids(pendingRemovalsKey) }
        set { setIDs(newValue, pendingRemovalsKey) }
    }

    static var mine: Set<UUID> {
        get { ids(mineKey) }
        set { setIDs(newValue, mineKey) }
    }

    private static func ids(_ key: String) -> Set<UUID> {
        Set((UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:)))
    }

    private static func setIDs(_ ids: Set<UUID>, _ key: String) {
        let value = ids.map(\.uuidString).sorted()
        let unchanged = UserDefaults.standard.stringArray(forKey: key) == value
        UserDefaults.standard.set(value, forKey: key)
        if key == publishedKey, !unchanged { NotificationCenter.default.post(name: changed, object: nil) }
    }

    /// Akışı Apple Podcasts'te açan adres: http → `podcast://`, https → `podcasts://`; başka şemada nil.
    nonisolated static func podcastsAppURL(_ feed: URL) -> URL? {
        guard var parts = URLComponents(url: feed, resolvingAgainstBaseURL: false) else { return nil }
        switch parts.scheme?.lowercased() {
        case "http": parts.scheme = "podcast"
        case "https": parts.scheme = "podcasts"
        default: return nil
        }
        return parts.url
    }

    static var publishedRevisions: [UUID: Int] {
        get {
            let raw = UserDefaults.standard.dictionary(forKey: revisionsKey) as? [String: Int] ?? [:]
            return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } })
        }
        set { UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.uuidString, $0.value) }), forKey: revisionsKey) }
    }

    /// Ses (bölüm işaretleri ve kapak sunucuda gömülür), açıklama, kapak ve sürüm.
    /// Model yalnız yüklemeden önce okunur: uzun yükleme sürerken bölüm silinebilir (silinmiş @Model'e dokunulmaz).
    /// Yükleme bitince bölüm artık yoksa akıştan geri çıkarılır ve `false` döner.
    @discardableResult
    static func publish(_ episode: Episode) async throws -> Bool {
        guard let audio = episode.audioURL, episode.status == .ready else {
            throw APIError(status: 0, code: "state", message: "Bölüm henüz hazır değil.")
        }
        let id = episode.id
        let meta = FeedMetaV2Request(episode: episode, cover: CoverArt.jpeg(for: episode)?.base64EncodedString())
        let revision = episode.audioRevision
        do {
            try await APIClient.shared.feedPublishV2(audio: audio, meta: meta)
        } catch {
            // Ses yüklenip meta gönderilemediyse ve bölüm bu arada silindiyse sunucuda yetim ses kalmasın.
            if !episodeExists(id) { await removeDeleted(id: id) }
            throw error
        }
        guard episodeExists(id) else {
            await removeDeleted(id: id)
            return false
        }
        published.insert(id)
        mine.insert(id)
        publishedRevisions[id] = revision
        return true
    }

    static func remove(_ episode: Episode) async throws {
        try await remove(id: episode.id)
    }

    static func remove(id: UUID) async throws {
        try await APIClient.shared.feedRemove(id)
        forget(id)
    }

    /// Bölüm cihazdan silindi: akıştan çıkar; başaramazsa (ağ yok) kimlik `pendingRemovals`'a yazılır ve
    /// `retryPendingRemovals` (açılış, akış ayarları, `.audioChanged`, `.episodeReady`) yeniden dener.
    static func removeDeleted(id: UUID) async {
        do {
            try await remove(id: id)
        } catch {
            published.remove(id)
            publishedRevisions[id] = nil
            pendingRemovals.insert(id)
        }
    }

    private static func forget(_ id: UUID) {
        published.remove(id)
        mine.remove(id)
        pendingRemovals.remove(id)
        publishedRevisions[id] = nil
    }

    /// Bekleyen çıkarmaları yeniden dener; ilk hatada durur (Mac'e ulaşılamıyorsa diğerleri de başarısız olur).
    static func retryPendingRemovals() async {
        for id in pendingRemovals.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard (try? await remove(id: id)) != nil else { return }
        }
    }

    /// Sunucu akışında olup cihazda karşılığı olmayan, temizlenmesi gereken bölümler: bekleyen çıkarmalar ve bu
    /// kurulumun eklediği (`mine`) ama artık cihazda olmayanlar. Yabancı kimliklere (yeni kurulum, geri yükleme öncesi) dokunulmaz.
    nonisolated static func staleOnServer(server: Set<UUID>, device: Set<UUID>, mine: Set<UUID>, pending: Set<UUID>) -> Set<UUID> {
        server.intersection(mine.union(pending)).subtracting(device)
    }

    /// #44: ses değişince (`.audioChanged`) akıştaki bölüm yeniden gönderilir; aynı sürümse bir şey yapılmaz.
    static func needsRepublish(id: UUID, revision: Int, published: Set<UUID>, revisions: [UUID: Int]) -> Bool {
        published.contains(id) && revisions[id] != revision
    }

    static func republishIfNeeded(_ episode: Episode) async {
        guard needsRepublish(id: episode.id, revision: episode.audioRevision, published: published, revisions: publishedRevisions) else { return }
        _ = try? await publish(episode)
    }

    /// Akışın tam adresi (sunucu adresi + gizli yol). Sunucu listesiyle eşitlerken silinmiş bölümler akıştan temizlenir.
    static func feedURL() async throws -> URL {
        let info = try await APIClient.shared.feedInfo()
        let server = Set(info.episodes.map(\.id))
        // Cihaz listesi okunamazsa yalnız bilinen silmeler temizlenir.
        let stale = deviceEpisodeIDs().map { staleOnServer(server: server, device: $0, mine: mine, pending: pendingRemovals) }
            ?? server.intersection(pendingRemovals)
        // Sunucuda olmayan bekleyen çıkarma zaten tamam; cihaza geri gelen (geri yüklenen) bölüm çıkarılmaz.
        pendingRemovals = stale
        published = server.subtracting(stale)
        await retryPendingRemovals()
        return Config.apiBaseURL.appending(path: info.feedPath)
    }

    private static func episodeExists(_ id: UUID) -> Bool {
        let d = FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })
        // Okunamazsa var sayılır: yanlışlıkla akıştan silmektense yayımlandı say.
        return ((try? AppDataStore.container.mainContext.fetchCount(d)) ?? 1) > 0
    }

    private static func deviceEpisodeIDs() -> Set<UUID>? {
        var d = FetchDescriptor<Episode>()
        d.propertiesToFetch = [\.id]
        return (try? AppDataStore.container.mainContext.fetch(d)).map { Set($0.map(\.id)) }
    }
}

/// #44: `/v1/feed/meta` ek alanları (`cover` ≤1 MB JPEG base64, `revision`). Eski sunucu fazla alanları atar.
nonisolated struct FeedMetaV2Request: Encodable, Sendable {
    var id: UUID
    var title: String
    var description: String
    var durationSec: Double
    var createdAt: String
    var chapters: [FeedChapter]
    var cover: String?
    var revision: Int?
}

@MainActor
extension FeedMetaV2Request {
    /// Sunucunun `metaSchema` sınırlarına uyan istek: başlık 1…300, bölüm başlığı ≤300, en çok 200 bölüm işareti,
    /// açıklama ≤4000 (JS `length` = UTF-16 birimi), süre 0…86 400 sn.
    init(id: UUID, title: String, summary: String, chapters: [TimedChapter], duration: Double, createdAt: Date,
         cover: String?, revision: Int?) {
        let marks = chapters.prefix(FeedLimits.maxChapters).map {
            FeedChapter(title: FeedLimits.clip($0.title, FeedLimits.maxTitle), start: max(0, $0.start.isFinite ? $0.start : 0))
        }
        let lines = [summary] + marks.map { "\($0.start.clockText) \($0.title)" }
        let name = FeedLimits.clip(title.trimmingCharacters(in: .whitespacesAndNewlines), FeedLimits.maxTitle)
        self.init(id: id, title: name.isEmpty ? "Bölüm" : name,
                  description: FeedLimits.clip(lines.joined(separator: "\n"), FeedLimits.maxDescription),
                  durationSec: min(max(0, duration.isFinite ? duration : 0), 86_400), createdAt: createdAt.ISO8601Format(),
                  chapters: marks, cover: cover, revision: revision)
    }

    init(episode: Episode, cover: String?) {
        self.init(id: episode.id, title: episode.title, summary: episode.script?.summary ?? "",
                  chapters: episode.timeline?.chapters ?? [], duration: episode.duration, createdAt: episode.createdAt,
                  cover: cover, revision: episode.audioRevision)
    }
}

/// Sunucu şema sınırları. `clip` karakter sınırında, UTF-16 uzunluğuna (JS `string.length`) göre kırpar.
nonisolated enum FeedLimits {
    static let maxTitle = 300
    static let maxChapters = 200
    static let maxDescription = 4000

    static func clip(_ text: String, _ limit: Int) -> String {
        guard text.utf16.count > limit else { return text }
        var out = ""
        var used = 0
        for ch in text {
            let n = ch.utf16.count
            if used + n > limit { break }
            out.append(ch)
            used += n
        }
        return out
    }
}

/// Bölüm adı sınırı (yeniden adlandırma alanları; akış başlığı ayrıca 300'e kırpılır).
nonisolated enum EpisodeTitle {
    static let maxLength = 200

    /// Boşlukları kırpar, sınıra keser; boşsa nil.
    static func cleaned(_ raw: String) -> String? {
        let name = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
        return name.isEmpty ? nil : name
    }
}

nonisolated private struct FeedOK: Decodable, Sendable { var ok: Bool }

extension APIClient {
    /// Sesi ham gövde olarak yükler (PUT, enclosure `?v=<revision>`), ardından kapaklı meta bilgiyi gönderir.
    nonisolated func feedPublishV2(audio: URL, meta: FeedMetaV2Request) async throws {
        var request = URLRequest(url: Config.apiBaseURL.appending(path: "/v1/feed/audio/\(meta.id.uuidString.lowercased())"))
        request.httpMethod = "PUT"
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        guard let token = PersonalToken.current else { throw APIError(status: 401, code: "unauthorized", message: "Erişim anahtarı yok.") }
        request.setValue(token, forHTTPHeaderField: "X-Personal-Token")
        request.timeoutInterval = 600
        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.upload(for: request, fromFile: audio)
        } catch {
            throw APIError.network(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError(status: status, code: "upload", message: "Ses akışa yüklenemedi (\(status)).")
        }
        let _: FeedOK = try await post("/v1/feed/meta", meta)
    }
}

struct FeedSettingsSection: View {
    @AppStorage(PodcastFeed.autoKey) private var autoPublish = false
    @State private var url: URL?
    @State private var error: String?
    @State private var copied = false

    var body: some View {
        Section {
            if let url {
                Text(url.absoluteString).font(.caption.monospaced()).textSelection(.enabled)
                Button(copied ? "Kopyalandı" : "Adresi kopyala", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = url.absoluteString
                    copied = true
                }
                if let podcasts = PodcastFeed.podcastsAppURL(url) {
                    Link(destination: podcasts) { Label("Podcasts'te aç", systemImage: "apple.podcasts.pages") }
                }
            } else if let error {
                Text(error).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Tekrar dene", systemImage: "arrow.clockwise") { Task { await load() } }
            } else {
                ProgressView()
            }
            Toggle("Yeni bölümleri otomatik ekle", isOn: $autoPublish)
        } header: {
            Text("Podcast akışı (Apple Podcasts)")
        } footer: {
            Text("Apple Podcasts'te Arşiv → ••• → \"URL ile bir programı takip et\" ile bu adresi ekle. Bölümler sunucudan çalınır; internet bağlantısı gerekir. Bölüm menüsündeki \"Podcast akışına ekle\" ile tek tek de ekleyebilirsin.")
        }
        .task { await load() }
    }

    private func load() async {
        error = nil
        do { url = try await PodcastFeed.feedURL() } catch { self.error = "Akış adresi alınamadı: \(error.localizedDescription)" }
    }
}
