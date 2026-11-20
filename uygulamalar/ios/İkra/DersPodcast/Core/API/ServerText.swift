import Foundation

/// Sunucu (zod/JS `length`) uzunlukları UTF-16 birimiyle ölçer; Swift `Character` sayısı emoji ve ayrışık (NFD)
/// harflerde daha küçük çıkar. Metin birleşik (NFC) biçime getirilir ve karakter bölünmeden kırpılır.
nonisolated enum ServerText {
    static func prefix(_ text: String, _ limit: Int) -> String {
        let text = text.precomposedStringWithCanonicalMapping
        guard text.utf16.count > limit else { return text }
        guard limit > 0 else { return "" }
        var end = text.startIndex
        var used = 0
        for index in text.indices {
            let width = text[index].utf16.count
            if used + width > limit { break }
            used += width
            end = text.index(after: index)
        }
        return String(text[..<end])
    }
}
