import Foundation
import CryptoKit
import Darwin

/// Metadata ve seçilmiş DB işaretçisi ayrı kalıcı depolardır. Açılış, yarım bir
/// geçiş varsa eski metadata geri gelmeden hiçbir ModelContainer açamaz.
@MainActor
enum ArchiveSwitchJournal {
    nonisolated struct Paths: Sendable, Equatable {
        let journalURL: URL
        let backupRoot: URL
        let recoveredRoot: URL
    }
    /// Yalnız izole testler gerçek Application Support günlüğünden ayrılır.
    static var pathsOverride: Paths?
    nonisolated static let maximumMarkerSize = 1_048_576

    static func backupRoot() throws -> URL { try paths().backupRoot }

    nonisolated enum Phase: String, Codable, Sendable { case pending, committed }
    nonisolated struct Entry: Codable, Equatable, Sendable {
        let version: Int
        let token: UUID
        let backupDirectory: String
        let oldPointer: String?
        let beforeFingerprint: String
        let backupHashes: [String: String]
        var phase: Phase
        var newPointer: String?
        var emergencyRecovery: Bool? = nil
    }
    struct RecoveryResult {
        let token: UUID
        let backupURL: URL
        let phase: Phase
    }
    /// Başka bir kaynak dosyası keyfi bir sistem geri alma izni üretemez.
    struct RecoveryPermit {
        fileprivate let token: UUID
        fileprivate let backupDirectory: String
        fileprivate init(token: UUID, backupDirectory: String) {
            self.token = token; self.backupDirectory = backupDirectory
        }
    }
    struct EmergencyRecovery {
        fileprivate let token: UUID
        fileprivate let directory: URL
        fileprivate let originalMarkerHash: String
        fileprivate let selectedFingerprint: String
        fileprivate let selectedArchiveHash: String
        fileprivate init(token: UUID, directory: URL, originalMarkerHash: String, selectedFingerprint: String, selectedArchiveHash: String) {
            self.token = token; self.directory = directory; self.originalMarkerHash = originalMarkerHash
            self.selectedFingerprint = selectedFingerprint; self.selectedArchiveHash = selectedArchiveHash
        }
    }

    /// Yalnız Journal oluşturabilir: SHA/ZIP doğrulaması işçide yapılmış özel
    /// dosyaların immutable proof'u ve pending markerın dosya kimliği taşınır.
    nonisolated struct CommitLease: Sendable {
        fileprivate let entry: Entry
        fileprivate let paths: Paths
        fileprivate let proof: ArchiveSwitchLeaseWorker.Proof
        fileprivate let marker: ArchiveSwitchLeaseWorker.FileSeal
    }

    /// Ağır disk/ZIP çalışması pending marker yazılmadan önce biter. Ardından
    /// caller'ın canlı değer denetimi ve bütün global commit senkron MainActor
    /// callback'te çalışır; pending yazımı ile metadata commit arasında await yoktur.
    static func beginAndCommitAsync<Result>(backupDirectory: URL, oldPointer: Any?,
        beforeFingerprint: String,
        beforeBegin: @MainActor () throws -> Void,
        commit: @MainActor (UUID, CommitLease) throws -> Result) async throws -> Result {
        let capturedPaths = try paths()
        let pointer = try checkedPointer(oldPointer, paths: capturedPaths, requireFile: oldPointer != nil)
        let directory = try checkedBackupDirectory(backupDirectory, paths: capturedPaths)
        guard validHash(beforeFingerprint) else { throw failure("Önceki katalog kapsam damgası geçersiz; geçiş başlamadı.") }
        let oldMarker = try asyncMarkerSnapshot(paths: capturedPaths)
        if oldMarker != nil {
            let existing = try readEntry(paths: capturedPaths)
            guard existing.phase == .committed, existing.newPointer == pointer else {
                throw failure("Önceki katalog geçişi tamamlanmamış; yeni geçiş başlamadı.")
            }
            _ = try checkedPointer(existing.newPointer, paths: capturedPaths, requireFile: true)
        }
        guard try checkedPointer(UserDefaults.standard.object(forKey: StoreRecovery.selectedStoreKey),
            paths: capturedPaths, requireFile: pointer != nil) == pointer else {
            throw failure("Geçiş hazırlığındaki canlı depo işaretçisi değişmiş.")
        }
        let proof = try await Task.detached(priority: .utility) {
            try ArchiveSwitchLeaseWorker.verify(directory: directory, backupRoot: capturedPaths.backupRoot,
                                                beforeFingerprint: beforeFingerprint)
        }.value
        try Task.checkCancellation()
        func preflight() throws {
            guard try paths() == capturedPaths,
                  try asyncMarkerSnapshot(paths: capturedPaths) == oldMarker,
                  try checkedPointer(UserDefaults.standard.object(forKey: StoreRecovery.selectedStoreKey),
                    paths: capturedPaths, requireFile: pointer != nil) == pointer else {
                throw failure("İşçi doğrulaması sırasında geçiş günlüğü, yollar veya canlı depo işaretçisi değişmiş.")
            }
            if oldMarker != nil {
                let existing = try readEntry(paths: capturedPaths)
                guard existing.phase == .committed, existing.newPointer == pointer else {
                    throw failure("İşçi doğrulamasından sonra önceki geçiş günlüğü değişmiş.")
                }
            }
            try proof.validateCurrent(backupRoot: capturedPaths.backupRoot)
        }
        try preflight()
        // Bu callback canlı context/JSON/ayar snapshot'ını eldeki before değeriyle
        // karşılaştırır; stale ise marker ve global dosyalara hiç dokunulmaz.
        try beforeBegin()
        try preflight()
        let token = UUID()
        let entry = Entry(version: 1, token: token, backupDirectory: proof.directory.path, oldPointer: pointer,
                          beforeFingerprint: beforeFingerprint, backupHashes: proof.hashes, phase: .pending, newPointer: nil)
        try write(entry, paths: capturedPaths)
        let lease = CommitLease(entry: entry, paths: capturedPaths, proof: proof,
                                marker: try ArchiveSwitchLeaseWorker.FileSeal.capture(capturedPaths.journalURL))
        return try commit(token, lease)
    }

    static func requirePending(token: UUID, lease: CommitLease) throws {
        try validateLease(token: token, lease: lease)
        guard try checkedPointer(UserDefaults.standard.object(forKey: StoreRecovery.selectedStoreKey),
            paths: lease.paths, requireFile: lease.entry.oldPointer != nil) == lease.entry.oldPointer else {
            throw failure("Metadata commit öncesindeki eski depo işaretçisi değişmiş.")
        }
    }

    static func markCommitted(token: UUID, newPath: String, lease: CommitLease) throws {
        try validateLease(token: token, lease: lease)
        let pointer = try checkedPointer(newPath, paths: lease.paths, requireFile: true)
        guard pointer != nil, try checkedPointer(UserDefaults.standard.object(forKey: StoreRecovery.selectedStoreKey),
            paths: lease.paths, requireFile: true) == pointer else {
            throw failure("Yeni depo işaretçisi doğrulanmadı; katalog yayınlanmadı.")
        }
        var entry = lease.entry
        entry.phase = .committed; entry.newPointer = pointer
        try write(entry, paths: lease.paths)
    }

    /// Hata yolunda özel yedek ZIP yeniden çözülmez. Caller gerçek ham metadata
    /// rollback yaptıktan sonra byte eşitliği ve eski pointer yine doğrulanır.
    static func finishRollback(token: UUID, lease: CommitLease) throws {
        try requirePending(token: token, lease: lease)
        try verifyRawRestoration(directory: lease.proof.directory)
        guard UserDefaults.standard.synchronize() else { throw failure("Önceki depo işaretçisi diske yazılamadı; geçiş günlüğü korundu.") }
        try FileManager.default.removeItem(at: lease.paths.journalURL)
    }

    private static func validateLease(token: UUID, lease: CommitLease) throws {
        guard lease.entry.token == token, lease.entry.phase == .pending,
              try paths() == lease.paths else { throw failure("Doğrulanmış geçiş izni bu işleme/yollara ait değil.") }
        try lease.marker.validateCurrent()
        guard try readEntry(paths: lease.paths) == lease.entry else {
            throw failure("Doğrulanmış geçiş izninden sonra pending günlük değişmiş.")
        }
        try lease.proof.validateCurrent(backupRoot: lease.paths.backupRoot)
    }

    private static func asyncMarkerSnapshot(paths: Paths) throws -> Data? {
        guard FileManager.default.fileExists(atPath: paths.journalURL.path) else { return nil }
        let seal = try ArchiveSwitchLeaseWorker.FileSeal.capture(paths.journalURL)
        guard seal.size <= UInt64(maximumMarkerSize) else { throw failure("Geçiş günlüğü güvenli okuma sınırını aşıyor; korunuyor.") }
        let data = try Data(contentsOf: paths.journalURL)
        try seal.validateCurrent()
        return data
    }

    static func begin(backupDirectory: URL, oldPointer: Any?, beforeFingerprint: String) throws -> UUID {
        let paths = try paths()
        let pointer = try checkedPointer(oldPointer, paths: paths, requireFile: oldPointer != nil)
        let directory = try checkedBackupDirectory(backupDirectory, paths: paths)
        guard validHash(beforeFingerprint) else { throw failure("Önceki katalog kapsam damgası geçersiz; geçiş başlamadı.") }
        if FileManager.default.fileExists(atPath: paths.journalURL.path) {
            let existing = try readEntry(paths: paths)
            guard existing.phase == .committed, existing.newPointer == pointer else {
                throw failure("Önceki katalog geçişi tamamlanmamış. Uygulamayı yeniden açıp kurtarma sonucunu bekleyin.")
            }
            // İki geçiş aynı oturumda yapılabilir: tamamlanan eski marker, yeni
            // pending marker ile atomik olarak değiştirilir; korumasız boşluk yoktur.
            _ = try checkedPointer(existing.newPointer, paths: paths, requireFile: true)
        }
        let indexURL = directory.appendingPathComponent("dosya-dizini.json")
        let index = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: indexURL))
        let names = Set(index.keys).union(["dosya-dizini.json", "onceki-ayarlar.json", "Islem-Oncesi-Tam-Arsiv.zip"])
        var hashes: [String: String] = [:]
        for name in names { hashes[name] = digest(try backupFile(name, directory: directory)) }
        let previous = try FullArchive.readValidated(data: backupFile("Islem-Oncesi-Tam-Arsiv.zip", directory: directory))
        guard try ArchiveImportCoordinator.fingerprint(previous) == beforeFingerprint else {
            throw failure("Kalıcı geçiş günlüğünün tam yedeği önceki katalogla aynı değil.")
        }
        _ = try JSONDecoder().decode([String: Data].self, from: backupFile("onceki-ayarlar.json", directory: directory))
        let token = UUID()
        try write(Entry(version: 1, token: token, backupDirectory: directory.path, oldPointer: pointer,
                        beforeFingerprint: beforeFingerprint, backupHashes: hashes, phase: .pending, newPointer: nil), paths: paths)
        return token
    }

    /// Bu kayıt UI yayınından önce, bütün depo/metadata doğrulamalarından sonra
    /// yazılır. Yeni path disk üzerinde dayanıklıdır; UserDefaults gecikse de açılış
    /// bunu yeniden kurar. Runtime markerı silmez: pointer disk yarışı oluşamaz.
    static func markCommitted(token: UUID, newPath: String) throws {
        let paths = try paths()
        var entry = try readEntry(paths: paths)
        guard entry.token == token, entry.phase == .pending else { throw failure("Katalog geçişi günlüğü beklenen işleme ait değil.") }
        _ = try verifiedBackup(entry, paths: paths)
        let pointer = try checkedPointer(newPath, paths: paths, requireFile: true)
        guard pointer != nil, try checkedPointer(UserDefaults.standard.object(forKey: StoreRecovery.selectedStoreKey), paths: paths, requireFile: true) == pointer else {
            throw failure("Yeni depo işaretçisi doğrulanmadı; katalog yayınlanmadı.")
        }
        entry.phase = .committed; entry.newPointer = pointer
        try write(entry, paths: paths)
    }

    static func requirePending(token: UUID) throws {
        let paths = try paths(), entry = try readEntry(paths: paths)
        guard entry.token == token, entry.phase == .pending else {
            throw failure("Depo kurtarması bekleyen katalog geçişine ait değil.")
        }
        _ = try verifiedBackup(entry, paths: paths)
    }

    /// Başlangıçtaki doğrudan Veri Kurtarma yolu eski committed markerı tekrar
    /// kullanamaz. Yeni katalog metadata yazımından önce güvenli marker temizlenir.
    @discardableResult
    static func prepareForIndependentRestore(allowFailedSwitchRecovery: Bool = false, verifiedRecoveryContents: ArchiveContents? = nil) throws -> EmergencyRecovery? {
        let paths = try paths()
        guard FileManager.default.fileExists(atPath: paths.journalURL.path) else { return nil }
        if allowFailedSwitchRecovery {
            try SchoolLibraryService.requireAdmin()
            guard let verifiedRecoveryContents else { throw failure("Yarım geçişten çıkış için seçilen doğrulanmış arşiv gerekli.") }
            let archive = try FullArchive.buildVerified(verifiedRecoveryContents)
            let selected = try FullArchive.readValidated(data: archive)
            let marker = try Data(contentsOf: paths.journalURL)
            guard marker.count <= 1_048_576 else { throw failure("Bozuk geçiş günlüğü güvenli kurtarma sınırını aşıyor; dosya korunuyor.") }
            let token = UUID()
            let directory = paths.backupRoot.appendingPathComponent("emergency-" + token.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try marker.write(to: directory.appendingPathComponent("Onceki-Gecis-Gunlugu.bin"), options: .atomic)
            try archive.write(to: directory.appendingPathComponent("Secilen-Dogrulanmis-Arsiv.zip"), options: .atomic)
            guard try Data(contentsOf: directory.appendingPathComponent("Onceki-Gecis-Gunlugu.bin")) == marker,
                  try Data(contentsOf: directory.appendingPathComponent("Secilen-Dogrulanmis-Arsiv.zip")) == archive else {
                throw failure("Acil kurtarma öncesi günlük ve seçilen arşiv kopyası doğrulanamadı; hiçbir marker silinmedi.")
            }
            // Eski marker burada değiştirilmez. Yazım/kill sırasında açılış yine
            // failclosed kalır; yalnız doğrulanmış yeni depo bunu tamamlayabilir.
            return EmergencyRecovery(token: token, directory: directory.standardizedFileURL.resolvingSymlinksInPath(),
                originalMarkerHash: digest(marker), selectedFingerprint: try ArchiveImportCoordinator.fingerprint(selected), selectedArchiveHash: digest(archive))
        }
        let entry = try readEntry(paths: paths)
        guard entry.phase == .committed,
              let newPath = try checkedPointer(entry.newPointer, paths: paths, requireFile: true),
              try checkedPointer(UserDefaults.standard.object(forKey: StoreRecovery.selectedStoreKey), paths: paths, requireFile: true) == newPath else {
            throw failure("Bekleyen katalog geçişi varken bağımsız kurtarma başlayamaz. Uygulamayı yeniden açın.")
        }
        guard UserDefaults.standard.synchronize() else { throw failure("Doğrulanmış depo işaretçisi kalıcılaştırılamadı; geçiş günlüğü korundu.") }
        try FileManager.default.removeItem(at: paths.journalURL)
        return nil
    }

    /// Adminin açıkça seçtiği doğrulanmış ZIP kurtarması bütün DB/metadata
    /// kapılarını geçmiştir. Eski bozuk marker ham forensic kopyasında korunur.
    /// Commit pointer yazımından önce yapılır; crash olursa açılış yeni path'i kurar.
    static func commitEmergencyRecovery(_ recovery: EmergencyRecovery, newPath: String) throws {
        try SchoolLibraryService.requireAdmin()
        let paths = try paths(), directory = try checkedBackupDirectory(recovery.directory, paths: paths)
        guard digest(try Data(contentsOf: paths.journalURL)) == recovery.originalMarkerHash,
              digest(try backupFile("Onceki-Gecis-Gunlugu.bin", directory: directory)) == recovery.originalMarkerHash,
              digest(try backupFile("Secilen-Dogrulanmis-Arsiv.zip", directory: directory)) == recovery.selectedArchiveHash else {
            throw failure("Kurtarma sırasında eski geçiş günlüğü veya seçilen arşiv değişmiş; yeni katalog etkinleştirilmedi.")
        }
        let pointer = try checkedPointer(newPath, paths: paths, requireFile: true)
        guard pointer != nil else { throw failure("Acil kurtarmanın yeni deposu bulunamadı.") }
        let selected = try FullArchive.readValidated(data: backupFile("Secilen-Dogrulanmis-Arsiv.zip", directory: directory))
        guard try ArchiveImportCoordinator.fingerprint(selected) == recovery.selectedFingerprint else { throw failure("Acil kurtarmanın seçili arşiv kapsamı değişmiş.") }
        let oldPointer = try? checkedPointer(UserDefaults.standard.object(forKey: StoreRecovery.selectedStoreKey), paths: paths, requireFile: false)
        try write(Entry(version: 1, token: recovery.token, backupDirectory: directory.path, oldPointer: oldPointer,
            beforeFingerprint: recovery.selectedFingerprint,
            backupHashes: ["Onceki-Gecis-Gunlugu.bin": recovery.originalMarkerHash, "Secilen-Dogrulanmis-Arsiv.zip": recovery.selectedArchiveHash],
            phase: .committed, newPointer: pointer, emergencyRecovery: true), paths: paths)
    }

    static func recoveredStoreRoot() throws -> URL { try paths().recoveredRoot }

    /// Normal catch yolu metadata/pointer kapsamını doğruladıktan sonra çağırır.
    /// Bu fonksiyon eski metadata doğrulamasını atlayarak marker temizleyemez.
    static func finishRollback(token: UUID) throws {
        let paths = try paths()
        let entry = try readEntry(paths: paths)
        guard entry.token == token, entry.phase == .pending else { throw failure("Geri alma günlüğü beklenen işleme ait değil.") }
        let directory = try verifiedBackup(entry, paths: paths)
        try verifyRawRestoration(directory: directory)
        guard try checkedPointer(UserDefaults.standard.object(forKey: StoreRecovery.selectedStoreKey), paths: paths, requireFile: entry.oldPointer != nil) == entry.oldPointer else {
            throw failure("Önceki depo işaretçisi geri alınmamış; geçiş günlüğü korundu.")
        }
        guard UserDefaults.standard.synchronize() else { throw failure("Önceki depo işaretçisi diske yazılamadı; geçiş günlüğü korundu.") }
        try FileManager.default.removeItem(at: paths.journalURL)
    }

    /// MyApp.init içinde, selectedStoreURL/makeContainer/global defter okumalarından
    /// önce çağrılır. Rol kilidi değişmez; yalnız doğrulanmış pending işleme geri alınır.
    @discardableResult
    static func recoverPendingBeforeStoreOpen() throws -> RecoveryResult? {
        let paths = try paths()
        guard FileManager.default.fileExists(atPath: paths.journalURL.path) else { return nil }
        let entry = try readEntry(paths: paths)
        if entry.phase == .committed {
            let newPointer = try checkedPointer(entry.newPointer, paths: paths, requireFile: true)
            guard let newPointer else { throw failure("Tamamlanan katalog geçişinin yeni deposu eksik; boş katalog açılmadı.") }
            if entry.emergencyRecovery != true {
                let current = try checkedPointer(UserDefaults.standard.object(forKey: StoreRecovery.selectedStoreKey), paths: paths, requireFile: false)
                guard current == entry.oldPointer || current == newPointer else {
                    throw failure("Tamamlanan katalog geçişi ile depo işaretçisi çelişiyor; katalog açılmadı.")
                }
            }
            UserDefaults.standard.set(newPointer, forKey: StoreRecovery.selectedStoreKey)
            guard UserDefaults.standard.synchronize() else { throw failure("Yeni depo işaretçisi kalıcılaştırılamadı; doğrulanmış geçiş günlüğü korundu.") }
            try FileManager.default.removeItem(at: paths.journalURL)
        } else {
            guard entry.emergencyRecovery != true else {
                throw failure("Yarım acil kurtarma ham doğrulaması için güvenli asenkron açılış gereklidir; katalog kapalı kaldı.")
            }
            let directory = try verifiedBackup(entry, paths: paths)
            let permit = RecoveryPermit(token: entry.token, backupDirectory: directory.path)
            try StoreRecovery.rollbackMetadataForInterruptedSwitch(from: directory, permit: permit)
            try verifyRawRestoration(directory: directory)
            if let oldPointer = entry.oldPointer { UserDefaults.standard.set(oldPointer, forKey: StoreRecovery.selectedStoreKey) }
            else { UserDefaults.standard.removeObject(forKey: StoreRecovery.selectedStoreKey) }
            try recordRecoveredRollback(directory: directory)
            try finishRollback(token: entry.token)
        }
        return RecoveryResult(token: entry.token,
            backupURL: URL(fileURLWithPath: entry.backupDirectory).appendingPathComponent(entry.emergencyRecovery == true ? "Secilen-Dogrulanmis-Arsiv.zip" : "Islem-Oncesi-Tam-Arsiv.zip"), phase: entry.phase)
    }

    /// StoreRecovery'nin internal sistem geri alma kapısı bunu yeniden doğrular.
    static func validateRecoveryPermit(_ permit: RecoveryPermit, backupDirectory: URL) throws {
        let paths = try paths(), entry = try readEntry(paths: paths)
        guard entry.phase == .pending, entry.token == permit.token,
              entry.backupDirectory == permit.backupDirectory,
              backupDirectory.standardizedFileURL.resolvingSymlinksInPath().path == permit.backupDirectory else {
            throw failure("Sistem geri alma izni bu kalıcı geçişe ait değil.")
        }
        _ = try verifiedBackup(entry, paths: paths)
    }

    /// Yarım ya da tamamlanmış ama temizlenmemiş bir geçiş günlüğü var mı? Siri ve arka plan görevleri
    /// kurtarmayı kendileri yürütmez; var ise kullanıcıdan uygulamayı açmasını ister.
    static func hasMarker() -> Bool {
        guard let paths = try? paths() else { return false }
        return FileManager.default.fileExists(atPath: paths.journalURL.path)
    }

    /// Geçiş günlüğünün bulunduğu klasör; süpürücü buradaki yarım `.switch-journal-*.tmp` dosyalarını bulur.
    static func journalDirectory() -> URL? {
        (try? paths())?.journalURL.deletingLastPathComponent()
    }

    private static func paths() throws -> Paths {
        if let pathsOverride { return pathsOverride }
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return Paths(journalURL: root.appendingPathComponent("ArchiveStoreSwitchJournal.json"),
                     backupRoot: root.appendingPathComponent("ArchiveRestoreBackups", isDirectory: true),
                     recoveredRoot: root.appendingPathComponent("RecoveredStores", isDirectory: true))
    }

    private static func readEntry(paths: Paths) throws -> Entry {
        guard (try paths.journalURL.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else {
            throw failure("Kalıcı katalog geçişi günlüğü normal bir dosya değil.")
        }
        let entry = try JSONDecoder().decode(Entry.self, from: Data(contentsOf: paths.journalURL))
        guard entry.version == 1, validHash(entry.beforeFingerprint),
              !entry.backupHashes.isEmpty, entry.backupHashes.values.allSatisfy(validHash),
              (entry.phase == .pending ? entry.newPointer == nil : entry.newPointer != nil) else {
            throw failure("Kalıcı katalog geçişi günlüğü bozuk; metadata değiştirilmedi, katalog açılmadı.")
        }
        _ = try checkedBackupDirectory(URL(fileURLWithPath: entry.backupDirectory), paths: paths)
        _ = try checkedPointer(entry.oldPointer, paths: paths, requireFile: false)
        if let new = entry.newPointer { _ = try checkedPointer(new, paths: paths, requireFile: false) }
        return entry
    }

    private static func verifiedBackup(_ entry: Entry, paths: Paths) throws -> URL {
        let directory = try checkedBackupDirectory(URL(fileURLWithPath: entry.backupDirectory), paths: paths)
        for (name, hash) in entry.backupHashes {
            guard digest(try backupFile(name, directory: directory)) == hash else {
                throw failure("Yarım katalog geçişinin ham yedeği değişmiş; otomatik geri alma ve katalog açılışı durduruldu.")
            }
        }
        let index = try JSONDecoder().decode([String: String].self, from: backupFile("dosya-dizini.json", directory: directory))
        let required = Set(index.keys).union(["dosya-dizini.json", "onceki-ayarlar.json", "Islem-Oncesi-Tam-Arsiv.zip"])
        guard Set(entry.backupHashes.keys) == required else { throw failure("Katalog geçişinin ham yedek kapsamı eksik.") }
        let previous = try FullArchive.readValidated(data: backupFile("Islem-Oncesi-Tam-Arsiv.zip", directory: directory))
        guard try ArchiveImportCoordinator.fingerprint(previous) == entry.beforeFingerprint else {
            throw failure("Yarım geçişin tam yedek kapsamı doğrulanamadı.")
        }
        return directory
    }

    private static func checkedBackupDirectory(_ directory: URL, paths: Paths) throws -> URL {
        let value = directory.standardizedFileURL.resolvingSymlinksInPath(), root = paths.backupRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard value.path.hasPrefix(root.path + "/"),
              (try value.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else {
            throw failure("Geçiş yedeği izin verilen katalog yedek dizininde değil.")
        }
        return value
    }

    private static func checkedPointer(_ object: Any?, paths: Paths, requireFile: Bool) throws -> String? {
        guard let object else { return nil }
        guard let path = object as? String, !path.isEmpty, path.hasPrefix("/") else { throw failure("Katalog geçişi depo işaretçisi geçersiz.") }
        let value = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath(), root = paths.recoveredRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard value.path.hasPrefix(root.path + "/"), value.pathExtension == "store" else {
            throw failure("Katalog geçişi işaretçisi izin verilen depo dizininde değil.")
        }
        if requireFile {
            guard (try value.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { throw failure("Katalog geçişinin depo dosyası bulunamadı.") }
            let handle = try FileHandle(forReadingFrom: value); defer { try? handle.close() }
            guard try handle.read(upToCount: 16) == Data("SQLite format 3\0".utf8) else { throw failure("Katalog geçişinin depo dosyası geçersiz.") }
        }
        return value.path
    }

    private static func backupFile(_ name: String, directory: URL) throws -> Data {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\") else { throw failure("Ham geçiş yedeğinin dosya adı geçersiz.") }
        let url = directory.appendingPathComponent(name).standardizedFileURL.resolvingSymlinksInPath()
        guard url.deletingLastPathComponent().path == directory.path,
              (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else {
            throw failure("Ham geçiş yedeği izin verilen dizinden çıkıyor veya dosya eksik.")
        }
        return try Data(contentsOf: url)
    }

    private static func verifyRawRestoration(directory: URL) throws {
        let index = try JSONDecoder().decode([String: String].self, from: backupFile("dosya-dizini.json", directory: directory))
        for (name, path) in index {
            guard try Data(contentsOf: URL(fileURLWithPath: path)) == backupFile(name, directory: directory) else {
                throw failure("Eski metadata ham baytları geri alma doğrulamasından geçmedi.")
            }
        }
        let preferences = try JSONDecoder().decode([String: Data].self, from: backupFile("onceki-ayarlar.json", directory: directory))
        func normalized(_ settings: [String: Data]) throws -> [String: Data] {
            try settings.mapValues { data in
                let value = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
                return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
            }
        }
        guard try normalized(ArchiveSettings.snapshot()) == normalized(preferences) else { throw failure("Eski ayarlar geri alma doğrulamasından geçmedi.") }
    }

    private static func recordRecoveredRollback(directory: URL) throws {
        let url = directory.appendingPathComponent("Katalog-Gecisi-Kapsam.txt")
        let raw = try Data(contentsOf: url)
        guard let text = String(data: raw, encoding: .utf8),
              let first = text.split(separator: "\n", omittingEmptySubsequences: false).first,
              let prefix = ["Ayrı katalog açma:", "Mevcut kataloğa ekleme:"].first(where: { first.hasPrefix($0) }) else {
            throw failure("Geri alınan katalog geçişinin kapsam raporu doğrulanamadı; günlük korundu.")
        }
        let remaining = text.dropFirst(first.count)
        try Data((prefix + " geri_alindi" + remaining).utf8).write(to: url, options: .atomic)
    }

    /// Writer and async reader use the identical byte cap. The pure guard runs
    /// before even a temporary marker is written, so an oversized session/hash
    /// index cannot create a journal that the next startup refuses to read.
    nonisolated static func encodeValidatedEntry(_ entry: Entry) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(entry)
        guard data.count <= maximumMarkerSize else {
            throw ArchiveSwitchLeaseWorker.Failure(message: "Katalog geçişi günlüğü 1 MiB güvenli okuma sınırını aşıyor; işlem günlüğü yazılmadı ve mevcut katalog korundu.")
        }
        return data
    }

    private static func write(_ entry: Entry, paths: Paths) throws {
        let encoded = try encodeValidatedEntry(entry)
        try FileManager.default.createDirectory(at: paths.journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = paths.journalURL.deletingLastPathComponent().appendingPathComponent(".switch-journal-" + UUID().uuidString + ".tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try encoded.write(to: temporary, options: .withoutOverwriting)
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        try handle.synchronize()
        try handle.close()
        guard try JSONDecoder().decode(Entry.self, from: Data(contentsOf: temporary)) == entry else {
            throw failure("Kalıcı katalog geçişi günlüğü tekrar okunamadı.")
        }
        // Bütün hata veren işlemler commit öncesinde yapılır. rename eski veya
        // yeni tam markerı bırakır; sonrasında UI yayınını ters çevirecek hata yoktur.
        guard rename(temporary.path, paths.journalURL.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func validHash(_ value: String) -> Bool { value.count == 64 && value.allSatisfy(\.isHexDigit) }
    private static func failure(_ message: String) -> SchoolLibraryService.OperationError { .init(message: message) }
}

@MainActor
extension ArchiveSwitchJournal {
    /// Only this file can issue the system permit. It binds the existing pending
    /// marker, current (possibly NEW) pointer and all privately verified files.
    struct StartupRecoveryPermit {
        fileprivate let entry: Entry
        fileprivate let paths: Paths
        fileprivate let marker: ArchiveSwitchLeaseWorker.FileSeal
        fileprivate let proof: ArchiveSwitchLeaseWorker.Proof
        fileprivate let pointer: Data?
        fileprivate init(entry: Entry, paths: Paths, marker: ArchiveSwitchLeaseWorker.FileSeal,
                         proof: ArchiveSwitchLeaseWorker.Proof, pointer: Data?) {
            self.entry = entry; self.paths = paths; self.marker = marker; self.proof = proof; self.pointer = pointer
        }
    }

    struct EmergencyLease {
        fileprivate let entry: Entry
        fileprivate let paths: Paths
        fileprivate let marker: ArchiveSwitchLeaseWorker.FileSeal
        fileprivate let pointer: Data?
        fileprivate let proof: ArchiveRecoveryWorker.EmergencyProof
        fileprivate init(entry: Entry, paths: Paths, marker: ArchiveSwitchLeaseWorker.FileSeal,
                         pointer: Data?, proof: ArchiveRecoveryWorker.EmergencyProof) {
            self.entry = entry; self.paths = paths; self.marker = marker; self.pointer = pointer; self.proof = proof
        }
    }

    /// Issued only after the distinct selected-ZIP + raw-globals proof has been
    /// fully verified. A role-locked startup cannot create arbitrary write permits.
    struct EmergencyStartupPermit {
        fileprivate let entry: Entry
        fileprivate let paths: Paths
        fileprivate let marker: ArchiveSwitchLeaseWorker.FileSeal
        fileprivate let pointer: Data?
        fileprivate let proof: ArchiveRecoveryWorker.EmergencyProof
        fileprivate init(entry: Entry, paths: Paths, marker: ArchiveSwitchLeaseWorker.FileSeal,
            pointer: Data?, proof: ArchiveRecoveryWorker.EmergencyProof) {
            self.entry = entry; self.paths = paths; self.marker = marker; self.pointer = pointer; self.proof = proof
        }
    }

    /// No store or model-dependent UI may exist until this returns successfully.
    /// The old synchronous API remains available to existing compatibility tests.
    @discardableResult
    static func recoverPendingBeforeStoreOpenAsync(beforeRollback: (() throws -> Void)? = nil,
        didStart: (@Sendable (Bool) -> Void)? = nil) async throws -> RecoveryResult? {
        let capturedPaths = try paths()
        guard let markerData = try asyncMarkerSnapshot(paths: capturedPaths) else { return nil }
        let marker = try ArchiveSwitchLeaseWorker.FileSeal.capture(capturedPaths.journalURL)
        let entry = try readEntry(paths: capturedPaths)
        // The committed branch has no full ZIP/fingerprint work and keeps its
        // existing pointer contradiction checks and emergency handling.
        if entry.phase == .committed { return try recoverPendingBeforeStoreOpen() }
        if entry.emergencyRecovery == true {
            return try await recoverEmergencyPending(entry: entry, capturedPaths: capturedPaths,
                markerData: markerData, marker: marker, beforeRollback: beforeRollback, didStart: didStart)
        }
        let pointer = try recoveryPointerSnapshot()
        let raw = try ArchiveImportCoordinator.captureRawMetadataPlan()
        let directory = try checkedBackupDirectory(URL(fileURLWithPath: entry.backupDirectory), paths: capturedPaths)
        let proof = try await Task.detached(priority: .utility) {
            ArchiveRecoveryWorker.recordWorkerStart(didStart)
            try Task.checkCancellation()
            let value = try ArchiveSwitchLeaseWorker.verify(directory: directory, backupRoot: capturedPaths.backupRoot,
                beforeFingerprint: entry.beforeFingerprint, expectedHashes: entry.backupHashes)
            try Task.checkCancellation()
            return value
        }.value
        try Task.checkCancellation()
        try beforeRollback?()
        guard try paths() == capturedPaths, try asyncMarkerSnapshot(paths: capturedPaths) == markerData,
              try recoveryPointerSnapshot() == pointer else {
            throw failure("Açılış doğrulaması sırasında geçiş günlüğü, yollar veya depo işaretçisi değişmiş; katalog kapalı kaldı.")
        }
        try marker.validateCurrent(); try proof.validateCurrent(backupRoot: capturedPaths.backupRoot)
        try requireRecoveryRawUnchanged(raw)
        let permit = StartupRecoveryPermit(entry: entry, paths: capturedPaths, marker: marker, proof: proof, pointer: pointer)
        // From this point through marker removal there is no await. Role-locked
        // system recovery is authorized only by this exact private sealed permit.
        try StoreRecovery.rollbackMetadataForInterruptedSwitch(from: directory, permit: permit)
        try verifyRawRestoration(directory: directory)
        if let old = entry.oldPointer { UserDefaults.standard.set(old, forKey: StoreRecovery.selectedStoreKey) }
        else { UserDefaults.standard.removeObject(forKey: StoreRecovery.selectedStoreKey) }
        try recordRecoveredRollback(directory: directory)
        try finishStartupRollback(permit)
        return RecoveryResult(token: entry.token, backupURL: directory.appendingPathComponent("Islem-Oncesi-Tam-Arsiv.zip"), phase: .pending)
    }

    static func validateStartupRecoveryPermit(_ permit: StartupRecoveryPermit, backupDirectory: URL) throws {
        try validateStartupProof(permit)
        guard backupDirectory.standardizedFileURL.resolvingSymlinksInPath() == permit.proof.directory,
              try recoveryPointerSnapshot() == permit.pointer else {
            throw failure("Sistem geri alma izni canlı başlangıç işaretçisine veya bu özel yedeğe ait değil.")
        }
    }

    private static func validateStartupProof(_ permit: StartupRecoveryPermit) throws {
        try permit.marker.validateCurrent()
        guard permit.entry.phase == .pending, try paths() == permit.paths,
              try readEntry(paths: permit.paths) == permit.entry else {
            throw failure("Sistem geri alma izninin bekleyen geçişi veya yolları değişmiş.")
        }
        try permit.proof.validateCurrent(backupRoot: permit.paths.backupRoot)
    }

    private static func finishStartupRollback(_ permit: StartupRecoveryPermit) throws {
        try validateStartupProof(permit)
        // A crash may have switched to the new pointer before the commit marker.
        // Only AFTER raw rollback must the pointer equal the old verified value.
        guard try checkedPointer(UserDefaults.standard.object(forKey: StoreRecovery.selectedStoreKey),
            paths: permit.paths, requireFile: permit.entry.oldPointer != nil) == permit.entry.oldPointer else {
            throw failure("Açılış geri almasında eski depo işaretçisi doğrulanmadı; günlük korundu.")
        }
        guard UserDefaults.standard.synchronize() else { throw failure("Açılış geri almasında eski işaretçi kalıcılaştırılamadı; günlük korundu.") }
        try FileManager.default.removeItem(at: permit.paths.journalURL)
    }

    /// Heavy ZIP/SHA/raw copying ends before the pending marker is written.
    /// The marker covers EVERY emergency restore, even when no old marker exists.
    /// There is no await between this durable pending write and commit/rollback.
    static func withEmergencyRecoveryAsync<Result>(contents: ArchiveContents,
        beforeCommit: (() throws -> Void)? = nil, didStart: (@Sendable (Bool) -> Void)? = nil,
        commit: (ArchiveContents, EmergencyLease) throws -> Result) async throws -> Result {
        try SchoolLibraryService.requireAdmin()
        let capturedPaths = try paths(), token = UUID()
        let originalMarker = try asyncMarkerSnapshot(paths: capturedPaths)
        let originalSeal = try ArchiveBackgroundWork.FileSeal.capture(capturedPaths.journalURL)
        let pointer = try recoveryPointerSnapshot()
        let raw = try ArchiveImportCoordinator.captureRawMetadataPlan()
        let directory = capturedPaths.backupRoot.appendingPathComponent("emergency-" + token.uuidString, isDirectory: true)
        let proof = try await Task.detached(priority: .userInitiated) {
            ArchiveRecoveryWorker.recordWorkerStart(didStart)
            return try ArchiveRecoveryWorker.prepareEmergency(contents: contents, marker: originalMarker, pointer: pointer,
                raw: raw, directory: directory, backupRoot: capturedPaths.backupRoot)
        }.value
        try Task.checkCancellation()
        try beforeCommit?()
        try SchoolLibraryService.requireAdmin()
        guard try paths() == capturedPaths, try asyncMarkerSnapshot(paths: capturedPaths) == originalMarker,
              try ArchiveBackgroundWork.FileSeal.capture(capturedPaths.journalURL) == originalSeal,
              try recoveryPointerSnapshot() == pointer else {
            throw failure("Acil kurtarma doğrulaması sırasında yollar, eski günlük veya depo işaretçisi değişti; yazım başlamadı.")
        }
        try proof.validateCurrent(backupRoot: capturedPaths.backupRoot)
        try requireRecoveryRawUnchanged(raw)
        // The previous DB can be corrupt, so this pending emergency format binds
        // raw globals + original pointer and the fully validated SELECTED ZIP.
        // It does not misrepresent the corrupt old DB as a valid full archive.
        let entry = Entry(version: 1, token: token, backupDirectory: proof.directory.path, oldPointer: nil,
            beforeFingerprint: proof.fingerprint, backupHashes: proof.hashes, phase: .pending,
            newPointer: nil, emergencyRecovery: true)
        try write(entry, paths: capturedPaths)
        let lease = EmergencyLease(entry: entry, paths: capturedPaths,
            marker: try ArchiveSwitchLeaseWorker.FileSeal.capture(capturedPaths.journalURL), pointer: pointer, proof: proof)
        do {
            return try commit(proof.contents, lease)
        } catch {
            let original = error
            do { try rollbackEmergency(lease) }
            catch {
                throw failure("Acil kurtarma ve ham geri alma tamamlanamadı. Kalıcı pending günlük ve ham yedekler korundu; açılış güvenle kapalı kalır: \(error.localizedDescription)")
            }
            throw original
        }
    }

    static func commitEmergencyRecovery(_ lease: EmergencyLease, newPath: String) throws {
        try SchoolLibraryService.requireAdmin()
        try validateEmergencyProof(entry: lease.entry, paths: lease.paths, marker: lease.marker, proof: lease.proof)
        guard try recoveryPointerSnapshot() == lease.pointer else { throw failure("Acil kurtarmanın eski işaretçisi değişmiş.") }
        let pointer = try checkedPointer(newPath, paths: lease.paths, requireFile: true)
        guard pointer != nil else { throw failure("Acil kurtarmanın doğrulanan yeni deposu bulunamadı.") }
        var committed = lease.entry
        committed.phase = .committed; committed.newPointer = pointer
        try write(committed, paths: lease.paths)
    }

    private static func validateEmergencyProof(entry: Entry, paths captured: Paths,
        marker: ArchiveSwitchLeaseWorker.FileSeal, proof: ArchiveRecoveryWorker.EmergencyProof) throws {
        try marker.validateCurrent()
        guard entry.phase == .pending, entry.emergencyRecovery == true, try paths() == captured,
              try readEntry(paths: captured) == entry, entry.backupDirectory == proof.directory.path,
              entry.backupHashes == proof.hashes, entry.beforeFingerprint == proof.fingerprint else {
            throw failure("Acil sistem geri alma izni bu kalıcı pending geçişe ait değil.")
        }
        try proof.validateCurrent(backupRoot: captured.backupRoot)
    }

    private static func recoverEmergencyPending(entry: Entry, capturedPaths: Paths, markerData: Data,
        marker: ArchiveSwitchLeaseWorker.FileSeal, beforeRollback: (() throws -> Void)?,
        didStart: (@Sendable (Bool) -> Void)?) async throws -> RecoveryResult {
        let pointer = try recoveryPointerSnapshot(), raw = try ArchiveImportCoordinator.captureRawMetadataPlan()
        let directory = try checkedBackupDirectory(URL(fileURLWithPath: entry.backupDirectory), paths: capturedPaths)
        let proof = try await Task.detached(priority: .utility) {
            ArchiveRecoveryWorker.recordWorkerStart(didStart)
            return try ArchiveRecoveryWorker.verifyEmergency(directory: directory, backupRoot: capturedPaths.backupRoot,
                fingerprint: entry.beforeFingerprint, expectedHashes: entry.backupHashes)
        }.value
        try Task.checkCancellation(); try beforeRollback?()
        guard try paths() == capturedPaths, try asyncMarkerSnapshot(paths: capturedPaths) == markerData,
              try recoveryPointerSnapshot() == pointer else {
            throw failure("Acil açılış geri alma doğrulaması sırasında yollar, günlük veya işaretçi değişti; katalog kapalı kaldı.")
        }
        try marker.validateCurrent(); try proof.validateCurrent(backupRoot: capturedPaths.backupRoot)
        try requireRecoveryRawUnchanged(raw)
        let permit = EmergencyStartupPermit(entry: entry, paths: capturedPaths, marker: marker, pointer: pointer, proof: proof)
        try StoreRecovery.rollbackMetadataForInterruptedEmergency(from: directory, permit: permit)
        try verifyRawRestoration(directory: directory)
        try restoreEmergencyOrigin(entry: entry, paths: capturedPaths, marker: marker, proof: proof)
        if proof.originalMarker != nil {
            throw failure("Yarım acil kurtarmanın eski ham verileri ve özgün günlüğü geri alındı. Önceki günlük de güvenli açılış gerektiriyor; yeniden deneyin veya doğrulanmış ZIP seçin.")
        }
        return RecoveryResult(token: entry.token, backupURL: directory.appendingPathComponent(ArchiveRecoveryWorker.selectedName), phase: .pending)
    }

    static func validateEmergencyStartupPermit(_ permit: EmergencyStartupPermit, backupDirectory: URL) throws {
        try validateEmergencyProof(entry: permit.entry, paths: permit.paths, marker: permit.marker, proof: permit.proof)
        guard backupDirectory.standardizedFileURL.resolvingSymlinksInPath() == permit.proof.directory,
              try recoveryPointerSnapshot() == permit.pointer else { throw failure("Acil sistem izni bu canlı başlangıç işaretçisine ait değil.") }
    }

    private static func rollbackEmergency(_ lease: EmergencyLease) throws {
        try validateEmergencyProof(entry: lease.entry, paths: lease.paths, marker: lease.marker, proof: lease.proof)
        let permit = EmergencyStartupPermit(entry: lease.entry, paths: lease.paths, marker: lease.marker,
            pointer: try recoveryPointerSnapshot(), proof: lease.proof)
        try StoreRecovery.rollbackMetadataForInterruptedEmergency(from: lease.proof.directory, permit: permit)
        try verifyRawRestoration(directory: lease.proof.directory)
        try restoreEmergencyOrigin(entry: lease.entry, paths: lease.paths, marker: lease.marker, proof: lease.proof)
    }

    /// Raw metadata is already restored before the original pointer/marker is
    /// installed. A kill anywhere before marker replacement repeats this exact
    /// rollback at next startup; a corrupt original marker remains failclosed.
    private static func restoreEmergencyOrigin(entry: Entry, paths captured: Paths,
        marker: ArchiveSwitchLeaseWorker.FileSeal, proof: ArchiveRecoveryWorker.EmergencyProof) throws {
        try validateEmergencyProof(entry: entry, paths: captured, marker: marker, proof: proof)
        if let data = proof.originalPointer {
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            UserDefaults.standard.set(object, forKey: StoreRecovery.selectedStoreKey)
        } else { UserDefaults.standard.removeObject(forKey: StoreRecovery.selectedStoreKey) }
        guard try recoveryPointerSnapshot() == proof.originalPointer, UserDefaults.standard.synchronize() else {
            throw failure("Acil geri almada eski pointer kalıcılaştırılamadı; pending günlük korundu.")
        }
        if let original = proof.originalMarker {
            let temporary = captured.journalURL.deletingLastPathComponent().appendingPathComponent(".emergency-original-" + UUID().uuidString + ".tmp")
            defer { try? FileManager.default.removeItem(at: temporary) }
            try original.write(to: temporary, options: .withoutOverwriting)
            let handle = try FileHandle(forWritingTo: temporary)
            defer { try? handle.close() }; try handle.synchronize(); try handle.close()
            guard try Data(contentsOf: temporary) == original else { throw failure("Özgün günlük forensic kopyası geri okunamadı; pending korundu.") }
            guard rename(temporary.path, captured.journalURL.path) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        } else { try FileManager.default.removeItem(at: captured.journalURL) }
    }

    private static func recoveryPointerSnapshot() throws -> Data? {
        guard let value = UserDefaults.standard.object(forKey: StoreRecovery.selectedStoreKey) else { return nil }
        return try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }

    private static func requireRecoveryRawUnchanged(_ before: ArchiveBackgroundWork.RawMetadata) throws {
        let current = try ArchiveImportCoordinator.captureRawMetadataPlan()
        let old = before.sources.sorted { $0.url.path < $1.url.path }, new = current.sources.sorted { $0.url.path < $1.url.path }
        guard old.count == new.count, zip(old, new).allSatisfy({ pair in pair.0.url == pair.1.url && pair.0.seal == pair.1.seal }),
              try ArchiveLiveState.same(ArchiveContents(settings: before.settings), ArchiveContents(settings: current.settings)) else {
            throw failure("Doğrulama sırasında kişi, geçmiş, tarama dosyası veya ayarlar değişti. Yeni deneme gerekir; canlı metadata yazılmadı.")
        }
    }
}
