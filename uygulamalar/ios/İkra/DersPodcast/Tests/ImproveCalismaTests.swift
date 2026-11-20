import CoreGraphics
import CoreText
import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import Ikra

/// Çalış alanı iyileştirmeleri. Dalga 1: bölüm seçici ve açılış sekmesi, yanlış defteri süzgeci, quiz turu,
/// tekrar turu ve geri alma, odak oturumunun kalıcılığı, Cornell PDF sayfalama.
/// Dalga 2: kavram/formül araması ve özet sayfalama, fotoğraftan okuma, yoklama rozeti, tek seferlik paket üretimi,
/// yanlışları çözme sırası, kavram ustalığı ve diğer bölümlerdeki geçişler.
@MainActor
@Suite struct ImproveCalismaTests {
    private func q(_ text: String, difficulty: Int? = nil) -> QuizItem {
        QuizItem(question: text, options: ["a", "b", "c", "d"], answerIndex: 0, explanation: "", sourcePage: nil, kind: nil,
                 chapterIndex: nil, turnIndex: nil, difficulty: difficulty, answerText: nil, verified: nil)
    }

    /// Sabit, geçmişte bir an (testler saate bağlı kalmasın).
    private func date(_ secondsAfter: TimeInterval = 0) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + secondsAfter) }

    // MARK: - 1: açılış sekmesi, bölüm seçici, arama

    @Test func startModePrefersKnownDebugNameThenCallerChoice() {
        #expect(StudyView.startMode(debug: "quiz", initial: .summary) == .quiz)
        #expect(StudyView.startMode(debug: nil, initial: .quiz) == .quiz)
        #expect(StudyView.startMode(debug: nil, initial: .summary) == .summary)
        #expect(StudyView.startMode(debug: "yok", initial: .cards) == .cards)
    }

    @Test func pickerLocksOnlyDeadEnds() {
        // Quiz hiç kilitlenmez: paketsiz bölümde "Oluştur" ekranı açılır.
        let noQuiz = EpisodePicker.row(kind: .quiz, figures: 0, questions: 0)
        #expect(!noQuiz.locked && !noQuiz.warns)
        #expect(noQuiz.note == "Quiz henüz yok, açınca oluşturabilirsin")
        #expect(EpisodePicker.row(kind: .quiz, figures: 0, questions: 12) == EpisodePicker.Row(note: "12 soru"))

        let noFigures = EpisodePicker.row(kind: .labelQuiz, figures: 0, questions: 0)
        #expect(noFigures.locked && noFigures.warns && noFigures.note != nil)
        #expect(EpisodePicker.row(kind: .labelQuiz, figures: 3, questions: 0) == EpisodePicker.Row(note: "3 şekil"))

        let noQuestions = EpisodePicker.row(kind: .socratic, figures: 0, questions: 0)
        #expect(noQuestions.locked && noQuestions.warns)
        #expect(noQuestions.note == "Önce bu bölümün quiz'ini oluştur")
        #expect(!EpisodePicker.row(kind: .socratic, figures: 0, questions: 5).locked)
        #expect(EpisodePicker.row(kind: .feynman, figures: 0, questions: 0) == EpisodePicker.Row())
    }

    @Test func pickerDoesNotLockBeforeCountsAreRead() {
        for kind in [StudyHub.PickKind.labelQuiz, .quiz, .feynman, .socratic] {
            #expect(EpisodePicker.row(kind: kind, figures: nil, questions: nil) == EpisodePicker.Row())
        }
    }

    @Test func searchFoldsTurkishLetters() {
        #expect(StudySearch.matches(["Isı ve sıcaklık"], query: "ısı"))
        #expect(StudySearch.matches(["Isı ve sıcaklık"], query: "ISI"))
        #expect(StudySearch.matches(["Isı ve sıcaklık"], query: "isi sicak"))
        #expect(StudySearch.matches(["İyon bağı"], query: "iyon bagi"))
        #expect(StudySearch.matches(["Hücre zarı"], query: "HÜCRE"))
        #expect(!StudySearch.matches(["Hücre zarı"], query: "mitokondri"))
        // Boş sorgu her şeyi eşler; sözcükler ayrı alanlarda bulunabilir.
        #expect(StudySearch.matches(["Hücre zarı"], query: ""))
        #expect(StudySearch.matches(["Hücre zarı"], query: "   "))
        #expect(StudySearch.matches(["Isı", "Sıcaklık"], query: "sicaklik isi"))
        #expect(!StudySearch.matches(["Isı", "Sıcaklık"], query: "isi basinc"))
        #expect(!StudySearch.matches([], query: "isi"))
    }

    // MARK: - 2: yanlış defteri

    @Test func mistakeSearchMatchesQuestionAnswersAndEpisode() {
        #expect(MistakeBook.matches(question: "Isı ve sıcaklık farkı", query: "ısı", group: .all))
        #expect(MistakeBook.matches(question: "İyon bağı nedir?", query: "iyon", group: .all))
        #expect(!MistakeBook.matches(question: "İyon bağı nedir?", query: "kovalent", group: .all))
        #expect(MistakeBook.matches(question: "Soru", myAnswer: "Madde alışverişini denetler", query: "alisveris", group: .all))
        #expect(MistakeBook.matches(question: "Soru", correct: "Seçici geçirgendir", query: "secici", group: .all))
        #expect(MistakeBook.matches(question: "Soru", why: "Zar çift katlıdır", query: "cift katli", group: .all))
        #expect(MistakeBook.matches(question: "Soru", episodeTitle: "Hücre zarı", query: "hucre", group: .all))
    }

    @Test func mistakeGroupsCoverEverySource() {
        for source in ["inline", "handsfree", "probe", "endcard", "quiz", "pretest", "discriminate"] {
            #expect(MistakeBook.matches(question: "S", source: source, query: "", group: .podcast))
            #expect(!MistakeBook.matches(question: "S", source: source, query: "", group: .video))
        }
        #expect(!MistakeBook.matches(question: "S", source: "video", query: "", group: .podcast))
        #expect(MistakeBook.matches(question: "S", source: "video", query: "", group: .video))
        #expect(MistakeBook.matches(question: "S", source: "confused", query: "", group: .video))
        #expect(MistakeBook.matches(question: "S", source: "exam", query: "", group: .exam))
        #expect(MistakeBook.matches(question: "S", source: "label", query: "", group: .label))
        #expect(MistakeBook.matches(question: "S", source: "question-solver", query: "", group: .solver))
        #expect(MistakeBook.matches(question: "S", source: "manual", query: "", group: .manual))
        // Tanınmayan kaynak süzgeçlerin dışında kalmaz.
        #expect(MistakeBook.Group.of(source: "yeni-kaynak") == .manual)
        #expect(MistakeBook.matches(question: "S", source: "yeni-kaynak", query: "", group: .all))
        // Süzgeç ve arama birlikte: grup tutmazsa arama tutsa da gelmez.
        #expect(!MistakeBook.matches(question: "Isı", source: "video", query: "isi", group: .exam))
    }

    @Test func mistakeSourceTitles() {
        #expect(MistakeBook.sourceTitle("handsfree") == "Eller serbest")
        #expect(MistakeBook.sourceTitle("inline") == "Dinlerken")
        #expect(MistakeBook.sourceTitle("confused") == "Video")
        #expect(MistakeBook.sourceTitle("bilinmeyen") == "Diğer")
        #expect(MistakeBook.sourceLine(source: "inline", episodeTitle: "Hücre zarı") == "Dinlerken · Hücre zarı")
        #expect(MistakeBook.sourceLine(source: "manual", episodeTitle: "") == "Elle")
        #expect(MistakeBook.sourceLine(source: "question-solver", episodeTitle: "Soru Çöz") == "Soru çöz")
    }

    // MARK: - 3: quiz turu

    @Test func quizRoundCountsOnlyItsOwnQuestions() {
        let items = (1...10).map { q("S\($0)") }
        var round = QuizRound(items: items)
        for (i, item) in items.enumerated() {
            #expect(round.current == item)
            #expect(!round.finished)
            round.record(item, isCorrect: i != 3)
            #expect(round.answered)
            round.advance()
        }
        #expect(round.finished && round.current == nil)
        #expect(round.total == 10)
        #expect(round.correct == 9)
        #expect(round.passed)
        #expect(round.wrong == [items[3]])
        // "Yalnız yanlışları çöz": yeni tur yalnız yanlışlardan ve baştan.
        let retry = QuizRound(items: round.wrong)
        #expect(retry.total == 1 && retry.index == 0 && retry.correct == 0 && !retry.finished)
    }

    @Test func quizRoundPassNeedsHalf() {
        func play(correct: Int) -> QuizRound {
            let items = (1...10).map { q("S\($0)") }
            var round = QuizRound(items: items)
            for (i, item) in items.enumerated() { round.record(item, isCorrect: i < correct); round.advance() }
            return round
        }
        #expect(!play(correct: 4).passed)
        #expect(play(correct: 5).passed)
        #expect(play(correct: 4).wrong.count == 6)
    }

    @Test func quizRoundCountsAQuestionOnceAndSkipsUngraded() {
        let items = [q("A"), q("B")]
        var round = QuizRound(items: items)
        round.record(items[0], isCorrect: true)
        round.record(items[0], isCorrect: true)      // aynı soru ikinci kez sayılmaz
        round.record(items[0], isCorrect: false)
        #expect(round.correct == 1 && round.wrong.isEmpty)
        round.advance()
        #expect(round.index == 1 && !round.answered)
        round.record(items[1], isCorrect: nil)       // notlanmamış açık uçlu: ne doğru ne yanlış
        #expect(round.correct == 1 && round.wrong.isEmpty && round.answered)
        round.advance()
        #expect(round.finished)
        round.advance()                              // biten turda etkisiz
        #expect(round.finished && round.index == 1)
    }

    @Test func newQuestionsStartTheirOwnRound() {
        // 10 soruluk quiz bitti, 10 yeni soru geldi, 9'u doğru: sonuç 10 üzerinden ve başlık "Soru 1 / 10".
        let old = (1...10).map { q("Eski \($0)") }
        let added = (1...10).map { q("Yeni \($0)") }
        var round = QuizRound(items: QuestionPicker.easyFirst(added))
        #expect(round.index == 0 && round.total == 10)
        for (i, item) in round.items.enumerated() { round.record(item, isCorrect: i != 0); round.advance() }
        #expect(round.total == 10 && round.correct == 9 && round.passed)
        // Paket büyüdü: sıra hepsini içerir, süren tur değişmez.
        let synced = QuizRound.sync(order: old + added, round: round, quiz: old + added)
        #expect(synced.order.count == 20)
        #expect(synced.round == round)
    }

    @Test func quizSyncBuildsKeepsAndResets() {
        let quiz = [q("Zor", difficulty: 3), q("Kolay", difficulty: 1), q("Orta")]
        let first = QuizRound.sync(order: [], round: nil, quiz: quiz)
        #expect(first.order.map(\.question) == ["Kolay", "Orta", "Zor"])
        #expect(first.round == QuizRound(items: first.order))

        // Süren tura dokunmadan: pakete eklenen soru sıranın sonuna girer.
        var playing = QuizRound(items: first.order)
        playing.record(first.order[0], isCorrect: true)
        playing.advance()
        let grown = QuizRound.sync(order: first.order, round: playing, quiz: quiz + [q("Ek")])
        #expect(grown.order.map(\.question) == ["Kolay", "Orta", "Zor", "Ek"])
        #expect(grown.round == playing)

        // Paket yeniden üretildi (turun soruları kalmadı): tur baştan kurulur.
        let replaced = QuizRound.sync(order: first.order, round: playing, quiz: [q("Başka 1"), q("Başka 2")])
        #expect(replaced.order.map(\.question) == ["Başka 1", "Başka 2"])
        #expect(replaced.round?.index == 0 && replaced.round?.correct == 0 && replaced.round?.total == 2)

        let emptied = QuizRound.sync(order: first.order, round: playing, quiz: [])
        #expect(emptied.order.isEmpty && emptied.round == nil)
    }

    // MARK: - 4: tekrar turu ve geri alma

    private func makeCard(in context: ModelContext) -> ReviewCard {
        let card = ReviewCard(episodeID: UUID(), episodeTitle: "Hücre", kind: .flashcard, front: "Ön", back: "Arka", sourcePage: nil)
        card.intervalDays = 10
        card.ease = 2.3
        card.repetitions = 4
        card.stability = 8
        card.memoryDifficulty = 5.5
        card.lastReviewed = date(-10 * 86_400)
        card.due = date()
        context.insert(card)
        return card
    }

    @Test func scheduleSnapshotRestoresEveryFieldAfterEasy() throws {
        let container = try ModelContainer(for: ReviewCard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        defer { withExtendedLifetime(container) {} }
        let card = makeCard(in: container.mainContext)
        let before = card.schedule
        card.reviewWithMemory(.easy, now: date())
        #expect(card.schedule != before)
        #expect(card.due > before.due && card.repetitions == 5)
        card.schedule = before
        #expect(card.schedule == before)
        #expect(card.ease == 2.3 && card.intervalDays == 10 && card.repetitions == 4 && card.lapses == 0)
        #expect(card.due == date() && card.lastReviewed == date(-10 * 86_400))
        #expect(card.stability == 8 && card.memoryDifficulty == 5.5 && card.lastLapseAt == nil)
    }

    @Test func scheduleSnapshotRestoresLapseAfterAgain() throws {
        let container = try ModelContainer(for: ReviewCard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        defer { withExtendedLifetime(container) {} }
        let card = makeCard(in: container.mainContext)
        let before = card.schedule
        card.reviewWithMemory(.again, now: date())
        #expect(card.lapses == 1 && card.lastLapseAt == date() && card.repetitions == 0)
        card.schedule = before
        #expect(card.lapses == 0 && card.lastLapseAt == nil && card.repetitions == 4)
        #expect(card.schedule == before)
    }

    @Test func reviewSummaryOffersNextRoundWhileCardsWait() {
        let more = ReviewSummary.text(done: 40, left: 80)
        #expect(more.title == "Bu tur bitti")
        #expect(more.continueTitle == "Devam et (40 kart)")
        #expect(more.detail.contains("40 kart tekrar edildi") && more.detail.contains("80 kart daha bekliyor"))
        #expect(ReviewSummary.text(done: 40, left: 7).continueTitle == "Devam et (7 kart)")

        let done = ReviewSummary.text(done: 12, left: 0)
        #expect(done.title == "Bugünlük bu kadar!")
        #expect(done.continueTitle == nil)
        #expect(done.detail == "12 kart tekrar edildi.")
    }

    // MARK: - 5: odak oturumu

    private func snapshot(phase: FocusTimer.Phase = .focus, start: Date, minutes: Int = 25, completedFocus: Int = 0,
                          courseID: UUID? = nil, episodeID: UUID? = nil) -> FocusTimer.Snapshot {
        FocusTimer.Snapshot(phase: phase.rawValue, startedAt: start, endsAt: start.addingTimeInterval(Double(minutes) * 60),
                            presetName: "25 / 5", focus: 25, brk: 5, courseID: courseID, episodeID: episodeID, completedFocus: completedFocus)
    }

    private func makeStore(_ snapshot: FocusTimer.Snapshot? = nil) throws -> (defaults: UserDefaults, suite: String) {
        let suite = "w1.focus.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        if let snapshot {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: FocusTimer.storeKey)
        }
        return (defaults, suite)
    }

    @Test func focusSessionSurvivesRelaunch() throws {
        let (defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let course = UUID(), episode = UUID()
        let a = FocusTimer(store: defaults)
        a.preset = FocusTimer.presets[1]
        a.courseID = course
        a.start(.focus)
        a.episodeID = episode                       // çalışırken bağlanan bölüm de yazılır

        let b = FocusTimer(store: defaults)         // "uygulama yeniden açıldı"
        #expect(b.phase == .focus && b.isRunning)
        #expect(abs(b.remaining - a.remaining) < 1)
        #expect(b.preset.focus == 50 && b.preset.brk == 10 && b.preset == FocusTimer.presets[1])
        #expect(b.courseID == course && b.episodeID == episode)

        a.stop()
        #expect(defaults.data(forKey: FocusTimer.storeKey) == nil)
        #expect(FocusTimer(store: defaults).phase == .idle)
    }

    @Test func recoveredSecondsNeverExceedPhaseLength() {
        let s = snapshot(start: date())
        let late = FocusTimer.recovered(s, now: date(4000))
        #expect(late.seconds == 1500 && late.completed)
        let early = FocusTimer.recovered(s, now: date(600))
        #expect(early.seconds == 600 && !early.completed)
        let before = FocusTimer.recovered(s, now: date(-30))
        #expect(before.seconds == 0 && !before.completed)
        #expect(!FocusTimer.isStale(s, now: date(1500 + 11 * 3600)))
        #expect(FocusTimer.isStale(s, now: date(1500 + 13 * 3600)))
    }

    @Test func expiredSessionIsRecordedAtRelaunchInsteadOfResuming() throws {
        // Bitişinden 1 saat sonra açıldı: "çalışıyor" geri gelmez (ders ekranı kendiliğinden mola başlatmasın, eski oturum
        // yeni derse bağlanmasın); kaydı açılışta tam süreyle yazılır.
        let course = UUID(), episode = UUID()
        let (defaults, suite) = try makeStore(snapshot(start: date(), completedFocus: 2, courseID: course, episodeID: episode))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try ModelContainer(for: StudySession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let now = date(1500 + 3600)

        let timer = FocusTimer(store: defaults, now: now)
        #expect(timer.phase == .idle && !timer.isRunning)
        #expect(timer.courseID == nil && timer.episodeID == nil)
        #expect(defaults.data(forKey: FocusTimer.storeKey) != nil)  // kayıt yazılana kadar saklanır
        timer.reconcile(context: context, now: now)
        var sessions = try context.fetch(FetchDescriptor<StudySession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.seconds == 1500 && sessions.first?.completed == true)
        #expect(sessions.first?.startedAt == date() && sessions.first?.courseID == course && sessions.first?.episodeID == episode)
        #expect(sessions.first?.kind == "focus")
        #expect(defaults.data(forKey: FocusTimer.storeKey) == nil)
        #expect(timer.completedFocus == 3 && !timer.isRunning)      // uzun mola sırası kısa kapanışta kaybolmaz
        timer.reconcile(context: context, now: now)                 // ikinci kez yazmaz, sayacı yeniden artırmaz
        sessions = try context.fetch(FetchDescriptor<StudySession>())
        #expect(sessions.count == 1 && timer.completedFocus == 3)
    }

    @Test func relaunchResumesOnlyAnUnexpiredSession() throws {
        let (defaults, suite) = try makeStore(snapshot(start: date(), completedFocus: 1))
        defer { defaults.removePersistentDomain(forName: suite) }
        let running = FocusTimer(store: defaults, now: date(1499))  // bitişe 1 sn var: kaldığı yerden
        #expect(running.phase == .focus && running.isRunning && running.completedFocus == 1)
        #expect(FocusTimer(store: defaults, now: date(1500)).phase == .idle)        // tam bitiş anı: dolmuş
        #expect(FocusTimer(store: defaults, now: date(1500 + 60)).phase == .idle)
    }

    @Test func expiredBreakIsDroppedAtRelaunchAndKeepsTheFocusCount() throws {
        // Süresi dolmuş mola geri gelseydi ders açılır açılmaz odak başlar, video kendiliğinden oynardı.
        let (defaults, suite) = try makeStore(snapshot(phase: .shortBreak, start: date(), minutes: 5, completedFocus: 3))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try ModelContainer(for: StudySession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        defer { withExtendedLifetime(container) {} }
        let now = date(300 + 600)
        let timer = FocusTimer(store: defaults, now: now)
        #expect(timer.phase == .idle)
        timer.reconcile(context: container.mainContext, now: now)
        #expect(try container.mainContext.fetch(FetchDescriptor<StudySession>()).isEmpty)   // mola çalışma sayılmaz
        #expect(defaults.data(forKey: FocusTimer.storeKey) == nil)
        #expect(timer.completedFocus == 3)
    }

    @Test func staleSessionIsRecordedInsteadOfResuming() throws {
        let episode = UUID()
        let (defaults, suite) = try makeStore(snapshot(start: date(), episodeID: episode))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try ModelContainer(for: StudySession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let now = date(1500 + 13 * 3600)

        let timer = FocusTimer(store: defaults, now: now)
        #expect(timer.phase == .idle && !timer.isRunning)          // günler sonra "çalışıyor" görünmez
        #expect(defaults.data(forKey: FocusTimer.storeKey) != nil)  // kayıt yazılana kadar saklanır
        timer.reconcile(context: context, now: now)
        var sessions = try context.fetch(FetchDescriptor<StudySession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.seconds == 1500 && sessions.first?.completed == true && sessions.first?.episodeID == episode)
        #expect(defaults.data(forKey: FocusTimer.storeKey) == nil)
        timer.reconcile(context: context, now: now)                 // ikinci kez yazmaz
        sessions = try context.fetch(FetchDescriptor<StudySession>())
        #expect(sessions.count == 1)
        #expect(timer.completedFocus == 0)                          // çok eski oturumdan sonra mola sırası baştan
    }

    @Test func staleBreakLeavesNoSession() throws {
        let (defaults, suite) = try makeStore(snapshot(phase: .shortBreak, start: date(), minutes: 5))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try ModelContainer(for: StudySession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        defer { withExtendedLifetime(container) {} }
        let now = date(300 + 13 * 3600)
        let timer = FocusTimer(store: defaults, now: now)
        timer.reconcile(context: container.mainContext, now: now)
        #expect(try container.mainContext.fetch(FetchDescriptor<StudySession>()).isEmpty)
        #expect(defaults.data(forKey: FocusTimer.storeKey) == nil)
    }

    @Test func corruptSnapshotIsIgnored() throws {
        let (defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("bozuk".utf8), forKey: FocusTimer.storeKey)
        #expect(FocusTimer(store: defaults).phase == .idle)
    }

    @Test func focusNotificationNamesTheRealBreak() {
        #expect(FocusTimer.minutes(for: .focus, preset: FocusTimer.presets[1]) == 50)
        #expect(FocusTimer.minutes(for: .shortBreak, preset: FocusTimer.presets[1]) == 10)
        #expect(FocusTimer.minutes(for: .longBreak, preset: FocusTimer.presets[2]) == 45)
        let focus = FocusTimer.notificationText(ending: .focus, breakMinutes: 10)
        #expect(focus.title == "Odak bitti — mola zamanı")
        #expect(focus.body == "Kalk, su iç, 10 dakika uzaklaş.")
        #expect(FocusTimer.notificationText(ending: .focus, breakMinutes: 45).body.contains("45 dakika"))
        let rest = FocusTimer.notificationText(ending: .shortBreak, breakMinutes: 10)
        #expect(rest.title == "Mola bitti — devam" && !rest.body.contains("10"))
    }

    // MARK: - 6: Cornell

    @Test func cornellPDFPagesStartAtTheTop() {
        #expect(CornellPDF.pageOffsets(contentHeight: 500) == [342])
        #expect(CornellPDF.pageOffsets(contentHeight: 842) == [0])
        #expect(CornellPDF.pageOffsets(contentHeight: 1000) == [-158, 684])
        #expect(CornellPDF.pageOffsets(contentHeight: 1684) == [-842, 0])
        // Yuvarlama payı yeni sayfa açmaz; boş içerik tek sayfadır.
        #expect(CornellPDF.pageOffsets(contentHeight: 842.4).count == 1)
        #expect(CornellPDF.pageOffsets(contentHeight: 0) == [842])
        #expect(CornellPDF.pageOffsets(contentHeight: 3000).count == 4)
        // Her sayfada içeriğin üstü bir sayfa boyu daha aşağıdan başlar.
        let offsets = CornellPDF.pageOffsets(contentHeight: 3000)
        #expect(offsets.first == CGFloat(-2158))
        #expect(zip(offsets, offsets.dropFirst()).allSatisfy { $1 - $0 == 842 })
    }

    @Test func blankNewCornellNoteIsDiscardedButTypedOneIsKept() {
        #expect(CornellNote.isBlank(cues: " ", notes: "\n", summary: ""))
        #expect(!CornellNote.isBlank(cues: " ", notes: "a", summary: ""))
        #expect(!CornellNote.isBlank(cues: "", notes: "", summary: "Özet"))
        // Yeni not: başlık açılıştaki (bölüm adı) hâlindeyse ve gövde boşsa silinir.
        #expect(CornellNote.isUntouchedNew(title: "", initialTitle: "", cues: "", notes: " \n", summary: ""))
        #expect(CornellNote.isUntouchedNew(title: "Hücre zarı ", initialTitle: "Hücre zarı", cues: "", notes: "", summary: ""))
        // Başlık yazıldıysa ya da gövdede bir şey varsa kalır.
        #expect(!CornellNote.isUntouchedNew(title: "Kimya 3. ünite", initialTitle: "", cues: "", notes: "", summary: ""))
        #expect(!CornellNote.isUntouchedNew(title: "", initialTitle: "", cues: "Soru?", notes: "", summary: ""))
    }

    // MARK: - Dalga 2 yardımcıları

    private func store() throws -> ModelContainer {
        try ModelContainer(for: Schema(AppDataStore.modelTypes), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func makeEpisode(in context: ModelContext) -> Episode {
        let turn = ScriptTurn(speaker: .a, text: "Metin", style: "", sourcePage: nil, think: nil)
        let script = PodcastScript(title: "Hücre", summary: "Özet", keyPoints: [],
                                   chapters: [ScriptChapter(title: "Konu", scenes: [ScriptScene(turns: [turn])])], sourceNotes: "Notlar")
        let episode = Episode(script: script, settings: PodcastSettings(), sourceNames: [], jobToken: "")
        context.insert(episode)
        return episode
    }

    private func concept(_ name: String, _ definition: String = "") -> Concept {
        Concept(name: name, definition: definition, related: [], sourcePage: nil)
    }

    /// Üzerinde `text` yazan JPEG. `exifOrientation` 6: pikseller 90° saat yönünün tersine yatırılır ve EXIF yönü 6 yazılır
    /// (iPhone'un dik çekimi gibi; doğru gösterim için 90° saat yönünde çevrilmesi gerekir).
    private func photo(_ text: String, exifOrientation: Int) -> Data? {
        let w = 640, h = 240
        let space = CGColorSpaceCreateDeviceRGB()
        func canvas(_ w: Int, _ h: Int) -> CGContext? {
            CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        }
        guard let up = canvas(w, h) else { return nil }
        up.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        up.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 72, nil)
        let attributes = [kCTFontAttributeName: font,
                          kCTForegroundColorAttributeName: CGColor(red: 0, green: 0, blue: 0, alpha: 1)] as CFDictionary
        guard let string = CFAttributedStringCreate(nil, text as CFString, attributes) else { return nil }
        up.textPosition = CGPoint(x: 40, y: 90)
        CTLineDraw(CTLineCreateWithAttributedString(string), up)
        guard let upright = up.makeImage() else { return nil }
        var image = upright
        if exifOrientation == 6 {
            guard let turned = canvas(h, w) else { return nil }
            // CG koordinatında (y yukarı) +90° saat yönünün tersine dönüştür.
            turned.translateBy(x: CGFloat(h), y: 0)
            turned.rotate(by: .pi / 2)
            turned.draw(upright, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard let made = turned.makeImage() else { return nil }
            image = made
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: exifOrientation] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    // MARK: - 7: kavram ve formül araması, özet sayfalama

    @Test func searchKeyMatchesLikeFieldSearch() {
        #expect(StudySearch.matches(key: StudySearch.key(["Isı"]), query: "ısı"))
        #expect(StudySearch.matches(key: StudySearch.key(["İyon bağı"]), query: "iyon"))
        #expect(StudySearch.matches(key: StudySearch.key(["Işık hızı"]), query: "ISIK"))
        #expect(StudySearch.matches(key: StudySearch.key(["Işık"]), query: "isik"))
        #expect(!StudySearch.matches(key: StudySearch.key(["Baz"]), query: "asit"))
        #expect(StudySearch.matches(key: StudySearch.key(["Baz"]), query: ""))
        // Alan aramasıyla aynı kural: sözcükler ayrı alanlarda bulunabilir, tek sözcük iki alana yayılamaz.
        #expect(StudySearch.matches(key: StudySearch.key(["Isı", "Sıcaklık"]), query: "sicaklik isi"))
        #expect(!StudySearch.matches(key: StudySearch.key(["ab", "cd"]), query: "abcd"))
    }

    @Test func formulaCardsDecodeEpisodeBlobsAndFilterByKind() async throws {
        let encoder = JSONEncoder()
        let pack = StudyPack(quiz: [], flashcards: [], concepts: [concept("Paket kavramı", "Yedek")],
                             formulas: [Formula(name: "İş", expression: "W = F·d", meaning: "Kuvvet çarpı yol", when: "Sabit kuvvet"),
                                        Formula(name: "Güç", expression: "P = W/t", meaning: "Birim zamandaki iş", when: "")])
        let withConcepts = FormulaCards.Blob(title: "Fizik 1", concepts: try encoder.encode([concept("Isı", "Enerji aktarımı")]),
                                             study: try encoder.encode(pack))
        // Kavram alanı yok ya da bozuk: paketteki kavramlar (Episode.concepts ile aynı kural).
        let packOnly = FormulaCards.Blob(title: "Fizik 2", concepts: nil, study: try encoder.encode(pack))
        let broken = FormulaCards.Blob(title: "Bozuk", concepts: Data("bozuk".utf8), study: Data("bozuk".utf8))
        let items = FormulaCards.items([withConcepts, packOnly, broken, FormulaCards.Blob(title: "Boş", concepts: nil, study: nil)])
        #expect(items.map(\.name) == ["Isı", "İş", "Güç", "Paket kavramı", "İş", "Güç"])
        #expect(items.map(\.kind) == [.concept, .formula, .formula, .concept, .formula, .formula])
        #expect(items[0].episode == "Fizik 1" && items[3].episode == "Fizik 2")
        #expect(items[1].body == "W = F·d\nKuvvet çarpı yol\nNe zaman: Sabit kuvvet")
        #expect(items[2].body == "P = W/t\nBirim zamandaki iş")

        #expect(FormulaCards.filter(items, query: "ısı", kind: nil).map(\.name) == ["Isı"])
        #expect(FormulaCards.filter(items, query: "is", kind: .formula).count == 4)        // "İş" adı, "iş" gövdesi
        #expect(FormulaCards.filter(items, query: "", kind: .formula).count == 4)
        #expect(FormulaCards.filter(items, query: "", kind: .concept).map(\.name) == ["Isı", "Paket kavramı"])
        #expect(FormulaCards.filter(items, query: "", kind: nil).count == 6)
        #expect(FormulaCards.filter(items, query: "sabit kuvvet", kind: .concept).isEmpty)
        #expect(FormulaCards.filter(items, query: "sabit kuvvet", kind: nil).count == 2)

        let background = await FormulaCards.decode([withConcepts])
        #expect(background.map(\.name) == ["Isı", "İş", "Güç"])
    }

    @Test func cheatSheetPagesRespectCapacityAndKeepEveryRow() {
        func load(_ page: [(String, String, String)]) -> Int { page.reduce(0) { $0 + CheatSheet.cost($1) } }
        let short = (1...30).map { ("Kavram \($0)", "Kısa tanım", "Bölüm") }
        let pages = CheatSheet.pages(short)
        #expect(pages.count == 2)
        #expect(pages.allSatisfy { load($0) <= 58 })
        #expect(pages.flatMap { $0 }.map(\.0) == short.map(\.0))

        // Beş satırlık gövde: satır başına 7 birim; hiçbir satır kaybolmaz.
        let long = (1...20).map { ("Formül \($0)", "a\nb\nc\nd\ne", "Bölüm") }
        let longPages = CheatSheet.pages(long)
        #expect(CheatSheet.cost(long[0]) == 7)
        #expect(longPages.count == 3)
        #expect(longPages.allSatisfy { load($0) <= 58 })
        #expect(longPages.flatMap { $0 }.map(\.0) == long.map(\.0))

        #expect(CheatSheet.bodyLines("") == 1)
        #expect(CheatSheet.bodyLines("ifade\nanlam\nNe zaman: hep") == 3)
        #expect(CheatSheet.bodyLines(String(repeating: "a", count: 250)) == 3)
        #expect(CheatSheet.bodyLines("a\nb\nc\nd\ne\nf\ng") == 5)                    // en çok beş satır basılır
        #expect(CheatSheet.pages([]).isEmpty)
        // Kapasite tek satırdan küçükse de satır atlanmaz: her satır kendi sayfasında.
        #expect(CheatSheet.pages(short, capacity: 1).count == 30)
    }

    // MARK: - 8: fotoğraftan soru okuma

    @Test func ocrLinesStaySeparateAndBlankOnesDrop() {
        #expect(TextReader.assemble([" Soru kökü ", "", "A) x", "B) y"]) == "Soru kökü\nA) x\nB) y")
        #expect(TextReader.assemble([]) == "")
        #expect(TextReader.assemble(["  ", "\n"]) == "")
        // Elle yazılmış soru silinmez: okunan metin sonuna eklenir.
        #expect(TextReader.appended("A) x", to: "") == "A) x")
        #expect(TextReader.appended("A) x", to: "  \n") == "A) x")
        #expect(TextReader.appended("A) x\nB) y", to: "Elle yazdığım soru \n") == "Elle yazdığım soru\nA) x\nB) y")
    }

    @Test func rotatedPhotoIsReadUpright() async throws {
        // Yön, okunan metinle sınanamaz (Vision yatık yazıyı da okur): satırın kutusuna bakılır. EXIF yönü uygulanınca
        // kutu düz görseldeki gibi yatay çıkar; uygulanmazsa (ham pikseller) dikey çıkar.
        let upright = try #require(photo("HUCRE ZARI", exifOrientation: 1))
        let flatLines = await TextReader.lines(upright)
        let flat = try #require(flatLines.first { $0.text.contains("HUCRE") })
        #expect(flat.box.width > flat.box.height)
        let rotated = try #require(photo("HUCRE ZARI", exifOrientation: 6))
        let turnedLines = await TextReader.lines(rotated)
        let turned = try #require(turnedLines.first { $0.text.contains("HUCRE") })
        #expect(turned.box.width > turned.box.height)
        let text = await TextReader.read(rotated)
        #expect(text.contains("HUCRE"))
    }

    // MARK: - 9: yoklama rozeti ve liste

    @Test func dueEpisodeCountMatchesTheProbeList() {
        let a = UUID(), b = UUID()
        let end = date(86_400)
        // Aynı bölümün vadesi gelmiş yoklaması ve yeniden dinleme görevi tek bölüm sayılır.
        #expect(ProbeScheduler.dueEpisodeCount([(episodeID: a, due: date()), (episodeID: a, due: date(-3600))], endOfToday: end) == 1)
        #expect(ProbeScheduler.dueEpisodeCount([(episodeID: a, due: date(-3600))], endOfToday: end) == 1)       // yalnız yeniden dinleme
        #expect(ProbeScheduler.dueEpisodeCount([(episodeID: a, due: date(86_400 + 9 * 3600))], endOfToday: end) == 0)   // yarına vadeli
        #expect(ProbeScheduler.dueEpisodeCount([(episodeID: nil, due: date())], endOfToday: end) == 0)           // bölümsüz kayıt
        #expect(ProbeScheduler.dueEpisodeCount([(episodeID: a, due: date()), (episodeID: b, due: date()),
                                                (episodeID: b, due: date(2 * 86_400))], endOfToday: end) == 2)
        #expect(ProbeScheduler.dueEpisodeCount([], endOfToday: end) == 0)
    }

    @Test func probeRowNotes() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Istanbul"))
        let now = date()
        let start = calendar.startOfDay(for: now)
        let end = ProbeScheduler.endOfDay(now, calendar: calendar)
        #expect(end > now && end.timeIntervalSince(start) == 86_400)
        #expect(ProbeScheduler.dueNote(start.addingTimeInterval(-60), now: now, calendar: calendar) == "gecikti")
        #expect(ProbeScheduler.dueNote(start.addingTimeInterval(9 * 3600), now: now, calendar: calendar) == "bugün")
        #expect(ProbeScheduler.dueNote(end, now: now, calendar: calendar) == nil)
        #expect(ProbeScheduler.relistenNote(score: 0.4) == "Yoklamada %40")
        #expect(ProbeScheduler.relistenNote(score: nil) == "Yoklamada zorlandın")
    }

    // MARK: - 10: çalışma paketi tek sefer üretilir

    @MainActor private final class BuildProbe {
        var runs = 0
        var sawActive = false
    }

    private struct BuildFailed: Error {}

    @Test func relistenTaskCountsUntilItIsClosedByHand() throws {
        let container = try store()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let episode = makeEpisode(in: context)
        episode.statusRaw = EpisodeStatus.ready.rawValue
        let now = date()
        ProbeAdvisor.scheduleProbes(for: episode, context: context, now: date(-86_400), stages: [1, 7], plan: nil)
        ProbeAdvisor.finish(episodeID: episode.id, score: 0.4, context: context, now: now)
        var open = try context.fetch(FetchDescriptor<EpisodeProbe>()).filter { $0.completedAt == nil }
        let relisten = try #require(open.first { $0.kindRaw == "relisten" })
        let end = ProbeScheduler.endOfDay(now)
        // Rozet: yeniden dinleme görevi (yoklama kapanmış olsa da) bölümü sayar; liste de onu gösterir.
        #expect(ProbeScheduler.dueEpisodeCount(open.map { (episodeID: $0.episodeID, due: $0.dueDate) }, endOfToday: end) == 1)

        relisten.completedAt = now      // listedeki "Tamamlandı"
        try context.save()
        open = try context.fetch(FetchDescriptor<EpisodeProbe>()).filter { $0.completedAt == nil }
        #expect(ProbeScheduler.dueEpisodeCount(open.map { (episodeID: $0.episodeID, due: $0.dueDate) }, endOfToday: end) == 0)
    }

    @Test func sameEpisodeIsBuiltOnceAndWaitersShareIt() async throws {
        let builds = StudyBuilds()
        let probe = BuildProbe()
        let id = UUID()
        let work: @MainActor () async throws -> Void = {
            probe.runs += 1
            probe.sawActive = builds.active.contains(id)
            try await Task.sleep(for: .milliseconds(50))
        }
        let first = Task { try await builds.run(id, work) }
        let second = Task { try await builds.run(id, work) }
        try await first.value
        try await second.value
        #expect(probe.runs == 1)
        #expect(probe.sawActive)
        #expect(builds.active.isEmpty)
        // Bitince aynı bölüm yeniden üretilebilir.
        try await builds.run(id, work)
        #expect(probe.runs == 2 && builds.active.isEmpty)
    }

    @Test func failedBuildReachesEveryWaiterAndClears() async {
        let builds = StudyBuilds()
        let probe = BuildProbe()
        let id = UUID()
        let work: @MainActor () async throws -> Void = {
            probe.runs += 1
            try await Task.sleep(for: .milliseconds(30))
            throw BuildFailed()
        }
        let first = Task { try await builds.run(id, work) }
        let second = Task { try await builds.run(id, work) }
        let a = await first.result, b = await second.result
        #expect(throws: BuildFailed.self) { try a.get() }
        #expect(throws: BuildFailed.self) { try b.get() }
        #expect(probe.runs == 1 && builds.active.isEmpty)
    }

    @Test func differentEpisodesBuildSeparately() async throws {
        let builds = StudyBuilds()
        let probe = BuildProbe()
        let work: @MainActor () async throws -> Void = {
            probe.runs += 1
            try await Task.sleep(for: .milliseconds(20))
        }
        let first = Task { try await builds.run(UUID(), work) }
        let second = Task { try await builds.run(UUID(), work) }
        try await first.value
        try await second.value
        #expect(probe.runs == 2 && builds.active.isEmpty)
    }

    @Test func deckAddSkipsDuplicateFrontsWithinAPack() throws {
        let container = try store()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let episode = makeEpisode(in: context)
        let pack = [Flashcard(front: "A", back: "1"), Flashcard(front: "A", back: "2"), Flashcard(front: "B", back: "3")]
        ReviewDeck.add(flashcards: pack, episode: episode, context: context)
        #expect(try context.fetch(FetchDescriptor<ReviewCard>()).map(\.front).sorted() == ["A", "B"])
        ReviewDeck.add(flashcards: pack, episode: episode, context: context)       // aynı paket ikinci kez: kart eklenmez
        #expect(try context.fetch(FetchDescriptor<ReviewCard>()).count == 2)
    }

    // MARK: - 11: yanlışları çöz

    @Test func practiceOrderPrefersLeastReviewedThenNewest() {
        let ids = (0..<4).map { _ in UUID() }
        let items = [(id: ids[0], reviewed: 0, created: date(0)), (id: ids[1], reviewed: 2, created: date(300)),
                     (id: ids[2], reviewed: 0, created: date(200)), (id: ids[3], reviewed: 1, created: date(100))]
        #expect(MistakeBook.practiceOrder(items, limit: 2) == [ids[2], ids[0]])
        #expect(MistakeBook.practiceOrder(items) == [ids[2], ids[0], ids[3], ids[1]])
        #expect(MistakeBook.practiceOrder(items, limit: 0).isEmpty)
        #expect(MistakeBook.practiceOrder([]).isEmpty)
        #expect(MistakeBook.practiceSummary(known: 10, total: 10, solved: 0) == "10 / 10 bildin · 0 soru defterden düştü")
    }

    @Test func repeatedMistakeResetsStreakAndKeepsOneEntry() throws {
        let container = try store()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let item = q("Hücre zarı neyden oluşur?")
        MistakeBook.record(item, myAnswer: "b", episode: nil, source: "quiz", context: context)
        var entries = try context.fetch(FetchDescriptor<MistakeEntry>())
        #expect(entries.count == 1 && entries.first?.myAnswer == "b")
        entries.first?.correctStreak = 1        // bir kez "Bildim" denmişti
        try context.save()

        MistakeBook.record(item, myAnswer: "c", episode: nil, source: "quiz", context: context)
        entries = try context.fetch(FetchDescriptor<MistakeEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.correctStreak == 0 && entries.first?.myAnswer == "c")
        // Boş cevap (eller serbest "bilemedim" gibi) eski cevabı silmez.
        MistakeBook.record(item, myAnswer: "", episode: nil, source: "quiz", context: context)
        #expect(try context.fetch(FetchDescriptor<MistakeEntry>()).first?.myAnswer == "c")

        // Çözülmüş soru yeniden yanlış yapılırsa yeni girdi açılır (eski davranış).
        entries.first?.resolved = true
        try context.save()
        MistakeBook.record(item, myAnswer: "d", episode: nil, source: "quiz", context: context)
        #expect(try context.fetch(FetchDescriptor<MistakeEntry>()).count == 2)
    }

    @Test func mistakeInAnotherQuestionWithTheSameStemLeavesTheEntryAlone() throws {
        let container = try store()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let stem = "Aşağıdakilerden hangisi doğrudur?"
        MistakeBook.record(q(stem), myAnswer: "b", episode: nil, source: "quiz", context: context)      // doğru cevabı "a"
        let entry = try #require(try context.fetch(FetchDescriptor<MistakeEntry>()).first)
        entry.correctStreak = 1                 // bir kez "Bildim" denmişti
        try context.save()

        // Kökü aynı, şıkları ve doğru cevabı başka bir soru: ilk sorunun cevabı ve serisi değişmez.
        let other = QuizItem(question: stem, options: ["k", "l", "m", "n"], answerIndex: 1, explanation: "", sourcePage: nil, kind: nil,
                             chapterIndex: nil, turnIndex: nil, difficulty: nil, answerText: nil, verified: nil)
        MistakeBook.record(other, myAnswer: "k", episode: nil, source: "quiz", context: context)
        #expect(entry.myAnswer == "b" && entry.correctStreak == 1 && entry.correctAnswer == "a")
        // Aynı soru yeniden yanlış yapılınca eskisi gibi güncellenir.
        MistakeBook.record(q(stem), myAnswer: "c", episode: nil, source: "quiz", context: context)
        #expect(entry.myAnswer == "c" && entry.correctStreak == 0)
    }

    @Test func placeholderAnswerKeepsTheConcreteWrongAnswer() throws {
        #expect(MistakeBook.repeatedAnswer(old: "b", new: "c") == "c")
        #expect(MistakeBook.repeatedAnswer(old: "b", new: "") == "b")
        #expect(MistakeBook.repeatedAnswer(old: "b", new: "  ") == "b")
        #expect(MistakeBook.repeatedAnswer(old: "b", new: "Bilemedim") == "b")
        #expect(MistakeBook.repeatedAnswer(old: "b", new: "Boş") == "b")
        #expect(MistakeBook.repeatedAnswer(old: "", new: "Boşluk") == "Boşluk")

        let container = try store()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let item = q("Hücre zarı neyden oluşur?")
        MistakeBook.record(item, myAnswer: "b", episode: nil, source: "quiz", context: context)
        let entry = try #require(try context.fetch(FetchDescriptor<MistakeEntry>()).first)
        entry.correctStreak = 1
        try context.save()
        // Eller serbest "Bilemedim" ve denemede boş bırakma: somut yanlış cevap kalır, seri yine sıfırlanır.
        MistakeBook.record(item, myAnswer: "Bilemedim", episode: nil, source: "handsfree", context: context)
        #expect(entry.myAnswer == "b" && entry.correctStreak == 0)
        MistakeBook.record(item, myAnswer: "Boş", episode: nil, source: "exam", context: context)
        #expect(entry.myAnswer == "b")
        #expect(try context.fetch(FetchDescriptor<MistakeEntry>()).count == 1)
        // Yeni girdide yer tutucu yazılır (defterde "Senin cevabın: Bilemedim").
        MistakeBook.record(q("Ribozom ne üretir?"), myAnswer: "Bilemedim", episode: nil, source: "handsfree", context: context)
        let all = try context.fetch(FetchDescriptor<MistakeEntry>())
        #expect(all.first { $0.question == "Ribozom ne üretir?" }?.myAnswer == "Bilemedim")
    }

    @Test func wrongAgainPullsTheCardForwardWithoutDuplicating() throws {
        let container = try store()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let episode = makeEpisode(in: context)
        let item = q("Zar seçici geçirgen midir?")
        ReviewDeck.addWrong(item, episode: episode, context: context, now: date())
        var cards = try context.fetch(FetchDescriptor<ReviewCard>())
        #expect(cards.count == 1)
        cards.first?.due = date(10 * 86_400)     // haftalar sonraya planlı
        try context.save()

        ReviewDeck.addWrong(item, episode: episode, context: context, now: date(60))
        cards = try context.fetch(FetchDescriptor<ReviewCard>())
        #expect(cards.count == 1)
        #expect(cards.first?.due == date(60))
        // Vadesi zaten gelmiş kartın tarihi ileri alınmaz.
        cards.first?.due = date(-86_400)
        ReviewDeck.addWrong(item, episode: episode, context: context, now: date(60))
        #expect(try context.fetch(FetchDescriptor<ReviewCard>()).first?.due == date(-86_400))
    }

    // MARK: - 12: kavram ustalığı ve diğer bölümler

    @Test func masteryIgnoresUnstudiedCards() {
        #expect(Mastery.score(samples: []) == nil)
        #expect(Mastery.score(samples: [(repetitions: 0, lapses: 0, reviewed: false)]) == nil)
        #expect(Mastery.score(samples: [(repetitions: 0, lapses: 1, reviewed: true)]) == 0)
        #expect(Mastery.score(samples: [(repetitions: 2, lapses: 0, reviewed: true)]) == 1)
        #expect(Mastery.score(samples: [(repetitions: 1, lapses: 0, reviewed: true), (repetitions: 0, lapses: 0, reviewed: false)]) == 0.6)
    }

    @Test func wrongQuizCardIsWeakOnTheMapBeforeItsFirstReview() throws {
        let container = try store()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let episode = makeEpisode(in: context)
        ReviewDeck.addWrong(q("Kornea ışığı nasıl kırar?"), episode: episode, context: context, now: date())
        ReviewDeck.add(flashcards: [Flashcard(front: "Retina nedir?", back: "Işığa duyarlı tabaka")], episode: episode, context: context)
        let cards = try context.fetch(FetchDescriptor<ReviewCard>())
        // İkisi de hiç tekrar edilmedi; fark kartın kökeninde.
        #expect(cards.count == 2 && cards.allSatisfy { $0.repetitions == 0 && $0.lapses == 0 && $0.lastReviewed == nil })
        let scores = Mastery.scores(names: ["Kornea", "Retina"], cards: cards)
        #expect(scores["Kornea"] == 0.3)        // yanlış yapılan soru: "Zayıf" (kırmızı)
        #expect(scores["Kornea"].map(Mastery.label) == "Zayıf")
        #expect(scores["Retina"] == nil)        // hiç açılmamış flashcard: nötr
    }

    @Test func masteryScoresEveryConceptInOnePass() {
        let cards: [(text: String, sample: Mastery.Sample)] = [
            (text: "Isı nedir? Enerji aktarımı", sample: (repetitions: 2, lapses: 0, reviewed: true)),
            (text: "İyon bağı elektron alışverişidir", sample: (repetitions: 0, lapses: 0, reviewed: false)),
            (text: "ISI ve sıcaklık farkı", sample: (repetitions: 0, lapses: 1, reviewed: true)),
        ]
        let scores = Mastery.scores(names: ["Isı", "İyon bağı", "Entropi"], cards: cards)
        #expect(scores["Isı"] == 0.5)           // öğrenilmiş bir kart + yanlış yapılmış bir kart
        #expect(scores["İyon bağı"] == nil)     // kartı var ama hiç çalışılmamış: nötr
        #expect(scores["Entropi"] == nil)       // kartı yok
    }

    @Test func otherEpisodeMentionsComeFromRawBlobs() async throws {
        let encoder = JSONEncoder()
        func transcript(_ texts: [String]) throws -> Data {
            let turns = texts.enumerated().map {
                TimedTurn(id: $0.offset, chapterIndex: 0, speaker: .a, text: $0.element, sourcePage: nil,
                          start: Double($0.offset) * 10, end: Double($0.offset) * 10 + 9)
            }
            return try encoder.encode(Timeline(chapters: [], turns: turns, duration: 100))
        }
        let spoken = ConceptLayout.EpisodeBlob(id: UUID(), title: "Göz", concepts: nil, study: nil,
                                               timeline: try transcript(["Giriş", "İris ve KORNEA ışığı kırar", "Kornea yine"]))
        let silent = ConceptLayout.EpisodeBlob(id: UUID(), title: "Kulak", concepts: nil, study: nil,
                                               timeline: try transcript(["Giriş", "Salyangoz"]))
        // Biri transkriptinde geçiriyor, diğeri geçirmiyor: tek sonuç, zaman o turun başlangıcı.
        #expect(ConceptLayout.mentionsNow(of: "Kornea", in: [spoken, silent]) == [OtherMention(id: spoken.id, title: "Göz", time: 10)])

        // Kavram listesinde adı olan ama transkriptinde geçmeyen bölüm zamansız döner (paketteki kavramlar da sayılır).
        let listed = ConceptLayout.EpisodeBlob(id: UUID(), title: "Optik", concepts: try encoder.encode([concept("kornea")]),
                                               study: nil, timeline: try transcript(["Mercekler"]))
        let pack = StudyPack(quiz: [], flashcards: [], concepts: [concept("Kornea")], formulas: nil)
        let viaPack = ConceptLayout.EpisodeBlob(id: UUID(), title: "Paket", concepts: nil, study: try encoder.encode(pack), timeline: nil)
        let broken = ConceptLayout.EpisodeBlob(id: UUID(), title: "Bozuk", concepts: Data("x".utf8), study: nil, timeline: Data("x".utf8))
        let found = await ConceptLayout.mentions(of: "Kornea", in: [silent, listed, broken, spoken, viaPack])
        #expect(found.map(\.title) == ["Optik", "Göz", "Paket"])
        #expect(found.map(\.time) == [nil, 10, nil])
        #expect(ConceptLayout.mentionsNow(of: "", in: [spoken]).isEmpty)
    }
}
