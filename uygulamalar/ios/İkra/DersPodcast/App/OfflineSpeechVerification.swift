#if DEBUG
import AVFoundation
import CryptoKit
import Foundation
import SwiftData
import UIKit

/// Opt-in physical-device integration check. Does not contact a script/TTS API.
/// Launch with -offlineSpeechVerify -autoVerify NO -autoStudyPack NO.
enum OfflineSpeechVerification {
    static var report: [String: Any] = [:]
    static let directory = URL.documentsDirectory.appending(path: "OfflineSpeechVerification")

    static func record(_ key: String, _ value: Any) {
        report[key] = value
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appending(path: "report.json"), options: .atomic)
        }
        print("OFFLINE_SPEECH \(key): \(value)")
    }

    static func run(context: ModelContext, generator: GenerationCoordinator) async -> Episode? {
        guard ProcessInfo.processInfo.arguments.contains("-offlineSpeechVerify") else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let previousIdle = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = previousIdle }
        record("started", Date().description)
        record("device", UIDevice.current.model + " iOS " + UIDevice.current.systemVersion)
        var last: Episode?
        do {
            let models = OfflineSpeechModels.shared
            for engine in OfflineModelCatalog.engines {
                record("stage", "download-" + engine.rawValue)
                if !OfflineModelCatalog.ready(engine) {
                    models.download(engine)
                    await models.waitForDownload(engine)
                }
                guard OfflineModelCatalog.ready(engine) else {
                    throw OfflineSpeechError.message(models.state(engine).message ?? "Model not ready")
                }
                record(engine.rawValue + "-download", "verified")
            }
            var metrics: [[String: Any]] = []
            for voice in (1...5).map({ "F\($0)" }) + (1...5).map({ "M\($0)" }) + ["dfki", "tr"] {
                let engine: SpeechEngine = voice == "dfki" ? .piper : voice == "tr" ? .ema : .supertonic
                record("stage", "synthesize-" + voice)
                var settings = PodcastSettings(speechProvider: engine.rawValue)
                settings.format = .tekAnlatici
                let speaker: Speaker = voice.hasPrefix("M") ? .b : .a
                if speaker == .a, engine == .supertonic { settings.localVoiceA = voice }
                if speaker == .b { settings.localVoiceB = voice }
                let started = Date()
                let clip = try await LocalSpeech.scene(turns: [.init(speaker: speaker,
                    text: "Hücre, canlıların temel yapı ve görev birimidir. Işık ve su, fotosentez için gereklidir.", style: "", sourcePage: nil)], settings: settings)
                let data = WAV.encode(clip)
                try data.write(to: directory.appending(path: voice + ".wav"), options: .atomic)
                let rms = sqrt(clip.samples.reduce(0.0) { $0 + pow(Double($1) / 32768, 2) } / Double(clip.samples.count))
                guard rms > 0.0001 else { throw OfflineSpeechError.noAudio }
                metrics.append(["voice": voice, "seconds": Double(clip.samples.count) / Double(clip.sampleRate),
                                "generationSeconds": Date().timeIntervalSince(started), "sampleRate": clip.sampleRate,
                                "rms": rms, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()])
                record("voices", metrics)
            }
            // Force both runtime models to reopen from the downloaded files.
            await NeuralSpeechRenderer.shared.unload()
            for engine in OfflineModelCatalog.engines {
                record("stage", "podcast-" + engine.rawValue)
                var settings = PodcastSettings(speechProvider: engine.rawValue)
                if !engine.supportsTwoHosts { settings.format = .tekAnlatici }
                let turns: [ScriptTurn] = [
                    .init(speaker: .a, text: "Merhaba. Bu ders iPhone üzerinde seslendirildi. Hücrenin temel kısımları hücre zarı, sitoplazma ve çekirdektir.", style: "", sourcePage: nil),
                    .init(speaker: engine.supportsTwoHosts ? .b : .a, text: "Hücre zarı seçici geçirgendir. Şimdi düşünelim: Bir hücrenin su alması, çevresindeki çözeltiye nasıl bağlıdır?", style: "", sourcePage: nil)
                ]
                let title = (engine == .supertonic ? "Supertonic" : engine == .ema ? "EMA-TTS" : "Piper") + " · iPhone ses denemesi"
                let script = PodcastScript(title: title, summary: "Gerçek cihazda Türkçe ses üretimi", keyPoints: [],
                    chapters: [.init(title: "Hücre", scenes: turns.map { .init(turns: [$0]) })], sourceNotes: "Cihaz içi ses doğrulaması")
                let episode = Episode(script: script, settings: settings, sourceNames: ["iPhone ses denemesi"], jobToken: "")
                episode.jobToken = nil
                episode.visuals = .init(cover: .init(title: title, subtitle: engine.title, symbol: "waveform", theme: "ocean", motif: "network", accessibilityLabel: title), diagrams: [], model: "local-verification")
                context.insert(episode); try context.save()
                generator.resume(episode, context: context)
                let deadline = Date().addingTimeInterval(600)
                while generator.isRunning(episode), Date() < deadline { try await Task.sleep(for: .seconds(1)) }
                guard episode.status == .ready, let url = episode.audioURL else {
                    throw OfflineSpeechError.message(episode.errorMessage ?? "Podcast generation timed out")
                }
                let audio = try AVAudioPlayer(contentsOf: url)
                guard audio.duration > 1, episode.timeline?.turns.count == 2 else { throw OfflineSpeechError.noAudio }
                record(engine.rawValue + "-podcast", ["id": episode.id.uuidString, "duration": audio.duration,
                    "scenes": episode.scenesDone, "turns": episode.timeline?.turns.count ?? 0, "audioBytes": (try Data(contentsOf: url)).count])
                last = episode
            }
            record("result", "passed")
        } catch {
            record("error", error.localizedDescription)
            record("result", "failed")
        }
        record("finished", Date().description)
        return last
    }
}
#endif
