import AVFoundation

/// İsteğe bağlı: sessiz ses çalarak uygulamayı arka planda uyanık tutar, böylece vekil
/// sunucusu ekran kilitliyken de Mac'ten / öbür uygulamalardan gelen istekleri karşılar.
/// Pil tüketir; varsayılan kapalı.
@MainActor
final class KeepAlive {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?

    func start() {
        guard engine == nil else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let e = AVAudioEngine()
            let p = AVAudioPlayerNode()
            e.attach(p)
            let format = e.mainMixerNode.outputFormat(forBus: 0)
            e.connect(p, to: e.mainMixerNode, format: format)
            e.mainMixerNode.outputVolume = 0
            guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate)) else { return }
            buf.frameLength = buf.frameCapacity      // sıfırlarla dolu = sessizlik
            try e.start()
            p.scheduleBuffer(buf, at: nil, options: .loops)
            p.play()
            engine = e; player = p
        } catch {
            engine = nil; player = nil
        }
    }

    func stop() {
        player?.stop()
        engine?.stop()
        engine = nil; player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
