#if DEBUG
import Foundation
import SwiftData

/// Yalnız iki açık UI test argümanı ile çalışır. Geçiş günlüğü, tam yedekler ve
/// yeni SQLite depoları bu çalışmanın geçici dizinindedir; gerçek işaretçi okunmaz.
@MainActor
enum ArchiveSwitchUITestFixture {
    private static var enabled: Bool {
        TestEnvironment.isUITesting && ProcessInfo.processInfo.arguments.contains("-ui-testing-archive-switch")
    }

    static func configure(directory: URL) throws {
        guard enabled else { return }
        let paths = ArchiveSwitchJournal.Paths(
            journalURL: directory.appendingPathComponent("ArchiveStoreSwitchJournal.json"),
            backupRoot: directory.appendingPathComponent("ArchiveRestoreBackups", isDirectory: true),
            recoveredRoot: directory.appendingPathComponent("RecoveredStores", isDirectory: true)
        )
        try FileManager.default.createDirectory(at: paths.backupRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.recoveredRoot, withIntermediateDirectories: true)
        ArchiveSwitchJournal.pathsOverride = paths
        // StoreRecovery'nin DEBUG anahtarı yalnız -ui-testing çalışmasına özeldir.
        guard StoreRecovery.selectedStoreKey == "uiTestingSelectedRecoveryStorePath" else {
            throw SchoolLibraryService.OperationError(message: "Arşiv UI testinin depo işaretçisi izole değil; hazırlık durduruldu.")
        }
        UserDefaults.standard.removeObject(forKey: StoreRecovery.selectedStoreKey)
        LibraryStoreSwitchStatus.shared.receipt = nil
        LoanHistoryStore.invalidateCache()
    }

    /// Yedek geçmişindeki normal ZIP yolu kullanılır; doğrudan servis geçişi veya
    /// sentetik başarı yayımlanmaz. İlk ZIP tek eserli ayrı bir geçmiş kataloğudur.
    static func seed(context: ModelContext) throws {
        guard enabled else { return }
        guard let paths = ArchiveSwitchJournal.pathsOverride, !context.hasChanges else {
            throw SchoolLibraryService.OperationError(message: "Arşiv UI testinin geçici yolları veya kaydedilmiş kataloğu eksik.")
        }
        let current = try FullArchive.snapshot(context: context)
        let beforeFingerprint = try ArchiveImportCoordinator.fingerprint(current)
        guard Set(current.books.map(\.title)) == Set(["Deneme Kitabı", "Geciken Kitap", "Bugün İade"]),
              current.books.count == 3, current.activeLoans.count == 2 else {
            throw SchoolLibraryService.OperationError(message: "Arşiv geçişi UI testi özgün üç eserli örneği gerektiriyor.")
        }
        let book = Book(
            id: UUID(uuidString: "A7100000-0000-4000-8000-000000000001")!,
            title: "Arşiv Deneme Eseri", author: "Arşiv Yazarı", quantity: 1,
            addedAt: Date(timeIntervalSince1970: 946_684_800)
        )
        var student = Student(name: "Arşiv Okuru", number: "202", className: "8/B")
        student.id = UUID(uuidString: "A7100000-0000-4000-8000-000000000002")!
        let seed = ArchiveContents(books: [book], students: [student], settings: current.settings)
        let zip = try FullArchive.buildVerified(seed)
        let verified = try FullArchive.readValidated(data: zip)
        guard try ArchiveImportCoordinator.fingerprint(verified) == ArchiveImportCoordinator.fingerprint(seed) else {
            throw SchoolLibraryService.OperationError(message: "UI test arşivi tekrar okunarak doğrulanamadı.")
        }
        let folder = paths.backupRoot.appendingPathComponent("switch-A7100000-0000-4000-8000-000000000003", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try zip.write(to: folder.appendingPathComponent("Islem-Oncesi-Tam-Arsiv.zip"), options: .atomic)
        // Raporun 'önce' kapsamı her zaman yanındaki ZIP ile aynıdır. UI gerçek
        // geçişi yapınca oluşan üç eserli yedek bu eski örnekten daha yeni sıralanır.
        let rows = ArchiveImportCoordinator.scope(before: seed, incoming: current, after: current)
        guard rows.count == 12 else {
            throw SchoolLibraryService.OperationError(message: "Arşiv UI testinin tam kapsam raporu güncellenmeli.")
        }
        let lines = ["Ayrı katalog açma: dogrulandi", "Yalnız izole UI kabul testi için oluşturulmuş eski katalog yedeği."]
            + rows.map { "\($0.title): önce \($0.before), seçilen arşiv \($0.incoming), yeni katalog \($0.after)" }
        try Data(lines.joined(separator: "\n").utf8).write(to: folder.appendingPathComponent("Katalog-Gecisi-Kapsam.txt"), options: .atomic)
        try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 946_684_800)], ofItemAtPath: folder.path)
        let listing = try ArchiveSwitchBackupStore.listing(root: paths.backupRoot)
        guard listing.failures.isEmpty, listing.entries.count == 1,
              listing.entries[0].books == 1, listing.entries[0].students == 1,
              try ArchiveImportCoordinator.fingerprint(FullArchive.snapshot(context: context)) == beforeFingerprint,
              !context.hasChanges else {
            throw SchoolLibraryService.OperationError(message: "UI test yedeğinin doğrulaması veya canlı örneğin değişmezlik denetimi başarısız.")
        }
    }
}
#endif
