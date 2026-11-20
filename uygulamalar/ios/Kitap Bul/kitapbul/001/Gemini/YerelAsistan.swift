import Foundation

/// Ağ yokken ya da Gemini engelliyken/sınırı doluyken asistanın cihazda yanıtlayabildiği kısa sorular.
/// Yalnız katalog ve ödünç verisinden, kalıplarla çalışır; anlamadığı soruda `nil` döner ve
/// çağıran normal hata kartını gösterir. Hiçbir veri cihazdan çıkmaz.
enum YerelAsistan {
    struct Yanit: Equatable {
        var text: String
        var bookIDs: [UUID] = []
    }

    enum Niyet: Equatable {
        case kitapSayisi
        case gecikenler
        case kitapVarMi(String)
    }

    /// Yerel yanıtın devreye gireceği hatalar: bağlantı sorunu ya da aylık sınır.
    static func shouldAnswerLocally(after error: Error) -> Bool {
        switch error as? GeminiError {
        case .network, .limitReached: true
        case .http(let code, _)? where code == 429 || (500...599).contains(code): true
        default: false
        }
    }

    // MARK: Niyet

    static func intent(for question: String) -> Niyet? {
        let text = CatalogMatcher.normalize(question)
        guard !text.isEmpty else { return nil }
        if matches(text, #"\b(kac|toplam)\b.*\b(kitap|kitabimiz|nusha|eser)\b"#) || matches(text, #"\bkitap sayisi\b"#) {
            return .kitapSayisi
        }
        if matches(text, #"\bgecik\w*"#),
           matches(text, #"\b(var mi|kac|hangi|kimler|kim|liste|listesi|goster)\b"#) {
            return .gecikenler
        }
        // "<ad> var mı", "<ad> nerede", "<ad> bizde mi"
        if let range = text.range(of: #"\s+(var mi|nerede|nerde|bulunuyor mu|bizde mi|rafta mi)$"#, options: .regularExpression) {
            let subject = String(text[..<range.lowerBound])
                .replacingOccurrences(of: #"^(kutuphanede|katalogda|bizde|acaba|peki)\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+(kitabi|kitap|isimli kitap|adli kitap)$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if subject.count >= 2 { return .kitapVarMi(subject) }
        }
        return nil
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: Yanıt

    static func answer(_ question: String, books: [CatalogBook], loans: [ActiveLoan], now: Date = .now) -> Yanit? {
        guard let niyet = intent(for: question) else { return nil }
        switch niyet {
        case .kitapSayisi:
            let active = books.filter { !$0.isWithdrawn }
            let copies = active.reduce(0) { $0 + ($1.quantity ?? 1) }
            let overdue = loans.filter(\.isOverdue).count
            return Yanit(text: "Katalogda \(active.count) kitap (\(copies) nüsha) var. Şu an \(loans.count) ödünçte, \(overdue) tanesi gecikmiş.")
        case .gecikenler:
            let overdue = loans.filter(\.isOverdue).sorted { $0.dueDate < $1.dueDate }
            guard !overdue.isEmpty else { return Yanit(text: "Geciken ödünç yok.") }
            let calendar = Calendar.current
            let lines = overdue.prefix(5).map { loan -> String in
                let days = calendar.dateComponents([.day], from: loan.dueDate, to: now).day ?? 0
                let klass = loan.studentClass.isEmpty ? "" : " (\(loan.studentClass))"
                return "• \(loan.bookTitleSnapshot) — \(loan.studentName)\(klass), \(days) gün"
            }
            let more = overdue.count > 5 ? "\n… ve \(overdue.count - 5) ödünç daha." : ""
            return Yanit(text: "\(overdue.count) geciken ödünç var:\n" + lines.joined(separator: "\n") + more,
                         bookIDs: Array(overdue.prefix(5).map(\.bookID)))
        case .kitapVarMi(let subject):
            let found = AssistantContext.matchingBooks(for: subject, in: books, limit: 3)
            guard !found.isEmpty else {
                return Yanit(text: "“\(subject)” için katalogda eşleşme bulamadım. Kitaplar sekmesinden de arayabilirsiniz.")
            }
            let counts = AssistantContext.loanCounts(loans)
            let lines = found.map { book -> String in
                let total = book.quantity ?? 1
                let free = max(0, total - (counts[book.id] ?? 0))
                let place = book.konumMetni ?? "yeri belirtilmemiş"
                return "• “\(book.title)” — \(book.author.isEmpty ? "yazar bilinmiyor" : book.author): \(place), boşta \(free)/\(total)"
            }
            return Yanit(text: lines.joined(separator: "\n"), bookIDs: found.map(\.id))
        }
    }
}
