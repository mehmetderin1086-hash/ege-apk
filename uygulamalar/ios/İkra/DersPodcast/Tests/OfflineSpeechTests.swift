import CryptoKit
import Foundation
import Testing
@testable import Ikra

@MainActor
struct OfflineSpeechTests {
    @Test func legacySettingsKeepTheirEngineAndReceiveVoiceDefaults() throws {
        let old = try JSONDecoder().decode(PodcastSettings.self, from: Data(#"{"speechProvider":"apple","durationMin":20}"#.utf8))
        #expect(old.engine == .apple && old.durationMin == 20)
        #expect(old.localVoiceA == "F1" && old.localVoiceB == "M1")
        for engine in SpeechEngine.allCases {
            var settings = PodcastSettings(speechProvider: engine.rawValue)
            settings.localVoiceA = "F4"; settings.localVoiceB = "M3"
            let saved = try JSONDecoder().decode(PodcastSettings.self, from: JSONEncoder().encode(settings))
            #expect(saved == settings)
            #expect(QualityMode.apply(to: settings).engine == engine)
        }
    }

    @Test func localEnginesNeverUseServerSpeechAndRejectUnsupportedSettings() throws {
        for engine in [SpeechEngine.supertonic, .piper, .ema] {
            var settings = PodcastSettings(speechProvider: engine.rawValue)
            #expect(!settings.usesServerSpeech && engine.isNeuralOnDevice)
            settings.format = .tekAnlatici
            try LocalSpeech.validate(settings, requireModel: false)
        }
        var piper = PodcastSettings(speechProvider: "piper")
        #expect(throws: OfflineSpeechError.self) { try LocalSpeech.validate(piper, requireModel: false) }
        // EMA-TTS de tek seslidir: iki sunuculu biçim ve İngilizce reddedilir.
        var ema = PodcastSettings(speechProvider: "ema")
        #expect(throws: OfflineSpeechError.self) { try LocalSpeech.validate(ema, requireModel: false) }
        ema.format = .tekAnlatici; ema.language = .en
        #expect(throws: OfflineSpeechError.self) { try LocalSpeech.validate(ema, requireModel: false) }
        piper.format = .tekAnlatici; piper.language = .en
        #expect(throws: OfflineSpeechError.self) { try LocalSpeech.validate(piper, requireModel: false) }
        var supertonic = PodcastSettings(speechProvider: "supertonic")
        supertonic.localVoiceA = "../../bad"
        #expect(throws: OfflineSpeechError.self) { try LocalSpeech.validate(supertonic, requireModel: false) }
    }

    @Test func chunksPreserveTurkishAndBoundLongInputs() {
        let text = Array(repeating: "Işık, çığ, öğüt, ığdır; ĞÜŞİÖÇ. Öğrenci hücreyi öğreniyor! 👩🏽‍🔬", count: 40).joined(separator: " ")
        let chunks = LocalSpeech.chunks(text)
        #expect(chunks.count > 2 && chunks.allSatisfy { !$0.isEmpty && $0.count <= 180 })
        #expect(chunks.joined(separator: " ") == text)
        let long = String(repeating: "ğ", count: 1001)
        #expect(LocalSpeech.chunks(long).joined() == long)
        #expect(LocalSpeech.chunks(" \n \t").isEmpty)
    }

    @Test func cachedScenesSeparateVoicesPaceAndLanguage() {
        let original = PodcastSettings(speechProvider: "supertonic")
        var changed = original; changed.localVoiceA = "F2"
        #expect(LocalSpeech.cacheKey(original) != LocalSpeech.cacheKey(changed))
        changed = original; changed.localVoiceB = "M5"
        #expect(LocalSpeech.cacheKey(original) != LocalSpeech.cacheKey(changed))
        changed = original; changed.pace = .yavas
        #expect(LocalSpeech.cacheKey(original) != LocalSpeech.cacheKey(changed))
        changed = original; changed.language = .en
        #expect(LocalSpeech.cacheKey(original) != LocalSpeech.cacheKey(changed))
    }

    @Test func actualManifestContainsPinnedModelsAndAllTenVoices() throws {
        let s = try OfflineModelCatalog.manifest(.supertonic)
        let p = try OfflineModelCatalog.manifest(.piper)
        #expect(s.revision.count == 40 && p.revision.count == 40)
        for prefix in ["F", "M"] {
            for i in 1...5 { #expect(s.files.contains { $0.path == "voice_styles/\(prefix)\(i).json" }) }
        }
        #expect(p.files.contains { $0.path == "tr_TR-dfki-medium.onnx" })
        #expect(p.files.contains { $0.path == "espeak-ng-data/tr_dict" })
        for manifest in [s, p] {
            #expect(Set(manifest.files.map(\.path)).count == manifest.files.count)
            #expect(manifest.files.allSatisfy { !$0.path.hasPrefix("/") && !$0.path.split(separator: "/").contains("..") })
            #expect(manifest.files.allSatisfy { $0.hash.count == ($0.hashKind == "sha256" ? 64 : 40) })
        }
    }

    @Test func downloadVerificationRejectsCorruptionAndIncompleteModels() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = Data("Türkçe model doğrulaması".utf8)
        let url = directory.appending(path: "test.bin")
        try data.write(to: url)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let file = OfflineModelManifest.File(path: "test.bin", size: Int64(data.count), hash: hash, hashKind: "sha256")
        try OfflineModelCatalog.validate(file, at: url)
        let blob = Data("blob \(data.count)\0".utf8) + data
        let git = Insecure.SHA1.hash(data: blob).map { String(format: "%02x", $0) }.joined()
        try OfflineModelCatalog.validate(.init(path: "test.bin", size: Int64(data.count), hash: git, hashKind: "git-sha1"), at: url)
        let manifest = OfflineModelManifest(repository: "test", revision: "pinned", files: [file])
        #expect(!OfflineModelCatalog.ready(manifest, directory: directory))
        try "pinned".write(to: directory.appending(path: ".ready"), atomically: true, encoding: .utf8)
        #expect(OfflineModelCatalog.ready(manifest, directory: directory))
        try Data(repeating: 0, count: data.count).write(to: url)
        #expect(throws: OfflineSpeechError.self) { try OfflineModelCatalog.validate(file, at: url) }
        try FileManager.default.removeItem(at: url)
        #expect(!OfflineModelCatalog.ready(manifest, directory: directory))
    }

    @Test func nativeSampleRatesBecomeValid48kAudioAndRejectInvalidOutput() throws {
        for rate in [22_050, 44_100] {
            let samples = (0..<rate).map { Float(0.4 * sin(2 * .pi * 440 * Double($0) / Double(rate))) }
            let clip = try LocalSpeech.pcm(samples, sampleRate: rate)
            #expect(clip.sampleRate == 48_000)
            #expect(abs(clip.samples.count - 48_000) < 256)
            #expect(clip.samples.contains { abs(Int($0)) > 1000 })
            #expect(try WAV.parse(WAV.encode(clip)).samples == clip.samples)
        }
        for samples: [Float] in [[], [0, 0], [.nan], [.infinity]] {
            #expect(throws: OfflineSpeechError.self) { try LocalSpeech.pcm(samples, sampleRate: 44_100) }
        }
    }
}
