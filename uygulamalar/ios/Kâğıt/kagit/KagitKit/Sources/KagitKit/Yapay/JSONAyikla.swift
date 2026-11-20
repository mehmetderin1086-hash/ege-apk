import Foundation

/// Model çıktısındaki JSON'u sağlam biçimde ayıklar: ``` çitlerini ve baştaki/sondaki açıklamayı atar.
public enum JSONAyikla {

    /// Metindeki ilk dengeli JSON nesnesi/dizisini döndürür.
    public static func metin(_ ham: String) -> String? {
        var s = ham
        if let bas = s.range(of: "```") {
            var icerik = String(s[bas.upperBound...])
            // "```json" satır başı etiketi
            if let nl = icerik.firstIndex(of: "\n"), !icerik[..<nl].contains(where: { "{[".contains($0) }) {
                icerik = String(icerik[icerik.index(after: nl)...])
            }
            if let son = icerik.range(of: "```") { icerik = String(icerik[..<son.lowerBound]) }
            s = icerik
        }
        let ks = Array(s)
        guard let basIdx = ks.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
        var derinlik = 0
        var dizgide = false
        var kacis = false
        var i = basIdx
        while i < ks.count {
            let c = ks[i]
            if dizgide {
                if kacis { kacis = false } else if c == "\\" { kacis = true } else if c == "\"" { dizgide = false }
            } else if c == "\"" {
                dizgide = true
            } else if c == "{" || c == "[" {
                derinlik += 1
            } else if c == "}" || c == "]" {
                derinlik -= 1
                if derinlik == 0 { return temizle(String(ks[basIdx...i])) }
            }
            i += 1
        }
        return nil
    }

    /// Sondaki virgülleri (`,}` / `,]`) giderir.
    private static func temizle(_ s: String) -> String {
        s.replacingOccurrences(of: #",\s*([}\]])"#, with: "$1", options: .regularExpression)
    }

    public static func coz<T: Decodable>(_ tur: T.Type, _ ham: String) throws -> T {
        guard let j = metin(ham), let veri = j.data(using: .utf8) else {
            throw KagitHata.yapayZeka("Yanıtta geçerli JSON bulunamadı")
        }
        do {
            return try JSONDecoder().decode(T.self, from: veri)
        } catch {
            throw KagitHata.yapayZeka("JSON beklenen biçimde değil: \(error.localizedDescription)")
        }
    }
}
