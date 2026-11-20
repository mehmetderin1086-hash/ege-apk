#if DEBUG
import Foundation
import SwiftData

/// Yalnızca Debug: `-followDemo` ile Documents/follow-demo/{transcript.json, audio.m4a} dosyalarından
/// gerçek bir YouTube dersi ve aynı sesle bir podcast bölümü oluşturur; okuma takibini simülatörde denemek için.
/// `-openFollowDemo=video|podcast` ilgili ekranı açar, `-autoplayDemo` oynatmayı başlatır.
enum FollowDemo {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-followDemo") }
    static var autoplay: Bool { ProcessInfo.processInfo.arguments.contains("-autoplayDemo") }
    static var open: String? {
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix("-openFollowDemo=") }?.replacingOccurrences(of: "-openFollowDemo=", with: "")
    }
    static let episodeTitle = "Okuma takibi · demo"

    @MainActor
    static func seed(context: ModelContext) -> (lesson: VideoLesson?, episode: Episode?) {
        let root = URL.documentsDirectory.appending(path: "follow-demo")
        let audio = root.appending(path: "audio.m4a")
        guard let data = try? Data(contentsOf: root.appending(path: "transcript.json")),
              let status = try? JSONDecoder().decode(YouTubeJobStatus.self, from: data), let transcript = status.result,
              FileManager.default.fileExists(atPath: audio.path) else { return (nil, nil) }

        // YouTube dersi (ses kipi: gömülü oynatma kapalı, ses dosyası hazır).
        let lesson: VideoLesson
        if let existing = try? context.fetch(FetchDescriptor<VideoLesson>()).first(where: { $0.videoID == transcript.video.id }) {
            lesson = existing
        } else {
            lesson = VideoLesson(url: transcript.video.url, info: transcript.video)
            lesson.transcript = transcript
            lesson.embeddable = false
            context.insert(lesson)
        }
        _ = VideoFiles.directory(for: lesson.id)   // klasörü oluşturur
        let target = VideoFiles.audioURL(lesson: lesson.id)
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.copyItem(at: audio, to: target)
        lesson.audioFileName = target.lastPathComponent
        lesson.lastPosition = 0

        // Podcast bölümü: her paragraf bir tur (konuşmacılar dönüşümlü), zamanlar transkriptten.
        let episode: Episode
        if let existing = try? context.fetch(FetchDescriptor<Episode>()).first(where: { $0.title == episodeTitle }) {
            episode = existing
        } else {
            let paragraphs = transcript.paragraphs
            let turns = paragraphs.enumerated().map { i, p in ScriptTurn(speaker: i % 2 == 0 ? .a : .b, text: p.text, style: "", sourcePage: nil) }
            let script = PodcastScript(title: episodeTitle, summary: transcript.video.title, keyPoints: [],
                                       chapters: [.init(title: transcript.video.title, scenes: [.init(turns: turns)])], sourceNotes: "")
            episode = Episode(script: script, settings: PodcastSettings(speechProvider: "apple"), sourceNames: ["demo"], jobToken: "")
            episode.jobToken = nil
            var chapters: [TimedChapter] = transcript.chapters.enumerated().map { TimedChapter(id: $0.offset, title: $0.element.title, start: $0.element.start) }
            if chapters.isEmpty { chapters = [TimedChapter(id: 0, title: transcript.video.title, start: 0)] }
            func chapterIndex(for t: Double) -> Int { chapters.last { $0.start <= t }?.id ?? 0 }
            let timedTurns = paragraphs.enumerated().map { i, p in
                TimedTurn(id: i, chapterIndex: chapterIndex(for: p.start), speaker: i % 2 == 0 ? .a : .b, text: p.text, sourcePage: nil, start: p.start, end: p.end)
            }
            episode.timeline = Timeline(chapters: chapters, turns: timedTurns, duration: transcript.video.duration)
            episode.duration = transcript.video.duration
            episode.status = .ready
            context.insert(episode)
        }
        let output = episode.directory.appending(path: "podcast.m4a")
        try? FileManager.default.removeItem(at: output)
        try? FileManager.default.copyItem(at: audio, to: output)
        episode.audioFileName = "podcast.m4a"
        episode.lastPosition = 0
        if episode.study == nil, let notes = transcript.notes {
            // Çalış sekmesi denetimi için küçük bir çalışma paketi (quiz ders notundaki sorulardan).
            episode.study = StudyPack(quiz: notes.questions.prefix(3).map {
                QuizItem(question: $0.question, options: [$0.answer, "Yanlış seçenek A", "Yanlış seçenek B", "Yanlış seçenek C"],
                         answerIndex: 0, explanation: "", sourcePage: nil)
            }, flashcards: [], concepts: nil, formulas: nil)
        }
        if episode.concepts.isEmpty, let notes = transcript.notes {
            // Kavram haritası denetimi için: ders notundaki kavramlar, sırayla birbirine bağlı.
            let names = notes.concepts.map(\.name)
            episode.concepts = notes.concepts.enumerated().map { i, c in
                Concept(name: c.name, definition: c.definition, related: [names[(i + 1) % max(names.count, 1)]], sourcePage: nil)
            }
        }
        episode.scenesDone = episode.scenesTotal
        try? context.save()
        return (lesson, episode)
    }
}
#endif
