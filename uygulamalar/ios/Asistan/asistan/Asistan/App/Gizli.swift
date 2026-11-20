import Foundation
import Security
import ProxyKit

/// Kimlikler yalnız Keychain'den okunur; uygulama paketine gömülmez.
nonisolated enum Gizli {
    private static var ortakDurum: ProxyState? {
        guard let veri = try? KeychainSecretStore(accessGroup: KeychainSecretStore.sharedGroup).load() else { return nil }
        return ProxyState.decode(veri)
    }
    static var claudeAnahtari: String? {
        #if DEBUG
        // P3.10 hermetik kip: zincir yalnız `.telefon` (sahte sunucu) yolunu dener; Anthropic'e düşüş olmaz.
        if SahteModelSunucusu.etkin { return nil }
        #endif
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                               kSecAttrService as String: "com.mehmetderin.asistan",
                               kSecAttrAccount as String: "claude-api",
                               kSecReturnData as String: true,
                               kSecMatchLimit as String: kSecMatchLimitOne]
        var veri: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &veri) == errSecSuccess, let data = veri as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static var vekilToken: String? {
        #if DEBUG
        if SahteModelSunucusu.etkin { return nil }   // P3.10: hermetik kipte VPS'e düşüş yok
        #endif
        guard let durum = ortakDurum, durum.remote.isUsable else { return nil }
        return durum.remote.personalToken
    }
    /// Vekil kökü, "/v1" OLMADAN: bütün tüketiciler (ClaudeForFoundationModels "v1/messages", Whisper "v1/whisper/…",
    /// SunucuGorevleri) kendi "v1/…" yolunu ekler. CLI Proxy uygulaması ortak durumu "…/claude/v1" olarak yazabildiği için
    /// sondaki "/v1" soyulur; aksi hâlde "/v1/v1/messages" → 404 (2026-10-20'de vekil yedeği bu yüzden çalışmıyordu).
    static var vekilTaban: URL? {
        #if DEBUG
        if SahteModelSunucusu.etkin { return nil }   // P3.10: hermetik kipte VPS'e düşüş yok
        // P3.10-arıza 'ağ yok': kapalı yerel port; https şema korumaları geçilir, gerçek 'bağlantı reddedildi' alınır.
        if ArizaAnahtarlari.etkin(.agYok) { return arizaKapaliVekil }
        #endif
        guard let durum = ortakDurum, durum.remote.isUsable else { return nil }
        return vekilKoku(durum.remote.baseURL)
    }

    #if DEBUG
    /// P3.10-arıza 'ağ yok' kipinde vekil kökü (9 numaralı port dinlenmez).
    static let arizaKapaliVekil = URL(string: "https://127.0.0.1:9")!
    #endif

    /// Saf dizgi işlemi (URL bileşen döngüsü kök adreste bitmeyebiliyordu): sondaki "/" ve "/v1" parçaları soyulur.
    static func vekilKoku(_ ham: String) -> URL? {
        var s = ham.trimmingCharacters(in: .whitespacesAndNewlines)
        while true {
            if s.hasSuffix("/") { s.removeLast(); continue }
            if s.lowercased().hasSuffix("/v1"), s.count > 3, !s.dropLast(3).hasSuffix(":/") { s.removeLast(3); continue }
            break
        }
        guard let url = URL(string: s), let sema = url.scheme?.lowercased(), sema == "https" || sema == "http", url.host() != nil else { return nil }
        return url
    }
}
