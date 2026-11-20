import Foundation

/// Asistan yanıtlarını okunaklı, düzgün Türkçe düz metne çevirir: ham Markdown işaretleri, `utm_` izleri,
/// yinelenen kaynak listeleri ve emojiler temizlenir; bağlantılar sonda tek satırda alan adı olarak verilir.
/// Birden çok kez uygulanması sonucu değiştirmez (idempotent).
nonisolated enum YanitBicimi {
    private static let urlDeseni = #"https?://[^\s)\]>"'<]+"#

    /// `zengin: true` = ekranda gösterilecek biçim: başlık, kalın, liste, tablo ve kod blokları KORUNUR (kod bloklarına hiç dokunulmaz);
    /// yine de bağlantı/utm/yinelenen kaynak/emoji temizlenir ve kaynaklar sonda tek satırda verilir. `false` = düz metin (sesli okuma, Siri).
    static func duzelt(_ ham: String, zengin: Bool) -> String {
        guard zengin else { return duzelt(ham) }
        let t = ham.replacingOccurrences(of: "\r\n", with: "\n")
        // Çitli kod bloklarını ayır: çift sayılı parçalar metin, tek sayılılar kod.
        let parcalar = t.components(separatedBy: "```")
        let metinParcalari = parcalar.enumerated().filter { $0.offset % 2 == 0 }.map(\.element).joined(separator: "\n")
        let alanlar = alanAdlari(utmTemizle(metinParcalari))
        var cikti = ""
        for (i, p) in parcalar.enumerated() {
            if i % 2 == 1 { cikti += "```" + p + (i < parcalar.count - 1 ? "```" : ""); continue }   // son parça kodsa çit kapanmamıştır (akış)
            cikti += zenginMetniTemizle(p)
        }
        // Kapanmamış çit (akış sırasında): kod olarak bırakıldı, kapatma eklenmez.
        var son = cikti.trimmingCharacters(in: .whitespacesAndNewlines)
        if !alanlar.isEmpty, !son.isEmpty { son += "\n\nKaynak: " + alanlar.joined(separator: ", ") }
        return son
    }

    private static func zenginMetniTemizle(_ ham: String) -> String {
        var t = utmTemizle(ham)
        var satirlar: [String] = []
        for satir in t.components(separatedBy: "\n") {
            let k = satir.trimmingCharacters(in: .whitespaces)
            if k.range(of: #"^[\[\(\*\-•\s]*(Kaynaklar?|Sources?)\b[^\n]*"#, options: [.regularExpression, .caseInsensitive]) != nil,
               k.range(of: urlDeseni, options: .regularExpression) != nil || k.range(of: #"^[\*\s]*(Kaynaklar|Sources)\s*:?\**\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            if k.range(of: #"^[\-\*•\s]*(\[[^\]]*\]\()?https?://\S+\)?\s*$"#, options: .regularExpression) != nil { continue }
            var s = satir
            s = s.replacingOccurrences(of: #"\s*\(\[[^\]\s]+\.[^\]\s]+\]\([^)]*\)\)"#, with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: urlDeseni, with: "", options: .regularExpression)
            s = emojiTemizle(s)
            if !k.hasPrefix("|") {
                s = s.replacingOccurrences(of: #"(?<=\S)[ \t]{2,}(?=\S)"#, with: " ", options: .regularExpression)
                s = s.replacingOccurrences(of: #"\s+([.,;:!?])"#, with: "$1", options: .regularExpression)
            }
            s = s.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression)
            satirlar.append(s)
        }
        t = satirlar.joined(separator: "\n")
        t = t.replacingOccurrences(of: #"\(\s*\)"#, with: "", options: .regularExpression)
        return t.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)   // yalnız metin parçasında; kod bloklarına dokunulmaz
    }

    static func duzelt(_ ham: String) -> String {
        var t = ham.replacingOccurrences(of: "\r\n", with: "\n")
        t = utmTemizle(t)
        let alanlar = alanAdlari(t)

        var satirlar: [String] = []
        for satir in t.components(separatedBy: "\n") {
            let k = satir.trimmingCharacters(in: .whitespaces)
            // Kaynak başlığı/satırı ve yalnız bağlantıdan oluşan satırlar sonda tek satırda toplanır.
            if k.range(of: #"^[\[\(\*\-•\s]*(Kaynaklar?|Sources?)\b[^\n]*"#, options: [.regularExpression, .caseInsensitive]) != nil,
               k.range(of: urlDeseni, options: .regularExpression) != nil || k.range(of: #"^[\*\s]*(Kaynaklar|Sources)\s*:?\**\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            if k.range(of: #"^[\-\*•\s]*(\[[^\]]*\]\()?https?://\S+\)?\s*$"#, options: .regularExpression) != nil { continue }
            satirlar.append(satir)
        }
        t = satirlar.joined(separator: "\n")

        // ([alan.com](url)) gibi parantezli alan adı bağlantıları kaldırılır; diğer bağlantılar yalnız etiketle kalır.
        t = t.replacingOccurrences(of: #"\s*\(\[[^\]\s]+\.[^\]\s]+\]\([^)]*\)\)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: urlDeseni, with: "", options: .regularExpression)

        // Kalın işaretleri (** __) kaldır: yanıtlar düz metin; model kural dışı kalın yazsa bile temizlenir.
        t = t.replacingOccurrences(of: #"\*\*([^*\n]+?)\*\*"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?<![A-Za-z0-9_])__([^_\n]+?)__(?![A-Za-z0-9_])"#, with: "$1", options: .regularExpression)

        // Blok Markdown: başlık, liste işareti, yatay çizgi.
        t = t.components(separatedBy: "\n").compactMap { satir -> String? in
            var s = satir
            if s.range(of: #"^\s*([-*_]\s*){3,}$"#, options: .regularExpression) != nil { return nil }
            s = s.replacingOccurrences(of: #"^\s{0,3}#{1,6}\s*"#, with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: #"^(\s*)[-*]\s+"#, with: "$1• ", options: .regularExpression)
            return s
        }.joined(separator: "\n")

        t = emojiTemizle(t)
        t = t.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?<=\S)[ \t]{2,}(?=\S)"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+([.,;:!?])"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\(\s*\)"#, with: "", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)

        if !alanlar.isEmpty, !t.isEmpty { t += "\n\nKaynak: " + alanlar.joined(separator: ", ") }
        return t
    }

    /// `?utm_source=openai`, `&utm_medium=…` gibi izleme parametrelerini siler.
    static func utmTemizle(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"[?&]utm_[A-Za-z_]+=[^&\s)\]>"']*"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(https?://[^\s?)\]>"']+)&([A-Za-z_]+=)"#, with: "$1?$2", options: .regularExpression)
        return t
    }

    /// Metindeki bağlantıların alan adları (www. olmadan), sırayla, tekrarsız, en çok 3.
    static func alanAdlari(_ s: String) -> [String] {
        var gorulen = Set<String>(), sonuc: [String] = []
        var aralik = s.startIndex..<s.endIndex
        while let r = s.range(of: urlDeseni, options: .regularExpression, range: aralik) {
            if var h = URL(string: String(s[r]))?.host?.lowercased() {
                if h.hasPrefix("www.") { h.removeFirst(4) }
                if gorulen.insert(h).inserted { sonuc.append(h) }
            }
            aralik = r.upperBound..<s.endIndex
        }
        return Array(sonuc.prefix(3))
    }

    /// Unicode'da Emoji=Yes ama metin sunumlu bilimsel/tipografik işaretler (♀ ♂ ↔ ™ ☢ ⚛ ✔ …): yanıtta anlam taşır, silinmez.
    private static let korunanIsaretler: Set<UInt32> = [0x2640, 0x2642, 0x26A7,                     // ♀ ♂ ⚧
                                                        0x2194, 0x2195, 0x2196, 0x2197, 0x2198, 0x2199, // ↔ ↕ ↖ ↗ ↘ ↙
                                                        0x21A9, 0x21AA, 0x27A1, 0x2934, 0x2935,         // ↩ ↪ ➡ ⤴ ⤵
                                                        0x2B05, 0x2B06, 0x2B07, 0x2122, 0x267E,         // ⬅ ⬆ ⬇ ™ ♾
                                                        0x2622, 0x2623, 0x2695, 0x2696, 0x2697, 0x269B, // ☢ ☣ ⚕ ⚖ ⚗ ⚛
                                                        0x2714, 0x2716]                                 // ✔ ✖

    static func emojiTemizle(_ s: String) -> String {
        var cikti = String.UnicodeScalarView()
        var onceki: Unicode.Scalar?
        for u in s.unicodeScalars {
            defer { onceki = u }
            // ZWJ dizisinin parçası (🏃‍♀️, 👨‍⚕️) emojiyle birlikte gider; yoksa geriye başıboş ♀ kalır.
            if korunanIsaretler.contains(u.value), onceki?.value != 0x200D { cikti.append(u); continue }
            if u.properties.isEmojiPresentation || u.value == 0xFE0F || u.value == 0x200D || (u.properties.isEmoji && u.value > 0x2000 && u.value != 0x2022 && u.value != 0x2019 && u.value != 0x00B0) { continue }
            cikti.append(u)
        }
        return String(cikti)
    }

    /// Balon için satır içi Markdown (kalın, italik, kod) uygular; satır sonları korunur.
    static func goster(_ metin: String) -> AttributedString {
        let secenek = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: duzelt(metin), options: secenek)) ?? AttributedString(duzelt(metin))
    }
}
