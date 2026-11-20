import SwiftData
import SwiftUI

/// #28: bölüm başına yoklama takvimi. Bölüm bitince `policy.probeStages` günlerine yoklama kurulur
/// (sınava 14 günden az kaldıysa sıkışır); puan < 0,6 ise yeniden dinleme görevi eklenir.
enum ProbeAdvisor {
    /// Bölüm bitti: açık yoklaması yoksa takvimi kurar.
    static func scheduleProbes(for episode: Episode, context: ModelContext, now: Date = .now,
                               stages: [Int] = ListeningMode.current.policy.probeStages, plan: StudyPlan? = StudyPlan.current) {
        let id: UUID? = episode.id
        let existing = (try? context.fetch(FetchDescriptor<EpisodeProbe>(predicate: #Predicate { $0.episodeID == id && $0.completedAt == nil }))) ?? []
        guard !existing.contains(where: { $0.kindRaw == "probe" }) else { return }
        let daysToExam = plan.flatMap { $0.examDate > now ? RecallLog.days(from: now, to: $0.examDate) : nil }
        for stage in ProbeScheduler.stages(stages, daysToExam: daysToExam) {
            let probe = EpisodeProbe(episodeID: episode.id, episodeTitle: episode.title,
                                     dueDate: ProbeScheduler.dueDate(stage: stage, listenedAt: now), stage: stage)
            probe.createdAt = now   // dinleme (bitiş) anı: kalıcılık eğrisi buradan sayar
            context.insert(probe)
        }
        try? context.save()
    }

    /// Bölüm yeniden dinlendi: açık "yeniden dinle" görevleri kapanır.
    static func completeRelisten(episodeID: UUID, context: ModelContext, now: Date = .now) {
        let id: UUID? = episodeID
        let open = (try? context.fetch(FetchDescriptor<EpisodeProbe>(predicate: #Predicate { $0.episodeID == id && $0.completedAt == nil }))) ?? []
        var changed = false
        for probe in open where probe.kindRaw == "relisten" {
            probe.completedAt = now
            changed = true
        }
        if changed { try? context.save() }
    }

    /// Yoklama bitti: vadesi gelmiş yoklamalar kapanır; puan düşükse yeniden dinleme görevi eklenir.
    static func finish(episodeID: UUID, score: Double, context: ModelContext, now: Date = .now) {
        let id: UUID? = episodeID
        let open = (try? context.fetch(FetchDescriptor<EpisodeProbe>(predicate: #Predicate { $0.episodeID == id && $0.completedAt == nil }))) ?? []
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        var due = open.filter { $0.kindRaw == "probe" && $0.dueDate < endOfDay }
        if due.isEmpty, let next = open.filter({ $0.kindRaw == "probe" }).min(by: { $0.dueDate < $1.dueDate }) { due = [next] }
        for probe in due {
            probe.completedAt = now
            probe.score = score
        }
        if score < ProbeScheduler.relistenThreshold, !open.contains(where: { $0.kindRaw == "relisten" }) {
            let title = due.first?.episodeTitle ?? open.first?.episodeTitle ?? ""
            let task = EpisodeProbe(episodeID: episodeID, episodeTitle: title, dueDate: now, stage: due.first?.stage ?? 0, kind: "relisten")
            task.score = score
            context.insert(task)
        }
        try? context.save()
    }

    /// Yoklama soruları: şıklı, konulara yayılmış; önceki yoklamalarda doğru bilinenler (yeterince soru varsa) atlanır.
    static func questions(for episode: Episode, context: ModelContext, count: Int = 5) -> [QuizItem] {
        let quiz = episode.study?.quiz ?? []
        let id: UUID? = episode.id
        let known = Set(((try? context.fetch(FetchDescriptor<RecallAttempt>(predicate: #Predicate { $0.episodeID == id }))) ?? [])
            .filter { $0.source == "probe" && $0.isCorrect == true }.map(\.question))
        let fresh = QuestionPicker.spread(quiz, count: count, excluding: known)
        return fresh.count >= min(3, count) ? fresh : QuestionPicker.spread(quiz, count: count)
    }
}

struct ProbeSessionView: View {
    let episodeID: UUID
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var episode: Episode?
    @State private var items: [QuizItem] = []
    @State private var stage: Int?
    @State private var score: Double?
    @State private var preparing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let episode {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(episode.title).font(.title3.bold())
                            Text(stage.map { "\($0). gün yoklaması: dinlediklerinden aklında ne kaldı?" } ?? "Hatırlama yoklaması")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let score {
                            summary(score, episode: episode)
                        } else if items.isEmpty {
                            empty(episode)
                        } else {
                            QuestionRun(items: items, episode: episode, source: "probe",
                                        showConfidence: ListeningMode.current.policy.confidence,
                                        onListen: { time in dismiss(); LearningLinks.listen(episodeID: episode.id, at: time) }) { outcomes in
                                let value = Double(outcomes.filter { $0.isCorrect == true }.count) / Double(max(1, outcomes.count))
                                ProbeAdvisor.finish(episodeID: episode.id, score: value, context: context)
                                score = value
                            }
                        }
                    } else {
                        ContentUnavailableView("Bekleyen yoklama yok", systemImage: "checkmark.seal",
                                               description: Text("Bölüm silinmiş olabilir."))
                    }
                    if let error { Text(error).font(.callout).foregroundStyle(.red) }
                }
                .padding(20)
            }
            .navigationTitle("Yoklama")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
        }
        .onAppear(perform: load)
    }

    private func summary(_ score: Double, episode: Episode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("%\(Int((score * 100).rounded()))").font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(score >= ProbeScheduler.relistenThreshold ? .green : .orange)
            Text(score >= ProbeScheduler.relistenThreshold
                 ? "Kalıcı görünüyor. Sıradaki yoklama takvimde."
                 : "Unutmaya başlamışsın: bölümü yeniden dinlemen iyi olur. Yanlışlar tekrar destende.")
                .font(.callout).foregroundStyle(.secondary)
            if score < ProbeScheduler.relistenThreshold {
                Button("Şimdi yeniden dinle", systemImage: "headphones") {
                    dismiss()
                    AppState.current?.open(episode.id, at: 0, play: true)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func empty(_ episode: Episode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bu bölümün sorusu yok. Önce soruları hazırla.").font(.callout).foregroundStyle(.secondary)
            Button {
                Task {
                    preparing = true
                    error = nil
                    defer { preparing = false }
                    do {
                        try await StudyMaterials.buildStudyPack(episode, context: context)
                        items = ProbeAdvisor.questions(for: episode, context: context)
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            } label: {
                HStack { if preparing { ProgressView() }; Text("Soruları hazırla") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(preparing)
        }
    }

    private func load() {
        guard episode == nil else { return }
        let id = episodeID
        episode = try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })).first
        guard let episode else { return }
        items = ProbeAdvisor.questions(for: episode, context: context)
        let optional: UUID? = id
        stage = ((try? context.fetch(FetchDescriptor<EpisodeProbe>(predicate: #Predicate { $0.episodeID == optional && $0.completedAt == nil }))) ?? [])
            .filter { $0.kindRaw == "probe" }.min { $0.dueDate < $1.dueDate }?.stage
    }
}
