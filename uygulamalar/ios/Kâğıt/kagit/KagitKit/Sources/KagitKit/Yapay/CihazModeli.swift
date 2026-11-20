import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence (Foundation Models) ile cihaz içi üretim. Cihaz desteklemiyorsa `kullanilabilir` false olur.
public struct CihazModeli: YapayKaynak {
    public init() {}

    public var etiket: String { "Cihaz" }
    /// Cihaz modelinin bağlamı küçüktür (~4K belirteç).
    public var baglamSiniri: Int { 4_500 }

    /// Model hazır ve Türkçeyi destekliyor mu.
    public static var kullanilabilir: Bool {
        #if canImport(FoundationModels)
        let m = SystemLanguageModel.default
        return m.availability == .available && m.supportsLocale(Locale(identifier: "tr_TR"))
        #else
        return false
        #endif
    }

    public func yanit(_ istek: YapayIstek, akis: YapayAkisi?) async throws -> YapayYaniti {
        #if canImport(FoundationModels)
        guard Self.kullanilabilir else { throw KagitHata.yapayZeka("Bu cihazda Apple Intelligence kullanılamıyor.") }
        let oturum = LanguageModelSession(instructions: istek.sistem.isEmpty ? "Türkçe yanıt ver." : istek.sistem)
        let istem = istek.mesajlar.map { m in
            m.rol == .kullanici ? m.icerik : "Önceki yanıtın: \(m.icerik)"
        }.joined(separator: "\n\n")
        var secenek = GenerationOptions()
        if let s = istek.sicaklik { secenek.temperature = s }
        let r = try await oturum.respond(to: istem, options: secenek)
        akis?(r.content)
        return YapayYaniti(metin: r.content, model: "Apple Intelligence", kaynakEtiketi: "Cihaz")
        #else
        throw KagitHata.yapayZeka("Bu cihazda Apple Intelligence kullanılamıyor.")
        #endif
    }
}
