import XCTest
@testable import BilgiArena

final class QuestionPoolTests: XCTestCase {
    func testDailyQuotasBalanceAllLevelsAndStopAt450() {
        var counts: [PoolCell:Int] = [:]
        let day = "2026-10-29"
        for _ in 0..<150 {
            guard let cell = DailyPoolPlan.next(counts:counts,day:day) else { break }
            counts[cell,default:0] += min(5,DailyPoolPlan.quota(cell,day:day)-counts[cell,default:0])
        }
        XCTAssertEqual(counts.values.reduce(0,+),450)
        XCTAssertNil(DailyPoolPlan.next(counts:counts,day:day))
        for topic in DailyPoolPlan.categories {
            XCTAssertEqual(Difficulty.allCases.reduce(0) { $0+counts[PoolCell(topic:topic,difficulty:$1),default:0] },50)
            for level in Difficulty.allCases { XCTAssertTrue((16...17).contains(counts[PoolCell(topic:topic,difficulty:level),default:0])) }
        }
        XCTAssertNotEqual(DailyPoolPlan.quota(PoolCell(topic:.science,difficulty:.easy),day:day),DailyPoolPlan.quota(PoolCell(topic:.science,difficulty:.easy),day:"2026-10-30"))
    }
    func testChoiceOrderPreservesCorrectAnswerAndReasons() {
        let q = Question(text:"Bu soruda hangi seçenek doğrudur?",options:["Bir","İki","Üç","Dört"],answer:1,explanation:"İkinci seçenek doğru olarak belirlenmiştir.",category:.science,difficulty:.easy,optionExplanations:["Bir açıklaması","İki açıklaması","Üç açıklaması","Dört açıklaması"],modelID:"model",reviewedBy:"reviewer")
        for position in 0..<4 {
            let shuffled = q.rearranged(correctPosition:position)
            XCTAssertEqual(shuffled.answer,position); XCTAssertEqual(shuffled.options[position],"İki")
            for i in 0..<4 { XCTAssertEqual(shuffled.optionExplanations?[i],shuffled.options[i]+" açıklaması") }
            XCTAssertEqual(shuffled.reviewedBy,"reviewer")
        }
    }
    func testDuplicatePunctuationAndNearCopiesButNotDifferentNumbers() {
        XCTAssertTrue(QuestionSimilarity.isDuplicate("Dünya’nın doğal uydusu hangisidir?!",against:["Dünya'nın doğal uydusu hangisidir?"]))
        let text = "Dünya üzerindeki canlı hücrelerde genetik bilgiyi taşıyan temel molekül hangisidir?"
        XCTAssertTrue(QuestionSimilarity.isDuplicate(text,against:["Dünya üzerindeki canlı hücrelerde genetik bilgiyi taşıyan temel molekül hangisidir acaba?"]))
        XCTAssertFalse(QuestionSimilarity.isDuplicate("Bir sayının 20 ile çarpılması sonucunda elde edilen değer kaçtır?",against:["Bir sayının 30 ile çarpılması sonucunda elde edilen değer kaçtır?"]))
    }
    func testModelFamiliesInterleaveAndEveryModelAppearsOnce() {
        let ids = ["claude-a","claude-b","gpt-a","gpt-b","gemini-a"]
        let models = ids.map { PhoneModel(id:$0,owner:"test") }
        let order = PoolModelRouting.balanced(models)
        XCTAssertEqual(Set(order),Set(ids)); XCTAssertEqual(order.count,ids.count)
        XCTAssertEqual(Array(order.prefix(3)),["gpt-a","claude-a","gemini-a"])
    }
    func testDatabaseReopensDeduplicatesSeparatesDaysFiltersAndRemembersPlay() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url = folder.appendingPathComponent("pool.sqlite")
        let database = try QuestionPoolDatabase(url:url)
        let qs = Array(Seed.questions.filter { $0.category == .science && $0.difficulty == .easy }.prefix(3))
        let first = try await database.insert(qs,day:"2026-10-29"); XCTAssertEqual(first,3)
        let duplicate = try await database.insert(qs,day:"2026-10-30"); XCTAssertEqual(duplicate,0)
        try await database.markPlayed(qs[0])
        let sample = try await database.sample(topic:.science,difficulty:.easy,limit:2)
        XCTAssertFalse(sample.contains { $0.id == qs[0].id })
        try await database.hide(QuestionSimilarity.fingerprint(qs[1].text),hidden:true)
        let reopened = try QuestionPoolDatabase(url:url)
        let old = try await reopened.snapshot(day:"2026-10-29"), next = try await reopened.snapshot(day:"2026-10-30")
        XCTAssertEqual(old.today,3); XCTAssertEqual(next.today,0); XCTAssertEqual(old.total,2)
        let hidden = try await reopened.sample(topic:.science,difficulty:.easy,limit:10)
        XCTAssertFalse(hidden.contains { $0.id == qs[1].id })
        let wrongLevel = try await reopened.sample(topic:.science,difficulty:.hard,limit:10); XCTAssertTrue(wrongLevel.isEmpty)
        try await reopened.hide(QuestionSimilarity.fingerprint(qs[1].text),hidden:false)
        let found = try await reopened.search(text:qs[1].text,topic:.mixed,difficulty:nil)
        XCTAssertEqual(found.map(\.id),[qs[1].id])
    }
}

extension GenerationRecoveryTests {
    @MainActor func testDailyWorkerSavesValidBatchAndContinuesWithNextModelAfterFailure() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "pool-worker-"+UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite); try? FileManager.default.removeItem(at:folder) }
        let visualQuestions = (1...5).map { n -> Question in var q = question(n); q.visual = VisualQuestionSeeds.questions[0].visual; return q }
        let transport = ScriptedQuestionTransport(["bad JSON","bad JSON","bad JSON",try json(visualQuestions)])
        let database = try QuestionPoolDatabase(url:folder.appendingPathComponent("pool.sqlite"))
        let worker = DailyQuestionPool(defaults:defaults,gateway:try gateway(transport),database:database)
        await worker.run(maxBatches:2)
        XCTAssertEqual(worker.snapshot.today,5)
        let count = await transport.count(); XCTAssertEqual(count,4)
        let stored = try await database.sample(topic:.science,difficulty:.easy,limit:10)
        XCTAssertTrue(stored.allSatisfy { $0.modelID == "model-b" })
        XCTAssertNotNil(defaults.dictionary(forKey:"dailyPoolCooldowns")?["model-a"])
        let reopened = try QuestionPoolDatabase(url:folder.appendingPathComponent("pool.sqlite"))
        let snapshot = try await reopened.snapshot(day:DailyPoolPlan.day(Date())); XCTAssertEqual(snapshot.today,5)
    }
    func testFailedCheckpointStopsGenerationBeforeAnotherRequest() async throws {
        enum StorageFailure: Error { case full }
        let transport = ScriptedQuestionTransport([try json((1...5).map(question))])
        do {
            _ = try await AIService(gateway:gateway(transport)).questions(topic:.science,detail:"",difficulty:.easy,count:10,models:["model-a"],excluding:[],onBatch:{ _ in throw StorageFailure.full },progress:{ _,_,_ in })
            XCTFail("A failed durable checkpoint must stop work")
        } catch { XCTAssertTrue(error is StorageFailure) }
        let calls = await transport.count(); XCTAssertEqual(calls,1)
    }
}
