import Foundation

/// Türkçe'ye duyarlı metin yardımcıları (İ/ı dönüşümü, bulanık eşleştirme).
public enum TurkceMetin {
    public static let yerel = Locale(identifier: "tr_TR")

    public static func kucuk(_ s: String) -> String { s.lowercased(with: yerel) }
    public static func buyuk(_ s: String) -> String { s.uppercased(with: yerel) }

    /// Karşılaştırma anahtarı: küçük harf, Türkçe harfler ASCII'ye, noktalama ve fazla boşluk yok.
    public static func anahtar(_ s: String) -> String {
        var k = kucuk(s)
        for (a, b) in [("ç", "c"), ("ğ", "g"), ("ı", "i"), ("ö", "o"), ("ş", "s"), ("ü", "u"), ("â", "a"), ("î", "i"), ("û", "u")] {
            k = k.replacingOccurrences(of: a, with: b)
        }
        k = k.folding(options: [.diacriticInsensitive], locale: yerel)
        let izinli = k.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(izinli).split(separator: " ").joined(separator: " ")
    }

    /// Levenshtein uzaklığına dayalı benzerlik (0...1).
    public static func benzerlik(_ a: String, _ b: String) -> Double {
        let x = Array(anahtar(a)), y = Array(anahtar(b))
        if x.isEmpty && y.isEmpty { return 1 }
        if x.isEmpty || y.isEmpty { return 0 }
        var onceki = Array(0...y.count)
        var simdiki = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            simdiki[0] = i
            for j in 1...y.count {
                let maliyet = x[i - 1] == y[j - 1] ? 0 : 1
                simdiki[j] = min(onceki[j] + 1, simdiki[j - 1] + 1, onceki[j - 1] + maliyet)
            }
            swap(&onceki, &simdiki)
        }
        return 1 - Double(onceki[y.count]) / Double(max(x.count, y.count))
    }

    /// Metin içinde listedeki en iyi eşleşen adı bulur (ör. OCR satırı ↔ sınıf listesi).
    /// Ad soyadın sırası değişmiş olabilir; sözcük kümesi de denenir.
    public static func enIyiEslesme(_ metin: String, _ adaylar: [String], esik: Double = 0.72) -> (indeks: Int, puan: Double)? {
        let m = anahtar(metin)
        guard !m.isEmpty else { return nil }
        var enIyi: (Int, Double)?
        for (i, aday) in adaylar.enumerated() {
            let a = anahtar(aday)
            guard !a.isEmpty else { continue }
            var puan = benzerlik(m, a)
            if m.contains(a) { puan = max(puan, 0.98) }
            // Sözcük bazlı: adayın her sözcüğü metinde benzer bir sözcükle karşılanıyor mu
            let ms = m.split(separator: " ").map(String.init)
            let asz = a.split(separator: " ").map(String.init)
            if !asz.isEmpty, !ms.isEmpty {
                let ort = asz.map { s in ms.map { benzerlik($0, s) }.max() ?? 0 }.reduce(0, +) / Double(asz.count)
                puan = max(puan, ort * 0.97)
            }
            if puan > (enIyi?.1 ?? 0) { enIyi = (i, puan) }
        }
        guard let enIyi, enIyi.1 >= esik else { return nil }
        return (enIyi.0, enIyi.1)
    }

    /// Dosya adı için güvenli metin (Türkçe harfler korunur, yasak karakterler atılır).
    public static func dosyaAdi(_ s: String, varsayilan: String = "Belge") -> String {
        let yasak = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let temiz = s.components(separatedBy: yasak).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let kisa = String(temiz.prefix(120))
        return kisa.isEmpty ? varsayilan : kisa
    }

    /// Vision OCR'ın Türkçe büyük harf hatası: sözcük başındaki "I" çoğu zaman "İ" olmalı.
    /// Yalnız bilinen sık sözcükler düzeltilir; körlemesine değiştirme yapılmaz.
    public static func ocrDuzelt(_ s: String) -> String {
        var sonuc = s
        let sozcukler = ["Imza": "İmza", "Isim": "İsim", "Il ": "İl ", "Ilce": "İlçe", "Ilçe": "İlçe",
                         "Istanbul": "İstanbul", "Izmir": "İzmir", "Içindekiler": "İçindekiler",
                         "Ihtiyaç": "İhtiyaç", "Iyi": "İyi", "Ise": "İse", "Ile": "İle", "Ikinci": "İkinci",
                         "Ilk": "İlk", "Inceleme": "İnceleme", "Insan": "İnsan", "Işlem": "İşlem",
                         "Iş": "İş", "Itibaren": "İtibaren", "Içinde": "İçinde"]
        for (yanlis, dogru) in sozcukler {
            sonuc = sonuc.replacingOccurrences(of: "\\b\(NSRegularExpression.escapedPattern(for: yanlis))",
                                               with: dogru, options: .regularExpression)
        }
        return sonuc
    }
}
