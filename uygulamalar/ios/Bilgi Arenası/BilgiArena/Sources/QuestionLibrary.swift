import Foundation
import CryptoKit

enum QuestionSimilarity {
    static func fingerprint(_ text: String) -> String {
        Question.normalized(text).unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }.joined()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    static func isDuplicate(_ text: String, against others: Set<String>) -> Bool {
        let key = fingerprint(text), words = Set(key.split(separator: " ").map(String.init))
        let digits = key.filter(\.isNumber)
        return others.contains { other in
            let otherKey = fingerprint(other)
            if key == otherKey { return true }
            let tokens = Set(otherKey.split(separator: " ").map(String.init))
            // Keep different numerical questions and short stems distinct.
            guard words.count >= 8, tokens.count >= 8, digits == otherKey.filter(\.isNumber) else { return false }
            return Double(words.intersection(tokens).count) / Double(words.union(tokens).count) >= 0.88
        }
    }
}

extension Question {
    var uniquenessText: String {
        guard let activity else { return text }
        let stimulus: String
        switch activity.kind {
        case .listening, .pronunciation: stimulus = (activity.language ?? "") + " " + (activity.transcript ?? "")
        case .ordering: stimulus = (activity.items ?? []).map(Self.normalized).sorted().joined(separator:" | ")
        case .matching: stimulus = (activity.left ?? []).map(Self.normalized).sorted().joined(separator:" | ") + " / " + (activity.right ?? []).map(Self.normalized).sorted().joined(separator:" | ")
        }
        return text + " | " + activity.kind.rawValue + " | " + stimulus
    }
    var poolKey: String {
        guard activity != nil else { return QuestionSimilarity.fingerprint(text) }
        let digest = SHA256.hash(data:Data(QuestionSimilarity.fingerprint(uniquenessText).utf8)).map { String(format:"%02x",$0) }.joined()
        return "activity:"+digest
    }
    func rearranged(correctPosition: Int? = nil) -> Question {
        guard isWellFormed else { return self }
        if let activity, activity.needsResponse { return replacingActivity(activity.shuffled()) }
        var order = (0..<4).filter { $0 != answer }.shuffled()
        order.insert(answer, at: correctPosition.map { min(3,max(0,$0)) } ?? Int.random(in: 0..<4))
        return Question(text:text, options:order.map { options[$0] }, answer:order.firstIndex(of:answer)!, explanation:explanation,
                        category:category, difficulty:difficulty, optionExplanations:optionExplanations.map { reasons in order.map { reasons[$0] } }, modelID:modelID, reviewedBy:reviewedBy,visual:visual,activity:activity,study:study)
    }
}

enum ReportReason: String, Codable, CaseIterable, Identifiable {
    case incorrect = "Cevap hatalı", ambiguous = "Soru belirsiz", repeated = "Tekrar eden soru", other = "Başka bir sorun"
    var id: String { rawValue }
}
struct QuestionReport: Codable, Identifiable {
    var id: String { question.poolKey }
    let question: Question
    let reason: ReportReason
    let date: Date
}

extension Topic {
    var editorialAreas: [String] {
        switch self {
        case .science: return ["fizik ve günlük yaşam", "biyoloji ve canlılar", "kimya ve maddeler", "astronomi", "bilimsel yöntem"]
        case .history: return ["Türkiye Cumhuriyeti", "dünya uygarlıkları", "kültür ve bilim tarihi", "Osmanlı tarihi", "kronoloji ve neden-sonuç"]
        case .geography: return ["fiziki coğrafya", "Türkiye coğrafyası", "iklim ve çevre", "harita bilgisi", "dünya coğrafyası"]
        case .art: return ["resim ve heykel", "müzik", "edebiyat", "mimarlık", "sanat kavramları"]
        case .sport: return ["takım sporları", "atletizm", "raket sporları", "olimpik branşlar", "temel oyun kuralları"]
        case .culture: return ["günlük yaşam", "dil ve kavramlar", "teknoloji", "mantık", "kültürel miras"]
        case .cinema: return ["sinema dili", "kurgu ve ses", "film yapımı", "türler", "anlatı teknikleri"]
        case .language: return ["kelime anlamı", "cümle tamamlama", "dil bilgisi", "bağlamdan anlam", "kısa okuma"]
        case .exam: return ["kavram bilgisi", "kısa problem", "çıkarım", "karşılaştırma", "uygulama"]
        case .custom: return ["temel kavram", "uygulama", "karşılaştırma", "neden-sonuç", "çıkarım"]
        case .mixed: return ["Bilim", "Tarih", "Coğrafya", "Sanat ve edebiyat", "Genel kültür"]
        }
    }
}

enum QuestionBlueprint {
    static func instructions(topic: Topic, difficulty: Difficulty, offset: Int, count: Int) -> String {
        let areas = topic.editorialAreas
        let styles = ["doğrudan bilgi", "kısa bağlamdan çıkarım", "karşılaştırma", "günlük uygulama", "neden-sonuç"]
        let slots = (0..<count).map { index in
            let position = offset + index
            return "\(index+1). \(areas[position % areas.count]) · \(styles[(position / areas.count + index) % styles.count])"
        }.joined(separator:"\n")
        let level: String
        switch difficulty {
        case .easy: level = "Temel tek kavram, kısa cümle; ezoterik bilgi veya çok adımlı hesap yok."
        case .medium: level = "Kavramı uygulatan bir veya iki düşünme adımı; makul çeldiriciler."
        case .hard: level = "Kavramlar arasında bağlantı veya çok adımlı çıkarım; zorluk muğlaklıktan ya da gereksiz ayrıntıdan gelmesin."
        }
        return "Zorluk ölçütü: \(level)\nÇeşitlilik planı (özel dil/sınav/konu isteğinin sınırlarını aşma):\n\(slots)"
    }
}
