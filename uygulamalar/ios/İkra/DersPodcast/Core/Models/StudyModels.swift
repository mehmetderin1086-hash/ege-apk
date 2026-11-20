import Foundation
import SwiftData

/// Transkriptte işaretlenmiş an (+ isteğe bağlı not).
@Model
final class Bookmark {
    var id: UUID = UUID()
    var episodeID: UUID = UUID()
    var episodeTitle: String = ""
    var time: Double = 0
    var text: String = ""
    var note: String = ""
    var createdAt: Date = Date.now
    /// Sesli not (Application Support/VoiceNotes/<ad>.m4a).
    var audioFileName: String?
    /// "note" | "confused" | "flag" | "siri"
    var kind: String = "note"
    var chapterIndex: Int?

    init(episode: Episode, time: Double, text: String, note: String = "") {
        episodeID = episode.id
        episodeTitle = episode.title
        self.time = time
        self.text = text
        self.note = note
    }
}

/// Aralıklı tekrar kartı (SM-2'nin sadeleştirilmiş hali). Hem flashcard'lar hem yanlış yapılan quiz soruları buraya düşer.
@Model
final class ReviewCard {
    enum Kind: String, Codable { case flashcard, quiz }

    var id: UUID = UUID()
    var episodeID: UUID = UUID()
    var episodeTitle: String = ""
    var kindRaw: String = Kind.flashcard.rawValue
    var front: String = ""
    var back: String = ""
    var sourcePage: Int?
    /// Kaynak kitap anahtarı (kitap-36 veya document-UUID); eski kartlarda nil.
    var sourceBookID: String? = nil
    /// Explicit source snapshot; optional for existing cards and lightweight migration.
    var learningSourceJSON: String? = nil

    var ease: Double = 2.5
    var intervalDays: Int = 0
    var repetitions: Int = 0
    var lapses: Int = 0
    var due: Date = Date.now
    var lastReviewed: Date?
    var createdAt: Date = Date.now
    /// Sesli kart: kartın arkasında çalınacak video dersi kesiti (ders kimliği + saniye aralığı); nil = yok.
    var clipLessonID: UUID?
    var clipStart: Double = 0
    var clipEnd: Double = 0
    /// #32 bellek modeli; 0 = henüz hesaplanmadı (SM-2 alanlarından türetilir).
    var stability: Double = 0
    var memoryDifficulty: Double = 0
    var lastLapseAt: Date?
    /// #33 bağlam
    var episodeTime: Double?
    var figureID: String?
    /// "quiz" | "flashcard" | "inline" | "handsfree" | "probe" | "suggestion" | "live"
    var origin: String?
    var chapterIndex: Int?

    init(episodeID: UUID, episodeTitle: String, kind: Kind, front: String, back: String, sourcePage: Int?) {
        self.episodeID = episodeID
        self.episodeTitle = episodeTitle
        kindRaw = kind.rawValue
        self.front = front
        self.back = back
        self.sourcePage = sourcePage
    }

    var kind: Kind { Kind(rawValue: kindRaw) ?? .flashcard }
    var isDue: Bool { due <= .now }

    /// İki başarılı tekrardan sonra zayıf sayılmaz; son lapse 30 günden eskiyse de sayılmaz.
    var isWeak: Bool {
        if repetitions >= 2 { return false }
        if let last = lastLapseAt { return last > Date.now.addingTimeInterval(-30 * 86_400) }
        return lapses >= 1 || (repetitions == 0 && kind == .quiz)
    }
}

enum ReviewGrade: Int, CaseIterable {
    case again = 0, hard = 3, good = 4, easy = 5

    var title: String {
        switch self {
        case .again: "Bilemedim"
        case .hard: "Zor"
        case .good: "İyi"
        case .easy: "Kolay"
        }
    }
}

nonisolated enum SpacedRepetition {
    /// SM-2: ilk tekrarlar 1 → 3 gün, sonra aralık × ease. "Bilemedim" kartı yarın tekrar gelir.
    static func next(ease: Double, interval: Int, repetitions: Int, grade: Int, now: Date = .now)
        -> (ease: Double, interval: Int, repetitions: Int, due: Date) {
        var ease = ease
        var interval = interval
        var repetitions = repetitions
        if grade < 3 {
            repetitions = 0
            interval = 1
        } else {
            repetitions += 1
            interval = switch repetitions {
            case 1: 1
            case 2: 3
            default: max(1, Int((Double(interval) * ease).rounded()))
            }
            if grade == 5 { interval = Int((Double(interval) * 1.3).rounded()) }
        }
        let q = Double(grade)
        ease = max(1.3, ease + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)))
        let due = Calendar.current.startOfDay(for: now).addingTimeInterval(Double(interval) * 86_400 + 4 * 3600)
        return (ease, interval, repetitions, due)
    }
}

extension ReviewCard {
    func review(_ grade: ReviewGrade, now: Date = .now) {
        let result = SpacedRepetition.next(ease: ease, interval: intervalDays, repetitions: repetitions, grade: grade.rawValue, now: now)
        ease = result.ease
        intervalDays = result.interval
        repetitions = result.repetitions
        due = result.due
        lastReviewed = now
        if grade == .again { lapses += 1; lastLapseAt = now }
    }
}
