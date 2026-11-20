import Foundation
import SwiftData

// MARK: - Oku: öğrencinin günlük çalışma verileri (tek kullanıcı, cihazda)

/// Ders (Biyoloji, Matematik…). Program, ödev ve odak oturumları buna bağlanır.
@Model
final class Course {
    var id: UUID = UUID()
    var name: String = ""
    /// Hex renk ("#6B4CF2").
    var colorHex: String = "#6B4CF2"
    var createdAt: Date = Date.now

    init(name: String, colorHex: String) {
        self.name = name
        self.colorHex = colorHex
    }
}

/// Haftalık ders programındaki bir saat. `weekday` 1 = Pazar … 7 = Cumartesi (Calendar ile aynı).
@Model
final class Lesson {
    var id: UUID = UUID()
    var courseID: UUID = UUID()
    var weekday: Int = 2
    /// Gün içindeki başlangıç, dakika (örn. 9:30 → 570).
    var startMinute: Int = 540
    var durationMinutes: Int = 40
    var room: String = ""

    init(courseID: UUID, weekday: Int, startMinute: Int, durationMinutes: Int, room: String = "") {
        self.courseID = courseID
        self.weekday = weekday
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes
        self.room = room
    }
}

/// Ödev ya da sınav.
@Model
final class Assignment {
    enum Kind: String, Codable, CaseIterable { case homework, exam, project }

    var id: UUID = UUID()
    var courseID: UUID?
    var title: String = ""
    var kindRaw: String = Kind.homework.rawValue
    var dueDate: Date = Date.now
    var isDone: Bool = false
    var note: String = ""
    /// İlgili podcast bölümü (varsa "bu bölümü dinle").
    var episodeID: UUID?
    var createdAt: Date = Date.now

    init(title: String, kind: Kind, dueDate: Date, courseID: UUID? = nil, episodeID: UUID? = nil, note: String = "") {
        self.title = title
        self.kindRaw = kind.rawValue
        self.dueDate = dueDate
        self.courseID = courseID
        self.episodeID = episodeID
        self.note = note
    }

    var kind: Kind { Kind(rawValue: kindRaw) ?? .homework }
    var isOverdue: Bool { !isDone && dueDate < Calendar.current.startOfDay(for: .now) }
}

/// Odak (Pomodoro) oturumu kaydı.
@Model
final class StudySession {
    var id: UUID = UUID()
    var startedAt: Date = Date.now
    var seconds: Double = 0
    var courseID: UUID?
    var episodeID: UUID?
    /// "focus" | "break"
    var kind: String = "focus"
    var completed: Bool = false

    init(startedAt: Date, seconds: Double, courseID: UUID?, episodeID: UUID?, kind: String, completed: Bool) {
        self.startedAt = startedAt
        self.seconds = seconds
        self.courseID = courseID
        self.episodeID = episodeID
        self.kind = kind
        self.completed = completed
    }
}

/// Yanlış defteri girdisi: her yanlış buraya düşer; "neden yanlış" açıklaması ve tekrar tarihi tutulur.
@Model
final class MistakeEntry {
    var id: UUID = UUID()
    var question: String = ""
    var myAnswer: String = ""
    var correctAnswer: String = ""
    var why: String = ""
    /// "quiz" | "exam" | "label" | "manual"
    var source: String = "manual"
    var episodeID: UUID?
    var episodeTitle: String = ""
    var sourcePage: Int?
    var courseID: UUID?
    var createdAt: Date = Date.now
    var reviewedCount: Int = 0
    /// Üst üste doğru sayısı (2 olunca çözülmüş sayılır).
    var correctStreak: Int = 0
    var resolved: Bool = false
    var photoFileName: String?
    /// Video dersinden geldiyse konunun anlatıldığı an (sn); `episodeID` o zaman ders kimliğidir.
    var videoTime: Double?
    /// Podcast'ten geldiyse konunun anlatıldığı an (sn).
    var podcastTime: Double?
    var chapterIndex: Int?

    init(question: String, myAnswer: String, correctAnswer: String, why: String = "", source: String,
         episodeID: UUID? = nil, episodeTitle: String = "", sourcePage: Int? = nil, courseID: UUID? = nil) {
        self.question = question
        self.myAnswer = myAnswer
        self.correctAnswer = correctAnswer
        self.why = why
        self.source = source
        self.episodeID = episodeID
        self.episodeTitle = episodeTitle
        self.sourcePage = sourcePage
        self.courseID = courseID
    }
}

/// Cornell not: ipuçları (sol), notlar (sağ), özet (alt). Bölüme bağlanabilir.
@Model
final class CornellNote {
    var id: UUID = UUID()
    var title: String = ""
    var cues: String = ""
    var notes: String = ""
    var summary: String = ""
    var episodeID: UUID?
    var courseID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(title: String, episodeID: UUID? = nil, courseID: UUID? = nil) {
        self.title = title
        self.episodeID = episodeID
        self.courseID = courseID
    }
}

// MARK: - Günün sözü (Çalış > alışkanlık araçları)

nonisolated enum StudyMotivation {
    static let motivations = [
        "Her gün biraz, her gün aynı saatte: beyin böyle öğrenir.",
        "Yanlış, öğrenmenin ham maddesidir. Deftere yaz, geri dön.",
        "25 dakika tam odak, 5 dakika mola. Bu kadar basit.",
        "Bir konuyu anlatabiliyorsan öğrenmişsindir.",
        "Dün yaptığın tekrar bugün seni taşır.",
        "Zor soru seni yavaşlatır, bırakmak durdurur.",
        "Küçük adım, her gün. Sınav günü sürpriz olmaz.",
    ]

    static func motivation(for date: Date = .now) -> String {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 0
        return motivations[day % motivations.count]
    }
}
