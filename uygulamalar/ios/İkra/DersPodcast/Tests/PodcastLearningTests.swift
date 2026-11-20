import Foundation
import SwiftData
import Testing
@testable import Ikra

/// P6: öğrenme çekirdeği (#23–#29, #31–#35).
@MainActor
struct PodcastLearningTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: Schema(AppDataStore.modelTypes), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func q(_ text: String, chapter: Int?, kind: String? = nil, difficulty: Int? = nil, options: [String] = ["a", "b", "c", "d"],
                   answer: Int = 0, turn: Int? = nil, verified: Bool? = nil) -> QuizItem {
        QuizItem(question: text, options: options, answerIndex: answer, explanation: "", sourcePage: nil, kind: kind,
                 chapterIndex: chapter, turnIndex: turn, difficulty: difficulty, answerText: nil, verified: verified)
    }

    private func episode(chapters: Int = 3, in context: ModelContext) -> Episode {
        let t = { (text: String, think: Double?) in ScriptTurn(speaker: .a, text: text, style: "", sourcePage: nil, think: think) }
        let script = PodcastScript(title: "Hücre", summary: "Özet", keyPoints: ["Zar", "Çekirdek", "Mitokondri", "Ribozom"],
                                   chapters: (0..<chapters).map { ScriptChapter(title: "Konu \($0)", scenes: [ScriptScene(turns: [t("Soru \($0)?", 6), t("Cevap \($0)", nil)])]) },
                                   sourceNotes: "Notlar")
        let episode = Episode(script: script, settings: PodcastSettings(), sourceNames: [], jobToken: "")
        episode.timeline = Timeline(chapters: (0..<chapters).map { TimedChapter(id: $0, title: "Konu \($0)", start: Double($0) * 100) },
                                    turns: (0..<chapters).flatMap { c in
                                        [TimedTurn(id: c * 2, chapterIndex: c, speaker: .a, text: "Soru \(c)?", sourcePage: nil, start: Double(c) * 100, end: Double(c) * 100 + 10),
                                         TimedTurn(id: c * 2 + 1, chapterIndex: c, speaker: .b, text: "Cevap \(c)", sourcePage: nil, start: Double(c) * 100 + 20, end: Double(c) * 100 + 60)]
                                    }, duration: Double(chapters) * 100)
        context.insert(episode)
        return episode
    }

    // MARK: - #24 soru seçimi

    @Test func picksQuestionOfFinishedChapterNeverOpenEnded() {
        let quiz = [
            q("Genel", chapter: nil),
            q("Açık 1", chapter: 1, kind: "open", options: [], answer: -1),
            q("Zor 1", chapter: 1, difficulty: 3),
            q("Kolay 1", chapter: 1, difficulty: 1),
            q("Konu 2", chapter: 2),
            q("Doğrulanamadı 0", chapter: 0, verified: false),
        ]
        #expect(QuestionPicker.forChapter(quiz, chapter: 1)?.question == "Kolay 1")
        #expect(QuestionPicker.forChapter(quiz, chapter: 1, asked: ["Kolay 1"])?.question == "Zor 1")
        #expect(QuestionPicker.forChapter(quiz, chapter: 1, asked: ["Kolay 1", "Zor 1"]) == nil)   // açık uçlu seçilmez
        #expect(QuestionPicker.forChapter(quiz, chapter: 0) == nil)    // doğrulanmamış soru da sorulmaz
        #expect(QuestionPicker.forChapter(quiz, chapter: 5) == nil)    // eski "quiz[chapter % count]" yok
    }

    @Test func questionsAreEasyFirstAndSpreadAcrossChapters() {
        let quiz = [q("z", chapter: 0, difficulty: 3), q("o", chapter: 1, difficulty: 2), q("k", chapter: 0, difficulty: 1),
                    q("n", chapter: 1), q("t", chapter: 2, kind: "open", options: [], answer: -1)]
        #expect(QuestionPicker.easyFirst(quiz).map(\.question) == ["k", "o", "n", "t", "z"])
        let spread = QuestionPicker.spread(quiz, count: 2)
        #expect(Set(spread.compactMap(\.chapterIndex)) == [0, 1])
        #expect(!spread.contains { QuestionKind.isOpen($0) })
    }

    @Test func listenAnchorAndThinkTiming() throws {
        let store = try container(); let context = store.mainContext
        let ep = episode(in: context)
        let item = q("Soru", chapter: 1, turn: 3)
        #expect(ListenAnchor.time(for: item, timeline: ep.timeline) == 120)
        #expect(ListenAnchor.time(for: q("x", chapter: 2), timeline: ep.timeline) == 200)
        #expect(ListenAnchor.label(734) == "Bu kısmı dinle (12:14)")
        #expect(ThinkTiming.seconds(for: q("x", chapter: 0, turn: 0), script: ep.script) == 6)
        #expect(ThinkTiming.seconds(for: q("x", chapter: nil), script: ep.script) == ThinkTiming.fallback)
        #expect(ThinkTiming.clamp(20) == 8 && ThinkTiming.clamp(1) == 3)
    }

    // MARK: - Konu sonu hakemi

    @Test func chapterEndArbiterPriority() {
        let aktif = ListeningMode.aktif.policy
        func input(fg: Bool, detail: Bool = true, policy: ListeningPolicy = ListeningMode.aktif.policy, handsFree: Bool = true,
                   question: Bool = true, ready: Bool = true, learn2: Bool = true) -> ChapterEndArbiter.Input {
            .init(isForeground: fg, detailOpen: detail, policy: policy, handsFreeEnabled: handsFree, hasChapterQuestion: question,
                  interludeReady: ready, learn2: learn2, hasChapterTurns: true)
        }
        // 2) ön plan + detay açık + soru → dinlerken quiz (anlatarak hatırla değil)
        #expect(ChapterEndArbiter.decide(input(fg: true)) == .inlineQuiz)
        // 4) ön plan ama detay kapalı → anlatarak hatırla
        #expect(ChapterEndArbiter.decide(input(fg: true, detail: false)) == .recallPrompt)
        // ön plan + konuya bağlı soru yok → anlatarak hatırla
        #expect(ChapterEndArbiter.decide(input(fg: true, question: false)) == .recallPrompt)
        // 3) arka plan → eller serbest; hazır ses yoksa hiçbir şey (arka planda hatırlama ekranı açılmaz)
        #expect(ChapterEndArbiter.decide(input(fg: false)) == .handsFree)
        #expect(ChapterEndArbiter.decide(input(fg: false, ready: false)) == .none)
        #expect(ChapterEndArbiter.decide(input(fg: false, handsFree: false)) == .none)
        // Rahat mod: konu sonunda hiçbir şey
        #expect(ChapterEndArbiter.decide(input(fg: true, policy: ListeningMode.rahat.policy)) == .none)
        #expect(ChapterEndArbiter.decide(input(fg: false, policy: ListeningMode.rahat.policy)) == .none)
        // learn2 yoksa anlatarak hatırla önerilmez
        #expect(ChapterEndArbiter.decide(input(fg: true, detail: false, learn2: false)) == .none)
        #expect(aktif.recallPrompt)
    }

    // MARK: - #27 günlük, eminlik, eğri

    @Test func calibrationByConfidence() {
        var samples: [RecallStats.Sample] = []
        for i in 0..<4 { samples.append(.init(isCorrect: i < 2, confidence: 2, daysSinceListen: 0)) }   // Eminim: %50
        for i in 0..<3 { samples.append(.init(isCorrect: i < 2, confidence: 0, daysSinceListen: 0)) }   // Tahmin: %67
        samples.append(.init(isCorrect: nil, confidence: 1, daysSinceListen: 0))                          // sonuçsuz sayılmaz
        let points = RecallStats.calibration(samples)
        #expect(points.map(\.label) == ["Tahmin", "Sanırım", "Eminim"])
        #expect(points[2].accuracy == 0.5 && points[2].count == 4)
        #expect(points[1].accuracy == nil && points[1].count == 0)
        #expect(RecallStats.calibrationNote(points)?.contains("aşırı güveniyorsun") == true)
        let good = RecallStats.calibration((0..<5).map { _ in .init(isCorrect: true, confidence: 2, daysSinceListen: 1) })
        #expect(RecallStats.calibrationNote(good) == "Eminliğin doğruluğunla uyumlu.")
    }

    @Test func retentionCurveBuckets() {
        let samples: [RecallStats.Sample] = [
            .init(isCorrect: true, confidence: nil, daysSinceListen: 0),
            .init(isCorrect: true, confidence: nil, daysSinceListen: 1),
            .init(isCorrect: true, confidence: nil, daysSinceListen: 7),
            .init(isCorrect: false, confidence: nil, daysSinceListen: 6),
            .init(isCorrect: false, confidence: nil, daysSinceListen: 30),
            .init(isCorrect: true, confidence: nil, daysSinceListen: nil),   // gün bilinmiyor: eğriye girmez
        ]
        let curve = RecallStats.retention(samples)
        #expect(curve.map(\.label) == ["1. gün", "7. gün", "30. gün"])
        #expect(curve[0].accuracy == 1 && curve[0].count == 2)
        #expect(curve[1].accuracy == 0.5 && curve[1].count == 2)
        #expect(curve[2].accuracy == 0 && curve[2].count == 1)
    }

    @Test func recallAttemptIsWrittenWithChoiceAndEvent() throws {
        let store = try container(); let context = store.mainContext
        let ep = episode(in: context)
        ep.lastPlayedAt = Calendar.current.date(byAdding: .day, value: -7, to: .now)
        ep.isFinished = true   // yoklaması olmayan eski bölüm: son dinleme kullanılır
        let item = q("Zar neyi sağlar?", chapter: 1, options: ["A", "B", "C", "D"], answer: 2)
        var received: PodcastEventInfo?
        let token = PodcastEvent.observe(PodcastEvent.recallRecorded) { received = $0 }
        defer { NotificationCenter.default.removeObserver(token) }
        let attempt = RecallLog.record(RecallLog.entry(item, source: "quiz",
                                                       outcome: QuestionOutcome(chosenIndex: 1, isCorrect: false, confidence: 2, seconds: 4)),
                                       episode: ep, context: context)
        let stored = try context.fetch(FetchDescriptor<RecallAttempt>())
        #expect(stored.count == 1)
        #expect(attempt.episodeTitle == "Hücre" && attempt.chapterIndex == 1)
        #expect(attempt.choices == ["A", "B", "C", "D"] && attempt.chosenIndex == 1 && attempt.correctIndex == 2)
        #expect(attempt.isCorrect == false && attempt.score == 0 && attempt.confidence == 2 && attempt.responseSeconds == 4)
        #expect(attempt.daysSinceListen == 7)
        #expect(received?.episodeID == ep.id)
    }

    // MARK: - #28 yoklama takvimi

    @Test func probeStagesCompressBeforeExam() {
        #expect(ProbeScheduler.stages([1, 3, 7, 21], daysToExam: nil) == [1, 3, 7, 21])
        #expect(ProbeScheduler.stages([1, 3, 7, 21], daysToExam: 30) == [1, 3, 7, 21])
        let seven = ProbeScheduler.stages([1, 3, 7, 21], daysToExam: 7)
        #expect(!seven.isEmpty && seven.allSatisfy { $0 >= 1 && $0 <= 7 })
        #expect(seven == seven.sorted() && Set(seven).count == seven.count)
        #expect(seven.last! < 7)    // sıkıştı
        #expect(ProbeScheduler.stages([1, 3, 7, 21], daysToExam: 1) == [1])
        #expect(ProbeScheduler.stages([1, 3, 7, 21], daysToExam: 0) == [])
    }

    // MARK: - #32 bellek modeli

    @Test func probesScheduleOnceAndLowScoreAddsRelisten() throws {
        let store = try container(); let context = store.mainContext
        let ep = episode(in: context)
        ep.statusRaw = EpisodeStatus.ready.rawValue
        let now = Date.now
        ProbeAdvisor.scheduleProbes(for: ep, context: context, now: now, stages: [1, 3, 7, 21], plan: nil)
        ProbeAdvisor.scheduleProbes(for: ep, context: context, now: now, stages: [1, 3, 7, 21], plan: nil)   // yinelenmez
        var probes = try context.fetch(FetchDescriptor<EpisodeProbe>()).sorted { $0.stage < $1.stage }
        #expect(probes.map(\.stage) == [1, 3, 7, 21])
        let dayOne = Calendar.current.date(byAdding: .day, value: 1, to: now)!

        ProbeAdvisor.finish(episodeID: ep.id, score: 0.4, context: context, now: dayOne)
        probes = try context.fetch(FetchDescriptor<EpisodeProbe>())
        #expect(probes.first { $0.stage == 1 && $0.kindRaw == "probe" }?.completedAt != nil)
        #expect(probes.contains { $0.kindRaw == "relisten" && $0.completedAt == nil })
        ProbeAdvisor.completeRelisten(episodeID: ep.id, context: context, now: dayOne)

        // Sınava 5 gün: aralıklar sıkışır.
        let other = episode(in: context)
        let plan = StudyPlan(examName: "TYT", examDate: Calendar.current.date(byAdding: .day, value: 5, to: now)!, dailyMinutes: 30)
        ProbeAdvisor.scheduleProbes(for: other, context: context, now: now, stages: [1, 3, 7, 21], plan: plan)
        let otherID: UUID? = other.id
        let stages = try context.fetch(FetchDescriptor<EpisodeProbe>(predicate: #Predicate { $0.episodeID == otherID })).map(\.stage)
        #expect(!stages.isEmpty && stages.allSatisfy { $0 <= 5 })
    }

    @Test func weakMeaningForgivesOldOrRecoveredLapses() throws {
        let store = try container(); let context = store.mainContext
        let card = ReviewCard(episodeID: UUID(), episodeTitle: "x", kind: .flashcard, front: "a", back: "b", sourcePage: nil)
        context.insert(card)
        card.reviewWithMemory(.again)
        #expect(card.isWeak)
        card.reviewWithMemory(.good)
        card.reviewWithMemory(.good)
        #expect(!card.isWeak)   // iki başarılı tekrar
        let old = ReviewCard(episodeID: UUID(), episodeTitle: "x", kind: .flashcard, front: "c", back: "d", sourcePage: nil)
        context.insert(old)
        old.lapses = 1
        old.lastLapseAt = Calendar.current.date(byAdding: .day, value: -40, to: .now)
        #expect(!old.isWeak)    // 30 günden eski lapse
    }

    @Test func legacyStabilityIsDerivedWithoutCalendarJump() throws {
        let store = try container(); let context = store.mainContext
        let card = ReviewCard(episodeID: UUID(), episodeTitle: "x", kind: .flashcard, front: "a", back: "b", sourcePage: nil)
        context.insert(card)
        // SM-2 ile 3 kez iyi: aralık 7–8 gün, stability alanı yok (eski kart).
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        card.review(.good, now: start)
        card.review(.good, now: start.addingTimeInterval(86_400))
        card.review(.good, now: start.addingTimeInterval(4 * 86_400))
        #expect(card.stability == 0)
        let derived = try #require(card.memoryState)
        // Türetilmiş kararlılıkla hedef aralık = mevcut SM-2 aralığı: sıradaki tarih değişmez.
        #expect(MemoryModel.interval(for: derived.stability) == card.intervalDays)
        #expect(derived.difficulty >= 1 && derived.difficulty <= 10)
        // Vadesinde %90 civarı hatırlama.
        let p = try #require(card.recallProbability(at: card.lastReviewed!.addingTimeInterval(Double(card.intervalDays) * 86_400)))
        #expect(abs(p - 0.9) < 0.01)
        // Yeni kart: durum yok, ilk tekrar başlangıç kararlılığıyla.
        let fresh = ReviewCard(episodeID: UUID(), episodeTitle: "x", kind: .flashcard, front: "n", back: "m", sourcePage: nil)
        context.insert(fresh)
        #expect(fresh.memoryState == nil && fresh.recallProbability() == nil)
        let due = card.due
        card.reviewWithMemory(.good, now: due)
        #expect(card.stability > derived.stability)       // vadesinde iyi → kararlılık artar
        #expect(card.intervalDays > Int(derived.stability))
        card.reviewWithMemory(.again, now: card.due)
        #expect(card.intervalDays == 1 && card.lastLapseAt != nil)
    }

    @Test func intervalsGrowAndAgainShrinks() {
        let first = MemoryModel.next(nil, rating: 3, elapsedDays: 0)
        let second = MemoryModel.next(first, rating: 3, elapsedDays: first.stability)
        let third = MemoryModel.next(second, rating: 3, elapsedDays: second.stability)
        #expect(second.stability > first.stability && third.stability > second.stability)
        let lapse = MemoryModel.next(third, rating: 1, elapsedDays: third.stability)
        #expect(lapse.stability < third.stability && lapse.difficulty > third.difficulty)
        let easy = MemoryModel.next(first, rating: 4, elapsedDays: first.stability)
        let hard = MemoryModel.next(first, rating: 2, elapsedDays: first.stability)
        #expect(easy.stability > second.stability && hard.stability < second.stability)
        #expect(MemoryModel.interval(for: 10) == 10)
    }

    @Test func interleavedSessionAvoidsSameEpisodeBackToBack() {
        let keys = ["A", "A", "A", "B", "B", "C"]
        let out = MemoryModel.interleave(keys) { $0 }
        #expect(out.count == keys.count && out.sorted() == keys.sorted())
        #expect(zip(out, out.dropFirst()).allSatisfy { $0 != $1 })
        #expect(MemoryModel.interleave(["A", "B", "B"]) { $0 } == ["B", "A", "B"])
        // Olanaksızsa en az tekrar: A A A B → A B A A
        #expect(MemoryModel.interleave(["A", "A", "A", "B"]) { $0 } == ["A", "B", "A", "A"])
        // "Bilemedim" yeniden ekleme: komşular başka bölümden.
        let session = ["A", "B", "A", "C", "B", "C"]
        let at = MemoryModel.reinsertIndex("A", in: session, after: 0)
        var copy = session
        copy.insert("A", at: at)
        #expect(at > 1)
        #expect(copy[at - 1] != "A" && (at + 1 >= copy.count || copy[at + 1] != "A"))
    }

    // MARK: - #31 tekrar bölümleri

    @Test func recapSettingsDropSeriesAndAskFirst() {
        var base = PodcastSettings()
        base.series = SeriesContext(id: UUID(), name: "Biyoloji", index: 2, total: 5, previousTitles: ["Hücre"], previousKeyPoints: ["Zar"])
        base.directives = ["İki dilli anlat"]
        base.derivation = Derivation(kind: "video", parentEpisodeID: UUID())
        let parent = UUID()
        let s = RecapGenerator.settings(from: base, kind: "gap", parent: parent)
        #expect(s.series == nil)
        #expect(s.recallFirst)
        #expect(s.directives == [RecapGenerator.recallFirstDirective])
        #expect(s.directives.allSatisfy { $0.count <= 800 })
        #expect(s.derivation?.kind == "gap" && s.derivation?.parentEpisodeID == parent)
        #expect((s.customInstructions ?? "").count <= PodcastSettings.maxCustomInstructions)
        let legacy = RecapGenerator.settings(from: base)
        #expect(legacy.derivation?.kind == "recap" && legacy.series == nil && legacy.recallFirst)
    }

    @Test func weeklyRecapCatchesMissedSundayWithMondayFirstCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "tr_TR")
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10) -> Date {
            calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
        }
        // 2026-10-04 pazar; 2026-10-05 pazartesi.
        let sunday = date(2026, 10, 4, 0)
        #expect(WeeklyRecap.lastSundayStart(before: date(2026, 10, 5), calendar: calendar) == sunday)
        #expect(WeeklyRecap.lastSundayStart(before: date(2026, 10, 4, 15), calendar: calendar) == sunday)
        // Cumartesi çalışmış, pazar kaçırılmış → pazartesi yakalanır.
        #expect(WeeklyRecap.isDue(now: date(2026, 10, 5), lastRunAt: date(2026, 10, 3), calendar: calendar))
        // Pazar sabah çalışmış → pazartesi yeniden çalışmaz.
        #expect(!WeeklyRecap.isDue(now: date(2026, 10, 5), lastRunAt: date(2026, 10, 4, 8), calendar: calendar))
        // Hiç çalışmamış → çalışır; çarşamba, pazartesi çalışmış → çalışmaz.
        #expect(WeeklyRecap.isDue(now: date(2026, 10, 7), lastRunAt: nil, calendar: calendar))
        #expect(!WeeklyRecap.isDue(now: date(2026, 10, 7), lastRunAt: date(2026, 10, 5), calendar: calendar))
        // Sonraki pazar yeniden sıra gelir.
        #expect(WeeklyRecap.isDue(now: date(2026, 10, 11, 9), lastRunAt: date(2026, 10, 5), calendar: calendar))
    }

    // MARK: - #25 ara ses durum makinesi

    @MainActor private final class FakeHost: InterludeHost {
        var allow = true
        var began = 0
        var ended: [Bool] = []
        var interludeRemoteHandler: ((RemoteCommand) -> Bool)?
        func beginInterlude() -> Bool { began += 1; return allow }
        func endInterlude(resume: Bool) { ended.append(resume) }
    }

    @MainActor private final class FakeAudio: InterludeAudio {
        var ok = true
        var playing = false
        var seeks: [Double] = []
        var finish: (() -> Void)?
        var suspendedAt: Date?
        var canResume = true
        var stops = 0
        var isIdle: Bool { !playing && suspendedAt == nil }
        func play(url: URL, onFinish: @escaping () -> Void) -> Bool { playing = ok; finish = onFinish; return ok }
        func seek(to time: Double) { seeks.append(time) }
        func stop() { playing = false; suspendedAt = nil; stops += 1 }
        func resume() -> Bool {
            guard canResume else { return false }
            suspendedAt = nil; playing = true
            return true
        }
        /// Kesinti: sistem sesi durdurdu.
        func interrupt(at date: Date = .now) { playing = false; suspendedAt = date }
    }

    private func prepared() -> PreparedInterlude {
        PreparedInterlude(episodeID: UUID(), chapter: 1, item: q("Soru", chapter: 1), url: URL(filePath: "/tmp/x.wav"),
                          answerStart: 12.5, duration: 20)
    }

    @Test func interludeStateMachine() {
        let host = FakeHost(), audio = FakeAudio()
        let session = InterludeSession(prepared: prepared(), host: host, audio: audio)
        var dontKnow = 0
        var finished: (Bool, Bool)?
        session.onDontKnow = { _ in dontKnow += 1 }
        session.onFinish = { _, dk, resume in finished = (dk, resume) }
        #expect(session.start())
        #expect(session.state == .playing && audio.playing && host.interludeRemoteHandler != nil)
        #expect(!session.start())   // ikinci kez başlamaz
        // Kulaklıkta "sonraki" = bilemedim: cevaba atlanır, bir kez sayılır.
        #expect(host.interludeRemoteHandler?(.nextChapter) == true)
        #expect(host.interludeRemoteHandler?(.skip(30)) == true)
        #expect(dontKnow == 1 && audio.seeks == [12.5])
        #expect(host.interludeRemoteHandler?(.previousChapter) == true && audio.seeks.last == 0)
        #expect(host.interludeRemoteHandler?(.seek(5)) == true)   // yutulur
        #expect(session.state == .playing)
        audio.finish?()
        #expect(session.state == .finished(dontKnow: true))
        #expect(host.ended == [true] && host.interludeRemoteHandler == nil && !audio.playing)
        #expect(finished?.0 == true && finished?.1 == true)
        audio.finish?()   // ikinci bitiş yok sayılır
        #expect(host.ended == [true])
    }

    @Test func interludePauseStopsAndRefusedHostFails() {
        let host = FakeHost(), audio = FakeAudio()
        let session = InterludeSession(prepared: prepared(), host: host, audio: audio)
        session.start()
        #expect(host.interludeRemoteHandler?(.toggle) == true)
        #expect(session.state == .finished(dontKnow: false) && host.ended == [false])
        #expect(session.handle(.nextChapter) == false)   // bittikten sonra tüketmez

        let refusing = FakeHost()
        refusing.allow = false
        let failed = InterludeSession(prepared: prepared(), host: refusing, audio: FakeAudio())
        #expect(!failed.start() && failed.state == .failed && refusing.ended.isEmpty)

        let noAudio = FakeAudio()
        noAudio.ok = false
        let host2 = FakeHost()
        let broken = InterludeSession(prepared: prepared(), host: host2, audio: noAudio)
        #expect(!broken.start() && host2.ended == [true] && host2.interludeRemoteHandler == nil)
    }

    @Test func interludePlayResumesAfterInterruptionOtherwiseEnds() {
        // Kesintiden sonra kilit ekranındaki "Oynat": ara ses sürer (yutulmaz, takılmaz).
        let host = FakeHost(), audio = FakeAudio()
        let session = InterludeSession(prepared: prepared(), host: host, audio: audio)
        session.start()
        audio.interrupt()
        #expect(session.watchdog())   // kesintide bekliyor: bekçi kapatmaz
        #expect(host.interludeRemoteHandler?(.play) == true)
        #expect(session.state == .playing && audio.playing && host.ended.isEmpty)
        // Çalarken "Oynat": ara ses biter, podcast sürer.
        #expect(host.interludeRemoteHandler?(.play) == true)
        #expect(session.state == .finished(dontKnow: false) && host.ended == [true] && !audio.playing)

        // Sürdürülemezse de takılmaz: biter ve podcast sürer.
        let host2 = FakeHost(), stuck = FakeAudio()
        stuck.canResume = false
        let s2 = InterludeSession(prepared: prepared(), host: host2, audio: stuck)
        s2.start()
        stuck.interrupt()
        #expect(host2.interludeRemoteHandler?(.play) == true)
        #expect(s2.state == .finished(dontKnow: false) && host2.ended == [true])
    }

    @Test func interludeAbandonAndWatchdog() {
        // Oynatıcı ara sesi kendisi bıraktı (yeni bölüm): ses susar, oynatıcıya dokunulmaz, oturum kapanır.
        let host = FakeHost(), audio = FakeAudio()
        let session = InterludeSession(prepared: prepared(), host: host, audio: audio)
        var finished: (Bool, Bool)?
        session.onFinish = { _, dk, resume in finished = (dk, resume) }
        session.start()
        session.abandon()
        #expect(session.state == .finished(dontKnow: false) && !audio.playing && audio.stops == 1)
        #expect(host.ended.isEmpty && finished?.1 == false)
        audio.finish?()   // geç gelen bitiş yok sayılır
        #expect(host.ended.isEmpty)

        // Bitiş haberi kayboldu: bekçi kapatır, podcast sürer.
        let host2 = FakeHost(), silent = FakeAudio()
        let s2 = InterludeSession(prepared: prepared(), host: host2, audio: silent)
        s2.start()
        #expect(s2.watchdog())          // çalıyor: sürer
        silent.playing = false
        #expect(!s2.watchdog())
        #expect(s2.state == .finished(dontKnow: false) && host2.ended == [true])

        // Kesinti hiç bitmedi ya da sistem "sürdür" demedi: sınırlı beklenir, sonra ara ses kapanır, podcast duraklamış kalır.
        let host3 = FakeHost(), waiting = FakeAudio()
        let s3 = InterludeSession(prepared: prepared(), host: host3, audio: waiting)
        s3.start()
        let t0 = Date.now
        waiting.interrupt(at: t0)
        #expect(s3.watchdog(now: t0.addingTimeInterval(60)))
        #expect(!s3.watchdog(now: t0.addingTimeInterval(InterludeSession.suspendLimit + 1)))
        #expect(s3.state == .finished(dontKnow: false) && host3.ended == [false])
    }

    @Test func interludeScriptReadsOptionsAndAnswer() {
        let item = QuizItem(question: "Zarın görevi?", options: ["Enerji", "Seçici geçirgenlik"], answerIndex: 1, explanation: "Zar seçer.")
        let script = InterludeBuilder.script(for: item, english: false)
        #expect(script.question.contains("A: Enerji.") && script.question.contains("B: Seçici geçirgenlik."))
        #expect(script.answer.hasPrefix("Cevap: B, Seçici geçirgenlik") && script.answer.contains("Zar seçer."))
        let tf = QuizItem(question: "Zar canlıdır.", options: ["Doğru", "Yanlış"], answerIndex: 0, explanation: "", kind: "truefalse")
        #expect(InterludeBuilder.script(for: tf, english: false).question.hasSuffix("Doğru mu, yanlış mı?"))
        let clip = PCMClip(samples: [0, 1000, 2000, 3000], sampleRate: 22_050)
        #expect(InterludeBuilder.resample(clip, to: 44_100).samples.count == 8)
    }

    // MARK: - #34 soru türleri ve istekler

    @Test func openQuestionsAndShuffle() throws {
        let open = try JSONDecoder().decode(QuizItem.self, from: Data(#"{"question":"Açıkla","options":[],"answerIndex":-1,"explanation":"e","kind":"open","answerText":"Cevap","chapterIndex":null,"verified":true}"#.utf8))
        #expect(QuestionKind.isOpen(open) && QuestionKind.expectedAnswer(open) == "Cevap")
        var rng = SeededRandom(seed: 7)
        let item = q("Q", chapter: 0, options: ["a", "b", "c", "d", "e"], answer: 3)
        for _ in 0..<10 {
            let s = OptionShuffle.shuffled(item, using: &rng)
            #expect(s.options.sorted() == item.options.sorted())
            #expect(s.options[s.answerIndex] == "d")
        }
        let tf = q("D/Y", chapter: 0, kind: "truefalse", options: ["Doğru", "Yanlış"], answer: 1)
        #expect(OptionShuffle.shuffled(tf, using: &rng) == tf)
        #expect(OptionShuffle.shuffled(open, using: &rng) == open)
    }

    @Test func unverifiedQuestionNeverEntersDeck() throws {
        let store = try container(); let context = store.mainContext
        let ep = episode(in: context)
        ReviewDeck.addWrong(q("Doğrulanmamış", chapter: 0, verified: false), episode: ep, context: context)
        ReviewDeck.addWrong(q("Tamam", chapter: 1, turn: 3), episode: ep, context: context, origin: "inline")
        let cards = try context.fetch(FetchDescriptor<ReviewCard>())
        #expect(cards.map(\.front) == ["Tamam"])
        #expect(cards[0].origin == "inline" && cards[0].chapterIndex == 1 && cards[0].episodeTime == 120)
    }

    @Test func studyV2RequestIsTrimmedAndEncoded() throws {
        let turns = (0..<900).map { TimedTurn(id: $0, chapterIndex: $0 / 300, speaker: .a, text: String(repeating: "ı", count: 700), sourcePage: nil, start: Double($0), end: Double($0) + 1) }
        let timeline = Timeline(chapters: [], turns: turns, duration: 900)
        let refs = try #require(LearnPayload.transcriptTurns(timeline))
        #expect(refs.count <= 600)
        #expect(refs.reduce(0) { $0 + $1.t.count } <= 20_000)
        #expect(refs.allSatisfy { $0.t.count <= 600 })
        #expect(refs.last?.i == 899)  // son tur (son konu) da girer
        let avoid = LearnPayload.avoid((0..<50).map { q(String(repeating: "x", count: 400) + "\($0)", chapter: nil) })
        #expect(avoid.count == 40 && avoid.allSatisfy { $0.count <= 300 })
        let request = StudyV2Request(title: "T", sourceNotes: "N", level: "lise", quizCount: 10, flashcardCount: 15, conceptCount: nil,
                                     transcript: nil, transcriptTurns: Array(refs.prefix(1)), kinds: LearnPayload.allKinds, avoid: [], verify: true)
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect((json["kinds"] as? [String]) == ["mcq", "osym", "premise", "truefalse", "open"])
        #expect(((json["transcriptTurns"] as? [[String: Any]])?.first?["i"] as? Int) == 0)
        #expect(json["conceptCount"] == nil)
        let check = RecallCheckRequest(title: "T", sourceNotes: "", chapterTitle: "K", chapterTurns: [ChapterTurnRef(i: 3, t: "x")],
                                       response: "r", followUp: RecallFollowUp(question: "q", answer: "a"))
        let cj = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(check)) as? [String: Any])
        #expect((cj["followUp"] as? [String: String]) == ["question": "q", "answer": "a"])
        let result = try JSONDecoder().decode(RecallCheckResult.self, from: Data(#"{"score":72,"covered":["a"],"missing":[{"point":"p","turnIndex":null}],"wrong":[{"claim":"c","correction":"d","turnIndex":4}],"followUp":null,"feedback":"iyi"}"#.utf8))
        #expect(result.missing[0].turnIndex == nil && result.wrong[0].turnIndex == 4)
    }

    @Test func chapterTurnsRespectServerTurnLimit() {
        // 3 turluk konu: 12k/3 = 4000 olurdu; sunucu tur başına 2400 kabul eder.
        let long = String(repeating: "ş", count: 5000)
        let turns = (0..<3).map { TimedTurn(id: $0, chapterIndex: 2, speaker: .a, text: long, sourcePage: nil, start: Double($0), end: Double($0) + 1) }
        let refs = LearnPayload.chapterTurns(Timeline(chapters: [], turns: turns, duration: 3), chapter: 2)
        #expect(refs.count == 3 && refs.allSatisfy { $0.t.utf16.count <= 2_400 })
        #expect(refs.reduce(0) { $0 + $1.t.utf16.count } <= 12_000)
        // UTF-16 ile ölçülür ve karakter bölünmez (emoji 2 birim).
        let emoji = String(repeating: "🧬", count: 2000)
        let one = LearnPayload.chapterTurns(Timeline(chapters: [], turns: [TimedTurn(id: 0, chapterIndex: 0, speaker: .a, text: emoji, sourcePage: nil, start: 0, end: 1)], duration: 1), chapter: 0)
        #expect(one.count == 1 && one[0].t.utf16.count == 2_400 && one[0].t.count == 1_200)
        #expect(LearnPayload.utf16Prefix("kısa", 10) == "kısa")
    }

    // MARK: - #26 bölüm sonu otomatik geçişi

    @Test func nextUpPeekFollowsQueueOrderIncludingAudio() {
        let ready = UUID(), notReady = UUID()
        let titles: (UUID) -> String? = { $0 == ready ? "Bölüm 2" : nil }
        #expect(NextUpPeek.title(queue: [.episode(notReady), .audio(fileName: "b.m4a", title: "Brifing"), .episode(ready)],
                                 readyEpisodeTitle: titles, seriesNext: { "Seri 3" }) == "Brifing")
        #expect(NextUpPeek.title(queue: [.episode(notReady), .episode(ready)], readyEpisodeTitle: titles, seriesNext: { nil }) == "Bölüm 2")
        #expect(NextUpPeek.title(queue: [.audio(fileName: "x", title: "")], readyEpisodeTitle: titles, seriesNext: { nil }) == "Sesli özet")
        #expect(NextUpPeek.title(queue: [], readyEpisodeTitle: titles, seriesNext: { "Seri 3" }) == "Seri 3")
        #expect(NextUpPeek.title(queue: [.episode(notReady)], readyEpisodeTitle: titles, seriesNext: { nil }) == nil)
    }

    @Test func nextUpHoldStartsNextOnCloseUnlessWaiting() {
        var hold = NextUpHold()
        #expect(hold.isEmpty)
        var started = hold.release()
        #expect(!started)                           // tutulmuyorsa kapanış bir şey başlatmaz
        hold.begin(title: "Bölüm 2")
        #expect(hold.title == "Bölüm 2" && hold.autoAdvance)
        started = hold.release()
        #expect(started && hold.isEmpty)            // "Kapat"/kaydırma: sıradaki başlar
        started = hold.release()
        #expect(!started)                           // bir kez
        hold.begin(title: "Bölüm 2")
        hold.wait()                                 // "Bekle"
        #expect(hold.title == "Bölüm 2" && !hold.autoAdvance)
        started = hold.release()
        #expect(!started && hold.isEmpty)
    }

    // MARK: - #27 eğri ölçüsü

    @Test func retentionExcludesPretestAndDiscrimination() {
        let samples: [RecallStats.Sample] = [
            .init(isCorrect: true, confidence: nil, daysSinceListen: 1, source: "probe"),
            .init(isCorrect: false, confidence: nil, daysSinceListen: 1, source: "pretest"),
            .init(isCorrect: false, confidence: nil, daysSinceListen: 1, source: "discriminate"),
        ]
        let curve = RecallStats.retention(samples)
        #expect(curve[0].accuracy == 1 && curve[0].count == 1)
    }

    @Test func daysSinceListenCountsFromFirstFinish() throws {
        let store = try container(); let context = store.mainContext
        let ep = episode(in: context)
        let now = Date.now
        let tenDaysAgo = try #require(Calendar.current.date(byAdding: .day, value: -10, to: now))
        #expect(RecallLog.daysSinceListen(episodeID: ep.id, context: context, now: now) == nil)   // hiç bitmedi
        ProbeAdvisor.scheduleProbes(for: ep, context: context, now: tenDaysAgo, stages: [1, 7], plan: nil)
        // Sonradan "O anı dinle" kesiti çalındı: son dinleme bugün, ama gün ilk bitişten sayılır.
        ep.lastPlayedAt = now
        ep.isFinished = false
        #expect(RecallLog.daysSinceListen(episodeID: ep.id, context: context, now: now) == 10)
        // Bütün yoklamalar bitip bölüm yeniden bitirilince de ilk bitiş korunur.
        for probe in try context.fetch(FetchDescriptor<EpisodeProbe>()) { probe.completedAt = now }
        ProbeAdvisor.scheduleProbes(for: ep, context: context, now: now, stages: [1], plan: nil)
        #expect(RecallLog.daysSinceListen(episodeID: ep.id, context: context, now: now) == 10)
    }

    // MARK: - #22, #33, #35

    @Test func weakSpotClipsAreRecentAndDeduped() {
        let a = UUID(), b = UUID()
        let now = Date.now
        let picked = WeakSpots.select([
            (now.addingTimeInterval(-100), WeakSpots.clip(a, 100, 600, reason: "1", key: "1")),
            (now, WeakSpots.clip(a, 110, 600, reason: "2", key: "2")),          // aynı yer, daha yeni
            (now.addingTimeInterval(-50), WeakSpots.clip(b, 590, 600, reason: "3", key: "3")),
        ], limit: 5)
        #expect(picked.map(\.questionKey) == ["2", "3"])
        #expect(picked[1].end == 600 && picked[1].start == 587)
    }

    @Test func weakSpotQuestionFallsBackToCard() throws {
        let store = try container(); let context = store.mainContext
        let ep = episode(in: context)
        let card = ReviewCard(episodeID: ep.id, episodeTitle: ep.title, kind: .flashcard, front: "Mitokondri?", back: "Enerji", sourcePage: nil)
        context.insert(card)
        let clip = WeakSpots.clip(ep.id, 50, 300, reason: "", key: "Mitokondri?")
        let item = try #require(WeakSpots.question(for: clip, context: context))
        #expect(QuestionKind.isOpen(item) && item.answerText == "Enerji")
    }

    @Test func labelCardNumberRoundTripsAndGuardsStaleCache() {
        let front = LabelCard.front(caption: "Göz — kesit", number: 3)
        #expect(front == "Şekil: Göz — kesit — 3 numaralı yapı nedir?")
        #expect(LabelCard.number(from: front) == 3)
        #expect(LabelCard.number(from: LabelCard.front(caption: "", number: 12)) == 12)
        #expect(LabelCard.number(from: "Zar neyi sağlar?") == nil)
        let labels = [FigureLabel(id: 0, text: "Kornea", box: .zero), FigureLabel(id: 2, text: "Retina", box: .zero)]
        #expect(LabelCard.target(in: labels, number: 3, answer: "retina")?.id == 2)
        #expect(LabelCard.target(in: labels, number: 3, answer: "İris") == nil)     // önbellek değişmiş: vurgulanmaz
        #expect(LabelCard.target(in: labels, number: nil, answer: "Retina") == nil)
    }

    @Test func chapterMasteryCombinesAttemptsAndCards() throws {
        let now = Date.now
        #expect(Mastery.combine(attempts: [], cards: []) == nil)
        #expect(Mastery.combine(attempts: [(now, 1), (now.addingTimeInterval(-10), 0)], cards: []).map { $0 > 0.5 } == true)   // yeni olan ağır basar
        #expect(Mastery.combine(attempts: [(now, 1)], cards: [0]) == 0.6)
        let store = try container(); let context = store.mainContext
        let ep = episode(in: context)
        #expect(Mastery.chapterScore(episodeID: ep.id, chapter: 1, context: context) == nil)
        RecallLog.record(RecallLog.Entry(source: "quiz", question: "x", isCorrect: true, chapterIndex: 1), episode: ep, context: context)
        RecallLog.record(RecallLog.Entry(source: "quiz", question: "y", isCorrect: false, chapterIndex: 2), episode: ep, context: context)
        #expect(Mastery.chapterScore(episodeID: ep.id, chapter: 1, context: context) == 1)
        #expect(Mastery.chapterScore(episodeID: ep.id, chapter: 2, context: context) == 0)
    }

    @Test func cardSuggestionsFromMarksAndLive() {
        let made = CardSuggestion.make(
            bookmarks: [.init(kind: "note", text: "düz not", note: "", time: 5, chapter: 0),
                        .init(kind: "confused", text: "Osmoz suyun geçişidir", note: "", time: 42, chapter: 1),
                        .init(kind: "flag", text: "x", note: "Osmoz nedir?", time: 50, chapter: 1)],
            live: [.init(question: "Difüzyon farkı?", answer: "Enerji gerekmez", time: 70, chapter: 1),
                   .init(question: "Osmoz nedir?", answer: "tekrar", time: 80, chapter: 1)],
            existingFronts: ["Difüzyon farkı?"])
        #expect(made.map(\.origin) == ["suggestion", "suggestion"])
        #expect(made[0].front.contains("Osmoz suyun geçişidir") && made[0].time == 42)
        #expect(made[1].front == "Osmoz nedir?")
    }

    // MARK: - İnceleme düzeltmeleri

    @Test func lockedScreenAdvancesOnlyAHeldEndCard() {
        let id = UUID()
        var hold = NextUpHold()
        #expect(NextUpHold.backgroundAdvance(sheet: .endCard(episodeID: id), hold: hold) == nil)   // sıradaki yok
        hold.begin(title: "Bölüm 2")
        #expect(NextUpHold.backgroundAdvance(sheet: .endCard(episodeID: id), hold: hold) == id)
        #expect(NextUpHold.backgroundAdvance(sheet: nil, hold: hold) == nil)
        #expect(NextUpHold.backgroundAdvance(sheet: .recall(episodeID: id, chapter: 0), hold: hold) == nil)
        hold.wait()                                                                                 // "Bekle"
        #expect(NextUpHold.backgroundAdvance(sheet: .endCard(episodeID: id), hold: hold) == nil)
    }

    @Test func endCardBannerPutsQuestionFirstAndShortensTitle() {
        #expect(LearningBanner.endCardText(title: "Hücre") == "Ne öğrendin? “Hücre” bitti.")
        let long = LearningBanner.endCardText(title: String(repeating: "Mitoz ve mayoz bölünme ", count: 4))
        #expect(long.hasPrefix("Ne öğrendin? “") && long.hasSuffix("…” bitti."))
        #expect(long.count <= "Ne öğrendin? “” bitti.".count + 40)
        #expect(LearningBanner.endCardText(title: "  ") == "Bölüm bitti. Ne öğrendin?")
    }

    @Test func weeklyRecapLegacyWeekKeyMigratesWithoutSecondRun() {
        var tr = Calendar(identifier: .gregorian)
        tr.locale = Locale(identifier: "tr_TR")
        tr.firstWeekday = 2
        tr.minimumDaysInFirstWeek = 4
        tr.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        func date(_ m: Int, _ d: Int, _ h: Int = 10, calendar: Calendar) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
        }
        // Eski sürüm pazar (4 Ekim) üretti; anahtar pazartesi başlayan haftanın (28 Eyl–4 Eki) anahtarı.
        let sundayKey = WeeklyRecap.weekKey(for: date(10, 4, calendar: tr), calendar: tr)
        for day in 5...10 {   // pazartesi–cumartesi: ikinci tekrar yok
            let now = date(10, day, calendar: tr)
            let migrated = WeeklyRecap.migratedLastRun(legacyKey: sundayKey, now: now, calendar: tr)
            #expect(migrated == date(10, 4, 0, calendar: tr))
            #expect(!WeeklyRecap.isDue(now: now, lastRunAt: migrated, calendar: tr))
        }
        // Sonraki pazar sıra gelir.
        let nextSunday = date(10, 11, calendar: tr)
        #expect(WeeklyRecap.isDue(now: nextSunday, lastRunAt: WeeklyRecap.migratedLastRun(legacyKey: sundayKey, now: nextSunday, calendar: tr), calendar: tr))
        // Eski sürüm bir önceki pazar (27 Eyl) üretmiş, 4 Ekim kaçmış → çarşamba yakalanır.
        let olderKey = WeeklyRecap.weekKey(for: date(9, 27, calendar: tr), calendar: tr)
        let wednesday = date(10, 7, calendar: tr)
        #expect(WeeklyRecap.isDue(now: wednesday, lastRunAt: WeeklyRecap.migratedLastRun(legacyKey: olderKey, now: wednesday, calendar: tr), calendar: tr))
        // Çözülemeyen anahtar: ihtiyatla son pazar (yeniden üretme yok).
        for bad in ["", "abc", "2026", "2026-99", "0-0"] {
            #expect(!WeeklyRecap.isDue(now: wednesday, lastRunAt: WeeklyRecap.migratedLastRun(legacyKey: bad, now: wednesday, calendar: tr), calendar: tr))
        }
        // Pazar başlayan takvim (haftanın ilk günü pazar): anahtarın pazarı haftanın başıdır.
        var us = Calendar(identifier: .gregorian)
        us.firstWeekday = 1
        us.timeZone = tr.timeZone
        let usKey = WeeklyRecap.weekKey(for: date(10, 4, calendar: us), calendar: us)
        let usMigrated = WeeklyRecap.migratedLastRun(legacyKey: usKey, now: date(10, 7, calendar: us), calendar: us)
        #expect(usMigrated == date(10, 4, 0, calendar: us))
        #expect(!WeeklyRecap.isDue(now: date(10, 7, calendar: us), lastRunAt: usMigrated, calendar: us))
    }

    @Test func thinkTimeIsFullFromFirstFrame() {
        #expect(QuestionCard.thinkRemaining(seconds: 5, elapsed: 0, skipped: false) == 5)
        #expect(QuestionCard.thinkRemaining(seconds: 3.2, elapsed: 0, skipped: false) == 4)
        #expect(QuestionCard.thinkRemaining(seconds: 5, elapsed: 4, skipped: false) == 1)
        #expect(QuestionCard.thinkRemaining(seconds: 5, elapsed: 9, skipped: false) == 0)
        #expect(QuestionCard.thinkRemaining(seconds: 5, elapsed: 0, skipped: true) == 0)   // "Şıkları şimdi göster"
        #expect(QuestionCard.thinkRemaining(seconds: 0, elapsed: 0, skipped: false) == 0)
    }

    @Test func onceValueNeverStrandsASecondWaiter() async {
        let value = OnceValue<String>()
        async let first = value.wait()
        async let second = value.wait()
        try? await Task.sleep(for: .milliseconds(50))
        value.resolve("son metin")
        value.resolve("geç gelen")                   // yok sayılır
        let r1 = await first
        let r2 = await second
        #expect(r1 == "son metin" && r2 == "son metin")
        #expect(await value.wait() == "son metin")   // çözüldükten sonra bekleyen hemen alır
        #expect(value.isResolved)
    }

    @Test func recorderBackgroundBanIsOptIn() async {
        let review = SpeechRecorder()                       // sesli kart tekrarı: kilitliyken de dinler
        let recall = SpeechRecorder(foregroundOnly: true)   // #29
        #expect(!review.foregroundOnly && recall.foregroundOnly)
        let said = await review.stop()                       // kayıt yokken durdurma zararsız
        #expect(said.isEmpty && !review.isStopping && !review.isRecording)
    }

    // MARK: - P5 ile uçtan uca (gerçek oynatıcı)

    /// Kapsayıcılar test boyunca yaşar (ARC erken bırakırsa bağlam SwiftData'da çöker).
    private static var liveContainers: [ModelContainer] = []

    private func playable(_ title: String, in context: ModelContext, series: UUID? = nil, index: Int = 0) throws -> Episode {
        let script = PodcastScript(title: title, summary: "", keyPoints: [], chapters: [], sourceNotes: "Notlar")
        let e = Episode(script: script, settings: PodcastSettings(), sourceNames: [], jobToken: "t")
        e.status = .ready
        e.audioFileName = "audio.wav"
        e.duration = 6
        e.seriesID = series
        e.seriesIndex = index
        e.timeline = Timeline(chapters: [TimedChapter(id: 0, title: "Konu 1", start: 0), TimedChapter(id: 1, title: "Konu 2", start: 3)],
                              turns: [TimedTurn(id: 0, chapterIndex: 0, speaker: .a, text: "Bir", sourcePage: nil, start: 0, end: 3),
                                      TimedTurn(id: 1, chapterIndex: 1, speaker: .b, text: "İki", sourcePage: nil, start: 3, end: 6)],
                              duration: 6)
        context.insert(e)
        try WAV.encode(PCMClip.silence(seconds: 6, sampleRate: 8000)).write(to: try #require(e.audioURL))
        return e
    }

    private func livePlayer() throws -> (PlayerController, ModelContext) {
        let store = try container()
        Self.liveContainers.append(store)
        let player = PlayerController()
        player.queueStore = UserDefaults(suiteName: "p6.player")!   // uygulamanın kalıcı kuyruğuna dokunma
        player.setQueue([])
        return (player, store.mainContext)
    }

    @Test func handsFreeInterludeDrivesTheRealPlayer() throws {
        let (player, context) = try livePlayer()
        let a = try playable("A", in: context)
        defer { EpisodeFiles.remove(episode: a.id); player.close() }
        player.load(a, context: context, autoplay: true)
        #expect(player.isPlaying)

        let audio = FakeAudio()
        let session = InterludeSession(prepared: PreparedInterlude(episodeID: a.id, chapter: 0, item: q("Soru", chapter: 0),
                                                                   url: URL(filePath: "/tmp/x.wav"), answerStart: 12.5, duration: 20),
                                       host: player, audio: audio)
        var dontKnow = 0
        session.onDontKnow = { _ in dontKnow += 1 }
        #expect(session.start())
        #expect(player.isInInterlude && !player.isPlaying)          // podcast durdu, ara ses çalıyor

        player.route(.nextChapter)                                 // kulaklıkta "sonraki" = bilemedim
        #expect(dontKnow == 1 && audio.seeks == [12.5])
        #expect(player.currentChapterIndex == 0)                   // podcast konusu değişmedi
        audio.finish?()
        #expect(!player.isInInterlude && player.isPlaying)          // ara ses bitti, podcast sürüyor
        player.route(.nextChapter)                                 // artık oynatıcıya gider
        #expect(player.currentChapterIndex == 1)
    }

    @Test func endCardHoldAndLockedScreenStartNextOnRealPlayer() throws {
        let (player, context) = try livePlayer()
        let series = UUID()
        let a = try playable("A", in: context, series: series, index: 1)
        let b = try playable("B", in: context, series: series, index: 2)
        defer { EpisodeFiles.remove(episode: a.id); EpisodeFiles.remove(episode: b.id); player.close() }
        player.load(a, context: context, autoplay: false)

        // Ön planda bitiş: kart sıradakini tutar (LearningCenter.episodeFinished ile aynı adımlar).
        var hold = NextUpHold()
        let token = PodcastEvent.observe(PodcastEvent.episodeFinished) { info in
            guard info.episodeID == a.id else { return }
            if let title = NextUpPeek.title(queue: player.queue, readyEpisodeTitle: { _ in nil }, seriesNext: { player.nextInSeries()?.title }) {
                player.holdAutoplay = true
                hold.begin(title: title)
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        player.finished()
        #expect(player.episode?.id == a.id && hold.title == "B")    // kart açık, sayaç sürüyor

        // Sayaç sürerken ekran kilitlendi: sıradaki hemen başlar.
        let card = LearningSheet.endCard(episodeID: a.id)
        #expect(NextUpHold.backgroundAdvance(sheet: card, hold: hold) == a.id)
        _ = hold.release()
        player.holdAutoplay = false
        player.playNext()
        #expect(player.episode?.id == b.id && player.isPlaying)
        #expect(NextUpHold.backgroundAdvance(sheet: card, hold: hold) == nil)   // ikinci kez başlatılmaz
    }

    @Test func listenAtMomentPlaysClipOnRealPlayer() throws {
        let (player, context) = try livePlayer()
        let a = try playable("A", in: context)
        defer { EpisodeFiles.remove(episode: a.id); player.close() }
        // "O anı dinle": kartın anı 3 sn öncesinden kesit olarak çalınır (bölüm sonunu aşan uç kırpılır).
        let clip = PodcastClip(episodeID: a.id, start: max(0, 4 - 3), end: 4 + 45, reason: "Kart", questionKey: "Soru")
        player.playClips([clip], context: context) { _ in }
        #expect(player.episode?.id == a.id && player.isPlayingClips && player.isPlaying)
        #expect(abs(player.currentTime - 1) < 0.01)
    }
}

/// Testte tekrarlanabilir karıştırma.
private struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
