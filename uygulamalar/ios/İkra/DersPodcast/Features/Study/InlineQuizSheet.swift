import SwiftUI

/// Dinlerken quiz: konu sonunda sorulan tek soru (#23, #24, #34).
/// Şıklar düşünme payı (senaryodaki 3–8 sn) kadar gizli kalır; açık uçlu / şıksız soruda cevap görülüp kendini notlanır.
struct InlineQuizSheet: View {
    var item: QuizItem
    var thinkSeconds: Double = 0
    var episode: Episode?
    var showConfidence = false
    /// Ayrıntılı sonuç (seçilen şık, eminlik, süre); `done`'dan önce çağrılır.
    var onOutcome: ((QuestionOutcome) -> Void)?
    var done: (Bool) -> Void
    @State private var outcome: QuestionOutcome?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("Kısa bir mola: kendini dene", systemImage: "questionmark.bubble.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.tint)
                QuestionCard(item: item, episode: episode, showConfidence: showConfidence, thinkSeconds: thinkSeconds,
                             onListen: { time in
                                 // Yanlışın altında "Bu kısmı dinle": soruyu kapatıp o andan sürdür.
                                 if let id = episode?.id { finish(); LearningLinks.listen(episodeID: id, at: time) }
                             }) { result in
                    outcome = result
                }
                if outcome != nil {
                    if outcome?.isCorrect == false, item.verified != false {
                        Label("Bu soru tekrar kartlarına eklendi.", systemImage: "rectangle.stack.badge.plus")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Dinlemeye devam et") { finish() }
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button("Atla") { done(true) }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(20)
            .animation(.smooth, value: outcome)
        }
    }

    private func finish() {
        guard let outcome else { done(true); return }
        onOutcome?(outcome)
        done(outcome.isCorrect != false)
    }
}
