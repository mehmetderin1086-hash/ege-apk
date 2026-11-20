import Foundation
import SwiftData

@MainActor
extension StoreRecovery {
    /// Production emergency recovery verifies the complete ZIP on a worker;
    /// the old synchronous restore API remains available to compatibility tests.
    static func restoreAsync(_ contents: ArchiveContents, reservationNow: Date? = nil,
        notifyReservations: Bool = true, beforeCommit: (() throws -> Void)? = nil,
        didStart: (@Sendable (Bool) -> Void)? = nil,
        verify: ((ModelContext) throws -> Void)? = nil) async throws -> ModelContainer {
        try await ArchiveSwitchJournal.withEmergencyRecoveryAsync(contents: contents,
            beforeCommit: beforeCommit, didStart: didStart) { selected, lease in
                // No ModelContext/global write crossed the worker boundary.
                let prepared = try prepareStore(selected)
                return try activateIndependentRecovery(prepared, contents: selected, reservationNow: reservationNow,
                    notifyReservations: notifyReservations, lease: lease, verify: verify)
            }
    }

    private static func activateIndependentRecovery(_ prepared: PreparedStore, contents: ArchiveContents,
        reservationNow: Date?, notifyReservations: Bool, lease: ArchiveSwitchJournal.EmergencyLease,
        verify: ((ModelContext) throws -> Void)?) throws -> ModelContainer {
        try SchoolLibraryService.requireAdmin()
        var metadataBackup: URL?
        let priorWarning = LibrarySyncStatus.shared.warning
        do {
            metadataBackup = try ArchiveLoanRestorer.restoreRecoveryMetadata(contents)
            let context = prepared.container.mainContext
            let converted = try SchoolLibraryService.migrateLegacyLoans(context: context)
            try SchoolLibraryService.refreshReservations(context: context, now: reservationNow ?? .now, notify: notifyReservations)
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
                throw SchoolLibraryService.OperationError(message: "Kurtarılan depo ilişkileri veya metadata sayıları doğrulanamadı; eski işaretçi korundu.")
            }
            try verify?(context)
            try ArchiveSwitchJournal.commitEmergencyRecovery(lease, newPath: prepared.url.path)
            // Every throwing operation ended BEFORE the durable committed marker.
            // The root UI is published only after this selected pointer is installed.
            UserDefaults.standard.set(prepared.url.path, forKey: selectedStoreKey)
            return prepared.container
        } catch {
            let original = error
            if let metadataBackup {
                do { try rollbackMetadata(from: metadataBackup) }
                catch { throw SchoolLibraryService.OperationError(message: "Kurtarma doğrulanamadı; metadata geri alma yazımı da tamamlanamadı. Eski günlük, özgün depo ve ham metadata-backup dosyaları korundu.") }
            }
            LibrarySyncStatus.shared.warning = priorWarning
            throw original
        }
    }
}
