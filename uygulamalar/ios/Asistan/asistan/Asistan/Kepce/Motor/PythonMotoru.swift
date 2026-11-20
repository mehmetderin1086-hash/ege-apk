import Foundation
import JavaScriptCore

/// YouTube'un JS sınavlarını (imza ve n parametresi) çözen C işlevi; Python ctypes ile çağırır.
/// Her çağrı kendi JSContext'ini kurar; dönen belleği Python `free` ile bırakır.
nonisolated func kepceJSDegerlendir(_ girdi: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let girdi else { return nil }
    let betik = String(cString: girdi)
    let sonuc: String = autoreleasepool {
        guard let baglam = JSContext() else { return PythonMotoru.jsHata("JSContext kurulamadı") }
        var hata: String?
        baglam.exceptionHandler = { _, deger in hata = deger?.toString() ?? "bilinmeyen JS hatası" }
        let deger = baglam.evaluateScript(betik)
        if let hata { return PythonMotoru.jsHata(hata) }
        return deger?.toString() ?? ""
    }
    return UnsafeMutableRawPointer(strdup(sonuc))
}

/// Gömülü CPython + yt-dlp. Bütün çağrılar tek bir arka plan kuyruğunda sırayla yapılır.
nonisolated final class PythonMotoru: @unchecked Sendable {
    static let shared = PythonMotoru()

    enum Hata: LocalizedError {
        case baslatma(String), cagri(String), cozum(String)
        var errorDescription: String? {
            switch self {
            case .baslatma(let ileti): "İndirme motoru başlatılamadı: \(ileti)"
            case .cagri(let ileti): "İndirme motoru hatası: \(ileti)"
            case .cozum(let ileti): ileti
            }
        }
    }

    private let kuyruk = DispatchQueue(label: "kepce.python", qos: .userInitiated)
    private var pythonAcik = false        // yalnız `kuyruk` üzerinde
    private var hazir = false             // yt-dlp yapılandırıldı (başarısızsa sonraki çağrıda yeniden denenir)
    private var baslatmaHatasi: String?   // yalnız `kuyruk` üzerinde
    /// `pythonAcik`in kuyruk dışından (iptal iş parçacığından) okunabilen kopyası.
    private let acikKilit = NSLock()
    private var acikKopya = false

    // MARK: Dizinler

    static var destek: URL {
        let url = URL.applicationSupportDirectory.appending(path: "Kepce")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Uygulama içinden güncellenen yt-dlp buraya kurulur ve paketteki sürümü gölgeler.
    static var guncelMotor: URL { destek.appending(path: "guncel-motor") }
    /// Kullanıcının içe aktardığı Netscape biçimli çerez dosyası (yaş sınırlı videolar için, isteğe bağlı).
    static var cerezDosyasi: URL { destek.appending(path: "cerezler.txt") }
    static var onbellek: URL { URL.cachesDirectory.appending(path: "yt-dlp") }

    static func jsHata(_ ileti: String) -> String {
        let veri = (try? JSONSerialization.data(withJSONObject: ["type": "error", "error": ileti])) ?? Data()
        return String(decoding: veri, as: UTF8.self)
    }

    // MARK: Çağrılar

    /// Tek seferlik sürdürme: kuyruktaki sonuç ya da iptal, hangisi önce gelirse; öbürü yok sayılır.
    nonisolated private final class DevamKutusu: @unchecked Sendable {
        private let kilit = NSLock()
        private var devam: CheckedContinuation<String, Error>?
        func koy(_ d: CheckedContinuation<String, Error>) { kilit.withLock { devam = d } }
        func al() -> CheckedContinuation<String, Error>? { kilit.withLock { defer { devam = nil }; return devam } }
    }

    /// `jeton` verilirse iptalde Python tarafına da bildirilir: süren extract ilk günlük satırında durur,
    /// seri kuyruk sonraki indirmeleri (Yeniden dene, yeni arama) bekletmez.
    func cagir(_ islev: String, _ argumanlar: [String] = [], jeton: String? = nil) async throws -> String {
        let kutu = DevamKutusu()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (devam: CheckedContinuation<String, Error>) in
                kutu.koy(devam)
                // İptal kayıttan önce geldiyse onCancel devamı bulamamıştır: burada sürdür, kuyruğa hiç verme.
                if Task.isCancelled {
                    kutu.al()?.resume(throwing: CancellationError())
                    return
                }
                kuyruk.async {
                    let sonuc = Result { try self.esZamanliCagir(islev, argumanlar) }
                    kutu.al()?.resume(with: sonuc)
                }
            }
        } onCancel: {
            kutu.al()?.resume(throwing: CancellationError())
            if let jeton { self.iptalGonder(jeton) }
        }
    }

    /// İptali seri kuyruğun DIŞINDA bildirir (kp_cagir GIL'i kendi alır; extract çalışırken de güvenli).
    private func iptalGonder(_ jeton: String) {
        guard acikKilit.withLock({ acikKopya }) else { return }
        DispatchQueue.global(qos: .userInitiated).async { _ = try? self.ham("cancel", [jeton]) }
    }

    /// Motoru önceden ısıtır (ilk açılışta yt-dlp'nin modülleri derlenir, birkaç saniye sürer).
    func isit() {
        kuyruk.async { _ = try? self.hazirla() }
    }

    private func hazirla() throws {
        if let baslatmaHatasi { throw Hata.baslatma(baslatmaHatasi) }
        if hazir { return }
        if !pythonAcik {
            guard let kaynak = Bundle.main.resourcePath else { throw Hata.baslatma("paket yolu yok") }
            let yollar = [Self.guncelMotor.path, "\(kaynak)/app_packages", "\(kaynak)/app"].joined(separator: ":")
            let pycache = URL.cachesDirectory.appending(path: "pycache").path
            if let ileti = kp_baslat("\(kaynak)/python", yollar, pycache) {
                let metin = String(cString: ileti)
                free(ileti)
                baslatmaHatasi = metin
                throw Hata.baslatma(metin)
            }
            pythonAcik = true
            acikKilit.withLock { acikKopya = true }
            // JS değerlendiricisi yt-dlp'ye bağlı değildir: önce bağlanır, yapılandırma düşse bile kalır.
            let isaret: @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? = kepceJSDegerlendir
            _ = try ham("set_native_evaluator", [String(Int(bitPattern: unsafeBitCast(isaret, to: UnsafeRawPointer.self)))])
        }
        let cerez = FileManager.default.fileExists(atPath: Self.cerezDosyasi.path) ? Self.cerezDosyasi.path : ""
        _ = try ham("configure", [Self.onbellek.path, cerez])
        hazir = true
    }

    private func esZamanliCagir(_ islev: String, _ argumanlar: [String]) throws -> String {
        try hazirla()
        return try ham(islev, argumanlar)
    }

    private func ham(_ islev: String, _ argumanlar: [String]) throws -> String {
        let kopyalar = argumanlar.map { UnsafePointer(strdup($0)) }
        defer { kopyalar.forEach { free(UnsafeMutablePointer(mutating: $0)) } }
        var hata: UnsafeMutablePointer<CChar>?
        let sonuc = kopyalar.withUnsafeBufferPointer { tampon in
            kp_cagir("kepce_motor", islev, tampon.baseAddress, Int32(argumanlar.count), &hata)
        }
        if let sonuc {
            defer { free(sonuc) }
            return String(cString: sonuc)
        }
        let ileti = hata.map { String(cString: $0) } ?? "bilinmeyen hata"
        free(hata)
        throw Hata.cagri(ileti)
    }

    // MARK: Yüksek düzey işlemler

    struct CozumSecenekleri: Encodable {
        var playlist = false
        var flat = false
        var limit: Int?
        var token: String?   // iptal jetonu (kepce_motor.cancel)
    }

    /// Bağlantının bilgisini (biçimler, adresler, altyazılar ya da liste öğeleri) çıkarır.
    @concurrent func coz(_ adres: String, liste: Bool = false, sinir: Int? = nil) async throws -> MedyaBilgisi {
        let adres = liste ? ListeAdresi.duzelt(adres) : adres
        let jeton = UUID().uuidString
        let secenek = String(decoding: try JSONEncoder().encode(CozumSecenekleri(playlist: liste, flat: liste, limit: sinir, token: jeton)), as: UTF8.self)
        return try Self.ayristir(try await cagir("extract", [adres, secenek], jeton: jeton))
    }

    @concurrent func ara(_ sorgu: String, adet: Int = 25) async throws -> MedyaBilgisi {
        let jeton = UUID().uuidString
        return try Self.ayristir(try await cagir("search", [sorgu, String(adet), jeton], jeton: jeton))
    }

    static func ayristir(_ json: String) throws -> MedyaBilgisi {
        let bilgi = try JSONDecoder().decode(MedyaBilgisi.self, from: Data(json.utf8))
        if bilgi.kind == "error" { throw Hata.cozum(Self.anlasilir(bilgi.error ?? "Bilinmeyen hata")) }
        return bilgi
    }

    /// yt-dlp hata iletilerini kısa Türkçe açıklamaya çevirir (asıl ileti de eklenir).
    /// Yeniden uygulanınca açıklamayı ikinci kez eklemez (ayristir ve MotorluIndirme ikisi de çağırır).
    static func anlasilir(_ ileti: String) -> String {
        let kucuk = ileti.lowercased()
        let aciklama: String? = switch true {
        // YouTube'un yaş iletisi de "Sign in to confirm your age" diye başlar: bot dalından ÖNCE denetlenir.
        case kucuk.contains("confirm your age") || kucuk.contains("age-restricted") || kucuk.contains("age restricted")
            || kucuk.contains("inappropriate for some users"):
            "Yaş doğrulaması gereken bir video; Ayarlar > İndirme motoru > Çerez dosyası ekle ile YouTube çerezlerini eklemen gerekir."
        case kucuk.contains("not a bot") || kucuk.contains("sign in to confirm"):
            "YouTube bu ağdan gelen isteği robot sanıyor. VPN açıksa kapatıp yeniden dene (sunucu IP'leri YouTube'da engellidir); olmazsa Ayarlar > İndirme motoru'ndan çerez dosyası ekle."
        case kucuk.contains("private video"): "Bu video gizli."
        case kucuk.contains("unsupported url"): "Bu bağlantı desteklenmiyor."
        // "Requested format is not available" bir sonuçtur, videonun kaldırıldığı anlamına gelmez.
        case kucuk.contains("requested format"): "Uygun biçim seçilemedi; Ayarlar > İndirme motoru'ndan motoru güncelleyip yeniden dene."
        case kucuk.contains("video unavailable") || kucuk.contains("not available"): "Video kullanılamıyor (kaldırılmış ya da bölgende kapalı olabilir)."
        case kucuk.contains("members-only") || kucuk.contains("join this channel"): "Yalnız kanal üyelerine açık bir video."
        case kucuk.contains("live event") || kucuk.contains("is live"): "Canlı yayınlar indirilemez; yayın bitince yeniden dene."
        case kucuk.contains("drm"): "Bu içerik DRM korumalı; indirilemez."
        case kucuk.contains("timed out") || kucuk.contains("network") || kucuk.contains("urlopen"): "Bağlantı hatası; internetini denetle."
        default: nil
        }
        guard let aciklama, !ileti.hasPrefix(aciklama) else { return ileti }
        return "\(aciklama)\n\n\(ileti)"
    }

    /// İçe aktarılan dosya Netscape biçimli çerez dosyası mı (cookies.txt)? Boş ya da çok büyük dosya reddedilir.
    static func cerezMetniGecerli(_ metin: String) -> Bool {
        guard !metin.isEmpty, metin.utf8.count <= 5_000_000 else { return false }
        // Kırpma yapılmaz: boş değerli çerezde sondaki sekme alan sayısını belirler.
        let satirlar = metin.split(whereSeparator: \.isNewline).map(String.init)
        if let ilk = satirlar.first, ilk.hasPrefix("# Netscape HTTP Cookie File") || ilk.hasPrefix("# HTTP Cookie File") { return true }
        // Başlıksız dosya: en az bir satır 7 sekmeyle ayrılmış alandan oluşmalı (alan, bayrak, yol, güvenli, süre, ad, değer).
        return satirlar.contains { s in
            let govde = s.hasPrefix("#HttpOnly_") ? String(s.dropFirst("#HttpOnly_".count)) : s
            return !govde.hasPrefix("#") && govde.split(separator: "\t", omittingEmptySubsequences: false).count == 7
        }
    }

    struct Surum: Decodable, Sendable { let yt_dlp: String; let ejs: String; let python: String }

    func surum() async throws -> Surum {
        try JSONDecoder().decode(Surum.self, from: Data(try await cagir("version").utf8))
    }

    /// PyPI'den en yeni yt-dlp'yi kurar ve modülleri yeniden yükler; yeni sürümü döndürür.
    func guncelle() async throws -> Surum {
        _ = try await cagir("update", [Self.guncelMotor.path])
        return try await surum()
    }

    /// Güncellenen sürümü silip paketteki sürüme döner.
    func paketSurumuneDon() async throws -> Surum {
        _ = try await cagir("reset", [Self.guncelMotor.path])
        return try await surum()
    }

    /// Çerez dosyası değişince motora bildirir.
    /// Çerez dosyası değişti: Python'u şimdi başlatmaz (Ayarlar'ı ve süren indirmeyi bekletmesin);
    /// sonraki motor çağrısı `hazirla()` ile yapılandırmayı güncel çerez yoluyla yeniler.
    func cerezleriYenile() async throws {
        kuyruk.async { self.hazir = false }
    }
}
