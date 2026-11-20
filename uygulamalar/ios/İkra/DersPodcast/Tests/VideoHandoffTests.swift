import Foundation
import SwiftData
import Testing
@testable import Ikra

// Soru Çöz ve konu videosu kayıtlarının Ders Video için ortak klasöre bırakılması.
@Suite @MainActor struct VideoHandoffTests {
    private func scratch() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "video-handoff-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func leavesTheArchiveFoldersAndPreferencesThenStops() throws {
        let support = try scratch(), destination = try scratch().appending(path: "OkuAktarim")
        let preferences = UserDefaults(suiteName: "video-handoff-\(UUID().uuidString)")!
        preferences.set("YKS", forKey: "questions.level"); preferences.set("Kore", forKey: "topic.voiceA"); preferences.set("x", forKey: "coach.other")
        for name in ["DersdasQuestions.store", "DersdasQuestions.store-wal", "QuestionStudio/anlatim/lesson.json", "TopicVideos/video/meta.json", "Tools/kalir.json"] {
            let file = support.appending(path: name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(name.utf8).write(to: file)
        }
        let id = UUID()
        #expect(VideoHandoff.export(from: support, to: destination, preferences: preferences, installID: id))
        #expect(try String(contentsOf: destination.appending(path: VideoHandoff.installFile), encoding: .utf8) == id.uuidString.lowercased())
        let files = FileManager.default
        for name in ["DersdasQuestions.store", "DersdasQuestions.store-wal", "QuestionStudio/anlatim/lesson.json", "TopicVideos/video/meta.json", VideoHandoff.marker] {
            #expect(files.fileExists(atPath: destination.appending(path: name).path), "\(name)")
        }
        // Oku'nun kendi verisi bırakılmaz; kayıtlar Oku'dan silinmez; yarım klasör kalmaz.
        #expect(!files.fileExists(atPath: destination.appending(path: "Tools").path))
        #expect(files.fileExists(atPath: support.appending(path: "QuestionStudio/anlatim/lesson.json").path))
        #expect(!files.fileExists(atPath: destination.deletingLastPathComponent().appending(path: "OkuAktarim.tmp").path))
        let saved = try PropertyListSerialization.propertyList(from: Data(contentsOf: destination.appending(path: VideoHandoff.preferencesFile)), format: nil) as? [String: String]
        #expect(saved == ["questions.level": "YKS", "topic.voiceA": "Kore"])
        // Bir kez: işaret varken yeniden bırakılmaz.
        #expect(!VideoHandoff.export(from: support, to: destination, preferences: preferences, installID: id))
        // Kimlik eklenmeden önce bırakılmış klasör: kimlik eklenir, işaret yenilenir (Ders Video yeniden alsın), başka şeye dokunulmaz.
        let before = try String(contentsOf: destination.appending(path: VideoHandoff.marker), encoding: .utf8)
        try FileManager.default.removeItem(at: destination.appending(path: VideoHandoff.installFile))
        try Data("eski".utf8).write(to: destination.appending(path: VideoHandoff.marker))
        #expect(VideoHandoff.export(from: support, to: destination, preferences: preferences, installID: id))
        #expect(try String(contentsOf: destination.appending(path: VideoHandoff.installFile), encoding: .utf8) == id.uuidString.lowercased())
        #expect(try String(contentsOf: destination.appending(path: VideoHandoff.marker), encoding: .utf8) != "eski" && !before.isEmpty)
        #expect(files.fileExists(atPath: destination.appending(path: "TopicVideos/video/meta.json").path))
    }

    /// App Group yetkisi varken adressiz depo ortak klasöre giderdi; ana depo uygulamanın kendi klasöründe kalmalı.
    @Test func theMainStoreStaysInTheAppsOwnFolder() {
        #expect(AppDataStore.storeURL == URL.applicationSupportDirectory.appending(path: "default.store"))
        #expect(AppDataStore.container.configurations.map(\.url) == [AppDataStore.storeURL])
    }

    @Test func onlySolverAndTopicVideoStudyRecordsAreLeftAndTheMarkerIsRefreshed() throws {
        let destination = try scratch().appending(path: "OkuAktarim")
        let schema = Schema(AppDataStore.modelTypes)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let topic = UUID()
        context.insert(ReviewCard(episodeID: UUID(), episodeTitle: "Soru Çöz · Fizik", kind: .flashcard, front: "soru kartı", back: "c", sourcePage: nil))
        context.insert(ReviewCard(episodeID: topic, episodeTitle: "Fotosentez", kind: .flashcard, front: "konu kartı", back: "c", sourcePage: nil))
        context.insert(ReviewCard(episodeID: UUID(), episodeTitle: "Podcast bölümü", kind: .quiz, front: "podcast kartı", back: "c", sourcePage: nil))
        context.insert(MistakeEntry(question: "soru yanlışı", myAnswer: "a", correctAnswer: "b", source: "question-solver", episodeTitle: "Soru Çöz"))
        context.insert(MistakeEntry(question: "quiz yanlışı", myAnswer: "a", correctAnswer: "b", source: "quiz"))
        // Klasör henüz bırakılmadıysa (işaret yok) kartlar da bırakılmaz.
        #expect(!VideoHandoff.exportStudy(context: context, to: destination, topicIDs: [topic]))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("eski".utf8).write(to: destination.appending(path: VideoHandoff.marker))
        #expect(VideoHandoff.exportStudy(context: context, to: destination, topicIDs: [topic]))
        let study = try JSONDecoder().decode(VideoHandoff.Study.self, from: Data(contentsOf: destination.appending(path: VideoHandoff.studyFile)))
        #expect(Set(study.cards.map(\.front)) == ["soru kartı", "konu kartı"] && study.mistakes.map(\.question) == ["soru yanlışı"])
        #expect(try String(contentsOf: destination.appending(path: VideoHandoff.marker), encoding: .utf8) != "eski")
        // Bir kez; kayıtlar Oku'dan silinmez.
        #expect(!VideoHandoff.exportStudy(context: context, to: destination, topicIDs: [topic]))
        #expect(try context.fetch(FetchDescriptor<ReviewCard>()).count == 3)
    }

    @Test func nothingIsLeftWhenThereIsNoArchiveOrNoSharedFolder() throws {
        let support = try scratch(), destination = try scratch().appending(path: "OkuAktarim")
        #expect(!VideoHandoff.export(from: support, to: destination))
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        try Data().write(to: support.appending(path: "DersdasQuestions.store"))
        #expect(!VideoHandoff.export(from: support, to: nil))
    }
}
