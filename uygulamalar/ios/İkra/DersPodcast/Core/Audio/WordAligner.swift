import Foundation

/// Tanıyıcının bulduğu kelime (zamanlar sn).
nonisolated struct RecognizedWord: Sendable, Equatable {
    var text: String
    var start: Double
    var end: Double
}

/// #13/#20: bilinen metin ile tanınan kelimelerin dinamik programlamayla hizalanması.
nonisolated enum WordAligner {
    /// Eşleşme anahtarı: Türkçe katlama, harf/rakam dışı karakterler atılır.
    static func key(_ word: String) -> String {
        String(TurkishFold.fold(word).filter { $0.isLetter || $0.isNumber })
    }

    /// Aynı ya da yakın (Türkçe ek farkı, tanıma hatası) kelime mi?
    static func similar(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        let longer = max(a.count, b.count)
        guard min(a.count, b.count) >= 4 else { return false }
        return distance(Array(a), Array(b)) <= max(1, Int(Double(longer) * 0.34))
    }

    static func distance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = previous
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// `expected[i]` ile eşleşen `recognized` indeksi (yoksa nil). Monoton, en az düzenlemeli hizalama.
    static func align(expected: [String], recognized: [String]) -> [Int?] {
        let e = expected.map(key), r = recognized.map(key)
        let n = e.count, m = r.count
        guard n > 0, m > 0 else { return Array(repeating: nil, count: n) }
        let width = m + 1
        var cost = [Int](repeating: 0, count: (n + 1) * width)
        var same = [Bool](repeating: false, count: n * m)
        for i in 0...n { cost[i * width] = i }
        for j in 0...m { cost[j] = j }
        for i in 1...n {
            for j in 1...m {
                let match = similar(e[i - 1], r[j - 1])
                same[(i - 1) * m + (j - 1)] = match
                cost[i * width + j] = min(cost[(i - 1) * width + j - 1] + (match ? 0 : 1),
                                          cost[(i - 1) * width + j] + 1,
                                          cost[i * width + j - 1] + 1)
            }
        }
        var result = [Int?](repeating: nil, count: n)
        var i = n, j = m
        while i > 0, j > 0 {
            let here = cost[i * width + j]
            if same[(i - 1) * m + (j - 1)], here == cost[(i - 1) * width + j - 1] {
                result[i - 1] = j - 1
                i -= 1; j -= 1
            } else if here == cost[(i - 1) * width + j] + 1 {
                i -= 1
            } else if here == cost[i * width + j - 1] + 1 {
                j -= 1
            } else {
                i -= 1; j -= 1
            }
        }
        return result
    }

    /// Tanınan sayıları ve simgeleri konuşulan biçime açar ("1990" → bin dokuz yüz doksan); süre kelimelere bölünür.
    static func expand(_ words: [RecognizedWord]) -> [RecognizedWord] {
        var out: [RecognizedWord] = []
        for word in words {
            let parts = word.text.split(whereSeparator: \.isWhitespace).map(String.init)
            let spoken = TurkishReading.read(parts).flatMap { $0 }.filter { !key($0).isEmpty }
            guard spoken.count > 1 else {
                if !key(word.text).isEmpty { out.append(word) }
                continue
            }
            let step = max(0, word.end - word.start) / Double(spoken.count)
            for (k, w) in spoken.enumerated() {
                out.append(RecognizedWord(text: w, start: word.start + Double(k) * step, end: word.start + Double(k + 1) * step))
            }
        }
        return out
    }

    /// Beklenen kelimelerin başlangıç zamanları. Eşleşenler tanıyıcı zamanını alır; eşleşmeyenler komşu çapalar
    /// arasında karakter uzunluğuna göre monoton doldurulur. `matched`: çapa sayısı.
    static func startTimes(expected: [String], recognized: [RecognizedWord], span: ClosedRange<Double>) -> (times: [Double], matched: Int) {
        guard !expected.isEmpty else { return ([], 0) }
        let words = expand(recognized)
        let matches = align(expected: expected, recognized: words.map(\.text))
        var anchors: [(index: Int, time: Double)] = []
        for (i, match) in matches.enumerated() {
            guard let match else { continue }
            let t = min(max(words[match].start, span.lowerBound), span.upperBound)
            if let last = anchors.last, t < last.time { continue }
            anchors.append((i, t))
        }
        // Kelime konumu: önceki kelimelerin karakter ağırlığı.
        var position = [Double](repeating: 0, count: expected.count + 1)
        for (i, w) in expected.enumerated() { position[i + 1] = position[i] + Double(max(1, w.count)) + 1 }
        var times = [Double](repeating: span.lowerBound, count: expected.count)
        // Son çapadan sonraki kelimeler parçanın sonuna kadar yayılır (tanıyıcı kuyruğu kaçırmış olabilir).
        let bounds = [(index: -1, time: span.lowerBound)] + anchors + [(index: expected.count, time: max(span.upperBound, anchors.last?.time ?? span.lowerBound))]
        for k in 0..<(bounds.count - 1) {
            let a = bounds[k], b = bounds[k + 1]
            if a.index >= 0 { times[a.index] = a.time }
            let pa = a.index >= 0 ? position[a.index] : 0
            let pb = position[min(b.index, expected.count)]
            for i in (a.index + 1)..<b.index where i >= 0 {
                let f = pb > pa ? (position[i] - pa) / (pb - pa) : 0
                times[i] = a.time + (b.time - a.time) * f
            }
        }
        for i in 1..<times.count where times[i] < times[i - 1] { times[i] = times[i - 1] }
        return (times, anchors.count)
    }

    /// Turların ORİJİNAL kelimelerinin başlangıçları (her tur için) ve kapsama oranı (eşleşen/beklenen konuşulan kelime).
    /// `spans` verilirse her turun zamanı kendi aralığına sıkıştırılır.
    static func turnWordTimes(_ turns: [ScriptTurn], language: PodcastLanguage, dictionary: [Pronunciation],
                              recognized: [RecognizedWord], span: ClosedRange<Double>,
                              spans: [ClosedRange<Double>]? = nil) -> (times: [[Double]], coverage: Double) {
        let prepared = SpeakableText.prepare(turns, language: language, dictionary: dictionary)
        let spoken = prepared.turns.map { $0.text.split(whereSeparator: \.isWhitespace).map(String.init) }
        let flat = spoken.flatMap { $0 }
        guard !flat.isEmpty else { return (turns.map { _ in [] }, 0) }
        let aligned = startTimes(expected: flat, recognized: recognized, span: span)
        var result: [[Double]] = []
        var offset = 0
        for (t, turn) in turns.enumerated() {
            let count = spoken[t].count
            let spokenTimes = Array(aligned.times[offset..<(offset + count)])
            offset += count
            let originalCount = turn.text.split(whereSeparator: \.isWhitespace).count
            var times = [Double?](repeating: nil, count: originalCount)
            for (k, original) in prepared.wordMap[t].enumerated() where k < spokenTimes.count && original < originalCount && times[original] == nil {
                times[original] = spokenTimes[k]
            }
            // Konuşulan karşılığı olmayan kelimeler (ör. yalnız noktalama) komşudan alınır.
            var filled: [Double] = []
            var last = spokenTimes.first ?? span.lowerBound
            for value in times {
                if let value { last = value }
                filled.append(last)
            }
            if let spans, spans.indices.contains(t) { let range = spans[t]; filled = filled.map { min(max($0, range.lowerBound), range.upperBound) } }
            result.append(filled)
        }
        return (result, Double(aligned.matched) / Double(flat.count))
    }
}
