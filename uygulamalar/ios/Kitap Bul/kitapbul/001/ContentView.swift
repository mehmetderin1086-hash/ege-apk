import SwiftUI
import CoreSpotlight
import SwiftData
import PhotosUI
@preconcurrency import Vision
import PDFKit
import ImageIO
import UniformTypeIdentifiers
import CoreImage
#if os(iOS)
import UIKit
import VisionKit
#endif

/// Saf değer tipi; arşiv/Excel/yedek üreticileri arka planda kullanır, bu yüzden
/// ana aktöre bağlı değildir (Codable uyumu da izolasyonsuz kalır).
nonisolated struct Book: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var author: String
    var publisher: String?
    var isbn: String?
    var publicationYear: String?
    var edition: String?
    var pageCount: String?
    var notes: String
    var category: String?
    var location: String?
    var language: String?
    var readingStatus: String?
    var rating: Int?
    var quantity: Int?
    var shelf: String?
    var cabinet: String?
    var coverData: Data?
    var backCoverData: Data?
    var imprintData: Data?
    var accessionCode: String?
    var isWithdrawn: Bool = false
    var withdrawnReason: String?
    var withdrawnDate: Date?
    var isTextbook: Bool = false
    var loanedTo: String?
    var loanDueDate: Date?
    // Seri, etiket, düzey ve içerik bilgisi (hepsi isteğe bağlı; eski yedekler sorunsuz çözülür)
    var series: String? = nil
    var volume: Int? = nil
    var tags: String? = nil
    var readingLevel: String? = nil
    var contentWarning: String? = nil
    var fieldMetadata: String? = nil
    let addedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        author: String,
        publisher: String? = nil,
        isbn: String? = nil,
        publicationYear: String? = nil,
        edition: String? = nil,
        pageCount: String? = nil,
        notes: String = "",
        category: String? = nil,
        location: String? = nil,
        language: String? = nil,
        readingStatus: String? = nil,
        rating: Int? = nil,
        quantity: Int? = nil,
        shelf: String? = nil,
        cabinet: String? = nil,
        coverData: Data? = nil,
        backCoverData: Data? = nil,
        imprintData: Data? = nil,
        accessionCode: String? = nil,
        isWithdrawn: Bool = false,
        withdrawnReason: String? = nil,
        withdrawnDate: Date? = nil,
        isTextbook: Bool = false,
        loanedTo: String? = nil,
        loanDueDate: Date? = nil,
        series: String? = nil,
        volume: Int? = nil,
        tags: String? = nil,
        readingLevel: String? = nil,
        contentWarning: String? = nil,
        fieldMetadata: String? = nil,
        addedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.publisher = publisher
        self.isbn = isbn
        self.publicationYear = publicationYear
        self.edition = edition
        self.pageCount = pageCount
        self.notes = notes
        self.category = category
        self.location = location
        self.language = language
        self.readingStatus = readingStatus
        self.rating = rating
        self.quantity = quantity
        self.shelf = shelf
        self.cabinet = cabinet
        self.coverData = coverData
        self.backCoverData = backCoverData
        self.imprintData = imprintData
        self.accessionCode = accessionCode
        self.isWithdrawn = isWithdrawn
        self.withdrawnReason = withdrawnReason
        self.withdrawnDate = withdrawnDate
        self.isTextbook = isTextbook
        self.loanedTo = loanedTo
        self.loanDueDate = loanDueDate
        self.series = series
        self.volume = volume
        self.tags = tags
        self.readingLevel = readingLevel
        self.contentWarning = contentWarning
        self.fieldMetadata = fieldMetadata
        self.addedAt = addedAt
    }

    var isOverdue: Bool {
        guard loanedTo?.isEmpty == false, let due = loanDueDate else { return false }
        return due < .now
    }
}

extension Book {
    /// İçerikten türetilen kararlı UUID (FNV-1a, iki farklı tohum → 128 bit).
    nonisolated static func stableID(title: String, author: String, isbn: String) -> UUID {
        let bytes = Array("\(title)|\(author)|\(isbn)".utf8)
        func fnv(_ seed: UInt64) -> UInt64 {
            var hash = seed
            for byte in bytes { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
            return hash
        }
        let a = fnv(0xcbf29ce484222325), b = fnv(0x84222325cbf29ce4)
        var raw = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            raw[i] = UInt8(truncatingIfNeeded: a >> (UInt64(i) * 8))
            raw[i + 8] = UInt8(truncatingIfNeeded: b >> (UInt64(i) * 8))
        }
        raw[6] = (raw[6] & 0x0F) | 0x50   // sürüm 5 biçimi
        raw[8] = (raw[8] & 0x3F) | 0x80
        return UUID(uuid: (raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
                           raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]))
    }

    nonisolated private enum CodingKeys: String, CodingKey {
        case id, title, author, publisher, isbn, publicationYear, edition, pageCount, notes
        case category, location, language, readingStatus, rating, quantity, shelf, cabinet
        case coverData, backCoverData, imprintData, accessionCode, isWithdrawn, withdrawnReason
        case withdrawnDate, isTextbook, loanedTo, loanDueDate, series, volume, tags
        case readingLevel, contentWarning, fieldMetadata, addedAt
    }

    /// Hoşgörülü çözücü: eski sürümlerin yedeklerinde bulunmayan alanlar
    /// (düşüm, ders kitabı, seri vb.) varsayılana düşer; yedek tümden reddedilmez.
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            // Kimliği olmayan eski kayıt: içerikten kararlı kimlik (aynı yedek iki kez yüklenince çoğalmasın)
            id: (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? Book.stableID(
                title: (try? c.decodeIfPresent(String.self, forKey: .title)) ?? "",
                author: (try? c.decodeIfPresent(String.self, forKey: .author)) ?? "",
                isbn: (try? c.decodeIfPresent(String.self, forKey: .isbn)) ?? ""),
            title: try c.decode(String.self, forKey: .title),
            author: (try? c.decodeIfPresent(String.self, forKey: .author)) ?? "",
            publisher: try? c.decodeIfPresent(String.self, forKey: .publisher),
            isbn: try? c.decodeIfPresent(String.self, forKey: .isbn),
            publicationYear: try? c.decodeIfPresent(String.self, forKey: .publicationYear),
            edition: try? c.decodeIfPresent(String.self, forKey: .edition),
            pageCount: try? c.decodeIfPresent(String.self, forKey: .pageCount),
            notes: (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? "",
            category: try? c.decodeIfPresent(String.self, forKey: .category),
            location: try? c.decodeIfPresent(String.self, forKey: .location),
            language: try? c.decodeIfPresent(String.self, forKey: .language),
            readingStatus: try? c.decodeIfPresent(String.self, forKey: .readingStatus),
            rating: try? c.decodeIfPresent(Int.self, forKey: .rating),
            quantity: try? c.decodeIfPresent(Int.self, forKey: .quantity),
            shelf: try? c.decodeIfPresent(String.self, forKey: .shelf),
            cabinet: try? c.decodeIfPresent(String.self, forKey: .cabinet),
            coverData: try? c.decodeIfPresent(Data.self, forKey: .coverData),
            backCoverData: try? c.decodeIfPresent(Data.self, forKey: .backCoverData),
            imprintData: try? c.decodeIfPresent(Data.self, forKey: .imprintData),
            accessionCode: try? c.decodeIfPresent(String.self, forKey: .accessionCode),
            isWithdrawn: (try? c.decodeIfPresent(Bool.self, forKey: .isWithdrawn)) ?? false,
            withdrawnReason: try? c.decodeIfPresent(String.self, forKey: .withdrawnReason),
            withdrawnDate: try c.decodeIfPresent(Date.self, forKey: .withdrawnDate),
            isTextbook: (try? c.decodeIfPresent(Bool.self, forKey: .isTextbook)) ?? false,
            loanedTo: try? c.decodeIfPresent(String.self, forKey: .loanedTo),
            loanDueDate: try c.decodeIfPresent(Date.self, forKey: .loanDueDate),
            series: try? c.decodeIfPresent(String.self, forKey: .series),
            volume: try? c.decodeIfPresent(Int.self, forKey: .volume),
            tags: try? c.decodeIfPresent(String.self, forKey: .tags),
            readingLevel: try? c.decodeIfPresent(String.self, forKey: .readingLevel),
            contentWarning: try? c.decodeIfPresent(String.self, forKey: .contentWarning),
            fieldMetadata: try? c.decodeIfPresent(String.self, forKey: .fieldMetadata),
            // Tarihler bilerek "try": biçim uymazsa yedek okuyucu diğer tarih biçimini dener
            addedAt: try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? .now
        )
    }
}

struct BookDraft: Identifiable {
    var id = UUID()
    var existingBookID: UUID?
    var title = ""
    var author = ""
    var publisher = ""
    var isbn = ""
    var publicationYear = ""
    var edition = ""
    var pageCount = ""
    var notes = ""
    var category = ""
    var location = ""
    var language = ""
    var readingStatus = "Okunacak"
    var rating = 0
    var quantity = 1
    var shelf = ""
    var cabinet = ""
    var coverData: Data?
    var backCoverData: Data?
    var imprintData: Data?
    var isTextbook = false
    var series = ""
    var volume = 0
    var tags = ""
    var readingLevel = ""
    var contentWarning = ""
    var lowConfidenceFields: Set<String> = []
    /// Alanlar Gemini OCR ile okundu (düzenleyicide rozet gösterilir).
    var recognizedByGemini = false
    var fieldMetadata: String?
    var recognitionSource: String?
    /// Yalnız arayüz notu (ör. "ISBN kaynaklarda bulunamadı"); formun üstünde görünür.
    /// Kayda, `init(book:)`'a ve kaydedilmemiş değişiklik denetimine girmez.
    var bilgiNotu: String?
    /// Depo taramasında kayıtlı kitap başka yerde okutulduysa onay kuyruğu satırında "Konum farklı: A-3 → B-1".
    var konumFarki: String?

    init() { }

    init(book: Book) {
        existingBookID = book.id
        title = book.title
        author = book.author
        publisher = book.publisher ?? ""
        isbn = book.isbn ?? ""
        publicationYear = book.publicationYear ?? ""
        edition = book.edition ?? ""
        pageCount = book.pageCount ?? ""
        notes = book.notes
        category = book.category ?? ""
        location = book.location ?? ""
        language = book.language ?? ""
        readingStatus = book.readingStatus ?? "Okunacak"
        rating = book.rating ?? 0
        quantity = book.quantity ?? 1
        shelf = book.shelf ?? ""
        cabinet = book.cabinet ?? ""
        coverData = book.coverData
        backCoverData = book.backCoverData
        imprintData = book.imprintData
        isTextbook = book.isTextbook
        series = book.series ?? ""
        volume = book.volume ?? 0
        tags = book.tags ?? ""
        readingLevel = book.readingLevel ?? ""
        contentWarning = book.contentWarning ?? ""
        fieldMetadata = book.fieldMetadata
    }
}

extension BookDraft {
    var snapshot: Book {
        let draft = self
        return Book(
            id: draft.existingBookID ?? draft.id,
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            author: draft.author.trimmingCharacters(in: .whitespacesAndNewlines),
            publisher: draft.publisher.isEmpty ? nil : draft.publisher,
            isbn: ISBNFormatter.repair(draft.isbn).isEmpty
                ? nil
                : ISBNFormatter.repair(draft.isbn),
            publicationYear: draft.publicationYear.isEmpty ? nil : draft.publicationYear,
            edition: draft.edition.isEmpty ? nil : draft.edition,
            pageCount: draft.pageCount.isEmpty ? nil : draft.pageCount,
            notes: draft.notes,
            category: draft.category.isEmpty ? nil : draft.category,
            location: draft.location.isEmpty ? nil : draft.location,
            language: draft.language.isEmpty ? nil : draft.language,
            readingStatus: draft.readingStatus,
            rating: draft.rating == 0 ? nil : draft.rating,
            quantity: draft.quantity,
            shelf: draft.shelf.isEmpty ? nil : draft.shelf,
            cabinet: draft.cabinet.isEmpty ? nil : draft.cabinet,
            coverData: draft.coverData,
            backCoverData: draft.backCoverData,
            imprintData: draft.imprintData,
            isTextbook: draft.isTextbook,
            series: draft.series.isEmpty ? nil : draft.series,
            volume: draft.volume == 0 ? nil : draft.volume,
            tags: draft.tags.isEmpty ? nil : draft.tags,
            readingLevel: draft.readingLevel.isEmpty ? nil : draft.readingLevel,
            contentWarning: draft.contentWarning.isEmpty ? nil : draft.contentWarning,
            fieldMetadata: draft.fieldMetadata
        )
    }

}

@Model
final class CatalogBook {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String
    var publisher: String?
    var isbn: String?
    var publicationYear: String?
    var edition: String?
    var pageCount: String?
    var notes: String
    var category: String?
    var location: String?
    var language: String?
    var readingStatus: String?
    var rating: Int?
    var quantity: Int?
    var shelf: String?
    var cabinet: String?
    @Attribute(.externalStorage) var coverData: Data?
    @Attribute(.externalStorage) var backCoverData: Data?
    @Attribute(.externalStorage) var imprintData: Data?
    var accessionCode: String?
    var isWithdrawn: Bool = false
    var withdrawnReason: String?
    var withdrawnDate: Date?
    var isTextbook: Bool = false
    var loanedTo: String?
    var loanDueDate: Date?
    var addedAt: Date
    /// Ad + yazar + kategori + yayınevinin aksansız/küçük harfli birleşimi. Asistan ve
    /// büyük kataloglarda arama, bellekte 50 bin kaydı tek tek normalize etmek yerine
    /// veritabanında bu alan üzerinden ön süzme yapar. Kayıt/güncellemede yenilenir.
    var searchKey: String?
    /// Kayıt sonrası AI zenginleştirmesinin ürettiği anahtar sözcükler (virgülle); aramaya katılır.
    var aiKeywords: String?
    var series: String?
    var volume: Int?
    /// Virgülle ayrılmış etiketler ("TÜBİTAK, 100 Temel Eser")
    var tags: String?
    /// Önerilen okuma düzeyi ("5–7. sınıf")
    var readingLevel: String?
    /// Yaş düzeyine uygunluk uyarısı (Gemini ya da kütüphaneci)
    var contentWarning: String?
    var fieldMetadata: String?

    /// Etiket listesi (boşlukları kırpılmış)
    var tagList: [String] {
        (tags ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var isOverdue: Bool {
        guard loanedTo?.isEmpty == false, let due = loanDueDate else { return false }
        return due < .now
    }

    /// `searchKey` alanını mevcut değerlerden üretir.
    static func makeSearchKey(title: String, author: String, category: String?, publisher: String?,
                              keywords: String? = nil, series: String? = nil, tags: String? = nil) -> String {
        CatalogMatcher.normalize([title, author, category ?? "", publisher ?? "", keywords ?? "", series ?? "", tags ?? ""]
            .joined(separator: " "))
    }

    /// Düzenleyici yalnızca katalog alanlarını bilir; demirbaş kodu, düşülme ve ödünç
    /// bilgisi ondan gelmez. Kaydederken bunlar mevcut kayıttan korunur (aksi hâlde silinirdi).
    func preservingRecordFields(of edited: Book) -> Book {
        var book = edited
        book.accessionCode = edited.accessionCode ?? accessionCode
        book.isWithdrawn = isWithdrawn
        book.withdrawnReason = withdrawnReason
        book.withdrawnDate = withdrawnDate
        book.loanedTo = loanedTo
        book.loanDueDate = loanDueDate
        book.fieldMetadata = edited.fieldMetadata ?? fieldMetadata
        return book
    }

    func refreshSearchKey() {
        searchKey = Self.makeSearchKey(title: title, author: author, category: category, publisher: publisher,
                                       keywords: aiKeywords, series: series, tags: tags)
    }

    init(book: Book) {
        id = book.id
        title = book.title
        author = book.author
        publisher = book.publisher
        isbn = book.isbn
        publicationYear = book.publicationYear
        edition = book.edition
        pageCount = book.pageCount
        notes = book.notes
        category = book.category
        location = book.location
        language = book.language
        readingStatus = book.readingStatus
        rating = book.rating
        quantity = book.quantity
        shelf = book.shelf
        cabinet = book.cabinet
        coverData = book.coverData
        backCoverData = book.backCoverData
        imprintData = book.imprintData
        accessionCode = book.accessionCode
        isWithdrawn = book.isWithdrawn
        withdrawnReason = book.withdrawnReason
        withdrawnDate = book.withdrawnDate
        isTextbook = book.isTextbook
        loanedTo = book.loanedTo
        loanDueDate = book.loanDueDate
        series = book.series
        volume = book.volume
        tags = book.tags
        readingLevel = book.readingLevel
        contentWarning = book.contentWarning
        fieldMetadata = book.fieldMetadata
        addedAt = book.addedAt
        refreshSearchKey()
    }

    func update(from book: Book) {
        title = book.title
        author = book.author
        publisher = book.publisher
        isbn = book.isbn
        publicationYear = book.publicationYear
        edition = book.edition
        pageCount = book.pageCount
        notes = book.notes
        category = book.category
        location = book.location
        language = book.language
        readingStatus = book.readingStatus
        rating = book.rating
        quantity = book.quantity
        shelf = book.shelf
        cabinet = book.cabinet
        coverData = book.coverData
        backCoverData = book.backCoverData
        imprintData = book.imprintData
        accessionCode = book.accessionCode
        isWithdrawn = book.isWithdrawn
        withdrawnReason = book.withdrawnReason
        withdrawnDate = book.withdrawnDate
        isTextbook = book.isTextbook
        loanedTo = book.loanedTo
        loanDueDate = book.loanDueDate
        series = book.series
        volume = book.volume
        tags = book.tags
        readingLevel = book.readingLevel
        contentWarning = book.contentWarning
        fieldMetadata = book.fieldMetadata
        refreshSearchKey()
    }

    var book: Book {
        Book(
            id: id,
            title: title,
            author: author,
            publisher: publisher,
            isbn: isbn,
            publicationYear: publicationYear,
            edition: edition,
            pageCount: pageCount,
            notes: notes,
            category: category,
            location: location,
            language: language,
            readingStatus: readingStatus,
            rating: rating,
            quantity: quantity,
            shelf: shelf,
            cabinet: cabinet,
            coverData: coverData,
            backCoverData: backCoverData,
            imprintData: imprintData,
            accessionCode: accessionCode,
            isWithdrawn: isWithdrawn,
            withdrawnReason: withdrawnReason,
            withdrawnDate: withdrawnDate,
            isTextbook: isTextbook,
            loanedTo: loanedTo,
            loanDueDate: loanDueDate,
            series: series,
            volume: volume,
            tags: tags,
            readingLevel: readingLevel,
            contentWarning: contentWarning,
            fieldMetadata: fieldMetadata,
            addedAt: addedAt
        )
    }
}

enum CatalogLayout: String, CaseIterable, Identifiable {
    case list = "Liste"
    case grid = "Kapaklar"
    case shelves = "Raflar"

    var id: Self { self }

    var icon: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.2x2"
        case .shelves: "books.vertical"
        }
    }
}

enum ScanAction: Equatable {
    case saved(UUID)
    case queued(UUID)
    case merged(UUID, added: Int)
}

enum SaveOutcome {
    case updated
    case inserted(UUID)
    case merged(UUID, added: Int)
    case failed(String)

    var succeeded: Bool { if case .failed = self { return false }; return true }
}

enum ContentPresentation { case add, management }

enum CatalogFilter: String, CaseIterable, Identifiable {
    case all = "Tümü"
    case incomplete = "Eksik Bilgi"
    case unread = "Okunacak"
    case reading = "Okunuyor"
    case read = "Okundu"
    case loaned = "Ödünçte"
    case withdrawn = "Düşülenler"

    var id: Self { self }

    var icon: String {
        switch self {
        case .all: "tray.full"
        case .incomplete: "exclamationmark.triangle"
        case .unread: "bookmark"
        case .reading: "book"
        case .read: "checkmark.circle"
        case .loaned: "person.badge.clock"
        case .withdrawn: "archivebox"
        }
    }
}

/// Arama metnini doğrudan SwiftData sorgusuna indiren sarmalayıcı.
/// 50.000 kayıtta tüm kayıtları hafızaya alıp süzmek yerine veritabanı süzer.
struct CatalogQueryView<Content: View>: View {
    @Query private var books: [CatalogBook]
    private let content: ([CatalogBook]) -> Content

    init(searchTerm: String, @ViewBuilder content: @escaping ([CatalogBook]) -> Content) {
        self.content = content
        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        if term.isEmpty {
            _books = Query(sort: \CatalogBook.addedAt, order: .reverse)
        } else if ISBNFormatter.isBarcodeQuery(term) {
            // Barkod/ISBN araması: kayıtlı ISBN tireli/boşluklu olabileceğinden
            // veritabanı ön süzmesi eşleşmeyi kaçırır. Tüm katalog çekilir;
            // süzmeyi, tireleri ayıklayarak karşılaştıran bellek içi filtre yapar.
            _books = Query(sort: \CatalogBook.addedAt, order: .reverse)
        } else {
            // Veritabanı seviyesinde ön süzme (büyük/küçük harf duyarsız)
            _books = Query(
                filter: Self.searchPredicate(term: term),
                sort: \CatalogBook.addedAt,
                order: .reverse
            )
        }
    }

    /// Ad, yazar ve ISBN üzerinde arama koşulu.
    ///
    /// DİKKAT: Buradaki ifadelerin tamamı SwiftData tarafından SQL'e çevrilebilir
    /// olmalı. ISBN isteğe bağlı olduğu için `(book.isbn ?? "")` YAZILMAZ; SwiftData
    /// bunu çeviremeyip uygulamayı çökertiyor ("unimplemented SQL generation for
    /// predicate: TERNARY(...) CONTAINS"). İsteğe bağlı zincirleme kullanılır;
    /// ISBN yoksa koşul false olur.
    nonisolated static func searchPredicate(term: String) -> Predicate<CatalogBook> {
        // `localizedStandardContains` noktasız ı'yı i saymaz ("kizi" → "Kızı" kaçar) ve
        // kategori/yayınevini görmez; aksansız `searchKey` ikisini de karşılar. Anahtar
        // boşsa (yalnız noktalama/emoji) eklenmez: boş dize her kayıtla eşleşirdi.
        let key = CatalogMatcher.normalize(term)
        guard !key.isEmpty else {
            return #Predicate<CatalogBook> { book in
                book.title.localizedStandardContains(term)
                    || book.author.localizedStandardContains(term)
                    || (book.isbn?.localizedStandardContains(term) ?? false)
            }
        }
        // Çok kelimeli sorguda kelimeler ayrı ayrı aranır (sıra ve bitişiklik şartı yok)
        let kelimeler = CatalogMatcher.aramaKelimeleri(key)
        switch kelimeler.count {
        case 2:
            let a = kelimeler[0], b = kelimeler[1]
            return #Predicate<CatalogBook> { book in
                book.title.localizedStandardContains(term)
                    || book.author.localizedStandardContains(term)
                    || (book.isbn?.localizedStandardContains(term) ?? false)
                    || ((book.searchKey?.contains(a) ?? false) && (book.searchKey?.contains(b) ?? false))
            }
        case 3:
            let a = kelimeler[0], b = kelimeler[1], c = kelimeler[2]
            return #Predicate<CatalogBook> { book in
                book.title.localizedStandardContains(term)
                    || book.author.localizedStandardContains(term)
                    || (book.isbn?.localizedStandardContains(term) ?? false)
                    || ((book.searchKey?.contains(a) ?? false) && (book.searchKey?.contains(b) ?? false)
                        && (book.searchKey?.contains(c) ?? false))
            }
        default:
            // Tek kelime ("seker seker" gibi yinelenen yazım da tek kelimedir)
            let tek = kelimeler.first ?? key
            return #Predicate<CatalogBook> { book in
                book.title.localizedStandardContains(term)
                    || book.author.localizedStandardContains(term)
                    || (book.isbn?.localizedStandardContains(term) ?? false)
                    || (book.searchKey?.contains(tek) ?? false)
            }
        }
    }

    var body: some View {
        content(books)
    }
}

struct ContentView: View {
    @Environment(\.dismiss) var dismiss
    var presentation: ContentPresentation = .add
    var initialTool: KatalogAraci? = nil
    @State var initialToolHandled = false
    @State var catalogLease: ActiveCatalogLease?
    @State var scanSession: ScanSession?
    @State var recentScanSessions: [ScanSession] = []
    @State var resumedShelfSessionID: UUID?
    @Environment(\.modelContext) var modelContext
    @Query(sort: \CatalogBook.addedAt, order: .reverse) var catalogBooks: [CatalogBook]
    @Query var catalogLoans: [ActiveLoan]
    @State var singleBookPhotos: [PhotosPickerItem] = []
    @State var selectedPhotos: [PhotosPickerItem] = []
    @State var retainedPhotoSelections: [UUID: PhotosPickerItem] = [:]
    /// "Raf Karesi": tek fotoğrafta yan yana dizilmiş birçok kitap
    @State var shelfPhotos: [PhotosPickerItem] = []
    @State var pendingShelfPhotos: [PhotosPickerItem] = []
    @State var isShowingShelfPhotoChoice = false
    @State var shelfPhotoRelation: ScanPhotoRelation = .overlapping
    @State var draft: BookDraft?
    @State var queuedDrafts: [BookDraft] = []
    @State var scanProgress = 0
    @State var scanTotal = 0
    @State var isShowingPDFImporter = false
    @State var isRecognizing = false
    @State var isSeedImportRunning = false
    @State var recognitionError: String?
    @State var searchText = ""
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @FocusState var isSearchFieldFocused: Bool
    /// Aramada her harfte yeniden süzmemek için gecikmeli (debounce) kopya
    @State var activeSearchText = ""
    @State var isCancelRequested = false
    @State var isShowingRestoreImporter = false
    @State var isTorchOn = false
    @State var bulkUndoSnapshot: [Book] = []
    @State var bulkUndoAfterSnapshots: [UUID: Book] = [:]
    @State var bulkUndoDeletedIDs: Set<UUID> = []
    @State var isShowingSettings = false
    @State var isShowingToolsPanel = false
    // Üst panel (Kitap ekle kartları) ölçümleri: büyük yazı boyutunda panel ekrana sığmazsa
    // arama çubuğu ve sekme çubuğuyla üst üste binmesin diye yüksekliği sınırlanır.
    @State var headerContentHeight: CGFloat = 0
    @State var availableHeight: CGFloat = 0
    @State var isShowingVoiceEntry = false
    @State var isShowingLiveCover = false
    let derinBaglanti = DerinBaglanti.shared
    @State var isShowingShelfScan = false
    @State var savedViews: [SavedView] = SavedViewStore.all()
    @State var isShowingSaveViewPrompt = false
    @State var newViewName = ""
    @State var isExportingArchive = false
    @State var isShowingArchiveImporter = false
    @State var isShowingArchiveChoice = false
    @State var archiveImportSourceData = Data()
    @State var isReadingArchive = false
    /// Dışa aktarma verileri yalnızca kullanıcı istediğinde üretilir.
    /// (Eskiden her ekran yenilemesinde 2.500+ kitap paketleniyor ve uygulama kilitleniyordu.)
    /// Akışla yazılmış, kullanıcı hedefi seçene kadar bekleyen geçici tam arşiv (belleğe alınmaz).
    @State var archiveFileURL: URL?
    @State var jsonYedekOnizlemesi: ArchiveImportCoordinator.Preparation?
    @State var jsonYedekVerisi = Data()
    @State var excelData = Data()
    @State var isPreparingExport = false
    @State var isExportingExcel = false
    @State var isShowingDocumentScanner = false
    @State var isShowingBarcodeScanner = false
    @State var isShowingAmazonLookup = false
    @State var isShowingKitapyurduLookup = false
    @State var isShowingStatistics = false
    @State var isShowingReportCenter = false
    @State var catalogLayout: CatalogLayout = .list
    @State var catalogFilter: CatalogFilter = .all
    @State var catalogSort: CatalogSort = .dateAdded
    @State var isSelecting = false
    @State var selectedBookIDs = Set<UUID>()
    @State var isShowingBulkAssign = false
    @State var isShowingDuplicateCleaner = false
    @State var isShowingInventory = false
    @State var isShowingCSVImporter = false
    @State var bulkMessage: String?
    /// Tarayıcı oturumunun kipi, sayacı, günlüğü ve kalıcı ISBN kuyruğu (BarkodTarama.swift).
    @State var tarama = BarkodTaramaDenetleyicisi()
    @State var kameraIzniUyarisi = false
    @State var bitmisOturumOzeti: (sessions: Int, bytes: Int64) = (0, 0)
    @State var bitmisOturumOnayi = false
    /// Uzun fotoğraf/PDF okuma işinin görevi: "Durdur" bayrağın yanında görevi de iptal eder (Vision istekleri durur).
    @State var islemGorevi: Task<Void, Never>?
    /// Künye aramasının görevi: "İptal, elle gir" bunu iptal eder.
    @State var kunyeGorevi: Task<Void, Never>?
    @State var scanSessionKaydiGorevi: Task<Void, Never>?
    @State var depoSorusu: DepoSorusu?
    /// Okunmayı bekleyen "Kuyruk kaydedilemedi" uyarısı: bellekteki kuyruk diske yazılamadığında görünür.
    @State var kuyrukKayitHatasi: String?
    @AppStorage("barcodePhotoCapture") var capturesBarcodePhoto = true
    @State var batchDrafts: [BookDraft] = []
    @State var isShowingBatchReview = false
    @State var isShowingScanSetup = false
    @State var scanAssignment = BulkAssignment()
    @State var autoSaveScans = true
    @State var lastScanAction: ScanAction?
    /// Tekli taramada katalogda zaten olan kitap: adet sormadan artmaz, kullanıcıya sorulur.
    @State var katalogdakiKitap: KatalogdakiKitapOnayi?
    /// Tarayıcı kapanırken bulunan katalogdaki kitap: soru, kapanış bitince (`onDismiss`) sorulur
    @State var bekleyenKatalogOnayi: KatalogdakiKitapOnayi?
    /// Kayıttan sonra alttaki "eklendi · Geri al · Sonrakini okut" şeridi
    @State var sonEkleme: SonEklemeSeridi?
    /// Sonradan düzenlenmiş yeni kaydın geri alınması (kalıcı silme) için onay
    @State var degisenEklemeOnayi: SonEklemeSeridi?
    /// Şeridin geri alacağı işlem; son işlem değişirse (ör. seri taramada kuyruğa alma) şerit kalkar
    @State var sonEklemeEylemi: ScanAction?
    /// Tekli tarayıcıda kitap barkodu olmadığı için yok sayılan son kod (tarayıcı açık kalır)
    @State var reddedilenBarkod: String?
    @State var elleISBN = ""
    @State var csvPreviewBooks: [Book] = []
    @State var isShowingCSVPreview = false
    @State var isShowingAmazonFollowUp = false
    @State var lastSessionInserted: [UUID] = []
    @State var lastSessionMerged: [UUID: Int] = [:]
    @State var bulkPendingBooks: [Book] = []
    @State var lastSavedOperationID: UUID?
    @State var lastScanOperationID: UUID?
    @State var sourceSession: ScanSession?
    @State var showingSessionUndoConfirmation = false
    @State var showingBulkDeleteConfirmation = false
    @State var pendingRestoredTaslaklar: [KuyrukTaslagi] = []
    @State var isShowingQueueRestorePrompt = false
    @State var isShowingShelfAssignSetup = false
    @State var lastShelfAssignment: (bookID: UUID, previousShelf: String?, previousCabinet: String?)?
    @State var withdrawTargetBook: CatalogBook?
    @State var withdrawReasonText = ""
    @State var isShowingAccessionRegister = false
    @State var isExportingLabels = false
    @State var labelPDFData = Data()
    @State var isPreparingLabels = false
    @State var isShowingDataQuality = false
    @State var isShowingFieldMerge = false
    @State var isShowingBulkFindReplace = false
    @State var shareTargetBook: Book?
    @State var isShowingStudents = false
    @State var isShowingClassLoan = false
    @State var isShowingTextbookDistribution = false
    @State var isShowingReadingChampions = false
    @State var isShowingUsageReport = false
    @State var isShowingStudentCards = false
    @State var isShowingDepotSetup = false
    @State var depotLocation = ""
    @State var depotCabinet = ""
    @State var depotShelf = ""
    @State var depotCategory = ""
    @State var depotIndex: [String: CatalogBook] = [:]
    @State var isShowingEnrichPrompt = false
    @State var isEnriching = false
    @State var enrichmentDone = 0
    @State var isSerialWorkerRunning = false
    @State var loanTargetBook: CatalogBook?
    @State var pendingBulkPhotos: [PhotosPickerItem] = []
    @State var isShowingBulkPhotoChoice = false
    @Environment(\.scenePhase) var scenePhase

    /// Veritabanından gelen (arama ile ön süzülmüş) kayıtlar
    @State var queriedBooks: [CatalogBook] = []

    var isSerialScan: Bool { tarama.kip.seri }
    var isDepotScan: Bool { tarama.kip.depo }
    var isShelfAssignMode: Bool { tarama.kip.rafAtama }
    var isSearchScan: Bool { tarama.kip.arama }
    var serialScanCount: Int {
        get { tarama.okunan }
        nonmutating set { tarama.okunan = newValue }
    }
    var serialLog: [String] { tarama.gunluk }

    var filteredBooks: [CatalogBook] {
        catalogSort.apply(unsortedFilteredBooks)
    }

    var unsortedFilteredBooks: [CatalogBook] {
        // Türkçe duyarsız arama: "Yuzbasinin kizi" yazınca "Yüzbaşının Kızı" bulunur.
        // Arama metni yazma bitene kadar beklenir (aşağıdaki debounce görevi).
        let query = CatalogMatcher.normalize(activeSearchText)
        // Arama varsa veritabanının ön süzdüğü küme, yoksa tüm katalog
        let source = activeSearchText.isEmpty ? catalogBooks : queriedBooks

        return source.filter { book in
            let matchesSearch = query.isEmpty
                || CatalogMatcher.normalize(book.title).contains(query)
                || CatalogMatcher.normalize(book.author).contains(query)
                || CatalogMatcher.normalize(book.isbn ?? "").contains(query)
                || CatalogMatcher.normalize(book.category ?? "").contains(query)
                || CatalogMatcher.normalize(book.location ?? "").contains(query)
                || CatalogMatcher.normalize(book.shelf ?? "").contains(query)
                || CatalogMatcher.normalize(book.cabinet ?? "").contains(query)
                || CatalogMatcher.normalize(book.loanedTo ?? "").contains(query)

            let matchesFilter: Bool
            switch catalogFilter {
            case .all:
                matchesFilter = true
            case .incomplete:
                matchesFilter = book.isbn?.isEmpty ?? true
                    || book.author.isEmpty
                    || book.publisher?.isEmpty ?? true
                    || book.coverData == nil
            case .unread:
                matchesFilter = book.readingStatus == "Okunacak"
            case .reading:
                matchesFilter = book.readingStatus == "Okunuyor"
            case .read:
                matchesFilter = book.readingStatus == "Okundu"
            case .loaned:
                matchesFilter = !(book.loanedTo ?? "").isEmpty || catalogLoans.contains { $0.bookID == book.id }
            case .withdrawn:
                matchesFilter = book.isWithdrawn
            }
            // Düşülen kayıtlar, özellikle "Düşülenler" filtresi seçilmedikçe hiçbir
            // görünümde listelenmez (resmî kayıttan düşme mantığı).
            let visibilityGuard = catalogFilter == .withdrawn || !book.isWithdrawn
            return matchesSearch && matchesFilter && visibilityGuard
        }
    }

    var body: some View {
        NavigationStack {
            systemLayer(sheetLayer(baseContent))
        }
        .sheet(item: $sourceSession) { session in
            NavigationStack {
                ScrollView {
                    ForEach(Array((session.sourceImages ?? []).enumerated()), id: \.offset) { index, data in
                        if let image = UIImage(data: data) {
                            ScanSourcePhotoView(image: image, items: sourcePhotoItems(in: session, photoIndex: index)) { id, box in
                                try confirmSourceBox(box, bookID: id, session: session)
                            }.padding()
                            Text("Fotoğraf \(index + 1)").font(.caption)
                            if let error = session.photoErrors?[index] { Text(error).font(.footnote).foregroundStyle(.red) }
                        }
                    }
                }.padding().navigationTitle("Tarama Kaynakları")
                .toolbar { Button("Kapat") { sourceSession = nil } }
            }
        }
        .confirmationDialog("\(lastSessionCount) ekleme geri alınsın mı?", isPresented: $showingSessionUndoConfirmation, titleVisibility: .visible) {
            Button("Eklemeleri Geri Al", role: .destructive) { undoLastSession() }
            Button("Vazgeç", role: .cancel) { }
        }
        .confirmationDialog("\(selectedBookIDs.count) kitap çöp kutusuna taşınsın mı?",
                            isPresented: $showingBulkDeleteConfirmation, titleVisibility: .visible) {
            Button("Çöp Kutusuna Taşı", role: .destructive) { bulkDeleteSelected() }
            Button("Vazgeç", role: .cancel) { }
        }
        // Tekli taramada katalogdaki kitap: sessiz +1 yok, kullanıcı seçer
        .confirmationDialog(katalogdakiKitap?.baslik ?? "", isPresented: katalogdakiKitapBinding,
                            titleVisibility: .visible, presenting: katalogdakiKitap) { onay in
            if onay.nushaEklenebilir {
                Button("Nüsha ekle (+1)") { nushaEkleOnayla(onay) }
            }
            // Yalnız düşülmüş kayıt varsa yeniden edinilen kitap yeni kayıt olarak eklenebilir
            if onay.yeniKayitAcilabilir {
                Button("Yeni kayıt olarak ekle") { kunyeyleFormuAc(isbn: onay.isbn, backPhoto: onay.arkaKapak) }
            }
            Button("Kitabı aç") { katalogdakiKitabiAc(onay) }
            Button("Vazgeç", role: .cancel) { }
        } message: { onay in
            Text(onay.mesaj)
        }
        // Şeritteki "Geri al" yeni kaydı kalıcı siler: eklendikten sonra düzenlendiyse önce sorulur
        .confirmationDialog("“\(degisenEklemeOnayi?.kitapAdi ?? "")” eklendikten sonra değiştirildi",
                            isPresented: degisenEklemeBinding, titleVisibility: .visible, presenting: degisenEklemeOnayi) { serit in
            Button("Kaydı Sil ve Geri Al", role: .destructive) { sonEklemeyiGeriAl(serit, degisiklikOnaylandi: true) }
            Button("Vazgeç", role: .cancel) { }
        } message: { _ in
            Text("Geri alırsanız kayıt ve sonradan girilen bilgiler (kapak, raf, not…) kalıcı olarak silinir.")
        }
    }

    var katalogdakiKitapBinding: Binding<Bool> {
        Binding(get: { katalogdakiKitap != nil }, set: { if !$0 { katalogdakiKitap = nil } })
    }

    var degisenEklemeBinding: Binding<Bool> {
        Binding(get: { degisenEklemeOnayi != nil }, set: { if !$0 { degisenEklemeOnayi = nil } })
    }

    var baseContent: some View {
            Group {
            if presentation == .add {
                ScrollView {
                    VStack(spacing: 16) {
                        importActions
                            .background {
                                CanliGradyan().opacity(0.35)
                            }
                        scanSessionsPanel
                    }
                    .padding(.bottom, 16)
                }
                .okunurAltKaydirmaKenari()
                .scrollBounceBehavior(.basedOnSize)
            } else {
            VStack(spacing: 0) {
                // Panel ekrana sığmıyorsa (büyük Dinamik Yazı) kendi içinde kaydırılır ve
                // yüksekliği ekranın %60'ı ile sınırlanır; böylece liste görünür kalır.
                ScrollView {
                    importActions
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerContentHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: headerHeight)
                // Canlı renkli zemin (okunurluk için yarı saydam); kartlar malzeme üzerinde
                .background {
                    CanliGradyan()
                        .opacity(0.35)
                        .ignoresSafeArea(edges: .top)
                }

                CatalogQueryView(searchTerm: activeSearchText) { books in
                    // Kimlik listesine göre karşılaştırma: yalnızca SAYI değil, içerik
                    // değiştiğinde de (aynı sayıda farklı sonuç) liste tazelenir.
                    Color.clear
                        .frame(height: 0)
                        .onAppear { queriedBooks = books }
                        .onChange(of: books.map(\.id)) { queriedBooks = books }
                }

                Group {
                    if catalogBooks.isEmpty {
                        BosDurum(baslik: "Kitaplığınız boş", aciklama: "Yukarıdaki kartlarla ekleyin.", ikon: "books.vertical")
                    } else {
                        bookList
                    }
                }
            }
            }
            }
            .task {
                guard acceptsActiveCatalogResult() else { return }
                // JSON'daki eski fotoğraflar dosyalara taşınır, sahipsiz fotoğraf klasörleri silinir (oturum silinmez)
                await withCheckedContinuation { devam in
                    ScanSessionStore.runMaintenance { _, _ in devam.resume() }
                }
                guard acceptsActiveCatalogResult() else { return }
                refreshScanSessions()
                bitmisOturumOzeti = ScanSessionStore.finishedUsage()
                yarimKalanISBNleriSurdur()
                if !initialToolHandled, let initialTool {
                    initialToolHandled = true
                    handleToolAction(initialTool)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { availableHeight = $0 }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    if let kuyrukKayitHatasi { kuyrukHataSeridi(kuyrukKayitHatasi) }
                    if let sonEkleme { sonEklemeSeridi(sonEkleme) }
                }
            }
            // Başka bir kayıt ya da işlem son işlem olduysa şeridin "Geri al"ı artık bu kitaba ait değil
            .onChange(of: lastScanOperationID) { _, yeni in
                if let yeni, let seritteki = sonEkleme?.islemKimligi, yeni != seritteki { sonEkleme = nil }
            }
            .onChange(of: lastScanAction) { _, yeni in
                if sonEkleme?.geriAlinabilir == true, yeni != sonEklemeEylemi { sonEkleme = nil }
            }
            // Ekleme oturumu değiştiyse (yeni ekleme, "Kontrole Devam Et", oturum geri alma) şerit eski
            // oturumun kaydını gösterir; geri alma başka oturumun günlüğünü bozmasın diye kalkar.
            .onChange(of: scanSession?.id) { _, yeni in
                if let serit = sonEkleme, serit.oturumKimligi != yeni { sonEkleme = nil }
            }
            // Sayfadan çıkılınca (ör. Kitaplar'da düzenlemeye gidince) "Geri al" süresiz açık kalmaz
            .onDisappear {
                if presentation == .add { sonEkleme = nil }
            }
            .navigationTitle(presentation == .add ? "Kitap Ekle" : "Katalog Yönetimi")
            .navigationBarTitleDisplayMode(.inline)
            .kenardanSekmeKaydir()
            // Kitap eklendiğinde başarı titreşimi
            .sensoryFeedback(trigger: catalogBooks.count) { eski, yeni in yeni > eski ? .success : nil }
            // Arama alanı gezinti çubuğu çekmecesi yerine listenin üstünde (`catalogSearchField`):
            // çekmece kaydırılmayan başlığın üstüne biniyordu (iOS 26).
            .toolbar {
                if presentation == .management {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Kapat") { persistScanSessionNow(); dismiss() }
                            .disabled(isRecognizing || isEnriching)
                    }
                }
                ToolbarItemGroup(placement: .automatic) {
                    // Eski 35 maddelik açılır menü yerine kartlı, aranabilir araç paneli (AraclarPaneli.swift)
                    Button {
                        if presentation == .add { derinBaglanti.hedefSekme = .yonetim }
                        else { isShowingToolsPanel = true }
                    } label: {
                        Label(presentation == .add ? "Yönetim" : "Araçlar", systemImage: "square.grid.2x2.fill")
                    }
                    .accessibilityHint(presentation == .add
                        ? "Yönetim sekmesine geçer"
                        : "Görünüm, ödünç, rapor, bakım ve yedek araçlarını açar")

                    if presentation == .management {
                    Button(isSelecting ? "Bitti" : "Seç") {
                        withAnimation {
                            isSelecting.toggle()
                            if !isSelecting {
                                selectedBookIDs.removeAll()
                            }
                        }
                    }
                    .tint(.primary)
                    .disabled(catalogBooks.isEmpty)
                    }
                }

                if isSelecting {
                    ToolbarItemGroup(placement: bulkBarPlacement) {
                        Text("\(selectedBookIDs.count) seçili")
                            .font(.subheadline)

                        Spacer()

                        Menu {
                            Button("Okunacak") { bulkSetStatus("Okunacak") }
                            Button("Okunuyor") { bulkSetStatus("Okunuyor") }
                            Button("Okundu") { bulkSetStatus("Okundu") }
                        } label: {
                            Label("Durum", systemImage: "bookmark")
                        }
                        .disabled(selectedBookIDs.isEmpty)

                        Button {
                            isShowingBulkAssign = true
                        } label: {
                            Label("Konum/Kategori Ata", systemImage: "tray.full")
                        }
                        .disabled(selectedBookIDs.isEmpty)

                        Button {
                            printSpineLabels()
                        } label: {
                            Label(
                                isPreparingLabels ? "Hazırlanıyor…" : "Sırt Etiketi Bas",
                                systemImage: "tag"
                            )
                        }
                        .disabled(selectedBookIDs.isEmpty || isPreparingLabels)

                        Button {
                            isShowingBulkFindReplace = true
                        } label: {
                            Label("Bul-Değiştir", systemImage: "text.magnifyingglass")
                        }
                        .disabled(selectedBookIDs.isEmpty)

                        Button(role: .destructive) {
                            showingBulkDeleteConfirmation = true
                        } label: {
                            Label("Sil", systemImage: "trash")
                        }
                        .disabled(selectedBookIDs.isEmpty)
                    }
                }
            }
            .overlay(alignment: .top) {
                if isRecognizing {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(progressOverlayText)
                            .font(.subheadline.weight(.semibold))

                        if scanTotal > 1 {
                            Button {
                                isCancelRequested = true
                                islemGorevi?.cancel()
                            } label: {
                                Label("Durdur", systemImage: "stop.circle")
                                    .labelStyle(.iconOnly)
                                    .font(.title3)
                            }
                            .tint(KitapTema.vurgu)
                            .accessibilityLabel("İşlemi durdur")
                        }
                        if kunyeGorevi != nil {
                            Button {
                                kunyeGorevi?.cancel()
                            } label: {
                                Label("İptal, elle gir", systemImage: "square.and.pencil")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .tint(KitapTema.vurgu)
                            .accessibilityIdentifier("add.lookup.cancel")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: .capsule)
                    .shadow(radius: 4)
                    .padding(.top, 8)
                }
            }
    }

    func sheetLayer(_ content: some View) -> some View {
        content
            .sheet(item: $draft, onDismiss: presentNextDraft) { draft in
                BookEditorView(validating: draft, save: { book in
                    // Var olan kitap düzenlendiyse demirbaş/ödünç/düşülme bilgisi korunur
                    if let existing = catalogBooks.first(where: { $0.id == book.id }) {
                        return saveBook(existing.preservingRecordFields(of: book))
                    } else {
                        let outcome = saveBook(book)
                        recordSession(outcome)
                        // Görünür onay: altta "eklendi · Geri al · Sonrakini okut" şeridi
                        sonEklemeyiGoster(outcome, kitapAdi: book.title)
                        return outcome
                    }
                }, onDraftChange: { updated in
                    self.draft = updated
                    persistScanSession()
                }, initialMergeDecision: scanSession?.saveDecisions?[draft.snapshot.id] ?? .automatic,
                   onMergeDecision: { decision in
                    if scanSession == nil { beginAddSession() }
                    if var session = scanSession {
                        var decisions = session.saveDecisions ?? [:]
                        decisions[draft.snapshot.id] = decision
                        session.saveDecisions = decisions
                        scanSession = session
                    }
                    persistScanSession()
                }, sonKonumuHatirla: true)
            }
            .sheet(isPresented: $isShowingReportCenter) {
                KapatilabilirSayfa { RaporMerkezi() }
            }
            .sheet(isPresented: $isShowingStatistics) {
                CatalogStatisticsView(stats: catalogBooks.map {
                    BookStatSummary(
                        category: $0.category,
                        isbn: $0.isbn,
                        author: $0.author,
                        publisher: $0.publisher,
                        hasCover: $0.coverData != nil,
                        quantity: $0.quantity,
                        readingStatus: $0.readingStatus
                    )
                })
            }
            .sheet(isPresented: $isShowingAmazonLookup) {
                AmazonLookupView { newDraft in
                    draft = newDraft
                }
            }
            .sheet(isPresented: $isShowingKitapyurduLookup) {
                KitapyurduLookupView { newDraft in
                    draft = newDraft
                }
            }
            .sheet(isPresented: $isShowingBulkAssign) {
                BulkAssignSheet(count: selectedBookIDs.count) { assignment in
                    bulkAssign(assignment)
                }
            }
            .sheet(isPresented: $isShowingBulkFindReplace) {
                BulkFindReplaceSheet(count: selectedBookIDs.count, books: selectedBooks().map(\.book)) { field, find, replace in
                    try bulkFindReplace(field: field, find: find, replace: replace)
                }
            }
            .sheet(isPresented: $isShowingDuplicateCleaner) {
                DuplicateCleanerView()
            }
            .sheet(isPresented: $isShowingInventory) {
                InventoryCountView()
            }
            .sheet(isPresented: $isShowingAccessionRegister) {
                AccessionRegisterView(books: catalogBooks)
            }
            .sheet(isPresented: $isShowingDataQuality) {
                DataQualityDashboardView()
            }
            .sheet(isPresented: $isShowingFieldMerge) {
                FieldMergeView()
            }
            .sheet(item: $shareTargetBook) { book in
                BookShareSheet(book: book)
            }
            .sheet(isPresented: $isShowingStudents) {
                StudentsView()
            }
            .sheet(isPresented: $isShowingClassLoan) {
                ClassLoanView()
            }
            .sheet(isPresented: $isShowingTextbookDistribution) {
                TextbookDistributionView()
            }
            .sheet(isPresented: $isShowingReadingChampions) {
                ReadingChampionsView()
            }
            .sheet(isPresented: $isShowingUsageReport) {
                UsageReportView()
            }
            .sheet(isPresented: $isShowingStudentCards) {
                StudentCardsView()
            }
            .fileExporter(
                isPresented: $isExportingLabels,
                document: PDFDocumentFile(data: labelPDFData),
                contentType: .pdf,
                defaultFilename: "Sirt-Etiketleri"
            ) { _ in }
            .sheet(isPresented: $isShowingVoiceEntry) {
                KapatilabilirSayfa { VoiceBookEntryPage() }
            }
            .fullScreenCover(isPresented: $isShowingLiveCover) {
                CanliKapakTaramaSayfasi { foto in
                    Task { await recognizeSingleCover(foto) }
                }
            }
            // Kitaplar'da bulunamayan ISBN: künye aranıp forma gelir. Yönetim'in katalog sayfası dinlemez.
            .onChange(of: derinBaglanti.bekleyenISBN, initial: true) { _, isbn in
                guard presentation == .add, let isbn else { return }
                derinBaglanti.bekleyenISBN = nil
                Task {
                    // Sekme geçişi bitsin, sonra sayfa açılsın
                    try? await Task.sleep(for: .milliseconds(350))
                    guard acceptsActiveCatalogResult() else { return }
                    // Tekli barkod okutmasıyla aynı yol: künye aranır, form açılır; kayıt kullanıcıyla olur.
                    // Bu arada katalogda belirdiyse (ya da düşülmüş kayıtsa) adet sessizce artmaz; onay sorulur.
                    handleScannedISBN(isbn)
                }
            }
            // Ana Sayfa kısayolları, Kitaplar'daki "+" ve kitapbul://ekle/… bağlantısından gelen ekleme isteği.
            // Yönetim'in katalog sayfası dinlemez: işi yalnız Ekle sayfası tüketir.
            .onChange(of: derinBaglanti.bekleyenEylem, initial: true) { _, eylem in
                guard presentation == .add, let eylem else { return }
                derinBaglanti.bekleyenEylem = nil
                Task {
                    // Sekme geçişi bitsin, sonra sayfa açılsın
                    try? await Task.sleep(for: .milliseconds(350))
                    startQuickAction(eylem)
                }
            }
            .sheet(isPresented: $isShowingShelfScan) {
                KapatilabilirSayfa { ShelfScanPage(sessionID: resumedShelfSessionID) }
            }
            .sheet(isPresented: $isShowingToolsPanel) {
                KatalogAraclarPaneli(
                    layout: $catalogLayout,
                    filter: $catalogFilter,
                    sort: $catalogSort,
                    savedViews: savedViews,
                    pendingQueueCount: batchDrafts.count,
                    undoSessionCount: lastSessionCount,
                    bulkUndoCount: bulkUndoSnapshot.count,
                    isBusy: isRecognizing || isPreparingExport,
                    catalogEmpty: catalogBooks.isEmpty,
                    onAction: handleToolAction
                )
                .presentationDetents([.large])
                }
            .sheet(isPresented: $isShowingSettings) {
                // Tanıtımın son düğmesi Ekle sekmesine geçer: Katalog Yönetimi'nden açılan Ayarlar
                // kapanırken bu sayfa da kapanır; yoksa Ekle, Katalog Yönetimi'nin arkasında kalırdı.
                SettingsView()
                    .environment(\.ayarlariKapat, presentation == .management ? { persistScanSessionNow(); dismiss() } : nil)
            }
            .alert("Görünümü Kaydet", isPresented: $isShowingSaveViewPrompt) {
                TextField("Ad (örn. B dolabı eksikleri)", text: $newViewName)
                Button("Kaydet") { saveCurrentView() }
                Button("Vazgeç", role: .cancel) { newViewName = "" }
            } message: {
                Text("Şu anki görünüm, filtre, sıralama ve arama birlikte kaydedilir.")
            }
            .alert("Kayıttan Düşür", isPresented: withdrawPromptBinding) {
                TextField("Gerekçe (örn. kayıp, yıpranmış)", text: $withdrawReasonText)
                Button("Düşür", role: .destructive) {
                    if let book = withdrawTargetBook {
                        withdrawBook(book, reason: withdrawReasonText)
                    }
                    withdrawReasonText = ""
                    withdrawTargetBook = nil
                }
                Button("Vazgeç", role: .cancel) {
                    withdrawReasonText = ""
                    withdrawTargetBook = nil
                }
            } message: {
                Text("Kitap kalıcı silinmez; \"Düşülenler\" filtresinden geri getirilebilir.")
            }
            // Kitaplar'daki ayrıntıyla aynı form: kimlikli öğrenci/üye seçimi, süre sınıf kuralından.
            // Form açıkken katalog değişmiş olabilir: etkin katalog kayıt anında yeniden denetlenir.
            .sheet(item: $loanTargetBook) { book in
                KitapOduncFormu(kitap: book, kayitOncesi: { try requireActiveCatalog() })
            }
#if os(iOS)
            .sheet(isPresented: $isShowingScanSetup) {
                ScanSetupSheet { assignment, autoSave in
                    beginSerialScan(assignment: assignment, autoSave: autoSave)
                }
            }
            .sheet(isPresented: $isShowingDepotSetup) {
                DepotSetupSheet { location, cabinet, shelf, category in
                    beginDepotScan(location: location, cabinet: cabinet, shelf: shelf, category: category)
                }
            }
            .sheet(isPresented: $isShowingShelfAssignSetup) {
                ShelfAssignSetupSheet { cabinet, shelf in
                    beginShelfAssign(cabinet: cabinet, shelf: shelf)
                }
            }
#endif
            .alert("Depo taraması bitti", isPresented: $isShowingEnrichPrompt) {
                Button("Doldurmaya Başla") { toggleEnrichment() }
                Button("Sonra", role: .cancel) { }
            } message: {
                Text("\(enrichmentPendingCount) kitap bilgi bekliyor. Kitap adı, yazar ve kapaklar Amazon'dan sırayla doldurulsun mu? (İstediğin an duraklatabilirsin; kaldığı yerden devam eder.)")
            }
            .sheet(isPresented: $isShowingBatchReview) {
                BatchReviewView(drafts: $batchDrafts, onEditionDecision: { id, decision in
                    if scanSession == nil { beginAddSession() }
                    if var session = scanSession {
                        var decisions = session.saveDecisions ?? [:]
                        decisions[id] = decision
                        session.saveDecisions = decisions
                        scanSession = session
                        persistScanSession()
                    }
                }, editionDecision: { id in scanSession?.saveDecisions?[id] ?? .automatic }) {
                    let sonuc = saveBatchDrafts()
                    // Kuyruk boşaldıysa sayfa kapanır, sonuç Ekle'de söylenir; kalan varsa sayfada, listenin üstünde
                    if batchDrafts.isEmpty { bulkMessage = sonuc }
                    return sonuc
                }
            }
            .sheet(isPresented: $isShowingCSVPreview) {
                CSVPreviewView(books: csvPreviewBooks) {
                    importPreviewedCSV()
                }
            }
    }

    func systemLayer(_ content: some View) -> some View {
        content
            .alert("İçe aktarma tamamlandı", isPresented: $isShowingAmazonFollowUp) {
                Button("Tamamla") { bulkCompleteFromAmazon() }
                Button("Şimdi Değil", role: .cancel) { }
            } message: {
                Text("ISBN'i olan eksik kayıtlar Amazon'dan otomatik tamamlansın mı?")
            }
            .alert("Yarım kalan tarama kuyruğu", isPresented: $isShowingQueueRestorePrompt) {
                Button("Kuyruğu Aç") {
                    batchDrafts = pendingRestoredTaslaklar.map(\.draft)
                    pendingRestoredTaslaklar = []
                    isShowingBatchReview = true
                }
                Button("Sil", role: .destructive) {
                    guard acceptsActiveCatalogResult() else { return }
                    pendingRestoredTaslaklar = []
                    PendingQueueStore.clear()
                }
            } message: {
                Text("Önceki oturumdan \(pendingRestoredTaslaklar.count) taranmış kitap bulundu. Onaylamak için kuyruğu açın.")
            }
            .onChange(of: batchDrafts.count) {
                persistPendingQueue()
            }
            .modifier(KameraIzniUyarisi(goster: $kameraIzniUyarisi))
            .onChange(of: scenePhase) { _, phase in
                // Uygulama arka plana giderken her şey güvenceye alınır:
                // veritabanı, bekleyen kuyruk ve tam yedek
                if phase == .background {
                    guard acceptsActiveCatalogResult() else { return }
                    try? modelContext.save()
                    persistPendingQueue(hemen: true)
                    // Süreç askıya alınmadan arka plan yazmaları diske insin
                    ScanSessionStore.flush()
                    CatalogBackup.saveLight(catalogBooks, force: true)
                }
            }
            .alert("Bilgi", isPresented: bulkMessageBinding) {
                Button("Tamam", role: .cancel) { }
            } message: {
                Text(bulkMessage ?? "")
            }
            .fileImporter(
                isPresented: $isShowingCSVImporter,
                allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                processCSVImport(result)
            }
            .fileImporter(
                isPresented: $isShowingRestoreImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                restoreFromBackup(result)
            }
            .fileExporter(
                isPresented: $isExportingArchive,
                document: ArchiveFileDocument(url: archiveFileURL),
                contentType: .zip,
                defaultFilename: "KitapBul-Arsiv"
            ) { result in
                // Akışla yazılan geçici arşiv, hedefe kopyalandıktan (ya da vazgeçildikten) sonra silinir
                let kaynak = archiveFileURL
                switch result {
                case .success(let url):
                    guard acceptsActiveCatalogResult(), let kaynak else { return }
                    let access = url.startAccessingSecurityScopedResource()
                    isPreparingExport = true
                    Task { @MainActor in
                        defer {
                            isPreparingExport = false
                            if access { url.stopAccessingSecurityScopedResource() }
                            try? FileManager.default.removeItem(at: kaynak)
                            archiveFileURL = nil
                        }
                        do {
                            let receipt = try await Task.detached(priority: .utility) {
                                try BackupExportVerifier.verify(url: url, expectedURL: kaynak)
                            }.value
                            try requireActiveCatalog()
                            try BackupExportStatusStore.recordSuccess(receipt)
                            bulkMessage = "Tam arşiv seçilen hedefte doğrulandı: \(receipt.books) eser, \(receipt.copies) nüsha. \(receipt.fileName)"
                        } catch {
                            guard acceptsActiveCatalogResult() else { return }
                            try? BackupExportStatusStore.recordFailure(error.localizedDescription)
                            bulkMessage = "Arşiv dosyası kaydedildi, ancak doğrulama veya başarı günlüğü tamamlanamadı: \(error.localizedDescription)"
                        }
                    }
                case .failure(let error):
                    if let kaynak { try? FileManager.default.removeItem(at: kaynak) }
                    archiveFileURL = nil
                    try? BackupExportStatusStore.recordFailure(error.localizedDescription)
                    if (error as NSError).code != NSUserCancelledError {
                        bulkMessage = "Arşiv kaydedilemedi: \(error.localizedDescription)"
                    }
                }
            }
            .fileImporter(
                isPresented: $isShowingArchiveImporter,
                allowedContentTypes: [.zip],
                allowsMultipleSelection: false
            ) { result in
                restoreFromArchive(result)
            }
            .overlay {
                if isReadingArchive {
                    ProgressView("Arşiv dosyası arka planda doğrulanıyor…")
                        .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("archive.input.loading")
                }
            }
            .sheet(isPresented: $isShowingArchiveChoice) {
                ArchiveImportChoiceView(data: archiveImportSourceData, context: modelContext)
            }
            .modifier(JSONYedekGeriYuklemeOnizlemesi(onizleme: $jsonYedekOnizlemesi, veri: jsonYedekVerisi, context: modelContext))
#if os(iOS)
            .fullScreenCover(isPresented: $isShowingBarcodeScanner, onDismiss: tarayiciKapandi) {
                scannerCover
            }
#endif
            .modifier(
                DocumentScannerPresentation(
                    isPresented: $isShowingDocumentScanner,
                    onScan: { pages in
                        islemBaslat { await processScannedPages(pages) }
                    }
                )
            )
            .fileExporter(
                isPresented: $isExportingExcel,
                document: BookExcelDocument(data: excelData),
                contentType: BookExcelDocument.xlsxType,
                defaultFilename: "Kitap Katalogu"
            ) { result in
                if case .failure(let error) = result {
                    recognitionError = error.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $isShowingPDFImporter,
                allowedContentTypes: [.pdf, .jpeg, .png],
                allowsMultipleSelection: true
            ) { result in
                islemBaslat { await processFileImport(result) }
            }
            .alert("İşlem tamamlanamadı", isPresented: recognitionErrorBinding) {
                Button("Tamam", role: .cancel) { }
            } message: {
                Text(recognitionError ?? "Bilinmeyen bir hata oluştu.")
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                      let uuid = UUID(uuidString: identifier),
                      let book = catalogBooks.first(where: { $0.id == uuid })
                else { return }
                draft = BookDraft(book: book.book)
            }
            .task(id: searchText) {
                // Yazma bitene kadar bekle; 50 binlik katalogda her harfte süzme yapılmaz
                // İptal edilen (yeni tuşla geçersizleşen) bekleme süzmeyi tetiklemez
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                activeSearchText = searchText
            }
            .task(id: singleBookPhotos) {
                await processSingleBookPhotos()
            }
            .task(id: shelfPhotos) {
                guard !shelfPhotos.isEmpty else { return }
                pendingShelfPhotos = shelfPhotos
                shelfPhotos = []
                if pendingShelfPhotos.count > 1 { isShowingShelfPhotoChoice = true }
                else {
                    shelfPhotoRelation = .overlapping
                    let items = pendingShelfPhotos
                    pendingShelfPhotos = []
                    Task { await processShelfPhotos(items) }
                }
            }
            .confirmationDialog("Fotoğraflar aynı kitapları mı gösteriyor?", isPresented: $isShowingShelfPhotoChoice, titleVisibility: .visible) {
                Button("Aynı kitapların farklı açıları") {
                    shelfPhotoRelation = .overlapping
                    let items = pendingShelfPhotos
                    pendingShelfPhotos = []
                    Task { await processShelfPhotos(items) }
                }
                Button("Farklı kitaplar / yeni nüshalar") {
                    shelfPhotoRelation = .distinct
                    let items = pendingShelfPhotos
                    pendingShelfPhotos = []
                    Task { await processShelfPhotos(items) }
                }
                Button("Vazgeç", role: .cancel) { pendingShelfPhotos = [] }
            }
            .task(id: selectedPhotos) {
                guard !selectedPhotos.isEmpty, acceptsActiveCatalogResult() else { return }
                let items = selectedPhotos
                if items.count == 1 {
                    await processSeparateBooks(items)
                } else {
                    // Birden çok fotoğraf: ayar açıksa Gemini gruplar, değilse kullanıcıya sorulur
                    if GeminiFotoGruplayici.acik {
                        await groupPhotosWithGemini(items)
                    } else {
                        pendingBulkPhotos = items
                        isShowingBulkPhotoChoice = true
                    }
                }
                guard acceptsActiveCatalogResult() else { return }
                if selectedPhotos == items { selectedPhotos = [] }
            }
            .confirmationDialog(
                "\(pendingBulkPhotos.count) fotoğraf seçtiniz",
                isPresented: $isShowingBulkPhotoChoice,
                titleVisibility: .visible
            ) {
                Button("Tek Kitap — fotoğrafları birleştir") {
                    let items = pendingBulkPhotos
                    pendingBulkPhotos = []
                    Task { await mergePhotosIntoOneBook(items) }
                }
                Button("Ayrı Kitaplar — her fotoğraf bir kitap") {
                    let items = pendingBulkPhotos
                    pendingBulkPhotos = []
                    Task { await processSeparateBooks(items) }
                }
                if GeminiSettings.isActive {
                    Button("Karışık — Gemini kitaplara göre gruplasın") {
                        let items = pendingBulkPhotos
                        pendingBulkPhotos = []
                        Task { await groupPhotosWithGemini(items) }
                    }
                }
                Button("Vazgeç", role: .cancel) {
                    pendingBulkPhotos = []
                }
            } message: {
                Text("Aynı kitabın sayfaları mı (kapak + künye + son sayfa), yoksa farklı kitaplar mı?")
            }
            .task {
                // İlk açılış tanıtımı burada değil, MainTabView'da açılır (Ana Sayfa'nın üstünde).
                guard acceptsActiveCatalogResult() else { return }
                // Demirbaş kodları kataloğa bağlı: önce başlangıç kataloğu tamamen
                // yüklensin, sonra kodlar işlensin (sıra değişirse kodlar kaybolur).
                await importSeedCatalogIfNeeded()
                guard acceptsActiveCatalogResult() else { return }
                applyAccessionCodesIfNeeded()
                // Yarım kalan "Amazon'dan doldur" işi varsa kendiliğinden sürdürülür
                // Yalnız Ekle sekmesinde ve çalışmıyorken: ikinci ContentView (Yönetim) aynı işi
                // paralel başlatmasın, sekmeye dönüş çalışan işi durdurmasın, görevli oturumunda
                // her açılışta yetki uyarısı çıkmasın
                if presentation == .add, !isEnriching, YetkiDurumu.shared.yonetici,
                   UserDefaults.standard.bool(forKey: "enrichmentWasRunning"),
                   enrichmentPendingCount > 0 {
                    toggleEnrichment()
                }
                migrateLegacyBooksIfNeeded()
                // Yarım kalan tarama kuyruğu var mı?
                let yukleme = PendingQueueStore.loadResult()
                if yukleme.bozukYedek != nil {
                    bulkMessage = "Bekleyen kuyruk dosyası okunamadı; bozuk dosya “BekleyenKuyruk.bozuk” olarak saklandı. Kitapları yeniden tarayabilirsiniz."
                }
                let pending = yukleme.taslaklar
                if !pending.isEmpty && batchDrafts.isEmpty {
                    pendingRestoredTaslaklar = pending
                    isShowingQueueRestorePrompt = true
                } else if draft == nil, let yarim = TaslakDeposu.yukle().first {
                    // Kaydedilmeden kalan tek kitap düzenlemesi: düzenleyici kaldığı yerden açılır
                    var geri = BookDraft(book: yarim)
                    geri.existingBookID = nil
                    draft = geri
                    TaslakDeposu.temizle()
                    bulkMessage = "Kaydedilmeden kalan “\(yarim.title.isEmpty ? yarim.isbn ?? "" : yarim.title)” taslağı geri açıldı."
                }
            }
    }

    var bookList: some View {
        VStack(spacing: 0) {
            catalogSearchField
                .padding(.horizontal)
                .padding(.top, 8)

            HStack {
                Label("\(catalogBooks.count) kitap", systemImage: "books.vertical")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KitapTema.ana)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(KitapTema.ana.opacity(0.12), in: .capsule)

                Spacer()
                Text("\(incompleteBookCount) eksik kayıt")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(incompleteBookCount == 0 ? KitapTema.basari : KitapTema.vurgu)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        (incompleteBookCount == 0 ? KitapTema.basari : KitapTema.vurgu).opacity(0.12),
                        in: .capsule
                    )
            }
            .font(.subheadline)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if catalogLayout == .list {
                // Ada göre sıralıyken harf bölümleri + A-Z hızlı kaydırma şeridi
                if catalogSort == .title && !isSelecting {
                    alphabeticList
                } else {
                List(selection: $selectedBookIDs) {
                    ForEach(filteredBooks) { book in
                        Button {
                            draft = BookDraft(book: book.book)
                        } label: {
                            BookRow(book: book.book)
                        }
                        .buttonStyle(.plain)
                        .tag(book.id)
.contextMenu {
                            if let isbn = book.isbn, !isbn.isEmpty {
                                Button {
                                    enrichFromAmazon(book)
                                } label: {
                                    Label("Amazon’dan Güncelle", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }
                            if (book.loanedTo ?? "").isEmpty {
                                Button {
                                    // Etkin katalog form açılmadan denetlenir; kayıt anında form yeniden denetler.
                                    do { try requireActiveCatalog(); loanTargetBook = book }
                                    catch { recognitionError = error.localizedDescription }
                                } label: {
                                    Label("Ödünç ver", systemImage: "person.badge.clock")
                                }
                            } else {
                                Button {
                                    do {
                                        _ = try LoanActionEngine.giveBack(book: book, person: book.loanedTo,
                                            loans: catalogLoans, context: modelContext)
                                    } catch { recognitionError = error.localizedDescription }
                                } label: {
                                    Label("İade Al", systemImage: "arrow.uturn.left.circle")
                                }
                            }
                            Button {
                                shareTargetBook = book.book
                            } label: {
                                Label("Paylaş", systemImage: "square.and.arrow.up")
                            }
                            if book.coverData != nil {
                                Button {
                                    reReadOCR(book)
                                } label: {
                                    Label("Yeniden Oku (OCR)", systemImage: "text.viewfinder")
                                }
                            }
                            if (book.isbn ?? "").isEmpty {
                                Button {
                                    searchByTitleAuthor(book)
                                } label: {
                                    Label("Ad + Yazarla Ara", systemImage: "magnifyingglass")
                                }
                                Button {
                                    var updated = book.book
                                    updated.isbn = InternalBarcode.generate(existingCodes: Set(catalogBooks.compactMap(\.isbn)))
                                    _ = saveBook(updated)
                                } label: {
                                    Label("Barkod Üret", systemImage: "barcode")
                                }
                            }
                            if book.isWithdrawn {
                                Button {
                                    restoreWithdrawnBook(book)
                                } label: {
                                    Label("Geri Getir", systemImage: "arrow.uturn.backward")
                                }
                            } else {
                                Button {
                                    withdrawTargetBook = book
                                } label: {
                                    Label("Kayıttan Düşür", systemImage: "archivebox")
                                }
                            }
                            Button(role: .destructive) {
                                deleteBook(book)
                            } label: {
                                Label("Çöp Kutusuna Taşı", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: deleteFilteredBooks)
                }
#if os(iOS)
                .environment(\.editMode, .constant(isSelecting ? .active : .inactive))
#endif
                }
            } else if catalogLayout == .shelves {
                shelfList
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 120), spacing: 16)],
                        spacing: 20
                    ) {
                        ForEach(filteredBooks) { book in
                            Button {
                                draft = BookDraft(book: book.book)
                            } label: {
                                BookCoverCard(book: book.book)
                            }
                            .buttonStyle(.plain)
.contextMenu {
                                Button {
                                    shareTargetBook = book.book
                                } label: {
                                    Label("Paylaş", systemImage: "square.and.arrow.up")
                                }
                                if let isbn = book.isbn, !isbn.isEmpty {
                                    Button {
                                        enrichFromAmazon(book)
                                    } label: {
                                        Label("Amazon’dan Güncelle", systemImage: "arrow.triangle.2.circlepath")
                                    }
                                }
                                if book.isWithdrawn {
                                    Button {
                                        restoreWithdrawnBook(book)
                                    } label: {
                                        Label("Geri Getir", systemImage: "arrow.uturn.backward")
                                    }
                                } else {
                                    Button {
                                        withdrawTargetBook = book
                                    } label: {
                                        Label("Kayıttan Düşür", systemImage: "archivebox")
                                    }
                                }
                                Button(role: .destructive) {
                                    deleteBook(book)
                                } label: {
                                    Label("Çöp Kutusuna Taşı", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }

    /// Ada göre harf bölümlerine ayrılmış liste; sağ kenarda A-Z hızlı şeridi.
    /// Katalog arama alanı: listeyi süzer; yanındaki barkod düğmesi kamerayla ISBN arar.
    var catalogSearchField: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Kitap, yazar veya ISBN ara", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isSearchFieldFocused)
                    .accessibilityLabel("Katalogda ara")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Aramayı temizle")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))

#if os(iOS)
            Button {
                isSearchFieldFocused = false
                startSearchScan()
            } label: {
                Image(systemName: "barcode.viewfinder")
                    .font(.title3)
                    .foregroundStyle(KitapTema.ana)
                    .padding(8)
                    .background(KitapTema.ana.opacity(0.12), in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Barkod okutarak kitap ara")
#endif
        }
    }

    var alphabeticList: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .trailing) {
                List {
                    ForEach(alphabetSections, id: \.0) { letter, books in
                        Section(letter) {
                            ForEach(books) { book in
                                Button {
                                    draft = BookDraft(book: book.book)
                                } label: {
                                    BookRow(book: book.book)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .id(letter)
                    }
                }

                VStack(spacing: 1) {
                    ForEach(alphabetSections.map(\.0), id: \.self) { letter in
                        Button {
                            withAnimation { proxy.scrollTo(letter, anchor: .top) }
                        } label: {
                            Text(letter)
                                .font(.caption2.weight(.semibold))
                                .frame(width: 18)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(KitapTema.ana)
                    }
                }
                .padding(.vertical, 6)
                .padding(.trailing, 2)
                .background(.thinMaterial, in: .capsule)
                .padding(.trailing, 2)
                .accessibilityLabel("Harfe göre hızlı geçiş")
            }
        }
    }

    var alphabetSections: [(String, [CatalogBook])] {
        Dictionary(grouping: filteredBooks) { book -> String in
            let normalized = CatalogMatcher.normalize(book.title)
            guard let first = normalized.first, first.isLetter else { return "#" }
            return String(first).uppercased()
        }
        .sorted { $0.key < $1.key }
        .map { ($0.key, $0.value) }
    }

    /// Dolap → Raf hiyerarşisinde gruplu görünüm.
    var shelfList: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                cabinetStrip(proxy: proxy)
                List {
                    ForEach(shelfGroups, id: \.0) { groupName, books in
                        Section(groupName) {
                            ForEach(books) { book in
                                Button {
                                    draft = BookDraft(book: book.book)
                                } label: {
                                    BookRow(book: book.book)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .id(groupName)
                    }
                }
            }
        }
    }

    /// Üstte dolap harfleri (A-Z) ve her dolaptaki kitap sayısı; dokununca o dolaba atlar.
    func cabinetStrip(proxy: ScrollViewProxy) -> some View {
        let counts = cabinetCounts
        return Group {
            if !counts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(counts, id: \.0) { cabinet, count in
                            Button {
                                if let target = shelfGroups.first(where: { $0.0.contains("Dolap \(cabinet)") || $0.0 == cabinet })?.0 {
                                    withAnimation { proxy.scrollTo(target, anchor: .top) }
                                }
                            } label: {
                                VStack(spacing: 2) {
                                    Text(cabinet).font(.headline)
                                    Text("\(count)").font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(KitapTema.ana.opacity(0.1), in: .rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(.bar)
            }
        }
    }

    var cabinetCounts: [(String, Int)] {
        var counts: [String: Int] = [:]
        for book in filteredBooks {
            guard let cabinet = book.cabinet, !cabinet.isEmpty else { continue }
            counts[cabinet, default: 0] += 1
        }
        return counts.sorted { $0.key < $1.key }
    }

    var shelfGroups: [(String, [CatalogBook])] {
        // Raflar görünümüyle aynı düzen: yeri atanmamış kitaplar en sonda.
        Dictionary(grouping: filteredBooks) { $0.konumMetni ?? CatalogBook.yerAtanmamis }
        .sorted { a, b in
            if (a.key == CatalogBook.yerAtanmamis) != (b.key == CatalogBook.yerAtanmamis) { return b.key == CatalogBook.yerAtanmamis }
            return a.key.localizedStandardCompare(b.key) == .orderedAscending
        }
        .map { ($0.key, $0.value) }
    }

    var incompleteBookCount: Int {
        catalogBooks.filter {
            !$0.isWithdrawn && (
                $0.isbn?.isEmpty ?? true
                    || $0.author.isEmpty
                    || $0.publisher?.isEmpty ?? true
                    || $0.coverData == nil
            )
        }
        .count
    }

    func sourcePhotoItems(in session: ScanSession, photoIndex: Int) -> [ScanSourcePhotoItem] {
        (session.bookSources ?? [:]).filter { $0.value.photoIndex == photoIndex && $0.value.tileID == nil }
            .sorted {
                let a = $0.value.box ?? [], b = $1.value.box ?? []
                if a.count == 4, b.count == 4 {
                    if a[0] != b[0] { return a[0] < b[0] }
                    if a[1] != b[1] { return a[1] < b[1] }
                }
                return $0.key.uuidString < $1.key.uuidString
            }.map { id, source in
                ScanSourcePhotoItem(id: id,
                    title: session.pendingBooks.first(where: { $0.id == id })?.title
                        ?? catalogBooks.first(where: { $0.id == id })?.title ?? "Algılanan kitap",
                    source: source)
            }
    }

    func confirmSourceBox(_ box: [Double], bookID: UUID, session original: ScanSession) throws {
        try requireActiveCatalog()
        let latest = scanSession?.id == original.id ? scanSession! : (try ScanSessionStore.allVerified().first(where: { $0.id == original.id }) ?? original)
        let recovered = try ScanSessionStore.reconciled(latest, context: modelContext)
        guard let source = recovered.bookSources?[bookID], let photos = recovered.sourceImages,
              photos.indices.contains(source.photoIndex) else { throw ScanBoxEditError.sourceMissing }
        let bounds = try ScanBoxBounds.validated(box)
        let crop = CokluKitapAlgilayici.kapakKesiti(photos[source.photoIndex], kutu: bounds.rect)
        let updated = try ScanBoxEditEngine.applyPhoto(bounds.values, bookID: bookID, to: recovered, coverData: crop)
        try ScanSessionStore.save(updated)
        sourceSession = updated
        if scanSession?.id == updated.id {
            scanSession = updated
            for index in batchDrafts.indices {
                let id = batchDrafts[index].existingBookID ?? batchDrafts[index].id
                if let pending = updated.pendingBooks.first(where: { $0.id == id }) {
                    batchDrafts[index].coverData = pending.coverData
                    batchDrafts[index].fieldMetadata = pending.fieldMetadata
                }
            }
        }
        refreshScanSessions()
    }

    /// Son Eklemeler'de gösterilen oturumlar; boşsa panel hiç çizilmez (yönlendirme cümlesi de anmaz).
    var gosterilecekOturumlar: [ScanSession] {
        recentScanSessions.filter {
            !$0.pendingBooks.isEmpty || !$0.insertedIDs.isEmpty || !$0.mergedCopies.isEmpty || $0.shelfResult != nil || $0.hasSourceImages || !($0.separatePhotoSources ?? []).isEmpty
        }
    }

    /// Ekle sayfasının dış ScrollView'u içinde düz yığın (iç içe ikinci kaydırma alanı yok).
    /// Oturum yokken hiç gösterilmez; "N kaydı kontrol et" şeridi kartların üstündedir.
    @ViewBuilder
    var scanSessionsPanel: some View {
        let sessions = gosterilecekOturumlar
        if !sessions.isEmpty || bitmisOturumOzeti.sessions > 0 {
            VStack(alignment: .leading, spacing: 14) {
                if !sessions.isEmpty {
                    Text("Son Eklemeler").font(.headline)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(Array(sessions.prefix(5))) { session in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.title).font(.subheadline.weight(.semibold))
                        Text(session.updatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(KitapTema.ikincilMetin)
                        if session.hasSourceImages {
                            HStack {
                                Button("Kaynak Fotoğraflar") { sourceSession = ScanSessionStore.hydrated(session) }.buttonStyle(.bordered)
                                if session.separatePhotoSources == nil && session.kind == .photo {
                                    Button("Fotoğrafları Yeniden Tara") {
                                        islemBaslat { await processShelfImages(ScanSessionStore.hydrated(session).sourceImages ?? [], resuming: session) }
                                    }.buttonStyle(.bordered).disabled(isRecognizing)
                                }
                            }
                        }
                        if let sources = session.separatePhotoSources, sources.contains(where: \.needsRead) {
                            ForEach(sources.filter(\.needsRead)) { source in
                                Text("Fotoğraf \(source.selectionIndex + 1): \(source.errorMessage ?? "Okuma bekliyor")")
                                    .font(.footnote).fixedSize(horizontal: false, vertical: true)
                                if source.imageIndex == nil {
                                    PhotosPicker(selection: Binding<PhotosPickerItem?>(get: { nil }, set: { item in
                                        guard let item else { return }
                                        retainedPhotoSelections[source.id] = item
                                        islemBaslat { await processSeparatePhotoSources(sources, resuming: session, only: [source.id]) }
                                    }), matching: .images) {
                                        Label("Bu fotoğrafı galeriden yeniden seç", systemImage: "photo.badge.plus")
                                    }.disabled(isRecognizing)
                                }
                            }
                            Button("Başarısız Fotoğrafları Yeniden Dene") {
                                islemBaslat { await processSeparatePhotoSources(sources, resuming: session) }
                            }.buttonStyle(.bordered).disabled(isRecognizing)
                        }
                        if let result = session.shelfResult {
                            Text("\(result.books.count) kitap · \(result.successfulTileCount)/\(result.tileCount) dilim okundu")
                            Button("Raf Oturumunu Aç") {
                                resumedShelfSessionID = session.id
                                isShowingShelfScan = true
                            }.buttonStyle(.bordered)
                        } else {
                            // Sıfırlar yazılmaz: "0 inceleme bekliyor · 0 yeni kayıt" gürültüsü olmasın
                            if let ozet = session.ozetMetni {
                                Text(ozet)
                                    .font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            // Dar ekranda ve büyük yazıda düğmeler alt alta iner
                            ViewThatFits(in: .horizontal) {
                                HStack { oturumDugmeleri(session) }
                                VStack(alignment: .leading) { oturumDugmeleri(session) }
                            }
                        }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                }
                if bitmisOturumOzeti.sessions > 0 {
                    Button(role: .destructive) { bitmisOturumOnayi = true } label: {
                        Label("Bitmiş tarama oturumlarını temizle (\(bitmisOturumOzeti.sessions) oturum, \(ByteCountFormatter.string(fromByteCount: bitmisOturumOzeti.bytes, countStyle: .file)))",
                              systemImage: "trash")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("add.purgeFinishedSessions")
                    .confirmationDialog("Bitmiş tarama oturumları silinsin mi?", isPresented: $bitmisOturumOnayi, titleVisibility: .visible) {
                        Button("\(bitmisOturumOzeti.sessions) oturumu sil", role: .destructive) {
                            ScanSessionStore.purgeFinished()
                            bitmisOturumOzeti = ScanSessionStore.finishedUsage()
                            refreshScanSessions()
                        }
                        Button("Vazgeç", role: .cancel) { }
                    } message: {
                        Text("30 günden eski, bekleyen işi olmayan oturumların kayıtları ve fotoğrafları silinir. Kataloğa eklenen kitaplar silinmez; bu oturumların “Eklemeleri Geri Al” kaydı kalkar.")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    @ViewBuilder
    func oturumDugmeleri(_ session: ScanSession) -> some View {
        if !session.pendingBooks.isEmpty {
            Button("Kontrole Devam Et") {
                let recovered = ScanSessionStore.hydrated((try? ScanSessionStore.reconciled(session, context: modelContext)) ?? session)
                scanSession = recovered
                lastSessionInserted = recovered.insertedIDs
                lastSessionMerged = recovered.mergedCopies
                batchDrafts = recovered.pendingBooks.map { BookDraft(book: $0) }
                isShowingBatchReview = true
            }.buttonStyle(.bordered)
        }
        if !session.insertedIDs.isEmpty || !session.mergedCopies.isEmpty {
            Button("Eklemeleri Geri Al") {
                scanSession = ScanSessionStore.hydrated(session)
                lastSessionInserted = session.insertedIDs
                lastSessionMerged = session.mergedCopies
                // Araç panelindeki eşdeğeri gibi önce onay sorulur
                showingSessionUndoConfirmation = true
            }.buttonStyle(.bordered)
        }
    }

    var importActions: some View {
        VStack(spacing: 2) {
            HStack {
                Label("Kitap ekle", systemImage: "plus.viewfinder")
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text("\(catalogBooks.count) kitap")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: .capsule)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            if presentation == .add {
                // Yönlendirme ilk bakışta görünsün: kartların altında değil, başlığın hemen altında
                Text(gosterilecekOturumlar.isEmpty
                     ? "Bir ekleme yöntemi seçin."
                     : "Bir ekleme yöntemi seçin. Önceki eklemeler en altta, Son Eklemeler’de.")
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                // Yarım kalan kuyruk kaydırmadan görünsün: kartların üstünde
                if !batchDrafts.isEmpty {
                    Button { isShowingBatchReview = true } label: {
                        Label("\(batchDrafts.count) kaydı kontrol et", systemImage: "tray.full.fill")
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.kitapDolu(KitapTema.ana))
                    .accessibilityIdentifier("add.reviewQueue")
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
            importActionButtons

            if enrichmentPendingCount > 0 {
                // Dar ekranda ve büyük yazıda düğme metnin altına iner; düğme en az 44 pt kalır
                ViewThatFits(in: .horizontal) {
                    HStack {
                        enrichmentStatus
                        Spacer()
                        enrichmentButton
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        enrichmentStatus
                        enrichmentButton
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
            // Yöntemin ne zaman kullanılacağı ilgili kartın alt başlığında yazar (eski genel ipucu kalktı).
        }
    }

    var enrichmentStatus: some View {
        Label(
            isEnriching
                ? "Dolduruluyor: %\(enrichmentPercent) — kalan \(enrichmentPendingCount)"
                : "Bilgi bekleyen: \(enrichmentPendingCount) kitap",
            systemImage: "wand.and.stars"
        )
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }

    var enrichmentButton: some View {
        Button(isEnriching ? "Duraklat" : "Amazon'dan Doldur") {
            toggleEnrichment()
        }
        .buttonStyle(.kitapTonlu(KitapTema.ana))
    }

    /// Üst panelin yüksekliği: içerik sığıyorsa kendi yüksekliği, sığmıyorsa ekranın %60'ı.
    /// Ölçümler henüz gelmediyse nil (doğal yükseklik) döner.
    var headerHeight: CGFloat? {
        guard availableHeight > 0, headerContentHeight > 0 else { return nil }
        return min(headerContentHeight, availableHeight * (presentation == .add ? 0.68 : 0.6))
    }

    @ViewBuilder
    var importActionButtons: some View {
        // Büyük, renkli işlem kartları; her kart ikon + ad + ne zaman kullanılacağını söyleyen kısa açıklama
        // taşır; dokunma alanı geniş, VoiceOver etiketli.
        // Katalog Yönetimi'nde erişilebilirlik yazı boyutlarında ızgara tüm ekranı kaplayıp listeyi sıfıra
        // itiyordu; o durumda kartlar tek sıra yatay şerit olarak kaydırılır.
        if dynamicTypeSize.isAccessibilitySize && presentation == .management {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    tumEklemeKartlari
                        .frame(width: 150)
                }
                .buttonStyle(.kitapKart())
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
        } else if presentation == .add {
            // Ekle sayfasında kartlar üç grupta; en sık iş (tek kitap, barkodla) en üstte
            VStack(alignment: .leading, spacing: 0) {
                kartGrubu("Tek kitap") { tekKitapKartlari }
                kartGrubu("Çok kitap") { cokKitapKartlari }
                kartGrubu("Diğer kaynaklar") { digerKaynakKartlari }
            }
            .padding(.bottom, 6)
        } else {
            kartIzgarasi { tumEklemeKartlari }
                .padding(.horizontal)
                .padding(.vertical, 10)
        }
    }

    /// Ekle sayfasında bir kart grubu: başlık ve altında eşit sütunlu ızgara.
    func kartGrubu<Icerik: View>(_ baslik: String, @ViewBuilder icerik: () -> Icerik) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(baslik)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 10)
            kartIzgarasi(icerik)
        }
        .padding(.horizontal)
    }

    /// Tembel değil: büyük yazıda aşağı itilen kartlar erişilebilirlik ağacında kalır.
    /// Ekle sayfasında kartlar daha geniştir (telefonda 2 sütun): "ne zaman kullanılır" açıklaması
    /// tek satıra sığar. Dar kartta iki satıra bölünüp son satırı kısa kalan ortalanmış açıklama,
    /// görünüşte okunur olsa da erişilebilirlik kontrast denetiminde hata veriyordu.
    func kartIzgarasi<Icerik: View>(@ViewBuilder _ icerik: () -> Icerik) -> some View {
        let genis = presentation == .add
        return EsitSutunIzgara(enKucukGenislik: dynamicTypeSize.isAccessibilitySize ? 230 : (genis ? 150 : 108),
                        enBuyukGenislik: dynamicTypeSize.isAccessibilitySize ? .infinity : (genis ? 260 : 180),
                        yatayAralik: 8, dikeyAralik: 8) {
            icerik()
        }
        .buttonStyle(.kitapKart())
    }

    /// Katalog Yönetimi'ndeki tek parça şerit ve ızgara için bütün yöntemler.
    @ViewBuilder
    var tumEklemeKartlari: some View {
        tekKitapKartlari
        cokKitapKartlari
        digerKaynakKartlari
    }

    /// Tek kitap: en sık iş. "Barkodla ekle" menü açmaz, tek dokunuşla tarayıcıyı açar.
    @ViewBuilder
    var tekKitapKartlari: some View {
#if os(iOS)
                Button { startBarcodeScan(serial: false, yeniOturum: true) } label: {
                    IslemKarti(baslik: "Barkodla ekle", altBaslik: "Arka kapaktaki ISBN", ikon: "barcode.viewfinder", renk: KitapTema.ana)
                }
                // Etiket görünen adla başlar: Sesle Denetim'de "Barkodla ekle'ye dokun" eşleşsin
                .accessibilityLabel("Barkodla ekle: tek kitap, arka kapaktaki ISBN")
                .accessibilityIdentifier("add.barcode")
#endif
                Button { draft = BookDraft(); beginAddSession() } label: {
                    IslemKarti(baslik: "Elle", altBaslik: "Barkod yoksa yazın", ikon: "square.and.pencil", renk: KitapTema.ana)
                }
                .accessibilityIdentifier("add.manual")
#if os(iOS)
                Button { isShowingLiveCover = true } label: {
                    IslemKarti(baslik: "Canlı Kapak", altBaslik: "Kapağı kameraya tutun", ikon: "text.viewfinder", renk: .cyan, ai: GeminiSettings.isOCREnabled)
                }
                .accessibilityLabel("Canlı kapak: kapağı kameraya tutarak ekle")
                .accessibilityIdentifier("add.liveCover")

                Button {
                    if VNDocumentCameraViewController.isSupported {
                        isShowingDocumentScanner = true
                    } else {
                        recognitionError = "Kamera ile tarayıcı bu ortamda desteklenmiyor (Simülatörde fiziksel kamera bulunmamaktadır). Fotoğraf seçebilir veya Amazon üzerinden arayabilirsiniz."
                    }
                } label: {
                    // "Kapak" sözcüğü Canlı Kapak'ın: belge kamerası sayfa sayfa tarar
                    IslemKarti(baslik: "Belge Tara", altBaslik: "Kapak + künye + son sayfa", ikon: "doc.viewfinder", renk: KitapTema.vurgu, ai: GeminiSettings.isOCREnabled)
                }
                .accessibilityLabel("Belge tara: kapak, künye ve son sayfa")
                .accessibilityIdentifier("add.cover")
#endif

                PhotosPicker(selection: $singleBookPhotos, maxSelectionCount: 6, matching: .images) {
                    IslemKarti(baslik: "Galeriden", altBaslik: "En çok 6 foto, aynı kitap", ikon: "photo.badge.plus", renk: KitapTema.foto, ai: GeminiSettings.isOCREnabled)
                }
                .accessibilityLabel("Galeriden tek kitabın fotoğraflarını seç")
    }

    /// Çok kitap: toplu barkod modları, fotoğraflar ve raf.
    @ViewBuilder
    var cokKitapKartlari: some View {
#if os(iOS)
                Menu {
                    Button {
                        startBarcodeScan(serial: true)
                    } label: {
                        Label("Seri tarama (kitapları art arda okut)", systemImage: "rectangle.stack.badge.plus")
                    }
                    Button {
                        startDepotSetup()
                    } label: {
                        Label("Depo modu (binlerce kitap, bilgiler sonra)", systemImage: "shippingbox")
                    }
                    Button {
                        startShelfAssignSetup()
                    } label: {
                        Label("Raf atama (kayıtlı kitaba raf ver)", systemImage: "square.grid.3x3")
                    }
                } label: {
                    IslemKarti(baslik: "Toplu tarama", altBaslik: "Seri, depo, raf atama", ikon: "rectangle.stack.badge.plus", renk: .mint, menu: true)
                }
                .accessibilityLabel("Toplu tarama: seri, depo veya raf atama")
                .accessibilityIdentifier("add.barcodeModes")
#endif

                PhotosPicker(selection: $selectedPhotos, matching: .images) {
                    IslemKarti(baslik: "Ayrı fotoğraflar", altBaslik: "Her kitap ayrı fotoğrafta", ikon: "photo.stack", renk: KitapTema.toplu, ai: GeminiSettings.isOCREnabled)
                }
                .accessibilityLabel("Ayrı fotoğraflar: her kitap ayrı fotoğrafta, çok kitap ekle")

                // Tek karede yan yana dizilmiş kitaplar: her kitap barkod + Gemini ile ayrı bulunur,
                // Amazon'dan doldurulur, tam olanlar onaysız kaydedilir (RafKaresi.swift)
                PhotosPicker(selection: $shelfPhotos, maxSelectionCount: 10, matching: .images) {
                    IslemKarti(baslik: "Yan yana kapaklar", altBaslik: "Tek karede çok kitap", ikon: "square.grid.3x3.fill", renk: .indigo, ai: GeminiSettings.isOCREnabled)
                }
                .accessibilityLabel("Yan yana kapaklar: tek karedeki kitapların hepsini ekle")
                .accessibilityIdentifier("add.table")

                Button { resumedShelfSessionID = nil; isShowingShelfScan = true } label: {
                    IslemKarti(baslik: "Raf sırtları", altBaslik: "Raf fotoğrafından", ikon: "books.vertical.fill", renk: KitapTema.vurgu, ai: true)
                }
                .accessibilityLabel("Raf sırtları: raf fotoğrafından kitap ekle")
                .accessibilityIdentifier("add.shelf")
    }

    /// Diğer kaynaklar: çevrimiçi arama, dosya ve ses.
    @ViewBuilder
    var digerKaynakKartlari: some View {
                Button {
                    isShowingAmazonLookup = true
                } label: {
                    IslemKarti(baslik: "Amazon", altBaslik: "ISBN ile bul", ikon: "cart.fill", renk: KitapTema.amazon)
                }
                .accessibilityLabel("Amazon'dan kitap bilgisi ara")

                Button {
                    isShowingKitapyurduLookup = true
                } label: {
                    IslemKarti(baslik: "Kitapyurdu", altBaslik: "Ad ile ara", ikon: "books.vertical.fill", renk: .red)
                }
                .accessibilityLabel("Kitapyurdu'ndan kitap bilgisi ara")

                Button {
                    isShowingPDFImporter = true
                } label: {
                    IslemKarti(baslik: "Dosya", altBaslik: "PDF / görsel", ikon: "folder", renk: KitapTema.dosya)
                }
                .accessibilityLabel("Dosyadan PDF veya görsel içe aktar")

                // Amazon'la aynı renkte değil: ayrı bir yöntem olduğu renkten de anlaşılsın
                Button {
                    isShowingVoiceEntry = true
                } label: {
                    IslemKarti(baslik: "Sesle", altBaslik: "Söyle, kaydet", ikon: "mic.fill", renk: .brown, ai: true)
                }
                .accessibilityLabel("Kitabı sesle kaydet")
    }

#if os(iOS)
    var scannerCover: some View {
        ZStack(alignment: .topTrailing) {
            isbnScanner()
                // Seri taramada her 10 kitapta sesli sayaç (ekrana bakmadan çalışmak için)
                .onChange(of: serialScanCount) { _, sayi in
                    SeriTaramaSesi.bildir(sayi)
                }
                // Kamera tüm ekranı kaplar; klavye açılınca küçülmez
                .ignoresSafeArea()

            HStack(spacing: 16) {
                Button {
                    isTorchOn.toggle()
                    ScannerTorch.set(on: isTorchOn)
                } label: {
                    Label(
                        "Fener",
                        systemImage: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill"
                    )
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .foregroundStyle(isTorchOn ? Color.yellow : Color.white)
                    .shadow(radius: 3)
                }
                .accessibilityLabel(isTorchOn ? "Feneri kapat" : "Feneri aç")
                .accessibilityIdentifier("scanner.torch")

                Button {
                    closeBarcodeScanner()
                } label: {
                    Label("Kapat", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                }
                .accessibilityLabel("Barkod tarayıcıyı kapat")
                .accessibilityIdentifier("scanner.close")
            }
            .padding()

            if tarama.kip.panelGerekli {
                scannerOverlayPanel
            } else if !isSearchScan {
                tekliTaramaPaneli
            }

            if let hata = tarama.hata {
                TaramaHataSeridi(mesaj: hata)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 64)
            }
        }
        // Kenarlara uzanır; yalnız klavye alanı korunur ki elle ISBN alanı klavyenin altında kalmasın
        .ignoresSafeArea(.container)
        .confirmationDialog(depoSorusu.map { "“\($0.kitapAdi)” zaten kayıtlı" } ?? "",
                            isPresented: Binding(get: { depoSorusu != nil }, set: { if !$0 { depoSorusu = nil } }),
                            titleVisibility: .visible, presenting: depoSorusu) { soru in
            Button("Nüsha ekle (+1)") { depoSorusunuYanitla(soru, tasi: false) }
            Button("Konumunu buraya taşı") { depoSorusunuYanitla(soru, tasi: true) }
            Button("Vazgeç", role: .cancel) { depoSorusu = nil }
        } message: { soru in
            Text("Şu an: \(soru.eskiKonum)\nOkutulan yer: \(soru.yeniKonum)")
        }
    }

    /// Tekli taramada alttaki yönlendirme: hangi barkodun okutulacağı, kitap barkodu olmayan kodun
    /// uyarısı ve barkod okunmazsa ISBN'i elle yazma yolu. Tarayıcı geçersiz kodda kapanmaz.
    var tekliTaramaPaneli: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                if let reddedilenBarkod {
                    Label("“\(reddedilenBarkod)” kitap ISBN'i değil. Arka kapaktaki 978… barkodunu okutun ya da ISBN'i yazın.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("scanner.rejected")
                } else {
                    Label("Arka kapaktaki 978… barkodunu çerçeveye alın.", systemImage: "barcode.viewfinder")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Erişilebilirlik yazı boyutlarında "Getir" alanın altına iner; alan daralıp ISBN'i kesmez
                let elleGirisDuzeni = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 8))
                elleGirisDuzeni {
                    TextField("Okunmuyorsa ISBN'i yazın", text: $elleISBN)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit { elleISBNIsle() }
                        .accessibilityIdentifier("scanner.manualISBN")
                    Button("Getir") { elleISBNIsle() }
                        .buttonStyle(.kitapTonlu())
                        .disabled(elleISBN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(14)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity)
    }

    /// Barkod okunmazsa ISBN elle yazılır; tekli okutmayla aynı yoldan (katalogdaysa onay) geçer.
    func elleISBNIsle() {
        let kod = elleISBN.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kod.isEmpty else { return }
        guard TekliBarkodDenetimi.kabulEdilir(kod, kayitliIcKod: { registeredInternalBarcode($0) != nil }) else {
            barkoduReddet(kod)
            return
        }
        elleISBN = ""
        isShowingBarcodeScanner = false
        handleScannedISBN(kod, tarayiciKapaniyor: true)
    }

    /// Kitap barkodu olmayan kod: panel uyarır ve VoiceOver'a duyurulur (odak panelde olmayabilir).
    func barkoduReddet(_ kod: String) {
        reddedilenBarkod = kod
        AccessibilityNotification.Announcement(
            "“\(kod)” kitap ISBN'i değil. Arka kapaktaki 978 ile başlayan barkodu okutun ya da ISBN'i yazın."
        ).post()
    }

    /// Barkod tarayıcı. Tekli taramada (ayar açıksa) barkodla birlikte arka kapak fotoğrafı da çekilir.
    func isbnScanner() -> LiveISBNScannerView {
        var scanner = LiveISBNScannerView(
            continuous: tarama.kip.surekli,
            allowRepeats: tarama.kip.surekli
        ) { isbn in
            // Yalnız tekli ve arama kipinde çalışır; sürekli kipler `onScanResult` kullanır.
            if isSearchScan {
                isShowingBarcodeScanner = false
                handleSearchScan(isbn)
            } else {
                isShowingBarcodeScanner = false
                handleScannedISBN(isbn, tarayiciKapaniyor: true)
            }
        } onCancel: {
            closeBarcodeScanner()
        }
        if tarama.kip.surekli {
            scanner.onScanResult = { kod in
                if isShelfAssignMode { return handleShelfAssignScan(kod) }
                if isDepotScan { return handleDepotScan(kod) }
                return handleScannedISBN(kod, enqueueOnly: true)
            }
        }
        if isSerialScan {
            // Aynı kitabın birkaç nüshası art arda okutulabilir; yalnız kadrajda titreyen kod yutulur.
            scanner.tekrarPenceresi = 1.5
            scanner.onTekrar = { kod in
                appendSerialLog("↩︎ Aynı barkod az önce okundu (\(kod)); nüsha için “Son kitaba +1”e basın")
            }
        }
        scanner.onFailure = { hata in
            tarama.hata = "Kamera başlatılamadı: \(hata.localizedDescription)"
            AccessibilityNotification.Announcement("Kamera başlatılamadı").post()
        }
        if capturesBarcodePhoto && !tarama.kip.surekli && !isSearchScan {
            scanner.onScanWithPhoto = { isbn, photo in
                isShowingBarcodeScanner = false
                handleScannedISBN(isbn, backPhoto: photo, tarayiciKapaniyor: true)
            }
        }
        // Tekli taramada (arama dışında) kitap barkodu olmayan kod tarayıcıyı kapatmaz; panel uyarır.
        // Denetim fotoğraflı yoldan da önce yapılır.
        if !tarama.kip.surekli && !isSearchScan {
            scanner.kabulEt = { TekliBarkodDenetimi.kabulEdilir($0, kayitliIcKod: { registeredInternalBarcode($0) != nil }) }
            scanner.onReddedildi = { kod in
                barkoduReddet(kod)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        }
        return scanner
    }

    /// Depo ve seri tarama sırasında alttaki canlı bilgi paneli (ayrı görünüm: BarkodTarama.swift).
    var scannerOverlayPanel: some View {
        TaramaPaneli(
            gunluk: serialLog,
            durumMetni: scannerStatusText,
            rafArtirGoster: isDepotScan || isShelfAssignMode,
            geriAlGoster: isShelfAssignMode ? lastShelfAssignment != nil : (lastScanAction != nil || (isDepotScan && lastShelfAssignment != nil)),
            sonKitabaArtiGoster: isSerialScan && lastScanAction != nil,
            onRafArtir: { advanceDepotShelf() },
            onGeriAl: { if isShelfAssignMode || (isDepotScan && lastShelfAssignment != nil) { undoLastShelfAssignment() } else { undoLastScan() } },
            onSonKitabaArti: { adet in sonKitabaNushaEkle(adet) }
        )
    }

    var scannerStatusText: String {
        if isShelfAssignMode {
            return "Dolap \(depotCabinet) • Raf \(depotShelf) • \(serialScanCount) kitaba atandı"
        }
        if isDepotScan {
            return "Dolap \(depotCabinet) • Raf \(depotShelf) • \(serialScanCount) kitap"
        }
        if tarama.bekleyenSayisi == 0 {
            return "Okunan: \(serialScanCount)"
        }
        return "Okunan: \(serialScanCount) • işlenen: \(tarama.bekleyenSayisi)"
    }
#endif

    var progressOverlayText: String {
        guard scanTotal > 1 else { return "Kitap bilgileri okunuyor…" }
        let percent = scanProgress * 100 / max(1, scanTotal)
        let remaining = max(0, scanTotal - scanProgress)
        return "İşleniyor: \(scanProgress) / \(scanTotal) (%\(percent)) — kalan \(remaining)"
    }

    var bulkBarPlacement: ToolbarItemPlacement {
#if os(iOS)
        .bottomBar
#else
        .automatic
#endif
    }

    /// Şu anki görünüm/filtre/sıralama/arama birleşimini adlandırarak kaydeder.
    func saveCurrentView() {
        guard acceptsActiveCatalogResult() else { return }
        let name = newViewName.trimmingCharacters(in: .whitespacesAndNewlines)
        newViewName = ""
        guard !name.isEmpty else { return }
        SavedViewStore.add(
            SavedView(
                name: name,
                layout: catalogLayout.rawValue,
                filter: catalogFilter.rawValue,
                sort: catalogSort.rawValue,
                searchText: searchText
            )
        )
        savedViews = SavedViewStore.all()
        bulkMessage = "“\(name)” görünümü kaydedildi."
    }

    /// Araç panelinden gelen eylemi uygular. Panel bir sayfa (sheet) olduğu için başka
    /// bir sayfa açan eylemler, panel kapanışı bitene kadar kısa süre beklettirilir;
    /// aksi hâlde iOS ikinci sayfayı sunamaz.
    func startQuickAction(_ eylem: HizliEylem) {
        guard acceptsActiveCatalogResult() else { return }
        switch eylem {
        // Ekle kartlarıyla aynı: tek kitap yolları yeni ekleme oturumu açar (kayıtlar önceki oturuma yazılmasın)
        case .barkod: startBarcodeScan(serial: false, yeniOturum: true)
        case .seri: startBarcodeScan(serial: true)
        case .canliKapak: isShowingLiveCover = true
        case .kamera:
            if VNDocumentCameraViewController.isSupported {
                isShowingDocumentScanner = true
            } else {
                recognitionError = "Bu cihazda belge kamerası desteklenmiyor."
            }
        case .ses: isShowingVoiceEntry = true
        case .elle: draft = BookDraft(); beginAddSession()
        }
    }

    /// Canlı kapak taramasından gelen (düzeltilmiş) tek fotoğrafı okur.
    func recognizeSingleCover(_ photo: Data) async {
        guard acceptsActiveCatalogResult() else { return }
        isRecognizing = true
        defer { isRecognizing = false }
        var result: BookDraft
        if let fields = await GeminiBookRecognizer.fieldsIfEnabled(images: [photo]), fields.isBook != false {
            result = GeminiBookRecognizer.draft(from: fields, cover: photo)
        } else if let local = await BookOCREngine.recognizeBook(imageData: photo) {
            result = local
            result.coverData = photo
        } else {
            recognitionError = "Kapak okunamadı. Işığı artırıp yeniden deneyin."
            return
        }
        guard acceptsActiveCatalogResult() else { return }
        reconcileWithCatalog(&result)
        await replaceWithOfficialCover(&result)
        guard acceptsActiveCatalogResult() else { return }
        presentOrQuickSave(result)
    }

    func handleToolAction(_ action: KatalogAraci) {
        guard acceptsActiveCatalogResult() else { return }
        // Görevli modunda geri dönüşü zor işler yönetici kimliği ister
        let yoneticiGerekli: Set<KatalogAraci> = [.clearSavedViews, .undoSession, .undoBulk, .restoreBackup, .archiveImport, .settings, .fieldMerge, .duplicates]
        if yoneticiGerekli.contains(action) && !YetkiDurumu.shared.yonetici {
            Task {
                if await YetkiDurumu.shared.yoneticiOl() { handleToolAction(action) }
            }
            return
        }
        switch action {
        case .applySavedView(let id):
            if let view = savedViews.first(where: { $0.id == id }) { applySavedView(view) }
        case .clearSavedViews:
            for view in savedViews { SavedViewStore.remove(id: view.id) }
            savedViews = []
        case .amazonComplete:
            bulkCompleteFromAmazon()
        case .undoSession:
            refreshScanSessions()
            guard let last = recentScanSessions.first(where: { !$0.insertedIDs.isEmpty || $0.mergedCopies.values.contains(where: { $0 > 0 }) }) else {
                bulkMessage = "Geri alınabilir kayıt oturumu yok."; return
            }
            scanSession = ScanSessionStore.hydrated(last)
            lastSessionInserted = last.insertedIDs
            lastSessionMerged = last.mergedCopies
            showingSessionUndoConfirmation = true
        case .undoBulk:
            if bulkUndoSnapshot.isEmpty { bulkMessage = "Bu ekranda geri alınabilir toplu işlem yok. Katalog Yönetimi'nde işlemden sonra Geri Al'ı kullanın." }
            else { undoLastBulkOperation() }
        case .archiveExport:
            prepareArchive()
        case .excelExport:
            prepareExcel()
        case .loans:
            oduncListesineGit()
        default:
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                presentTool(action)
            }
        }
    }

    func presentTool(_ action: KatalogAraci) {
        guard acceptsActiveCatalogResult() else { return }
        switch action {
        case .saveView: isShowingSaveViewPrompt = true
        case .duplicates: isShowingDuplicateCleaner = true
        case .students: isShowingStudents = true
        case .classLoan: isShowingClassLoan = true
        case .textbooks: isShowingTextbookDistribution = true
        case .champions: isShowingReadingChampions = true
        case .usageReport: isShowingUsageReport = true
        case .studentCards: isShowingStudentCards = true
        case .accessionRegister: isShowingAccessionRegister = true
        case .statistics: isShowingStatistics = true
        case .reportCenter: isShowingReportCenter = true
        case .dataQuality: isShowingDataQuality = true
        case .fieldMerge: isShowingFieldMerge = true
        case .inventory: isShowingInventory = true
        case .batchQueue: isShowingBatchReview = true
        case .csvImport: isShowingCSVImporter = true
        case .restoreBackup: isShowingRestoreImporter = true
        case .archiveImport: isShowingArchiveImporter = true
        case .settings: isShowingSettings = true
        case .shelfScan: isShowingShelfScan = true
        case .applySavedView, .clearSavedViews, .amazonComplete, .undoSession, .undoBulk, .archiveExport, .excelExport,
             .loans:
            break
        }
    }

    /// Ödünç işlerinin tek merkezi Ödünç sekmesidir: eski ödünç ekranları açılmaz, sekmeye gidilir.
    func oduncListesineGit() {
        KutuphaneRotasi.shared.oduncBolumu = .etkin
        derinBaglanti.hedefSekme = .odunc
        if presentation == .management { persistScanSessionNow(); dismiss() }
    }

    func applySavedView(_ view: SavedView) {
        if let layout = CatalogLayout(rawValue: view.layout) { catalogLayout = layout }
        if let filter = CatalogFilter(rawValue: view.filter) { catalogFilter = filter }
        if let sort = CatalogSort(rawValue: view.sort) { catalogSort = sort }
        searchText = view.searchText
        activeSearchText = view.searchText
    }

    var withdrawPromptBinding: Binding<Bool> {
        Binding(
            get: { withdrawTargetBook != nil },
            set: { isPresented in
                if !isPresented {
                    withdrawTargetBook = nil
                    withdrawReasonText = ""
                }
            }
        )
    }

    var bulkMessageBinding: Binding<Bool> {
        Binding(
            get: { bulkMessage != nil },
            set: { isPresented in
                if !isPresented {
                    bulkMessage = nil
                }
            }
        )
    }

#if os(iOS)
    /// Kamera izni ve tarayıcı desteği. Reddedilmişse Ayarlar'a götüren uyarı çıkar; "desteklenmiyor"
    /// yalnız cihazda ya da simülatörde canlı tarayıcı yoksa söylenir.
    func kameraHazir() async -> Bool {
        switch await KameraIzni.iste() {
        case .izinli:
            return true
        case .reddedildi:
            kameraIzniUyarisi = true
            return false
        case .desteklenmiyor:
            recognitionError = "Barkod tarayıcı bu cihazda veya simülatörde desteklenmiyor. Kamera veya Amazon aramasını kullanabilirsiniz."
            return false
        }
    }

    /// Kayıt yazan tarama kipleri yönetici ister; rol kilidi açıksa tarayıcı açılmadan önce kimlik sorulur.
    func taramaYetkisi(_ neden: String) async -> Bool {
        guard await YetkiDurumu.shared.yoneticiOl(neden: neden) else {
            recognitionError = YetkiDurumu.shared.hata ?? "Bu işlem için yönetici kimliği gerekir."
            return false
        }
        return acceptsActiveCatalogResult()
    }

    /// `yeniOturum`: kart ya da kısayoldan başlayan tekli tarama yeni ekleme oturumu açar;
    /// şeritteki "Sonrakini okut" aynı oturumda kalır (her kitap ayrı oturum kartı olmasın).
    func startBarcodeScan(serial: Bool, yeniOturum: Bool = false) {
        Task { @MainActor in
            guard await kameraHazir() else { return }
            if serial {
                guard await taramaYetkisi("Seri taramayı başlatmak için kimliğinizi doğrulayın") else { return }
                isShowingScanSetup = true
            } else {
                if yeniOturum { beginAddSession() }
                reddedilenBarkod = nil
                elleISBN = ""
                tarama.kip = .tekli
                tarama.hata = nil
                isShowingBarcodeScanner = true
            }
        }
    }

    func beginSerialScan(assignment: BulkAssignment, autoSave: Bool) {
        scanAssignment = assignment
        autoSaveScans = autoSave
        beginAddSession()
        tarama.sifirla()
        lastScanAction = nil
        tarama.kip = .seri(assignment, otoKayit: autoSave)
        isShowingBarcodeScanner = true
    }
#endif

    // MARK: - Depo modu (50.000+ kitap için ağsız hızlı kayıt)

#if os(iOS)
    func startDepotSetup() {
        Task { @MainActor in
            guard await kameraHazir() else { return }
            guard await taramaYetkisi("Depo modunu başlatmak için kimliğinizi doğrulayın") else { return }
            isShowingDepotSetup = true
        }
    }

    func beginDepotScan(location: String, cabinet: String, shelf: String, category: String) {
        depotLocation = location
        depotCabinet = cabinet
        depotShelf = shelf
        depotCategory = category

        // Hızlı mükerrer kontrolü için ISBN dizini bir kez kurulur (50k kayıtta bile tek geçiş)
        depotIndex = DepoIndeksi.kur(catalogBooks)

        beginAddSession()
        tarama.sifirla()
        lastScanAction = nil
        tarama.kip = .depo
        isShowingBarcodeScanner = true
    }
#endif

    /// Uygulamanın ISBN'siz kitaba ürettiği "200…" iç barkod, katalogda kayıtlıysa taramalarda
    /// ISBN gibi kabul edilir; kayıtlı olmayan iç barkoddan yeni kitap açılmaz.
    func registeredInternalBarcode(_ code: String) -> String? {
        let normalized = ISBNFormatter.normalize(code)
        guard InternalBarcode.isInternal(normalized),
              catalogBooks.contains(where: { ISBNFormatter.normalize($0.isbn ?? "") == normalized }) else { return nil }
        return normalized
    }

    /// Depo taraması: ağa çıkmadan anında kayıt. Bilgiler sonra zenginleştirme kuyruğuyla dolar.
    /// Katalogda zaten olan kitap için davranış `DepoEslesmeKarari` ile belirlenir (nüsha / konum taşı / sor).
    @discardableResult
    func handleDepotScan(_ code: String) -> ScanFeedback {
        guard acceptsActiveCatalogResult() else { return .none }
        guard depoSorusu == nil else {
            appendSerialLog("⏸ Önce açık soruyu yanıtlayın; bu okutma sayılmadı")
            return .error
        }
        guard let isbn = BookEditorValidation.normalizedISBN(code) ?? registeredInternalBarcode(code) else {
            appendSerialLog("⚠️ Kitap ISBN'i değil veya kontrol basamağı hatalı; kayıt yapılmadı")
            return .error
        }
        let existing = depotIndex[isbn].flatMap { $0.isDeleted ? nil : $0 }
        if let existing {
            switch DepoEslesmeKarari.mevcut {
            case .nusha:
                break
            case .konumTasi:
                return konumuTasi(existing, isbn: isbn)
            case .sor:
                depoSorusu = DepoSorusu(kitapID: existing.id, isbn: isbn,
                                        kitapAdi: existing.title.isEmpty ? isbn : existing.title,
                                        eskiKonum: existing.konumMetni ?? CatalogBook.yerAtanmamis,
                                        yeniKonum: "Dolap \(depotCabinet) · Raf \(depotShelf)")
                return .warning
            }
        }
        return depoNushaEkle(isbn: isbn, existing: existing)
    }

    /// Depo kipinde kayıt: yeni kitap ya da kayıtlı kitaba nüsha. Konum taraması başlangıcında seçilen yere yazılır.
    func depoNushaEkle(isbn: String, existing: CatalogBook?) -> ScanFeedback {
        let incoming = Book(title: existing?.title ?? "", author: existing?.author ?? "", isbn: isbn,
            category: depotCategory.isEmpty ? nil : depotCategory, location: depotLocation.isEmpty ? nil : depotLocation,
            quantity: 1, shelf: depotShelf.isEmpty ? nil : depotShelf, cabinet: depotCabinet.isEmpty ? nil : depotCabinet)
        let outcome = saveBook(incoming, source: "barcode")
        guard outcome.succeeded else {
            var taslak = BookDraft(book: incoming)
            if let existing {
                taslak.konumFarki = KonumFarki.metin(eskiDolap: existing.cabinet, eskiRaf: existing.shelf,
                                                     yeniDolap: depotCabinet, yeniRaf: depotShelf)
            }
            batchDrafts.append(taslak); persistPendingQueue()
            appendSerialLog("⚠️ \(isbn) — kaydedilemedi, taslak korunuyor")
            return .error
        }
        serialScanCount += 1
        lastShelfAssignment = nil
        recordSession(outcome)
        switch outcome {
        case .merged(let id, let delta):
            lastScanAction = .merged(id, added: delta)
            let toplam = tarama.nushaEklendi(isbn: isbn, adet: delta)
            appendSerialLog("↺ \(existing?.title.isEmpty == false ? existing!.title : isbn) — adet +\(delta) (bu oturumda \(toplam))")
            return .warning
        case .inserted(let id):
            lastScanAction = .saved(id)
            _ = tarama.nushaEklendi(isbn: isbn, adet: 1)
            let recordID = id
            if let model = try? modelContext.fetch(FetchDescriptor<CatalogBook>(predicate: #Predicate { $0.id == recordID })).first { depotIndex[isbn] = model }
            appendSerialLog("✓ \(isbn) → Dolap \(depotCabinet) Raf \(depotShelf)")
            return .success
        case .updated, .failed:
            return .none
        }
    }

    /// "Her seferinde sor" yanıtı: nüsha eklenir ya da kitabın konumu okutulduğu yere taşınır.
    func depoSorusunuYanitla(_ soru: DepoSorusu, tasi: Bool) {
        depoSorusu = nil
        guard let kitap = catalogBooks.first(where: { $0.id == soru.kitapID }), !kitap.isDeleted else {
            appendSerialLog("⚠️ “\(soru.kitapAdi)” artık katalogda değil")
            return
        }
        if tasi { _ = konumuTasi(kitap, isbn: soru.isbn) } else { _ = depoNushaEkle(isbn: soru.isbn, existing: kitap) }
    }

    /// Kayıtlı kitabın dolap/rafını depo kipinin geçerli yerine taşır; adet artmaz. `lastShelfAssignment` ile geri alınır.
    func konumuTasi(_ book: CatalogBook, isbn: String) -> ScanFeedback {
        let onceki = (dolap: book.cabinet, raf: book.shelf)
        var updated = book.book
        updated.shelf = depotShelf.isEmpty ? nil : depotShelf
        if !depotCabinet.isEmpty { updated.cabinet = depotCabinet }
        do { try CatalogSaveEngine.save(updated, context: modelContext, catalog: catalogBooks) }
        catch {
            recognitionError = "Konum taşınamadı: \(error.localizedDescription)"
            return .error
        }
        serialScanCount += 1
        lastScanAction = nil
        lastShelfAssignment = (bookID: book.id, previousShelf: onceki.raf, previousCabinet: onceki.dolap)
        let fark = KonumFarki.metin(eskiDolap: onceki.dolap, eskiRaf: onceki.raf, yeniDolap: depotCabinet, yeniRaf: depotShelf)
        appendSerialLog("⇢ \(book.title.isEmpty ? isbn : book.title) → Dolap \(depotCabinet) Raf \(depotShelf)"
                        + (fark == nil ? "" : " (\(fark!.replacingOccurrences(of: "Konum farklı: ", with: "")))"))
        return .warning
    }

    func advanceDepotShelf() {
        guard YetkiDurumu.shared.yonetici else { recognitionError = "Bu değişiklik için yönetici kimliği gerekir."; return }
        if let number = Int(depotShelf.trimmingCharacters(in: .whitespaces)) {
            depotShelf = String(number + 1)
        } else {
            depotShelf = "1"
        }
        appendSerialLog("📍 Yeni raf: Dolap \(depotCabinet) Raf \(depotShelf)")
    }

#if os(iOS)
    /// Raf Atama Modu: katalogda zaten kayıtlı kitaplara barkodla raf numarası atar
    /// (dolap bilgisi Excel'den geldi ama raf numarası hiçbir zaman girilmemişti).
    func startShelfAssignSetup() {
        Task { @MainActor in
            guard await kameraHazir() else { return }
            guard await taramaYetkisi("Raf atamayı başlatmak için kimliğinizi doğrulayın") else { return }
            isShowingShelfAssignSetup = true
        }
    }

    func beginShelfAssign(cabinet: String, shelf: String) {
        depotCabinet = cabinet
        depotShelf = shelf
        tarama.sifirla()
        lastScanAction = nil
        lastShelfAssignment = nil
        tarama.kip = .rafAtama
        isShowingBarcodeScanner = true
    }
#endif

    func undoLastShelfAssignment() {
        guard acceptsActiveCatalogResult() else { return }
        guard let last = lastShelfAssignment,
              let book = catalogBooks.first(where: { $0.id == last.bookID }) else { return }
        var previous = book.book
        previous.shelf = last.previousShelf
        previous.cabinet = last.previousCabinet
        do {
            try CatalogSaveEngine.save(previous, context: modelContext, catalog: catalogBooks)
            serialScanCount = max(0, serialScanCount - 1)
            appendSerialLog("↩︎ Son raf ataması geri alındı")
            lastShelfAssignment = nil
        } catch { recognitionError = "Raf ataması geri alınamadı: \(error.localizedDescription)" }
    }

    @discardableResult
    func handleShelfAssignScan(_ code: String) -> ScanFeedback {
        guard acceptsActiveCatalogResult() else { return .none }
        guard YetkiDurumu.shared.yonetici else {
            recognitionError = "Bu değişiklik için yönetici kimliği gerekir."
            return .error
        }
        guard let isbn = BookEditorValidation.normalizedISBN(code) ?? registeredInternalBarcode(code) else {
            appendSerialLog("⚠️ Kitap ISBN'i değil veya kontrol basamağı hatalı; raf ataması yapılmadı")
            return .error
        }
        // Önce etkin kayıt; aynı ISBN'de birden çok etkin kayıt varsa yanlış kitaba raf yazılmaz.
        let eslesenler = catalogBooks.filter { ISBNFormatter.normalize($0.isbn ?? "") == isbn }
        let etkinler = eslesenler.filter { !$0.isWithdrawn }
        guard etkinler.count <= 1 else {
            appendSerialLog("⚠️ \(isbn) için \(etkinler.count) etkin kayıt var; raf atanmadı, Kitaplar'dan birleştirin")
            return .error
        }
        guard let book = etkinler.first else {
            appendSerialLog(eslesenler.isEmpty ? "⚠️ \(isbn) katalogda kayıtlı değil"
                                               : "⚠️ \(isbn) koleksiyondan düşülmüş; raf atanmadı")
            return .error
        }

        let previousShelf = book.shelf
        let previousCabinet = book.cabinet
        var updated = book.book
        updated.shelf = depotShelf
        if !depotCabinet.isEmpty { updated.cabinet = depotCabinet }
        do { try CatalogSaveEngine.save(updated, context: modelContext, catalog: catalogBooks) }
        catch { recognitionError = "Raf ataması kaydedilemedi: \(error.localizedDescription)"; return .error }
        serialScanCount += 1
        // Mevcut kayıt güncelleniyor — genel geri alma (.saved) burada KULLANILMAZ,
        // çünkü o durum kaydı SİLER. Ayrı bir iz sürülür.
        lastShelfAssignment = (bookID: book.id, previousShelf: previousShelf, previousCabinet: previousCabinet)
        appendSerialLog("✓ \(book.title.isEmpty ? isbn : book.title) → Raf \(depotShelf)")
        return .success
    }

    func finishDepotScan() {
        guard acceptsActiveCatalogResult() else { return }
        try? modelContext.save()
        CatalogBackup.saveLight(catalogBooks, force: true)
        depotIndex = [:]
        tarama.kip = .tekli
        if enrichmentPendingCount > 0 {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                isShowingEnrichPrompt = true
            }
        }
    }

    // MARK: - Zenginleştirme kuyruğu (Amazon'dan arka planda doldurma)

    /// Bilgi bekleyen kayıtlar: depo modunda eklenen, adı henüz doldurulmamış ISBN'li kitaplar.
    var enrichmentPendingCount: Int {
        catalogBooks.count { $0.title.isEmpty && !($0.isbn ?? "").isEmpty }
    }

    var enrichmentPercent: Int {
        let total = enrichmentDone + enrichmentPendingCount
        return total > 0 ? enrichmentDone * 100 / total : 0
    }

    func toggleEnrichment() {
        guard acceptsActiveCatalogResult() else { return }
        guard YetkiDurumu.shared.yonetici else { recognitionError = "Bu değişiklik için yönetici kimliği gerekir."; return }
        if isEnriching {
            isEnriching = false
            UserDefaults.standard.set(false, forKey: "enrichmentWasRunning")
            return
        }
        isEnriching = true
        enrichmentDone = 0
        UserDefaults.standard.set(true, forKey: "enrichmentWasRunning")

        Task { @MainActor in
            var skipped = Set<UUID>()
            var consecutiveErrors = 0

            while isEnriching {
                guard acceptsActiveCatalogResult() else { return }
                guard YetkiDurumu.shared.yonetici else { break }
                guard let book = catalogBooks.first(where: {
                    $0.title.isEmpty && !($0.isbn ?? "").isEmpty && !skipped.contains($0.id)
                }) else { break }

                do {
                    if let meta = await BookMetadataService.fetch(isbn: book.isbn ?? "") {
                        try apply(meta, to: book)
                        enrichmentDone += 1
                    }
                    if book.title.isEmpty {
                        // Bulunamadı: tekrar denenmesin, elle düzeltilebilir kalsın
                        skipped.insert(book.id)
                    }
                    consecutiveErrors = 0
                } catch {
                    skipped.insert(book.id)
                    consecutiveErrors += 1
                    if consecutiveErrors >= 5 {
                        bulkMessage = "Ağ sorunu nedeniyle doldurma duraklatıldı. İnternet düzelince yeniden başlatın; kaldığı yerden devam eder."
                        break
                    }
                }

                guard acceptsActiveCatalogResult() else { return }
                if enrichmentDone % 10 == 0 {
                    try? modelContext.save()
                }
                // Amazon'un engellememesi için istekler arası bekleme
                try? await Task.sleep(for: .seconds(2))
            }

            guard acceptsActiveCatalogResult() else { return }
            try? modelContext.save()
            CatalogBackup.saveLight(catalogBooks, force: true)
            if isEnriching && enrichmentDone > 0 {
                bulkMessage = "\(enrichmentDone) kitabın bilgileri dolduruldu."
            }
            isEnriching = false
            // Bekleyen kalmadıysa işaret temizlenir; kaldıysa açılışta devam eder
            if enrichmentPendingCount == 0 {
                UserDefaults.standard.set(false, forKey: "enrichmentWasRunning")
            }
        }
    }

#if os(iOS)
    /// Barkod okutarak katalogda arama: kitabın barkodunu okut, arama kutusuna ISBN yazılır.
    func startSearchScan() {
        Task { @MainActor in
            guard await kameraHazir() else { return }
            tarama.hata = nil
            tarama.kip = .arama
            isShowingBarcodeScanner = true
        }
    }
#endif

    func handleSearchScan(_ code: String) {
        tarama.kip = .tekli
        let isbn = ISBNFormatter.repair(code)
        guard !isbn.isEmpty else {
            recognitionError = "Okunan barkod geçerli bir ISBN değil."
            return
        }
        searchText = isbn
        if !catalogBooks.contains(where: { ISBNFormatter.normalize($0.isbn ?? "") == isbn }) {
            bulkMessage = "Bu barkod katalogda kayıtlı değil: \(isbn)"
        }
    }

    func closeBarcodeScanner() {
        guard acceptsActiveCatalogResult() else { return }
        isShowingBarcodeScanner = false
        // Kapakta okunan kamera hatası kapanınca bir uyarı olarak da kalır
        if let hata = tarama.hata {
            tarama.hata = nil
            recognitionError = hata
        }
        if isTorchOn {
            isTorchOn = false
            ScannerTorch.set(on: false)
        }
        switch tarama.kip {
        case .rafAtama:
            tarama.kip = .tekli
            try? modelContext.save()
            CatalogBackup.saveLight(catalogBooks, force: true)
        case .depo:
            finishDepotScan()
        case .seri:
            tarama.kip = .tekli
            if UserDefaults.standard.bool(forKey: SeriTaramaAyari.cevrimdisiOnce), enrichmentPendingCount > 0 {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    isShowingEnrichPrompt = true
                }
            }
            if !batchDrafts.isEmpty {
                // Tam ekran kapanışı bitince onay listesini aç
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    isShowingBatchReview = !batchDrafts.isEmpty
                }
            }
        case .arama, .tekli:
            tarama.kip = .tekli
        }
    }

    // MARK: - Toplu işlemler

    func selectedBooks() -> [CatalogBook] {
        catalogBooks.filter { selectedBookIDs.contains($0.id) }
    }

    func finishBulkOperation(message: String) throws {
        try requireActiveCatalog()
        for previous in bulkUndoSnapshot {
            if let book = catalogBooks.first(where: { $0.id == previous.id && !$0.isDeleted }) {
                book.fieldMetadata = BookFieldMetadata.stampChanges(before: previous, after: book.book, source: "manual").fieldMetadata
                book.refreshSearchKey()
            }
        }
        try modelContext.save()
        bulkUndoAfterSnapshots = Dictionary(uniqueKeysWithValues: catalogBooks.filter { book in
            !book.isDeleted && bulkUndoSnapshot.contains(where: { $0.id == book.id })
        }.map { ($0.id, $0.book) })
        CatalogBackup.saveLight(catalogBooks)
        selectedBookIDs.removeAll()
        withAnimation { isSelecting = false }
        bulkMessage = message
    }

    func bulkSetStatus(_ status: String) {
        guard acceptsActiveCatalogResult() else { return }
        guard YetkiDurumu.shared.yonetici else { recognitionError = "Bu değişiklik için yönetici kimliği gerekir."; return }
        let books = selectedBooks()
        captureUndoSnapshot(of: books)
        for book in books {
            book.readingStatus = status
        }
        do { try finishBulkOperation(message: "\(books.count) kitabın durumu “\(status)” yapıldı.") }
        catch { restoreBulkSnapshotAfterFailure(error) }
    }

    func bulkAssign(_ assignment: BulkAssignment) {
        guard acceptsActiveCatalogResult() else { return }
        guard YetkiDurumu.shared.yonetici else { recognitionError = "Bu değişiklik için yönetici kimliği gerekir."; return }
        let books = selectedBooks()
        captureUndoSnapshot(of: books)
        for book in books {
            if !assignment.location.isEmpty { book.location = assignment.location }
            if !assignment.cabinet.isEmpty { book.cabinet = assignment.cabinet }
            if !assignment.shelf.isEmpty { book.shelf = assignment.shelf }
            if !assignment.category.isEmpty { book.category = assignment.category }
        }
        do { try finishBulkOperation(message: "\(books.count) kitaba konum/kategori atandı.") }
        catch { restoreBulkSnapshotAfterFailure(error) }
    }

    func bulkFindReplace(field: BulkEditableField, find: String, replace: String) throws {
        try requireActiveCatalog()
        guard YetkiDurumu.shared.yonetici else { throw CatalogSaveEngine.SaveError(message: "Bu değişiklik için yönetici kimliği gerekir.") }
        guard !find.isEmpty else { return }
        let books = selectedBooks()
        captureUndoSnapshot(of: books)

        var changed = 0
        for book in books {
            let current = currentValue(of: field, in: book)
            let updated = BulkTextReplace.replacing(find, with: replace, in: current)
            guard updated != current else { continue }
            setValue(updated, of: field, in: book)
            changed += 1
        }
        do { try finishBulkOperation(message: "\(changed) kitapta \(field.rawValue.lowercased()) alanı güncellendi.") }
        catch { restoreBulkSnapshotAfterFailure(error); throw error }
    }

    func restoreBulkSnapshotAfterFailure(_ error: Error) {
        for snapshot in bulkUndoSnapshot {
            catalogBooks.first(where: { $0.id == snapshot.id })?.update(from: snapshot)
        }
        recognitionError = "Toplu değişiklik kaydedilemedi: \(error.localizedDescription)"
    }

    func currentValue(of field: BulkEditableField, in book: CatalogBook) -> String {
        switch field {
        case .title: return book.title
        case .author: return book.author
        case .publisher: return book.publisher ?? ""
        case .category: return book.category ?? ""
        case .notes: return book.notes
        }
    }

    func setValue(_ value: String, of field: BulkEditableField, in book: CatalogBook) {
        switch field {
        case .title: book.title = value
        case .author: book.author = value
        case .publisher: book.publisher = value.isEmpty ? nil : value
        case .category: book.category = value.isEmpty ? nil : value
        case .notes: book.notes = value
        }
    }

    func bulkDeleteSelected() {
        guard acceptsActiveCatalogResult() else { return }
        let books = selectedBooks()
        captureUndoSnapshot(of: books)
        let ids = Set(books.map(\.id))
        do {
            try TrashStore.moveVerified(books, context: modelContext, reason: "Toplu silme")
            bulkUndoDeletedIDs = ids
            bulkUndoAfterSnapshots = [:]
            selectedBookIDs.removeAll()
            isSelecting = false
            bulkMessage = "\(ids.count) kitap çöp kutusuna taşındı."
            CatalogBackup.saveLight(catalogBooks)
        } catch { recognitionError = "Silme kaydedilemedi: \(error.localizedDescription)" }
    }

    /// Seçili kitaplar için sırt etiketi PDF'i hazırlar.
    func printSpineLabels() {
        isPreparingLabels = true
        let infos = selectedBooks().map { book in
            SpineLabelBuilder.LabelInfo(
                callNumber: SpineLabelBuilder.callNumber(category: book.category, author: book.author, location: book.location),
                title: book.title,
                accessionCode: book.accessionCode ?? "",
                barcodeValue: ISBNFormatter.normalize(book.isbn ?? ""),
                category: book.category ?? "",
                bookID: book.id
            )
        }
        Task { @MainActor in
            defer { isPreparingLabels = false }
            labelPDFData = await Task.detached(priority: .userInitiated) {
                SpineLabelBuilder.build(infos)
            }.value
            isExportingLabels = true
        }
    }

    /// Toplu işlem öncesi kayıtların tam kopyasını alır — "Toplu İşlemi Geri Al" bunu kullanır.
    func captureUndoSnapshot(of books: [CatalogBook]) {
        bulkUndoSnapshot = books.map(\.book)
        bulkUndoAfterSnapshots = [:]
        bulkUndoDeletedIDs = []
    }

    /// Son toplu işlemi (durum/konum/silme) eski hâline döndürür.
    func undoLastBulkOperation() {
        guard acceptsActiveCatalogResult() else { return }
        guard !bulkUndoSnapshot.isEmpty else { return }
        let count = bulkUndoSnapshot.count
        do {
            try SchoolLibraryService.requireAdmin()
            let current = try modelContext.fetch(FetchDescriptor<CatalogBook>())
            for old in bulkUndoSnapshot {
                let existing = current.first { $0.id == old.id }
                if bulkUndoDeletedIDs.contains(old.id) {
                    guard existing == nil else { throw CatalogSaveEngine.SaveError(message: "“\(old.title)” yeniden oluşturulmuş; sonraki değişikliklerin üzerine yazılmadı.") }
                } else {
                    guard let existing, let expected = bulkUndoAfterSnapshots[old.id], existing.book == expected else {
                        throw CatalogSaveEngine.SaveError(message: "“\(old.title)” işlemden sonra değişmiş; sonraki değişikliklerin üzerine yazılmadı.")
                    }
                }
            }
            _ = try CatalogSaveEngine.saveBatch(bulkUndoSnapshot, context: modelContext, catalog: current,
                mergeWithinBatch: false, matchByEdition: false)
            for id in bulkUndoDeletedIDs { TrashStore.remove(id: id) }
            CatalogBackup.saveLight(catalogBooks, force: true)
            bulkUndoSnapshot = []
            bulkUndoAfterSnapshots = [:]
            bulkUndoDeletedIDs = []
            bulkMessage = "\(count) kayıt eski hâline döndürüldü."
        } catch { recognitionError = "Toplu işlem geri alınamadı: \(error.localizedDescription)" }
    }

    func isIncomplete(_ book: CatalogBook) -> Bool {
        book.isbn?.isEmpty ?? true
            || book.author.isEmpty
            || isPlaceholderAuthor(book.author)
            || book.publisher?.isEmpty ?? true
            || book.coverData == nil
    }

    /// İçe aktarılan kataloglarda gerçek yazar yerine geçen genel ifadeler
    /// ("Kolektif", "Anonim" vb.) — bunlar da eksik sayılır ve doldurulmaya çalışılır.
    func isPlaceholderAuthor(_ author: String) -> Bool {
        let placeholders = ["kolektif", "anonim", "bilinmiyor", "derleme", "yazar bilinmiyor", "various"]
        let normalized = author.trimmingCharacters(in: .whitespaces).lowercased(with: Locale(identifier: "tr_TR"))
        return placeholders.contains(normalized)
    }

    /// ISBN'i olan tüm eksik kayıtları sırayla Amazon'dan tamamlar.
    func bulkCompleteFromAmazon() {
        guard acceptsActiveCatalogResult() else { return }
        let targets = catalogBooks.filter { !($0.isbn ?? "").isEmpty && isIncomplete($0) }
        guard !targets.isEmpty else {
            bulkMessage = "ISBN'i olan eksik bilgili kayıt bulunamadı."
            return
        }

        isRecognizing = true
        scanTotal = targets.count
        scanProgress = 0
        isCancelRequested = false

        Task { @MainActor in
            defer {
                isRecognizing = false
                scanTotal = 0
                scanProgress = 0
                isCancelRequested = false
            }

            var updated = 0
            var missed = 0
            for (index, book) in targets.enumerated() {
                guard acceptsActiveCatalogResult() else { return }
                if isCancelRequested { break }
                // Önceki kayıtların 2 sn'lik beklemeleri sırasında bu kitap silinmiş olabilir
                guard isStillInCatalog(book) else {
                    scanProgress += 1
                    continue
                }
                do {
                    if let meta = await BookMetadataService.fetch(
                        isbn: book.isbn ?? "",
                        title: book.title,
                        author: book.author,
                        publisher: book.publisher ?? ""
                    ) {
                        try apply(meta, to: book)
                        updated += 1
                    } else {
                        missed += 1
                    }
                } catch {
                    missed += 1
                }
                guard acceptsActiveCatalogResult() else { return }
                scanProgress += 1
                // Amazon'un istekleri engellememesi için kayıtlar arası bekleme
                if index < targets.count - 1 {
                    try? await Task.sleep(for: .seconds(2))
                }
            }

            guard acceptsActiveCatalogResult() else { return }
            try? modelContext.save()
            CatalogBackup.saveLight(catalogBooks)
            bulkMessage = "Amazon'dan tamamlanan: \(updated) kitap. Bulunamayan/hatalı: \(missed)."
        }
    }

    func processCSVImport(_ result: Result<[URL], Error>) {
        guard acceptsActiveCatalogResult() else { return }
        do {
            guard let url = try result.get().first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let books = CSVImporter.parse(data)
            guard !books.isEmpty else {
                bulkMessage = "Dosyadan kitap okunamadı. İlk satırda başlıklar (Kitap Adı, Yazar…) olmalı."
                return
            }
            csvPreviewBooks = books
            isShowingCSVPreview = true
        } catch {
            bulkMessage = "İçe aktarma başarısız: \(error.localizedDescription)"
        }
    }

    /// Yedek JSON dosyasından kayıtları geri yükler. Mevcut kayıtlar silinmez;
    /// aynı kitaplar mükerrer kontrolünden geçtiği için katalog bozulmaz.
    /// Eski `KitapKatalogu-Yedek.json` dosyasını tam arşiv kapılarından geçirir: önizleme, işlem öncesi
    /// doğrulanmış tam yedek ve yönetici denetimi. Eskiden kayıtlar doğrudan toplu kayda düşüyordu.
    func restoreFromBackup(_ result: Result<[URL], Error>) {
        guard acceptsActiveCatalogResult() else { return }
        guard !isReadingArchive else { return }
        isReadingArchive = true
        Task { @MainActor in
            defer { isReadingArchive = false }
            do {
                guard let url = try result.get().first else { return }
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                let data = try await KoordineliDosyaOkuma.oku(url)
                let onizleme = try await ArchiveImportCoordinator.prepareAsync(jsonBackup: data, context: modelContext)
                try requireActiveCatalog()
                jsonYedekVerisi = data
                jsonYedekOnizlemesi = onizleme
            } catch {
                bulkMessage = "Geri yükleme başarısız: \(error.localizedDescription)"
            }
        }
    }

    /// Başlangıç kataloğuna ait demirbaş kodlarını (Excel'in "Envanter Kodları" sütunu)
    /// ISBN eşleşmesiyle geriye işler. Tek seferliktir.
    func applyAccessionCodesIfNeeded() {
        guard acceptsActiveCatalogResult() else { return }
        guard !SeedCatalog.isEnrichmentApplied else { return }
        let codes = SeedCatalog.loadAccessionCodes()
        guard !codes.isEmpty else {
            SeedCatalog.markEnrichmentApplied()
            return
        }

        var updated = 0
        for book in catalogBooks {
            let isbn = ISBNFormatter.normalize(book.isbn ?? "")
            guard !isbn.isEmpty, let code = codes[isbn], book.accessionCode == nil else { continue }
            book.accessionCode = code
            updated += 1
        }
        if updated > 0 {
            try? modelContext.save()
        }
        SeedCatalog.markEnrichmentApplied()
#if DEBUG
        print("📚 SEED: \(updated) kitaba demirbaş kodu işlendi")
#endif
    }

    /// Uygulamayla gelen başlangıç kataloğunu ilk açılışta bir kez içe aktarır.
    ///
    /// Asenkron olduğu için çağıran, demirbaş kodu işleme gibi kataloğa bağlı adımları
    /// bu fonksiyon BİTTİKTEN sonra çalıştırmalı (aksi hâlde boş katalogda "uygulandı"
    /// işaretlenir ve kodlar bir daha hiç işlenmez).
    func importSeedCatalogIfNeeded() async {
        guard acceptsActiveCatalogResult() else { return }
        guard !SeedCatalog.isImported, !isSeedImportRunning else { return }

        // Görünüm yeniden kurulup `.task` tekrar tetiklenirse ikinci bir içe aktarma
        // başlamasın; aksi hâlde aynı ISBN'lerin adedi iki kez artar.
        isSeedImportRunning = true
        isRecognizing = true

        do {
            defer {
                isSeedImportRunning = false
                isRecognizing = false
                scanTotal = 0
                scanProgress = 0
            }

            // Arşivi (ZIP + JSON + kapaklar) ARKA PLANDA aç: ilk açılışta ana iş
            // parçacığında yapılırsa iOS'un 20 saniyelik açılış bekçisi uygulamayı
            // öldürür (0x8BADF00D). Ana iş parçacığı yalnızca veritabanına yazar.
            let seed = await Task.detached(priority: .userInitiated) {
                SeedCatalog.load()
            }.value
            guard acceptsActiveCatalogResult() else { return }
#if DEBUG
            print("📚 SEED: arşivden \(seed.count) kitap okundu, kapaklı: \(seed.filter { $0.coverData != nil }.count)")
#endif
            guard !seed.isEmpty else {
#if DEBUG
                print("📚 SEED: arşiv boş ya da bulunamadı")
#endif
                SeedCatalog.markImported()
                return
            }

            scanTotal = seed.count
            scanProgress = 0

            guard YetkiDurumu.shared.yonetici else { return }
            var added = 0
            for start in stride(from: 0, to: seed.count, by: 100) {
                let batch = Array(seed[start..<min(start + 100, seed.count)])
                do {
                    try requireActiveCatalog()
                    let current = try modelContext.fetch(FetchDescriptor<CatalogBook>())
                    let existingIDs = Set(current.map(\.id))
                    let incoming = batch.filter { !existingIDs.contains($0.id) }
                    let outcomes = try CatalogSaveEngine.saveBatch(incoming, context: modelContext, catalog: current,
                        mergeWithinBatch: true, source: "api")
                    added += outcomes.filter { if case .inserted = $0 { return true }; return false }.count
                    scanProgress = start + batch.count
                    await Task.yield()
                } catch {
                    recognitionError = "Başlangıç kataloğu kaydedilemedi; tekrar denenebilir: \(error.localizedDescription)"
                    return
                }
            }
            guard acceptsActiveCatalogResult() else { return }
            CatalogBackup.saveLight(catalogBooks, force: true)
            SeedCatalog.markImported()
#if DEBUG
            print("📚 SEED: içe aktarma bitti — eklenen \(added), katalogdaki toplam \(catalogBooks.count)")
#endif
            bulkMessage = "Başlangıç kataloğu yüklendi: \(added) kitap eklendi."
        }
    }

    /// Arşivi diske akışla yazar (bellekte tam kopya tutulmaz), doğrulayıp kaydetme ekranını açar.
    func prepareArchive() {
        guard acceptsActiveCatalogResult() else { return }
        try? BackupExportStatusStore.recordAttempt()
        isPreparingExport = true
        Task { @MainActor in
            defer { isPreparingExport = false }
            let klasor = FileManager.default.temporaryDirectory
            let hedef = klasor.appendingPathComponent("KitapBul-Arsiv-\(UUID().uuidString.prefix(8)).zip")
            let gecici = klasor.appendingPathComponent(hedef.lastPathComponent + ".\(UUID().uuidString).tmp")
            do {
                try await AutoArchive.writeStreaming(context: modelContext, target: hedef, temporary: gecici)
                try requireActiveCatalog()
                archiveFileURL = hedef
                isExportingArchive = true
            } catch {
                try? FileManager.default.removeItem(at: hedef)
                try? FileManager.default.removeItem(at: gecici)
                guard acceptsActiveCatalogResult() else { return }
                try? BackupExportStatusStore.recordFailure(error.localizedDescription)
                bulkMessage = "Arşiv hazırlanamadı: \(error.localizedDescription)"
            }
        }
    }

    /// Excel dosyasını arka planda hazırlar, sonra paylaşım ekranını açar.
    func prepareExcel() {
        guard acceptsActiveCatalogResult() else { return }
        isPreparingExport = true
        let books = catalogBooks.map(\.book)
        Task { @MainActor in
            defer { isPreparingExport = false }
            let data = await Task.detached(priority: .userInitiated) {
                ExcelWorkbookBuilder.makeWorkbook(books: books)
            }.value
            guard acceptsActiveCatalogResult() else { return }
            excelData = data
            isExportingExcel = true
        }
    }

    /// Kapaklar dahil ZIP arşivinden geri yükler.
    func restoreFromArchive(_ result: Result<[URL], Error>) {
        guard acceptsActiveCatalogResult() else { return }
        guard !isReadingArchive else { return }
        isReadingArchive = true
        Task { @MainActor in
            defer { isReadingArchive = false }
            do {
                guard let url = try result.get().first else { return }
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                try SchoolLibraryService.requireAdmin()
                let before = try FullArchive.snapshot(context: modelContext)
                let data = try await ArchiveBackgroundWork.readValidatedInput(from: url)
                try requireActiveCatalog()
                try ArchiveImportCoordinator.requireUnchanged(before, context: modelContext)
                archiveImportSourceData = data
                isShowingArchiveChoice = true
            } catch { bulkMessage = "Arşiv geri yüklenemedi: \(error.localizedDescription)" }
        }
    }

    /// Önizlemesi onaylanan CSV kitaplarını kaydeder; ardından Amazon tamamlama önerir.
    func importPreviewedCSV() {
        guard acceptsActiveCatalogResult() else { return }
        beginAddSession()
        let books = csvPreviewBooks
        csvPreviewBooks = []

        Task { @MainActor in
            let saved = await saveBooksInBulk(books)
            guard acceptsActiveCatalogResult() else { return }
            guard saved == books.count else {
                // Durdurma/hata sonrası "hepsi aktarıldı" denmez; hata uyarısı zaten gösteriliyorsa ezilmez
                if recognitionError == nil { bulkMessage = "\(saved) kitap içe aktarıldı; kalan \(books.count - saved) kayıt onay kuyruğunda bekliyor." }
                return
            }

            if catalogBooks.contains(where: { !($0.isbn ?? "").isEmpty && isIncomplete($0) }) {
                isShowingAmazonFollowUp = true
            } else {
                bulkMessage = "\(books.count) kitap içe aktarıldı."
            }
        }
    }

    var recognitionErrorBinding: Binding<Bool> {
        Binding(
            get: { recognitionError != nil },
            set: { isPresented in
                if !isPresented {
                    recognitionError = nil
                }
            }
        )
    }

    /// Aynı kitap mı? Ad benzer ve (yazar boşsa ya da) yazar benzer.
    func isSameTitleAndAuthor(_ existing: CatalogBook, _ book: Book) -> Bool {
        CatalogMatcher.isSimilar(existing.title, book.title)
            && (book.author.isEmpty || existing.author.isEmpty
                || CatalogMatcher.isSimilar(existing.author, book.author))
    }

    /// Toplu içe aktarma (CSV, yedek, arşiv) için tek geçişli kayıt.
    ///
    /// `saveBook` her kitapta `save()` + tam yedek yazıp kataloğu üç kez tarıyordu;
    /// 2.575 satırlık CSV'de ana iş parçacığı ~45 sn kilitleniyor, telefonda
    /// gigabaytlarca gereksiz disk yazması oluşuyordu. Burada dizinler BİR KEZ
    /// kurulur, 100 kayıtta bir kaydedilir ve arayüz nefes alır.
    ///
    /// `mergeWithinBatch`: aynı partideki kayıtlar birbiriyle de mükerrer kontrolünden
    /// geçsin mi? CSV için evet; yedek/arşiv geri yüklemede HAYIR — yedekteki aynı
    /// ISBN'li iki ayrı kayıt (farklı demirbaş kodlu iki nüsha) ayrı kayıt olarak
    /// geri gelmeli, tek kayda adet olarak katlanıp bilgileri kaybolmamalı.
    /// Kaydedilen kayıt sayısını döndürür; durdurma ya da hata kalanları onay kuyruğuna bırakır.
    @discardableResult
    func saveBooksInBulk(_ books: [Book], mergeWithinBatch: Bool = true) async -> Int {
        guard acceptsActiveCatalogResult() else { return 0 }
        guard !books.isEmpty else { return 0 }
        var saved = 0
        bulkPendingBooks = books
        persistScanSession()
        isRecognizing = true
        isCancelRequested = false
        scanTotal = books.count
        scanProgress = 0
        defer { isRecognizing = false; scanTotal = 0; scanProgress = 0; isCancelRequested = false }
        for start in stride(from: 0, to: books.count, by: 100) {
            if isCancelRequested { break }
            let end = min(start + 100, books.count)
            let batch = Array(books[start..<end])
            do {
                try requireActiveCatalog()
                let catalog = try modelContext.fetch(FetchDescriptor<CatalogBook>())
                let outcomes = try CatalogSaveEngine.saveBatch(batch, context: modelContext,
                    catalog: catalog, mergeWithinBatch: mergeWithinBatch)
                bulkPendingBooks.removeAll { pending in batch.contains { $0.id == pending.id } }
                for (book, outcome) in zip(batch, outcomes) {
                    lastSavedOperationID = book.id
                    recordSession(outcome)
                }
                scanProgress = end
                saved = end
                await Task.yield()
                guard acceptsActiveCatalogResult() else { return saved }
            } catch {
                guard acceptsActiveCatalogResult() else { return saved }
                batchDrafts.append(contentsOf: books[start...].map(BookDraft.init(book:)))
                bulkPendingBooks = []
                persistPendingQueue()
                recognitionError = "\(scanProgress) kayıt kaydedildi; kalan \(books.count - start) taslak korunuyor: \(error.localizedDescription)"
                break
            }
        }
        guard acceptsActiveCatalogResult() else { return saved }
        if isCancelRequested {
            batchDrafts.append(contentsOf: bulkPendingBooks.map(BookDraft.init(book:)))
            bulkPendingBooks = []
            persistPendingQueue()
        }
        CatalogBackup.saveLight(catalogBooks, force: true)
        return saved
    }

    func currentCatalogLease() throws -> ActiveCatalogLease {
        if catalogLease == nil { catalogLease = try ActiveCatalogLease.captureCurrent(context: modelContext) }
        guard let lease = catalogLease else { throw ActiveCatalogLease.Expired() }
        try lease.requireCurrent(context: modelContext)
        return lease
    }

    func requireActiveCatalog() throws {
        _ = try currentCatalogLease()
    }

    func acceptsActiveCatalogResult() -> Bool {
        do { try requireActiveCatalog(); return true }
        catch {
            isCancelRequested = true
            recognitionError = error is CancellationError
                ? "İşlem iptal edildi; sonuç kaydedilmedi."
                : error.localizedDescription
            return false
        }
    }

    @discardableResult
    func saveBook(_ book: Book, source: String = "manual") -> SaveOutcome {
        do {
            let lease = try currentCatalogLease()
            return try lease.performCurrent(context: modelContext) {
                lastSavedOperationID = nil
                if !catalogBooks.contains(where: { $0.id == book.id }) {
                    if scanSession == nil { beginAddSession() }
                    if var session = scanSession {
                        session.pendingBooks.removeAll { $0.id == book.id }
                        session.pendingBooks.append(book)
                        scanSession = session
                        try ScanSessionStore.save(session)
                    }
                }
                let outcome = try CatalogSaveEngine.save(book, context: modelContext, catalog: catalogBooks, source: source,
                    decision: scanSession?.saveDecisions?[book.id] ?? .automatic)
                if try CatalogSaveEngine.receipt(for: book.id, context: modelContext) != nil {
                    lastSavedOperationID = book.id
                    lastScanOperationID = book.id
                }
                if case .inserted(let id) = outcome,
                   (book.category ?? "").isEmpty || book.notes.isEmpty || (book.publisher ?? "").isEmpty {
                    EnrichmentQueue.enqueue(id)
                }
                CatalogBackup.saveLight(catalogBooks)
                return outcome
            }
        } catch {
            recognitionError = "Kaydedilemedi: \(error.localizedDescription). Taslak korunuyor."
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Toplu onay kuyruğu

    /// Onay kuyruğunu diske yazar. Yazılamazsa kuyruk bellekte kalır ve kullanıcıya şeritte söylenir;
    /// "Yeniden dene" aynı yazmayı tekrarlar. `hemen`: oturum JSON'u da beklemeden yazılır (arka plana geçerken).
    func persistPendingQueue(hemen: Bool = false) {
        guard acceptsActiveCatalogResult() else { return }
        // Yarım kalan kuyruk için soru açıkken disk dosyası henüz bellekte değil: boş liste onu silmesin
        if pendingRestoredTaslaklar.isEmpty {
            do {
                try PendingQueueStore.save(batchDrafts.map { KuyrukTaslagi(draft: $0, book: book(from: $0)) })
                kuyrukKayitHatasi = nil
            } catch {
                kuyrukKayitHatasi = "Kuyruk kaydedilemedi: \(batchDrafts.count) kitap bellekte. \(error.localizedDescription)"
                AccessibilityNotification.Announcement("Kuyruk kaydedilemedi").post()
            }
        }
        if hemen { persistScanSessionNow() } else { persistScanSession() }
    }

    /// Birden çok taslağı onay kuyruğuna yönlendirir; tek taslak doğrudan düzenleyiciye gider.
    func routeBatch(_ drafts: [BookDraft]) {
        guard acceptsActiveCatalogResult() else { return }
        guard !drafts.isEmpty else { return }
        if drafts.count == 1 && batchDrafts.isEmpty {
            draft = drafts[0]
            persistScanSession()
        } else {
            batchDrafts.append(contentsOf: drafts)
            persistPendingQueue()
            isShowingBatchReview = true
        }
    }

    /// Onay kuyruğundaki adı dolu tüm taslakları kaydeder; adı boşlar kuyrukta kalır.
    /// Sonuç cümlesi döner: kuyruk ekranı açık kalırsa listenin üstünde gösterir.
    @discardableResult
    func saveBatchDrafts() -> String? {
        guard acceptsActiveCatalogResult() else { return nil }
        var savedCount = 0
        var remaining: [BookDraft] = []
        for pending in batchDrafts {
            if pending.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                remaining.append(pending)
                continue
            }
            let outcome = saveBook(book(from: pending))
            if outcome.succeeded {
                recordSession(outcome)
                savedCount += 1
            } else {
                remaining.append(pending)
            }
        }
        batchDrafts = remaining
        persistPendingQueue()
        return remaining.isEmpty
            ? "\(savedCount) kitap kataloğa eklendi."
            : "\(savedCount) kitap eklendi; eksik veya kaydedilemeyen \(remaining.count) kayıt kuyrukta bekliyor."
    }

    /// OCR taslağını mevcut katalogla karşılaştırır: aynı kitap katalogda varsa oradaki
    /// doğru yazım benimsenir ve ISBN devralınır — kayıt sırasında mükerrer oluşmaz,
    /// mevcut kaydın adedi artar.
    func reconcileWithCatalog(_ draft: inout BookDraft) {
        let draftISBN = ISBNFormatter.normalize(draft.isbn)
        // Ad benzerliği tek başına başka bir baskının ISBN'ini taslağa taşımaz.
        guard !draftISBN.isEmpty else { return }
        let match = catalogBooks.first { book in
            ISBNFormatter.normalize(book.isbn ?? "") == draftISBN
                && CatalogSaveEngine.sameEdition(book, draft.snapshot)
        }
        guard let match else { return }

        draft.title = match.title
        if !match.author.isEmpty { draft.author = match.author }
        if draft.isbn.isEmpty, let isbn = match.isbn, !isbn.isEmpty {
            draft.isbn = isbn
        }
        if draft.publisher.isEmpty, let publisher = match.publisher {
            draft.publisher = publisher
        }
        draft.lowConfidenceFields.remove("title")
        draft.lowConfidenceFields.remove("author")
    }

    /// `tarayiciKapaniyor`: kod tekli tarayıcıdan geldi ve tarayıcı kapanıyor; katalogdaki kitap sorusu
    /// kapanış bitince sorulur (aynı anda ikinci sunum yapılamaz).
    /// Dönüş değeri yalnız seri taramada (`enqueueOnly`) anlamlıdır: sayaç ve titreşim sonuca göre verilir.
    @discardableResult
    func handleScannedISBN(_ value: String, enqueueOnly: Bool = false, backPhoto: Data? = nil,
                                   tarayiciKapaniyor: Bool = false) -> ScanFeedback {
        guard let isbn = BookEditorValidation.normalizedISBN(value) ?? registeredInternalBarcode(value) else {
            if enqueueOnly { appendSerialLog("⚠️ Kitap ISBN'i değil veya kontrol basamağı hatalı; kayıt yapılmadı") }
            else { recognitionError = "Okunan barkod geçerli bir kitap ISBN'i değil. ISBN-10 veya 978/979 ile başlayan ISBN-13 gerekir." }
            return .error
        }

        // Önce etkin kayıt: aynı ISBN'li düşülmüş kayıt önde olsa da nüsha etkin kayda eklenir
        if let existing = KatalogdakiKitapOnayi.eslesenKayit(isbn: isbn, in: catalogBooks) {
            guard enqueueOnly else {
                // Tekli taramada adet sessizce artmaz: "Nüsha ekle (+1)", "Kitabı aç" ya da "Vazgeç".
                // Ekle kartı, Ana Sayfa kısayolu, kitapbul://ekle/barkod, widget ve Kitaplar'daki
                // "Bu ISBN ile kataloğa ekle" aynı yoldan gelir.
                let onay = KatalogdakiKitapOnayi(kitap: existing, isbn: isbn, arkaKapak: backPhoto)
                if tarayiciKapaniyor {
                    // Sabit bekleme kapanış animasyonundan kısa kalabiliyordu; soru `tarayiciKapandi`'da sorulur
                    bekleyenKatalogOnayi = onay
                } else {
                    katalogdakiKitap = onay
                }
                return .success
            }
            // Seri tarama değişmez: her okutma bilinçli bir nüshadır, günlükte ve "Geri Al"da görünür
            let dusulmus = existing.isWithdrawn
            let ad = existing.title.isEmpty ? isbn : existing.title
            let outcome = nushaArtir(existing, isbn: isbn)
            guard outcome.succeeded else {
                appendSerialLog("⚠️ \(ad) — kaydedilemedi, taslak kuyrukta")
                return .error
            }
            serialScanCount += 1
            switch outcome {
            case .inserted:
                // Yalnız düşülmüş kayıt vardı: nüsha eklenmez, yeni kayıt açılır
                _ = tarama.nushaEklendi(isbn: isbn, adet: 1)
                appendSerialLog("✓ \(ad) — yeni kayıt açıldı" + (dusulmus ? " (düşülmüş kayıt var)" : ""))
            case .merged(_, let added):
                let toplam = tarama.nushaEklendi(isbn: isbn, adet: added)
                appendSerialLog("↺ \(ad) — adet +\(added) (bu oturumda \(toplam))")
            case .updated, .failed:
                break
            }
            return .warning
        } else if enqueueOnly {
            // Seri tarama: ağ işleri tek sıralı işçide toplanır. Hızlı taramada
            // onlarca eşzamanlı istek birikip donmaya/engellenmeye yol açamaz.
            // Kuyruk oturumla birlikte diske yazılır; uygulama kapanırsa açılışta kaldığı yerden sürer.
            if scanSession == nil { beginAddSession() }
            // Çevrimdışı önce: ISBN ve konum anında kaydedilir, künye sonra "Bilgi bekleyen" kuyruğuyla dolar
            if UserDefaults.standard.bool(forKey: SeriTaramaAyari.cevrimdisiOnce) { return seriAnindaKaydet(isbn) }
            serialScanCount += 1
            tarama.isbnEkle(isbn)
            persistScanSession()
            startSerialWorker()
            return .success
        } else {
            kunyeyleFormuAc(isbn: isbn, backPhoto: backPhoto)
            return .success
        }
    }

    /// Çevrimdışı-önce seri tarama: ağ beklemeden adsız, ISBN'li kayıt açılır (depo modundaki gibi).
    /// Ad, yazar ve kapak sonradan zenginleştirme kuyruğuyla dolar; dolmayanlar "Bilgi bekleyen" olarak kalır.
    func seriAnindaKaydet(_ isbn: String) -> ScanFeedback {
        let incoming = Book(title: "", author: "", isbn: isbn,
            category: scanAssignment.category.isEmpty ? nil : scanAssignment.category,
            location: scanAssignment.location.isEmpty ? nil : scanAssignment.location,
            quantity: 1,
            shelf: scanAssignment.shelf.isEmpty ? nil : scanAssignment.shelf,
            cabinet: scanAssignment.cabinet.isEmpty ? nil : scanAssignment.cabinet)
        let outcome = saveBook(incoming, source: "barcode")
        guard outcome.succeeded else {
            batchDrafts.append(BookDraft(book: incoming)); persistPendingQueue()
            appendSerialLog("⚠️ \(isbn) — kaydedilemedi, taslak kuyrukta")
            return .error
        }
        serialScanCount += 1
        recordSession(outcome)
        if case .inserted(let id) = outcome { lastScanAction = .saved(id) }
        _ = tarama.nushaEklendi(isbn: isbn, adet: 1)
        appendSerialLog("✓ \(isbn) kaydedildi — künye sonra dolacak")
        return .success
    }

    /// Tekli tarayıcıdan bırakılan katalogdaki kitap sorusu, tarayıcının kapanışı bitince sorulur.
    func tarayiciKapandi() {
        guard let onay = bekleyenKatalogOnayi else { return }
        bekleyenKatalogOnayi = nil
        guard acceptsActiveCatalogResult() else { return }
        katalogdakiKitap = onay
    }

    /// Künye aranır ve yeni kayıt formu açılır; kayıt kullanıcıyla olur. Katalogda olmayan ISBN'in ve
    /// yalnız düşülmüş kaydı olan kitabın ("Yeni kayıt olarak ekle") yolu.
    func kunyeyleFormuAc(isbn: String, backPhoto: Data?) {
        isRecognizing = true
        kunyeGorevi?.cancel()
        kunyeGorevi = Task { @MainActor in
            defer { isRecognizing = false; kunyeGorevi = nil }
            var scannedDraft = BookDraft()
            scannedDraft.isbn = isbn
            scannedDraft.backCoverData = backPhoto
            let sonuc: KunyeSonucu
            do {
                sonuc = try await BookMetadataService.fetchSonucuButceli(isbn: isbn)
            } catch {
                // Toplam bütçe doldu ya da kullanıcı "İptal, elle gir" dedi: form boş künyeyle açılır
                guard acceptsActiveCatalogResult() else { return }
                scannedDraft.lowConfidenceFields = ["title", "author"]
                scannedDraft.bilgiNotu = "Künye araması tamamlanmadı; bilgileri elle girin."
                draft = scannedDraft
                return
            }
            if let meta = sonuc.meta {
                AmazonBookScraper.apply(metadata: meta, to: &scannedDraft, overwrite: true)
            } else {
                scannedDraft.lowConfidenceFields = ["title", "author"]
            }
            // Arka kapak fotoğrafından özet/etiket/düzey (ve bulunamayan künye) tamamlanır
            if let backPhoto {
                await GeminiBookRecognizer.fillEmptyFromBackCover(&scannedDraft, photo: backPhoto)
            }
            // Çevrimiçi kaynaklar bulamadıysa Gemini'nin kendi bilgisi denenir (ad/yazar işaretli kalır)
            if scannedDraft.title.isEmpty {
                await GeminiBookRecognizer.lookupISBN(isbn, into: &scannedDraft)
            }
            guard acceptsActiveCatalogResult() else { return }
            // "Kitap yok" ile "kaynaklara ulaşılamadı" ayrı söylenir; yoksa bağlantı sorunu
            // kitabın bulunmadığı sanılıp elle girilir. Not formun içinde görünür (arkadaki uyarıda değil).
            if scannedDraft.title.isEmpty, let mesaj = sonuc.bulunamadiMesaji { scannedDraft.bilgiNotu = mesaj }
            draft = scannedDraft
        }
    }

    /// Katalogdaki kitaba bir nüsha ekler (seri tarama ve tekli onaydaki "Nüsha ekle (+1)").
    /// Kayıt olmazsa (baskı seçimi gerekirse ya da yetki yoksa) taslak kuyruğa ya da forma gider.
    @discardableResult
    func nushaArtir(_ existing: CatalogBook, isbn: String, kuyruga: Bool = true, adet: Int = 1) -> SaveOutcome {
        let incoming = Book(title: existing.title, author: existing.author, isbn: isbn, quantity: max(1, adet))
        let outcome = saveBook(incoming, source: "barcode")
        guard outcome.succeeded else {
            var pending = BookDraft()
            pending.title = existing.title
            pending.author = existing.author
            pending.isbn = isbn
            pending.quantity = max(1, adet)
            if kuyruga { batchDrafts.append(pending); persistPendingQueue() } else { draft = pending }
            return outcome
        }
        recordSession(outcome)
        switch outcome {
        case .merged(let id, let added): lastScanAction = .merged(id, added: added)
        case .inserted(let id): lastScanAction = .saved(id)
        case .updated, .failed: break
        }
        return outcome
    }

    /// Seri tarama panelindeki "Son kitaba +1" (uzun basışta +2/+5/+10): aynı kitabın nüshaları için barkodu
    /// yeniden okutmak gerekmez. Son işlem kuyruktaki bir taslaksa adedi kuyrukta artar.
    func sonKitabaNushaEkle(_ adet: Int) {
        guard acceptsActiveCatalogResult(), let eylem = lastScanAction, adet > 0 else { return }
        switch eylem {
        case .saved(let id), .merged(let id, _):
            guard let kitap = catalogBooks.first(where: { $0.id == id && !$0.isDeleted }) else {
                appendSerialLog("⚠️ Son kitap artık katalogda değil")
                return
            }
            let isbn = ISBNFormatter.normalize(kitap.isbn ?? "")
            let ad = kitap.title.isEmpty ? isbn : kitap.title
            let outcome = nushaArtir(kitap, isbn: isbn, adet: adet)
            guard outcome.succeeded else {
                appendSerialLog("⚠️ \(ad) — nüsha eklenemedi")
                return
            }
            serialScanCount += adet
            let toplam = tarama.nushaEklendi(isbn: isbn, adet: adet)
            appendSerialLog("↺ \(ad) — adet +\(adet) (bu oturumda \(toplam))")
        case .queued(let id):
            guard let index = batchDrafts.firstIndex(where: { $0.id == id }) else { return }
            batchDrafts[index].quantity += adet
            persistPendingQueue()
            serialScanCount += adet
            let ad = batchDrafts[index].title.isEmpty ? batchDrafts[index].isbn : batchDrafts[index].title
            appendSerialLog("• \(ad) — adet \(batchDrafts[index].quantity) (onay kuyruğunda)")
        }
    }

    /// Onay diyaloğundaki "Nüsha ekle (+1)": nüsha artırma yönetici ister, rol kilidi açıksa önce kimlik sorulur.
    func nushaEkleOnayla(_ onay: KatalogdakiKitapOnayi) {
        Task { @MainActor in
            guard await YetkiDurumu.shared.yoneticiOl(neden: "Nüsha eklemek için kimliğinizi doğrulayın") else {
                recognitionError = YetkiDurumu.shared.hata ?? "Nüsha eklemek için yönetici kimliği gerekir."
                return
            }
            guard acceptsActiveCatalogResult() else { return }
            guard let existing = catalogBooks.first(where: { $0.id == onay.kitapID }), !existing.isWithdrawn else {
                recognitionError = "“\(onay.kitapAdi)” artık katalogda değil; nüsha eklenmedi."
                return
            }
            let outcome = nushaArtir(existing, isbn: onay.isbn, kuyruga: false)
            sonEklemeyiGoster(outcome, kitapAdi: existing.title)
        }
    }

    /// Onay diyaloğundaki "Kitabı aç": Kitaplar'da ayrıntı açılır.
    func katalogdakiKitabiAc(_ onay: KatalogdakiKitapOnayi) {
        derinBaglanti.bekleyenKitapID = onay.kitapID
        derinBaglanti.hedefSekme = .kitaplar
        // Katalog Yönetimi bir sayfadır: kapanmazsa Kitaplar arkada kalır
        if presentation == .management { persistScanSessionNow(); dismiss() }
    }

    /// Seri tarama ağ işçisi: kuyruğu teker teker işler; hata/kopma tek kitabı etkiler,
    /// taramayı asla kilitlemez. İşlenen ISBN iş bitene kadar diskteki oturumda kalır; katalog kilidi
    /// kaybolursa ISBN sıranın başına döner ve günlükte "bekliyor" yazar.
    func startSerialWorker() {
        guard acceptsActiveCatalogResult() else { return }
        guard !isSerialWorkerRunning else { return }
        isSerialWorkerRunning = true
        Task { @MainActor in
            defer { isSerialWorkerRunning = false }

            while true {
                guard acceptsActiveCatalogResult() else { return }
                guard let isbn = tarama.siradakiniAl() else { break }
                persistScanSession()
                var scannedDraft = BookDraft()
                scannedDraft.isbn = isbn
                let sonuc = await BookMetadataService.fetchSonucu(isbn: isbn)
                if let meta = sonuc.meta {
                    AmazonBookScraper.apply(metadata: meta, to: &scannedDraft, overwrite: true)
                } else {
                    scannedDraft.lowConfidenceFields = ["title", "author"]
                }
                if scannedDraft.title.isEmpty {
                    await GeminiBookRecognizer.lookupISBN(isbn, into: &scannedDraft)
                }

                guard acceptsActiveCatalogResult() else {
                    tarama.islenenigeriVer()
                    appendSerialLog("⚠️ \(isbn) — katalog değişti, künye bekliyor")
                    return
                }
                // Tarama kurulumunda seçilen raf/konum uygulanır
                if !scanAssignment.location.isEmpty { scannedDraft.location = scanAssignment.location }
                if !scanAssignment.cabinet.isEmpty { scannedDraft.cabinet = scanAssignment.cabinet }
                if !scanAssignment.shelf.isEmpty { scannedDraft.shelf = scanAssignment.shelf }
                if !scanAssignment.category.isEmpty { scannedDraft.category = scanAssignment.category }

                let isComplete = !scannedDraft.title.isEmpty
                    && !scannedDraft.author.isEmpty
                    && scannedDraft.coverData != nil
                if autoSaveScans && isComplete {
                    let outcome = saveBook(book(from: scannedDraft))
                    recordSession(outcome)
                    if case .inserted(let id) = outcome {
                        lastScanAction = .saved(id)
                        _ = tarama.nushaEklendi(isbn: isbn, adet: 1)
                    } else if case .merged(let id, let added) = outcome {
                        lastScanAction = .merged(id, added: added)
                    }
                    if outcome.succeeded {
                        appendSerialLog("✓ \(scannedDraft.title) — kaydedildi")
                    } else {
                        batchDrafts.append(scannedDraft)
                        persistPendingQueue()
                        appendSerialLog("⚠️ \(scannedDraft.title) — taslak korunuyor")
                    }
                } else {
                    batchDrafts.append(scannedDraft)
                    persistPendingQueue()
                    lastScanAction = .queued(scannedDraft.id)
                    appendSerialLog(
                        scannedDraft.title.isEmpty
                            ? (sonuc.erisimSorunuVar
                                ? "⚠️ \(isbn) — kaynaklara ulaşılamadı (bağlantıyı denetleyin), onay kuyruğunda"
                                : "⚠️ \(isbn) — bilgi bulunamadı, onay kuyruğunda")
                            : "• \(scannedDraft.title) — onay kuyruğunda"
                    )
                }
                // Sonuç taslak ya da kayıt olarak güvenceye alındı: ISBN artık bekleyenler listesinden düşer
                tarama.islemBitti()
                persistScanSession()
            }

            guard acceptsActiveCatalogResult() else { return }
            // Tarayıcı kapandıysa ve bekleyen varsa onay listesini aç
            if !isShowingBarcodeScanner && !batchDrafts.isEmpty {
                isShowingBatchReview = true
            }
        }
    }

    /// Uygulama kapanırken ya da katalog kilidi kaybolurken diskte kalan seri tarama kuyruğunu devralır:
    /// künyesi alınmamış ISBN'ler yeni bir ekleme oturumunda, kayıtlı konum ataması ve otomatik kayıt
    /// tercihiyle kaldığı yerden sürer. Eski oturumun kuyruğu boşaltılır; kitapları ve geri alma günlüğü kalır.
    func yarimKalanISBNleriSurdur() {
        guard presentation == .add, acceptsActiveCatalogResult(), !isSerialWorkerRunning,
              tarama.bekleyenSayisi == 0, scanSession == nil,
              let eski = recentScanSessions.first(where: { !($0.pendingISBNs ?? []).isEmpty }),
              let bekleyen = eski.pendingISBNs else { return }
        if let atama = eski.seriAtama {
            var kurulum = BulkAssignment()
            kurulum.location = atama.location
            kurulum.cabinet = atama.cabinet
            kurulum.shelf = atama.shelf
            kurulum.category = atama.category
            scanAssignment = kurulum
            autoSaveScans = atama.otoKayit
        }
        beginAddSession()
        tarama.devral(bekleyen: bekleyen)
        appendSerialLog("⚠️ \(bekleyen.count) ISBN önceki taramadan sürdürülüyor")
        persistScanSessionNow()
        var temiz = eski
        temiz.pendingISBNs = nil
        temiz.seriAtama = nil
        do { try ScanSessionStore.save(temiz, updateTimestamp: false) }
        catch { recognitionError = "Önceki tarama kuyruğu güncellenemedi: \(error.localizedDescription)" }
        recentScanSessions = recentScanSessions.map { $0.id == eski.id ? temiz : $0 }
        startSerialWorker()
    }

    /// Amazon'dan gelen bilgileri kayıttaki BOŞ alanlara işler (dolu alanlara dokunmaz).
    /// Ağ beklemesi (await) sırasında kitap silinmiş olabilir. Silinmiş bir SwiftData
    /// modelinin alanına dokunmak "model instance was invalidated" ile çöker; bu
    /// yüzden her beklemeden sonra yazmadan önce kaydın hâlâ yaşadığı doğrulanır.
    func isStillInCatalog(_ book: CatalogBook) -> Bool {
        acceptsActiveCatalogResult() && !book.isDeleted && book.modelContext === modelContext
    }

    func apply(_ meta: AmazonBookMetadata, to book: CatalogBook) throws {
        try requireActiveCatalog()
        try SchoolLibraryService.requireAdmin()
        guard isStillInCatalog(book) else { throw CatalogSaveEngine.SaveError(message: "Kitap artık katalogda bulunmuyor.") }
        var updated = book.book
        if !BookFieldMetadata.isLocked("title", on: book), book.title.isEmpty && !meta.title.isEmpty { updated.title = meta.title }
        if !BookFieldMetadata.isLocked("author", on: book), (book.author.isEmpty || isPlaceholderAuthor(book.author)) && !meta.author.isEmpty {
            updated.author = meta.author
        }
        if !BookFieldMetadata.isLocked("publisher", on: book), (book.publisher ?? "").isEmpty && !meta.publisher.isEmpty {
            updated.publisher = meta.publisher
        }
        if !BookFieldMetadata.isLocked("publicationYear", on: book), (book.publicationYear ?? "").isEmpty && !meta.publicationYear.isEmpty {
            updated.publicationYear = meta.publicationYear
        }
        if !BookFieldMetadata.isLocked("edition", on: book), (book.edition ?? "").isEmpty && !meta.edition.isEmpty {
            updated.edition = meta.edition
        }
        if !BookFieldMetadata.isLocked("pageCount", on: book), (book.pageCount ?? "").isEmpty && !meta.pageCount.isEmpty {
            updated.pageCount = meta.pageCount
        }
        if !BookFieldMetadata.isLocked("language", on: book), (book.language ?? "").isEmpty && !meta.language.isEmpty {
            updated.language = meta.language
        }
        if !BookFieldMetadata.isLocked("category", on: book), (book.category ?? "").isEmpty && !meta.category.isEmpty {
            updated.category = meta.category
        }
        if !BookFieldMetadata.isLocked("coverData", on: book), updated.coverData == nil, let cover = meta.coverData {
            updated.coverData = cover
        }
        if !BookFieldMetadata.isLocked("notes", on: book), book.notes.isEmpty && !meta.notes.isEmpty {
            updated.notes = meta.notes
        }
        if (book.isbn ?? "").isEmpty, !meta.isbn.isEmpty, !BookFieldMetadata.isLocked("isbn", on: book) { updated.isbn = meta.isbn }
        _ = try CatalogSaveEngine.save(updated, context: modelContext, catalog: catalogBooks, source: "api")
    }

    /// Kayıtlı kitabın kapak görselini yeniden OCR'dan geçirir ve BOŞ alanları doldurur.
    /// OCR iyileştikçe ya da düzeltme belleği büyüdükçe eski kayıtlar da düzelir.
    func reReadOCR(_ book: CatalogBook) {
        guard acceptsActiveCatalogResult() else { return }
        guard YetkiDurumu.shared.yonetici else { recognitionError = "Bu değişiklik için yönetici kimliği gerekir."; return }
        guard let cover = book.coverData else {
            recognitionError = "Bu kayıtta yeniden okunacak bir görsel yok."
            return
        }

        isRecognizing = true
        Task { @MainActor in
            defer { isRecognizing = false }
            guard let draft = await BookOCREngine.recognizeBook(imageData: cover) else {
                recognitionError = "Görsel yeniden okunamadı."
                return
            }

            guard isStillInCatalog(book), YetkiDurumu.shared.yonetici else { return }
            var updated = book.book
            var changed = 0
            if !BookFieldMetadata.isLocked("title", on: book), book.title.isEmpty, !draft.title.isEmpty { updated.title = draft.title; changed += 1 }
            if !BookFieldMetadata.isLocked("author", on: book), book.author.isEmpty, !draft.author.isEmpty { updated.author = draft.author; changed += 1 }
            if !BookFieldMetadata.isLocked("isbn", on: book), (book.isbn ?? "").isEmpty, !draft.isbn.isEmpty { updated.isbn = draft.isbn; changed += 1 }
            if !BookFieldMetadata.isLocked("publisher", on: book), (book.publisher ?? "").isEmpty, !draft.publisher.isEmpty {
                updated.publisher = draft.publisher; changed += 1
            }
            if !BookFieldMetadata.isLocked("publicationYear", on: book), (book.publicationYear ?? "").isEmpty, !draft.publicationYear.isEmpty {
                updated.publicationYear = draft.publicationYear; changed += 1
            }
            if !BookFieldMetadata.isLocked("pageCount", on: book), (book.pageCount ?? "").isEmpty, !draft.pageCount.isEmpty {
                updated.pageCount = draft.pageCount; changed += 1
            }
            if !BookFieldMetadata.isLocked("edition", on: book), (book.edition ?? "").isEmpty, !draft.edition.isEmpty {
                updated.edition = draft.edition; changed += 1
            }

            // Öğrenen düzeltme belleği mevcut değerleri de tazeler
            let corrected = CorrectionMemory.correct(book.title)
            if !BookFieldMetadata.isLocked("title", on: book), corrected != book.title { updated.title = corrected; changed += 1 }

            guard saveBook(updated, source: draft.recognizedByGemini ? "gemini" : "vision").succeeded else { return }
            CatalogBackup.saveLight(catalogBooks, force: true)
            bulkMessage = changed == 0
                ? "Yeniden okumada yeni bilgi bulunamadı."
                : "\(changed) alan yeniden okumayla güncellendi."
        }
    }

    /// ISBN'i olmayan kayıtları ad + yazar ile arayıp tamamlar (Amazon → Google Books).
    func searchByTitleAuthor(_ book: CatalogBook) {
        guard acceptsActiveCatalogResult() else { return }
        guard !book.title.isEmpty else {
            recognitionError = "Arama için önce kitap adını girin."
            return
        }

        isRecognizing = true
        Task { @MainActor in
            defer { isRecognizing = false }
            guard let meta = await BookMetadataService.search(
                title: book.title,
                author: book.author,
                publisher: book.publisher ?? ""
            ) else {
                bulkMessage = "Ad ve yazarla kitap bulunamadı."
                return
            }
            guard isStillInCatalog(book) else { return }
            do { try apply(meta, to: book) }
            catch { recognitionError = "Bilgi kaydedilemedi: \(error.localizedDescription)"; return }
            CatalogBackup.saveLight(catalogBooks, force: true)
            bulkMessage = "“\(meta.title)” bilgileri eklendi."
        }
    }

    func enrichFromAmazon(_ book: CatalogBook) {
        guard acceptsActiveCatalogResult() else { return }
        guard let isbn = book.isbn, !isbn.isEmpty else { return }
        isRecognizing = true
        Task { @MainActor in
            defer { isRecognizing = false }
            do {
                if let meta = await BookMetadataService.fetch(
                    isbn: isbn,
                    title: book.title,
                    author: book.author,
                    publisher: book.publisher ?? ""
                ) {
                    try apply(meta, to: book)
                    try modelContext.save()
                    CatalogBackup.saveLight(catalogBooks)
                } else {
                    recognitionError = "Amazon’da bu ISBN için ek bilgi bulunamadı."
                }
            } catch {
                recognitionError = "Amazon’dan veri çekilirken hata oluştu: \(error.localizedDescription)"
            }
        }
    }

    func deleteBook(_ book: CatalogBook) {
        guard acceptsActiveCatalogResult() else { return }
        do {
            try TrashStore.moveVerified([book], context: modelContext)
            CatalogBackup.saveLight(catalogBooks)
        } catch { recognitionError = "Kitap çöp kutusuna taşınamadı: \(error.localizedDescription)" }
    }

    /// Kitabı kalıcı silmek yerine "düşülmüş" işaretler (resmî kayıt defteri mantığı).
    /// Düşülen kayıtlar normal görünümlerden gizlenir ama veritabanında kalır.
    func withdrawBook(_ book: CatalogBook, reason: String) {
        guard acceptsActiveCatalogResult() else { return }
        var updated = book.book
        updated.isWithdrawn = true
        updated.withdrawnReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.withdrawnDate = .now
        _ = saveBook(updated)
    }

    func restoreWithdrawnBook(_ book: CatalogBook) {
        guard acceptsActiveCatalogResult() else { return }
        var updated = book.book
        updated.isWithdrawn = false
        updated.withdrawnReason = nil
        updated.withdrawnDate = nil
        _ = saveBook(updated)
    }

    func book(from draft: BookDraft) -> Book {
        BookFieldMetadata.stampChanges(before: nil, after: draft.snapshot,
            source: draft.recognitionSource ?? (draft.recognizedByGemini ? "gemini" : "manual"))
    }

    func acceptOrQueue(_ draft: BookDraft, reviewQueue: inout [BookDraft]) {
        guard acceptsActiveCatalogResult() else { return }
        if draft.lowConfidenceFields.isEmpty && !draft.title.isEmpty {
            let outcome = saveBook(book(from: draft))
            if outcome.succeeded { recordSession(outcome) }
            else { reviewQueue.append(draft) }
        } else {
            reviewQueue.append(draft)
        }
    }

    /// Hızlı mod: Gemini emin, fotoğraf iyi ve ISBN/yayınevi doluysa düzenleyici açılmadan
    /// kaydedilir; aksi hâlde düzenleyici açılır.
    func presentOrQuickSave(_ scanned: BookDraft) {
        guard acceptsActiveCatalogResult() else { return }
        if GeminiSettings.isQuickSaveEnabled, GeminiBookRecognizer.isConfidentEnoughToAutoSave(scanned) {
            let outcome = saveBook(book(from: scanned))
            recordSession(outcome)
            guard outcome.succeeded else { draft = scanned; return }
            bulkMessage = "Hızlı mod: “\(scanned.title)” kaydedildi."
#if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
        } else {
            draft = scanned
        }
    }

    func presentNextDraft() {
        guard acceptsActiveCatalogResult() else { return }
        persistScanSession()
        guard draft == nil, !queuedDrafts.isEmpty else {
            return
        }
        draft = queuedDrafts.removeFirst()
    }

    func enqueue(_ drafts: [BookDraft]) {
        guard acceptsActiveCatalogResult() else { return }
        guard !drafts.isEmpty else {
            return
        }

        if draft == nil {
            draft = drafts[0]
            queuedDrafts.append(contentsOf: drafts.dropFirst())
        } else {
            queuedDrafts.append(contentsOf: drafts)
        }
    }

    func migrateLegacyBooksIfNeeded() {
        guard acceptsActiveCatalogResult() else { return }
        let migrationKey = "swiftDataMigrationCompleted"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else {
            return
        }

        if
            let data = UserDefaults.standard.data(forKey: "savedBooks"),
            let legacyBooks = try? JSONDecoder().decode([Book].self, from: data)
        {
            for book in legacyBooks where !catalogBooks.contains(where: { $0.id == book.id }) {
                modelContext.insert(CatalogBook(book: book))
            }
            do { try modelContext.save() }
            catch { modelContext.rollback(); recognitionError = "Eski katalog taşınamadı: \(error.localizedDescription)"; return }
        }
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    func deleteFilteredBooks(at offsets: IndexSet) {
        let ids = Set(offsets.filter { filteredBooks.indices.contains($0) }.map { filteredBooks[$0].id })
        do {
            try TrashStore.moveVerified(catalogBooks.filter { ids.contains($0.id) }, context: modelContext)
            CatalogBackup.saveLight(catalogBooks)
        } catch { recognitionError = "Silme kaydedilemedi: \(error.localizedDescription)" }
    }

}


private struct BookExcelDocument: FileDocument {
    static let xlsxType = UTType(
        filenameExtension: "xlsx",
        conformingTo: .data
    ) ?? .data

    static var readableContentTypes: [UTType] {
        [xlsxType]
    }

    private let data: Data

    /// Hazır veriyle oluşturulur; paketleme ekran çizimi sırasında YAPILMAZ.
    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Katalogdaki kayıtlarla aksan/harf hatasına dayanıklı benzerlik karşılaştırması.
/// OCR'ın "Yüzbasının Kızı" okuduğu kitabı katalogdaki "Yüzbaşının Kızı" ile eşleştirir.
/// Arka plan görevlerinden (mükerrer tarama, alan birleştirme) de çağrılır; `NSCache`
/// iş parçacığı güvenlidir, bu yüzden ana aktöre bağlı olması gerekmez.
nonisolated enum CatalogMatcher {
    /// 2.500+ kayıtlı katalogda arama/sıralama her karede aynı başlık ve yazarları
    /// tekrar tekrar normalize ediyordu; sonuçlar burada önbelleğe alınır.
    private static let normalizeCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 8000
        return cache
    }()

    static func normalize(_ text: String) -> String {
        let key = text as NSString
        if let cached = normalizeCache.object(forKey: key) {
            return cached as String
        }
        // Türkçe katlamada noktasız "ı" korunur; arama ve eşleştirmede "i" ile eş sayılması
        // için elle çevrilir ("Kızı" ↔ "kizi").
        let result = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "İ", with: "i")
            .lowercased(with: Locale(identifier: "en_US"))
            .filter { $0.isLetter || $0.isNumber || $0 == " " }
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        normalizeCache.setObject(result as NSString, forKey: key)
        return result
    }

    /// Normalize edilmiş arama terimini kelimelere ayırır: "tolstoy savas" sorgusu
    /// "savas ve baris … tolstoy" anahtarıyla eşleşsin diye her kelime ayrı aranır.
    /// Koşul SQL'e sabit biçimde çevrildiği için en uzun (en ayırt edici) 3 kelime döner.
    static func aramaKelimeleri(_ normalized: String) -> [String] {
        var kelimeler: [String] = []
        for kelime in normalized.split(separator: " ").map(String.init) where !kelimeler.contains(kelime) {
            kelimeler.append(kelime)
        }
        guard kelimeler.count > 3 else { return kelimeler }
        return Array(kelimeler.sorted { $0.count > $1.count }.prefix(3))
    }

    /// Ad benzerliği + sayı/cilt eşitliği: "Sefiller 1. Cilt" ile "Sefiller 2. Cilt" ayrı kitaptır,
    /// "Sokrates'in Savunması" ile "Sokratesin Savunmasi" aynı.
    static func isSimilarTitle(_ a: String, _ b: String) -> Bool {
        isSimilar(a, b) && sayiImzasi(a) == sayiImzasi(b)
    }

    /// Addaki rakamlar ve Roma rakamı sözcükleri ("II", "IV"): cilt ayrımı için imza.
    static func sayiImzasi(_ text: String) -> String {
        let rakamlar = text.filter(\.isNumber)
        let roma = text.split(whereSeparator: { !$0.isLetter })
            .filter { sozcuk in sozcuk.count <= 4 && sozcuk.uppercased().allSatisfy { "IVXLC".contains($0) } }
            .map { $0.uppercased() }
            .joined(separator: ",")
        return rakamlar + "|" + roma
    }

    static func isSimilar(_ a: String, _ b: String) -> Bool {
        let na = normalize(a)
        let nb = normalize(b)
        guard !na.isEmpty, !nb.isEmpty else { return false }
        if na == nb { return true }
        guard min(na.count, nb.count) >= 6 else { return false }
        let tolerance = max(1, min(na.count, nb.count) / 8)
        guard abs(na.count - nb.count) <= tolerance else { return false }
        return levenshtein(na, nb) <= tolerance
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        var previous = Array(0...bChars.count)
        var current = [Int](repeating: 0, count: bChars.count + 1)
        for i in 1...aChars.count {
            current[0] = i
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[bChars.count]
    }
}

enum ISBNFormatter {
    nonisolated static func normalize(_ value: String) -> String {
        var digits = value.filter(\.isNumber)
        // ISBN-10'un kontrol hanesi "X" olabilir (975-8431-07-X): ilk 9 hane yeter,
        // ISBN-13 kontrol hanesi aşağıda yeniden hesaplanır
        if digits.count == 9, let last = value.last(where: { $0.isNumber || $0 == "X" || $0 == "x" }), !last.isNumber {
            digits += "0"
        }

        if digits.count == 13 {
            return isValidISBN13(digits) ? digits : ""
        }

        guard digits.count == 10 else {
            return ""
        }

        let firstTwelve = "978" + digits.prefix(9)
        let checkDigit = isbn13CheckDigit(for: String(firstTwelve))
        return firstTwelve + String(checkDigit)
    }

    nonisolated static func repair(_ value: String) -> String {
        let replacements: [Character: Character] = [
            "O": "0", "Q": "0", "I": "1", "L": "1",
            "Z": "2", "S": "5", "G": "6", "B": "8"
        ]
        let repaired = value.uppercased().map { character in
            replacements[character] ?? character
        }
        return normalize(String(repaired))
    }

    /// Arama metni barkod/ISBN görünümünde mi? (en az 6 rakam ve çoğunluğu rakam)
    /// "1984" gibi sayı içeren kısa kitap adları barkod sayılmaz.
    nonisolated static func isBarcodeQuery(_ value: String) -> Bool {
        let digits = value.filter(\.isNumber)
        return digits.count >= 6 && digits.count * 2 >= value.count
    }

    nonisolated static func isValidISBN13(_ value: String) -> Bool {
        let digits = value.filter(\.isNumber)
        guard digits.count == 13 else {
            return false
        }

        let firstTwelve = String(digits.prefix(12))
        guard let suppliedCheckDigit = digits.last.flatMap({ Int(String($0)) }) else {
            return false
        }
        return isbn13CheckDigit(for: firstTwelve) == suppliedCheckDigit
    }

    nonisolated private static func isbn13CheckDigit(for firstTwelve: String) -> Int {
        let sum = firstTwelve.enumerated().reduce(0) { result, item in
            result + (Int(String(item.element)) ?? 0)
                * (item.offset.isMultiple(of: 2) ? 1 : 3)
        }
        return (10 - (sum % 10)) % 10
    }
}

nonisolated enum ExcelWorkbookBuilder {
    private struct ImageEntry {
        let row: Int
        let filename: String
        let data: Data
    }

    static func makeWorkbook(books: [Book]) -> Data {
        let images = books.enumerated().compactMap { index, book -> ImageEntry? in
            guard let coverData = book.coverData else {
                return nil
            }
            let fileExtension = isPNG(coverData) ? "png" : "jpg"
            return ImageEntry(
                row: index + 1,
                filename: "image\(index + 1).\(fileExtension)",
                data: coverData
            )
        }

        var archive = ZIPArchiveBuilder()
        archive.add(name: "[Content_Types].xml", text: contentTypes(hasImages: !images.isEmpty))
        archive.add(name: "_rels/.rels", text: packageRelationships)
        archive.add(name: "xl/workbook.xml", text: workbook)
        archive.add(name: "xl/_rels/workbook.xml.rels", text: workbookRelationships)
        archive.add(name: "xl/worksheets/sheet1.xml", text: worksheet(books: books, hasImages: !images.isEmpty))

        if !images.isEmpty {
            archive.add(name: "xl/worksheets/_rels/sheet1.xml.rels", text: worksheetRelationships)
            archive.add(name: "xl/drawings/drawing1.xml", text: drawing(images: images))
            archive.add(name: "xl/drawings/_rels/drawing1.xml.rels", text: drawingRelationships(images: images))

            for image in images {
                archive.add(name: "xl/media/\(image.filename)", data: image.data)
            }
        }

        return archive.finalize()
    }

    private static func worksheet(books: [Book], hasImages: Bool) -> String {
        let headers = [
            "Kapak", "Kitap Adı", "Yazar", "Yayınevi", "ISBN-13",
            "Basım Yılı", "Baskı", "Sayfa Sayısı", "Kategori", "Dil",
            "Oda / Konum", "Dolap", "Raf", "Adet", "Okuma Durumu", "Puan",
            "Notlar", "Eklenme Tarihi"
        ]
        let headerCells = headers.enumerated()
            .map { cell(column: $0.offset, row: 1, value: $0.element) }
            .joined()

        let rows = books.enumerated().map { index, book in
            let values = [
                book.coverData == nil ? "Kapak yok" : "",
                book.title,
                book.author,
                book.publisher ?? "",
                ISBNFormatter.normalize(book.isbn ?? ""),
                book.publicationYear ?? "",
                book.edition ?? "",
                book.pageCount ?? "",
                book.category ?? "",
                book.language ?? "",
                book.location ?? "",
                book.cabinet ?? "",
                book.shelf ?? "",
                book.quantity.map(String.init) ?? "",
                book.readingStatus ?? "",
                book.rating.map(String.init) ?? "",
                book.notes,
                book.addedAt.formatted(date: .numeric, time: .omitted)
            ]
            let cells = values.enumerated()
                .map { cell(column: $0.offset, row: index + 2, value: $0.element) }
                .joined()
            return #"<row r="\#(index + 2)" ht="82" customHeight="1">\#(cells)</row>"#
        }
        .joined()

        let drawingElement = hasImages ? #"<drawing r:id="rId1"/>"# : ""
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <cols>
            <col min="1" max="1" width="16" customWidth="1"/>
            <col min="2" max="4" width="24" customWidth="1"/>
            <col min="5" max="16" width="16" customWidth="1"/>
            <col min="17" max="17" width="32" customWidth="1"/>
            <col min="18" max="18" width="18" customWidth="1"/>
          </cols>
          <sheetData>
            <row r="1" ht="24" customHeight="1">\(headerCells)</row>
            \(rows)
          </sheetData>
          \(drawingElement)
        </worksheet>
        """
    }

    private static func cell(column: Int, row: Int, value: String) -> String {
        let reference = "\(columnName(column))\(row)"
        return #"<c r="\#(reference)" t="inlineStr"><is><t xml:space="preserve">\#(xmlEscape(value))</t></is></c>"#
    }

    private static func drawing(images: [ImageEntry]) -> String {
        let anchors = images.enumerated().map { index, image in
            """
            <xdr:twoCellAnchor editAs="oneCell">
              <xdr:from><xdr:col>0</xdr:col><xdr:colOff>80000</xdr:colOff><xdr:row>\(image.row)</xdr:row><xdr:rowOff>50000</xdr:rowOff></xdr:from>
              <xdr:to><xdr:col>1</xdr:col><xdr:colOff>-80000</xdr:colOff><xdr:row>\(image.row + 1)</xdr:row><xdr:rowOff>-50000</xdr:rowOff></xdr:to>
              <xdr:pic>
                <xdr:nvPicPr><xdr:cNvPr id="\(index + 2)" name="Kapak \(index + 1)"/><xdr:cNvPicPr/></xdr:nvPicPr>
                <xdr:blipFill><a:blip r:embed="rId\(index + 1)"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>
                <xdr:spPr><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr>
              </xdr:pic>
              <xdr:clientData/>
            </xdr:twoCellAnchor>
            """
        }
        .joined()

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          \(anchors)
        </xdr:wsDr>
        """
    }

    private static func drawingRelationships(images: [ImageEntry]) -> String {
        let relationships = images.enumerated().map { index, image in
            #"<Relationship Id="rId\#(index + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/\#(image.filename)"/>"#
        }
        .joined()

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          \(relationships)
        </Relationships>
        """
    }

    private static func columnName(_ index: Int) -> String {
        var value = index + 1
        var result = ""
        while value > 0 {
            value -= 1
            result = String(UnicodeScalar(UInt8(65 + value % 26))) + result
            value /= 26
        }
        return result
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func isPNG(_ data: Data) -> Bool {
        Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10]
    }

    private static func contentTypes(hasImages: Bool) -> String {
        let imageDefaults = hasImages
            ? #"<Default Extension="png" ContentType="image/png"/><Default Extension="jpg" ContentType="image/jpeg"/>"#
            : ""
        let drawingOverride = hasImages
            ? #"<Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>"#
            : ""

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          \(imageDefaults)
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          \(drawingOverride)
        </Types>
        """
    }

    private static let packageRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """

    private static let workbook = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <sheets><sheet name="Kitap Kataloğu" sheetId="1" r:id="rId1"/></sheets>
    </workbook>
    """

    private static let workbookRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
    </Relationships>
    """

    private static let worksheetRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/>
    </Relationships>
    """
}

/// Excel (.xlsx) de sıradan bir ZIP paketidir; sınır kontrollü ortak yazıcı kullanılır
/// (bkz. FullArchive.swift — 65.535 giriş / 4 GB sınırında çökme yerine atlama).
private typealias ZIPArchiveBuilder = ZIPWriter

enum PDFPageSelector {
    static func indices(for pageCount: Int) -> [Int] {
        let candidates = [0, 1, pageCount - 2, pageCount - 1]
        return Array(Set(candidates.filter { $0 >= 0 && $0 < pageCount })).sorted()
    }
}

enum BookScanError: LocalizedError {
    case invalidImage
    case invalidPDF
    case noText

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "Seçilen fotoğraf geçerli bir görüntü değil."
        case .invalidPDF:
            "Seçilen PDF açılamadı."
        case .noText:
            "Seçilen sayfalarda okunabilir metin bulunamadı."
        }
    }
}

enum CoverImageDecoder {
    /// Üretilen küçük kapakları bellekte tutar: liste kaydırılırken aynı kapak
    /// her satır çiziminde yeniden çözülmez (50 binlik katalogda akıcılık için kritik).
    /// NSCache iş parçacığı güvenlidir; küçük kapaklar arka planda da çözülüp yazılır.
    nonisolated(unsafe) private static let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        // 2.500+ kitaplık katalogda liste hızlıca kaydırılınca çok daha fazla
        // benzersiz kapak görülür; sınır büyütüldü, toplam bellek de sınırlandı.
        // Kapak ızgarasının küçük kapağı ~0,5 MB; 160 MB yaklaşık 300 kapağı tutar.
        cache.countLimit = 1500
        cache.totalCostLimit = 160 * 1024 * 1024
        return cache
    }()

    /// Katalog kapağının önbellek anahtarı: kitap, kapak verisinin boyu ve piksel ölçüsü.
    /// Kapak verisinin tamamını her çizimde karıştırmaya (hash) gerek bırakmaz.
    nonisolated struct KucukKapakAnahtari: Hashable, Sendable {
        let kitap: UUID
        let bayt: Int
        let piksel: Int
        var metin: NSString { "kapak-\(kitap.uuidString)-\(bayt)-\(piksel)" as NSString }
    }

    nonisolated static func onbellektekiKucukKapak(_ anahtar: KucukKapakAnahtari) -> CGImage? {
        cache.object(forKey: anahtar.metin)
    }

    /// Küçük kapağı çözer ve önbelleğe yazar; arka planda çağrılır. Görsel burada tamamen
    /// çözülür (ShouldCacheImmediately), ilk çizimde ana iş parçacığında çözülmez.
    nonisolated static func kucukKapak(_ data: Data, anahtar: KucukKapakAnahtari) -> CGImage? {
        if let hazir = cache.object(forKey: anahtar.metin) { return hazir }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: anahtar.piksel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        cache.setObject(image, forKey: anahtar.metin, cost: image.bytesPerRow * image.height)
        return image
    }

    static func thumbnail(from data: Data, maxPixelSize: Int) -> CGImage? {
        let key = "\(data.count)-\(data.hashValue)-\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let cost = image.bytesPerRow * image.height
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }
}

private struct BookCoverCard: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Ölçüyü renkli zemin belirler; geniş fotoğraf kartın dışına taşıp komşu karta binmez
            Rectangle()
                .fill(KitapTema.kitapRengi(book.title).gradient)
                .frame(height: 170)
                .frame(maxWidth: .infinity)
                .overlay {
                    if
                        let data = book.coverData,
                        let image = CoverImageDecoder.thumbnail(from: data, maxPixelSize: 400)
                    {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "book.closed.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                    }
                }
                .clipShape(.rect(cornerRadius: 10))

            Text(book.title)
                .font(.headline)
                .lineLimit(2)
            Text(book.author)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let location = book.location, !location.isEmpty {
                Label(location, systemImage: "books.vertical")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// İstatistik ekranı için kapak BAYTLARI değil, sadece bir "var/yok" bayrağı taşır —
/// 2.500+ kitaplık katalogda her açılışta onlarca MB kopyalamamak için.
private struct BookStatSummary {
    let category: String?
    let isbn: String?
    let author: String
    let publisher: String?
    let hasCover: Bool
    let quantity: Int?
    let readingStatus: String?
}

private struct CatalogStatisticsView: View {
    @Environment(\.dismiss) private var dismiss
    let stats: [BookStatSummary]

    private var totalCopies: Int {
        stats.reduce(0) { $0 + ($1.quantity ?? 1) }
    }

    private var categoryCount: Int {
        Set(stats.compactMap(\.category).filter { !$0.isEmpty }).count
    }

    private var completeCount: Int {
        stats.filter {
            !($0.isbn ?? "").isEmpty
                && !$0.author.isEmpty
                && !($0.publisher ?? "").isEmpty
                && $0.hasCover
        }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Katalog Özeti") {
                    statisticRow("Farklı kitap", value: stats.count, icon: "books.vertical")
                    statisticRow("Toplam adet", value: totalCopies, icon: "number")
                    statisticRow("Kategori", value: categoryCount, icon: "tag")
                    statisticRow("Eksiksiz kayıt", value: completeCount, icon: "checkmark.circle")
                }

                Section("Okuma Durumu") {
                    statisticRow("Okunacak", value: count(status: "Okunacak"), icon: "bookmark")
                    statisticRow("Okunuyor", value: count(status: "Okunuyor"), icon: "book.pages")
                    statisticRow("Okundu", value: count(status: "Okundu"), icon: "checkmark")
                }
            }
            // Yönetim ve araç panelindeki adla aynı (tek ad kaynağı: KatalogAraci.statistics)
            .navigationTitle(KatalogAraci.statistics.aracBasligi ?? "")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func count(status: String) -> Int {
        stats.filter { $0.readingStatus == status }
            .reduce(0) { $0 + ($1.quantity ?? 1) }
    }

    private func statisticRow(_ title: String, value: Int, icon: String) -> some View {
        LabeledContent {
            Text(value, format: .number)
                .fontWeight(.semibold)
                .foregroundStyle(KitapTema.ana)
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(KitapTema.kitapRengi(title))
            }
        }
    }
}

private struct BookRow: View {
    let book: Book
    /// Erişilebilirlik: büyük yazı ayarında kapak da büyür
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var coverWidth: CGFloat { dynamicTypeSize.isAccessibilitySize ? 76 : 54 }
    private var coverHeight: CGFloat { dynamicTypeSize.isAccessibilitySize ? 108 : 76 }

    var body: some View {
        HStack(spacing: 14) {
            cover

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title.isEmpty ? "Bilgi bekleniyor — ISBN \(book.isbn ?? "?")" : book.title)
                    .font(.headline)
                    .foregroundStyle(book.title.isEmpty ? Color.orange : Color.primary)
                    .lineLimit(2)

                Text(book.author.isEmpty ? "Yazar belirtilmedi" : book.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let isbn = book.isbn, !isbn.isEmpty {
                    Text("ISBN: \(isbn)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                metadataLine
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if let status = book.readingStatus, !status.isEmpty {
                    Text(status)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(statusColor(status).opacity(0.15), in: .capsule)
                        .foregroundStyle(statusColor(status))
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    /// VoiceOver için okunabilir özet: ad, yazar, durum ve ödünç bilgisi.
    private var accessibilityDescription: String {
        var parts: [String] = [book.title.isEmpty ? "Bilgi bekleyen kayıt" : book.title]
        if !book.author.isEmpty { parts.append("Yazar \(book.author)") }
        if let status = book.readingStatus, !status.isEmpty { parts.append(status) }
        if let person = book.loanedTo, !person.isEmpty {
            parts.append("\(person) kişisine ödünç verildi")
            if book.isOverdue { parts.append("iade tarihi geçti") }
        }
        return parts.joined(separator: ", ")
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "Okunuyor": .blue
        case "Okundu": .green
        default: .orange
        }
    }

    private var metadataLine: Text {
        let values = [
            book.publisher,
            book.publicationYear,
            book.pageCount.map { "\($0) sayfa" },
            book.category,
            book.location,
            book.cabinet.map { "Dolap \($0)" },
            book.shelf.map { "Raf \($0)" },
            book.quantity.map { "\($0) adet" },
            book.readingStatus,
            book.rating.map { "\($0)/5" }
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        return Text(values.isEmpty ? book.addedAt.formatted(date: .abbreviated, time: .omitted) : values.joined(separator: " • "))
    }

    @ViewBuilder
    private var cover: some View {
        if
            let data = book.coverData,
            let image = CoverImageDecoder.thumbnail(from: data, maxPixelSize: 160)
        {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: coverWidth, height: coverHeight)
                .clipShape(.rect(cornerRadius: 8))
        } else {
            Image(systemName: "book.closed.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: coverWidth, height: coverHeight)
                .background(
                    KitapTema.kitapRengi(book.title).gradient,
                    in: .rect(cornerRadius: 8)
                )
        }
    }
}

private struct DocumentScannerPresentation: ViewModifier {
    @Binding var isPresented: Bool
    let onScan: ([Data]) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(iOS)
        content
            .fullScreenCover(isPresented: $isPresented) {
                DocumentScannerView(
                    onScan: { pages in
                        isPresented = false
                        onScan(pages)
                    },
                    onCancel: {
                        isPresented = false
                    }
                )
                .ignoresSafeArea()
            }
#else
        content
#endif
    }
}

#if os(iOS)
struct LiveISBNScannerView: UIViewControllerRepresentable {
    var continuous = false
    /// Sayım modu için: aynı barkodun her okunuşu ayrı sayılır (nüsha sayımı).
    var allowRepeats = false
    let onScan: (String) -> Void
    let onCancel: () -> Void
    /// Tekli taramada barkodla birlikte (arka kapağın) fotoğrafı da çekilir.
    var onScanWithPhoto: ((String, Data?) -> Void)? = nil
    /// Tekli taramada kabul denetimi: reddedilen kod tarayıcıyı kapatmaz, `onReddedildi` ile bildirilir.
    var kabulEt: ((String) -> Bool)? = nil
    var onReddedildi: ((String) -> Void)? = nil
    /// Sürekli kipte her okutmanın sonucunu bildirir; titreşim dönüş değerine göre verilir
    /// (`.success` hafif, `.warning` çift, `.error` sert, `.none` sessiz). Verilirse `onScan` çağrılmaz.
    var onScanResult: ((String) -> ScanFeedback)? = nil
    /// Doluysa sürekli kipte bu süre içinde yinelenen aynı kod yutulur (`allowRepeats` ile birlikte
    /// nüsha okutmaya izin verir); yutulan kod `onTekrar` ile bildirilir ve uyarı titreşimi verir.
    var tekrarPenceresi: TimeInterval? = nil
    var onTekrar: ((String) -> Void)? = nil
    /// Kamera başlatılamazsa çağrılır; verilmezse eski davranış (tarayıcıyı kapat) sürer.
    var onFailure: ((Error) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(continuous: continuous, allowRepeats: allowRepeats, onScan: onScan, onScanWithPhoto: onScanWithPhoto,
                    kabulEt: kabulEt, onReddedildi: onReddedildi, onScanResult: onScanResult,
                    tekrarPenceresi: tekrarPenceresi, onTekrar: onTekrar)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        guard DataScannerViewController.isSupported, DataScannerViewController.isAvailable else {
            return UIHostingController(
                rootView: ContentUnavailableView(
                    "Barkod tarayıcı kullanılamıyor",
                    systemImage: "barcode.viewfinder"
                )
            )
        }

        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        let hataGeri = onFailure
        let iptal = onCancel
        return ISBNScannerHostViewController(scanner: scanner, onFailure: { hata in
            if let hataGeri { hataGeri(hata) } else { iptal() }
        })
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) { }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        (uiViewController as? ISBNScannerHostViewController)?.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let continuous: Bool
        private let allowRepeats: Bool
        private let onScan: (String) -> Void
        private let onScanWithPhoto: ((String, Data?) -> Void)?
        private let kabulEt: ((String) -> Bool)?
        private let onReddedildi: ((String) -> Void)?
        private let onScanResult: ((String) -> ScanFeedback)?
        private let onTekrar: ((String) -> Void)?
        private var tekrar: TekrarBastirici?
        private var hasScanned = false
        private var seenCodes = Set<String>()
        /// Aynı geçersiz kod kadrajda kaldıkça uyarı tekrarlanmasın
        private var sonReddedilen: String?

        init(continuous: Bool, allowRepeats: Bool, onScan: @escaping (String) -> Void,
             onScanWithPhoto: ((String, Data?) -> Void)? = nil,
             kabulEt: ((String) -> Bool)? = nil, onReddedildi: ((String) -> Void)? = nil,
             onScanResult: ((String) -> ScanFeedback)? = nil, tekrarPenceresi: TimeInterval? = nil,
             onTekrar: ((String) -> Void)? = nil) {
            self.onScanResult = onScanResult
            self.onTekrar = onTekrar
            self.tekrar = tekrarPenceresi.map { TekrarBastirici(pencere: $0) }
            self.continuous = continuous
            self.allowRepeats = allowRepeats
            self.onScan = onScan
            self.onScanWithPhoto = onScanWithPhoto
            self.kabulEt = kabulEt
            self.onReddedildi = onReddedildi
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                guard
                    case .barcode(let barcode) = item,
                    let value = barcode.payloadStringValue
                else {
                    continue
                }

                if continuous {
                    // Seri mod: tarayıcı açık kalır; sayım dışı kullanımda aynı barkod tekrar sayılmaz
                    if tekrar != nil {
                        if tekrar?.yutulsunMu(value) == true {
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            onTekrar?(value)
                            continue
                        }
                    } else if !allowRepeats {
                        guard seenCodes.insert(value).inserted else { continue }
                    }
                    let geriBildirim: ScanFeedback
                    if let onScanResult {
                        geriBildirim = onScanResult(value)
                    } else {
                        onScan(value)
                        geriBildirim = .success
                    }
                    switch geriBildirim {
                    case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
                    case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
                    case .none: break
                    }
                } else {
                    guard !hasScanned else { return }
                    // Kitap barkodu değilse (fiyat etiketi gibi) tarayıcı açık kalır; fotoğraflı yol da denetlenir
                    if let kabulEt, !kabulEt(value) {
                        if sonReddedilen != value {
                            sonReddedilen = value
                            onReddedildi?(value)
                        }
                        continue
                    }
                    hasScanned = true
                    if let onScanWithPhoto {
                        // Barkod arka kapaktadır: aynı kareden fotoğraf çekilir (özet/etiket için)
                        Task { @MainActor in
                            let photo = try? await dataScanner.capturePhoto()
                            dataScanner.stopScanning()
                            onScanWithPhoto(value, photo?.jpegData(compressionQuality: 0.85))
                        }
                        return
                    }
                    dataScanner.stopScanning()
                    onScan(value)
                    return
                }
            }
        }
    }
}

private final class ISBNScannerHostViewController: UIViewController {
    private let scanner: DataScannerViewController
    private let onFailure: (Error) -> Void
    private var didStartScanning = false

    init(scanner: DataScannerViewController, onFailure: @escaping (Error) -> Void) {
        self.scanner = scanner
        self.onFailure = onFailure
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(scanner)
        scanner.view.frame = view.bounds
        scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scanner.view)
        scanner.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStartScanning else { return }

        do {
            try scanner.startScanning()
            didStartScanning = true
        } catch {
            onFailure(error)
        }
    }

    func stopScanning() {
        scanner.stopScanning()
    }
}

private struct DocumentScannerView: UIViewControllerRepresentable {
    let onScan: ([Data]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ uiViewController: VNDocumentCameraViewController,
        context: Context
    ) { }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: ([Data]) -> Void
        let onCancel: () -> Void

        init(onScan: @escaping ([Data]) -> Void, onCancel: @escaping () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let pages = (0..<scan.pageCount).compactMap { index in
                scan.imageOfPage(at: index).jpegData(compressionQuality: 0.92)
            }
            onScan(pages)
        }

        func documentCameraViewControllerDidCancel(
            _ controller: VNDocumentCameraViewController
        ) {
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            onCancel()
        }
    }
}
#endif

/// Genişlik dolunca alt satıra geçen düzen — kaynak düğmelerinin hiçbiri
/// ekran dışında kalmasın diye yatay kaydırmanın yerine kullanılır.
/// Katalog üstündeki büyük işlem kartı: renkli zemin, ikon, ad, kısa açıklama.
/// `ai` açıksa köşede kıvılcım rozeti (Gemini OCR devrede) görünür.
private struct IslemKarti: View {
    let baslik: String
    let altBaslik: String
    let ikon: String
    let renk: Color
    var menu = false
    var ai = false

    @ScaledMetric(relativeTo: .title2) private var ikonBoyu: CGFloat = 26
    @State private var belirdi = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: ikon)
                    .font(.system(size: ikonBoyu, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: ikonBoyu * 1.9, height: ikonBoyu * 1.9)
                    .background(renk.mix(with: .black, by: 0.45).gradient, in: .rect(cornerRadius: 14))
                    .symbolEffect(.bounce, value: belirdi)
                    .shadow(color: renk.opacity(0.35), radius: 6, y: 3)
                if ai {
                    Image(systemName: "sparkles")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(KitapTema.foto.mix(with: .black, by: 0.45), in: .circle)
                        .offset(x: 6, y: -6)
                        .accessibilityHidden(true)
                }
                if menu {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.white, renk.mix(with: .black, by: 0.45))
                        .offset(x: 6, y: -6)
                        .accessibilityHidden(true)
                }
            }
            // Büyük yazı boyutunda kırpılmasın: iki satıra kadar sarar
            // Yazılar büyük yazı boyutunda küçültülmez, iki-üç satıra sarar
            Text(baslik)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
            Text(altBaslik)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        .shadow(color: renk.opacity(0.18), radius: 6, y: 3)
        .onAppear { if !reduceMotion { belirdi = true } }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
        // Zemin, kenarlık ve basma tepkisi ortak `.kitapKart` stilinden gelir
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(baslik), \(altBaslik)")
    }
}

private struct AkanDuzen: Layout {
    var yatayAralik: CGFloat = 10
    var dikeyAralik: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let siniriGenislik = proposal.width ?? .infinity
        var satirGenisligi: CGFloat = 0
        var satirYuksekligi: CGFloat = 0
        var toplamYukseklik: CGFloat = 0
        var enGenisSatir: CGFloat = 0

        for altGorunum in subviews {
            let boyut = altGorunum.sizeThatFits(.unspecified)
            if satirGenisligi > 0, satirGenisligi + yatayAralik + boyut.width > siniriGenislik {
                enGenisSatir = max(enGenisSatir, satirGenisligi)
                toplamYukseklik += satirYuksekligi + dikeyAralik
                satirGenisligi = boyut.width
                satirYuksekligi = boyut.height
            } else {
                satirGenisligi += satirGenisligi > 0 ? yatayAralik + boyut.width : boyut.width
                satirYuksekligi = max(satirYuksekligi, boyut.height)
            }
        }
        enGenisSatir = max(enGenisSatir, satirGenisligi)
        return CGSize(width: proposal.width ?? enGenisSatir, height: toplamYukseklik + satirYuksekligi)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var satirYuksekligi: CGFloat = 0

        for altGorunum in subviews {
            let boyut = altGorunum.sizeThatFits(.unspecified)
            if x > bounds.minX, x + boyut.width > bounds.maxX {
                x = bounds.minX
                y += satirYuksekligi + dikeyAralik
                satirYuksekligi = 0
            }
            altGorunum.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(boyut))
            x += boyut.width + yatayAralik
            satirYuksekligi = max(satirYuksekligi, boyut.height)
        }
    }
}

/// Kitapyurdu'ndan kitap çekme ekranı. Amazon ekranının ISBN'le çalışan
/// eşdeğeri; Kitapyurdu ISBN aramasına sonuç vermediği için burada arama
/// kitap adı + yazar + yayınevi ile yapılır ve çıkan baskılar listelenir.
private struct KitapyurduLookupView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (BookDraft) -> Void

    @State private var titleInput = ""
    @State private var authorInput = ""
    @State private var publisherInput = ""
    @State private var results: [KitapyurduSearchResult] = []
    @State private var selectedResult: KitapyurduSearchResult?
    @State private var foundMetadata: AmazonBookMetadata?
    @State private var isSearching = false
    @State private var isLoadingProduct = false
    @State private var productGorevi: Task<Void, Never>?
    @State private var errorMessage: String?

    private var canSearch: Bool {
        titleInput.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Kitap Adı (zorunlu)", text: $titleInput)
                        .autocorrectionDisabled()
                    TextField("Yazar", text: $authorInput)
                        .autocorrectionDisabled()
                    TextField("Yayınevi", text: $publisherInput)
                        .autocorrectionDisabled()

                    Button {
                        search()
                    } label: {
                        HStack {
                            Spacer()
                            if isSearching {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Kitapyurdu'nda Aranıyor…")
                            } else {
                                Label("Kitapyurdu'nda Ara", systemImage: "magnifyingglass")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canSearch || isSearching)
                } header: {
                    Text("Ad, Yazar ve Yayınevi ile Ara")
                } footer: {
                    Text("Kitapyurdu ISBN ile arama yapmıyor; bu yüzden kitap adı, yazar ve yayınevi kullanılır. Yazar ve yayınevi doğru baskıyı bulmayı kolaylaştırır, boş bırakılabilir.")
                }

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }

                if !results.isEmpty {
                    Section {
                        ForEach(results) { result in
                            Button {
                                loadProduct(result)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.title).font(.headline)
                                        Text([result.author, result.publisher]
                                            .filter { !$0.isEmpty }
                                            .joined(separator: " • "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if isLoadingProduct, selectedResult == result {
                                        ProgressView()
                                    } else if selectedResult == result {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(KitapTema.vurgu)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Label("Bulunan baskılar", systemImage: "square.stack.3d.up")
                            .foregroundStyle(KitapTema.vurgu)
                    } footer: {
                        Text("Doğru baskıyı seçin; bilgiler ve kapak o baskıdan çekilir.")
                    }
                    .disabled(isLoadingProduct)
                }

                if let meta = foundMetadata {
                    Section("Bulunan Kitap") {
                        if let coverData = meta.coverData {
                            HStack {
                                Spacer()
                                CoverPreview(data: coverData)
                                    .frame(maxHeight: 180)
                                Spacer()
                            }
                        }

                        LabeledContent("Kitap Adı", value: meta.title)
                        if !meta.author.isEmpty {
                            LabeledContent("Yazar", value: meta.author)
                        }
                        if !meta.publisher.isEmpty {
                            LabeledContent("Yayınevi", value: meta.publisher)
                        }
                        if !meta.isbn.isEmpty {
                            LabeledContent("ISBN", value: meta.isbn)
                        }
                        if !meta.publicationYear.isEmpty {
                            LabeledContent("Basım Yılı", value: meta.publicationYear)
                        }
                        if !meta.pageCount.isEmpty {
                            LabeledContent("Sayfa Sayısı", value: meta.pageCount)
                        }
                        if !meta.category.isEmpty {
                            LabeledContent("Kategori", value: meta.category)
                        }
                        if !meta.language.isEmpty {
                            LabeledContent("Dil", value: meta.language)
                        }

                        Button {
                            var draft = BookDraft()
                            draft.isbn = meta.isbn
                            AmazonBookScraper.apply(metadata: meta, to: &draft, overwrite: true)
                            dismiss()
                            onSelect(draft)
                        } label: {
                            HStack {
                                Spacer()
                                Label("Bu Kitabı Kataloğa Ekle", systemImage: "plus.circle.fill")
                                    .font(.headline)
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Kitapyurdu'ndan Çek")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func search() {
        let title = titleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count >= 2 else { return }

        isSearching = true
        errorMessage = nil
        results = []
        selectedResult = nil
        foundMetadata = nil

        Task { @MainActor in
            defer { isSearching = false }
            do {
                let found = try await KitapyurduScraper.searchResults(
                    title: title,
                    author: authorInput.trimmingCharacters(in: .whitespacesAndNewlines),
                    publisher: publisherInput.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                if found.isEmpty {
                    errorMessage = "Kitapyurdu'nda bu ad ile kitap bulunamadı. Kitap adını kısaltıp yazar/yayınevi alanlarını boş bırakmayı deneyin."
                } else {
                    results = found
                    // Tek sonuç varsa kullanıcıyı ikinci dokunuştan kurtar
                    if found.count == 1 { loadProduct(found[0]) }
                }
            } catch {
                errorMessage = KunyeHataMetni.metin(error, kaynak: "Kitapyurdu")
            }
        }
    }

    private func loadProduct(_ result: KitapyurduSearchResult) {
        selectedResult = result
        isLoadingProduct = true
        errorMessage = nil
        foundMetadata = nil
        // Önceki satırın yanıtı geç gelip yeni seçimin üstüne yazılmasın
        productGorevi?.cancel()
        productGorevi = Task { @MainActor in
            defer { if selectedResult == result { isLoadingProduct = false } }
            do {
                let meta = try await KitapyurduScraper.fetchProduct(result: result)
                guard !Task.isCancelled, selectedResult == result else { return }
                if let meta {
                    foundMetadata = meta
                } else {
                    errorMessage = "Bu baskının sayfası okunamadı. Listeden başka bir baskı seçin."
                }
            } catch {
                guard !Task.isCancelled, selectedResult == result else { return }
                errorMessage = KunyeHataMetni.metin(error, kaynak: "Kitapyurdu")
            }
        }
    }
}

private struct AmazonLookupView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (BookDraft) -> Void

    @State private var isbnInput = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var foundMetadata: AmazonBookMetadata?
    @State private var candidates: [AmazonBookMetadata] = []
    @State private var isLoadingCandidates = false
    @State private var isShowingScanner = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("ISBN (10 veya 13 haneli)", text: $isbnInput)
#if os(iOS)
                            .keyboardType(.numberPad)
#endif
                            .autocorrectionDisabled()

                        if !isbnInput.isEmpty {
                            Button {
                                isbnInput = ""
                                foundMetadata = nil
                                candidates = []
                                errorMessage = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("ISBN alanını temizle")
                        }

                        Button {
#if os(iOS)
                            if let pasteboardString = UIPasteboard.general.string {
                                isbnInput = pasteboardString.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
#elseif os(macOS)
                            if let pasteboardString = NSPasteboard.general.string(forType: .string) {
                                isbnInput = pasteboardString.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
#endif
                        } label: {
                            Label("Yapıştır", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.borderless)
                    }

#if os(iOS)
                    Button {
                        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                            isShowingScanner = true
                        } else {
                            errorMessage = "Barkod tarayıcı bu cihazda veya simülatörde desteklenmiyor. ISBN’i elle girebilirsiniz."
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Barkodu Kamerayla Tara", systemImage: "barcode.viewfinder")
                            Spacer()
                        }
                    }
                    .disabled(isLoading)
#endif

                    Button {
                        searchAmazon()
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Amazon’dan Çekiliyor…")
                            } else {
                                Label("Amazon’dan Bilgileri Getir", systemImage: "arrow.down.circle.fill")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isbnInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                } header: {
                    Text("ISBN ile Sorgula")
                } footer: {
                    Text("Amazon Türkiye ve Amazon üzerinden kitap adı, yazar, yayınevi, basım yılı, sayfa sayısı ve kapak görseli otomatik çekilir.")
                }

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }

                if foundMetadata != nil && candidates.isEmpty {
                    Section {
                        Button {
                            loadCandidates()
                        } label: {
                            Label(
                                isLoadingCandidates ? "Baskılar aranıyor…" : "Diğer Baskıları Göster",
                                systemImage: "square.stack.3d.up"
                            )
                        }
                        .disabled(isLoadingCandidates)
                    }
                }

                if !candidates.isEmpty {
                    Section {
                        ForEach(Array(candidates.enumerated()), id: \.offset) { _, candidate in
                            Button {
                                foundMetadata = candidate
                                candidates = []
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.title).font(.headline)
                                    Text([candidate.author, candidate.publisher, candidate.publicationYear]
                                        .filter { !$0.isEmpty }
                                        .joined(separator: " • "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Label("Baskı adayları", systemImage: "square.stack.3d.up")
                            .foregroundStyle(KitapTema.vurgu)
                    } footer: {
                        Text("Doğru baskıyı seçin; bilgiler ona göre doldurulur.")
                    }
                }

                if let meta = foundMetadata {
                    Section("Bulunan Kitap") {
                        if let coverData = meta.coverData {
                            HStack {
                                Spacer()
                                CoverPreview(data: coverData)
                                    .frame(maxHeight: 180)
                                Spacer()
                            }
                        }

                        LabeledContent("Kitap Adı", value: meta.title)
                        if !meta.author.isEmpty {
                            LabeledContent("Yazar", value: meta.author)
                        }
                        if !meta.publisher.isEmpty {
                            LabeledContent("Yayınevi", value: meta.publisher)
                        }
                        if !meta.publicationYear.isEmpty {
                            LabeledContent("Basım Yılı", value: meta.publicationYear)
                        }
                        if !meta.pageCount.isEmpty {
                            LabeledContent("Sayfa Sayısı", value: meta.pageCount)
                        }
                        if !meta.category.isEmpty {
                            LabeledContent("Kategori", value: meta.category)
                        }
                        if !meta.language.isEmpty {
                            LabeledContent("Dil", value: meta.language)
                        }

                        Button {
                            var draft = BookDraft()
                            draft.isbn = meta.isbn
                            AmazonBookScraper.apply(metadata: meta, to: &draft, overwrite: true)
                            dismiss()
                            onSelect(draft)
                        } label: {
                            HStack {
                                Spacer()
                                Label("Bu Kitabı Kataloğa Ekle", systemImage: "plus.circle.fill")
                                    .font(.headline)
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Amazon’dan Kitap Çek")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") {
                        dismiss()
                    }
                }
            }
#if os(iOS)
            .fullScreenCover(isPresented: $isShowingScanner) {
                ZStack(alignment: .topTrailing) {
                    LiveISBNScannerView { scanned in
                        isShowingScanner = false
                        let isbn = ISBNFormatter.repair(scanned)
                        if isbn.isEmpty {
                            isbnInput = scanned
                            errorMessage = "Okunan barkod geçerli bir ISBN-13 değil."
                        } else {
                            isbnInput = isbn
                            searchAmazon()
                        }
                    } onCancel: {
                        isShowingScanner = false
                    }

                    Button {
                        isShowingScanner = false
                    } label: {
                        Label("Kapat", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                            .shadow(radius: 3)
                    }
                    .padding()
                    .accessibilityLabel("Barkod tarayıcıyı kapat")
                }
                .ignoresSafeArea()
            }
#endif
        }
    }

    /// Aynı kitabın farklı baskılarını listeler.
    private func loadCandidates() {
        let query = isbnInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isLoadingCandidates = true
        Task { @MainActor in
            defer { isLoadingCandidates = false }
            let found = await AmazonBookScraper.fetchCandidates(query: query)
            if found.count <= 1 {
                errorMessage = "Bu arama için başka baskı bulunamadı."
            } else {
                candidates = found
            }
        }
    }

    private func searchAmazon() {
        let query = isbnInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        foundMetadata = nil
        // Önceki ISBN'in baskı adayları yeni aramanın sonucuyla karışmasın
        candidates = []

        Task { @MainActor in
            defer { isLoading = false }
            if let result = await BookMetadataService.fetch(isbn: query) {
                foundMetadata = result
            } else {
                errorMessage = "Bu ISBN numarasıyla kitap bulunamadı. Numarayı ve internet bağlantınızı kontrol edin."
            }
        }
    }
}
#Preview {
    ContentView()
}
