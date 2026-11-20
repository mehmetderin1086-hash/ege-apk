import AVFoundation
import SwiftUI

/// #12: senaryodaki okunuşu riskli terimler (`/v1/pronunciation-suggest`) tek dokunuşla sözlüğe eklenir.
struct PronunciationSuggestionsSheet: View {
    let episode: Episode
    /// Yalnız önizleme/test: sunucuya gitmeden gösterilecek öneriler.
    var previewItems: [PronunciationSuggestion]? = nil
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var items: [PronunciationSuggestion] = []
    @State private var edits: [String: String] = [:]
    @State private var dictionary = Pronunciations.all
    @State private var loading = false
    @State private var loaded = false
    @State private var error: String?
    @State private var listener = PronunciationListener()

    private var supported: Bool { previewItems != nil || app.serverSupports("podcast2") }
    private var full: Bool { dictionary.count >= Pronunciations.limit }

    var body: some View {
        NavigationStack {
            List {
                if !supported {
                    ContentUnavailableView("Sunucu güncel değil", systemImage: "icloud.slash",
                                           description: Text("Telaffuz önerileri için sunucunun güncellenmesi gerekiyor."))
                } else if loading {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Okunuşu riskli terimler aranıyor…").foregroundStyle(.secondary)
                    }
                } else if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                        Button("Yeniden dene") { Task { await load() } }
                    }
                } else if loaded && items.isEmpty {
                    ContentUnavailableView("Öneri yok", systemImage: "checkmark.seal",
                                           description: Text("Bu bölümde okunuşu riskli yeni bir terim bulunamadı."))
                } else {
                    Section {
                        ForEach(items, id: \.from) { item in row(item) }
                        // Araç çubuğunda değil: dar ekranda başlığı itmesin.
                        if items.filter({ !isAdded($0) }).count > 1, !full {
                            Button {
                                for item in items where !isAdded(item) { add(item) }
                            } label: {
                                Label("Tümünü onayla", systemImage: "checkmark.circle").frame(minHeight: 44)
                            }
                        }
                    } header: {
                        Text("Önerilen okunuşlar")
                    } footer: {
                        Text(full
                             ? "Sözlük dolu (\(Pronunciations.limit)/\(Pronunciations.limit)). Yer açmak için Telaffuz ekranından kayıt sil."
                             : "Onaylananlar yeni üretilen seslerde tüm motorlarda uygulanır. Bu bölüm için Sahne stüdyosu ya da Sesi yeniden üret. Sözlük: \(dictionary.count)/\(Pronunciations.limit)")
                    }
                }
            }
            .navigationTitle("Telaffuz önerileri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
            }
            .task { if !loaded { await load() } }
            .onDisappear { listener.stop() }
        }
    }

    private func row(_ item: PronunciationSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.from).font(.headline)
            TextField("Okunuş", text: Binding(get: { edits[item.from] ?? item.to },
                                              set: { edits[item.from] = Pronunciations.clipped($0, to: Pronunciations.maxToLength) }))
                .textFieldStyle(.roundedBorder)
                .disabled(isAdded(item))
                .accessibilityLabel("\(item.from) okunuşu")
            if !item.why.isEmpty {
                Text(item.why).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack { listenButton(item); Spacer(); addButton(item) }
                VStack(alignment: .leading, spacing: 8) { listenButton(item); addButton(item) }
            }
        }
        .padding(.vertical, 4)
    }

    private func listenButton(_ item: PronunciationSuggestion) -> some View {
        let text = edits[item.from] ?? item.to
        return Button {
            Task { await listener.toggle(text, settings: episode.settings ?? PodcastSettings(), server: supported) }
        } label: {
            Label(listener.speaking == text ? "Durdur" : "Dinle", systemImage: listener.speaking == text ? "stop.fill" : "speaker.wave.2")
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(listener.speaking == text ? "Durdur" : "\(text) okunuşunu dinle")
    }

    @ViewBuilder private func addButton(_ item: PronunciationSuggestion) -> some View {
        if isAdded(item) {
            Label("Eklendi", systemImage: "checkmark").foregroundStyle(.green).frame(minHeight: 44)
        } else {
            Button {
                add(item)
            } label: {
                Text("Onayla").frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(full || (edits[item.from] ?? item.to).trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func isAdded(_ item: PronunciationSuggestion) -> Bool {
        dictionary.contains { $0.id == TurkishFold.fold(item.from.trimmingCharacters(in: .whitespaces)) }
    }

    private func add(_ item: PronunciationSuggestion) {
        guard !full else { return }
        Pronunciations.set(item.from, edits[item.from] ?? item.to)
        dictionary = Pronunciations.all
    }

    private func load() async {
        if let previewItems {
            items = previewItems
            loaded = true
            return
        }
        guard supported, let script = episode.script else { loaded = true; return }
        loading = true
        error = nil
        defer { loading = false; loaded = true }
        do {
            let request = Self.request(script: script, dictionary: Pronunciations.all)
            let known = Set(Pronunciations.all.map(\.id))
            var seen = Set<String>()
            items = try await APIClient.shared.pronunciationSuggest(request).filter {
                let key = TurkishFold.fold($0.from.trimmingCharacters(in: .whitespaces))
                return !key.isEmpty && !known.contains(key) && seen.insert(key).inserted
            }
            .prefix(Pronunciations.limit).map { $0 }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// İstek: metin ≤30 bin karakter, bilinen kayıtlar ≤100 ve her biri ≤60 karakter (sunucu sınırları).
    static func request(script: PodcastScript, dictionary: [Pronunciation]) -> PronunciationSuggestRequest {
        let text = script.flatScenes.flatMap { $0.scene.turns.map(\.text) }.joined(separator: "\n")
        let known = dictionary.map(\.from).filter { $0.utf16.count <= Pronunciations.maxFromLength }
        return PronunciationSuggestRequest(text: String(text.prefix(30_000)), known: Array(known.prefix(100)))
    }
}

/// Okunuşu dinletir: sunucu motorunda bölümün sesiyle (`/v1/speak`), değilse cihaz sesiyle.
@MainActor
@Observable
final class PronunciationListener {
    private(set) var speaking: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var device = SpeechOut()

    func toggle(_ text: String, settings: PodcastSettings, server: Bool) async {
        if speaking == text { stop(); return }
        stop()
        AppState.current?.player.suspendForLiveSession()   // bölüm sesiyle üst üste çalmasın
        speaking = text
        defer { if speaking == text, player == nil { speaking = nil } }
        if server, settings.usesServerSpeech,
           let response = try? await APIClient.shared.speak(SpeakRequest(engine: settings.engine.voicedBy.rawValue, voice: settings.hostA.voice,
                                                                         pace: settings.pace, style: nil, text: String(text.prefix(200)),
                                                                         replacements: nil)),
           let data = Data(base64Encoded: response.audio), let player = try? AVAudioPlayer(data: data) {
            guard speaking == text else { return }
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
            self.player = player
            player.play()
            try? await Task.sleep(for: .seconds(player.duration + 0.1))
            if self.player === player { stop() }
            return
        }
        await device.speak(text)
    }

    func stop() {
        player?.stop()
        player = nil
        device.stop()
        speaking = nil
    }
}
