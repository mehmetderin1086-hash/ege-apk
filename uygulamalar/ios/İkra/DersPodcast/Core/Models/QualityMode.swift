import Foundation
import SwiftData

/// "Maksimum kalite" modu: en iyi dinleme ve öğrenme ayarları + bölüm hazır olunca çalışma malzemesinin otomatik hazırlanması.
nonisolated enum QualityMode {
    static let key = "maxQuality"
    static let autoStudyKey = "autoStudyPack"

    /// Varsayılan açık.
    static var isMax: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    /// AAC bit hızı. TTS sesi 24 kHz mono: bu hızda 64 kbps konuşma için kayıpsıza yakın ve kodlayıcının desteklediği üst sınıra yakın
    /// (96 kbps'i reddediyor; testler yakaladı). 44,1 kHz+ kaynaklarda 128 kbps.
    static func bitrate(sampleRate: Double) -> Int { sampleRate >= 44_100 ? 128_000 : 64_000 }

    /// Podcast ayarlarını en yüksek öğrenme ve dinleme kalitesine çeker (kullanıcı ekranda yine değiştirebilir).
    static func apply(to settings: PodcastSettings) -> PodcastSettings {
        var s = settings
        s.depth = .derin
        s.pace = .normal
        s.extras.examples = true
        s.extras.analogies = true
        s.extras.examTips = true
        s.extras.commonMistakes = true
        s.extras.recapQuestions = true
        // Keep the user's selected voice engine, including downloaded iPhone voices.
        // Learning quality must not silently switch a free engine to a server API.
        return s
    }

    /// Modu açar/kapatır; açarken ilgili tüm özellikleri etkinleştirir.
    static func set(_ on: Bool) {
        let d = UserDefaults.standard
        d.set(on, forKey: key)
        guard on else { return }
        for flag in [SoundDesign.key, "autoVerify", "showSlides", "inlineQuiz", "narrateFigures", "weeklyRecap.auto", autoStudyKey] {
            d.set(true, forKey: flag)
        }
    }

    static var autoStudy: Bool { UserDefaults.standard.object(forKey: autoStudyKey) as? Bool ?? isMax }
}
