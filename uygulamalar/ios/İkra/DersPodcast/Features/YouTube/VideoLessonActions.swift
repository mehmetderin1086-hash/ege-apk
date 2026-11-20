import Foundation
import ImageIO
import SwiftData
import SwiftUI
import UIKit

// MARK: - Arka plan yükleme ve dosya işleri

/// Ana iş parçacığını bloklamayan yükleme/yazma işleri (yalnızca Sendable değerler alır).
nonisolated enum LessonFiles {
    /// Kayıtlı transkripti çözer.
    @concurrent
    static func decodeTranscript(_ data: Data) async -> VideoTranscript? {
        try? JSONDecoder().decode(VideoTranscript.self, from: data)
    }

    /// Kayıtlı transkriptlerin düz metinleri (podcast kaynağı için); çözülemeyen boş döner. Sıra korunur.
    @concurrent
    static func plainTexts(_ datas: [Data?]) async -> [String] {
        datas.map { data in
            data.flatMap { try? JSONDecoder().decode(VideoTranscript.self, from: $0) }?.plainText() ?? ""
        }
    }

    /// Arama anahtarları (satır başına), büyük transkriptlerde ana iş parçacığı dışında.
    @concurrent
    static func searchKeys(_ texts: [String]) async -> [[Character]] {
        texts.map(TranscriptFormat.searchKey)
    }

    /// Dosyadan küçültülmüş görsel (ImageIO; tam boy görsel belleğe açılmaz).
    @concurrent
    static func thumbnail(_ url: URL, maxPixel: Int) async -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: image)
    }

    @concurrent
    static func image(_ url: URL) async -> UIImage? {
        UIImage(contentsOfFile: url.path)
    }

    nonisolated enum TextExport: Sendable {
        case srt, txt, markdown
    }

    /// Metin dışa aktarmasını üretir ve geçici klasöre yazar (ikisi de ana iş parçacığı dışında).
    @concurrent
    static func exportText(_ kind: TextExport, transcript: VideoTranscript, title: String, channel: String, url: String) async throws -> URL {
        let text: String
        let fileName: String
        switch kind {
        case .srt:
            let segments = transcript.segments.isEmpty
                ? transcript.paragraphs.map { TranscriptSegment(start: $0.start, end: $0.end, text: $0.text) }
                : transcript.segments
            text = TranscriptFormat.srt(segments)
            fileName = TranscriptFormat.fileName(title, ext: "srt")
        case .txt:
            text = TranscriptFormat.plainText(title: title, channel: channel, url: url,
                                              paragraphs: transcript.paragraphs, chapters: transcript.chapters)
            fileName = TranscriptFormat.fileName(title, ext: "txt")
        case .markdown:
            text = TranscriptFormat.markdown(title: title, channel: channel, transcript: transcript)
            fileName = TranscriptFormat.fileName(title, suffix: " - Ders notu", ext: "md")
        }
        let destination = exportURL(fileName)
        try Data(text.utf8).write(to: destination, options: .atomic)
        return destination
    }

    static func exportURL(_ fileName: String) -> URL {
        let dir = URL.temporaryDirectory.appending(path: "VideoExport", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: fileName)
        try? FileManager.default.removeItem(at: url)
        return url
    }

    /// Kare JPEG'ini bölümün figure_<id>.png dosyasına PNG olarak yazar; yazılan şekil kimliklerini döndürür.
    nonisolated struct FigureCopy: Sendable {
        var figureID: String
        var source: URL
        var destination: URL
    }

    @concurrent
    static func copyFigures(_ jobs: [FigureCopy]) async -> Set<String> {
        var written = Set<String>()
        for job in jobs {
            guard let image = UIImage(contentsOfFile: job.source.path), let png = image.pngData() else { continue }
            if (try? png.write(to: job.destination, options: .atomic)) != nil { written.insert(job.figureID) }
        }
        return written
    }
}

// MARK: - Çalışma eylemleri (kart, Cornell notu)

enum LessonStudy {
    /// Mevcut kartların ön yüzleri (bu ders için).
    static func existingFronts(lessonID: UUID, context: ModelContext) -> Set<String> {
        let id = lessonID
        let cards = (try? context.fetch(FetchDescriptor<ReviewCard>(predicate: #Predicate { $0.episodeID == id }))) ?? []
        return Set(cards.map(\.front))
    }

    /// Paragraftan tek kart; aynı ön yüz varsa eklemez (false). `clip` verilirse kart sesli olur (tekrarda "Dinle").
    @discardableResult
    static func addCard(_ draft: LessonCardDraft, lesson: VideoLesson, context: ModelContext, clip: ClipRange? = nil) -> Bool {
        guard !draft.back.isEmpty else { return false }
        let id = lesson.id, front = draft.front, back = draft.back
        let duplicates = (try? context.fetchCount(FetchDescriptor<ReviewCard>(predicate: #Predicate {
            $0.episodeID == id && $0.front == front && $0.back == back
        }))) ?? 0
        guard duplicates == 0 else { return false }
        let card = ReviewCard(episodeID: lesson.id, episodeTitle: lesson.title, kind: .flashcard,
                              front: front, back: back, sourcePage: nil)
        attach(clip, to: card, lesson: lesson)
        context.insert(card)
        try? context.save()
        return true
    }

    /// Kartı ders sesinden bir kesite bağlar (sesli kart); geçersiz aralıkta bağlamaz.
    static func attach(_ clip: ClipRange?, to card: ReviewCard, lesson: VideoLesson) {
        guard let clip, clip.start.isFinite, clip.end.isFinite, clip.start >= 0, clip.duration >= 1 else { return }
        card.clipLessonID = lesson.id
        card.clipStart = clip.start
        card.clipEnd = min(clip.end, clip.start + 90)
    }

    /// Ders notundaki kavram ve soruları kart yapar; eklenen kart sayısı. Kartlar anın paragrafına bağlı sesli kart olur.
    static func addNoteCards(_ notes: LectureNotes, lesson: VideoLesson, context: ModelContext,
                             formulas: Bool = false, concepts: Bool = true, questions: Bool = true) -> Int {
        let drafts = NoteCardPlan.drafts(notes, existingFronts: existingFronts(lessonID: lesson.id, context: context),
                                         concepts: concepts, questions: questions, formulas: formulas)
        guard !drafts.isEmpty else { return 0 }
        let paragraphs = lesson.transcript?.paragraphs ?? []
        for draft in drafts {
            let card = ReviewCard(episodeID: lesson.id, episodeTitle: lesson.title, kind: .flashcard,
                                  front: draft.front, back: draft.back, sourcePage: nil)
            if let time = draft.time, !paragraphs.isEmpty {
                attach(ClipPlanner.cardClip(at: time, paragraphs: paragraphs), to: card, lesson: lesson)
            }
            context.insert(card)
        }
        try? context.save()
        return drafts.count
    }

    /// Quiz/deneme yanlışı: yanlış defterine (kaynak "video", ders kimliği + an) ve tekrar destesine (sesli kart) ekler.
    /// Aynı soru açık durumdaysa yinelenmez.
    static func recordWrong(_ question: StudyQuestion, myAnswer: String, lesson: VideoLesson, fallbackTime: Double?,
                            clip: ClipRange?, context: ModelContext) {
        let text = question.question, id = lesson.id
        let correct = question.choices[safeAnswer: question.answer] ?? ""
        let openCount = (try? context.fetchCount(FetchDescriptor<MistakeEntry>(predicate: #Predicate {
            $0.question == text && $0.episodeID == id && !$0.resolved
        }))) ?? 0
        if openCount == 0 {
            let entry = MistakeEntry(question: text, myAnswer: myAnswer, correctAnswer: correct, why: question.explanation,
                                     source: "video", episodeID: lesson.id, episodeTitle: lesson.title, courseID: lesson.courseID)
            entry.videoTime = question.time ?? fallbackTime
            context.insert(entry)
        }
        let cardCount = (try? context.fetchCount(FetchDescriptor<ReviewCard>(predicate: #Predicate {
            $0.episodeID == id && $0.front == text
        }))) ?? 0
        if cardCount == 0 {
            let back = question.explanation.isEmpty ? correct : "\(correct)\n\n\(question.explanation)"
            let card = ReviewCard(episodeID: lesson.id, episodeTitle: lesson.title, kind: .quiz, front: text, back: back, sourcePage: nil)
            attach(clip, to: card, lesson: lesson)
            context.insert(card)
        }
        try? context.save()
        ReviewReminder.ensureScheduled()
    }

    /// "Anlamadım": zayıf nokta olarak yanlış defterine düşer (Koç açık kayıtları görür). Aynı an yinelenmez.
    static func recordConfused(time: Double, topic: String, explanation: String, example: String, lesson: VideoLesson,
                               context: ModelContext) {
        let label = TranscriptFormat.timestamp(time)
        let question = "Anlamadığım yer: \(topic.isEmpty ? lesson.title : topic) (\(label))"
        let id = lesson.id
        let existing = (try? context.fetchCount(FetchDescriptor<MistakeEntry>(predicate: #Predicate {
            $0.question == question && $0.episodeID == id && !$0.resolved
        }))) ?? 0
        guard existing == 0 else { return }
        let entry = MistakeEntry(question: question, myAnswer: "", correctAnswer: StudyText.excerpt(explanation, maxChars: 400),
                                 why: example, source: "confused", episodeID: lesson.id, episodeTitle: lesson.title,
                                 courseID: lesson.courseID)
        entry.videoTime = time
        context.insert(entry)
        try? context.save()
    }

    /// Video başlıklı Cornell notuna "[mm:ss] alıntı" satırı ekler (yoksa not oluşturur).
    /// Aynı adlı bir podcast bölümünün notuna yazılmasın diye yalnızca bölüme bağlı olmayan notlar aranır
    /// (episodeID'ye ders kimliği yazılmaz: not ekranı onu bölüm sanıp Feynman'ı açardı).
    static func appendToCornell(time: Double, quote: String, lesson: VideoLesson, context: ModelContext) {
        let title = lesson.title.isEmpty ? "YouTube dersi" : lesson.title
        var descriptor = FetchDescriptor<CornellNote>(predicate: #Predicate { $0.title == title && $0.episodeID == nil },
                                                      sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        let note: CornellNote
        if let found = (try? context.fetch(descriptor))?.first {
            note = found
        } else {
            note = CornellNote(title: title)
            context.insert(note)
        }
        let line = TranscriptFormat.noteLine(time: time, quote: quote)
        note.notes = note.notes.isEmpty ? line : note.notes + "\n" + line
        note.updatedAt = .now
        try? context.save()
    }
}

// MARK: - Ders notu PDF'i

enum LessonPDF {
    static let pageSize = CGSize(width: 595, height: 842)
    static let margin: CGFloat = 40

    /// Çok sayfalı PDF: başlık, özet, bölümler, notlar, kareler (görselle); not yoksa transkript.
    static func render(title: String, channel: String, transcript: VideoTranscript, frames: [String: UIImage], to url: URL) -> Bool {
        let width = pageSize.width - margin * 2
        var box = CGRect(origin: .zero, size: pageSize)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return false }
        var y = margin
        var pageOpen = false

        func place(_ view: some View, spacingAfter: CGFloat = 8) {
            let renderer = ImageRenderer(content: view
                .frame(width: width, alignment: .leading)
                .foregroundStyle(.black)
                .environment(\.colorScheme, .light))
            renderer.proposedSize = ProposedViewSize(width: width, height: nil)
            renderer.render { size, draw in
                if !pageOpen || (y + size.height > pageSize.height - margin && y > margin) {
                    if pageOpen { ctx.endPDFPage() }
                    ctx.beginPDFPage(nil)
                    pageOpen = true
                    y = margin
                }
                ctx.saveGState()
                ctx.translateBy(x: margin, y: pageSize.height - y - size.height)
                draw(ctx)
                ctx.restoreGState()
                y += size.height + spacingAfter
            }
        }

        func heading(_ text: String) {
            place(Text(text).font(.system(size: 15, weight: .bold)).padding(.top, 8), spacingAfter: 4)
        }

        func paragraph(_ text: String, time: Double? = nil, bold: String? = nil) {
            for (i, chunk) in TranscriptFormat.chunks(text).enumerated() {
                var line = AttributedString()
                if let bold, i == 0 {
                    var label = AttributedString(bold + ": ")
                    label.font = .system(size: 11, weight: .bold)
                    line += label
                }
                line += AttributedString(chunk)
                place(HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let time, i == 0 {
                        Text(TranscriptFormat.timestamp(time)).font(.system(size: 9, weight: .semibold).monospacedDigit()).foregroundStyle(.gray)
                    }
                    Text(line).font(.system(size: 11))
                }, spacingAfter: 5)
            }
        }

        let id = transcript.video.id
        place(VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 21, weight: .bold))
            Text([channel, TranscriptFormat.timestamp(transcript.video.duration), TranscriptFormat.shareURL(videoID: id)?.absoluteString ?? ""]
                .filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 10)).foregroundStyle(.gray)
        }, spacingAfter: 12)

        let chapters = transcript.chapters.sorted { $0.start < $1.start }
        if let notes = transcript.notes {
            if !notes.summary.isEmpty { heading("Özet"); paragraph(notes.summary) }
            if !chapters.isEmpty { heading("Bölümler"); chapters.forEach { paragraph($0.title, time: $0.start) } }
            if !notes.keyPoints.isEmpty { heading("Ana noktalar"); notes.keyPoints.forEach { paragraph("• " + $0.text, time: $0.time) } }
            if !notes.concepts.isEmpty { heading("Kavramlar"); notes.concepts.forEach { paragraph($0.definition, time: $0.time, bold: $0.name) } }
            if !notes.formulas.isEmpty {
                heading("Formüller")
                for f in notes.formulas {
                    place(VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(TranscriptFormat.timestamp(f.time)).font(.system(size: 9, weight: .semibold).monospacedDigit()).foregroundStyle(.gray)
                            Text(f.name).font(.system(size: 11, weight: .bold))
                        }
                        Text(f.expression).font(.system(size: 12, design: .monospaced))
                        if !f.meaning.isEmpty { Text(f.meaning).font(.system(size: 10)).foregroundStyle(.gray) }
                    }, spacingAfter: 6)
                }
            }
            if !notes.questions.isEmpty {
                heading("Sorular")
                for (i, q) in notes.questions.enumerated() {
                    paragraph(q.question, time: q.time, bold: "Soru \(i + 1)")
                    paragraph(q.answer, bold: "Cevap")
                }
            }
            if !notes.examTips.isEmpty { heading("Sınav ipuçları"); notes.examTips.forEach { paragraph("• " + $0) } }
        } else {
            if !chapters.isEmpty { heading("Bölümler"); chapters.forEach { paragraph($0.title, time: $0.start) } }
        }

        let sortedFrames = transcript.keyframes.sorted { $0.time < $1.time }
        if !sortedFrames.isEmpty {
            heading("Tahta ve slayt kareleri")
            for frame in sortedFrames {
                place(VStack(alignment: .leading, spacing: 4) {
                    if let image = frames[frame.id] {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: width, maxHeight: 300, alignment: .leading)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(TranscriptFormat.timestamp(frame.time)).font(.system(size: 9, weight: .semibold).monospacedDigit()).foregroundStyle(.gray)
                        Text(frame.caption).font(.system(size: 11, weight: .semibold))
                    }
                    if !frame.text.isEmpty {
                        Text(TranscriptFormat.chunks(frame.text, maxLength: 900, maxLines: 14).first ?? "").font(.system(size: 9)).foregroundStyle(.gray)
                    }
                }, spacingAfter: 12)
            }
        }

        if transcript.notes == nil {
            heading("Transkript")
            for p in transcript.paragraphs.sorted(by: { $0.start < $1.start }) { paragraph(p.text, time: p.start) }
        }

        place(Text("Ders Podcast · YouTube Ders Stüdyosu").font(.system(size: 8)).foregroundStyle(.gray).padding(.top, 10))
        if pageOpen { ctx.endPDFPage() }
        ctx.closePDF()
        return true
    }
}

private extension Array where Element == String {
    subscript(safeAnswer index: Int) -> String? { indices.contains(index) ? self[index] : nil }
}
