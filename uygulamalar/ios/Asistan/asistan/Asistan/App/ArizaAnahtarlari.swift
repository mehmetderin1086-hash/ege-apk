#if DEBUG
import Foundation

/// P3.10-arıza: yalnız DEBUG derlemede, telefondan yapay arıza tetikleme (Ayarlar → Geliştirici → Arıza modu).
/// Release ve TestFlight derlemelerinde bu dosya yoktur; telefonda denemek için `./telefona-kur.sh --sinama`.
nonisolated enum ArizaTuru: String, CaseIterable, Codable, Sendable {
    case modelKota429, modelSunucu500, akisYarida, ilkParcaGec, yerelSunucuOlu, agYok, aracHatasi, sttHatasi

    /// Ekranda görünen Türkçe ad.
    var ad: String {
        switch self {
        case .modelKota429: "Model kotası doldu (429)"
        case .modelSunucu500: "Model sunucu hatası (500)"
        case .akisYarida: "Akış yarıda kesilir"
        case .ilkParcaGec: "İlk parça 8 sn gecikir"
        case .yerelSunucuOlu: "Yerel sunucu ölür"
        case .agYok: "Ağ yok (bağlantı reddedilir)"
        case .aracHatasi: "Araç hatası"
        case .sttHatasi: "Ses dökümü (STT) hatası"
        }
    }

    /// Model isteklerini geçiş sunucusundan geçiren arızalar (TelefonProxy.taban).
    var modelArizasi: Bool { [.modelKota429, .modelSunucu500, .akisYarida, .ilkParcaGec].contains(self) }

    /// Kalıcı anahtar değil, tek seferlik eylem (ekrandaki düğme `TelefonProxy.sunucuyuOldurTest()` çağırır).
    var eylem: Bool { self == .yerelSunucuOlu }
}

/// Araç arızası: `IzlenenArac.call` içindeki `do` bloğunda fırlatılır; mevcut catch yolu adımı "Hata" olarak kapatır
/// ve metin çıktılı araçlarda `hataSonucu` metnini döndürür (fırlatma modele ulaşmaz).
nonisolated enum ArizaHatasi: LocalizedError, Equatable {
    case arac(String)

    var errorDescription: String? {
        switch self {
        case .arac(let ad): "arıza modu — \(ad) yapay olarak başarısız"
        }
    }
}

/// Arıza anahtarlarının deposu: NSLock korumalı bellek içi durum + UserDefaults ("debug.ariza.v1") kalıcılığı.
/// Bütün üyeler nonisolated: `IzlenenArac` @concurrent bağlamdan, sahte sunucu kendi kuyruğundan çağırır.
nonisolated final class ArizaDeposu: @unchecked Sendable {
    nonisolated struct Kayit: Codable, Sendable, Equatable {
        /// Kalan tetiklenme sayısı; −1 sınırsız demektir.
        var kalan: Int
        var bitis: Date
    }

    static let anahtar = "debug.ariza.v1"
    static let sinirsiz = -1
    static let varsayilanSure: TimeInterval = 1800

    /// Uygulamanın deposu. Birim testinde (XCTest) kalıcı ayarlar kirlenmesin diye her süreçte ayrı, boş bir suite kullanılır.
    static let ortak: ArizaDeposu = {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let ad = "asistan.ariza.birim.\(ProcessInfo.processInfo.processIdentifier)"
            let d = UserDefaults(suiteName: ad) ?? .standard
            d.removePersistentDomain(forName: ad)
            return ArizaDeposu(depo: d)
        }
        return ArizaDeposu(depo: .standard)
    }()

    private let kilit = NSLock()
    private let depo: UserDefaults
    private var durum: [ArizaTuru: Kayit]

    init(depo: UserDefaults) {
        self.depo = depo
        self.durum = Self.coz(depo.data(forKey: Self.anahtar))
    }

    // MARK: Saf çekirdek (test edilebilir)

    /// Süresi geçmiş kayıtları atar; `tuket` türünün kaydı varsa bir tetiklenme harcar (sınırsızda azaltmaz, 1'de kapatır).
    static func durumGuncelle(_ d: [ArizaTuru: Kayit], tuket tur: ArizaTuru, simdi: Date) -> (Bool, [ArizaTuru: Kayit]) {
        var yeni = temizle(d, simdi: simdi)
        guard let k = yeni[tur] else { return (false, yeni) }
        if k.kalan < 0 { return (true, yeni) }
        if k.kalan <= 0 { yeni[tur] = nil; return (false, yeni) }
        if k.kalan == 1 { yeni[tur] = nil } else { yeni[tur]?.kalan = k.kalan - 1 }
        return (true, yeni)
    }

    static func temizle(_ d: [ArizaTuru: Kayit], simdi: Date) -> [ArizaTuru: Kayit] {
        d.filter { $0.value.bitis > simdi && $0.value.kalan != 0 }
    }

    static func coz(_ veri: Data?) -> [ArizaTuru: Kayit] {
        guard let veri, let ham = try? JSONDecoder().decode([String: Kayit].self, from: veri) else { return [:] }
        var d: [ArizaTuru: Kayit] = [:]
        for (k, v) in ham { if let t = ArizaTuru(rawValue: k) { d[t] = v } }
        return d
    }

    static func kodla(_ d: [ArizaTuru: Kayit]) -> Data? {
        try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: d.map { ($0.key.rawValue, $0.value) }))
    }

    // MARK: Kilitli işlemler

    /// Kilit tutulurken çağrılır.
    private func kaydet(_ yeni: [ArizaTuru: Kayit]) {
        guard yeni != durum else { return }
        durum = yeni
        if yeni.isEmpty { depo.removeObject(forKey: Self.anahtar) } else if let v = Self.kodla(yeni) { depo.set(v, forKey: Self.anahtar) }
    }

    /// `tekrar` kez tetiklenir (−1 ya da 0'dan küçük: sınırsız); `sure` sonunda kendiliğinden kapanır.
    func ac(_ tur: ArizaTuru, tekrar: Int = 1, sure: TimeInterval = ArizaDeposu.varsayilanSure, simdi: Date = Date()) {
        kilit.lock(); defer { kilit.unlock() }
        var yeni = Self.temizle(durum, simdi: simdi)
        yeni[tur] = Kayit(kalan: tekrar < 0 ? Self.sinirsiz : max(1, tekrar), bitis: simdi.addingTimeInterval(max(1, sure)))
        kaydet(yeni)
    }

    func kapat(_ tur: ArizaTuru) {
        kilit.lock(); defer { kilit.unlock() }
        var yeni = durum; yeni[tur] = nil
        kaydet(yeni)
    }

    func hepsiniKapat() {
        kilit.lock(); defer { kilit.unlock() }
        kaydet([:])
    }

    /// Süresi geçmişse kaydı siler ve false döner. Tetiklenme harcamaz.
    func etkin(_ tur: ArizaTuru, simdi: Date = Date()) -> Bool {
        kilit.lock(); defer { kilit.unlock() }
        let yeni = Self.temizle(durum, simdi: simdi)
        kaydet(yeni)
        return yeni[tur] != nil
    }

    /// Etkinse bir tetiklenme harcar ve true döner (kalan 1 azalır, 0'da kapanır; −1 sınırsız).
    func tuket(_ tur: ArizaTuru, simdi: Date = Date()) -> Bool {
        kilit.lock(); defer { kilit.unlock() }
        let (sonuc, yeni) = Self.durumGuncelle(durum, tuket: tur, simdi: simdi)
        kaydet(yeni)
        return sonuc
    }

    /// Ekran için anlık görüntü (süresi geçmişler atılmış).
    func kayitlar(simdi: Date = Date()) -> [ArizaTuru: Kayit] {
        kilit.lock(); defer { kilit.unlock() }
        let yeni = Self.temizle(durum, simdi: simdi)
        kaydet(yeni)
        return yeni
    }

    var modelArizasiVar: Bool { kayitlar().keys.contains { $0.modelArizasi } }
    var herhangiEtkin: Bool { !kayitlar().isEmpty }
}

/// Uygulama kodunun kullandığı kısa yollar. `gecerli` görev yereli: birim testi kendi deposunu
/// `ArizaAnahtarlari.$gecerli.withValue(depo) { … }` ile verir, öbür (paralel) testler etkilenmez.
nonisolated enum ArizaAnahtarlari {
    @TaskLocal static var gecerli: ArizaDeposu = .ortak

    static func ac(_ tur: ArizaTuru, tekrar: Int = 1, sure: TimeInterval = ArizaDeposu.varsayilanSure) {
        gecerli.ac(tur, tekrar: tekrar, sure: sure)
    }
    static func kapat(_ tur: ArizaTuru) {
        gecerli.kapat(tur)
        if gecerli === ArizaDeposu.ortak, !gecerli.modelArizasiVar { SahteModelSunucusu.gecis.durdur() }
    }
    /// Bütün anahtarları kapatır; uygulamanın deposundaysa geçiş sunucusu da durur (trafik doğrudan gerçek tabana döner).
    static func hepsiniKapat() {
        gecerli.hepsiniKapat()
        if gecerli === ArizaDeposu.ortak { SahteModelSunucusu.gecis.durdur() }
    }
    static func etkin(_ tur: ArizaTuru) -> Bool { gecerli.etkin(tur) }
    static func tuket(_ tur: ArizaTuru) -> Bool { gecerli.tuket(tur) }
    static var modelArizasiVar: Bool { gecerli.modelArizasiVar }
    static var herhangiEtkin: Bool { gecerli.herhangiEtkin }
}
#endif
