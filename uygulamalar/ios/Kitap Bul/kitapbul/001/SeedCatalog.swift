import Foundation

/// Uygulamayla birlikte gelen başlangıç kataloğu (Excel'den dönüştürülmüş 2.575 kitap
/// ve kapak görselleri). Yalnızca BİR KEZ içe aktarılır; sonraki açılışlarda atlanır.
nonisolated enum SeedCatalog {
    private static let importedKey = "seedCatalogImported"

    static var isImported: Bool {
        UserDefaults.standard.bool(forKey: importedKey)
    }

    static func markImported() {
        UserDefaults.standard.set(true, forKey: importedKey)
    }

    /// Uygulama paketindeki arşivden kitapları okur (kapaklar dahil).
    static func load() -> [Book] {
        guard let url = Bundle.main.url(forResource: "BaslangicKatalogu", withExtension: "zip") else {
            return []
        }
        return FullArchive.restore(from: url)
    }

    // MARK: - Demirbaş kodu geri yükleme

    private static let enrichmentKey = "seedEnrichmentApplied"

    static var isEnrichmentApplied: Bool {
        UserDefaults.standard.bool(forKey: enrichmentKey)
    }

    static func markEnrichmentApplied() {
        UserDefaults.standard.set(true, forKey: enrichmentKey)
    }

    /// ISBN → demirbaş kodu(ları) eşlemesi. Excel'den taşınan kitaplara,
    /// zaten katalogda oldukları için ISBN üzerinden geriye işlenir.
    static func loadAccessionCodes() -> [String: String] {
        guard let url = Bundle.main.url(forResource: "SeedEnrichment", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded
    }
}
