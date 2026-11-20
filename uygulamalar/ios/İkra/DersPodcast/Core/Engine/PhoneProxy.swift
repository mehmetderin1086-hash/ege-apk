import Foundation
import ProxyKit
#if DEBUG
import UIKit
#endif

/// Telefondaki CLI Proxy hesapları (17 Eki 2026).
///
/// CLI Proxy uygulaması sunucudaki vekilin bütün hesaplarını (Claude, ChatGPT/Codex, OpenAI ve Gemini anahtarları) telefona
/// taşır ve ortak Keychain kasasında tutar. İkra aynı kasayı okur: motorun vekile (`/dersdas/claude/v1`) giden model istekleri
/// ağa çıkmadan burada, ProxyKit ile karşılanır. CLI Proxy uygulamasının açık olması gerekmez.
/// - Sunucuya özel modeller (Antigravity, Gemini Pro hesabı, Qwen, görsel üretim) ve telefonda hata veren istekler ProxyKit
///   içinden yine VPS'e gider; math/ders/kaynak gibi öbür sunucu yolları hiç buraya gelmez.
/// - Kasa boşsa ya da ayar kapalıysa `localPath` nil döner ve istek eskisi gibi VPS'e gider.
nonisolated enum PhoneProxy {
    static let enabledKey = "ikra.phoneProxy"
    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    static let store = KeychainSecretStore(accessGroup: KeychainSecretStore.sharedGroup)

    static let engine: ProxyEngine = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return ProxyEngine(vault: Vault(store: store), log: UsageLog(file: support.appendingPathComponent("cliproxy-kullanim.json"), limit: 300))
    }()

    /// Vekil yolunun telefonda karşılanan parçaları (sunucudaki CLI Proxy API'nin model uçları).
    static let handled: Set<String> = ["/messages", "/messages/count_tokens", "/chat/completions", "/responses", "/models",
                                       "/audio/speech", "/embeddings"]

    /// Kasadaki durum (kısa süre önbellekte; her istekte Keychain okunmasın).
    private static let cache = Cache()

    /// Vekil adresindeki istek telefonda karşılanacaksa ProxyKit yolu (`/v1/…`); değilse nil.
    static func localPath(for url: URL, proxy: URL) -> String? {
        guard enabled else { return nil }
        let base = proxy.path().hasSuffix("/") ? String(proxy.path().dropLast()) : proxy.path()
        let path = url.path()
        guard path.hasPrefix(base) else { return nil }
        let rel = String(path.dropFirst(base.count))
        guard handled.contains(rel), cache.usable() else { return nil }
        return "/v1" + rel
    }

    /// Kasada açık hesap var mı ve özeti (Ayarlar'da gösterilir).
    static func summary() -> (usable: Bool, text: String) {
        guard let s = cache.state() else { return (false, "CLI Proxy uygulamasında hesap yok") }
        let oauth = s.oauth.filter(\.enabled).count   // Claude, ChatGPT, Antigravity
        let keys = s.apiProviders.filter(\.enabled).count
        return (s.hasUsableAccounts, "\(oauth) abonelik hesabı, \(keys) API sağlayıcısı" + (s.remote.isUsable ? " · sunucu yedeği açık" : ""))
    }

    static func handle(method: String, path: String, headers: [String: String], body: Data) async -> (status: Int, headers: [String: String], body: Data) {
        let state = await engine.vault.reload()
        var h: [String: String] = [:]
        for (k, v) in headers where !["x-api-key", "x-personal-token", "authorization"].contains(k.lowercased()) { h[k.lowercased()] = v }
        h["authorization"] = "Bearer \(state.localKey)"
        let reply = await engine.handle(ProxyRequest(method: method, path: path, headers: h, body: body))
        var data = Data()
        do {
            for try await chunk in reply.body { data.append(chunk) }
        } catch {
            if data.isEmpty {
                let msg = #"{"error":{"message":"Telefondaki vekil yanıtı yarıda kesildi: \#(error.localizedDescription)","type":"upstream_error"}}"#
                return (502, ["content-type": "application/json"], Data(msg.utf8))
            }
        }
        var out: [String: String] = [:]
        for (k, v) in reply.headers { out[k.lowercased()] = v }
        if let quota = await quotaHeaders(for: body) { out.merge(quota) { $1 } }
        return (reply.status, out, data)
    }

    /// Telefondaki vekil kotayı upstream başlıklarından bilir (`KotaDurumu`); motorun hesaplar arası devri için yanıta yazılır:
    /// `x-proxy-quota-used` (0…1) ve `x-proxy-quota-reset` (sn). Aynı sağlayıcının en boş hesabı sayılır: biri doluyken öbürü
    /// kullanılabiliyorsa devir gerekmez (vekil hesaplar arasında kendisi döner).
    private static func quotaHeaders(for body: Data) async -> [String: String]? {
        guard let model = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["model"] as? String else { return nil }
        let prefix: String
        if model.hasPrefix("claude-") { prefix = "claude:" }
        else if model.hasPrefix("gpt-") || model.hasPrefix("o1-") || model.hasPrefix("o3-") { prefix = "codex:" }
        else if model.hasPrefix("antigravity-") { prefix = "antigravity:" }
        else { return nil }
        let accounts = await engine.kota.hesaplar.filter { $0.key.hasPrefix(prefix) }
        var best: (used: Double, reset: Double)?
        for key in accounts.keys {
            guard let used = await engine.kota.doluluk(key) else { return nil } // doluluğu bilinmeyen hesap varsa devir yapma
            let reset = accounts[key]?.sifirlanma.map { max(0, $0.timeIntervalSinceNow) } ?? 0
            if best == nil || used < best!.used { best = (used, reset) }
        }
        guard let best else { return nil }
        return ["x-proxy-quota-used": String(format: "%.3f", best.used), "x-proxy-quota-reset": String(Int(best.reset))]
    }

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var value: ProxyState?
        private var at = Date.distantPast

        func state() -> ProxyState? {
            lock.withLock {
                if Date().timeIntervalSince(at) > 5 {
                    value = (try? PhoneProxy.store.load()).flatMap { ProxyState.decode($0) }
                    at = Date()
                }
                return value
            }
        }
        func usable() -> Bool { state()?.hasUsableAccounts ?? false }
    }

    #if DEBUG
    /// Motorun vekil adresiyle aynı yönlendirme kararını ve süreç içi çağrıyı dener; sonucu Belgeler/cliproxy-sinama.json'a yazar.
    static func selfTest() async {
        // Ekran kapalıyken başlatılınca iOS uygulamayı askıya almasın diye arka plan süresi istenir (~30 sn yeter).
        let bg = await MainActor.run { UIApplication.shared.beginBackgroundTask(withName: "cliproxy-sinama") }
        defer { Task { @MainActor in UIApplication.shared.endBackgroundTask(bg) } }
        var out: [String: Any] = ["zaman": ISO8601DateFormatter().string(from: Date()), "ozet": summary().text]
        guard let proxy = Backend.claudeProxyURL else {
            out["hata"] = "vekil adresi yok"
            write(out); return
        }
        out["vekil"] = proxy.absoluteString
        var results: [[String: Any]] = []
        for (name, rel, body) in [
            ("claude", "/messages", #"{"model":"claude-haiku-4-5","max_tokens":20,"messages":[{"role":"user","content":"Sadece 'tamam' yaz."}]}"#),
            ("modeller", "/models", ""),
            ("antigravity", "/messages", #"{"model":"antigravity-claude-opus-5-5","max_tokens":20,"messages":[{"role":"user","content":"Sadece 'tamam' yaz."}]}"#),
            ("gemini-kredi-ikamesi", "/messages", #"{"model":"dersdas-gemini-ocr","max_tokens":20,"messages":[{"role":"user","content":"Sadece 'hazır' yaz."}]}"#),
            ("sunucu-modeli", "/chat/completions", #"{"model":"gemini-4-argon-low","max_tokens":20,"messages":[{"role":"user","content":"Sadece 'ok' yaz."}]}"#),
            ("math-yolu", "/math/health", ""),
        ] {
            let url = proxy.appendingPathComponent(String(rel.dropFirst()))
            let local = localPath(for: url, proxy: proxy)
            var r: [String: Any] = ["ad": name, "telefonda": local != nil]
            if let local {
                let t0 = Date()
                let reply = await handle(method: body.isEmpty ? "GET" : "POST", path: local, headers: ["content-type": "application/json"], body: Data(body.utf8))
                r["durum"] = reply.status
                r["ms"] = Int(Date().timeIntervalSince(t0) * 1000)
                r["yol"] = await engine.log.records.first?.route ?? "-"
                r["yanit"] = String(decoding: reply.body.prefix(160), as: UTF8.self)
            }
            results.append(r)
        }
        out["sonuclar"] = results
        write(out)
    }

    private static func write(_ out: [String: Any]) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("cliproxy-sinama.json")
        if let d = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted]) { try? d.write(to: url) }
    }
    #endif
}
