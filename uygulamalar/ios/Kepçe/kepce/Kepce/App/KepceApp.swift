import AVFoundation
import SwiftUI

@main
struct KepceApp: App {
    @State private var yonlendirici = Yonlendirici.shared
    @Environment(\.scenePhase) private var evre

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        PythonMotoru.shared.isit()
        if OzSinama.topluIstendi {
            IndirmeKuyrugu.shared.baslat()
            Task { await OzSinama.toplu() }
        } else if OzSinama.istendi {
            Task { await OzSinama.calistir() }
        } else {
            IndirmeKuyrugu.shared.baslat()
        }
    }

    var body: some Scene {
        WindowGroup {
            AnaGorunum()
                .environment(yonlendirici)
                .onOpenURL { yonlendirici.ac($0) }
                .onChange(of: evre) { _, yeni in
                    if yeni == .active { yonlendirici.paylasilanlariAl() }
                }
                .tint(.kepce)
        }
    }
}

extension Color {
    static let kepce = Color(red: 0.93, green: 0.26, blue: 0.22)
}

/// Bilgi sayfası isteği: bir bağlantı (isteğe bağlı başlık/kapak ön bilgisiyle).
struct BilgiIstegi: Identifiable, Hashable {
    let id = UUID()
    var adres: String
    var baslik: String?
    var kapak: String?
    var liste = false
}

@Observable final class Yonlendirici {
    static let shared = Yonlendirici()

    enum Sekme: Hashable { case indir, ara, kutuphane, ayarlar }
    var sekme: Sekme = .indir
    var bilgi: BilgiIstegi?
    var oynatilan: KutuphaneOgesi?
    var bildirim: String?

    /// kepce://indir?url=…&tur=video|ses  ·  kepce://ac?url=…  ·  kepce://paylasim
    func ac(_ url: URL) {
        guard url.scheme == "kepce" else {
            if ["http", "https"].contains(url.scheme ?? "") { bilgi = BilgiIstegi(adres: url.absoluteString) }
            return
        }
        let parametreler = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let adres = parametreler.first { $0.name == "url" }?.value
        switch url.host() {
        case "indir":
            guard let adres else { return }
            let tur = IndirmeTuru(rawValue: parametreler.first { $0.name == "tur" }?.value ?? "") ?? Ayarlar.shared.hizliTur
            hizliIndir(adres, tur: tur)
        case "ac":
            if let adres { bilgi = BilgiIstegi(adres: adres) }
        default:
            paylasilanlariAl()
        }
    }

    func hizliIndir(_ adres: String, tur: IndirmeTuru, baslik: String? = nil) {
        IndirmeKuyrugu.shared.ekle(adres: adres, secim: .hizli(tur), baslik: baslik)
        sekme = .indir
        bildirim = tur == .ses ? "Ses sıraya eklendi" : "Video sıraya eklendi"
    }

    /// Paylaşım uzantısının bıraktığı bağlantıları işler.
    func paylasilanlariAl() {
        for baglanti in PaylasimKutusu.bosalt() {
            switch baglanti.tur {
            case .video: hizliIndir(baglanti.adres, tur: .video)
            case .ses: hizliIndir(baglanti.adres, tur: .ses)
            case .sec: bilgi = BilgiIstegi(adres: baglanti.adres)
            }
        }
    }
}
