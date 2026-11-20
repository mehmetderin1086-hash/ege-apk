import Foundation
import Testing
import UIKit
@testable import Ikra

/// YouTube çalışma / dinleme / kütüphane iyileştirmeleri (dalga 1–2): saf mantık (ağ ve arayüz yok).
/// Dosya/UserDefaults deposu sınayan birkaç test geçici klasör ya da özel suite kullanır ve ardından temizler.
@MainActor
@Suite struct ImproveYoutubeCalismaTests {
    // MARK: - Otomatik içe aktarma kuyruğu: hata politikası

    private func apiError(_ status: Int, _ code: String, _ message: String = "x") -> APIError {
        APIError(status: status, code: code, message: message)
    }

    @Test func queueErrorKindSeparatesGeneralFromItemFailures() {
        #expect(ImportQueuePolicy.kind(of: APIError.network(URLError(.notConnectedToInternet))) == .transient)
        #expect(ImportQueuePolicy.kind(of: URLError(.timedOut)) == .transient)
        #expect(ImportQueuePolicy.kind(of: apiError(429, "quota")) == .transient)
        #expect(ImportQueuePolicy.kind(of: apiError(500, "http_500")) == .transient)
        #expect(ImportQueuePolicy.kind(of: apiError(503, "http_503")) == .transient)
        #expect(ImportQueuePolicy.kind(of: apiError(401, "unauthorized")) == .auth)
        #expect(ImportQueuePolicy.kind(of: apiError(0, "job")) == .item)
        #expect(ImportQueuePolicy.kind(of: apiError(0, "cancelled")) == .item)
        #expect(ImportQueuePolicy.kind(of: apiError(400, "invalid_request")) == .item)
        #expect(ImportQueuePolicy.kind(of: apiError(404, "not_found")) == .item)
        #expect(ImportQueuePolicy.kind(of: CocoaError(.fileNoSuchFile)) == .item)
    }

    @Test func queuePauseReasonNamesTheCause() {
        #expect(ImportQueuePolicy.pauseReason(for: APIError.network(URLError(.notConnectedToInternet))) == ImportQueuePolicy.offlineReason)
        #expect(ImportQueuePolicy.pauseReason(for: URLError(.networkConnectionLost)) == ImportQueuePolicy.offlineReason)
        #expect(ImportQueuePolicy.offlineReason.hasPrefix("Bağlantı yok"))
        #expect(ImportQueuePolicy.pauseReason(for: apiError(429, "quota", "Günlük hak doldu.")) == "Günlük hak doldu.")
        #expect(ImportQueuePolicy.pauseReason(for: apiError(401, "unauthorized", "Erişim anahtarı yok.")) == "Erişim anahtarı yok.")
    }

    @Test func queueKeepsEveryItemOnTransientOrAuthFailure() {
        let a = QueuedImport(url: "https://youtu.be/AAAAAAAAAAA", title: "A")
        let b = QueuedImport(url: "https://youtu.be/BBBBBBBBBBB", title: "B")
        let c = QueuedImport(url: "https://youtu.be/CCCCCCCCCCC", title: "C")
        for kind in [ImportFailureKind.transient, .auth] {
            let outcome = ImportQueuePolicy.applyFailure([a, b, c], id: a.id, kind: kind, maxAttempts: 2)
            #expect(outcome.items == [a, b, c])
            #expect(outcome.items.first?.attempts == 0)
            #expect(outcome.stop)
        }
    }

    @Test func queueMovesFailedItemToTheEndThenDropsIt() {
        let a = QueuedImport(url: "https://youtu.be/AAAAAAAAAAA", title: "A")
        let b = QueuedImport(url: "https://youtu.be/BBBBBBBBBBB", title: "B")
        let c = QueuedImport(url: "https://youtu.be/CCCCCCCCCCC", title: "C")
        let first = ImportQueuePolicy.applyFailure([a, b, c], id: a.id, kind: .item, maxAttempts: 2)
        #expect(first.items.map(\.id) == [b.id, c.id, a.id])
        #expect(first.items.map(\.attempts) == [0, 0, 1])
        #expect(!first.stop)
        // İkinci hata: sınıra ulaşan öğe kuyruktan çıkar, ötekiler yerinde kalır.
        var retried = a
        retried.attempts = 1
        let second = ImportQueuePolicy.applyFailure([retried, b, c], id: a.id, kind: .item, maxAttempts: 2)
        #expect(second.items == [b, c])
        #expect(!second.stop)
        // Öğe bu arada kuyruktan çıkmışsa liste değişmez.
        let missing = ImportQueuePolicy.applyFailure([b, c], id: a.id, kind: .item, maxAttempts: 2)
        #expect(missing.items == [b, c])
        #expect(!missing.stop)
    }

    @Test func queueServerFailureYieldsItsTurnWithoutBurningAttempts() {
        // 5xx genel de olabilir videoya özgü de: kuyruk bekler (transient) ama öğe sona geçer, deneme hakkı yanmaz.
        #expect(ImportQueuePolicy.isServerFailure(apiError(500, "internal")))
        #expect(ImportQueuePolicy.isServerFailure(apiError(502, "upstream_error")))
        #expect(ImportQueuePolicy.isServerFailure(apiError(503, "http_503")))
        #expect(ImportQueuePolicy.kind(of: apiError(502, "upstream_error")) == .transient)
        #expect(!ImportQueuePolicy.isServerFailure(APIError.network(URLError(.notConnectedToInternet))))
        #expect(!ImportQueuePolicy.isServerFailure(URLError(.timedOut)))
        #expect(!ImportQueuePolicy.isServerFailure(apiError(429, "daily_limit")))
        #expect(!ImportQueuePolicy.isServerFailure(apiError(401, "unauthorized")))
        #expect(!ImportQueuePolicy.isServerFailure(apiError(400, "invalid_request")))
        #expect(!ImportQueuePolicy.isServerFailure(apiError(0, "job")))

        var tried = QueuedImport(url: "https://youtu.be/AAAAAAAAAAA", title: "A")
        tried.attempts = 1
        let b = QueuedImport(url: "https://youtu.be/BBBBBBBBBBB", title: "B")
        let c = QueuedImport(url: "https://youtu.be/CCCCCCCCCCC", title: "C")
        #expect(ImportQueuePolicy.movedToEnd([tried, b, c], id: tried.id) == [b, c, tried])
        #expect(ImportQueuePolicy.movedToEnd([b, tried], id: tried.id) == [b, tried])
        #expect(ImportQueuePolicy.movedToEnd([tried], id: tried.id) == [tried])
        #expect(ImportQueuePolicy.movedToEnd([b, c], id: tried.id) == [b, c])
        #expect(ImportQueuePolicy.movedToEnd([], id: tried.id).isEmpty)
    }

    // MARK: - ÖSYM denemesi gezgini

    @Test func examNavListsUnansweredQuestions() {
        #expect(ExamNav.unanswered(count: 5, answers: [0: 1, 3: 2]) == [1, 2, 4])
        #expect(ExamNav.unanswered(count: 3, answers: [0: 0, 1: 0, 2: 0]).isEmpty)
        #expect(ExamNav.unanswered(count: 0, answers: [:]).isEmpty)
        #expect(ExamNav.unanswered(count: -2, answers: [:]).isEmpty)
    }

    @Test func examNavNextUnansweredWrapsAround() {
        let answers = [0: 1, 3: 2]
        #expect(ExamNav.nextUnanswered(after: 3, count: 5, answers: answers) == 4)
        #expect(ExamNav.nextUnanswered(after: 4, count: 5, answers: answers) == 1)
        #expect(ExamNav.nextUnanswered(after: 0, count: 5, answers: answers) == 1)
        // Tek boş geçerli soruysa yerinde kalır.
        #expect(ExamNav.nextUnanswered(after: 2, count: 3, answers: [0: 0, 1: 0]) == 2)
        #expect(ExamNav.nextUnanswered(after: 1, count: 3, answers: [0: 0, 1: 0, 2: 0]) == nil)
        #expect(ExamNav.nextUnanswered(after: 0, count: 0, answers: [:]) == nil)
    }

    // MARK: - İlerleme çubuğu önizlemesi

    @Test func scrubPreviewShowsTargetAndDifference() {
        #expect(ScrubPreview.label(target: 754, current: 674) == "12:34 · +1:20")
        #expect(ScrubPreview.label(target: 30, current: 75) == "00:30 · −0:45")
        #expect(ScrubPreview.label(target: 3725, current: 0) == "1:02:05 · +1:02:05")
    }

    @Test func scrubPreviewDropsTinyDifferenceAndBadValues() {
        #expect(ScrubPreview.label(target: 60, current: 60.4) == "01:00")
        #expect(ScrubPreview.label(target: 60.9, current: 60.1) == "01:00")
        #expect(ScrubPreview.label(target: .nan, current: 10).hasPrefix("00:00"))
        #expect(ScrubPreview.label(target: .infinity, current: .nan) == "00:00")
        #expect(ScrubPreview.label(target: -5, current: 0) == "00:00")
    }

    // MARK: - Kanal takibi

    @Test func channelCheckMessageDoesNotHideFailures() {
        #expect(FeedDiff.checkMessage(ChannelCheckSummary()) == "Yeni video yok.")
        #expect(FeedDiff.checkMessage(ChannelCheckSummary(found: 0, checked: 3)) == "Yeni video yok.")
        #expect(FeedDiff.checkMessage(ChannelCheckSummary(found: 2, checked: 1)) == "2 yeni video bulundu.")
        #expect(FeedDiff.checkMessage(ChannelCheckSummary(found: 2, checked: 1, failed: 1, firstError: "x"))
            == "2 yeni video bulundu. 1 kanal kontrol edilemedi.")
        #expect(FeedDiff.checkMessage(ChannelCheckSummary(failed: 2, firstError: "İnternet bağlantısı yok."))
            == "2 kanal kontrol edilemedi: İnternet bağlantısı yok.")
        #expect(FeedDiff.checkMessage(ChannelCheckSummary(failed: 1)) == "1 kanal kontrol edilemedi.")
    }

    @Test func channelLinkAcceptsBareHandle() {
        #expect(ImportLinks.channelLink("@TEDEd") == "https://www.youtube.com/@TEDEd")
        #expect(ImportLinks.channelLink("  @biyoloji.hocasi_1\n") == "https://www.youtube.com/@biyoloji.hocasi_1")
        #expect(ImportLinks.channelLink("youtube.com/@teded") == "https://youtube.com/@teded")
        #expect(ImportLinks.channelLink("https://www.youtube.com/playlist?list=PLabcdefghij123")
            == "https://www.youtube.com/playlist?list=PLabcdefghij123")
        #expect(ImportLinks.channelLink("merhaba") == nil)
        #expect(ImportLinks.channelLink("@") == nil)
        #expect(ImportLinks.channelLink("@iki kelime") == nil)
        #expect(ImportLinks.channelLink("@teded/videos") == nil)
        #expect(ImportLinks.channelLink("") == nil)
    }

    @Test func channelKeyIgnoresCaseAndTabSuffix() {
        #expect(ImportLinks.channelKey("https://www.youtube.com/@TEDEd/videos") == ImportLinks.channelKey("youtube.com/@teded/featured"))
        #expect(ImportLinks.channelKey("https://m.youtube.com/@TEDEd/") == "yc:@teded")
        #expect(ImportLinks.channelLink("@TEDEd").map(ImportLinks.channelKey) == "yc:@teded")
        #expect(ImportLinks.channelKey("https://www.youtube.com/c/TedEd/streams") == ImportLinks.channelKey("https://youtube.com/c/teded"))
        #expect(ImportLinks.channelKey("https://www.youtube.com/user/TEDEducation") == "yc:user/tededucation")
        #expect(ImportLinks.channelKey("https://www.youtube.com/@a") != ImportLinks.channelKey("https://www.youtube.com/@b"))
    }

    @Test func channelKeyKeepsPlaylistAndChannelIDs() {
        #expect(ImportLinks.channelKey("https://www.youtube.com/playlist?list=PLabcdefghij123") == "yl:PLabcdefghij123")
        // Sunucuyla aynı kural: /watch?list=… oynatma listesidir, kanal adresindeki list= sayılmaz.
        #expect(ImportLinks.channelKey("https://www.youtube.com/watch?v=EKGRs8q7HlA&list=PLabcdefghij123") == "yl:PLabcdefghij123")
        #expect(ImportLinks.channelKey("https://www.youtube.com/@kanal/videos?list=PLabcdefghij123") == "yc:@kanal")
        let id = "UCsooa4yRKGN_zEE8iknghZA"
        #expect(ImportLinks.channelKey("https://www.youtube.com/channel/\(id)/videos") == "yc:channel/\(id)")
        // Kanal kimliği harf duyarlıdır: küçültülmez.
        #expect(ImportLinks.channelKey("https://www.youtube.com/channel/\(id)")
            != ImportLinks.channelKey("https://www.youtube.com/channel/\(id.lowercased())"))
        // Tanınmayan adres eski anahtara düşer.
        #expect(ImportLinks.channelKey("https://vimeo.com/Kanal/") == ImportLinks.dedupeKey("https://vimeo.com/Kanal/"))
        #expect(ImportLinks.channelKey("https://www.youtube.com/") == ImportLinks.dedupeKey("https://www.youtube.com/"))
    }

    // MARK: - Yarıda kapatılan quiz'in yanlışları

    private func question(_ text: String, answer: Int) -> StudyQuestion {
        StudyQuestion(question: text, choices: ["A", "B", "C", "D"], answer: answer)
    }

    @Test func missedCountsOnlyRevealedWrongAnswersWhenClosedEarly() {
        let questions = [question("1", answer: 0), question("2", answer: 1), question("3", answer: 2)]
        #expect(StudyQuizRules.missed(questions, answers: [0: 3, 1: 1], includeUnanswered: false) == [0])
        #expect(StudyQuizRules.missed(questions, answers: [0: 3, 1: 1], includeUnanswered: true) == [0, 2])
        #expect(StudyQuizRules.missed(questions, answers: [:], includeUnanswered: false).isEmpty)
        #expect(StudyQuizRules.missed(questions, answers: [:], includeUnanswered: true) == [0, 1, 2])
        #expect(StudyQuizRules.missed(questions, answers: [0: 0, 1: 1, 2: 2], includeUnanswered: true).isEmpty)
        #expect(StudyQuizRules.missed([], answers: [0: 1], includeUnanswered: true).isEmpty)
    }

    // MARK: - Dalga 2 · Medya işi: hazır dosyayı yeniden kullanma

    @Test func mediaJobReusesReadyFileOnlyForTheSameRequest() {
        let low = MediaStartRequest(kind: .video, url: "https://youtu.be/AAAAAAAAAAA", quality: 360)
        let high = MediaStartRequest(kind: .video, url: "https://youtu.be/AAAAAAAAAAA", quality: 480)
        let key = MediaJobRunner.requestKey(low)
        #expect(!key.isEmpty)
        #expect(key == MediaJobRunner.requestKey(low))
        #expect(key != MediaJobRunner.requestKey(high))
        #expect(MediaJobRunner.reusableFile(readyKey: key, fileId: "f1", requestKey: key) == "f1")
        #expect(MediaJobRunner.reusableFile(readyKey: key, fileId: "f1", requestKey: MediaJobRunner.requestKey(high)) == nil)
        #expect(MediaJobRunner.reusableFile(readyKey: nil, fileId: "f1", requestKey: key) == nil)
        #expect(MediaJobRunner.reusableFile(readyKey: key, fileId: nil, requestKey: key) == nil)
        #expect(MediaJobRunner.reusableFile(readyKey: key, fileId: "", requestKey: key) == nil)
        #expect(MediaJobRunner.reusableFile(readyKey: Data(), fileId: "f1", requestKey: Data()) == nil)
        // Altyazı metni değişince (çeviri ↔ orijinal) dosya yeniden hazırlanır.
        let tr = MediaStartRequest(kind: .subtitled, url: "https://youtu.be/AAAAAAAAAAA", quality: 480, srt: "1\n00:00:00,000 --> 00:00:01,000\nMerhaba\n")
        let en = MediaStartRequest(kind: .subtitled, url: "https://youtu.be/AAAAAAAAAAA", quality: 480, srt: "1\n00:00:00,000 --> 00:00:01,000\nHello\n")
        #expect(MediaJobRunner.requestKey(tr) != MediaJobRunner.requestKey(en))
    }

    // MARK: - Dalga 2 · Altyazılı video önbelleği

    @Test func subtitledCacheFindsOnlyNonEmptyFileAndKeepsMeta() throws {
        let root = URL.temporaryDirectory.appending(path: "subtitled-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let lesson = UUID()
        let file = SubtitledCache.url(lesson: lesson, root: root)
        #expect(file.lastPathComponent == "\(lesson.uuidString).mp4")
        #expect(SubtitledCache.existing(lesson: lesson, root: root)?.url == nil)

        // 0 baytlık (yarım kalmış) dosya sayılmaz.
        try FileManager.default.createDirectory(at: SubtitledCache.folder(root: root), withIntermediateDirectories: true)
        try Data().write(to: file)
        #expect(SubtitledCache.existing(lesson: lesson, root: root)?.url == nil)

        // Meta yoksa (eski sürümün bıraktığı dosya) yine de bulunur.
        try Data([1, 2, 3]).write(to: file)
        let bare = try #require(SubtitledCache.existing(lesson: lesson, root: root))
        #expect(bare.url == file)
        #expect(bare.meta == nil)

        let meta = SubtitledCache.Meta(translated: true, quality: 480, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        SubtitledCache.saveMeta(meta, lesson: lesson, root: root)
        let found = try #require(SubtitledCache.existing(lesson: lesson, root: root))
        #expect(found.url == file)
        #expect(found.meta == meta)
        // Başka dersin dosyası karışmaz.
        #expect(SubtitledCache.existing(lesson: UUID(), root: root)?.url == nil)
    }

    @Test func subtitledCacheSummaryNamesSubtitleAndQuality() {
        let date = Date(timeIntervalSince1970: 0)
        #expect(SubtitledCache.summary(.init(translated: true, quality: 480, createdAt: date)) == "Türkçe çeviri · 480p")
        #expect(SubtitledCache.summary(.init(translated: false, quality: 360, createdAt: date)) == "Orijinal altyazı · 360p")
    }

    // MARK: - Dalga 2 · Feynman taslakları

    private func withScratchDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "ImproveYoutubeCalismaTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    @Test func feynmanDraftSurvivesPerLessonAndTopic() throws {
        try withScratchDefaults { defaults in
            let lesson = UUID()
            #expect(FeynmanDrafts.load(lesson: lesson, topic: -1, defaults: defaults).isEmpty)
            FeynmanDrafts.save("Osmoz suyun geçişidir.", lesson: lesson, topic: -1, defaults: defaults)
            FeynmanDrafts.save("Difüzyon başka.", lesson: lesson, topic: 2, defaults: defaults)
            #expect(FeynmanDrafts.load(lesson: lesson, topic: -1, defaults: defaults) == "Osmoz suyun geçişidir.")
            #expect(FeynmanDrafts.load(lesson: lesson, topic: 2, defaults: defaults) == "Difüzyon başka.")
            #expect(FeynmanDrafts.load(lesson: UUID(), topic: -1, defaults: defaults).isEmpty)
            // Boş metin kaydı siler; öteki konu durur.
            FeynmanDrafts.save("  \n", lesson: lesson, topic: -1, defaults: defaults)
            #expect(FeynmanDrafts.load(lesson: lesson, topic: -1, defaults: defaults).isEmpty)
            #expect(FeynmanDrafts.load(lesson: lesson, topic: 2, defaults: defaults) == "Difüzyon başka.")
            FeynmanDrafts.clear(lesson: lesson, topic: 2, defaults: defaults)
            #expect(FeynmanDrafts.load(lesson: lesson, topic: 2, defaults: defaults).isEmpty)
            #expect(FeynmanDrafts.all(defaults: defaults).isEmpty)
        }
    }

    @Test func feynmanDraftsDropOldestAndClipLongText() throws {
        try withScratchDefaults { defaults in
            let lesson = UUID()
            let start = Date(timeIntervalSince1970: 1_000_000)
            for topic in 0...FeynmanDrafts.limit {
                FeynmanDrafts.save("Taslak \(topic)", lesson: lesson, topic: topic, now: start.addingTimeInterval(Double(topic)), defaults: defaults)
            }
            #expect(FeynmanDrafts.all(defaults: defaults).count == FeynmanDrafts.limit)
            #expect(FeynmanDrafts.load(lesson: lesson, topic: 0, defaults: defaults).isEmpty)
            #expect(FeynmanDrafts.load(lesson: lesson, topic: 1, defaults: defaults) == "Taslak 1")
            #expect(FeynmanDrafts.load(lesson: lesson, topic: FeynmanDrafts.limit, defaults: defaults) == "Taslak \(FeynmanDrafts.limit)")

            let long = String(repeating: "a", count: 6000)
            FeynmanDrafts.save(long, lesson: lesson, topic: 1, now: start.addingTimeInterval(100), defaults: defaults)
            #expect(FeynmanDrafts.load(lesson: lesson, topic: 1, defaults: defaults).count == FeynmanDrafts.maxLength)
            #expect(FeynmanDrafts.maxLength == 5000)
            #expect(LessonFeynmanView.maxAnswer == FeynmanDrafts.maxLength)
        }
    }

    @Test func feynmanTopicSwitchKeepsEachTopicsOwnDraft() throws {
        try withScratchDefaults { defaults in
            let lesson = UUID()
            func stored(_ topic: Int) -> String { FeynmanDrafts.load(lesson: lesson, topic: topic, defaults: defaults) }
            FeynmanDrafts.save("Bölüm 2 anlatımı.", lesson: lesson, topic: 2, defaults: defaults)
            FeynmanDrafts.save("Bölüm 3 anlatımı.", lesson: lesson, topic: 3, defaults: defaults)

            // Alan Bölüm 2'nin taslağıyla doluyken Bölüm 3 seçilir: Bölüm 3'ün taslağı ezilmez, alana o gelir.
            var field = FeynmanDrafts.switchTopic(stored(2), from: 2, to: 3, lesson: lesson, defaults: defaults)
            #expect(field == "Bölüm 3 anlatımı.")
            #expect(stored(2) == "Bölüm 2 anlatımı.")
            #expect(stored(3) == "Bölüm 3 anlatımı.")

            // Henüz kaydedilmemiş yazı eski konuda saklanır; taslağı olmayan konuda alan boşalır.
            field = FeynmanDrafts.switchTopic(field + " Ek cümle.", from: 3, to: -1, lesson: lesson, defaults: defaults)
            #expect(field.isEmpty)
            #expect(stored(3) == "Bölüm 3 anlatımı. Ek cümle.")
            #expect(stored(-1).isEmpty)
            #expect(stored(2) == "Bölüm 2 anlatımı.")

            // Eski konuya dönünce yazılan metin geri gelir; boş alan hiçbir taslağı silmez.
            field = FeynmanDrafts.switchTopic(field, from: -1, to: 3, lesson: lesson, defaults: defaults)
            #expect(field == "Bölüm 3 anlatımı. Ek cümle.")
            #expect(FeynmanDrafts.all(defaults: defaults).count == 2)

            // Alan elle boşaltılıp konu değiştirilirse eski konunun taslağı da silinir.
            field = FeynmanDrafts.switchTopic("", from: 3, to: 2, lesson: lesson, defaults: defaults)
            #expect(field == "Bölüm 2 anlatımı.")
            #expect(stored(3).isEmpty)
        }
    }

    @Test func feynmanTopicSwitchLeavesDraftsAloneWhenFieldAlreadyShowsTheNewTopic() throws {
        try withScratchDefaults { defaults in
            let lesson = UUID()
            func stored(_ topic: Int) -> String { FeynmanDrafts.load(lesson: lesson, topic: topic, defaults: defaults) }
            FeynmanDrafts.save("Tüm ders anlatımı.", lesson: lesson, topic: -1, defaults: defaults)
            FeynmanDrafts.save("Bölüm 1 anlatımı.", lesson: lesson, topic: 1, defaults: defaults)

            // Açılış: konu -1'den açık bölüme atanır ve o bölümün taslağı yüklenir; ardından gelen değişim
            // bildirimi bu metni "Tüm ders" yuvasına yazmamalı.
            #expect(FeynmanDrafts.switchTopic(stored(1), from: -1, to: 1, lesson: lesson, defaults: defaults) == "Bölüm 1 anlatımı.")
            #expect(stored(-1) == "Tüm ders anlatımı.")
            #expect(stored(1) == "Bölüm 1 anlatımı.")

            // Taslağı olmayan bölümle açılış (alan boş): "Tüm ders" taslağı silinmez.
            #expect(FeynmanDrafts.switchTopic("", from: -1, to: 4, lesson: lesson, defaults: defaults).isEmpty)
            #expect(stored(-1) == "Tüm ders anlatımı.")

            // Konu aynı kalıyorsa metin olduğu gibi döner, kayıt değişmez.
            #expect(FeynmanDrafts.switchTopic("Yeni yazı", from: 1, to: 1, lesson: lesson, defaults: defaults) == "Yeni yazı")
            #expect(stored(1) == "Bölüm 1 anlatımı.")
        }
    }

    // MARK: - Dalga 2 · Öğretmenin sesinden özet: kesitler derse yayılır

    private func clips(starts: [Double], length: Double) -> [ClipRange] {
        starts.map { ClipRange(start: $0, end: $0 + length) }
    }

    @Test func spreadPicksClipsAcrossTheWholeLesson() {
        let all = clips(starts: (0..<10).map { Double($0) * 100 }, length: 20)
        let picked = ClipPlanner.spread(all, maxTotal: 60)
        #expect(picked.map(\.start) == [100, 500, 800])
        #expect(picked.reduce(0) { $0 + $1.duration } == 60)
        // Bütçeye sığıyorsa girdi aynen döner.
        #expect(ClipPlanner.spread(all, maxTotal: 200) == all)
        #expect(ClipPlanner.spread(all, maxTotal: 5000) == all)
        #expect(ClipPlanner.spread([], maxTotal: 60).isEmpty)
    }

    @Test func spreadHandlesOversizedAndUnevenClips() {
        // Tek kesit bütçeden uzunsa boş (eski davranış).
        #expect(ClipPlanner.spread([ClipRange(start: 0, end: 90)], maxTotal: 60).isEmpty)
        #expect(ClipPlanner.spread([ClipRange(start: 0, end: 90)], maxTotal: 0).isEmpty)
        #expect(ClipPlanner.spread([ClipRange(start: 0, end: 90)], maxTotal: .nan).isEmpty)
        // Dokuz kısa + sonda bir uzun kesit: uzun sığmaz, artan bütçe kısa kesitlerle dolar (özet boş kalmaz).
        let uneven = clips(starts: (0..<9).map { Double($0) * 100 }, length: 10) + [ClipRange(start: 900, end: 1000)]
        let picked = ClipPlanner.spread(uneven, maxTotal: 100)
        #expect(picked.count == 9)
        #expect(picked.reduce(0) { $0 + $1.duration } == 90)
        #expect(picked == picked.sorted { $0.start < $1.start })
        #expect(ClipPlanner.fit(uneven, maxTotal: 25).map(\.start) == [0, 100])
    }

    @Test func planKeepsTheEndOfTheLessonWhenBudgetIsTight() {
        // Eski davranış ilk iki kesiti alırdı; yeni seçim dersin sonunu da kapsar.
        let three = [TranscriptParagraph(start: 0, end: 20, text: "A"), TranscriptParagraph(start: 100, end: 120, text: "B"),
                     TranscriptParagraph(start: 200, end: 220, text: "C")]
        #expect(ClipPlanner.plan(times: [210, 5, 105], paragraphs: three, maxTotal: 45)
            == [ClipRange(start: 0, end: 20), ClipRange(start: 200, end: 220)])
        // 30 ana nokta × 25 sn = 12,5 dk; sınır 5 dk: kesitler dersin ikinci yarısına da uzanır.
        let many = (0..<30).map { TranscriptParagraph(start: Double($0) * 240, end: Double($0) * 240 + 25, text: "P\($0)") }
        let planned = ClipPlanner.plan(times: many.map(\.start), paragraphs: many, maxTotal: 300)
        #expect(planned.reduce(0) { $0 + $1.duration } <= 300)
        #expect(planned.count == 12)
        #expect((planned.first?.start ?? .infinity) < 600)
        #expect((planned.last?.start ?? 0) > 6000)
        #expect(planned == planned.sorted { $0.start < $1.start })
    }

    // MARK: - Dalga 2 · Kütüphane araması: tümünü göster ve vurgulama

    private func searchDoc(_ title: String, _ paragraphs: [(Double, String)]) -> LibrarySearch.Doc {
        LibrarySearch.Doc(id: UUID(), title: title, channel: "", foldedTitle: LibrarySearch.fold(title),
                          paragraphs: paragraphs.map { .init(start: $0.0, text: $0.1, folded: LibrarySearch.fold($0.1)) },
                          frames: [], chapters: [], keyPoints: [])
    }

    @Test func searchShowsEveryHitForExpandedLesson() {
        let long = searchDoc("Uzun", (0..<20).map { (Double($0 * 10), "osmoz örneği \($0)") })
        let other = searchDoc("Kısa", (0..<8).map { (Double($0 * 10), "osmoz notu \($0)") })
        let collapsed = LibrarySearch.search("osmoz", in: [long, other])
        #expect(collapsed.first?.hits.count == LibrarySearch.maxPerLesson)
        #expect(collapsed.first?.total == 20)
        let expanded = LibrarySearch.search("osmoz", in: [long, other], expanded: [long.id])
        #expect(expanded.first?.lesson == long.id)
        #expect(expanded.first?.hits.count == 20)
        #expect(expanded.first?.total == 20)
        #expect(expanded.first?.hits.map(\.time) == (0..<20).map { Double($0 * 10) })
        // Açılmayan ders kısa kalır.
        #expect(expanded.last?.hits.count == LibrarySearch.maxPerLesson)
        #expect(expanded.last?.total == 8)
    }

    @Test func expandedLessonIsStillCapped() {
        let huge = searchDoc("Dev", (0..<(LibrarySearch.maxExpanded + 10)).map { (Double($0), "osmoz \($0)") })
        let result = LibrarySearch.search("osmoz", in: [huge], expanded: [huge.id]).first
        #expect(result?.hits.count == LibrarySearch.maxExpanded)
        #expect(result?.total == LibrarySearch.maxExpanded + 10)
    }

    @Test func highlightOffsetsMarkEveryFoldedMatch() {
        #expect(LibrarySearch.highlightOffsets(snippet: "Osmoz, suyun geçişidir", tokens: ["osmoz"]) == [0..<5])
        #expect(LibrarySearch.highlightOffsets(snippet: "IŞIK ve ışık", tokens: LibrarySearch.tokens("isik")) == [0..<4, 8..<12])
        #expect(LibrarySearch.highlightOffsets(snippet: "Hücre zarı", tokens: ["osmoz"]).isEmpty)
        #expect(LibrarySearch.highlightOffsets(snippet: "", tokens: ["osmoz"]).isEmpty)
        #expect(LibrarySearch.highlightOffsets(snippet: "osmoz", tokens: []).isEmpty)
        // Örtüşen ve yinelenen belirteçler tek aralıkta birleşir.
        #expect(LibrarySearch.highlightOffsets(snippet: "mitokondri", tokens: ["mito", "tokon", "mito"]) == [0..<7])
        #expect(LibrarySearch.highlightOffsets(snippet: "…zar ve zar…", tokens: ["zar"]) == [1..<4, 8..<11])
    }

    // MARK: - Dalga 2 · Zamanlı not: zaman girdisi

    @Test func timedNoteInputParsesAndClampsToDuration() {
        #expect(TimedNoteInput.time(from: "12:34", duration: 3600) == 754)
        #expect(TimedNoteInput.time(from: "90", duration: 60) == 60)
        #expect(TimedNoteInput.time(from: "1.30", duration: 0) == 90)
        #expect(TimedNoteInput.time(from: "1:02:05", duration: 0) == 3725)
        #expect(TimedNoteInput.time(from: "5:75", duration: 600) == nil)
        #expect(TimedNoteInput.time(from: "abc", duration: 0) == nil)
        #expect(TimedNoteInput.time(from: "12x", duration: 600) == nil)
        #expect(TimedNoteInput.time(from: "", duration: 600) == nil)
        // Süre bilinmiyorsa (0, NaN) kırpılmaz.
        #expect(TimedNoteInput.time(from: "2:00:00", duration: .nan) == 7200)
    }

    // MARK: - Zamanlı not: düzenlemeye geçilirken yarım kalan yeni not

    @Test func timedNoteStashGivesBackHalfWrittenNoteWithItsPhoto() {
        let photo = Data([0xFF, 0xD8, 0xFF])
        let preview = UIImage()
        var stash = TimedNoteStash()
        stash.keep(text: "Yarım not", photoData: photo, photoPreview: preview, whileEditing: false)
        // Bir nottan ötekine geçilirken düzenleyicide duran, düzenlenen notun içeriğidir: saklananı ezmez.
        stash.keep(text: "Düzenlenen notun metni", photoData: nil, photoPreview: nil, whileEditing: true)
        let back = stash.take()
        #expect(back.text == "Yarım not")
        #expect(back.photoData == photo)
        #expect(back.photoPreview === preview)

        // Geri verilen taslak bir sonraki düzenlemeden sonra yeniden gelmez.
        let empty = stash.take()
        #expect(empty.text.isEmpty)
        #expect(empty.photoData == nil)
        #expect(empty.photoPreview == nil)

        // Yalnız fotoğraftan oluşan taslak da saklanır.
        stash.keep(text: "", photoData: photo, photoPreview: preview, whileEditing: false)
        #expect(stash.take().photoData == photo)
    }

    // MARK: - Dalga 2 · Deneme geçmişi

    private func exam(_ correct: Int, _ wrong: Int, questions: Int = 20, at seconds: Double = 0) -> ExamRecord {
        ExamRecord(date: Date(timeIntervalSince1970: seconds), questions: questions, correct: correct, wrong: wrong,
                   blank: questions - correct - wrong, seconds: 600)
    }

    @Test func examHistoryKeepsNewestFirstAndCaps() {
        var list: [ExamRecord] = []
        for index in 0...ExamHistory.limit { list = ExamHistory.appending(exam(index % 10, 0, at: Double(index)), to: list) }
        #expect(list.count == ExamHistory.limit)
        #expect(list.first?.date == Date(timeIntervalSince1970: Double(ExamHistory.limit)))
        #expect(list.last?.date == Date(timeIntervalSince1970: 1))
        // Aynı kayıt iki kez eklenmez.
        let again = ExamHistory.appending(list[3], to: list)
        #expect(again.count == ExamHistory.limit)
        #expect(again.first?.id == list[3].id)
    }

    @Test func examDeltaComparesWithPreviousAttempt() {
        #expect(exam(12, 4).net == 11)
        #expect(ExamHistory.deltaText(latest: exam(12, 4), previous: exam(10, 3)) == "+1,75 net")
        #expect(ExamHistory.deltaText(latest: exam(10, 2), previous: exam(10, 0)) == "−0,5 net")
        #expect(ExamHistory.deltaText(latest: exam(10, 2), previous: exam(10, 2)) == "aynı net")
        #expect(ExamHistory.deltaText(latest: exam(10, 2), previous: nil) == nil)
        #expect(ExamHistory.delta(latest: exam(10, 2), previous: nil) == nil)
        #expect(ExamHistory.delta(latest: exam(12, 4), previous: exam(10, 3)) == 1.75)
        // Soru sayısı farklıysa net/soru yüzdesinin puan farkı.
        #expect(ExamHistory.deltaText(latest: exam(10, 0, questions: 20), previous: exam(4, 0, questions: 10)) == "net oranı +10 puan")
        #expect(ExamHistory.deltaText(latest: exam(4, 0, questions: 10), previous: exam(10, 0, questions: 20)) == "net oranı −10 puan")
        #expect(ExamHistory.deltaText(latest: exam(5, 0, questions: 10), previous: exam(10, 0, questions: 20)) == "aynı net oranı")
        #expect(ExamHistory.title(exam(10, 2, questions: 15)) == "Net 9,5 · 15 soru")
        #expect(ExamHistory.detail(exam(12, 3, questions: 15)) == "12 D · 3 Y · 0 B")
    }

    @Test func examHistoryRoundTripsThroughLessonFolder() throws {
        #expect(ExamHistory.decode(Data("bozuk".utf8)).isEmpty)
        #expect(ExamHistory.decode(Data()).isEmpty)
        let list = [exam(12, 4, at: 200), exam(10, 3, at: 100)]
        let encoded = try JSONEncoder().encode(list)
        #expect(ExamHistory.decode(encoded) == list)

        let lesson = UUID()
        defer { VideoFiles.remove(lesson: lesson) }
        #expect(ExamHistory.load(lesson: lesson).isEmpty)
        ExamHistory.save(list, lesson: lesson)
        #expect(ExamHistory.load(lesson: lesson) == list)
        #expect(ExamHistory.fileURL(lesson: lesson).lastPathComponent == ExamHistory.fileName)
        try Data("{bozuk".utf8).write(to: ExamHistory.fileURL(lesson: lesson))
        #expect(ExamHistory.load(lesson: lesson).isEmpty)
    }

    // MARK: - Dalga 2 · Kuyruk öğesi ve kaybolan işin yeniden gönderilmesi

    @Test func queuedImportShowsTitleOrShortLink() {
        #expect(QueuedImport(url: "https://youtu.be/AAAAAAAAAAA", title: "Hücre zarı").displayTitle == "Hücre zarı")
        #expect(QueuedImport(url: "https://youtu.be/AAAAAAAAAAA", title: "").displayTitle == ImportLinks.shortName("https://youtu.be/AAAAAAAAAAA"))
    }

    @Test func resendFailureForgetsJobOnlyWhenPermanent() {
        #expect(LessonImporter.resendFailureIsPermanent(apiError(400, "invalid_request")))
        #expect(LessonImporter.resendFailureIsPermanent(apiError(404, "not_found")))
        #expect(LessonImporter.resendFailureIsPermanent(apiError(413, "too_large")))
        #expect(!LessonImporter.resendFailureIsPermanent(APIError.network(URLError(.notConnectedToInternet))))
        #expect(!LessonImporter.resendFailureIsPermanent(URLError(.timedOut)))
        #expect(!LessonImporter.resendFailureIsPermanent(apiError(429, "daily_limit")))
        #expect(!LessonImporter.resendFailureIsPermanent(apiError(503, "http_503")))
        #expect(!LessonImporter.resendFailureIsPermanent(apiError(401, "unauthorized")))
        #expect(!LessonImporter.resendFailureIsPermanent(CancellationError()))
    }
}
