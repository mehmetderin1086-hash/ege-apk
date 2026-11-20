import PhotosUI
import SwiftData
import SwiftUI
import Vision

/// Yanlış defteri: her yanlış buraya düşer; "neden yanlış?" açıklaması ve çözülme durumu tutulur.
enum MistakeBook {
    /// Quiz/deneme yanlışı. Aynı soru açık durumdaysa yinelenmez; "üst üste doğru" serisi sıfırlanır (bir kez bilinmiş soru
    /// yeniden yanlış yapıldıysa tek "Bildim" onu çözülmüş saymasın) ve son somut yanlış cevap yazılır (`repeatedAnswer`).
    /// Podcast'ten geldiyse konunun anı ve indeksi saklanır (#24, #25).
    static func record(_ item: QuizItem, myAnswer: String, episode: Episode?, source: String, context: ModelContext,
                       podcastTime: Double? = nil, chapterIndex: Int? = nil) {
        let question = item.question, answer = QuestionKind.expectedAnswer(item)
        let existing = (try? context.fetch(FetchDescriptor<MistakeEntry>(predicate: #Predicate { $0.question == question && !$0.resolved }))) ?? []
        if !existing.isEmpty {
            // Kökü aynı, doğru cevabı başka girdi başka bir sorudur ("Aşağıdakilerden hangisi doğrudur?"): ona dokunulmaz.
            for open in existing where open.correctAnswer == answer {
                open.correctStreak = 0
                open.myAnswer = repeatedAnswer(old: open.myAnswer, new: myAnswer)
                registerEvidence(open, item: item, episode: episode, context: context)
            }
            try? context.save()
            return
        }
        let entry = MistakeEntry(question: item.question, myAnswer: myAnswer,
                                 correctAnswer: answer, why: item.explanation,
                                 source: source, episodeID: episode?.id, episodeTitle: episode?.title ?? "", sourcePage: item.sourcePage)
        entry.chapterIndex = chapterIndex ?? item.chapterIndex
        entry.podcastTime = podcastTime ?? episode.flatMap { ListenAnchor.time(for: item, timeline: $0.timeline) }
        context.insert(entry)
        try? context.save()
        registerEvidence(entry, item: item, episode: episode, context: context)
    }

    private static func registerEvidence(_ entry: MistakeEntry, item: QuizItem, episode: Episode?, context: ModelContext) {
        guard !context.container.configurations.allSatisfy(\.isStoredInMemoryOnly) else { return }
        let chapter = (item.chapterIndex ?? entry.chapterIndex).flatMap { episode?.script?.chapters[safe: $0]?.title }
        MistakeRemediationStore.shared.register(entry, item: item, topic: chapter ?? episode?.title ?? entry.question)
    }

    /// Etiket quiz'i yanlışı.
    static func recordLabel(expected: String, given: String, figureCaption: String, episode: Episode, context: ModelContext) {
        let question = "Şekil: \(figureCaption) — işaretli yapı nedir?"
        let answer = expected
        let existing = try? context.fetch(FetchDescriptor<MistakeEntry>(predicate: #Predicate { $0.question == question && $0.correctAnswer == answer && !$0.resolved }))
        if existing?.isEmpty == false { return }
        let entry = MistakeEntry(question: "Şekil: \(figureCaption) — işaretli yapı nedir?", myAnswer: given, correctAnswer: expected,
                                 why: "", source: "label", episodeID: episode.id, episodeTitle: episode.title)
        context.insert(entry)
        try? context.save()
    }

    /// Cevap verilmeden geçilen soruda çağıranların yazdığı yer tutucular (eller serbest "Bilemedim", denemede "Boş").
    nonisolated static let placeholderAnswers: Set<String> = ["Bilemedim", "Boş"]

    /// Açık girdi yeniden yanlış yapılınca "benim cevabım": yeni somut cevap yazılır; boş cevap ya da yer tutucu eldeki
    /// cevabı silmez (yer tutucu yalnız yeni girdide görünür).
    nonisolated static func repeatedAnswer(old: String, new: String) -> String {
        let given = new.trimmingCharacters(in: .whitespacesAndNewlines)
        return given.isEmpty || placeholderAnswers.contains(given) ? old : new
    }

    // MARK: - Çözme turu (saf; testlenir)

    /// Çözme turunun girdileri: önce az çalışılan, eşitlikte yeni olan. Yalnız en yeniler seçilseydi eskiler hiç sıraya girmezdi.
    nonisolated static func practiceOrder(_ items: [(id: UUID, reviewed: Int, created: Date)], limit: Int = 10) -> [UUID] {
        items.sorted { ($0.reviewed, $1.created) < ($1.reviewed, $0.created) }.prefix(max(0, limit)).map(\.id)
    }

    /// Tur sonu özeti. `solved`: bu turda defterden düşen (üst üste ikinci kez bilinen) soru sayısı.
    nonisolated static func practiceSummary(known: Int, total: Int, solved: Int) -> String {
        "\(known) / \(total) bildin · \(solved) soru defterden düştü"
    }

    // MARK: - Arama ve kaynak süzgeci (saf; testlenir)

    /// Kaynak süzgeci. Her girdi "Tümü" dışında tam bir gruba düşer.
    nonisolated enum Group: String, CaseIterable, Identifiable, Sendable {
        case all, podcast, video, exam, label, solver, manual
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "Tümü"
            case .podcast: "Podcast ve quiz"
            case .video: "Video"
            case .exam: "Deneme"
            case .label: "Etiket"
            case .solver: "Soru çöz"
            case .manual: "Elle ve diğer"
            }
        }

        /// Tanınmayan kaynak "Elle ve diğer"e düşer: hiçbir yanlış süzgeçlerin dışında kalmaz.
        static func of(source: String) -> Group {
            switch source {
            case "quiz", "inline", "handsfree", "probe", "endcard", "pretest", "discriminate": .podcast
            case "video", "confused": .video
            case "exam": .exam
            case "label": .label
            case "question-solver": .solver
            default: .manual
            }
        }
    }

    nonisolated static func sourceTitle(_ source: String) -> String {
        switch source {
        case "quiz": "Quiz"
        case "inline": "Dinlerken"
        case "handsfree": "Eller serbest"
        case "probe": "Yoklama"
        case "endcard": "Bölüm sonu"
        case "pretest": "Ön test"
        case "exam": "Deneme"
        case "video", "confused": "Video"
        case "label": "Etiket"
        case "discriminate": "Ayırt etme"
        case "question-solver": "Soru çöz"
        case "manual": "Elle"
        default: "Diğer"
        }
    }

    /// Satırın alt bilgisi: "Dinlerken · Hücre zarı". Bölüm adı kaynağı yineliyorsa ("Soru çöz · Soru Çöz") yazılmaz.
    nonisolated static func sourceLine(source: String, episodeTitle: String) -> String {
        let title = sourceTitle(source)
        let episode = episodeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !episode.isEmpty, LibrarySearch.fold(episode) != LibrarySearch.fold(title) else { return title }
        return "\(title) · \(episode)"
    }

    /// Arama (soru, cevaplar, açıklama, bölüm adı) ve kaynak grubu birlikte; boş sorgu yalnız gruba bakar.
    nonisolated static func matches(question: String, myAnswer: String = "", correct: String = "", why: String = "",
                                    episodeTitle: String = "", source: String = "manual", query: String, group: Group) -> Bool {
        guard group == .all || Group.of(source: source) == group else { return false }
        return StudySearch.matches([question, myAnswer, correct, why, episodeTitle], query: query)
    }
}

struct MistakeBookView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Query(sort: \MistakeEntry.createdAt, order: .reverse) private var entries: [MistakeEntry]
    @State private var showResolved = false
    @State private var showAdd = false
    /// Çözme oturumunun girdileri düğmeye basıldığı anda sabitlenir (çözülen girdi listeden düşünce sıra kaymasın).
    /// Sayfa öğeyle açılır: gövdede okunmayan ayrı bir kimlik durumu, sayfa içeriğine bayat (boş) ulaşıyordu.
    private struct PracticeRound: Identifiable { let id = UUID(); let ids: [UUID] }
    @State private var practiceRound: PracticeRound?
    @State private var query = ""
    @State private var group = MistakeBook.Group.all

    /// Aramaya ve kaynak süzgecine uyan girdiler; açık ve çözülmüş tek geçişte ayrılır.
    private var parts: (open: [MistakeEntry], resolved: [MistakeEntry]) {
        var open: [MistakeEntry] = [], resolved: [MistakeEntry] = []
        for entry in entries where MistakeBook.matches(question: entry.question, myAnswer: entry.myAnswer, correct: entry.correctAnswer,
                                                       why: entry.why, episodeTitle: entry.episodeTitle, source: entry.source,
                                                       query: query, group: group) {
            if entry.resolved { resolved.append(entry) } else { open.append(entry) }
        }
        return (open, resolved)
    }

    private var filtering: Bool { group != .all || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            let shown = parts
            List {
                if group != .all {
                    Section {
                        Button {
                            group = .all
                        } label: {
                            Label("Süzgeç: \(group.title) (kaldır)", systemImage: "line.3.horizontal.decrease.circle.fill")
                        }
                    }
                }
                if !shown.open.isEmpty {
                    Section {
                        Button {
                            practiceRound = PracticeRound(ids: MistakeBook.practiceOrder(shown.open.map { (id: $0.id, reviewed: $0.reviewedCount, created: $0.createdAt) }))
                        } label: {
                            Label("Yanlışları çöz (\(min(shown.open.count, 10)) soru)", systemImage: "arrow.clockwise.circle.fill")
                        }
                    }
                } else if !filtering {
                    ContentUnavailableView("Defter boş", systemImage: "checkmark.seal",
                                           description: Text("Quiz ve denemelerdeki yanlışlar otomatik olarak buraya düşer. Elle de ekleyebilirsin."))
                } else {
                    ContentUnavailableView("Eşleşen açık yanlış yok", systemImage: "magnifyingglass",
                                           description: Text(shown.resolved.isEmpty ? "Aramayı ya da kaynak süzgecini değiştir."
                                                                                    : "Eşleşenler aşağıda, Çözülenler'de."))
                }
                ForEach(shown.open) { entry in MistakeRow(entry: entry) }
                if !shown.resolved.isEmpty {
                    Section {
                        DisclosureGroup("Çözülenler (\(shown.resolved.count))", isExpanded: $showResolved) {
                            ForEach(shown.resolved) { entry in MistakeRow(entry: entry) }
                        }
                    }
                }
            }
            .navigationTitle("Yanlış defteri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Kaynak", selection: $group) {
                            ForEach(MistakeBook.Group.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        Label("Kaynak süzgeci", systemImage: group == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityValue(group.title)
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Ekle", systemImage: "plus") { showAdd = true } }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Soru, cevap ya da bölüm ara")
            .sheet(isPresented: $showAdd) { MistakeEditor() }
            .sheet(item: $practiceRound) { MistakePractice(ids: $0.ids) }
            .debugNarrowScreen()
        }
    }
}

private struct MistakeRow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Bindable var entry: MistakeEntry
    @State private var expanded = false
    /// Video dersinden gelen yanlış: ders, konunun anlatıldığı dakikada açılır.
    @State private var videoLesson: VideoLessonTarget?

    private struct VideoLessonTarget: Identifiable { var id: UUID }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.question).font(.subheadline.weight(.semibold)).lineLimit(expanded ? nil : 2)
                // Dar ekranda yan yana sığmayan cevaplar alt alta gelir (kapalıyken ikişer satır), kesilmez.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { mine; if expanded { correct } }.lineLimit(1)
                    VStack(alignment: .leading, spacing: 2) { mine; if expanded { correct } }.lineLimit(expanded ? nil : 2)
                }
                .font(.caption)
                Text(MistakeBook.sourceLine(source: entry.source, episodeTitle: entry.episodeTitle))
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(expanded ? "Ayrıntıyı gizlemek için çift dokun" : "Ayrıntı için çift dokun")
            .accessibilityAction { toggleDetails() }
            if expanded {
                if !entry.why.isEmpty { Text(entry.why).font(.caption).foregroundStyle(.secondary) }
                Group {
                    if entry.source == "video" || entry.source == "confused" {
                        Button("Videoda aç", systemImage: "play.rectangle") { openVideo() }
                    } else if let time = entry.podcastTime, let id = entry.episodeID {
                        // #24: konunun anlatıldığı ana git ve çal.
                        Button(ListenAnchor.label(time), systemImage: "headphones") {
                            dismiss()
                            app.open(id, at: time, play: true)
                        }
                    } else if !entry.episodeTitle.isEmpty, let id = entry.episodeID {
                        Button("Bölümü aç", systemImage: "play.circle") {
                            dismiss()
                            app.selectedTab = .library
                            app.pendingOpenEpisode = id
                        }
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                Text(MistakeRemediationStore.shared.record(for: entry).status(resolved: entry.resolved)).font(.caption).foregroundStyle(.secondary)
                HStack {
                    // Kaydırma hareketini bilmeyen de çözüldü diyebilsin.
                    Button {
                        toggleResolved()
                    } label: {
                        Label(entry.resolved ? "Geri al" : "Çözüldü işaretle", systemImage: entry.resolved ? "arrow.uturn.left" : "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 30)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    Spacer()
                    Text("\(entry.reviewedCount)× deneme").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { toggleDetails() }
        .sheet(item: $videoLesson) { target in VideoLibraryView(openLesson: target.id) }
        .swipeActions(edge: .leading) {
            Button(entry.resolved ? "Geri al" : "Çözüldü işaretle", systemImage: entry.resolved ? "arrow.uturn.left" : "checkmark") { toggleResolved() }
                .tint(.green)
        }
        .swipeActions { Button("Sil", role: .destructive) { context.delete(entry); try? context.save() } }
    }

    @ViewBuilder private var mine: some View {
        if !entry.myAnswer.isEmpty {
            Label(entry.myAnswer, systemImage: "xmark").foregroundStyle(.red)
                .accessibilityLabel("Benim cevabım: \(entry.myAnswer)")
        }
    }

    private var correct: some View {
        Label(entry.correctAnswer, systemImage: "checkmark").foregroundStyle(.green)
            .accessibilityLabel("Doğru cevap: \(entry.correctAnswer)")
    }

    private func toggleDetails() {
        if !expanded, !MistakeRemediationStore.shared.expose(entry) { return }
        withAnimation { expanded.toggle() }
    }

    private func toggleResolved() {
        let resolved = !entry.resolved
        guard MistakeRemediationStore.shared.mark(entry, resolved: resolved) else { return }
        withAnimation { entry.resolved = resolved }
        try? context.save()
    }

    private func openVideo() {
        guard let id = entry.episodeID,
              let lesson = try? context.fetch(FetchDescriptor<VideoLesson>(predicate: #Predicate { $0.id == id })).first else { return }
        if let time = entry.videoTime { lesson.lastPosition = max(0, time - 3); try? context.save() }
        videoLesson = VideoLessonTarget(id: id)
    }
}

/// Elle ekleme: soru + doğru cevap (+ fotoğraf, isteğe bağlı OCR).
struct MistakeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Course.createdAt) private var courses: [Course]
    @State private var question = ""
    @State private var myAnswer = ""
    @State private var correct = ""
    @State private var why = ""
    @State private var courseID: UUID?
    @State private var photo: PhotosPickerItem?
    @State private var reading = false
    /// Fotoğraf okunamadıysa nedenini söyleyen not (yeni fotoğraf seçilince silinir).
    @State private var readNote: String?

    private var trimmedQuestion: String { question.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedCorrect: String { correct.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasDraft: Bool { !(question + myAnswer + correct + why).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Soru") {
                    TextField("Soru metni", text: $question, axis: .vertical).lineLimit(3...8)
                    let isReading = reading
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label(isReading ? "Okunuyor…" : "Fotoğraftan oku", systemImage: "text.viewfinder")
                    }
                    .disabled(reading)
                    if let readNote {
                        Label(readNote, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    }
                }
                Section("Cevaplar") {
                    TextField("Benim cevabım", text: $myAnswer)
                    TextField("Doğru cevap", text: $correct)
                    TextField("Neden yanlış yaptım?", text: $why, axis: .vertical).lineLimit(2...5)
                }
                if !courses.isEmpty {
                    Picker("Ders", selection: $courseID) {
                        Text("—").tag(UUID?.none)
                        ForEach(courses) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            }
            .navigationTitle("Yanlış ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        context.insert(MistakeEntry(question: trimmedQuestion, myAnswer: myAnswer, correctAnswer: trimmedCorrect, why: why,
                                                    source: "manual", courseID: courseID))
                        try? context.save()
                        dismiss()
                    }
                    .disabled(trimmedQuestion.isEmpty || trimmedCorrect.isEmpty)
                }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                reading = true
                readNote = nil
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let text = await TextReader.read(data)
                        if text.isEmpty {
                            readNote = "Fotoğrafta okunabilir yazı bulunamadı. Daha yakından ve düz çekip tekrar dene."
                        } else {
                            question = TextReader.appended(text, to: question)
                        }
                    } else {
                        readNote = "Fotoğraf açılamadı. Başka bir fotoğrafla tekrar dene."
                    }
                    reading = false
                    photo = nil
                }
            }
            // Aşağı çekince yazılanlar onaysız kaybolmasın; çıkış için "Vazgeç" var.
            .interactiveDismissDisabled(hasDraft)
        }
    }
}

/// Cihazda OCR (Vision) — fotoğraftan soru metni.
nonisolated enum TextReader {
    @concurrent
    static func read(_ data: Data) async -> String {
        assemble(await lines(data).map(\.text))
    }

    /// Okunan satırlar ve kutuları (yönü düzeltilmiş görselde, 0…1). Görsel veri olarak verilir: Vision EXIF yönünü
    /// kendisi okur (dik çekilmiş fotoğraf yatık okunmasın); kutu, yönün uygulandığını sınamaya da yarar.
    @concurrent
    static func lines(_ data: Data) async -> [(text: String, box: CGRect)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["tr-TR", "en-US"]
        try? VNImageRequestHandler(data: data, options: [:]).perform([request])
        return (request.results ?? []).compactMap { line in line.topCandidates(1).first.map { (text: $0.string, box: line.boundingBox) } }
    }

    /// Okunan satırlar ayrı satırlarda kalır (soru kökü ve şıklar tek paragraf olmasın); boş satırlar atılır.
    static func assemble(_ lines: [String]) -> String {
        lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Elle yazılmış soru silinmez: okunan metin sonuna yeni satırla eklenir.
    static func appended(_ text: String, to question: String) -> String {
        let current = question.trimmingCharacters(in: .whitespacesAndNewlines)
        return current.isEmpty ? text : current + "\n" + text
    }
}

/// A response is committed before the answer appears. Open responses remain self-assessments.
struct MistakePractice: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var all: [MistakeEntry]
    let ids: [UUID]
    private var entries: [MistakeEntry] { ids.compactMap { id in all.first { $0.id == id } } }
    @State private var ledger = MistakeRemediationStore.shared
    @State private var index = 0
    @State private var revealed = false
    @State private var known = 0
    @State private var solved = 0
    @State private var answer = ""
    @State private var selected: Int?
    @State private var assisted: Bool?
    @State private var sameConcept = false
    @State private var skipped = false
    @State private var attemptID = UUID().uuidString
    @State private var started = Date.now
    @State private var submittedAt: Date?
    @State private var exposureBaseline: Date?
    @State private var activePrompt: Prompt?
    @State private var error: String?
    private struct Prompt {
        var text: String; var expected: String; var explanation: String
        var key: String; var rule: MistakeRemediation.ClosedAnswer?; var transfer: Bool
    }
    private func prompt(_ entry: MistakeEntry) -> Prompt {
        let record = ledger.record(for: entry)
        if record.retention != nil, Date.now.timeIntervalSince(record.lastExposure) >= MistakeRemediation.delay,
           let episodeID = entry.episodeID, let chapter = entry.chapterIndex,
           let episode = try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.id == episodeID })).first,
           let item = episode.study?.quiz.first(where: {
               $0.chapterIndex == chapter && $0.verified != false && MistakeRemediation.ClosedAnswer.make($0) != nil
                   && MistakeRemediation.key(question: $0.question, answer: QuestionKind.expectedAnswer($0)) != record.originalKey
           }) {
            return Prompt(text: item.question, expected: QuestionKind.expectedAnswer(item), explanation: item.explanation,
                          key: MistakeRemediation.key(question: item.question, answer: QuestionKind.expectedAnswer(item)),
                          rule: MistakeRemediation.ClosedAnswer.make(item), transfer: true)
        }
        return Prompt(text: entry.question, expected: entry.correctAnswer, explanation: entry.why,
                      key: record.originalKey, rule: record.rule, transfer: false)
    }
    var body: some View {
        NavigationStack {
            let round = entries
            Group {
                if let entry = round[safe: index] {
                    let task = activePrompt ?? prompt(entry)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("\(index + 1) / \(round.count) · " + (task.transfer ? "Aynı bölümden farklı soru" : "Aynı soruyu yeniden deneme")).font(.caption).foregroundStyle(.secondary)
                            Text(task.text).font(.title3.weight(.semibold))
                            if !revealed {
                                if let rule = task.rule {
                                    ForEach(rule.options.indices, id: \.self) { option in
                                        Button { selected = option; answer = rule.options[option] } label: {
                                            HStack { Image(systemName: selected == option ? "largecircle.fill.circle" : "circle"); Text(rule.options[option]); Spacer() }
                                        }.buttonStyle(.bordered)
                                    }
                                } else {
                                    TextField("Cevabı görmeden kendi çözümünü yaz", text: $answer, axis: .vertical).lineLimit(3...10).textFieldStyle(.roundedBorder)
                                    Text("Açık yanıtın otomatik doğru sayılmaz. Çözümü görünce özdeğerlendirmeni ayrıca kaydedebilirsin.").font(.caption).foregroundStyle(.secondary)
                                }
                                Picker("Yardım durumu", selection: $assisted) {
                                    Text("Seç").tag(Bool?.none)
                                    Text("Yardımsız denedim").tag(Optional(false))
                                    Text("Not veya ipucu kullandım").tag(Optional(true))
                                }
                                if task.transfer {
                                    Toggle("Bu sorunun önceki yanlışla aynı kavramı ölçtüğünü eşleştirdim", isOn: $sameConcept)
                                    Text("Aynı bölümde olmak aynı kazanım anlamına gelmez. Eşleştirme yapmazsan sonuç yalnız farklı soru denemesi olarak tutulur.").font(.caption).foregroundStyle(.secondary)
                                }
                            } else {
                                Text(task.expected).font(.headline).foregroundStyle(.green)
                                if !answer.isEmpty { Text("Bu denemendeki cevap: " + answer).font(.callout) }
                                if !task.explanation.isEmpty { Text(task.explanation).font(.subheadline).foregroundStyle(.secondary) }
                                Text(ledger.record(for: entry).status(resolved: entry.resolved)).font(.caption).foregroundStyle(.secondary)
                            }
                            if let error = error ?? ledger.error { Text(error).foregroundStyle(.red) }
                        }.padding()
                    }.id(index).safeAreaInset(edge: .bottom) { buttons(entry, task: task) }
                } else {
                    VStack(spacing: 12) {
                        Text("Tur tamamlandı").font(.title2.bold())
                        Text("\(known) anahtarla eşleşen cevap · \(solved) gecikmeli tekrar ve farklı soru başarısı")
                        Text("Özdeğerlendirme ve hemen tekrarlanan cevaplar, hatanın giderildiğini kanıtlamaz. Gecikmeli deneme en az 24 saat sonra yapılır.").font(.caption).foregroundStyle(.secondary)
                        Button("Tamam") { dismiss() }.buttonStyle(.borderedProminent)
                    }.multilineTextAlignment(.center).padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.navigationTitle("Yanlışları çöz").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }.debugNarrowScreen()
        }
    }
    private func buttons(_ entry: MistakeEntry, task: Prompt) -> some View {
        Group {
            if revealed {
                if task.rule == nil {
                    HStack {
                        Button("Özdeğerlendirme: eksik") { complete(entry, task: task, selfReported: false) }.buttonStyle(.bordered)
                        Button("Özdeğerlendirme: anladım") { complete(entry, task: task, selfReported: true) }.buttonStyle(.borderedProminent)
                    }
                } else { Button("Denemeyi kaydet ve ilerle") { complete(entry, task: task, selfReported: nil) }.buttonStyle(.borderedProminent) }
            } else {
                VStack {
                    Button("Cevabımı sabitle ve çözümü göster") { reveal(entry, task: task, skipping: false) }
                        .buttonStyle(.borderedProminent).disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || assisted == nil)
                    Button("Denemeden çözümü göster") { reveal(entry, task: task, skipping: true) }.font(.caption)
                }
            }
        }.controlSize(.large).padding().frame(maxWidth: .infinity).background(.bar)
    }
    private func reveal(_ entry: MistakeEntry, task: Prompt, skipping: Bool) {
        let now = Date.now, baseline = ledger.record(for: entry).lastExposure
        guard ledger.expose(entry, at: now) else { return }
        activePrompt = task; exposureBaseline = baseline; submittedAt = now
        skipped = skipping; if skipping { assisted = true }
        revealed = true
    }
    private func complete(_ entry: MistakeEntry, task: Prompt, selfReported: Bool?) {
        let record = ledger.record(for: entry), now = submittedAt ?? .now
        let attempt = MistakeRemediation.makeAttempt(id: attemptID, questionKey: task.key, response: answer,
            rule: task.rule, selected: selected, selfReported: selfReported, assisted: assisted, beforeReveal: !skipped, conceptMatched: task.transfer ? sameConcept : nil,
            lastExposure: exposureBaseline ?? record.lastExposure, now: now, seconds: now.timeIntervalSince(started))
        let alreadyRecorded = record.attempts.contains { $0.id == attempt.id }
        guard ledger.append(attempt, entry: entry) else { return }
        let updated = ledger.record(for: entry)
        if !alreadyRecorded {
            entry.reviewedCount += 1
            entry.correctStreak = attempt.correct == true && attempt.assisted == false ? entry.correctStreak + 1 : 0
            if updated.demonstrated, !entry.resolved { entry.resolved = true; solved += 1 }
        }
        do { try context.save() } catch { self.error = error.localizedDescription; return }
        if attempt.correct == true { known += 1 }
        LearningContinuity.record(source: .mistake, sourceID: entry.id.uuidString + "/" + attempt.id,
            topic: record.topic, correct: attempt.correct, assisted: attempt.assisted, seconds: attempt.seconds,
            detail: (task.transfer ? (sameConcept ? "Kullanıcının aynı kavrama eşleştirdiği farklı soru" : "Aynı bölümde farklı soru; kavram eşleşmesi kurulmadı") : "Aynı soru") + "; " + (attempt.delaySeconds >= MistakeRemediation.delay ? "gecikmeli deneme" : "yakın tekrar")
                + (selfReported.map { $0 ? "; özdeğerlendirme: anladım" : "; özdeğerlendirme: eksik" } ?? "") + ". " + answer,
            occurredAt: attempt.occurredAt, resourceID: entry.id.uuidString)
        revealed = false; answer = ""; selected = nil; assisted = nil; sameConcept = false; skipped = false; submittedAt = nil; exposureBaseline = nil; activePrompt = nil; error = nil
        attemptID = UUID().uuidString; started = .now
        withAnimation { index += 1 }
    }
}
