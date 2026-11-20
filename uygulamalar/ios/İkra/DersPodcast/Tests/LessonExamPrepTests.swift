import Foundation
import Testing
@testable import Ikra

// YouTube dersleri: "Yazılıya hazırlan" soru provası ve sade sekme sırası.

@Suite @MainActor struct LessonExamPrepTests {
    @Test func practiceWalksThroughQuestionsAndCollectsMissedOnes() {
        var session = ExamPrepSession(count: 3)
        #expect(session.current == 0 && session.progress == "1 / 3" && !session.finished)
        session.revealed = true
        session.answer(knew: true)
        // Sonraki soruda cevap yeniden kapalı gelir.
        #expect(session.current == 1 && !session.revealed)
        session.answer(knew: false); session.answer(knew: false)
        #expect(session.finished && session.current == nil && session.known == [0] && session.missed == [1, 2])
        // Bittikten sonra yanıt sayılmaz.
        session.answer(knew: true)
        #expect(session.known == [0])
        // İkinci tur yalnız bilinemeyenleri sorar.
        session.retryMissed()
        #expect(session.current == 1 && session.progress == "1 / 2" && session.missed.isEmpty)
        session.answer(knew: true); session.answer(knew: true)
        #expect(session.finished && session.known == [1, 2] && session.missed.isEmpty)
        session.retryMissed()
        #expect(session.finished)
    }

    @Test func emptyLessonHasNothingToPractise() {
        var session = ExamPrepSession(count: 0)
        #expect(session.finished && session.current == nil)
        session.answer(knew: false)
        #expect(session.missed.isEmpty)
        #expect(ExamPrepSession(count: -4).finished)
    }

    @Test func summaryTabComesFirstAndKeepsItsStoredName() {
        #expect(LessonTab.allCases.map(\.title) == ["Özet", "Metin", "Bölümler", "Sor", "Kareler"])
        // Kayıtlı ve hata ayıklama adları değişmedi.
        #expect(LessonTab(rawValue: "notes") == .notes && LessonTab(rawValue: "transcript") == .transcript)
    }
}
