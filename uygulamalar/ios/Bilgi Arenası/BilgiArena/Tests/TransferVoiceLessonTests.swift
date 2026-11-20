import XCTest
@testable import BilgiArena

final class TransferVoiceLessonTests: XCTestCase {
    func testSpokenAnswersRequireUnambiguousChoiceAndPreserveRealText() {
        let q = Question(text:"Hangi gezegen kızıl gezegendir?",options:["Venüs","Mars","Dünya","Jüpiter"],answer:1,explanation:"Mars kızıl gezegen olarak bilinir.",category:.science,difficulty:.easy)
        XCTAssertEqual(VoiceAnswerResolver.resolve("Benim cevabım Mars.",for:q),.choice(1))
        XCTAssertEqual(VoiceAnswerResolver.resolve("B şıkkı",for:q),.choice(1))
        XCTAssertNil(VoiceAnswerResolver.resolve("A veya B",for:q))
        XCTAssertNil(VoiceAnswerResolver.resolve("bilmiyorum",for:q))
        var r = Round(questions:[q],source:"test")
        r.answer(1,response:.init(indices:[],spokenText:"Benim cevabım Mars."))
        XCTAssertTrue(r.answers[0].correct); XCTAssertEqual(r.answers[0].response?.spokenText,"Benim cevabım Mars.")
    }
    func testVoiceOrderingIsPermutationAndPronunciationIsRecognitionOnly() {
        let ordering = ActivityQuestionSeeds.questions[1]
        XCTAssertEqual(VoiceAnswerResolver.resolve("iki dört bir üç",for:ordering),.activity(.init(indices:[1,3,0,2],spokenText:"iki dört bir üç")))
        XCTAssertNil(VoiceAnswerResolver.resolve("iki iki üç dört",for:ordering))
        let q = ActivityQuestionSeeds.questions.first { $0.activity?.kind == .pronunciation }!
        XCTAssertTrue(q.isWellFormed)
        XCTAssertTrue(q.activity!.isCorrect(.init(indices:[],spokenText:"Good morning.")))
        XCTAssertFalse(q.activity!.isCorrect(.init(indices:[],spokenText:"Good evening")))
        var r = Round(questions:[q],source:"test",mode:.training)
        r.answer(0); XCTAssertFalse(r.revealed)
        r.answer(0,response:.init(indices:[],spokenText:"Good morning.")); XCTAssertTrue(r.answers[0].correct)
    }
    func testCrossModelDuplicatesShareIdentityAndReorderedStimuliStaySame() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let database = try QuestionPoolDatabase(url:folder.appendingPathComponent("pool.sqlite"))
        var a = ActivityQuestionSeeds.questions[1], b = a.rearranged()
        a.modelID = "gpt"; b.modelID = "claude"
        XCTAssertEqual(a.poolKey,b.poolKey)
        let first = try await database.insert([a]); let second = try await database.insert([b])
        XCTAssertEqual(first,1); XCTAssertEqual(second,0)
        var different = ActivityQuestionSeeds.questions[1]
        different.activity?.items = ["300","100","400","200"]
        different = different.replacingActivity(different.activity!)
        XCTAssertNotEqual(a.poolKey,different.poolKey)
        let third = try await database.insert([different]); XCTAssertEqual(third,1)
    }
    func testNewNearCopiesAreRejectedAcrossModels() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let database = try QuestionPoolDatabase(url:folder.appendingPathComponent("pool.sqlite"))
        let a = Question(text:"Dünya üzerindeki canlı hücrelerde genetik bilgiyi taşıyan temel molekül hangisidir?",options:["DNA","Su","Yağ","Glikoz"],answer:0,explanation:"DNA, kalıtsal bilginin taşınmasında görev yapar.",category:.science,difficulty:.easy,modelID:"gpt")
        var b = Question(text:"Dünya üzerindeki canlı hücrelerde genetik bilgiyi taşıyan temel molekül hangisidir acaba?",options:a.options,answer:0,explanation:a.explanation,category:.science,difficulty:.easy,modelID:"claude")
        b = b.rearranged()
        let count = try await database.insert([a,b]); XCTAssertEqual(count,1)
        let more = try await database.novelCandidates([b]); XCTAssertTrue(more.isEmpty)
    }
    func testThousandQuestionImportExportRetryAndUndoPreserveExistingRecord() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let database = try QuestionPoolDatabase(url:folder.appendingPathComponent("pool.sqlite"))
        try await database.insert([Seed.questions[0]])
        let qs = (1...1000).map { n in Question(text:"\(n) sayısının 1 fazlası kaçtır?",options:["\(n+1)","\(n+2)","\(n+3)","\(n+4)"],answer:0,explanation:"\(n) sayısına 1 eklenince \(n+1) bulunur.",category:.exam,difficulty:.easy,study:.init(exam:"TYT",lesson:"Matematik")) }
        let input = folder.appendingPathComponent("1000.json")
        try QuestionTransfer.exportQuestions(qs,to:input)
        let preview = try await QuestionTransfer.previewFiles([input])
        XCTAssertEqual(preview.questions.count,1000); XCTAssertEqual(preview.invalid,0)
        let first = try await QuestionTransfer.store(preview,database:database)
        XCTAssertEqual(first.inserted,1000); XCTAssertEqual(first.duplicates,0)
        let second = try await QuestionTransfer.importFile(input,database:database)
        XCTAssertEqual(second.inserted,0); XCTAssertEqual(second.duplicates,1000)
        let output = folder.appendingPathComponent("whole-pool.json")
        let exported = try await database.exportFile(to:output)
        XCTAssertEqual(exported,1001)
        XCTAssertEqual(try QuestionTransfer.decode(Data(contentsOf:output)).questions.count,1001)
        let filtered = folder.appendingPathComponent("filtered.json")
        let filteredCount = try await database.exportFile(text:"1000 sayısının",to:filtered)
        XCTAssertEqual(filteredCount,1)
        let onlyMath = folder.appendingPathComponent("math.json")
        let count = try await database.exportFile(study:.init(exam:"TYT",lesson:"Matematik"),to:onlyMath)
        XCTAssertEqual(count,1000)
        let last = try await database.lastImport(); XCTAssertEqual(last?.count,1000)
        let removed = try await database.undoImport(first.importBatchID!); XCTAssertEqual(removed,1000)
        let snapshot = try await database.snapshot(day:"test"); XCTAssertEqual(snapshot.total,1)
        let remaining = try await database.search(text:"",topic:.mixed,difficulty:nil); XCTAssertEqual(remaining.map(\.id),[Seed.questions[0].id])
    }
    func testImportReportsInvalidRowsAndReadsBareExternalActivities() throws {
        let q = ActivityQuestionSeeds.questions[1]
        var activity = try JSONSerialization.jsonObject(with:JSONEncoder().encode(q)) as! [String:Any]
        activity.removeValue(forKey:"options"); activity.removeValue(forKey:"answer"); activity.removeValue(forKey:"optionExplanations")
        let data = try JSONSerialization.data(withJSONObject:["schemaVersion":1,"questions":[activity,["text":"invalid"]]])
        let parsed = try QuestionTransfer.decode(data)
        XCTAssertEqual(parsed.questions.count,1); XCTAssertEqual(parsed.invalid,1); XCTAssertEqual(parsed.questions[0].activity,q.activity)
        XCTAssertThrowsError(try QuestionTransfer.decode(Data("{\"schemaVersion\":999,\"questions\":[]}".utf8)))
    }
    func testLessonLabelsPersistShuffleAndFilterWithoutSubtopics() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let database = try QuestionPoolDatabase(url:folder.appendingPathComponent("pool.sqlite"))
        var a = Seed.questions[0], b = Seed.questions[1]
        a = Question(text:a.text,options:a.options,answer:a.answer,explanation:a.explanation,category:.exam,difficulty:a.difficulty,study:.init(exam:"TYT",lesson:"Biyoloji"))
        b = Question(text:b.text,options:b.options,answer:b.answer,explanation:b.explanation,category:.exam,difficulty:b.difficulty,study:.init(exam:"AYT",lesson:"Kimya"))
        XCTAssertEqual(a.rearranged().study,a.study)
        try await database.insert([a,b])
        let found = try await database.search(text:"",topic:.exam,difficulty:nil,study:.init(exam:"TYT",lesson:"Biyoloji"))
        XCTAssertEqual(found.map(\.id),[a.id])
        let sample = try await database.sample(topic:.exam,difficulty:nil,limit:50,study:.init(exam:"AYT"))
        XCTAssertEqual(sample.map(\.id),[b.id])
        XCTAssertTrue(StudyCatalog.lessons("TYT").contains("Biyoloji")); XCTAssertTrue(StudyCatalog.lessons("AYT").contains("Matematik"))
        XCTAssertFalse(StudyLesson(exam:"Unknown",lesson:"X").isValid)
    }
}
