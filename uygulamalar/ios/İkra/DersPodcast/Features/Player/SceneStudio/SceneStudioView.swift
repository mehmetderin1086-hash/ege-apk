import AVFoundation
import SwiftData
import SwiftUI

/// #10 sahne stüdyosu: turlar elle düzenlenir, yalnız o sahne seslendirilir; "Eski/Yeni" dinlenip uygulanır ya da geri alınır.
struct SceneStudioView: View {
    let episode: Episode
    let sceneIndex: Int
    @Environment(GenerationCoordinator.self) private var generator
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// Kimlikli satırlar: tur sayısı değişince (kısaltma, sıfırlama) eski indeks bağlamaları okunmasın.
    @State private var items: [StudioTurn] = []
    @State private var original: [ScriptTurn] = []
    @State private var rendered: URL?
    @State private var renderedTurns: [ScriptTurn]?
    @State private var phase: Phase = .idle
    @State private var error: String?
    @State private var notice: String?
    @State private var instruction = Self.presets[0]
    @State private var custom = ""
    @State private var audition = StudioAudition()
    @State private var canUndo = false
    @State private var showSuggestions = false
    @State private var renderTask: Task<Void, Never>?
    @State private var isVisible = false
    @State private var confirmDiscard = false

    enum Phase { case idle, rewriting, rendering, applying, undoing }

    static let presets = ["Daha basit anlat", "Somut bir örnek ekle", "Kısalt", "Daha ayrıntılı anlat", "Bir benzetmeyle açıkla", "Özel…"]

    private var settings: PodcastSettings { episode.settings ?? PodcastSettings() }
    private var turns: [ScriptTurn] { items.map(\.turn) }
    private var busy: Bool { phase != .idle }
    /// Kapatınca kaybolacak iş var: elle düzeltilmiş turlar ya da seslendirilmiş ama uygulanmamış yeni hâl.
    private var isDirty: Bool { Self.hasUnsavedWork(turns: turns, original: original, hasRendered: rendered != nil) }

    static func hasUnsavedWork(turns: [ScriptTurn], original: [ScriptTurn], hasRendered: Bool) -> Bool {
        hasRendered || turns != original
    }

    static func discardMessage(hasRendered: Bool) -> String {
        hasRendered ? "Seslendirilen yeni hâl uygulanmadı; kapatırsan silinir." : "Düzelttiğin turlar kaydedilmedi."
    }
    private var hasEmptyTurn: Bool { turns.contains { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    /// Sunucu sınırını (1500) aşan ilk tur; seslendirme kapalı kalır, hangi tur olduğu yazılır.
    private var overLimit: (index: Int, length: Int)? { SceneEditor.overLimit(turns) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Turları düzelt; yalnız bu sahne yeniden seslendirilir. Diğer sahneler, notlar ve yer imleri korunur.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                turnsSection
                rewriteSection
                voiceSection
                if canUndo {
                    Section {
                        Button {
                            Task { await undo() }
                        } label: {
                            HStack {
                                if phase == .undoing { ProgressView() }
                                Label("Son düzenlemeyi geri al", systemImage: "arrow.uturn.backward")
                            }
                        }
                        .disabled(busy)
                    } footer: {
                        Text("Bölüm, son sahne düzenlemesinden önceki hâline döner.")
                    }
                }
                if let notice {
                    Section { Label(notice, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Sahne stüdyosu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") {
                        if isDirty { confirmDiscard = true } else { dismiss() }
                    }
                    .disabled(phase == .applying || phase == .undoing)
                }
                if app.serverSupports("podcast2") {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showSuggestions = true
                        } label: {
                            Image(systemName: "character.bubble")
                        }
                        .accessibilityLabel("Telaffuz önerileri")
                    }
                }
            }
            // Aşağı kaydırma düzenlemeyi (ve hak harcamış seslendirmeyi) sessizce silmesin: "Kapat" onay ister.
            .interactiveDismissDisabled(phase == .applying || phase == .undoing || isDirty)
            .confirmationDialog("Değişiklikler atılsın mı?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Değişiklikleri at", role: .destructive) { dismiss() }
                Button("Düzenlemeye dön", role: .cancel) {}
            } message: {
                Text(Self.discardMessage(hasRendered: rendered != nil))
            }
            .sheet(isPresented: $showSuggestions) { PronunciationSuggestionsSheet(episode: episode) }
            .onAppear {
                isVisible = true
                load()
            }
            .onDisappear {
                // Kapatılınca süren seslendirme iptal edilir; sonucu gelirse dosyası silinir, dinletme başlamaz.
                isVisible = false
                renderTask?.cancel()
                renderTask = nil
                audition.stop()
                discardRendered()
            }
            .onChange(of: turns) { _, newValue in
                if let renderedTurns, renderedTurns != newValue { discardRendered() }
            }
        }
    }

    // MARK: Bölümler

    private var turnsSection: some View {
        Section {
            ForEach($items) { $item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(settings.displayName(for: item.turn.speaker))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Tur metni", text: $item.turn.text, axis: .vertical)
                        .lineLimit(2...12)
                        .disabled(busy)
                        .accessibilityLabel("\(settings.displayName(for: item.turn.speaker)) turu")
                    let length = item.turn.text.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
                    if length > SceneEditor.maxTurnLength {
                        Text("Çok uzun: \(length)/\(SceneEditor.maxTurnLength) karakter")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
            }
            if turns != original {
                Button("Değişiklikleri sıfırla", role: .destructive) { setTurns(original) }
                    .disabled(busy)
            }
        } header: {
            Text("Turlar")
        } footer: {
            if hasEmptyTurn {
                Text("Boş tur bırakılamaz.").foregroundStyle(.red)
            } else if let over = overLimit {
                Text("\(over.index). tur \(SceneEditor.maxTurnLength) karakteri aşıyor; kısalt ya da ikiye böl.").foregroundStyle(.red)
            }
        }
    }

    private var rewriteSection: some View {
        Section {
            Picker("İstek", selection: $instruction) {
                ForEach(Self.presets, id: \.self) { Text($0).tag($0) }
            }
            if instruction == "Özel…" {
                TextField("Ör. formülü adım adım açıkla", text: $custom, axis: .vertical).lineLimit(2...4)
            }
            Button {
                Task { await rewrite() }
            } label: {
                HStack {
                    if phase == .rewriting { ProgressView() }
                    Label("Yapay zekâyla yeniden yaz", systemImage: "wand.and.stars")
                }
            }
            .disabled(busy || (instruction == "Özel…" && custom.trimmingCharacters(in: .whitespaces).isEmpty))
        } header: {
            Text("Yeniden yaz")
        } footer: {
            Text("Bölümün tempo ve derinliği korunur. Sonucu yukarıda düzenleyebilirsin.")
        }
    }

    private var voiceSection: some View {
        Section {
            Button {
                renderTask?.cancel()
                renderTask = Task { await render() }
            } label: {
                HStack {
                    if phase == .rendering { ProgressView() }
                    Label(rendered == nil ? "Bu sahneyi seslendir" : "Yeniden seslendir", systemImage: "waveform")
                }
            }
            .disabled(busy || hasEmptyTurn || overLimit != nil || turns.isEmpty)
            if rendered != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { oldButton; newButton }
                    VStack(alignment: .leading, spacing: 8) { oldButton; newButton }
                }
                Button {
                    Task { await apply() }
                } label: {
                    HStack {
                        if phase == .applying { ProgressView().tint(.white) }
                        Label("Uygula", systemImage: "checkmark.circle.fill")
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
            }
        } header: {
            Text("Dinle ve uygula")
        } footer: {
            Text(settings.usesServerSpeech
                 ? "Sunucu motorunda günlük araç hakkından düşer; podcast hakkı harcanmaz. Uygulayınca eski hâli geri alabilirsin."
                 : "Ses iPhone'da üretilir; kota harcanmaz. Uygulayınca eski hâli geri alabilirsin.")
        }
    }

    private var oldButton: some View {
        Button {
            if let audio = episode.audioURL, let range = SceneEditor.sceneTimeRange(episode, sceneIndex: sceneIndex) {
                audition.toggle(.old, url: audio, range: range)
            }
        } label: {
            Label(audition.playing == .old ? "Durdur" : "Eski", systemImage: audition.playing == .old ? "stop.fill" : "play.fill")
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(audition.playing == .old ? "Eski hâli durdur" : "Eski hâli dinle")
    }

    private var newButton: some View {
        Button {
            if let rendered { audition.toggle(.new, url: rendered, range: nil) }
        } label: {
            Label(audition.playing == .new ? "Durdur" : "Yeni", systemImage: audition.playing == .new ? "stop.fill" : "play.fill")
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(.accentColor)
        .accessibilityLabel(audition.playing == .new ? "Yeni hâli durdur" : "Yeni hâli dinle")
    }

    // MARK: İşlemler

    private func load() {
        let current = episode.script?.flatScenes[safeScene: sceneIndex]?.scene.turns ?? []
        if original.isEmpty || original != current {
            original = current
            setTurns(current)
        }
        canUndo = SceneEditor.canUndo(episode)
    }

    private func rewrite() async {
        phase = .rewriting
        error = nil
        notice = nil
        defer { phase = .idle }
        do {
            let text = instruction == "Özel…" ? custom : instruction
            let result = try await SceneEditor.rewrite(episode, sceneIndex: sceneIndex, turns: turns, instruction: text, context: context)
            if !result.isEmpty { setTurns(result) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func render() async {
        audition.stop()
        phase = .rendering
        error = nil
        notice = nil
        defer { phase = .idle }
        let wanted = turns.map { turn in
            var t = turn
            t.text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t
        }
        do {
            let url = try await SceneEditor.render(episode, sceneIndex: sceneIndex, turns: wanted)
            guard isVisible, !Task.isCancelled else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            discardRendered()
            rendered = url
            renderedTurns = turns
            audition.toggle(.new, url: url, range: nil)
        } catch {
            guard isVisible, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    private func apply() async {
        guard let rendered, let renderedTurns else { return }
        audition.stop()
        phase = .applying
        error = nil
        defer { phase = .idle }
        let applied = renderedTurns.map { turn in
            var t = turn
            t.text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t
        }
        do {
            try await SceneEditor.applyRendered(episode, sceneIndex: sceneIndex, turns: applied, wav: rendered,
                                                expected: original, context: context, generator: generator)
            discardRendered()
            original = applied
            setTurns(applied)
            canUndo = SceneEditor.canUndo(episode)
            notice = "Sahne bölüme yerleştirildi."
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func undo() async {
        audition.stop()
        phase = .undoing
        error = nil
        defer { phase = .idle }
        do {
            try await SceneEditor.undo(episode, context: context, generator: generator)
            discardRendered()
            original = []
            load()
            canUndo = false
            notice = "Önceki hâline dönüldü."
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func setTurns(_ turns: [ScriptTurn]) {
        items = turns.map { StudioTurn(turn: $0) }
    }

    private func discardRendered() {
        if let rendered { try? FileManager.default.removeItem(at: rendered) }
        rendered = nil
        renderedTurns = nil
        if audition.playing == .new { audition.stop() }
    }
}

/// Stüdyoda düzenlenen tur (satır kimliği tur sayısı değişse de sabit kalır).
struct StudioTurn: Identifiable, Equatable {
    let id = UUID()
    var turn: ScriptTurn
}

/// Stüdyoda eski (bölüm sesindeki aralık) ve yeni (seslendirilen WAV) hâli çalar.
@MainActor
@Observable
final class StudioAudition {
    enum Source { case old, new }
    private(set) var playing: Source?
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var boundary: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    func toggle(_ source: Source, url: URL, range: ClosedRange<Double>?) {
        if playing == source { stop(); return }
        stop()
        AppState.current?.player.suspendForLiveSession()   // iki ses aynı anda çalmasın
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        if let range {
            player.seek(to: CMTime(seconds: range.lowerBound, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            let end = NSValue(time: CMTime(seconds: range.upperBound, preferredTimescale: 600))
            boundary = player.addBoundaryTimeObserver(forTimes: [end], queue: .main) { @Sendable [weak self] in
                MainActor.assumeIsolated { self?.stop() }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { @Sendable [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        player.play()
        playing = source
    }

    func stop() {
        player?.pause()
        if let boundary { player?.removeTimeObserver(boundary) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        boundary = nil
        endObserver = nil
        player = nil
        playing = nil
    }
}
