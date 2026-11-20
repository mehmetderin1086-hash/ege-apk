import Foundation
import SwiftData
import SwiftUI
import Observation

extension Notification.Name {
    nonisolated static let libraryStoreActivated = Notification.Name("LibraryStoreActivated")
}

/// Yayın yalnız depo+metadata doğrulaması ve işaretçi aktivasyonu tamamlandığında yapılır.
@MainActor
final class LibraryStoreActivation {
    let container: ModelContainer
    let receipt: ArchiveSwitchCoordinator.Receipt
    init(container: ModelContainer, receipt: ArchiveSwitchCoordinator.Receipt) { self.container = container; self.receipt = receipt }
}

@MainActor
@Observable
final class LibraryStoreSwitchStatus {
    static let shared = LibraryStoreSwitchStatus()
    var receipt: ArchiveSwitchCoordinator.Receipt?
}

@MainActor
enum ArchiveSwitchCoordinator {
    struct Preparation: Identifiable {
        let id = UUID()
        let before: ArchiveContents
        let incoming: ArchiveContents
        let expected: ArchiveContents
        let beforeFingerprint: String
        let preparedAt: Date
        let restoreSettings: Bool
        var rows: [ArchiveImportCoordinator.ScopeRow] { ArchiveImportCoordinator.scope(before: before, incoming: incoming, after: expected) }
    }
    struct Receipt: Identifiable {
        var id: String { backupURL.absoluteString }
        let backupURL: URL
        let scopeReportURL: URL
        let beforeBooks: Int
        let afterBooks: Int
        let summary: String
    }

    static func prepare(data: Data, context: ModelContext, restoreSettings: Bool = false, now: Date = .now) throws -> Preparation {
        try SchoolLibraryService.requireAdmin()
        guard !context.hasChanges else { throw failure("Önce açık değişiklikleri kaydedin; ayrı katalog henüz hazırlanmadı.") }
        let before = try FullArchive.snapshot(context: context), incoming = try FullArchive.readValidated(data: data)
        var selected = incoming
        // Sağlayıcı anahtarları/PIN/token yedeğe veya depolar arası aktarıma dahil değildir.
        selected.settings = before.settings
        if restoreSettings { selected.settings.merge(incoming.settings) { _, imported in imported } }
        if !restoreSettings {
            for name in ["KademeKurallari.json", "KayitliGorunumler.json"] {
                selected.supportingFiles[name] = before.supportingFiles[name]
            }
        }
        let expected = try ArchiveImportCoordinator.replacementTrial(selected, now: now)
        return Preparation(before: before, incoming: incoming, expected: expected, beforeFingerprint: try ArchiveImportCoordinator.fingerprint(before),
                           preparedAt: now, restoreSettings: restoreSettings)
    }

    /// Eski DB'ye yazılmaz/silinmez. Ham defter ve işaretçi geri alma yalnız bu
    /// işlemin kapsamını geri getirir; yeni depo geçerli olsa da yayın öncesi hata geri alınır.
    static func apply(_ preparation: Preparation, context: ModelContext, backupDirectory: URL? = nil,
                      beforePublish: ((ModelContainer) throws -> Void)? = nil,
                      publish: ((LibraryStoreActivation) -> Void)? = nil) throws -> Receipt {
        try SchoolLibraryService.requireAdmin()
        guard !context.hasChanges, try ArchiveImportCoordinator.fingerprint(FullArchive.snapshot(context: context)) == preparation.beforeFingerprint else {
            throw failure("Önizlemeden sonra canlı katalog, kişiler veya ayarlar değişti. Yeni önizleme gerekir; katalog değiştirilmedi.")
        }
        let root = try backupDirectory ?? ArchiveSwitchJournal.backupRoot()
        let directory = root.appendingPathComponent("switch-" + preparation.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let backup = directory.appendingPathComponent("Islem-Oncesi-Tam-Arsiv.zip")
        try FullArchive.buildVerified(preparation.before).write(to: backup, options: .atomic)
        guard try ArchiveImportCoordinator.fingerprint(FullArchive.readValidated(from: backup)) == preparation.beforeFingerprint else {
            throw failure("Önceki tam arşiv tekrar okunarak doğrulanamadı; ayrı katalog açılmadı.")
        }
        try FullArchive.buildVerified(preparation.incoming).write(to: directory.appendingPathComponent("Secilen-Arsiv.zip"), options: .atomic)
        try ArchiveImportCoordinator.captureRawMetadata(at: directory)
        let report = directory.appendingPathComponent("Katalog-Gecisi-Kapsam.txt")
        try writeReport(preparation, state: "hazir", at: report)
        let oldPointer = UserDefaults.standard.object(forKey: StoreRecovery.selectedStoreKey)
        let oldShared = KitapVeritabani.shared, oldWarning = LibrarySyncStatus.shared.warning
        let journalToken = try ArchiveSwitchJournal.begin(backupDirectory: directory, oldPointer: oldPointer, beforeFingerprint: preparation.beforeFingerprint)
        do {
            // Aynı prova zamanı ve bildirim kapalı: süresi dolan rezervasyonun
            // deterministik dönüşümü global bildirim veya JSON yan etkisiz denenmiştir.
            let restored = try StoreRecovery.restore(preparation.expected, reservationNow: preparation.preparedAt, notifyReservations: false, switchJournalToken: journalToken) { restoredContext in
                guard try ArchiveImportCoordinator.fingerprint(FullArchive.snapshot(context: restoredContext)) == ArchiveImportCoordinator.fingerprint(preparation.expected) else {
                    throw failure("Yeni kataloğun kişiler/kapaklar/açık borçlar dahil tam kapsamı provayla aynı değil; işaretçi etkinleştirilmedi.")
                }
            }
            try beforePublish?(restored)
            let receipt = Receipt(backupURL: backup, scopeReportURL: report, beforeBooks: preparation.before.books.count,
                                  afterBooks: preparation.expected.books.count,
                                  summary: "Arşiv ayrı katalog olarak açıldı. Önceki \(preparation.before.books.count) eserli katalog silinmedi; tam yedekten yeniden açılabilir. Yeni katalog: \(preparation.expected.books.count) eser, \(preparation.expected.activeLoans.count) açık ödünç.")
            try writeReport(preparation, state: "dogrulandi", at: report)
            guard let newPath = UserDefaults.standard.string(forKey: StoreRecovery.selectedStoreKey) else {
                throw failure("Doğrulanmış yeni katalog işaretçisi bulunamadı.")
            }
            try ArchiveSwitchJournal.markCommitted(token: journalToken, newPath: newPath)
            // Buradan sonra hata veren dosya/DB işlemi yoktur. Root ortamı yeni
            // container ile birlikte @Query/modelContext/intent kabını değiştirir.
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
                guard try ArchiveImportCoordinator.fingerprint(FullArchive.snapshot(context: context)) == preparation.beforeFingerprint else {
                    throw failure("Önceki kapsam geri alma denetiminden geçmedi.")
                }
                try writeReport(preparation, state: "geri_alindi", at: report)
                try ArchiveSwitchJournal.finishRollback(token: journalToken)
            } catch {
                throw ArchiveImportCoordinator.ApplyError(message: "Ayrı katalog etkinleştirilemedi; eski depo korunuyor, metadata geri alımı tamamlanamadı. Doğrulanmış tam yedeği Veri Kurtarma ile açın.", backupURL: backup)
            }
            throw ArchiveImportCoordinator.ApplyError(message: "Ayrı katalog açılmadı; eski işaretçi, canlı DB, kişiler ve ayarlar geri getirildi. \(original.localizedDescription)", backupURL: backup)
        }
    }

    static func writeReport(_ preparation: Preparation, state: String, at url: URL) throws {
        let lines = ["Ayrı katalog açma: \(state)", "Önceki DB silinmez. İşlem öncesi tam ZIP ayrı saklanır."]
            + preparation.rows.map { "\($0.title): önce \($0.before), seçilen arşiv \($0.incoming), yeni katalog \($0.after)" }
        try Data(lines.joined(separator: "\n").utf8).write(to: url, options: .atomic)
    }
    private static func failure(_ text: String) -> SchoolLibraryService.OperationError { .init(message: text) }
}

/// Normal çalışan Yönetim'den de erişilir; eski arşiv operasyonlarının güvenli
/// merge edilemediği durumda izole katalog alternatifi kaybolmaz.
struct ArchiveImportChoiceView: View {
    @Environment(\.dismiss) private var dismiss
    let data: Data
    let context: ModelContext
    @State private var mergePreview: ArchiveImportCoordinator.Preparation?
    @State private var switchPreview: ArchiveSwitchCoordinator.Preparation?
    @State private var error: String?
    @State private var includeSettings = false
    @State private var preparing = false

    var body: some View {
        NavigationStack {
            List {
                Section("Arşivi nasıl kullanmak istiyorsunuz?") {
                    Text("Önce etkisini inceleyin. Her iki yol da canlı değişiklikten önce doğrulanmış mevcut tam yedeği alır.")
                    Button("Mevcut kataloğa ekleme önizlemesi") {
                        guard !preparing else { return }; preparing = true
                        Task { @MainActor in
                            defer { preparing = false }
                            do { mergePreview = try await ArchiveImportCoordinator.prepareAsync(data: data, context: context, restoreSettings: includeSettings); self.error = nil }
                            catch { self.error = error.localizedDescription }
                        }
                    }.frame(minHeight: 44).accessibilityIdentifier("archive.import.merge").disabled(preparing)
                    Text("Mevcut kayıtlar ve açık borçlar korunur. Farklı eski operasyon durumu canlı geçmişe eklenmez.").font(.subheadline)
                    Button("Arşivi ayrı katalog olarak aç") {
                        guard !preparing else { return }; preparing = true
                        Task { @MainActor in
                            defer { preparing = false }
                            do { switchPreview = try await ArchiveSwitchCoordinator.prepareAsync(data: data, context: context, restoreSettings: includeSettings); self.error = nil }
                            catch { self.error = error.localizedDescription }
                        }
                    }.frame(minHeight: 44).accessibilityIdentifier("archive.import.separate").disabled(preparing)
                    Text("Seçilen arşivin eser, kişi, nüsha, geçmiş ve açık borçlarının tümü yeni ayrı depoda açılır. Önceki katalog silinmez; tam yedeğinden aynı menü ile yeniden açabilirsiniz.").font(.subheadline)
                    Toggle("Arşivdeki güvenli ayarları da kullan", isOn: $includeSettings).disabled(preparing)
                    if preparing { ProgressView("Arşiv önizlemesi arka planda doğrulanıyor…") }
                }
                if let error { Section("İşlem başlamadı") { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) } }
            }
            .navigationTitle("Arşiv geri yükleme")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
            .sheet(item: $mergePreview) { preview in
                ArchiveImportReviewView(preparation: preview, onSettingsChange: { selected in
                    try await ArchiveImportCoordinator.prepareAsync(data: data, context: context, restoreSettings: selected)
                }, onApply: { try await ArchiveImportCoordinator.applyAsync($0, context: context) })
            }
            .sheet(item: $switchPreview) { preview in ArchiveSwitchReviewView(preparation: preview, context: context) }
        }
    }
}

struct ArchiveSwitchReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let preparation: ArchiveSwitchCoordinator.Preparation
    let context: ModelContext
    @State private var confirm = false
    @State private var applying = false
    @State private var error: String?
    @State private var failureBackup: URL?

    var body: some View {
        NavigationStack {
            List {
                Section("Yeni ayrı katalog") {
                    Text("İzole prova tamamlandı. Bu işlem görünür kataloğu seçilen arşivin tam durumuna geçirir; eski DB silinmez. Önceki veriler ayrıca doğrulanmış tam ZIP yedeğinde tutulur.")
                    Text(preparation.restoreSettings ? "Güvenli arşiv ayarları kullanılacak." : "Mevcut güvenli ayarlar korunacak.")
                }
                Section("Önceki katalog / seçilen arşiv / yeni katalog") {
                    ForEach(preparation.rows) { row in
                        VStack(alignment: .leading, spacing: 6) { Text(row.title).font(.headline); Text("\(row.before) / \(row.incoming) / \(row.after)").font(.subheadline) }
                            .accessibilityElement(children: .combine)
                    }
                }
                if let error {
                    Section("İşlem tamamlanmadı") {
                        Text(error).foregroundStyle(.red)
                        if let failureBackup { ShareLink(item: failureBackup) { Label("Korunan tam yedeği paylaş", systemImage: "square.and.arrow.up") }.frame(minHeight: 44) }
                    }
                }
                Section {
                    Button(applying ? "Yedek ve ayrı katalog doğrulanıyor…" : "Önceki veriyi yedekle ve ayrı kataloğu aç") { confirm = true }
                        .frame(minHeight: 44).disabled(applying || error != nil).accessibilityIdentifier("archive.switch.apply")
                } footer: { Text("Başarıdan sonra eski tam yedeği paylaşabilir, Yönetim → Arşiv geri yükleme → Ayrı katalog ile yeniden açabilirsiniz.") }
            }
            .navigationTitle("Ayrı katalog önizlemesi")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("İptal") { dismiss() }.disabled(applying) } }
            .interactiveDismissDisabled(applying)
            .confirmationDialog("Seçilen arşivi ayrı katalog olarak aç", isPresented: $confirm, titleVisibility: .visible) {
                Button("Doğrulanmış yedekten sonra aç") {
                    applying = true
                    Task { @MainActor in
                        await Task.yield()
                        defer { applying = false }
                        do { _ = try await ArchiveSwitchCoordinator.applyAsync(preparation, context: context) }
                        catch { self.error = error.localizedDescription; failureBackup = (error as? ArchiveImportCoordinator.ApplyError)?.backupURL }
                    }
                }
                Button("Vazgeç", role: .cancel) { }
            } message: { Text("Görünür katalog \(preparation.before.books.count) eserden \(preparation.expected.books.count) eserli ayrı depoya geçecek. Eski DB silinmez; önceki tam ZIP saklanır.") }
        }
    }
}
