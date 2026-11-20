import Foundation
import Observation
import UIKit

nonisolated enum TelefonAdresleri {
    static func ad(_ metin: String) -> String {
        metin.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "tr_TR"))
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
    }

    static func web(_ metin: String) -> URL? {
        guard let c = URLComponents(string: metin.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme?.lowercased() == "https", let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil else { return nil }
        return c.url
    }

    static func kisayol(_ ad: String, girdi: String? = nil) -> URL? {
        guard !ad.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var c = URLComponents(string: "shortcuts://run-shortcut")!
        c.queryItems = [URLQueryItem(name: "name", value: ad)]
        if let girdi, !girdi.isEmpty {
            c.queryItems! += [URLQueryItem(name: "input", value: "text"), URLQueryItem(name: "text", value: girdi)]
        }
        return c.url
    }

    @MainActor
    static func ac(_ url: URL) async -> Bool {
        // canOpenURL yalnız bir uygulamanın kayıtlı olduğunu söyler; gerçek sonucu bekle.
        await UIApplication.shared.open(url, options: [:])
    }
}

@MainActor
@Observable
final class TelefonKestirmeleri {
    struct Kayit: Codable, Identifiable, Equatable {
        var id = UUID()
        var ad: String
        var kestirme: String
    }
    static let ortak = TelefonKestirmeleri()
    private let defaults: UserDefaults
    private(set) var kayitlar: [Kayit]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        kayitlar = defaults.data(forKey: "telefon.kestirmeler")
            .flatMap { try? JSONDecoder().decode([Kayit].self, from: $0) } ?? []
    }

    func kaydet(ad: String, kestirme: String) {
        let ad = ad.trimmingCharacters(in: .whitespacesAndNewlines)
        let kestirme = kestirme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ad.isEmpty, !kestirme.isEmpty else { return }
        if let i = kayitlar.firstIndex(where: { TelefonAdresleri.ad($0.ad) == TelefonAdresleri.ad(ad) }) {
            kayitlar[i].kestirme = kestirme
        } else { kayitlar.append(Kayit(ad: ad, kestirme: kestirme)) }
        sakla()
    }

    func sil(_ id: UUID) { kayitlar.removeAll { $0.id == id }; sakla() }
    func bul(_ ad: String) -> Kayit? { kayitlar.first { TelefonAdresleri.ad($0.ad) == TelefonAdresleri.ad(ad) } }
    private func sakla() {
        if let veri = try? JSONEncoder().encode(kayitlar) { defaults.set(veri, forKey: "telefon.kestirmeler") }
    }
}
