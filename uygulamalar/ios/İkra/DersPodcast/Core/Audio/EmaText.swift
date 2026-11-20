import Foundation

/// EMA-TTS'in metin ön işlemesi (`text.py` içindeki `normalize`): modelin sözlüğü yalnız küçük harf, rakam ve sınırlı noktalama
/// tanır. Sayılar bu katmana gelmeden `TurkishReading` ile yazıya açılmış olur; burada yalnız karakter dönüşümleri, noktalama
/// sadeleştirmesi ve modelin beklediği baş öneki (". ") uygulanır. Sözlük dışı karakterler çalışma zamanında `<unk>` olur.
nonisolated enum EmaText {
    /// Kıvrık tırnak, uzun çizgi ve görünmez boşluklar aynı sesi verir.
    static let punctuation: [Character: String] = [
        "\u{2018}": "'", "\u{2019}": "'", "\u{201A}": "'", "\u{201B}": "'", "\u{2032}": "'", "\u{00B4}": "'", "\u{0060}": "'", "\u{02BC}": "'",
        "\u{201C}": "\"", "\u{201D}": "\"", "\u{201E}": "\"", "\u{00AB}": "\"", "\u{00BB}": "\"", "\u{2033}": "\"",
        "\u{2010}": "-", "\u{2011}": "-", "\u{2012}": "-", "\u{2013}": "-", "\u{2014}": "-", "\u{2015}": "-", "\u{2212}": "-",
        "\u{2026}": "...", "\u{00A0}": " ", "\u{2007}": " ", "\u{202F}": " ", "\u{200B}": "", "\u{FEFF}": "", "\u{200E}": "", "\u{200F}": "",
    ]
    /// Düzeltme işareti neredeyse hiç yazılmaz: katlanır.
    static let circumflex: [Character: Character] = ["â": "a", "Â": "A", "î": "i", "Î": "İ", "û": "u", "Û": "U", "ê": "e", "Ê": "E", "ô": "o", "Ô": "O"]
    static let terminal: Set<Character> = [".", "!", "?"]

    /// Karakter düzeyi dönüşümler (tek kelimede de güvenli): NFC, noktalama eşlemesi, birleşen imlerin atılması, düzeltme işareti,
    /// Türkçe küçük harf (İ → i, I → ı).
    static func base(_ text: String) -> String {
        var mapped = ""
        for character in text.precomposedStringWithCanonicalMapping {
            if let replacement = punctuation[character] { mapped += replacement } else { mapped.append(character) }
        }
        // `İ`.lowercased() gibi dönüşümlerin bıraktığı görünmez birleşen imler (U+0307) ayrı kod noktasıdır: atılır.
        var scalars = String.UnicodeScalarView()
        for scalar in mapped.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark: continue
            default: scalars.append(scalar)
            }
        }
        var folded = ""
        for character in String(scalars) {
            let c = circumflex[character] ?? character
            switch c {
            case "İ": folded.append("i")
            case "I": folded.append("ı")
            default: folded += String(c).lowercased()
            }
        }
        return folded
    }

    /// Tam satır, modele hazır: yinelenen işaretler sadeleşir, noktalamadan önceki boşluk kalkar, sonrasına boşluk gelir, kesme
    /// işareti köke yapışır, satır sonu noktalamayla biter.
    static func normalize(_ text: String, addFinal: Bool = true) -> String {
        var t = base(text)
        t = t.replacing(/\.{2,}/, with: ".")
        t = t.replacing(/[!?]{2,}/) { $0.output.contains("?") ? "?" : "!" }
        t = t.replacing(/,{2,}/, with: ",")
        t = t.replacing(/\s+([.,!?;:])/) { String($0.output.1) }
        t = t.replacing(/([.,!?;:])(?=[^\s\d])/) { "\($0.output.1) " }
        t = t.replacing(/\s*'\s*/, with: "'")
        t = t.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespaces)
        if addFinal, let last = t.last, !terminal.contains(last) {
            while let tail = t.last, ",;:".contains(tail) { t.removeLast() }
            t += "."
        }
        return t
    }

    /// Modele giden metin: normalize edilmiş satır, baş önekiyle (`lead`; model eğitimde her satırı ". " ile gördü).
    static func prepare(_ text: String, lead: String = ". ") -> String {
        let t = normalize(text)
        guard let first = lead.trimmingCharacters(in: .whitespaces).first else { return t }
        return t.hasPrefix(String(first)) ? t : lead + t
    }
}
