import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Okul kütüphanesi öğrenci kaydı: ad, okul numarası, sınıf/şube.
/// Tam bir öğrenci bilgi sistemi değildir — ödünç ve raporlama akışlarını
/// hızlandıran hafif bir kayıt defteridir.
nonisolated struct Student: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var number: String = ""
    var className: String = ""
}

/// JSON defterlerinin "değişti mi?" ölçüsü: yol + değişiklik zamanı + boyut. Değişmedikçe çözülmüş liste
/// bellekten verilir; yazımlar (ve geri yükleme sonrası `invalidateCaches`) önbelleği yeniler.
nonisolated struct DefterParmakIzi: Equatable, Sendable {
    let path: String
    let modified: Date?
    let size: Int

    static func of(_ url: URL) -> DefterParmakIzi? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return DefterParmakIzi(path: url.path, modified: attributes[.modificationDate] as? Date, size: (attributes[.size] as? NSNumber)?.intValue ?? -1)
    }
}

enum StudentStore {
    static var directoryOverride: URL?
    private static var cache: (print: DefterParmakIzi, list: [Student])?

    /// Dışarıdan dosya değişikliğinden (arşiv geri yükleme, geri alma) sonra çağrılır.
    static func invalidateCaches() { cache = nil }

    private static var url: URL? {
        if let directoryOverride { return directoryOverride.appendingPathComponent("Ogrenciler.json") }
        // Kişisel veri klasörü Veri paketinin göçüyle değişir (eski yol okunur, göçten sonra yeni yol); her çağrıda türetilir.
        return MetadataRelocation.metadataDirectory.appendingPathComponent("Ogrenciler.json")
    }

    static var storageURL: URL? { url }

    static func all() -> [Student] { (try? allVerified()) ?? [] }

    /// Eksik dosya boş defterdir; mevcut bozuk/okunamayan defterin üzerine yazılmaz.
    static func allVerified() throws -> [Student] {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        guard let print = DefterParmakIzi.of(url) else { cache = nil; return [] }
        if let cache, cache.print == print { return cache.list }
        let list = try JSONDecoder().decode([Student].self, from: Data(contentsOf: url))
        cache = (print, list)
        return list
    }

    @discardableResult
    static func addVerified(_ student: Student) throws -> Bool {
        var list = try allVerified()
        guard !list.contains(where: {
            $0.id == student.id || (CatalogMatcher.normalize($0.name) == CatalogMatcher.normalize(student.name)
                && $0.className == student.className && $0.number == student.number)
        }) else { return false }
        list.append(student)
        try replaceAllVerified(list)
        return true
    }

    static func add(_ student: Student) {
        do { _ = try addVerified(student) } catch { AppLog.write("Öğrenci eklenemedi; mevcut defter korundu") }
    }

    static func removeVerified(id: UUID, context: ModelContext? = nil) throws {
        try SchoolLibraryService.requireAdmin()
        guard let context = context ?? KitapVeritabani.shared?.mainContext else {
            throw SchoolLibraryService.OperationError(message: "Öğrenci dolaşım bağlantıları denetlenemedi; kayıt silinmedi.")
        }
        let loans = try context.fetch(FetchDescriptor<ActiveLoan>())
        let reservations = try context.fetch(FetchDescriptor<Reservation>())
        guard !loans.contains(where: { $0.studentID == id && $0.memberID == nil }),
              !reservations.contains(where: { !$0.isClosed && $0.studentID == id && $0.memberID == nil }) else {
            throw SchoolLibraryService.OperationError(message: "Bu öğrencinin aktif ödüncü veya rezervasyonu var. Önce dolaşım kaydını kapatın; geçmiş için mezun listesi kullanılabilir.")
        }
        try replaceAllVerified(allVerified().filter { $0.id != id })
    }

    static func remove(id: UUID) {
        do { try removeVerified(id: id) } catch { AppLog.write("Öğrenci silinemedi; mevcut defter korundu") }
    }

    @discardableResult
    static func importVerified(_ incoming: [Student]) throws -> Int {
        try SchoolLibraryService.requireAdmin()
        var list = try allVerified()
        var added = 0
        for student in incoming where !student.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard !list.contains(where: { $0.id == student.id ||
                (CatalogMatcher.normalize($0.name) == CatalogMatcher.normalize(student.name)
                    && $0.className == student.className && $0.number == student.number) }) else { continue }
            list.append(student); added += 1
        }
        try replaceAllVerified(list)
        return added
    }

    static func classNames() -> [String] {
        Array(Set(all().map(\.className).filter { !$0.isEmpty })).sorted()
    }

    static func students(in className: String) -> [Student] {
        all().filter { $0.className == className }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func suggestions(matching query: String) -> [Student] {
        guard !query.isEmpty else { return [] }
        let key = CatalogMatcher.normalize(query)
        return all()
            .filter { CatalogMatcher.normalize($0.name).contains(key) }
            .prefix(5)
            .map { $0 }
    }

    static func replaceAllVerified(_ list: [Student]) throws {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(list).write(to: url, options: .atomic)
        cache = DefterParmakIzi.of(url).map { ($0, list) }
    }
}

nonisolated struct GraduatedStudent: Codable, Identifiable, Equatable {
    var id: UUID { student.id }
    var student: Student
    var graduatedAt: Date
}

/// Mezun kimliği silinmez; geri çağırma aynı UUID ile açık borç ve geçmişi korur.
enum GraduatedStudentStore {
    static var storageURL: URL? { StudentStore.storageURL?.deletingLastPathComponent().appendingPathComponent("Mezunlar.json") }

    static func allVerified() throws -> [GraduatedStudent] {
        guard let url = storageURL else { throw CocoaError(.fileNoSuchFile) }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let records = try decoder.decode([GraduatedStudent].self, from: Data(contentsOf: url))
        guard Set(records.map(\.id)).count == records.count else { throw CocoaError(.fileReadCorruptFile) }
        return records
    }

    static func replaceAllVerified(_ records: [GraduatedStudent]) throws {
        guard let url = storageURL else { throw CocoaError(.fileNoSuchFile) }
        guard Set(records.map(\.id)).count == records.count else { throw CocoaError(.fileWriteInvalidFileName) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(records).write(to: url, options: .atomic)
    }

    static func recall(id: UUID, className: String, context: ModelContext) throws {
        try SchoolLibraryService.requireAdmin()
        let nextClass = className.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextClass.isEmpty else { throw SchoolLibraryService.OperationError(message: "Geri çağrılacak öğrencinin sınıfını yazın.") }
        let previous = try allVerified(), active = try StudentStore.allVerified()
        guard let record = previous.first(where: { $0.id == id }) else {
            throw SchoolLibraryService.OperationError(message: "Mezun kaydı bulunamadı.")
        }
        let loans = try context.fetch(FetchDescriptor<ActiveLoan>())
        let previousClasses = Dictionary(uniqueKeysWithValues: loans.filter { $0.studentID == id && $0.memberID == nil }.map { ($0.id, $0.studentClass) })
        var restored = active.first { $0.id == id } ?? record.student; restored.className = nextClass
        do {
            // Çökmede iki defterde bulunması, kimliğin ikisinden de kaybolmasından güvenlidir.
            try StudentStore.replaceAllVerified(active.filter { $0.id != id } + [restored])
            for loan in loans where loan.studentID == id && loan.memberID == nil { loan.studentClass = nextClass }
            try context.save()
            try replaceAllVerified(previous.filter { $0.id != id })
        } catch {
            let failure = error
            for loan in loans where previousClasses[loan.id] != nil { loan.studentClass = previousClasses[loan.id]! }
            do { try context.save(); try StudentStore.replaceAllVerified(active); try replaceAllVerified(previous) }
            catch { throw SchoolLibraryService.OperationError(message: "Geri çağırma ve geri alma yazımı tamamlanamadı; kimlik korunuyor, tam arşivden kurtarın.") }
            throw failure
        }
    }
}

struct GraduatedStudentsView: View {
    @Environment(\.modelContext) private var context
    @State private var graduates: [GraduatedStudent] = []
    @State private var search = ""
    @State private var selected: GraduatedStudent?
    @State private var className = ""
    @State private var error: String?
    private var filtered: [GraduatedStudent] {
        let term = CatalogMatcher.normalize(search)
        return graduates.filter { term.isEmpty || CatalogMatcher.normalize([$0.student.name, $0.student.number, $0.student.className].joined(separator: " ")).contains(term) }
            .sorted { $0.graduatedAt > $1.graduatedAt }
    }
    var body: some View {
        List {
            Text("Mezunların öğrenci kimliği, açık borcu ve geçmişi korunur. Geri çağırma aynı kimlikle aktif listeye taşır.").font(.footnote).foregroundStyle(.secondary)
            ForEach(filtered) { graduate in
                VStack(alignment: .leading, spacing: 6) {
                    Text(graduate.student.name).font(.headline)
                    Text("\(graduate.student.className) · No: \(graduate.student.number) · \(graduate.graduatedAt.formatted(date: .abbreviated, time: .omitted))").font(.subheadline).foregroundStyle(.secondary)
                    NavigationLink("Öğrenci geçmişi") { OgrenciProfili(ogrenci: graduate.student) }
                    Button("Aktif listeye geri çağır") { selected = graduate; className = graduate.student.className }.frame(minHeight: 44)
                }
            }
            if filtered.isEmpty { ContentUnavailableView("Mezun kaydı yok", systemImage: "graduationcap") }
        }
        .navigationTitle("Mezun Defteri")
        .searchable(text: $search, prompt: "Ad, numara veya eski sınıf")
        .onAppear { reload() }
        .alert("Mezun defteri", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Tamam", role: .cancel) { }
        } message: { Text(error ?? "") }
        .sheet(item: $selected) { graduate in
            NavigationStack {
                Form {
                    Text(graduate.student.name).font(.headline)
                    TextField("Yeni sınıf", text: $className)
                    if let error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                    Button("Aynı kimlikle geri çağır") {
                        Task {
                            guard await YetkiDurumu.shared.yoneticiOl() else { error = YetkiDurumu.shared.hata; return }
                            do { try GraduatedStudentStore.recall(id: graduate.id, className: className, context: context); selected = nil; reload() }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(className.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.navigationTitle("Geri Çağır")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { selected = nil } } }
            }
        }
    }
    private func reload() { do { graduates = try GraduatedStudentStore.allVerified() } catch { self.error = error.localizedDescription } }
}

// MARK: - Kademe bazlı ödünç kuralları

struct GradeLoanRule: Codable, Identifiable {
    var id = UUID()
    var gradePrefix: String  // sınıf adının başlangıcı, örn. "5", "9", "Lise"
    var maxConcurrentLoans: Int = 3
    var loanDurationDays: Int = 15
}

enum GradeLoanRuleStore {
    static var directoryOverride: URL?
    private static var url: URL? {
        if let directoryOverride { return directoryOverride.appendingPathComponent("KademeKurallari.json") }
        return MetadataRelocation.metadataDirectory.appendingPathComponent("KademeKurallari.json")
    }

    static var storageURL: URL? { url }
    static func all() -> [GradeLoanRule] { (try? allVerified()) ?? [] }
    static func allVerified() throws -> [GradeLoanRule] {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let rules = try JSONDecoder().decode([GradeLoanRule].self, from: Data(contentsOf: url))
        try validate(rules)
        return rules
    }
    private static func validate(_ rules: [GradeLoanRule]) throws {
        let prefixes = rules.map { $0.gradePrefix.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard prefixes.allSatisfy({ !$0.isEmpty }), Set(prefixes).count == prefixes.count,
              rules.allSatisfy({ (0...99).contains($0.maxConcurrentLoans) && (1...365).contains($0.loanDurationDays) }) else {
            throw SchoolLibraryService.OperationError(message: "Kademe kuralları bozuk: her kademe tek olmalı, kota 0–99 ve süre 1–365 gün olmalı.")
        }
    }

    static func save(_ rules: [GradeLoanRule]) {
        do { try saveVerified(rules) } catch { AppLog.write("Kademe kuralları kaydedilemedi") }
    }

    static func saveVerified(_ rules: [GradeLoanRule]) throws {
        try SchoolLibraryService.requireAdmin()
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        try validate(rules)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(rules).write(to: url, options: .atomic)
    }

    /// Yalnız tanımlı bir kural eşleşirse döner (kota denetimi varsayılanla kimseyi engellemesin).
    static func explicitRule(for className: String, rules: [GradeLoanRule]? = nil) -> GradeLoanRule? {
        guard !className.isEmpty else { return nil }
        return (rules ?? all())
            .filter { !$0.gradePrefix.isEmpty && prefixMatches($0.gradePrefix, className) }
            .max { $0.gradePrefix.count < $1.gradePrefix.count }
    }

    /// "1" öneki "1-A"ya uyar, "10-A"ya uymaz: rakamla biten önekten sonra rakam gelemez.
    static func prefixMatches(_ prefix: String, _ className: String) -> Bool {
        guard className.hasPrefix(prefix) else { return false }
        return !(prefix.last?.isNumber == true && className.dropFirst(prefix.count).first?.isNumber == true)
    }

    /// Sınıf adına göre en uzun eşleşen önekli kuralı döndürür; kural yoksa varsayılan.
    static func rule(for className: String) -> GradeLoanRule {
        let matches = all().filter { prefixMatches($0.gradePrefix, className) }
        if let best = matches.max(by: { $0.gradePrefix.count < $1.gradePrefix.count }) {
            return best
        }
        return GradeLoanRule(gradePrefix: "", maxConcurrentLoans: 3, loanDurationDays: 15)
    }
}

// MARK: - Öğrenci yönetimi ekranı

struct StudentsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var students: [Student] = StudentStore.all()
    @State private var newName = ""
    @State private var newNumber = ""
    @State private var newClass = ""
    @State private var isShowingCSVImporter = false
    @State private var importMessage: String?
    @State private var csvRows: [[String]] = []

    private var groupedByClass: [(String, [Student])] {
        Dictionary(grouping: students) { $0.className.isEmpty ? "Sınıfsız" : $0.className }
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Ad Soyad", text: $newName)
                    TextField("Okul numarası", text: $newNumber)
                    TextField("Sınıf (örn. 9-A)", text: $newClass)
                    Button {
                        addStudent()
                    } label: {
                        Label("Öğrenci Ekle", systemImage: "person.badge.plus")
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button {
                        isShowingCSVImporter = true
                    } label: {
                        Label("CSV'den Toplu İçe Aktar", systemImage: "square.and.arrow.down")
                    }
                    Button("Son öğrenci aktarımını geri al", systemImage: "arrow.uturn.backward") {
                        geriAl(receiptID: nil)
                    }
                    let makbuzlar = StudentImportService.geriAlinabilirMakbuzlar()
                    if makbuzlar.count > 1 {
                        Menu("Önceki aktarımlardan birini geri al", systemImage: "clock.arrow.circlepath") {
                            ForEach(makbuzlar) { makbuz in
                                Button("\(makbuz.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(makbuz.affectedIDs.count) öğrenci") { geriAl(receiptID: makbuz.id) }
                            }
                        }
                    }
                } footer: {
                    Text("Herhangi bir CSV/Excel dışa aktarımı olur: sütunları içe aktarırken siz eşlersiniz.")
                }

                Section {
                    NavigationLink { GraduatedStudentsView().onDisappear { students = StudentStore.all() } } label: {
                        Label("Mezun Defteri", systemImage: "graduationcap")
                    }
                    NavigationLink {
                        SinifPanosu()
                    } label: {
                        Label("Sınıf Panosu", systemImage: "chart.bar.doc.horizontal")
                    }
                    NavigationLink {
                        SinifAtlatmaSihirbazi()
                            .onDisappear { students = StudentStore.all() }
                    } label: {
                        Label("Yıl Sonu Sınıf Atlatma", systemImage: "arrow.up.forward.circle")
                    }
                }

                ForEach(groupedByClass, id: \.0) { className, list in
                    Section("\(className) (\(list.count))") {
                        ForEach(list) { student in
                            NavigationLink {
                                OgrenciProfili(ogrenci: student)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(student.name).font(.subheadline.weight(.medium))
                                    if !student.number.isEmpty {
                                        Text("No: \(student.number)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { list[$0].id }
                            Task {
                                do {
                                    try await YetkiKapisi.yoneticiyleCalistir(neden: "Öğrenci kaydını silmek için kimliğinizi doğrulayın") {
                                        for id in ids { try StudentStore.removeVerified(id: id, context: modelContext) }
                                    }
                                    students = try StudentStore.allVerified()
                                } catch { importMessage = "Öğrenci silinemedi: \(error.localizedDescription)" }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Öğrenciler")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $isShowingCSVImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                importStudentsCSV(result)
            }
            .sheet(isPresented: Binding(get: { !csvRows.isEmpty }, set: { if !$0 { csvRows = [] } })) {
                OgrenciCSVEslestirmeSayfasi(satirlar: csvRows) { count in
                    students = StudentStore.all()
                    importMessage = "\(count) öğrenci içe aktarıldı."
                }
            }
            .alert("İçe Aktarma", isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )) {
                Button("Tamam", role: .cancel) { }
            } message: {
                Text(importMessage ?? "")
            }
        }
    }

    private func geriAl(receiptID: UUID?) {
        Task {
            guard await YetkiDurumu.shared.yoneticiOl() else { importMessage = YetkiDurumu.shared.hata ?? "Yönetici kimliği gerekir."; return }
            do {
                let count = try StudentImportService.undo(receiptID: receiptID, context: modelContext)
                students = try StudentStore.allVerified()
                importMessage = "\(count) öğrenci kimliğindeki aktarım değişikliği geri alındı."
            } catch { importMessage = error.localizedDescription }
        }
    }

    private func addStudent() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            let added = try StudentStore.addVerified(Student(
                name: name,
                number: newNumber.trimmingCharacters(in: .whitespaces),
                className: newClass.trimmingCharacters(in: .whitespaces)
            ))
            guard added else { importMessage = "Aynı ad, numara ve sınıfla öğrenci zaten kayıtlı."; return }
            students = try StudentStore.allVerified()
            newName = ""; newNumber = ""; newClass = ""
        } catch { importMessage = "Öğrenci eklenemedi; bilgiler korunuyor: \(error.localizedDescription)" }
    }

    private func importStudentsCSV(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let rows = OgrenciCSVEslestirme.satirlar(data)
            guard !rows.isEmpty else {
                importMessage = "Dosyada satır bulunamadı."
                return
            }
            // Sütun eşleme ekranı açılır (ad/numara/sınıf hangi sütunda?)
            csvRows = rows
        } catch {
            importMessage = "İçe aktarma başarısız: \(error.localizedDescription)"
        }
    }
}

/// Serbest metin girişini korur ama yazarken kayıtlı öğrencilerden öneri gösterir.
struct StudentSuggestField: View {
    let placeholder: String
    @Binding var text: String
    @Binding var className: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(placeholder, text: $text)

            let suggestions = StudentStore.suggestions(matching: text)
            if !suggestions.isEmpty && suggestions.first?.name != text {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        // Öneri düğmeleri en az 44 pt dokunma alanı taşır
                        ForEach(suggestions) { student in
                            Button("\(student.name) (\(student.className))") {
                                text = student.name
                                className = student.className
                            }
                            .buttonStyle(.kitapTonlu())
                        }
                    }
                }
            }
        }
    }
}
