import Foundation
import SwiftData
import Testing
@testable import Ikra

@Suite struct BookCardDraftTests {
    @Test func hidesOnlySelectedRepeatedPhrase() throws {
        let text = "DNA eşlenir. DNA kalıtsal bilgiyi taşır."
        #expect(BookCardDraft.occurrenceCount(in: text, phrase: "DNA") == 2)
        let first = try BookCardDraft.cloze(quote: text, phrase: "DNA")
        let second = try BookCardDraft.cloze(quote: text, phrase: "DNA", occurrence: 1)
        #expect(first.front == "[Boşluk] eşlenir. DNA kalıtsal bilgiyi taşır.")
        #expect(second.front == "DNA eşlenir. [Boşluk] kalıtsal bilgiyi taşır.")
        #expect(first.back == "DNA" && second.back == "DNA")
    }

    @Test func preservesTurkishUnicodeAndEmojiAroundSelection() throws {
        let text = "🧬 Işık, İZ ve ışık farklı yazılır."
        let result = try BookCardDraft.cloze(quote: text, phrase: "İZ")
        #expect(result.front == "🧬 Işık, [Boşluk] ve ışık farklı yazılır.")
        #expect(result.back == "İZ")
        #expect(BookCardDraft.occurrenceCount(in: text, phrase: "ışık") == 1)
        #expect(BookCardDraft.occurrenceCount(in: text, phrase: "IŞIK") == 0)
        let accented = try BookCardDraft.cloze(quote: "Genetikte a\u{301} işareti korunur.", phrase: "a\u{301}")
        #expect(accented.back == "a\u{301}")
        #expect(accented.front == "Genetikte [Boşluk] işareti korunur.")
    }

    @Test func rejectsMissingAndAmbiguousInvalidInput() {
        #expect(throws: BookCardDraft.Problem.emptyPassage) { try BookCardDraft.cloze(quote: " \n", phrase: "DNA") }
        #expect(throws: BookCardDraft.Problem.emptyPhrase) { try BookCardDraft.cloze(quote: "DNA eşlenir.", phrase: " ") }
        #expect(throws: BookCardDraft.Problem.phraseNotFound) { try BookCardDraft.cloze(quote: "DNA eşlenir.", phrase: "RNA") }
        #expect(throws: BookCardDraft.Problem.invalidOccurrence) { try BookCardDraft.cloze(quote: "DNA eşlenir.", phrase: "DNA", occurrence: 1) }
        #expect(throws: BookCardDraft.Problem.invalidOccurrence) { try BookCardDraft.cloze(quote: "DNA eşlenir.", phrase: "DNA", occurrence: -1) }
        #expect(throws: BookCardDraft.Problem.entirePassage) { try BookCardDraft.cloze(quote: "DNA", phrase: "DNA") }
        #expect(BookCardDraft.occurrenceCount(in: "AAA", phrase: "") == 0)
    }

    @Test func manualCardTrimsEdgesButPreservesContent() throws {
        let draft = try BookCardDraft.manual(question: "  DNA nedir?\n", answer: " Kalıtsal bilgi.\nİkinci satır. ")
        #expect(draft.front == "DNA nedir?")
        #expect(draft.back == "Kalıtsal bilgi.\nİkinci satır.")
        #expect(throws: BookCardDraft.Problem.emptyQuestion) { try BookCardDraft.manual(question: " ", answer: "cevap") }
        #expect(throws: BookCardDraft.Problem.emptyAnswer) { try BookCardDraft.manual(question: "soru", answer: "\n") }
    }

    @MainActor @Test func savingKeepsSourceAndDeduplicatesWithinBook() throws {
        let container = try ModelContainer(for: ReviewCard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let source = BookStudyNote(bookID: "kitap-36", title: "Biyoloji", page: 34, quote: "DNA kalıtsal bilgiyi taşır.")
        let draft = try BookCardDraft.cloze(quote: source.quote, phrase: "DNA")
        let first = try BookCardWriter.save(draft, source: source, context: context)
        let second = try BookCardWriter.save(draft, source: source, context: context)
        #expect(first.created && !second.created && first.id == second.id)
        let saved = try #require(context.fetch(FetchDescriptor<ReviewCard>()).first)
        #expect(saved.sourceBookID == "kitap-36" && saved.sourcePage == 34)
        #expect(saved.episodeID == BookStudyStore.sourceID(for: "kitap-36"))
        #expect(saved.origin == "book" && saved.front == draft.front && saved.back == "DNA")
        let otherBook = BookStudyNote(bookID: "kitap-45", title: "Başka kitap", page: 2)
        #expect(try BookCardWriter.save(draft, source: otherBook, context: context).created)
        #expect(try context.fetchCount(FetchDescriptor<ReviewCard>()) == 2)
        var anotherPage = source
        anotherPage.page = 35
        let fromAnotherPage = try BookCardWriter.save(draft, source: anotherPage, context: context)
        #expect(fromAnotherPage.created && fromAnotherPage.id != first.id)
        let pageCard = try #require(context.fetch(FetchDescriptor<ReviewCard>()).first { $0.id == fromAnotherPage.id })
        #expect(pageCard.sourceBookID == source.bookID && pageCard.sourcePage == 35)
    }

    @MainActor @Test func validationDoesNotCommitUnrelatedPendingChanges() throws {
        let container = try ModelContainer(for: ReviewCard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let pending = ReviewCard(episodeID: UUID(), episodeTitle: "Taslak", kind: .flashcard, front: "Bekleyen", back: "Cevap", sourcePage: nil)
        context.insert(pending)
        let source = BookStudyNote(bookID: "kitap-36", title: "Biyoloji", page: 3)
        #expect(throws: BookCardDraft.Problem.emptyQuestion) {
            try BookCardWriter.save(.init(front: " ", back: "DNA"), source: source, context: context)
        }
        #expect(context.hasChanges && pending.modelContext != nil && !pending.isDeleted)
        let reader = ModelContext(container)
        #expect(try reader.fetchCount(FetchDescriptor<ReviewCard>()) == 0)
        _ = try BookCardWriter.save(.init(front: "Soru", back: "DNA"), source: source, context: context)
        #expect(context.hasChanges && pending.modelContext != nil && !pending.isDeleted)
        #expect(try reader.fetchCount(FetchDescriptor<ReviewCard>()) == 1)
    }
}
