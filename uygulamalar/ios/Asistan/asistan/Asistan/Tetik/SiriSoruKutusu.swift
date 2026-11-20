import Foundation

/// O4: Siri / tetik devrinin (`GorevKopru.teslimEt`) kalıcı posta kutusundaki bir kaydı.
nonisolated struct SiriSoruKaydi: Codable, Equatable, Sendable {
    var id = UUID()
    let metin: String
    let zaman: Date
    /// Kaydı yazan sürecin kimliği (`SiriSoruKutusu.surec`): aynı süreçteki kayıtları köprünün yeniden yayın döngüsü teslim eder.
    var surec: String
}

/// O4: Siri'den uygulamaya devredilen sorunun kalıcı kutusu (Application Support/siri-soru-kutusu.json).
/// Köprü soruyu teslim ederken yazar, Beyin kabul edince (`GorevKopru.kabul`) ya da istek kalıcı çevrimdışı kuyruğa
/// girince (`GorevKopru.kuyrugaAlindi`) silinir. Uygulama soru gönderilmeden kapanır ya da çökerse önceki süreçten kalan
/// kayıtlar açılışta `eskiler()` ile alınır: `omur` içindekiler iç sıraya (`DisSoruKuyrugu.ic`) girer, eskileri
/// gönderilmez, kullanıcıya not gösterilir. Yalnız kabulü kesin eşleşen istekler (`GorevKopru.yinelenebilir`) yazılır:
/// eğik çizgi komutu ya da 4000 karakteri aşan metin her açılışta yeniden çalışmasın.
@MainActor
final class SiriSoruKutusu {
    static let ortak = SiriSoruKutusu()
    /// Bu sürecin kimliği (her açılışta yeni).
    nonisolated static let surec = UUID().uuidString
    /// Önceki süreçten kalan soru en çok bu kadar eskiyse kendiliğinden gönderilir (saniye).
    nonisolated static let omur: TimeInterval = 3_600
    nonisolated static let enFazla = 5

    private(set) var kayitlar: [SiriSoruKaydi]
    let dosya: URL

    /// Varsayılan dosya; testte/sınamada (`CevrimdisiKuyruk.yalitilmis`) kullanıcının gerçek kutusuna dokunulmaz.
    nonisolated static func varsayilanDosya() -> URL {
        if CevrimdisiKuyruk.yalitilmis {
            return FileManager.default.temporaryDirectory.appending(path: "siri-soru-kutusu-\(UUID().uuidString).json")
        }
        return URL.applicationSupportDirectory.appending(path: "siri-soru-kutusu.json")
    }

    init(dosya: URL? = nil) {
        let d = dosya ?? Self.varsayilanDosya()
        self.dosya = d
        kayitlar = Self.oku(d)
    }

    /// Okuma hatası ya da bozuk JSON → boş liste. Dosya bozuksa bir sonraki yazım üzerine yazacağı için özgün içerik önce
    /// `BozukDosya.sakla` ile yanına yedeklenir.
    nonisolated static func oku(_ dosya: URL) -> [SiriSoruKaydi] {
        guard let veri = try? Data(contentsOf: dosya), !veri.isEmpty else { return [] }
        do { return try JSONDecoder().decode([SiriSoruKaydi].self, from: veri) }
        catch { BozukDosya.sakla(dosya); return [] }
    }

    private func kaydet() {
        do {
            try FileManager.default.createDirectory(at: dosya.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Siri kilit ekranından gelebilir: ilk kilit açılışından sonra yazılabilir koruma.
            try JSONEncoder().encode(kayitlar).write(to: dosya, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            TaniGunlugu.yaz("SİRİ KUTUSU: yazılamadı (\(error.localizedDescription))")
        }
    }

    /// Soruyu kutuya yazar; boş ya da kutuda zaten olan metin eklenmez.
    func ekle(_ metin: String, simdi: Date = .now) {
        let t = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !kayitlar.contains(where: { $0.metin == t }) else { return }
        kayitlar = Self.ayikla(kayitlar + [SiriSoruKaydi(metin: t, zaman: simdi, surec: Self.surec)], simdi: simdi)
        kaydet()
    }

    /// Metni kutudan siler; kutuda yoksa diske yazmaz (her `Beyin.gonder` → `kabul` disk yazımı yapmasın).
    func cikar(metin: String) {
        let t = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        let once = kayitlar.count
        kayitlar.removeAll { $0.metin == t }
        guard kayitlar.count != once else { return }
        kaydet()
    }

    /// Önceki süreçlerden kalan kayıtlar: `omur` içindekiler gönderilecek (kutuda kalır, bu sürece devralınır; kabul
    /// edilince silinir), eskileri düşer ve kutudan silinir. Aynı süreçteki kayıtlar ikisine de girmez.
    func eskiler(simdi: Date = .now) -> (gonderilecek: [String], dusen: [String]) {
        let (g, d) = Self.ayir(kayitlar, simdi: simdi, surec: Self.surec)
        guard !g.isEmpty || !d.isEmpty else { return ([], []) }
        let dusenler = Set(d.map(\.id))
        let devralinan = Set(g.map(\.id))
        kayitlar = kayitlar.compactMap { k in
            if dusenler.contains(k.id) { return nil }
            var y = k
            if devralinan.contains(k.id) { y.surec = Self.surec }   // ikinci çağrı aynı kaydı yeniden vermesin
            return y
        }
        kaydet()
        return (g.map(\.metin), d.map(\.metin))
    }

    /// Saf: ömrü dolanları atar, yinelenen metni (en yenisini tutarak) tekler, son `enFazla` kaydı tutar.
    nonisolated static func ayikla(_ k: [SiriSoruKaydi], simdi: Date, omur: TimeInterval = SiriSoruKutusu.omur, enFazla: Int = SiriSoruKutusu.enFazla) -> [SiriSoruKaydi] {
        var gorulen: Set<String> = []
        var tersten: [SiriSoruKaydi] = []
        for kayit in k.reversed() where simdi.timeIntervalSince(kayit.zaman) <= omur {
            guard gorulen.insert(kayit.metin).inserted else { continue }
            tersten.append(kayit)
        }
        return Array(tersten.reversed().suffix(max(0, enFazla)))
    }

    /// Saf: başka süreçten kalan kayıtları ömre göre ikiye ayırır; `surec` ile aynı süreçten olanlar dışarıda kalır.
    nonisolated static func ayir(_ k: [SiriSoruKaydi], simdi: Date, surec: String, omur: TimeInterval = SiriSoruKutusu.omur) -> (gonderilecek: [SiriSoruKaydi], dusen: [SiriSoruKaydi]) {
        let onceki = k.filter { $0.surec != surec }
        let taze = onceki.filter { simdi.timeIntervalSince($0.zaman) <= omur }
        let eski = onceki.filter { simdi.timeIntervalSince($0.zaman) > omur }
        return (taze, eski)
    }

    /// Saf: önceki süreçten kalıp gönderilmeyen (ömrü dolan) sorular için kullanıcıya gösterilecek not.
    nonisolated static func dusmeNotu(_ l: [String]) -> String? {
        guard let ilk = l.first else { return nil }
        let alinti = "“\(ilk.prefix(60))”"
        if l.count == 1 { return "Siri'den devredilen isteğin uygulama kapandığı için bir saatten uzun bekledi ve gönderilmedi: \(alinti). Yeniden söyleyebilirsin." }
        return "Siri'den devredilen \(l.count) isteğin uygulama kapandığı için bir saatten uzun bekledi ve gönderilmedi (ilki: \(alinti)). Yeniden söyleyebilirsin."
    }
}
