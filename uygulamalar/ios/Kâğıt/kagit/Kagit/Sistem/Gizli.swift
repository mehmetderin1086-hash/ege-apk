import Foundation
import Security

/// Keychain'de saklanan gizli değerler (VPS vekil anahtarı).
enum Gizli {
    private static let servis = "com.mehmetderin.kagit"
    static let vekilAnahtariHesabi = "vekil-anahtari"

    static func oku(_ hesap: String) -> String? {
        let sorgu: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: servis,
                                      kSecAttrAccount: hesap, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
        var sonuc: CFTypeRef?
        guard SecItemCopyMatching(sorgu as CFDictionary, &sonuc) == errSecSuccess, let v = sonuc as? Data else { return nil }
        return String(data: v, encoding: .utf8)
    }

    static func yaz(_ deger: String?, _ hesap: String) {
        let anahtar: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: servis, kSecAttrAccount: hesap]
        SecItemDelete(anahtar as CFDictionary)
        guard let deger, !deger.isEmpty else { return }
        var ekle = anahtar
        ekle[kSecValueData] = Data(deger.utf8)
        ekle[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(ekle as CFDictionary, nil)
    }

    /// VPS vekil erişim anahtarı (Claude + PDF Studio).
    static var vekilAnahtari: String? {
        get { oku(vekilAnahtariHesabi) }
        set { yaz(newValue, vekilAnahtariHesabi) }
    }

    /// Derlemeyle gelen anahtarı (Secrets.xcconfig → Info.plist) ilk açılışta Keychain'e alır.
    static func ilkAcilisAktarimi() {
        guard vekilAnahtari == nil,
              let gomulu = Bundle.main.object(forInfoDictionaryKey: "KagitVekilAnahtari") as? String,
              !gomulu.isEmpty, !gomulu.hasPrefix("$(") else { return }
        vekilAnahtari = gomulu
    }
}

/// VPS adresleri.
enum Sunucu {
    static let varsayilanKok = "https://xn--cumhuriyetanadolulisesiktphanesi-vmdb.com.tr/dersdas/claude/v1"

    /// Vekil kökü (ayarlardan değiştirilebilir).
    static var kok: String {
        get { UserDefaults.standard.string(forKey: "sunucu.kok") ?? varsayilanKok }
        set { UserDefaults.standard.set(newValue, forKey: "sunucu.kok") }
    }

    /// Claude Messages ucu.
    static var mesajlar: URL { URL(string: "\(kok)/messages")! }
    /// PDF Studio dönüşüm kökü (Caddy: /dersdas/claude/v1/pdf/* → 127.0.0.1:8060).
    static var pdfStudio: URL { URL(string: "\(kok)/pdf")! }
}
