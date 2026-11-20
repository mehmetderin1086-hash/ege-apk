import Foundation
import SwiftData
import SwiftUI

nonisolated struct TutorDeck: Codable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var subject: String
    var cards: [TutorDeckCard]
    var createdAt = Date()
}

nonisolated struct TutorDeckCard: Codable, Identifiable, Sendable {
    var id = UUID()
    var front: String
    var back: String
}

nonisolated enum TutorCardParser {
    enum Problem: LocalizedError, Equatable {
        case malformed, count, empty, tooLong, duplicate
        var errorDescription: String? {
            switch self {
            case .malformed: "Kart yanıtı okunamadı. Yeniden oluşturmayı dene."
            case .count: "Yanıttaki kart sayısı istenen sayıyla eşleşmiyor. Yeniden dene."
            case .empty: "Yanıtta sorusu veya cevabı boş bir kart var. Yeniden dene."
            case .tooLong: "Kart yanıtı fazla uzun. Kaynağı daraltarak yeniden dene."
            case .duplicate: "Yanıtta aynı soru birden fazla kez var. Yeniden dene."
            }
        }
    }
    private struct Response: Decodable {
        struct Card: Decodable { var front: String; var back: String }
        var cards: [Card]
    }
    static func parse(_ text: String, expectedCount: Int) throws -> [TutorDeckCard] {
        guard (5...20).contains(expectedCount) else { throw Problem.count }
        guard text.utf8.count <= 100_000 else { throw Problem.tooLong }
        var json = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```"), json.hasSuffix("```"), let newline = json.firstIndex(of: "\n") {
            json = String(json[json.index(after: newline)...].dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: Data(json.utf8)) else { throw Problem.malformed }
        guard response.cards.count == expectedCount else { throw Problem.count }
        var questions = Set<String>()
        return try response.cards.map { card in
            let front = card.front.trimmingCharacters(in: .whitespacesAndNewlines)
            let back = card.back.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty, !back.isEmpty else { throw Problem.empty }
            guard front.count <= 1_000, back.count <= 2_000 else { throw Problem.tooLong }
            let key = front.folding(options: [.caseInsensitive], locale: Locale(identifier: "tr_TR"))
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard questions.insert(key).inserted else { throw Problem.duplicate }
            return TutorDeckCard(front: front, back: back)
        }
    }
}

@MainActor enum TutorCardWriter {
    /// Dedicated context avoids committing unrelated edits; stable deck ID prevents re-import duplicates.
    static func save(_ deck: TutorDeck, context: ModelContext) throws -> Int {
        let writer = ModelContext(context.container)
        writer.autosaveEnabled = false
        let deckID = deck.id
        let existing = try writer.fetch(FetchDescriptor<ReviewCard>(predicate: #Predicate { $0.episodeID == deckID }))
        var keys = Set(existing.map { CardImport.key(front: $0.front, back: $0.back) })
        var added = 0
        do {
            for item in deck.cards {
                guard keys.insert(CardImport.key(front: item.front, back: item.back)).inserted else { continue }
                let card = ReviewCard(episodeID: deck.id, episodeTitle: deck.title, kind: .flashcard,
                                      front: item.front, back: item.back, sourcePage: nil)
                card.origin = "tutor"
                writer.insert(card)
                added += 1
            }
            if added > 0 { try writer.save() }
            return added
        } catch { writer.rollback(); throw error }
    }
}

struct TutorCardsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var store = JSONStore<TutorDeck>("tutor-decks")
    @State private var topic = ""
    @State private var source = ""
    @State private var subject = "Biyoloji"
    @State private var count = 10
    @State private var busy = false
    @State private var error: String?
    @State private var request: Task<Void, Never>?
    @State private var selected: TutorDeck?

    var body: some View {
        NavigationStack {
            Form {
                Section("Yeni deste") {
                    TextField("Konu veya kaynak başlığı", text: $topic, axis: .vertical).lineLimit(1...3)
                    Picker("Ders", selection: $subject) { ForEach(TutorHub.subjects, id: \.self) { Text($0) } }
                    TextField("Kaynak metni (isteğe bağlı)", text: $source, axis: .vertical).lineLimit(4...10)
                    Text("En çok 24.000 karakter kaynak ekleyebilirsin. Kartlar yapay zekâyla hazırlanır; cevapları kaynağınla kontrol et.")
                        .font(.caption).foregroundStyle(.secondary)
                    Stepper("\(count) kart", value: $count, in: 5...20)
                }.disabled(busy)
                Section {
                    if busy {
                        ProgressView("Kartlar hazırlanıyor…")
                        Button("Durdur") { request?.cancel() }
                    } else {
                        Button("Kartları oluştur", systemImage: "rectangle.on.rectangle") { generate() }
                            .disabled(topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                if !store.items.isEmpty {
                    Section("Kaydedilen desteler") {
                        ForEach(store.items.sorted { $0.createdAt > $1.createdAt }) { deck in
                            Button { selected = deck } label: {
                                VStack(alignment: .leading) {
                                    Text(deck.title)
                                    Text("\(deck.subject) · \(deck.cards.count) kart").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bilgi kartları")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
            .sheet(item: $selected) { deck in TutorDeckStudyView(deck: deck) }
            .onDisappear { request?.cancel() }
        }
    }

    private func generate() {
        let title = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !busy else { return }
        guard title.count <= 200, source.count <= 24_000 else {
            error = "Başlık en çok 200, kaynak en çok 24.000 karakter olabilir."; return
        }
        let requestedCount = count
        let selectedSubject = subject
        let sourceText = source
        error = nil
        busy = true
        request = Task {
            defer { busy = false }
            do {
                let prompt = "Konu: \(title)\nTam \(requestedCount) bilgi kartı oluştur.\nKaynak metni:\n\(sourceText)"
                let answer = try await TutorEngine.reply(mode: .cardDeck, subject: selectedSubject, level: "Lise / TYT-AYT",
                                                        messages: [.init(role: "user", text: prompt)])
                let cards = try TutorCardParser.parse(answer, expectedCount: requestedCount)
                try Task.checkCancellation()
                let deck = TutorDeck(title: title, subject: selectedSubject, cards: cards)
                store.items.append(deck)
                selected = deck
            } catch is CancellationError { error = "Kart oluşturma durduruldu. Yeniden deneyebilirsin." }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct TutorDeckStudyView: View {
    let deck: TutorDeck
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var revealed = false
    @State private var again: [TutorDeckCard] = []
    @State private var round: [TutorDeckCard] = []
    @State private var known = 0
    @State private var saveMessage: String?
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if index < round.count {
                        Text("Kart \(index + 1) / \(round.count)").font(.headline)
                        ProgressView(value: Double(index), total: Double(max(1, round.count)))
                        Button { revealed.toggle() } label: {
                            VStack(spacing: 20) {
                                Text(revealed ? "Cevap" : "Soru").font(.caption).foregroundStyle(.secondary)
                                Text(revealed ? round[index].back : round[index].front)
                                    .font(.title3).frame(maxWidth: .infinity, minHeight: 190)
                                Text(revealed ? "Soruyu göster" : "Cevabı görmek için dokun").font(.caption)
                            }.padding().background(.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain)
                        if revealed {
                            HStack {
                                Button("Tekrar çalış") { rate(remembered: false) }.buttonStyle(.bordered)
                                Button("Bildim") { rate(remembered: true) }.buttonStyle(.borderedProminent)
                            }
                        }
                    } else {
                        Label("Tur tamamlandı", systemImage: "checkmark.circle").font(.title2)
                        Text("Bu turda \(known) kartı bildim, \(again.count) kartı tekrar çalış seçtin.")
                        Text("Bu sayılar kendi değerlendirmen; kalıcı öğrenme puanı değildir.")
                            .font(.caption).foregroundStyle(.secondary)
                        if !again.isEmpty { Button("\(again.count) kartı yeniden çalış") { start(again) } }
                        Button("Tüm desteyi yeniden çalış") { start(deck.cards) }
                    }
                    Divider()
                    Button("Aralıklı tekrara ekle", systemImage: "calendar.badge.plus") {
                        do {
                            let added = try TutorCardWriter.save(deck, context: context)
                            saveMessage = added == 0 ? "Bu deste zaten aralıklı tekrarda." : "\(added) kart aralıklı tekrara eklendi."
                            saveError = nil
                        } catch { saveError = "Kartlar kaydedilemedi: \(error.localizedDescription)" }
                    }
                    if let saveMessage { Text(saveMessage).font(.callout).foregroundStyle(.green) }
                    if let saveError { Text(saveError).font(.callout).foregroundStyle(.red) }
                }.padding()
            }
            .navigationTitle(deck.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
            .onAppear { if round.isEmpty { start(deck.cards) } }
        }
    }
    private func start(_ cards: [TutorDeckCard]) {
        round = cards; index = 0; known = 0; again = []; revealed = false
    }
    private func rate(remembered: Bool) {
        guard revealed, index < round.count else { return }
        if remembered { known += 1 } else { again.append(round[index]) }
        index += 1; revealed = false
    }
}
