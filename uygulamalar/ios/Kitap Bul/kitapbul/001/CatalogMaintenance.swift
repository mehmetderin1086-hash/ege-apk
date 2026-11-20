import Foundation
import SwiftData

/// Birleştirme ve geri alma defteri aynı katalog transaction'ında kalıcılaşır.
@Model
final class CatalogMergeUndoRecord {
    var id: UUID = UUID()
    var payload: Data = Data()
    var createdAt: Date = Date()
    var undoneAt: Date?
    init(payload: Data) { self.payload = payload }
}

nonisolated struct CatalogMergeGraph: Codable {
    var books: [Book]
    var loans: [ArchivedLoan]
    var copies: [ArchivedCopy]
    var reservations: [ArchivedReservation]
    var receipts: [ArchivedScanReceipt]
    var events: [LoanEvent]
}

nonisolated struct CatalogMergeUndoSnapshot: Codable {
    var bookIDs: [UUID]
    var primaryID: UUID
    var before: CatalogMergeGraph
    var after: CatalogMergeGraph
}

@MainActor
enum CatalogMaintenance {
    /// Bütün ilişkileri ana kayda taşır. Farklı geçerli ISBN'ler otomatik birleştirilemez.
    @discardableResult
    static func merge(_ group: [CatalogBook], context: ModelContext, persist: (() throws -> Void)? = nil) throws -> CatalogBook {
        try SchoolLibraryService.requireAdmin()
        guard group.count >= 2, Set(group.map(\.id)).count == group.count,
              group.allSatisfy({ !$0.isDeleted && $0.modelContext != nil }) else {
            throw SchoolLibraryService.OperationError(message: "Birleştirilecek canlı kayıtları yeniden seçin.")
        }
        let distinct = Set(group.compactMap { ISBNFormatter.isValidISBN13($0.isbn ?? "") ? ISBNFormatter.normalize($0.isbn ?? "") : nil })
        let volumes = Set(group.compactMap(\.volume))
        guard distinct.count <= 1, volumes.count <= 1, let primary = group.max(by: { score($0) < score($1) }) else {
            throw SchoolLibraryService.OperationError(message: "Farklı ISBN veya ciltler birleştirilemez; ayrı baskı olarak korunmalı.")
        }
        // Diğer ekranların değişikliklerini önce sakla; rollback bu işleme ait kalsın.
        try context.save()
        let affectedIDs = Set(group.map(\.id))
        let before = try graph(context: context, bookIDs: affectedIDs)
        let places = Set(before.books.map { ($0.cabinet ?? "") + "|" + ($0.shelf ?? "") })
        if places.count > 1 {
            guard before.books.allSatisfy({ book in
                before.copies.filter { $0.bookID == book.id }.count >= max(1, book.quantity ?? 1)
            }) else {
                throw SchoolLibraryService.OperationError(message: "Farklı konumlardaki miktar kayıtları için önce fiziksel nüsha kimliklerini ve yerlerini tamamlayın. Konumlar birleştirilerek kaybedilmedi.")
            }
        }
        let priorEvents = before.events
        var combinedQuantity = max(1, primary.quantity ?? 1)
        for other in group where other.id != primary.id {
            let (sum, overflow) = combinedQuantity.addingReportingOverflow(max(1, other.quantity ?? 1))
            guard !overflow else { throw SchoolLibraryService.OperationError(message: "Nüsha adedi birleştirilemeyecek kadar büyük.") }
            combinedQuantity = sum
        }
        let deletedSnapshots = group.filter { $0.id != primary.id }.map(\.book)
        do {
            _ = try SchoolLibraryService.migrateLegacyLoans(context: context, persist: false, bookIDs: Set(group.map(\.id)))
            let loans = try context.fetch(FetchDescriptor<ActiveLoan>())
            let copies = try context.fetch(FetchDescriptor<BookCopy>())
            // Kitap kimliği değişince miras alınan eski yer, yeni ana kaydın yerine dönüşmez.
            for copy in copies where affectedIDs.contains(copy.bookID) {
                if let oldBook = before.books.first(where: { $0.id == copy.bookID }) {
                    if copy.cabinet == nil { copy.cabinet = oldBook.cabinet ?? "" }
                    if copy.shelf == nil { copy.shelf = oldBook.shelf ?? "" }
                }
            }
            let reservations = try context.fetch(FetchDescriptor<Reservation>())
            let scanReceipts = try context.fetch(FetchDescriptor<ScanWriteReceipt>())
            let outbox = try context.fetch(FetchDescriptor<LibraryEventOutbox>())
            var evidence = BookFieldMetadata.decode(primary.fieldMetadata)
            var knownCodes = Set(copies.filter { affectedIDs.contains($0.bookID) }
                .map { $0.accessionCode.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            for other in group where other.id != primary.id {
                let otherEvidence = BookFieldMetadata.decode(other.fieldMetadata)
                func fill(_ field: String, when empty: Bool, _ update: () -> Void) {
                    guard empty, evidence[field]?.isLocked != true, !BookFieldMetadata.isLocked(field, on: primary) else { return }
                    update(); evidence[field] = otherEvidence[field] ?? .init(source: "unknown")
                }
                fill("author", when: primary.author.isEmpty) { primary.author = other.author }
                fill("isbn", when: (primary.isbn ?? "").isEmpty) { primary.isbn = other.isbn }
                fill("publisher", when: (primary.publisher ?? "").isEmpty) { primary.publisher = other.publisher }
                fill("publicationYear", when: (primary.publicationYear ?? "").isEmpty) { primary.publicationYear = other.publicationYear }
                fill("edition", when: (primary.edition ?? "").isEmpty) { primary.edition = other.edition }
                fill("pageCount", when: (primary.pageCount ?? "").isEmpty) { primary.pageCount = other.pageCount }
                fill("category", when: (primary.category ?? "").isEmpty) { primary.category = other.category }
                fill("language", when: (primary.language ?? "").isEmpty) { primary.language = other.language }
                fill("location", when: (primary.location ?? "").isEmpty) { primary.location = other.location }
                fill("cabinet", when: (primary.cabinet ?? "").isEmpty) { primary.cabinet = other.cabinet }
                fill("shelf", when: (primary.shelf ?? "").isEmpty) { primary.shelf = other.shelf }
                fill("notes", when: primary.notes.isEmpty) { primary.notes = other.notes }
                fill("coverData", when: primary.coverData == nil) { primary.coverData = other.coverData }
                fill("backCoverData", when: primary.backCoverData == nil) { primary.backCoverData = other.backCoverData }
                fill("imprintData", when: primary.imprintData == nil) { primary.imprintData = other.imprintData }
                fill("accessionCode", when: (primary.accessionCode ?? "").isEmpty) { primary.accessionCode = other.accessionCode }
                // Ana kayıttan farklı demirbaş kodu fiziksel nüsha olarak korunur; kod kaybolmaz.
                let code = (other.accessionCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !code.isEmpty, code != (primary.accessionCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                   !knownCodes.contains(code) {
                    context.insert(BookCopy(bookID: primary.id, accessionCode: code, cabinet: other.cabinet, shelf: other.shelf))
                    knownCodes.insert(code)
                }
                for loan in loans where loan.bookID == other.id { loan.bookID = primary.id; loan.bookTitleSnapshot = primary.title }
                for copy in copies where copy.bookID == other.id { copy.bookID = primary.id }
                for reservation in reservations where reservation.bookID == other.id {
                    reservation.bookID = primary.id; reservation.bookTitleSnapshot = primary.title
                }
                for receipt in scanReceipts where receipt.bookID == other.id { receipt.bookID = primary.id }
                context.delete(other)
            }
            primary.fieldMetadata = BookFieldMetadata.encode(evidence)
            primary.quantity = combinedQuantity
            primary.refreshSearchKey()
            let oldIDs = Set(deletedSnapshots.map(\.id))
            var mergedEvents = priorEvents
            for index in mergedEvents.indices where oldIDs.contains(mergedEvents[index].bookID) {
                mergedEvents[index].bookID = primary.id; mergedEvents[index].bookTitle = primary.title
            }
            try stageHistory(mergedEvents, context: context, existingOutbox: outbox)
            let after = try graph(context: context, bookIDs: affectedIDs, events: mergedEvents)
            let snapshot = CatalogMergeUndoSnapshot(bookIDs: Array(affectedIDs), primaryID: primary.id,
                                                    before: before, after: after)
            context.insert(CatalogMergeUndoRecord(payload: try encode(snapshot)))
            if let persist { try persist() } else { try context.save() }
        } catch { context.rollback(); throw error }
        // JSON aktarımı başarısızsa ilişki değişikliği dayanıklı outbox'ta kalır.
        try? SchoolLibraryService.flushHistoryOutbox(context: context)
        AppLog.write("Mükerrer birleştirme: \(group.count) kayıt; ilişkiler taşındı")
        return primary
    }

    static func latestUndoRecord(context: ModelContext) throws -> CatalogMergeUndoRecord? {
        var request = FetchDescriptor<CatalogMergeUndoRecord>(
            predicate: #Predicate { $0.undoneAt == nil }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    /// Sonradan ödünç/nüsha/makbuz/alan değişmişse eski durumu üzerine yazmaz.
    @discardableResult
    static func undoLastMerge(context: ModelContext, persist: (() throws -> Void)? = nil) throws -> Int {
        try SchoolLibraryService.requireAdmin()
        guard let record = try latestUndoRecord(context: context) else {
            throw SchoolLibraryService.OperationError(message: "Geri alınabilir kitap birleştirmesi bulunamadı.")
        }
        let snapshot = try JSONDecoder().decode(CatalogMergeUndoSnapshot.self, from: record.payload)
        let ids = Set(snapshot.bookIDs)
        let current = try graph(context: context, bookIDs: ids)
        guard try encode(current) == encode(snapshot.after) else {
            throw SchoolLibraryService.OperationError(message: "Birleştirmeden sonra kitap, nüsha, ödünç, rezervasyon veya tarama kaydı değişmiş. Güncel veriyi korumak için geri alma uygulanmadı.")
        }
        try context.save()
        do {
            try restore(snapshot.before, context: context, bookIDs: ids)
            record.undoneAt = .now
            if let persist { try persist() } else { try context.save() }
        } catch { context.rollback(); throw error }
        try? SchoolLibraryService.flushHistoryOutbox(context: context)
        return snapshot.before.books.count
    }

    static func undoSummary(context: ModelContext) throws -> String? {
        guard let record = try latestUndoRecord(context: context) else { return nil }
        let snapshot = try JSONDecoder().decode(CatalogMergeUndoSnapshot.self, from: record.payload)
        return "\(snapshot.before.books.count) kitap kaydı ve önceki nüsha/ödünç/rezervasyon bağlantıları geri getirilecek."
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    private static func graph(context: ModelContext, bookIDs: Set<UUID>, events: [LoanEvent]? = nil) throws -> CatalogMergeGraph {
        CatalogMergeGraph(
            books: try context.fetch(FetchDescriptor<CatalogBook>()).filter { !$0.isDeleted && bookIDs.contains($0.id) }.map(\.book).sorted { $0.id.uuidString < $1.id.uuidString },
            loans: try context.fetch(FetchDescriptor<ActiveLoan>()).filter { !$0.isDeleted && bookIDs.contains($0.bookID) }.map(ArchivedLoan.init).sorted { $0.id.uuidString < $1.id.uuidString },
            copies: try context.fetch(FetchDescriptor<BookCopy>()).filter { !$0.isDeleted && bookIDs.contains($0.bookID) }.map(ArchivedCopy.init).sorted { $0.id.uuidString < $1.id.uuidString },
            reservations: try context.fetch(FetchDescriptor<Reservation>()).filter { !$0.isDeleted && bookIDs.contains($0.bookID) }.map(ArchivedReservation.init).sorted { $0.id.uuidString < $1.id.uuidString },
            receipts: try context.fetch(FetchDescriptor<ScanWriteReceipt>()).filter { !$0.isDeleted && bookIDs.contains($0.bookID) }.map(ArchivedScanReceipt.init).sorted { $0.id.uuidString < $1.id.uuidString },
            events: try canonicalEvents(events ?? SchoolLibraryService.historySnapshot(context: context)).filter { bookIDs.contains($0.bookID) }.sorted { $0.id.uuidString < $1.id.uuidString })
    }

    private static func canonicalEvents(_ events: [LoanEvent]) throws -> [LoanEvent] {
        // Geçmiş JSON'u saniye çözünürlüklü ISO tarihler kullanır; outbox aktarımı semantik
        // değişiklik sayılmasın diye karşılaştırmada aynı tarih biçimini kullanıyoruz.
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([LoanEvent].self, from: encoder.encode(events))
    }

    private static func stageHistory(_ events: [LoanEvent], context: ModelContext, existingOutbox: [LibraryEventOutbox]? = nil) throws {
        let pending = try existingOutbox ?? context.fetch(FetchDescriptor<LibraryEventOutbox>())
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        for event in events {
            if let record = pending.first(where: { $0.id == event.id }) {
                record.eventData = try encoder.encode(event)
                record.replacesExisting = true
            } else {
                let record = try LibraryEventOutbox(event: event)
                record.replacesExisting = true
                context.insert(record)
            }
        }
    }

    private static func restore(_ snapshot: CatalogMergeGraph, context: ModelContext, bookIDs: Set<UUID>) throws {
        let books = try context.fetch(FetchDescriptor<CatalogBook>())
        for value in snapshot.books {
            if let book = books.first(where: { $0.id == value.id }) { book.update(from: value) }
            else { context.insert(CatalogBook(book: value)) }
        }
        let loans = try context.fetch(FetchDescriptor<ActiveLoan>()).filter { bookIDs.contains($0.bookID) }
        let wantedLoans = Set(snapshot.loans.map(\.id))
        for loan in loans where !wantedLoans.contains(loan.id) { context.delete(loan) }
        for value in snapshot.loans {
            if let loan = loans.first(where: { $0.id == value.id }) {
                let restored = value.makeActiveLoan()
                loan.bookID = restored.bookID; loan.bookTitleSnapshot = restored.bookTitleSnapshot
                loan.studentName = restored.studentName; loan.studentClass = restored.studentClass
                loan.loanedAt = restored.loanedAt; loan.dueDate = restored.dueDate; loan.extensionCount = restored.extensionCount
                loan.studentID = restored.studentID; loan.memberID = restored.memberID; loan.identitySource = restored.identitySource
                loan.copyID = restored.copyID; loan.needsIdentityReview = restored.needsIdentityReview; loan.kind = restored.kind
                loan.periodSnapshot = restored.periodSnapshot
                loan.studentNumberSnapshot = restored.studentNumberSnapshot
            } else { context.insert(value.makeActiveLoan()) }
        }
        let copies = try context.fetch(FetchDescriptor<BookCopy>()).filter { bookIDs.contains($0.bookID) }
        // Birleştirmenin demirbaş kodundan ürettiği nüshalar geri almada silinir.
        let wantedCopies = Set(snapshot.copies.map(\.id))
        for copy in copies where !wantedCopies.contains(copy.id) { context.delete(copy) }
        for value in snapshot.copies {
            if let copy = copies.first(where: { $0.id == value.id }) {
                copy.bookID = value.bookID; copy.accessionCode = value.accessionCode; copy.condition = value.condition
                copy.status = value.status; copy.note = value.note; copy.addedAt = value.addedAt
                copy.cabinet = value.cabinet; copy.shelf = value.shelf
            } else { context.insert(value.makeModel()) }
        }
        let reservations = try context.fetch(FetchDescriptor<Reservation>()).filter { bookIDs.contains($0.bookID) }
        for value in snapshot.reservations {
            if let reservation = reservations.first(where: { $0.id == value.id }) {
                reservation.bookID = value.bookID; reservation.bookTitleSnapshot = value.bookTitleSnapshot
                reservation.studentName = value.studentName; reservation.studentClass = value.studentClass
                reservation.createdAt = value.createdAt; reservation.notifiedAt = value.notifiedAt; reservation.isClosed = value.isClosed
                reservation.studentID = value.studentID; reservation.copyID = value.copyID; reservation.expiresAt = value.expiresAt
                reservation.memberID = value.memberID; reservation.identitySource = value.identitySource
                reservation.studentNumberSnapshot = value.studentNumberSnapshot
                reservation.needsIdentityReview = value.needsIdentityReview ?? false
                reservation.closureKind = value.closureKind; reservation.closedAt = value.closedAt
            } else { context.insert(value.makeModel()) }
        }
        let receipts = try context.fetch(FetchDescriptor<ScanWriteReceipt>()).filter { bookIDs.contains($0.bookID) }
        for value in snapshot.receipts {
            if let receipt = receipts.first(where: { $0.id == value.id }) {
                receipt.bookID = value.bookID; receipt.operationID = value.operationID
                receipt.addedCopies = value.addedCopies; receipt.inserted = value.inserted; receipt.createdAt = value.createdAt
                receipt.beforeBookData = value.beforeBookData; receipt.afterBookData = value.afterBookData
            } else { context.insert(value.makeModel()) }
        }
        try stageHistory(snapshot.events, context: context)
    }

    private static func score(_ book: CatalogBook) -> Int {
        [book.isbn, book.publisher, book.publicationYear, book.pageCount, book.author].compactMap { $0 }.filter { !$0.isEmpty }.count
            + (book.coverData == nil ? 0 : 2)
    }
}
