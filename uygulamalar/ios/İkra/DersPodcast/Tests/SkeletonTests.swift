import Foundation
import Testing
import SwiftData
@testable import Ikra

/// Adım 0 iskeleti: eski verinin çözülmesi, bağlantılar, dinleme modu, zayıf kart, bağlam ve olay yolu.
@MainActor
struct SkeletonTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Eski JSON

    @Test func legacySettingsGetDefaults() throws {
        let s = try decode(PodcastSettings.self, #"{"speechProvider":"chirp","durationMin":15,"hostA":{"name":"Ayşe","voice":"Kore"}}"#)
        #expect(s.durationMin == 15)
        #expect(s.hostA.name == "Ayşe")
        #expect(s.directives == [])
        #expect(s.thinkPauses == true)
        #expect(s.mixedFormat == false)
        #expect(s.recallFirst == false)
        #expect(s.series == nil)
        #expect(s.guest == nil)
        #expect(s.soundIdentity == nil)
        #expect(s.derivation == nil)
    }

    @Test func corruptNewSettingsFieldsFallBack() throws {
        let s = try decode(PodcastSettings.self, #"{"speechProvider":"apple","directives":"bozuk","thinkPauses":"x","series":{"id":1},"guest":5}"#)
        #expect(s.speechProvider == "apple")
        #expect(s.directives == [])
        #expect(s.thinkPauses == true)
        #expect(s.series == nil)
        #expect(s.guest == nil)
    }

    /// Gemini seslendirmesi kaldırıldı: eski kayıtlardaki seçim sunucu seslerine (XTTS) çevrilir; motor listesinde Gemini yoktur.
    @Test func removedGeminiEngineMigratesToServerVoices() throws {
        let old = try JSONDecoder().decode(PodcastSettings.self, from: Data(#"{"speechProvider":"gemini"}"#.utf8))
        #expect(old.speechProvider == "xtts" && old.engine == .xtts)
        #expect(PodcastSettings(speechProvider: "gemini").engine == .xtts)
        #expect(try JSONDecoder().decode(PodcastSettings.self, from: Data(#"{"speechProvider":"chirp"}"#.utf8)).engine == .chirp)
        #expect(SpeechEngine(rawValue: "gemini") == nil && !SpeechEngine.allCases.map(\.rawValue).contains("gemini"))
        #expect(!SpeechEngine.allCases.contains { $0.title.contains("Gemini") || $0.detail.contains("Gemini") })
    }

    @Test func newSettingsRoundTrip() throws {
        var s = PodcastSettings(speechProvider: "chirp")
        s.series = SeriesContext(id: UUID(), name: "Biyoloji", index: 2, total: 5, previousTitles: ["Hücre"], previousKeyPoints: ["Zar"])
        s.directives = ["İki dilli anlat"]
        s.mixedFormat = true
        s.guest = Host(name: "Doktor Zeynep", voice: "Charon")
        s.thinkPauses = false
        s.recallFirst = true
        s.soundIdentity = "odak"
        s.derivation = Derivation(kind: "recap", parentEpisodeID: UUID(), sourceLessonID: nil, sourceVideoTime: 12, courseID: UUID())
        let back = try JSONDecoder().decode(PodcastSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }

    @Test func legacyScriptDecodesAndBadQualityIsDropped() throws {
        let base = #""title":"Hücre","summary":"Özet","keyPoints":["a"],"sourceNotes":"not","chapters":[{"title":"Giriş","scenes":[{"turns":[{"speaker":"A","text":"Merhaba","style":"neşeli"},{"speaker":"C","text":"Ben konuğum","style":"","think":4}]}]}]"#
        let old = try decode(PodcastScript.self, "{\(base)}")
        #expect(old.quality == nil)
        #expect(old.chapters[0].style == nil)
        #expect(old.chapters[0].sourcePages == nil)
        #expect(old.chapters[0].scenes[0].turns[0].think == nil)
        #expect(old.chapters[0].scenes[0].turns[1].speaker == .c)
        #expect(old.chapters[0].scenes[0].turns[1].think == 4)

        let broken = try decode(PodcastScript.self, #"{\#(base),"quality":{"targetMinutes":"on"}}"#)
        #expect(broken.quality == nil)
        #expect(broken.chapters.count == 1)

        let good = try decode(PodcastScript.self, #"{\#(base),"quality":{"targetMinutes":10,"estimatedMinutes":9.5,"words":1300,"findings":[{"id":"x","label":"Tekrar","count":2}],"weakScenes":[{"scene":0,"reasons":["kısa"]}],"chapterErrors":[]}}"#)
        #expect(good.quality?.words == 1300)
        #expect(good.quality?.weakScenes.first?.scene == 0)
        #expect(good.quality?.findings.first?.examples == nil)
    }

    @Test func legacyValueTypesDecode() throws {
        let timeline = try decode(Timeline.self, #"{"chapters":[{"id":0,"title":"Giriş","start":0}],"turns":[{"id":0,"chapterIndex":0,"speaker":"B","text":"Selam","start":0,"end":1.5}],"duration":1.5}"#)
        #expect(timeline.thinkPauses == nil)
        #expect(timeline.sceneStarts == nil)
        #expect(timeline.turns.count == 1)

        let quiz = try decode(QuizItem.self, #"{"question":"Soru?","options":["a","b"],"answerIndex":1,"explanation":"Çünkü"}"#)
        #expect(quiz.kind == nil && quiz.chapterIndex == nil && quiz.turnIndex == nil)
        #expect(quiz.difficulty == nil && quiz.answerText == nil && quiz.verified == nil)

        let issue = try decode(ScriptIssue.self, #"{"index":3,"severity":"hatali","reason":"Yanlış tarih"}"#)
        #expect(issue.index == 3)
        #expect(issue.quote == nil && issue.page == nil && issue.fixedAt == nil)
    }

    // MARK: - AppLink

    @Test func appLinkRoundTrips() throws {
        let id = UUID()
        let links: [AppLink] = [
            .episode(id, time: 125, play: true),
            .episode(id, time: nil, play: false),
            .generation(id),
            .route("review"),
        ]
        for link in links {
            #expect(link.url.scheme == "kocum")
            #expect(AppLink(url: link.url) == link)
        }
        #expect(AppLink.episode(id, time: 12.9, play: true).url.absoluteString == "kocum://episode/\(id.uuidString)?t=12&play=1")
        #expect(AppLink(url: AppLink.episode(id, time: -5, play: false).url) == .episode(id, time: 0, play: false))
        #expect(AppLink(url: URL(string: "https://episode/\(id.uuidString)")!) == nil)
        #expect(AppLink(url: URL(string: "kocum://episode/bozuk")!) == nil)
        #expect(AppLink(url: URL(string: "kocum://route/")!) == nil)
        #expect(AppLink(url: URL(string: "kocum://bilinmeyen/x")!) == nil)
    }

    // MARK: - Dinleme modu

    @Test func listeningModePolicyAndLegacyKey() {
        let defaults = UserDefaults.standard
        let oldMode = defaults.object(forKey: ListeningMode.key)
        let oldInline = defaults.object(forKey: "inlineQuiz")
        defer {
            defaults.set(oldMode, forKey: ListeningMode.key)
            defaults.set(oldInline, forKey: "inlineQuiz")
        }
        #expect(ListeningMode.rahat.policy.inlineQuestions == false)
        #expect(ListeningMode.rahat.policy.handsFree == false)
        #expect(ListeningMode.rahat.policy.probeStages == [3, 7, 21])
        #expect(ListeningMode.aktif.policy.playThinkPauses == true)
        #expect(ListeningMode.aktif.policy.preTest == false)
        #expect(ListeningMode.aktif.policy.probeStages == [1, 3, 7, 21])
        #expect(ListeningMode.sinav.policy.preTest == true)
        #expect(ListeningMode.sinav.policy.confidence == true)
        #expect(ListeningMode.sinav.policy.probeStages == [1, 2, 4, 7, 14])

        defaults.removeObject(forKey: ListeningMode.key)
        #expect(ListeningMode.current == .aktif)
        ListeningMode.current = .rahat
        #expect(ListeningMode.current == .rahat)
        #expect(defaults.bool(forKey: "inlineQuiz") == false)
        ListeningMode.current = .sinav
        #expect(defaults.string(forKey: ListeningMode.key) == "sinav")
        #expect(defaults.bool(forKey: "inlineQuiz") == true)
        #expect(ListeningMode.sinav.title == "Sınav")
    }

    // MARK: - Zayıf kart (#32)

    @Test func weakCardMeaning() throws {
        let container = try ModelContainer(for: ReviewCard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        func card(_ kind: ReviewCard.Kind) -> ReviewCard {
            let c = ReviewCard(episodeID: UUID(), episodeTitle: "Hücre", kind: kind, front: "Ön", back: "Arka", sourcePage: nil)
            context.insert(c)
            return c
        }
        #expect(card(.quiz).isWeak)
        #expect(!card(.flashcard).isWeak)

        let now = Date.now
        let lapsed = card(.flashcard)
        lapsed.review(.again, now: now)
        #expect(lapsed.lapses == 1)
        #expect(lapsed.lastLapseAt == now)
        #expect(lapsed.isWeak)

        // Eski kayıt: lapse var, tarih yok → eski kural.
        let legacy = card(.flashcard)
        legacy.lapses = 1
        #expect(legacy.isWeak)

        // Son lapse 30 günden eski → zayıf değil.
        let stale = card(.quiz)
        stale.lapses = 2
        stale.lastLapseAt = now.addingTimeInterval(-31 * 86_400)
        #expect(!stale.isWeak)

        // İki başarılı tekrar → zayıf değil.
        let recovered = card(.quiz)
        recovered.review(.again, now: now)
        recovered.review(.good, now: now)
        recovered.review(.good, now: now)
        #expect(recovered.repetitions >= 2)
        #expect(!recovered.isWeak)

        // "İyi" notu lapse tarihini değiştirmez.
        let good = card(.flashcard)
        good.review(.good, now: now)
        #expect(good.lastLapseAt == nil)
    }

    // MARK: - Ayarlar ve bölüm bağlamı

    @Test func reusableSettingsAndDisplayNames() {
        var s = PodcastSettings(speechProvider: "chirp")
        s.series = SeriesContext(id: UUID(), name: "Seri", index: 1, total: 3, previousTitles: [], previousKeyPoints: [])
        s.directives = ["Karşılaştır"]
        s.recallFirst = true
        s.derivation = Derivation(kind: "gap", parentEpisodeID: UUID())
        s.thinkPauses = false
        s.mixedFormat = true
        s.soundIdentity = "sicak"
        let r = s.reusable
        #expect(r.series == nil)
        #expect(r.directives.isEmpty)
        #expect(r.recallFirst == false)
        #expect(r.derivation == nil)
        #expect(r.thinkPauses == false)
        #expect(r.mixedFormat == true)
        #expect(r.soundIdentity == "sicak")
        #expect(r.speechProvider == "chirp")

        #expect(s.displayName(for: .a) == s.hostA.name)
        #expect(s.displayName(for: .b) == s.hostB.name)
        #expect(s.displayName(for: .c) == "Konuk")
        s.guest = Host(name: "Doç. Dr. İpek", voice: "Charon")
        #expect(s.displayName(for: .c) == "Doç. Dr. İpek")
        #expect(SpeechEngine.chirp.supportsGuest && !SpeechEngine.xtts.supportsGuest)
        #expect(!SpeechEngine.apple.supportsGuest && !SpeechEngine.edge.supportsGuest)
    }

    @Test func episodeAppliesContext() throws {
        let container = try ModelContainer(for: Episode.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let script = PodcastScript(title: "Hücre", summary: "Zar", keyPoints: [], chapters: [], sourceNotes: "")
        let id = UUID()
        let parent = UUID()
        let course = UUID()
        let seriesID = UUID()
        var settings = PodcastSettings(speechProvider: "apple")
        settings.series = SeriesContext(id: seriesID, name: "Biyoloji serisi", index: 3, total: 4, previousTitles: [], previousKeyPoints: [])
        settings.derivation = Derivation(kind: "video", parentEpisodeID: parent, sourceLessonID: UUID(), sourceVideoTime: 750, courseID: course)
        let episode = Episode(id: id, script: script, settings: settings, sourceNames: [], jobToken: "t")
        context.insert(episode)
        #expect(episode.id == id)
        #expect(episode.needsApproval == false)
        #expect(episode.audioRevision == 0)
        episode.applyContext(from: settings)
        #expect(episode.seriesID == seriesID)
        #expect(episode.seriesTitle == "Biyoloji serisi")
        #expect(episode.seriesIndex == 3)
        #expect(episode.derivedKind == "video")
        #expect(episode.parentEpisodeID == parent)
        #expect(episode.sourceVideoTime == 750)
        #expect(episode.courseID == course)

        // courseID'siz türev, var olan bağı silmez.
        var other = PodcastSettings()
        other.derivation = Derivation(kind: "recap")
        episode.applyContext(from: other)
        #expect(episode.courseID == course)
        #expect(episode.derivedKind == "recap")

        // Hesaplanan JSON alanları.
        #expect(episode.audioIssues.isEmpty && episode.audioIssuesData == nil)
        episode.audioIssues = [AudioIssue(scene: 2, reasons: ["kesik"])]
        episode.topics = [TopicTag(subject: "Biyoloji", unit: "Hücre", topic: "Zar", chapterIndex: 0)]
        episode.generationStats = GenerationStats(engine: "chirp", scriptModel: nil, startedAt: .now, scriptSeconds: 30, voiceSeconds: nil,
                                                  mixSeconds: nil, characters: 1000, scenes: 4, retakes: 0, estimatedCostUSD: 0.03)
        try context.save()
        #expect(episode.audioIssues.first?.scene == 2)
        #expect(episode.topics.first?.topic == "Zar")
        #expect(episode.generationStats?.scenes == 4)
        episode.audioIssues = []
        #expect(episode.audioIssuesData == nil)
        #expect(Episode(script: script, settings: settings, sourceNames: [], jobToken: "").id != id)
    }

    // MARK: - Olay yolu

    @Test func eventsAreDeliveredSynchronously() {
        final class Box { var infos: [PodcastEventInfo] = [] }
        let box = Box()
        let token = PodcastEvent.observe(PodcastEvent.chapterFinished) { box.infos.append($0) }
        defer { NotificationCenter.default.removeObserver(token) }
        let id = UUID()
        PodcastEvent.post(PodcastEvent.chapterFinished, episodeID: id, chapter: 2)
        // Yayın döndüğünde dinleyici çoktan çalışmış olmalı.
        #expect(box.infos.count == 1)
        #expect(box.infos.first?.episodeID == id)
        #expect(box.infos.first?.chapter == 2)
        #expect(box.infos.first?.count == nil)
        #expect(box.infos.first?.sleepTimer == false)
        PodcastEvent.post(PodcastEvent.episodeFinished, episodeID: id, sleepTimer: true)
        #expect(box.infos.count == 1)   // başka ad bu dinleyiciye gelmez
    }

    @Test func storeSnapshotCopiesOncePerTag() throws {
        // Gerçek depoya dokunmadan yalnız "dosya yoksa atla" yolunu dener: var olmayan etiket, depo yoksa klasör oluşturmaz.
        let fm = FileManager.default
        let base = URL.applicationSupportDirectory
        let tag = "test-\(UUID().uuidString)"
        let target = base.appending(path: "StoreBackup-\(tag)", directoryHint: .isDirectory)
        StoreSnapshot.takeOnce(tag: tag)
        let hasStore = fm.fileExists(atPath: base.appending(path: "default.store").path)
        #expect(fm.fileExists(atPath: target.path) == hasStore)
        if hasStore {
            #expect(fm.fileExists(atPath: target.appending(path: "default.store").path))
            try? fm.removeItem(at: target)
        }
    }
}
