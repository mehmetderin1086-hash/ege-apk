import Foundation
import Observation
import SwiftData

/// Süren çalışma paketi üretimleri. Aynı bölüm için ikinci istek yeni iş başlatmaz, sürene katılır: otomatik hazırlık
/// sürerken "Oluştur"a basılınca iki paket üretilip kartların ikisi de desteye girmesin.
@Observable
final class StudyBuilds {
    static let shared = StudyBuilds()

    /// Paketi şu an üretilen bölümler (Çalış ekranı "Hazırlanıyor…" gösterir).
    private(set) var active: Set<UUID> = []
    @ObservationIgnored private var tasks: [UUID: Task<Void, Error>] = [:]

    /// İş çağıranın görevine bağlı değildir: çağıran ekran kapansa da sürer, sonucu (ya da hatayı) bekleyen herkes alır.
    func run(_ id: UUID, _ work: @escaping @MainActor () async throws -> Void) async throws {
        if let running = tasks[id] { return try await running.value }
        let task = Task {
            defer { self.finish(id) }
            try await work()
        }
        tasks[id] = task
        active.insert(id)
        try await task.value
    }

    private func finish(_ id: UUID) {
        tasks[id] = nil
        active.remove(id)
    }
}

/// Çalışma paketi (quiz + kartlar + kavram haritası) ve slaytların üretimi; Çalış ekranı ve otomatik hazırlık ortak kullanır.
enum StudyMaterials {
    /// Bölüm başına aynı anda tek üretim (bkz. `StudyBuilds`).
    static func buildStudyPack(_ episode: Episode, context: ModelContext) async throws {
        try await StudyBuilds.shared.run(episode.id) { try await buildNow(episode, context: context) }
    }

    /// `learn2` varsa `/v1/study-v2` (konu/tur bağlı, kolaydan zora, tür tür ve doğrulanmış sorular), yoksa eski `/v1/study`.
    private static func buildNow(_ episode: Episode, context: ModelContext) async throws {
        guard let script = episode.script else { return }
        let quizCount = QualityMode.isMax ? 15 : 10, cardCount = QualityMode.isMax ? 20 : 15, conceptCount = QualityMode.isMax ? 20 : 15
        let level = episode.settings?.level.rawValue ?? "genel"
        let title = String(script.title.prefix(300)), notes = String(script.sourceNotes.prefix(15_000))
        let pack: StudyPack
        var cardChapters: [Int?] = []
        if AppState.current?.serverSupports("learn2") == true {
            let response = try await APIClient.shared.studyV2(StudyV2Request(
                title: title, sourceNotes: notes, level: level, quizCount: quizCount, flashcardCount: cardCount,
                conceptCount: conceptCount, transcript: nil, transcriptTurns: LearnPayload.transcriptTurns(episode.timeline),
                kinds: LearnPayload.allKinds, avoid: episode.study.map { LearnPayload.avoid($0.quiz) }, verify: true))
            pack = StudyPack(quiz: QuestionPicker.easyFirst(response.quiz), flashcards: response.pack.flashcards,
                             concepts: response.concepts, formulas: response.formulas)
            cardChapters = response.flashcards.map(\.chapterIndex)
        } else {
            let transcript = episode.timeline.map { LearnPayload.utf16Prefix($0.turns.map(\.text).joined(separator: "\n"), 20_000) }
            pack = try await APIClient.shared.study(StudyRequest(
                title: title, sourceNotes: notes, level: level, quizCount: quizCount, flashcardCount: cardCount,
                conceptCount: conceptCount, transcript: transcript))
        }
        guard !episode.isDeleted, episode.modelContext != nil else { return }
        // Beklerken bölüm yeniden üretildiyse paket eski metne aittir: yazılmaz.
        guard episode.script == script else { return }
        episode.study = pack
        if let concepts = pack.concepts { episode.concepts = ConceptLayout.unique(concepts) }
        ReviewDeck.add(flashcards: pack.flashcards, episode: episode, context: context, chapters: cardChapters)
        try? context.save()
    }

    static func buildSlides(_ episode: Episode, context: ModelContext) async throws {
        guard let script = episode.script, let timeline = episode.timeline else { return }
        let chapters = timeline.chapters.map { chapter in
            SlideChapter(title: chapter.title,
                         text: String(timeline.turns.filter { $0.chapterIndex == chapter.id }.map(\.text).joined(separator: " ").prefix(6000)))
        }
        let slides = try await APIClient.shared.slides(SlidesRequest(title: script.title, sourceNotes: String(script.sourceNotes.prefix(15_000)),
                                                                     chapters: Array(chapters.prefix(15))))
        guard !episode.isDeleted, episode.modelContext != nil else { return }
        episode.slides = slides
        try? context.save()
    }

    /// Bölüm hazır olunca (otomatik hazırlık açıksa): çalışma paketi + slaytlar, birbirinden bağımsız.
    static func prepare(_ episode: Episode, context: ModelContext) {
        guard QualityMode.autoStudy else { return }
        Task {
            if episode.study == nil { try? await buildStudyPack(episode, context: context) }
            if episode.slides == nil, UserDefaults.standard.object(forKey: "showSlides") as? Bool ?? true {
                try? await buildSlides(episode, context: context)
            }
        }
    }
}
