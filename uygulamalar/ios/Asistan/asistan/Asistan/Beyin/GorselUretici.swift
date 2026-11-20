import Foundation
import UIKit

@MainActor
enum GorselUretici {
    enum Hata: LocalizedError {
        case http(Int), goruntuYok
        var errorDescription: String? {
            switch self {
            case .http(let kod): "Görsel üretilemedi (HTTP \(kod)). Seçilen görsel modeli veya hesap kotası kullanılamıyor olabilir."
            case .goruntuYok: "Sağlayıcı geçerli bir görsel döndürmedi. Başka bir görsel modeli seç."
            }
        }
    }
    static func uret(model: String, istem: String) async throws -> UIImage {
        let proxy = TelefonProxy.ortak
        await proxy.hazirla()
        guard proxy.hazir else { throw URLError(.userAuthenticationRequired) }
        let gemini = model.hasPrefix("gemini-")
        var r = URLRequest(url: proxy.taban.appending(path: gemini ? "v1beta/models/\(model):generateContent" : "v1/images/generations"))
        r.httpMethod = "POST"; r.timeoutInterval = 240
        r.setValue("Bearer \(proxy.yerelAnahtar)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = gemini
            ? ["contents": [["role": "user", "parts": [["text": istem]]]], "generationConfig": ["responseModalities": ["TEXT", "IMAGE"]]]
            : ["model": model, "prompt": istem, "n": 1, "size": "1024x1024"]
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 240; config.timeoutIntervalForResource = 240
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (d, response) = try await session.data(for: r)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Hata.http(status) }
        let obj = try JSONSerialization.jsonObject(with: d) as? [String: Any]
        if gemini {
            for candidate in obj?["candidates"] as? [[String: Any]] ?? [] {
                let content = candidate["content"] as? [String: Any]
                for part in content?["parts"] as? [[String: Any]] ?? [] {
                    let inline = part["inlineData"] as? [String: Any] ?? part["inline_data"] as? [String: Any]
                    if let b64 = inline?["data"] as? String, let data = Data(base64Encoded: b64), let img = UIImage(data: data) {
                        try Task.checkCancellation()
                        return img
                    }
                }
            }
        }
        let ilk = (obj?["data"] as? [[String: Any]])?.first
        if let b64 = ilk?["b64_json"] as? String, let data = Data(base64Encoded: b64), let img = UIImage(data: data) {
            try Task.checkCancellation()
            return img
        }
        if let adres = ilk?["url"] as? String, let url = TelefonAdresleri.web(adres) {
            let (data, _) = try await URLSession.shared.data(from: url)
            try Task.checkCancellation()
            if let img = UIImage(data: data) { return img }
        }
        throw Hata.goruntuYok
    }
}
