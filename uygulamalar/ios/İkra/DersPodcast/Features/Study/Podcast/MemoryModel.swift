import Foundation

/// #32: FSRS benzeri bellek modeli. Kartın kararlılığı (S, gün) ve zorluğu (D, 1…10) tutulur;
/// hatırlama olasılığı R(t) = (1 + F·t/S)^C, t = S iken %90.
nonisolated enum MemoryModel {
    struct State: Hashable, Sendable {
        var stability: Double
        var difficulty: Double
    }

    /// FSRS-4.5 varsayılan ağırlıkları.
    private static let w: [Double] = [0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.031, 1.6474,
                                      0.1367, 1.0461, 2.1072, 0.0793, 0.3246, 1.587, 0.2272, 2.8755]
    private static let decay = -0.5
    private static let factor = 19.0 / 81.0
    static let targetRetention = 0.9

    /// ReviewGrade → FSRS notu (1 Bilemedim, 2 Zor, 3 İyi, 4 Kolay).
    static func rating(_ grade: ReviewGrade) -> Int {
        switch grade {
        case .again: 1
        case .hard: 2
        case .good: 3
        case .easy: 4
        }
    }

    static func retrievability(elapsedDays: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        return pow(1 + factor * max(0, elapsedDays) / stability, decay)
    }

    /// Hedef hatırlamaya göre aralık (gün, 1…365). %90 hedefte aralık = S.
    static func interval(for stability: Double, retention: Double = targetRetention) -> Int {
        let days = stability / factor * (pow(retention, 1 / decay) - 1)
        return min(365, max(1, Int(days.rounded())))
    }

    /// Eski (stability == 0) kartlar için SM-2 alanlarından türetme: S = mevcut aralık, böylece sıradaki tarih değişmez.
    /// Hiç tekrar edilmemiş kartın durumu yoktur (nil).
    static func derived(intervalDays: Int, ease: Double, lapses: Int, repetitions: Int, reviewed: Bool) -> State? {
        guard reviewed || repetitions > 0 || lapses > 0 else { return nil }
        let s = Double(max(1, intervalDays))
        let d = 5 + (2.5 - ease) * 3.5 + Double(min(lapses, 3)) * 0.3
        return State(stability: s, difficulty: clampD(d))
    }

    static func initial(_ rating: Int) -> State {
        State(stability: w[max(1, min(4, rating)) - 1], difficulty: clampD(w[4] - Double(rating - 3) * w[5]))
    }

    /// Bir tekrar sonrası yeni durum. `prior` nil ise ilk tekrar.
    static func next(_ prior: State?, rating: Int, elapsedDays: Double) -> State {
        guard let prior else { return initial(rating) }
        let r = retrievability(elapsedDays: elapsedDays, stability: prior.stability)
        let d0 = clampD(w[4] - 0 * w[5])
        let d = clampD(w[7] * d0 + (1 - w[7]) * (prior.difficulty - w[6] * Double(rating - 3)))
        let s: Double
        if rating == 1 {
            let forget = w[11] * pow(prior.difficulty, -w[12]) * (pow(prior.stability + 1, w[13]) - 1) * exp(w[14] * (1 - r))
            s = max(0.1, min(prior.stability, forget))
        } else {
            let hard = rating == 2 ? w[15] : 1
            let easy = rating == 4 ? w[16] : 1
            let growth = exp(w[8]) * (11 - prior.difficulty) * pow(prior.stability, -w[9]) * (exp(w[10] * (1 - r)) - 1) * hard * easy
            s = prior.stability * (1 + max(0, growth))
        }
        return State(stability: s, difficulty: d)
    }

    private static func clampD(_ d: Double) -> Double { min(10, max(1, d)) }

    // MARK: - Karışık oturum

    /// Art arda iki öğe aynı anahtardan (bölüm) gelmez; olanaksızsa en az tekrarla dizilir.
    /// Her adımda son anahtardan farklı ve en çok öğesi kalan anahtar seçilir (eşitlikte ilk sıradaki).
    static func interleave<T, K: Hashable>(_ items: [T], key: (T) -> K) -> [T] {
        var pool = items
        var out: [T] = []
        out.reserveCapacity(items.count)
        while !pool.isEmpty {
            var counts: [K: Int] = [:]
            for item in pool { counts[key(item), default: 0] += 1 }
            let last = out.last.map(key)
            var best: Int?
            for (i, item) in pool.enumerated() where key(item) != last {
                if let b = best, counts[key(pool[b])]! >= counts[key(item)]! { continue }
                best = i
            }
            out.append(pool.remove(at: best ?? 0))
        }
        return out
    }

    /// "Bilemedim" kartını oturuma yeniden eklemek için konum: en az `gap` sonra ve komşuları başka bölümden; yoksa sona.
    static func reinsertIndex<K: Equatable>(_ key: K, in keys: [K], after current: Int, gap: Int = 3) -> Int {
        let start = min(keys.count, current + 1 + gap)
        if start <= keys.count {
            for p in start...keys.count {
                let before = p > 0 ? keys[p - 1] : nil
                let after = p < keys.count ? keys[p] : nil
                if before != key && after != key { return p }
            }
        }
        return keys.count
    }
}

extension ReviewCard {
    /// Zamanlama alanlarının anlık görüntüsü (saklanmaz): son notu geri almak için.
    nonisolated struct Schedule: Equatable, Sendable {
        var ease: Double
        var intervalDays: Int
        var repetitions: Int
        var lapses: Int
        var due: Date
        var lastReviewed: Date?
        var stability: Double
        var memoryDifficulty: Double
        var lastLapseAt: Date?
    }

    var schedule: Schedule {
        get {
            Schedule(ease: ease, intervalDays: intervalDays, repetitions: repetitions, lapses: lapses, due: due,
                     lastReviewed: lastReviewed, stability: stability, memoryDifficulty: memoryDifficulty, lastLapseAt: lastLapseAt)
        }
        set {
            ease = newValue.ease
            intervalDays = newValue.intervalDays
            repetitions = newValue.repetitions
            lapses = newValue.lapses
            due = newValue.due
            lastReviewed = newValue.lastReviewed
            stability = newValue.stability
            memoryDifficulty = newValue.memoryDifficulty
            lastLapseAt = newValue.lastLapseAt
        }
    }

    /// Kaydedilmiş ya da SM-2 alanlarından türetilmiş bellek durumu.
    var memoryState: MemoryModel.State? {
        if stability > 0 { return MemoryModel.State(stability: stability, difficulty: memoryDifficulty > 0 ? memoryDifficulty : 5) }
        return MemoryModel.derived(intervalDays: intervalDays, ease: ease, lapses: lapses, repetitions: repetitions, reviewed: lastReviewed != nil)
    }

    /// Şu anki (ya da verilen tarihteki) hatırlama olasılığı; yeni kartta nil.
    func recallProbability(at date: Date = .now) -> Double? {
        guard let state = memoryState else { return nil }
        let since = lastReviewed ?? createdAt
        return MemoryModel.retrievability(elapsedDays: date.timeIntervalSince(since) / 86_400, stability: state.stability)
    }

    /// Bu notla tekrar edilirse kaç gün sonra (Bilemedim = 1).
    func nextInterval(_ grade: ReviewGrade, now: Date = .now, retention: Double = 0.9) -> Int {
        guard grade != .again else { return 1 }
        let elapsed = lastReviewed.map { now.timeIntervalSince($0) / 86_400 } ?? 0
        return MemoryModel.interval(for: MemoryModel.next(memoryState, rating: MemoryModel.rating(grade), elapsedDays: elapsed).stability, retention: retention)
    }

    /// #32: yeni zamanlayıcı. SM-2 alanları (tekrar, lapse, zayıflık) da güncellenir; tarih bellek modelinden gelir.
    func reviewWithMemory(_ grade: ReviewGrade, now: Date = .now, retention: Double = 0.9) {
        let prior = memoryState
        let elapsed = lastReviewed.map { max(0, now.timeIntervalSince($0) / 86_400) } ?? 0
        review(grade, now: now)
        let next = MemoryModel.next(prior, rating: MemoryModel.rating(grade), elapsedDays: elapsed)
        stability = next.stability
        memoryDifficulty = next.difficulty
        let days = grade == .again ? 1 : MemoryModel.interval(for: next.stability, retention: retention)
        intervalDays = days
        due = Calendar.current.startOfDay(for: now).addingTimeInterval(Double(days) * 86_400 + 4 * 3600)
    }
}
