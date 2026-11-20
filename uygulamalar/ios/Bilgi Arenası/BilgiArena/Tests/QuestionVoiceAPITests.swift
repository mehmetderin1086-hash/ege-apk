import XCTest
import ProxyKit
@testable import BilgiArena

actor VoiceFixtureTransport: HTTPTransport {
    var calls = 0
    let status: Int
    let data: Data
    init(status: Int = 200, data: Data) { self.status = status; self.data = data }
    func send(_ request: URLRequest) async throws -> UpstreamResponse { calls += 1; return .fixed(status:status,data:data) }
    func count() -> Int { calls }
}
final class QuestionVoiceAPITests: XCTestCase {
    func testLanguageSpecificVoicesEscapeTextAndRejectInvalidRegion() throws {
        let choice = QuestionVoiceChoice(engine:.azure,voice:"Elif",model:"")
        let request = try QuestionVoiceAPI.azureRequest(text:"A < B & C",language:"tr-TR",choice:choice,config:.init(azureKey:"fixture",azureRegion:"westeurope"))
        XCTAssertEqual(request.url?.host,"westeurope.tts.speech.microsoft.com")
        let ssml = String(decoding:request.httpBody!,as:UTF8.self)
        XCTAssertTrue(ssml.contains("A &lt; B &amp; C")); XCTAssertTrue(ssml.contains("tr-TR-Elif:MAI-Voice-2-Flash"))
        XCTAssertEqual(QuestionVoiceAPI.azureVoice("Elif",language:"en-US"),"en-US-AvaMultilingualNeural")
        XCTAssertThrowsError(try QuestionVoiceAPI.azureRequest(text:"Hello",language:"en-US",choice:choice,config:.init(azureKey:"fixture",azureRegion:"evil.com/path")))
        let body = try JSONSerialization.jsonObject(with:QuestionVoiceAPI.chirpBody(text:"Good morning",language:"en-US",voice:"Kore")) as! [String:Any]
        XCTAssertEqual((body["voice"] as? [String:String])?["name"],"en-US-Chirp3-HD-Kore")
        XCTAssertFalse(PhonePolicy.allows(URL(string:"https://westeurope.tts.speech.microsoft.com.evil.example")))
        XCTAssertTrue(PhonePolicy.allows(request.url))
    }
    func testAudioCacheAvoidsRepeatNetworkRequestsAndSeparatesLanguages() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        var bytes = Data("ID3".utf8); bytes.append(Data(repeating:1,count:200))
        let transport = VoiceFixtureTransport(data:bytes)
        let service = QuestionVoiceAPI(transport:transport,folder:folder,configuration:{ .init(azureKey:"fixture",azureRegion:"westeurope") })
        let choice = QuestionVoiceChoice(engine:.azure,voice:"Elif",model:"")
        let a = try await service.audio(text:"Hello",language:"en-US",choice:choice)
        let b = try await service.audio(text:"Hello",language:"en-US",choice:choice)
        XCTAssertEqual(a,b)
        let c = try await service.audio(text:"Hello",language:"tr-TR",choice:choice)
        XCTAssertNotEqual(a,c)
        let count = await transport.count(); XCTAssertEqual(count,2)
    }
    func testGeminiSpeechUsesNativeAudioAndWrapsPCMWithWavHeader() throws {
        let body = try JSONSerialization.jsonObject(with:PhoneGateway.geminiSpeechBody(text:"Good morning",language:"en-US",voice:"Kore")) as! [String:Any]
        XCTAssertNotNil(body["generationConfig"])
        XCTAssertThrowsError(try PhoneGateway.geminiSpeechBody(text:"Hello",language:"en-US",voice:"marin"))
        let pcm = Data(repeating:0,count:48000)
        let json = try JSONSerialization.data(withJSONObject:["candidates":[["content":["parts":[["inlineData":["mimeType":"audio/L16;codec=pcm;rate=24000","data":pcm.base64EncodedString()]]]]]]])
        let wav = try PhoneGateway.geminiAudio(json)
        XCTAssertEqual(wav.count,48044); XCTAssertTrue(QuestionVoiceAPI.validAudio(wav))
        XCTAssertEqual(String(decoding:wav[8..<12],as:UTF8.self),"WAVE")
        XCTAssertThrowsError(try PhoneGateway.geminiAudio(Data("{}".utf8)))
    }
    func testQuotaAndInvalidAudioAreNotCachedOrReportedAsSuccess() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let transport = VoiceFixtureTransport(status:429,data:Data("quota".utf8))
        let service = QuestionVoiceAPI(transport:transport,folder:folder,configuration:{ .init(azureKey:"fixture",azureRegion:"westeurope") })
        do { _ = try await service.audio(text:"Hello",language:"en-US",choice:.init(engine:.azure,voice:"Elif",model:"")); XCTFail("Quota failure must not succeed") }
        catch { XCTAssertTrue((error as? QuizError)?.message.contains("kota") == true) }
        XCTAssertFalse(QuestionVoiceAPI.validAudio(Data(repeating:32,count:200)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:folder.path).count,0)
    }
}
