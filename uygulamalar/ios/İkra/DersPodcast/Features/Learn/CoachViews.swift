import SwiftData
import SwiftUI

// MARK: - Ortak parçalar

/// Kayıt düğmesi + canlı transkript.
struct RecordPanel: View {
    var recorder: SpeechRecorder
    var hint: String
    var onStop: (String) -> Void

    var body: some View {
        VStack(spacing: 14) {
            if !recorder.transcript.isEmpty {
                Text(recorder.transcript)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            }
            if let error = recorder.error {
                Text(error).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Button {
                // Kapanış sürerken (çift dokunma) yeni kayıt da ikinci durdurma da başlamaz.
                guard !recorder.isStopping else { return }
                Task {
                    if recorder.isRecording { onStop(await recorder.stop()) } else { await recorder.start() }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(recorder.isRecording ? AnyShapeStyle(Theme.warmGradient) : AnyShapeStyle(Theme.gradient))
                        .frame(width: 84, height: 84)
                        .scaleEffect(1 + CGFloat(recorder.level) * 0.35)
                        .animation(.easeOut(duration: 0.1), value: recorder.level)
                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(recorder.isStopping)
            .accessibilityLabel(recorder.isRecording ? "Kaydı bitir" : "Konuşmaya başla")
            Text(recorder.isStopping ? "Son sözcükler toparlanıyor…" : recorder.isRecording ? "Bitirince dokun" : hint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// Değerlendirme isteği hata verince: saklanan cevap yeniden kayıt yapmadan gönderilir (mikrofona dokunmak transkripti sıfırlar).
struct ResendAnswerPanel: View {
    var answer: String
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("“\(answer)”").font(.footnote).foregroundStyle(.secondary).lineLimit(3)
            Button("Aynı cevabı yeniden gönder", systemImage: "arrow.clockwise", action: action)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EvaluationCard: View {
    var evaluation: Evaluation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(verdictTitle, systemImage: verdictSymbol)
                    .font(.headline)
                    .foregroundStyle(verdictColor)
                Spacer()
                Text("\(evaluation.score)").font(.title2.bold().monospacedDigit()).foregroundStyle(verdictColor)
            }
            Text(evaluation.feedback).font(.body)
            if !evaluation.missing.isEmpty {
                Text("Eksik kalanlar").font(.subheadline.bold())
                ForEach(evaluation.missing, id: \.self) { Label($0, systemImage: "circle.dashed").font(.callout) }
            }
            if !evaluation.errors.isEmpty {
                Text("Hatalı noktalar").font(.subheadline.bold())
                ForEach(evaluation.errors, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange) }
            }
        }
        .padding(16)
        .background(verdictColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var verdictTitle: String {
        switch evaluation.verdict {
        case "dogru": "Doğru"
        case "kismen": "Kısmen doğru"
        default: "Tekrar etmekte fayda var"
        }
    }
    private var verdictSymbol: String { evaluation.verdict == "dogru" ? "checkmark.seal.fill" : evaluation.verdict == "kismen" ? "circle.lefthalf.filled" : "arrow.counterclockwise" }
    private var verdictColor: Color { evaluation.verdict == "dogru" ? .green : evaluation.verdict == "kismen" ? .orange : .red }
}

// MARK: - Sokratik sınama (öneri 8)

/// Bölüm bitince sunucu soru sorar (cihaz sesiyle), kullanıcı sesli cevaplar, sunucudaki model (Claude) değerlendirir.
struct SocraticView: View {
    var episode: Episode
    var limit: Int = 8
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = SpeechRecorder()
    @State private var index = 0
    @State private var evaluation: Evaluation?
    @State private var evaluating = false
    @State private var error: String?
    @State private var scores: [Int] = []
    @State private var speakQuestions = true
    /// Değerlendirmeye gönderilen son cevap; istek hata verirse yeniden gönderilebilsin diye başarıya dek saklanır.
    @State private var pendingAnswer: String?

    /// Ekran açılırken bir kez karıştırılır (yeniden çizimde sıra değişmesin).
    @State private var questions: [QuizItem] = []

    private var language: String { episode.settings?.language == .en ? "en-US" : "tr-TR" }

    var body: some View {
        NavigationStack {
            Group {
                if questions.isEmpty {
                    ContentUnavailableView("Soru yok", systemImage: "questionmark.circle",
                                           description: Text("Önce Çalış sekmesinden quiz oluştur; sorular oradan gelir."))
                } else if index >= questions.count {
                    summary
                } else {
                    questionView(questions[index])
                }
            }
            .navigationTitle("Sokratik sınama")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") {
                        recorder.cancel()
                        SpeechOut.shared.stop()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $speakQuestions) { Image(systemName: speakQuestions ? "speaker.wave.2.fill" : "speaker.slash") }
                        .toggleStyle(.button)
                        .accessibilityLabel("Soruları sesli oku")
                }
            }
        }
        .onAppear { if questions.isEmpty { questions = Array((episode.study?.quiz ?? []).filter { $0.verified != false }.shuffled().prefix(limit)) } }
        .task(id: index) {
            guard index < questions.count, speakQuestions else { return }
            await SpeechOut.shared.speak(questions[index].question, language: language)
        }
    }

    private func questionView(_ item: QuizItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Soru \(index + 1) / \(questions.count)").font(.caption.bold()).foregroundStyle(.secondary)
                SpokenText(text: item.question, speech: SpeechOut.shared, font: .title3.weight(.semibold))
                Text("Şıklara bakmadan, kendi cümlelerinle cevapla.").font(.footnote).foregroundStyle(.secondary)

                if let evaluation {
                    EvaluationCard(evaluation: evaluation)
                    Text("Doğru cevap: \(QuestionKind.expectedAnswer(item))").font(.callout.bold())
                    Button(index + 1 < questions.count ? "Sonraki soru" : "Sonucu gör") {
                        self.evaluation = nil
                        pendingAnswer = nil
                        index += 1
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else if evaluating {
                    HStack { ProgressView(); Text("Cevabın değerlendiriliyor…") }.frame(maxWidth: .infinity)
                } else {
                    if error != nil, let pendingAnswer {
                        ResendAnswerPanel(answer: pendingAnswer) {
                            recorder.cancel()
                            Task { await evaluate(item, answer: pendingAnswer) }
                        }
                    }
                    // Kayıt başlangıcı okumayı zaten durdurur (`SpeechRecorder.start`): soru okunurken de cevaplanabilir.
                    RecordPanel(recorder: recorder,
                                hint: SpeechOut.shared.isSpeaking ? "Soru okunuyor… beklemeden cevaplamak için dokun" : "Cevaplamak için dokun") { answer in
                        Task { await evaluate(item, answer: answer) }
                    }
                    .frame(maxWidth: .infinity)
                    Button("Bu soruyu atla") {
                        recorder.cancel()
                        SpeechOut.shared.stop()
                        pendingAnswer = nil
                        error = nil
                        index += 1
                    }
                    .frame(maxWidth: .infinity).font(.subheadline)
                }
                if let error { Text(error).foregroundStyle(.red).font(.callout) }
            }
            .padding(20)
        }
    }

    private var summary: some View {
        VStack(spacing: 14) {
            Spacer()
            let average = scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count
            Text("\(average)").font(.system(size: 64, weight: .bold, design: .rounded)).foregroundStyle(Theme.gradient)
            Text("ortalama puan · \(scores.count) cevap").foregroundStyle(.secondary)
            Text("Zorlandığın sorular tekrar destene eklendi.").font(.footnote).foregroundStyle(.secondary)
            Button("Baştan başla") { index = 0; scores = [] }.buttonStyle(.bordered)
            Spacer()
        }
    }

    private func evaluate(_ item: QuizItem, answer: String) async {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "Sesini duyamadım. Tekrar dene."
            return
        }
        pendingAnswer = trimmed
        evaluating = true
        error = nil
        defer { evaluating = false }
        let expected = "\(QuestionKind.expectedAnswer(item)) — \(item.explanation)"
        do {
            let result = try await APIClient.shared.evaluate(EvaluateRequest(
                mode: "answer", prompt: item.question, expected: expected,
                sourceNotes: String((episode.script?.sourceNotes ?? "").prefix(15_000)),
                response: String(trimmed.prefix(5000)), language: episode.settings?.language.rawValue ?? "tr"))
            evaluation = result
            pendingAnswer = nil
            scores.append(result.score)
            var entry = RecallLog.Entry(source: "socratic", question: item.question, correctIndex: item.answerIndex >= 0 ? item.answerIndex : nil,
                                        answerText: trimmed, isCorrect: result.verdict == "dogru", score: Double(result.score) / 100)
            entry.chapterIndex = item.chapterIndex
            RecallLog.record(entry, episode: episode, context: context)
            if result.verdict != "dogru" { ReviewDeck.addWrong(item, episode: episode, context: context) }
            if speakQuestions { await SpeechOut.shared.speak(result.feedback, language: language) }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Feynman modu (öneri 10)

struct FeynmanView: View {
    var episode: Episode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var recorder = SpeechRecorder()
    @State private var topic: String = ""
    @State private var evaluation: Evaluation?
    @State private var evaluating = false
    @State private var error: String?
    /// Değerlendirmeye gönderilen son anlatım; istek hata verirse yeniden gönderilebilsin diye başarıya dek saklanır.
    @State private var pendingAnswer: String?

    private var topics: [String] {
        let chapters = episode.timeline?.chapters.map(\.title) ?? episode.script?.chapters.map(\.title) ?? []
        return chapters + episode.concepts.map(\.name)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Bir konuyu, hiç bilmeyen birine anlatır gibi 1–2 dakika sesli anlat. Anlatımın belgeyle karşılaştırılıp eksik ve hatalı noktalar gösterilir.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("Konu", selection: $topic) {
                        ForEach(topics, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)

                    if let evaluation {
                        EvaluationCard(evaluation: evaluation)
                        if let follow = evaluation.followUp {
                            Label(follow, systemImage: "arrow.turn.down.right").font(.callout)
                        }
                        Button("Yeniden anlat") { self.evaluation = nil }.buttonStyle(.bordered)
                    } else if evaluating {
                        HStack { ProgressView(); Text("Anlatımın inceleniyor…") }.frame(maxWidth: .infinity)
                    } else {
                        if error != nil, let pendingAnswer {
                            ResendAnswerPanel(answer: pendingAnswer) {
                                recorder.cancel()
                                Task { await evaluate(pendingAnswer) }
                            }
                        }
                        RecordPanel(recorder: recorder, hint: "Anlatmaya başlamak için dokun") { text in
                            Task { await evaluate(text) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    if let error { Text(error).foregroundStyle(.red).font(.callout) }
                }
                .padding(20)
            }
            .navigationTitle("Feynman modu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { recorder.cancel(); dismiss() }
                }
            }
            .onAppear { if topic.isEmpty { topic = topics.first ?? "" } }
            // Saklanan anlatım eski konuya aittir: yeni konuyla yeniden gönderilmesin.
            .onChange(of: topic) { _, _ in pendingAnswer = nil }
        }
    }

    private func evaluate(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 20 else {
            error = "Anlatım çok kısa kaldı. Biraz daha ayrıntılı anlat."
            return
        }
        pendingAnswer = trimmed
        evaluating = true
        error = nil
        defer { evaluating = false }
        do {
            let result = try await APIClient.shared.evaluate(EvaluateRequest(
                mode: "explain", prompt: topic, expected: nil,
                sourceNotes: String((episode.script?.sourceNotes ?? "").prefix(15_000)),
                response: String(trimmed.prefix(5000)), language: episode.settings?.language.rawValue ?? "tr"))
            evaluation = result
            pendingAnswer = nil
            var entry = RecallLog.Entry(source: "feynman", question: "Anlat: \(topic)", answerText: trimmed,
                                        isCorrect: result.verdict == "dogru", score: Double(result.score) / 100)
            entry.chapterIndex = episode.timeline?.chapters.first { $0.title == topic }?.id
            entry.conceptKey = episode.concepts.contains { $0.name == topic } ? topic : nil
            RecallLog.record(entry, episode: episode, context: context)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Sesli kart tekrarı (öneri 9)

/// Ekrana bakmadan: kart okunur, düşünme payı, cevap okunur, "bildim / bilemedim / zor / kolay" denir.
struct VoiceReviewView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ReviewCard.due) private var cards: [ReviewCard]
    @State private var recorder = SpeechRecorder()
    @State private var session: [ReviewCard] = []
    @State private var index = 0
    @State private var phase = "Hazır"
    @State private var running = false
    @State private var loop: Task<Void, Never>?
    /// Ekran kilidi engelini bu oturum mu açtı (kapatırken başka ekranın ayarı ezilmesin).
    @State private var keepsAwake = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                if let card = session[safe: index] {
                    SpokenText(text: card.front, speech: SpeechOut.shared, font: .title3.weight(.semibold)).multilineTextAlignment(.center)
                    Text(phase).font(.subheadline).foregroundStyle(.secondary)
                    Text("\(index + 1) / \(session.count)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    if running {
                        HStack(spacing: 8) {
                            ForEach(ReviewGrade.allCases, id: \.self) { grade in
                                Button(grade.title) { apply(grade) }
                                    .buttonStyle(.bordered)
                                    .font(.caption)
                            }
                        }
                    }
                } else if session.isEmpty {
                    Image(systemName: "headphones").font(.system(size: 56)).foregroundStyle(Theme.gradient)
                    Text("\(cards.filter(\.isDue).count) kart hazır").font(.title2.bold())
                    Text("Kart okunur, 3 saniye düşünürsün, cevap okunur. Sonra \"bildim\", \"bilemedim\", \"zor\" ya da \"kolay\" de. Kulaklıkla yürürken bile çalışır.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                } else {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(.green)
                    Text("Sesli tekrar bitti").font(.title2.bold())
                }
                Spacer()
                Button(running ? "Durdur" : "Başla") { running ? stop() : start() }
                    .buttonStyle(PrimaryButtonStyle(enabled: running || !cards.filter(\.isDue).isEmpty))
                    .disabled(!running && cards.filter(\.isDue).isEmpty)
                    .padding(.horizontal, 24)
            }
            .padding(.bottom, 16)
            .navigationTitle("Sesli tekrar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { stop(); dismiss() } } }
            // Sayfa aşağı çekilerek kapanınca da oturum (okuma, mikrofon, ekran kilidi engeli) kapanır.
            .onDisappear { stop() }
        }
    }

    private func start() {
        session = MemoryModel.interleave(Array(cards.filter(\.isDue).prefix(30)), key: \.episodeID)
        index = 0
        running = true
        keepAwake(true)
        loop = Task { await run() }
    }

    private func stop() {
        running = false
        loop?.cancel()
        recorder.cancel()
        SpeechOut.shared.stop()
        keepAwake(false)
    }

    /// Ekrana dokunmadan çalışılır: oturum sürerken ekran kendiliğinden kilitlenmesin (`OnTheRoadView` ile aynı ayar).
    private func keepAwake(_ on: Bool) {
        guard on != keepsAwake else { return }
        keepsAwake = on
        UIApplication.shared.isIdleTimerDisabled = on
    }

    private func run() async {
        AppState.current?.player.suspendForLiveSession()
        while running, let card = session[safe: index], !Task.isCancelled {
            let position = index
            // Kullanıcı düğmeyle not verdiyse bu kart bitti: döngü yeni karttan devam eder.
            func stillOnCard() -> Bool { running && index == position && session[safe: index] === card }
            phase = "Soru okunuyor"
            await SpeechOut.shared.speak(card.front)
            guard stillOnCard() else { continue }
            phase = "Düşün…"
            try? await Task.sleep(for: .seconds(3))
            guard stillOnCard() else { continue }
            phase = "Cevap"
            await SpeechOut.shared.speak(card.back)
            guard stillOnCard() else { continue }
            phase = "Dinliyorum: bildim, bilemedim, zor, kolay"
            await recorder.start()
            if recorder.error != nil {
                phase = "Konuşma tanıma kullanılamıyor: düğmeyle seç"
            } else {
                try? await Task.sleep(for: .seconds(3.5))
            }
            let said = await recorder.stop().lowercased(with: Locale(identifier: "tr"))
            guard stillOnCard() else { continue }
            if let grade = Self.grade(from: said) {
                apply(grade)
            } else {
                // Anlaşılmadı: kartı tahminle notlama (tekrar verisi bozulmasın), düğmeyi bekle.
                phase = "Anlaşılmadı: düğmeyle seç"
                while stillOnCard() { try? await Task.sleep(for: .milliseconds(200)) }
            }
        }
        if index >= session.count, !session.isEmpty {
            running = false
            keepAwake(false)
            PodcastEvent.post(PodcastEvent.reviewFinished, count: session.count)
            await SpeechOut.shared.speak("Tebrikler, bugünkü tekrarlar bitti.")
        }
    }

    /// Sesli yanıttan not: anlaşılmazsa "iyi" sayılır.
    static func grade(from text: String) -> ReviewGrade? {
        if text.contains("bilemedim") || text.contains("bilmiyorum") || text.contains("tekrar") { return .again }
        if text.contains("zor") { return .hard }
        if text.contains("kolay") { return .easy }
        if text.contains("bildim") || text.contains("biliyorum") || text.contains("iyi") || text.contains("tamam") { return .good }
        return nil
    }

    private func apply(_ grade: ReviewGrade, advanceOnly: Bool = false) {
        guard let card = session[safe: index] else { return }
        card.reviewWithMemory(grade, retention: LearningAdaptiveReview.target(for: card))
        try? context.save()
        RecallLog.record(RecallLog.Entry(source: "review", question: card.front, isCorrect: grade != .again,
                                         chapterIndex: card.chapterIndex, cardID: card.id),
                         episodeID: card.episodeID, episodeTitle: card.episodeTitle, context: context)
        if grade == .again {
            session.insert(card, at: MemoryModel.reinsertIndex(card.episodeID, in: session.map(\.episodeID), after: index))
        }
        index += 1
    }
}

// MARK: - Sınav simülasyonu (öneri 13)

extension ExamScore {
    /// Podcast denemesinin sonucu (video denemesindeki `compute` ile aynı sayım; saf, test edilir).
    /// `answers`: soru sırası → seçilen şık; `keys`: soru sırasıyla doğru şık. Boş soru neti etkilemez.
    nonisolated static func tally(answers: [Int: Int], keys: [Int]) -> ExamScore {
        var score = ExamScore(correct: 0, wrong: 0, blank: 0)
        for (index, key) in keys.enumerated() {
            guard let answer = answers[index] else { score.blank += 1; continue }
            if answer == key { score.correct += 1 } else { score.wrong += 1 }
        }
        return score
    }
}

struct ExamSimulatorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Episode.createdAt, order: .reverse) private var episodes: [Episode]

    @State private var selected: Set<UUID> = []
    @State private var questionCount = 20
    @State private var minutes = 25
    @State private var exam: [LearnExamQuestion] = []
    @State private var draft: LearnExamDraft?
    @State private var persistenceError: String?
    @State private var restored = false
    @State private var history: [LearnExamDraft] = []
    @State private var classification = JSONStore<LearnExamClassification>("exam-classifications")
    @State private var answers: [Int: Int] = [:]
    @State private var current = 0
    @State private var deadline: Date?
    @State private var finished = false
    @State private var confidences: [Int: Int] = [:]
    /// Denemeye girebilecek sorusu olan bölümler; çalışma paketleri ekran açılırken bir kez çözülür (nil = henüz okunmadı).
    @State private var pool: [PoolEntry]?
    @State private var confirmClose = false
    @State private var confirmFinish = false

    private struct PoolEntry: Identifiable {
        var episode: Episode
        var items: [QuizItem]
        var id: UUID { episode.id }
    }

    /// Sınav başladı ve bitmedi: kapatma onaya bağlanır (cevaplar sorulmadan silinmesin).
    private var inProgress: Bool { !exam.isEmpty && !finished }

    /// Denemeye şıklı ve doğrulanmış sorular girer (#34).
    static func examEligible(_ item: QuizItem) -> Bool { !QuestionKind.isOpen(item) && item.verified != false }

    var body: some View {
        NavigationStack {
            Group {
                VStack(spacing: 0) {
                    if let persistenceError { VStack { Text(persistenceError).font(.callout).foregroundStyle(.red); Button(draft == nil ? "Kaydı yeniden oku" : "Kaydetmeyi yeniden dene") { if draft == nil { restore() } else if persist(), finished { recordResults() } } }.padding() }
                    if finished { results } else if exam.isEmpty { setup } else { examView }
                }
            }
            .navigationTitle("Sınav simülasyonu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { if inProgress { confirmClose = true } else { dismiss() } }
                }
                if let deadline, !finished, !exam.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            let left = max(0, deadline.timeIntervalSinceNow)
                            Text(left.clockText).font(.subheadline.monospacedDigit().bold())
                                .foregroundStyle(left < 60 ? .red : .primary)
                                .onChange(of: left <= 0) { _, over in if over { finish() } }
                        }
                    }
                }
            }
            .confirmationDialog("Sınav sürüyor", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("Sınavı bitir ve sonucu gör") { finish() }
                Button("Kaydet ve sonra devam et") { if persist() { dismiss() } }
                Button("Devam et", role: .cancel) {}
            } message: {
                Text("\(exam.count) sorudan \(answers.count) tanesini cevapladın. Cevapların ve şık sırası saklanır; sınav süresi işlemeye devam eder.")
            }
        }
        .interactiveDismissDisabled(inProgress)
        .task {
            if pool == nil { loadPool() }
            if !restored { restore(); history = LearnExamStorage.history(); restored = true }
        }
        .onChange(of: answers) { _, _ in _ = persist() }
        .onChange(of: confidences) { _, _ in _ = persist() }
        .onChange(of: current) { _, _ in _ = persist() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { if let deadline, deadline <= .now, inProgress { finish() } }
            else { _ = persist() }
        }
        .onDisappear { _ = persist() }
    }

    private var setup: some View {
        Form {
            if !history.isEmpty {
                Section("Önceki denemeler") {
                    ForEach(history, id: \.id) { saved in
                        Button("\(saved.started.formatted(date: .abbreviated, time: .shortened)) · \(saved.questions.count) soru") {
                            load(saved)
                            if persist(), finished { recordResults() }
                        }
                    }
                }
            }
            Section("Bölümler (quiz'i olanlar)") {
                if let pool {
                    if pool.isEmpty {
                        Text("Önce bölümlerin Çalış sekmesinden quiz oluştur.").foregroundStyle(.secondary)
                    }
                    ForEach(pool) { entry in
                        let id = entry.episode.id
                        Button {
                            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(id) ? "checkmark.circle.fill" : "circle")
                                Text(entry.episode.title).foregroundStyle(.primary).lineLimit(2)
                                Spacer()
                                Text("\(entry.items.count) soru").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityAddTraits(selected.contains(id) ? .isSelected : [])
                    }
                } else {
                    HStack { ProgressView(); Text("Sorular okunuyor…").foregroundStyle(.secondary) }
                }
            }
            Section("Sınav") {
                Stepper("Soru sayısı: \(questionCount)", value: $questionCount, in: 5...60, step: 5)
                Stepper("Süre: \(minutes) dk", value: $minutes, in: 5...120, step: 5)
                Text("Kazanım/bölüm, zorluk ve incelenmiş soru aileleri dengelenir. Daha az gördüğün sorular önce gelir; eksik havuzda soru uydurulmaz.").font(.caption)
                Button("Sınavı başlat") { begin() }.disabled(selected.isEmpty || persistenceError != nil)
            }
            Section("İsteğe bağlı kapsam incelemesi") {
                ForEach((pool ?? []).filter { selected.contains($0.id) }) { group in
                    ForEach(group.items, id: \.question) { item in
                        DisclosureGroup(String(item.question.prefix(100))) {
                            let key = LearnExamSelection.key(item.question)
                            TextField("Kazanım (boşsa bölüm kullanılır)", text: classificationText(key, \.outcome))
                            TextField("Aynı soru ailesinin ortak adı", text: classificationText(key, \.family))
                            Picker("Zorluk", selection: classificationDifficulty(key, fallback: item.difficulty)) { Text("Bilinmiyor").tag(0); Text("Kolay").tag(1); Text("Orta").tag(2); Text("Zor").tag(3) }
                        }
                    }
                }
            }
        }
    }

    private var examView: some View {
        let entry = exam[current]
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ProgressView(value: Double(answers.count), total: Double(exam.count))
                Text("Soru \(current + 1) / \(exam.count) · \(entry.episodeTitle)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(entry.item.question).font(.title3.weight(.semibold))
                ForEach(Array(entry.item.options.enumerated()), id: \.offset) { i, option in
                    let chosen = answers[current] == i
                    Button {
                        // Aynı şıkka yeniden dokunmak seçimi kaldırır: yanlış net götürdüğü için soru boş bırakılabilmeli.
                        answers[current] = chosen ? nil : i
                    } label: {
                        HStack {
                            Text(QuestionKind.letter(i)).bold()
                            Text(option).multilineTextAlignment(.leading)
                            Spacer()
                            if chosen { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                        }
                        .padding(14)
                        .background(chosen ? AnyShapeStyle(Theme.gradient.opacity(0.25)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                                    in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
                Text("Boş bırakmak için seçili şıkka yeniden dokun.").font(.footnote).foregroundStyle(.secondary)
                if ListeningMode.current.policy.confidence {
                    ConfidencePicker(value: Binding(get: { confidences[current] }, set: { confidences[current] = $0 }))
                }
                HStack {
                    Button("Önceki") { current = max(0, current - 1) }.disabled(current == 0)
                    Spacer()
                    if current + 1 < exam.count {
                        Button("Sonraki") { current += 1 }.buttonStyle(.borderedProminent)
                    } else {
                        Button("Sınavı bitir") {
                            if ExamNav.unanswered(count: exam.count, answers: answers).isEmpty { finish() } else { confirmFinish = true }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(20)
        }
        .confirmationDialog("\(exam.count - answers.count) soru boş. Yine de bitir?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Sınavı bitir") { finish() }
            Button("İlk boş soruya git") {
                if let blank = ExamNav.unanswered(count: exam.count, answers: answers).first { current = blank }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Boş sorular neti düşürmez; tekrar destene ve yanlış defterine “Boş” diye eklenir.")
        }
    }

    private var results: some View {
        let score = ExamScore.tally(answers: answers, keys: exam.map { $0.item.answerIndex })
        let byEpisode = Dictionary(grouping: exam.indices, by: { exam[$0].episodeTitle })
        return List {
            Section {
                VStack(spacing: 6) {
                    Text("\(score.correct) / \(exam.count)").font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("Doğru: \(score.correct) · Yanlış: \(score.wrong) · Boş: \(score.blank)").font(.subheadline)
                    Text(String(format: "Net: %.2f (4 yanlış 1 doğruyu götürür)", score.net)).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            if let note = draft?.selectionNote { Section("Sınavın kapsamı") { Text(note).font(.caption) } }
            Section { Button("Sonucu arşivle ve yeni sınav hazırla") {
                do {
                    guard let draft else { throw QSError.message("Arşivlenecek sınav bulunamadı.") }
                    try LearnExamStorage.archive(draft)
                    try FileManager.default.removeItem(at: LearnExamStorage.url)
                    self.draft = nil; exam = []; finished = false; answers = [:]; confidences = [:]
                    history = LearnExamStorage.history(); persistenceError = nil
                } catch { persistenceError = "Sonuç arşivlenemedi; mevcut sınav korundu: " + error.localizedDescription }
            }.disabled(draft?.resultsRecorded != true) }
            Section("Bölüm bazında") {
                ForEach(byEpisode.keys.sorted(), id: \.self) { title in
                    let indices = byEpisode[title] ?? []
                    let ok = indices.filter { answers[$0] == exam[$0].item.answerIndex }.count
                    LabeledContent(title, value: "\(ok)/\(indices.count)")
                }
            }
            if let weakest = byEpisode.min(by: { a, b in
                let ra = Double(a.value.filter { answers[$0] == exam[$0].item.answerIndex }.count) / Double(max(1, a.value.count))
                let rb = Double(b.value.filter { answers[$0] == exam[$0].item.answerIndex }.count) / Double(max(1, b.value.count))
                return ra < rb
            }), let episode = episodes.first(where: { $0.id == exam[weakest.value[0]].episodeID }),
               weakest.value.contains(where: { answers[$0] != exam[$0].item.answerIndex }) {
                Section("Koçun önerisi") {
                    Button("En zayıf konu: \(episode.title) — dinle", systemImage: "play.circle.fill") {
                        AppState.current?.pendingOpenEpisode = episode.id
                        dismiss()
                    }
                }
            }
            Section("Yanlışlar") {
                ForEach(exam.indices.filter { answers[$0] != exam[$0].item.answerIndex }, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exam[i].item.question).font(.callout.bold())
                        if answers[i] == nil { Text("Boş bırakıldı").font(.caption).foregroundStyle(.secondary) }
                        Text("Doğru: \(exam[i].item.options[safe: exam[i].item.answerIndex] ?? "")").font(.caption).foregroundStyle(.green)
                        if let episode = episodes.first(where: { $0.id == exam[i].episodeID }), let time = ListenAnchor.time(for: exam[i].item, timeline: episode.timeline) {
                            Button(ListenAnchor.label(time), systemImage: "headphones") {
                                let id = exam[i].episodeID
                                dismiss()
                                AppState.current?.open(id, at: time, play: true)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                }
            }
        }
    }

    /// Çalışma paketi olmayan bölüm çözülmeden atlanır; kurulum satırları ve `begin` bu listeyi kullanır
    /// (her çizimde ve her seçim dokunuşunda bütün paketler yeniden süzülmesin).
    private func loadPool() {
        pool = episodes.compactMap { episode in
            guard episode.studyData != nil else { return nil }
            let items = (episode.study?.quiz ?? []).filter(Self.examEligible)
            return items.isEmpty ? nil : PoolEntry(episode: episode, items: items)
        }
    }

    private func classificationText(_ id: String, _ path: WritableKeyPath<LearnExamClassification, String>) -> Binding<String> {
        Binding(get: { classification.items.first { $0.id == id }?[keyPath: path] ?? "" }, set: { value in
            if let index = classification.items.firstIndex(where: { $0.id == id }) { classification.items[index][keyPath: path] = String(value.prefix(150)) }
            else { var item = LearnExamClassification(id: id); item[keyPath: path] = String(value.prefix(150)); classification.items.append(item) }
        })
    }
    private func classificationDifficulty(_ id: String, fallback: Int?) -> Binding<Int> {
        Binding(get: { classification.items.first { $0.id == id }?.difficulty ?? fallback ?? 0 }, set: { value in
            if let index = classification.items.firstIndex(where: { $0.id == id }) { classification.items[index].difficulty = value == 0 ? nil : value }
            else { classification.items.append(.init(id: id, difficulty: value == 0 ? nil : value)) }
        })
    }
    private func begin() {
        let candidates = (pool ?? []).filter { selected.contains($0.id) }.flatMap { group in
            group.items.map { LearnExamQuestion(episodeID: group.id, episodeTitle: group.episode.title, item: $0) }
        }
        let history = (try? context.fetch(FetchDescriptor<RecallAttempt>())) ?? []
        let seen = Dictionary(grouping: history, by: { LearnExamSelection.key($0.question) }).mapValues(\.count)
        let selection = LearnExamSelection.select(candidates, count: questionCount, classifications: classification.items, seen: seen)
        guard !selection.questions.isEmpty else { persistenceError = "Seçilen kaynaklarda uygun soru yok."; return }
        exam = selection.questions.map { var q = $0; q.item = OptionShuffle.shuffled(q.item); return q }
        answers = [:]; confidences = [:]; current = 0; finished = false
        deadline = .now.addingTimeInterval(Double(minutes * 60))
        draft = LearnExamDraft(questions: exam, deadline: deadline!, selectionNote: selection.note)
        if !persist() { exam = []; draft = nil }
    }
    @discardableResult private func persist() -> Bool {
        guard var saved = draft else { return true }
        saved.answers = answers; saved.confidences = confidences; saved.current = current
        if finished && saved.finishedAt == nil { saved.finishedAt = .now }
        do { try LearnExamStorage.save(saved); draft = saved; persistenceError = nil; return true }
        catch { persistenceError = "Sınav kaydedilemedi. Ekranı kapatmadan yeniden dene: " + error.localizedDescription; return false }
    }
    private func load(_ saved: LearnExamDraft) {
        draft = saved; exam = saved.questions; answers = saved.answers; confidences = saved.confidences
        current = saved.current; deadline = saved.deadline; finished = saved.finishedAt != nil
    }
    private func restore() {
        do {
            guard let saved = try LearnExamStorage.load() else { return }
            load(saved)
            if finished { recordResults() } else if saved.deadline <= .now { finish() }
        } catch { persistenceError = "Kayıtlı sınav okunamadı; dosya korunuyor ve yeni sınavla üzerine yazılmadı. " + error.localizedDescription }
    }
    private func finish() {
        guard !finished, !exam.isEmpty else { return }
        finished = true
        guard persist() else { finished = false; return }
        recordResults()
    }
    private func recordResults() {
        guard var saved = draft, saved.finishedAt != nil else { return }
        for i in saved.questions.indices where !saved.recorded.contains(i) {
            let question = saved.questions[i]
            let outcome = classification.items.first { $0.id == question.id }?.outcome ?? ""
            let topic = outcome.isEmpty ? question.episodeTitle : outcome
            do {
                saved = try LearnExamResultSession.record(saved, index: i, topic: topic, container: context.container)
                draft = saved
            } catch {
                persistenceError = "Sonuç kaydı tamamlanamadı; cevapların korunuyor. Yeniden dene: " + error.localizedDescription
                return
            }
        }
        persistenceError = nil
    }
}
