import Foundation
import SwiftData

/// #27: her soru/hatırlama denemesi. Bölüm silinse de kalır (başlık anlık görüntüsü).
@Model
final class RecallAttempt {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var episodeID: UUID?
    var episodeTitle: String = ""
    var chapterIndex: Int?
    /// quiz | inline | handsfree | pretest | endcard | exam | socratic | feynman | recall | probe | review | discriminate
    var source: String = "quiz"
    var question: String = ""
    var choices: [String] = []
    var chosenIndex: Int?
    var correctIndex: Int?
    var answerText: String?
    var isCorrect: Bool?
    /// 0…1
    var score: Double?
    /// 0 Tahmin, 1 Sanırım, 2 Eminim
    var confidence: Int?
    var responseSeconds: Double?
    var daysSinceListen: Int?
    var conceptKey: String?
    var cardID: UUID?

    init(source: String, question: String, episodeID: UUID? = nil, episodeTitle: String = "", chapterIndex: Int? = nil) {
        self.source = source
        self.question = question
        self.episodeID = episodeID
        self.episodeTitle = episodeTitle
        self.chapterIndex = chapterIndex
    }
}

/// #28: bölüm başına yoklama. `stage` = dinlemeden sonraki gün sayısı (policy.probeStages öğesi).
@Model
final class EpisodeProbe {
    var id: UUID = UUID()
    var episodeID: UUID?
    var episodeTitle: String = ""
    var dueDate: Date = Date.now
    var stage: Int = 1
    /// "probe" | "relisten"
    var kindRaw: String = "probe"
    var createdAt: Date = Date.now
    var completedAt: Date?
    var score: Double?

    init(episodeID: UUID, episodeTitle: String, dueDate: Date, stage: Int, kind: String = "probe") {
        self.episodeID = episodeID
        self.episodeTitle = episodeTitle
        self.dueDate = dueDate
        self.stage = stage
        kindRaw = kind
    }
}

/// #30: canlı soru-cevap kaydı. Bölüm silinse de kalır.
@Model
final class LiveExchange {
    var id: UUID = UUID()
    var episodeID: UUID?
    var episodeTitle: String = ""
    var createdAt: Date = Date.now
    var question: String = ""
    var answer: String = ""
    var chapterIndex: Int?
    var time: Double?
    /// "ask" | "teach"
    var mode: String = "ask"

    init(episodeID: UUID?, episodeTitle: String, question: String, answer: String, chapterIndex: Int?, time: Double?, mode: String) {
        self.episodeID = episodeID
        self.episodeTitle = episodeTitle
        self.question = question
        self.answer = answer
        self.chapterIndex = chapterIndex
        self.time = time
        self.mode = mode
    }
}

/// #36: dinleme modu. Davranışın tek kaynağı `policy`; eski "inlineQuiz" anahtarı yalnız yazılır.
nonisolated enum ListeningMode: String, CaseIterable, Identifiable, Sendable {
    case rahat, aktif, sinav
    static let key = "listening.mode"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rahat: "Rahat"
        case .aktif: "Aktif"
        case .sinav: "Sınav"
        }
    }

    static var current: ListeningMode {
        get { UserDefaults.standard.string(forKey: key).flatMap(ListeningMode.init(rawValue:)) ?? .aktif }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            UserDefaults.standard.set(newValue.policy.inlineQuestions, forKey: "inlineQuiz")
        }
    }

    var policy: ListeningPolicy {
        switch self {
        case .rahat: ListeningPolicy(inlineQuestions: false, playThinkPauses: false, endCard: true, preTest: false,
                                     confidence: false, recallPrompt: false, handsFree: false, probeStages: [3, 7, 21])
        case .aktif: ListeningPolicy(inlineQuestions: true, playThinkPauses: true, endCard: true, preTest: false,
                                     confidence: false, recallPrompt: true, handsFree: true, probeStages: [1, 3, 7, 21])
        case .sinav: ListeningPolicy(inlineQuestions: true, playThinkPauses: true, endCard: true, preTest: true,
                                     confidence: true, recallPrompt: true, handsFree: true, probeStages: [1, 2, 4, 7, 14])
        }
    }
}

nonisolated struct ListeningPolicy: Hashable, Sendable {
    var inlineQuestions: Bool
    var playThinkPauses: Bool
    var endCard: Bool
    var preTest: Bool
    var confidence: Bool
    var recallPrompt: Bool
    var handsFree: Bool
    var probeStages: [Int]
}
