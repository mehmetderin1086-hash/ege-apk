import SwiftData
import SwiftUI

/// #40: "Kaynak video · 12:30": bölüm bir YouTube dersinden geldiyse o dersi (o andan) açar.
struct SourceVideoChip: View {
    let episode: Episode
    @Environment(\.modelContext) private var context
    @State private var lesson: (id: UUID, title: String)?
    @State private var open: Target?

    private struct Target: Identifiable { var id: UUID }

    var body: some View {
        Group {
            if let lesson {
                Button {
                    if let time = episode.sourceVideoTime, let live = VideoLessonView.liveLesson(id: lesson.id, in: context) {
                        live.lastPosition = time
                        try? context.save()
                    }
                    open = Target(id: lesson.id)
                } label: {
                    Label(SourceVideo.label(title: lesson.title, time: episode.sourceVideoTime), systemImage: "play.rectangle.fill")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                        .background(Color.red.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityLabel("Kaynak videoyu aç: \(lesson.title)")
            }
        }
        .task(id: episode.id) { lesson = SourceVideo.lesson(for: episode, context: context) }
        .sheet(item: $open) { VideoLibraryView(openLesson: $0.id) }
    }
}

enum SourceVideo {
    nonisolated static func label(title: String, time: Double?) -> String {
        guard let time, time > 0 else { return "Kaynak video" }
        return "Kaynak video · \(clock(time))"
    }

    nonisolated static func clock(_ t: Double) -> String {
        let total = Int(t.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// `sourceLessonID` ya da dersin `episodeIDs` listesi.
    static func lesson(for episode: Episode, context: ModelContext) -> (id: UUID, title: String)? {
        if let id = episode.sourceLessonID, let l = VideoLessonView.liveLesson(id: id, in: context) { return (l.id, l.title) }
        let lessons = (try? context.fetch(FetchDescriptor<VideoLesson>())) ?? []
        return lessons.first { $0.episodeIDs.contains(episode.id) }.map { ($0.id, $0.title) }
    }
}
