import AVFoundation
import Foundation
import PDFKit
import UIKit
import SwiftData
import Testing
@testable import Ikra

/// P7: kütüphane (arama, filtre, seri, türev), Koç (günlük görevler), dışa aktarma (föy, bölüm işaretli ses), Mac yedeği.
@MainActor
struct PodcastLibraryTests {
    // MARK: - Yardımcılar

    private func item(_ title: String = "Bölüm", created: TimeInterval = 0, position: Double = 0, duration: Double = 600,
                      finished: Bool = false, status: String = "ready", due: Bool = false, derived: String? = nil,
                      parent: UUID? = nil, series: UUID? = nil, index: Int = 0, played: Date? = nil) -> EpisodeListItem {
        EpisodeListItem(id: UUID(), title: title, createdAt: Date(timeIntervalSince1970: created), lastPlayedAt: played, duration: duration,
                    lastPosition: position, isFinished: finished, statusRaw: status, hasDueCards: due, derivedKind: derived,
                    parentID: parent, seriesID: series, seriesIndex: index)
    }

    private func timeline(_ turns: [(String, Double)], chapters: [(String, Double)] = [("Giriş", 0)]) -> Timeline {
        Timeline(chapters: chapters.enumerated().map { TimedChapter(id: $0.offset, title: $0.element.0, start: $0.element.1) },
                 turns: turns.enumerated().map { TimedTurn(id: $0.offset, chapterIndex: 0, speaker: $0.offset % 2 == 0 ? .a : .b,
                                                           text: $0.element.0, sourcePage: nil, start: $0.element.1, end: $0.element.1 + 5) },
                 duration: (turns.last?.1 ?? 0) + 5, thinkPauses: nil, sceneStarts: nil)
    }

    private func memoryContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema(AppDataStore.modelTypes), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func tempDir() throws -> URL {
        let dir = URL.temporaryDirectory.appending(path: "p7-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - #37 arama

    @Test func searchFoldsTurkishAndReturnsTranscriptTime() throws {
        let id = UUID()
        let data = try JSONEncoder().encode(timeline([("Merhaba", 0), ("IŞIK hızı sabittir", 42.5), ("İyon nedir?", 80)]))
        let docs = [EpisodeSearch.Doc(id: id, title: "Fizik", sources: ["Ders notu.pdf"], timelineData: data)]
        let hits = EpisodeSearch.search("ışık", in: docs)
        #expect(hits.count == 1)
        #expect(hits.first?.field == .transcript)
        #expect(hits.first?.time == 42.5)
        // Noktasız ı ≈ i ve büyük İ katlanır.
        #expect(EpisodeSearch.search("isik", in: docs).first?.time == 42.5)
        #expect(EpisodeSearch.search("iyon", in: docs).first?.time == 80)
        // Başlık ve kaynak adı eşleşmesi.
        #expect(EpisodeSearch.search("fizik", in: docs).first?.field == .title)
        #expect(EpisodeSearch.search("ders notu", in: docs).first?.field == .source)
        #expect(EpisodeSearch.search("   ", in: docs).isEmpty)
    }

    // MARK: - #37 filtre ve sıralama

    @Test func filtersAndSorting() {
        let half = item("Yarım", created: 1, position: 120)
        let fresh = item("Yeni", created: 2)
        let done = item("Bitti", created: 3, position: 600, finished: true)
        let failed = item("Hata", created: 4, status: "failed")
        let review = item("Tekrar", created: 5, finished: true, derived: "recap")
        let due = item("Kartlı", created: 6, finished: true, due: true)
        let all = [half, fresh, done, failed, review, due]
        #expect(all.filter { LibraryQuery.matches($0, .inProgress) }.map(\.id) == [half.id])
        #expect(all.filter { LibraryQuery.matches($0, .unplayed) }.map(\.id) == [fresh.id])
        #expect(all.filter { LibraryQuery.matches($0, .failed) }.map(\.id) == [failed.id])
        #expect(Set(all.filter { LibraryQuery.matches($0, .review) }.map(\.id)) == [review.id, due.id])
        #expect(LibraryQuery.ids(all, filter: .all, sort: .newest).first == due.id)
        #expect(LibraryQuery.ids(all, filter: .all, sort: .oldest).first == half.id)
        #expect(LibraryQuery.sorted(all, by: .title).first?.title == "Bitti")
    }

    // MARK: - #39 seri

    @Test func seriesReorderProgressAndResume() {
        let s = UUID()
        let a = item("A", finished: true, series: s, index: 1)
        let b = item("B", series: s, index: 2)
        let c = item("C", series: s, index: 3)
        #expect(SeriesOps.progressText([a, b, c]) == "1/3 dinlendi")
        #expect(SeriesOps.resumeTarget([c, a, b]) == b.id)
        // C'yi başa sürükle.
        let order = SeriesOps.reorder([a.id, b.id, c.id], from: IndexSet(integer: 2), to: 0)
        #expect(order[c.id] == 1 && order[a.id] == 2 && order[b.id] == 3)
    }

    // MARK: - #40 türev gruplama

    @Test func derivedEpisodesFoldUnderParentAndSeriesCollapse() {
        let parent = item("Ana", created: 1)
        let recap = item("Tekrar", created: 3, derived: "recap", parent: parent.id)
        let orphan = item("Yetim", created: 4, derived: "gap", parent: UUID())
        let s = UUID()
        let s1 = item("S1", created: 2, series: s, index: 1)
        let s2 = item("S2", created: 5, series: s, index: 2)
        let ordered = [s2, orphan, recap, s1, parent]
        let rows = LibraryGrouping.rows(ordered, collapseSeries: true)
        #expect(rows == [.series(s), .episode(orphan.id, children: []), .episode(parent.id, children: [recap.id])])
        let flat = LibraryGrouping.rows(ordered, collapseSeries: false)
        #expect(flat.count == 4)
        #expect(flat.contains(.episode(parent.id, children: [recap.id])))
        #expect(DerivedKind.title("video") == "Videodan")
        #expect(DerivedKind.title(nil) == nil)
    }

    // MARK: - #42 "Bugün 3/5" ve otomatik tamamlama

    // MARK: - #41 günü başlat

    // MARK: - #49 manifest

    @Test func manifestV1DecodesWithNewFieldsNil() throws {
        let id = UUID()
        let json = """
        {"version":1,"createdAt":"2026-09-01T10:00:00Z","episodes":[{"id":"\(id.uuidString)","createdAt":"2026-09-01T10:00:00Z","title":"Eski","sourceNames":[],"statusRaw":"ready","scriptData":"e30=","settingsData":"e30=","duration":60,"lastPosition":0,"isFinished":false,"seriesIndex":0}],
         "bookmarks":[{"id":"\(UUID().uuidString)","episodeID":"\(id.uuidString)","episodeTitle":"Eski","time":3,"text":"t","note":"","createdAt":"2026-09-01T10:00:00Z"}],
         "cards":[{"id":"\(UUID().uuidString)","episodeID":"\(id.uuidString)","episodeTitle":"Eski","kindRaw":"quiz","front":"f","back":"b","ease":2.5,"intervalDays":0,"repetitions":0,"lapses":0,"due":"2026-09-01T10:00:00Z"}],
         "documents":[],"preferences":{"studyPlan":"e30="}}
        """
        let m = try BackupManifest.decode(Data(json.utf8))
        #expect(m.version == 1)
        #expect(m.episodes.first?.courseID == nil && m.episodes.first?.audioRevision == nil)
        #expect(m.bookmarks.first?.kind == nil && m.cards.first?.stability == nil)
        #expect(m.listeningDays == nil && m.recallAttempts == nil && m.preferenceValues == nil)
        #expect(m.preferences?["studyPlan"] != nil)
        // Yeni manifest v2 olarak yazılır ve geri okunur.
        let v2 = BackupManifest(episodes: [], bookmarks: [], cards: [], documents: [])
        #expect(try BackupManifest.decode(v2.encoded()).version == 2)
    }

    @Test func prefValueRoundTripKeepsTypes() throws {
        let values: [String: PrefValue] = ["s": .string("aktif"), "b": .bool(true), "i": .int(45), "d": .double(1.25), "x": .data(Data([1, 2, 3]))]
        let back = try JSONDecoder().decode([String: PrefValue].self, from: JSONEncoder().encode(values))
        #expect(back == values)
        #expect(PrefValue.from(NSNumber(value: true)) == .bool(true))
        #expect(PrefValue.from(NSNumber(value: 7)) == .int(7))
        #expect(PrefValue.from(NSNumber(value: 0.5)) == .double(0.5))
        #expect(PrefValue.from(Date()) == nil)
        // Uygulama: yalnız cihazda olmayan anahtar yazılır.
        let suite = "p7-prefs-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("rahat", forKey: "listening.mode")
        BackupManifest.applyPreferenceValues(["listening.mode": .string("sinav"), "coach.dailyGoalMinutes": .int(60)], to: defaults)
        #expect(defaults.string(forKey: "listening.mode") == "rahat")
        #expect(defaults.integer(forKey: "coach.dailyGoalMinutes") == 60)
        defaults.set(true, forKey: "coach.x")
        defaults.set("y", forKey: "ilgisiz")
        let collected = BackupManifest.collectPreferenceValues(defaults)
        #expect(collected["coach.x"] == .bool(true) && collected["ilgisiz"] == nil && collected["listening.mode"] == .string("rahat"))
    }

    @Test func manifestV2RestoresNewModels() throws {
        let source = ModelContext(try memoryContainer())
        let day = ListeningDay(day: "2026-10-01")
        day.seconds = 900
        source.insert(day)
        source.insert(TimedNote(lessonID: UUID(), time: 12, text: "not"))
        source.insert(FollowedChannel(url: "https://youtube.com/@kanal", title: "Kanal"))
        let attempt = RecallAttempt(source: "quiz", question: "Soru?", episodeID: UUID(), episodeTitle: "Bölüm", chapterIndex: 2)
        attempt.isCorrect = true
        attempt.confidence = 2
        source.insert(attempt)
        source.insert(EpisodeProbe(episodeID: UUID(), episodeTitle: "Bölüm", dueDate: .now, stage: 3))
        source.insert(LiveExchange(episodeID: nil, episodeTitle: "", question: "Neden?", answer: "Çünkü", chapterIndex: nil, time: 4, mode: "teach"))
        try source.save()
        let folder = try tempDir()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Backup.manifest(context: source).encoded().write(to: folder.appending(path: "manifest.json"))

        let target = ModelContext(try memoryContainer())
        _ = try Backup.restore(from: folder, context: target)
        #expect(try target.fetch(FetchDescriptor<ListeningDay>()).first?.seconds == 900)
        #expect(try target.fetchCount(FetchDescriptor<TimedNote>()) == 1)
        #expect(try target.fetchCount(FetchDescriptor<FollowedChannel>()) == 1)
        let restored = try #require(try target.fetch(FetchDescriptor<RecallAttempt>()).first)
        #expect(restored.id == attempt.id && restored.isCorrect == true && restored.confidence == 2 && restored.chapterIndex == 2)
        #expect(try target.fetch(FetchDescriptor<EpisodeProbe>()).first?.stage == 3)
        #expect(try target.fetch(FetchDescriptor<LiveExchange>()).first?.mode == "teach")
        // İkinci geri yükleme eklemelidir: aynı kimlikler atlanır.
        _ = try Backup.restore(from: folder, context: target)
        #expect(try target.fetchCount(FetchDescriptor<RecallAttempt>()) == 1)
        #expect(try target.fetchCount(FetchDescriptor<ListeningDay>()) == 1)
    }

    // MARK: - #49 artımlı fark

    @Test func incrementalBackupSkipsUnchangedFiles() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appending(path: "a.m4a"), b = dir.appending(path: "b.json"), c = dir.appending(path: "c.json")
        try Data(repeating: 1, count: 4096).write(to: a)
        try Data("{}".utf8).write(to: b)
        try Data("{}".utf8).write(to: c)   // b ile aynı içerik
        let entries = [Backup.Entry(path: "Audio/a.m4a", url: a), Backup.Entry(path: "EpisodeFiles/x/b.json", url: b),
                       Backup.Entry(path: "EpisodeFiles/x/c.json", url: c)]
        var cache: [String: BackupHashCache.Entry] = [:]
        let first = try BackupHashCache.items(for: entries, cache: &cache)
        #expect(first.hashed == 3)
        #expect(first.items[0].record.sha256.count == 64)
        #expect(first.items[1].record.sha256 == first.items[2].record.sha256)
        // Değişmeyen dosya yeniden okunmaz.
        let second = try BackupHashCache.items(for: entries, cache: &cache)
        #expect(second.hashed == 0)
        #expect(second.items.map(\.record) == first.items.map(\.record))
        // Sunucuda olan içerik gönderilmez; aynı içerik bir kez gider.
        let missing: Set<String> = [first.items[1].record.sha256]
        let plan = MacBackup.uploadPlan(items: second.items, missing: missing, budget: 1_000_000)
        #expect(plan.uploads.map(\.record.path) == ["EpisodeFiles/x/b.json"])
        #expect(plan.complete)
        // Bütçe aşılırsa kalanı sonraki çalışmaya kalır (commit yok).
        let tight = MacBackup.uploadPlan(items: second.items, missing: Set(second.items.map(\.record.sha256)), budget: 100)
        #expect(!tight.complete && tight.uploads.map(\.record.path) == ["EpisodeFiles/x/b.json"])
        // Dosya değişirse yeniden hesaplanır.
        try Data(repeating: 2, count: 5000).write(to: a)
        let third = try BackupHashCache.items(for: entries, cache: &cache)
        #expect(third.hashed == 1 && third.items[0].record.sha256 != first.items[0].record.sha256)
    }

    @Test func restoreSuggestionAndSafePaths() {
        #expect(MacBackup.shouldSuggestRestore(episodes: 0, cards: 0, notes: 0, hasSnapshot: true))
        #expect(!MacBackup.shouldSuggestRestore(episodes: 0, cards: 1, notes: 0, hasSnapshot: true))
        #expect(!MacBackup.shouldSuggestRestore(episodes: 0, cards: 0, notes: 1, hasSnapshot: true))
        #expect(!MacBackup.shouldSuggestRestore(episodes: 0, cards: 0, notes: 0, hasSnapshot: false))
        #expect(MacBackup.isDue(lastAt: nil))
        #expect(!MacBackup.isDue(lastAt: Date.now.addingTimeInterval(-3600)))
        #expect(MacBackup.isDue(lastAt: Date.now.addingTimeInterval(-25 * 3600)))
        #expect(MacBackup.safeRelativePath("Audio/\(UUID().uuidString).m4a") != nil)
        #expect(MacBackup.safeRelativePath("manifest.json") != nil)
        #expect(MacBackup.safeRelativePath("../etc/passwd") == nil)
        #expect(MacBackup.safeRelativePath("/Audio/a.m4a") == nil)
        #expect(MacBackup.safeRelativePath("Audio//a.m4a") == nil)
        #expect(MacBackup.safeRelativePath("SceneMasters/a.caf") == nil)
        #expect(BackupBlobID.isValid(String(repeating: "a", count: 64)))
        #expect(!BackupBlobID.isValid(String(repeating: "A", count: 64)))
    }

    @Test func backupEntriesUseFolderLayoutAndSkipSceneFiles() throws {
        let context = ModelContext(try memoryContainer())
        let script = PodcastScript(title: "T", summary: "", keyPoints: [], chapters: [], sourceNotes: "", quality: nil)
        let episode = Episode(script: script, settings: PodcastSettings(), sourceNames: [], jobToken: "")
        episode.statusRaw = "ready"
        episode.audioFileName = "podcast.m4a"
        context.insert(episode)
        defer { EpisodeFiles.remove(episode: episode.id) }
        try Data([0]).write(to: episode.directory.appending(path: "podcast.m4a"))
        try Data("{}".utf8).write(to: episode.directory.appending(path: "figure_map.json"))
        try Data([0]).write(to: episode.directory.appending(path: "chirp_scene_0001.wav"))
        let paths = try Backup.entries(context: context).map(\.path)
        #expect(paths.contains("Audio/\(episode.id.uuidString).m4a"))
        #expect(paths.contains("EpisodeFiles/\(episode.id.uuidString)/figure_map.json"))
        #expect(!paths.contains { $0.hasSuffix(".wav") })
    }

    // MARK: - #45 föy

    @Test func studySheetHasLinksGuestNamesAndOpenQuestions() throws {
        let id = UUID()
        var settings = PodcastSettings()
        settings.guest = Host(name: "Dr. Ece", voice: "Leda")
        var tl = timeline([("Merhaba", 0), ("Soru", 30)], chapters: [("Giriş", 0), ("Mitoz", 75)])
        tl.turns[1].speaker = .c
        let study = StudyPack(quiz: [QuizItem(question: "Mitozu anlat.", options: [], answerIndex: -1, explanation: "",
                                              kind: "open", answerText: "Hücre bölünmesidir."),
                                     QuizItem(question: "Hangisi?", options: ["A", "B"], answerIndex: 1, explanation: "Çünkü B.")],
                              flashcards: [], concepts: nil, formulas: [Formula(name: "Hız", expression: "v = x / t", meaning: "yol bölü zaman", when: "")])
        let input = StudySheetInput(id: id, title: "Hücre", script: nil, settings: settings, timeline: tl, study: study,
                                    bookmarks: [.init(time: 30, text: "Önemli", note: "sınavda", kind: "flag")],
                                    cornell: [.init(title: "Mitoz", cues: "Evreler?", notes: "Profaz…", summary: "Dört evre")])
        let md = StudySheetExport.markdown(input)
        #expect(md.contains("(kocum://episode/\(id.uuidString)?t=75)"))
        #expect(md.contains("(kocum://episode/\(id.uuidString)?t=30)"))
        #expect(md.contains("**Dr. Ece**"))
        #expect(md.contains("Cevap: **Hücre bölünmesidir.**"))
        #expect(md.contains("**B** ✓"))
        #expect(md.contains("## Cornell notları") && md.contains("## Formüller") && md.contains("`v = x / t`"))
        // PDF'te başlık bağlantıları tıklanabilir alandır.
        let pdf = try #require(PDFDocument(data: StudySheetExport.pdfData(sections: [md])))
        let links = (0..<pdf.pageCount).flatMap { pdf.page(at: $0)?.annotations ?? [] }.compactMap(\.url)
        #expect(links.contains { $0.scheme == "kocum" && $0.absoluteString.contains("t=75") })
    }

    // MARK: - #44 bölüm işaretli ses, klip, akış

    @Test func chapterMarksNormalizeAndClipRange() {
        let marks = ChapterAudioExport.normalized([ChapterMark(title: "B", start: 30), ChapterMark(title: "A", start: 2),
                                                   ChapterMark(title: "Taşan", start: 500)], duration: 100)
        #expect(marks.map(\.title) == ["A", "B"])
        #expect(marks[0].start == 0 && marks[0].duration == 30 && marks[1].duration == 70)
        #expect(ClipShare.range(start: 10, duration: 600) == (10, 70))
        #expect(ClipShare.range(start: 590, duration: 600) == (540, 600))
        #expect(ClipShare.range(start: -5, duration: 30) == (0, 30))
        let id = UUID()
        #expect(PodcastFeed.needsRepublish(id: id, revision: 2, published: [id], revisions: [id: 1]))
        #expect(!PodcastFeed.needsRepublish(id: id, revision: 2, published: [id], revisions: [id: 2]))
        #expect(!PodcastFeed.needsRepublish(id: id, revision: 3, published: [], revisions: [:]))
    }

    /// Prototip: AVAssetWriter ile `.m4a`'ya bölüm metin izi. Yazıcı reddederse işaretsiz dosya yazılır ve test bunu belgeler.
    @Test func assetWriterChapterTrackReadsBack() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "src.m4a")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        do {
            let file = try AVAudioFile(forWriting: source, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
                                                                      AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000])
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100 * 4))
            buffer.frameLength = 44_100 * 4
            let samples = try #require(buffer.floatChannelData?[0])
            for i in 0..<Int(buffer.frameLength) { samples[i] = Float(sin(Double(i) * 2 * .pi * 440 / 44_100) * 0.2) }
            try file.write(from: buffer)
        }
        let output = dir.appending(path: "out.m4a")
        let cover = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).jpegData(withCompressionQuality: 0.8) { ctx in
            UIColor.systemIndigo.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let written = try await ChapterAudioExport.write(audio: source, chapters: [ChapterMark(title: "Giriş", start: 0), ChapterMark(title: "Mitoz", start: 2)],
                                                         title: "Deneme", artist: "Dersdaş", cover: cover, to: output)
        let asset = AVURLAsset(url: output)
        #expect(try await asset.load(.duration).seconds > 3.5)
        // Prototip sonucu: 'tx3g' bölüm metin izi kabul edildi (QuickTime 'text' biçimi -11800 ile reddediliyordu).
        #expect(written)
        let chapters = try await ChapterAudioExport.readChapters(output)
        #expect(chapters.map(\.title) == ["Giriş", "Mitoz"])
        #expect(abs((chapters.last?.start ?? 0) - 2) < 0.1)
        let artwork = AVMetadataItem.metadataItems(from: try await asset.load(.commonMetadata), filteredByIdentifier: .commonIdentifierArtwork)
        #expect(!artwork.isEmpty)
        // Bölüm işaretsiz istekte de dosya yazılır.
        #expect(try await ChapterAudioExport.write(audio: source, chapters: [], title: "Deneme", artist: "", cover: nil, to: output) == false)
        #expect(try await ChapterAudioExport.readChapters(output).isEmpty)
    }

    // MARK: - #35 konu ağacı

    @Test func topicTreeTagsBuildAndWeakest() {
        let e1 = UUID(), e2 = UUID()
        let response = TopicsResponse(subjects: [
            .init(name: "Biyoloji", units: [.init(name: "Hücre", topics: [
                .init(name: "Mitoz", refs: [.init(episodeId: e1.uuidString.lowercased(), chapter: 0)]),
                .init(name: "Mayoz", refs: [.init(episodeId: e1.uuidString, chapter: 1), .init(episodeId: e2.uuidString, chapter: 0),
                                            .init(episodeId: UUID().uuidString, chapter: 0)]),
            ])]),
        ], confusables: [.init(a: "Mitoz", b: "Mayoz", why: "İkisi de bölünme", refs: [])])
        let tags = TopicTree.tags(from: response, known: [e1, e2])
        #expect(tags[e1]?.count == 2 && tags[e2]?.count == 1)
        let scores: [TopicTag.Ref: Double] = [.init(episodeID: e1, chapter: 0): 0.9, .init(episodeID: e1, chapter: 1): 0.2,
                                               .init(episodeID: e2, chapter: 0): 0.4]
        let tree = TopicTree.build(tags.map { (episodeID: $0.key, tags: $0.value) }, scores: scores)
        #expect(tree.first?.units.first?.topics.map(\.name) == ["Mayoz", "Mitoz"])
        let weak = TopicTree.weakest(tree)
        #expect(weak?.name == "Mayoz")
        #expect(abs((weak?.mastery ?? 0) - 0.3) < 0.0001)
        #expect(TopicTree.percent(0.3) == "%30")
        let request = TopicTree.request([.init(id: e1, title: "Hücre", course: nil, chapters: ["A", "B"], concepts: Array(repeating: "k", count: 40))])
        #expect(request.episodes.first?.concepts.count == 30 && request.episodes.first?.chapters.last?.i == 1)
    }
    // MARK: - İnceleme düzeltmeleri

    @Test func derivedOfSeriesMemberStaysVisibleAndChainsFoldToTop() {
        let s = UUID()
        let member = item("Biyoloji 2", created: 1, series: s, index: 2)
        let recap = item("Hızlı tekrar", created: 2, derived: "recap", parent: member.id)
        let diff = item("Farkı ne?", created: 3, derived: "discriminate", parent: member.id)
        let root = item("Ana", created: 4)
        let child = item("Tekrar", created: 5, derived: "recap", parent: root.id)
        let grandchild = item("Tekrarın tekrarı", created: 6, derived: "recap", parent: child.id)
        let seriesChild = item("Seri üyesi türev", created: 7, derived: "video", parent: root.id, series: s, index: 3)
        let ordered = [member, recap, diff, root, child, grandchild, seriesChild]
        let rows = LibraryGrouping.rows(ordered, collapseSeries: true)
        // Seri kartına dönen ana bölümün türevleri kendi satırında; seri üyesi türev seri kartında.
        #expect(rows == [.series(s), .episode(recap.id, children: []), .episode(diff.id, children: []),
                         .episode(root.id, children: [child.id, grandchild.id])])
        // Seri açık listelenince (filtreli görünüm) türevler ana bölümün altına katlanır.
        let flat = LibraryGrouping.rows(ordered, collapseSeries: false)
        #expect(flat == [.episode(member.id, children: [recap.id, diff.id]),
                         .episode(root.id, children: [child.id, grandchild.id, seriesChild.id])])
        // Her bölüm ya satırda ya bir satırın altında görünür (hiçbiri kaybolmaz); döngü kilitlemez.
        var loopA = item("A", created: 1, derived: "recap"), loopB = item("B", created: 2, derived: "recap")
        loopA.parentID = loopB.id
        loopB.parentID = loopA.id
        for set in [ordered, [loopA, loopB]] {
            for collapse in [true, false] {
                let r = LibraryGrouping.rows(set, collapseSeries: collapse)
                var shown = Set<UUID>()
                for row in r {
                    switch row {
                    case let .episode(id, children): shown.insert(id); shown.formUnion(children)
                    case let .series(sid): shown.formUnion(set.filter { $0.seriesID == sid }.map(\.id))
                    }
                }
                #expect(shown == Set(set.map(\.id)))
            }
        }
    }

    @Test func autoBackupHoldsForEmptyDeviceAndForeignSnapshots() {
        let old = BackupSnapshotInfo(id: "s1", createdAt: "2026-09-01T10:00:00Z", device: "iPhone", files: 120, bytes: 900_000_000)
        let empty = BackupSnapshotInfo(id: "s2", createdAt: "2026-10-01T10:00:00Z", device: "iPhone", files: 1, bytes: 2_000)
        // Cihaz boş ve Mac'te yedek var: otomatik yedek tutulur (boş snapshot asıl yedeğin yerine geçmez).
        #expect(MacBackup.autoHold(episodes: 0, cards: 0, notes: 0, hasLineage: false, snapshots: [old]) == .deviceEmpty)
        #expect(MacBackup.autoHold(episodes: 0, cards: 0, notes: 0, hasLineage: true, snapshots: [old]) == .deviceEmpty)
        // Yeniden kurulum + yeni bölüm: bu kurulum hiç yedeklemedi, eski yedekler döndürülmesin.
        #expect(MacBackup.autoHold(episodes: 1, cards: 0, notes: 0, hasLineage: false, snapshots: [old]) == .foreignSnapshots)
        // Kendi yedeğinin devamı ya da Mac'te hiç yedek yok: çalışır.
        #expect(MacBackup.autoHold(episodes: 3, cards: 0, notes: 0, hasLineage: true, snapshots: [old]) == nil)
        #expect(MacBackup.autoHold(episodes: 0, cards: 0, notes: 0, hasLineage: false, snapshots: []) == nil)
        // Öneri: yalnız manifest'li (boş) yeni snapshot yerine içerikli olan; hepsi boşsa en yenisi.
        #expect(MacBackup.preferredSnapshot([old, empty])?.id == "s1")
        #expect(MacBackup.preferredSnapshot([empty])?.id == "s2")
        let newer = BackupSnapshotInfo(id: "s3", createdAt: "2026-10-02T10:00:00Z", device: "iPhone", files: 130, bytes: 950_000_000)
        #expect(MacBackup.preferredSnapshot([old, empty, newer])?.id == "s3")
        #expect(MacBackup.preferredSnapshot([]) == nil)
    }

    @Test func hashCacheKeepsProgressWhenCancelled() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = (0..<3).map { dir.appending(path: "f\($0).m4a") }
        for (i, url) in urls.enumerated() { try Data(repeating: UInt8(i + 1), count: 2048).write(to: url) }
        let entries = urls.enumerated().map { Backup.Entry(path: "Audio/f\($0.offset).m4a", url: $0.element) }
        let stale = BackupHashCache.Entry(bytes: 1, mtime: 0, sha256: String(repeating: "0", count: 64))
        var cache: [String: BackupHashCache.Entry] = ["Audio/eski.m4a": stale]
        // İlk dosya özetlendikten sonra süre doluyor.
        var checks = 0
        #expect(throws: CancellationError.self) {
            _ = try BackupHashCache.items(for: entries, cache: &cache, isCancelled: { checks += 1; return checks > 1 })
        }
        #expect(cache["Audio/f0.m4a"]?.sha256.count == 64)
        #expect(cache["Audio/f1.m4a"] == nil)
        #expect(cache["Audio/eski.m4a"] == stale)
        // Sonraki çalışma ilk dosyayı yeniden okumaz; tamamlanınca var olmayan kayıt atılır.
        let next = try BackupHashCache.items(for: entries, cache: &cache)
        #expect(next.hashed == 2)
        #expect(cache.count == 3 && cache["Audio/eski.m4a"] == nil)
    }

    @Test func feedMetaRespectsServerLimits() {
        let long = String(repeating: "ş", count: 280) + String(repeating: "😀", count: 20)
        let chapters = (0..<250).map { TimedChapter(id: $0, title: long, start: $0 == 0 ? -3 : Double($0) * 10) }
        let meta = FeedMetaV2Request(id: UUID(), title: "  " + long + "  ", summary: String(repeating: "a", count: 5000),
                                     chapters: chapters, duration: 100_000, createdAt: .now, cover: nil, revision: 2)
        #expect(meta.title.utf16.count <= 300 && meta.title.hasPrefix("şşş"))
        #expect(!meta.title.hasSuffix("\u{FFFD}"))
        #expect(meta.chapters.count == 200)
        #expect(meta.chapters.allSatisfy { $0.title.utf16.count <= 300 && $0.start >= 0 })
        #expect(meta.description.utf16.count <= 4000)
        #expect(meta.durationSec == 86_400)
        #expect(FeedMetaV2Request(id: UUID(), title: "   ", summary: "", chapters: [], duration: 10, createdAt: .now,
                                  cover: nil, revision: nil).title == "Bölüm")
        #expect(FeedLimits.clip("ab😀", 3) == "ab")
        #expect(EpisodeTitle.cleaned("  " + String(repeating: "x", count: 500)) == String(repeating: "x", count: EpisodeTitle.maxLength))
        #expect(EpisodeTitle.cleaned("   ") == nil)
    }

    @Test func studySheetPDFMarksTruncationAndRendersOffMain() async throws {
        let md = "# Uzun\n\n" + Array(repeating: "Satır metni uzun bir paragraf olarak tekrar ediyor.", count: 400).joined(separator: "\n")
        let pdf = try #require(PDFDocument(data: StudySheetExport.pdfData(sections: [md], maxPages: 1)))
        #expect(pdf.pageCount == 2)
        #expect(pdf.page(at: 1)?.string?.contains("kısaltıldı") == true)
        // Kısa bölümde not yok.
        let short = try #require(PDFDocument(data: StudySheetExport.pdfData(sections: ["# Kısa\n\nMetin"])))
        #expect(short.pageCount == 1 && short.page(at: 0)?.string?.contains("kısaltıldı") != true)
        // Arka planda yazım.
        let url = try tempDir().appending(path: "f.pdf")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try await StudySheetExport.writePDF(sections: [md], to: url)
        #expect((PDFDocument(url: url)?.pageCount ?? 0) >= 2)
    }

    // MARK: - İnceleme düzeltmeleri

    @Test func searchIndexReadsTranscriptOnlyWhenEpisodeChanges() async throws {
        let index = EpisodeSearchIndex()
        let a = UUID(), b = UUID()
        var reads: [UUID: Int] = [:]
        let dataA = try JSONEncoder().encode(timeline([("Mitoz bölünmesi", 12)]))
        let dataB = try JSONEncoder().encode(timeline([("Işık kırılması", 30)]))
        func entries(versionA: Int = 1, includeB: Bool = true, newA: Data? = nil) -> [EpisodeSearchIndex.Entry] {
            var list = [EpisodeSearchIndex.Entry(meta: .init(id: a, title: "Biyoloji", sources: []), version: versionA,
                                                 timelineData: { reads[a, default: 0] += 1; return newA ?? dataA })]
            if includeB {
                list.append(.init(meta: .init(id: b, title: "Fizik", sources: ["Optik.pdf"]), version: 1,
                                  timelineData: { reads[b, default: 0] += 1; return dataB }))
            }
            return list
        }
        // İlk arama tüm transkriptleri bir kez okur.
        #expect(await index.search("mitoz", entries: entries()).first?.time == 12)
        #expect(index.lastReads == 2)
        // Sonraki aramalar transkripte dokunmadan dizinden bulur.
        #expect(await index.search("ışık", entries: entries()).first?.time == 30)
        #expect(await index.search("isik kirilmasi", entries: entries()).first?.field == .transcript)
        #expect(index.lastReads == 0 && reads[a] == 1 && reads[b] == 1)
        // Sesi değişen bölüm yeniden dizinlenir.
        let changed = try JSONEncoder().encode(timeline([("Mayoz bölünmesi", 44)]))
        #expect(await index.search("mayoz", entries: entries(versionA: 2, newA: changed)).first?.time == 44)
        #expect(index.lastReads == 1 && reads[a] == 2)
        // Silinen bölüm dizinden düşer.
        #expect(await index.search("ışık", entries: entries(versionA: 2, includeB: false, newA: changed)).isEmpty)
        #expect(await index.store.indexedEpisodes == 1)
        #expect(EpisodeSearchIndex.version(status: "ready", audioRevision: 1, duration: 60, scenesDone: 3)
                != EpisodeSearchIndex.version(status: "ready", audioRevision: 2, duration: 60, scenesDone: 3))
    }

    @Test func backupQuotaBlocksAutoRunAndKeepsNewestSnapshot() {
        let now = Date.now
        #expect(!MacBackup.isQuotaBlocked(quotaAt: nil, now: now))
        #expect(MacBackup.isQuotaBlocked(quotaAt: now.addingTimeInterval(-3600), now: now))
        #expect(!MacBackup.isQuotaBlocked(quotaAt: now.addingTimeInterval(-25 * 3600), now: now))
        // Saat geri alındıysa bekleme uygulanmaz.
        #expect(!MacBackup.isQuotaBlocked(quotaAt: now.addingTimeInterval(3600), now: now))
        #expect(APIError(status: 507, code: "quota_exceeded", message: "").isBackupQuotaExceeded)
        #expect(APIError(status: 500, code: "quota_exceeded", message: "").isBackupQuotaExceeded)
        #expect(!APIError(status: 409, code: "conflict", message: "").isBackupQuotaExceeded)
        // 15 snapshot (karışık sırada): en yenisi korunur; en yeni 13'ün dışındakileri Mac sonraki yedekte siler.
        let list = (0..<15).map { i in
            BackupSnapshotInfo(id: "s\(i)", createdAt: now.addingTimeInterval(-Double(i) * 86_400).ISO8601Format(), device: "iPhone",
                               files: 10, bytes: 1_000)
        }.shuffled()
        let roles = MacBackup.snapshotRoles(list)
        #expect(!roles.deletable.contains("s0") && roles.deletable.count == 14)
        #expect(roles.expiring == ["s13", "s14"])
        #expect(MacBackup.snapshotRoles([list[0]]).deletable.isEmpty)
    }

    @Test func backupEntrySourcesResolveOffMain() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("a".utf8).write(to: dir.appending(path: "b.json"))
        try Data("a".utf8).write(to: dir.appending(path: "a.png"))
        try Data("a".utf8).write(to: dir.appending(path: "scene.wav"))
        let present = dir.appending(path: "x.m4a")
        try Data("a".utf8).write(to: present)
        let sources: [Backup.EntrySource] = [
            .file(Backup.Entry(path: "Audio/x.m4a", url: present)),
            .file(Backup.Entry(path: "Audio/yok.m4a", url: dir.appending(path: "yok.m4a"))),
            .folder(prefix: "EpisodeFiles/e", directory: dir, extensions: ["json", "png"]),
            .folder(prefix: "Videos/v", directory: dir.appending(path: "olmayan"), extensions: ["jpg"]),
        ]
        let paths = await Task.detached { Backup.entries(from: sources).map(\.path) }.value
        #expect(paths == ["Audio/x.m4a", "EpisodeFiles/e/a.png", "EpisodeFiles/e/b.json"])
    }

    @Test func feedCleanupOnlyTouchesOwnOrPendingEpisodes() {
        let kept = UUID(), deletedMine = UUID(), deletedPending = UUID(), foreign = UUID(), restored = UUID()
        let server: Set = [kept, deletedMine, deletedPending, foreign, restored]
        let stale = PodcastFeed.staleOnServer(server: server, device: [kept, restored], mine: [kept, deletedMine],
                                              pending: [deletedPending, restored, UUID()])
        // Cihazda silinmiş (bu kurulumun ya da bekleyen) bölümler çıkar; yabancı ve geri yüklenen bölüme dokunulmaz.
        #expect(stale == [deletedMine, deletedPending])
        // Yeni kurulum (kendi kaydı yok): sunucudaki eski bölümler silinmez.
        #expect(PodcastFeed.staleOnServer(server: server, device: [], mine: [], pending: []).isEmpty)
    }
}
