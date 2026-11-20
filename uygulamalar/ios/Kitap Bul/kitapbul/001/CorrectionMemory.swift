import Foundation

/// Öğrenen düzeltme belleği: kullanıcı bir OCR hatasını elle düzeltince aynı hatalı
/// okuma bir daha aynı şekilde kaydedilmez. Düzeltmeler diskte saklanır.
///
/// Örnek: OCR "Yüzbasının Kızı" okudu, kullanıcı "Yüzbaşının Kızı" yaptı →
/// sonraki taramalarda aynı hatalı metin otomatik düzeltilir.
enum CorrectionMemory {
    private static var corrections: [String: String] = load()
    private static let maxEntries = 500

    private static var url: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("OCRDuzeltmeleri.json")
    }

    /// OCR çıktısı ile kullanıcının yazdığı doğru metni eşleştirir.
    /// Yalnızca anlamlı ve birbirine yakın düzeltmeler öğrenilir.
    static func learn(ocrText: String, correctedText: String) {
        let ocr = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        let corrected = correctedText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard ocr.count >= 4, corrected.count >= 4, ocr != corrected else { return }
        // Tamamen farklı metinler (kullanıcı baştan yazmış) öğrenilmez. Sayısı değişen
        // düzeltme de ("Türkçe 5" → "Türkçe 6") OCR hatası değil başka kitaptır; öğrenilirse
        // doğru okunan her "Türkçe 5" sessizce "Türkçe 6"ya çevrilir. Rakam-harf karışıklığı
        // ("Kar1nca" → "Karınca") ise bir tarafta rakam olmadığından öğrenilmeye devam eder.
        let ocrDigits = ocr.filter(\.isNumber), correctedDigits = corrected.filter(\.isNumber)
        guard CatalogMatcher.isSimilar(ocr, corrected),
              ocrDigits.isEmpty || correctedDigits.isEmpty || ocrDigits == correctedDigits else { return }

        corrections[key(ocr)] = corrected
        if corrections.count > maxEntries {
            corrections.removeValue(forKey: corrections.keys.first ?? "")
        }
        save()
    }

    /// Bilinen bir hatalı okuma ise düzeltilmiş hâlini verir.
    static func correct(_ text: String) -> String {
        corrections[key(text)] ?? text
    }

    static var count: Int { corrections.count }

    /// Gemini istemine eklenecek "bu okulda şöyle yazılır" örnekleri: en son öğrenilen
    /// 12 düzeltme. OCR'ın tekrar tekrar yaptığı hatalar modele örnek olarak gider.
    static func promptExamples(limit: Int = 12) -> String {
        let pairs = corrections.suffix(limit).map { "\"\($0.key)\" → \"\($0.value)\"" }
        guard !pairs.isEmpty else { return "" }
        return "\n- Bu kütüphanede daha önce elle düzeltilmiş okumalar (aynı hataları tekrarlama): " + pairs.joined(separator: "; ")
    }

    static func reset() {
        corrections = [:]
        save()
    }

    private static func key(_ text: String) -> String {
        CatalogMatcher.normalize(text)
    }

    private static func save() {
        guard let url,
              let data = try? JSONEncoder().encode(corrections) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func load() -> [String: String] {
        guard let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("OCRDuzeltmeleri.json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded
    }
}
