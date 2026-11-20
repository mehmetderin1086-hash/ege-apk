import Foundation

// P6: öğrenme çekirdeğinin saf mantığı (ağ ve arayüz yok; testlenir).

nonisolated enum QuestionKind {
    static func of(_ item: QuizItem) -> String { item.kind ?? "mcq" }
    /// Açık uçlu ya da şıksız soru (yazılı/sesli cevap ister).
    static func isOpen(_ item: QuizItem) -> Bool { of(item) == "open" || item.options.isEmpty || item.answerIndex < 0 }
    static func letter(_ index: Int) -> String { ["A", "B", "C", "D", "E", "F"][safe: index] ?? "•" }

    /// Açık uçlunun beklenen cevabı; şıklı soruda doğru şık.
    static func expectedAnswer(_ item: QuizItem) -> String {
        if let text = item.answerText, !text.isEmpty { return text }
        return item.options[safe: item.answerIndex] ?? item.explanation
    }
}

/// #24: soru seçimi ve sıralaması.
nonisolated enum QuestionPicker {
    /// Kolaydan zora (zorluk yoksa orta sayılır); eşitlikte özgün sıra korunur.
    static func easyFirst(_ items: [QuizItem]) -> [QuizItem] {
        items.enumerated().sorted { ($0.element.difficulty ?? 2, $0.offset) < ($1.element.difficulty ?? 2, $1.offset) }.map(\.element)
    }

    /// Biten konunun kendi sorusu (açık uçlu seçilmez; daha önce sorulanlar atlanır). Konuya bağlı soru yoksa nil.
    static func forChapter(_ quiz: [QuizItem], chapter: Int, asked: Set<String> = []) -> QuizItem? {
        let candidates = quiz.filter { $0.chapterIndex == chapter && !QuestionKind.isOpen($0) && $0.verified != false }
        return easyFirst(candidates.filter { !asked.contains($0.question) }).first
    }

    /// Ön test / bölüm sonu / yoklama: şıklı sorulardan, konulara yayılmış, kolaydan zora.
    static func spread(_ quiz: [QuizItem], count: Int, excluding: Set<String> = []) -> [QuizItem] {
        let pool = quiz.filter { !QuestionKind.isOpen($0) && $0.verified != false && !excluding.contains($0.question) }
        var byChapter: [Int: [QuizItem]] = [:]
        for item in easyFirst(pool) { byChapter[item.chapterIndex ?? -1, default: []].append(item) }
        let keys = byChapter.keys.sorted()
        var out: [QuizItem] = []
        var round = 0
        while out.count < count {
            var added = false
            for key in keys where out.count < count {
                if let item = byChapter[key]?[safe: round] { out.append(item); added = true }
            }
            if !added { break }
            round += 1
        }
        return easyFirst(out)
    }
}

/// Quiz turu: sonuç yalnız bu turun sorularından hesaplanır ("Yeni sorular" ve "Yalnız yanlışlar" ayrı turdur).
nonisolated struct QuizRound: Equatable, Sendable {
    var items: [QuizItem]
    var index = 0
    var correct = 0
    var wrong: [QuizItem] = []
    var finished = false
    /// Gösterilen soru cevaplandı, henüz sonrakine geçilmedi.
    var answered = false

    var total: Int { items.count }
    /// En az yarısı doğru.
    var passed: Bool { correct * 2 >= total }
    var current: QuizItem? { finished ? nil : items[safe: index] }

    /// Gösterilen soru bir kez sayılır. `isCorrect` nil: notlanmamış açık uçlu (ne doğru ne yanlış).
    mutating func record(_ item: QuizItem, isCorrect: Bool?) {
        guard !answered, !finished else { return }
        answered = true
        if isCorrect == true { correct += 1 } else if isCorrect == false { wrong.append(item) }
    }

    /// Son sorudan sonra tur biter.
    mutating func advance() {
        guard !finished else { return }
        answered = false
        if index + 1 < items.count { index += 1 } else { finished = true }
    }

    /// Paketle eşitleme. İlk açılışta tur kurulur; pakete eklenen sorular sıraya girer, süren tur değişmez;
    /// paket yeniden üretilip turun soruları pakette kalmadıysa tur baştan kurulur.
    static func sync(order: [QuizItem], round: QuizRound?, quiz: [QuizItem]) -> (order: [QuizItem], round: QuizRound?) {
        guard !quiz.isEmpty else { return ([], nil) }
        let live = Set(quiz.map(\.question))
        guard let round, !round.items.isEmpty, round.items.allSatisfy({ live.contains($0.question) }) else {
            let fresh = QuestionPicker.easyFirst(quiz)
            return (fresh, QuizRound(items: fresh))
        }
        let known = Set(order.map(\.question))
        let kept = order.filter { live.contains($0.question) }
        return (kept + QuestionPicker.easyFirst(quiz.filter { !known.contains($0.question) }), round)
    }
}

/// Konu sonu hakeminin kararı (#24, #25, #29). Uyku zamanlayıcısı durdurduğunda olay zaten gelmez.
nonisolated enum ChapterEndAction: Equatable, Sendable {
    case inlineQuiz, handsFree, recallPrompt, none
}

nonisolated enum ChapterEndArbiter {
    struct Input: Sendable {
        var isForeground: Bool
        var detailOpen: Bool
        var policy: ListeningPolicy
        var handsFreeEnabled: Bool
        var hasChapterQuestion: Bool
        var interludeReady: Bool
        var learn2: Bool
        var hasChapterTurns: Bool
    }

    static func decide(_ i: Input) -> ChapterEndAction {
        if i.isForeground, i.detailOpen, i.policy.inlineQuestions, i.hasChapterQuestion { return .inlineQuiz }
        if !i.isForeground, i.policy.handsFree, i.handsFreeEnabled, i.interludeReady { return .handsFree }
        if i.isForeground, i.policy.recallPrompt, i.learn2, i.hasChapterTurns { return .recallPrompt }
        return .none
    }
}

/// #23: düşünme payı. Senaryodaki soru turunun payı (3–8 sn) kullanılır; yoksa 5 sn.
nonisolated enum ThinkTiming {
    static let fallback = 5.0

    static func seconds(for item: QuizItem, script: PodcastScript?) -> Double {
        guard let script else { return fallback }
        let turns = script.chapters.flatMap { $0.scenes.flatMap(\.turns) }
        if let index = item.turnIndex, let think = turns[safe: index]?.think { return clamp(think) }
        if let chapter = item.chapterIndex, let think = script.chapters[safe: chapter]?.scenes.flatMap(\.turns).compactMap(\.think).first {
            return clamp(think)
        }
        return fallback
    }

    static func clamp(_ value: Double) -> Double { min(8, max(3, value)) }
}

/// "Bu kısmı dinle": sorunun dayandığı an.
nonisolated enum ListenAnchor {
    static func time(turnIndex: Int?, chapterIndex: Int?, timeline: Timeline?) -> Double? {
        guard let timeline else { return nil }
        if let turnIndex, let turn = timeline.turns.first(where: { $0.id == turnIndex }) { return turn.start }
        if let chapterIndex, let chapter = timeline.chapters.first(where: { $0.id == chapterIndex }) { return chapter.start }
        return nil
    }

    static func time(for item: QuizItem, timeline: Timeline?) -> Double? {
        time(turnIndex: item.turnIndex, chapterIndex: item.chapterIndex, timeline: timeline)
    }

    static func label(_ time: Double) -> String { "Bu kısmı dinle (\(clock(time)))" }

    /// 734 → "12:14", 3725 → "1:02:05"
    static func clock(_ time: Double) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// #28: yoklama takvimi. `stage` = dinlemeden sonraki gün. Sınava 14 günden az kaldıysa aralıklar sıkışır.
nonisolated enum ProbeScheduler {
    static func stages(_ base: [Int], daysToExam: Int?) -> [Int] {
        let sorted = Array(Set(base.filter { $0 > 0 })).sorted()
        guard let left = daysToExam, left < 14 else { return sorted }
        guard left >= 1 else { return [] }
        let scale = Double(left) / 14
        var out = sorted.map { max(1, Int((Double($0) * scale).rounded())) }.filter { $0 <= left }
        if out.isEmpty { out = [1] }
        return Array(Set(out)).sorted()
    }

    static func dueDate(stage: Int, listenedAt: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: listenedAt)
        return calendar.date(byAdding: .day, value: stage, to: day)?.addingTimeInterval(9 * 3600) ?? listenedAt
    }

    /// Yoklama puanı bu eşiğin altındaysa yeniden dinleme görevi eklenir.
    static let relistenThreshold = 0.6

    /// Günün sonu (yarının başlangıcı): bundan önce vadesi gelen görev "bugün açık" sayılır.
    static func endOfDay(_ now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
    }

    /// Çalış sekmesindeki rozet: bugün açık görevi (yoklama ya da yeniden dinleme) olan bölüm sayısı.
    /// Yoklamalar listesinde dokunulabilen bölüm sayısıyla aynıdır; bölümsüz kayıt sayılmaz.
    static func dueEpisodeCount(_ items: [(episodeID: UUID?, due: Date)], endOfToday: Date) -> Int {
        Set(items.filter { $0.due < endOfToday }.compactMap(\.episodeID)).count
    }

    /// Satırdaki vade notu: günü geçmişse "gecikti", bugünse "bugün", ileri tarihliyse nil.
    static func dueNote(_ due: Date, now: Date, calendar: Calendar = .current) -> String? {
        if due < calendar.startOfDay(for: now) { return "gecikti" }
        return due < endOfDay(now, calendar: calendar) ? "bugün" : nil
    }

    /// Yeniden dinleme satırının alt metni.
    static func relistenNote(score: Double?) -> String {
        score.map { "Yoklamada %\(Int(($0 * 100).rounded()))" } ?? "Yoklamada zorlandın"
    }
}

/// #27: kalıcılık eğrisi ve kalibrasyon.
nonisolated enum RecallStats {
    struct Point: Hashable, Sendable {
        var label: String
        var accuracy: Double?
        var count: Int
    }

    struct Sample: Sendable {
        var isCorrect: Bool?
        var confidence: Int?
        var daysSinceListen: Int?
        var source: String? = nil
    }

    /// Kalıcılık ölçmeyen denemeler: dinlemeden önceki ön test ve iki kavramı ayırt etme.
    static let nonRetentionSources: Set<String> = ["pretest", "discriminate"]

    /// 1. gün (0–2), 7. gün (3–14), 30. gün (15+) kovaları.
    static func retention(_ samples: [Sample]) -> [Point] {
        let buckets: [(String, ClosedRange<Int>)] = [("1. gün", 0...2), ("7. gün", 3...14), ("30. gün", 15...100_000)]
        let eligible = samples.filter { !nonRetentionSources.contains($0.source ?? "") }
        return buckets.map { label, range in
            let scored = eligible.filter { $0.isCorrect != nil && range.contains($0.daysSinceListen ?? -1) }
            return Point(label: label, accuracy: accuracy(scored), count: scored.count)
        }
    }

    static let confidenceTitles = ["Tahmin", "Sanırım", "Eminim"]

    /// Eminlik düzeyine göre gerçek doğruluk.
    static func calibration(_ samples: [Sample]) -> [Point] {
        confidenceTitles.indices.map { level in
            let scored = samples.filter { $0.isCorrect != nil && $0.confidence == level }
            return Point(label: confidenceTitles[level], accuracy: accuracy(scored), count: scored.count)
        }
    }

    /// Kalibrasyon özeti: "Eminim" dediklerinde doğruluk %80'in altındaysa aşırı güven, "Tahmin"lerde %60 üstüyse az güven.
    static func calibrationNote(_ points: [Point]) -> String? {
        guard points.count == 3 else { return nil }
        if let sure = points[2].accuracy, points[2].count >= 3, sure < 0.8 {
            return "\"Eminim\" dediklerinin %\(Int((sure * 100).rounded()))'i doğru: biraz aşırı güveniyorsun."
        }
        if let guess = points[0].accuracy, points[0].count >= 3, guess > 0.6 {
            return "\"Tahmin\" dediklerinin %\(Int((guess * 100).rounded()))'i doğru: bildiğinden fazlasını biliyorsun."
        }
        if points.allSatisfy({ $0.count == 0 }) { return nil }
        return "Eminliğin doğruluğunla uyumlu."
    }

    private static func accuracy(_ samples: [Sample]) -> Double? {
        guard !samples.isEmpty else { return nil }
        return Double(samples.filter { $0.isCorrect == true }.count) / Double(samples.count)
    }
}

/// #26: ön planda bölüm sonu kartı açıkken tutulan otomatik geçiş.
/// Oynatıcının `holdAutoplay`'i yalnız o bitiş anı için okunur (P5 `finished()` hemen sıfırlar); kalıcı durum burada.
/// Sayaç biterse, "Şimdi başlat"a basılırsa ya da kart başka yoldan kapanırsa ("Kapat", kaydırma) sıradaki başlar.
/// "Bekle" ya da karttan "O anı dinle" otomatik geçişi bu bitiş için iptal eder; "Şimdi başlat" kartta kalır.
struct NextUpHold: Equatable {
    private(set) var title: String?
    /// true: kart kapanınca sıradaki başlar.
    private(set) var autoAdvance = false

    var isEmpty: Bool { title == nil }

    mutating func begin(title: String) {
        self.title = title
        autoAdvance = true
    }

    /// "Bekle": sayaç durur, kapatınca da başlamaz.
    mutating func wait() { autoAdvance = false }

    /// Kart kapandı ya da sayaç bitti: sıradaki başlamalı mı? Durum sıfırlanır.
    mutating func release() -> Bool {
        defer { self = NextUpHold() }
        return autoAdvance
    }

    /// Arka plana geçerken: bölüm sonu kartı açık ve sıradaki tutuluyorsa ("Bekle" denmemiş) kartın bölümü;
    /// çağıran sıradakini hemen başlatır (askıya alınan uygulamada sayaç donar).
    static func backgroundAdvance(sheet: LearningSheet?, hold: NextUpHold) -> UUID? {
        guard case let .endCard(id)? = sheet, hold.title != nil, hold.autoAdvance else { return nil }
        return id
    }
}

/// #26: oynatıcının `advanceQueue` sırasıyla sıradaki öğenin adı: kuyrukta ilk hazır bölüm ya da brifing sesi,
/// kuyruk boşsa serinin sonraki bölümü. (`nextUp()` sesleri atladığı için kart yanlış adı göstermesin.)
enum NextUpPeek {
    static func title(queue: [PlaybackQueueItem], readyEpisodeTitle: (UUID) -> String?, seriesNext: () -> String?) -> String? {
        for item in queue {
            switch item {
            case let .episode(id):
                if let title = readyEpisodeTitle(id) { return title }
            case let .audio(_, title):
                return title.isEmpty ? "Sesli özet" : title
            }
        }
        return seriesNext()
    }
}

/// #34: denemede şık karıştırma (doğru/yanlış ve açık uçlu karıştırılmaz).
nonisolated enum OptionShuffle {
    static func shuffled<G: RandomNumberGenerator>(_ item: QuizItem, using rng: inout G) -> QuizItem {
        guard !QuestionKind.isOpen(item), QuestionKind.of(item) != "truefalse", item.options.count > 1 else { return item }
        let order = Array(item.options.indices).shuffled(using: &rng)
        var out = item
        out.options = order.map { item.options[$0] }
        out.answerIndex = order.firstIndex(of: item.answerIndex) ?? item.answerIndex
        return out
    }

    static func shuffled(_ item: QuizItem) -> QuizItem {
        var rng = SystemRandomNumberGenerator()
        return shuffled(item, using: &rng)
    }
}
