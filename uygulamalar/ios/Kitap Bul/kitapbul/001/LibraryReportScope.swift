import Foundation

nonisolated enum LibraryReaderKind: String, CaseIterable, Identifiable, Sendable {
    case all, student, teacher, guardian, staff, other, unknownMember, manual, unresolved
    var id: Self { self }
    var title: String {
        switch self {
        case .all: "Tüm okurlar"
        case .student: "Öğrenci"
        case .teacher: "Öğretmen"
        case .guardian: "Veli"
        case .staff: "Personel"
        case .other: "Diğer üye"
        case .unknownMember: "Türü belirtilmemiş üye"
        case .manual: "Elle girilmiş okur"
        case .unresolved: "Kimliği belirlenmemiş eski kayıt"
        }
    }
}

nonisolated struct LibraryReportFilter: Equatable, Sendable {
    var start: Date = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    var end: Date = .now
    var academicPeriodLabel = "Özel tarih aralığı"
    var className = ""
    var readerKind: LibraryReaderKind = .all
    var category = ""
    var cabinet = ""
    var shelf = ""

    var locationFiltered: Bool { !cabinet.isEmpty || !shelf.isEmpty }
    var collectionFiltered: Bool { !category.isEmpty || !cabinet.isEmpty || !shelf.isEmpty }
    var scopeDescription: String {
        [academicPeriodLabel, className.isEmpty ? "Tüm sınıflar" : "Sınıf: \(className)", readerKind.title,
         category.isEmpty ? nil : "Kategori: \(category)", cabinet.isEmpty ? nil : "Dolap: \(cabinet)",
         shelf.isEmpty ? nil : "Raf: \(shelf)"].compactMap { $0 }.joined(separator: " · ")
    }
}

nonisolated struct EducationalReportPeriod: Identifiable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date

    static func choices(now: Date = .now, calendar: Calendar = .current) -> [Self] {
        let year = calendar.component(.year, from: now) - (calendar.component(.month, from: now) < 9 ? 1 : 0)
        return (0..<3).flatMap { offset -> [Self] in
            let y = year - offset
            func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
                calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? now
            }
            return [
                Self(id: "\(y):year", title: "\(y)–\(y + 1) eğitim yılı", start: date(y, 9, 1), end: date(y + 1, 8, 31)),
                Self(id: "\(y):first", title: "\(y)–\(y + 1) / 1. dönem", start: date(y, 9, 1), end: date(y + 1, 1, 31)),
                Self(id: "\(y):second", title: "\(y)–\(y + 1) / 2. dönem", start: date(y + 1, 2, 1), end: date(y + 1, 6, 30))
            ]
        }
    }
}

/// Grafik, ekran ve üç dışa aktarım biçimi aynı kapsamı ve kimlikleri kullanır.
enum LibraryReportEngine {
    struct Snapshot {
        let filter: LibraryReportFilter
        let books: [CatalogBook]
        let events: [LoanEvent]
        let loans: [ActiveLoan]
        let copies: [BookCopy]
        let stock: [UUID: LibraryStock]
        let unresolvedLoanCounts: [UUID: Int]
        let sections: [PDFReportBuilder.Section]
        let generatedAt: Date
        var table: [[String]] {
            [["Bölüm", "Gösterge", "Değer"], ["Kapsam", "Filtreler", filter.scopeDescription],
             ["Kapsam", "Başlangıç", filter.start.formatted(date: .numeric, time: .omitted)],
             ["Kapsam", "Bitiş", filter.end.formatted(date: .numeric, time: .omitted)]] + sections.flatMap { section in
                section.rows.map { [section.title, $0.0, $0.1] }
             }
        }
        func document(title: String, schoolName: String) -> Document {
            let dates = "\(filter.start.formatted(date: .numeric, time: .omitted)) – \(filter.end.formatted(date: .numeric, time: .omitted))"
            let scopeRows: [(String, String)] = [("Okul", schoolName.isEmpty ? "Belirtilmemiş" : schoolName),
                ("Eğitim dönemi", filter.academicPeriodLabel), ("Tarih", dates),
                ("Sınıf", filter.className.isEmpty ? "Tüm sınıflar" : filter.className), ("Okur türü", filter.readerKind.title),
                ("Kategori", filter.category.isEmpty ? "Tüm kategoriler" : filter.category),
                ("Dolap / raf", "\(filter.cabinet.isEmpty ? "Tüm dolaplar" : filter.cabinet) / \(filter.shelf.isEmpty ? "Tüm raflar" : filter.shelf)"),
                ("Konum hesabı", "Kimlikli nüshada kendi etkin konumu; kimliksiz adet ve eski hareketlerde eser konumu kullanılır. Kayıtlı nüshası silinmiş hareketler konum filtresinde eşleştirilemez.")]
            return Document(title: title,
                subtitle: dates + " · Düzenlenme: " + generatedAt.formatted(date: .numeric, time: .omitted),
                sections: [PDFReportBuilder.Section(title: "Rapor Kapsamı", rows: scopeRows)] + sections)
        }
    }
    struct Document {
        let title: String
        let subtitle: String
        let sections: [PDFReportBuilder.Section]
        var table: [[String]] {
            [["Bölüm", "Gösterge", "Değer"], ["Rapor", "Başlık", title], ["Rapor", "Tarih", subtitle]]
                + sections.flatMap { section in section.rows.map { [section.title, $0.0, $0.1] } }
        }
    }

    static func readerKind(studentID: UUID?, memberID: UUID?, identitySource: String?, className: String,
                           memberKindSnapshot: String? = nil, memberKinds: [UUID: String]) -> LibraryReaderKind {
        if studentID != nil && memberID != nil { return .unresolved }
        if studentID != nil && memberID == nil { return .student }
        if let memberID, studentID == nil {
            switch memberKindSnapshot ?? memberKinds[memberID] {
            case "teacher": return .teacher
            case "guardian": return .guardian
            case "staff": return .staff
            case "other": return .other
            default: return .unknownMember
            }
        }
        if identitySource == "manual" { return .manual }
        return className.isEmpty ? .unresolved : .student
    }

    static func matchesPlace(cabinet: String?, shelf: String?, filter: LibraryReportFilter) -> Bool {
        (filter.cabinet.isEmpty || cabinet == filter.cabinet) && (filter.shelf.isEmpty || shelf == filter.shelf)
    }
    private static func matchesCategory(_ book: CatalogBook, filter: LibraryReportFilter) -> Bool {
        filter.category.isEmpty || book.kategoriAdi == filter.category
    }

    /// Kimliksiz adetler eser konumunu devralır; kimlikli nüshalar kendi etkin konumuyla seçilir.
    /// Bu, sayımdaki kuralla aynıdır (`InventorySnapshot.eserYeri`): eserin yeri genel konum, o yoksa
    /// eserin dolap/rafıdır; nüshası olmayan kitap da bu yerle kapsama girer.
    static func scopedQuantity(for book: CatalogBook, copies: [BookCopy], filter: LibraryReportFilter) -> Int {
        guard matchesCategory(book, filter: filter) else { return 0 }
        let physical = copies.filter { $0.bookID == book.id }
        let untracked = max(0, max(1, book.quantity ?? 1) - physical.count)
        let selected = physical.filter { matchesPlace(cabinet: $0.effectiveCabinet(for: book), shelf: $0.effectiveShelf(for: book), filter: filter) }.count
        return selected + (matchesPlace(cabinet: book.cabinet, shelf: book.shelf, filter: filter) ? untracked : 0)
    }
    static func filteredBooks(_ books: [CatalogBook], filter: LibraryReportFilter, copies: [BookCopy] = []) -> [CatalogBook] {
        let byBook = Dictionary(grouping: copies, by: \.bookID)
        return books.filter { matchesCategory($0, filter: filter) && (!filter.locationFiltered || scopedQuantity(for: $0, copies: byBook[$0.id] ?? [], filter: filter) > 0) }
    }
    static func filteredCopies(_ copies: [BookCopy], books: [CatalogBook], filter: LibraryReportFilter) -> [BookCopy] {
        let lookup = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return copies.filter { copy in
            guard let book = lookup[copy.bookID], matchesCategory(book, filter: filter) else { return false }
            return matchesPlace(cabinet: copy.effectiveCabinet(for: book), shelf: copy.effectiveShelf(for: book), filter: filter)
        }
    }
    /// Yalnız hesaplama için geçici değerler; kalıcı eserin adedi veya konumu değiştirilmez.
    static func quantityBooks(_ books: [CatalogBook], copies: [BookCopy], filter: LibraryReportFilter) -> [CatalogBook] {
        let byBook = Dictionary(grouping: copies, by: \.bookID)
        return filteredBooks(books, filter: filter, copies: copies).map { book in
            guard filter.locationFiltered else { return book }
            let value = CatalogBook(book: book.book)
            value.quantity = scopedQuantity(for: book, copies: byBook[book.id] ?? [], filter: filter)
            if !matchesPlace(cabinet: book.cabinet, shelf: book.shelf, filter: filter) {
                value.loanedTo = nil; value.loanDueDate = nil
            }
            return value
        }
    }

    private static func matchesCollection(bookID: UUID, copyID: UUID?, bookIDs: Set<UUID>, filter: LibraryReportFilter,
                                           books: [UUID: CatalogBook], copies: [UUID: BookCopy]) -> Bool {
        guard filter.collectionFiltered else { return true }
        guard let book = books[bookID] else { return bookIDs.contains(bookID) }
        guard matchesCategory(book, filter: filter) else { return false }
        guard filter.locationFiltered else { return true }
        if let copyID {
            guard let copy = copies[copyID], copy.bookID == bookID else { return false }
            return matchesPlace(cabinet: copy.effectiveCabinet(for: book), shelf: copy.effectiveShelf(for: book), filter: filter)
        }
        // Eski kimliksiz hareketin fiziksel yeri bilinmediğinden eser konumu kullanılır.
        return matchesPlace(cabinet: book.cabinet, shelf: book.shelf, filter: filter)
    }

    static func filteredEvents(_ events: [LoanEvent], bookIDs: Set<UUID>, filter: LibraryReportFilter,
                               memberKinds: [UUID: String] = [:], books: [CatalogBook] = [], copies: [BookCopy] = []) -> [LoanEvent] {
        let bookLookup = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let copyLookup = Dictionary(copies.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return events.filter { event in
            event.date >= filter.start && event.date <= filter.end
                && matchesCollection(bookID: event.bookID, copyID: event.copyID, bookIDs: bookIDs, filter: filter, books: bookLookup, copies: copyLookup)
                && (filter.className.isEmpty || event.classSnapshot == filter.className)
                && (filter.readerKind == .all || readerKind(studentID: event.studentID, memberID: event.memberID,
                    identitySource: event.identitySource, className: event.classSnapshot ?? "",
                    memberKindSnapshot: event.memberKindSnapshot, memberKinds: memberKinds) == filter.readerKind)
        }
    }
    static func filteredLoans(_ loans: [ActiveLoan], books: [CatalogBook], copies: [BookCopy], filter: LibraryReportFilter,
                              memberKinds: [UUID: String] = [:]) -> [ActiveLoan] {
        let lookup = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let copyLookup = Dictionary(copies.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let ids = Set(lookup.keys)
        return loans.filter { loan in
            matchesCollection(bookID: loan.bookID, copyID: loan.copyID, bookIDs: ids, filter: filter, books: lookup, copies: copyLookup)
                && (filter.className.isEmpty || loan.studentClass == filter.className)
                && (filter.readerKind == .all || readerKind(studentID: loan.studentID, memberID: loan.memberID,
                    identitySource: loan.identitySource, className: loan.studentClass, memberKinds: memberKinds) == filter.readerKind)
        }
    }

    static func snapshot(books: [CatalogBook], events: [LoanEvent], loans: [ActiveLoan],
                         copies: [BookCopy], reservations: [Reservation], filter: LibraryReportFilter,
                         memberKinds: [UUID: String] = [:], now: Date = .now) throws -> Snapshot {
        guard filter.start <= filter.end else {
            throw SchoolLibraryService.OperationError(message: "Başlangıç tarihi bitişten sonra olamaz.")
        }
        let selectedBooks = filteredBooks(books, filter: filter, copies: copies)
        let ids = Set(selectedBooks.map(\.id))
        let selectedCopies = filteredCopies(copies, books: books, filter: filter)
        let selectedEvents = filteredEvents(events, bookIDs: ids, filter: filter, memberKinds: memberKinds, books: books, copies: copies)
        let selectedLoans = filteredLoans(loans, books: books, copies: copies, filter: filter, memberKinds: memberKinds)
        var stockFilter = filter; stockFilter.readerKind = .all; stockFilter.className = ""
        let stockLoans = filteredLoans(loans, books: books, copies: copies, filter: stockFilter)
        let lookup = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let copyLookup = Dictionary(copies.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let selectedReservations = reservations.filter {
            matchesCollection(bookID: $0.bookID, copyID: $0.copyID, bookIDs: ids, filter: filter, books: lookup, copies: copyLookup)
        }
        let countedBooks = quantityBooks(books, copies: copies, filter: filter)
        var stock = SchoolLibraryService.stockByBook(books: countedBooks, loans: stockLoans, copies: selectedCopies,
                                                   reservations: selectedReservations, now: now)
        var unresolvedCounts: [UUID: Int] = [:]
        if filter.locationFiltered {
            let countedLoanIDs = Set(stockLoans.map(\.id))
            // Konumu belirsiz ödünç başka bir rafta olduğu varsayılarak müsait gösterilemez.
            // Eser konumuyla zaten düşülmüş eski ödünç ikinci kez düşülmez.
            let unknownByBook = Dictionary(grouping: loans.filter { loan in
                guard ids.contains(loan.bookID) else { return false }
                guard let copyID = loan.copyID, let copy = copyLookup[copyID], copy.bookID == loan.bookID else { return true }
                return false
            }, by: \.bookID)
            for (bookID, unknown) in unknownByBook {
                let unique = Dictionary(unknown.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                unresolvedCounts[bookID] = unique.count
                let additional = unique.keys.filter { !countedLoanIDs.contains($0) }.count
                guard additional > 0, var state = stock[bookID] else { continue }
                let free = max(0, state.available + state.reserved - additional)
                state.reserved = min(state.reserved, free)
                state.available = max(0, free - state.reserved)
                stock[bookID] = state
            }
        }
        var sections = RaporMotoru.donemBolumleri(kitaplar: countedBooks, events: selectedEvents, loans: selectedLoans,
            baslangic: filter.start, bitis: filter.end, now: now, copies: selectedCopies, reservations: selectedReservations,
            className: filter.className, stockLoans: stockLoans, includeLegacyLoans: filter.readerKind == .all || filter.readerKind == .unresolved)
        if !unresolvedCounts.isEmpty {
            if let generalIndex = sections.firstIndex(where: { $0.title == "Genel Durum" }) {
                let general = sections[generalIndex]
                sections[generalIndex] = PDFReportBuilder.Section(title: general.title, rows: general.rows.map { row in
                    row.0 == "Şu an verilebilir nüsha (seçili koleksiyon)" ? (row.0, "\(stock.values.reduce(0) { $0 + $1.available })") : row
                })
            }
            let warningRows: [(String, String)] = selectedBooks.compactMap { book in
                guard let count = unresolvedCounts[book.id], count > 0 else { return nil }
                return (book.title + " · " + book.id.uuidString,
                    "\(count) etkin ödüncün nüsha konumu bilinmiyor. Müsaitlik ihtiyatlı alt sınırdır; nüsha kimliği eşleştirilmelidir.")
            }
            sections.append(PDFReportBuilder.Section(title: "Konumu belirsiz etkin ödünçler", rows: warningRows))
        }
        let participation = Dictionary(grouping: selectedEvents.filter { $0.kind == .lent && $0.memberID == nil && $0.identitySource != "manual" },
            by: { ($0.classSnapshot ?? "").isEmpty ? "Sınıfı belirlenmemiş eski kayıt" : $0.classSnapshot! })
            .map { ($0.key, "\($0.value.count) ödünç") }.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
        sections.append(PDFReportBuilder.Section(title: "Sınıf Katılımı (hareket tarihindeki sınıf)", rows: participation))
        return Snapshot(filter: filter, books: selectedBooks, events: selectedEvents, loans: selectedLoans,
                        copies: selectedCopies, stock: stock, unresolvedLoanCounts: unresolvedCounts, sections: sections, generatedAt: now)
    }
}

/// Gerçek nüsha kimliği olan kayıtlar; toplam adetten sahte kimlik üretilmez.
enum CopyRegisterEngine {
    nonisolated struct Row: Identifiable, Sendable {
        let id: UUID
        let bookID: UUID
        let code: String
        let title: String
        let author: String
        let isbn: String
        let status: String
        let condition: String
        let cabinet: String
        let shelf: String
        let activeLoans: String
        let place: String
        let addedAt: Date
        var fields: [String] {
            [id.uuidString, bookID.uuidString, code, title, author, isbn, status, condition, cabinet, shelf,
             place, activeLoans, addedAt.formatted(.iso8601.year().month().day())]
        }
    }
    nonisolated static let headers = ["Nüsha Kimliği", "Eser Kimliği", "Demirbaş", "Kitap", "Yazar", "ISBN",
                                     "Durum", "Fiziksel durum", "Dolap", "Raf", "Etkin konum", "Etkin ödünç", "Eklenme"]

    static func rows(books: [CatalogBook], copies: [BookCopy], loans: [ActiveLoan], filter: LibraryReportFilter = LibraryReportFilter()) -> [Row] {
        let lookup = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let byCopy = Dictionary(grouping: loans.compactMap { loan in loan.copyID.map { ($0, loan) } }, by: { $0.0 })
        return LibraryReportEngine.filteredCopies(copies, books: books, filter: filter).compactMap { copy in
            guard let book = lookup[copy.bookID] else { return nil }
            let loanText = (byCopy[copy.id] ?? []).map { _, loan in
                "\(loan.id.uuidString) · \(loan.studentName) · \(loan.studentClass) · son gün \(loan.dueDate.formatted(date: .numeric, time: .omitted))"
            }.joined(separator: " | ")
            return Row(id: copy.id, bookID: book.id, code: copy.accessionCode, title: book.title, author: book.author,
                isbn: book.isbn ?? "", status: book.isWithdrawn ? "Eser düşülmüş / \(copy.status)" : copy.status,
                condition: copy.condition, cabinet: copy.effectiveCabinet(for: book) ?? "", shelf: copy.effectiveShelf(for: book) ?? "",
                activeLoans: loanText, place: copy.effectivePlace(for: book), addedAt: copy.addedAt)
        }.sorted { $0.code != $1.code ? $0.code.localizedStandardCompare($1.code) == .orderedAscending : $0.id.uuidString < $1.id.uuidString }
    }

    static func untracked(books: [CatalogBook], copies: [BookCopy], filter: LibraryReportFilter = LibraryReportFilter()) -> [(book: CatalogBook, count: Int)] {
        let counts = Dictionary(grouping: copies, by: \.bookID).mapValues(\.count)
        return books.compactMap { book in
            guard LibraryReportEngine.filteredBooks([book], filter: filter).isEmpty == false, LibraryReportEngine.matchesPlace(cabinet: book.cabinet, shelf: book.shelf, filter: filter) else { return nil }
            let missing = max(0, (book.quantity ?? 1) - counts[book.id, default: 0])
            return missing > 0 ? (book: book, count: missing) : nil
        }
    }
}
