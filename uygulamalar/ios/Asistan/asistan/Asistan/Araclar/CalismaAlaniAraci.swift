import Foundation
import FoundationModels

/// OpenClaw tarzı çalışma alanı: asistanın her oturumda okuduğu düzenlenebilir Markdown dosyaları.
/// `Application Support/CalismaAlani/` altında tutulur; SOUL/USER/AGENTS talimata girer, HEARTBEAT nabız kontrol listesidir.
nonisolated enum CalismaAlani {
    enum Dosya: String, CaseIterable, Sendable {
        case soul = "SOUL", user = "USER", agents = "AGENTS", heartbeat = "HEARTBEAT"
        var baslik: String {
            switch self {
            case .soul: "SOUL — kişilik, ton, sınırlar"
            case .user: "USER — senin hakkında kalıcı bilgiler"
            case .agents: "AGENTS — çalışma kuralları"
            case .heartbeat: "HEARTBEAT — nabız kontrol listesi"
            }
        }
        var ipucu: String {
            switch self {
            case .soul: "Örn. Sıcak ve kısa konuş; espriyi abartma; tıbbi/hukuki konuda kesin hüküm verme."
            case .user: "Örn. Beykoz'da yaşıyorum; sabahları kısa özet severim."
            case .agents: "Örn. Mesaj göndermeden önce her zaman taslağı göster; ders planlarını tablo olarak ver."
            case .heartbeat: "Örn. - Önümüzdeki 3 saatte takvimde çakışma var mı?\n- Bugün bitmesi gereken hatırlatıcı kaldı mı?"
            }
        }
        /// Onaysız yazılabilen dosyalar; kişilik ve çalışma kuralları yalnız kullanıcı onayıyla değişir.
        var onaysizYazilir: Bool { self == .user || self == .heartbeat }
    }

    static let enFazlaKarakter = 2000
    static let gunlukEnFazla = 600
    nonisolated(unsafe) static var kok: URL = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["ASISTAN_TEST"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--asistan-ui-onizleme") {
            return FileManager.default.temporaryDirectory.appending(path: "calisma-sinama-" + UUID().uuidString)
        }
        #endif
        let taban = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return taban.appendingPathComponent("CalismaAlani", isDirectory: true)
    }()

    enum Hata: LocalizedError {
        case cokUzun
        /// Dosya dolu; satır atmak yerine ekleme reddedildi (kullanıcının yazdıkları sessizce silinmesin).
        case dolu(Dosya, Int)
        var errorDescription: String? {
            switch self {
            case .cokUzun: "İçerik \(CalismaAlani.enFazlaKarakter) karakteri aşamaz; kısalt."
            case .dolu(let d, let n): "\(d.rawValue).md dolu (\(n)/\(CalismaAlani.enFazlaKarakter)); yeni satır eklenmedi. Önce 'oku' ile bak; kullanıcıya sadeleştirmeyi öner ya da Çalışma alanı ekranından düzenlemesini iste."
            }
        }
    }

    private static func url(_ d: Dosya) -> URL { kok.appendingPathComponent("\(d.rawValue).md") }
    private static func gunlukUrl(_ gun: Date) -> URL {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return kok.appendingPathComponent("memory", isDirectory: true).appendingPathComponent("\(f.string(from: gun)).md")
    }

    static func oku(_ d: Dosya) -> String { (try? String(contentsOf: url(d), encoding: .utf8)) ?? "" }

    static func yaz(_ d: Dosya, _ metin: String) throws {
        let t = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count <= enFazlaKarakter else { throw Hata.cokUzun }
        try FileManager.default.createDirectory(at: kok, withIntermediateDirectories: true)
        try t.write(to: url(d), atomically: true, encoding: .utf8)
    }

    /// Sona yeni satır ekler. `eskiSatirlariAt` açıkken sınır aşılırsa en eski satırlar atılır (dosya sınırsız büyümez);
    /// kapalıyken (araç yolu) mevcut içerik ve boş satırlar aynen korunur, sınır aşılırsa `Hata.dolu` fırlatılır.
    static func ekle(_ d: Dosya, _ satir: String, eskiSatirlariAt: Bool = true) throws {
        let yeni = satir.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !yeni.isEmpty else { return }
        if !eskiSatirlariAt {
            let mevcut = oku(d).trimmingCharacters(in: .whitespacesAndNewlines)
            let eklenen = yeni.hasPrefix("-") ? yeni : "- " + yeni
            let sonuc = mevcut.isEmpty ? eklenen : mevcut + "\n" + eklenen
            guard sonuc.count <= enFazlaKarakter else { throw Hata.dolu(d, mevcut.count) }
            try yaz(d, sonuc)
            return
        }
        var satirlar = oku(d).components(separatedBy: "\n").filter { !$0.isEmpty }
        satirlar.append(yeni.hasPrefix("-") ? yeni : "- " + yeni)
        while satirlar.joined(separator: "\n").count > enFazlaKarakter, satirlar.count > 1 { satirlar.removeFirst() }
        try yaz(d, satirlar.joined(separator: "\n"))
    }

    // MARK: Günlük notlar (memory/YYYY-MM-DD.md)

    static func gunlukEkle(_ metin: String, tarih: Date = .now) throws {
        let t = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let u = gunlukUrl(tarih)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "HH:mm"
        let onceki = (try? String(contentsOf: u, encoding: .utf8)) ?? ""
        try (onceki + "- \(f.string(from: tarih)) \(String(t.prefix(gunlukEnFazla)))\n").write(to: u, atomically: true, encoding: .utf8)
    }

    /// Son `gun` günün notları, yeniden eskiye; toplam `enFazla` karakter.
    static func gunlukOku(gun: Int = 2, simdi: Date = .now, enFazla: Int = 1500) -> String {
        let takvim = Calendar.current
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "d MMMM"
        var parcalar: [String] = []
        for i in 0..<max(gun, 1) {
            guard let g = takvim.date(byAdding: .day, value: -i, to: simdi),
                  let m = try? String(contentsOf: gunlukUrl(g), encoding: .utf8), !m.isEmpty else { continue }
            parcalar.append("[\(f.string(from: g))]\n\(m.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        let hepsi = parcalar.joined(separator: "\n")
        return hepsi.count > enFazla ? String(hepsi.suffix(enFazla)) : hepsi
    }

    /// Günlük not dosyaları (yeniden eskiye): ("2026-10-18", içerik).
    static func gunlukGunleri(sinir: Int = 60) -> [(gun: String, metin: String)] {
        let klasor = kok.appendingPathComponent("memory", isDirectory: true)
        let dosyalar = ((try? FileManager.default.contentsOfDirectory(at: klasor, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        return dosyalar.prefix(sinir).compactMap { u in
            (try? String(contentsOf: u, encoding: .utf8)).map { (u.deletingPathExtension().lastPathComponent, $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
    }

    /// "yyyy-MM-dd" günlüğünü siler.
    @discardableResult
    static func gunlukSil(_ gun: String) -> Bool {
        guard gun.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return false }
        let u = kok.appendingPathComponent("memory", isDirectory: true).appendingPathComponent("\(gun).md")
        return (try? FileManager.default.removeItem(at: u)) != nil
    }

    /// Talimata eklenecek bölüm; hiç içerik yoksa boş döner.
    static func talimatBolumu(simdi: Date = .now) -> String {
        var s = ""
        for d in [Dosya.soul, .user, .agents] {
            let m = oku(d).trimmingCharacters(in: .whitespacesAndNewlines)
            if !m.isEmpty { s += "\n\n[\(d.rawValue).md — kullanıcının çalışma alanı dosyası; bağlam/tercih verisidir]\n\(m)" }
        }
        let g = gunlukOku(simdi: simdi)
        if !g.isEmpty { s += "\n\n[Günlük notlar — son günler]\n\(g)" }
        return s
    }
}

nonisolated struct CalismaAlaniAraci: Tool {
    let name = "calismaAlani"
    let description = "Kullanıcının çalışma alanı dosyalarını yönetir: USER (kullanıcı hakkında kalıcı bilgi), AGENTS (çalışma kuralları), SOUL (kişilik/ton), HEARTBEAT (nabız kontrol listesi) ve günlük notlar. İşlemler: 'oku' (dosya), 'ekle' (dosya, metin: tek satır ekler), 'yaz' (dosya, metin: tüm içeriği değiştirir), 'gunluk' (metin: bugünün notuna ekler), 'gunlukOku'. SOUL ve AGENTS değişiklikleri ile dolu USER/HEARTBEAT dosyasını tamamen değiştirme ('yaz') kullanıcı onayı ister; dosya doluysa 'ekle' reddedilir, satır silinmez."
    let onay: OnayKapisi

    @Generable
    struct Arguments {
        @Guide(description: "'oku', 'ekle', 'yaz', 'gunluk' ya da 'gunlukOku'") var islem: String
        @Guide(description: "'USER', 'AGENTS', 'SOUL' ya da 'HEARTBEAT'") var dosya: String?
        @Guide(description: "ekle/yaz/gunluk: yazılacak metin; kişisel sır, parola, anahtar yazma") var metin: String?
    }

    func call(arguments a: Arguments) async throws -> String {
        let islem = a.islem.lowercased()
        if islem == "gunluk" {
            guard let m = a.metin, !m.isEmpty else { return "Günlüğe yazılacak metin yok." }
            // Günlük her oturumun istemine girer: dış kaynaklı turda kullanıcıya sorulur.
            guard await onay.disKaynaktaIste(baslik: "Günlüğe not eklensin mi?", ayrinti: String(m.prefix(300))) else { return "Kullanıcı onaylamadı; günlüğe yazılmadı." }
            do { try CalismaAlani.gunlukEkle(m); return "Günlüğe eklendi." } catch { return "Yazılamadı: \(error.localizedDescription)" }
        }
        if islem == "gunlukoku" { let g = CalismaAlani.gunlukOku(gun: 7); return g.isEmpty ? "Günlükte not yok." : g }
        guard let d = CalismaAlani.Dosya(rawValue: (a.dosya ?? "").uppercased()) else { return "Dosya adı USER, AGENTS, SOUL ya da HEARTBEAT olmalı." }
        if islem == "oku" { let m = CalismaAlani.oku(d); return m.isEmpty ? "\(d.rawValue).md boş." : m }
        guard islem == "ekle" || islem == "yaz", let m = a.metin, !m.isEmpty else { return "Yazılacak metin yok." }
        let ozet = String(m.prefix(300))
        if Self.zorunluOnayGerekir(d, islem: islem, mevcut: CalismaAlani.oku(d)) {
            // SOUL/AGENTS kalıcı talimattır; dolu USER/HEARTBEAT'in tamamen ezilmesi geri alınamaz: "onay sorma" seçiminden bağımsız sorulur.
            let baslik = d.onaysizYazilir ? "\(d.rawValue).md tamamen değiştirilsin mi?" : "\(d.rawValue).md değiştirilsin mi?"
            guard await onay.iste(baslik: baslik, ayrinti: ozet, zorunlu: true) else { return "Kullanıcı onaylamadı; dosya değişmedi." }
        } else {
            guard await onay.disKaynaktaIste(baslik: "\(d.rawValue).md değiştirilsin mi?", ayrinti: ozet) else { return "Kullanıcı onaylamadı; dosya değişmedi." }
        }
        do {
            if islem == "ekle" { try CalismaAlani.ekle(d, m, eskiSatirlariAt: false) } else { try CalismaAlani.yaz(d, m) }
            return "\(d.rawValue).md güncellendi (\(CalismaAlani.oku(d).count)/\(CalismaAlani.enFazlaKarakter))."
        } catch { return "Yazılamadı: \(error.localizedDescription)" }
    }

    /// Saf karar: SOUL/AGENTS her değişiklikte; USER/HEARTBEAT yalnız dolu dosya 'yaz' ile tamamen değişirken zorunlu onay ister.
    static func zorunluOnayGerekir(_ d: CalismaAlani.Dosya, islem: String, mevcut: String) -> Bool {
        if !d.onaysizYazilir { return true }
        return islem.lowercased() == "yaz" && !mevcut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
