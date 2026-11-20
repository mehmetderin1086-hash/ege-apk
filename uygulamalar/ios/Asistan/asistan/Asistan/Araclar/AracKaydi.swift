import Foundation
import FoundationModels

/// Beyne verilen araçların tek listesi.
enum AracKaydi {
    @MainActor
    static func hepsi(depo: HafizaDeposu, onay: OnayKapisi) -> [any Tool] {
        [
            GelenKutusuAraci(),
            ArsivAraci(),
            OfisAraci(),
            PdfAraci(onay: onay),
            ExcelAraci(),
            IndirmeAraci(onay: onay),
            DosyaAraci(),
            UygulamaIslemAraci(onay: onay),
            SaatAraci(),
            TakvimAraci(onay: onay, kimlikGoster: true),
            HatirlaticiAraci(onay: onay),
            KisilerAraci(),
            IletisimAraci(onay: onay),
            HaritaAraci(),
            HavaAraci(),
            UcretsizServisAraci(),
            YasamServisleriAraci(),
            KisayolAraci(onay: onay),
            UygulamaAcAraci(onay: onay),
            HafizaAraci(depo: depo, onay: onay),
            ZamanlayiciAraci(),
            MuzikAraci(),
            CihazAraci(onay: onay),
            EvAraci(onay: onay),
            BeceriAraci(onay: onay),
            CalismaAlaniAraci(onay: onay),
            WebSayfaAraci(),
            PlanAraci(),
            GecmisAramaAraci(depo: depo),
            AltAjanAraci(),
            McpAraci(onay: onay),
            ProjeAraci(),
            TuvalAraci(),
            TarayiciAraci(onay: onay),
            VeriKaziAraci(),
            FotografAraci(onay: onay),
        ] + McpKaydi.ortak.dinamikAraclar(onay: onay)
    }

    static var adlar: [String] {
        ["gelenKutusu", "arsivler", "ofisBelgesiOlustur", "pdfIslem", "excelOlustur", "indirmeler", "dosyalar", "uygulamaIslemi", "suankiSaat", "takvim", "hatirlatici", "kisiler", "iletisim", "harita", "havaDurumu", "ucretsizServis", "yasamServisleri", "kisayolCalistir", "uygulamaAc", "hafiza", "zamanlayici", "muzik", "cihaz", "ev", "beceriler", "gecmisAra", "altAjanlar", "mcp", "calismaAlani", "webSayfaOku", "plan", "proje", "tuval", "tarayici", "veriKazi", "fotograflar"]
    }
}

/// Araçların ortak yardımcıları.
nonisolated enum AracYardim {
    nonisolated(unsafe) static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()
    nonisolated(unsafe) static let isoSaniyesiz: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
        f.timeZone = .current
        return f
    }()

    /// "2026-10-15T18:30" ya da "2026-10-15T18:30:00+03:00" ya da "2026-10-15" biçimlerini çözer.
    static func tarih(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if let d = iso.date(from: t) { return d }
        if let d = isoSaniyesiz.date(from: t) { return d }
        if let d = isoSaniyesiz.date(from: t + ":00") { return d }
        let g = DateFormatter(); g.locale = Locale(identifier: "en_US_POSIX"); g.timeZone = .current
        for biçim in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            g.dateFormat = biçim
            if let d = g.date(from: t) { return d }
        }
        return nil
    }

    static func kisa(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "d MMM EEE HH:mm"
        return f.string(from: d)
    }

    /// Saatsiz gün ("2026-10-21") mi? `tarih` bunu gece 00:00'a çözer; çağıran tüm gün / varsayılan saat seçmeli.
    static func yalnizGun(_ s: String?) -> Bool {
        s?.trimmingCharacters(in: .whitespaces).range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    /// Hatırlatma zamanı: saatsiz gün verilirse gece yarısı yerine o günün `saat`ine (varsayılan 09:00) kurulur.
    static func hatirlatmaZamani(_ s: String, saat: Int = 9) -> Date? {
        guard let d = tarih(s) else { return nil }
        guard yalnizGun(s) else { return d }
        return Calendar.current.date(bySettingHour: saat, minute: 0, second: 0, of: d) ?? d
    }

    static func kisaGun(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "d MMM EEE"
        return f.string(from: d)
    }

    /// Toplu eklemede atlanan satırların ve sınır üstü kesilen maddelerin raporu (boşsa ek metin yok).
    static func topluOzet(atlanan: [String], kesilen: Int, sinir: Int) -> String {
        var s = ""
        if !atlanan.isEmpty {
            s += " Eklenemeyen \(atlanan.count) satır (tarih/biçim anlaşılmadı): " + atlanan.prefix(10).joined(separator: "; ") + (atlanan.count > 10 ? "…" : "") + "."
        }
        if kesilen > 0 { s += " Sınır \(sinir): \(kesilen) madde işlenmedi; kalanları ayrı çağrıda gönder." }
        return s
    }
}
