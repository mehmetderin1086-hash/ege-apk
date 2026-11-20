import Foundation

/// Çalış ekranlarındaki listelerde arama (bölüm seçici, yanlış defteri, Cornell notları, kavram ve formüller).
/// Katlama kütüphane aramasıyla aynıdır: büyük/küçük harf, aksan ve ı/i farkı yok sayılır.
nonisolated enum StudySearch {
    /// Boş sorgu her şeyi eşler; sorgudaki her sözcük alanlardan birinde geçmelidir.
    static func matches(_ fields: [String], query: String) -> Bool {
        let tokens = LibrarySearch.tokens(query)
        guard !tokens.isEmpty else { return true }
        let folded = fields.map(LibrarySearch.fold)
        return tokens.allSatisfy { token in folded.contains { $0.contains(token) } }
    }

    /// Uzun listeler için: alanların katlanmış hâli liste kurulurken bir kez hesaplanır, her tuş vuruşunda değil.
    static func key(_ fields: [String]) -> String { fields.map(LibrarySearch.fold).joined(separator: "\n") }

    /// `key(_:)` ile kurulmuş anahtarda arama; `matches(_:query:)` ile aynı sonucu verir.
    static func matches(key: String, query: String) -> Bool {
        LibrarySearch.tokens(query).allSatisfy { key.contains($0) }
    }
}
