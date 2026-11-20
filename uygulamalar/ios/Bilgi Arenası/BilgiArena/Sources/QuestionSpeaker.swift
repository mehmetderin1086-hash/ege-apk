import AVFoundation
import Combine

@MainActor final class QuestionSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published private(set) var playing = false
    @Published private(set) var error: String?
    private(set) var everStarted = false
    @Published private(set) var source = ""
    private var player: AVAudioPlayer?
    private var generation = UUID()
    private let synthesizer = AVSpeechSynthesizer()
    private var utterance: AVSpeechUtterance?
    private var preparation: Task<Void,Never>?
    private var watchdog: Task<Void,Never>?
    private var completion: ((Bool) -> Void)?
    override init() { super.init(); synthesizer.delegate = self; synthesizer.usesApplicationAudioSession = true }
    func speak(_ activity: QuestionActivity, choice: QuestionVoiceChoice? = nil, completion: @escaping (Bool) -> Void) {
        cancel(); error = nil; everStarted = false
        guard activity.isValid, (activity.kind == .listening || activity.kind == .pronunciation), let text = activity.transcript, let language = activity.language else {
            error = "Soru sesi verisi geçersiz."; completion(false); return
        }
        speakText(text,language:language,choice:choice,completion:completion)
    }
    func speakText(_ text: String, language: String = "tr-TR", choice: QuestionVoiceChoice? = nil, completion: @escaping (Bool) -> Void) {
        cancel(); error = nil; everStarted = false
        guard (1...1200).contains(text.count), QuestionActivity.languages.contains(language) else { error = "Ses metni geçersiz."; completion(false); return }
        let choice = choice ?? QuestionVoiceChoice.current(language:language)
        source = choice.engine.title
        if choice.engine != .apple { speakCloud(text:text,language:language,choice:choice,completion:completion); return }
        guard let voice = AVSpeechSynthesisVoice(language:language) else {
            error = "Bu dilin sesi cihazda bulunamadı. Metni açarak devam edebilirsin."; completion(false); return
        }
        let value = AVSpeechUtterance(string:text)
        value.voice = voice; value.rate = min(AVSpeechUtteranceMaximumSpeechRate,AVSpeechUtteranceDefaultSpeechRate * 0.9 * Float(ArenaPreferences.speechRate()))
        self.utterance = value; self.completion = completion; playing = true
        preparation = Task { [weak self] in
            let ready: Bool = await withCheckedContinuation { continuation in
                GameAudio.sessionQueue.async {
                    do {
                        try AVAudioSession.sharedInstance().setCategory(.playback,mode:.spokenAudio,options:[.duckOthers])
                        try AVAudioSession.sharedInstance().setActive(true)
                        continuation.resume(returning:true)
                    } catch { continuation.resume(returning:false) }
                }
            }
            guard let self, !Task.isCancelled, self.utterance === value else { return }
            guard ready else { self.finish(value,success:false); return }
            self.synthesizer.speak(value)
            self.watchdog = Task { [weak self] in
                try? await Task.sleep(for:.seconds(8))
                guard !Task.isCancelled, let self, self.utterance === value else { return }
                if !self.everStarted { self.finish(value,success:false) }
            }
        }
    }
    private func speakCloud(text: String, language: String, choice: QuestionVoiceChoice, completion: @escaping (Bool) -> Void) {
        self.completion = completion; playing = true
        let id = generation
        preparation = Task { [weak self] in
            do {
                let file = try await QuestionVoiceAPI.shared.audio(text:text,language:language,choice:choice)
                try Task.checkCancellation()
                let ready: Bool = await withCheckedContinuation { continuation in
                    GameAudio.sessionQueue.async {
                        do { try AVAudioSession.sharedInstance().setCategory(.playback,mode:.spokenAudio,options:[.duckOthers]); try AVAudioSession.sharedInstance().setActive(true); continuation.resume(returning:true) }
                        catch { continuation.resume(returning:false) }
                    }
                }
                guard let self, !Task.isCancelled, self.generation == id else { return }
                guard ready else { throw QuizError("Ses çıkışı açılamadı.") }
                let player = try AVAudioPlayer(contentsOf:file); self.player = player; player.delegate = self
                guard player.play() else { throw QuizError("Örnek ses başlatılamadı.") }; self.everStarted = true
            } catch {
                guard let self, self.generation == id, !Task.isCancelled else { return }
                let callback = self.completion; self.cancel()
                self.error = (error as? QuizError)?.message ?? "Soru sesi alınamadı. Yeniden dene veya metinle devam et."
                callback?(false)
            }
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            let callback = self.completion; self.cancel()
            if !flag { self.error = "Soru sesi tamamlanamadı." }; callback?(flag)
        }
    }
    private func finish(_ value: AVSpeechUtterance, success: Bool) {
        guard utterance === value else { return }
        let callback = completion
        cancel()
        if !success { error = "Ses tamamlanamadı. Yeniden dinle veya metni açarak devam et." }
        callback?(success)
    }
    func cancel() {
        let wasPlaying = playing
        generation = UUID(); player?.stop(); player = nil
        utterance = nil; completion = nil; preparation?.cancel(); watchdog?.cancel()
        synthesizer.stopSpeaking(at:.immediate); playing = false
        if wasPlaying {
            GameAudio.sessionQueue.async { try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation) }
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in if self?.utterance === utterance { self?.everStarted = true } }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finish(utterance,success:true) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finish(utterance,success:false) }
    }
}
