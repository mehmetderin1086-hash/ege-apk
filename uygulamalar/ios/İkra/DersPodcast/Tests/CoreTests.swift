import AVFoundation
import Foundation
import Testing
import SwiftData
@testable import Ikra

private final class BundleToken {}

@MainActor
struct VisualPersistenceTests {
    @Test func oldEpisodeAndGeneratedVisualsSurviveSaving() throws {
        let container = try ModelContainer(for: Episode.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let script = PodcastScript(title: "Hücre", summary: "Zar", keyPoints: [], chapters: [], sourceNotes: "Zar")
        let old = Episode(script: script, settings: PodcastSettings(), sourceNames: [], jobToken: "test")
        context.insert(old)
        try context.save()
        #expect(old.visuals == nil)
        let cover = VisualCover(title: "Hücre", subtitle: "Zar", symbol: "atom", theme: "ocean", motif: "network", accessibilityLabel: "Hücre kapağı")
        let pack = VisualPack(cover: cover, diagrams: [.init(title: "Geçiş", caption: "Zar", layout: "flow", steps: [.init(title: "Pasif", detail: "ATP harcanmaz", symbol: "atom")])], model: "eski-model")
        old.visuals = pack
        try context.save()
        let saved = try #require(context.fetch(FetchDescriptor<Episode>()).first)
        #expect(saved.visuals == pack)
        #expect(saved.script == script)
    }
}

struct DocxTests {
    @Test func extractsTurkishParagraphs() throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "sample", withExtension: "docx"))
        let text = try DocxTextExtractor.extractText(from: Data(contentsOf: url))
        let lines = text.components(separatedBy: "\n")
        #expect(lines.first == "Fotosentez")
        #expect(text.contains("Bitkiler ışık enerjisini kimyasal enerjiye dönüştürür."))
        #expect(text.contains("ğüşıöç ĞÜŞİÖÇ"))
        #expect(lines.count == 3)
    }

    @Test func rejectsNonZip() {
        #expect(throws: DocxTextExtractor.DocxError.self) {
            try DocxTextExtractor.extractText(from: Data("merhaba dünya, bu bir zip değil".utf8))
        }
    }
}

struct WAVTests {
    @Test func roundTrip() throws {
        let clip = PCMClip(samples: [0, 1000, -1000, Int16.max, Int16.min], sampleRate: 24_000)
        let data = WAV.encode(clip)
        #expect(data.count == 44 + 10)
        let parsed = try WAV.parse(data)
        #expect(parsed.samples == clip.samples)
        #expect(parsed.sampleRate == 24_000)
    }

    @Test func toleratesStreamingSizeFields() throws {
        var data = WAV.encode(PCMClip(samples: Array(repeating: 500, count: 100), sampleRate: 24_000))
        // data chunk boyutunu 0xFFFFFFFF yap (akış çıktısında görülür)
        data.replaceSubrange(40..<44, with: [0xFF, 0xFF, 0xFF, 0xFF])
        #expect(try WAV.parse(data).samples.count == 100)
    }

    @Test func rejectsGarbage() {
        #expect(throws: WAV.ParseError.self) { try WAV.parse(Data(repeating: 1, count: 64)) }
    }
}

/// Konuşma benzeri sinyal: 220 Hz sinüs.
private func tone(_ seconds: Double, rate: Int = 24_000) -> [Int16] {
    (0..<Int(seconds * Double(rate))).map { Int16(9000 * sin(2 * .pi * 220 * Double($0) / Double(rate))) }
}

private func silence(_ seconds: Double, rate: Int = 24_000) -> [Int16] {
    Array(repeating: 0, count: Int(seconds * Double(rate)))
}

struct SilenceAlignerTests {
    @Test func snapsBoundariesToSilences() {
        // 3 tur: 2 sn, 0.4 sn sessizlik, 4 sn, 0.4 sn sessizlik, 2 sn
        let samples = tone(2) + silence(0.4) + tone(4) + silence(0.4) + tone(2)
        let clip = PCMClip(samples: samples, sampleRate: 24_000)
        // Karakter oranı bilerek biraz yanlış: gerçek oran 2:4:2, verilen 25:35:20
        let ranges = SilenceAligner.turnRanges(clip: clip, characterCounts: [25, 35, 20])
        #expect(ranges.count == 3)
        #expect(abs(ranges[1].start - 2.2) < 0.1)
        #expect(abs(ranges[2].start - 6.6) < 0.1)
        #expect(abs(ranges[2].end - clip.duration) < 0.001)
    }

    @Test func fallsBackToEstimateWithoutSilence() {
        let clip = PCMClip(samples: tone(6), sampleRate: 24_000)
        let ranges = SilenceAligner.turnRanges(clip: clip, characterCounts: [10, 20])
        #expect(abs(ranges[1].start - 2.0) < 0.05)
    }

    @Test func boundariesAreMonotonic() {
        let samples = tone(1) + silence(0.3) + tone(1) + silence(0.3) + tone(1) + silence(0.3) + tone(1)
        let clip = PCMClip(samples: samples, sampleRate: 24_000)
        let ranges = SilenceAligner.turnRanges(clip: clip, characterCounts: [100, 1, 1, 100])
        for i in 1..<ranges.count {
            #expect(ranges[i].start > ranges[i - 1].start)
            #expect(ranges[i].start == ranges[i - 1].end)
        }
    }

    @Test func singleTurnSpansWholeClip() {
        let clip = PCMClip(samples: tone(1.5), sampleRate: 24_000)
        let ranges = SilenceAligner.turnRanges(clip: clip, characterCounts: [42])
        #expect(ranges.count == 1)
        #expect(ranges[0].start == 0)
    }
}

struct StitcherTests {
    @Test func stitchesScenesAndBuildsTimeline() async throws {
        let dir = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        func scene(_ name: String, _ samples: [Int16]) throws -> URL {
            let url = dir.appending(path: name)
            try WAV.encode(PCMClip(samples: samples, sampleRate: 24_000)).write(to: url)
            return url
        }
        let turn = { (s: Speaker, t: String) in ScriptTurn(speaker: s, text: t, style: "", sourcePage: 1) }
        let inputs = [
            AudioStitcher.SceneInput(url: try scene("a.wav", tone(2) + silence(0.4) + tone(2)), chapterIndex: 0,
                                     turns: [turn(.a, "Merhaba"), turn(.b, "Selam")]),
            AudioStitcher.SceneInput(url: try scene("b.wav", tone(3)), chapterIndex: 0, turns: [turn(.a, "Devam")]),
            AudioStitcher.SceneInput(url: try scene("c.wav", tone(1)), chapterIndex: 1, turns: [turn(.b, "Yeni bölüm")]),
        ]
        let output = dir.appending(path: "out.m4a")
        let timeline = try await AudioStitcher.stitch(scenes: inputs, chapterTitles: ["Giriş", "Sonuç"], output: output, design: false)

        #expect(timeline.turns.count == 4)
        #expect(timeline.chapters.map(\.title) == ["Giriş", "Sonuç"])
        let expected = 4.4 + AudioStitcher.sceneGap + 3 + AudioStitcher.chapterGap + 1
        #expect(abs(timeline.duration - expected) < 0.05)
        #expect(abs(timeline.chapters[1].start - (4.4 + AudioStitcher.sceneGap + 3 + AudioStitcher.chapterGap)) < 0.05)
        #expect(timeline.turnIndex(at: 0.5) == 0)
        #expect(timeline.turnIndex(at: timeline.duration - 0.2) == 3)
        #expect(timeline.chapterIndex(at: timeline.duration - 0.2) == 1)

        let file = try AVAudioFile(forReading: output)
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        #expect(abs(seconds - expected) < 0.15)
    }
}

struct ScriptDecodingTests {
    @Test func decodesServerScript() throws {
        let json = """
        {"jobToken":"x.y",
         "script":{"title":"Fotosentez","summary":"Özet","keyPoints":["a"],"sourceNotes":"not",
         "chapters":[{"title":"Giriş","scenes":[{"turns":[{"speaker":"A","text":"Merhaba","style":"neşeli","sourcePage":null},
                                                           {"speaker":"B","text":"Selam","style":"meraklı","sourcePage":3}]}]}]}}
        """
        let response = try JSONDecoder().decode(ScriptResponse.self, from: Data(json.utf8))
        #expect(response.script.flatScenes.count == 1)
        #expect(response.script.chapters[0].scenes[0].turns[1].sourcePage == 3)
        #expect(response.script.totalCharacters == "Merhaba".count + "Selam".count)
    }

    @Test func encodesSourcesPerContract() throws {
        let request = ScriptRequest(settings: PodcastSettings(), sources: [.text("içerik", name: "Not"), .pdf(data: Data([1, 2, 3]), name: "Kitap")])
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        let sources = try #require(object?["sources"] as? [[String: Any]])
        #expect(sources[0]["kind"] as? String == "text")
        #expect(sources[1]["mimeType"] as? String == "application/pdf")
        #expect(sources[1]["data"] as? String == "AQID")
        let settings = try #require(object?["settings"] as? [String: Any])
        #expect(settings["level"] as? String == "universite")
        #expect((settings["hostA"] as? [String: Any])?["voice"] as? String == "Kore")
        #expect(settings["format"] as? String == "sohbet")
        #expect(settings["depth"] as? String == "dengeli")
        #expect((settings["extras"] as? [String: Any])?["recapQuestions"] as? Bool == false)
    }

    /// Eski sürümde kaydedilmiş ayarlar (yeni alanlar yok) açılabilmeli.
    @Test func decodesLegacySettings() throws {
        let legacy = #"{"durationMin":25,"level":"kpss","tone":"sinav","hostA":{"name":"Ayşe","voice":"Leda"},"hostB":{"name":"Can","voice":"Puck"}}"#
        let settings = try JSONDecoder().decode(PodcastSettings.self, from: Data(legacy.utf8))
        #expect(settings.durationMin == 25)
        #expect(settings.level == .kpss)
        #expect(settings.hostA.name == "Ayşe")
        #expect(settings.format == .sohbet)
        #expect(settings.extras.examples == true)
        #expect(settings.customInstructions == nil)
    }
}

import SwiftUI

/// Ekran Büyütme (iPhone 15'te 320 pt) ve büyük erişilebilirlik yazı boyutunda oynatıcı kontrolleri taşmamalı.
@MainActor
struct LayoutTests {
    @Test(arguments: [DynamicTypeSize.large, .xxxLarge, .accessibility3, .accessibility5])
    func playerControlsFitNarrowScreens(size: DynamicTypeSize) {
        let player = PlayerController()
        for width in [320.0, 375.0, 393.0] {
            let view = PlayerControls(ask: {})
                .environment(player)
                .dynamicTypeSize(size)
            let host = UIHostingController(rootView: view)
            let fitted = host.sizeThatFits(in: CGSize(width: width, height: 2000))
            #expect(fitted.width <= width + 0.5, "\(size) @ \(width)pt: \(fitted.width)")
        }
    }
}

@MainActor
struct LayoutMeasurementSanityTests {
    /// Ölçüm yönteminin taşmayı gerçekten yakaladığını kanıtlar (eski, sabit genişlikli satır deseni).
    @Test func detectsOverflowingRow() {
        let overflowing = HStack {
            Text("1×").frame(width: 52)
            Spacer()
            Image(systemName: "gobackward.15").font(.title2).padding(30)
            Spacer()
            Circle().frame(width: 64, height: 64).padding(20)
            Spacer()
            Image(systemName: "goforward.15").font(.title2).padding(30)
            Spacer()
            Text("Sor").frame(width: 52)
        }
        .padding(.horizontal, 20)
        .dynamicTypeSize(.accessibility5)
        let fitted = UIHostingController(rootView: overflowing).sizeThatFits(in: CGSize(width: 320, height: 2000))
        #expect(fitted.width > 320)
    }
}

struct SpacedRepetitionTests {
    @Test func intervalsGrowWithGoodAnswers() {
        var ease = 2.5, interval = 0, reps = 0
        var intervals: [Int] = []
        for _ in 0..<4 {
            let r = SpacedRepetition.next(ease: ease, interval: interval, repetitions: reps, grade: ReviewGrade.good.rawValue)
            (ease, interval, reps) = (r.ease, r.interval, r.repetitions)
            intervals.append(interval)
        }
        #expect(intervals[0] == 1)
        #expect(intervals[1] == 3)
        #expect(intervals[2] > intervals[1])
        #expect(intervals[3] > intervals[2])
    }

    @Test func againResetsAndLowersEase() {
        let r = SpacedRepetition.next(ease: 2.5, interval: 20, repetitions: 5, grade: ReviewGrade.again.rawValue)
        #expect(r.interval == 1)
        #expect(r.repetitions == 0)
        #expect(r.ease < 2.5)
        #expect(r.ease >= 1.3)
    }

    @Test func dueIsInTheFuture() {
        let now = Date()
        let r = SpacedRepetition.next(ease: 2.5, interval: 0, repetitions: 0, grade: ReviewGrade.easy.rawValue, now: now)
        #expect(r.due > now)
    }
}

struct ConceptLayoutTests {
    private let concepts = [
        Concept(name: "Kornea", definition: "", related: ["Lens", "Yok"], sourcePage: 1),
        Concept(name: "Lens", definition: "", related: ["Kornea", "Retina"], sourcePage: 2),
        Concept(name: "Retina", definition: "", related: [], sourcePage: 3),
    ]

    @Test func edgesAreUniqueAndKnown() {
        let edges = ConceptLayout.edges(concepts)
        #expect(edges.count == 2)   // Kornea–Lens (bir kez), Lens–Retina; "Yok" listede değil
    }

    @Test func layoutStaysInsideCanvas() {
        let size = CGSize(width: 760, height: 760)
        let layout = ConceptLayout.compute(concepts, in: size)
        #expect(layout.count == 3)
        for point in layout.values {
            #expect(point.x >= 0 && point.x <= size.width && point.y >= 0 && point.y <= size.height)
        }
    }

    @Test func firstMentionIsCaseInsensitiveTurkish() {
        let turns = [TimedTurn(id: 0, chapterIndex: 0, speaker: .a, text: "Giriş", sourcePage: nil, start: 0, end: 2),
                     TimedTurn(id: 1, chapterIndex: 0, speaker: .b, text: "İRİS ve kornea", sourcePage: nil, start: 2, end: 5)]
        let timeline = Timeline(chapters: [], turns: turns, duration: 5)
        #expect(ConceptLayout.firstMention(of: "iris", in: timeline) == 2)
        #expect(ConceptLayout.firstMention(of: "Kornea", in: timeline) == 2)
        #expect(ConceptLayout.firstMention(of: "lens", in: timeline) == nil)
    }
}

struct ConceptDuplicateTests {
    /// Model aynı adlı kavramı iki kez döndürürse harita çökmemeli (Dictionary(uniqueKeysWithValues:) çöküyordu).
    @Test func duplicateNamesDoNotCrash() {
        let concepts = [
            Concept(name: "Entropi", definition: "a", related: ["Isı"], sourcePage: nil),
            Concept(name: "Entropi", definition: "b", related: [], sourcePage: nil),
            Concept(name: "Isı", definition: "c", related: ["Entropi"], sourcePage: nil),
        ]
        #expect(ConceptLayout.unique(concepts).map(\.name) == ["Entropi", "Isı"])
        #expect(ConceptLayout.compute(concepts, in: CGSize(width: 500, height: 500)).count == 2)
    }
}

struct ScriptModelSelectionTests {
    @Test func legacySettingsAndNewSelectionPersist() throws {
        let old = try JSONDecoder().decode(PodcastSettings.self, from: Data("{}".utf8))
        #expect(old.scriptAI == nil)
        var settings = old
        settings.scriptAI = ScriptAISettings(provider: "claude", model: "claude-opus-5-5", effort: "high")
        let restored = try JSONDecoder().decode(PodcastSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.scriptAI == settings.scriptAI)
    }

    @Test func changingProviderResetsEffortAndUnavailableSavedSelectionIsRejected() {
        let catalog = ScriptModelCatalog(providers: [], models: [
            .init(id: "claude-fable-5-1", provider: "claude", title: "Fable", detail: "", efforts: ["auto", "max"]),
            .init(id: "claude-sonnet-5-5", provider: "claude", title: "Sonnet", detail: "", efforts: ["auto", "low", "high"])
        ], defaultSelection: .init(provider: "claude", model: "claude-fable-5-1"))
        let choice = catalog.selection(provider: "claude", modelID: "claude-sonnet-5-5")
        #expect(choice?.effort == "auto")
        #expect(catalog.accepts(choice))
        let invalidEffort = catalog.accepts(.init(provider: "claude", model: "claude-sonnet-5-5", effort: "max"))
        let invalidProvider = catalog.accepts(.init(provider: "baska", model: "claude-fable-5-1"))
        #expect(invalidEffort == false)
        #expect(invalidProvider == false)
        #expect(catalog.selection(provider: "baska") == nil)
        // Vekildeki hesapların sağlayıcıları (Gemini, Codex…) Soru Çöz'deki listeyle aynı biçimde kabul edilir; tanınmayan sağlayıcı
        // listeye girmez ve varsayılan seçim öyle bir modelse listedeki ilk modele çekilir.
        let mixed = ScriptModelCatalog(providers: [.init(id: "claude", title: "Claude"), .init(id: "baska", title: "Başka"), .init(id: "gemini", title: "Gemini")], models: [
            .init(id: "x-1", provider: "baska", title: "X", detail: "", efforts: ["auto"]),
            .init(id: "gemini-3-flash-preview", provider: "gemini", title: "Gemini", detail: "", efforts: ["auto"]),
            .init(id: "claude-opus-5-5", provider: "claude", title: "Opus", detail: "", efforts: ["auto"])
        ], defaultSelection: .init(provider: "baska", model: "x-1"))
        #expect(mixed.models.map(\.provider) == ["gemini", "claude"] && mixed.providers.map(\.id) == ["claude", "gemini"])
        #expect(mixed.defaultSelection == ScriptAISettings(provider: "gemini", model: "gemini-3-flash-preview"))
        #expect(mixed.selection(provider: "baska") == nil)
        #expect(mixed.selection(provider: "gemini") == ScriptAISettings(provider: "gemini", model: "gemini-3-flash-preview"))
        #expect(mixed.accepts(.init(provider: "gemini", model: "gemini-3-flash-preview")))
    }
}

@Suite struct SpeechQuotaTests {
    @Test func dailyQuotaPausesInsteadOfWaitingPastJobExpiry() {
        let daily = APIError(status: 429, code: "rate_limited", message: "Kota", retryAfter: 15678).needsLongQuotaPause
        let short = APIError(status: 429, code: "rate_limited", message: "Kota", retryAfter: 300).needsLongQuotaPause
        let other = APIError(status: 502, code: "upstream_error", message: "Hata", retryAfter: 15678).needsLongQuotaPause
        #expect(daily == true)
        #expect(short == false)
        #expect(other == false)
    }
}

@MainActor
struct DeviceSpeechTests {
    @Test func producesRealTurkishPCM() async throws {
        let clip = try await DeviceSpeech.scene(turns: [.init(speaker: .a, text: "Merhaba. Hücre canlıların temel yapı birimidir.", style: "", sourcePage: nil)], settings: PodcastSettings())
        #expect(clip.sampleRate == 48_000)
        #expect(clip.duration > 1)
        #expect(clip.samples.contains { abs(Int($0)) > 100 })
        let decoded = try WAV.parse(WAV.encode(clip))
        #expect(decoded.samples == clip.samples)
    }
    @Test func cancelledSpeechStopsAndOldTokenDoesNotBlockResume() async throws {
        let task = Task { try await DeviceSpeech.scene(turns: [.init(speaker: .a, text: String(repeating: "Biyoloji dersine devam ediyoruz. ", count: 100), style: "", sourcePage: nil)], settings: PodcastSettings()) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do { _ = try await task.value; Issue.record("İptal edilen seslendirme tamamlandı") }
        catch is CancellationError {} catch { Issue.record("Beklenmeyen hata: \(error)") }
        let episode = Episode(script: .init(title: "Test", summary: "", keyPoints: [], chapters: [], sourceNotes: ""), settings: PodcastSettings(), sourceNames: [], jobToken: "expired")
        episode.jobToken = nil
        episode.jobTokenExpiresAt = .distantPast
        #expect(episode.canResume)
        #expect(EpisodeFiles.deviceSceneURL(episode: episode.id, index: 0) != EpisodeFiles.sceneURL(episode: episode.id, index: 0))
    }
}

@MainActor
struct DistinctDeviceVoiceTests {
    @Test func neverSubstitutesFemaleVoiceForMissingMale() throws {
        for speaker in [Speaker.a, .b] {
            let gender: AVSpeechSynthesisVoiceGender = speaker == .a ? .female : .male
            let available = DeviceSpeech.voices().filter { $0.gender == gender }
            if let selected = try? DeviceSpeech.selectedVoice(speaker: speaker, language: .tr) {
                #expect(selected.gender == gender)
                #expect(selected.identifier == available.first?.identifier)
            } else {
                #expect(available.isEmpty)
            }
        }
    }
}

struct SpeechProviderPersistenceTests {
    @Test func newEpisodesUseChirpAndOldEpisodesKeepApple() throws {
        #expect(PodcastSettings().usesChirp)
        let old = try JSONDecoder().decode(PodcastSettings.self, from: Data("{}".utf8))
        #expect(old.speechProvider == "apple")
        for provider in SpeechEngine.allCases.map(\.rawValue) {
            let data = try JSONEncoder().encode(PodcastSettings(speechProvider: provider))
            #expect(try JSONDecoder().decode(PodcastSettings.self, from: data).speechProvider == provider)
        }
    }
}

struct AudioEditorTests {
    @Test func replacesMiddleSceneAndShiftsTimeline() async throws {
        let dir = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func tone(_ s: Double) -> [Int16] { (0..<Int(s * 24_000)).map { Int16(8000 * sin(2 * .pi * 220 * Double($0) / 24_000)) } }
        func scene(_ name: String, _ seconds: Double) throws -> URL {
            let url = dir.appending(path: name)
            try WAV.encode(PCMClip(samples: tone(seconds), sampleRate: 24_000)).write(to: url)
            return url
        }
        let t = { (text: String) in ScriptTurn(speaker: .a, text: text, style: "", sourcePage: nil) }
        let script = PodcastScript(title: "T", summary: "", keyPoints: [], chapters: [
            ScriptChapter(title: "Bir", scenes: [ScriptScene(turns: [t("a")]), ScriptScene(turns: [t("b")])]),
            ScriptChapter(title: "İki", scenes: [ScriptScene(turns: [t("c")])]),
        ], sourceNotes: "")
        let inputs = [
            AudioStitcher.SceneInput(url: try scene("0.wav", 2), chapterIndex: 0, turns: [t("a")]),
            AudioStitcher.SceneInput(url: try scene("1.wav", 2), chapterIndex: 0, turns: [t("b")]),
            AudioStitcher.SceneInput(url: try scene("2.wav", 2), chapterIndex: 1, turns: [t("c")]),
        ]
        let output = dir.appending(path: "podcast.m4a")
        let timeline = try await AudioStitcher.stitch(scenes: inputs, chapterTitles: ["Bir", "İki"], output: output, design: false)

        let newClip = PCMClip(samples: tone(5), sampleRate: 24_000)   // 2 sn → 5 sn
        let edited = try await AudioEditor.replaceScene(audio: output, timeline: timeline, script: script, sceneIndex: 1,
                                                        newTurns: [t("yeni b")], newClip: newClip)
        #expect(edited.turns.count == 3)
        #expect(edited.turns[1].text == "yeni b")
        #expect(abs(edited.duration - (timeline.duration + 3)) < 0.05)
        #expect(abs(edited.turns[2].start - (timeline.turns[2].start + 3)) < 0.05)
        #expect(abs(edited.chapters[1].start - (timeline.chapters[1].start + 3)) < 0.05)
        #expect(edited.turns[0].start == timeline.turns[0].start)
        let file = try AVAudioFile(forReading: output)
        #expect(abs(Double(file.length) / file.fileFormat.sampleRate - edited.duration) < 0.2)
        #expect(AudioEditor.sceneIndex(forTurn: 2, script: script) == 2)
    }
}

struct VoiceGradeTests {
    @Test func parsesSpokenGrades() {
        #expect(VoiceReviewView.grade(from: "bilemedim") == .again)
        #expect(VoiceReviewView.grade(from: "hmm bilmiyorum") == .again)
        #expect(VoiceReviewView.grade(from: "biraz zor") == .hard)
        #expect(VoiceReviewView.grade(from: "kolay") == .easy)
        #expect(VoiceReviewView.grade(from: "bildim") == .good)
        #expect(VoiceReviewView.grade(from: "") == nil)
    }
}

@MainActor
struct StreakTests {
    @Test func countsConsecutiveDays() {
        func day(_ offset: Int, _ seconds: Double) -> ListeningDay {
            let d = ListeningDay(day: ListeningDay.key(for: Calendar.current.date(byAdding: .day, value: -offset, to: .now)!))
            d.seconds = seconds
            return d
        }
        #expect(StatsView.streak([day(0, 120), day(1, 300), day(2, 90), day(4, 600)]) == 3)
        // Bugün henüz dinlenmediyse dünden say.
        #expect(StatsView.streak([day(1, 120), day(2, 120)]) == 2)
        // 1 dakikadan az dinleme seriyi bozar.
        #expect(StatsView.streak([day(0, 30), day(1, 120)]) == 1)
        #expect(StatsView.streak([]) == 0)
    }
}


struct SoundDesignTests {
    /// #15: eski RMS eşitlemesinin yerini −19 LUFS mastering aldı; sessiz ve gür sahne aynı yüksekliğe gelir.
    @Test func mastersQuietAndLoudClipsToSameLoudness() throws {
        let quiet = PCMClip(samples: (0..<48_000).map { Int16(1500 * sin(Double($0) * 0.26)) }, sampleRate: 24_000)
        let loud = PCMClip(samples: (0..<48_000).map { Int16(20_000 * sin(Double($0) * 0.26)) }, sampleRate: 24_000)
        let a = try #require(Mastering.loudness(Mastering.master(quiet)))
        let b = try #require(Mastering.loudness(Mastering.master(loud)))
        #expect(abs(a - Mastering.targetLUFS) < 0.5)
        #expect(abs(b - Mastering.targetLUFS) < 0.5)
        #expect(Mastering.samplePeakDBFS(Mastering.master(loud)) <= Mastering.ceilingDBFS + 0.01)
    }

    @Test func designedStitchShiftsTimelineByIntroLead() async throws {
        let dir = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "a.wav")
        try WAV.encode(PCMClip(samples: (0..<48_000).map { Int16(8000 * sin(Double($0) * 0.06)) }, sampleRate: 24_000)).write(to: url)
        let t = ScriptTurn(speaker: .a, text: "Merhaba", style: "", sourcePage: nil)
        let timeline = try await AudioStitcher.stitch(scenes: [.init(url: url, chapterIndex: 0, turns: [t])], chapterTitles: ["Bir"],
                                                      output: dir.appending(path: "o.m4a"), design: true, identity: .sade)
        let lead = SoundIdentity.sade.introLead
        #expect(abs(timeline.turns[0].start - lead) < 0.01)
        #expect(abs(timeline.chapters[0].start - lead) < 0.01)
        let outro = try #require(SoundIdentity.sade.outro(sampleRate: 24_000)).duration
        #expect(abs(timeline.duration - (lead + 2 + outro)) < 0.05)
        #expect(timeline.sceneStarts == [timeline.turns[0].start])
    }
}

struct ChapterRemovalTests {
    @Test func removesMiddleChapterAndReindexes() async throws {
        let dir = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func scene(_ name: String, _ seconds: Double) throws -> URL {
            let url = dir.appending(path: name)
            try WAV.encode(PCMClip(samples: (0..<Int(seconds * 24_000)).map { Int16(8000 * sin(Double($0) * 0.06)) }, sampleRate: 24_000)).write(to: url)
            return url
        }
        let t = { (text: String) in ScriptTurn(speaker: .a, text: text, style: "", sourcePage: nil) }
        let output = dir.appending(path: "p.m4a")
        let timeline = try await AudioStitcher.stitch(scenes: [
            .init(url: try scene("a.wav", 2), chapterIndex: 0, turns: [t("a")]),
            .init(url: try scene("b.wav", 3), chapterIndex: 1, turns: [t("b")]),
            .init(url: try scene("c.wav", 2), chapterIndex: 2, turns: [t("c")]),
        ], chapterTitles: ["Bir", "İki", "Üç"], output: output, design: false)

        let result = try await AudioEditor.removeChapter(audio: output, timeline: timeline, chapterIndex: 1)
        let removed = timeline.chapters[2].start - timeline.chapters[1].start
        #expect(result.timeline.chapters.map(\.title) == ["Bir", "Üç"])
        #expect(result.timeline.chapters.map(\.id) == [0, 1])
        #expect(result.timeline.turns.map(\.text) == ["a", "c"])
        #expect(result.timeline.turns[1].chapterIndex == 1)
        #expect(abs(result.timeline.turns[1].start - (timeline.turns[2].start - removed)) < 0.01)
        #expect(abs(result.timeline.duration - (timeline.duration - removed)) < 0.01)
        let file = try AVAudioFile(forReading: output)
        #expect(abs(Double(file.length) / file.fileFormat.sampleRate - result.timeline.duration) < 0.2)
    }
}

import PDFKit

@MainActor
struct PlanToolsTests {
    @Test func bookSplitterUsesOutline() throws {
        let doc = PDFDocument()
        for i in 0..<10 { doc.insert(PDFPage(), at: i) }
        let root = PDFOutline()
        for (i, page) in [(0, 0), (1, 4), (2, 7)] {
            let item = PDFOutline()
            item.label = "Bölüm \(i + 1)"
            item.destination = PDFDestination(page: doc.page(at: page)!, at: .zero)
            root.insertChild(item, at: i)
        }
        doc.outlineRoot = root
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        #expect(doc.write(to: url))
        defer { try? FileManager.default.removeItem(at: url) }
        let parts = BookSplitter.chapters(of: url)
        #expect(parts.map(\.title) == ["Bölüm 1", "Bölüm 2", "Bölüm 3"])
        #expect(parts.map(\.range) == [1...4, 5...7, 8...10])
    }

    @Test func ankiFileFormat() throws {
        let card = ReviewCard(episodeID: UUID(), episodeTitle: "Hücre Biyolojisi", kind: .flashcard,
                              front: "Mitokondri\tnedir?", back: "Enerji\nüretir", sourcePage: nil)
        let text = try String(contentsOf: AnkiExport.file(cards: [card]), encoding: .utf8)
        let lines = text.split(separator: "\n")
        #expect(lines.first == "#separator:tab")
        #expect(lines.last == "Mitokondri nedir?\tEnerji<br>üretir\tDersPodcast Hücre_Biyolojisi")
    }

    @Test func planPutsExamPracticeAtTheEnd() {
        let plan = StudyPlan(examName: "KPSS", examDate: Calendar.current.date(byAdding: .day, value: 12, to: .now)!, dailyMinutes: 30)
        let days = StudyPlanner.days(plan: plan, episodes: [], dueCards: 5)
        #expect(days.count == 12)
        #expect(days.first?.items.contains("Tekrar: 5 kart") == true)
        #expect(days.last?.items.first == "Sınav simülasyonu (karışık, süreli)")
    }

    @Test func citationTimeFindsQuoteInTranscript() throws {
        let t = { (text: String) in ScriptTurn(speaker: .a, text: text, style: "", sourcePage: nil) }
        let script = PodcastScript(title: "Ozmoz", summary: "", keyPoints: [],
                                   chapters: [ScriptChapter(title: "Giriş", scenes: [ScriptScene(turns: [t("Giriş")])])], sourceNotes: "")
        let episode = Episode(script: script, settings: PodcastSettings(), sourceNames: [], jobToken: "")
        episode.timeline = Timeline(chapters: [TimedChapter(id: 0, title: "Giriş", start: 0)], turns: [
            TimedTurn(id: 0, chapterIndex: 0, speaker: .a, text: "Bugün hücreyi konuşacağız", sourcePage: nil, start: 0, end: 5),
            TimedTurn(id: 1, chapterIndex: 0, speaker: .b, text: "Osmotik basınç suyun yarı geçirgen zardan geçişini belirler", sourcePage: nil, start: 42, end: 50),
        ], duration: 50)
        let citation = LibraryCitation(episodeId: episode.id, chapterIndex: 0, quote: "osmotik basınç, yarı geçirgen zar")
        #expect(LibraryAskView.time(for: citation, in: episode) == 42)
    }
}

struct QualityModeTests {
    @Test func appliesBestLearningAndListeningSettings() {
        var base = PodcastSettings()
        base.depth = .ozet
        base.extras.recapQuestions = false
        base.extras.examples = false
        base.durationMin = 15
        let max = QualityMode.apply(to: base)
        #expect(max.depth == .derin)
        #expect(max.extras.recapQuestions && max.extras.examples && max.extras.analogies && max.extras.examTips && max.extras.commonMistakes)
        #expect(max.engine == base.engine)
        #expect(max.durationMin == 15)   // kullanıcının süre seçimi korunur
        #expect(QualityMode.bitrate(sampleRate: 24_000) == 64_000)
    }
}

@MainActor
struct DeckPDFTests {
    @Test func rendersEverySlideKindToPDF() throws {
        let slides = [
            DeckSlide(kind: "title", title: "Fotosentez", chapterIndex: nil, sourcePages: [], notes: "Giriş"),
            DeckSlide(kind: "bullets", title: "Temel kavramlar", chapterIndex: 0, sourcePages: [1], notes: "",
                      bullets: ["Kloroplast", "Klorofil ışığı soğurur"]),
            DeckSlide(kind: "table", title: "Evreler", chapterIndex: 0, sourcePages: [2], notes: "",
                      table: DeckTable(headers: ["Evre", "Yer"], rows: [["Işığa bağımlı", "Tilakoit"], ["Calvin", "Stroma"]])),
            DeckSlide(kind: "chart", title: "Işık şiddeti", chapterIndex: 1, sourcePages: [3], notes: "",
                      chart: DeckChart(type: "bar", title: "Hız", unit: "%", labels: ["Az", "Orta", "Çok"], series: [.init(name: "Hız", values: [20, 60, 80])])),
            DeckSlide(kind: "chart", title: "Dağılım", chapterIndex: 1, sourcePages: [], notes: "",
                      chart: DeckChart(type: "pie", title: "Pay", unit: nil, labels: ["A", "B"], series: [.init(name: "P", values: [30, 70])])),
            DeckSlide(kind: "diagram", title: "Süreç", chapterIndex: 1, sourcePages: [], notes: "",
                      diagram: DeckDiagram(layout: "cycle", nodes: [.init(title: "CO2", detail: "bağlanır"), .init(title: "Şeker", detail: ""), .init(title: "RuBP", detail: "")])),
            DeckSlide(kind: "image", title: "Kloroplast", chapterIndex: 0, sourcePages: [], notes: "", imagePrompt: "chloroplast"),
            DeckSlide(kind: "quote", title: "Özet", chapterIndex: nil, sourcePages: [], notes: "", quote: "Işık enerjisi kimyasal enerjiye dönüşür"),
            DeckSlide(kind: "summary", title: "Akılda kalsın", chapterIndex: nil, sourcePages: [], notes: "", bullets: ["Stroma", "Tilakoit"]),
            DeckSlide(kind: "section", title: "Calvin döngüsü", chapterIndex: 1, sourcePages: [], notes: "", subtitle: "Karanlık evre"),
            DeckSlide(kind: "stat", title: "Verim", chapterIndex: 1, sourcePages: [4], notes: "", stat: DeckStat(value: "%3", label: "Enerji verimi", context: "Güneş ışığının")),
            DeckSlide(kind: "agenda", title: "Plan", chapterIndex: nil, sourcePages: [], notes: "", bullets: ["Işık", "Calvin"]),
            DeckSlide(kind: "timeline", title: "Tarihçe", chapterIndex: nil, sourcePages: [], notes: "",
                      timeline: [.init(label: "1779", title: "Ingenhousz", detail: "Işık"), .init(label: "1950", title: "Calvin", detail: "Döngü")]),
            DeckSlide(kind: "figure", title: "Şekil 1", chapterIndex: 0, sourcePages: [2], notes: "", figureId: "1", caption: "Kloroplast kesiti"),
            DeckSlide(kind: "twoColumn", title: "Karşılaştırma", chapterIndex: 0, sourcePages: [], notes: "", bullets: ["Tilakoit", "Stroma"], imagePrompt: "leaf"),
        ]
        let deck = Deck(title: "Fotosentez", subtitle: "Biyoloji", slides: slides)
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let figure = SourceFigure(id: "1", kind: "diagram", caption: "Kloroplast kesiti", page: 2, documentName: "ders.pdf", table: nil)
        try DeckPDF.render(deck: deck, images: Array(repeating: nil, count: slides.count),
                           figures: slides.map { $0.figureId == "1" ? figure : nil },
                           chapterTitles: slides.map { $0.chapterIndex.map { "Bölüm \($0 + 1)" } }, to: url)
        let pdf = try #require(PDFDocument(url: url))
        #expect(pdf.pageCount == slides.count)
        // Metin vektörel (raster değil). Not: SF yazı tipinde "i" harfinin PDF metin eşlemesi bozuk çıkıyor; "i" içermeyen kelimeyle kontrol.
        #expect(pdf.page(at: 2)?.string?.contains("Evreler") == true)
    }
}

@MainActor
struct DeckReconcileTests {
    @Test func reconcilesFiguresWithDeck() {
        let table = DeckTable(headers: ["Evre", "Yer"], rows: [["Calvin", "Stroma"]])
        let figures = [SourceFigure(id: "1", kind: "table", caption: "Evreler", page: 3, documentName: "a.pdf", table: table),
                       SourceFigure(id: "2", kind: "photo", caption: "Yaprak", page: 4, documentName: "a.pdf", table: nil)]
        let deck = Deck(title: "T", subtitle: "", slides: [
            DeckSlide(kind: "figure", title: "Tablo", chapterIndex: 0, sourcePages: [], notes: "", figureId: "1"),
            DeckSlide(kind: "figure", title: "Foto", chapterIndex: 0, sourcePages: [], notes: "", figureId: "2"),
            DeckSlide(kind: "figure", title: "Uydurma", chapterIndex: 0, sourcePages: [], notes: "", figureId: "9"),
            DeckSlide(kind: "figure", title: "Uydurma maddeli", chapterIndex: 0, sourcePages: [], notes: "", bullets: ["a"], figureId: "8"),
        ])
        let result = DeckAssets.reconcile(deck, figures: figures)
        #expect(result.slides.map(\.kind) == ["table", "figure", "bullets"])
        // Kullanılmayan şekil özetten önce kendi slaytına eklenir.
        let extra = SourceFigure(id: "3", kind: "diagram", caption: "Görsel 1.5.11: Gözün anatomik yapısı", page: 1, documentName: "foto", table: nil)
        let withSummary = Deck(title: "T", subtitle: "", slides: deck.slides + [DeckSlide(kind: "summary", title: "Özet", chapterIndex: nil, sourcePages: [], notes: "", bullets: ["x"])])
        let full = DeckAssets.reconcile(withSummary, figures: figures + [extra])
        #expect(full.slides.map(\.kind) == ["table", "figure", "bullets", "figure", "summary"])
        #expect(full.slides[3].figureId == "3" && full.slides[3].title.hasPrefix("Görsel 1.5.11"))
        #expect(result.slides[0].table == table && result.slides[0].figureId == nil && result.slides[0].sourcePages == [3])
        #expect(result.slides[1].figureId == "2")
        // Şekil slaytının maddeleri nota taşınır (fotoğraf büyük kalsın).
        let withBullets = Deck(title: "T", subtitle: "", slides: [DeckSlide(kind: "figure", title: "Foto", chapterIndex: 0, sourcePages: [], notes: "Not", bullets: ["a", "b"], figureId: "2")])
        let moved = DeckAssets.reconcile(withBullets, figures: figures).slides[0]
        #expect(moved.bullets == nil && moved.notes == "Not\n• a\n• b")
        #expect(result.slides[2].figureId == nil)
    }

    @Test func detectsTextInGeneratedImages() async {
        func render(_ draw: (CGContext) -> Void) -> Data {
            UIGraphicsImageRenderer(size: CGSize(width: 600, height: 400)).image { ctx in
                UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 400)); draw(ctx.cgContext)
            }.pngData()!
        }
        let labeled = render { _ in
            ("Optical axis" as NSString).draw(at: CGPoint(x: 40, y: 150), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 48), .foregroundColor: UIColor.black])
        }
        let plain = render { cg in cg.setFillColor(UIColor.systemBlue.cgColor); cg.fillEllipse(in: CGRect(x: 150, y: 50, width: 300, height: 300)) }
        #expect(await DeckAssets.containsText(labeled))
        #expect(await !DeckAssets.containsText(plain))
    }

    @Test func imagePromptsFollowDensity() {
        let deck = Deck(title: "Göz", subtitle: "", slides: [])
        let bullets = DeckSlide(kind: "bullets", title: "İris", chapterIndex: 0, sourcePages: [], notes: "", bullets: ["Işığı ayarlar"])
        let image = DeckSlide(kind: "image", title: "Kesit", chapterIndex: 0, sourcePages: [], notes: "", imagePrompt: "eye cross-section")
        let figure = DeckSlide(kind: "bullets", title: "Şekil", chapterIndex: 0, sourcePages: [], notes: "", bullets: ["a"], figureId: "1")
        #expect(DeckAssets.imagePrompt(for: bullets, deck: deck, level: 0) == nil)
        #expect(DeckAssets.imagePrompt(for: bullets, deck: deck, level: 1) == nil)
        #expect(DeckAssets.imagePrompt(for: bullets, deck: deck, level: 2)?.contains("İris") == true)
        #expect(DeckAssets.imagePrompt(for: image, deck: deck, level: 1)?.hasSuffix("Sahne: eye cross-section") == true)
        // Deste başlığı istemde geçmez (model onu resme yazıyordu); yazısızlık kuralı her istemde.
        let prompt = DeckAssets.imagePrompt(for: bullets, deck: deck, level: 2) ?? ""
        #expect(!prompt.contains("Göz.") && prompt.contains("no text") && prompt.count <= 800)
        #expect(DeckAssets.wrapPrompt("x", strict: true).contains("SIFIR yazı"))
        #expect(DeckAssets.imagePrompt(for: figure, deck: deck, level: 2) == nil)
    }
}

@MainActor
struct FigureExtractorTests {
    @Test func normalizesModelBoxes() {
        let r = FigureExtractor.normalizedRect([100, 200, 500, 800])   // ymin, xmin, ymax, xmax
        #expect(abs(r.minX - 0.18) < 0.001 && abs(r.minY - 0.08) < 0.001)
        #expect(abs(r.maxX - 0.82) < 0.001 && abs(r.maxY - 0.52) < 0.001)
        let clamped = FigureExtractor.normalizedRect([-50, -50, 1200, 1200])
        #expect(clamped == CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Sayfanın sağ alt çeyreğine kırmızı kare çizilmiş PDF: o bölge çizilince görüntü kırmızı olmalı, sol üst beyaz.
    @Test func rendersRegionFromVectorPDF() async throws {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let pageRect = CGRect(x: 0, y: 0, width: 600, height: 800)
        let data = UIGraphicsPDFRenderer(bounds: pageRect).pdfData { ctx in
            ctx.beginPage()
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 300, y: 400, width: 300, height: 400))   // UIKit: sol üst köken → sağ alt çeyrek
        }
        try data.write(to: url)
        // Sağ alt çeyrek (pay olmadan): x 0.5–1, y 0.5–1
        let red = try #require(await FigureExtractor.renderRegion(url: url, pageIndex: 0, box: CGRect(x: 0.55, y: 0.55, width: 0.4, height: 0.4), enhance: false))
        let white = try #require(await FigureExtractor.renderRegion(url: url, pageIndex: 0, box: CGRect(x: 0.05, y: 0.05, width: 0.4, height: 0.4), enhance: false))
        #expect(max(red.size.width, red.size.height) >= 1700)   // yüksek çözünürlük
        func center(_ image: UIImage) -> (r: CGFloat, g: CGFloat) {
            let cg = image.cgImage!
            var pixel = [UInt8](repeating: 0, count: 4)
            let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(cg, in: CGRect(x: -CGFloat(cg.width) / 2, y: -CGFloat(cg.height) / 2, width: CGFloat(cg.width), height: CGFloat(cg.height)))
            return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255)
        }
        let r = center(red), w = center(white)
        #expect(r.r > 0.8 && r.g < 0.2)
        #expect(w.r > 0.9 && w.g > 0.9)
    }

    /// mediaBox kökeni (100,100) ve 90° döndürülmüş sayfa: kutular görünür sayfaya göre doğru kırpılmalı.
    @Test func handlesOffsetAndRotatedPages() async throws {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        var box = CGRect(x: 100, y: 100, width: 400, height: 200)
        let ctx = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        ctx.beginPDFPage(nil)
        ctx.setFillColor(UIColor.red.cgColor)
        ctx.fill(CGRect(x: 100, y: 100, width: 200, height: 200))   // sol yarı kırmızı
        ctx.endPDFPage()
        ctx.closePDF()
        func center(_ image: UIImage?) -> CGFloat {
            guard let cg = image?.cgImage else { return -1 }
            var pixel = [UInt8](repeating: 0, count: 4)
            let c = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.draw(cg, in: CGRect(x: -CGFloat(cg.width) / 2, y: -CGFloat(cg.height) / 2, width: CGFloat(cg.width), height: CGFloat(cg.height)))
            return CGFloat(pixel[1]) / 255   // yeşil: kırmızıda ~0, beyazda ~1
        }
        let left = CGRect(x: 0.05, y: 0.1, width: 0.35, height: 0.8), right = CGRect(x: 0.6, y: 0.1, width: 0.35, height: 0.8)
        #expect(center(await FigureExtractor.renderRegion(url: url, pageIndex: 0, box: left, enhance: false)) < 0.2)
        #expect(center(await FigureExtractor.renderRegion(url: url, pageIndex: 0, box: right, enhance: false)) > 0.8)

        // 90° saat yönünde döndürülünce sol yarı üste gelir.
        let doc = try #require(PDFDocument(url: url))
        doc.page(at: 0)?.rotation = 90
        let rotatedURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: rotatedURL) }
        #expect(doc.write(to: rotatedURL))
        let top = CGRect(x: 0.1, y: 0.05, width: 0.8, height: 0.35), bottom = CGRect(x: 0.1, y: 0.6, width: 0.8, height: 0.35)
        #expect(center(await FigureExtractor.renderRegion(url: rotatedURL, pageIndex: 0, box: top, enhance: false)) < 0.2)
        #expect(center(await FigureExtractor.renderRegion(url: rotatedURL, pageIndex: 0, box: bottom, enhance: false)) > 0.8)
    }
}

@MainActor
struct VisualStudioTests {
    @Test func legacyDeckAndThemeRoundTrip() throws {
        let legacy = Data(#"{"title":"Eski","subtitle":"Korunur","slides":[]}"#.utf8)
        let old = try JSONDecoder().decode(Deck.self, from: legacy)
        #expect(old.palette == .studio && old.imageLevel == nil)
        let deck = StudioPreview.deck
        let restored = try JSONDecoder().decode(Deck.self, from: JSONEncoder().encode(deck))
        #expect(restored == deck && restored.palette == .ocean && restored.illustrationStyle == .cutaway)
    }
    @Test func tablePaginationKeepsEveryCellAndSource() {
        let rows = (1...14).map { ["Satır \($0)", "Değer \($0)"] }
        let slide = DeckSlide(kind: "table", title: "Tablo", chapterIndex: 2, sourcePages: [7], notes: "Kaynak notu", table: DeckTable(headers: ["Ad", "Değer"], rows: rows))
        let result = DeckReadability.prepare(Deck(title: "T", subtitle: "", slides: [slide]))
        #expect(result.slides.count == 4)
        #expect(result.slides.flatMap { $0.table!.rows } == rows)
        #expect(result.slides.allSatisfy { $0.sourcePages == [7] && $0.notes == "Kaynak notu" && $0.chapterIndex == 2 && $0.table!.rows.count <= 4 })
        #expect(DeckReadability.prepare(result) == result)
    }
    @Test func diagramGeometryStaysInsideCanvasAndPreservesRelations() {
        let size = CGSize(width: 1140, height: 420)
        for count in 2...8 {
            for kind in ["steps", "cycle", "hierarchy", "compare"] {
                let layout = DeckDiagramGeometry.make(layout: kind, count: count, size: size)
                #expect(layout.boxes.count == count)
                for box in layout.boxes { #expect(box.minX >= -0.01 && box.minY >= -0.01 && box.maxX <= size.width + 0.01 && box.maxY <= size.height + 0.01) }
                for i in layout.boxes.indices {
                    for j in layout.boxes.indices where j > i { #expect(!layout.boxes[i].intersects(layout.boxes[j])) }
                }
                if kind == "hierarchy" { #expect(layout.edges.count == count - 1 && layout.edges.allSatisfy { $0.0 == 0 }) }
                if kind == "cycle" { #expect(layout.edges.count == count && layout.edges.last?.1 == 0) }
            }
        }
    }
    @Test func imageBudgetPrioritizesActualImageSlidesAndKeepsScene() {
        let bullet = DeckSlide(kind: "bullets", title: "İris", chapterIndex: 0, sourcePages: [], notes: "", bullets: ["Işığı ayarlar"])
        let image = DeckSlide(kind: "image", title: "Kesit", chapterIndex: 0, sourcePages: [], notes: "", imagePrompt: "Mitokondrinin iç zar kıvrımları")
        let deck = Deck(title: "D", subtitle: "", slides: Array(repeating: bullet, count: 14) + [image, image], imageStyle: "isometric", imageLevel: 2)
        let plan = DeckAssets.imagePlan(deck)
        #expect(plan.count == 12 && plan.contains { $0.0 == 14 } && plan.contains { $0.0 == 15 })
        #expect(plan.last!.1.contains("Mitokondrinin") && plan.last!.1.contains("izometrik"))
        #expect(plan.allSatisfy { $0.1.count <= 800 && $0.1.contains("no text") })
    }
    @Test func cancellingImageDoesNotStartRequest() async {
        let task = Task { try await DeckAssets.generateImage(prompt: "İptal", aspect: "16:9", style: .textbook) }
        task.cancel()
        do { _ = try await task.value; Issue.record("İptal edilen görev sonuç üretmemeli") }
        catch { #expect(error is CancellationError) }
    }
    @Test func renderStudioThemesAndSlides() throws {
        let folder = URL.documentsDirectory.appending(path: "StudioQA", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var deck = StudioPreview.deck
        try JSONEncoder().encode(deck).write(to: folder.appending(path: "sample-deck.json"))
        for theme in DeckPalette.allCases {
            deck.theme = theme.rawValue
            let url = folder.appending(path: "studio-\(theme.rawValue).pdf")
            try DeckPDF.render(deck: deck, images: [], to: url)
            let pdf = try #require(PDFDocument(url: url))
            #expect(pdf.pageCount == deck.slides.count)
            for index in deck.slides.indices {
                let page = try #require(pdf.page(at: index))
                #expect(page.bounds(for: .mediaBox).size == CGSize(width: 1280, height: 720))
                #expect(!(page.string ?? "").isEmpty)
            }
        }
        let image = ImageRenderer(content: SlideCanvas(slide: deck.slides[0], deck: deck, index: 0, image: nil).content.frame(width: 1280, height: 720))
        image.scale = 2
        let png = try #require(image.uiImage)
        #expect(png.cgImage?.width == 2560 && png.cgImage?.height == 1440)
        try png.pngData()?.write(to: folder.appending(path: "slide-2x.png"))
    }
}

@MainActor
struct CoachTests {

    @Test func labelMatchingToleratesTurkishAndTypos() {
        #expect(LabelDetector.matches("kornea", expected: "Kornea"))
        #expect(LabelDetector.matches("goz bebegi", expected: "Göz bebeği"))
        #expect(LabelDetector.matches("Sari benek", expected: "Sarı benek"))
        #expect(LabelDetector.matches("retina", expected: "Ağ tabaka (Retina)") == false)   // parantez içi atılır
        #expect(LabelDetector.matches("ag tabaka", expected: "Ağ tabaka (Retina)"))
        #expect(LabelDetector.matches("iris", expected: "Mercek") == false)
        #expect(LabelDetector.isLabel("Kornea") && LabelDetector.isLabel("Optik sinir lifleri"))
        #expect(!LabelDetector.isLabel("Görsel 1.5.11: Gözün anatomik yapısı") && !LabelDetector.isLabel("12"))
    }

    @Test func focusTimerCyclesLongBreakEveryFourth() {
        let t = FocusTimer()
        #expect(t.nextPhase == .focus)
        t.start(.focus)
        #expect(t.isRunning && t.remaining > 24 * 60)
        #expect(t.nextPhase == .shortBreak)
        t.stop()
        #expect(!t.isRunning)
    }
}

@MainActor
struct FigureMapTests {
    @Test func picksNearestPrecedingFigureInChapter() {
        let map = [FigureMapEntry(figureId: "1", chapterIndex: 0, turnIndex: 3, confidence: 0.9),
                   FigureMapEntry(figureId: "2", chapterIndex: 0, turnIndex: 8, confidence: 0.8),
                   FigureMapEntry(figureId: "3", chapterIndex: 1, turnIndex: nil, confidence: 0.7),
                   FigureMapEntry(figureId: "4", chapterIndex: 2, turnIndex: 20, confidence: 0.2)]
        #expect(FigureMapper.figure(for: map, chapter: 0, turn: 5) == "1")
        #expect(FigureMapper.figure(for: map, chapter: 0, turn: 9) == "2")
        #expect(FigureMapper.figure(for: map, chapter: 0, turn: 1) == "1")   // henüz gelmediyse bölümün ilk şekli
        #expect(FigureMapper.figure(for: map, chapter: 1, turn: 12) == "3")
        #expect(FigureMapper.figure(for: map, chapter: 2, turn: 25) == nil)  // düşük güven
    }
}

@MainActor
struct RecapTests {
    @Test func recapSettingsAreShortSingleNarrator() {
        let s = RecapGenerator.settings(from: nil)
        #expect(s.durationMin == 5 && s.format == .tekAnlatici && s.depth == .ozet)
        #expect((s.customInstructions ?? "").count <= PodcastSettings.maxCustomInstructions)
    }

}

struct PronunciationTests {
    @Test func attachesDictionaryAndSplitsWords() {
        let saved = Pronunciations.all
        defer { Pronunciations.all = saved }
        Pronunciations.all = []
        Pronunciations.set("sklera", "sık-le-ra")
        Pronunciations.set("Sklera", "sk-le-ra")   // aynı kelime güncellenir
        #expect(Pronunciations.all.count == 1 && Pronunciations.all[0].to == "sk-le-ra")
        let r = Pronunciations.attach(to: TTSRequest(jobToken: "t", sceneIndex: 0, turns: []))
        #expect(r.replacements?.first?.from == "Sklera")
        #expect(Pronunciations.words(in: "Sert tabaka, yani sklera; sklera gözü korur.") == ["Sert", "tabaka", "yani", "sklera", "gözü", "korur"])
    }
}

struct DeckVideoTests {
    @Test func scheduleFollowsChaptersAndKeepsOrder() {
        func slide(_ kind: String, _ ch: Int?) -> DeckSlide { DeckSlide(kind: kind, title: kind, chapterIndex: ch, sourcePages: [], notes: "") }
        let slides = [slide("title", nil), slide("agenda", nil), slide("bullets", 0), slide("table", 0), slide("bullets", 1), slide("summary", nil)]
        let chapters = [TimedChapter(id: 0, title: "A", start: 10), TimedChapter(id: 1, title: "B", start: 100)]
        let t = DeckVideo.schedule(slides: slides, chapters: chapters, duration: 200)
        #expect(t.count == 6 && t[0] == 0)
        #expect(zip(t, t.dropFirst()).allSatisfy { $1 >= $0 + 3 })      // sıra ve en az 3 sn
        #expect(t[2] == 10 && t[3] == 55 && t[4] == 100)                  // bölüme eşit dağıtım
        #expect(t[5] > 100 && t[5] < 200)                                 // özet sonda
    }
}

@MainActor
struct YouTubeTests {
    /// Sözleşme örneği: isteğe bağlı alanların bir kısmı eksik (thumbnail, translation, keyframes, warnings, captions).
    static let sampleJSON = """
    {
      "state": "done", "progress": 1, "step": "Bitti",
      "result": {
        "video": {"id": "EKGRs8q7HlA", "url": "https://www.youtube.com/watch?v=EKGRs8q7HlA", "title": "Hücre zarı",
                  "channel": "Biyoloji Hocası", "duration": 882, "chapters": [{"title": "Giriş", "start": 0}], "language": null},
        "source": "auto-captions",
        "language": "tr",
        "segments": [{"start": 0.5, "end": 3.2, "text": "Gençler merhaba."}, {"start": 3.2, "end": 6, "text": "Hepiniz hoş geldiniz."}],
        "paragraphs": [{"start": 0.5, "end": 6, "text": "Gençler merhaba. Hepiniz hoş geldiniz."}],
        "chapters": [{"title": "Giriş", "start": 0}, {"title": "Zarın yapısı", "start": 120.5}],
        "notes": {"summary": "Hücre zarı seçici geçirgendir.", "keyPoints": [{"text": "Zar fosfolipitten oluşur", "time": 0.5}],
                  "concepts": [{"name": "Difüzyon", "definition": "Çok yoğundan az yoğuna geçiş", "time": 120.5}],
                  "formulas": [], "questions": [{"question": "Zar neden seçici?", "answer": "Proteinler sayesinde", "time": 0.5}]},
        "translation": null
      }
    }
    """

    @Test func decodesContractSampleWithMissingOptionals() throws {
        let status = try JSONDecoder().decode(YouTubeJobStatus.self, from: Data(Self.sampleJSON.utf8))
        #expect(status.state == .done && status.progress == 1 && status.step == "Bitti" && status.error == nil)
        let t = try #require(status.result)
        #expect(t.video.id == "EKGRs8q7HlA" && t.video.duration == 882 && t.video.thumbnail == nil)
        #expect(t.video.captions.isEmpty && t.video.language == nil && t.video.chapters.count == 1)
        #expect(t.source == "auto-captions" && t.language == "tr")
        #expect(t.segments.count == 2 && t.segments[1].text == "Hepiniz hoş geldiniz.")
        #expect(t.paragraphs.first?.end == 6)
        #expect(t.chapters.map(\.title) == ["Giriş", "Zarın yapısı"] && t.chapters[1].start == 120.5)
        #expect(t.translation == nil && t.keyframes.isEmpty && t.warnings.isEmpty)
        let notes = try #require(t.notes)
        #expect(notes.examTips.isEmpty && notes.formulas.isEmpty && notes.concepts.first?.name == "Difüzyon")
        #expect(notes.questions.first?.answer == "Proteinler sayesinde")
        #expect(VideoTranscript.sourceTitle(t.source) == "Otomatik altyazı")
        #expect(t.plainText() == "## Giriş\nGençler merhaba. Hepiniz hoş geldiniz.")
    }

    @Test func decodesQueuedStatusAndInfoResponses() throws {
        let queued = try JSONDecoder().decode(YouTubeJobStatus.self, from: Data(#"{"state":"queued","progress":0,"step":"Sırada"}"#.utf8))
        #expect(queued.state == .queued && queued.result == nil)
        let odd = try JSONDecoder().decode(YouTubeJobStatus.self, from: Data(#"{"state":"downloading","progress":1.7}"#.utf8))
        #expect(odd.state == .running && odd.progress == 1 && odd.step.isEmpty)
        let playlist = try JSONDecoder().decode(YouTubeInfoResponse.self, from: Data("""
        {"kind":"playlist","playlist":{"id":"PL1","title":"Biyoloji","entries":[{"id":"EKGRs8q7HlA","title":"Ders 1","duration":null,"url":"https://youtu.be/EKGRs8q7HlA"}]}}
        """.utf8))
        #expect(playlist.isPlaylist && playlist.playlist?.entries.first?.duration == nil)
        let video = try JSONDecoder().decode(YouTubeInfoResponse.self, from: Data("""
        {"kind":"video","video":{"id":"EKGRs8q7HlA","url":"u","title":"T","channel":"C","duration":60,"thumbnail":null,"chapters":[],
         "captions":[{"lang":"en","name":"English","auto":true},{"lang":"tr","name":"Türkçe","auto":false}],"language":"tr"}}
        """.utf8))
        #expect(!video.isPlaylist && video.video?.manualCaptions.map(\.lang) == ["tr"])
    }

    @Test func startRequestOmitsUnsetOptionals() throws {
        let request = YouTubeStartRequest(url: "https://youtu.be/EKGRs8q7HlA", mode: .captions, language: nil, translateTo: "tr",
                                          start: 30, end: nil, keyframes: true, notes: false)
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(json["mode"] as? String == "captions" && json["translateTo"] as? String == "tr")
        #expect(json["start"] as? Double == 30 && json["end"] == nil && json["language"] == nil)
        #expect(json["keyframes"] as? Bool == true && json["notes"] as? Bool == false)
    }

    @Test func lessonTranscriptRoundTripStripsImages() throws {
        let container = try ModelContainer(for: VideoLesson.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        var transcript = try #require(try JSONDecoder().decode(YouTubeJobStatus.self, from: Data(Self.sampleJSON.utf8)).result)
        transcript.keyframes = [Keyframe(id: "k1", time: 42, image: Data([0xFF, 0xD8, 0xFF, 0xD9]).base64EncodedString(),
                                         caption: "Zar şeması", text: "fosfolipit")]
        let lesson = VideoLesson(url: "https://youtu.be/EKGRs8q7HlA", info: transcript.video)
        lesson.apply(transcript: transcript)
        context.insert(lesson)
        try context.save()
        let saved = try #require(context.fetch(FetchDescriptor<VideoLesson>()).first)
        #expect(saved.videoID == "EKGRs8q7HlA" && saved.title == "Hücre zarı" && saved.duration == 882)
        #expect(saved.source == "auto-captions" && saved.language == "tr" && saved.episodeIDs.isEmpty && !saved.favorite)
        #expect(saved.thumbnailURL == "https://i.ytimg.com/vi/EKGRs8q7HlA/hqdefault.jpg")
        let back = try #require(saved.transcript)
        #expect(back.keyframes.count == 1 && back.keyframes[0].image.isEmpty && back.keyframes[0].caption == "Zar şeması")
        #expect(back.paragraphs == transcript.paragraphs && back.notes == transcript.notes && back.chapters == transcript.chapters)
        let raw = String(decoding: try #require(saved.transcriptData), as: UTF8.self)
        #expect(!raw.contains(transcript.keyframes[0].image))
        saved.transcript = nil
        #expect(saved.transcriptData == nil)
    }

    @Test func storeWritesKeyframeFilesAndEncodesWithoutImages() async throws {
        let id = UUID()
        defer { VideoFiles.remove(lesson: id) }
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0xFF, 0xD9])
        var transcript = try #require(try JSONDecoder().decode(YouTubeJobStatus.self, from: Data(Self.sampleJSON.utf8)).result)
        transcript.keyframes = [
            Keyframe(id: "a/1", time: 10, image: jpeg.base64EncodedString(), caption: "Tahta", text: "ATP"),
            Keyframe(id: "b", time: 20, image: "data:image/jpeg;base64," + jpeg.base64EncodedString(), caption: "Slayt", text: ""),
            Keyframe(id: "c", time: 30, image: "", caption: "Boş", text: ""),
        ]
        let data = try #require(await VideoFiles.store(transcript, lesson: id))
        let decoded = try JSONDecoder().decode(VideoTranscript.self, from: data)
        #expect(decoded.keyframes.allSatisfy { $0.image.isEmpty } && decoded.keyframes.count == 3)
        #expect(VideoFiles.keyframeURL(lesson: id, frame: "a/1").lastPathComponent == "frame_a_1.jpg")
        #expect(try Data(contentsOf: VideoFiles.keyframeURL(lesson: id, frame: "a/1")) == jpeg)
        #expect(try Data(contentsOf: VideoFiles.keyframeURL(lesson: id, frame: "b")) == jpeg)
        #expect(!FileManager.default.fileExists(atPath: VideoFiles.keyframeURL(lesson: id, frame: "c").path()))
        VideoFiles.remove(lesson: id)
        #expect(!FileManager.default.fileExists(atPath: VideoFiles.root.appending(path: id.uuidString).path()))
    }

    @Test func timeFormattingParsingAndSRT() {
        #expect(VideoTime.string(0) == "0:00" && VideoTime.string(75.9) == "1:15" && VideoTime.string(3725) == "1:02:05")
        #expect(VideoTime.string(-4) == "0:00" && VideoTime.string(.nan) == "0:00")
        #expect(VideoTime.parse("90") == 90 && VideoTime.parse("1:30") == 90 && VideoTime.parse(" 1:02:05 ") == 3725)
        #expect(VideoTime.parse("2.30") == 150 && VideoTime.parse("90:00") == 5400)
        #expect(VideoTime.parse("") == nil && VideoTime.parse("1:75") == nil && VideoTime.parse("a:10") == nil
                && VideoTime.parse("1:2:3:4") == nil && VideoTime.parse("1::2") == nil)
        #expect(VideoTime.srt(62.5) == "00:01:02,500" && VideoTime.srt(3725.042) == "01:02:05,042")
        let srt = TranscriptExport.srt([TranscriptSegment(start: 0, end: 2.25, text: "Merhaba "), TranscriptSegment(start: 2.25, end: 2.25, text: "Gençler")])
        #expect(srt == "1\n00:00:00,000 --> 00:00:02,250\nMerhaba\n\n2\n00:00:02,250 --> 00:00:02,750\nGençler\n")
    }

    @Test func importLogicCaptionStatusAndRange() {
        #expect(YouTubeImportLogic.captionStatus([.init(lang: "en", name: "English", auto: false), .init(lang: "tr", name: "Türkçe", auto: false)])
                == "Elle altyazı (tr)")
        #expect(YouTubeImportLogic.captionStatus([.init(lang: "en", name: "English", auto: false)]) == "Elle altyazı (en)")
        #expect(YouTubeImportLogic.captionStatus([.init(lang: "tr", name: "Türkçe", auto: true)]) == "Otomatik altyazı")
        #expect(YouTubeImportLogic.captionStatus([]) == "Altyazı yok → yapay zekâ ile dökülecek")
        // Seçici yalnızca elle izleri sunar: sunucu otomatik izde istenen dili dikkate almaz (makine çevirisi izi istenemez).
        let langs = YouTubeImportLogic.captionLanguages([.init(lang: "tr", name: "Türkçe", auto: true), .init(lang: "tr", name: "Türkçe", auto: false),
                                                        .init(lang: "en", name: "English", auto: true)])
        #expect(langs.map(\.lang) == ["tr"] && langs[0].auto == false)
        let r = YouTubeImportLogic.range(start: "1:00", end: "", duration: 882)
        #expect(r.start == 60 && r.end == nil && r.error == nil)
        #expect(YouTubeImportLogic.range(start: "", end: "14:42", duration: 882).end == 882)
        #expect(YouTubeImportLogic.range(start: "5:00", end: "4:00", duration: 882).error != nil)
        #expect(YouTubeImportLogic.range(start: "", end: "20:00", duration: 882).error != nil)
        #expect(YouTubeImportLogic.range(start: "x", end: "", duration: 882).error != nil)
        #expect(YouTubeImportLogic.range(start: "", end: "", duration: 882).error != nil)
        var video = VideoInfo(id: "EKGRs8q7HlA", url: "", title: "", channel: "", duration: 1, thumbnail: nil, chapters: [],
                              captions: [.init(lang: "en", name: "English", auto: true)], language: nil)
        #expect(YouTubeImportLogic.language(of: video) == "en")
        video.language = "tr-TR"
        #expect(YouTubeImportLogic.isTurkish(YouTubeImportLogic.language(of: video) ?? ""))
    }

    @Test func captionPickerOffersOnlyManualTracks() {
        // Ölçülen video: elle altyazı yok, otomatik tr (özgün) + en (çeviri) → seçici gösterilmez.
        var video = VideoInfo(id: "EKGRs8q7HlA", url: "", title: "", channel: "", duration: 882, thumbnail: nil, chapters: [],
                              captions: [.init(lang: "tr", name: "Turkish (Original)", auto: true), .init(lang: "en", name: "English", auto: true)],
                              language: "tr")
        #expect(YouTubeImportLogic.captionLanguages(video.captions).isEmpty)
        #expect(!YouTubeImportLogic.showsCaptionPicker(video))
        // Tek elle iz videonun dilinde: ‘Otomatik’ onu zaten seçer.
        video.captions = [.init(lang: "tr-TR", name: "Türkçe", auto: false), .init(lang: "en", name: "English", auto: true)]
        #expect(!YouTubeImportLogic.showsCaptionPicker(video))
        // Tek elle iz başka dilde ya da birden çok elle iz: seçici görünür.
        video.captions = [.init(lang: "en", name: "English", auto: false), .init(lang: "tr", name: "Türkçe", auto: true)]
        #expect(YouTubeImportLogic.showsCaptionPicker(video))
        video.captions = [.init(lang: "tr", name: "Türkçe", auto: false), .init(lang: "en", name: "English", auto: false)]
        #expect(YouTubeImportLogic.showsCaptionPicker(video) && YouTubeImportLogic.captionLanguages(video.captions).count == 2)
        #expect(YouTubeImportLogic.baseLanguage("tr-TR") == "tr" && YouTubeImportLogic.baseLanguage("pt_BR") == "pt")
    }

    @Test func rangeMatchesServerRules() {
        // Sunucu: bitiş > 0, bitiş − başlangıç ≥ 5 sn (kırpmadan sonra da), işlenecek kısım ≤ 4 saat.
        #expect(YouTubeImportLogic.range(start: "1:00", end: "1:03", duration: 882).error == "Bitiş, başlangıçtan en az 5 saniye sonra olmalı.")
        #expect(YouTubeImportLogic.range(start: "1:00", end: "1:05", duration: 882).error == nil)
        #expect(YouTubeImportLogic.range(start: "", end: "0:00", duration: 882).error != nil)
        #expect(YouTubeImportLogic.range(start: "", end: "0:03", duration: 882).error != nil)
        // Başlangıç süreye 5 sn'den yakın; bitiş süreye kırpılıyor ya da boş.
        #expect(YouTubeImportLogic.range(start: "14:40", end: "14:43", duration: 882.5).error != nil)
        #expect(YouTubeImportLogic.range(start: "14:40", end: "", duration: 882).error != nil)
        // 5 saatlik video: aralıksız engelli, 4 saati aşmayan aralıkla serbest.
        let long = 5.0 * 3600
        #expect(YouTubeImportLogic.durationBlocker(duration: long, useRange: false, start: "", end: "") != nil)
        #expect(YouTubeImportLogic.durationBlocker(duration: long, useRange: true, start: "0:00", end: "2:00:00") == nil)
        #expect(YouTubeImportLogic.durationBlocker(duration: long, useRange: true, start: "1:00:00", end: "") == nil)
        #expect(YouTubeImportLogic.durationBlocker(duration: long, useRange: true, start: "", end: "4:00:01") != nil)
        #expect(YouTubeImportLogic.durationBlocker(duration: long, useRange: true, start: "30:00", end: "") != nil)
        #expect(YouTubeImportLogic.durationBlocker(duration: 882, useRange: false, start: "", end: "") == nil)
        #expect(YouTubeImportLogic.durationBlocker(duration: 4 * 3600, useRange: false, start: "", end: "") == nil)
    }

    @Test func rangeLessonOpensAtTranscriptStart() throws {
        var transcript = try #require(try JSONDecoder().decode(YouTubeJobStatus.self, from: Data(Self.sampleJSON.utf8)).result)
        // Videonun başından işlenmiş ders: kayıtlı konum kullanılır.
        #expect(TranscriptFormat.initialSeek(lastPosition: 0, transcript: transcript) == nil)
        #expect(TranscriptFormat.chaptersEnd(videoDuration: 882, transcript: transcript) == 6)
        // 1:00:00–1:30:00 aralığı: hiç izlenmemişse ilk paragraf, izlenmişse kayıtlı konum.
        transcript.paragraphs = [TranscriptParagraph(start: 3600.4, end: 3660, text: "A."), TranscriptParagraph(start: 3660, end: 5400, text: "B.")]
        #expect(TranscriptFormat.initialSeek(lastPosition: 0, transcript: transcript) == 3600.4)
        #expect(TranscriptFormat.initialSeek(lastPosition: 3700, transcript: transcript) == nil)
        // Son bölüm videonun sonunda değil işlenen kısmın sonunda biter.
        #expect(TranscriptFormat.chaptersEnd(videoDuration: 7200, transcript: transcript) == 5400)
        transcript.paragraphs = []
        transcript.segments = []
        #expect(TranscriptFormat.chaptersEnd(videoDuration: 7200, transcript: transcript) == 7200)
        #expect(TranscriptFormat.initialSeek(lastPosition: 0, transcript: transcript) == nil)
    }

    @Test func missingNotesExplainsFailure() {
        let failed = TranscriptFormat.missingNotesMessage(warnings: ["Bölümler çıkarılamadı (x).", "Ders notu hazırlanamadı (kota doldu)."])
        #expect(failed.title == "Ders notu hazırlanamadı" && failed.detail.hasPrefix("Ders notu hazırlanamadı (kota doldu)."))
        let neutral = TranscriptFormat.missingNotesMessage(warnings: [])
        #expect(neutral.title == "Ders notu yok" && neutral.detail.contains("kapalıydı ya da not hazırlanamadı"))
    }

    @Test func liveLessonIgnoresDeletedLesson() throws {
        let container = try ModelContainer(for: VideoLesson.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let lesson = VideoLesson(url: "https://youtu.be/EKGRs8q7HlA")
        context.insert(lesson)
        try context.save()
        let id = lesson.id
        #expect(VideoLessonView.liveLesson(id: id, in: context) != nil)
        context.delete(lesson)
        try context.save()
        #expect(VideoLessonView.liveLesson(id: id, in: context) == nil)
    }

    @Test func plainTextsForBatchSources() async throws {
        let transcript = try #require(try JSONDecoder().decode(YouTubeJobStatus.self, from: Data(Self.sampleJSON.utf8)).result)
        let data = try JSONEncoder().encode(transcript)
        let texts = await LessonFiles.plainTexts([data, nil, Data("bozuk".utf8), data])
        #expect(texts.count == 4 && texts[1].isEmpty && texts[2].isEmpty && texts[0] == texts[3] && texts[0].contains("Gençler merhaba."))
    }

    @Test func youtubeLinkDetection() {
        #expect(YouTubeLink.videoID("https://www.youtube.com/watch?v=EKGRs8q7HlA&t=42s") == "EKGRs8q7HlA")
        #expect(YouTubeLink.videoID("youtu.be/EKGRs8q7HlA?si=x") == "EKGRs8q7HlA")
        #expect(YouTubeLink.videoID("https://m.youtube.com/shorts/EKGRs8q7HlA") == "EKGRs8q7HlA")
        #expect(YouTubeLink.videoID("https://music.youtube.com/watch?v=EKGRs8q7HlA&list=PL1") == "EKGRs8q7HlA")
        #expect(YouTubeLink.videoID("https://www.youtube.com/live/EKGRs8q7HlA") == "EKGRs8q7HlA")
        #expect(YouTubeLink.playlistID("https://www.youtube.com/playlist?list=PLabc") == "PLabc")
        #expect(YouTubeLink.videoID("https://www.youtube.com/watch?v=short") == nil)
        #expect(!YouTubeLink.isYouTube("https://notyoutube.com/watch?v=EKGRs8q7HlA") && !YouTubeLink.isYouTube("merhaba dünya"))
        #expect(YouTubeLink.watchURL(videoID: "EKGRs8q7HlA", at: 61.8)?.absoluteString == "https://www.youtube.com/watch?v=EKGRs8q7HlA&t=61s")
        let ask = YouTubeAskRequest.make(title: "T", question: String(repeating: "a", count: 600),
                                         paragraphs: [TranscriptParagraph(start: 0, end: 1, text: String(repeating: "b", count: 399_990)),
                                                      TranscriptParagraph(start: 1, end: 2, text: String(repeating: "c", count: 50)),
                                                      TranscriptParagraph(start: 2, end: 3, text: "d")])
        #expect(ask.question.count == 500 && ask.paragraphs.count == 2 && ask.paragraphs.reduce(0) { $0 + $1.text.count } == 400_000)
    }
}

@MainActor
struct VideoLessonViewTests {
    @Test func srtUsesSequenceNumbersAndCommaMilliseconds() {
        let srt = TranscriptFormat.srt([
            TranscriptSegment(start: 62.5, end: 65.25, text: "  İkinci satır  "),
            TranscriptSegment(start: 0, end: 2, text: "Gençler merhaba.\nHoş geldiniz."),
            TranscriptSegment(start: 70, end: 71, text: "   "),
            TranscriptSegment(start: 3725.1234, end: 3720, text: "Son"),
        ])
        #expect(srt == "1\n00:00:00,000 --> 00:00:02,000\nGençler merhaba.\nHoş geldiniz.\n\n"
            + "2\n00:01:02,500 --> 00:01:05,250\nİkinci satır\n\n"
            + "3\n01:02:05,123 --> 01:02:06,123\nSon\n")
        #expect(TranscriptFormat.srtTimestamp(-3) == "00:00:00,000")
        #expect(TranscriptFormat.srtTimestamp(.nan) == "00:00:00,000")
        #expect(TranscriptFormat.srtTimestamp(59.9996) == "00:01:00,000")
        #expect(TranscriptFormat.srt([]).isEmpty)
    }

    @Test func timestampAndLinks() {
        #expect(TranscriptFormat.timestamp(0) == "00:00")
        #expect(TranscriptFormat.timestamp(75.9) == "01:15")
        #expect(TranscriptFormat.timestamp(599) == "09:59")
        #expect(TranscriptFormat.timestamp(3599.99) == "59:59")
        #expect(TranscriptFormat.timestamp(3600) == "1:00:00")
        #expect(TranscriptFormat.timestamp(3725) == "1:02:05")
        #expect(TranscriptFormat.timestamp(-5) == "00:00")
        #expect(TranscriptFormat.timestamp(.infinity) == "00:00")
        #expect(TranscriptFormat.shareURL(videoID: "EKGRs8q7HlA", at: 61.8)?.absoluteString == "https://youtu.be/EKGRs8q7HlA?t=61")
        #expect(TranscriptFormat.shareURL(videoID: "EKGRs8q7HlA")?.absoluteString == "https://youtu.be/EKGRs8q7HlA")
        #expect(TranscriptFormat.shareURL(videoID: "bad") == nil)
        #expect(TranscriptFormat.noteLine(time: 75, quote: "  Hücre zarı seçici geçirgendir. ") == "[01:15] Hücre zarı seçici geçirgendir.")
        #expect(TranscriptFormat.fileName("A/B: C?", ext: "srt") == "A-B- C-.srt")
        #expect(TranscriptFormat.fileName("  ", suffix: " - Ders notu", ext: "md") == "Video dersi - Ders notu.md")
    }

    @Test func currentParagraphAndChapterBinarySearch() {
        let starts: [Double] = [0.5, 30, 75, 140]
        #expect(TranscriptFormat.index(at: 0, starts: starts) == nil)
        #expect(TranscriptFormat.index(at: 0.5, starts: starts) == 0)
        #expect(TranscriptFormat.index(at: 29.99, starts: starts) == 0)
        #expect(TranscriptFormat.index(at: 30, starts: starts) == 1)
        #expect(TranscriptFormat.index(at: 100, starts: starts) == 2)
        #expect(TranscriptFormat.index(at: 10_000, starts: starts) == 3)
        #expect(TranscriptFormat.index(at: 5, starts: []) == nil)
        #expect(TranscriptFormat.index(at: .nan, starts: starts) == nil)
        #expect(TranscriptFormat.index(at: 7, starts: [7]) == 0)
        #expect(TranscriptFormat.currentParagraph(at: 150, starts: starts, lastEnd: 180) == 3)
        #expect(TranscriptFormat.currentParagraph(at: 190, starts: starts, lastEnd: 180) == nil)
        #expect(TranscriptFormat.currentParagraph(at: 190, starts: starts, lastEnd: nil) == 3)
        let many = (0..<1000).map { Double($0) * 45 }
        #expect((0..<1000).allSatisfy { TranscriptFormat.index(at: Double($0) * 45 + 1, starts: many) == $0 })
        let chapters = [VideoChapter(title: "Giriş", start: 0), VideoChapter(title: "Hücre zarı", start: 120)].map(\.start)
        #expect(TranscriptFormat.index(at: 119.9, starts: chapters) == 0)
        #expect(TranscriptFormat.index(at: 120, starts: chapters) == 1)
        #expect(TranscriptFormat.index(at: 882, starts: chapters) == 1)
    }

    @Test func searchIsCaseTurkishAndDiacriticInsensitive() {
        let text = "İnsan hücresi. Işık ve HÜCRE zarı; hücre bölünmesi"
        let ranges = TranscriptFormat.matchRanges(of: "hucre", in: text)
        #expect(ranges.map { String(text[$0]) } == ["hücre", "HÜCRE", "hücre"])
        #expect(TranscriptFormat.matchRanges(of: "insan", in: text).map { String(text[$0]) } == ["İnsan"])
        #expect(TranscriptFormat.matchRanges(of: "ışık", in: text).map { String(text[$0]) } == ["Işık"])
        #expect(TranscriptFormat.matchRanges(of: "isik", in: text).map { String(text[$0]) } == ["Işık"])
        #expect(TranscriptFormat.matchRanges(of: "  ", in: text).isEmpty)
        #expect(TranscriptFormat.matchRanges(of: "mitokondri", in: text).isEmpty)
        #expect(TranscriptFormat.matchRanges(of: "aa", in: "aaaa").count == 2)
        #expect(TranscriptFormat.matchingIndices(of: "ZAR", in: ["Hücre zarı", "Çekirdek", "zar zor"]) == [0, 2])
        #expect(TranscriptFormat.matchingIndices(of: "", in: ["a"]).isEmpty)
        let attributed = AttributedString(text)
        #expect(ranges.allSatisfy { Range($0, in: attributed) != nil })
    }

    @Test func translationRowsAndCards() {
        let original = [TranscriptParagraph(start: 0, end: 30, text: "Hello. Welcome to class."),
                        TranscriptParagraph(start: 30, end: 60, text: "World")]
        let translation = TranscriptTranslation(language: "tr", paragraphs: [
            TranscriptParagraph(start: 30, end: 60, text: "Dünya"),
            TranscriptParagraph(start: 0, end: 30, text: "Merhaba. Derse hoş geldiniz."),
        ])
        let both = TranscriptFormat.rows(paragraphs: original, translation: translation, language: .both)
        #expect(both.map(\.text) == ["Hello. Welcome to class.", "World"])
        #expect(both.map(\.secondary) == ["Merhaba. Derse hoş geldiniz.", "Dünya"])
        #expect(TranscriptFormat.rows(paragraphs: original, translation: translation, language: .translated).map(\.text)
            == ["Merhaba. Derse hoş geldiniz.", "Dünya"])
        #expect(TranscriptFormat.rows(paragraphs: original, translation: nil, language: .both).allSatisfy { $0.secondary == nil })
        let uneven = TranscriptFormat.alignedTranslation(
            original: original + [TranscriptParagraph(start: 90, end: 120, text: "Bye")], translated: translation.paragraphs)
        #expect(uneven == ["Merhaba. Derse hoş geldiniz.", "Dünya", nil])

        let card = TranscriptFormat.cardContent(for: both[0])
        #expect(card.front == "Merhaba…?")
        #expect(card.back.hasPrefix("Merhaba. Derse hoş geldiniz.") && card.back.contains("Hello"))
        #expect(TranscriptFormat.cardFront("Gençler merhaba. Hepiniz hoş geldiniz.") == "Gençler merhaba…?")
        #expect(TranscriptFormat.cardFront("Hücre zarı, seçici geçirgen bir yapıdır ve madde alışverişini düzenler")
            == "Hücre zarı, seçici geçirgen bir yapıdır ve madde…?")

        let notes = LectureNotes(summary: "", keyPoints: [],
                                 concepts: [NoteConcept(name: "Osmoz", definition: "Suyun yarı geçirgen zardan geçişi", time: 10),
                                            NoteConcept(name: "Difüzyon", definition: "Çok yoğundan az yoğuna geçiş", time: 20)],
                                 formulas: [],
                                 questions: [NoteQuestion(question: "Osmoz nedir?", answer: "Suyun geçişi", time: 30),
                                             NoteQuestion(question: "Mitoz kaç evredir?", answer: "Dört", time: 40),
                                             NoteQuestion(question: "Boş cevap?", answer: " ", time: 50)],
                                 examTips: [])
        let drafts = TranscriptFormat.noteCards(notes, existingFronts: ["difüzyon NEDİR?"])
        #expect(drafts.map(\.front) == ["Osmoz nedir?", "Mitoz kaç evredir?"])
        #expect(TranscriptFormat.noteCards(notes, existingFronts: Set(drafts.map(\.front) + ["Difüzyon nedir?"])).isEmpty)
    }

    @Test func keyframesBecomeSourceFigures() {
        let frames = [Keyframe(id: "k/2", time: 90, image: "", caption: "Hücre şeması", text: "Çekirdek"),
                      Keyframe(id: "k1", time: 10, image: "abc", caption: " ", text: "Mitoz evreleri: profaz, metafaz"),
                      Keyframe(id: "k/2", time: 95, image: "", caption: "Yinelenen", text: "")]
        let figures = TranscriptFormat.sourceFigures(from: frames, title: "Biyoloji")
        #expect(figures.map(\.id) == ["yt_k1", "yt_k_2"])
        #expect(figures.map(\.caption) == ["Mitoz evreleri: profaz, metafaz", "Hücre şeması"])
        #expect(figures.allSatisfy { $0.kind == "figure" && $0.page == 0 && $0.documentName == "Biyoloji" && $0.table == nil })
        #expect(TranscriptFormat.figureID("k/2") == "yt_k_2")
    }

    @Test func textExportsAndMultiPagePDF() throws {
        let video = VideoInfo(id: "EKGRs8q7HlA", url: "https://www.youtube.com/watch?v=EKGRs8q7HlA", title: "Hücre", channel: "Kanal",
                              duration: 882, thumbnail: nil, chapters: [], captions: [], language: "tr")
        let paragraphs = (0..<40).map { i in
            TranscriptParagraph(start: Double(i) * 30, end: Double(i) * 30 + 30,
                                text: i == 0 ? "Gençler merhaba." : String(repeating: "Hücre zarı seçici geçirgendir. ", count: 20))
        }
        let transcript = VideoTranscript(video: video, source: "auto-captions", language: "tr", segments: [], paragraphs: paragraphs,
                                         chapters: [VideoChapter(title: "Zar", start: 60), VideoChapter(title: "Giriş", start: 0)],
                                         translation: nil, notes: nil, keyframes: [], warnings: [])
        let txt = TranscriptFormat.plainText(title: "Hücre", channel: "Kanal", url: video.url, paragraphs: paragraphs, chapters: transcript.chapters)
        #expect(txt.contains("[00:00] Gençler merhaba.") && txt.contains("== Zar [01:00] =="))
        #expect(txt.range(of: "== Giriş")!.lowerBound < txt.range(of: "== Zar")!.lowerBound)
        let md = TranscriptFormat.markdown(title: "Hücre", channel: "Kanal", transcript: transcript)
        #expect(md.hasPrefix("# Hücre") && md.contains("[01:00](https://youtu.be/EKGRs8q7HlA?t=60) Zar") && md.contains("## Transkript"))
        let source = TranscriptFormat.podcastSource(title: "Hücre", channel: "Kanal", transcript: transcript)
        #expect(source.contains("Bölümler:\n- Giriş\n- Zar") && source.contains("Gençler merhaba."))
        #expect(TranscriptFormat.chunks(String(repeating: "Bir cümle. ", count: 400), maxLength: 500).allSatisfy { $0.count <= 500 })
        let shortLines = TranscriptFormat.chunks(String(repeating: "satır\n", count: 100), maxLength: 5000, maxLines: 10)
        #expect(shortLines.count == 10 && shortLines.allSatisfy { $0.split(separator: "\n").count == 10 })

        let url = URL.temporaryDirectory.appending(path: "video-lesson-test.pdf")
        try? FileManager.default.removeItem(at: url)
        #expect(LessonPDF.render(title: "Hücre", channel: "Kanal", transcript: transcript, frames: [:], to: url))
        let pages = CGPDFDocument(url as CFURL)?.numberOfPages ?? 0
        #expect(pages >= 3)
        try? FileManager.default.removeItem(at: url)
    }
}

/// YouTube Ders Stüdyosu 2. tur: gömme bilgisi, uygulama içi ses, oynatıcı arka ucu, sunucu işini iptal.
@MainActor
struct YouTubeAudioAndCancelTests {
    private final class Owner: RemoteCommandOwner {
        var received: [RemoteCommand] = []
        func handleRemote(_ command: RemoteCommand) { received.append(command) }
    }

    @Test func embeddableMissingMeansTrueAndFalseIsKept() throws {
        let missing = try JSONDecoder().decode(VideoInfo.self, from: Data(#"{"id":"EKGRs8q7HlA","duration":60}"#.utf8))
        #expect(missing.embeddable == nil && missing.isEmbeddable)
        let blocked = try JSONDecoder().decode(VideoInfo.self, from: Data(#"{"id":"EKGRs8q7HlA","embeddable":false}"#.utf8))
        #expect(blocked.embeddable == false && !blocked.isEmbeddable)
        let allowed = try JSONDecoder().decode(VideoInfo.self, from: Data(#"{"id":"EKGRs8q7HlA","embeddable":true}"#.utf8))
        #expect(allowed.isEmbeddable)
        #expect(try JSONDecoder().decode(VideoInfo.self, from: JSONEncoder().encode(blocked)).embeddable == false)

        // Ders kaydı: false yansır; bilgi eksikse varsayılan (true) korunur. Ses indirilmemiş.
        let lesson = VideoLesson(url: "", info: blocked)
        #expect(!lesson.embeddable && lesson.audioFileName == nil && lesson.audioURL == nil && !lesson.hasAudioFile)
        #expect(VideoLesson(url: "", info: missing).embeddable)

        // Eski yedek kaydı (yeni alanlar yok) çözülür.
        let dto = try JSONDecoder().decode(BackupManifest.VideoLessonDTO.self, from: Data("""
        {"id":"\(UUID().uuidString)","url":"u","videoID":"EKGRs8q7HlA","title":"T","channel":"C","duration":60,"thumbnailURL":null,
         "language":"tr","source":"ai","createdAt":0,"lastPosition":0,"transcriptData":null,"episodeIDs":[],"favorite":false}
        """.utf8))
        #expect(dto.embeddable == nil && dto.audioFileName == nil)
    }

    @Test func decodesAudioResponseOffMainFriendly() throws {
        let bytes = Data([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x4D, 0x34, 0x41])   // "....ftypM4A"
        let json = #"{"audio":"\#(bytes.base64EncodedString())","mimeType":"audio/mp4","duration":125.5,"bytes":11}"#
        let response = try JSONDecoder().decode(YouTubeAudioResponse.self, from: Data(json.utf8))
        #expect(response.mimeType == "audio/mp4" && response.duration == 125.5 && response.bytes == 11)
        let audio = try response.decoded()
        #expect(audio.data == bytes && audio.duration == 125.5)

        // "data:" öneki ve eksik alanlar
        #expect(try YouTubeAudioResponse(audio: "data:audio/mp4;base64," + bytes.base64EncodedString()).decoded().data == bytes)
        let minimal = try JSONDecoder().decode(YouTubeAudioResponse.self, from: Data(#"{"audio":"AAAA"}"#.utf8))
        #expect(minimal.mimeType == "audio/mp4" && minimal.bytes == 0 && minimal.duration == 0)

        // Boş veri ve iPhone'da oynatılamayan biçim reddedilir.
        #expect(throws: APIError.self) { try YouTubeAudioResponse(audio: "").decoded() }
        #expect(throws: APIError.self) { try YouTubeAudioResponse(audio: bytes.base64EncodedString(), mimeType: "audio/webm").decoded() }
        #expect(YouTubeAudioResponse.isPlayable(mimeType: "audio/mp4; codecs=\"mp4a.40.5\""))
        #expect(!YouTubeAudioResponse.isPlayable(mimeType: "audio/ogg"))
    }

    @Test func savesAudioInLessonFolderAndRemovesWithIt() async throws {
        let id = UUID()
        defer { VideoFiles.remove(lesson: id) }
        let name = try await VideoFiles.saveAudio(Data([1, 2, 3]), lesson: id)
        #expect(name == "audio.m4a")
        let url = VideoFiles.audioURL(lesson: id, name: name)
        #expect(url.path().hasSuffix("Videos/\(id.uuidString)/audio.m4a"))
        #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        // Kayıtlı ad yol parçası taşıyamaz.
        #expect(VideoFiles.audioURL(lesson: id, name: "../../x.m4a").deletingLastPathComponent().lastPathComponent == id.uuidString)

        let lesson = VideoLesson(url: "https://youtu.be/EKGRs8q7HlA")
        lesson.id = id
        lesson.audioFileName = name
        #expect(lesson.hasAudioFile && lesson.audioURL == url)
        lesson.removeFiles()
        #expect(!lesson.hasAudioFile)
    }

    @Test func choosesPlayerBackend() throws {
        #expect(PlayerBackend.choose(embeddable: true, webFailed: false, hasAudioFile: false) == .web)
        #expect(PlayerBackend.choose(embeddable: true, webFailed: false, hasAudioFile: true) == .web)
        #expect(PlayerBackend.choose(embeddable: false, webFailed: false, hasAudioFile: false) == .offerAudio)
        #expect(PlayerBackend.choose(embeddable: false, webFailed: false, hasAudioFile: true) == .audio)
        #expect(PlayerBackend.choose(embeddable: true, webFailed: true, hasAudioFile: false) == .offerAudio)
        #expect(PlayerBackend.choose(embeddable: true, webFailed: true, hasAudioFile: true) == .audio)

        // Model: kayıtta ad olsa da dosya yoksa ses yok sayılır; dosya varsa doğrudan ses kipi.
        let missing = VideoPlayerModel(videoID: "EKGRs8q7HlA", startAt: 30, duration: 600, embeddable: false,
                                       audioURL: URL.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a"))
        #expect(missing.backend == .offerAudio && missing.currentTime == 30)
        missing.seek(to: 90)                                  // kartta da konum ilerler (ses oradan başlar)
        missing.play()
        #expect(missing.currentTime == 90 && !missing.isPlaying && !missing.hasStarted)

        let file = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
        try Data([0]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(VideoPlayerModel(videoID: "EKGRs8q7HlA", embeddable: false, audioURL: file).backend == .audio)
        #expect(VideoPlayerModel(videoID: "EKGRs8q7HlA", embeddable: true, audioURL: file).backend == .web)
        #expect(VideoPlayerModel(videoID: "EKGRs8q7HlA").backend == .web)
    }

    @Test func remoteCommandsCanBeLentAndReclaimed() {
        let main = PlayerController()
        let owner = Owner(), other = Owner()
        #expect(!main.ownsRemoteCommands(owner))
        main.lendRemoteCommands(to: owner)
        #expect(main.ownsRemoteCommands(owner))
        main.reclaimRemoteCommands(from: other)              // başkası bırakamaz
        #expect(main.ownsRemoteCommands(owner))
        main.reclaimRemoteCommands(from: owner)
        #expect(!main.ownsRemoteCommands(owner))
    }

    @Test func mapsCancelStates() throws {
        let cancelled = try JSONDecoder().decode(YouTubeCancelResponse.self, from: Data(#"{"ok":true,"state":"cancelled"}"#.utf8))
        #expect(cancelled.ok && cancelled.state == .cancelled)
        #expect(try JSONDecoder().decode(YouTubeCancelResponse.self, from: Data(#"{"ok":true,"state":"done"}"#.utf8)).state == .done)
        #expect(try JSONDecoder().decode(YouTubeCancelResponse.self, from: Data(#"{"state":"odd"}"#.utf8)).state == .running)
        let status = try JSONDecoder().decode(YouTubeJobStatus.self, from: Data(#"{"state":"cancelled","progress":0.4,"step":"İptal edildi"}"#.utf8))
        #expect(status.state == .cancelled && status.progress == 0.4)

        let gone = YouTubeImportLogic.afterCancel(.state(.cancelled))
        #expect(!gone.keepPending && gone.message == "İptal edildi.")
        #expect(!YouTubeImportLogic.afterCancel(.notFound).keepPending)
        #expect(YouTubeImportLogic.afterCancel(.state(.done)).keepPending)       // sonuç hâlâ alınabilir
        #expect(!YouTubeImportLogic.afterCancel(.state(.error)).keepPending)
        #expect(YouTubeImportLogic.afterCancel(.unreachable).keepPending)        // iş sürüyor olabilir
        #expect(YouTubeImportLogic.afterCancel(.state(.running)).keepPending)
    }

    @Test func audioCardTextsAndArtworkFrame() {
        #expect(LessonAudioCard.receivingText(fraction: 0.376, received: 2_000_000).hasPrefix("İndiriliyor %37 · "))
        #expect(LessonAudioCard.receivingText(fraction: nil, received: 0).hasPrefix("İndiriliyor · "))
        let frames = [Keyframe(id: "a", time: 10, image: "", caption: "", text: ""),
                      Keyframe(id: "b", time: 60, image: "", caption: "", text: "")]
        #expect(LessonAudioArtwork.frameID(at: 5, in: frames) == nil)
        #expect(LessonAudioArtwork.frameID(at: 9.6, in: frames) == "a")
        #expect(LessonAudioArtwork.frameID(at: 59, in: frames) == "a")
        #expect(LessonAudioArtwork.frameID(at: 3600, in: frames) == "b")
        #expect(LessonAudioDownload.maxDuration == 3 * 3600)
    }
}

/// 2. tur düzeltmeleri: durdurma bildirimi, yedekten gelen sesin iCloud dışı kalması, ses indirme hatası ve zaman aşımı.
@MainActor
struct YouTubeStopAndRestoreTests {
    @Test func stopNoticeCombinesCancelOutcomeAndSavedLessons() {
        #expect(YouTubeImportLogic.stopNotice(saved: 0, cancel: nil) == nil)
        #expect(YouTubeImportLogic.stopNotice(saved: 0, cancel: "İptal edildi.") == "İptal edildi.")
        // Kaydederken durdurulan tek ders: sunucuya iptal gitmez, ders kütüphanede kalır.
        #expect(YouTubeImportLogic.stopNotice(saved: 1, cancel: nil) == "Durdurulmadan önce biten ders kütüphaneye kaydedildi.")
        // Toplu işte sonraki iş iptal edildi; öncekiler kaydedilmişti.
        let both = YouTubeImportLogic.stopNotice(saved: 2, cancel: YouTubeImportLogic.cancelledText)
        #expect(both == "İptal edildi. Durdurulmadan önce biten 2 ders kütüphaneye kaydedildi.")
        #expect(YouTubeImportLogic.stoppingText == "Durduruluyor…")
    }

    @Test func restoredAudioIsExcludedFromBackupOtherFilesUntouched() throws {
        let source = URL.temporaryDirectory.appending(path: "restore-src-\(UUID().uuidString)", directoryHint: .isDirectory)
        let target = URL.temporaryDirectory.appending(path: "restore-dst-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: target)
        }
        let audio = source.appending(path: "audio.m4a"), frame = source.appending(path: "frame_a.jpg")
        try Data([1, 2, 3]).write(to: audio)
        try Data([4]).write(to: frame)
        // Hedefte eski bir dosya varsa üzerine yazılır.
        try Data([9, 9]).write(to: target.appending(path: "audio.m4a"))

        VideoFiles.restoreFile(audio, to: target.appending(path: "audio.m4a"))
        VideoFiles.restoreFile(frame, to: target.appending(path: "frame_a.jpg"))

        let restoredAudio = target.appending(path: "audio.m4a")
        #expect(try Data(contentsOf: restoredAudio) == Data([1, 2, 3]))
        #expect(try restoredAudio.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let restoredFrame = target.appending(path: "frame_a.jpg")
        #expect(try Data(contentsOf: restoredFrame) == Data([4]))
        #expect(try restoredFrame.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == false)
    }

    @Test func audioDownloadFailureHintsAtFastRetryAfterDisconnect() {
        let dropped = LessonAudioDownload.failureMessage(APIError.network(URLError(.networkConnectionLost)))
        #expect(dropped.contains("Tekrar dene") && dropped.contains("arka plana"))
        let timedOut = LessonAudioDownload.failureMessage(APIError.network(URLError(.timedOut)))
        #expect(timedOut.hasPrefix("Sunucu zamanında yanıt vermedi."))
        // Sunucunun kendi hatası olduğu gibi gösterilir.
        let tooLong = APIError(status: 413, code: "too_large", message: "Video 3 saatten uzun; sesi uygulamaya indirilemiyor.")
        #expect(LessonAudioDownload.failureMessage(tooLong) == tooLong.message)
    }

    @Test func audioRequestOutlastsServerLockAndDownload() {
        // Sunucu: önceki indirmeyi kilitte bekletme (≤ 10 dk) + kendi indirmesi (≤ 10 dk) boyunca hiç bayt göndermez.
        #expect(APIClient.longRequestTimeout >= 20 * 60)
        #expect(APIClient.longResourceTimeout >= 30 * 60)
    }
}

struct FollowAlongTests {
    @Test func wordTimingIsProportionalAndOrdered() {
        let text = "Enerji, iş yapabilme yeteneği ya da bir değişikliğe neden olma kapasitesidir."
        let words = FollowAlong.words(in: text)
        #expect(words.count == 11)
        #expect(String(text[words[0].range]) == "Enerji,")
        #expect(zip(words, words.dropFirst()).allSatisfy { $0.to == $1.from && $0.from < $1.from })
        #expect(FollowAlong.current(words, progress: 0) == 0)
        #expect(FollowAlong.current(words, progress: 0.999) == 10)
        #expect(FollowAlong.current(words, progress: 1.5) == 10)
        #expect(FollowAlong.current(words, progress: -0.1) == nil)
        // Ortadaki bir kelime: payı içinde kalan ilerleme o kelimeyi seçer.
        let mid = words[4]
        #expect(FollowAlong.current(words, progress: (mid.from + mid.to) / 2) == 4)
    }

    @Test func spansAnchorWordsToCaptionLines() {
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
        // Paragraf 0–20 sn ama ikinci satır 15. sn'de başlıyor: düz dağıtım 3. kelimeyi ~10. sn'ye koyardı.
        let text = "bir iki üç dört"
        let timing = FollowAlong.Timing(text: text, start: 0, end: 20,
                                        spans: [.init(start: 0, end: 4, words: 2), .init(start: 15, end: 20, words: 2)])
        #expect(near(timing.times[0], 0))
        #expect(near(timing.times[2], 15))
        #expect(timing.times[1] > 0 && timing.times[1] < 4)
        #expect(timing.current(at: 10) == 1)   // satır arası boşlukta önceki kelime vurgulu kalır
        #expect(timing.current(at: 15.1) == 2)
        #expect(timing.current(at: -1) == nil)
        // Kelime sayısı metinle tutmazsa orantılı eşlenir (8 kelime, satırlarda 2 + 2).
        let long = FollowAlong.Timing(text: "a b c d e f g h", start: 0, end: 10,
                                      spans: [.init(start: 0, end: 5, words: 2), .init(start: 5, end: 10, words: 2)])
        #expect(near(long.times[4], 5))
        #expect(long.times[3] < 5)
        // Parça yoksa eski davranış: tüm aralığa düz dağıtım.
        let plain = FollowAlong.Timing(text: text, start: 2, end: 6)
        #expect(near(plain.times[0], 2) && plain.times.last! < 6)
    }

    @Test func pausesKeepHighlightOnSpeech() {
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
        // Tur 10–20 sn; 10–10,6 baştaki sessizlik, 14–15 cümle arası durak.
        let pauses = [FollowAlong.Pause(start: 9.5, end: 10.6), FollowAlong.Pause(start: 14, end: 15), FollowAlong.Pause(start: 30, end: 31)]
        let timing = FollowAlong.Timing(text: "aaa bbb. ccc ddd", start: 10, end: 20, pauses: pauses)
        #expect(near(timing.times[0], 10.6))                 // ilk kelime konuşma başlayınca
        #expect(timing.current(at: 10.3) == nil)             // baştaki sessizlikte vurgu yok
        #expect(!timing.times.contains { $0 > 14 && $0 < 15 })   // durak sırasında kelime başlamaz
        #expect(timing.times[2] >= 15)
        // Ölçüm şüpheliyse (aralığın neredeyse tamamı sessiz) aralığın tamamı kullanılır.
        #expect(FollowAlong.voicedPieces(from: 0, to: 10, pauses: [.init(start: 0, end: 9.5)]) == [0...10])
        #expect(FollowAlong.voicedPieces(from: 0, to: 10, pauses: [.init(start: 2, end: 3)]) == [0...2, 3...10])
        // Okunan yerin metin konumu ilerledikçe artar (sayfa kaydırması için).
        #expect(timing.textProgress(at: 10.3) == 0)
        #expect(timing.textProgress(at: 16) > timing.textProgress(at: 12))
    }

    @Test func speechPausesDetectsQuietRuns() {
        // 20 ms kareler: 10 kare konuşma, 10 kare sessizlik (0,2 sn ≥ 0,14), 3 kare kısa sessizlik (sayılmaz), konuşma.
        let loud: [Float] = Array(repeating: 0.3, count: 10)
        let rms = loud + Array(repeating: 0.0001, count: 10) + loud + Array(repeating: 0.0001, count: 3) + loud
        let pauses = SpeechPauses.detect(rms: rms)
        #expect(pauses.count == 1)
        #expect(abs(pauses[0].start - 0.2) < 1e-9 && abs(pauses[0].end - 0.4) < 1e-9)
    }

    @Test func transcriptRowsCarryCaptionSpans() {
        let segments = [TranscriptSegment(start: 0, end: 2, text: "Merhaba gençler."),
                        TranscriptSegment(start: 2, end: 5, text: "Bugün fotosentez"),
                        TranscriptSegment(start: 5, end: 9, text: "konusuna devam ediyoruz.")]
        let spans = TranscriptFormat.spans(start: 2, end: 9, segments: segments)
        #expect(spans.map(\.words) == [2, 3])
        #expect(spans.first?.start == 2)
    }

    @Test func scrollDeltaOnlyMovesDownWhileReading() {
        let vp = 700.0
        func near(_ a: Double?, _ b: Double) -> Bool { abs((a ?? .nan) - b) < 1e-9 }
        // Okunan yer ekranda ve üst yarıda: kaydırma yok (yeni paragraf başında da sayfa geri gitmez).
        #expect(FollowAlong.scrollDelta(onScreen: 0.05 * vp, viewport: vp) == nil)
        #expect(FollowAlong.scrollDelta(onScreen: 0.35 * vp, viewport: vp) == nil)
        #expect(FollowAlong.scrollDelta(onScreen: 0.50 * vp, viewport: vp) == nil)
        #expect(FollowAlong.scrollDelta(onScreen: 0.0, viewport: vp, force: true) == nil)
        // Alt kısma inince aşağı kaydır (okunan yer %35'e gelir).
        #expect(near(FollowAlong.scrollDelta(onScreen: 0.60 * vp, viewport: vp), 0.25 * vp))
        // Ekran dışı (geri ya da ileri sarma): iki yöne de getir.
        #expect(near(FollowAlong.scrollDelta(onScreen: -100, viewport: vp), -100 - 0.35 * vp))
        #expect(near(FollowAlong.scrollDelta(onScreen: 1.5 * vp, viewport: vp), 1.15 * vp))
        #expect(FollowAlong.scrollDelta(onScreen: 100, viewport: 0) == nil)
        #expect(FollowAlong.clampOffset(-50, minOffset: -20, maxOffset: 900) == -20)
        #expect(FollowAlong.clampOffset(950, minOffset: -20, maxOffset: 900) == 900)
        #expect(FollowAlong.clampOffset(300, minOffset: 0, maxOffset: -100) == 0)   // içerik ekrandan kısa
    }

    @Test func attributedKeepsTextAndMarksCurrentWord() {
        let text = "Bir  çocuğun koşması."
        let words = FollowAlong.words(in: text)
        let attr = FollowAlong.attributed(text, words: words, current: 1, highlight: .yellow, readColor: .primary, upcoming: .secondary)
        #expect(String(attr.characters) == text)   // boşluklar korunur
        let highlighted = attr.runs.filter { $0.backgroundColor != nil }.map { String(attr[$0.range].characters) }
        #expect(highlighted == ["çocuğun"])
    }
}

@MainActor
struct ConceptMapLayoutTests {
    @Test func canvasFitsScreenWidthAndGrowsVertically() {
        let narrow = ConceptMapView.canvasSize(width: 320, count: 6)
        #expect(narrow.width == 320 && narrow.height >= 320)          // ekran genişliğinde, en az kare
        let many = ConceptMapView.canvasSize(width: 320, count: 25)
        #expect(many.width == 320 && many.height > narrow.height && many.height <= 960)   // dikeyde uzar, 3 ekranı geçmez
        #expect(narrow.height >= 352)   // dar ekranda da düğümlere yer kalsın
        // Yerleşim tuvalin içinde kalır (yatay taşma yok).
        let concepts = (0..<12).map { Concept(name: "Kavram \($0)", definition: "", related: ["Kavram \(($0 + 1) % 12)"], sourcePage: nil) }
        let size = ConceptMapView.canvasSize(width: 320, count: concepts.count)
        let layout = ConceptLayout.compute(concepts, in: size)
        #expect(layout.count == 12)
        #expect(layout.values.allSatisfy { $0.x >= 0 && $0.x <= size.width && $0.y >= 0 && $0.y <= size.height })
    }
}
