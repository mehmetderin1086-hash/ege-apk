import SwiftData
import SwiftUI

// Kütüphane ve dosya araçları. FrameTextView → FrameText.swift, OfflineVideoView → OfflineVideo.swift,
// SubtitledVideoView → SubtitledVideo.swift.

/// #29 + #40: dersi "Derslerim"deki bir derse bağla ve konu etiketlerini düzenle.
struct LessonCourseView: View {
    var context: LessonContext

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Course.createdAt) private var courses: [Course]
    @State private var newCourseName = ""
    @State private var newTag = ""
    @State private var tagging = false
    @State private var tagError: String?

    private var lesson: VideoLesson { context.lesson }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Ders", selection: courseBinding) {
                        Text("Bağlı değil").tag(UUID?.none)
                        ForEach(courses) { course in
                            Text(course.name).tag(UUID?.some(course.id))
                        }
                    }
                    HStack {
                        TextField("Yeni ders adı", text: $newCourseName)
                            .submitLabel(.done)
                            .onSubmit(addCourse)
                        Button("Ekle", action: addCourse)
                            .disabled(newCourseName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Derslerim")
                } footer: {
                    Text("Bağlı videoların izleme süresi bu dersin istatistiğine yazılır.")
                }
                Section {
                    ForEach(lesson.tags, id: \.self) { tag in
                        Label(tag, systemImage: "tag")
                    }
                    .onDelete { offsets in
                        var tags = lesson.tags
                        tags.remove(atOffsets: offsets)
                        lesson.tags = tags
                        save()
                    }
                    HStack {
                        TextField("Etiket ekle", text: $newTag)
                            .submitLabel(.done)
                            .onSubmit(addTag)
                        Button("Ekle", action: addTag)
                            .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Button {
                        Task { await autoTag() }
                    } label: {
                        HStack {
                            Label("Yapay zekâyla etiketle", systemImage: "sparkles")
                            if tagging { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(tagging)
                    if let tagError { Text(tagError).font(.footnote).foregroundStyle(.red) }
                } header: {
                    Text("Etiketler")
                } footer: {
                    Text("Kütüphanede etikete göre süzebilirsin. En fazla \(TagLogic.maxTags) etiket.")
                }
            }
            .navigationTitle("Derse bağla")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
        }
        .debugNarrowScreen()
    }

    private var courseBinding: Binding<UUID?> {
        Binding(get: { lesson.courseID }, set: { lesson.courseID = $0; save() })
    }

    private func save() { try? modelContext.save() }

    private func addCourse() {
        let name = newCourseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let id = PlaylistCourse.match(name: name, in: courses.map { ($0.id, $0.name) }) ?? {
            let course = Course(name: name, colorHex: Course.palette[courses.count % Course.palette.count])
            modelContext.insert(course)
            return course.id
        }()
        lesson.courseID = id
        newCourseName = ""
        save()
    }

    private func addTag() {
        let tags = TagLogic.normalize(subject: "", topics: lesson.tags + [newTag])
        newTag = ""
        guard tags != lesson.tags else { return }
        lesson.tags = tags
        save()
    }

    private func autoTag() async {
        tagging = true
        tagError = nil
        defer { tagging = false }
        let summary = LessonTagging.summary(for: context.transcript)
        do {
            let response = try await APIClient.shared.youtubeTags(YouTubeTagsRequest(title: lesson.title, summary: summary))
            let tags = TagLogic.normalize(subject: response.subject, topics: lesson.tags + response.topics)
            lesson.tags = tags
            save()
        } catch {
            tagError = error.localizedDescription
        }
    }
}
