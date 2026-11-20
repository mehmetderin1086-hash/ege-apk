import Foundation

/// Düzenleyici sınırları arşiv verisini temizlemez. Eski bir alana dokunulmadıysa
/// özgün metin korunur; yeni veya değiştirilmiş uygunsuz değer kaydedilemez.
nonisolated enum BookEditorValidation {
    enum Field: String, CaseIterable, Hashable, Sendable {
        case title, isbn, publicationYear, pageCount, quantity, location, cabinet, shelf
        var label: String {
            switch self {
            case .title: "Kitap adı"
            case .isbn: "ISBN"
            case .publicationYear: "Basım yılı"
            case .pageCount: "Sayfa sayısı"
            case .quantity: "Adet"
            case .location: "Oda / Genel konum"
            case .cabinet: "Dolap"
            case .shelf: "Raf"
            }
        }
    }

    struct Input: Equatable, Sendable {
        var title = ""
        var isbn = ""
        var publicationYear = ""
        var pageCount = ""
        var quantity = 1
        var location = ""
        var cabinet = ""
        var shelf = ""

        fileprivate func value(_ field: Field) -> String {
            switch field {
            case .title: title
            case .isbn: isbn
            case .publicationYear: publicationYear
            case .pageCount: pageCount
            case .quantity: String(quantity)
            case .location: location
            case .cabinet: cabinet
            case .shelf: shelf
            }
        }
    }

    struct Issue: Equatable, Sendable {
        let field: Field
        let message: String
        let isBlocking: Bool
        var description: String {
            let detail = isBlocking ? message : message + " Eski değer değiştirilmeden korunacak; düzeltmek için bu alanı düzenleyin."
            return field.label + ": " + detail
        }
    }

    struct Result: Equatable, Sendable {
        let issues: [Issue]
        var canSave: Bool { !issues.contains(where: \.isBlocking) }
        func issue(for field: Field) -> Issue? { issues.first { $0.field == field } }
    }

    struct ValidationError: LocalizedError {
        let messages: [String]
        var errorDescription: String? { messages.joined(separator: "\n") }
    }

    /// Mevcut editör ve AI düzenleme sınırı. Raf fotoğrafındaki 99 nüsha sınırı
    /// model çıktısı içindir; bütün katalog eserine aynı sınır uygulanmaz.
    static let quantityRange = 1...9999
    /// OCR okuyucusunun mevcut üst sınırı; kısa resimli kitaplar da kabul edilir.
    static let pageRange = 1...9999
    static func calendarYear(now: Date = .now) -> Int {
        Calendar(identifier: .gregorian).component(.year, from: now)
    }

    static func validate(_ input: Input, existing baseline: Input? = nil,
                         currentYear: Int = BookEditorValidation.calendarYear()) -> Result {
        var issues: [Issue] = []
        func add(_ field: Field, _ message: String) {
            // Boş kitap adı önceki davranış gibi daima engeldir. Diğer alanların
            // miras değeri yalnız gerçek mevcut kayıt için verilen baseline ile korunur.
            let unchanged = baseline?.value(field) == input.value(field)
            issues.append(Issue(field: field, message: message, isBlocking: field == .title || !unchanged))
        }
        if trimmed(input.title).isEmpty { add(.title, "Kitap adı gerekli.") }
        if !trimmed(input.isbn).isEmpty, normalizedISBN(input.isbn) == nil {
            add(.isbn, "Geçerli ISBN-10 veya 978/979 ile başlayan ISBN-13 girin; kontrol basamağı doğru olmalı.")
        }
        let year = trimmed(input.publicationYear)
        if !year.isEmpty, positiveInteger(year).map({ $0 <= currentYear + 1 }) != true {
            add(.publicationYear, "Boş bırakın veya 1–\(currentYear + 1) arasında tam yıl girin. Gelecek yılın baskıları kabul edilir.")
        }
        let pages = trimmed(input.pageCount)
        if !pages.isEmpty, positiveInteger(pages).map(pageRange.contains) != true {
            add(.pageCount, "Boş bırakın veya 1–9999 arasında tam sayfa sayısı girin.")
        }
        if !quantityRange.contains(input.quantity) { add(.quantity, "Adet 1–9999 arasında olmalı.") }
        for field in [Field.location, .cabinet, .shelf] {
            if containsInvisibleControl(input.value(field)) {
                add(field, "Satır sonu, kontrol veya görünmez biçim karakterlerini kaldırın. Konum adı serbest metindir.")
            }
        }
        return Result(issues: issues)
    }

    /// Taslak yedeği ve alan kaynağı karşılaştırması, hatalı girilmiş metni bile
    /// saklar. Bu fonksiyon doğrulanmış katalog kaydı oluşturmak için kullanılmaz.
    static func preservingInput(in book: Book, input: Input) -> Book {
        var result = book
        result.title = input.title
        result.isbn = rawOptional(input.isbn)
        result.publicationYear = rawOptional(input.publicationYear)
        result.pageCount = rawOptional(input.pageCount)
        result.quantity = input.quantity
        result.location = rawOptional(input.location)
        result.cabinet = rawOptional(input.cabinet)
        result.shelf = rawOptional(input.shelf)
        return result
    }

    static func preparedBook(_ book: Book, input: Input, existing baseline: Input? = nil,
                             currentYear: Int = BookEditorValidation.calendarYear()) throws -> Book {
        let result = validate(input, existing: baseline, currentYear: currentYear)
        guard result.canSave else { throw ValidationError(messages: result.issues.filter(\.isBlocking).map(\.description)) }
        var prepared = preservingInput(in: book, input: input)
        // Hiç dokunulmayan eski alanları trim/onarım bahanesiyle yeniden yazma.
        func changed(_ field: Field) -> Bool { baseline?.value(field) != input.value(field) }
        if changed(.title) { prepared.title = trimmed(input.title) }
        if changed(.isbn) { prepared.isbn = normalizedISBN(input.isbn) }
        if changed(.publicationYear) { prepared.publicationYear = trimmedOptional(input.publicationYear) }
        if changed(.pageCount) { prepared.pageCount = trimmedOptional(input.pageCount) }
        if changed(.location) { prepared.location = trimmedOptional(input.location) }
        if changed(.cabinet) { prepared.cabinet = trimmedOptional(input.cabinet) }
        if changed(.shelf) { prepared.shelf = trimmedOptional(input.shelf) }
        return prepared
    }

    /// Onarım önerisi seçmeden harfleri rakam gibi kabul etmez. ISBN-10 kontrol
    /// toplamı da doğrulanır; yalnız bundan sonra standart ISBN-13'e çevrilir.
    static func normalizedISBN(_ text: String) -> String? {
        let value = trimmed(text).uppercased()
        guard !value.isEmpty else { return nil }
        var compact = ""
        for scalar in value.unicodeScalars {
            if (48...57).contains(scalar.value) || scalar == "X" { compact.unicodeScalars.append(scalar) }
            else if CharacterSet.whitespaces.contains(scalar) || "-‐‑‒–—−".unicodeScalars.contains(scalar) { continue }
            else { return nil }
        }
        if compact.count == 13 {
            guard compact.hasPrefix("978") || compact.hasPrefix("979"),
                  compact.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }),
                  ISBNFormatter.isValidISBN13(compact) else { return nil }
            return compact
        }
        guard compact.count == 10 else { return nil }
        let chars = Array(compact)
        var checksum = 0
        for (index, character) in chars.enumerated() {
            let digit: Int
            if index == 9, character == "X" { digit = 10 }
            else if let value = character.wholeNumberValue, value <= 9 { digit = value }
            else { return nil }
            checksum += digit * (10 - index)
        }
        guard checksum.isMultiple(of: 11) else { return nil }
        let firstTwelve = "978" + String(chars.prefix(9))
        let sum = firstTwelve.enumerated().reduce(0) { total, item in
            total + (item.element.wholeNumberValue ?? 0) * (item.offset.isMultiple(of: 2) ? 1 : 3)
        }
        return firstTwelve + String((10 - sum % 10) % 10)
    }

    private static func positiveInteger(_ value: String) -> Int? {
        guard !value.isEmpty, value.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }),
              let number = Int(value), number > 0 else { return nil }
        return number
    }
    private static func containsInvisibleControl(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            switch $0.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator: true
            default: false
            }
        }
    }
    private static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func trimmedOptional(_ text: String) -> String? { rawOptional(trimmed(text)) }
    private static func rawOptional(_ text: String) -> String? { text.isEmpty ? nil : text }
}
