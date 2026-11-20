import Foundation
import Testing
@testable import Ikra

// Çalış sekmesi: "Bugün tekrar et" akışı ve ilerleme özeti.

@Suite @MainActor struct StudyTodayTests {
    @Test func planListsOnlyStepsWithWorkInAFixedOrder() {
        let plan = StudyTodayPlan(counts: [.cards: 5, .mistakes: 0, .probes: 1])
        #expect(plan.steps == [.cards, .probes])
        #expect(plan.total == 6)
        #expect(StudyTodayPlan().steps.isEmpty && StudyTodayPlan().total == 0)
        #expect(StudyTodayPlan.Step.cards.detail(3).contains("3 kart"))
    }

    @Test func flowMovesToTheNextUnvisitedStepThatStillHasWork() {
        let plan = StudyTodayPlan(counts: [.cards: 5, .mistakes: 2, .probes: 1])
        #expect(plan.next(visited: [], remaining: plan) == .cards)
        // Kartlar bitti: sıradaki yanlış defteri.
        var now = StudyTodayPlan(counts: [.cards: 0, .mistakes: 2, .probes: 1])
        #expect(plan.next(visited: [.cards], remaining: now) == .mistakes)
        // Kartlar yarım bırakıldıysa bu oturumda ona dönülmez; sıradaki adıma geçilir.
        now = StudyTodayPlan(counts: [.cards: 3, .mistakes: 2, .probes: 1])
        #expect(plan.next(visited: [.cards], remaining: now) == .mistakes)
        // İşi kalmayan adım atlanır; hepsi açıldıysa akış biter.
        now = StudyTodayPlan(counts: [.cards: 3, .mistakes: 0, .probes: 1])
        #expect(plan.next(visited: [.cards], remaining: now) == .probes)
        #expect(plan.next(visited: [.cards, .mistakes, .probes], remaining: now) == nil)
    }

    @Test func streakAndWeeklyMinutesFollowTheCalendar() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 9))!
        func key(_ back: Int) -> String { ListeningDay.key(for: calendar.date(byAdding: .day, value: -back, to: now)!) }
        // Bugün henüz çalışılmadı; dün ve önceki iki gün çalışıldı, dördüncü gün boş.
        var seconds = [key(1): 600.0, key(2): 120, key(3): 60, key(5): 3000]
        #expect(StudyProgress.streak(seconds, now: now, calendar: calendar) == 3)
        #expect(StudyProgress.weekMinutes(seconds, now: now, calendar: calendar) == 63)
        // Bugün de çalışılınca seri bugünden sayılır.
        seconds[key(0)] = 90
        #expect(StudyProgress.streak(seconds, now: now, calendar: calendar) == 4)
        // Bir dakikadan kısa gün seriyi sürdürmez.
        #expect(StudyProgress.streak([key(0): 30, key(1): 20], now: now, calendar: calendar) == 0)
        #expect(StudyProgress.streak([:], now: now, calendar: calendar) == 0 && StudyProgress.weekMinutes([:], now: now, calendar: calendar) == 0)
    }

    @Test func courseRowsAverageProgressAndPutWaitingCardsFirst() {
        let bio = UUID(), math = UUID(), empty = UUID()
        let a = UUID(), b = UUID(), c = UUID(), loose = UUID()
        let items = [StudyProgress.Item(id: a, courseID: bio, fraction: 1.4), StudyProgress.Item(id: b, courseID: bio, fraction: 0.5),
                     StudyProgress.Item(id: c, courseID: math, fraction: 0.25), StudyProgress.Item(id: loose, courseID: nil, fraction: 1)]
        let rows = StudyProgress.courses([(id: math, name: "Matematik", colorHex: "#111111"), (id: bio, name: "Biyoloji", colorHex: "#222222"), (id: empty, name: "Boş ders", colorHex: "#333333")],
                                         items: items, dueCardItems: [b, b, loose])
        // İçeriği olmayan ders listelenmez; tekrar bekleyen kartı olan ders üstte. Taşan oran %100'e kırpılır.
        #expect(rows.map(\.name) == ["Biyoloji", "Matematik"])
        #expect(rows[0].percent == 75 && rows[0].items == 2 && rows[0].dueCards == 2)
        #expect(rows[1].percent == 25 && rows[1].dueCards == 0)
        #expect(StudyProgress.courses([], items: items, dueCardItems: []).isEmpty)
    }
}
