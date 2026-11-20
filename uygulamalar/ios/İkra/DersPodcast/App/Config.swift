import Foundation

nonisolated enum Config {
    /// Uygulamanın görünen adı ("Ders Podcast" ya da "Ders Video"): ortak dosyalardaki iletilerde kullanılır.
    static var appName: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Ders Podcast" }
    static let apiBaseURLOverrideKey = "dev.apiBaseURL"
    static let vpsBaseURL = URL(string: "https://xn--cumhuriyetanadolulisesiktphanesi-vmdb.com.tr/dersdas")!
    /// Kullanıcının istediği VPS geçişi; sonraki elle adres değişiklikleri korunur.
    static func migrateToVPSIfNeeded() {
        let preferences = UserDefaults.standard
        let migration = "dersdas.vps-migration.20261006.all-providers"
        guard !preferences.bool(forKey: migration) else { return }
        if let previous = preferences.string(forKey: apiBaseURLOverrideKey) {
            preferences.set(previous, forKey: "dersdas.previous-api-base-url")
        }
        preferences.set(vpsBaseURL.absoluteString, forKey: apiBaseURLOverrideKey)
        preferences.set(true, forKey: migration)
    }

    /// Ayarlar'dan girilen sunucu adresi; yoksa derleme yapılandırmasındaki varsayılan.
    static var apiBaseURL: URL {
        migrateToVPSIfNeeded()
        if let override = UserDefaults.standard.string(forKey: apiBaseURLOverrideKey),
           let url = URL(string: override.trimmingCharacters(in: .whitespaces)), url.scheme != nil, url.host() != nil {
            return url
        }
        return defaultAPIBaseURL
    }

    static var defaultAPIBaseURL: URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String ?? ""
        return URL(string: raw) ?? vpsBaseURL
    }

    /// Belge yükleme sınırları (sunucu sözleşmesiyle uyumlu, biraz pay bırakılarak).
    static let maxInlinePDFBytes = 15 * 1024 * 1024
    static let maxTotalPayloadBytes = 13 * 1024 * 1024   // base64 öncesi; base64 sonrası ≈ 17,3 MB
    static let maxImages = 20
    static let maxTotalTextCharacters = 400_000
    static let maxImageDimension: CGFloat = 2000
}

/// İsteğin nerede işleneceği. Claude'a dayanan uçlar uygulamanın içinde çalışır (gömülü motor; Claude önce VPS'teki vekilden, o
/// yanıt veremezse API anahtarıyla doğrudan çağrılır). İki yol da kabul etmezse (kredi, kullanım sınırı, anahtar, bağlantı) aynı istek yedeğe, yani sunucuya gider;
/// orada Claude vekil üzerinden çağrılır. Cihazda yapılamayan işler (sunucu sesleri, YouTube, akış, yedek) hep sunucudadır.
nonisolated enum Backend {
    /// Yalnız Claude'a dayanan, uygulamanın içinde çalışan uçlar.
    static let enginePaths: Set<String> = [
        "/v1/script", "/v1/script-models", "/v1/study", "/v1/study-v2", "/v1/quiz-more", "/v1/recall-check", "/v1/topics", "/v1/discriminate",
        "/v1/library-ask", "/v1/vocab", "/v1/verify-script", "/v1/verify-deck", "/v1/slides", "/v1/rewrite-scene", "/v1/pronunciation-suggest",
        "/v1/fix-turns", "/v1/evaluate", "/v1/deck", "/v1/voice-ask", "/v1/assistant", "/v1/figures", "/v1/figure-map", "/v1/coach", "/v1/speech-readings",
        // A/B kare hakemi (madde 42). Ders Video'da soru uçlarını uygulama içine `QSClient` yönlendirir; burada da kayıtlıdır.
        "/v1/questions/judge-frames",
    ]
    /// Ayarlardan kapatılabilir: açıkken her istek sunucuya gider.
    static let serverOnlyKey = "backend.serverOnly"
    /// Claude API kredi ya da anahtar yüzünden "kullanılamıyor" döndükten (ya da motor çalışmadığında) bu süre boyunca istekler
    /// doğrudan yedeğe gider. Kullanım sınırında Claude'un bildirdiği bekleme süresi uygulanır.
    static let suspension: TimeInterval = 600
    /// Askı süresinin sınırları: çok kısa süre iki yol arasında gidip gelmeye, çok uzun süre gereksiz yere yedekte kalmaya yol açar.
    static let suspensionBounds: ClosedRange<TimeInterval> = 30...3600

    private static let lock = NSLock()
    nonisolated(unsafe) private static var suspendedUntil = Date.distantPast
    /// Testlerde gerçek (ücretli) Claude çağrısı yapılmasın diye istekler motora yönlenmez; `LIVE_ENGINE=1` ile açılır.
    private static let disabledForTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil && environment["LIVE_ENGINE"] != "1"
    }()

    /// VPS'teki Claude vekilinin (abonelik hesabı) Anthropic uyumlu ucu: uygulama içi motorun birinci yolu (kullanıcı kararı,
    /// 12 Eki 2026); API anahtarı ikinci yoldur. Sunucu adresini izler; erişim anahtarı yoksa vekil denenmez.
    static var claudeProxyURL: URL? {
        PersonalToken.current == nil ? nil : Config.apiBaseURL.appending(path: "claude/v1")
    }

    /// Uygulama içi Claude şu an kullanılabilir mi: bir yol (vekil için erişim anahtarı ya da API anahtarı) var, elle kapatılmamış ve
    /// yakın zamanda "kullanılamıyor" dönmemiş.
    static var engineReady: Bool {
        guard !disabledForTests, !UserDefaults.standard.bool(forKey: serverOnlyKey), ClaudeKey.current != nil || PersonalToken.current != nil else { return false }
        return lock.withLock { suspendedUntil <= .now }
    }

    static func usesEngine(_ path: String) -> Bool { enginePaths.contains(path) && engineReady }
    /// Süren bir askı kısaltılmaz: daha uzun olan geçerlidir.
    static func suspendEngine(for duration: TimeInterval = suspension) {
        let until = Date.now.addingTimeInterval(min(max(duration, suspensionBounds.lowerBound), suspensionBounds.upperBound))
        lock.withLock { suspendedUntil = max(suspendedUntil, until) }
    }
    static func resumeEngine() { lock.withLock { suspendedUntil = .distantPast } }
    /// Askının bittiği an (testler ve tanılama için); askı yoksa geçmişte bir tarih.
    static var engineSuspendedUntil: Date { lock.withLock { suspendedUntil } }
}
