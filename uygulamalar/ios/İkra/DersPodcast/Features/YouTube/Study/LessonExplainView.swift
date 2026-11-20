import SwiftData
import SwiftUI

/// "Anlamadım" (#19): son ~90 saniyeyi daha basit anlatır, örnek verir; yer zayıf nokta olarak yanlış defterine düşer.
struct ExplainView: View {
    var context: LessonContext
    var time: Double

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var phase: StudyPhase<StudyExplanation> = .idle
    @State private var cardAdded = false
    @State private var task: Task<Void, Never>?

    private var topic: String {
        StudyText.chapterIndex(context.sortedChapters, at: time).map { context.sortedChapters[$0].title } ?? context.lesson.title
    }

    var body: some View {
        StudySheet(title: "Anlamadım") {
            switch phase {
            case .idle, .loading:
                StudyLoadingView(message: "Son bölüm daha basit anlatılıyor…", onCancel: { dismiss() })
            case .failed(let message):
                StudyErrorView(message: message, retry: load)
            case .loaded(let result):
                explanation(result)
            }
        }
        .task { if case .idle = phase { load() } }
        .onAppear { context.pausePlayback() }
        .onDisappear { task?.cancel() }
    }

    private func explanation(_ result: StudyExplanation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("\(TranscriptFormat.timestamp(time)) · \(topic)", systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(result.explanation).font(.body).fixedSize(horizontal: false, vertical: true)
                if !result.example.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Örnek", systemImage: "lightbulb").font(.subheadline.bold()).foregroundStyle(.orange)
                        Text(result.example).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if !result.keyTerms.isEmpty {
                    Text("Anahtar terimler").font(.subheadline.bold())
                    StudyTags(terms: result.keyTerms)
                }
                Text("Bu yer zayıf noktalarına eklendi (Yanlış defteri).").font(.caption).foregroundStyle(.secondary)
                VStack(spacing: 10) {
                    Button("Devam et") {
                        dismiss()
                        context.resume(at: time)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button("90 sn geriden yeniden izle", systemImage: "gobackward") {
                        dismiss()
                        context.resume(at: max(0, time - 90))
                    }
                    .buttonStyle(.bordered)
                    Button(cardAdded ? "Karta eklendi" : "Kart olarak ekle", systemImage: cardAdded ? "checkmark" : "rectangle.on.rectangle") {
                        addCard(result)
                    }
                    .buttonStyle(.bordered)
                    .disabled(cardAdded)
                }
            }
            .padding(16)
        }
    }

    private func load() {
        task?.cancel()
        let text = StudyText.recentLines(context.transcript.paragraphs, endingAt: time)
        guard !text.isEmpty else {
            phase = .failed("Bu an için metin bulunamadı.")
            return
        }
        phase = .loading
        let request = StudyExplainRequest(title: context.lesson.title, text: text, time: time)
        // Ağ beklenirken ders silinebilir: kayıt için ders kimlikle yeniden çekilir.
        let lessonID = context.lesson.id
        let topicName = topic
        task = Task {
            do {
                let result = try await APIClient.shared.studyExplain(request)
                try Task.checkCancellation()
                guard !result.explanation.isEmpty else {
                    phase = .failed("Açıklama hazırlanamadı. Lütfen tekrar dene.")
                    return
                }
                phase = .loaded(result)
                if let live = VideoLessonView.liveLesson(id: lessonID, in: modelContext) {
                    LessonStudy.recordConfused(time: time, topic: topicName, explanation: result.explanation, example: result.example,
                                               lesson: live, context: modelContext)
                }
            } catch {
                if let message = StudyError.message(error) { phase = .failed(message) }
            }
        }
    }

    private func addCard(_ result: StudyExplanation) {
        guard context.lesson.modelContext != nil else { return }
        let back = result.example.isEmpty ? result.explanation : result.explanation + "\n\nÖrnek: " + result.example
        let clip = ClipRange(start: max(0, time - 90), end: time)
        let draft = LessonCardDraft(front: "\(topic) (\(TranscriptFormat.timestamp(time))): ne anlatılıyor?", back: back)
        LessonStudy.addCard(draft, lesson: context.lesson, context: modelContext, clip: clip)
        cardAdded = true   // aynı kart zaten varsa da eklenmiş sayılır
    }
}
