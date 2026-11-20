#if DEBUG
import Foundation
import FoundationModels
import ClaudeForFoundationModels

/// P3.10: sahte sunucunun Anthropic akışını uygulamanın kullandığı istemciyle (ClaudeForFoundationModels) okur.
/// Birim testi paketi paket modülünü doğrudan içe aktarmak zorunda kalmasın diye uygulama modülünde durur. Yalnız DEBUG.
enum SahteModelSinama {
    /// `taban` üzerinden `streamResponse` ile tam metni döndürür (araçsız, kısa talimatlı oturum).
    static func claudeAkisi(taban: URL, model: String = "claude-sonnet-5-5", istem: String) async throws -> String {
        let m = ClaudeLanguageModel(name: ClaudeModel.sabit(model),
                                    auth: .proxied(headers: ["Authorization": "Bearer sahte"]),
                                    baseURL: taban, timeout: 20)
        let oturum = LanguageModelSession(model: m, tools: [], instructions: "Kısa yanıtla.")
        var son = ""
        for try await parca in oturum.streamResponse(to: istem) { son = parca.content }
        return son
    }
}
#endif
