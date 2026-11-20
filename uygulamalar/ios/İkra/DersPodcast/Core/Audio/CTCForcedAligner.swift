import Foundation

// Madde 50 — cihazda CTC zorlamalı hizalama çekirdeği. Saf Swift: model, ses ve arayüz bağımlılığı yoktur (macOS'ta tek başına derlenir).
// Girdi: akustik modelin kare başına logit matrisi + söylenen metnin kelimeleri. Çıktı: kelime başına başlangıç/bitiş (sn) ve güven
// skoru; biçim sunucudaki hizalamanınkiyle aynıdır (`functions/src/align.ts` `Alignment`; sunucu: deployment/ders-align/server.py).
//
// Üç kural ölçümden gelir (13 Eki 2026, parseh/aligner-tr, Apple Yelda sesi, 84 kelime):
//  1. Blank simgesi model yapılandırmasından ALINMAZ; kare başına ortalama olasılık kütlesi en yüksek simgedir. Yanlış blank çökme
//     üretmez, zamanları sessizce kaydırır (hafıza notu: ctc-blank-simgesi-config-tuzagi).
//  2. Model "|" kelime ayracıyla eğitilmiştir: ayraç hedef diziye konur.
//  3. Okunuşu bilinmeyen kelime (rakam, simge) hedefte tek bir JOKER simgedir. Jokerin kare skoru o karedeki en iyi simgenin
//     skorudur (eksi küçük bir pay): doğru etiketlemeyi hiç geçmez, yalnız yanlış etiketlemeyi geçer; bu yüzden komşu kelimelerin
//     sınırını oynatmaz (ölçüm: 84 kelimenin 14'ü joker yapıldı, öbür kelimelerin hiçbiri bir kare bile kaymadı).
nonisolated enum CTCAlign {
    /// Akustik modelin kare adımı: 320 örnek @ 16 kHz = 20 ms; ilk kare 400 örnek ister.
    static let sampleRate = 16_000, hop = 320, receptive = 400
    static let frameSeconds = Double(hop) / Double(sampleRate)
    /// `samples` örnekten modelin üreteceği kare sayısı.
    static func frameCount(samples: Int) -> Int { samples < receptive ? 0 : (samples - receptive) / hop + 1 }

    // MARK: Emisyonlar

    /// Kare başına log-olasılıklar (satır = kare, sütun = simge).
    struct Emissions: Sendable, Equatable {
        private(set) var frames: Int
        let vocab: Int
        private(set) var values: [Float]

        /// Boş matris; pencereler `append` ile eklenir.
        init(vocab: Int) { self.vocab = max(1, vocab); frames = 0; values = [] }
        /// Ham logitlerden (kare × simge, satır sıralı): her kareye log-softmax uygulanır. Boyut tutmuyorsa ya da sayı bozuksa `nil`.
        init?(logits: [Float], frames: Int, vocab: Int) {
            self.init(vocab: vocab)
            guard append(logits: logits, frames: frames) else { return nil }
        }
        /// Bir pencerenin logitlerini ekler (yalnız `keep` aralığındaki kareler: bağlam kareleri atılır).
        @discardableResult mutating func append(logits: [Float], frames count: Int, keep: Range<Int>? = nil) -> Bool {
            guard count >= 0, vocab > 0, logits.count == count * vocab else { return false }
            let range = keep ?? 0..<count
            guard range.lowerBound >= 0, range.upperBound <= count else { return false }
            var rows = [Float](); rows.reserveCapacity(range.count * vocab)
            for t in range {
                let row = logits[(t * vocab)..<((t + 1) * vocab)]
                guard let top = row.max(), top.isFinite else { return false }
                var sum: Float = 0
                for value in row { sum += exp(value - top) }
                let shift = top + log(sum)
                for value in row { rows.append(value - shift) }
            }
            values += rows; frames += range.count
            return true
        }
        subscript(frame: Int, label: Int) -> Float { values[frame * vocab + label] }
    }

    /// Blank simgesi: kare başına ortalama olasılık kütlesi en yüksek simge (kütlesiyle birlikte). Kare yoksa `nil`.
    static func blank(of emissions: Emissions) -> (index: Int, mass: Double)? {
        guard emissions.frames > 0 else { return nil }
        var mass = [Double](repeating: 0, count: emissions.vocab)
        emissions.values.withUnsafeBufferPointer { values in
            for t in 0..<emissions.frames { for v in 0..<emissions.vocab { mass[v] += Double(exp(values[t * emissions.vocab + v])) } }
        }
        guard let best = mass.indices.max(by: { mass[$0] < mass[$1] }) else { return nil }
        return (best, mass[best] / Double(emissions.frames))
    }

    // MARK: Metin

    /// Modelin simge sözlüğü (`vocab.json`: simge → kimlik). Yalnız tek karakterli simgeler hizalanır; "|" kelime ayracıdır.
    struct Vocabulary: Sendable, Equatable {
        var ids: [Character: Int]
        var delimiter: Int?
        /// Sözlükteki simge sayısı (modelin çıktı genişliğiyle aynı olmalı).
        var count: Int

        init(ids: [Character: Int], delimiter: Int?, count: Int) { self.ids = ids; self.delimiter = delimiter; self.count = count }
        init?(json: Data) {
            guard let table = try? JSONDecoder().decode([String: Int].self, from: json), !table.isEmpty,
                  Set(table.values).count == table.count, let top = table.values.max(), table.values.allSatisfy({ $0 >= 0 }) else { return nil }
            var ids: [Character: Int] = [:]
            for (token, id) in table where token.count == 1 && token != "|" { ids[Character(token)] = id }
            guard ids.keys.contains(where: \.isLetter) else { return nil }
            self.init(ids: ids, delimiter: table["|"], count: top + 1)
        }
    }

    /// Türkçe küçük harf + sözlükte olmayan şapkalı harflerin ve tipografik kesme işaretinin sadeleştirilmesi.
    /// (Swift'in `lowercased()` çıktısı "İ" için i + birleşen nokta, "I" için ı değil i verir.)
    static func fold(_ word: String) -> String {
        var out = ""
        for character in word {
            switch character {
            case "I": out.append("ı")
            case "İ": out.append("i")
            case "â", "Â": out.append("a")
            case "î", "Î": out.append("i")
            case "û", "Û": out.append("u")
            case "’", "‘", "ʼ", "`", "´": out.append("'")
            default: out += String(character).lowercased()
            }
        }
        return out
    }

    /// Kelimenin hizalanacak simgeleri. Hizalanamıyorsa `nil`: rakam içeriyor (okunuşu bilinmiyor) ya da sözlükte tek harfi yok.
    static func tokens(_ word: String, vocabulary: Vocabulary) -> [Int]? {
        var result: [Int] = [], letters = 0
        for character in fold(word) {
            if character.isNumber { return nil }
            guard let id = vocabulary.ids[character] else { continue }
            result.append(id)
            if character.isLetter { letters += 1 }
        }
        return letters > 0 ? result : nil
    }

    /// Hedef dizi: kelimelerin simgeleri, aralarında ayraç; art arda hizalanamayan kelimeler tek jokerdir (kimliği `wildcard`).
    /// `owner[k]`: k. hedef simgenin ait olduğu kelime sırası; ayraç ve joker için -1.
    static func target(words: [String], vocabulary: Vocabulary, wildcard: Int) -> (labels: [Int], owner: [Int], aligned: [Bool]) {
        var labels: [Int] = [], owner: [Int] = [], aligned = [Bool](repeating: false, count: words.count), lastWild = false
        for (index, word) in words.enumerated() {
            guard let ids = tokens(word, vocabulary: vocabulary) else {
                if !lastWild {
                    if !labels.isEmpty, let delimiter = vocabulary.delimiter { labels.append(delimiter); owner.append(-1) }
                    labels.append(wildcard); owner.append(-1)
                }
                lastWild = true
                continue
            }
            if !labels.isEmpty, let delimiter = vocabulary.delimiter { labels.append(delimiter); owner.append(-1) }
            for id in ids { labels.append(id); owner.append(index) }
            aligned[index] = true; lastWild = false
        }
        return (labels, owner, aligned)
    }

    // MARK: Viterbi

    struct Path: Sendable, Equatable {
        /// Her hedef simgenin kapladığı kareler (ilk ve son, kapalı aralık).
        var first: [Int]
        var last: [Int]
        /// En iyi yolun kare başına log-olasılığı.
        var scores: [Float]
    }

    /// Jokerin, karedeki en iyi simgeye göre payı: eşitlikte gerçek simge kazanır.
    static let wildcardPenalty: Float = 0.05
    /// Geri izleme tablosunun üst sınırı (hücre; 2 bit/hücre → 24 MB). Aşılırsa hizalama yapılmaz.
    static let maxCells = 96_000_000

    /// Hedef diziyi karelere zorlar (CTC: simgeler arasında isteğe bağlı blank, aynı simge yinelenirse zorunlu blank).
    /// `labels` içinde `emissions.vocab` değeri jokerdir. Yol yoksa (ses hedefe göre çok kısa) ya da tablo sınırı aşılırsa `nil`.
    static func viterbi(_ emissions: Emissions, labels: [Int], blank: Int) -> Path? {
        let frames = emissions.frames, vocab = emissions.vocab, count = labels.count
        guard frames > 0, count > 0, count <= frames, (0..<vocab).contains(blank),
              labels.allSatisfy({ $0 >= 0 && $0 <= vocab && $0 != blank }) else { return nil }
        let states = 2 * count + 1
        guard frames <= maxCells / states else { return nil }
        // Joker emisyonu: karedeki en iyi log-olasılık (yalnız joker varsa hesaplanır).
        let wild: [Float] = labels.contains(vocab)
            ? (0..<frames).map { t in (emissions.values[(t * vocab)..<((t + 1) * vocab)].max() ?? 0) - wildcardPenalty } : []
        // Durum s: çift → blank, tek → labels[s / 2]. Blank atlanarak geçiş (s-2 → s) yalnız iki simge farklıysa serbesttir.
        var skip = [Bool](repeating: false, count: states)
        for k in 1..<max(1, count) where labels[k] != labels[k - 1] { skip[2 * k + 1] = true }
        var back = [UInt8](repeating: 0, count: (frames * states + 3) / 4)
        var previous = [Float](repeating: -.infinity, count: states), current = previous
        func emission(_ t: Int, _ s: Int) -> Float {
            if s & 1 == 0 { return emissions.values[t * vocab + blank] }
            let label = labels[s >> 1]
            return label == vocab ? wild[t] : emissions.values[t * vocab + label]
        }
        previous[0] = emission(0, 0)
        previous[1] = emission(0, 1)
        for t in 1..<max(1, frames) {
            // Ulaşılabilir durumlar: baştan en çok 2t+1'e gelinir; sondan geriye 2 adımda bir durum kapanır.
            let low = max(0, states - 2 - 2 * (frames - 1 - t)), high = min(states - 1, 2 * t + 1)
            if low > 0 { for s in max(0, low - 4)..<low { current[s] = -.infinity } }
            guard low <= high else { return nil }
            for s in low...high {
                var best = previous[s]; var step: UInt8 = 0
                if s >= 1, previous[s - 1] > best { best = previous[s - 1]; step = 1 }
                if s >= 2, skip[s], previous[s - 2] > best { best = previous[s - 2]; step = 2 }
                current[s] = best == -.infinity ? -.infinity : best + emission(t, s)
                if step != 0 { let cell = t * states + s; back[cell >> 2] |= step << UInt8((cell & 3) << 1) }
            }
            swap(&previous, &current)
        }
        var state = previous[states - 1] >= previous[states - 2] ? states - 1 : states - 2
        guard previous[state] > -.infinity else { return nil }
        var first = [Int](repeating: -1, count: count), last = first, scores = [Float](repeating: 0, count: frames)
        for t in stride(from: frames - 1, through: 0, by: -1) {
            scores[t] = emission(t, state)
            if state & 1 == 1 { let k = state >> 1; first[k] = t; if last[k] < 0 { last[k] = t } }
            let cell = t * states + state
            state -= Int((back[cell >> 2] >> UInt8((cell & 3) << 1)) & 3)
        }
        guard state >= 0, !first.contains(-1) else { return nil }
        return Path(first: first, last: last, scores: scores)
    }

    // MARK: Kelime zamanları

    /// Hizalanmış bir kelime (sunucudaki `AlignedWord` ile aynı alanlar).
    struct Word: Sendable, Equatable {
        var word: String
        var start: Double
        var end: Double
        /// Kelimenin kare başına ortalama log-olasılığı (0'a yakın iyi; yanlış okunan kelimede ≈ −4). Komşulardan doldurulduysa `nil`.
        var score: Double?
        var interpolated: Bool
    }
    /// Sunucudaki `Alignment` biçimi + cihazdaki kalite kapısının kullandığı ek ölçüler.
    struct Alignment: Sendable, Equatable {
        var words: [Word]
        /// Komşulardan doldurulmayan kelimelerin oranı.
        var coverage: Double
        var minScore: Double?
        var meanScore: Double?
        /// Hizalanan kelimelerin (güvensizler dahil) ortanca skoru: metin sese hiç uymuyorsa ≈ −2, uyuyorsa ≈ −0,03.
        var medianScore: Double?
        var blank: Int
        var blankMass: Double
    }

    /// Ölçüm (Apple Yelda, 84 kelime): CTC başlangıcı işaretçiden ortalama 12 ms sonra. Bitiş payı sunucudaki değerdir (bu modelde ölçülmedi).
    static let startBias = 0.012, endExtend = 0.065
    /// Bu skorun altındaki kelime metne uymuyor sayılır (sunucudaki yeniden sentez eşiğiyle aynı): zamanı komşularından doldurulur.
    static let lowScore = -2.5

    /// Emisyonları kelimelere hizalar. `duration`: sesin süresi (sn). Yol bulunamazsa ya da hiçbir kelime hizalanamazsa `nil`.
    static func align(_ emissions: Emissions, words: [String], vocabulary: Vocabulary, duration: Double) -> Alignment? {
        guard !words.isEmpty, duration > 0, vocabulary.count == emissions.vocab, let silence = blank(of: emissions) else { return nil }
        let plan = target(words: words, vocabulary: vocabulary, wildcard: emissions.vocab)
        guard plan.aligned.contains(true), let path = viterbi(emissions, labels: plan.labels, blank: silence.index) else { return nil }
        var from = [Int?](repeating: nil, count: words.count), to = from
        for (k, owner) in plan.owner.enumerated() where owner >= 0 {
            if from[owner] == nil { from[owner] = path.first[k] }
            to[owner] = path.last[k] + 1
        }
        var result = words.map { Word(word: $0, start: 0, end: 0, score: nil, interpolated: true) }
        var all: [Double] = []
        for index in words.indices {
            guard let a = from[index], let b = to[index] else { continue }
            let span = path.scores[a..<max(b, a + 1)]
            let score = Double(span.reduce(0, +)) / Double(span.count)
            all.append(score)
            guard score >= lowScore else { continue }
            result[index].start = max(0, Double(a) * frameSeconds - startBias)
            result[index].end = min(duration, Double(b) * frameSeconds + endExtend)
            result[index].score = score; result[index].interpolated = false
        }
        fill(&result, duration: duration)
        let scores = result.compactMap(\.score), sorted = all.sorted()
        return Alignment(words: result, coverage: Double(scores.count) / Double(words.count), minScore: scores.min(),
                         meanScore: scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count),
                         medianScore: sorted.isEmpty ? nil : sorted[sorted.count / 2], blank: silence.index, blankMass: silence.mass)
    }

    /// Hizalanamayan kelimeler komşuları arasına harf ağırlığıyla dağıtılır (uçlarda 0 ve süre); bitiş sonraki başlangıcı aşmaz.
    static func fill(_ words: inout [Word], duration: Double) {
        var index = 0
        while index < words.count {
            guard words[index].interpolated else { index += 1; continue }
            var stop = index
            while stop < words.count, words[stop].interpolated { stop += 1 }
            // Önceki kelimenin bitişi uzatma payıyla sonraki başlangıcı aşabilir: başlangıçlar azalmasın diye sola üst sınır konur.
            let right = stop < words.count ? words[stop].start : duration, left = min(index > 0 ? words[index - 1].end : 0, right)
            let weights = (index..<stop).map { Double(words[$0].word.count + 1) }, total = max(1, weights.reduce(0, +))
            var cursor = left
            for (offset, position) in (index..<stop).enumerated() {
                let span = max(0, right - left) * weights[offset] / total
                words[position].start = cursor; words[position].end = min(duration, cursor + span)
                cursor += span
            }
            index = stop
        }
        for position in words.indices.dropLast() {
            words[position].end = max(words[position].start, min(words[position].end, words[position + 1].start))
        }
    }

    // MARK: Pencereler

    /// Akustik modele verilecek ses dilimi (örnek cinsinden): modele `input` verilir (sonuna `padding` sıfır eklenerek),
    /// çıktının ilk `skip` karesi (bağlam) atılır ve `frames` kare alınır.
    struct Window: Sendable, Equatable {
        var input: Range<Int>
        var padding: Int
        var skip: Int
        var frames: Int
    }

    /// Sesi `core` saniyelik çekirdeklere böler; her pencere iki yanından `context` kare bağlam alır (kenar etkisine karşı).
    /// Bütün pencerelerin girdi boyu AYNIDIR (ilk pencere eksik sol bağlamını sağdan, son pencere sola kayarak tamamlar; son
    /// pencereye bir kareden kısa sıfır dolgu gelebilir): onnxruntime aynı biçimli girdide belleğini yeniden kullanır, böylece
    /// tepe bellek sesin uzunluğundan bağımsız kalır (ölçüm: 10 sn çekirdekte ilk pencereden sonra sabit, benzeticide 0,61 GB;
    /// değişken boylu pencerelerde her pencerede büyüyordu, bütün klip tek girdiyken 41,8 sn için 2,2 GB). Kesimler kare
    /// sınırındadır: pencerelerin kareleri bütün sesin kareleriyle aynı ızgaraya oturur (ölçüm: bütün klibe göre en çok 1–2
    /// kare fark, doğruluk aynı).
    static func windows(samples: Int, core: Double = 10, context: Int = 16) -> [Window] {
        let total = frameCount(samples: samples)
        guard total > 0 else { return [] }
        let coreSamples = max(1, Int(core * Double(sampleRate)) / hop) * hop, margin = max(1, context) * hop
        let length = coreSamples + 2 * margin
        guard samples > length else { return [Window(input: 0..<samples, padding: 0, skip: 0, frames: total)] }
        var result: [Window] = [], start = 0
        while samples - start > coreSamples + margin {
            let from = max(0, start - margin)
            result.append(Window(input: from..<(from + length), padding: 0, skip: (start - from) / hop, frames: coreSamples / hop))
            start += coreSamples
        }
        // Son pencere: girdi sesin sonunda biter, başı kare sınırına yukarı yuvarlanır (eksik kalan bir kareden azı sıfırla dolar).
        let from = min(start, (samples - length + hop - 1) / hop * hop)
        result.append(Window(input: from..<samples, padding: length - (samples - from), skip: (start - from) / hop, frames: total - start / hop))
        return result
    }

    /// Akustik modelin beklediği girdi: sıfır ortalama, birim varyans (pencere başına); `padding` kadar sıfır sona eklenir.
    static func normalized(_ samples: ArraySlice<Float>, padding: Int = 0) -> [Float] {
        guard !samples.isEmpty else { return [] }
        var mean = 0.0
        for value in samples { mean += Double(value) }
        mean /= Double(samples.count)
        var variance = 0.0
        for value in samples { let d = Double(value) - mean; variance += d * d }
        let scale = 1 / (variance / Double(samples.count) + 1e-7).squareRoot()
        return samples.map { Float((Double($0) - mean) * scale) } + [Float](repeating: 0, count: max(0, padding))
    }
}
