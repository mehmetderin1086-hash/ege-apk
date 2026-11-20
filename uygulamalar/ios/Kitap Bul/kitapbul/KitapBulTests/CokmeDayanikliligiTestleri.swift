import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import _01

// Telefondan çekilen çökme kayıtlarına (20–23 Eylül 2026) karşılık gelen koruma testleri:
//  • 0x8BADF00D açılış bekçisi: Excel/ZIP arşivi ana iş parçacığında üretiliyordu
//  • SIGABRT: SwiftData arama koşulu SQL'e çevrilemedi
//  • UInt16/UInt32 dönüşümleri: 65.535 giriş / 4 GB sınırında ZIP yazıcı çöker
//  • Silinmiş SwiftData modeline yazma ("model instance was invalidated")

// MARK: - ZIP yazıcı sınırları

@MainActor
struct ZIPSinirTestleri {
    /// CRC-32 tablo tabanlı sürüme geçti; sonuç standart test vektörüyle aynı olmalı.
    @Test func crc32BilinenDegerlerleUyusur() {
        #expect(ZIPCRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(ZIPCRC32.checksum(Data()) == 0)
        #expect(ZIPCRC32.checksum(Data("a".utf8)) == 0xE8B7_BE43)
    }

    /// 65.535'ten fazla giriş eklenirse uygulama ÇÖKMEMELİ; fazlası atlanmalı.
    @Test func girisSayisiSiniriAsilirsaCokmezAtlar() {
        var writer = ZIPWriter()
        let limit = ZIPWriter.maxEntryCount
        let extra = 5
        let payload = Data([1, 2, 3])
        for index in 0..<(limit + extra) {
            writer.add(name: "k/\(index)", data: payload)
        }
        #expect(writer.skippedCount == extra)

        let archive = writer.finalize()
        #expect(!archive.isEmpty)

        // Yazılan arşiv, kendi okuyucumuzla eksiksiz geri okunmalı
        let entries = ZIPReader.entries(in: archive)
        #expect(entries.count == limit)
        #expect(entries.first?.name == "k/0")
        #expect(entries.last?.name == "k/\(limit - 1)")
        #expect(entries.last?.data == payload)
    }

    /// 4 GB sınırını aşacak veri, bellek ayırmadan reddedilmeli.
    @Test func boyutSiniriOncedenReddedilir() {
        let writer = ZIPWriter()
        #expect(writer.canAdd(name: "kapak.png", dataCount: 10))
        #expect(!writer.canAdd(name: "dev.bin", dataCount: ZIPWriter.maxArchiveSize + 1))
        #expect(!writer.canAdd(name: "dev.bin", dataCount: ZIPWriter.maxArchiveSize - 10))
    }

    /// Ad uzunluğu 16 bitlik alana sığmıyorsa giriş atlanır (UInt16(x) çökmesi yerine).
    @Test func cokUzunAdAtlanir() {
        var writer = ZIPWriter()
        let longName = String(repeating: "a", count: Int(UInt16.max) + 1)
        let longAdded = writer.add(name: longName, data: Data([1]))
        let normalAdded = writer.add(name: "normal.txt", data: Data([1]))
        #expect(!longAdded)
        #expect(normalAdded)
        #expect(writer.skippedCount == 1)
        #expect(ZIPReader.entries(in: writer.finalize()).count == 1)
    }
}

// MARK: - Arşiv / Excel üretimi

@MainActor
struct DisaAktarimDayaniklilikTestleri {
    private func kucukPNG(_ seed: UInt8) -> Data {
        Data([137, 80, 78, 71, 13, 10, 26, 10, seed, seed, seed, seed])
    }

    /// Boş katalogla arşiv ve Excel üretimi çökmemeli.
    @Test func bosKatalogArsiviVeExceliUretilir() throws {
        let archive = FullArchive.build(books: [])
        let entries = ZIPReader.entries(in: archive).map(\.name)
        #expect(entries.contains("katalog.json"))
        #expect(entries.contains("manifest.json"))
        #expect(try FullArchive.readValidated(data: archive).books.isEmpty)

        let workbook = ExcelWorkbookBuilder.makeWorkbook(books: [])
        let names = ZIPReader.entries(in: workbook).map(\.name)
        #expect(names.contains("[Content_Types].xml"))
        #expect(names.contains("xl/worksheets/sheet1.xml"))
    }

    /// Excel çıktısı artık ortak ZIP yazıcıyı kullanıyor; kapaklar medya olarak yazılmalı.
    @Test func excelKapaklariMedyaOlarakYazar() {
        let books = [
            Book(title: "Kapaklı", author: "Yazar", coverData: kucukPNG(7)),
            Book(title: "Kapaksız", author: "Yazar"),
            Book(title: "JPEG Kapak", author: "Yazar", coverData: Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2]))
        ]
        let workbook = ExcelWorkbookBuilder.makeWorkbook(books: books)
        let names = Set(ZIPReader.entries(in: workbook).map(\.name))
        #expect(names.contains("xl/media/image1.png"))
        #expect(names.contains("xl/media/image3.jpg"))
        #expect(!names.contains("xl/media/image2.png"))
        #expect(names.contains("xl/drawings/drawing1.xml"))
    }

    /// Başlangıç kataloğu ölçeğinde (binlerce kapaklı kitap) geri yükleme,
    /// kare karmaşıklığa dönüp açılış bekçisini tetiklememeli.
    @Test func binlerceKapakliKitapHizliGeriYuklenir() throws {
        let count = 3000
        var books: [Book] = []
        books.reserveCapacity(count)
        for index in 0..<count {
            books.append(
                Book(title: "Kitap \(index)", author: "Yazar \(index % 50)",
                     coverData: kucukPNG(UInt8(truncatingIfNeeded: index)))
            )
        }
        let archive = FullArchive.build(books: books)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("buyuk-arsiv-\(UUID().uuidString).zip")
        try archive.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let clock = ContinuousClock()
        var restored: [Book] = []
        let elapsed = clock.measure {
            restored = FullArchive.restore(from: url)
        }
        #expect(restored.count == count)
        #expect(restored.allSatisfy { $0.coverData != nil })
        // Eski O(n×m) eşleştirme bu boyutta saniyeler sürüyordu; sözlükle anlık olmalı.
        // Eşik, yavaş simülatör/CI'da yanlış alarm vermesin diye bol tutuldu.
        #expect(elapsed < .seconds(8), "Geri yükleme çok yavaş: \(elapsed)")
    }

    /// Eksik/kesik arşivler (yarım kalan kopya) çökmeden boş sonuç vermeli.
    @Test func kesikArsivCokmez() {
        let books = [Book(title: "Tek", author: "Yazar", coverData: kucukPNG(1))]
        let archive = FullArchive.build(books: books)
        for cut in [1, 10, 29, 30, 31, 60, archive.count / 2, archive.count - 1] where cut < archive.count {
            let truncated = archive.prefix(cut)
            _ = ZIPReader.entries(in: Data(truncated))
        }
        // Rastgele çöp veri
        var rng = SystemRandomNumberGenerator()
        let garbage = Data((0..<512).map { _ in UInt8.random(in: 0...255, using: &rng) })
        _ = ZIPReader.entries(in: garbage)
    }
}

// MARK: - SwiftData arama koşulu

@MainActor
struct AramaKosuluDayaniklilikTestleri {
    private func baglam() throws -> ModelContext {
        let container = try ModelContainer(
            for: CatalogBook.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(CatalogBook(book: Book(title: "İstanbul Hatırası", author: "Ahmet Ümit", isbn: "9789750718533")))
        context.insert(CatalogBook(book: Book(title: "%100 Matematik", author: "Bilinmiyor", isbn: nil)))
        context.insert(CatalogBook(book: Book(title: "O'nun Hikâyesi", author: "Yazar_Adı", isbn: "")))
        try context.save()
        return context
    }

    /// SQL joker karakterleri, tırnaklar, Türkçe harfler, emoji ve çok uzun metin —
    /// hiçbiri SwiftData'nın SQL üretiminde istisna fırlatmamalı (23 Eylül çökmesi).
    @Test(arguments: [
        "%", "_", "%100", "'", "\"", "O'nun", "İ", "ı", "ğüşöç", "📚", "\\", ";", "--",
        "a b  c", String(repeating: "x", count: 5000), "istanbul", "Yazar_Adı", "hatıra"
    ])
    func sorunluTerimlerCokmez(term: String) throws {
        let context = try baglam()
        let predicate = CatalogQueryView<EmptyView>.searchPredicate(term: term)
        _ = try context.fetch(FetchDescriptor<CatalogBook>(predicate: predicate))
    }

    @Test func jokerKarakterlerHarfiyenEslesir() throws {
        let context = try baglam()
        func titles(_ term: String) throws -> [String] {
            let predicate = CatalogQueryView<EmptyView>.searchPredicate(term: term)
            return try context.fetch(FetchDescriptor<CatalogBook>(predicate: predicate)).map(\.title)
        }
        #expect(try titles("%100") == ["%100 Matematik"])
        #expect(try titles("O'nun") == ["O'nun Hikâyesi"])
        #expect(try titles("Yazar_Adı") == ["O'nun Hikâyesi"])
        #expect(try titles("hatıra").contains("İstanbul Hatırası"))
        // Noktasız ı / aksan yazılmadan da bulunur (ön süzme bellek içi süzmeyi boşa çıkarmaz)
        #expect(try titles("hatirasi") == ["İstanbul Hatırası"])
        #expect(try titles("umit") == ["İstanbul Hatırası"])
        #expect(try titles("📚").isEmpty)
    }
}

// MARK: - ISBN normalizasyonu (toplu içe aktarma mükerrer kontrolü)

@MainActor
struct ISBNNormalizasyonTestleri {
    /// Excel'in bozduğu ("9.78E+12"), kısa ya da harfli ISBN'ler boş dizgeye düşer;
    /// içe aktarma bu boş değeri "aynı ISBN" saymamalı (yoksa alakasız bir kitabın
    /// adedi artar, yeni kitap kaybolur). Hiçbiri çökmemeli.
    @Test(arguments: ["9.78E+12", "978", "", "ISBN YOK", "12345678901234567890", "9789750718534", "ğüşiöç"])
    func bozukISBNBosDoner(value: String) {
        #expect(ISBNFormatter.normalize(value).isEmpty)
    }

    @Test func gecerliISBNlerAyniAnahtaraDuser() {
        #expect(ISBNFormatter.normalize("978-975-07-1853-3") == "9789750718533")
        #expect(ISBNFormatter.normalize("9789750718533") == ISBNFormatter.normalize("975-07-1853-3"))
    }

    /// "X" kontrol haneli ISBN-10 atılmaz; ISBN-13 karşılığına çevrilir.
    @Test func xKontrolHaneliISBN10Cevrilir() {
        #expect(ISBNFormatter.normalize("975-8431-07-X") == ISBNFormatter.normalize("9758431070"))
        #expect(ISBNFormatter.normalize("080442957x").hasPrefix("978080442957"))
        #expect(ISBNFormatter.isValidISBN13(ISBNFormatter.normalize("080442957X")))
        // X başka yerdeyse ya da hane eksikse ISBN sayılmaz
        #expect(ISBNFormatter.normalize("X12345678").isEmpty)
        #expect(ISBNFormatter.normalize("12345678X").isEmpty)
    }
}

// MARK: - Kalıcı veritabanı

@MainActor
struct KaliciVeritabaniTestleri {
    /// Uygulamanın gerçek şeması diske yazılıp aynı şemayla YENİDEN açılabilmeli;
    /// açılamazsa MyApp bellek içi kaba düşer ve tüm katalog görünmez olur.
    @Test func semaDiskeYazilipYenidenAcilir() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kalici-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        let schema = Schema([CatalogBook.self, ActiveLoan.self])

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url)
            )
            let context = ModelContext(container)
            let book = CatalogBook(book: Book(title: "Kalıcı Kitap", author: "Yazar", quantity: 2))
            context.insert(book)
            context.insert(ActiveLoan(
                bookID: book.id, bookTitleSnapshot: book.title,
                studentName: "Ali", studentClass: "5-A", dueDate: .now.addingTimeInterval(86_400)
            ))
            try context.save()
        }

        // İkinci açılış: aynı dosya, aynı şema — geçiş gerekmez, veri yerinde olmalı
        let reopened = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
        let context = ModelContext(reopened)
        let books = try context.fetch(FetchDescriptor<CatalogBook>())
        let loans = try context.fetch(FetchDescriptor<ActiveLoan>())
        #expect(books.map(\.title) == ["Kalıcı Kitap"])
        #expect(loans.count == 1)
        #expect(loans.first?.bookID == books.first?.id)
    }

    /// Ağ beklemesi sırasında silinen kitabı tanıyan koruma: silinmiş model
    /// `isDeleted` ya da `modelContext == nil` ile ayırt edilebilmeli.
    @Test func silinmisModelAyirtEdilir() throws {
        let container = try ModelContainer(
            for: CatalogBook.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let book = CatalogBook(book: Book(title: "Silinecek", author: "Yazar"))
        context.insert(book)
        try context.save()
        #expect(!book.isDeleted && book.modelContext != nil)

        context.delete(book)
        #expect(book.isDeleted || book.modelContext == nil)
        try context.save()
        #expect(book.isDeleted || book.modelContext == nil)
    }

    /// Ödünç hesapları hiçbir girdi için negatif ya da taşan sonuç vermemeli.
    @Test func bosNushaSayisiNegatifOlmaz() throws {
        let container = try ModelContainer(
            for: CatalogBook.self, ActiveLoan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let book = CatalogBook(book: Book(title: "Tek Nüsha", author: "Yazar", quantity: nil))
        context.insert(book)
        let loans = (0..<3).map {
            ActiveLoan(bookID: book.id, bookTitleSnapshot: book.title,
                       studentName: "Öğrenci \($0)", studentClass: "6-B", dueDate: .now)
        }
        loans.forEach { context.insert($0) }
        #expect(LoanAvailability.availableCopies(for: book, activeLoans: loans) == 0)
        book.quantity = 0
        #expect(LoanAvailability.availableCopies(for: book, activeLoans: loans) == 0)
        book.quantity = 5
        #expect(LoanAvailability.availableCopies(for: book, activeLoans: loans) == 2)
    }
}
