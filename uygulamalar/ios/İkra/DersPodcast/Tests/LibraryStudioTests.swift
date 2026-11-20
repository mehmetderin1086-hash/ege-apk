import AVFoundation
import Foundation
import SwiftData
import Testing
import UIKit
@testable import Ikra

// I3: içe aktarma, kütüphane, Koç ve altyapı mantığı (ağ yok).

// MARK: - Bağlantılar (#3, #5, #40)

struct ImportLinkTests {
    @Test func parsesMultipleLinksAndDropsNoise() {
        let text = """
        Şu dersi izle https://youtu.be/EKGRs8q7HlA
        https://www.youtube.com/watch?v=EKGRs8q7HlA&t=30s
        vimeo.com/76979871, dailymotion.com/video/x8abcd
        merhaba dünya
        https://example.com/ders.mp4
        """
        let links = ImportLinks.parse(text)
        // youtu.be ve watch?v= aynı video: tek sayılır.
        #expect(links.count == 4)
        #expect(links[0] == "https://youtu.be/EKGRs8q7HlA")
        #expect(links.contains("https://vimeo.com/76979871"))
        #expect(links.contains("https://dailymotion.com/video/x8abcd"))
        #expect(links.contains("https://example.com/ders.mp4"))
    }

    @Test func parseCapsAtMaxLinks() {
        let text = (0..<50).map { "https://example.com/v/\($0)" }.joined(separator: "\n")
        #expect(ImportLinks.parse(text).count == ImportLinks.maxLinks)
        #expect(ImportLinks.parse("").isEmpty)
        #expect(ImportLinks.parse("sadece metin, bağlantı yok").isEmpty)
    }

    @Test func classifiesPlatforms() {
        #expect(ImportLinks.classify("https://www.youtube.com/watch?v=EKGRs8q7HlA") == .youtube)
        #expect(ImportLinks.classify("youtu.be/EKGRs8q7HlA") == .youtube)
        #expect(ImportLinks.classify("https://vimeo.com/76979871") == .supported("vimeo"))
        #expect(ImportLinks.classify("https://player.vimeo.com/video/76979871") == .supported("vimeo"))
        #expect(ImportLinks.classify("https://www.dailymotion.com/video/x8abcd") == .supported("dailymotion"))
        #expect(ImportLinks.classify("https://dai.ly/x8abcd") == .supported("dailymotion"))
        #expect(ImportLinks.classify("https://ornek.edu.tr/ders.mp4") == .other(host: "ornek.edu.tr"))
        #expect(ImportLinks.classify("http://ornek.edu.tr/ders.mp4") == .insecure)
        #expect(ImportLinks.classify("file:///etc/passwd") == .invalid)
        #expect(ImportLinks.classify("ftp://ornek.com/x") == .invalid)
        #expect(ImportLinks.classify("tek kelime") == .invalid)
        #expect(ImportLinks.classify("localhost") == .invalid)
    }

    @Test func allowOtherOnlyForUnlistedHttps() {
        #expect(!ImportLinks.needsAllowOther("https://youtu.be/EKGRs8q7HlA"))
        #expect(!ImportLinks.needsAllowOther("https://vimeo.com/1"))
        #expect(ImportLinks.needsAllowOther("https://ornek.edu.tr/ders.mp4"))
        #expect(!ImportLinks.needsAllowOther("http://ornek.edu.tr/ders.mp4"))
        #expect(!ImportLinks.needsAllowOther(""))
    }

    @Test func shortNames() {
        #expect(ImportLinks.shortName("https://youtu.be/EKGRs8q7HlA") == "youtube · EKGRs8q7HlA")
        #expect(ImportLinks.shortName("https://vimeo.com/76979871") == "vimeo.com · 76979871")
        #expect(ImportLinks.shortName("https://vimeo.com/") == "vimeo.com")
    }

    @Test func platformNameForPreview() {
        #expect(YouTubeImportLogic.platformName("vimeo") == "Vimeo")
        #expect(YouTubeImportLogic.platformName("other") == "Diğer site")
        #expect(YouTubeImportLogic.platformName("youtube") == nil)
        #expect(YouTubeImportLogic.platformName(nil) == nil)
    }
}

struct DuplicateAndBatchTests {
    private let existing = [
        LessonKey(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, videoID: "EKGRs8q7HlA", url: "https://www.youtube.com/watch?v=EKGRs8q7HlA"),
        LessonKey(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, videoID: "76979871", url: "https://vimeo.com/76979871/"),
    ]

    @Test func detectsDuplicatesByVideoIDAndURL() {
        #expect(LibraryDuplicates.existing(videoID: "EKGRs8q7HlA", url: nil, in: existing) == existing[0].id)
        // Farklı bağlantı biçimi, aynı video.
        #expect(LibraryDuplicates.existing(videoID: nil, url: "https://youtu.be/EKGRs8q7HlA?t=5", in: existing) == existing[0].id)
        // YouTube dışı: bağlantı karşılaştırılır (eğik çizgi farkı yok sayılır).
        #expect(LibraryDuplicates.existing(videoID: nil, url: "https://vimeo.com/76979871", in: existing) == existing[1].id)
        #expect(LibraryDuplicates.existing(videoID: "yeni", url: "https://youtu.be/AAAAAAAAAAA", in: existing) == nil)
        #expect(LibraryDuplicates.existing(videoID: nil, url: "", in: existing) == nil)
    }

    @Test func batchPlanMarksStatuses() {
        let entries = ImportBatch.plan(links: ["https://youtu.be/EKGRs8q7HlA", "https://youtu.be/AAAAAAAAAAA",
                                               "https://ornek.edu.tr/a.mp4", "http://ornek.edu.tr/b.mp4"],
                                       existing: existing, allowOther: false)
        #expect(entries[0].status == .duplicate(existing[0].id))
        #expect(entries[1].status == .ready)
        #expect(entries[2].status == .needsApproval)
        #expect(entries[3].status == .rejected)
        #expect(ImportBatch.runnable(entries, excluded: []) == ["https://youtu.be/AAAAAAAAAAA"])

        let approved = ImportBatch.plan(links: ["https://ornek.edu.tr/a.mp4"], existing: [], allowOther: true)
        #expect(approved[0].status == .ready)
        // Elle çıkarılan atlanır.
        #expect(ImportBatch.runnable(approved, excluded: ["https://ornek.edu.tr/a.mp4"]).isEmpty)
    }
}

// MARK: - Etiket, oynatma listesi, kayıt planı

struct TagCourseRecordingTests {
    @Test func normalizesTags() {
        #expect(TagLogic.normalize(subject: "Biyoloji", topics: ["hücre", "Hücre", " #zar ", "", "ATP", "mitokondri", "fazla"])
                == ["Biyoloji", "hücre", "zar", "ATP", "mitokondri"])
        #expect(TagLogic.normalize(subject: "", topics: []).isEmpty)
        let long = String(repeating: "a", count: 100)
        #expect(TagLogic.normalize(subject: long, topics: []).first?.count == TagLogic.maxLength)
    }

    @Test func countsTagsByFrequency() {
        let counts = TagLogic.counts([["Fizik", "Optik"], ["Fizik"], ["Kimya"]])
        #expect(counts.first?.tag == "Fizik" && counts.first?.count == 2)
        #expect(counts.map(\.tag) == ["Fizik", "Kimya", "Optik"])
    }

    @Test func playlistCourseNameAndMatch() {
        #expect(PlaylistCourse.name(from: "  YKS Biyoloji 2025 ") == "YKS Biyoloji 2025")
        #expect(PlaylistCourse.name(from: "   ") == "Oynatma listesi")
        #expect(PlaylistCourse.name(from: String(repeating: "x", count: 200)).count == 60)
        let id = UUID()
        #expect(PlaylistCourse.match(name: "yks biyoloji", in: [(UUID(), "Fizik"), (id, "YKS Biyoloji")]) == id)
        #expect(PlaylistCourse.match(name: "Kimya", in: [(id, "Fizik")]) == nil)
        // Türkçe büyük/küçük harf: "ISI" ≠ "isi" olmamalı (ı/İ).
        #expect(PlaylistCourse.match(name: "ISIL", in: [(id, "ısıl")]) == id)
    }

    @Test func recordingPlanThresholds() {
        let mb: Int64 = 1_048_576
        // Küçük m4a olduğu gibi; büyük ya da başka biçim dönüştürülür.
        #expect(RecordingPlan.plan(bytes: 10 * mb, fileExtension: "m4a", isVideo: false) == .init(convertToAAC: false, uploadVideo: false))
        #expect(RecordingPlan.plan(bytes: 30 * mb, fileExtension: "m4a", isVideo: false) == .init(convertToAAC: true, uploadVideo: false))
        // Ham .aac (ADTS) "audio.m4a" adıyla kopyalanamaz: küçük olsa da dönüştürülür.
        #expect(RecordingPlan.plan(bytes: 2 * mb, fileExtension: "aac", isVideo: false) == .init(convertToAAC: true, uploadVideo: false))
        #expect(RecordingPlan.plan(bytes: 2 * mb, fileExtension: "AAC", isVideo: false).convertToAAC)
        #expect(RecordingPlan.plan(bytes: 5 * mb, fileExtension: "WAV", isVideo: false) == .init(convertToAAC: true, uploadVideo: false))
        // Video: ≤ 200 MB olduğu gibi (kareler), üstü yalnız ses.
        #expect(RecordingPlan.plan(bytes: 150 * mb, fileExtension: "mp4", isVideo: true) == .init(convertToAAC: true, uploadVideo: true))
        #expect(RecordingPlan.plan(bytes: 300 * mb, fileExtension: "mov", isVideo: true) == .init(convertToAAC: true, uploadVideo: false))
    }

    @Test func recordingSizesAndTitles() {
        #expect(RecordingPlan.fitsUpload(500 * 1_048_576))
        #expect(!RecordingPlan.fitsUpload(500 * 1_048_576 + 1))
        #expect(!RecordingPlan.fitsUpload(0))
        // 1 saat AAC 48 kbps ≈ 21,6 MB.
        #expect(abs(RecordingPlan.estimatedAACBytes(duration: 3600) - 21_600_000) < 10)
        #expect(RecordingPlan.isVideo(fileExtension: "mp4") && RecordingPlan.isVideo(fileExtension: "MOV"))
        #expect(!RecordingPlan.isVideo(fileExtension: "m4a") && !RecordingPlan.isVideo(fileExtension: "xyz"))
        #expect(RecordingPlan.displayTitle(fileName: "Yeni Kayıt 12.m4a") == "Yeni Kayıt 12")
        #expect(RecordingPlan.displayTitle(fileName: ".m4a") == "Sınıf kaydı")
    }

    @Test func uploadRequestOmitsURLButKeepsOptions() throws {
        let request = YouTubeStartRequest(url: "", mode: .ai, language: nil, translateTo: "tr", start: nil, end: nil,
                                          keyframes: true, notes: true, uploadId: "0f1e2d3c-0000-4000-8000-000000000001", title: "Kayıt")
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(json["url"] == nil)
        #expect(json["uploadId"] as? String == "0f1e2d3c-0000-4000-8000-000000000001" && json["title"] as? String == "Kayıt")
        #expect(json["mode"] as? String == "ai" && json["translateTo"] as? String == "tr")
        // Yan depo için gidiş-dönüş.
        let back = try JSONDecoder().decode(YouTubeStartRequest.self, from: JSONEncoder().encode(request))
        #expect(back == request)

        let plain = YouTubeStartRequest(url: "https://youtu.be/EKGRs8q7HlA", mode: .auto, language: nil, translateTo: nil, start: nil, end: nil,
                                        keyframes: false, notes: true, allowOther: true)
        let plainJSON = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as? [String: Any])
        #expect(plainJSON["url"] as? String == "https://youtu.be/EKGRs8q7HlA" && plainJSON["uploadId"] == nil && plainJSON["allowOther"] as? Bool == true)
    }

    @Test func infoRequestAllowOtherOnlyWhenSet() throws {
        let off = try JSONSerialization.jsonObject(with: JSONEncoder().encode(YouTubeInfoRequest(url: "https://youtu.be/x"))) as? [String: Any]
        #expect(off?["allowOther"] == nil)
        let on = try JSONSerialization.jsonObject(with: JSONEncoder().encode(YouTubeInfoRequest(url: "https://a.b/x", allowOther: true))) as? [String: Any]
        #expect(on?["allowOther"] as? Bool == true)
    }
}

// MARK: - Kanal takibi (#2)

struct ChannelFeedTests {
    private func feed(_ ids: [String]) -> [FeedVideo] { ids.map { FeedVideo(id: $0, url: "https://youtu.be/\($0)", title: "Video \($0)") } }

    @Test func findsOnlyNewVideos() {
        let fresh = FeedDiff.newVideos(known: ["a", "b"], feed: feed(["c", "b", "a"]), isFirstCheck: false)
        #expect(fresh.map(\.id) == ["c"])
        #expect(FeedDiff.newVideos(known: ["a"], feed: feed(["a"]), isFirstCheck: false).isEmpty)
        // İlk kontrolde mevcut videolar bildirim çıkarmaz.
        #expect(FeedDiff.newVideos(known: [], feed: feed(["a", "b"]), isFirstCheck: true).isEmpty)
        // Kimliği boş olan atlanır.
        #expect(FeedDiff.newVideos(known: [], feed: [FeedVideo(id: "", url: "", title: "x")], isFirstCheck: false).isEmpty)
    }

    @Test func emptyKnownListCountsAsFirstCheck() {
        #expect(FeedDiff.isFirstCheck(known: []))
        #expect(!FeedDiff.isFirstCheck(known: ["a"]))
        // Takip anında listesi boş olan kanal: ilk video bildirim çıkarmaz, bilinenlere eklenir.
        let first = FeedDiff.newVideos(known: [], feed: feed(["a"]), isFirstCheck: FeedDiff.isFirstCheck(known: []))
        #expect(first.isEmpty)
        #expect(FeedDiff.updatedKnown(known: [], feed: feed(["a"])) == ["a"])
    }

    @Test func backgroundPicksOldestCheckedChannels() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let never = UUID(), old = UUID(), mid = UUID(), fresh = UUID()
        let picked = FeedDiff.oldestFirst([(fresh, now), (old, now - 86_400), (never, nil), (mid, now - 3600)], limit: 3)
        #expect(picked == [never, old, mid])
        #expect(FeedDiff.oldestFirst([(fresh, now)], limit: 3) == [fresh])
        #expect(FeedDiff.oldestFirst([(fresh, now)], limit: 0).isEmpty)
    }

    @Test func completionGateFiresOnce() {
        let log = CallLog()
        let gate = CompletionGate { success in log.add(success) }
        #expect(gate.complete(success: false))
        #expect(!gate.complete(success: true))
        #expect(log.values == [false])
    }

    @Test func knownIDsStayBoundedAndOrdered() {
        let known = (0..<400).map { "old\($0)" }
        let updated = FeedDiff.updatedKnown(known: known, feed: feed(["n1", "old0", "n2"]))
        #expect(updated.count == FeedDiff.maxKnown)
        #expect(Array(updated.prefix(3)) == ["n1", "old0", "n2"])
        #expect(Set(updated).count == updated.count)
    }

    @Test func notificationBody() {
        #expect(FeedDiff.notificationBody(channel: "Kanal", videos: feed(["a"])) == "Video a")
        #expect(FeedDiff.notificationBody(channel: "Kanal", videos: feed(["a", "b", "c"])) == "Video a ve 2 video daha")
        #expect(FeedDiff.notificationBody(channel: "Kanal", videos: []) == "Kanal")
    }

    @Test func feedRequestSendsOnlyTheURL() throws {
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(YouTubeFeedRequest(url: "https://www.youtube.com/@k"))) as? [String: Any])
        #expect(Array(json.keys) == ["url"])
    }

    @Test func feedDecodesTolerantly() throws {
        let json = #"{"title":"Kanal","url":"https://youtube.com/@k","videos":[{"id":"EKGRs8q7HlA","url":"https://youtu.be/EKGRs8q7HlA","title":"T","duration":65,"uploadDate":"20260101"},{"url":"https://youtu.be/AAAAAAAAAAA"}]}"#
        let feed = try JSONDecoder().decode(YouTubeFeed.self, from: Data(json.utf8))
        #expect(feed.title == "Kanal" && feed.videos.count == 2)
        #expect(feed.videos[0].duration == 65 && feed.videos[0].uploadDate == "20260101")
        // id yoksa bağlantıdan türetilir.
        #expect(feed.videos[1].id == "AAAAAAAAAAA" && feed.videos[1].title == "")
        let empty = try JSONDecoder().decode(YouTubeFeed.self, from: Data("{}".utf8))
        #expect(empty.videos.isEmpty)
    }

    @MainActor
    @Test func queueDedupesAndSkipsLibraryVideos() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: AutoImportQueue.key)
        defer { saved == nil ? defaults.removeObject(forKey: AutoImportQueue.key) : defaults.set(saved, forKey: AutoImportQueue.key) }
        AutoImportQueue.clear()
        let course = UUID()
        let library = [LessonKey(id: UUID(), videoID: "AAAAAAAAAAA", url: "https://youtu.be/AAAAAAAAAAA")]
        let added = AutoImportQueue.enqueue(feed(["BBBBBBBBBBB", "AAAAAAAAAAA", "CCCCCCCCCCC"]), courseID: course, existing: library)
        #expect(added == 2)
        // Aynı video tekrar eklenmez (başka biçimde bile).
        let again = AutoImportQueue.enqueue([FeedVideo(id: "BBBBBBBBBBB", url: "https://www.youtube.com/watch?v=BBBBBBBBBBB", title: "x")], courseID: nil, existing: [])
        #expect(again == 0)
        #expect(AutoImportQueue.items.map(\.courseID) == [course, course])
        if let first = AutoImportQueue.items.first { AutoImportQueue.remove(first.id) }
        #expect(AutoImportQueue.items.count == 1)
        AutoImportQueue.clear()
    }
}

// MARK: - Depolama (#43)

struct StorageTests {
    @Test func classifiesFiles() {
        #expect(StorageUsage.kind(of: "audio.m4a") == .audio)
        #expect(StorageUsage.kind(of: "voice.MP3") == .audio)
        #expect(StorageUsage.kind(of: "video.mp4") == .video)
        #expect(StorageUsage.kind(of: "clip.MOV") == .video)
        #expect(StorageUsage.kind(of: "frame_ab12.jpg") == .frames)
        #expect(StorageUsage.kind(of: "frame_text.json") == .other)
        #expect(StorageUsage.kind(of: "speakers.json") == .other)
        #expect(StorageUsage.kind(of: "foto.jpg") == .other)
    }

    @Test func measuresAndDeletesByKind() throws {
        let id = UUID()
        let dir = StorageUsage.lessonDirectory(id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(count: 1000).write(to: dir.appending(path: "audio.m4a"))
        try Data(count: 5000).write(to: dir.appending(path: "video.mp4"))
        try Data(count: 300).write(to: dir.appending(path: "frame_a.jpg"))
        try Data(count: 200).write(to: dir.appending(path: "frame_b.jpg"))
        try Data(count: 50).write(to: dir.appending(path: "frame_text.json"))
        let sizes = StorageUsage.measure(lesson: id)
        #expect(sizes.audio == 1000 && sizes.video == 5000 && sizes.frames == 500 && sizes.other == 50)
        #expect(sizes.total == 6550)
        #expect(StorageUsage.delete(.video, lesson: id) == 5000)
        #expect(StorageUsage.measure(lesson: id).video == 0)
        #expect(StorageUsage.measure(lesson: id).audio == 1000)
        // Olmayan klasör: sıfır, klasör oluşturulmaz.
        let missing = UUID()
        #expect(StorageUsage.measure(lesson: missing).total == 0)
        #expect(!FileManager.default.fileExists(atPath: StorageUsage.lessonDirectory(missing).path))
    }

    @Test func staleAudioUsesLastOpenedThenCreation() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 86_400
        let stale = UUID(), fresh = UUID(), neverOpenedOld = UUID(), noAudio = UUID(), openedRecently = UUID()
        let items = [
            StorageUsage.Candidate(id: stale, lastOpened: now - 40 * day, createdAt: now - 90 * day, hasAudio: true),
            StorageUsage.Candidate(id: fresh, lastOpened: now - 5 * day, createdAt: now - 90 * day, hasAudio: true),
            StorageUsage.Candidate(id: neverOpenedOld, lastOpened: nil, createdAt: now - 31 * day, hasAudio: true),
            StorageUsage.Candidate(id: noAudio, lastOpened: now - 90 * day, createdAt: now - 90 * day, hasAudio: false),
            // Eski ama yakın zamanda açılmış: silinmez.
            StorageUsage.Candidate(id: openedRecently, lastOpened: now - 29 * day, createdAt: now - 200 * day, hasAudio: true),
        ]
        #expect(Set(StorageUsage.staleAudio(items, days: 30, now: now)) == [stale, neverOpenedOld])
    }

    @Test func uploadedRecordingsAreNeverStale() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 86_400
        let upload = UUID(), regular = UUID()
        // Sınıf kaydı: ses tek kopya, yıllarca açılmasa da toplu silinmez.
        let items = [
            StorageUsage.Candidate(id: upload, lastOpened: nil, createdAt: now - 400 * day, hasAudio: true, isUpload: true),
            StorageUsage.Candidate(id: regular, lastOpened: nil, createdAt: now - 400 * day, hasAudio: true),
        ]
        #expect(StorageUsage.staleAudio(items, days: 30, now: now) == [regular])
        #expect(StorageUsage.isUploadLesson(videoID: "upload-0f1e2d3c-0000-4000-8000-000000000001", url: ""))
        #expect(StorageUsage.isUploadLesson(videoID: "EKGRs8q7HlA", url: ""))
        #expect(StorageUsage.isUploadLesson(videoID: "upload-x", url: "https://x.com"))
        #expect(!StorageUsage.isUploadLesson(videoID: "EKGRs8q7HlA", url: "https://youtu.be/EKGRs8q7HlA"))
    }

    @Test func openLogRoundTrip() {
        let id = UUID()
        defer { LessonOpenLog.forget(id) }
        #expect(LessonOpenLog.date(id) == nil)
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        LessonOpenLog.touch(id, now: when)
        #expect(LessonOpenLog.date(id) == when)
        LessonOpenLog.forget(id)
        #expect(LessonOpenLog.date(id) == nil)
    }

    @Test func byteFormatIsReadable() {
        #expect(!ByteFormat.string(1_500_000).isEmpty)
        #expect(FileTransfer.isValidID("0f1e2d3c4b5a69788796a5b4c3d2e1f0"))
        #expect(FileTransfer.isValidID("0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0"))
        #expect(!FileTransfer.isValidID("../../etc/passwd"))
        #expect(!FileTransfer.isValidID("kisa"))
        #expect(!FileTransfer.isValidID("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"))
    }
}

// MARK: - Arama (#38)

struct LibrarySearchTests {
    private func doc(_ title: String, _ paragraphs: [(Double, String)], frames: [(Double, String)] = []) -> LibrarySearch.Doc {
        LibrarySearch.Doc(id: UUID(), title: title, channel: "", foldedTitle: LibrarySearch.fold(title),
                          paragraphs: paragraphs.map { .init(start: $0.0, text: $0.1, folded: LibrarySearch.fold($0.1)) },
                          frames: frames.map { .init(start: $0.0, text: $0.1, folded: LibrarySearch.fold($0.1)) },
                          chapters: [], keyPoints: [])
    }

    @Test func foldingIgnoresCaseAndDiacritics() {
        #expect(LibrarySearch.matches(text: "Hücre Zarı ve Işık", tokens: LibrarySearch.tokens("HÜCRE zari")))
        #expect(LibrarySearch.matches(text: "Şeker ÇÖZELTİSİ", tokens: LibrarySearch.tokens("seker cozeltisi")))
        #expect(!LibrarySearch.matches(text: "mitokondri", tokens: LibrarySearch.tokens("kloroplast")))
        #expect(!LibrarySearch.matches(text: "x", tokens: []))
        // Büyük I/İ Türkçe'ye göre katlanır.
        #expect(LibrarySearch.matches(text: "ışık", tokens: LibrarySearch.tokens("IŞIK")))
    }

    @Test func searchGroupsRanksAndOrdersByTime() {
        let a = doc("Hücre zarı", [(10, "Zar seçici geçirgendir."), (95, "Osmoz zardan su geçişidir."), (300, "Konu bitti.")])
        let b = doc("Genetik", [(5, "DNA çift sarmaldır."), (50, "Osmoz burada geçmez.")], frames: [(70, "OSMOZ şeması")])
        let results = LibrarySearch.search("osmoz", in: [a, b])
        #expect(results.count == 2)
        // Çok eşleşmesi olan ders önce (b: 1 metin + 1 kare = 2; a: 1).
        #expect(results.first?.lesson == b.id)
        let bHits = results[0].hits
        #expect(bHits.map(\.time) == [50, 70])
        #expect(bHits.last?.source == .frame)
        #expect(results[1].hits.map(\.time) == [95])
        // Başlıkta geçen de bulunur.
        #expect(LibrarySearch.search("genetik", in: [a, b]).first?.hits.first?.source == .title)
        #expect(LibrarySearch.search("bulunamaz", in: [a, b]).isEmpty)
        #expect(LibrarySearch.search("  ", in: [a, b]).isEmpty)
    }

    @Test func multiTokenQueryNeedsAllInSameParagraph() {
        let d = doc("Ders", [(0, "ATP enerji üretir"), (20, "Mitokondri hücrenin enerji santralidir"), (40, "ATP sentezi zarda olur")])
        let hits = LibrarySearch.search("atp zar", in: [d]).first?.hits ?? []
        #expect(hits.map(\.time) == [40])
    }

    @Test func limitsHitsPerLesson() {
        let paragraphs = (0..<20).map { (Double($0 * 10), "osmoz örneği \($0)") }
        let result = LibrarySearch.search("osmoz", in: [doc("Uzun", paragraphs)])
        #expect(result.first?.hits.count == LibrarySearch.maxPerLesson)
        #expect(result.first?.total == 20)
    }

    @Test func snippetCentersOnMatch() {
        let text = String(repeating: "başlangıç ", count: 30) + "osmoz tanımı" + String(repeating: " son ", count: 30)
        let snippet = LibrarySearch.snippet(text: text, folded: LibrarySearch.fold(text), tokens: ["osmoz"])
        #expect(snippet.contains("osmoz"))
        #expect(snippet.hasPrefix("…") && snippet.hasSuffix("…"))
        #expect(snippet.count < 200)
    }

    @Test func aiEntriesAreTrimmed() {
        var d = doc("Ders", [])
        d.chapters = (0..<100).map { VideoChapter(title: "B\($0)", start: Double($0)) }
        d.keyPoints = (0..<100).map { NoteKeyPoint(text: "N\($0)", time: Double($0)) }
        let empty = doc("Boş", [])
        let entries = LibrarySearch.aiEntries(from: [d, empty])
        #expect(entries.count == 1)
        #expect(entries[0].chapters.count == 40 && entries[0].keyPoints.count == 30)
        #expect(entries[0].id == d.id.uuidString.lowercased())
    }

    @Test func searchResponseDecodes() throws {
        let json = #"{"results":[{"lessonId":"abc","time":12.5,"reason":"Osmoz anlatılıyor"},{"lessonId":"def"}]}"#
        let response = try JSONDecoder().decode(YouTubeSearchResponse.self, from: Data(json.utf8))
        #expect(response.results.count == 2 && response.results[0].time == 12.5 && response.results[1].reason == "")
        let tags = try JSONDecoder().decode(YouTubeTagsResponse.self, from: Data(#"{"subject":"Biyoloji","topics":["Hücre"]}"#.utf8))
        #expect(tags.subject == "Biyoloji" && tags.topics == ["Hücre"])
    }
}

// MARK: - Kare yazıları (#10)

struct FrameTextTests {
    @Test func cleansNoise() {
        #expect(FrameTextStore.cleaned("  Hücre   zarı \n\n a \n ATP  üretimi ") == "Hücre zarı\nATP üretimi")
        #expect(FrameTextStore.cleaned("•\n-\n.") == "")
        #expect(FrameTextStore.cleaned("ab") == "")
        #expect(FrameTextStore.cleaned("") == "")
    }

    @MainActor
    @Test func scannerJoinsRunningScanInsteadOfDuplicating() async throws {
        let id = UUID()
        let dir = VideoFiles.directory(for: id)
        defer { try? FileManager.default.removeItem(at: dir) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 300)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 300))
            ("MITOCHONDRIA" as NSString).draw(at: CGPoint(x: 40, y: 100), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 80), .foregroundColor: UIColor.black,
            ])
        }
        try #require(image.jpegData(compressionQuality: 0.95)).write(to: VideoFiles.keyframeURL(lesson: id, frame: "k1"))
        let frames = [FrameRef(id: "k1", time: 5)]
        #expect(!FrameTextScanner.isScanning(id))
        async let first = FrameTextScanner.scan(lesson: id, frames: frames)
        async let second = FrameTextScanner.scan(lesson: id, frames: frames)
        let (a, b) = await (first, second)
        #expect(a == b && a.count == 1)
        #expect(a.first?.text.localizedCaseInsensitiveContains("MITOCHONDRIA") == true)
        #expect(!FrameTextScanner.isScanning(id))
        // Dosyaya yazıldı; sonraki tarama taranmış kareyi atlar.
        #expect(FrameTextStore.load(lesson: id).count == 1)
        #expect(await FrameTextScanner.scan(lesson: id, frames: frames) == a)
    }

    @Test func mergesByIDAndSortsByTime() {
        let old = [FrameTextStore.Entry(id: "a", time: 30, text: ""), FrameTextStore.Entry(id: "b", time: 10, text: "eski")]
        let new = [FrameTextStore.Entry(id: "a", time: 30, text: "yeni"), FrameTextStore.Entry(id: "c", time: 5, text: "c")]
        let merged = FrameTextStore.merge(existing: old, new: new)
        #expect(merged.map(\.id) == ["c", "b", "a"])
        #expect(merged.last?.text == "yeni")
        #expect(FrameTextStore.nonEmpty(merged).count == 3)
        #expect(FrameTextStore.nonEmpty(old).count == 1)
    }

    @Test func storeRoundTripAndRecognition() throws {
        let id = UUID()
        let dir = VideoFiles.directory(for: id)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(FrameTextStore.load(lesson: id).isEmpty)
        FrameTextStore.save([.init(id: "k1", time: 12, text: "Mitokondri")], lesson: id)
        #expect(FrameTextStore.load(lesson: id).first?.text == "Mitokondri")
        #expect(FrameTextStore.fileURL(lesson: id).lastPathComponent == "frame_text.json")

        // Gerçek tanıma: büyük, net bir yazı görseli (Vision simülatörde de çalışır).
        let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 300)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 300))
            ("OSMOSIS MEMBRANE" as NSString).draw(at: CGPoint(x: 40, y: 100), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 80), .foregroundColor: UIColor.black,
            ])
        }
        let url = dir.appending(path: "frame_test.jpg")
        try #require(image.jpegData(compressionQuality: 0.95)).write(to: url)
        let text = FrameTextStore.recognizeText(at: url)
        #expect(text.localizedCaseInsensitiveContains("OSMOSIS"))
    }
}

// MARK: - Altyazı (#36)

struct SubtitleTests {
    @Test func chunksSentencesWithinLimit() {
        let text = "Hücre zarı seçici geçirgendir. Küçük moleküller kolayca geçer ve büyük moleküller taşıyıcı proteinlere ihtiyaç duyar; bu nedenle zar önemlidir. Kısa."
        let chunks = SubtitleBuilder.chunk(text)
        #expect(chunks.allSatisfy { $0.count <= SubtitleBuilder.maxCueCharacters })
        #expect(chunks.joined(separator: " ").replacingOccurrences(of: "  ", with: " ") == text)
        #expect(SubtitleBuilder.chunk("").isEmpty)
    }

    @Test func cuesSpreadTimeProportionallyAndStayOrdered() {
        let cues = SubtitleBuilder.cues(text: String(repeating: "kelime ", count: 40), start: 10, end: 40)
        #expect(cues.count >= 3)
        #expect(cues.first?.start == 10)
        for pair in zip(cues, cues.dropFirst()) { #expect(pair.0.start < pair.1.start) }
        #expect(cues.allSatisfy { $0.end - $0.start >= SubtitleBuilder.minCueDuration })
        // Çok kısa süreye sığmayan paragraf yine de okunabilir kalır.
        let squeezed = SubtitleBuilder.cues(text: String(repeating: "uzun cümle parçası ", count: 20), start: 0, end: 1)
        #expect(squeezed.count >= 2 && squeezed.allSatisfy { $0.end > $0.start })
    }

    @Test func rendersValidSRT() {
        let srt = SubtitleBuilder.render([
            .init(start: 1, end: 3.5, text: "Merhaba"),
            .init(start: 3.5, end: 5, text: "   "),
            .init(start: 5, end: 7, text: "Dünya"),
        ])
        #expect(srt == "1\n00:00:01,000 --> 00:00:03,500\nMerhaba\n\n2\n00:00:05,000 --> 00:00:07,000\nDünya\n\n")
    }

    @Test func paragraphAndOriginalSources() {
        let paragraphs = [TranscriptParagraph(start: 0, end: 10, text: "Birinci paragraf. İkinci cümle.")]
        let srt = SubtitleBuilder.srt(paragraphs: paragraphs)
        #expect(srt.hasPrefix("1\n00:00:00,000"))
        #expect(srt.contains("Birinci paragraf."))
    }

    @Test func hasContentIsCheapAndAccurate() async {
        let video = VideoInfo(id: "x", url: "", title: "", channel: "", duration: 10, thumbnail: nil, chapters: [], captions: [], language: nil)
        let empty = VideoTranscript(video: video, source: "ai", language: "tr", segments: [], paragraphs: [], chapters: [], translation: nil,
                                    notes: nil, keyframes: [], warnings: [])
        #expect(!SubtitleBuilder.hasContent(transcript: empty, translated: false))
        var withParagraph = empty
        withParagraph.paragraphs = [TranscriptParagraph(start: 0, end: 5, text: "Merhaba dünya.")]
        #expect(SubtitleBuilder.hasContent(transcript: withParagraph, translated: false))
        var translated = empty
        translated.translation = TranscriptTranslation(language: "tr", paragraphs: [TranscriptParagraph(start: 0, end: 5, text: "Çeviri.")])
        #expect(SubtitleBuilder.hasContent(transcript: translated, translated: true))
        #expect(!SubtitleBuilder.hasContent(transcript: translated, translated: false))
        // Çeviri istenip yoksa orijinale düşer.
        #expect(await SubtitleBuilder.build(transcript: withParagraph, translated: true).contains("Merhaba dünya."))
        #expect(await SubtitleBuilder.build(transcript: translated, translated: true).contains("Çeviri."))
        #expect(await SubtitleBuilder.build(transcript: empty, translated: false).isEmpty)
    }

    @Test func srtIsCappedForServer() {
        let big = (0..<20_000).map { TranscriptParagraph(start: Double($0), end: Double($0) + 1, text: "çok uzun bir altyazı metni örneği burada") }
        #expect(SubtitleBuilder.srt(paragraphs: big).count <= SubtitleBuilder.maxSRTCharacters)
    }

    @Test func mediaStatusDecodesStatesAndUnknowns() throws {
        func status(_ json: String) throws -> MediaStatus { try JSONDecoder().decode(MediaStatus.self, from: Data(json.utf8)) }
        let done = try status(#"{"state":"done","progress":1,"message":"Hazır","fileId":"0f1e2d3c4b5a69788796a5b4c3d2e1f0","bytes":12345}"#)
        #expect(done.state == .done && done.fileId != nil && done.bytes == 12345 && done.state.isFinished)
        #expect(try status(#"{"state":"canceled"}"#).state == .canceled)
        #expect(try status(#"{"state":"cancelled"}"#).state == .canceled)
        // Bilinmeyen ara durum: çalışıyor sayılır; ilerleme sınırlanır.
        let odd = try status(#"{"state":"muxing","progress":7}"#)
        #expect(odd.state == .running && odd.progress == 1 && !odd.state.isFinished)
        #expect(try status("{}").state == .running)
        #expect(try status(#"{"state":"error","error":"yt-dlp"}"#).error == "yt-dlp")
        let warned = try status(#"{"state":"done","fileId":"0f1e2d3c4b5a69788796a5b4c3d2e1f0","warnings":["Altyazı yumuşak iz olarak eklendi."]}"#)
        #expect(warned.warnings == ["Altyazı yumuşak iz olarak eklendi."] && odd.warnings.isEmpty)
    }
}

// MARK: - Koç: video görevleri (#29, #30)

struct CoachVideoTests {

}

// MARK: - Kütüphane geneli Sor (#39)

struct LibraryAskVideoTests {
    private func paragraphs(_ count: Int, chars: Int = 100) -> [TranscriptParagraph] {
        (0..<count).map { TranscriptParagraph(start: Double($0) * 10, end: Double($0) * 10 + 10, text: String(repeating: "a", count: chars)) }
    }

    @Test func compactMergesNeighborsOverParagraphLimit() {
        #expect(LibraryAskPayload.compact(paragraphs(100)).count == 100)
        let merged = LibraryAskPayload.compact(paragraphs(1300))
        #expect(merged.count <= LibraryAskPayload.maxParagraphsPerVideo)
        #expect(merged.first?.start == 0)
        #expect(merged.allSatisfy { $0.text.count <= LibraryAskPayload.maxParagraphCharacters })
        // Boş paragraflar atılır.
        #expect(LibraryAskPayload.compact([TranscriptParagraph(start: 0, end: 1, text: "  ")]).isEmpty)
    }

    @Test func videosRespectCountAndCharacterBudgets() {
        let lessons = (0..<60).map { (id: UUID(), title: "Ders \($0)", paragraphs: paragraphs(50, chars: 200)) }
        let videos = LibraryAskPayload.videos(from: lessons)
        #expect(videos.count <= LibraryAskPayload.maxVideos)
        let total = videos.flatMap(\.paragraphs).reduce(0) { $0 + $1.text.count }
        #expect(total <= LibraryAskPayload.maxTotalCharacters)
        #expect(videos.allSatisfy { $0.id == $0.id.lowercased() && UUID(uuidString: $0.id) != nil })
        // Bütçe darsa sonraki dersler atlanır ama ilk ders tam gelir.
        let big = [(id: UUID(), title: "Dev", paragraphs: paragraphs(600, chars: 1000)), (id: UUID(), title: "Küçük", paragraphs: paragraphs(3))]
        let capped = LibraryAskPayload.videos(from: big)
        #expect(capped.first?.paragraphs.reduce(0) { $0 + $1.text.count } ?? 0 <= LibraryAskPayload.maxTotalCharacters)
    }

    @Test func decodesEpisodeAndVideoCitations() throws {
        let video = UUID(), episode = UUID()
        let json = """
        {"answer":"Cevap","citations":[
          {"episodeId":"\(episode.uuidString)","chapterIndex":2,"quote":"alıntı"},
          {"kind":"video","id":"\(video.uuidString.lowercased())","time":125.5,"quote":"video alıntısı"},
          {"kind":"video","id":"geçersiz","time":3}
        ]}
        """
        let answer = try JSONDecoder().decode(LibraryAnswerV2.self, from: Data(json.utf8))
        #expect(answer.answer == "Cevap" && answer.citations.count == 3)
        #expect(!answer.citations[0].isVideo && answer.citations[0].episodeId == episode && answer.citations[0].chapterIndex == 2)
        #expect(answer.citations[1].isVideo && answer.citations[1].videoId == video && answer.citations[1].time == 125.5)
        // Çözülemeyen kimlik cevabı düşürmez.
        #expect(answer.citations[2].videoId == nil)
        // Atıf alanı bozuksa cevap yine gelir.
        let broken = try JSONDecoder().decode(LibraryAnswerV2.self, from: Data(#"{"answer":"x","citations":"bozuk"}"#.utf8))
        #expect(broken.answer == "x" && broken.citations.isEmpty)
    }

    @Test func requestOmitsVideosWhenNil() throws {
        let request = LibraryAskRequestV2(question: "s", language: "tr", episodes: [], videos: nil)
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(json["videos"] == nil && (json["episodes"] as? [Any])?.isEmpty == true)
    }
}

// MARK: - Bekleyen istekler ve gelen kutusu (#42, #1)

@MainActor
@Suite(.serialized)
struct PendingRequestTests {
    private let request = YouTubeStartRequest(url: "https://youtu.be/EKGRs8q7HlA", mode: .auto, language: "tr", translateTo: nil,
                                              start: 5, end: 60, keyframes: true, notes: true)

    @Test func requestIsStoredPerJobAndPruned() {
        let defaults = UserDefaults.standard
        let savedJobs = defaults.object(forKey: YouTubePendingJobs.key)
        let savedRequests = defaults.object(forKey: YouTubePendingRequests.key)
        defer {
            savedJobs == nil ? defaults.removeObject(forKey: YouTubePendingJobs.key) : defaults.set(savedJobs, forKey: YouTubePendingJobs.key)
            savedRequests == nil ? defaults.removeObject(forKey: YouTubePendingRequests.key) : defaults.set(savedRequests, forKey: YouTubePendingRequests.key)
        }
        defaults.removeObject(forKey: YouTubePendingJobs.key)
        defaults.removeObject(forKey: YouTubePendingRequests.key)

        YouTubePendingJobs.add(PendingYouTubeJob(jobId: "job-1", url: request.url, title: "T", startedAt: .now))
        YouTubePendingRequests.save(request, for: "job-1")
        #expect(YouTubePendingRequests.request(for: "job-1") == request)
        #expect(YouTubePendingRequests.request(for: "yok") == nil)

        // Yeni iş kaydedilirken bekleyenlerde olmayan eski istek temizlenir.
        YouTubePendingJobs.add(PendingYouTubeJob(jobId: "job-2", url: request.url, title: "T", startedAt: .now))
        YouTubePendingJobs.remove("job-1")
        YouTubePendingRequests.save(request, for: "job-2")
        #expect(YouTubePendingRequests.request(for: "job-1") == nil)
        #expect(YouTubePendingRequests.request(for: "job-2") == request)

        LessonImporter.forget("job-2")
        #expect(YouTubePendingRequests.request(for: "job-2") == nil)
        #expect(YouTubePendingJobs.all.isEmpty)
    }

    @Test func inboxMergeAppendsInsteadOfOverwriting() {
        #expect(ImportInbox.merge(nil, "a") == "a")
        #expect(ImportInbox.merge("a", "b") == "a\nb")
        #expect(ImportInbox.merge("", "b") == "b")
        #expect(ImportInbox.merge("a\nb", "c") == "a\nb\nc")
        // İkinci paylaşım birincinin üzerine yazmaz; ayrıştırma ikisini de görür.
        let merged = ImportInbox.merge("https://youtu.be/EKGRs8q7HlA", "https://vimeo.com/76979871")
        #expect(ImportLinks.parse(merged).count == 2)
    }

    @Test func importInboxAccumulatesAndClears() {
        let saved = UserDefaults.standard.string(forKey: ImportInbox.key)
        defer { saved == nil ? UserDefaults.standard.removeObject(forKey: ImportInbox.key) : UserDefaults.standard.set(saved, forKey: ImportInbox.key) }
        UserDefaults.standard.removeObject(forKey: ImportInbox.key)
        #expect(ImportInbox.take() == nil)
        ImportInbox.push("https://youtu.be/EKGRs8q7HlA")
        ImportInbox.push("https://vimeo.com/76979871")
        let text = ImportInbox.take()
        #expect(ImportLinks.parse(text ?? "").count == 2)
        #expect(ImportInbox.take() == nil)
    }
}

// MARK: - Ses dönüştürme (#4)

struct AudioConversionTests {
    /// 2 sn, 44,1 kHz stereo 440 Hz sinüs WAV.
    private func makeWAV(at url: URL, seconds: Double = 2) throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44_100, channels: 2, interleaved: true))
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        let frames = AVAudioFrameCount(44_100 * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try #require(buffer.int16ChannelData)
        for i in 0..<Int(frames) {
            let value = Int16(sin(Double(i) / 44_100 * 440 * 2 * .pi) * 12_000)
            samples[0][i * 2] = value
            samples[0][i * 2 + 1] = value
        }
        try file.write(from: buffer)
    }

    @Test func convertsToSmallMonoAAC() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "i3-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "kayit.wav")
        let output = dir.appending(path: "kayit.m4a")
        try makeWAV(at: source)
        let sourceBytes = try #require(try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int64)

        try await AudioConverter.convertToAAC(source: source, destination: output) { _ in }
        let outBytes = try #require(try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int64)
        #expect(outBytes > 0 && outBytes < sourceBytes / 5)

        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 2) < 0.3)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let descriptions = try await track.load(.formatDescriptions)
        let basic = try #require(descriptions.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee })
        #expect(basic.mChannelsPerFrame == 1)
        #expect(basic.mFormatID == kAudioFormatMPEG4AAC)
        #expect(await AudioConverter.duration(of: output) > 1.5)
    }

    @Test func rejectsNonAudioFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "i3-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "metin.m4a")
        try Data("bu ses değil".utf8).write(to: source)
        await #expect(throws: (any Error).self) {
            try await AudioConverter.convertToAAC(source: source, destination: dir.appending(path: "o.m4a")) { _ in }
        }
    }

    @Test func stashRemovalAndPruneAndBackupExclusion() throws {
        let fresh = UUID().uuidString.lowercased(), old = UUID().uuidString.lowercased(), gone = UUID().uuidString.lowercased()
        defer { for id in [fresh, old, gone] { UploadStash.remove(uploadID: id) } }
        for id in [fresh, old, gone] { try Data(count: 16).write(to: UploadStash.audioURL(uploadID: id)) }
        // Klasör iCloud yedeğine girmez.
        let values = try UploadStash.directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        // Hata/iptal/vazgeç: ilgili geçici ses silinir, diğerleri durur.
        UploadStash.remove(uploadID: gone)
        #expect(!FileManager.default.fileExists(atPath: UploadStash.audioURL(uploadID: gone).path))
        #expect(FileManager.default.fileExists(atPath: UploadStash.audioURL(uploadID: fresh).path))
        // 7 günden eski artık açılışta temizlenir.
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-8 * 86_400)], ofItemAtPath: UploadStash.audioURL(uploadID: old).path)
        UploadStash.prune()
        #expect(!FileManager.default.fileExists(atPath: UploadStash.audioURL(uploadID: old).path))
        #expect(FileManager.default.fileExists(atPath: UploadStash.audioURL(uploadID: fresh).path))
        // Kapsam birden çok kez bırakılabilir (dosya URL'si kapsamsız olsa da güvenli).
        let scope = SecurityScope(url: FileManager.default.temporaryDirectory)
        scope.release()
        scope.release()
    }

    @Test func uploadStashAdoptsAudioIntoLessonFolder() throws {
        let uploadID = UUID().uuidString.lowercased()
        let lessonID = UUID()
        defer {
            try? FileManager.default.removeItem(at: UploadStash.audioURL(uploadID: uploadID))
            VideoFiles.remove(lesson: lessonID)
        }
        #expect(UploadStash.adopt(uploadID: uploadID, into: lessonID) == nil)
        try Data(count: 64).write(to: UploadStash.audioURL(uploadID: uploadID))
        #expect(UploadStash.adopt(uploadID: uploadID, into: lessonID) == VideoFiles.audioFileName)
        #expect(FileManager.default.fileExists(atPath: VideoFiles.audioURL(lesson: lessonID).path))
        // Taşındı: ikinci kez alınamaz.
        #expect(UploadStash.adopt(uploadID: uploadID, into: lessonID) == nil)
    }
}

private nonisolated final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Bool] = []
    func add(_ value: Bool) { lock.withLock { items.append(value) } }
    var values: [Bool] { lock.withLock { items } }
}
