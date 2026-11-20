import Testing
import Foundation
import SwiftData
@testable import _01

@MainActor
@Suite(.serialized)
struct OduncUzatmaTestleri {
    private struct DiskFailure: Error {}
    private func isolated(_ body: (URL, UserDefaults) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("extension-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oldHistory = LoanHistoryStore.directoryOverride, oldMembers = MemberStore.directoryOverride
        let oldGrades = GradeLoanRuleStore.directoryOverride
        LoanHistoryStore.directoryOverride = directory; MemberStore.directoryOverride = directory; GradeLoanRuleStore.directoryOverride = directory
        LoanHistoryStore.invalidateCache()
        let suite = UUID().uuidString, defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            LoanHistoryStore.directoryOverride = oldHistory; MemberStore.directoryOverride = oldMembers; GradeLoanRuleStore.directoryOverride = oldGrades
            LoanHistoryStore.invalidateCache(); defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(directory, defaults)
    }
    private func container() throws -> ModelContainer { try KitapVeritabani.makeContainer(inMemory: true) }
    private func seed(_ context: ModelContext, due: Date, className: String = "") throws -> ActiveLoan {
        let book = CatalogBook(book: Book(title: "Uzatılacak", author: "Yazar"))
        context.insert(book)
        let loan = ActiveLoan(bookID: book.id, bookTitleSnapshot: book.title, studentName: "Aynı Ad", studentClass: className, dueDate: due)
        context.insert(loan); try context.save()
        return loan
    }

    @Test func vadeVeKimlikliGecmisBirlikteYazilir() throws {
        try isolated { _, defaults in
            let container = try container(); defer { withExtendedLifetime(container) {} }
            let context = container.mainContext; context.autosaveEnabled = false
            let now = Date(timeIntervalSince1970: 1_800_000_000), due = now.addingTimeInterval(3 * 86_400)
            let loan = try seed(context, due: due)
            loan.studentID = UUID(); loan.copyID = UUID(); loan.identitySource = "student"; loan.periodSnapshot = "2026–2027"
            try context.save()
            let operationID = UUID()
            let after = try SchoolLibraryService.extendLoan(loan, context: context, defaultDays: 10, now: now, operationID: operationID, defaults: defaults)
            #expect(Calendar.current.dateComponents([.day], from: due, to: after).day == 10)
            #expect(loan.extensionCount == 1)
            let event = try #require(SchoolLibraryService.historySnapshot(context: context).first(where: { $0.id == operationID }))
            #expect(event.kind == .extended && event.loanID == loan.id)
            #expect(event.studentID == loan.studentID && event.memberID == nil && event.copyID == loan.copyID)
            #expect(event.previousDueDate == due && event.dueDate == after && event.periodSnapshot == loan.periodSnapshot)
        }
    }

    @Test func uyeTuruSureKuraliniVeOduncAnindakiTuruKorur() throws {
        try isolated { _, defaults in
            let container = try container(); defer { withExtendedLifetime(container) {} }
            let context = container.mainContext; context.autosaveEnabled = false
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            var member = Member(name: "Öğretmen", kind: .teacher)
            try MemberStore.replaceAllVerified([member])
            let loan = try seed(context, due: now.addingTimeInterval(-86_400))
            loan.memberID = member.id; loan.identitySource = "member"
            try context.save()
            var borrowed = LoanEvent(bookID: loan.bookID, bookTitle: loan.bookTitleSnapshot, person: loan.studentName, kind: .lent, date: now.addingTimeInterval(-5 * 86_400), dueDate: loan.dueDate)
            borrowed.loanID = loan.id; borrowed.memberID = member.id; borrowed.memberKindSnapshot = MemberKind.teacher.rawValue
            try LoanHistoryStore.recordVerified(borrowed)
            // Güncel kural personel için, tarihçe ise ödünç verildiği günkü öğretmen türünü saklar.
            member.kind = .staff; try MemberStore.replaceAllVerified([member])
            defaults.set(try JSONEncoder().encode([MemberLoanRule(kind: .staff, durationDays: 30, maximumLoans: 4)]), forKey: MemberLoanRuleStore.key)
            let after = try SchoolLibraryService.extendLoan(loan, context: context, defaultDays: 10, now: now, defaults: defaults)
            #expect(Calendar.current.dateComponents([.day], from: now, to: after).day == 30)
            #expect(try SchoolLibraryService.historySnapshot(context: context).first(where: { $0.kind == .extended })?.memberKindSnapshot == MemberKind.teacher.rawValue)
        }
    }

    @Test func ayniIslemTekKezUzatirVeEskiOnaySonrakiVadeyiDegistirmez() throws {
        try isolated { _, defaults in
            let container = try container(); defer { withExtendedLifetime(container) {} }
            let context = container.mainContext; context.autosaveEnabled = false
            let now = Date(timeIntervalSince1970: 1_800_000_000), operation = UUID()
            let loan = try seed(context, due: now)
            let after = try SchoolLibraryService.extendLoan(loan, context: context, now: now, operationID: operation, expectedDueDate: now, expectedExtensionCount: 0, defaults: defaults)
            #expect(try SchoolLibraryService.extendLoan(loan, context: context, now: now, operationID: operation, expectedDueDate: now, expectedExtensionCount: 0, defaults: defaults) == after)
            #expect(loan.extensionCount == 1)
            #expect(try SchoolLibraryService.historySnapshot(context: context).count == 1)
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try SchoolLibraryService.extendLoan(loan, context: context, now: now, expectedDueDate: now, defaults: defaults)
            }
            _ = try SchoolLibraryService.extendLoan(loan, context: context, now: now, operationID: UUID(), defaults: defaults)
            #expect(loan.extensionCount == 2)
            #expect(throws: SchoolLibraryService.OperationError.self) { try SchoolLibraryService.extendLoan(loan, context: context, now: now, operationID: operation, defaults: defaults) }
            #expect(throws: OduncMerkezi.OduncHatasi.self) { try OduncMerkezi.uzat(loan, context: context, now: now) }
        }
    }

    @Test func ayniAdliBaskaOgrencininRezervasyonuUzatmayiEngeller() throws {
        try isolated { _, defaults in
            let container = try container(); defer { withExtendedLifetime(container) {} }
            let context = container.mainContext; context.autosaveEnabled = false
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let loan = try seed(context, due: now, className: "5-A")
            loan.studentID = UUID(); try context.save()
            let reservation = Reservation(bookID: loan.bookID, bookTitleSnapshot: loan.bookTitleSnapshot, studentName: loan.studentName, studentClass: loan.studentClass)
            reservation.studentID = UUID(); context.insert(reservation); try context.save()
            #expect(throws: SchoolLibraryService.OperationError.self) { try SchoolLibraryService.extendLoan(loan, context: context, now: now, defaults: defaults) }
            #expect(loan.dueDate == now && loan.extensionCount == 0)
            reservation.studentID = loan.studentID; try context.save()
            _ = try SchoolLibraryService.extendLoan(loan, context: context, now: now, defaults: defaults)
            #expect(loan.extensionCount == 1)
        }
    }

    @Test func kaydedilmemisVeyaDegismisOduncUzatilmadanReddedilir() throws {
        try isolated { _, defaults in
            let container = try container(); defer { withExtendedLifetime(container) {} }
            let context = container.mainContext; context.autosaveEnabled = false
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let transient = ActiveLoan(bookID: UUID(), bookTitleSnapshot: "Taslak", studentName: "A", studentClass: "", dueDate: now)
            context.insert(transient)
            #expect(throws: SchoolLibraryService.OperationError.self) { try SchoolLibraryService.extendLoan(transient, context: context, now: now, defaults: defaults) }
            context.rollback()
            let loan = try seed(context, due: now)
            loan.dueDate = now.addingTimeInterval(86_400)
            #expect(throws: SchoolLibraryService.OperationError.self) { try SchoolLibraryService.extendLoan(loan, context: context, now: now, defaults: defaults) }
            context.rollback()
            context.delete(loan); try context.save()
            #expect(throws: SchoolLibraryService.OperationError.self) { try SchoolLibraryService.extendLoan(loan, context: context, now: now, defaults: defaults) }
            #expect(try SchoolLibraryService.historySnapshot(context: context).isEmpty)
        }
    }

    @Test func diskHatasindaVadeSayacVeOutboxGeriDoner() throws {
        try isolated { _, defaults in
            let container = try container(); defer { withExtendedLifetime(container) {} }
            let context = container.mainContext; context.autosaveEnabled = false
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let loan = try seed(context, due: now)
            #expect(throws: DiskFailure.self) {
                try SchoolLibraryService.extendLoan(loan, context: context, now: now, defaults: defaults, persist: { throw DiskFailure() })
            }
            #expect(loan.dueDate == now && loan.extensionCount == 0)
            #expect(try context.fetchCount(FetchDescriptor<LibraryEventOutbox>()) == 0)
            #expect(try SchoolLibraryService.historySnapshot(context: context).isEmpty)
            let reloaded = try #require(ModelContext(container).fetch(FetchDescriptor<ActiveLoan>()).first)
            #expect(reloaded.dueDate == now && reloaded.extensionCount == 0)
        }
    }

    @Test func bozukKurallarVeGecersizSureKaydiDegistiremez() throws {
        try isolated { _, defaults in
            let container = try container(); defer { withExtendedLifetime(container) {} }
            let context = container.mainContext; context.autosaveEnabled = false
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let loan = try seed(context, due: now, className: "5-A")
            for days in [0, 366] {
                #expect(throws: SchoolLibraryService.OperationError.self) { try SchoolLibraryService.extendLoan(loan, context: context, defaultDays: days, now: now, defaults: defaults) }
            }
            let gradesURL = try #require(GradeLoanRuleStore.storageURL)
            try Data("invalid-json".utf8).write(to: gradesURL)
            #expect(throws: (any Error).self) { try SchoolLibraryService.extendLoan(loan, context: context, now: now, defaults: defaults) }
            try FileManager.default.removeItem(at: gradesURL)
            let member = Member(name: "Üye", kind: .teacher)
            try MemberStore.replaceAllVerified([member]); loan.memberID = member.id; try context.save()
            defaults.set(Data("broken-member-rule".utf8), forKey: MemberLoanRuleStore.key)
            #expect(throws: (any Error).self) { try SchoolLibraryService.extendLoan(loan, context: context, now: now, defaults: defaults) }
            #expect(loan.dueDate == now && loan.extensionCount == 0)
            #expect(try SchoolLibraryService.historySnapshot(context: context).isEmpty)
        }
    }

    @Test func jsonAktarimiBekleyenUzatmaMakbuzuYenidenUzatmaz() throws {
        try isolated { directory, defaults in
            let container = try container(); defer { withExtendedLifetime(container) {} }
            let context = container.mainContext; context.autosaveEnabled = false
            let now = Date(timeIntervalSince1970: 1_800_000_000), operationID = UUID()
            let loan = try seed(context, due: now)
            let blocked = directory.appendingPathComponent("blocked-directory")
            try Data([1]).write(to: blocked)
            LoanHistoryStore.directoryOverride = blocked; LoanHistoryStore.invalidateCache()
            let date = try SchoolLibraryService.extendLoan(loan, context: context, now: now, operationID: operationID, defaults: defaults)
            #expect(try context.fetchCount(FetchDescriptor<LibraryEventOutbox>()) == 1)
            #expect(try SchoolLibraryService.extendLoan(loan, context: context, now: now, operationID: operationID, defaults: defaults) == date)
            #expect(loan.extensionCount == 1)
            LoanHistoryStore.directoryOverride = directory; LoanHistoryStore.invalidateCache()
            try SchoolLibraryService.flushHistoryOutbox(context: context)
            #expect(try SchoolLibraryService.historySnapshot(context: context).filter { $0.id == operationID }.count == 1)
        }
    }

    // MARK: - İadede kitabın durumu (kütüphane ödüncü)

    @Test func hasarliIadeNushayiOnarimaAyirirVeGecmiseYazar() throws {
        try isolated { _, _ in
            let container = try container(); defer { withExtendedLifetime(container) {} }
            let context = container.mainContext; context.autosaveEnabled = false
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let loan = try seed(context, due: now.addingTimeInterval(86_400))
            let loanID = loan.id, bookID = loan.bookID
            try SchoolLibraryService.returnLoan(loan, context: context, now: now, returnedCondition: "Onarım gerekli")

            #expect(try context.fetch(FetchDescriptor<ActiveLoan>()).isEmpty)
            let copy = try #require(try context.fetch(FetchDescriptor<BookCopy>()).first { $0.bookID == bookID })
            #expect(copy.condition == "Onarım gerekli" && copy.status == "Onarımda")
            #expect(copy.note == "İadede durum kaydı", "Kütüphane ödüncü ders kitabı notu taşımaz")
            let event = try #require(SchoolLibraryService.historySnapshot(context: context).first { $0.loanID == loanID && $0.kind == .returned })
            #expect(event.returnedCondition == "Onarım gerekli" && event.copyID == copy.id)
            let book = try #require(try context.fetch(FetchDescriptor<CatalogBook>()).first { $0.id == bookID })
            #expect(SchoolLibraryService.stock(for: book, context: context).repair == 1)
        }
    }

    /// Tüm nüshaları kayıtlı kitapta kimliksiz ödünç hasarlı iade edilirse olmayan bir nüsha stoğa eklenmez.
    @Test func tumNushalarKayitliykenKimliksizHasarliIadeReddedilir() throws {
        try isolated { _, _ in
            let container = try container(); defer { withExtendedLifetime(container) {} }
            let context = container.mainContext; context.autosaveEnabled = false
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let loan = try seed(context, due: now.addingTimeInterval(86_400))
            let bookID = loan.bookID
            context.insert(BookCopy(bookID: bookID, condition: "İyi", status: "Rafta", note: ""))
            try context.save()
            #expect(throws: (any Error).self) {
                try SchoolLibraryService.returnLoan(loan, context: context, now: now, returnedCondition: "Onarım gerekli")
            }
            #expect(try context.fetch(FetchDescriptor<BookCopy>()).count == 1, "Yeni nüsha kaydı açılmaz")
            #expect(try context.fetch(FetchDescriptor<ActiveLoan>()).count == 1, "Ödünç açık kalır")
            let book = try #require(try context.fetch(FetchDescriptor<CatalogBook>()).first { $0.id == bookID })
            #expect(SchoolLibraryService.stock(for: book, context: context).total == 1)
        }
    }

    /// Nüsha kimliği olan ödünçte hasar o nüshaya işlenir; yeni kayıt açılmaz.
    @Test func kimlikliHasarliIadeMevcutNushayiGunceller() throws {
        try isolated { _, _ in
            let container = try container(); defer { withExtendedLifetime(container) {} }
            let context = container.mainContext; context.autosaveEnabled = false
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let loan = try seed(context, due: now.addingTimeInterval(86_400))
            let copy = BookCopy(bookID: loan.bookID, condition: "İyi", status: "Rafta", note: "")
            context.insert(copy); loan.copyID = copy.id
            try context.save()
            try SchoolLibraryService.returnLoan(loan, context: context, now: now, returnedCondition: "Yıpranmış")
            let copies = try context.fetch(FetchDescriptor<BookCopy>())
            #expect(copies.count == 1 && copies.first?.condition == "Yıpranmış" && copies.first?.status == "Rafta")
        }
    }

    @Test func iyiDurumdaIadeNushaKaydiAcmaz() throws {
        try isolated { _, _ in
            let container = try container(); defer { withExtendedLifetime(container) {} }
            let context = container.mainContext; context.autosaveEnabled = false
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let loan = try seed(context, due: now.addingTimeInterval(86_400))
            let loanID = loan.id
            try SchoolLibraryService.returnLoan(loan, context: context, now: now, returnedCondition: "İyi")
            #expect(try context.fetch(FetchDescriptor<BookCopy>()).isEmpty)
            let event = try #require(SchoolLibraryService.historySnapshot(context: context).first { $0.loanID == loanID && $0.kind == .returned })
            #expect(event.returnedCondition == "İyi")
        }
    }

    @Test func gecersizIadeDurumuOdunuKapatmaz() throws {
        try isolated { _, _ in
            let container = try container(); defer { withExtendedLifetime(container) {} }
            let context = container.mainContext; context.autosaveEnabled = false
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let loan = try seed(context, due: now.addingTimeInterval(86_400))
            #expect(throws: (any Error).self) {
                try SchoolLibraryService.returnLoan(loan, context: context, now: now, returnedCondition: "Parçalanmış")
            }
            #expect(try context.fetch(FetchDescriptor<ActiveLoan>()).count == 1)
            #expect(OduncMerkezi.hasarliIadeDurumlari.allSatisfy(BookCopy.conditions.contains))
        }
    }
}
