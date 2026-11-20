import Foundation
import SwiftData

@MainActor
extension StoreRecovery {
    struct PreparedStore {
        let container: ModelContainer
        let url: URL
    }

    /// Creates only a new isolated DB. Shared metadata and the active pointer are untouched.
    /// Models stay on their existing main actor; no ModelContext crosses an executor.
    static func prepareStore(_ contents: ArchiveContents) throws -> PreparedStore {
        try SchoolLibraryService.requireAdmin()
        let root = try ArchiveSwitchJournal.recoveredStoreRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(UUID().uuidString + ".store")
        return PreparedStore(container: try ArchiveLoanRestorer.buildRecoveryStore(contents: contents, at: url), url: url)
    }

    /// A background-validated journal lease and the final live-state gate precede this call.
    /// Shared metadata, model migration, checks and pointer publication form one synchronous
    /// actor transaction. It never compresses, parses or hashes a full ZIP on the main actor.
    static func activatePreparedStore(_ prepared: PreparedStore, contents: ArchiveContents,
                                      reservationNow: Date, switchJournalToken: UUID,
                                      lease: ArchiveSwitchJournal.CommitLease,
                                      preserveOperationalState: Bool = false,
                                      verify: ((ModelContext) throws -> Void)? = nil) throws -> ModelContainer {
        try SchoolLibraryService.requireAdmin()
        try ArchiveSwitchJournal.requirePending(token: switchJournalToken, lease: lease)
        var metadataBackup: URL?
        let priorWarning = LibrarySyncStatus.shared.warning
        do {
            metadataBackup = try ArchiveLoanRestorer.restoreRecoveryMetadata(contents)
            let context = prepared.container.mainContext
            // Merge already proved the combined graph and preserves the current records
            // exactly; a second migration or clock-based refresh would alter that scope.
            let converted = preserveOperationalState ? 0 : try SchoolLibraryService.migrateLegacyLoans(context: context)
            if !preserveOperationalState {
                try SchoolLibraryService.refreshReservations(context: context, now: reservationNow, notify: false)
            }
            try SchoolLibraryService.flushHistoryOutbox(context: context)
            let bookIDs = Set(try context.fetch(FetchDescriptor<CatalogBook>()).map(\.id))
            let loans = try context.fetch(FetchDescriptor<ActiveLoan>())
            let copies = try context.fetch(FetchDescriptor<BookCopy>())
            let reservations = try context.fetch(FetchDescriptor<Reservation>())
            guard bookIDs.count == contents.books.count, copies.count == contents.copies.count,
                  reservations.count == contents.reservations.count, loans.count == contents.activeLoans.count + converted,
                  try context.fetchCount(FetchDescriptor<ScanWriteReceipt>()) == contents.scanReceipts.count,
                  try context.fetchCount(FetchDescriptor<CatalogMergeUndoRecord>()) == contents.mergeUndoRecords.count,
                  loans.allSatisfy({ loan in bookIDs.contains(loan.bookID) && (loan.copyID == nil || copies.contains { $0.id == loan.copyID && $0.bookID == loan.bookID }) }),
                  copies.allSatisfy({ bookIDs.contains($0.bookID) }), reservations.allSatisfy({ bookIDs.contains($0.bookID) }),
                  Set(try StudentStore.allVerified().map(\.id)) == Set(contents.students.map(\.id)),
                  Set(try MemberStore.allVerified().map(\.id)) == Set(contents.members.map(\.id)),
                  Set(try GraduatedStudentStore.allVerified().map(\.id)) == Set(contents.graduatedStudents.map(\.id)),
                  Set(try LoanHistoryStore.allVerified().map(\.id)).isSuperset(of: contents.loanEvents.map(\.id)),
                  try ModelContext(prepared.container).fetchCount(FetchDescriptor<LibraryEventOutbox>()) == 0 else {
                throw SchoolLibraryService.OperationError(message: "Kurtarılan depo/metadata ilişkileri veya sayıları doğrulanamadı; eski işaretçi korundu.")
            }
            try verify?(context)
            UserDefaults.standard.set(prepared.url.path, forKey: selectedStoreKey)
            return prepared.container
        } catch {
            let original = error
            if let metadataBackup {
                do { try rollbackMetadata(from: metadataBackup) }
                catch { throw SchoolLibraryService.OperationError(message: "Kurtarma doğrulanamadı; metadata geri alma tamamlanmadı. Kalıcı geçiş günlüğü ve ham yedekler korundu.") }
            }
            LibrarySyncStatus.shared.warning = priorWarning
            throw original
        }
    }
}
