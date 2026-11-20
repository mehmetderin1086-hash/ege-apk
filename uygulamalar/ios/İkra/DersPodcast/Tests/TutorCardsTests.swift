import Foundation
import SwiftData
import Testing
@testable import Ikra

@Suite struct TutorCardsTests {
    private func response(_ count: Int = 5) throws -> String {
        let cards = (0..<count).map { ["front": " Soru \($0) 🧬 ", "back": " Cevap \($0) "] }
        return String(decoding: try JSONSerialization.data(withJSONObject: ["cards": cards]), as: UTF8.self)
    }
    @Test func parsesCardsAndFencedJSON() throws {
        let cards = try TutorCardParser.parse(response(), expectedCount: 5)
        #expect(cards.count == 5 && cards[0].front == "Soru 0 🧬" && cards[0].back == "Cevap 0")
        #expect(Set(cards.map(\.id)).count == 5)
        #expect(try TutorCardParser.parse("```json\n\(response())\n```", expectedCount: 5).count == 5)
    }
    @Test func rejectsWrongCountInvalidAndBlankCards() throws {
        #expect(throws: TutorCardParser.Problem.count) { try TutorCardParser.parse(response(), expectedCount: 6) }
        #expect(throws: TutorCardParser.Problem.count) { try TutorCardParser.parse(response(), expectedCount: 21) }
        #expect(throws: TutorCardParser.Problem.malformed) { try TutorCardParser.parse("not json", expectedCount: 5) }
        var cards = (0..<5).map { ["front": "soru \($0)", "back": "yanıt"] }
        cards[2]["back"] = " \n "
        let data = try JSONSerialization.data(withJSONObject: ["cards": cards])
        #expect(throws: TutorCardParser.Problem.empty) { try TutorCardParser.parse(String(decoding: data, as: UTF8.self), expectedCount: 5) }
    }
    @Test func rejectsDuplicateQuestionsAndOverlongText() throws {
        var cards = (0..<5).map { ["front": "soru \($0)", "back": "yanıt"] }
        cards[1]["front"] = "SORU   0"
        let duplicate = try JSONSerialization.data(withJSONObject: ["cards": cards])
        #expect(throws: TutorCardParser.Problem.duplicate) { try TutorCardParser.parse(String(decoding: duplicate, as: UTF8.self), expectedCount: 5) }
        cards[1]["front"] = String(repeating: "a", count: 1_001)
        let long = try JSONSerialization.data(withJSONObject: ["cards": cards])
        #expect(throws: TutorCardParser.Problem.tooLong) { try TutorCardParser.parse(String(decoding: long, as: UTF8.self), expectedCount: 5) }
    }
    @MainActor @Test func importsOncePreservingDeckAndPendingChanges() throws {
        let container = try ModelContainer(for: ReviewCard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(ReviewCard(episodeID: UUID(), episodeTitle: "Bekleyen", kind: .flashcard, front: "s", back: "c", sourcePage: nil))
        let deck = TutorDeck(title: "Hücre kaynağı", subject: "Biyoloji", cards: try TutorCardParser.parse(response(), expectedCount: 5))
        #expect(try TutorCardWriter.save(deck, context: context) == 5)
        #expect(try TutorCardWriter.save(deck, context: context) == 0)
        let saved = try ModelContext(container).fetch(FetchDescriptor<ReviewCard>())
        #expect(saved.count == 5)
        #expect(saved.allSatisfy { $0.episodeID == deck.id && $0.episodeTitle == deck.title && $0.origin == "tutor" && $0.sourceBookID == nil })
        #expect(context.hasChanges)
    }
}
