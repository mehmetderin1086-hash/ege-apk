import EventKit
import Foundation
import WidgetKit

/// P3.11: widget anlığını (`DersGunu`, App Group Widget/anlik.json) ana uygulamada tazeler ve zaman çizelgelerini yeniler.
/// Tetikler: açılış ve öne geliş (AsistanApp), takvim değişikliği (`EKEventStoreChanged`), başarılı yanıt (`Beyin.tamamla`)
/// ve Nabız (`NabizMotoru.calistir`; arka planda yalnız Ayarlar → Nabız açıksa çalışır, varsayılan kapalı).
/// Takvim izni yoksa izin sorulmaz; olaylar boş yazılır ve widget "Takvim izni için Asistan'ı aç" der.
/// Bütçe: EventKit sorgusu ana aktör dışında koşar ve öne gelişte 5 dk'da bir yapılır (takvim değişikliği bildirimi
/// bu sınırı `zorla` ile aşar); zaman çizelgesi yalnız `anlikTurleri` için ve en çok 10 dk'da bir yenilenir.
@MainActor
enum WidgetYenileyici {
    /// Sorgu ana aktör dışından da çağrılır (`olaylariOku`); EKEventStore bu kullanımda iş parçacığı güvenlidir.
    private nonisolated(unsafe) static let depo = EKEventStore()
    private static var gozlemci: NSObjectProtocol?
    private static var bekleyen: Task<Void, Never>?
    /// Bir anlıkta en çok bu kadar olay tutulur (36 saatlik pencere).
    nonisolated static let enFazlaOlay = 40
    /// `DersGunu.oku` anlığını gösteren widget türleri (AsistanKontrol: Bugün, Sıradaki ders); öbürleri sabit içeriklidir.
    static let anlikTurleri = ["com.mehmetderin.asistan.bugun", "com.mehmetderin.asistan.siradaki"]
    /// Art arda `reloadTimelines` çağrıları bu süreden sık yapılmaz (widget yenileme bütçesi).
    static let enAzYenilemeAraligi: TimeInterval = 600
    /// Öne gelişte takvim sorgusu bu süreden sık yapılmaz.
    static let enAzTakvimAraligi: TimeInterval = 300
    private static var sonYenileme: Date?
    private static var yenilemeGorevi: Task<Void, Never>?
    private static var sonTakvimSorgusu: Date?
    private static var takvimGorevi: Task<Void, Never>?
    private static var takvimYenidenIstendi = false

    /// Birim/arayüz testlerinde gerçek App Group dosyası kirletilmez.
    private static var etkin: Bool {
        ProcessInfo.processInfo.environment["ASISTAN_TEST"] != "1" && NSClassFromString("XCTestCase") == nil
    }

    /// Takvim değişikliklerini dinlemeye başlar (bir kez). Art arda gelen bildirimler 2 sn içinde birleştirilir.
    static func baslat() {
        guard etkin, gozlemci == nil else { return }
        // Bildirim herhangi bir kuyruktan gelebilir: kapanış @Sendable, iş ana aktöre taşınır.
        gozlemci = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: depo, queue: nil) { @Sendable _ in
            Task { @MainActor in WidgetYenileyici.gecikmeliYaz() }
        }
    }

    private static func gecikmeliYaz() {
        bekleyen?.cancel()
        bekleyen = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            takvimdenYaz(zorla: true)
        }
    }

    /// Önümüzdeki 36 saatin tüm gün olmayan etkinliklerini yazar; var olan son yanıt korunur. Değişiklik yoksa
    /// widget yeniden yüklenmez (arka plan yenileme bütçesi harcanmasın). Sorgu ana aktörü tutmaz; `zorla` olmadıkça
    /// son sorgudan 5 dk geçmeden yinelenmez (takvim değişikliği bildirimi `zorla` ile gelir).
    static func takvimdenYaz(simdi: Date = .now, zorla: Bool = false) {
        guard etkin else { return }
        if takvimGorevi != nil { takvimYenidenIstendi = true; return }
        if !zorla, let son = sonTakvimSorgusu, Date().timeIntervalSince(son) < enAzTakvimAraligi { return }
        sonTakvimSorgusu = Date()
        let izin = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        takvimGorevi = Task { @MainActor in
            let olaylar = izin ? await olaylariOku(simdi: simdi) : []
            takvimGorevi = nil
            takvimiUygula(olaylar: olaylar, izin: izin, simdi: simdi)
            if takvimYenidenIstendi { takvimYenidenIstendi = false; takvimdenYaz(simdi: .now, zorla: true) }
        }
    }

    /// EventKit sorgusu ve eşleme ana aktör dışında koşar.
    @concurrent private nonisolated static func olaylariOku(simdi: Date) async -> [WidgetAnlik.Olay] {
        let p = depo.predicateForEvents(withStart: simdi, end: simdi.addingTimeInterval(DersGunu.pencere), calendars: nil)
        return depo.events(matching: p)
            .filter { !$0.isAllDay && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .prefix(enFazlaOlay)
            .map { e in
                let yer = e.location?.trimmingCharacters(in: .whitespacesAndNewlines)
                return WidgetAnlik.Olay(baslik: e.title?.isEmpty == false ? e.title! : "Etkinlik",
                                        baslangic: e.startDate, bitis: e.endDate,
                                        yer: (yer?.isEmpty ?? true) ? nil : yer)
            }
    }

    private static func takvimiUygula(olaylar: [WidgetAnlik.Olay], izin: Bool, simdi: Date) {
        let eski = DersGunu.oku()
        if let eski, eski.olaylar == olaylar, eski.takvimIzni == izin { return }
        let yeni = WidgetAnlik(olaylar: olaylar, takvimIzni: izin, sonYanit: eski?.sonYanit, sonSohbetID: eski?.sonSohbetID,
                               sonYanitZamani: eski?.sonYanitZamani, guncelleme: simdi)
        yazVeYenile(yeni)
    }

    /// Başarılı yanıtın kısaltılmış hâlini yazar; olaylar korunur. Boş yanıt yazılmaz.
    static func sonYanitYaz(_ metin: String, sohbet: UUID?) {
        guard etkin else { return }
        let kisa = DersGunu.kisalt(metin)
        guard !kisa.isEmpty else { return }
        let simdi = Date()
        let sohbetID = sohbet?.uuidString
        if let eski = DersGunu.oku(), eski.sonYanit == kisa, eski.sonSohbetID == sohbetID { return }   // aynı yanıt: yazma, yenileme
        var a = DersGunu.oku() ?? WidgetAnlik(olaylar: [], takvimIzni: EKEventStore.authorizationStatus(for: .event) == .fullAccess,
                                              sonYanit: nil, sonSohbetID: nil, sonYanitZamani: nil, guncelleme: simdi)
        a.sonYanit = kisa
        a.sonSohbetID = sohbetID
        a.sonYanitZamani = simdi
        a.guncelleme = simdi
        yazVeYenile(a)
    }

    private static func yazVeYenile(_ a: WidgetAnlik) {
        do {
            try DersGunu.yaz(a)
            yenile()
        } catch {
            TaniGunlugu.yaz("WIDGET: anlık yazılamadı (\(error.localizedDescription))")
        }
    }

    /// Yalnız anlığı gösteren widget'ları yeniler; son yenilemeden 10 dk geçmediyse tek bir ertelenmiş yenileme planlar.
    private static func yenile() {
        let simdi = Date()
        if let son = sonYenileme, simdi.timeIntervalSince(son) < enAzYenilemeAraligi {
            guard yenilemeGorevi == nil else { return }
            let kalan = enAzYenilemeAraligi - simdi.timeIntervalSince(son)
            yenilemeGorevi = Task { @MainActor in
                try? await Task.sleep(for: .seconds(kalan))
                guard !Task.isCancelled else { return }
                yenilemeGorevi = nil
                yenile()
            }
            return
        }
        sonYenileme = simdi
        for tur in anlikTurleri { WidgetCenter.shared.reloadTimelines(ofKind: tur) }
    }
}
