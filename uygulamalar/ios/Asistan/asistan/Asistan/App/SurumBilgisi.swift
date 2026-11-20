import Foundation

/// Telefondaki derlemenin kimliği: pazarlama sürümü, derleme numarası (telefona-kur.sh'ta YYYYMMDDHHMM),
/// git kısa hash'i, derleme anında değişmiş dosya sayısı ve yapılandırma (Debug/Release).
/// Değerleri `araclar/surum-damgala.sh` derleme sonrası Info.plist'e yazar; eksik anahtar "bilinmiyor" olur.
nonisolated struct SurumBilgisi: Sendable, Equatable {
    static let bilinmiyor = "bilinmiyor"

    let pazarlama: String
    let derleme: String
    let git: String
    let degisik: Int
    let tur: String

    /// Bu ikilinin derleyici gözüyle türü; plist'teki AsistanDerlemeTuru ile çapraz denetlenir.
    static var derleyiciTuru: String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
    }

    /// Info.plist sözlüğünden okur. Sayılar plist'te dize ya da sayı olarak gelebilir.
    static func oku(_ s: [String: Any], derleyiciTuru: String = SurumBilgisi.derleyiciTuru) -> SurumBilgisi {
        func metin(_ anahtar: String) -> String {
            if let d = s[anahtar] as? String {
                let t = d.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? bilinmiyor : t
            }
            if let n = s[anahtar] as? NSNumber { return n.stringValue }
            return bilinmiyor
        }
        let degisik: Int
        if let n = s["AsistanDegisikDosya"] as? Int { degisik = max(0, n) }
        else if let d = s["AsistanDegisikDosya"] as? String, let n = Int(d.trimmingCharacters(in: .whitespaces)) { degisik = max(0, n) }
        else { degisik = 0 }
        // Plist türü derleme ayarından gelir; ikilinin kendisi farklı derlenmişse ikisi de gösterilir.
        let plistTuru = metin("AsistanDerlemeTuru")
        let tur: String
        if plistTuru == bilinmiyor || plistTuru == derleyiciTuru { tur = derleyiciTuru }
        else { tur = "\(derleyiciTuru) (plist: \(plistTuru))" }
        return SurumBilgisi(pazarlama: metin("CFBundleShortVersionString"), derleme: metin("CFBundleVersion"),
                            git: metin("AsistanGitHash"), degisik: degisik, tur: tur)
    }

    static let simdiki = oku(Bundle.main.infoDictionary ?? [:])

    /// "0.21.0 (202610201530)"
    var kisa: String { "\(pazarlama) (\(derleme))" }

    /// "git 7f2747a +3 · Release" — değişmiş dosya yoksa "+" yazılmaz.
    var derlemeOzeti: String { "git \(git)\(degisik > 0 ? " +\(degisik)" : "") · \(tur)" }

    /// "0.21.0 (202610201530) · git 7f2747a +3 · Release"
    var uzun: String { "\(kisa) · \(derlemeOzeti)" }

    /// Derleme numarası 12 haneli YYYYMMDDHHMM ise yerel saatle derleme anı; değilse (ör. "38") nil.
    var derlemeTarihi: Date? {
        let haneler = Array(derleme.utf8)
        guard haneler.count == 12, haneler.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        func sayi(_ a: Int, _ b: Int) -> Int { haneler[a..<b].reduce(0) { $0 * 10 + Int($1 - 48) } }
        var bilesen = DateComponents()
        bilesen.year = sayi(0, 4); bilesen.month = sayi(4, 6); bilesen.day = sayi(6, 8)
        bilesen.hour = sayi(8, 10); bilesen.minute = sayi(10, 12)
        let takvim = Calendar(identifier: .gregorian)
        guard let tarih = takvim.date(from: bilesen) else { return nil }
        // Takvim taşan değerleri (13. ay, 32. gün) ileri kaydırır; geri okunan bileşenler aynı değilse geçersiz.
        let geri = takvim.dateComponents([.year, .month, .day, .hour, .minute], from: tarih)
        guard geri.year == bilesen.year, geri.month == bilesen.month, geri.day == bilesen.day,
              geri.hour == bilesen.hour, geri.minute == bilesen.minute else { return nil }
        return tarih
    }
}
