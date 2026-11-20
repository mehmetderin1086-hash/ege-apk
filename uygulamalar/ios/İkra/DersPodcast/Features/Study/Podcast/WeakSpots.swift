import Foundation
import SwiftData

/// #22: zayıf yerler. Anı bilinen zayıf kartlar ve açık podcast yanlışları çalınacak kesitlere dönüşür.
enum WeakSpots {
    static func clips(context: ModelContext, limit: Int) -> [PodcastClip] {
        let episodes = ((try? context.fetch(FetchDescriptor<Episode>())) ?? []).filter { $0.status == .ready }
        let durations = Dictionary(episodes.map { ($0.id, $0.duration) }, uniquingKeysWith: { a, _ in a })
        var candidates: [(date: Date, clip: PodcastClip)] = []
        for card in (try? context.fetch(FetchDescriptor<ReviewCard>())) ?? [] where card.isWeak {
            guard let time = card.episodeTime, let duration = durations[card.episodeID] else { continue }
            candidates.append((card.lastLapseAt ?? card.lastReviewed ?? card.createdAt,
                               clip(card.episodeID, time, duration, reason: "Zayıf kart: \(card.front.prefix(80))", key: card.front)))
        }
        let mistakes = (try? context.fetch(FetchDescriptor<MistakeEntry>(predicate: #Predicate { !$0.resolved }))) ?? []
        for entry in mistakes {
            guard let time = entry.podcastTime, let id = entry.episodeID, let duration = durations[id] else { continue }
            candidates.append((entry.createdAt, clip(id, time, duration, reason: "Yanlış: \(entry.question.prefix(80))", key: entry.question)))
        }
        return select(candidates, limit: limit)
    }

    /// En yeniden eskiye; aynı bölümde 30 sn içindeki kesitler birleşir (tekrar çalınmasın).
    nonisolated static func select(_ candidates: [(date: Date, clip: PodcastClip)], limit: Int) -> [PodcastClip] {
        var out: [PodcastClip] = []
        for item in candidates.sorted(by: { $0.date > $1.date }) {
            if out.contains(where: { $0.episodeID == item.clip.episodeID && abs($0.start - item.clip.start) < 30 }) { continue }
            out.append(item.clip)
            if out.count >= limit { break }
        }
        return out
    }

    nonisolated static func clip(_ episodeID: UUID, _ time: Double, _ duration: Double, reason: String, key: String) -> PodcastClip {
        let start = max(0, time - 3)
        let end = duration > 0 ? min(duration, start + 45) : start + 45
        return PodcastClip(episodeID: episodeID, start: start, end: max(end, start + 1), reason: reason, questionKey: key)
    }

    /// Kesitten sonra sorulacak soru: bölümün quiz'indeki aynı soru; yoksa karttan/yanlıştan açık uçlu soru.
    static func question(for clip: PodcastClip, context: ModelContext) -> QuizItem? {
        guard let key = clip.questionKey else { return nil }
        let id = clip.episodeID
        if let episode = try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })).first,
           let item = episode.study?.quiz.first(where: { $0.question == key }) {
            return item
        }
        if let card = try? context.fetch(FetchDescriptor<ReviewCard>(predicate: #Predicate { $0.episodeID == id && $0.front == key })).first {
            return QuizItem(question: card.front, options: [], answerIndex: -1, explanation: card.back, sourcePage: card.sourcePage,
                            kind: "open", chapterIndex: card.chapterIndex, answerText: card.back)
        }
        if let entry = try? context.fetch(FetchDescriptor<MistakeEntry>(predicate: #Predicate { $0.question == key })).first {
            return QuizItem(question: entry.question, options: [], answerIndex: -1, explanation: entry.why, sourcePage: entry.sourcePage,
                            kind: "open", chapterIndex: entry.chapterIndex, answerText: entry.correctAnswer)
        }
        return nil
    }
}
