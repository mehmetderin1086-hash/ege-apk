#if DEBUG
import Foundation
import SwiftData
import SwiftUI

/// Yalnızca Debug: `-libDemo` ile kütüphane ekranlarını (arama, depolama, kanallar, Koç görevleri, ders araçları) simülatörde
/// denetlemek için örnek dersler/kanallar tohumlar. `-openLibraryTool=search|channels|storage`, `-openLessonTool=course|frameText|offline|subtitled`,
/// `-libQuery=<metin>` ilgili ekranı açar. `-queueDemo` işleme kuyruğuna iki örnek video koyar (kanallar ekranındaki bekleyen satırlar için).
enum LibraryDemo {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-libDemo") }

    @MainActor
    static func seedIfRequested(context: ModelContext) {
        guard isRequested else { return }
        if ProcessInfo.processInfo.arguments.contains("-queueDemo"), AutoImportQueue.items.isEmpty {
            AutoImportQueue.enqueue([
                FeedVideo(id: "QUEUEDEMO01", url: "https://youtu.be/QUEUEDEMO01", title: "Demo · Kuyrukta bekleyen uzun başlıklı video: mitoz ve mayoz bölünme"),
                FeedVideo(id: "QUEUEDEMO02", url: "https://youtu.be/QUEUEDEMO02", title: ""),
            ], courseID: nil)
        }
        guard ((try? context.fetchCount(FetchDescriptor<VideoLesson>(predicate: #Predicate { $0.title.contains("Demo ·") }))) ?? 0) == 0 else { return }

        let biology = Course(name: "Biyoloji", colorHex: Course.palette[0])
        let physics = Course(name: "Fizik", colorHex: Course.palette[1])
        context.insert(biology)
        context.insert(physics)

        let samples: [(String, String, UUID?, Double, [String], [Double])] = [
            ("Demo · Hücre zarı ve madde geçişi", "Biyoloji Hocası", biology.id, 640, ["Biyoloji", "Hücre"], [118, 122, 126, 131, 640]),
            ("Demo · Newton'un hareket yasaları", "Fizik Kanalı", physics.id, 0, ["Fizik"], []),
            ("Demo · Genel tekrar (derse bağlı değil)", "Kanal", nil, 90, [], []),
        ]
        for (index, sample) in samples.enumerated() {
            let id = String(format: "DEMO%07d", index)
            let chapters = [VideoChapter(title: "Giriş", start: 0), VideoChapter(title: "Osmoz ve difüzyon", start: 300), VideoChapter(title: "Aktif taşıma", start: 900)]
            let paragraphs = [
                TranscriptParagraph(start: 5, end: 60, text: "Hücre zarı seçici geçirgen bir yapıdır ve madde geçişini kontrol eder."),
                TranscriptParagraph(start: 310, end: 400, text: "Osmoz, suyun yarı geçirgen zardan az yoğun ortamdan çok yoğun ortama geçişidir."),
                TranscriptParagraph(start: 905, end: 990, text: "Aktif taşımada ATP harcanır ve madde derişim farkına karşı taşınır."),
            ]
            let video = VideoInfo(id: id, url: "https://youtu.be/\(id)", title: sample.0, channel: sample.1, duration: 1800, thumbnail: nil,
                                  chapters: chapters, captions: [], language: "tr", embeddable: true)
            let transcript = VideoTranscript(
                video: video, source: "ai", language: "tr", segments: [], paragraphs: paragraphs, chapters: chapters, translation: nil,
                notes: LectureNotes(summary: "Hücre zarından madde geçişi.", keyPoints: [NoteKeyPoint(text: "Osmoz", time: 310)], concepts: [], formulas: [], questions: [], examTips: []),
                keyframes: [Keyframe(id: "f1", time: 320, image: "", caption: "Osmoz şeması", text: "")], warnings: [])
            let lesson = VideoLesson(url: video.url, info: video)
            lesson.transcript = transcript
            lesson.courseID = sample.2
            lesson.lastPosition = sample.3
            lesson.tags = sample.4
            lesson.rewindTimes = sample.5
            context.insert(lesson)
            if index == 0 {
                FrameTextStore.save([FrameTextStore.Entry(id: "f1", time: 320, text: "OSMOZ\nSu: az yoğun → çok yoğun")], lesson: lesson.id)
                let dir = VideoFiles.directory(for: lesson.id)
                try? Data(count: 12_000_000).write(to: dir.appending(path: "audio.m4a"))
                lesson.audioFileName = "audio.m4a"
                try? Data(count: 90_000_000).write(to: dir.appending(path: "video.mp4"))
                lesson.videoFileName = "video.mp4"
            }
        }
        let channel = FollowedChannel(url: "https://www.youtube.com/@biyolojihocasi", title: "Biyoloji Hocası")
        channel.lastChecked = .now.addingTimeInterval(-3600)
        channel.autoProcess = true
        channel.courseID = biology.id
        context.insert(channel)
        try? context.save()
    }

    static var libraryTool: String? { DebugArg.value("openLibraryTool") }
    static var lessonTool: String? { DebugArg.value("openLessonTool") }
    static var query: String? { DebugArg.value("libQuery") }

    static func sheet(for name: String) -> LessonSheet? {
        switch name {
        case "course": .course
        case "frameText": .frameText
        case "offline": .offlineVideo
        case "subtitled": .subtitledVideo
        default: nil
        }
    }
}
#endif
