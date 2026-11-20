import Foundation

/// Temiz okuma: konuşma dolgularını ("ııı", "eee", "hmm", "um" ...) satırdan gizler.
/// Zamanlar korunur: çıkarılan kelimenin süresi satırın zaman çizelgesinden de düşer (kalan kelimeler kendi zamanlarında vurgulanır).
nonisolated enum CleanReading {
    /// Ünlü uzatması ve ünleme: "ee", "eee", "ııı", "ıh", "aah" ...
    private static let stretchVowels: Set<Character> = ["e", "ı", "i", "ö", "ü", "a"]
    private static let sounds: Set<String> = [
        "hm", "hmm", "hmmm", "mm", "mmm", "mhm", "hım", "hımm", "ıhım", "ımm",
        "um", "umm", "uh", "uhh", "uhm", "er", "erm", "ahh",
    ]
    /// Yalnızca virgüllü ya da cümle başındaki bağlaç dolguları (aksi hâlde anlamlı sözcük sayılır).
    private static let markers: Set<String> = ["yani", "işte"]

    /// Noktalama ve kenar boşluğu atılmış, küçük harfli (Türkçe) biçim.
    static func normalized(_ token: String) -> String {
        token.lowercased(with: Locale(identifier: "tr_TR"))
            .trimmingCharacters(in: .punctuationCharacters.union(.symbols).union(.whitespaces))
    }

    /// Tek başına dolgu sesi mi (eee, ııı, hmm, um ...).
    static func isHesitation(_ normalized: String) -> Bool {
        guard normalized.count >= 2 else { return false }
        if sounds.contains(normalized) { return true }
        guard let first = normalized.first, stretchVowels.contains(first) else { return false }
        let rest = normalized.drop { $0 == first }
        return rest.allSatisfy { $0 == "h" }   // eee, ııı, aah, eh, ıh; "hem", "ama", "ev" değil
    }

    /// Her kelime için "gizlenecek mi" bayrağı (kelime sırası `FollowAlong.words` ile aynı).
    static func fillerFlags(in text: String) -> [Bool] {
        let words = FollowAlong.words(in: text)
        var flags: [Bool] = []
        flags.reserveCapacity(words.count)
        for (i, word) in words.enumerated() {
            let token = String(text[word.range])
            let norm = normalized(token)
            if isHesitation(norm) {
                flags.append(true)
            } else if markers.contains(norm) {
                let commaAfter = token.last.map { ",;:".contains($0) } ?? false
                let sentenceStart = i == 0 || (String(text[words[i - 1].range]).last.map { ".!?".contains($0) } ?? false)
                flags.append(commaAfter || (sentenceStart && !token.hasSuffix(".")))
            } else {
                flags.append(false)
            }
        }
        return flags
    }

    /// Satırdan dolguları çıkarır. Kimlik, başlangıç/bitiş ve ikincil (çeviri) metin aynen kalır;
    /// altyazı parçalarının kelime sayıları ve kelime zamanları çıkarılan kelimelerle birlikte düşer.
    static func clean(_ row: TranscriptRow) -> TranscriptRow {
        let words = FollowAlong.words(in: row.text)
        let flags = fillerFlags(in: row.text)
        guard flags.contains(true) else { return row }
        // Dolgu dışında kelime kalmıyorsa satır olduğu gibi bırakılır (boş satır kalmasın).
        guard flags.contains(false) else { return row }

        var out = row
        out.text = zip(words, flags).filter { !$0.1 }.map { String(row.text[$0.0.range]) }.joined(separator: " ")

        // Parçalar metinle birebir tutuyorsa kelime sayıları/zamanları tek tek ayıklanır; tutmuyorsa orantılı dağıtım zaten çalışır.
        let ordered = row.spans.sorted { $0.start < $1.start }
        let total = ordered.reduce(0) { $0 + $1.words }
        if total == words.count, !ordered.isEmpty {
            var next = 0
            var spans: [FollowAlong.Span] = []
            for span in ordered {
                let range = next..<min(next + span.words, flags.count)
                next += span.words
                let keep = range.filter { !flags[$0] }
                guard !keep.isEmpty else { continue }
                var s = span
                s.words = keep.count
                if let times = span.times, times.count == span.words {
                    s.times = keep.map { times[$0 - range.lowerBound] }
                }
                spans.append(s)
            }
            out.spans = spans
        }
        return out
    }

    static func clean(_ rows: [TranscriptRow]) -> [TranscriptRow] { rows.map(clean) }
}
