import Testing
import Foundation
import SwiftData
@testable import _01

@MainActor
@Suite(.serialized)
struct AlanBakimSayimTestleri {
    private struct DiskFailure: Error {}
    private func isolated(_ work: (ModelContainer, ModelContext, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("field-journal-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oldJournal = FieldMaintenanceStore.directoryOverride
        let oldSupport = ArchiveSettings.directoryOverride
        FieldMaintenanceStore.directoryOverride = directory
        ArchiveSettings.directoryOverride = directory
        defer {
            FieldMaintenanceStore.directoryOverride = oldJournal; ArchiveSettings.directoryOverride = oldSupport
            try? FileManager.default.removeItem(at: directory)
        }
        let container = try KitapVeritabani.makeContainer(inMemory: true)
        let context = container.mainContext; context.autosaveEnabled = false
        try work(container, context, directory)
    }

    @Test func alanBakimiYenidenAcilincaGeriAlinirVeDigerAlanKilitleriKorunur() throws {
        try isolated { container, context, _ in
            var source = Book(title: "Eser", author: "Y", publisher: "Eski yayınevi", quantity: 2)
            source.fieldMetadata = BookFieldMetadata.encode(["notes": .init(source: "manual", isLocked: true)])
            let book = CatalogBook(book: source); context.insert(book); try context.save()
            let result = try #require(try FieldMaintenanceService.apply(field: .publisher, allowedValues: ["Eski yayınevi"], canonical: "Yeni yayınevi", context: context))
            let reopened = ModelContext(container); reopened.autosaveEnabled = false
            let receipt = try #require(try FieldMaintenanceService.latest(context: reopened))
            #expect(receipt.id == result.receipt.id && receipt.changes.first?.bookID == source.id)
            let saved = try #require(try reopened.fetch(FetchDescriptor<CatalogBook>()).first)
            saved.notes = "Daha sonra yazılan not"; try reopened.save()
            _ = try FieldMaintenanceService.undo(receiptID: receipt.id, context: reopened)
            #expect(saved.publisher == "Eski yayınevi" && saved.quantity == 2)
            #expect(saved.notes == "Daha sonra yazılan not")
            #expect(BookFieldMetadata.decode(saved.fieldMetadata)["publisher"] == nil)
            #expect(BookFieldMetadata.decode(saved.fieldMetadata)["notes"]?.isLocked == true)
            #expect(try FieldMaintenanceService.latest(context: reopened) == nil)
        }
    }

    @Test func sonradanDegisenTekAlanTumGeriAlmayiEngeller() throws {
        try isolated { _, context, _ in
            let one = CatalogBook(book: Book(title: "Bir", author: "Y", publisher: "A"))
            let two = CatalogBook(book: Book(title: "İki", author: "Y", publisher: "B"))
            context.insert(one); context.insert(two); try context.save()
            let receipt = try #require(try FieldMaintenanceService.apply(field: .publisher, allowedValues: ["A", "B"], canonical: "Ortak", context: context)).receipt
            two.publisher = "Sonraki baskı"; try context.save()
            #expect(throws: SchoolLibraryService.OperationError.self) { try FieldMaintenanceService.undo(receiptID: receipt.id, context: context) }
            #expect(one.publisher == "Ortak" && two.publisher == "Sonraki baskı")
            #expect(try FieldMaintenanceStore.allVerified().last?.state == .committed)
        }
    }

    @Test func yalnizKaynakKilitDegisimiDeStaleSayilir() throws {
        try isolated { _, context, _ in
            let book = CatalogBook(book: Book(title: "Eser", author: "Eski")); context.insert(book); try context.save()
            let receipt = try #require(try FieldMaintenanceService.apply(field: .author, allowedValues: ["Eski"], canonical: "Yeni", context: context)).receipt
            book.fieldMetadata = BookFieldMetadata.encode(["author": .init(source: "manual", isLocked: false)])
            try context.save()
            #expect(throws: SchoolLibraryService.OperationError.self) { try FieldMaintenanceService.undo(receiptID: receipt.id, context: context) }
            #expect(book.author == "Yeni" && BookFieldMetadata.decode(book.fieldMetadata)["author"]?.isLocked == false)
        }
    }

    @Test func dbHatasindaAlanVeGeriAlmaDurumuRollbackOlur() throws {
        try isolated { _, context, _ in
            let book = CatalogBook(book: Book(title: "Eser", author: "Y", category: "Eski")); context.insert(book); try context.save()
            #expect(throws: DiskFailure.self) {
                try FieldMaintenanceService.apply(field: .category, allowedValues: ["Eski"], canonical: "Yeni", context: context, persist: { throw DiskFailure() })
            }
            #expect(book.category == "Eski")
            #expect(try FieldMaintenanceStore.allVerified().last?.state == .cancelled)
            let receipt = try #require(try FieldMaintenanceService.apply(field: .category, allowedValues: ["Eski"], canonical: "Yeni", context: context)).receipt
            #expect(throws: DiskFailure.self) { try FieldMaintenanceService.undo(receiptID: receipt.id, context: context, persist: { throw DiskFailure() }) }
            #expect(book.category == "Yeni")
            #expect(try FieldMaintenanceStore.allVerified().last?.state == .committed)
        }
    }

    @Test func kesilenIslemOnceSonraVeGeriAlmaDurumlariylaUzlasir() throws {
        try isolated { _, context, _ in
            let book = CatalogBook(book: Book(title: "Eser", author: "Y", publisher: "Eski")); context.insert(book); try context.save()
            let evidence = BookFieldEvidence(source: "manual", isLocked: true)
            var receipt = FieldMaintenanceReceipt(field: .publisher, changes: [
                .init(bookID: book.id, title: book.title, before: "Eski", after: "Yeni", beforeEvidence: nil, afterEvidence: evidence)
            ])
            try FieldMaintenanceStore.replaceVerified([receipt])
            #expect(try FieldMaintenanceService.reconcile(context: context).first?.state == .cancelled)
            try FieldMaintenanceStore.replaceVerified([receipt])
            book.publisher = "Yeni"; book.fieldMetadata = BookFieldMetadata.encode(["publisher": evidence]); try context.save()
            #expect(try FieldMaintenanceService.reconcile(context: context).first?.state == .committed)
            receipt.state = .undoPrepared; try FieldMaintenanceStore.replaceVerified([receipt])
            book.publisher = "Eski"; book.fieldMetadata = nil; try context.save()
            let completed = try #require(try FieldMaintenanceService.reconcile(context: context).first)
            #expect(completed.state == .undone && completed.undoneAt != nil)
        }
    }

    @Test func bozukGunlukBakimOncesiKorunurVeArsivBirlesimiKimligiKontrolEder() throws {
        try isolated { _, context, directory in
            let book = CatalogBook(book: Book(title: "Eser", author: "Y", publisher: "Eski")); context.insert(book); try context.save()
            let bad = Data("bozuk günlük".utf8)
            let url = directory.appendingPathComponent(FieldMaintenanceStore.fileName)
            try bad.write(to: url)
            #expect(throws: (any Error).self) { try FieldMaintenanceService.apply(field: .publisher, allowedValues: ["Eski"], canonical: "Yeni", context: context) }
            let retained = try Data(contentsOf: url)
            #expect(book.publisher == "Eski" && retained == bad)
            try FileManager.default.removeItem(at: url)
            let receipt = try #require(try FieldMaintenanceService.apply(field: .publisher, allowedValues: ["Eski"], canonical: "Yeni", context: context)).receipt
            let data = try FieldMaintenanceStore.encode([receipt])
            #expect(try FieldMaintenanceStore.validate(FieldMaintenanceStore.merge(existing: data, incoming: data)).count == 1)
            var conflict = receipt; conflict.state = .undoPrepared
            #expect(throws: FullArchive.ValidationError.self) { try FieldMaintenanceStore.merge(existing: data, incoming: FieldMaintenanceStore.encode([conflict])) }
            let archive = try FullArchive.readValidated(data: FullArchive.buildVerified(ArchiveContents(books: [book.book], supportingFiles: [FieldMaintenanceStore.fileName: data])))
            #expect(try FieldMaintenanceStore.validate(archive.supportingFiles[FieldMaintenanceStore.fileName]!).first?.id == receipt.id)
            #expect(ArchiveSettings.supportingFileNames.contains(FieldMaintenanceStore.fileName))
            #expect(try FieldMaintenanceStore.validate(ArchiveSettings.supportingFilesVerified()[FieldMaintenanceStore.fileName]!).first?.id == receipt.id)
        }
    }

    private func expected(id: String, title: String, isbn: String? = "9786053607021", count: Int = 1, unresolved: Int? = nil) -> InventoryExpectedItem {
        InventoryExpectedItem(id: UUID(uuidString: id)!, title: title, author: "İşık Yılmaz", isbn: isbn, quantity: count,
                              location: "Raf 1", stock: .init(total: count, available: count), copies: [], unresolvedLoans: unresolved)
    }
    @Test func isbnTamEslesmesiSayilanListesineGirerAmaNushaDogrulandiDenmez() {
        let one = expected(id: "00000000-0000-4000-8000-000000000001", title: "Çağdaş Türk Edebiyatı", count: 2)
        let entries = InventoryCountResult.entries(expected: [one], scanned: ["9786053607021": 2])
        #expect(entries.first?.scanned == 2 && entries.first?.statusTitle == "Adet eşleşti")
        #expect(entries.first?.confidenceNote(hasSnapshot: true).contains("ayırt edilemez") == true)
        #expect(InventoryCountResult.search(entries, query: "cagdas").count == 1)
        #expect(InventoryCountResult.search(entries, query: "9786053607021").count == 1)
        #expect(InventoryCountResult.search(entries, query: "bulunamaz").isEmpty)
    }
    @Test func ayniIsbnHavuzuTekilleDemirbasVeElleSayimdanSonraDagitilir() {
        var one = expected(id: "00000000-0000-4000-8000-000000000001", title: "Bir", count: 2)
        let two = expected(id: "00000000-0000-4000-8000-000000000002", title: "İki", count: 2)
        let copy = InventoryCopySnapshot(id: UUID(), bookID: one.id, accessionCode: "DB-1")
        one.copies = [copy]
        let entries = InventoryCountResult.entries(expected: [two, one], scanned: ["copy:" + copy.id.uuidString: 8, "book:" + one.id.uuidString: 1, "9786053607021": 3])
        #expect(entries.first?.scanned == 2 && entries.first?.isbnCopies == 0)
        #expect(entries.last?.scanned == 3 && entries.last?.statusTitle == "Fazla 1")
        #expect(entries.reduce(0) { $0 + $1.scanned } == 5)
        #expect(InventoryCountResult.search(entries, query: "DB-1").first?.id == one.id)
    }
    @Test func bilinmeyenBaskaKonumVeSifirSayimSayilanKitapGibiGosterilmez() {
        let book = expected(id: "00000000-0000-4000-8000-000000000001", title: "Eser", unresolved: 1)
        let untouched = InventoryCountResult.entries(expected: [book], scanned: ["outside:" + book.id.uuidString: 1, "kayıtsız": 2])
        #expect(untouched.filter { $0.scanned > 0 }.isEmpty)
        let matched = InventoryCountResult.entries(expected: [book], scanned: ["9786053607021": 1])
        #expect(matched.first?.confidenceNote(hasSnapshot: true).contains("belirsiz") == true)
        #expect(matched.first?.confidenceNote(hasSnapshot: false).contains("sabitlenmemiş") == true)
    }
}
