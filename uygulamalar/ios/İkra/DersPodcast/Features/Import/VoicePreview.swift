import AVFoundation
import Observation
import SwiftUI

/// Uygulamaya gömülü ses örneklerini (Resources/VoiceSamples/voice_<Ad>.m4a) çalar.
@Observable
final class VoicePreview {
    static let shared = VoicePreview()
    private(set) var playing: String?
    private var player: AVAudioPlayer?

    func play(_ voice: String) {
        guard let url = Bundle.main.url(forResource: "voice_\(voice)", withExtension: "m4a") else { return }
        if playing == voice {
            stop()
            return
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
        playing = voice
        let duration = player?.duration ?? 8
        Task {
            try? await Task.sleep(for: .seconds(duration + 0.2))
            if playing == voice { playing = nil }
        }
    }

    func stop() {
        player?.stop()
        playing = nil
    }
}

/// #14: üretimden önce sunucu sesiyle kısa prova (`/v1/speak`, podcast2).
@Observable
final class VoiceRehearsal {
    static let shared = VoiceRehearsal()
    private(set) var loading: String?
    private(set) var playing: String?
    private(set) var errors: [String: String] = [:]
    private var player: AVAudioPlayer?
    private var task: Task<Void, Never>?

    /// #14: provada ses tonu stili (≤120). Sunucu bundan hız (Edge'de perde de) türetir.
    nonisolated static func style(tone: PodcastTone, speaker: Speaker) -> String {
        let base = switch tone {
        case .samimi: "sıcak, samimi"
        case .akademik: "sakin, ciddi"
        case .eglenceli: "neşeli, canlı"
        case .sinav: "net, tempolu"
        }
        return speaker == .b ? "meraklı, " + base : base
    }

    func toggle(key: String, request: SpeakRequest) {
        if playing == key || loading == key {
            stop()
            return
        }
        stop()
        loading = key
        errors[key] = nil
        task = Task {
            defer { if loading == key { loading = nil } }
            do {
                let response = try await APIClient.shared.speak(request)
                try Task.checkCancellation()
                guard let data = Data(base64Encoded: response.audio) else {
                    errors[key] = "Ses yanıtı okunamadı."
                    return
                }
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try? AVAudioSession.sharedInstance().setActive(true)
                player = try AVAudioPlayer(data: data)
                player?.play()
                loading = nil
                playing = key
                try? await Task.sleep(for: .seconds((player?.duration ?? 6) + 0.2))
                if playing == key { playing = nil }
            } catch is CancellationError {
            } catch {
                errors[key] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        player?.stop()
        playing = nil
        loading = nil
    }
}

/// Form satırı: seçili sesi gösterir, dokununca 30 hazır sesin (Chirp 3 HD) önizlemeli listesini açar.
struct VoiceChooserRow: View {
    let title: String
    @Binding var voice: String
    /// Listede gösterilmeyecek sesler (ör. diğer konuşmacının sesi).
    var excluded: [String] = []

    var body: some View {
        NavigationLink {
            VoiceChooserList(title: title, voice: $voice, excluded: excluded)
        } label: {
            LabeledContent(title, value: VoiceOption.title(voice))
        }
        .accessibilityHint("Bütün sesleri dinleyip seçmek için dokun")
    }
}

/// Hazır sesler (Chirp 3 HD): her satırda örneği çalan düğme, ad ve karakter; satıra dokununca ses seçilir.
struct VoiceChooserList: View {
    let title: String
    @Binding var voice: String
    var excluded: [String] = []
    @State private var samples = VoicePreview.shared

    var body: some View {
        List {
            Section {
                ForEach(VoiceOption.all.filter { !excluded.contains($0.id) || $0.id == voice }) { option in
                    HStack(spacing: 12) {
                        Button {
                            samples.play(option.id)
                        } label: {
                            Image(systemName: samples.playing == option.id ? "stop.circle.fill" : "play.circle.fill")
                                .font(.title2).frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(samples.playing == option.id ? "\(option.id) örneğini durdur" : "\(option.id) örneğini dinle")
                        Button {
                            voice = option.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.id).font(.body.weight(.medium)).foregroundStyle(.primary)
                                    Text(option.trait).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if option.id == voice { Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(.tint) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(option.id), \(option.trait)")
                        .accessibilityAddTraits(option.id == voice ? .isSelected : [])
                    }
                }
            } footer: {
                Text("Oynat düğmesi kısa bir örnek çalar; satıra dokununca ses seçilir. Seçim, bundan sonra hazırlanan anlatımlarda kullanılır.")
            }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .onDisappear { samples.stop() }
    }
}
