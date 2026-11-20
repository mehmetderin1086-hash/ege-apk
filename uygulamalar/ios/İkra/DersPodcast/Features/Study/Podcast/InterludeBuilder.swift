import AVFoundation
import Foundation

/// #25: konu sonu sesli yoklaması için hazır dosya (soru + şıklar → ton + düşünme payı → cevap).
nonisolated struct PreparedInterlude: Sendable, Equatable {
    var episodeID: UUID
    var chapter: Int
    var item: QuizItem
    var url: URL
    /// Cevabın başladığı an (sn): kulaklıkta "sonraki" = "bilemedim" buraya atlar.
    var answerStart: Double
    var duration: Double
}

/// Ara sesi konu başında tek dosya olarak hazırlar. `SpeechOut.speak` kullanılmaz (podcast'i askıya alıyor);
/// metin `AVSpeechSynthesizer.write` ile örneklere dökülür, sessizlik gerçek örneklerdir (Task.sleep yok).
enum InterludeBuilder {
    /// Okunacak iki metin: soru (+ şıklar) ve cevap.
    nonisolated static func script(for item: QuizItem, english: Bool) -> (question: String, answer: String) {
        var question = english ? "Quick check. " : "Konu sonu sorusu. "
        question += item.question.trimmingCharacters(in: .whitespacesAndNewlines)
        if QuestionKind.of(item) == "truefalse" {
            question += english ? " True or false?" : " Doğru mu, yanlış mı?"
        } else if !QuestionKind.isOpen(item) {
            for (i, option) in item.options.enumerated() {
                question += " \(QuestionKind.letter(i)): \(option.trimmingCharacters(in: .whitespacesAndNewlines))."
            }
        }
        var answer = english ? "Answer: " : "Cevap: "
        if QuestionKind.isOpen(item) || QuestionKind.of(item) == "truefalse" {
            answer += QuestionKind.expectedAnswer(item)
        } else {
            answer += "\(QuestionKind.letter(item.answerIndex)), \(QuestionKind.expectedAnswer(item))"
        }
        let explanation = item.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explanation.isEmpty { answer += ". " + String(explanation.prefix(300)) }
        return (question, answer)
    }

    static func directory() -> URL {
        let dir = URL.cachesDirectory.appending(path: "Interludes", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func fileURL(episodeID: UUID, chapter: Int) -> URL {
        directory().appending(path: "\(episodeID.uuidString)_\(chapter).wav")
    }

    /// Bir bölümün ya da hepsinin ara seslerini siler.
    static func purge(except episodeID: UUID? = nil) {
        let dir = directory()
        for url in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
            if let episodeID, url.lastPathComponent.hasPrefix(episodeID.uuidString) { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func remove(episodeID: UUID) {
        let dir = directory()
        for url in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        where url.lastPathComponent.hasPrefix(episodeID.uuidString) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func build(item: QuizItem, episodeID: UUID, chapter: Int, language: String, thinkSeconds: Double) async -> PreparedInterlude? {
        let parts = script(for: item, english: language.hasPrefix("en"))
        guard let question = await SpeechSynth.render(parts.question, language: language),
              let answer = await SpeechSynth.render(parts.answer, language: language) else { return nil }
        let url = fileURL(episodeID: episodeID, chapter: chapter)
        guard let layout = await assemble(question: question, answer: answer, think: ThinkTiming.clamp(thinkSeconds), to: url) else { return nil }
        return PreparedInterlude(episodeID: episodeID, chapter: chapter, item: item, url: url,
                                 answerStart: layout.answerStart, duration: layout.duration)
    }

    /// Soru → 0,4 sn → ton → düşünme payı → cevap → 0,3 sn; tek WAV.
    @concurrent
    nonisolated static func assemble(question: PCMClip, answer: PCMClip, think: Double, to url: URL) async -> (answerStart: Double, duration: Double)? {
        let rate = question.sampleRate
        let tone = ThinkTone.clip(sampleRate: rate)
        let answerSamples = answer.sampleRate == rate ? answer.samples : resample(answer, to: rate).samples
        var samples = question.samples
        samples += PCMClip.silence(seconds: 0.4, sampleRate: rate).samples
        samples += tone.sampleRate == rate ? tone.samples : resample(tone, to: rate).samples
        samples += PCMClip.silence(seconds: max(0.5, think - tone.duration), sampleRate: rate).samples
        let answerStart = Double(samples.count) / Double(rate)
        samples += answerSamples
        samples += PCMClip.silence(seconds: 0.3, sampleRate: rate).samples
        let clip = PCMClip(samples: samples, sampleRate: rate)
        do {
            try WAV.encode(clip).write(to: url, options: .atomic)
            return (answerStart, clip.duration)
        } catch {
            return nil
        }
    }

    /// Doğrusal örnekleme dönüşümü (konuşma için yeterli).
    nonisolated static func resample(_ clip: PCMClip, to rate: Int) -> PCMClip {
        guard clip.sampleRate != rate, clip.sampleRate > 0, !clip.samples.isEmpty else { return PCMClip(samples: clip.samples, sampleRate: rate) }
        let ratio = Double(clip.sampleRate) / Double(rate)
        let count = Int(Double(clip.samples.count) / ratio)
        var out = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            let pos = Double(i) * ratio
            let j = Int(pos)
            let frac = pos - Double(j)
            let a = Double(clip.samples[min(j, clip.samples.count - 1)])
            let b = Double(clip.samples[min(j + 1, clip.samples.count - 1)])
            out[i] = Int16(max(-32768, min(32767, a + (b - a) * frac)))
        }
        return PCMClip(samples: out, sampleRate: rate)
    }
}

/// `AVSpeechSynthesizer.write` → mono 16-bit örnekler.
enum SpeechSynth {
    static func render(_ text: String, language: String, timeout: Double = 30) async -> PCMClip? {
        let collector = SynthCollector()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = SpeechOut.bestVoice(for: language)
        utterance.rate = 0.5
        return await collector.run(utterance, timeout: timeout)
    }
}

/// Sentezleyiciyi iş bitene dek tutar; geri çağrılar sentezleyicinin kuyruğunda gelir.
nonisolated final class SynthCollector: @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private let lock = NSLock()
    private var samples: [Int16] = []
    private var rate = 0
    private var continuation: CheckedContinuation<PCMClip?, Never>?

    func run(_ utterance: AVSpeechUtterance, timeout: Double) async -> PCMClip? {
        await withCheckedContinuation { (c: CheckedContinuation<PCMClip?, Never>) in
            lock.withLock { continuation = c }
            synthesizer.write(utterance) { [self] buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else { finish(); return }
                append(pcm)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in finish() }
        }
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        let n = Int(buffer.frameLength)
        var chunk = [Int16](repeating: 0, count: n)
        if let data = buffer.int16ChannelData?[0] {
            for i in 0..<n { chunk[i] = data[i] }
        } else if let data = buffer.floatChannelData?[0] {
            for i in 0..<n { chunk[i] = Int16(max(-1, min(1, data[i])) * 32767) }
        } else {
            return
        }
        lock.withLock {
            if rate == 0 { rate = Int(buffer.format.sampleRate) }
            samples += chunk
        }
    }

    private func finish() {
        let (c, clip): (CheckedContinuation<PCMClip?, Never>?, PCMClip?) = lock.withLock {
            defer { continuation = nil }
            return (continuation, samples.isEmpty || rate == 0 ? nil : PCMClip(samples: samples, sampleRate: rate))
        }
        c?.resume(returning: clip)
    }
}

// MARK: - Ara ses durum makinesi

/// Oynatıcının ara ses API'si (P5). Testte sahte oynatıcı kullanılır.
protocol InterludeHost: AnyObject {
    func beginInterlude() -> Bool
    func endInterlude(resume: Bool)
    var interludeRemoteHandler: ((RemoteCommand) -> Bool)? { get set }
}

extension PlayerController: InterludeHost {}

/// Ara sesin çalınması (gerçekte AVAudioPlayer, podcast'in .playback/.spokenAudio oturumunda).
protocol InterludeAudio: AnyObject {
    /// `onFinish`: ses bitti ya da kesintiden sonra sürdürülemedi (bir kez).
    func play(url: URL, onFinish: @escaping () -> Void) -> Bool
    func seek(to time: Double)
    func stop()
    /// Kesintiyle (arama, başka uygulama) duraklama anı; `resume` bekliyor. Duraklamamışsa nil.
    var suspendedAt: Date? { get }
    /// Duraklamış sesi sürdürür; olmazsa false.
    func resume() -> Bool
    /// Ne çalıyor ne bekliyor (bitiş haberi kaybolmuş): bekçi bunu yakalar.
    var isIdle: Bool { get }
}

/// idle → playing → finished. Pencere içinde kulaklıkta "sonraki" = "bilemedim" (cevaba atlanır),
/// "önceki" soruyu yeniden okur, duraklat ara sesi bitirip podcast'i durdurur.
/// "Oynat": kesintiyle duraklamış ara ses sürer; çalarken basılırsa ara ses biter, podcast sürer (takılı kalmaz).
final class InterludeSession {
    enum State: Equatable { case idle, playing, finished(dontKnow: Bool), failed }

    let prepared: PreparedInterlude
    private(set) var state: State = .idle
    private(set) var dontKnow = false
    private weak var host: InterludeHost?
    private let audio: InterludeAudio
    /// "Bilemedim" anında (bir kez).
    var onDontKnow: ((PreparedInterlude) -> Void)?
    /// Bitince: (hazır ses, bilemedim mi, podcast sürüyor mu).
    var onFinish: ((PreparedInterlude, Bool, Bool) -> Void)?

    init(prepared: PreparedInterlude, host: InterludeHost, audio: InterludeAudio) {
        self.prepared = prepared
        self.host = host
        self.audio = audio
    }

    @discardableResult
    func start() -> Bool {
        guard state == .idle, let host else { return false }
        guard host.beginInterlude() else { state = .failed; return false }
        host.interludeRemoteHandler = { [weak self] command in self?.handle(command) ?? false }
        let started = audio.play(url: prepared.url) { [weak self] in self?.complete(resume: true) }
        guard started else {
            host.interludeRemoteHandler = nil
            host.endInterlude(resume: true)
            state = .failed
            return false
        }
        state = .playing
        return true
    }

    /// true = komut tüketildi.
    func handle(_ command: RemoteCommand) -> Bool {
        guard state == .playing else { return false }
        switch command {
        case .nextChapter:
            markDontKnow()
        case .skip(let seconds) where seconds > 0:
            markDontKnow()
        case .previousChapter:
            audio.seek(to: 0)
        case .skip:
            audio.seek(to: 0)
        case .pause, .toggle:
            complete(resume: false)
        case .play:
            // Kesintiden sonra sürdür; çalarken (ya da sürdürülemezse) ara ses biter, podcast sürer.
            if audio.suspendedAt == nil || !audio.resume() { complete(resume: true) }
        case .seek:
            break
        }
        return true
    }

    private func markDontKnow() {
        guard !dontKnow else { return }
        dontKnow = true
        onDontKnow?(prepared)
        audio.seek(to: prepared.answerStart)
    }

    /// Ses bitti ya da kullanıcı durdurdu.
    func complete(resume: Bool) {
        guard state == .playing else { return }
        audio.stop()
        host?.interludeRemoteHandler = nil
        host?.endInterlude(resume: resume)
        state = .finished(dontKnow: dontKnow)
        onFinish?(prepared, dontKnow, resume)
    }

    /// Oynatıcı ara sesi kendisi bıraktı (yeni bölüm, yeniden yükleme): ses susar, oynatıcıya dokunulmaz.
    func abandon() {
        guard state == .playing else { return }
        audio.stop()
        state = .finished(dontKnow: dontKnow)
        onFinish?(prepared, dontKnow, false)
    }

    /// Kesintide en fazla bu kadar beklenir (kesinti hiç bitmezse ya da sistem "sürdür" demezse).
    static let suspendLimit: TimeInterval = 180

    /// Bekçi: ses ne çalıyor ne bekliyorsa (bitiş haberi kaybolduysa) ara ses kapanır, podcast sürer;
    /// kesintide `suspendLimit`'ten uzun beklediyse ara ses kapanır, podcast duraklamış kalır.
    /// true = oturum hâlâ sürüyor.
    @discardableResult
    func watchdog(now: Date = .now) -> Bool {
        guard state == .playing else { return false }
        if audio.isIdle {
            complete(resume: true)
        } else if let at = audio.suspendedAt, now.timeIntervalSince(at) > Self.suspendLimit {
            complete(resume: false)
        }
        return state == .playing
    }
}

/// Gerçek ses: AVAudioPlayer (oturumu değiştirmez; podcast'in oturumu açık kalır).
/// Kesinti (arama, alarm, başka uygulama) dinlenir: sistem "sürdür" derse ses sürer, sürdürülemezse bitmiş sayılır;
/// "sürdür" demezse duraklamış bekler (kilit ekranındaki "Oynat" `resume` ile sürdürür; bekçi süreyi sınırlar).
final class AVInterludeAudio: NSObject, InterludeAudio, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var onFinish: (() -> Void)?
    private(set) var suspendedAt: Date?
    private var interruptionObserver: NSObjectProtocol?

    var isIdle: Bool {
        guard let player else { return true }
        return !player.isPlaying && suspendedAt == nil
    }

    func play(url: URL, onFinish: @escaping () -> Void) -> Bool {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return false }
        self.player = player
        self.onFinish = onFinish
        suspendedAt = nil
        player.delegate = self
        player.prepareToPlay()
        guard player.play() else {
            stop()
            return false
        }
        observeInterruptions()
        return true
    }

    func seek(to time: Double) {
        guard let player else { return }
        player.currentTime = max(0, time)
        if !player.isPlaying, player.play() { suspendedAt = nil }
    }

    func resume() -> Bool {
        guard let player else { return false }
        try? AVAudioSession.sharedInstance().setActive(true)
        guard player.play() else { return false }
        suspendedAt = nil
        return true
    }

    func stop() {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        player?.stop()
        player = nil
        onFinish = nil
        suspendedAt = nil
    }

    private func observeInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] note in
            let info = note.userInfo
            let type = (info?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = AVAudioSession.InterruptionOptions(rawValue: info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            MainActor.assumeIsolated { self?.interruption(type, shouldResume: options.contains(.shouldResume)) }
        }
    }

    private func interruption(_ type: AVAudioSession.InterruptionType?, shouldResume: Bool) {
        guard let player else { return }
        switch type {
        case .began:
            // Sistem sesi durdurdu (AVAudioPlayer bunu didFinish ile bildirmez).
            if suspendedAt == nil { suspendedAt = .now }
            if player.isPlaying { player.pause() }
        case .ended:
            guard suspendedAt != nil, shouldResume else { return }
            if !resume() { finished() }
        default:
            break
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let source = ObjectIdentifier(player)
        Task { @MainActor in self.finished(source) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let source = ObjectIdentifier(player)
        Task { @MainActor in self.finished(source) }
    }

    /// Yalnız şu anki oynatıcının bitişi sayılır (durdurulup yerine yenisi konan eskinin haberi yok sayılır).
    private func finished(_ source: ObjectIdentifier? = nil) {
        if let source, source != player.map(ObjectIdentifier.init) { return }
        let done = onFinish
        stop()
        done?()
    }
}
