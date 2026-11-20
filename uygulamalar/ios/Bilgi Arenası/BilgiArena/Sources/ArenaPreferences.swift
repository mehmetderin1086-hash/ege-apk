import Foundation

/// Ayarlar sekmesindeki tercihler. Görünümler aynı anahtarları @AppStorage ile okur;
/// ses ve oyun motoru buradaki okuyucuları kullanır, böylece varsayılanlar tek yerde kalır.
enum ArenaPreferences {
    enum Key {
        static let haptics = "hapticsEnabled"
        static let speechRate = "speechRate"
        static let voiceAutoStart = "voiceAnswerAutoStart"
        static let voiceAutoStop = "voiceAnswerAutoStop"
        static let voiceSilence = "voiceAnswerSilence"
        static let voiceMaxSeconds = "voiceAnswerMaxSeconds"
        static let voiceAutoSubmit = "voiceAnswerAutoSubmit"
        static let liveReviewSeconds = "liveReviewSeconds"
        static let liveExplanation = "liveReadExplanation"
        static let liveEngine = "quizLiveEngine"
        static let all = [liveEngine,haptics,speechRate,voiceAutoStart,voiceAutoStop,voiceSilence,voiceMaxSeconds,voiceAutoSubmit,liveReviewSeconds,liveExplanation]
    }
    static let silenceChoices = [0.8,1.2,2.0]
    static let maxSecondsChoices = [8,12,20]
    static let reviewChoices = [0,2,3,5]
    static let rateChoices = [0.8,0.9,1.0,1.15]

    static func haptics(_ d: UserDefaults = .standard) -> Bool { d.object(forKey:Key.haptics) as? Bool ?? true }
    /// iPhone sesinin konuşma hızı çarpanı; tanınmayan değer 1'e döner.
    static func speechRate(_ d: UserDefaults = .standard) -> Double {
        let value = d.object(forKey:Key.speechRate) as? Double ?? 1
        return rateChoices.contains(value) ? value : 1
    }
    static func voiceAutoStart(_ d: UserDefaults = .standard) -> Bool { d.object(forKey:Key.voiceAutoStart) as? Bool ?? true }
    static func voiceAutoStop(_ d: UserDefaults = .standard) -> Bool { d.object(forKey:Key.voiceAutoStop) as? Bool ?? true }
    static func voiceAutoSubmit(_ d: UserDefaults = .standard) -> Bool { d.bool(forKey:Key.voiceAutoSubmit) }
    static func liveExplanation(_ d: UserDefaults = .standard) -> Bool { d.object(forKey:Key.liveExplanation) as? Bool ?? true }
    static func liveReviewSeconds(_ d: UserDefaults = .standard) -> Int {
        let value = d.object(forKey:Key.liveReviewSeconds) as? Int ?? 3
        return reviewChoices.contains(value) ? value : 3
    }
    static func endpoint(_ d: UserDefaults = .standard) -> VoiceEndpointDetector.Limits {
        let silence = d.object(forKey:Key.voiceSilence) as? Double ?? 1.2
        let maximum = d.object(forKey:Key.voiceMaxSeconds) as? Int ?? 12
        return .init(silence:silenceChoices.contains(silence) ? silence : 1.2,maximum:Double(maxSecondsChoices.contains(maximum) ? maximum : 12))
    }
    static func reset(_ d: UserDefaults = .standard) { Key.all.forEach(d.removeObject(forKey:)) }
}
