import Foundation

/// Sağlayıcı ailesi: model kimliğinden ("antigravity-claude-…", "gpt-6.1-sol", "gemini-…") çıkarılır.
nonisolated enum SaglayiciAilesi: String, CaseIterable, Codable, Sendable {
    case claude, gpt, gemini, diger
    static func ait(_ model: String) -> SaglayiciAilesi {
        let m = model.lowercased()
        if m.contains("claude") { return .claude }
        if m.hasPrefix("gpt") || m.contains("codex") || m.contains("-gpt-") { return .gpt }
        if m.contains("gemini") { return .gemini }
        return .diger
    }
    var ad: String {
        switch self { case .claude: "Claude"; case .gpt: "ChatGPT / GPT"; case .gemini: "Gemini"; case .diger: "Diğer" }
    }
}

nonisolated struct KullanimSayaci: Codable, Equatable, Sendable {
    var istek = 0
    var basari = 0
    var hata = 0
    var toplam: Int { istek }
}

/// Günlük model/sağlayıcı kullanım sayaçları (yerel, kişisel; hiçbir şey sunucuya gönderilmez). Son 30 gün tutulur.
nonisolated final class KullanimDefteri: @unchecked Sendable {
    enum Olay { case istek, basari, hata }
    struct Kayit: Codable, Equatable {
        var aileler: [String: KullanimSayaci] = [:]
        /// Paralel yarışa giren sohbet sayısı ve bunlar için yapılan toplam sağlayıcı çağrısı.
        var yarisSohbet = 0
        var yarisCagri = 0
    }
    static let ortak = KullanimDefteri()
    static let saklamaGunu = 30

    private let kilit = NSLock()
    private let defaults: UserDefaults
    private let anahtar: String
    private var gunler: [String: Kayit]

    init(defaults: UserDefaults = .standard, anahtar: String = "kullanim.v1") {
        self.defaults = defaults; self.anahtar = anahtar
        gunler = defaults.data(forKey: anahtar).flatMap { try? JSONDecoder().decode([String: Kayit].self, from: $0) } ?? [:]
    }

    static func gunAnahtari(_ t: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: t)
    }

    private func degistir(_ simdi: Date, _ islem: (inout Kayit) -> Void) {
        kilit.lock(); defer { kilit.unlock() }
        let g = Self.gunAnahtari(simdi)
        var k = gunler[g] ?? Kayit()
        islem(&k)
        gunler[g] = k
        if gunler.count > Self.saklamaGunu { gunler.keys.sorted().prefix(gunler.count - Self.saklamaGunu).forEach { gunler[$0] = nil } }
        defaults.set(try? JSONEncoder().encode(gunler), forKey: anahtar)
    }

    func say(_ model: String, _ olay: Olay, simdi: Date = .now) {
        let a = SaglayiciAilesi.ait(model).rawValue
        degistir(simdi) { k in
            var s = k.aileler[a] ?? KullanimSayaci()
            switch olay { case .istek: s.istek += 1; case .basari: s.basari += 1; case .hata: s.hata += 1 }
            k.aileler[a] = s
        }
    }

    /// Bir sohbet `n` sağlayıcıyla paralel yarıştı.
    func yarisSohbeti(saglayiciSayisi n: Int, simdi: Date = .now) {
        degistir(simdi) { $0.yarisSohbet += 1; $0.yarisCagri += n }
    }

    func kayit(_ gun: Date = .now) -> Kayit {
        kilit.lock(); defer { kilit.unlock() }
        return gunler[Self.gunAnahtari(gun)] ?? Kayit()
    }

    /// Son `adet` günün toplam istek sayısı, eskiden yeniye (kullanılmayan günler 0).
    func sonGunler(_ adet: Int = 7, simdi: Date = .now) -> [(gun: String, istek: Int, hata: Int)] {
        (0..<adet).reversed().map { i in
            let t = Calendar.current.date(byAdding: .day, value: -i, to: simdi) ?? simdi
            let k = kayit(t)
            return (Self.gunAnahtari(t), k.aileler.values.reduce(0) { $0 + $1.istek }, k.aileler.values.reduce(0) { $0 + $1.hata })
        }
    }

    func temizle() {
        kilit.lock(); gunler = [:]; defaults.removeObject(forKey: anahtar); kilit.unlock()
    }
}

/// Kota beklemesi özeti (saf mantık): askıda olan modeller, kalan süreyle.
nonisolated enum KotaOzeti {
    struct Bekleme: Equatable, Sendable { let model: String; let kalanSn: Int }

    /// `esikSn` altındaki kısa askılar (ağ dalgalanması) kota sayılmaz; yalnız uzun beklemeler listelenir.
    static func beklemeler(askilar: [String: Date], simdi: Date = .now, esikSn: Int = 120) -> [Bekleme] {
        askilar.compactMap { m, t in
            let kalan = Int(t.timeIntervalSince(simdi))
            return kalan > esikSn ? Bekleme(model: m, kalanSn: kalan) : nil
        }.sorted { $0.kalanSn > $1.kalanSn }
    }

    static func sureMetni(_ sn: Int) -> String { sn >= 3600 ? "\(sn / 3600) sa \((sn % 3600) / 60) dk" : sn >= 60 ? "\(sn / 60) dk" : "\(sn) sn" }

    /// Sohbette gösterilecek uyarı; hiç bekleme yoksa nil.
    static func uyari(_ b: [Bekleme]) -> String? {
        guard !b.isEmpty else { return nil }
        let aileler = Dictionary(grouping: b) { SaglayiciAilesi.ait($0.model) }
        let satir = aileler.sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.ad) (\(sureMetni($0.value.map(\.kalanSn).max() ?? 0)))" }.joined(separator: ", ")
        return "Kota/erişim beklemesi: \(satir). Diğer sağlayıcılara geçiliyor."
    }
}
