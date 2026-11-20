import Foundation

/// #10/#48: bölüm sahnelerinin kayıpsız (WAV) kopyaları. Varsa sahne düzenleme, AAC'yi tekrar tekrar çözüp kodlamak
/// yerine bunlardan yeniden birleştirir. Yer: Caches/SceneMasters/<bölüm>/ (yedeğe girmez; sistem gerekirse siler).
/// Saklama sınırı: son 10 bölüm, toplam 1,5 GB, 30 gün.
nonisolated enum SceneMasters {
    static let markerName = "complete.json"
    static let undoName = "undo_scene.wav"
    /// Düzenleme sürerken değiştirilen sahnenin eski hâli; düzenleme başarılı olunca `undoName` olur.
    static let pendingName = "undo_pending.wav"
    /// Bekleyen dosyanın hangi sahneye ait olduğu ({"scene": N}); yarıda kesilen değişimi geri almak için.
    static let pendingInfoName = "undo_pending.json"

    /// `design`/`identity`: birleştirmede kullanılan ses tasarımı ve GENEL ses kimliği (bölüme özel seçim yoksa geçerli).
    /// Eski kayıtlarda yoktur (nil → bugünkü genel ayar).
    private struct Marker: Codable { var count: Int; var design: Bool?; var identity: String? }
    /// Aynı seçenekler bölüm klasöründe de durur (kopyalar temizlense de m4a yolundaki düzenleme üretimdeki
    /// mastering kararını kullansın).
    private struct Sound: Codable { var design: Bool; var identity: String }
    private struct Pending: Codable { var scene: Int }
    static let soundFileName = "sound-options.json"

    static var root: URL { URL.cachesDirectory.appending(path: "SceneMasters", directoryHint: .isDirectory) }

    static func directory(_ id: UUID, root: URL = root) -> URL { root.appending(path: id.uuidString, directoryHint: .isDirectory) }

    static func url(_ id: UUID, scene: Int, root: URL = root) -> URL {
        directory(id, root: root).appending(path: String(format: "scene_%04d.wav", scene))
    }

    /// scenes[i] = küresel sahne i'nin WAV'ı. `design`/`identity` verilmezse çağrı anındaki genel ayar saklanır
    /// (üretim bunu birleştirmenin hemen ardından çağırır; yeniden birleştirme aynı müziği kullanır).
    static func store(episodeID: UUID, scenes: [URL], design: Bool? = nil, identity: SoundIdentity? = nil) async throws {
        let design = design ?? SoundDesign.isEnabled
        let identity = identity ?? SoundIdentity.current
        try await Task.detached(priority: .utility) {
            saveSound(episodeID, design: design, identity: identity)
            try store(episodeID: episodeID, scenes: scenes, root: root, design: design, identity: identity)
            purge()
        }.value
    }

    /// Bölüm klasörüne (varsa; silinmiş bölümün klasörü yeniden oluşturulmaz) üretimdeki ses seçeneklerini yazar.
    static func saveSound(_ id: UUID, design: Bool, identity: SoundIdentity, episodes: URL = EpisodeFiles.root) {
        let dir = episodes.appending(path: id.uuidString, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: dir.path),
              let data = try? JSONEncoder().encode(Sound(design: design, identity: identity.rawValue)) else { return }
        try? data.write(to: dir.appending(path: soundFileName), options: .atomic)
    }

    private static func savedSound(_ id: UUID, episodes: URL) -> Sound? {
        let url = episodes.appending(path: id.uuidString, directoryHint: .isDirectory).appending(path: soundFileName)
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Sound.self, from: $0) }
    }

    static func store(episodeID: UUID, scenes: [URL], root: URL,
                      design: Bool = SoundDesign.isEnabled, identity: SoundIdentity = .current) throws {
        let fm = FileManager.default
        let dir = directory(episodeID, root: root)
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            for (i, source) in scenes.enumerated() {
                try fm.copyItem(at: source, to: url(episodeID, scene: i, root: root))   // APFS'de kopya yer tutmaz
            }
            try JSONEncoder().encode(Marker(count: scenes.count, design: design, identity: identity.rawValue))
                .write(to: dir.appending(path: markerName), options: .atomic)
        } catch {
            try? fm.removeItem(at: dir)
            throw error
        }
    }

    static func exists(_ id: UUID, root: URL = root) -> Bool { count(id, root: root) != nil }

    private static func marker(_ id: UUID, root: URL) -> Marker? {
        guard let data = try? Data(contentsOf: directory(id, root: root).appending(path: markerName)) else { return nil }
        return try? JSONDecoder().decode(Marker.self, from: data)
    }

    /// Tam saklanmış sahne sayısı (yoksa nil).
    static func count(_ id: UUID, root: URL = root) -> Int? { marker(id, root: root)?.count }

    /// Kayıpsız yeniden birleştirme mümkün mü: sayı tutuyor ve her sahne dosyası yerinde.
    static func isComplete(_ id: UUID, scenes: Int, root: URL = root) -> Bool {
        recoverInterrupted(id, root: root)
        guard scenes > 0, count(id, root: root) == scenes else { return false }
        return (0..<scenes).allSatisfy { FileManager.default.fileExists(atPath: url(id, scene: $0, root: root).path) }
    }

    /// Yeniden birleştirme seçenekleri: bölüme özel kimlik (`episodeIdentity`) varsa o, yoksa üretimde saklanan genel
    /// kimlik; ses tasarımı (mastering + müzik) üretimdeki gibi. Kaynak sırası: kopya işareti → bölüm klasöründeki
    /// kayıt → bugünkü genel ayar (eski bölümler).
    static func stitchOptions(_ id: UUID, episodeIdentity: String?, root: URL = root,
                              episodes: URL = EpisodeFiles.root) -> (design: Bool, identity: SoundIdentity) {
        let marker = marker(id, root: root)
        let sound = marker?.design == nil ? savedSound(id, episodes: episodes) : nil
        let design = marker?.design ?? sound?.design ?? SoundDesign.isEnabled
        let identity = (marker?.identity ?? sound?.identity).flatMap(SoundIdentity.init(rawValue:)) ?? SoundIdentity.current
        return SoundIdentity.options(for: episodeIdentity, designEnabled: design, fallback: identity)
    }

    static func invalidate(_ id: UUID, root: URL = root) { try? FileManager.default.removeItem(at: directory(id, root: root)) }

    /// Tek sahneyi değiştirir; eskisi `pendingName` olarak bekler. Başarıda `commitReplace`, hatada `rollbackReplace`
    /// (önceki düzenlemenin geri alma kopyası ancak yeni düzenleme başarılı olunca değişir).
    static func replace(_ id: UUID, scene: Int, with wav: URL, root: URL = root) throws {
        recoverInterrupted(id, root: root)
        let fm = FileManager.default
        let dir = directory(id, root: root)
        let target = url(id, scene: scene, root: root)
        let pending = dir.appending(path: pendingName)
        try? fm.removeItem(at: pending)
        setLive(dir, true)
        do {
            if fm.fileExists(atPath: target.path) {
                // Taşımadan ÖNCE: uygulama yeniden birleştirme sürerken sonlanırsa hangi sahnenin geri konacağı bilinsin.
                try JSONEncoder().encode(Pending(scene: scene)).write(to: dir.appending(path: pendingInfoName), options: .atomic)
                try fm.moveItem(at: target, to: pending)
            }
            try fm.copyItem(at: wav, to: target)
        } catch {
            rollbackReplace(id, scene: scene, root: root)
            throw error
        }
        touch(id, root: root)
    }

    /// Düzenleme başarılı: eski sahne geri alma kopyası olur.
    static func commitReplace(_ id: UUID, root: URL = root) {
        let fm = FileManager.default
        let dir = directory(id, root: root)
        let pending = dir.appending(path: pendingName)
        let undo = dir.appending(path: undoName)
        try? fm.removeItem(at: undo)
        if fm.fileExists(atPath: pending.path) { try? fm.moveItem(at: pending, to: undo) }
        try? fm.removeItem(at: dir.appending(path: pendingInfoName))
        setLive(dir, false)
    }

    /// Düzenleme başarısız: sahne eski hâline döner, önceki geri alma kopyası olduğu gibi kalır.
    static func rollbackReplace(_ id: UUID, scene: Int, root: URL = root) {
        let fm = FileManager.default
        let dir = directory(id, root: root)
        let pending = dir.appending(path: pendingName)
        let target = url(id, scene: scene, root: root)
        defer {
            try? fm.removeItem(at: dir.appending(path: pendingInfoName))
            setLive(dir, false)
        }
        guard fm.fileExists(atPath: pending.path) else { return }
        try? fm.removeItem(at: target)
        try? fm.moveItem(at: pending, to: target)
    }

    // MARK: Yarıda kesilen değişim

    private static let liveLock = NSLock()
    /// Bu süreçte `replace` ile `commitReplace`/`rollbackReplace` arasında olan klasörler (yeniden birleştirme sürüyor).
    nonisolated(unsafe) private static var live = Set<String>()

    private static func setLive(_ dir: URL, _ on: Bool) {
        liveLock.withLock { if on { live.insert(dir.path) } else { live.remove(dir.path) } }
    }

    /// Testler: süreç `replace` ile onay arasında sonlanıp yeniden başlamış gibi.
    static func simulateRelaunch(_ id: UUID, root: URL = root) { setLive(directory(id, root: root), false) }

    /// Uygulama yeniden birleştirme sürerken sonlandıysa kopyalarda sahnenin onaylanmamış yeni hâli kalır; sayı ve
    /// dosyalar tam göründüğü için sonraki düzenleme bölümü, senaryosu eski kalan o sahnenin yeni sesiyle birleştirirdi.
    /// Bekleyen dosya, bu süreçte süren bir değişime ait değilse kalıntıdır: yan dosyadaki sahneye geri konur. Yan dosya
    /// yoksa (eski sürümden kalma) hangi sahne olduğu bilinemez, kopyalar silinir (düzenleme m4a yoluna düşer).
    /// İşlem yapıldıysa true.
    @discardableResult
    static func recoverInterrupted(_ id: UUID, root: URL = root) -> Bool {
        let fm = FileManager.default
        let dir = directory(id, root: root)
        guard !liveLock.withLock({ live.contains(dir.path) }) else { return false }
        let info = dir.appending(path: pendingInfoName)
        guard fm.fileExists(atPath: dir.appending(path: pendingName).path) else {
            try? fm.removeItem(at: info)
            return false
        }
        guard let scene = (try? Data(contentsOf: info)).flatMap({ try? JSONDecoder().decode(Pending.self, from: $0) })?.scene else {
            invalidate(id, root: root)
            return true
        }
        rollbackReplace(id, scene: scene, root: root)
        return true
    }

    /// Son başarılı `replace` öncesindeki sahneyi geri koyar; kopya yoksa false (çağıran kopyaları geçersiz kılar).
    @discardableResult
    static func restoreUndo(_ id: UUID, scene: Int, root: URL = root) -> Bool {
        // Önce kalıntı: aynı sahnenin yarıda kalan ikinci değişimi beklerken geri alınırsa, sonradan gelen kurtarma
        // geri konan sahnenin üzerine yazardı.
        recoverInterrupted(id, root: root)
        let fm = FileManager.default
        let undo = directory(id, root: root).appending(path: undoName)
        guard fm.fileExists(atPath: undo.path) else { return false }
        let target = url(id, scene: scene, root: root)
        try? fm.removeItem(at: target)
        guard (try? fm.moveItem(at: undo, to: target)) != nil else { return false }
        touch(id, root: root)
        return true
    }

    /// Kullanım zamanını günceller (saklama sırası buna göre).
    static func touch(_ id: UUID, root: URL = root) {
        try? FileManager.default.setAttributes([.modificationDate: Date.now],
                                               ofItemAtPath: directory(id, root: root).appending(path: markerName).path)
    }

    /// Saklama sınırını uygular; silinen bayt sayısını döner.
    @discardableResult
    static func purge(keepingRecent: Int = 10, maxBytes: Int64 = 1_500_000_000, maxAge: TimeInterval = 30 * 86_400) -> Int64 {
        purge(root: root, now: .now, keepingRecent: keepingRecent, maxBytes: maxBytes, maxAge: maxAge)
    }

    static func purge(root: URL, now: Date, keepingRecent: Int, maxBytes: Int64, maxAge: TimeInterval) -> Int64 {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return 0 }
        struct Entry { var url: URL; var used: Date; var bytes: Int64; var complete: Bool }
        var entries: [Entry] = []
        for dir in dirs where (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let marker = dir.appending(path: markerName)
            let complete = fm.fileExists(atPath: marker.path)
            let stamp = complete ? marker : dir
            let used = ((try? fm.attributesOfItem(atPath: stamp.path))?[.modificationDate] as? Date) ?? .distantPast
            var bytes: Int64 = 0
            for file in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? [] {
                bytes += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            entries.append(Entry(url: dir, used: used, bytes: bytes, complete: complete))
        }
        var removed: Int64 = 0
        func remove(_ e: Entry) {
            if (try? fm.removeItem(at: e.url)) != nil { removed += e.bytes }
        }
        // Yarım kalmış (işaretsiz) kayıtlar 1 saatten eskiyse kalıntıdır; sınırlara sayılmaz.
        for e in entries where !e.complete && now.timeIntervalSince(e.used) > 3600 { remove(e) }
        var kept: [Entry] = []
        for (i, e) in entries.filter(\.complete).sorted(by: { $0.used > $1.used }).enumerated() {
            if i >= keepingRecent || now.timeIntervalSince(e.used) > maxAge { remove(e) } else { kept.append(e) }
        }
        var total = kept.reduce(Int64(0)) { $0 + $1.bytes }
        while total > maxBytes, let oldest = kept.popLast() {
            total -= oldest.bytes
            remove(oldest)
        }
        return removed
    }
}
