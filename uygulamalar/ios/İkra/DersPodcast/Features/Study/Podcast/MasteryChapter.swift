import Foundation
import SwiftData

/// #35: konu (bölüm içi konu) ustalığı. Son denemeler (yeniden eskiye ağırlıklı) ve o konunun kartları birleşir.
extension Mastery {
    static func chapterScore(episodeID: UUID, chapter: Int, context: ModelContext) -> Double? {
        let optional: UUID? = episodeID
        let attempts = ((try? context.fetch(FetchDescriptor<RecallAttempt>(predicate: #Predicate { $0.episodeID == optional }))) ?? [])
            .filter { $0.chapterIndex == chapter }
            .map { (date: $0.createdAt, value: $0.score ?? $0.isCorrect.map { $0 ? 1.0 : 0.0 }) }
        let id = episodeID
        let cards = ((try? context.fetch(FetchDescriptor<ReviewCard>(predicate: #Predicate { $0.episodeID == id }))) ?? [])
            .filter { $0.chapterIndex == chapter }
            .map { card -> Double in
                if card.isWeak { return 0.2 }
                if let p = card.recallProbability() { return p }
                return card.repetitions >= 1 ? 0.6 : 0.3
            }
        return combine(attempts: attempts, cards: cards)
    }

    /// Denemeler: son 20, en yeni ağırlık 1, her eski adımda ×0,9. İkisi de varsa %60 deneme, %40 kart.
    nonisolated static func combine(attempts: [(date: Date, value: Double?)], cards: [Double]) -> Double? {
        let scored = attempts.compactMap { a in a.value.map { (a.date, $0) } }.sorted { $0.0 > $1.0 }.prefix(20)
        var attemptScore: Double?
        if !scored.isEmpty {
            var total = 0.0, weights = 0.0, w = 1.0
            for (_, value) in scored {
                total += value * w
                weights += w
                w *= 0.9
            }
            attemptScore = total / weights
        }
        let cardScore = cards.isEmpty ? nil : cards.reduce(0, +) / Double(cards.count)
        switch (attemptScore, cardScore) {
        case let (a?, c?): return 0.6 * a + 0.4 * c
        case let (a?, nil): return a
        case let (nil, c?): return c
        default: return nil
        }
    }
}
