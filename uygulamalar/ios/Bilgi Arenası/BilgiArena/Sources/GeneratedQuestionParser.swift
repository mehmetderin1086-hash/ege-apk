import Foundation
import CoreFoundation

/// Provider output is normalized here; imported files still use strict Question.decode.
enum GeneratedQuestionParser {
    struct Result {
        let questions: [Question]
        let rejected: Int
    }
    static func parse(_ content: String, topic: Topic, difficulty: Difficulty, excluding: Set<String>, limit: Int) -> Result {
        guard content.utf8.count <= 150_000, limit > 0 else { return Result(questions: [], rejected: 1) }
        let clean = Question.cleanJSON(content).trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
        var rows: [[String: Any]] = []
        func append(_ value: Any) {
            if let root = value as? [String: Any] {
                if let array = root["questions"] as? [[String: Any]] { rows += array }
                else if root["text"] != nil || root["question"] != nil { rows.append(root) }
            } else if let array = value as? [[String: Any]] { rows += array }
        }
        if let value = try? JSONSerialization.jsonObject(with: Data(clean.utf8)) { append(value) }
        else {
            // Recover only fully closed JSON values, including complete rows before a truncated tail.
            for data in balancedValues(Data(clean.utf8)) {
                if let value = try? JSONSerialization.jsonObject(with: data) { append(value) }
            }
        }
        var questions: [Question] = [], seen = excluding, rejected = 0
        for row in rows {
            guard let q = question(row, topic: topic, difficulty: difficulty) else { rejected += 1; continue }
            guard !QuestionSimilarity.isDuplicate(q.uniquenessText, against:seen) else { rejected += 1; continue }
            seen.insert(Question.normalized(q.uniquenessText))
            questions.append(q)
            if questions.count == limit { break }
        }
        return Result(questions: questions, rejected: rejected)
    }
    private static func question(_ row: [String: Any], topic: Topic, difficulty: Difficulty) -> Question? {
        var activity: QuestionActivity?
        if let value = row["activity"], !(value is NSNull) {
            guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject:value),
                  let decoded = try? JSONDecoder().decode(QuestionActivity.self,from:data), decoded.isValid else { return nil }
            activity = decoded
        }
        let interactive = activity?.needsResponse == true
        guard let rawText = (row["text"] ?? row["question"]) as? String,
              let explanation = (row["explanation"] ?? row["reason"]) as? String,
              let options = interactive ? activity?.canonicalOptions : strings(row["options"] ?? row["choices"]), options.count == 4,
              let reasons = interactive ? [String(explanation.prefix(500)),"Bu düzen doğru çözümle uyuşmuyor.","Bu düzen doğru çözümle uyuşmuyor.","Bu düzen doğru çözümle uyuşmuyor."] : strings(row["optionExplanations"] ?? row["option_explanations"]), reasons.count == 4,
              let answer = interactive ? 0 : answer(row["answer"] ?? row["correctAnswer"] ?? row["correct_answer"], options: options) else { return nil }
        let category: Topic
        if let raw = row["category"] as? String {
            guard let value = Topic.allCases.first(where: { Question.normalized($0.rawValue) == Question.normalized(raw) }), topic == .mixed || value == topic else { return nil }
            category = value
        } else { category = topic }
        if let raw = row["difficulty"] as? String {
            let aliases: [String: Difficulty] = ["easy":.easy,"medium":.medium,"hard":.hard]
            guard (Difficulty.allCases.first { Question.normalized($0.rawValue) == Question.normalized(raw) } ?? aliases[raw.lowercased()]) == difficulty else { return nil }
        }
        var visual: QuestionVisual?
        if let value = row["visual"], !(value is NSNull) {
            guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject:value),
                  let decoded = try? JSONDecoder().decode(QuestionVisual.self,from:data), decoded.isValid else { return nil }
            visual = decoded
        }
        var study: StudyLesson?
        if let value = row["study"], !(value is NSNull) {
            guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject:value), let decoded = try? JSONDecoder().decode(StudyLesson.self,from:data), decoded.isValid else { return nil }
            study = decoded
        }
        let q = Question(text: rawText.trimmingCharacters(in: .whitespacesAndNewlines), options: options, answer: answer,
                         explanation: explanation.trimmingCharacters(in: .whitespacesAndNewlines), category: category,
                         difficulty: difficulty, optionExplanations: reasons,visual:visual,activity:activity,study:study)
        return q.isWellFormed ? q : nil
    }
    private static func strings(_ value: Any?) -> [String]? {
        let values: [String]
        if let array = value as? [String] { values = array }
        else if let map = value as? [String: String], map.count == 4, ["A","B","C","D"].allSatisfy({ map[$0] != nil }) { values = ["A","B","C","D"].map { map[$0]! } }
        else { return nil }
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    private static func answer(_ value: Any?, options: [String]) -> Int? {
        if let n = value as? NSNumber {
            guard CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.rounded() == n.doubleValue, (0...3).contains(n.intValue) else { return nil }
            return n.intValue
        }
        guard let s = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if let index = ["A","B","C","D"].firstIndex(of: s.uppercased()) { return index }
        if let index = Int(s), (0...3).contains(index) { return index }
        return options.firstIndex { Question.normalized($0) == Question.normalized(s) }
    }
    private static func balancedValues(_ data: Data) -> [Data] {
        let bytes = Array(data)
        var stack: [(UInt8, Int)] = [], inString = false, escaped = false, values: [Data] = []
        for (index, byte) in bytes.enumerated() {
            if stack.isEmpty {
                if byte == 123 || byte == 91 { stack.append((byte,index)); inString = false; escaped = false }
                continue
            }
            if inString {
                if escaped { escaped = false } else if byte == 92 { escaped = true } else if byte == 34 { inString = false }
                continue
            }
            if byte == 34 { inString = true }
            else if byte == 123 || byte == 91 {
                guard stack.count < 32 else { return [] }
                stack.append((byte,index))
            }
            else if byte == 125 || byte == 93 {
                guard let top = stack.last, (top.0 == 123 && byte == 125) || (top.0 == 91 && byte == 93) else { stack = []; continue }
                stack.removeLast()
                guard values.count < 512 else { return [] }
                values.append(Data(bytes[top.1...index]))
            }
        }
        // Larger complete envelopes first; individual rows remain available for truncated envelopes.
        return values.sorted { $0.count > $1.count }
    }
}
