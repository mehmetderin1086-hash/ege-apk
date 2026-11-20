import Foundation
import AVFoundation
import Observation
import UserNotifications

/// P4.7: Sürüş kipi. CarPlay ses yolu (`.carAudio`) görülünce (Ayarlar `surusKipiOtomatik`, varsayılan açık) ya da
/// elle (`surusKipiElle`; CarPlay'siz Bluetooth araç kiti `.bluetoothHFP/A2DP` verir, otomatik kip onu tanımaz) açılır.
/// Açıkken: yanıt en çok 2 kısa cümle (talimat eki + seslendirmede kırpma), onay sesle sorulur (dokunmalı diyalog da
/// açık kalır), belge/dosya üretimi ertelenir ve araba bağlantısı kesilince kullanıcının asıl isteği bildirimle hatırlatılır
/// (dokununca `TetikBildirimi` → `GorevKopru.teslimEt` isteği yeniden gönderir).
@MainActor
@Observable
final class SurusKipi {
    static let ortak = SurusKipi()

    /// Sürüş kipi şu an etkin mi (Beyin, SesOturumu, Ofis/Excel araçları okur).
    private(set) var aktif = false
    /// Son ses yolunda CarPlay çıkışı var mı (ayardan bağımsız; Ayarlar ekranında gösterilir).
    private(set) var arabada = false
    /// "Bu sürüşte kapat": oturumluk; araba bağlantısı kesilince kendiliğinden sıfırlanır.
    private(set) var elleKapali = false
    /// CarPlay sahnesi bağlıyken kip zorunlu açıktır (`CarPlaySahnesi`, ASISTAN_CARPLAY bayrağı arkasında).
    var carPlayBagli = false { didSet { if carPlayBagli != oldValue { guncelle() } } }
    /// Bu turun kullanıcı isteği (Beyin.gonder yazar): belge ertelenince araç özeti değil bu asıl istek saklanır.
    var sonIstek: String?
    /// Sürüşte ertelenen istekler (en çok `enFazlaErtelenen`, kalıcı).
    private(set) var ertelenenler: [String]

    nonisolated static let ertelenenAnahtari = "surus.ertelenen.v1"
    nonisolated static let enFazlaErtelenen = 5
    /// Ertelenen istek bildiriminin kimlik öneki ('tetik.' / 'ertele.' önekleriyle çakışmaz).
    nonisolated static let bildirimOnek = "surus."
    /// Belge aracı ertelendiğinde modele dönen metin.
    nonisolated static let ertelemeYaniti = "Sürüş kipinde belge üretimi ertelendi; araba bağlantısı kesilince bildirimle hatırlatılacak. Kullanıcıya bunu tek cümleyle söyle."
    /// Sürüş kipinde modele eklenen talimat (Beyin.gonder ve paralel yarışın sistem istemi).
    nonisolated static let talimatEki = "\n[Sürüş kipi: kullanıcı araç kullanıyor. En çok 2 kısa cümleyle yanıt ver; liste, tablo, bağlantı ve ekrana bakmayı gerektiren ayrıntı verme. Belge, dosya ve tablo üretme; isteği 'arabadan inince hatırlatacağım' diye ertele. Onay gerekirse sesli sor, ekrana dokunmasını isteme.]"

    /// `baslat` bağlar; testler ses yolu gözlemcisi kurmadan doğrudan atar. Güçlü başvuru: Ayarlar SurusKipi'ni tutmaz
    /// (döngü yok); zayıf olunca tek başına verilen Ayarlar hemen düşüp otomatik kip sessizce kapalı sayılıyordu.
    @ObservationIgnored var ayarlar: Ayarlar?
    @ObservationIgnored private var sonElle = false
    /// Son değerlendirilen çıkışlar ("Bu sürüşte kapat" ses yolunu yeniden okumadan aynı yolla karar versin).
    @ObservationIgnored private var sonCikislar: [AVAudioSession.Port]?
    /// CarPlay sahnesinin sesli kipi açabilmesi için (uygulama açılışında bağlanır).
    @ObservationIgnored private(set) weak var ses: SesOturumu?
    @ObservationIgnored private var gozlemci: (any NSObjectProtocol)?
    @ObservationIgnored private let d: UserDefaults
    /// Hatırlatma gönderici; testte sahtelenir. true: bildirimler kuruldu (liste boşaltılır), false: izin yok (liste kalır).
    @ObservationIgnored var hatirlatici: @MainActor ([String]) async -> Bool = { await SurusKipi.bildirimleriGonder($0) }

    init(defaults: UserDefaults = .standard) {
        d = defaults
        ertelenenler = Array((defaults.stringArray(forKey: Self.ertelenenAnahtari) ?? []).prefix(Self.enFazlaErtelenen))
    }

    // MARK: Başlatma ve ses yolu

    /// Açılışta bir kez: ses yolu değişimi izlenir, ayar değişince kip yeniden değerlendirilir.
    func baslat(ayarlar: Ayarlar, ses: SesOturumu? = nil) {
        self.ayarlar = ayarlar
        if let ses { self.ses = ses }
        if gozlemci == nil {
            // Gözlemci kapanışı sistem kuyruğundan gelebilir: @Sendable, ana aktöre yalnız Task ile geçilir.
            // (Ana aktöre bağlı sınıf Sendable'dır; `weak var` yakalaması eşzamanlı kapanışta derlenmediği için güçlü `let`.)
            let kip = self
            gozlemci = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { @Sendable _ in
                Task { @MainActor in kip.guncelle() }
            }
        }
        ayarlariIzle()
        guncelle()
    }

    /// `surusKipiOtomatik` / `surusKipiElle` değişince kip yeniden değerlendirilir (izleme her değişimde yenilenir).
    private func ayarlariIzle() {
        guard let a = ayarlar else { return }
        let kip = self
        withObservationTracking {
            _ = a.surusKipiOtomatik
            _ = a.surusKipiElle
        } onChange: { @Sendable in
            // onChange değişiklikten ÖNCE çağrılır: yeni değer ana aktörde, sonraki turda okunur.
            Task { @MainActor in kip.guncelle(); kip.ayarlariIzle() }
        }
    }

    /// Kipi yeniden değerlendirir. `cikislar` verilmezse geçerli ses yolu okunur (test kendi çıkışlarını verir).
    func guncelle(cikislar: [AVAudioSession.Port]? = nil) {
        let c = cikislar ?? AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType)
        sonCikislar = c
        arabada = Self.arabaMi(c)
        let elle = ayarlar?.surusKipiElle ?? false
        // Araba bağlantısı kesildi: "bu sürüşte kapat" sonraki sürüşe taşınmaz. Elle yeniden açmak da onu kaldırır.
        if elleKapali, (!arabada && !carPlayBagli) || (elle && !sonElle) { elleKapali = false }
        sonElle = elle
        let yeni = carPlayBagli || Self.karar(elle: elle, otomatik: ayarlar?.surusKipiOtomatik ?? false,
                                              arabada: arabada, elleKapali: elleKapali)
        guard yeni != aktif else { return }
        aktif = yeni
        TaniGunlugu.yaz("SÜRÜŞ KİPİ: " + (yeni ? "açıldı" : "kapandı"))
        if !yeni {
            sonIstek = nil
            Task { await hatirlat() }
        }
    }

    /// Ayarlar'daki "Bu sürüşte kapat": araba bağlantısı kesilene dek otomatik kip açılmaz.
    func buSurusteKapat() {
        ayarlar?.surusKipiElle = false
        elleKapali = arabada
        guncelle(cikislar: sonCikislar)
    }

    // MARK: Erteleme

    /// Belge üreten araç çağrıldı. Sürüş kipindeyse bu turun asıl isteği (yoksa araç özeti) ertelenir ve modele dönecek
    /// metin döner; değilse nil (araç olağan işini yapar).
    func belgeyiErtele(ozet: String) -> String? {
        guard aktif else { return nil }
        ertele(yedek: ozet)
        return Self.ertelemeYaniti
    }

    /// `sonIstek`'i (boşsa `yedek`i) ertelenenlere ekler; aynı istek ikinci kez eklenmez, en eski düşer.
    func ertele(yedek: String = "") {
        let s = (sonIstek ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let istek = s.isEmpty ? yedek.trimmingCharacters(in: .whitespacesAndNewlines) : s
        guard !istek.isEmpty else { return }
        ertelenenler = Self.ekle(istek, ertelenenler)
        kaydet()
    }

    /// Ertelenenleri listeden çıkarır (Ayarlar'daki "Şimdi gönder" / "Temizle").
    func cikar(_ istekler: [String]) {
        ertelenenler.removeAll { istekler.contains($0) }
        kaydet()
    }

    /// Kip kapandı: ertelenen istekler bildirimle hatırlatılır; izin yoksa liste Ayarlar'da kalır.
    func hatirlat() async {
        let liste = ertelenenler
        guard !liste.isEmpty, !aktif else { return }
        guard await hatirlatici(liste) else { return }
        cikar(liste)
    }

    private func kaydet() { d.set(ertelenenler, forKey: Self.ertelenenAnahtari) }

    // MARK: Saf mantık

    /// Çıkışlardan biri CarPlay ses yolu mu? (Bluetooth araç kiti CarPlay'siz `.bluetoothHFP/A2DP` verir: false.)
    nonisolated static func arabaMi(_ cikislar: [AVAudioSession.Port]) -> Bool { cikislar.contains(.carAudio) }

    /// Kip kuralı: `!elleKapali && (elle || (otomatik && arabada))`.
    nonisolated static func karar(elle: Bool, otomatik: Bool, arabada: Bool, elleKapali: Bool) -> Bool {
        !elleKapali && (elle || (otomatik && arabada))
    }

    /// Ertelenen listesine ekleme: aynısı öne alınır, en çok `enFazlaErtelenen` (en eski düşer).
    nonisolated static func ekle(_ istek: String, _ liste: [String]) -> [String] {
        var l = liste.filter { $0 != istek }
        l.append(istek)
        return Array(l.suffix(enFazlaErtelenen))
    }

    /// Onay yanıtı sözcük kararı (sözcük düzeyi: "yapma" "yap" sayılmaz). true/false; ikisi birden ya da hiçbiri nil.
    /// SesOturumu bunu yalnız RET için kullanır (fail-closed); onay `SesliOnayKarari`nın tam eşleşme + enerji kapısından geçer.
    nonisolated static func evetHayir(_ metin: String) -> Bool? {
        let sozcukler = Set(SesliOnayKarari.normalle(metin).split(separator: " ").map(String.init))
        let evet = !sozcukler.isDisjoint(with: evetSozcukleri)
        let hayir = !sozcukler.isDisjoint(with: hayirSozcukleri)
        if evet == hayir { return nil }
        return evet
    }
    nonisolated static let evetSozcukleri: Set<String> = ["evet", "tamam", "olur", "onaylıyorum", "onayla", "yap", "gönder", "ara"]
    nonisolated static let hayirSozcukleri: Set<String> = ["hayır", "iptal", "vazgeç", "dur", "yapma", "istemiyorum", "gönderme", "arama", "yok"]

    /// Metni ilk `cumle` cümlede keser; kesilen metin her zaman özgün metnin ÖNEKİdir (akış hâlinde büyüyen metne
    /// uygulanınca kararlı kalır: `Konusmaci`nın cümle bölücüsü kaldığı yerden sürer). Cümle sınırı `CumleBolucu` ile
    /// aynıdır: .!?… ardından boşluk/satır sonu ya da metin sonu; 20+ karakterlik satır da bir cümle sayılır.
    nonisolated static func kisalt(_ yanit: String, cumle: Int = 2) -> String {
        guard cumle > 0 else { return "" }
        let k = Array(yanit)
        var sayi = 0
        var biriken = ""
        func dolu(_ s: String) -> Int { s.trimmingCharacters(in: .whitespacesAndNewlines).count }
        for i in k.indices {
            let c = k[i]
            biriken.append(c)
            if ".!?…".contains(c) {
                let sonraki: Character = i + 1 < k.count ? k[i + 1] : " "
                guard sonraki.isWhitespace || sonraki.isNewline else { continue }
                if dolu(biriken) >= 2 {
                    sayi += 1
                    if sayi >= cumle { return String(k[...i]) }
                }
                biriken = ""
            } else if c == "\n", dolu(biriken) >= 20 {
                sayi += 1
                if sayi >= cumle { return String(k[..<i]) }
                biriken = ""
            }
        }
        return yanit
    }

    // MARK: Bildirim

    /// Ertelenen her istek için anında yerel bildirim (dokununca istek `TetikDeposu.istemAnahtari` ile yeniden gönderilir).
    /// İzin yoksa hiçbir şey kurulmaz ve false döner.
    nonisolated static func bildirimleriGonder(_ liste: [String]) async -> Bool {
        let merkez = UNUserNotificationCenter.current()
        let ayar = await merkez.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(ayar.authorizationStatus) else { return false }
        for istek in liste {
            try? await merkez.add(UNNotificationRequest(identifier: bildirimOnek + UUID().uuidString, content: bildirimIcerigi(istek), trigger: nil))
        }
        return true
    }

    /// Bildirim içeriği: başlık sabit, gövde isteğin kendisi (≤300 karakter), userInfo istem.
    nonisolated static func bildirimIcerigi(_ istek: String) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = "Sürüşte ertelenen istek"
        c.body = String(istek.prefix(300))
        c.sound = .default
        c.userInfo = [TetikDeposu.istemAnahtari: istek]
        return c
    }
}

extension Beyin {
    /// P4.7: sürüş kipi açıksa modele eklenecek talimat; değilse boş.
    nonisolated static func surusTalimati(aktif: Bool) -> String { aktif ? SurusKipi.talimatEki : "" }
}
