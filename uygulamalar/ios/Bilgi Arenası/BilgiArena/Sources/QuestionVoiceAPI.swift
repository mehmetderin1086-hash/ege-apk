import Foundation
import CryptoKit
import Security
import SwiftUI
import ProxyKit

// Question voices are separate from game alerts and microphone transcription.
enum QuestionVoiceEngine: String, CaseIterable, Identifiable {
    case chirp, azure, proxy, apple
    var id: String { rawValue }
    var title: String { switch self { case .chirp: return "Google Chirp 3 HD"; case .azure: return "Azure HD"; case .proxy: return "CLI Proxy · ses modeli"; case .apple: return "iPhone · çevrimdışı" } }
}
struct QuestionVoiceConfiguration: Codable {
    var azureKey = ""
    var azureRegion = ""
    var googleProject = ""
    var googleAccount = ""
    static let service = "com.mehmetderin.bilgiarena.question-voices"
    static func load() -> Self {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"providers",kSecReturnData as String:true]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary,&value) == errSecSuccess, let data = value as? Data else { return .init() }
        return (try? JSONDecoder().decode(Self.self,from:data)) ?? .init()
    }
    func save() throws {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:Self.service,kSecAttrAccount as String:"providers"]
        let data = try JSONEncoder().encode(self)
        let updated = SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if updated == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(add as CFDictionary,nil) == errSecSuccess else { throw QuizError("Ses bağlantısı güvenli kaydedilemedi.") }; return
        }
        guard updated == errSecSuccess else { throw QuizError("Ses bağlantısı güvenli kaydedilemedi.") }
    }
}
struct QuestionVoiceChoice: Equatable {
    let engine: QuestionVoiceEngine
    let voice: String
    let model: String
    static func current(language: String) -> Self {
        let d = UserDefaults.standard
        let localTest = ProcessInfo.processInfo.arguments.contains("--ui-test-new-round") || ProcessInfo.processInfo.environment["BILGI_PHONE_AUDIT"] == "activities"
        let engine = localTest ? QuestionVoiceEngine.apple : QuestionVoiceEngine(rawValue:d.string(forKey:"questionVoiceEngine") ?? "") ?? .chirp
        return .init(engine:engine,voice:d.string(forKey:engine == .azure ? "questionAzureVoice" : engine == .proxy ? "questionProxyVoice" : "questionChirpVoice") ?? (engine == .azure ? "Elif" : engine == .proxy ? "marin" : "Kore"),model:d.string(forKey:"questionVoiceModel") ?? "gpt-4o-mini-tts")
    }
}
actor QuestionVoiceAPI {
    static let shared = QuestionVoiceAPI()
    static let chirpVoices = ["Kore","Puck","Zephyr","Charon","Leda","Aoede","Fenrir","Orus","Callirrhoe","Autonoe","Enceladus","Iapetus","Umbriel","Algieba","Despina","Erinome","Algenib","Rasalgethi","Laomedeia","Achernar","Alnilam","Schedar","Gacrux","Pulcherrima","Achird","Zubenelgenubi","Vindemiatrix","Sadachbia","Sadaltager","Sulafat"]
    static let openAIVoices = ["marin","cedar","alloy","ash","ballad","coral","echo","fable","nova","onyx","sage","shimmer","verse"]
    private let transport: any HTTPTransport
    private let gateway: PhoneGateway
    private let configuration: @Sendable () -> QuestionVoiceConfiguration
    private let folder: URL
    init(transport: any HTTPTransport = PhoneTransport(), gateway: PhoneGateway = .shared, folder: URL? = nil, configuration: @escaping @Sendable () -> QuestionVoiceConfiguration = { .load() }) {
        self.transport = transport; self.gateway = gateway; self.configuration = configuration
        self.folder = folder ?? Self.cacheFolder
    }
    static func azureVoice(_ alias: String, language: String) -> String {
        if language.hasPrefix("tr") { return alias == "Aydın" ? "tr-TR-Aydın:MAI-Voice-2-Flash" : "tr-TR-Elif:MAI-Voice-2-Flash" }
        if language.hasPrefix("en") { return alias == "Aydın" ? "en-US-AndrewMultilingualNeural" : "en-US-AvaMultilingualNeural" }
        return ["de-DE":"de-DE-KatjaNeural","fr-FR":"fr-FR-DeniseNeural","es-ES":"es-ES-ElviraNeural","ar-SA":"ar-SA-ZariyahNeural"][language] ?? "en-US-AvaMultilingualNeural"
    }
    static func xml(_ text: String) -> String { text.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;").replacingOccurrences(of:"'",with:"&apos;") }
    static func azureRequest(text: String, language: String, choice: QuestionVoiceChoice, config: QuestionVoiceConfiguration) throws -> URLRequest {
        guard !config.azureKey.isEmpty, config.azureRegion.range(of:"^[a-z0-9-]{2,40}$",options:.regularExpression) != nil else { throw QuizError("Azure Speech bağlantısı ayarlı değil. Soru sesi ayarlarını kontrol et.") }
        var r = URLRequest(url:URL(string:"https://\(config.azureRegion).tts.speech.microsoft.com/cognitiveservices/v1")!,timeoutInterval:40)
        r.httpMethod = "POST"; r.setValue(config.azureKey,forHTTPHeaderField:"Ocp-Apim-Subscription-Key"); r.setValue("application/ssml+xml",forHTTPHeaderField:"Content-Type")
        r.setValue("audio-24khz-48kbitrate-mono-mp3",forHTTPHeaderField:"X-Microsoft-OutputFormat")
        r.httpBody = Data("<speak version=\"1.0\" xmlns=\"http://www.w3.org/2001/10/synthesis\" xml:lang=\"\(xml(language))\"><voice name=\"\(xml(azureVoice(choice.voice,language:language)))\">\(xml(text))</voice></speak>".utf8)
        return r
    }
    static func chirpBody(text: String, language: String, voice: String) throws -> Data {
        guard chirpVoices.contains(voice) else { throw QuizError("Chirp sesi desteklenmiyor.") }
        let code = language == "ar-SA" ? "ar-XA" : language
        return try JSONSerialization.data(withJSONObject:["input":["text":text],"voice":["languageCode":code,"name":code+"-Chirp3-HD-"+voice],"audioConfig":["audioEncoding":"MP3"]])
    }
    func audio(text: String, language: String, choice: QuestionVoiceChoice) async throws -> URL {
        guard !text.isEmpty, text.count <= 1200, ["tr-TR","en-US","de-DE","fr-FR","es-ES","ar-SA"].contains(language) else { throw QuizError("Soru sesi metni veya dili desteklenmiyor.") }
        let key = SHA256.hash(data:Data(("v1|"+choice.engine.rawValue+"|"+choice.voice+"|"+choice.model+"|"+language+"|"+text).utf8)).map { String(format:"%02x",$0) }.joined()
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let file = folder.appendingPathComponent(key+".audio")
        if let data = try? Data(contentsOf:file), Self.validAudio(data) { return file }
        let data: Data
        let config = configuration()
        switch choice.engine {
        case .apple: throw QuizError("iPhone sesi yerel konuşma motorunu kullanır.")
        case .proxy: data = try await gateway.speech(model:choice.model,voice:choice.voice,text:text,language:language)
        case .azure:
            let response = try await transport.send(Self.azureRequest(text:text,language:language,choice:choice,config:config))
            guard response.status == 200 else { throw Self.failure("Azure",response.status) }
            data = try await response.collect(limit:12_000_000)
        case .chirp:
            guard !config.googleProject.isEmpty else { throw QuizError("Google Cloud ses projesi ayarlı değil. Soru sesi bağlantısını kontrol et.") }
            let token = try await gateway.googleSpeechToken(account:config.googleAccount)
            var r = URLRequest(url:URL(string:"https://texttospeech.googleapis.com/v1/text:synthesize")!,timeoutInterval:45)
            r.httpMethod = "POST"; r.setValue("Bearer "+token,forHTTPHeaderField:"Authorization"); r.setValue(config.googleProject,forHTTPHeaderField:"x-goog-user-project"); r.setValue("application/json",forHTTPHeaderField:"Content-Type")
            r.httpBody = try Self.chirpBody(text:text,language:language,voice:choice.voice)
            let response = try await transport.send(r)
            guard response.status == 200 else { throw Self.failure("Google Chirp",response.status) }
            let raw = try await response.collect(limit:16_000_000)
            guard let body = try JSONSerialization.jsonObject(with:raw) as? [String:Any], let base64 = body["audioContent"] as? String, let audio = Data(base64Encoded:base64) else { throw QuizError("Google ses yanıtı okunamadı.") }; data = audio
        }
        try Task.checkCancellation()
        guard Self.validAudio(data) else { throw QuizError("Sağlayıcı geçerli bir ses dosyası döndürmedi.") }
        try data.write(to:file,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        // Bound only our own generated cache; a current audio is never evicted here.
        let files = (try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.contentModificationDateKey,.fileSizeKey])) ?? []
        var bytes = files.reduce(0) { $0+((try? $1.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0) }
        for old in files.sorted(by:{ ((try? $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }) where bytes > 100_000_000 && old != file {
            bytes -= (try? old.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0; try? FileManager.default.removeItem(at:old)
        }
        return file
    }
    static var cacheFolder: URL { FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("QuestionAudio") }
    static func cacheBytes(in folder: URL = cacheFolder) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.fileSizeKey])) ?? []
        return files.reduce(0) { $0+((try? $1.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0) }
    }
    /// Yalnız uygulamanın ürettiği soru seslerini siler; sonraki dinlemede sağlayıcıdan yeniden alınır.
    static func clearCache(in folder: URL = cacheFolder) { try? FileManager.default.removeItem(at:folder) }
    static func validAudio(_ data: Data) -> Bool {
        guard data.count > 100 else { return false }
        return data.starts(with:Data("RIFF".utf8)) || data.starts(with:Data("ID3".utf8)) || (data[0] == 0xff && data[1] & 0xe0 == 0xe0) || (data.count > 12 && String(decoding:data[4..<8],as:UTF8.self) == "ftyp")
    }
    private static func failure(_ label: String,_ status: Int) -> QuizError { QuizError(status == 429 ? "\(label) kotası dolu. Başka soru sesi seç veya sonra dene." : "\(label) sesi alınamadı (HTTP \(status)). Bağlantı yetkisini kontrol et.") }
}
