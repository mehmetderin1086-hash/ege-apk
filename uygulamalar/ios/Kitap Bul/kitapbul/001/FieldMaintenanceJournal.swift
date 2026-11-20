import Foundation
import SwiftData

nonisolated enum FieldMaintenanceField: String, Codable, CaseIterable, Identifiable {
    case publisher = "Yayınevi", author = "Yazar", category = "Kategori", readingLevel = "Okuma düzeyi"
    var id: Self { self }
    var key: String {
        switch self { case .publisher: "publisher"; case .author: "author"; case .category: "category"; case .readingLevel: "readingLevel" }
    }
}

nonisolated struct FieldMaintenanceChange: Codable, Equatable {
    let bookID: UUID
    let title: String
    let before: String?
    let after: String?
    let beforeEvidence: BookFieldEvidence?
    let afterEvidence: BookFieldEvidence?
}

nonisolated struct FieldMaintenanceReceipt: Codable, Equatable, Identifiable {
    /// `needsReview`: yarım kalan işlemin kayıtları ne öncesine ne sonrasına uyuyor; yönetici karar verene kadar bekler.
    enum State: String, Codable { case prepared, committed, undoPrepared, undone, cancelled, needsReview }
    var id = UUID()
    var createdAt = Date.now
    let field: FieldMaintenanceField
    let changes: [FieldMaintenanceChange]
    var state: State = .prepared
    var undoneAt: Date?
    /// `needsReview`a düşen fişin eski durumu (`prepared` veya `undoPrepared`); karar kartı buna göre sonuçlanır.
    var reviewOrigin: State?
}

@MainActor
enum FieldMaintenanceStore {
    nonisolated static let fileName = "field_maintenance_journal.json"
    static var directoryOverride: URL?
    static var storageURL: URL? {
        (directoryOverride ?? ArchiveSettings.supportingDirectory)?.appendingPathComponent(fileName)
    }
    nonisolated static func validate(_ data: Data) throws -> [FieldMaintenanceReceipt] {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let receipts = try decoder.decode([FieldMaintenanceReceipt].self, from: data)
        guard Set(receipts.map(\.id)).count == receipts.count,
              receipts.allSatisfy({ receipt in
                  !receipt.changes.isEmpty && Set(receipt.changes.map(\.bookID)).count == receipt.changes.count &&
                  receipt.changes.allSatisfy { $0.before != $0.after && $0.after?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false } &&
                  ((receipt.state == .undone) == (receipt.undoneAt != nil))
              }) else { throw CocoaError(.fileReadCorruptFile) }
        return receipts
    }
    nonisolated static func encode(_ receipts: [FieldMaintenanceReceipt]) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(receipts); _ = try validate(data); return data
    }
    /// Arşiv birleştirmesi mevcut geri alma kayıtlarını korur; aynı işlem kimliği farklı veriyle değiştirilemez.
    nonisolated static func merge(existing: Data?, incoming: Data) throws -> Data {
        var merged = try existing.map(validate) ?? []
        for receipt in try validate(incoming) {
            if let index = merged.firstIndex(where: { $0.id == receipt.id }) {
                let prior = merged[index]
                if prior == receipt { continue }
                guard let kept = reviewResolution(prior, receipt) else {
                    throw FullArchive.ValidationError(message: "Aynı alan bakım işlem kimliği farklı kayıt içeriyor; günlük birleştirilmedi.")
                }
                merged[index] = kept
            } else { merged.append(receipt) }
        }
        merged.sort { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
        return try encode(merged)
    }
    /// Aynı içerikli iki fişten biri `needsReview` ise: bekleyen (`prepared`/`undoPrepared`) fişe karşı inceleme
    /// durumu korunur, sonuçlanmış fişe karşı sonuç korunur. Başka her fark çakışmadır.
    nonisolated private static func reviewResolution(_ a: FieldMaintenanceReceipt, _ b: FieldMaintenanceReceipt) -> FieldMaintenanceReceipt? {
        let (review, other) = a.state == .needsReview ? (a, b) : (b, a)
        guard review.state == .needsReview, other.state != .needsReview, other.field == review.field,
              other.changes == review.changes, other.createdAt == review.createdAt else { return nil }
        switch other.state {
        case .prepared, .undoPrepared: return review
        case .committed, .cancelled, .undone: return other
        case .needsReview: return nil
        }
    }
    static func allVerified() throws -> [FieldMaintenanceReceipt] {
        guard let url = storageURL else { throw CocoaError(.fileNoSuchFile) }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try validate(Data(contentsOf: url))
    }
    static func replaceVerified(_ receipts: [FieldMaintenanceReceipt]) throws {
        guard let url = storageURL else { throw CocoaError(.fileNoSuchFile) }
        let data = try encode(receipts)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

/// Dosyadaki işlem niyeti DB yazımından önce saklanır. Kesinti sonrası DB'nin atomik
/// önce/sonra durumu uzlaştırılır; güncel veya eksik kayıtların üzerine yazılmaz.
@MainActor
enum FieldMaintenanceService {
    struct Result { let receipt: FieldMaintenanceReceipt; let warning: String? }

    static func value(_ book: CatalogBook, field: FieldMaintenanceField) -> String? {
        switch field { case .publisher: book.publisher; case .author: book.author; case .category: book.category; case .readingLevel: book.readingLevel }
    }
    private static func set(_ value: String?, evidence: BookFieldEvidence?, on book: CatalogBook, field: FieldMaintenanceField) {
        switch field { case .publisher: book.publisher = value; case .author: book.author = value ?? ""; case .category: book.category = value; case .readingLevel: book.readingLevel = value }
        var metadata = BookFieldMetadata.decode(book.fieldMetadata)
        metadata[field.key] = evidence
        book.fieldMetadata = BookFieldMetadata.encode(metadata)
        book.refreshSearchKey()
    }
    private static func matches(_ receipt: FieldMaintenanceReceipt, books: [UUID: CatalogBook], after: Bool) -> Bool {
        receipt.changes.allSatisfy { change in
            guard let book = books[change.bookID], !book.isDeleted else { return false }
            return value(book, field: receipt.field) == (after ? change.after : change.before) &&
                BookFieldMetadata.decode(book.fieldMetadata)[receipt.field.key] == (after ? change.afterEvidence : change.beforeEvidence)
        }
    }
    private static func bookMap(_ context: ModelContext) throws -> [UUID: CatalogBook] {
        Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<CatalogBook>()).filter { !$0.isDeleted }.map { ($0.id, $0) })
    }
    @discardableResult
    static func reconcile(context: ModelContext) throws -> [FieldMaintenanceReceipt] {
        var journal = try FieldMaintenanceStore.allVerified()
        let books = try bookMap(context)
        var changed = false
        for index in journal.indices where journal[index].state == .prepared || journal[index].state == .undoPrepared {
            let receipt = journal[index]
            let before = matches(receipt, books: books, after: false), after = matches(receipt, books: books, after: true)
            // Uyuşmayan fiş yalnız kendini işaretler; diğer fişler uzlaştırılmaya devam eder.
            guard before || after else {
                journal[index].reviewOrigin = receipt.state
                journal[index].state = .needsReview
                changed = true
                continue
            }
            if receipt.state == .prepared { journal[index].state = after ? .committed : .cancelled }
            else {
                journal[index].state = before ? .undone : .committed
                journal[index].undoneAt = before ? .now : nil
            }
            changed = true
        }
        if changed { try FieldMaintenanceStore.replaceVerified(journal) }
        return journal
    }
    /// İncelenmesi gereken (kayıtları ne öncesine ne sonrasına uyan) fişler, en eskiden yeniye.
    static func pendingReviews(context: ModelContext) throws -> [FieldMaintenanceReceipt] {
        try reconcile(context: context).filter { $0.state == .needsReview }
    }
    /// Yönetici kararı: yalnız fiş durumu değişir, kitap kayıtlarına dokunulmaz.
    /// `applied`: işlemin gerçekte uygulanmış olduğu kabulü.
    @discardableResult
    static func resolveReview(receiptID: UUID, applied: Bool, context: ModelContext) throws -> FieldMaintenanceReceipt {
        try SchoolLibraryService.requireAdmin()
        var journal = try reconcile(context: context)
        guard let index = journal.firstIndex(where: { $0.id == receiptID && $0.state == .needsReview }) else {
            throw SchoolLibraryService.OperationError(message: "Bu alan bakım işlemi artık inceleme beklemiyor.")
        }
        let undoing = journal[index].reviewOrigin == .undoPrepared
        switch (undoing, applied) {
        case (false, true): journal[index].state = .committed
        case (false, false): journal[index].state = .cancelled
        case (true, true): journal[index].state = .undone; journal[index].undoneAt = .now
        case (true, false): journal[index].state = .committed
        }
        journal[index].reviewOrigin = nil
        try FieldMaintenanceStore.replaceVerified(journal)
        return journal[index]
    }
    static func latest(context: ModelContext) throws -> FieldMaintenanceReceipt? {
        try reconcile(context: context).last { $0.state == .committed }
    }
    static func apply(field: FieldMaintenanceField, allowedValues: [String], canonical: String, context: ModelContext,
                      persist: (() throws -> Void)? = nil) throws -> Result? {
        try SchoolLibraryService.requireAdmin()
        guard !canonical.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SchoolLibraryService.OperationError(message: "Birleştirilecek ad boş olamaz.")
        }
        // Başka açık form değişiklikleri bu bakım işleminin rollback kapsamına girmez.
        try context.save()
        var journal = try reconcile(context: context)
        let books = try bookMap(context)
        let affected = books.values.filter { allowedValues.contains(value($0, field: field) ?? "") && value($0, field: field) != canonical }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        guard !affected.isEmpty else { return nil }
        let evidence = BookFieldEvidence(source: "manual", isLocked: true)
        var receipt = FieldMaintenanceReceipt(field: field, changes: affected.map {
            FieldMaintenanceChange(bookID: $0.id, title: $0.title, before: value($0, field: field), after: canonical,
                                   beforeEvidence: BookFieldMetadata.decode($0.fieldMetadata)[field.key], afterEvidence: evidence)
        })
        journal.append(receipt)
        try FieldMaintenanceStore.replaceVerified(journal)
        do {
            for book in affected { set(canonical, evidence: evidence, on: book, field: field) }
            if let persist { try persist() } else { try context.save() }
        } catch {
            context.rollback()
            journal[journal.count - 1].state = .cancelled
            // Bu yazım da başarısızsa prepared kayıt yeniden açılışta önce durumuyla uzlaştırılır.
            try? FieldMaintenanceStore.replaceVerified(journal)
            throw error
        }
        receipt.state = .committed; journal[journal.count - 1] = receipt
        do { try FieldMaintenanceStore.replaceVerified(journal) }
        catch { return Result(receipt: receipt, warning: "Alanlar kaydedildi. Günlük sonlandırılamadı; kalıcı önce/sonra kaydı korunuyor ve yeniden açıldığında doğrulanacak.") }
        return Result(receipt: receipt, warning: nil)
    }
    @discardableResult
    static func undo(receiptID: UUID, context: ModelContext, persist: (() throws -> Void)? = nil) throws -> Result {
        try SchoolLibraryService.requireAdmin()
        try context.save()
        var journal = try reconcile(context: context)
        guard let index = journal.lastIndex(where: { $0.id == receiptID && $0.state == .committed }) else {
            throw SchoolLibraryService.OperationError(message: "Bu alan bakım işlemi geri alınabilir durumda değil.")
        }
        var receipt = journal[index]
        let books = try bookMap(context)
        guard matches(receipt, books: books, after: true) else {
            throw SchoolLibraryService.OperationError(message: "İşlemden sonra alan, kaynak/kilit veya kitap kimliği değişmiş. Güncel veriyi korumak için hiçbir kayıt geri alınmadı.")
        }
        journal[index].state = .undoPrepared
        try FieldMaintenanceStore.replaceVerified(journal)
        do {
            for change in receipt.changes {
                if let book = books[change.bookID] { set(change.before, evidence: change.beforeEvidence, on: book, field: receipt.field) }
            }
            if let persist { try persist() } else { try context.save() }
        } catch {
            context.rollback(); journal[index].state = .committed
            try? FieldMaintenanceStore.replaceVerified(journal)
            throw error
        }
        receipt.state = .undone; receipt.undoneAt = .now; journal[index] = receipt
        do { try FieldMaintenanceStore.replaceVerified(journal) }
        catch { return Result(receipt: receipt, warning: "Alanlar geri alındı. Günlük sonlandırılamadı; kalıcı kayıt yeniden açıldığında doğrulanacak.") }
        return Result(receipt: receipt, warning: nil)
    }
}
