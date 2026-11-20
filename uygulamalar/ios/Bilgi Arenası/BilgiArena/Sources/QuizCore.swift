import Foundation

struct QuizError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum Topic: String, CaseIterable, Codable, Identifiable {
    case mixed = "Karışık", science = "Bilim", history = "Tarih", geography = "Coğrafya", art = "Sanat", sport = "Spor", culture = "Genel Kültür", cinema = "Sinema ve TV", language = "Yabancı Dil", exam = "Sınav Hazırlık", custom = "Özel Konu"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .mixed: return "sparkles"
        case .science: return "atom"
        case .history: return "building.columns.fill"
        case .geography: return "globe.europe.africa.fill"
        case .art: return "paintpalette.fill"
        case .sport: return "sportscourt.fill"
        case .culture: return "lightbulb.fill"
        case .cinema: return "film.fill"
        case .language: return "character.book.closed.fill"
        case .exam: return "graduationcap.fill"
        case .custom: return "pencil.and.list.clipboard"
        }
    }
}

enum Difficulty: String, CaseIterable, Codable { case easy = "Kolay", medium = "Orta", hard = "Zor" }

struct Question: Codable, Identifiable, Equatable {
    var id: String { activity == nil ? text : poolKey }
    let text: String
    let options: [String]
    let answer: Int
    let explanation: String
    let category: Topic
    let difficulty: Difficulty
    var optionExplanations: [String]? = nil
    var modelID: String? = nil
    var reviewedBy: String? = nil
    var visual: QuestionVisual? = nil
    var activity: QuestionActivity? = nil
    var study: StudyLesson? = nil

    static func decode(_ content: String, expectedCount: Int = 10) throws -> [Question] {
        struct Envelope: Decodable { let questions: [Question] }
        let clean = cleanJSON(content)
        guard clean.utf8.count < 900_000,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(clean.utf8)),
              envelope.questions.count == expectedCount else { throw QuizError("Model eksiksiz bir soru paketi döndürmedi. Tekrar dene.") }
        let questions = envelope.questions
        guard Set(questions.map { normalized($0.text) }).count == questions.count,
              questions.allSatisfy(\.isWellFormed) else { throw QuizError("Sorularda eksik, tekrarlanan veya geçersiz alanlar var. Paket kullanılmadı.") }
        return questions
    }
    var isWellFormed: Bool {
        (8...400).contains(text.count) && options.count == 4 && (0...3).contains(answer)
        && options.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 180 }
        && Set(options.map(Self.normalized)).count == 4 && (10...1400).contains(explanation.count)
        && (optionExplanations == nil || (optionExplanations!.count == 4 && optionExplanations!.allSatisfy { (5...500).contains($0.count) }))
        && (study == nil || (category == .exam && study!.isValid))
        && (activity?.isValid ?? true) && (visual == nil || activity == nil)
        && (activity?.needsResponse != true || (answer == 0 && options == activity?.canonicalOptions))
        && (activity?.kind == .listening || !QuestionActivity.requiresAudio(text))
        && (visual?.isValid ?? true)
        && (visual != nil || !QuestionVisual.requiresVisual(text))
    }
    static func cleanJSON(_ content: String) -> String {
        let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```"), let firstLine = value.firstIndex(of: "\n"), value.hasSuffix("```") { return String(value[value.index(after: firstLine)...].dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines) }
        return value
    }
    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
    }
}

struct AnswerRecord: Codable, Identifiable {
    var id: String { question.id }
    let question: Question
    let chosen: Int?
    let points: Int
    var response: ActivityResponse? = nil
    var correct: Bool { chosen == question.answer }
}

struct Round: Codable {
    let id: UUID
    let questions: [Question]
    let source: String
    var index = 0
    var answers: [AnswerRecord] = []
    var remaining = 10
    var mode: GameMode? = nil
    var effectiveMode: GameMode { mode ?? .classic }
    var settings: RoundSettings? = nil
    var totalRemaining: Int? = nil
    var liveVoice: Bool? = nil
    var activityDraft: ActivityResponse? = nil
    var audioReadyQuestionID: String? = nil
    var awaitsListening: Bool { current.activity?.kind == .listening && audioReadyQuestionID != current.id }
    var stageIndex: Int { min(2,index * 3 / max(1,questions.count)) }
    var stageTitle: String { ["Isınma", "Odak", "Final"][stageIndex] }
    var hasQuestionClock: Bool { questionSeconds > 0 }
    var questionSeconds: Int {
        guard effectiveMode != .training, effectiveMode != .timed else { return 0 }
        let custom = settings?.normalized.seconds ?? 0
        let base = custom > 0 ? custom : effectiveMode == .stages ? [20,15,10][stageIndex] : effectiveMode.seconds
        let readingFloor = current.activity == nil ? 0 : effectiveMode == .sprint ? 20 : 30
        let visualFloor = current.visual == nil ? 0 : effectiveMode == .sprint ? 15 : 25
        return max(base,max(readingFloor,visualFloor))
    }
    var clockText: String? { totalRemaining.map { String(format:"%02d:%02d",$0/60,$0%60) } }
    var eliminated: [Int] = []
    var usedHalf = false
    var usedTime = false
    var usedSkip = false
    var streak = 0
    var finished = false
    var paused = false
    var score: Int { answers.reduce(0) { $0 + $1.points } }
    var current: Question { questions[index] }
    var revealed: Bool { answers.count > index }

    init(questions: [Question], source: String, mode: GameMode = .classic, settings: RoundSettings = .init()) {
        precondition(!questions.isEmpty)
        id = UUID(); self.questions = questions; self.source = source; self.mode = mode
        self.settings = settings.normalized
        let minutes = mode == .timed ? max(1,settings.normalized.minutes) : settings.normalized.minutes
        totalRemaining = mode == .training || minutes == 0 ? nil : minutes * 60
        remaining = questionSeconds
    }
    mutating func answer(_ choice: Int?, response: ActivityResponse? = nil) {
        guard !finished, !revealed, !paused, choice == nil || (0..<4).contains(choice!), choice == nil || !eliminated.contains(choice!) else { return }
        if choice != nil {
            guard !awaitsListening else { return }
            if let activity = current.activity, activity.needsResponse {
                guard let response, activity.accepts(response), choice == (activity.isCorrect(response) ? current.answer : (current.answer+1)%4) else { return }
            }
        }
        let correct = choice == current.answer
        streak = correct ? streak + 1 : 0
        let points = correct ? 100 + min(10, remaining) * 10 + min(streak - 1, 4) * 25 : 0
        answers.append(AnswerRecord(question: current, chosen: choice, points: points,response:response))
    }
    mutating func tick() {
        guard !finished, !paused, !revealed, !awaitsListening, effectiveMode != .training else { return }
        if let total = totalRemaining {
            totalRemaining = max(0,total - 1)
            if totalRemaining == 0 { answer(nil); finished = true; return }
        }
        if hasQuestionClock {
            remaining = max(0, remaining - 1)
            if remaining == 0 { answer(nil) }
        }
    }
    mutating func next() {
        guard revealed, !finished else { return }
        if index + 1 == questions.count { finished = true; return }
        index += 1; remaining = questionSeconds; eliminated = []; audioReadyQuestionID = nil; activityDraft = nil
    }
    mutating func half() {
        guard current.activity?.needsResponse != true, !usedHalf, !revealed, !finished, !paused else { return }
        eliminated = Array((0..<4).filter { $0 != current.answer }.shuffled().prefix(2)); usedHalf = true
    }
    mutating func moreTime() {
        guard !usedTime, !revealed, !finished, !paused else { return }
        if let total = totalRemaining { totalRemaining = total + 15 }
        if hasQuestionClock { remaining += 15 }; usedTime = true
    }
    mutating func skip() {
        guard !usedSkip, !revealed, !finished, !paused else { return }
        usedSkip = true; answer(nil)
    }
}

struct RoundResult: Codable, Identifiable {
    let id: UUID
    let date: Date
    let score: Int
    let correct: Int
    let total: Int
    let source: String
}
