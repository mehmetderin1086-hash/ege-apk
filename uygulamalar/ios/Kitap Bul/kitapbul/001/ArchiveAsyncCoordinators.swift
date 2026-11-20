import Foundation
import SwiftData

@MainActor
extension ArchiveImportCoordinator {
    static func captureRawMetadataPlan() throws -> ArchiveBackgroundWork.RawMetadata {
        var urls = [StudentStore.storageURL, MemberStore.storageURL, LoanHistoryStore.storageURL, GraduatedStudentStore.storageURL].compactMap { $0 }
        urls += ArchiveSettings.supportingFileNames.compactMap { ArchiveSettings.supportingURL(for: $0) }
        let sessions = ScanSessionStore.directoryOverride ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("TaramaOturumlari", isDirectory: true)
        if let sessions, FileManager.default.fileExists(atPath: sessions.path) {
            urls += try FileManager.default.contentsOfDirectory(at: sessions, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        }
        return ArchiveBackgroundWork.RawMetadata(sources: try urls.map {
            .init(url: $0, seal: try ArchiveBackgroundWork.FileSeal.capture($0))
        }, settings: ArchiveSettings.snapshot())
    }

    static func requireUnchanged(_ before: ArchiveContents, context: ModelContext) throws {
        try Task.checkCancellation()
        try SchoolLibraryService.requireAdmin()
        guard !context.hasChanges, try ArchiveLiveState.same(before, FullArchive.snapshot(context: context)) else {
            throw SchoolLibraryService.OperationError(message: "Arka plan doğrulaması sırasında katalog, kişi, geçmiş veya ayarlar değişti. Yeni önizleme gerekir; canlı veri değiştirilmedi.")
        }
    }

    static func prepareAsync(data: Data, context: ModelContext, restoreSettings: Bool = false, now: Date = .now) async throws -> Preparation {
        let token = try ArchiveUIOperationGate.begin(); defer { ArchiveUIOperationGate.end(token) }
        try SchoolLibraryService.requireAdmin()
        guard !context.hasChanges else { throw SchoolLibraryService.OperationError(message: "Önce açık değişiklikleri kaydedin.") }
        let before = try FullArchive.snapshot(context: context)
        let decoded = try await ArchiveBackgroundWork.decode(data, before: before)
        try requireUnchanged(before, context: context)
        let plan = try makePlan(before: before, incoming: decoded.incoming, restoreSettings: restoreSettings, now: now)
        let validated = try await ArchiveBackgroundWork.validate(plan.contents)
        try requireUnchanged(before, context: context)
        let expected = try runValidatedModelTrial(validated)
        _ = try await ArchiveBackgroundWork.validate(expected)
        try requireUnchanged(before, context: context)
        var warnings = plan.warnings
        let reviewCount = expected.activeLoans.filter { $0.needsIdentityReview == true }.count
        if reviewCount > 0 { warnings.append("\(reviewCount) ödünç kimlik eşleştirmesi gerektiriyor; kişi tahmin edilmedi.") }
        return Preparation(before: before, incoming: decoded.incoming, payload: plan.contents, expected: expected,
                           beforeFingerprint: decoded.beforeFingerprint,
                           rows: scope(before: before, incoming: decoded.incoming, after: expected), warnings: warnings,
                           restoreSettings: restoreSettings, migratedLoans: plan.migrated, preparedAt: now)
    }

    static func applyAsync(_ preparation: Preparation, context: ModelContext, backupDirectory: URL? = nil,
                           verify: ((ModelContext) throws -> Void)? = nil,
                           publish: ((LibraryStoreActivation) -> Void)? = nil) async throws -> Receipt {
        let token = try ArchiveUIOperationGate.begin(); defer { ArchiveUIOperationGate.end(token) }
        // Production merge uses the same durable new-store activation as replacement.
        // The old store is never edited; verify receives only the isolated NEW context.
        let activationPlan = ArchiveSwitchCoordinator.Preparation(before: preparation.before, incoming: preparation.incoming,
            expected: preparation.expected, beforeFingerprint: preparation.beforeFingerprint,
            preparedAt: preparation.preparedAt, restoreSettings: preparation.restoreSettings)
        let activated = try await ArchiveSwitchCoordinator.activateAsync(activationPlan, context: context,
            backupDirectory: backupDirectory, mode: .merge, verify: verify, publish: publish)
        return Receipt(backupURL: activated.backupURL, rows: preparation.rows, summary: activated.summary)
    }

}

@MainActor
extension ArchiveSwitchCoordinator {
    static func prepareAsync(data: Data, context: ModelContext, restoreSettings: Bool = false, now: Date = .now) async throws -> Preparation {
        let token = try ArchiveUIOperationGate.begin(); defer { ArchiveUIOperationGate.end(token) }
        try SchoolLibraryService.requireAdmin()
        guard !context.hasChanges else { throw SchoolLibraryService.OperationError(message: "Önce açık değişiklikleri kaydedin.") }
        let before = try FullArchive.snapshot(context: context)
        let decoded = try await ArchiveBackgroundWork.decode(data, before: before)
        try ArchiveImportCoordinator.requireUnchanged(before, context: context)
        var selected = decoded.incoming
        selected.settings = before.settings
        if restoreSettings { selected.settings.merge(decoded.incoming.settings) { _, imported in imported } }
        if !restoreSettings {
            for name in ["KademeKurallari.json", "KayitliGorunumler.json"] { selected.supportingFiles[name] = before.supportingFiles[name] }
        }
        let studentIDs = Set(selected.students.map(\.id))
        guard !selected.graduatedStudents.contains(where: { studentIDs.contains($0.id) }) else {
            throw SchoolLibraryService.OperationError(message: "Aynı öğrenci hem aktif hem mezun. Arşiv değiştirilmedi.")
        }
        let plan = try ArchiveImportCoordinator.makePlan(before: ArchiveContents(), incoming: selected,
            restoreSettings: true, now: now, validateStock: false)
        let validated = try await ArchiveBackgroundWork.validate(plan.contents)
        try ArchiveImportCoordinator.requireUnchanged(before, context: context)
        let expected = try ArchiveImportCoordinator.runValidatedModelTrial(validated, refreshAt: now)
        _ = try await ArchiveBackgroundWork.validate(expected)
        try ArchiveImportCoordinator.requireUnchanged(before, context: context)
        return Preparation(before: before, incoming: decoded.incoming, expected: expected,
                           beforeFingerprint: decoded.beforeFingerprint, preparedAt: now, restoreSettings: restoreSettings)
    }

    static func prepareAsync(from url: URL, context: ModelContext, restoreSettings: Bool = false, now: Date = .now) async throws -> Preparation {
        let before = try FullArchive.snapshot(context: context)
        let data = try await ArchiveBackgroundWork.read(url)
        try ArchiveImportCoordinator.requireUnchanged(before, context: context)
        return try await prepareAsync(data: data, context: context, restoreSettings: restoreSettings, now: now)
    }

    static func applyAsync(_ preparation: Preparation, context: ModelContext, backupDirectory: URL? = nil,
                           beforePublish: ((ModelContainer) throws -> Void)? = nil,
                           publish: ((LibraryStoreActivation) -> Void)? = nil) async throws -> Receipt {
        let token = try ArchiveUIOperationGate.begin(); defer { ArchiveUIOperationGate.end(token) }
        return try await activateAsync(preparation, context: context, backupDirectory: backupDirectory,
            mode: .separate, beforePublish: beforePublish, publish: publish)
    }

    enum ActivationMode {
        case separate, merge
        var title: String { self == .merge ? "Mevcut kataloğa ekleme" : "Ayrı katalog açma" }
    }

    /// Caller owns the single operation gate. One shared durable marker/lease covers both
    /// UI choices; there is no in-place DB commit and no nested begin/end gate.
    static func activateAsync(_ preparation: Preparation, context: ModelContext, backupDirectory: URL? = nil,
                              mode: ActivationMode, verify: ((ModelContext) throws -> Void)? = nil,
                              beforePublish: ((ModelContainer) throws -> Void)? = nil,
                              publish: ((LibraryStoreActivation) -> Void)? = nil) async throws -> Receipt {
        try ArchiveImportCoordinator.requireUnchanged(preparation.before, context: context)
        let pendingBefore = mode == .merge ? try context.fetch(FetchDescriptor<LibraryEventOutbox>())
            .map(ArchiveImportCoordinator.PendingEventSnapshot.init) : []
        guard Set(pendingBefore.map(\.id)).count == pendingBefore.count else {
            throw SchoolLibraryService.OperationError(message: "Bekleyen geçmiş hareketlerinde tekrarlanan kimlik var. Geçmiş aktarımını düzeltip yeni arşiv önizlemesi oluşturun; canlı veri değiştirilmedi.")
        }
        let root = try backupDirectory ?? ArchiveSwitchJournal.backupRoot()
        let directory = root.appendingPathComponent("switch-" + preparation.id.uuidString, isDirectory: true)
        let raw = try ArchiveImportCoordinator.captureRawMetadataPlan()
        let backup = try await ArchiveBackgroundWork.backup(before: preparation.before, incoming: preparation.incoming,
            fingerprint: preparation.beforeFingerprint, directory: directory, raw: raw)
        try ArchiveImportCoordinator.requireUnchanged(preparation.before, context: context)
        try ArchiveBackgroundWork.requireRawUnchanged(raw)
        let report = directory.appendingPathComponent("Katalog-Gecisi-Kapsam.txt")
        try writeActivationReport(preparation, mode: mode, state: "hazir", at: report)
        let oldPointer = UserDefaults.standard.object(forKey: StoreRecovery.selectedStoreKey)
        let preparedStore = try StoreRecovery.prepareStore(preparation.expected)
        if !pendingBefore.isEmpty {
            // Keep every pending ID, raw event, date and replace flag in the isolated DB.
            // The expected archive already folds these committed events into history;
            // flushing the new queue is idempotent and leaves the old queue untouched.
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            for snapshot in pendingBefore {
                let event = try decoder.decode(LoanEvent.self, from: snapshot.data)
                guard event.id == snapshot.id, preparation.expected.loanEvents.contains(where: { $0.id == event.id }) else {
                    throw SchoolLibraryService.OperationError(message: "Bekleyen geçmiş hareketi arşiv kapsamıyla tutarsız. Geçmiş aktarımını yeniden deneyip yeni önizleme oluşturun.")
                }
                let record = try LibraryEventOutbox(event: event, replacesExisting: snapshot.replacesExisting)
                record.id = snapshot.id; record.eventData = snapshot.data; record.createdAt = snapshot.date
                preparedStore.container.mainContext.insert(record)
            }
            try preparedStore.container.mainContext.save()
        }
        // The worker's final await happens INSIDE this helper, before the pending
        // marker exists. The stale gate, marker write and callback then share one
        // uninterrupted main-actor turn. Startup rollback cannot revert a newer
        // operation that interleaved after a prematurely written pending marker.
        return try await ArchiveSwitchJournal.beginAndCommitAsync(backupDirectory: directory,
            oldPointer: oldPointer, beforeFingerprint: preparation.beforeFingerprint,
            beforeBegin: {
                try ArchiveImportCoordinator.requireUnchanged(preparation.before, context: context)
                try ArchiveBackgroundWork.requireRawUnchanged(raw)
                if mode == .merge {
                    let currentPending = try context.fetch(FetchDescriptor<LibraryEventOutbox>())
                        .map(ArchiveImportCoordinator.PendingEventSnapshot.init)
                    guard currentPending.sorted(by: { $0.id.uuidString < $1.id.uuidString }) ==
                            pendingBefore.sorted(by: { $0.id.uuidString < $1.id.uuidString }) else {
                        throw SchoolLibraryService.OperationError(message: "Bekleyen geçmiş hareketleri değişti. Yeni arşiv önizlemesi gerekir; canlı veri değiştirilmedi.")
                    }
                }
            }) { journalToken, lease in
          let oldShared = KitapVeritabani.shared, oldWarning = LibrarySyncStatus.shared.warning
          do {
            let restored = try StoreRecovery.activatePreparedStore(preparedStore, contents: preparation.expected,
                reservationNow: preparation.preparedAt, switchJournalToken: journalToken, lease: lease,
                preserveOperationalState: mode == .merge) { restoredContext in
                    try verify?(restoredContext)
                    guard try ArchiveLiveState.same(FullArchive.snapshot(context: restoredContext), preparation.expected) else {
                        throw SchoolLibraryService.OperationError(message: "Yeni kataloğun tam kapsamı izole provayla aynı değil.")
                    }
                }
            try beforePublish?(restored)
            let receipt = Receipt(backupURL: backup.backupURL, scopeReportURL: report,
                beforeBooks: preparation.before.books.count, afterBooks: preparation.expected.books.count,
                summary: mode == .merge
                    ? "Mevcut kataloğa ekleme doğrulandı. Önceki eserler, kapaklar, kişiler ve açık ödünçler korundu. Yeni katalog: \(preparation.expected.books.count) eser, \(preparation.expected.activeLoans.count) açık ödünç. İşlem öncesi tam yedek yeniden açılabilir."
                    : "Arşiv ayrı katalog olarak açıldı. Önceki \(preparation.before.books.count) eserli katalog silinmedi; tam yedekten yeniden açılabilir. Yeni katalog: \(preparation.expected.books.count) eser, \(preparation.expected.activeLoans.count) açık ödünç.")
            try writeActivationReport(preparation, mode: mode, state: "dogrulandi", at: report)
            guard let newPath = UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey) else {
                throw SchoolLibraryService.OperationError(message: "Doğrulanmış yeni depo işaretçisi bulunamadı.")
            }
            try ArchiveSwitchJournal.markCommitted(token: journalToken, newPath: newPath, lease: lease)
            ActiveCatalogGeneration.didActivate()
            KitapVeritabani.shared = restored
            let activation = LibraryStoreActivation(container: restored, receipt: receipt)
            if let publish { publish(activation) }
            else {
                MainActor.assertIsolated()
                NotificationCenter.default.post(name: .libraryStoreActivated, object: activation)
            }
            return receipt
        } catch {
            let original = error
            if let oldPointer { UserDefaults.standard.set(oldPointer, forKey: StoreRecovery.selectedStoreKey) }
            else { UserDefaults.standard.removeObject(forKey: StoreRecovery.selectedStoreKey) }
            KitapVeritabani.shared = oldShared; LibrarySyncStatus.shared.warning = oldWarning
            do {
                try StoreRecovery.rollbackMetadata(from: directory)
                guard try ArchiveLiveState.same(FullArchive.snapshot(context: context), preparation.before) else {
                    throw SchoolLibraryService.OperationError(message: "Önceki kapsam geri alma doğrulamasından geçmedi.")
                }
                try writeActivationReport(preparation, mode: mode, state: "geri_alindi", at: report)
                try ArchiveSwitchJournal.finishRollback(token: journalToken, lease: lease)
            } catch {
                throw ArchiveImportCoordinator.ApplyError(message: "\(mode.title) uygulanmadı; metadata geri alma doğrulaması tamamlanamadı. Kalıcı geçiş günlüğü ve tam yedek korunuyor.", backupURL: backup.backupURL)
            }
            throw ArchiveImportCoordinator.ApplyError(message: "\(mode.title) uygulanmadı; eski işaretçi ve metadata geri getirildi. \(original.localizedDescription)", backupURL: backup.backupURL)
          }
        }
    }

    private static func writeActivationReport(_ preparation: Preparation, mode: ActivationMode, state: String, at url: URL) throws {
        if mode == .separate { try writeReport(preparation, state: state, at: url); return }
        let lines = ["\(mode.title): \(state)", "Önceki DB silinmez. İşlem öncesi tam ZIP ayrı saklanır."]
            + preparation.rows.map { "\($0.title): önce \($0.before), seçilen arşiv \($0.incoming), yeni katalog \($0.after)" }
        try Data(lines.joined(separator: "\n").utf8).write(to: url, options: .atomic)
    }

}
