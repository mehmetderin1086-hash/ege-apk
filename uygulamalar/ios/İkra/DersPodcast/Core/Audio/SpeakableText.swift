import Foundation

/// #12: Türkçe uyumlu katlama (sunucudaki kuralla aynı).
/// `I`, `İ`, `ı`, `i` → `i`; diğer karakterler tek karaktere inen küçük harfe çevrilir,
/// dönüşüm uzunluğu değiştirirse karakter olduğu gibi kalır. `.caseInsensitive`/`lowercased()` eşleşmede kullanılmaz.
nonisolated enum TurkishFold {
    static func fold(_ c: Character) -> Character {
        switch c {
        case "I", "İ", "ı", "i": return "i"
        default:
            let s = String(c)
            let lower = s.lowercased()
            guard lower.count == 1, lower.unicodeScalars.count == s.unicodeScalars.count, let l = lower.first else { return c }
            return l
        }
    }

    static func fold(_ s: String) -> String { String(s.map { fold($0) }) }

    /// Kelime karakteri (sunucudaki `[\p{L}\p{N}_]`).
    static func isWordCharacter(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
}

/// #11/#12: TTS'e gidecek okunuş katmanı. Transkriptteki yazı değişmez; yalnız motora verilen metin dönüşür.
nonisolated enum SpeakableText {
    struct Result: Sendable {
        var turns: [ScriptTurn]
        /// wordMap[t][k]: konuşulan metindeki k. kelimenin, t. turun ORİJİNAL metnindeki kelime indeksi.
        var wordMap: [[Int]]
    }

    /// Önce telaffuz sözlüğü, sonra Türkçe okunuş (sunucudaki sıra).
    static func prepare(_ turns: [ScriptTurn], language: PodcastLanguage, dictionary: [Pronunciation]) -> Result {
        var out: [ScriptTurn] = []
        var maps: [[Int]] = []
        for turn in turns {
            let (words, map) = spokenWords(turn.text, language: language, dictionary: dictionary)
            var t = turn
            t.text = words.joined(separator: " ")
            out.append(t)
            maps.append(map)
        }
        return Result(turns: out, wordMap: maps)
    }

    static func spoken(_ text: String, language: PodcastLanguage) -> String {
        spokenWords(text, language: language, dictionary: []).words.joined(separator: " ")
    }

    /// Konuşulan kelimeler ve her birinin orijinal metindeki kelime indeksi.
    static func spokenWords(_ text: String, language: PodcastLanguage, dictionary: [Pronunciation]) -> (words: [String], map: [Int]) {
        let chars = Array(text)
        var origins = [Int](repeating: -1, count: chars.count)
        var word = -1
        for i in chars.indices where !chars[i].isWhitespace {
            if i == 0 || chars[i - 1].isWhitespace { word += 1 }
            origins[i] = word
        }
        let replaced = applyDictionary(chars: chars, origins: origins, dictionary: dictionary)
        // Sözlük çıktısını boşluktan kelimelere böl (kelimenin kökeni ilk karakterinin kökeni).
        var tokens: [(text: String, origin: Int)] = []
        var current = ""
        var origin = -1
        for (c, o) in zip(replaced.chars, replaced.origins) {
            if c.isWhitespace {
                if !current.isEmpty { tokens.append((current, origin)) }
                current = ""
            } else {
                if current.isEmpty { origin = o }
                current.append(c)
            }
        }
        if !current.isEmpty { tokens.append((current, origin)) }

        guard language == .tr else { return (tokens.map(\.text), tokens.map { max(0, $0.origin) }) }
        let spoken = TurkishReading.read(tokens.map(\.text))
        var words: [String] = []
        var map: [Int] = []
        for (i, group) in spoken.enumerated() {
            for w in group where !w.isEmpty {
                words.append(w)
                map.append(max(0, tokens[i].origin))
            }
        }
        return (words, map)
    }

    // MARK: - Telaffuz sözlüğü

    /// Sözlüğü uygular: eşleşme katlanmış kopyada aranır, değiştirme orijinalde yapılır; kelime sınırı gözetilir.
    /// Tek geçiştir, uzun ifade önce denenir, aynı anahtarın ilk kaydı geçerlidir (sunucuyla aynı).
    static func applyDictionary(_ text: String, dictionary: [Pronunciation]) -> String {
        let chars = Array(text)
        return String(applyDictionary(chars: chars, origins: Array(repeating: 0, count: chars.count), dictionary: dictionary).chars)
    }

    /// İstek sözlüğünü seçerken de uygularken de aynı Türkçe katlama ve tam sözcük sınırı kullanılır.
    /// Girdi sırası korunur; metindeki noktalama, I/İ/ı/i ve birden çok sözcüklü kayıtlar desteklenir.
    static func matchingEntries(in texts: [String], dictionary: [Pronunciation]) -> [Pronunciation] {
        let prepared = texts.map { text -> (chars: [Character], folded: [Character]) in
            let chars = Array(text)
            return (chars, chars.map { TurkishFold.fold($0) })
        }
        return dictionary.filter { entry in
            let key = Array(TurkishFold.fold(entry.from.trimmingCharacters(in: .whitespacesAndNewlines)))
            guard !key.isEmpty else { return false }
            return prepared.contains { text in
                text.chars.indices.contains { matches(key, at: $0, chars: text.chars, folded: text.folded) }
            }
        }
    }

    private static func matches(_ key: [Character], at start: Int, chars: [Character], folded: [Character]) -> Bool {
        let end = start + key.count
        guard !key.isEmpty, start >= 0, end <= chars.count,
              start == 0 || !TurkishFold.isWordCharacter(chars[start - 1]),
              end == chars.count || !TurkishFold.isWordCharacter(chars[end]) else { return false }
        return folded[start..<end].elementsEqual(key)
    }

    static func applyDictionary(chars: [Character], origins: [Int], dictionary: [Pronunciation]) -> (chars: [Character], origins: [Int]) {
        var seen = Set<String>()
        var entries: [(key: [Character], to: [Character])] = []
        for p in dictionary {
            let from = p.from.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !from.isEmpty else { continue }
            let key = TurkishFold.fold(from)
            guard seen.insert(key).inserted else { continue }
            entries.append((Array(key), Array(p.to)))
        }
        guard !entries.isEmpty, !chars.isEmpty else { return (chars, origins) }
        entries.sort { $0.key.count > $1.key.count }
        let folded = chars.map { TurkishFold.fold($0) }
        var outChars: [Character] = []
        var outOrigins: [Int] = []
        outChars.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            var matched = false
            if i == 0 || !TurkishFold.isWordCharacter(chars[i - 1]) {
                for entry in entries {
                    let end = i + entry.key.count
                    guard matches(entry.key, at: i, chars: chars, folded: folded) else { continue }
                    let o = origins[i]
                    outChars += entry.to
                    outOrigins += Array(repeating: o, count: entry.to.count)
                    i = end
                    matched = true
                    break
                }
            }
            if !matched {
                outChars.append(chars[i])
                outOrigins.append(origins[i])
                i += 1
            }
        }
        return (outChars, outOrigins)
    }
}

/// Türkçe okunuş kuralları: sayılar, yüzdeler, tarih ekleri, Roma rakamları, birimler, alt/üst simgeler.
/// Ortak vektörler: `docs/spoken-tr-vectors.json`.
nonisolated enum TurkishReading {
    static let ones = ["", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz"]
    static let tens = ["", "on", "yirmi", "otuz", "kırk", "elli", "altmış", "yetmiş", "seksen", "doksan"]
    static let scales = ["", "bin", "milyon", "milyar", "trilyon", "katrilyon", "kentilyon"]
    static let vowels: Set<Character> = ["a", "e", "ı", "i", "o", "ö", "u", "ü", "â", "î", "û"]
    private static let apostrophes: Set<Character> = ["'", "’"]
    private static let leading: Set<Character> = ["(", "[", "{", "\"", "“", "‘", "«", "„"]
    private static let trailing: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "]", "}", "\"", "”", "’", "»", "…"]
    private static let sentenceEnd: Set<Character> = [".", "!", "?", "…", ":"]
    private static let superscripts: [Character: Character] = ["⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "-", "⁺": "+"]
    private static let subscripts: [Character: Character] = ["₀": "0", "₁": "1", "₂": "2", "₃": "3", "₄": "4", "₅": "5", "₆": "6", "₇": "7", "₈": "8", "₉": "9", "₊": "+", "₋": "-"]

    static let months = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]
    /// Sunucudaki kısaltmalar (noktasıyla).
    static let abbreviations: [String: String] = [
        "M.Ö.": "milattan önce", "M.S.": "milattan sonra", "vb.": "ve benzeri", "vs.": "vesaire", "örn.": "örneğin",
        "bkz.": "bakınız", "yy.": "yüzyıl", "Prof.": "Profesör", "Doç.": "Doçent", "Dr.": "Doktor",
    ]
    static let symbols: [Character: String] = ["≈": "yaklaşık", "±": "artı eksi", "×": "çarpı", "÷": "bölü", "≤": "küçük eşit", "≥": "büyük eşit"]

    static let units: [String: String] = [
        "km": "kilometre", "m": "metre", "cm": "santimetre", "mm": "milimetre", "dm": "desimetre",
        "µm": "mikrometre", "μm": "mikrometre", "nm": "nanometre",
        "kg": "kilogram", "g": "gram", "mg": "miligram", "µg": "mikrogram", "μg": "mikrogram",
        "L": "litre", "l": "litre", "lt": "litre", "mL": "mililitre", "ml": "mililitre", "dL": "desilitre", "dl": "desilitre", "cL": "santilitre", "cl": "santilitre",
        "sa": "saat", "dk": "dakika", "sn": "saniye", "s": "saniye", "ms": "milisaniye",
        "Hz": "hertz", "kHz": "kilohertz", "MHz": "megahertz", "GHz": "gigahertz",
        "W": "vat", "kW": "kilovat", "MW": "megavat", "kWh": "kilovatsaat", "Wh": "vatsaat",
        "V": "volt", "mV": "milivolt", "kV": "kilovolt", "mA": "miliamper",
        "N": "nevton", "J": "jul", "kJ": "kilojul", "cal": "kalori", "kcal": "kilokalori",
        "Pa": "paskal", "kPa": "kilopaskal", "atm": "atmosfer", "mmHg": "milimetre cıva", "bar": "bar",
        "mol": "mol", "K": "kelvin", "°C": "santigrat derece", "°F": "fahrenhayt derece", "°": "derece",
        "Ω": "ohm", "dB": "desibel", "kB": "kilobayt", "KB": "kilobayt", "MB": "megabayt", "GB": "gigabayt", "TB": "terabayt",
    ]
    /// Yalnız sayıdan sonra birim sayılanlar (tek başına sıradan kelime ya da harf olabilir).
    static let numberOnlyUnits: Set<String> = ["m", "g", "L", "l", "s", "sa", "dk", "sn", "W", "V", "N", "J", "K", "°", "bar", "mol", "cal", "Pa"]
    private static let lengthUnits: Set<String> = ["km", "m", "cm", "mm", "dm", "µm", "μm", "nm"]
    private static let letterNames: [Character: String] = [
        "A": "a", "B": "be", "C": "ce", "Ç": "çe", "D": "de", "E": "e", "F": "fe", "G": "ge", "Ğ": "yumuşak ge", "H": "ha",
        "I": "ı", "İ": "i", "J": "je", "K": "ka", "L": "le", "M": "me", "N": "ne", "O": "o", "Ö": "ö", "P": "pe", "Q": "kü",
        "R": "re", "S": "se", "Ş": "şe", "T": "te", "U": "u", "Ü": "ü", "V": "ve", "W": "çift ve", "X": "iks", "Y": "ye", "Z": "ze",
    ]

    // MARK: Belirteçler

    /// Her giriş kelimesi için konuşulan kelimeler (noktalama korunur).
    static func read(_ tokens: [String]) -> [[String]] {
        var result: [[String]] = []
        var previousNumeric = false
        for (i, token) in tokens.enumerated() {
            let (lead, core, t) = split(token)
            var trail = t
            var words: [String]?
            // Kısaltma: "M.Ö.", "vb.", "Dr."; tek başına "MÖ"; ayrık "%" ("% 15").
            if trail.first == ".", let full = abbreviations[core + "."] {
                words = full.split(separator: " ").map(String.init)
                trail.removeFirst()
            } else if core == "MÖ" {
                words = ["milattan", "önce"]
            } else if core == "%", tokens.indices.contains(i + 1), split(tokens[i + 1]).core.first.map({ $0.isASCII && $0.isNumber }) == true {
                words = ["yüzde"]
            } else if core.count == 1, let first = core.first, let symbol = symbols[first] {
                words = symbol.split(separator: " ").map(String.init)
            }
            // Sıra sayısı: "3. sınıf", "II. Dünya", "XV. yüzyıl" (nokta sıra ekidir, cümle sonu değil).
            if words == nil, trail.first == ".", tokens.indices.contains(i + 1) {
                let next = split(tokens[i + 1])
                if next.lead.isEmpty, let first = next.core.first, first.isLetter {
                    let upper = first.isUppercase
                    if isDigits(core), !upper || ordinalBeforeCapital(tokens, at: i) {
                        words = ordinalWords(core, capitalized: upper)
                    } else if let value = romanValue(core), core.count > 1 || ["I", "V", "X"].contains(core), !upper || value <= 40 {
                        words = ordinalWords(String(value), capitalized: upper)
                    }
                    if words != nil { trail.removeFirst() }
                }
            }
            var out = words ?? readCore(core, previousNumeric: previousNumeric) ?? [core]
            if out.isEmpty { out = [core] }
            if !lead.isEmpty { out[0] = lead + out[0] }
            if !trail.isEmpty { out[out.count - 1] += trail }
            result.append(out)
            previousNumeric = core.contains { $0.isASCII && $0.isNumber } && trail.isEmpty
        }
        return result
    }

    private static let linkingWords: Set<String> = ["ve", "veya", "ile", "ya", "hem", "ama", "fakat", "ancak", "bu", "şu", "her"]

    /// Sayı + nokta + büyük harfli kelime açıkça sıra sayısı mı (sunucudaki `ordinalBeforeCapital` ile aynı kural)?
    /// Cümle başında, bağlaçtan ("1. ve 2. Dünya") ya da kısaltmadan ("TBMM 2. Dönem") sonra evet; büyük harfli
    /// addan sonra yalnız ad cümle başında değilse ("… Atatürk 1. Meclis"). Diğerleri ("Cevap 2. Şimdi") sıra değil.
    static func ordinalBeforeCapital(_ tokens: [String], at i: Int) -> Bool {
        func opensSentence(_ k: Int) -> Bool { k == 0 || tokens[k - 1].last.map { sentenceEnd.contains($0) } == true }
        if opensSentence(i) { return true }
        var word = Substring(tokens[i - 1])
        while let f = word.first, leading.contains(f) { word.removeFirst() }
        // Noktalamayla biten kelime ("sonuç,") bağ kurmaz.
        guard let last = word.last, last.isLetter else { return false }
        if linkingWords.contains(word.lowercased(with: Locale(identifier: "tr_TR"))) { return true }
        // Kesme işaretinden sonraki ek ayrılır ("TBMM'nin", "Atatürk'ün").
        let stem = word.split(maxSplits: 1, omittingEmptySubsequences: false) { apostrophes.contains($0) }.first ?? word
        guard let first = stem.first, first.isUppercase else { return false }
        if stem.count >= 2, stem.allSatisfy({ $0.isUppercase }) { return true }
        return stem.dropFirst().allSatisfy { $0.isLowercase } && !opensSentence(i - 1)
    }

    /// Belirteci baştaki noktalama, çekirdek ve sondaki noktalamaya ayırır.
    static func split(_ token: String) -> (lead: String, core: String, trail: String) {
        var chars = Array(token)
        var lead = ""
        while let f = chars.first, leading.contains(f), chars.count > 1 {
            lead.append(f)
            chars.removeFirst()
        }
        var trail: [Character] = []
        while let l = chars.last, trailing.contains(l), chars.count > 1 {
            trail.insert(l, at: 0)
            chars.removeLast()
        }
        return (lead, String(chars), String(trail))
    }

    // MARK: Çekirdek okuma

    static func readCore(_ raw: String, previousNumeric: Bool) -> [String]? {
        guard !raw.isEmpty else { return nil }
        // Kesme işaretli ek: 1990'larda, %50'si, 08.15'te
        if let cut = raw.lastIndex(where: { apostrophes.contains($0) }), cut != raw.startIndex {
            let base = String(raw[..<cut])
            let suffix = String(raw[raw.index(after: cut)...])
            if !suffix.isEmpty, suffix.allSatisfy(\.isLetter),
               base.contains(where: { $0.isNumber || $0 == "%" }) || unitWords(base, previousNumeric: previousNumeric) != nil,
               var words = readCore(base, previousNumeric: previousNumeric), !words.isEmpty {
                words[words.count - 1] = attach(words[words.count - 1], suffix: suffix)
                return words
            }
        }
        // Bitişik simge: "2±0,5", "3×4".
        if raw.count > 1, let cut = raw.firstIndex(where: { symbols[$0] != nil }) {
            let left = String(raw[..<cut]), right = String(raw[raw.index(after: cut)...])
            let symbol = symbols[raw[cut]]!.split(separator: " ").map(String.init)
            return (left.isEmpty ? [] : readCore(left, previousNumeric: previousNumeric) ?? [left]) + symbol
                + (right.isEmpty ? [] : readCore(right, previousNumeric: true) ?? [right])
        }
        let hasDigit = raw.contains { $0.isNumber && $0.isASCII }
        if !hasDigit {
            if let unit = unitWords(raw, previousNumeric: previousNumeric) { return unit }
            if raw.contains(where: { subscripts[$0] != nil || superscripts[$0] != nil }) { return formulaWords(raw) }
            return nil
        }
        if let n = number(raw) { return n }
        // Yüzde
        if raw.hasPrefix("%"), let n = number(String(raw.dropFirst())) { return ["yüzde"] + n }
        if raw.hasSuffix("%"), let n = number(String(raw.dropLast())) { return ["yüzde"] + n }
        // Eksi
        if let f = raw.first, f == "-" || f == "−" || f == "–", let n = number(String(raw.dropFirst())) { return ["eksi"] + n }
        // Aralık: 3-5, 1914–1918
        for dash in ["-", "–"] {
            let parts = raw.components(separatedBy: dash)
            if parts.count == 2, let a = number(parts[0]), let b = number(parts[1]) { return a + ["ile"] + b }
        }
        // Kesir: 3/4 → dörtte üç
        let slash = raw.split(separator: "/", omittingEmptySubsequences: false)
        if slash.count == 2, isDigits(String(slash[0])), isDigits(String(slash[1])), !slash[1].allSatisfy({ $0 == "0" }) {
            var denominator = cardinal(String(slash[1]))
            denominator[denominator.count - 1] = locative(denominator[denominator.count - 1])
            return denominator + cardinal(String(slash[0]))
        }
        // Üs: 10³, 2²
        if let power = powerWords(raw) { return power }
        // Sayı + birim bitişik: 37°C, 5km, 90°
        if let glued = numberWithUnit(raw) { return glued }
        // Alt simge: H₂O
        if raw.contains(where: { subscripts[$0] != nil }) { return formulaWords(raw) }
        // Harf ve rakam karışık: B12, COVID-19, 5G
        return mixedWords(raw)
    }

    /// Düz sayı biçimleri: 1.250,5 · 3,14 · 1.000.000 · 1990 · 14.30 (saat) · 2.5 (nokta).
    static func number(_ s: String) -> [String]? {
        guard let first = s.first, first.isASCII, first.isNumber else { return nil }
        let colon = s.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if colon.count > 1 {
            guard colon.count == 2, isDigits(colon[0]), colon[0].count <= 2, isDigits(colon[1]), colon[1].count == 2,
                  let h = Int(colon[0]), let m = Int(colon[1]), h <= 24, m <= 59 else { return nil }
            return clock(h, colon[1])
        }
        if let date = date(s) { return date }
        let commaParts = s.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard commaParts.count <= 2 else { return nil }
        let integer = commaParts[0]
        let fraction = commaParts.count == 2 ? commaParts[1] : nil
        if let fraction, !isDigits(fraction) { return nil }
        let groups = integer.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var words: [String]
        if groups.count == 1 {
            guard isDigits(integer) else { return nil }
            // Baştaki sıfırlı tamsayı rakam rakam okunur ("007" → sıfır sıfır yedi).
            words = integer.count > 1 && integer.first == "0" && fraction == nil
                ? integer.map { cardinal(String($0)) }.flatMap { $0 }
                : cardinal(integer)
        } else if groups.allSatisfy(isDigits), (1...3).contains(groups[0].count), groups.dropFirst().allSatisfy({ $0.count == 3 }) {
            words = cardinal(groups.joined())
        } else if fraction == nil, groups.count == 2, groups.allSatisfy(isDigits), groups[0].count <= 2, groups[1].count == 2,
                  let h = Int(groups[0]), let m = Int(groups[1]), h <= 24, m <= 59 {
            return clock(h, groups[1])
        } else if fraction == nil, groups.allSatisfy({ isDigits($0) }) {
            return Array(groups.map { cardinal($0) }.joined(separator: ["nokta"]))
        } else {
            return nil
        }
        if let fraction { words += ["virgül"] + digitsWords(fraction) }
        return words
    }

    /// Saat: 14.30 → on dört otuz; 09.05 → dokuz sıfır beş; 14.00 → on dört.
    static func clock(_ hour: Int, _ minutes: String) -> [String] {
        if minutes == "00" { return cardinal(String(hour)) }
        return cardinal(String(hour)) + (minutes.first == "0" ? ["sıfır"] + cardinal(minutes) : cardinal(minutes))
    }

    /// Tarih: 19.05.2024 ya da 19/05/2024 → on dokuz Mayıs iki bin yirmi dört.
    static func date(_ s: String) -> [String]? {
        for separator: Character in [".", "/"] {
            let parts = s.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, parts.allSatisfy(isDigits), parts[0].count <= 2, parts[1].count <= 2, parts[2].count == 4,
                  let d = Int(parts[0]), let m = Int(parts[1]), (1...31).contains(d), (1...12).contains(m) else { continue }
            return cardinal(String(d)) + [months[m - 1]] + cardinal(parts[2])
        }
        return nil
    }

    /// Ondalık kısım: baştaki sıfırlar tek tek, kalanı sayı olarak.
    static func digitsWords(_ s: String) -> [String] {
        let zeros = s.prefix { $0 == "0" }.count
        let rest = s.dropFirst(zeros)
        return Array(repeating: "sıfır", count: zeros) + (rest.isEmpty ? [] : cardinal(String(rest)))
    }

    static func isDigits(_ s: String) -> Bool { !s.isEmpty && s.allSatisfy { $0.isASCII && $0.isNumber } }

    /// Tamsayının Türkçe okunuşu (kelime dizisi).
    static func cardinal(_ digits: String) -> [String] {
        let trimmed = String(digits.drop { $0 == "0" })
        guard !trimmed.isEmpty else { return ["sıfır"] }
        if trimmed.count > 3 * scales.count { return trimmed.map { cardinal(String($0)) }.flatMap { $0 } }
        var groups: [Int] = []
        var rest = Substring(trimmed)
        while !rest.isEmpty {
            let take = min(3, rest.count)
            groups.append(Int(rest.suffix(take)) ?? 0)
            rest = rest.dropLast(take)
        }
        var words: [String] = []
        for (scale, group) in groups.enumerated().reversed() where group > 0 {
            if scale == 1, group == 1 { words.append("bin"); continue }
            words += under1000(group)
            if scale > 0 { words.append(scales[scale]) }
        }
        return words
    }

    static func under1000(_ n: Int) -> [String] {
        var w: [String] = []
        let h = n / 100, t = (n / 10) % 10, o = n % 10
        if h == 1 { w.append("yüz") } else if h > 1 { w += [ones[h], "yüz"] }
        if t > 0 { w.append(tens[t]) }
        if o > 0 { w.append(ones[o]) }
        return w
    }

    static func ordinalWords(_ digits: String, capitalized: Bool) -> [String] {
        var words = cardinal(digits)
        words[words.count - 1] = ordinal(words[words.count - 1])
        if capitalized { words[0] = capitalize(words[0]) }
        return words
    }

    /// bir → birinci, dört → dördüncü, altı → altıncı.
    static func ordinal(_ word: String) -> String {
        let base = word == "dört" ? "dörd" : word
        let v = harmony4(base)
        return (base.last.map { vowels.contains($0) } ?? false) ? base + "nc" + v : base + v + "nc" + v
    }

    /// Kesme işaretli eki kelimeye ekler (dört + ün → dördün).
    static func attach(_ word: String, suffix: String) -> String {
        if word == "dört", let f = suffix.first, vowels.contains(TurkishFold.fold(f)) { return "dörd" + suffix }
        return word + suffix
    }

    /// Bulunma eki: dört → dörtte, iki → ikide, altı → altıda.
    static func locative(_ word: String) -> String {
        let back = lastVowel(word).map { "aıouâû".contains($0) } ?? false
        let voiceless = word.last.map { "fstkçşhp".contains($0) } ?? false
        return word + (voiceless ? "t" : "d") + (back ? "a" : "e")
    }

    private static func lastVowel(_ word: String) -> Character? { word.last { vowels.contains($0) } }

    private static func harmony4(_ word: String) -> String {
        switch lastVowel(word) {
        case "a", "ı", "â": "ı"
        case "o", "u", "û": "u"
        case "ö", "ü": "ü"
        default: "i"
        }
    }

    static func capitalize(_ word: String) -> String {
        guard let f = word.first else { return word }
        let head = f == "i" ? "İ" : f == "ı" ? "I" : String(f).uppercased()
        return head + word.dropFirst()
    }

    // MARK: Roma rakamları

    static func romanValue(_ s: String) -> Int? {
        // D ve M dışarıda: "CD", "MIX" gibi kısaltmalar sıra sayısına dönmesin.
        let map: [Character: Int] = ["I": 1, "V": 5, "X": 10, "L": 50, "C": 100]
        guard !s.isEmpty, s.count <= 9, s.allSatisfy({ map[$0] != nil }) else { return nil }
        var total = 0
        let values = s.map { map[$0]! }
        for (i, v) in values.enumerated() {
            if i + 1 < values.count, v < values[i + 1] { total -= v } else { total += v }
        }
        guard total > 0, total < 4000, roman(total) == s else { return nil }
        return total
    }

    static func roman(_ n: Int) -> String {
        let table: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                                      (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var n = n
        var out = ""
        for (value, symbol) in table {
            while n >= value { out += symbol; n -= value }
        }
        return out
    }

    // MARK: Birimler, üsler, formüller

    /// Tek başına birim ya da bileşik birim (km/sa, m/s², g/mol).
    static func unitWords(_ raw: String, previousNumeric: Bool) -> [String]? {
        let parts = raw.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 1 {
            guard let words = unitPart(raw, compound: false) else { return nil }
            if numberOnlyUnits.contains(raw), !previousNumeric { return nil }
            return words
        }
        guard parts.count <= 3 else { return nil }
        var words: [String] = []
        for (i, part) in parts.enumerated() {
            guard let w = unitPart(part, compound: true) else { return nil }
            if i > 0 { words.append("bölü") }
            words += w
        }
        return words
    }

    private static func unitPart(_ part: String, compound: Bool) -> [String]? {
        var base = part
        var exponent: String?
        if let last = part.last, let digit = superscripts[last], digit.isNumber {
            base = String(part.dropLast())
            exponent = String(digit)
        }
        guard let word = units[base] else { return nil }
        guard let exponent else { return word.split(separator: " ").map(String.init) }
        if lengthUnits.contains(base), exponent == "2" || exponent == "3" { return [word + (exponent == "2" ? "kare" : "küp")] }
        return word.split(separator: " ").map(String.init) + exponentWords(exponent)
    }

    private static func exponentWords(_ e: String) -> [String] {
        switch e {
        case "2": ["kare"]
        case "3": ["küp"]
        default: ["üssü"] + (e.hasPrefix("-") ? ["eksi"] + cardinal(String(e.dropFirst())) : cardinal(e))
        }
    }

    /// 10³ → on üzeri üç; 2² → iki üzeri iki.
    static func powerWords(_ raw: String) -> [String]? {
        guard let start = raw.firstIndex(where: { superscripts[$0] != nil }) else { return nil }
        let base = String(raw[..<start])
        let exp = String(raw[start...].map { superscripts[$0] ?? "?" })
        guard !base.isEmpty, !exp.contains("?"), exp.contains(where: \.isNumber), let b = number(base) else { return nil }
        let e = exp.replacingOccurrences(of: "+", with: "")
        // Sayının kuvveti "üzeri" ile okunur (10³ → on üzeri üç; sunucuyla aynı). Birimlerde kare/küp kalır.
        return b + ["üzeri"] + (e.hasPrefix("-") ? ["eksi"] + cardinal(String(e.dropFirst())) : cardinal(e))
    }

    /// 37°C, 5km, 90° gibi bitişik yazımlar.
    static func numberWithUnit(_ raw: String) -> [String]? {
        guard let cut = raw.firstIndex(where: { !($0.isASCII && ($0.isNumber || $0 == "," || $0 == ".")) }), cut != raw.startIndex else { return nil }
        let head = String(raw[..<cut])
        let tail = String(raw[cut...])
        guard let n = number(head) else { return nil }
        if tail == "%" { return ["yüzde"] + n }
        guard let unit = unitWords(tail, previousNumeric: true) else { return nil }
        return n + unit
    }

    /// Kimyasal formül: H₂O → ha iki o; CO₂ → ce o iki.
    static func formulaWords(_ raw: String) -> [String]? {
        var words: [String] = []
        var digits = ""
        let uppercase = raw.contains { $0.isUppercase }
        func flush() {
            guard !digits.isEmpty else { return }
            words += cardinal(digits)
            digits = ""
        }
        for c in raw {
            if let d = subscripts[c] ?? superscripts[c] {
                if d.isNumber { digits.append(d) } else { flush(); words.append(d == "+" ? "artı" : "eksi") }
            } else if c.isASCII, c.isNumber {
                digits.append(c)
            } else if c.isLetter {
                flush()
                let key: Character? = c == "i" ? "İ" : c == "ı" ? "I" : String(c).uppercased().count == 1 ? String(c).uppercased().first : nil
                if uppercase, let key, let name = letterNames[key] { words += name.split(separator: " ").map(String.init) } else { words.append(String(c)) }
            } else {
                flush()
            }
        }
        flush()
        return words.isEmpty ? nil : words
    }

    /// Harf-rakam karışık belirteçte rakam koşuları okunur, harfler kalır (B12 → B on iki).
    static func mixedWords(_ raw: String) -> [String]? {
        guard raw.allSatisfy({ $0.isLetter || ($0.isASCII && $0.isNumber) || $0 == "-" }) else { return nil }
        var words: [String] = []
        var run = ""
        var runIsDigit = false
        func flush() {
            guard !run.isEmpty else { return }
            words += runIsDigit ? cardinal(run) : [run]
            run = ""
        }
        for c in raw {
            if c == "-" { flush(); continue }
            let digit = c.isASCII && c.isNumber
            if !run.isEmpty, digit != runIsDigit { flush() }
            runIsDigit = digit
            run.append(c)
        }
        flush()
        return words.isEmpty ? nil : words
    }
}
