import Foundation

/// Paylaşım uzantısı ile uygulama arasındaki bekleyen bağlantılar (App Group içinde tek JSON dosyası).
nonisolated struct PaylasilanBaglanti: Codable, Hashable, Sendable, Identifiable {
    enum Tur: String, Codable, Sendable { case video, ses, sec }
    var id = UUID()
    var adres: String
    var tur: Tur
    var tarih = Date()
}

nonisolated enum PaylasimKutusu {
    static let grup = "group.com.mehmetderin.kepce"

    static var dosya: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grup)?.appending(path: "bekleyen-baglantilar.json")
    }

    static func ekle(_ baglanti: PaylasilanBaglanti) throws {
        guard let dosya else { throw CocoaError(.fileNoSuchFile) }
        var liste = oku()
        liste.append(baglanti)
        try JSONEncoder().encode(liste).write(to: dosya, options: .atomic)
    }

    static func oku() -> [PaylasilanBaglanti] {
        guard let dosya, let veri = try? Data(contentsOf: dosya) else { return [] }
        return (try? JSONDecoder().decode([PaylasilanBaglanti].self, from: veri)) ?? []
    }

    /// Bekleyenleri döndürür ve kutuyu boşaltır.
    static func bosalt() -> [PaylasilanBaglanti] {
        let liste = oku()
        if !liste.isEmpty, let dosya { try? FileManager.default.removeItem(at: dosya) }
        return liste
    }

    /// Metnin içindeki ilk http(s) bağlantısını bulur (paylaşılan metinler çoğu zaman başlık + adres içerir).
    static func adresBul(_ metin: String) -> String? {
        guard let algilayici = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let aralik = NSRange(metin.startIndex..., in: metin)
        for eslesme in algilayici.matches(in: metin, range: aralik) {
            if let url = eslesme.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") { return url.absoluteString }
        }
        return nil
    }
}
