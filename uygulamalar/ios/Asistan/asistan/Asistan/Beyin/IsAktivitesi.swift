import ActivityKit
import Foundation

/// Uzun süren isteklerde Live Activity'yi başlatır, günceller ve bitirir.
@MainActor
final class IsAktivitesi {
    /// Bu süreden uzun süren istekler için etkinlik açılır (kısa sohbetler kilit ekranını kirletmez).
    static let esikSn: Double = 6
    /// Bu süre içinde güncelleme gelmezse sistem etkinliği bayat sayar; widget "Bağlantı koptu" gösterir
    /// (uygulama öldüyse etkinlik sonsuza dek "Asistan çalışıyor" kalmasın).
    nonisolated static let bayatlikSn: TimeInterval = 90
    /// Durum değişmese de bayatlık tarihi en geç bu aralıkla yenilenir.
    nonisolated static let yenilemeSn: TimeInterval = 30
    nonisolated static func bayatlikTarihi(_ simdi: Date) -> Date { simdi.addingTimeInterval(bayatlikSn) }
    /// Saf karar: güncelleme gönderilmeli mi (durum değişti ya da bayatlık tarihi yenilenmeli).
    nonisolated static func yenilenmeli(durum: AsistanIsNitelikleri.ContentState, son: AsistanIsNitelikleri.ContentState?,
                                        sonYenileme: Date, simdi: Date) -> Bool {
        durum != son || simdi.timeIntervalSince(sonYenileme) > yenilemeSn
    }
    /// Etkinlik nesnesi Sendable değil; yalnız kimliği tutulur, işlemler yalıtılmamış yardımcıda kimlikle yapılır.
    private var etkinlikID: String?
    private var son: AsistanIsNitelikleri.ContentState?
    /// Son gönderilen istek/güncellemenin zamanı (bayatlık tarihi yenileme sayacı; her yeni etkinlikte sıfırlanır).
    private var sonYenileme = Date.distantPast
    private(set) var acik = false
    /// Kullanıcı durdurduysa (Beyin.iptal) etkinlik "Yanıt hazır" yerine "Durduruldu" ile kapanır.
    var durdurmaIstendi = false
    /// Süreç başına bir kez çalışır: önceki çalıştırmadan kalan etkinlikler (çökme, iOS'un öldürmesi, yeniden kurulum).
    private static var artikTemizligiYapildi = false

    init() {
        guard !Self.artikTemizligiYapildi else { return }
        Self.artikTemizligiYapildi = true
        // Bu süreçte açılan etkinliklerin başlangıcı hep bundan sonradır; yalnız öncekiler kapatılır.
        let acilis = Date()
        Task.detached { await IsAktivitesi.artiklariKapat(oncesi: acilis) }
    }

    /// Önceki çalıştırmadan "çalışıyor" kalmış etkinlikleri hemen kapatır; yeni istek ikinci bir etkinlik açmaz.
    nonisolated static func artiklariKapat(oncesi: Date) async {
        for a in Activity<AsistanIsNitelikleri>.activities
        where (a.activityState == .active || a.activityState == .stale) && a.attributes.baslangic < oncesi {
            var s = a.content.state
            s.bitti = true; s.hata = true; s.adim = "Önceki iş yarım kaldı"
            await a.end(.init(state: s, staleDate: nil), dismissalPolicy: .immediate)
            // Kullanıcı metni günlüğe yazılmaz; yalnız uzunluğu.
            TaniGunlugu.yaz("LIVE ACTIVITY artığı kapatıldı: \(a.attributes.istek.count) karakter")
        }
    }

    /// Saf karar: bitiş adımı metni ve hata bayrağı (durdurmada `durduruldu` bayrağı da kurulur; widget gri "Durduruldu" gösterir).
    nonisolated static func bitisMetni(hata: Bool, durduruldu: Bool) -> (adim: String, hata: Bool) {
        if hata { return ("Bir sorun oluştu; uygulamada ayrıntı var", true) }
        if durduruldu { return ("Durduruldu", true) }
        return ("Yanıt hazır", false)
    }

    /// Saf karar: bitişte gönderilecek son durum. `adim` verilirse (P4.2 vazgeçme) hata yok sayılır, "Durduruldu" hâli
    /// o metinle gösterilir. Bitişte mikrofon artık dinlemiyordur (`dinliyor` kapanır).
    nonisolated static func bitisDurumu(_ onceki: AsistanIsNitelikleri.ContentState, sureSn: Int, hata: Bool, durduruldu: Bool,
                                        ozet: String?, sohbetID: String?, adim: String?) -> AsistanIsNitelikleri.ContentState {
        var s = onceki
        let hataVar = hata && adim == nil
        let bitis = bitisMetni(hata: hataVar, durduruldu: durduruldu)
        s.bitti = true; s.hata = bitis.hata; s.sureSn = sureSn
        s.durduruldu = durduruldu && !hataVar   // hata öncelikli: sorun çıktıysa "Durduruldu" değil "Tamamlanamadı"
        s.adim = adim ?? bitis.adim
        s.ozet = ozet; s.sohbetID = sohbetID
        s.dinliyor = false
        return s
    }

    /// Kilit ekranı özetinin üst sınırı (karakter; "…" hariç).
    nonisolated static let ozetSiniri = 140
    /// P2.14 saf karar: yanıttan kilit ekranı özeti. Markdown işaretleri (*, #, `, |) atılır, satır sonları ve çoklu boşluk
    /// tek boşluk olur; sınırı aşan metin kelime ortasında değil son kelime sınırında "…" ile kesilir. Boşsa nil.
    nonisolated static func ozetle(_ metin: String) -> String? {
        var t = metin
        for isaret in ["*", "#", "`", "|"] { t = t.replacingOccurrences(of: isaret, with: "") }
        t = t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !t.isEmpty else { return nil }
        guard t.count > ozetSiniri else { return t }
        var govde = String(t.prefix(ozetSiniri))
        // Sınırdaki karakter boşluk değilse son kelime yarımdır: son boşluğa kadar geri çekilir (tek dev kelimede sert kesilir).
        if t[t.index(t.startIndex, offsetBy: ozetSiniri)] != " ", let bosluk = govde.lastIndex(of: " ") {
            govde = String(govde[..<bosluk])
        }
        return govde.trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Saf karar: o anki duruma göre gösterilecek adım metni ve plan ilerlemesi.
    nonisolated static func durum(yaziyor: Bool, calisanArac: String?, planTamam: Int, planToplam: Int) -> AsistanIsNitelikleri.ContentState {
        let adim = calisanArac.map { "\($0) çalışıyor" } ?? (yaziyor ? "Yanıt yazılıyor" : "Düşünüyor")
        return .init(adim: adim, tamamlanan: planTamam, toplam: planToplam)
    }

    func baslat(istek: String, baslangic: Date, durum: AsistanIsNitelikleri.ContentState) {
        guard etkinlikID == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        durdurmaIstendi = false   // önceki istekte etkinlik açılmadan basılmış Durdur bu işe taşınmasın
        let n = AsistanIsNitelikleri(istek: String(istek.prefix(80)), baslangic: baslangic)
        let simdi = Date()
        do {
            etkinlikID = try Activity.request(attributes: n, content: .init(state: durum, staleDate: Self.bayatlikTarihi(simdi)), pushType: nil).id
        } catch {
            // Arka planda istek reddedilir (visibility); neden görünsün ki kilit ekranı kartının neden çıkmadığı anlaşılsın.
            etkinlikID = nil
            TaniGunlugu.yaz("LIVE ACTIVITY açılamadı: \(error)")
        }
        son = durum; sonYenileme = simdi; acik = etkinlikID != nil
        if acik { TaniGunlugu.yaz("LIVE ACTIVITY başladı: \(istek.count) karakter") }
    }

    func guncelle(_ durum: AsistanIsNitelikleri.ContentState) async {
        let simdi = Date()
        guard let id = etkinlikID, Self.yenilenmeli(durum: durum, son: son, sonYenileme: sonYenileme, simdi: simdi) else { return }
        son = durum; sonYenileme = simdi
        await Self.guncelle(id: id, durum, bayatlik: Self.bayatlikTarihi(simdi))
    }

    /// `ozet`/`sohbetID` (P2.14): kilit ekranında yanıt özeti ve "Aç" bağlantısı (`asistan://sohbet?kimlik=`).
    /// `adim` (P4.2): verilirse bitiş metni o olur ve etkinlik gri "Durduruldu" hâlinde kapanır (ör. "Komut duyulmadı");
    /// hata yok sayılır.
    func bitir(sureSn: Int, hata: Bool, ozet: String? = nil, sohbetID: String? = nil, adim: String? = nil) async {
        let durduruldu = durdurmaIstendi || adim != nil
        durdurmaIstendi = false
        guard let id = etkinlikID else { return }
        let s = Self.bitisDurumu(son ?? .init(adim: ""), sureSn: sureSn, hata: hata, durduruldu: durduruldu,
                                 ozet: ozet, sohbetID: sohbetID, adim: adim)
        etkinlikID = nil; son = nil; sonYenileme = .distantPast; acik = false
        await Self.bitir(id: id, s)
    }

    nonisolated private static func etkinlik(_ id: String) -> Activity<AsistanIsNitelikleri>? {
        Activity<AsistanIsNitelikleri>.activities.first { $0.id == id }
    }
    nonisolated private static func guncelle(id: String, _ s: AsistanIsNitelikleri.ContentState, bayatlik: Date) async {
        await etkinlik(id)?.update(.init(state: s, staleDate: bayatlik))
    }
    nonisolated private static func bitir(id: String, _ s: AsistanIsNitelikleri.ContentState) async {
        await etkinlik(id)?.end(.init(state: s, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(8)))
    }
    /// Test/tanı: şu an açık etkinlik sayısı.
    nonisolated static var acikSayisi: Int { Activity<AsistanIsNitelikleri>.activities.filter { $0.activityState == .active }.count }
}
