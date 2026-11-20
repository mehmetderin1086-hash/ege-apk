#if DEBUG
import Foundation
import AVFoundation
import SwiftData

/// Yalnızca Debug: `-demoEpisode` başlatma argümanıyla, sunucuya gitmeden sahte bir bölüm oluşturur.
/// Arayüz düzenini simülatörde denetlemek ve ekran görüntüsü almak için kullanılır.
enum DebugSeed {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-demoEpisode") }

    static func seedIfRequested(context: ModelContext) async -> Episode? {
        if ProcessInfo.processInfo.arguments.contains("-studioDemo") {
            return StudioPreview.seed(context: context)
        }
        if ProcessInfo.processInfo.arguments.contains("-deviceSpeechEpisode") || ProcessInfo.processInfo.arguments.contains("-chirpEpisode") || ProcessInfo.processInfo.arguments.contains("-edgeEpisode") || ProcessInfo.processInfo.arguments.contains("-hfEpisode") {
            let voices = DeviceSpeech.voices().map { ["name": $0.name, "quality": String($0.quality.rawValue), "gender": String($0.gender.rawValue), "identifier": $0.identifier] }
            if let data = try? JSONSerialization.data(withJSONObject: voices, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL.documentsDirectory.appending(path: "device-voices.json"), options: .atomic)
            }
            let chirp = ProcessInfo.processInfo.arguments.contains("-chirpEpisode")
            let edge = ProcessInfo.processInfo.arguments.contains("-edgeEpisode")
            let hf = ProcessInfo.processInfo.arguments.contains("-hfEpisode")
            let title = edge ? "Edge TTS · Emel ve Ahmet" : hf ? "Hugging Face · MMS Türkçe" : chirp ? "Chirp HD · Kore ve Puck" : "Yelda ve Cem · Doğrulama"
            if let existing = try? context.fetch(FetchDescriptor<Episode>()).first(where: { $0.title == title }) { return existing }
            var script = PodcastScript(title: title, summary: "Gerçek cihaz içi ses üretimi testi", keyPoints: [], chapters: [.init(title: "Hücre", scenes: [.init(turns: [
                .init(speaker: .a, text: chirp ? "Merhaba, ben Kore. Bu ders Google Chirp HD ile seslendiriliyor. Hücre, canlıların temel yapı ve görev birimidir." : "Merhaba. Bu dersin sesi iPhone üzerinde oluşturuldu. Hücre, canlıların temel yapı ve görev birimidir.", style: "", sourcePage: nil),
                .init(speaker: .b, text: chirp ? "Ben de Puck. Kadın ve erkek sunucu ayrı seslerle konuşuyor. Kaydedilen dersimizi çevrimdışı dinleyebiliriz." : "Bu seslendirme bulut ses kotası kullanmıyor. Dersimizi çevrimdışı dinleyebiliriz.", style: "", sourcePage: nil)
            ])])], sourceNotes: "Cihaz sesi testi")
            if edge || hf {
                script.chapters[0].scenes[0].turns[0].text = "Merhaba. Hücre canlıların temel yapı birimidir."
                script.chapters[0].scenes[0].turns[1].text = "Bugün hücrenin görevlerini öğreniyoruz."
            }
            if hf { script.chapters[0].scenes[0].turns = Array(script.chapters[0].scenes[0].turns.prefix(1)) }
            var speechSettings = PodcastSettings(speechProvider: edge ? "edge" : hf ? "huggingface" : chirp ? "chirp" : "apple")
            if hf { speechSettings.format = .tekAnlatici }
            let episode = Episode(script: script, settings: speechSettings, sourceNames: ["Ses doğrulaması"], jobToken: "")
            episode.jobToken = nil
            // Bu doğrulama yalnızca yerel ses içindir; görsel isteği gönderilmez.
            episode.visuals = VisualPack(cover: .init(title: title, subtitle: "Apple cihaz sesi", symbol: "waveform", theme: "ocean", motif: "network", accessibilityLabel: title), diagrams: [], model: "local-test")
            context.insert(episode)
            try? context.save()
            return episode
        }
        if ProcessInfo.processInfo.arguments.contains("-verifiedEpisode") {
            return await seedVerified(context: context)
        }
        guard isRequested else { return nil }
        if let existing = try? context.fetch(FetchDescriptor<Episode>()).first(where: { $0.title == demoTitle }) {
            return existing
        }
        let turns: [ScriptTurn] = [
            .init(speaker: .a, text: "Merhaba sevgili dinleyiciler, bugün görme duyusunu ve gözün anatomik yapısını konuşacağız. Ben Elif.", style: "neşeli", sourcePage: 1),
            .init(speaker: .b, text: "Ben de Can. Gözün dış tabakasındaki sert yapı ön tarafta beyaz kalmıyor, saydamlaşıyor sanırım. Kornea dediğimiz yer burası mı?", style: "meraklı", sourcePage: 2),
            .init(speaker: .a, text: "Çok doğru tespit Can. Sert tabaka ön tarafa doğru incelip saydamlaşır ve hafif şişkinleşerek korneayı, yani saydam tabakayı oluşturur.", style: "açıklayıcı", sourcePage: 2),
            .init(speaker: .b, text: "Peki korneanın görevi nedir ve nasıl beslenir? Kan damarı yok diye hatırlıyorum.", style: "meraklı", sourcePage: 2),
        ]
        let script = PodcastScript(
            title: demoTitle, summary: "Gözün katmanları, kornea ve görme süreci.",
            keyPoints: ["Kornea saydamdır ve damarsızdır.", "Işık önce korneada kırılır."],
            chapters: [ScriptChapter(title: "Gözün dış tabakası", scenes: [ScriptScene(turns: Array(turns[0..<2])), ScriptScene(turns: Array(turns[2...]))]),
                       ScriptChapter(title: "Kornea ve ışığın kırılması", scenes: [ScriptScene(turns: turns)])],
            sourceNotes: "Demo")
        let episode = Episode(script: script, settings: PodcastSettings(speechProvider: "apple"), sourceNames: ["Demo"], jobToken: "demo")

        // Her tur için 4 sn ton + 0,5 sn sessizlik içeren sahte sahneler.
        var inputs: [AudioStitcher.SceneInput] = []
        for (index, item) in script.flatScenes.enumerated() {
            var samples: [Int16] = []
            for _ in item.scene.turns {
                samples += (0..<96_000).map { Int16(6000 * sin(2 * .pi * 220 * Double($0) / 24_000)) }
                samples += Array(repeating: 0, count: 12_000)
            }
            let url = EpisodeFiles.sceneURL(episode: episode.id, index: index)
            try? WAV.encode(PCMClip(samples: samples, sampleRate: 24_000)).write(to: url)
            inputs.append(.init(url: url, chapterIndex: item.chapterIndex, turns: item.scene.turns))
        }
        let output = episode.directory.appending(path: "podcast.m4a")
        guard let timeline = try? await AudioStitcher.stitch(scenes: inputs, chapterTitles: script.chapters.map(\.title), output: output) else { return nil }
        episode.audioFileName = "podcast.m4a"
        episode.timeline = timeline
        episode.duration = timeline.duration
        episode.status = .ready
        episode.jobToken = nil
        // Slayt kartının uzun metinlerle yerleşimini denetlemek için.
        episode.slides = [LessonSlide(chapterIndex: 0, title: "Ağ Tabaka: Çubuklar, Koniler ve Sarı Benek",
                                      bullets: ["Çubuk hücreleri: az ışıkta siyah-beyaz görmeyi sağlar ve retinanın kenarlarında yoğundur",
                                                "Koni hücreleri: yeterli ışıkta renkli ve net görmeyi sağlar",
                                                "Sarı benek: optik eksenin retinaya düştüğü, konilerin en yoğun olduğu nokta",
                                                "İnsan gözü 380-750 nm aralığındaki dalga boylarını algılar"],
                                      formula: nil, symbol: "sun.max.fill")]
        context.insert(episode)
        try? context.save()
        return episode
    }

    private static let demoTitle = "Görme Duyusu ve Gözün Anatomik Yapısı"

    /// Açık Debug argümanı ile gerçek HTTP doğrulama çıktısını gösterir; anahtar içermez.
    private static func seedVerified(context: ModelContext) async -> Episode? {
        let root = URL.documentsDirectory.appending(path: "CLIProxyVerification")
        do {
            let decoder = JSONDecoder()
            var script = try decoder.decode(PodcastScript.self, from: Data(contentsOf: root.appending(path: "sample-script.json")))
            let visuals = try decoder.decode(VisualPack.self, from: Data(contentsOf: root.appending(path: "sample-visuals.json")))
            guard let chapter = script.chapters.first, let scene = chapter.scenes.first else { return nil }
            script.chapters = [.init(title: chapter.title, scenes: [scene])]
            script.title += " · Doğrulama"
            if let existing = try context.fetch(FetchDescriptor<Episode>()).first(where: { $0.title == script.title }) { return existing }
            let episode = Episode(script: script, settings: PodcastSettings(speechProvider: "apple"), sourceNames: ["CLIProxy gerçek üretim testi"], jobToken: "verification")
            let output = episode.directory.appending(path: "podcast.m4a")
            let timeline = try await AudioStitcher.stitch(scenes: [.init(url: root.appending(path: "sample-podcast-scene.wav"), chapterIndex: 0, turns: scene.turns)], chapterTitles: [chapter.title], output: output)
            episode.visuals = visuals
            episode.study = try? decoder.decode(StudyPack.self, from: Data(contentsOf: root.appending(path: "sample-study.json")))
            episode.timeline = timeline
            episode.audioFileName = "podcast.m4a"
            episode.duration = timeline.duration
            episode.status = .ready
            episode.jobToken = nil
            context.insert(episode)
            try context.save()
            return episode
        } catch { return nil }
    }
}
#endif
