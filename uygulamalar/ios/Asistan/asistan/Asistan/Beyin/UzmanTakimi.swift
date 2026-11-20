import Foundation
import Observation

struct AsistanUzmani: Codable, Identifiable, Hashable {
    let id: UUID
    var ad: String
    var unvan: String
    var aciklama: String
    var simge: String
    var sablon: Bool
}

@MainActor @Observable
final class UzmanTakimi {
    static let ortak = UzmanTakimi()
    private let defaults: UserDefaults
    private let veriAnahtari = "asistan.uzmanlar.v1"
    private let secimAnahtari = "asistan.uzmanlar.secim.v1"
    private(set) var uzmanlar: [AsistanUzmani] = []
    var secilenler: Set<UUID> = [] { didSet { kaydetSecim() } }

    static let sablonlar: [AsistanUzmani] = [
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!, ad: "Araştırmacı", unvan: "Kaynak araştırması", aciklama: "Güncel ve birincil kaynakları bulur; iddiaları kanıtlarla ayırır ve bağlantıları doğrular.", simge: "magnifyingglass", sablon: true),
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!, ad: "Yazar", unvan: "Yazı ve belge", aciklama: "Mehmet'in amacına ve üslubuna uygun, açık ve iyi yapılandırılmış metinler hazırlar.", simge: "pencil.line", sablon: true),
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!, ad: "Kodcu", unvan: "Yazılım geliştirme", aciklama: "Kodlama işlerini planlar, sunucu çalışma alanına aktarır, test sonucunu ve sınırlamaları raporlar.", simge: "chevron.left.forwardslash.chevron.right", sablon: true),
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!, ad: "Denetçi", unvan: "Doğruluk ve kalite", aciklama: "Taslağı bağımsız gözle denetler; eksik kanıtı, çelişkiyi ve tamamlanmamış işlemi işaretler.", simge: "checkmark.seal", sablon: true),
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!, ad: "Ofis Uzmanı", unvan: "DOCX, XLSX, PPTX ve PDF", aciklama: "Bilgiyi uygun ofis biçimine dönüştürür; tablo, belge, sunum ve PDF çıktısını doğrular.", simge: "doc.on.doc", sablon: true),
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000006")!, ad: "Koordinatör", unvan: "Ekip ve görev yönetimi", aciklama: "İşi uzmanlara böler, bağımlılık sırasını kurar ve sonuçları tek, tutarlı bir yanıtta birleştirir.", simge: "person.3", sablon: true),
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let ozel = defaults.data(forKey: veriAnahtari).flatMap { try? JSONDecoder().decode([AsistanUzmani].self, from: $0) } ?? []
        uzmanlar = Self.sablonlar + ozel.filter { !$0.sablon }
        let kimlikler = defaults.array(forKey: secimAnahtari) as? [String] ?? []
        secilenler = Set(kimlikler.compactMap(UUID.init(uuidString:)))
    }

    func sec(_ id: UUID) {
        if secilenler.contains(id) { secilenler.remove(id) }
        else if secilenler.count < 6 { secilenler.insert(id) }
    }

    func ekle(ad: String, unvan: String, aciklama: String) {
        let temizAd = String(ad.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        let temizUnvan = String(unvan.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        let temizAciklama = String(aciklama.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        guard !temizAd.isEmpty, !temizAciklama.isEmpty else { return }
        uzmanlar.append(.init(id: UUID(), ad: temizAd, unvan: temizUnvan, aciklama: temizAciklama, simge: "person.crop.circle.badge.plus", sablon: false))
        kaydet()
    }

    func cogalt(_ uzman: AsistanUzmani) {
        uzmanlar.append(.init(id: UUID(), ad: String((uzman.ad + " Kopya").prefix(40)), unvan: uzman.unvan, aciklama: uzman.aciklama, simge: uzman.simge, sablon: false))
        kaydet()
    }

    func sil(_ uzman: AsistanUzmani) {
        guard !uzman.sablon else { return }
        uzmanlar.removeAll { $0.id == uzman.id }; secilenler.remove(uzman.id); kaydet()
    }

    func baglam(istek: String) -> String? {
        let etiketlenen = uzmanlar.filter { istek.localizedCaseInsensitiveContains("@" + $0.ad.replacingOccurrences(of: " ", with: "")) || istek.localizedCaseInsensitiveContains("@" + $0.ad) }
        let secili = uzmanlar.filter { secilenler.contains($0.id) }
        let otomatik = otomatikSec(istek)
        let etkin = !etiketlenen.isEmpty ? etiketlenen : (!secili.isEmpty ? secili : otomatik)
        guard !etkin.isEmpty else { return nil }
        let secim = !etiketlenen.isEmpty ? "etiketli seçim" : (!secili.isEmpty ? "elle seçim" : "otomatik seçim")
        let roller = etkin.prefix(6).map { "- \($0.ad) (\($0.unvan)): \($0.aciklama)" }.joined(separator: "\n")
        return """
        [Etkin uzman ekibi · \(secim)]
        \(roller)
        Her uzman isteği kendi rolünden incelesin. Birden fazla uzman varsa Koordinatör gibi görev sırasını kur, farklı değerlendirmeleri tek tutarlı sonuçta birleştir ve hangi gerçek araçların çalıştığını işlem günlüğünden ayır. Uzmanların ayrı ayrı çalıştığını veya dış sistemlere eriştiğini uydurma.
        [Uzman ekibi sonu]
        """
    }

    /// Atölye otomatik kipinden bağımsız, isteğin içeriğine göre rol bağlamı seçer.
    /// Kullanıcının açık @etiketi ve ekranda yaptığı seçim her zaman önceliklidir.
    private func otomatikSec(_ istek: String) -> [AsistanUzmani] {
        let adlar = Self.otomatikAdlar(istek)
        return uzmanlar.filter { adlar.contains($0.ad) }
    }

    /// İstekten otomatik seçilecek uzman adları. Desenler sözcük başına bağlı: "hücre testi" Kodcu'yu,
    /// "kodon"/"protestan" alt dizeleri rolü tetiklemez; noktasız ı katlamada i'ye çevrilir ("araştır", "yazı").
    nonisolated static func otomatikAdlar(_ istek: String) -> Set<String> {
        let metin = istek.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
        let eslesmeler: [(String, [String])] = [
            (#"\b(arastir|kaynak|guncel|haber|kanit|incele)"#, ["Araştırmacı"]),
            // "kod" yalnız Türkçe ekleriyle (kodu/kodum/koda/kodda/koddan/kodla…): "kodon", "kodominant", "kodaman" eşleşmez.
            (#"\b(kod(u\w*|a|da\w*|dan|la\w*)?|swift\w*|python\w*|javascript\w*|debug\w*|birim test\w*|unit test\w*|yazilim test\w*|uygulama gelistir\w*)\b"#, ["Kodcu"]),
            (#"\b(pdf|word|docx|excel|xlsx|pptx|sunum|ofis|zip|rar)"#, ["Ofis Uzmanı"]),
            (#"\b(yazi|metin|makale|cevir|ozet|mesaj)"#, ["Yazar"]),
            (#"\b(denetle|kontrol|dogrula|elestir|duzelt|hata)"#, ["Denetçi"]),
            (#"\b(plan|takvim|rutin|gorev|organize)"#, ["Koordinatör"])
        ]
        return Set(eslesmeler.filter { metin.range(of: $0.0, options: .regularExpression) != nil }.flatMap(\.1))
    }

    func disariAktar(_ uzman: AsistanUzmani) throws -> URL {
        let data = try JSONEncoder().encode(uzman)
        let url = FileManager.default.temporaryDirectory.appending(path: "\(uzman.ad.replacingOccurrences(of: " ", with: "-"))-uzman.json")
        try data.write(to: url, options: .atomic); return url
    }

    private func kaydet() {
        let ozel = uzmanlar.filter { !$0.sablon }
        if let data = try? JSONEncoder().encode(ozel) { defaults.set(data, forKey: veriAnahtari) }
    }
    private func kaydetSecim() { defaults.set(secilenler.map(\.uuidString), forKey: secimAnahtari) }
}

struct AsistanBecerisi: Codable, Identifiable, Hashable {
    let id: UUID
    var ad: String
    var istem: String
    var simge: String
    var sablon: Bool
}

@MainActor @Observable
final class BeceriKitapligi {
    static let ortak = BeceriKitapligi()
    private let defaults: UserDefaults
    private let anahtar = "asistan.beceriler.v1"
    private(set) var beceriler: [AsistanBecerisi]
    static let sablonlar: [AsistanBecerisi] = [
        .init(id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!, ad: "Kaynaklı araştırma", istem: "Bu konuyu güncel birincil kaynaklarla araştır. Bulguları, belirsizlikleri ve doğrudan bağlantıları düzenli bir raporda ver.", simge: "globe", sablon: true),
        .init(id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!, ad: "Belge üret", istem: "Bu içerikten düzenli bir ofis belgesi oluştur. Uygun başlıkları, maddeleri ve gerekiyorsa tabloyu ekle; gerçek dosyayı üretip doğrula.", simge: "doc.badge.plus", sablon: true),
        .init(id: UUID(uuidString: "20000000-0000-0000-0000-000000000003")!, ad: "Kodla ve sına", istem: "Bu yazılım işini sunucudaki çalışma alanında uygula. Değişikliği, anlamlı testleri ve kalan sınırlamaları raporla.", simge: "terminal", sablon: true),
        .init(id: UUID(uuidString: "20000000-0000-0000-0000-000000000004")!, ad: "Eleştir ve düzelt", istem: "Bu taslağı doğruluk, açıklık ve eksik adımlar açısından bağımsız denetle; sorunları düzeltip son sürümü ver.", simge: "checkmark.seal", sablon: true)
    ]
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        beceriler = Self.sablonlar + (defaults.data(forKey: anahtar).flatMap { try? JSONDecoder().decode([AsistanBecerisi].self, from: $0) } ?? [])
    }
    func ekle(ad: String, istem: String) {
        let a = String(ad.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)), i = String(istem.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
        guard !a.isEmpty, !i.isEmpty else { return }
        beceriler.append(.init(id: UUID(), ad: a, istem: i, simge: "wand.and.stars", sablon: false)); kaydet()
    }
    func sil(_ beceri: AsistanBecerisi) { guard !beceri.sablon else { return }; beceriler.removeAll { $0.id == beceri.id }; kaydet() }
    private func kaydet() { if let data = try? JSONEncoder().encode(beceriler.filter { !$0.sablon }) { defaults.set(data, forKey: anahtar) } }
}
