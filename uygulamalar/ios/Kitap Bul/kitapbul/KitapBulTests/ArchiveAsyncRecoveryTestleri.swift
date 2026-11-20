import Foundation
import SwiftData
import Testing
import Darwin
import Dispatch
@testable import _01

@MainActor
@Suite(.serialized)
struct ArchiveAsyncRecoveryTestleri {
    @MainActor private struct Fixture {
        let root: URL
        let paths: ArchiveSwitchJournal.Paths
        let backup: URL
        let before: ArchiveContents
        let oldStore: ModelContainer
        let oldPath: String
        let rawStudent: Data
        let fingerprint: String
    }
    private struct Injected: Error {}

    private func isolated(_ action: (Fixture) async throws -> Void) async throws {
        try await TestSandbox.run { sandbox in
        let root = sandbox.root
        let metadata = root.appendingPathComponent("metadata", isDirectory: true)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        let priorPaths = ArchiveSwitchJournal.pathsOverride
        let fields = FieldMaintenanceStore.directoryOverride
        let preferences = ArchiveSettings.snapshot(), pointer = UserDefaults.standard.object(forKey: StoreRecovery.selectedStoreKey)
        let lock = YetkiDurumu.shared.kilitEtkin, shared = KitapVeritabani.shared, warning = LibrarySyncStatus.shared.warning
        let restoreLocations = StoreLocations.install(.isolated(root: metadata, defaultsSuite: sandbox.suiteName), includeSharedStores: false)
        FieldMaintenanceStore.directoryOverride = nil
        YetkiDurumu.shared.kilitEtkin = false
        for key in ArchiveSettings.allowedKeys { UserDefaults.standard.removeObject(forKey: key) }
        let paths = ArchiveSwitchJournal.Paths(journalURL: root.appendingPathComponent("journal.json"),
            backupRoot: root.appendingPathComponent("backups"), recoveredRoot: root.appendingPathComponent("stores"))
        ArchiveSwitchJournal.pathsOverride = paths
        defer {
            ArchiveSwitchJournal.pathsOverride = priorPaths
            restoreLocations(); FieldMaintenanceStore.directoryOverride = fields
            YetkiDurumu.shared.kilitEtkin = lock
            for key in ArchiveSettings.allowedKeys { UserDefaults.standard.removeObject(forKey: key) }
            try? ArchiveSettings.restore(preferences)
            if let pointer { UserDefaults.standard.set(pointer, forKey: StoreRecovery.selectedStoreKey) }
            else { UserDefaults.standard.removeObject(forKey: StoreRecovery.selectedStoreKey) }
            UserDefaults.standard.synchronize(); KitapVeritabani.shared = shared; LibrarySyncStatus.shared.warning = warning
        }
        let student = Student(name: "Önceki öğrenci", number: "101", className: "7/A")
        try StudentStore.replaceAllVerified([student]); UserDefaults.standard.set("Eski okul", forKey: "schoolName")
        UserDefaults.standard.set("dark", forKey: "appearanceMode")
        UserDefaults.standard.set(TemaRengi.indigo.rawValue, forKey: TemaRengi.anahtar)
        let before = ArchiveContents(books: [Book(title: "Önceki eser", author: "Y", addedAt: Date(timeIntervalSince1970: 1_700_000_000))],
            students: [student], settings: ArchiveSettings.snapshot())
        try FileManager.default.createDirectory(at: paths.recoveredRoot, withIntermediateDirectories: true)
        let oldURL = paths.recoveredRoot.appendingPathComponent("old.store")
        let oldStore = try ArchiveLoanRestorer.buildRecoveryStore(contents: before, at: oldURL)
        UserDefaults.standard.set(oldURL.path, forKey: StoreRecovery.selectedStoreKey)
        let backup = paths.backupRoot.appendingPathComponent("switch-before", isDirectory: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try FullArchive.buildVerified(before).write(to: backup.appendingPathComponent("Islem-Oncesi-Tam-Arsiv.zip"))
        try ArchiveImportCoordinator.captureRawMetadata(at: backup)
        let report = "Ayrı katalog açma: dogrulandi\n" + (1...12).map { "Kapsam \($0): önce 1, seçilen arşiv 2, yeni katalog 2" }.joined(separator: "\n")
        try Data(report.utf8).write(to: backup.appendingPathComponent("Katalog-Gecisi-Kapsam.txt"))
        let studentURL = try #require(StudentStore.storageURL)
        let fixture = Fixture(root: root, paths: paths, backup: backup, before: before, oldStore: oldStore,
            oldPath: oldURL.path, rawStudent: try Data(contentsOf: studentURL), fingerprint: try ArchiveImportCoordinator.fingerprint(before))
        try await action(fixture)
        withExtendedLifetime(oldStore) {}
        }
    }

    private func begin(_ fixture: Fixture) throws -> UUID {
        try ArchiveSwitchJournal.begin(backupDirectory: fixture.backup, oldPointer: fixture.oldPath,
            beforeFingerprint: fixture.fingerprint)
    }
    private func changeMetadata() throws {
        try StudentStore.replaceAllVerified([Student(name: "Yarım yeni kişi", number: "202")])
        UserDefaults.standard.set("light", forKey: "appearanceMode"); UserDefaults.standard.set("Yeni okul", forKey: "schoolName")
    }

    @Test func pendingStartupChecksOffMainAndRestoresOldMetadataEvenAfterPointerSwitchedWithRoleLocked() async throws {
        try await isolated { fixture in
            let token = try begin(fixture); try changeMetadata()
            let newURL = fixture.paths.recoveredRoot.appendingPathComponent("new.store")
            let newStore = try ArchiveLoanRestorer.buildRecoveryStore(contents: ArchiveContents(books: [Book(title: "Yarım yeni eser", author: "Y")]), at: newURL)
            UserDefaults.standard.set(newURL.path, forKey: StoreRecovery.selectedStoreKey)
            YetkiDurumu.shared.kilitEtkin = true; YetkiDurumu.shared.gorevliyeGec()
            KitapVeritabani.shared = nil
            let probe = fixture.root.appendingPathComponent("off-main.bin")
            let result = try await ArchiveSwitchJournal.recoverPendingBeforeStoreOpenAsync(didStart: { offMain in
                try? Data([offMain ? 1 : 0]).write(to: probe)
            })
            let recovery = try #require(result)
            let studentURL = try #require(StudentStore.storageURL)
            #expect(recovery.token == token && recovery.phase == .pending)
            #expect(try Data(contentsOf: probe) == Data([1]))
            #expect(try Data(contentsOf: studentURL) == fixture.rawStudent)
            #expect(UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey) == fixture.oldPath)
            #expect(UserDefaults.standard.string(forKey: "appearanceMode") == "dark")
            #expect(!YetkiDurumu.shared.yonetici && YetkiDurumu.shared.kilitEtkin && KitapVeritabani.shared == nil)
            #expect(!FileManager.default.fileExists(atPath: fixture.paths.journalURL.path))
            #expect(try String(contentsOf: fixture.backup.appendingPathComponent("Katalog-Gecisi-Kapsam.txt"), encoding: .utf8).hasPrefix("Ayrı katalog açma: geri_alindi"))
            #expect(try await ArchiveSwitchJournal.recoverPendingBeforeStoreOpenAsync() == nil)
            withExtendedLifetime(newStore) {}
        }
    }

    @Test func newLiveMetadataDuringWorkerVerificationIsNeverRolledBack() async throws {
        try await isolated { fixture in
            _ = try begin(fixture); try changeMetadata()
            let concurrent = Student(name: "Eşzamanlı son kayıt", number: "303")
            do {
                _ = try await ArchiveSwitchJournal.recoverPendingBeforeStoreOpenAsync(beforeRollback: {
                    try StudentStore.replaceAllVerified([concurrent])
                })
                Issue.record("Stale açılış izni yeni canlı kaydı geri almamalı")
            } catch is SchoolLibraryService.OperationError { }
            #expect(try StudentStore.allVerified() == [concurrent])
            #expect(FileManager.default.fileExists(atPath: fixture.paths.journalURL.path))
        }
    }

    @Test func changedPendingMarkerAfterWorkerCannotAuthorizeRawWrites() async throws {
        try await isolated { fixture in
            _ = try begin(fixture); try changeMetadata()
            let studentURL = try #require(StudentStore.storageURL), current = try Data(contentsOf: studentURL)
            let replacement = Data("farklı marker".utf8)
            do {
                _ = try await ArchiveSwitchJournal.recoverPendingBeforeStoreOpenAsync(beforeRollback: {
                    try replacement.write(to: fixture.paths.journalURL, options: .atomic)
                })
                Issue.record("Worker sonrası değişen marker kabul edilmemeli")
            } catch is SchoolLibraryService.OperationError { }
            #expect(try Data(contentsOf: studentURL) == current)
            #expect(try Data(contentsOf: fixture.paths.journalURL) == replacement)
        }
    }

    @Test func cancellingStartupBeforeCommitPreservesPendingMarkerAndMixedMetadataForNextAttempt() async throws {
        try await isolated { fixture in
            _ = try begin(fixture); try changeMetadata()
            let marker = try Data(contentsOf: fixture.paths.journalURL)
            let studentURL = try #require(StudentStore.storageURL), current = try Data(contentsOf: studentURL)
            let signal = fixture.root.appendingPathComponent("worker-start.bin"), release = DispatchSemaphore(value: 0)
            defer { release.signal() }
            let task = Task { @MainActor in
                try await ArchiveSwitchJournal.recoverPendingBeforeStoreOpenAsync(didStart: { _ in
                    try? Data([1]).write(to: signal)
                    _ = release.wait(timeout: .now() + 5)
                })
            }
            for _ in 0..<1_000 {
                if FileManager.default.fileExists(atPath: signal.path) { break }
                try await Task.sleep(for: .milliseconds(1))
            }
            #expect(FileManager.default.fileExists(atPath: signal.path))
            task.cancel(); release.signal()
            do { _ = try await task.value; Issue.record("İptal edilmiş açılış metadata yazmamalı") }
            catch is CancellationError { }
            #expect(try Data(contentsOf: studentURL) == current && Data(contentsOf: fixture.paths.journalURL) == marker)
            _ = try await ArchiveSwitchJournal.recoverPendingBeforeStoreOpenAsync()
            #expect(try Data(contentsOf: studentURL) == fixture.rawStudent)
        }
    }

    @Test func emergencyVerifiedWorkerPreservesForensicMarkerAndCommittedPointerSurvivesProcessBoundary() async throws {
        try await isolated { fixture in
            let original = Data("bozuk fakat korunması gereken günlük".utf8)
            try original.write(to: fixture.paths.journalURL)
            let person = Student(name: "Kurtarılan öğrenci", number: "404", className: "8/A")
            let date = Date(timeIntervalSince1970: 1_700_000_000)
            let book = Book(title: "Kurtarılan kaynak eser", author: "Y", coverData: Data([1, 2]), addedAt: date)
            var session = ScanSession(kind: .photo, title: "Kurtarılan eski kaynak")
            session.createdAt = date; session.updatedAt = date; session.sourceImages = [Data([3, 4])]
            let selected = ArchiveContents(books: [book], students: [person], settings: ["schoolName": Data("\"Kurtarılan okul\"".utf8)], scanSessions: [session])
            let probe = fixture.root.appendingPathComponent("emergency-off-main.bin")
            let restored = try await StoreRecovery.restoreAsync(selected, didStart: { offMain in
                try? Data([offMain ? 1 : 0]).write(to: probe)
            })
            #expect(try Data(contentsOf: probe) == Data([1]))
            #expect(try StudentStore.allVerified() == [person])
            #expect(try ScanSessionStore.allVerified() == [session])
            #expect(try restored.mainContext.fetch(FetchDescriptor<CatalogBook>()).map(\.id) == [book.id])
            let entry = try JSONDecoder().decode(ArchiveSwitchJournal.Entry.self, from: Data(contentsOf: fixture.paths.journalURL))
            #expect(entry.phase == .committed && entry.emergencyRecovery == true)
            let forensic = URL(fileURLWithPath: entry.backupDirectory).appendingPathComponent("Onceki-Gecis-Gunlugu.bin")
            #expect(try Data(contentsOf: forensic) == original)
            #expect(try FullArchive.readValidated(from: URL(fileURLWithPath: entry.backupDirectory).appendingPathComponent("Secilen-Dogrulanmis-Arsiv.zip")).books == [book])
            UserDefaults.standard.set(42, forKey: StoreRecovery.selectedStoreKey)
            let recovered = try await ArchiveSwitchJournal.recoverPendingBeforeStoreOpenAsync()
            let outcome = try #require(recovered)
            #expect(outcome.phase == .committed && UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey) == entry.newPointer)
            #expect(!FileManager.default.fileExists(atPath: fixture.paths.journalURL.path))
        }
    }

    @Test func emergencyVerificationFailureRestoresRawMetadataAndOriginalBadMarker() async throws {
        try await isolated { fixture in
            let marker = Data("korunan bozuk marker".utf8)
            try marker.write(to: fixture.paths.journalURL)
            do {
                _ = try await StoreRecovery.restoreAsync(ArchiveContents(books: [Book(title: "Başarısız yeni eser", author: "Y")],
                    students: [Student(name: "Başarısız yeni kişi")]), verify: { _ in throw Injected() })
                Issue.record("İlişki kapısı başarısızken katalog yayınlanmamalı")
            } catch is Injected { }
            let studentURL = try #require(StudentStore.storageURL)
            #expect(try Data(contentsOf: studentURL) == fixture.rawStudent)
            #expect(try Data(contentsOf: fixture.paths.journalURL) == marker)
            #expect(UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey) == fixture.oldPath)
        }
    }

    @Test func revokedAdminAndChangedMetadataBeforeEmergencyCommitPreventAnySharedWrite() async throws {
        try await isolated { fixture in
            let marker = Data("önceki bozuk marker".utf8); try marker.write(to: fixture.paths.journalURL)
            let selected = ArchiveContents(books: [Book(title: "Yeni", author: "Y")])
            do {
                _ = try await StoreRecovery.restoreAsync(selected, beforeCommit: {
                    YetkiDurumu.shared.kilitEtkin = true; YetkiDurumu.shared.gorevliyeGec()
                })
                Issue.record("Worker beklerken kaybedilen yönetici yetkisi yeniden denetlenmeli")
            } catch is SchoolLibraryService.OperationError { }
            let studentURL = try #require(StudentStore.storageURL)
            #expect(try Data(contentsOf: studentURL) == fixture.rawStudent && Data(contentsOf: fixture.paths.journalURL) == marker)
            YetkiDurumu.shared.kilitEtkin = false
            let concurrent = Student(name: "Son canlı kişi", number: "505")
            do {
                _ = try await StoreRecovery.restoreAsync(selected, beforeCommit: { try StudentStore.replaceAllVerified([concurrent]) })
                Issue.record("Worker sonrası canlı metadata değişikliği korunmalı")
            } catch is SchoolLibraryService.OperationError { }
            #expect(try StudentStore.allVerified() == [concurrent])
            #expect(try Data(contentsOf: fixture.paths.journalURL) == marker)
        }
    }

    @Test func sealedEmergencyZIPRejectsSameInodeSizeAndRestoredMtimeTamperingBeforeMarkerCommit() async throws {
        try await isolated { fixture in
            let marker = Data("önceki marker".utf8); try marker.write(to: fixture.paths.journalURL)
            do {
                _ = try await ArchiveSwitchJournal.withEmergencyRecoveryAsync(contents: ArchiveContents(books: [Book(title: "Seçilen", author: "Y")])) { _, lease in
                    let directories = try FileManager.default.contentsOfDirectory(at: fixture.paths.backupRoot, includingPropertiesForKeys: nil)
                    let directory = try #require(directories.first { $0.lastPathComponent.hasPrefix("emergency-") })
                    let url = directory.appendingPathComponent("Secilen-Dogrulanmis-Arsiv.zip")
                    let before = try ArchiveSwitchLeaseWorker.FileSeal.capture(url)
                    let data = try Data(contentsOf: url), first = try #require(data.first)
                    let handle = try FileHandle(forUpdating: url); defer { try? handle.close() }
                    try handle.seek(toOffset: 0); try handle.write(contentsOf: Data([first ^ 1])); try handle.synchronize()
                    let times = [timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT)),
                                 timespec(tv_sec: Int(before.modifiedSeconds), tv_nsec: Int(before.modifiedNanoseconds))]
                    let status = times.withUnsafeBufferPointer { Darwin.futimens(handle.fileDescriptor, $0.baseAddress!) }
                    guard status == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                    let after = try ArchiveSwitchLeaseWorker.FileSeal.capture(url)
                    #expect(before.inode == after.inode && before.size == after.size && before.modifiedSeconds == after.modifiedSeconds && before.modifiedNanoseconds == after.modifiedNanoseconds)
                    try ArchiveSwitchJournal.commitEmergencyRecovery(lease, newPath: fixture.oldPath)
                }
                Issue.record("Özel ZIP yerinde değiştirilince cheap commit kapısı başarısız olmalı")
            } catch { }
            // A tampered private proof cannot authorize even rollback. Keep the
            // new durable pending marker failclosed instead of hiding the error.
            let entry = try JSONDecoder().decode(ArchiveSwitchJournal.Entry.self, from: Data(contentsOf: fixture.paths.journalURL))
            #expect(entry.phase == .pending && entry.emergencyRecovery == true)
            #expect(try Data(contentsOf: URL(fileURLWithPath: entry.backupDirectory).appendingPathComponent("Onceki-Gecis-Gunlugu.bin")) == marker)
            #expect(UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey) == fixture.oldPath)
        }
    }

    @Test func noOriginalMarkerEmergencyCrashAfterSharedWritesRestoresRawGlobalsAndPointerBeforeOpening() async throws {
        try await isolated { fixture in
            #expect(!FileManager.default.fileExists(atPath: fixture.paths.journalURL.path))
            let studentURL = try #require(StudentStore.storageURL)
            var crashMarker = Data(), crashStudent = Data()
            let selected = ArchiveContents(books: [Book(title: "Kapanmadan önce yeni eser", author: "Y")],
                students: [Student(name: "Yarım kurtarılan kişi", number: "606")],
                settings: ["appearanceMode": Data("\"light\"".utf8), "schoolName": Data("\"Yeni kurtarma okulu\"".utf8)])
            do {
                _ = try await StoreRecovery.restoreAsync(selected, verify: { _ in
                    crashMarker = try Data(contentsOf: fixture.paths.journalURL)
                    crashStudent = try Data(contentsOf: studentURL)
                    let pending = try JSONDecoder().decode(ArchiveSwitchJournal.Entry.self, from: crashMarker)
                    #expect(pending.phase == .pending && pending.emergencyRecovery == true)
                    #expect(pending.backupHashes["dosya-dizini.json"] != nil && pending.backupHashes["onceki-depo-isaretcisi.json"] != nil)
                    throw Injected()
                })
                Issue.record("İşlem öncesi doğrulama başarısızlığı yayına dönüşmemeli")
            } catch is Injected { }
            #expect(!crashMarker.isEmpty && !crashStudent.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: fixture.paths.journalURL.path))
            // Reinstall the exact durable files captured at the process boundary;
            // this simulates termination, rather than pretending catch is a kill.
            try crashMarker.write(to: fixture.paths.journalURL, options: .atomic)
            try crashStudent.write(to: studentURL, options: .atomic)
            UserDefaults.standard.set("light", forKey: "appearanceMode")
            UserDefaults.standard.set("Yeni kurtarma okulu", forKey: "schoolName")
            let newURL = fixture.paths.recoveredRoot.appendingPathComponent("interrupted-emergency.store")
            let newStore = try ArchiveLoanRestorer.buildRecoveryStore(contents: selected, at: newURL)
            UserDefaults.standard.set(newURL.path, forKey: StoreRecovery.selectedStoreKey)
            YetkiDurumu.shared.kilitEtkin = true; YetkiDurumu.shared.gorevliyeGec(); KitapVeritabani.shared = nil
            let probe = fixture.root.appendingPathComponent("pending-emergency-worker.bin")
            let result = try await ArchiveSwitchJournal.recoverPendingBeforeStoreOpenAsync(didStart: { offMain in
                try? Data([offMain ? 1 : 0]).write(to: probe)
            })
            #expect(try Data(contentsOf: probe) == Data([1]))
            #expect(result?.phase == .pending && KitapVeritabani.shared == nil && !YetkiDurumu.shared.yonetici)
            #expect(try Data(contentsOf: studentURL) == fixture.rawStudent)
            #expect(UserDefaults.standard.string(forKey: "appearanceMode") == "dark")
            #expect(UserDefaults.standard.string(forKey: "schoolName") == "Eski okul")
            #expect(UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey) == fixture.oldPath)
            #expect(!FileManager.default.fileExists(atPath: fixture.paths.journalURL.path))
            #expect(try await ArchiveSwitchJournal.recoverPendingBeforeStoreOpenAsync() == nil)
            let reopened = try KitapVeritabani.makeContainer(url: URL(fileURLWithPath: fixture.oldPath))
            #expect(try reopened.mainContext.fetch(FetchDescriptor<CatalogBook>()).map(\.id) == fixture.before.books.map(\.id))
            withExtendedLifetime(newStore) {}
        }
    }

    @Test func pendingEmergencyRestoresOpaqueCorruptOriginalMarkerAndStaysFailclosedWithoutAdmin() async throws {
        try await isolated { fixture in
            let original = Data("Özgün bozuk marker korunmalı".utf8)
            try original.write(to: fixture.paths.journalURL)
            let studentURL = try #require(StudentStore.storageURL)
            var crashMarker = Data(), crashStudent = Data()
            do {
                _ = try await StoreRecovery.restoreAsync(ArchiveContents(books: [Book(title: "Yarım acil eser", author: "Y")],
                    students: [Student(name: "Yarım acil kişi")]), verify: { _ in
                        crashMarker = try Data(contentsOf: fixture.paths.journalURL)
                        crashStudent = try Data(contentsOf: studentURL)
                        throw Injected()
                    })
                Issue.record("Başarısız doğrulama yayınlanmamalı")
            } catch is Injected { }
            #expect(try Data(contentsOf: fixture.paths.journalURL) == original)
            try crashMarker.write(to: fixture.paths.journalURL, options: .atomic)
            try crashStudent.write(to: studentURL, options: .atomic)
            YetkiDurumu.shared.kilitEtkin = true; YetkiDurumu.shared.gorevliyeGec(); KitapVeritabani.shared = nil
            do {
                _ = try await ArchiveSwitchJournal.recoverPendingBeforeStoreOpenAsync()
                Issue.record("Bozuk özgün marker geri gelince bu açılış failclosed kalmalı")
            } catch is SchoolLibraryService.OperationError { }
            #expect(try Data(contentsOf: studentURL) == fixture.rawStudent)
            #expect(try Data(contentsOf: fixture.paths.journalURL) == original)
            #expect(UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey) == fixture.oldPath)
            #expect(KitapVeritabani.shared == nil && !YetkiDurumu.shared.yonetici)
            do { _ = try await ArchiveSwitchJournal.recoverPendingBeforeStoreOpenAsync(); Issue.record("Özgün bozuk marker sonraki açılışta da korunmalı") }
            catch { }
            #expect(try Data(contentsOf: fixture.paths.journalURL) == original)
        }
    }

    @Test func tamperedEmergencyRawBackupNeverWritesLiveGlobalsAtStartup() async throws {
        try await isolated { fixture in
            let studentURL = try #require(StudentStore.storageURL)
            var crashMarker = Data(), crashStudent = Data()
            do {
                _ = try await StoreRecovery.restoreAsync(ArchiveContents(books: [Book(title: "Yarım", author: "Y")],
                    students: [Student(name: "Yeni kişi")]), verify: { _ in
                        crashMarker = try Data(contentsOf: fixture.paths.journalURL)
                        crashStudent = try Data(contentsOf: studentURL)
                        throw Injected()
                    })
            } catch is Injected { }
            try crashMarker.write(to: fixture.paths.journalURL, options: .atomic)
            try crashStudent.write(to: studentURL, options: .atomic)
            let entry = try JSONDecoder().decode(ArchiveSwitchJournal.Entry.self, from: crashMarker)
            let directory = URL(fileURLWithPath: entry.backupDirectory)
            let index = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: directory.appendingPathComponent("dosya-dizini.json")))
            let name = try #require(index.first { $0.value == studentURL.path }?.key)
            try Data("Değişmiş ham yedek".utf8).write(to: directory.appendingPathComponent(name), options: .atomic)
            do { _ = try await ArchiveSwitchJournal.recoverPendingBeforeStoreOpenAsync(); Issue.record("SHA'sı değişmiş acil ham yedek kabul edilemez") }
            catch is ArchiveSwitchLeaseWorker.Failure { }
            #expect(try Data(contentsOf: studentURL) == crashStudent)
            #expect(try Data(contentsOf: fixture.paths.journalURL) == crashMarker)
            #expect(UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey) == fixture.oldPath)
        }
    }

    @Test func journalEncoderRejectsUnreadableLargeSessionHashIndexAndRoundTripsValidEntries() throws {
        let hashes = Dictionary(uniqueKeysWithValues: (0..<20_000).map { ("session-\($0).json", String(repeating: "a", count: 64)) })
        let large = ArchiveSwitchJournal.Entry(version: 1, token: UUID(), backupDirectory: "/private/backups/test",
            oldPointer: nil, beforeFingerprint: String(repeating: "b", count: 64), backupHashes: hashes,
            phase: .pending, newPointer: nil, emergencyRecovery: true)
        #expect(try JSONEncoder().encode(large).count > ArchiveSwitchJournal.maximumMarkerSize)
        do {
            _ = try ArchiveSwitchJournal.encodeValidatedEntry(large)
            Issue.record("Reader sınırını aşan günlük writer tarafından kabul edilmemeli")
        } catch is ArchiveSwitchLeaseWorker.Failure { }
        let small = ArchiveSwitchJournal.Entry(version: 1, token: large.token, backupDirectory: large.backupDirectory,
            oldPointer: nil, beforeFingerprint: large.beforeFingerprint,
            backupHashes: ["dosya-dizini.json": String(repeating: "c", count: 64)], phase: .pending,
            newPointer: nil, emergencyRecovery: true)
        let encoded = try ArchiveSwitchJournal.encodeValidatedEntry(small)
        #expect(encoded.count <= ArchiveSwitchJournal.maximumMarkerSize)
        #expect(try JSONDecoder().decode(ArchiveSwitchJournal.Entry.self, from: encoded) == small)
    }

    @Test func coldLaunchLinksStayInMemoryAndDispatchOnlyAfterExplicitReadyDrain() {
        let state = DerinBaglanti.shared
        let previousBook = state.bekleyenKitapID, previousAction = state.bekleyenEylem, previousTab = state.hedefSekme
        defer { state.bekleyenKitapID = previousBook; state.bekleyenEylem = previousAction; state.hedefSekme = previousTab }
        state.bekleyenKitapID = nil; state.bekleyenEylem = nil; state.hedefSekme = nil
        let queue = LibraryLaunchLinkQueue(), bookID = UUID()
        queue.enqueue(KitapQR.url(for: bookID))
        #expect(state.bekleyenKitapID == nil && state.hedefSekme == nil)
        queue.enqueue(URL(string: "https://example.invalid/no-route")!)
        #expect(queue.pendingURL == KitapQR.url(for: bookID))
        queue.dispatchPending()
        #expect(state.bekleyenKitapID == bookID && state.hedefSekme == .kitaplar && queue.pendingURL == nil)
        queue.enqueue(URL(string: "kitapbul://ekle/barkod")!)
        queue.enqueue(URL(string: "kitapbul://ekle/gecersiz")!)
        queue.dispatchPending()
        #expect(state.bekleyenEylem == .barkod && state.hedefSekme == .katalog && state.bekleyenKitapID == nil)
        queue.enqueue(URL(string: "kitapbul://asistan")!); queue.dispatchPending()
        #expect(state.hedefSekme == .asistan && state.bekleyenEylem == nil)
    }
}
