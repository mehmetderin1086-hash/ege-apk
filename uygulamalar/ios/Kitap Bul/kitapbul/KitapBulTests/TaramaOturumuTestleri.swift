import Testing
import Foundation
import SwiftData
@testable import _01

private actor TileReadCounter {
    var inputs: [Data] = []
    func record(_ data: Data) { inputs.append(data) }
    func values() -> [Data] { inputs }
}

@MainActor
@Suite(.serialized)
struct TaramaOturumuTestleri {
    private struct DiskFailure: Error {}
    private func container() throws -> ModelContainer {
        let schema = KitapVeritabani.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        container.mainContext.autosaveEnabled = false
        return container
    }

    @Test func diskHatasindaYeniKitapKatalogdaKalmaz() throws {
        let container = try container()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        #expect(throws: DiskFailure.self) {
            try CatalogSaveEngine.save(Book(title: "Yeni", author: "Yazar"), context: context, catalog: [], persist: { throw DiskFailure() })
        }
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<CatalogBook>()) == 0)
    }

    @Test func diskHatasindaMiktarArtisiGeriDoner() throws {
        let container = try container()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let existing = CatalogBook(book: Book(title: "Kitap", author: "Yazar", quantity: 2))
        context.insert(existing)
        try context.save()
        #expect(throws: DiskFailure.self) {
            try CatalogSaveEngine.save(Book(title: "Kitap", author: "Yazar", quantity: 4), context: context, catalog: [existing], persist: { throw DiskFailure() })
        }
        #expect(existing.quantity == 2)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<CatalogBook>()).first?.quantity == 2)
    }

    @Test func dortNushaEklemeVeGeriAlmaGercekDeltayiKullanir() throws {
        let container = try container()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let existing = CatalogBook(book: Book(title: "Kitap", author: "Yazar", quantity: 2))
        context.insert(existing)
        try context.save()
        let outcome = try CatalogSaveEngine.save(Book(title: "Kitap", author: "Yazar", quantity: 4), context: context, catalog: [existing])
        guard case .merged(let id, let added) = outcome else { Issue.record("Nüshalar birleşmeli"); return }
        #expect(added == 4)
        #expect(existing.quantity == 6)
        try CatalogSaveEngine.undo(insertedIDs: [], mergedCopies: [id: added], catalog: [existing], context: context)
        #expect(existing.quantity == 2)
    }

    @Test func partiHatasindaIlkMiktarVeYeniKayitBirlikteGeriDoner() throws {
        let container = try container()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let existing = CatalogBook(book: Book(title: "Kitap", author: "Yazar", quantity: 2))
        context.insert(existing)
        try context.save()
        #expect(throws: DiskFailure.self) {
            try CatalogSaveEngine.saveBatch([
                Book(title: "Kitap", author: "Yazar", quantity: 4),
                Book(title: "Başka Eser", author: "Başka Yazar")
            ], context: context, catalog: [existing], mergeWithinBatch: true, persist: { throw DiskFailure() })
        }
        try context.save()
        #expect(existing.quantity == 2)
        #expect(try context.fetchCount(FetchDescriptor<CatalogBook>()) == 1)
    }

    @Test func farkliISBNliAyniEserAyriBaskiKalir() throws {
        let container = try container()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let original = CatalogBook(book: Book(title: "Aynı Eser", author: "Yazar", isbn: "9780140449136"))
        context.insert(original)
        try context.save()
        let outcome = try CatalogSaveEngine.save(Book(title: "Aynı Eser", author: "Yazar", isbn: "9780140449266"), context: context, catalog: [original])
        guard case .inserted = outcome else { Issue.record("Farklı ISBN ayrı baskı olmalı"); return }
        #expect(try context.fetchCount(FetchDescriptor<CatalogBook>()) == 2)
    }

    @Test func odunctekiAdedinAltinaInenDuzenlemeReddedilir() throws {
        let container = try container()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let book = CatalogBook(book: Book(title: "Kitap", author: "Yazar", quantity: 3))
        context.insert(book)
        context.insert(ActiveLoan(bookID: book.id, bookTitleSnapshot: book.title, studentName: "A", studentClass: "5/A", dueDate: .now))
        context.insert(ActiveLoan(bookID: book.id, bookTitleSnapshot: book.title, studentName: "B", studentClass: "5/A", dueDate: .now))
        try context.save()
        var edit = book.book
        edit.quantity = 1
        #expect(throws: CatalogSaveEngine.SaveError.self) { try CatalogSaveEngine.save(edit, context: context, catalog: [book]) }
        #expect(book.quantity == 3)
    }

    @Test func ortusenVideoKareleriNushaSayisiniSisirmez() {
        var fields = GeminiBookFields(title: "Sinekli Bakkal", author: "Halide Edip")
        fields.copies = 4
        let frames = Array(repeating: [fields], count: 4)
        #expect(ShelfScanEngine.combinePhotos(frames, relation: .overlapping).first?.nusha == 4)
        #expect(ShelfScanEngine.combinePhotos(frames, relation: .distinct).first?.nusha == 16)
    }

    @Test func yenidenDenemeYalnizBasarisizDilimiOkur() async throws {
        var previous = ShelfScanResult()
        var first = ShelfTileReading(jpeg: Data([1]), photo: 0, row: 0, column: 0, overlapsAbove: false)
        first.status = .read
        first.books = [GeminiBookFields(title: "Başarılı", author: "Bir")]
        var second = ShelfTileReading(jpeg: Data([2]), photo: 0, row: 0, column: 1, overlapsAbove: false)
        second.status = .failed
        second.errorMessage = "Ağ kesildi"
        previous.tiles = [first, second]
        let counter = TileReadCounter()
        let result = try await ShelfScanEngine.scanDetailed(images: [], retrying: previous, reader: { data in
            await counter.record(data)
            return ShelfScanReply(books: [GeminiBookFields(title: "Yeniden Okunan", author: "İki")])
        })
        #expect(await counter.values() == [Data([2])])
        #expect(result.successfulTileCount == 2)
        #expect(result.failedTileCount == 0)
        #expect(result.books.count == 2)
    }

    @Test func oturumKaydiKaynakDilimVeHataIleGeriGelir() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        ScanSessionStore.directoryOverride = directory
        defer { ScanSessionStore.directoryOverride = nil; try? FileManager.default.removeItem(at: directory) }
        var session = ScanSession(kind: .shelf, title: "B/3")
        var result = ShelfScanResult()
        var tile = ShelfTileReading(jpeg: Data([1, 2, 3]), photo: 0, row: 0, column: 0, overlapsAbove: false)
        tile.status = .failed
        tile.errorMessage = "Ağ kesildi"
        result.tiles = [tile]
        session.shelfResult = result
        session.mergedCopies = [UUID(): 4]
        try ScanSessionStore.save(session)
        let loaded = try #require(ScanSessionStore.all().first)
        #expect(loaded.shelfResult?.tiles.first?.jpeg == tile.jpeg)
        #expect(loaded.shelfResult?.failedTileCount == 1)
        #expect(loaded.mergedCopies.values.reduce(0, +) == 4)
    }

    @Test func makbuzVeAdetAyniIslemdeYazilirTekrarDenemeAdediArtirmaz() throws {
        let container = try container()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let existing = CatalogBook(book: Book(title: "Kitap", author: "Yazar", quantity: 2))
        context.insert(existing)
        try context.save()
        let draft = Book(title: "Kitap", author: "Yazar", quantity: 4)
        var session = ScanSession(kind: .photo, title: "Kesilen oturum")
        session.pendingBooks = [draft]
        _ = try CatalogSaveEngine.save(draft, context: context, catalog: [existing])
        // JSON günlüğü güncellenmeden kapanma: eski oturum ve SwiftData makbuzundan toparlanır.
        let recovered = try ScanSessionStore.reconciled(session, context: context)
        #expect(recovered.pendingBooks.isEmpty)
        #expect(recovered.mergedCopies[existing.id] == 4)
        let repeated = try CatalogSaveEngine.save(draft, context: context, catalog: [existing])
        guard case .merged(_, let delta) = repeated else { Issue.record("Önceden işlenen kayıt tanınmalı"); return }
        #expect(delta == 0)
        #expect(existing.quantity == 6)
        #expect(try context.fetchCount(FetchDescriptor<ScanWriteReceipt>()) == 1)
        try CatalogSaveEngine.undo(insertedIDs: [], mergedCopies: recovered.mergedCopies, catalog: [existing],
            context: context, operationIDs: recovered.savedOperationIDs ?? [])
        #expect(existing.quantity == 2)
        #expect(try context.fetchCount(FetchDescriptor<ScanWriteReceipt>()) == 0)
    }

    @Test func basarisizPartiMakbuzBirakmazYenidenDenemeKayitlariTamEkler() throws {
        let container = try container()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let draft = Book(title: "Kitap", author: "Yazar", quantity: 4)
        #expect(throws: DiskFailure.self) {
            try CatalogSaveEngine.saveBatch([draft], context: context, catalog: [], mergeWithinBatch: true,
                persist: { throw DiskFailure() })
        }
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<ScanWriteReceipt>()) == 0)
        let outcomes = try CatalogSaveEngine.saveBatch([draft], context: context, catalog: [], mergeWithinBatch: true)
        #expect(outcomes.count == 1)
        #expect(try context.fetch(FetchDescriptor<CatalogBook>()).first?.quantity == 4)
    }

    @Test func kayitSonrasiOduncVerilinceGeriAlmaKitabiSilmez() throws {
        let container = try container()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let draft = Book(title: "Kitap", author: "Yazar")
        _ = try CatalogSaveEngine.save(draft, context: context, catalog: [])
        let book = try #require(context.fetch(FetchDescriptor<CatalogBook>()).first)
        context.insert(ActiveLoan(bookID: book.id, bookTitleSnapshot: book.title, studentName: "Ali", studentClass: "5/A", dueDate: .now))
        try context.save()
        #expect(throws: CatalogSaveEngine.SaveError.self) {
            try CatalogSaveEngine.undo(insertedIDs: [book.id], mergedCopies: [:], catalog: [book], context: context, operationIDs: [draft.id])
        }
        #expect(try context.fetchCount(FetchDescriptor<CatalogBook>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<ActiveLoan>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<ScanWriteReceipt>()) == 1)
    }

    @Test func gorevliYeniKitapEkleyebilirMevcutAdediDegistiremez() throws {
        let container = try container()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let existing = CatalogBook(book: Book(title: "Kitap", author: "Yazar", quantity: 2))
        context.insert(existing)
        try context.save()
        let previousLock = YetkiDurumu.shared.kilitEtkin
        YetkiDurumu.shared.kilitEtkin = true
        YetkiDurumu.shared.gorevliyeGec()
        defer { YetkiDurumu.shared.kilitEtkin = previousLock }
        #expect(throws: CatalogSaveEngine.SaveError.self) {
            try CatalogSaveEngine.save(Book(title: "Kitap", author: "Yazar", quantity: 4), context: context, catalog: [existing])
        }
        #expect(existing.quantity == 2)
        _ = try CatalogSaveEngine.save(Book(title: "Başka Eser", author: "Diğer"), context: context, catalog: [existing])
        #expect(try context.fetchCount(FetchDescriptor<CatalogBook>()) == 2)
    }

    @Test func rezervasyonVarkenYeniEklemeGeriAlinmaz() throws {
        let container = try container()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let draft = Book(title: "Kitap", author: "Yazar")
        _ = try CatalogSaveEngine.save(draft, context: context, catalog: [])
        let book = try #require(context.fetch(FetchDescriptor<CatalogBook>()).first)
        context.insert(Reservation(bookID: book.id, bookTitleSnapshot: book.title, studentName: "Ali", studentClass: "5/A"))
        try context.save()
        #expect(throws: CatalogSaveEngine.SaveError.self) {
            try CatalogSaveEngine.undo(insertedIDs: [book.id], mergedCopies: [:], catalog: [book], context: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<CatalogBook>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Reservation>()) == 1)
    }

    @Test func rafSayimiOduncNushayiEksikSaymazVeBaskiyiKaristirmaz() throws {
        let container = try container()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let book = CatalogBook(book: Book(title: "Kitap", author: "Yazar", isbn: "9780140449136", quantity: 4, shelf: "3", cabinet: "B"))
        context.insert(book)
        let loan = ActiveLoan(bookID: book.id, bookTitleSnapshot: book.title, studentName: "Ali", studentClass: "5/A", dueDate: .now)
        context.insert(loan)
        try context.save()
        var fields = GeminiBookFields(title: "Kitap", author: "Yazar")
        fields.isbn = "9780140449136"
        fields.copies = 3
        let correct = ShelfScanEngine.compare([fields], catalog: [book], cabinet: "B", shelf: "3", loans: [loan])
        #expect(correct.found.count == 1)
        #expect(correct.quantityDifferences.isEmpty)
        fields.isbn = "9780140449266"
        let edition = ShelfScanEngine.compare([fields], catalog: [book], cabinet: "B", shelf: "3", loans: [loan])
        #expect(edition.unknown.count == 1)
        #expect(edition.quantityDifferences.first?.expected == 3)
        #expect(edition.quantityDifferences.first?.seen == 0)
    }

    @Test func bozukOturumTumArsivOkumasiniSessizceEksiltmez() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        ScanSessionStore.directoryOverride = directory
        defer { ScanSessionStore.directoryOverride = nil; try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("bozuk JSON".utf8).write(to: directory.appendingPathComponent("bozuk.json"))
        #expect(throws: (any Error).self) { try ScanSessionStore.allVerified() }
    }
}
