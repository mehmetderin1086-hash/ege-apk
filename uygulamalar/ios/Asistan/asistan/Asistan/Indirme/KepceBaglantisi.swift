import Foundation
import UIKit

@MainActor enum KepceBaglantisi {
    static var kurulu: Bool { UIApplication.shared.canOpenURL(URL(string: "kepce://paylasim")!) }
    nonisolated static func adres(_ kaynak: URL, tur: String) -> URL? {
        guard ["video", "audio"].contains(tur), (try? IndirmeYoneticisi.dogrula(kaynak.absoluteString)) != nil else { return nil }
        var c = URLComponents(); c.scheme = "kepce"; c.host = "indir"
        c.queryItems = [URLQueryItem(name: "url", value: kaynak.absoluteString), URLQueryItem(name: "tur", value: tur == "audio" ? "ses" : "video")]
        return c.url
    }
    static func aktar(_ kaynak: URL, tur: String) async throws {
        guard kurulu, let url = adres(kaynak, tur: tur), await UIApplication.shared.open(url) else { throw IndirmeHatasi.metin("Kepçe açılamadı. Uygulamanın bu iPhone’da kurulu olduğunu kontrol et.") }
    }
    static func ac() { UIApplication.shared.open(URL(string: "kepce://paylasim")!) }
}
