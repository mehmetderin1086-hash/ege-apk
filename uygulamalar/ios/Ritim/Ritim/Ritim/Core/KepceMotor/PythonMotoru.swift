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

    // Python runs on one serial queue. Cancellation releases the Swift caller
    // immediately; the queue still serializes any Python call already in progress.
    private final class PendingCall: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<String, Error>?
        private var finished = false
        func bind(_ value: CheckedContinuation<String, Error>) {
            lock.lock()
            if finished { lock.unlock(); value.resume(throwing: CancellationError()); return }
            continuation = value
            lock.unlock()
        }
        var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return finished }
        func finish(_ result: Result<String, Error>) {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(with: result)
        }
        func cancel() { finish(.failure(CancellationError())) }
    }

    func cagir(_ islev: String, _ argumanlar: [String] = []) async throws -> String {
        let pending = PendingCall()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.bind(continuation)
                kuyruk.async {
                    guard !pending.isFinished else { return }
                    pending.finish(Result { try self.esZamanliCagir(islev, argumanlar) })
                }
            }
        } onCancel: { pending.cancel() }
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
    }

    /// Bağlantının bilgisini (biçimler, adresler, altyazılar ya da liste öğeleri) çıkarır.
    @concurrent func coz(_ adres: String, liste: Bool = false, sinir: Int? = nil) async throws -> MedyaBilgisi {
        let adres = liste ? ListeAdresi.duzelt(adres) : adres
        let secenek = String(decoding: try JSONEncoder().encode(CozumSecenekleri(playlist: liste, flat: liste, limit: sinir)), as: UTF8.self)
        return try Self.ayristir(try await cagir("extract", [adres, secenek]))
    }

    @concurrent func ara(_ sorgu: String, adet: Int = 25) async throws -> MedyaBilgisi {
        try Self.ayristir(try await cagir("search", [sorgu, String(adet)]))
    }

    static func ayristir(_ json: String) throws -> MedyaBilgisi {
        let bilgi = try JSONDecoder().decode(MedyaBilgisi.self, from: Data(json.utf8))
        if bilgi.kind == "error" { throw Hata.cozum(Self.anlasilir(bilgi.error ?? "Bilinmeyen hata")) }
        return bilgi
    }

    /// yt-dlp hata iletilerini kısa Türkçe açıklamaya çevirir (asıl ileti de eklenir).
    static func anlasilir(_ ileti: String) -> String {
        let kucuk = ileti.lowercased()
        let aciklama: String? = switch true {
        case kucuk.contains("not a bot") || kucuk.contains("sign in to confirm"):
            "YouTube bu bağlantı için oturum doğrulaması istiyor. Biraz bekleyip yeniden dene ya da Ayarlar'dan çerez dosyası ekle."
        case kucuk.contains("private video"): "Bu video gizli."
        case kucuk.contains("age") && kucuk.contains("confirm"): "Yaş doğrulaması gereken bir video; Ayarlar'dan çerez dosyası eklemen gerekir."
        case kucuk.contains("unsupported url"): "Bu bağlantı desteklenmiyor."
        case kucuk.contains("video unavailable") || kucuk.contains("not available"): "Video kullanılamıyor (kaldırılmış ya da bölgende kapalı olabilir)."
        case kucuk.contains("members-only") || kucuk.contains("join this channel"): "Yalnız kanal üyelerine açık bir video."
        case kucuk.contains("live event") || kucuk.contains("is live"): "Canlı yayınlar indirilemez; yayın bitince yeniden dene."
        case kucuk.contains("drm"): "Bu içerik DRM korumalı; indirilemez."
        case kucuk.contains("timed out") || kucuk.contains("network") || kucuk.contains("urlopen"): "Bağlantı hatası; internetini denetle."
        default: nil
        }
        guard let aciklama else { return ileti }
        return "\(aciklama)\n\n\(ileti)"
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
    func cerezleriYenile() async throws {
        let cerez = FileManager.default.fileExists(atPath: Self.cerezDosyasi.path) ? Self.cerezDosyasi.path : ""
        _ = try await cagir("configure", [Self.onbellek.path, cerez])
    }
}
