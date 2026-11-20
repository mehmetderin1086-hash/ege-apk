import Foundation

/// #15: sahne bazında yayın kalitesi. Sıra: 80 Hz yüksek geçiren → BS.1770 (K ağırlıklı, 400 ms kapılı) ölçüm
/// → −19 LUFS (mono) kazanç → basit tepe sınırlayıcı (örnek tepe ≤ −1,5 dBFS). Kompresör yok.
/// Bölüm boyunda tampon tutulmaz; her sahne kendi Float32 tamponunda işlenir.
nonisolated enum Mastering {
    static let targetLUFS = -19.0
    static let ceilingDBFS = -1.5
    static let highPassHz = 80.0
    /// Sessize yakın sahnede gürültüyü aşırı yükseltmemek için kazanç tavanı.
    static let maxGainDB = 24.0

    static var ceiling: Float { Float(pow(10, ceilingDBFS / 20)) }

    static func master(_ clip: PCMClip) -> PCMClip {
        guard !clip.samples.isEmpty else { return clip }
        var x = floats(clip)
        Biquad.highPass(hz: highPassHz, sampleRate: Double(clip.sampleRate)).process(&x)
        if let lufs = loudness(x, sampleRate: clip.sampleRate) {
            let gain = Float(pow(10, min(maxGainDB, targetLUFS - lufs) / 20))
            for i in x.indices { x[i] *= gain }
        }
        limit(&x, sampleRate: clip.sampleRate, ceiling: ceiling)
        return PCMClip(samples: int16(x), sampleRate: clip.sampleRate)
    }

    // MARK: Ölçüm

    static func loudness(_ clip: PCMClip) -> Double? { loudness(floats(clip), sampleRate: clip.sampleRate) }

    /// ITU-R BS.1770-4 bütünleşik ses yüksekliği (mono, LUFS). Sessizse nil.
    static func loudness(_ input: [Float], sampleRate: Int) -> Double? {
        guard !input.isEmpty, sampleRate > 0 else { return nil }
        var y = input
        let fs = Double(sampleRate)
        Biquad.kShelf(sampleRate: fs).process(&y)
        Biquad.kHighPass(sampleRate: fs).process(&y)
        var prefix = [Double](repeating: 0, count: y.count + 1)
        for i in y.indices { prefix[i + 1] = prefix[i] + Double(y[i]) * Double(y[i]) }
        let block = Int(0.4 * fs)
        let step = max(1, Int(0.1 * fs))
        var z: [Double] = []
        if y.count < block {
            z = [prefix[y.count] / Double(y.count)]
        } else {
            var start = 0
            while start + block <= y.count {
                z.append((prefix[start + block] - prefix[start]) / Double(block))
                start += step
            }
        }
        func lufs(_ ms: Double) -> Double { -0.691 + 10 * log10(ms) }
        let absolute = z.filter { $0 > 0 && lufs($0) > -70 }
        guard !absolute.isEmpty else { return nil }
        let relative = lufs(absolute.reduce(0, +) / Double(absolute.count)) - 10
        let gated = absolute.filter { lufs($0) > relative }
        guard !gated.isEmpty else { return nil }
        return lufs(gated.reduce(0, +) / Double(gated.count))
    }

    /// Örnek tepe (dBFS).
    static func samplePeakDBFS(_ clip: PCMClip) -> Double {
        let peak = clip.samples.reduce(Int32(0)) { max($0, abs(Int32($1))) }
        return peak == 0 ? -.infinity : 20 * log10(Double(peak) / 32768)
    }

    // MARK: Sınırlayıcı

    /// Ön görülü tepe sınırlayıcı: kazanç tepe örneğine 3 ms'de doğrusal iner, 60 ms'de geri döner.
    /// Kazanç hiçbir örnekte gereken değeri aşmadığı için çıkış tepesi `ceiling`'i geçmez.
    static func limit(_ x: inout [Float], sampleRate: Int, ceiling: Float) {
        let n = x.count
        guard n > 0 else { return }
        var need = [Float](repeating: 1, count: n)
        var over = false
        for i in 0..<n {
            let a = abs(x[i])
            if a > ceiling { need[i] = ceiling / a; over = true }
        }
        guard over else { return }
        let attack = Float(1) / Float(max(1, Int(0.003 * Double(sampleRate))))
        // Geriye doğru: tepeden önce kazancı yumuşakça indir.
        var env = need
        if n > 1 { for i in stride(from: n - 2, through: 0, by: -1) { env[i] = min(env[i], env[i + 1] + attack) } }
        // İleriye doğru: bırakma.
        let release = Float(1 - exp(-1 / (0.06 * Double(sampleRate))))
        var g = env[0]
        for i in 0..<n {
            g = min(env[i], g + (1 - g) * release)
            x[i] *= g
        }
    }

    // MARK: Dönüşüm

    static func floats(_ clip: PCMClip) -> [Float] { clip.samples.map { Float($0) / 32768 } }

    /// Sıfıra doğru yuvarlar: genlik büyümez, tepe sınırı korunur.
    static func int16(_ x: [Float]) -> [Int16] {
        x.map { Int16(max(-32768, min(32767, ($0 * 32768).rounded(.towardZero)))) }
    }
}

/// İkinci dereceden IIR süzgeç (doğrudan biçim I, Double durum).
nonisolated struct Biquad {
    var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double

    func process(_ x: inout [Float]) {
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in x.indices {
            let input = Double(x[i])
            let out = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = input
            y2 = y1; y1 = out
            x[i] = Float(out)
        }
    }

    /// RBJ yüksek geçiren (Butterworth, Q = 1/√2).
    static func highPass(hz: Double, sampleRate fs: Double, q: Double = 0.7071067811865476) -> Biquad {
        let w = 2 * Double.pi * hz / fs
        let alpha = sin(w) / (2 * q)
        let c = cos(w)
        let a0 = 1 + alpha
        return Biquad(b0: (1 + c) / 2 / a0, b1: -(1 + c) / a0, b2: (1 + c) / 2 / a0, a1: -2 * c / a0, a2: (1 - alpha) / a0)
    }

    /// BS.1770 K ağırlığı 1. aşama (yüksek raf); her örnekleme hızı için yeniden hesaplanır.
    static func kShelf(sampleRate fs: Double) -> Biquad {
        let f0 = 1681.974450955533, gain = 3.999843853973347, q = 0.7071752369554196
        let k = tan(Double.pi * f0 / fs)
        let vh = pow(10, gain / 20)
        let vb = pow(vh, 0.4996667741545416)
        let a0 = 1 + k / q + k * k
        return Biquad(b0: (vh + vb * k / q + k * k) / a0, b1: 2 * (k * k - vh) / a0, b2: (vh - vb * k / q + k * k) / a0,
                      a1: 2 * (k * k - 1) / a0, a2: (1 - k / q + k * k) / a0)
    }

    /// BS.1770 K ağırlığı 2. aşama (RLB yüksek geçiren).
    static func kHighPass(sampleRate fs: Double) -> Biquad {
        let f0 = 38.13547087602444, q = 0.5003270373238773
        let k = tan(Double.pi * f0 / fs)
        let d = 1 + k / q + k * k
        return Biquad(b0: 1, b1: -2, b2: 1, a1: 2 * (k * k - 1) / d, a2: (1 - k / q + k * k) / d)
    }
}
