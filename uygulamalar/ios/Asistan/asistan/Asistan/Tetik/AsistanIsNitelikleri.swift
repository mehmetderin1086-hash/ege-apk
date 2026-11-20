import ActivityKit
import Foundation

/// Uygulama ile widget uzantısının paylaştığı "uzun iş" Live Activity verisi (araştırma, alt ajan, toplu işlem…).
nonisolated struct AsistanIsNitelikleri: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var adim: String
        var tamamlanan: Int = 0
        var toplam: Int = 0
        var bitti = false
        var hata = false
        var sureSn = 0
        /// Kullanıcı Durdur'a bastı: widget "Tamamlanamadı" değil "Durduruldu" gösterir.
        var durduruldu = false
        /// P2.14: bitince yanıtın kısa özeti (Markdown'sız, en çok ~140 karakter; `IsAktivitesi.ozetle`). Kilit ekranında gizlenebilir.
        var ozet: String? = nil
        /// P2.14: yanıtın kaydedildiği sohbetin kimliği (UUID metni): dokununca `asistan://sohbet?kimlik=` o sohbeti açar.
        var sohbetID: String? = nil
        /// P4.2: bas-konuş ya da arka plan Live mikrofonu dinliyor (widget "Dinliyorum" ve dalga simgesi gösterir).
        var dinliyor = false

        nonisolated enum CodingKeys: String, CodingKey {
            case adim, tamamlanan, toplam, bitti, hata, sureSn, durduruldu, ozet, sohbetID, dinliyor
        }
    }
    var istek: String
    var baslangic: Date
}

/// Geriye uyumlu çözücü: eski sürümden kalan etkinliğin durumunda yeni alanlar yoktur; yalnız `adim` zorunludur.
/// Extension'da olduğu için memberwise init korunur; `nonisolated` olmazsa varsayılan MainActor yalıtımı
/// Decodable uyumunu yalıtımlı yapar ve uzantı süreci/`Task.detached` içinde çözme çalışmaz.
nonisolated extension AsistanIsNitelikleri.ContentState {
    init(from decoder: any Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        adim = try k.decode(String.self, forKey: .adim)
        tamamlanan = try k.decodeIfPresent(Int.self, forKey: .tamamlanan) ?? 0
        toplam = try k.decodeIfPresent(Int.self, forKey: .toplam) ?? 0
        bitti = try k.decodeIfPresent(Bool.self, forKey: .bitti) ?? false
        hata = try k.decodeIfPresent(Bool.self, forKey: .hata) ?? false
        sureSn = try k.decodeIfPresent(Int.self, forKey: .sureSn) ?? 0
        durduruldu = try k.decodeIfPresent(Bool.self, forKey: .durduruldu) ?? false
        ozet = try k.decodeIfPresent(String.self, forKey: .ozet)
        sohbetID = try k.decodeIfPresent(String.self, forKey: .sohbetID)
        dinliyor = try k.decodeIfPresent(Bool.self, forKey: .dinliyor) ?? false
    }
}

/// Saf görünüm kararı (uygulama ve widget uzantısı ortak): kilit ekranı/Dynamic Island başlığı ve simgesi.
nonisolated enum IsAktivitesiGorunum {
    nonisolated enum Hal: Equatable, Sendable { case calisiyor, hazir, durduruldu, hata, koptu }

    /// Öncelik: durduruldu > hata > hazır; bitmemiş iş bayatsa (uygulama öldü/güncelleme gelmedi) koptu.
    static func hal(_ s: AsistanIsNitelikleri.ContentState, bayat: Bool) -> Hal {
        if s.bitti {
            if s.durduruldu { return .durduruldu }
            return s.hata ? .hata : .hazir
        }
        return bayat ? .koptu : .calisiyor
    }

    static func baslik(_ h: Hal) -> String {
        switch h {
        case .calisiyor: "Asistan çalışıyor"
        case .hazir: "Hazır"
        case .durduruldu: "Durduruldu"
        case .hata: "Tamamlanamadı"
        case .koptu: "Bağlantı koptu"
        }
    }

    static func simge(_ h: Hal) -> String {
        switch h {
        case .calisiyor: "sparkles"
        case .hazir: "checkmark.circle.fill"
        case .durduruldu: "stop.circle.fill"
        case .hata: "exclamationmark.circle.fill"
        case .koptu: "exclamationmark.arrow.circlepath"
        }
    }

    /// P4.2: mikrofon açıkken (bas-konuş, arka plan Live) çalışan etkinliğin başlığı "Dinliyorum" olur.
    static func baslik(_ s: AsistanIsNitelikleri.ContentState, _ h: Hal) -> String {
        s.dinliyor && h == .calisiyor ? "Dinliyorum" : baslik(h)
    }

    /// P4.2: mikrofon açıkken dalga simgesi (widget canlı efektle gösterir).
    static func simge(_ s: AsistanIsNitelikleri.ContentState, _ h: Hal) -> String {
        s.dinliyor && h == .calisiyor ? "waveform" : simge(h)
    }

    /// Koptu hâlinde eski adım metni yanıltıcıdır; yerine yönlendirme yazılır.
    static func adimMetni(_ s: AsistanIsNitelikleri.ContentState, _ h: Hal) -> String {
        h == .koptu ? "Durumu görmek için uygulamayı aç" : s.adim
    }

    /// P2.14: sohbeti açan bağlantı (`AsistanBaglantisi.coz` → `.sohbet`); kimlik UUID değilse nil.
    static func sohbetAdresi(_ kimlik: String?) -> URL? {
        guard let kimlik, let u = UUID(uuidString: kimlik) else { return nil }
        return URL(string: "asistan://sohbet?kimlik=\(u.uuidString)")
    }
}
