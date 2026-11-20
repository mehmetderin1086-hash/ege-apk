import ImageIO
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// Zamanlı notlar (#22): videonun bir anına yazı ve isteğe bağlı fotoğraf; dokununca o ana gider.
struct TimedNotesView: View {
    var context: LessonContext

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var notes: [TimedNote]
    @State private var timeText: String
    @State private var text = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoPreview: UIImage?
    @State private var saving = false
    @State private var errorText: String?
    /// Düzenlenen not (nil = yeni not ekleniyor).
    @State private var editing: TimedNote?
    /// Düzenlemeye geçilirken yarım kalan yeni not (metni ve seçilmiş fotoğrafı); düzenleme bitince geri gelir.
    @State private var stash = TimedNoteStash()
    @FocusState private var focused: Bool

    private static let editorID = "timedNoteEditor"

    init(context: LessonContext) {
        self.context = context
        let id = context.lesson.id
        _notes = Query(filter: #Predicate<TimedNote> { $0.lessonID == id }, sort: \.time)
        _timeText = State(initialValue: TranscriptFormat.timestamp(context.player.currentTime))
    }

    /// Videonun süresi (işlenen aralığın değil: sonraki anlara da not alınabilir); bilinmiyorsa 0.
    private var videoLength: Double {
        max(context.transcript.video.duration, context.lesson.duration, context.player.duration)
    }

    /// Zaman alanının çözülmüş değeri; anlaşılmıyorsa nil (kayıt engellenir).
    private var parsedTime: Double? { TimedNoteInput.time(from: timeText, duration: videoLength) }

    private var canSave: Bool {
        guard !saving, parsedTime != nil else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || photoData != nil || editing?.photoFileName != nil
    }

    var body: some View {
        StudySheet(title: "Zamanlı notlar") {
            ScrollViewReader { proxy in
                List {
                    Section(editing == nil ? "Yeni not" : "Notu düzenle") { editor.id(Self.editorID) }
                    Section {
                        if notes.isEmpty {
                            Text("Henüz not yok. Videonun bir anına yazı ya da fotoğraf ekleyebilirsin.").foregroundStyle(.secondary).font(.callout)
                        }
                        ForEach(notes) { note in
                            TimedNoteRow(note: note, lessonID: context.lesson.id, isEditing: editing?.id == note.id) {
                                dismiss()
                                context.resume(at: note.time)
                            }
                            .swipeActions(edge: .leading) {
                                Button("Düzenle", systemImage: "pencil") { beginEdit(note, proxy: proxy) }.tint(.blue)
                            }
                            // Özel kaydırma eylemi eklenince `onDelete`'in hazır "Sil"i gelmez: açıkça eklenir.
                            .swipeActions(edge: .trailing) {
                                Button("Sil", systemImage: "trash", role: .destructive) { delete(note) }
                            }
                            .contextMenu {
                                Button("Düzenle", systemImage: "pencil") { beginEdit(note, proxy: proxy) }
                            }
                        }
                    } header: {
                        Text("Notlar (\(notes.count))")
                    } footer: {
                        if !notes.isEmpty { Text("Düzenlemek için notu sağa kaydır ya da basılı tut.") }
                    }
                }
            }
        }
        .onAppear { context.pausePlayback() }
        .onChange(of: pickerItem) { _, item in loadPhoto(item) }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                TextField("0:00", text: $timeText)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.body.monospacedDigit())
                    .frame(maxWidth: 110)
                    .focused($focused)
                    .accessibilityLabel("Notun zamanı")
                Spacer(minLength: 4)
                Button("Şimdiki an") {
                    timeText = TranscriptFormat.timestamp(context.player.currentTime)
                }
                .buttonStyle(.bordered)
                .font(.footnote)
            }
            if let parsedTime {
                // Dersin süresini aşan zaman sona çekilir; alan başka bir şey gösterirken sessizce değişmesin.
                if let typed = VideoTime.parse(timeText), typed > parsedTime {
                    Label("Ders \(TranscriptFormat.timestamp(parsedTime)) sürüyor; not dersin sonuna yazılır.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Label("Zaman anlaşılmadı (ör. 12:34)", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            TextField("Notun…", text: $text, axis: .vertical)
                .lineLimit(2...6)
                .focused($focused)
            if let preview = photoPreview {
                HStack {
                    Image(uiImage: preview).resizable().scaledToFill().frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    // Satırın boş yerine dokunmak bu düğmeyi tetiklemesin diye açık stil.
                    Button("Fotoğrafı kaldır", role: .destructive) {
                        photoData = nil
                        photoPreview = nil
                        pickerItem = nil
                    }
                    .buttonStyle(.borderless)
                    .font(.footnote)
                }
            }
            if editing?.photoFileName != nil {
                Text(photoData == nil ? "Notun fotoğrafı korunur; yenisini seçersen onun yerine geçer." : "Yeni fotoğraf eskisinin yerine geçecek.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let errorText { Text(errorText).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    photoPicker
                    Spacer(minLength: 4)
                    actionButtons
                }
                VStack(alignment: .leading, spacing: 8) {
                    photoPicker
                    HStack(spacing: 8) { actionButtons }
                }
            }
        }
    }

    private var photoPicker: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            Label("Fotoğraf", systemImage: "photo")
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if editing != nil {
            Button("Vazgeç") { endEdit() }
                .buttonStyle(.borderless)
                .disabled(saving)
        }
        Button {
            save()
        } label: {
            if saving { ProgressView() } else { Text(editing == nil ? "Ekle" : "Kaydet") }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canSave)
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                photoData = data
                photoPreview = await TimedNotePhoto.preview(data)
            } else {
                errorText = "Fotoğraf okunamadı."
            }
        }
    }

    private func clearPhoto() {
        photoData = nil
        photoPreview = nil
        pickerItem = nil
    }

    /// Notun metnini ve zamanını düzenleyiciye yükler.
    private func beginEdit(_ note: TimedNote, proxy: ScrollViewProxy) {
        guard !saving else { return }
        stash.keep(text: text, photoData: photoData, photoPreview: photoPreview, whileEditing: editing != nil)
        editing = note
        text = note.text
        timeText = TranscriptFormat.timestamp(note.time)
        clearPhoto()
        errorText = nil
        withAnimation { proxy.scrollTo(Self.editorID, anchor: .top) }
    }

    /// Düzenlemeyi kapatır; yarım kalan yeni not (metni ve seçilmiş fotoğrafı) geri gelir.
    private func endEdit() {
        let draft = stash.take()
        editing = nil
        text = draft.text
        timeText = TranscriptFormat.timestamp(context.player.currentTime)
        // Seçici öğesi geri konmaz: fotoğrafın verisi eldedir, öğe geri konursa `onChange` onu yeniden okur.
        pickerItem = nil
        photoData = draft.photoData
        photoPreview = draft.photoPreview
        errorText = nil
        focused = false
    }

    private func save() {
        guard !saving, context.lesson.modelContext != nil, let noteTime = parsedTime else { return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = photoData
        let lessonID = context.lesson.id
        let target = editing
        saving = true
        errorText = nil
        Task {
            defer { saving = false }
            let created = target == nil ? TimedNote(lessonID: lessonID, time: noteTime, text: body) : nil
            var newPhoto: String?
            if let data {
                // Düzenlemede yeni ad: kayıt başarısız olursa eski fotoğraf yerinde kalır, satırdaki görsel de yenilenir.
                let name = "note_\((created?.id ?? UUID()).uuidString).jpg"
                let url = VideoFiles.directory(for: lessonID).appending(path: name)
                guard await TimedNotePhoto.save(data, to: url) else {
                    errorText = "Fotoğraf kaydedilemedi."
                    return
                }
                newPhoto = name
            }
            // Fotoğraf yazılırken ders ya da düzenlenen not silinmiş olabilir: silinmiş kayda dokunulmaz.
            let targetGone = target.map { $0.modelContext == nil || $0.isDeleted } ?? false
            guard context.lesson.modelContext != nil, !targetGone, let note = target ?? created else {
                if let newPhoto { TimedNotePhoto.remove(newPhoto, lesson: lessonID) }
                if target != nil { endEdit() }
                return
            }
            let oldText = note.text, oldTime = note.time, oldPhoto = note.photoFileName
            note.text = body
            note.time = noteTime
            if let newPhoto { note.photoFileName = newPhoto }
            if target == nil { modelContext.insert(note) }
            do {
                try modelContext.save()
            } catch {
                // Yazılamayan değişiklik geri alınır; düzenleyicideki metin durur.
                if target == nil {
                    modelContext.delete(note)
                } else {
                    note.text = oldText
                    note.time = oldTime
                    note.photoFileName = oldPhoto
                }
                if let newPhoto { TimedNotePhoto.remove(newPhoto, lesson: lessonID) }
                errorText = "Not kaydedilemedi: \(error.localizedDescription)"
                return
            }
            if let newPhoto, let oldPhoto, oldPhoto != newPhoto { TimedNotePhoto.remove(oldPhoto, lesson: lessonID) }
            if target == nil {
                text = ""
                clearPhoto()
                focused = false
            } else {
                endEdit()
            }
        }
    }

    private func delete(_ note: TimedNote) {
        if editing?.id == note.id { endEdit() }
        if let name = note.photoFileName { TimedNotePhoto.remove(name, lesson: context.lesson.id) }
        modelContext.delete(note)
        try? modelContext.save()
    }
}

private struct TimedNoteRow: View {
    var note: TimedNote
    var lessonID: UUID
    var isEditing = false
    var onGo: () -> Void
    @State private var photo: UIImage?

    var body: some View {
        Button(action: onGo) {
            VStack(alignment: .leading, spacing: 6) {
                Label(TranscriptFormat.timestamp(note.time), systemImage: "play.circle.fill")
                    .font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.tint)
                if isEditing {
                    Label("Düzenleniyor", systemImage: "pencil").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                if !note.text.isEmpty {
                    Text(note.text).font(.callout).foregroundStyle(.primary).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Videoyu bu ana götürür")
        .task(id: note.photoFileName) {
            guard let name = note.photoFileName else { photo = nil; return }
            photo = await LessonFiles.thumbnail(VideoFiles.directory(for: lessonID).appending(path: VideoFiles.safeAudioName(name)),
                                                maxPixel: 700)
        }
    }
}

/// Düzenlemeye geçilirken yarım kalan yeni not: metni ve seçilmiş (henüz kaydedilmemiş) fotoğrafı.
nonisolated struct TimedNoteStash {
    private(set) var text = ""
    private(set) var photoData: Data?
    private(set) var photoPreview: UIImage?

    /// Yarım notu saklar. Düzenleme zaten sürüyorsa (bir nottan ötekine geçiş) saklanan korunur:
    /// o an düzenleyicide duran, yeni notun değil düzenlenen notun içeriğidir.
    mutating func keep(text: String, photoData: Data?, photoPreview: UIImage?, whileEditing: Bool) {
        guard !whileEditing else { return }
        self.text = text
        self.photoData = photoData
        self.photoPreview = photoPreview
    }

    /// Saklananı verir ve boşaltır (aynı taslak ikinci kez geri gelmesin).
    mutating func take() -> TimedNoteStash {
        defer { self = TimedNoteStash() }
        return self
    }
}

nonisolated enum TimedNotePhoto {
    /// Fotoğrafı en uzun kenarı ≤ 1600 px olacak şekilde JPEG olarak yazar (ana iş parçacığı dışında).
    @concurrent
    static func save(_ data: Data, to url: URL) async -> Bool {
        guard let image = UIImage(data: data) else { return false }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 1600 ? 1600 / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { return false }
        return (try? jpeg.write(to: url, options: .atomic)) != nil
    }

    @concurrent
    static func preview(_ data: Data) async -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: 300] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options).map { UIImage(cgImage: $0) }
    }

    static func remove(_ name: String, lesson: UUID) {
        try? FileManager.default.removeItem(at: VideoFiles.directory(for: lesson).appending(path: VideoFiles.safeAudioName(name)))
    }
}
