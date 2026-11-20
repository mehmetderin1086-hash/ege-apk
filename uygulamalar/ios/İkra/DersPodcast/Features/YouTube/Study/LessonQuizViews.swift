import SwiftData
import SwiftUI

// Bölüm quiz'i (#18), ÖSYM tarzı deneme (#23) ve ön bilgi kontrolü (#26).

/// Tek soru sayfası: başlık, soru, şıklar, (cevaplandıysa) açıklama ve ilerleme düğmesi.
private struct QuizQuestionPage: View {
    var header: String
    var index: Int
    var total: Int
    var question: StudyQuestion
    var selected: Int?
    var nextTitle: String
    var onSelect: (Int) -> Void
    var onNext: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ProgressView(value: Double(index + (selected == nil ? 0 : 1)), total: Double(max(1, total)))
                Text("Soru \(index + 1) / \(total) · \(header)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(question.question).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                QuizChoices(question: question, selected: selected, reveal: selected != nil, onSelect: onSelect)
                if selected != nil {
                    QuizExplanation(question: question, selected: selected)
                    Button(nextTitle, action: onNext).buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Bölüm quiz'i (#18)

struct ChapterQuizView: View {
    var context: LessonContext
    var chapter: Int?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(StudyPrefs.chapterQuizKey) private var autoQuiz = false
    @State private var phase: StudyPhase<[StudyQuestion]> = .idle
    @State private var answers: [Int: Int] = [:]
    @State private var current = 0
    @State private var finished = false
    /// Bu turda yanlış defterine yazılmış soru sıraları (yarıda kapatma + bitirme aynı soruyu iki kez işlemesin).
    @State private var recorded: Set<Int> = []
    @State private var scope: (title: String, range: ClipRange)?
    @State private var count = 3
    @State private var task: Task<Void, Never>?

    var body: some View {
        StudySheet(title: "Bölüm quiz'i") {
            switch phase {
            case .idle, .loading:
                StudyLoadingView(message: "Sorular hazırlanıyor…", onCancel: { dismiss() })
            case .failed(let message):
                StudyErrorView(message: message, retry: start)
            case .loaded(let questions):
                if finished { results(questions) } else { page(questions) }
            }
        }
        .task { if case .idle = phase { start() } }
        .onAppear { context.pausePlayback() }
        .onDisappear {
            task?.cancel()
            // Yarıda kapatıldı: cevabı açıklanmış yanlışlar kaybolmasın (cevaplanmayanlar sayılmaz).
            if !finished, let questions = phase.value { record(questions, includeUnanswered: false) }
        }
    }

    private func page(_ questions: [StudyQuestion]) -> some View {
        QuizQuestionPage(header: scope?.title ?? "", index: current, total: questions.count, question: questions[current],
                         selected: answers[current], nextTitle: current + 1 < questions.count ? "Sonraki soru" : "Bitir",
                         onSelect: { answers[current] = $0 },
                         onNext: {
                             if current + 1 < questions.count { withAnimation { current += 1 } } else { finish(questions) }
                         })
    }

    private func results(_ questions: [StudyQuestion]) -> some View {
        let correct = questions.indices.filter { answers[$0] == questions[$0].answer }.count
        let wrong = questions.indices.filter { answers[$0] != questions[$0].answer }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 4) {
                    Text("\(correct) / \(questions.count)").font(.system(size: 44, weight: .bold, design: .rounded))
                    Text(correct == questions.count ? "Hepsi doğru, devam!" : "doğru cevap").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                if !wrong.isEmpty {
                    Text("Yanlışların").font(.headline)
                    ForEach(wrong, id: \.self) { index in
                        let question = questions[index]
                        VStack(alignment: .leading, spacing: 6) {
                            Text(question.question).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                            Text("Doğru: \(question.choices[question.answer])").font(.callout).foregroundStyle(.green)
                            if !question.explanation.isEmpty {
                                Text(question.explanation).font(.caption).foregroundStyle(.secondary)
                            }
                            if let time = question.time {
                                Button("O anı izle (\(TranscriptFormat.timestamp(time)))", systemImage: "play.circle") {
                                    dismiss()
                                    context.resume(at: time)
                                }
                                .buttonStyle(.bordered)
                                .font(.footnote)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Text("Yanlışların yanlış defterine ve tekrar kartlarına eklendi.").font(.footnote).foregroundStyle(.secondary)
                }
                Button("Videoya devam et") {
                    dismiss()
                    context.player.play()
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("5 yeni soru daha") {
                    count = 5
                    start()
                }
                .buttonStyle(.bordered)
                Toggle("Bölüm bitince otomatik sor", isOn: $autoQuiz)
                    .font(.callout)
                Text("Açıkken video her bölümün sonunda durur ve 3 soru sorulur.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }

    private func start() {
        task?.cancel()
        let resolved = QuizScope.resolve(chapters: context.sortedChapters, chapter: chapter, end: context.contentEnd,
                                         currentTime: context.player.currentTime)
        scope = resolved
        let text = StudyText.lines(context.transcript.paragraphs, from: resolved.range.start, to: resolved.range.end, maxChars: 40_000)
        guard text.count >= 20 else {
            phase = .failed("Bu bölümün metni çok kısa; soru hazırlanamadı.")
            return
        }
        phase = .loading
        answers = [:]
        current = 0
        finished = false
        recorded = []
        let wanted = count
        let request = StudyQuizRequest(title: [context.lesson.title, resolved.title].filter { !$0.isEmpty }.joined(separator: " — "),
                                       text: text, count: wanted, style: "mcq")
        task = Task {
            do {
                let result = try await APIClient.shared.studyQuiz(request)
                try Task.checkCancellation()
                let clean = StudyQuizRules.sanitize(result, limit: wanted)
                phase = clean.isEmpty ? .failed("Geçerli soru hazırlanamadı. Lütfen tekrar dene.") : .loaded(clean)
            } catch {
                if let message = StudyError.message(error) { phase = .failed(message) }
            }
        }
    }

    private func finish(_ questions: [StudyQuestion]) {
        finished = true
        record(questions, includeUnanswered: true)
    }

    /// Yanlışları yanlış defterine ve tekrar destesine yazar; tur içinde her soru bir kez işlenir.
    private func record(_ questions: [StudyQuestion], includeUnanswered: Bool) {
        guard context.lesson.modelContext != nil, let scope else { return }
        let pending = StudyQuizRules.missed(questions, answers: answers, includeUnanswered: includeUnanswered).filter { !recorded.contains($0) }
        guard !pending.isEmpty else { return }
        let paragraphs = context.transcript.paragraphs
        for index in pending {
            let question = questions[index]
            let mine = answers[index].flatMap { question.choices.indices.contains($0) ? question.choices[$0] : nil } ?? ""
            let clip = ClipPlanner.cardClip(at: question.time ?? scope.range.start, paragraphs: paragraphs)
            LessonStudy.recordWrong(question, myAnswer: mine, lesson: context.lesson, fallbackTime: scope.range.start,
                                    clip: clip, context: modelContext)
            recorded.insert(index)
        }
    }
}

// MARK: - ÖSYM tarzı deneme (#23)

struct LessonExamView: View {
    var context: LessonContext

    private enum Stage { case setup, loading, running, finished }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var stage: Stage = .setup
    @State private var count = 15
    @State private var minutes = 25
    @State private var questions: [StudyQuestion] = []
    @State private var answers: [Int: Int] = [:]
    @State private var current = 0
    @State private var deadline: Date?
    @State private var startedAt: Date?
    @State private var elapsed: TimeInterval = 0
    @State private var errorText: String?
    @State private var weakTopics: [WeakTopic] = []
    @State private var task: Task<Void, Never>?
    @State private var confirmExit = false
    @State private var confirmBlank = false
    /// Bu dersin önceki denemeleri (en yeni başta).
    @State private var history: [ExamRecord] = []
    /// Az önce biten denemenin kaydı ve ondan önceki (sonuç ekranındaki karşılaştırma için).
    @State private var latestRecord: ExamRecord?
    @State private var previousRecord: ExamRecord?

    private static let shownHistory = 5

    var body: some View {
        // Sınav sürerken sayfa aşağı çekilerek kapanmaz; "Kapat" onay ister (cevaplar ve sonuç kaybolmasın).
        StudySheet(title: "ÖSYM tarzı deneme", guardDismiss: stage == .running,
                   onClose: { if stage == .running { confirmExit = true } else { dismiss() } }) {
            Group {
                switch stage {
                case .setup: setup
                case .loading: StudyLoadingView(message: "\(count) soruluk deneme hazırlanıyor…", onCancel: { cancelLoading() })
                case .running: running
                case .finished: results
                }
            }
            .toolbar {
                if stage == .running, let deadline {
                    ToolbarItem(placement: .topBarTrailing) {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            let left = max(0, deadline.timeIntervalSinceNow)
                            Text(left.clockText).font(.subheadline.monospacedDigit().bold())
                                .foregroundStyle(left < 60 ? .red : .primary)
                        }
                    }
                }
            }
        }
        .onAppear {
            context.pausePlayback()
            history = ExamHistory.load(lesson: context.lesson.id)
        }
        .onDisappear { task?.cancel() }
        .task(id: deadline) {
            guard let deadline, stage == .running else { return }
            let wait = deadline.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            if !Task.isCancelled, stage == .running { finish() }
        }
        #if DEBUG
        // Simülatörde sunucusuz denetim: -examDemo=N, 15 hazır soruyla süren sınavı açar ve N. soruya geçer.
        .task {
            guard stage == .setup, let target = DebugArg.value("examDemo").flatMap({ Int($0) }) else { return }
            begin((1...15).map { number in
                StudyQuestion(question: "Deneme sorusu \(number): aşağıdaki ifadelerden hangisi doğrudur?",
                              choices: (0..<5).map { "Seçenek \(StudyQuizRules.letter($0))" }, answer: number % 5)
            })
            answers = [0: 1, 1: 2, 3: 0]
            // Gezgin çizildikten sonra geçilir ki şeridin geçerli soruyu ortalaması da görülsün.
            try? await Task.sleep(for: .seconds(0.8))
            if stage == .running { current = min(max(target, 1), questions.count) - 1 }
        }
        #endif
        .confirmationDialog("Deneme bitmedi", isPresented: $confirmExit, titleVisibility: .visible) {
            Button("Bitir ve sonucu gör") { finish() }
            Button("Çık (cevaplar silinir)", role: .destructive) { dismiss() }
            Button("Devam et", role: .cancel) {}
        } message: {
            Text("\(answers.count) / \(questions.count) soru cevaplandı. Çıkarsan cevapların ve sonucun kaydedilmez.")
        }
    }

    // MARK: Kurulum

    private var setup: some View {
        Form {
            Section {
                Stepper("Soru sayısı: \(count)", value: $count, in: 10...20, step: 5)
                    .onChange(of: count) { _, value in minutes = max(5, Int((Double(value) * 1.5 / 5).rounded()) * 5) }
                Stepper("Süre: \(minutes) dk", value: $minutes, in: 5...90, step: 5)
            } footer: {
                Text("Sorular dersin tamamından ÖSYM tarzında (5 şık) hazırlanır. Net = doğru − yanlış / 4; boşlar sayılmaz.")
            }
            if let errorText {
                Section { Text(errorText).foregroundStyle(.red).font(.callout) }
            }
            Section {
                Button("Denemeyi başlat") { start() }
                    .frame(maxWidth: .infinity)
                    .font(.headline)
            }
            if !history.isEmpty {
                Section {
                    ForEach(history.prefix(Self.shownHistory)) { record in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ExamHistory.title(record)).font(.callout.weight(.semibold))
                            Text("\(ExamHistory.detail(record)) · \(record.date.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(ExamHistory.title(record)); \(record.correct) doğru, \(record.wrong) yanlış, \(record.blank) boş; \(record.date.formatted(.relative(presentation: .named)))")
                    }
                } header: {
                    Text("Önceki denemeler")
                } footer: {
                    if history.count > Self.shownHistory { Text("Son \(Self.shownHistory) deneme gösteriliyor (toplam \(history.count)).") }
                }
            }
        }
    }

    private func start() {
        task?.cancel()
        errorText = nil
        let text = StudyText.lessonText(context.transcript, maxChars: 120_000)
        guard text.count >= 20 else {
            errorText = "Dersin metni çok kısa; deneme hazırlanamadı."
            return
        }
        stage = .loading
        let request = StudyQuizRequest(title: context.lesson.title, text: text, count: count, style: "osym")
        let wanted = count
        task = Task {
            do {
                let result = try await APIClient.shared.studyQuiz(request)
                try Task.checkCancellation()
                let clean = StudyQuizRules.sanitize(result, limit: wanted)
                guard !clean.isEmpty else {
                    errorText = "Geçerli soru hazırlanamadı. Lütfen tekrar dene."
                    stage = .setup
                    return
                }
                begin(clean)
            } catch {
                errorText = StudyError.message(error)
                stage = .setup
            }
        }
    }

    private func begin(_ clean: [StudyQuestion]) {
        questions = clean
        answers = [:]
        current = 0
        startedAt = .now
        deadline = .now.addingTimeInterval(Double(minutes) * 60)
        stage = .running
    }

    private func cancelLoading() {
        task?.cancel()
        stage = .setup
    }

    // MARK: Sınav

    private var running: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    // Daire 30 pt kalır; dokunma hedefi 44 pt (hücreler bitişik).
                    HStack(spacing: 0) {
                        ForEach(questions.indices, id: \.self) { index in
                            Button { current = index } label: {
                                Text("\(index + 1)")
                                    .font(.caption.bold().monospacedDigit())
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(index == current ? Color.accentColor
                                                               : answers[index] != nil ? Color.accentColor.opacity(0.25) : Color(.secondarySystemFill)))
                                    .foregroundStyle(index == current ? Color.white : Color.primary)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Soru \(index + 1)\(answers[index] != nil ? ", cevaplandı" : "")")
                            .accessibilityAddTraits(index == current ? .isSelected : [])
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 9).padding(.vertical, 1)
                }
                // Önceki/Sonraki ile ilerleyince geçerli soru şeridin dışında kalmasın.
                .onChange(of: current) { _, value in withAnimation { proxy.scrollTo(value, anchor: .center) } }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ProgressView(value: Double(answers.count), total: Double(max(1, questions.count)))
                    Text("Soru \(current + 1) / \(questions.count)").font(.caption).foregroundStyle(.secondary)
                    Text(questions[current].question).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    QuizChoices(question: questions[current], selected: answers[current], reveal: false) { answers[current] = $0 }
                    navigation
                }
                .padding(16)
            }
        }
        .confirmationDialog("\(ExamNav.unanswered(count: questions.count, answers: answers).count) soru boş",
                            isPresented: $confirmBlank, titleVisibility: .visible) {
            Button("Boş soruya git") {
                if let next = ExamNav.nextUnanswered(after: current, count: questions.count, answers: answers) { current = next }
            }
            Button("Yine de bitir") { finish() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Boş sorular nete sayılmaz; yanlışlarla birlikte yanlış defterine eklenir.")
        }
    }

    /// Önceki / Bitir / Sonraki: sığmazsa (büyük yazı) "Bitir" alt satıra iner. Her sorudan bitirilebilir.
    private var navigation: some View {
        let isLast = current + 1 >= questions.count
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                previousButton
                Spacer(minLength: 4)
                finishButton(prominent: isLast)
                if !isLast { nextButton }
            }
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    previousButton
                    Spacer(minLength: 4)
                    if !isLast { nextButton }
                }
                finishButton(prominent: isLast)
            }
        }
    }

    private var previousButton: some View {
        Button { current = max(0, current - 1) } label: {
            Text("Önceki").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .disabled(current == 0)
    }

    private var nextButton: some View {
        Button("Sonraki") { current = min(questions.count - 1, current + 1) }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
    }

    @ViewBuilder
    private func finishButton(prominent: Bool) -> some View {
        if prominent {
            Button("Denemeyi bitir") { requestFinish() }.buttonStyle(.borderedProminent).controlSize(.large)
        } else {
            Button("Bitir") { requestFinish() }.buttonStyle(.bordered).controlSize(.large)
        }
    }

    /// Boş soru varsa bitirmeden önce sorar.
    private func requestFinish() {
        if ExamNav.unanswered(count: questions.count, answers: answers).isEmpty { finish() } else { confirmBlank = true }
    }

    private func finish() {
        guard stage == .running else { return }
        confirmExit = false
        confirmBlank = false
        elapsed = startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        deadline = nil
        weakTopics = ExamAnalysis.weakTopics(questions, answers: answers, chapters: context.sortedChapters)
        latestRecord = nil
        previousRecord = nil
        stage = .finished
        guard context.lesson.modelContext != nil else { return }
        // Hiç cevaplanmamış deneme geçmişe yazılmaz (sonraki karşılaştırmayı yanıltırdı).
        if !answers.isEmpty {
            let score = ExamScore.compute(questions, answers: answers)
            let record = ExamRecord(date: .now, questions: questions.count, correct: score.correct, wrong: score.wrong,
                                    blank: score.blank, seconds: elapsed)
            previousRecord = history.first
            latestRecord = record
            history = ExamHistory.appending(record, to: history)
            ExamHistory.save(history, lesson: context.lesson.id)
        }
        let paragraphs = context.transcript.paragraphs
        for (index, question) in questions.enumerated() where answers[index] != question.answer {
            let mine = answers[index].flatMap { question.choices.indices.contains($0) ? question.choices[$0] : nil } ?? "Boş"
            let clip = question.time.map { ClipPlanner.cardClip(at: $0, paragraphs: paragraphs) }
            LessonStudy.recordWrong(question, myAnswer: mine, lesson: context.lesson, fallbackTime: nil, clip: clip, context: modelContext)
        }
    }

    // MARK: Sonuç

    private var results: some View {
        let score = ExamScore.compute(questions, answers: answers)
        let missed = questions.indices.filter { answers[$0] != questions[$0].answer }
        return List {
            Section {
                VStack(spacing: 6) {
                    Text("Net \(ExamScore.netText(score.net))").font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("\(score.correct) doğru · \(score.wrong) yanlış · \(score.blank) boş")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if let latestRecord, let delta = ExamHistory.delta(latest: latestRecord, previous: previousRecord),
                       let text = ExamHistory.deltaText(latest: latestRecord, previous: previousRecord) {
                        // Yön yalnız renkle verilmez: ok simgesi ve işaretli metin.
                        Label("Önceki denemeye göre: \(text)",
                              systemImage: abs(delta) < 0.005 ? "equal" : delta > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(abs(delta) < 0.005 ? Color.secondary : delta > 0 ? Color.green : Color.orange)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Süre: \(elapsed.clockText) / \(minutes) dk").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
            if !weakTopics.isEmpty {
                Section("Zayıf konular") {
                    ForEach(weakTopics, id: \.self) { topic in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(topic.title).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                                Text("\(topic.wrong) / \(topic.total) soruda hata").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            // Konunun anı bilinmiyorsa (0 ya da yok) "İzle" gösterilmez.
                            if topic.time > 0 {
                                Button("İzle") {
                                    dismiss()
                                    context.resume(at: topic.time)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            if !missed.isEmpty {
                Section {
                    ForEach(missed, id: \.self) { index in
                        let question = questions[index]
                        VStack(alignment: .leading, spacing: 4) {
                            Text(question.question).font(.callout.bold()).fixedSize(horizontal: false, vertical: true)
                            Text("Doğru: \(StudyQuizRules.letter(question.answer)) · \(question.choices[question.answer])")
                                .font(.caption).foregroundStyle(.green)
                            if let selected = answers[index], question.choices.indices.contains(selected) {
                                Text("Senin cevabın: \(StudyQuizRules.letter(selected)) · \(question.choices[selected])")
                                    .font(.caption).foregroundStyle(.red)
                            }
                            if !question.explanation.isEmpty {
                                Text(question.explanation).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Yanlışlar ve boşlar")
                } footer: {
                    Text("Yanlış defterine ve tekrar destesine eklendi.")
                }
            }
            Section {
                Button("Yeni deneme") {
                    stage = .setup
                    questions = []
                }
            }
        }
    }
}

// MARK: - Ön bilgi kontrolü (#26)

struct PrereqView: View {
    var context: LessonContext

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var phase: StudyPhase<StudyPrereqResponse> = .idle
    @State private var answers: [Int: Int] = [:]
    @State private var current = 0
    @State private var finished = false
    /// Bu turda yanlış defterine yazılmış soru sıraları.
    @State private var recorded: Set<Int> = []
    @State private var task: Task<Void, Never>?

    var body: some View {
        StudySheet(title: "Ön bilgi kontrolü") {
            switch phase {
            case .idle, .loading:
                // İptal edilen istek durumu değiştirmez (StudyError iptali yutar); sayfa kapanmazsa çark sonsuza dek döner.
                StudyLoadingView(message: "Ön koşullar belirleniyor…", onCancel: { task?.cancel(); dismiss() })
            case .failed(let message):
                StudyErrorView(message: message, retry: load)
            case .loaded(let response):
                content(response)
            }
        }
        .task { if case .idle = phase { load() } }
        .onAppear { context.pausePlayback() }
        .onDisappear {
            task?.cancel()
            // Yoklama yarıda kapatıldı: cevabı açıklanmış yanlışlar kaybolmasın.
            if !finished, let response = phase.value { record(sanitized(response), includeUnanswered: false) }
        }
    }

    /// Yoklamada gösterilen sorular (geçersizler atılmış); sıra numaraları `answers` ile aynı diziye göredir.
    private func sanitized(_ response: StudyPrereqResponse) -> [StudyQuestion] {
        response.questions.compactMap { StudyQuizRules.sanitize($0) }
    }

    private func content(_ response: StudyPrereqResponse) -> some View {
        let questions = sanitized(response)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Bu dersi rahat anlamak için önceden bilmen gerekenler:").font(.subheadline).foregroundStyle(.secondary)
                ForEach(Array(response.prerequisites.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.callout.weight(.semibold))
                        if !item.why.isEmpty { Text(item.why).font(.caption).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if !questions.isEmpty {
                    Divider()
                    if finished {
                        summary(questions)
                    } else {
                        let question = questions[min(current, questions.count - 1)]
                        Text("Kısa yoklama · \(current + 1) / \(questions.count)").font(.headline)
                        Text(question.question).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        QuizChoices(question: question, selected: answers[current], reveal: answers[current] != nil) { answers[current] = $0 }
                        if answers[current] != nil {
                            QuizExplanation(question: question, selected: answers[current])
                            Button(current + 1 < questions.count ? "Sonraki soru" : "Bitir") {
                                if current + 1 < questions.count { current += 1 } else { finish(questions) }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func summary(_ questions: [StudyQuestion]) -> some View {
        let correct = questions.indices.filter { answers[$0] == questions[$0].answer }.count
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(correct) / \(questions.count) doğru").font(.title2.bold())
            Text(correct == questions.count
                 ? "Ön bilgin yerinde, derse rahatça devam edebilirsin."
                 : "Eksik kalan ön bilgiler yanlış defterine ve tekrar kartlarına eklendi; derse başlamadan göz at.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Yeniden dene") {
                answers = [:]
                current = 0
                finished = false
                recorded = []
            }
            .buttonStyle(.bordered)
        }
    }

    private func finish(_ questions: [StudyQuestion]) {
        finished = true
        record(questions, includeUnanswered: true)
    }

    /// Yanlışları yanlış defterine ve tekrar destesine yazar; tur içinde her soru bir kez işlenir.
    private func record(_ questions: [StudyQuestion], includeUnanswered: Bool) {
        guard context.lesson.modelContext != nil else { return }
        let pending = StudyQuizRules.missed(questions, answers: answers, includeUnanswered: includeUnanswered).filter { !recorded.contains($0) }
        for index in pending {
            let question = questions[index]
            let mine = answers[index].flatMap { question.choices.indices.contains($0) ? question.choices[$0] : nil } ?? ""
            LessonStudy.recordWrong(question, myAnswer: mine, lesson: context.lesson, fallbackTime: nil, clip: nil, context: modelContext)
            recorded.insert(index)
        }
    }

    private func load() {
        task?.cancel()
        let notes = context.transcript.notes
        var summary = StudyText.clean(notes?.summary ?? "")
        if summary.isEmpty {
            summary = StudyText.excerpt(context.transcript.paragraphs.prefix(12).map(\.text).joined(separator: " "), maxChars: 3000)
        }
        let request = StudyPrereqRequest(title: context.lesson.title, summary: String(summary.prefix(7500)),
                                         concepts: (notes?.concepts ?? []).prefix(60).map { String($0.name.prefix(200)) })
        guard !request.summary.isEmpty || !request.concepts.isEmpty else {
            phase = .failed("Ön bilgi için dersin özeti ya da kavramları gerekir; bu derste metin yok.")
            return
        }
        phase = .loading
        answers = [:]
        current = 0
        finished = false
        recorded = []
        task = Task {
            do {
                let response = try await APIClient.shared.studyPrereq(request)
                try Task.checkCancellation()
                phase = response.prerequisites.isEmpty && response.questions.isEmpty
                    ? .failed("Ön bilgi listesi hazırlanamadı. Lütfen tekrar dene.") : .loaded(response)
            } catch {
                if let message = StudyError.message(error) { phase = .failed(message) }
            }
        }
    }
}
