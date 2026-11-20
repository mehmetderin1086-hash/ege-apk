import Foundation

/// #23/#25: soru sonrası düşünme payını haber veren yumuşak ton (≈ −30 dBFS RMS, 0,3 sn).
nonisolated enum ThinkTone {
    static let duration = 0.3
    static let levelDBFS = -30.0
    static let fileName = "think_tone.wav"

    static func clip(sampleRate: Int) -> PCMClip {
        let count = max(1, Int(duration * Double(sampleRate)))
        let rate = Double(sampleRate)
        var x = [Double](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / rate
            // 30 ms yükseliş, üstel sönüm, son 40 ms yumuşak kapanış: tık yok.
            let attack = min(1, t / 0.03)
            let release = min(1, (duration - t) / 0.04)
            let env = attack * release * exp(-4 * t / duration)
            x[i] = env * (sin(2 * .pi * 659.25 * t) + 0.35 * sin(2 * .pi * 987.77 * t))
        }
        let rms = (x.reduce(0) { $0 + $1 * $1 } / Double(count)).squareRoot()
        let gain = rms > 0 ? pow(10, levelDBFS / 20) / rms : 0
        return PCMClip(samples: x.map { Int16(max(-32767, min(32767, ($0 * gain * 32767).rounded()))) }, sampleRate: sampleRate)
    }

    /// 24 kHz mono WAV (Caches); yoksa üretilir.
    static func fileURL() -> URL {
        let url = URL.cachesDirectory.appending(path: fileName)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: URL.cachesDirectory, withIntermediateDirectories: true)
            try? WAV.encode(clip(sampleRate: 24_000)).write(to: url, options: .atomic)
        }
        return url
    }
}
