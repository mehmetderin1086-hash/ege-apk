import Testing
import Foundation
import SwiftData
@testable import _01

// Yeni AI motorları: canlı dikte ayrıştırıcı, sesle düzeltme sezgisi, takma ad, ödünç/iade,
// raf sayımı karşılaştırması, haftalık rapor, arama dizini, hızlı mod kararı, zenginleştirme.

@MainActor
struct CanliDikteTestleri {
    @Test func alanlarVirguldenAyrisir() {
        let kaydi = VoiceBookEngine.quickParse("Kürk Mantolu Madonna, Sabahattin Ali, YKY, iki adet, B dolabı, üçüncü raf")
        #expect(kaydi.title == "Kürk Mantolu Madonna")
        #expect(kaydi.author == "Sabahattin Ali")
        #expect(kaydi.publisher == "YKY")
        #expect(kaydi.quantity == 2)
        #expect(kaydi.cabinet == "B")
        #expect(kaydi.shelf == "3")
    }

    @Test func rakamliAdetVeRafNumarasi() {
        let kaydi = VoiceBookEngine.quickParse("Şeker Portakalı, 5 tane, raf 4")
        #expect(kaydi.title == "Şeker Portakalı")
        #expect(kaydi.quantity == 5)
        #expect(kaydi.shelf == "4")
        #expect(kaydi.author == nil)
    }

    @Test func duzeltmeCumlesiTaninir() {
        #expect(VoiceBookEngine.looksLikeEdit("yazarı Orhan Pamuk yap"))
        #expect(VoiceBookEngine.looksLikeEdit("adet üç olsun"))
        #expect(VoiceBookEngine.looksLikeEdit("rafı dört"))
        #expect(!VoiceBookEngine.looksLikeEdit("Kuyucaklı Yusuf Sabahattin Ali"))
    }
}

@MainActor
struct TakmaAdTestleri {
    @Test func sorudakiAdlarGizlenirVeGeriCevrilir() {
        let aliases = PersonAliases()
        let safe = aliases.pseudonymize("Ali Veli Kaya'ya Kürk Mantolu Madonna'yı ver, Ali de beklesin",
                                        names: ["Ali Veli Kaya", "Ali"])
        #expect(!safe.contains("Veli"))
        #expect(safe.contains("Öğrenci 1"))
        #expect(aliases.restore(in: safe).contains("Ali Veli Kaya"))
    }

    @Test func buyukKucukHarfDuyarsiz() {
        let aliases = PersonAliases()
        let safe = aliases.pseudonymize("ayşe yılmaz iade etti", names: ["Ayşe Yılmaz"])
        #expect(safe == "Öğrenci 1 iade etti")
    }
}

@MainActor
struct OduncIadeMotoruTestleri {
    private func context() throws -> (ModelContext, CatalogBook) {
        let container = try ModelContainer(for: CatalogBook.self, ActiveLoan.self, BookCopy.self, Reservation.self, ScanWriteReceipt.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let book = CatalogBook(book: Book(title: "Kuyucaklı Yusuf", author: "Sabahattin Ali", quantity: 1))
        ctx.insert(book)
        try ctx.save()
        return (ctx, book)
    }

    @Test func oduncVerIadeAl() throws {
        let (ctx, book) = try context()
        let lent = try LoanActionEngine.lend(book: book, person: "Deneme Öğrenci", className: "7-C",
                                             loans: [], context: ctx, defaultDays: 10)
        #expect(lent.contains("ödünç verildi"))
        var loans = try ctx.fetch(FetchDescriptor<ActiveLoan>())
        #expect(loans.count == 1)
        #expect(loans.first?.studentClass == "7-C")

        // Tek nüsha ödünçteyken ikinci ödünç reddedilir
        #expect(throws: LoanActionEngine.LoanError.self) {
            try LoanActionEngine.lend(book: book, person: "Başka", className: nil, loans: loans, context: ctx)
        }

        let returned = try LoanActionEngine.giveBack(book: book, person: "deneme ogrenci", loans: loans, context: ctx)
        #expect(returned.contains("iade edildi"))
        loans = try ctx.fetch(FetchDescriptor<ActiveLoan>())
        #expect(loans.isEmpty)
    }

    @Test func eskiTekilOduncIadeEdilir() throws {
        let (ctx, book) = try context()
        book.loanedTo = "Eski Kayıt"
        book.loanDueDate = .now
        let text = try LoanActionEngine.giveBack(book: book, person: nil, loans: [], context: ctx)
        #expect(text.contains("Eski Kayıt"))
        #expect(book.loanedTo == nil)
    }

    @Test func kayitYoksaAnlamliHata() throws {
        let (ctx, book) = try context()
        #expect(throws: LoanActionEngine.LoanError.self) {
            try LoanActionEngine.giveBack(book: book, person: "Kimse", loans: [], context: ctx)
        }
    }

    @Test func asistanOduncNiyetiCozulur() throws {
        let json = """
        {"answer":"Ödünç vereyim mi?","action":{"type":"lend","loan":{"kind":"lend","bookTitle":"Kuyucaklı Yusuf","person":"Öğrenci 1"}}}
        """
        let reply = try GeminiJSON.decode(AssistantReply.self, from: json)
        #expect(reply.action?.loan?.kind == "lend")
        #expect(reply.action?.loan?.person == "Öğrenci 1")
    }
}

@MainActor
struct RafSayimiTestleri {
    @Test func rafKarsilastirmasi() throws {
        let container = try ModelContainer(for: CatalogBook.self, ActiveLoan.self, BookCopy.self, Reservation.self, ScanWriteReceipt.self, LibraryEventOutbox.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let here = CatalogBook(book: Book(title: "Kürk Mantolu Madonna", author: "Sabahattin Ali", shelf: "3", cabinet: "B"))
        let missing = CatalogBook(book: Book(title: "İnce Memed", author: "Yaşar Kemal", shelf: "3", cabinet: "B"))
        let elsewhere = CatalogBook(book: Book(title: "Tutunamayanlar", author: "Oğuz Atay", shelf: "1", cabinet: "A"))
        [here, missing, elsewhere].forEach { ctx.insert($0) }

        let seen = [
            GeminiBookFields(title: "Kürk Mantolu Madona", author: "Sabahattin Ali"),
            GeminiBookFields(title: "Tutunamayanlar", author: "Oğuz Atay"),
            GeminiBookFields(title: "Hiç Olmayan Kitap", author: "Yok")
        ]
        let result = ShelfScanEngine.compare(seen, catalog: [here, missing, elsewhere], cabinet: "b", shelf: "3")
        #expect(result.found.map(\.title) == ["Kürk Mantolu Madonna"])
        #expect(result.missing.map(\.title) == ["İnce Memed"])
        #expect(result.misplaced.map(\.book.title) == ["Tutunamayanlar"])
        #expect(result.misplaced.first?.registered == "A/1")
        #expect(result.unknown.count == 1)
    }

    @Test func taramaSonucuKayitTaslaginaCevrilir() {
        let kaydi = SesliKitapKaydi(fields: GeminiBookFields(title: "Saatleri Ayarlama Enstitüsü", author: "Tanpınar"),
                                    cabinet: "C", shelf: "")
        #expect(kaydi.title == "Saatleri Ayarlama Enstitüsü")
        #expect(kaydi.cabinet == "C")
        #expect(kaydi.shelf == nil)
        #expect(kaydi.quantity == 1)
    }
}

@MainActor
struct HaftalikRaporTestleri {
    @Test func sayilarDogruHesaplanir() throws {
        let container = try ModelContainer(for: CatalogBook.self, ActiveLoan.self, BookCopy.self, Reservation.self, ScanWriteReceipt.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let a = CatalogBook(book: Book(title: "A", author: "X", category: "Roman"))
        let b = CatalogBook(book: Book(title: "B", author: "Y"))
        let old = CatalogBook(book: Book(title: "Eski", author: "Z", addedAt: .now.addingTimeInterval(-30 * 86_400)))
        [a, b, old].forEach { ctx.insert($0) }
        let overdue = ActiveLoan(bookID: b.id, bookTitleSnapshot: "B", studentName: "S", studentClass: "5", dueDate: .now.addingTimeInterval(-86_400))
        ctx.insert(overdue)
        let events = [
            LoanEvent(bookID: a.id, bookTitle: "A", person: "p", kind: .lent, date: .now.addingTimeInterval(-2 * 86_400)),
            LoanEvent(bookID: a.id, bookTitle: "A", person: "p", kind: .returned, date: .now.addingTimeInterval(-86_400), wasLate: true),
            LoanEvent(bookID: a.id, bookTitle: "A", person: "q", kind: .lent, date: .now.addingTimeInterval(-3_600)),
            LoanEvent(bookID: b.id, bookTitle: "B", person: "r", kind: .lent, date: .now.addingTimeInterval(-20 * 86_400))
        ]
        let data = WeeklyReportData.build(books: [a, b, old], loans: [overdue], events: events)
        #expect(data.lentCount == 2)
        #expect(data.returnedCount == 1)
        #expect(data.lateReturns == 1)
        #expect(data.overdueNow == 1)
        #expect(data.newBooks == 2)
        #expect(data.totalBooks == 3)
        #expect(data.neverLoaned == 1) // yalnız "Eski"
        #expect(data.topBooks.first?.title == "A")
        #expect(data.missingCategory == 2)
        #expect(data.pdfSections.count == 4)
    }
}

@MainActor
struct AramaDiziniTestleri {
    @Test func aramaAnahtariUretilirVeSorgulanir() async throws {
        let container = try ModelContainer(for: CatalogBook.self, ActiveLoan.self, BookCopy.self, Reservation.self, ScanWriteReceipt.self, LibraryEventOutbox.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let book = CatalogBook(book: Book(title: "Şeker Portakalı", author: "Vasconcelos", category: "Roman"))
        ctx.insert(book)
        ctx.insert(CatalogBook(book: Book(title: "Başka Kitap", author: "Kimse")))
        try ctx.save()
        #expect(book.searchKey?.contains("seker") == true)

        // Eski kayıt simülasyonu: anahtar boşsa doldurulur
        book.searchKey = nil
        try ctx.save()
        await CatalogSearchIndex.backfillIfNeeded(context: ctx)
        #expect(book.searchKey?.isEmpty == false)

        let found = CatalogSearchIndex.candidates(for: ["portakali", "vasconcelos"], context: ctx)
        #expect(found.map(\.title) == ["Şeker Portakalı"])
    }
}

@MainActor
struct HizliModVeZenginlestirmeTestleri {
    @Test func eminTaslakOnaysizKaydedilebilir() {
        var draft = BookDraft()
        draft.title = "Kürk Mantolu Madonna"
        draft.author = "Sabahattin Ali"
        draft.isbn = "9789750718533"
        draft.recognizedByGemini = true
        #expect(GeminiBookRecognizer.isConfidentEnoughToAutoSave(draft))

        draft.lowConfidenceFields = ["publisher"]
        #expect(!GeminiBookRecognizer.isConfidentEnoughToAutoSave(draft), "Şüpheli alan varsa onay istenir")

        draft.lowConfidenceFields = []
        draft.recognizedByGemini = false
        #expect(!GeminiBookRecognizer.isConfidentEnoughToAutoSave(draft), "Yalnız Vision okuduysa onay istenir")
    }

    @Test func bulanikFotografUyarisi() {
        var draft = BookDraft()
        var fields = GeminiBookFields(title: "X", author: "Y")
        fields.imageQuality = "blurry"
        GeminiBookRecognizer.merge(fields, into: &draft)
        #expect(GeminiBookRecognizer.imageQualityWarning(for: draft)?.contains("bulanık") == true)
        #expect(!GeminiBookRecognizer.isConfidentEnoughToAutoSave(draft))
    }

    @Test func kunyeVeDeweyIslenir() {
        var draft = BookDraft()
        var fields = GeminiBookFields(title: "Küçük Prens", author: "Saint-Exupéry")
        fields.translator = "Cemal Süreya"
        fields.dewey = "843.912"
        GeminiBookRecognizer.merge(GeminiBookRecognizer.normalized(fields), into: &draft)
        #expect(draft.notes.contains("Çeviren: Cemal Süreya"))
        #expect(draft.location == "843.912")
    }

    @Test func zenginlestirmeYalnizBosAlanlariDoldurur() throws {
        let container = try ModelContainer(for: CatalogBook.self, ActiveLoan.self, BookCopy.self, Reservation.self, ScanWriteReceipt.self, LibraryEventOutbox.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let book = CatalogBook(book: Book(title: "Kitap", author: "Yazar", publisher: "Elle Girilen"))
        ctx.insert(book)
        var fields = GeminiBookFields(title: "Başka", author: "Başka", publisher: "AI Yayınevi", category: "Roman")
        fields.summary = "Özet"
        EnrichmentQueue.fillEmpty(book, from: fields)
        #expect(book.title == "Kitap")
        #expect(book.publisher == "Elle Girilen")
        #expect(book.category == "Roman")
        #expect(book.notes == "Özet")
    }

    @Test func kuyrugaEklenirTekrarlanmaz() {
        let id = UUID()
        EnrichmentQueue.enqueue(id)
        EnrichmentQueue.enqueue(id)
        #expect(EnrichmentQueue.pendingIDs.filter { $0 == id }.count == 1)
    }

    @Test func kullanimSayaciBiriktirir() {
        let before = GeminiUsage.load()
        GeminiUsage.record(promptTokens: 100, outputTokens: 20)
        let after = GeminiUsage.load()
        #expect(after.requests == before.requests + 1)
        #expect(after.promptTokens == before.promptTokens + 100)
        #expect(GeminiUsage.currentMonth(Date(timeIntervalSince1970: 1_790_000_000)).count == 7)
    }

    @Test func vekilAdresiDogrulanir() {
        let key = GeminiSettings.proxyURLKey
        let previous = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        UserDefaults.standard.set("https://okul.example.com/gemini", forKey: key)
        #expect(GeminiSettings.proxyBaseURL?.absoluteString == "https://okul.example.com/gemini/")
        UserDefaults.standard.set("gecersiz adres", forKey: key)
        #expect(GeminiSettings.proxyBaseURL == nil)
        UserDefaults.standard.set("http://okul.example.com/gemini", forKey: key)
        #expect(GeminiSettings.proxyBaseURL == nil)
        UserDefaults.standard.set("http://localhost:8080/gemini", forKey: key)
        #expect(GeminiSettings.proxyBaseURL != nil)
        UserDefaults.standard.set("https://kisi:parola@okul.example.com/gemini", forKey: key)
        #expect(GeminiSettings.proxyBaseURL == nil)
        UserDefaults.standard.set("https://okul.example.com/gemini?key=yanlis", forKey: key)
        #expect(GeminiSettings.proxyBaseURL == nil)
        UserDefaults.standard.set("", forKey: key)
        #expect(GeminiSettings.proxyBaseURL == nil)
    }
}
