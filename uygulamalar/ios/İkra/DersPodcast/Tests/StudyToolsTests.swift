import AVFoundation
import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import Ikra

// Ders Stüdyosu öğrenme araçları (#18–#28, #34, #35, #37): saf mantık, kodlama ve kayıt davranışları.

private func para(_ start: Double, _ end: Double, _ text: String = "Metin") -> TranscriptParagraph {
    TranscriptParagraph(start: start, end: end, text: text)
}

private func transcript(paragraphs: [TranscriptParagraph], chapters: [VideoChapter] = [], notes: LectureNotes? = nil,
                        keyframes: [Keyframe] = [], language: String = "tr", translation: TranscriptTranslation? = nil,
                        duration: Double = 600) -> VideoTranscript {
    let video = VideoInfo(id: "EKGRs8q7HlA", url: "https://www.youtube.com/watch?v=EKGRs8q7HlA", title: "Hücre", channel: "Kanal",
                          duration: duration, thumbnail: nil, chapters: chapters, captions: [], language: language)
    return VideoTranscript(video: video, source: "ai", language: language, segments: [], paragraphs: paragraphs, chapters: chapters,
                           translation: translation, notes: notes, keyframes: keyframes, warnings: [])
}

private func close(_ a: [Double], _ b: [Double]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-9 }
}

private func question(_ text: String, choices: [String] = ["A şıkkı", "B şıkkı", "C şıkkı", "D şıkkı"], answer: Int = 1,
                      time: Double? = nil) -> StudyQuestion {
    StudyQuestion(question: text, choices: choices, answer: answer, explanation: "Çünkü öyle.", time: time)
}

// MARK: - Metin hazırlama

struct StudyTextTests {
    @Test func linesUseTimestampPrefixAndCollapseWhitespace() {
        let text = StudyText.lines([para(75, 90, "İkinci"), para(0, 10, "Merhaba   dünya\n bugün")])
        #expect(text == "[00:00] Merhaba dünya bugün\n[01:15] İkinci")
    }

    @Test func hourTimestampsKeepServerFormat() {
        #expect(StudyText.lines([para(3725, 3740, "Geç")]) == "[1:02:05] Geç")
    }

    @Test func linesShrinkProportionallyAndKeepEveryParagraph() {
        let long = String(repeating: "kelime ", count: 60)   // ~420 karakter
        let text = StudyText.lines([para(0, 60, long), para(60, 120, long), para(120, 180, long)], maxChars: 600)
        #expect(text.count <= 600)
        #expect(text.contains("[00:00]") && text.contains("[01:00]") && text.contains("[02:00]"))
    }

    @Test func linesFromRangeFilterByStart() {
        let items = [para(0, 50, "bir"), para(60, 110, "iki"), para(130, 170, "üç")]
        #expect(StudyText.lines(items, from: 60, to: 130) == "[01:00] iki")
    }

    @Test func recentLinesCoverLastNinetySeconds() {
        let items = [para(0, 60, "a"), para(60, 120, "b"), para(120, 180, "c"), para(180, 240, "d")]
        let text = StudyText.recentLines(items, endingAt: 200)
        #expect(!text.contains("[00:00]"))
        #expect(text.contains("[01:00]") && text.contains("[02:00]") && text.contains("[03:00]"))
        // Aralık dışında kalan zamanda bile an paragrafı gelir.
        #expect(StudyText.recentLines([para(0, 10, "x")], endingAt: 5000).contains("[00:00] x"))
        #expect(StudyText.recentLines([], endingAt: 5).isEmpty)
    }

    @Test func excerptCutsAtWordBoundary() {
        #expect(StudyText.excerpt("kısa", maxChars: 20) == "kısa")
        let cut = StudyText.excerpt("bir iki üç dört beş altı", maxChars: 10)
        #expect(cut.hasSuffix("…") && cut.count <= 11 && !cut.contains("üç…"))
    }

    @Test func chapterRangesAndIndexes() {
        let chapters = [VideoChapter(title: "Son", start: 120), VideoChapter(title: "Giriş", start: 0), VideoChapter(title: "Zar", start: 60)]
        #expect(StudyText.chapterRange(chapters, index: 0, end: 200) == ClipRange(start: 0, end: 60))
        #expect(StudyText.chapterRange(chapters, index: 2, end: 200) == ClipRange(start: 120, end: 200))
        #expect(StudyText.chapterRange(chapters, index: 3, end: 200) == nil)
        #expect(StudyText.chapterIndex(chapters, at: 30) == 0)
        #expect(StudyText.chapterIndex(chapters, at: 130) == 2)
        #expect(StudyText.chapterIndex([], at: 5) == nil)
    }

    @Test func lessonTextNeverExceedsBudget() {
        let notes = LectureNotes(summary: String(repeating: "özet ", count: 4000), keyPoints: [], concepts: [], formulas: [], questions: [], examTips: [])
        let t = transcript(paragraphs: (0..<50).map { para(Double($0) * 10, Double($0) * 10 + 10, String(repeating: "kelime ", count: 40)) }, notes: notes)
        #expect(StudyText.lessonText(t, maxChars: 5000).count <= 5000)
        #expect(StudyText.lessonText(t, maxChars: 5000).contains("[00:00]"))
    }

    @Test func feynmanReferenceUsesChapterTextOrNotes() {
        let notes = LectureNotes(summary: "Özet metni.", keyPoints: [NoteKeyPoint(text: "Ana nokta", time: 5)],
                                 concepts: [NoteConcept(name: "Zar", definition: "Seçici geçirgen", time: 8)],
                                 formulas: [], questions: [], examTips: [])
        let t = transcript(paragraphs: [para(0, 50, "Giriş metni"), para(60, 110, "Zar metni")],
                           chapters: [VideoChapter(title: "Giriş", start: 0), VideoChapter(title: "Zar", start: 60)], notes: notes)
        #expect(StudyText.reference(t, chapter: 1, end: 120) == "Zar metni")
        let whole = StudyText.reference(t, chapter: nil, end: 120)
        #expect(whole.contains("Özet metni.") && whole.contains("- Ana nokta") && whole.contains("- Zar: Seçici geçirgen"))
        #expect(StudyText.reference(transcript(paragraphs: [para(0, 5, "Ham metin")]), chapter: nil, end: 5) == "Ham metin")
    }

    @Test func quizScopeFallsBackWhenNoChapter() {
        let chapters = [VideoChapter(title: "Giriş", start: 0), VideoChapter(title: "Zar", start: 100)]
        #expect(QuizScope.resolve(chapters: chapters, chapter: 1, end: 400, currentTime: 0).range == ClipRange(start: 100, end: 400))
        #expect(QuizScope.resolve(chapters: [], chapter: nil, end: 4000, currentTime: 1000).range == ClipRange(start: 400, end: 1000))
        #expect(QuizScope.resolve(chapters: [], chapter: nil, end: 4000, currentTime: 10).range == ClipRange(start: 0, end: 600))
        #expect(QuizScope.resolve(chapters: [], chapter: nil, end: 200, currentTime: 0).range == ClipRange(start: 0, end: 200))
    }
}

// MARK: - Quiz doğrulama, net ve zayıf konular

struct QuizRulesTests {
    @Test func sanitizeDropsInvalidQuestions() {
        let good = question("Hücre zarı nedir?")
        #expect(StudyQuizRules.sanitize(good) == good)
        #expect(StudyQuizRules.sanitize(question("  ")) == nil)
        #expect(StudyQuizRules.sanitize(question("Q?", answer: 4)) == nil)
        #expect(StudyQuizRules.sanitize(question("Q?", answer: -1)) == nil)
        #expect(StudyQuizRules.sanitize(question("Q?", choices: ["tek"], answer: 0)) == nil)
        #expect(StudyQuizRules.sanitize(question("Q?", choices: ["Aynı", "aynı", "Başka"], answer: 0)) == nil)
        #expect(StudyQuizRules.sanitize(question("Q?", choices: ["A", " ", "C"], answer: 0)) == nil)
    }

    @Test func sanitizeLimitsAndDeduplicates() {
        let items = [question("Bir?"), question("bir?"), question("İki?", answer: 9), question("Üç?"), question("Dört?")]
        let clean = StudyQuizRules.sanitize(items, limit: 2)
        #expect(clean.map(\.question) == ["Bir?", "Üç?"])
    }

    @Test func letterAndCorrectness() {
        #expect(StudyQuizRules.letter(0) == "A" && StudyQuizRules.letter(4) == "E" && StudyQuizRules.letter(-1) == "•")
        #expect(StudyQuizRules.isCorrect(question("Q?", answer: 2), selected: 2))
        #expect(!StudyQuizRules.isCorrect(question("Q?", answer: 2), selected: nil))
    }

    @Test func netIsCorrectMinusWrongOverFour() {
        #expect(ExamScore.net(correct: 10, wrong: 4) == 9)
        #expect(ExamScore.net(correct: 0, wrong: 2) == -0.5)
        let questions = [question("1?", answer: 1), question("2?", answer: 0), question("3?", answer: 2), question("4?", answer: 3)]
        let score = ExamScore.compute(questions, answers: [0: 1, 1: 3, 2: 2])
        #expect(score == ExamScore(correct: 2, wrong: 1, blank: 1))
        #expect(score.net == 1.75)
        #expect(ExamScore.netText(7.5) == "7,5" && ExamScore.netText(9) == "9")
    }

    @Test func weakTopicsGroupByChapterAndSortByMistakes() {
        let chapters = [VideoChapter(title: "Giriş", start: 0), VideoChapter(title: "Zar", start: 100), VideoChapter(title: "Çekirdek", start: 200)]
        let questions = [question("a?", answer: 0, time: 10), question("b?", answer: 0, time: 120), question("c?", answer: 0, time: 150),
                         question("d?", answer: 0, time: 210), question("e?", answer: 0, time: nil)]
        // Doğru: a, d. Yanlış: b, c (Zar), boş: e (zamansız → Genel).
        let weak = ExamAnalysis.weakTopics(questions, answers: [0: 0, 1: 2, 2: 1, 3: 0], chapters: chapters)
        #expect(weak.map(\.title) == ["Zar", "Genel"])
        #expect(weak[0].wrong == 2 && weak[0].total == 2 && weak[0].time == 120)
        #expect(weak[1].wrong == 1 && weak[1].total == 1)
        #expect(ExamAnalysis.weakTopics(questions, answers: [0: 0, 1: 0, 2: 0, 3: 0, 4: 0], chapters: chapters).isEmpty)
    }

    @Test func chapterBoundaryDetectionIgnoresSeeksAndShortChapters() {
        let chapters = [VideoChapter(title: "A", start: 0), VideoChapter(title: "B", start: 120), VideoChapter(title: "C", start: 300)]
        // Bölüm sonu 120 − 0,3: doğal ilerlemede yakalanır.
        #expect(ChapterQuizTiming.finishedChapter(previous: 119.4, current: 119.9, chapters: chapters, end: 500) == 0)
        #expect(ChapterQuizTiming.finishedChapter(previous: 118.0, current: 118.5, chapters: chapters, end: 500) == nil)
        // Atlama (3 sn'den büyük adım) sayılmaz.
        #expect(ChapterQuizTiming.finishedChapter(previous: 10, current: 130, chapters: chapters, end: 500) == nil)
        // Geri sarma sayılmaz.
        #expect(ChapterQuizTiming.finishedChapter(previous: 125, current: 119.9, chapters: chapters, end: 500) == nil)
        // Son bölüm, işlenen aralığın sonunda biter.
        #expect(ChapterQuizTiming.finishedChapter(previous: 499.2, current: 499.8, chapters: chapters, end: 500) == 2)
        // 60 sn'den kısa bölüm atlanır.
        let short = [VideoChapter(title: "Kısa", start: 0), VideoChapter(title: "Uzun", start: 30)]
        #expect(ChapterQuizTiming.finishedChapter(previous: 29.5, current: 29.9, chapters: short, end: 400) == nil)
    }
}

// MARK: - Kesit planlama

struct ClipPlannerTests {
    @Test func shortParagraphExtendsAndNeighboursMerge() {
        let items = [para(0, 10), para(10, 20), para(20, 30), para(100, 125)]
        // 5. sn: [0,10] <12 → [0,20]; 12. sn: [10,20] → [10,30]; birleşince [0,30]. 110. sn tek paragraf (25 sn).
        let clips = ClipPlanner.plan(times: [5, 12, 110], paragraphs: items)
        #expect(clips == [ClipRange(start: 0, end: 30), ClipRange(start: 100, end: 125)])
    }

    @Test func totalIsCappedAndOrdered() {
        let items = [para(0, 20), para(100, 120), para(200, 220)]
        let clips = ClipPlanner.plan(times: [210, 5, 105], paragraphs: items, maxTotal: 45)
        // Bütçe (45 sn) üç kesite yetmiyor: kesitler dersin başına yığılmaz, derse yayılır (baş ve son).
        #expect(clips == [ClipRange(start: 0, end: 20), ClipRange(start: 200, end: 220)])
        #expect(ClipPlanner.plan(times: [5], paragraphs: []).isEmpty)
    }

    @Test func oversizedMergedClipFallsBackToSeparateClips() {
        // Birbirine bitişik 10 paragraf tek 200 sn'lik kesite birleşir; bütçe 60 sn ise ayrı kesitler seçilir.
        let items = (0..<10).map { para(Double($0) * 20, Double($0) * 20 + 20) }
        let clips = ClipPlanner.plan(times: items.map(\.start), paragraphs: items, maxTotal: 60)
        #expect(!clips.isEmpty && clips.reduce(0) { $0 + $1.duration } <= 60)
    }

    @Test func mergeJoinsOverlapsAndSmallGaps() {
        let merged = ClipPlanner.merge([ClipRange(start: 30, end: 40), ClipRange(start: 0, end: 10), ClipRange(start: 11, end: 20)], gap: 1.5)
        #expect(merged == [ClipRange(start: 0, end: 20), ClipRange(start: 30, end: 40)])
    }

    @Test func cardClipFollowsParagraphAndFallsBack() {
        let items = [para(0, 30), para(30, 100)]
        #expect(ClipPlanner.cardClip(at: 40, paragraphs: items) == ClipRange(start: 30, end: 75))
        #expect(ClipPlanner.cardClip(at: 10, paragraphs: items) == ClipRange(start: 0, end: 30))
        #expect(ClipPlanner.cardClip(at: 500, paragraphs: items) == ClipRange(start: 500, end: 520))
        #expect(ClipPlanner.cardClip(at: 5, paragraphs: []) == ClipRange(start: 5, end: 25))
    }

    @Test func teacherSummaryTimelineStacksClipsWithGap() {
        let items = [para(10, 20, "A"), para(20, 30, "B"), para(200, 215, "C"), para(215, 230, "D")]
        let chapters = [VideoChapter(title: "Giriş", start: 0), VideoChapter(title: "Zar", start: 100)]
        let clips = [ClipRange(start: 10, end: 30), ClipRange(start: 200, end: 230)]
        let plan = TeacherSummaryPlan.build(clips: clips, paragraphs: items, chapters: chapters, fallbackTitle: "Ana noktalar")
        #expect(plan.chapters.map(\.title) == ["Giriş", "Zar"])
        #expect(plan.chapters.map { $0.scenes.count } == [1, 1])
        #expect(close(plan.timeline.chapters.map(\.start), [0, 20.35]))
        #expect(plan.timeline.turns.map(\.text) == ["A", "B", "C", "D"])
        #expect(close(plan.timeline.turns.map(\.start), [0, 10, 20.35, 35.35]))
        #expect(plan.timeline.turns.map(\.chapterIndex) == [0, 0, 1, 1])
        #expect(abs(plan.timeline.duration - 50.35) < 0.001)
        #expect(abs(TeacherSummaryPlan.totalDuration(clips) - 50.35) < 0.001)
        #expect(close(TeacherSummaryPlan.offsets(clips), [0, 20.35]))
    }

    @Test func summaryWithoutChaptersUsesSingleGroupAndDropsEmptyClips() {
        let items = [para(0, 15, "Metin"), para(100, 110, "   ")]
        let clips = [ClipRange(start: 0, end: 15), ClipRange(start: 100, end: 110)]
        #expect(TeacherSummaryPlan.usable(clips, paragraphs: items) == [ClipRange(start: 0, end: 15)])
        let plan = TeacherSummaryPlan.build(clips: clips, paragraphs: items, chapters: [], fallbackTitle: "Ana noktalar")
        #expect(plan.chapters.map(\.title) == ["Ana noktalar"])
        #expect(plan.timeline.turns.count == 1 && abs(plan.timeline.duration - 15) < 1e-9)
    }
}

// MARK: - Kart taslakları ve dışa aktarma

struct CardExportTests {
    private let notes = LectureNotes(
        summary: "", keyPoints: [],
        concepts: [NoteConcept(name: "Difüzyon", definition: "Maddenin yoğun yerden seyrek yere geçişi", time: 40),
                   NoteConcept(name: "Ozmos nedir?", definition: "Suyun geçişi", time: 70)],
        formulas: [NoteFormula(name: "Ohm yasası", expression: "V = I · R", meaning: "Gerilim, akım ve direnç ilişkisi", time: 90)],
        questions: [NoteQuestion(question: "Zarın görevi nedir?", answer: "Seçici geçirgenlik", time: 100)], examTips: [])

    @Test func noteCardDraftsCarryTimesAndSkipExisting() {
        let all = NoteCardPlan.drafts(notes, existingFronts: [], formulas: true)
        #expect(all.map(\.front) == ["Difüzyon nedir?", "Ozmos nedir?", "Zarın görevi nedir?", "Ohm yasası formülü nedir?"])
        #expect(all.map(\.time) == [40, 70, 100, 90])
        #expect(all.last?.back == "V = I · R\nGerilim, akım ve direnç ilişkisi")
        let rest = NoteCardPlan.drafts(notes, existingFronts: ["difüzyon NEDİR?"], concepts: true, questions: false, formulas: false)
        #expect(rest.map(\.front) == ["Ozmos nedir?"])
        #expect(NoteCardPlan.drafts(notes, existingFronts: [], concepts: false, questions: false, formulas: false).isEmpty)
    }

    @Test func csvQuotesAndStartsWithBOM() {
        let rows = [CardExportRow(front: "Ön, yüz", back: "Arka \"tırnaklı\"\nsatır", tag: "Ders Adı")]
        #expect(CardExport.csv(rows) == "\u{FEFF}Ön yüz,Arka yüz,Etiket\r\n\"Ön, yüz\",\"Arka \"\"tırnaklı\"\"\nsatır\",Ders Adı\r\n")
        #expect(CardExport.csvField("düz metin") == "düz metin")
        #expect(CardExport.csvField("a\rb") == "\"a\rb\"")
    }

    @Test func ankiEscapesHtmlTabsAndNewlines() {
        #expect(CardExport.ankiField("a < b & c\tD\nE") == "a &lt; b &amp; c D<br>E")
        #expect(CardExport.ankiField("x\r\ny") == "x<br>y")
        #expect(CardExport.ankiTag("Hücre  Zarı\nDersi") == "Hücre_Zarı_Dersi")
        let text = CardExport.anki([CardExportRow(front: "Ön", back: "Arka\nsatır", tag: "Hücre Zarı")])
        #expect(text == "#separator:tab\n#html:true\n#tags column:3\nÖn\tArka<br>satır\tHücre_Zarı\n")
    }
}

// MARK: - Çalışma kâğıdı, slayt ve dublaj

struct OutputPlanTests {
    @Test func blankedSentenceReplacesAnswerOrKeepsServerBlank() {
        #expect(WorksheetLayout.blanked(sentence: "Hücre zarı seçici geçirgendir.", answer: "seçici") == "Hücre zarı ________ geçirgendir.")
        #expect(WorksheetLayout.blanked(sentence: "İNCE bağırsak emilim yapar", answer: "ince") == "________ bağırsak emilim yapar")
        #expect(WorksheetLayout.blanked(sentence: "Zar _____ geçirgendir.", answer: "seçici") == "Zar _____ geçirgendir.")
        #expect(WorksheetLayout.blanked(sentence: "Başka bir cümle", answer: "yok") == "Başka bir cümle ________")
    }

    @Test func shuffledOrderIsDeterministicAndMovesEveryItem() {
        for count in 2...12 {
            let order = WorksheetLayout.shuffledOrder(count: count, seed: 42)
            #expect(Set(order) == Set(0..<count))
            #expect(!order.indices.contains { order[$0] == $0 })
            #expect(order == WorksheetLayout.shuffledOrder(count: count, seed: 42))
        }
        #expect(WorksheetLayout.shuffledOrder(count: 1, seed: 1) == [0])
        #expect(WorksheetLayout.shuffledOrder(count: 0, seed: 1).isEmpty)
        #expect(WorksheetLayout.seed(for: "abc") == WorksheetLayout.seed(for: "abc"))
        #expect(WorksheetLayout.seed(for: "abc") != WorksheetLayout.seed(for: "abd"))
    }

    @Test func matchingKeyPointsToShuffledPositions() {
        // 0. konumda 1. tanım, 1. konumda 2., 2. konumda 0. tanım gösteriliyor.
        #expect(WorksheetLayout.matchingKey(order: [1, 2, 0]) == ["C", "A", "B"])
    }

    @Test func slidesFollowFramesWithSummaryAndKeyPoints() {
        let notes = LectureNotes(summary: "Dersin özeti", keyPoints: [NoteKeyPoint(text: "Birinci nokta", time: 20), NoteKeyPoint(text: "İkinci nokta", time: 150)],
                                 concepts: [NoteConcept(name: "Zar", definition: "Hücre sınırı", time: 30)], formulas: [], questions: [], examTips: [])
        let frames = [Keyframe(id: "f2", time: 100, image: "", caption: "", text: ""), Keyframe(id: "f1", time: 10, image: "", caption: "Hücre şeması", text: "")]
        let t = transcript(paragraphs: [para(10, 60, "İlk bölümün metni."), para(100, 190, "İkinci bölümün metni.")],
                           chapters: [VideoChapter(title: "Giriş", start: 0), VideoChapter(title: "Zar", start: 90)], notes: notes, keyframes: frames,
                           duration: 200)
        let slides = SlidePlan.build(title: "Hücre", transcript: t)
        #expect(slides.map(\.kind) == [.cover, .content, .content, .concepts])
        #expect(slides[0].title == "Hücre" && slides[0].body == "Dersin özeti")
        #expect(slides[1].title == "Hücre şeması" && slides[1].frameID == "f1" && slides[1].bullets == ["Birinci nokta"])
        #expect(slides[1].body == "İlk bölümün metni." && slides[1].timeLabel == "00:10")
        #expect(slides[2].title == "Zar" && slides[2].frameID == "f2" && slides[2].bullets == ["İkinci nokta"])
        #expect(slides[3].bullets == ["Zar: Hücre sınırı"])
    }

    @Test func slideCountIsCappedIncludingCoverAndConcepts() {
        let concepts = (0..<60).map { NoteConcept(name: "K\($0)", definition: "Tanım", time: Double($0)) }
        let notes = LectureNotes(summary: "", keyPoints: [], concepts: concepts, formulas: [], questions: [], examTips: [])
        let frames = (0..<200).map { Keyframe(id: "f\($0)", time: Double($0) * 10, image: "", caption: "Kare \($0)", text: "") }
        let t = transcript(paragraphs: (0..<200).map { para(Double($0) * 10, Double($0) * 10 + 10) }, notes: notes, keyframes: frames, duration: 2000)
        #expect(SlidePlan.build(title: "Ders", transcript: t).count <= SlidePlan.maxSlides)
    }

    @Test func slidesWithoutFramesFollowChapters() {
        let t = transcript(paragraphs: [para(0, 50, "Bir"), para(100, 150, "İki")],
                           chapters: [VideoChapter(title: "Giriş", start: 0), VideoChapter(title: "Zar", start: 100)], duration: 160)
        let slides = SlidePlan.build(title: "", transcript: t)
        #expect(slides.map(\.title) == ["Video dersi", "Giriş", "Zar"])
        #expect(slides.dropFirst().allSatisfy { $0.frameID == nil })
    }

    @Test func dubbingScenesRespectServerLimits() throws {
        let long = String(repeating: "Hücre zarı seçici geçirgendir. ", count: 70)   // ~2170 karakter
        let items = (0..<30).map { para(Double($0) * 20, Double($0) * 20 + 20, $0 % 7 == 0 ? long : "Kısa bir paragraf. Devamı da burada.") }
        let chapters = [VideoChapter(title: "A", start: 0), VideoChapter(title: "B", start: 300)]
        let script = try #require(DubbingPlan.script(title: "Dublaj", paragraphs: items, chapters: chapters))
        #expect(script.chapters.map(\.title) == ["A", "B"])
        for scene in script.chapters.flatMap(\.scenes) {
            #expect(!scene.turns.isEmpty && scene.turns.count <= 24)
            #expect(scene.turns.reduce(0) { $0 + $1.text.count } <= 1500)
            #expect(scene.turns.allSatisfy { $0.speaker == .a && $0.text.count <= 1500 })
        }
        #expect(script.sourceNotes.isEmpty)   // boş: otomatik doğrulama atlanır
        #expect(DubbingPlan.script(title: "x", paragraphs: [], chapters: []) == nil)
        // Bölüm aralığı seçilince yalnız o bölümün paragrafları.
        let ranged = try #require(DubbingPlan.script(title: "R", paragraphs: items, chapters: chapters, range: ClipRange(start: 300, end: 600)))
        #expect(ranged.chapters.map(\.title) == ["B"])
    }

    @Test func dubbingSourcePrefersTurkishTranslationThenTurkishOriginal() {
        let translation = TranscriptTranslation(language: "tr", paragraphs: [para(0, 10, "Çeviri")])
        let english = transcript(paragraphs: [para(0, 10, "Original")], language: "en", translation: translation)
        #expect(DubbingPlan.source(english)?.paragraphs.first?.text == "Çeviri" && DubbingPlan.source(english)?.translated == true)
        let turkish = transcript(paragraphs: [para(0, 10, "Özgün")], language: "tr")
        #expect(DubbingPlan.source(turkish)?.translated == false)
        #expect(DubbingPlan.source(transcript(paragraphs: [para(0, 10, "Original")], language: "en")) == nil)
        #expect(DubbingPlan.characters([para(0, 10, "abc  def"), para(20, 30, "gh")], range: ClipRange(start: 15, end: 40)) == 2)
        #expect(DubbingPlan.estimatedSeconds(characters: 1400) == 100)
    }
}

// MARK: - Sunucu yanıtlarını toleranslı çözme

struct StudyAPICodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func questionToleratesStringNumbersAndMissingFields() throws {
        let q = try decode(StudyQuestion.self, #"{"question":"Q?","choices":["a","b"],"answer":"1","explanation":null,"time":"42.5"}"#)
        #expect(q.answer == 1 && q.explanation == "" && q.time == 42.5)
        let bare = try decode(StudyQuestion.self, #"{"question":"Q?"}"#)
        #expect(bare.choices.isEmpty && bare.answer == -1 && bare.time == nil)
        #expect(StudyQuizRules.sanitize(bare) == nil)
    }

    @Test func hugeNumbersDoNotTrap() throws {
        let q = try decode(StudyQuestion.self, #"{"question":"Q?","choices":["a","b"],"answer":1e100}"#)
        #expect(q.answer == -1)
        #expect(try decode(StudyFeynmanResult.self, #"{"score":1e300}"#).score == 0)
    }

    @Test func quizResponseWithoutQuestionsIsEmpty() throws {
        #expect(try decode(StudyQuizResponse.self, "{}").questions.isEmpty)
        let r = try decode(StudyQuizResponse.self, #"{"questions":[{"question":"Q?","choices":["a","b","c","d"],"answer":2,"explanation":"E","time":null}]}"#)
        #expect(r.questions.count == 1 && r.questions[0].time == nil && r.questions[0].answer == 2)
    }

    @Test func explainPrereqAndCompareDecode() throws {
        let e = try decode(StudyExplanation.self, #"{"explanation":"Basit anlatım","example":"Örnek","keyTerms":["zar","ozmos"]}"#)
        #expect(e.keyTerms == ["zar", "ozmos"])
        #expect(try decode(StudyExplanation.self, "{}").explanation.isEmpty)
        let p = try decode(StudyPrereqResponse.self, #"{"prerequisites":[{"name":"Hücre","why":"Temel"}],"questions":[]}"#)
        #expect(p.prerequisites == [StudyPrerequisite(name: "Hücre", why: "Temel")] && p.questions.isEmpty)
        let c = try decode(StudyComparison.self, #"{"summary":"S","common":["x"],"onlyA":[],"onlyB":["y"],"better":[{"topic":"T","winner":"A","why":"W"}]}"#)
        #expect(c.better.first?.winner == "a" && c.onlyB == ["y"])
    }

    @Test func worksheetAndFeynmanDecode() throws {
        let w = try decode(StudyWorksheet.self, #"{"blanks":[{"sentence":"Zar _____","answer":"seçici"}],"questions":[],"matching":[{"term":"T","definition":"D"}]}"#)
        #expect(w.blanks.count == 1 && w.matching.count == 1 && !w.isEmpty)
        #expect(try decode(StudyWorksheet.self, "{}").isEmpty)
        let f = try decode(StudyFeynmanResult.self, #"{"score":150,"covered":["a"],"missing":["b"],"wrong":[],"feedback":"İyi"}"#)
        #expect(f.score == 100 && f.covered == ["a"] && f.missing == ["b"] && f.feedback == "İyi")
        #expect(try decode(StudyFeynmanResult.self, #"{"score":-5}"#).score == 0)
    }

    @Test func titlesAreClampedToServerLimit() throws {
        let long = String(repeating: "Başlık ", count: 100)
        #expect(studyServerTitle(long).count == 300)
        #expect(studyServerTitle("  Kısa  ") == "Kısa")
        #expect(StudyQuizRequest(title: long, text: "x", count: 3, style: "mcq").title.count == 300)
        #expect(StudyExplainRequest(title: long, text: "x", time: 1).title.count == 300)
        #expect(StudyPrereqRequest(title: long, summary: "x", concepts: []).title.count == 300)
        #expect(StudyWorksheetRequest(title: long, text: "x").title.count == 300)
        #expect(StudyFeynmanRequest(title: long, reference: "r", answer: "a").title.count == 300)
        #expect(StudyCompareSide(title: long, text: "x").title.count == 300)
    }

    @Test func requestsEncodeServerContract() throws {
        let data = try JSONEncoder().encode(StudyQuizRequest(title: "T", text: "[00:00] x", count: 3, style: "osym"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["count"] as? Int == 3 && object["style"] as? String == "osym" && object["text"] as? String == "[00:00] x")
        let compare = try JSONEncoder().encode(StudyCompareRequest(a: StudyCompareSide(title: "A", text: "a"), b: StudyCompareSide(title: "B", text: "b")))
        let compareObject = try #require(try JSONSerialization.jsonObject(with: compare) as? [String: Any])
        #expect((compareObject["a"] as? [String: String])?["title"] == "A" && (compareObject["b"] as? [String: String])?["text"] == "b")
    }
}

// MARK: - Kayıtlar (SwiftData)

@MainActor
struct StudyRecordTests {
    /// Bağlam, kapsayıcı yaşadığı sürece geçerlidir: testler kapsayıcıyı değişkende tutar.
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: VideoLesson.self, ReviewCard.self, MistakeEntry.self, TimedNote.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func addCardAttachesAndCapsClip() throws {
        let container = try makeContainer()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let lesson = VideoLesson(url: "https://youtu.be/EKGRs8q7HlA")
        lesson.title = "Hücre"
        context.insert(lesson)
        let draft = LessonCardDraft(front: "Zar…?", back: "Zar seçici geçirgendir.")
        #expect(LessonStudy.addCard(draft, lesson: lesson, context: context, clip: ClipRange(start: 30, end: 200)))
        let card = try #require(context.fetch(FetchDescriptor<ReviewCard>()).first)
        #expect(card.clipLessonID == lesson.id && card.clipStart == 30 && card.clipEnd == 120)
        // Aynı kart ikinci kez eklenmez.
        #expect(!LessonStudy.addCard(draft, lesson: lesson, context: context, clip: ClipRange(start: 30, end: 60)))
        // Çok kısa ya da geçersiz kesit bağlanmaz.
        let plain = LessonCardDraft(front: "Ön?", back: "Arka")
        #expect(LessonStudy.addCard(plain, lesson: lesson, context: context, clip: ClipRange(start: 10, end: 10.4)))
        let cards = try context.fetch(FetchDescriptor<ReviewCard>())
        #expect(cards.first { $0.front == "Ön?" }?.clipLessonID == nil)
    }

    @Test func noteCardsBecomeAudioCardsAtTheirParagraph() throws {
        let container = try makeContainer()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let lesson = VideoLesson(url: "https://youtu.be/EKGRs8q7HlA")
        lesson.title = "Hücre"
        let notes = LectureNotes(summary: "", keyPoints: [],
                                 concepts: [NoteConcept(name: "Difüzyon", definition: "Yoğundan seyrek yere geçiş", time: 40)],
                                 formulas: [NoteFormula(name: "Ohm yasası", expression: "V = I · R", meaning: "İlişki", time: 5)],
                                 questions: [], examTips: [])
        lesson.transcript = transcript(paragraphs: [para(0, 30, "Giriş"), para(30, 80, "Difüzyon anlatımı")], notes: notes)
        context.insert(lesson)
        #expect(LessonStudy.addNoteCards(notes, lesson: lesson, context: context) == 1)
        #expect(LessonStudy.addNoteCards(notes, lesson: lesson, context: context) == 0)
        #expect(LessonStudy.addNoteCards(notes, lesson: lesson, context: context, formulas: true, concepts: false, questions: false) == 1)
        let cards = try context.fetch(FetchDescriptor<ReviewCard>())
        let concept = try #require(cards.first { $0.front == "Difüzyon nedir?" })
        #expect(concept.clipLessonID == lesson.id && concept.clipStart == 30 && concept.clipEnd == 75)
        let formula = try #require(cards.first { $0.front == "Ohm yasası formülü nedir?" })
        #expect(formula.back == "V = I · R\nİlişki" && formula.clipStart == 0 && formula.clipEnd == 30)
    }

    @Test func wrongAnswerFeedsMistakeBookAndAudioCard() throws {
        let container = try makeContainer()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let lesson = VideoLesson(url: "https://youtu.be/EKGRs8q7HlA")
        lesson.title = "Hücre"
        lesson.courseID = UUID()
        context.insert(lesson)
        let q = question("Zarın görevi nedir?", answer: 1, time: 90)
        LessonStudy.recordWrong(q, myAnswer: "A şıkkı", lesson: lesson, fallbackTime: 10, clip: ClipRange(start: 80, end: 110), context: context)
        LessonStudy.recordWrong(q, myAnswer: "C şıkkı", lesson: lesson, fallbackTime: 10, clip: ClipRange(start: 80, end: 110), context: context)
        let mistakes = try context.fetch(FetchDescriptor<MistakeEntry>())
        #expect(mistakes.count == 1)
        let entry = try #require(mistakes.first)
        #expect(entry.source == "video" && entry.episodeID == lesson.id && entry.videoTime == 90 && entry.courseID == lesson.courseID)
        #expect(entry.correctAnswer == "B şıkkı" && entry.myAnswer == "A şıkkı")
        let cards = try context.fetch(FetchDescriptor<ReviewCard>())
        #expect(cards.count == 1 && cards[0].kind == .quiz && cards[0].clipStart == 80)
        // Zamansız soruda yedek an kullanılır.
        LessonStudy.recordWrong(question("Başka?", time: nil), myAnswer: "", lesson: lesson, fallbackTime: 12, clip: nil, context: context)
        #expect(try context.fetch(FetchDescriptor<MistakeEntry>()).first { $0.question == "Başka?" }?.videoTime == 12)
    }

    @Test func confusedSpotIsRecordedOnce() throws {
        let container = try makeContainer()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let lesson = VideoLesson(url: "https://youtu.be/EKGRs8q7HlA")
        lesson.title = "Hücre"
        context.insert(lesson)
        LessonStudy.recordConfused(time: 125, topic: "Zar", explanation: "Basit anlatım", example: "Elek gibi", lesson: lesson, context: context)
        LessonStudy.recordConfused(time: 125, topic: "Zar", explanation: "Basit anlatım", example: "Elek gibi", lesson: lesson, context: context)
        let entries = try context.fetch(FetchDescriptor<MistakeEntry>())
        #expect(entries.count == 1)
        #expect(entries[0].source == "confused" && entries[0].videoTime == 125 && entries[0].question.contains("02:05"))
        #expect(entries[0].why == "Elek gibi" && entries[0].episodeID == lesson.id)
    }
}

// MARK: - PDF

@MainActor
struct StudyPDFTests {
    @Test func worksheetPDFHasQuestionPagesAndAnswerKey() throws {
        let sheet = StudyWorksheet(
            blanks: (0..<12).map { WorksheetBlank(sentence: "Cümle \($0) _____ içerir.", answer: "cevap\($0)") },
            questions: (0..<8).map { WorksheetQuestion(question: "Soru \($0)?", answer: "Cevap \($0)") },
            matching: (0..<8).map { WorksheetPair(term: "Terim \($0)", definition: "Tanım \($0)") })
        let url = URL.temporaryDirectory.appending(path: "worksheet-test.pdf")
        try? FileManager.default.removeItem(at: url)
        #expect(WorksheetPDF.render(title: "Hücre", sheet: sheet, seed: 7, to: url))
        let pages = CGPDFDocument(url as CFURL)?.numberOfPages ?? 0
        #expect(pages >= 2)
        try? FileManager.default.removeItem(at: url)
    }

    @Test func slideFlowWritesOneLandscapePagePerSlide() throws {
        let url = URL.temporaryDirectory.appending(path: "slides-test.pdf")
        try? FileManager.default.removeItem(at: url)
        let flow = try #require(PDFFlow(url: url, pageSize: SlidePageView.pageSize, margin: 0))
        let specs = [SlideSpec(kind: .cover, title: "Hücre", timeLabel: nil, body: "Özet", bullets: [], frameID: nil),
                     SlideSpec(kind: .content, title: "Zar", timeLabel: "01:00", body: "Metin", bullets: ["Nokta"], frameID: nil),
                     SlideSpec(kind: .concepts, title: "Kavramlar", timeLabel: nil, body: "", bullets: ["Zar: tanım"], frameID: nil)]
        for (i, spec) in specs.enumerated() { flow.fullPage(SlidePageView(spec: spec, image: nil, index: i + 1, total: specs.count)) }
        flow.finish()
        let document = try #require(CGPDFDocument(url as CFURL))
        #expect(document.numberOfPages == 3)
        let box = document.page(at: 1)?.getBoxRect(.mediaBox)
        #expect(box?.width == 842 && box?.height == 595)
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Öğretmen sesi birleştirme (gerçek AVMutableComposition)

struct TeacherAudioTests {
    @Test func exportJoinsClipsWithGapsAndClampsToAssetDuration() async throws {
        let dir = URL.temporaryDirectory.appending(path: "teacher-audio-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // 12 sn'lik kaynak ses (m4a).
        var samples: [Int16] = []
        samples.reserveCapacity(24_000 * 12)
        for index in 0..<(24_000 * 12) {
            let phase: Double = 2 * Double.pi * 220 * Double(index) / 24_000
            samples.append(Int16(6000 * sin(phase)))
        }
        let wav = dir.appending(path: "scene.wav")
        try WAV.encode(PCMClip(samples: samples, sampleRate: 24_000)).write(to: wav)
        let source = dir.appending(path: "source.m4a")
        let turn = ScriptTurn(speaker: .a, text: "Deneme", style: "", sourcePage: nil)
        _ = try await AudioStitcher.stitch(scenes: [.init(url: wav, chapterIndex: 0, turns: [turn])], chapterTitles: ["A"],
                                           output: source, design: false)
        let sourceDuration = try await AVURLAsset(url: source).load(.duration).seconds

        let output = dir.appending(path: "summary.m4a")
        let clips = [ClipRange(start: 1, end: 3), ClipRange(start: 5, end: 5.2), ClipRange(start: 6, end: 8), ClipRange(start: 11, end: 40)]
        let result = try await TeacherAudio.export(source: source, clips: clips, gap: 0.35, to: output)
        // 0,2 sn'lik kesit atlanır; son kesit kaynağın gerçek süresine kırpılır.
        #expect(result.clips.count == 3)
        #expect(result.clips[0] == ClipRange(start: 1, end: 3) && result.clips[1] == ClipRange(start: 6, end: 8))
        #expect(abs(result.clips[2].end - sourceDuration) < 0.01 && result.clips[2].start == 11)
        let expected = result.clips.reduce(0) { $0 + $1.duration } + 0.35 * 2
        #expect(abs(result.duration - expected) < 0.3)
        let written = try await AVURLAsset(url: output).load(.duration).seconds
        #expect(abs(written - result.duration) < 0.01)
        // Zaman çizelgesi aynı kesitlerden kurulur.
        #expect(abs(TeacherSummaryPlan.totalDuration(result.clips) - expected) < 1e-9)
    }
}
