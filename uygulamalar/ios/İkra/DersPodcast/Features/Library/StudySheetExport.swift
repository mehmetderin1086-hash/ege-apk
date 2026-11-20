import Foundation
import SwiftData
import UIKit

/// #45: notlarla birlikte çalışma föyü (tek bölüm ya da serinin tamamı tek kitapçık).
nonisolated struct StudySheetInput: Sendable {
    struct Mark: Sendable { var time: Double; var text: String; var note: String; var kind: String }
    struct Cornell: Sendable { var title: String; var cues: String; var notes: String; var summary: String }

    var id: UUID
    var title: String
    var script: PodcastScript?
    var settings: PodcastSettings?
    var timeline: Timeline?
    var study: StudyPack?
    var concepts: [Concept] = []
    var slides: [LessonSlide] = []
    var bookmarks: [Mark] = []
    var cornell: [Cornell] = []
}

enum StudySheetExport {
    /// Bölümden föy girdisi (yer imleri ve Cornell notları bölümün bağlamından okunur).
    static func input(for episode: Episode) -> StudySheetInput {
        var input = StudySheetInput(id: episode.id, title: episode.title, script: episode.script, settings: episode.settings,
                                    timeline: episode.timeline, study: episode.study, concepts: episode.concepts, slides: episode.slides ?? [])
        if let context = episode.modelContext {
            let id = episode.id
            let marks = (try? context.fetch(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.episodeID == id }, sortBy: [SortDescriptor(\.time)]))) ?? []
            input.bookmarks = marks.map { .init(time: $0.time, text: $0.text, note: $0.note, kind: $0.kind) }
            let notes = (try? context.fetch(FetchDescriptor<CornellNote>(predicate: #Predicate { $0.episodeID == id }, sortBy: [SortDescriptor(\.createdAt)]))) ?? []
            input.cornell = notes.map { .init(title: $0.title, cues: $0.cues, notes: $0.notes, summary: $0.summary) }
        }
        return input
    }

    nonisolated static func link(_ id: UUID, time: Double? = nil) -> String {
        AppLink.episode(id, time: time, play: false).url.absoluteString
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "/").trimmingCharacters(in: .whitespaces)
    }

    static func markdown(_ e: StudySheetInput) -> String {
        var md = "# [\(clean(e.title))](\(link(e.id)))\n\n"
        if let script = e.script {
            if !script.summary.isEmpty { md += "## Özet\n\n\(script.summary)\n\n" }
            if !script.keyPoints.isEmpty { md += "## Anahtar noktalar\n\n" + script.keyPoints.map { "- \(clean($0))" }.joined(separator: "\n") + "\n\n" }
        }
        if !e.bookmarks.isEmpty {
            md += "## Notlarım\n\n"
            for b in e.bookmarks {
                let label = b.kind == "confused" ? "Anlamadım" : b.kind == "flag" ? "İşaret" : "Not"
                let note = b.note.isEmpty ? "" : " — \(clean(b.note))"
                md += "- [\(b.time.clockText)](\(link(e.id, time: b.time))) \(label): \(clean(b.text))\(note)\n"
            }
            md += "\n"
        }
        if !e.cornell.isEmpty {
            md += "## Cornell notları\n\n"
            for n in e.cornell {
                md += "### \(clean(n.title.isEmpty ? "Not" : n.title))\n\n"
                if !n.cues.isEmpty { md += "**İpuçları:** \(clean(n.cues))\n\n" }
                if !n.notes.isEmpty { md += "**Notlar:** \(clean(n.notes))\n\n" }
                if !n.summary.isEmpty { md += "**Özet:** \(clean(n.summary))\n\n" }
            }
        }
        if !e.concepts.isEmpty {
            md += "## Kavramlar\n\n"
            for c in e.concepts {
                let page = c.sourcePage.map { " _(s. \($0))_" } ?? ""
                md += "- **\(clean(c.name))**: \(clean(c.definition))\(page)\n"
            }
            md += "\n"
        }
        if let formulas = e.study?.formulas, !formulas.isEmpty {
            md += "## Formüller\n\n"
            for f in formulas {
                let when = f.when.isEmpty ? "" : " (\(clean(f.when)))"
                md += "- **\(clean(f.name))**: `\(clean(f.expression))` — \(clean(f.meaning))\(when)\n"
            }
            md += "\n"
        }
        if !e.slides.isEmpty {
            md += "## Slaytlar\n\n"
            let starts = Dictionary((e.timeline?.chapters ?? []).map { ($0.id, $0.start) }, uniquingKeysWith: { a, _ in a })
            for s in e.slides {
                let title = clean(s.title)
                md += starts[s.chapterIndex].map { "### [\(title)](\(link(e.id, time: $0)))\n\n" } ?? "### \(title)\n\n"
                md += s.bullets.map { "- \(clean($0))" }.joined(separator: "\n") + "\n"
                if let formula = s.formula, !formula.isEmpty { md += "\n`\(clean(formula))`\n" }
                md += "\n"
            }
        }
        if let timeline = e.timeline {
            md += "## Transkript\n"
            for chapter in timeline.chapters {
                md += "\n### [\(clean(chapter.title))](\(link(e.id, time: chapter.start)))\n\n"
                for turn in timeline.turns where turn.chapterIndex == chapter.id {
                    let name = e.settings?.displayName(for: turn.speaker) ?? turn.speaker.rawValue
                    let page = turn.sourcePage.map { " _(s. \($0))_" } ?? ""
                    md += "**\(clean(name))** \(turn.start.clockText): \(turn.text)\(page)\n\n"
                }
            }
        }
        if let study = e.study {
            if !study.quiz.isEmpty {
                md += "## Quiz\n\n"
                for (i, q) in study.quiz.enumerated() {
                    md += "\(i + 1). \(clean(q.question))\n"
                    if q.options.isEmpty {
                        // Açık uçlu soru: şık yok, örnek cevap yazılır.
                        md += "   - Cevap: **\(clean(q.answerText ?? q.explanation))**\n"
                    } else {
                        for (j, o) in q.options.enumerated() { md += "   - \(j == q.answerIndex ? "**\(clean(o))** ✓" : clean(o))\n" }
                    }
                    if !q.explanation.isEmpty, !(q.options.isEmpty && q.answerText == nil) { md += "   > \(clean(q.explanation))\n" }
                    md += "\n"
                }
            }
            if !study.flashcards.isEmpty {
                md += "## Kartlar\n\n| Ön | Arka |\n|---|---|\n"
                for c in study.flashcards { md += "| \(clean(c.front)) | \(clean(c.back)) |\n" }
            }
        }
        return md
    }

    /// Serinin kitapçığı: içindekiler + her bölüm yeni sayfada.
    static func seriesSections(_ episodes: [Episode]) -> [String] {
        let sorted = episodes.sorted { $0.seriesIndex < $1.seriesIndex }
        let name = sorted.first?.seriesTitle ?? "Seri"
        var toc = "# \(clean(name))\n\n## İçindekiler\n\n"
        for (i, e) in sorted.enumerated() { toc += "- \(i + 1). [\(clean(e.title))](\(link(e.id)))\n" }
        return [toc] + sorted.map { markdown(input(for: $0)) }
    }

    /// Metinler (SwiftData okuması) ana iş parçacığında toplanır; dizgi ve PDF çizimi arka planda.
    static func writeSeriesPDF(_ episodes: [Episode]) async throws -> URL {
        let name = EpisodeExporter.safeName("Kitapçık - " + (episodes.first?.seriesTitle ?? "Seri"))
        let url = URL.temporaryDirectory.appending(path: "\(name).pdf")
        try await writePDF(sections: seriesSections(episodes), to: url)
        return url
    }

    static func writeSeriesMarkdown(_ episodes: [Episode]) throws -> URL {
        let name = EpisodeExporter.safeName("Kitapçık - " + (episodes.first?.seriesTitle ?? "Seri"))
        let url = URL.temporaryDirectory.appending(path: "\(name).md")
        try seriesSections(episodes).joined(separator: "\n\n---\n\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - PDF (TextKit; bağlantılar PDF bağlantı alanı olarak yazılır)

    nonisolated static let page = CGRect(x: 0, y: 0, width: 595, height: 842)
    /// Tek bölümün en çok sayfası (aşılırsa bölümün sonuna "kısaltıldı" sayfası eklenir).
    nonisolated static let maxPagesPerSection = 400
    nonisolated static let truncatedNote = "Bu bölüm \(maxPagesPerSection) sayfa sınırında kısaltıldı. Tamamı için föyü Markdown olarak dışa aktar."

    /// Ana iş parçacığını dondurmadan PDF üretir ve dosyaya yazar.
    @concurrent
    nonisolated static func writePDF(sections: [String], to url: URL) async throws {
        try Task.checkCancellation()
        try pdfData(sections: sections).write(to: url, options: .atomic)
    }

    /// Her bölüm yeni sayfada başlar. Ana iş parçacığı dışında da çağrılabilir.
    nonisolated static func pdfData(sections: [String], maxPages: Int = maxPagesPerSection) -> Data {
        let textRect = page.insetBy(dx: 40, dy: 48)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { ctx in
            for section in sections {
                let storage = NSTextStorage(attributedString: attributed(section))
                let layout = NSLayoutManager()
                storage.addLayoutManager(layout)
                var pages = 0
                var finished = false
                while pages < maxPages {
                    let container = NSTextContainer(size: textRect.size)
                    container.lineFragmentPadding = 0
                    layout.addTextContainer(container)
                    let glyphs = layout.glyphRange(for: container)
                    ctx.beginPage()
                    pages += 1
                    layout.drawBackground(forGlyphRange: glyphs, at: textRect.origin)
                    layout.drawGlyphs(forGlyphRange: glyphs, at: textRect.origin)
                    let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
                    storage.enumerateAttribute(.link, in: chars) { value, range, _ in
                        guard let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:)) else { return }
                        let g = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                        layout.enumerateEnclosingRects(forGlyphRange: g, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                                       in: container) { rect, _ in
                            UIGraphicsSetPDFContextURLForRect(url, rect.offsetBy(dx: textRect.minX, dy: textRect.minY))
                        }
                    }
                    if NSMaxRange(glyphs) >= layout.numberOfGlyphs { finished = true; break }
                }
                if !finished {
                    ctx.beginPage()
                    let note = NSAttributedString(string: truncatedNote, attributes: [
                        .font: UIFont.italicSystemFont(ofSize: 12), .foregroundColor: UIColor.darkGray,
                    ])
                    note.draw(with: textRect, options: [.usesLineFragmentOrigin], context: nil)
                }
            }
        }
    }

    /// Föy Markdown'ının sade biçimli metne çevrilmesi (başlık, madde, alıntı, tablo, kalın, italik, kod, bağlantı).
    nonisolated static func attributed(_ md: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let body = UIFont.systemFont(ofSize: 11)
        func paragraph(indent: CGFloat = 0, spacing: CGFloat = 4) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.firstLineHeadIndent = indent
            p.headIndent = indent
            p.paragraphSpacing = spacing
            p.lineSpacing = 1.5
            return p
        }
        for raw in md.components(separatedBy: "\n") {
            var line = raw
            var font = body
            var color = UIColor.black
            var style = paragraph()
            if line.hasPrefix("|---") { continue }
            if line.hasPrefix("### ") {
                line.removeFirst(4); font = .boldSystemFont(ofSize: 12.5); style = paragraph(spacing: 6)
            } else if line.hasPrefix("## ") {
                line.removeFirst(3); font = .boldSystemFont(ofSize: 15); style = paragraph(spacing: 8)
            } else if line.hasPrefix("# ") {
                line.removeFirst(2); font = .boldSystemFont(ofSize: 20); style = paragraph(spacing: 10)
            } else if line.hasPrefix("   > ") {
                line = String(line.dropFirst(5)); color = .darkGray; style = paragraph(indent: 22)
            } else if line.hasPrefix("   - ") {
                line = "◦ " + line.dropFirst(5); style = paragraph(indent: 22, spacing: 2)
            } else if line.hasPrefix("- ") {
                line = "• " + line.dropFirst(2); style = paragraph(indent: 10, spacing: 2)
            } else if line.hasPrefix("|") {
                line = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "  —  ")
            } else if line == "---" {
                continue
            }
            out.append(inline(line + "\n", font: font, color: color, style: style))
        }
        return out
    }

    /// Satır içi biçim: **kalın**, _(s. N)_ italik, `kod`, [metin](url).
    nonisolated private static func inline(_ text: String, font: UIFont, color: UIColor, style: NSParagraphStyle) -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let result = NSMutableAttributedString()
        let pattern = #"\*\*(.+?)\*\*|_(\(s\. \d+\))_|`([^`]+)`|\[([^\]]+)\]\(([^)\s]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return NSAttributedString(string: text, attributes: base) }
        let ns = text as NSString
        var cursor = 0
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > cursor {
                result.append(NSAttributedString(string: ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)), attributes: base))
            }
            var attrs = base
            let content: String
            if m.range(at: 1).location != NSNotFound {
                content = ns.substring(with: m.range(at: 1))
                attrs[.font] = UIFont.boldSystemFont(ofSize: font.pointSize)
            } else if m.range(at: 2).location != NSNotFound {
                content = ns.substring(with: m.range(at: 2))
                attrs[.font] = UIFont.italicSystemFont(ofSize: font.pointSize)
                attrs[.foregroundColor] = UIColor.gray
            } else if m.range(at: 3).location != NSNotFound {
                content = ns.substring(with: m.range(at: 3))
                attrs[.font] = UIFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
            } else {
                content = ns.substring(with: m.range(at: 4))
                if let url = URL(string: ns.substring(with: m.range(at: 5))) {
                    attrs[.link] = url
                    attrs[.foregroundColor] = UIColor.systemIndigo
                }
            }
            result.append(NSAttributedString(string: content, attributes: attrs))
            cursor = m.range.location + m.range.length
        }
        if cursor < ns.length { result.append(NSAttributedString(string: ns.substring(from: cursor), attributes: base)) }
        return result
    }
}
