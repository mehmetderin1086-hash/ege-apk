import Foundation
import Testing
@testable import Ikra

struct TutorWrittenExamTests {
    @Test func extractsFencedJSONWithBracesAndEscapes() throws {
        let text = #"Örnek: ```json {"questions":["{x} kümesini açıkla.","\"Hız\" nedir?","İvmeyi tanımla."]} ```"#
        let result = try TutorWrittenLogic.questions(from: text, count: 3)
        #expect(result.count == 3)
        #expect(result[0] == "{x} kümesini açıkla.")
        #expect(result[1] == "\"Hız\" nedir?")
    }
    @Test func rejectsMissingDuplicateEmptyAndOversizedQuestions() {
        for text in [#"{"questions":["A","B"]}"#,
                     #"{"questions":["A","a","B"]}"#,
                     #"{"questions":["A"," ","B"]}"#,
                     "{\"questions\":[\"A\",\"B\",\"\(String(repeating: "x", count: 501))\"]}",
                     "Sorular: 1. A 2. B 3. C"] {
            #expect(throws: (any Error).self) { try TutorWrittenLogic.questions(from: text, count: 3) }
        }
    }
    @Test func restoredDeadlineDoesNotRestartTimer() throws {
        let end = Date(timeIntervalSince1970: 1_000)
        let draft = TutorWrittenDraft(subject: "Fizik", level: "TYT", topic: "Hareket", minutes: 5,
                                      questions: ["A", "B", "C"], answers: ["Cevabım", "", ""], deadline: end)
        let restored = try JSONDecoder().decode(TutorWrittenDraft.self, from: JSONEncoder().encode(draft))
        #expect(restored.answers[0] == "Cevabım")
        #expect(restored.remaining(at: end.addingTimeInterval(-0.5)) == 1)
        #expect(!restored.isExpired(at: end.addingTimeInterval(-1)))
        #expect(restored.isExpired(at: end))
        #expect(restored.remaining(at: end.addingTimeInterval(30)) == 0)
    }
    @Test func rubricRejectsMismatchedTotalsAndDuplicateCriterionIDs() throws {
        let good = #"{"rubrics":[{"question":1,"criteria":[{"id":"a","title":"Kavram","points":100}]},{"question":2,"criteria":[{"id":"a","title":"Kavram","points":100}]},{"question":3,"criteria":[{"id":"a","title":"Kavram","points":100}]}]}"#
        #expect(try TutorWrittenRubricLogic.rubrics(from: good, count: 3).count == 3)
        #expect(throws: (any Error).self) { try TutorWrittenRubricLogic.rubrics(from: good.replacingOccurrences(of: "100", with: "90"), count: 3) }
        #expect(throws: (any Error).self) { try TutorWrittenRubricLogic.rubrics(from: good.replacingOccurrences(of: "100", with: String(Int.max)), count: 3) }
        let duplicate = good.replacingOccurrences(of: #"{"id":"a","title":"Kavram","points":100}"#, with: #"{"id":"a","title":"Kavram","points":50},{"id":"a","title":"Yöntem","points":50}"#)
        #expect(throws: (any Error).self) { try TutorWrittenRubricLogic.rubrics(from: duplicate, count: 3) }
    }
    @Test func gradeRequiresActualAnswerQuotesAndPreservesManualRevisionHistory() throws {
        let rubric = [TutorWrittenRubric(question: 1, criteria: [.init(id: "concept", title: "Kavram", points: 100)])]
        let text = #"{"answers":[{"question":1,"criteria":[{"id":"concept","earned":60,"quote":"hücre zarı","explanation":"Kavram belirtilmiş, görevi eksik."}],"example":"Hücre zarı seçici geçirgendir."}]}"#
        var grade = try TutorWrittenRubricLogic.grade(from: text, rubrics: rubric, answers: ["hücre zarı"])
        #expect(grade.total(questionCount: 1) == 60)
        #expect(throws: (any Error).self) { try TutorWrittenRubricLogic.grade(from: text, rubrics: rubric, answers: [""]) }
        #expect(throws: (any Error).self) { try TutorWrittenRubricLogic.grade(from: text, rubrics: rubric, answers: ["başka cevap"]) }
        #expect(throws: (any Error).self) { try grade.revise(question: 1, criterion: "concept", earned: 80, reason: "", rubrics: rubric) }
        try grade.revise(question: 1, criterion: "concept", earned: 80, reason: "Kısmi kazanım daha fazla puanı karşılıyor", rubrics: rubric)
        #expect(grade.answers[0].criteria[0].earned == 60)
        #expect(grade.total(questionCount: 1) == 80 && grade.revisions[0].previous == 60)
        try grade.revise(question: 1, criterion: "concept", earned: 70, reason: "İkinci inceleme", rubrics: rubric)
        #expect(grade.revisions[1].previous == 80 && grade.total(questionCount: 1) == 70)
        let restored = try JSONDecoder().decode(TutorWrittenGrade.self, from: JSONEncoder().encode(grade))
        #expect(restored.revisions.count == 2 && restored.total(questionCount: 1) == 70)
    }
    @Test func blankAnswerCannotReceivePointsAndModelCannotInventCriterion() {
        let rubric = [TutorWrittenRubric(question: 1, criteria: [.init(id: "concept", title: "Kavram", points: 100)])]
        let text = #"{"answers":[{"question":1,"criteria":[{"id":"concept","earned":0,"quote":"","explanation":"Boş cevap."}],"example":"Örnek"}]}"#
        #expect(throws: Never.self) { try TutorWrittenRubricLogic.grade(from: text, rubrics: rubric, answers: [""]) }
        #expect(throws: (any Error).self) { try TutorWrittenRubricLogic.grade(from: text.replacingOccurrences(of: "concept", with: "invented"), rubrics: rubric, answers: [""]) }
        #expect(throws: (any Error).self) { try TutorWrittenRubricLogic.grade(from: text.replacingOccurrences(of: #""earned":0"#, with: #""earned":1"#), rubrics: rubric, answers: [""]) }
    }
}
