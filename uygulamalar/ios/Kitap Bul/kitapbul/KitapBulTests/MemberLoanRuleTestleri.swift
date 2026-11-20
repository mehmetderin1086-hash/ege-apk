import Foundation
import SwiftData
import Testing
@testable import _01

@MainActor @Suite(.serialized)
struct MemberLoanRuleTestleri {
    @Test func legacyMemberDoesNotAcquireInventedKindAndRuleRoundTrips() throws {
        let id = UUID()
        let data = Data("{\"id\":\"\(id)\",\"name\":\"Eski Üye\",\"memberNumber\":\"5\",\"note\":\"\"}".utf8)
        let member = try JSONDecoder().decode(Member.self, from: data)
        #expect(member.id == id && member.kind == nil)
        let suite = "member-rules-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let rules = [MemberLoanRule(kind: .teacher, durationDays: 30, maximumLoans: 6),
            MemberLoanRule(kind: .guardian, durationDays: 7, maximumLoans: 1)]
        defaults.set(try JSONEncoder().encode(rules), forKey: MemberLoanRuleStore.key)
        #expect(try MemberLoanRuleStore.rule(for: .teacher, defaults: defaults)?.durationDays == 30)
        #expect(try MemberLoanRuleStore.rule(for: nil, defaults: defaults) == nil)
        #expect(throws: FullArchive.ValidationError.self) {
            try MemberLoanRuleStore.validate([rules[0], rules[0]])
        }
        #expect(try MemberLoanRuleStore.all(defaults: defaults) == rules)
        defaults.set(Data("broken".utf8), forKey: MemberLoanRuleStore.key)
        #expect(throws: (any Error).self) { try MemberLoanRuleStore.all(defaults: defaults) }
        defaults.set("wrong stored type", forKey: MemberLoanRuleStore.key)
        #expect(throws: FullArchive.ValidationError.self) { try MemberLoanRuleStore.all(defaults: defaults) }
    }

    @Test func memberKindQuotaAndDurationUseSharedLendServiceAndHistoricalSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let oldRules = UserDefaults.standard.object(forKey: MemberLoanRuleStore.key)
        let oldRole = UserDefaults.standard.object(forKey: "roleLockEnabled")
        UserDefaults.standard.set(false, forKey: "roleLockEnabled")
        let oldMember = MemberStore.directoryOverride, oldHistory = LoanHistoryStore.directoryOverride
        MemberStore.directoryOverride = root; LoanHistoryStore.directoryOverride = root
        LoanHistoryStore.invalidateCache()
        defer {
            UserDefaults.standard.set(oldRules, forKey: MemberLoanRuleStore.key)
            UserDefaults.standard.set(oldRole, forKey: "roleLockEnabled")
            MemberStore.directoryOverride = oldMember; LoanHistoryStore.directoryOverride = oldHistory
            LoanHistoryStore.invalidateCache(); try? FileManager.default.removeItem(at: root)
        }
        try MemberLoanRuleStore.save([MemberLoanRule(kind: .teacher, durationDays: 31, maximumLoans: 1)])
        let member = Member(name: "Öğretmen", kind: .teacher)
        try MemberStore.replaceAllVerified([member])
        let store = try KitapVeritabani.makeContainer(url: root.appendingPathComponent("unit.store"))
        let context = store.mainContext
        let a = CatalogBook(book: Book(title: "A", author: "", quantity: 1))
        let b = CatalogBook(book: Book(title: "B", author: "", quantity: 1))
        context.insert(a); context.insert(b); try context.save()
        let loan = try SchoolLibraryService.lend(book: a, person: member.name, className: "", context: context, memberID: member.id)
        let loanID = loan.id
        let days = Calendar.current.dateComponents([.day], from: loan.loanedAt, to: loan.dueDate).day ?? 0
        #expect(days >= 30 && days <= 31)
        #expect(throws: OduncMerkezi.OduncHatasi.self) {
            try SchoolLibraryService.lend(book: b, person: member.name, className: "", context: context, memberID: member.id)
        }
        #expect(try context.fetchCount(FetchDescriptor<ActiveLoan>()) == 1)
        try MemberStore.updateKind(id: member.id, kind: .guardian)
        _ = try SchoolLibraryService.returnLoan(loan, context: context)
        let history = try SchoolLibraryService.historySnapshot(context: context)
        #expect(history.filter { $0.memberID == member.id }.allSatisfy { $0.memberKindSnapshot == "teacher" })
        #expect(history.filter { $0.memberID == member.id }.allSatisfy { $0.loanID == loanID })
    }
}
