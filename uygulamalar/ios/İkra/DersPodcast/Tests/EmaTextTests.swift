import Foundation
import Testing
@testable import Ikra

/// EMA-TTS metin ön işlemesi, modelin kendi `text.py` örnekleriyle birebir (sayılar hariç; onları TurkishReading açar).
struct EmaTextTests {
    @Test func matchesTheModelsOwnNormalizer() {
        #expect(EmaText.prepare("Merhaba , nasılsın") == ". merhaba, nasılsın.")
        #expect(EmaText.prepare("HÂLÂ  bekliyorum!!!") == ". hala bekliyorum!")
        #expect(EmaText.prepare("İSTANBUL'da yaşıyorum") == ". istanbul'da yaşıyorum.")
        #expect(EmaText.prepare("Fotosentez,kloroplastta olur…Neden?!") == ". fotosentez, kloroplastta olur. neden?")
        #expect(EmaText.prepare("Işık ve ılık: ŞIK, ÇİĞ.") == ". ışık ve ılık: şık, çiğ.")
        // Kıvrık tırnak ve uzun çizgi düz karşılığına; sondaki virgül noktaya döner; baş öneki bir kez eklenir.
        #expect(EmaText.prepare("“Hücre” – canlıların yapı birimi,") == ". \"hücre\" - canlıların yapı birimi.")
        #expect(EmaText.prepare(". Zaten önekli.") == ". zaten önekli.")
        #expect(EmaText.normalize("a 1.543 b") == "a 1.543 b.")  // rakamdan önceki noktaya boşluk eklenmez (sayılar daha önce açılır)
        #expect(EmaText.prepare("") == ". ")
    }

    @Test func emaIsAnOnDeviceSingleVoiceEngineInEveryModule() {
        #expect(SpeechEngine.ema.isNeuralOnDevice && !SpeechEngine.ema.usesServer && !SpeechEngine.ema.supportsTwoHosts && SpeechEngine.ema.turkishOnly)
        #expect(SpeechEngine.offered.contains(.ema) && OfflineModelCatalog.engines.contains(.ema))
        #expect(OfflineModelCatalog.directory(.ema).lastPathComponent == "ema-tts")
        let manifest = try? OfflineModelCatalog.manifest(.ema)
        #expect(manifest?.baseURL?.hasPrefix("https://") == true && manifest?.files.map(\.path).sorted() == ["coskulu/ema_align.onnx", "coskulu/ema_dit.onnx", "coskulu/ema_text.onnx", "ema.json", "ema_align.onnx", "ema_dit.onnx", "ema_text.onnx", "ema_vae.onnx"])
        #expect(manifest?.files.allSatisfy { $0.hashKind == "sha256" && $0.hash.count == 64 && $0.size > 0 } == true)
        // Ses anahtarı: cihaz içi motor, tek ses "tr"; podcast ayarına çevrilince tek anlatıcı biçimi.
        let key = QSVoiceKey(local: .ema, voice: "tr")
        #expect(key.raw == "ema:tr" && QSVoiceKey(key.raw) == key && key.isLocal && key.engine.speech == .ema && key.localVoice == "tr")
        #expect(QSLocalVoices.options(.ema).map(\.id) == ["tr", "coskulu"] && QSLocalVoices.valid("bilinmeyen", engine: .ema) == "tr" && QSLocalVoices.valid("coskulu", engine: .ema) == "coskulu")
        // Coşkulu ses ayrı anahtar ("ema:coskulu"); podcast ayarına yerel ses olarak geçer ve tek anlatıcıdır.
        let lively = QSVoiceKey(local: .ema, voice: "coskulu")
        var livelySettings = PodcastSettings()
        livelySettings.apply(voiceA: lively)
        #expect(lively.raw == "ema:coskulu" && livelySettings.engine == .ema && livelySettings.localVoiceA == "coskulu" && livelySettings.format == .tekAnlatici)
        #expect(LocalSpeech.cacheKey(livelySettings) != LocalSpeech.cacheKey({ var s = livelySettings; s.localVoiceA = "tr"; return s }()))
        var settings = PodcastSettings()
        settings.apply(voiceA: key)
        #expect(settings.engine == .ema && settings.format == .tekAnlatici && settings.language == .tr && settings.voiceKey(.a) == key)
        #expect(QSSceneVoice.localSettings(key, student: "ema:tr").format == .tekAnlatici)
        #expect(AppVoice.usable("ema:tr")?.raw == "ema:tr" && AppVoice.partner(nil, avoiding: key).engine == .ema)
    }
}
