import Foundation

/// Tek bir sahne WAV'ı içinde tur sınırlarını bulur.
/// TTS zaman damgası döndürmediği için: karakter oranından beklenen sınır hesaplanır,
/// en yakın sessizlik boşluğuna oturtulur. Bulunamazsa tahmin kullanılır.
nonisolated enum SilenceAligner {
    static let frameSeconds = 0.02
    static let minSilenceSeconds = 0.14

    /// Her tur için (başlangıç, bitiş) saniyeleri, sahne başına göre.
    static func turnRanges(clip: PCMClip, characterCounts: [Int]) -> [(start: Double, end: Double)] {
        let duration = clip.duration
        guard characterCounts.count > 1, duration > 0 else {
            return characterCounts.isEmpty ? [] : [(0, duration)]
        }

        let totalChars = Double(max(characterCounts.reduce(0, +), 1))
        var expected: [Double] = []
        var cumulative = 0
        for count in characterCounts.dropLast() {
            cumulative += count
            expected.append(duration * Double(cumulative) / totalChars)
        }

        let gaps = silenceMidpoints(clip: clip)
        let window = max(1.2, duration * 0.25)
        var boundaries: [Double] = []
        var lowerBound = 0.0
        var available = gaps

        for (i, target) in expected.enumerated() {
            // Sonraki sınırlar için yer bırak: en az 0,3 sn konuşma.
            let remaining = Double(expected.count - i - 1)
            let upperBound = duration - 0.3 * (remaining + 1)
            let candidates = available.filter { $0 > lowerBound + 0.3 && $0 < upperBound && abs($0 - target) <= window }
            let chosen = candidates.min { abs($0 - target) < abs($1 - target) }
                ?? min(max(target, lowerBound + 0.3), max(upperBound, lowerBound + 0.3))
            boundaries.append(chosen)
            lowerBound = chosen
            available.removeAll { $0 <= chosen }
        }

        var ranges: [(Double, Double)] = []
        var start = 0.0
        for b in boundaries {
            ranges.append((start, b))
            start = b
        }
        ranges.append((start, duration))
        return ranges
    }

    /// Yeterince uzun sessiz bölgelerin orta noktaları (saniye).
    static func silenceMidpoints(clip: PCMClip) -> [Double] {
        silenceRuns(clip: clip, minSeconds: minSilenceSeconds).map { ($0.start + $0.end) / 2 }
    }

    /// İç sessiz bölgeler (baştaki ve sondaki sayılmaz), saniye. Eşik konuşma düzeyine göre görelidir.
    static func silenceRuns(clip: PCMClip, minSeconds: Double) -> [(start: Double, end: Double)] {
        let frameLength = max(1, Int(Double(clip.sampleRate) * frameSeconds))
        let frameCount = clip.samples.count / frameLength
        guard frameCount > 2 else { return [] }

        var rms = [Double](repeating: 0, count: frameCount)
        clip.samples.withUnsafeBufferPointer { samples in
            for f in 0..<frameCount {
                var sum = 0.0
                let base = f * frameLength
                for i in 0..<frameLength {
                    let s = Double(samples[base + i])
                    sum += s * s
                }
                rms[f] = (sum / Double(frameLength)).squareRoot()
            }
        }

        // Eşik: konuşma seviyesine (90. yüzdelik) göre göreli, mutlak tabanla.
        let sorted = rms.sorted()
        let speechLevel = sorted[Int(Double(sorted.count - 1) * 0.9)]
        let threshold = max(speechLevel * 0.08, 120)
        let minFrames = Int((minSeconds / frameSeconds).rounded(.up))

        var runs: [(start: Double, end: Double)] = []
        var runStart: Int?
        for f in 0...frameCount {
            let silent = f < frameCount && rms[f] < threshold
            if silent {
                if runStart == nil { runStart = f }
            } else if let s = runStart {
                if f - s >= minFrames, s > 0, f < frameCount {   // baştaki/sondaki sessizliği sayma
                    runs.append((Double(s) * frameSeconds, Double(f) * frameSeconds))
                }
                runStart = nil
            }
        }
        return runs
    }
}
