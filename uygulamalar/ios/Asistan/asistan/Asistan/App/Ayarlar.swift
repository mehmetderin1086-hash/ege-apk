import Foundation
import Observation

/// Kullanıcının değiştirebildiği ayarlar; UserDefaults'a yazılır.
@Observable
final class Ayarlar {
    enum Anahtar {
        static let model = "ayar.model"
        static let caba = "ayar.caba"
        static let sesliYanit = "ayar.sesliYanit"
        static let webArama = "ayar.webArama"
        static let yalnizAnahtar = "ayar.yalnizAnahtar"
        static let otomatikHafiza = "ayar.otomatikHafiza"
        static let istemSuzgeci = "ayar.istemSuzgeciV1"
        static let sttMotoru = "ayar.sttMotoru"
        static let whisperModeli = "ayar.whisperModeli"
        static let calismaKipi = "ayar.calismaKipi"
    }

    private let d: UserDefaults
    /// P4.2: App Group alanı (Hey Asistan kontrolüyle paylaşılır). Yalnız uygulamanın gerçek açılışı `OrtakAyarlar.suite` verir;
    /// önizleme ve testler nil verir, gerçek ortak değere dokunulmaz.
    private let ortak: UserDefaults?

    init(defaults: UserDefaults = .standard, ortak: UserDefaults? = nil) {
        d = defaults
        self.ortak = ortak
        var ilkGorunum = d.data(forKey: "ayar.gorunumV1").flatMap { try? GorunumTercihleri.coz($0) } ?? GorunumTercihleri()
        if !d.bool(forKey: "ayar.sadeSesModlariV1") {
            ilkGorunum.durum = false; ilkGorunum.hizliKomutlar = false
            if let data = try? JSONEncoder().encode(ilkGorunum) { d.set(data, forKey: "ayar.gorunumV1") }
            d.set(true, forKey: "ayar.sadeSesModlariV1")
        }
        // 19 Eki 2026: varsayılan sohbet görünümü Claude teması + Claude turuncusu (bir kez).
        if !d.bool(forKey: "ayar.claudeTemaV1") {
            ilkGorunum.sohbet = .claude; ilkGorunum.renk = "D97757"
            if let data = try? ilkGorunum.veri() { d.set(data, forKey: "ayar.gorunumV1") }
            d.set(true, forKey: "ayar.claudeTemaV1")
        }
        // 20 Eki 2026: varsayılan tema Karma (Claude renkleri + Telegram kart balonları). Değiştirilmemiş Claude teması bir kez taşınır;
        // kullanıcının elle değiştirdiği tema (Claude'dan türemiş ama farklı) korunur.
        if !d.bool(forKey: "ayar.karmaTemaV1") {
            if ilkGorunum.sohbet == nil || ilkGorunum.sohbet == .claude { ilkGorunum.sohbet = .karma; ilkGorunum.renk = "D97757" }
            if let data = try? ilkGorunum.veri() { d.set(data, forKey: "ayar.gorunumV1") }
            d.set(true, forKey: "ayar.karmaTemaV1")
        }
        // 20 Eki 2026: eski varsayılan "Açık" koyu modu yok sayıyordu; bir kez sisteme bağlanır (Ayarlar'dan yine seçilebilir).
        if !d.bool(forKey: "ayar.sistemTemaV1") {
            if ilkGorunum.tema == .acik { ilkGorunum.tema = .sistem }
            if let data = try? ilkGorunum.veri() { d.set(data, forKey: "ayar.gorunumV1") }
            d.set(true, forKey: "ayar.sistemTemaV1")
        }
        gorunum = ilkGorunum
        SohbetTemaDeposu.ortak.tema = ilkGorunum.sohbetTemasi
        // P4.2: ortak (App Group) değer önceliklidir; yoksa yerel değer (anahtar hiç yoksa varsayılan açık) ortak alana taşınır.
        let yerelHey = d.object(forKey: "ayar.heyAsistan") as? Bool ?? true
        heyAsistan = ortak.flatMap { OrtakAyarlar.heyAsistan($0) } ?? yerelHey
        if let o = ortak, OrtakAyarlar.heyAsistan(o) == nil { OrtakAyarlar.heyAsistanYaz(yerelHey, o) }
        canliArkaPlan = d.bool(forKey: "ayar.canliArkaPlanV1")
        arkaPlanUyandirma = d.bool(forKey: "ayar.arkaPlanUyandirmaV1")
        // 28 Eki: kullanıcının Live sesi değişikliği isteği. Telefonda hata veren Elif seçimini
        // bir kez doğrulanan Kore'ye taşı; bundan sonraki açık ses seçimleri korunur.
        if !d.bool(forKey: "ayar.liveSesKore20261028") {
            if d.string(forKey: "ayar.sesKimligi") == "azure:Elif" {
                d.set("claude:Kore", forKey: "ayar.sesKimligi")
            }
            d.set(true, forKey: "ayar.liveSesKore20261028")
        }
        sesKimligi = d.string(forKey: "ayar.sesKimligi") ?? "azure:Elif"
        sunucuGorevleri = d.object(forKey: "ayar.sunucuGorevleri") as? Bool ?? true
        // 19 Eki 2026: uygulamanın adı "Asistan" oldu; eski varsayılan ad kayıtlıysa bir kez yeni ada geçilir (kullanıcının kendi verdiği ad korunur).
        let kayitliAd = d.string(forKey: "ayar.dostAdi")
        dostAdi = kayitliAd == nil || kayitliAd == "Mehmet Asistan" ? "Asistan" : kayitliAd!
        dostTarzi = d.string(forKey: "ayar.dostTarzi") ?? "samimi"
        if !d.bool(forKey: "ayar.opus55TumMetinV1") {
            d.set("claude-opus-5-5", forKey: Anahtar.model)
            d.set(false, forKey: Anahtar.yalnizAnahtar)
            d.set(true, forKey: "ayar.opus55TumMetinV1")
        }
        otomatikModel = d.object(forKey: "ayar.otomatikModelV1") as? Bool ?? true
        modelKimligi = d.string(forKey: Anahtar.model) ?? "claude-opus-5-5"
        // Kullanıcının istediği otomatik çabayı bir kez etkinleştir; sonraki elle seçimleri koru.
        if !d.bool(forKey: "ayar.otomatikCabaV1") {
            d.set("auto", forKey: Anahtar.caba)
            d.set(true, forKey: "ayar.otomatikCabaV1")
        }
        caba = d.string(forKey: Anahtar.caba) ?? "auto"
        sesliYanit = d.object(forKey: Anahtar.sesliYanit) as? Bool ?? true
        // Ölü 'sürekli konuşma' ayarı ve göç işareti diskte kalmasın.
        d.removeObject(forKey: "ayar.surekliKonusma")
        d.removeObject(forKey: "ayar.tekKomutV1")
        webArama = d.object(forKey: Anahtar.webArama) as? Bool ?? true
        yalnizAnahtar = d.bool(forKey: Anahtar.yalnizAnahtar)
        nabizDakika = d.integer(forKey: "ayar.nabizDakikaV1")
        canliMotor = d.string(forKey: "ayar.canliMotorV1") ?? "claude"
        canliClaude = d.object(forKey: "ayar.canliClaudeV1") as? Bool ?? true
        antigravityOncelik = d.object(forKey: "ayar.antigravityOncelikV1") as? Bool ?? true
        sozKesme = d.object(forKey: "ayar.sozKesmeV1") as? Bool ?? true
        isaretSesleri = d.object(forKey: "ayar.isaretSesleriV1") as? Bool ?? true
        // P3.12 ses hattı: kulaklık mikrofonu ve kulaklık düğmesi varsayılan KAPALI (bugünkü HFP'siz, müziği kısan davranış).
        kulaklikMikrofonu = d.object(forKey: YolSecici.kulaklikAnahtari) as? Bool ?? false
        kumanda = d.object(forKey: YolSecici.kumandaAnahtari) as? Bool ?? false
        akilliKonusmaSonu = d.object(forKey: "ayar.akilliKonusmaSonuV1") as? Bool ?? true
        ilkSesHizli = d.object(forKey: "ayar.ilkSesHizliV1") as? Bool ?? true
        okumaHizi = d.object(forKey: "ayar.okumaHiziV1") as? Double ?? 1.0
        anlamsalHafiza = d.bool(forKey: "ayar.anlamsalHafiza")
        dikteSozlugu = d.object(forKey: "ayar.dikteSozlugu") as? Bool ?? true
        yarisSaglayici = d.integer(forKey: "ayar.yarisSaglayiciV1") == 0 ? 3 : min(3, max(1, d.integer(forKey: "ayar.yarisSaglayiciV1")))
        otomatikHafiza = d.object(forKey: Anahtar.otomatikHafiza) as? Bool ?? true
        istemSuzgeci = d.object(forKey: Anahtar.istemSuzgeci) as? Bool ?? true
        // P3.4: varsayılan KAPALI (telefonda ölçülmeden açılmaz).
        aracGruplama = d.object(forKey: "ayar.aracGruplamaV1") as? Bool ?? false
        // P4.4: ikisi de varsayılan KAPALI (gizlilik ve pil).
        spotlightIcerik = d.bool(forKey: AsistanSpotlight.icerikAnahtari)
        fotoMetinIndeksi = d.bool(forKey: FotoIndeksi.acikAnahtari)
        // P4.7: CarPlay'e bağlanınca sürüş kipi varsayılan AÇIK; elle açma (CarPlay'siz araç kiti) varsayılan kapalı.
        surusKipiOtomatik = d.object(forKey: "ayar.surusKipiOtomatik") as? Bool ?? true
        surusKipiElle = d.bool(forKey: "ayar.surusKipiElle")
        sttMotoru = d.string(forKey: Anahtar.sttMotoru) ?? "apple"
        whisperModeli = d.string(forKey: Anahtar.whisperModeli) ?? YerelWhisper.varsayilanModel
        // This release enables the requested automatic routing once; subsequent manual choices persist.
        if !d.bool(forKey: "ayar.otomatikAtolyeV1") {
            d.set("otomatik", forKey: Anahtar.calismaKipi)
            d.set(true, forKey: "ayar.otomatikAtolyeV1")
        }
        calismaKipi = d.string(forKey: Anahtar.calismaKipi) ?? "otomatik"
    }

    var gorunum: GorunumTercihleri { didSet {
        if SohbetTemaDeposu.ortak.tema != gorunum.sohbetTemasi { SohbetTemaDeposu.ortak.tema = gorunum.sohbetTemasi }
        if let veri = try? gorunum.veri() { d.set(veri, forKey: "ayar.gorunumV1") }
    } }
    var heyAsistan: Bool { didSet {
        d.set(heyAsistan, forKey: "ayar.heyAsistan")
        // P4.2: Kontrol Merkezi'ndeki Hey Asistan anahtarı da aynı değeri göstersin (yalnız değer değiştiyse yenilenir).
        if let o = ortak, OrtakAyarlar.heyAsistan(o) != heyAsistan {
            OrtakAyarlar.heyAsistanYaz(heyAsistan, o)
            OrtakAyarlar.heyKontrolunuYenile()
        }
    } }
    /// P4.2: Hey Asistan kontrolünden (App Group) gelen değeri alır; değer değiştiyse true (çağıran ses kipini yeniden seçer).
    @discardableResult func ortaktanEsitle() -> Bool {
        guard let o = ortak, let v = OrtakAyarlar.heyAsistan(o), v != heyAsistan else { return false }
        heyAsistan = v
        return true
    }
    /// P4.2: sıralı (Claude) Live ekran kilitlenince/uygulama arka plana geçince sürsün. Varsayılan KAPALI (pil ve gizlilik);
    /// gerçek zamanlı motorlar (OpenAI/Gemini) arka planda sürmez. 10 dk sessizlikte kapanır.
    var canliArkaPlan: Bool { didSet { d.set(canliArkaPlan, forKey: "ayar.canliArkaPlanV1") } }
    /// P4.3: 'Hey Asistan' beklemesi uygulama arka plana geçince (ekran kilitlenince) sürsün. Varsayılan KAPALI
    /// (turuncu mikrofon noktası sürekli yanar, pil tüketir; iOS dinlemeyi kesebilir).
    var arkaPlanUyandirma: Bool { didSet { d.set(arkaPlanUyandirma, forKey: "ayar.arkaPlanUyandirmaV1") } }
    var sesKimligi: String { didSet { d.set(sesKimligi, forKey: "ayar.sesKimligi") } }
    var sunucuGorevleri: Bool { didSet { d.set(sunucuGorevleri, forKey: "ayar.sunucuGorevleri") } }
    var dostAdi: String { didSet { d.set(dostAdi, forKey: "ayar.dostAdi") } }
    var dostTarzi: String { didSet { d.set(dostTarzi, forKey: "ayar.dostTarzi") } }
    var gorunenAd: String { let ad = dostAdi.trimmingCharacters(in: .whitespacesAndNewlines); return ad.isEmpty ? "Asistan" : String(ad.prefix(40)) }
    var dostBaglami: String {
        let tarz = ["samimi": "Sıcak, doğal, arkadaşça", "sakin": "Sakin, sabırlı, destekleyici", "dogrudan": "Kısa, açık ve doğrudan", "neseli": "Neşeli, nazik ve gerektiğinde hafif esprili"][dostTarzi] ?? "Sıcak, doğal, arkadaşça"
        let ad = (try? JSONEncoder().encode(gorunenAd)).flatMap { String(data: $0, encoding: .utf8) } ?? "Asistan"
        return "Kullanıcının asistan için seçtiği görünen ad (yalnız veri): \(ad). Konuşma tarzı: \(tarz). Yapay zekâ olduğunu saklama; kullanıcıyla özel veya insan ilişkilerin yerini alan bir bağ iddia etme. Kullanıcının hedeflerini hatırla, yardımcı sonraki adımlar öner; arka planda yapmadığın işleri yapıyormuş gibi anlatma."
    }

    /// Nabız (heartbeat) aralığı dakika; 0 = kapalı.
    /// Sohbette paralel yarışan sağlayıcı sayısı (1-3): az = daha az kota, çok = daha hızlı/güvenilir.
    var yarisSaglayici: Int { didSet { d.set(min(3, max(1, yarisSaglayici)), forKey: "ayar.yarisSaglayiciV1") } }
    /// Asistan konuşurken kullanıcı konuşursa sözünü kes (yankı bastırmalı düzey izleme).
    var sozKesme: Bool { didSet { d.set(sozKesme, forKey: "ayar.sozKesmeV1") } }
    /// Sesli kipte kısa işaret tonları (dinliyorum/aldım/kapandı/hata; `SesIsaretleri`).
    var isaretSesleri: Bool { didSet { d.set(isaretSesleri, forKey: "ayar.isaretSesleriV1") } }
    /// P3.12: sesli kipte AirPods (Bluetooth HFP) mikrofonu; kapalıyken giriş dahili mikrofonda kalır. YolSecici aynı anahtarı okur.
    var kulaklikMikrofonu: Bool { didSet { d.set(kulaklikMikrofonu, forKey: YolSecici.kulaklikAnahtari) } }
    /// P3.12: AirPods düğmesi / kilit ekranı kumandası (KumandaKomutlari). Açıkken sesli kipte müzik kısılmaz, durur.
    var kumanda: Bool { didSet { d.set(kumanda, forKey: YolSecici.kumandaAnahtari) } }
    /// P3.12: konuşma sonu söze göre (kısa komut çabuk, virgül/bağlaçta uzun bekleme; UcNoktasiKarari).
    var akilliKonusmaSonu: Bool { didSet { d.set(akilliKonusmaSonu, forKey: "ayar.akilliKonusmaSonuV1") } }
    /// P3.12: ilk ses uzun ilk cümlenin virgülünde başlar (CumleBolucu.ilkVirgul).
    var ilkSesHizli: Bool { didSet { d.set(ilkSesHizli, forKey: "ayar.ilkSesHizliV1") } }
    /// P3.12: okuma hızı (0,8-1,6; okuma çubuğu ve AirPods hız komutu).
    var okumaHizi: Double { didSet { d.set(okumaHizi, forKey: "ayar.okumaHiziV1") } }
    /// Anlamsal hafıza: olgu ve mesaj metinleri vekildeki bge-m3 ile gömülür (`UzakGomlemci`, aynı anahtarı aktör dışından okur).
    /// Varsayılan KAPALI: sunucu gömme ucu hazır olunca ve metinlerin vekile gitmesi kabul edilince açılır.
    var anlamsalHafiza: Bool { didSet { d.set(anlamsalHafiza, forKey: "ayar.anlamsalHafiza") } }
    /// Dikte sözlüğü: kişiler + düzeltme defteri cihaz içi dil modeline öğretilir (`DikteDilModeli`).
    var dikteSozlugu: Bool { didSet { d.set(dikteSozlugu, forKey: "ayar.dikteSozlugu") } }
    /// Önce Antigravity hesabındaki modelleri dene (ana Claude/ChatGPT hesaplarının kotası korunur); hata olursa doğrudan hesaplara dön.
    var antigravityOncelik: Bool { didSet { d.set(antigravityOncelik, forKey: "ayar.antigravityOncelikV1") } }
    /// Live modunda yalnız Claude modelleri kullanılsın.
    var canliClaude: Bool { didSet { d.set(canliClaude, forKey: "ayar.canliClaudeV1") } }
    /// Live motoru: "claude" (sıralı, Claude modelleri) ya da "openai" (OpenAI Realtime, anahtar gerekir).
    var canliMotor: String { didSet { d.set(canliMotor, forKey: "ayar.canliMotorV1") } }
    var nabizDakika: Int { didSet { d.set(nabizDakika, forKey: "ayar.nabizDakikaV1") } }
    var otomatikModel: Bool { didSet { d.set(otomatikModel, forKey: "ayar.otomatikModelV1") } }
    var modelKimligi: String { didSet { d.set(modelKimligi, forKey: Anahtar.model) } }
    var caba: String { didSet { d.set(caba, forKey: Anahtar.caba) } }
    var sesliYanit: Bool { didSet { d.set(sesliYanit, forKey: Anahtar.sesliYanit) } }
    var webArama: Bool { didSet { d.set(webArama, forKey: Anahtar.webArama) } }
    /// Vekili atla, doğrudan API anahtarını kullan.
    var yalnizAnahtar: Bool { didSet { d.set(yalnizAnahtar, forKey: Anahtar.yalnizAnahtar) } }
    /// Konuşmadan kalıcı olguları uygun hızlı modelle otomatik çıkar.
    var otomatikHafiza: Bool { didSet { d.set(otomatikHafiza, forKey: Anahtar.otomatikHafiza) } }
    /// Her istek ana modele gitmeden önce hızlı modelle çözümlenir (dikte düzeltme, kısıtlar, doğrulama).
    var istemSuzgeci: Bool { didSet { d.set(istemSuzgeci, forKey: Anahtar.istemSuzgeci) } }
    /// Test sorusunda (şıklı metin ya da soru fotoğrafı) üç model ayrı ayrı çözer; uzlaşma/ayrışma kontrol notunda gösterilir (P2.11).
    /// P3.4 (deneysel): süzgeç yarış adayında da çalışır ve araç gerektiren istekte yarışı keser; araçlı zincir yalnız süzgecin seçtiği
    /// araç gruplarını görür; tur bağlamı istemden ayrılıp oturum talimatına taşınır. Kapalıyken bugünkü yol değişmez.
    var aracGruplama: Bool { didSet { d.set(aracGruplama, forKey: "ayar.aracGruplamaV1") } }
    /// P4.4: Spotlight'ta sohbet başlığının yanında ilk mesajın ilk 200 karakteri (`AsistanSpotlight`, aynı anahtarı okur).
    /// Yalnız bayrak; yeniden kurulumu Ayarlar → Sistem araması ekranı tetikler.
    var spotlightIcerik: Bool { didSet { d.set(spotlightIcerik, forKey: AsistanSpotlight.icerikAnahtari) } }
    /// P4.4: fotoğraflardaki yazının cihaz içi indeksi (şarjda, ağsız arka plan görevi; `FotoIndeksi`, aynı anahtarı okur).
    var fotoMetinIndeksi: Bool { didSet { d.set(fotoMetinIndeksi, forKey: FotoIndeksi.acikAnahtari) } }
    /// P4.7: CarPlay ses yolu (`.carAudio`) görülünce sürüş kipi (`SurusKipi`).
    var surusKipiOtomatik: Bool { didSet { d.set(surusKipiOtomatik, forKey: "ayar.surusKipiOtomatik") } }
    /// P4.7: sürüş kipini ses yolundan bağımsız elle aç (CarPlay'siz Bluetooth araç kiti).
    var surusKipiElle: Bool { didSet { d.set(surusKipiElle, forKey: "ayar.surusKipiElle") } }
    /// "yerel": telefonda WhisperKit; "whisper": OpenAI (VPS aktarıcısı); "apple": yalnız Apple cihaz içi.
    var sttMotoru: String { didSet { d.set(sttMotoru, forKey: Anahtar.sttMotoru) } }
    var whisperModeli: String { didSet { d.set(whisperModeli, forKey: Anahtar.whisperModeli) } }
    var calismaKipi: String { didSet { d.set(calismaKipi, forKey: Anahtar.calismaKipi) } }
    var bulutWhisperKullan: Bool { sttMotoru == "whisper" && WhisperIstemcisi.kullanilabilir }
    var yerelWhisperKullan: Bool { sttMotoru == "yerel" }

    var model: ModelSecimi { ModelSecimi(rawValue: modelKimligi) ?? .varsayilan }
}

enum ModelSecimi: String, CaseIterable, Identifiable {
    case opus55 = "claude-opus-5-5"
    case sonnet55 = "claude-sonnet-5-5"
    // CLIProxy'nin iPhone'da doğrulanan hızlı Claude yolu. Önceki 5.5
    // kimliği sağlayıcı listesinde yoksa elle seçimde gereksiz hata veriyordu.
    case haiku55 = "claude-haiku-4-5"
    static let varsayilan: ModelSecimi = .opus55
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .opus55: "Claude Opus 5.5 (en akıllı)"
        case .sonnet55: "Claude Sonnet 5.5 (hızlı)"
        case .haiku55: "Claude Haiku 4.5 (en hızlı)"
        }
    }
}
