import Foundation
import Security

enum VoiceEngine: String, CaseIterable, Identifiable {
    case auto, chirp, azure, apple
    var id: String { rawValue }
    var title: String { switch self { case .auto: "Otomatik"; case .chirp: "Google Chirp"; case .azure: "Azure"; case .apple: "Cihaz sesi" } }
}

struct AudioClip: Equatable { var data: Data; var fileExtension: String }

enum TTSError: LocalizedError {
    case notConfigured(String), server(String), badAudio
    var errorDescription: String? {
        switch self {
        case .notConfigured(let what): "\(what) ayarlı değil."
        case .server(let message): message
        case .badAudio: "Ses yanıtı okunamadı."
        }
    }
}

/// Ses sunucusu ve kullanıcı ayarları (anahtar Info.plist'ten, Azure anahtarı Anahtar Zinciri'nden).
enum VoiceConfig {
    static var serverHost: String? { (Bundle.main.object(forInfoDictionaryKey: "VoiceServerHost") as? String).flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : $0 } }
    static var serverToken: String? { (Bundle.main.object(forInfoDictionaryKey: "VoiceServerToken") as? String).flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : $0 } }
    static var serverConfigured: Bool { serverHost != nil && serverToken != nil }
    static var installID: String {
        if let id = UserDefaults.standard.string(forKey: "voice.installID") { return id }
        let id = UUID().uuidString.lowercased(); UserDefaults.standard.set(id, forKey: "voice.installID"); return id
    }
    static var engine: VoiceEngine { VoiceEngine(rawValue: UserDefaults.standard.string(forKey: "voice.engine") ?? "") ?? .auto }
    static var chirpVoice: String { UserDefaults.standard.string(forKey: "voice.chirp") ?? "Kore" }
    static var azureVoice: String { UserDefaults.standard.string(forKey: "voice.azure") ?? "tr-TR-EmelNeural" }
    static var azureRegion: String { UserDefaults.standard.string(forKey: "voice.azureRegion") ?? "westeurope" }
    static var rate: Double { let v = UserDefaults.standard.double(forKey: "voice.rate"); return v == 0 ? 1.0 : v }
    static var azureKey: String? { get { Keychain.read("azure.speech.key") } set { Keychain.write("azure.speech.key", newValue) } }
    static var azureConfigured: Bool { !(azureKey ?? "").isEmpty }
    static let chirpVoices = ["Kore", "Puck", "Zephyr", "Charon", "Leda", "Aoede", "Fenrir", "Orus", "Callirrhoe", "Sulafat"]
    static let azureVoices = [("tr-TR-EmelNeural", "Emel (kadın)"), ("tr-TR-AhmetNeural", "Ahmet (erkek)")]
}

enum Keychain {
    static func read(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "iett.voice", kSecAttrAccount as String: account, kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func write(_ account: String, _ value: String?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "iett.voice", kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = base; add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }
}

protocol TTSProvider { var name: String { get }; func synthesize(_ text: String) async throws -> AudioClip }

/// Kişisel sunucunun Chirp (Google Chirp 3 HD) ucu: `/v1/speak`. Geçici "ses yanıtı okunamadı" hatasında bir kez yeniden dener.
struct ChirpTTS: TTSProvider {
    var host: String, token: String, voice: String, rate: Double = 1.0
    var session: URLSession = .shared
    var name: String { "Chirp · \(voice)" }

    func request(for text: String) throws -> URLRequest {
        guard let url = URL(string: "https://\(host)/dersdas/v1/speak") else { throw TTSError.notConfigured("Ses sunucusu") }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-Personal-Token")
        request.setValue(VoiceConfig.installID, forHTTPHeaderField: "X-Install-Id")
        let pace = rate >= 1.15 ? "hizli" : rate <= 0.85 ? "yavas" : "normal"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["engine": "chirp", "voice": voice, "pace": pace, "text": text])
        return request
    }
    func synthesize(_ text: String) async throws -> AudioClip {
        var failure: TTSError = .badAudio
        for attempt in 0..<2 {
            let (data, response) = try await session.data(for: try request(for: text))
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if let audio = json?["audio"] as? String, let wav = Data(base64Encoded: audio), wav.count > 100 { return AudioClip(data: wav, fileExtension: "wav") }
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            failure = .server(message)
            // Yalnızca geçici sağlayıcı hatası ("ses yanıtı okunamadı") bir kez yeniden denenir; öbür hatalar hemen döner.
            guard attempt == 0, message.contains("okunamad") else { break }
        }
        throw failure
    }
}

/// Azure Konuşma Servisi (REST): Türkçe sinirsel sesler. Anahtar ve bölge kullanıcıdan (Ayarlar › Ses) gelir.
struct AzureTTS: TTSProvider {
    var key: String, region: String, voice: String, rate: Double = 1.0
    var session: URLSession = .shared
    var name: String { "Azure · \(voice.replacingOccurrences(of: "tr-TR-", with: "").replacingOccurrences(of: "Neural", with: ""))" }

    func request(for text: String) throws -> URLRequest {
        guard let url = URL(string: "https://\(region).tts.speech.microsoft.com/cognitiveservices/v1") else { throw TTSError.notConfigured("Azure bölgesi") }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue("audio-24khz-48kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
        request.setValue("OtobusAsistani", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(SpeechText.ssml(text: text, voice: voice, rate: rate).utf8)
        return request
    }
    func synthesize(_ text: String) async throws -> AudioClip {
        let (data, response) = try await session.data(for: try request(for: text))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw TTSError.server(status == 401 || status == 403 ? "Azure anahtarı ya da bölgesi geçersiz." : "Azure ses hatası (HTTP \(status)).")
        }
        guard data.count > 100 else { throw TTSError.badAudio }
        return AudioClip(data: data, fileExtension: "mp3")
    }
}

/// Hangi motorlar hangi sırayla denenir. Otomatik: Azure (anahtar varsa) → Chirp (sunucu varsa) → cihaz sesi. Seçilen motor yoksa sıradakine düşer; cihaz sesi hep son çaredir.
enum VoiceRouter {
    static func order(_ engine: VoiceEngine, azureConfigured: Bool, serverConfigured: Bool) -> [VoiceEngine] {
        var list: [VoiceEngine]
        switch engine {
        case .auto: list = [.azure, .chirp, .apple]
        case .azure: list = [.azure, .chirp, .apple]
        case .chirp: list = [.chirp, .azure, .apple]
        case .apple: list = [.apple]
        }
        return list.filter { $0 == .apple || ($0 == .azure && azureConfigured) || ($0 == .chirp && serverConfigured) }
    }
}
