import SwiftData
import SwiftUI

/// #26: bölüm sonu kartı. "Ne öğrendin" (3 madde), 3 hızlı soru, "Sıradaki: … 5 sn".
/// Sınav modunda ön test yapıldıysa aynı sorular yeniden sorulur: "Önce 1/5 → Sonra 4/5".
struct EpisodeEndCard: View {
    var episode: Episode
    @Environment(\.modelContext) private var context
    @State private var questions: [QuizItem] = []
    @State private var before: Int?
    @State private var after: Int?
    @State private var countdown = 5
    @State private var countdownStopped = false
    @State private var nextTitle: String?
    private var center: LearningCenter { LearningCenter.shared }
    /// Kart kapanınca sıradaki başlayacak mı ("Bekle" denmedi).
    private var autoAdvance: Bool { center.nextHold.autoAdvance }

    private var keyPoints: [String] { Array((episode.script?.keyPoints ?? []).prefix(3)) }
    private var policy: ListeningPolicy { ListeningMode.current.policy }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Bölüm bitti", systemImage: "checkmark.seal.fill").font(.subheadline.bold()).foregroundStyle(.green)
                        Text(episode.title).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                    }
                    if let nextTitle { nextRow(nextTitle) }
                    if !keyPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Ne öğrendin").font(.headline)
                            ForEach(Array(keyPoints.enumerated()), id: \.offset) { i, point in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(i + 1)").font(.caption.bold()).frame(width: 24, height: 24)
                                        .background(Theme.gradient, in: Circle()).foregroundStyle(.white)
                                    Text(point).font(.callout).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    if let after {
                        result(after)
                    } else if !questions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(before != nil ? "Ön testteki sorular, şimdi" : "\(questions.count) hızlı soru").font(.headline)
                            QuestionRun(items: questions, episode: episode, source: "endcard", showConfidence: policy.confidence,
                                        onListen: { time in
                                            center.waitForNext()   // o anı dinlerken sıradaki başlamasın
                                            center.sheet = nil
                                            LearningLinks.listen(episodeID: episode.id, at: time)
                                        },
                                        onFinish: { outcomes in after = outcomes.filter { $0.isCorrect == true }.count },
                                        onFirstAnswer: { countdownStopped = true })
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Bölüm sonu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { LearningCenter.shared.sheet = nil } }
            }
        }
        .onAppear(perform: setUp)
        .task(id: "\(nextTitle ?? "")|\(countdownStopped)|\(autoAdvance)") {
            guard nextTitle != nil, !countdownStopped, autoAdvance else { return }
            while countdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled || countdownStopped || !autoAdvance { return }
                countdown -= 1
            }
            center.playNextFromEndCard()
        }
    }

    private func nextRow(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(countdownStopped || !autoAdvance ? "Sıradaki: \(title)" : "Sıradaki: \(title) · \(countdown) sn")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .lineLimit(2)
            if autoAdvance, countdownStopped {
                Text("Kartı kapatınca başlar.").font(.caption).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack { startButton; holdButton }
                VStack(alignment: .leading) { startButton; holdButton }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private var startButton: some View {
        Button("Şimdi başlat", systemImage: "forward.fill") { center.playNextFromEndCard() }
            .buttonStyle(.borderedProminent)
    }

    /// "Bekle": sayaç durur ve kart kapanınca da sıradaki başlamaz ("Şimdi başlat" kalır).
    @ViewBuilder private var holdButton: some View {
        if autoAdvance {
            Button("Bekle") {
                countdownStopped = true
                center.waitForNext()
            }
            .buttonStyle(.bordered)
        }
    }

    private func result(_ after: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let before {
                Text("Önce \(before)/\(questions.count) → Sonra \(after)/\(questions.count)")
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(after > before ? AnyShapeStyle(.green) : AnyShapeStyle(.primary))
                Text(after > before ? "Dinlediğin bölüm işe yaradı." : "Kaçırdıkların tekrar kartlarına eklendi.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("\(questions.count) soruda \(after) doğru").font(.title3.bold())
                Text(after == questions.count ? "Harika, konu oturmuş." : "Kaçırdıkların tekrar kartlarına eklendi; yoklamalar Çalış sekmesinde.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func setUp() {
        guard questions.isEmpty else { return }
        let quiz = episode.study?.quiz ?? []
        let pre = PretestStore.attempts(episodeID: episode.id, context: context)
        if policy.preTest, !pre.isEmpty {
            let texts = pre.map(\.question)
            questions = texts.compactMap { text in quiz.first { $0.question == text } }
            before = pre.filter { $0.isCorrect == true }.count
            if questions.count != pre.count { questions = []; before = nil }
        }
        if questions.isEmpty { questions = QuestionPicker.spread(quiz, count: 3) }
        // P5 `holdAutoplay`'i bitişte hemen sıfırlar; sıradakinin adı LearningCenter'da tutulur.
        nextTitle = center.nextHold.title
    }
}

/// #26 sınav modu: dinlemeden önce 5 soruluk ön test. Yanlışlar karta düşmez (henüz dinlenmedi).
struct PretestView: View {
    var episode: Episode
    @Environment(\.modelContext) private var context
    @State private var items: [QuizItem] = []
    @State private var score: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Bilmediğini görmek, dinlerken dikkatini doğru yere verir. Bölüm sonunda aynı sorular yeniden gelecek.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let score {
                        Text("Ön test: \(score)/\(items.count)").font(.title2.bold().monospacedDigit())
                        Button("Dinlemeye başla", systemImage: "play.fill") { start() }
                            .buttonStyle(PrimaryButtonStyle())
                    } else if !items.isEmpty {
                        QuestionRun(items: items, episode: episode, source: "pretest", showConfidence: true, addWrong: false,
                                    onListen: nil) { outcomes in
                            score = outcomes.filter { $0.isCorrect == true }.count
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Ön test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { LearningCenter.shared.sheet = nil } } }
        }
        .onAppear { if items.isEmpty { items = QuestionPicker.spread(episode.study?.quiz ?? [], count: 5) } }
    }

    private func start() {
        LearningCenter.shared.sheet = nil
        guard let player = AppState.current?.player else { return }
        if player.episode?.id == episode.id { player.play() } else { player.play(episode, at: nil, context: context) }
    }
}
