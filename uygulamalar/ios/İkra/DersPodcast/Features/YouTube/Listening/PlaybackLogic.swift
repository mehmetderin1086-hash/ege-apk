import Foundation

// Ders oynatıcısının saf karar mantığı (arayüzden ve AVPlayer'dan bağımsız, test edilebilir).

// MARK: - A–B döngü (#15)

nonisolated struct ABLoop: Equatable, Sendable {
    var start: Double
    var end: Double

    static let minLength = 1.0
    /// Döngü bitişini bu kadar aşan konum "kullanıcı başka yere gitti" sayılır (döngü kapanır).
    static let overshoot = 2.5

    /// Geçerli (bitiş başlangıçtan en az 1 sn sonra) döngü; değilse nil.
    init?(start: Double, end: Double) {
        guard start.isFinite, end.isFinite, start >= 0, end - start >= Self.minLength else { return nil }
        self.start = start
        self.end = end
    }

    enum Action: Equatable, Sendable {
        case none
        /// Bitişe geldi: başa dön.
        case wrap(to: Double)
        /// Kullanıcı döngünün dışına atladı: döngüyü kapat.
        case cancel
    }

    func action(at time: Double) -> Action {
        guard time.isFinite else { return .none }
        if time >= end { return time < end + Self.overshoot ? .wrap(to: start) : .cancel }
        if time < start - Self.overshoot { return .cancel }
        return .none
    }
}

// MARK: - Sessizlikleri atla (#12)

nonisolated enum SilenceSkip {
    /// Atlanacak en kısa sessizlik (sn).
    static let minPause = 0.6
    /// Sessizliğin başında ve sonunda bırakılan pay: nefes payı kalır, sonraki sözcüğün başı kesilmez.
    static let lead = 0.15

    /// `time` uzun bir sessizliğin içindeyse atlanacak konum (sessizliğin bitişinden biraz önce); değilse nil.
    /// `pauses` başlangıca göre sıralıdır (`SpeechPauses` böyle üretir).
    static func target(at time: Double, pauses: [FollowAlong.Pause]) -> Double? {
        guard time.isFinite, !pauses.isEmpty else { return nil }
        // start <= time olan son sessizlik.
        var lo = 0, hi = pauses.count - 1
        guard pauses[0].start <= time else { return nil }
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if pauses[mid].start <= time { lo = mid } else { hi = mid - 1 }
        }
        let pause = pauses[lo]
        guard pause.end - pause.start >= minPause, time >= pause.start + lead, time < pause.end - lead else { return nil }
        let target = pause.end - lead
        return target - time > 0.1 ? target : nil
    }
}

// MARK: - Bölüm gezintisi (#17 kilit ekranı)

nonisolated enum ChapterNav {
    /// Önceki bölüme dönerken, bölümün ilk bu kadar saniyesinde bir öncekine gidilir (aksi hâlde bölüm başına).
    static let restartWindow = 3.0

    /// Sonraki/önceki bölümün başlangıcı. `starts` sıralı olmak zorunda değildir. Gidilecek yer yoksa nil.
    static func target(from time: Double, starts: [Double], forward: Bool) -> Double? {
        let sorted = starts.sorted()
        if forward { return sorted.first { $0 > time + 0.5 } }
        if let previous = sorted.last(where: { $0 < time - restartWindow }) { return previous }
        return time > 1 ? (sorted.first ?? 0) : nil   // ilk bölümün içindeyiz: bölümü baştan çal
    }

    /// `time` anındaki bölümün bitişi (sonraki bölümün başı; son bölümde `duration`). Süre bilinmiyorsa ve bölüm sonuncuysa nil.
    static func chapterEnd(at time: Double, starts: [Double], duration: Double) -> Double? {
        let sorted = starts.sorted()
        if let next = sorted.first(where: { $0 > time + 0.01 }) { return next }
        return duration > time ? duration : nil
    }
}

// MARK: - Uyku zamanlayıcısı (#17)

nonisolated enum LessonSleep: Equatable, Sendable {
    case until(Date)
    /// Çalan bölüm bitince (konum sn).
    case endOfChapter(Double)

    func isDue(time: Double, now: Date) -> Bool {
        switch self {
        case .until(let date): now >= date
        case .endOfChapter(let end): time >= end
        }
    }

    static let minuteOptions = [5, 10, 15, 30, 45, 60]
}

// MARK: - Geri sarma ısı şeridi (#30)

nonisolated enum RewindHeat {
    /// Kaydedilecek en çok geri sarma sayısı (en eskiler düşer).
    static let limit = 600
    /// Bundan kısa geri gidiş (kaydırma titremesi) ve bundan uzun atlama (bölüme gitme) geri sarma sayılmaz.
    static let minJump = 2.0
    static let maxJump = 120.0

    /// `from` anında `to` anına geri gidildi: zorlanılan an. Geri alınan aralığın ortası (en çok 20 sn'lik kısmın) alınır;
    /// 10 sn geri → 5 sn öncesi, uzun geri sürüklemede hedefe yakın bir an. Geri sarma değilse nil.
    static func moment(from: Double, to: Double) -> Double? {
        let jump = from - to
        guard from.isFinite, to.isFinite, jump >= minJump, jump <= maxJump else { return nil }
        return to + min(jump, 20) / 2
    }

    /// Anı listeye ekler (kopyala-değiştir-ata için yeni dizi döner); sınır aşılırsa en eskiler düşer.
    static func appending(_ moment: Double, to times: [Double]) -> [Double] {
        var all = times
        all.append(moment)
        return all.count > limit ? Array(all.suffix(limit)) : all
    }

    /// 0…1 arası `count` kovanın yoğunluğu (kova başına geri sarma sayısı; 3'ten az sarma varsa soluk kalır).
    static func buckets(times: [Double], duration: Double, count: Int) -> [Double] {
        guard count > 0, duration > 0, duration.isFinite else { return [] }
        var counts = [Double](repeating: 0, count: count)
        for t in times where t.isFinite && t >= 0 && t <= duration {
            counts[min(count - 1, Int(t / duration * Double(count)))] += 1
        }
        let peak = max(3, counts.max() ?? 0)
        return counts.map { min(1, $0 / peak) }
    }
}

// MARK: - İzleme süresi (#33)

nonisolated struct WatchAccumulator: Sendable {
    /// Kayda alınacak en kısa parça (sn).
    static let minChunk = 10.0
    /// İki tik arasında sayılan en uzun süre (uygulama donarsa/askıya alınırsa şişmesin).
    static let maxStep = 1.5
    /// Kesintisiz izlemede bu süreye gelince parça kaydedilir.
    static let maxChunk = 600.0

    struct Chunk: Equatable, Sendable {
        var start: Date
        var seconds: Double
    }

    private(set) var pending = 0.0
    private var startedAt: Date?
    private var lastTick: Date?

    /// Oynarken her oynatıcı tikinde çağrılır; `maxChunk`a gelince parçayı döndürür.
    mutating func tick(now: Date) -> Chunk? {
        if let last = lastTick {
            pending += min(Self.maxStep, max(0, now.timeIntervalSince(last)))
        } else if startedAt == nil {
            startedAt = now
        }
        lastTick = now
        return pending >= Self.maxChunk ? emit(now: now) : nil
    }

    /// Oynatma durdu: birikim ≥ 10 sn ise parçayı döndürür; değilse birikim sürer (sonraki izlemeye eklenir).
    mutating func stop(now: Date) -> Chunk? {
        lastTick = nil
        return pending >= Self.minChunk ? emit(now: now) : nil
    }

    private mutating func emit(now: Date) -> Chunk {
        let chunk = Chunk(start: startedAt ?? now.addingTimeInterval(-pending), seconds: pending)
        pending = 0
        startedAt = nil
        return chunk
    }
}

// MARK: - Kelimeye dokununca atla (#16)

nonisolated enum WordSeek {
    static let scheme = "dersseek"

    /// Satırdaki `word`. kelimeye bağlantı: dersseek://<satır>/<kelime>.
    static func url(row: Int, word: Int) -> URL? {
        URL(string: "\(scheme)://\(row)/\(word)")
    }

    static func parse(_ url: URL) -> (row: Int, word: Int)? {
        guard url.scheme == scheme, let host = url.host(), let row = Int(host),
              let word = Int(url.lastPathComponent) else { return nil }
        return (row, word)
    }

    /// Satırdaki kelimenin başlama zamanı (kelime zamanı varsa o; yoksa parçalara/ağırlıklara göre tahmin).
    static func time(of word: Int, in row: TranscriptRow) -> Double? {
        let timing = FollowAlong.Timing(text: row.text, start: row.start, end: row.end, spans: row.spans)
        return timing.times.indices.contains(word) ? timing.times[word] : nil
    }
}

// MARK: - İlerleme çubuğu önizlemesi

/// Çubuk sürüklenirken gösterilen hedef: "12:34 · +1:20" (bırakılacak an · geçerli konuma göre fark).
nonisolated enum ScrubPreview {
    /// Fark 1 sn'den azsa yalnız an yazılır; sonlu olmayan/eksi değerler 0 sayılır. Tam saniyeler karşılaştırılır
    /// (yandaki süre etiketi de saniyeyi aşağı yuvarlar; kabarcıktaki fark etiketlerin farkıyla aynı olur).
    static func label(target: Double, current: Double) -> String {
        let to = (target.isFinite ? max(0, target) : 0).rounded(.down)
        let from = (current.isFinite ? max(0, current) : 0).rounded(.down)
        let time = TranscriptFormat.timestamp(to)
        let delta = to - from
        guard abs(delta) >= 1 else { return time }
        return "\(time) · \(delta > 0 ? "+" : "−")\(VideoTime.string(abs(delta)))"
    }
}
