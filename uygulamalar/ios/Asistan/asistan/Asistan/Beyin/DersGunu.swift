import Foundation

/// P3.11: ana ekran / kilit ekranı widget'larının okuduğu anlık. Ana uygulama yazar (`WidgetYenileyici`), widget uzantısı
/// App Group'tan okur. Widget uygulama kapalıyken takvimi kendisi okumaz: önümüzdeki 36 saatin olayları önceden yazılır,
/// zaman çizelgesi ders sınırlarında kendiliğinden ilerler.
nonisolated struct WidgetAnlik: Codable, Equatable, Sendable {
    nonisolated struct Olay: Codable, Equatable, Sendable {
        var baslik: String
        var baslangic: Date
        var bitis: Date
        var yer: String?
    }

    var olaylar: [Olay]
    var takvimIzni: Bool
    /// Son başarılı yanıtın kısaltılmış hâli (`DersGunu.kisalt`, ≤160 karakter); widget'ta `.privacySensitive()` gösterilir.
    var sonYanit: String?
    /// Son yanıtın sohbeti (UUID metni); dokununca `asistan://sohbet?kimlik=` açılır.
    var sonSohbetID: String?
    var sonYanitZamani: Date?
    var guncelleme: Date
}

/// Widget'ın gösterdiği hazır soru (uygulamaya gömülü sabit metin; dış bağlantı yalnız numara taşır).
nonisolated struct HizliIstem: Equatable, Sendable, Identifiable {
    let no: Int
    let baslik: String
    let simge: String
    let istem: String
    var id: Int { no }
}

/// Saf widget mantığı ve App Group dosyası. Hem uygulamaya hem AsistanKontrol uzantısına derlenir (EventKit içe aktarmaz).
nonisolated enum DersGunu {
    /// `PaylasimKutusu.grup` ile aynı değer; PaylasimKutusu uzantıya derlenmediği için burada yinelenir.
    static let grup = "group.com.mehmetderin.asistan"
    /// Olayların ileriye doğru yazıldığı pencere.
    static let pencere: TimeInterval = 36 * 3_600

    /// container/Widget/anlik.json (App Group yoksa nil).
    static var dosya: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grup)?
            .appendingPathComponent("Widget", isDirectory: true)
            .appendingPathComponent("anlik.json")
    }

    static func oku(_ url: URL? = dosya) -> WidgetAnlik? {
        guard let url, let veri = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetAnlik.self, from: veri)
    }

    /// Atomik yazar; cihaz kilitliyken widget okuyabilsin diye koruma `completeUntilFirstUserAuthentication`.
    static func yaz(_ a: WidgetAnlik, _ url: URL? = dosya) throws {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let veri = try JSONEncoder().encode(a)
        try veri.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: Saf kararlar

    /// Süren olay (başlamış, bitmemiş) önce gelir; yoksa en yakın başlayacak olay. Geçmiş olaylar atlanır.
    static func siradaki(_ o: [WidgetAnlik.Olay], simdi: Date) -> (olay: WidgetAnlik.Olay, suruyor: Bool)? {
        let suren = o.filter { $0.baslangic <= simdi && $0.bitis > simdi }
            .min { ($0.bitis, $0.baslangic) < ($1.bitis, $1.baslangic) }
        if let suren { return (suren, true) }
        let gelecek = o.filter { $0.baslangic > simdi }.min { $0.baslangic < $1.baslangic }
        return gelecek.map { ($0, false) }
    }

    /// Bugünün kalan olayları: bugünle kesişen ve henüz bitmemiş olaylar, başlangıca göre sıralı.
    static func bugun(_ o: [WidgetAnlik.Olay], simdi: Date, takvim: Calendar = .current) -> [WidgetAnlik.Olay] {
        let gunBasi = takvim.startOfDay(for: simdi)
        guard let gunSonu = takvim.date(byAdding: .day, value: 1, to: gunBasi) else { return [] }
        return o.filter { $0.baslangic < gunSonu && $0.bitis > gunBasi && $0.bitis > simdi }
            .sorted { $0.baslangic < $1.baslangic }
    }

    /// Zaman çizelgesinin girdi anları: şimdi + her başlangıç ve bitiş + gece yarısı (bugün listesi yenilensin);
    /// sıralı, benzersiz, 36 saatle ve `enFazla` adetle sınırlı.
    static func zamanNoktalari(_ o: [WidgetAnlik.Olay], simdi: Date, enFazla: Int = 30, takvim: Calendar = .current) -> [Date] {
        let son = simdi.addingTimeInterval(pencere)
        var kume = Set<Date>()
        for olay in o { kume.insert(olay.baslangic); kume.insert(olay.bitis) }
        if let geceYarisi = takvim.date(byAdding: .day, value: 1, to: takvim.startOfDay(for: simdi)) { kume.insert(geceYarisi) }
        let ileri = kume.filter { $0 > simdi && $0 <= son }.sorted()
        return Array(([simdi] + ileri).prefix(max(1, enFazla)))
    }

    /// Yanıtı widget satırına indirger: Markdown işaretleri ve bağlantı adresleri atılır, boşluklar tekleşir,
    /// `sinir` aşılırsa kelime sınırında kesilip "…" eklenir (sonuç `sinir` karakteri aşmaz).
    static func kisalt(_ yanit: String, sinir: Int = 160) -> String {
        var t = yanit
        // [metin](adres) → metin
        t = t.replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        // Satır başı başlık, alıntı ve liste işaretleri
        t = t.replacingOccurrences(of: #"(?m)^\s*(#{1,6}|>|[-*+]|\d+[.)])\s+"#, with: "", options: .regularExpression)
        for isaret in ["**", "__", "*", "`", "|", "#", "~~"] { t = t.replacingOccurrences(of: isaret, with: "") }
        t = t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard sinir > 1, t.count > sinir else { return t }
        var govde = String(t.prefix(sinir - 1))
        if t[t.index(t.startIndex, offsetBy: sinir - 1)] != " ", let bosluk = govde.lastIndex(of: " ") {
            govde = String(govde[..<bosluk])
        }
        return govde.trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: Biçim (widget metinleri; DateFormatter'sız, saf)

    /// "09:05" biçiminde saat.
    static func saat(_ d: Date, takvim: Calendar = .current) -> String {
        let c = takvim.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Saatin yönelme eki, okunuşa göre: 10:50 → "ye" (elli), 11:00 → "e" (on bir), 10:30 → "a" (otuz), 00:00 → "a" (sıfır).
    static func yonelmeEki(saat: Int, dakika: Int) -> String {
        let n = dakika != 0 ? dakika : saat
        if n == 0 { return "a" }   // sıfır
        let birler = n % 10
        if birler != 0 {
            // bir, iki, üç, dört, beş, altı, yedi, sekiz, dokuz
            return ["e", "ye", "e", "e", "e", "ya", "ye", "e", "a"][birler - 1]
        }
        // on, yirmi, otuz, kırk, elli
        return ["a", "ye", "a", "a", "ye"][min(4, n / 10 - 1)]
    }

    /// "10:50'ye kadar".
    static func kadar(_ d: Date, takvim: Calendar = .current) -> String {
        let c = takvim.dateComponents([.hour, .minute], from: d)
        return "\(saat(d, takvim: takvim))'\(yonelmeEki(saat: c.hour ?? 0, dakika: c.minute ?? 0)) kadar"
    }

    /// Başlangıç saati; bugün değilse "yarın 08:30" ya da "Pzt 08:30" öneki alır.
    static func baslangicMetni(_ d: Date, simdi: Date, takvim: Calendar = .current) -> String {
        if takvim.isDate(d, inSameDayAs: simdi) { return saat(d, takvim: takvim) }
        if let yarin = takvim.date(byAdding: .day, value: 1, to: simdi), takvim.isDate(d, inSameDayAs: yarin) {
            return "yarın " + saat(d, takvim: takvim)
        }
        let gunler = ["Paz", "Pzt", "Sal", "Çar", "Per", "Cum", "Cmt"]
        let g = takvim.component(.weekday, from: d)
        return gunler[(g - 1 + 7) % 7] + " " + saat(d, takvim: takvim)
    }

    /// Kilit ekranı satırı: "Şimdi: Toplantı · 10:50'ye kadar" ya da "Sıradaki: Toplantı · 11:00"; olay yoksa nil.
    static func siradakiMetni(_ o: [WidgetAnlik.Olay], simdi: Date, takvim: Calendar = .current) -> String? {
        guard let s = siradaki(o, simdi: simdi) else { return nil }
        if s.suruyor { return "Şimdi: \(s.olay.baslik) · \(kadar(s.olay.bitis, takvim: takvim))" }
        return "Sıradaki: \(s.olay.baslik) · \(baslangicMetni(s.olay.baslangic, simdi: simdi, takvim: takvim))"
    }

    // MARK: Hızlı sor

    /// Widget'taki hazır sorular. `asistan://hizli?no=N` yalnız bu sabit metinleri çalıştırır; dış uygulama metni değiştiremez.
    static let hizliIstemler: [HizliIstem] = [
        HizliIstem(no: 1, baslik: "Bugün ne var?", simge: "calendar", istem: "Bugünkü etkinliklerimi kısaca söyle."),
        HizliIstem(no: 2, baslik: "Hava", simge: "cloud.sun", istem: "Bugün hava nasıl?"),
        HizliIstem(no: 3, baslik: "Hatırlatıcılar", simge: "checklist", istem: "Bugünkü hatırlatıcılarımı listele."),
        HizliIstem(no: 4, baslik: "Sabah özeti", simge: "sunrise", istem: "Sabah özeti: bugünkü etkinliklerim, hava ve hatırlatıcılarım."),
    ]

    static func hizliIstem(_ no: Int) -> String? {
        hizliIstemler.first { $0.no == no }?.istem
    }

    static func hizliAdres(_ no: Int) -> URL? {
        URL(string: "asistan://hizli?no=\(no)")
    }
}
