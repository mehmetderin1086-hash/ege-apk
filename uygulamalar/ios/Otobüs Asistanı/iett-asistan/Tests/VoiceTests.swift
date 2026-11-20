import Foundation
import Testing
@testable import IETTAsistan

/// Ağa çıkmayan sahte oturum: sıradaki yanıtları verir, giden istekleri kaydeder.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [(Int, Data)] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    static func reset(_ list: [(Int, Data)]) { responses = list; requests = [] }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var request = self.request
        if let stream = request.httpBodyStream { stream.open(); var data = Data(); let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096); defer { buffer.deallocate() }
            while stream.hasBytesAvailable { let n = stream.read(buffer, maxLength: 4096); if n <= 0 { break }; data.append(buffer, count: n) }; request.httpBody = data }
        Self.requests.append(request)
        let (status, body) = Self.responses.isEmpty ? (500, Data()) : Self.responses.removeFirst()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    static var session: URLSession { let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [StubProtocol.self]; return URLSession(configuration: c) }
}

@Suite(.serialized) struct VoiceTests {
    @Test func spokenTextExpandsAbbreviationsAndDropsSymbols() {
        #expect(SpeechText.spoken(from: "500T hattı → 4.LEVENT METRO · ~7 dk (-1)") == "500T hattı  yönüne  4.LEVENT METRO, yaklaşık 7 dakika".replacingOccurrences(of: "  ", with: " "))
        #expect(SpeechText.spoken(from: "Durak 1,2 km uzakta, 300 m yürü, 45 sn kaldı") == "Durak 1,2 kilometre uzakta, 300 metre yürü, 45 saniye kaldı")
        #expect(SpeechText.spoken(from: "Şu an yolda 1 araç var (G: 0, D: 1).") == "Şu an yolda 1 araç var (gidiş 0, dönüş 1)")
        #expect(SpeechText.spoken(from: "İlk 05:50, son 23:35 ⭐ 🚌 satır\nikinci satır") == "İlk 05 50, son 23 35 satır. ikinci satır")
        #expect(SpeechText.spoken(from: "  ...  ") == "")
    }
    @Test func chunksSplitOnSentencesAndNeverExceedTheLimit() {
        let sentence = "Bu bir deneme cümlesidir"
        let text = Array(repeating: sentence + ".", count: 80).joined(separator: " ")
        let chunks = SpeechText.chunks(text, max: 200)
        #expect(chunks.count > 5 && chunks.allSatisfy { $0.count <= 200 })
        #expect(chunks.joined(separator: " ").replacingOccurrences(of: " ", with: "").count == text.replacingOccurrences(of: " ", with: "").count)
        #expect(SpeechText.chunks("Kısa.") == ["Kısa."] && SpeechText.chunks("   ").isEmpty)
        let long = SpeechText.chunks(Array(repeating: "kelime", count: 500).joined(separator: " "), max: 100)
        #expect(long.allSatisfy { $0.count <= 100 })
    }
    @Test func ssmlEscapesTextAndSetsProsody() {
        let xml = SpeechText.ssml(text: "A & B <C>", voice: "tr-TR-EmelNeural", rate: 1.1)
        #expect(xml.contains("name='tr-TR-EmelNeural'") && xml.contains("A &amp; B &lt;C&gt;") && xml.contains("rate='+10%'") && xml.contains("xml:lang='tr-TR'"))
        #expect(SpeechText.ssml(text: "x", voice: "v", rate: 0.9).contains("rate='-10%'"))
    }
    @Test func endpointDetectorFiresAfterSilenceOnly() {
        var detector = EndpointDetector(silence: 1.0)
        let t0 = Date()
        let r1 = detector.update(text: "", now: t0)
        let r2 = detector.update(text: "500T", now: t0.addingTimeInterval(0.2))
        let r3 = detector.update(text: "500T kaç", now: t0.addingTimeInterval(0.8))      // yeni kelime sayacı sıfırlar
        let r4 = detector.update(text: "500T kaç", now: t0.addingTimeInterval(1.5))
        let r5 = detector.update(text: "500T kaç", now: t0.addingTimeInterval(1.9))      // 1,1 sn değişmedi
        #expect(!r1 && !r2 && !r3 && !r4 && r5)
        detector.reset()
        let r6 = detector.update(text: "", now: t0.addingTimeInterval(10))
        #expect(!r6)
    }
    @Test func routerOrdersEnginesAndAlwaysEndsWithTheDevice() {
        #expect(VoiceRouter.order(.auto, azureConfigured: true, serverConfigured: true) == [.azure, .chirp, .apple])
        #expect(VoiceRouter.order(.auto, azureConfigured: false, serverConfigured: true) == [.chirp, .apple])
        #expect(VoiceRouter.order(.chirp, azureConfigured: true, serverConfigured: true) == [.chirp, .azure, .apple])
        #expect(VoiceRouter.order(.azure, azureConfigured: false, serverConfigured: false) == [.apple])
        #expect(VoiceRouter.order(.apple, azureConfigured: true, serverConfigured: true) == [.apple])
    }
    @Test func chirpClientBuildsTheRequestDecodesAudioAndRetriesOnce() async throws {
        let wav = Data(repeating: 7, count: 400)
        let ok = try JSONSerialization.data(withJSONObject: ["audio": wav.base64EncodedString(), "durationSec": 1.2])
        let failure = try JSONSerialization.data(withJSONObject: ["error": ["code": "upstream_error", "message": "Ses motoru ses yanıtı okunamadı."]])
        StubProtocol.reset([(502, failure), (200, ok)])
        let clip = try await ChirpTTS(host: "ses.example", token: "TOKEN", voice: "Kore", session: StubProtocol.session).synthesize("Merhaba")
        #expect(clip == AudioClip(data: wav, fileExtension: "wav") && StubProtocol.requests.count == 2)
        let request = StubProtocol.requests[0]
        #expect(request.url?.absoluteString == "https://ses.example/dersdas/v1/speak" && request.value(forHTTPHeaderField: "X-Personal-Token") == "TOKEN" && request.httpMethod == "POST")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String]
        #expect(body == ["engine": "chirp", "voice": "Kore", "pace": "normal", "text": "Merhaba"])
        // Kalıcı hata yeniden denenmez; ikinci denemeden sonra da hata fırlatır.
        StubProtocol.reset([(400, try JSONSerialization.data(withJSONObject: ["error": ["message": "Geçersiz ses."]]))])
        await #expect(throws: TTSError.self) { try await ChirpTTS(host: "h", token: "t", voice: "X", session: StubProtocol.session).synthesize("a") }
        #expect(StubProtocol.requests.count == 1)
        StubProtocol.reset([(502, failure), (502, failure)])
        await #expect(throws: TTSError.self) { try await ChirpTTS(host: "h", token: "t", voice: "Kore", session: StubProtocol.session).synthesize("a") }
        #expect(StubProtocol.requests.count == 2)
        #expect(ChirpTTS(host: "h", token: "t", voice: "Kore", rate: 1.3).name == "Chirp · Kore")
    }
    @Test func azureClientSendsSSMLWithKeyAndMapsErrors() async throws {
        StubProtocol.reset([(200, Data(repeating: 1, count: 500))])
        let azure = AzureTTS(key: "KEY", region: "westeurope", voice: "tr-TR-EmelNeural", session: StubProtocol.session)
        let clip = try await azure.synthesize("Merhaba & hoş geldin")
        #expect(clip.fileExtension == "mp3" && clip.data.count == 500)
        let request = StubProtocol.requests[0]
        #expect(request.url?.absoluteString == "https://westeurope.tts.speech.microsoft.com/cognitiveservices/v1")
        #expect(request.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") == "KEY" && request.value(forHTTPHeaderField: "Content-Type") == "application/ssml+xml")
        #expect(request.value(forHTTPHeaderField: "X-Microsoft-OutputFormat") == "audio-24khz-48kbitrate-mono-mp3")
        let xml = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        #expect(xml.contains("Merhaba &amp; hoş geldin") && xml.contains("tr-TR-EmelNeural"))
        StubProtocol.reset([(401, Data())])
        do { _ = try await azure.synthesize("a"); Issue.record("hata beklenirdi") } catch { #expect(error.localizedDescription.contains("anahtarı")) }
        #expect(azure.name == "Azure · Emel")
    }
}

import AVFoundation

/// Gerçek ses sunucusuna bağlanır (Secrets.xcconfig gerekir); günlük "tools" hakkından 1 harcar.
struct LiveVoiceTests {
    @Test func realChirpReturnsPlayableAudioThroughTheAppConfiguration() async throws {
        guard let host = VoiceConfig.serverHost, let token = VoiceConfig.serverToken else { Issue.record("Secrets.xcconfig ses sunucusu ayarı yok"); return }
        let text = SpeechText.spoken(from: "500T hattı → 4.LEVENT METRO durağına ~4 dk kaldı.")
        let clip = try await ChirpTTS(host: host, token: token, voice: "Kore").synthesize(text)
        #expect(clip.fileExtension == "wav" && String(decoding: clip.data.prefix(4), as: UTF8.self) == "RIFF")
        let player = try AVAudioPlayer(data: clip.data)
        #expect(player.duration > 1.5 && player.duration < 12, "süre \(player.duration)")
    }
}
