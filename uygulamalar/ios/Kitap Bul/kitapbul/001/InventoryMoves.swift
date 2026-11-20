import Foundation
import SwiftData

nonisolated struct InventoryObservation: Codable, Identifiable {
    var id = UUID()
    var bookID: UUID
    var copyID: UUID?
    var observedAt = Date.now
    var operatorName: String
    var method: String
    var observedLocation: String
    var outsideScope: Bool
}

nonisolated struct InventoryMoveCandidate: Identifiable {
    var id: UUID
    var before: Book
    var copies: [ArchivedCopy]
    var counted: Int
    var reason: String?
    var copyID: UUID? = nil
    var targetPlace: String
    var sourcePlace: String
    /// Tabloda gösterilen tam önceki/sonraki yer (eser dalında dolap/raf dâhil).
    var beforePlace: String = ""
    var afterPlace: String = ""
}

nonisolated struct InventoryMovePreview {
    var location: String
    var cabinet: String
    var shelf: String
    var candidates: [InventoryMoveCandidate]
    /// Nüsha dalında boş bırakılan dolap/raf eserin değerini devralır (varsayılan). Kapalıysa açıkça boşaltılır.
    var inheritEmpty = true
    var eligible: [InventoryMoveCandidate] { candidates.filter { $0.reason == nil } }
}

@MainActor
enum InventoryMoveService {
    static func preview(session: InventorySession, location: String, cabinet: String = "", shelf: String = "", context: ModelContext,
                        inheritEmpty: Bool = true) throws -> InventoryMovePreview {
        let target = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, target != "Tümü" else { throw SchoolLibraryService.OperationError(message: "Bulunan kitaplar için belirli bir hedef konum girin.") }
        let books = try context.fetch(FetchDescriptor<CatalogBook>())
        let copies = try context.fetch(FetchDescriptor<BookCopy>())
        let loans = try context.fetch(FetchDescriptor<ActiveLoan>())
        let reservations = try context.fetch(FetchDescriptor<Reservation>())
        let observations = session.observations ?? []
        let ids = Set(observations.filter(\.outsideScope).map(\.bookID))
        let snapshots = session.catalogSnapshot ?? session.expected ?? []
        var candidates: [InventoryMoveCandidate] = []
        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let book = books.first(where: { $0.id == id }), let snapshot = snapshots.first(where: { $0.id == id }) else {
                throw SchoolLibraryService.OperationError(message: "Sayılan kitabın başlangıç kimliği veya katalog kaydı bulunamadı. Taşıma uygulanmadı.")
            }
            let ownCopies = copies.filter { $0.bookID == id }.map(ArchivedCopy.init).sorted { $0.id.uuidString < $1.id.uuidString }
            let seenCopies = Set(observations.filter { $0.bookID == id }.compactMap(\.copyID))
            let outsideCopies = Set(observations.filter { $0.bookID == id && $0.outsideScope }.compactMap(\.copyID))
            if !outsideCopies.isEmpty {
                guard !cabinet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !shelf.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw SchoolLibraryService.OperationError(message: "Nüsha konumunu taşımak için hedef dolap veya raf alanını yazın.")
                }
                for copyID in outsideCopies.sorted(by: { $0.uuidString < $1.uuidString }) {
                    guard let copy = copies.first(where: { $0.id == copyID && $0.bookID == id }),
                          let frozen = snapshot.copies.first(where: { $0.id == copyID }) else {
                        throw SchoolLibraryService.OperationError(message: "Sayılan nüshanın kimlik bağlantısı değişti. Taşıma uygulanmadı.")
                    }
                    var reason: String?
                    // Konum ayracı " • " iken başlamış sayımın nüsha yeri, yeni " · " biçimiyle aynı sayılır.
                    let yer = copy.effectivePlace(for: book)
                    let donmusYer = frozen.location.map { $0 == yer ? $0 : BookCopy.eskiAyraciCevir($0) }
                    if (donmusYer != nil && donmusYer != yer) ||
                        (frozen.status != nil && frozen.status != copy.status) || frozen.accessionCode != copy.accessionCode {
                        reason = "Nüsha başlangıçtan sonra değişti. Yeniden sayın."
                    } else if !copy.isCirculating || book.isWithdrawn {
                        reason = "Kayıp, onarımda veya düşülen nüsha taşınamaz."
                    } else if !(book.loanedTo ?? "").isEmpty || loans.contains(where: { $0.bookID == id && ($0.copyID == nil || $0.copyID == copyID) }) {
                        reason = "Bu nüshada açık veya kimliği belirsiz ödünç var; konumu değiştirilmez."
                    } else if reservations.contains(where: { !$0.isClosed && $0.bookID == id && ($0.copyID == nil || $0.copyID == copyID) }) {
                        reason = "Bu nüsha için açık rezervasyon var; önce sırayı çözün."
                    }
                    let temizCabinet = cabinet.trimmingCharacters(in: .whitespacesAndNewlines), temizShelf = shelf.trimmingCharacters(in: .whitespacesAndNewlines)
                    let targetPlace = BookCopy.place(cabinet: temizCabinet.isEmpty ? (inheritEmpty ? book.cabinet : nil) : temizCabinet,
                                                     shelf: temizShelf.isEmpty ? (inheritEmpty ? book.shelf : nil) : temizShelf)
                    candidates.append(InventoryMoveCandidate(id: copyID, before: book.book, copies: [ArchivedCopy(copy)], counted: 1,
                        reason: reason, copyID: copyID, targetPlace: targetPlace, sourcePlace: yer,
                        beforePlace: yer, afterPlace: targetPlace))
                }
                continue
            }
            let counted = ownCopies.isEmpty ? (session.scanned["outside:" + id.uuidString] ?? 0) : seenCopies.count
            var reason: String?
            if book.location != snapshot.location || (book.quantity ?? 1) != snapshot.stock.total ||
                Set(ownCopies.map(\.id)) != Set(snapshot.copies.map(\.id)) {
                reason = "Başlangıçtan sonra konum, adet veya nüsha listesi değişti. Yeni sayım gerekir."
            } else if book.isWithdrawn || !(book.loanedTo ?? "").isEmpty || loans.contains(where: { $0.bookID == id }) {
                reason = "Düşülen veya açık ödüncü bulunan eserin konumu topluca taşınamaz."
            } else if reservations.contains(where: { !$0.isClosed && $0.bookID == id }) {
                reason = "Açık rezervasyon var; önce ayrılan nüsha ve sırayı çözün."
            } else if !ownCopies.isEmpty && (ownCopies.count != snapshot.stock.total || ownCopies.contains { $0.status != "Rafta" }) {
                reason = "Tüm nüshalar ayrı demirbaşla rafta doğrulanmadı. Kısmi eserin konumu değiştirilmez."
            } else if counted < snapshot.stock.total || snapshot.stock.available + snapshot.stock.reserved != snapshot.stock.total {
                reason = "\(counted)/\(snapshot.stock.total) nüsha sayıldı; bütün eser taşımadan önce tüm nüshaları doğrulayın."
            }
            let hedefDolap = cabinet.trimmingCharacters(in: .whitespacesAndNewlines), hedefRaf = shelf.trimmingCharacters(in: .whitespacesAndNewlines)
            candidates.append(InventoryMoveCandidate(id: id, before: book.book, copies: ownCopies, counted: counted, reason: reason, targetPlace: target,
                sourcePlace: book.location ?? "Belirtilmedi",
                beforePlace: CatalogBook.konumMetni(yer: book.location, dolap: book.cabinet, raf: book.shelf) ?? "Belirtilmedi",
                afterPlace: CatalogBook.konumMetni(yer: target, dolap: hedefDolap, raf: hedefRaf) ?? target))
        }
        return InventoryMovePreview(location: target, cabinet: cabinet.trimmingCharacters(in: .whitespacesAndNewlines),
                                    shelf: shelf.trimmingCharacters(in: .whitespacesAndNewlines), candidates: candidates,
                                    inheritEmpty: inheritEmpty)
    }

    @discardableResult
    static func apply(_ preview: InventoryMovePreview, selectedIDs: Set<UUID>, context: ModelContext, persist: (() throws -> Void)? = nil) throws -> Int {
        try applyWithReceipt(preview, selectedIDs: selectedIDs, context: context, persist: persist).changes.count
    }

    /// Taşımayı uygular ve geri alınabilir fiş döner (önce `prepared`, kayıt başarılı olunca `committed`).
    static func applyWithReceipt(_ preview: InventoryMovePreview, selectedIDs: Set<UUID>, context: ModelContext,
                                 persist: (() throws -> Void)? = nil) throws -> InventoryActionReceipt {
        try SchoolLibraryService.requireAdmin()
        guard !context.hasChanges else { throw SchoolLibraryService.OperationError(message: "Bekleyen başka değişiklik var. Önce kaydedin; taşıma uygulanmadı.") }
        guard !selectedIDs.isEmpty, selectedIDs.isSubset(of: Set(preview.eligible.map(\.id))) else {
            throw SchoolLibraryService.OperationError(message: "Yalnız doğrulanmış taşıma satırlarını seçin.")
        }
        let books = try context.fetch(FetchDescriptor<CatalogBook>()), copies = try context.fetch(FetchDescriptor<BookCopy>())
        let loans = try context.fetch(FetchDescriptor<ActiveLoan>()), reservations = try context.fetch(FetchDescriptor<Reservation>())
        for row in preview.eligible where selectedIDs.contains(row.id) {
            guard let book = books.first(where: { $0.id == row.before.id }), book.book == row.before,
                  (book.loanedTo ?? "").isEmpty else {
                throw SchoolLibraryService.OperationError(message: "Önizlemeden sonra kitap, nüsha veya ödünç bağlantısı değişti. Taşımayı yeniden önizleyin.")
            }
            let ownCopies = copies.filter { $0.bookID == book.id && (row.copyID == nil || $0.id == row.copyID) }
                .map(ArchivedCopy.init).sorted { $0.id.uuidString < $1.id.uuidString }
            guard ownCopies == row.copies,
                  !loans.contains(where: { $0.bookID == book.id && (row.copyID == nil || $0.copyID == nil || $0.copyID == row.copyID) }),
                  !reservations.contains(where: { !$0.isClosed && $0.bookID == book.id && (row.copyID == nil || $0.copyID == nil || $0.copyID == row.copyID) }) else {
                throw SchoolLibraryService.OperationError(message: "Nüsha veya açık ödünç/sıra önizlemeden sonra değişti. Taşıma uygulanmadı.")
            }
        }
        var changes: [InventoryActionChange] = []
        do {
            for row in preview.eligible where selectedIDs.contains(row.id) {
                guard let book = books.first(where: { $0.id == row.before.id }) else { continue }
                var change = InventoryActionChange(bookID: book.id, copyID: row.copyID, title: book.title)
                if let copyID = row.copyID {
                    guard let copy = copies.first(where: { $0.id == copyID }) else { throw CocoaError(.fileNoSuchFile) }
                    let before = (copy.cabinet, copy.shelf)
                    copy.cabinet = preview.cabinet.isEmpty ? (preview.inheritEmpty ? nil : "") : preview.cabinet
                    copy.shelf = preview.shelf.isEmpty ? (preview.inheritEmpty ? nil : "") : preview.shelf
                    change.assignments = [.init(key: "copy.cabinet", before: before.0, after: copy.cabinet),
                                          .init(key: "copy.shelf", before: before.1, after: copy.shelf)]
                } else {
                    let before = (book.location, book.cabinet, book.shelf, book.fieldMetadata)
                    book.location = preview.location; book.cabinet = preview.cabinet.isEmpty ? nil : preview.cabinet
                    book.shelf = preview.shelf.isEmpty ? nil : preview.shelf
                    book.fieldMetadata = BookFieldMetadata.stampChanges(before: row.before, after: book.book, source: "manual").fieldMetadata
                    book.refreshSearchKey()
                    change.assignments = [.init(key: "book.location", before: before.0, after: book.location),
                                          .init(key: "book.cabinet", before: before.1, after: book.cabinet),
                                          .init(key: "book.shelf", before: before.2, after: book.shelf),
                                          .init(key: "book.fieldMetadata", before: before.3, after: book.fieldMetadata)]
                }
                changes.append(change)
            }
            return try InventoryActionService.commit(kind: .move, title: "\(changes.count) konum kaydı taşındı", changes: changes,
                                                      context: context, persist: persist)
        } catch { context.rollback(); throw error }
    }
}

// MARK: - Sayım sonrası işlem fişleri

/// Fişin tek bir alan atamasının önceki/sonraki değeri. Anahtarlar `InventoryActionService.read/write` içinde tanımlıdır.
nonisolated struct InventoryAssignment: Codable, Equatable {
    var key: String
    var before: String?
    var after: String?
}

nonisolated struct InventoryActionChange: Codable, Equatable {
    var bookID: UUID
    var copyID: UUID?
    var title: String
    var assignments: [InventoryAssignment] = []
    /// Bu işlemle oluşturulan nüsha; geri alınca silinir.
    var createdCopyID: UUID?
}

/// Konum taşıma ve sayım sonrası işlemler (Kayıp işaretle, nüsha aç) için geri alınabilir fiş. Kapak/görsel verisi taşımaz.
nonisolated struct InventoryActionReceipt: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case move, markLost, createCopy }
    enum State: String, Codable { case prepared, committed, undone, cancelled, needsReview }
    var id = UUID()
    var createdAt = Date.now
    var kind: Kind
    var title: String
    var changes: [InventoryActionChange]
    var state: State = .prepared
    var undoneAt: Date?
}

@MainActor
enum InventoryActionStore {
    nonisolated static let fileName = "sayim_islem_fisleri.json"
    static var directoryOverride: URL?
    static var storageURL: URL? { (directoryOverride ?? ArchiveSettings.supportingDirectory)?.appendingPathComponent(fileName) }

    nonisolated static func validate(_ data: Data) throws -> [InventoryActionReceipt] {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let receipts = try decoder.decode([InventoryActionReceipt].self, from: data)
        guard Set(receipts.map(\.id)).count == receipts.count,
              receipts.allSatisfy({ !$0.changes.isEmpty && (($0.state == .undone) == ($0.undoneAt != nil)) }) else { throw CocoaError(.fileReadCorruptFile) }
        return receipts
    }
    nonisolated static func encode(_ receipts: [InventoryActionReceipt]) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(receipts); _ = try validate(data); return data
    }
    static func allVerified() throws -> [InventoryActionReceipt] {
        guard let url = storageURL else { throw CocoaError(.fileNoSuchFile) }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try validate(Data(contentsOf: url))
    }
    static func replaceVerified(_ receipts: [InventoryActionReceipt]) throws {
        guard let url = storageURL else { throw CocoaError(.fileNoSuchFile) }
        let data = try encode(receipts)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

@MainActor
enum InventoryActionService {
    static func read(_ key: String, book: CatalogBook, copy: BookCopy?) -> String? {
        switch key {
        case "book.location": book.location
        case "book.cabinet": book.cabinet
        case "book.shelf": book.shelf
        case "book.fieldMetadata": book.fieldMetadata
        case "book.notes": book.notes
        case "book.quantity": book.quantity.map(String.init)
        case "copy.cabinet": copy?.cabinet
        case "copy.shelf": copy?.shelf
        case "copy.status": copy?.status
        default: nil
        }
    }
    static func write(_ key: String, _ value: String?, book: CatalogBook, copy: BookCopy?) {
        switch key {
        case "book.location": book.location = value
        case "book.cabinet": book.cabinet = value
        case "book.shelf": book.shelf = value
        case "book.fieldMetadata": book.fieldMetadata = value
        case "book.notes": book.notes = value ?? ""
        case "book.quantity": book.quantity = value.flatMap(Int.init)
        case "copy.cabinet": copy?.cabinet = value
        case "copy.shelf": copy?.shelf = value
        case "copy.status": if let value { copy?.status = value }
        default: break
        }
    }

    private struct Lookup {
        let books: [UUID: CatalogBook]
        let copies: [UUID: BookCopy]
        init(_ context: ModelContext) throws {
            books = Dictionary(try context.fetch(FetchDescriptor<CatalogBook>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            copies = Dictionary(try context.fetch(FetchDescriptor<BookCopy>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    /// Her değişikliğin bugünkü değeri tümüyle önceki (veya sonraki) değerlere eşit mi?
    private static func matches(_ receipt: InventoryActionReceipt, _ lookup: Lookup, after: Bool) -> Bool {
        receipt.changes.allSatisfy { change in
            guard let book = lookup.books[change.bookID] else { return false }
            if let created = change.createdCopyID, (lookup.copies[created] != nil) != after { return false }
            let copy = (change.copyID ?? change.createdCopyID).flatMap { lookup.copies[$0] }
            return change.assignments.allSatisfy { assignment in
                if assignment.key.hasPrefix("copy."), copy == nil { return false }
                return read(assignment.key, book: book, copy: copy) == (after ? assignment.after : assignment.before)
            }
        }
    }

    /// Fişi önce `prepared` olarak günlüğe yazar, kaydı kalıcılaştırır, sonra `committed` yapar.
    /// Bellek değişiklikleri çağıran tarafından yapılmış olmalı; günlük yazılamazsa hiçbir şey kaydedilmez.
    static func commit(kind: InventoryActionReceipt.Kind, title: String, changes: [InventoryActionChange],
                       context: ModelContext, persist: (() throws -> Void)?) throws -> InventoryActionReceipt {
        var journal = try reconcile(context: context)
        var receipt = InventoryActionReceipt(kind: kind, title: title, changes: changes)
        journal.append(receipt)
        try InventoryActionStore.replaceVerified(journal)
        do { if let persist { try persist() } else { try context.save() } }
        catch {
            context.rollback()
            journal[journal.count - 1].state = .cancelled
            try? InventoryActionStore.replaceVerified(journal)
            throw error
        }
        receipt.state = .committed; journal[journal.count - 1] = receipt
        // Günlük sonlandırılamasa bile kayıt yazıldı; yeniden açılışta `prepared` fiş verinin durumuna göre uzlaştırılır.
        try? InventoryActionStore.replaceVerified(journal)
        return receipt
    }

    /// Yarım kalan fişleri verinin bugünkü durumuna göre sonuçlandırır; hiçbirine uymayan fiş `needsReview` olur.
    @discardableResult
    static func reconcile(context: ModelContext) throws -> [InventoryActionReceipt] {
        var journal = try InventoryActionStore.allVerified()
        guard journal.contains(where: { $0.state == .prepared }) else { return journal }
        let lookup = try Lookup(context)
        for index in journal.indices where journal[index].state == .prepared {
            let receipt = journal[index]
            if matches(receipt, lookup, after: true) { journal[index].state = .committed }
            else if matches(receipt, lookup, after: false) { journal[index].state = .cancelled }
            else { journal[index].state = .needsReview }
        }
        try InventoryActionStore.replaceVerified(journal)
        return journal
    }

    static func latestUndoable(context: ModelContext) throws -> InventoryActionReceipt? {
        try reconcile(context: context).last { $0.state == .committed }
    }

    /// Son işlemi geri alır; işlemden sonra kayıt değiştiyse hiçbir şey geri alınmaz.
    @discardableResult
    static func undo(receiptID: UUID, context: ModelContext, persist: (() throws -> Void)? = nil) throws -> InventoryActionReceipt {
        try SchoolLibraryService.requireAdmin()
        guard !context.hasChanges else { throw SchoolLibraryService.OperationError(message: "Bekleyen başka değişiklik var. Önce kaydedin; geri alınmadı.") }
        var journal = try reconcile(context: context)
        guard let index = journal.lastIndex(where: { $0.id == receiptID && $0.state == .committed }) else {
            throw SchoolLibraryService.OperationError(message: "Bu işlem geri alınabilir durumda değil.")
        }
        let receipt = journal[index]
        let lookup = try Lookup(context)
        guard matches(receipt, lookup, after: true) else {
            throw SchoolLibraryService.OperationError(message: "İşlemden sonra kayıtlar değişmiş. Güncel veriyi korumak için hiçbir şey geri alınmadı.")
        }
        let loans = try context.fetch(FetchDescriptor<ActiveLoan>()), reservations = try context.fetch(FetchDescriptor<Reservation>())
        for change in receipt.changes {
            if let created = change.createdCopyID,
               loans.contains(where: { $0.copyID == created }) || reservations.contains(where: { !$0.isClosed && $0.copyID == created }) {
                throw SchoolLibraryService.OperationError(message: "Oluşturulan nüshaya ödünç veya sıra bağlanmış; geri alınmadı.")
            }
        }
        do {
            for change in receipt.changes {
                guard let book = lookup.books[change.bookID] else { continue }
                let copy = change.copyID.flatMap { lookup.copies[$0] }
                for assignment in change.assignments { write(assignment.key, assignment.before, book: book, copy: copy) }
                if let created = change.createdCopyID, let model = lookup.copies[created] { context.delete(model) }
                book.refreshSearchKey()
            }
            if let persist { try persist() } else { try context.save() }
        } catch { context.rollback(); throw error }
        journal[index].state = .undone; journal[index].undoneAt = .now
        try? InventoryActionStore.replaceVerified(journal)
        return journal[index]
    }

    // MARK: Sayım sonrası eylemler

    /// Nüsha kimliği bilinmeyen (copyID'siz ya da eski tek alanlı) açık ödüncü olan eserler: hangi nüshanın
    /// ödünçte olduğu bilinmediğinden rafta görünen hiçbir nüsha güvenle Kayıp işaretlenemez.
    static func kimliksizOduncluEserler(entries: [InventoryCountEntry], context: ModelContext) throws -> Set<UUID> {
        let loans = try context.fetch(FetchDescriptor<ActiveLoan>())
        let books = try context.fetch(FetchDescriptor<CatalogBook>())
        let loanedBooks = Set(loans.filter { $0.copyID == nil }.map(\.bookID))
            .union(books.filter { !($0.loanedTo ?? "").isEmpty }.map(\.id))
        return Set(entries.map(\.book.id)).intersection(loanedBooks)
    }

    /// Eksik çıkan eserlerin sayılmamış, rafta ve ödüncü olmayan nüshalarını "Kayıp" yapar; nüsha kaydı
    /// olmayan adetler için eserin notuna kayıp adayı satırı eklenir. Ödünçteki nüshaya dokunulmaz.
    static func markLost(entries: [InventoryCountEntry], scanned: [String: Int], context: ModelContext,
                         now: Date = .now, persist: (() throws -> Void)? = nil) throws -> InventoryActionReceipt {
        try SchoolLibraryService.requireAdmin()
        guard !context.hasChanges else { throw SchoolLibraryService.OperationError(message: "Bekleyen başka değişiklik var. Önce kaydedin; işlem uygulanmadı.") }
        let lookup = try Lookup(context)
        let loans = try context.fetch(FetchDescriptor<ActiveLoan>())
        let loanedCopies = Set(loans.compactMap(\.copyID))
        var changes: [InventoryActionChange] = []
        let belirsiz = try kimliksizOduncluEserler(entries: entries, context: context)
        do {
            for entry in entries {
                // Kimliksiz açık ödünç varsa hangi nüshanın ödünçte olduğu bilinmez; bu eser atlanır.
                guard !belirsiz.contains(entry.book.id), let book = lookup.books[entry.book.id] else { continue }
                var remaining = max(0, entry.expected - entry.scanned)
                guard remaining > 0 else { continue }
                let candidates = entry.book.copies.compactMap { snapshot -> BookCopy? in
                    guard scanned["copy:" + snapshot.id.uuidString] == nil, let copy = lookup.copies[snapshot.id], copy.bookID == book.id,
                          copy.status == "Rafta", !loanedCopies.contains(copy.id) else { return nil }
                    return copy
                }.sorted { $0.accessionCode.localizedStandardCompare($1.accessionCode) == .orderedAscending }
                for copy in candidates.prefix(remaining) {
                    let before = copy.status
                    copy.status = "Kayıp"
                    changes.append(.init(bookID: book.id, copyID: copy.id, title: book.title,
                                         assignments: [.init(key: "copy.status", before: before, after: copy.status)]))
                    remaining -= 1
                }
                if remaining > 0, entry.book.copies.isEmpty {
                    let before = book.notes
                    let satir = "Sayım \(now.formatted(date: .numeric, time: .omitted)): \(remaining) nüsha kayıp adayı (nüsha kaydı yok)."
                    book.notes = before.isEmpty ? satir : before + "\n" + satir
                    changes.append(.init(bookID: book.id, copyID: nil, title: book.title,
                                         assignments: [.init(key: "book.notes", before: before, after: book.notes)]))
                }
            }
            guard !changes.isEmpty else { throw SchoolLibraryService.OperationError(message: "Kayıp işaretlenecek uygun nüsha bulunamadı. Ödünçteki veya sayılan nüshalara dokunulmaz.") }
            return try commit(kind: .markLost, title: "\(changes.count) kayıt Kayıp işaretlendi", changes: changes, context: context, persist: persist)
        } catch { context.rollback(); throw error }
    }

    /// Fazla okutulan esere demirbaşsız yeni nüsha açar. Konum, sayım kapsamından (Dolap/Raf) türetilir.
    static func createSurplusCopy(book bookID: UUID, scope: String, context: ModelContext,
                                  persist: (() throws -> Void)? = nil) throws -> InventoryActionReceipt {
        try SchoolLibraryService.requireAdmin()
        guard !context.hasChanges else { throw SchoolLibraryService.OperationError(message: "Bekleyen başka değişiklik var. Önce kaydedin; işlem uygulanmadı.") }
        let lookup = try Lookup(context)
        guard let book = lookup.books[bookID] else { throw SchoolLibraryService.OperationError(message: "Eser bulunamadı.") }
        let parts = scope == "Tümü" ? [] : scope.components(separatedBy: " · ")
        let cabinet = parts.first { $0.hasPrefix("Dolap ") }.map { String($0.dropFirst(6)) }
        let shelf = parts.first { $0.hasPrefix("Raf ") }.map { String($0.dropFirst(4)) }
        let existing = lookup.copies.values.filter { $0.bookID == bookID }.count
        let copy = BookCopy(bookID: bookID, accessionCode: "", cabinet: cabinet, shelf: shelf)
        var change = InventoryActionChange(bookID: bookID, copyID: nil, title: book.title, createdCopyID: copy.id)
        do {
            context.insert(copy)
            let beforeQuantity = book.quantity
            let newQuantity = max(book.quantity ?? 1, existing + 1)
            book.quantity = newQuantity
            change.assignments = [.init(key: "book.quantity", before: beforeQuantity.map(String.init), after: String(newQuantity))]
            return try commit(kind: .createCopy, title: "\(book.title) için yeni nüsha açıldı", changes: [change], context: context, persist: persist)
        } catch { context.rollback(); throw error }
    }
}
