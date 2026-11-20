import XCTest
import SQLite3
@testable import BilgiArena

final class QuestionActivityTests: XCTestCase {
    func testAllSeedsRoundTripAndContainThreeActualInteractionKinds() throws {
        let qs = ActivityQuestionSeeds.questions
        XCTAssertEqual(qs.count,12); XCTAssertTrue(qs.allSatisfy(\.isWellFormed))
        XCTAssertEqual(Set(qs.compactMap { $0.activity?.kind }),Set(ActivityKind.allCases))
        let data = try JSONEncoder().encode(["questions":qs])
        XCTAssertEqual(try Question.decode(String(decoding:data,as:UTF8.self),expectedCount:12),qs)
        for kind in ActivityKind.allCases { XCTAssertEqual(qs.filter { $0.activity?.kind == kind }.count,3) }
    }
    func testMalformedActivityIsRejectedAndNotDowngradedToText() throws {
        var q = ActivityQuestionSeeds.questions[1]
        q.activity?.solution = [0,0,2,3]; XCTAssertFalse(q.isWellFormed)
        let content = String(decoding:try JSONEncoder().encode(["questions":[q]]),as:UTF8.self)
        XCTAssertThrowsError(try Question.decode(content,expectedCount:1))
        XCTAssertTrue(GeneratedQuestionParser.parse(content,topic:.exam,difficulty:.easy,excluding:[],limit:1).questions.isEmpty)
        var listening = ActivityQuestionSeeds.questions[0]
        listening.activity?.language = "xx-XX"; XCTAssertFalse(listening.isWellFormed)
        listening = ActivityQuestionSeeds.questions[0]; listening.visual = VisualQuestionSeeds.questions[0].visual; XCTAssertFalse(listening.isWellFormed)
        listening = ActivityQuestionSeeds.questions[0]; listening.activity = nil; XCTAssertFalse(listening.isWellFormed)
        var match = ActivityQuestionSeeds.questions[2].activity!; match.right = ["A","A","B","C"]; XCTAssertFalse(match.isValid)
    }
    func testParserBuildsCompatibilityChoicesForOrderingAndMatching() throws {
        for q in ActivityQuestionSeeds.questions.prefix(3) {
            var row = try JSONSerialization.jsonObject(with:JSONEncoder().encode(q)) as! [String:Any]
            if q.activity!.isInteractive { for key in ["options","answer","optionExplanations"] { row.removeValue(forKey:key) } }
            else { row["optionExplanations"] = ["Blue mavi anlamındadır.","Red kırmızı demektir.","Yellow sarı demektir.","Green yeşil demektir."] }
            let content = String(decoding:try JSONSerialization.data(withJSONObject:["questions":[row]]),as:UTF8.self)
            let result = GeneratedQuestionParser.parse(content,topic:q.category,difficulty:q.difficulty,excluding:[],limit:1)
            XCTAssertEqual(result.questions.count,1)
            XCTAssertEqual(result.questions.first?.activity,q.activity)
        }
    }
    func testShufflingRetainsSemanticSolutionAndSubmissionCannotBypassInteraction() {
        for q in ActivityQuestionSeeds.questions.filter({ $0.activity!.isInteractive }) {
            let shuffled = q.rearranged(), activity = shuffled.activity!
            XCTAssertTrue(shuffled.isWellFormed)
            if activity.kind == .ordering { XCTAssertEqual(shuffled.correctAnswerText,q.correctAnswerText) }
            else { XCTAssertEqual(Set(shuffled.correctAnswerText.components(separatedBy:" · ")),Set(q.correctAnswerText.components(separatedBy:" · "))) }
            var r = Round(questions:[shuffled],source:"test")
            r.answer(shuffled.answer); XCTAssertFalse(r.revealed)
            r.answer(shuffled.answer,response:.init(indices:[0,0,1,2])); XCTAssertFalse(r.revealed)
            r.answer(shuffled.answer,response:.init(indices:activity.solution!)); r.answer(nil)
            XCTAssertEqual(r.answers.count,1); XCTAssertTrue(r.answers[0].correct); XCTAssertEqual(r.answers[0].response?.indices,activity.solution)
        }
    }
    func testListeningClocksWaitForCompletionAndReadyStateSurvivesSave() throws {
        let q = ActivityQuestionSeeds.questions[0]
        var r = Round(questions:[q],source:"test",settings:.init(minutes:2))
        XCTAssertTrue(r.awaitsListening)
        for _ in 0..<60 { r.tick() }
        XCTAssertEqual(r.remaining,30); XCTAssertEqual(r.totalRemaining,120)
        r.answer(0); XCTAssertFalse(r.revealed)
        r.audioReadyQuestionID = q.id; r.tick()
        XCTAssertEqual(r.remaining,29); XCTAssertEqual(r.totalRemaining,119)
        let restored = try JSONDecoder().decode(Round.self,from:JSONEncoder().encode(r))
        XCTAssertFalse(restored.awaitsListening)
        r.answer(0); XCTAssertTrue(r.answers[0].correct)
        var skipped = Round(questions:[q],source:"test"); skipped.skip(); XCTAssertTrue(skipped.revealed)
    }
    func testLegacyRecordsDecodeWithAbsentActivityAndListeningState() throws {
        var row = try JSONSerialization.jsonObject(with:JSONEncoder().encode(Round(questions:[Seed.questions[0]],source:"old"))) as! [String:Any]
        for key in ["activityDraft","audioReadyQuestionID"] { row.removeValue(forKey:key) }
        let old = try JSONDecoder().decode(Round.self,from:JSONSerialization.data(withJSONObject:row))
        XCTAssertFalse(old.awaitsListening); XCTAssertNil(old.activityDraft); XCTAssertNil(old.current.activity)
        let record = AnswerRecord(question:Seed.questions[0],chosen:Seed.questions[0].answer,points:100)
        let restored = try JSONDecoder().decode(AnswerRecord.self,from:JSONEncoder().encode(record))
        XCTAssertNil(restored.response); XCTAssertTrue(restored.correct)
    }
    @MainActor func testDraftAndActualWrongResponseSurviveStoreRelaunch() {
        let name = "activity-store-"+UUID().uuidString
        let actualDefaults = UserDefaults(suiteName:name)!
        defer { actualDefaults.removePersistentDomain(forName:name) }
        let game = GameStore(defaults:actualDefaults,startTimer:false); game.soundEnabled = false; game.voiceEnabled = false
        let q = ActivityQuestionSeeds.questions[1]
        game.start([q],source:"test",mode:.training)
        game.saveActivityDraft(.init(indices:[2,0]))
        let recovered = GameStore(defaults:actualDefaults,startTimer:false)
        XCTAssertEqual(recovered.round?.activityDraft?.indices,[2,0]); recovered.resume()
        recovered.submitActivity(.init(indices:[0,1,2,3])); recovered.submitActivity(.init(indices:q.activity!.solution!))
        XCTAssertEqual(recovered.history.count,1); XCTAssertFalse(recovered.history[0].correct)
        XCTAssertEqual(recovered.history[0].response?.indices,[0,1,2,3])
        recovered.leave(); game.leave()
    }
    func testOldVisualSchemaMigratesAndAllFormatFiltersStayDisjoint() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let url = folder.appendingPathComponent("pool.sqlite")
        var handle: OpaquePointer?
        sqlite3_open(url.path,&handle)
        XCTAssertEqual(sqlite3_exec(handle,"CREATE TABLE questions(fingerprint TEXT PRIMARY KEY,payload BLOB NOT NULL,category TEXT NOT NULL,difficulty TEXT NOT NULL,day TEXT,created REAL NOT NULL,lastPlayed REAL,hidden INTEGER NOT NULL DEFAULT 0,visualKind TEXT)",nil,nil,nil),SQLITE_OK)
        sqlite3_close(handle)
        let database = try QuestionPoolDatabase(url:url)
        let qs = [Seed.questions[0],VisualQuestionSeeds.questions[0]] + ActivityQuestionSeeds.questions
        try await database.insert(qs)
        let snapshot = try await database.snapshot(day:"test")
        XCTAssertEqual(snapshot.total,14); XCTAssertEqual(snapshot.activityCounts.values.reduce(0,+),12)
        for format in QuestionFormat.allCases {
            let expected = Set(qs.filter(format.accepts).map(\.id))
            let sample = try await database.sample(topic:.mixed,difficulty:nil,limit:50,format:format)
            let search = try await database.search(text:"",topic:.mixed,difficulty:nil,format:format)
            XCTAssertEqual(Set(sample.map(\.id)),expected); XCTAssertEqual(Set(search.map(\.id)),expected)
        }
    }
    @MainActor func testDailyProductionCyclesThroughVisualListeningOrderingMatchingAndMixed() {
        XCTAssertEqual((0..<10).map(DailyQuestionPool.formatForBatch),[.visual,.listening,.ordering,.matching,.pronunciation,.mixed,.visual,.listening,.ordering,.matching])
    }
}

extension GenerationRecoveryTests {
    func testEveryNewFormatRejectsOtherKindsThenPersistsMatchingKind() async throws {
        for (format,index) in [(QuestionFormat.listening,0),(.ordering,1),(.matching,2)] {
            var q = ActivityQuestionSeeds.questions[index]
            q.optionExplanations = ["Bu seçenek doğru yanıtı verir.","Bu seçenek farklı bir yanıt verir.","Bu seçenek farklı bir yanıt verir.","Bu seçenek farklı bir yanıt verir."]
            let transport = ScriptedQuestionTransport([try json([question(1)]),try json([q])])
            let qs = try await AIService(gateway:gateway(transport)).questions(topic:q.category,detail:"Genel",difficulty:q.difficulty,count:1,models:["model-a"],excluding:[],format:format,progress:{ _,_,_ in })
            XCTAssertEqual(qs.count,1); XCTAssertTrue(format.accepts(qs[0]))
            let calls = await transport.count(); XCTAssertEqual(calls,2)
        }
    }
}
