import SwiftData
import SwiftUI
import UIKit

// Çıktılar ve aktarmalar: Çalış'a aktar (#24), çalışma kâğıdı PDF (#28), slayt PDF (#34), Anki / CSV (#37).

// MARK: - Çok sayfalı PDF yazıcı

/// Görünümleri sayfa sayfa PDF'e akıtır (ImageRenderer + CGContext). Sayfa dolunca yenisini açar.
@MainActor
final class PDFFlow {
    let pageSize: CGSize
    let margin: CGFloat
    private let ctx: CGContext
    private var y: CGFloat
    private var pageOpen = false

    init?(url: URL, pageSize: CGSize = CGSize(width: 595, height: 842), margin: CGFloat = 40) {
        var box = CGRect(origin: .zero, size: pageSize)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        self.ctx = ctx
        self.pageSize = pageSize
        self.margin = margin
        y = margin
    }

    var contentWidth: CGFloat { pageSize.width - margin * 2 }

    /// Soldan hizalı bir blok yerleştirir; sığmazsa yeni sayfa açar.
    func place(_ view: some View, spacingAfter: CGFloat = 8) {
        let width = contentWidth
        let renderer = ImageRenderer(content: view
            .frame(width: width, alignment: .leading)
            .foregroundStyle(.black)
            .environment(\.colorScheme, .light))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.render { [self] size, draw in
            if !pageOpen || (y + size.height > pageSize.height - margin && y > margin) {
                openPage()
                y = margin
            }
            ctx.saveGState()
            ctx.translateBy(x: margin, y: pageSize.height - y - size.height)
            draw(ctx)
            ctx.restoreGState()
            y += size.height + spacingAfter
        }
    }

    /// Bir sonraki bloğu yeni sayfadan başlatır.
    func breakPage() {
        if pageOpen { ctx.endPDFPage() }
        pageOpen = false
        y = margin
    }

    /// Tüm sayfayı kaplayan bir görünüm (slayt): kendi sayfasında.
    func fullPage(_ view: some View) {
        let size = pageSize
        let renderer = ImageRenderer(content: view
            .frame(width: size.width, height: size.height)
            .background(Color.white)
            .foregroundStyle(.black)
            .environment(\.colorScheme, .light))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.render { [self] rendered, draw in
            openPage()
            ctx.saveGState()
            ctx.translateBy(x: 0, y: size.height - rendered.height)
            draw(ctx)
            ctx.restoreGState()
            y = size.height
        }
    }

    func finish() {
        if pageOpen { ctx.endPDFPage() }
        pageOpen = false
        ctx.closePDF()
    }

    private func openPage() {
        if pageOpen { ctx.endPDFPage() }
        ctx.beginPDFPage(nil)
        pageOpen = true
    }
}

// MARK: - Kapsam seçici

/// "Tüm ders" ya da tek bir bölüm (çalışma kâğıdı).
struct ScopePicker: View {
    var chapters: [VideoChapter]
    @Binding var selection: Int

    var body: some View {
        Picker("Kapsam", selection: $selection) {
            Text("Tüm ders").tag(-1)
            ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                Text(chapter.title).tag(index)
            }
        }
        .pickerStyle(.menu)
    }
}

// MARK: - Çalış'a aktar (#24)

struct StudyExportView: View {
    var context: LessonContext

    @Environment(\.modelContext) private var modelContext
    @Query private var cards: [ReviewCard]
    @State private var includeConcepts = true
    @State private var includeFormulas = true
    @State private var includeQuestions = false
    @State private var message: String?
    @State private var showReview = false
    @State private var sheetURL: URL?

    init(context: LessonContext) {
        self.context = context
        let id = context.lesson.id
        _cards = Query(filter: #Predicate<ReviewCard> { $0.episodeID == id })
    }

    private var notes: LectureNotes? { context.transcript.notes }

    private var drafts: [TimedCardDraft] {
        guard let notes else { return [] }
        return NoteCardPlan.drafts(notes, existingFronts: Set(cards.map(\.front)), concepts: includeConcepts,
                                   questions: includeQuestions, formulas: includeFormulas)
    }

    var body: some View {
        StudySheet(title: "Çalış'a aktar") {
            if let notes, !(notes.concepts.isEmpty && notes.formulas.isEmpty && notes.questions.isEmpty) {
                content(notes)
            } else {
                ContentUnavailableView("Aktarılacak not yok", systemImage: "tray",
                                       description: Text("Bu derste kavram, formül ya da soru çıkarılmamış."))
            }
        }
        .sheet(isPresented: $showReview) { ReviewView() }
        .sheet(item: $sheetURL) { ShareSheet(items: [$0]) }
    }

    private func content(_ notes: LectureNotes) -> some View {
        List {
            Section {
                Toggle("Kavramlar (\(notes.concepts.count))", isOn: $includeConcepts)
                Toggle("Formüller (\(notes.formulas.count))", isOn: $includeFormulas)
                Toggle("Ders soruları (\(notes.questions.count))", isOn: $includeQuestions)
            } header: {
                Text("Karta çevrilecekler")
            } footer: {
                Text("Kartlar tekrar destesine eklenir ve öğretmenin sesinden dinlenebilir; aralıklı tekrar 1 – 3 – 7 gün gibi ilerler.")
            }
            Section {
                let count = drafts.count
                Button {
                    addCards()
                } label: {
                    Label(count == 0 ? "Yeni kart yok (hepsi ekli)" : "\(count) kartı tekrar destesine ekle", systemImage: "square.and.arrow.down.on.square")
                }
                .disabled(count == 0)
                if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
                if !cards.isEmpty {
                    Button("Şimdi tekrar et", systemImage: "play.circle") { showReview = true }
                }
            }
            if !notes.concepts.isEmpty {
                Section("Kavram ustalığı") {
                    ForEach(Array(notes.concepts.enumerated()), id: \.offset) { _, concept in
                        HStack(alignment: .firstTextBaseline) {
                            Text(concept.name).font(.callout).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            if let score = Mastery.score(for: concept.name, cards: Array(cards)) {
                                Text(Mastery.label(score))
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(Mastery.color(score).opacity(0.2)))
                                    .foregroundStyle(Mastery.color(score))
                            } else {
                                Text("Kart yok").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            Section {
                Button("Tek sayfa özet (PDF)", systemImage: "doc.text") { makeCheatSheet(notes) }
            } footer: {
                Text("Kavram ve formüller tek sayfalık özet olarak paylaşılır.")
            }
        }
    }

    private func addCards() {
        guard context.lesson.modelContext != nil, let notes else { return }
        let count = LessonStudy.addNoteCards(notes, lesson: context.lesson, context: modelContext, formulas: includeFormulas,
                                             concepts: includeConcepts, questions: includeQuestions)
        message = count > 0 ? "\(count) kart eklendi." : "Kartlar zaten ekli."
        if count > 0 { ReviewReminder.ensureScheduled() }
    }

    private func makeCheatSheet(_ notes: LectureNotes) {
        let title = context.lesson.title
        var rows: [(String, String, String)] = notes.concepts.map { ($0.name, $0.definition, title) }
        rows += notes.formulas.map { ($0.name, "\($0.expression)\n\($0.meaning)", title) }
        sheetURL = CheatSheet.render(rows)
    }
}

// MARK: - Çalışma kâğıdı (#28)

struct WorksheetView: View {
    var context: LessonContext

    @State private var scope = -1
    @State private var phase: StudyPhase<StudyWorksheet> = .idle
    @State private var rendering = false
    @State private var shareURL: URL?
    @State private var errorText: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        StudySheet(title: "Çalışma kâğıdı") {
            switch phase {
            case .idle: setup
            case .loading: StudyLoadingView(message: "Çalışma kâğıdı hazırlanıyor…", onCancel: { task?.cancel(); phase = .idle })
            case .failed(let message): StudyErrorView(message: message, retry: { phase = .idle })
            case .loaded(let sheet): ready(sheet)
            }
        }
        .onAppear { context.pausePlayback() }
        .onDisappear { task?.cancel() }
        .sheet(item: $shareURL) { ShareSheet(items: [$0]) }
    }

    private var setup: some View {
        Form {
            Section {
                ScopePicker(chapters: context.sortedChapters, selection: $scope)
            } footer: {
                Text("Boşluk doldurma, kısa cevaplı sorular ve terim–tanım eşleştirmesi hazırlanır; cevap anahtarı ayrı sayfada çıkar.")
            }
            Section {
                Button("Hazırla") { generate() }.frame(maxWidth: .infinity).font(.headline)
            }
        }
    }

    private func ready(_ sheet: StudyWorksheet) -> some View {
        List {
            Section("İçerik") {
                LabeledContent("Boşluk doldurma", value: "\(sheet.blanks.count)")
                LabeledContent("Soru", value: "\(sheet.questions.count)")
                LabeledContent("Eşleştirme", value: "\(sheet.matching.count)")
            }
            Section {
                Button {
                    makePDF(sheet)
                } label: {
                    if rendering { HStack { ProgressView(); Text("PDF hazırlanıyor…") } } else { Label("PDF oluştur ve paylaş", systemImage: "square.and.arrow.up") }
                }
                .disabled(rendering)
                if let errorText { Text(errorText).font(.caption).foregroundStyle(.red) }
                Button("Yeniden hazırla") { phase = .idle }
            }
        }
    }

    private func generate() {
        task?.cancel()
        let text: String
        if scope >= 0, let range = StudyText.chapterRange(context.transcript.chapters, index: scope, end: context.contentEnd) {
            text = StudyText.lines(context.transcript.paragraphs, from: range.start, to: range.end, maxChars: 100_000)
        } else {
            text = StudyText.lessonText(context.transcript, maxChars: 100_000)
        }
        guard text.count >= 20 else {
            phase = .failed("Seçilen kapsamın metni çok kısa.")
            return
        }
        let title = scope >= 0 && context.sortedChapters.indices.contains(scope)
            ? "\(context.lesson.title) — \(context.sortedChapters[scope].title)" : context.lesson.title
        phase = .loading
        task = Task {
            do {
                let sheet = try await APIClient.shared.studyWorksheet(StudyWorksheetRequest(title: title, text: text))
                try Task.checkCancellation()
                phase = sheet.isEmpty ? .failed("Çalışma kâğıdı hazırlanamadı. Lütfen tekrar dene.") : .loaded(sheet)
            } catch {
                if let message = StudyError.message(error) { phase = .failed(message) }
            }
        }
    }

    private func makePDF(_ sheet: StudyWorksheet) {
        rendering = true
        errorText = nil
        let title = context.lesson.title
        let seed = WorksheetLayout.seed(for: context.lesson.id.uuidString)
        let url = LessonFiles.exportURL(TranscriptFormat.fileName(title, suffix: " - Çalışma kâğıdı", ext: "pdf"))
        Task {
            await Task.yield()
            if WorksheetPDF.render(title: title, sheet: sheet, seed: seed, to: url) {
                shareURL = url
            } else {
                errorText = "PDF oluşturulamadı."
            }
            rendering = false
        }
    }
}

@MainActor
enum WorksheetPDF {
    static func render(title: String, sheet: StudyWorksheet, seed: UInt64, to url: URL) -> Bool {
        guard let flow = PDFFlow(url: url) else { return false }
        func heading(_ text: String) {
            flow.place(Text(text).font(.system(size: 14, weight: .bold)).padding(.top, 10), spacingAfter: 6)
        }
        flow.place(VStack(alignment: .leading, spacing: 6) {
            Text("Çalışma kâğıdı").font(.system(size: 22, weight: .bold))
            Text(title).font(.system(size: 12)).foregroundStyle(.gray)
            Text("Ad Soyad: ______________________     Tarih: ____________").font(.system(size: 11)).padding(.top, 6)
        }, spacingAfter: 10)

        if !sheet.blanks.isEmpty {
            heading("1. Boşlukları doldur")
            for (i, blank) in sheet.blanks.enumerated() {
                flow.place(Text("\(i + 1). \(WorksheetLayout.blanked(sentence: blank.sentence, answer: blank.answer))")
                    .font(.system(size: 12)), spacingAfter: 8)
            }
        }
        if !sheet.questions.isEmpty {
            heading("2. Kısa cevaplı sorular")
            for (i, item) in sheet.questions.enumerated() {
                flow.place(VStack(alignment: .leading, spacing: 14) {
                    Text("\(i + 1). \(item.question)").font(.system(size: 12))
                    Rectangle().fill(Color.gray.opacity(0.6)).frame(height: 0.5)
                    Rectangle().fill(Color.gray.opacity(0.6)).frame(height: 0.5)
                }, spacingAfter: 12)
            }
        }
        let order = WorksheetLayout.shuffledOrder(count: sheet.matching.count, seed: seed)
        if !sheet.matching.isEmpty {
            heading("3. Terimleri tanımlarla eşleştir (cevabı boşluğa harfle yaz)")
            for (i, pair) in sheet.matching.enumerated() {
                let definition = sheet.matching[order[i]].definition
                flow.place(HStack(alignment: .top, spacing: 14) {
                    Text("\(i + 1). \(pair.term)  ____").font(.system(size: 12, weight: .semibold)).frame(width: 190, alignment: .leading)
                    Text("\(StudyQuizRules.letter(i))) \(definition)").font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
                }, spacingAfter: 8)
            }
        }

        flow.breakPage()
        flow.place(Text("Cevap anahtarı").font(.system(size: 20, weight: .bold)), spacingAfter: 8)
        if !sheet.blanks.isEmpty {
            heading("1. Boşluklar")
            for (i, blank) in sheet.blanks.enumerated() {
                flow.place(Text("\(i + 1). \(blank.answer)").font(.system(size: 12)), spacingAfter: 4)
            }
        }
        if !sheet.questions.isEmpty {
            heading("2. Sorular")
            for (i, item) in sheet.questions.enumerated() {
                flow.place(Text("\(i + 1). \(item.answer)").font(.system(size: 11)), spacingAfter: 6)
            }
        }
        if !sheet.matching.isEmpty {
            heading("3. Eşleştirme")
            let key = WorksheetLayout.matchingKey(order: order)
            flow.place(Text(key.enumerated().map { "\($0 + 1)-\($1)" }.joined(separator: "   ")).font(.system(size: 12)), spacingAfter: 4)
        }
        flow.place(Text("Ders Podcast · YouTube Ders Stüdyosu").font(.system(size: 8)).foregroundStyle(.gray).padding(.top, 14))
        flow.finish()
        return true
    }
}

// MARK: - Slayt destesi (#34)

struct LessonSlidesView: View {
    var context: LessonContext

    @State private var rendering = false
    @State private var progress = 0.0
    @State private var shareURL: URL?
    @State private var errorText: String?
    @State private var task: Task<Void, Never>?

    private var slides: [SlideSpec] { SlidePlan.build(title: context.lesson.title, transcript: context.transcript) }

    var body: some View {
        StudySheet(title: "Slayt destesi") {
            let current = slides
            List {
                Section {
                    LabeledContent("Slayt", value: "\(current.count)")
                    LabeledContent("Kare", value: "\(current.filter { $0.frameID != nil }.count)")
                } footer: {
                    Text("Her kare için o anda anlatılanın özeti ve ana noktalar tek yatay sayfada toplanır; PDF olarak paylaşılır.")
                }
                Section {
                    if rendering {
                        ProgressView(value: progress)
                        Text("Slaytlar hazırlanıyor… \(Int(progress * 100))%").font(.callout).foregroundStyle(.secondary)
                        Button("Vazgeç", role: .cancel) { task?.cancel() }
                    } else {
                        Button("Slayt PDF'i oluştur", systemImage: "rectangle.on.rectangle") { render(current) }
                            .disabled(current.count < 2)
                    }
                    if let errorText { Text(errorText).font(.caption).foregroundStyle(.red) }
                }
                Section("Önizleme") {
                    ForEach(Array(current.prefix(12).enumerated()), id: \.offset) { _, slide in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(slide.title).font(.callout.weight(.semibold)).lineLimit(2)
                            if let time = slide.timeLabel { Text(time).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                        }
                    }
                    if current.count > 12 { Text("…ve \(current.count - 12) slayt daha").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .onDisappear { task?.cancel() }
        .sheet(item: $shareURL) { ShareSheet(items: [$0]) }
    }

    private func render(_ slides: [SlideSpec]) {
        rendering = true
        progress = 0
        errorText = nil
        let lessonID = context.lesson.id
        let title = context.lesson.title
        let url = LessonFiles.exportURL(TranscriptFormat.fileName(title, suffix: " - Slaytlar", ext: "pdf"))
        task = Task {
            defer { rendering = false }
            guard let flow = PDFFlow(url: url, pageSize: SlidePageView.pageSize, margin: 0) else {
                errorText = "PDF oluşturulamadı."
                return
            }
            for (index, slide) in slides.enumerated() {
                if Task.isCancelled {
                    flow.finish()
                    return
                }
                // Kare yalnız çizilirken bellekte durur (ana iş parçacığı dışında küçültülür); tüm kareler aynı anda tutulmaz.
                var image: UIImage?
                if let id = slide.frameID {
                    image = await LessonFiles.thumbnail(VideoFiles.keyframeURL(lesson: lessonID, frame: id), maxPixel: 900)
                }
                flow.fullPage(SlidePageView(spec: slide, image: image, index: index + 1, total: slides.count))
                image = nil
                progress = Double(index + 1) / Double(slides.count)
                await Task.yield()
            }
            flow.finish()
            shareURL = url
        }
    }
}

/// Tek slayt sayfası (yatay A4).
struct SlidePageView: View {
    static let pageSize = CGSize(width: 842, height: 595)

    var spec: SlideSpec
    var image: UIImage?
    var index: Int
    var total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch spec.kind {
            case .cover:
                Spacer()
                Text(spec.title).font(.system(size: 36, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                if !spec.body.isEmpty { Text(spec.body).font(.system(size: 15)).foregroundStyle(.gray) }
                Spacer()
            case .concepts:
                Text(spec.title).font(.system(size: 26, weight: .bold))
                ForEach(Array(spec.bullets.enumerated()), id: \.offset) { _, bullet in
                    Text("• " + bullet).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            case .content:
                HStack(alignment: .firstTextBaseline) {
                    Text(spec.title).font(.system(size: 24, weight: .bold)).lineLimit(2)
                    Spacer()
                    if let time = spec.timeLabel { Text(time).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(.gray) }
                }
                HStack(alignment: .top, spacing: 22) {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxWidth: 440, maxHeight: 400)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        if !spec.body.isEmpty { Text(spec.body).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true) }
                        ForEach(Array(spec.bullets.enumerated()), id: \.offset) { _, bullet in
                            Text("• " + bullet).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Text("Ders Podcast").font(.system(size: 9)).foregroundStyle(.gray)
                Spacer()
                Text("\(index) / \(total)").font(.system(size: 9).monospacedDigit()).foregroundStyle(.gray)
            }
        }
        .padding(36)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .topLeading)
    }
}

// MARK: - Anki / CSV (#37)

struct AnkiExportView: View {
    var context: LessonContext

    private enum Format: String, CaseIterable, Identifiable {
        case anki, csv
        var id: String { rawValue }
        var title: String { self == .anki ? "Anki (TSV)" : "CSV" }
    }

    @Query private var cards: [ReviewCard]
    @State private var format: Format = .anki
    @State private var includeConcepts = true
    @State private var includeFormulas = true
    @State private var shareURL: URL?
    @State private var errorText: String?

    init(context: LessonContext) {
        self.context = context
        let id = context.lesson.id
        _cards = Query(filter: #Predicate<ReviewCard> { $0.episodeID == id }, sort: \.createdAt)
    }

    private var rows: [CardExportRow] {
        let tag = context.lesson.title
        var result = cards.map { CardExportRow(front: $0.front, back: $0.back, tag: tag) }
        if let notes = context.transcript.notes {
            let extra = NoteCardPlan.drafts(notes, existingFronts: Set(cards.map(\.front)), concepts: includeConcepts,
                                            questions: false, formulas: includeFormulas)
            result += extra.map { CardExportRow(front: $0.front, back: $0.back, tag: tag) }
        }
        return result
    }

    var body: some View {
        StudySheet(title: "Anki / CSV") {
            let current = rows
            Form {
                Section {
                    Picker("Biçim", selection: $format) {
                        ForEach(Format.allCases) { Text($0.title).tag($0) }
                    }
                    .modifier(AccessiblePickerStyle())
                } footer: {
                    Text(format == .anki
                         ? "Anki'de Dosya → İçe Aktar ile açılır; ön yüz, arka yüz ve etiket sütunları hazırdır."
                         : "Excel, Numbers ve Google E-Tablolar'da açılır (UTF-8, virgülle ayrılmış).")
                }
                Section {
                    Toggle("Henüz kart olmayan kavramlar", isOn: $includeConcepts)
                    Toggle("Henüz kart olmayan formüller", isOn: $includeFormulas)
                } header: {
                    Text("Eklenecekler")
                } footer: {
                    Text("Bu dersin \(cards.count) kartı her zaman dahildir.")
                }
                Section {
                    LabeledContent("Toplam kart", value: "\(current.count)")
                    Button("Dosyayı hazırla ve paylaş", systemImage: "square.and.arrow.up") { export(current) }
                        .disabled(current.isEmpty)
                    if let errorText { Text(errorText).font(.caption).foregroundStyle(.red) }
                }
            }
        }
        .sheet(item: $shareURL) { ShareSheet(items: [$0]) }
    }

    private func export(_ rows: [CardExportRow]) {
        let title = context.lesson.title
        let text = format == .anki ? CardExport.anki(rows) : CardExport.csv(rows)
        let ext = format == .anki ? "txt" : "csv"
        let url = LessonFiles.exportURL(TranscriptFormat.fileName(title, suffix: " - Kartlar", ext: ext))
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            shareURL = url
            errorText = nil
        } catch {
            errorText = "Dosya yazılamadı: \(error.localizedDescription)"
        }
    }
}
