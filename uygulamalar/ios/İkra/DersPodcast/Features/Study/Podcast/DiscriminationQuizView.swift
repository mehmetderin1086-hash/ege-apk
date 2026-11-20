import SwiftData
import SwiftUI

/// #35: sık karıştırılan iki kavram için "Farkı ne?" tablosu ve ayırt etme soruları (`/v1/discriminate`, `learn2`).
struct DiscriminationQuizView: View {
    let a: String
    let b: String
    let notes: String
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @State private var result: DiscriminateResult?
    @State private var loading = false
    @State private var error: String?
    @State private var score: Int?

    /// Gezinme yığınını çağıran kurar (ör. `NavigationStack { DiscriminationQuizView(...) }`); iç içe yığın açılmaz.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(a) mı, \(b) mi?").font(.title3.bold())
                if let result {
                    contrast(result.contrast)
                    if let score {
                        Text("\(result.questions.count) soruda \(score) doğru").font(.headline)
                        Text(score == result.questions.count ? "İkisini artık ayırıyorsun." : "Yanlışlar yanlış defterine yazıldı.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else if !result.questions.isEmpty {
                        Text("Ayırt etme soruları").font(.headline)
                        QuestionRun(items: result.questions, episode: nil, source: "discriminate",
                                    showConfidence: ListeningMode.current.policy.confidence) { outcomes in
                            score = outcomes.filter { $0.isCorrect == true }.count
                        }
                    }
                } else if loading {
                    HStack { ProgressView(); Text("Farklar çıkarılıyor…") }
                } else if !app.serverSupports("learn2") {
                    Text("Bu özellik için sunucunun güncellenmesi gerekiyor.").foregroundStyle(.secondary)
                }
                if let error {
                    Text(error).font(.callout).foregroundStyle(.red)
                    Button("Yeniden dene") { Task { await load() } }.buttonStyle(.bordered)
                }
            }
            .padding(20)
        }
        .navigationTitle("Farkı ne?")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
        .task { if result == nil, app.serverSupports("learn2") { await load() } }
    }

    /// Dar ekranda tablo yerine satır başına kart: yön, A, B alt alta.
    private func contrast(_ rows: [DiscriminateResult.Row]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.aspect).font(.subheadline.bold())
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 10) { cell(a, row.a, .blue); cell(b, row.b, .orange) }
                        VStack(alignment: .leading, spacing: 6) { cell(a, row.a, .blue); cell(b, row.b, .orange) }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func cell(_ title: String, _ text: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.bold()).foregroundStyle(color)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let response = try await APIClient.shared.discriminate(DiscriminateRequest(
                a: String(a.prefix(200)), b: String(b.prefix(200)), notes: String(notes.prefix(15_000)), count: 5))
            result = DiscriminateResult(contrast: response.contrast, questions: QuestionPicker.easyFirst(response.questions.map(OptionShuffle.shuffled)))
        } catch {
            self.error = error.localizedDescription
        }
    }
}
