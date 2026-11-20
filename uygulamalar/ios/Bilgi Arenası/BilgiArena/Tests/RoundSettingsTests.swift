import XCTest
import AVFoundation
@testable import BilgiArena

final class RoundSettingsTests: XCTestCase {
    private var questions: [Question] { Array(Seed.questions.filter { $0.visual == nil }.prefix(9)) }
    func testMinuteBudgetExpiresOnceWithoutCountingUnseenQuestions() {
        var r = Round(questions:questions,source:"test",mode:.timed,settings:.init(minutes:1))
        XCTAssertEqual(r.clockText,"01:00"); XCTAssertFalse(r.hasQuestionClock)
        r.answer(r.current.answer); r.next()
        for _ in 0..<60 { r.tick() }
        XCTAssertTrue(r.finished); XCTAssertEqual(r.answers.count,2); XCTAssertNil(r.answers.last?.chosen)
        r.tick(); r.next(); r.answer(0); XCTAssertEqual(r.answers.count,2)
    }
    func testBothClocksPauseOnAnswerAndPauseAndTrainingIgnoresLimits() {
        var r = Round(questions:questions,source:"test",settings:.init(minutes:2,seconds:30))
        r.tick(); XCTAssertEqual(r.remaining,29); XCTAssertEqual(r.totalRemaining,119)
        r.paused = true; r.tick(); XCTAssertEqual(r.totalRemaining,119)
        r.paused = false; r.answer(0); r.tick(); XCTAssertEqual(r.totalRemaining,119)
        r.next(); XCTAssertEqual(r.remaining,30); XCTAssertEqual(r.totalRemaining,119)
        let training = Round(questions:questions,source:"test",mode:.training,settings:.init(minutes:1,seconds:5))
        XCTAssertNil(training.totalRemaining); XCTAssertEqual(training.remaining,0)
    }
    func testStageTransitionsAndVisualReadingFloor() {
        var r = Round(questions:questions,source:"test",mode:.stages)
        for index in 0..<9 {
            XCTAssertEqual(r.stageIndex,index/3); XCTAssertEqual(r.remaining,[20,15,10][index/3])
            r.answer(r.current.answer); r.next()
        }
        XCTAssertTrue(r.finished)
        let visual = Round(questions:VisualQuestionSeeds.questions,source:"test",mode:.stages,settings:.init(seconds:5))
        XCTAssertEqual(visual.remaining,25)
    }
    func testNewRoundFieldsAreOptionalForLegacySavedGame() throws {
        let r = Round(questions:questions,source:"legacy")
        var data = try JSONSerialization.jsonObject(with:JSONEncoder().encode(r)) as! [String:Any]
        data.removeValue(forKey:"settings"); data.removeValue(forKey:"totalRemaining")
        let old = try JSONDecoder().decode(Round.self,from:JSONSerialization.data(withJSONObject:data))
        XCTAssertEqual(old.current,r.current); XCTAssertEqual(old.remaining,10); XCTAssertNil(old.totalRemaining)
        let saved = Round(questions:questions,source:"clock",mode:.timed,settings:.init(minutes:3))
        let restored = try JSONDecoder().decode(Round.self,from:JSONEncoder().encode(saved))
        XCTAssertEqual(restored.totalRemaining,180); XCTAssertEqual(restored.effectiveMode,.timed)
    }
    func testSettingsLimitsAndTimeJokerApplyOnlyOnce() {
        XCTAssertEqual(RoundSettings(minutes:999,seconds:999).normalized,.init(minutes:30,seconds:120))
        XCTAssertEqual(RoundSettings(minutes:-2,seconds:-5).normalized,.init(minutes:0,seconds:5))
        var r = Round(questions:questions,source:"test",mode:.timed,settings:.init(minutes:1))
        r.moreTime(); r.moreTime(); XCTAssertEqual(r.totalRemaining,75)
    }
    @MainActor func testStoreBreaksAndExpiryPersistOneResultAndSettings() throws {
        let name = "RoundSettings-"+UUID().uuidString
        let defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let store = GameStore(defaults:defaults,startTimer:false)
        store.soundEnabled = false; store.voiceEnabled = false
        store.roundSettings = .init(minutes:2,seconds:20); store.persistSelection()
        let restored = GameStore(defaults:defaults,startTimer:false)
        XCTAssertEqual(restored.roundSettings,store.roundSettings); XCTAssertFalse(restored.soundEnabled)
        store.start(questions,source:"test",mode:.stages)
        for _ in 0..<3 { store.answer(store.round!.current.answer); store.next() }
        XCTAssertTrue(store.card); XCTAssertEqual(store.round?.stageTitle,"Odak")
        store.card = false; store.leave()
        store.start(questions,source:"test",mode:.timed); store.round?.totalRemaining = 1
        store.tick(now:Date().addingTimeInterval(2)); store.tick(now:Date().addingTimeInterval(3))
        XCTAssertTrue(store.round!.finished); XCTAssertEqual(store.results.count,1); XCTAssertEqual(store.results[0].total,1)
        store.leave()
    }
    @MainActor func testStoppingPendingAudioPreventsDelayedSpeechAndEffects() async throws {
        let audio = GameAudio()
        audio.play(.stage,effects:true,speech:"Bu duyuru iptal edildi.")
        audio.stop()
        try await Task.sleep(for:.milliseconds(300))
        XCTAssertFalse(audio.isSpeaking); XCTAssertFalse(audio.lastEffectStarted)
    }
    @MainActor func testEveryEffectIsAPlayableLocalWave() throws {
        for event in GameAudio.Event.allCases {
            let data = GameAudio.wave(event)
            XCTAssertEqual(String(data:Data(data.prefix(4)),encoding:.utf8),"RIFF")
            let player = try AVAudioPlayer(data:data)
            XCTAssertGreaterThan(player.duration,0.03); XCTAssertLessThan(player.duration,1)
        }
    }
}
