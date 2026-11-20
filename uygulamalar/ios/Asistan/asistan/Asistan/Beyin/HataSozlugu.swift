import Foundation
import FoundationModels
import ClaudeForFoundationModels

/// Zincirin sonunda kalan hatanın kaba türü: durum şeridinin simgesi ve eylemleri (Yeniden dene, Bağlantıyı sına…) buna göre seçilir.
nonisolated enum HataTuru: String, Sendable {
    case yetki, kota, sunucu, baglanti, zamanAsimi, baglam, kimlik, bilinmeyen
}

/// Model/ağ hatalarını kullanıcının anlayacağı kısa Türkçe metne ve türe çevirir (`Beyin.hataMetni` buraya yönlenir).
/// `tur` ile `metin` aynı sırayı izler: LanguageModelError → ClaudeError → zaman aşımı → NSURLError → "Underlying error:"
/// (araç hatasının asıl nedeni) → açıklamada sözcük sınırlı kod/sözcük araması (401/403, 429, 5xx) → "Hata: …".
/// Kodlar sayı sınırıyla aranır: "1500 karakter" ya da "4010" yetki/kota/sunucu sayılmaz.
nonisolated enum HataSozlugu {
    static let zamanAsimiMetni = "Model zamanında yanıt vermedi (yoğunluk ya da yavaş bağlantı). Biraz sonra tekrar dene ya da başka bir model seç."
    static let yetkiMetni = "Hesap doğrulanamadı (401/403). CLI Proxy'de hesabı yeniden bağla ya da başka model dene."
    static let kotaMetni = "Model kullanım sınırında (429). Biraz sonra dene ya da başka model seç."
    static let sunucuMetni = "Sağlayıcı geçici hata verdi (5xx). Yeniden dene."
    static let vekilMetni = "Yerel vekile bağlanılamadı (-1004): uygulama içi CLIProxy sunucusu hazır değil. Bağlantıyı sına."
    static let internetYokMetni = "İnternet bağlantısı yok."
    static let baglantiMetni = "Bağlantı yok ya da sunucuya ulaşılamadı."
    static let baglamMetni = "Sohbet çok uzadı; yeni sohbet başlatın."
    static let altNedenOneki = "Underlying error: "

    /// Hatanın türü (zincir sonunda `Beyin.bitir(hata:tur:)`'a verilir).
    static func tur(_ h: any Error) -> HataTuru {
        if let m = h as? LanguageModelError {
            switch m {
            case .rateLimited: return .kota
            case .contextSizeExceeded: return .baglam
            default:
                let k = m.localizedDescription.lowercased()
                if k.contains("timed out") { return .zamanAsimi }
                return aciklamaTuru(k + " " + String(describing: m).lowercased()) ?? .bilinmeyen
            }
        }
        if h is ClaudeError { return .kimlik }
        let ns = h as NSError
        let ham = h.localizedDescription
        let kucuk = ham.lowercased()
        if ns.code == NSURLErrorTimedOut || kucuk.contains("timed out") { return .zamanAsimi }
        if ns.domain == NSURLErrorDomain { return .baglanti }
        if let r = ham.range(of: altNedenOneki) { return aciklamaTuru(String(ham[r.upperBound...]).lowercased()) ?? .bilinmeyen }
        return aciklamaTuru(kucuk + " " + String(describing: h).lowercased()) ?? .bilinmeyen
    }

    /// Kullanıcıya gösterilecek kısa metin; ham hata dökümü yerine yalnız "Hata: …" kısaltması kalır.
    /// `sonYol`: zincirde hatayı veren son adımın yolu. -1004 (yerel vekile bağlanılamadı) yalnız telefon yolunda ya da
    /// yol bilinmiyorsa (nil) vekil metnini alır; vekil/anahtar yolunda genel bağlantı metni gösterilir.
    static func metin(_ h: (any Error)?, sonYol: ModelZinciri.Yol? = nil) -> String {
        guard let h else { return "Bilinmeyen hata." }
        if let m = h as? LanguageModelError {
            switch m {
            case .rateLimited: return kotaMetni
            case .contextSizeExceeded: return baglamMetni
            default:
                let k = m.localizedDescription.lowercased()
                if k.contains("timed out") { return zamanAsimiMetni }
                if let t = aciklamaTuru(k + " " + String(describing: m).lowercased()), let s = turMetni(t) { return s }
                return "Model hatası: \(m.localizedDescription)"
            }
        }
        if h is ClaudeError { return "Claude kimlik hatası: \(h)" }
        let ns = h as NSError
        let ham = h.localizedDescription
        let kucuk = ham.lowercased()
        if ns.code == NSURLErrorTimedOut || kucuk.contains("timed out") { return zamanAsimiMetni }
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCannotConnectToHost: return sonYol == nil || sonYol == .telefon ? vekilMetni : baglantiMetni
            case NSURLErrorNotConnectedToInternet: return internetYokMetni
            default: return baglantiMetni
            }
        }
        // "An error occurred while invoking the tool: … Underlying error: X" → yalnız X (araç hatasının asıl nedeni).
        if let r = ham.range(of: altNedenOneki) { return String(ham[r.upperBound...]) }
        if let t = aciklamaTuru(kucuk + " " + String(describing: h).lowercased()), let s = turMetni(t) { return s }
        return "Hata: \(ham)"
    }

    /// Küçük harfli açıklamada sağlayıcı kodu/sözcüğü arar. Sıra `ModelZinciri.dusmeKarari` ile aynı: önce kota, sonra yetki;
    /// 5xx en sonda (`GeciciHata` sözcükleri).
    static func aciklamaTuru(_ kucuk: String) -> HataTuru? {
        func kod(_ desen: String) -> Bool { kucuk.range(of: "(?<![0-9])(\(desen))(?![0-9])", options: .regularExpression) != nil }
        func sozcuk(_ s: [String]) -> Bool { s.contains { kucuk.contains($0) } }
        if kod("429") || sozcuk(["rate limit", "ratelimit", "usage limit", "overloaded", "too many requests", "insufficient_quota", "no credits remaining"]) { return .kota }
        if kod("401|403") || sozcuk(["unauthorized", "credential", "authentication", "forbidden"]) { return .yetki }
        if kod("500|502|503|504") || sozcuk(["bad gateway", "service unavailable", "gateway timeout", "internal server error"]) { return .sunucu }
        return nil
    }

    /// Açıklama aramasıyla bulunan türlerin sabit metni.
    static func turMetni(_ t: HataTuru) -> String? {
        switch t {
        case .yetki: yetkiMetni
        case .kota: kotaMetni
        case .sunucu: sunucuMetni
        default: nil
        }
    }
}
