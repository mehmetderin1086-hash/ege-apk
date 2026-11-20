import Foundation
import SwiftData

nonisolated struct StudentImportMapping: Codable, Equatable {
    var nameColumn: Int
    var numberColumn: Int?
    var classColumn: Int?
    var hasHeader = true
}

nonisolated struct StudentImportRow: Identifiable {
    var id: Int { line }
    var line: Int
    var student: Student?
    var candidates: [Student] = []
    var issue: String?
    var unchanged = false
    var requiresDecision = false
    /// Tek aday + okul numarası eşleşmesinde karar beklemeden uygulanan çözüm (kimliği koru, ad/sınıfı güncelle).
    var defaultResolution: StudentImportResolution?
}

nonisolated struct StudentImportPreview {
    var before: [Student]
    var rows: [StudentImportRow]
    /// Dosyada sınıf/numara sütunu yoksa kimlik güncellemesi mevcut değeri silmez.
    var classProvided = true
    var numberProvided = true
    var errors: [StudentImportRow] { rows.filter { $0.student == nil } }
    var conflicts: [StudentImportRow] { rows.filter { $0.requiresDecision && !$0.unchanged } }
    /// Varsayılan çözümle (kimlik güncelleme) uygulanacak satırlar.
    var autoUpdates: [StudentImportRow] { rows.filter { $0.defaultResolution != nil && !$0.unchanged } }
}

nonisolated enum StudentImportResolution: Equatable {
    case skip, newStudent, update(UUID)
}

nonisolated struct StudentImportReceipt: Codable, Identifiable, Equatable {
    var id = UUID()
    var createdAt = Date.now
    var before: [Student]
    var after: [Student]
    var affectedIDs: [UUID]
    var state = "prepared"
    var undoneAt: Date?
}

@MainActor
enum StudentImportStore {
    static let fileName = "OgrenciAktarimGunlugu.json"
    static var storageURL: URL? { StudentStore.storageURL?.deletingLastPathComponent().appendingPathComponent(fileName) }

    nonisolated static func validate(_ data: Data) throws -> [StudentImportReceipt] {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([StudentImportReceipt].self, from: data)
        guard Set(entries.map(\.id)).count == entries.count,
              entries.allSatisfy({ Set($0.before.map(\.id)).count == $0.before.count && Set($0.after.map(\.id)).count == $0.after.count && Set($0.affectedIDs).count == $0.affectedIDs.count && Set($0.affectedIDs).isSubset(of: Set($0.after.map(\.id))) && ["prepared", "committed", "undone"].contains($0.state) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return entries
    }
    /// Günlükte geri alınabilir en fazla bu kadar son makbuz tutulur.
    nonisolated static let enFazlaMakbuz = 10
    nonisolated static func sonMakbuzlar(_ entries: [StudentImportReceipt]) -> [StudentImportReceipt] {
        Array(entries.suffix(enFazlaMakbuz))
    }
    static func allVerified() throws -> [StudentImportReceipt] {
        guard let url = storageURL else { throw CocoaError(.fileNoSuchFile) }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try validate(Data(contentsOf: url))
    }
    static func replaceAllVerified(_ entries: [StudentImportReceipt]) throws {
        guard let url = storageURL else { throw CocoaError(.fileNoSuchFile) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entries); _ = try validate(data)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

@MainActor
enum StudentImportService {
    struct Result { var added: Int; var updated: Int; var skipped: Int; var receiptID: UUID? }

    static func preview(rows: [[String]], mapping: StudentImportMapping) throws -> StudentImportPreview {
        let before = try StudentStore.allVerified()
        let columns = [mapping.nameColumn, mapping.numberColumn, mapping.classColumn].compactMap { $0 }
        guard columns.allSatisfy({ $0 >= 0 }), Set(columns).count == columns.count else {
            throw SchoolLibraryService.OperationError(message: "Ad, numara ve sınıf için farklı sütunlar seçin.")
        }
        var seen = Set<String>()
        let numberCounts = Dictionary(rows.dropFirst(mapping.hasHeader ? 1 : 0).compactMap { values -> (String, Int)? in
            guard let column = mapping.numberColumn, values.indices.contains(column) else { return nil }
            let number = values[column].trimmingCharacters(in: .whitespacesAndNewlines)
            return number.isEmpty ? nil : (number, 1)
        }, uniquingKeysWith: +)
        let preview = rows.enumerated().dropFirst(mapping.hasHeader ? 1 : 0).map { offset, values -> StudentImportRow in
            let line = offset + 1
            func value(_ column: Int?) -> String { guard let column, values.indices.contains(column) else { return "" }; return values[column].trimmingCharacters(in: .whitespacesAndNewlines) }
            let name = value(mapping.nameColumn), number = value(mapping.numberColumn), className = value(mapping.classColumn)
            guard !name.isEmpty else { return StudentImportRow(line: line, issue: "Ad boş; satır aktarılmayacak.") }
            guard mapping.classColumn == nil || (!className.isEmpty && className.contains(where: { $0.isLetter || $0.isNumber }) && className.count <= 40) else {
                return StudentImportRow(line: line, issue: "Sınıf boş veya geçersiz; sütun eşlemesini kontrol edin.")
            }
            let key = CatalogMatcher.normalize(name) + "|" + number + "|" + className
            guard seen.insert(key).inserted else { return StudentImportRow(line: line, issue: "Dosyada aynı öğrenci satırı tekrar ediyor; aktarılmayacak.") }
            let student = Student(name: name, number: number, className: className)
            let exact = before.filter { CatalogMatcher.normalize($0.name) == CatalogMatcher.normalize(name) && $0.number == number && $0.className == className }
            if exact.count == 1 { return StudentImportRow(line: line, student: student, candidates: exact, issue: "Aynı kayıt zaten var; değişiklik yok.", unchanged: true) }
            let candidates = before.filter { (!number.isEmpty && $0.number == number) || (CatalogMatcher.normalize($0.name) == CatalogMatcher.normalize(name) && $0.className == className) }
            let duplicateNumber = !number.isEmpty && numberCounts[number, default: 0] > 1
            // Yıllık liste: aynı numara tek bir mevcut öğrenciye uyuyorsa kimlik korunur, karar sorulmaz.
            if !duplicateNumber, !number.isEmpty, candidates.count == 1, let eski = candidates.first, eski.number == number {
                var farklar: [String] = []
                if mapping.classColumn != nil, eski.className != className {
                    farklar.append("Sınıf \(eski.className.isEmpty ? "—" : eski.className) → \(className)")
                }
                if CatalogMatcher.normalize(eski.name) != CatalogMatcher.normalize(name) { farklar.append("Ad: \(eski.name) → \(name)") }
                let ozet = farklar.isEmpty ? "Bilgiler güncellenecek." : farklar.joined(separator: " · ")
                return StudentImportRow(line: line, student: student, candidates: candidates,
                                        issue: "Aynı numara, kimlik korunur: " + ozet,
                                        defaultResolution: .update(eski.id))
            }
            return StudentImportRow(line: line, student: student, candidates: candidates,
                                    issue: duplicateNumber ? "Dosyada okul numarası birden çok kişide var. Ayrı kimlik ekleme veya atlama kararı verin." : candidates.isEmpty ? nil : "Kimlik eşleşmesi belirsiz. Mevcut kimliği seçin, ayrı öğrenci ekleyin veya atlayın.",
                                    requiresDecision: !candidates.isEmpty || duplicateNumber)
        }
        return StudentImportPreview(before: before, rows: preview, classProvided: mapping.classColumn != nil, numberProvided: mapping.numberColumn != nil)
    }

    static func apply(_ preview: StudentImportPreview, resolutions: [Int: StudentImportResolution] = [:], context: ModelContext) throws -> Result {
        try SchoolLibraryService.requireAdmin()
        let current = try StudentStore.allVerified()
        guard current == preview.before else { throw SchoolLibraryService.OperationError(message: "Öğrenci defteri önizlemeden sonra değişti. Dosyayı yeniden önizleyin.") }
        var after = current, added = 0, updated = 0, skipped = 0, affected = Set<UUID>()
        for row in preview.rows {
            guard var student = row.student, !row.unchanged else { skipped += 1; continue }
            let resolution: StudentImportResolution? = resolutions[row.line] ?? row.defaultResolution ?? (row.requiresDecision ? nil : .newStudent)
            guard let resolution else { throw SchoolLibraryService.OperationError(message: "Satır \(row.line): belirsiz öğrenci kimliği için seçim yapın.") }
            switch resolution {
            case .skip: skipped += 1
            case .newStudent:
                guard !after.contains(where: { $0.id == student.id }) else { throw SchoolLibraryService.OperationError(message: "Aktarım kimliği tekrar ediyor.") }
                after.append(student); affected.insert(student.id); added += 1
            case .update(let id):
                guard row.candidates.contains(where: { $0.id == id }), let index = after.firstIndex(where: { $0.id == id }), !affected.contains(id) else {
                    throw SchoolLibraryService.OperationError(message: "Satır \(row.line): aynı kimliği birden çok kez değiştirmeyin.")
                }
                student.id = id
                if !preview.classProvided { student.className = after[index].className }
                if !preview.numberProvided { student.number = after[index].number }
                after[index] = student; affected.insert(id); updated += 1
            }
        }
        guard !affected.isEmpty else { return Result(added: 0, updated: 0, skipped: skipped, receiptID: nil) }
        let oldJournal = try StudentImportStore.allVerified()
        var receipt = StudentImportReceipt(before: current, after: after, affectedIDs: affected.sorted { $0.uuidString < $1.uuidString })
        // Önce kalıcı öncesi/sonrası kayıt: iki dosya arasındaki kesinti de geri alınabilir.
        try StudentImportStore.replaceAllVerified(StudentImportStore.sonMakbuzlar(oldJournal + [receipt]))
        // Hata dalında geri yüklenecek bağlantı değerleri (kaydedilmiş olsa bile)
        var loanBackups: [(loan: ActiveLoan, name: String, className: String)] = []
        var reservationBackups: [(reservation: Reservation, name: String, className: String)] = []
        var linksSaved = false
        do {
            try StudentStore.replaceAllVerified(after)
            // Kimliği güncellenen öğrencinin açık ödünç/sıra kayıtları yeni ad ve sınıfı taşır;
            // yoksa sınıf filtreleri ve ders kitabı teslim listesi öğrenciyi eski sınıfta arar.
            let refreshed = Dictionary(after.filter { affected.contains($0.id) }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let loans = try context.fetch(FetchDescriptor<ActiveLoan>())
            let reservations = try context.fetch(FetchDescriptor<Reservation>())
            for loan in loans where loan.memberID == nil {
                guard let id = loan.studentID, let student = refreshed[id],
                      loan.studentName != student.name || loan.studentClass != student.className else { continue }
                loanBackups.append((loan, loan.studentName, loan.studentClass))
                loan.studentName = student.name; loan.studentClass = student.className
            }
            for reservation in reservations where !reservation.isClosed && reservation.memberID == nil {
                guard let id = reservation.studentID, let student = refreshed[id],
                      reservation.studentName != student.name || reservation.studentClass != student.className else { continue }
                reservationBackups.append((reservation, reservation.studentName, reservation.studentClass))
                reservation.studentName = student.name; reservation.studentClass = student.className
            }
            if !loanBackups.isEmpty || !reservationBackups.isEmpty { try context.save(); linksSaved = true }
            receipt.state = "committed"
            try StudentImportStore.replaceAllVerified(StudentImportStore.sonMakbuzlar(oldJournal + [receipt]))
        } catch {
            // Öğrenci defteri geri alınırken bağlantılar yeni ad/sınıfta kalmasın. Bağlantılar
            // diske yazılmadıysa bellekteki değişikliği atmak yeter; yazıldıysa eski değerler geri kaydedilir.
            var linksRestored = true
            if !linksSaved { context.rollback() }
            else {
                for backup in loanBackups { backup.loan.studentName = backup.name; backup.loan.studentClass = backup.className }
                for backup in reservationBackups { backup.reservation.studentName = backup.name; backup.reservation.studentClass = backup.className }
                do { try context.save() } catch { context.rollback(); linksRestored = false }
            }
            guard linksRestored else {
                throw SchoolLibraryService.OperationError(message: "Aktarım tamamlanamadı ve ödünç bağlantıları geri alınamadı. Kalıcı işlem günlüğü ile öncesi/sonrası korunuyor; tam arşivden kurtarın.")
            }
            do { try StudentStore.replaceAllVerified(current); try StudentImportStore.replaceAllVerified(oldJournal) }
            catch { throw SchoolLibraryService.OperationError(message: "Aktarım ve geri alma yazımı tamamlanamadı. Kalıcı işlem günlüğü ile öncesi/sonrası korunuyor; tam arşivden kurtarın.") }
            throw error
        }
        return Result(added: added, updated: updated, skipped: skipped, receiptID: receipt.id)
    }

    /// Henüz geri alınmamış makbuzlar, en yenisi başta (en fazla 10).
    static func geriAlinabilirMakbuzlar() -> [StudentImportReceipt] {
        ((try? StudentImportStore.allVerified()) ?? []).filter { $0.undoneAt == nil }.reversed()
    }

    static func undoLast(context: ModelContext) throws -> Int {
        try undo(receiptID: nil, context: context)
    }

    /// Makbuzdaki aktarımı geri alır. Kimliği güncellenen öğrencilerin ad/sınıfı eski haline döner (açık
    /// ödünç engel olmaz, ödünç ve sıra kayıtları da eski ad/sınıfa döner); engel yalnız bu aktarımla
    /// YENİ eklenen kimliklerin açık ödünç/sırası ya da mezun kaydı varsa konur.
    static func undo(receiptID: UUID?, context: ModelContext) throws -> Int {
        try SchoolLibraryService.requireAdmin()
        var journal = try StudentImportStore.allVerified()
        guard let index = receiptID.map({ id in journal.firstIndex(where: { $0.id == id && $0.undoneAt == nil }) }) ?? journal.lastIndex(where: { $0.undoneAt == nil }) else {
            throw SchoolLibraryService.OperationError(message: "Geri alınacak öğrenci aktarımı yok.")
        }
        let receipt = journal[index], affected = Set(receipt.affectedIDs)
        let current = try StudentStore.allVerified()
        // Günlük yazıldıktan sonra, öğrenci dosyasından önce kesilen işlem henüz uygulanmamıştır.
        if receipt.state == "prepared", affected.allSatisfy({ id in current.first(where: { $0.id == id }) == receipt.before.first(where: { $0.id == id }) }) {
            journal[index].undoneAt = .now; journal[index].state = "undone"
            try StudentImportStore.replaceAllVerified(journal)
            return 0
        }
        for id in affected {
            guard current.first(where: { $0.id == id }) == receipt.after.first(where: { $0.id == id }) else {
                throw SchoolLibraryService.OperationError(message: "Aktarılan öğrenci daha sonra değişti; geri alma uygulanmadı.")
            }
        }
        let beforeByID = Dictionary(receipt.before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let updatedIDs = affected.filter { beforeByID[$0] != nil }
        let addedIDs = affected.subtracting(updatedIDs)
        let active = try context.fetch(FetchDescriptor<ActiveLoan>())
        let reservations = try context.fetch(FetchDescriptor<Reservation>())
        let addedSnapshots = receipt.after.filter { addedIDs.contains($0.id) }
        guard !active.contains(where: { loan in
            if let id = loan.studentID { return addedIDs.contains(id) }
            return loan.memberID == nil && addedSnapshots.contains { $0.name == loan.studentName && $0.className == loan.studentClass }
        }), !reservations.contains(where: { reservation in
            guard !reservation.isClosed else { return false }
            if let id = reservation.studentID { return addedIDs.contains(id) }
            return addedSnapshots.contains { $0.name == reservation.studentName && $0.className == reservation.studentClass }
        }),
        !(try GraduatedStudentStore.allVerified()).contains(where: { affected.contains($0.id) }) else {
            throw SchoolLibraryService.OperationError(message: "Yeni eklenen öğrencinin açık ödüncü, sırası veya mezun kaydı var. Önce bu bağlantıları çözün; kimlik silinmedi.")
        }
        // Kimliği güncellenenlerin bağlantıları eski ad/sınıfa döner.
        for loan in active where loan.memberID == nil {
            guard let id = loan.studentID, updatedIDs.contains(id), let eski = beforeByID[id],
                  loan.studentName != eski.name || loan.studentClass != eski.className else { continue }
            loan.studentName = eski.name; loan.studentClass = eski.className
        }
        for reservation in reservations where !reservation.isClosed && reservation.memberID == nil {
            guard let id = reservation.studentID, updatedIDs.contains(id), let eski = beforeByID[id],
                  reservation.studentName != eski.name || reservation.studentClass != eski.className else { continue }
            reservation.studentName = eski.name; reservation.studentClass = eski.className
        }
        let restored = current.filter { !affected.contains($0.id) } + receipt.before.filter { affected.contains($0.id) }
        let originalJournal = journal
        do {
            try StudentStore.replaceAllVerified(restored)
            journal[index].undoneAt = .now; journal[index].state = "undone"
            try StudentImportStore.replaceAllVerified(journal)
            if context.hasChanges { try context.save() }
        } catch {
            context.rollback()
            do { try StudentStore.replaceAllVerified(current); try StudentImportStore.replaceAllVerified(originalJournal) }
            catch { throw SchoolLibraryService.OperationError(message: "Geri alma yazımı tamamlanmadı; işlem günlüğü korunuyor, arşivden kurtarın.") }
            throw error
        }
        return affected.count
    }
}
