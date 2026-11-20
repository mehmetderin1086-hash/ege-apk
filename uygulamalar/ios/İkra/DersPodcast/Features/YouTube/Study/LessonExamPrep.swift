import SwiftData
import SwiftUI

/// Açık uçlu soru provasının durumu: soru gösterilir, cevap açılır, öğrenci bilip bilmediğini işaretler.
nonisolated struct ExamPrepSession: Equatable, Sendable {
    private(set) var order: [Int]
    private(set) var position = 0
    private(set) var known: [Int] = []
    private(set) var missed: [Int] = []
    var revealed = false

    init(count: Int) { order = Array(0..<max(0, count)) }
    var current: Int? { position < order.count ? order[position] : nil }
    var finished: Bool { current == nil }
    var progress: String { "\(min(position + 1, order.count)) / \(order.count)" }
    mutating func answer(knew: Bool) {
        guard let current else { return }
        if knew { known.append(current) } else { missed.append(current) }
        position += 1; revealed = false
    }
    /// Yalnız bilinemeyen sorularla yeni tur.
    mutating func retryMissed() {
        guard !missed.isEmpty else { return }
        order = missed; position = 0; known = []; missed = []; revealed = false
    }
}

/// "Yazılıya hazırlan": dersin özeti, açık uçlu soru provası, kavramlar ve çalışma kâğıdı tek ekranda.
/// Sorular ve özet dersin hazır notlarından gelir; yeni istek gönderilmez.
struct LessonExamPrepView: View {
    var context: LessonContext
    @Environment(\.modelContext) private var modelContext
    @State private var session: ExamPrepSession
    @State private var nested: LessonSheet?
    @State private var note: String?

    init(context: LessonContext) {
        self.context = context
        _session = State(initialValue: ExamPrepSession(count: context.transcript.notes?.questions.count ?? 0))
    }

    var body: some View {
        StudySheet(title: "Yazılıya hazırlan") {
            if let notes = context.transcript.notes {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if !notes.summary.isEmpty { block("Konu özeti", "text.alignleft") { Text(notes.summary).textSelection(.enabled) } }
                        if !notes.questions.isEmpty { block("Soru provası", "pencil.and.list.clipboard") { practice(notes.questions) } }
                        if !notes.keyPoints.isEmpty {
                            block("Ana noktalar", "list.bullet") {
                                ForEach(Array(notes.keyPoints.enumerated()), id: \.offset) { _, point in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) { Text("•").foregroundStyle(.secondary); Text(point.text).frame(maxWidth: .infinity, alignment: .leading) }
                                }
                            }
                        }
                        if !notes.concepts.isEmpty {
                            block("Kavramlar", "character.book.closed") {
                                ForEach(Array(notes.concepts.enumerated()), id: \.offset) { _, concept in
                                    VStack(alignment: .leading, spacing: 2) { Text(concept.name).fontWeight(.semibold); Text(concept.definition).foregroundStyle(.secondary) }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        if !notes.examTips.isEmpty {
                            block("Sınav ipuçları", "lightbulb") { ForEach(Array(notes.examTips.enumerated()), id: \.offset) { _, tip in Text("• " + tip).frame(maxWidth: .infinity, alignment: .leading) } }
                        }
                        block("Daha fazlası", "square.grid.2x2") {
                            Button("Çalışma kâğıdı oluştur (PDF)", systemImage: "doc.on.clipboard") { nested = .worksheet }
                            Button("Bölüm quiz'i çöz", systemImage: "checklist") { nested = .quiz(chapter: nil) }
                            Button("Özeti ve soruları kartlara ekle", systemImage: "rectangle.stack.badge.plus") {
                                let count = LessonStudy.addNoteCards(notes, lesson: context.lesson, context: modelContext)
                                note = count > 0 ? "\(count) kart tekrar listesine eklendi." : "Kartlar zaten ekli."
                            }
                            if let note { Text(note).font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                    .padding(16)
                }
                .background(Color(.systemBackground))
                .sheet(item: $nested) { LessonSheetHost(sheet: $0, context: context) }
            } else {
                ContentUnavailableView("Bu dersin notu yok", systemImage: "note.text",
                                       description: Text("Özet ve sorular ders işlenirken hazırlanır. Bu ders için hazırlanamamış; bölüm quiz'ini ya da çalışma kâğıdını kullanabilirsin."))
            }
        }
    }

    private func block<Content: View>(_ title: String, _ symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func practice(_ questions: [NoteQuestion]) -> some View {
        if let index = session.current, questions.indices.contains(index) {
            let question = questions[index]
            VStack(alignment: .leading, spacing: 12) {
                Text("Soru \(session.progress)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(question.question).font(.body.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                if session.revealed {
                    Text(question.answer).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    Button("Videoda bu yere git", systemImage: "play.circle") { context.player.seek(to: question.time) }.font(.footnote)
                    HStack(spacing: 10) {
                        Button { session.answer(knew: false) } label: { Label("Bilemedim", systemImage: "xmark").frame(maxWidth: .infinity) }.buttonStyle(.bordered).tint(.orange)
                        Button { session.answer(knew: true) } label: { Label("Bildim", systemImage: "checkmark").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                    }
                } else {
                    Text("Önce cevabı aklından ya da kâğıda yaz, sonra karşılaştır.").font(.footnote).foregroundStyle(.secondary)
                    Button { session.revealed = true } label: { Label("Cevabı göster", systemImage: "eye").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("\(session.known.count) soruyu bildin, \(session.missed.count) soruyu bilemedin.", systemImage: session.missed.isEmpty ? "checkmark.seal.fill" : "chart.bar")
                    .foregroundStyle(session.missed.isEmpty ? Color.green : Color.primary)
                if !session.missed.isEmpty {
                    Button("Bilemediklerimi yeniden sor", systemImage: "arrow.clockwise") { session.retryMissed() }
                    Button("Bilemediklerimi tekrar kartlarına ekle", systemImage: "rectangle.stack.badge.plus") {
                        let added = session.missed.filter { questions.indices.contains($0) }.filter {
                            LessonStudy.addCard(LessonCardDraft(front: questions[$0].question, back: questions[$0].answer), lesson: context.lesson, context: modelContext)
                        }.count
                        note = added > 0 ? "\(added) soru tekrar kartlarına eklendi." : "Bu sorular zaten kartlarında."
                    }
                } else {
                    Button("Baştan sor", systemImage: "arrow.clockwise") { session = ExamPrepSession(count: questions.count) }
                }
            }
        }
    }
}
