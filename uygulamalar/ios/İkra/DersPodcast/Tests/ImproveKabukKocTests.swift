import Foundation
import Testing
@testable import Ikra

/// Kabuk + Koç, dalga 1: Derslerim metinleri ve hatırlatma zamanı, sunucu durumu tazeliği,
/// Koç görevlerinin kendiliğinden tamamlanması, gün değişimi, plan kaydı ve bildirim penceresi.
@MainActor
@Suite struct ImproveKabukKocTests {
    // MARK: - Yardımcılar

    /// Sabit takvim: Türkçe kısaltmalar ("Cum", "Eki") ve İstanbul saati; cihaz ayarından bağımsız.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "tr_TR")
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul") ?? .gmt
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    /// 6 Ekim 2026 Salı, 10:00.
    private var now: Date { date(2026, 10, 6, 10) }

    // MARK: - Madde 1: son tarih metni, renk adı

    @Test func assignmentDueTextSaysDirection() {
        #expect(AssignmentDue.text(due: date(2026, 10, 6, 17), now: now, calendar: calendar) == "Bugün 17:00")
        #expect(AssignmentDue.text(due: date(2026, 10, 7, 9), now: now, calendar: calendar) == "Yarın 09:00")
        #expect(AssignmentDue.text(due: date(2026, 10, 9), now: now, calendar: calendar) == "3 gün kaldı · Cum")
        #expect(AssignmentDue.text(due: date(2026, 10, 5), now: now, calendar: calendar) == "1 gün gecikti")
        #expect(AssignmentDue.text(due: date(2026, 10, 4), now: now, calendar: calendar) == "2 gün gecikti")
        #expect(AssignmentDue.text(due: date(2026, 10, 20, 9), now: now, calendar: calendar) == "20 Eki · 14 gün kaldı")
    }

    @Test func assignmentDueCountsCalendarDaysNotHours() {
        // Bugün saati geçmiş ödev "gecikti" değil, hâlâ bugündür; yarın 00:30 ise 14 saat sonra bile "Yarın"dır.
        #expect(AssignmentDue.text(due: date(2026, 10, 6, 8, 30), now: now, calendar: calendar) == "Bugün 08:30")
        #expect(AssignmentDue.text(due: date(2026, 10, 7, 0, 30), now: now, calendar: calendar) == "Yarın 00:30")
        #expect(AssignmentDue.text(due: date(2026, 10, 12, 23, 59), now: now, calendar: calendar) == "6 gün kaldı · Pzt")
        #expect(AssignmentDue.text(due: date(2026, 10, 13), now: now, calendar: calendar) == "13 Eki · 7 gün kaldı")
    }

    @Test func finishedAssignmentShowsOnlyTheDate() {
        #expect(AssignmentDue.dateText(due: date(2026, 10, 14, 9), now: now, calendar: calendar) == "14 Eki")
        #expect(AssignmentDue.dateText(due: date(2025, 12, 3), now: now, calendar: calendar) == "3 Ara 2025")
    }

    @Test func everyPaletteColorHasAName() {
        #expect(Course.paletteNames.count == Course.palette.count)
        #expect(Set(Course.palette.map { Course.colorName($0) }).count == Course.palette.count)
        #expect(Course.colorName("#6B4CF2") == "Mor")
        #expect(Course.colorName("#f2b705") == "Sarı")
        #expect(Course.colorName("#123456") == "Renk")
    }

    // MARK: - Madde 6: ders silme onayı, hatırlatma

    @Test func courseDeletionSummaryListsWhatIsLost() {
        #expect(CourseDeletion.summary(lessons: 3, assignments: 2, videos: 1) == "3 program saati silinir; 2 ödev/sınav ve 1 video derssiz kalır.")
        #expect(CourseDeletion.summary(lessons: 0, assignments: 1, videos: 0) == "1 ödev/sınav derssiz kalır.")
        #expect(CourseDeletion.summary(lessons: 2, assignments: 0, videos: 0) == "2 program saati silinir.")
        #expect(CourseDeletion.summary(lessons: 0, assignments: 1, videos: 4, channels: 1) == "1 ödev/sınav, 4 video ve 1 kanal derssiz kalır.")
        #expect(CourseDeletion.summary(lessons: 0, assignments: 0, videos: 0) == "Bu derse bağlı program saati, ödev ya da video yok.")
    }

    @Test func reminderFiresDayBeforeOrTwoHoursBefore() {
        let due = date(2026, 10, 7, 10)
        // Önceki gün 18:00 gelecekte.
        #expect(Reminders.fireDate(due: due, now: date(2026, 10, 6, 12), calendar: calendar) == date(2026, 10, 6, 18))
        // 18:00 geçti: son tarihten 2 saat önce.
        #expect(Reminders.fireDate(due: due, now: date(2026, 10, 6, 19), calendar: calendar) == date(2026, 10, 7, 8))
        // Son tarihe 1 saat kaldı ya da geçti: kurulmaz.
        #expect(Reminders.fireDate(due: due, now: date(2026, 10, 7, 9), calendar: calendar) == nil)
        #expect(Reminders.fireDate(due: due, now: date(2026, 10, 8, 9), calendar: calendar) == nil)
    }

    @Test func reminderTextMatchesTheDayItArrives() {
        let due = date(2026, 10, 7, 10)
        let early = Reminders.content(title: "Türev", isExam: false, courseName: "Matematik", fire: date(2026, 10, 6, 18), due: due, calendar: calendar)
        #expect(early.title == "Yarın teslim: Türev")
        #expect(early.body == "Matematik · Bugün 25 dakikalık bir tekrar yap.")
        let late = Reminders.content(title: "Yazılı", isExam: true, courseName: nil, fire: date(2026, 10, 7, 8), due: due, calendar: calendar)
        #expect(late.title == "Bugün sınav: Yazılı")
        #expect(late.body == "Son tarihe 2 saat kaldı.")
        // Gece yarısından hemen sonraki son tarih: 2 saat önceki bildirim bir önceki güne düşer, "Yarın" denir.
        let midnight = date(2026, 10, 7, 1)
        let fire = Reminders.fireDate(due: midnight, now: date(2026, 10, 6, 19), calendar: calendar)
        #expect(fire == date(2026, 10, 6, 23))
        #expect(Reminders.content(title: "Ödev", isExam: false, courseName: nil, fire: date(2026, 10, 6, 23), due: midnight, calendar: calendar).title == "Yarın teslim: Ödev")
    }

    @Test func reminderNoteExplainsWhenNothingIsScheduled() {
        let due = date(2026, 10, 7, 10)
        #expect(Reminders.note(due: due, now: date(2026, 10, 6, 12), calendar: calendar) == "Bir gün önce 18:00'de hatırlatılır.")
        #expect(Reminders.note(due: due, now: date(2026, 10, 6, 19), calendar: calendar) == "Bir gün öncesi geçti; son tarihten 2 saat önce hatırlatılır.")
        #expect(Reminders.note(due: due, now: date(2026, 10, 7, 9), calendar: calendar) == "Son tarihe 2 saatten az kaldı; hatırlatma kurulmaz.")
        #expect(Reminders.note(due: due, now: date(2026, 10, 7, 11), calendar: calendar) == "Son tarih geçmiş; hatırlatma kurulmaz.")
    }

    @Test func reminderWishSurvivesDoneAndIsForgottenOnDelete() throws {
        let suite = "ImproveKabukKocTests.remind"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = UUID(), b = UUID()
        #expect(!Reminders.isWanted(a, defaults: defaults))
        Reminders.setWanted(a, true, defaults: defaults)
        Reminders.setWanted(b, true, defaults: defaults)
        Reminders.setWanted(a, true, defaults: defaults)   // yinelenen kayıt olmaz
        #expect(Reminders.isWanted(a, defaults: defaults))
        #expect(defaults.stringArray(forKey: Reminders.remindKey)?.count == 2)
        Reminders.setWanted(a, false, defaults: defaults)
        #expect(!Reminders.isWanted(a, defaults: defaults))
        #expect(Reminders.isWanted(b, defaults: defaults))
    }

    // MARK: - Madde 2: sunucu durumu tazeliği

    @Test func statusRefreshesWhenUnknownOrStale() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        // Sunucu bilinmiyor, hiç denenmedi.
        #expect(AppState.shouldRefreshStatus(hasServer: false, lastSuccess: nil, lastAttempt: nil, now: now))
        // Sunucu bilinmiyor ama 3 sn önce denendi: üst üste istek atılmaz.
        #expect(!AppState.shouldRefreshStatus(hasServer: false, lastSuccess: nil, lastAttempt: now.addingTimeInterval(-3), now: now))
        #expect(AppState.shouldRefreshStatus(hasServer: false, lastSuccess: nil, lastAttempt: now.addingTimeInterval(-11), now: now))
        // Sunucu biliniyor: 5 dk taze, 11 dk bayat.
        #expect(!AppState.shouldRefreshStatus(hasServer: true, lastSuccess: now.addingTimeInterval(-300), lastAttempt: now.addingTimeInterval(-300), now: now))
        #expect(AppState.shouldRefreshStatus(hasServer: true, lastSuccess: now.addingTimeInterval(-660), lastAttempt: now.addingTimeInterval(-660), now: now))
        // Bayat ama az önce denenmiş (hata sürüyor): bekler.
        #expect(!AppState.shouldRefreshStatus(hasServer: true, lastSuccess: now.addingTimeInterval(-660), lastAttempt: now.addingTimeInterval(-2), now: now))
    }

    @Test func statusRetryBacksOffAndStaysAtTwoMinutes() {
        #expect((0..<6).map(AppState.statusRetryDelay) == [5, 15, 45, 120, 120, 120])
        #expect(AppState.statusRetryDelay(attempt: -1) == 5)
    }

    // MARK: - Madde 3: kendiliğinden tamamlanan görevler

    // MARK: - Madde 5: gün değişimi

    // MARK: - Madde 4: plan kaydı, düzenlenebilir tarih, bildirim penceresi

    @Test func storingPlanAlsoSetsDailyGoal() throws {
        let suite = "ImproveKabukKocTests.plan"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(45, forKey: StudyPlan.dailyGoalKey)

        StudyPlan.store(StudyPlan(examName: "YKS", examDate: date(2027, 6, 19), dailyMinutes: 90), defaults: defaults)
        #expect(defaults.integer(forKey: "coach.dailyGoalMinutes") == 90)
        let saved = try JSONDecoder().decode(StudyPlan.self, from: #require(defaults.data(forKey: StudyPlan.key)))
        #expect(saved.examName == "YKS")
        #expect(saved.dailyMinutes == 90)
        #expect(saved.examDate == date(2027, 6, 19))

        // Plan kalkınca anahtar silinir; günlük hedef olduğu gibi kalır.
        StudyPlan.store(nil, defaults: defaults)
        #expect(defaults.object(forKey: StudyPlan.key) == nil)
        #expect(defaults.integer(forKey: StudyPlan.dailyGoalKey) == 90)
    }

    @Test func planWrittenBeforeThisChangeStillDecodes() throws {
        // Eski kayıt biçimi (JSONEncoder varsayılanı: tarih, 2001'den beri saniye).
        let json = #"{"examName":"KPSS","examDate":812345678,"dailyMinutes":60}"#
        let plan = try JSONDecoder().decode(StudyPlan.self, from: Data(json.utf8))
        #expect(plan.examName == "KPSS")
        #expect(plan.dailyMinutes == 60)
        #expect(plan.examDate == Date(timeIntervalSinceReferenceDate: 812_345_678))
    }

    @Test func editableDateNeverStartsInThePast() {
        let yesterday = date(2026, 10, 5, 15)
        let later = date(2026, 10, 16, 9)
        #expect(StudyPlan.editableDate(yesterday, now: now, calendar: calendar) == now)
        #expect(StudyPlan.editableDate(later, now: now, calendar: calendar) == later)
        // Bugünün erken saati geçmiş sayılmaz (sınav bugün olabilir).
        #expect(StudyPlan.editableDate(date(2026, 10, 6, 8), now: now, calendar: calendar) == date(2026, 10, 6, 8))
        #expect(StudyPlan.editableDate(nil, now: now, calendar: calendar) == date(2026, 11, 5, 10))
    }

    @Test func notificationPlanSkipsPastMorningAndCapsAtFourteen() {
        let start = date(2026, 10, 6, 9)   // bugünün 08:00'i geçti
        let days = (0..<20).map { offset in
            StudyPlanner.Day(date: calendar.date(byAdding: .day, value: offset, to: start) ?? start, items: ["Dinle: Bölüm \(offset)", "Tekrar"])
        }
        let list = StudyPlanner.notificationPlan(days: days, examName: "YKS", now: start, calendar: calendar)
        #expect(list.count == 14)
        #expect(list.first?.id == "plan-2026-10-07")
        #expect(list.last?.id == "plan-2026-10-20")
        #expect(list.allSatisfy { $0.components.hour == 8 && $0.title == "YKS planı · bugün" })
        #expect(list.first?.body == "Dinle: Bölüm 1 · Tekrar")
        #expect(Set(list.map(\.id)).count == 14)

        // Sabah 07:00'de bugünün bildirimi de kurulur; kısa planda gün sayısı kadar kayıt döner.
        let early = StudyPlanner.notificationPlan(days: Array(days.prefix(3)), examName: "YKS", now: date(2026, 10, 6, 7), calendar: calendar)
        #expect(early.map(\.id) == ["plan-2026-10-06", "plan-2026-10-07", "plan-2026-10-08"])
        #expect(StudyPlanner.notificationPlan(days: [], examName: "YKS", now: start, calendar: calendar).isEmpty)
    }

    // MARK: - Dalga 2 · Madde 7: Koç özeti gövdede ağır iş yapmaz

    // MARK: - Dalga 2 · Madde 8: sınav sonucu ve boş sorular

    @Test func examTallyCountsBlanksWithoutPenalty() {
        let keys = Array(repeating: 1, count: 10)
        // 0–5 doğru, 6–7 yanlış, 8–9 boş.
        var answers: [Int: Int] = [:]
        for index in 0..<6 { answers[index] = 1 }
        answers[6] = 0
        answers[7] = 3
        let score = ExamScore.tally(answers: answers, keys: keys)
        #expect(score.correct == 6)
        #expect(score.wrong == 2)
        #expect(score.blank == 2)
        #expect(score.net == 5.5)

        let empty = ExamScore.tally(answers: [:], keys: keys)
        #expect(empty.correct == 0)
        #expect(empty.wrong == 0)
        #expect(empty.blank == 10)
        #expect(empty.net == 0)

        // Seçimi kaldırmak (anahtarın silinmesi) soruyu yeniden boş yapar: yanlışın götürdüğü çeyrek geri gelir.
        answers[6] = nil
        let cleared = ExamScore.tally(answers: answers, keys: keys)
        #expect(cleared.wrong == 1)
        #expect(cleared.blank == 3)
        #expect(cleared.net == 5.75)
        #expect(ExamScore.tally(answers: [:], keys: []) == ExamScore(correct: 0, wrong: 0, blank: 0))
    }

    /// "İlk boş soruya git" ve bitirme uyarısı ortak `ExamNav` yardımcısına dayanır.
    @Test func firstBlankIsTheEarliestUnanswered() {
        #expect(ExamNav.unanswered(count: 5, answers: [0: 2, 1: 0, 3: 1]).first == 2)
        #expect(ExamNav.unanswered(count: 3, answers: [0: 0, 1: 1, 2: 2]).isEmpty)
        // Seçimi kaldırılan soru yeniden boş sayılır.
        var answers = [0: 0, 1: 1, 2: 2]
        answers[1] = nil
        #expect(ExamNav.unanswered(count: 3, answers: answers) == [1])
    }

    // MARK: - Dalga 2 · Madde 11: plana sığmayan içerik

    @Test func planFitReportsWhatDoesNotReachTheExam() {
        // 20'şer dakikalık 30 bölüm, 8 çalışma günü, günde 45 dk: güne 3 bölüm yerleşir, 6 bölüm kalır.
        // 60 dk ile de güne 3 bölüm (bütçe tam sıfırlanır) yerleşir; 75 dk ile 4.
        let tight = StudyPlanner.fit(remaining: Array(repeating: 20, count: 30), studyDays: 8, dailyMinutes: 45)
        #expect(tight == StudyPlanner.Fit(plannedMinutes: 480, leftoverCount: 6, leftoverMinutes: 120, suggestedDailyMinutes: 75))
        #expect(StudyPlanner.fit(remaining: Array(repeating: 20, count: 30), studyDays: 8, dailyMinutes: 75).leftoverCount == 0)

        #expect(StudyPlanner.fit(remaining: [20, 20], studyDays: 3, dailyMinutes: 45)
                == StudyPlanner.Fit(plannedMinutes: 40, leftoverCount: 0, leftoverMinutes: 0, suggestedDailyMinutes: nil))
        #expect(StudyPlanner.fit(remaining: [], studyDays: 5, dailyMinutes: 45)
                == StudyPlanner.Fit(plannedMinutes: 0, leftoverCount: 0, leftoverMinutes: 0, suggestedDailyMinutes: nil))

        // 240 dk'ya kadar hiçbir günlük süre yetmiyor: öneri yok.
        let hopeless = StudyPlanner.fit(remaining: Array(repeating: 60, count: 100), studyDays: 2, dailyMinutes: 45)
        #expect(hopeless.leftoverCount == 98)
        #expect(hopeless.leftoverMinutes == 98 * 60)
        #expect(hopeless.suggestedDailyMinutes == nil)

        // Sıfır gün ya da sıfır bütçe: hiçbir şey yerleşmez, döngü takılmaz.
        #expect(StudyPlanner.fit(remaining: [10, 10], studyDays: 0, dailyMinutes: 45, maxDaily: 60).leftoverCount == 2)
        #expect(StudyPlanner.fit(remaining: [10], studyDays: 2, dailyMinutes: 0, maxDaily: 0).leftoverCount == 1)
    }

    @Test func dayShareAndStudyDaysMatchThePlanRules() {
        #expect(StudyPlanner.dayShare([20, 20, 20, 20], from: 0, budget: 45) == 3)
        #expect(StudyPlanner.dayShare([20, 20, 20, 20], from: 3, budget: 45) == 1)
        #expect(StudyPlanner.dayShare([20, 20, 20, 20], from: 4, budget: 45) == 0)
        #expect(StudyPlanner.dayShare([90, 10], from: 0, budget: 45) == 1)   // son alınan bütçeyi aşabilir
        #expect(StudyPlanner.dayShare([20], from: 0, budget: 0) == 0)
        #expect([0, 1, 4, 10, 100].map { StudyPlanner.studyDays(daysLeft: $0) } == [1, 1, 3, 8, 97])
    }

    @Test func planDaysAreDistributedAsBefore() {
        let episodes = (0..<5).map { index -> Episode in
            let script = PodcastScript(title: "Bölüm \(index)", summary: "", keyPoints: [], chapters: [], sourceNotes: "")
            let episode = Episode(script: script, settings: PodcastSettings(), sourceNames: [], jobToken: "")
            episode.status = .ready
            episode.duration = 20 * 60
            episode.createdAt = now.addingTimeInterval(Double(index))
            return episode
        }
        let exam = Calendar.current.date(byAdding: .day, value: 12, to: .now) ?? .now
        let days = StudyPlanner.days(plan: StudyPlan(examName: "YKS", examDate: exam, dailyMinutes: 45), episodes: episodes, dueCards: 2)
        #expect(days.count == 12)
        #expect(days[0].items == ["Dinle: Bölüm 0 (20 dk)", "Dinle: Bölüm 1 (20 dk)", "Dinle: Bölüm 2 (20 dk)", "Tekrar: 2 kart"])
        #expect(days[1].items == ["Dinle: Bölüm 3 (20 dk)", "Dinle: Bölüm 4 (20 dk)", "Tekrar: günlük kartlar"])
        #expect(days[2].items == ["Tekrar: günlük kartlar"])
        #expect(days[11].items.first == "Sınav simülasyonu (karışık, süreli)")
        // Ekranın sığma özeti aynı kuyruk ve gün sayısından çıkar.
        let fit = StudyPlanner.fit(remaining: StudyPlanner.queue(episodes).map { $0.minutes },
                                   studyDays: StudyPlanner.studyDays(daysLeft: 12), dailyMinutes: 45)
        #expect(fit == StudyPlanner.Fit(plannedMinutes: 100, leftoverCount: 0, leftoverMinutes: 0, suggestedDailyMinutes: nil))
    }

    // MARK: - İnceleme · Bulgu 1: sesli koçta `busy` yalnız isteği kapsar

    /// Akışın bir sonraki işaretini bekler; akış işaret vermeden biterse de döner (sınama asılı kalmasın).
    private static func signal(_ stream: AsyncStream<Void>) async {
        for await _ in stream { return }
    }

    // MARK: - İnceleme · Bulgu 2: iptal, sunucu afişine hata diye yazılmaz

    @Test func cancelledStatusRequestIsNotAnError() {
        #expect(AppState.statusFailureMessage(CancellationError()) == nil)
        #expect(AppState.statusFailureMessage(APIError(status: 401, code: "unauthorized", message: "Anahtar geçersiz.")) == "Anahtar geçersiz.")
        #expect(AppState.statusFailureMessage(APIError.network(URLError(.timedOut))) == "Sunucu zamanında yanıt vermedi. Lütfen tekrar dene.")
        let other = URLError(.badURL)
        #expect(AppState.statusFailureMessage(other) == other.localizedDescription)
    }

    // MARK: - İnceleme · Bulgu 3: bir gün gecikme de "gecikti" der

    @Test func everyOverdueDaySaysLate() {
        // Dünün başı da sonu da bir takvim günü gecikmedir.
        #expect(AssignmentDue.text(due: date(2026, 10, 5, 23, 59), now: now, calendar: calendar) == "1 gün gecikti")
        #expect(AssignmentDue.text(due: date(2026, 10, 5, 0, 0), now: now, calendar: calendar) == "1 gün gecikti")
        for daysLate in 1...9 {
            let due = calendar.date(byAdding: .day, value: -daysLate, to: now) ?? now
            #expect(AssignmentDue.text(due: due, now: now, calendar: calendar) == "\(daysLate) gün gecikti")
        }
    }
}
