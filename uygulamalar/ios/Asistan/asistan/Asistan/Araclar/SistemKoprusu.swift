import AVFoundation
import Foundation
import Observation
import UIKit

/// Siri'nin doğrudan değiştirdiği sistem ayarlarından biri. iOS bunlar için uygulamalara genel API vermez;
/// imzalı "Asistan Sistem Köprüsü" kestirmesi her `kod` için sabit bir Kestirmeler eylemi çalıştırır
/// (`araclar/sistem-koprusu.py` aynı tabloyu üretir; `SistemKoprusuTestleri` iki tarafı karşılaştırır).
nonisolated enum SistemKomutu: Equatable, Hashable, Sendable {
    enum Ayar: String, CaseIterable, Sendable {
        case wifi, bluetooth, ucak, mobilveri, dusukguc, donmekilidi, hotspot, gecevardiyasi, truetone, bildirimseslendir, odak

        var ad: String {
            switch self {
            case .wifi: "Wi-Fi"
            case .bluetooth: "Bluetooth"
            case .ucak: "Uçak modu"
            case .mobilveri: "Mobil veri"
            case .dusukguc: "Düşük güç modu"
            case .donmekilidi: "Dikey yön kilidi"
            case .hotspot: "Kişisel erişim noktası"
            case .gecevardiyasi: "Night Shift"
            case .truetone: "True Tone"
            case .bildirimseslendir: "Bildirimleri seslendirme"
            case .odak: "Rahatsız Etme"
            }
        }
    }

    case anahtar(Ayar, Bool)
    case gorunum(karanlik: Bool)
    /// 0-100, onluk adımlara yuvarlanmış.
    case ses(Int)
    case kilitle
    /// Kurulum sınaması: köprüde boş daldır, hiçbir ayarı değiştirmez.
    case deneme

    /// Köprüye giden girdi; köprü yalnız bu sabit adları tanır.
    var kod: String {
        switch self {
        case .anahtar(let a, let acik): "\(a.rawValue)_\(acik ? "ac" : "kapat")"
        case .gorunum(let k): k ? "karanlik" : "aydinlik"
        case .ses(let y): "ses_\(y)"
        case .kilitle: "kilitle"
        case .deneme: "deneme"
        }
    }

    static var tumu: [SistemKomutu] {
        Ayar.allCases.flatMap { [.anahtar($0, true), .anahtar($0, false)] } + [.gorunum(karanlik: true), .gorunum(karanlik: false), .kilitle, .deneme]
            + stride(from: 0, through: 100, by: 10).map { .ses($0) }
    }

    /// İnterneti kesebilen komut: yanıt (bulut model, bulut ses) bittikten sonra çalıştırılır.
    var agiKeser: Bool {
        switch self {
        case .anahtar(.ucak, true), .anahtar(.wifi, false), .anahtar(.mobilveri, false): true
        default: false
        }
    }

    /// Yanıttan sonra çalışır: interneti kesen komutlar ve ekran kilidi (kilitlenen ekran Asistan'a dönüş yapamaz).
    var yanittanSonra: Bool { agiKeser || self == .kilitle }

    /// Ertelenen listede aynı ayarın yalnız son isteği kalır.
    var ayarAnahtari: String {
        switch self {
        case .anahtar(let a, _): a.rawValue
        case .gorunum: "gorunum"
        case .ses: "ses"
        case .kilitle: "kilitle"
        case .deneme: "deneme"
        }
    }

    var ozet: String {
        switch self {
        case .anahtar(let a, let acik): return "\(a.ad) \(acik ? "açıldı" : "kapatıldı")"
        case .gorunum(let k): return k ? "Karanlık görünüme geçildi" : "Açık görünüme geçildi"
        case .ses(let y): return "Ses düzeyi %\(y) yapıldı"
        case .kilitle: return "Ekran kilitlendi"
        case .deneme: return "Sistem köprüsü çalışıyor"
        }
    }

    /// Onay diyaloğu başlığı ("Wi-Fi: kapat").
    var istek: String {
        switch self {
        case .anahtar(let a, let acik): "\(a.ad): \(acik ? "aç" : "kapat")"
        case .gorunum(let k): "Görünüm: \(k ? "karanlık" : "açık")"
        case .ses(let y): "Ses düzeyi: %\(y)"
        case .kilitle: "Ekranı kilitle"
        case .deneme: "Köprü sınaması"
        }
    }

    /// Ertelenen komutun bildirimi ("Uçak modu açılacak").
    var gelecek: String {
        if case .anahtar(let a, let acik) = self { return "\(a.ad) \(acik ? "açılacak" : "kapatılacak")" }
        if self == .kilitle { return "Ekran kilitlenecek" }
        return ozet
    }

    // MARK: Çözümleme (saf)

    /// Model ya da yerel komut çözücüsünün verdiği ayar adı + değer. Anlaşılmazsa nil.
    /// `mevcutSes` (0-1): göreli ses isteği ("artir"/"azalt") için şimdiki medya ses düzeyi; yoksa göreli istek çözülmez.
    static func coz(ayar: String, deger: String?, mevcutSes: Double? = nil) -> SistemKomutu? {
        let a = TelefonAdresleri.ad(ayar).replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        let d = deger.map { TelefonAdresleri.ad($0) } ?? ""
        if ["kilitle", "ekrani kilitle", "ekran kilidi", "kilit"].contains(a) { return .kilitle }
        if a == "deneme" { return .deneme }
        if ["ses", "ses duzeyi", "ses seviyesi", "volume", "sesi"].contains(a) {
            if ["sustur", "kapat", "sessiz"].contains(d) { return .ses(0) }
            let adim: Int? = ["artir", "yukselt", "ac", "arttir"].contains(d) ? 20 : ["azalt", "kis", "dusur"].contains(d) ? -20 : nil
            if let adim {
                guard let m = mevcutSes else { return nil }
                return .ses(min(max(Int((m * 10).rounded()) * 10 + adim, 0), 100))
            }
            guard let y = Double(d.filter { $0.isNumber || $0 == "." || $0 == "," }.replacingOccurrences(of: ",", with: ".")) else { return nil }
            return .ses(Int((min(max(y, 0), 100) / 10).rounded()) * 10)
        }
        if ["gorunum", "tema", "karanlik mod", "karanlik", "koyu mod", "koyu", "aydinlik mod", "aydinlik", "acik mod", "dark mode", "light mode"].contains(a) {
            if d.contains("aydin") || d.contains("light") || d == "acik mod" { return .gorunum(karanlik: false) }
            // iOS Türkçe arayüzü temaları "Açık / Koyu" diye adlandırır: görünüm için "açık" aydınlık demektir, "aç" değil.
            if a == "gorunum" || a == "tema", d.hasPrefix("acik") { return .gorunum(karanlik: false) }
            if d.contains("karanlik") || d.contains("koyu") || d.contains("dark") { return .gorunum(karanlik: true) }
            guard let acik = acikMi(d) else { return nil }
            // "karanlık modu kapat" → aydınlık; "aydınlık modu aç" → aydınlık.
            let karanlikAdi = !(a.contains("aydin") || a.contains("acik") || a.contains("light"))
            return .gorunum(karanlik: karanlikAdi == acik)
        }
        guard let ayar = ayarAdi(a), let acik = acikMi(d) else { return nil }
        return .anahtar(ayar, acik)
    }

    static func ayarAdi(_ a: String) -> Ayar? {
        let b = a.replacingOccurrences(of: " ", with: "")
        if b.contains("wifi") || b.contains("kablosuzag") { return .wifi }
        if b.contains("bluetooth") { return .bluetooth }
        if b.contains("ucak") { return .ucak }
        if b.contains("mobilveri") || b.contains("hucresel") { return .mobilveri }
        if b.contains("dusukguc") || b.contains("guctasarruf") { return .dusukguc }
        if b.contains("donme") || b.contains("dondurme") || b.contains("yonkilidi") || b.contains("yonlendirmekilidi") { return .donmekilidi }
        if b.contains("hotspot") || b.contains("erisimnoktasi") || b.contains("internetpaylas") { return .hotspot }
        if b.contains("gecevardiya") || b.contains("nightshift") { return .gecevardiyasi }
        if b.contains("truetone") { return .truetone }
        if b.contains("bildirim") && (b.contains("seslendir") || b.contains("duyur") || b.contains("oku")) { return .bildirimseslendir }
        if b.contains("odak") || b.contains("rahatsizetme") || b == "dnd" { return .odak }
        return Ayar(rawValue: b)
    }

    static func acikMi(_ d: String) -> Bool? {
        let t = d.trimmingCharacters(in: .whitespaces)
        if ["ac", "acik", "on", "1", "true", "evet", "etkin", "aktif", "baslat"].contains(t) || t.hasPrefix("ac") { return true }
        if ["kapat", "kapali", "off", "0", "false", "hayir", "devre disi", "pasif", "sondur"].contains(t) || t.hasPrefix("kapa") { return false }
        return nil
    }
}

/// Köprüyü x-callback-url ile çalıştırır ve sonucunu bekler. Kestirmeler işi bitirince `asistan://sistem-koprusu` ile döner.
@MainActor
@Observable
final class SistemKoprusu {
    enum Sonuc: Equatable, Sendable {
        case tamam
        case hata(String)
        case iptal
        case zamanAsimi
        case acilamadi
        /// Asistan'daki iş durduruldu (Kestirmeler açılmış olabilir).
        case durduruldu
        /// Uygulama öne gelmedi: iOS arka plandan Kestirmeler'i açtırmaz.
        case arkaPlanda
    }

    static let ortak = SistemKoprusu()
    nonisolated static let kestirmeAdi = "Asistan Sistem Köprüsü"
    nonisolated static let anahtar = "sistem.koprusu.kuruldu.v1"

    /// İlk başarılı dönüşte kendiliğinden açılır; köprü bulunamadı hatasında kapanır.
    var kuruldu: Bool { didSet { defaults.set(kuruldu, forKey: Self.anahtar) } }
    var ekranAcik = false
    private(set) var ertelenenler: [SistemKomutu] = []
    private var ertelenenGorev: Task<Void, Never>?
    private var bekleyenler: [String: CheckedContinuation<Sonuc, Never>] = [:]
    private var zamanlayicilar: [String: Task<Void, Never>] = [:]

    /// Köprü çağrısı sürüyor (Kestirmeler önde): SesOturumu bu kısa geçişte Live'ı ve sesli kipi kapatmaz.
    var gecisSuruyor: Bool { !bekleyenler.isEmpty }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        kuruldu = defaults.bool(forKey: Self.anahtar)
    }

    /// x-callback adresi. Değerler katı biçimde kodlanır: dönüş adresinin `&` ve `=` işaretleri Kestirmeler'in
    /// sorgusuna karışmasın (URLComponents sorgu değerinde bunları kodlamaz).
    nonisolated static func adres(_ k: SistemKomutu, kimlik: String) -> URL? {
        let izinli = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        func kodla(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: izinli) ?? s }
        func donus(_ s: String) -> String { "asistan://sistem-koprusu?sonuc=\(s)&k=\(kodla(kimlik))" }
        let ogeler = [("name", kestirmeAdi), ("input", "text"), ("text", k.kod),
                      ("x-success", donus("tamam")), ("x-error", donus("hata")), ("x-cancel", donus("iptal"))]
        return URL(string: "shortcuts://x-callback-url/run-shortcut?" + ogeler.map { "\($0.0)=\(kodla($0.1))" }.joined(separator: "&"))
    }

    /// Dönüş bağlantısı (`asistan://sistem-koprusu?sonuc=…&k=…[&errorMessage=…]`): (kimlik, sonuç); başka adres nil.
    nonisolated static func donusCoz(_ url: URL) -> (kimlik: String, sonuc: Sonuc)? {
        guard url.scheme?.lowercased() == "asistan", url.host?.lowercased() == "sistem-koprusu",
              let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let k = q.first(where: { $0.name == "k" })?.value, !k.isEmpty else { return nil }
        switch q.first(where: { $0.name == "sonuc" })?.value {
        case "tamam": return (k, .tamam)
        case "iptal": return (k, .iptal)
        case "hata": return (k, .hata(String((q.first(where: { $0.name == "errorMessage" })?.value ?? "").prefix(300))))
        default: return nil
        }
    }

    /// Kestirmeler köprüyü bulamadı mı (kurulmamış ya da adı değiştirilmiş).
    nonisolated static func bulunamadiMi(_ hata: String) -> Bool {
        let h = hata.lowercased()
        return ["bulunamad", "not found", "be found", "couldn’t find", "couldn't find", "could not find", "doesn’t exist", "doesn't exist"].contains { h.contains($0) }
    }

    /// `onSure`: Kestirmeler'den dönüş için uygulama ÖNDEYKEN beklenecek süre. Kestirmeler önde (Asistan askıda) geçen
    /// zaman sayılmaz; uzun ilk çalıştırma ya da izin sorusu yanlış zaman aşımı üretmez.
    func calistir(_ k: SistemKomutu, onSure: Double = 12) async -> Sonuc {
        // iOS arka plandaki uygulamaya başka uygulama açtırmaz: kısa süre öne gelmesini bekle.
        var bekleme = 0.0
        while UIApplication.shared.applicationState != .active, bekleme < 20, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250)); bekleme += 0.25
        }
        if Task.isCancelled { return .durduruldu }
        guard UIApplication.shared.applicationState == .active else { return .arkaPlanda }
        let kimlik = UUID().uuidString
        guard let url = Self.adres(k, kimlik: kimlik) else { return .acilamadi }
        let sonuc = await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Sonuc, Never>) in
                if Task.isCancelled { c.resume(returning: .durduruldu); return }
                bekleyenler[kimlik] = c
                zamanlayicilar[kimlik] = Task {
                    // Durdurma bu görev başlamadan geldiyse Kestirmeler açılmaz.
                    guard self.bekleyenler[kimlik] != nil, !Task.isCancelled else { return }
                    if !(await TelefonAdresleri.ac(url)) { self.bitir(kimlik, .acilamadi); return }
                    var gecen = 0.0
                    while gecen < onSure {
                        try? await Task.sleep(for: .milliseconds(500))
                        if Task.isCancelled { return }
                        if UIApplication.shared.applicationState == .active { gecen += 0.5 }
                    }
                    self.bitir(kimlik, .zamanAsimi)
                }
            }
        } onCancel: {
            Task { @MainActor in self.bitir(kimlik, .durduruldu) }
        }
        if sonuc == .tamam { kuruldu = true }
        if case .hata(let m) = sonuc, Self.bulunamadiMi(m) { kuruldu = false }
        return sonuc
    }

    /// `onOpenURL`: bekleyen çağrıya sonucu verir. Bağlantı köprüye aitse true.
    @discardableResult
    func geriDonus(_ url: URL) -> Bool {
        guard let d = Self.donusCoz(url) else { return false }
        bitir(d.kimlik, d.sonuc)
        return true
    }

    private func bitir(_ kimlik: String, _ s: Sonuc) {
        zamanlayicilar.removeValue(forKey: kimlik)?.cancel()
        bekleyenler.removeValue(forKey: kimlik)?.resume(returning: s)
    }

    // MARK: Yanıttan sonra çalışan komutlar

    /// Yanıt bittikten sonra çalışacak komutlar: sırayla, aynı ayarın yalnız son isteği; ekran kilidi en sonda.
    func ertele(_ k: SistemKomutu) {
        ertelenenler.removeAll { $0.ayarAnahtari == k.ayarAnahtari }
        ertelenenler.append(k)
        if let i = ertelenenler.firstIndex(of: .kilitle) { ertelenenler.append(ertelenenler.remove(at: i)) }
    }

    /// Yeni tur başladı: önceki turdan kalan (hata/iptal ile bitmiş ya da henüz beklemede olan) komutlar çalışmaz.
    func ertelenenTemizle() {
        ertelenenler = []
        ertelenenGorev?.cancel(); ertelenenGorev = nil
    }

    /// Yanıt tamamlandı: ertelenen komutlar kısa bir bekleyişten sonra (bulut ses yanıtı alabilsin) çalışır.
    /// Bu sırada yeni tur başlarsa `ertelenenTemizle` görevi iptal eder; yeni turun isteği uçuştayken internet kesilmez.
    func turBitti() {
        guard !ertelenenler.isEmpty else { return }
        let liste = ertelenenler
        ertelenenler = []
        ertelenenGorev?.cancel()
        ertelenenGorev = Task {
            try? await Task.sleep(for: .milliseconds(3000))
            for k in liste {
                guard !Task.isCancelled else { return }
                let s = await calistir(k)
                // Kilitlenen ekran dönüş yapamaz; zaman aşımı beklenen sonuçtur.
                if s != .tamam, s != .durduruldu, !(k == .kilitle && s == .zamanAsimi) {
                    TostDefteri.ortak.goster(Self.metin(k, s, dogrulandi: nil), simge: "exclamationmark.triangle")
                }
            }
        }
    }

    // MARK: Doğrulama

    /// Uygulamanın kendisinin okuyabildiği ayarlarda sonucu denetler: true doğrulandı, false tutmadı, nil okunamıyor.
    func dogrula(_ k: SistemKomutu) async -> Bool? {
        try? await Task.sleep(for: .milliseconds(400))
        switch k {
        case .anahtar(.dusukguc, let acik): return ProcessInfo.processInfo.isLowPowerModeEnabled == acik
        case .ses(let y): return abs(Double(AVAudioSession.sharedInstance().outputVolume) - Double(y) / 100) < 0.07
        case .gorunum(let karanlik):
            let stil = UIScreen.main.traitCollection.userInterfaceStyle
            return stil == .unspecified ? nil : (stil == .dark) == karanlik
        default: return nil
        }
    }

    /// Sonucu modele/kullanıcıya dönecek metne çevirir (saf).
    nonisolated static func metin(_ k: SistemKomutu, _ s: Sonuc, dogrulandi: Bool?) -> String {
        switch s {
        case .tamam:
            switch dogrulandi {
            case true?: return "\(k.ozet) (telefondan doğrulandı)."
            case false?: return "Kestirmeler işlemi tamamladı ama telefon durumu değişmemiş görünüyor: \(k.ozet.lowercased()) doğrulanamadı."
            case nil: return "\(k.ozet). Kestirmeler işlemi tamamladığını bildirdi."
            }
        case .hata(let m):
            if bulunamadiMi(m) { return "Asistan Sistem Köprüsü kestirmesi telefonda bulunamadı. Telefon işlemleri → Sistem ayarları ekranından köprüyü ekle (adını değiştirme)." }
            return "Kestirmeler işlemi tamamlayamadı" + (m.isEmpty ? "." : ": \(m)")
        case .iptal: return "İşlem Kestirmeler'de iptal edildi; ayar değişmedi."
        case .zamanAsimi: return "Kestirmeler'den yanıt gelmedi; ayarın değişip değişmediği doğrulanamadı."
        case .acilamadi: return "Kestirmeler uygulaması açılamadı; ayar değişmedi."
        case .durduruldu: return "İşlem durduruldu. Kestirmeler açılmış olabilir; ayarın değişip değişmediği doğrulanamadı."
        case .arkaPlanda: return "Asistan arka plandayken iOS Kestirmeler'i açtırmıyor; ayar değişmedi. Asistan'ı açıp yeniden söyle."
        }
    }
}
