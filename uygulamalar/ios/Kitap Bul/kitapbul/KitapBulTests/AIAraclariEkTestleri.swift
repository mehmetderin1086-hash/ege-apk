import Testing
import Foundation
import SwiftData
@testable import _01

@MainActor
struct AIAraclariEkTestleri {
    @Test func bozukSorularAtilir() {
        let sorular = [
            QuizQuestion(question: "Geçerli?", options: ["a", "b", "c", "d"], answer: 2, explanation: nil),
            QuizQuestion(question: "Cevap dışarıda", options: ["a", "b"], answer: 5, explanation: nil),
            QuizQuestion(question: " ", options: ["a", "b"], answer: 0, explanation: nil),
            QuizQuestion(question: "Boş seçenek", options: ["a", " "], answer: 0, explanation: nil),
            QuizQuestion(question: "Tek seçenek", options: ["a"], answer: 0, explanation: nil)
        ]
        #expect(QuizEngine.sanitized(sorular).map(\.question) == ["Geçerli?"])
        let kagit = QuizEngine.printable(title: "Nutuk", QuizEngine.sanitized(sorular), withAnswers: true)
        #expect(kagit.contains("1) Geçerli?"))
        #expect(kagit.contains("C) c"))
        #expect(kagit.contains("CEVAP ANAHTARI: 1-C"))
        #expect(!QuizEngine.printable(title: "Nutuk", QuizEngine.sanitized(sorular), withAnswers: false).contains("CEVAP"))
    }

    @Test func talepArzOraniHesaplanir() throws {
        let ctx = ModelContext(try KitapVeritabani.makeContainer(inMemory: true))
        let roman = CatalogBook(book: Book(title: "R", author: "", category: "Roman", quantity: 2))
        let bilim = CatalogBook(book: Book(title: "B", author: "", category: "Bilim", quantity: 4))
        ctx.insert(roman)
        ctx.insert(bilim)
        let olaylar = (0..<6).map { _ in LoanEvent(bookID: roman.id, bookTitle: "R", person: "x", kind: .lent, date: .now) }
            + [LoanEvent(bookID: bilim.id, bookTitle: "B", person: "x", kind: .lent, date: .now.addingTimeInterval(-400 * 86_400))]
        let satirlar = GapAnalysisEngine.rows(books: [roman, bilim], events: olaylar)
        #expect(satirlar.first?.category == "Roman")
        #expect(satirlar.first?.demandRatio == 3)
        #expect(satirlar.last?.loans == 0)   // bir yıldan eski ödünç sayılmaz
    }

    @Test func bagisListesiAyiklanir() {
        let metin = """
        1. Küçük Prens - Antoine de Saint-Exupéry
        • Simyacı, Paulo Coelho
        - Nutuk
        x
        Sefiller — Victor Hugo
        """
        let liste = DonationEngine.parse(metin)
        #expect(liste.map(\.title) == ["Küçük Prens", "Simyacı", "Nutuk", "Sefiller"])
        #expect(liste[0].author == "Antoine de Saint-Exupéry")
        #expect(liste[2].author == nil)
        #expect(liste[3].author == "Victor Hugo")
    }

    @Test func kategoriYerelEslemeVeUygulama() throws {
        #expect(CategoryConsistencyEngine.localMatch("hikaye") == "Hikâye")
        #expect(CategoryConsistencyEngine.localMatch("ROMANLAR") == "Roman")
        #expect(CategoryConsistencyEngine.localMatch("şiirler") == "Şiir")
        #expect(CategoryConsistencyEngine.localMatch("Uzay Macerası") == nil)

        let ctx = ModelContext(try KitapVeritabani.makeContainer(inMemory: true))
        let kitaplar = [
            CatalogBook(book: Book(title: "A", author: "", category: "hikaye")),
            CatalogBook(book: Book(title: "B", author: "", category: "hikaye")),
            CatalogBook(book: Book(title: "C", author: "", category: "Roman")),
            CatalogBook(book: Book(title: "D", author: "", category: "Garip Tür"))
        ]
        kitaplar.forEach { ctx.insert($0) }
        let sapmalar = CategoryConsistencyEngine.strayCategories(kitaplar)
        #expect(sapmalar.map(\.name) == ["hikaye", "Garip Tür"])
        #expect(sapmalar.first?.count == 2)
        let degisen = try CategoryConsistencyEngine.apply(["hikaye": "Hikâye"], to: kitaplar, context: ctx)
        #expect(degisen == 2)
        #expect(kitaplar[0].category == "Hikâye")
        #expect(kitaplar[3].category == "Garip Tür")
    }

    @Test func aylikSinirVeMaliyet() {
        var anlik = GeminiUsage.Snapshot(month: GeminiUsage.currentMonth())
        anlik.requests = 100
        anlik.promptTokens = 2_000_000
        anlik.outputTokens = 400_000
        #expect(!GeminiUsage.isOverLimit(anlik, limit: 0))   // 0 = sınırsız
        #expect(GeminiUsage.isOverLimit(anlik, limit: 100))
        #expect(!GeminiUsage.isOverLimit(anlik, limit: 101))
        let maliyet = GeminiUsage.estimatedCostUSD(anlik, inputPrice: 0.30, outputPrice: 2.50)
        #expect(abs(maliyet - 1.6) < 0.0001)
        #expect(GeminiError.limitReached(100).errorDescription?.contains("100") == true)
    }

    @Test func bagisYanitiCozulurVeKararDuzeltilir() throws {
        let json = #"{"items": [{"title": "A", "decision": "al", "reason": "iyi"}, {"title": "B", "decision": "belki", "reason": "?"}]}"#
        let yanit = try JSONDecoder().decode(DonationReply.self, from: Data(json.utf8))
        #expect(yanit.items.count == 2)
        let duzeltilmis = DonationEngine.normalizedDecisions(yanit.items + [DonationItem(title: "C", decision: " AL ", reason: "")])
        #expect(duzeltilmis.map(\.decision) == ["al", "kontrol", "al"])
    }
}
