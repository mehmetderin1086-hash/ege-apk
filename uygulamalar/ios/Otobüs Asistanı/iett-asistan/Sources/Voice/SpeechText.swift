import Foundation

/// Sesli okunacak metni hazırlar: simgeleri ve kısaltmaları söylenişe çevirir, uzun metni parçalara böler.
enum SpeechText {
    /// Ekran metninden konuşma metnine: "4 dk" → "4 dakika", "→" → yön, "~7" → "yaklaşık 7", "1,2 km" → "1,2 kilometre", işaret/emoji temizliği.
    static func spoken(from text: String) -> String {
        var s = text
        let replacements: [(String, String)] = [
            ("→", " yönüne "), ("➜", " yönüne "), ("●", ". "), ("•", ". "), ("·", ", "), ("~", "yaklaşık "), ("★", ""), ("*", ""),
            ("(-1)", ""), ("(-2)", ""),
        ]
        for (a, b) in replacements { s = s.replacingOccurrences(of: a, with: b) }
        let patterns: [(String, String)] = [
            (#"(?<=\d)\s*dk\b"#, " dakika"), (#"(?<=\d)\s*sa\b"#, " saat"), (#"(?<=\d)\s*sn\b"#, " saniye"),
            (#"(?<=\d)\s*km\b"#, " kilometre"), (#"(?<=\d)\s*m\b"#, " metre"), (#"\bdk\b"#, "dakika"), (#"\bG:\s*(\d+)"#, "gidiş $1"), (#"\bD:\s*(\d+)"#, "dönüş $1"),
            (#"(\d{1,2}):(\d{2})"#, "$1 $2"),
            (#"[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}\x{2B00}-\x{2BFF}\x{FE0F}]"#, ""),
            (#"[ \t]{2,}"#, " "), (#"\s*\n\s*"#, ". "), (#"\.\s*\.+"#, "."), (#"\s+([.,!?])"#, "$1"),
        ]
        for (pattern, template) in patterns { s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression) }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: " .,;").union(.whitespacesAndNewlines))
    }

    /// En çok `max` karakterlik parçalar; cümle sınırında bölünür (sunucu tek istekte 1500 karakter kabul eder).
    static func chunks(_ text: String, max: Int = 900) -> [String] {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        if clean.count <= max { return [clean] }
        var result: [String] = [], current = ""
        let sentences = clean.split(omittingEmptySubsequences: true, whereSeparator: { ".!?".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) + "." }
        for sentence in sentences {
            if sentence.count > max {   // tek cümle bile uzunsa kelime sınırında kes
                if !current.isEmpty { result.append(current); current = "" }
                var piece = ""
                for word in sentence.split(separator: " ") { if piece.count + word.count + 1 > max { result.append(piece); piece = "" }; piece += (piece.isEmpty ? "" : " ") + word }
                if !piece.isEmpty { current = piece }
                continue
            }
            if current.count + sentence.count + 1 > max { result.append(current); current = sentence } else { current += (current.isEmpty ? "" : " ") + sentence }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Azure SSML gövdesi (XML kaçışlı).
    static func ssml(text: String, voice: String, rate: Double = 1.0) -> String {
        func escape(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        let percent = Int(((rate - 1) * 100).rounded())
        return "<speak version='1.0' xml:lang='tr-TR' xmlns='http://www.w3.org/2001/10/synthesis'><voice name='\(voice)'><prosody rate='\(percent >= 0 ? "+" : "")\(percent)%'>\(escape(text))</prosody></voice></speak>"
    }
}

/// Konuşma tanıma sonuçları değişmeyi bırakınca "söz bitti" der (sessizlik süresi dolunca).
struct EndpointDetector {
    var silence: TimeInterval = 1.3
    private var lastText = ""
    private var lastChange = Date.distantPast
    mutating func update(text: String, now: Date) -> Bool {
        if text != lastText { lastText = text; lastChange = now; return false }
        return !text.isEmpty && now.timeIntervalSince(lastChange) >= silence
    }
    mutating func reset() { lastText = ""; lastChange = .distantPast }
}
