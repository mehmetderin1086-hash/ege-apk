import Foundation

/// Hermes/OpenClaw tarzı sohbet komutları. Modele gitmez; uygulama yerelde yanıtlar.
nonisolated enum SlashKomut: Equatable, Sendable {
    case yeni, sikistir, model(String), beceriler, mcp, gecmis(String), kimlik, gunluk, nabiz, plan, durum, tani, yardim, bilinmeyen(String)
}

nonisolated enum SlashKomutlari {
    /// "/yeni", "/model gpt", "/gecmis ankara bütçe" gibi; dosya yolu ("/Users/x") ya da düz metin için nil.
    static func coz(_ metin: String) -> SlashKomut? {
        let t = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("/"), t.count > 1 else { return nil }
        let parcalar = t.dropFirst().split(maxSplits: 1, whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let ilk = parcalar.first else { return nil }
        let ad = AtolyeYonlendirme.normalize(ilk)
        guard !ad.isEmpty, ad.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "?" }) else { return nil }
        let arg = parcalar.count > 1 ? parcalar[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        switch ad {
        case "yeni", "new": return .yeni
        case "sikistir", "compact": return .sikistir
        case "model": return .model(arg)
        case "beceriler", "skills": return .beceriler
        case "mcp": return .mcp
        case "gecmis", "ara", "search": return .gecmis(arg)
        case "kimlik", "soul", "calismaalani": return .kimlik
        case "gunluk": return .gunluk
        case "nabiz", "heartbeat": return .nabiz
        case "plan": return .plan
        case "durum", "status": return .durum
        case "tani", "tanı", "diag": return .tani
        case "yardim", "help", "?": return .yardim
        default: return .bilinmeyen(ad)
        }
    }

    static let yardimMetni = """
    Komutlar:
    /yeni — yeni sohbet
    /sikistir — sohbet bağlamını özetleyip hafiflet
    /model — model durumu; /model otomatik; /model <ad> ile elle seç
    /durum — model, bağlam, beceri, MCP ve nabız özeti
    /beceriler — kayıtlı beceriler
    /gecmis <sözcük> — eski sohbetlerde ara
    /kimlik — SOUL/USER/AGENTS dosyaları
    /gunluk — son günlük notlar
    /plan — yapılacaklar listesi
    /mcp — bağlı MCP sunucuları
    /nabiz — nabız kontrolünü şimdi çalıştır
    /tani — maskeli tanı paketini (.zip) hazırlar
    """
}
