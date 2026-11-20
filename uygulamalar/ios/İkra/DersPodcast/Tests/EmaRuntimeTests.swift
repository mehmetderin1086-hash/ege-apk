import Foundation
import Testing
@testable import Ikra
import PiperRuntime

/// EMA-TTS ONNX çalışma zamanının uçtan uca denemesi. Model dosyaları (≈ 220 MB) depoda olmadığından isteğe bağlıdır:
/// `TEST_RUNNER_EMA_DIR=<ema.json ve dört .onnx dosyasının klasörü> xcodebuild test … -only-testing:IkraTests/EmaRuntimeTests`.
struct EmaRuntimeTests {
    @Test func synthesizesTurkishSpeechOnDevice() async throws {
        let env = ProcessInfo.processInfo.environment
        var directory: URL
        if let dir = env["EMA_DIR"], !dir.isEmpty { directory = URL(filePath: dir) }
        else if env["EMA_DOWNLOAD"] == "1" {
            // Gerçek cihaz: model manifestteki sunucudan geçici klasöre iner (≈ 220 MB), indirme süresi de ölçülür.
            directory = URL.temporaryDirectory.appending(path: "ema-tts-test", directoryHint: .isDirectory)
            let manifest = try OfflineModelCatalog.manifest(.ema)
            let t = Date()
            try await SpeechModelTransfer.download(manifest, to: directory) { _, _ in }
            print("EMA_RUNTIME indirme \(String(format: "%.0f", Date().timeIntervalSince(t))) sn, \(manifest.size / 1_000_000) MB")
            #expect(OfflineModelCatalog.ready(manifest, directory: directory))
        } else { return }
        let started = Date()
        let ema = try EmaTTS(directory: directory)
        let loaded = Date().timeIntervalSince(started)
        #expect(ema.config.sampleRate == 48_000 && ema.config.vocab.count == 61 && ema.config.steps == 32)
        // Sözlük ve kelime aralıkları `prepare_text` ile aynı: baş öneki ilk birime katılır.
        let encoded = ema.encode(". merhaba dünya.")
        #expect(encoded.ids.count == 16 && encoded.spans.count == 3 && encoded.spans[0] == (0, 2) && encoded.spans[1] == (2, 10) && encoded.spans[2] == (10, 16))
        #expect(!encoded.ids.contains(1), "bütün karakterler sözlükte olmalı")
        let text = EmaText.prepare("Fotosentez, bitkilerin ışık enerjisini kullanarak karbondioksit ve sudan glikoz ürettiği olaydır.")
        let t0 = Date()
        var state: UInt64 = 42
        let audio = try ema.synthesize(text, noise: { state = state &* 6364136223846793005 &+ 1442695040888963407; return Float(state >> 40) / Float(1 << 24) })
        let elapsed = Date().timeIntervalSince(t0)
        let seconds = Double(audio.samples.count) / Double(audio.sampleRate)
        print("EMA_RUNTIME yükleme \(String(format: "%.1f", loaded)) sn, üretim \(String(format: "%.1f", elapsed)) sn, ses \(String(format: "%.1f", seconds)) sn, tepe \(audio.samples.map(abs).max() ?? 0)")
        #expect(audio.sampleRate == 48_000 && seconds > 4 && seconds < 12, "6 saniyelik cümle beklenir, \(seconds)")
        if let out = env["EMA_OUT"], !out.isEmpty {
            // "documents": gerçek cihazda uygulama kabının Documents klasörüne (devicectl ile çekilir). Ham Float32 örnekler de yazılır
            // (sunucudaki aynı gürültüyle üretilen çıktıyla örnek örnek karşılaştırma için).
            let url = out == "documents" ? URL.documentsDirectory.appending(path: "ema-test.wav") : URL(filePath: out)
            try WAV.encode(LocalSpeech.pcm(audio.samples, sampleRate: audio.sampleRate)).write(to: url)
            try audio.samples.withUnsafeBytes { Data($0) }.write(to: url.deletingPathExtension().appendingPathExtension("f32"))
        }
        #expect(audio.samples.allSatisfy(\.isFinite) && (audio.samples.map(abs).max() ?? 0) > 0.05)
        // Hız: süreler bölünür → daha kısa ses.
        let fast = try ema.synthesize(text, steps: 4, speed: 1.3)
        #expect(Double(fast.samples.count) < Double(audio.samples.count) * 0.9)
        // Coşkulu ses (ince ayarlı DiT/hizalayıcı/metin kodlayıcı `coskulu/` altında, VAE ortak): aynı cümle anlaşılır uzunlukta ses üretir.
        if FileManager.default.fileExists(atPath: directory.appending(path: "coskulu/ema_dit.onnx").path) {
            let lively = try EmaTTS(directory: directory, voice: "coskulu")
            let t1 = Date()
            let other = try lively.synthesize(text, noise: { state = state &* 6364136223846793005 &+ 1442695040888963407; return Float(state >> 40) / Float(1 << 24) })
            let otherSeconds = Double(other.samples.count) / Double(other.sampleRate)
            print("EMA_RUNTIME coşkulu üretim \(String(format: "%.1f", Date().timeIntervalSince(t1))) sn, ses \(String(format: "%.1f", otherSeconds)) sn")
            #expect(other.sampleRate == 48_000 && otherSeconds > 4 && otherSeconds < 12 && other.samples.allSatisfy(\.isFinite) && (other.samples.map(abs).max() ?? 0) > 0.05)
            #expect(other.samples != audio.samples, "ince ayarlı model tabandan farklı ses üretmeli")
        }
        // Podcast yolu: PCMClip'e çevrim.
        let clip = try LocalSpeech.pcm(audio.samples, sampleRate: audio.sampleRate)
        #expect(clip.sampleRate == 48_000 && abs(Double(clip.samples.count) / 48_000 - seconds) < 0.05)
    }
}
