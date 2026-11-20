import AVFoundation
import SwiftUI

struct OfflineSpeechModelsView: View {
    @State private var settings = PodcastSettings(speechProvider: "supertonic")
    var body: some View {
        Form {
            Section {
                Text("Modelleri bir kez indir; hazır senaryoları iPhone’da çevrimdışı seslendir. Yeni belgeden senaryo oluşturmak için mevcut yapay zekâ bağlantısı kullanılır.")
            }
            Section("Supertonic 3") {
                OfflineModelControls(engine: .supertonic)
                SupertonicVoiceOptions(settings: $settings)
                OfflineVoicePreviewButton(engine: .supertonic, voice: settings.localVoiceA, title: "Birinci sesi dinle")
                OfflineVoicePreviewButton(engine: .supertonic, voice: settings.localVoiceB, title: "İkinci sesi dinle")
                Text("5 kadın ve 5 erkek ses · Türkçe ve İngilizce · OpenRAIL-M. Ana modelin resmî geliştirmesi sona ermiştir; bu sürüm topluluk Core ML uyarlamasını kullanır.")
                    .font(.footnote).foregroundStyle(.secondary)
                Link("Hugging Face model bilgileri", destination: URL(string: "https://huggingface.co/FluidInference/supertonic-3-coreml")!)
            }
            Section("EMA-TTS") {
                OfflineModelControls(engine: .ema)
                OfflineVoicePreviewButton(engine: .ema, voice: "tr", title: "Sesi dinle")
                OfflineVoicePreviewButton(engine: .ema, voice: "coskulu", title: "Coşkulu sesi dinle")
                Text("Türkçe tek ses · 48 kHz · Apache-2.0. Freya-TR-Eval’de %3,0 kelime hatası (açık Türkçe sistemlerin en düşüğü). Kısa sözcelerde zayıf, uzun cümlede güçlüdür; dört ONNX parça İkra sunucusundan iner. “Coşkulu” ses, YouTube’daki Creative Commons BY lisanslı biyoloji dersleriyle (Biyoizm kanalı) ince ayarlanmış sürümdür; kelime hatası taban sese göre biraz yüksektir (ölçüm: %2,1 / %1,2).")
                    .font(.footnote).foregroundStyle(.secondary)
                Link("Hugging Face model bilgileri", destination: URL(string: "https://huggingface.co/canberkkkkkk/ema-tts")!)
            }
            Section("Piper Türkçe") {
                OfflineModelControls(engine: .piper)
                OfflineVoicePreviewButton(engine: .piper, voice: "dfki", title: "Tek anlatıcıyı dinle")
                Text("DFKI tek anlatıcı · Türkçe. Model kartındaki veri lisansı CC-BY-NC-SA 4.0: ticari olmayan kullanım.")
                    .font(.footnote).foregroundStyle(.secondary)
                Link("Hugging Face model ve lisans bilgileri", destination: URL(string: "https://huggingface.co/rhasspy/piper-voices/blob/main/tr/tr_TR/dfki/medium/MODEL_CARD")!)
            }
            Section {
                NavigationLink("Açık kaynak lisansları") {
                    ScrollView {
                        Text(Bundle.main.url(forResource: "OfflineSpeechLicenses", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "Lisans bilgileri model bağlantılarında bulunur.")
                            .font(.caption).textSelection(.enabled).padding()
                    }.navigationTitle("Lisanslar")
                }
            }
        }
        .navigationTitle("iPhone ses modelleri")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { OfflineSpeechModels.shared.refresh() }
    }
}

struct OfflineModelControls: View {
    let engine: SpeechEngine
    @State private var models = OfflineSpeechModels.shared
    @State private var confirmRemove = false
    @State private var removing = false
    var body: some View {
        let state = models.state(engine)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(state.ready ? "Çevrimdışı kullanıma hazır" : "Model indirme", systemImage: state.ready ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(state.ready ? .green : .primary)
                Spacer()
                Text(OfflineModelCatalog.sizeLabel(engine)).font(.caption).foregroundStyle(.secondary)
            }
            if state.removing {
                ProgressView("Model kapatılıyor…")
            } else if state.downloading {
                ProgressView(value: state.progress)
                HStack {
                    Text("İndiriliyor · %\(Int(state.progress * 100))").font(.caption)
                    Spacer()
                    Button("Durdur") { models.cancel(engine) }.buttonStyle(.borderless)
                }
            } else if state.ready {
                Button(removing ? "Model kapatılıyor…" : "Modeli telefondan kaldır", role: .destructive) { confirmRemove = true }
                    .buttonStyle(.borderless).disabled(removing)
            } else {
                Button("Modeli indir", systemImage: "arrow.down.circle") { models.download(engine) }
                    .buttonStyle(.bordered).accessibilityIdentifier("download-\(engine.rawValue)")
            }
            if let message = state.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 4)
        .confirmationDialog("Ses modeli kaldırılsın mı?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Modeli kaldır", role: .destructive) {
                removing = true
                Task { await models.remove(engine); removing = false }
            }
        } message: { Text("İndirilen model dosyaları kaldırılır. Hazır kayıtlar korunur; modeli daha sonra yeniden indirebilirsin.") }
    }
}

struct SupertonicVoiceOptions: View {
    @Binding var settings: PodcastSettings
    var body: some View {
        Picker(settings.format.usesTwoHosts ? "Birinci sunucu" : "Anlatıcı sesi", selection: $settings.localVoiceA) {
            ForEach(1...5, id: \.self) { Text("Kadın \($0)").tag("F\($0)") }
            ForEach(1...5, id: \.self) { Text("Erkek \($0)").tag("M\($0)") }
        }
        if settings.format.usesTwoHosts {
            Picker("İkinci sunucu", selection: $settings.localVoiceB) {
                ForEach(1...5, id: \.self) { Text("Kadın \($0)").tag("F\($0)") }
                ForEach(1...5, id: \.self) { Text("Erkek \($0)").tag("M\($0)") }
            }
        }
    }
}

@Observable
final class OfflineVoicePreview {
    static let shared = OfflineVoicePreview()
    private(set) var activeID: String?
    private(set) var preparing = false
    private(set) var errors: [String: String] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var generation: UUID?

    func stop() {
        generation = nil; task?.cancel(); task = nil
        player?.stop(); player = nil; activeID = nil; preparing = false
    }
    func play(id: String, engine: SpeechEngine, voice: String) {
        if activeID == id { stop(); return }
        stop()
        let token = UUID()
        generation = token; activeID = id; preparing = true; errors[id] = nil
        task = Task {
            defer {
                if generation == token { activeID = nil; preparing = false; task = nil; player = nil }
            }
            do {
                var settings = PodcastSettings(speechProvider: engine.rawValue)
                settings.format = .tekAnlatici
                if engine == .supertonic || engine == .ema { settings.localVoiceA = voice }
                let clip = try await LocalSpeech.scene(turns: [.init(speaker: .a,
                    text: "Merhaba. Hücre canlıların temel yapı ve görev birimidir. Bugün birlikte biyoloji öğreneceğiz.", style: "", sourcePage: nil)], settings: settings)
                try Task.checkCancellation()
                AppState.current?.player.suspendForLiveSession()
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
                let audio = try AVAudioPlayer(data: WAV.encode(clip))
                player = audio; preparing = false
                guard audio.play() else { throw OfflineSpeechError.noAudio }
                while audio.isPlaying { try await Task.sleep(for: .milliseconds(200)) }
            } catch is CancellationError {} catch {
                if generation == token { errors[id] = error.localizedDescription }
            }
        }
    }
}

struct OfflineVoicePreviewButton: View {
    let engine: SpeechEngine
    let voice: String
    let title: String
    @State private var models = OfflineSpeechModels.shared
    @State private var preview = OfflineVoicePreview.shared
    private var id: String { engine.rawValue + voice + title }
    var body: some View {
        let active = preview.activeID == id
        VStack(alignment: .leading, spacing: 4) {
            Button(active ? (preview.preparing ? "Hazırlamayı durdur" : "Sesi durdur") : title,
                   systemImage: active ? "stop.circle" : "play.circle") {
                preview.play(id: id, engine: engine, voice: voice)
            }
            .buttonStyle(.borderless)
            .disabled(!models.state(engine).ready)
            if let error = preview.errors[id] { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .onChange(of: voice) { _, _ in preview.stop() }
        .onLeave { if preview.activeID == id { preview.stop() } }
    }
}
