import Foundation
import Testing
@testable import _01

struct BookEditorValidationTestleri {
    @Test func invalidNewFieldsBlockWithoutDeletingEnteredValues() throws {
        let input = BookEditorValidation.Input(title: "Yeni Eser", isbn: "ISBN 9780306406157", publicationYear: "2028", pageCount: "0", quantity: 0, cabinet: "A\u{200B}")
        let result = BookEditorValidation.validate(input, currentYear: 2026)
        #expect(Set(result.issues.filter(\.isBlocking).map(\.field)) == Set([.isbn, .publicationYear, .pageCount, .quantity, .cabinet]))
        #expect(!result.canSave)
        let draft = BookEditorValidation.preservingInput(in: Book(title: "Yeni Eser", author: "Yazar"), input: input)
        let roundTrip = try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(draft))
        #expect(roundTrip.isbn == input.isbn && roundTrip.pageCount == "0" && roundTrip.cabinet == input.cabinet)
        #expect(throws: BookEditorValidation.ValidationError.self) {
            _ = try BookEditorValidation.preparedBook(draft, input: input, currentYear: 2026)
        }
        #expect(draft.isbn == input.isbn && draft.quantity == 0)
    }

    @Test func historicalYearsShortBooksAndOptionalUnknownValuesAreValid() throws {
        var input = BookEditorValidation.Input(title: "Eski Eser")
        #expect(BookEditorValidation.validate(input, currentYear: 2026).canSave)
        input.publicationYear = "1453"; input.pageCount = "4"
        #expect(BookEditorValidation.validate(input, currentYear: 2026).canSave)
        input.publicationYear = "2027"; input.pageCount = "9999"; input.quantity = 9999
        #expect(BookEditorValidation.validate(input, currentYear: 2026).canSave)
        input.publicationYear = "2028"; input.pageCount = "10000"; input.quantity = 10000
        let result = BookEditorValidation.validate(input, currentYear: 2026)
        #expect(Set(result.issues.map(\.field)) == Set([.publicationYear, .pageCount, .quantity]))
        input.publicationYear = "tarihsiz"; input.pageCount = "12,5"
        #expect(!BookEditorValidation.validate(input, currentYear: 2026).canSave)
        input.publicationYear = " "; input.pageCount = " " ; input.quantity = 1
        let saved = try BookEditorValidation.preparedBook(Book(title: "Eser", author: "Y"), input: input, currentYear: 2026)
        #expect(saved.publicationYear == nil && saved.pageCount == nil && saved.isbn == nil)
    }

    @Test func ISBN10And13RequireRealChecksumsAndBookPrefixes() {
        #expect(BookEditorValidation.normalizedISBN("978-0-306-40615-7") == "9780306406157")
        #expect(BookEditorValidation.normalizedISBN("0-306-40615-2") == "9780306406157")
        #expect(BookEditorValidation.normalizedISBN("0-8044-2957-X") != nil)
        #expect(BookEditorValidation.normalizedISBN("0-306-40615-3") == nil)
        #expect(BookEditorValidation.normalizedISBN("9780306406158") == nil)
        #expect(BookEditorValidation.normalizedISBN("4006381333931") == nil)
        #expect(BookEditorValidation.normalizedISBN("ISBN:9780306406157") == nil)
        #expect(BookEditorValidation.normalizedISBN("978O306406157") == nil)
    }

    @Test func unchangedLegacyInvalidFieldsSurviveUnrelatedEditExactly() throws {
        let initial = BookEditorValidation.Input(title: "Eski Eser", isbn: "yanlış isbn", publicationYear: "tarihsiz", pageCount: "iv, 128", quantity: 0, location: "Kat\n1", cabinet: " A ", shelf: "Çocuk / 6 Türk Edebiyatı")
        var edited = initial; edited.title = "Düzeltilen Eser"
        let result = BookEditorValidation.validate(edited, existing: initial, currentYear: 2026)
        #expect(result.canSave && result.issues.count == 5)
        #expect(result.issues.allSatisfy { !$0.isBlocking })
        let original = BookEditorValidation.preservingInput(in: Book(title: initial.title, author: "Y"), input: initial)
        let saved = try BookEditorValidation.preparedBook(original, input: edited, existing: initial, currentYear: 2026)
        #expect(saved.title == "Düzeltilen Eser")
        #expect(saved.isbn == original.isbn && saved.publicationYear == original.publicationYear && saved.pageCount == original.pageCount)
        #expect(saved.quantity == 0 && saved.location == original.location && saved.cabinet == " A " && saved.shelf == original.shelf)
        edited.pageCount = "iii, 200"
        #expect(BookEditorValidation.validate(edited, existing: initial, currentYear: 2026).issue(for: .pageCount)?.isBlocking == true)
        // Aynı ham değer yeni OCR/elle ekleme taslağında miras ayrıcalığı kazanamaz.
        #expect(!BookEditorValidation.validate(initial, currentYear: 2026).canSave)
    }

    @Test func freeformTurkishLocationsTrimOnlyChangedFieldsAndRejectInvisibleCharacters() throws {
        let initial = BookEditorValidation.Input(title: "Eser", location: " Oda 1 ", cabinet: " B ", shelf: " 6 Türk Edebiyatı ")
        var edited = initial; edited.cabinet = "  Öğretmenler Odası / Ç-2  "
        let saved = try BookEditorValidation.preparedBook(Book(title: "Eser", author: "Y"), input: edited, existing: initial, currentYear: 2026)
        #expect(saved.cabinet == "Öğretmenler Odası / Ç-2")
        #expect(saved.location == initial.location && saved.shelf == initial.shelf)
        for invisible in ["\n", "\t", "\u{0000}", "\u{200B}", "\u{2066}", "\u{2028}"] {
            edited.shelf = "Türkçe" + invisible + "Raf"
            #expect(BookEditorValidation.validate(edited, existing: initial, currentYear: 2026).issue(for: .shelf)?.isBlocking == true)
        }
    }

    @Test func unrelatedEditDoesNotRelabelPreservedLegacyISBNAsManualChange() throws {
        let initial = BookEditorValidation.Input(title: "Eski", isbn: "eski-künye")
        let original = BookEditorValidation.preservingInput(in: Book(title: initial.title, author: "Y"), input: initial)
        var edited = initial; edited.title = "Yeni Başlık"
        let prepared = try BookEditorValidation.preparedBook(original, input: edited, existing: initial, currentYear: 2026)
        let stamped = BookFieldMetadata.stampChanges(before: original, after: prepared, source: "manual")
        #expect(stamped.isbn == "eski-künye")
        #expect(BookFieldMetadata.isLocked("title", metadata: stamped.fieldMetadata))
        #expect(!BookFieldMetadata.isLocked("isbn", metadata: stamped.fieldMetadata))
    }
}
