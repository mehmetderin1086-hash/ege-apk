import Foundation
import SwiftData
import Testing
@testable import Ikra

/// Kütüphane iyileştirmeleri: bağlantı ipucu, hücresel yedek kısıtı, doğrulanan ve sürdürülebilen geri yükleme, belge kullanımı;
/// dalga 2: konu ağacı, seri sırası, podcast akışı, yedek kapsamı, yedek ekranı, araç kutusu birleştirme ve geri yükleme özeti.
@Suite @MainActor
struct ImproveKutuphaneTests {
    // MARK: - Yardımcılar

    private let sha = String(repeating: "a", count: 64)

    private func record(_ path: String, sha256: String? = nil, bytes: Int64 = 10) -> BackupFileRecord {
        BackupFileRecord(path: path, sha256: sha256 ?? sha, bytes: bytes, mtime: 0)
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ImproveKutuphane-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func memoryContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(AppDataStore.modelTypes), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func episode(_ title: String, series: UUID? = nil, index: Int = 0, created: TimeInterval = 0) -> Episode {
        let script = PodcastScript(title: title, summary: "", keyPoints: [], chapters: [], sourceNotes: "", quality: nil)
        let e = Episode(script: script, settings: PodcastSettings(), sourceNames: [], jobToken: "")
        e.statusRaw = EpisodeStatus.ready.rawValue
        e.createdAt = Date(timeIntervalSince1970: created)
        if let series {
            e.seriesID = series
            e.seriesTitle = "Seri"
            e.seriesIndex = index
        }
        return e
    }

    private func item(_ path: String, bytes: Int64) -> BackupItem {
        BackupItem(record: record(path, bytes: bytes), url: URL(fileURLWithPath: "/yok/\(path)"))
    }

    private func json(_ text: String) -> Data { Data(text.utf8) }

    private func objects(_ data: Data?) throws -> [[String: Any]] {
        let data = try #require(data)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    // MARK: - Madde 5: sunucu yeri ve metinler

    @Test func serverPlaceRecognizesHomeNetworkHosts() {
        for host in ["192.168.1.20", "mehmet-mac.local", "100.101.5.9", "localhost", "LOCALHOST", "10.0.0.7", "172.16.0.5", "172.31.255.1", "127.0.0.1"] {
            #expect(ServerPlace.isLocal(host: host), "\(host) yerel sayılmalı")
        }
        for host in ["ornek.com", "8.8.8.8", "172.32.0.1", "172.15.0.1", "192.169.1.1", "100.63.0.1", "100.128.0.1", "256.1.1.1", "10.0.0", "", "yerel.localhost.com"] {
            #expect(!ServerPlace.isLocal(host: host), "\(host) yerel sayılmamalı")
        }
        #expect(!ServerPlace.isLocal(host: nil))
    }

    @Test func connectionHintFollowsServerPlace() {
        let home = ServerPlace.connectionHint(host: "192.168.1.20")
        let remote = ServerPlace.connectionHint(host: "ornek.com")
        #expect(home.contains("aynı ağda"))
        #expect(remote.contains("İnternet bağlantını") && remote.contains("Sunucu adresini"))
        #expect(ServerPlace.connectionHint(host: nil) == remote)
        #expect(!home.contains("Mac") && !remote.contains("Mac"))
    }

    @Test func backupScreenTextsSayServerNotMac() {
        let texts = [MacBackupView.quotaText, MacBackupView.quotaBannerText, MacBackupView.holdText(.deviceEmpty),
                     MacBackupView.holdText(.foreignSnapshots), MacBackupView.networkText(cellular: false), MacBackupView.networkText(cellular: true)]
        for text in texts {
            #expect(!text.contains("Mac"), "\(text)")
        }
        #expect(MacBackupView.quotaText.contains("Sunucudaki yedek alanı doldu"))
        #expect(MacBackupView.quotaBannerText.contains("Sunucu yedeği"))
        #expect(MacBackupView.networkText(cellular: false).contains("Wi-Fi"))
        #expect(MacBackupView.networkText(cellular: true).contains("hücresel"))
    }

    // MARK: - Madde 3: otomatik yedek hücresel veride yüklemez

    @Test func automaticBackupIsWifiOnlyUnlessAllowed() {
        #expect(!MacBackup.allowsExpensive(manual: false, userAllowsCellular: false))
        #expect(MacBackup.allowsExpensive(manual: true, userAllowsCellular: false))
        #expect(MacBackup.allowsExpensive(manual: false, userAllowsCellular: true))
        #expect(MacBackup.allowsExpensive(manual: true, userAllowsCellular: true))
    }

    @Test func backupRequestNetworkPolicy() throws {
        let url = try #require(URL(string: "https://ornek.com/v1/backup/blob/x"))
        var restricted = URLRequest(url: url)
        BackupAPI.configure(&restricted, allowsExpensive: false)
        #expect(!restricted.allowsExpensiveNetworkAccess && !restricted.allowsConstrainedNetworkAccess)
        var open = URLRequest(url: url)
        BackupAPI.configure(&open, allowsExpensive: true)
        #expect(open.allowsExpensiveNetworkAccess && open.allowsConstrainedNetworkAccess)
    }

    // MARK: - Madde 4: geri yükleme planı, özet doğrulama, sürdürme

    @Test func restorePlanDropsFilesOfRecordsAlreadyOnDevice() {
        let episode = UUID(), newEpisode = UUID(), lesson = UUID(), newLesson = UUID()
        let files = [
            record("manifest.json"),
            record("Audio/\(episode.uuidString).m4a"),
            record("Audio/\(episode.uuidString.lowercased()).m4a"),
            record("Audio/\(newEpisode.uuidString).m4a"),
            record("EpisodeFiles/\(episode.uuidString)/figures.json"),
            record("EpisodeFiles/\(newEpisode.uuidString)/figures.json"),
            record("Videos/\(lesson.uuidString)/audio.m4a"),
            record("Videos/\(newLesson.uuidString)/frame_1.jpg"),
            // Belgeler kimliğe göre düşmez: dosya adı manifestteki kayıtla eşleşir.
            record("Documents/\(episode.uuidString).pdf"),
            record("VoiceNotes/not.m4a"),
            record("Tools/habits.json"),
            record("../x"),
            record("SceneMasters/a.caf"),
            record("Tools/kisa-ozet.json", sha256: String(repeating: "a", count: 63)),
            record("Tools/buyuk-harf.json", sha256: String(repeating: "A", count: 64)),
        ]
        let plan = MacBackup.restorePlan(files, existingEpisodes: [episode], existingLessons: [lesson]).map(\.path)
        #expect(plan == ["manifest.json", "Audio/\(newEpisode.uuidString).m4a", "EpisodeFiles/\(newEpisode.uuidString)/figures.json",
                         "Videos/\(newLesson.uuidString)/frame_1.jpg", "Documents/\(episode.uuidString).pdf", "VoiceNotes/not.m4a",
                         "Tools/habits.json"])
        // Boş cihaz: yalnız güvensiz yol ve geçersiz özet düşer.
        let fresh = MacBackup.restorePlan(files, existingEpisodes: [], existingLessons: [])
        #expect(fresh.count == files.count - 4)
        #expect(fresh.contains { $0.path == "manifest.json" })
    }

    @Test func restorePlanKeepsUnrecognizedNamesUnderKnownRoots() {
        // Kimliği çözülemeyen ad düşürülmez (eski davranış: indir, `Backup.restore` karar versin).
        let id = UUID()
        let files = [record("Audio/kapak.m4a"), record("Audio/\(id.uuidString).wav"), record("Audio/\(id.uuidString)/ek.m4a"),
                     record("EpisodeFiles/ortak/a.json"), record("Videos/ortak/a.json")]
        #expect(MacBackup.restorePlan(files, existingEpisodes: [id], existingLessons: [id]).count == files.count)
    }

    @Test func downloadedBlobHashMatchesKnownDigest() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "a.bin"), flipped = dir.appending(path: "b.bin"), empty = dir.appending(path: "c.bin")
        try Data("abc".utf8).write(to: file)
        try Data("abd".utf8).write(to: flipped)
        try Data().write(to: empty)
        let digest = try BackupBlobID.sha256(of: file)
        #expect(digest == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(BackupBlobID.isValid(digest))
        #expect(try BackupBlobID.sha256(of: flipped) != digest)
        #expect(try BackupBlobID.sha256(of: empty) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        // Yükleme önbelleği aynı işlevi kullanır.
        #expect(try BackupHashCache.sha256(of: file) == digest)
        #expect(throws: (any Error).self) { try BackupBlobID.sha256(of: dir.appending(path: "yok.bin")) }
    }

    @Test func stagedFileCountsOnlyWithExactSize() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "ses.m4a")
        try Data(repeating: 7, count: 1000).write(to: file)
        #expect(MacBackup.stagedIsComplete(url: file, bytes: 1000))
        #expect(!MacBackup.stagedIsComplete(url: file, bytes: 1001))
        #expect(!MacBackup.stagedIsComplete(url: file, bytes: 999))
        #expect(!MacBackup.stagedIsComplete(url: dir.appending(path: "yok.m4a"), bytes: 0))
    }

    @Test func stagedFileIsReusedOnlyWhenDigestStillMatches() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "manifest.json")
        try Data("abc".utf8).write(to: file)
        let abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        #expect(MacBackup.stagedMatches(url: file, record: record("manifest.json", sha256: abc, bytes: 3)))
        // Boyut aynı, içerik farklı: yeniden indirilir.
        try Data("abd".utf8).write(to: file)
        #expect(!MacBackup.stagedMatches(url: file, record: record("manifest.json", sha256: abc, bytes: 3)))
        #expect(!MacBackup.stagedMatches(url: file, record: record("manifest.json", sha256: abc, bytes: 4)))
        #expect(!MacBackup.stagedMatches(url: dir.appending(path: "yok.json"), record: record("yok.json", sha256: abc, bytes: 3)))
    }

    @Test func onlyTransientDownloadErrorsAreRetried() {
        let network = APIError.network(URLError(.networkConnectionLost))
        let mismatch = APIError(status: 0, code: APIError.backupHashMismatchCode, message: "Yedek dosyası bozuk indi.")
        let notFound = APIError(status: 404, code: "not_found", message: "Yedek dosyası indirilemedi (404).")
        #expect(MacBackup.isRetryableDownload(network))
        #expect(MacBackup.isRetryableDownload(mismatch))
        #expect(!MacBackup.isRetryableDownload(notFound))
        #expect(!MacBackup.isRetryableDownload(APIError(status: 401, code: "unauthorized", message: "")))
        #expect(!MacBackup.isRetryableDownload(CancellationError()))
        #expect(MacBackup.downloadRetryDelays == [1, 3])
        // Sürdürülebilen hatada kullanıcıya söylenir.
        #expect(MacBackup.restoreFailureText(network).contains("kaldığı yerden"))
        #expect(MacBackup.restoreFailureText(notFound) == notFound.message)
    }

    @Test func restoreProgressFollowsBytes() {
        #expect(MacBackup.restoreProgress(done: 0, total: 1000) == 0)
        #expect(MacBackup.restoreProgress(done: 250, total: 1000) == 0.25)
        #expect(MacBackup.restoreProgress(done: 1000, total: 1000) == 1)
        #expect(MacBackup.restoreProgress(done: 1500, total: 1000) == 1)
        #expect(MacBackup.restoreProgress(done: 0, total: 0) == 1)
    }

    @Test func stagingFolderNameIsSafeAndStable() {
        let name = MacBackup.stagingName(snapshotID: "../../etc/passwd")
        #expect(BackupBlobID.isValid(name))
        #expect(name == MacBackup.stagingName(snapshotID: "../../etc/passwd"))
        #expect(name != MacBackup.stagingName(snapshotID: "snap-1"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(!MacBackup.isStagingStale(created: now.addingTimeInterval(-3600), now: now))
        #expect(!MacBackup.isStagingStale(created: now.addingTimeInterval(-6 * 86_400), now: now))
        #expect(MacBackup.isStagingStale(created: now.addingTimeInterval(-8 * 86_400), now: now))
        #expect(MacBackup.isStagingStale(created: nil, now: now))
        // Saat geri alındıysa (oluşturma gelecekte) silinmez.
        #expect(!MacBackup.isStagingStale(created: now.addingTimeInterval(3600), now: now))
    }

    @Test func restoreWarningTextIsUnchanged() {
        #expect(Backup.RestoreWarning(added: 3, skipped: 1).localizedDescription
                == "3 bölüm geri yüklendi; 1 bölümün ses dosyası yedekte bulunamadığı için atlandı.")
    }

    // MARK: - Madde 6: belge kullanımı ve önizleme adı

    @Test func documentUsageCountsEpisodesAndQueue() {
        let doc = UUID(), other = UUID(), unused = UUID()
        let episodeDocs = [[doc], [other, doc], [other], []]
        let queuedDocs = [[doc, other], [other]]
        let used = DocumentUsage.count(doc, episodeDocs: episodeDocs, queuedDocs: queuedDocs)
        #expect(used.episodes == 2 && used.queued == 1)
        let none = DocumentUsage.count(unused, episodeDocs: episodeDocs, queuedDocs: queuedDocs)
        #expect(none.episodes == 0 && none.queued == 0)
        #expect(DocumentUsage.suffix(used) == " · 2 bölümde · sırada 1 istek")
        #expect(DocumentUsage.suffix(none).isEmpty)
        #expect(DocumentUsage.suffix((episodes: 3, queued: 0)) == " · 3 bölümde")
    }

    @Test func documentDeleteMessageNamesWhatBreaks() {
        let used = DocumentUsage.deleteMessage(episodes: 3, queued: 2)
        #expect(used.contains("3 bölümün kaynağı") && used.contains("Sıradaki 2 istek") && used.contains("geri alınamaz"))
        let queuedOnly = DocumentUsage.deleteMessage(episodes: 0, queued: 1)
        #expect(queuedOnly.contains("Sıradaki 1 istek") && !queuedOnly.contains("bölümün kaynağı"))
        #expect(DocumentUsage.deleteMessage(episodes: 0, queued: 0) == "Belge dosyası bu cihazdan kalıcı olarak silinir.")
    }

    @Test func previewFileNameUsesDisplayNameAndStoredExtension() {
        let stored = "\(UUID().uuidString).pdf"
        #expect(DocumentPreview.fileName(name: "Biyoloji Ünite 3.pdf", storedFileName: stored) == "Biyoloji Ünite 3.pdf")
        #expect(DocumentPreview.fileName(name: "DERS.PDF", storedFileName: stored) == "DERS.PDF")
        #expect(DocumentPreview.fileName(name: "Not", storedFileName: "x.txt") == "Not.txt")
        #expect(DocumentPreview.fileName(name: "ders.docx", storedFileName: "x.txt") == "ders.docx.txt")
        #expect(DocumentPreview.fileName(name: "a/b:c\nd", storedFileName: "x.jpg") == "a-b-c-d.jpg")
        #expect(DocumentPreview.fileName(name: "  ", storedFileName: stored) == "Belge.pdf")
        #expect(DocumentPreview.fileName(name: "..", storedFileName: stored) == "Belge.pdf")
        let long = DocumentPreview.fileName(name: String(repeating: "u", count: 200) + ".pdf", storedFileName: stored)
        #expect(long.count == 84 && long.hasSuffix(".pdf"))
    }

    // MARK: - Dalga 2 · Madde 7: konunun geçtiği yerler

    @Test func topicRefTitlesKeepOrderAndDropDeletedEpisodes() {
        let a = UUID(), b = UUID(), deleted = UUID()
        let refs = [TopicTag.Ref(episodeID: b, chapter: 2), TopicTag.Ref(episodeID: deleted, chapter: 0),
                    TopicTag.Ref(episodeID: a, chapter: nil), TopicTag.Ref(episodeID: b, chapter: 5)]
        let places = TopicTree.refTitles(refs, titles: [a: "Hücre", b: "Mitoz"])
        #expect(places.map(\.title) == ["Mitoz", "Hücre", "Mitoz"])
        #expect(places.map(\.ref) == [refs[0], refs[2], refs[3]])
        #expect(TopicTree.refTitles(refs, titles: [:]).isEmpty)
        #expect(TopicTree.refTitles([], titles: [a: "Hücre"]).isEmpty)
    }

    // MARK: - Dalga 2 · Madde 8: seri sırasında boşluk kalmaz

    @Test func seriesCompactionClosesGapsAndReportsOnlyChanges() {
        let a = UUID(), b = UUID(), c = UUID()
        let t0 = Date(timeIntervalSince1970: 0), t1 = Date(timeIntervalSince1970: 100)
        // 1-2-3-4'ten 2. bölüm silindi.
        #expect(SeriesOps.compacted([(id: a, index: 1, createdAt: t0), (id: b, index: 3, createdAt: t0), (id: c, index: 4, createdAt: t0)]) == [b: 2, c: 3])
        // Zaten 1…n: değişiklik yok.
        #expect(SeriesOps.compacted([(id: b, index: 2, createdAt: t0), (id: a, index: 1, createdAt: t0)]).isEmpty)
        #expect(SeriesOps.compacted([]).isEmpty)
        // Aynı numarada eski oluşturulan önce.
        #expect(SeriesOps.compacted([(id: a, index: 2, createdAt: t1), (id: b, index: 2, createdAt: t0)]) == [b: 1])
        // İlk bölüm silindi: kalanlar 1'den başlar.
        #expect(SeriesOps.compacted([(id: a, index: 2, createdAt: t0), (id: b, index: 3, createdAt: t0)]) == [a: 1, b: 2])
    }

    @Test func deletingSeriesMemberRenumbersTheRest() throws {
        let context = try memoryContext()
        let series = UUID(), other = UUID()
        let first = episode("1", series: series, index: 1), middle = episode("2", series: series, index: 2), last = episode("3", series: series, index: 3)
        // Başka seri ve serisiz bölüm etkilenmez.
        let lone = episode("Tek"), elsewhere = episode("Öteki", series: other, index: 1)
        for e in [first, middle, last, lone, elsewhere] { context.insert(e) }
        try context.save()
        let deleted = middle.id
        context.delete(middle)
        try context.save()
        LibraryHooks.unlink(deleted: deleted, context: context)
        #expect(first.seriesIndex == 1 && last.seriesIndex == 2)
        #expect(lone.seriesIndex == 0 && elsewhere.seriesIndex == 1)
        // Yinelenen çağrı bir şey değiştirmez.
        LibraryHooks.unlink(deleted: deleted, context: context)
        #expect(first.seriesIndex == 1 && last.seriesIndex == 2)
    }

    @Test func movingEpisodeOutOfSeriesClosesOnlyThatSeries() throws {
        let context = try memoryContext()
        let series = UUID(), other = UUID()
        let a = episode("1", series: series, index: 1), b = episode("2", series: series, index: 2), c = episode("3", series: series, index: 3)
        let x = episode("x", series: other, index: 2)
        for e in [a, b, c, x] { context.insert(e) }
        try context.save()
        // Düzenle sayfası: bölüm "Seri yok"a alınır, eski serinin kalanları kapanır; başka serinin boşluğuna dokunulmaz.
        a.seriesID = nil
        a.seriesTitle = nil
        a.seriesIndex = 0
        #expect(SeriesOps.closeGaps(context: context, only: series, excluding: a.id))
        #expect(b.seriesIndex == 1 && c.seriesIndex == 2 && a.seriesIndex == 0 && x.seriesIndex == 2)
        #expect(!SeriesOps.closeGaps(context: context, only: series, excluding: a.id))
    }

    @Test func seriesWithQueuedPartIsNotRenumbered() throws {
        let context = try memoryContext()
        let series = UUID()
        // 2. bölüm kuyrukta (henüz bölüm kaydı yok): 1 ve 3 kapatılırsa gelen 2. bölümle numara çakışır.
        let first = episode("1", series: series, index: 1), third = episode("3", series: series, index: 3)
        var settings = PodcastSettings()
        settings.series = SeriesContext(id: series, name: "Seri", index: 2, total: 3, previousTitles: [], previousKeyPoints: [])
        context.insert(first)
        context.insert(third)
        context.insert(QueuedRequest(documentIDs: [], settings: settings, title: "2"))
        try context.save()
        #expect(!SeriesOps.closeGaps(context: context))
        #expect(first.seriesIndex == 1 && third.seriesIndex == 3)
    }

    // MARK: - Dalga 2 · Madde 9: Podcasts bağlantısı

    @Test func podcastsAppURLMapsSchemes() throws {
        let https = try #require(URL(string: "https://h/dersdas/v1/feed/x.xml"))
        #expect(PodcastFeed.podcastsAppURL(https)?.absoluteString == "podcasts://h/dersdas/v1/feed/x.xml")
        let http = try #require(URL(string: "http://192.168.1.20:8787/v1/feed/x.xml?t=1"))
        #expect(PodcastFeed.podcastsAppURL(http)?.absoluteString == "podcast://192.168.1.20:8787/v1/feed/x.xml?t=1")
        let upper = try #require(URL(string: "HTTPS://h/feed.xml"))
        #expect(PodcastFeed.podcastsAppURL(upper)?.scheme == "podcasts")
        #expect(PodcastFeed.podcastsAppURL(try #require(URL(string: "ftp://h/feed.xml"))) == nil)
        #expect(PodcastFeed.podcastsAppURL(try #require(URL(string: "feed.xml"))) == nil)
    }

    // MARK: - Dalga 2 · Madde 10: yedek kapsamı

    @Test func oversizedFilesAreSplitAndRemembered() {
        let small = item("Audio/\(UUID().uuidString).m4a", bytes: 199_000_000)
        let edge = item("Documents/a.pdf", bytes: MacBackup.maxBlobBytes)
        let big = item("Videos/\(UUID().uuidString)/audio.m4a", bytes: 201_000_000)
        let split = MacBackup.splitBySize([small, big, edge], limit: MacBackup.maxBlobBytes)
        #expect(split.kept == [small, edge] && split.oversized == [big])
        #expect(MacBackup.splitBySize([], limit: 10).kept.isEmpty)
        // Kayıt biçimi: "<yol>|<bayt>"; yolda `|` olsa da boyut sondadır, bozuk kayıt düşer.
        let entries = MacBackup.skippedEntries([big])
        #expect(entries == ["\(big.record.path)|201000000"])
        let parsed = MacBackup.parseSkipped(entries + ["Documents/a|b.pdf|5", "bozuk", "Audio/x.m4a|çok"])
        #expect(parsed.map(\.path) == [big.record.path, "Documents/a|b.pdf"] && parsed.map(\.bytes) == [201_000_000, 5])
    }

    @Test func backupPathOwnerAndSkippedText() {
        let id = UUID()
        #expect(MacBackup.ownerID(ofBackupPath: "Videos/\(id.uuidString)/audio.m4a") == id)
        #expect(MacBackup.ownerID(ofBackupPath: "Audio/\(id.uuidString).m4a") == id)
        #expect(MacBackup.ownerID(ofBackupPath: "EpisodeFiles/\(id.uuidString.lowercased())/figures.json") == id)
        #expect(MacBackup.ownerID(ofBackupPath: "Documents/\(id.uuidString).pdf") == nil)
        #expect(MacBackup.ownerID(ofBackupPath: "manifest.json") == nil)
        #expect(MacBackup.ownerID(ofBackupPath: "Videos/ortak/a.json") == nil)
        let one = MacBackup.skippedText([(name: "Fizik dersi", bytes: 231_000_000)])
        #expect(one.hasPrefix("1 dosya ") && one.contains("Fizik dersi (") && one.contains("yedeğe girmedi") && !one.contains("Mac"))
        let many = MacBackup.skippedText((1...5).map { (name: "Ders \($0)", bytes: Int64(300_000_000)) })
        #expect(many.hasPrefix("5 dosya ") && many.contains("Ders 3") && !many.contains("Ders 4") && many.contains("ve 2 dosya daha"))
    }

    @Test func manifestCarriesLessonProgressAndDocumentUsage() throws {
        let source = try memoryContext()
        let lesson = VideoLesson(url: "https://youtu.be/x")
        lesson.rewindTimes = [12, 40]
        lesson.playbackRate = 1.5
        lesson.watchedSeconds = 300
        source.insert(lesson)
        let fileName = "\(UUID().uuidString).txt"
        let document = SourceDocument(name: "Not.txt", kind: "text", fileName: fileName, pageCount: 0)
        document.addedAt = Date(timeIntervalSince1970: 1_600_000_000)
        document.lastUsedAt = Date(timeIntervalSince1970: 1_700_000_000)
        source.insert(document)
        try source.save()
        let folder = try tempDir()
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: DocumentStore.directory.appending(path: fileName))
        }
        try FileManager.default.createDirectory(at: folder.appending(path: "Documents"), withIntermediateDirectories: true)
        try Data("not".utf8).write(to: folder.appending(path: "Documents/\(fileName)"))
        try Backup.manifest(context: source).encoded().write(to: folder.appending(path: "manifest.json"))

        let target = try memoryContext()
        let summary = try Backup.restoreDetailed(from: folder, context: target)
        #expect(summary.lessons == 1 && summary.documents == 1 && summary.episodes == 0)
        let restoredLesson = try #require(try target.fetch(FetchDescriptor<VideoLesson>()).first)
        #expect(restoredLesson.id == lesson.id && restoredLesson.rewindTimes == [12, 40])
        #expect(restoredLesson.playbackRate == 1.5 && restoredLesson.watchedSeconds == 300)
        let restoredDocument = try #require(try target.fetch(FetchDescriptor<SourceDocument>()).first)
        #expect(restoredDocument.lastUsedAt == document.lastUsedAt && restoredDocument.addedAt == document.addedAt)
    }

    @Test func oldBackupRecordsDecodeWithoutNewFields() throws {
        // Dalga 2'den önceki yedek: ders ilerlemesi ve belge kullanım tarihi yok.
        let lesson = try JSONDecoder().decode(BackupManifest.VideoLessonDTO.self, from: json("""
        {"id":"\(UUID().uuidString)","url":"u","videoID":"EKGRs8q7HlA","title":"T","channel":"C","duration":60,"thumbnailURL":null,
         "language":"tr","source":"ai","createdAt":0,"lastPosition":0,"transcriptData":null,"episodeIDs":[],"favorite":false}
        """))
        #expect(lesson.rewindTimes == nil && lesson.playbackRate == nil && lesson.watchedSeconds == nil)
        let document = try JSONDecoder().decode(BackupManifest.DocumentDTO.self, from: json("""
        {"id":"\(UUID().uuidString)","name":"n","kindRaw":"pdf","fileName":"f.pdf","pageCount":3,"addedAt":0}
        """))
        #expect(document.lastUsedAt == nil && document.pageCount == 3)
        // Eski belge kaydı geri yüklenince kullanım tarihi eklenme tarihidir (bugün değil).
        let fileName = "\(UUID().uuidString).pdf"
        let added = Date(timeIntervalSince1970: 1_600_000_000)
        let manifest = BackupManifest(episodes: [], bookmarks: [], cards: [],
                                      documents: [.init(id: UUID(), name: "Eski", kindRaw: "pdf", fileName: fileName, pageCount: 1, addedAt: added)])
        let folder = try tempDir()
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: DocumentStore.directory.appending(path: fileName))
        }
        try FileManager.default.createDirectory(at: folder.appending(path: "Documents"), withIntermediateDirectories: true)
        try Data([1]).write(to: folder.appending(path: "Documents/\(fileName)"))
        try manifest.encoded().write(to: folder.appending(path: "manifest.json"))
        let target = try memoryContext()
        _ = try Backup.restore(from: folder, context: target)
        #expect(try target.fetch(FetchDescriptor<SourceDocument>()).first?.lastUsedAt == added)
    }

    @Test func backupCoversTermDictionaryAndPlayerPreferences() throws {
        let suite = "improve-kutuphane-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let terms = Data("[{\"from\":\"entegral\",\"to\":\"integral\"}]".utf8)
        defaults.set(terms, forKey: "lesson.termDictionary")
        defaults.set(Float(1.25), forKey: PlayerController.rateKey)
        defaults.set(true, forKey: PlayerController.skipSilenceKey)
        defaults.set(true, forKey: "studyPlan.notify")
        defaults.set(2, forKey: "deck.imageLevel")
        defaults.set("Genel", forKey: "questions.level")
        defaults.set(1.2, forKey: "reading.textSize")
        // Cihaza özgü olanlar ve desteklenmeyen türler (dizi, sözlük) yedeğe girmez.
        defaults.set(["a"], forKey: "feed.published")
        defaults.set(Date(), forKey: "backup.mac.lastAt")
        defaults.set(Data([1]), forKey: "player.queue")
        defaults.set("http://x", forKey: "dev.apiBaseURL")
        defaults.set(["x"], forKey: "assignments.remind")
        defaults.set(["a": "b"], forKey: "questions.panelModels")
        let collected = BackupManifest.collectPreferenceValues(defaults)
        #expect(collected["lesson.termDictionary"] == .data(terms))
        #expect(collected[PlayerController.rateKey] == .double(1.25) && collected[PlayerController.skipSilenceKey] == .bool(true))
        #expect(collected["studyPlan.notify"] == .bool(true) && collected["deck.imageLevel"] == .int(2))
        #expect(collected["questions.level"] == .string("Genel") && collected["reading.textSize"] == .double(1.2))
        for key in ["feed.published", "backup.mac.lastAt", "player.queue", "dev.apiBaseURL", "assignments.remind", "questions.panelModels"] {
            #expect(collected[key] == nil, "\(key) yedeğe girmemeli")
        }
        // JSON turundan sonra yeni cihaza uygulanır; oynatıcı hızı kendi okuyucusuyla geri gelir.
        let back = try JSONDecoder().decode([String: PrefValue].self, from: JSONEncoder().encode(collected))
        let freshSuite = "improve-kutuphane-\(UUID().uuidString)"
        let fresh = try #require(UserDefaults(suiteName: freshSuite))
        defer { fresh.removePersistentDomain(forName: freshSuite) }
        BackupManifest.applyPreferenceValues(back, to: fresh)
        #expect(fresh.data(forKey: "lesson.termDictionary") == terms)
        #expect(PlayerController.storedRate(fresh) == 1.25)
        #expect(fresh.bool(forKey: PlayerController.skipSilenceKey) && fresh.bool(forKey: "studyPlan.notify"))
        for key in ["weeklyRecap.auto", "autoStudyPack", "autoVerify", "showSlides", "soundDesign"] {
            #expect(BackupManifest.preferenceValueKeys.contains(key), "\(key)")
        }
    }

    // MARK: - Dalga 2 · Madde 11: yedek ekranı

    @Test func staleBackupWarningAfterThreeDays() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 86_400
        #expect(MacBackup.staleDays(lastAt: nil, now: now) == nil)
        #expect(MacBackup.staleDays(lastAt: now.addingTimeInterval(-2 * day), now: now) == nil)
        #expect(MacBackup.staleDays(lastAt: now.addingTimeInterval(-3 * day + 60), now: now) == nil)
        #expect(MacBackup.staleDays(lastAt: now.addingTimeInterval(-5 * day), now: now) == 5)
        #expect(MacBackup.staleDays(lastAt: now.addingTimeInterval(-5 * day - 3600), now: now) == 5)
        #expect(MacBackup.staleDays(lastAt: now.addingTimeInterval(day), now: now) == nil)
        let text = MacBackup.staleText(days: 5)
        #expect(text.contains("5 gün önce") && text.contains("Şimdi yedekle") && !text.contains("Mac"))
    }

    @Test func manualBackupContinuesOnlyWhileFilesAreUploaded() {
        #expect(MacBackup.shouldContinueManual(.partial(uploaded: 12), round: 0))
        #expect(MacBackup.shouldContinueManual(.partial(uploaded: 1), round: MacBackup.manualMaxRounds - 2))
        // Tur sınırı, ilerleme olmayan tur (iptal), bitiş, hata ve kota durdurur.
        #expect(!MacBackup.shouldContinueManual(.partial(uploaded: 1), round: MacBackup.manualMaxRounds - 1))
        #expect(!MacBackup.shouldContinueManual(.partial(uploaded: 0), round: 0))
        #expect(!MacBackup.shouldContinueManual(.done(files: 10, uploaded: 3), round: 0))
        #expect(!MacBackup.shouldContinueManual(.unavailable, round: 0))
        #expect(!MacBackup.shouldContinueManual(.busy, round: 0))
        #expect(!MacBackup.shouldContinueManual(.failed("x"), round: 0))
        #expect(!MacBackup.shouldContinueManual(.quotaExceeded("x"), round: 0))
        #expect(!MacBackup.shouldContinueManual(.held(.deviceEmpty), round: 0))
        #expect(MacBackup.manualMaxRounds == 40)
        #expect(MacBackup.backupStoppedText.contains("sunucuda kaldı") && !MacBackup.backupStoppedText.contains("Mac"))
        #expect(MacBackup.restoreStoppedText.contains("kaldığı yerden") && !MacBackup.restoreStoppedText.contains("Mac"))
    }

    // MARK: - Dalga 2 · Madde 12: araç kutusu birleştirme, dosyasız kayıt, özet

    @Test func toolArraysMergeByIdKeepingDeviceRecords() throws {
        let merged = try objects(Backup.mergedToolArray(existing: json(#"[{"id":"A","x":1}]"#),
                                                        incoming: json(#"[{"id":"A","x":2},{"id":"B","x":3}]"#)))
        #expect(merged.count == 2)
        #expect(merged[0]["id"] as? String == "A" && merged[0]["x"] as? Int == 1)
        #expect(merged[1]["id"] as? String == "B" && merged[1]["x"] as? Int == 3)
        // Yedekte yeni kimlik yok: dosyaya dokunulmaz.
        #expect(Backup.mergedToolArray(existing: json(#"[{"id":"A"},{"id":"B"}]"#), incoming: json(#"[{"id":"B"},{"id":"A"}]"#)) == nil)
        #expect(Backup.mergedToolArray(existing: json(#"[{"id":"A"}]"#), incoming: json("[]")) == nil)
        // Biçim uymuyor: dizi değil, öğe nesne değil, `id` yok ya da tanınmayan türde.
        #expect(Backup.mergedToolArray(existing: json(#"{"id":"A"}"#), incoming: json(#"[{"id":"B"}]"#)) == nil)
        #expect(Backup.mergedToolArray(existing: json(#"[{"id":"A"}]"#), incoming: json(#"{"id":"B"}"#)) == nil)
        #expect(Backup.mergedToolArray(existing: json("[1,2]"), incoming: json(#"[{"id":"B"}]"#)) == nil)
        #expect(Backup.mergedToolArray(existing: json(#"[{"ad":"A"}]"#), incoming: json(#"[{"id":"B"}]"#)) == nil)
        #expect(Backup.mergedToolArray(existing: json(#"[{"id":"A"}]"#), incoming: json(#"[{"id":"B"},{"x":1}]"#)) == nil)
        #expect(Backup.mergedToolArray(existing: json(#"[{"id":["A"]}]"#), incoming: json(#"[{"id":"B"}]"#)) == nil)
        #expect(Backup.mergedToolArray(existing: json("bozuk"), incoming: json(#"[{"id":"B"}]"#)) == nil)
        // Boş cihaz deposu yedektekileri alır; sayı kimlikler de eşleşir, yedekte yinelenen kimlik bir kez eklenir.
        #expect(try objects(Backup.mergedToolArray(existing: json("[]"), incoming: json(#"[{"id":"B"}]"#))).count == 1)
        let numeric = try objects(Backup.mergedToolArray(existing: json(#"[{"id":1}]"#), incoming: json(#"[{"id":1},{"id":2},{"id":2}]"#)))
        #expect(numeric.map { $0["id"] as? Int } == [1, 2])
    }

    @Test func mergedToolStoreDecodesWithSameValues() throws {
        // Gerçek depo biçimi (JSONEncoder: tarih Double, UUID metin): birleşim sonrası her alan aynı değerle çözülür.
        let device = [ToolRow(id: UUID(), title: "Türkçe ödev / \"deneme\"", date: Date(timeIntervalSinceReferenceDate: 781_234_567.123456), done: true,
                          ratio: 0.1, count: 3, note: nil, tags: ["a", "b"]),
                      ToolRow(id: UUID(), title: "", date: Date(timeIntervalSinceReferenceDate: 0.000001), done: false, ratio: 1.0 / 3.0,
                          count: -7, note: "not", tags: [])]
        let extra = ToolRow(id: UUID(), title: "Yedekten", date: Date(timeIntervalSinceReferenceDate: 700_000_000.5), done: false,
                        ratio: 2.5, count: 1, note: "x", tags: ["c"])
        var changedCopy = device[0]
        changedCopy.title = "Yedekteki eski hâl"
        let merged = try #require(Backup.mergedToolArray(existing: JSONEncoder().encode(device), incoming: JSONEncoder().encode([changedCopy, extra])))
        #expect(try JSONDecoder().decode([ToolRow].self, from: merged) == device + [extra])
    }

    @Test func restoreToolsCopiesMissingMergesExistingAndKeepsDrawing() throws {
        let base = try tempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appending(path: "yedek"), target = base.appending(path: "cihaz")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        // Bilinen depo: aynı kimlik cihazdaki hâliyle kalır, yalnız yedekteki kayıt eklenir.
        let shared = TodoItem(title: "Ortak", createdAt: Date(timeIntervalSinceReferenceDate: 700_000_000.25))
        var sharedInBackup = shared
        sharedInBackup.title = "Yedekteki eski ad"
        let onlyInBackup = TodoItem(title: "Yalnız yedekte", urgent: true, createdAt: Date(timeIntervalSinceReferenceDate: 710_000_000.5))
        try JSONEncoder().encode([sharedInBackup, onlyInBackup]).write(to: source.appending(path: "todos.json"))
        try JSONEncoder().encode([shared]).write(to: target.appending(path: "todos.json"))
        // Cihazda olmayan dosya olduğu gibi kopyalanır.
        let habits = [Habit(name: "Kitap", days: ["2026-10-01"]), Habit(name: "Paragraf"), Habit(name: "Erken yat")]
        try JSONEncoder().encode(habits).write(to: source.appending(path: "habits.json"))
        // Şeması uymayan yedek kaydı (zorunlu alan yok): birleşim yazılmaz, cihaz dosyası baytı baytına kalır.
        let quotes = try JSONEncoder().encode([OwnQuote(text: "Cihazdaki söz")])
        try quotes.write(to: target.appending(path: "quotes.json"))
        try json(#"[{"id":"\#(UUID().uuidString)"}]"#).write(to: source.appending(path: "quotes.json"))
        // Tanınmayan depo birleştirilmez; çizim, kenara alınmış bozuk dosya ve tek nesneli dosya ezilmez.
        try json(#"[{"id":"B"}]"#).write(to: source.appending(path: "yeni-arac.json"))
        try json(#"[{"id":"A"}]"#).write(to: target.appending(path: "yeni-arac.json"))
        try json("yedek çizim").write(to: source.appending(path: "whiteboard.drawing"))
        try json("cihaz çizim").write(to: target.appending(path: "whiteboard.drawing"))
        try json(#"[{"id":"Z"}]"#).write(to: source.appending(path: "todos.bozuk-1.json"))
        try json("cihazdaki bozuk").write(to: target.appending(path: "todos.bozuk-1.json"))
        try json(#"{"ayar":1}"#).write(to: source.appending(path: "tek.json"))
        try json(#"{"ayar":2}"#).write(to: target.appending(path: "tek.json"))
        try json("x").write(to: source.appending(path: "ilgisiz.txt"))

        // 1 birleşen kayıt (yalnız yedekteki yapılacak) + 3 kopyalanan kayıt (alışkanlıklar).
        #expect(Backup.restoreTools(from: source, to: target) == 4)
        #expect(try JSONDecoder().decode([TodoItem].self, from: Data(contentsOf: target.appending(path: "todos.json"))) == [shared, onlyInBackup])
        #expect(try JSONDecoder().decode([Habit].self, from: Data(contentsOf: target.appending(path: "habits.json"))) == habits)
        #expect(try Data(contentsOf: target.appending(path: "quotes.json")) == quotes)
        #expect(try Data(contentsOf: target.appending(path: "yeni-arac.json")) == json(#"[{"id":"A"}]"#))
        #expect(try Data(contentsOf: target.appending(path: "whiteboard.drawing")) == json("cihaz çizim"))
        #expect(try Data(contentsOf: target.appending(path: "todos.bozuk-1.json")) == json("cihazdaki bozuk"))
        #expect(try Data(contentsOf: target.appending(path: "tek.json")) == json(#"{"ayar":2}"#))
        #expect(!FileManager.default.fileExists(atPath: target.appending(path: "ilgisiz.txt").path))
        // İkinci geri yükleme bir şey eklemez; olmayan klasör sorun değildir.
        #expect(Backup.restoreTools(from: source, to: target) == 0)
        #expect(Backup.restoreTools(from: base.appending(path: "yok"), to: target) == 0)
        // Hedef klasör yoksa oluşturulur ve her dosya kopyalanır (2 + 3 + 1 + 1 + 1 + 1 + 1 kayıt).
        let fresh = base.appending(path: "yeni")
        #expect(Backup.restoreTools(from: source, to: fresh) == 10)
        #expect(try Data(contentsOf: fresh.appending(path: "whiteboard.drawing")) == json("yedek çizim"))
    }

    @Test func toolMergeIsWrittenOnlyWhenTheStoreStillDecodes() throws {
        let mine = TodoItem(title: "Cihazdaki", createdAt: Date(timeIntervalSinceReferenceDate: 700_000_000.125))
        let theirs = TodoItem(title: "Yedekteki", createdAt: Date(timeIntervalSinceReferenceDate: 690_000_000))
        let existing = try JSONEncoder().encode([mine])
        let merged = try #require(Backup.mergedToolArray(existing: existing, incoming: JSONEncoder().encode([theirs])))
        #expect(Backup.toolMergeIsSafe(store: "todos", existing: existing, merged: merged) == true)
        // Yanlış türle (başka deponun kayıtları) çözülemez: yazılmaz.
        #expect(Backup.toolMergeIsSafe(store: "habits", existing: existing, merged: merged) == false)
        // Zorunlu alanı olmayan yedek kaydı JSON düzeyinde birleşir ama depo türüyle çözülemez: yazılmaz.
        let broken = try #require(Backup.mergedToolArray(existing: existing, incoming: json(#"[{"id":"\#(UUID().uuidString)","title":"eksik"}]"#)))
        #expect(Backup.toolMergeIsSafe(store: "todos", existing: existing, merged: broken) == false)
        // Cihaz dosyası zaten okunamıyorsa dokunulmaz (depo onu kendisi kenara alır).
        #expect(Backup.toolMergeIsSafe(store: "todos", existing: json(#"[{"id":"x"}]"#), merged: merged) == false)
        // Tanınmayan depo: birleştirme yapılmaz.
        #expect(Backup.toolMergeIsSafe(store: "yeni-arac", existing: existing, merged: merged) == nil)
        for store in ["habits", "goals", "todos", "journal", "revisions", "books", "quotes", "mock-exams", "grades", "absences", "countdowns", "questions"] {
            #expect(Backup.toolMergeIsSafe(store: store, existing: json("[]"), merged: json("[]")) == false, "\(store) tanınmalı")
        }
    }

    @Test func restoreSkipsRecordsWhoseFilesAreMissing() throws {
        let target = try memoryContext()
        let existing = episode("Cihazdaki")
        target.insert(existing)
        try target.save()
        let voiceName = "improve-\(UUID().uuidString).m4a", missingVoice = "improve-\(UUID().uuidString).m4a"
        let withVoice = UUID(), withoutVoice = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manifest = BackupManifest(
            episodes: [],
            bookmarks: [.init(id: withoutVoice, episodeID: existing.id, episodeTitle: "", time: 1, text: "a", note: "", createdAt: now, audioFileName: missingVoice),
                        .init(id: withVoice, episodeID: existing.id, episodeTitle: "", time: 2, text: "b", note: "", createdAt: now, audioFileName: voiceName)],
            cards: [],
            documents: [.init(id: UUID(), name: "Dosyasız", kindRaw: "pdf", fileName: "\(UUID().uuidString).pdf", pageCount: 1, addedAt: now),
                        .init(id: UUID(), name: "Adsız", kindRaw: "pdf", fileName: "", pageCount: 1, addedAt: now)])
        let folder = try tempDir()
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: VoiceNotes.url(voiceName))
        }
        try FileManager.default.createDirectory(at: folder.appending(path: "VoiceNotes"), withIntermediateDirectories: true)
        try Data([1, 2]).write(to: folder.appending(path: "VoiceNotes/\(voiceName)"))
        try manifest.encoded().write(to: folder.appending(path: "manifest.json"))

        let summary = try Backup.restoreDetailed(from: folder, context: target)
        // Dosyası gelmeyen belge kaydı eklenmez; yer imi eklenir ama çalmayacak sesli nota bağlanmaz.
        #expect(try target.fetchCount(FetchDescriptor<SourceDocument>()) == 0)
        #expect(summary.documents == 0 && summary.bookmarks == 2 && summary.episodes == 0)
        let marks = try target.fetch(FetchDescriptor<Bookmark>())
        #expect(marks.first { $0.id == withoutVoice }?.audioFileName == nil)
        #expect(marks.first { $0.id == withVoice }?.audioFileName == voiceName)
        #expect(summary.text == "2 bölüm notu eklendi.")
        // İkinci kez: hepsi cihazda.
        #expect(try Backup.restoreDetailed(from: folder, context: target).text == "Yeni kayıt yok; yedektekilerin hepsi cihazda.")
    }

    @Test func restoreSummaryTextNamesWhatWasAdded() {
        #expect(Backup.RestoreSummary(cards: 5).text == "5 kart eklendi.")
        #expect(Backup.RestoreSummary().text == "Yeni kayıt yok; yedektekilerin hepsi cihazda.")
        #expect(Backup.RestoreSummary(episodes: 3, cards: 120, notes: 4).text == "3 bölüm, 120 kart, 4 Cornell notu eklendi.")
        #expect(Backup.RestoreSummary(lessons: 1, documents: 2, toolItems: 7, other: 9).text == "1 video dersi, 2 belge, 7 araç kaydı, 9 diğer kayıt eklendi.")
        #expect(Backup.RestoreSummary(cards: 2, skippedEpisodes: 1).text
                == "2 kart eklendi. 1 bölümün ses dosyası yedekte bulunamadığı için atlandı.")
        #expect(Backup.RestoreSummary(skippedEpisodes: 2).text == "Yeni kayıt eklenmedi. 2 bölümün ses dosyası yedekte bulunamadığı için atlandı.")
    }

    @Test func restoreWithoutAudioCountsSkippedAndOldEntryPointStillThrows() throws {
        let source = try memoryContext()
        let lost = episode("Sesi yok")
        source.insert(lost)
        source.insert(ReviewCard(episodeID: lost.id, episodeTitle: lost.title, kind: .flashcard, front: "ö", back: "a", sourcePage: nil))
        try source.save()
        let folder = try tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Backup.manifest(context: source).encoded().write(to: folder.appending(path: "manifest.json"))

        // Ayrıntılı giriş: atlanan bölüm hata değildir, kart yine eklenir.
        let detailed = try memoryContext()
        let summary = try Backup.restoreDetailed(from: folder, context: detailed)
        #expect(summary.episodes == 0 && summary.skippedEpisodes == 1 && summary.cards == 1)
        #expect(try detailed.fetchCount(FetchDescriptor<Episode>()) == 0)
        // Eski giriş (Ayarlar → klasörden geri yükle) aynı uyarıyı fırlatmaya devam eder.
        let legacy = try memoryContext()
        do {
            _ = try Backup.restore(from: folder, context: legacy)
            Issue.record("Sesi olmayan bölümde RestoreWarning bekleniyordu.")
        } catch let warning as Backup.RestoreWarning {
            #expect(warning.added == 0 && warning.skipped == 1)
        }
        #expect(try legacy.fetchCount(FetchDescriptor<ReviewCard>()) == 1)
    }

    // MARK: - İnceleme 2 · Bulgu 1: geri yüklenen yedeğin satırında gösterge

    @Test func snapshotRowShowsSpinnerWhileDeletingOrRestoringThatSnapshot() {
        #expect(MacBackupView.rowIsWorking("a", deleting: nil, restoring: "a"))
        #expect(MacBackupView.rowIsWorking("a", deleting: "a", restoring: nil))
        #expect(!MacBackupView.rowIsWorking("a", deleting: nil, restoring: "b"))
        #expect(!MacBackupView.rowIsWorking("a", deleting: "b", restoring: nil))
        #expect(!MacBackupView.rowIsWorking("a", deleting: nil, restoring: nil))
    }

    // MARK: - İnceleme 2 · Bulgu 2: araç kutusu geri yüklemesi açık depolara haber verir

    @Test func toolRestoreNotifiesOpenStoresOnlyWhenRecordsWereAdded() throws {
        let base = try tempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appending(path: "yedek"), target = base.appending(path: "cihaz")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let mine = TodoItem(title: "Cihazdaki", createdAt: Date(timeIntervalSinceReferenceDate: 700_000_000.25))
        let theirs = TodoItem(title: "Yedekteki", createdAt: Date(timeIntervalSinceReferenceDate: 710_000_000.5))
        try JSONEncoder().encode([mine]).write(to: target.appending(path: "todos.json"))
        try JSONEncoder().encode([mine, theirs]).write(to: source.appending(path: "todos.json"))

        // Ad `JSONStore` ile ortak sözleşmedir.
        #expect(Backup.toolsRestored.rawValue == "dersdas.tools.restored")
        let center = NotificationCenter()
        let posts = PostCounter()
        let token = center.addObserver(forName: Backup.toolsRestored, object: nil, queue: nil) { _ in posts.increment() }
        defer { center.removeObserver(token) }

        // Birleşim dosyaya yazıldı: haber, çağrı dönmeden bir kez yayımlanır.
        #expect(Backup.restoreToolsAndNotify(from: source, to: target, center: center) == 1)
        #expect(posts.value == 1)
        #expect(try JSONDecoder().decode([TodoItem].self, from: Data(contentsOf: target.appending(path: "todos.json"))) == [mine, theirs])
        // Eklenecek kayıt yok (ikinci geri yükleme, olmayan klasör): dosyaya dokunulmaz, haber de yok.
        #expect(Backup.restoreToolsAndNotify(from: source, to: target, center: center) == 0)
        #expect(Backup.restoreToolsAndNotify(from: base.appending(path: "yok"), to: target, center: center) == 0)
        #expect(posts.value == 1)
        // Cihazda olmayan dosyanın kopyalanması da haber verir (açık depo boş listeyle üstüne yazmasın).
        try FileManager.default.removeItem(at: target.appending(path: "todos.json"))
        #expect(Backup.restoreToolsAndNotify(from: source, to: target, center: center) == 2)
        #expect(posts.value == 2)
    }

    /// Bulgudaki senaryo uçtan uca (haberi `JSONStore` dinler): geri yükleme sırasında açık olan depo, sonraki ilk
    /// değişikliğinde bellekteki eski listeyi yazıp yedekten eklenenleri silmez.
    @Test func openToolStoreKeepsRestoredRecordsOnItsNextChange() throws {
        let base = try tempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appending(path: "yedek"), target = base.appending(path: "cihaz")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let mine = TodoItem(title: "Cihazdaki", createdAt: Date(timeIntervalSinceReferenceDate: 700_000_000.25))
        let theirs = TodoItem(title: "Yedekteki", createdAt: Date(timeIntervalSinceReferenceDate: 710_000_000.5))
        try JSONEncoder().encode([mine]).write(to: target.appending(path: "todos.json"))
        try JSONEncoder().encode([theirs]).write(to: source.appending(path: "todos.json"))

        let open = JSONStore<TodoItem>("todos", directory: target)
        #expect(open.items == [mine])
        #expect(Backup.restoreToolsAndNotify(from: source, to: target) == 1)
        #expect(open.items == [mine, theirs])
        open.items[0].done = true
        let onDisk = try JSONDecoder().decode([TodoItem].self, from: Data(contentsOf: target.appending(path: "todos.json")))
        #expect(onDisk.map(\.id) == [mine.id, theirs.id])
        #expect(onDisk.first?.done == true)
    }
}

/// Bildirim sayacı (gözlemci kapanışı `@Sendable`).
nonisolated private final class PostCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

/// Araç kutusu deposu örneği (`JSONStore` öğeleri gibi JSONEncoder ile yazılır).
nonisolated private struct ToolRow: Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var date: Date
    var done: Bool
    var ratio: Double
    var count: Int
    var note: String?
    var tags: [String]
}
