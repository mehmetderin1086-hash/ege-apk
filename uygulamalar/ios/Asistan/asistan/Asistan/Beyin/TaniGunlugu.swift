import Foundation
import os

/// Cihazda oluşan hataları Documents/tani.log dosyasına ekler; Mac'ten `devicectl copy from` ile okunur,
/// uygulamada Sağlık → Tanı günlüğü ile görüntülenir, `/tani` ya da Sağlık → Tanı paketi ile maskeli .zip olur.
///
/// Satır biçimi: `<ISO zaman> <B|U|H> [r=ab12cd] <olay>` (istek kimliği yoksa köşeli bölüm yazılmaz).
/// Kullanıcı metni yazılmaz; yalnız 'Ayrıntılı tanı (24 saat)' açıkken `icerik(_:)` ile yazılır.
/// E-posta, telefon, anahtar, IBAN ve kimlik numarası biçimleri yazım anında maskelenir.
///
/// Kilit düzeni: bütün dosya G/Ç'si tek seri `kuyruk`ta koşar. Genel `yaz(_:seviye:)` çağıranı bekletmez
/// (`kuyruk.async`; düzenli ifadeli satır kurulumu da kuyrukta). Sınanabilir `yaz(_:klasor:)`, `sil(klasor:)` ve
/// `bosalt()` `kuyruk.sync` kullanır; bunlar KUYRUĞUN İÇİNDEN hiçbir zaman çağrılmaz (aynı seri kuyrukta sync kilitlenir).
nonisolated enum TaniGunlugu {
    /// Döndürme sınırı: aşılınca tani.log → tani.1.log olur (önceki geçmiş tümüyle silinmez).
    static let sinir = 500_000
    /// Ayrıntılı tanı kapalıyken bir olay en çok bu kadar karakter yazılır (hata dökümleri uzayabilir).
    static let kisaSinir = 600
    /// Ayrıntılı tanı açıkken bile tek satırın üst sınırı (maskeleme taraması sınırlı kalsın).
    static let uzunSinir = 4000
    static let ayrintiliAnahtar = "tani.ayrintiliBitisV1"
    static let dosyaAdi = "tani.log"
    static let eskiDosyaAdi = "tani.1.log"

    enum Seviye: String, Sendable, CaseIterable {
        case bilgi = "B", uyari = "U", hata = "H"

        var osSeviye: OSLogType {
            switch self { case .bilgi: .info; case .uyari: .default; case .hata: .error }
        }
    }

    /// İsteğin tanı kimliği: `Beyin.gonder` bir isteğin görevini `$istek.withValue(...)` içinde başlatır;
    /// yapılandırılmış ve yapılandırılmamış (`Task {}`) alt görevler kimliği miras alır, `Task.detached` almaz.
    @TaskLocal static var istek: String? = nil

    private static let kuyruk = DispatchQueue(label: "asistan.tani-gunlugu", qos: .utility)
    private static let log = Logger(subsystem: "com.mehmetderin.asistan", category: "tani")

    static var varsayilanKlasor: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    /// 6 küçük harfli onaltılık hane (istek kimliği).
    static func yeniKimlik() -> String {
        String(format: "%06x", UInt32.random(in: 0...0xFFFFFF))
    }

    // MARK: Seviye

    private static let hataIzleri = ["HATA", "hata", "DÜŞTÜ", "ÖLÜ", "BAŞARISIZ", "AÇILAMADI", "kaydedilemedi", "istenemedi",
                                     "çözülemedi", "yazılamadı", "kurulamadı", "taşınamadı", "Çökme"]
    private static let uyariIzleri = ["koptu", "atlandı", "ATLANDI", "SÜRESİ DOLDU", "süresi doldu", "bırakıldı", "uyarı", "UYARI", "Takılma"]

    /// Olay metninden seviye tahmini ('MODEL HATA …' → H, 'AĞ koptu' → U, öbürleri B). 'GEÇİCİ HATA' uyarıdır.
    static func tahmin(_ olay: String) -> Seviye {
        if olay.contains("GEÇİCİ") { return .uyari }
        if hataIzleri.contains(where: { olay.contains($0) }) { return .hata }
        if uyariIzleri.contains(where: { olay.contains($0) }) { return .uyari }
        return .bilgi
    }

    // MARK: Ayrıntılı tanı (24 saat)

    /// Ayrıntılı tanının bitiş zamanı; nil ya da geçmişse kapalıdır. Ana aktör dışından okunabilsin diye UserDefaults'ta.
    static var ayrintiliBitis: Date? {
        get { UserDefaults.standard.object(forKey: ayrintiliAnahtar) as? Date }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: ayrintiliAnahtar) }
            else { UserDefaults.standard.removeObject(forKey: ayrintiliAnahtar) }
        }
    }

    static var ayrintiliAcik: Bool { (ayrintiliBitis ?? .distantPast) > .now }

    /// Kullanıcı içeriği (istek metni vb.) yalnız ayrıntılı tanı açıkken yazılır; kapalıyken yalnız uzunluğu.
    static func icerik(_ s: String) -> String { ayrintiliAcik ? s : "‹\(s.count) karakter›" }

    // MARK: Yazım

    /// Çağıranı bekletmez: zaman, istek kimliği ve seviye burada yakalanır; satır kurulumu, OSLog ve dosya kuyrukta.
    static func yaz(_ olay: String, seviye: Seviye? = nil) {
        let zaman = Date.now, r = istek
        kuyruk.async {
            let s = seviye ?? tahmin(olay)
            let metin = satir(olay, zaman: zaman, istek: r, seviye: s)
            log.log(level: s.osSeviye, "\(metin, privacy: .private)")
            guard let klasor = varsayilanKlasor else { return }
            ekle(metin, klasor: klasor, sinir: sinir)
        }
    }

    /// Sınanabilir eşzamanlı çekirdek: verilen klasördeki tani.log'a ekler (döner döndüğünde satır dosyadadır).
    /// Kuyruğun içinden çağrılmaz.
    static func yaz(_ olay: String, klasor: URL, sinir: Int = TaniGunlugu.sinir, seviye: Seviye? = nil) {
        let metin = satir(olay, zaman: .now, istek: istek, seviye: seviye ?? tahmin(olay))
        kuyruk.sync { ekle(metin, klasor: klasor, sinir: sinir) }
    }

    /// Satır kurucu: tek satıra indirir, kısaltır, maskeler ve önekler (sonda satır sonu yok).
    static func satir(_ olay: String, zaman: Date, istek: String?, seviye: Seviye) -> String {
        let kimlik = istek.map { "[r=\($0)] " } ?? ""
        return "\(zaman.ISO8601Format()) \(seviye.rawValue) \(kimlik)\(maskele(kisalt(olay)))"
    }

    /// Satır sonları görünür işarete döner (bir olay = bir satır); ayrıntılı tanı kapalıyken 600 karakterde kesilir.
    static func kisalt(_ olay: String) -> String {
        let tek = olay.replacingOccurrences(of: "\r\n", with: " ⏎ ").replacingOccurrences(of: "\n", with: " ⏎ ")
        let n = ayrintiliAcik ? uzunSinir : kisaSinir
        return tek.count > n ? String(tek.prefix(n)) + "…" : tek
    }

    /// Bekleyen bütün yazımlar dosyaya geçene kadar bekler (tanı paketi ve testler için). Kuyruğun içinden çağrılmaz.
    static func bosalt() { kuyruk.sync {} }

    /// Kilitsiz çekirdek; YALNIZ `kuyruk` üzerinde çağrılır. Boyut denetimi, döndürme ve ekleme.
    private static func ekle(_ metin: String, klasor: URL, sinir: Int) {
        let url = klasor.appendingPathComponent(dosyaAdi)
        let veri = Data((metin + "\n").utf8)
        // Boyut ve yedek bayrağı tek çağrıda okunur; dosya yoksa nil döner (ilk yazım).
        var degerler = try? url.resourceValues(forKeys: [.fileSizeKey, .isExcludedFromBackupKey])
        if let boyut = degerler?.fileSize, boyut > sinir {
            let eski = klasor.appendingPathComponent(eskiDosyaAdi)
            try? FileManager.default.removeItem(at: eski)
            if (try? FileManager.default.moveItem(at: url, to: eski)) == nil { try? FileManager.default.removeItem(at: url) }
            yedektenDisla(eski)
            degerler = nil   // yeni tani.log oluşacak; bayrağı yeniden verilmeli
        }
        if let h = try? FileHandle(forWritingTo: url) { defer { try? h.close() }; _ = try? h.seekToEnd(); try? h.write(contentsOf: veri) }
        else { try? veri.write(to: url) }
        // Tanı günlüğü yalnız bu telefonda kalır: iCloud/bilgisayar yedeğine girmez.
        if degerler?.isExcludedFromBackup != true { yedektenDisla(url) }
    }

    // MARK: Okuma ve silme

    /// tani.1.log + tani.log birleşik, son `adet` satır (en eski önce). Ana aktörde çağrılmaz (dosya G/Ç'si).
    static func sonSatirlar(_ adet: Int = 1000, klasor: URL? = nil) -> [String] {
        bosalt()
        guard let k = klasor ?? varsayilanKlasor else { return [] }
        var satirlar: [String] = []
        for ad in [eskiDosyaAdi, dosyaAdi] {
            guard let veri = try? Data(contentsOf: k.appendingPathComponent(ad)) else { continue }
            satirlar += String(decoding: veri, as: UTF8.self).split(separator: "\n").map(String.init)
        }
        return Array(satirlar.suffix(adet))
    }

    /// Kullanıcı "Kayıtları sil" dediğinde tani.log ve döndürülmüş tani.1.log silinir.
    static func sil() {
        guard let klasor = varsayilanKlasor else { return }
        sil(klasor: klasor)
    }

    /// Sınanabilir çekirdek: verilen klasördeki tanı günlüklerini siler.
    static func sil(klasor: URL) {
        kuyruk.sync {
            for ad in [dosyaAdi, eskiDosyaAdi] {
                try? FileManager.default.removeItem(at: klasor.appendingPathComponent(ad))
            }
        }
    }

    private static func yedektenDisla(_ url: URL) {
        var u = url
        var d = URLResourceValues(); d.isExcludedFromBackup = true
        try? u.setResourceValues(d)
    }

    // MARK: Maskeleme

    /// Önceden derlenmiş kalıplar (sıra önemli: sorgu dizesi ve anahtar önekleri genel kalıplardan önce).
    /// NSRegularExpression değişmez ve iş parçacığı güvenlidir.
    private static let kaliplar: [(NSRegularExpression, String)] = desenler.compactMap { desen, yerine in
        (try? NSRegularExpression(pattern: desen)).map { ($0, yerine) }
    }

    private static let desenler: [(String, String)] = [
        (#"(https?://[^\s?#]+)\?[^\s]+"#, "$1?‹…›"),
        (#"(?i)\bBearer\s+\S+"#, "Bearer ‹anahtar›"),
        (#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, "‹e-posta›"),
        (#"\b(?:sk|pk|rk|sess)-[A-Za-z0-9_\-]{12,}"#, "‹anahtar›"),
        (#"eyJ[\w-]+\.[\w-]+\.[\w-]+"#, "‹anahtar›"),
        (#"(?i)\bTR\d{2}(?:\s?\d{4}){5}\s?\d{2}\b"#, "‹iban›"),
        (#"(?<![\d+])(?:\+?90[\s-]?)?0?5\d{2}[\s-]?\d{3}[\s-]?\d{2}[\s-]?\d{2}(?!\d)"#, "‹telefon›"),
        (#"\b[1-9]\d{10}\b"#, "‹kimlik›"),
        (#"\b[A-Fa-f0-9]{32,}\b"#, "‹anahtar›"),
        // Büyük + küçük harf + rakam karışık, '/' içermeyen 32+ karakter (base64/API anahtarı). Küçük harfli model adları,
        // büyük harfli UUID'ler ve dosya yolları (/ ile bölünür) değişmez.
        (#"(?<![A-Za-z0-9+_\-])(?=[A-Za-z0-9+_\-]*\d)(?=[A-Za-z0-9+_\-]*[a-z])(?=[A-Za-z0-9+_\-]*[A-Z])[A-Za-z0-9+_\-]{32,}={0,2}"#, "‹anahtar›"),
    ]

    /// E-posta, telefon, anahtar/jeton, IBAN, T.C. kimlik no ve URL sorgu dizelerini maskeler.
    static func maskele(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        var m = s
        for (kalip, yerine) in kaliplar {
            m = kalip.stringByReplacingMatches(in: m, range: NSRange(m.startIndex..., in: m), withTemplate: yerine)
        }
        return m
    }
}
