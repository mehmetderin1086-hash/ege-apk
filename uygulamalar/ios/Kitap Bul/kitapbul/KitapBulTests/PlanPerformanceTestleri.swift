import Testing
import Foundation
import SwiftData
import UIKit
@testable import _01

@MainActor
@Suite(.serialized)
struct PlanPerformanceTestleri {
    @Test(.tags(.performans), .timeLimit(.minutes(3)), arguments: [2_500, 10_000])
    func measuredCatalogSearchFilterAndArchive(count: Int) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("benchmark-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try KitapVeritabani.makeContainer(url: root.appendingPathComponent("benchmark.store"))
        let context = store.mainContext
        context.autosaveEnabled = false
        var books: [CatalogBook] = []
        for index in 0..<count {
            let book = CatalogBook(book: Book(title: "Kitap \(index) \(index % 7 == 0 ? "Türk Edebiyatı" : "Macera")",
                author: "Yazar \(index % 120)", category: index % 2 == 0 ? "Roman" : "Hikâye", quantity: 1 + index % 3,
                shelf: "\(index % 8)", cabinet: "\(index % 4)"))
            context.insert(book); books.append(book)
        }
        try context.save()
        func milliseconds<T>(_ operation: () throws -> T) rethrows -> (T, Double) {
            let start = ContinuousClock.now
            let value = try operation(), elapsed = ContinuousClock.now - start
            return (value, Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
        }
        var searches: [Double] = []
        for index in 0..<30 {
            let query = index.isMultiple(of: 2) ? "türk edebiyatı" : "macera"
            let predicate = try #require(KitapAramaKosulu.predicate(for: query))
            let (_, elapsed) = try milliseconds { try context.fetchCount(FetchDescriptor<CatalogBook>(predicate: predicate)) }
            searches.append(elapsed)
        }
        var filter = KitapFiltresi(); filter.kategori = "Roman"
        let (filtered, filterMS) = milliseconds { filter.uygula(books, oduncSayilari: [:], siralama: .ad) }
        #expect(filtered.count == count / 2)
        let (_, csvMS) = milliseconds { KitapCSV.olustur(books, sutunlar: KitapSutunu.varsayilan) }
        let (archive, archiveMS) = try milliseconds { try FullArchive.buildVerified(ArchiveContents(books: books.map(\.book))) }
        let (_, validateMS) = try milliseconds { try FullArchive.readValidated(data: archive) }
        searches.sort()
        let p95 = searches[Int((Double(searches.count) * 0.95).rounded(.up)) - 1]
#if targetEnvironment(simulator)
        let environment = "iOS Simulator / synthetic no-cover catalog"
#else
        let environment = "Physical \(UIDevice.current.model) / iOS \(UIDevice.current.systemVersion) / synthetic no-cover catalog"
#endif
        let result: [String: Any] = ["count": count, "environment": environment, "searchP95MS": p95,
            "filterMS": filterMS, "csvMS": csvMS, "archiveMS": archiveMS, "archiveValidationMS": validateMS, "archiveBytes": archive.count]
        let report = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        Attachment.record(report, named: "Benchmark-\(count).json")
        let searchLimit = PerformansTabani.sinir(300), filterLimit = PerformansTabani.sinir(500)
        #expect(p95 <= searchLimit, "Yerel arama p95 \(p95) ms; sınır \(searchLimit) ms")
        #expect(filterMS <= filterLimit, "Filtre \(filterMS) ms; sınır \(filterLimit) ms")
    }
}
