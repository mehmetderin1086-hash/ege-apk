import Foundation
import FoundationModels
import Observation

@MainActor @Observable
final class GorevGunlugu {
    struct Adim: Identifiable {
        let id = UUID()
        let ad: String
        let baslangic = Date()
        var durum = "Çalışıyor"
    }
    private(set) var toplamBaslatilan = 0
    /// Yeniden çalıştırılınca dış etki bırakabilecek araçların sayısı; yedek model denemesinin güvenliği buna bakar.
    private(set) var yanEtkiliBaslatilan = 0
    nonisolated static let saltOkunurAraclar: Set<String> = ["suankiSaat", "havaDurumu", "ucretsizServis", "yasamServisleri", "harita", "kisiler", "webArastir", "gecmisAra", "beceriler", "altAjanlar", "webSayfaOku", "plan", "calismaAlani", "veriKazi", "webAra", "fotograflar"]
    /// Okuma ve yazma işlemi aynı araçta olanlar: listelenen işlemler yan etkilidir (yedek model tekrarında yinelenmesin).
    nonisolated static let yazanIslemler: [String: Set<String>] = ["tuval": ["olustur", "kaydet", "geridon"], "calismaAlani": ["ekle", "yaz", "gunluk"], "beceriler": ["kaydet", "sil", "iceaktar"], "harita": ["yoltarifi"], "takvim": ["ekle", "sil", "guncelle"], "hatirlatici": ["ekle", "tamamla"], "pdfIslem": ["birlestir", "bol", "dondur", "sikistir", "doldur", "imzala"]]
    /// Çıktısı güvenilmeyen (dış) içerik taşıyabilen araçlar: biri içerik döndürünce turun kalan yan etkili adımları kullanıcıya sorulur.
    /// Kararı `disIcerikGetirdi` verir (işleme ve sonuca bakar). Kullanıcının kendi verisini listeleyen araçlar (arşiv ekranı,
    /// hafıza, takvim) burada yoktur. altAjanlar: 'arastir'/'arac' görevi web okur. arkaPlanGorevi: sunucu görev sonuçları
    /// ('listele') dış içerik taşır.
    nonisolated static let disIcerikAraclari: Set<String> = ["webSayfaOku", "veriKazi", "tarayici", "webArastir", "webAra", "mcp", "gelenKutusu", "altAjanlar", "dosyalar", "indirmeler", "arkaPlanGorevi", "tuval"]
    /// Bu araçlar bayrağı yalnız sonuç güvenilmeyen-veri çerçevesi taşıyınca açar: klasör/indirme listesi, ekran açma, boş liste,
    /// MCP sunucu listesi ve hata metinleri dış içerik değildir (çerçeveyi aracın kendi kodu yazar, sayfa silemez).
    nonisolated static let cerceveliDisIcerikAraclari: Set<String> = ["webSayfaOku", "veriKazi", "tarayici", "mcp", "gelenKutusu", "dosyalar", "indirmeler", "arkaPlanGorevi", "tuval"]
    nonisolated static let disIcerikCerceveleri = ["güvenilmeyen veri", "[Harici sayfa içeriği", "[KAYNAK VERİ", "yalnız kaynak veri", "Aday dosyalar", "Bulunan sayfalar", "Adaylar:"]
    /// Çerçevesiz web araçlarının içerik taşımayan kısa hata/kapalı yanıtları (yalnız başta ve kısa yanıtta sayılır).
    nonisolated static let icerikTasimayanOnekler = ["Web araması Ayarlar'dan kapalı", "Web araması tamamlanamadı", "Görev verilmedi"]
    private(set) var adimlar: [Adim] = []

    /// Saf karar: bu çağrı yeniden çalıştırılınca dış etki bırakır mı? İşlem adı bilinen karma araçlarda işleme bakılır.
    nonisolated static func yanEtkiliMi(_ ad: String, islem: String?) -> Bool {
        if let yazanlar = yazanIslemler[ad], let islem {
            // Model "birleştir" / "sıkıştır" gibi Türkçe harfli yazabilir; araçlar da aynı biçimde katlayıp kabul eder.
            let katli = islem.lowercased().replacingOccurrences(of: "ı", with: "i")
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "tr_TR"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return yazanlar.contains(katli)
        }
        return !saltOkunurAraclar.contains(ad)
    }

    /// Saf karar: bu araç çağrısının sonucu modele güvenilmeyen (dış) içerik taşıdı mı? Boş/hata sonucu, kullanıcının kendi
    /// listesi ve yalnız 'dusun' görevli alt ajan çağrısı bayrak açmaz (kullanıcının doğrudan komutunda fazladan onay çıkmasın).
    /// Metin dışı çıktı güvenli yönde dış içerik sayılır.
    nonisolated static func disIcerikGetirdi(_ ad: String, argumanlar: Any, sonuc: Any) -> Bool {
        // Dinamik MCP araçları (`mcp_<sunucu>_<araç>`) genel `mcp` aracıyla aynı kuralı izler: çerçeveli dış içerik.
        guard disIcerikAraclari.contains(ad) || ad.hasPrefix("mcp_") else { return false }
        if let a = argumanlar as? AltAjanAraci.Arguments,
           !AltAjanlar.temizle(a.gorevler.map(AltAjanAraci.gorevCoz)).contains(where: { $0.tur != "dusun" }) { return false }
        guard let ham = sonuc as? String else { return true }
        let m = ham.trimmingCharacters(in: .whitespacesAndNewlines)
        if m.isEmpty { return false }
        if cerceveliDisIcerikAraclari.contains(ad) || ad.hasPrefix("mcp_") { return disIcerikCerceveleri.contains { m.contains($0) } }
        return !(m.count <= 400 && icerikTasimayanOnekler.contains { m.hasPrefix($0) })
    }

    /// Karma araçların argümanından işlem adı (yalnız yalıtımsız araç türleri; bilinmeyen tür nil).
    nonisolated static func islemAdi(_ argumanlar: Any) -> String? {
        switch argumanlar {
        case let a as TuvalAraci.Arguments: return a.islem
        case let a as IndirmeAraci.Arguments: return a.islem
        case let a as YasamServisleriAraci.Arguments: return a.islem
        case let a as CalismaAlaniAraci.Arguments: return a.islem
        case let a as BeceriAraci.Arguments: return a.islem
        case let a as HaritaAraci.Arguments: return a.islem
        case let a as TakvimAraci.Arguments: return a.islem
        case let a as HatirlaticiAraci.Arguments: return a.islem
        case let a as PdfAraci.Arguments: return a.islem
        default: return nil
        }
    }

    func baslat(_ ad: String, yanEtkili: Bool? = nil) -> UUID {
        toplamBaslatilan += 1
        if yanEtkili ?? !Self.saltOkunurAraclar.contains(ad) { yanEtkiliBaslatilan += 1 }
        let a = Adim(ad: Self.gorunenAd(ad))
        adimlar.append(a)
        if adimlar.count > 30 { adimlar.removeFirst(adimlar.count - 30) }
        return a.id
    }
    func bitir(_ id: UUID, durum: String) {
        guard let i = adimlar.firstIndex(where: { $0.id == id }) else { return }
        adimlar[i].durum = durum
    }
    func temizle() { adimlar = [] }

    /// Çalışan aracın görünen adından kısa, insan dilinde durum cümlesi ("Takvim" → "Takvime işleniyor…").
    nonisolated static func eylemCumlesi(_ ad: String) -> String {
        let t = ["Takvim": "Takvim işleniyor", "Hatırlatıcılar": "Hatırlatıcı ekleniyor", "Kaynak araştırması": "Web'de araştırılıyor", "Hava durumu": "Hava durumuna bakılıyor",
                 "Saat ve tarih": "Saate bakılıyor", "Harita": "Haritada aranıyor", "Kişi arama": "Kişilerde aranıyor", "Arama / mesaj hazırlama": "Mesaj hazırlanıyor",
                 "Hafıza": "Hafıza güncelleniyor", "Beceriler": "Beceri yükleniyor", "Geçmiş arama": "Geçmiş sohbetlerde aranıyor", "Alt ajanlar": "Alt ajanlar çalışıyor",
                 "MCP": "Dış araç çağrılıyor", "Çalışma alanı": "Çalışma alanı güncelleniyor", "Web sayfası": "Sayfa okunuyor", "Plan": "Plan hazırlanıyor",
                 "Ofis belgesi": "Belge oluşturuluyor", "Excel dosyası": "Excel hazırlanıyor", "Zamanlayıcı": "Zamanlayıcı kuruluyor", "Müzik": "Müzik ayarlanıyor",
                 "PDF işlemi": "PDF hazırlanıyor", "Fotoğraflar": "Galeride aranıyor", "Ücretsiz servisler": "Ücretsiz serviste aranıyor",
                 "Telefon": "Telefon ayarlanıyor"]
        return (t[ad] ?? "\(ad) çalışıyor") + "…"
    }
    nonisolated static let adlar = ["gelenKutusu": "Gelen Kutusu", "rutinler": "Zamanlanmış rutin", "arsivler": "ZIP / RAR", "ofisBelgesiOlustur": "Ofis belgesi", "excelOlustur": "Excel dosyası", "suankiSaat": "Saat ve tarih", "takvim": "Takvim", "hatirlatici": "Hatırlatıcılar", "kisiler": "Kişi arama", "iletisim": "Arama / mesaj hazırlama", "harita": "Harita", "havaDurumu": "Hava durumu", "ucretsizServis": "Ücretsiz servisler", "kisayolCalistir": "Kestirme", "uygulamaAc": "Uygulama açma", "hafiza": "Hafıza", "zamanlayici": "Zamanlayıcı", "muzik": "Müzik", "cihaz": "Telefon", "ev": "Ev", "webArastir": "Kaynak araştırması", "beceriler": "Beceriler", "gecmisAra": "Geçmiş arama", "altAjanlar": "Alt ajanlar", "mcp": "MCP", "calismaAlani": "Çalışma alanı", "webSayfaOku": "Web sayfası", "plan": "Plan", "proje": "Proje", "tarayici": "Tarayıcı", "webAra": "Web araması", "arkaPlanGorevi": "Sunucu görevi (kod)", "veriKazi": "Veri kazıma", "indirmeler": "İndirmeler", "pdfIslem": "PDF işlemi", "fotograflar": "Fotoğraflar"]
    /// Görünen ad: sözlükte yoksa dinamik MCP aracı "MCP", öbürleri kendi adıyla.
    nonisolated static func gorunenAd(_ ad: String) -> String {
        adlar[ad] ?? (ad.hasPrefix("mcp_") ? "MCP" : ad)
    }
}

/// Araç kullanılamadığında (kapalı, onay yok, bütçe doldu) metin çıktısı olmayan araçlar için hata.
nonisolated struct AracEngeli: LocalizedError { let neden: String; var errorDescription: String? { neden } }

/// Report tool lifecycle, not assumed success of an external action. No private arguments/results are logged.
/// Ayrıca ajan denetimi: araç izni (otomatik/sor/kapalı), adım bütçesi ve kalıcı denetim kaydı (AjanDefteri).
nonisolated struct IzlenenArac<T: Tool>: Tool {
    let asil: T
    let gunluk: GorevGunlugu
    var onay: OnayKapisi? = nil
    var name: String { asil.name }
    var description: String { asil.description }
    var parameters: GenerationSchema { asil.parameters }
    var includesSchemaInInstructions: Bool { asil.includesSchemaInInstructions }

    static func hataSonucu(_ hata: any Error) -> String {
        let ayrinti = (hata as? LocalizedError)?.errorDescription ?? hata.localizedDescription
        return "Araç çalışmadı: \(ayrinti) Aynı çağrıyı tekrarlama; başka bir araçla ya da yöntemle dene, olmazsa kullanıcıya kısa ve anlaşılır biçimde söyle; teknik ayrıntı gösterme."
    }

    private func engel(_ metin: String) throws -> T.Output {
        if let s = metin as? T.Output { return s }
        throw AracEngeli(neden: metin)
    }

    @concurrent func call(arguments: T.Arguments) async throws -> T.Output {
        // İptal edilmiş eski denemeden geç gelen çağrı yeni görevin bütçesini/kaydını kirletmesin.
        try Task.checkCancellation()
        let ad = GorevGunlugu.gorunenAd(name)
        let karar = await AjanDefteri.ortak.karar(name)
        switch karar {
        case .kapali:
            return try engel("\(ad) aracı kullanıcı ayarlarında kapalı. Kullanıcıya bunu söyle; mümkünse başka yolla yap.")
        case .butceDoldu:
            return try engel("Adım bütçesi doldu (\(await AjanDefteri.ortak.adimButcesi) araç çağrısı). Yeni araştırma/okuma aracı çağırma; elindekilerle SONUÇ ÜRET: kullanıcı belge/PDF/Excel istediyse ofisBelgesiOlustur ya da excelOlustur aracı (bütçeden muaf) hâlâ çalışır, önce onu çağır; eksik kalan kısmı yanıtta belirt.")
        case .sor, .gec: break
        }
        // Adım onaydan ÖNCE "Çalışıyor" olarak açılır: zaman aşımı bekçisi onay beklerken denemeyi kesmez.
        let yanEtkili = GorevGunlugu.yanEtkiliMi(name, islem: GorevGunlugu.islemAdi(arguments))
        let id = await gunluk.baslat(name, yanEtkili: yanEtkili)
        let islem = GorevGunlugu.islemAdi(arguments)
        let kayit = await AjanDefteri.ortak.adimBaslat(name, islem: islem)
        if karar == .sor, let onay,
           !(await onay.iste(baslik: "\(ad) kullanılsın mı?", ayrinti: "Ajan bu adımı çalıştırmak istiyor. (Araç izinlerinde \"Her seferinde sor\" seçili.)", zorunlu: true)) {
            await gunluk.bitir(id, durum: "Reddedildi")
            await AjanDefteri.ortak.adimBitir(kayit, durum: "Reddedildi")
            return try engel("Kullanıcı \(ad) adımına izin vermedi. Bunu kabul et; izin gerektirmeyen bir yol varsa öner.")
        }
        #if DEBUG
        // P3.3 kuru çalışma (yalnız DegerlendirmeCanliTestleri): yan etkili araç gerçekten çalıştırılmaz, başarılı sayılır.
        if AjanDefteri.kuruCalisma, yanEtkili {
            await gunluk.bitir(id, durum: "Araç yanıtladı")
            await AjanDefteri.ortak.adimBitir(kayit, durum: "Tamam")
            return try engel("KURU ÇALIŞMA: \(ad) başarılı sayıldı (gerçekte çalıştırılmadı).")
        }
        #endif
        do {
            try Task.checkCancellation()
            #if DEBUG
            if ArizaAnahtarlari.tuket(.aracHatasi) { throw ArizaHatasi.arac(ad) }
            #endif
            let sonuc = try await asil.call(arguments: arguments)
            try Task.checkCancellation()
            // Güvenilmeyen içerik modele girdi: bu turda sonraki yan etkili adımlar kullanıcıya sorulur.
            // Live turunda da geçerlidir: onay diyaloğu Live ekranında da gösterilir.
            if let onay, GorevGunlugu.disIcerikGetirdi(name, argumanlar: arguments, sonuc: sonuc) { await onay.disIcerikOkundu() }
            if KanitTamponu.veriAraciMi(name) {
                let cikti = (sonuc as? String) ?? String(describing: sonuc)
                await KanitTamponu.ortak.ekle(arac: name, cikti: cikti)
            }
            await gunluk.bitir(id, durum: "Araç yanıtladı")
            let indirmeBasladi = name == "indirmeler" && ["ekle", "tekrar"].contains(islem ?? "")
                && ((sonuc as? String)?.contains("Kimlik:") == true)
            let aracDurumu = name == "indirmeler" && ["ekle", "tekrar"].contains(islem ?? "") && !indirmeBasladi
                ? "İşlem başlamadı" : "Tamam"
            await AjanDefteri.ortak.adimBitir(kayit, durum: aracDurumu)
            // Bütçe azalınca modele sonuç üretme zamanı geldiğini bildir (belge aracına sıra gelmeden bütçe bitmesin).
            if let kalan = await AjanDefteri.ortak.kalanButce, kalan <= 4, !AjanDefteri.butceMuaf.contains(name),
               let metin = sonuc as? String, let yeni = (metin + "\n[Adım bütçesi: \(kalan) araç çağrısı kaldı. Araştırmayı bitir; belge/PDF/Excel isteniyorsa toplanan veriyle şimdi ofisBelgesiOlustur ya da excelOlustur çağır.]") as? T.Output { return yeni }
            return sonuc
        } catch {
            let iptal = Task.isCancelled || error is CancellationError
            await gunluk.bitir(id, durum: iptal ? "Durduruldu" : "Hata")
            await AjanDefteri.ortak.adimBitir(kayit, durum: iptal ? "Durduruldu" : "Hata")
            // Araç hatası yanıtı çökertmesin: metin çıktılı araçlarda hata, araç sonucu olarak modele döner
            // (model kullanıcıya doğal dille açıklar; ham teknik hata ekrana basılmaz).
            if !iptal, let sonuc = Self.hataSonucu(error) as? T.Output { return sonuc }
            throw error
        }
    }
}
