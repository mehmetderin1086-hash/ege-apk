import Foundation
import FoundationModels
import ClaudeForFoundationModels

/// Hangi kimlik yoluyla gidileceğini sırayla belirler: önce iPhone CLIProxy, kullanılamıyorsa VPS veya doğrudan API.
/// Saf mantık; test edilebilir. Askı (suspend) kaydı belleğin içindedir.
nonisolated struct ModelZinciri: Sendable {
    enum Yol: String, Sendable, CaseIterable {
        case telefon, vekil, anahtar
        var ad: String {
            switch self {
            case .telefon: "iPhone CLIProxy"
            case .vekil: "CLIProxy sunucusu"
            case .anahtar: "API anahtarı"
            }
        }
    }

    struct Adim: Sendable, Equatable {
        let yol: Yol
        let model: String
    }

    /// P3.7: hatanın neyi bozduğu. `istek`: yalnız bu istek (ağ dalgası, askı yazılmaz); `modelYol`: yalnız bu model bu
    /// yolda (401/404/kota; ModelVitesi "model|yol" anahtarı); `rota`: bu yol bütün modeller için (sunucuya ulaşılamıyor).
    nonisolated enum Kapsam: Equatable, Sendable {
        case yok, istek
        case modelYol(TimeInterval)
        case rota(TimeInterval)
        var sure: TimeInterval {
            switch self {
            case .yok, .istek: 0
            case .modelYol(let s), .rota(let s): s
            }
        }
    }

    /// `gec`: sıradaki adıma geçilir mi; `hakDusmez`: deneme hakkı tüketmez (yapısal uyumsuzluk, sunucuda olmayan model).
    nonisolated struct Karar: Equatable, Sendable {
        let gec: Bool
        let kapsam: Kapsam
        var hakDusmez = false
    }

    var vekilVar: Bool
    var anahtarVar: Bool
    var yalnizAnahtar: Bool
    /// Rota askıları (bütün modeller için; Beyin.askilar, kalıcı).
    var askiBitis: [Yol: Date] = [:]
    var telefonVar: Bool = false
    /// "model|yol" anahtarlı askılar (ModelVitesi.yolAskilari): yalnız o model o yolda atlanır.
    var modelAskilari: [String: Date] = [:]
    /// BaglantiDurumu VPS'e ulaşamadı: .vekil adımı yalnız tek seçenekse kalır.
    var vekilErisilemez: Bool = false

    static func askiAnahtari(model: String, yol: Yol) -> String { "\(model)|\(yol.rawValue)" }

    /// `askiYoksay`: bütün kullanılabilir yollar (askılar ve VPS erişilemezliği yok sayılır). Çağıran, süzülmüş liste
    /// hiç adım vermezse bununla bir kez daha kurar (askı yalnız öncelik düşürür).
    func adimlar(model: String, simdi: Date = .now, askiYoksay: Bool = false) -> [Adim] {
        // Ana yol iPhone CLIProxy'dir. Bağlantı, kimlik ya da kota hatasında
        // aynı isteğin sunucu/anahtar yedeği denenebilir; çağıran yalnız araç
        // başlamamış ve kısmi yanıt oluşmamışsa bu geçişe izin verir.
        var sira: [Yol] = yalnizAnahtar ? [.anahtar] : (telefonVar ? [.telefon, .vekil, .anahtar] : [.vekil, .anahtar])
        sira = sira.filter { yol in
            switch yol {
            case .telefon: telefonVar
            case .vekil: vekilVar
            case .anahtar: anahtarVar
            }
        }
        if askiYoksay { return sira.map { Adim(yol: $0, model: model) } }
        if vekilErisilemez, sira.count > 1 { sira.removeAll { $0 == .vekil } }
        let acik = sira.filter { (askiBitis[$0] ?? .distantPast) <= simdi }
        // Rota askısı bütün modeller için aynıdır: hepsi askıdaysa yine de dene; rota askısı yalnız öncelik düşürür.
        let rotalar = acik.isEmpty ? sira : acik
        // Model|yol askısı süzülür; hiç adım kalmazsa çağıran `askiYoksay: true` ile yeniden kurar.
        return rotalar
            .filter { (modelAskilari[Self.askiAnahtari(model: model, yol: $0)] ?? .distantPast) <= simdi }
            .map { Adim(yol: $0, model: model) }
    }

    /// P4.2 saf karar: uygulama arka plandayken (bas-konuş, kilitliyken Live) iPhone CLIProxy'nin yerel loopback sunucusu
    /// askıda olabilir; `.telefon` adımları çıkarılır, sıra korunur (vekil → anahtar). Geriye adım kalmazsa girdi aynen döner.
    static func arkaPlanSuz(_ a: [Adim], arkaPlanda: Bool) -> [Adim] {
        guard arkaPlanda else { return a }
        let suzulmus = a.filter { $0.yol != .telefon }
        return suzulmus.isEmpty ? a : suzulmus
    }

    /// Uyumluluk: eski (gec, askı süresi) biçimi; telefon yolu varsayılır.
    static func dusmeKarari(_ hata: any Error) -> (gec: Bool, askiSn: TimeInterval) {
        let k = sinifla(hata, yol: .telefon)
        return (k.gec, k.kapsam.sure)
    }

    /// P3.7: hata türle sınıflanır (URLError, LanguageModelError, ClaudeError, APIError.kind Mirror'la).
    /// Metin araması yalnız türsüz hatalar içindir (ProxyKit'in Türkçe yapılandırma iletileri, eski metin biçimleri).
    static func sinifla(_ hata: any Error, yol: Yol) -> Karar {
        if hata is CancellationError { return Karar(gec: false, kapsam: .yok) }
        if let u = hata as? URLError { return urlKarari(u.code, yol: yol) }
        let ns = hata as NSError
        if ns.domain == NSURLErrorDomain { return urlKarari(URLError.Code(rawValue: ns.code), yol: yol) }
        if let l = hata as? LanguageModelError {
            switch l {
            // ErrorMapper .overloaded'ı da .rateLimited'e çevirir.
            case .rateLimited: return Karar(gec: true, kapsam: .modelYol(600))
            // ErrorMapper URLError.timedOut'u .timeout'a çevirir: ağ dalgası, yalnız bu istek.
            case .timeout: return Karar(gec: true, kapsam: .istek)
            case .contextSizeExceeded, .guardrailViolation, .refusal, .unsupportedCapability,
                 .unsupportedTranscriptContent, .unsupportedGenerationGuide, .unsupportedLanguageOrLocale:
                return Karar(gec: false, kapsam: .yok)
            @unknown default: return Karar(gec: true, kapsam: .modelYol(60))
            }
        }
        // 401 ve kimlik: yalnız bu model bu yolda (vekilin ve anahtarın kimliği ayrıdır).
        if hata is ClaudeError { return Karar(gec: true, kapsam: .modelYol(3600)) }
        if let tur = apiTuru(hata) {
            switch tur {
            case "notFound": return Karar(gec: true, kapsam: .modelYol(3600), hakDusmez: true)
            case "permission", "authentication": return Karar(gec: true, kapsam: .modelYol(3600))
            case "rateLimit", "overloaded": return Karar(gec: true, kapsam: .modelYol(600))
            case "api": return Karar(gec: true, kapsam: .modelYol(60))
            case "requestTooLarge": return Karar(gec: false, kapsam: .yok)
            case "invalidRequest":
                if yapilandirmaHatasi(apiIletisi(hata).lowercased()) { return Karar(gec: true, kapsam: .modelYol(3600), hakDusmez: true) }
                // İstek bu modele uymuyor olabilir (görsel biçimi, şema): bir kez öbür adımı dene, askı yazma.
                return Karar(gec: true, kapsam: .istek)
            default: break
            }
        }
        let aciklama = String(describing: hata).lowercased()
        // Hesap/sağlayıcı yapılandırması: bu model bu yolda hiç çalışmaz (kredi yok, araç desteği yok, sağlayıcı uyumsuz).
        if yapilandirmaHatasi(aciklama) { return Karar(gec: true, kapsam: .modelYol(3600), hakDusmez: true) }
        if aciklama.contains("ratelimit") || aciklama.contains("rate limit") || aciklama.contains("429") || aciklama.contains("usage limit") || aciklama.contains("overloaded") {
            return Karar(gec: true, kapsam: .modelYol(600))
        }
        if aciklama.contains("401") || aciklama.contains("403") || aciklama.contains("credential") || aciklama.contains("authentication") || aciklama.contains("unauthorized") {
            return Karar(gec: true, kapsam: .modelYol(3600))
        }
        if aciklama.contains("contextsizeexceeded") || aciklama.contains("guardrail") || aciklama.contains("unsupported") {
            return Karar(gec: false, kapsam: .yok)
        }
        // Bilinmeyen 5xx vb.: bir kez öbür yolu dene, bu model bu yolda kısa askı.
        return Karar(gec: true, kapsam: .modelYol(60))
    }

    private static func urlKarari(_ kod: URLError.Code, yol: Yol) -> Karar {
        switch kod {
        case .cannotConnectToHost, .secureConnectionFailed:
            // Sunucuya hiç ulaşılamıyor: bu yol bütün modeller için askıya (yerel vekil kısa, uzak sunucu uzun).
            return Karar(gec: true, kapsam: .rota(yol == .telefon ? 30 : 120))
        case .cannotFindHost, .dnsLookupFailed:
            // DNS çözümü geçici de olur (hücresel geçiş, ağ değişimi): rotayı kapatmadan yalnız bu isteği geç.
            return Karar(gec: true, kapsam: .istek)
        default:
            // notConnectedToInternet, networkConnectionLost, timedOut, dataNotAllowed ve öbürleri: yalnız bu istek.
            return Karar(gec: true, kapsam: .istek)
        }
    }

    /// `ClaudeAPI.APIError` paket erişimli: türü doğrudan eşlenemez, `kind` alanı Mirror ile okunur (ör. "notFound").
    static func apiTuru(_ hata: any Error) -> String? {
        for c in Mirror(reflecting: hata).children where c.label == "kind" { return String(describing: c.value) }
        return nil
    }

    private static func apiIletisi(_ hata: any Error) -> String {
        for c in Mirror(reflecting: hata).children where c.label == "message" { return String(describing: c.value) }
        return String(describing: hata)
    }

    /// Modelin bu hesapta/yolda yapısal olarak çalışmadığını gösteren hata (deneme hakkı tüketmemeli):
    /// simülatör vekilinde OpenAI kredisi yokken ve Gemini sağlayıcısı araç desteklemezken zincir
    /// üç denemeyi bunlara harcayıp Claude'a hiç ulaşmadan hata veriyordu (20 Eki 2026).
    static func yapilandirmaHatasi(_ aciklamaKucuk: String) -> Bool {
        let a = aciklamaKucuk
        return a.contains("yeteneğini desteklemiyor") || a.contains("does not support tools") || a.contains("tools are not supported")
            || a.contains("no credits remaining") || a.contains("insufficient_quota") || a.contains("kullanılabilir hesap yok")
            || a.contains("require the matching provider")
    }
}
