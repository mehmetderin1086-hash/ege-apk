import AVFoundation
import AVKit
import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Ikra

// I1 — dinleme, oynatıcı, transkript: kelime zamanları, terim düzeltme, temiz okuma, döngü, sessizlik atlama,
// bölüm gezintisi, geri sarma ısı şeridi, izleme süresi, öğrenci konuşması.

private func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) < tolerance }

private final class BundleToken {}

// MARK: - #7 kelime zamanları

struct WordTimeTests {
    @Test func spanTimesAreUsedDirectlyWhenCountsMatch() {
        let text = "bir iki üç dört"
        let spans = [FollowAlong.Span(start: 0, end: 4, words: 2, times: [0.2, 1.7]),
                     FollowAlong.Span(start: 15, end: 20, words: 2, times: [15.4, 18.0])]
        let timing = FollowAlong.Timing(text: text, start: 0, end: 20, spans: spans)
        #expect(timing.times == [0.2, 1.7, 15.4, 18.0])
        #expect(timing.current(at: 1.8) == 1)
        #expect(timing.current(at: 16) == 2)
        #expect(timing.current(at: 0.1) == nil)   // ilk kelimeden önce
    }

    @Test func mismatchedWordTimesFallBackToDistribution() {
        // Kelime zamanı sayısı kelime sayısıyla tutmuyor: ağırlıklı dağıtım (eski davranış).
        let spans = [FollowAlong.Span(start: 0, end: 4, words: 2, times: [0.2])]
        let timing = FollowAlong.Timing(text: "bir iki", start: 0, end: 4, spans: spans)
        #expect(near(timing.times[0], 0))
        #expect(timing.times[1] > 0 && timing.times[1] < 4)
        // Metin başka kelime sayısına düzeltildiyse (parça sayısı ≠ metin kelimeleri) de zamanlar kullanılmaz ama sıralı kalır.
        let edited = FollowAlong.Timing(text: "bir iki üç", start: 0, end: 4,
                                        spans: [.init(start: 0, end: 4, words: 2, times: [0.2, 1.7])])
        #expect(zip(edited.times, edited.times.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func noisyWordTimesNeverGoBackwards() {
        let spans = [FollowAlong.Span(start: 0, end: 3, words: 3, times: [0.5, 0.4, 2.0])]
        let timing = FollowAlong.Timing(text: "a b c", start: 0, end: 3, spans: spans)
        #expect(timing.times == [0.5, 0.5, 2.0])
    }

    @Test func transcriptSpansCarryWordTimesOnlyWhenCountsMatch() {
        let segments = [TranscriptSegment(start: 0, end: 2, text: "Merhaba gençler.", w: [0.1, 0.9]),
                        TranscriptSegment(start: 2, end: 5, text: "Bugün fotosentez", w: [2.0]),   // sayı tutmuyor
                        TranscriptSegment(start: 5, end: 9, text: "devam ediyoruz")]              // w yok
        let spans = TranscriptFormat.spans(start: 0, end: 9, segments: segments)
        #expect(spans.count == 3)
        #expect(spans[0].times == [0.1, 0.9])
        #expect(spans[1].times == nil)
        #expect(spans[2].times == nil)
        // Eski çağrı biçimi (times yok) derlenir ve eski davranışı verir.
        #expect(FollowAlong.Span(start: 0, end: 1, words: 1).times == nil)
    }

    @Test func segmentWordTimesSurviveCoding() throws {
        let segment = TranscriptSegment(start: 1, end: 3, text: "a b", w: [1.0, 2.0])
        let decoded = try JSONDecoder().decode(TranscriptSegment.self, from: JSONEncoder().encode(segment))
        #expect(decoded.w == [1.0, 2.0])
        let legacy = try JSONDecoder().decode(TranscriptSegment.self, from: Data(#"{"start":1,"end":3,"text":"a b"}"#.utf8))
        #expect(legacy.w == nil)
    }
}

// MARK: - #9 terim düzeltme

struct TermDictionaryTests {
    private func transcript() throws -> VideoTranscript {
        let json = #"""
        {"video":{"id":"EKGRs8q7HlA","title":"Fizik","chapters":[{"title":"Kuantım giriş","start":0}]},
         "segments":[{"start":0,"end":3,"text":"Kuantım fiziği çok ilginç","w":[0.1,1.0,1.8,2.2]},
                     {"start":3,"end":6,"text":"bugün kuantım mekaniği","w":[3.0,3.6,4.2]}],
         "paragraphs":[{"start":0,"end":6,"text":"Kuantım fiziği çok ilginç bugün kuantım mekaniği"}],
         "chapters":[{"title":"Kuantım giriş","start":0}],
         "notes":{"summary":"Kuantım üzerine","keyPoints":[{"text":"kuantım nedir","time":1}],
                  "concepts":[{"name":"Kuantım","definition":"küçük kuantım paketi","time":2}],
                  "formulas":[],"questions":[],"examTips":["kuantım çalış"]},
         "keyframes":[{"id":"k1","time":1,"caption":"kuantım şeması","text":""}]}
        """#
        return try JSONDecoder().decode(VideoTranscript.self, from: Data(json.utf8))
    }

    @Test func replacesWholeWordsIgnoringCase() {
        #expect(TermDictionary.replace("Kuantım fiziği, kuantım!", from: "kuantım", to: "kuantum") == "kuantum fiziği, kuantum!")
        // Tam sözcük: bir sözcüğün parçası değişmez.
        #expect(TermDictionary.replace("kuantımlar ve ekuantım", from: "kuantım", to: "kuantum") == "kuantımlar ve ekuantım")
        // Birkaç sözcüklü ifade.
        #expect(TermDictionary.replace("schrödinger denklemi önemli", from: "schrödinger denklemi", to: "Schrödinger denklemi")
                == "Schrödinger denklemi önemli")
        // Kenarında noktalama olan ifade (C++): sözcük sınırı yalnızca harf/rakamda aranır.
        #expect(TermDictionary.replace("C++ ve C+++", from: "C++", to: "C plus plus") == "C plus plus ve C plus plus+")
        #expect(TermDictionary.replace("hiçbir şey", from: "", to: "x") == "hiçbir şey")
    }

    @Test func applyingTwiceDoesNotDuplicate() {
        let once = TermDictionary.replace("enerji korunur", from: "enerji", to: "enerji kaynağı")
        #expect(once == "enerji kaynağı korunur")
        #expect(TermDictionary.replace(once, from: "enerji", to: "enerji kaynağı") == once)
        // Düzeltilmiş hâlin sonunda `from` varsa da (ön ek) çoğalmaz.
        let suffixed = TermDictionary.replace("kaynak", from: "kaynak", to: "enerji kaynak")
        #expect(suffixed == "enerji kaynak")
        #expect(TermDictionary.replace(suffixed, from: "kaynak", to: "enerji kaynak") == suffixed)
    }

    @Test func rulesApplyEverywhereInTranscript() throws {
        let rules = [TermRule(from: "kuantım", to: "kuantum")]
        let fixed = TermDictionary.apply(to: try transcript(), rules: rules)
        #expect(fixed.segments.map(\.text) == ["kuantum fiziği çok ilginç", "bugün kuantum mekaniği"])
        #expect(fixed.paragraphs[0].text == "kuantum fiziği çok ilginç bugün kuantum mekaniği")
        #expect(fixed.chapters[0].title == "kuantum giriş")
        #expect(fixed.video.chapters[0].title == "kuantum giriş")
        #expect(fixed.notes?.summary == "kuantum üzerine")
        #expect(fixed.notes?.keyPoints[0].text == "kuantum nedir")
        #expect(fixed.notes?.concepts[0].name == "kuantum" && fixed.notes?.concepts[0].definition == "küçük kuantum paketi")
        #expect(fixed.notes?.examTips == ["kuantum çalış"])
        #expect(fixed.keyframes[0].caption == "kuantum şeması")
        // Kelime sayısı değişmediği için kelime zamanları korunur.
        #expect(fixed.segments[0].w == [0.1, 1.0, 1.8, 2.2])
    }

    @Test func wordTimesAreDroppedWhenWordCountChanges() throws {
        let rules = [TermRule(from: "kuantım", to: "kuantum fiziği")]
        let fixed = TermDictionary.apply(to: try transcript(), rules: rules)
        #expect(fixed.segments[0].w == nil && fixed.segments[1].w == nil)
        #expect(fixed.segments[0].text.hasPrefix("kuantum fiziği fiziği"))
    }

    @Test func emptyOrInvalidRulesLeaveTranscriptUntouched() throws {
        let original = try transcript()
        #expect(TermDictionary.apply(to: original, rules: []) == original)
        #expect(TermDictionary.apply(to: original, rules: [TermRule(from: "kuantım", to: "kuantım"), TermRule(from: "", to: "x")]) == original)
    }

    @Test func matchingFollowsTurkishCaseRules() {
        // İ ↔ i ve I ↔ ı: büyük harfle yazılmış ya da cümle başındaki sözcük de eşleşir.
        #expect(TermDictionary.replace("İNTEGRAL ve İntegral ile integral", from: "integral", to: "türev") == "türev ve türev ile türev")
        #expect(TermDictionary.replace("IZGARA kullandık, Izgara da", from: "ızgara", to: "kafes") == "kafes kullandık, kafes da")
        #expect(TermRule(from: "IZGARA", to: "x").id == TermRule(from: "ızgara", to: "y").id)
        #expect(TermRule(from: "İNTEGRAL", to: "x").id == TermRule(from: "integral", to: "y").id)
        // Düzeltilmiş hâli denetleyen yol da aynı kuralla çalışır.
        let once = TermDictionary.replace("İNTEGRAL alıyoruz", from: "integral", to: "integral hesabı")
        #expect(once == "integral hesabı alıyoruz")
        #expect(TermDictionary.replace(once, from: "integral", to: "integral hesabı") == once)
    }

    @Test func longerRulesWinOverShorterOnes() {
        let rules = [TermRule(from: "kuantum", to: "kuantum"), TermRule(from: "kuantım", to: "kuantum"),
                     TermRule(from: "kuantım mekaniği", to: "kuantum mekaniği")]
        let ordered = TermDictionary.ordered(rules)
        #expect(ordered.first?.from == "kuantım mekaniği")
        #expect(!ordered.contains { $0.from == "kuantum" })   // kendine eşit kural geçersiz
    }

    @Test func dictionaryPersistsAndReplacesByKey() {
        let saved = TermDictionary.rules
        defer { TermDictionary.save(saved) }
        TermDictionary.save([])
        #expect(TermDictionary.add(from: " kuantım ", to: "kuantum")?.from == "kuantım")
        #expect(TermDictionary.add(from: "Kuantım", to: "kuantom") != nil)   // aynı anahtar (büyük/küçük harf duyarsız): günceller
        #expect(TermDictionary.add(from: "x", to: "x") == nil)
        #expect(TermDictionary.add(from: "", to: "y") == nil)
        #expect(TermDictionary.rules.map(\.to) == ["kuantom"])
        #expect(TermDictionary.add(from: "entropi", to: "entropi") == nil && TermDictionary.rules.count == 1)
        TermDictionary.remove(TermRule(from: "KUANTIM".replacingOccurrences(of: "I", with: "ı"), to: ""))
        #expect(TermDictionary.rules.isEmpty)
    }
}

// MARK: - #11 temiz okuma

struct CleanReadingTests {
    @Test func detectsHesitationsButNotRealWords() {
        for filler in ["eee", "ııı", "ıhh", "ee", "aah", "eh", "hmm", "Hımm,", "um", "uh.", "Eee…"] {
            #expect(CleanReading.isHesitation(CleanReading.normalized(filler)), "\(filler) dolgu sayılmalı")
        }
        for word in ["hem", "ama", "ev", "e", "a", "ehe", "ağaç", "enerji", "ıslak", "ah-vah", "evet"] {
            #expect(!CleanReading.isHesitation(CleanReading.normalized(word)), "\(word) dolgu sayılmamalı")
        }
    }

    @Test func discourseMarkersGoOnlyWhenCommaOrSentenceStart() {
        #expect(CleanReading.fillerFlags(in: "Bu, yani, önemli") == [false, true, false])
        // "yani" virgüllü → dolgu; cümle ortasında virgülsüz → anlamlı sözcük.
        #expect(CleanReading.fillerFlags(in: "Bu yani şu demek") == [false, false, false, false])
        #expect(CleanReading.fillerFlags(in: "Bu doğru. İşte bu yüzden") == [false, false, true, false, false])
    }

    @Test func cleanKeepsTimesOfRemainingWords() {
        // 6 kelime, iki parça: "eee bir iki" (0–3 sn) ve "üç ııı dört" (10–13 sn). Kelime zamanları var.
        let row = TranscriptRow(id: 0, start: 0, end: 13, text: "eee bir iki üç ııı dört", secondary: "çeviri",
                                spans: [.init(start: 0, end: 3, words: 3, times: [0.0, 1.0, 2.0]),
                                        .init(start: 10, end: 13, words: 3, times: [10.0, 11.0, 12.0])])
        let cleaned = CleanReading.clean(row)
        #expect(cleaned.text == "bir iki üç dört")
        #expect(cleaned.id == 0 && cleaned.start == 0 && cleaned.end == 13 && cleaned.secondary == "çeviri")
        #expect(cleaned.spans.map(\.words) == [2, 2])
        let timing = FollowAlong.Timing(text: cleaned.text, start: cleaned.start, end: cleaned.end, spans: cleaned.spans)
        #expect(timing.times == [1.0, 2.0, 10.0, 12.0])   // çıkarılan kelimelerin zamanları da düştü
    }

    @Test func cleanLeavesRowsWithoutFillersAndAllFillerRowsAlone() {
        let plain = TranscriptRow(id: 1, start: 0, end: 5, text: "Enerji korunur.")
        #expect(CleanReading.clean(plain) == plain)
        let onlyFillers = TranscriptRow(id: 2, start: 0, end: 5, text: "eee ııı")
        #expect(CleanReading.clean(onlyFillers) == onlyFillers)   // boş satır kalmasın
    }

    @Test func spanCountsDropToZeroRemoveTheSpan() {
        let row = TranscriptRow(id: 0, start: 0, end: 6, text: "ııı bir iki",
                                spans: [.init(start: 0, end: 1, words: 1), .init(start: 1, end: 6, words: 2)])
        let cleaned = CleanReading.clean(row)
        #expect(cleaned.text == "bir iki")
        #expect(cleaned.spans.count == 1 && cleaned.spans[0].words == 2)
    }
}

// MARK: - #12, #15, #17 oynatıcı kararları

struct PlaybackDecisionTests {
    @Test func abLoopValidatesAndDecides() throws {
        #expect(ABLoop(start: 10, end: 10.5) == nil)   // en az 1 sn
        #expect(ABLoop(start: -1, end: 5) == nil)
        let loop = try #require(ABLoop(start: 10, end: 20))
        #expect(loop.action(at: 15) == .none)
        #expect(loop.action(at: 20.1) == .wrap(to: 10))     // bitişi geçti → başa
        #expect(loop.action(at: 22.4) == .wrap(to: 10))
        #expect(loop.action(at: 40) == .cancel)             // kullanıcı ileri atladı → kapan
        #expect(loop.action(at: 3) == .cancel)              // geriye çok uzağa atladı
        #expect(loop.action(at: 9) == .none)                // başlangıca yakın (kısa geri) döngüde kalır
    }

    @Test func silenceSkipOnlyJumpsLongPauses() {
        let pauses = [FollowAlong.Pause(start: 5, end: 5.4),    // kısa: atlanmaz
                      FollowAlong.Pause(start: 10, end: 12),    // 2 sn
                      FollowAlong.Pause(start: 20, end: 20.7)]  // 0,7 sn
        #expect(SilenceSkip.target(at: 5.2, pauses: pauses) == nil)
        #expect(SilenceSkip.target(at: 9.9, pauses: pauses) == nil)            // sessizlikten önce
        #expect(SilenceSkip.target(at: 10.05, pauses: pauses) == nil)          // başındaki nefes payı
        let target = SilenceSkip.target(at: 10.3, pauses: pauses)
        #expect(target.map { near($0, 12 - SilenceSkip.lead) } == true)
        #expect(SilenceSkip.target(at: 11.9, pauses: pauses) == nil)           // zaten sonunda: atlanacak yer yok
        #expect(SilenceSkip.target(at: 12.5, pauses: pauses) == nil)           // sessizlik bitti
        #expect(SilenceSkip.target(at: 20.3, pauses: pauses) != nil)           // 0,7 ≥ 0,6
        #expect(SilenceSkip.target(at: 1, pauses: pauses) == nil)
        #expect(SilenceSkip.target(at: 30, pauses: []) == nil)
        // 0,5 sn'lik sessizlik atlanmaz.
        #expect(SilenceSkip.target(at: 7.3, pauses: [.init(start: 7, end: 7.5)]) == nil)
    }

    @Test func chapterNavigation() {
        let starts = [60.0, 0, 120, 300]   // sırasız verilebilir
        #expect(ChapterNav.target(from: 10, starts: starts, forward: true) == 60)
        #expect(ChapterNav.target(from: 59.8, starts: starts, forward: true) == 120)   // 0,5 sn payı: neredeyse bölüm başı
        #expect(ChapterNav.target(from: 300, starts: starts, forward: true) == nil)
        // Geri: bölümün ilk 3 saniyesinde bir önceki, sonrasında bölüm başı.
        #expect(ChapterNav.target(from: 121, starts: starts, forward: false) == 60)
        #expect(ChapterNav.target(from: 125, starts: starts, forward: false) == 120)
        #expect(ChapterNav.target(from: 150, starts: starts, forward: false) == 120)
        #expect(ChapterNav.target(from: 30, starts: starts, forward: false) == 0)      // ilk bölümün içinde: baştan
        #expect(ChapterNav.target(from: 0.5, starts: starts, forward: false) == nil)
        #expect(ChapterNav.target(from: 30, starts: [], forward: true) == nil)
        // Bölüm sonu (uyku zamanlayıcısı).
        #expect(ChapterNav.chapterEnd(at: 70, starts: starts, duration: 600) == 120)
        #expect(ChapterNav.chapterEnd(at: 400, starts: starts, duration: 600) == 600)
        #expect(ChapterNav.chapterEnd(at: 400, starts: starts, duration: 0) == nil)
    }

    @Test func sleepTimerDueDecision() {
        let now = Date.now
        #expect(!LessonSleep.until(now.addingTimeInterval(60)).isDue(time: 0, now: now))
        #expect(LessonSleep.until(now.addingTimeInterval(-1)).isDue(time: 0, now: now))
        #expect(!LessonSleep.endOfChapter(120).isDue(time: 119.9, now: now))
        #expect(LessonSleep.endOfChapter(120).isDue(time: 120, now: now))
    }
}

// MARK: - #30 geri sarma ısı şeridi

struct RewindHeatTests {
    @Test func rewindMomentIsMiddleOfReplayedSpan() throws {
        #expect(try near(#require(RewindHeat.moment(from: 100, to: 90)), 95))   // 10 sn geri → 5 sn öncesi
        #expect(try near(#require(RewindHeat.moment(from: 200, to: 140)), 150)) // uzun geri sürükleme: hedefe yakın (en çok 20 sn'lik pay)
        #expect(RewindHeat.moment(from: 100, to: 99) == nil)        // 2 sn'den kısa: titreme
        #expect(RewindHeat.moment(from: 100, to: 110) == nil)       // ileri
        #expect(RewindHeat.moment(from: 1000, to: 100) == nil)      // bölüme atlama, geri sarma değil
        #expect(RewindHeat.moment(from: .nan, to: 1) == nil)
    }

    @Test func appendingKeepsNewestWithinLimit() {
        let many = Array(repeating: 1.0, count: RewindHeat.limit)
        let next = RewindHeat.appending(5, to: many)
        #expect(next.count == RewindHeat.limit && next.last == 5)
        #expect(RewindHeat.appending(5, to: [1, 2]) == [1, 2, 5])
    }

    @Test func bucketsNormalizeAndStayInRange() {
        let times = [10.0, 11, 12, 12.5, 90]   // 100 sn'lik ders, 10 kova (10'ar sn)
        let buckets = RewindHeat.buckets(times: times, duration: 100, count: 10)
        #expect(buckets.count == 10)
        #expect(buckets[1] == 1)                  // 4 geri sarma (≥ 3 payda): en yoğun
        #expect(near(buckets[9], 1.0 / 4.0))      // 1 geri sarma / tepe 4
        #expect(buckets[0] == 0 && buckets[5] == 0)
        // Az sarma (tepe 3'ten az) soluk kalır.
        #expect(near(RewindHeat.buckets(times: [5], duration: 100, count: 10)[0], 1.0 / 3.0))
        // Geçersiz girdiler.
        #expect(RewindHeat.buckets(times: [1], duration: 0, count: 10).isEmpty)
        #expect(RewindHeat.buckets(times: [150, -3, .nan], duration: 100, count: 4) == [0, 0, 0, 0])
        #expect(RewindHeat.buckets(times: [100], duration: 100, count: 10)[9] > 0)   // son an son kovaya girer
    }
}

// MARK: - #33 izleme süresi

struct WatchAccumulatorTests {
    @Test func accumulatesTickDeltasAndEmitsOnStopOnlyWhenLongEnough() {
        var watch = WatchAccumulator()
        let start = Date(timeIntervalSince1970: 1_000_000)
        #expect(watch.tick(now: start) == nil)
        for second in 1...9 { _ = watch.tick(now: start.addingTimeInterval(Double(second))) }
        #expect(near(watch.pending, 9))
        #expect(watch.stop(now: start.addingTimeInterval(9)) == nil)           // 9 sn < 10: birikim sürer
        // Yeni oynatma: ilk tik yalnızca zamanı işaretler, 9 sn korunur.
        _ = watch.tick(now: start.addingTimeInterval(100))
        _ = watch.tick(now: start.addingTimeInterval(101))
        _ = watch.tick(now: start.addingTimeInterval(102))
        #expect(near(watch.pending, 11))
        let chunk = watch.stop(now: start.addingTimeInterval(102))
        #expect(chunk.map { near($0.seconds, 11) } == true)
        #expect(chunk?.start == start)
        #expect(watch.pending == 0)
        #expect(watch.stop(now: start.addingTimeInterval(200)) == nil)
    }

    @Test func longGapsAreCapped() {
        var watch = WatchAccumulator()
        let start = Date(timeIntervalSince1970: 0)
        _ = watch.tick(now: start)
        _ = watch.tick(now: start.addingTimeInterval(60))   // uygulama askıya alındı: en çok 1,5 sn sayılır
        #expect(near(watch.pending, WatchAccumulator.maxStep))
    }

    @Test func emitsEveryMaxChunkWhileWatching() {
        var watch = WatchAccumulator()
        var now = Date(timeIntervalSince1970: 0)
        var chunks: [WatchAccumulator.Chunk] = []
        for _ in 0...Int(WatchAccumulator.maxChunk) + 5 {
            if let chunk = watch.tick(now: now) { chunks.append(chunk) }
            now = now.addingTimeInterval(1)
        }
        #expect(chunks.count == 1 && near(chunks[0].seconds, WatchAccumulator.maxChunk))
    }
}

// MARK: - #16 kelimeye dokununca atla

struct WordSeekTests {
    @Test func urlsRoundTrip() throws {
        let url = try #require(WordSeek.url(row: 12, word: 7))
        let hit = try #require(WordSeek.parse(url))
        #expect(hit.row == 12 && hit.word == 7)
        #expect(WordSeek.parse(URL(string: "https://example.com/1/2")!) == nil)
        #expect(WordSeek.parse(URL(string: "dersseek://abc/2")!) == nil)
    }

    @Test func wordTimeUsesRealWordTimesWhenAvailable() {
        let row = TranscriptRow(id: 3, start: 10, end: 20, text: "bir iki üç dört",
                                spans: [.init(start: 10, end: 20, words: 4, times: [10.5, 12.0, 15.0, 19.0])])
        #expect(WordSeek.time(of: 2, in: row) == 15.0)
        #expect(WordSeek.time(of: 9, in: row) == nil)
        // Kelime zamanı yoksa paragraf içinde artan bir tahmin.
        let plain = TranscriptRow(id: 4, start: 0, end: 10, text: "bir iki üç dört")
        let first = WordSeek.time(of: 0, in: plain)
        let last = WordSeek.time(of: 3, in: plain)
        #expect(first != nil && last != nil && first! < last! && last! < 10)
    }

    @Test func attributedTextLinksEveryWord() {
        let text = "Bir çocuğun koşması."
        let words = FollowAlong.words(in: text)
        let attr = FollowAlong.attributed(text, words: words, current: nil, highlight: .yellow, readColor: .primary, upcoming: .primary,
                                          link: { WordSeek.url(row: 5, word: $0) })
        #expect(String(attr.characters) == text)
        let links = attr.runs.compactMap(\.link).map(\.absoluteString)
        #expect(links == ["dersseek://5/0", "dersseek://5/1", "dersseek://5/2"])
    }
}

// MARK: - #8 öğrenci konuşması (altyazı satırı düzeyi, kelime aralığı)

struct SpeakerAnalysisTests {
    private func line(_ i: Int, _ text: String = "metin") -> TranscriptSegment {
        TranscriptSegment(start: Double(i) * 2, end: Double(i) * 2 + 2, text: text)
    }

    @Test func requestsAreChunkedByFourHundredWithGlobalIndexes() {
        let segments = (0..<850).map { line($0, String(repeating: "a", count: 700)) }
        let requests = SpeakerAnalysis.requests(segments: segments)
        #expect(requests.map(\.segments.count) == [400, 400, 50])
        #expect(requests[1].segments.first?.i == 400 && requests[2].segments.last?.i == 849)
        #expect(requests[0].segments[0].text.count == SpeakerAnalysis.maxTextLength)
        #expect(SpeakerAnalysis.requests(segments: []).isEmpty)
    }

    @Test func requestsFollowOrderedSegmentsEvenWhenInputIsUnsorted() {
        let segments = [line(5, "ikinci"), line(0, "birinci")]
        #expect(SpeakerAnalysis.requests(segments: segments)[0].segments.map(\.text) == ["birinci", "ikinci"])
        #expect(TranscriptFormat.orderedSegments(segments).map(\.text) == ["birinci", "ikinci"])   // öğrenci sırası bu sıralamaya göre
    }

    @Test func mergeKeepsValidUniqueSortedIndexes() {
        let merged = SpeakerAnalysis.merge([SpeakersResponse(student: [5, 2, 99, -1]), SpeakersResponse(student: [2, 7])], segmentCount: 10)
        #expect(merged == [2, 5, 7])
    }

    @Test func responseDecodesWithMissingField() throws {
        #expect(try JSONDecoder().decode(SpeakersResponse.self, from: Data(#"{"student":[1,3]}"#.utf8)).student == [1, 3])
        #expect(try JSONDecoder().decode(SpeakersResponse.self, from: Data("{}".utf8)).student.isEmpty)
        let body = try JSONEncoder().encode(SpeakersRequest(segments: [SpeakerSegment(i: 0, text: "Hocam şu nasıl?")]))
        #expect(String(decoding: body, as: UTF8.self).contains(#""segments""#))
    }

    @Test func storeRoundTripsAndDetectsStaleResults() {
        let id = UUID()
        defer { VideoFiles.remove(lesson: id) }
        #expect(SpeakerAnalysis.load(lesson: id) == nil)
        let saved = LessonSpeakers(count: 12, student: [3, 8])
        SpeakerAnalysis.save(saved, lesson: id)
        #expect(SpeakerAnalysis.load(lesson: id) == saved)
        #expect(saved.version == 2 && saved.matches(segmentCount: 12))
        #expect(!saved.matches(segmentCount: 13))   // transkript yenilenmiş: eski kayıt kullanılmaz
        SpeakerAnalysis.delete(lesson: id)
        #expect(SpeakerAnalysis.load(lesson: id) == nil)
    }

    @Test func versionOneParagraphLevelFilesAreIgnored() throws {
        let id = UUID()
        defer { VideoFiles.remove(lesson: id) }
        _ = VideoFiles.directory(for: id)
        // Eski sürüm: paragraf düzeyli kayıt (19 paragraf); aynı sayıda satır olsa bile geçerli sayılmaz.
        try Data(#"{"version":1,"count":19,"student":[2,5]}"#.utf8).write(to: SpeakerAnalysis.url(lesson: id))
        #expect(SpeakerAnalysis.load(lesson: id) == nil)
        #expect(!LessonSpeakers(version: 1, count: 19, student: [2]).matches(segmentCount: 19))
    }
}

struct StudentWordTests {
    @Test func studentSpansMapToProportionalWordRanges() {
        // 6 kelime: öğretmen 2, öğrenci 3, öğretmen 1.
        let spans = [FollowAlong.Span(start: 0, end: 2, words: 2),
                     FollowAlong.Span(start: 2, end: 5, words: 3, student: true),
                     FollowAlong.Span(start: 5, end: 6, words: 1)]
        #expect(FollowAlong.studentWords(wordCount: 6, spans: spans) == [false, false, true, true, true, false])
        // Metin parçalarla tam tutmazsa (12 kelime) aralık aynı oranla ölçeklenir: 4..<10.
        let scaled = FollowAlong.studentWords(wordCount: 12, spans: spans)
        #expect(scaled == [false, false, false, false, true, true, true, true, true, true, false, false])
        // Öğrenci parçası yoksa ya da kelime yoksa boş.
        #expect(FollowAlong.studentWords(wordCount: 6, spans: spans.map { var s = $0; s.student = false; return s }).isEmpty)
        #expect(FollowAlong.studentWords(wordCount: 0, spans: spans) == [])
        // Zamanlama ile aynı bölme: öğrenci kelimelerinin zamanları öğrenci parçasının süresi içinde.
        let timing = FollowAlong.Timing(text: "bir iki üç dört beş altı", start: 0, end: 6, spans: spans)
        #expect(timing.students == [false, false, true, true, true, false])
        #expect(timing.times[2] >= 2 && timing.times[4] < 5)
    }

    @Test func attributedColorsOnlyStudentWords() {
        let text = "Ders sürüyor hocam şu nasıl yapılır"
        let words = FollowAlong.words(in: text)
        let students = [false, false, true, true, true, true]
        let attr = FollowAlong.attributed(text, words: words, current: nil, highlight: .yellow, readColor: .primary, upcoming: .primary,
                                          students: students, studentUpcoming: FollowAlong.studentColor)
        #expect(String(attr.characters) == text)
        let colored = attr.runs.filter { $0.foregroundColor == FollowAlong.studentColor }.map { String(attr[$0.range].characters) }
        #expect(colored == ["hocam", "şu", "nasıl", "yapılır"])
        let plain = attr.runs.filter { $0.foregroundColor == Color.primary }.map { String(attr[$0.range].characters) }
        #expect(plain.joined().contains("Ders") && plain.joined().contains("sürüyor") && !plain.joined().contains("hocam"))
        // Çalan kelime sarı vurguda kalır; öğrenci olsa da.
        let live = FollowAlong.attributed(text, words: words, current: 4, highlight: .yellow, readColor: .primary, upcoming: .secondary,
                                          students: students)
        #expect(live.runs.filter { $0.backgroundColor != nil }.map { String(live[$0.range].characters) } == ["nasıl"])
    }

    @Test func rowsMarkOnlyStudentLinesInsideMixedParagraph() {
        // Ders paragrafı: öğretmen + öğrenci sorusu + öğretmen (gerçek örnek).
        let segments = [TranscriptSegment(start: 0, end: 2.5, text: "Gençler merhaba. Hepiniz hoş geldiniz."),
                        TranscriptSegment(start: 2.5, end: 4.7, text: "Fotosenteze kaldığımız yerden devam"),
                        TranscriptSegment(start: 4.7, end: 7.7, text: "ediyoruz. Hocam kaçıncı sayfadayız?"),
                        TranscriptSegment(start: 7.7, end: 11.4, text: "Sayfa 15'ten 24'e kadar arkadaşlar")]
        let text = segments.map(\.text).joined(separator: " ")
        let paragraphs = [TranscriptParagraph(start: 0, end: 12, text: text)]
        let rows = TranscriptFormat.rows(paragraphs: paragraphs, translation: nil, language: .original, segments: segments, students: [2])
        let row = rows[0]
        #expect(row.hasStudent && row.spans.map(\.student) == [false, false, true, false])
        let words = FollowAlong.words(in: row.text)
        let flags = FollowAlong.studentWords(wordCount: words.count, spans: row.spans)
        let student = zip(words, flags).filter { $0.1 }.map { String(row.text[$0.0.range]) }
        #expect(student == ["ediyoruz.", "Hocam", "kaçıncı", "sayfadayız?"])   // satır düzeyi: yalnız o altyazı satırı
        // Öğrenci bilgisi yoksa hiçbir satır işaretli değil.
        let none = TranscriptFormat.rows(paragraphs: paragraphs, translation: nil, language: .original, segments: segments)
        #expect(!none[0].hasStudent)
        // Öğrenci sırası başlangıca göre sıralamaya göre: girdi sırasız olsa da aynı satır işaretlenir.
        let shuffled = TranscriptFormat.rows(paragraphs: paragraphs, translation: nil, language: .original,
                                             segments: segments.reversed(), students: [2])
        #expect(shuffled[0].spans.map(\.student) == [false, false, true, false])
    }

    @Test func cleanReadingKeepsStudentFlagOnSpans() {
        let row = TranscriptRow(id: 0, start: 0, end: 6, text: "bir iki eee hocam şu nasıl",
                                spans: [.init(start: 0, end: 3, words: 3), .init(start: 3, end: 6, words: 3, student: true)])
        let cleaned = CleanReading.clean(row)
        #expect(cleaned.text == "bir iki hocam şu nasıl")
        #expect(cleaned.spans.map(\.student) == [false, true])
        #expect(cleaned.spans.map(\.words) == [2, 3])
        let flags = FollowAlong.studentWords(wordCount: 5, spans: cleaned.spans)
        #expect(flags == [false, false, true, true, true])
    }

    @Test func rowsBuiltFromTranscriptsWithoutLinesStayWithoutSpans() {
        let rows = TranscriptFormat.rows(paragraphs: [TranscriptParagraph(start: 0, end: 5, text: "Metin")], translation: nil,
                                         language: .original, segments: [], students: [0])
        #expect(rows[0].spans.isEmpty && !rows[0].hasStudent)
    }
}

// MARK: - Oynatıcı modeli (arka uç gerektirmeyen davranışlar)

@MainActor
struct LessonPlayerModelTests {
    private func model(startAt: Double = 60) -> VideoPlayerModel {
        VideoPlayerModel(videoID: "EKGRs8q7HlA", startAt: startAt, duration: 600, embeddable: false)   // ses yok → öneri kartı
    }

    @Test func downloadedVideoSelectsLocalPlaybackBackend() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "listening-\(UUID().uuidString).mp4")
        try Data([0, 1, 2]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let withVideo = VideoPlayerModel(videoID: "EKGRs8q7HlA", embeddable: true, videoURL: file)
        #expect(withVideo.backend == .audio && withVideo.isVideoFile)
        let missing = VideoPlayerModel(videoID: "EKGRs8q7HlA", embeddable: true, videoURL: file.appending(path: "yok"))
        #expect(missing.backend == .web && !missing.isVideoFile)
        // Ses önerisi kartında video kipi yok; kayıtlı video silinirse web'e döner.
        withVideo.videoRemoved()
        #expect(!withVideo.isVideoFile && withVideo.backend == .web)
    }

    @Test func rewindIsRecordedForSkipBackAndScrubBackOnly() {
        let player = model()
        var moments: [Double] = []
        player.onRewind = { moments.append($0) }
        player.skip(-10)                       // 60 → 50: ortası 55
        #expect(moments.count == 1 && near(moments[0], 55))
        player.skip(10)                        // ileri: kayıt yok
        player.seek(to: 20)                    // paragrafa dokunma gibi doğrudan atlama: kayıt yok
        #expect(moments.count == 1)
        player.scrub(to: 5)                    // 20 → 5 geri sürükleme
        #expect(moments.count == 2 && moments[1] > 5 && moments[1] < 20)
        player.scrub(to: 4.5)                  // 0,5 sn: titreme
        #expect(moments.count == 2)
    }

    @Test func loopSeeksToStartAndRejectsTooShortLoops() {
        let player = model()
        player.setLoop(start: 30, end: 45, play: false)
        #expect(player.loop == ABLoop(start: 30, end: 45) && near(player.currentTime, 30))
        player.setLoop(start: 30, end: 30.2, play: false)
        #expect(player.loop == nil)
        player.setLoop(start: 30, end: 45, play: false)
        player.clearLoop()
        #expect(player.loop == nil)
    }

    @Test func chapterButtonsSeekUsingChapterStarts() {
        let player = model(startAt: 70)
        player.chapterStarts = [0, 60, 120]
        player.nextChapter()
        #expect(near(player.currentTime, 120))
        player.previousChapter()               // 120'den (bölüm başı) → bir önceki
        #expect(near(player.currentTime, 60))
        player.seek(to: 100)
        player.previousChapter()               // bölüm içinde: bölüm başı
        #expect(near(player.currentTime, 60))
        player.seek(to: 130)
        player.nextChapter()                   // son bölümde sonraki yok: yerinde kalır
        #expect(near(player.currentTime, 130))
    }

    @Test func sleepTimerSetsAndClears() {
        let player = model(startAt: 70)
        player.chapterStarts = [0, 60, 120]
        player.setSleep(minutes: 10)
        #expect((player.sleepRemaining ?? 0) > 9 * 60)
        player.setSleepEndOfChapter()
        #expect(player.sleep == .endOfChapter(120) && player.sleepRemaining == nil)
        player.cancelSleep()
        #expect(player.sleep == nil)
    }

    @Test func expiredSleepIsClearedWhenPlayStarts() {
        let player = model()
        player.setSleep(minutes: -1)                 // süresi çoktan geçmiş
        #expect(player.sleep != nil)
        player.play()
        #expect(player.sleep == nil)
        player.setSleep(minutes: 10)
        player.play()                                // süresi dolmamış zamanlayıcı korunur
        #expect(player.sleep != nil)
    }

    @Test func chapterEndSleepFollowsUserSeeks() {
        let player = model(startAt: 70)
        player.chapterStarts = [0, 60, 120]
        player.setSleepEndOfChapter()
        #expect(player.sleep == .endOfChapter(120))
        player.seek(to: 130)                         // sonraki bölüme gidildi: bitiş artık videonun sonu
        #expect(player.sleep == .endOfChapter(600))
        player.seek(to: 10)                          // başa dönüldü: ilk bölümün bitişi
        #expect(player.sleep == .endOfChapter(60))
        player.skip(10)
        #expect(player.sleep == .endOfChapter(60))
        player.chapterStarts = []
        player.seek(to: 20)                          // bölüm bilgisi yok, süre var: videonun sonu
        #expect(player.sleep == .endOfChapter(600))
        let unknownDuration = VideoPlayerModel(videoID: "EKGRs8q7HlA", startAt: 5, duration: 0, embeddable: false)
        unknownDuration.setSleepEndOfChapter()        // bitiş bilinmiyor: kurulmaz
        #expect(unknownDuration.sleep == nil)
    }

    @Test func loopEndIsClampedToDurationAndRejectedWhenTooShort() {
        let player = model()                          // süre 600
        #expect(player.setLoop(start: 590, end: 700, play: false))
        #expect(player.loop?.end == 599.9)
        #expect(!player.setLoop(start: 599.5, end: 650, play: false))   // kırpılınca 1 sn'den kısa
        #expect(player.loop == nil)
        #expect(!player.setLoop(start: 10, end: 10.4, play: false))
        // Duraklatılmışken döngünün çok dışına atlanınca döngü kapanır; yakın atlama korur.
        #expect(player.setLoop(start: 30, end: 45, play: false))
        player.seek(to: 31)
        #expect(player.loop != nil)
        player.seek(to: 300)
        #expect(player.loop == nil)
    }

    @Test func silenceSkipNeedsPlayerMedia() throws {
        #expect(!model().canSkipSilence)              // ses/video dosyası yok
        let file = FileManager.default.temporaryDirectory.appending(path: "listening-\(UUID().uuidString).mp4")
        try Data([0, 1, 2]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(VideoPlayerModel(videoID: "EKGRs8q7HlA", embeddable: true, videoURL: file).canSkipSilence)   // yerel video dahil
    }

    @Test func pictureInPictureKeepsPlayerAliveAfterScreenCloses() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "listening-\(UUID().uuidString).mp4")
        try Data([0, 1, 2]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let before = PictureInPictureKeeper.count
        let player = VideoPlayerModel(videoID: "EKGRs8q7HlA", embeddable: true, videoURL: file)
        player.suspend()                               // PiP yok: normal söküm, tutulmaz
        #expect(PictureInPictureKeeper.count == before)
        player.pictureInPictureStarted(AVPlayerViewController())
        #expect(player.isPictureInPictureActive)
        player.suspend()                               // PiP açık: oynatıcı canlı tutulur
        #expect(PictureInPictureKeeper.count == before + 1)
        player.pictureInPictureStopped()
        #expect(!player.isPictureInPictureActive && PictureInPictureKeeper.count == before)
    }

    @Test func rateChangeIsReported() {
        let player = model()
        var rates: [Double] = []
        player.onRateChange = { rates.append($0) }
        player.rate = 1.5
        player.rate = 1.5
        player.rate = 1.25
        #expect(rates == [1.5, 1.25])
    }
}

// MARK: - Kayıtlar (izleme süresi, geri sarma, hız)

@MainActor
struct WatchRecorderTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: VideoLesson.self, StudySession.self, ListeningDay.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @Test func watchTimeGoesToLessonSessionAndDay() throws {
        let context = try makeContext()
        let lesson = VideoLesson(url: "https://youtu.be/EKGRs8q7HlA")
        lesson.courseID = UUID()
        context.insert(lesson)
        WatchRecorder.record(start: .now, seconds: 12, lesson: lesson)
        WatchRecorder.record(start: .now, seconds: 30, lesson: lesson)
        WatchRecorder.record(start: .now, seconds: 9, lesson: lesson)   // 10 sn'den kısa: kaydedilmez
        #expect(near(lesson.watchedSeconds, 42))
        let sessions = try context.fetch(FetchDescriptor<StudySession>())
        #expect(sessions.count == 2 && sessions.allSatisfy { $0.kind == "video" && $0.episodeID == lesson.id && $0.courseID == lesson.courseID })
        let days = try context.fetch(FetchDescriptor<ListeningDay>())
        #expect(days.count == 1 && near(days[0].seconds, 42))
    }

    @Test func rewindAndRateAreStoredOnLesson() throws {
        let context = try makeContext()
        let lesson = VideoLesson(url: "https://youtu.be/EKGRs8q7HlA")
        context.insert(lesson)
        WatchRecorder.recordRewind(55, lesson: lesson)
        WatchRecorder.recordRewind(80, lesson: lesson)
        #expect(lesson.rewindTimes == [55, 80])
        WatchRecorder.recordRate(1.5, lesson: lesson)
        #expect(lesson.playbackRate == 1.5)
        WatchRecorder.recordRate(0, lesson: lesson)        // geçersiz hız yok sayılır
        WatchRecorder.recordRate(.nan, lesson: lesson)
        #expect(lesson.playbackRate == 1.5)
        // Silinmiş/bağlamsız derse dokunulmaz.
        WatchRecorder.record(start: .now, seconds: 30, lesson: nil)
        WatchRecorder.recordRewind(1, lesson: VideoLesson(url: "x"))
    }
}

// MARK: - Altyazı dizini ve video sessizlik ölçümü

struct CaptionIndexTests {
    private func brute(start: Double, end: Double, segments: [TranscriptSegment]) -> [FollowAlong.Span] {
        segments.sorted { $0.start < $1.start }.compactMap { s in
            let middle = (s.start + s.end) / 2
            let count = s.text.split(whereSeparator: \.isWhitespace).count
            guard middle >= start, middle <= end, count > 0 else { return nil }
            return FollowAlong.Span(start: s.start, end: max(s.start, s.end), words: count, times: s.w.flatMap { $0.count == count ? $0 : nil })
        }
    }

    @Test func indexMatchesFullScanForOverlappingUnsortedCaptions() {
        // Örtüşen (otomatik altyazı gibi) ve sırasız satırlar; bazıları boş ya da kelime zamanlı.
        var segments: [TranscriptSegment] = (0..<400).map { i in
            let start = Double(i) * 2.0 + Double(i % 3) * 0.1
            let words = (0..<(i % 5)).map { "k\($0)" }
            let w: [Double]? = i % 7 == 0 && !words.isEmpty ? words.indices.map { start + Double($0) * 0.2 } : nil
            return TranscriptSegment(start: start, end: start + 1.5 + Double(i % 4), text: words.joined(separator: " "), w: w)
        }
        segments.reverse()
        let index = TranscriptFormat.CaptionIndex(segments)
        for (a, b) in [(0.0, 10.0), (10.0, 50.0), (49.9, 50.1), (300.0, 801.0), (-5.0, 1.0), (900.0, 1000.0), (20.0, 19.0)] {
            #expect(index.spans(start: a, end: b) == brute(start: a, end: b, segments: segments), "\(a)–\(b)")
        }
        #expect(TranscriptFormat.spans(start: 10, end: 50, segments: segments) == brute(start: 10, end: 50, segments: segments))
        #expect(TranscriptFormat.CaptionIndex([]).spans(start: 0, end: 10).isEmpty)
    }

    @Test func rowsBuiltWithSharedIndexCarrySpans() {
        let segments = [TranscriptSegment(start: 5, end: 9, text: "devam ediyoruz"), TranscriptSegment(start: 0, end: 2, text: "Merhaba gençler.")]
        let paragraphs = [TranscriptParagraph(start: 0, end: 4, text: "Merhaba gençler."), TranscriptParagraph(start: 4, end: 10, text: "devam ediyoruz")]
        let rows = TranscriptFormat.rows(paragraphs: paragraphs, translation: nil, language: .original, segments: segments)
        #expect(rows.map(\.spans.count) == [1, 1])
        #expect(rows[1].spans[0].start == 5)
    }
}

struct PauseMeasurementTests {
    @Test func measuresPausesInsideVideoFilesAndCachesThem() async throws {
        // Fixture: 6 sn'lik video; 2–4 sn arası sessizlik, ötesi 440 Hz ton.
        let source = try #require(Bundle(for: BundleToken.self).url(forResource: "pauses", withExtension: "mp4"))
        let copy = FileManager.default.temporaryDirectory.appending(path: "pauses-\(UUID().uuidString).mp4")
        try FileManager.default.copyItem(at: source, to: copy)
        defer {
            try? FileManager.default.removeItem(at: copy)
            try? FileManager.default.removeItem(at: copy.appendingPathExtension("pauses.json"))
        }
        #expect(PauseMeasurement.isVideoContainer(copy))
        let pauses = await PauseMeasurement.load(copy)
        let found = try #require(pauses.first)
        #expect(pauses.count == 1)
        #expect(abs(found.start - 2.0) < 0.25 && abs(found.end - 4.0) < 0.25)
        #expect(SilenceSkip.target(at: 3.0, pauses: pauses) != nil)    // ortasındayken atlanır
        #expect(SilenceSkip.target(at: 1.0, pauses: pauses) == nil)
        // İkinci okuma önbellekten gelir.
        #expect(FileManager.default.fileExists(atPath: copy.appendingPathExtension("pauses.json").path))
        #expect(await PauseMeasurement.load(copy) == pauses)
    }

    @Test func audioFilesUseSpeechPausesAndMissingFilesAreEmpty() async {
        #expect(!PauseMeasurement.isVideoContainer(URL(fileURLWithPath: "/tmp/ders.m4a")))
        #expect(await PauseMeasurement.load(URL(fileURLWithPath: "/tmp/yok-\(UUID().uuidString).mp4")).isEmpty)
        #expect(await PauseMeasurement.load(URL(fileURLWithPath: "/tmp/yok-\(UUID().uuidString).m4a")).isEmpty)
    }
}
