import Foundation
import SwiftData

enum EpisodeStatus: String, Codable {
    case generating   // senaryo hazır, sahneler seslendiriliyor
    case ready
    case failed
}

/// Bir podcast bölümü. Karmaşık yapılar JSON blob olarak saklanır; SwiftData ilişkileri gereksiz yük getirir.
@Model
final class Episode {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var title: String
    var sourceNames: [String]
    var statusRaw: String
    var errorMessage: String?

    var scriptData: Data
    var settingsData: Data
    var timelineData: Data?
    var studyData: Data?

    var jobToken: String?
    var jobTokenExpiresAt: Date?
    var scenesDone: Int
    var scenesTotal: Int

    var audioFileName: String?
    var duration: Double
    var lastPosition: Double
    var isFinished: Bool
    var lastPlayedAt: Date?

    /// Seri: birden çok belgeden sıralı bölümler (aynı seriID, 1'den başlayan seriIndex).
    var seriesID: UUID?
    var seriesTitle: String?
    var seriesIndex: Int = 0
    /// Konu haritası (sunucunun /v1/study yanıtındaki concepts). JSON.
    var conceptsData: Data?
    /// Daha önce üretilmiş kapak ve ders şemaları (üretim kaldırıldı; eski bölümlerde görünür). Opsiyonel alanlar eski bölümleri korur.
    var visualsData: Data?
    var visualsError: String?
    /// Kullanıcı puanı (1 = 👎, 2 = 👍) ve sebebi.
    var rating: Int?
    var ratingNote: String?
    /// Belge kütüphanesindeki kaynaklar (SourceDocument.id); transkriptteki "s. N" etiketinden PDF açmak için.
    var sourceDocumentIDs: [UUID]?
    /// Oynatmayla senkron slaytlar ve senaryo doğrulama sonuçları (JSON).
    var slidesData: Data?
    var verifyData: Data?
    /// Slayt destesi (JSON) ve üreten model; görseller bölüm klasöründe deck_<i>.png.
    var deckData: Data?
    var deckModel: String?
    var courseID: UUID?
    var parentEpisodeID: UUID?
    /// "recap" | "gap" | "weekly" | "video" | "discriminate"
    var derivedKind: String?
    var sourceLessonID: UUID?
    var sourceVideoTime: Double?
    var generationStatsData: Data?
    var audioIssuesData: Data?
    /// #7: senaryo hazır, seslendirme onayı bekliyor.
    var needsApproval: Bool = false
    var topicsData: Data?
    /// #44: ses her değişince +1.
    var audioRevision: Int = 0

    init(id: UUID = UUID(), script: PodcastScript, settings: PodcastSettings, sourceNames: [String], jobToken: String) {
        self.id = id
        createdAt = .now
        title = script.title
        self.sourceNames = sourceNames
        statusRaw = EpisodeStatus.generating.rawValue
        scriptData = (try? JSONEncoder().encode(script)) ?? Data()
        settingsData = (try? JSONEncoder().encode(settings)) ?? Data()
        self.jobToken = jobToken
        jobTokenExpiresAt = .now.addingTimeInterval(115 * 60)
        scenesDone = 0
        scenesTotal = script.flatScenes.count
        duration = 0
        lastPosition = 0
        isFinished = false
    }

    var status: EpisodeStatus {
        get { EpisodeStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    var script: PodcastScript? { blob("script", scriptData) }
    var settings: PodcastSettings? { blob("settings", settingsData) }

    var timeline: Timeline? {
        get { blob("timeline", timelineData) }
        set { timelineData = encoded("timeline", newValue) }
    }

    var concepts: [Concept] {
        get { (blob("concepts", conceptsData) as [Concept]?) ?? study?.concepts ?? [] }
        set { conceptsData = encoded("concepts", newValue) }
    }

    var slides: [LessonSlide]? {
        get { blob("slides", slidesData) }
        set { slidesData = encoded("slides", newValue) }
    }

    var deck: Deck? {
        get { blob("deck", deckData) }
        set { deckData = encoded("deck", newValue) }
    }

    func deckImageURL(_ index: Int) -> URL { directory.appending(path: "deck_\(index).png") }

    /// Kaynaktan çıkarılan şekiller (figures.json) ve kırpılmış görselleri. Okuma klasör oluşturmaz; liste dosya
    /// damgası değişmedikçe yeniden okunmaz (her çizimde bölüm başına bir kez sorulur).
    var sourceFigures: [SourceFigure] {
        get { EpisodeBlobCache.shared.figures(id, at: EpisodeFiles.figuresURL(for: id)) }
        set {
            let url = directory.appending(path: EpisodeFiles.figuresName)
            guard let data = try? JSONEncoder().encode(newValue), (try? data.write(to: url, options: .atomic)) != nil else { return }
            EpisodeBlobCache.shared.storeFigures(id, newValue, at: url)
        }
    }

    func figureURL(_ id: String) -> URL { directory.appending(path: "figure_\(id).png") }

    var verification: [ScriptIssue]? {
        get { blob("verification", verifyData) }
        set { verifyData = encoded("verification", newValue) }
    }

    var study: StudyPack? {
        get { blob("study", studyData) }
        set { studyData = encoded("study", newValue) }
    }

    var visuals: VisualPack? {
        get { blob("visuals", visualsData) }
        set { visualsData = encoded("visuals", newValue) }
    }

    var generationStats: GenerationStats? {
        get { blob("generationStats", generationStatsData) }
        set { generationStatsData = encoded("generationStats", newValue) }
    }

    var audioIssues: [AudioIssue] {
        get { blob("audioIssues", audioIssuesData) ?? [] }
        set { audioIssuesData = encoded("audioIssues", newValue.isEmpty ? nil : newValue) }
    }

    var topics: [TopicTag] {
        get { blob("topics", topicsData) ?? [] }
        set { topicsData = encoded("topics", newValue.isEmpty ? nil : newValue) }
    }

    /// Blob alanının çözülmüş hâli: aynı Data için JSON yalnız bir kez çözülür (`EpisodeBlobCache`).
    private func blob<T: Decodable & Sendable>(_ field: String, _ data: Data?) -> T? {
        guard let data else { return nil }
        return EpisodeBlobCache.shared.value(id, field, data)
    }

    /// Saklanacak Data; değer önbelleğe de yazılır (ardından gelen okuma çözmesin). nil ya da kodlanamayan değer → nil.
    private func encoded<T: Encodable & Sendable>(_ field: String, _ value: T?) -> Data? {
        EpisodeBlobCache.shared.encode(id, field, value)
    }

    /// Bölüm oluşturulurken ayarlardaki seri ve türev bağlamını işler (P3 çağırır).
    func applyContext(from settings: PodcastSettings) {
        if let s = settings.series {
            seriesID = s.id
            seriesTitle = s.name
            seriesIndex = s.index
        }
        if let d = settings.derivation {
            derivedKind = d.kind
            parentEpisodeID = d.parentEpisodeID
            sourceLessonID = d.sourceLessonID
            sourceVideoTime = d.sourceVideoTime
            if let course = d.courseID { courseID = course }
        }
    }

    var canResume: Bool {
        status == .generating && script != nil && settings != nil
    }

    var directory: URL { EpisodeFiles.directory(for: id) }
    var audioURL: URL? { audioFileName.map { directory.appending(path: $0) } }

    var progress: Double {
        guard scenesTotal > 0 else { return 0 }
        return Double(scenesDone) / Double(scenesTotal)
    }
}

/// Bölüm blob alanlarının çözülmüş hâli: görünümler bu alanları her çizimde okur, JSON her seferinde çözülmesin.
/// Kayıt, çözüldüğü Data ile birlikte durur; saklanan Data başka yoldan değişmişse (doğrudan `scriptData` ataması,
/// geri alma, yedekten dönüş, başka bağlam) eşleşmez ve yeniden çözülür. Şekil listesi (figures.json) dosya
/// damgasıyla saklanır: dosya dışarıdan da değişebilir (yedekten geri yükleme).
/// `Episode` bir aktöre bağlı değildir (@Model); bu yüzden önbellek kilitlidir ve her bağlamdan çağrılabilir.
nonisolated final class EpisodeBlobCache: @unchecked Sendable {
    static let shared = EpisodeBlobCache()

    private struct Key: Hashable { var id: UUID; var field: String }
    private struct Entry {
        var data: Data
        var type: ObjectIdentifier
        var value: (any Sendable)?
        var order: UInt64
        /// Bu anahtar kayıtlıyken kaç kez çözüldü.
        var decodes: Int
    }
    private struct FileEntry { var stamp: WordSync.AudioStamp; var value: [SourceFigure]; var order: UInt64 }

    /// Kayıt sayısı ve toplam JSON baytı sınırı; aşılınca en uzun süredir kullanılmayan düşer.
    let limit: Int
    let byteLimit: Int
    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    private var files: [UUID: FileEntry] = [:]
    private var bytes = 0
    private var clock: UInt64 = 0
    private var decodes = 0
    private var fileReads = 0

    init(limit: Int = 320, byteLimit: Int = 12 << 20) {
        self.limit = max(1, limit)
        self.byteLimit = max(0, byteLimit)
    }

    /// Testler ve tanılama: kaç kez JSON çözüldü, kaç kez şekil dosyası okundu, kaç kayıt duruyor.
    var decodeCount: Int { lock.withLock { decodes } }
    var fileReadCount: Int { lock.withLock { fileReads } }
    var count: Int { lock.withLock { entries.count } }
    var figureListCount: Int { lock.withLock { files.count } }
    /// Tek alanın çözülme sayısı (ortak önbellekte başka bölümlerin okumalarından etkilenmez).
    func decodeCount(for id: UUID, _ field: String) -> Int { lock.withLock { entries[Key(id: id, field: field)]?.decodes ?? 0 } }

    /// `data`nın çözülmüş hâli. Başarısız çözüm de (nil) saklanır: bozuk blob her okumada yeniden denenmez.
    func value<T: Decodable & Sendable>(_ id: UUID, _ field: String, _ data: Data?) -> T? {
        guard let data else { return nil }
        let key = Key(id: id, field: field)
        let type = ObjectIdentifier(T.self)
        let cached = lock.withLock { () -> (hit: Bool, value: T?) in
            clock += 1
            guard let entry = entries[key], entry.type == type, entry.data == data else { return (false, nil) }
            entries[key]?.order = clock
            return (true, entry.value as? T)
        }
        if cached.hit { return cached.value }
        let value = try? JSONDecoder().decode(T.self, from: data)   // kilidin dışında: büyük blobda uzun sürer
        lock.withLock {
            decodes += 1
            put(key, data, type, value, decoded: true)
        }
        return value
    }

    /// Değeri kodlar ve çözülmüş hâliyle saklar. nil ya da kodlanamayan değerde kayıt silinir ve nil döner.
    func encode<T: Encodable & Sendable>(_ id: UUID, _ field: String, _ value: T?) -> Data? {
        let key = Key(id: id, field: field)
        guard let value, let data = try? JSONEncoder().encode(value) else {
            lock.withLock { drop(key) }
            return nil
        }
        lock.withLock {
            clock += 1
            put(key, data, ObjectIdentifier(T.self), value, decoded: false)
        }
        return data
    }

    /// `url`deki şekil listesi. Dosya yoksa okumadan boş döner; damga (boyut + değişim zamanı) aynıysa yeniden okunmaz.
    func figures(_ id: UUID, at url: URL) -> [SourceFigure] {
        guard let stamp = WordSync.AudioStamp(of: url) else {
            lock.withLock { files[id] = nil }
            return []
        }
        let cached = lock.withLock { () -> [SourceFigure]? in
            clock += 1
            guard let entry = files[id], Self.same(entry.stamp, stamp) else { return nil }
            files[id]?.order = clock
            return entry.value
        }
        if let cached { return cached }
        let value = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([SourceFigure].self, from: $0) } ?? []
        lock.withLock {
            fileReads += 1
            putFigures(id, stamp, value)
        }
        return value
    }

    /// Az önce `url`ye yazılan liste (ardından gelen okuma dosyayı açmasın).
    func storeFigures(_ id: UUID, _ value: [SourceFigure], at url: URL) {
        let stamp = WordSync.AudioStamp(of: url)
        lock.withLock {
            guard let stamp else {
                files[id] = nil
                return
            }
            clock += 1
            putFigures(id, stamp, value)
        }
    }

    func remove(_ id: UUID) {
        lock.withLock {
            for key in entries.keys.filter({ $0.id == id }) { drop(key) }
            files[id] = nil
        }
    }

    func removeAll() {
        lock.withLock {
            entries = [:]
            files = [:]
            bytes = 0
        }
    }

    /// Önbellekte tolerans yok: `AudioStamp.==` yarım milisaniyeyi eşit sayar, burada birebir aranır.
    private static func same(_ a: WordSync.AudioStamp, _ b: WordSync.AudioStamp) -> Bool {
        a.size == b.size && a.modified == b.modified
    }

    // Aşağıdakiler kilit tutulurken çağrılır.

    private func drop(_ key: Key) {
        guard let old = entries.removeValue(forKey: key) else { return }
        bytes -= old.data.count
    }

    private func put(_ key: Key, _ data: Data, _ type: ObjectIdentifier, _ value: (any Sendable)?, decoded: Bool) {
        let decodes = (entries[key]?.decodes ?? 0) + (decoded ? 1 : 0)
        drop(key)
        entries[key] = Entry(data: data, type: type, value: value, order: clock, decodes: decodes)
        bytes += data.count
        // Tek kayıt bayt sınırını aşsa da kalır (yoksa büyük bir blob her okumada yeniden çözülürdü).
        while entries.count > limit || (bytes > byteLimit && entries.count > 1),
              let oldest = entries.min(by: { $0.value.order < $1.value.order })?.key {
            drop(oldest)
        }
    }

    private func putFigures(_ id: UUID, _ stamp: WordSync.AudioStamp, _ value: [SourceFigure]) {
        files[id] = FileEntry(stamp: stamp, value: value, order: clock)
        while files.count > limit, let oldest = files.min(by: { $0.value.order < $1.value.order })?.key {
            files[oldest] = nil
        }
    }
}

nonisolated enum EpisodeFiles {
    static let figuresName = "figures.json"
    /// Bölümlerin kök yolu. `root`tan farkı diske dokunmamasıdır (klasör oluşturmaz).
    static let location = URL.applicationSupportDirectory.appending(path: "Episodes", directoryHint: .isDirectory)

    static var root: URL {
        try? FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
        return location
    }

    static func directory(for id: UUID) -> URL {
        let dir = root.appending(path: id.uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Klasör OLUŞTURMAZ ve diske dokunmaz (şekil listesi her çizimde sorulur; silinmiş bölümün klasörü yeniden doğmasın).
    static func figuresURL(for id: UUID, root: URL = location) -> URL {
        root.appending(path: id.uuidString, directoryHint: .isDirectory).appending(path: figuresName)
    }

    static func deviceSceneURL(episode id: UUID, index: Int) -> URL {
        directory(for: id).appending(path: String(format: "apple_hd1_scene_%04d.wav", index))
    }

    static func sceneURL(episode id: UUID, index: Int) -> URL {
        directory(for: id).appending(path: String(format: "scene_%04d.wav", index))
    }

    static func remove(episode id: UUID) {
        try? FileManager.default.removeItem(at: root.appending(path: id.uuidString))
        EpisodeBlobCache.shared.remove(id)
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: root)
        EpisodeBlobCache.shared.removeAll()
    }
}
