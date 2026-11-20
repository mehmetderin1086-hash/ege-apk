import AVFoundation
import Foundation
import Observation

/// Sesli yanıt: metni parçalara böler, motorları sırayla dener (Azure → Chirp → cihaz sesi), sıradaki parçayı çalarken üretir.
@MainActor @Observable final class VoicePlayer: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    static let shared = VoicePlayer()
    private(set) var isSpeaking = false
    private(set) var lastEngine = ""
    private(set) var lastError: String?
    private var player: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    private var finish: CheckedContinuation<Void, Never>?
    private var job: Task<Void, Never>?

    override init() { super.init(); synthesizer.delegate = self }

    /// Ses oturumu: konuşurken dinleyebilmek için `record` true (yankı önleme için voiceChat kipi).
    static func configureSession(record: Bool) {
        let session = AVAudioSession.sharedInstance()
        if record { try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothA2DP, .allowBluetooth]) }
        else { try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers]) }
        try? session.setActive(true)
    }

    /// Her motoru sırayla dener; hata mesajını `lastError`'a yazar. Cihaz sesi hep son çaredir.
    nonisolated static func synthesize(_ text: String, order: [VoiceEngine]) async -> (clip: AudioClip, engine: String, error: String?)? {
        var lastFailure: String?
        for engine in order {
            do {
                switch engine {
                case .azure:
                    guard let key = VoiceConfig.azureKey, !key.isEmpty else { continue }
                    let provider = AzureTTS(key: key, region: VoiceConfig.azureRegion, voice: VoiceConfig.azureVoice, rate: VoiceConfig.rate)
                    return (try await provider.synthesize(text), provider.name, lastFailure)
                case .chirp:
                    guard let host = VoiceConfig.serverHost, let token = VoiceConfig.serverToken else { continue }
                    let provider = ChirpTTS(host: host, token: token, voice: VoiceConfig.chirpVoice, rate: VoiceConfig.rate)
                    return (try await provider.synthesize(text), provider.name, lastFailure)
                default: continue
                }
            } catch is CancellationError { return nil }
            catch { lastFailure = error.localizedDescription }
        }
        return nil
    }

    /// Metni seslendirir; bitince ya da `stop()` çağrılınca döner.
    func speak(_ text: String, recording: Bool = false) async {
        stop()
        let spoken = SpeechText.spoken(from: text)
        let chunks = SpeechText.chunks(spoken)
        guard !chunks.isEmpty else { return }
        Self.configureSession(record: recording)
        isSpeaking = true; lastError = nil
        let order = VoiceRouter.order(VoiceConfig.engine, azureConfigured: VoiceConfig.azureConfigured, serverConfigured: VoiceConfig.serverConfigured)
        // Tüm parçalar paralel üretilir (en çok 3 eşzamanlı), sırayla çalınır.
        let tasks = chunks.map { chunk in Task.detached { await Self.synthesize(chunk, order: order) } }
        let current = Task { @MainActor in
            for (index, task) in tasks.enumerated() {
                if Task.isCancelled { break }
                if let made = await task.value {
                    lastEngine = made.engine; if let error = made.error { lastError = error }
                    await play(made.clip)
                } else {
                    lastEngine = "Cihaz sesi"
                    await speakWithDevice(chunks[index])
                }
            }
        }
        job = current
        await current.value
        for task in tasks { task.cancel() }
        isSpeaking = false
    }

    func stop() {
        job?.cancel(); job = nil
        player?.stop(); player = nil
        synthesizer.stopSpeaking(at: .immediate)
        finish?.resume(); finish = nil
        isSpeaking = false
    }

    private func play(_ clip: AudioClip) async {
        guard let audio = try? AVAudioPlayer(data: clip.data, fileTypeHint: clip.fileExtension == "mp3" ? AVFileType.mp3.rawValue : AVFileType.wav.rawValue) else { return }
        audio.delegate = self; player = audio
        await withCheckedContinuation { continuation in
            finish = continuation
            if !audio.play() { finish = nil; continuation.resume() }
        }
        player = nil
    }

    private func speakWithDevice(_ text: String) async {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR"); utterance.rate = 0.5
        await withCheckedContinuation { continuation in
            finish = continuation
            synthesizer.speak(utterance)
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor in self.finish?.resume(); self.finish = nil } }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { Task { @MainActor in self.finish?.resume(); self.finish = nil } }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { Task { @MainActor in self.finish?.resume(); self.finish = nil } }
}
