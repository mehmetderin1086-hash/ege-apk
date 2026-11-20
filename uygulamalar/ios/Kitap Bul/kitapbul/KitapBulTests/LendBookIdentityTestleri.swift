import Foundation
import SwiftData
import Testing
@testable import _01

@MainActor @Suite(.serialized)
struct LendBookIdentityTestleri {
    private func isolated(_ body: () throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let oldStudent = StudentStore.directoryOverride, oldMember = MemberStore.directoryOverride
        let oldGrade = GradeLoanRuleStore.directoryOverride, oldHistory = LoanHistoryStore.directoryOverride
        StudentStore.directoryOverride = root; MemberStore.directoryOverride = root
        GradeLoanRuleStore.directoryOverride = root; LoanHistoryStore.directoryOverride = root
        LoanHistoryStore.invalidateCache()
        defer {
            StudentStore.directoryOverride = oldStudent; MemberStore.directoryOverride = oldMember
            GradeLoanRuleStore.directoryOverride = oldGrade; LoanHistoryStore.directoryOverride = oldHistory
            LoanHistoryStore.invalidateCache(); try? FileManager.default.removeItem(at: root)
        }
        try body()
    }
    @Test func baglamsizKitapYetimOduncOlusturamaz() throws {
        try isolated {
            let store = try KitapVeritabani.makeContainer(inMemory: true)
            let context = store.mainContext
            let transient = CatalogBook(book: Book(title: "Kaydedilmemiş", author: "Yazar"))
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try SchoolLibraryService.lend(book: transient, person: "Elle kişi", className: "", context: context, resolveKnownStudent: false)
            }
            #expect(try context.fetchCount(FetchDescriptor<ActiveLoan>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<LibraryEventOutbox>()) == 0)
        }
    }
    @Test func baskaBaglamdakiKitapYanlisKatalogdaOduncVerilemez() throws {
        try isolated {
            let store = try KitapVeritabani.makeContainer(inMemory: true)
            let source = store.mainContext, target = ModelContext(store)
            let book = CatalogBook(book: Book(title: "Kaydedildi", author: "Yazar"))
            source.insert(book); try source.save()
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try SchoolLibraryService.lend(book: book, person: "Elle kişi", className: "", context: target, resolveKnownStudent: false)
            }
            #expect(try target.fetchCount(FetchDescriptor<ActiveLoan>()) == 0)
        }
    }
    @Test func silinmisKitapFormuYetimOduncYazamaz() throws {
        try isolated {
            let store = try KitapVeritabani.makeContainer(inMemory: true)
            let context = store.mainContext
            let book = CatalogBook(book: Book(title: "Silindi", author: "Yazar"))
            context.insert(book); try context.save()
            context.delete(book)
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try SchoolLibraryService.lend(book: book, person: "Elle kişi", className: "", context: context, resolveKnownStudent: false)
            }
            try context.save()
            #expect(try context.fetchCount(FetchDescriptor<ActiveLoan>()) == 0)
            #expect(try SchoolLibraryService.historySnapshot(context: context).isEmpty)
        }
    }
    @Test func ayniBaglamdaYeniEklenenKitapVeOduncBirlikteKaydedilir() throws {
        try isolated {
            let store = try KitapVeritabani.makeContainer(inMemory: true)
            let context = store.mainContext; context.autosaveEnabled = false
            let book = CatalogBook(book: Book(title: "Yeni eser", author: "Yazar"))
            context.insert(book)
            let loan = try SchoolLibraryService.lend(book: book, person: "Elle kişi", className: "", context: context, resolveKnownStudent: false)
            let read = ModelContext(store)
            #expect(try read.fetchCount(FetchDescriptor<CatalogBook>()) == 1)
            #expect(try read.fetch(FetchDescriptor<ActiveLoan>()).first?.bookID == book.id)
            #expect(try SchoolLibraryService.historySnapshot(context: context).first?.loanID == loan.id)
        }
    }

    @Test func asistanOtomatikVadesiUyeVeGenelMerkeziKurallariIzler() throws {
        try isolated {
            let oldRules = UserDefaults.standard.object(forKey: MemberLoanRuleStore.key)
            let oldDays = UserDefaults.standard.object(forKey: "loanDurationDays")
            defer {
                UserDefaults.standard.set(oldRules, forKey: MemberLoanRuleStore.key)
                UserDefaults.standard.set(oldDays, forKey: "loanDurationDays")
            }
            UserDefaults.standard.set(try JSONEncoder().encode([MemberLoanRule(kind: .teacher, durationDays: 30, maximumLoans: 6)]), forKey: MemberLoanRuleStore.key)
            UserDefaults.standard.set(45, forKey: "loanDurationDays")
            let member = Member(name: "Öğretmen", kind: .teacher)
            try MemberStore.replaceAllVerified([member])
            let store = try KitapVeritabani.makeContainer(inMemory: true)
            let context = store.mainContext
            let teacherBook = CatalogBook(book: Book(title: "Öğretmen kitabı", author: "Yazar"))
            let manualBook = CatalogBook(book: Book(title: "Genel süre kitabı", author: "Yazar"))
            context.insert(teacherBook); context.insert(manualBook); try context.save()
            _ = try LoanActionEngine.lend(book: teacherBook, person: member.name, className: nil, loans: [], context: context, defaultDays: 2, memberID: member.id)
            _ = try LoanActionEngine.lend(book: manualBook, person: "Yeni elle okur", className: nil, loans: [], context: context, defaultDays: 2, resolveKnownStudent: false)
            let loans = try context.fetch(FetchDescriptor<ActiveLoan>())
            let teacherLoan = try #require(loans.first(where: { $0.memberID == member.id }))
            let manualLoan = try #require(loans.first(where: { $0.bookID == manualBook.id }))
            let calendar = Calendar.current
            #expect(calendar.dateComponents([.day], from: calendar.startOfDay(for: teacherLoan.loanedAt), to: calendar.startOfDay(for: teacherLoan.dueDate)).day == 30)
            #expect(calendar.dateComponents([.day], from: calendar.startOfDay(for: manualLoan.loanedAt), to: calendar.startOfDay(for: manualLoan.dueDate)).day == 45)
        }
    }
}
