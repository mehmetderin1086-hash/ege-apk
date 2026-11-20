import Foundation
import SwiftUI
import SwiftData
import MetricKit
import CryptoKit
import BackgroundTasks

// MARK: - Arşivden ödünç geri yükleme

/// Arşivdeki ödünç geçmişini ve etkin ödünçleri kataloğa geri koyar.
enum ArchiveLoanRestorer {
    /// - Returns: kullanıcıya gösterilecek kısa ek özet (boş olabilir)
    @discardableResult
    static func restore(_ contents: ArchiveContents, context: ModelContext) -> String {
        do { return try restoreAll(contents, context: context) }
        catch { return "Arşiv geri yüklenemedi: \(error.localizedDescription)" }
    }

    @discardableResult
    static func restoreAll(_ contents: ArchiveContents, context: ModelContext, restoreSettings: Bool = true) throws -> String {
        try SchoolLibraryService.requireAdmin()
        // Var olan kayıtlar değiştirilmez; başarısız metadata yazımında yalnız bu işlemin ekledikleri geri alınır.
        let before = try FullArchive.snapshot(context: context)
        let inventoryJournalMerged = try contents.supportingFiles[InventoryActionStore.fileName].map {
            try InventoryActionStore.merge(existing: before.supportingFiles[InventoryActionStore.fileName], incoming: $0)
        }
        let fieldJournalMerged = try contents.supportingFiles[FieldMaintenanceStore.fileName].map {
            try FieldMaintenanceStore.merge(existing: before.supportingFiles[FieldMaintenanceStore.fileName], incoming: $0)
        }
        let importJournalBefore = try StudentImportStore.allVerified()
        var importJournalMerged = importJournalBefore
        if let data = contents.supportingFiles[StudentImportStore.fileName] {
            for entry in try StudentImportStore.validate(data) {
                if let existing = importJournalBefore.first(where: { $0.id == entry.id }) {
                    guard existing == entry else { throw SchoolLibraryService.OperationError(message: "Aynı öğrenci aktarım kimliğinin farklı günlüğü var. Arşivi ayrı depoda kurtarın.") }
                } else { importJournalMerged.append(entry) }
            }
        }
        let existingBooks = Set(before.books.map(\.id))
        let existingLoans = Set(before.activeLoans.map(\.id))
        let existingCopies = Set(before.copies.map(\.id))
        let existingReservations = Set(before.reservations.map(\.id))
        let existingReceipts = Set(before.scanReceipts.map(\.operationID))
        let existingSessions = Set(before.scanSessions.map(\.id))
        let existingUndoRecords = Set(before.mergeUndoRecords.map(\.id))
        let newLoans = contents.activeLoans.filter { !existingLoans.contains($0.id) }
        let newCopies = contents.copies.filter { !existingCopies.contains($0.id) }
        let newReservations = contents.reservations.filter { !existingReservations.contains($0.id) }
        let hasNewLegacyLoans = contents.books.contains { !($0.loanedTo ?? "").isEmpty && !existingBooks.contains($0.id) }
        if !before.activeLoans.isEmpty || !before.loanEvents.isEmpty {
            guard newLoans.isEmpty, newCopies.isEmpty, newReservations.isEmpty, !hasNewLegacyLoans else {
                throw SchoolLibraryService.OperationError(message: "Canlı ödünç/geçmiş bulunan kataloğa eski arşivin operasyon durumu güvenle birleştirilemez. İşlem yapılmadı; arşivi ayrı depoda Veri Kurtarma ile açın.")
            }
        }
        let combinedLoans = before.activeLoans + newLoans
        let copyLoanIDs = combinedLoans.compactMap(\.copyID)
        guard Set(copyLoanIDs).count == copyLoanIDs.count else {
            throw SchoolLibraryService.OperationError(message: "Arşiv birleşimi aynı fiziksel nüshaya birden çok etkin ödünç bağlıyor. İşlem yapılmadı; ayrı depoda kurtarın.")
        }
        let combinedCopies = before.copies + newCopies
        let combinedBookIDs = existingBooks.union(contents.books.map(\.id))
        guard combinedLoans.allSatisfy({ loan in combinedBookIDs.contains(loan.bookID) && (loan.copyID == nil || combinedCopies.contains { $0.id == loan.copyID && $0.bookID == loan.bookID }) }),
              combinedCopies.allSatisfy({ combinedBookIDs.contains($0.bookID) }),
              (before.reservations + newReservations).allSatisfy({ combinedBookIDs.contains($0.bookID) }) else {
            throw SchoolLibraryService.OperationError(message: "Arşiv ve canlı katalog ilişkileri çakışıyor; hiçbir kayıt değiştirilmedi.")
        }
        var insertedBooks: [CatalogBook] = [], insertedLoans: [ActiveLoan] = []
        var insertedCopies: [BookCopy] = [], insertedReservations: [Reservation] = []
        var insertedReceipts: [ScanWriteReceipt] = []
        var insertedUndoRecords: [CatalogMergeUndoRecord] = []
        for book in contents.books where !existingBooks.contains(book.id) {
            let model = CatalogBook(book: book); context.insert(model); insertedBooks.append(model)
        }
        let bookIDs = existingBooks.union(contents.books.map(\.id))
        for copy in contents.copies where !existingCopies.contains(copy.id) {
            guard bookIDs.contains(copy.bookID) else { context.rollback(); throw CocoaError(.fileReadCorruptFile) }
            let model = copy.makeModel(); context.insert(model); insertedCopies.append(model)
        }
        for reservation in contents.reservations where !existingReservations.contains(reservation.id) {
            guard bookIDs.contains(reservation.bookID) else { context.rollback(); throw CocoaError(.fileReadCorruptFile) }
            let model = reservation.makeModel(); context.insert(model); insertedReservations.append(model)
        }
        for loan in contents.activeLoans where !existingLoans.contains(loan.id) {
            guard bookIDs.contains(loan.bookID) else { context.rollback(); throw CocoaError(.fileReadCorruptFile) }
            let model = loan.makeActiveLoan(); context.insert(model); insertedLoans.append(model)
        }
        for receipt in contents.scanReceipts where !existingReceipts.contains(receipt.operationID) {
            let model = receipt.makeModel(); context.insert(model); insertedReceipts.append(model)
        }
        for record in contents.mergeUndoRecords where !existingUndoRecords.contains(record.id) {
            let model = record.makeModel(); context.insert(model); insertedUndoRecords.append(model)
        }
        do { try context.save() } catch { context.rollback(); throw error }
        do {
            var students = before.students
            let studentIDs = Set(students.map(\.id))
            students.append(contentsOf: contents.students.filter { !studentIDs.contains($0.id) })
            var members = before.members
            let memberIDs = Set(members.map(\.id))
            members.append(contentsOf: contents.members.filter { !memberIDs.contains($0.id) })
            try StudentStore.replaceAllVerified(students)
            try MemberStore.replaceAllVerified(members)
            let graduateIDs = Set(before.graduatedStudents.map(\.id))
            let liveStudentIDs = Set(students.map(\.id))
            try GraduatedStudentStore.replaceAllVerified((before.graduatedStudents + contents.graduatedStudents.filter { !graduateIDs.contains($0.id) }).filter { !liveStudentIDs.contains($0.id) })
            if importJournalMerged != importJournalBefore { try StudentImportStore.replaceAllVerified(importJournalMerged) }
            let eventIDs = Set(before.loanEvents.map(\.id))
            try LoanHistoryStore.replaceAll(before.loanEvents + contents.loanEvents.filter { !eventIDs.contains($0.id) })
            for session in contents.scanSessions where !existingSessions.contains(session.id) { try ScanSessionStore.save(session, updateTimestamp: false) }
            if restoreSettings {
                try ArchiveSettings.restore(contents.settings)
                for (name, data) in contents.supportingFiles where ArchiveSettings.supportingFileNames.contains(name) && name != "Mezunlar.json" && name != StudentImportStore.fileName {
                    guard let url = ArchiveSettings.supportingURL(for: name) else { throw CocoaError(.fileNoSuchFile) }
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try (name == FieldMaintenanceStore.fileName ? fieldJournalMerged ?? data : name == InventoryActionStore.fileName ? inventoryJournalMerged ?? data : data).write(to: url, options: .atomic)
                }
            }
        } catch {
            insertedLoans.forEach(context.delete); insertedReservations.forEach(context.delete)
            insertedCopies.forEach(context.delete); insertedBooks.forEach(context.delete); insertedReceipts.forEach(context.delete)
            insertedUndoRecords.forEach(context.delete)
            for session in contents.scanSessions where !existingSessions.contains(session.id) { try? ScanSessionStore.remove(session.id) }
            try? context.save()
            try? StudentStore.replaceAllVerified(before.students); try? MemberStore.replaceAllVerified(before.members)
            try? GraduatedStudentStore.replaceAllVerified(before.graduatedStudents)
            if importJournalMerged != importJournalBefore { try? StudentImportStore.replaceAllVerified(importJournalBefore) }
            try? LoanHistoryStore.replaceAll(before.loanEvents)
            if restoreSettings {
                for key in ArchiveSettings.allowedKeys { UserDefaults.standard.removeObject(forKey: key) }
                try? ArchiveSettings.restore(before.settings)
                for name in contents.supportingFiles.keys where ArchiveSettings.supportingFileNames.contains(name) {
                    guard let url = ArchiveSettings.supportingURL(for: name) else { continue }
                    if let data = before.supportingFiles[name] { try? data.write(to: url, options: .atomic) }
                    else { try? FileManager.default.removeItem(at: url) }
                }
            }
            throw error
        }
        return "\(insertedBooks.count) eser, \(insertedCopies.count) nüsha, \(insertedLoans.count) ödünç, \(insertedReservations.count) rezervasyon geri yüklendi."
    }

    /// Kurtarma seçilen arşivin metadata'sını aynen kurar. Bozuk eski JSON da ham
    /// baytlarıyla saklanır; yazma başarısızlığında aynı baytlar geri getirilir.
    @discardableResult
    static func restoreRecoveryMetadata(_ contents: ArchiveContents) throws -> URL {
        try SchoolLibraryService.requireAdmin()
        struct RawFile { var url: URL; var data: Data? }
        var urls = [StudentStore.storageURL, MemberStore.storageURL, LoanHistoryStore.storageURL, GraduatedStudentStore.storageURL].compactMap { $0 }
        urls += ArchiveSettings.supportingFileNames.sorted().compactMap { ArchiveSettings.supportingURL(for: $0) }
        let sessionDirectory = ScanSessionStore.directoryOverride ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("TaramaOturumlari", isDirectory: true)
        if let directory = sessionDirectory {
            if FileManager.default.fileExists(atPath: directory.path) {
                urls += try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
            }
            urls += contents.scanSessions.map { directory.appendingPathComponent($0.id.uuidString + ".json") }
        }
        var unique = Set<URL>()
        let snapshots = try urls.filter { unique.insert($0.standardizedFileURL).inserted }.map { url in
            RawFile(url: url, data: FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil)
        }
        let preferences = ArchiveSettings.snapshot()
        let root = try ArchiveSwitchJournal.recoveredStoreRoot()
            .appendingPathComponent("metadata-backup-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var index: [String: String] = [:]
        for (offset, snapshot) in snapshots.enumerated() {
            let name = "\(offset)-" + snapshot.url.lastPathComponent
            if let data = snapshot.data { try data.write(to: root.appendingPathComponent(name), options: .atomic); index[name] = snapshot.url.path }
        }
        try JSONEncoder().encode(index).write(to: root.appendingPathComponent("dosya-dizini.json"), options: .atomic)
        try JSONEncoder().encode(preferences).write(to: root.appendingPathComponent("onceki-ayarlar.json"), options: .atomic)
        do {
            try StudentStore.replaceAllVerified(contents.students)
            try MemberStore.replaceAllVerified(contents.members)
            try LoanHistoryStore.replaceAll(contents.loanEvents)
            for name in ArchiveSettings.supportingFileNames {
                guard let url = ArchiveSettings.supportingURL(for: name) else { throw CocoaError(.fileNoSuchFile) }
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let data = contents.supportingFiles[name] { try data.write(to: url, options: .atomic) }
                else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
            try GraduatedStudentStore.replaceAllVerified(contents.graduatedStudents)
            if let directory = sessionDirectory, FileManager.default.fileExists(atPath: directory.path) {
                for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
                    try FileManager.default.removeItem(at: url)
                }
            }
            for session in contents.scanSessions { try ScanSessionStore.save(session, updateTimestamp: false) }
            for key in ArchiveSettings.allowedKeys { UserDefaults.standard.removeObject(forKey: key) }
            try ArchiveSettings.restore(contents.settings)
        } catch {
            let original = error
            var rollbackFailed = false
            for snapshot in snapshots {
                do {
                    if let data = snapshot.data { try data.write(to: snapshot.url, options: .atomic) }
                    else if FileManager.default.fileExists(atPath: snapshot.url.path) { try FileManager.default.removeItem(at: snapshot.url) }
                } catch { rollbackFailed = true }
            }
            LoanHistoryStore.invalidate(); StudentStore.invalidateCaches(); MemberStore.invalidateCaches()
            for key in ArchiveSettings.allowedKeys { UserDefaults.standard.removeObject(forKey: key) }
            do { try ArchiveSettings.restore(preferences) } catch { rollbackFailed = true }
            if rollbackFailed {
                throw SchoolLibraryService.OperationError(message: "Kurtarma yazımı ve eski metadata geri alma işlemi tamamlanamadı. Ham dosyalar ayrı metadata-backup klasöründe korunuyor.")
            }
            throw original
        }
        return root
    }

    /// Yeni dosyada doğrulanmış kap hazırlar; mevcut kap ve JSON dosyaları değiştirilmez.
    static func buildRecoveryStore(contents: ArchiveContents, at url: URL) throws -> ModelContainer {
        try SchoolLibraryService.requireAdmin()
        guard !FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileWriteFileExists) }
        let container = try KitapVeritabani.makeContainer(url: url)
        let context = ModelContext(container)
        let bookIDs = Set(contents.books.map(\.id))
        let loanedCopyIDs = contents.activeLoans.compactMap(\.copyID)
        guard bookIDs.count == contents.books.count,
              Set(loanedCopyIDs).count == loanedCopyIDs.count,
              contents.activeLoans.allSatisfy({ $0.studentID == nil || $0.memberID == nil }),
              contents.activeLoans.allSatisfy({ bookIDs.contains($0.bookID) }),
              contents.copies.allSatisfy({ bookIDs.contains($0.bookID) }),
              contents.reservations.allSatisfy({ bookIDs.contains($0.bookID) }) else { throw CocoaError(.fileReadCorruptFile) }
        contents.books.map(CatalogBook.init(book:)).forEach(context.insert)
        contents.copies.map { $0.makeModel() }.forEach(context.insert)
        contents.reservations.map { $0.makeModel() }.forEach(context.insert)
        contents.activeLoans.map { $0.makeActiveLoan() }.forEach(context.insert)
        contents.scanReceipts.map { $0.makeModel() }.forEach(context.insert)
        contents.mergeUndoRecords.map { $0.makeModel() }.forEach(context.insert)
        do { try context.save() } catch { context.rollback(); throw error }
        guard try context.fetchCount(FetchDescriptor<CatalogBook>()) == contents.books.count,
              try context.fetchCount(FetchDescriptor<BookCopy>()) == contents.copies.count,
              try context.fetchCount(FetchDescriptor<Reservation>()) == contents.reservations.count,
              try context.fetchCount(FetchDescriptor<ActiveLoan>()) == contents.activeLoans.count,
              try context.fetchCount(FetchDescriptor<ScanWriteReceipt>()) == contents.scanReceipts.count,
              try context.fetchCount(FetchDescriptor<CatalogMergeUndoRecord>()) == contents.mergeUndoRecords.count else { throw CocoaError(.fileReadCorruptFile) }
        return container
    }

}

// MARK: - Çöp kutusu

/// Silinen kitap (kapaklarıyla) — 30 gün boyunca geri alınabilir.
nonisolated struct TrashEntry: Codable, Identifiable {
    var book: Book
    var deletedAt: Date
    var reason: String
    /// Silinen kitaba ait tarama makbuzları (geri alma kanıtı). Eski çöp dosyalarında yoktur; boş okunur.
    var receipts: [ArchivedScanReceipt] = []

    var id: UUID { book.id }

    func daysLeft(now: Date = .now) -> Int {
        let elapsed = now.timeIntervalSince(deletedAt) / 86_400
        return max(0, TrashStore.retentionDays - Int(elapsed))
    }
}

/// Özel çözücü uzantıda durur ki bellek-sıralı başlatıcı korunsun. `receipts` anahtarı olmayan
/// eski çöp dosyaları sorunsuz okunur.
nonisolated extension TrashEntry {
    private enum CodingKeys: String, CodingKey { case book, deletedAt, reason, receipts }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        book = try container.decode(Book.self, forKey: .book)
        deletedAt = try container.decode(Date.self, forKey: .deletedAt)
        reason = try container.decode(String.self, forKey: .reason)
        receipts = try container.decodeIfPresent([ArchivedScanReceipt].self, forKey: .receipts) ?? []
    }
}

/// Çöp kutusu: her silinen kitap Uygulama Desteği/CopKutusu/<id>.json olarak saklanır.
/// Tek dosya yerine kitap başına dosya: kapaklı binlerce kaydı her silmede yeniden yazmamak için.
enum TrashStore {
    nonisolated static let retentionDays = 30
    /// Testler geçici klasör verir
    static var directoryOverride: URL?

    static var directory: URL? {
        if let directoryOverride { return directoryOverride }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("CopKutusu", isDirectory: true)
    }

    static func add(_ books: [CatalogBook], reason: String = "Silindi") {
        add(books.map(\.book), reason: reason)
    }

    static func add(_ books: [Book], reason: String = "Silindi", now: Date = .now) {
        guard let directory, !books.isEmpty else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        for book in books {
            let entry = TrashEntry(book: book, deletedAt: now, reason: reason)
            guard let data = try? encoder.encode(entry) else { continue }
            try? data.write(to: fileURL(for: book.id, in: directory), options: .atomic)
        }
        AppLog.write("Çöp kutusuna \(books.count) kitap taşındı (\(reason))")
    }

    /// Çöp yazımı doğrulanmadan kalıcı katalog satırı silinmez; ilişkili eser düşülmelidir.
    static func moveVerified(_ books: [CatalogBook], context: ModelContext, reason: String = "Silindi") throws {
        try SchoolLibraryService.requireAdmin()
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        let live = books.filter { !$0.isDeleted && $0.modelContext != nil }
        let ids = Set(live.map(\.id))
        guard ids.count == live.count else { throw SchoolLibraryService.OperationError(message: "Silinecek kayıt listesinde tekrarlanan kimlik var.") }
        let loans = try context.fetch(FetchDescriptor<ActiveLoan>())
        let copies = try context.fetch(FetchDescriptor<BookCopy>())
        let reservations = try context.fetch(FetchDescriptor<Reservation>())
        let history = try SchoolLibraryService.historySnapshot(context: context)
        guard !loans.contains(where: { ids.contains($0.bookID) }), !copies.contains(where: { ids.contains($0.bookID) }),
              !reservations.contains(where: { ids.contains($0.bookID) }), !history.contains(where: { ids.contains($0.bookID) }),
              live.allSatisfy({ ($0.loanedTo ?? "").isEmpty }) else {
            throw SchoolLibraryService.OperationError(message: "Ödünç, nüsha, rezervasyon veya geçmişi bulunan eser silinemez. İlişkileri korumak için koleksiyondan düşürün.")
        }
        let receipts = try context.fetch(FetchDescriptor<ScanWriteReceipt>()).filter { ids.contains($0.bookID) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let encoded = try live.map { book in
            let own = receipts.filter { $0.bookID == book.id }.map(ArchivedScanReceipt.init)
            return (fileURL(for: book.id, in: directory), try encoder.encode(TrashEntry(book: book.book, deletedAt: .now, reason: reason, receipts: own)))
        }
        let previous: [(URL, Data?)] = try encoded.map { url, _ in (url, FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil) }
        // Önceden bekleyen başka ekran değişiklikleri işlem rollback'ine karışmaz.
        try context.save()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            for (url, data) in encoded { try data.write(to: url, options: .atomic) }
            live.forEach(context.delete); receipts.forEach(context.delete)
            try context.save()
        } catch {
            context.rollback()
            var rollbackFailed = false
            for (url, data) in previous {
                do {
                    if let data { try data.write(to: url, options: .atomic) }
                    else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                } catch { rollbackFailed = true }
            }
            if rollbackFailed { throw SchoolLibraryService.OperationError(message: "Silme tamamlanmadı; çöp kayıtlarını geri alma yazımı da başarısız. Katalog satırları korunuyor.") }
            throw error
        }
        AppLog.write("Çöp kutusuna doğrulanarak taşındı: \(live.count) eser")
    }

    /// Süresi dolanları temizleyip kalanları en yeni önce döndürür.
    static func entries(now: Date = .now) -> [TrashEntry] {
        purgeExpired(now: now)
        return loadAll().sorted { $0.deletedAt > $1.deletedAt }
    }

    static var count: Int {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return 0 }
        return files.filter { $0.hasSuffix(".json") }.count
    }

    static func remove(id: UUID) {
        guard YetkiDurumu.shared.yonetici else { return }
        guard let directory else { return }
        try? FileManager.default.removeItem(at: fileURL(for: id, in: directory))
    }

    static func empty() {
        guard YetkiDurumu.shared.yonetici else { return }
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    static func purgeExpired(now: Date = .now) {
        guard let directory else { return }
        for entry in loadAll() where entry.daysLeft(now: now) == 0 {
            try? FileManager.default.removeItem(at: fileURL(for: entry.id, in: directory))
        }
    }

    /// Kitabı kataloğa geri koyar (aynı kimlikli kayıt zaten varsa yalnızca çöpten siler).
    @discardableResult
    static func restore(_ entry: TrashEntry, context: ModelContext) -> Bool {
        guard YetkiDurumu.shared.yonetici else { return false }
        let id = entry.book.id
        let existing = (try? context.fetch(FetchDescriptor<CatalogBook>(predicate: #Predicate { $0.id == id }))) ?? []
        if existing.isEmpty {
            context.insert(CatalogBook(book: entry.book))
            // Silme sırasında düşen tarama makbuzları da aynı işlemle geri gelir (kaydı geri almak için kanıt).
            let knownOperations = Set(((try? context.fetch(FetchDescriptor<ScanWriteReceipt>())) ?? []).map(\.operationID))
            for receipt in entry.receipts where !knownOperations.contains(receipt.operationID) {
                context.insert(receipt.makeModel())
            }
            do { try context.save() } catch { context.rollback(); AppLog.write("Çöp kutusundan geri alma kaydedilemedi"); return false }
        }
        remove(id: id)
        AppLog.write("Çöp kutusundan geri alındı: \(entry.book.title)")
        return existing.isEmpty
    }

    private static func loadAll() -> [TrashEntry] {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(TrashEntry.self, from: Data(contentsOf: $0)) }
    }

    private static func fileURL(for id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}

struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var entries: [TrashEntry] = []
    @State private var isConfirmingEmpty = false
    @State private var deleteCandidate: TrashEntry?
    @State private var message: String?

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Çöp kutusu boş",
                    systemImage: "trash.slash",
                    description: Text("Silinen kitaplar \(TrashStore.retentionDays) gün burada tutulur.")
                )
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.book.title).font(.headline)
                    if !entry.book.author.isEmpty {
                        Text(entry.book.author).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("\(entry.reason) · \(entry.deletedAt.formatted(date: .abbreviated, time: .shortened)) · \(entry.daysLeft()) gün kaldı"
                         + (entry.receipts.isEmpty ? "" : " · \(entry.receipts.count) makbuz"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .swipeActions(edge: .leading) {
                    Button {
                        restore(entry)
                    } label: {
                        Label("Geri Al", systemImage: "arrow.uturn.backward")
                    }
                    .tint(.green)
                }
                // Kalıcı silme geri alınamaz: tam kaydırma tek başına silmez, onay sorulur
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        deleteCandidate = entry
                    } label: {
                        Label("Kalıcı Sil", systemImage: "trash")
                    }
                    .tint(.red)
                }
                .contextMenu {
                    Button("Geri Al", systemImage: "arrow.uturn.backward") { restore(entry) }
                    Button("Kalıcı Sil", systemImage: "trash", role: .destructive) { deleteCandidate = entry }
                }
            }
        }
        .navigationTitle("Çöp Kutusu")
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Tümünü Geri Al", systemImage: "arrow.uturn.backward.circle") {
                            let toplam = entries.count
                            let geriAlinan = entries.filter { TrashStore.restore($0, context: modelContext) }.count
                            reload()
                            let kalan = entries.count
                            message = "\(geriAlinan) kitap geri alındı."
                                + (toplam - geriAlinan - kalan > 0 ? " \(toplam - geriAlinan - kalan) kitap zaten katalogdaydı." : "")
                                + (kalan > 0 ? " \(kalan) kitap geri alınamadı (yönetici yetkisi ya da kayıt hatası); çöp kutusunda duruyor." : "")
                        }
                        Button("Çöp Kutusunu Boşalt", systemImage: "trash", role: .destructive) {
                            isConfirmingEmpty = true
                        }
                    } label: {
                        Label("İşlemler", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog("Çöp kutusundaki \(entries.count) kitap kalıcı olarak silinsin mi?",
                            isPresented: $isConfirmingEmpty, titleVisibility: .visible) {
            Button("Kalıcı Olarak Sil", role: .destructive) {
                TrashStore.empty()
                reload()
            }
            Button("Vazgeç", role: .cancel) { }
        }
        .confirmationDialog("“\(deleteCandidate?.book.title ?? "")” kalıcı olarak silinsin mi? Bu işlem geri alınamaz.",
                            isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }), titleVisibility: .visible) {
            Button("Kalıcı Olarak Sil", role: .destructive) {
                if let entry = deleteCandidate { TrashStore.remove(id: entry.id); reload() }
                deleteCandidate = nil
            }
            Button("Vazgeç", role: .cancel) { deleteCandidate = nil }
        }
        .alert("Çöp Kutusu", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("Tamam", role: .cancel) { }
        } message: {
            Text(message ?? "")
        }
        .onAppear(perform: reload)
    }

    private func restore(_ entry: TrashEntry) {
        let restored = TrashStore.restore(entry, context: modelContext)
        reload()
        // Geri alınamayan kayıt çöp kutusunda kalır; "zaten katalogda" denmez
        if restored { message = "“\(entry.book.title)” kataloğa geri alındı." }
        else if entries.contains(where: { $0.id == entry.id }) { message = "“\(entry.book.title)” geri alınamadı (yönetici yetkisi ya da kayıt hatası). Kitap çöp kutusunda duruyor." }
        else { message = "Bu kitap zaten katalogda." }
    }

    private func reload() {
        entries = TrashStore.entries()
    }
}

// MARK: - Otomatik günlük tam arşiv

/// iCloud eşitlemesi yerine: günde bir kez kapaklar ve ödünçler dahil tam ZIP arşivi
/// Belgeler/Arsivler klasörüne yazılır. Eski dosyalar saklama önizlemesinden temizlenir. Dosyalar uygulamasından
/// iCloud Drive'a elle kopyalanabilir; cihaz iCloud yedeği de bu klasörü kapsar.
enum AutoArchive {
    /// Günlük arşiv çalışmasının sonucu. Kabuk (arka plan görevi, `.background` geçişi)
    /// bunu `setTaskCompleted` ve günlük için kullanır.
    nonisolated enum Outcome: Equatable, Sendable {
        case yazildi
        case atlandiCalisiyor
        case basarisiz(String)
        case iptal
    }

    /// Info.plist `BGTaskSchedulerPermittedIdentifiers` ile birebir aynı olmalıdır.
    nonisolated static let backgroundTaskIdentifier = "com.mehmetderin.kitapbul.gunluk-arsiv"
    /// Eski arşivleri günlük arşivden sonra kendiliğinden uygulama tercihi (varsayılan kapalı).
    nonisolated static let autoApplyRetentionKey = "autoArchiveApplyRetention"
    /// Bundan eski `yaziliyor-*.tmp` dosyaları yarım kalmış yazım sayılır.
    nonisolated static let staleTemporaryAge: TimeInterval = 600
    private static let lastDateKey = "autoArchiveLastDate"
    private static let lastAttemptKey = "autoArchiveLastAttempt"
    private static let lastFailureKey = "autoArchiveLastFailure"
    private static var isRunning = false
    private static var backgroundTaskRegistered = false
    static var lastAttemptDate: Date? { UserDefaults.standard.object(forKey: lastAttemptKey) as? Date }
    static var lastFailure: String? { UserDefaults.standard.string(forKey: lastFailureKey) }
    static var directoryOverride: URL?
    /// Yazım sürerken (günlük çalışma ya da elle dışa aktarma) geçici dosyalar süpürülmez.
    static var activeTemporaries = Set<URL>()
    /// Yazım sürüyor mu? Tanılama "zaten yazılıyor" iletisi ve süpürücü için.
    static var isWriting: Bool { isRunning || !activeTemporaries.isEmpty }
    /// Testler boş disk kapasitesini buradan enjekte eder. nil ise gerçek disk okunur; ancak
    /// `directoryOverride` (test klasörü) varken ve kapasite enjekte edilmemişken bütçe denetimi
    /// atlanır, böylece testler makinenin disk doluluğuna bağlı kalmaz.
    static var availableCapacityProvider: ((URL) -> Int64?)?
    /// Testler akış kancalarını (örn. yazma hatası) buradan verir.
    static var testHooks: StreamingHooks?

    static var directory: URL? {
        if let directoryOverride { return directoryOverride }
        return FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Arsivler", isDirectory: true)
    }

    static var lastArchiveDate: Date? {
        UserDefaults.standard.object(forKey: lastDateKey) as? Date
    }

    static func isDue(now: Date = .now, last: Date? = lastArchiveDate) -> Bool {
        guard let last else { return true }
        return !Calendar.current.isDate(last, inSameDayAs: now)
    }

    static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "KitapArsivi-\(formatter.string(from: date)).zip"
    }

    static func existingArchives() -> [URL] {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        // Ad tarih içerdiğinden alfabetik sıra = kronolojik sıra
        return files.filter { $0.pathExtension == "zip" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    // MARK: Yarım kalan geçici dosyalar

    private struct StaleFile { let url: URL; let bytes: Int64 }

    /// Süpürülecek klasörler: arşiv klasöründe `yaziliyor-*.tmp`, geçiş günlüğü klasöründe `.switch-journal-*.tmp`.
    private static func sweepTargets() -> [(directory: URL, prefix: String)] {
        var result: [(URL, String)] = []
        if let directory { result.append((directory, "yaziliyor-")) }
        if let journal = ArchiveSwitchJournal.journalDirectory() { result.append((journal, ".switch-journal-")) }
        return result
    }

    private static func staleFiles(olderThan age: TimeInterval, now: Date) -> [StaleFile] {
        let active = Set(activeTemporaries.map { $0.standardizedFileURL.path })
        var result: [StaleFile] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        for (directory, prefix) in sweepTargets() {
            guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { continue }
            for url in urls {
                let name = url.lastPathComponent
                guard name.hasPrefix(prefix), name.hasSuffix(".tmp"),
                      !active.contains(url.standardizedFileURL.path),
                      let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true, values.isSymbolicLink != true,
                      let modified = values.contentModificationDate,
                      now.timeIntervalSince(modified) > age else { continue }
                result.append(StaleFile(url: url, bytes: Int64(values.fileSize ?? 0)))
            }
        }
        return result
    }

    /// Yarım kalmış yazımların artık dosyaları. Yazım sürerken (`isWriting`) hiçbir şeye dokunmaz.
    static func staleTemporaryCount(olderThan age: TimeInterval = staleTemporaryAge, now: Date = .now) -> (count: Int, bytes: Int64) {
        guard !isWriting else { return (0, 0) }
        let files = staleFiles(olderThan: age, now: now)
        return (files.count, files.reduce(0) { $0 + $1.bytes })
    }

    /// `age` saniyeden eski yarım geçici dosyaları siler; silinenlerin adreslerini döndürür.
    /// Canlı bir yazımın dosyası asla silinmez: `isWriting` iken hiçbir şey yapılmaz.
    @discardableResult
    static func sweepStaleTemporaries(olderThan age: TimeInterval = staleTemporaryAge, now: Date = .now) -> [URL] {
        guard !isWriting else { return [] }
        var removed: [URL] = [], bytes: Int64 = 0
        for file in staleFiles(olderThan: age, now: now) {
            do { try FileManager.default.removeItem(at: file.url); removed.append(file.url); bytes += file.bytes }
            catch { AppLog.write("Yarım kalan geçici dosya silinemedi") }
        }
        if !removed.isEmpty {
            AppLog.write("Yarım kalan \(removed.count) artık dosya silindi (\(String(format: "%.1f", Double(bytes) / 1_048_576)) MB)")
        }
        return removed
    }

    // MARK: Disk bütçesi

    nonisolated static func requiredCapacity(lastArchiveBytes: Int64) -> Int64 {
        lastArchiveBytes * 3 + 300 * 1_048_576
    }

    private nonisolated static func systemAvailableCapacity(_ url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }

    /// Yeni arşiv için yer yoksa kullanıcıya gösterilecek ileti; yeterliyse ya da bilinmiyorsa nil.
    static func diskShortfall(directory: URL) -> String? {
        let provider: (URL) -> Int64?
        if let availableCapacityProvider { provider = availableCapacityProvider }
        else if directoryOverride != nil { return nil }
        else { provider = { systemAvailableCapacity($0) } }
        let probe = FileManager.default.fileExists(atPath: directory.path) ? directory : directory.deletingLastPathComponent()
        guard let available = provider(probe) else { return nil }
        let lastBytes = existingArchives().first
            .flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.map(Int64.init) ?? 0
        let required = requiredCapacity(lastArchiveBytes: lastBytes)
        guard available < required else { return nil }
        let free = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
        let need = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
        return "Disk alanı yetersiz: \(free) boş, günlük arşiv için en az \(need) gerekir."
    }

    // MARK: Çalıştırma

    /// Günlük arşiv zamanı geldiyse arka planda yazar.
    static func runIfDue(context: ModelContext, requireCurrent: (@MainActor () throws -> Void)? = nil) async {
        do { try Task.checkCancellation(); try requireCurrent?() } catch { return }
        guard isDue() else { return }
        await run(context: context, requireCurrent: requireCurrent)
    }

    /// Kabuk girişi: açık kataloğu (yoksa güvenli kapıdan açarak) bugünün arşiviyle günceller.
    /// Bugünün arşivi zaten yazılmışsa iş yapmadan `.yazildi` döner. `cancellable: true` iken çağıran
    /// Task iptal edilirse (arka plan görevi süresi dolarsa) yazım durur ve geçici dosya silinir;
    /// `false` iken çağıranın iptali yazımı kesmez.
    static func run(cancellable: Bool) async -> Outcome {
        let work = Task { await runCurrentCatalog() }
        guard cancellable else { return await work.value }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    private static func runCurrentCatalog() async -> Outcome {
        guard !isDue() else { return await runCurrentCatalogForced() }
        return .yazildi
    }

    private static func runCurrentCatalogForced() async -> Outcome {
        do { try Task.checkCancellation() } catch { return .iptal }
        let container: ModelContainer
        if let shared = KitapVeritabani.shared { container = shared }
        else {
            // Arka plan görevi yarım geçiş kurtarmasını kendisi yürütmez; uygulama açılınca doğrulamalı çalışır.
            guard !ArchiveSwitchJournal.hasMarker() else {
                return .basarisiz("Katalog güvenli açılış bekliyor; Kitap Bul'u açın.")
            }
            do { container = try StoreRecovery.openVerifiedContainer(sync: true) }
            catch { return .basarisiz(error.localizedDescription) }
            KitapVeritabani.shared = container
        }
        let context = container.mainContext
        let lease: ActiveCatalogLease
        do { lease = try ActiveCatalogLease.captureCurrent(context: context) }
        catch { return .basarisiz(error.localizedDescription) }
        let check: @MainActor () throws -> Void = { try lease.requireCurrent(context: context) }
        return await run(context: context, requireCurrent: check)
    }

    /// Arşivi AKIŞLA yazar: kitaplar 100'erli sayfalar hâlinde okunur, kapaklar doğrudan dosyaya
    /// yazılır. Önceden bütün katalog kapaklarıyla belleğe alınıyordu; binlerce kapakta iOS
    /// uygulamayı bellek yüzünden kapatabiliyordu (açılışta "çökme").
    @discardableResult
    static func run(context: ModelContext, now: Date = .now,
                    requireCurrent: (@MainActor () throws -> Void)? = nil) async -> Outcome {
        do { try Task.checkCancellation(); try requireCurrent?() } catch { return .iptal }
        guard let directory else { return .basarisiz("Arşiv klasörü bulunamadı.") }
        guard !isWriting else { return .atlandiCalisiyor }
        let defaults = UserDefaults.standard
        defaults.set(now, forKey: lastAttemptKey)
        // Önceki çalışmadan kalan yarım dosyalar önce temizlenir ve görünür kılınır.
        let swept = sweepStaleTemporaries()
        isRunning = true
        defer { isRunning = false }
        if !swept.isEmpty {
            defaults.set("Önceki arşiv yazımı yarım kalmış; \(swept.count) artık dosya temizlendi.", forKey: lastFailureKey)
        }
        let toplam: Int
        do { toplam = try context.fetchCount(FetchDescriptor<CatalogBook>()) }
        catch {
            defaults.set(error.localizedDescription, forKey: lastFailureKey)
            AppLog.write("Günlük arşiv için katalog okunamadı")
            return .basarisiz(error.localizedDescription)
        }
        guard toplam > 0 else { return .basarisiz("Katalog boş; arşiv yazılmadı.") }
        if let shortfall = diskShortfall(directory: directory) {
            defaults.set(shortfall, forKey: lastFailureKey)
            AppLog.write("Günlük arşiv atlandı: disk alanı yetersiz")
            return .basarisiz(shortfall)
        }
        let target = directory.appendingPathComponent(fileName(for: now))
        let temp = directory.appendingPathComponent("yaziliyor-\(UUID().uuidString).tmp")
        do {
            try await writeStreaming(context: context, expectedCount: toplam, target: target, temporary: temp,
                                     hooks: testHooks ?? StreamingHooks())
        } catch {
            // Yazıcı kendi geçici dosyasını siler; yine de yayımlanmamış hiçbir artık bırakma.
            try? FileManager.default.removeItem(at: temp)
            if error is CancellationError || Task.isCancelled { return .iptal }
            do { try requireCurrent?() } catch { return .iptal }
            defaults.set(error.localizedDescription, forKey: lastFailureKey)
            AppLog.write("Günlük arşiv YAZILAMADI")
            return .basarisiz(error.localizedDescription)
        }
        // Yayım tamamlandı: sonradan iptal gelse de bugünün arşivi diskte tamdır.
        defaults.set(now, forKey: lastDateKey)
        defaults.removeObject(forKey: lastFailureKey)
        AppLog.write("Günlük arşiv yazıldı: \(toplam) kitap")
        applyAutomaticRetention(in: directory)
        return .yazildi
    }

    /// Eski yedeklerin silinmesi varsayılan olarak ayrı, dosya adları görünen onaylı bir işlemdir.
    /// Yönetici 'otomatik uygula' tercihini açtıysa yalnız saklama planının dışında kalanlar silinir.
    private static func applyAutomaticRetention(in directory: URL) {
        guard UserDefaults.standard.bool(forKey: autoApplyRetentionKey) else { return }
        let raw = UserDefaults.standard.string(forKey: ArchiveRetention.preferenceKey) ?? ""
        let policy = ArchiveRetentionPolicy(rawValue: raw) ?? .short
        do {
            let removed = try ArchiveRetention.applyAutomatically(in: directory, policy: policy)
            if !removed.isEmpty {
                AppLog.write("Saklama tercihi gereği \(removed.count) eski arşiv silindi: " + removed.map(\.lastPathComponent).joined(separator: ", "))
            }
        } catch { AppLog.write("Eski arşivlere saklama tercihi uygulanamadı") }
    }
}

// MARK: - Arka plan işleme görevi

/// BGTaskScheduler kaydı. Kayıt uygulama açılışı bitmeden yapılmalıdır; bu yüzden
/// `registerBackgroundTask()` `MyApp.init()` içinden (görünüm `.task`'ından değil) çağrılır.
extension AutoArchive {
    /// Çağrılan taşıyıcı: BGTask Sendable değildir; yalnız ana aktöre atlayan Task içinde kullanılır.
    private nonisolated final class TaskBox: @unchecked Sendable {
        let task: BGTask
        init(_ task: BGTask) { self.task = task }
    }

    /// Tekrar çağrılması güvenlidir. Kayıttan sonra ilk isteği de gönderir.
    static func registerBackgroundTask() {
        guard !backgroundTaskRegistered else { return }
        backgroundTaskRegistered = true
        // İşleyici BGTaskScheduler'ın arka plan kuyruğunda çalışır; ana aktöre bağlı bir kapanış
        // burada çalışma zamanı denetimiyle çökerdi. Bu yüzden kapanış açıkça Sendable'dır.
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { @Sendable task in
            let box = TaskBox(task)
            let work = Task { @MainActor in
                let outcome = await run(cancellable: true)
                scheduleBackgroundTask()
                switch outcome {
                case .yazildi, .atlandiCalisiyor: box.task.setTaskCompleted(success: true)
                case .basarisiz, .iptal: box.task.setTaskCompleted(success: false)
                }
            }
            task.expirationHandler = { work.cancel() }
        }
        if registered { scheduleBackgroundTask() }
        else { AppLog.write("Günlük arşiv arka plan görevi kaydedilemedi") }
    }

    /// Bir sonraki takvim gününün erken saatine istek bırakır; sistem uygun anı seçer.
    static func scheduleBackgroundTask(now: Date = .now) {
        let request = BGProcessingTaskRequest(identifier: backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))
        request.earliestBeginDate = tomorrow.map { $0.addingTimeInterval(3_600) }
        Task {
            do { try await BGTaskScheduler.shared.submitTaskRequest(request) }
            catch { AppLog.write("Günlük arşiv arka plan isteği gönderilemedi") }
        }
    }
}

// MARK: - Açılışta bütünlük denetimi

struct IntegrityReport: Equatable {
    var bookCount = 0
    /// Kataloğu silinmiş kitaplara ait etkin ödünçler (kitap öğrencide olabilir; silinmez, raporlanır)
    var orphanLoanTitles: [String] = []
    /// 1'den küçük adetler 1'e düzeltildi
    var fixedQuantities = 0
    /// Nüsha sayısından fazla ödünçte görünen kitaplar
    var overLoanedTitles: [String] = []
    /// Aynı ISBN'e sahip kayıt grupları
    var duplicateISBNGroups = 0
    var checkedAt = Date.now

    var isClean: Bool {
        orphanLoanTitles.isEmpty && overLoanedTitles.isEmpty && duplicateISBNGroups == 0
    }

    var summary: String {
        var lines: [String] = ["\(bookCount) kitap denetlendi."]
        if fixedQuantities > 0 { lines.append("\(fixedQuantities) kitabın geçersiz adedi 1 yapıldı.") }
        if !orphanLoanTitles.isEmpty { lines.append("\(orphanLoanTitles.count) ödünç, katalogda olmayan kitaba ait.") }
        if !overLoanedTitles.isEmpty { lines.append("\(overLoanedTitles.count) kitap nüsha sayısından fazla ödünçte.") }
        if duplicateISBNGroups > 0 { lines.append("\(duplicateISBNGroups) ISBN birden çok kayıtta geçiyor.") }
        if isClean && fixedQuantities == 0 { lines.append("Sorun bulunmadı.") }
        return lines.joined(separator: "\n")
    }
}

enum IntegrityCheck {
    private(set) static var lastReport: IntegrityReport?

    @discardableResult
    static func run(context: ModelContext) -> IntegrityReport {
        let books = (try? context.fetch(FetchDescriptor<CatalogBook>())) ?? []
        let loans = (try? context.fetch(FetchDescriptor<ActiveLoan>())) ?? []
        var report = IntegrityReport(bookCount: books.count)

        var byID: [UUID: CatalogBook] = [:]
        var isbnCounts: [String: Int] = [:]
        for book in books {
            byID[book.id] = book
            if let quantity = book.quantity, quantity < 1 {
                book.quantity = 1
                report.fixedQuantities += 1
            }
            let isbn = ISBNFormatter.normalize(book.isbn ?? "")
            if isbn.count >= 10 { isbnCounts[isbn, default: 0] += 1 }
        }
        report.duplicateISBNGroups = isbnCounts.values.filter { $0 > 1 }.count

        var loanCounts: [UUID: Int] = [:]
        for loan in loans {
            if byID[loan.bookID] == nil {
                report.orphanLoanTitles.append(loan.bookTitleSnapshot)
            } else {
                loanCounts[loan.bookID, default: 0] += 1
            }
        }
        for (id, count) in loanCounts {
            guard let book = byID[id] else { continue }
            if count > max(1, book.quantity ?? 1) { report.overLoanedTitles.append(book.title) }
        }

        if report.fixedQuantities > 0 { try? context.save() }
        lastReport = report
        AppLog.write("Bütünlük denetimi: " + report.summary.replacingOccurrences(of: "\n", with: " "))
        return report
    }
}

// MARK: - Tanılama günlüğü ve MetricKit

/// Uygulama içi olay günlüğü (kişisel veri yazılmaz): son 500 satır Önbellek klasöründe.
enum AppLog {
    private static let maxLines = 500
    private static var lines: [String] = load()

    private static var url: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("KitapBul-Gunluk.txt")
    }

    static var all: [String] { lines }

    static func write(_ message: String) {
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
        lines.append("\(stamp) \(message)")
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        guard let url else { return }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func clear() {
        lines = []
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    private static func load() -> [String] {
        guard let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("KitapBul-Gunluk.txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return text.split(separator: "\n").map(String.init)
    }
}

/// Apple'ın MetricKit çökme/takılma raporlarını Belgeler/Tanilama klasörüne kaydeder.
/// TestFlight olmadan da çökme ayrıntısı Tanılama ekranından paylaşılabilir.
nonisolated final class CrashReportCollector: NSObject, MXMetricManagerSubscriber, Sendable {
    static let shared = CrashReportCollector()

    static var directory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Tanilama", isDirectory: true)
    }

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard let directory = Self.directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for payload in payloads {
            let name = "Rapor-\(Int(payload.timeStampEnd.timeIntervalSince1970)).json"
            try? payload.jsonRepresentation().write(to: directory.appendingPathComponent(name), options: .atomic)
        }
    }

    static func reports() -> [URL] {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}

/// Tanılama ekranı: sürüm, sayılar, bütünlük raporu, arşivler, çöp kutusu ve günlük paylaşımı.
struct DiagnosticsView: View {
    @State private var catalogLease: ActiveCatalogLease?
    @Environment(\.modelContext) private var modelContext
    @State private var report = IntegrityCheck.lastReport
    @State private var archives: [URL] = AutoArchive.existingArchives()
    @State private var trashCount = TrashStore.count
    @State private var isArchiving = false
    @State private var bookCount = 0
    @State private var loanCount = 0
    @State private var logURL: URL?
    @State private var exportStatus: BackupExportStatus?
    @State private var exportStatusError: String?
    @AppStorage(ArchiveRetention.preferenceKey) private var retentionRaw = ArchiveRetentionPolicy.short.rawValue
    @State private var retentionFiles: [ArchiveRetentionFile] = []
    @State private var removalPlan: [ArchiveRetentionFile] = []
    @State private var retentionPreview = false
    @State private var confirmArchiveDeletion = false
    @State private var retentionError: String?
    @State private var staleTemporaries: (count: Int, bytes: Int64) = (0, 0)
    @State private var archiveNotice: String?
    @AppStorage(AutoArchive.autoApplyRetentionKey) private var autoApplyRetention = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func currentCatalogLease() throws -> ActiveCatalogLease {
        if catalogLease == nil { catalogLease = try ActiveCatalogLease.captureCurrent(context: modelContext) }
        guard let lease = catalogLease else { throw ActiveCatalogLease.Expired() }
        try lease.requireCurrent(context: modelContext)
        return lease
    }

    var body: some View {
        Form {
            Section("Uygulama") {
                LabeledContent("Sürüm", value: version)
                LabeledContent("Kitap", value: "\(bookCount)")
                LabeledContent("Etkin ödünç", value: "\(loanCount)")
                LabeledContent("Ödünç hareketi", value: "\(LoanHistoryStore.all.count)")
            }

            Section {
                if let report {
                    Text(report.summary)
                        .font(.callout)
                    if !report.orphanLoanTitles.isEmpty {
                        DisclosureGroup("Katalogda olmayan ödünçler") {
                            ForEach(Array(report.orphanLoanTitles.enumerated()), id: \.offset) { Text($0.element) }
                        }
                    }
                    if !report.overLoanedTitles.isEmpty {
                        DisclosureGroup("Fazla ödünçte görünenler") {
                            ForEach(Array(report.overLoanedTitles.enumerated()), id: \.offset) { Text($0.element) }
                        }
                    }
                }
                Button("Şimdi Denetle", systemImage: "checkmark.shield") {
                    report = IntegrityCheck.run(context: modelContext)
                }
            } header: {
                Text("Bütünlük")
            } footer: {
                Text("Her açılışta otomatik yapılır. Geçersiz adetler düzeltilir; diğer bulgular yalnızca raporlanır.")
            }

            Section {
                if let attempt = AutoArchive.lastAttemptDate {
                    LabeledContent("Son deneme", value: attempt.formatted(date: .abbreviated, time: .shortened))
                }
                if let last = AutoArchive.lastArchiveDate {
                    LabeledContent("Son başarılı arşiv", value: last.formatted(date: .abbreviated, time: .shortened))
                }
                if let failure = AutoArchive.lastFailure {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(KitapTema.ikincilMetin)
                }
                if staleTemporaries.count > 0 {
                    LabeledContent("Yarım kalan dosyalar", value: "\(staleTemporaries.count), \(ByteCountFormatter.string(fromByteCount: staleTemporaries.bytes, countStyle: .file))")
                    Button("Yarım Kalan Dosyaları Temizle", systemImage: "trash") {
                        AutoArchive.sweepStaleTemporaries()
                        staleTemporaries = AutoArchive.staleTemporaryCount()
                        archives = AutoArchive.existingArchives(); refreshRetention()
                    }
                }
                if let archiveNotice {
                    Label(archiveNotice, systemImage: "info.circle").font(.footnote)
                }
                ForEach(archives, id: \.self) { url in
                    ShareLink(item: url) {
                        Label(url.lastPathComponent, systemImage: "archivebox")
                    }
                }
                Picker("Saklama tercihi", selection: $retentionRaw) {
                    ForEach(ArchiveRetentionPolicy.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Eski arşivleri otomatik uygula", isOn: $autoApplyRetention)
                    .disabled(!YetkiDurumu.shared.yonetici || retentionRaw == ArchiveRetentionPolicy.all.rawValue)
                LabeledContent("Yerel arşiv alanı", value: ByteCountFormatter.string(
                    fromByteCount: retentionFiles.reduce(0) { $0 + $1.bytes }, countStyle: .file))
                Button("Eski Arşivleri İncele", systemImage: "list.bullet.rectangle") {
                    refreshRetention()
                    removalPlan = ArchiveRetention.removals(from: retentionFiles,
                        policy: ArchiveRetentionPolicy(rawValue: retentionRaw) ?? .short)
                    retentionPreview = true
                }
                if let retentionError {
                    // Hata yalnız renkle değil, uyarı ikonuyla ayrışır
                    Label(retentionError, systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(RenkliIkonEtiketi(renk: KitapTema.vurgu))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    let lease: ActiveCatalogLease
                    do { lease = try currentCatalogLease() }
                    catch { retentionError = error.localizedDescription; return }
                    let context = modelContext
                    let check: @MainActor @Sendable () throws -> Void = { @MainActor @Sendable in
                        try lease.requireCurrent(context: context)
                    }
                    isArchiving = true
                    Task { @MainActor in
                        defer { isArchiving = false }
                        do { try check() } catch { return }
                        let outcome = await AutoArchive.run(context: context, requireCurrent: check)
                        do { try check() } catch { return }
                        switch outcome {
                        case .atlandiCalisiyor: archiveNotice = "Arşiv zaten yazılıyor; bitmesini bekleyin."
                        case .basarisiz(let reason): archiveNotice = "Arşiv yazılamadı: \(reason)"
                        case .iptal: archiveNotice = "Arşiv yazımı durduruldu; yarım dosya silindi."
                        case .yazildi: archiveNotice = nil
                        }
                        archives = AutoArchive.existingArchives()
                        staleTemporaries = AutoArchive.staleTemporaryCount()
                        refreshRetention()
                    }
                } label: {
                    if isArchiving {
                        ProgressView()
                    } else {
                        Label("Şimdi Arşivle", systemImage: "archivebox.fill")
                    }
                }
                .disabled(isArchiving)
            } header: {
                Text("Otomatik Günlük Arşiv")
            } footer: {
                Text("Tam arşiv günde bir kez Dosyalar › Kitap Bul › Arsivler klasörüne yazılır. Arşiv ZIP'leri öğrenci ve üye bilgileri gibi kişisel veri içerir; paylaşırken dikkat edin. Saklama tercihi silinecek dosyaları önizler; dosyalar yalnız ayrıca onaylandığında silinir. 'Otomatik uygula' açıksa her günlük arşivden sonra saklama planının dışındaki eski dosyalar kendiliğinden silinir. Haftalık seçim her takvim haftasının en yeni yedeğini korur.")
            }

            Section {
                if let receipt = exportStatus?.lastSuccess {
                    LabeledContent("Son doğrulanmış yedek", value: receipt.verifiedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Seçilen hedef", value: receipt.targetName)
                    Text(receipt.fileName)
                    Text("\(receipt.books) eser · \(receipt.copies) nüsha · \(receipt.students) öğrenci · \(receipt.activeLoans) etkin ödünç")
                        .foregroundStyle(KitapTema.ikincilMetin)
                    LabeledContent("Dosya boyutu", value: ByteCountFormatter.string(fromByteCount: Int64(receipt.bytes), countStyle: .file))
                } else {
                    Label("Dış hedefte doğrulanmış tam yedek yok", systemImage: "exclamationmark.triangle")
                }
                if let attempt = exportStatus?.lastAttempt {
                    LabeledContent("Son deneme", value: attempt.formatted(date: .abbreviated, time: .shortened))
                }
                if let error = exportStatus?.lastFailure ?? exportStatusError {
                    Label(error, systemImage: "exclamationmark.triangle")
                }
            } header: {
                Text("Seçilen Hedefte Tam Yedek")
            } footer: {
                Text("Yönetim › Tam Arşiv Oluştur ile Dosyalar'da iCloud Drive veya başka bir hedef seçin. Başarı tarihi, kaydedilen dosyanın kapsamı ve sağlama toplamı doğrulanınca güncellenir.")
            }

            InactiveStoresSection()

            Section("Çöp Kutusu") {
                NavigationLink {
                    TrashView()
                        .onDisappear { trashCount = TrashStore.count }
                } label: {
                    LabeledContent("Silinen kitaplar", value: "\(trashCount)")
                }
            }

            Section {
                let reports = CrashReportCollector.reports()
                LabeledContent("Çökme/takılma raporu", value: "\(reports.count)")
                ForEach(reports.prefix(5), id: \.self) { url in
                    ShareLink(item: url) {
                        Label(url.lastPathComponent, systemImage: "ladybug")
                    }
                }
                if let logURL {
                    ShareLink(item: logURL) {
                        Label("Günlüğü Paylaş", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("Tanılama")
            } footer: {
                Text("Günlükte öğrenci adı ya da kitap içeriği yoktur; yalnızca işlem özetleri bulunur.")
            }
        }
        .navigationTitle("Veri ve Tanılama")
        .sheet(isPresented: $retentionPreview) {
            NavigationStack {
                List {
                    Section {
                        Text("\(removalPlan.count) eski arşiv · \(ByteCountFormatter.string(fromByteCount: removalPlan.reduce(0) { $0 + $1.bytes }, countStyle: .file))")
                        Text("Aşağıdaki yerel ZIP dosyaları kalıcı silinir. Katalog ve korunan arşivler bu işlemden etkilenmez.")
                    }
                    ForEach(removalPlan) { file in
                        VStack(alignment: .leading) {
                            Text(file.url.lastPathComponent)
                            Text(ByteCountFormatter.string(fromByteCount: file.bytes, countStyle: .file)).font(.caption)
                        }
                    }
                    if removalPlan.isEmpty { Text("Seçilen tercihe göre silinecek arşiv yok.") }
                    Button("Listelenen Arşivleri Sil", role: .destructive) { confirmArchiveDeletion = true }
                        .disabled(removalPlan.isEmpty)
                }
                .navigationTitle("Arşiv Silme Önizlemesi")
                .toolbar { Button("Kapat") { retentionPreview = false } }
                .confirmationDialog("Listelenen \(removalPlan.count) arşiv kalıcı silinsin mi?", isPresented: $confirmArchiveDeletion, titleVisibility: .visible) {
                    Button("Listelenen Dosyaları Sil", role: .destructive) {
                        do {
                            try SchoolLibraryService.requireAdmin()
                            guard let directory = AutoArchive.directory else { throw CocoaError(.fileNoSuchFile) }
                            try ArchiveRetention.removeVerified(removalPlan, in: directory)
                            removalPlan = []; archives = AutoArchive.existingArchives()
                            refreshRetention(); retentionPreview = false
                        } catch { retentionError = error.localizedDescription; retentionPreview = false }
                    }
                }
            }
        }
        .onAppear {
            do { _ = try currentCatalogLease() } catch { retentionError = error.localizedDescription; return }
            refreshRetention()
            staleTemporaries = AutoArchive.staleTemporaryCount()
            do { exportStatus = try BackupExportStatusStore.load(); exportStatusError = nil }
            catch { exportStatusError = "Yedek durum günlüğü okunamadı: \(error.localizedDescription)" }
            bookCount = (try? modelContext.fetchCount(FetchDescriptor<CatalogBook>())) ?? 0
            loanCount = (try? modelContext.fetchCount(FetchDescriptor<ActiveLoan>())) ?? 0
            if report == nil { report = IntegrityCheck.run(context: modelContext) }
            // Günlük dosyası bir kez, ekran açılınca yazılır (her çizimde değil)
            logURL = exportLog()
        }
    }

    private func refreshRetention() {
        guard let directory = AutoArchive.directory, FileManager.default.fileExists(atPath: directory.path) else {
            retentionFiles = []; return
        }
        do { retentionFiles = try ArchiveRetention.files(in: directory); retentionError = nil }
        catch { retentionError = error.localizedDescription }
    }

    private func exportLog() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("KitapBul-Gunluk.txt")
        let text = ["Kitap Bul \(version)", "Cihaz: \(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)", ""] + AppLog.all
        do {
            try text.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
