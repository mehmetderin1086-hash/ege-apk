import XCTest
import ProxyKit
@testable import BilgiArena

actor RecordingTransport: HTTPTransport {
    var calls = 0
    func send(_ request: URLRequest) async throws -> UpstreamResponse { calls += 1; return .fixed(status: 401, data: Data("{}".utf8)) }
    func count() -> Int { calls }
}
final class PhoneGatewayTests: XCTestCase {
    func testFilteredVaultPreservesSharedSettingsOnTokenWrite() throws {
        var original = ProxyState()
        original.remote = RemoteProxy(baseURL: "https://vps.example/v1", personalToken: "fixture", syncToken: "fixture", enabled: true)
        original.oauth = [OAuthAccount(id:"a",provider:.codex,label:"fixture",accessToken:"old",refreshToken:"refresh",expiresAt:Date(timeIntervalSinceNow:200),refreshOwner:.telefon)]
        original.apiProviders = [APIKeyProvider(name:"remote",kind:.openAICompatible,baseURL:"https://vps.example/v1",apiKey:"fixture",models:["fake"]), APIKeyProvider(name:"official",kind:.openAICompatible,baseURL:"https://api.openai.com/v1",apiKey:"fixture",models:["gpt-6-luna"])]
        let base = MemorySecretStore(try PhoneAccountStore.encode(original))
        let store = PhoneAccountStore(shared: base)
        var local = try PhoneAccountStore.decode(XCTUnwrap(store.load()))
        XCTAssertFalse(local.remote.isUsable); XCTAssertTrue(local.remote.baseURL.isEmpty)
        XCTAssertEqual(local.apiProviders.count,1)
        local.oauth[0].accessToken = "new"; local.oauth[0].expiresAt = Date(timeIntervalSinceNow:1000)
        try store.save(PhoneAccountStore.encode(local))
        let saved = try PhoneAccountStore.decode(XCTUnwrap(base.load()))
        XCTAssertEqual(saved.remote, original.remote)
        XCTAssertEqual(saved.apiProviders, original.apiProviders)
        XCTAssertEqual(saved.oauth[0].accessToken,"new")
    }
    func testExpiredServerOwnedAccountCannotContactVPS() async throws {
        var state = ProxyState()
        state.remote = RemoteProxy(baseURL:"https://vps.example/v1",personalToken:"fixture",syncToken:"fixture",enabled:true)
        state.oauth = [OAuthAccount(id:"a",provider:.codex,label:"fixture",accessToken:"expired",refreshToken:nil,expiresAt:.distantPast,refreshOwner:.sunucu)]
        let transport = RecordingTransport()
        let gateway = PhoneGateway(store: PhoneAccountStore(shared: MemorySecretStore(try PhoneAccountStore.encode(state))), transport: transport)
        let inventory = try await gateway.inventory()
        XCTAssertTrue(inventory.serverDisabled); XCTAssertEqual(inventory.expiringAccounts,1)
        do { _ = try await gateway.chat(model:"gpt-6-luna",system:"test",user:"test"); XCTFail("Expected refusal") } catch {}
        let count = await transport.count()
        XCTAssertEqual(count,0)
    }
    @MainActor func testWrongAnswerEntersReviewAndSurvivesReopen() throws {
        let suite = "arena-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let q = Seed.questions[0]
        let store = GameStore(defaults:defaults,startTimer:false)
        store.start([q],source:"test",mode:.training)
        store.answer((q.answer + 1) % 4)
        XCTAssertEqual(store.dueCards.count,1)
        let reopened = GameStore(defaults:defaults,startTimer:false)
        XCTAssertEqual(reopened.dueCards.first?.question.id,q.id)
        XCTAssertTrue(reopened.round?.paused == true)
    }
}

actor QuestionTransport: HTTPTransport {
    var calls = 0
    func send(_ request: URLRequest) async throws -> UpstreamResponse {
        calls += 1
        let p = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let model = p["model"] as! String
        let qs = (0..<5).map { index in Question(text:"\(model) için benzersiz soru \(index)?",options:["A","B","C","D"],answer:0,explanation:"Bu seçenek verilen bilgiye göre doğrudur.",category:.science,difficulty:.easy,optionExplanations:["Doğru seçenek","Yanlış seçenek","Yanlış seçenek","Yanlış seçenek"]) }
        let content = String(decoding: try JSONEncoder().encode(["questions":qs]),as:UTF8.self)
        let body: [String:Any] = ["model":model,"choices":[["message":["content":content]]]]
        return .fixed(status:200,data:try JSONSerialization.data(withJSONObject:body))
    }
    func count() -> Int { calls }
}
extension PhoneGatewayTests {
    func testTeamGenerationRotatesModelsAndResumesCompletedBatch() async throws {
        var state = ProxyState()
        state.apiProviders = [APIKeyProvider(name:"fixture",kind:.openAICompatible,baseURL:"https://api.openai.com/v1",apiKey:"fixture",models:["model-a","model-b"])]
        let transport = QuestionTransport()
        let gateway = PhoneGateway(store:PhoneAccountStore(shared:MemorySecretStore(try PhoneAccountStore.encode(state))),transport:transport)
        let first = (0..<5).map { i in Question(text:"Önceden tamamlanan soru \(i)?",options:["A","B","C","D"],answer:0,explanation:"Doğru seçenek bu soruda ilk seçenektir.",category:.science,difficulty:.easy,optionExplanations:["Doğru seçenek","Yanlış seçenek","Yanlış seçenek","Yanlış seçenek"],modelID:"model-a") }
        let qs = try await AIService(gateway:gateway).questions(topic:.science,detail:"",difficulty:.easy,count:10,models:["model-a","model-b"],excluding:[],initial:first,progress:{ _,_,_ in })
        XCTAssertEqual(qs.count,10)
        XCTAssertEqual(qs.prefix(5).map(\.modelID),Array(repeating:"model-a",count:5))
        XCTAssertEqual(qs.suffix(5).map(\.modelID),Array(repeating:"model-b",count:5))
        let count = await transport.count(); XCTAssertEqual(count,1)
    }
}
