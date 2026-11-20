import Foundation

/// Widget, kontrol ve QR'ların ortak derin bağlantı rotaları. Hem uygulama hem widget hedefinde derlenir.
nonisolated enum DeepLinkRoute: String, CaseIterable, Sendable {
    case barkod, seri, ses, kapak, kamera, elle, asistan, odunc, iade

    static let scheme = "kitapbul"

    /// Şemadan sonraki yol: `ekle/barkod`, `asistan`, `odunc`.
    var path: String {
        switch self {
        case .asistan, .odunc, .iade: rawValue
        default: "ekle/" + rawValue
        }
    }

    var url: URL { URL(string: "\(Self.scheme)://\(path)")! }

    /// Widget'ta düğme olarak gösterilenler (sıra görünüm sırasıdır).
    static let widgetRoutes: [DeepLinkRoute] = [.barkod, .ses, .kapak, .asistan]
}
