import XCTest
@testable import BilgiArena

final class QuizTests: XCTestCase {
    func question() -> Question { Question(text: "Hangi gezegen kızıldır?", options: ["Mars", "Venüs", "Dünya", "Jüpiter"], answer: 0, explanation: "Mars kırmızı gezegen olarak bilinir.", category: .science, difficulty: .easy) }
    func testAnswerLocksAndScoringIsIdempotent() {
        var round = Round(questions: [question()], source: "test")
        round.answer(0); round.answer(1)
        XCTAssertEqual(round.answers.count, 1)
        XCTAssertEqual(round.score, 200)
        round.next(); XCTAssertTrue(round.finished)
    }
    func testTimeoutPauseAndJokers() {
        var round = Round(questions: [question()], source: "test")
        round.paused = true; round.tick(); XCTAssertEqual(round.remaining, 10)
        round.paused = false; round.half()
        XCTAssertEqual(round.eliminated.count, 2); XCTAssertFalse(round.eliminated.contains(0))
        round.moreTime(); round.moreTime(); XCTAssertEqual(round.remaining, 25)
        for _ in 0..<25 { round.tick() }
        XCTAssertTrue(round.revealed); XCTAssertNil(round.answers.first?.chosen)
    }
    func testJSONValidationAndFences() throws {
        let q = question()
        let data = try JSONEncoder().encode(["questions": [q]])
        let wrapped = "```json\n" + String(decoding: data, as: UTF8.self) + "\n```"
        XCTAssertEqual(try Question.decode(wrapped, expectedCount: 1), [q])
        let invalid = "{\"questions\":[{\"text\":\"Soru nedir?\",\"options\":[\"A\",\"A\",\"C\",\"D\"],\"answer\":5,\"explanation\":\"Yeterince uzun açıklama\",\"category\":\"Bilim\",\"difficulty\":\"Kolay\"}]}"
        XCTAssertThrowsError(try Question.decode(invalid, expectedCount: 1))
    }
    func testPhoneNetworkRejectsVPSAndRedirectDestinations() {
        XCTAssertFalse(PhonePolicy.allows(URL(string: "https://82.29.179.131/v1")))
        XCTAssertFalse(PhonePolicy.allows(URL(string: "https://custom.example.com/v1")))
        XCTAssertFalse(PhonePolicy.allows(URL(string: "http://api.openai.com/v1")))
        XCTAssertFalse(PhonePolicy.allows(URL(string: "https://api.openai.com.attacker.com/v1")))
        XCTAssertTrue(PhonePolicy.allows(URL(string: "https://api.anthropic.com/v1/messages")))
        XCTAssertTrue(PhonePolicy.allows(URL(string: "https://chatgpt.com/backend-api/codex/responses")))
    }
    func testTrainingNeverTimesOutAndSprintResetsToSeven() {
        var training = Round(questions: [question()], source: "test", mode: .training)
        for _ in 0..<100 { training.tick() }
        XCTAssertFalse(training.revealed)
        var sprint = Round(questions: [question(), question()], source: "test", mode: .sprint)
        XCTAssertEqual(sprint.remaining, 7)
        sprint.answer(0); sprint.next(); XCTAssertEqual(sprint.remaining, 7)
    }
    func testSpacedReviewExtendsIntervalAndFailureResets() {
        let now = Date()
        var card = ReviewCard(question: question(), due: now, interval: 1, attempts: 1, correct: 0)
        card.record(true, now: now); XCTAssertEqual(card.interval, 2)
        card.record(true, now: now); XCTAssertEqual(card.interval, 4)
        card.record(false, now: now); XCTAssertEqual(card.interval, 1)
    }
    func testDailyQuestionsAreStableAndUnique() {
        let day = Date(timeIntervalSince1970: 1_792_000_000)
        let a = Seed.questions.daily(date: day)
        XCTAssertEqual(a.map(\.id), Seed.questions.daily(date: day).map(\.id))
        XCTAssertEqual(Set(a.map(\.id)).count, 10)
    }
    func testSeedQuestionsAreSound() {
        XCTAssertEqual(Seed.questions.count, 174)
        XCTAssertEqual(Set(Seed.questions.map { QuestionSimilarity.fingerprint($0.text) }).count,174)
        for q in Seed.questions { XCTAssertTrue(q.isWellFormed) }
        for topic in DailyPoolPlan.categories {
            for difficulty in Difficulty.allCases { XCTAssertFalse(Seed.questions.filter { $0.category == topic && $0.difficulty == difficulty }.isEmpty) }
        }
    }
}
