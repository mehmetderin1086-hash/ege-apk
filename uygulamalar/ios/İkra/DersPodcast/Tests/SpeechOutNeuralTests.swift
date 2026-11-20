import Foundation
import Testing
@testable import Ikra

/// Asistan ve sesli okuma: Ayarlar › Ses'teki ses modeli inmiş bir iPhone motoruysa (EMA-TTS vb.) cihaz içi motor, değilse Apple.
@MainActor
struct SpeechOutNeuralTests {
    @Test func emaBecomesTheAppVoiceWhenDownloadedAndNothingWasChosen() {
        let d = UserDefaults(suiteName: "SpeechOutNeuralTests-primary-\(UUID())")!
        // Hiç seçim yok: EMA inmişse EMA, değilse eski davranış (Kore).
        #expect(AppVoice.primaryChoice(d).raw == (OfflineModelCatalog.ready(.ema) ? "ema:tr" : AppVoice.defaultPrimary.raw))
        // Açık seçim her zaman öndedir.
        d.set("apple:F", forKey: AppVoice.primaryKey)
        #expect(AppVoice.primaryChoice(d).raw == "apple:F")
    }

    @Test func firstPieceIsShortSoSpeechStartsEarly() {
        let text = "Mitoz, vücut hücrelerinde görülen ve iki özdeş hücre oluşturan bölünmedir. Mayoz ise üreme ana hücrelerinde görülür, kromozom sayısını yarıya indirir ve dört hücre oluşturur. Mitozda genetik çeşitlilik olmaz; mayozda krossing over ile çeşitlilik sağlanır."
        let pieces = SpeechOut.pieces(text)
        #expect(pieces.count >= 3 && pieces.first!.count <= 110 && pieces.allSatisfy { $0.count <= 220 })
        #expect(pieces.joined(separator: " ") == text)
        #expect(SpeechOut.pieces("").isEmpty && SpeechOut.pieces("Kısa.") == ["Kısa."])
    }

    @Test func neuralSettingsFollowTheAppVoice() {
        let d = UserDefaults(suiteName: "SpeechOutNeuralTests-\(UUID())")!
        // Chirp, Apple ve sunucu sesi: Apple'ın sesi okur.
        // EMA inmemişken (simülatör) Apple'ın sesi; EMA inmişse ses ayarı ne olursa olsun EMA.
        for raw in ["Kore@chirp", "apple:F", "xtts:6d01e02dbed1"] {
            d.set(raw, forKey: AppVoice.primaryKey)
            let settings = SpeechOut.neuralSettings(d)
            #expect(OfflineModelCatalog.ready(.ema) ? settings?.engine == .ema : settings == nil, Comment(rawValue: raw))
        }
        // EMA-TTS seçili ama model inmemiş (simülatör): yine Apple'a düşer; model inince tek anlatıcılı EMA ayarı döner.
        d.set("ema:tr", forKey: AppVoice.primaryKey)
        let settings = SpeechOut.neuralSettings(d)
        if OfflineModelCatalog.ready(.ema) {
            #expect(settings?.engine == .ema && settings?.format == .tekAnlatici && settings?.language == .tr)
        } else {
            #expect(settings == nil)
        }
    }
}
