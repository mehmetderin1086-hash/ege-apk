import Foundation

// Araç kutusunun saf mantığı: ağ ve arayüz yok, tamamı test edilir.

nonisolated enum ExamMath {
    /// Net = doğru − yanlış / ceza (ceza 0 → yanlış götürmez).
    static func net(correct: Int, wrong: Int, penalty: Int) -> Double {
        penalty > 0 ? Double(correct) - Double(wrong) / Double(penalty) : Double(correct)
    }
}

nonisolated enum MockExamStats {
    /// En az iki denemede geçen ders adları (yazım farkı `AnswerMatch.normalize` ile katlanır); en yeni denemedeki yazılış ve sıra korunur.
    static func lessons(_ exams: [MockExam]) -> [String] {
        var counts: [String: Int] = [:], names: [String] = [], seen: Set<String> = []
        for exam in exams.sorted(by: { $0.date > $1.date }) {
            var inExam: Set<String> = []
            for row in exam.rows {
                let key = AnswerMatch.normalize(row.name)
                guard !key.isEmpty, inExam.insert(key).inserted else { continue }
                counts[key, default: 0] += 1
                if seen.insert(key).inserted { names.append(row.name.trimmingCharacters(in: .whitespaces)) }
            }
        }
        return names.filter { (counts[AnswerMatch.normalize($0)] ?? 0) >= 2 }
    }

    /// Tarihe göre artan net dizisi. `lesson` nil → denemenin toplam neti; değilse o dersin satırlarının neti (dersi içermeyen deneme atlanır).
    static func series(_ exams: [MockExam], lesson: String?) -> [(date: Date, net: Double)] {
        let key = lesson.map(AnswerMatch.normalize)
        return exams.sorted { $0.date < $1.date }.compactMap { exam -> (date: Date, net: Double)? in
            guard let key else { return (exam.date, exam.net) }
            let rows = exam.rows.filter { AnswerMatch.normalize($0.name) == key }
            guard !rows.isEmpty else { return nil }
            return (exam.date, rows.reduce(0) { $0 + ExamMath.net(correct: $1.correct, wrong: $1.wrong, penalty: exam.penalty) })
        }
    }
}

/// Soru kronometresi tur özeti (süreler saniye).
nonisolated struct LapStats: Equatable, Sendable {
    let count: Int
    let average, fastest, slowest: Double
    let overTarget: Int

    init(laps: [Double], target: Double) {
        count = laps.count
        average = laps.isEmpty ? 0 : laps.reduce(0, +) / Double(laps.count)
        fastest = laps.min() ?? 0
        slowest = laps.max() ?? 0
        overTarget = laps.filter { $0 > target }.count
    }

    /// Son turu geri alır: tur diziden çıkar; dönen tarih o turun başladığı andır (süren soru oradan devam eder). Geri alınacak tur yoksa nil ve dizi değişmez.
    static func undoLast(laps: inout [Double], lastLapAt: Date?) -> Date? {
        guard let lastLapAt, let last = laps.popLast() else { return nil }
        return lastLapAt.addingTimeInterval(-last)
    }
}

nonisolated enum GradeMath {
    /// Ağırlıklı ortalama; ağırlık toplamı 0 ise nil.
    static func average(_ items: [(score: Double, weight: Double)]) -> Double? {
        let total = items.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return nil }
        return items.reduce(0) { $0 + $1.score * $1.weight } / total
    }

    /// Kalan ağırlıkta (100 − girilenler) hedefe ulaşmak için gereken not; kalan yoksa nil.
    static func needed(_ items: [(score: Double, weight: Double)], target: Double) -> Double? {
        let remaining = 100 - items.reduce(0) { $0 + $1.weight }
        guard remaining > 0.0001 else { return nil }
        let earned = items.reduce(0) { $0 + $1.score * $1.weight } / 100
        return (target - earned) * 100 / remaining
    }
}

nonisolated enum Streak {
    /// Bugün (bugün işaretli değilse dün) biten ardışık gün sayısı.
    static func current(days: Set<String>, today: Date = .now, calendar: Calendar = .current) -> Int {
        var cursor = calendar.startOfDay(for: today)
        if !days.contains(DayKey.key(cursor, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(DayKey.key(cursor, calendar: calendar)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    /// En uzun ardışık gün dizisi.
    static func best(days: Set<String>, calendar: Calendar = .current) -> Int {
        let dates = days.compactMap { DayKey.date($0, calendar: calendar) }.sorted()
        var best = 0, run = 0
        var previous: Date?
        for date in dates {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous), calendar.isDate(next, inSameDayAs: date) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = date
        }
        return best
    }
}

nonisolated enum HabitWeek {
    /// Bugünde biten 7 gün (eskiden yeniye). Hepsi gün başlangıcıdır: aynı gün içinde her çağrı aynı diziyi verir (liste kimliği sabit kalır).
    static func days(ending today: Date = .now, calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: today)
        return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: start) }.map { calendar.startOfDay(for: $0) }
    }

    /// İki harfli gün adı. Türkçe dar adlar (P-S-Ç-P-C-C-P) birbirine karışıyor.
    static func label(_ date: Date, calendar: Calendar = .current) -> String {
        let names = ["Pz", "Pt", "Sa", "Ça", "Pe", "Cu", "Ct"]
        let index = calendar.component(.weekday, from: date) - 1
        return names.indices.contains(index) ? names[index] : ""
    }
}

nonisolated enum GoalMath {
    enum Status: Equatable, Sendable { case done, overdue(missing: Int), remaining(days: Int, perDay: Int) }

    static let maxCount = 100_000

    /// Biten hedef son günü geçse de `.done`; bitmemiş ve son günü yoksa nil. `perDay`: kalan günlere bölünmüş eksik (yukarı yuvarlanır; son gün bugünse eksiğin tamamı).
    static func status(done: Int, target: Int, deadline: Date?, today: Date = .now, calendar: Calendar = .current) -> Status? {
        if done >= target { return .done }
        guard let deadline else { return nil }
        let missing = target - done
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: deadline)).day ?? 0
        if days < 0 { return .overdue(missing: missing) }
        return .remaining(days: days, perDay: Int((Double(missing) / Double(max(1, days))).rounded(.up)))
    }

    /// Uyarı penceresindeki metin alanından sayı: yalnız rakamlar okunur; rakam yoksa nil.
    static func count(from text: String) -> Int? {
        Int(String(text.filter { $0.isASCII && $0.isNumber }.prefix(9)))
    }
}

nonisolated enum JournalLogic {
    /// Kendiliğinden kaydetmeye değer mi: bir alan dolu ya da ruh hali varsayılandan (3) farklı.
    static func hasContent(_ entry: JournalEntry) -> Bool {
        entry.mood != 3 || !(entry.learned + entry.hard + entry.tomorrow).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Taslak kendiliğinden kaydedilsin mi: depodakinden farklıysa ve içerik varsa. O günün kaydı zaten varsa boşaltılmış taslak da
    /// kaydedilir (kullanıcı sildi); kaydı olmayan günün boş taslağı ise dosyaya yazılmaz.
    static func needsSave(_ draft: JournalEntry, stored: JournalEntry?) -> Bool {
        draft != stored && (stored != nil || hasContent(draft))
    }

    /// Bugünden önceki en yeni girdi; onun "Yarın ilk işim" notu boşsa nil (daha eski güne bakılmaz: o plan artık geçerli değil).
    static func carryOver(_ entries: [JournalEntry], todayKey: String) -> JournalEntry? {
        guard let latest = entries.filter({ $0.day < todayKey }).max(by: { $0.day < $1.day }),
              !latest.tomorrow.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return latest
    }

    /// Devreden not tam dünün girdisinden mi (başlık "Dünden planın" mı olacak)?
    static func isYesterday(_ day: String, todayKey: String, calendar: Calendar = .current) -> Bool {
        guard let today = DayKey.date(todayKey, calendar: calendar), let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return false }
        return DayKey.key(yesterday, calendar: calendar) == day
    }
}

nonisolated enum RevisionPlan {
    /// İlk çalışmadan sonraki tekrar günleri (unutma eğrisi: 1-3-7-14-30).
    static let intervals = [1, 3, 7, 14, 30]

    /// Sıradaki tekrar günü; tüm adımlar bittiyse nil. `anchor` son çalışılan gündür.
    static func nextDue(anchor: Date, doneSteps: Int, calendar: Calendar = .current) -> Date? {
        guard doneSteps >= 0, doneSteps < intervals.count else { return nil }
        let gap = intervals[doneSteps] - (doneSteps > 0 ? intervals[doneSteps - 1] : 0)
        return calendar.date(byAdding: .day, value: gap, to: calendar.startOfDay(for: anchor))
    }

    static func isDue(_ due: Date?, today: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let due else { return false }
        return due <= calendar.startOfDay(for: today)
    }
}

nonisolated enum MentalMath {
    struct Problem: Equatable, Sendable { var text: String; var answer: Int }

    /// 1 = toplama/çıkarma (≤20), 2 = iki basamak + çarpım tablosu, 3 = büyük sayılar + bölme. Cevap hiç negatif olmaz.
    static func problem<R: RandomNumberGenerator>(level: Int, using rng: inout R) -> Problem {
        let ops: [Character] = level <= 1 ? ["+", "−"] : level == 2 ? ["+", "−", "×"] : ["+", "−", "×", "÷"]
        let op = ops.randomElement(using: &rng) ?? "+"
        let top = level <= 1 ? 20 : level == 2 ? 100 : 500
        switch op {
        case "−":
            let a = Int.random(in: 1...top, using: &rng), b = Int.random(in: 0...a, using: &rng)
            return Problem(text: "\(a) − \(b)", answer: a - b)
        case "×":
            let a = Int.random(in: 2...(level == 2 ? 10 : 20), using: &rng), b = Int.random(in: 2...(level == 2 ? 10 : 12), using: &rng)
            return Problem(text: "\(a) × \(b)", answer: a * b)
        case "÷":
            let b = Int.random(in: 2...12, using: &rng), q = Int.random(in: 2...20, using: &rng)
            return Problem(text: "\(b * q) ÷ \(b)", answer: q)
        default:
            let a = Int.random(in: 1...top, using: &rng), b = Int.random(in: 1...top, using: &rng)
            return Problem(text: "\(a) + \(b)", answer: a + b)
        }
    }
}

nonisolated enum AnswerMatch {
    enum Verdict: Sendable { case exact, close, wrong }

    /// Küçük harf (Türkçe), noktalama yok, tek boşluk.
    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased(with: Locale(identifier: "tr_TR"))
        let kept = lowered.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    /// 0…1; 1 = aynı.
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(normalize(a)), y = Array(normalize(b))
        if x.isEmpty && y.isEmpty { return 1 }
        if x.isEmpty || y.isEmpty { return 0 }
        var row = Array(0...y.count)
        for i in 1...x.count {
            var diagonal = row[0]
            row[0] = i
            for j in 1...y.count {
                let up = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, diagonal + (x[i - 1] == y[j - 1] ? 0 : 1))
                diagonal = up
            }
        }
        return 1 - Double(row[y.count]) / Double(max(x.count, y.count))
    }

    static func verdict(typed: String, expected: String) -> Verdict {
        let score = similarity(typed, expected)
        if score >= 0.999 { return .exact }
        // Uzun cevapta beklenen metni içeren yanıt da yakın sayılır.
        let t = normalize(typed), e = normalize(expected)
        if score >= 0.8 || (t.count >= 4 && (e.contains(t) || t.contains(e))) { return .close }
        return .wrong
    }
}

/// Dört işlem + üs + parantez + temel fonksiyonlar (özyinelemeli iniş). Geçersiz ifade → nil.
nonisolated struct Calculator {
    private var chars: [Character]
    private var pos = 0
    private var degrees: Bool

    static func evaluate(_ text: String, degrees: Bool = true) -> Double? {
        let cleaned = text.lowercased().replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "−", with: "-")
            .filter { !$0.isWhitespace }
        guard !cleaned.isEmpty else { return nil }
        var parser = Calculator(chars: Array(cleaned), degrees: degrees)
        guard let value = parser.expression(), parser.pos == parser.chars.count, value.isFinite else { return nil }
        return value
    }

    /// 0.1 + 0.2 → "0,3"
    /// Üstel gösterim kullanılmaz (sonuç yeniden ifadeye yazılabilsin); 1e-12'den küçükler 0 sayılır.
    static func format(_ value: Double) -> String {
        guard abs(value) >= 1e-12 else { return "0" }
        var text = String(format: abs(value) >= 1e15 ? "%.0f" : "%.10f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        if text == "-0" { text = "0" }
        return text.replacingOccurrences(of: ".", with: ",")
    }

    /// Kapanmamış "(" sayısı; fazladan ")" eksiye düşürmez.
    static func openParens(_ text: String) -> Int {
        max(0, text.reduce(0) { $0 + ($1 == "(" ? 1 : $1 == ")" ? -1 : 0) })
    }

    private var peek: Character? { pos < chars.count ? chars[pos] : nil }

    private mutating func take(_ c: Character) -> Bool {
        if peek == c { pos += 1; return true }
        return false
    }

    private mutating func expression() -> Double? {
        guard var value = term() else { return nil }
        while true {
            if take("+") { guard let r = term() else { return nil }; value += r }
            else if take("-") { guard let r = term() else { return nil }; value -= r }
            else { return value }
        }
    }

    private mutating func term() -> Double? {
        guard var value = factor() else { return nil }
        while true {
            if take("×") || take("*") { guard let r = factor() else { return nil }; value *= r }
            else if take("÷") || take("/") { guard let r = factor(), r != 0 else { return nil }; value /= r }
            // Örtük çarpma: 2π, 3(4+5), 2sin(30), (2)(3). İşlev tuşları ifadeye işleçsiz eklenir.
            else if let c = peek, c == "(" || c == "√" || c == "π" || c.isLetter || c.isNumber || c == "." {
                guard let r = factor() else { return nil }
                value *= r
            } else { return value }
        }
    }

    private mutating func factor() -> Double? {
        if take("-") { return factor().map { -$0 } }
        if take("+") { return factor() }
        guard let base = postfix() else { return nil }
        if take("^") { guard let exponent = factor() else { return nil }; return pow(base, exponent) }
        return base
    }

    private mutating func postfix() -> Double? {
        guard var value = primary() else { return nil }
        while true {
            if take("%") { value /= 100 }
            else if take("!") {
                guard value >= 0, value <= 170, value == value.rounded() else { return nil }
                value = (1...max(1, Int(value))).reduce(1.0) { $0 * Double($1) }
            } else { return value }
        }
    }

    private mutating func primary() -> Double? {
        if take("(") {
            guard let value = expression(), take(")") else { return nil }
            return value
        }
        if take("√") { return postfix().flatMap { $0 >= 0 ? $0.squareRoot() : nil } }
        if take("π") { return .pi }
        if let c = peek, c.isNumber || c == "." {
            let start = pos
            while let d = peek, d.isNumber || d == "." { pos += 1 }
            // Bilimsel gösterim: sayıya bitişik "e" + rakam 10 üssüdür (3e8), Euler sabiti değil.
            // İşaretli üs (1e-3) "1×e − 3" ile karışır: sessiz yanlış sonuç yerine geçersiz sayılır.
            if peek == "e", pos + 1 < chars.count {
                let next = chars[pos + 1]
                if next.isNumber {
                    pos += 1
                    while let d = peek, d.isNumber || d == "." { pos += 1 }
                } else if next == "+" || next == "-", pos + 2 < chars.count, chars[pos + 2].isNumber {
                    return nil
                }
            }
            return Double(String(chars[start..<pos]))
        }
        let start = pos
        while let c = peek, c.isLetter { pos += 1 }
        let name = String(chars[start..<pos])
        switch name {
        case "pi": return .pi
        case "e": return M_E
        case "": return nil
        default: break
        }
        guard take("("), let x = expression(), take(")") else { return nil }
        let angle = degrees ? x * .pi / 180 : x
        switch name {
        case "sin": return sin(angle)
        case "cos": return cos(angle)
        case "tan": return abs(cos(angle)) < 1e-12 ? nil : tan(angle)
        case "sqrt", "kök": return x >= 0 ? x.squareRoot() : nil
        case "ln": return x > 0 ? log(x) : nil
        case "log": return x > 0 ? log10(x) : nil
        case "abs": return abs(x)
        default: return nil
        }
    }
}

nonisolated enum SpeedReading {
    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Gözün odaklanacağı harf (ORP): kelimenin ortasının biraz solu.
    static func pivot(_ word: String) -> Int {
        switch word.count {
        case ...1: 0
        case 2...5: 1
        case 6...9: 2
        case 10...13: 3
        default: 4
        }
    }

    /// Kelimenin ekranda kalma süresi: cümle sonunda ve uzun kelimede biraz daha uzun.
    static func seconds(for word: String, wpm: Int) -> Double {
        var seconds = 60 / Double(max(60, wpm))
        if let last = word.last, ".!?…".contains(last) { seconds *= 1.6 } else if let last = word.last, ",;:".contains(last) { seconds *= 1.3 }
        if word.count > 9 { seconds *= 1.2 }
        return seconds
    }

    /// Odak harfinin solunda ayrılan sabit genişlik (en uzun ön ek 4 harf): odak harfi her kelimede aynı yatay konumda kalır.
    /// `advance`: eş aralıklı yazıda harf genişliğinin yazı boyuna oranı.
    static func prefixWidth(base: Double = 34, advance: Double = 0.62) -> Double { 4 * base * advance }

    /// Kelimenin tamamı tek boyda yazılsın diye yazı boyu: odak harfi + son ek, ön ekten kalan genişliğe sığmıyorsa küçülür (alt sınır `minimum`).
    static func fontSize(for word: String, width: Double, base: Double = 34, advance: Double = 0.62, minimum: Double = 12) -> Double {
        let needed = Double(word.count - pivot(word)) * base * advance
        let room = width - prefixWidth(base: base, advance: advance)
        guard needed > room else { return base }
        return max(minimum, room > 0 ? base * room / needed : minimum)
    }

    /// Kayıtlı konumdan devam edilecek kelime; metin yoksa ya da sonuna gelinmişse nil.
    static func resumeIndex(saved: Int, count: Int) -> Int? {
        count > 0 && saved < count ? max(0, saved) : nil
    }

    /// Okunan kısmın yüzdesi (0…100).
    static func percent(index: Int, count: Int) -> Int {
        count > 0 ? Int((Double(min(max(0, index), count)) / Double(count) * 100).rounded()) : 0
    }
}

nonisolated enum CardImport {
    struct Pair: Equatable, Sendable { var front: String; var back: String }

    struct Outcome: Equatable, Sendable {
        var cards: [Pair] = []
        /// Ayırıcısı bulunamayan dolu satırlar (kullanıcı düzeltsin diye olduğu gibi).
        var skipped: [String] = []
        /// Destede ya da aynı listede zaten bulunan kart sayısı.
        var duplicates = 0
    }

    /// Kopya denetimi anahtarı: büyük/küçük harf ve boşluk farkı aynı kart sayılır.
    /// Noktalama ve işleçler korunur: "2+2" ile "2×2", "-5" ile "5" ayrı karttır (kopya sayılan satır eklenmeden alandan silinir).
    static func key(front: String, back: String) -> String {
        fold(front) + "\t" + fold(back)
    }

    private static func fold(_ text: String) -> String {
        text.lowercased(with: Locale(identifier: "tr_TR")).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Sekmesiz satırlarda denenen ayırıcılar (eşitlikte öncelik sırası). "-" yalnız iki yanında boşlukla ayırıcıdır ("iyi-kötü" bölünmesin).
    private static let separators = [";", " = ", " – ", " - ", ":", "="]

    /// Anki metin dışa aktarımının başlık anahtarları ("#separator:tab", "#html:false", "#tags column:3"…).
    private static let ankiHeaders: Set<String> = [
        "separator", "html", "tags", "columns", "notetype", "deck", "notetype column", "deck column", "tags column", "guid column", "if matches",
    ]

    /// Yalnız bilinen Anki başlıkları atlanır; "#1: soru" gibi satır kart adayıdır (sessizce kaybolmaz).
    static func isHeader(_ line: String) -> Bool {
        guard line.hasPrefix("#"), let colon = line.firstIndex(of: ":") else { return false }
        return ankiHeaders.contains(line[line.index(after: line.startIndex)..<colon].lowercased())
    }

    /// Her satır bir kart: "ön ; arka", "ön<TAB>arka", "ön = arka", "ön - arka" ya da "ön : arka".
    /// Anki başlık satırları yok sayılır. Sekmeli satırda ilk iki dolu sütun alınır (etiket sütunu arka yüze yapışmaz).
    /// Diğer satırlarda listede en çok satırda geçen ayırıcı önce denenir: liste ":" ile yazıldıysa "ATP: enerji - taşıyıcı" da ":"den bölünür.
    static func analyze(_ text: String, existing: Set<String> = []) -> Outcome {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isHeader($0) }
        let plain = lines.filter { !$0.contains("\t") }
        let counts = separators.map { separator in plain.filter { $0.contains(separator) }.count }
        let order = separators.indices.sorted { counts[$0] != counts[$1] ? counts[$0] > counts[$1] : $0 < $1 }.map { separators[$0] }
        var outcome = Outcome(), seen = existing
        for line in lines {
            guard let pair = split(line, order: order) else { outcome.skipped.append(line); continue }
            if seen.insert(key(front: pair.front, back: pair.back)).inserted { outcome.cards.append(pair) } else { outcome.duplicates += 1 }
        }
        return outcome
    }

    /// `analyze`'ın yalnız kartları (aynı listede yinelenen kart bir kez gelir).
    static func parse(_ text: String) -> [(front: String, back: String)] {
        analyze(text).cards.map { ($0.front, $0.back) }
    }

    private static func split(_ line: String, order: [String]) -> Pair? {
        if line.contains("\t") {
            let columns = line.split(separator: "\t").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if columns.count >= 2 { return Pair(front: columns[0], back: columns[1]) }
        }
        for separator in order {
            guard let range = line.range(of: separator) else { continue }
            let front = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let back = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !front.isEmpty, !back.isEmpty { return Pair(front: front, back: back) }
        }
        return nil
    }
}

nonisolated enum HeatMap {
    /// 0 (hiç) … 4 (90 dk ve üstü)
    static func level(minutes: Double) -> Int {
        switch minutes {
        case ..<1: 0
        case ..<15: 1
        case ..<45: 2
        case ..<90: 3
        default: 4
        }
    }

    /// Bugünün haftasında biten `weeks` haftalık ızgara: sütun = hafta (Pazartesi başlar), hücre = gün; gelecek günler nil.
    static func grid(weeks: Int, today: Date = .now, calendar: Calendar = .current) -> [[Date?]] {
        var cal = calendar
        cal.firstWeekday = 2
        let start = cal.startOfDay(for: today)
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: start)?.start else { return [] }
        return (0..<weeks).map { column in
            (0..<7).map { row in
                guard let day = cal.date(byAdding: .day, value: (column - (weeks - 1)) * 7 + row, to: thisWeek), day <= start else { return nil }
                return day
            }
        }
    }
}

nonisolated struct BadgeStats: Sendable {
    var cards = 0
    var matureCards = 0
    var reviews = 0
    var resolvedMistakes = 0
    var focusMinutes = 0
    var listenedMinutes = 0
    var bestStreak = 0
    var episodes = 0
    var videoLessons = 0
    var notes = 0
    var mockExams = 0
    var solvedQuestions = 0
}

nonisolated struct Badge: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var detail: String
    var symbol: String
    var value: Int
    var goal: Int
    var earned: Bool { value >= goal }
    var progress: Double { goal > 0 ? min(1, Double(value) / Double(goal)) : 0 }
}

nonisolated enum Badges {
    /// Her ölçü için üç kademe (bronz, gümüş, altın).
    static func all(_ s: BadgeStats) -> [Badge] {
        let rows: [(String, String, String, Int, [Int], String)] = [
            ("streak", "Seri", "flame.fill", s.bestStreak, [3, 14, 60], "gün üst üste çalışma"),
            ("focus", "Odak", "timer", s.focusMinutes, [60, 600, 3000], "dakika odak"),
            ("listen", "Kulak", "headphones", s.listenedMinutes, [60, 600, 3000], "dakika dinleme"),
            ("reviews", "Tekrar", "rectangle.on.rectangle.angled", s.reviews, [25, 250, 1500], "kart tekrarı"),
            ("mature", "Kalıcı bilgi", "brain.head.profile", s.matureCards, [10, 75, 300], "olgun kart (21+ gün)"),
            ("mistakes", "Hata avcısı", "checkmark.seal.fill", s.resolvedMistakes, [5, 40, 150], "çözülen yanlış"),
            ("episodes", "Kütüphaneci", "books.vertical.fill", s.episodes + s.videoLessons, [3, 20, 75], "bölüm ve ders"),
            ("notes", "Not ustası", "note.text", s.notes, [3, 20, 60], "Cornell notu"),
            ("exams", "Denemeci", "stopwatch.fill", s.mockExams, [1, 10, 40], "deneme"),
            ("questions", "Soru canavarı", "pencil.and.list.clipboard", s.solvedQuestions, [100, 2000, 10000], "çözülen soru"),
        ]
        let tiers = ["Bronz", "Gümüş", "Altın"]
        return rows.flatMap { id, title, symbol, value, goals, unit in
            goals.enumerated().map { index, goal in
                Badge(id: "\(id)-\(index)", title: "\(title) · \(tiers[index])", detail: "\(goal) \(unit)", symbol: symbol, value: value, goal: goal)
            }
        }
    }
}

nonisolated enum DigitSpan {
    /// Art arda aynı rakam gelmez (ezber kolaylaşmasın).
    static func sequence<R: RandomNumberGenerator>(length: Int, using rng: inout R) -> [Int] {
        var out: [Int] = []
        while out.count < length {
            let digit = Int.random(in: 0...9, using: &rng)
            if digit != out.last { out.append(digit) }
        }
        return out
    }

    /// Yazılanın diziden ayrıldığı ilk konum (0'dan); eksik ya da fazla rakam da farktır. Tam eşleşmede nil.
    static func firstMismatch(typed: String, expected: [Int]) -> Int? {
        let digits = typed.compactMap { $0.wholeNumberValue }
        if let index = zip(digits, expected).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset { return index }
        return digits.count == expected.count ? nil : min(digits.count, expected.count)
    }
}

nonisolated enum Schulte {
    /// 12.34 → "12,3" (uygulamanın geri kalanı gibi virgüllü).
    static func timeText(_ seconds: Double) -> String {
        seconds.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "tr_TR")))
    }
}

nonisolated enum QuestionStats {
    struct CourseTotal: Identifiable, Equatable, Sendable {
        var course: String
        var solved: Int
        var wrong: Int
        /// Doğruluk yüzdesi (0…100).
        var accuracy: Int
        var id: String { course }
    }

    struct DayTotal: Identifiable, Equatable, Sendable {
        var key: String
        var date: Date
        var solved: Int
        var id: String { key }
    }

    static let noCourse = "Derssiz"

    /// Ders bazında toplam: büyük/küçük harf ve boşluk farkı aynı ders sayılır, ilk yazım gösterilir; en çok çözülen üstte.
    static func byCourse(_ logs: [QuestionLog]) -> [CourseTotal] {
        var order: [String] = [], totals: [String: CourseTotal] = [:]
        for log in logs {
            // Adı "Derssiz" yazılan ders, adsız kayıtlarla aynı satırda toplanır (satır kimliği çakışmasın).
            let normalized = AnswerMatch.normalize(log.course)
            let key = normalized == AnswerMatch.normalize(noCourse) ? "" : normalized
            var total = totals[key] ?? CourseTotal(course: key.isEmpty ? noCourse : log.course.trimmingCharacters(in: .whitespaces), solved: 0, wrong: 0, accuracy: 0)
            if totals[key] == nil { order.append(key) }
            total.solved += log.solved
            total.wrong += min(log.wrong, log.solved)
            total.accuracy = total.solved > 0 ? Int((Double(total.solved - total.wrong) / Double(total.solved) * 100).rounded()) : 0
            totals[key] = total
        }
        // Eşitlikte ilk görülen ders önce (sıralama kararlı olsun diye sıra numarasıyla).
        return order.compactMap { totals[$0] }.enumerated()
            .sorted { $0.element.solved != $1.element.solved ? $0.element.solved > $1.element.solved : $0.offset < $1.offset }
            .map { $0.element }
    }

    /// Bugünle biten `days` günün toplamı (eskiden yeniye). Kayıtlar tek geçişte günlere dağıtılır.
    static func dayTotals(_ logs: [QuestionLog], days: Int, today: Date = .now, calendar: Calendar = .current) -> [DayTotal] {
        var sums: [String: Int] = [:]
        for log in logs { sums[log.day, default: 0] += log.solved }
        let start = calendar.startOfDay(for: today)
        return (0..<max(0, days)).reversed().compactMap { back in
            guard let date = calendar.date(byAdding: .day, value: -back, to: start) else { return nil }
            let key = DayKey.key(date, calendar: calendar)
            return DayTotal(key: key, date: date, solved: sums[key] ?? 0)
        }
    }
}

/// Yazarak tekrar turu: sıradaki kart, doğru sayısı ve bilinemeyenler.
nonisolated struct ReviewRound<ID: Hashable & Sendable>: Sendable {
    var ids: [ID]
    var index = 0
    var correct = 0
    var missed: [ID] = []

    var isFinished: Bool { index >= ids.count }
    var current: ID? { isFinished ? nil : ids[index] }

    mutating func record(correct isCorrect: Bool) {
        guard !isFinished else { return }
        if isCorrect { correct += 1 } else { missed.append(ids[index]) }
        index += 1
    }

    /// Yalnız bilinemeyenlerle yeni tur (sayaçlar sıfır).
    func retry() -> ReviewRound { ReviewRound(ids: missed) }
}

nonisolated enum AbsenceMath {
    enum Level: Sendable { case ok, warning, atLimit, exceeded }

    struct DayCount: Identifiable, Equatable, Sendable {
        var day: String
        var count: Int
        var id: String { day }
    }

    /// Kalan hak 2'den çoksa sorun yok, 1–2 uyarı, 0 sınırda, eksiyse aşıldı.
    static func level(count: Int, limit: Int) -> Level {
        switch limit - count {
        case ..<0: .exceeded
        case 0: .atLimit
        case 1...2: .warning
        default: .ok
        }
    }

    /// Sınır dolunca ya da aşılınca da sayı görünür kalır.
    static func summary(count: Int, limit: Int) -> String {
        switch level(count: count, limit: limit) {
        case .ok, .warning: "\(count) devamsızlık · \(limit - count) hak kaldı"
        case .atLimit: "\(count)/\(limit) · hakkın bitti"
        case .exceeded: "\(count)/\(limit) · sınır \(count - limit) aşıldı"
        }
    }

    /// Aynı gün tek satırda (ders saati sayısıyla), yeniden eskiye.
    static func grouped(_ days: [String]) -> [DayCount] {
        Dictionary(grouping: days, by: { $0 }).map { DayCount(day: $0.key, count: $0.value.count) }.sorted { $0.day > $1.day }
    }

    /// O günün kayıtlarından yalnız birini çıkarır; gün listede yoksa dizi değişmez.
    static func removingOne(_ day: String, from days: [String]) -> [String] {
        guard let index = days.lastIndex(of: day) else { return days }
        var out = days
        out.remove(at: index)
        return out
    }
}

/// Periyodik tablo: 118 element (Türkçe ad, standart atom kütlesi).
nonisolated struct ChemElement: Identifiable, Hashable, Sendable {
    enum Category: String, CaseIterable, Sendable {
        case nonmetal, nobleGas, alkali, alkalineEarth, metalloid, halogen, transition, postTransition, lanthanide, actinide

        var title: String {
            switch self {
            case .nonmetal: "Ametal"
            case .nobleGas: "Soy gaz"
            case .alkali: "Alkali metal"
            case .alkalineEarth: "Toprak alkali metal"
            case .metalloid: "Yarı metal"
            case .halogen: "Halojen"
            case .transition: "Geçiş metali"
            case .postTransition: "Zayıf metal"
            case .lanthanide: "Lantanit"
            case .actinide: "Aktinit"
            }
        }
    }

    var number: Int
    var symbol: String
    var name: String
    var mass: String
    var id: Int { number }

    var period: Int {
        switch number {
        case ...2: 1
        case ...10: 2
        case ...18: 3
        case ...36: 4
        case ...54: 5
        case ...86: 6
        default: 7
        }
    }

    /// 1–18; lantanit ve aktinitlerde nil (f bloğu).
    var group: Int? {
        switch number {
        case 1: 1
        case 2: 18
        case 3...4: number - 2
        case 5...10: number + 8
        case 11...12: number - 10
        case 13...18: number
        case 19...36: number - 18
        case 37...54: number - 36
        case 55...56: number - 54
        case 57...71: nil
        case 72...86: number - 68
        case 87...88: number - 86
        case 89...103: nil
        default: number - 100
        }
    }

    var category: Category {
        switch number {
        case 2, 10, 18, 36, 54, 86, 118: .nobleGas
        case 3, 11, 19, 37, 55, 87: .alkali
        case 4, 12, 20, 38, 56, 88: .alkalineEarth
        case 9, 17, 35, 53, 85, 117: .halogen
        case 1, 6, 7, 8, 15, 16, 34: .nonmetal
        case 5, 14, 32, 33, 51, 52: .metalloid
        case 57...71: .lanthanide
        case 89...103: .actinide
        case 13, 31, 49, 50, 81, 82, 83, 84, 113, 114, 115, 116: .postTransition
        default: .transition
        }
    }

    static let all: [ChemElement] = raw.split(separator: ";").enumerated().compactMap { index, item in
        let parts = item.split(separator: ",")
        guard parts.count == 3 else { return nil }
        return ChemElement(number: index + 1, symbol: String(parts[0]), name: String(parts[1]), mass: String(parts[2]))
    }

    private static let raw = "H,Hidrojen,1.008;He,Helyum,4.003;Li,Lityum,6.94;Be,Berilyum,9.012;B,Bor,10.81;C,Karbon,12.011;N,Azot,14.007;O,Oksijen,15.999;F,Flor,18.998;Ne,Neon,20.180;Na,Sodyum,22.990;Mg,Magnezyum,24.305;Al,Alüminyum,26.982;Si,Silisyum,28.085;P,Fosfor,30.974;S,Kükürt,32.06;Cl,Klor,35.45;Ar,Argon,39.95;K,Potasyum,39.098;Ca,Kalsiyum,40.078;Sc,Skandiyum,44.956;Ti,Titanyum,47.867;V,Vanadyum,50.942;Cr,Krom,51.996;Mn,Mangan,54.938;Fe,Demir,55.845;Co,Kobalt,58.933;Ni,Nikel,58.693;Cu,Bakır,63.546;Zn,Çinko,65.38;Ga,Galyum,69.723;Ge,Germanyum,72.630;As,Arsenik,74.922;Se,Selenyum,78.971;Br,Brom,79.904;Kr,Kripton,83.798;Rb,Rubidyum,85.468;Sr,Stronsiyum,87.62;Y,İtriyum,88.906;Zr,Zirkonyum,91.224;Nb,Niyobyum,92.906;Mo,Molibden,95.95;Tc,Teknesyum,98;Ru,Rutenyum,101.07;Rh,Rodyum,102.906;Pd,Paladyum,106.42;Ag,Gümüş,107.868;Cd,Kadmiyum,112.414;In,İndiyum,114.818;Sn,Kalay,118.710;Sb,Antimon,121.760;Te,Tellür,127.60;I,İyot,126.904;Xe,Ksenon,131.293;Cs,Sezyum,132.905;Ba,Baryum,137.327;La,Lantan,138.905;Ce,Seryum,140.116;Pr,Praseodim,140.908;Nd,Neodim,144.242;Pm,Prometyum,145;Sm,Samaryum,150.36;Eu,Evropiyum,151.964;Gd,Gadolinyum,157.25;Tb,Terbiyum,158.925;Dy,Disprosyum,162.500;Ho,Holmiyum,164.930;Er,Erbiyum,167.259;Tm,Tulyum,168.934;Yb,İterbiyum,173.045;Lu,Lutesyum,174.967;Hf,Hafniyum,178.49;Ta,Tantal,180.948;W,Tungsten,183.84;Re,Renyum,186.207;Os,Osmiyum,190.23;Ir,İridyum,192.217;Pt,Platin,195.084;Au,Altın,196.967;Hg,Cıva,200.592;Tl,Talyum,204.38;Pb,Kurşun,207.2;Bi,Bizmut,208.980;Po,Polonyum,209;At,Astatin,210;Rn,Radon,222;Fr,Fransiyum,223;Ra,Radyum,226;Ac,Aktinyum,227;Th,Toryum,232.038;Pa,Protaktinyum,231.036;U,Uranyum,238.029;Np,Neptünyum,237;Pu,Plütonyum,244;Am,Amerikyum,243;Cm,Küriyum,247;Bk,Berkelyum,247;Cf,Kaliforniyum,251;Es,Aynştaynyum,252;Fm,Fermiyum,257;Md,Mendelevyum,258;No,Nobelyum,259;Lr,Lavrensiyum,266;Rf,Rutherfordiyum,267;Db,Dubniyum,268;Sg,Seaborgiyum,269;Bh,Bohriyum,270;Hs,Hassiyum,277;Mt,Meitneriyum,278;Ds,Darmstadtiyum,281;Rg,Röntgenyum,282;Cn,Kopernikyum,285;Nh,Nihonyum,286;Fl,Flerovyum,289;Mc,Moskovyum,290;Lv,Livermoryum,293;Ts,Tenesin,294;Og,Oganesson,294"
}
