import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@MainActor
enum StoreRecovery {
    static var selectedStoreKey: String {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") { return "uiTestingSelectedRecoveryStorePath" }
#endif
        return "selectedRecoveryStorePath"
    }
    static var selectedStoreURL: URL? { get throws { try validatedSelectedStoreURL() } }

    /// İşaretçi varsa eksik/bozuk hedef sessizce varsayılan boş depoya düşemez.
    static func validatedSelectedStoreURL() throws -> URL? {
        try selectedPointerURL(validateFile: true)
    }

    private static func selectedPointerURL(validateFile: Bool) throws -> URL? {
        guard let value = UserDefaults.standard.object(forKey: selectedStoreKey) else { return nil }
        guard let path = value as? String, !path.isEmpty else {
            throw SchoolLibraryService.OperationError(message: "Seçilmiş kurtarma deposunun işaretçisi geçersiz. Eski veri korunuyor; doğrulanmış arşivle kurtarın.")
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let safeRoot = try ArchiveSwitchJournal.recoveredStoreRoot().standardizedFileURL.resolvingSymlinksInPath()
        guard url.resolvingSymlinksInPath().path.hasPrefix(safeRoot.path + "/"), url.pathExtension == "store" else {
            throw SchoolLibraryService.OperationError(message: "Seçilmiş kurtarma deposunun yolu geçersiz. Otomatik boş katalog açılmadı.")
        }
        if validateFile {
            guard FileManager.default.fileExists(atPath: url.path),
                  (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else {
                throw SchoolLibraryService.OperationError(message: "Seçilmiş kurtarma deposu bulunamadı. Yeni boş katalog açılmadı; arşivden yeniden kurtarın.")
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            guard try handle.read(upToCount: 16) == Data("SQLite format 3\0".utf8) else {
                throw SchoolLibraryService.OperationError(message: "Seçilmiş kurtarma deposunun dosyası geçersiz veya eksik. Özgün dosya değiştirilmedi.")
            }
        }
        return url
    }

    static func restore(_ contents: ArchiveContents, reservationNow: Date? = nil, notifyReservations: Bool = true, switchJournalToken: UUID? = nil, allowFailedSwitchRecovery: Bool = false, verify: ((ModelContext) throws -> Void)? = nil) throws -> ModelContainer {
        try SchoolLibraryService.requireAdmin()
        let emergencyRecovery: ArchiveSwitchJournal.EmergencyRecovery?
        if let switchJournalToken {
            guard !allowFailedSwitchRecovery else { throw SchoolLibraryService.OperationError(message: "Aynı işlem normal geçiş ve acil kurtarma olamaz.") }
            try ArchiveSwitchJournal.requirePending(token: switchJournalToken)
            emergencyRecovery = nil
        } else {
            emergencyRecovery = try ArchiveSwitchJournal.prepareForIndependentRestore(allowFailedSwitchRecovery: allowFailedSwitchRecovery, verifiedRecoveryContents: contents)
        }
        let root = try ArchiveSwitchJournal.recoveredStoreRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(UUID().uuidString + ".store")
        let restored = try ArchiveLoanRestorer.buildRecoveryStore(contents: contents, at: url)
        var metadataBackup: URL?
        let priorWarning = LibrarySyncStatus.shared.warning
        do {
            metadataBackup = try ArchiveLoanRestorer.restoreRecoveryMetadata(contents)
            let context = restored.mainContext
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
                  try ModelContext(restored).fetchCount(FetchDescriptor<LibraryEventOutbox>()) == 0 else {
                throw SchoolLibraryService.OperationError(message: "Kurtarılan depo ilişkileri veya metadata sayıları doğrulanamadı; eski işaretçi korundu.")
            }
            try verify?(context)
            // İşaretçi yalnız bütün kalıcı depo ve metadata kapıları geçince değişir.
            if let emergencyRecovery { try ArchiveSwitchJournal.commitEmergencyRecovery(emergencyRecovery, newPath: url.path) }
            UserDefaults.standard.set(url.path, forKey: selectedStoreKey)
            return restored
        } catch {
            let original = error
            if let metadataBackup {
                do { try rollbackMetadata(from: metadataBackup) }
                catch { throw SchoolLibraryService.OperationError(message: "Kurtarma doğrulanamadı; metadata geri alma yazımı da tamamlanamadı. Özgün depo işaretçisi ve ham metadata-backup dosyaları korundu.") }
            }
            LibrarySyncStatus.shared.warning = priorWarning
            throw original
        }
    }

    /// Kurtarma sonrası bir doğrulama kapısı başarısızsa ham, hatta bozuk eski dosyayı aynen geri getirir.
    static func rollbackMetadata(from backup: URL) throws {
        try SchoolLibraryService.requireAdmin()
        try rollbackMetadataContents(from: backup)
    }

    /// Sistem geri alma yalnız kalıcı markerın token/path/hash kapsamıyla yetkilidir.
    static func rollbackMetadataForInterruptedSwitch(from backup: URL, permit: ArchiveSwitchJournal.RecoveryPermit) throws {
        try ArchiveSwitchJournal.validateRecoveryPermit(permit, backupDirectory: backup)
        try rollbackMetadataContents(from: backup)
    }

    /// Startup permission has already fully verified every private file on a
    /// worker. This cheap sealed check cannot be constructed by another source file.
    static func rollbackMetadataForInterruptedSwitch(from backup: URL, permit: ArchiveSwitchJournal.StartupRecoveryPermit) throws {
        try ArchiveSwitchJournal.validateStartupRecoveryPermit(permit, backupDirectory: backup)
        try rollbackMetadataContents(from: backup)
    }

    /// Distinct emergency format authorizes only privately SHA-verified raw
    /// globals. It never treats a corrupt old database as a verified full archive.
    static func rollbackMetadataForInterruptedEmergency(from backup: URL,
        permit: ArchiveSwitchJournal.EmergencyStartupPermit) throws {
        try ArchiveSwitchJournal.validateEmergencyStartupPermit(permit, backupDirectory: backup)
        try rollbackMetadataContents(from: backup)
    }

    private static func rollbackMetadataContents(from backup: URL) throws {
        let index = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: backup.appendingPathComponent("dosya-dizini.json")))
        let preferences = try JSONDecoder().decode([String: Data].self, from: Data(contentsOf: backup.appendingPathComponent("onceki-ayarlar.json")))
        var targets = [StudentStore.storageURL, MemberStore.storageURL, LoanHistoryStore.storageURL, GraduatedStudentStore.storageURL].compactMap { $0 }
        targets += ArchiveSettings.supportingFileNames.compactMap { ArchiveSettings.supportingURL(for: $0) }
        let sessionDirectory = ScanSessionStore.directoryOverride ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("TaramaOturumlari", isDirectory: true)
        if let directory = sessionDirectory, FileManager.default.fileExists(atPath: directory.path) {
            targets += try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        }
        let known = Set(targets.map { $0.standardizedFileURL.path })
        var originals: [String: Data] = [:]
        for (name, path) in index {
            let target = URL(fileURLWithPath: path).standardizedFileURL
            let sessionAllowed = sessionDirectory.map { target.deletingLastPathComponent().standardizedFileURL == $0.standardizedFileURL && target.pathExtension == "json" } ?? false
            guard !name.contains("/"), name != "..", known.contains(target.path) || sessionAllowed else {
                throw SchoolLibraryService.OperationError(message: "Ham metadata yedeğinin dosya dizini geçersiz; keyfi dosya yolu değiştirilmedi.")
            }
            originals[target.path] = try Data(contentsOf: backup.appendingPathComponent(name))
        }
        // Eski olup kurtarmada çıkarılan oturum yolları da geri gelir.
        targets += originals.keys.map { URL(fileURLWithPath: $0) }
        var restoredPaths = Set<String>()
        for target in targets where restoredPaths.insert(target.standardizedFileURL.path).inserted {
            if let data = originals[target.standardizedFileURL.path] {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: target, options: .atomic)
            } else if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        }
        LoanHistoryStore.invalidate(); StudentStore.invalidateCaches(); MemberStore.invalidateCaches()
        for key in ArchiveSettings.allowedKeys { UserDefaults.standard.removeObject(forKey: key) }
        try ArchiveSettings.restore(preferences)
    }

    /// Capture the selected path here; large file reads and ZIP work run on a worker.
    /// Keep rawStoreBackup() unchanged for synchronous compatibility/tests.
    static func rawStoreBackupAsync() async throws -> ArchiveDocument {
        let original = try selectedPointerURL(validateFile: false) ?? ModelConfiguration(schema: KitapVeritabani.schema).url
        let result = try await ArchiveFileBackgroundWork.technicalBackup(store: original)
        return ArchiveDocument(data: result.data)
    }

    static func rawStoreBackup() throws -> ArchiveDocument {
        let original = try selectedPointerURL(validateFile: false) ?? ModelConfiguration(schema: KitapVeritabani.schema).url
        return ArchiveDocument(data: try ArchiveFileBackgroundWork.buildTechnicalBackup(store: original).data)
    }

    /// Uygulama açılışı, Siri/Kısayollar ve arka plan arşivi AYNI kapıdan geçer: kişi/geçmiş dosyaları
    /// taşınır, işaretçi doğrulanır, kap açılır, bekleyen geçmiş aktarımı ve rezervasyonlar işlenir.
    /// - Parameter sync: `true` ise bekleyen geçiş günlüğü eşzamanlı sürümle kurtarılır (Siri/arka plan).
    ///   `false` ise çağıran (uygulama açılışı) eşzamansız kurtarmayı zaten bitirmiştir; günlük hâlâ
    ///   duruyorsa kap AÇILMAZ.
    static func openVerifiedContainer(sync: Bool) throws -> ModelContainer {
        if sync { try ArchiveSwitchJournal.recoverPendingBeforeStoreOpen() }
        else if ArchiveSwitchJournal.hasMarker() {
            throw SchoolLibraryService.OperationError(message: "Yarım kalmış katalog geçişi var; güvenli kurtarma bitmeden katalog açılmadı.")
        }
        // Kurtarma geri alması bitti; okuyucular açılmadan kişi/geçmiş dosyaları yeni konuma taşınır.
        MetadataRelocation.migrateIfNeeded()
        let store = try KitapVeritabani.makeContainer(url: try validatedSelectedStoreURL())
        do { try SchoolLibraryService.flushHistoryOutbox(context: store.mainContext) }
        catch { LibrarySyncStatus.shared.warning = "Ödünç işlemleri depoda korunuyor; geçmiş aktarımı bekliyor: \(error.localizedDescription)" }
        try SchoolLibraryService.migrateLegacyLoans(context: store.mainContext)
        try SchoolLibraryService.refreshReservations(context: store.mainContext)
        return store
    }
}

struct StoreRecoveryView: View {
    let failure: String
    let onRecovered: (ModelContainer) -> Void
    @State private var chooseArchive = false
    @State private var contents: ArchiveContents?
    @State private var message: String?
    @State private var exportDocument: ArchiveDocument?
    @State private var exportBackup = false
    @State private var working = false
    @State private var permission = YetkiDurumu.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Katalog açılamadı", systemImage: "externaldrive.badge.exclamationmark")
                        .font(.title2.bold())
                    Text("Kayıtlı dosyanız korunuyor. Kalıcı depo açılana kadar kitap ekleme ve ödünç işlemleri kapalıdır.")
                    Text(failure).font(.footnote).foregroundStyle(.secondary)
                }
                Section("Kurtarma") {
                    if !permission.yonetici {
                        Button("Kurtarma için yönetici kilidini aç", systemImage: "lock.open") {
                            Task { await permission.yoneticiOl(neden: "Doğrulanmış yedekten kütüphane verilerini kurtarmak için doğrulayın") }
                        }
                        if let error = permission.hata { HataSatiri(metin: error) }
                    }
                    Button("Tam sistem arşivi seç", systemImage: "folder") { chooseArchive = true }.disabled(working)
                    Button("Mevcut depo dosyalarını dışa aktar", systemImage: "square.and.arrow.up") {
                        working = true
                        Task { @MainActor in
                            defer { working = false }
                            do { exportDocument = try await StoreRecovery.rawStoreBackupAsync(); exportBackup = true }
                            catch { message = error.localizedDescription }
                        }
                    }.disabled(working)
                    if working { ProgressView("Dosya işleniyor…") }
                    if let contents {
                        LabeledContent("Eser", value: "\(contents.books.count)")
                        LabeledContent("Nüsha kayıtları", value: "\(contents.copies.count)")
                        LabeledContent("Aktif ödünç", value: "\(contents.activeLoans.count)")
                        Text("Arşiv ayrı bir depoda denenecek. Eski depo değiştirilmez.")
                        Button("Doğrulanmış yedekten kurtar", systemImage: "arrow.counterclockwise") {
                            working = true
                            Task { @MainActor in
                                defer { working = false }
                                do {
                                    let restored = try await StoreRecovery.restoreAsync(contents)
                                    onRecovered(restored)
                                } catch { message = "Kurtarma tamamlanmadı: \(error.localizedDescription)" }
                            }
                        }.disabled(working || !permission.yonetici)
                    }
                    if let message { HataSatiri(metin: message) }
                }
            }
            .navigationTitle("Veri Kurtarma")
            .fileImporter(isPresented: $chooseArchive, allowedContentTypes: [.zip]) { result in
                working = true
                Task { @MainActor in
                    defer { working = false }
                    do {
                        let url = try result.get()
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let decoded = try await ArchiveFileBackgroundWork.readValidated(from: url)
                        contents = decoded.contents
                        message = nil
                    } catch { contents = nil; message = "Arşiv doğrulanamadı: \(error.localizedDescription)" }
                }
            }
            .fileExporter(isPresented: $exportBackup, document: exportDocument, contentType: .zip,
                          defaultFilename: "Kitap-Bul-Depo-Kurtarma") { result in
                if case .failure(let error) = result { message = error.localizedDescription }
            }
        }
    }
}

/// Kurtarma ekranı hataları yalnız renkle değil, uyarı simgesi ve 'Hata:' önekiyle de ayrışır
/// (renk körlüğü, büyük yazı ve VoiceOver için).
struct HataSatiri: View {
    let metin: String
    var body: some View {
        Label("Hata: " + metin, systemImage: "exclamationmark.triangle.fill")
            .labelStyle(RenkliIkonEtiketi(renk: KitapTema.vurgu))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isStaticText)
    }
}
