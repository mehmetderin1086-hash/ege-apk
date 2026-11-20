import AVFoundation
import CryptoKit
@preconcurrency import CoreML
import Foundation
@preconcurrency import PiperRuntime
import SupertonicRuntime
import UIKit

enum LocalSpeech {
    nonisolated static func validate(_ settings: PodcastSettings, requireModel: Bool = true) throws {
        if settings.engine.turkishOnly, settings.language != .tr {
            throw OfflineSpeechError.message("Bu ses motoru Türkçe için ayarlı. İngilizce için Supertonic veya Apple seçin.")
        }
        if !settings.engine.supportsTwoHosts, settings.format.usesTwoHosts {
            throw OfflineSpeechError.message("\(settings.engine.title) tek seslidir. Tek anlatıcı biçimini seçin.")
        }
        if settings.engine == .supertonic {
            let voices = (1...5).map({ "F\($0)" }) + (1...5).map({ "M\($0)" })
            guard voices.contains(settings.localVoiceA), voices.contains(settings.localVoiceB) else {
                throw OfflineSpeechError.message("Supertonic kadın ve erkek seslerini yeniden seçin.")
            }
        }
        if requireModel, settings.engine.isNeuralOnDevice, !OfflineModelCatalog.ready(settings.engine) {
            throw OfflineSpeechError.message("Önce iPhone ses modelleri ekranından \(settings.engine.title) modelini indirin. Senaryo ve hazır sesler korunuyor.")
        }
    }

    static func scene(turns: [ScriptTurn], settings: PodcastSettings) async throws -> PCMClip {
        try validate(settings)
        if settings.engine == .apple { return try await DeviceSpeech.scene(turns: turns, settings: settings) }
        observeMemoryWarnings()
        return try await NeuralSpeechRenderer.shared.scene(turns: turns, settings: settings)
    }

    private static var observingMemory = false

    /// Bellek uyarısında boştaki ses modeli (yüzlerce MB) hemen bırakılır; süren seslendirmeye dokunulmaz.
    private static func observeMemoryWarnings() {
        guard !observingMemory else { return }
        observingMemory = true
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            Task { await NeuralSpeechRenderer.shared.unloadIfIdle() }
        }
    }

    nonisolated static func cacheKey(_ settings: PodcastSettings) -> String {
        let revision = (try? OfflineModelCatalog.manifest(settings.engine).revision) ?? "v1"
        let value = [revision, settings.engine.rawValue, settings.language.rawValue, settings.pace.rawValue,
                     settings.localVoiceA, settings.localVoiceB].joined(separator: "|")
        let hash = SHA256.hash(data: Data(value.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return settings.engine.rawValue + "_" + hash
    }

    /// Bounded chunks keep memory/cancellation latency independent of podcast
    /// length. Swift Characters preserve Turkish characters and grapheme clusters.
    nonisolated static func chunks(_ text: String, limit: Int = 180) -> [String] {
        let limit = max(1, limit)
        var result: [String] = []
        var current = ""
        for word in text.split(whereSeparator: \.isWhitespace).map(String.init) {
            var remaining = word
            if !current.isEmpty, current.count + 1 + remaining.count > limit {
                result.append(current); current = ""
            }
            while remaining.count > limit {
                result.append(String(remaining.prefix(limit)))
                remaining = String(remaining.dropFirst(limit))
            }
            if !remaining.isEmpty {
                current += (current.isEmpty ? "" : " ") + remaining
            }
            if let last = current.last, ".!?;".contains(last), current.count >= 50 {
                result.append(current); current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    nonisolated static func pcm(_ samples: [Float], sampleRate: Int) throws -> PCMClip {
        guard !samples.isEmpty, sampleRate > 0, samples.allSatisfy(\.isFinite),
              samples.contains(where: { abs($0) > 0.000_01 }) else { throw OfflineSpeechError.noAudio }
        let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false)!
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(samples.count)),
              let converter = AVAudioConverter(from: source, to: target) else { throw OfflineSpeechError.noAudio }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        converter.primeMethod = .none
        let capacity = AVAudioFrameCount(ceil(Double(samples.count) * 48_000 / Double(sampleRate)) + 256)
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { throw OfflineSpeechError.noAudio }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if consumed { state.pointee = .endOfStream; return nil }
            consumed = true; state.pointee = .haveData; return input
        }
        guard status != .error, error == nil, output.frameLength > 0 else { throw OfflineSpeechError.noAudio }
        let floats = UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength))
        let values = floats.map { Int16(max(-32768, min(32767, $0 * 32767))) }
        return PCMClip(samples: values, sampleRate: 48_000)
    }
}

/// One serialized inference lane for previews, new podcasts and scene edits.
/// Model loading/inference stays off the main actor; only one engine is resident.
/// Model, son sahneden sonra `idleSeconds` boş kalınca ya da bellek uyarısında bırakılır (Supertonic 172 MB, Piper
/// 63 MB; yoksa tek önizlemeden sonra uygulama kapanana kadar bellekte kalırdı). Sonraki sahnede yeniden yüklenir.
actor NeuralSpeechRenderer {
    static let shared = NeuralSpeechRenderer()
    private var supertonic: Supertonic3Manager?
    private var piper: PiperRuntime?
    private var ema: EmaTTS?
    private var emaVoice = "tr"
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    let idleSeconds: Double
    private var idleTask: Task<Void, Never>?
    #if DEBUG
    private var residentForTesting = false
    #endif

    init(idleSeconds: Double = 120) { self.idleSeconds = idleSeconds }

    /// Bellekte yüklü model var mı.
    var isResident: Bool {
        #if DEBUG
        if residentForTesting { return true }
        #endif
        return supertonic != nil || piper != nil || ema != nil
    }

    private func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }

    func unload() async {
        await acquire()
        defer { release() }
        await supertonic?.cleanup()
        supertonic = nil; piper = nil; ema = nil
        #if DEBUG
        residentForTesting = false
        #endif
    }

    /// Seslendirme sürmüyor ve sırada bekleyen yoksa modeli bırakır (boşta süre doldu ya da bellek uyarısı).
    func unloadIfIdle() async {
        guard !busy, waiters.isEmpty, isResident else { return }
        await unload()
    }

    /// Boşta sayacını (yeniden) başlatır; üretimde sahneler art arda geldiği için süre dolmaz. Sıra bir sonraki
    /// sahneye geçtiyse sayaç kurulmaz (o sahne bitince kurar).
    func scheduleIdleUnload() {
        idleTask?.cancel()
        idleTask = nil
        guard isResident, !busy else { return }
        let delay = idleSeconds
        idleTask = Task { [weak self] in
            guard (try? await Task.sleep(for: .seconds(delay))) != nil else { return }
            await self?.unloadIfIdle()
        }
    }

    func cancelIdleUnload() {
        idleTask?.cancel()
        idleTask = nil
    }

    #if DEBUG
    /// Testler: model dosyası olmadan "yüklü" durumu taklit eder.
    func markResidentForTesting() { residentForTesting = true }
    #endif

    /// EMA-TTS'in sesi: taban ("tr") ya da ince ayarlı "coskulu"; başka değer tabana düşer.
    private func emaVoiceID(_ settings: PodcastSettings) -> String { settings.localVoiceA == "coskulu" ? "coskulu" : "tr" }

    func scene(turns: [ScriptTurn], settings: PodcastSettings) async throws -> PCMClip {
        cancelIdleUnload()
        await acquire()
        defer { release(); scheduleIdleUnload() }
        try Task.checkCancellation()
        try LocalSpeech.validate(settings)
        guard settings.engine.isNeuralOnDevice else { throw OfflineSpeechError.message("Geçersiz cihaz ses motoru.") }
        let directory = OfflineModelCatalog.directory(settings.engine)
        if settings.engine == .supertonic, supertonic == nil {
            piper = nil; ema = nil
            #if targetEnvironment(simulator)
            let units: MLComputeUnits = .cpuOnly
            #else
            let units: MLComputeUnits = .cpuAndNeuralEngine
            #endif
            let manager = Supertonic3Manager(directory: OfflineModelCatalog.engineRoot(.supertonic),
                                             computeUnits: units, vectorEstimator: .aneBucketed(.int4))
            try await manager.initialize()
            supertonic = manager
        } else if settings.engine == .piper, piper == nil {
            await supertonic?.cleanup(); supertonic = nil; ema = nil
            do { piper = try PiperRuntime(directory: directory) }
            catch { throw OfflineSpeechError.message("Piper modeli açılamadı. Ses modelleri ekranından kaldırıp yeniden indirin.") }
        } else if settings.engine == .ema, ema == nil || emaVoice != emaVoiceID(settings) {
            await supertonic?.cleanup(); supertonic = nil; piper = nil
            let voice = emaVoiceID(settings)
            do { ema = try EmaTTS(directory: directory, voice: voice); emaVoice = voice }
            catch { throw OfflineSpeechError.message("EMA-TTS modeli açılamadı (\(error.localizedDescription)). Ses modelleri ekranından kaldırıp yeniden indirin.") }
        }
        let speed: Float = settings.pace == .yavas ? 0.88 : settings.pace == .hizli ? 1.15 : 1
        var result = PCMClip(samples: [], sampleRate: 48_000)
        for turn in turns {
            try Task.checkCancellation()
            let style: Supertonic3VoiceStyle? = settings.engine == .supertonic
                ? try Supertonic3VoiceStyle.load(from: directory.appending(path: "voice_styles/\(turn.speaker == .a ? settings.localVoiceA : settings.localVoiceB).json")) : nil
            // EMA-TTS kısa sözcede zayıf, uzun cümlede güçlüdür (model kartı): parçalar iki kat uzun tutulur.
            for chunk in LocalSpeech.chunks(turn.text, limit: settings.engine == .ema ? 360 : 180) {
                try Task.checkCancellation()
                let samples: [Float]
                let rate: Int
                if let manager = supertonic, let style, settings.engine == .supertonic {
                    let audio = try await manager.synthesize(text: chunk, language: settings.language.rawValue,
                                                             style: style, totalSteps: 8, speed: speed)
                    samples = audio.samples; rate = 44_100
                } else if let piper, settings.engine == .piper {
                    let audio = try piper.synthesize(chunk, speed: speed)
                    samples = audio.samples; rate = audio.sampleRate
                } else if let ema, settings.engine == .ema {
                    // Metin modelin kendi ön işlemesinden geçer (noktalama, küçük harf, baş öneki); sayılar TurkishReading'de açılmıştır.
                    let audio = try ema.synthesize(EmaText.prepare(chunk), speed: speed)
                    samples = audio.samples; rate = audio.sampleRate
                } else { throw OfflineSpeechError.noAudio }
                try Task.checkCancellation()
                result.samples += try LocalSpeech.pcm(samples, sampleRate: rate).samples
                result.samples += PCMClip.silence(seconds: 0.08, sampleRate: 48_000).samples
            }
            result.samples += PCMClip.silence(seconds: 0.18, sampleRate: 48_000).samples
        }
        guard result.samples.contains(where: { $0 != 0 }) else { throw OfflineSpeechError.noAudio }
        return result
    }
}
