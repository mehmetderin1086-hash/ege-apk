import Foundation
import AVFoundation
import UIKit

struct QuizLiveConnection {
    let request: URLRequest
    let model: String
}
enum QuizLiveProtocol {
    static func setup(_ engine: QuizLiveEngine, model: String) -> [String:Any] {
        let instruction = "Sen bilgi yarışması sunucususun. Yalnız sana oku diye verilen metni aynen seslendir. Soruları çözme, doğru cevabı tahmin etme, puan verme. Kullanıcının konuşmasına yalnız 'Yanıtını aldım' de. Puanı uygulama hesaplar."
        if engine == .openAI {
            return ["type":"session.update","session":["type":"realtime","model":model,"instructions":instruction,"output_modalities":["audio"],"audio":["input":["format":["type":"audio/pcm","rate":24000],"transcription":["model":"whisper-1","language":"tr"],"turn_detection":["type":"server_vad","silence_duration_ms":1000,"create_response":false,"interrupt_response":true]],"output":["format":["type":"audio/pcm","rate":24000],"voice":"marin"]]]]
        }
        return ["setup":["model":"models/"+model,"generationConfig":["responseModalities":["AUDIO"],"speechConfig":["voiceConfig":["prebuiltVoiceConfig":["voiceName":"Kore"]]]],"systemInstruction":["parts":[["text":instruction]]],"inputAudioTranscription":[:],"outputAudioTranscription":[:]]]
    }
    static func read(_ engine: QuizLiveEngine, text: String, language: String) -> [String:Any] {
        let prompt = "\(language) dilinde yalnız aşağıdaki metni aynen oku; soruyu yanıtlama:\n"+text
        if engine == .openAI { return ["type":"response.create","response":["input":[],"instructions":prompt,"output_modalities":["audio"]]] }
        return ["clientContent":["turns":[["role":"user","parts":[["text":prompt]]]],"turnComplete":true]]
    }
    static func audio(_ engine: QuizLiveEngine, data: Data) -> [String:Any] {
        engine == .openAI ? ["type":"input_audio_buffer.append","audio":data.base64EncodedString()] : ["realtimeInput":["audio":["mimeType":"audio/pcm;rate=16000","data":data.base64EncodedString()]]]
    }
    enum Event: Equatable { case ready, audio(Data), transcript(String), done, failed(String), ignore }
    static func event(_ json: [String:Any], engine: QuizLiveEngine) -> [Event] {
        if let error = json["error"] as? [String:Any] {
            let code = (error["code"] as? String ?? String(error["code"] as? Int ?? 0)).lowercased()
            if ["response_cancel_not_active","input_audio_buffer_commit_empty"].contains(code) { return [] }
            let quota = code.contains("quota") || code.contains("rate") || code.contains("credit") || ["402","429","8"].contains(code)
            return [.failed(quota ? "Canlı ses hesabının kota/kredisi yetersiz. Sıralı sesli modu kullanabilirsin." : "Canlı ses sağlayıcısı isteği kabul etmedi. Hesap ve model erişimini kontrol et.")]
        }
        if engine == .openAI {
            switch json["type"] as? String {
            case "session.updated": return [.ready]
            case "response.output_audio.delta", "response.audio.delta": return (json["delta"] as? String).flatMap { Data(base64Encoded:$0) }.map { [.audio($0)] } ?? []
            case "conversation.item.input_audio_transcription.completed": return (json["transcript"] as? String).map { [.transcript($0)] } ?? []
            case "response.done":
                if let response = json["response"] as? [String:Any], response["status"] as? String == "failed" { return [.failed("ChatGPT canlı ses üretilemedi; kota veya model erişimini kontrol et.")] }
                return [.done]
            default:return []
            }
        }
        if json["setupComplete"] != nil { return [.ready] }
        if json["goAway"] != nil { return [.failed("Gemini canlı oturumu sona eriyor. Yeniden bağlanabilirsin.")] }
        guard let content = json["serverContent"] as? [String:Any] else { return [] }
        var events: [Event] = []
        if let transcript = content["inputTranscription"] as? [String:Any], let text = transcript["text"] as? String { events.append(.transcript(text)) }
        if let turn = content["modelTurn"] as? [String:Any], let parts = turn["parts"] as? [[String:Any]] {
            for part in parts {
                if let inline = part["inlineData"] as? [String:Any], let mime = inline["mimeType"] as? String, mime.hasPrefix("audio/pcm"), let text = inline["data"] as? String, let data = Data(base64Encoded:text) { events.append(.audio(data)) }
            }
        }
        if content["turnComplete"] as? Bool == true { events.append(.done) }; return events
    }
}
@MainActor final class RemoteQuizVoice: QuizLiveVoice {
    let engine: QuizLiveEngine
    let gateway: PhoneGateway
    var route: String { engine.title+" · iPhone CLI Proxy hesabı" }
    var level: Double { max(0,min(1,Double((pcm?.girisDb ?? -100)+55)/55)) }
    private(set) var receivedAudioBytes = 0
    private(set) var lastErrorCode: String?
    private(set) var closeKind: String?
    private(set) var transportStatus: String?
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var receiver: Task<Void,Never>?
    private var sender: Task<Void,Never>?
    private var pcm: QuizLivePCMIO?
    private var ready = false, readDone = false, listening = false
    private var transcript = ""
    private var failure: String?
    private var token = UUID()
    private var turnDone = false
    init(engine: QuizLiveEngine, gateway: PhoneGateway = .shared) { self.engine = engine; self.gateway = gateway }
    func prepare() async throws {
        if ready { return }
        stop(); failure = nil
        let id = token
        let connection = try await gateway.liveConnection(engine)
        try Task.checkCancellation()
        guard token == id else { throw CancellationError() }
        let session = URLSession(configuration:.ephemeral,delegate:PhoneRedirectGuard(),delegateQueue:nil)
        self.session = session
        await PhoneTraffic.shared.record(connection.request.url?.host ?? "")
        let socket = session.webSocketTask(with:connection.request); socket.maximumMessageSize = 4_000_000; self.socket = socket; socket.resume()
        receiver = Task { [weak self] in await self?.receive(id:id) }
        try await send(QuizLiveProtocol.setup(engine,model:connection.model))
        try await wait(seconds:12) { self.ready }
    }
    private func ensureAudio() async throws {
        if pcm != nil { return }
        guard await AVAudioApplication.requestRecordPermission() else { throw QuizError("Canlı mod için mikrofon izni gerekiyor.") }
        try Task.checkCancellation()
        guard UIApplication.shared.applicationState == .active else { throw QuizError("Mikrofon izninden sonra Canlı devam düğmesine dokun.") }
        let io = QuizLivePCMIO(girisHz:engine == .openAI ? 24000 : 16000)
        let pair = AsyncStream<Data>.makeStream(bufferingPolicy:.bufferingOldest(8))
        let id = token
        io.kesildi = { [weak self] _ in Task { @MainActor in if self?.token == id { self?.failure = "Ses yolu kesildi. Canlı turu yeniden başlat." } } }
        sender = Task { [weak self] in
            for await data in pair.stream {
                guard let self, !Task.isCancelled, token == id else { return }
                if listening { do { try await send(QuizLiveProtocol.audio(engine,data:data)) } catch { failure = "Canlı ses gönderilemedi."; return } }
            }
        }
        let success: Bool = await withCheckedContinuation { continuation in
            GameAudio.sessionQueue.async { [weak self] in
                do { try io.baslat { [weak self] data in
                    if case .dropped = pair.continuation.yield(data) { Task { @MainActor [weak self] in if self?.token == id { self?.failure = "Canlı ses bağlantısı yavaşladı. Yeniden bağlan." } } }
                }; continuation.resume(returning:true) } catch { continuation.resume(returning:false) }
            }
        }
        guard success else { sender?.cancel(); pair.continuation.finish(); GameAudio.sessionQueue.async { io.durdur() }; throw QuizError("Canlı mikrofon başlatılamadı.") }
        guard token == id, !Task.isCancelled else { GameAudio.sessionQueue.async { io.durdur() }; throw CancellationError() }
        pcm = io
    }
    func speak(_ segments: [QuizSpeechSegment]) async throws {
        try await ensureAudio(); listening = false
        for segment in segments {
            let before = receivedAudioBytes
            readDone = false; try await send(QuizLiveProtocol.read(engine,text:segment.text,language:segment.language))
            try await wait(seconds:90) { self.readDone }
            guard receivedAudioBytes > before else { throw QuizError("Canlı model soruyu seslendirmedi. Sıralı sesli modu seçebilirsin.") }
            let id = token; var drained = false
            pcm?.calinincaBildir { [weak self] in Task { @MainActor [weak self] in if self?.token == id { drained = true } } }
            try await wait(seconds:90) { drained }
        }
    }
    func probe() async throws -> Int {
        try await prepare(); readDone = false
        try await send(QuizLiveProtocol.read(engine,text:"Merhaba. Hazır mısın?",language:"tr-TR"))
        try await wait(seconds:15) { self.readDone }
        guard receivedAudioBytes > 100 else { throw QuizError("Canlı model ses döndürmedi.") }; return receivedAudioBytes
    }
    func hear(language: String) async throws -> String {
        transcript = ""; turnDone = false
        if engine == .openAI {
            try await send(["type":"session.update","session":["type":"realtime","audio":["input":["transcription":["model":"whisper-1","language":language]]]]])
            try await send(["type":"input_audio_buffer.clear"])
        }
        listening = true; defer { listening = false; pcm?.yanitiKes() }
        try await wait(seconds:25) { !self.transcript.isEmpty && (self.engine == .openAI || self.turnDone) }
        return transcript
    }
    func finishHearing() {
        guard listening else { return }
        Task {
            do { try await send(engine == .openAI ? ["type":"input_audio_buffer.commit"] : ["realtimeInput":["audioStreamEnd":true]]) }
            catch { failure = "Ses turu tamamlanamadı." }
        }
    }
    private func wait(seconds: Double, until condition: () -> Bool) async throws {
        let id = token, end = Date().addingTimeInterval(seconds)
        while !condition() {
            try Task.checkCancellation()
            guard token == id else { throw CancellationError() }
            if let failure { throw QuizError(failure) }
            guard Date() < end else { throw QuizError("Canlı ses yanıtı zamanında gelmedi. Yeniden dene veya sıralı sesli moda geç.") }
            try await Task.sleep(for:.milliseconds(80))
        }
        try Task.checkCancellation()
        guard token == id else { throw CancellationError() }
        if let failure { throw QuizError(failure) }
    }
    private func receive(id: UUID) async {
        while !Task.isCancelled, token == id, let socket {
            do {
                let message = try await socket.receive()
                guard token == id else { return }
                let data: Data
                switch message { case .data(let d):data=d; case .string(let s):data=Data(s.utf8); @unknown default:continue }
                guard let json = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { continue }
                if let error = json["error"] as? [String:Any], let code = error["code"] as? String, code.count <= 60, code.range(of:"^[A-Za-z0-9_-]+$",options:.regularExpression) != nil { lastErrorCode = code }
                for event in QuizLiveProtocol.event(json,engine:engine) {
                    switch event {
                    case .ready:ready=true
                    case .audio(let bytes): receivedAudioBytes += bytes.count; if !listening { pcm?.oynat(bytes) }
                    case .transcript(let text): if listening { transcript += engine == .gemini ? text : (transcript.isEmpty ? text : " "+text) }
                    case .done:readDone=true; turnDone=true
                    case .failed(let text):failure=text
                    case .ignore:break
                    }
                }
            } catch {
                if token == id && !Task.isCancelled {
                    let status = (socket.response as? HTTPURLResponse)?.statusCode ?? 0
                    transportStatus = "http_\(status)_ws_\(socket.closeCode.rawValue)_error_\((error as NSError).code)"
                    let reason = socket.closeReason.map { String(decoding:$0,as:UTF8.self).lowercased() } ?? ""
                    closeKind = reason.contains("quota") || reason.contains("billing") || reason.contains("resource_exhausted") ? "quota" : reason.contains("model") ? "model" : "connection"
                    failure = closeKind == "quota" ? "Canlı ses hesabının kota/kredisi yetersiz. Sıralı sesli modu kullanabilirsin." : "Canlı sağlayıcı bağlantısı kurulamadı veya kesildi. Hesap ve model erişimini kontrol et."
                }; return
            }
        }
    }
    private func send(_ value: [String:Any]) async throws {
        try Task.checkCancellation()
        guard let socket else { throw QuizError("Canlı ses bağlantısı kapalı.") }
        let data = try JSONSerialization.data(withJSONObject:value)
        try await socket.send(.string(String(decoding:data,as:UTF8.self)))
    }
    func stop() {
        token = UUID(); listening = false; ready = false
        receiver?.cancel(); sender?.cancel(); receiver = nil; sender = nil
        socket?.cancel(with:.normalClosure,reason:nil); socket = nil; session?.invalidateAndCancel(); session = nil
        if let pcm { GameAudio.sessionQueue.async { pcm.durdur() } }; pcm = nil
    }
}
