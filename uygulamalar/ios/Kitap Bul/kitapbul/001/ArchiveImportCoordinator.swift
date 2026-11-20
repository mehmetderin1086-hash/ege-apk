import Foundation
import SwiftData
import SwiftUI
import CryptoKit

/// Normal arşiv içe aktarma da kurtarma ekranıyla aynı güvenlik kapılarından geçer.
/// Prova yalnız kendisine verilen değerleri kullanır; dosya defterlerine veya tercihlere yazmaz.
@MainActor
enum ArchiveImportCoordinator {
    struct ScopeRow: Identifiable {
        let id: String
        let title: String
        let before: Int
        let incoming: Int
        let after: Int
        var added: Int { after - before }
    }
    struct Preparation: Identifiable {
        let id = UUID()
        let before: ArchiveContents
        let incoming: ArchiveContents
        let payload: ArchiveContents
        let expected: ArchiveContents
        let beforeFingerprint: String
        let rows: [ScopeRow]
        let warnings: [String]
        let restoreSettings: Bool
        let migratedLoans: Int
        let preparedAt: Date
    }
    struct Receipt {
        let backupURL: URL
        let rows: [ScopeRow]
        let summary: String
    }
    struct ApplyError: LocalizedError {
        let message: String
        let backupURL: URL
        var errorDescription: String? { message }
    }

    static func prepare(data: Data, context: ModelContext, restoreSettings: Bool = false,
                        now: Date = .now) throws -> Preparation {
        try SchoolLibraryService.requireAdmin()
        guard !context.hasChanges else { throw failure("Kaydedilmemiş bir işlem var. Önce tamamlayın; arşiv henüz uygulanmadı.") }
        let incoming = try FullArchive.readValidated(data: data)
        let before = try FullArchive.snapshot(context: context)
        let plan = try makePlan(before: before, incoming: incoming, restoreSettings: restoreSettings, now: now)
        let expected = try isolatedTrial(plan.contents)
        // Birlikte okuma/yazma ve ilişki doğrulaması: kapaklar ve bütün metadata da kapsanır.
        _ = try FullArchive.readValidated(data: FullArchive.buildVerified(expected))
        let rows = scope(before: before, incoming: incoming, after: expected)
        var warnings = plan.warnings
        let reviewCount = expected.activeLoans.filter { $0.needsIdentityReview == true }.count
        if reviewCount > 0 { warnings.append("\(reviewCount) ödünç kimlik eşleştirmesi gerektiriyor; kişi tahmin edilmedi.") }
        return Preparation(before: before, incoming: incoming, payload: plan.contents, expected: expected,
                           beforeFingerprint: try fingerprint(before), rows: rows, warnings: warnings,
                           restoreSettings: restoreSettings, migratedLoans: plan.migrated, preparedAt: now)
    }

    /// Bütün kapılar eşzamanlıdır: önizleme sonrası değişiklik varsa yeni önizleme gerekir.
    /// verify yalnız hata enjeksiyonlu testler ve ek kapsam denetimleri içindir.
    static func apply(_ preparation: Preparation, context: ModelContext, backupDirectory: URL? = nil,
                      verify: ((ModelContext) throws -> Void)? = nil) throws -> Receipt {
        try SchoolLibraryService.requireAdmin()
        guard !context.hasChanges else { throw failure("Kaydedilmemiş bir işlem var; arşiv uygulanmadı.") }
        let current = try FullArchive.snapshot(context: context)
        let pendingBefore = try context.fetch(FetchDescriptor<LibraryEventOutbox>()).map(PendingEventSnapshot.init)
        guard try fingerprint(current) == preparation.beforeFingerprint else {
            throw failure("Önizlemeden sonra katalog, kişiler, geçmiş veya ayarlar değişti. Dosyayı yeniden seçip yeni önizlemeyi inceleyin.")
        }
        let directory = try backupRoot(override: backupDirectory).appendingPathComponent(preparation.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let backupURL = directory.appendingPathComponent("Islem-Oncesi-Tam-Arsiv.zip")
        let beforeData = try FullArchive.buildVerified(current)
        try beforeData.write(to: backupURL, options: .atomic)
        let verifiedBackup = try FullArchive.readValidated(from: backupURL)
        guard try fingerprint(verifiedBackup) == preparation.beforeFingerprint else {
            throw failure("İşlem öncesi tam yedek doğrulanamadı; canlı veriler değiştirilmedi.")
        }
        // Gelen dosya da saklanır; bir çakışmada hiçbir arşiv kaydı kaybolmaz.
        try FullArchive.buildVerified(preparation.incoming).write(to: directory.appendingPathComponent("Secilen-Arsiv.zip"), options: .atomic)
        try captureRawMetadata(at: directory)
        try writeStatus("hazir", at: directory, rows: preparation.rows)
        let previousWarning = LibrarySyncStatus.shared.warning
        do {
            _ = try ArchiveLoanRestorer.restoreAll(preparation.payload, context: context, restoreSettings: true)
            try verify?(context)
            let after = try FullArchive.snapshot(context: context)
            guard try fingerprint(after) == fingerprint(preparation.expected) else {
                throw failure("Geri yükleme sonrası eser, kapak, kişi veya ödünç kapsamı provayla aynı değil.")
            }
            try writeStatus("dogrulandi", at: directory, rows: preparation.rows)
            let added = preparation.rows.filter { $0.id != "covers" }.reduce(0) { $0 + max(0, $1.added) }
            return Receipt(backupURL: backupURL, rows: preparation.rows,
                           summary: "Arşiv geri yükleme doğrulandı. \(added) yeni kayıt eklendi. Önceki eserler, kapaklar, kişiler ve açık ödünçler korundu. İşlem öncesi tam yedek paylaşılabilir.")
        } catch {
            let original = error
            do {
                try rollbackDatabase(to: preparation.before, pending: pendingBefore, context: context)
                try StoreRecovery.rollbackMetadata(from: directory)
                LibrarySyncStatus.shared.warning = previousWarning
                let restored = try FullArchive.snapshot(context: context)
                guard try fingerprint(restored) == preparation.beforeFingerprint else {
                    throw failure("İşlem öncesi kapsam geri alma kontrolünden geçmedi.")
                }
                try writeStatus("geri_alindi", at: directory, rows: preparation.rows)
            } catch {
                try? writeStatus("geri_alma_bekliyor", at: directory, rows: preparation.rows)
                throw ApplyError(message: "Arşiv doğrulanamadı ve geri alma tamamlanamadı. İşlem öncesi doğrulanmış tam yedek korunuyor. Veri Kurtarma ile bu yedeği açın. \(original.localizedDescription)", backupURL: backupURL)
            }
            throw ApplyError(message: "Arşiv uygulanamadı; işlem öncesi veri ve ayarlar geri getirildi. Doğrulanmış tam yedek korundu. \(original.localizedDescription)", backupURL: backupURL)
        }
    }

    static func scope(before: ArchiveContents, incoming: ArchiveContents, after: ArchiveContents) -> [ScopeRow] {
        [ScopeRow(id: "books", title: "Eser", before: before.books.count, incoming: incoming.books.count, after: after.books.count),
         ScopeRow(id: "covers", title: "Kapak", before: before.books.filter { $0.coverData != nil }.count, incoming: incoming.books.filter { $0.coverData != nil }.count, after: after.books.filter { $0.coverData != nil }.count),
         ScopeRow(id: "copies", title: "Fiziksel nüsha", before: before.copies.count, incoming: incoming.copies.count, after: after.copies.count),
         ScopeRow(id: "loans", title: "Açık ödünç", before: before.activeLoans.count, incoming: incoming.activeLoans.count, after: after.activeLoans.count),
         ScopeRow(id: "reservations", title: "Rezervasyon", before: before.reservations.count, incoming: incoming.reservations.count, after: after.reservations.count),
         ScopeRow(id: "history", title: "Geçmiş hareketi", before: before.loanEvents.count, incoming: incoming.loanEvents.count, after: after.loanEvents.count),
         ScopeRow(id: "students", title: "Öğrenci", before: before.students.count, incoming: incoming.students.count, after: after.students.count),
         ScopeRow(id: "members", title: "Üye", before: before.members.count, incoming: incoming.members.count, after: after.members.count),
         ScopeRow(id: "graduates", title: "Mezun", before: before.graduatedStudents.count, incoming: incoming.graduatedStudents.count, after: after.graduatedStudents.count),
         ScopeRow(id: "sessions", title: "Tarama oturumu", before: before.scanSessions.count, incoming: incoming.scanSessions.count, after: after.scanSessions.count),
         ScopeRow(id: "receipts", title: "Tarama makbuzu", before: before.scanReceipts.count, incoming: incoming.scanReceipts.count, after: after.scanReceipts.count),
         ScopeRow(id: "undo", title: "Birleştirme geri alma", before: before.mergeUndoRecords.count, incoming: incoming.mergeUndoRecords.count, after: after.mergeUndoRecords.count)]
    }

    /// Ayrı katalog provası bütün arşiv kimliklerini korur; mevcut global defterleri kullanmaz.
    /// Eski stok belirsizliği aynen taşınabilir; yeni dolaşım merkezi servis kurallarını kullanır.
    static func replacementTrial(_ incoming: ArchiveContents, now: Date) throws -> ArchiveContents {
        let studentIDs = Set(incoming.students.map(\.id))
        guard !incoming.graduatedStudents.contains(where: { studentIDs.contains($0.id) }) else {
            throw failure("Arşivde aynı öğrenci hem aktif hem mezun. Kimlik durumunu düzeltin; kısmi katalog açılmadı.")
        }
        let plan = try makePlan(before: ArchiveContents(), incoming: incoming, restoreSettings: true, now: now, validateStock: false)
        return try isolatedTrial(plan.contents, refreshAt: now)
    }

    struct Plan { let contents: ArchiveContents; let warnings: [String]; let migrated: Int }
    static func makePlan(before: ArchiveContents, incoming: ArchiveContents, restoreSettings: Bool, now: Date, validateStock: Bool = true) throws -> Plan {
        func appendNew<T>(_ current: [T], _ next: [T], id: (T) -> UUID) -> [T] {
            let ids = Set(current.map(id)); return current + next.filter { !ids.contains(id($0)) }
        }
        let bookIDs = Set(before.books.map(\.id))
        let loanIDs = Set(before.activeLoans.map(\.id)), copyIDs = Set(before.copies.map(\.id))
        let reservationIDs = Set(before.reservations.map(\.id))
        if !before.activeLoans.isEmpty || !before.loanEvents.isEmpty {
            guard incoming.activeLoans.allSatisfy({ loanIDs.contains($0.id) }),
                  incoming.copies.allSatisfy({ copyIDs.contains($0.id) }),
                  incoming.reservations.allSatisfy({ reservationIDs.contains($0.id) }),
                  !incoming.books.contains(where: { !bookIDs.contains($0.id) && !($0.loanedTo ?? "").isEmpty }) else {
                throw failure("Canlı ödünç/geçmiş bulunan kataloğa eski operasyon durumu eklenemez. İşlem yapılmadı; arşivi ayrı depoda Veri Kurtarma ile açın.")
            }
        }
        let graduates = Set(before.graduatedStudents.map(\.id)), students = Set(before.students.map(\.id))
        guard !incoming.students.contains(where: { graduates.contains($0.id) && !students.contains($0.id) }) else {
            throw failure("Arşiv, mevcut mezun kimliğini aktif öğrenciye dönüştürüyor. Önce Mezun Defteri'nden geri çağırın veya arşivi ayrı depoda kurtarın.")
        }
        var combined = ArchiveContents(
            books: appendNew(before.books, incoming.books, id: \.id),
            loanEvents: appendNew(before.loanEvents, incoming.loanEvents, id: \.id),
            activeLoans: appendNew(before.activeLoans, incoming.activeLoans, id: \.id),
            copies: appendNew(before.copies, incoming.copies, id: \.id),
            reservations: appendNew(before.reservations, incoming.reservations, id: \.id),
            students: appendNew(before.students, incoming.students, id: \.id),
            members: appendNew(before.members, incoming.members, id: \.id),
            settings: before.settings, supportingFiles: before.supportingFiles,
            scanReceipts: appendNew(before.scanReceipts, incoming.scanReceipts, id: \.operationID),
            scanSessions: appendNew(before.scanSessions, incoming.scanSessions, id: \.id),
            graduatedStudents: appendNew(before.graduatedStudents, incoming.graduatedStudents, id: \.id),
            mergeUndoRecords: appendNew(before.mergeUndoRecords, incoming.mergeUndoRecords, id: \.id))
        let liveIDs = Set(combined.students.map(\.id))
        combined.graduatedStudents.removeAll { liveIDs.contains($0.id) }
        var warnings: [String] = []
        let overlappingBooks = incoming.books.filter { bookIDs.contains($0.id) }
        if !overlappingBooks.isEmpty { warnings.append("Aynı kimlikli \(overlappingBooks.count) eserde mevcut kayıt ve kapak korunur; arşiv sürümü üzerine yazılmaz.") }
        if restoreSettings { combined.settings.merge(incoming.settings) { _, imported in imported } }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = .sortedKeys
        for (name, data) in incoming.supportingFiles where ArchiveSettings.supportingFileNames.contains(name) {
            if name == "Mezunlar.json" { continue }
            if name == StudentImportStore.fileName {
                var entries = try combined.supportingFiles[name].map(StudentImportStore.validate) ?? []
                for entry in try StudentImportStore.validate(data) {
                    if let old = entries.first(where: { $0.id == entry.id }) {
                        guard old == entry else { throw failure("Aynı öğrenci aktarım kimliğinin farklı günlüğü var; ayrı depoda kurtarın.") }
                    } else { entries.append(entry) }
                }
                combined.supportingFiles[name] = try encoder.encode(entries)
            } else if name == InventoryActionStore.fileName {
                combined.supportingFiles[name] = try InventoryActionStore.merge(existing: combined.supportingFiles[name], incoming: data)
            } else if name == FieldMaintenanceStore.fileName {
                combined.supportingFiles[name] = try FieldMaintenanceStore.merge(existing: combined.supportingFiles[name], incoming: data)
            } else if combined.supportingFiles[name] == nil {
                combined.supportingFiles[name] = data
            } else if combined.supportingFiles[name] != data {
                warnings.append("\(name): devam eden mevcut çalışma korundu. Arşivdeki sürüm seçilen dosyada saklanır.")
            }
        }
        // restoreAll mezun defterini her zaman yazar; prova aynı kalıcı kapsamı bekler.
        combined.supportingFiles["Mezunlar.json"] = try encoder.encode(combined.graduatedStudents)
        var migrated = 0
        for index in combined.books.indices where !bookIDs.contains(combined.books[index].id) && !(combined.books[index].loanedTo ?? "").isEmpty {
            let book = combined.books[index]
            let id = Book.stableID(title: "legacy-loan", author: book.id.uuidString, isbn: "")
            if !combined.activeLoans.contains(where: { $0.id == id }) {
                let name = book.loanedTo ?? "", key = CatalogMatcher.normalize(name)
                let candidates = combined.students.filter { CatalogMatcher.normalize($0.name) == key }
                let memberCollision = combined.members.contains { CatalogMatcher.normalize($0.name) == key }
                let student = !memberCollision && candidates.count == 1 ? candidates.first : nil
                combined.activeLoans.append(ArchivedLoan(id: id, bookID: book.id, bookTitleSnapshot: book.title,
                    studentName: name, studentClass: student?.className ?? "", loanedAt: now, dueDate: book.loanDueDate ?? now,
                    studentID: student?.id, identitySource: "legacy", studentNumberSnapshot: student?.number,
                    needsIdentityReview: student == nil, kind: "library"))
                migrated += 1
            }
            combined.books[index].loanedTo = nil; combined.books[index].loanDueDate = nil
        }
        // Eski etkin kayıtların kişi göçü de prova verisinden yapılır; global defter okunmaz.
        // Mevcut aktif kimlikler ve bilinçli elle girilmiş kimlikler değiştirilmez.
        func legacyStudent(name: String, className: String) -> Student? {
            let key = CatalogMatcher.normalize(name)
            guard !combined.members.contains(where: { CatalogMatcher.normalize($0.name) == key }) else { return nil }
            let candidates = combined.students.filter { CatalogMatcher.normalize($0.name) == key && (className.isEmpty || $0.className == className) }
            return candidates.count == 1 ? candidates.first : nil
        }
        for index in combined.activeLoans.indices where !loanIDs.contains(combined.activeLoans[index].id) {
            let loan = combined.activeLoans[index]
            guard loan.studentID == nil, loan.memberID == nil, loan.identitySource == nil || loan.identitySource == "legacy" else { continue }
            let student = legacyStudent(name: loan.studentName, className: loan.studentClass)
            combined.activeLoans[index].studentID = student?.id
            combined.activeLoans[index].studentNumberSnapshot = student?.number
            combined.activeLoans[index].needsIdentityReview = student == nil
        }
        if migrated > 0 { warnings.append("\(migrated) eski tekil ödünç sabit kimlikle taşınacak; belirsiz kişi eşleştirilmez.") }
        if validateStock { try validateProjectedStock(before: before, after: combined) }
        return Plan(contents: combined, warnings: warnings, migrated: migrated)
    }

    private static func validateProjectedStock(before: ArchiveContents, after: ArchiveContents) throws {
        let oldCopies = Dictionary(grouping: before.copies, by: \.bookID).mapValues(\.count)
        let newCopies = Dictionary(grouping: after.copies, by: \.bookID).mapValues(\.count)
        let oldLoans = Dictionary(grouping: before.activeLoans, by: \.bookID).mapValues(\.count)
        let newLoans = Dictionary(grouping: after.activeLoans, by: \.bookID).mapValues(\.count)
        let oldUnidentified = Dictionary(grouping: before.activeLoans.filter { $0.copyID == nil }, by: \.bookID).mapValues(\.count)
        let newUnidentified = Dictionary(grouping: after.activeLoans.filter { $0.copyID == nil }, by: \.bookID).mapValues(\.count)
        let oldBookIDs = Set(before.books.map(\.id)), oldLoanIDs = Set(before.activeLoans.map(\.id))
        for book in after.books {
            let quantity = book.quantity ?? 1
            let copies = newCopies[book.id, default: 0], loans = newLoans[book.id, default: 0]
            // Eski tutarsızlık korunabilir; yeni arşiv onu büyütemez. Aynı UUID'li
            // eserin current-wins adedi arşivdeki daha yüksek miktarla örtülmez.
            if (!oldBookIDs.contains(book.id) && quantity < 1)
                || (copies > quantity && copies > oldCopies[book.id, default: 0])
                || (loans > quantity && loans > oldLoans[book.id, default: 0])
                || (newUnidentified[book.id, default: 0] > max(0, quantity - copies)
                    && newUnidentified[book.id, default: 0] > oldUnidentified[book.id, default: 0]) {
                throw failure("“\(book.title)” mevcut adedi \(quantity); birleşim \(copies) fiziksel nüsha ve \(loans) açık ödünç üretiyor. Stok tutarsızlığı büyütülmedi; adet/nüsha ilişkisini düzeltin veya arşivi ayrı depoda kurtarın.")
            }
        }
        // Tekrarlı eski UUID daha sonra arşiv doğrulamasında anlaşılır hatayla
        // reddedilir; Dictionary oluşturmak o kontrolden önce çökemez.
        let copiesByID = Dictionary(after.copies.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for loan in after.activeLoans where !oldLoanIDs.contains(loan.id) {
            if let id = loan.copyID, let copy = copiesByID[id], copy.status != "Rafta" {
                throw failure("Arşivde yeni ödünç, rafta olmayan fiziksel nüshaya bağlı; işlem yapılmadı.")
            }
        }
    }

    /// Metadata parametredir: burada FullArchive.snapshot (global dosya okuyan) kullanılmaz.
    private static func isolatedTrial(_ contents: ArchiveContents, refreshAt: Date? = nil) throws -> ArchiveContents {
        try runValidatedModelTrial(ArchiveBackgroundWork.validateSync(contents), refreshAt: refreshAt)
    }

    static func runValidatedModelTrial(_ validated: ArchiveBackgroundWork.ValidatedContents, refreshAt: Date? = nil) throws -> ArchiveContents {
        let contents = validated.contents
        let container = try KitapVeritabani.makeContainer(inMemory: true)
        let context = ModelContext(container); context.autosaveEnabled = false
        contents.books.map(CatalogBook.init(book:)).forEach(context.insert)
        contents.copies.map { $0.makeModel() }.forEach(context.insert)
        contents.reservations.map { $0.makeModel() }.forEach(context.insert)
        contents.activeLoans.map { $0.makeActiveLoan() }.forEach(context.insert)
        contents.scanReceipts.map { $0.makeModel() }.forEach(context.insert)
        contents.mergeUndoRecords.map { $0.makeModel() }.forEach(context.insert)
        try context.save()
        if let refreshAt { _ = try SchoolLibraryService.refreshReservations(context: context, now: refreshAt, notify: false) }
        var result = contents
        result.books = try context.fetch(FetchDescriptor<CatalogBook>()).map(\.book)
        result.copies = try context.fetch(FetchDescriptor<BookCopy>()).map(ArchivedCopy.init)
        result.reservations = try context.fetch(FetchDescriptor<Reservation>()).map(ArchivedReservation.init)
        result.activeLoans = try context.fetch(FetchDescriptor<ActiveLoan>()).map(ArchivedLoan.init)
        result.scanReceipts = try context.fetch(FetchDescriptor<ScanWriteReceipt>()).map(ArchivedScanReceipt.init)
        result.mergeUndoRecords = try context.fetch(FetchDescriptor<CatalogMergeUndoRecord>()).map(ArchivedCatalogMergeUndo.init)
        guard result.books.count == contents.books.count, result.copies.count == contents.copies.count,
              result.reservations.count == contents.reservations.count, result.activeLoans.count == contents.activeLoans.count,
              result.scanReceipts.count == contents.scanReceipts.count, result.mergeUndoRecords.count == contents.mergeUndoRecords.count else {
            throw failure("İzole arşiv provasında kayıt sayıları doğrulanamadı; canlı veriler değiştirilmedi.")
        }
        return result
    }

    /// Dizi/fetch sırası veya JSON anahtar sırası aynı kapsamı farklı göstermez.
    nonisolated static func fingerprint(_ contents: ArchiveContents) throws -> String {
        var canonical = contents
        canonical.books.sort { $0.id.uuidString < $1.id.uuidString }
        canonical.loanEvents.sort { $0.id.uuidString < $1.id.uuidString }
        canonical.activeLoans.sort { $0.id.uuidString < $1.id.uuidString }
        canonical.copies.sort { $0.id.uuidString < $1.id.uuidString }
        canonical.reservations.sort { $0.id.uuidString < $1.id.uuidString }
        canonical.students.sort { $0.id.uuidString < $1.id.uuidString }
        canonical.members.sort { $0.id.uuidString < $1.id.uuidString }
        canonical.scanReceipts.sort { $0.operationID.uuidString < $1.operationID.uuidString }
        canonical.scanSessions.sort { $0.id.uuidString < $1.id.uuidString }
        canonical.graduatedStudents.sort { $0.id.uuidString < $1.id.uuidString }
        canonical.mergeUndoRecords.sort { $0.id.uuidString < $1.id.uuidString }
        func normalizedJSON(_ data: Data) throws -> Data {
            let object = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
        }
        canonical.settings = try canonical.settings.mapValues(normalizedJSON)
        // Bazı destek dosyaları JSON dışı olabilirse ham bayt kapsamı aynen korunur.
        canonical.supportingFiles = canonical.supportingFiles.mapValues { (try? normalizedJSON($0)) ?? $0 }
        return SHA256.hash(data: try FullArchive.buildVerified(canonical)).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated struct PendingEventSnapshot: Equatable, Sendable {
        var id: UUID; var data: Data; var date: Date; var replacesExisting: Bool
        @MainActor init(_ value: LibraryEventOutbox) { id = value.id; data = value.eventData; date = value.createdAt; replacesExisting = value.replacesExisting }
    }
    static func rollbackDatabase(to before: ArchiveContents, pending: [PendingEventSnapshot], context: ModelContext) throws {
        context.rollback()
        let books = Set(before.books.map(\.id)), loans = Set(before.activeLoans.map(\.id))
        let copies = Set(before.copies.map(\.id)), reservations = Set(before.reservations.map(\.id))
        let receipts = Set(before.scanReceipts.map(\.operationID)), undo = Set(before.mergeUndoRecords.map(\.id))
        for value in try context.fetch(FetchDescriptor<ActiveLoan>()) where !loans.contains(value.id) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<Reservation>()) where !reservations.contains(value.id) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<BookCopy>()) where !copies.contains(value.id) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<ScanWriteReceipt>()) where !receipts.contains(value.operationID) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<CatalogMergeUndoRecord>()) where !undo.contains(value.id) { context.delete(value) }
        for value in try context.fetch(FetchDescriptor<CatalogBook>()) where !books.contains(value.id) { context.delete(value) }
        // Önceki kimliklere ait kalıcı alanlar da aynen geri gelir. Sonraki doğrulama
        // kapısı hata vermeden önce bir kaydı değiştirmiş/silmiş olabilir.
        let currentBooks = try context.fetch(FetchDescriptor<CatalogBook>()).filter { !$0.isDeleted }
        for snapshot in before.books {
            if let model = currentBooks.first(where: { $0.id == snapshot.id }) { model.update(from: snapshot); model.addedAt = snapshot.addedAt }
            else { context.insert(CatalogBook(book: snapshot)) }
        }
        let currentLoans = try context.fetch(FetchDescriptor<ActiveLoan>()).filter { !$0.isDeleted }
        for snapshot in before.activeLoans {
            if let model = currentLoans.first(where: { $0.id == snapshot.id }) {
                model.bookID = snapshot.bookID; model.bookTitleSnapshot = snapshot.bookTitleSnapshot
                model.studentName = snapshot.studentName; model.studentClass = snapshot.studentClass
                model.loanedAt = snapshot.loanedAt; model.dueDate = snapshot.dueDate; model.extensionCount = snapshot.extensionCount
                model.studentID = snapshot.studentID; model.memberID = snapshot.memberID; model.identitySource = snapshot.identitySource
                model.studentNumberSnapshot = snapshot.studentNumberSnapshot; model.copyID = snapshot.copyID
                model.needsIdentityReview = snapshot.needsIdentityReview ?? false; model.kind = snapshot.kind ?? "library"
                model.periodSnapshot = snapshot.periodSnapshot
            } else { context.insert(snapshot.makeActiveLoan()) }
        }
        let currentCopies = try context.fetch(FetchDescriptor<BookCopy>()).filter { !$0.isDeleted }
        for snapshot in before.copies {
            if let model = currentCopies.first(where: { $0.id == snapshot.id }) {
                model.bookID = snapshot.bookID; model.accessionCode = snapshot.accessionCode
                model.condition = snapshot.condition; model.status = snapshot.status; model.note = snapshot.note
                model.addedAt = snapshot.addedAt; model.cabinet = snapshot.cabinet; model.shelf = snapshot.shelf
            } else { context.insert(snapshot.makeModel()) }
        }
        let currentReservations = try context.fetch(FetchDescriptor<Reservation>()).filter { !$0.isDeleted }
        for snapshot in before.reservations {
            if let model = currentReservations.first(where: { $0.id == snapshot.id }) {
                model.bookID = snapshot.bookID; model.bookTitleSnapshot = snapshot.bookTitleSnapshot
                model.studentName = snapshot.studentName; model.studentClass = snapshot.studentClass
                model.studentID = snapshot.studentID; model.memberID = snapshot.memberID; model.identitySource = snapshot.identitySource
                model.studentNumberSnapshot = snapshot.studentNumberSnapshot; model.copyID = snapshot.copyID
                model.expiresAt = snapshot.expiresAt; model.needsIdentityReview = snapshot.needsIdentityReview ?? false
                model.createdAt = snapshot.createdAt; model.notifiedAt = snapshot.notifiedAt
                model.isClosed = snapshot.isClosed; model.closureKind = snapshot.closureKind; model.closedAt = snapshot.closedAt
            } else { context.insert(snapshot.makeModel()) }
        }
        let currentReceipts = try context.fetch(FetchDescriptor<ScanWriteReceipt>()).filter { !$0.isDeleted }
        for snapshot in before.scanReceipts {
            if let model = currentReceipts.first(where: { $0.operationID == snapshot.operationID }) {
                model.id = snapshot.id; model.bookID = snapshot.bookID; model.addedCopies = snapshot.addedCopies
                model.inserted = snapshot.inserted; model.createdAt = snapshot.createdAt
                model.beforeBookData = snapshot.beforeBookData; model.afterBookData = snapshot.afterBookData
            } else { context.insert(snapshot.makeModel()) }
        }
        let currentUndo = try context.fetch(FetchDescriptor<CatalogMergeUndoRecord>()).filter { !$0.isDeleted }
        for snapshot in before.mergeUndoRecords {
            if let model = currentUndo.first(where: { $0.id == snapshot.id }) {
                model.payload = snapshot.payload; model.createdAt = snapshot.createdAt; model.undoneAt = snapshot.undoneAt
            } else { context.insert(snapshot.makeModel()) }
        }
        let pendingIDs = Set(pending.map(\.id))
        let currentPending = try context.fetch(FetchDescriptor<LibraryEventOutbox>())
        for model in currentPending where !pendingIDs.contains(model.id) { context.delete(model) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        for snapshot in pending {
            let model: LibraryEventOutbox
            if let existing = currentPending.first(where: { $0.id == snapshot.id }) { model = existing }
            else { model = try LibraryEventOutbox(event: decoder.decode(LoanEvent.self, from: snapshot.data)); context.insert(model) }
            model.id = snapshot.id; model.eventData = snapshot.data; model.createdAt = snapshot.date; model.replacesExisting = snapshot.replacesExisting
        }
        try context.save()
    }

    private static func backupRoot(override: URL?) throws -> URL {
        if let override { return override }
        return try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ArchiveRestoreBackups", isDirectory: true)
    }

    static func captureRawMetadata(at directory: URL) throws {
        var urls = [StudentStore.storageURL, MemberStore.storageURL, LoanHistoryStore.storageURL, GraduatedStudentStore.storageURL].compactMap { $0 }
        urls += ArchiveSettings.supportingFileNames.compactMap { ArchiveSettings.supportingURL(for: $0) }
        let sessions = ScanSessionStore.directoryOverride ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("TaramaOturumlari", isDirectory: true)
        if let sessions, FileManager.default.fileExists(atPath: sessions.path) {
            urls += try FileManager.default.contentsOfDirectory(at: sessions, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        }
        var seen = Set<String>(), index: [String: String] = [:]
        for (offset, url) in urls.enumerated() where seen.insert(url.standardizedFileURL.path).inserted {
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url), name = "\(offset)-" + url.lastPathComponent
                let target = directory.appendingPathComponent(name)
                try data.write(to: target, options: .atomic)
                guard try Data(contentsOf: target) == data else { throw CocoaError(.fileReadCorruptFile) }
                index[name] = url.standardizedFileURL.path
            }
        }
        try JSONEncoder().encode(index).write(to: directory.appendingPathComponent("dosya-dizini.json"), options: .atomic)
        try JSONEncoder().encode(ArchiveSettings.snapshot()).write(to: directory.appendingPathComponent("onceki-ayarlar.json"), options: .atomic)
    }

    static func writeStatus(_ state: String, at directory: URL, rows: [ScopeRow]) throws {
        let text = ["Arşiv geri yükleme durumu: \(state)", "İşlem öncesi tam arşiv: Islem-Oncesi-Tam-Arsiv.zip"]
            + rows.map { "\($0.title): önce \($0.before), arşiv \($0.incoming), sonra \($0.after)" }
        try Data(text.joined(separator: "\n").utf8).write(to: directory.appendingPathComponent("Kapsam-Dogrulamasi.txt"), options: .atomic)
    }
    private static func failure(_ message: String) -> SchoolLibraryService.OperationError { .init(message: message) }
}

struct ArchiveImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let preparation: ArchiveImportCoordinator.Preparation
    let onSettingsChange: (Bool) async throws -> ArchiveImportCoordinator.Preparation
    let onApply: (ArchiveImportCoordinator.Preparation) async throws -> ArchiveImportCoordinator.Receipt
    @State private var updatedPreparation: ArchiveImportCoordinator.Preparation?
    @State private var applying = false
    @State private var preparing = false
    @State private var failure: String?
    @State private var receipt: ArchiveImportCoordinator.Receipt?
    @State private var failureBackupURL: URL?
    private var preview: ArchiveImportCoordinator.Preparation { updatedPreparation ?? preparation }

    var body: some View {
        NavigationStack {
            List {
                Section("Doğrulanmış arşiv provası") {
                    Text(receipt?.summary ?? "İzole depoda kayıtlar ve ilişkiler doğrulandı. Aşağıdaki kapsamı inceleyin; canlı veriler henüz değiştirilmedi.")
                        .fixedSize(horizontal: false, vertical: true)
                    if preview.migratedLoans > 0 { Text("Eski ödünç geçişi: \(preview.migratedLoans)") }
                }
                Section("Önce / seçilen arşiv / sonra") {
                    ForEach(preview.rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.title).font(.headline)
                            Text("\(row.before) / \(row.incoming) / \(row.after) • +\(max(0, row.added)) yeni")
                                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        }.accessibilityElement(children: .combine)
                    }
                }
                Section("Korunan kapsam") {
                    Text("Mevcut kimlikler, kapaklar, öğrenciler, üyeler ve açık ödünçler korunur. Aynı kimlikli kayıtlar değiştirilmez. Silme yapılmaz.")
                    if receipt == nil {
                        Toggle("Arşivdeki güvenli ayarları da yükle", isOn: Binding(get: { preview.restoreSettings }, set: { selected in
                            guard !preparing else { return }
                            preparing = true
                            Task { @MainActor in
                                defer { preparing = false }
                                do { updatedPreparation = try await onSettingsChange(selected); failure = nil }
                                catch { failure = error.localizedDescription }
                            }
                        })).disabled(applying || preparing)
                        if preparing { ProgressView("Önizleme arka planda doğrulanıyor…") }
                    }
                    Text(preview.restoreSettings ? "Arşivdeki güvenli ayarlar mevcut tercihlere eklenecek; belirtilen tercihler değişebilir." : "Mevcut ayarlar korunacak.")
                    ForEach(Array(preview.warnings.enumerated()), id: \.offset) { _, warning in Text(warning).fixedSize(horizontal: false, vertical: true) }
                }
                if let failure {
                    Section("İşlem tamamlanmadı") {
                        Text(failure).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                        if let failureBackupURL { ShareLink(item: failureBackupURL) { Label("Korunan tam yedeği paylaş", systemImage: "square.and.arrow.up") }.frame(minHeight: 44) }
                    }
                }
                if let receipt {
                    Section("İşlem öncesi doğrulanmış tam yedek") {
                        ShareLink(item: receipt.backupURL) { Label("Tam yedeği paylaş", systemImage: "square.and.arrow.up") }.frame(minHeight: 44)
                    }
                } else {
                    Section {
                        Button {
                            applying = true; failure = nil
                            Task { @MainActor in
                                await Task.yield()
                                defer { applying = false }
                                do { receipt = try await onApply(preview) }
                                catch { failure = error.localizedDescription; failureBackupURL = (error as? ArchiveImportCoordinator.ApplyError)?.backupURL }
                            }
                        } label: {
                            Label(applying ? "Yedek ve geri yükleme doğrulanıyor…" : "Önce tam yedek al ve geri yükle", systemImage: "externaldrive.badge.checkmark")
                                .fixedSize(horizontal: false, vertical: true)
                        }.frame(minHeight: 44).disabled(applying || preparing || failure != nil).accessibilityIdentifier("archive.import.apply")
                    } footer: { Text("Önceki durumun tam ZIP yedeği yazılıp tekrar okunarak doğrulanmadan geri yükleme başlamaz.") }
                }
            }
            .navigationTitle(receipt == nil ? "Arşiv önizlemesi" : "Geri yükleme doğrulandı")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(receipt == nil ? "İptal" : "Kapat") { dismiss() }.disabled(applying) } }
            .interactiveDismissDisabled(applying)
        }
    }
}

@MainActor
extension ArchiveImportCoordinator {
    /// Eski `KitapKatalogu-Yedek.json` (yalnız kitap listesi) dosyasını tam arşiv kapılarından geçirir:
    /// JSON `ArchiveContents(books:)` içine sarılır; aynı önizleme, işlem öncesi tam yedek ve yönetici
    /// denetimi uygulanır. Böylece yedekten geri yükleme sahne arkasında toplu kayda düşmez.
    /// Sonuç, `applyAsync` ile uygulanan olağan `Preparation`dır; kimliği olan kayıtlar mevcutsa korunur.
    static func prepareAsync(jsonBackup: Data, context: ModelContext, restoreSettings: Bool = false,
                             now: Date = .now) async throws -> Preparation {
        try SchoolLibraryService.requireAdmin()
        let books = CatalogBackup.decode(jsonBackup)
        guard !books.isEmpty else {
            throw FullArchive.ValidationError(message: "Yedek dosyasından kayıt okunamadı; katalog değiştirilmedi.")
        }
        let wrapped = ArchiveContents(books: books)
        let archive = try await ArchiveBackgroundWork.buildArchive(wrapped)
        return try await prepareAsync(data: archive, context: context, restoreSettings: restoreSettings, now: now)
    }
}

extension InventoryActionStore {
    /// Arşiv birleştirmesi mevcut sayım fişlerini korur; fişler kimliğe göre birleşir.
    /// Aynı kimlik farklı içerik taşıyorsa çakışmadır ve birleştirme reddedilir.

    nonisolated static func merge(existing: Data?, incoming: Data) throws -> Data {
        var merged = try existing.map(validate) ?? []
        for receipt in try validate(incoming) {
            if let index = merged.firstIndex(where: { $0.id == receipt.id }) {
                if merged[index] == receipt { continue }
                throw FullArchive.ValidationError(message: "Aynı sayım işlem kimliği farklı kayıt içeriyor; günlük birleştirilmedi.")
            }
            merged.append(receipt)
        }
        merged.sort { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
        return try encode(merged)
    }
}
