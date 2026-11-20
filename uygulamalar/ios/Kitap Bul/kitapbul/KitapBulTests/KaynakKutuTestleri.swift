import Testing
import Foundation
import CoreGraphics
@testable import _01

@MainActor
@Suite(.serialized)
struct KaynakKutuTestleri {
    @Test func sinirlariKirparVeGecersizKutuyuReddeder() throws {
        let bounds = try ScanBoxBounds.validated([-30, 100, 1040, 1200])
        #expect(bounds.values == [0, 100, 1000, 1000])
        #expect(bounds.rect.minX == 0.1)
        #expect(bounds.rect.maxY == 1)
        for invalid in [[0.0, 1, 3], [0, 0, 0, 100], [400, 10, 100, 20], [0, 900, 1000, 100], [Double.nan, 0, 100, 100], [0, 0, Double.infinity, 100], [-10, 0, -1, 500]] {
            #expect(throws: ScanBoxEditError.self) { try ScanBoxBounds.validated(invalid) }
        }
    }

    @Test func kenarKontrolleriDigerKenariGecemezVeVazgecKaydiDegistirmez() throws {
        let id = UUID()
        var session = ScanSession(kind: .photo, title: "Kaynak")
        session.sourceImages = [Data([1])]
        session.bookSources = [id: .init(photoIndex: 0, box: [100, 200, 700, 800], method: "gemini", confidence: 0.8)]
        let original = session.bookSources?[id]
        var draft = ScanBoxEditDraft(id: id, box: original?.box)
        draft.setEdge(0, to: 950)
        draft.setEdge(3, to: -50)
        draft.setEdge(2, to: .nan)
        #expect(draft.bounds.values == [699, 200, 700, 201])
        _ = try ScanBoxBounds.validated(draft.bounds.values)
        // Onay çağrılmadan düzenleme kopyası atılır; oturumdaki kaynak aynı kalır.
        #expect(session.bookSources?[id] == original)
        let confirmed = try ScanBoxEditEngine.applyPhoto([50, 150, 900, 950], bookID: id, to: session)
        #expect(confirmed.bookSources?[id]?.box == [50, 150, 900, 950])
        #expect(session.bookSources?[id] == original)
    }

    @Test func onaylananKutununKesitiVeKaynagiDiskteKalir() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        ScanSessionStore.directoryOverride = directory
        defer { ScanSessionStore.directoryOverride = nil; try? FileManager.default.removeItem(at: directory) }
        let pending = Book(title: "Bekleyen", author: "Yazar", coverData: Data([1]))
        var session = ScanSession(kind: .photo, title: "Masa fotoğrafı")
        session.pendingBooks = [pending]
        session.sourceImages = [Data([20])]
        session.bookSources = [pending.id: .init(photoIndex: 0, box: [0, 0, 500, 500], method: "barcode", confidence: 1)]
        try ScanSessionStore.save(session)
        let updated = try ScanBoxEditEngine.applyPhoto([100, 100, 900, 900], bookID: pending.id, to: session, coverData: Data([7, 8]))
        try ScanSessionStore.save(updated)
        let restored = try #require(ScanSessionStore.allVerified().first)
        #expect(restored.bookSources?[pending.id]?.box == [100, 100, 900, 900])
        #expect(restored.bookSources?[pending.id]?.boxEditedManually == true)
        #expect(restored.bookSources?[pending.id]?.method == "barcode")
        #expect(restored.pendingBooks.first?.coverData == Data([7, 8]))
        #expect(BookFieldMetadata.decode(restored.pendingBooks.first?.fieldMetadata)["coverData"]?.isLocked == true)
        #expect(session.pendingBooks.first?.coverData == Data([1]))
    }

    @Test func kayitHatasiEskiOturumuVeTaslaginiKorur() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ScanSessionStore.directoryOverride = directory
        defer { ScanSessionStore.directoryOverride = nil; try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        var session = ScanSession(kind: .photo, title: "Başlangıç")
        session.sourceImages = [Data([1])]
        session.bookSources = [id: .init(photoIndex: 0, box: [0, 0, 500, 500], method: "gemini", confidence: 0.9)]
        try ScanSessionStore.save(session)
        let updated = try ScanBoxEditEngine.applyPhoto([10, 20, 600, 700], bookID: id, to: session)
        let blocked = root.appendingPathComponent("not-a-directory")
        try Data([1]).write(to: blocked)
        ScanSessionStore.directoryOverride = blocked
        #expect(throws: (any Error).self) { try ScanSessionStore.save(updated) }
        ScanSessionStore.directoryOverride = directory
        #expect(try ScanSessionStore.allVerified().first?.bookSources?[id]?.box == [0, 0, 500, 500])
        #expect(updated.bookSources?[id]?.box == [10, 20, 600, 700]) // yeniden denenecek düzeltme kaybolmaz
    }

    @Test func kaydedilmisIslemdeYalnizKaynakKanitiDegisir() throws {
        let pending = Book(title: "Kaydedildi", author: "Yazar", quantity: 4, coverData: Data([3]))
        var session = ScanSession(kind: .photo, title: "Makbuzlu kaynak")
        session.pendingBooks = [pending]
        session.sourceImages = [Data([1])]
        session.savedOperationIDs = [pending.id]
        session.mergedCopies = [UUID(): 4]
        session.bookSources = [pending.id: .init(photoIndex: 0, box: [0, 0, 500, 500], method: "gemini", confidence: 0.9)]
        let updated = try ScanBoxEditEngine.applyPhoto([0, 0, 900, 900], bookID: pending.id, to: session, coverData: Data([9]))
        #expect(updated.pendingBooks == session.pendingBooks)
        #expect(updated.savedOperationIDs == session.savedOperationIDs)
        #expect(updated.mergedCopies == session.mergedCopies)
        #expect(updated.bookSources?[pending.id]?.box == [0, 0, 900, 900])
    }

    @Test func rafDilimiDuzenlemesiDogruKitabaVeKoordinatKaynaginaBaglanir() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        ScanSessionStore.directoryOverride = directory
        defer { ScanSessionStore.directoryOverride = nil; try? FileManager.default.removeItem(at: directory) }
        var first = GeminiBookFields(title: "Birinci", author: "Yazar")
        first.box_2d = [0, 0, 1000, 400]
        var second = GeminiBookFields(title: "İkinci", author: "Yazar")
        second.box_2d = [0, 400, 1000, 1000]
        var tile = ShelfTileReading(jpeg: Data([1]), photo: 1, row: 2, column: 3, overlapsAbove: false)
        tile.books = [first, second]
        var session = ScanSession(kind: .shelf, title: "Raf")
        session.shelfResult = ShelfScanResult(books: [first, second], tiles: [tile])
        let updated = try ScanBoxEditEngine.applyShelf([50, 450, 950, 990], tileID: tile.id, bookIndex: 1, to: session, coverData: Data([5]))
        try ScanSessionStore.save(updated)
        let restored = try #require(ScanSessionStore.allVerified().first)
        let key = ShelfScanEngine.signature(second)
        let id = try #require(restored.shelfBookKeys?[key])
        #expect(restored.reviewedShelfBooks?[key]?.box_2d == [50, 450, 950, 990])
        #expect(restored.reviewedShelfBooks?[ShelfScanEngine.signature(first)] == nil)
        #expect(restored.bookSources?[id]?.tileID == tile.id)
        #expect(restored.bookSources?[id]?.photoIndex == 1)
        #expect(restored.pendingBooks.first?.coverData == Data([5]))
        #expect(restored.shelfResult?.tiles.first?.books == [first, second]) // ham model kanıtı korunur
        #expect(throws: ScanBoxEditError.self) {
            try ScanBoxEditEngine.applyShelf([0, 0, 500, 500], tileID: tile.id, bookIndex: 2, to: session)
        }
    }
}
