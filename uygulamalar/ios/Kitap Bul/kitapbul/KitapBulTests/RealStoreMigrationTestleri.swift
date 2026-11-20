import Testing
import Foundation
import SwiftData
@testable import _01

@MainActor @Suite(.serialized)
struct RealStoreMigrationTestleri {
    nonisolated private struct Expected: Decodable { var count: Int; var quantity: Int; var ids: [String] }
    /// `KITAPBUL_REAL_STORE_FIXTURE`: küçültülmüş/anonimleştirilmiş depo klasörünün yolu ya da
    /// test paketine kaynak olarak eklenmiş `PlanMigrationFixture` için `bundle`. 'Cihaz Kabul' planı
    /// bunu ayarlar; değişken yoksa test (Hızlı planda) atlanır.
    nonisolated static var fixtureSetting: String? {
        let value = ProcessInfo.processInfo.environment["KITAPBUL_REAL_STORE_FIXTURE"]
        return (value?.isEmpty ?? true) ? nil : value
    }
    nonisolated static var fixtureURL: URL? {
        guard let setting = fixtureSetting else { return nil }
        let url = setting == "bundle"
            ? Bundle(for: BundleAnchor.self).resourceURL?.appendingPathComponent("PlanMigrationFixture")
            : URL(fileURLWithPath: setting, isDirectory: true)
        guard let url, FileManager.default.fileExists(atPath: url.appendingPathComponent("expected.json").path) else { return nil }
        return url
    }
    private final class BundleAnchor {}

    @Test(.tags(.cihaz), .enabled(if: RealStoreMigrationTestleri.fixtureSetting != nil, "KITAPBUL_REAL_STORE_FIXTURE ayarlı değil"), .timeLimit(.minutes(3)))
    func migrateCopiedEgeStoreWithoutLosingBookIDsOrQuantity() throws {
        let fixture = try #require(Self.fixtureURL, "KITAPBUL_REAL_STORE_FIXTURE ayarlı ama expected.json bulunamadı")
        let expected = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: fixture.appendingPathComponent("expected.json")))
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("real-store-migration-" + UUID().uuidString)
        try FileManager.default.copyItem(at: fixture, to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let container = try KitapVeritabani.makeContainer(url: temporary.appendingPathComponent("default.store"))
        let context = container.mainContext
        context.autosaveEnabled = false
        let before = try context.fetch(FetchDescriptor<CatalogBook>())
        #expect(before.count == expected.count)
        #expect(before.reduce(0) { $0 + ($1.quantity ?? 1) } == expected.quantity)
        #expect(before.map { $0.id.uuidString }.sorted() == expected.ids)
        let beforeBooks = before.map(\.book)
        try SchoolLibraryService.migrateLegacyLoans(context: context)
        try SchoolLibraryService.refreshReservations(context: context)
        try context.save()
        let after = try context.fetch(FetchDescriptor<CatalogBook>())
        #expect(after.map { $0.id.uuidString }.sorted() == expected.ids)
        #expect(after.reduce(0) { $0 + ($1.quantity ?? 1) } == expected.quantity)
        let byID = Dictionary(uniqueKeysWithValues: beforeBooks.map { ($0.id, $0) })
        for book in after {
            let previous = try #require(byID[book.id])
            #expect(book.title == previous.title && book.author == previous.author && book.isbn == previous.isbn)
            #expect(book.coverData == previous.coverData && book.notes == previous.notes)
            #expect(book.cabinet == previous.cabinet && book.shelf == previous.shelf)
        }
        let summary: [String: Any] = ["source": "Ege verified backup copy", "countBefore": expected.count, "countAfter": after.count,
            "copiesBefore": expected.quantity, "copiesAfter": after.reduce(0) { $0 + ($1.quantity ?? 1) }, "allIDsPreserved": true,
            "titlesAuthorsISBNNotesCoversPlacesPreserved": true]
        Attachment.record(try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]), named: "Ege-Migration.json")
    }
}
