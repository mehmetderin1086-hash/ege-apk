import Testing
import Foundation
import SwiftData
@testable import _01

@MainActor
@Suite(.serialized)
struct ArchiveSwitchJournalTestleri {
    private struct Fixture {
        let directory: URL
        let paths: ArchiveSwitchJournal.Paths
        let backup: URL
        let before: ArchiveContents
        let fingerprint: String
        let rawStudent: Data
        let oldStore: ModelContainer
        let oldPath: String
    }
    private func isolated(_ action: (Fixture) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("switch-journal-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oldPaths = ArchiveSwitchJournal.pathsOverride
        let students = StudentStore.directoryOverride, members = MemberStore.directoryOverride
        let history = LoanHistoryStore.directoryOverride, support = ArchiveSettings.directoryOverride
        let sessions = ScanSessionStore.directoryOverride, fields = FieldMaintenanceStore.directoryOverride
        let preferences = ArchiveSettings.snapshot(), pointer = UserDefaults.standard.object(forKey: StoreRecovery.selectedStoreKey)
        let lock = YetkiDurumu.shared.kilitEtkin
        let metadata = directory.appendingPathComponent("metadata", isDirectory: true)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        StudentStore.directoryOverride = metadata; MemberStore.directoryOverride = metadata
        LoanHistoryStore.directoryOverride = metadata; ArchiveSettings.directoryOverride = metadata
        ScanSessionStore.directoryOverride = metadata.appendingPathComponent("sessions"); FieldMaintenanceStore.directoryOverride = nil
        LoanHistoryStore.invalidateCache(); YetkiDurumu.shared.kilitEtkin = false
        for key in ArchiveSettings.allowedKeys { UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.removeObject(forKey: StoreRecovery.selectedStoreKey)
        let paths = ArchiveSwitchJournal.Paths(journalURL: directory.appendingPathComponent("journal.json"),
            backupRoot: directory.appendingPathComponent("backups", isDirectory: true),
            recoveredRoot: directory.appendingPathComponent("stores", isDirectory: true))
        ArchiveSwitchJournal.pathsOverride = paths
        defer {
            ArchiveSwitchJournal.pathsOverride = oldPaths
            StudentStore.directoryOverride = students; MemberStore.directoryOverride = members
            LoanHistoryStore.directoryOverride = history; ArchiveSettings.directoryOverride = support
            ScanSessionStore.directoryOverride = sessions; FieldMaintenanceStore.directoryOverride = fields
            LoanHistoryStore.invalidateCache(); YetkiDurumu.shared.kilitEtkin = lock
            for key in ArchiveSettings.allowedKeys { UserDefaults.standard.removeObject(forKey: key) }
            try? ArchiveSettings.restore(preferences)
            if let pointer { UserDefaults.standard.set(pointer, forKey: StoreRecovery.selectedStoreKey) }
            else { UserDefaults.standard.removeObject(forKey: StoreRecovery.selectedStoreKey) }
            UserDefaults.standard.synchronize()
            try? FileManager.default.removeItem(at: directory)
        }
        let student = Student(name: "Eski öğrenci", number: "101", className: "7-A")
        try StudentStore.replaceAllVerified([student]); UserDefaults.standard.set("Eski okul", forKey: "schoolName")
        let rawStudent = try Data(contentsOf: #require(StudentStore.storageURL))
        let before = ArchiveContents(books: [Book(title: "Eski eser", author: "Y")], students: [student], settings: ArchiveSettings.snapshot())
        try FileManager.default.createDirectory(at: paths.recoveredRoot, withIntermediateDirectories: true)
        let oldURL = paths.recoveredRoot.appendingPathComponent("old.store")
        let oldStore = try ArchiveLoanRestorer.buildRecoveryStore(contents: before, at: oldURL)
        UserDefaults.standard.set(oldURL.path, forKey: StoreRecovery.selectedStoreKey)
        let backup = paths.backupRoot.appendingPathComponent("switch-test", isDirectory: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try FullArchive.buildVerified(before).write(to: backup.appendingPathComponent("Islem-Oncesi-Tam-Arsiv.zip"), options: .atomic)
        try ArchiveImportCoordinator.captureRawMetadata(at: backup)
        let report = "Ayrı katalog açma: dogrulandi\n" + (1...12).map { "Kapsam \($0): önce 1, seçilen arşiv 2, yeni katalog 2" }.joined(separator: "\n")
        try Data(report.utf8).write(to: backup.appendingPathComponent("Katalog-Gecisi-Kapsam.txt"))
        let fixture = Fixture(directory: directory, paths: paths, backup: backup, before: before,
            fingerprint: try ArchiveImportCoordinator.fingerprint(before), rawStudent: rawStudent,
            oldStore: oldStore, oldPath: oldURL.path)
        try action(fixture)
        withExtendedLifetime(oldStore) {}
    }
    private func begin(_ fixture: Fixture) throws -> UUID {
        try ArchiveSwitchJournal.begin(backupDirectory: fixture.backup,
            oldPointer: UserDefaults.standard.object(forKey: StoreRecovery.selectedStoreKey), beforeFingerprint: fixture.fingerprint)
    }
    private func changedMetadata() throws {
        try StudentStore.replaceAllVerified([Student(name: "Yeni öğrenci", number: "202", className: "8-B")])
        UserDefaults.standard.set("Yeni okul", forKey: "schoolName")
    }
    private func newStore(_ fixture: Fixture) throws -> (ModelContainer, String) {
        let path = fixture.paths.recoveredRoot.appendingPathComponent(UUID().uuidString + ".store")
        return (try ArchiveLoanRestorer.buildRecoveryStore(contents: ArchiveContents(books: [Book(title: "Yeni eser", author: "Y")]), at: path), path.path)
    }

    @Test func metadataYazildiIsaretciEskiKaldiRolKilitliykenSistemGeriAlir() throws {
        try isolated { fixture in
            let token = try begin(fixture)
            try changedMetadata()
            YetkiDurumu.shared.kilitEtkin = true; YetkiDurumu.shared.gorevliyeGec()
            let recovered = try ArchiveSwitchJournal.recoverPendingBeforeStoreOpen()
            let result = try #require(recovered)
            #expect(result.token == token && result.phase == .pending)
            #expect(try Data(contentsOf: #require(StudentStore.storageURL)) == fixture.rawStudent)
            #expect(UserDefaults.standard.string(forKey: "schoolName") == "Eski okul")
            #expect(UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey) == fixture.oldPath)
            #expect(!YetkiDurumu.shared.yonetici && YetkiDurumu.shared.kilitEtkin)
            let report = try String(contentsOf: fixture.backup.appendingPathComponent("Katalog-Gecisi-Kapsam.txt"), encoding: .utf8)
            #expect(report.hasPrefix("Ayrı katalog açma: geri_alindi\n"))
            #expect(report.split(separator: "\n").dropFirst().count == 12)
            #expect(try ArchiveSwitchJournal.recoverPendingBeforeStoreOpen() == nil)
            #expect(try fixture.oldStore.mainContext.fetch(FetchDescriptor<CatalogBook>()).map(\.id) == fixture.before.books.map(\.id))
            #expect(FileManager.default.fileExists(atPath: fixture.backup.appendingPathComponent("Islem-Oncesi-Tam-Arsiv.zip").path))
        }
    }

    @Test func yeniIsaretciYazildiCommitMarkerYokEskiMetadataVePointerDoner() throws {
        try isolated { fixture in
            _ = try begin(fixture); let (store, newPath) = try newStore(fixture)
            try changedMetadata(); UserDefaults.standard.set(newPath, forKey: StoreRecovery.selectedStoreKey)
            try ArchiveSwitchJournal.recoverPendingBeforeStoreOpen()
            #expect(UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey) == fixture.oldPath)
            #expect(try Data(contentsOf: #require(StudentStore.storageURL)) == fixture.rawStudent)
            #expect(!FileManager.default.fileExists(atPath: fixture.paths.journalURL.path))
            #expect(try ArchiveSwitchJournal.recoverPendingBeforeStoreOpen() == nil)
            withExtendedLifetime(store) {}
        }
    }

    @Test func varsayilanKatalogunNilPointeriAyniSekildeGeriGelir() throws {
        try isolated { fixture in
            UserDefaults.standard.removeObject(forKey: StoreRecovery.selectedStoreKey)
            _ = try ArchiveSwitchJournal.begin(backupDirectory: fixture.backup, oldPointer: nil, beforeFingerprint: fixture.fingerprint)
            let (store, newPath) = try newStore(fixture)
            try changedMetadata(); UserDefaults.standard.set(newPath, forKey: StoreRecovery.selectedStoreKey)
            try ArchiveSwitchJournal.recoverPendingBeforeStoreOpen()
            #expect(UserDefaults.standard.object(forKey: StoreRecovery.selectedStoreKey) == nil)
            #expect(try Data(contentsOf: #require(StudentStore.storageURL)) == fixture.rawStudent)
            withExtendedLifetime(store) {}
        }
    }

    @Test func committedMarkerEskiDefaultsDiskDegeriniYeniDepoyaTutarliKurur() throws {
        try isolated { fixture in
            let token = try begin(fixture), (store, newPath) = try newStore(fixture)
            try changedMetadata(); UserDefaults.standard.set(newPath, forKey: StoreRecovery.selectedStoreKey)
            try ArchiveSwitchJournal.markCommitted(token: token, newPath: newPath)
            // Process sınırı taklidi: marker kalıcı, defaults eski disk değerini döndürüyor.
            UserDefaults.standard.set(fixture.oldPath, forKey: StoreRecovery.selectedStoreKey)
            let recovered = try ArchiveSwitchJournal.recoverPendingBeforeStoreOpen()
            let result = try #require(recovered)
            #expect(result.phase == .committed && result.token == token)
            #expect(UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey) == newPath)
            #expect(try StudentStore.allVerified().first?.number == "202")
            #expect(UserDefaults.standard.string(forKey: "schoolName") == "Yeni okul")
            #expect(try StoreRecovery.validatedSelectedStoreURL()?.path == newPath)
            #expect(!FileManager.default.fileExists(atPath: fixture.paths.journalURL.path))
            withExtendedLifetime(store) {}
        }
    }

    @Test func yarimGeriAlmaHatasiMarkerKorurTekrarGeriAlmaIdempotenttir() throws {
        try isolated { fixture in
            _ = try begin(fixture); let (store, newPath) = try newStore(fixture)
            try changedMetadata(); UserDefaults.standard.set(newPath, forKey: StoreRecovery.selectedStoreKey)
            let studentURL = try #require(StudentStore.storageURL)
            try FileManager.default.removeItem(at: studentURL)
            try FileManager.default.createDirectory(at: studentURL, withIntermediateDirectories: true)
            #expect(throws: (any Error).self) { try ArchiveSwitchJournal.recoverPendingBeforeStoreOpen() }
            #expect(FileManager.default.fileExists(atPath: fixture.paths.journalURL.path))
            #expect(UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey) == newPath)
            try FileManager.default.removeItem(at: studentURL)
            try ArchiveSwitchJournal.recoverPendingBeforeStoreOpen()
            #expect(try Data(contentsOf: studentURL) == fixture.rawStudent)
            #expect(UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey) == fixture.oldPath)
            #expect(try ArchiveSwitchJournal.recoverPendingBeforeStoreOpen() == nil)
            withExtendedLifetime(store) {}
        }
    }

    @Test func degismisHamYedekVeBozukJournalKatalogAcilisiniKapaliTutar() throws {
        try isolated { fixture in
            _ = try begin(fixture); try changedMetadata()
            let index = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: fixture.backup.appendingPathComponent("dosya-dizini.json")))
            let original = try #require(index.keys.first { $0.hasSuffix("Ogrenciler.json") })
            try Data("[]".utf8).write(to: fixture.backup.appendingPathComponent(original), options: .atomic)
            #expect(throws: SchoolLibraryService.OperationError.self) { try ArchiveSwitchJournal.recoverPendingBeforeStoreOpen() }
            #expect(try StudentStore.allVerified().first?.number == "202")
            #expect(FileManager.default.fileExists(atPath: fixture.paths.journalURL.path))
            try Data("bozuk".utf8).write(to: fixture.paths.journalURL, options: .atomic)
            #expect(throws: (any Error).self) { try ArchiveSwitchJournal.recoverPendingBeforeStoreOpen() }
            #expect(try StudentStore.allVerified().first?.number == "202")
        }
    }

    @Test func bekleyenGecisBagimsizKurtarmayiVeDogrulanmamisMarkerTemizliginiReddeder() throws {
        try isolated { fixture in
            let token = try begin(fixture); try changedMetadata()
            #expect(throws: SchoolLibraryService.OperationError.self) { try ArchiveSwitchJournal.prepareForIndependentRestore() }
            #expect(throws: SchoolLibraryService.OperationError.self) { try ArchiveSwitchJournal.finishRollback(token: token) }
            #expect(FileManager.default.fileExists(atPath: fixture.paths.journalURL.path))
            try ArchiveSwitchJournal.recoverPendingBeforeStoreOpen()
        }
    }

    @Test func tamamlanmisMarkerYeniBagimsizKurtarmaninPointeriniGeriCeviremez() throws {
        try isolated { fixture in
            let token = try begin(fixture), (store, newPath) = try newStore(fixture)
            try changedMetadata(); UserDefaults.standard.set(newPath, forKey: StoreRecovery.selectedStoreKey)
            try ArchiveSwitchJournal.markCommitted(token: token, newPath: newPath)
            try ArchiveSwitchJournal.prepareForIndependentRestore()
            let (independent, independentPath) = try newStore(fixture)
            UserDefaults.standard.set(independentPath, forKey: StoreRecovery.selectedStoreKey)
            #expect(try ArchiveSwitchJournal.recoverPendingBeforeStoreOpen() == nil)
            #expect(UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey) == independentPath)
            withExtendedLifetime(store) {}; withExtendedLifetime(independent) {}
        }
    }

    @Test func gecersizPointerTipiDisDizinVeYanlisTokenCanliMetadataYazamaz() throws {
        try isolated { fixture in
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try ArchiveSwitchJournal.begin(backupDirectory: fixture.backup, oldPointer: 42, beforeFingerprint: fixture.fingerprint)
            }
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try ArchiveSwitchJournal.begin(backupDirectory: fixture.directory, oldPointer: nil, beforeFingerprint: fixture.fingerprint)
            }
            let token = try begin(fixture)
            #expect(throws: SchoolLibraryService.OperationError.self) { try ArchiveSwitchJournal.requirePending(token: UUID()) }
            try ArchiveSwitchJournal.requirePending(token: token)
            #expect(try Data(contentsOf: #require(StudentStore.storageURL)) == fixture.rawStudent)
            try ArchiveSwitchJournal.recoverPendingBeforeStoreOpen()
        }
    }

    @Test func raporYazimiBasarisizsaGeriAlinanKapsamdaMarkerKalirTekrarDuzelir() throws {
        try isolated { fixture in
            _ = try begin(fixture); try changedMetadata()
            let report = fixture.backup.appendingPathComponent("Katalog-Gecisi-Kapsam.txt")
            let contents = try Data(contentsOf: report)
            try FileManager.default.removeItem(at: report)
            #expect(throws: (any Error).self) { try ArchiveSwitchJournal.recoverPendingBeforeStoreOpen() }
            #expect(FileManager.default.fileExists(atPath: fixture.paths.journalURL.path))
            #expect(try Data(contentsOf: #require(StudentStore.storageURL)) == fixture.rawStudent)
            try contents.write(to: report)
            try ArchiveSwitchJournal.recoverPendingBeforeStoreOpen()
            #expect(try String(contentsOf: report, encoding: .utf8).hasPrefix("Ayrı katalog açma: geri_alindi"))
            #expect(!FileManager.default.fileExists(atPath: fixture.paths.journalURL.path))
        }
    }

    @Test func bozukMarkerAcilKurtarmadaBasarisizlikBoyuncaAyniHamBaytlarlaKalir() throws {
        try isolated { fixture in
            _ = try begin(fixture)
            let original = Data("bozuk-eski-marker".utf8)
            try original.write(to: fixture.paths.journalURL, options: .atomic)
            let selected = ArchiveContents(books: [Book(title: "Kurtarılacak", author: "Y")], students: [Student(name: "Seçilen", number: "303")])
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try StoreRecovery.restore(selected, allowFailedSwitchRecovery: true) { _ in
                    #expect(try Data(contentsOf: fixture.paths.journalURL) == original)
                    throw SchoolLibraryService.OperationError(message: "Kurtarma doğrulama hatası")
                }
            }
            #expect(try Data(contentsOf: fixture.paths.journalURL) == original)
            #expect(try Data(contentsOf: #require(StudentStore.storageURL)) == fixture.rawStudent)
            #expect(UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey) == fixture.oldPath)
            let forensic = try #require(FileManager.default.contentsOfDirectory(at: fixture.paths.backupRoot, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("emergency-") })
            #expect(try Data(contentsOf: forensic.appendingPathComponent("Onceki-Gecis-Gunlugu.bin")) == original)
            #expect(try FullArchive.readValidated(from: forensic.appendingPathComponent("Secilen-Dogrulanmis-Arsiv.zip")).books.map(\.id) == selected.books.map(\.id))
        }
    }

    @Test func admininDogrulanmisArsiviBozukMarkerdenCikisSaglarCommitOncePointerDiskSorununuToparlar() throws {
        try isolated { fixture in
            _ = try begin(fixture)
            let original = Data("bozuk-eski-marker".utf8)
            try original.write(to: fixture.paths.journalURL, options: .atomic)
            let selected = ArchiveContents(books: [Book(title: "Kurtarılan", author: "Y")], students: [Student(name: "Seçilen", number: "303")])
            let restored = try StoreRecovery.restore(selected, allowFailedSwitchRecovery: true)
            let newPath = try #require(UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey))
            #expect(try StudentStore.allVerified() == selected.students)
            let entry = try JSONDecoder().decode(ArchiveSwitchJournal.Entry.self, from: Data(contentsOf: fixture.paths.journalURL))
            #expect(entry.phase == .committed && entry.emergencyRecovery == true)
            let forensic = URL(fileURLWithPath: entry.backupDirectory).appendingPathComponent("Onceki-Gecis-Gunlugu.bin")
            #expect(try Data(contentsOf: forensic) == original)
            // Bozuk eski pointer diskten geri gelmiş olsa bile explicit admin
            // recovery'nin dayanıklı committed yeni path'i tek yetkili kaynaktır.
            UserDefaults.standard.set(42, forKey: StoreRecovery.selectedStoreKey)
            let recovered = try ArchiveSwitchJournal.recoverPendingBeforeStoreOpen()
            let recovery = try #require(recovered)
            #expect(recovery.phase == .committed)
            #expect(UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey) == newPath)
            #expect(try restored.mainContext.fetch(FetchDescriptor<CatalogBook>()).map(\.id) == selected.books.map(\.id))
            #expect(try StudentStore.allVerified() == selected.students)
            #expect(FileManager.default.fileExists(atPath: forensic.path))
        }
    }

    @Test func acilCikisYoneticiVeDogrulanmisSecimOlmadanMarkerSilemez() throws {
        try isolated { fixture in
            _ = try begin(fixture)
            let original = Data("bozuk-eski-marker".utf8)
            try original.write(to: fixture.paths.journalURL, options: .atomic)
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try ArchiveSwitchJournal.prepareForIndependentRestore(allowFailedSwitchRecovery: true)
            }
            YetkiDurumu.shared.kilitEtkin = true; YetkiDurumu.shared.gorevliyeGec()
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try ArchiveSwitchJournal.prepareForIndependentRestore(allowFailedSwitchRecovery: true, verifiedRecoveryContents: ArchiveContents(books: [Book(title: "A", author: "Y")]))
            }
            #expect(try Data(contentsOf: fixture.paths.journalURL) == original)
            #expect(!YetkiDurumu.shared.yonetici)
        }
    }
}
