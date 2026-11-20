import SwiftUI
import SwiftData

/// İsim önerisinden bağımsız, UUID taşıyan açık öğrenci/üye seçimi.
struct LibraryRecipientPicker: View {
    @Binding var selection: LoanIdentitySelection?
    @State private var memberMode = false
    @State private var studentPicker = false
    @State private var memberPicker = false
    @State private var selectedDescription = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Okur türü", selection: $memberMode) {
                Text("Öğrenci").tag(false)
                Text("Üye").tag(true)
            }.pickerStyle(.segmented)
                .onChange(of: memberMode) { _, _ in selection = nil; selectedDescription = "" }
            Button {
                if memberMode { memberPicker = true } else { studentPicker = true }
            } label: {
                Label(selectedDescription.isEmpty ? (memberMode ? "Üye seç" : "Öğrenci seç") : selectedDescription,
                      systemImage: memberMode ? "person.crop.rectangle" : "person.crop.circle")
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(minHeight: 44).accessibilityIdentifier("identity.selectRecipient")
        }
        .onChange(of: selection) { _, value in if value == nil { selectedDescription = "" } }
        .sheet(isPresented: $studentPicker) {
            OgrenciSecimSayfasi { student in
                selection = .student(student.id)
                selectedDescription = [student.name, student.className, student.number.isEmpty ? "" : "No: " + student.number]
                    .filter { !$0.isEmpty }.joined(separator: " · ")
            }
        }
        .sheet(isPresented: $memberPicker) {
            UyeSecimSayfasi { member in
                selection = .member(member.id)
                selectedDescription = [member.name, member.kindTitle, member.memberNumber]
                    .filter { !$0.isEmpty }.joined(separator: " · ")
            }
        }
    }
}

struct LoanIdentityReviewSheet: View {
    let loan: ActiveLoan
    let onSaved: () -> Void
    private let expected: ArchivedLoan
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var copies: [BookCopy]
    @Query private var loans: [ActiveLoan]
    @State private var recipient: LoanIdentitySelection?
    @State private var copyID: UUID?
    @State private var operationID = UUID()
    @State private var error: String?
    @State private var confirmation = false

    init(loan: ActiveLoan, onSaved: @escaping () -> Void = {}) {
        self.loan = loan; self.onSaved = onSaved; expected = ArchivedLoan(loan)
        _copyID = State(initialValue: loan.copyID)
    }

    private var candidates: [BookCopy] {
        copies.filter { copy in copy.bookID == loan.bookID && copy.isCirculating
            && !loans.contains { other in other.id != loan.id && other.copyID == copy.id } }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mevcut kayıt") {
                    Text(expected.bookTitleSnapshot).font(.headline)
                    LabeledContent("Ad", value: expected.studentName)
                    LabeledContent("Sınıf", value: expected.studentClass)
                    if let number = expected.studentNumberSnapshot, !number.isEmpty { LabeledContent("Ödünçteki numara", value: number) }
                    Text("Kitap adedi ve ödünç tarihi korunur. Doğru okuru ve fiziksel nüshayı seçin.")
                        .font(.footnote).fixedSize(horizontal: false, vertical: true)
                }
                Section("Doğru okur") { LibraryRecipientPicker(selection: $recipient) }
                Section("Fiziksel nüsha") {
                    Picker("Nüsha", selection: $copyID) {
                        Text("Demirbaşsız fiziksel adet").tag(Optional<UUID>.none)
                        ForEach(candidates) { copy in
                            Text(copy.accessionCode.isEmpty ? "Nüsha " + String(copy.id.uuidString.prefix(8)) : copy.accessionCode)
                                .tag(Optional(copy.id))
                        }
                    }.accessibilityIdentifier("identity.selectCopy")
                    Text("Başka kişide, onarımda veya kayıp nüsha seçilemez. Ayrılmış nüsha kayıtta yeniden doğrulanır.")
                        .font(.footnote).fixedSize(horizontal: false, vertical: true)
                }
                if let error { Section { Label(error, systemImage: "exclamationmark.triangle").fixedSize(horizontal: false, vertical: true) } }
            }
            .navigationTitle("Ödünç kimliğini düzelt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("İncele ve kaydet") { confirmation = true }.disabled(recipient == nil)
                        .accessibilityIdentifier("identity.save")
                }
            }
            .confirmationDialog("Seçilen okur ve nüsha bu eski ödünce bağlansın mı? Eski kayıt tarihçede korunur.", isPresented: $confirmation, titleVisibility: .visible) {
                Button("Kimliği düzelt") { save() }
                Button("Vazgeç", role: .cancel) { }
            }
        }
    }

    private func save() {
        guard let recipient else { return }
        do {
            try SchoolLibraryService.correctLoanIdentity(loan, recipient: recipient, copyID: copyID,
                expected: expected, operationID: operationID, context: context)
            onSaved(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
