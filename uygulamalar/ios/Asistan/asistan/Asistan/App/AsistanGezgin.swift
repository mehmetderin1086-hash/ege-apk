import Foundation
import Observation

/// Kestirmeler, Denetim Merkezi ve `asistan://` bağlantılarından gelen ekran isteklerini
/// uygulamanın tek penceresine taşır. İstek yalnızca uygulama açıkken işlenir.
@MainActor @Observable
final class AsistanGezgin {
    enum Hedef: String, Equatable {
        case atolye
        case indirmeler
        case telefon
        case donustur
        case arsiv
        case gelenKutusu
        case uretkenlik
        case herYerdeAra
    }

    static let ortak = AsistanGezgin()
    var hedef: Hedef?

    func ac(_ yeniHedef: Hedef) {
        hedef = yeniHedef
    }

    func tamamla() {
        hedef = nil
    }
}

/// Uygulamanın dışa açık bağlantı sözleşmesi. Kestirmeler ve Denetim Merkezi bu
/// bağlantıları üretir; çözümleme saf tutulduğu için uygulama açılmadan test edilir.
enum AsistanBaglantisi: Equatable {
    case dinle
    case live
    case ekran(AsistanGezgin.Hedef)
    case taslak(String)
    /// Dış bağlantıdan gelen soru (herhangi bir uygulama, web sayfası, QR açabilir): dış kaynaklı tur olarak
    /// gönderilir, yan etkili adımlar kullanıcıya sorulur; asistan meşgulse sırada bekler (`DisSoruKuyrugu.ortak`).
    /// Siri, Kestirmeler ve tetik bildirimleri bu bağlantıyı değil, süreç içi `.asistanSor` bildirimini kullanır
    /// (kullanıcının kendisi sayılır; meşgulse `DisSoruKuyrugu.ic` sırasında bekler).
    case sor(String)
    /// Paylaş menüsünden kutuya düşen işi başlat.
    case paylasim
    /// P2.14: kayıtlı bir sohbeti açar (`asistan://sohbet?kimlik=<uuid>`; Live Activity, arka plan yanıt bildirimi).
    /// Dış uygulama da açabilir ama yalnız var olan sohbeti gösterir: gönderim, araç ya da başka yan etki yoktur.
    case sohbet(UUID)
    /// P3.11: Hızlı sor widget'ı (`asistan://hizli?no=N`). Bağlantı yalnız numara taşır; çalışan metin uygulamaya gömülü
    /// sabit istemdir (`DersGunu.hizliIstem`), dış uygulama onu değiştiremez. Bilinmeyen numara nil döner.
    /// Widget dokunuşu dış uygulamadan ayırt edilemediği için `.sor` gibi dış kaynaklı tur olarak gider (`DisSoruKuyrugu.ortak`).
    case hizli(Int)
    /// P4.2 kipli kontrol: Live açılır, ardından kamera (`asistan://canli-kamera`).
    case canliKamera
    /// P4.2 kipli kontrol: son sohbete dönüp dinlemeye başlar (`asistan://devam`); yeni gönderim yoktur.
    case devam

    static func coz(_ url: URL) -> AsistanBaglantisi? {
        guard url.scheme?.lowercased() == "asistan" else { return nil }
        switch url.host?.lowercased() {
        case "dinle": return .dinle
        case "live": return .live
        case "canli-kamera": return .canliKamera
        case "devam": return .devam
        case "gelen-kutusu": return .ekran(.gelenKutusu)
        case "atolye": return .ekran(.atolye)
        case "indirmeler": return .ekran(.indirmeler)
        case "telefon": return .ekran(.telefon)
        case "donustur": return .ekran(.donustur)
        case "arsiv": return .ekran(.arsiv)
        case "uretkenlik": return .ekran(.uretkenlik)
        case "ara": return .ekran(.herYerdeAra)
        case "taslak":
            guard let metin = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "metin" })?.value,
                  !metin.isEmpty else { return nil }
            return .taslak(String(metin.prefix(8_000)))
        case "paylasim": return .paylasim
        case "sor":
            guard let metin = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "metin" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !metin.isEmpty else { return nil }
            return .sor(String(metin.prefix(4_000)))
        case "sohbet":
            guard let k = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "kimlik" })?.value,
                  let kimlik = UUID(uuidString: k) else { return nil }
            return .sohbet(kimlik)
        case "hizli":
            guard let n = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "no" })?.value,
                  let no = Int(n), DersGunu.hizliIstem(no) != nil else { return nil }
            return .hizli(no)
        default: return nil
        }
    }

    /// P2.13: Siri devri sesli sürsün mü (`asistan://sor?metin=…&ses=1`). `coz` bu bayrağı yok sayar.
    nonisolated static func sesliMi(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "ses" && $0.value == "1" } ?? false
    }
}
