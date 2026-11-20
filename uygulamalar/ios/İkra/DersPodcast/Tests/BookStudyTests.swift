import Foundation
import SwiftData
import Testing
@testable import Ikra

@Suite @MainActor struct BookStudyTests {
    private func folder() throws -> URL {
        let value = FileManager.default.temporaryDirectory.appending(path: "OkuBookStudy-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: true)
        return value
    }

    private func container() throws -> ModelContainer {
        try ModelContainer(for: Schema(AppDataStore.modelTypes), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func notePersistsReopensAndEditingKeepsCreationDate() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "book-study.json"), store = BookStudyStore(url: root.appending(path: "book-study.json"))
        let created = Date(timeIntervalSince1970: 100)
        var note = BookStudyNote(bookID: " kitap-36 ", title: " Biyoloji ", page: 33, quote: " Hücre ", note: " Ayrıntı ", createdAt: created)
        try store.save(note)
        #expect(store.entries.count == 1 && store.entries[0].bookID == "kitap-36")
        #expect(store.entries[0].quote == "Hücre" && store.entries[0].note == "Ayrıntı")
        let first = store.entries[0]
        note.note = "Yeni açıklama"; note.createdAt = .now
        try store.save(note)
        #expect(store.entries[0].createdAt == created && store.entries[0].updatedAt > first.updatedAt)
        let reopened = BookStudyStore(url: file)
        #expect(reopened.loadError == nil && reopened.entries == store.entries)
        #expect(reopened.notes(for: "kitap-36").first?.page == 33)
    }

    @Test func bookmarkIsPerSourceAndPageAndRemovingItKeepsWrittenNote() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let store = BookStudyStore(url: root.appending(path: "book-study.json"))
        try store.toggleBookmark(bookID: "kitap-36", title: "Biyoloji", page: 4)
        #expect(store.isBookmarked(bookID: "kitap-36", page: 4))
        #expect(!store.isBookmarked(bookID: "kitap-36", page: 5) && !store.isBookmarked(bookID: "kitap-45", page: 4))
        var mark = try #require(store.entries.first); mark.note = "Tekrar oku"
        try store.save(mark)
        try store.toggleBookmark(bookID: "kitap-36", title: "Biyoloji", page: 4)
        #expect(store.entries.count == 1 && store.entries[0].note == "Tekrar oku" && !store.entries[0].isBookmark)
        try store.toggleBookmark(bookID: "kitap-45", title: "Fizik", page: 5)
        try store.toggleBookmark(bookID: "kitap-45", title: "Fizik", page: 5)
        #expect(store.entries.count == 1)
    }

    @Test func failedWriteNeverCommitsInMemoryOrChangesLastSavedFile() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let parent = root.appending(path: "notes", directoryHint: .isDirectory)
        let store = BookStudyStore(url: parent.appending(path: "book-study.json"))
        let note = BookStudyNote(bookID: "kitap-36", title: "Biyoloji", page: 1, note: "Özgün")
        try store.save(note)
        let prior = store.entries
        let moved = root.appending(path: "saved", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: parent, to: moved)
        try Data("folder blocked".utf8).write(to: parent)
        let before = try Data(contentsOf: moved.appending(path: "book-study.json"))
        var edit = note; edit.note = "Kaydedilemeyen"
        #expect(throws: (any Error).self) { try store.save(edit) }
        #expect(throws: (any Error).self) { try store.delete(id: note.id) }
        #expect(store.entries == prior)
        #expect(try Data(contentsOf: moved.appending(path: "book-study.json")) == before)
    }

    @Test func corruptedFileIsKeptAndMutationsWaitForReadableReload() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "book-study.json"), corrupt = Data("{not valid JSON".utf8)
        try corrupt.write(to: file)
        let store = BookStudyStore(url: file)
        #expect(store.loadError != nil && store.entries.isEmpty)
        let note = BookStudyNote(bookID: "kitap-36", title: "Biyoloji", page: 2, note: "Not")
        #expect(throws: (any Error).self) { try store.save(note) }
        #expect(throws: (any Error).self) { try store.delete(id: note.id) }
        #expect(throws: (any Error).self) { try store.toggleBookmark(bookID: "kitap-36", title: "Biyoloji", page: 2) }
        #expect(try Data(contentsOf: file) == corrupt)
        try BookStudyStore.encode([note]).write(to: file)
        try store.reload()
        #expect(store.loadError == nil && store.entries.count == 1)
    }

    @Test func reloadFailureKeepsPreviouslyLoadedNotes() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "book-study.json"), store = BookStudyStore(url: root.appending(path: "book-study.json"))
        try store.save(BookStudyNote(bookID: "kitap-36", title: "Biyoloji", page: 2, quote: "Alıntı"))
        let prior = store.entries
        try Data("[] broken".utf8).write(to: file)
        #expect(throws: (any Error).self) { try store.reload() }
        #expect(store.entries == prior && store.loadError != nil)
    }

    @Test func validationRejectsEmptyNotesInvalidPagesAndOversizedTextWithoutWriting() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "book-study.json"), store = BookStudyStore(url: root.appending(path: "book-study.json"))
        var note = BookStudyNote(bookID: "kitap-36", title: "Biyoloji", page: 1)
        #expect(throws: (any Error).self) { try store.save(note) }
        note.note = "Not"; note.page = 0
        #expect(throws: (any Error).self) { try store.save(note) }
        note.page = 1; note.bookID = "../outside"
        #expect(throws: (any Error).self) { try store.save(note) }
        note.bookID = "kitap-36"; note.quote = String(repeating: "ş", count: 12_001)
        #expect(throws: (any Error).self) { try store.save(note) }
        #expect(store.entries.isEmpty && !FileManager.default.fileExists(atPath: file.path))
    }

    @Test func duplicateRecordIDsAreRejectedAndSourceIDRemainsStable() throws {
        let note = BookStudyNote(bookID: "kitap-36", title: "Biyoloji", page: 1, note: "Not")
        let data = try JSONEncoder().encode([note, note])
        #expect(throws: (any Error).self) { try BookStudyStore.decode(data) }
        #expect(BookStudyStore.sourceID(for: "kitap-36").uuidString.lowercased() == "c1c410cc-8af2-81ae-90bc-04189566ed76")
        #expect(BookStudyStore.sourceID(for: "kitap-36") != BookStudyStore.sourceID(for: "program-36"))
        #expect(BookStudyStore.sourceID(for: "kitap-36") != ManualCards.deckID)
    }

    @Test func backupMergeUsesUpdatedAtAndKeepsLocalOnTies() throws {
        let early = Date(timeIntervalSince1970: 100), late = Date(timeIntervalSince1970: 200)
        let a = BookStudyNote(bookID: "kitap-36", title: "Biyoloji", page: 1, note: "Yerel", createdAt: early, updatedAt: late)
        let b = BookStudyNote(bookID: "kitap-36", title: "Biyoloji", page: 2, note: "Eski", createdAt: early, updatedAt: early)
        var oldA = a; oldA.note = "Geri alınmamalı"; oldA.updatedAt = early
        var freshB = b; freshB.note = "Yeni"; freshB.updatedAt = late
        let c = BookStudyNote(bookID: "kitap-45", title: "Fizik", page: 3, isBookmark: true)
        let current = try BookStudyStore.encode([a, b])
        let merge = try BookStudyStore.merge(existing: current, incoming: BookStudyStore.encode([oldA, freshB, c]))
        #expect(merge.changed == 2)
        #expect(try BookStudyStore.decode(merge.data) == [a, freshB, c])
        #expect(Backup.toolMergeIsSafe(store: "book-study", existing: current, merged: merge.data) == true)
        var tie = a; tie.note = "Eşit tarih"
        let tied = try BookStudyStore.merge(existing: current, incoming: BookStudyStore.encode([tie]))
        let tiedNotes = try BookStudyStore.decode(tied.data)
        #expect(tied.changed == 0 && tiedNotes == [a, b])
        #expect(Backup.toolMergeIsSafe(store: "book-study", existing: merge.data, merged: current) == false)
    }

    @Test func restoreMergesUpdatedNotesAndRefreshesAnOpenStore() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "backup"), target = root.appending(path: "local")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let store = BookStudyStore(url: target.appending(path: "book-study.json"))
        try store.save(BookStudyNote(bookID: "kitap-36", title: "Biyoloji", page: 2, note: "Önce"))
        var updated = try #require(store.entries.first)
        updated.note = "Sonra"; updated.updatedAt = updated.updatedAt.addingTimeInterval(60)
        try BookStudyStore.encode([updated]).write(to: source.appending(path: "book-study.json"))
        let count = Backup.restoreToolsAndNotify(from: source, to: target)
        #expect(count == 1 && store.entries.first?.note == "Sonra")
        #expect(Backup.restoreToolsAndNotify(from: source, to: target) == 0)
    }

    @Test func invalidBookNotesInBackupAreNotCopiedOrMerged() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "backup"), target = root.appending(path: "local")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("[{\"id\":\"broken\"}]".utf8).write(to: source.appending(path: "book-study.json"))
        #expect(Backup.restoreTools(from: source, to: target) == 0)
        #expect(!FileManager.default.fileExists(atPath: target.appending(path: "book-study.json").path))
    }

    @Test func sourceLinkedCardBackupRestoresMemoryAndLegacyDTOStillDecodes() throws {
        // A mainContext does not keep its temporary container alive. Hold both stores through every fetch/save.
        let sourceContainer = try container(), destinationContainer = try container()
        try withExtendedLifetime((sourceContainer, destinationContainer)) {
            let source = sourceContainer.mainContext
            let card = ReviewCard(episodeID: BookStudyStore.sourceID(for: "kitap-36"), episodeTitle: "Biyoloji", kind: .flashcard,
                                  front: "Hücrenin enerji organeli?", back: "Mitokondri", sourcePage: 33)
            card.sourceBookID = "kitap-36"; card.origin = "book"
            card.stability = 12.5; card.memoryDifficulty = 4.2; card.repetitions = 3
            source.insert(card); try source.save()
            var manifest = try Backup.manifest(context: source)
            // Test archive contains only its in-memory card, never the host app's preferences or tool files.
            manifest.preferences = nil; manifest.preferenceValues = nil
            let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
            try manifest.encoded().write(to: root.appending(path: "manifest.json"))
            let destination = destinationContainer.mainContext
            let restored = try Backup.restoreDetailed(from: root, context: destination)
            #expect(restored.cards == 1)
            let copy = try #require(destination.fetch(FetchDescriptor<ReviewCard>()).first)
            #expect(copy.sourceBookID == "kitap-36" && copy.sourcePage == 33 && copy.id == card.id)
            #expect(copy.stability == 12.5 && copy.memoryDifficulty == 4.2 && copy.repetitions == 3)
            var json = try #require(JSONSerialization.jsonObject(with: manifest.encoded()) as? [String: Any])
            var cards = try #require(json["cards"] as? [[String: Any]])
            cards[0].removeValue(forKey: "sourceBookID"); json["cards"] = cards
            let legacy = try BackupManifest.decode(JSONSerialization.data(withJSONObject: json))
            #expect(legacy.cards.first?.sourceBookID == nil && legacy.cards.first?.sourcePage == 33)
        }
    }
}
