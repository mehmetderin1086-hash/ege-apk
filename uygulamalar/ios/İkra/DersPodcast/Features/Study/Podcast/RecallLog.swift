import SwiftData
import SwiftUI

/// #27: tüm soru ve hatırlama sonuçlarının günlüğü. Yazdıktan sonra `.recallRecorded` yayılır.
enum RecallLog {
    struct Entry {
        var source: String
        var question: String
        var choices: [String] = []
        var chosenIndex: Int?
        var correctIndex: Int?
        var answerText: String?
        var isCorrect: Bool?
        var score: Double?
        var confidence: Int?
        var responseSeconds: Double?
        var chapterIndex: Int?
        var conceptKey: String?
        var cardID: UUID?
        var daysSinceListen: Int?
    }

    /// Soru öğesinden kayıt (şıklar, doğru şık ve konu dahil).
    static func entry(_ item: QuizItem, source: String, outcome: QuestionOutcome) -> Entry {
        Entry(source: source, question: item.question, choices: item.options, chosenIndex: outcome.chosenIndex,
              correctIndex: item.answerIndex >= 0 ? item.answerIndex : nil, answerText: outcome.answerText,
              isCorrect: outcome.isCorrect, score: outcome.score ?? outcome.isCorrect.map { $0 ? 1 : 0 },
              confidence: outcome.confidence, responseSeconds: outcome.seconds, chapterIndex: item.chapterIndex)
    }

    @discardableResult
    static func record(_ entry: Entry, episodeID: UUID?, episodeTitle: String, context: ModelContext, now: Date = .now) -> RecallAttempt {
        let attempt = RecallAttempt(source: entry.source, question: String(entry.question.prefix(1000)), episodeID: episodeID,
                                    episodeTitle: episodeTitle, chapterIndex: entry.chapterIndex)
        attempt.createdAt = now
        attempt.choices = entry.choices
        attempt.chosenIndex = entry.chosenIndex
        attempt.correctIndex = entry.correctIndex
        attempt.answerText = entry.answerText.map { String($0.prefix(3000)) }
        attempt.isCorrect = entry.isCorrect
        attempt.score = entry.score.map { min(1, max(0, $0)) }
        attempt.confidence = entry.confidence
        attempt.responseSeconds = entry.responseSeconds
        attempt.conceptKey = entry.conceptKey
        attempt.cardID = entry.cardID
        attempt.daysSinceListen = entry.daysSinceListen ?? episodeID.flatMap { daysSinceListen(episodeID: $0, context: context, now: now) }
        context.insert(attempt)
        do { try context.save(); LearningContinuity.recall(attempt) } catch { /* Primary save failed; do not publish secondary evidence. */ }
        PodcastEvent.post(PodcastEvent.recallRecorded, episodeID: episodeID)
        return attempt
    }

    @discardableResult
    static func record(_ entry: Entry, episode: Episode?, context: ModelContext) -> RecallAttempt {
        record(entry, episodeID: episode?.id, episodeTitle: episode?.title ?? "", context: context)
    }

    /// İlk bitişten bu yana geçen gün (takvim günü). Kesit ya da yeniden dinleme eğriyi sıfırlamaz.
    /// İlk bitiş = bölümün ilk yoklamasının kurulduğu an (`.episodeFinished`). Yoklaması olmayan eski bölümde
    /// bitmişse son dinleme kullanılır; hiç bitmemişse gün bilinmez (eğriye girmez).
    static func daysSinceListen(episodeID: UUID, context: ModelContext, now: Date = .now) -> Int? {
        guard let listened = firstFinishedAt(episodeID: episodeID, context: context) else { return nil }
        return days(from: listened, to: now)
    }

    static func firstFinishedAt(episodeID: UUID, context: ModelContext) -> Date? {
        let pid: UUID? = episodeID
        var probes = FetchDescriptor<EpisodeProbe>(predicate: #Predicate { $0.episodeID == pid && $0.kindRaw == "probe" },
                                                   sortBy: [SortDescriptor(\.createdAt)])
        probes.fetchLimit = 1
        if let first = (try? context.fetch(probes))?.first { return first.createdAt }
        let id = episodeID
        guard let episode = try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })).first,
              episode.isFinished else { return nil }
        return episode.lastPlayedAt
    }

    static func days(from: Date, to: Date, calendar: Calendar = .current) -> Int {
        max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0)
    }
}

/// Bir sorunun sonucu (QuestionCard → çağıran).
struct QuestionOutcome: Equatable {
    var chosenIndex: Int?
    var isCorrect: Bool?
    var score: Double?
    var confidence: Int?
    var answerText: String?
    var seconds: Double?
}

/// #27: eminlik seçimi (Tahmin / Sanırım / Eminim).
struct ConfidencePicker: View {
    @Binding var value: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ne kadar eminsin?").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(RecallStats.confidenceTitles.indices, id: \.self) { level in
                    Button {
                        value = value == level ? nil : level
                    } label: {
                        Text(RecallStats.confidenceTitles[level])
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(value == level ? AnyShapeStyle(Color.accentColor.opacity(0.22)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(value == level ? .isSelected : [])
                }
            }
        }
    }
}
