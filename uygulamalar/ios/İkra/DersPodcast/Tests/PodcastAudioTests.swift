import AVFoundation
import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Ikra

// P4: okunuş, telaffuz, mastering, düşünme payı, hizalama, kalite kapısı, sahne kopyaları.

private let rate = 24_000

private func tone(_ seconds: Double, amplitude: Double = 9000, hz: Double = 220, sampleRate: Int = rate) -> [Int16] {
    (0..<Int(seconds * Double(sampleRate))).map { Int16(amplitude * sin(2 * .pi * hz * Double($0) / Double(sampleRate))) }
}

private func silence(_ seconds: Double, sampleRate: Int = rate) -> [Int16] {
    Array(repeating: 0, count: Int(seconds * Double(sampleRate)))
}

private func turn(_ speaker: Speaker, _ text: String, think: Double? = nil) -> ScriptTurn {
    ScriptTurn(speaker: speaker, text: text, style: "", sourcePage: nil, think: think)
}

private func tempDir() throws -> URL {
    let dir = URL.temporaryDirectory.appending(path: "p4-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func writeWAV(_ samples: [Int16], _ url: URL, sampleRate: Int = rate) throws -> URL {
    try WAV.encode(PCMClip(samples: samples, sampleRate: sampleRate)).write(to: url)
    return url
}

private func fileSeconds(_ url: URL) throws -> Double {
    let file = try AVAudioFile(forReading: url)
    return Double(file.length) / file.fileFormat.sampleRate
}

// MARK: - #11 Türkçe okunuş

struct SpeakableTextTests {
    private struct Vectors: Decodable { struct Vector: Decodable { var `in`: String; var out: String }; var vectors: [Vector] }

    @Test func sharedVectorsPass() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "docs/spoken-tr-vectors.json")
        let data = try Data(contentsOf: url)
        let vectors = try JSONDecoder().decode(Vectors.self, from: data).vectors
        #expect(vectors.count >= 30)
        for v in vectors {
            #expect(SpeakableText.spoken(v.in, language: .tr) == v.out, "\(v.in)")
        }
    }

    @Test(arguments: [
        ("Hücrelerin %3,5'i bölünür.", "Hücrelerin yüzde üç virgül beşi bölünür."),
        ("Ders 14:30'da başlar.", "Ders on dört otuzda başlar."),
        ("Sürüm 2.5 çıktı", "Sürüm iki nokta beş çıktı"),
        ("B12 vitamini", "B on iki vitamini"),
        ("1/2 oranında", "ikide bir oranında"),
        ("(1990)", "(bin dokuz yüz doksan)"),
        ("10³ hücre", "on üzeri üç hücre"),
        ("Sonuç 42.", "Sonuç kırk iki."),
        ("Cevap 5. Şimdi devam", "Cevap beş. Şimdi devam"),
        ("1. Dünya Savaşı", "Birinci Dünya Savaşı"),
        // Sunucuyla aynı kural (spoken.test.ts): bağlaç, kısaltma ve cümle içindeki addan sonra sıra sayısı.
        ("Bu dönemde Atatürk 1. Meclis'i açtı.", "Bu dönemde Atatürk Birinci Meclis'i açtı."),
        ("TBMM 2. Dönem", "TBMM İkinci Dönem"),
        ("1. ve 2. Dünya Savaşı", "birinci ve İkinci Dünya Savaşı"),
        ("sonuç, 2. Sonra", "sonuç, iki. Sonra"),
        ("XIX. yüzyılda", "on dokuzuncu yüzyılda"),
        ("CD. Sonra", "CD. Sonra"),
        ("H₂SO₄ asittir", "ha iki se o dört asittir"),
        ("5 m koştu", "beş metre koştu"),
        ("m harfi", "m harfi"),
        ("2 000", "iki sıfır sıfır sıfır"),
        ("007 numara", "sıfır sıfır yedi numara"),
        ("Saat 9.30'da", "Saat dokuz otuzda"),
        ("Saat 14.00", "Saat on dört"),
        ("19.05.2024 tarihinde", "on dokuz Mayıs iki bin yirmi dört tarihinde"),
        ("M.Ö. 500 yılında", "milattan önce beş yüz yılında"),
        ("elma, armut vb. meyveler", "elma, armut ve benzeri meyveler"),
        ("Dr. Ayşe", "Doktor Ayşe"),
        ("%12,5 artış", "yüzde on iki virgül beş artış"),
        ("% 15", "yüzde on beş"),
        ("5 km'den", "beş kilometreden"),
        ("0,05", "sıfır virgül sıfır beş"),
        ("2 ± 0,5", "iki artı eksi sıfır virgül beş"),
        ("3×4", "üç çarpı dört"),
        ("XX. yüzyıl", "yirminci yüzyıl"),
        ("2.000.000.000", "iki milyar"),
        ("4'ü", "dördü"),
        ("Merhaba dünya", "Merhaba dünya"),
    ])
    func extraReadings(input: String, expected: String) {
        #expect(SpeakableText.spoken(input, language: .tr) == expected)
    }

    @Test func numbersAndOrdinals() {
        #expect(TurkishReading.cardinal("0") == ["sıfır"])
        #expect(TurkishReading.cardinal("1000").joined(separator: " ") == "bin")
        #expect(TurkishReading.cardinal("1100").joined(separator: " ") == "bin yüz")
        #expect(TurkishReading.cardinal("2000000001").joined(separator: " ") == "iki milyar bir")
        #expect(TurkishReading.cardinal("100100").joined(separator: " ") == "yüz bin yüz")
        let ordinals = ["bir": "birinci", "iki": "ikinci", "üç": "üçüncü", "dört": "dördüncü", "altı": "altıncı",
                        "dokuz": "dokuzuncu", "kırk": "kırkıncı", "yüz": "yüzüncü", "milyon": "milyonuncu"]
        for (word, ordinal) in ordinals { #expect(TurkishReading.ordinal(word) == ordinal) }
        #expect(TurkishReading.locative("altı") == "altıda")
        #expect(TurkishReading.locative("kırk") == "kırkta")
        #expect(TurkishReading.romanValue("XIV") == 14)
        #expect(TurkishReading.romanValue("IIII") == nil)
        #expect(TurkishReading.romanValue("MIX") == nil)
    }

    @Test func englishIsLeftAlone() {
        #expect(SpeakableText.spoken("In 1990 we had 5 km", language: .en) == "In 1990 we had 5 km")
    }
}

// MARK: - #12 Katlama ve sözlük

struct PronunciationFoldTests {
    @Test func foldsTurkishAndEnglishIs() {
        #expect(TurkishFold.fold("İstanbul'da") == "istanbul'da")
        #expect(TurkishFold.fold("ISTANBUL'DA") == "istanbul'da")
        #expect(TurkishFold.fold("ılık") == "ilik")
        #expect(TurkishFold.fold("IŞIK") == "işik")
        #expect(TurkishFold.fold("Iron") == "iron")
        #expect(TurkishFold.fold("IRON") == TurkishFold.fold("iron"))
        #expect(TurkishFold.fold("İ").count == 1)
        #expect(TurkishFold.fold("ÇĞÖÜŞ") == "çğöüş")
    }

    @Test func pronunciationIdsUseFold() {
        #expect(Pronunciation(from: "İyon", to: "i-yon").id == Pronunciation(from: "IYON", to: "x").id)
        #expect(Pronunciation(from: "ıyon", to: "x").id == Pronunciation(from: "iyon", to: "x").id)
    }

    @Test func setDeduplicatesAcrossDottedI() {
        var list = Pronunciations.updated([], from: "İyon", to: "i-yon")
        list = Pronunciations.updated(list, from: "IYON", to: "iy-yon")
        list = Pronunciations.updated(list, from: "Iron", to: "ay-ın")
        #expect(list.count == 2)
        #expect(Pronunciations.entry(for: "iyon", in: list)?.to == "iy-yon")
        #expect(Pronunciations.entry(for: "IRON", in: list)?.to == "ay-ın")
        list = Pronunciations.updated(list, from: "iyon", to: "")
        #expect(list.count == 1)
        // Dolu sözlükte yeni kelime eklenmez (en eski kayıt sessizce düşmez); var olan güncellenir.
        let many = (0..<45).reduce([Pronunciation]()) { Pronunciations.updated($0, from: "k\($1)", to: "x") }
        #expect(many.count == Pronunciations.limit)
        #expect(many.first?.from == "k39")
        #expect(Pronunciations.entry(for: "k0", in: many) != nil)
        #expect(!Pronunciations.canAdd("yeni", to: many))
        #expect(Pronunciations.canAdd("K0", to: many))
        let updated = Pronunciations.updated(many, from: "K0", to: "ke-sıfır")
        #expect(updated.count == Pronunciations.limit && updated.first?.to == "ke-sıfır")
        #expect(Pronunciations.updated(many, from: "k5", to: "").count == Pronunciations.limit - 1)
    }

    /// Eski sürüm `lowercased()` kimliğiyle "İyon" ve "iyon"u ayrı saklamıştı: okurken ilk kayıt kalır, temiz liste
    /// geri yazılır; liste kimlikleri tekil olur (ForEach/onDelete karışmaz), sunucuya tek kayıt gider.
    @Test func legacyDuplicatesAreMergedOnRead() throws {
        let suite = "p4-pron-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = [Pronunciation(from: "İksiyon", to: "ik-si-yon"), Pronunciation(from: "iksiyon", to: "eski"),
                      Pronunciation(from: "IKSIYON", to: "daha eski"), Pronunciation(from: "zebercet", to: "ze-ber-cet"),
                      Pronunciation(from: "  ", to: "boş")]
        defaults.set(try JSONEncoder().encode(legacy), forKey: Pronunciations.key)
        let list = Pronunciations.load(from: defaults)
        #expect(list.map(\.from) == ["İksiyon", "zebercet"])
        #expect(Set(list.map(\.id)).count == list.count)
        #expect(Pronunciations.sanitized(list).count == 2)
        // Temiz liste kalıcı: ikinci okuma aynı, saklanan veri de ayıklanmış.
        let stored = try JSONDecoder().decode([Pronunciation].self, from: try #require(defaults.data(forKey: Pronunciations.key)))
        #expect(stored.map(\.from) == ["İksiyon", "zebercet"])
        #expect(Pronunciations.deduplicated(stored) == stored)
    }

    @Test func entriesRespectServerLengthLimits() {
        let longWord = String(repeating: "ş", count: 70)
        let longSpoken = String(repeating: "ı", count: 130)
        let list = Pronunciations.updated([], from: "  \(longWord)  ", to: longSpoken)
        #expect(list.first?.from.utf16.count == Pronunciations.maxFromLength)
        #expect(list.first?.to.utf16.count == Pronunciations.maxToLength)
        #expect(list.allSatisfy(Pronunciations.isValid))
        // UTF-16 sayımı: emoji (2 birim) ortadan bölünmez.
        #expect(Pronunciations.clipped("ab😀", to: 3) == "ab")
        #expect(Pronunciations.clipped("İyon", to: 60) == "İyon")
        // Elle bozulmuş/eski kayıtlar istekten düşer.
        let stored = [Pronunciation(from: "sklera", to: "sk-le-ra"), Pronunciation(from: longWord, to: "x"),
                      Pronunciation(from: "iyon", to: longSpoken), Pronunciation(from: "   ", to: "x")]
        #expect(Pronunciations.sanitized(stored).map(\.from) == ["sklera"])
        let script = PodcastScript(title: "T", summary: "", keyPoints: [], chapters: [
            ScriptChapter(title: "Bir", scenes: [ScriptScene(turns: [turn(.a, "Sklera")])])], sourceNotes: "")
        #expect(PronunciationSuggestionsSheet.request(script: script, dictionary: stored).known == ["sklera", "iyon", "   "])
    }

    @Test func dictionaryMatchesFoldedWithWordBoundaries() {
        let dict = [Pronunciation(from: "İyon", to: "i-yon"), Pronunciation(from: "İstanbul", to: "is-tan-bul"),
                    Pronunciation(from: "Iron", to: "ay-ın")]
        #expect(SpeakableText.applyDictionary("IYON ve iyon ile İyonlar", dictionary: dict) == "i-yon ve i-yon ile İyonlar")
        #expect(SpeakableText.applyDictionary("İstanbul'da ve ISTANBUL'DA", dictionary: dict) == "is-tan-bul'da ve is-tan-bul'DA")
        #expect(SpeakableText.applyDictionary("iron, Iron; IRON.", dictionary: dict) == "ay-ın, ay-ın; ay-ın.")
        #expect(SpeakableText.applyDictionary("Ironman", dictionary: dict) == "Ironman")
    }

    @Test func longestEntryWinsAndSinglePass() {
        let dict = [Pronunciation(from: "Krebs", to: "kreps"), Pronunciation(from: "Krebs döngüsü", to: "kreps çevrimi"),
                    Pronunciation(from: "kreps", to: "YANLIŞ")]
        #expect(SpeakableText.applyDictionary("Krebs döngüsü ve Krebs", dictionary: dict) == "kreps çevrimi ve kreps")
    }

    @Test func prepareAppliesDictionaryBeforeReadingAndMapsWords() {
        let dict = [Pronunciation(from: "CO₂", to: "karbondioksit")]
        let result = SpeakableText.prepare([turn(.a, "CO₂ oranı %15 arttı."), turn(.b, "II. Dünya")], language: .tr, dictionary: dict)
        #expect(result.turns[0].text == "karbondioksit oranı yüzde on beş arttı.")
        #expect(result.wordMap[0] == [0, 1, 2, 2, 2, 3])
        #expect(result.turns[1].text == "İkinci Dünya")
        #expect(result.wordMap[1] == [0, 1])
        // Sözlük olmadan formül okunur.
        #expect(SpeakableText.prepare([turn(.a, "CO₂ oranı")], language: .tr, dictionary: []).turns[0].text == "ce o iki oranı")
        // Çok kelimeli karşılık aynı orijinal kelimeye bağlanır.
        let multi = SpeakableText.prepare([turn(.a, "sklera sert")], language: .tr, dictionary: [Pronunciation(from: "sklera", to: "sık le ra")])
        #expect(multi.wordMap[0] == [0, 0, 0, 1])
        #expect(multi.turns[0].speaker == .a)
    }
}

// MARK: - #15 Mastering ve ses kimliği

struct MasteringTests {
    private func sine(_ hz: Double, amplitude: Double, seconds: Double, sampleRate: Int) -> PCMClip {
        PCMClip(samples: (0..<Int(seconds * Double(sampleRate))).map { Int16(amplitude * 32767 * sin(2 * .pi * hz * Double($0) / Double(sampleRate))) },
                sampleRate: sampleRate)
    }

    private func noise(_ amplitude: Double, seconds: Double, sampleRate: Int) -> PCMClip {
        var state: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53) * 2 - 1
        }
        return PCMClip(samples: (0..<Int(seconds * Double(sampleRate))).map { _ in Int16(amplitude * 32767 * (next() + next() + next()) / 3) },
                       sampleRate: sampleRate)
    }

    @Test(arguments: [24_000, 48_000])
    func meterMatchesBS1770ReferenceSine(sampleRate: Int) throws {
        // 0 dBFS 997 Hz sinüs = −3,01 LUFS (mono); −6 dB genlik → −9,03.
        let measured = try #require(Mastering.loudness(sine(997, amplitude: 0.5, seconds: 5, sampleRate: sampleRate)))
        #expect(abs(measured - (-3.01 + 20 * log10(0.5))) < 0.3)
    }

    @Test(arguments: [24_000, 48_000])
    func mastersSineAndNoiseToTarget(sampleRate: Int) throws {
        for clip in [sine(997, amplitude: 0.05, seconds: 4, sampleRate: sampleRate), sine(997, amplitude: 0.7, seconds: 4, sampleRate: sampleRate),
                     noise(0.05, seconds: 4, sampleRate: sampleRate), noise(0.6, seconds: 4, sampleRate: sampleRate)] {
            let out = Mastering.master(clip)
            let lufs = try #require(Mastering.loudness(out))
            #expect(abs(lufs - Mastering.targetLUFS) <= 0.5, "\(lufs)")
            #expect(Mastering.samplePeakDBFS(out) <= Mastering.ceilingDBFS + 0.01)
            #expect(out.samples.count == clip.samples.count)
        }
    }

    @Test func limiterKeepsSamplePeakUnderCeiling() {
        // Sessiz konuşma + seyrek gür tıklar: kazanç büyür, tepeler sınırlanmalı.
        var samples = tone(4, amplitude: 600, hz: 300)
        for k in stride(from: 1000, to: samples.count, by: 9000) { samples[k] = 30_000; samples[k + 1] = -30_000 }
        let out = Mastering.master(PCMClip(samples: samples, sampleRate: rate))
        #expect(Mastering.samplePeakDBFS(out) <= Mastering.ceilingDBFS + 0.01)
        let square = PCMClip(samples: (0..<48_000).map { ($0 / 40) % 2 == 0 ? 32_000 : -32_000 }, sampleRate: rate)
        #expect(Mastering.samplePeakDBFS(Mastering.master(square)) <= Mastering.ceilingDBFS + 0.01)
    }

    @Test func highPassRemovesRumble() {
        let rumble = sine(30, amplitude: 0.5, seconds: 2, sampleRate: rate)
        var x = Mastering.floats(rumble)
        Biquad.highPass(hz: Mastering.highPassHz, sampleRate: Double(rate)).process(&x)
        let rms = (x.suffix(24_000).reduce(0) { $0 + Double($1 * $1) } / 24_000).squareRoot()
        #expect(rms < 0.5 / 2.squareRoot() * 0.2)
    }

    @Test func silenceIsLeftSilent() {
        let out = Mastering.master(PCMClip(samples: silence(1), sampleRate: rate))
        #expect(out.samples.allSatisfy { $0 == 0 })
        #expect(Mastering.loudness(out) == nil)
    }

    @Test func identitiesProduceMusicExceptNone() throws {
        for identity in [SoundIdentity.sade, .sicak, .odak] {
            let intro = try #require(identity.intro(sampleRate: rate))
            #expect(intro.duration > identity.introLead + 2)
            let lufs = try #require(Mastering.loudness(intro))
            #expect(abs(lufs - (-23)) < 1)
            #expect(identity.transition(sampleRate: rate) != nil)
            #expect(identity.outro(sampleRate: rate) != nil)
        }
        #expect(SoundIdentity.yok.intro(sampleRate: rate) == nil)
        #expect(SoundIdentity.yok.transition(sampleRate: rate) == nil)
        #expect(SoundIdentity.yok.outro(sampleRate: rate) == nil)
    }

    @Test func introMusicDucksUnderSpeech() {
        let speech = PCMClip(samples: tone(3, amplitude: 6000, hz: 200), sampleRate: rate)
        let music = tone(3, amplitude: 4000, hz: 1000)[...]
        let mixed = SoundIdentity.mixUnderSpeech(speech, music: music)
        // 0,5 sn sonra müzik ≈ −18 dB: karışım − konuşma = kısılmış müzik.
        let residual = (12_000..<24_000).map { Double(Int(mixed.samples[$0]) - Int(speech.samples[$0])) }
        let rms = (residual.reduce(0) { $0 + $1 * $1 } / Double(residual.count)).squareRoot()
        let expected = 4000 / 2.squareRoot() * pow(10, -18.0 / 20)
        #expect(abs(20 * log10(rms / expected)) < 1)
    }

    @Test func identityOptions() {
        // Üretimdeki birleştirmeyle aynı kural: tasarım kapalıysa müzik yok; kimlik bölüme özel ya da genel.
        #expect(SoundIdentity.options(for: nil, designEnabled: false, fallback: .yok).design == false)
        #expect(SoundIdentity.options(for: "sicak", designEnabled: true, fallback: .sade).identity == .sicak)
        #expect(SoundIdentity.options(for: nil, designEnabled: true, fallback: .odak).identity == .odak)
        #expect(SoundIdentity.options(for: "bozuk", designEnabled: true, fallback: .sade).identity == .sade)
        #expect(SoundIdentity.resolve("odak") == .odak)
        #expect(SoundIdentity.resolve("bozuk") == SoundIdentity.current)
    }

    @Test func thinkToneIsSoftAndCached() throws {
        let clip = ThinkTone.clip(sampleRate: rate)
        #expect(abs(clip.duration - ThinkTone.duration) < 0.001)
        let rms = (clip.samples.reduce(0.0) { $0 + pow(Double($1) / 32767, 2) } / Double(clip.samples.count)).squareRoot()
        #expect(abs(20 * log10(rms) - ThinkTone.levelDBFS) < 0.5)
        #expect(clip.samples.first.map { abs(Int($0)) < 50 } == true && clip.samples.last.map { abs(Int($0)) < 50 } == true)
        let url = ThinkTone.fileURL()
        let parsed = try WAV.parse(Data(contentsOf: url))
        #expect(parsed.sampleRate == 24_000)
        #expect(abs(parsed.duration - ThinkTone.duration) < 0.001)
    }
}

// MARK: - #23 Düşünme payı ve sahne başlangıçları

struct ThinkPauseTests {
    @Test func pauseSitsOnRealSilenceAfterQuestion() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try writeWAV(tone(2) + silence(0.4) + tone(2), dir.appending(path: "a.wav"))
        let output = dir.appending(path: "o.m4a")
        let timeline = try await AudioStitcher.stitch(
            scenes: [.init(url: a, chapterIndex: 0, turns: [turn(.a, "Sence neden?", think: 5), turn(.b, "Çünkü zar seçicidir.")])],
            chapterTitles: ["Bir"], output: output, design: false)
        let pause = try #require(timeline.thinkPauses?.first)
        #expect(timeline.thinkPauses?.count == 1)
        #expect(pause.turnID == 0)
        #expect(abs(pause.start - 2.2) < 0.03)
        #expect(abs(pause.end - pause.start - 5) < 0.01)
        #expect(abs(timeline.turns[0].end - pause.start) < 0.001)
        #expect(abs(timeline.turns[1].start - pause.end) < 0.001)
        #expect(abs(timeline.duration - 9.4) < 0.05)
        #expect(abs(try fileSeconds(output) - timeline.duration) < 0.15)
        #expect(timeline.sceneStarts == [0])
    }

    @Test func pauseAfterLastTurnPrecedesNextScene() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try writeWAV(tone(2) + silence(0.4) + tone(1.5), dir.appending(path: "a.wav"))
        let b = try writeWAV(tone(2), dir.appending(path: "b.wav"))
        let timeline = try await AudioStitcher.stitch(scenes: [
            .init(url: a, chapterIndex: 0, turns: [turn(.a, "Hücre zarını anlattık."), turn(.b, "Peki zar ne işe yarar?", think: 12)]),
            .init(url: b, chapterIndex: 0, turns: [turn(.a, "Madde geçişini düzenler.")]),
        ], chapterTitles: ["Bir"], output: dir.appending(path: "o.m4a"), design: false)
        let pause = try #require(timeline.thinkPauses?.first)
        #expect(pause.turnID == 1)
        #expect(abs(pause.start - timeline.turns[1].end) < 0.001)
        #expect(abs(pause.end - pause.start - AudioStitcher.thinkRange.upperBound) < 0.01)   // 12 → 8 sn
        #expect(abs(timeline.turns[2].start - (pause.end + AudioStitcher.sceneGap)) < 0.01)
        #expect(timeline.sceneStarts?.count == 2)
        #expect(abs((timeline.sceneStarts?[1] ?? 0) - timeline.turns[2].start) < 0.001)
    }

    @Test func lowConfidenceBoundarySkipsPause() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try writeWAV(tone(5), dir.appending(path: "a.wav"))   // sessizlik yok: sınır tahmin
        let timeline = try await AudioStitcher.stitch(
            scenes: [.init(url: a, chapterIndex: 0, turns: [turn(.a, "Sence neden?", think: 4), turn(.b, "Çünkü öyle.")])],
            chapterTitles: ["Bir"], output: dir.appending(path: "o.m4a"), design: false)
        #expect(timeline.thinkPauses == [])
        #expect(abs(timeline.duration - 5) < 0.05)
    }

    @Test func layoutClampsAndSnaps() {
        let clip = PCMClip(samples: tone(2) + silence(0.3) + tone(2), sampleRate: rate)
        let short = AudioStitcher.layout(clip, turns: [turn(.a, "Soru?", think: 1), turn(.b, "Cevap")])
        #expect(short.pauses.count == 1)
        #expect(abs(short.pauses[0].end - short.pauses[0].start - 3) < 0.01)
        #expect(abs(short.clip.duration - (clip.duration + 3)) < 0.01)
        #expect(abs(short.shifted(3.0) - 6.0) < 0.01)
        #expect(abs(short.shifted(1.0) - 1.0) < 0.001)
        // Sahne düzenlemede son turun payı eklenmez.
        let trailing = AudioStitcher.layout(clip, turns: [turn(.a, "Bilgi"), turn(.b, "Soru?", think: 5)], trailingPause: false)
        #expect(trailing.pauses.isEmpty)
        #expect(trailing.clip.samples.count == clip.samples.count)
    }

    /// Bulgu: `turnRanges` sınırı en yakın sessizliğe (burada cevaptaki virgül) oturtur. Gerçek sınır pencere
    /// içindeyse ve en uzun sessizlikse pay oraya gider; virgüle asla gitmez.
    @Test func commaPauseNearEstimateDoesNotGetThePause() {
        let question = turn(.a, "Peki sence hücre zarı neden bu kadar önemli bir yapı?", think: 4)
        let answer = turn(.b, "Evet, çünkü seçicidir.")
        // Soru 1,5 sn | gerçek sınır 0,4 sn | "Evet" 0,4 sn | virgül 0,18 sn | cevap 1,5 sn.
        let clip = PCMClip(samples: tone(1.5) + silence(0.4) + tone(0.4) + silence(0.18) + tone(1.5), sampleRate: rate)
        let estimate = SilenceAligner.turnRanges(clip: clip, characterCounts: [question.text.count, answer.text.count])[0].end
        #expect(abs(estimate - 2.39) < 0.05)   // tahmin virgüle oturdu
        let placed = AudioStitcher.layout(clip, turns: [question, answer])
        let pause = placed.pauses.first
        #expect(placed.pauses.count == 1)
        #expect(abs((pause?.start ?? 0) - 1.7) < 0.03)   // gerçek sınırın ortası
        #expect(abs(placed.ranges[0].end - 1.7) < 0.03)
    }

    /// Gerçek sınır pencerenin dışında kalınca elde yalnız virgül (ya da daha kısa bir duraklama) var: pay eklenmez.
    @Test(arguments: [0.18, 0.3])
    func onlyAnswerPauseInWindowSkipsThePause(comma: Double) {
        let question = turn(.a, "Peki sence hücre zarı neden bu kadar önemli bir yapı?", think: 4)
        let answer = turn(.b, "Evet, çünkü seçicidir.")
        let clip = PCMClip(samples: tone(1.5) + silence(0.4) + tone(1.0) + silence(comma) + tone(1.5), sampleRate: rate)
        let placed = AudioStitcher.layout(clip, turns: [question, answer])
        #expect(placed.pauses.isEmpty)
        #expect(placed.clip.samples.count == clip.samples.count)
    }

    /// Kalite kapısının kelime zamanları varsa sınırı onlar belirler; uyuşmazlarsa pay eklenmez.
    @Test func gateWordTimesDecideTheBoundary() {
        let question = turn(.a, "Peki sence hücre zarı neden bu kadar önemli bir yapı?", think: 4)
        let answer = turn(.b, "Evet, çünkü seçicidir.")
        let clip = PCMClip(samples: tone(1.5) + silence(0.4) + tone(1.0) + silence(0.18) + tone(1.5), sampleRate: rate)
        let agreeing = AudioStitcher.layout(clip, turns: [question, answer], wordTimes: [[0, 0.5, 1.0], [1.9, 2.95, 3.4]])
        #expect(agreeing.pauses.count == 1)
        #expect(abs((agreeing.pauses.first?.start ?? 0) - 1.7) < 0.03)
        // Cevabın ilk kelimesi sessizlik olmayan bir yerde: sınırdan emin değiliz.
        let disagreeing = AudioStitcher.layout(clip, turns: [question, answer], wordTimes: [[0, 0.5, 1.0], [2.5, 3.0]])
        #expect(disagreeing.pauses.isEmpty)
        // Sorunun son kelimesinden önceki sessizlik sınır olamaz.
        let early = AudioStitcher.layout(clip, turns: [question, answer], wordTimes: [[0, 0.5, 2.2], [1.9, 3.1]])
        #expect(early.pauses.isEmpty)
    }

    @Test func removingLastChapterAlsoCutsItsTrailingPause() {
        let turns = [TimedTurn(id: 0, chapterIndex: 0, speaker: .a, text: "", sourcePage: nil, start: 0, end: 9),
                     TimedTurn(id: 1, chapterIndex: 1, speaker: .a, text: "", sourcePage: nil, start: 10, end: 13),
                     TimedTurn(id: 2, chapterIndex: 1, speaker: .b, text: "", sourcePage: nil, start: 13, end: 15)]
        let timeline = Timeline(chapters: [TimedChapter(id: 0, title: "Bir", start: 0), TimedChapter(id: 1, title: "İki", start: 10)],
                                turns: turns, duration: 25,
                                thinkPauses: [ThinkPause(turnID: 0, start: 9, end: 9.5), ThinkPause(turnID: 2, start: 15, end: 20)],
                                sceneStarts: [0, 10])
        #expect(AudioEditor.chapterCut(timeline, chapterIndex: 1) == 10...20)   // kapanış (20…25) korunur
        #expect(AudioEditor.chapterCut(timeline, chapterIndex: 0) == 0...10)
        let noPause = Timeline(chapters: timeline.chapters, turns: turns, duration: 25, thinkPauses: nil, sceneStarts: nil)
        #expect(AudioEditor.chapterCut(noPause, chapterIndex: 1) == 10...15)
        #expect(AudioEditor.chapterCut(timeline, chapterIndex: 5) == nil)
    }

    @Test func sceneStartsFollowGapsAndChapters() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = try [2.0, 3.0, 1.0].enumerated().map { try writeWAV(tone($1), dir.appending(path: "\($0).wav")) }
        let timeline = try await AudioStitcher.stitch(scenes: [
            .init(url: urls[0], chapterIndex: 0, turns: [turn(.a, "a")]),
            .init(url: urls[1], chapterIndex: 0, turns: [turn(.b, "b")]),
            .init(url: urls[2], chapterIndex: 1, turns: [turn(.a, "c")]),
        ], chapterTitles: ["Bir", "İki"], output: dir.appending(path: "o.m4a"), design: false)
        let starts = try #require(timeline.sceneStarts)
        #expect(starts.count == 3)
        #expect(starts[0] == 0)
        #expect(abs(starts[1] - (2 + AudioStitcher.sceneGap)) < 0.01)
        #expect(abs(starts[2] - (5 + AudioStitcher.sceneGap + AudioStitcher.chapterGap)) < 0.01)
        #expect(abs(starts[2] - timeline.chapters[1].start) < 0.001)
    }

    @Test func gateWordTimesAreShiftedIntoWordTimesFile() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try writeWAV(silence(0.5) + tone(2), dir.appending(path: "a.wav"))
        var input = AudioStitcher.SceneInput(url: a, chapterIndex: 0, turns: [turn(.a, "Merhaba dünya")])
        input.wordTimes = [[0.6, 1.0]]
        _ = try await AudioStitcher.stitch(scenes: [input], chapterTitles: ["Bir"], output: dir.appending(path: "o.m4a"), design: false)
        let times = try #require(WordSync.load(from: dir.appending(path: WordSync.fileName)))
        #expect(times.keys.sorted() == [0])
        #expect(abs(times[0]![0] - 0.2) < 0.001)   // 0,4 sn baş kırpıldı
        #expect(abs(times[0]![1] - 0.6) < 0.001)
        // Kelime zamanı olmadan yeniden birleştirme eski dosyayı siler.
        _ = try await AudioStitcher.stitch(scenes: [.init(url: a, chapterIndex: 0, turns: [turn(.a, "Merhaba dünya")])],
                                           chapterTitles: ["Bir"], output: dir.appending(path: "o.m4a"), design: false)
        #expect(WordSync.load(from: dir.appending(path: WordSync.fileName)) == nil)
    }

    @Test func wordTimesAreStampedWithTheirAudio() async throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let episodeDir = root.appending(path: id.uuidString)
        try FileManager.default.createDirectory(at: episodeDir, withIntermediateDirectories: true)
        let audio = episodeDir.appending(path: "podcast.m4a")
        let a = try writeWAV(silence(0.5) + tone(2), root.appending(path: "a.wav"))
        var input = AudioStitcher.SceneInput(url: a, chapterIndex: 0, turns: [turn(.a, "Merhaba dünya")])
        input.wordTimes = [[0.6, 1.0]]
        _ = try await AudioStitcher.stitch(scenes: [input], chapterTitles: ["Bir"], output: audio, design: false)
        #expect(WordSync.stamp(at: WordSync.fileURL(id, root: root)) == WordSync.AudioStamp(of: audio))
        #expect(WordSync.load(episodeID: id, root: root) != nil)
        // Üretim sonrası "ses değişti" bildirimi aynı sese ait (kalite kapısının) zamanları silmez.
        WordSync.invalidate(id, root: root)
        #expect(WordSync.load(episodeID: id, root: root) != nil)

        // Ses değişti (sahne düzenleme: atomik değiştirme): eski zamanlar okunmaz, invalidate siler.
        let stale = try #require(WordSync.AudioStamp(of: audio))
        let replacement = root.appending(path: "new.m4a")
        try FileManager.default.copyItem(at: audio, to: replacement)
        try Data([0, 1, 2]).write(to: replacement)
        _ = try FileManager.default.replaceItemAt(audio, withItemAt: replacement)
        #expect(WordSync.load(episodeID: id, root: root) == nil)
        WordSync.invalidate(id, root: root)
        #expect(!FileManager.default.fileExists(atPath: WordSync.fileURL(id, root: root).path))

        // Eski sesle başlamış hazırlık sonucu yazılmaz; güncel sesle yazılır.
        #expect(!WordSync.commit([0: [0.1]], episodeID: id, audioURL: audio, stamp: stale, root: root))
        #expect(!FileManager.default.fileExists(atPath: WordSync.fileURL(id, root: root).path))
        let current = try #require(WordSync.AudioStamp(of: audio))
        #expect(WordSync.commit([0: [0.1]], episodeID: id, audioURL: audio, stamp: current, root: root))
        #expect(WordSync.load(episodeID: id, root: root) == [0: [0.1]])

        // Silinmiş bölüm: klasör yeniden oluşturulmaz.
        let gone = UUID()
        #expect(!WordSync.save([0: [0.1]], to: WordSync.fileURL(gone, root: root), audio: current))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: gone.uuidString).path))

        // Eski (damgasız) biçim okunur ama bölüm için geçerli sayılmaz.
        try JSONEncoder().encode(["0": [0.5]]).write(to: WordSync.fileURL(id, root: root))
        #expect(WordSync.load(from: WordSync.fileURL(id, root: root)) == [0: [0.5]])
        #expect(WordSync.load(episodeID: id, root: root) == nil)
    }

    @Test func editorKeepsTrailingPauseAndRemovalShiftsPauses() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let s0 = try writeWAV(tone(2) + silence(0.4) + tone(1.5), dir.appending(path: "0.wav"))
        let s1 = try writeWAV(tone(2), dir.appending(path: "1.wav"))
        let s2 = try writeWAV(tone(2) + silence(0.4) + tone(1), dir.appending(path: "2.wav"))
        let script = PodcastScript(title: "T", summary: "", keyPoints: [], chapters: [
            ScriptChapter(title: "Bir", scenes: [ScriptScene(turns: [turn(.a, "Bilgi"), turn(.b, "Soru?", think: 4)]),
                                                 ScriptScene(turns: [turn(.a, "Cevap")])]),
            ScriptChapter(title: "İki", scenes: [ScriptScene(turns: [turn(.a, "Yeni soru?", think: 3), turn(.b, "Yanıt")])]),
        ], sourceNotes: "")
        let output = dir.appending(path: "podcast.m4a")
        let timeline = try await AudioStitcher.stitch(scenes: script.flatScenes.enumerated().map { i, item in
            AudioStitcher.SceneInput(url: [s0, s1, s2][i], chapterIndex: item.chapterIndex, turns: item.scene.turns)
        }, chapterTitles: ["Bir", "İki"], output: output, design: false)
        let pauses = try #require(timeline.thinkPauses)
        #expect(pauses.map(\.turnID) == [1, 3])

        // Sahne 0'ı tek tura indir: sondaki pay korunur, kimlikler kayar.
        let edited = try await AudioEditor.replaceScene(audio: output, timeline: timeline, script: script, sceneIndex: 0,
                                                        newTurns: [turn(.a, "Kısa soru?", think: 4)],
                                                        newClip: PCMClip(samples: tone(3), sampleRate: rate))
        let delta = edited.duration - timeline.duration
        let kept = try #require(edited.thinkPauses)
        #expect(kept.map(\.turnID) == [0, 2])
        #expect(abs(kept[0].start - edited.turns[0].end) < 0.05)
        #expect(abs(kept[1].start - (pauses[1].start + delta)) < 0.01)
        #expect(abs((edited.sceneStarts?[2] ?? 0) - ((timeline.sceneStarts?[2] ?? 0) + delta)) < 0.01)

        // Konu 0 silinince kalan payın kimliği ve zamanı kayar.
        let removed = try await AudioEditor.removeChapter(audio: output, timeline: timeline, chapterIndex: 0)
        let shift = removed.removed.upperBound - removed.removed.lowerBound
        #expect(removed.timeline.thinkPauses?.map(\.turnID) == [0])
        #expect(abs((removed.timeline.thinkPauses?[0].start ?? 0) - (pauses[1].start - shift)) < 0.01)
        #expect(removed.timeline.sceneStarts?.count == 1)
    }
}

// MARK: - #20/#13 Hizalama

struct WordAlignerTests {
    private func words(_ text: String, from start: Double = 0, step: Double = 0.4) -> [RecognizedWord] {
        text.split(separator: " ").enumerated().map { i, w in
            RecognizedWord(text: String(w), start: start + Double(i) * step, end: start + Double(i) * step + step * 0.8)
        }
    }

    @Test func alignsWithMissingAndExtraWords() {
        let expected = "hücre zarı seçici geçirgendir ve madde geçişini düzenler".split(separator: " ").map(String.init)
        let recognized = words("hücre zarı şey seçici geçirgendir madde geçişini düzenler")
        let matches = WordAligner.align(expected: expected, recognized: recognized.map(\.text))
        #expect(matches == [0, 1, 3, 4, nil, 5, 6, 7])
        let result = WordAligner.startTimes(expected: expected, recognized: recognized, span: 0...4)
        #expect(result.matched == 7)
        #expect(abs(result.times[2] - 1.2) < 0.001)
        // Eşleşmeyen "ve" komşu çapalar arasında.
        #expect(result.times[4] > result.times[3] && result.times[4] < result.times[5])
        #expect(zip(result.times, result.times.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func toleratesSuffixAndCaseDifferences() {
        #expect(WordAligner.similar(WordAligner.key("İstanbul'da"), WordAligner.key("istanbulda")))
        #expect(WordAligner.similar(WordAligner.key("geçirgendir"), WordAligner.key("geçirgendi")))
        #expect(!WordAligner.similar(WordAligner.key("ve"), WordAligner.key("de")))
        #expect(!WordAligner.similar(WordAligner.key("hücre"), WordAligner.key("madde")))
    }

    @Test func mapsRecognizedNumbersBackToOriginalWords() {
        let recognized = [RecognizedWord(text: "1990'da", start: 0.5, end: 1.7), RecognizedWord(text: "başladı", start: 1.8, end: 2.3)]
        let result = WordAligner.turnWordTimes([turn(.a, "1990'da başladı.")], language: .tr, dictionary: [],
                                               recognized: recognized, span: 0...3)
        #expect(result.times.count == 1)
        #expect(result.times[0].count == 2)
        #expect(abs(result.times[0][0] - 0.5) < 0.001)
        #expect(abs(result.times[0][1] - 1.8) < 0.001)
        #expect(result.coverage > 0.99)
    }

    @Test func coverageDropsWhenSentenceSkipped() {
        let text = "Mitoz bölünmede kromozom sayısı korunur. Mayozda ise yarıya iner ve çeşitlilik artar."
        let recognized = words("mitoz bölünmede kromozom sayısı korunur")
        let result = WordAligner.turnWordTimes([turn(.a, text)], language: .tr, dictionary: [], recognized: recognized, span: 0...6)
        #expect(result.coverage < SceneQualityGate.minCoverage)
        #expect(result.times[0].count == text.split(separator: " ").count)
        #expect(zip(result.times[0], result.times[0].dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func turnSpansClampTimesAndChunksSplit() {
        let recognized = words("bir iki üç dört", step: 1)
        let result = WordAligner.turnWordTimes([turn(.a, "bir iki"), turn(.b, "üç dört")], language: .tr, dictionary: [],
                                               recognized: recognized, span: 0...4, spans: [0...1.5, 2...4])
        #expect(result.times == [[0, 1], [2, 3]])

        let turns = (0..<5).map { TimedTurn(id: $0, chapterIndex: $0 < 4 ? 0 : 1, speaker: .a, text: "x", sourcePage: nil,
                                             start: Double($0) * 25, end: Double($0) * 25 + 24) }
        let chunks = WordSync.chunks(Timeline(chapters: [], turns: turns, duration: 124), maxSeconds: 60)
        #expect(chunks == [[0, 1], [2, 3], [4]])
    }

    @Test func splitsRecognizedRunsByCharacters() {
        let parts = SpeechAlignment.split("iki kelime", start: 1, end: 2)
        #expect(parts.count == 2)
        #expect(abs(parts[1].start - (1 + 3.0 / 9.0)) < 0.001)
    }
}

// MARK: - #13 Kalite kapısı

struct QualityGateTests {
    @Test func rateBoundsAtTheEdges() {
        let bounds = SceneQualityGate.rateBounds(.chirp)
        let chars = 100
        func reasons(_ seconds: Double) -> [String] {
            SceneQualityGate.cheapReasons(clip: PCMClip(samples: tone(seconds) + silence(0.2), sampleRate: rate), characters: chars, engine: .chirp)
        }
        // Kırpılan pay: +0,1 sn
        #expect(reasons(bounds.lowerBound * Double(chars) + 0.05).isEmpty)
        #expect(reasons(bounds.lowerBound * Double(chars) - 0.4).count == 1)
        #expect(reasons(bounds.upperBound * Double(chars) - 0.3).isEmpty)
        #expect(reasons(bounds.upperBound * Double(chars) + 0.4).count == 1)
        // Kısa metinde oran denetlenmez.
        #expect(SceneQualityGate.cheapReasons(clip: PCMClip(samples: tone(9) + silence(0.2), sampleRate: rate), characters: 20, engine: .chirp).isEmpty)
    }

    @Test func detectsCutTailSilenceAndStall() {
        #expect(SceneQualityGate.cutAtEnd(PCMClip(samples: tone(2), sampleRate: rate)))
        #expect(!SceneQualityGate.cutAtEnd(PCMClip(samples: tone(2) + silence(0.2), sampleRate: rate)))
        #expect(SceneQualityGate.cheapReasons(clip: PCMClip(samples: silence(2), sampleRate: rate), characters: 50, engine: .edge) == ["Ses boş."])
        let stall = PCMClip(samples: tone(2) + silence(3.2) + tone(2) + silence(0.2), sampleRate: rate)
        #expect(SceneQualityGate.cheapReasons(clip: stall, characters: 50, engine: .edge).contains("Seste uzun bir takılma var."))
    }

    @Test func recognitionHasDeadlineEvenIfWorkIgnoresCancellation() async {
        let start = Date.now
        await #expect(throws: SpeechAlignment.Failure.self) {
            _ = try await SpeechAlignment.withDeadline(seconds: 0.2) {
                try? await Task.sleep(for: .seconds(3))   // iptali yok sayan (takılan) model
                return [RecognizedWord(text: "geç", start: 0, end: 1)]
            }
        }
        #expect(Date.now.timeIntervalSince(start) < 1.5)
        let words = try? await SpeechAlignment.withDeadline(seconds: 5) { [RecognizedWord(text: "a", start: 0, end: 1)] }
        #expect(words?.count == 1)
        #expect(SpeechAlignment.timeout(forAudioSeconds: 10) == 120)
        #expect(SpeechAlignment.timeout(forAudioSeconds: 300) == 630)
    }

    @Test func coverageThreshold() {
        #expect(SceneQualityGate.asrReasons(coverage: 0.8, expectedWords: 50, recognizedWords: 50).isEmpty)
        #expect(SceneQualityGate.asrReasons(coverage: 0.79, expectedWords: 50, recognizedWords: 50).count == 1)
        #expect(SceneQualityGate.asrReasons(coverage: 0.95, expectedWords: 50, recognizedWords: 70).count == 1)
    }

    /// Dil tahmini yalnız dil verilmediğinde: tek "ö" (Schrödinger, Gödel) ya da kanıtsız kısa İngilizce satır Türkçe sayılmaz.
    @Test func languageGuessNeedsTurkishEvidence() {
        #expect(!WordSync.looksTurkish("Exactly. Great point!"))
        #expect(!WordSync.looksTurkish("Schrödinger's cat and Gödel's theorem are about what we can know."))
        #expect(!WordSync.looksTurkish("Schrödinger"))
        #expect(!WordSync.looksTurkish(""))
        #expect(WordSync.looksTurkish("Peki bu neden önemli?"))
        #expect(WordSync.looksTurkish("Hücre zarı seçici geçirgendir."))
        #expect(WordSync.looksTurkish("İYİ GÜNLER, BUGÜN ZARI ANLATIYORUZ"))
    }

    @Test func evaluateWithoutRecognitionUsesCheapChecks() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let text = String(repeating: "Hücre zarı madde geçişini düzenler. ", count: 2)
        let good = try writeWAV(tone(Double(text.count) * 0.07) + silence(0.2), dir.appending(path: "g.wav"))
        let check = await SceneQualityGate.evaluate(wav: good, turns: [turn(.a, text)], engine: .chirp, recognize: false)
        #expect(check.ok)
        #expect(check.wordTimes == nil)
        let cut = try writeWAV(tone(1), dir.appending(path: "c.wav"))
        let bad = await SceneQualityGate.evaluate(wav: cut, turns: [turn(.a, text)], engine: .chirp, recognize: false)
        #expect(!bad.ok)
        #expect(bad.reasons.count == 2)
        let missing = await SceneQualityGate.evaluate(wav: dir.appending(path: "yok.wav"), turns: [], engine: .chirp, recognize: false)
        #expect(!missing.ok)
    }
}

// MARK: - #10/#48 Sahne kopyaları ve düzenleme

struct SceneMastersTests {
    @Test func restitchFromMastersKeepsDuration() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "masters")
        let urls = try [tone(2) + silence(0.4) + tone(1), tone(3), tone(1.5)].enumerated().map {
            try writeWAV($1, dir.appending(path: "s\($0).wav"))
        }
        let turnsPerScene = [[turn(.a, "Bilgi"), turn(.b, "Soru?", think: 4)], [turn(.a, "Cevap")], [turn(.b, "Son")]]
        let chapters = [0, 0, 1]
        func inputs(_ sources: [URL]) -> [AudioStitcher.SceneInput] {
            sources.enumerated().map { .init(url: $1, chapterIndex: chapters[$0], turns: turnsPerScene[$0]) }
        }
        let original = try await AudioStitcher.stitch(scenes: inputs(urls), chapterTitles: ["Bir", "İki"], output: dir.appending(path: "a.m4a"),
                                                      design: true, identity: .sicak)
        let id = UUID()
        try SceneMasters.store(episodeID: id, scenes: urls, root: root)
        #expect(SceneMasters.count(id, root: root) == 3)
        let masters = (0..<3).map { SceneMasters.url(id, scene: $0, root: root) }
        let again = try await AudioStitcher.stitch(scenes: inputs(masters), chapterTitles: ["Bir", "İki"], output: dir.appending(path: "b.m4a"),
                                                   design: true, identity: .sicak)
        #expect(again == original)
        #expect(abs(try fileSeconds(dir.appending(path: "a.m4a")) - (try fileSeconds(dir.appending(path: "b.m4a")))) < 0.001)

        // Bir sahne değişince yalnız o sahnenin süresi kadar fark olur; geri alınabilir.
        let replacement = try writeWAV(tone(5), dir.appending(path: "new.wav"))
        try SceneMasters.replace(id, scene: 1, with: replacement, root: root)
        SceneMasters.commitReplace(id, root: root)
        let edited = try await AudioStitcher.stitch(scenes: inputs(masters), chapterTitles: ["Bir", "İki"], output: dir.appending(path: "c.m4a"),
                                                    design: true, identity: .sicak)
        #expect(abs(edited.duration - original.duration - 2) < 0.01)
        #expect(edited.turns[0].start == original.turns[0].start)
        SceneMasters.restoreUndo(id, scene: 1, root: root)
        let restored = try await AudioStitcher.stitch(scenes: inputs(masters), chapterTitles: ["Bir", "İki"], output: dir.appending(path: "d.m4a"),
                                                      design: true, identity: .sicak)
        #expect(restored == original)
    }

    @Test func failedReplaceKeepsPreviousUndo() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "masters")
        let id = UUID()
        let urls = try [tone(1), tone(2)].enumerated().map { try writeWAV($1, dir.appending(path: "s\($0).wav")) }
        try SceneMasters.store(episodeID: id, scenes: urls, root: root)
        let first = try writeWAV(tone(3), dir.appending(path: "first.wav"))
        let second = try writeWAV(tone(4), dir.appending(path: "second.wav"))
        func seconds(_ scene: Int) throws -> Double { try WAV.parse(Data(contentsOf: SceneMasters.url(id, scene: scene, root: root))).duration }
        // 1. düzenleme başarılı.
        try SceneMasters.replace(id, scene: 1, with: first, root: root)
        SceneMasters.commitReplace(id, root: root)
        // 2. düzenleme başarısız: sahne 1. düzenlemedeki hâline döner, 1. düzenlemenin geri alma kopyası kalır.
        try SceneMasters.replace(id, scene: 1, with: second, root: root)
        #expect(abs(try seconds(1) - 4) < 0.01)
        SceneMasters.rollbackReplace(id, scene: 1, root: root)
        #expect(abs(try seconds(1) - 3) < 0.01)
        #expect(SceneMasters.restoreUndo(id, scene: 1, root: root))
        #expect(abs(try seconds(1) - 2) < 0.01)
        #expect(!SceneMasters.restoreUndo(id, scene: 1, root: root))
    }

    @Test func completenessAndStoredSoundOptions() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appending(path: "masters")
        let id = UUID()
        let urls = try [tone(1), tone(1)].enumerated().map { try writeWAV($1, dir.appending(path: "s\($0).wav")) }
        try SceneMasters.store(episodeID: id, scenes: urls, root: root, design: false, identity: .odak)
        #expect(SceneMasters.isComplete(id, scenes: 2, root: root))
        #expect(!SceneMasters.isComplete(id, scenes: 3, root: root))
        // Üretimdeki tasarım ve genel kimlik kullanılır; bugünkü genel ayar değil. Bölüme özel seçim önce gelir.
        let stored = SceneMasters.stitchOptions(id, episodeIdentity: nil, root: root)
        #expect(stored.design == false && stored.identity == .odak)
        let own = SceneMasters.stitchOptions(id, episodeIdentity: "sicak", root: root)
        #expect(own.design == false && own.identity == .sicak)
        // Eksik sahne dosyası → kayıpsız yol kullanılmaz.
        try FileManager.default.removeItem(at: SceneMasters.url(id, scene: 1, root: root))
        #expect(!SceneMasters.isComplete(id, scenes: 2, root: root))
        // Eski işaret (yalnız sayı) → bugünkü genel ayar.
        let old = UUID()
        try FileManager.default.createDirectory(at: SceneMasters.directory(old, root: root), withIntermediateDirectories: true)
        try Data(#"{"count":1}"#.utf8).write(to: SceneMasters.directory(old, root: root).appending(path: SceneMasters.markerName))
        #expect(SceneMasters.count(old, root: root) == 1)
        let episodes = dir.appending(path: "episodes")
        let fallback = SceneMasters.stitchOptions(old, episodeIdentity: nil, root: root, episodes: episodes)
        #expect(fallback.design == SoundDesign.isEnabled && fallback.identity == SoundIdentity.current)
        // Kopyalar temizlense de bölüm klasöründeki kayıt kullanılır; silinmiş bölümün klasörü oluşturulmaz.
        SceneMasters.saveSound(id, design: false, identity: .sicak, episodes: episodes)
        #expect(!FileManager.default.fileExists(atPath: episodes.path))
        try FileManager.default.createDirectory(at: episodes.appending(path: id.uuidString), withIntermediateDirectories: true)
        SceneMasters.saveSound(id, design: false, identity: .sicak, episodes: episodes)
        SceneMasters.invalidate(id, root: root)
        let saved = SceneMasters.stitchOptions(id, episodeIdentity: nil, root: root, episodes: episodes)
        #expect(saved.design == false && saved.identity == .sicak)
    }

    /// Uçtan uca (sunucusuz): Uygula → kayıpsız yeniden birleştirme, yer imi kayması, geri alma kaydı; Geri al;
    /// kopyalar yokken m4a yolu.
    @MainActor
    @Test func applyAndUndoEndToEnd() async throws {
        guard let app = AppState.current else { return }
        let container = try ModelContainer(for: Episode.self, Bookmark.self, ReviewCard.self, MistakeEntry.self, LiveExchange.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let script = PodcastScript(title: "T", summary: "", keyPoints: [], chapters: [
            ScriptChapter(title: "Bir", scenes: [ScriptScene(turns: [turn(.a, "Birinci sahne")]), ScriptScene(turns: [turn(.b, "İkinci sahne")])]),
            ScriptChapter(title: "İki", scenes: [ScriptScene(turns: [turn(.a, "Üçüncü sahne")])]),
        ], sourceNotes: "")
        let episode = Episode(script: script, settings: PodcastSettings(), sourceNames: [], jobToken: "")
        context.insert(episode)
        let id = episode.id
        let dir = episode.directory
        defer {
            try? FileManager.default.removeItem(at: dir)
            SceneMasters.invalidate(id)
        }
        let sources = try [2.0, 3.0, 1.5].enumerated().map { try writeWAV(tone($1), dir.appending(path: "src-\($0).wav")) }
        let audio = dir.appending(path: "podcast.m4a")
        let original = try await AudioStitcher.stitch(scenes: sources.enumerated().map {
            .init(url: $1, chapterIndex: [0, 0, 1][$0], turns: script.flatScenes[$0].scene.turns)
        }, chapterTitles: ["Bir", "İki"], output: audio, design: false, identity: .yok)
        try await SceneMasters.store(episodeID: id, scenes: sources, design: false, identity: .yok)
        episode.audioFileName = "podcast.m4a"
        episode.timeline = original
        episode.duration = original.duration
        let mark = Bookmark(episode: episode, time: original.turns[2].start + 0.5, text: "")
        context.insert(mark)
        let revision = episode.audioRevision

        // Sahne 1 (2. sahne) 2 sn uzar: kayıpsız yol.
        let longer = try writeWAV(tone(5), dir.appending(path: "studio.wav"))
        let newTurns = [turn(.b, "Yeni ikinci sahne")]
        try await SceneEditor.applyRendered(episode, sceneIndex: 1, turns: newTurns, wav: longer,
                                            expected: try #require(episode.script).flatScenes[1].scene.turns, context: context, generator: app.generator)
        #expect(abs(episode.duration - original.duration - 2) < 0.02)
        #expect(abs(try fileSeconds(audio) - episode.duration) < 0.1)
        #expect(episode.script?.flatScenes[1].scene.turns.map(\.text) == ["Yeni ikinci sahne"])
        #expect(episode.audioRevision == revision + 1)
        #expect(abs(mark.time - (original.turns[2].start + 0.5 + 2)) < 0.02)
        #expect(SceneEditor.canUndo(episode))
        #expect(SceneEditor.undoState(episode)?.masterBackup == true)
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: SceneEditor.pendingAudioName).path))

        // Geri al: ses, senaryo, yer imi ve kopyalar düzenleme öncesine döner.
        try await SceneEditor.undo(episode, context: context, generator: app.generator)
        #expect(abs(episode.duration - original.duration) < 0.001)
        #expect(abs(try fileSeconds(audio) - original.duration) < 0.1)
        #expect(episode.script == script)
        #expect(abs(mark.time - (original.turns[2].start + 0.5)) < 0.001)
        #expect(!SceneEditor.canUndo(episode))
        #expect(SceneMasters.isComplete(id, scenes: 3))
        #expect(abs(try WAV.parse(Data(contentsOf: SceneMasters.url(id, scene: 1))).duration - 3) < 0.01)

        // Kopyalar yokken (ör. temizlendi) m4a yolu; ardından ses başka yoldan değişirse geri alma düşer.
        SceneMasters.invalidate(id)
        try await SceneEditor.applyRendered(episode, sceneIndex: 1, turns: newTurns, wav: longer,
                                            expected: try #require(episode.script).flatScenes[1].scene.turns, context: context, generator: app.generator)
        #expect(abs(episode.duration - original.duration - 2) < 0.1)
        #expect(SceneEditor.undoState(episode)?.masterBackup == false)
        #expect(SceneEditor.canUndo(episode))
        episode.audioRevision += 1
        #expect(!SceneEditor.canUndo(episode))
        await #expect(throws: APIError.self) { try await SceneEditor.undo(episode, context: context, generator: app.generator) }
        #expect(episode.script?.flatScenes[1].scene.turns.map(\.text) == ["Yeni ikinci sahne"])
    }

    /// Bulgu #10: sahnenin tur sayısı değişince küresel tur indeksi tutan veriler (şekil eşlemesi, soru → "Bu kısmı
    /// dinle") ve bölüm anı tutan kayıtlar kayar; Geri al hepsini düzenleme öncesine döndürür. Sahne bu arada
    /// değiştiyse stüdyonun sesi uygulanmaz.
    @MainActor
    @Test func turnCountChangeShiftsTurnIndexedDataAndUndoRestoresIt() async throws {
        guard let app = AppState.current else { return }
        let container = try ModelContainer(for: Episode.self, Bookmark.self, ReviewCard.self, MistakeEntry.self, LiveExchange.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let script = PodcastScript(title: "T", summary: "", keyPoints: [], chapters: [
            ScriptChapter(title: "Bir", scenes: [ScriptScene(turns: [turn(.a, "Giriş")]),
                                                 ScriptScene(turns: [turn(.a, "Bir"), turn(.b, "İki"), turn(.a, "Üç"), turn(.b, "Dört")])]),
            ScriptChapter(title: "İki", scenes: [ScriptScene(turns: [turn(.a, "Son"), turn(.b, "Son cevap")])]),
        ], sourceNotes: "")
        let episode = Episode(script: script, settings: PodcastSettings(), sourceNames: [], jobToken: "")
        context.insert(episode)
        let id = episode.id
        let dir = episode.directory
        defer {
            try? FileManager.default.removeItem(at: dir)
            SceneMasters.invalidate(id)
        }
        let gap = silence(0.4)
        let sources = try [tone(2), tone(1) + gap + tone(1) + gap + tone(1) + gap + tone(1), tone(1) + gap + tone(1)]
            .enumerated().map { try writeWAV($1, dir.appending(path: "src-\($0).wav")) }
        let audio = dir.appending(path: "podcast.m4a")
        let original = try await AudioStitcher.stitch(scenes: sources.enumerated().map {
            .init(url: $1, chapterIndex: [0, 0, 1][$0], turns: script.flatScenes[$0].scene.turns)
        }, chapterTitles: ["Bir", "İki"], output: audio, design: false, identity: .yok)
        try await SceneMasters.store(episodeID: id, scenes: sources, design: false, identity: .yok)
        episode.audioFileName = "podcast.m4a"
        episode.timeline = original
        episode.duration = original.duration
        #expect(original.turns.count == 7)

        let figures = [FigureMapEntry(figureId: "f0", chapterIndex: 0, turnIndex: 0, confidence: 1),
                       FigureMapEntry(figureId: "f3", chapterIndex: 0, turnIndex: 3, confidence: 1),
                       FigureMapEntry(figureId: "f6", chapterIndex: 1, turnIndex: 6, confidence: 1),
                       FigureMapEntry(figureId: "fc", chapterIndex: 1, turnIndex: nil, confidence: 1)]
        func quiz(_ turn: Int?) -> QuizItem {
            QuizItem(question: "S\(turn ?? -1)", options: ["a", "b"], answerIndex: 0, explanation: "", chapterIndex: 0, turnIndex: turn)
        }
        let study = StudyPack(quiz: [quiz(6), quiz(4), quiz(nil), quiz(0)], flashcards: [])
        episode.figureMap = figures
        episode.study = study
        let card = ReviewCard(episodeID: id, episodeTitle: "T", kind: .quiz, front: "", back: "", sourcePage: nil)
        card.episodeTime = original.turns[5].start + 0.2
        context.insert(card)
        let live = LiveExchange(episodeID: id, episodeTitle: "T", question: "", answer: "", chapterIndex: 1,
                                time: original.turns[6].start + 0.1, mode: "ask")
        context.insert(live)

        // Sahne bu arada değiştiyse (beklenen turlar tutmuyor) hiçbir şey değişmez.
        let short = try writeWAV(tone(1) + gap + tone(1), dir.appending(path: "studio.wav"))
        let newTurns = [turn(.a, "Kısa bir"), turn(.b, "Kısa iki")]
        await #expect(throws: APIError.self) {
            try await SceneEditor.applyRendered(episode, sceneIndex: 1, turns: newTurns, wav: short, expected: [turn(.a, "Başka")],
                                                context: context, generator: app.generator)
        }
        #expect(episode.script == script && episode.figureMap == figures && !SceneEditor.canUndo(episode))

        // "Kısalt": 4 tur → 2 tur. Sonraki turlar 2 geri kayar, sahnenin içindekiler aynı orandaki tura gider.
        try await SceneEditor.applyRendered(episode, sceneIndex: 1, turns: newTurns, wav: short,
                                            expected: script.flatScenes[1].scene.turns, context: context, generator: app.generator)
        let timeline = try #require(episode.timeline)
        #expect(timeline.turns.count == 5)
        #expect(episode.figureMap?.map(\.turnIndex) == [0, 2, 4, nil])
        #expect(episode.study?.quiz.map(\.turnIndex) == [4, 2, nil, 0])
        #expect(ListenAnchor.time(for: try #require(episode.study?.quiz.first), timeline: timeline) == timeline.turns[4].start)
        #expect(abs((card.episodeTime ?? 0) - (timeline.turns[3].start + 0.2)) < 0.02)
        #expect(abs((live.time ?? 0) - (timeline.turns[4].start + 0.1)) < 0.02)
        let undoAudio = dir.appending(path: SceneEditor.undoAudioName)
        #expect(try undoAudio.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)

        // Eşleme düzenlemeden sonra yeniden alındı (yeni indekslerle): geri almada ters yönde kayar; çalışma paketi
        // değişmediği için düzenleme öncesi hâline döner.
        episode.figureMap = [FigureMapEntry(figureId: "yeni", chapterIndex: 1, turnIndex: 4, confidence: 1)]
        try await SceneEditor.undo(episode, context: context, generator: app.generator)
        #expect(episode.script == script)
        #expect(episode.figureMap?.map(\.turnIndex) == [6])
        #expect(episode.study == study)
        #expect(abs((card.episodeTime ?? 0) - (original.turns[5].start + 0.2)) < 0.001)
        #expect(abs((live.time ?? 0) - (original.turns[6].start + 0.1)) < 0.001)

        // Ses başka yoldan değişince (yeniden üretim, konu çıkarma: hepsi `WordSync.invalidate` çağırır) geri alma
        // kopyası hemen silinir; stüdyonun yeniden açılması beklenmez.
        episode.figureMap = figures
        try await SceneEditor.applyRendered(episode, sceneIndex: 1, turns: newTurns, wav: short,
                                            expected: script.flatScenes[1].scene.turns, context: context, generator: app.generator)
        #expect(FileManager.default.fileExists(atPath: undoAudio.path))
        WordSync.invalidate(id)
        #expect(!FileManager.default.fileExists(atPath: undoAudio.path))
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: SceneEditor.undoStateName).path))
    }

    @Test func turnIndexRemap() {
        // Sahne = tur 1…4 (4 tur) → 2 tur.
        let old = 1..<5, new = 1..<3
        #expect((0...7).map { SceneEditor.remapTurn($0, oldRange: old, newRange: new) } == [0, 1, 1, 2, 2, 3, 4, 5])
        // Tur sayısı aynıysa indeks değişmez; artınca sonrakiler ileri kayar.
        #expect((0...5).map { SceneEditor.remapTurn($0, oldRange: 1..<3, newRange: 1..<3) } == [0, 1, 2, 3, 4, 5])
        #expect((0...4).map { SceneEditor.remapTurn($0, oldRange: 1..<3, newRange: 1..<5) } == [0, 1, 3, 5, 6])
    }

    @Test func turnLengthLimitMatchesServer() {
        #expect(SceneEditor.overLimit([turn(.a, String(repeating: "a", count: 1500))]) == nil)
        let over = SceneEditor.overLimit([turn(.a, "kısa"), turn(.b, String(repeating: "ş", count: 1501))])
        #expect(over?.index == 2 && over?.length == 1501)
        // Sunucu UTF-16 birimi sayar: emoji 2 birim.
        #expect(SceneEditor.overLimit([turn(.a, String(repeating: "😀", count: 750))]) == nil)
        #expect(SceneEditor.overLimit([turn(.a, String(repeating: "😀", count: 751))])?.length == 1502)
    }

    @MainActor
    @Test func undoRecordDropsWhenAudioChangedElsewhere() throws {
        let container = try ModelContainer(for: Episode.self, Bookmark.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let script = PodcastScript(title: "T", summary: "", keyPoints: [], chapters: [
            ScriptChapter(title: "Bir", scenes: [ScriptScene(turns: [turn(.a, "a")])])], sourceNotes: "")
        let episode = Episode(script: script, settings: PodcastSettings(), sourceNames: [], jobToken: "")
        container.mainContext.insert(episode)
        let dir = episode.directory
        defer { try? FileManager.default.removeItem(at: dir) }
        let fm = FileManager.default
        let audio = dir.appending(path: SceneEditor.undoAudioName), stateURL = dir.appending(path: SceneEditor.undoStateName)
        func write(revision: Int?) throws {
            try Data([1]).write(to: audio)
            let state = SceneEditor.UndoState(sceneIndex: 0, scriptData: Data(), timelineData: nil, duration: 1,
                                              audioFileName: "podcast.m4a", bookmarks: [:], masterBackup: false, audioRevision: revision)
            try JSONEncoder().encode(state).write(to: stateURL)
        }
        try write(revision: episode.audioRevision)
        #expect(SceneEditor.canUndo(episode))
        // Ses başka yoldan değişti (yeniden üretim, konu çıkarma, önceki sese dönüş): geri alma düşer, yedekler silinir.
        episode.audioRevision += 1
        #expect(!SceneEditor.canUndo(episode))
        #expect(!fm.fileExists(atPath: audio.path) && !fm.fileExists(atPath: stateURL.path))
        // Sürümsüz (eski) kayıt ve yedeği eksik kayıt da geçersiz.
        try write(revision: nil)
        #expect(!SceneEditor.canUndo(episode))
        try write(revision: episode.audioRevision)
        try fm.removeItem(at: audio)
        #expect(!SceneEditor.canUndo(episode))
        #expect(!fm.fileExists(atPath: stateURL.path))
    }

    @Test func purgeLimits() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fm = FileManager.default
        let now = Date.now
        var ids: [UUID] = []
        // 12 bölüm, i. bölüm i gün önce kullanılmış, her biri 1000 bayt.
        for i in 0..<12 {
            let id = UUID()
            ids.append(id)
            let wav = dir.appending(path: "src-\(i).wav")
            try Data(repeating: 1, count: 1000).write(to: wav)
            try SceneMasters.store(episodeID: id, scenes: [wav], root: dir.appending(path: "root"))
            let marker = SceneMasters.directory(id, root: dir.appending(path: "root")).appending(path: SceneMasters.markerName)
            try fm.setAttributes([.modificationDate: now.addingTimeInterval(-Double(i) * 86_400)], ofItemAtPath: marker.path)
        }
        let root = dir.appending(path: "root")
        // Yarım kalmış eski kayıt.
        let stale = root.appending(path: UUID().uuidString)
        try fm.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 500).write(to: stale.appending(path: "scene_0000.wav"))
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-7200)], ofItemAtPath: stale.path)

        var removed = SceneMasters.purge(root: root, now: now, keepingRecent: 10, maxBytes: 1_000_000, maxAge: 30 * 86_400)
        #expect(removed >= 2000 + 500)
        #expect(SceneMasters.count(ids[9], root: root) == 1)
        #expect(SceneMasters.count(ids[10], root: root) == nil && SceneMasters.count(ids[11], root: root) == nil)
        #expect(!fm.fileExists(atPath: stale.path))

        removed = SceneMasters.purge(root: root, now: now, keepingRecent: 10, maxBytes: 1_000_000, maxAge: 5.5 * 86_400)
        #expect(SceneMasters.count(ids[5], root: root) == 1 && SceneMasters.count(ids[6], root: root) == nil)

        removed = SceneMasters.purge(root: root, now: now, keepingRecent: 10, maxBytes: 3_500, maxAge: 30 * 86_400)
        #expect(SceneMasters.count(ids[2], root: root) == 1 && SceneMasters.count(ids[3], root: root) == nil)
        #expect(removed > 0)
    }

    @Test func bookmarkRemapAcrossEdit() {
        func tl(_ spans: [(Double, Double)]) -> Timeline {
            Timeline(chapters: [], turns: spans.enumerated().map { TimedTurn(id: $0, chapterIndex: 0, speaker: .a, text: "", sourcePage: nil, start: $1.0, end: $1.1) },
                     duration: spans.last?.1 ?? 0)
        }
        let old = tl([(0, 2), (2.4, 4), (4.4, 6), (6.4, 8)])
        // Sahne = tur 1…2; yeni sahne tek tur ve 1 sn daha uzun.
        let new = tl([(0, 2), (2.4, 7), (7.4, 9)])
        #expect(SceneEditor.remap(1.0, old: old, new: new, oldRange: 1..<3, newRange: 1..<2) == 1.0)
        #expect(abs(SceneEditor.remap(7.0, old: old, new: new, oldRange: 1..<3, newRange: 1..<2) - 8.0) < 0.001)
        let mid = SceneEditor.remap(4.2, old: old, new: new, oldRange: 1..<3, newRange: 1..<2)
        #expect(abs(mid - (2.4 + (4.2 - 2.4) / 3.6 * 4.6)) < 0.001)
    }

    @Test func replacingSceneTouchesOnlyThatScene() {
        let script = PodcastScript(title: "T", summary: "", keyPoints: [], chapters: [
            ScriptChapter(title: "Bir", scenes: [ScriptScene(turns: [turn(.a, "a")]), ScriptScene(turns: [turn(.a, "b")])]),
            ScriptChapter(title: "İki", scenes: [ScriptScene(turns: [turn(.a, "c")])]),
        ], sourceNotes: "")
        let edited = SceneEditor.replacing(script, sceneIndex: 2, turns: [turn(.b, "yeni"), turn(.a, "ek")])
        #expect(edited.flatScenes.map { $0.scene.turns.map(\.text) } == [["a"], ["b"], ["yeni", "ek"]])
        #expect(SceneEditor.replacing(script, sceneIndex: 9, turns: []) == script)
    }

    @Test func editRequestsUseEditPurposeAndEpisodeSettings() throws {
        let request = AudioJobRequest(script: PodcastScript(title: "T", summary: "", keyPoints: [], chapters: [], sourceNotes: ""),
                                      settings: PodcastSettings(), previousJobToken: "tok", purpose: "edit")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        #expect(json?["purpose"] as? String == "edit")
        #expect(json?["previousJobToken"] as? String == "tok")
        var settings = PodcastSettings()
        settings.pace = .hizli
        settings.depth = .derin
        let rewrite = RewriteSettings(level: settings.level, tone: settings.tone, format: settings.format, language: settings.language,
                                      hostA: settings.hostA, hostB: settings.hostB, pace: settings.pace, depth: settings.depth, guest: nil)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rewrite)) as? [String: Any]
        #expect(encoded?["pace"] as? String == "hizli")
        #expect(encoded?["depth"] as? String == "derin")
    }

    @Test func suggestRequestRespectsServerLimits() throws {
        let long = String(repeating: "Mitokondri hücrenin enerji santralidir. ", count: 2000)
        let script = PodcastScript(title: "T", summary: "", keyPoints: [], chapters: [
            ScriptChapter(title: "Bir", scenes: [ScriptScene(turns: [turn(.a, long)])])], sourceNotes: "")
        let dictionary = (0..<150).map { Pronunciation(from: "k\($0)", to: "x") }
        let request = PronunciationSuggestionsSheet.request(script: script, dictionary: dictionary)
        #expect(request.text.count == 30_000)
        #expect(request.known.count == 100)
        let decoded = try JSONDecoder().decode([PronunciationSuggestion].self, from: Data(#"[{"from":"İyon","to":"i-yon","why":"İ"}]"#.utf8))
        #expect(decoded.first?.to == "i-yon")
    }
}

// MARK: - Dar ekran (320 pt, büyük ve kalın yazı)

@MainActor
struct PodcastAudioLayoutTests {
    @Test(arguments: [DynamicTypeSize.large, .xxxLarge, .accessibility3])
    func identityPickerFitsNarrowScreen(size: DynamicTypeSize) {
        let view = Form { SoundIdentityPicker(selection: .constant("sicak")) }
            .dynamicTypeSize(size)
            .environment(\.legibilityWeight, .bold)
        let host = UIHostingController(rootView: view)
        let fitted = host.sizeThatFits(in: CGSize(width: 320, height: 2000))
        #expect(fitted.width <= 320.5)
    }
}

// MARK: - Görsel denetim (yalnız geliştirme makinesinde; görüntüler scratchpad'e yazılır)

@MainActor
struct PodcastAudioSnapshots {
    private static let outDir = "/private/tmp/claude-501/-Users-mehmetderin-Desktop-ads-z-klas-r-2/77227023-b9c9-47a8-ae0c-656d7ac2c503/scratchpad/p4shots"

    private func snapshot<V: View>(_ view: V, name: String, height: CGFloat = 1500) async throws {
        guard FileManager.default.fileExists(atPath: (Self.outDir as NSString).deletingLastPathComponent),
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        try FileManager.default.createDirectory(atPath: Self.outDir, withIntermediateDirectories: true)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: height)
        window.rootViewController = UIHostingController(rootView: view
            .dynamicTypeSize(.xxxLarge)
            .environment(\.legibilityWeight, .bold))
        window.isHidden = false
        try await Task.sleep(for: .milliseconds(800))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try image.pngData()?.write(to: URL(fileURLWithPath: Self.outDir).appending(path: "\(name).png"))
        window.isHidden = true
    }

    @Test func studioAndPickers() async throws {
        let container = try ModelContainer(for: Episode.self, Bookmark.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let script = PodcastScript(title: "Hücre zarı", summary: "", keyPoints: [], chapters: [
            ScriptChapter(title: "Zarın yapısı", scenes: [ScriptScene(turns: [
                turn(.a, "Hücre zarı, hücreyi çevreleyen ve madde geçişini düzenleyen seçici geçirgen bir yapıdır."),
                turn(.b, "Peki sence zar neden seçici geçirgen olmak zorunda?", think: 5),
            ])])], sourceNotes: "")
        let episode = Episode(script: script, settings: PodcastSettings(speechProvider: "chirp"), sourceNames: [], jobToken: "")
        container.mainContext.insert(episode)
        // Uygulamanın kendi örneği kullanılır (AppState.init `current`'ı değiştirir).
        guard let app = AppState.current else { return }
        try await snapshot(SceneStudioView(episode: episode, sceneIndex: 0)
            .environment(app.generator)
            .environment(app)
            .modelContainer(container), name: "scene-studio")
        // Sunucu sınırını aşan tur: satır altında sayaç, altta hangi tur olduğu; seslendirme kapalı.
        let long = PodcastScript(title: "Uzun", summary: "", keyPoints: [], chapters: [
            ScriptChapter(title: "Uzun tur", scenes: [ScriptScene(turns: [
                turn(.a, "Kısa giriş."), turn(.b, String(repeating: "Seçici geçirgenlik ışığında çok uzun bir açıklama. ", count: 32)),
            ])])], sourceNotes: "")
        let longEpisode = Episode(script: long, settings: PodcastSettings(speechProvider: "chirp"), sourceNames: [], jobToken: "")
        container.mainContext.insert(longEpisode)
        try await snapshot(SceneStudioView(episode: longEpisode, sceneIndex: 0)
            .environment(app.generator)
            .environment(app)
            .modelContainer(container), name: "scene-studio-long", height: 1800)
        try await snapshot(NavigationStack { Form { SoundIdentityPicker(selection: .constant("sicak")) } }, name: "identity-picker", height: 700)
        try await snapshot(PronunciationEditor(text: "Sklera ve İyon kanalları 1990'larda keşfedildi."), name: "pronunciation-editor")
        try await snapshot(PronunciationSuggestionsSheet(episode: episode).environment(app), name: "suggestions", height: 700)
        let items = [PronunciationSuggestion(from: "İyon", to: "i-yon", why: "İ harfi motorlarda farklı okunabiliyor."),
                     PronunciationSuggestion(from: "Mitokondri", to: "mi-to-kond-ri", why: "Uzun bilimsel terim.")]
        try await snapshot(PronunciationSuggestionsSheet(episode: episode, previewItems: items).environment(app), name: "suggestions-list", height: 1400)
    }
}
