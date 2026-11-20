import SwiftUI
import SwiftData

nonisolated struct AssistantTargetChoice: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var bookIDs: [UUID]
    var loan: LoanIntent? = nil
    var edit: BookEditIntent? = nil
    var person = ""
    var className = ""

    @MainActor static func candidates(_ title: String, in books: [CatalogBook]) -> [CatalogBook] {
        let normalized = CatalogMatcher.normalize(title)
        let exact = books.filter { CatalogMatcher.normalize($0.title) == normalized }
        return (exact.isEmpty ? books.filter { CatalogMatcher.isSimilarTitle($0.title, title) } : exact)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Tam/benzer başlık eşleşmesi yokken ikinci, gevşek arama: ses tanıma hatalı yazdığı adın
    /// anahtar sözcüklerinin yarısından fazlasını içeren başlıklar (en çok 6, en iyi eşleşen önce).
    @MainActor static func looseCandidates(_ title: String, in books: [CatalogBook], limit: Int = 6) -> [CatalogBook] {
        let terms = AssistantContext.keywords(in: title)
        guard !terms.isEmpty else { return [] }
        let needed = max(1, (terms.count + 1) / 2)
        let scored: [(CatalogBook, Int)] = books.compactMap { book in
            guard !book.isWithdrawn else { return nil }
            let haystack = CatalogMatcher.normalize(book.title)
            let hits = terms.filter { haystack.contains($0) }.count
            return hits >= needed ? (book, hits) : nil
        }
        return scored
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.title.localizedStandardCompare($1.0.title) == .orderedAscending }
            .prefix(limit)
            .map(\.0)
    }
}

/// Yazma yapılmaz; seçilen kimlik ve etki, ayrı son onay kartına taşınır.
struct AssistantTargetPicker: View {
    let choice: AssistantTargetChoice
    let onSelect: (UUID, String, String, UUID?, UUID?, UUID?, UUID?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query private var books: [CatalogBook]
    @Query private var loans: [ActiveLoan]
    @Query private var copies: [BookCopy]
    @Query private var reservations: [Reservation]
    @State private var selectedID: UUID?
    @State private var studentID: UUID?
    @State private var memberID: UUID?
    @State private var copyID: UUID?
    @State private var loanID: UUID?
    @State private var person = ""
    @State private var className = ""

    private var candidates: [CatalogBook] { books.filter { choice.bookIDs.contains($0.id) } }
    private var selected: CatalogBook? { candidates.first { $0.id == selectedID } }
    private var chosenLoan: ActiveLoan? { loans.first { $0.id == loanID && $0.bookID == selectedID } }
    private var chosenLoanMatches: Bool {
        guard let loan = chosenLoan, copyID == loan.copyID else { return false }
        if let studentID { return loan.studentID == studentID && loan.memberID == nil && memberID == nil }
        if let memberID { return loan.memberID == memberID && loan.studentID == nil }
        return loan.studentID == nil && loan.memberID == nil && CatalogMatcher.normalize(loan.studentName) == CatalogMatcher.normalize(person) && loan.studentClass == className
    }
    private func clearLoanSelection() { loanID = nil; copyID = nil; memberID = nil }
    private func clearInconsistentLoan() {
        if loanID != nil && !chosenLoanMatches { clearLoanSelection() }
    }
    private var students: [Student] {
        StudentStore.all().filter { student in
            choice.person.isEmpty || CatalogMatcher.normalize(student.name).contains(CatalogMatcher.normalize(choice.person))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var isReturn: Bool { choice.loan?.kind == "return" }
    private var state: LibraryStock? {
        selected.map { SchoolLibraryService.stock(for: $0, loans: loans, copies: copies, reservations: reservations) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Kitap ve baskı") {
                    Picker("Hedef kitap", selection: $selectedID) {
                        Text("Seçin").tag(Optional<UUID>.none)
                        ForEach(candidates) { book in
                            Text([book.title, book.publisher ?? "", book.isbn ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                .tag(Optional(book.id))
                        }
                    }
                    if let selected, let state {
                        Text("\(selected.author) · ISBN \(selected.isbn ?? "yok")")
                        Text("\(state.available) müsait / \(state.total) nüsha · \(selected.cabinet ?? "Dolap yok") / \(selected.shelf ?? "Raf yok")")
                            .font(.footnote)
                    }
                }
                if choice.loan != nil {
                    Section("Öğrenci / okur") {
                        if !students.isEmpty {
                            Picker("Kayıtlı öğrenci", selection: $studentID) {
                                Text("Seçin / elle girin").tag(Optional<UUID>.none)
                                ForEach(students) { student in
                                    Text("\(student.name) · \(student.className) · No \(student.number)").tag(Optional(student.id))
                                }
                            }
                            .disabled(loanID != nil)
                            .onChange(of: studentID) {
                                // Ödünç satırını seçmek, güncel sınıfın eski hareketin sınıfını ezmesine yol açamaz.
                                if loanID == nil, let student = students.first(where: { $0.id == studentID }) { person = student.name; className = student.className }
                                clearInconsistentLoan()
                            }
                        }
                        TextField("Okur adı", text: $person).disabled(studentID != nil || loanID != nil)
                        TextField("Sınıf", text: $className).disabled(studentID != nil || loanID != nil)
                        if isReturn, let selected {
                            ForEach(loans.filter { $0.bookID == selected.id }) { loan in
                                Button {
                                    person = loan.studentName; className = loan.studentClass; studentID = loan.studentID
                                    memberID = loan.memberID; copyID = loan.copyID; loanID = loan.id
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Label("\(loan.studentName) · \(loan.studentClass)", systemImage: loanID == loan.id ? "checkmark.circle.fill" : "circle")
                                        Text(copies.first { $0.id == loan.copyID }?.accessionCode ?? "Veriliş: \(loan.loanedAt.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(.secondary)
                                    }.fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
                                }
                            }
                        }
                        if let loan = chosenLoan {
                            LabeledContent("Seçilen ödünç", value: "\(loan.studentName) · \(loan.studentClass)")
                            Button("Ödünç seçimini değiştir", systemImage: "arrow.triangle.2.circlepath") { clearLoanSelection() }
                        } else if isReturn { Text("İade edilecek açık ödünç satırını seçin.").font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                Section("İşlem etkisi") {
                    if let edit = choice.edit { ForEach(edit.changeLines, id: \.self) { Text($0) } }
                    if choice.loan != nil { Text(isReturn ? "Seçilen okurun bir ödünç kaydı kapanır." : "Bir müsait nüsha seçilen okura ödünç verilir.") }
                    Button("Seçimi onay kartına taşı") {
                        if let selectedID, !isReturn || chosenLoanMatches { onSelect(selectedID, person, className, studentID, memberID, copyID, loanID); dismiss() }
                    }
                    .disabled(selectedID == nil || (choice.loan != nil && person.trimmingCharacters(in: .whitespaces).isEmpty)
                              || (choice.loan != nil && !isReturn && state?.available == 0) || (isReturn && !chosenLoanMatches))
                }
            }
            .navigationTitle("Hedefleri Seç")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } } }
            .onChange(of: selectedID) { clearLoanSelection() }
            .onChange(of: memberID) { clearInconsistentLoan() }
            .onChange(of: person) { clearInconsistentLoan() }
            .onChange(of: className) { clearInconsistentLoan() }
            .onAppear {
                selectedID = candidates.count == 1 ? candidates.first?.id : nil
                person = choice.person; className = choice.className
                if students.count == 1, let student = students.first {
                    studentID = student.id; person = student.name; className = student.className
                }
            }
        }
    }
}
