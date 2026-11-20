import SwiftUI
import SwiftData

/// Ders Kitabı Dağıtımı: "Ders Kitabı" olarak işaretlenmiş kitapların sınıf bazında
/// dağıtımını ve dönem sonu teslim alımını takip eder. Aynı `ActiveLoan` mekanizmasını
/// kullanır (iade tarihi öğretim yılı sonuna ayarlanır, gecikme hatırlatması kurulmaz).
struct TextbookDistributionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CatalogBook.title) private var allBooks: [CatalogBook]
    @Query private var activeLoans: [ActiveLoan]

    @State private var selectedClass = ""
    @State private var selectedBook: CatalogBook?
    @State private var resultMessage: String?
    @AppStorage("textbookDueDateTimestamp") private var dueTimestamp = 0.0
    @AppStorage("textbookPeriod") private var period = ""
    @State private var selectedReturns = Set<UUID>()
    @State private var returnConditions: [UUID: String] = [:]
    @State private var confirmReturn = false
    @State private var confirmAllGood = false

    private var textbooks: [CatalogBook] { allBooks.filter { $0.isTextbook } }
    private var classNames: [String] { StudentStore.classNames() }
    private var studentsInClass: [Student] {
        selectedClass.isEmpty ? [] : StudentStore.students(in: selectedClass)
    }

    /// Seçili ders kitabı için sınıftaki öğrencilerden kimde olduğu, kimde olmadığı.
    private func distributionStatus(for book: CatalogBook) -> (has: [Student], missing: [Student]) {
        let relevant = activeLoans.filter { $0.bookID == book.id && $0.kind == "textbook" && $0.memberID == nil && $0.identitySource != "manual" }
        func hasLoan(_ student: Student) -> Bool { relevant.contains { $0.studentID == student.id || ($0.studentID == nil && $0.studentName == student.name && $0.studentClass == student.className) } }
        let has = studentsInClass.filter(hasLoan)
        let missing = studentsInClass.filter { !hasLoan($0) }
        return (has, missing)
    }

    private func returnableLoans(_ book: CatalogBook) -> [ActiveLoan] {
        activeLoans.filter { $0.bookID == book.id && $0.kind == "textbook" && $0.studentClass == selectedClass }
            .sorted { $0.studentName.localizedStandardCompare($1.studentName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                if textbooks.isEmpty {
                    Section {
                        Text("Henüz \"Ders Kitabı\" olarak işaretlenmiş kayıt yok. Kitabı düzenleyip Basım Bilgileri bölümünden işaretleyin.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Sınıf ve Ders Kitabı") {
                    Picker("Sınıf", selection: $selectedClass) {
                        Text("Seçin").tag("")
                        ForEach(classNames, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Ders Kitabı", selection: $selectedBook) {
                        Text("Seçin").tag(CatalogBook?.none)
                        ForEach(textbooks) { book in
                            Text(book.title).tag(Optional(book))
                        }
                    }
                }

                Section {
                    TextField("Dönem (boşsa \(TextbookOperations.currentPeriod()))", text: $period)
                    DatePicker("Teslim tarihi", selection: Binding(get: { effectiveDueDate }, set: { dueTimestamp = $0.timeIntervalSince1970 }), displayedComponents: .date)
                } header: {
                    Text("Öğretim yılı")
                } footer: {
                    if TextbookOperations.isPastPeriod(period) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Kayıtlı dönem (\(period)) geçmiş bir öğretim yılına ait; yeni dağıtımlar bu dönemle kaydedilir.")
                            Button("\(TextbookOperations.currentPeriod()) dönemine geç") { period = TextbookOperations.currentPeriod() }
                        }
                    }
                }

                if let book = selectedBook, !selectedClass.isEmpty {
                    let status = distributionStatus(for: book)

                    let assigned = returnableLoans(book)
                    Section("Dağıtılmış / teslim alınacak (\(assigned.count))") {
                        ForEach(assigned) { loan in
                            VStack(alignment: .leading, spacing: 6) {
                                Toggle(isOn: Binding(get: { selectedReturns.contains(loan.id) }, set: { if $0 { selectedReturns.insert(loan.id) } else { selectedReturns.remove(loan.id) } })) {
                                    Text(loan.studentName).font(.headline)
                                }
                                Text("\(loan.periodSnapshot ?? "Eski kayıtta dönem yok") · \(loan.studentClass) · \(loan.dueDate.formatted(date: .abbreviated, time: .omitted))").font(.footnote).foregroundStyle(.secondary)
                                Picker("Teslimde fiziksel durum", selection: Binding<String?>(get: { returnConditions[loan.id] }, set: { returnConditions[loan.id] = $0 })) {
                                    Text("Belirtilmedi").tag(String?.none)
                                    ForEach(BookCopy.conditions, id: \.self) { Text($0).tag(Optional($0)) }
                                }
                                Button("Bu nüshayı teslim al") { selectedReturns = [loan.id]; confirmReturn = true }.frame(minHeight: 44)
                            }
                        }
                        if !assigned.isEmpty {
                            Button("Tüm teslimleri seç") { selectedReturns = Set(assigned.map(\.id)) }.frame(minHeight: 44)
                            Button("Tümünü İyi işaretle") { confirmAllGood = true }.frame(minHeight: 44)
                            Button("Seçili \(selectedReturns.intersection(assigned.map(\.id)).count) nüshayı teslim al") { confirmReturn = true }
                                .disabled(selectedReturns.intersection(assigned.map(\.id)).isEmpty).frame(minHeight: 44)
                            Text("Durum “Belirtilmedi” kalırsa nüshanın kayıtlı durumu değişmez. Onarım gerekli seçilen nüsha raftaki müsaitliğe dönmez. Teslim alınmayan/eksik kitaplar açık ödünç olarak korunur.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    Section("Dağıtılmamış (\(status.missing.count))") {
                        ForEach(status.missing) { student in
                            HStack {
                                Text(student.name)
                                Spacer()
                                Button("Ver") {
                                    do { try distribute(book: book, student: student); resultMessage = "Dağıtım kaydedildi." }
                                    catch { resultMessage = error.localizedDescription }
                                }
                                .buttonStyle(.kitapTonlu())
                                .frame(minHeight: 44)
                            }
                        }
                        if !status.missing.isEmpty {
                            Button {
                                distributeAll(book: book, students: status.missing)
                            } label: {
                                Label("Tümüne Dağıt", systemImage: "person.3.fill")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Ders Kitabı Dağıtımı")
            .safeAreaInset(edge: .bottom) {
                let acik = activeLoans.filter { $0.kind == "textbook" }
                if !acik.isEmpty {
                    NavigationLink {
                        AcikDersKitaplariSayfasi()
                    } label: {
                        Label("Teslim alınmamış tüm ders kitapları (\(acik.count), Mezun dâhil)", systemImage: "list.bullet.rectangle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.kitapTonlu())
                    .padding(.horizontal).padding(.vertical, 8)
                    .background(.bar)
                    .accessibilityIdentifier("textbook.openAll")
                }
            }
            .onChange(of: selectedClass) { _, _ in selectedReturns = [] }
            .onChange(of: selectedBook?.id) { _, _ in selectedReturns = [] }
            .confirmationDialog("Seçili ders kitapları belirtilen fiziksel durumlarla teslim alınsın mı?", isPresented: $confirmReturn, titleVisibility: .visible) {
                Button("Teslimleri kaydet") { collectSelected() }
                Button("Vazgeç", role: .cancel) { }
            }
            .confirmationDialog("Listedeki tüm nüshalar “İyi” durumuna işaretlensin mi? Kayıtlı durumlar (ör. Yıpranmış) teslimde “İyi” ile değişir.", isPresented: $confirmAllGood, titleVisibility: .visible) {
                Button("Tümünü İyi işaretle") {
                    if let book = selectedBook { for loan in returnableLoans(book) { returnConditions[loan.id] = "İyi" } }
                }
                Button("Vazgeç", role: .cancel) { }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .alert("Ders Kitabı Dağıtımı", isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            )) {
                Button("Tamam", role: .cancel) { }
            } message: {
                Text(resultMessage ?? "")
            }
        }
    }

    /// Geçen yıldan kalan (bugünden eski) teslim tarihi yeni dağıtımı anında "gecikmiş"
    /// yapmasın diye yok sayılır; öğretim yılı sonu tahmini kullanılır.
    private var effectiveDueDate: Date {
        let stored = Date(timeIntervalSince1970: dueTimestamp)
        return dueTimestamp > 0 && stored >= Calendar.current.startOfDay(for: .now) ? stored : endOfSchoolYear()
    }

    private func endOfSchoolYear() -> Date {
        var components = Calendar.current.dateComponents([.year, .month], from: .now)
        // Haziran sonu tahmini öğretim yılı sonu
        if let month = components.month, month >= 8 {
            components.year = (components.year ?? 0) + 1
        }
        components.month = 6
        components.day = 20
        return Calendar.current.date(from: components) ?? .now
    }

    private func distribute(book: CatalogBook, student: Student) throws {
        try SchoolLibraryService.lend(book: book, person: student.name, className: selectedClass, context: modelContext,
                                      studentID: student.id, kind: "textbook", dueDate: effectiveDueDate,
                                      periodSnapshot: period.isEmpty ? TextbookOperations.currentPeriod() : period)
    }

    /// Toplu dağıtım görevlide de Face ID ister; kayıtlar tek save ile yazılır.
    private func distributeAll(book: CatalogBook, students: [Student]) {
        Task {
            do {
                let sonuc = try await YetkiKapisi.yoneticiyleCalistir(neden: "Toplu ders kitabı dağıtımı için kimliğinizi doğrulayın") {
                    try SchoolLibraryService.batchLend(book: book, students: students, className: selectedClass, kind: "textbook",
                                                       dueDate: effectiveDueDate, periodSnapshot: period.isEmpty ? TextbookOperations.currentPeriod() : period,
                                                       context: modelContext)
                }
                resultMessage = "\(sonuc.loans.count) öğrenciye \(book.title) dağıtıldı." + (sonuc.failures.isEmpty ? "" : "\n" + sonuc.failures.joined(separator: "\n"))
            } catch { resultMessage = error.localizedDescription }
        }
    }

    private func collectSelected() {
        do {
            guard let book = selectedBook else { return }
            let targetIDs = selectedReturns.intersection(returnableLoans(book).map(\.id))
            let result = try TextbookOperations.collect(loanIDs: targetIDs, conditions: returnConditions, context: modelContext)
            selectedReturns.subtract(result.collectedIDs)
            result.collectedIDs.forEach { returnConditions.removeValue(forKey: $0) }
            resultMessage = "\(result.collectedIDs.count) nüsha teslim alındı." + (result.failures.isEmpty ? "" : "\n" + result.failures.values.sorted().joined(separator: "\n"))
        } catch { resultMessage = error.localizedDescription }
    }
}

enum TextbookOperations {
    struct CollectionResult {
        var collectedIDs = Set<UUID>()
        var failures: [UUID: String] = [:]
    }
    static func currentPeriod(now: Date = .now) -> String {
        let year = Calendar.current.component(.year, from: now)
        let start = Calendar.current.component(.month, from: now) >= 8 ? year : year - 1
        return "\(start)–\(start + 1)"
    }
    /// "2025–2026" biçimindeki dönem, içinde bulunulan öğretim yılından eski mi?
    /// Serbest metin dönemler ("1. Dönem" gibi) eski sayılmaz.
    static func isPastPeriod(_ period: String, now: Date = .now) -> Bool {
        let years = period.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard years.count == 2, years[1] == years[0] + 1,
              let currentStart = Int(currentPeriod(now: now).prefix(4)) else { return false }
        return years[0] < currentStart
    }
    /// Seçili teslimleri tek save ile alır. Durum verilmeyen (nil) satırda nüshanın kayıtlı durumu değişmez.
    static func collect(loanIDs: Set<UUID>, conditions: [UUID: String], context: ModelContext) throws -> CollectionResult {
        let loans = try context.fetch(FetchDescriptor<ActiveLoan>())
        var result = CollectionResult()
        var targets: [ActiveLoan] = []
        for id in loanIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let loan = loans.first(where: { $0.id == id && $0.kind == "textbook" }) else {
                result.failures[id] = "Teslim kaydı bulunamadı; başka ödünç kapatılmadı."; continue
            }
            targets.append(loan)
        }
        let batch = try SchoolLibraryService.batchReturn(targets, conditions: conditions, context: context)
        result.collectedIDs = batch.returned
        result.failures.merge(batch.failures) { first, _ in first }
        return result
    }
}

/// Dönem sonu: sınıfı ne olursa olsun (Mezun dâhil) teslim alınmamış tüm ders kitapları.
struct AcikDersKitaplariSayfasi: View {
    @Query(sort: \ActiveLoan.dueDate) private var loans: [ActiveLoan]
    @AppStorage("schoolName") private var schoolName = ""

    private var acik: [ActiveLoan] { loans.filter { $0.kind == "textbook" } }
    private var siniflar: [(sinif: String, loans: [ActiveLoan])] {
        Dictionary(grouping: acik) { $0.studentClass.isEmpty ? "Sınıfsız" : $0.studentClass }
            .map { ($0.key, $0.value.sorted { $0.studentName.localizedStandardCompare($1.studentName) == .orderedAscending }) }
            .sorted { $0.sinif.localizedStandardCompare($1.sinif) == .orderedAscending }
    }

    var body: some View {
        List {
            if acik.isEmpty { ContentUnavailableView("Teslim bekleyen ders kitabı yok", systemImage: "checkmark.circle") }
            ForEach(siniflar, id: \.sinif) { grup in
                Section {
                    ForEach(grup.loans) { loan in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loan.studentName).font(.headline)
                            Text("\(loan.bookTitleSnapshot) · \(loan.periodSnapshot ?? "Dönem yok") · son gün \(loan.dueDate.formatted(OduncMerkezi.tarihBicimi))")
                                .font(.footnote).foregroundStyle(KitapTema.ikincilMetin)
                        }
                        .frame(minHeight: 44, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    HStack {
                        Text("\(grup.sinif) (\(grup.loans.count))")
                        Spacer()
                        ShareLink(item: OduncMerkezi.sinifVeliMesajlari(grup.loans, okul: schoolName)) {
                            Label("Veli mesajları", systemImage: "square.and.arrow.up")
                        }.font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Teslim bekleyen kitaplar")
    }
}
