import Foundation

/// Terim düzeltme kuralı: yanlış yazılan sözcük/ifade → doğrusu (büyük/küçük harf duyarsız eşleşir, tam sözcük olarak).
nonisolated struct TermRule: Codable, Hashable, Identifiable, Sendable {
    var from: String
    var to: String
    var id: String { from.lowercased(with: TermDictionary.turkish) }
}

/// Küresel terim sözlüğü (UserDefaults). Ders ekranında düzeltilen terimler buraya yazılır;
/// yeni içe aktarılan derslere `apply(to:)` ile uygulanır (içe aktarma ekranı çağırır).
nonisolated enum TermDictionary {
    static let key = "lesson.termDictionary"
    /// Eşleştirme Türkçe kurallarıyla: "İNTEGRAL" ↔ "integral", "IZGARA" ↔ "ızgara".
    static let turkish = Locale(identifier: "tr_TR")

    static var rules: [TermRule] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let rules = try? JSONDecoder().decode([TermRule].self, from: data) else { return [] }
        return rules
    }

    static func save(_ rules: [TermRule]) {
        if rules.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Kural ekler (aynı "yanlış" varsa günceller). Geçersiz kural (boş ya da aynı) eklenmez; eklendiyse kuralı döndürür.
    @discardableResult
    static func add(from: String, to: String) -> TermRule? {
        let rule = TermRule(from: from.trimmingCharacters(in: .whitespacesAndNewlines),
                            to: to.trimmingCharacters(in: .whitespacesAndNewlines))
        guard isValid(rule) else { return nil }
        var all = rules.filter { $0.id != rule.id }
        all.append(rule)
        save(all)
        return rule
    }

    static func remove(_ rule: TermRule) {
        save(rules.filter { $0.id != rule.id })
    }

    static func isValid(_ rule: TermRule) -> Bool {
        !rule.from.isEmpty && rule.from != rule.to
    }

    // MARK: - Uygulama

    /// Kayıtlı sözlüğü transkripte uygular (içe aktarma noktası). Sözlük boşsa aynen döner.
    static func apply(to transcript: VideoTranscript) -> VideoTranscript {
        apply(to: transcript, rules: rules)
    }

    /// Kuralları transkriptin tüm metinlerinde (altyazı satırları, paragraflar, çeviri, bölümler, notlar, kare yazıları) uygular.
    /// Satırın kelime sayısı değişirse o satırın kelime zamanları (`w`) atılır; zamanlar kayık kalmasın diye satır içi dağıtıma düşer.
    static func apply(to transcript: VideoTranscript, rules: [TermRule]) -> VideoTranscript {
        let active = ordered(rules)
        guard !active.isEmpty else { return transcript }
        func fix(_ text: String) -> String { replace(text, rules: active) }
        var out = transcript
        out.segments = transcript.segments.map { segment in
            var s = segment
            s.text = fix(segment.text)
            if wordCount(s.text) != wordCount(segment.text) { s.w = nil }
            return s
        }
        out.paragraphs = transcript.paragraphs.map { var p = $0; p.text = fix($0.text); return p }
        out.chapters = transcript.chapters.map { var c = $0; c.title = fix($0.title); return c }
        out.video.chapters = transcript.video.chapters.map { var c = $0; c.title = fix($0.title); return c }
        if var translation = transcript.translation {
            translation.paragraphs = translation.paragraphs.map { var p = $0; p.text = fix($0.text); return p }
            out.translation = translation
        }
        if var notes = transcript.notes {
            notes.summary = fix(notes.summary)
            notes.keyPoints = notes.keyPoints.map { var k = $0; k.text = fix($0.text); return k }
            notes.concepts = notes.concepts.map { var c = $0; c.name = fix($0.name); c.definition = fix($0.definition); return c }
            notes.formulas = notes.formulas.map { var f = $0; f.name = fix($0.name); f.meaning = fix($0.meaning); return f }
            notes.questions = notes.questions.map { var q = $0; q.question = fix($0.question); q.answer = fix($0.answer); return q }
            notes.examTips = notes.examTips.map(fix)
            out.notes = notes
        }
        out.keyframes = transcript.keyframes.map { var k = $0; k.caption = fix($0.caption); k.text = fix($0.text); return k }
        return out
    }

    /// Tek metne uygular (not, başlık vb.).
    static func apply(to text: String) -> String {
        replace(text, rules: ordered(rules))
    }

    /// Uzun ifadeler önce: "kuantum mekanik" kısa "kuantum" kuralından önce eşleşsin.
    static func ordered(_ rules: [TermRule]) -> [TermRule] {
        rules.filter(isValid).sorted { $0.from.count > $1.from.count }
    }

    static func replace(_ text: String, rules: [TermRule]) -> String {
        rules.reduce(text) { replace($0, from: $1.from, to: $1.to) }
    }

    /// `from`'u tam sözcük olarak (harf/rakam sınırı), büyük/küçük harf duyarsız değiştirir.
    /// Metinde zaten düzeltilmiş hâli (`to`, `from`'u içeriyorsa) varsa dokunmaz: kural tekrar uygulansa da çoğalmaz.
    static func replace(_ text: String, from: String, to: String) -> String {
        guard !from.isEmpty, text.range(of: from, options: .caseInsensitive, locale: turkish) != nil else { return text }
        let wordLeading = from.first.map { $0.isLetter || $0.isNumber } ?? false
        let wordTrailing = from.last.map { $0.isLetter || $0.isNumber } ?? false
        var out = ""
        var cursor = text.startIndex       // çıktıya yazılmış son konum
        var search = text.startIndex       // aramanın sürdüğü konum
        while search < text.endIndex,
              let r = text.range(of: from, options: .caseInsensitive, range: search..<text.endIndex, locale: turkish) {
            let before = r.lowerBound > text.startIndex ? text[text.index(before: r.lowerBound)] : nil
            let after = r.upperBound < text.endIndex ? text[r.upperBound] : nil
            let boundaryOK = !(wordLeading && (before.map { $0.isLetter || $0.isNumber } ?? false))
                && !(wordTrailing && (after.map { $0.isLetter || $0.isNumber } ?? false))
            if boundaryOK, !alreadyCorrected(text, match: r, from: from, to: to) {
                out += text[cursor..<r.lowerBound]
                out += to
                cursor = r.upperBound
                search = r.upperBound
            } else {
                search = text.index(after: r.lowerBound)   // çakışan eşleşmeleri de gör
            }
        }
        out += text[cursor...]
        return out
    }

    /// `match` aralığı, `to` metninin içindeki bir `from` oluşumuna denk geliyor ve çevresiyle birlikte `to`'yu oluşturuyorsa true.
    private static func alreadyCorrected(_ text: String, match r: Range<String.Index>, from: String, to: String) -> Bool {
        guard to.count > from.count, to.range(of: from, options: .caseInsensitive, locale: turkish) != nil else { return false }
        var from_ = to.startIndex
        while let hit = to.range(of: from, options: .caseInsensitive, range: from_..<to.endIndex, locale: turkish) {
            let lead = to.distance(from: to.startIndex, to: hit.lowerBound)
            let trail = to.distance(from: hit.upperBound, to: to.endIndex)
            if let start = text.index(r.lowerBound, offsetBy: -lead, limitedBy: text.startIndex),
               let end = text.index(r.upperBound, offsetBy: trail, limitedBy: text.endIndex),
               text[start..<end].compare(to, options: .caseInsensitive, range: nil, locale: turkish) == .orderedSame {
                return true
            }
            from_ = to.index(after: hit.lowerBound)
        }
        return false
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}
