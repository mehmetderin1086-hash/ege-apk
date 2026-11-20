import Testing
import Foundation
import SwiftData
@testable import _01

/// Sıralı: arşiv ve çöp kutusu testleri ortak klasör ayarlarını (statik) değiştirir;
/// paralel koşunca birbirlerinin klasörünü görüyorlardı.
@MainActor
@Suite(.serialized)
struct VeriGuvenligiTestleri {
    private func baglam() throws -> ModelContext {
        ModelContext(try KitapVeritabani.makeContainer(inMemory: true))
    }

    private func geciciKlasor() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vg-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: Yedek biçimi

    /// Eski sürüm yedeğinde düşüm/ders kitabı/seri alanları yoktu; yedek reddedilmemeli.
    @Test func eskiYedekEksikAlanlarlaCozulur() {
        let json = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"Çalıkuşu","author":"Reşat Nuri",
          "notes":"","addedAt":"2024-05-01T10:00:00Z"}]
        """
        let books = CatalogBackup.decode(Data(json.utf8))
        #expect(books.count == 1)
        #expect(books.first?.title == "Çalıkuşu")
        #expect(books.first?.isWithdrawn == false)
        #expect(books.first?.isTextbook == false)
        #expect(books.first?.series == nil)
    }

    @Test func yeniAlanlarGidipGelir() throws {
        let book = Book(title: "Harry Potter", author: "Rowling", accessionCode: "D-12", isWithdrawn: true,
                        withdrawnReason: "Yıpranmış", isTextbook: true, series: "Harry Potter", volume: 3,
                        tags: "fantastik, büyü", readingLevel: "Ortaokul", contentWarning: "Korku ögeleri")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoded = CatalogBackup.decode(try encoder.encode([book]))
        #expect(decoded.first?.volume == 3)
        #expect(decoded.first?.accessionCode == "D-12")
        #expect(decoded.first?.withdrawnReason == "Yıpranmış")
        #expect(decoded.first?.isTextbook == true)
        #expect(decoded.first?.tags == "fantastik, büyü")
        #expect(decoded.first?.contentWarning == "Korku ögeleri")
    }

    // MARK: Arşiv

    @Test func arsivOduncleriTasir() throws {
        let directory = geciciKlasor()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oldStudents = StudentStore.directoryOverride, oldMembers = MemberStore.directoryOverride
        let oldHistory = LoanHistoryStore.directoryOverride, oldSupport = ArchiveSettings.directoryOverride
        let oldSessions = ScanSessionStore.directoryOverride
        StudentStore.directoryOverride = directory; MemberStore.directoryOverride = directory
        LoanHistoryStore.directoryOverride = directory; ArchiveSettings.directoryOverride = directory
        ScanSessionStore.directoryOverride = directory.appendingPathComponent("TaramaOturumlari")
        defer {
            StudentStore.directoryOverride = oldStudents; MemberStore.directoryOverride = oldMembers
            LoanHistoryStore.directoryOverride = oldHistory; ArchiveSettings.directoryOverride = oldSupport
            ScanSessionStore.directoryOverride = oldSessions; LoanHistoryStore.invalidateCache()
            try? FileManager.default.removeItem(at: directory)
        }
        let book = Book(title: "Sefiller", author: "Hugo", coverData: Data([1, 2, 3]))
        let event = LoanEvent(bookID: book.id, bookTitle: book.title, person: "Ali", kind: .lent, date: .now)
        let loan = ArchivedLoan(id: UUID(), bookID: book.id, bookTitleSnapshot: book.title, studentName: "Ali",
                                studentClass: "7-A", loanedAt: .now, dueDate: .now.addingTimeInterval(86_400),
                                extensionCount: 1)
        let data = FullArchive.build(books: [book], loanEvents: [event], activeLoans: [loan])
        let contents = FullArchive.restoreContents(data: data)
        #expect(contents.books.first?.coverData == Data([1, 2, 3]))
        #expect(contents.loanEvents.map(\.id) == [event.id])
        #expect(contents.activeLoans.first?.id == loan.id)
        #expect(contents.activeLoans.first?.extensionCount == 1)

        // Geri yüklemede etkin ödünç, kitap katalogdaysa eklenir; ikinci kez eklenmez
        let ctx = try baglam()
        ctx.insert(CatalogBook(book: book))
        try ctx.save()
        _ = try ArchiveLoanRestorer.restoreAll(contents, context: ctx)
        _ = try ArchiveLoanRestorer.restoreAll(contents, context: ctx)
        let loans = try ctx.fetch(FetchDescriptor<ActiveLoan>())
        #expect(loans.count == 1)
        #expect(loans.first?.id == loan.id)
    }

    @Test func eskiArsivOduncsuzAcilir() {
        var writer = ZIPWriter()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        writer.add(name: "katalog.json", data: (try? encoder.encode([Book(title: "A", author: "B")])) ?? Data())
        let contents = FullArchive.restoreContents(data: writer.finalize())
        #expect(contents.books.count == 1)
        #expect(contents.loanEvents.isEmpty)
        #expect(contents.activeLoans.isEmpty)
    }

    // MARK: Çöp kutusu

    @Test func copKutusuGeriAlmaVeSureDolumu() throws {
        let klasor = geciciKlasor()
        TrashStore.directoryOverride = klasor
        defer {
            TrashStore.directoryOverride = nil
            try? FileManager.default.removeItem(at: klasor)
        }
        let ctx = try baglam()
        let eski = Book(title: "Eski", author: "X")
        let yeni = Book(title: "Yeni", author: "Y", coverData: Data([9]))
        TrashStore.add([eski], now: .now.addingTimeInterval(-31 * 86_400))
        TrashStore.add([yeni])
        #expect(TrashStore.count == 2)

        let kalanlar = TrashStore.entries()
        #expect(kalanlar.map(\.book.title) == ["Yeni"])   // 30 günü geçen temizlendi
        #expect(kalanlar.first?.daysLeft() == 30)

        #expect(TrashStore.restore(kalanlar[0], context: ctx))
        let katalog = try ctx.fetch(FetchDescriptor<CatalogBook>())
        #expect(katalog.map(\.title) == ["Yeni"])
        #expect(katalog.first?.coverData == Data([9]))
        #expect(TrashStore.count == 0)
    }

    // MARK: Günlük arşiv

    @Test func gunlukArsivZamanlamasi() {
        let bugun = Date.now
        #expect(AutoArchive.isDue(now: bugun, last: nil))
        #expect(!AutoArchive.isDue(now: bugun, last: bugun))
        #expect(AutoArchive.isDue(now: bugun, last: bugun.addingTimeInterval(-2 * 86_400)))
        let tarih = ISO8601DateFormatter().date(from: "2026-03-07T12:00:00Z")!
        #expect(AutoArchive.fileName(for: tarih).hasPrefix("KitapArsivi-2026-03-0"))
    }

    @Test func gunlukArsivSilmeOnayinaKadarKorunur() async throws {
        let klasor = geciciKlasor()
        AutoArchive.directoryOverride = klasor
        defer {
            AutoArchive.directoryOverride = nil
            try? FileManager.default.removeItem(at: klasor)
        }
        let ctx = try baglam()
        ctx.insert(CatalogBook(book: Book(title: "Nutuk", author: "Atatürk")))
        try ctx.save()
        for gun in 0..<9 {
            await AutoArchive.run(context: ctx, now: Date(timeIntervalSince1970: 1_700_000_000 + Double(gun) * 86_400))
        }
        let arsivler = AutoArchive.existingArchives()
        #expect(arsivler.count == 9)
        let archiveData = try Data(contentsOf: try #require(arsivler.first))
        #expect(ZIPReader.entries(in: archiveData).contains { $0.name == "manifest.json" })
        let icerik = try FullArchive.readValidated(data: archiveData)
        #expect(icerik.books.map(\.title) == ["Nutuk"])
    }

    // MARK: Bütünlük

    @Test func butunlukDenetimi() throws {
        let ctx = try baglam()
        let a = CatalogBook(book: Book(title: "A", author: "", isbn: "9789750718434", quantity: 0))
        let b = CatalogBook(book: Book(title: "B", author: "", isbn: "978-975-07-1843-4", quantity: 1))
        ctx.insert(a)
        ctx.insert(b)
        ctx.insert(ActiveLoan(bookID: b.id, bookTitleSnapshot: "B", studentName: "Ali", studentClass: "", dueDate: .now))
        ctx.insert(ActiveLoan(bookID: b.id, bookTitleSnapshot: "B", studentName: "Ayşe", studentClass: "", dueDate: .now))
        ctx.insert(ActiveLoan(bookID: UUID(), bookTitleSnapshot: "Silinmiş", studentName: "Can", studentClass: "", dueDate: .now))
        try ctx.save()

        let rapor = IntegrityCheck.run(context: ctx)
        #expect(rapor.bookCount == 2)
        #expect(rapor.fixedQuantities == 1)
        #expect(a.quantity == 1)
        #expect(rapor.orphanLoanTitles == ["Silinmiş"])
        #expect(rapor.overLoanedTitles == ["B"])
        #expect(rapor.duplicateISBNGroups == 1)
        #expect(!rapor.isClean)
    }

    // MARK: Sürümlü şema

    /// Geçiş planı olmadan oluşturulmuş (eski sürüm) veritabanı yeni kapla sorunsuz açılmalı.
    @Test func eskiVeritabaniYeniSemaylaAcilir() throws {
        let klasor = geciciKlasor()
        try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: klasor) }
        let url = klasor.appendingPathComponent("eski.store")

        do {
            let eskiSema = Schema([CatalogBook.self, ActiveLoan.self])
            let eski = try ModelContainer(for: eskiSema, configurations: ModelConfiguration(schema: eskiSema, url: url))
            let ctx = ModelContext(eski)
            ctx.insert(CatalogBook(book: Book(title: "Eski Kayıt", author: "Yazar")))
            try ctx.save()
        }

        let yeni = try KitapVeritabani.makeContainer(url: url)
        let ctx = ModelContext(yeni)
        #expect(try ctx.fetch(FetchDescriptor<CatalogBook>()).map(\.title) == ["Eski Kayıt"])
        ctx.insert(BookCopy(bookID: UUID(), accessionCode: "N-1"))
        ctx.insert(Reservation(bookID: UUID(), bookTitleSnapshot: "X", studentName: "Ali", studentClass: "5-B"))
        try ctx.save()
        #expect(try ctx.fetchCount(FetchDescriptor<BookCopy>()) == 1)
        #expect(try ctx.fetchCount(FetchDescriptor<Reservation>()) == 1)
    }
}

extension VeriGuvenligiTestleri {
    @Test func dosyayaAkitilanZipOkunur() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("akis-\(UUID()).zip")
        defer { try? FileManager.default.removeItem(at: url) }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        var zip = ZIPWriter(fileHandle: handle)
        zip.add(name: "a.txt", data: Data("merhaba".utf8))
        zip.add(name: "b/c.bin", data: Data([1, 2, 3, 4]))
        #expect(zip.finalize().isEmpty)   // dosya kipinde bellekte arşiv tutulmaz
        try handle.close()
        let girdiler = ZIPReader.entries(in: try Data(contentsOf: url))
        #expect(girdiler.map(\.name) == ["a.txt", "b/c.bin"])
        #expect(girdiler.last?.data == Data([1, 2, 3, 4]))
    }

    @Test func gunlukArsivArkaKapakVeKunyeyiTasir() async throws {
        let klasor = FileManager.default.temporaryDirectory.appendingPathComponent("gunluk-\(UUID())", isDirectory: true)
        AutoArchive.directoryOverride = klasor
        defer {
            AutoArchive.directoryOverride = nil
            try? FileManager.default.removeItem(at: klasor)
        }
        let ctx = ModelContext(try KitapVeritabani.makeContainer(inMemory: true))
        for i in 0..<250 {
            ctx.insert(CatalogBook(book: Book(title: "K\(i)", author: "Y", coverData: Data([UInt8(i % 255)]),
                                              backCoverData: i == 7 ? Data([9, 9]) : nil, imprintData: i == 7 ? Data([8]) : nil)))
        }
        try ctx.save()
        await AutoArchive.run(context: ctx, now: Date(timeIntervalSince1970: 1_800_000_000))
        let arsiv = try #require(AutoArchive.existingArchives().first)
        let icerik = try FullArchive.readValidated(data: Data(contentsOf: arsiv))
        #expect(icerik.books.count == 250)   // 100'lük sayfaların hepsi yazıldı
        let yedinci = try #require(icerik.books.first { $0.title == "K7" })
        #expect(yedinci.coverData == Data([7]))
        #expect(yedinci.backCoverData == Data([9, 9]))
        #expect(yedinci.imprintData == Data([8]))
        #expect(!((try? FileManager.default.contentsOfDirectory(atPath: klasor.path)) ?? []).contains { $0.hasPrefix("yaziliyor-") })
    }
}
