import SwiftData
import SwiftUI

/// Tek soru kartı (#24, #27, #34): şıklı (4/5 şık, öncüllü), doğru/yanlış ve açık uçlu sorular.
/// Açık uçlu cevap `/v1/evaluate` ile değerlendirilir; olmazsa kullanıcı kendini notlar.
/// Yanlışın altında "Bu kısmı dinle (12:14)". Kart soru değişince `.id(...)` ile yenilenmeli.
struct QuestionCard: View {
    var item: QuizItem
    var header: String?
    var episode: Episode?
    var showConfidence = false
    /// > 0 ise şıklar düşünme payı kadar gizli kalır (#23).
    var thinkSeconds: Double = 0
    /// Verilmezse bölüm o ana açılır ve çalar.
    var onListen: ((Double) -> Void)?
    var onAnswered: (QuestionOutcome) -> Void

    @State private var selected: Int?
    @State private var confidence: Int?
    @State private var openAnswer = ""
    @State private var evaluation: Evaluation?
    @State private var evaluating = false
    @State private var evalError: String?
    @State private var revealedOpen = false
    @State private var selfGrade: Bool?
    @State private var started = Date.now
    /// #23: geçen düşünme süresi; kalan süre ilk çizimden itibaren doludur (şıklar bir kare bile görünüp dokunulmaz).
    @State private var thinkElapsed = 0
    @State private var thinkSkipped = false
    @State private var recorder = SpeechRecorder()

    private var thinkLeft: Int { Self.thinkRemaining(seconds: thinkSeconds, elapsed: thinkElapsed, skipped: thinkSkipped) }

    static func thinkRemaining(seconds: Double, elapsed: Int, skipped: Bool) -> Int {
        guard !skipped, seconds > 0 else { return 0 }
        return max(0, Int(seconds.rounded(.up)) - elapsed)
    }

    private var isOpen: Bool { QuestionKind.isOpen(item) }
    private var answered: Bool { selected != nil || evaluation != nil || selfGrade != nil }
    private var wasWrong: Bool {
        if let selected { return selected != item.answerIndex }
        if let evaluation { return evaluation.verdict != "dogru" }
        return selfGrade == false
    }
    private var listenTime: Double? { ListenAnchor.time(for: item, timeline: episode?.timeline) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let header {
                Text(header).font(.caption.bold()).foregroundStyle(.secondary)
            }
            kindBadge
            Text(item.question).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if thinkLeft > 0, !answered {
                thinking
            } else if isOpen {
                openArea
            } else {
                choices
            }
            if showConfidence, !answered, thinkLeft == 0 {
                ConfidencePicker(value: $confidence)
            }
            if answered { feedback }
        }
        .animation(.smooth, value: answered)
        .task {
            started = .now
            while thinkLeft > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                thinkElapsed += 1
            }
        }
        .onDisappear { recorder.cancel() }
    }

    @ViewBuilder private var kindBadge: some View {
        let title: String? = switch QuestionKind.of(item) {
        case "osym": "ÖSYM tarzı"
        case "premise": "Öncüllü"
        case "truefalse": "Doğru / Yanlış"
        case "open": "Açık uçlu"
        default: nil
        }
        if title != nil || item.verified == false {
            HStack(spacing: 6) {
                if let title { Text(title).font(.caption2.bold()).padding(.horizontal, 8).padding(.vertical, 3).background(.quaternary, in: Capsule()) }
                if item.verified == false {
                    Label("Kaynakla doğrulanamadı", systemImage: "exclamationmark.triangle").font(.caption2).foregroundStyle(.orange)
                }
            }
        }
    }

    private var thinking: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Düşün… \(thinkLeft)", systemImage: "brain.head.profile")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.tint)
                .accessibilityLabel("Düşünme payı, \(thinkLeft) saniye")
            Text("Şıklara bakmadan cevabı aklında kur; sonra karşılaştır.").font(.footnote).foregroundStyle(.secondary)
            Button("Şıkları şimdi göster") { thinkSkipped = true }.buttonStyle(.bordered)
        }
    }

    private var choices: some View {
        VStack(spacing: 8) {
            ForEach(Array(item.options.enumerated()), id: \.offset) { i, option in
                Button {
                    guard selected == nil else { return }
                    selected = i
                    finish(QuestionOutcome(chosenIndex: i, isCorrect: i == item.answerIndex, confidence: confidence))
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text(QuestionKind.letter(i)).font(.subheadline.bold())
                        Text(option).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if selected != nil, i == item.answerIndex {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Doğru cevap")
                        } else if selected == i {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.red).accessibilityLabel("Senin cevabın")
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(fill(for: i), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var openArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            if evaluation == nil, selfGrade == nil {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Cevabını yaz ya da söyle", text: $openAnswer, axis: .vertical)
                        .lineLimit(2...6)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        Task {
                            if recorder.isRecording { openAnswer = await recorder.stop() } else { await recorder.start() }
                        }
                    } label: {
                        Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(recorder.isRecording ? .red : .accentColor)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(recorder.isRecording ? "Kaydı bitir" : "Sesle cevapla")
                }
                if recorder.isRecording, !recorder.transcript.isEmpty {
                    Text(recorder.transcript).font(.caption).foregroundStyle(.secondary)
                }
                if let error = recorder.error ?? evalError { Text(error).font(.caption).foregroundStyle(.red) }
                ViewThatFits(in: .horizontal) {
                    HStack { evaluateButton; revealButton }
                    VStack(alignment: .leading) { evaluateButton; revealButton }
                }
                if revealedOpen {
                    Text(QuestionKind.expectedAnswer(item)).font(.callout).padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                    HStack(spacing: 8) {
                        Button("Bildim") { grade(true) }.buttonStyle(.borderedProminent).tint(.green)
                        Button("Bilemedim") { grade(false) }.buttonStyle(.bordered).tint(.red)
                    }
                }
            } else if let evaluation {
                EvaluationCard(evaluation: evaluation)
            }
        }
    }

    private var evaluateButton: some View {
        Button {
            Task { await evaluate() }
        } label: {
            HStack { if evaluating { ProgressView() }; Text(evaluating ? "Değerlendiriliyor…" : "Değerlendir") }
        }
        .buttonStyle(.borderedProminent)
        .disabled(evaluating || openAnswer.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
    }

    private var revealButton: some View {
        Button("Cevabı göster") { revealedOpen = true }
            .buttonStyle(.bordered)
            .disabled(revealedOpen)
    }

    @ViewBuilder private var feedback: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isOpen, evaluation != nil || selfGrade != nil {
                Text("Beklenen: \(QuestionKind.expectedAnswer(item))").font(.callout.bold())
            }
            if !item.explanation.isEmpty {
                Text(item.explanation).font(.callout)
            }
            if let page = item.sourcePage {
                Text("Kaynak: sayfa \(page)").font(.caption).foregroundStyle(.secondary)
            }
            if wasWrong, let time = listenTime, let episode {
                Button {
                    if let onListen { onListen(time) } else { LearningLinks.listen(episodeID: episode.id, at: time) }
                } label: {
                    Label(ListenAnchor.label(time), systemImage: "headphones")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private func fill(for i: Int) -> AnyShapeStyle {
        guard let selected else { return AnyShapeStyle(.quaternary.opacity(0.5)) }
        if i == item.answerIndex { return AnyShapeStyle(Color.green.opacity(0.18)) }
        if i == selected { return AnyShapeStyle(Color.red.opacity(0.15)) }
        return AnyShapeStyle(.quaternary.opacity(0.3))
    }

    private func grade(_ knew: Bool) {
        guard selfGrade == nil else { return }
        selfGrade = knew
        finish(QuestionOutcome(isCorrect: knew, confidence: confidence, answerText: openAnswer.isEmpty ? nil : openAnswer))
    }

    private func evaluate() async {
        if recorder.isRecording { openAnswer = await recorder.stop() }
        let answer = openAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        evaluating = true
        evalError = nil
        defer { evaluating = false }
        do {
            let result = try await APIClient.shared.evaluate(EvaluateRequest(
                mode: "answer", prompt: String(item.question.prefix(2000)), expected: String(QuestionKind.expectedAnswer(item).prefix(3000)),
                sourceNotes: String((episode?.script?.sourceNotes ?? "").prefix(15_000)),
                response: String(answer.prefix(5000)), language: episode?.settings?.language.rawValue ?? "tr"))
            evaluation = result
            finish(QuestionOutcome(isCorrect: result.verdict == "dogru", score: Double(result.score) / 100,
                                   confidence: confidence, answerText: answer))
        } catch {
            evalError = "\(error.localizedDescription) Cevabı görüp kendin notlayabilirsin."
            revealedOpen = true
        }
    }

    private func finish(_ outcome: QuestionOutcome) {
        var outcome = outcome
        outcome.seconds = Date.now.timeIntervalSince(started)
        onAnswered(outcome)
    }
}

/// "Bu kısmı dinle": bölüm oynatıcıda açıksa oraya atlar, değilse kütüphanede o anı açıp çalar.
enum LearningLinks {
    static func listen(episodeID: UUID, at time: Double) {
        guard let app = AppState.current else { return }
        if app.player.episode?.id == episodeID {
            app.player.seek(to: time)
            app.player.play()
        } else {
            app.open(episodeID, at: time, play: true)
        }
    }
}

/// Art arda sorular (bölüm sonu kartı, ön test, yoklama, ayırt etme). Her cevap günlüğe yazılır;
/// `addWrong` açıksa yanlışlar karta ve yanlış defterine düşer.
struct QuestionRun: View {
    var items: [QuizItem]
    var episode: Episode?
    var source: String
    var showConfidence = false
    var addWrong = true
    var onListen: ((Double) -> Void)?
    var onFinish: ([QuestionOutcome]) -> Void
    var onFirstAnswer: (() -> Void)?

    @Environment(\.modelContext) private var context
    @State private var index = 0
    @State private var outcomes: [QuestionOutcome] = []
    @State private var current: QuestionOutcome?

    var body: some View {
        if let item = items[safe: index] {
            VStack(alignment: .leading, spacing: 12) {
                QuestionCard(item: item, header: "Soru \(index + 1) / \(items.count)", episode: episode,
                             showConfidence: showConfidence, onListen: onListen) { outcome in
                    if outcomes.isEmpty, current == nil { onFirstAnswer?() }
                    current = outcome
                    log(item, outcome)
                }
                .id("\(index)-\(item.question)")
                if let current {
                    Button(index + 1 < items.count ? "Sonraki soru" : "Bitir") {
                        outcomes.append(current)
                        self.current = nil
                        index += 1
                        if index >= items.count { onFinish(outcomes) }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    private func log(_ item: QuizItem, _ outcome: QuestionOutcome) {
        RecallLog.record(RecallLog.entry(item, source: source, outcome: outcome), episode: episode, context: context)
        guard addWrong, outcome.isCorrect == false else { return }
        if let episode { ReviewDeck.addWrong(item, episode: episode, context: context, origin: source == "probe" ? "probe" : "quiz") }
        let mine = outcome.chosenIndex.flatMap { item.options[safe: $0] } ?? outcome.answerText ?? ""
        MistakeBook.record(item, myAnswer: mine, episode: episode, source: source, context: context)
    }
}
