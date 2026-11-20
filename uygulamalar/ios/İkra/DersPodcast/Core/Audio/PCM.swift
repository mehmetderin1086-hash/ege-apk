import Foundation

/// 16-bit LE mono PCM. Sunucu sesleri (XTTS) 24 kHz üretir.
nonisolated struct PCMClip: Sendable {
    var samples: [Int16]
    var sampleRate: Int

    var duration: Double { Double(samples.count) / Double(sampleRate) }

    static func silence(seconds: Double, sampleRate: Int) -> PCMClip {
        PCMClip(samples: Array(repeating: 0, count: Int(seconds * Double(sampleRate))), sampleRate: sampleRate)
    }
}

nonisolated enum WAV {
    enum ParseError: Error { case notWAV, unsupportedFormat, missingData }

    /// RIFF WAV'dan 16-bit PCM mono örnekleri okur. Stereo gelirse sol kanalı alır.
    static func parse(_ data: Data) throws -> PCMClip {
        guard data.count >= 12,
              String(decoding: data[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: data[8..<12], as: UTF8.self) == "WAVE" else { throw ParseError.notWAV }

        var offset = 12
        var sampleRate = 24000
        var channels = 1
        var bits = 16
        var pcmRange: Range<Int>?

        while offset + 8 <= data.count {
            let id = String(decoding: data[offset..<offset + 4], as: UTF8.self)
            let size = Int(data.readUInt32LE(at: offset + 4))
            let body = offset + 8
            switch id {
            case "fmt ":
                guard body + 16 <= data.count else { throw ParseError.unsupportedFormat }
                let format = data.readUInt16LE(at: body)
                channels = Int(data.readUInt16LE(at: body + 2))
                sampleRate = Int(data.readUInt32LE(at: body + 4))
                bits = Int(data.readUInt16LE(at: body + 14))
                guard format == 1 || format == 0xFFFE, bits == 16, channels >= 1 else { throw ParseError.unsupportedFormat }
            case "data":
                // Akışla üretilmiş WAV'larda boyut alanı 0 veya 0xFFFFFFFF olabilir.
                let end = (size == 0 || body + size > data.count) ? data.count : body + size
                pcmRange = body..<end
            default:
                break
            }
            if pcmRange != nil { break }
            offset = body + size + (size & 1)
        }

        guard let range = pcmRange else { throw ParseError.missingData }
        let frameBytes = 2 * channels
        let frames = range.count / frameBytes
        var samples = [Int16](repeating: 0, count: frames)
        data.withUnsafeBytes { raw in
            let base = raw.baseAddress!.advanced(by: range.lowerBound)
            for i in 0..<frames {
                var value: Int16 = 0
                memcpy(&value, base.advanced(by: i * frameBytes), 2)
                samples[i] = Int16(littleEndian: value)
            }
        }
        return PCMClip(samples: samples, sampleRate: sampleRate)
    }

    static func encode(_ clip: PCMClip) -> Data {
        let dataSize = clip.samples.count * 2
        var out = Data(capacity: 44 + dataSize)
        out.append(contentsOf: Array("RIFF".utf8))
        out.appendLE(UInt32(36 + dataSize))
        out.append(contentsOf: Array("WAVEfmt ".utf8))
        out.appendLE(UInt32(16))
        out.appendLE(UInt16(1))
        out.appendLE(UInt16(1))
        out.appendLE(UInt32(clip.sampleRate))
        out.appendLE(UInt32(clip.sampleRate * 2))
        out.appendLE(UInt16(2))
        out.appendLE(UInt16(16))
        out.append(contentsOf: Array("data".utf8))
        out.appendLE(UInt32(dataSize))
        clip.samples.withUnsafeBufferPointer { buffer in
            buffer.withMemoryRebound(to: UInt8.self) { out.append($0) }
        }
        return out
    }
}

nonisolated extension Data {
    func readUInt16LE(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[startIndex + offset + $1]) << (8 * $1) }
    }

    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}


// MARK: - Apple cihaz içi seslendirme
import AVFoundation
import UIKit

/// Cihazdaki konuşma sesleri. `speechVoices()` sistem servisine gider ve pahalıdır; Ayarlar ve Yeni Podcast her
/// çizimde soruyordu. Liste bir kez okunup dile göre gruplanır; ses indirilince ya da uygulama öne gelince
/// (kullanıcı iPhone Ayarlar'dan ses indirip döndü) bir sonraki soruda tazelenir.
@MainActor
enum SpeechVoiceCatalog {
    /// Testlerde sayaçlı kaynakla değiştirilir.
    static var loader: () -> [AVSpeechSynthesisVoice] = { AVSpeechSynthesisVoice.speechVoices() }
    private static var byLanguage: [String: [AVSpeechSynthesisVoice]]?
    private static var ranked: [String: [AVSpeechSynthesisVoice]] = [:]
    private static var observing = false

    /// Dilin sesleri, sistemin verdiği sırayla.
    static func voices(language: String) -> [AVSpeechSynthesisVoice] {
        observeChanges()
        if let byLanguage { return byLanguage[language] ?? [] }
        let grouped = Dictionary(grouping: loader(), by: \.language)
        byLanguage = grouped
        return grouped[language] ?? []
    }

    /// Kaliteye göre dizilmiş sesler (yüksekten düşüğe; eşitlikte kimlik sırası).
    static func rankedVoices(language: String) -> [AVSpeechSynthesisVoice] {
        if let cached = ranked[language] { return cached }
        let sorted = voices(language: language)
            .sorted { $0.quality.rawValue == $1.quality.rawValue ? $0.identifier < $1.identifier : $0.quality.rawValue > $1.quality.rawValue }
        ranked[language] = sorted
        return sorted
    }

    static func invalidate() {
        byLanguage = nil
        ranked = [:]
    }

    private static func observeChanges() {
        guard !observing else { return }
        observing = true
        for name in [AVSpeechSynthesizer.availableVoicesDidChangeNotification, UIApplication.willEnterForegroundNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { invalidate() }
            }
        }
    }
}

/// Callback buffer'larının ömrü bitmeden kopyalar; AVSpeech callback'i ana kuyruğa bağlı değildir.
nonisolated private final class SpeechSamples: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var rate: Double = 0
    private var invalid = false

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        if rate == 0 { rate = buffer.format.sampleRate }
        guard rate == buffer.format.sampleRate, buffer.format.channelCount == 1 else { invalid = true; return }
        let count = Int(buffer.frameLength)
        if let floats = buffer.floatChannelData {
            samples.append(contentsOf: UnsafeBufferPointer(start: floats[0], count: count))
        } else if let ints = buffer.int16ChannelData {
            samples.append(contentsOf: UnsafeBufferPointer(start: ints[0], count: count).map { Float($0) / 32768 })
        } else { invalid = true }
    }

    func clip() throws -> PCMClip {
        lock.lock(); defer { lock.unlock() }
        guard !invalid, rate > 0, !samples.isEmpty else { throw DeviceSpeech.Failure.noAudio }
        // Kaynağın bant genişliğini azaltmadan, yüksek kaliteli dönüştürücü ile ortak biçim.
        let native = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
        guard let input = AVAudioPCMBuffer(pcmFormat: native, frameCapacity: AVAudioFrameCount(samples.count)),
              let converter = AVAudioConverter(from: native, to: target) else { throw DeviceSpeech.Failure.noAudio }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        converter.primeMethod = .none
        let capacity = AVAudioFrameCount(ceil(Double(samples.count) * 48_000 / rate) + 256)
        guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { throw DeviceSpeech.Failure.noAudio }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, state in
            if consumed { state.pointee = .endOfStream; return nil }
            consumed = true
            state.pointee = .haveData
            return input
        }
        guard status != .error, error == nil else { throw error ?? DeviceSpeech.Failure.noAudio as NSError }
        let output = UnsafeBufferPointer(start: converted.floatChannelData![0], count: Int(converted.frameLength)).map {
            Int16(max(-32768, min(32767, $0 * 32767)))
        }

        guard output.contains(where: { $0 != 0 }) else { throw DeviceSpeech.Failure.noAudio }
        return PCMClip(samples: output, sampleRate: 48_000)
    }
}

@MainActor
final class DeviceSpeech {
    nonisolated enum Failure: LocalizedError {
        case missingVoice, missingMaleVoice, missingFemaleVoice, noAudio, timeout
        var errorDescription: String? {
            switch self {
            case .missingVoice: "Cihazda bu dil için ses bulunamadı. iPhone Ayarlar > Erişilebilirlik bölümünden Türkçe konuşma sesi indirin."
            case .missingMaleVoice: "Bu dilde uygulamanın kullanabildiği erkek sesi bulunamadı. İki ayrı ses için iPhone’a uygun bir erkek konuşma sesi indirin. Senaryo korunuyor."
            case .missingFemaleVoice: "Bu dilde uygulamanın kullanabildiği kadın sesi bulunamadı. iPhone’a uygun bir kadın konuşma sesi indirin. Senaryo korunuyor."
            case .noAudio: "iPhone ses üretemedi. İndirilen konuşma sesini kontrol edip yeniden deneyin."
            case .timeout: "Cihaz seslendirmesi yanıt vermedi. Hazır sahneler korundu; yeniden deneyebilirsiniz."
            }
        }
    }
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<PCMClip, Error>?
    private var timeout: Task<Void, Never>?

    static func scene(turns: [ScriptTurn], settings: PodcastSettings) async throws -> PCMClip {
        for speaker in Set(turns.map(\.speaker)) {
            _ = try selectedVoice(speaker: speaker, language: settings.language, swapped: swapsGenders(settings))
        }
        let engine = DeviceSpeech()
        var result = PCMClip(samples: [], sampleRate: 48_000)
        for turn in turns {
            try Task.checkCancellation()
            guard !turn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let clip = try await engine.speak(turn.text, speaker: turn.speaker, settings: settings)
            result.samples += clip.samples
            result.samples += PCMClip.silence(seconds: 0.22, sampleRate: 48_000).samples
        }
        guard !result.samples.isEmpty else { throw Failure.noAudio }
        return result
    }

    static func voices(language: String = "tr-TR") -> [AVSpeechSynthesisVoice] {
        SpeechVoiceCatalog.rankedVoices(language: language)
    }

    /// `swapped`: A erkek, B kadın (Ayarlar'da birincil Apple sesi "Erkek" seçilmişse; bkz. `swapsGenders`).
    static func selectedVoice(speaker: Speaker, language: PodcastLanguage, swapped: Bool = false) throws -> AVSpeechSynthesisVoice {
        let available = voices(language: language == .tr ? "tr-TR" : "en-US")
        let gender: AVSpeechSynthesisVoiceGender = (speaker == .a) != swapped ? .female : .male
        guard let voice = available.first(where: { $0.gender == gender }) else {
            throw gender == .female ? Failure.missingFemaleVoice : Failure.missingMaleVoice
        }
        return voice
    }

    /// Apple motorunda konuşmacı A'nın sesi erkek seçilmişse ("apple:M") A erkek, B kadın konuşur.
    nonisolated static func swapsGenders(_ settings: PodcastSettings) -> Bool { settings.engine == .apple && settings.localVoiceA == "M" }

    static func qualityDescription(speaker: Speaker, language: PodcastLanguage = .tr) -> String {
        guard let voice = try? selectedVoice(speaker: speaker, language: language) else { return "Uygun ses bulunamadı" }
        let quality = voice.quality == .premium ? "Premium" : voice.quality == .enhanced ? "Geliştirilmiş" : "Standart"
        return "\(voice.name) · \(quality)"
    }

    private func speak(_ text: String, speaker: Speaker, settings: PodcastSettings) async throws -> PCMClip {
        try Task.checkCancellation()
        let voice = try Self.selectedVoice(speaker: speaker, language: settings.language, swapped: Self.swapsGenders(settings))
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = settings.pace == .yavas ? 0.43 : settings.pace == .hizli ? 0.55 : 0.49
        utterance.pitchMultiplier = 1 // HD için sesin doğal perdesini koru.
        let collected = SpeechSamples()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(180)) } catch { return }
                    self?.finish(.failure(Failure.timeout))
                }
                synthesizer.write(utterance) { [weak self] buffer in
                    guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                    if pcm.frameLength == 0 {
                        let result = Result { try collected.clip() }
                        Task { @MainActor [weak self] in self?.finish(result) }
                    } else { collected.append(pcm) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ result: Result<PCMClip, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        if case .failure = result { synthesizer.stopSpeaking(at: .immediate) }
        continuation.resume(with: result)
    }
}
