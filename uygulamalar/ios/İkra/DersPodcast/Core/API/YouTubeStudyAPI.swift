import Foundation

// Ders Stüdyosu öğrenme uçları (sunucu: /v1/youtube/quiz|explain|prereq|compare|worksheet|feynman).
// Girdi metinleri "[mm:ss] metin" satırlarıdır. Yanıtlar toleranslı çözülür: eksik alan boş değere düşer.

// MARK: - Toleranslı çözme yardımcıları

private nonisolated extension KeyedDecodingContainer {
    func string(_ key: Key) -> String { (try? decodeIfPresent(String.self, forKey: key)) ?? "" }
    func strings(_ key: Key) -> [String] { (try? decodeIfPresent([String].self, forKey: key)) ?? [] }
    func double(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let text = try? decodeIfPresent(String.self, forKey: key) { return Double(text) }
        return nil
    }
    func int(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite,
           value >= -1_000_000_000, value <= 1_000_000_000 { return Int(value) }
        if let text = try? decodeIfPresent(String.self, forKey: key) { return Int(text) }
        return nil
    }
}

/// Sunucu başlık sınırı (300 karakter): tüm isteklerin başlığı bu yardımcıdan geçer.
nonisolated func studyServerTitle(_ title: String) -> String {
    String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
}

// MARK: - Quiz (#18, #23, #26)

nonisolated struct StudyQuestion: Codable, Hashable, Sendable, Identifiable {
    var question: String
    var choices: [String]
    /// Doğru seçeneğin sırası (0'dan).
    var answer: Int
    var explanation: String
    /// Sorunun dayandığı an (sn); yoksa nil.
    var time: Double?

    var id: String { question + "|" + choices.joined(separator: "|") }

    private enum CodingKeys: String, CodingKey { case question, choices, answer, explanation, time }

    init(question: String, choices: [String], answer: Int, explanation: String = "", time: Double? = nil) {
        self.question = question
        self.choices = choices
        self.answer = answer
        self.explanation = explanation
        self.time = time
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        question = c.string(.question)
        choices = c.strings(.choices)
        answer = c.int(.answer) ?? -1
        explanation = c.string(.explanation)
        time = c.double(.time)
    }
}

nonisolated struct StudyQuizRequest: Encodable, Sendable {
    var title: String
    var text: String
    var count: Int
    /// "mcq" (4 şık) | "osym" (5 şık)
    var style: String

    init(title: String, text: String, count: Int, style: String) {
        self.title = studyServerTitle(title)
        self.text = text
        self.count = count
        self.style = style
    }
}

nonisolated struct StudyQuizResponse: Decodable, Sendable {
    var questions: [StudyQuestion]

    private enum CodingKeys: String, CodingKey { case questions }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        questions = (try? c.decodeIfPresent([StudyQuestion].self, forKey: .questions)) ?? []
    }
}

// MARK: - Anlamadım (#19)

nonisolated struct StudyExplainRequest: Encodable, Sendable {
    var title: String
    var text: String
    var time: Double

    init(title: String, text: String, time: Double) {
        self.title = studyServerTitle(title)
        self.text = text
        self.time = time
    }
}

nonisolated struct StudyExplanation: Decodable, Hashable, Sendable {
    var explanation: String
    var example: String
    var keyTerms: [String]

    private enum CodingKeys: String, CodingKey { case explanation, example, keyTerms }
    init(explanation: String = "", example: String = "", keyTerms: [String] = []) {
        self.explanation = explanation
        self.example = example
        self.keyTerms = keyTerms
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        explanation = c.string(.explanation)
        example = c.string(.example)
        keyTerms = c.strings(.keyTerms)
    }
}

// MARK: - Ön bilgi (#26)

nonisolated struct StudyPrereqRequest: Encodable, Sendable {
    var title: String
    var summary: String
    var concepts: [String]

    init(title: String, summary: String, concepts: [String]) {
        self.title = studyServerTitle(title)
        self.summary = summary
        self.concepts = concepts
    }
}

nonisolated struct StudyPrerequisite: Decodable, Hashable, Sendable {
    var name: String
    var why: String

    private enum CodingKeys: String, CodingKey { case name, why }
    init(name: String, why: String = "") {
        self.name = name
        self.why = why
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.string(.name)
        why = c.string(.why)
    }
}

nonisolated struct StudyPrereqResponse: Decodable, Sendable {
    var prerequisites: [StudyPrerequisite]
    var questions: [StudyQuestion]

    private enum CodingKeys: String, CodingKey { case prerequisites, questions }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prerequisites = (try? c.decodeIfPresent([StudyPrerequisite].self, forKey: .prerequisites)) ?? []
        questions = (try? c.decodeIfPresent([StudyQuestion].self, forKey: .questions)) ?? []
    }
}

// MARK: - Karşılaştırma (#27)

nonisolated struct StudyCompareSide: Encodable, Sendable {
    var title: String
    var text: String

    init(title: String, text: String) {
        self.title = studyServerTitle(title)
        self.text = text
    }
}

nonisolated struct StudyCompareRequest: Encodable, Sendable {
    var a: StudyCompareSide
    var b: StudyCompareSide
}

nonisolated struct StudyCompareVerdict: Decodable, Hashable, Sendable {
    var topic: String
    /// "a" | "b"
    var winner: String
    var why: String

    private enum CodingKeys: String, CodingKey { case topic, winner, why }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        topic = c.string(.topic)
        winner = c.string(.winner).lowercased()
        why = c.string(.why)
    }
}

nonisolated struct StudyComparison: Decodable, Sendable {
    var summary: String
    var common: [String]
    var onlyA: [String]
    var onlyB: [String]
    var better: [StudyCompareVerdict]

    private enum CodingKeys: String, CodingKey { case summary, common, onlyA, onlyB, better }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = c.string(.summary)
        common = c.strings(.common)
        onlyA = c.strings(.onlyA)
        onlyB = c.strings(.onlyB)
        better = (try? c.decodeIfPresent([StudyCompareVerdict].self, forKey: .better)) ?? []
    }
}

// MARK: - Çalışma kâğıdı (#28)

nonisolated struct StudyWorksheetRequest: Encodable, Sendable {
    var title: String
    var text: String

    init(title: String, text: String) {
        self.title = studyServerTitle(title)
        self.text = text
    }
}

nonisolated struct WorksheetBlank: Decodable, Hashable, Sendable {
    var sentence: String
    var answer: String

    private enum CodingKeys: String, CodingKey { case sentence, answer }
    init(sentence: String, answer: String) {
        self.sentence = sentence
        self.answer = answer
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sentence = c.string(.sentence)
        answer = c.string(.answer)
    }
}

nonisolated struct WorksheetQuestion: Decodable, Hashable, Sendable {
    var question: String
    var answer: String

    private enum CodingKeys: String, CodingKey { case question, answer }
    init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        question = c.string(.question)
        answer = c.string(.answer)
    }
}

nonisolated struct WorksheetPair: Decodable, Hashable, Sendable {
    var term: String
    var definition: String

    private enum CodingKeys: String, CodingKey { case term, definition }
    init(term: String, definition: String) {
        self.term = term
        self.definition = definition
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        term = c.string(.term)
        definition = c.string(.definition)
    }
}

nonisolated struct StudyWorksheet: Decodable, Hashable, Sendable {
    var blanks: [WorksheetBlank]
    var questions: [WorksheetQuestion]
    var matching: [WorksheetPair]

    private enum CodingKeys: String, CodingKey { case blanks, questions, matching }
    init(blanks: [WorksheetBlank] = [], questions: [WorksheetQuestion] = [], matching: [WorksheetPair] = []) {
        self.blanks = blanks
        self.questions = questions
        self.matching = matching
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blanks = (try? c.decodeIfPresent([WorksheetBlank].self, forKey: .blanks)) ?? []
        questions = (try? c.decodeIfPresent([WorksheetQuestion].self, forKey: .questions)) ?? []
        matching = (try? c.decodeIfPresent([WorksheetPair].self, forKey: .matching)) ?? []
    }

    var isEmpty: Bool { blanks.isEmpty && questions.isEmpty && matching.isEmpty }
}

// MARK: - Feynman (#25)

nonisolated struct StudyFeynmanRequest: Encodable, Sendable {
    var title: String
    var reference: String
    var answer: String

    init(title: String, reference: String, answer: String) {
        self.title = studyServerTitle(title)
        self.reference = reference
        self.answer = answer
    }
}

nonisolated struct StudyFeynmanResult: Decodable, Hashable, Sendable {
    var score: Int
    var covered: [String]
    var missing: [String]
    var wrong: [String]
    var feedback: String

    private enum CodingKeys: String, CodingKey { case score, covered, missing, wrong, feedback }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        score = max(0, min(100, c.int(.score) ?? 0))
        covered = c.strings(.covered)
        missing = c.strings(.missing)
        wrong = c.strings(.wrong)
        feedback = c.string(.feedback)
    }
}

// MARK: - İstemci

extension APIClient {
    @concurrent
    nonisolated func studyQuiz(_ request: StudyQuizRequest) async throws -> [StudyQuestion] {
        let response: StudyQuizResponse = try await post("/v1/youtube/quiz", request)
        return response.questions
    }

    @concurrent
    nonisolated func studyExplain(_ request: StudyExplainRequest) async throws -> StudyExplanation {
        try await post("/v1/youtube/explain", request)
    }

    @concurrent
    nonisolated func studyPrereq(_ request: StudyPrereqRequest) async throws -> StudyPrereqResponse {
        try await post("/v1/youtube/prereq", request)
    }

    @concurrent
    nonisolated func studyCompare(_ request: StudyCompareRequest) async throws -> StudyComparison {
        try await post("/v1/youtube/compare", request)
    }

    @concurrent
    nonisolated func studyWorksheet(_ request: StudyWorksheetRequest) async throws -> StudyWorksheet {
        try await post("/v1/youtube/worksheet", request)
    }

    @concurrent
    nonisolated func studyFeynman(_ request: StudyFeynmanRequest) async throws -> StudyFeynmanResult {
        try await post("/v1/youtube/feynman", request)
    }
}
