import SwiftData
import SwiftUI

/// #33: işaretlenen turlar (Bookmark.kind) ve canlı soru kayıtları (LiveExchange) kart önerisine dönüşür.
struct CardSuggestionsView: View {
    let episode: Episode
    @Environment(\.modelContext) private var context
    @State private var suggestions: [CardSuggestion] = []

    var body: some View {
        Group {
            if suggestions.isEmpty {
                ContentUnavailableView("Öneri yok", systemImage: "rectangle.stack.badge.plus",
                                       description: Text("Dinlerken \"anlamadım\" ya da \"önemli\" diye işaretlediğin turlar ve canlı sorduğun sorular burada karta dönüşür."))
            } else {
                List {
                    Section {
                        Button("Hepsini karta ekle (\(suggestions.count))", systemImage: "plus.rectangle.on.rectangle") {
                            suggestions.forEach(add)
                        }
                    }
                    Section {
                        ForEach(suggestions) { s in
                            VStack(alignment: .leading, spacing: 6) {
                                Label(s.sourceTitle, systemImage: s.symbol).font(.caption.bold()).foregroundStyle(.secondary)
                                Text(s.front).font(.subheadline.weight(.semibold))
                                Text(s.back).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                                HStack {
                                    if let time = s.time {
                                        Button(ListenAnchor.label(time), systemImage: "headphones") {
                                            LearningLinks.listen(episodeID: episode.id, at: time)
                                        }
                                        .buttonStyle(.borderless)
                                        .font(.caption)
                                    }
                                    Spacer()
                                    Button("Karta ekle") { add(s) }
                                        .buttonStyle(.borderedProminent)
                                        .font(.caption)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Kart önerileri")
        .onAppear(perform: load)
    }

    private func load() {
        let id = episode.id
        let optional: UUID? = id
        let marks = (try? context.fetch(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.episodeID == id }))) ?? []
        let live = (try? context.fetch(FetchDescriptor<LiveExchange>(predicate: #Predicate { $0.episodeID == optional }))) ?? []
        let existing = Set(((try? context.fetch(FetchDescriptor<ReviewCard>(predicate: #Predicate { $0.episodeID == id }))) ?? []).map(\.front))
        suggestions = CardSuggestion.make(bookmarks: marks.map { .init(kind: $0.kind, text: $0.text, note: $0.note, time: $0.time, chapter: $0.chapterIndex) },
                                          live: live.map { .init(question: $0.question, answer: $0.answer, time: $0.time, chapter: $0.chapterIndex) },
                                          existingFronts: existing)
    }

    private func add(_ s: CardSuggestion) {
        let card = ReviewCard(episodeID: episode.id, episodeTitle: episode.title, kind: .flashcard, front: s.front, back: s.back, sourcePage: nil)
        card.origin = s.origin
        card.episodeTime = s.time
        card.chapterIndex = s.chapter
        context.insert(card)
        try? context.save()
        ReviewReminder.ensureScheduled()
        suggestions.removeAll { $0.id == s.id }
    }
}

nonisolated struct CardSuggestion: Identifiable, Hashable, Sendable {
    struct Mark: Sendable { var kind: String; var text: String; var note: String; var time: Double; var chapter: Int? }
    struct Live: Sendable { var question: String; var answer: String; var time: Double?; var chapter: Int? }

    var id: String { origin + front }
    var origin: String
    var front: String
    var back: String
    var time: Double?
    var chapter: Int?

    var symbol: String { origin == "live" ? "bubble.left.and.text.bubble.right" : "bookmark" }
    var sourceTitle: String { origin == "live" ? "Canlı soru" : "İşaretlediğin tur" }

    /// "note" türü (düz yer imi) öneri olmaz; aynı ön yüzlü kart varsa atlanır.
    static func make(bookmarks: [Mark], live: [Live], existingFronts: Set<String>) -> [CardSuggestion] {
        var out: [CardSuggestion] = []
        for mark in bookmarks where mark.kind != "note" && !mark.text.isEmpty {
            let excerpt = mark.text.count > 160 ? String(mark.text.prefix(160)) + "…" : mark.text
            let front = mark.note.isEmpty ? "Bu kısımda anlatılanı kendi cümlelerinle açıkla: “\(excerpt)”" : mark.note
            out.append(CardSuggestion(origin: "suggestion", front: front, back: mark.text, time: mark.time, chapter: mark.chapter))
        }
        for item in live where !item.question.isEmpty && !item.answer.isEmpty {
            out.append(CardSuggestion(origin: "live", front: item.question, back: item.answer, time: item.time, chapter: item.chapter))
        }
        var seen = existingFronts
        return out.filter { seen.insert($0.front).inserted }
    }
}
