import AVFoundation
import Observation
import PDFKit
import SwiftData
import SwiftUI
import UIKit

// MARK: - Öneri 1: üretim sürerken hazır sahneleri dinle

/// Hazır sahne WAV'larını sırayla çalar; yeni sahneler hazır oldukça kuyruğa ekler.
@Observable
final class PreviewPlayer {
    private(set) var isPlaying = false
    private(set) var currentScene: Int?
    private(set) var episodeID: UUID?
    private var player: AVQueuePlayer?
    private var queued: [Int] = []
    /// Kuyruktaki her öğenin sahne indeksi (gösterilen metin çalan öğeye göre seçilir).
    private var itemScenes: [ObjectIdentifier: Int] = [:]
    private var itemObservation: NSKeyValueObservation?
    private var poll: Task<Void, Never>?
    private var endObserver: NSObjectProtocol?

    func start(_ episode: Episode) {
        stop()
        AppState.current?.player.suspendForLiveSession()   // iki ses aynı anda çalmasın
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        let player = AVQueuePlayer()
        self.player = player
        episodeID = episode.id
        enqueueNew(episode)
        player.play()
        isPlaying = true
        // Gösterilen sahne = şu an çalan öğe (başka oynatıcıların bitiş bildirimleri karışmaz).
        itemObservation = player.observe(\.currentItem, options: [.new]) { [weak self] player, _ in
            let item = player.currentItem.map(ObjectIdentifier.init)
            Task { @MainActor in
                guard let self else { return }
                self.currentScene = item.flatMap { self.itemScenes[$0] }
            }
        }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                // Üretim bitti ya da durduruldu: önizleme de dursun.
                if episode.status != .generating || !(AppState.current?.generator.isRunning(episode) ?? false) { self.stop(); return }
                self.enqueueNew(episode)
            }
        }
    }

    func toggle() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    func stop() {
        poll?.cancel()
        player?.pause()
        player?.removeAllItems()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        itemObservation?.invalidate()
        itemObservation = nil
        player = nil
        queued = []
        itemScenes = [:]
        currentScene = nil
        isPlaying = false
        episodeID = nil
    }

    private func enqueueNew(_ episode: Episode) {
        guard let player else { return }
        for scene in GenerationCoordinator.readyScenes(episode) where !queued.contains(scene.index) {
            let item = AVPlayerItem(url: scene.url)
            itemScenes[ObjectIdentifier(item)] = scene.index
            player.insert(item, after: nil)
            queued.append(scene.index)
        }
        if currentScene == nil, let item = player.currentItem { currentScene = itemScenes[ObjectIdentifier(item)] }
        if isPlaying, player.rate == 0, player.currentItem != nil { player.play() }
    }

}

struct PreviewBar: View {
    var episode: Episode
    var preview: PreviewPlayer

    var body: some View {
        let ready = GenerationCoordinator.readyScenes(episode).count
        VStack(spacing: 10) {
            if preview.episodeID == episode.id, let scene = preview.currentScene,
               let turns = episode.script?.flatScenes[safe: scene]?.scene.turns {
                Text(turns.map(\.text).joined(separator: " "))
                    .font(.callout)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                    .animation(.smooth, value: scene)
            }
            Button {
                if preview.episodeID == episode.id { preview.toggle() } else { preview.start(episode) }
            } label: {
                Label(preview.episodeID == episode.id && preview.isPlaying ? "Duraklat" : (ready == 0 ? "İlk sahne hazırlanıyor…" : "Dinlemeye başla · \(ready) sahne hazır"),
                      systemImage: preview.episodeID == episode.id && preview.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle(enabled: ready > 0))
            .disabled(ready == 0)
            Text("Kalan sahneler sen dinlerken hazırlanır. Bölüm tamamlanınca transkriptli oynatıcıya geçilir.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Öneri 2: sesi yeniden üret

struct RegenerateAudioSheet: View {
    var episode: Episode
    @Environment(GenerationCoordinator.self) private var generator
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var settings = PodcastSettings()
    /// Bu bölüm için seçilen sesler (`QSVoiceKey.raw`); bölümün kendi sesleriyle açılır, uygulamanın tek ses ayarını değiştirmez.
    @State private var voiceA = AppVoice.primaryChoice().raw
    @State private var voiceB = AppVoice.secondaryChoice().raw
    /// "Claude + Chirp": bölüm öyle üretildiyse açık başlar; yalnız Chirp seslerinde anlamlıdır.
    @State private var claudeReadings = AppVoice.claudeReadings()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Senaryo aynı kalır; yalnızca ses seçtiğin seslerle baştan üretilir. Transkript, quiz ve notların korunur.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section("Sesler") {
                    AppVoiceRow(title: settings.hostA.name, raw: $voiceA)
                    if settings.format.usesTwoHosts {
                        AppVoiceRow(title: settings.hostB.name, raw: $voiceB, excluded: [voiceA], onlyEngine: QSVoiceKey(voiceA).engine)
                    }
                    if QSVoiceKey(voiceA).engine == .chirp { Toggle("Okunuşları Claude hazırlasın", isOn: $claudeReadings) }
                }
                // Anlatıcının motoru değişince ikinci ses de o motordan türetilir (bir senaryo tek sağlayıcıdan seslendirilir).
                .onChange(of: voiceA) { _, raw in voiceB = AppVoice.partner(QSVoiceKey(voiceB), avoiding: QSVoiceKey(raw)).raw }
                Section("Ses kimliği") {
                    SoundIdentityPicker(selection: $settings.soundIdentity)
                }
            }
            .navigationTitle("Sesi yeniden üret")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Üret") {
                        func reading(_ raw: String) -> QSVoiceKey { let key = QSVoiceKey(raw); return key.engine == .chirp && claudeReadings ? QSVoiceKey(name: key.name, chirp: .claude) : key }
                        settings.apply(voiceA: reading(voiceA), voiceB: reading(voiceB))
                        generator.regenerateAudio(episode, settings: settings, context: context)
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard let s = episode.settings else { return }
                settings = s
                voiceA = AppVoice.usable(s.voiceKey(.a).raw)?.raw ?? voiceA
                voiceB = AppVoice.usable(s.voiceKey(.b).raw)?.raw ?? voiceB
                claudeReadings = s.engine == .claude
            }
        }
    }
}

// MARK: - Öneri 3: sahneyi yeniden yaz

struct SceneRewriteSheet: View {
    var episode: Episode
    var sceneIndex: Int
    @Environment(GenerationCoordinator.self) private var generator
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var instruction = "Daha basit anlat"
    @State private var custom = ""
    @State private var result: [ScriptTurn]?
    @State private var working = false
    @State private var applying = false
    @State private var error: String?
    @State private var confirmDiscard = false

    private let presets = ["Daha basit anlat", "Somut bir örnek ekle", "Kısalt", "Daha ayrıntılı anlat", "Bir benzetmeyle açıkla", "Özel…"]
    /// "Özel…" seçiliyken istek boş gönderilmez.
    private var missingCustom: Bool { instruction == "Özel…" && custom.trimmingCharacters(in: .whitespaces).isEmpty }

    private var scene: ScriptScene? { episode.script?.flatScenes[safe: sceneIndex]?.scene }

    var body: some View {
        NavigationStack {
            Form {
                if let scene {
                    Section("Şu anki sahne") {
                        ForEach(Array(scene.turns.enumerated()), id: \.offset) { _, turn in
                            Text(turn.text).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Nasıl değişsin?") {
                    Picker("İstek", selection: $instruction) { ForEach(presets, id: \.self) { Text($0).tag($0) } }
                    if instruction == "Özel…" {
                        TextField("Ör. formülü adım adım açıkla", text: $custom, axis: .vertical).lineLimit(2...4)
                    }
                    Button {
                        Task { await rewrite() }
                    } label: { HStack { if working { ProgressView() }; Text(result == nil ? "Yeniden yaz" : "Bir daha dene") } }
                    .disabled(working || applying || missingCustom)
                }
                if let result {
                    Section("Yeni hali") {
                        ForEach(Array(result.enumerated()), id: \.offset) { _, turn in Text(turn.text).font(.callout) }
                    }
                    Section {
                        Button {
                            Task { await apply(result) }
                        } label: { HStack { if applying { ProgressView() }; Text("Uygula ve seslendir") } }
                        .disabled(applying)
                    } footer: {
                        Text("Yalnızca bu sahne yeniden seslendirilir ve bölüme yerleştirilir.")
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Sahneyi yeniden yaz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") {
                        if result != nil { confirmDiscard = true } else { dismiss() }
                    }
                    .disabled(applying)
                }
            }
            // Üretilmiş "Yeni hali" aşağı kaydırmayla sessizce kaybolmasın.
            .interactiveDismissDisabled(applying || working || result != nil)
            .confirmationDialog("Yeni hâl atılsın mı?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Yeni hâli at", role: .destructive) { dismiss() }
                Button("Düzenlemeye dön", role: .cancel) {}
            } message: {
                Text("Yazılan yeni hâl uygulanmadı; kapatırsan silinir.")
            }
        }
    }

    private func rewrite() async {
        guard let scene else { return }
        working = true
        error = nil
        defer { working = false }
        do {
            // #10: bölümün kendi tempo, derinlik ve konuğu; varsa kaynak sayfaları.
            result = try await SceneEditor.rewrite(episode, sceneIndex: sceneIndex, turns: scene.turns,
                                                   instruction: instruction == "Özel…" ? custom : instruction, context: context)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func apply(_ turns: [ScriptTurn]) async {
        applying = true
        error = nil
        defer { applying = false }
        do {
            try await generator.replaceScene(episode, sceneIndex: sceneIndex, turns: turns, context: context)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
