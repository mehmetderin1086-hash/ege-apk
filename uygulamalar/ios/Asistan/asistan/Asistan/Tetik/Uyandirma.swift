import Foundation

nonisolated enum Uyandirma {
    /// Yalnız sözün başındaki tam uyandırma ifadesini kabul eder.
    /// nil: uyanma yok; boş metin: yalnız çağrı; dolu: aynı nefeste söylenen komut.
    static func komut(_ metin: String) -> String? {
        // Türkçe dikte bazen uyandırma adını İngilizce yazımla döndürüyor.
        // İfade yine yalnız cümlenin başında ve bir sözcük sınırında kabul edilir;
        // böylece ortam konuşması veya "asistanlık" yanlışlıkla komuta dönüşmez.
        // Apple'ın Türkçe diktesi ilk "H" sesini bazen düşürüp "Ey Asistan"
        // yazabiliyor. İki kelime arasındaki sınırı zorunlu tutuyoruz; böylece
        // "heyasistan" veya "asistanlık" gibi sıradan konuşmalar uyandırmaz.
        // `caseInsensitive`, Türkçe büyük İ harfini ASCII i ile her SDK'da
        // eşitlemiyor; bu nedenle asistan sözcüğünün o karakterini açıkça da
        // kabul ediyoruz.
        let pattern = #"^\s*(?:hey|ey)[\s,!.:;]+(?:as[iıİI]stan|assistant)(?:[\s,!.:;]+|$)"#
        guard let range = metin.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(metin[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Mikrofon verisi ile komut gönderme arasındaki kapı. Bekleme konuşmaları komut değildir.
nonisolated struct UyandirmaAkisi {
    enum Durum { case kapali, bekliyor, komut, isleniyor }
    private(set) var durum: Durum = .kapali
    private(set) var uyandirmaIleAcildi = false
    var etkin: Bool { durum == .komut || durum == .isleniyor }
    mutating func bekle() { durum = .bekliyor; uyandirmaIleAcildi = false }
    mutating func elleDinle() { durum = .komut; uyandirmaIleAcildi = false }
    mutating func kapat() { durum = .kapali; uyandirmaIleAcildi = false }
    @discardableResult mutating func araSonuc(_ metin: String) -> Bool {
        guard durum == .bekliyor, Uyandirma.komut(metin) != nil else { return false }
        durum = .komut; uyandirmaIleAcildi = true
        return true
    }
    mutating func kesinSonuc(_ metin: String) -> String? {
        araSonuc(metin)
        guard durum == .komut else { return nil }
        let komut = (Uyandirma.komut(metin) ?? metin).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !komut.isEmpty else { return nil }
        durum = .isleniyor // Yinelenen/gecikmiş tanıma sonucu ikinci komut gönderemez.
        return komut
    }
    @discardableResult mutating func yanitBitti(surekli: Bool) -> Bool {
        if durum == .isleniyor, !uyandirmaIleAcildi, surekli {
            durum = .komut
            return true
        }
        kapat()
        return false
    }
}
