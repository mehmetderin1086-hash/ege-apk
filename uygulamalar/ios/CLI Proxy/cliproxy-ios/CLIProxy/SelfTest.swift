import Foundation
import UIKit
import ProxyKit

/// `--oz-sinama` açılış argümanıyla çalışır: gerçek soket üzerinden kendi sunucusuna
/// istek atar ve sonucu Belgeler/oz-sinama.json'a yazar (Mac'ten devicectl ile okunur).
enum SelfTest {
    @MainActor
    static func run(_ model: AppModel) async {
        // Ekran kapalıyken (Mac'ten devicectl ile başlatılınca) iOS uygulamayı hemen askıya alır: sınama boyunca uyanık kal.
        let bg = UIApplication.shared.beginBackgroundTask(withName: "oz-sinama")
        model.keepAlive.start()
        defer {
            if !model.keepAwakeInBackground { model.keepAlive.stop() }
            UIApplication.shared.endBackgroundTask(bg)
        }
        for _ in 0..<50 { if model.isRunning { break }; try? await Task.sleep(for: .milliseconds(100)) }
        var results: [JSON] = []
        let key = model.state.localKey
        let base = "http://127.0.0.1:\(model.port)"
        let cases: [(String, String, String?)] = [
            ("modeller", "/v1/models", nil),
            ("claude-openai", "/v1/chat/completions", #"{"model":"claude-haiku-4-5","max_tokens":20,"messages":[{"role":"user","content":"Sadece 'tamam' yaz."}]}"#),
            ("claude-anthropic-akis", "/v1/messages", #"{"model":"claude-sonnet-5-5","max_tokens":30,"stream":true,"messages":[{"role":"user","content":"1, 2, 3 diye say."}]}"#),
            ("codex", "/v1/messages", #"{"model":"gpt-6-astra","max_tokens":30,"messages":[{"role":"user","content":"Sadece 'evet' yaz."}]}"#),
            ("antigravity", "/v1/messages", #"{"model":"antigravity-claude-opus-5-5","max_tokens":20,"messages":[{"role":"user","content":"Sadece 'tamam' yaz."}]}"#),
            ("gemini-kredi-ikamesi", "/v1/messages", #"{"model":"dersdas-gemini-ocr","max_tokens":20,"messages":[{"role":"user","content":"Sadece 'hazır' yaz."}]}"#),
            ("sunucu-modeli", "/v1/chat/completions", #"{"model":"gemini-4-argon-low","max_tokens":20,"messages":[{"role":"user","content":"Sadece 'ok' yaz."}]}"#),
        ]
        await model.syncNow(silent: true)
        results.append(["ad": "esitleme", "tamam": .bool(model.lastSync != nil)])
        for (name, path, body) in cases {
            var r = URLRequest(url: URL(string: base + path)!)
            r.httpMethod = body == nil ? "GET" : "POST"
            r.timeoutInterval = 120
            r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = body.map { Data($0.utf8) }
            let t0 = Date()
            do {
                let (d, resp) = try await URLSession.shared.data(for: r)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let route = await model.log.records.first?.route ?? "-"
                results.append(["ad": .string(name), "durum": .int(status), "ms": .int(Int(Date().timeIntervalSince(t0) * 1000)),
                                "yol": .string(route), "ozet": .string(String(decoding: d.prefix(240), as: UTF8.self))])
            } catch {
                results.append(["ad": .string(name), "hata": .string(error.localizedDescription)])
            }
        }
        let s = model.state
        let out: JSON = ["zaman": .string(ISO8601DateFormatter().string(from: Date())),
                         "sunucu": .string("\(model.serverState)"),
                         "hesaplar": .array(s.oauth.map { ["saglayici": .string($0.provider.rawValue), "etiket": .string($0.label), "etkin": .bool($0.enabled),
                                                           "sahip": .string($0.refreshOwner.rawValue), "bitis": .str($0.expiresAt.map { ISO8601DateFormatter().string(from: $0) })] }),
                         "api": .array(s.apiProviders.map { .string($0.name) }),
                         "istemci_anahtari": .int(s.clientKeys.count), "kural": .int(s.routing.count),
                         "uzak": .bool(s.remote.isUsable), "sonuclar": .array(results)]
        try? out.data().write(to: AppModel.documents.appendingPathComponent("oz-sinama.json"))
    }
}
