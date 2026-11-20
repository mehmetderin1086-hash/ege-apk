import Foundation

nonisolated struct SceneCheck: Sendable {
    var ok: Bool
    var reasons: [String]
    /// Tur başına ORİJİNAL kelime başlangıçları (sahne WAV'ının başına göre sn); yalnız ASR çalıştıysa.
    var wordTimes: [[Double]]?
}

/// #13: seslendirme kalite kapısı (iki aşama).
/// 1. Ucuz denetim: motor bazında süre/karakter oranı, sonda ani kesik, boş ses, uzun takılma.
/// 2. ASR yalnız `recognize: true` iken (çağıran yalnız ön planda ve `quality.asrCheck` açıkken verir); kapsama < 0,8 → kötü.
nonisolated enum SceneQualityGate {
    static let asrCheckKey = "quality.asrCheck"
    static var asrCheckEnabled: Bool { UserDefaults.standard.bool(forKey: asrCheckKey) }
    static let minCoverage = 0.8
    /// Bu kadar kısa metinde oran denetimi güvenilmez.
    static let minCharactersForRate = 40
    static let maxSilence = 3.0
    static let tailSeconds = 0.02
    static let tailRatio = 0.35

    /// Konuşulan metnin karakter başına saniyesi (boşluk dahil); dışı şüpheli.
    static func rateBounds(_ engine: SpeechEngine) -> ClosedRange<Double> {
        switch engine {
        // EMA-TTS kısa sözceyi uzun okur (ölçüm 17 Eki 2026: 30 harf ≈ 2 sn, 140 harf ≈ 8 sn).
        case .huggingface, .piper, .ema: 0.035...0.20
        case .apple, .supertonic: 0.03...0.18
        case .azure, .chirp, .claude, .edge: 0.035...0.16
        // XTTS Türkçeyi biraz daha yavaş okur; uzun duraklar olağandır.
        case .xtts: 0.04...0.20
        }
    }

    /// `language`: bölümün dili (ayarlardan). nil ise metinden tahmin edilir; tek sahnelik kısa metinde tahmin
    /// yanılabilir, çağıranın vermesi önerilir.
    @concurrent
    static func evaluate(wav: URL, turns: [ScriptTurn], engine: SpeechEngine, recognize: Bool,
                         language: PodcastLanguage? = nil) async -> SceneCheck {
        guard let data = try? Data(contentsOf: wav), let clip = try? WAV.parse(data) else {
            return SceneCheck(ok: false, reasons: ["Ses dosyası okunamadı."], wordTimes: nil)
        }
        let language = language ?? (WordSync.looksTurkish(turns.map(\.text).joined(separator: " ")) ? .tr : .en)
        let dictionary = Pronunciations.all
        let spoken = SpeakableText.prepare(turns, language: language, dictionary: dictionary)
        let characters = spoken.turns.reduce(0) { $0 + $1.text.count } + max(0, turns.count - 1)
        var reasons = cheapReasons(clip: clip, characters: characters, engine: engine)
        var wordTimes: [[Double]]?
        if recognize, reasons.isEmpty, language == .tr, SpeechAlignment.isAuthorized,
           case .ready(let asr) = await SpeechAlignment.modelState(),
           let words = try? await SpeechAlignment.recognize(wav, engine: asr) {
            let aligned = WordAligner.turnWordTimes(turns, language: language, dictionary: dictionary,
                                                    recognized: words, span: 0...clip.duration)
            let expected = spoken.turns.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
            reasons += asrReasons(coverage: aligned.coverage, expectedWords: expected, recognizedWords: WordAligner.expand(words).count)
            if reasons.isEmpty { wordTimes = aligned.times }
        }
        return SceneCheck(ok: reasons.isEmpty, reasons: reasons, wordTimes: wordTimes)
    }

    /// ASR sonucu: eksik kelime (kapsama) ve tekrar (fazla kelime).
    static func asrReasons(coverage: Double, expectedWords: Int, recognizedWords: Int) -> [String] {
        var reasons: [String] = []
        if coverage < minCoverage { reasons.append("Ses metinle uyuşmuyor (%\(Int((coverage * 100).rounded())) eşleşme).") }
        if expectedWords >= 10, Double(recognizedWords) > Double(expectedWords) * 1.35 { reasons.append("Seste tekrar eden bölüm var.") }
        return reasons
    }

    /// Ucuz denetim (ASR'siz).
    static func cheapReasons(clip: PCMClip, characters: Int, engine: SpeechEngine) -> [String] {
        let kept = AudioStitcher.trimmedRange(clip)
        guard clip.samples.contains(where: { abs(Int32($0)) > 200 }) else { return ["Ses boş."] }
        var reasons: [String] = []
        let seconds = Double(kept.count) / Double(clip.sampleRate)
        if characters >= minCharactersForRate {
            let ratio = seconds / Double(characters)
            let bounds = rateBounds(engine)
            if ratio < bounds.lowerBound { reasons.append("Ses metinden çok kısa; cümle atlanmış olabilir.") }
            if ratio > bounds.upperBound { reasons.append("Ses metinden çok uzun; tekrar ya da takılma olabilir.") }
        }
        if cutAtEnd(clip) { reasons.append("Ses sonda yarıda kesiliyor.") }
        if SilenceAligner.silenceRuns(clip: clip, minSeconds: maxSilence).contains(where: { $0.end - $0.start >= maxSilence }) {
            reasons.append("Seste uzun bir takılma var.")
        }
        return reasons
    }

    /// Son 20 ms konuşma düzeyine yakınsa ses doğal sönmeden kesilmiştir.
    static func cutAtEnd(_ clip: PCMClip) -> Bool {
        let frame = max(1, Int(Double(clip.sampleRate) * tailSeconds))
        guard clip.samples.count > frame * 10 else { return false }
        func rms(_ range: Range<Int>) -> Double {
            var sum = 0.0
            for i in range { let v = Double(clip.samples[i]); sum += v * v }
            return (sum / Double(range.count)).squareRoot()
        }
        var levels: [Double] = []
        var start = 0
        while start + frame <= clip.samples.count {
            levels.append(rms(start..<(start + frame)))
            start += frame
        }
        let speech = levels.sorted()[Int(Double(levels.count - 1) * 0.9)]
        guard speech > 200 else { return false }
        let tail = rms((clip.samples.count - frame)..<clip.samples.count)
        return tail > speech * tailRatio
    }
}
