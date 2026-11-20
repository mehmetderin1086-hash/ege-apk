import AVFoundation
import Foundation

/// Bölüm sesindeki sessizlikler: okurken takipte kelimeler yalnızca konuşulan süreye dağıtılsın diye.
/// Ölçüm bir kez yapılır, ses dosyasının yanına önbelleklenir (dosya değişirse yeniden ölçülür).
nonisolated enum SpeechPauses {
    static let frameSeconds = 0.02
    static let minPauseSeconds = 0.14
    private static let version = 1

    private struct Cache: Codable {
        var version: Int
        var size: Int
        var modified: Double
        var pauses: [FollowAlong.Pause]
    }

    /// Önbellekten okur; yoksa ölçüp yazar. Ana iş parçacığını tutmaz.
    static func load(audioURL: URL) async -> [FollowAlong.Pause] {
        await Task.detached(priority: .utility) { cached(audioURL: audioURL) }.value
    }

    static func cached(audioURL: URL) -> [FollowAlong.Pause] {
        let cacheURL = audioURL.appendingPathExtension("pauses.json")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
              let size = (attributes[.size] as? NSNumber)?.intValue,
              let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 else { return [] }
        if let data = try? Data(contentsOf: cacheURL), let cache = try? JSONDecoder().decode(Cache.self, from: data),
           cache.version == version, cache.size == size, abs(cache.modified - modified) < 1 {
            return cache.pauses
        }
        guard let rms = try? frameLevels(audioURL: audioURL) else { return [] }
        let pauses = detect(rms: rms)
        if let data = try? JSONEncoder().encode(Cache(version: version, size: size, modified: modified, pauses: pauses)) {
            try? data.write(to: cacheURL, options: .atomic)
        }
        return pauses
    }

    /// 20 ms'lik karelerin RMS düzeyi (ilk kanal; dosya parça parça okunur, bellek sabit kalır).
    static func frameLevels(audioURL: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: audioURL)
        let format = file.processingFormat
        let frameLength = max(1, Int(format.sampleRate * frameSeconds))
        let chunk = AVAudioFrameCount(frameLength * 250)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return [] }
        var levels: [Float] = []
        levels.reserveCapacity(Int(Double(file.length) / Double(frameLength)) + 1)
        var sum: Float = 0
        var count = 0
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: chunk)
            guard buffer.frameLength > 0, let samples = buffer.floatChannelData?[0] else { break }
            for i in 0..<Int(buffer.frameLength) {
                sum += samples[i] * samples[i]
                count += 1
                if count == frameLength {
                    levels.append((sum / Float(count)).squareRoot())
                    sum = 0
                    count = 0
                }
            }
        }
        return levels
    }

    /// Sessiz koşular (≥ 0,14 sn). Eşik konuşma düzeyine (90. yüzdelik) göre görelidir, mutlak tabanlıdır
    /// (`SilenceAligner` ile aynı ölçüt; 120/32768 ≈ 16 bit sessizlik tabanı).
    static func detect(rms: [Float], frameSeconds: Double = frameSeconds) -> [FollowAlong.Pause] {
        guard rms.count > 2 else { return [] }
        let sorted = rms.sorted()
        let speechLevel = sorted[Int(Double(sorted.count - 1) * 0.9)]
        let threshold = max(speechLevel * 0.08, 120.0 / 32768.0)
        let minFrames = Int((minPauseSeconds / frameSeconds).rounded(.up))
        var pauses: [FollowAlong.Pause] = []
        var runStart: Int?
        for f in 0...rms.count {
            if f < rms.count, rms[f] < threshold {
                if runStart == nil { runStart = f }
            } else if let s = runStart {
                if f - s >= minFrames {
                    pauses.append(FollowAlong.Pause(start: Double(s) * frameSeconds, end: Double(f) * frameSeconds))
                }
                runStart = nil
            }
        }
        return pauses
    }
}
