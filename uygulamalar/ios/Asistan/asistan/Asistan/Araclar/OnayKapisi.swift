import Foundation
import Observation

/// Yan etkili araçlar (kısayol, arama, dış adres) çalışmadan önce kullanıcıdan onay alır.
/// Web arama sonuçlarından gelebilecek istem enjeksiyonuna karşı tek somut kapı.
@MainActor
@Observable
final class OnayKapisi {
    struct Istek: Identifiable, Equatable {
        let id = UUID()
        let baslik: String
        let ayrinti: String
        /// Görsel önizleme (ör. imzalı PDF sayfasının PNG'si). Doluysa ekranlar metin diyaloğu yerine
        /// önizleme sayfasını (`ImzaOnizlemeSayfasi`) açar.
        var onizleme: URL? = nil
    }

    private(set) var bekleyen: Istek?
    private var devam: CheckedContinuation<Bool, Never>?
    /// Ekrandaki onay yanıtlanmadan gelen istekler (FIFO): biri yanıtlanınca sıradaki gösterilir; hiçbiri sessizce reddedilmez.
    private var sira: [(istek: Istek, devam: CheckedContinuation<Bool, Never>)] = []
    /// Sıradakini kısa aradan sonra gösteren görev: kapanan diyalog yeni istekle yeniden açılabilsin ve
    /// kapanış bağlamasının (`isPresented` setter) gecikmeli `false`'u yeni isteği reddetmesin.
    private var siraGorevi: Task<Void, Never>?
    /// Sıradaki onayın görünmeden önceki ara.
    nonisolated static let siraAraligi: Duration = .milliseconds(400)
    /// Sırada bekleyebilecek en çok istek; aşan yeni istek gösterilmeden reddedilir (kaçak döngü diyalog yağdırmasın).
    nonisolated static let enFazlaSira = 6
    /// Ekrandakiyle birlikte bekleyen onay sayısı.
    var bekleyenSayisi: Int { (bekleyen == nil ? 0 : 1) + sira.count }
    /// Testlerde ve kapalı kipte otomatik karar.
    var otomatikKarar: Bool?
    /// Bu tur dış kaynaklı (asistan:// bağlantısı) ya da güvenilmeyen içerik (web, belge, MCP, gelen kutusu) okundu:
    /// yan etkili adımlar otomatik karardan bağımsız olarak kullanıcıya sorulur. Beyin her turun başında ayarlar.
    var disKaynakTuru = false
    /// P2.13: Sesli kipte diyalog açılınca soruyu seslendirip yanıtı dinler (SesOturumu kurar). true/false sesli karar,
    /// nil belirsiz (diyalog ekranda kalır). Diyalog her durumda görünür: dokunma ya da ses, hangisi önce gelirse;
    /// `yanitla(id:)` bayat yanıtı yok sayar. Otomatik karar dalı (diyalogsuz) sesli soru açmaz.
    var sesliSorucu: (@MainActor (Istek) async -> Bool?)?

    /// Test süreci: zorunlu onaylar da otomatik karara uyar (diyalog testi kilitlemesin).
    nonisolated static let testte = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || ProcessInfo.processInfo.environment["ASISTAN_TEST"] == "1"
    /// Zorunlu (ya da dış kaynaklı turdaki) onay da otomatik karara uyar mı? Varsayılan yalnız test sürecinde evet;
    /// testler `false` vererek üründeki gerçek kapıyı (diyalog açılması) sınayabilir.
    let zorunluOtomatikKararaUyar: Bool

    init(zorunluOtomatikKararaUyar: Bool = OnayKapisi.testte) {
        self.zorunluOtomatikKararaUyar = zorunluOtomatikKararaUyar
    }

    /// `zorunlu`: kullanıcı "onay sorma" seçse bile sorulur (Ajan merkezinde "Her seferinde sor" seçilmiş araç, tarayıcıda ödeme/gönderme).
    /// Dış kaynaklı turda (`disKaynakTuru`) her onay zorunlu sayılır.
    /// `onizleme`: onay ekranında gösterilecek görsel (PNG/JPEG dosyası); FIFO ve otomatik karar mantığı aynıdır.
    func iste(baslik: String, ayrinti: String, zorunlu: Bool = false, onizleme: URL? = nil) async -> Bool {
        guard !Task.isCancelled else { return false }
        if let otomatikKarar, Self.otomatikKararGecerli(zorunlu: zorunlu || disKaynakTuru, zorunluOtomatikKararaUyar: zorunluOtomatikKararaUyar) { return otomatikKarar }
        // Ekranda başka onay varsa bu istek sıraya girer (FIFO); ilki sessizce reddedilmez. Tek seferde tek diyalog.
        guard sira.count < Self.enFazlaSira else { return false }
        let istek = Istek(baslik: baslik, ayrinti: ayrinti, onizleme: onizleme)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { c in
                if Task.isCancelled { c.resume(returning: false); return }
                if bekleyen == nil, devam == nil, sira.isEmpty, siraGorevi == nil { bekleyen = istek; devam = c; sesliSor(istek) }
                else { sira.append((istek, c)); if bekleyen == nil { siradakiniGoster() } }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.iptalEt(istek.id) }
        }
    }

    /// İptal edilen istek ekrandaysa reddedilir (sıradaki gösterilir), sıradaysa gösterilmeden çıkarılır.
    private func iptalEt(_ id: UUID) {
        if bekleyen?.id == id { yanitla(false, id: id); return }
        guard let i = sira.firstIndex(where: { $0.istek.id == id }) else { return }
        sira.remove(at: i).devam.resume(returning: false)
    }

    /// Sıradaki isteği kısa aradan sonra ekrana getirir.
    private func siradakiniGoster() {
        guard !sira.isEmpty, siraGorevi == nil else { return }
        siraGorevi = Task { [weak self] in
            try? await Task.sleep(for: OnayKapisi.siraAraligi)
            guard let self else { return }
            self.siraGorevi = nil
            guard self.bekleyen == nil, self.devam == nil, !self.sira.isEmpty else { return }
            let s = self.sira.removeFirst()
            self.bekleyen = s.istek
            self.devam = s.devam
            self.sesliSor(s.istek)
        }
    }

    /// Ekrana gelen isteği sesli kipte seslendirip dinletir; karar geldiğinde istek hâlâ ekrandaysa yanıtlanır.
    /// Önizlemeli istek (imza) sesle onaylanmaz: kullanıcı görseli görüp dokunarak karar verir.
    private func sesliSor(_ i: Istek) {
        guard i.onizleme == nil, let s = sesliSorucu else { return }
        Task { [weak self] in
            guard let karar = await s(i), let self, self.bekleyen?.id == i.id else { return }
            self.yanitla(karar, id: i.id)
        }
    }

    /// Kullanıcının kendi komutunda soru sormayan, ama dış kaynaklı ya da güvenilmeyen içerik okunmuş turda
    /// zorunlu soru soran kapı (WhatsApp kestirmesi, kestirme çalıştırma, beceri kaydı, günlük yazımı).
    func disKaynaktaIste(baslik: String, ayrinti: String) async -> Bool {
        guard disKaynakTuru else { return true }
        return await iste(baslik: baslik, ayrinti: ayrinti, zorunlu: true)
    }

    /// Güvenilmeyen içerik okuyan bir araç yanıt verdi: bu turun kalan yan etkili adımları sorulur.
    func disIcerikOkundu() { disKaynakTuru = true }

    /// Saf karar: otomatik karar diyalogsuz kullanılabilir mi? Zorunlu onay yalnız `zorunluOtomatikKararaUyar` iken (test) diyalogsuz geçer.
    nonisolated static func otomatikKararGecerli(zorunlu: Bool, zorunluOtomatikKararaUyar: Bool) -> Bool {
        !zorunlu || zorunluOtomatikKararaUyar
    }

    /// Ekrandaki onayı yanıtlar; `id` verilirse yalnız o istek ekrandaysa (bayat diyalog/kapanış sıradakini yanıtlamasın).
    /// Ardından sıradaki istek kısa aradan sonra gösterilir.
    func yanitla(_ onay: Bool, id: UUID? = nil) {
        if let id, bekleyen?.id != id { return }
        bekleyen = nil
        let c = devam
        devam = nil
        c?.resume(returning: onay)
        siradakiniGoster()
    }
}
