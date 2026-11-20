import Foundation

// P6: öğrenme uçları (/v1/study-v2, /v1/quiz-more, /v1/recall-check, /v1/discriminate). Hepsi `learn2` bayrağına bağlı.

/// Transkript turu (küresel tur indeksi `i`, konu `c`, metin `t` ≤600).
nonisolated struct TranscriptTurnRef: Codable, Hashable, Sendable {
    var i: Int
    var c: Int
    var t: String
}

/// Konu turu (`/v1/recall-check`).
nonisolated struct ChapterTurnRef: Codable, Hashable, Sendable {
    var i: Int
    var t: String
}

nonisolated struct StudyV2Request: Encodable, Sendable {
    var title: String
    var sourceNotes: String
    var level: String
    var quizCount: Int
    var flashcardCount: Int
    var conceptCount: Int?
    var transcript: String?
    var transcriptTurns: [TranscriptTurnRef]?
    var kinds: [String]?
    var avoid: [String]?
    var verify: Bool?
}

nonisolated struct FlashcardV2: Codable, Hashable, Sendable {
    var front: String
    var back: String
    var chapterIndex: Int?
}

/// `/v1/study` şekli + kartlarda konu indeksi.
nonisolated struct StudyV2Response: Decodable, Sendable {
    var quiz: [QuizItem]
    var flashcards: [FlashcardV2]
    var concepts: [Concept]?
    var formulas: [Formula]?

    var pack: StudyPack {
        StudyPack(quiz: quiz, flashcards: flashcards.map { Flashcard(front: $0.front, back: $0.back) }, concepts: concepts, formulas: formulas)
    }
}

nonisolated struct QuizMoreRequest: Encodable, Sendable {
    var title: String
    var sourceNotes: String
    var transcriptTurns: [TranscriptTurnRef]?
    var count: Int
    var kinds: [String]
    var avoid: [String]
}

nonisolated struct QuizMoreResponse: Decodable, Sendable {
    var quiz: [QuizItem]
}

nonisolated struct RecallFollowUp: Codable, Hashable, Sendable {
    var question: String
    var answer: String
}

nonisolated struct RecallCheckRequest: Encodable, Sendable {
    var title: String
    var sourceNotes: String
    var chapterTitle: String
    var chapterTurns: [ChapterTurnRef]
    var response: String
    var followUp: RecallFollowUp?
}

nonisolated struct RecallCheckResult: Codable, Hashable, Sendable {
    struct Missing: Codable, Hashable, Sendable { var point: String; var turnIndex: Int? }
    struct Wrong: Codable, Hashable, Sendable { var claim: String; var correction: String; var turnIndex: Int? }
    var score: Int
    var covered: [String]
    var missing: [Missing]
    var wrong: [Wrong]
    var followUp: String?
    var feedback: String
}

nonisolated struct DiscriminateRequest: Encodable, Sendable {
    var a: String
    var b: String
    var notes: String
    var count: Int
}

nonisolated struct DiscriminateResult: Decodable, Sendable {
    struct Row: Codable, Hashable, Sendable { var aspect: String; var a: String; var b: String }
    var contrast: [Row]
    var questions: [QuizItem]
}

extension APIClient {
    func studyV2(_ request: StudyV2Request) async throws -> StudyV2Response {
        try await post("/v1/study-v2", request, longRunning: true)
    }

    func quizMore(_ request: QuizMoreRequest) async throws -> [QuizItem] {
        let response: QuizMoreResponse = try await post("/v1/quiz-more", request, longRunning: true)
        return response.quiz
    }

    func recallCheck(_ request: RecallCheckRequest) async throws -> RecallCheckResult {
        try await post("/v1/recall-check", request)
    }

    func discriminate(_ request: DiscriminateRequest) async throws -> DiscriminateResult {
        try await post("/v1/discriminate", request)
    }
}

/// İstek gövdelerinin sunucu sınırlarına kırpılması (zod sınırı aşılırsa 400 döner).
nonisolated enum LearnPayload {
    static let allKinds = ["mcq", "osym", "premise", "truefalse", "open"]

    /// ≤600 tur, tur başına ≤600, toplam ≤20k karakter. Fazla tur varsa eşit aralıkla seçilir (son konular kaybolmasın).
    static func transcriptTurns(_ timeline: Timeline?, maxTurns: Int = 600, maxTotal: Int = 20_000) -> [TranscriptTurnRef]? {
        guard let turns = timeline?.turns, !turns.isEmpty else { return nil }
        // Tur başına en az 40 karakter kalacak kadar tur seçilir; seçim eşit aralıklıdır, son tur da girer.
        let limit = max(1, min(maxTurns, maxTotal / 40))
        var picked = turns
        if turns.count > limit {
            let step = Double(turns.count - 1) / Double(limit - 1 == 0 ? 1 : limit - 1)
            picked = (0..<limit).map { turns[min(turns.count - 1, Int((Double($0) * step).rounded()))] }
        }
        // Kısa turların artan payı uzunlara kalır: toplamı sığdıran en büyük tur sınırı (≤600).
        let lengths = picked.map(\.text.utf16.count)
        var lo = 1, hi = 600
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lengths.reduce(0, { $0 + min($1, mid) }) <= maxTotal { lo = mid } else { hi = mid - 1 }
        }
        let cap = lo
        var out: [TranscriptTurnRef] = []
        var total = 0
        for turn in picked {
            // Sunucu uzunluğu UTF-16 birimiyle ölçer.
            let text = utf16Prefix(turn.text, cap)
            guard total + text.utf16.count <= maxTotal else { break }
            total += text.utf16.count
            out.append(TranscriptTurnRef(i: turn.id, c: turn.chapterIndex, t: text))
        }
        return out
    }

    /// Sunucunun recall-check tur sınırı (`MAX_TURN_TEXT * 4`).
    static let maxChapterTurnText = 2_400

    /// Bir konunun turları (≤12k toplam, tur başına ≤2400: sunucu daha uzununu 400 ile reddeder).
    static func chapterTurns(_ timeline: Timeline?, chapter: Int, maxTotal: Int = 12_000) -> [ChapterTurnRef] {
        guard let turns = timeline?.turns.filter({ $0.chapterIndex == chapter }), !turns.isEmpty else { return [] }
        let cap = min(maxChapterTurnText, max(60, maxTotal / turns.count))
        var out: [ChapterTurnRef] = []
        var total = 0
        for turn in turns {
            // Sunucu uzunluğu UTF-16 birimiyle ölçer.
            let text = utf16Prefix(turn.text, cap)
            guard total + text.utf16.count <= maxTotal else { break }
            total += text.utf16.count
            out.append(ChapterTurnRef(i: turn.id, t: text))
        }
        return out
    }

    /// En fazla `limit` UTF-16 birimi; karakter (harf + birleşen işaret, emoji) bölünmez.
    static func utf16Prefix(_ s: String, _ limit: Int) -> String {
        guard s.utf16.count > limit else { return s }
        var out = ""
        var n = 0
        for ch in s {
            let w = ch.utf16.count
            if n + w > limit { break }
            out.append(ch)
            n += w
        }
        return out
    }

    /// Sorulmuş sorular (≤40×300): yeni üretimde tekrar edilmesin.
    static func avoid(_ quiz: [QuizItem]) -> [String] {
        Array(quiz.suffix(40)).map { utf16Prefix($0.question, 300) }
    }
}
