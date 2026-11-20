import XCTest
import ProxyKit
@testable import BilgiArena

@MainActor final class TestQuizVoice: QuizLiveVoice {
    var route = "Sınama sesi"
    var level = 0.0
    var replies: [String]
    var spoken: [QuizSpeechSegment] = []
    var stopped = 0
    var failNextSpeak = false
    var hearingPhase = QuizHearingPhase.recording
    var transcribeDelay: Duration?
    var delay: Duration
    init(_ replies: [String], delay: Duration = .milliseconds(20)) { self.replies = replies; self.delay = delay }
    func prepare() async throws {}
    func speak(_ segments: [QuizSpeechSegment]) async throws {
        if failNextSpeak { failNextSpeak = false; throw QuizError("Canlı API ses üretemedi.") }
        spoken += segments; try await Task.sleep(for:delay)
    }
    func hear(language: String) async throws -> String {
        hearingPhase = .recording; try await Task.sleep(for:delay)
        if let transcribeDelay { hearingPhase = .transcribing; try await Task.sleep(for:transcribeDelay) }
        return replies.isEmpty ? "bilmiyorum" : replies.removeFirst()
    }
    func finishHearing() {}
    func stop() { stopped += 1 }
}
final class LiveQuizTests: XCTestCase {
    func testNarrationReadsChoicesAndStimuliWithoutRevealingSolution() {
        let q = Seed.questions[0]
        let narration = QuizNarration.question(q,number:1).map(\.text).joined(separator:" ")
        XCTAssertTrue(narration.contains(q.text)); XCTAssertTrue(narration.contains("A şıkkı"))
        XCTAssertFalse(narration.contains(q.explanation)); XCTAssertFalse(narration.contains("Doğru cevap"))
        for q in ActivityQuestionSeeds.questions {
            let segments = QuizNarration.question(q,number:1)
            XCTAssertTrue(segments.allSatisfy { !$0.text.isEmpty && $0.text.count <= 1000 })
            if let text = q.activity?.transcript { XCTAssertTrue(segments.contains { $0.text.contains(text) && $0.language == q.activity?.language }) }
            if q.activity?.isInteractive == true { XCTAssertFalse(segments.map(\.text).joined().contains("Doğru sıralama")) }
            if q.activity?.kind == .pronunciation {
                let feedback = QuizNarration.feedback(q,correct:false,last:false)
                XCTAssertTrue(feedback.contains { $0.language == q.activity?.language && $0.text.contains(q.activity?.transcript ?? "") })
                XCTAssertTrue(feedback.first?.text.contains("Anlaşılan kelimeler") == true)
            }
        }
    }
    func testEndpointWaitsForSpeechThenSilenceAndBoundsNoSpeech() {
        var detector = VoiceEndpointDetector()
        for _ in 0..<20 { XCTAssertFalse(detector.sample(db:-70,seconds:0.1)) }
        XCTAssertFalse(detector.heardSpeech)
        for _ in 0..<5 { XCTAssertFalse(detector.sample(db:-20,seconds:0.1)) }
        XCTAssertTrue(detector.heardSpeech)
        for _ in 0..<10 { XCTAssertFalse(detector.sample(db:-70,seconds:0.1)) }
        XCTAssertTrue(detector.sample(db:-70,seconds:0.3))
        var silence = VoiceEndpointDetector(); var ended = false
        for _ in 0..<62 { ended = silence.sample(db:-80,seconds:0.1) || ended }
        XCTAssertTrue(ended); XCTAssertFalse(silence.heardSpeech)
        var quiet = VoiceEndpointDetector()
        for _ in 0..<4 { XCTAssertFalse(quiet.sample(db:-44,seconds:0.1)) }
        XCTAssertTrue(quiet.heardSpeech)
        XCTAssertTrue(quiet.sample(db:-70,seconds:1.3))
    }
    func testRealtimeProtocolsParseTranscriptAudioCompletionAndQuota() throws {
        let setup = QuizLiveProtocol.setup(.openAI,model:"gpt-realtime-2.1-mini")
        let session = setup["session"] as! [String:Any], audio = session["audio"] as! [String:Any], input = audio["input"] as! [String:Any]
        XCTAssertEqual((input["turn_detection"] as? [String:Any])?["create_response"] as? Bool,false)
        XCTAssertEqual(QuizLiveProtocol.event(["type":"session.updated"],engine:.openAI),[.ready])
        XCTAssertEqual(QuizLiveProtocol.event(["type":"conversation.item.input_audio_transcription.completed","transcript":"Mars"],engine:.openAI),[.transcript("Mars")])
        let pcm = Data(repeating:0,count:100)
        XCTAssertEqual(QuizLiveProtocol.event(["type":"response.output_audio.delta","delta":pcm.base64EncodedString()],engine:.openAI),[.audio(pcm)])
        XCTAssertEqual(QuizLiveProtocol.event(["serverContent":["inputTranscription":["text":"B şıkkı"],"turnComplete":true]],engine:.gemini),[.transcript("B şıkkı"),.done])
        if case .failed(let text) = QuizLiveProtocol.event(["error":["code":"insufficient_quota","message":"private"]],engine:.openAI).first { XCTAssertFalse(text.contains("private")) } else { XCTFail() }
        if case .failed(let text) = QuizLiveProtocol.event(["error":["code":"credit_balance_exhausted"]],engine:.openAI).first { XCTAssertTrue(text.contains("kota/kredisi")) } else { XCTFail() }
        XCTAssertEqual(LiveQuizController.command("Tekrar oku"),.repeatQuestion)
        XCTAssertNil(LiveQuizController.command("A değil B"))
    }
    @MainActor func makeGame(_ voice: TestQuizVoice) throws -> (GameStore,UserDefaults,URL,String) {
        let name = "LiveQuizTest-"+UUID().uuidString, d = UserDefaults(suiteName:name)!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let database = try QuestionPoolDatabase(url:folder.appendingPathComponent("pool.sqlite"))
        let controller = LiveQuizController(); controller.factory = { _,_ in voice }; controller.reviewDelay = .milliseconds(30)
        let pool = DailyQuestionPool(defaults:d,database:database)
        return (GameStore(defaults:d,startTimer:false,pool:pool,liveQuiz:controller),d,folder,name)
    }
    @MainActor func testHandsFreeLoopRecordsOnlyResolvedAnswerAndFinishesOneResult() async throws {
        let q = Question(text:"Hangi gezegen kızıl gezegendir?",options:["Venüs","Mars","Dünya","Jüpiter"],answer:1,explanation:"Mars yüzeyindeki demir oksit nedeniyle kızıl görünür.",category:.science,difficulty:.easy)
        let voice = TestQuizVoice(["B"])
        let (game,d,folder,name) = try makeGame(voice)
        defer { game.leave(); d.removePersistentDomain(forName:name); try? FileManager.default.removeItem(at:folder) }
        game.start([q],source:"Live",mode:.training,live:true)
        for _ in 0..<100 { if game.round?.finished == true { break }; try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertEqual(game.round?.answers.count,1); XCTAssertTrue(game.round?.answers[0].correct == true)
        XCTAssertEqual(game.round?.answers[0].response?.spokenText,"B"); XCTAssertEqual(game.results.count,1)
        XCTAssertTrue(voice.spoken.contains { $0.text.contains("Doğru cevap") })
    }
    @MainActor func testHearingSeparatesRecordingAndWhisperDecodingBeforeCommitting() async throws {
        let voice = TestQuizVoice(["A"],delay:.milliseconds(250)); voice.transcribeDelay = .milliseconds(400)
        let (game,d,folder,name) = try makeGame(voice)
        defer { game.leave(); d.removePersistentDomain(forName:name); try? FileManager.default.removeItem(at:folder) }
        game.start([Seed.questions[0]],source:"Live",mode:.training,live:true)
        for _ in 0..<70 { if game.liveQuiz.phase == .listening { break }; try await Task.sleep(for:.milliseconds(10)) }
        XCTAssertEqual(game.liveQuiz.phase,.listening); XCTAssertEqual(game.round?.answers.count,0)
        for _ in 0..<70 { if game.liveQuiz.phase == .transcribing { break }; try await Task.sleep(for:.milliseconds(10)) }
        XCTAssertEqual(game.liveQuiz.phase,.transcribing); XCTAssertEqual(game.round?.answers.count,0)
        for _ in 0..<150 { if game.round?.finished == true { break }; try await Task.sleep(for:.milliseconds(10)) }
        XCTAssertTrue(game.round?.finished == true); XCTAssertEqual(game.round?.answers.count,1)
    }
    @MainActor func testLiveReadFailureFallsBackVisiblyWithoutLosingQuestionOrDoubleScoring() async throws {
        let previous = UserDefaults.standard.object(forKey:"quizLiveEngine")
        UserDefaults.standard.set(QuizLiveEngine.openAI.rawValue,forKey:"quizLiveEngine")
        defer { if let previous { UserDefaults.standard.set(previous,forKey:"quizLiveEngine") } else { UserDefaults.standard.removeObject(forKey:"quizLiveEngine") } }
        let failed = TestQuizVoice([]); failed.failNextSpeak = true
        let chained = TestQuizVoice(["B"])
        let (game,d,folder,name) = try makeGame(failed)
        defer { game.leave(); d.removePersistentDomain(forName:name); try? FileManager.default.removeItem(at:folder) }
        var calls = 0
        game.liveQuiz.factory = { _,_ in calls += 1; return calls == 1 ? failed : chained }
        let q = Question(text:"Hangi gezegen kızıl gezegendir?",options:["Venüs","Mars","Dünya","Jüpiter"],answer:1,explanation:"Mars kızıl gezegendir.",category:.science,difficulty:.easy)
        game.start([q],source:"Live",mode:.training,live:true)
        for _ in 0..<100 { if game.round?.finished == true { break }; try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertTrue(game.liveQuiz.notice.contains("sıralı sesli")); XCTAssertTrue(failed.stopped > 0)
        XCTAssertTrue(game.round?.finished == true); XCTAssertEqual(game.round?.answers.count,1)
        XCTAssertTrue(game.round?.answers.first?.correct == true); XCTAssertEqual(game.results.count,1)
    }
    @MainActor func testUnresolvedAnswerAndPauseNeverCommitAndResumeRetainsQuestion() async throws {
        let voice = TestQuizVoice(["A veya B"])
        let (game,d,folder,name) = try makeGame(voice)
        defer { game.leave(); d.removePersistentDomain(forName:name); try? FileManager.default.removeItem(at:folder) }
        game.start([Seed.questions[0]],source:"Live",mode:.training,live:true)
        for _ in 0..<60 { if game.liveQuiz.phase == .failed { break }; try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertEqual(game.liveQuiz.phase,.failed); XCTAssertEqual(game.round?.answers.count,0)
        let id = game.round!.id
        game.pause(); XCTAssertEqual(game.liveQuiz.phase,.paused)
        game.setActive(false); game.resume(); XCTAssertTrue(game.round?.paused == true)
        XCTAssertEqual(game.round?.id,id); XCTAssertEqual(game.round?.answers.count,0)
    }
    @MainActor func testPauseDuringReviewCancelsDelayedSubmissionAndSavedLiveFlagIsOptional() async throws {
        let voice = TestQuizVoice(["A"])
        let (game,d,folder,name) = try makeGame(voice)
        defer { game.leave(); d.removePersistentDomain(forName:name); try? FileManager.default.removeItem(at:folder) }
        game.liveQuiz.reviewDelay = .seconds(1)
        game.start([Seed.questions[0]],source:"Live",mode:.training,live:true)
        for _ in 0..<100 { if game.liveQuiz.phase == .reviewing { break }; try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertEqual(game.liveQuiz.phase,.reviewing); game.pause()
        try await Task.sleep(for:.milliseconds(1100)); XCTAssertEqual(game.round?.answers.count,0)
        let round = try JSONDecoder().decode(Round.self,from:JSONEncoder().encode(game.round!)); XCTAssertEqual(round.liveVoice,true)
        var json = try JSONSerialization.jsonObject(with:JSONEncoder().encode(round)) as! [String:Any]; json.removeValue(forKey:"liveVoice")
        XCTAssertNil(try JSONDecoder().decode(Round.self,from:JSONSerialization.data(withJSONObject:json)).liveVoice)
    }
}
