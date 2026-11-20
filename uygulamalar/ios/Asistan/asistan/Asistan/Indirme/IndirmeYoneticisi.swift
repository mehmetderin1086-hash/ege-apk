import UserNotifications
import Foundation
import Observation
import UIKit

struct IndirmeKaydi: Codable, Identifiable, Sendable {
    var id = UUID()
    var adres: String
    var tur: String
    var ad: String = "Dosya"
    var durum = "queued"
    var alinan: Int64 = 0
    var toplam: Int64 = 0
    var dosya: String?
    var hata: String?
    /// Gömülü Kepçe motoruyla indirilir (uygulama kapanırsa devam etmez).
    var motor: Bool?
    var etkin: Bool { ["queued", "running"].contains(durum) }
    /// `yerelKayit` true yazar; kullanıcının eklediği kayıt false taşır (sahte adresi andıran bir bağlantı yerel sayılmasın).
    /// Bayraktan önce yazılmış eski kayıtlarda nil: adres önekine bakılır.
    var yerelUretim: Bool? = false
    /// iPhone'da üretilmiş ya da arşivden çıkarılmış dosya: sahte adresi vardır, yeniden indirilemez.
    var yerel: Bool { yerelUretim ?? adres.hasPrefix("https://local.invalid/") }
    var durumMetni: String { ["queued":"Sırada", "running":"iPhone’a indiriliyor", "done":"Tamamlandı", "external":"Kepçe’ye aktarıldı", "failed":"İndirilemedi", "cancelled":"İptal edildi"][durum] ?? durum }
}

@MainActor @Observable
final class IndirmeYoneticisi {
    static let ortak = IndirmeYoneticisi()
    static let oturumID = "com.mehmetderin.asistan.downloads"
    var medyaSayfasi: MedyaSayfasi?
    var kazimaSayfasi: KazimaSayfasi?
    var ekranAcik = false
    var hata: String?
    private(set) var kayitlar: [IndirmeKaydi] = []
    private let temsilci = IndirmeTemsilcisi()
    @ObservationIgnored var motorGorevleri: [UUID: Task<Void, Never>] = [:]
    var arkaPlanBitti: (() -> Void)?
    static let enFazlaEtkin = 30
    /// ZIP/RAR'dan çıkarılan dosyaların türü; İndirmeler ekranında ayrı bölümde listelenir.
    nonisolated static let arsivTuru = "arsiv"
    /// İndirme bitince (başarılı ya da değil) sohbete mesaj olarak iletmek için (Beyin bağlar).
    @ObservationIgnored var bitti: ((IndirmeKaydi) -> Void)?
    static var klasor: URL { URL.documentsDirectory.appending(path: "Indirmeler", directoryHint: .isDirectory) }
    nonisolated static var klasorYolu: String { URL.documentsDirectory.appending(path: "Indirmeler", directoryHint: .isDirectory).path }
    private var dizin: URL { Self.klasor.appending(path: "kayitlar.json") }
    @ObservationIgnored private lazy var oturum: URLSession = {
        let c = URLSessionConfiguration.background(withIdentifier: IndirmeYoneticisi.oturumID)
        c.httpMaximumConnectionsPerHost = 2
        c.isDiscretionary = false
        c.timeoutIntervalForResource = 3600
        return URLSession(configuration: c, delegate: temsilci, delegateQueue: nil)
    }()
    init() {
        try? FileManager.default.createDirectory(at: Self.klasor, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: dizin), let k = try? JSONDecoder().decode([IndirmeKaydi].self, from: d) { kayitlar = k }
        // Motorlu indirme uygulamayla birlikte ölür: yarım kalanları işaretle.
        for i in kayitlar.indices where kayitlar[i].motor == true && kayitlar[i].etkin {
            kayitlar[i].durum = "failed"; kayitlar[i].hata = "Uygulama kapandığı için yarım kaldı; yeniden dene."
        }
        // Açılışta süren motor işi yoktur: kaydı silinmiş/eski klasörleri temizle, başarısızların klasörü devam için kalır.
        let bekleyen = Set(kayitlar.filter { $0.motor == true && $0.durum == "failed" }.map(\.id))
        // Görüntü anı geçer: temizlik gecikirse açılıştan hemen sonra başlayan motorlu işin klasörü silinmesin.
        let an = Date.now
        Task.detached(priority: .utility) { MotorluIndirici.sahipsizleriTemizle(etkin: [], bekleyen: bekleyen, simdi: an) }
    }
    func kaydiEkle(_ k: IndirmeKaydi) { kayitlar.insert(k, at: 0); kaydet() }
    nonisolated static func dogrula(_ metin: String) throws -> URL {
        guard metin.count <= 4096, let u = URL(string: metin.trimmingCharacters(in: .whitespacesAndNewlines)), u.scheme == "https", u.host != nil, u.user == nil, u.password == nil else { throw IndirmeHatasi.metin("Geçerli bir HTTPS bağlantısı gir.") }
        // Yerel ağ / özel IP adreslerine indirme yapılmaz (sayfadan gelen bağlantılarla SSRF önlemi).
        guard WebSayfa.urlGuvenli(u) else { throw IndirmeHatasi.metin("Yerel ağ ya da özel adreslerden indirme yapılmaz.") }
        return u
    }
    nonisolated static func dogrudanMedya(_ url: URL) -> Bool {
        ["mp4", "mov", "webm", "mp3", "m4a", "aac", "wav", "ogg"].contains(url.pathExtension.lowercased())
    }
    nonisolated static func dosyaAdi(_ ad: String) -> String {
        // Dosya sistemi/URL adları ayrışık (NFD) gelir: "İ" = "I" + U+0307. Önce birleşik biçime getirilir,
        // kalan birleştirici işaretler de korunur; yoksa "Ödev.pdf" → "O_dev.pdf" oluyordu.
        let birlesik = ad.precomposedStringWithCanonicalMapping
        let sonuc = birlesik.replacingOccurrences(of: "[^\\p{L}\\p{M}\\p{N}._ -]", with: "_", options: .regularExpression)
        return String(sonuc.prefix(140)).trimmingCharacters(in: CharacterSet(charactersIn: ". ")).isEmpty ? "Dosya" : String(sonuc.prefix(140)).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }
    func baslat() {
        _ = oturum
    }
    @discardableResult func ekle(_ adres: String, tur: String) async throws -> UUID {
        let url = try Self.dogrula(adres)
        guard ["file","video","audio"].contains(tur) else { throw IndirmeHatasi.metin("Dosya, video veya ses seç.") }
        // Ad özel adrese çözülüyorsa (MagicDNS, ev NAS'ı, split-DNS) dosya baştan indirilmez; yoksa ancak tamamı inince
        // reddedilirdi. getaddrinfo eşzamanlı: ana iş parçacığı dışında. Sınır denetimi ile kayıt ekleme arasında await yok.
        let host = url.host ?? ""
        if await Task.detached(priority: .userInitiated, operation: { WebSayfa.ozeleCozuluyor(host) }).value {
            throw IndirmeHatasi.metin("Bu adres yerel ağa ya da özel bir adrese çıkıyor; indirme yapılmaz.")
        }
        try Task.checkCancellation()
        guard kayitlar.filter(\.etkin).count < Self.enFazlaEtkin else { throw IndirmeHatasi.metin("En fazla \(Self.enFazlaEtkin) etkin indirme olabilir.") }
        baslat()
        let k = IndirmeKaydi(adres: url.absoluteString, tur: tur, ad: url.lastPathComponent.isEmpty ? "Dosya" : Self.dosyaAdi(url.lastPathComponent))
        kayitlar.insert(k, at: 0); kaydet()
        indir(k, istek: URLRequest(url: url))
        return k.id
    }
    func kepceyeAktar(_ adres: String, tur: String) async throws {
        let url = try Self.dogrula(adres)
        try await KepceBaglantisi.aktar(url, tur: tur)
        var k = IndirmeKaydi(adres: url.absoluteString, tur: tur, ad: url.host ?? "Medya")
        k.durum = "external"
        kayitlar.insert(k, at: 0); kaydet()
    }
    func yerelDosyaEkle(url: URL, gorunenAd: String, tur: String = "file") {
        guard let k = Self.yerelKayit(url: url, gorunenAd: gorunenAd, tur: tur) else { return }
        kayitlar.insert(k, at: 0); kaydet()
    }
    /// Çok dosyayı (ör. arşivden çıkanlar) tek kaydet() ile ekler; sıra tek tek `yerelDosyaEkle` çağrısıyla aynıdır (son eklenen en üstte).
    func yerelDosyalarEkle(_ ciftler: [(url: URL, gorunenAd: String)], tur: String = "file") {
        let yeni = ciftler.compactMap { Self.yerelKayit(url: $0.url, gorunenAd: $0.gorunenAd, tur: tur) }
        guard !yeni.isEmpty else { return }
        kayitlar.insert(contentsOf: yeni.reversed(), at: 0); kaydet()
    }
    /// Yalnız İndirmeler klasöründe duran dosya için tamamlanmış yerel kayıt; değilse nil (test için erişilebilir).
    static func yerelKayit(url: URL, gorunenAd: String, tur: String = "file") -> IndirmeKaydi? {
        guard url.deletingLastPathComponent().standardizedFileURL == klasor.standardizedFileURL,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        var k = IndirmeKaydi(adres: "https://local.invalid/" + url.lastPathComponent, tur: tur, ad: gorunenAd)
        k.durum = "done"; k.dosya = url.lastPathComponent; k.yerelUretim = true
        return k
    }
    private func indir(_ k: IndirmeKaydi, istek: URLRequest) {
        degistir(k.id) { $0.durum = "running" }
        let t = oturum.downloadTask(with: istek); t.taskDescription = k.id.uuidString; t.resume()
    }
    func iptal(_ id: UUID) async {
        guard let k = kayitlar.first(where: { $0.id == id }), k.etkin else { return }
        degistir(id) { $0.durum = "cancelled" }
        motorGorevleri[id]?.cancel(); motorGorevleri[id] = nil
        for t in await oturum.allTasks where t.taskDescription == id.uuidString { t.cancel() }

    }
    func tekrar(_ k: IndirmeKaydi) async {
        // Yerel kayıt (iPhone'da üretilen/arşivden çıkan) sahte adrese istek atmasın; 'arsiv' türü ekle'de anlamsız hata vermesin.
        guard !k.yerel else { hata = "Bu dosya iPhone'da üretildi; yeniden indirilemez."; return }
        // Aynı kimlikle yeniden başlatır: çalışma klasörü korunduğu için motor kaldığı yerden sürer.
        if k.motor == true { do { try motorluTekrar(k) } catch { hata = error.localizedDescription }; return }
        do { _ = try await ekle(k.adres, tur: k.tur) } catch { hata = error.localizedDescription }
    }
    func sil(_ k: IndirmeKaydi) {
        guard !k.etkin else { return }
        if let u = dosyaURL(k) { try? FileManager.default.removeItem(at: u) }
        if k.motor == true {
            // Başarısız motorlu kaydın devam için tutulan yarım parçaları; büyük olabilir, ana iş parçacığında silinmez.
            let calisma = MotorluIndirici.calismaKlasoru(k.id)
            Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: calisma) }
        }
        kayitlar.removeAll { $0.id == k.id }; kaydet()
    }
    func dosyaURL(_ k: IndirmeKaydi) -> URL? {
        guard let ad = k.dosya, !ad.contains("/"), ad != ".", ad != ".." else { return nil }
        let u = Self.klasor.appending(path: ad)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
    func degistir(_ id: UUID, _ islem: (inout IndirmeKaydi) -> Void) {
        guard let i = kayitlar.firstIndex(where: { $0.id == id }) else { return }
        islem(&kayitlar[i]); kaydet()
    }
    private func kaydet() { do { try JSONEncoder().encode(kayitlar).write(to: dizin, options: .atomic) } catch { hata = "İndirme listesi kaydedilemedi." } }
    func ilerleme(_ id: UUID, alinan: Int64, toplam: Int64) {
        guard let i = kayitlar.firstIndex(where: { $0.id == id && $0.etkin }) else { return }
        kayitlar[i].alinan = alinan; kayitlar[i].toplam = toplam
    }
    func tamam(_ id: UUID, ad: String?, hata: String?, gorunenAd: String? = nil) {
        guard kayitlar.contains(where: { $0.id == id && $0.etkin }) else {
            if let ad { try? FileManager.default.removeItem(at: Self.klasor.appending(path: ad)) }; return
        }
        degistir(id) { k in k.durum = ad == nil ? "failed" : "done"; k.dosya = ad; k.hata = hata; if let ad { k.ad = gorunenAd ?? String(ad.dropFirst(37)) } }
        if let k = kayitlar.first(where: { $0.id == id }) { bitti?(k) }
    }

}

nonisolated enum IndirmeHatasi: LocalizedError { case metin(String); var errorDescription: String? { if case let .metin(s) = self { s } else { nil } } }

/// Arka plan oturumu geri çağrıları sistem kuyruğunda gelir: sınıf ana aktöre bağlı olmamalı.
nonisolated final class IndirmeTemsilcisi: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    /// Genel web dosyaları güvenli HTTPS CDN'lerine yönlenebilir. Kişisel kimlik
    /// taşıyan bir istek ise başlangıç sunucusundan ayrılmaz.
    nonisolated static func yonlendirmeyeIzinVer(orijinal: URLRequest?, yeni: URLRequest) -> Bool {
        guard let hedef = yeni.url, hedef.scheme == "https", hedef.host != nil,
              hedef.user == nil, hedef.password == nil, WebSayfa.urlGuvenli(hedef) else { return false }
        guard let orijinal, orijinal.value(forHTTPHeaderField: "X-Personal-Token") != nil else { return true }
        guard let kaynak = orijinal.url?.host else { return false }
        return kaynak.caseInsensitiveCompare(hedef.host ?? "") == .orderedSame
    }
    /// İndirmenin vardığı son adres: HTTPS, herkese açık ve DNS ile iç ağa çözülmüyor olmalı.
    /// Arka plan oturumu yönlendirmeleri kendisi izler (willPerformHTTPRedirection çağrılmaz); asıl denetim budur.
    nonisolated static func sonAdresGuvenli(_ u: URL?) -> Bool {
        guard let u, u.scheme == "https", WebSayfa.urlGuvenli(u) else { return false }
        return !WebSayfa.ozeleCozuluyor(u.host ?? "")
    }
    /// Son adres reddinde ileti: yönlendirme yalnız ana makine gerçekten değiştiyse söylenir.
    nonisolated static func guvensizSonAdresMetni(son: URL?, ilk: URL?) -> String {
        let yonlendi = son?.host?.lowercased() != ilk?.host?.lowercased()
        return yonlendi ? "İndirme yerel ağa ya da özel bir adrese yönlendi; dosya alınmadı."
                        : "Bu sunucu yerel ağda ya da özel bir adreste; dosya alınmadı."
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let s = downloadTask.taskDescription, let id = UUID(uuidString: s) else { return }
        if totalBytesWritten > 1_073_741_824 || totalBytesExpectedToWrite > 1_073_741_824 { downloadTask.cancel(); Task { @MainActor in IndirmeYoneticisi.ortak.tamam(id, ad: nil, hata: "1 GB dosya sınırı aşıldı.") }; return }
        Task { @MainActor in IndirmeYoneticisi.ortak.ilerleme(id, alinan: totalBytesWritten, toplam: totalBytesExpectedToWrite) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let s = downloadTask.taskDescription, let id = UUID(uuidString: s) else { return }
        do {
            guard let h = downloadTask.response as? HTTPURLResponse, (200..<300).contains(h.statusCode) else { throw IndirmeHatasi.metin("Sunucu dosyayı vermedi.") }
            // Temsilci kuyruğu ana iş parçacığı değil: DNS denetimi burada arayüzü dondurmaz. Dosya taşınmazsa sistem geçici dosyayı siler.
            let son = h.url ?? downloadTask.currentRequest?.url
            guard Self.sonAdresGuvenli(son) else { throw IndirmeHatasi.metin(Self.guvensizSonAdresMetni(son: son, ilk: downloadTask.originalRequest?.url)) }
            guard !(h.mimeType ?? "").contains("text/html") else { throw IndirmeHatasi.metin("Bu bir web sayfası. Video veya ses seçeneğini kullan.") }
            let ad = id.uuidString + "-" + IndirmeYoneticisi.dosyaAdi(h.suggestedFilename ?? "Dosya")
            let klasor = URL.documentsDirectory.appending(path: "Indirmeler", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: location, to: klasor.appending(path: ad))
            Task { @MainActor in IndirmeYoneticisi.ortak.tamam(id, ad: ad, hata: nil) }
        } catch { let mesaj = error.localizedDescription; Task { @MainActor in IndirmeYoneticisi.ortak.tamam(id, ad: nil, hata: mesaj) } }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error, let s = task.taskDescription, let id = UUID(uuidString: s) else { return }
        let mesaj = error.localizedDescription
        Task { @MainActor in IndirmeYoneticisi.ortak.tamam(id, ad: nil, hata: mesaj) }
    }
    // Arka plan oturumunda çağrılmaz (yalnız default/ephemeral oturumlarda); asıl denetim didFinishDownloadingTo içinde.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(Self.yonlendirmeyeIzinVer(orijinal: task.originalRequest, yeni: request) ? request : nil)
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in let k = IndirmeYoneticisi.ortak; k.arkaPlanBitti?(); k.arkaPlanBitti = nil }
    }
}

final class IndirmeAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // P2.14: bildirim düğmeleri (Yanıtla / Sesli dinle / Ertele 10 dk) kategorilerle gelir.
        BildirimEylemleri.kaydet()
        return true
    }
    // Tamamlayıcılı varyantlar: async varyantlar varsayılan MainActor yalıtımında sistem kuyruğunda çöküyordu (bkz. not).
    // P2.14: tamamlayıcı ancak eylem bitince çağrılır (arka plan yanıtı, erteleme kaydı); `isle` her dalda bir kez çağırır.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        nonisolated(unsafe) let tamam = completionHandler
        BildirimEylemleri.isle(response) { tamam() }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    // P4.6: APNs jetonu görev sunucusuna kaydedilir (sunucu görevi bitince bildirim). Ana aktöre yalnız String taşınır.
    nonisolated func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let jeton = SunucuGorevleri.jetonHex(deviceToken)
        Task { @MainActor in
            do { try await SunucuGorevleri.ortak.cihazKaydet(jeton) }
            catch { TaniGunlugu.yaz("APNS jetonu sunucuya kaydedilemedi: \(String(describing: type(of: error)))") }
        }
    }
    /// Jeton yazılmaz; yalnız hata türü ve kodu.
    nonisolated func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        let n = error as NSError
        TaniGunlugu.yaz("APNS kaydı başarısız: \(n.domain) \(n.code)")
    }
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == IndirmeYoneticisi.oturumID else { completionHandler(); return }
        IndirmeYoneticisi.ortak.arkaPlanBitti = completionHandler
        IndirmeYoneticisi.ortak.baslat()
    }
}
