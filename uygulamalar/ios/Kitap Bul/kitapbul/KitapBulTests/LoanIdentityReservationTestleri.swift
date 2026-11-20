import Testing
import Foundation
import SwiftData
@testable import _01

@MainActor
@Suite(.serialized)
struct LoanIdentityReservationTestleri {
    private struct SaveFailure: Error {}

    private func isolated(_ run: () throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let students = StudentStore.directoryOverride, members = MemberStore.directoryOverride
        let history = LoanHistoryStore.directoryOverride, rules = GradeLoanRuleStore.directoryOverride
        let lock = YetkiDurumu.shared.kilitEtkin
        StudentStore.directoryOverride = folder; MemberStore.directoryOverride = folder
        LoanHistoryStore.directoryOverride = folder; GradeLoanRuleStore.directoryOverride = folder
        LoanHistoryStore.invalidateCache(); YetkiDurumu.shared.kilitEtkin = false
        defer {
            StudentStore.directoryOverride = students; MemberStore.directoryOverride = members
            LoanHistoryStore.directoryOverride = history; GradeLoanRuleStore.directoryOverride = rules
            LoanHistoryStore.invalidateCache(); YetkiDurumu.shared.kilitEtkin = lock
            try? FileManager.default.removeItem(at: folder)
        }
        try run()
    }

    private func book(_ context: ModelContext, quantity: Int = 2) throws -> CatalogBook {
        let book = CatalogBook(book: Book(title: "Kimlikli eser", author: "Yazar", quantity: quantity))
        context.insert(book); try context.save(); return book
    }

    private func legacy(_ context: ModelContext, book: CatalogBook) throws -> ActiveLoan {
        let loan = ActiveLoan(bookID: book.id, bookTitleSnapshot: book.title, studentName: "Aynı Ad",
                              studentClass: "", dueDate: Date(timeIntervalSince1970: 1_800_000_000))
        loan.needsIdentityReview = true; loan.identitySource = "legacy"
        context.insert(loan); try context.save(); return loan
    }

    @Test func ayniAdliOgrenciVeUyeAyriSiradaVeUyeKendiAyrilmisNushasiniAlir() throws {
        try isolated {
            let container = try KitapVeritabani.makeContainer(inMemory: true); defer { withExtendedLifetime(container) {} }
            let context = container.mainContext; context.autosaveEnabled = false
            let student = Student(name: "Aynı Ad", number: "101", className: "7/A")
            let member = Member(name: student.name)
            try StudentStore.replaceAllVerified([student]); try MemberStore.replaceAllVerified([member])
            let book = try book(context, quantity: 1)
            let copy = BookCopy(bookID: book.id, accessionCode: "A-1"); context.insert(copy); try context.save()
            let studentHold = try OduncMerkezi.rezerveEt(book: book, student: student.name, className: student.className, context: context, studentID: student.id)
            let memberHold = try OduncMerkezi.rezerveEt(book: book, student: member.name, className: "", context: context, memberID: member.id)
            #expect(studentHold.id != memberHold.id && memberHold.studentID == nil)
            #expect(studentHold.studentNumberSnapshot == "101" && memberHold.identitySource == "member")
            memberHold.copyID = copy.id; memberHold.notifiedAt = .now; memberHold.expiresAt = .now.addingTimeInterval(48 * 3600)
            try context.save()
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try SchoolLibraryService.lend(book: book, person: student.name, className: student.className, context: context, studentID: student.id)
            }
            let lent = try SchoolLibraryService.lend(book: book, person: member.name, className: "", context: context, memberID: member.id)
            #expect(lent.memberID == member.id && lent.copyID == copy.id)
            #expect(memberHold.isClosed && memberHold.closureKind == "delivered" && !studentHold.isClosed)
        }
    }

    @Test func rezervasyonTekIslemTekKimlikVeCanliKitapGerektirir() throws {
        try isolated {
            let container = try KitapVeritabani.makeContainer(inMemory: true); defer { withExtendedLifetime(container) {} }
            let context = container.mainContext; context.autosaveEnabled = false
            let member = Member(name: "Üye"); try MemberStore.replaceAllVerified([member])
            let book = try book(context); let operation = UUID()
            let first = try SchoolLibraryService.reserve(book: book, person: member.name, className: "", context: context, memberID: member.id, operationID: operation)
            let replay = try SchoolLibraryService.reserve(book: book, person: member.name, className: "", context: context, memberID: member.id, operationID: operation)
            #expect(first.id == operation && replay.id == first.id)
            #expect(try context.fetchCount(FetchDescriptor<Reservation>()) == 1)
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try SchoolLibraryService.reserve(book: book, person: member.name, className: "", context: context, studentID: UUID(), memberID: member.id)
            }
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try SchoolLibraryService.reserve(book: book, person: member.name, className: "", context: ModelContext(container), memberID: member.id)
            }
            try SchoolLibraryService.cancelReservation(first, context: context)
            #expect(throws: SchoolLibraryService.OperationError.self) {
                try SchoolLibraryService.reserve(book: book, person: member.name, className: "", context: context, memberID: member.id, operationID: operation)
            }
        }
    }

    @Test func bilinmeyenAdTekrarindaKimlikTahminEdilmezAcikElleKuyrukAyridir() throws {
        try isolated {
            let container = try KitapVeritabani.makeContainer(inMemory: true); defer { withExtendedLifetime(container) {} }
            let context = container.mainContext; context.autosaveEnabled = false
            let book = try book(context)
            let unresolved = try OduncMerkezi.rezerveEt(book: book, student: "Ayşe", className: "6-B", context: context)
            let sameName = try OduncMerkezi.rezerveEt(book: book, student: "ayse", className: "6-B", context: context)
            #expect(unresolved.id != sameName.id)
            for pending in [unresolved, sameName] {
                #expect(pending.studentID == nil && pending.memberID == nil)
                #expect(pending.identitySource == "unresolved" && pending.needsIdentityReview)
                #expect(!SchoolLibraryService.samePerson(studentID: nil, name: "Ayşe", className: "6-B", reservation: pending))
            }
            let manual = try OduncMerkezi.rezerveEt(book: book, student: "Ayşe", className: "6-B", context: context, resolveKnownStudent: false)
            let manualReplay = try OduncMerkezi.rezerveEt(book: book, student: "ayse", className: "6-B", context: context, resolveKnownStudent: false)
            #expect(manual.id == manualReplay.id && manual.id != unresolved.id && manual.id != sameName.id)
            #expect(manual.identitySource == "manual" && !manual.needsIdentityReview)
            #expect(manual.studentID == nil && manual.memberID == nil)
            #expect(try context.fetchCount(FetchDescriptor<Reservation>()) == 3)
        }
    }

    @Test func ogrenciUyeAyniUUIDOlsaBileFarkliKimlikAlani() {
        let id = UUID(), reservation = Reservation(bookID: UUID(), bookTitleSnapshot: "Eser", studentName: "Ad", studentClass: "")
        reservation.memberID = id
        #expect(!SchoolLibraryService.samePerson(studentID: id, name: "Ad", className: "", reservation: reservation))
        #expect(SchoolLibraryService.samePerson(studentID: nil, name: "Ad", className: "", reservation: reservation, memberID: id))
        reservation.needsIdentityReview = true
        #expect(!SchoolLibraryService.samePerson(studentID: nil, name: "Ad", className: "", reservation: reservation, memberID: id))
    }

    @Test func kimlikVeNushaDuzeltmesiAdetVadeDegistirmezVeTekIslemTekGecmis() throws {
        try isolated {
            let container = try KitapVeritabani.makeContainer(inMemory: true); defer { withExtendedLifetime(container) {} }
            let context = container.mainContext; context.autosaveEnabled = false
            let student = Student(name: "Aynı Ad", number: "222", className: "8/B")
            try StudentStore.replaceAllVerified([student])
            let book = try book(context), loan = try legacy(context, book: book)
            let copy = BookCopy(bookID: book.id, accessionCode: "X-1"); context.insert(copy); try context.save()
            let before = ArchivedLoan(loan), operation = UUID(), quantity = book.quantity
            try SchoolLibraryService.correctLoanIdentity(loan, recipient: .student(student.id), copyID: copy.id, expected: before, operationID: operation, context: context)
            #expect(loan.studentID == student.id && loan.memberID == nil && !loan.needsIdentityReview && loan.copyID == copy.id)
            #expect(loan.studentNumberSnapshot == "222" && loan.studentClass == "8/B")
            #expect(book.quantity == quantity && loan.dueDate == before.dueDate && loan.loanedAt == before.loanedAt)
            try SchoolLibraryService.correctLoanIdentity(loan, recipient: .student(student.id), copyID: copy.id, expected: before, operationID: operation, context: context)
            let events = try SchoolLibraryService.historySnapshot(context: context)
            #expect(events.count == 1 && events[0].kind == .identityCorrected && events[0].loanID == loan.id)
            #expect(try JSONDecoder().decode(ArchivedLoan.self, from: #require(events[0].identityCorrectionBefore)) == before)
        }
    }

    @Test func eskiFormDoluKayipVeAyrilmisNushayiDegistirmez() throws {
        try isolated {
            let container = try KitapVeritabani.makeContainer(inMemory: true); defer { withExtendedLifetime(container) {} }
            let context = container.mainContext; context.autosaveEnabled = false
            let member = Member(name: "Üye"); try MemberStore.replaceAllVerified([member])
            let book = try book(context), loan = try legacy(context, book: book)
            let copy = BookCopy(bookID: book.id, status: "Kayıp"); context.insert(copy); try context.save()
            let before = ArchivedLoan(loan)
            #expect(throws: SchoolLibraryService.OperationError.self) { try SchoolLibraryService.correctLoanIdentity(loan, recipient: .member(member.id), copyID: copy.id, expected: before, operationID: UUID(), context: context) }
            copy.status = "Rafta"
            let other = ActiveLoan(bookID: book.id, bookTitleSnapshot: book.title, studentName: "Başka", studentClass: "", dueDate: .now)
            other.copyID = copy.id; context.insert(other); try context.save()
            #expect(throws: SchoolLibraryService.OperationError.self) { try SchoolLibraryService.correctLoanIdentity(loan, recipient: .member(member.id), copyID: copy.id, expected: before, operationID: UUID(), context: context) }
            context.delete(other)
            let hold = Reservation(bookID: book.id, bookTitleSnapshot: book.title, studentName: "Başka", studentClass: "")
            hold.memberID = UUID(); hold.copyID = copy.id; hold.notifiedAt = .now; hold.expiresAt = .distantFuture
            context.insert(hold); try context.save()
            #expect(throws: SchoolLibraryService.OperationError.self) { try SchoolLibraryService.correctLoanIdentity(loan, recipient: .member(member.id), copyID: copy.id, expected: before, operationID: UUID(), context: context) }
            loan.dueDate = .distantFuture; try context.save()
            #expect(throws: SchoolLibraryService.OperationError.self) { try SchoolLibraryService.correctLoanIdentity(loan, recipient: .member(member.id), copyID: nil, expected: before, operationID: UUID(), context: context) }
            #expect(loan.memberID == nil && loan.needsIdentityReview)
        }
    }

    @Test func kayitHatasiVeYetkiReddiKimligiVeGecmisiKorur() throws {
        try isolated {
            let container = try KitapVeritabani.makeContainer(inMemory: true); defer { withExtendedLifetime(container) {} }
            let context = container.mainContext; context.autosaveEnabled = false
            let member = Member(name: "Üye"); try MemberStore.replaceAllVerified([member])
            let book = try book(context), loan = try legacy(context, book: book), before = ArchivedLoan(loan)
            #expect(throws: SaveFailure.self) { try SchoolLibraryService.correctLoanIdentity(loan, recipient: .member(member.id), copyID: nil, expected: before, operationID: UUID(), context: context, persist: { throw SaveFailure() }) }
            #expect(ArchivedLoan(loan) == before)
            #expect(try context.fetchCount(FetchDescriptor<LibraryEventOutbox>()) == 0)
            YetkiDurumu.shared.kilitEtkin = true; YetkiDurumu.shared.gorevliyeGec()
            #expect(throws: SchoolLibraryService.OperationError.self) { try SchoolLibraryService.correctLoanIdentity(loan, recipient: .member(member.id), copyID: nil, expected: before, operationID: UUID(), context: context) }
            #expect(ArchivedLoan(loan) == before)
            #expect(try SchoolLibraryService.historySnapshot(context: context).isEmpty)
        }
    }

    @Test func tarihselVeGuncelOkulNumarasiKimliksizAyniAdiBaglamaz() throws {
        let student = Student(name: "Aynı Ad", number: "Yeni222", className: "8/B")
        let index = LibraryIdentitySearchIndex(students: [student], members: [])
        var event = LoanEvent(bookID: UUID(), bookTitle: "Eser", person: student.name, kind: .returned, date: .now,
                              studentID: student.id, classSnapshot: student.className)
        event.studentNumberSnapshot = "Eski101"
        #expect(index.text(for: event).contains("Eski101") && index.text(for: event).contains("Yeni222"))
        event.studentID = nil; event.studentNumberSnapshot = nil
        #expect(!index.text(for: event).contains("Yeni222"))
        let reservation = Reservation(bookID: event.bookID, bookTitleSnapshot: event.bookTitle, studentName: student.name, studentClass: "")
        reservation.memberID = UUID(); reservation.identitySource = "member"; reservation.studentNumberSnapshot = "Eski101"
        let dto = ArchivedReservation(reservation)
        let restored = try JSONDecoder().decode(ArchivedReservation.self, from: JSONEncoder().encode(dto)).makeModel()
        #expect(restored.memberID == reservation.memberID && restored.identitySource == "member" && restored.studentNumberSnapshot == "Eski101")
        let loan = ActiveLoan(bookID: event.bookID, bookTitleSnapshot: "Eser", studentName: "Ad", studentClass: "", dueDate: .now)
        loan.studentNumberSnapshot = "101"
        #expect(try JSONDecoder().decode(ArchivedLoan.self, from: JSONEncoder().encode(ArchivedLoan(loan))).makeActiveLoan().studentNumberSnapshot == "101")
    }

    @Test func acikRezervasyonuOlanKisiSilinmez() throws {
        try isolated {
            let container = try KitapVeritabani.makeContainer(inMemory: true); defer { withExtendedLifetime(container) {} }
            let context = container.mainContext; context.autosaveEnabled = false
            let student = Student(name: "Öğrenci", number: "9"), member = Member(name: "Üye")
            try StudentStore.replaceAllVerified([student]); try MemberStore.replaceAllVerified([member])
            let book = try book(context)
            let studentHold = try SchoolLibraryService.reserve(book: book, person: student.name, className: "", context: context, studentID: student.id)
            let memberHold = try SchoolLibraryService.reserve(book: book, person: member.name, className: "", context: context, memberID: member.id)
            #expect(throws: SchoolLibraryService.OperationError.self) { try StudentStore.removeVerified(id: student.id, context: context) }
            #expect(throws: SchoolLibraryService.OperationError.self) { try MemberStore.removeVerified(id: member.id, context: context) }
            try SchoolLibraryService.cancelReservation(studentHold, context: context); try SchoolLibraryService.cancelReservation(memberHold, context: context)
            try StudentStore.removeVerified(id: student.id, context: context); try MemberStore.removeVerified(id: member.id, context: context)
            #expect(try StudentStore.allVerified().isEmpty && MemberStore.allVerified().isEmpty)
        }
    }
}
