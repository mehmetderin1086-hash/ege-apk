import Foundation
import Observation

@MainActor @Observable
final class UygulamaBaglantilari {
    struct Kayit: Codable, Identifiable, Equatable {
        var id = UUID()
        var ad: String
        var uygulama: String
        var kestirme: String
        var whatsapp: Bool
    }
    static let ortak = UygulamaBaglantilari()
    private(set) var kayitlar: [Kayit]
    private let d: UserDefaults
    init(defaults: UserDefaults = .standard) {
        d = defaults
        kayitlar = d.data(forKey: "uygulama.eylemler.v1").flatMap { try? JSONDecoder().decode([Kayit].self, from: $0) } ?? []
    }
    struct Ozet: Equatable {
        let uygulamaKoprusuKurulu: Bool
        let bagliEylemSayisi: Int
        let whatsappHazir: Bool
        var durumMetni: String {
            let kopru = uygulamaKoprusuKurulu ? "Uygulama köprüsü hazır" : "Uygulama köprüsü kurulmadı"
            let whatsapp = whatsappHazir ? "WhatsApp köprüsü bağlı" : "WhatsApp köprüsü bağlı değil"
            return "\(kopru) · \(bagliEylemSayisi) bağlı eylem · \(whatsapp)"
        }
    }
    func ozet(uygulamaKoprusuKurulu: Bool) -> Ozet {
        .init(uygulamaKoprusuKurulu: uygulamaKoprusuKurulu, bagliEylemSayisi: kayitlar.count, whatsappHazir: kayitlar.contains(where: \.whatsapp))
    }
    func kaydet(ad: String, uygulama: String, kestirme: String, whatsapp: Bool) throws {
        let ad = ad.trimmingCharacters(in: .whitespacesAndNewlines)
        let uygulama = uygulama.trimmingCharacters(in: .whitespacesAndNewlines)
        let kestirme = kestirme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ad.isEmpty, !uygulama.isEmpty, !kestirme.isEmpty, ad.count <= 80, kestirme.count <= 100, kayitlar.count < 40 else { throw Hata.gecersiz }
        if whatsapp { kayitlar.removeAll(where: \.whatsapp) }
        if let index = kayitlar.firstIndex(where: {
            TelefonAdresleri.ad($0.ad) == TelefonAdresleri.ad(ad) && TelefonAdresleri.ad($0.uygulama) == TelefonAdresleri.ad(uygulama)
        }) {
            let id = kayitlar[index].id
            kayitlar[index] = .init(id: id, ad: ad, uygulama: uygulama, kestirme: kestirme, whatsapp: whatsapp)
        } else {
            kayitlar.append(.init(ad: ad, uygulama: uygulama, kestirme: kestirme, whatsapp: whatsapp))
        }
        sakla()
    }
    func sil(_ id: UUID) { kayitlar.removeAll { $0.id == id }; sakla() }
    private func sakla() { if let data = try? JSONEncoder().encode(kayitlar) { d.set(data, forKey: "uygulama.eylemler.v1") } }
    enum Hata: LocalizedError {
        case gecersiz
        var errorDescription: String? { "Ad, uygulama ve kestirme adını doldur. En fazla 40 bağlantı eklenebilir." }
    }
    static func whatsappGirdisi(hedef: String, metin: String) -> String? {
        guard let url = IletisimAraci.adres(islem: "whatsapp", hedef: hedef, metin: metin),
              !metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, metin.count <= 8000 else { return nil }
        let telefon = url.lastPathComponent
        guard let data = try? JSONSerialization.data(withJSONObject: ["telefon": telefon, "mesaj": metin], options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }
}
