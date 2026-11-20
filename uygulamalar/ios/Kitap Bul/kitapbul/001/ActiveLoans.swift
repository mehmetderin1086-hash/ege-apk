import Foundation
import SwiftUI
import SwiftData

/// Bir kitabın TEK nüshasının ödünç kaydı. `CatalogBook.loanedTo` tekil alanının
/// aksine, aynı kitabın BİRDEN ÇOK nüshası aynı anda FARKLI kişilere ödünç
/// verilebilir — kütüphanede 3 nüshası olan bir kitap 3 öğrenciye aynı anda
/// verilebilmelidir. Sınıfa toplu ödünç ve Ödünç sekmesi bu modeli kullanır.
@Model
final class ActiveLoan {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var bookTitleSnapshot: String
    var studentName: String
    var studentClass: String
    var loanedAt: Date
    var dueDate: Date
    /// Kaç kez süre uzatıldı (kademe kuralındaki sınır için)
    var extensionCount: Int = 0
    var studentID: UUID? = nil
    var memberID: UUID? = nil
    var identitySource: String? = nil
    var studentNumberSnapshot: String? = nil
    var copyID: UUID? = nil
    var needsIdentityReview: Bool = false
    /// library / textbook: ders kitabı hareketleri okuma puanına karışmaz.
    var kind: String = "library"
    var periodSnapshot: String? = nil

    var isOverdue: Bool { dueDate < Calendar.current.startOfDay(for: .now) }

    init(bookID: UUID, bookTitleSnapshot: String, studentName: String, studentClass: String, dueDate: Date) {
        self.id = UUID()
        self.bookID = bookID
        self.bookTitleSnapshot = bookTitleSnapshot
        self.studentName = studentName
        self.studentClass = studentClass
        self.loanedAt = .now
        self.dueDate = dueDate
    }
}

/// Bir kitabın kaç nüshasının şu an ödünçte olduğunu ve kaç nüshanın boşta
/// olduğunu hesaplar — `ActiveLoan` kayıtlarını `CatalogBook.quantity` ile karşılaştırır.
enum LoanAvailability {
    static func activeLoanCount(for bookID: UUID, in loans: [ActiveLoan]) -> Int {
        loans.filter { $0.bookID == bookID }.count
    }

    static func availableCopies(for book: CatalogBook, activeLoans: [ActiveLoan]) -> Int {
        SchoolLibraryService.availableCopies(for: book, loans: activeLoans)
    }
}

/// Ödünç ekranlarında kütüphane ödüncü ile ders kitabı dağıtımını ayırır: yüzlerce ders kitabı
/// teslimi gecikenler, özetler ve Ana Sayfa kartlarında kütüphane ödüncüyle karışmasın.
enum LoanKindFilter: String, CaseIterable, Identifiable {
    case kutuphane = "Kütüphane", dersKitabi = "Ders kitabı", tumu = "Tümü"
    var id: String { rawValue }

    func uygula(_ loans: [ActiveLoan]) -> [ActiveLoan] {
        switch self {
        case .kutuphane: loans.filter { $0.kind != "textbook" }
        case .dersKitabi: loans.filter { $0.kind == "textbook" }
        case .tumu: loans
        }
    }

    /// Vadesi geçmiş kütüphane ödünçleri (ders kitabı hariç); Ana Sayfa "gecikmiş" kartı bunu kullanır.
    static func gecikenKutuphane(loans: [ActiveLoan], now: Date = .now) -> [ActiveLoan] {
        let gunBasi = Calendar.current.startOfDay(for: now)
        return loans.filter { $0.kind != "textbook" && $0.dueDate < gunBasi }
    }

    /// Teslim bekleyen ders kitabı sayısı.
    static func dersKitabiBekleyen(loans: [ActiveLoan]) -> Int { loans.filter { $0.kind == "textbook" }.count }
}

// MARK: - Sınıfa Toplu Ödünç

/// Bir öğretmen/kütüphaneci, seçilen sınıftaki öğrencilere aynı kitabı (nüsha
/// sınırı dahilinde) veya farklı kitapları tek ekrandan dağıtır.
struct ClassLoanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CatalogBook.title) private var books: [CatalogBook]
    @Query private var activeLoans: [ActiveLoan]

    @State private var selectedClass = ""
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var bookQuery = ""
    @State private var selectedBook: CatalogBook?
    @AppStorage("loanDurationDays") private var loanDurationDays = 15
    @State private var resultMessage: String?

    private var classNames: [String] { StudentStore.classNames() }
    private var studentsInClass: [Student] {
        selectedClass.isEmpty ? [] : StudentStore.students(in: selectedClass)
    }
    /// Seçili kitabı şu an elinde tutan öğrenciler: aynı eser ikinci kez verilmez.
    private var elindekiler: Set<UUID> {
        guard let selectedBook else { return [] }
        return Set(activeLoans.filter { $0.bookID == selectedBook.id && $0.kind != "textbook" && $0.memberID == nil }.compactMap(\.studentID))
    }

    private var matchingBooks: [CatalogBook] {
        guard !bookQuery.isEmpty else { return [] }
        let query = CatalogMatcher.normalize(bookQuery)
        return books.filter {
            CatalogMatcher.normalize($0.title).contains(query)
                || CatalogMatcher.normalize($0.isbn ?? "").contains(query)
        }
        .prefix(8)
        .map { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sınıf") {
                    if classNames.isEmpty {
                        Text("Önce Öğrenciler ekranından sınıf/öğrenci ekleyin.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Sınıf", selection: $selectedClass) {
                            Text("Seçin").tag("")
                            ForEach(classNames, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }

                if !studentsInClass.isEmpty {
                    Section("Öğrenciler (\(selectedStudentIDs.count)/\(studentsInClass.count) seçili)") {
                        // Tek geçiş düğmesi: yan yana iki küçük düğme birbirine karışıyordu.
                        let tumuSecili = selectedStudentIDs.isSuperset(of: studentsInClass.map(\.id))
                        Button(tumuSecili ? "Seçimi kaldır" : "Tümünü seç",
                               systemImage: tumuSecili ? "circle.dashed" : "checkmark.circle") {
                            selectedStudentIDs = tumuSecili ? [] : Set(studentsInClass.map(\.id))
                        }
                        .buttonStyle(.borderless)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        ForEach(studentsInClass) { student in
                            Button {
                                toggle(student.id)
                            } label: {
                                HStack {
                                    Image(systemName: selectedStudentIDs.contains(student.id)
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(KitapTema.ana)
                                    Text(student.name)
                                    Spacer()
                                    if elindekiler.contains(student.id) {
                                        Text("Elinde").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Kitap") {
                    TextField("Kitap adı veya ISBN ara", text: $bookQuery)
                    ForEach(matchingBooks) { book in
                        Button {
                            selectedBook = book
                            bookQuery = book.title
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(book.title).font(.subheadline)
                                    // Tek durum sözlüğü: "Rafta", "2/3 rafta", "Ödünçte", "Sırada", "Kayıp"…
                                    Text(KitapDurumu.rozet(book, stok: SchoolLibraryService.stock(for: book, context: modelContext)).metin)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedBook?.id == book.id {
                                    Image(systemName: "checkmark").foregroundStyle(KitapTema.basari)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let selectedBook {
                    Section {
                        let available = SchoolLibraryService.stock(for: selectedBook, context: modelContext).available
                        Text("Seçili kitapta \(available) boş nüsha var. \(selectedStudentIDs.count) öğrenci seçtiniz.")
                            .font(.footnote)
                            .foregroundStyle(available < selectedStudentIDs.count ? .orange : .secondary)

                        Button {
                            distributeLoans(book: selectedBook, available: available)
                        } label: {
                            Label("Seçili Öğrencilere Ödünç Ver", systemImage: "person.3.fill")
                        }
                        .disabled(selectedStudentIDs.isEmpty)
                    }
                }
            }
            .navigationTitle("Sınıfa Toplu Ödünç")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .alert("Sınıfa Toplu Ödünç", isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            )) {
                Button("Tamam", role: .cancel) { }
            } message: {
                Text(resultMessage ?? "")
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selectedStudentIDs.contains(id) { selectedStudentIDs.remove(id) } else { selectedStudentIDs.insert(id) }
    }

    /// Toplu ödünç görevlide de kimlik ister (ayarlar metni: toplu değişiklik Face ID ister).
    private func distributeLoans(book: CatalogBook, available: Int) {
        let targets = studentsInClass.filter { selectedStudentIDs.contains($0.id) }
        let sinif = selectedClass
        Task {
            do {
                let sonuc = try await YetkiKapisi.yoneticiyleCalistir(neden: "Sınıfa toplu ödünç için kimliğinizi doğrulayın") {
                    try SchoolLibraryService.batchLend(book: book, students: targets, className: sinif, context: modelContext)
                }
                var metin = "\(sonuc.loans.count) öğrenciye ödünç verildi."
                if !sonuc.skipped.isEmpty { metin += "\nZaten elinde olduğu için atlananlar:\n" + sonuc.skipped.joined(separator: "\n") }
                if !sonuc.failures.isEmpty { metin += "\nVerilemeyenler:\n" + sonuc.failures.joined(separator: "\n") }
                resultMessage = metin
                selectedStudentIDs = []
            } catch { resultMessage = error.localizedDescription }
        }
    }
}
