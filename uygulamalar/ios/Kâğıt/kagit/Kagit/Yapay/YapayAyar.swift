import KagitKit
import SwiftUI

/// Yapay zekâ ayarları (kaynak tercihi, model) ve hazır `YapayZeka` üreticisi.
@Observable
final class YapayAyar {
    static let paylasilan = YapayAyar()
    private let d = UserDefaults.standard

    var tercih: KaynakTercihi { didSet { d.set(tercih.rawValue, forKey: "yapay.kaynak") } }
    var model: String { didSet { d.set(model, forKey: "yapay.model") } }
    /// Ekranda düzenlenen anahtar; Keychain'e yazılır, UserDefaults'a asla.
    var anahtar: String { didSet { Gizli.vekilAnahtari = anahtar.isEmpty ? nil : anahtar } }

    init() {
        tercih = KaynakTercihi(rawValue: d.string(forKey: "yapay.kaynak") ?? "") ?? .otomatik
        model = d.string(forKey: "yapay.model") ?? YapayModeller.varsayilan
        anahtar = Gizli.vekilAnahtari ?? ""
    }

    func yapayZeka() -> YapayZeka {
        YapayZeka(YapayYapilandirma(tercih: tercih, model: model, bulutAcik: Ayarlar.paylasilan.bulutYapayZeka,
                                    kok: Sunucu.kok, anahtar: Gizli.vekilAnahtari))
    }
}

/// “Kaynak: Claude (bulut)” rozeti.
struct KaynakRozeti: View {
    let etiket: String
    var body: some View {
        Label("Kaynak: \(etiket)", systemImage: etiket == "Cihaz" ? "iphone" : "cloud")
            .font(.caption).foregroundStyle(.secondary)
    }
}
