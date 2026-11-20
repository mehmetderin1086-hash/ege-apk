import Foundation

/// Yan dosya, üst veri ve arşiv klasörlerinin tek kaynağı. Canlı değerler bugünkü yerleşimi
/// (Documents) korur; testler ve UI fikstürleri `current` değerini geçici dizine çevirir.
@MainActor
struct StoreLocations: Equatable {
    var supportingDirectory: URL
    var metadataDirectory: URL
    var archivesDirectory: URL
    /// nil ise `UserDefaults.standard`.
    var defaultsSuite: String?

    var defaults: UserDefaults {
        defaultsSuite.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    static var live: StoreLocations {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return StoreLocations(supportingDirectory: documents, metadataDirectory: documents,
                              archivesDirectory: documents.appendingPathComponent("Arsivler", isDirectory: true),
                              defaultsSuite: nil)
    }

    static var current: StoreLocations = .live

    /// Tek köklü yerleşim: her şey `root` altında.
    static func isolated(root: URL, defaultsSuite: String? = nil) -> StoreLocations {
        StoreLocations(supportingDirectory: root, metadataDirectory: root,
                       archivesDirectory: root.appendingPathComponent("Arsivler", isDirectory: true),
                       defaultsSuite: defaultsSuite)
    }

    /// `includeSharedStores: false` yalnız öğrenci/üye/geçmiş/destek/tarama klasörlerini bağlar; çöp, otomatik
    /// arşiv, kademe kuralı ve sayım yollarına dokunmaz (başka testlerin paralel kullandığı alanlar).
    /// `current` değerini değiştirir ve mevcut `directoryOverride` alanlarını aynı klasörlere bağlar;
    /// geri dönüşte hepsi önceki değerine döner. Eski alanlara bağlanan tek yer burasıdır.
    @discardableResult
    static func install(_ locations: StoreLocations, includeSharedStores: Bool = true) -> @MainActor () -> Void {
        let previous = current
        let students = StudentStore.directoryOverride, members = MemberStore.directoryOverride
        let history = LoanHistoryStore.directoryOverride, support = ArchiveSettings.directoryOverride
        let sessions = ScanSessionStore.directoryOverride, inventory = InventorySessionStore.directoryOverride
        let trash = TrashStore.directoryOverride, archives = AutoArchive.directoryOverride, rules = GradeLoanRuleStore.directoryOverride
        current = locations
        StudentStore.directoryOverride = locations.metadataDirectory
        MemberStore.directoryOverride = locations.metadataDirectory
        LoanHistoryStore.directoryOverride = locations.metadataDirectory
        ArchiveSettings.directoryOverride = locations.supportingDirectory
        ScanSessionStore.directoryOverride = locations.supportingDirectory.appendingPathComponent("TaramaOturumlari", isDirectory: true)
        if includeSharedStores {
            InventorySessionStore.directoryOverride = locations.supportingDirectory
            TrashStore.directoryOverride = locations.supportingDirectory.appendingPathComponent("CopKutusu", isDirectory: true)
            AutoArchive.directoryOverride = locations.archivesDirectory
            GradeLoanRuleStore.directoryOverride = locations.supportingDirectory
        }
        LoanHistoryStore.invalidateCache()
        return {
            current = previous
            StudentStore.directoryOverride = students; MemberStore.directoryOverride = members
            LoanHistoryStore.directoryOverride = history; ArchiveSettings.directoryOverride = support
            ScanSessionStore.directoryOverride = sessions
            if includeSharedStores {
                InventorySessionStore.directoryOverride = inventory
                TrashStore.directoryOverride = trash; AutoArchive.directoryOverride = archives
                GradeLoanRuleStore.directoryOverride = rules
            }
            LoanHistoryStore.invalidateCache()
        }
    }
}
