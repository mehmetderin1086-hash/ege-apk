import Foundation
import SwiftData
import Darwin
import Testing
@testable import _01

@MainActor
@Suite(.serialized)
struct ArchiveSwitchLeaseTestleri {
    private struct Fixture {
        let paths: ArchiveSwitchJournal.Paths
        let backup: URL
        let before: ArchiveContents
        let fingerprint: String
    }
    private struct Stale: Error {}

    private func isolated(_ body: (Fixture) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("switch-lease-" + UUID().uuidString)
        let metadata = root.appendingPathComponent("metadata", isDirectory: true)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        let oldPaths = ArchiveSwitchJournal.pathsOverride
        let student = StudentStore.directoryOverride, member = MemberStore.directoryOverride
        let history = LoanHistoryStore.directoryOverride, support = ArchiveSettings.directoryOverride
        let sessions = ScanSessionStore.directoryOverride, fields = FieldMaintenanceStore.directoryOverride
        let pointer = UserDefaults.standard.object(forKey: StoreRecovery.selectedStoreKey)
        let lock = YetkiDurumu.shared.kilitEtkin, preferences = ArchiveSettings.snapshot()
        StudentStore.directoryOverride = metadata; MemberStore.directoryOverride = metadata
        LoanHistoryStore.directoryOverride = metadata; ArchiveSettings.directoryOverride = metadata
        ScanSessionStore.directoryOverride = metadata.appendingPathComponent("sessions")
        FieldMaintenanceStore.directoryOverride = nil
        LoanHistoryStore.invalidateCache(); YetkiDurumu.shared.kilitEtkin = false
        let paths = ArchiveSwitchJournal.Paths(journalURL: root.appendingPathComponent("journal.json"),
            backupRoot: root.appendingPathComponent("backups"), recoveredRoot: root.appendingPathComponent("stores"))
        ArchiveSwitchJournal.pathsOverride = paths
        UserDefaults.standard.removeObject(forKey: StoreRecovery.selectedStoreKey)
        defer {
            ArchiveSwitchJournal.pathsOverride = oldPaths
            StudentStore.directoryOverride = student; MemberStore.directoryOverride = member
            LoanHistoryStore.directoryOverride = history; ArchiveSettings.directoryOverride = support
            ScanSessionStore.directoryOverride = sessions; FieldMaintenanceStore.directoryOverride = fields
            LoanHistoryStore.invalidateCache()
            try? ArchiveSettings.restore(preferences); YetkiDurumu.shared.kilitEtkin = lock
            if let pointer { UserDefaults.standard.set(pointer, forKey: StoreRecovery.selectedStoreKey) }
            else { UserDefaults.standard.removeObject(forKey: StoreRecovery.selectedStoreKey) }
            try? FileManager.default.removeItem(at: root)
        }
        let person = Student(name: "Lease Öğrencisi", number: "101", className: "7/A")
        try StudentStore.replaceAllVerified([person])
        let before = ArchiveContents(books: [Book(title: "Lease Eseri", author: "Y")], students: [person], settings: ArchiveSettings.snapshot())
        let backup = paths.backupRoot.appendingPathComponent("switch-lease", isDirectory: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try FullArchive.buildVerified(before).write(to: backup.appendingPathComponent("Islem-Oncesi-Tam-Arsiv.zip"), options: .atomic)
        try ArchiveImportCoordinator.captureRawMetadata(at: backup)
        try await body(Fixture(paths: paths, backup: backup, before: before, fingerprint: try ArchiveImportCoordinator.fingerprint(before)))
    }

    @Test func workerProofThenAtomicCallbackCommitsAndStartupReassertsRealSQLite() async throws {
        try await isolated { fixture in
            var checked = false
            let container = try await ArchiveSwitchJournal.beginAndCommitAsync(backupDirectory: fixture.backup, oldPointer: nil,
                beforeFingerprint: fixture.fingerprint, beforeBegin: { checked = true }) { token, lease in
                    #expect(checked)
                    try ArchiveSwitchJournal.requirePending(token: token, lease: lease)
                    try FileManager.default.createDirectory(at: fixture.paths.recoveredRoot, withIntermediateDirectories: true)
                    let url = fixture.paths.recoveredRoot.appendingPathComponent("new.store")
                    let store = try ArchiveLoanRestorer.buildRecoveryStore(contents: fixture.before, at: url)
                    UserDefaults.standard.set(url.path, forKey: StoreRecovery.selectedStoreKey)
                    try ArchiveSwitchJournal.markCommitted(token: token, newPath: url.path, lease: lease)
                    return store
                }
            UserDefaults.standard.removeObject(forKey: StoreRecovery.selectedStoreKey)
            let recovery = try ArchiveSwitchJournal.recoverPendingBeforeStoreOpen()
            let recovered = try #require(recovery)
            #expect(recovered.phase == .committed)
            #expect(UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey)?.hasSuffix("new.store") == true)
            #expect(try container.mainContext.fetch(FetchDescriptor<CatalogBook>()).map(\.title) == ["Lease Eseri"])
        }
    }

    @Test func staleBeforeBeginNeverCreatesMarkerAndPreservesNewLiveMetadata() async throws {
        try await isolated { fixture in
            let concurrent = Student(name: "Eşzamanlı yeni kişi", number: "202")
            var called = false
            do {
                _ = try await ArchiveSwitchJournal.beginAndCommitAsync(backupDirectory: fixture.backup, oldPointer: nil,
                    beforeFingerprint: fixture.fingerprint, beforeBegin: {
                        try StudentStore.replaceAllVerified([concurrent]); throw Stale()
                    }) { _, _ in called = true }
                Issue.record("Stale canlı snapshot yeni marker oluşturamamalı")
            } catch is Stale { }
            #expect(!called && !FileManager.default.fileExists(atPath: fixture.paths.journalURL.path))
            #expect(try StudentStore.allVerified() == [concurrent])
        }
    }

    @Test func identicalBytesAtomicReplacementFailsSealBeforePendingWrite() async throws {
        try await isolated { fixture in
            let url = fixture.backup.appendingPathComponent("Islem-Oncesi-Tam-Arsiv.zip")
            let data = try Data(contentsOf: url)
            do {
                _ = try await ArchiveSwitchJournal.beginAndCommitAsync(backupDirectory: fixture.backup, oldPointer: nil,
                    beforeFingerprint: fixture.fingerprint, beforeBegin: { try data.write(to: url, options: .atomic) }) { _, _ in
                        Issue.record("Aynı baytlı yeni inode bile yeniden doğrulama gerektirir")
                    }
                Issue.record("Private backup replacement kabul edildi")
            } catch is ArchiveSwitchLeaseWorker.Failure { }
            #expect(!FileManager.default.fileExists(atPath: fixture.paths.journalURL.path))
            #expect(try StudentStore.allVerified() == fixture.before.students)
        }
    }

    @Test func wrongTokenCannotConsumeLeaseAndVerifiedUnchangedRollbackCompletes() async throws {
        try await isolated { fixture in
            try await ArchiveSwitchJournal.beginAndCommitAsync(backupDirectory: fixture.backup, oldPointer: nil,
                beforeFingerprint: fixture.fingerprint, beforeBegin: {}) { token, lease in
                    #expect(throws: SchoolLibraryService.OperationError.self) {
                        try ArchiveSwitchJournal.requirePending(token: UUID(), lease: lease)
                    }
                    try ArchiveSwitchJournal.finishRollback(token: token, lease: lease)
                }
            #expect(!FileManager.default.fileExists(atPath: fixture.paths.journalURL.path))
            #expect(try StudentStore.allVerified() == fixture.before.students)
        }
    }

    @Test func changedPendingMarkerOrPrivateBackupNeverPassesCheapCommitGuard() async throws {
        try await isolated { fixture in
            try await ArchiveSwitchJournal.beginAndCommitAsync(backupDirectory: fixture.backup, oldPointer: nil,
                beforeFingerprint: fixture.fingerprint, beforeBegin: {}) { token, lease in
                    let marker = try Data(contentsOf: fixture.paths.journalURL)
                    try marker.write(to: fixture.paths.journalURL, options: .atomic)
                    #expect(throws: ArchiveSwitchLeaseWorker.Failure.self) {
                        try ArchiveSwitchJournal.requirePending(token: token, lease: lease)
                    }
                }
            #expect(FileManager.default.fileExists(atPath: fixture.paths.journalURL.path))
            #expect(try StudentStore.allVerified() == fixture.before.students)
        }
    }

    @Test func sameInodeAndSizeWithExactlyRestoredMtimeStillRejectsTamperedBackup() async throws {
        try await isolated { fixture in
            try await ArchiveSwitchJournal.beginAndCommitAsync(backupDirectory: fixture.backup, oldPointer: nil,
                beforeFingerprint: fixture.fingerprint, beforeBegin: {}) { token, lease in
                    let url = fixture.backup.appendingPathComponent("Islem-Oncesi-Tam-Arsiv.zip")
                    let before = try ArchiveSwitchLeaseWorker.FileSeal.capture(url)
                    let first = try #require(Data(contentsOf: url).first)
                    let handle = try FileHandle(forUpdating: url)
                    defer { try? handle.close() }
                    try handle.seek(toOffset: 0)
                    try handle.write(contentsOf: Data([first ^ 1]))
                    try handle.synchronize()
                    // Date/utimes yuvarlama yerine eski mtime'ı tam nanosanıye
                    // değeriyle geri yükle; test ctime korumasını ayrı sınar.
                    let times = [timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT)),
                                 timespec(tv_sec: Int(before.modifiedSeconds), tv_nsec: Int(before.modifiedNanoseconds))]
                    let reset = times.withUnsafeBufferPointer { Darwin.futimens(handle.fileDescriptor, $0.baseAddress!) }
                    guard reset == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                    let after = try ArchiveSwitchLeaseWorker.FileSeal.capture(url)
                    #expect(before.inode == after.inode && before.device == after.device && before.size == after.size)
                    #expect(before.modifiedSeconds == after.modifiedSeconds && before.modifiedNanoseconds == after.modifiedNanoseconds)
                    #expect(before.changedSeconds != after.changedSeconds || before.changedNanoseconds != after.changedNanoseconds)
                    #expect(throws: ArchiveSwitchLeaseWorker.Failure.self) {
                        try ArchiveSwitchJournal.requirePending(token: token, lease: lease)
                    }
                    #expect(throws: ArchiveSwitchLeaseWorker.Failure.self) {
                        try ArchiveSwitchJournal.markCommitted(token: token, newPath: fixture.paths.recoveredRoot.appendingPathComponent("unused.store").path, lease: lease)
                    }
                }
            #expect(FileManager.default.fileExists(atPath: fixture.paths.journalURL.path))
            #expect(try StudentStore.allVerified() == fixture.before.students)
        }
    }

    @Test func asyncCoordinatorPreservesTypedMemberCopyLoanAndOldSessionTimestampsExactly() async throws {
        try await isolated { fixture in
            let previousShared = KitapVeritabani.shared
            let previousReceipt = LibraryStoreSwitchStatus.shared.receipt
            let previousWarning = LibrarySyncStatus.shared.warning
            defer {
                KitapVeritabani.shared = previousShared
                LibraryStoreSwitchStatus.shared.receipt = previousReceipt
                LibrarySyncStatus.shared.warning = previousWarning
            }
            let current = try KitapVeritabani.makeContainer(inMemory: true)
            for book in fixture.before.books { current.mainContext.insert(CatalogBook(book: book)) }
            try current.mainContext.save()
            let oldDate = Date(timeIntervalSince1970: 1_704_067_200)
            var beforeSession = ScanSession(kind: .voice, title: "İşlem öncesi eski tarama")
            beforeSession.createdAt = oldDate.addingTimeInterval(-7200)
            beforeSession.updatedAt = oldDate.addingTimeInterval(-3600)
            try ScanSessionStore.save(beforeSession, updateTimestamp: false)
            let persistedBefore = try ScanSessionStore.allVerified()
            #expect(persistedBefore.first?.updatedAt == beforeSession.updatedAt)

            let book = Book(title: "Kimlikli Arşiv Eseri", author: "Arşiv Yazarı", quantity: 1, addedAt: oldDate)
            let member = Member(name: "Arşiv Öğretmeni", memberNumber: "M-202", kind: .teacher)
            let copy = ArchivedCopy(id: UUID(), bookID: book.id, accessionCode: "ARC-001", condition: "İyi", status: "Rafta",
                note: "Arşiv nüshası", addedAt: oldDate, cabinet: "C", shelf: "Türk Edebiyatı")
            let loan = ArchivedLoan(id: UUID(), bookID: book.id, bookTitleSnapshot: book.title,
                studentName: member.name, studentClass: "", loanedAt: oldDate.addingTimeInterval(7200),
                dueDate: oldDate.addingTimeInterval(7 * 86400), memberID: member.id,
                identitySource: "member", copyID: copy.id, needsIdentityReview: false, kind: "library")
            var session = ScanSession(kind: .barcode, title: "Arşivde eski tarama oturumu")
            session.createdAt = oldDate; session.updatedAt = oldDate.addingTimeInterval(3600)
            session.pendingBooks = [Book(title: "Kontrol bekleyen kitap", author: "Yazar", addedAt: oldDate)]
            let incoming = ArchiveContents(books: [book], activeLoans: [loan], copies: [copy], members: [member], scanSessions: [session])
            let preparation = try await ArchiveSwitchCoordinator.prepareAsync(
                data: FullArchive.buildVerified(incoming), context: current.mainContext)
            #expect(preparation.expected.scanSessions.first?.updatedAt == session.updatedAt)
            var activation: LibraryStoreActivation?
            let receipt = try await ArchiveSwitchCoordinator.applyAsync(preparation, context: current.mainContext,
                publish: { activation = $0 })
            let published = try #require(activation)
            let snapshot = try FullArchive.snapshot(context: published.container.mainContext)
            #expect(try ArchiveLiveState.same(snapshot, preparation.expected))
            #expect(snapshot.books.map(\.id) == [book.id] && snapshot.members.map(\.id) == [member.id])
            #expect(snapshot.activeLoans.count == 1 && snapshot.copies.count == 1)
            #expect(snapshot.activeLoans.first?.id == loan.id && snapshot.activeLoans.first?.memberID == member.id)
            #expect(snapshot.activeLoans.first?.studentID == nil && snapshot.activeLoans.first?.identitySource == "member")
            #expect(snapshot.activeLoans.first?.copyID == copy.id && snapshot.copies.first?.bookID == book.id)
            let restoredSession = try #require(snapshot.scanSessions.first)
            #expect(restoredSession.id == session.id && restoredSession.createdAt == oldDate)
            #expect(restoredSession.updatedAt == session.updatedAt && restoredSession.pendingBooks == session.pendingBooks)
            let persistedAfter = try ScanSessionStore.allVerified()
            #expect(persistedAfter == [session])
            let previousZIP = try FullArchive.readValidated(from: receipt.backupURL)
            #expect(previousZIP.books.map(\.id) == fixture.before.books.map(\.id))
            #expect(previousZIP.scanSessions == [beforeSession])
            #expect(receipt.beforeBooks == 1 && receipt.afterBooks == 1)
            withExtendedLifetime(current) {}
        }
    }

    @Test func badFingerprintNeverCreatesMarkerOrInvokesCommit() async throws {
        try await isolated { fixture in
            var called = false
            do {
                _ = try await ArchiveSwitchJournal.beginAndCommitAsync(backupDirectory: fixture.backup, oldPointer: nil,
                    beforeFingerprint: String(repeating: "0", count: 64), beforeBegin: {}) { _, _ in called = true }
                Issue.record("Tam arşiv fingerprint hatası kabul edildi")
            } catch is ArchiveSwitchLeaseWorker.Failure { }
            #expect(!called && !FileManager.default.fileExists(atPath: fixture.paths.journalURL.path))
            #expect(try StudentStore.allVerified() == fixture.before.students)
        }
    }
}


// Append this extension to ArchiveSwitchLeaseTestleri.swift after the suite body.
// It reuses the suite's serialized, temporary-path fixture; no extra global races.
@MainActor
extension ArchiveSwitchLeaseTestleri {
    @Test func asyncMergeActivatesNewStorePreservingCurrentUUIDCoverHoldAndTypedIncomingLoan() async throws {
        try await isolated { fixture in
            let shared = KitapVeritabani.shared, receipt = LibraryStoreSwitchStatus.shared.receipt
            let warning = LibrarySyncStatus.shared.warning
            defer { KitapVeritabani.shared = shared; LibraryStoreSwitchStatus.shared.receipt = receipt; LibrarySyncStatus.shared.warning = warning }
            let current = try KitapVeritabani.makeContainer(inMemory: true)
            let seed = try #require(fixture.before.books.first)
            let oldDate = Date(timeIntervalSince1970: 1_704_067_200)
            let existing = Book(id: seed.id, title: seed.title, author: seed.author, quantity: 2, coverData: Data([1, 2, 3, 4]), addedAt: oldDate)
            current.mainContext.insert(CatalogBook(book: existing))
            let oldCopy = BookCopy(bookID: existing.id, accessionCode: "LIVE-001")
            oldCopy.addedAt = oldDate
            current.mainContext.insert(oldCopy)
            let hold = Reservation(bookID: existing.id, bookTitleSnapshot: existing.title,
                studentName: fixture.before.students[0].name, studentClass: fixture.before.students[0].className)
            hold.studentID = fixture.before.students[0].id; hold.identitySource = "student"
            hold.copyID = oldCopy.id; hold.createdAt = oldDate
            hold.notifiedAt = oldDate.addingTimeInterval(3600); hold.expiresAt = oldDate.addingTimeInterval(86400)
            current.mainContext.insert(hold)
            try current.mainContext.save()
            var oldSession = ScanSession(kind: .voice, title: "Mevcut eski oturum")
            oldSession.createdAt = oldDate; oldSession.updatedAt = oldDate.addingTimeInterval(3600)
            try ScanSessionStore.save(oldSession, updateTimestamp: false)
            let before = try FullArchive.snapshot(context: current.mainContext)

            var conflicting = existing; conflicting.title = "Arşivden üzerine yazılmamalı"
            conflicting.coverData = Data([9, 9, 9])
            let added = Book(title: "Yeni kimlikli eser", author: "Yazar", quantity: 1, addedAt: oldDate)
            let member = Member(name: "Yeni öğretmen", memberNumber: "M-303", kind: .teacher)
            let copy = ArchivedCopy(id: UUID(), bookID: added.id, accessionCode: "NEW-001", condition: "İyi", status: "Rafta", note: "", addedAt: oldDate)
            let loan = ArchivedLoan(id: UUID(), bookID: added.id, bookTitleSnapshot: added.title,
                studentName: member.name, studentClass: "", loanedAt: oldDate, dueDate: oldDate.addingTimeInterval(7 * 86400),
                memberID: member.id, identitySource: "member", copyID: copy.id, needsIdentityReview: false, kind: "library")
            var newSession = ScanSession(kind: .barcode, title: "Arşivden gelen oturum")
            newSession.createdAt = oldDate.addingTimeInterval(7200); newSession.updatedAt = oldDate.addingTimeInterval(10800)
            let incoming = ArchiveContents(books: [conflicting, added], activeLoans: [loan], copies: [copy], members: [member], scanSessions: [newSession])
            let preparation = try await ArchiveImportCoordinator.prepareAsync(data: FullArchive.buildVerified(incoming), context: current.mainContext, now: oldDate)
            #expect(preparation.preparedAt == oldDate)
            var activation: LibraryStoreActivation?
            let result = try await ArchiveImportCoordinator.applyAsync(preparation, context: current.mainContext, publish: { activation = $0 })
            let activated = try #require(activation)
            #expect(activated.container !== current)
            let after = try FullArchive.snapshot(context: activated.container.mainContext)
            #expect(try ArchiveLiveState.same(after, preparation.expected))
            #expect(after.books.first(where: { $0.id == existing.id }) == existing)
            #expect(after.activeLoans.first?.id == loan.id && after.activeLoans.first?.memberID == member.id)
            #expect(after.activeLoans.first?.copyID == copy.id && after.activeLoans.first?.studentID == nil)
            #expect(after.reservations.first?.id == hold.id && after.reservations.first?.notifiedAt == hold.notifiedAt)
            #expect(after.reservations.first?.expiresAt == hold.expiresAt && after.reservations.first?.isClosed == false)
            #expect(after.scanSessions.contains(oldSession) && after.scanSessions.contains(newSession))
            #expect(try current.mainContext.fetch(FetchDescriptor<CatalogBook>()).map(\.book) == [existing])
            #expect(try current.mainContext.fetch(FetchDescriptor<ActiveLoan>()).isEmpty)
            #expect(try current.mainContext.fetch(FetchDescriptor<Reservation>()).map(ArchivedReservation.init) == before.reservations)
            #expect(result.summary.hasPrefix("Mevcut kataloğa ekleme"))
            #expect(try String(contentsOf: activated.receipt.scopeReportURL, encoding: .utf8).hasPrefix("Mevcut kataloğa ekleme: dogrulandi"))
            let backup = try FullArchive.readValidated(from: result.backupURL)
            #expect(try ArchiveLiveState.same(backup, before))
            let listing = try ArchiveSwitchBackupStore.listing(root: fixture.paths.backupRoot)
            #expect(listing.failures.isEmpty && listing.entries.count == 1)
            let startupResult = try ArchiveSwitchJournal.recoverPendingBeforeStoreOpen()
            let recovered = try #require(startupResult)
            #expect(recovered.phase == .committed)
        }
    }

    @Test func asyncMergeNewContextVerificationFailureRestoresRawMetadataPointerAndOldPendingOutbox() async throws {
        try await isolated { fixture in
            let shared = KitapVeritabani.shared, receipt = LibraryStoreSwitchStatus.shared.receipt
            let warning = LibrarySyncStatus.shared.warning
            defer { KitapVeritabani.shared = shared; LibraryStoreSwitchStatus.shared.receipt = receipt; LibrarySyncStatus.shared.warning = warning }
            let current = try KitapVeritabani.makeContainer(inMemory: true)
            let existing = try #require(fixture.before.books.first)
            current.mainContext.insert(CatalogBook(book: existing))
            let person = fixture.before.students[0], date = Date(timeIntervalSince1970: 1_704_067_200)
            let loan = ActiveLoan(bookID: existing.id, bookTitleSnapshot: existing.title, studentName: person.name, studentClass: person.className, dueDate: date.addingTimeInterval(86400))
            loan.studentID = person.id; loan.identitySource = "student"; loan.loanedAt = date
            current.mainContext.insert(loan)
            var event = LoanEvent(bookID: existing.id, bookTitle: existing.title, person: person.name, kind: .lent, date: date, dueDate: loan.dueDate)
            event.id = loan.id; event.loanID = loan.id; event.studentID = person.id; event.identitySource = "student"; event.classSnapshot = person.className
            let pending = try LibraryEventOutbox(event: event)
            current.mainContext.insert(pending); try current.mainContext.save()
            let queueBefore = try current.mainContext.fetch(FetchDescriptor<LibraryEventOutbox>()).map(ArchiveImportCoordinator.PendingEventSnapshot.init)
            let before = try FullArchive.snapshot(context: current.mainContext)
            let studentURL = try #require(StudentStore.storageURL), rawStudents = try Data(contentsOf: studentURL)
            let historyURL = try #require(LoanHistoryStore.storageURL)
            let rawHistory = try? Data(contentsOf: historyURL)
            let added = Book(title: "Hata halinde eklenmeyecek", author: "Yazar")
            let newStudent = Student(name: "Arşivden yeni kişi", number: "505", className: "8/A")
            let incoming = ArchiveContents(books: [added], students: [newStudent])
            let preparation = try await ArchiveImportCoordinator.prepareAsync(data: FullArchive.buildVerified(incoming), context: current.mainContext)
            var verifiedNewContext = false, published = false
            do {
                _ = try await ArchiveImportCoordinator.applyAsync(preparation, context: current.mainContext, verify: { newContext in
                    verifiedNewContext = newContext.container !== current
                    #expect(try newContext.fetch(FetchDescriptor<ActiveLoan>()).first?.studentID == person.id)
                    #expect(try LoanHistoryStore.allVerified().contains(where: { $0.id == event.id }))
                    #expect(try ModelContext(newContext.container).fetchCount(FetchDescriptor<LibraryEventOutbox>()) == 0)
                    let models = try newContext.fetch(FetchDescriptor<CatalogBook>())
                    let model = try #require(models.first(where: { $0.id == existing.id }))
                    model.title = "Sadece izole depoda değişen başlık"; try newContext.save()
                    try StudentStore.replaceAllVerified([newStudent])
                    throw Stale()
                }, publish: { _ in published = true })
                Issue.record("Yeni depo doğrulama hatası uygulanmış sayıldı")
            } catch is ArchiveImportCoordinator.ApplyError { }
            #expect(verifiedNewContext && !published)
            #expect(try ArchiveLiveState.same(FullArchive.snapshot(context: current.mainContext), before))
            #expect(try Data(contentsOf: studentURL) == rawStudents)
            #expect((try? Data(contentsOf: historyURL)) == rawHistory)
            #expect(try current.mainContext.fetch(FetchDescriptor<LibraryEventOutbox>()).map(ArchiveImportCoordinator.PendingEventSnapshot.init) == queueBefore)
            #expect(UserDefaults.standard.object(forKey: StoreRecovery.selectedStoreKey) == nil)
            #expect(!FileManager.default.fileExists(atPath: fixture.paths.journalURL.path))
            let listing = try ArchiveSwitchBackupStore.listing(root: fixture.paths.backupRoot)
            #expect(listing.failures.isEmpty && listing.entries.first?.state == "geri_alindi")
        }
    }
}
