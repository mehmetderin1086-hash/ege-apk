import Foundation
import SwiftData

nonisolated struct LibraryStock: Codable, Equatable, Sendable {
    var total: Int = 0
    var loaned: Int = 0
    var available: Int = 0
    var reserved: Int = 0
    var lost: Int = 0
    var repair: Int = 0
    var withdrawn: Int = 0
}

/// Katalog, kiosk, sınıfa dağıtım ve raporlar aynı dolaşım kurallarını kullanır.
@MainActor
enum SchoolLibraryService {
    struct OperationError: LocalizedError {
        /// Arayüzün ek soru sorabilmesi için ayırt edilebilen durumlar.
        enum Kod: String { case nushaBelirsiz, zatenElinde, kayipNushaGerekli }
        let message: String
        var kod: Kod? = nil
        var errorDescription: String? { message }
    }

    /// Nüsha seçilmeden ödünç verilirken ne yapılacağı.
    enum NushaSecimi {
        /// En eski boş nüsha otomatik seçilir (sınıfa toplu dağıtım, kiosk).
        case otomatik
        /// Birden çok boş nüsha varsa `nushaBelirsiz` hatası atılır (barkod masası).
        case sor
        /// Nüsha kimliği bağlanmaz; demirbaşsız fiziksel adet olarak yazılır.
        case nushasiz
    }

    /// Toplu işlemde tek save/flush/özet yenileme için biriken yan etkiler.
    final class BatchState {
        var hatirlaticilar: [(id: UUID, baslik: String, kisi: String, sonGun: Date)] = []
        var iptaller: [UUID] = []
        var bildirimler: [(Reservation, String)] = []
        fileprivate var lentByLoan: [UUID: LoanEvent]?
    }

    /// Toplu iadede ilk değişiklikten sonra çıkan hata: bağlam geri alınır, hiçbir iade yazılmaz.
    struct BatchAbort: Error { let underlying: Error }

    static func requireAdmin() throws {
        guard YetkiDurumu.shared.yonetici else { throw OperationError(message: "Bu işlem yönetici kimliği gerektirir.") }
    }

    static func loanCounts(_ loans: [ActiveLoan]) -> [UUID: Int] {
        Dictionary(loans.map { ($0.bookID, 1) }, uniquingKeysWith: +)
    }

    static func overdueBookIDs(_ loans: [ActiveLoan], books: [CatalogBook] = [], now: Date = .now) -> Set<UUID> {
        Set(loans.filter { $0.dueDate < Calendar.current.startOfDay(for: now) }.map(\.bookID))
            .union(books.filter { !($0.loanedTo ?? "").isEmpty && ($0.loanDueDate ?? .distantFuture) < Calendar.current.startOfDay(for: now) }.map(\.id))
    }

    static func missingFields(_ book: CatalogBook) -> [String] {
        var fields: [String] = []
        if book.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields.append("Ad") }
        if book.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields.append("Yazar") }
        if (book.isbn ?? "").isEmpty { fields.append("ISBN") }
        if (book.category ?? "").isEmpty { fields.append("Kategori") }
        if (book.publisher ?? "").isEmpty { fields.append("Yayınevi") }
        if book.coverData == nil { fields.append("Kapak") }
        if (book.cabinet ?? "").isEmpty { fields.append("Dolap") }
        if (book.shelf ?? "").isEmpty { fields.append("Raf") }
        return fields
    }

    static func stock(for book: CatalogBook, loans: [ActiveLoan], copies: [BookCopy] = [], reservations: [Reservation] = [], now: Date = .now) -> LibraryStock {
        let physical = copies.filter { $0.bookID == book.id }
        let active = loans.filter { $0.bookID == book.id }
        let total = max(max(1, book.quantity ?? 1), physical.count)
        let legacy = (book.loanedTo ?? "").isEmpty ? 0 : 1
        let lost = physical.filter { $0.status == "Kayıp" }.count
        let repair = physical.filter { $0.status == "Onarımda" }.count
        let withdrawn = physical.filter { $0.status == "Düşüldü" }.count
        let held = reservations.filter {
            $0.bookID == book.id && !$0.isClosed && $0.notifiedAt != nil && ($0.expiresAt ?? .distantFuture) > now
        }.count
        let blocked = physical.filter { !$0.isCirculating }.count
        let circulating = book.isWithdrawn ? 0 : max(0, total - blocked)
        let free = max(0, circulating - active.count - legacy)
        return LibraryStock(total: total, loaned: active.count + legacy, available: max(0, free - held),
                            reserved: min(free, held), lost: lost, repair: repair,
                            withdrawn: book.isWithdrawn ? total : withdrawn)
    }

    static func stockByBook(books: [CatalogBook], loans: [ActiveLoan], copies: [BookCopy], reservations: [Reservation], now: Date = .now) -> [UUID: LibraryStock] {
        let loansByBook = Dictionary(grouping: loans, by: \.bookID)
        let copiesByBook = Dictionary(grouping: copies, by: \.bookID)
        let reservationsByBook = Dictionary(grouping: reservations, by: \.bookID)
        return Dictionary(uniqueKeysWithValues: books.map { book in
            (book.id, stock(for: book, loans: loansByBook[book.id] ?? [], copies: copiesByBook[book.id] ?? [],
                            reservations: reservationsByBook[book.id] ?? [], now: now))
        })
    }

    static func stock(for book: CatalogBook, context: ModelContext, now: Date = .now) -> LibraryStock {
        // Okuma hatası raftaki adedi büyütmemeli: kapalı/güvenli sonuç döndür.
        guard let loans = try? context.fetch(FetchDescriptor<ActiveLoan>()),
              let copies = try? context.fetch(FetchDescriptor<BookCopy>()),
              let reservations = try? context.fetch(FetchDescriptor<Reservation>()) else {
            return LibraryStock(total: max(1, book.quantity ?? 1))
        }
        return stock(for: book, loans: loans, copies: copies, reservations: reservations, now: now)
    }

    static func availableCopies(for book: CatalogBook, loans: [ActiveLoan], copies: [BookCopy] = [], reservations: [Reservation] = []) -> Int {
        stock(for: book, loans: loans, copies: copies, reservations: reservations).available
    }

    static func minimumQuantity(for book: CatalogBook, context: ModelContext) -> Int {
        let id = book.id
        guard let count = try? context.fetchCount(FetchDescriptor<BookCopy>(predicate: #Predicate { $0.bookID == id })),
              let loanCount = try? context.fetchCount(FetchDescriptor<ActiveLoan>(predicate: #Predicate { $0.bookID == id })) else { return Int.max }
        return max(1, max(count, loanCount + ((book.loanedTo ?? "").isEmpty ? 0 : 1)))
    }

    static func student(forCard code: String) throws -> Student {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let students = try StudentStore.allVerified()
        if code.hasPrefix("OGRID") {
            let hex = String(code.dropFirst(5))
            guard hex.count == 32, hex.allSatisfy({ $0.isHexDigit }) else { throw OperationError(message: "Öğrenci kartının kimliği geçersiz.") }
            let formatted = hex.enumerated().map { index, character in ([8, 12, 16, 20].contains(index) ? "-" : "") + String(character) }.joined()
            guard let id = UUID(uuidString: formatted), let student = students.first(where: { $0.id == id }) else {
                throw OperationError(message: "Bu kartın öğrenci kaydı bulunamadı.")
            }
            return student
        }
        guard code.hasPrefix("OGR") else { throw OperationError(message: "Öğrenci kartı tanınmadı.") }
        let number = String(code.dropFirst(3))
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { throw OperationError(message: "Eski numarasız kartı yeni öğrenci kartıyla değiştirin.") }
        let matches = students.filter { $0.number.filter(\.isNumber) == number }
        guard matches.count == 1, let student = matches.first else {
            throw OperationError(message: matches.isEmpty ? "Karttaki okul numarası kayıtlı değil." : "Aynı okul numarasında birden çok öğrenci var; yeni kimlikli kartı kullanın.")
        }
        return student
    }

    static func resolvedStudent(name: String, className: String, id: UUID? = nil) throws -> Student? {
        let all = try StudentStore.allVerified()
        if let id {
            guard let student = all.first(where: { $0.id == id }) else {
                throw OperationError(message: "Öğrenci kaydı bulunamadı; yeniden seçin.")
            }
            return student
        }
        let exact = all.filter {
            CatalogMatcher.normalize($0.name) == CatalogMatcher.normalize(name)
                && (className.isEmpty || $0.className == className)
        }
        guard exact.count <= 1 else {
            throw OperationError(message: "Aynı adla birden çok öğrenci var. Öğrenci kartını veya sınıfını seçin.")
        }
        return exact.first
    }

    static func resolvedMember(id: UUID) throws -> Member {
        let matches = try MemberStore.allVerified().filter { $0.id == id }
        guard matches.count == 1, let member = matches.first else {
            throw OperationError(message: "Üye kimliği bulunamadı veya birden çok kayda ait; üyeyi yeniden seçin.")
        }
        return member
    }

    @discardableResult
    static func lend(book: CatalogBook, person: String, className: String, context: ModelContext,
                     studentID: UUID? = nil, copyID: UUID? = nil, kind: String = "library", dueDate: Date? = nil,
                     operationID: UUID? = nil, memberID: UUID? = nil,
                     resolveKnownStudent: Bool = true, periodSnapshot: String? = nil,
                     nusha: NushaSecimi = .otomatik, yineDeVer: Bool = false, batch: BatchState? = nil) throws -> ActiveLoan {
        guard !book.isDeleted, book.modelContext === context else {
            throw OperationError(message: "Kitap kaydı bu katalog bağlamında etkin değil; ödünç verilmedi.")
        }
        let requestedBookID = book.id
        // Aynı bağlama yeni eklenen eser transaction'a katılabilir; silinmiş eski form
        // veya başka bağlamdan taşınan model yetim ödünç oluşturamaz.
        guard try context.fetch(FetchDescriptor<CatalogBook>(predicate: #Predicate { $0.id == requestedBookID }))
            .contains(where: { !$0.isDeleted && $0.modelContext === context }) else {
            throw OperationError(message: "Kitap kaydı artık katalogda bulunmuyor; güncel kaydı açın.")
        }
        let name = person.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw OperationError(message: "Ödünç alan kişi boş olamaz.") }
        guard !book.isWithdrawn else { throw OperationError(message: "Koleksiyondan düşülmüş kitap ödünç verilemez.") }
        guard studentID == nil || memberID == nil else { throw OperationError(message: "Öğrenci ve üye aynı işlemde birlikte seçilemez.") }
        let member = try memberID.map { try resolvedMember(id: $0) }
        let student = memberID == nil && (resolveKnownStudent || studentID != nil)
            ? try resolvedStudent(name: name, className: className, id: studentID) : nil
        if memberID == nil && studentID == nil && resolveKnownStudent, student != nil,
           try MemberStore.allVerified().contains(where: { CatalogMatcher.normalize($0.name) == CatalogMatcher.normalize(name) }) {
            throw OperationError(message: "Aynı adla öğrenci ve üye var. Öğrenci veya üye kaydını açıkça seçin.")
        }
        let identity = student?.id ?? studentID
        let effectiveClass = member == nil ? student?.className ?? className : ""
        let canonicalName = member?.name ?? student?.name ?? name
        let loans = try context.fetch(FetchDescriptor<ActiveLoan>())
        if let operationID {
            if let existing = loans.first(where: { $0.id == operationID }) {
                let sameIdentity: Bool
                if memberID != nil || existing.memberID != nil { sameIdentity = memberID != nil && memberID == existing.memberID }
                else if identity != nil || existing.studentID != nil { sameIdentity = identity != nil && identity == existing.studentID }
                else { sameIdentity = CatalogMatcher.normalize(existing.studentName) == CatalogMatcher.normalize(canonicalName) && existing.studentClass == effectiveClass }
                guard existing.bookID == book.id, sameIdentity, existing.kind == kind else {
                    throw OperationError(message: "Bu işlem kimliği başka bir kitap veya kişiye ait; kayıt değişmedi.")
                }
                return existing
            }
            guard !(try historySnapshot(context: context)).contains(where: { $0.id == operationID }) else {
                throw OperationError(message: "Bu işlem daha önce tamamlandı; yeni ödünç için yeni işlem oluşturun.")
            }
        }
        let kitapKimligi = book.id
        let copies = try context.fetch(FetchDescriptor<BookCopy>(predicate: #Predicate { $0.bookID == kitapKimligi }))
        let reservations = try context.fetch(FetchDescriptor<Reservation>(predicate: #Predicate { $0.bookID == kitapKimligi }))
        let memberRule = member == nil ? nil : try MemberLoanRuleStore.rule(for: member?.kind)
        let gradeRules = member == nil ? try GradeLoanRuleStore.allVerified() : []
        let ownHolds = reservations.filter { (memberID != nil || identity != nil || !resolveKnownStudent) &&
            $0.bookID == book.id && !$0.isClosed && $0.notifiedAt != nil && ($0.expiresAt ?? .distantFuture) > .now
                && samePerson(studentID: identity, name: canonicalName, className: effectiveClass, reservation: $0, memberID: memberID)
        }
        let state = stock(for: book, loans: loans, copies: copies, reservations: reservations)
        guard state.available + min(state.reserved, ownHolds.count) > 0 else { throw OperationError(message: "“\(book.title)” için verilebilir boş nüsha yok.") }
        if kind == "library" {
            let relevant = loans.filter { loan in
                guard loan.kind != "textbook" else { return false }
                if let memberID { return loan.memberID == memberID }
                guard loan.memberID == nil else { return false }
                if let identity { return loan.studentID == identity || (loan.studentID == nil && loan.identitySource != "manual" && !loan.needsIdentityReview) }
                return loan.studentID == nil
            }
            try OduncKotasi.denetle(kisi: canonicalName, sinif: effectiveClass, loans: relevant,
                kurallar: gradeRules,
                genelSinir: memberRule?.maximumLoans ?? UserDefaults.standard.integer(forKey: OduncKotasi.genelSinirAnahtari),
                studentID: identity, memberID: memberID)
        }
        // Aynı eser, aynı okur: ikinci nüsha yanlışlıkla (çift okutma) verilmesin. Ders kitabı setleri kasıtlı çift verilebilir.
        if kind != "textbook", !yineDeVer {
            let elinde = loans.contains { loan in
                guard loan.bookID == book.id, loan.kind != "textbook" else { return false }
                if let memberID { return loan.memberID == memberID }
                if let identity { return loan.studentID == identity && loan.memberID == nil }
                return loan.studentID == nil && loan.memberID == nil
                    && CatalogMatcher.normalize(loan.studentName) == CatalogMatcher.normalize(canonicalName) && loan.studentClass == effectiveClass
            }
            if elinde {
                throw OperationError(message: "\(canonicalName) “\(book.title)” kitabını zaten ödünçte tutuyor. İkinci nüshayı yine de vermek için onaylayın.", kod: .zatenElinde)
            }
        }
        let outIDs = Set(loans.compactMap(\.copyID))
        let heldByOthers = Set(reservations.filter { reservation in !reservation.isClosed && reservation.notifiedAt != nil && (reservation.expiresAt ?? .distantFuture) > .now && !ownHolds.contains(where: { $0.id == reservation.id }) }.compactMap(\.copyID))
        let freeCopies = copies.filter { $0.bookID == book.id && $0.isCirculating && !outIDs.contains($0.id) && !heldByOthers.contains($0.id) }
        let selected: BookCopy?
        if let copyID {
            guard let copy = freeCopies.first(where: { $0.id == copyID }) else { throw OperationError(message: "Seçilen nüsha ödünç verilemiyor.") }
            selected = copy
        } else {
            switch nusha {
            case .nushasiz: selected = nil
            case .sor:
                if freeCopies.count > 1 {
                    throw OperationError(message: "“\(book.title)” kitabının \(freeCopies.count) boş nüshası var. Hangisini verdiğinizi seçin ya da demirbaşını okutun.", kod: .nushaBelirsiz)
                }
                selected = freeCopies.first
            case .otomatik: selected = freeCopies.sorted { $0.addedAt < $1.addedAt }.first
            }
        }
        let days = memberRule?.durationDays ?? GradeLoanRuleStore.explicitRule(for: effectiveClass, rules: gradeRules)?.loanDurationDays ?? max(1, UserDefaults.standard.integer(forKey: "loanDurationDays") == 0 ? 15 : UserDefaults.standard.integer(forKey: "loanDurationDays"))
        let due = dueDate ?? Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .now
        let loan = ActiveLoan(bookID: book.id, bookTitleSnapshot: book.title, studentName: canonicalName,
                              studentClass: effectiveClass, dueDate: due)
        if let operationID { loan.id = operationID }
        loan.studentID = identity
        loan.memberID = memberID
        loan.studentNumberSnapshot = student?.number
        loan.identitySource = memberID != nil ? "member" : identity != nil ? "student" : resolveKnownStudent ? "unresolved" : "manual"
        if identity == nil, memberID == nil, !resolveKnownStudent {
            loan.needsIdentityReview = try StudentStore.allVerified().contains { CatalogMatcher.normalize($0.name) == CatalogMatcher.normalize(name) }
                || MemberStore.allVerified().contains { CatalogMatcher.normalize($0.name) == CatalogMatcher.normalize(name) }
        }
        loan.copyID = selected?.id
        loan.kind = kind
        let period = periodSnapshot?.trimmingCharacters(in: .whitespacesAndNewlines)
        loan.periodSnapshot = kind == "textbook" ? ((period ?? "").isEmpty ? TextbookOperations.currentPeriod() : period) : period
        var event = LoanEvent(bookID: book.id, bookTitle: book.title, person: loan.studentName, kind: .lent,
                                         date: loan.loanedAt, dueDate: due, studentID: identity, memberID: memberID, identitySource: loan.identitySource, copyID: loan.copyID,
                                         classSnapshot: loan.studentClass, loanKind: kind, periodSnapshot: loan.periodSnapshot)
        if let operationID { event.id = operationID }
        event.studentNumberSnapshot = loan.studentNumberSnapshot
        event.memberKindSnapshot = member?.kind?.rawValue
        event.loanID = loan.id
        // Toplu işlemde olay kaydı, kayıt eklenmeden önce üretilir: hata yarım ödünç bırakmaz.
        let toplu = try batch.map { _ in try LibraryEventOutbox(event: event) }
        context.insert(loan)
        for reservation in reservations where (memberID != nil || identity != nil || !resolveKnownStudent) && !reservation.isClosed && reservation.bookID == book.id
            && samePerson(studentID: identity, name: canonicalName, className: effectiveClass, reservation: reservation, memberID: memberID) {
            reservation.isClosed = true
            reservation.closureKind = "delivered"; reservation.closedAt = .now
        }
        if let batch, let toplu {
            context.insert(toplu)
            if kind != "textbook" { batch.hatirlaticilar.append((loan.id, book.title, loan.studentName, due)) }
            return loan
        }
        try commit(event: event, context: context)
        if kind != "textbook" { LoanReminders.schedule(bookID: loan.id, title: book.title, person: loan.studentName, dueDate: due) }
        return loan
    }

    struct BatchLendResult {
        var loans: [ActiveLoan] = []
        /// Zaten bu kitabı elinde tutan okurlar (atlandı).
        var skipped: [String] = []
        var failures: [String] = []
    }

    /// Aynı kitabı birçok öğrenciye verir: kayıtlar tek `save`, tek geçmiş aktarımı ve tek gecikenler
    /// özeti yenilemesiyle yazılır. Öğrenci bazlı kural hataları (kota, stok, zaten elinde) o öğrenciyi atlar;
    /// kaydın kendisi yazılamazsa hiçbir ödünç kalmaz.
    static func batchLend(book: CatalogBook, students: [Student], className: String, kind: String = "library",
                          dueDate: Date? = nil, periodSnapshot: String? = nil, context: ModelContext) throws -> BatchLendResult {
        try requireAdmin()
        let batch = BatchState()
        var result = BatchLendResult()
        for student in students {
            do {
                result.loans.append(try lend(book: book, person: student.name, className: className, context: context,
                                             studentID: student.id, kind: kind, dueDate: dueDate, periodSnapshot: periodSnapshot, batch: batch))
            } catch let error as OperationError where error.kod == .zatenElinde {
                result.skipped.append(student.name)
            } catch { result.failures.append("\(student.name): \(error.localizedDescription)") }
        }
        guard !result.loans.isEmpty else { return result }
        do { try context.save() } catch { context.rollback(); throw error }
        batchSonrasi(batch, context: context)
        return result
    }

    struct BatchReturnResult {
        var returned: Set<UUID> = []
        var failures: [UUID: String] = [:]
        /// Sıradaki rezervasyon sahiplerine verilen haberler.
        var notices: [String] = []
    }

    /// Birçok ödüncü tek `save` ile iade alır. Doğrulama hatası olan satır atlanır ve başarısızlıklara yazılır;
    /// yazma sırasında beklenmeyen hata çıkarsa tüm toplu iade geri alınır.
    static func batchReturn(_ loans: [ActiveLoan], conditions: [UUID: String] = [:], context: ModelContext, now: Date = .now) throws -> BatchReturnResult {
        let batch = BatchState()
        var result = BatchReturnResult()
        for loan in loans {
            let id = loan.id, name = loan.studentName
            do {
                _ = try returnLoan(loan, context: context, now: now, returnedCondition: conditions[id], batch: batch)
                result.returned.insert(id)
            } catch let abort as BatchAbort {
                context.rollback()
                throw abort.underlying
            } catch { result.failures[id] = "\(name): \(error.localizedDescription)" }
        }
        guard !result.returned.isEmpty else { return result }
        do { try context.save() } catch { context.rollback(); throw error }
        result.notices = batchSonrasi(batch, context: context)
        return result
    }

    /// Tek seferlik yan etkiler: geçmiş aktarımı, hatırlatmalar, rezervasyon haberleri, gecikenler özeti.
    @discardableResult
    private static func batchSonrasi(_ batch: BatchState, context: ModelContext) -> [String] {
        try? flushHistoryOutbox(context: context)
        for item in batch.hatirlaticilar { LoanReminders.schedule(bookID: item.id, title: item.baslik, person: item.kisi, dueDate: item.sonGun) }
        for id in batch.iptaller { LoanReminders.cancel(bookID: id) }
        let haberler = batch.bildirimler.map { OduncMerkezi.notifyReadyReservation($0.0, title: $0.1) }
        LoanReminders.gecikenOzetiniYenile(context: context)
        return haberler
    }

    static func samePerson(studentID: UUID?, name: String, className: String, reservation: Reservation, memberID: UUID? = nil) -> Bool {
        guard !reservation.needsIdentityReview else { return false }
        // Öğrenci/üye UUID'leri ayrı ad alanlarıdır; adı aynı olan iki kişi birleşmez.
        if memberID != nil || reservation.memberID != nil {
            return memberID != nil && memberID == reservation.memberID && studentID == nil && reservation.studentID == nil
        }
        if studentID != nil || reservation.studentID != nil {
            return studentID != nil && studentID == reservation.studentID
        }
        return CatalogMatcher.normalize(reservation.studentName) == CatalogMatcher.normalize(name)
            && reservation.studentClass == className
    }

    /// Vade değişikliği ve kimlikli hareket aynı SwiftData commit'inde dayanıklıdır.
    @discardableResult
    static func extendLoan(_ loan: ActiveLoan, context: ModelContext, defaultDays: Int = 15, now: Date = .now,
                           operationID: UUID? = nil, expectedDueDate: Date? = nil, expectedExtensionCount: Int? = nil,
                           defaults: UserDefaults = .standard, persist: (() throws -> Void)? = nil) throws -> Date {
        guard !loan.isDeleted, loan.modelContext === context,
              !context.insertedModelsArray.contains(where: { ($0 as? ActiveLoan)?.id == loan.id }) else {
            throw OperationError(message: "Bu ödünç kaydedilmemiş veya kapanmış; süre uzatılmadı.")
        }
        let id = loan.id
        let readContext = ModelContext(context.container)
        guard let saved = try readContext.fetch(FetchDescriptor<ActiveLoan>(predicate: #Predicate { $0.id == id })).first,
              saved.bookID == loan.bookID, saved.studentID == loan.studentID, saved.memberID == loan.memberID,
              saved.copyID == loan.copyID, saved.studentName == loan.studentName, saved.studentClass == loan.studentClass,
              saved.kind == loan.kind, saved.identitySource == loan.identitySource,
              saved.dueDate == loan.dueDate, saved.extensionCount == loan.extensionCount else {
            throw OperationError(message: "Ödünç kaydı değişti veya kapanmış. Güncel kaydı açıp tekrar deneyin.")
        }
        let history = try historySnapshot(context: context)
        if let operationID, let prior = history.first(where: { $0.id == operationID }) {
            guard prior.kind == .extended, prior.loanID == loan.id, prior.bookID == loan.bookID,
                  prior.studentID == loan.studentID, prior.memberID == loan.memberID, prior.copyID == loan.copyID,
                  prior.person == loan.studentName, prior.classSnapshot == loan.studentClass,
                  prior.loanKind == loan.kind, let after = prior.dueDate,
                  abs(after.timeIntervalSince(loan.dueDate)) < 1 else {
                throw OperationError(message: "Bu uzatma işlemi başka bir kayda ait veya vade sonradan değişmiş; ikinci uzatma yapılmadı.")
            }
            return loan.dueDate
        }
        guard expectedDueDate.map({ $0 == loan.dueDate }) ?? true,
              expectedExtensionCount.map({ $0 == loan.extensionCount }) ?? true else {
            throw OperationError(message: "Onaylanan eski vade artık güncel değil. Ödüncü tekrar açın.")
        }
        guard loan.extensionCount >= 0, loan.extensionCount < OduncMerkezi.enFazlaUzatma else {
            throw OperationError(message: "Bu ödünç en fazla \(OduncMerkezi.enFazlaUzatma) kez uzatılabilir.")
        }
        guard loan.studentID == nil || loan.memberID == nil, !loan.needsIdentityReview else {
            throw OperationError(message: "Ödünç alanın kimliği netleştirilmeli; süre uzatılmadı.")
        }
        let bookID = loan.bookID
        guard let book = try context.fetch(FetchDescriptor<CatalogBook>(predicate: #Predicate { $0.id == bookID })).first,
              !book.isDeleted, !book.isWithdrawn else { throw OperationError(message: "Kitap kaydı dolaşımda değil; süre uzatılamaz.") }
        let pending = try context.fetch(FetchDescriptor<Reservation>(predicate: #Predicate { $0.bookID == bookID && !$0.isClosed }))
        guard pending.filter({ $0.expiresAt.map { $0 > now } ?? true }).allSatisfy({ reservation in
            samePerson(studentID: loan.studentID, name: loan.studentName, className: loan.studentClass,
                       reservation: reservation, memberID: loan.memberID)
        }) else { throw OperationError(message: "Bu kitabı başka kişi bekliyor; süre uzatılamaz.") }
        let member = try loan.memberID.map { try resolvedMember(id: $0) }
        let memberRule = member != nil ? try MemberLoanRuleStore.rule(for: member?.kind, defaults: defaults) : nil
        let gradeRule = member == nil ? GradeLoanRuleStore.explicitRule(for: loan.studentClass, rules: try GradeLoanRuleStore.allVerified()) : nil
        let days = memberRule?.durationDays ?? gradeRule?.loanDurationDays ?? defaultDays
        guard (1...365).contains(days), now.timeIntervalSince1970.isFinite, loan.dueDate.timeIntervalSince1970.isFinite else {
            throw OperationError(message: "Uzatma süresi 1–365 gün arasında ve vade geçerli olmalı.")
        }
        let previousDue = loan.dueDate
        let start = max(previousDue, now)
        guard let due = Calendar.current.date(byAdding: .day, value: days, to: start), due > start else {
            throw OperationError(message: "Yeni vade hesaplanamadı; ödünç değişmedi.")
        }
        var event = LoanEvent(bookID: loan.bookID, bookTitle: loan.bookTitleSnapshot, person: loan.studentName,
            kind: .extended, date: now, dueDate: due, studentID: loan.studentID, memberID: loan.memberID,
            identitySource: loan.identitySource, copyID: loan.copyID, classSnapshot: loan.studentClass,
            loanKind: loan.kind, periodSnapshot: loan.periodSnapshot)
        event.id = operationID ?? UUID()
        event.loanID = loan.id
        event.previousDueDate = previousDue
        event.studentNumberSnapshot = loan.studentNumberSnapshot
        event.memberKindSnapshot = history.first(where: { $0.loanID == loan.id && $0.kind == .lent })?.memberKindSnapshot
        // Formun diğer bekleyen değişikliklerini sonraki rollback'in silmesini önler.
        if context.hasChanges { try context.save() }
        do {
            let outbox = try LibraryEventOutbox(event: event)
            loan.dueDate = due
            loan.extensionCount += 1
            context.insert(outbox)
            if let persist { try persist() } else { try context.save() }
        } catch { context.rollback(); throw error }
        // JSON aktarımı gecikse de aynı operationID dayanıklı outbox'tan tek kez okunur.
        try? flushHistoryOutbox(context: context)
        if loan.kind != "textbook" {
            LoanReminders.schedule(bookID: loan.id, title: loan.bookTitleSnapshot, person: loan.studentName, dueDate: due)
        }
        LoanReminders.gecikenOzetiniYenile(context: context)
        return due
    }

    @discardableResult
    static func returnLoan(_ loan: ActiveLoan, context: ModelContext, now: Date = .now, returnedCondition: String? = nil, readingCompleted: Bool? = nil,
                           batch: BatchState? = nil) throws -> String? {
        guard !loan.isDeleted, loan.modelContext != nil else { throw OperationError(message: "Bu ödünç zaten kapatılmış veya kaydedilmemiş; yeni iade hareketi oluşturulmadı.") }
        if let returnedCondition, !BookCopy.conditions.contains(returnedCondition) { throw OperationError(message: "Teslim alınan nüshanın fiziksel durumu geçersiz.") }
        let loanCopyID = loan.copyID
        var returnedCopy: BookCopy?
        if let returnedCondition {
            if let loanCopyID {
                let iadeKitabi = loan.bookID
                returnedCopy = try context.fetch(FetchDescriptor<BookCopy>(predicate: #Predicate { $0.id == loanCopyID && $0.bookID == iadeKitabi })).first
                guard returnedCopy != nil else { throw OperationError(message: "Ödüncün nüsha kaydı bulunamadı; hasar işlemi yapılmadı.") }
            } else if returnedCondition == "Onarım gerekli" || returnedCondition == "Yıpranmış" {
                // Nüsha kimliği olmayan eski ödünçte hasar yeni bir nüsha kaydına işlenir. Kitabın tüm
                // nüshaları zaten kayıtlıysa yeni kayıt olmayan bir nüshayı stoğa eklerdi.
                let bookID = loan.bookID
                let kayitliNusha = try context.fetchCount(FetchDescriptor<BookCopy>(predicate: #Predicate { $0.bookID == bookID }))
                let adet = try context.fetch(FetchDescriptor<CatalogBook>(predicate: #Predicate { $0.id == bookID })).first.map { max(1, $0.quantity ?? 1) } ?? 1
                guard kayitliNusha < adet else {
                    throw OperationError(message: "Bu ödünçte nüsha kimliği yok ve kitabın tüm nüshaları kayıtlı; hasarın hangi nüshaya işleneceği bilinemiyor. Önce ödünç ayrıntısından nüsha kimliğini düzeltin.")
                }
                returnedCopy = BookCopy(bookID: loan.bookID, condition: returnedCondition,
                                       status: returnedCondition == "Onarım gerekli" ? "Onarımda" : "Rafta",
                                       note: loan.kind == "textbook" ? "Ders kitabı tesliminde durum kaydı" : "İadede durum kaydı")
            }
        }
        var event = LoanEvent(bookID: loan.bookID, bookTitle: loan.bookTitleSnapshot, person: loan.studentName,
                              kind: .returned, date: now, dueDate: loan.dueDate,
                              wasLate: loan.dueDate < Calendar.current.startOfDay(for: now), studentID: loan.studentID,
                              memberID: loan.memberID, identitySource: loan.identitySource, copyID: returnedCopy?.id ?? loan.copyID,
                              classSnapshot: loan.studentClass, loanKind: loan.kind, periodSnapshot: loan.periodSnapshot, returnedCondition: returnedCondition)
        event.studentNumberSnapshot = try numberSnapshot(for: loan)
        event.memberKindSnapshot = try batch.map { try memberKindSnapshot(for: loan, batch: $0, context: context) } ?? memberKindSnapshot(for: loan, context: context)
        event.loanID = loan.id
        event.readingCompleted = loan.kind == "textbook" ? nil : readingCompleted
        let loanID = loan.id, bookID = loan.bookID, title = loan.bookTitleSnapshot, copyID = loan.copyID
        do {
            if let returnedCopy, let returnedCondition {
                if returnedCopy.modelContext == nil { context.insert(returnedCopy) }
                returnedCopy.condition = returnedCondition
                returnedCopy.status = returnedCondition == "Onarım gerekli" ? "Onarımda" : "Rafta"
            }
            context.delete(loan)
            let reservation = try prepareNextReservation(bookID: bookID, copyID: copyID, context: context, now: now)
            if let batch {
                context.insert(try LibraryEventOutbox(event: event))
                batch.iptaller.append(loanID)
                if let reservation { batch.bildirimler.append((reservation, title)) }
                return nil
            }
            try commit(event: event, context: context)
            LoanReminders.cancel(bookID: loanID)
            guard let reservation else { return nil }
            return OduncMerkezi.notifyReadyReservation(reservation, title: title)
        } catch {
            // Toplu işlemde bağlam diğer iadelerle paylaşılır: geri alma kararı toplu işleme aittir.
            if batch != nil { throw BatchAbort(underlying: error) }
            context.rollback(); throw error
        }
    }

    /// Barkodla iadede eşleşen etkin ödünçler. Öğrenci seçiliyse yalnız onun kimlikli (ya da adla
    /// eşleşen eski) ödünçleri; seçili değilse kitabın (demirbaş okutulduysa o nüshanın) bütün
    /// ödünçleri, üye ödünçleri dahil. Öğrencisiz iadede kitabın birden çok nüshası varsa ve
    /// demirbaş okutulmadıysa tek aday da onaylatılır: okutulan nüsha başka okurun olabilir.
    /// Okutulan nüsha hiçbir açık ödünce bağlı değilse kitap, nüsha kaydı yokken (nüshasız) verilmiştir:
    /// o zaman kitabın nüshasız ödünçleri aday olur ve ISBN okutulmuş gibi değerlendirilir.
    static func iadeAdaylari(loans: [ActiveLoan], bookID: UUID, copyID: UUID?, student: Student?,
                             nushaSayisi: Int) -> (adaylar: [ActiveLoan], onayGerekir: Bool) {
        let kitabin = loans.filter { $0.bookID == bookID }
        let nushaBagli = copyID != nil && kitabin.contains { $0.copyID == copyID }
        let adaylar = kitabin.filter { loan in
            if copyID != nil, loan.copyID != (nushaBagli ? copyID : nil) { return false }
            guard let student else { return true }
            return loan.memberID == nil && (loan.studentID == student.id
                || (loan.studentID == nil && loan.identitySource != "manual"
                    && CatalogMatcher.normalize(loan.studentName) == CatalogMatcher.normalize(student.name)
                    && loan.studentClass == student.className))
        }
        .sorted { $0.dueDate != $1.dueDate ? $0.dueDate < $1.dueDate : $0.loanedAt < $1.loanedAt }
        let onay = adaylar.count > 1 || (adaylar.count == 1 && student == nil && !nushaBagli && nushaSayisi > 1)
        return (adaylar, onay)
    }

    @discardableResult
    static func giveBack(book: CatalogBook, person: String, className: String = "", studentID: UUID? = nil, copyID: UUID? = nil,
                         context: ModelContext, now: Date = .now, memberID: UUID? = nil, loanID: UUID? = nil, readingCompleted: Bool? = nil) throws -> String? {
        guard studentID == nil || memberID == nil else { throw OperationError(message: "Öğrenci ve üye birlikte seçilemez.") }
        let id = book.id
        let loans = try context.fetch(FetchDescriptor<ActiveLoan>(predicate: #Predicate { $0.bookID == id }))
        let wanted = CatalogMatcher.normalize(person)
        let candidates = loans.filter { loan in
            if let loanID, loan.id != loanID { return false }
            if let copyID, loan.copyID != copyID { return false }
            if let memberID { return loan.memberID == memberID && loan.studentID == nil }
            if let studentID { return loan.studentID == studentID && loan.memberID == nil }
            if loanID == nil, loan.studentID != nil || loan.memberID != nil { return false }
            if wanted.isEmpty { return true }
            return CatalogMatcher.normalize(loan.studentName) == wanted && (className.isEmpty || loan.studentClass == className)
        }
        guard candidates.count == 1, let loan = candidates.first else {
            throw OperationError(message: candidates.isEmpty ? "Bu kişi adına ödünç kaydı bulunamadı." : "Birden çok ödünç var; nüshayı veya ödünç kaydını seçin.")
        }
        return try returnLoan(loan, context: context, now: now, readingCompleted: readingCompleted)
    }

    static func reportLost(_ loan: ActiveLoan, context: ModelContext, now: Date = .now) throws -> String {
        try requireAdmin()
        let id = loan.bookID
        let book = try context.fetch(FetchDescriptor<CatalogBook>(predicate: #Predicate { $0.id == id })).first
        let copyID = loan.copyID
        let kitapKopyalari = try context.fetch(FetchDescriptor<BookCopy>(predicate: #Predicate { $0.bookID == id }))
        // Nüsha kayıtları varken hangi nüshanın kaybolduğu bilinmiyorsa adet düşürmek yanlış nüshayı sayıdan çıkarır.
        if copyID == nil, !kitapKopyalari.isEmpty {
            throw OperationError(message: "Bu ödünç hiçbir nüshaya bağlı değil, ama kitabın nüsha kayıtları var. Önce ödüncün nüshasını düzeltin; sonra kayıp bildirin.", kod: .kayipNushaGerekli)
        }
        let copy = kitapKopyalari.first { $0.id == copyID }
        let report = OduncMerkezi.kayipTutanagi(kitapAdi: loan.bookTitleSnapshot, yazar: book?.author ?? "",
                                               isbn: book?.isbn ?? "", demirbas: copy?.accessionCode ?? book?.accessionCode ?? "",
                                               ogrenci: loan.studentName, sinif: loan.studentClass, verilis: loan.loanedAt, tarih: now)
        var event = LoanEvent(bookID: id, bookTitle: loan.bookTitleSnapshot, person: loan.studentName, kind: .lost,
                              date: now, dueDate: loan.dueDate, wasLate: loan.dueDate < Calendar.current.startOfDay(for: now),
                              studentID: loan.studentID, memberID: loan.memberID, identitySource: loan.identitySource, copyID: copyID, classSnapshot: loan.studentClass, loanKind: loan.kind, periodSnapshot: loan.periodSnapshot)
        event.studentNumberSnapshot = try numberSnapshot(for: loan)
        event.memberKindSnapshot = try memberKindSnapshot(for: loan, context: context)
        event.loanID = loan.id
        if let copy { copy.status = "Kayıp" }
        else if let book {
            if (book.quantity ?? 1) > 1 { book.quantity = (book.quantity ?? 1) - 1 }
            else { book.isWithdrawn = true; book.withdrawnReason = "Kayıp"; book.withdrawnDate = now }
        }
        let loanID = loan.id
        context.delete(loan)
        try commit(event: event, context: context)
        LoanReminders.cancel(bookID: loanID)
        return report
    }

    static var pendingHistoryWarning: String? { LibrarySyncStatus.shared.warning }

    /// SwiftData'da commit edilmiş hareketler JSON'a kimliğe göre tek kez aktarılır.
    /// Ayrı context kullanımı formdaki başka bekleyen değişiklikleri rollback ile silemez.
    static func flushHistoryOutbox(context: ModelContext) throws {
        let syncContext = ModelContext(context.container)
        syncContext.autosaveEnabled = false
        do {
            let pending = try syncContext.fetch(FetchDescriptor<LibraryEventOutbox>(sortBy: [SortDescriptor(\.createdAt)]))
            guard !pending.isEmpty else { LibrarySyncStatus.shared.warning = nil; return }
            var events = try LoanHistoryStore.allVerified(reload: false)
            var positions = Dictionary(events.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
            for record in pending {
                let event = try record.decodedEvent()
                guard event.id == record.id else { throw OperationError(message: "Bekleyen ödünç hareketinin kimliği tutarsız.") }
                if let index = positions[event.id] { if record.replacesExisting { events[index] = event } }
                else { positions[event.id] = events.count; events.append(event) }
            }
            try LoanHistoryStore.replaceAll(events)
            pending.forEach(syncContext.delete)
            do { try syncContext.save() } catch { syncContext.rollback(); throw error }
            LibrarySyncStatus.shared.warning = nil
        } catch {
            LibrarySyncStatus.shared.warning = "Ödünç işlemi katalogda kaydedildi. Geçmiş aktarımı bekliyor; yeniden deneyin. " + error.localizedDescription
            AppLog.write("Ödünç geçmişi outbox aktarımı bekliyor")
            throw error
        }
    }

    static func historySnapshot(context: ModelContext) throws -> [LoanEvent] {
        var events = try LoanHistoryStore.allVerified(reload: false)
        var positions = Dictionary(events.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let readContext = ModelContext(context.container)
        for record in try readContext.fetch(FetchDescriptor<LibraryEventOutbox>()) {
            let event = try record.decodedEvent()
            guard event.id == record.id else { throw OperationError(message: "Bekleyen ödünç hareketinin kimliği tutarsız.") }
            if let index = positions[event.id] { if record.replacesExisting { events[index] = event } }
            else { positions[event.id] = events.count; events.append(event) }
        }
        return events
    }

    static func memberKindSnapshot(for loan: ActiveLoan, context: ModelContext) throws -> String? {
        if let borrowed = try historySnapshot(context: context).first(where: { $0.loanID == loan.id && $0.kind == .lent }) {
            return borrowed.memberKindSnapshot
        }
        return nil
    }

    /// Toplu iadede geçmiş bir kez okunur; her iade için diski ve outbox'ı yeniden taramaz.
    static func memberKindSnapshot(for loan: ActiveLoan, batch: BatchState, context: ModelContext) throws -> String? {
        if batch.lentByLoan == nil {
            var index: [UUID: LoanEvent] = [:]
            for event in try historySnapshot(context: context) where event.kind == .lent {
                if let id = event.loanID, index[id] == nil { index[id] = event }
            }
            batch.lentByLoan = index
        }
        return batch.lentByLoan?[loan.id]?.memberKindSnapshot
    }

    static func commit(event: LoanEvent, context: ModelContext) throws {
        do {
            context.insert(try LibraryEventOutbox(event: event))
            try context.save()
        } catch { context.rollback(); throw error }
        // Kalıcı ödünç başarılıdır. JSON IO hatası aynı işlemi yeniden ödünçlendirmeye yönlendirmez.
        do { try flushHistoryOutbox(context: context) }
        catch { /* Dayanıklı outbox ve görünür LibrarySyncStatus sonraki denemeye taşınır. */ }
        // Ödünç/iade/kayıp sonrası gecikenler özeti güncel sayıyı göstersin
        LoanReminders.gecikenOzetiniYenile(context: context)
    }

    static func prepareNextReservation(bookID: UUID, copyID: UUID?, context: ModelContext, now: Date) throws -> Reservation? {
        let id = bookID
        let pending = try context.fetch(FetchDescriptor<Reservation>(predicate: #Predicate { $0.bookID == id && !$0.isClosed }, sortBy: [SortDescriptor(\.createdAt)]))
        for reservation in pending where reservation.notifiedAt != nil && (reservation.expiresAt ?? .distantFuture) <= now {
            reservation.isClosed = true; reservation.closureKind = "expired"; reservation.closedAt = now
        }
        guard let book = try context.fetch(FetchDescriptor<CatalogBook>(predicate: #Predicate { $0.id == id })).first else { return nil }
        let loans = try context.fetch(FetchDescriptor<ActiveLoan>(predicate: #Predicate { $0.bookID == id }))
        let copies = try context.fetch(FetchDescriptor<BookCopy>(predicate: #Predicate { $0.bookID == id }))
        guard stock(for: book, loans: loans, copies: copies, reservations: pending, now: now).available > 0 else { return nil }
        let busy = Set(loans.compactMap(\.copyID)).union(pending.filter { !$0.isClosed && $0.notifiedAt != nil }.compactMap(\.copyID))
        let freeCopies = copies.filter { $0.bookID == bookID && $0.isCirculating && !busy.contains($0.id) }
        guard let next = pending.first(where: { !$0.isClosed && $0.notifiedAt == nil }) else { return nil }
        next.notifiedAt = now
        next.expiresAt = ReservationPolicy.ayarliBitis(from: now)
        next.copyID = freeCopies.first(where: { $0.id == copyID })?.id ?? freeCopies.first?.id
        return next
    }

    /// Hazır rezervasyon süresi bittiğinde sıra ilerler; bildirimi yalnız başarılı yazımdan sonra kurar.
    @discardableResult
    static func refreshReservations(context: ModelContext, now: Date = .now, notify: Bool = true) throws -> Int {
        let books = try context.fetch(FetchDescriptor<CatalogBook>())
        let loans = try context.fetch(FetchDescriptor<ActiveLoan>())
        let copies = try context.fetch(FetchDescriptor<BookCopy>())
        let reservations = try context.fetch(FetchDescriptor<Reservation>(sortBy: [SortDescriptor(\.createdAt)]))
        for reservation in reservations where !reservation.isClosed {
            if let notifiedAt = reservation.notifiedAt, reservation.expiresAt == nil { reservation.expiresAt = ReservationPolicy.ayarliBitis(from: notifiedAt) }
            if reservation.notifiedAt != nil && (reservation.expiresAt ?? .distantFuture) <= now {
                reservation.isClosed = true; reservation.closureKind = "expired"; reservation.closedAt = now
            }
        }
        var notices: [(Reservation, String)] = []
        for book in books where !book.isWithdrawn {
            var available = stock(for: book, loans: loans, copies: copies, reservations: reservations, now: now).available
            guard available > 0 else { continue }
            let usedIDs = Set(loans.compactMap(\.copyID)).union(reservations.filter { !$0.isClosed && $0.notifiedAt != nil }.compactMap(\.copyID))
            var freeCopies = copies.filter { $0.bookID == book.id && $0.isCirculating && !usedIDs.contains($0.id) }.sorted { $0.addedAt < $1.addedAt }
            for pending in reservations where pending.bookID == book.id && !pending.isClosed && pending.notifiedAt == nil {
                guard available > 0 else { break }
                pending.notifiedAt = now; pending.expiresAt = ReservationPolicy.ayarliBitis(from: now)
                if !freeCopies.isEmpty { pending.copyID = freeCopies.removeFirst().id }
                available -= 1; notices.append((pending, book.title))
            }
        }
        do { try context.save() } catch { context.rollback(); throw error }
        if notify { for (reservation, title) in notices { _ = OduncMerkezi.notifyReadyReservation(reservation, title: title) } }
        return notices.count
    }

    static func cancelReservation(_ reservation: Reservation, context: ModelContext, now: Date = .now) throws {
        guard !reservation.isDeleted, reservation.modelContext != nil, !reservation.isClosed else {
            throw OperationError(message: "Bu rezervasyon zaten kapanmış veya bulunamadı; kayıt değişmedi.")
        }
        reservation.isClosed = true; reservation.closureKind = "cancelled"; reservation.closedAt = now
        do { _ = try refreshReservations(context: context, now: now) }
        catch { context.rollback(); throw error }
    }

    /// Eski tekil ödünçler UUID'den türetilen kimlikle bir kez taşınır; belirsiz kişiye kimlik atanmaz.
    @discardableResult
    static func migrateLegacyLoans(context: ModelContext, persist: Bool = true, bookIDs: Set<UUID>? = nil) throws -> Int {
        let books = try context.fetch(FetchDescriptor<CatalogBook>())
        let loans = try context.fetch(FetchDescriptor<ActiveLoan>())
        _ = try StudentStore.allVerified()
        let members = try MemberStore.allVerified()
        func legacyStudent(name: String, className: String) -> Student? {
            guard !members.contains(where: { CatalogMatcher.normalize($0.name) == CatalogMatcher.normalize(name) }) else { return nil }
            return try? resolvedStudent(name: name, className: className)
        }
        var converted = 0
        for book in books where !(book.loanedTo ?? "").isEmpty && (bookIDs == nil || bookIDs!.contains(book.id)) {
            let legacyID = Book.stableID(title: "legacy-loan", author: book.id.uuidString, isbn: "")
            if !loans.contains(where: { $0.id == legacyID }) {
                let loan = ActiveLoan(bookID: book.id, bookTitleSnapshot: book.title, studentName: book.loanedTo ?? "",
                                      studentClass: "", dueDate: book.loanDueDate ?? .now)
                loan.id = legacyID
                loan.identitySource = "legacy"
                if let student = legacyStudent(name: loan.studentName, className: "") { loan.studentID = student.id; loan.studentClass = student.className; loan.studentNumberSnapshot = student.number }
                else { loan.needsIdentityReview = true }
                context.insert(loan)
                converted += 1
            }
            book.loanedTo = nil
            book.loanDueDate = nil
        }
        for loan in loans where loan.studentID == nil && loan.memberID == nil && (loan.identitySource == nil || loan.identitySource == "legacy") && (bookIDs == nil || bookIDs!.contains(loan.bookID)) {
            if let student = legacyStudent(name: loan.studentName, className: loan.studentClass) { loan.studentID = student.id; loan.studentNumberSnapshot = student.number }
            else { loan.needsIdentityReview = true }
        }
        if persist { do { try context.save() } catch { context.rollback(); throw error } }
        return converted
    }
}
