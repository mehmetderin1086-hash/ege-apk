import Foundation

enum GameMode: String, Codable, CaseIterable, Identifiable {
    case classic = "Klasik", training = "Öğren", sprint = "Hız Turu", timed = "Dakika Turu", stages = "Etaplı Tur"
    var id: String { rawValue }
    var seconds: Int { self == .sprint ? 7 : self == .training || self == .timed ? 0 : 10 }
    var subtitle: String {
        switch self {
        case .classic: return "Soru başına süre · jokerler"
        case .training: return "Süresiz · keşfederek öğren"
        case .sprint: return "Kısa sorular · hızlı karar"
        case .timed: return "Seçtiğin dakika boyunca çöz · ortak tur saati"
        case .stages: return "Isınma → Odak → Final · giderek hızlan"
        }
    }
    var icon: String {
        switch self { case .classic: return "trophy.fill"; case .training: return "book.fill"; case .sprint: return "bolt.fill"; case .timed: return "timer"; case .stages: return "flag.checkered" }
    }
}
struct RoundSettings: Codable, Equatable {
    var minutes = 0
    var seconds = 0
    var normalized: Self { Self(minutes:min(30,max(0,minutes)),seconds:seconds == 0 ? 0 : min(120,max(5,seconds))) }
}
struct ReviewCard: Codable, Identifiable {
    var id: String { question.id }
    let question: Question
    var due: Date
    var interval: Int
    var attempts: Int
    var correct: Int
    mutating func record(_ success: Bool, now: Date = Date()) {
        attempts += 1
        if success { correct += 1; interval = min(30, max(1, interval * 2)) } else { interval = 1 }
        due = Calendar.current.date(byAdding: .day, value: interval, to: now) ?? now
    }
}
struct QuestionPack: Codable, Identifiable {
    let id: UUID
    let date: Date
    let title: String
    let questions: [Question]
    let models: [String]
}
struct Achievement: Identifiable {
    let id: String
    let title: String
    let icon: String
    let earned: Bool
}
extension Array where Element == Question {
    func daily(date: Date) -> [Question] {
        let day = Calendar(identifier: .gregorian).startOfDay(for: date)
        let seed = UInt64(Swift.max(0, Int(day.timeIntervalSince1970 / 86400)))
        func key(_ text: String) -> UInt64 { text.utf8.reduce(seed ^ 1469598103934665603) { ($0 ^ UInt64($1)) &* 1099511628211 } }
        return Array(sorted { key($0.text) < key($1.text) }.prefix(10))
    }
}
struct GenerationDraft: Codable {
    let id: UUID
    let topic: Topic
    let detail: String
    let difficulty: Difficulty
    let count: Int
    let models: [String]
    var questions: [Question]
    var format: QuestionFormat? = nil
    var study: StudyLesson? = nil
    var effectiveFormat: QuestionFormat { format ?? .mixed }
}
