import Foundation
import SwiftData

nonisolated enum LoanIdentitySelection: Equatable, Sendable {
    case student(UUID)
    case member(UUID)
}

/// Metin araması kimlikli güncel numarayı ve ödünç anındaki numarayı birlikte kullanır.
/// Kimliği bulunmayan eski kayıt, aynı adlı öğrenciye arama sırasında bağlanmaz.
nonisolated struct LibraryIdentitySearchIndex: Sendable {
    var studentNumbers: [UUID: String]
    var memberNumbers: [UUID: String]

    init(students: [Student], members: [Member]) {
        studentNumbers = Dictionary(students.map { ($0.id, $0.number) }, uniquingKeysWith: { first, _ in first })
        memberNumbers = Dictionary(members.map { ($0.id, $0.memberNumber) }, uniquingKeysWith: { first, _ in first })
    }

    func text(name: String, className: String, studentID: UUID?, memberID: UUID?, numberSnapshot: String?) -> String {
        [name, className, numberSnapshot ?? "", studentID.flatMap { studentNumbers[$0] } ?? "",
         memberID.flatMap { memberNumbers[$0] } ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }

    func text(for event: LoanEvent) -> String {
        text(name: event.person, className: event.classSnapshot ?? "", studentID: event.studentID,
             memberID: event.memberID, numberSnapshot: event.studentNumberSnapshot)
            + " " + event.bookTitle + " " + event.kind.rawValue
    }
}

@MainActor
extension SchoolLibraryService {
    static func numberSnapshot(for loan: ActiveLoan) throws -> String? {
        if let saved = loan.studentNumberSnapshot { return saved }
        guard let id = loan.studentID, loan.memberID == nil else { return nil }
        return try StudentStore.allVerified().first { $0.id == id }?.number
    }

    @discardableResult
    static func reserve(book: CatalogBook, person: String, className: String, context: ModelContext,
                        studentID: UUID? = nil, memberID: UUID? = nil, resolveKnownStudent: Bool = true,
                        operationID: UUID? = nil) throws -> Reservation {
        guard !book.isDeleted, book.modelContext === context, !book.isWithdrawn else {
            throw OperationError(message: "Kitap bu katalogda dolaşımda değil; rezervasyon oluşturulmadı.")
        }
        let bookID = book.id
        guard try context.fetch(FetchDescriptor<CatalogBook>(predicate: #Predicate { $0.id == bookID }))
            .contains(where: { !$0.isDeleted }) else { throw OperationError(message: "Kitap kaydı bulunamadı.") }
        let name = person.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, studentID == nil || memberID == nil else {
            throw OperationError(message: "Tek bir öğrenci veya üye seçin; kişi adı boş olamaz.")
        }
        let member = try memberID.map { try resolvedMember(id: $0) }
        let student = memberID == nil && (studentID != nil || resolveKnownStudent)
            ? try resolvedStudent(name: name, className: className, id: studentID) : nil
        if memberID == nil && studentID == nil && resolveKnownStudent,
           try MemberStore.allVerified().contains(where: { CatalogMatcher.normalize($0.name) == CatalogMatcher.normalize(name) }) {
            throw OperationError(message: "Bu adla kayıtlı üye var. Öğrenci veya üyeyi açıkça seçin.")
        }
        let identity = student?.id
        let canonicalName = member?.name ?? student?.name ?? name
        let effectiveClass = member == nil ? student?.className ?? className : ""
        let source = member != nil ? "member" : student != nil ? "student" : resolveKnownStudent ? "unresolved" : "manual"
        let reservations = try context.fetch(FetchDescriptor<Reservation>())
        if let operationID, let existing = reservations.first(where: { $0.id == operationID }) {
            guard existing.bookID == book.id, !existing.isClosed,
                  samePerson(studentID: identity, name: canonicalName, className: effectiveClass,
                             reservation: existing, memberID: memberID), existing.identitySource == source else {
                throw OperationError(message: "Bu rezervasyon işlemi başka kişiye ait veya kapanmış; yeni işlem oluşturun.")
            }
            return existing
        }
        if let existing = reservations.first(where: {
            $0.bookID == book.id && !$0.isClosed && $0.identitySource != "unresolved"
                && samePerson(studentID: identity, name: canonicalName, className: effectiveClass, reservation: $0, memberID: memberID)
        }) { return existing }
        let reservation = Reservation(bookID: book.id, bookTitleSnapshot: book.title,
                                      studentName: canonicalName, studentClass: effectiveClass)
        reservation.id = operationID ?? UUID()
        reservation.studentID = identity; reservation.memberID = memberID
        reservation.identitySource = source; reservation.studentNumberSnapshot = student?.number
        reservation.needsIdentityReview = source == "unresolved"
        if context.hasChanges { try context.save() }
        do { context.insert(reservation); try context.save() }
        catch { context.rollback(); throw error }
        return reservation
    }

    /// Eski ödüncün kişi/nüsha bağlantısını stok artırmadan, tarihçeyle aynı transaction'da düzeltir.
    /// Form açıldıktan sonraki herhangi bir ödünç değişikliği eski onayı geçersiz kılar.
    @discardableResult
    static func correctLoanIdentity(_ loan: ActiveLoan, recipient: LoanIdentitySelection, copyID: UUID?,
                                    expected: ArchivedLoan, operationID: UUID, context: ModelContext,
                                    now: Date = .now, persist: (() throws -> Void)? = nil) throws -> ActiveLoan {
        try requireAdmin()
        guard !loan.isDeleted, loan.modelContext === context,
              !context.insertedModelsArray.contains(where: { ($0 as? ActiveLoan)?.id == loan.id }) else {
            throw OperationError(message: "Ödünç kaydı kapanmış veya kaydedilmemiş; kimlik düzeltilmedi.")
        }
        let student: Student?, member: Member?
        switch recipient {
        case .student(let id): student = try resolvedStudent(name: "", className: "", id: id); member = nil
        case .member(let id): member = try resolvedMember(id: id); student = nil
        }
        let name = student?.name ?? member?.name ?? ""
        let className = student?.className ?? ""
        let source = member == nil ? "student" : "member"
        let history = try historySnapshot(context: context)
        if let prior = history.first(where: { $0.id == operationID }) {
            guard prior.kind == .identityCorrected, prior.loanID == loan.id, prior.bookID == loan.bookID,
                  prior.studentID == student?.id, prior.memberID == member?.id, prior.copyID == copyID,
                  loan.studentID == student?.id, loan.memberID == member?.id, loan.copyID == copyID,
                  loan.studentName == name, loan.studentClass == className, !loan.needsIdentityReview,
                  let beforeData = prior.identityCorrectionBefore,
                  try JSONDecoder().decode(ArchivedLoan.self, from: beforeData) == expected else {
                throw OperationError(message: "Düzeltme işlemi başka kayda ait veya kayıt sonradan değişmiş; tekrar uygulanmadı.")
            }
            return loan
        }
        let loanID = loan.id
        let readContext = ModelContext(context.container)
        guard let saved = try readContext.fetch(FetchDescriptor<ActiveLoan>(predicate: #Predicate { $0.id == loanID })).first,
              ArchivedLoan(saved) == expected, ArchivedLoan(loan) == expected else {
            throw OperationError(message: "Ödünç form açıldıktan sonra değişti; güncel kaydı tekrar açın.")
        }
        guard loan.needsIdentityReview || loan.studentID == nil && loan.memberID == nil || loan.copyID == nil else {
            throw OperationError(message: "Bu ödüncün kimliği zaten açık; eski kayıt düzeltmesi uygulanmadı.")
        }
        let bookID = loan.bookID
        guard let book = try context.fetch(FetchDescriptor<CatalogBook>(predicate: #Predicate { $0.id == bookID })).first,
              !book.isDeleted, !book.isWithdrawn else { throw OperationError(message: "Kitap kaydı etkin değil.") }
        let loans = try context.fetch(FetchDescriptor<ActiveLoan>())
        let otherLoans = loans.filter { $0.id != loan.id }
        let copies = try context.fetch(FetchDescriptor<BookCopy>()).filter { $0.bookID == book.id }
        let reservations = try context.fetch(FetchDescriptor<Reservation>())
        if let copyID {
            guard let copy = copies.first(where: { $0.id == copyID }), copy.isCirculating,
                  !otherLoans.contains(where: { $0.copyID == copyID }),
                  !reservations.contains(where: {
                      $0.copyID == copyID && !$0.isClosed && $0.notifiedAt != nil && ($0.expiresAt ?? .distantFuture) > now
                          && !samePerson(studentID: student?.id, name: name, className: className, reservation: $0, memberID: member?.id)
                  }) else { throw OperationError(message: "Seçilen nüsha başka kişide, ayrılmış veya dolaşımda değil.") }
        } else {
            let unidentifiedCapacity = max(0, max(book.quantity ?? 1, copies.count) - copies.count)
            let unidentifiedLoans = otherLoans.filter { $0.bookID == book.id && $0.copyID == nil }.count
            guard unidentifiedCapacity > unidentifiedLoans else {
                throw OperationError(message: "Kimliksiz fiziksel adet kalmadı; uygun demirbaş nüshasını açıkça seçin.")
            }
        }
        let beforeData = try JSONEncoder().encode(expected)
        var event = LoanEvent(bookID: loan.bookID, bookTitle: loan.bookTitleSnapshot, person: name,
                              kind: .identityCorrected, date: now, dueDate: loan.dueDate,
                              studentID: student?.id, memberID: member?.id, identitySource: source, copyID: copyID,
                              classSnapshot: className, loanKind: loan.kind, periodSnapshot: loan.periodSnapshot)
        event.id = operationID; event.loanID = loan.id
        event.studentNumberSnapshot = student?.number; event.memberKindSnapshot = member?.kind?.rawValue
        event.identityCorrectionBefore = beforeData
        let outbox = try LibraryEventOutbox(event: event)
        if context.hasChanges { try context.save() }
        do {
            loan.studentID = student?.id; loan.memberID = member?.id
            loan.studentName = name; loan.studentClass = className; loan.identitySource = source
            loan.studentNumberSnapshot = student?.number; loan.copyID = copyID; loan.needsIdentityReview = false
            context.insert(outbox)
            if let persist { try persist() } else { try context.save() }
        } catch { context.rollback(); throw error }
        try? flushHistoryOutbox(context: context)
        return loan
    }
}
