import Foundation
import Observation
import AVFoundation

/// İçerik, istem, hesap ve anahtar tutmadan uygulamanın gecikme ve bileşen sağlığını izler.
@MainActor @Observable
final class SaglikMerkezi {
    struct Olcum: Codable, Identifiable, Equatable {
        let id: UUID
        let zaman: Date
        let tur: String
        let sureMs: Double
        let basarili: Bool
        let etiket: String?
    }

    struct Ozet: Equatable {
        let adet: Int
        let ortalamaMs: Double
        let medyanMs: Double
        let p90Ms: Double
        let p95Ms: Double
        let basariOrani: Double
    }

    struct Denetim: Identifiable, Equatable {
        enum Durum: String { case iyi, uyari, hata }
        let id: String
        let baslik: String
        let ayrinti: String
        let durum: Durum
    }

    static let ortak = SaglikMerkezi()
    private let defaults: UserDefaults
    private(set) var olcumler: [Olcum]
    private(set) var denetimler: [Denetim] = []
    private(set) var denetleniyor = false
    private(set) var sonDenetim: Date?
    /// Sesli tur dört kayıt (ses_tur + üç aşama) ürettiği için pencere geniş tutulur.
    nonisolated static let sinir = 300

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        olcumler = defaults.data(forKey: "saglik.olcumler.v1")
            .flatMap { try? JSONDecoder().decode([Olcum].self, from: $0) } ?? []
    }

    func kaydet(_ tur: String, sure: TimeInterval, basarili: Bool = true, etiket: String? = nil) {
        let temizEtiket = etiket.map { String($0.prefix(80)) }
        olcumler.append(.init(id: UUID(), zaman: .now, tur: tur,
                              sureMs: min(300_000, max(0, sure * 1000)),
                              basarili: basarili, etiket: temizEtiket))
        if olcumler.count > Self.sinir { olcumler.removeFirst(olcumler.count - Self.sinir) }
        sakla()
    }

    func ozet(_ tur: String) -> Ozet? {
        let secilen = olcumler.filter { $0.tur == tur }
        guard !secilen.isEmpty else { return nil }
        let sureler = secilen.map(\.sureMs).sorted()
        return Ozet(adet: secilen.count,
                    ortalamaMs: sureler.reduce(0, +) / Double(sureler.count),
                    medyanMs: Self.yuzdelik(sureler, 0.5),
                    p90Ms: Self.yuzdelik(sureler, 0.9),
                    p95Ms: Self.yuzdelik(sureler, 0.95),
                    basariOrani: Double(secilen.filter(\.basarili).count) / Double(secilen.count))
    }

    /// Sıralı dizide yüzdelik (en yakın sıra yöntemi: ceil(p·n). eleman). Boş dizide 0.
    nonisolated static func yuzdelik(_ sirali: [Double], _ p: Double) -> Double {
        guard !sirali.isEmpty else { return 0 }
        let sira = Int(ceil(Double(sirali.count) * min(1, max(0, p))))
        return sirali[min(sirali.count - 1, max(0, sira - 1))]
    }

    func temizle() {
        olcumler.removeAll()
        defaults.removeObject(forKey: "saglik.olcumler.v1")
    }

    /// `zorla`: 'Şimdi yeniden denetle' düğmesi model listesini her zaman ağdan yeniden sınar. Ekran açılışında (P3.9)
    /// son bir dakika içinde alınmış liste yeniden sınanmaz; açılış sınaması zaten yapıldıysa ağ isteği tekrarlanmaz.
    func denetle(zorla: Bool = false) async {
        guard !denetleniyor else { return }
        denetleniyor = true
        defer { denetleniyor = false; sonDenetim = .now }
        if zorla { await TelefonProxy.ortak.sina() } else { await TelefonProxy.ortak.sinaGerekirse(enEski: 60) }
        let proxy = TelefonProxy.ortak
        var sonuc: [Denetim] = [
            .init(id: "proxy", baslik: "iPhone CLIProxy", ayrinti: proxy.durum,
                  durum: proxy.hazir ? .iyi : .hata),
            .init(id: "hesap", baslik: "Bağlı hesaplar", ayrinti: "\(proxy.hesapSayisi) hesap · \(proxy.modeller.count) bilinen model",
                  durum: proxy.hesapSayisi > 0 ? .iyi : .hata)
        ]
        let antigravityCanliHazir = proxy.modeller.contains { $0.id == ModelVitesi.antigravityCanliModel }
        sonuc.append(.init(id: "live_yedek", baslik: "Live ses yedeği",
                           ayrinti: antigravityCanliHazir ? "Antigravity Gemini 3.8 Flash hazır" : "Antigravity Gemini 3.8 Flash model listesinde bulunamadı",
                           durum: antigravityCanliHazir ? .iyi : .uyari))
        let mikrofon = AVAudioApplication.shared.recordPermission
        sonuc.append(.init(id: "mikrofon", baslik: "Mikrofon izni",
                           ayrinti: mikrofon == .granted ? "Açık" : (mikrofon == .denied ? "Kapalı" : "Henüz sorulmadı"),
                           durum: mikrofon == .granted ? .iyi : (mikrofon == .denied ? .hata : .uyari)))
        let turkce = await SesDinleyici.destekleniyor()
        sonuc.append(.init(id: "stt", baslik: "Türkçe konuşma tanıma", ayrinti: turkce ? "Cihazda hazır" : "Bu cihazda kullanılamıyor",
                           durum: turkce ? .iyi : .hata))
        await AsistanSesleri.ortak.yenile()
        let sesSayisi = AsistanSesleri.ortak.sesler.count
        sonuc.append(.init(id: "tts", baslik: "Ses kataloğu", ayrinti: sesSayisi > 0 ? "\(sesSayisi) bulut sesi + iPhone sesleri" : "Yalnız iPhone sesleri",
                           durum: sesSayisi > 0 ? .iyi : .uyari))
        let sunucu = Gizli.vekilTaban?.scheme == "https" && Gizli.vekilToken != nil
        sonuc.append(.init(id: "sunucu", baslik: "Kodlama sunucusu", ayrinti: sunucu ? "Yapılandırıldı" : "Yapılandırılmadı",
                           durum: sunucu ? .iyi : .uyari))
        // P3.9: termal durum, Düşük Güç ve Düşük Veri; etkin kısıtlar (yarış genişliği, bekçi aralığı, uyandırma beklemesi).
        let guc = GucPolitikasi.ortak.ozet(dusukVeri: AgIzleyici.ortak.dusukVeri)
        sonuc.append(.init(id: "guc", baslik: "Güç", ayrinti: guc.metin, durum: guc.kisitli ? .uyari : .iyi))
        denetimler = sonuc
    }

    private func sakla() {
        if let veri = try? JSONEncoder().encode(olcumler) { defaults.set(veri, forKey: "saglik.olcumler.v1") }
    }
}
