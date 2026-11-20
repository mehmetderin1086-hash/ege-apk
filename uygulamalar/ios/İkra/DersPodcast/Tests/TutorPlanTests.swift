import Foundation
import Testing
@testable import Ikra

struct TutorPlanTests {
    @Test func rejectsInvalidDatesTasksAndDailyBudgets() {
        let cases = [
            #"{"days":[{"date":"2030-01-02","tasks":[{"title":"A","minutes":5}]}]}"#,
            #"{"days":[{"date":"2030-01-01","tasks":[{"title":"A","minutes":0}]}]}"#,
            #"{"days":[{"date":"2030-01-01","tasks":[{"title":"A","minutes":20},{"title":"B","minutes":11}]}]}"#,
            #"{"days":[{"date":"2030-01-01","tasks":[{"title":" ","minutes":5}]}]}"#,
            #"{"days":[{"date":"2030-01-01","tasks":[]},{"date":"2030-01-01","tasks":[]}]}"#,
            #"{"days":[]}"#
        ]
        for value in cases {
            #expect(throws: (any Error).self) { try TutorPlanLogic.parse(value, allowedDates: ["2030-01-01"], budget: 30) }
        }
    }
    @Test func acceptsExactBudgetAndPreservesCompletion() throws {
        let input = #"{"days":[{"date":"2030-01-01","tasks":[{"title":"Konu tekrarı","minutes":20},{"title":"Soru çözümü","minutes":10}]}]}"#
        var days = try TutorPlanLogic.parse(input, allowedDates: ["2030-01-01"], budget: 30)
        #expect(days[0].tasks.reduce(0) { $0 + $1.minutes } == 30)
        days[0].tasks[0].completed = true
        let plan = TutorSavedPlan(subject: "Biyoloji", topics: "Hücre", examDate: "2030-01-03", dailyMinutes: 30, target: "80", days: days)
        let restored = try JSONDecoder().decode(TutorSavedPlan.self, from: JSONEncoder().encode(plan))
        #expect(restored.days[0].tasks[0].completed)
        #expect(restored.days[0].tasks[0].id == days[0].tasks[0].id)
    }
    @Test func datesStopAtExamAndSevenDaysAcrossMonthBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2030, month: 1, day: 30))!
        let soon = calendar.date(from: DateComponents(year: 2030, month: 2, day: 1))!
        #expect(TutorPlanLogic.allowedDates(now: now, exam: soon, calendar: calendar) == ["2030-01-30", "2030-01-31", "2030-02-01"])
        #expect(TutorPlanLogic.allowedDates(now: now, exam: now.addingTimeInterval(86400 * 20), calendar: calendar).count == 7)
        #expect(TutorPlanLogic.allowedDates(now: now, exam: now.addingTimeInterval(-86400), calendar: calendar).isEmpty)
    }
    @Test func archivePlanLinksRealRevisionsAndRespectsRoundedDailyBudget() throws {
        var entries: [QSEntry] = []
        for i in 1...10 {
            var q = QSQuestion.blank; q.number = String(i); q.subject = "Biyoloji"; q.topic = "Hücre"; q.text = "Hücre zarını açıkla."
            var e = QSEntry(question: q); e.attempts = [.init(answer: "x", revision: 1, elapsedSeconds: 70, correct: true)]
            entries.append(e)
        }
        entries[1].origin = .init(parent: entries[0].id, kind: "similar")
        let days = try TutorPlanLogic.archiveDays(entries: entries, dates: ["2030-01-01", "2030-01-02"], budget: 5, subject: "Biyoloji", topics: "Hücre")
        #expect(days.allSatisfy { $0.tasks.reduce(0) { $0 + $1.minutes } <= 5 })
        let ids = days.flatMap(\.tasks).compactMap(\.questionID)
        #expect(Set(ids).count == ids.count)
        #expect(!(ids.contains(entries[0].id) && ids.contains(entries[1].id)))
        #expect(days.flatMap(\.tasks).allSatisfy { $0.questionRevision == 1 && $0.timingSamples == 1 })
        #expect(ids.allSatisfy { id in entries.contains { $0.id == id } })
    }
    @Test func planCanLinkExistingCardsWithoutInventingQuestionIDs() throws {
        let deck = TutorDeck(title: "Hücre", subject: "Biyoloji", cards: [.init(front: "Zar?", back: "Seçici geçirgen")])
        let days = try TutorPlanLogic.archiveDays(entries: [], dates: ["2030-01-01"], budget: 5, subject: "Biyoloji", topics: "Hücre", decks: [deck])
        #expect(days[0].tasks.count == 1 && days[0].tasks[0].deckID == deck.id)
        #expect(days[0].tasks[0].questionID == nil && days[0].tasks[0].timingSamples == 0)
        #expect(days[0].tasks[0].minutes == 1)
    }
    @Test func reschedulingKeepsCompletedWorkAndExposesOverflowInsteadOfDroppingIt() throws {
        let done = TutorPlanTask(title: "Bitti", minutes: 3, completed: true)
        let missed = TutorPlanTask(title: "Kaçırılan", minutes: 4)
        let large = TutorPlanTask(title: "Uzun iş", minutes: 8)
        let plan = TutorSavedPlan(subject: "Matematik", topics: "Denklemler", examDate: "2030-01-03", dailyMinutes: 5, target: "80", days: [
            .init(date: "2030-01-01", tasks: [done, missed, large])])
        let updated = try TutorPlanLogic.rescheduled(plan, dates: ["2030-01-02", "2030-01-03"], entries: [])
        #expect(updated.days.first?.tasks.first?.id == done.id && updated.days.first?.tasks.first?.completed == true)
        #expect(updated.days.first { $0.date == "2030-01-02" }?.tasks.first?.id == missed.id)
        #expect(updated.backlog?.map(\.id) == [large.id])
        #expect(updated.days.filter { $0.date >= "2030-01-02" }.allSatisfy { $0.tasks.reduce(0) { $0 + $1.minutes } <= 5 })
        let again = try TutorPlanLogic.rescheduled(updated, dates: ["2030-01-02", "2030-01-03"], entries: [])
        #expect(again.days.flatMap(\.tasks).map(\.id) == updated.days.flatMap(\.tasks).map(\.id))
        #expect(again.backlog?.map(\.id) == [large.id])
    }
    @Test func completedQuestionRevisionIsNotPlannedAgainButNewRevisionCanBe() throws {
        var first = QSQuestion.blank; first.subject = "Biyoloji"; first.topic = "Hücre"; first.text = "Hücre?"
        var next = first; next.id = UUID().uuidString
        let completed = Set(["question:" + first.id + ":r1"])
        let days = try TutorPlanLogic.archiveDays(entries: [.init(question: first), .init(question: next)], dates: ["2030-01-01"], budget: 10, subject: "Biyoloji", topics: "Hücre", completed: completed)
        #expect(days.flatMap(\.tasks).compactMap(\.questionID) == [next.id])
        first.revision = 2
        let revised = try TutorPlanLogic.archiveDays(entries: [.init(question: first)], dates: ["2030-01-01"], budget: 10, subject: "Biyoloji", topics: "Hücre", completed: completed)
        #expect(revised[0].tasks[0].questionRevision == 2)
    }
}
