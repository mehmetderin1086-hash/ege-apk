import SwiftData
import SwiftUI

// #43: Depolama ekranı — ders başına ses/video/kare boyutu, tek tek silme, "30 gündür açılmayanların sesini sil".

/// Dersin son açılış zamanı (kütüphane ekranı açtıkça yazar). Model alanı eklemeden, cihazda UserDefaults'ta tutulur.
nonisolated enum LessonOpenLog {
    static let key = "youtube.lessonOpened"

    private static var stored: [String: Double] {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: Double]) ?? [:]
    }

    static func touch(_ id: UUID, now: Date = .now) {
        var all = stored
        all[id.uuidString] = now.timeIntervalSince1970
        UserDefaults.standard.set(all, forKey: key)
    }

    static func date(_ id: UUID) -> Date? {
        stored[id.uuidString].map { Date(timeIntervalSince1970: $0) }
    }

    static func forget(_ id: UUID) {
        var all = stored
        guard all.removeValue(forKey: id.uuidString) != nil else { return }
        UserDefaults.standard.set(all, forKey: key)
    }
}

nonisolated enum StorageUsage {
    enum Kind: Sendable { case audio, video, frames, other }

    struct Sizes: Sendable, Equatable {
        var audio: Int64 = 0
        var video: Int64 = 0
        var frames: Int64 = 0
        var other: Int64 = 0
        var total: Int64 { audio + video + frames + other }
    }

    /// Dosya adına göre tür.
    static func kind(of fileName: String) -> Kind {
        let lower = fileName.lowercased()
        let ext = (lower as NSString).pathExtension
        if ["m4a", "mp3", "aac", "wav", "caf", "ogg", "opus"].contains(ext) { return .audio }
        if ["mp4", "mov", "m4v", "webm", "mkv"].contains(ext) { return .video }
        if lower.hasPrefix("frame_") && ["jpg", "jpeg", "png"].contains(ext) { return .frames }
        return .other
    }

    static func lessonDirectory(_ id: UUID) -> URL {
        URL.applicationSupportDirectory.appending(path: "Videos", directoryHint: .isDirectory).appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    /// Ders klasöründeki dosyaları türe göre toplar (klasör oluşturmaz).
    static func measure(lesson id: UUID) -> Sizes {
        var sizes = Sizes()
        let directory = lessonDirectory(id)
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return sizes }
        for file in files {
            let bytes = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            switch kind(of: file.lastPathComponent) {
            case .audio: sizes.audio += bytes
            case .video: sizes.video += bytes
            case .frames: sizes.frames += bytes
            case .other: sizes.other += bytes
            }
        }
        return sizes
    }

    /// Ders klasöründen belirli türdeki dosyaları siler; silinen bayt sayısını döndürür.
    @discardableResult
    static func delete(_ kind: Kind, lesson id: UUID) -> Int64 {
        let directory = lessonDirectory(id)
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var freed: Int64 = 0
        for file in files where self.kind(of: file.lastPathComponent) == kind {
            freed += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            try? FileManager.default.removeItem(at: file)
        }
        return freed
    }

    struct Candidate: Sendable {
        var id: UUID
        var lastOpened: Date?
        var createdAt: Date
        var hasAudio: Bool
        /// Sınıf kaydı dersi: ses tek kopyadır (sunucuda indirilecek video yok), asla toplu silinmez.
        var isUpload: Bool = false
    }

    /// Yüklenen sınıf kaydı mı: kimliği "upload-" ile başlar ya da bağlantısı boştur.
    static func isUploadLesson(videoID: String, url: String) -> Bool {
        videoID.hasPrefix("upload-") || url.isEmpty
    }

    /// `days` gündür açılmamış (hiç açılmadıysa eklenme tarihine göre) ve sesi yeniden indirilebilir dersler.
    /// Sınıf kaydı dersleri hariçtir: sesleri tek kopyadır.
    static func staleAudio(_ items: [Candidate], days: Int = 30, now: Date = .now) -> [UUID] {
        let limit = now.addingTimeInterval(-Double(days) * 86_400)
        return items.filter { $0.hasAudio && !$0.isUpload && ($0.lastOpened ?? $0.createdAt) < limit }.map(\.id)
    }
}

struct StorageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VideoLesson.createdAt, order: .reverse) private var lessons: [VideoLesson]
    @State private var sizes: [UUID: StorageUsage.Sizes] = [:]
    @State private var loading = true
    @State private var confirmStale = false
    @State private var freeBytes: Int64 = 0
    /// Sınıf kaydı dersinin sesi silinmeden önce "geri alınamaz" onayı.
    @State private var confirmUploadAudio: VideoLesson?

    private var rows: [VideoLesson] {
        lessons.sorted { (sizes[$0.id]?.total ?? 0) > (sizes[$1.id]?.total ?? 0) }
    }
    private var totals: StorageUsage.Sizes {
        sizes.values.reduce(into: StorageUsage.Sizes()) { sum, s in
            sum.audio += s.audio; sum.video += s.video; sum.frames += s.frames; sum.other += s.other
        }
    }
    private var staleIDs: [UUID] {
        StorageUsage.staleAudio(lessons.map {
            StorageUsage.Candidate(id: $0.id, lastOpened: LessonOpenLog.date($0.id), createdAt: $0.createdAt, hasAudio: (sizes[$0.id]?.audio ?? 0) > 0,
                                   isUpload: StorageUsage.isUploadLesson(videoID: $0.videoID, url: $0.url))
        })
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Toplam") {
                    LabeledContent("Ders dosyaları", value: ByteFormat.string(totals.total))
                    LabeledContent("Ses", value: ByteFormat.string(totals.audio))
                    LabeledContent("Video", value: ByteFormat.string(totals.video))
                    LabeledContent("Kareler", value: ByteFormat.string(totals.frames))
                    if freeBytes > 0 { LabeledContent("Telefonda boş yer", value: ByteFormat.string(freeBytes)) }
                }
                Section {
                    Button {
                        confirmStale = true
                    } label: {
                        Label("30 gündür açılmayanların sesini sil (\(staleIDs.count))", systemImage: "clock.badge.xmark")
                    }
                    .disabled(staleIDs.isEmpty)
                } footer: {
                    Text("Ders, transkript ve notlar kalır; YouTube derslerinin sesi istediğin zaman yeniden indirilebilir. Yüklediğin sınıf kayıtlarının sesi tek kopyadır: bu işleme dahil edilmez.")
                }
                Section {
                    if loading { HStack(spacing: 8) { ProgressView(); Text("Hesaplanıyor…").foregroundStyle(.secondary) } }
                    ForEach(rows) { lesson in
                        StorageRow(lesson: lesson, sizes: sizes[lesson.id] ?? StorageUsage.Sizes()) { kind in
                            // Sınıf kaydının sesi tek kopya: önce açık onay.
                            if kind == .audio, StorageUsage.isUploadLesson(videoID: lesson.videoID, url: lesson.url) {
                                confirmUploadAudio = lesson
                            } else {
                                remove(kind, from: lesson)
                            }
                        }
                    }
                } header: {
                    Text("Dersler")
                }
            }
            .navigationTitle("Depolama")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
            .task { await refresh() }
            .confirmationDialog("Sınıf kaydının sesi silinsin mi?",
                                isPresented: Binding(get: { confirmUploadAudio != nil }, set: { if !$0 { confirmUploadAudio = nil } }),
                                titleVisibility: .visible) {
                Button("Sesi kalıcı olarak sil", role: .destructive) {
                    if let lesson = confirmUploadAudio { remove(.audio, from: lesson) }
                    confirmUploadAudio = nil
                }
            } message: {
                Text("Bu ses tek kopyadır; sunucudan yeniden indirilemez. Silinirse ders yalnızca transkript olarak kalır. Bu işlem geri alınamaz.")
            }
            .confirmationDialog("Sesler silinsin mi?", isPresented: $confirmStale, titleVisibility: .visible) {
                Button("\(staleIDs.count) dersin sesini sil", role: .destructive, action: deleteStale)
            } message: {
                Text("30 günden uzun süredir açılmayan derslerin indirilmiş sesi silinir.")
            }
        }
        .debugNarrowScreen()
    }

    private func refresh() async {
        let ids = lessons.map(\.id)
        sizes = await Self.measureAll(ids)
        freeBytes = (try? URL.applicationSupportDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
        loading = false
    }

    @concurrent
    private static func measureAll(_ ids: [UUID]) async -> [UUID: StorageUsage.Sizes] {
        Dictionary(uniqueKeysWithValues: ids.map { ($0, StorageUsage.measure(lesson: $0)) })
    }

    private func remove(_ kind: StorageUsage.Kind, from lesson: VideoLesson) {
        StorageUsage.delete(kind, lesson: lesson.id)
        switch kind {
        case .audio: lesson.audioFileName = nil
        case .video: lesson.videoFileName = nil
        case .frames, .other: break
        }
        try? modelContext.save()
        sizes[lesson.id] = StorageUsage.measure(lesson: lesson.id)
    }

    private func deleteStale() {
        let ids = Set(staleIDs)
        // Savunma: sınıf kaydı dersleri `staleIDs`'te zaten yok; yine de asla toplu silinmez.
        for lesson in lessons where ids.contains(lesson.id) && !StorageUsage.isUploadLesson(videoID: lesson.videoID, url: lesson.url) {
            remove(.audio, from: lesson)
        }
    }
}

private struct StorageRow: View {
    var lesson: VideoLesson
    var sizes: StorageUsage.Sizes
    var delete: (StorageUsage.Kind) -> Void

    private var isUpload: Bool { StorageUsage.isUploadLesson(videoID: lesson.videoID, url: lesson.url) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(lesson.title.isEmpty ? lesson.url : lesson.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 8)
                Text(ByteFormat.string(sizes.total)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
            }
            // Dar ekranda alt alta: kısa satırlar, taşma yok.
            VStack(alignment: .leading, spacing: 2) {
                if sizes.audio > 0 {
                    Label("Ses \(ByteFormat.string(sizes.audio))" + (isUpload ? " · tek kopya" : ""), systemImage: "headphones")
                }
                if sizes.video > 0 { Label("Video \(ByteFormat.string(sizes.video))", systemImage: "film") }
                if sizes.frames > 0 { Label("Kareler \(ByteFormat.string(sizes.frames))", systemImage: "photo.on.rectangle") }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            if sizes.video > 0 { Button("Video", systemImage: "trash", role: .destructive) { delete(.video) } }
            if sizes.audio > 0 { Button("Ses", systemImage: "trash", role: .destructive) { delete(.audio) } }
        }
        .contextMenu {
            if sizes.audio > 0 { Button("Sesi sil", systemImage: "trash", role: .destructive) { delete(.audio) } }
            if sizes.video > 0 { Button("Videoyu sil", systemImage: "trash", role: .destructive) { delete(.video) } }
            if sizes.frames > 0 { Button("Kareleri sil", systemImage: "trash", role: .destructive) { delete(.frames) } }
        }
    }
}
