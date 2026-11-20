import AVFoundation

/// Sessizlik ölçümü (#12): ses dosyaları için `SpeechPauses`, yerel video dosyaları için video içindeki ses izi.
/// `AVAudioFile` mp4/mov kabını açamadığı için videolar `AVAssetReader` ile (16 kHz mono) okunur; sonuç `SpeechPauses` ile
/// aynı eşikle ve aynı biçimde dosyanın yanına önbelleklenir.
nonisolated enum PauseMeasurement {
    private static let version = 1
    private static let sampleRate = 16_000

    private struct Cache: Codable {
        var version: Int
        var size: Int
        var modified: Double
        var pauses: [FollowAlong.Pause]
    }

    static func isVideoContainer(_ url: URL) -> Bool {
        ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
    }

    /// Önbellekten okur; yoksa ölçüp yazar. Ana iş parçacığını tutmaz. Ölçülemezse boş.
    static func load(_ url: URL) async -> [FollowAlong.Pause] {
        guard isVideoContainer(url) else { return await SpeechPauses.load(audioURL: url) }
        return await Task.detached(priority: .utility) { await cachedVideo(url) }.value
    }

    static func cachedVideo(_ url: URL) async -> [FollowAlong.Pause] {
        let cacheURL = url.appendingPathExtension("pauses.json")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.intValue,
              let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 else { return [] }
        if let data = try? Data(contentsOf: cacheURL), let cache = try? JSONDecoder().decode(Cache.self, from: data),
           cache.version == version, cache.size == size, abs(cache.modified - modified) < 1 {
            return cache.pauses
        }
        guard let levels = try? await frameLevels(videoURL: url) else { return [] }
        let pauses = SpeechPauses.detect(rms: levels)
        if let data = try? JSONEncoder().encode(Cache(version: version, size: size, modified: modified, pauses: pauses)) {
            try? data.write(to: cacheURL, options: .atomic)
        }
        return pauses
    }

    /// Videonun ilk ses izinin 20 ms'lik karelerinin RMS düzeyi (akarak okunur, bellek sabit kalır). Ses izi yoksa boş.
    static func frameLevels(videoURL: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: videoURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return [] }
        return try readLevels(asset: asset, track: track)
    }

    /// `copyNextSampleBuffer` eşzamansız bağlamdan çağrılamaz: okuma ayrı, eşzamanlı bir işlevde.
    private static func readLevels(asset: AVURLAsset, track: AVAssetTrack) throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadUnknown) }

        let frameLength = Int(Double(sampleRate) * SpeechPauses.frameSeconds)
        var levels: [Float] = []
        var sum: Float = 0
        var count = 0
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            let sampleCount = length / MemoryLayout<Float>.size
            var samples = [Float](repeating: 0, count: sampleCount)
            let status = samples.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: sampleCount * MemoryLayout<Float>.size, destination: $0.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { continue }
            for value in samples {
                sum += value * value
                count += 1
                if count == frameLength {
                    levels.append((sum / Float(count)).squareRoot())
                    sum = 0
                    count = 0
                }
            }
        }
        if reader.status == .failed { throw reader.error ?? CocoaError(.fileReadUnknown) }
        return levels
    }
}
