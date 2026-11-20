import AVFoundation
import Foundation
import Observation
import Speech

/// Türkçe konuşma tanıma (Apple): kısmi sonuçlar, ses seviyesi ve sessizlikle "söz bitti" algılama.
@MainActor @Observable final class VoiceListener {
    enum State: Equatable { case idle, listening, denied }
    private(set) var state: State = .idle
    private(set) var transcript = ""
    private(set) var level: Float = 0
    var onFinal: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var detector = EndpointDetector(silence: 1.3)
    private var timer: Timer?

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        let mic = await AVAudioApplication.requestRecordPermission()
        if !(speech && mic) { state = .denied }
        return speech && mic
    }

    func start() throws {
        stop()
        guard let recognizer, recognizer.isAvailable else { throw TTSError.notConfigured("Konuşma tanıma") }
        VoicePlayer.configureSession(record: true)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = false }
        self.request = request; transcript = ""; detector.reset()
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let samples = buffer.floatChannelData?[0], count = Int(buffer.frameLength)
            guard let samples, count > 0 else { return }
            var sum: Float = 0
            for i in 0..<count { sum += samples[i] * samples[i] }
            let rms = min(1, sqrt(sum / Float(count)) * 8)
            Task { @MainActor [weak self] in self?.level = rms }
        }
        audioEngine.prepare()
        try audioEngine.start()
        state = .listening
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.state == .listening else { return }
                if let result { self.transcript = result.bestTranscription.formattedString }
                if error != nil, self.transcript.isEmpty { self.stop() }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .listening else { return }
                if self.detector.update(text: self.transcript, now: .now) {
                    let text = self.transcript
                    self.stop()
                    self.onFinal?(text)
                }
            }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if audioEngine.isRunning { audioEngine.stop(); audioEngine.inputNode.removeTap(onBus: 0) }
        request?.endAudio(); task?.cancel(); request = nil; task = nil
        level = 0
        if state == .listening { state = .idle }
    }
}
