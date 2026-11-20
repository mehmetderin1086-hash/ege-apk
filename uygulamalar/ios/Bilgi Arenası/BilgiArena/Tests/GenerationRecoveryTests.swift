import XCTest
import ProxyKit
@testable import BilgiArena

actor ScriptedQuestionTransport: HTTPTransport {
    var replies: [String]
    var calls = 0
    init(_ replies: [String]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> UpstreamResponse {
        let index = min(calls, replies.count - 1); calls += 1
        let body: [String: Any] = ["choices":[["message":["content":replies[index]]]]]
        return .fixed(status:200,data:try JSONSerialization.data(withJSONObject:body))
    }
    func count() -> Int { calls }
}
actor SavedBatches {
    var questions: [Question] = []
    func save(_ qs: [Question]) { questions = qs }
    func count() -> Int { questions.count }
}
final class GenerationRecoveryTests: XCTestCase {
    func question(_ n: Int) -> Question {
        Question(text:"Bu örnekte \(n) numaralı sorunun doğru seçeneği hangisidir?", options:["Birinci","İkinci","Üçüncü","Dördüncü"], answer:0, explanation:"Bu örnekte ilk seçenek doğru kabul edilmiştir.", category:.science, difficulty:.easy, optionExplanations:["Doğru seçenek","Yanlış seçenek","Yanlış seçenek","Yanlış seçenek"])
    }
    func json(_ qs: [Question]) throws -> String { String(decoding:try JSONEncoder().encode(["questions":qs]),as:UTF8.self) }
    func gateway(_ transport: ScriptedQuestionTransport) throws -> PhoneGateway {
        var state = ProxyState()
        state.apiProviders = [APIKeyProvider(name:"test",kind:.openAICompatible,baseURL:"https://api.openai.com/v1",apiKey:"fixture",models:["model-a","model-b"])]
        return PhoneGateway(store:PhoneAccountStore(shared:MemorySecretStore(try PhoneAccountStore.encode(state))),transport:transport)
    }
    func testProseWrappedAndDirectArraysCanBeReadWithoutWeakeningImports() throws {
        let envelope = try json([question(1)])
        let parsed = GeneratedQuestionParser.parse("İşte soru paketi:\n```json\n" + envelope + "\n```\nİyi oyunlar.",topic:.science,difficulty:.easy,excluding:[],limit:1)
        XCTAssertEqual(parsed.questions.map(\.text),[question(1).text])
        let array = String(decoding:try JSONEncoder().encode([question(2)]),as:UTF8.self)
        XCTAssertEqual(GeneratedQuestionParser.parse(array,topic:.science,difficulty:.easy,excluding:[],limit:1).questions.count,1)
        XCTAssertThrowsError(try Question.decode(array,expectedCount:1))
    }
    func testTruncatedTailKeepsOnlyCompleteValidQuestions() throws {
        let first = String(decoding:try JSONEncoder().encode(question(1)),as:UTF8.self)
        let truncated = "{\"questions\":[" + first + ",{\"text\":\"yarıda kalan soru"
        let parsed = GeneratedQuestionParser.parse(truncated,topic:.science,difficulty:.easy,excluding:[],limit:5)
        XCTAssertEqual(parsed.questions.map(\.text),[question(1).text])
    }
    func testAnswerLettersAndMissingMetadataNormalizeButInvalidAnswersDoNot() throws {
        let raw = try JSONEncoder().encode(question(1))
        var row = try JSONSerialization.jsonObject(with:raw) as! [String:Any]
        row["answer"] = "B"; row.removeValue(forKey:"category"); row.removeValue(forKey:"difficulty")
        func parse(_ row: [String:Any]) throws -> [Question] {
            let text = String(decoding:try JSONSerialization.data(withJSONObject:["questions":[row]]),as:UTF8.self)
            return GeneratedQuestionParser.parse(text,topic:.science,difficulty:.easy,excluding:[],limit:1).questions
        }
        XCTAssertEqual(try parse(row).first?.answer,1)
        row["answer"] = 4; XCTAssertTrue(try parse(row).isEmpty)
        row["answer"] = true; XCTAssertTrue(try parse(row).isEmpty)
        row["answer"] = 1.5; XCTAssertTrue(try parse(row).isEmpty)
        row["answer"] = 0; row.removeValue(forKey:"optionExplanations"); XCTAssertTrue(try parse(row).isEmpty)
    }
    func testSavedFiveSurviveShortResponseAndOnlyMissingQuestionsAreCompleted() async throws {
        let transport = ScriptedQuestionTransport([try json([question(6),question(7)]),try json([question(8),question(9),question(10)])])
        let saved = SavedBatches()
        let first = (1...5).map(question)
        let qs = try await AIService(gateway:gateway(transport)).questions(topic:.science,detail:"",difficulty:.easy,count:10,models:["model-a","model-b"],excluding:[],initial:first,onBatch:{ await saved.save($0) },progress:{ _,_,_ in })
        XCTAssertEqual(qs.count,10); XCTAssertEqual(Array(qs.prefix(5)),first)
        XCTAssertEqual(Set(qs.map(\.text)).count,10)
        XCTAssertTrue(qs.suffix(5).allSatisfy { $0.modelID == "model-b" })
        let calls = await transport.count(); XCTAssertEqual(calls,2)
        let count = await saved.count(); XCTAssertEqual(count,10)
    }
    func testRepeatedMalformedResponseIsBoundedAndPartialProgressIsSaved() async throws {
        let transport = ScriptedQuestionTransport([try json([question(6),question(7)]),"{invalid", "no JSON"])
        let saved = SavedBatches()
        do {
            _ = try await AIService(gateway:gateway(transport)).questions(topic:.science,detail:"",difficulty:.easy,count:10,models:["model-a","model-b"],excluding:[],initial:(1...5).map(question),onBatch:{ await saved.save($0) },progress:{ _,_,_ in })
            XCTFail("Incomplete generation must not be accepted")
        } catch { XCTAssertTrue((error as? QuizError)?.message.contains("7 soru korundu") == true) }
        let calls = await transport.count(); XCTAssertEqual(calls,3)
        let count = await saved.count(); XCTAssertEqual(count,7)
    }
}

extension GenerationRecoveryTests {
    @MainActor func testStoredDraftCanResumeWithAnotherModelAfterFailure() async throws {
        let suite = "recovery-store-" + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let initial = (1...5).map(question)
        let draft = GenerationDraft(id:UUID(),topic:.science,detail:"",difficulty:.easy,count:10,models:["model-a","model-b"],questions:initial)
        defaults.set(try JSONEncoder().encode(draft),forKey:"draft")
        defaults.set(["model-a","model-b"],forKey:"teamModels")
        defaults.set(true,forKey:"teamEnabled")
        defaults.set(true,forKey:"phoneTeamV2Configured")
        let transport = ScriptedQuestionTransport(["not JSON","{invalid","[]",try json((6...10).map(question))])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let gateway = try gateway(transport)
        let database = try QuestionPoolDatabase(url:folder.appendingPathComponent("pool.sqlite"))
        let pool = DailyQuestionPool(defaults:defaults,gateway:gateway,database:database)
        let store = GameStore(defaults:defaults,gateway:gateway,startTimer:false,pool:pool)
        store.topic = .science; store.difficulty = .easy
        await store.startAI()
        XCTAssertEqual(store.draft?.questions,initial)
        XCTAssertFalse(store.loading); XCTAssertNotNil(store.error)
        store.error = nil
        store.teamEnabled = false; store.selectedModel = "model-a"
        await store.startAI()
        XCTAssertNil(store.error); XCTAssertNil(store.draft); XCTAssertFalse(store.loading)
        XCTAssertEqual(Array(store.round!.questions.prefix(5)),initial)
        XCTAssertEqual(store.round?.questions.count,10)
        XCTAssertEqual(store.packs.count,1)
        XCTAssertTrue(store.round!.questions.suffix(5).allSatisfy { $0.modelID == "model-a" })
        let calls = await transport.count(); XCTAssertEqual(calls,4)
    }
}
