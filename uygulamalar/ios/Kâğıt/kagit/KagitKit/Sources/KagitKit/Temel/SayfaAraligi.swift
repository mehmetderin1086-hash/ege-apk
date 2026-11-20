import Foundation

/// Kullanıcının yazdığı sayfa aralığını (1 tabanlı) 0 tabanlı sıralı indekslere çevirir.
///
/// Desteklenenler: "1-3, 5, 8-" · "-4" · "tek" · "çift" · "hepsi" / boş · "son" · "son-2"
public enum SayfaAraligi {

    public static func coz(_ metin: String, sayfaSayisi: Int) throws -> [Int] {
        guard sayfaSayisi > 0 else { throw KagitHata.bosGirdi }
        let temiz = metin.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "tr_TR"))
        if temiz.isEmpty || temiz == "hepsi" || temiz == "tümü" || temiz == "tumu" {
            return Array(0..<sayfaSayisi)
        }
        if temiz == "tek" { return stride(from: 0, to: sayfaSayisi, by: 2).map { $0 } }
        if temiz == "çift" || temiz == "cift" { return stride(from: 1, to: sayfaSayisi, by: 2).map { $0 } }

        var kume = Set<Int>()
        for parca in temiz.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " }) {
            let p = String(parca)
            guard !p.isEmpty else { continue }
            if let tire = p.firstIndex(of: "-") {
                let bas = String(p[..<tire]), son = String(p[p.index(after: tire)...])
                // "son-2" biçimi: sondan geriye
                if bas == "son" {
                    guard let n = Int(son), n >= 0, n < sayfaSayisi else { throw KagitHata.gecersizAralik(metin) }
                    kume.insert(sayfaSayisi - 1 - n)
                    continue
                }
                let a = bas.isEmpty ? 1 : try sayi(bas, metin, sayfaSayisi)
                let b = son.isEmpty ? sayfaSayisi : try sayi(son, metin, sayfaSayisi)
                guard a <= b else { throw KagitHata.gecersizAralik(metin) }
                for i in a...b { kume.insert(i - 1) }
            } else {
                kume.insert(try sayi(p, metin, sayfaSayisi) - 1)
            }
        }
        guard !kume.isEmpty else { throw KagitHata.gecersizAralik(metin) }
        return kume.sorted()
    }

    private static func sayi(_ p: String, _ metin: String, _ sayfaSayisi: Int) throws -> Int {
        if p == "son" { return sayfaSayisi }
        guard let n = Int(p), n >= 1, n <= sayfaSayisi else { throw KagitHata.gecersizAralik(metin) }
        return n
    }

    /// 0 tabanlı indeksleri kısa metne çevirir: [0,1,2,4] → "1-3, 5"
    public static func metin(_ indeksler: [Int]) -> String {
        let s = Array(Set(indeksler)).sorted()
        guard var bas = s.first else { return "" }
        var onceki = bas
        var parcalar: [String] = []
        func ekle() { parcalar.append(bas == onceki ? "\(bas + 1)" : "\(bas + 1)-\(onceki + 1)") }
        for i in s.dropFirst() {
            if i == onceki + 1 { onceki = i; continue }
            ekle(); bas = i; onceki = i
        }
        ekle()
        return parcalar.joined(separator: ", ")
    }
}
