import Foundation

/// Ağ isteği yapmadan, yalnız kullanıcının isteği ve eklerin boyutuyla seçim yapar.
/// Kaynak belgelerindeki talimatlar veya uygulamanın eklediği sistem metni puanlanmaz.
nonisolated enum DusunmeSecimi {
    enum Caba: String, CaseIterable, Sendable {
        case low, medium, high
        var ad: String {
            switch self { case .low: "Düşük"; case .medium: "Orta"; case .high: "Yüksek" }
        }
    }
    static func sec(_ metin: String, ayar: String = "auto", kip: CalismaKipi = .sohbet,
                    belgeBoyutu: Int = 0, gorsel: Bool = false, onceki: Caba? = nil) -> Caba {
        if let elle = Caba(rawValue: ayar) { return elle }
        let s = AtolyeYonlendirme.normalize(metin)
        func eslesir(_ desen: String) -> Bool { s.range(of: desen, options: .regularExpression) != nil }
        // Kısa istekler de zor olabilir. Sesli mod bu kararı düşürmez.
        if eslesir(#"\b(kanitla|ispatla|turev|integral|optimizasyon|optimize|mimari|deadlock|race condition|kok neden|hata ayikla|debug|guvenlik acigi|tehdit modeli|detayli analiz|ayrintili analiz|kapsamli|cok adimli|adim adim coz|teshis|tedavi|ilac dozu|hukuki|yatirim riski)\b"#) { return .high }
        let adimlar = s.components(separatedBy: .newlines).filter { $0.range(of: #"^\s*(\d+[.)]|[-*])\s+"#, options: .regularExpression) != nil }.count
        if s.count > 1800 || belgeBoyutu > 12000 || adimlar >= 3 { return .high }
        if eslesir(#"\b(once|ardindan|sonra|son olarak)\b"#),
           s.components(separatedBy: "sonra").count + s.components(separatedBy: "ardindan").count >= 4 { return .high }
        if eslesir(#"^(devam et|cozmeye devam et|buna test ekle|buna birim testlerini de ekle|test de ekle|bunu daha ayrintili yaz)[.!?]*$"#), let onceki { return onceki }
        // Zor sorular: test sorusu kalıbı (3+ şık), "çöz/doğru cevap" ifadeleri ve fotoğraflı sorular Opus düzeyinde düşünür.
        if testSorusuKalibi(s) { return .high }
        if gorsel { return .high }
        if belgeBoyutu > 0 { return .medium }
        if eslesir(#"^(bunu kisalt|biraz kisalt|tesekkurler|sag ol|merhaba|selam|nasilsin|beni duyuyor musun|saat kac|pilim kac|pil durumu)[.!?]*$"#) { return .low }
        if s.count < 220, eslesir(#"\b(ac|oynat|cal|ara|gonder|alarm kur|zamanlayici kur|hatirlat|kapat|hava nasil|hava durumu|kac derece)\b"#) { return .low }
        if s.count < 180, eslesir(#"(\bnedir\b|\bne demek\b|\bcevir\b|\bmesaji yaz\b|^\d+\s*[+*/−-]\s*\d+)"#) { return .low }
        if kip == .kod || kip == .arastirma || s.count > 220 { return .medium }
        return .medium
    }

    /// Metindeki "a)" … "e)" biçimli şık belirteçlerinin sayısı (büyük/küçük harf ve aksan fark etmez).
    static func sikSayisi(_ metin: String) -> Int {
        AtolyeYonlendirme.normalize(metin).components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.range(of: #"^[a-e]\)"#, options: .regularExpression) != nil }.count
    }

    /// Test sorusu kalıbı: 3+ şık ya da "çöz/doğru cevap/test sorusu" ifadeleri (yüksek çaba ve oylamalı çözüm kararı).
    static func testSorusuKalibi(_ metin: String) -> Bool {
        if sikSayisi(metin) >= 3 { return true }
        return AtolyeYonlendirme.normalize(metin).range(of: #"\b(coz|cozer misin|cozum|cozumle|dogru cevap|test sorusu|soruyu coz|problemi coz)\b"#,
                                                        options: .regularExpression) != nil
    }
}
