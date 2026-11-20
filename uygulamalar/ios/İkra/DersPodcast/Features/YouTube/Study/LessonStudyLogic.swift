import Foundation

// Ders araçlarının saf mantığı (görünümden ve ağdan bağımsız, test edilir).

/// Saniye cinsinden kapalı olmayan aralık [start, end).
nonisolated struct ClipRange: Hashable, Sendable, Codable {
    var start: Double
    var end: Double
    var duration: Double { max(0, end - start) }
}

// MARK: - Metin hazırlama

nonisolated enum StudyText {
    /// Paragrafları "[mm:ss] metin" satırlarına çevirir. `maxChars` aşılırsa her paragraf oransal kısaltılır
    /// (derse yayılan kapsam korunur; baştan kesmek sonlardaki konuları düşürürdü).
    static func lines(_ paragraphs: [TranscriptParagraph], maxChars: Int = 60_000) -> String {
        let sorted = paragraphs.sorted { $0.start < $1.start }
            .map { (start: $0.start, text: clean($0.text)) }
            .filter { !$0.text.isEmpty }
        let prefixLength = { (start: Double) in "[\(TranscriptFormat.timestamp(start))] ".count + 1 }
        let total = sorted.reduce(0) { $0 + prefixLength($1.start) + $1.text.count }
        guard total > maxChars, !sorted.isEmpty else {
            return sorted.map { "[\(TranscriptFormat.timestamp($0.start))] \($0.text)" }.joined(separator: "\n")
        }
        // Başlık payı düşülür; kalan metin bütçesi paragraflara oransal dağıtılır.
        let overhead = sorted.reduce(0) { $0 + prefixLength($1.start) }
        let textTotal = max(1, total - overhead)
        let ratio = Double(max(0, maxChars - overhead)) / Double(textTotal)
        let kept = sorted.map { item -> String in
            let limit = max(40, Int(Double(item.text.count) * ratio))
            return "[\(TranscriptFormat.timestamp(item.start))] \(excerpt(item.text, maxChars: limit))"
        }
        return String(kept.joined(separator: "\n").prefix(maxChars))
    }

    /// `[from, to)` aralığında başlayan paragraflar.
    static func lines(_ paragraphs: [TranscriptParagraph], from: Double, to: Double, maxChars: Int = 60_000) -> String {
        lines(paragraphs.filter { $0.start >= from - 0.01 && $0.start < to }, maxChars: maxChars)
    }

    /// "Anlamadım": `time` anında biten son `seconds` saniyenin paragrafları (anın paragrafı her zaman dahil).
    static func recentLines(_ paragraphs: [TranscriptParagraph], endingAt time: Double, seconds: Double = 90) -> String {
        let sorted = paragraphs.sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return "" }
        var picked = sorted.filter { $0.end > time - seconds && $0.start <= time + 0.5 }
        if picked.isEmpty {
            let starts = sorted.map(\.start)
            picked = [sorted[TranscriptFormat.index(at: time, starts: starts) ?? 0]]
        }
        return lines(picked, maxChars: 12_000)
    }

    /// Boşlukları sadeleştirir.
    static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Sözcük sınırında kısaltır; kısalttıysa "…" ekler.
    static func excerpt(_ text: String, maxChars: Int) -> String {
        let cleaned = clean(text)
        guard cleaned.count > maxChars, maxChars > 1 else { return cleaned }
        let head = String(cleaned.prefix(maxChars))
        let cut = head.lastIndex(of: " ").map { String(head[..<$0]) } ?? head
        let base = cut.count >= maxChars / 2 ? cut : head
        return base.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—")) + "…"
    }

    /// Bölümün aralığı: başlangıcı bölümün kendisi, bitişi sonraki bölümün başı (sonuncuda `end`).
    static func chapterRange(_ chapters: [VideoChapter], index: Int, end: Double) -> ClipRange? {
        let sorted = chapters.sorted { $0.start < $1.start }
        guard sorted.indices.contains(index) else { return nil }
        let stop = sorted.indices.contains(index + 1) ? sorted[index + 1].start : max(end, sorted[index].start)
        return ClipRange(start: sorted[index].start, end: stop)
    }

    /// `time` anının bölüm sırası (bölümden önceyse 0; bölüm yoksa nil).
    static func chapterIndex(_ chapters: [VideoChapter], at time: Double) -> Int? {
        let sorted = chapters.sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return nil }
        return sorted.lastIndex { $0.start <= time + 0.5 } ?? 0
    }

    /// Feynman karşılaştırma metni: bölüm verildiyse o bölümün düz metni; yoksa özet + ana noktalar + kavramlar
    /// (not yoksa dersin başındaki paragraflar). En çok `maxChars` karakter.
    static func reference(_ transcript: VideoTranscript, chapter: Int?, end: Double, maxChars: Int = 20_000) -> String {
        if let chapter, let range = chapterRange(transcript.chapters, index: chapter, end: end) {
            let text = transcript.paragraphs.sorted { $0.start < $1.start }
                .filter { $0.start >= range.start - 0.01 && $0.start < range.end }
                .map { clean($0.text) }.joined(separator: "\n")
            return String(text.prefix(maxChars))
        }
        var parts: [String] = []
        if let notes = transcript.notes {
            if !notes.summary.isEmpty { parts.append(clean(notes.summary)) }
            if !notes.keyPoints.isEmpty { parts.append("Ana noktalar:\n" + notes.keyPoints.map { "- " + clean($0.text) }.joined(separator: "\n")) }
            if !notes.concepts.isEmpty {
                parts.append("Kavramlar:\n" + notes.concepts.map { "- \(clean($0.name)): \(clean($0.definition))" }.joined(separator: "\n"))
            }
        }
        if parts.isEmpty {
            parts.append(transcript.paragraphs.sorted { $0.start < $1.start }.map { clean($0.text) }.joined(separator: "\n"))
        }
        return String(parts.joined(separator: "\n\n").prefix(maxChars))
    }

    /// Dersin tamamı için başlık + özet + paragraf satırları (karşılaştırma ve sınav girdisi).
    static func lessonText(_ transcript: VideoTranscript, maxChars: Int = 60_000) -> String {
        var parts: [String] = []
        // Özet bütçenin en çok dörtte birini alır; kalanı paragraflara kalır, toplam `maxChars`'ı aşmaz.
        if let summary = transcript.notes?.summary, !summary.isEmpty {
            parts.append("Özet: " + excerpt(summary, maxChars: max(0, maxChars / 4)))
        }
        let used = parts.reduce(0) { $0 + $1.count + 2 }
        parts.append(lines(transcript.paragraphs, maxChars: max(0, maxChars - used)))
        return String(parts.joined(separator: "\n\n").prefix(maxChars))
    }
}

// MARK: - Quiz doğrulama ve net

nonisolated enum StudyQuizRules {
    /// Sunucudan gelen soruyu temizler; geçersizse nil (boş metin, <2 şık, aralık dışı cevap, yinelenen şık).
    static func sanitize(_ question: StudyQuestion) -> StudyQuestion? {
        let text = StudyText.clean(question.question)
        let choices = question.choices.map(StudyText.clean)
        guard !text.isEmpty, choices.count >= 2, choices.allSatisfy({ !$0.isEmpty }),
              Set(choices.map { $0.lowercased() }).count == choices.count,
              choices.indices.contains(question.answer) else { return nil }
        var copy = question
        copy.question = text
        copy.choices = choices
        copy.explanation = StudyText.clean(question.explanation)
        if let time = question.time, !(time.isFinite && time >= 0) { copy.time = nil }
        return copy
    }

    /// Geçerli soruların ilk `limit` tanesi; aynı soru metni tekrarlanmaz.
    static func sanitize(_ questions: [StudyQuestion], limit: Int) -> [StudyQuestion] {
        var seen = Set<String>()
        var result: [StudyQuestion] = []
        for question in questions {
            guard let clean = sanitize(question), seen.insert(clean.question.lowercased()).inserted else { continue }
            result.append(clean)
            if result.count == limit { break }
        }
        return result
    }

    static func isCorrect(_ question: StudyQuestion, selected: Int?) -> Bool {
        selected == question.answer
    }

    /// Yanlış cevaplanan soruların sıraları; `includeUnanswered` açıksa cevapsızlar da (bitirilen quiz).
    /// Yarıda kapatılan quiz'de yalnız cevabı açıklanmış sorular sayılır.
    static func missed(_ questions: [StudyQuestion], answers: [Int: Int], includeUnanswered: Bool) -> [Int] {
        questions.indices.filter { index in
            guard let selected = answers[index] else { return includeUnanswered }
            return selected != questions[index].answer
        }
    }

    /// Seçenek harfi: 0 → "A".
    static func letter(_ index: Int) -> String {
        guard (0..<26).contains(index), let scalar = Unicode.Scalar(65 + index) else { return "•" }
        return String(Character(scalar))
    }
}

/// Deneme gezgini: boş sorular ve "boş soruya git".
nonisolated enum ExamNav {
    /// Cevaplanmamış soruların sıraları (artan).
    static func unanswered(count: Int, answers: [Int: Int]) -> [Int] {
        guard count > 0 else { return [] }
        return (0..<count).filter { answers[$0] == nil }
    }

    /// `current`'tan sonraki ilk boş soru; sona gelince baştan sarar (tek boş geçerli soruysa onu döndürür). Boş yoksa nil.
    static func nextUnanswered(after current: Int, count: Int, answers: [Int: Int]) -> Int? {
        let open = unanswered(count: count, answers: answers)
        return open.first { $0 > current } ?? open.first
    }
}

nonisolated struct ExamScore: Hashable, Sendable {
    var correct: Int
    var wrong: Int
    var blank: Int
    /// ÖSYM neti: doğru − yanlış / 4 (boşlar sayılmaz).
    var net: Double { ExamScore.net(correct: correct, wrong: wrong) }

    static func net(correct: Int, wrong: Int) -> Double { Double(correct) - Double(wrong) / 4 }

    static func compute(_ questions: [StudyQuestion], answers: [Int: Int]) -> ExamScore {
        var score = ExamScore(correct: 0, wrong: 0, blank: 0)
        for (index, question) in questions.enumerated() {
            guard let selected = answers[index] else { score.blank += 1; continue }
            if selected == question.answer { score.correct += 1 } else { score.wrong += 1 }
        }
        return score
    }

    /// Netin 1 ondalıkla Türkçe yazımı: "7,5".
    static func netText(_ net: Double) -> String {
        net.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "tr_TR")))
    }
}

/// Bitirilen bir denemenin sonucu (ders klasöründeki `exam_history.json`'da saklanır).
nonisolated struct ExamRecord: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var date: Date
    var questions: Int
    var correct: Int
    var wrong: Int
    var blank: Int
    var seconds: Double
    var net: Double { ExamScore.net(correct: correct, wrong: wrong) }
}

/// Deneme geçmişi: ders başına son `limit` sonuç. Dosya ders klasöründe durur; ders silinince klasörle birlikte gider.
nonisolated enum ExamHistory {
    static let limit = 50
    static let fileName = "exam_history.json"

    /// Yeni kayıt başa eklenir (en yeni başta); liste `limit` ile sınırlanır.
    static func appending(_ record: ExamRecord, to list: [ExamRecord]) -> [ExamRecord] {
        Array(([record] + list.filter { $0.id != record.id }).prefix(limit))
    }

    /// Öncekine göre fark: soru sayıları eşitse net farkı; değilse net/soru yüzdesinin puan farkı. Önceki yoksa nil.
    static func delta(latest: ExamRecord, previous: ExamRecord?) -> Double? {
        guard let previous else { return nil }
        if latest.questions == previous.questions { return latest.net - previous.net }
        func percent(_ record: ExamRecord) -> Double { record.questions > 0 ? record.net / Double(record.questions) * 100 : 0 }
        return (percent(latest) - percent(previous)).rounded()
    }

    /// "+1,75 net" / "−0,5 net" / "aynı net"; soru sayısı farklıysa "net oranı +8 puan". Önceki yoksa nil.
    static func deltaText(latest: ExamRecord, previous: ExamRecord?) -> String? {
        guard let previous, let change = delta(latest: latest, previous: previous) else { return nil }
        let same = latest.questions == previous.questions
        guard abs(change) >= 0.005 else { return same ? "aynı net" : "aynı net oranı" }
        let amount = (change > 0 ? "+" : "−") + ExamScore.netText(abs(change))
        return same ? "\(amount) net" : "net oranı \(amount) puan"
    }

    /// "Net 9,5 · 15 soru".
    static func title(_ record: ExamRecord) -> String {
        "Net \(ExamScore.netText(record.net)) · \(record.questions) soru"
    }

    /// "12 D · 3 Y · 0 B".
    static func detail(_ record: ExamRecord) -> String {
        "\(record.correct) D · \(record.wrong) Y · \(record.blank) B"
    }

    static func decode(_ data: Data) -> [ExamRecord] {
        (try? JSONDecoder().decode([ExamRecord].self, from: data)) ?? []
    }

    /// Yan etkisiz yol (klasör oluşturmaz).
    static func fileURL(lesson id: UUID) -> URL {
        URL.applicationSupportDirectory.appending(path: "Videos", directoryHint: .isDirectory)
            .appending(path: id.uuidString, directoryHint: .isDirectory)
            .appending(path: fileName)
    }

    static func load(lesson id: UUID) -> [ExamRecord] {
        (try? Data(contentsOf: fileURL(lesson: id))).map(decode) ?? []
    }

    static func save(_ list: [ExamRecord], lesson id: UUID) {
        _ = VideoFiles.directory(for: id)
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: fileURL(lesson: id), options: .atomic)
    }
}

nonisolated struct WeakTopic: Hashable, Sendable {
    var title: String
    var wrong: Int
    var total: Int
    /// Konunun anlatıldığı yer (sn); videoda "izle" için.
    var time: Double
}

nonisolated enum ExamAnalysis {
    /// Yanlış (boş dahil) yapılan soruları bölüme göre toplar; en çok yanlış olandan başlar.
    /// Bölümü olmayan videoda tek "Genel" konu.
    static func weakTopics(_ questions: [StudyQuestion], answers: [Int: Int], chapters: [VideoChapter]) -> [WeakTopic] {
        let sorted = chapters.sorted { $0.start < $1.start }
        var buckets: [Int: (wrong: Int, total: Int, time: Double)] = [:]
        for (index, question) in questions.enumerated() {
            let key = question.time.flatMap { StudyText.chapterIndex(sorted, at: $0) } ?? -1
            var bucket = buckets[key] ?? (0, 0, question.time ?? sorted[safeIndex: key]?.start ?? 0)
            bucket.total += 1
            if answers[index] != question.answer {
                if bucket.wrong == 0 { bucket.time = question.time ?? bucket.time }
                bucket.wrong += 1
            }
            buckets[key] = bucket
        }
        return buckets
            .filter { $0.value.wrong > 0 }
            .map { key, value in
                WeakTopic(title: sorted[safeIndex: key]?.title ?? "Genel", wrong: value.wrong, total: value.total, time: value.time)
            }
            .sorted { $0.wrong != $1.wrong ? $0.wrong > $1.wrong : $0.time < $1.time }
    }
}

private nonisolated extension Array {
    subscript(safeIndex index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - Quiz kapsamı (#18)

nonisolated enum QuizScope {
    /// Bölüm sırası verildiyse o bölüm; yoksa (bölümsüz video) şu ana kadarki son 10 dk, ders başındaysa ilk 10 dk.
    static func resolve(chapters: [VideoChapter], chapter: Int?, end: Double, currentTime: Double) -> (title: String, range: ClipRange) {
        let sorted = chapters.sorted { $0.start < $1.start }
        if let chapter, let range = StudyText.chapterRange(sorted, index: chapter, end: end) {
            return (sorted[chapter].title, range)
        }
        if currentTime > 60 {
            return ("Son dakikalar", ClipRange(start: max(0, currentTime - 600), end: currentTime))
        }
        return ("Dersin başı", ClipRange(start: 0, end: end > 0 ? min(end, 600) : 600))
    }
}

// MARK: - Kesit planlama (#20, #21, #31)

nonisolated enum ClipPlanner {
    /// Önemli anların çevresindeki paragraf kesitleri: anın paragrafı, `minLength`'ten kısaysa sonraki paragraflarla
    /// uzatılır (toplam `maxLength`'i aşmayacak şekilde; tek paragraf asla kesilmez). Yakın/örtüşen kesitler birleşir.
    /// Toplam süre `maxTotal`'ı aşınca kesitler derse yayılarak seçilir (`spread`); dersin sonu özet dışında kalmaz.
    static func plan(times: [Double], paragraphs: [TranscriptParagraph], minLength: Double = 12, maxLength: Double = 60,
                     mergeGap: Double = 1.5, maxTotal: Double = 1500) -> [ClipRange] {
        let sorted = paragraphs.sorted { $0.start < $1.start }.filter { $0.end > $0.start }
        guard !sorted.isEmpty else { return [] }
        let starts = sorted.map(\.start)
        var raw: [ClipRange] = []
        for time in Set(times.filter { $0.isFinite && $0 >= 0 }).sorted() {
            var i = TranscriptFormat.index(at: time, starts: starts) ?? 0
            // Paragraf anın hemen öncesinde bitmişse (boşluk) sonraki paragrafa geç.
            if sorted[i].end < time - 1, sorted.indices.contains(i + 1) { i += 1 }
            let start = sorted[i].start
            var end = sorted[i].end
            var j = i
            while end - start < minLength, sorted.indices.contains(j + 1), sorted[j + 1].end - start <= maxLength {
                j += 1
                end = sorted[j].end
            }
            raw.append(ClipRange(start: start, end: end))
        }
        // Bütçeye sığmayan birleşik kesit atlanır; hiçbiri sığmazsa birleştirilmemiş kesitlerle denenir.
        let merged = spread(merge(raw, gap: mergeGap), maxTotal: maxTotal)
        return merged.isEmpty ? spread(raw.sorted { $0.start < $1.start }, maxTotal: maxTotal) : merged
    }

    /// Zaman sırasındaki kesitlerden bütçeye sığanları baştan alır (sığmayan atlanır).
    static func fit(_ clips: [ClipRange], maxTotal: Double) -> [ClipRange] {
        var total = 0.0
        var result: [ClipRange] = []
        for clip in clips where total + clip.duration <= maxTotal {
            total += clip.duration
            result.append(clip)
        }
        return result
    }

    /// Toplamı `maxTotal`'ı aşan (zaman sırasındaki) kesitlerden derse eşit aralıklarla yayılmış bir alt küme seçer;
    /// baştan doldurmak dersin sonundaki konuları özetin dışında bırakırdı. Sığıyorsa girdi aynen döner.
    /// Artan bütçe, seçilmeyen kesitlerden sığanlarla doldurulur; hiçbir seçim sığmazsa `fit` sonucuna düşülür.
    static func spread(_ clips: [ClipRange], maxTotal: Double) -> [ClipRange] {
        let total = clips.reduce(0) { $0 + $1.duration }
        guard total.isFinite, maxTotal.isFinite else { return fit(clips, maxTotal: maxTotal) }
        guard total > maxTotal, !clips.isEmpty else { return clips }
        let n = clips.count
        var keep = max(1, min(n, Int(Double(n) * max(0, maxTotal) / total)))
        while keep >= 1 {
            var picked = Set((0..<keep).map { min(n - 1, Int((Double($0) + 0.5) * Double(n) / Double(keep))) })
            var used = picked.reduce(0.0) { $0 + clips[$1].duration }
            if used <= maxTotal {
                for index in clips.indices where !picked.contains(index) && used + clips[index].duration <= maxTotal {
                    used += clips[index].duration
                    picked.insert(index)
                }
                return picked.sorted().map { clips[$0] }
            }
            keep -= 1
        }
        return fit(clips, maxTotal: maxTotal)
    }

    /// Başlangıca göre sıralı kesitleri, aralarındaki boşluk ≤ `gap` olanları birleştirerek döndürür.
    static func merge(_ ranges: [ClipRange], gap: Double) -> [ClipRange] {
        var result: [ClipRange] = []
        for range in ranges.sorted(by: { $0.start < $1.start }) {
            if var last = result.last, range.start <= last.end + gap {
                last.end = max(last.end, range.end)
                result[result.count - 1] = last
            } else {
                result.append(range)
            }
        }
        return result
    }

    /// Sesli kart kesiti: `time` anının paragrafı (anın içinde başladığı yerden paragraf sonuna); en fazla `maxLength` sn.
    /// Paragraf bulunamazsa `time`'dan `fallback` sn.
    static func cardClip(at time: Double, paragraphs: [TranscriptParagraph], maxLength: Double = 45, fallback: Double = 20) -> ClipRange {
        let t = time.isFinite ? max(0, time) : 0
        let sorted = paragraphs.sorted { $0.start < $1.start }
        let starts = sorted.map(\.start)
        guard let i = TranscriptFormat.index(at: t, starts: starts), sorted[i].end > t else {
            return ClipRange(start: t, end: t + fallback)
        }
        return ClipRange(start: sorted[i].start, end: min(sorted[i].end, sorted[i].start + maxLength))
    }

    /// Kesitin içine düşen paragraflar (başlangıcı kesit içinde olanlar).
    static func paragraphs(in range: ClipRange, from paragraphs: [TranscriptParagraph]) -> [TranscriptParagraph] {
        paragraphs.sorted { $0.start < $1.start }.filter { $0.start >= range.start - 0.01 && $0.start < range.end - 0.01 }
    }

}

// MARK: - Öğretmenin sesinden özet (#20)

nonisolated enum TeacherSummaryPlan {
    /// Kesitler arasındaki sessizlik (sn).
    static let gap = 0.35

    /// Birleştirilen sesin zaman çizelgesi ve senaryosu: her kesit bir sahne; kesitin paragrafları tur olur.
    /// Kesitler dersin bölümlerine göre gruplanır (bölüm yoksa tek grup).
    static func build(clips: [ClipRange], paragraphs: [TranscriptParagraph], chapters: [VideoChapter],
                      fallbackTitle: String) -> (chapters: [ScriptChapter], timeline: Timeline) {
        let sortedChapters = chapters.sorted { $0.start < $1.start }
        var scriptChapters: [ScriptChapter] = []
        var timedChapters: [TimedChapter] = []
        var turns: [TimedTurn] = []
        var cursor = 0.0
        var lastGroup: Int?
        for clip in clips.sorted(by: { $0.start < $1.start }) {
            let texts = ClipPlanner.paragraphs(in: clip, from: paragraphs).map { (paragraph: $0, text: StudyText.clean($0.text)) }
                .filter { !$0.text.isEmpty }
            guard !texts.isEmpty else { continue }
            let group = sortedChapters.isEmpty ? 0 : (StudyText.chapterIndex(sortedChapters, at: clip.start) ?? 0)
            if group != lastGroup {
                let title = sortedChapters.isEmpty ? fallbackTitle : sortedChapters[group].title
                scriptChapters.append(ScriptChapter(title: title, scenes: []))
                timedChapters.append(TimedChapter(id: timedChapters.count, title: title, start: cursor))
                lastGroup = group
            }
            let chapterIndex = scriptChapters.count - 1
            var sceneTurns: [ScriptTurn] = []
            for item in texts {
                sceneTurns.append(ScriptTurn(speaker: .a, text: item.text, style: "", sourcePage: nil))
                let start = cursor + max(0, item.paragraph.start - clip.start)
                let end = cursor + min(clip.duration, max(item.paragraph.end - clip.start, item.paragraph.start - clip.start + 0.5))
                turns.append(TimedTurn(id: turns.count, chapterIndex: chapterIndex, speaker: .a, text: item.text, sourcePage: nil,
                                       start: start, end: end))
            }
            scriptChapters[chapterIndex].scenes.append(ScriptScene(turns: sceneTurns))
            cursor += clip.duration + gap
        }
        let duration = max(0, cursor - (turns.isEmpty ? 0 : gap))
        return (scriptChapters, Timeline(chapters: timedChapters, turns: turns, duration: duration))
    }

    /// Metni olmayan kesitleri eler (sesle çizelge aynı kesitlerden oluşsun).
    static func usable(_ clips: [ClipRange], paragraphs: [TranscriptParagraph]) -> [ClipRange] {
        clips.filter { clip in
            ClipPlanner.paragraphs(in: clip, from: paragraphs).contains { !StudyText.clean($0.text).isEmpty }
        }
    }

    /// Kesitlerin birleşik sesteki başlangıçları (kesit sırasıyla).
    static func offsets(_ clips: [ClipRange]) -> [Double] {
        var cursor = 0.0
        return clips.map { clip in
            defer { cursor += clip.duration + gap }
            return cursor
        }
    }

    static func totalDuration(_ clips: [ClipRange]) -> Double {
        clips.reduce(0) { $0 + $1.duration } + gap * Double(max(0, clips.count - 1))
    }
}

// MARK: - Zamanlı not girdisi (#22)

nonisolated enum TimedNoteInput {
    /// Zaman alanındaki metni saniyeye çevirir ("12:34", "1.30", "90"); anlaşılmıyorsa nil.
    /// `duration` biliniyorsa (> 0) değer dersin süresine kırpılır.
    static func time(from text: String, duration: Double) -> Double? {
        guard let value = VideoTime.parse(text) else { return nil }
        return duration.isFinite && duration > 0 ? min(value, duration) : value
    }
}

// MARK: - Notlardan kart taslakları (#21, #24)

nonisolated struct TimedCardDraft: Hashable, Sendable {
    enum Kind: Sendable { case concept, question, formula }
    var kind: Kind
    var front: String
    var back: String
    /// Kartın dayandığı an (sn); sesli kart kesiti buradan çıkar.
    var time: Double?
}

nonisolated enum NoteCardPlan {
    /// Kavram ("<ad> nedir?"), soru ve (isteğe bağlı) formül kartları; mevcut ön yüzlerle ve kendi içinde yinelenmez.
    static func drafts(_ notes: LectureNotes, existingFronts: Set<String>, concepts: Bool = true, questions: Bool = true,
                       formulas: Bool = false) -> [TimedCardDraft] {
        var seen = Set(existingFronts.map(TranscriptFormat.normalizedKey))
        var result: [TimedCardDraft] = []
        func add(_ kind: TimedCardDraft.Kind, _ front: String, _ back: String, _ time: Double) {
            let f = front.trimmingCharacters(in: .whitespacesAndNewlines)
            let b = back.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !f.isEmpty, !b.isEmpty, seen.insert(TranscriptFormat.normalizedKey(f)).inserted else { return }
            result.append(TimedCardDraft(kind: kind, front: f, back: b, time: time.isFinite ? time : nil))
        }
        if concepts {
            for concept in notes.concepts {
                let name = concept.name.trimmingCharacters(in: .whitespacesAndNewlines)
                add(.concept, name.hasSuffix("?") ? name : "\(name) nedir?", concept.definition, concept.time)
            }
        }
        if questions {
            for question in notes.questions { add(.question, question.question, question.answer, question.time) }
        }
        if formulas {
            for formula in notes.formulas {
                let name = formula.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let back = [formula.expression, formula.meaning].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }.joined(separator: "\n")
                add(.formula, "\(name) formülü nedir?", back, formula.time)
            }
        }
        return result
    }
}

// MARK: - Kart dışa aktarma (#37)

nonisolated struct CardExportRow: Hashable, Sendable {
    var front: String
    var back: String
    var tag: String
}

nonisolated enum CardExport {
    /// Anki "metin dosyasından içe aktar": sekmeyle ayrılmış, HTML açık. Satır sonu <br>, `<`, `>`, `&` kaçışlı.
    static func anki(_ rows: [CardExportRow]) -> String {
        var text = "#separator:tab\n#html:true\n#tags column:3\n"
        for row in rows {
            text += "\(ankiField(row.front))\t\(ankiField(row.back))\t\(ankiTag(row.tag))\n"
        }
        return text
    }

    static func ankiField(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    /// Anki etiketi boşluk içeremez: boşluklar "_" olur.
    static func ankiTag(_ tag: String) -> String {
        let words = tag.split(whereSeparator: \.isWhitespace)
        return String(words.joined(separator: "_").prefix(80))
    }

    /// RFC 4180: alan virgül, çift tırnak ya da satır sonu içeriyorsa tırnaklanır; tırnaklar ikilenir.
    static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Excel Türkçe karakterleri doğru açsın diye UTF-8 BOM ile başlar; satırlar CRLF.
    static func csv(_ rows: [CardExportRow]) -> String {
        let header = ["Ön yüz", "Arka yüz", "Etiket"].map(csvField).joined(separator: ",")
        let body = rows.map { [$0.front, $0.back, $0.tag].map(csvField).joined(separator: ",") }
        return "\u{FEFF}" + ([header] + body).joined(separator: "\r\n") + "\r\n"
    }
}

// MARK: - Çalışma kâğıdı (#28)

nonisolated enum WorksheetLayout {
    static let blank = "________"

    /// Cümledeki cevabı boşlukla değiştirir. Sunucu cümleyi zaten boşluklu verdiyse ("___" ya da "…") dokunmaz;
    /// cevap cümlede yoksa sona boşluk eklenir.
    static func blanked(sentence: String, answer: String) -> String {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains("___") || text.contains("……") { return text }
        let target = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !target.isEmpty, let range = TranscriptFormat.matchRanges(of: target, in: text).first {
            return text.replacingCharacters(in: range, with: blank)
        }
        return text + " " + blank
    }

    /// Eşleştirme cevap anahtarı: her terim (sırayla) için karıştırılmış sütundaki harfi. `order[i]` = i. konumda
    /// gösterilen tanımın özgün sırası.
    static func matchingKey(order: [Int]) -> [String] {
        order.indices.map { term in
            guard let position = order.firstIndex(of: term) else { return "?" }
            return StudyQuizRules.letter(position)
        }
    }

    /// Metinden kararlı (süreçler arası aynı) tohum: FNV-1a.
    static func seed(for text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return hash
    }

    /// 0..<count'un belirli tohumla karıştırılmış sırası (eşleştirme sütunu için); aynı tohum aynı sırayı verir.
    /// Mümkünse hiçbir öğe kendi yerinde kalmaz (cevap görünür olmasın).
    static func shuffledOrder(count: Int, seed: UInt64) -> [Int] {
        guard count > 1 else { return Array(0..<max(0, count)) }
        var generator = SeededGenerator(seed: seed)
        var order = Array(0..<count)
        for _ in 0..<8 {
            order.shuffle(using: &generator)
            if !order.indices.contains(where: { order[$0] == $0 }) { return order }
        }
        // Rastgele denemeler tutmadıysa dairesel kaydırma: hiçbir öğe yerinde kalmaz.
        return (0..<count).map { ($0 + 1) % count }
    }
}

/// Tekrarlanabilir rastgelelik (SplitMix64).
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Slayt planı (#34)

nonisolated struct SlideSpec: Hashable, Sendable {
    enum Kind: Sendable { case cover, content, concepts }
    var kind: Kind
    var title: String
    var timeLabel: String?
    var body: String
    var bullets: [String]
    var frameID: String?
}

nonisolated enum SlidePlan {
    static let maxSlides = 80

    /// Kapak + (kare başına ya da bölüm başına) içerik slaytları + kavram slaytları.
    /// Kare varsa her kare, sonraki kareye kadar olan konuşmayı özetler; yoksa bölümler (o da yoksa 5 dk'lık bloklar).
    static func build(title: String, transcript: VideoTranscript) -> [SlideSpec] {
        var slides = [SlideSpec(kind: .cover, title: title.isEmpty ? "Video dersi" : title, timeLabel: nil,
                                body: StudyText.excerpt(transcript.notes?.summary ?? "", maxChars: 600), bullets: [], frameID: nil)]
        let paragraphs = transcript.paragraphs.sorted { $0.start < $1.start }
        let chapters = transcript.chapters.sorted { $0.start < $1.start }
        let end = TranscriptFormat.chaptersEnd(videoDuration: transcript.video.duration, transcript: transcript)
        let points = transcript.notes?.keyPoints ?? []

        struct Span { var start: Double; var end: Double; var title: String; var frameID: String? }
        var spans: [Span] = []
        let frames = transcript.keyframes.sorted { $0.time < $1.time }
        if !frames.isEmpty {
            for (i, frame) in frames.enumerated() {
                let stop = i + 1 < frames.count ? frames[i + 1].time : max(end, frame.time + 1)
                let caption = StudyText.clean(frame.caption)
                let fallback = StudyText.chapterIndex(chapters, at: frame.time).map { chapters[$0].title } ?? "Kare \(i + 1)"
                spans.append(Span(start: frame.time, end: stop, title: caption.isEmpty ? fallback : caption, frameID: frame.id))
            }
        } else if !chapters.isEmpty {
            for index in chapters.indices {
                guard let range = StudyText.chapterRange(chapters, index: index, end: end) else { continue }
                spans.append(Span(start: range.start, end: range.end, title: chapters[index].title, frameID: nil))
            }
        } else if let first = paragraphs.first {
            var cursor = first.start
            var n = 1
            while cursor < end {
                spans.append(Span(start: cursor, end: min(cursor + 300, end), title: "Bölüm \(n)", frameID: nil))
                cursor += 300
                n += 1
            }
        }
        // Kapak ve kavram slaytları dahil toplam `maxSlides`'ı aşmasın.
        let concepts = transcript.notes?.concepts ?? []
        let conceptSlides = min(4, (concepts.count + 5) / 6)
        let contentLimit = max(1, maxSlides - 1 - conceptSlides)
        if spans.count > contentLimit {
            let step = Double(spans.count) / Double(contentLimit)
            spans = (0..<contentLimit).map { spans[Int(Double($0) * step)] }
        }
        for span in spans {
            let text = paragraphs.filter { $0.start >= span.start - 0.01 && $0.start < span.end }.map(\.text).joined(separator: " ")
            let bullets = points.filter { $0.time >= span.start - 0.01 && $0.time < span.end }.prefix(4)
                .map { StudyText.excerpt($0.text, maxChars: 160) }
            slides.append(SlideSpec(kind: .content, title: span.title, timeLabel: TranscriptFormat.timestamp(span.start),
                                    body: StudyText.excerpt(text, maxChars: 360), bullets: Array(bullets), frameID: span.frameID))
        }
        for start in stride(from: 0, to: min(concepts.count, conceptSlides * 6), by: 6) {
            let chunk = concepts[start..<min(start + 6, concepts.count)]
            slides.append(SlideSpec(kind: .concepts, title: "Kavramlar", timeLabel: nil, body: "",
                                    bullets: chunk.map { "\($0.name): \(StudyText.excerpt($0.definition, maxChars: 150))" }, frameID: nil))
        }
        return slides
    }
}

// MARK: - Türkçe dublaj (#35)

nonisolated enum DubbingPlan {
    /// Sunucunun sahne sınırları: sahne ≤ 24 tur, toplam ≤ 1500 karakter; en çok 1000 sahne, 100 bölüm.
    static let maxSceneChars = 1100
    static let maxTurnChars = 900
    static let maxScenes = 900
    static let charsPerSecond = 14.0

    /// Hazır metinden tek anlatıcılı senaryo. Paragraflar bölümlere dağıtılır, sahneler ≤ `maxSceneChars`.
    /// Metin yoksa ya da sahne sınırı aşılırsa nil.
    static func script(title: String, paragraphs: [TranscriptParagraph], chapters: [VideoChapter], summary: String = "",
                       range: ClipRange? = nil, style: String = "sakin ve anlaşılır ders anlatımı") -> PodcastScript? {
        var items = paragraphs.sorted { $0.start < $1.start }
            .filter { !StudyText.clean($0.text).isEmpty }
        if let range { items = items.filter { $0.start >= range.start - 0.01 && $0.start < range.end } }
        guard !items.isEmpty else { return nil }

        var sortedChapters = chapters.sorted { $0.start < $1.start }
        if sortedChapters.count > 100 || sortedChapters.isEmpty { sortedChapters = [] }

        var groups: [(title: String, paragraphs: [TranscriptParagraph])] = []
        if sortedChapters.isEmpty {
            groups = [(title, items)]
        } else {
            for paragraph in items {
                let chapter = StudyText.chapterIndex(sortedChapters, at: paragraph.start) ?? 0
                let name = sortedChapters[chapter].title
                if groups.last?.title == name {
                    groups[groups.count - 1].paragraphs.append(paragraph)
                } else {
                    groups.append((name, [paragraph]))
                }
            }
        }

        var scriptChapters: [ScriptChapter] = []
        var sceneCount = 0
        for group in groups {
            var scenes: [ScriptScene] = []
            var turns: [ScriptTurn] = []
            var chars = 0
            func flush() {
                guard !turns.isEmpty else { return }
                scenes.append(ScriptScene(turns: turns))
                turns = []
                chars = 0
            }
            for paragraph in group.paragraphs {
                for piece in TranscriptFormat.chunks(StudyText.clean(paragraph.text), maxLength: maxTurnChars, maxLines: 30) {
                    if chars + piece.count > maxSceneChars || turns.count >= 24 { flush() }
                    turns.append(ScriptTurn(speaker: .a, text: piece, style: style, sourcePage: nil))
                    chars += piece.count
                }
            }
            flush()
            sceneCount += scenes.count
            if !scenes.isEmpty { scriptChapters.append(ScriptChapter(title: group.title, scenes: scenes)) }
        }
        guard sceneCount > 0, sceneCount <= maxScenes else { return nil }
        // sourceNotes bilerek boş: boş notla otomatik "senaryoyu belgeyle doğrula" çağrısı atlanır
        // (dublaj zaten kaynak metnin kendisidir).
        return PodcastScript(title: title, summary: summary, keyPoints: [], chapters: scriptChapters, sourceNotes: "")
    }

    /// Tahmini ses süresi (sn).
    static func estimatedSeconds(characters: Int) -> Double { Double(characters) / charsPerSecond }

    static func characters(_ paragraphs: [TranscriptParagraph], range: ClipRange? = nil) -> Int {
        paragraphs.filter { paragraph in range.map { paragraph.start >= $0.start - 0.01 && paragraph.start < $0.end } ?? true }
            .reduce(0) { $0 + StudyText.clean($1.text).count }
    }

    /// Dublaj kaynağı: Türkçe çeviri varsa o; dersin kendisi Türkçeyse özgün metin; aksi hâlde nil.
    static func source(_ transcript: VideoTranscript) -> (paragraphs: [TranscriptParagraph], translated: Bool)? {
        if let translation = transcript.translation, !translation.paragraphs.isEmpty,
           translation.language.lowercased().hasPrefix("tr") {
            return (translation.paragraphs, true)
        }
        if transcript.language.lowercased().hasPrefix("tr"), !transcript.paragraphs.isEmpty {
            return (transcript.paragraphs, false)
        }
        return nil
    }
}
