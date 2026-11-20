import Foundation
import UniformTypeIdentifiers

// İçe aktarma, kütüphane ve kanal takibinin saf mantığı (test edilir; arayüz/ağ yok).

// MARK: - Bağlantılar (#3, #5)

nonisolated enum LinkClass: Equatable, Sendable {
    case youtube
    /// "vimeo" | "dailymotion"
    case supported(String)
    /// İzinli listede olmayan https adresi: "Bu siteyi dene" onayı ister.
    case other(host: String)
    /// İzinli listede olmayan düz http adresi (reddedilir).
    case insecure
    case invalid
}

nonisolated enum ImportLinks {
    static let maxLinks = 30
    private static let knownPrefixes = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be",
                                        "vimeo.com", "www.vimeo.com", "player.vimeo.com", "dailymotion.com", "www.dailymotion.com", "dai.ly"]

    /// Metni (çok satırlı, boşluk/virgülle ayrılmış, başlık + bağlantı karışık) bağlantı listesine ayırır; tekrarlar atılır.
    static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        var links: [String] = []
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;"))
        for raw in text.components(separatedBy: separators) {
            let token = raw.trimmingCharacters(in: CharacterSet(charactersIn: "<>()[]\"'“”"))
            guard let link = normalize(token) else { continue }
            guard seen.insert(dedupeKey(link)).inserted else { continue }
            links.append(link)
            if links.count >= maxLinks { break }
        }
        return links
    }

    /// Bağlantı gibi görünen belirteci http(s) adresine çevirir; değilse nil.
    static func normalize(_ token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            guard let url = URL(string: trimmed), url.host()?.contains(".") == true else { return nil }
            return trimmed
        }
        guard knownPrefixes.contains(where: { lower.hasPrefix($0 + "/") || lower == $0 }) else { return nil }
        return "https://" + trimmed
    }

    /// Aynı video farklı biçimlerde (youtu.be / watch?v=) gelirse tek sayılır.
    static func dedupeKey(_ link: String) -> String {
        if let id = YouTubeLink.videoID(link) { return "yt:" + id }
        if let list = YouTubeLink.playlistID(link) { return "yl:" + list }
        var key = link.lowercased()
        while key.hasSuffix("/") { key.removeLast() }
        return key
    }

    /// Kanal takibi girdisi: çıplak "@kullanıcı" da kabul edilir (kanal adresine çevrilir); diğerleri `normalize` ile.
    static func channelLink(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@") {
            let handle = trimmed.dropFirst()
            guard !handle.isEmpty, handle.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }) else { return nil }
            return "https://www.youtube.com/" + trimmed
        }
        return normalize(trimmed)
    }

    /// Aynı kanalın farklı yazımları (büyük/küçük harf, sondaki /videos, /featured…) tek sayılır. Oynatma listesi "yl:<id>";
    /// kanal "yc:@kullanıcı" | "yc:channel/UC…" (kimlik harf duyarlı, aynen) | "yc:c/ad" | "yc:user/ad"; tanınmazsa `dedupeKey`.
    static func channelKey(_ link: String) -> String {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let full = lower.hasPrefix("http://") || lower.hasPrefix("https://") ? trimmed : "https://" + trimmed
        guard YouTubeLink.isYouTube(full), let url = URL(string: full) else { return dedupeKey(link) }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let first = parts.first else { return dedupeKey(link) }
        // Sunucuyla aynı kural: yalnız /playlist ve /watch?list=… oynatma listesidir; kanal adresindeki list= kanalı değiştirmez.
        if first == "playlist" || first == "watch", let list = YouTubeLink.playlistID(full) { return "yl:" + list }
        if first.hasPrefix("@"), first.count > 1 { return "yc:" + first.lowercased() }
        guard parts.count >= 2 else { return dedupeKey(link) }
        switch first {
        case "channel": return "yc:channel/" + parts[1]
        case "c", "user": return "yc:\(first)/" + parts[1].lowercased()
        default: return dedupeKey(link)
        }
    }

    static func classify(_ text: String) -> LinkClass {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return .invalid }
        let full = trimmed.lowercased().hasPrefix("http") ? trimmed : "https://" + trimmed
        guard let url = URL(string: full), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host()?.lowercased(), host.contains(".") else { return .invalid }
        if YouTubeLink.isYouTube(full) { return .youtube }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if bare == "vimeo.com" || bare == "player.vimeo.com" { return .supported("vimeo") }
        if bare == "dailymotion.com" || bare == "dai.ly" { return .supported("dailymotion") }
        return scheme == "https" ? .other(host: host) : .insecure
    }

    /// Sunucuya `allowOther: true` gönderilmesi gereken adres (izinli listede değil).
    static func needsAllowOther(_ link: String) -> Bool {
        if case .other = classify(link) { return true }
        return false
    }

    /// Bağlantı kısa görünüm adı (ana makine + yol sonu).
    static func shortName(_ link: String) -> String {
        if let id = YouTubeLink.videoID(link) { return "youtube · \(id)" }
        guard let url = URL(string: link), let host = url.host() else { return link }
        let last = url.lastPathComponent
        return last.isEmpty || last == "/" ? host : "\(host) · \(last)"
    }
}

// MARK: - Kopya tespiti (#40)

nonisolated struct LessonKey: Hashable, Sendable {
    var id: UUID
    var videoID: String
    var url: String
}

nonisolated enum LibraryDuplicates {
    /// Aynı video zaten kütüphanede mi: önce video kimliği, yoksa bağlantı (eğik çizgi/büyük harf farkı yok sayılır).
    static func existing(videoID: String?, url: String?, in lessons: [LessonKey]) -> UUID? {
        if let videoID, !videoID.isEmpty, let hit = lessons.first(where: { $0.videoID == videoID }) { return hit.id }
        let id = url.flatMap { YouTubeLink.videoID($0) }
        if let id, let hit = lessons.first(where: { $0.videoID == id }) { return hit.id }
        guard let url, !url.isEmpty else { return nil }
        let key = ImportLinks.dedupeKey(url)
        return lessons.first { !$0.url.isEmpty && ImportLinks.dedupeKey($0.url) == key }?.id
    }
}

// MARK: - Etiketler (#40)

nonisolated enum TagLogic {
    static let maxTags = 5
    static let maxLength = 40

    /// Konu + alt başlıklar → temiz etiket listesi (ilk öğe ders/alan adı; tekrarsız, ≤ 5).
    static func normalize(subject: String, topics: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in [subject] + topics {
            let tag = String(raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "#,;"))).prefix(maxLength))
            guard !tag.isEmpty, seen.insert(tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr"))).inserted else { continue }
            out.append(tag)
            if out.count == maxTags { break }
        }
        return out
    }

    /// Kütüphanede kullanılan etiketler: sıklığa göre azalan, eşitlikte alfabetik.
    static func counts(_ lists: [[String]]) -> [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for tag in lists.flatMap({ $0 }) { counts[tag, default: 0] += 1 }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag.localizedCompare($1.tag) == .orderedAscending }
    }
}

// MARK: - Oynatma listesi → ders (#6)

nonisolated enum PlaylistCourse {
    static func name(from playlistTitle: String) -> String {
        let trimmed = playlistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Oynatma listesi" : String(trimmed.prefix(60))
    }

    /// Aynı adlı ders varsa (büyük/küçük harf farkı yok sayılır) onu eşler.
    static func match(name: String, in courses: [(id: UUID, name: String)]) -> UUID? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(with: Locale(identifier: "tr"))
        return courses.first { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(with: Locale(identifier: "tr")) == key }?.id
    }
}

// MARK: - Sınıf kaydı (#4)

nonisolated enum RecordingPlan {
    /// Sunucunun yükleme sınırı.
    static let maxUploadBytes: Int64 = 500 * 1024 * 1024
    /// Bu boyutun altındaki m4a olduğu gibi yüklenir; üstü cihazda AAC 48 kbps mono'ya dönüştürülür.
    static let directAudioLimit: Int64 = 25 * 1024 * 1024
    /// Kareler için video olduğu gibi yüklenir; bu boyutu aşarsa yalnız ses (kare çıkarılmaz).
    static let directVideoLimit: Int64 = 200 * 1024 * 1024
    /// AAC 48 kbps mono ≈ 6 KB/sn.
    static let aacBytesPerSecond = 6_000.0

    struct Plan: Equatable, Sendable {
        /// Cihazda m4a (AAC 48 kbps mono) üret: dersin çevrimdışı sesi ve (video yüklenmeyecekse) yüklenecek dosya.
        var convertToAAC: Bool
        /// Yükleme gövdesi videonun kendisi (kare çıkarma için).
        var uploadVideo: Bool
    }

    static func plan(bytes: Int64, fileExtension: String, isVideo: Bool) -> Plan {
        if isVideo { return Plan(convertToAAC: true, uploadVideo: bytes <= directVideoLimit) }
        // Yalnız m4a kapsayıcısı doğrudan sayılır: ham .aac (ADTS) "audio.m4a" adıyla kopyalanırsa oynatılamaz, o yüzden dönüştürülür.
        let m4a = fileExtension.lowercased() == "m4a"
        return Plan(convertToAAC: !m4a || bytes > directAudioLimit, uploadVideo: false)
    }

    static func estimatedAACBytes(duration: Double) -> Int64 {
        Int64(max(0, duration) * aacBytesPerSecond)
    }

    /// Yüklenecek dosya sınırı aşmıyor mu.
    static func fitsUpload(_ bytes: Int64) -> Bool { bytes > 0 && bytes <= maxUploadBytes }

    static func isVideo(fileExtension: String) -> Bool {
        UTType(filenameExtension: fileExtension.lowercased())?.conforms(to: .movie) ?? false
    }

    static func displayTitle(fileName: String) -> String {
        var base = (fileName as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        // ".m4a" gibi yalnız uzantıdan oluşan ad başlık olmaz.
        if base.hasPrefix(".") { base = "" }
        return base.isEmpty ? "Sınıf kaydı" : base
    }
}

// MARK: - Kanal takibi (#2)

/// Bir kanal kontrol turunun özeti: bulunan yeni video, kontrol edilen ve kontrol edilemeyen kanal sayısı.
nonisolated struct ChannelCheckSummary: Equatable, Sendable {
    var found = 0
    var checked = 0
    var failed = 0
    /// Kontrol edilemeyen ilk kanalın hata iletisi.
    var firstError: String?
}

nonisolated enum FeedDiff {
    static let maxKnown = 300

    /// "Şimdi kontrol et" sonucu: hata "Yeni video yok" diye gösterilmez.
    static func checkMessage(_ summary: ChannelCheckSummary) -> String {
        let failed = "\(summary.failed) kanal kontrol edilemedi"
        if summary.found > 0 {
            return "\(summary.found) yeni video bulundu." + (summary.failed > 0 ? " \(failed)." : "")
        }
        guard summary.failed > 0 else { return "Yeni video yok." }
        let reason = summary.firstError?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return reason.isEmpty ? "\(failed)." : "\(failed): \(reason)"
    }

    /// İlk kontrol: bilinen video kimliği yoksa (yeni takip ya da o an listesi boş kanal) mevcut videolar "görülmüş" sayılır.
    static func isFirstCheck(known: [String]) -> Bool { known.isEmpty }

    /// Arka plan yolunda bir turda en fazla `limit` kanal: en eski kontrol edilenler önce (hiç kontrol edilmemiş en eski sayılır).
    static func oldestFirst(_ items: [(id: UUID, lastChecked: Date?)], limit: Int) -> [UUID] {
        items.sorted { ($0.lastChecked ?? .distantPast) < ($1.lastChecked ?? .distantPast) }.prefix(max(0, limit)).map(\.id)
    }

    /// Daha önce görülmeyen videolar (kanal ilk kez kontrol ediliyorsa hepsi "bilinen" sayılır, bildirim çıkmaz).
    static func newVideos(known: [String], feed: [FeedVideo], isFirstCheck: Bool) -> [FeedVideo] {
        guard !isFirstCheck else { return [] }
        let seen = Set(known)
        return feed.filter { !$0.id.isEmpty && !seen.contains($0.id) }
    }

    /// Yeni kimlikler başa, eskiler arkaya; sınırlı (kopyasız).
    static func updatedKnown(known: [String], feed: [FeedVideo]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for id in feed.map(\.id) + known where !id.isEmpty && seen.insert(id).inserted { out.append(id) }
        return Array(out.prefix(maxKnown))
    }

    /// Bildirim metni.
    static func notificationBody(channel: String, videos: [FeedVideo]) -> String {
        guard let first = videos.first else { return channel }
        if videos.count == 1 { return first.title.isEmpty ? channel : first.title }
        return "\(first.title) ve \(videos.count - 1) video daha"
    }
}

// MARK: - Toplu kuyruk (#3)

nonisolated enum ImportBatch {
    enum Status: Equatable, Sendable {
        case ready
        /// Zaten kütüphanede (mevcut ders kimliği): varsayılan olarak atlanır.
        case duplicate(UUID)
        /// İzinli listede olmayan https adresi; "diğer siteleri dene" onayı gerekir.
        case needsApproval
        /// http ya da geçersiz bağlantı.
        case rejected
    }

    struct Entry: Identifiable, Equatable, Sendable {
        var link: String
        var status: Status
        var id: String { link }
    }

    static func plan(links: [String], existing: [LessonKey], allowOther: Bool) -> [Entry] {
        links.map { link in
            switch ImportLinks.classify(link) {
            case .invalid, .insecure:
                return Entry(link: link, status: .rejected)
            case .other:
                if !allowOther { return Entry(link: link, status: .needsApproval) }
            case .youtube, .supported:
                break
            }
            if let id = LibraryDuplicates.existing(videoID: nil, url: link, in: existing) {
                return Entry(link: link, status: .duplicate(id))
            }
            return Entry(link: link, status: .ready)
        }
    }

    /// Başlatılacak bağlantılar: yalnız hazır olanlar, elle çıkarılanlar hariç.
    static func runnable(_ entries: [Entry], excluded: Set<String>) -> [String] {
        entries.filter { $0.status == .ready && !excluded.contains($0.link) }.map(\.link)
    }
}
