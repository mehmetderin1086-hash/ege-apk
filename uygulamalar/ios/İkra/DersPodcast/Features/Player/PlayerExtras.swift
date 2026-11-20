import AVFoundation
import SwiftData
import SwiftUI

// MARK: - Uyku zamanlayıcısı

struct SleepTimerMenu: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        Menu {
            if player.sleepTimer != nil {
                Button("Zamanlayıcıyı kapat", systemImage: "xmark", role: .destructive) { player.cancelSleepTimer() }
                Divider()
            }
            ForEach([5, 15, 30, 45, 60], id: \.self) { minutes in
                Button("\(minutes) dakika sonra") { player.setSleepTimer(minutes: minutes) }
            }
            Button("Bu konu bitince") { player.setSleepTimerEndOfChapter() }
            Button("Bölüm sonunda") { player.setSleepTimerEndOfEpisode() }
        } label: {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                if let remaining = player.sleepRemaining {
                    Label(remaining.clockText, systemImage: "moon.zzz.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.monospacedDigit().bold())
                } else {
                    Image(systemName: player.sleepTimer == nil ? "moon.zzz" : "moon.zzz.fill")
                }
            }
        }
        .accessibilityLabel("Uyku zamanlayıcısı")
    }
}

// MARK: - Yer imleri ve notlar

/// Yeni not (transkript turu) ya da var olan işaretin notunu düzenleme (`initialNote`/`existingAudio`).
struct BookmarkEditor: View {
    /// İşaretlenen an ve cümle.
    var time: Double
    var text: String
    var initialNote: String
    /// Düzenlenen kaydın sesli notu. Bu görünüm ona dokunmaz: yenisi kaydedilirse değiştirmek `save`'in işidir
    /// ("Vazgeç" eski sesli notu silmesin).
    var existingAudio: String?
    /// (not metni, bu oturumda kaydedilen sesli not dosya adı; yeni kayıt yoksa nil)
    var save: (String, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @State private var recorder = SpeechRecorder()
    /// Bu oturumda kaydedilen dosya (var olan sesli not değil).
    @State private var audioName: String?
    @State private var saved = false

    init(time: Double, text: String, initialNote: String = "", existingAudio: String? = nil, save: @escaping (String, String?) -> Void) {
        self.time = time
        self.text = text
        self.initialNote = initialNote
        self.existingAudio = existingAudio
        self.save = save
        _note = State(initialValue: initialNote)
    }

    private var isEditing: Bool { existingAudio != nil || !initialNote.isEmpty }
    private var keepsOldAudio: Bool { existingAudio != nil && audioName == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("İşaretlenen cümle · \(time.clockText)") {
                    Text(text).font(.callout).foregroundStyle(.secondary)
                }
                Section("Notun") {
                    TextField("Ör. sınavda çıkabilir, formülü ezberle", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Button {
                        Task {
                            if recorder.isRecording {
                                let text = await recorder.stop()
                                if note.isEmpty { note = text }
                            } else {
                                let old = audioName
                                let name = "\(UUID().uuidString).m4a"
                                await recorder.start(recordTo: VoiceNotes.url(name))
                                // Kayıt başlamadıysa (izin yok, önceki kayıt kapanıyor) eski sesli not yerinde kalır.
                                guard recorder.isRecording else {
                                    try? FileManager.default.removeItem(at: VoiceNotes.url(name))
                                    return
                                }
                                audioName = name
                                // "Yeniden kaydet": eski dosya sahipsiz kalmasın.
                                if let old { try? FileManager.default.removeItem(at: VoiceNotes.url(old)) }
                            }
                        }
                    } label: {
                        Label(recorder.isRecording ? "Kaydı bitir" : (audioName == nil && existingAudio == nil ? "Sesli not kaydet" : "Yeniden kaydet"),
                              systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    }
                    if recorder.isRecording { Text(recorder.transcript.isEmpty ? "Dinliyorum…" : recorder.transcript).font(.caption).foregroundStyle(.secondary) }
                    if let error = recorder.error { Text(error).font(.caption).foregroundStyle(.red) }
                } footer: {
                    Text(keepsOldAudio ? "Bu kaydın sesli notu var. Yeniden kaydedip \"Kaydet\"e basarsan eskisinin yerine geçer."
                                       : "Sesli not kaydedilir ve otomatik olarak yazıya da çevrilir.")
                }
            }
            .navigationTitle(isEditing ? "Notu düzenle" : "Not ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") {
                        recorder.cancel()
                        if let audioName { try? FileManager.default.removeItem(at: VoiceNotes.url(audioName)) }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        Task {
                            if recorder.isRecording {
                                let text = await recorder.stop()
                                if note.isEmpty { note = text }
                            }
                            let hasAudio = !recorder.lastRecordingFailed
                                && (audioName.map { FileManager.default.fileExists(atPath: VoiceNotes.url($0).path) } ?? false)
                            if !hasAudio, let audioName { try? FileManager.default.removeItem(at: VoiceNotes.url(audioName)) }
                            saved = true
                            save(note.trimmingCharacters(in: .whitespacesAndNewlines), hasAudio ? audioName : nil)
                            dismiss()
                        }
                    }
                }
            }
            // Yazılan not ya da kayıt aşağı kaydırmayla kaybolmasın; çıkış "Vazgeç" ya da "Kaydet" iledir.
            .interactiveDismissDisabled(recorder.isRecording || audioName != nil
                                        || note.trimmingCharacters(in: .whitespacesAndNewlines)
                                            != initialNote.trimmingCharacters(in: .whitespacesAndNewlines))
            // Kaydedilmeden kapandıysa (hangi yoldan olursa olsun) mikrofon kapanır, yarım dosya silinir.
            .onDisappear {
                guard !saved else { return }
                recorder.cancel()
                if let audioName { try? FileManager.default.removeItem(at: VoiceNotes.url(audioName)) }
            }
        }
    }
}

/// Bir bölümün yer imleri (veya episodeID nil ise tüm bölümlerin).
struct EpisodeNotesView: View {
    var episodeID: UUID?
    @Environment(PlayerController.self) private var player
    @Environment(\.modelContext) private var context
    @Query(sort: \Bookmark.createdAt, order: .reverse) private var all: [Bookmark]
    @State private var filter = BookmarkFilter.all
    @State private var editing: Bookmark?

    private var bookmarks: [Bookmark] {
        guard let episodeID else { return all }
        return all.filter { $0.episodeID == episodeID }.sorted { $0.time < $1.time }
    }

    var body: some View {
        let marks = bookmarks
        if marks.isEmpty {
            ContentUnavailableView {
                Label("Henüz not yok", systemImage: "bookmark")
            } description: {
                Text("Transkriptte bir cümleye uzun basıp \"İşaretle\" veya \"Not ekle\"yi seç.")
            }
        } else {
            let shown = marks.filter { filter.matches(kind: $0.kind, note: $0.note, hasAudio: $0.audioFileName != nil) }
            VStack(spacing: 0) {
                Picker("Süzgeç", selection: $filter) {
                    ForEach(BookmarkFilter.allCases) { Text($0.title).tag($0) }
                }
                .modifier(AccessiblePickerStyle())
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                if shown.isEmpty {
                    ContentUnavailableView("Bu türde kayıt yok", systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("Bütün kayıtları görmek için \"Tümü\"nü seç."))
                } else {
                    List {
                        ForEach(shown) { mark in
                            row(mark)
                                // Hızlı işaretler notsuz oluşur (mini oynatıcı, Yolda, Siri): not sonradan buradan yazılır.
                                .swipeActions(edge: .leading) {
                                    Button("Not", systemImage: "square.and.pencil") { editing = mark }.tint(.orange)
                                }
                                .contextMenu {
                                    Button(mark.note.isEmpty ? "Not ekle" : "Notu düzenle", systemImage: "square.and.pencil") { editing = mark }
                                }
                        }
                        .onDelete { delete(at: $0, in: shown) }
                    }
                    .listStyle(.plain)
                }
            }
            .onAppear {
                if let raw = DebugArg.value("notesFilter"), let value = BookmarkFilter(rawValue: raw) { filter = value }
            }
            .sheet(item: $editing) { mark in
                BookmarkEditor(time: mark.time, text: mark.text, initialNote: mark.note, existingAudio: mark.audioFileName) { note, audio in
                    update(mark, note: note, audio: audio)
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func row(_ mark: Bookmark) -> some View {
        Button {
            jump(to: mark)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if episodeID == nil {
                        Text(mark.episodeTitle).font(.caption.bold()).foregroundStyle(.tint).lineLimit(1)
                    }
                    if let kind = BookmarkKind.label(mark.kind) {
                        Label(kind.title, systemImage: kind.symbol)
                            .font(.caption2.bold())
                            .foregroundStyle(kind.color)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(mark.time.clockText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(mark.text).font(.callout).foregroundStyle(.primary).lineLimit(4)
                if !mark.note.isEmpty {
                    Label(mark.note, systemImage: "square.and.pencil")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.orange)
                }
                if let audio = mark.audioFileName {
                    Button { VoiceNotes.play(audio) } label: {
                        Label("Sesli notu dinle", systemImage: "play.circle.fill").font(.callout)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    /// Düzenlenen not yazılır; yeni sesli not kaydedildiyse eskisinin yerine geçer.
    private func update(_ mark: Bookmark, note: String, audio: String?) {
        let old = mark.audioFileName
        mark.note = note
        if let audio, audio != old { mark.audioFileName = audio }
        do { try context.save() } catch { return }
        guard let old, mark.audioFileName != old else { return }
        removeAudio([old], keptBy: all)
    }

    /// Silinen kayıtların sesli not dosyaları da silinir (yoksa `VoiceNotes` klasöründe sahipsiz kalır).
    private func delete(at offsets: IndexSet, in shown: [Bookmark]) {
        let doomed = offsets.compactMap { shown[safe: $0] }
        let ids = Set(doomed.map(\.id))
        let audio = doomed.compactMap(\.audioFileName)
        let kept = all.filter { !ids.contains($0.id) }
        for mark in doomed { context.delete(mark) }
        // Kayıt silinemediyse dosyası da kalır (kayıt yeniden görünürse sesli notu çalabilsin).
        do { try context.save() } catch { return }
        removeAudio(audio, keptBy: kept)
    }

    private func removeAudio(_ names: [String], keptBy marks: [Bookmark]) {
        for name in VoiceNotes.unreferenced(names, keptBy: marks.map(\.audioFileName)) {
            try? FileManager.default.removeItem(at: VoiceNotes.url(name))
        }
    }

    private func jump(to mark: Bookmark) {
        if player.episode?.id == mark.episodeID {
            player.seek(to: mark.time)
            if !player.isPlaying { player.play() }
            return
        }
        let id = mark.episodeID
        guard let episode = try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })).first else { return }
        player.play(episode, at: mark.time, context: context)
    }
}

/// Notlar listesinin süzgeci (saf; test edilir). "Notlu": yazılı ya da sesli notu olan kayıt.
nonisolated enum BookmarkFilter: String, CaseIterable, Identifiable {
    case all, noted, confused

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Tümü"
        case .noted: "Notlu"
        case .confused: "Anlamadım"
        }
    }

    func matches(kind: String, note: String, hasAudio: Bool) -> Bool {
        switch self {
        case .all: true
        case .noted: hasAudio || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .confused: kind == "confused"
        }
    }
}

/// Yer iminin türü (#19/#22): liste satırında küçük rozet.
enum BookmarkKind {
    static func label(_ kind: String) -> (title: String, symbol: String, color: Color)? {
        switch kind {
        case "confused": ("Anlamadım", "questionmark.circle.fill", .orange)
        case "siri": ("Siri", "mic.fill", Theme.blueInk)
        case "flag": ("İşaret", "bookmark.fill", .blue)
        default: nil
        }
    }
}

/// Sesli notların saklandığı yer ve oynatıcı.
/// #50: sesli not çalarken podcast duraklar, not bitince (öncesinde çalıyorsa) sürer.
enum VoiceNotes {
    static func url(_ name: String) -> URL {
        let dir = URL.applicationSupportDirectory.appending(path: "VoiceNotes", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: name)
    }

    /// `names` içinden kalan kayıtların hiçbirinin göstermediği dosyalar (saf; test edilir). Aynı dosyayı iki kayıt
    /// gösterebilir; başka kaydın kullandığı sesli not diskten silinmez.
    nonisolated static func unreferenced(_ names: [String], keptBy remaining: [String?]) -> [String] {
        let kept = Set(remaining.compactMap { $0 })
        var seen = Set<String>()
        return names.filter { !kept.contains($0) && seen.insert($0).inserted }
    }

    private static var player: AVAudioPlayer?
    private static var resumePodcast = false
    private static let delegate = VoiceNoteDelegate()

    static func play(_ name: String) {
        if let podcast = AppState.current?.player, podcast.isPlaying {
            podcast.pause()
            resumePodcast = true
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: url(name))
        player?.delegate = delegate
        if player?.play() != true { finished() }
    }

    static func finished() {
        player = nil
        guard resumePodcast else { return }
        resumePodcast = false
        AppState.current?.player.play()
    }
}

/// AVAudioPlayer geri çağrısı ana iş parçacığında olmayabilir: iş ana aktöre aktarılır.
private final class VoiceNoteDelegate: NSObject, AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in VoiceNotes.finished() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor in VoiceNotes.finished() }
    }
}
