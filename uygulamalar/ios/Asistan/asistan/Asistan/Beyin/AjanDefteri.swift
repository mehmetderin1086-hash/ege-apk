import Foundation
import Observation

/// Ajanın denetim katmanı: araç izinleri, görev geçmişi (denetim günlüğü), adım bütçesi ve pahalı model bütçesi.
/// Kayıtlar yalnız telefonda tutulur (Application Support/ajan-gorevleri.json); araç argümanı/çıktısı yazılmaz.
@MainActor @Observable
final class AjanDefteri {
    static let ortak = AjanDefteri()

    // MARK: Araç izinleri (madde 10)
    nonisolated enum Politika: String, Codable, CaseIterable, Sendable { case otomatik = "Otomatik", sor = "Her seferinde sor", kapali = "Kapalı" }
    nonisolated enum Karar: Equatable, Sendable { case gec, sor, kapali, butceDoldu }

    private let d: UserDefaults
    private let dosya: URL
    private(set) var politikalar: [String: Politika]

    /// P4.5: dinamik MCP araçları ("mcp_<sunucu>_<araç>") kendi kayıtları yoksa genel `mcp` aracının iznini devralır.
    func politika(_ arac: String) -> Politika {
        politikalar[arac] ?? (arac.hasPrefix("mcp_") ? politikalar["mcp"] : nil) ?? .otomatik
    }
    func politikaAta(_ arac: String, _ p: Politika) {
        politikalar[arac] = p == .otomatik ? nil : p
        d.set(politikalar.mapValues(\.rawValue), forKey: "ajan.politikalar")
    }

    // MARK: Adım bütçesi (madde 3)
    var adimButcesi: Int { didSet { d.set(adimButcesi, forKey: "ajan.adimButcesi") } }
    private(set) var buIstekteAdim = 0

    /// Araç çağrısından hemen önce: politika + bütçe kararı.
    /// Sonuç üreten araçlar adım bütçesinden muaftır: araştırma bütçeyi bitirse de belge/Excel/plan/hafıza yazılabilsin.
    nonisolated static let butceMuaf: Set<String> = ["ofisBelgesiOlustur", "excelOlustur", "plan", "hafiza", "proje", "calismaAlani", "pdfIslem"]

    func karar(_ arac: String) -> Karar {
        let p = politika(arac)
        if p == .kapali { return .kapali }
        if Self.butceMuaf.contains(arac) { return p == .sor ? .sor : .gec }
        if adimButcesi > 0, buIstekteAdim >= adimButcesi { return .butceDoldu }
        buIstekteAdim += 1
        return p == .sor ? .sor : .gec
    }

    /// Bu istekte kalan araç çağrısı (sınırsızsa nil).
    var kalanButce: Int? { adimButcesi > 0 ? max(0, adimButcesi - buIstekteAdim) : nil }

    // MARK: Görev geçmişi ve denetim günlüğü (madde 11)
    struct AdimKaydi: Codable, Equatable, Identifiable, Sendable {
        var id = UUID()
        let arac: String
        var islem: String? = nil
        let zaman: Date
        var sure: Double = 0
        var durum: String
    }
    struct GorevKaydi: Codable, Equatable, Identifiable, Sendable {
        var id = UUID()
        let istek: String
        /// Modele giden asıl istek (görünen metinden farklı olabilir: paylaşım, yeniden üretim); yeniden çalıştırmada kullanılır.
        var asil: String?
        let baslangic: Date
        var sure: Double = 0
        var model: String?
        var adimlar: [AdimKaydi] = []
        var sonuc: String = ""
        var durum: String = "Sürüyor"
    }
    private(set) var gorevler: [GorevKaydi] = []
    private var aktifGorev: UUID?
    static let enFazlaGorev = 200

    func gorevBaslat(_ istek: String, asil: String? = nil) {
        buIstekteAdim = 0
        let g = GorevKaydi(istek: String(istek.prefix(400)), asil: asil.map { String($0.prefix(8000)) }, baslangic: .now)
        gorevler.insert(g, at: 0)
        if gorevler.count > Self.enFazlaGorev { gorevler.removeLast(gorevler.count - Self.enFazlaGorev) }
        aktifGorev = g.id
        kaydet()
    }

    @discardableResult
    func adimBaslat(_ arac: String, islem: String? = nil) -> UUID? {
        guard let aktifGorev, let i = gorevler.firstIndex(where: { $0.id == aktifGorev }) else { return nil }
        let a = AdimKaydi(arac: arac, islem: islem, zaman: .now, durum: "Çalışıyor")
        gorevler[i].adimlar.append(a)
        ArkaPlanSurdurucu.ortak.ilerle(adim: gorevler[i].adimlar.count)
        return a.id
    }

    func adimBitir(_ id: UUID?, durum: String) {
        guard let id, let aktifGorev, let i = gorevler.firstIndex(where: { $0.id == aktifGorev }),
              let j = gorevler[i].adimlar.firstIndex(where: { $0.id == id }) else { return }
        gorevler[i].adimlar[j].durum = durum
        gorevler[i].adimlar[j].sure = Date().timeIntervalSince(gorevler[i].adimlar[j].zaman)
    }

    func gorevBitir(model: String?, sonuc: String, durum: String) {
        guard let aktifGorev, let i = gorevler.firstIndex(where: { $0.id == aktifGorev }) else { return }
        gorevler[i].model = model
        gorevler[i].sure = Date().timeIntervalSince(gorevler[i].baslangic)
        gorevler[i].sonuc = String(sonuc.prefix(300))
        gorevler[i].durum = durum
        self.aktifGorev = nil
        kaydet()
        if let m = model, Self.pahali(m), durum == "Tamamlandı" { pahaliSay() }
    }

    func gecmisiTemizle() { gorevler = []; kaydet() }

    #if DEBUG
    /// P3.3 kuru çalışma: açıkken yan etkili araçlar (`IzlenenArac`) gerçekten çalıştırılmaz, adım 'Tamam' sayılır.
    /// Yalnız `DegerlendirmeCanliTestleri` açar ve sonunda kapatır. Kısa yollar (müzik, yerel komut)
    /// sarmalayıcıdan geçmediği için bu kipten etkilenmez; o yollar canlı testte çalıştırılmaz.
    nonisolated(unsafe) static var kuruCalisma = false
    #endif

    // MARK: Pahalı model bütçesi (madde 12)
    /// Günlük Opus/Fable yanıt sınırı; 0 = sınırsız.
    var pahaliGunlukSinir: Int { didSet { d.set(pahaliGunlukSinir, forKey: "ajan.pahaliSinir") } }
    nonisolated static func pahali(_ model: String) -> Bool {
        let m = model.lowercased(); return m.contains("opus") || m.contains("fable")
    }
    var bugunPahali: Int { d.integer(forKey: "ajan.pahali." + KullanimDefteri.gunAnahtari(.now)) }
    var pahaliBittiMi: Bool { pahaliGunlukSinir > 0 && bugunPahali >= pahaliGunlukSinir }
    private func pahaliSay() { d.set(bugunPahali + 1, forKey: "ajan.pahali." + KullanimDefteri.gunAnahtari(.now)) }

    /// Model sırasından günlük sınırı aşan pahalı modelleri çıkarır (zorla seçilen model hariç); hepsi pahalıysa listeyi korur.
    func butceyeGoreSuz(_ modeller: [String], zorla: String?) -> [String] {
        guard pahaliBittiMi else { return modeller }
        let suzulmus = modeller.filter { $0 == zorla || !Self.pahali($0) }
        return suzulmus.isEmpty ? modeller : suzulmus
    }

    // MARK: Eleştirmen (madde 9) ve beceri önerisi (madde 6) ayarları
    var elestirmen: Bool { didSet { d.set(elestirmen, forKey: "ajan.elestirmen") } }
    var beceriOnerisi: Bool { didSet { d.set(beceriOnerisi, forKey: "ajan.beceriOnerisi") } }

    init(defaults: UserDefaults = .standard, dosya: URL? = nil) {
        d = defaults
        let taban = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        self.dosya = dosya ?? taban.appendingPathComponent("ajan-gorevleri.json")
        politikalar = (d.dictionary(forKey: "ajan.politikalar") as? [String: String] ?? [:]).compactMapValues(Politika.init(rawValue:))
        // Eski varsayılan (20) hiç diske yazılmadı; kayıtlı değer yalnız kullanıcının elle seçimidir (0 = Sınırsız), göçle ezilmez.
        adimButcesi = d.object(forKey: "ajan.adimButcesi") as? Int ?? 30
        pahaliGunlukSinir = d.object(forKey: "ajan.pahaliSinir") as? Int ?? 0
        elestirmen = d.object(forKey: "ajan.elestirmen") as? Bool ?? true
        beceriOnerisi = d.object(forKey: "ajan.beceriOnerisi") as? Bool ?? true
        gorevler = (try? Data(contentsOf: self.dosya)).flatMap { try? JSONDecoder().decode([GorevKaydi].self, from: $0) } ?? []
        // Uygulama yarıda kapandıysa "Sürüyor" kalan görevler kesildi sayılır.
        for i in gorevler.indices where gorevler[i].durum == "Sürüyor" { gorevler[i].durum = "Kesildi" }
    }

    /// Yazımlar tek seri kuyrukta, sırayla: eski anlık görüntü yenisinin üstüne yazılamaz.
    nonisolated private static let yazmaKuyrugu = DispatchQueue(label: "asistan.ajan-defteri", qos: .utility)
    private func kaydet() {
        let v = gorevler, url = dosya
        Self.yazmaKuyrugu.async { try? JSONEncoder().encode(v).write(to: url, options: .atomic) }
    }
}
