import Foundation
import Observation

/// A cold launch can receive a widget/QR URL while no catalogue is mounted.
/// Keep the latest valid navigation intent in memory, without reading any DB.
@MainActor
@Observable
final class LibraryLaunchLinkQueue {
    private(set) var pendingURL: URL?
    private static let actions: [String: HizliEylem] = ["barkod": .barkod, "seri": .seri, "ses": .ses,
        "kapak": .canliKapak, "kamera": .kamera, "elle": .elle]

    /// kitapbul://odunc ve kitapbul://iade: Ana Sayfa'da barkod masasını ilgili kipte açar.
    /// Yalnızca ekranı açar; hiçbir kayıt bu bağlantıyla değişmez.
    static func oduncModu(from url: URL) -> HizliOduncSayfasi.Mode? {
        guard url.scheme?.lowercased() == KitapQR.sema else { return nil }
        switch url.host?.lowercased() {
        case "odunc": return .lend
        case "iade": return .giveBack
        default: return nil
        }
    }

    func enqueue(_ url: URL) {
        if Self.oduncModu(from: url) != nil { pendingURL = url; return }
        guard let target = KitapQR.hedef(from: url) else { return }
        if case .ekle(let method) = target, Self.actions[method] == nil { return }
        pendingURL = url
    }

    /// Called only by the ready root after a verified container exists. Initial
    /// observers on MainTab/Book/Add consume the route even before first appear.
    func dispatchPending() {
        guard let url = pendingURL else { return }
        let state = DerinBaglanti.shared
        if let mod = Self.oduncModu(from: url) {
            pendingURL = nil
            state.bekleyenKitapID = nil; state.bekleyenEylem = nil
            KutuphaneRotasi.shared.bekleyenOduncModu = mod
            state.hedefSekme = .anaSayfa
            return
        }
        guard let target = KitapQR.hedef(from: url) else { return }
        pendingURL = nil
        state.bekleyenKitapID = nil; state.bekleyenEylem = nil
        switch target {
        case .kitap(let id): state.bekleyenKitapID = id; state.hedefSekme = .kitaplar
        case .ekle(let method):
            guard let action = Self.actions[method] else { return }
            state.bekleyenEylem = action; state.hedefSekme = .katalog
        case .asistan: state.hedefSekme = .asistan
        }
    }
}
