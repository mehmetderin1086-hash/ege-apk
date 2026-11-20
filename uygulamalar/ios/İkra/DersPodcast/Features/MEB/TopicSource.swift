import Foundation

/// Konu videosuna kaynak olacak metnin sınırları. Kitaptan metin çıkaran kod (MEB okuyucu) Oku ile ortak olduğundan burada durur.
nonisolated enum TopicSource {
    /// Ders saati uzunluğundaki videolar (bölümlü üretim, 16 Eki 2026) daha uzun kaynak kullanır; kısa videolar ve yedek sunucu
    /// (eski sürüm, 60 bin sınırı) `quick` kadarını alır.
    static let minimum = 200, maximum = 150_000, quick = 60_000
    /// Kısa video isteği için kaynak (yedek sunucunun sınırı).
    static func quickPart(_ text: String) -> String { String(decoding: text.utf16.prefix(quick), as: UTF16.self) }
    /// Kaynak metni sunucunun sınırına indirir; fazlası baştan sona eşit dağıtılarak değil, sondan kesilerek atılır (konunun başı korunur).
    static func prepared(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\r", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Sunucu sınırı UTF-16 birimiyle sayar (emoji ve matematik harfleri iki birimdir).
        return String(decoding: cleaned.utf16.prefix(maximum), as: UTF16.self)
    }
    static func problem(_ text: String, topic: String) -> String? {
        if topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Konunun adını yaz." }
        if prepared(text).count < minimum { return "Kaynak çok kısa. Ders kitabının ya da notunun ilgili sayfalarını ekle (en az birkaç paragraf)." }
        return nil
    }
}
