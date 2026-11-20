import Foundation
import SwiftData

nonisolated enum ScanPhotoRelation: String, Codable, CaseIterable, Identifiable, Sendable {
    case overlapping = "Aynı rafın farklı açıları"
    case distinct = "Farklı raflar / yeni nüshalar"
    var id: Self { self }
}

nonisolated struct ScanBookSource: Codable, Sendable, Equatable {
    var photoIndex: Int
    /// Gemini kutusu [ymin,xmin,ymax,xmax], 0–1000; orijinal görüntüye göre.
    var box: [Double]?
    var method: String
    var confidence: Double?
    /// Raf dilimi kutuları, orijinal fotoğrafa değil bu dilimin JPEG'ine göredir.
    var tileID: UUID? = nil
    var boxEditedManually: Bool? = nil
}

/// Kitap ve bu makbuz aynı SwiftData işlemiyle yazılır. JSON oturumu yazılmadan uygulama
/// kapanırsa aynı taslağın yeniden denenmesi adedi ikinci kez artırmaz.
@Model
final class ScanWriteReceipt {
    var id: UUID = UUID()
    @Attribute(.unique) var operationID: UUID
    var bookID: UUID
    var addedCopies: Int
    var inserted: Bool
    var beforeBookData: Data? = nil
    var afterBookData: Data? = nil
    var createdAt: Date = Date()

    init(operationID: UUID, bookID: UUID, addedCopies: Int, inserted: Bool) {
        self.operationID = operationID
        self.bookID = bookID
        self.addedCopies = addedCopies
        self.inserted = inserted
    }
}

nonisolated enum CatalogSaveDecision: Codable, Equatable, Sendable {
    case automatic
    case keepSeparate
    case mergeInto(UUID)
}

nonisolated struct CatalogSavePreview: Identifiable, Sendable {
    var incoming: Book
    var candidates: [Book]
    var suggestedTargetID: UUID?
    var requiresChoice: Bool
    var reasons: [String]
    var id: UUID { incoming.id }
    var actionText: String {
        if requiresChoice { return "Baskıyı karşılaştırıp kayıt türünü seçin" }
        if let _ = suggestedTargetID { return "Mevcut kayda \(max(1, incoming.quantity ?? 1)) nüsha eklenecek" }
        return "Ayrı kitap / baskı kaydı oluşturulacak"
    }
}

/// Bir kayıt ancak disk yazması başarılı olduğunda sonuç ve geri alma günlüğüne girer.
enum CatalogSaveEngine {
    struct SaveError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }
    struct EditionReviewRequired: LocalizedError {
        var preview: CatalogSavePreview
        var errorDescription: String? { "Birden çok olası kayıt veya eksik baskı kimliği var. Baskıları karşılaştırıp mevcut kayda nüsha eklemeyi veya ayrı baskı tutmayı seçin." }
    }

    static func preview(_ incoming: Book, catalog: [CatalogBook]) -> CatalogSavePreview {
        let live = catalog.filter { !$0.isDeleted && $0.modelContext != nil && !$0.isWithdrawn && $0.id != incoming.id }
        let candidates = live.filter { existing in
            let a = ISBNFormatter.normalize(existing.isbn ?? ""), b = ISBNFormatter.normalize(incoming.isbn ?? "")
            return (!a.isEmpty && a == b) || (!incoming.title.isEmpty && CatalogMatcher.isSimilar(existing.title, incoming.title))
        }
        let matches = candidates.filter { sameEdition($0, incoming) }
        var reasons: [String] = []
        if matches.count > 1 { reasons.append("Birden çok katalog kaydı aynı taslakla eşleşiyor.") }
        var needsChoice = matches.count > 1
        if let existing = matches.first {
            let a = ISBNFormatter.normalize(existing.isbn ?? ""), b = ISBNFormatter.normalize(incoming.isbn ?? "")
            if a.isEmpty != b.isEmpty {
                reasons.append("İki kayıttan birinin ISBN'i eksik; baskı kimliği kesin değil.")
                needsChoice = true
            }
            if a.isEmpty && b.isEmpty && (existing.author.isEmpty || incoming.author.isEmpty) {
                reasons.append("ISBN ve yazar bilgisi eşleştirmeyi kesinleştirmiyor.")
                needsChoice = true
            }
            let oldCabinet = existing.cabinet?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let newCabinet = incoming.cabinet?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let oldShelf = existing.shelf?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let newShelf = incoming.shelf?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if (!oldCabinet.isEmpty && !newCabinet.isEmpty && oldCabinet != newCabinet)
                || (!oldShelf.isEmpty && !newShelf.isEmpty && oldShelf != newShelf) {
                reasons.append("Konumlar farklı. Mevcut kayda nüsha eklerseniz onun yeri korunur; yeni konumu ayrı kayıtla veya fiziksel nüsha yerleriyle izleyin.")
                needsChoice = true
            }
        }
        if candidates.contains(where: { existing in
            let a = ISBNFormatter.normalize(existing.isbn ?? ""), b = ISBNFormatter.normalize(incoming.isbn ?? "")
            return !a.isEmpty && !b.isEmpty && a != b
        }) { reasons.append("Benzer başlıklı farklı ISBN'ler ayrı baskı olarak korunur.") }
        if candidates.contains(where: { $0.volume != nil && incoming.volume != nil && $0.volume != incoming.volume }) {
            reasons.append("Cilt numaraları farklı; otomatik birleştirme yapılmaz.")
        }
        if candidates.contains(where: { existing in
            !(existing.publisher ?? "").isEmpty && !(incoming.publisher ?? "").isEmpty
                && !CatalogMatcher.isSimilar(existing.publisher ?? "", incoming.publisher ?? "")
        }) { reasons.append("Yayınevleri farklı; baskı ve çeviri bilgisini karşılaştırın.") }
        return CatalogSavePreview(incoming: incoming, candidates: candidates.map(\.book),
            suggestedTargetID: matches.count == 1 ? matches.first?.id : nil,
            requiresChoice: needsChoice, reasons: reasons)
    }

    static func canMerge(_ incoming: Book, into existing: Book) -> Bool {
        let a = ISBNFormatter.normalize(existing.isbn ?? ""), b = ISBNFormatter.normalize(incoming.isbn ?? "")
        guard a.isEmpty || b.isEmpty || a == b else { return false }
        guard existing.volume == nil || incoming.volume == nil || existing.volume == incoming.volume else { return false }
        return CatalogMatcher.isSimilarTitle(existing.title, incoming.title)
            && (existing.author.isEmpty || incoming.author.isEmpty || CatalogMatcher.isSimilar(existing.author, incoming.author))
    }

    static func sameEdition(_ existing: CatalogBook, _ incoming: Book) -> Bool {
        let a = ISBNFormatter.normalize(existing.isbn ?? "")
        let b = ISBNFormatter.normalize(incoming.isbn ?? "")
        if let volumeA = existing.volume, let volumeB = incoming.volume, volumeA != volumeB { return false }
        if !a.isEmpty, !b.isEmpty { return a == b }
        guard !incoming.title.isEmpty, CatalogMatcher.isSimilarTitle(existing.title, incoming.title) else { return false }
        if !existing.author.isEmpty, !incoming.author.isEmpty,
           !CatalogMatcher.isSimilar(existing.author, incoming.author) { return false }
        let publisherA = existing.publisher ?? "", publisherB = incoming.publisher ?? ""
        if !publisherA.isEmpty, !publisherB.isEmpty,
           !CatalogMatcher.isSimilar(publisherA, publisherB) { return false }
        let editionA = existing.edition ?? "", editionB = incoming.edition ?? ""
        if !editionA.isEmpty, !editionB.isEmpty, CatalogMatcher.normalize(editionA) != CatalogMatcher.normalize(editionB) { return false }
        return true
    }

    @discardableResult
    static func save(_ book: Book, context: ModelContext, catalog: [CatalogBook],
                     operationID: UUID? = nil,
                     source: String = "manual",
                     matchByEdition: Bool = true,
                     decision: CatalogSaveDecision = .automatic,
                     persist: (() throws -> Void)? = nil) throws -> SaveOutcome {
        let live = catalog.filter { !$0.isDeleted && $0.modelContext != nil }
        // Aynı model kimliği, düzenleme akışını belirtir; yalnız yeni taslaklar kendiliğinden
        // işlem kimliği kazanır. Ses/raf akışları tekrar denemede açık operationID iletir.
        let operationID = operationID ?? (live.contains { $0.id == book.id } ? nil : book.id)
        if let operationID, let receipt = try receipt(for: operationID, context: context) {
            guard live.contains(where: { $0.id == receipt.bookID }) else {
                throw SaveError(message: "Bu taslak daha önce işlendi; hedef kitap artık katalogda yok. Yeni kayıt açarak devam edin.")
            }
            return .merged(receipt.bookID, added: 0)
        }
        let directEdit = live.first { $0.id == book.id }
        let existing: CatalogBook?
        if let directEdit { existing = directEdit }
        else {
            switch decision {
            case .keepSeparate: existing = nil
            case .mergeInto(let id):
                guard let selected = live.first(where: { $0.id == id }), !selected.isWithdrawn,
                      canMerge(book, into: selected.book) else {
                    throw SaveError(message: "Seçilen kayıt artık uygun değil; farklı ISBN/ciltleri ayrı tutun ve baskıyı yeniden karşılaştırın.")
                }
                existing = selected
            case .automatic:
                let review = preview(book, catalog: live)
                if matchByEdition, review.requiresChoice { throw EditionReviewRequired(preview: review) }
                existing = matchByEdition ? live.first { !$0.isWithdrawn && sameEdition($0, book) } : nil
            }
        }
        guard existing == nil || YetkiDurumu.shared.yonetici else {
            throw SaveError(message: "Mevcut kitabı değiştirmek veya nüsha artırmak için yönetici kimliği gerekir. Taslak korunuyor.")
        }
        if let existing, existing.id == book.id,
           max(1, book.quantity ?? 1) < SchoolLibraryService.minimumQuantity(for: existing, context: context) {
            throw SaveError(message: "Adet, kayıtlı nüsha veya etkin ödünç sayısından az olamaz.")
        }
        let previous = existing?.book
        let previousData = try previous.map { try JSONEncoder().encode($0) }
        var inserted: CatalogBook?
        var writeReceipt: ScanWriteReceipt?
        let outcome: SaveOutcome
        if let existing {
            if existing.id == book.id {
                existing.update(from: BookFieldMetadata.stampChanges(before: previous, after: book, source: source))
                outcome = .updated
            } else {
                let added = max(1, book.quantity ?? 1)
                let (total, overflow) = max(1, existing.quantity ?? 1).addingReportingOverflow(added)
                guard !overflow else { throw SaveError(message: "Nüsha adedi çok büyük; adedi kontrol edin.") }
                existing.quantity = total
                if !BookFieldMetadata.isLocked("cabinet", on: existing), (existing.cabinet ?? "").isEmpty, let cabinet = book.cabinet { existing.cabinet = cabinet }
                if !BookFieldMetadata.isLocked("shelf", on: existing), (existing.shelf ?? "").isEmpty, let shelf = book.shelf { existing.shelf = shelf }
                existing.fieldMetadata = BookFieldMetadata.stampChanges(before: previous, after: existing.book, source: source).fieldMetadata
                outcome = .merged(existing.id, added: added)
            }
        } else {
            let model = CatalogBook(book: BookFieldMetadata.stampChanges(before: nil, after: book, source: source))
            context.insert(model)
            inserted = model
            outcome = .inserted(model.id)
        }
        do {
        if let operationID {
            let targetID: UUID
            let added: Int
            let wasInserted: Bool
            switch outcome {
            case .inserted(let id): targetID = id; added = max(1, book.quantity ?? 1); wasInserted = true
            case .merged(let id, let delta): targetID = id; added = delta; wasInserted = false
            case .updated, .failed: targetID = book.id; added = 0; wasInserted = false
            }
            let receipt = ScanWriteReceipt(operationID: operationID, bookID: targetID, addedCopies: added, inserted: wasInserted)
            if case .merged = outcome {
                receipt.beforeBookData = previousData
                receipt.afterBookData = try existing.map { try JSONEncoder().encode($0.book) }
            }
            context.insert(receipt)
            writeReceipt = receipt
        }
            if let persist { try persist() } else { try context.save() }
            return outcome
        } catch {
            // context.rollback() başka bir ekrandaki bekleyen değişikliği de silebilir.
            if let existing, let previous { existing.update(from: previous) }
            if let inserted { context.delete(inserted) }
            if let writeReceipt { context.delete(writeReceipt) }
            throw error
        }
    }

    static func receipt(for operationID: UUID, context: ModelContext) throws -> ScanWriteReceipt? {
        try context.fetch(FetchDescriptor<ScanWriteReceipt>(predicate: #Predicate { $0.operationID == operationID })).first
    }

    static func saveBatch(_ books: [Book], context: ModelContext, catalog: [CatalogBook],
                          mergeWithinBatch: Bool, source: String = "manual", matchByEdition: Bool = true,
                          persist: (() throws -> Void)? = nil) throws -> [SaveOutcome] {
        guard YetkiDurumu.shared.yonetici else { throw SaveError(message: "Toplu kayıt değişikliği için yönetici kimliği gerekir.") }
        let snapshots = Dictionary(uniqueKeysWithValues: catalog.filter { !$0.isDeleted }.map { ($0.id, $0.book) })
        let previousIDs = Set(try context.fetch(FetchDescriptor<CatalogBook>()).map(\.id))
        var candidates = catalog
        var inserted: [CatalogBook] = []
        var outcomes: [SaveOutcome] = []
        let previousReceipts = Set(try context.fetch(FetchDescriptor<ScanWriteReceipt>()).map(\.operationID))
        do {
            for book in books {
                let outcome = try save(book, context: context, catalog: candidates, source: source,
                    matchByEdition: matchByEdition, persist: {})
                outcomes.append(outcome)
                if case .inserted(let id) = outcome,
                   let model = try context.fetch(FetchDescriptor<CatalogBook>(predicate: #Predicate { $0.id == id })).first {
                    inserted.append(model)
                    if mergeWithinBatch { candidates.append(model) }
                }
            }
            if let persist { try persist() } else { try context.save() }
            return outcomes
        } catch {
            for model in catalog where !model.isDeleted {
                if let snapshot = snapshots[model.id] { model.update(from: snapshot) }
            }
            for model in inserted where !model.isDeleted { context.delete(model) }
            for case let model as CatalogBook in context.insertedModelsArray where !previousIDs.contains(model.id) {
                context.delete(model)
            }
            for receipt in try context.fetch(FetchDescriptor<ScanWriteReceipt>()) where !previousReceipts.contains(receipt.operationID) {
                context.delete(receipt)
            }
            throw error
        }
    }

    static func undo(insertedIDs: [UUID], mergedCopies: [UUID: Int], catalog: [CatalogBook],
                     context: ModelContext, operationIDs: [UUID] = [], persist: (() throws -> Void)? = nil) throws {
        guard YetkiDurumu.shared.yonetici else { throw SaveError(message: "Eklemeyi geri almak için yönetici kimliği gerekir.") }
        guard mergedCopies.values.allSatisfy({ $0 >= 0 }) else { throw SaveError(message: "Geri alma günlüğünde geçersiz miktar var.") }
        let loans = try context.fetch(FetchDescriptor<ActiveLoan>())
        let copies = try context.fetch(FetchDescriptor<BookCopy>())
        let reservations = try context.fetch(FetchDescriptor<Reservation>())
        let receipts = try context.fetch(FetchDescriptor<ScanWriteReceipt>())
        let history = try SchoolLibraryService.historySnapshot(context: context)
        let inserted = Set(insertedIDs)
        let requested = inserted.union(mergedCopies.filter { $0.value > 0 }.map(\.key))
        let present = Set(catalog.filter { !$0.isDeleted && $0.modelContext != nil }.map(\.id))
        guard requested.isSubset(of: present) else {
            throw SaveError(message: "Bu oturumdaki bazı kayıtlar silinmiş veya birleştirilmiş. Günlük korunuyor; katalogdaki güncel kayıtları kontrol edin.")
        }
        for book in catalog where inserted.contains(book.id) {
            guard !loans.contains(where: { $0.bookID == book.id }),
                  !copies.contains(where: { $0.bookID == book.id }), (book.loanedTo ?? "").isEmpty else {
                throw SaveError(message: "“\(book.title)” için ödünç veya demirbaş kaydı oluşturulmuş; ekleme geri alınamaz.")
            }
            guard !reservations.contains(where: { $0.bookID == book.id }),
                  !history.contains(where: { $0.bookID == book.id }) else {
                throw SaveError(message: "“\(book.title)” için rezervasyon veya ödünç geçmişi oluşmuş; ekleme geri alınamaz.")
            }
        }
        for book in catalog {
            if let delta = mergedCopies[book.id], (book.quantity ?? 1) - delta < SchoolLibraryService.minimumQuantity(for: book, context: context) {
                throw SaveError(message: "“\(book.title)” adedi ödünç/demirbaş sayısının altına düşürülemez.")
            }
        }
        var operations = Set(operationIDs)
        if operations.isEmpty {
            for (id, delta) in mergedCopies where delta > 0 {
                let candidates = receipts.filter { $0.bookID == id && !$0.inserted && $0.addedCopies > 0 }
                let sum = candidates.reduce(0) { total, receipt in
                    let (value, overflow) = total.addingReportingOverflow(receipt.addedCopies)
                    return overflow ? Int.max : value
                }
                if sum == delta { operations.formUnion(candidates.map(\.operationID)) }
            }
        }
        var restoredBooks: [UUID: Book] = [:]
        for book in catalog where !book.isDeleted {
            guard let delta = mergedCopies[book.id], delta > 0 else { continue }
            var restored = book.book
            for receipt in receipts.filter({ $0.bookID == book.id && operations.contains($0.operationID) })
                .sorted(by: { $0.createdAt > $1.createdAt }) {
                guard let beforeData = receipt.beforeBookData, let afterData = receipt.afterBookData else { continue }
                let before = try JSONDecoder().decode(Book.self, from: beforeData)
                let after = try JSONDecoder().decode(Book.self, from: afterData)
                if before.cabinet != after.cabinet {
                    guard restored.cabinet == after.cabinet else { throw SaveError(message: "Dolap bilgisi eklemeden sonra değişmiş; güncel konumu korumak için geri alma uygulanmadı.") }
                    restored.cabinet = before.cabinet
                }
                if before.shelf != after.shelf {
                    guard restored.shelf == after.shelf else { throw SaveError(message: "Raf bilgisi eklemeden sonra değişmiş; güncel konumu korumak için geri alma uygulanmadı.") }
                    restored.shelf = before.shelf
                }
                let previousEvidence = BookFieldMetadata.decode(before.fieldMetadata)
                let resultEvidence = BookFieldMetadata.decode(after.fieldMetadata)
                var evidence = BookFieldMetadata.decode(restored.fieldMetadata)
                var changed = false
                for field in Set(previousEvidence.keys).union(resultEvidence.keys) where previousEvidence[field] != resultEvidence[field] {
                    guard evidence[field] == resultEvidence[field] else { throw SaveError(message: "Alan kaynağı veya kullanıcı kilidi eklemeden sonra değişmiş; geri alma uygulanmadı.") }
                    evidence[field] = previousEvidence[field]
                    changed = true
                }
                if changed { restored.fieldMetadata = evidence == previousEvidence ? before.fieldMetadata : BookFieldMetadata.encode(evidence) }
            }
            restored.quantity = max(1, (book.quantity ?? 1) - delta)
            restoredBooks[book.id] = restored
        }
        // Başka değişiklikleri önce sakla; geri alma hatasında rollback yalnız bu işlemi geri döndürür.
        try context.save()
        for book in catalog where !book.isDeleted {
            if inserted.contains(book.id) { context.delete(book) }
            else if let restored = restoredBooks[book.id] { book.update(from: restored) }
        }
        for receipt in receipts
            where operations.contains(receipt.operationID) || inserted.contains(receipt.bookID) {
            context.delete(receipt)
        }
        do { if let persist { try persist() } else { try context.save() } }
        catch { context.rollback(); throw error }
    }
}

/// Seri taramada bekleyen ISBN'lerin hangi konum/kategoriyle işleneceği; uygulama kapanıp açılınca
/// kuyruk aynı atamayla sürsün diye oturumla birlikte saklanır.
nonisolated struct SeriAtama: Codable, Sendable, Equatable {
    var location = ""
    var cabinet = ""
    var shelf = ""
    var category = ""
    var otoKayit = true
}

nonisolated struct ScanSession: Identifiable, Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable { case shelf, photo, barcode, voice }
    var id = UUID()
    var createdAt = Date()
    var updatedAt = Date()
    var kind: Kind
    var title: String
    var pendingBooks: [Book] = []
    var insertedIDs: [UUID] = []
    var mergedCopies: [UUID: Int] = [:]
    var shelfResult: ShelfScanResult?
    var shelfSavedKeys: [String] = []
    var cabinet = ""
    var shelf = ""
    var lastError: String?
    var savedOperationIDs: [UUID]? = []
    /// Model yanıtındaki ilk kayıt anahtarını düzenlenen taslağın sabit kimliğine bağlar.
    var shelfBookKeys: [String: UUID]? = [:]
    var reviewedShelfBooks: [String: GeminiBookFields]? = [:]
    /// Bellekteki fotoğraflar. Diskte JSON'a yazılmaz: `ScanSessionStore` her fotoğrafı
    /// `TaramaOturumlari/<id>/foto-<n>.jpg` dosyasına koyar, yüklerken bu diziyi geri doldurur.
    var sourceImages: [Data]? = []
    /// Yalnız diskte (JSON'da) bulunur; `sourceImages` doluyken `nil` kalır. Fotoğrafsız yüklenmiş
    /// (`hydratePhotos: false`) oturumda fotoğraf dosyalarının adlarını taşır.
    var sourceImageFiles: [String]? = nil
    /// Seri taramada henüz künyesi alınmamış ISBN'ler (işlenmekte olan ilk sırada). Uygulama kapanırsa
    /// açılışta kaldığı yerden sürer; eski JSON'larda yoktur.
    var pendingISBNs: [String]? = nil
    var seriAtama: SeriAtama? = nil
    /// Ordinary Toplu photos are independent one-book inputs, not Raf Karesi.
    /// Optional keeps all earlier session/archive JSON backward compatible.
    var separatePhotoSources: [ScanPhotoImportSource]?
    var bookSources: [UUID: ScanBookSource]? = [:]
    var photoBookKeys: [String: UUID]? = [:]
    var photoErrors: [Int: String]? = [:]
    var photoRelation: ScanPhotoRelation?
    var saveDecisions: [UUID: CatalogSaveDecision]? = [:]
    /// Aynı kitap farklı dilimlerde görünürse her kaynak kutusu ayrı korunur.
    var shelfBoxEdits: [String: [Double]]? = [:]
    var savedCopies: Int { insertedIDs.count + mergedCopies.values.reduce(0, +) }
    var hasSourceImages: Bool { !(sourceImages ?? []).isEmpty || !(sourceImageFiles ?? []).isEmpty }
}

/// Sonuçlar JSON, fotoğraflar oturum klasöründe ayrı dosya olarak yerel uygulama desteğinde kalır.
/// Her oturum ayrı atomik dosyadır; fotoğraflar JSON'dan önce yazılır, böylece yarım kalan bir yazma
/// önceki geçerli JSON'u bozmaz.
nonisolated enum ScanSessionStore {
    nonisolated(unsafe) static var directoryOverride: URL?
    /// Yazmalar tek sırada yürür: arka plan kaydı ile eşzamanlı `save` aynı dosyada yarışmaz.
    private static let writeQueue = DispatchQueue(label: "kitapbul.scan-session-writes", qos: .utility)
    /// Bu süreden eski ve bekleyen işi kalmamış oturumlar "bitmiş" sayılır; yalnız kullanıcı onayıyla elle temizlenir.
    static let retentionInterval: TimeInterval = 30 * 24 * 3600

    private static var directory: URL? {
        directoryOverride ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("TaramaOturumlari", isDirectory: true)
    }

    private static func jsonURL(_ id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent(id.uuidString + ".json")
    }

    static func photoDirectory(for id: UUID) -> URL? {
        directory?.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func save(_ session: ScanSession, updateTimestamp: Bool = true) throws {
        try writeQueue.sync { try write(session, updateTimestamp: updateTimestamp) }
    }

    /// Kodlama ve disk yazması ana iş parçacığından çıkar; hata ana iş parçacığında bildirilir.
    static func saveInBackground(_ session: ScanSession, updateTimestamp: Bool = true,
                                 onFailure: @escaping @Sendable (Error) -> Void) {
        writeQueue.async {
            do { try write(session, updateTimestamp: updateTimestamp) }
            catch { DispatchQueue.main.async { onFailure(error) } }
        }
    }

    /// Bekleyen arka plan yazmaları bitene kadar bekler (test ve kapanış için).
    static func flush() { writeQueue.sync { } }

    private static func write(_ session: ScanSession, updateTimestamp: Bool) throws {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var stored = session
        if updateTimestamp { stored.updatedAt = Date() }
        let images = session.sourceImages ?? []
        let folder = directory.appendingPathComponent(session.id.uuidString, isDirectory: true)
        if !images.isEmpty {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var names: [String] = []
            for (index, data) in images.enumerated() {
                let name = "foto-\(index).jpg"
                let url = folder.appendingPathComponent(name)
                // Aynı boyutlu ama farklı fotoğraf eski dosyada kalmasın: boyut eşitse içerik de karşılaştırılır
                let existing = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                if existing != data.count || (try? Data(contentsOf: url, options: .mappedIfSafe)) != data {
                    try data.write(to: url, options: .atomic)
                }
                names.append(name)
            }
            let fazla = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !names.contains($0) }
            for name in fazla { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
            stored.sourceImageFiles = names
        } else if (session.sourceImageFiles ?? []).isEmpty {
            if FileManager.default.fileExists(atPath: folder.path) { try? FileManager.default.removeItem(at: folder) }
            stored.sourceImageFiles = nil
        }
        // Fotoğraflar dosyalarda; fotoğrafsız oturumda alan eskisi gibi ([] ya da nil) yazılır, gidiş-dönüş eşitliği bozulmaz.
        if !images.isEmpty { stored.sourceImages = nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(stored).write(to: jsonURL(session.id, in: directory), options: .atomic)
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Fotoğraf dosyalarını `sourceImages` içine okur. Eksik dosya yerine boş veri konur ki
    /// fotoğraf sıra numaraları (kutu kaynakları buna bağlı) kaymasın.
    static func hydrated(_ session: ScanSession) -> ScanSession {
        guard let names = session.sourceImageFiles, !names.isEmpty,
              let folder = photoDirectory(for: session.id) else { return session }
        var result = session
        result.sourceImages = names.map { (try? Data(contentsOf: folder.appendingPathComponent($0))) ?? Data() }
        result.sourceImageFiles = nil
        return result
    }

    private static func decodeSession(at url: URL, hydratePhotos: Bool) throws -> ScanSession {
        let session = try decoder().decode(ScanSession.self, from: Data(contentsOf: url))
        return hydratePhotos ? hydrated(session) : session
    }

    /// Ekran listesi için hoşgörülü okuma: tek bozuk oturum dosyası diğer oturumları gizlemez.
    /// Arşiv/kurtarma yolları katı `allVerified()` kullanmaya devam eder.
    static func all(hydratePhotos: Bool = true) -> [ScanSession] {
        if let sessions = try? allVerified(hydratePhotos: hydratePhotos) { return sessions }
        guard let directory,
              let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return urls.filter { $0.pathExtension == "json" }
            .compactMap { try? decodeSession(at: $0, hydratePhotos: hydratePhotos) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    static func allVerified(hydratePhotos: Bool = true) throws -> [ScanSession] {
        guard let directory, FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return try urls.filter { $0.pathExtension == "json" }
            .map { try decodeSession(at: $0, hydratePhotos: hydratePhotos) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    static func remove(_ id: UUID) throws {
        guard let directory else { return }
        try writeQueue.sync {
            let url = jsonURL(id, in: directory)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            let folder = directory.appendingPathComponent(id.uuidString, isDirectory: true)
            if FileManager.default.fileExists(atPath: folder.path) { try? FileManager.default.removeItem(at: folder) }
        }
    }

    /// Kayıtlı oturumların toplam disk kullanımı (JSON + fotoğraf klasörleri); Ayarlar göstergesi için.
    static func diskUsage() -> (sessions: Int, bytes: Int64) {
        guard let directory,
              let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]) else { return (0, 0) }
        var total: Int64 = 0
        var count = 0
        for entry in entries {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                let files = (try? FileManager.default.contentsOfDirectory(at: entry, includingPropertiesForKeys: [.fileSizeKey])) ?? []
                total += files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            } else if entry.pathExtension == "json" {
                count += 1
                total += Int64((try? entry.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return (count, total)
    }

    /// Bu oturumun tekrar sürdürülebilecek bir işi var mı? Varsa süresi dolsa da silinmez.
    static func hasResumableWork(_ session: ScanSession) -> Bool {
        !session.pendingBooks.isEmpty
            || !(session.pendingISBNs ?? []).isEmpty
            || session.shelfResult != nil
            || (session.separatePhotoSources ?? []).contains(where: \.needsRead)
    }

    /// Açılış bakımı: (1) JSON'a gömülü eski fotoğrafları dosyalara döker (başarısızsa eski JSON kalır),
    /// (2) oturumu kalmamış fotoğraf klasörlerini siler. Hiçbir oturumu kendiliğinden silmez.
    /// Arka plan yazma kuyruğunda çalışır; bittiğinde `completion` ana iş parçacığında çağrılır.
    static func runMaintenance(completion: (@Sendable (_ migrated: Int, _ orphansRemoved: Int) -> Void)? = nil) {
        writeQueue.async {
            let result = maintenanceNow()
            if let completion { DispatchQueue.main.async { completion(result.migrated, result.orphansRemoved) } }
        }
    }

    /// Eşzamanlı bakım; yalnız yazma kuyruğundan ya da testlerden çağrılır.
    static func maintenanceNow() -> (migrated: Int, orphansRemoved: Int) {
        guard let directory,
              let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return (0, 0) }
        var migrated = 0, orphans = 0
        for url in urls where url.pathExtension == "json" {
            guard let session = try? decodeSession(at: url, hydratePhotos: false) else { continue }
            if !(session.sourceImages ?? []).isEmpty, (session.sourceImageFiles ?? []).isEmpty {
                // Yazma önce fotoğraflara, en son JSON'a gider: hata olursa eski JSON olduğu gibi kalır.
                if (try? write(session, updateTimestamp: false)) != nil { migrated += 1 }
            }
        }
        // Oturum JSON'u kalmamış (ör. depo değiştirilirken silinmiş) fotoğraf klasörleri artık kimseye ait değildir.
        for url in urls where url.pathExtension.isEmpty {
            guard let id = UUID(uuidString: url.lastPathComponent),
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  !FileManager.default.fileExists(atPath: jsonURL(id, in: directory).path) else { continue }
            try? FileManager.default.removeItem(at: url)
            orphans += 1
        }
        return (migrated, orphans)
    }

    /// Süresi dolmuş ve bekleyen işi kalmamış oturumlar ("bitmiş"), kapladıkları yerle birlikte.
    static func finishedSessions(now: Date = Date()) -> [(id: UUID, bytes: Int64)] {
        guard let directory,
              let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let session = try? decodeSession(at: url, hydratePhotos: false),
                  now.timeIntervalSince(session.updatedAt) > retentionInterval, !hasResumableWork(session) else { return nil }
            return (session.id, sessionBytes(session.id, in: directory))
        }
    }

    private static func sessionBytes(_ id: UUID, in directory: URL) -> Int64 {
        func size(_ url: URL) -> Int64 { Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        var total = size(jsonURL(id, in: directory))
        let folder = directory.appendingPathComponent(id.uuidString, isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        total += files.reduce(0) { $0 + size($1) }
        return total
    }

    /// "Bitmiş tarama oturumlarını temizle" için özet (oturum sayısı, bayt).
    static func finishedUsage(now: Date = Date()) -> (sessions: Int, bytes: Int64) {
        let liste = writeQueue.sync { finishedSessions(now: now) }
        return (liste.count, liste.reduce(0) { $0 + $1.bytes })
    }

    /// Kullanıcı onayından sonra bitmiş oturumları (JSON + fotoğraflar) siler; silinen sayısını döndürür.
    @discardableResult
    static func purgeFinished(now: Date = Date()) -> Int {
        guard let directory else { return 0 }
        return writeQueue.sync {
            let liste = finishedSessions(now: now)
            for item in liste {
                try? FileManager.default.removeItem(at: jsonURL(item.id, in: directory))
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(item.id.uuidString, isDirectory: true))
            }
            return liste.count
        }
    }

    /// Disk oturumu ve katalog farklı anda yazılmış olsa da makbuzlardan tek kez günlük kurulur.
    @MainActor
    static func reconciled(_ original: ScanSession, context: ModelContext) throws -> ScanSession {
        var session = original
        var known = Set(session.savedOperationIDs ?? [])
        for book in session.pendingBooks {
            guard let receipt = try CatalogSaveEngine.receipt(for: book.id, context: context) else { continue }
            if known.insert(receipt.operationID).inserted {
                if receipt.inserted {
                    if !session.insertedIDs.contains(receipt.bookID) { session.insertedIDs.append(receipt.bookID) }
                } else { session.mergedCopies[receipt.bookID, default: 0] += receipt.addedCopies }
            }
        }
        session.pendingBooks.removeAll { known.contains($0.id) }
        session.savedOperationIDs = Array(known)
        for (key, id) in session.shelfBookKeys ?? [:] where known.contains(id) && !session.shelfSavedKeys.contains(key) {
            session.shelfSavedKeys.append(key)
        }
        return session
    }
}
