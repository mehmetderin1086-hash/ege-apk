import Foundation

/// Transkript görünümünde gösterilecek dil.
nonisolated enum TranscriptLanguage: String, CaseIterable, Identifiable, Sendable {
    case original, translated, both
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: "Orijinal"
        case .translated: "Türkçe"
        case .both: "İkisi"
        }
    }
}

/// Transkript ekranındaki bir paragraf satırı (çeviri seçimine göre birincil + isteğe bağlı ikincil metin).
nonisolated struct TranscriptRow: Identifiable, Hashable, Sendable {
    var id: Int
    var start: Double
    var end: Double
    var text: String
    var secondary: String?
    /// Paragrafın içindeki altyazı satırları: kelime takibi bu satırların zamanlarına bağlanır.
    var spans: [FollowAlong.Span] = []
    /// Satırda öğrenci konuşması olan altyazı parçası var mı.
    var hasStudent: Bool { spans.contains { $0.student } }
}

/// Ders notundan üretilecek tekrar kartı taslağı.
nonisolated struct LessonCardDraft: Hashable, Sendable {
    var front: String
    var back: String
}

/// Video dersi için saf biçimleme, konum bulma, arama ve dışa aktarma yardımcıları (test edilebilir).
nonisolated enum TranscriptFormat {
    // MARK: - Zaman

    /// Rozet biçimi: 75 → "01:15", 3725 → "1:02:05".
    static func timestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds : 0))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// SRT zaman damgası (virgüllü milisaniye): 62.5 → "00:01:02,500".
    static func srtTimestamp(_ seconds: Double) -> String {
        let ms = max(0, Int(((seconds.isFinite ? seconds : 0) * 1000).rounded()))
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
    }

    /// SubRip metni: 1'den başlayan sıra numarası, "başlangıç --> bitiş", metin, boş satır. Boş segmentler atlanır.
    static func srt(_ segments: [TranscriptSegment]) -> String {
        var blocks: [String] = []
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            let text = segment.text
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            guard !text.isEmpty else { continue }
            let end = segment.end > segment.start ? segment.end : segment.start + 1
            blocks.append("\(blocks.count + 1)\n\(srtTimestamp(segment.start)) --> \(srtTimestamp(end))\n\(text)\n")
        }
        return blocks.joined(separator: "\n")
    }

    /// "YouTube'da aç" bağlantısı: https://youtu.be/<id>?t=<sn>.
    static func shareURL(videoID: String, at seconds: Double = 0) -> URL? {
        guard YouTubeLink.isValidID(videoID) else { return nil }
        let t = Int(max(0, seconds.isFinite ? seconds : 0))
        return URL(string: "https://youtu.be/\(videoID)" + (t > 0 ? "?t=\(t)" : ""))
    }

    // MARK: - Konum (ikili arama)

    /// Artan sıralı başlangıçlarda `start <= time` olan son indeks; zaman ilk başlangıçtan önceyse ya da liste boşsa nil.
    static func index(at time: Double, starts: [Double]) -> Int? {
        guard let first = starts.first, time.isFinite, time >= first else { return nil }
        var low = 0, high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= time { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Çalan paragraf: son paragrafın bitişinden sonra (ör. kırpılmış aralık dışı) vurgu kalkar.
    static func currentParagraph(at time: Double, starts: [Double], lastEnd: Double?) -> Int? {
        guard let index = index(at: time, starts: starts) else { return nil }
        if index == starts.count - 1, let lastEnd, lastEnd > starts[index], time > lastEnd + 2 { return nil }
        return index
    }

    // MARK: - Satırlar ve çeviri hizalama

    /// Her orijinal paragraf için aynı ana ait çeviri metni (sayılar eşitse sırayla, değilse en yakın başlangıç ≤ 3 sn).
    static func alignedTranslation(original: [TranscriptParagraph], translated: [TranscriptParagraph]) -> [String?] {
        guard !translated.isEmpty else { return original.map { _ in nil } }
        if original.count == translated.count { return translated.map(\.text) }
        let sorted = translated.sorted { $0.start < $1.start }
        let starts = sorted.map(\.start)
        return original.map { paragraph in
            let i = index(at: paragraph.start, starts: starts) ?? 0
            let best = [i, i + 1].filter { starts.indices.contains($0) }
                .min { abs(starts[$0] - paragraph.start) < abs(starts[$1] - paragraph.start) } ?? i
            return abs(starts[best] - paragraph.start) <= 3 ? sorted[best].text : nil
        }
    }

    /// Seçilen dile göre ekranda gösterilecek satırlar (zaman sıralı).
    /// `students`: öğrenci konuşması olan altyazı satırlarının sırası (`orderedSegments` sıralamasında).
    static func rows(paragraphs: [TranscriptParagraph], translation: TranscriptTranslation?, language: TranscriptLanguage,
                     segments: [TranscriptSegment] = [], students: Set<Int> = []) -> [TranscriptRow] {
        let original = paragraphs.sorted { $0.start < $1.start }
        let translated = (translation?.paragraphs ?? []).sorted { $0.start < $1.start }
        let captions = CaptionIndex(segments, students: students)
        switch translated.isEmpty ? .original : language {
        case .original:
            return original.enumerated().map {
                TranscriptRow(id: $0, start: $1.start, end: $1.end, text: $1.text, spans: captions.spans(start: $1.start, end: $1.end))
            }
        case .translated:
            return translated.enumerated().map { TranscriptRow(id: $0, start: $1.start, end: $1.end, text: $1.text) }
        case .both:
            let aligned = alignedTranslation(original: original, translated: translated)
            return original.enumerated().map { i, p in
                TranscriptRow(id: i, start: p.start, end: p.end, text: p.text, secondary: aligned[i],
                              spans: captions.spans(start: p.start, end: p.end))
            }
        }
    }

    /// Altyazı satırlarının tek geçerli sıralaması (başlangıca göre): öğrenci konuşması sıra numaraları bu sıraya göredir.
    static func orderedSegments(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        segments.sorted { $0.start < $1.start }
    }

    /// Paragraf aralığına düşen (orta noktası içeride) altyazı satırları, zaman sıralı.
    /// Paragraf metni bu satırların birleşimidir: kelimeler satır satır kendi süresine dağıtılır (tüm paragrafa düz dağıtmaktan çok daha isabetli).
    /// Tek paragraf için; çok paragraf için `CaptionIndex` bir kez kurulup paylaşılır (`rows` böyle yapar).
    static func spans(start: Double, end: Double, segments: [TranscriptSegment]) -> [FollowAlong.Span] {
        CaptionIndex(segments).spans(start: start, end: end)
    }

    /// Altyazı satırlarının orta noktalarına göre sıralı dizin: her paragraf kendi penceresini ikili aramayla bulur
    /// (paragraf × satır taraması ve her satırı yeniden bölmek yok). Kelime sayısı yalnızca seçilen satırlar için hesaplanır.
    struct CaptionIndex {
        private let segments: [TranscriptSegment]
        private let order: [Int]      // segment sıraları, orta noktaya göre
        private let mids: [Double]    // `order` sırasında orta noktalar
        private let students: Set<Int>

        /// `students`: öğrenci satırlarının sırası (`orderedSegments` sıralamasında); parçalar `student` olarak işaretlenir.
        init(_ lines: [TranscriptSegment], students: Set<Int> = []) {
            let segments = TranscriptFormat.orderedSegments(lines)
            self.segments = segments
            self.students = students
            let middles = segments.map { ($0.start + $0.end) / 2 }
            let sorted = segments.indices.sorted { middles[$0] < middles[$1] }
            order = sorted
            mids = sorted.map { middles[$0] }
        }

        func spans(start: Double, end: Double) -> [FollowAlong.Span] {
            guard !segments.isEmpty, start <= end else { return [] }
            let lo = lowerBound(start), hi = upperBound(end)
            guard lo < hi else { return [] }
            // Segment dizisindeki özgün sıra (zamana göre) korunur.
            return order[lo..<hi].sorted().compactMap { i in
                let s = segments[i]
                let count = s.text.split(whereSeparator: \.isWhitespace).count
                guard count > 0 else { return nil }
                // Kelime zamanları (json3) yalnızca kelime sayısı tutuyorsa taşınır.
                return FollowAlong.Span(start: s.start, end: max(s.start, s.end), words: count,
                                        times: s.w.flatMap { $0.count == count ? $0 : nil }, student: students.contains(i))
            }
        }

        /// İlk `mids[i] >= value`.
        private func lowerBound(_ value: Double) -> Int {
            var lo = 0, hi = mids.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if mids[mid] < value { lo = mid + 1 } else { hi = mid }
            }
            return lo
        }

        /// İlk `mids[i] > value`.
        private func upperBound(_ value: Double) -> Int {
            var lo = 0, hi = mids.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if mids[mid] <= value { lo = mid + 1 } else { hi = mid }
            }
            return lo
        }
    }

    // MARK: - Arama (büyük/küçük harf, Türkçe ı/İ ve aksan duyarsız)

    private static let foldTable: [Character: Character] = [
        "ç": "c", "Ç": "c", "ğ": "g", "Ğ": "g", "ı": "i", "İ": "i", "ö": "o", "Ö": "o",
        "ş": "s", "Ş": "s", "ü": "u", "Ü": "u", "â": "a", "Â": "a", "î": "i", "Î": "i", "û": "u", "Û": "u",
    ]
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// Tek karakteri arama anahtarına indirger (karakter sayısı korunur, aralıklar asıl metne eşlenebilir).
    static func fold(_ c: Character) -> Character {
        if let ascii = c.asciiValue {
            return (65...90).contains(ascii) ? Character(UnicodeScalar(ascii + 32)) : c
        }
        if let mapped = foldTable[c] { return mapped }
        return String(c).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: posix).first ?? c
    }

    static func searchKey(_ text: String) -> [Character] { text.map(fold) }

    private static func firstOffset(of needle: [Character], in hay: [Character], from: Int = 0) -> Int? {
        guard !needle.isEmpty, hay.count >= needle.count, from <= hay.count - needle.count else { return nil }
        var i = from
        let last = hay.count - needle.count
        while i <= last {
            if hay[i] == needle[0] {
                var j = 1
                while j < needle.count && hay[i + j] == needle[j] { j += 1 }
                if j == needle.count { return i }
            }
            i += 1
        }
        return nil
    }

    static func contains(_ needle: [Character], in hay: [Character]) -> Bool {
        firstOffset(of: needle, in: hay) != nil
    }

    /// Sorgunun metindeki tüm (çakışmayan) eşleşme aralıkları.
    static func matchRanges(of query: String, in text: String) -> [Range<String.Index>] {
        let needle = searchKey(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty, !text.isEmpty else { return [] }
        let hay = searchKey(text)
        let indices = Array(text.indices)
        var ranges: [Range<String.Index>] = []
        var from = 0
        while let offset = firstOffset(of: needle, in: hay, from: from) {
            let endOffset = offset + needle.count
            ranges.append(indices[offset]..<(endOffset < indices.count ? indices[endOffset] : text.endIndex))
            from = endOffset
        }
        return ranges
    }

    /// Önceden hesaplanmış anahtarlarda sorguyu içeren satırların indeksleri.
    static func matchingIndices(of query: String, keys: [[Character]]) -> [Int] {
        let needle = searchKey(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return [] }
        return keys.indices.filter { contains(needle, in: keys[$0]) }
    }

    static func matchingIndices(of query: String, in texts: [String]) -> [Int] {
        matchingIndices(of: query, keys: texts.map(searchKey))
    }

    /// Satırın aranacak metni (birincil + ikincil).
    static func searchText(_ row: TranscriptRow) -> String {
        row.secondary.map { row.text + "\n" + $0 } ?? row.text
    }

    // MARK: - Kartlar ve notlar

    /// Paragraftan kart ön yüzü: ilk cümlenin başlangıcı (≤ maxWords sözcük) + "…?".
    static func cardFront(_ text: String, maxWords: Int = 8) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = trimmed.firstIndex { ".?!…".contains($0) } ?? trimmed.endIndex
        let words = trimmed[..<end].split(whereSeparator: \.isWhitespace).prefix(maxWords)
        let head = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ",;:-–—\"' "))
        return head.isEmpty ? "…?" : head + "…?"
    }

    /// Paragraf satırından kart: Türkçe metin varsa o kullanılır (ön yüz = cümle başlangıcı + "…?", arka yüz = paragraf).
    static func cardContent(for row: TranscriptRow) -> LessonCardDraft {
        let original = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let secondary = row.secondary?.trimmingCharacters(in: .whitespacesAndNewlines), !secondary.isEmpty else {
            return LessonCardDraft(front: cardFront(original), back: original)
        }
        return LessonCardDraft(front: cardFront(secondary), back: secondary + "\n\n(Orijinal) " + original)
    }

    /// Yinelenme kontrolü için normalleştirilmiş anahtar.
    static func normalizedKey(_ text: String) -> String {
        String(searchKey(text.split(whereSeparator: \.isWhitespace).joined(separator: " ")))
    }

    /// Kavramlar ("<ad> nedir?" → tanım) ve sorular (soru → cevap); mevcut ön yüzlerle ve kendi içinde yinelenmez.
    static func noteCards(_ notes: LectureNotes, existingFronts: Set<String>) -> [LessonCardDraft] {
        var seen = Set(existingFronts.map(normalizedKey))
        var result: [LessonCardDraft] = []
        func add(_ front: String, _ back: String) {
            let f = front.trimmingCharacters(in: .whitespacesAndNewlines)
            let b = back.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !f.isEmpty, !b.isEmpty, seen.insert(normalizedKey(f)).inserted else { return }
            result.append(LessonCardDraft(front: f, back: b))
        }
        for concept in notes.concepts {
            let name = concept.name.trimmingCharacters(in: .whitespacesAndNewlines)
            add(name.hasSuffix("?") ? name : "\(name) nedir?", concept.definition)
        }
        for question in notes.questions { add(question.question, question.answer) }
        return result
    }

    /// Cornell notuna eklenecek satır: "[mm:ss] alıntı".
    static func noteLine(time: Double, quote: String, limit: Int = 1000) -> String {
        let text = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = text.count > limit ? String(text.prefix(limit)) + "…" : text
        return "[\(timestamp(time))] \(clipped)"
    }

    // MARK: - Kareler → kaynak şekilleri

    static func figureID(_ keyframeID: String) -> String { "yt_" + VideoFiles.safeName(keyframeID) }

    /// Kareleri bölümün kaynak şekillerine çevirir (kind "figure", page 0, belge adı = video başlığı); yinelenen kimlik atlanır.
    static func sourceFigures(from keyframes: [Keyframe], title: String) -> [SourceFigure] {
        var used = Set<String>()
        return keyframes.sorted { $0.time < $1.time }.compactMap { frame in
            let id = figureID(frame.id)
            guard used.insert(id).inserted else { return nil }
            let caption = frame.caption.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = String(frame.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
            return SourceFigure(id: id, kind: "figure", caption: caption.isEmpty ? fallback : caption,
                                page: 0, documentName: title, table: nil)
        }
    }

    // MARK: - Metin dışa aktarma

    private static func sortedChapters(_ chapters: [VideoChapter]) -> [VideoChapter] {
        chapters.sorted { $0.start < $1.start }
    }

    /// Paragrafları bölüm başlıklarıyla birlikte satırlara dizer.
    private static func paragraphLines(_ paragraphs: [TranscriptParagraph], chapters: [VideoChapter],
                                       heading: (VideoChapter) -> String, line: (TranscriptParagraph) -> String) -> [String] {
        let chapters = sortedChapters(chapters)
        var lines: [String] = []
        var next = 0
        for paragraph in paragraphs.sorted(by: { $0.start < $1.start }) {
            while next < chapters.count, chapters[next].start <= paragraph.start + 0.5 {
                lines.append(heading(chapters[next]))
                next += 1
            }
            lines.append(line(paragraph))
        }
        return lines
    }

    /// Zaman damgalı düz metin (.txt).
    static func plainText(title: String, channel: String, url: String, paragraphs: [TranscriptParagraph], chapters: [VideoChapter]) -> String {
        var header = [title]
        let meta = [channel, url].filter { !$0.isEmpty }.joined(separator: " · ")
        if !meta.isEmpty { header.append(meta) }
        let body = paragraphLines(paragraphs, chapters: chapters,
                                  heading: { "\n== \($0.title) [\(timestamp($0.start))] ==" },
                                  line: { "[\(timestamp($0.start))] \($0.text)" })
        return (header + [""] + body).joined(separator: "\n") + "\n"
    }

    private static func link(_ videoID: String, _ time: Double) -> String {
        guard let url = shareURL(videoID: videoID, at: time) else { return timestamp(time) }
        return "[\(timestamp(time))](\(url.absoluteString))"
    }

    /// Markdown ders notu: özet, bölümler, ana noktalar, kavramlar, formüller, sorular, ipuçları, kareler.
    /// Ders notu yoksa transkript eklenir.
    static func markdown(title: String, channel: String, transcript: VideoTranscript) -> String {
        let id = transcript.video.id
        var out: [String] = ["# \(title)", ""]
        var meta: [String] = []
        if !channel.isEmpty { meta.append(channel) }
        if transcript.video.duration > 0 { meta.append(timestamp(transcript.video.duration)) }
        if let url = shareURL(videoID: id) { meta.append(url.absoluteString) }
        if !meta.isEmpty { out += [meta.joined(separator: " · "), ""] }

        if let notes = transcript.notes {
            if !notes.summary.isEmpty { out += ["## Özet", "", notes.summary, ""] }
            let chapters = sortedChapters(transcript.chapters)
            if !chapters.isEmpty {
                out += ["## Bölümler", ""] + chapters.map { "- \(link(id, $0.start)) \($0.title)" } + [""]
            }
            if !notes.keyPoints.isEmpty {
                out += ["## Ana noktalar", ""] + notes.keyPoints.map { "- \($0.text) (\(link(id, $0.time)))" } + [""]
            }
            if !notes.concepts.isEmpty {
                out += ["## Kavramlar", ""] + notes.concepts.map { "- **\($0.name)**: \($0.definition) (\(link(id, $0.time)))" } + [""]
            }
            if !notes.formulas.isEmpty {
                out += ["## Formüller", ""] + notes.formulas.map {
                    "- **\($0.name)**: `\($0.expression)`" + ($0.meaning.isEmpty ? "" : " — \($0.meaning)") + " (\(link(id, $0.time)))"
                } + [""]
            }
            if !notes.questions.isEmpty {
                out += ["## Sorular", ""]
                for (i, q) in notes.questions.enumerated() {
                    out += ["\(i + 1). **\(q.question)** (\(link(id, q.time)))", "   Cevap: \(q.answer)"]
                }
                out.append("")
            }
            if !notes.examTips.isEmpty {
                out += ["## Sınav ipuçları", ""] + notes.examTips.map { "- \($0)" } + [""]
            }
        } else if !transcript.chapters.isEmpty {
            out += ["## Bölümler", ""] + sortedChapters(transcript.chapters).map { "- \(link(id, $0.start)) \($0.title)" } + [""]
        }

        let frames = transcript.keyframes.sorted { $0.time < $1.time }
        if !frames.isEmpty {
            out += ["## Tahta ve slayt kareleri", ""]
            for frame in frames {
                out.append("- \(link(id, frame.time)) \(frame.caption)")
                let text = frame.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { out.append("  > " + text.replacingOccurrences(of: "\n", with: "\n  > ")) }
            }
            out.append("")
        }

        if transcript.notes == nil, !transcript.paragraphs.isEmpty {
            out += ["## Transkript", ""]
            out += paragraphLines(transcript.paragraphs, chapters: transcript.chapters,
                                  heading: { "\n### \($0.title)\n" },
                                  line: { "\(link(id, $0.start)) \($0.text)\n" })
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// Podcast kaynağı: başlık + özet + bölüm başlıkları + paragraflar (çeviri varsa Türkçe).
    static func podcastSource(title: String, channel: String, transcript: VideoTranscript) -> String {
        var parts: [String] = ["Başlık: \(title)"]
        parts.append("Kaynak: YouTube ders videosu" + (channel.isEmpty ? "" : " (\(channel))"))
        if let summary = transcript.notes?.summary, !summary.isEmpty { parts.append("Özet:\n\(summary)") }
        let chapters = sortedChapters(transcript.chapters)
        if !chapters.isEmpty { parts.append("Bölümler:\n" + chapters.map { "- \($0.title)" }.joined(separator: "\n")) }
        let translated = transcript.translation?.paragraphs ?? []
        let paragraphs = translated.isEmpty ? transcript.paragraphs : translated
        let body = paragraphLines(paragraphs, chapters: chapters, heading: { "\n## \($0.title)" }, line: \.text)
        parts.append("Ders anlatımı:\n" + body.joined(separator: "\n"))
        return parts.joined(separator: "\n\n")
    }

    /// Dosya adına güvenli başlık.
    static func fileName(_ title: String, suffix: String = "", ext: String) -> String {
        let safe = String(title.map { "/\\:?%*|\"<>\n\r\t".contains($0) ? "-" : $0 }.prefix(60))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (safe.isEmpty ? "Video dersi" : safe) + suffix
        return "\(base).\(ext)"
    }

    /// PDF'de sayfa taşmasın diye uzun metni cümle sonlarından parçalara böler.
    /// Satır sınırı da uygulanır: kısa satırlardan oluşan metin de tek parçada sayfadan taşmasın.
    static func chunks(_ text: String, maxLength: Int = 1400, maxLines: Int = 30) -> [String] {
        var result: [String] = []
        var current = ""
        var lines = 0
        for sentence in splitSentences(text) {
            let breaks = sentence.hasSuffix("\n") ? 1 : 0
            if !current.isEmpty, current.count + sentence.count > maxLength || lines + breaks > maxLines {
                result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
                lines = 0
            }
            lines += breaks
            if sentence.count > maxLength {
                var rest = Substring(sentence)
                while rest.count > maxLength {
                    result.append(String(rest.prefix(maxLength)))
                    rest = rest.dropFirst(maxLength)
                }
                current = String(rest)
            } else {
                current += sentence
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.filter { !$0.isEmpty }
    }

    private static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for c in text {
            current.append(c)
            if c == "." || c == "?" || c == "!" || c == "\n" {
                sentences.append(current)
                current = ""
            }
        }
        if !current.isEmpty { sentences.append(current) }
        return sentences
    }
}

// MARK: - İşlenen aralık ve eksik notlar (saf, test edilir)

nonisolated extension TranscriptFormat {
    /// İşlenen kısmın başı ve sonu: paragraflardan (yoksa segmentlerden). Aralıkla işlenen derslerde
    /// videonun başı/sonu değildir.
    static func contentBounds(_ transcript: VideoTranscript) -> (start: Double, end: Double)? {
        let spans = transcript.paragraphs.isEmpty
            ? transcript.segments.map { (start: $0.start, end: $0.end) }
            : transcript.paragraphs.map { (start: $0.start, end: $0.end) }
        guard let start = spans.map(\.start).min(), let end = spans.map(\.end).max(), end >= start else { return nil }
        return (start, end)
    }

    /// Ders açılırken oynatıcının gideceği yer: ders hiç izlenmemişse ve transkript videonun başından değil
    /// ileriden başlıyorsa (ör. 1:00:00–1:30:00 aralığıyla işlenmiş ders) ilk paragrafın başı; aksi hâlde nil.
    static func initialSeek(lastPosition: Double, transcript: VideoTranscript) -> Double? {
        guard lastPosition < 1, let bounds = contentBounds(transcript), bounds.start > 5 else { return nil }
        return bounds.start
    }

    /// Bölümler sekmesinde son bölümün bitişi: işlenen kısmın sonu (video süresini aşmadan); transkript yoksa video süresi.
    static func chaptersEnd(videoDuration: Double, transcript: VideoTranscript) -> Double {
        guard let end = contentBounds(transcript)?.end, end > 0 else { return videoDuration }
        return videoDuration > 0 ? min(videoDuration, end) : end
    }

    /// Notlar sekmesi boşken gösterilecek açıklama. Sunucu not adımı başarısız olunca
    /// "Ders notu hazırlanamadı (…)" uyarısı ekler; o varsa gerçek neden gösterilir.
    static func missingNotesMessage(warnings: [String]) -> (title: String, detail: String) {
        if let warning = warnings.first(where: { $0.hasPrefix("Ders notu") }) {
            return ("Ders notu hazırlanamadı", "\(warning) Videoyu yeniden işleyerek tekrar deneyebilirsin.")
        }
        return ("Ders notu yok",
                "Bu ders için not yok: “Ders notu” seçeneği kapalıydı ya da not hazırlanamadı. Videoyu yeniden işleyerek not hazırlatabilirsin.")
    }
}
