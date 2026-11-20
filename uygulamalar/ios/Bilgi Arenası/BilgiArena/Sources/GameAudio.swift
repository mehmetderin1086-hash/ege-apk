import AVFoundation
import UIKit

/// Short, locally synthesized effects and Turkish announcements. No microphone or network.
@MainActor final class GameAudio {
    enum Event: CaseIterable { case start, correct, wrong, tick, timeout, stage, finish }
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var activation: Task<Void,Never>?
    static let sessionQueue = DispatchQueue(label:"bilgiarena.audio-session")
    private(set) var lastEffectStarted = false
    private var sounds: [Event: Data] = [:]
    init() { synthesizer.usesApplicationAudioSession = true }
    func play(_ event: Event, effects: Bool, speech: String?) {
        guard effects || speech != nil else { return }
        activation?.cancel(); lastEffectStarted = false
        activation = Task { [weak self] in
            let ready: Bool = await withCheckedContinuation { continuation in
                Self.sessionQueue.async {
                    do {
                        try AVAudioSession.sharedInstance().setCategory(.ambient,mode:.default)
                        try AVAudioSession.sharedInstance().setActive(true)
                        continuation.resume(returning:true)
                    } catch { continuation.resume(returning:false) }
                }
            }
            guard let self, ready, !Task.isCancelled else { return }
            self.render(event,effects:effects,speech:speech)
        }
    }
    private func render(_ event: Event, effects: Bool, speech: String?) {
        do {
            if effects {
                let data = sounds[event] ?? Self.wave(event)
                sounds[event] = data
                player = try AVAudioPlayer(data:data); player?.volume = 0.4; lastEffectStarted = player?.play() == true
            }
            if let speech, !UIAccessibility.isVoiceOverRunning {
                synthesizer.stopSpeaking(at:.immediate)
                let utterance = AVSpeechUtterance(string:speech)
                utterance.voice = AVSpeechSynthesisVoice(language:"tr-TR")
                utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate,AVSpeechUtteranceDefaultSpeechRate * Float(ArenaPreferences.speechRate()))
                utterance.preUtteranceDelay = effects ? 0.12 : 0
                synthesizer.speak(utterance)
            }
        } catch { stop() }
    }
    var isSpeaking: Bool { synthesizer.isSpeaking }
    func stop() { activation?.cancel(); player?.stop(); synthesizer.stopSpeaking(at:.immediate) }
    static func wave(_ event: Event) -> Data {
        let notes: [Double]
        switch event {
        case .start: notes = [440,660]
        case .correct: notes = [660,880]
        case .wrong: notes = [330,220]
        case .tick: notes = [880]
        case .timeout: notes = [440,330,220]
        case .stage: notes = [440,554,660]
        case .finish: notes = [523,659,784,1047]
        }
        let rate = 22050, count = event == .tick ? 900 : 2205
        var pcm = Data()
        for frequency in notes {
            for i in 0..<count {
                let envelope = min(1,Double(i)/100) * min(1,Double(count-i)/400)
                var value = Int16(sin(2 * .pi * frequency * Double(i)/Double(rate)) * envelope * 12000).littleEndian
                withUnsafeBytes(of:&value) { pcm.append(contentsOf:$0) }
            }
        }
        var data = Data("RIFF".utf8)
        func u32(_ number: Int) { var n = UInt32(number).littleEndian; withUnsafeBytes(of:&n) { data.append(contentsOf:$0) } }
        func u16(_ number: Int) { var n = UInt16(number).littleEndian; withUnsafeBytes(of:&n) { data.append(contentsOf:$0) } }
        u32(36+pcm.count); data.append(Data("WAVEfmt ".utf8)); u32(16); u16(1); u16(1)
        u32(rate); u32(rate*2); u16(2); u16(16); data.append(Data("data".utf8)); u32(pcm.count); data.append(pcm)
        return data
    }
}
