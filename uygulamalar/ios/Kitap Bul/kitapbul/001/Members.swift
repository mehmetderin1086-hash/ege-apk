import Foundation
import SwiftUI
import SwiftData

nonisolated enum MemberKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case teacher, guardian, staff, other
    var id: Self { self }
    var title: String {
        switch self {
        case .teacher: "Öğretmen"
        case .guardian: "Veli"
        case .staff: "Personel"
        case .other: "Diğer üye"
        }
    }
}

/// Öğrencilerden ayrı kimlik; eski kaydın belirtilmemiş türü tahmin edilmez.
nonisolated struct Member: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var memberNumber: String = ""
    var note: String = ""
    var kind: MemberKind? = nil
    var kindTitle: String { kind?.title ?? "Türü belirtilmemiş" }
}

enum MemberStore {
    static var directoryOverride: URL?
    private static var cache: (print: DefterParmakIzi, list: [Member])?

    /// Dışarıdan dosya değişikliğinden (arşiv geri yükleme, geri alma) sonra çağrılır.
    static func invalidateCaches() { cache = nil }

    private static var url: URL? {
        if let directoryOverride { return directoryOverride.appendingPathComponent("Uyeler.json") }
        // Kişisel veri klasörü Veri paketinin göçüyle değişir (eski yol okunur, göçten sonra yeni yol); her çağrıda türetilir.
        return MetadataRelocation.metadataDirectory.appendingPathComponent("Uyeler.json")
    }

    static var storageURL: URL? { url }

    static func all() -> [Member] { (try? allVerified()) ?? [] }

    static func allVerified() throws -> [Member] {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        guard let print = DefterParmakIzi.of(url) else { cache = nil; return [] }
        if let cache, cache.print == print { return cache.list }
        let list = try JSONDecoder().decode([Member].self, from: Data(contentsOf: url))
        cache = (print, list)
        return list
    }

    @discardableResult
    static func addVerified(_ member: Member) throws -> Bool {
        var list = try allVerified()
        guard !list.contains(where: { $0.id == member.id ||
            CatalogMatcher.normalize($0.name) == CatalogMatcher.normalize(member.name)
                && $0.memberNumber == member.memberNumber }) else { return false }
        list.append(member)
        try replaceAllVerified(list)
        return true
    }

    static func add(_ member: Member) {
        do { _ = try addVerified(member) } catch { AppLog.write("Üye eklenemedi; mevcut defter korundu") }
    }

    static func removeVerified(id: UUID, context: ModelContext? = nil) throws {
        try SchoolLibraryService.requireAdmin()
        guard let context = context ?? KitapVeritabani.shared?.mainContext else {
            throw SchoolLibraryService.OperationError(message: "Üye ödünç bağlantıları denetlenemedi; kayıt silinmedi.")
        }
        let active = try context.fetch(FetchDescriptor<ActiveLoan>())
        guard !active.contains(where: { $0.memberID == id }) else {
            throw SchoolLibraryService.OperationError(message: "Bu üyenin aktif ödüncü var. Önce kitabı iade alın.")
        }
        let reservations = try context.fetch(FetchDescriptor<Reservation>())
        guard !reservations.contains(where: { !$0.isClosed && $0.memberID == id }) else {
            throw SchoolLibraryService.OperationError(message: "Bu üyenin açık rezervasyonu var. Önce rezervasyonu kapatın.")
        }
        try replaceAllVerified(allVerified().filter { $0.id != id })
    }

    static func remove(id: UUID) {
        do { try removeVerified(id: id) } catch { AppLog.write("Üye silinemedi; mevcut defter korundu") }
    }

    static func updateKind(id: UUID, kind: MemberKind) throws {
        try SchoolLibraryService.requireAdmin()
        var list = try allVerified()
        guard let index = list.firstIndex(where: { $0.id == id }) else {
            throw SchoolLibraryService.OperationError(message: "Üye kaydı bulunamadı; tür değişmedi.")
        }
        list[index].kind = kind
        try replaceAllVerified(list)
    }

    /// Yazılan metne göre üye adı önerileri (en fazla 5).
    static func suggestions(matching query: String) -> [Member] {
        guard !query.isEmpty else { return [] }
        let key = CatalogMatcher.normalize(query)
        return all()
            .filter { CatalogMatcher.normalize($0.name).contains(key) }
            .prefix(5)
            .map { $0 }
    }

    static func replaceAllVerified(_ list: [Member]) throws {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(list).write(to: url, options: .atomic)
        cache = DefterParmakIzi.of(url).map { ($0, list) }
    }
}

// MARK: - Üyeler ekranı

struct MembersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var members: [Member] = MemberStore.all()
    @State private var newName = ""
    @State private var newNumber = ""
    @State private var newKind: MemberKind = .other
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Ad Soyad", text: $newName)
                    TextField("Üye no (isteğe bağlı)", text: $newNumber)
                    Picker("Üye türü", selection: $newKind) {
                        ForEach(MemberKind.allCases) { Text($0.title).tag($0) }
                    }
                    Button {
                        addMember()
                    } label: {
                        Label("Üye Ekle", systemImage: "person.badge.plus")
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section("Kayıtlı Üyeler (\(members.count))") {
                    if members.isEmpty {
                        Text("Henüz üye eklenmedi. Ödünç verirken de otomatik eklenir.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(members) { member in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name).font(.subheadline.weight(.medium))
                            Text(member.kindTitle).font(.caption)
                            Menu("Türü Düzenle") {
                                ForEach(MemberKind.allCases) { kind in
                                    Button(kind.title) {
                                        Task {
                                            do {
                                                try await YetkiKapisi.yoneticiyleCalistir(neden: "Üye türünü değiştirmek için kimliğinizi doğrulayın") {
                                                    try MemberStore.updateKind(id: member.id, kind: kind)
                                                }
                                                members = try MemberStore.allVerified()
                                            } catch { saveError = error.localizedDescription }
                                        }
                                    }
                                }
                            }
                            .font(.caption)
                            .frame(minHeight: 44, alignment: .leading)
                            if !member.memberNumber.isEmpty {
                                Text("Üye no: \(member.memberNumber)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { members[$0].id }
                        Task {
                            do {
                                try await YetkiKapisi.yoneticiyleCalistir(neden: "Üye kaydını silmek için kimliğinizi doğrulayın") {
                                    for id in ids { try MemberStore.removeVerified(id: id, context: modelContext) }
                                }
                                members = try MemberStore.allVerified()
                            } catch { saveError = error.localizedDescription }
                        }
                    }
                }
                Section {
                    NavigationLink("Üye Türü Süre ve Kotaları") { MemberLoanRulesView() }
                }
            }
            .alert("Üye kaydı", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("Tamam", role: .cancel) { }
            } message: { Text(saveError ?? "") }
            .navigationTitle("Üyeler")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }

    private func addMember() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            guard try MemberStore.addVerified(Member(name: name, memberNumber: newNumber.trimmingCharacters(in: .whitespaces), kind: newKind)) else {
                saveError = "Aynı ad ve numarayla üye zaten kayıtlı."; return
            }
            members = try MemberStore.allVerified()
            newName = ""; newNumber = ""
        } catch { saveError = error.localizedDescription }
    }
}

// MARK: - Üye adı önerileriyle metin alanı

/// Serbest metin girişini korur ama yazarken kayıtlı üyelerden öneri gösterir.
struct MemberSuggestField: View {
    let placeholder: String
    @Binding var text: String
    let onSelection: ((UUID?) -> Void)?
    @State private var selectedMemberID: UUID?

    init(placeholder: String, text: Binding<String>, onSelection: ((UUID?) -> Void)? = nil) {
        self.placeholder = placeholder
        _text = text
        self.onSelection = onSelection
    }

    private var editableText: Binding<String> {
        Binding(get: { text }, set: { value in
            text = value
            selectedMemberID = nil
            onSelection?(nil)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(placeholder, text: editableText)

            let suggestions = MemberStore.suggestions(matching: text)
            if !suggestions.isEmpty && selectedMemberID == nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions) { member in
                            Button {
                                text = member.name
                                selectedMemberID = member.id
                                onSelection?(member.id)
                            } label: {
                                // Çip küçük punto kalır ama en az 44 pt yükseklik taşır
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name)
                                    Text(member.kindTitle).foregroundStyle(KitapTema.ikincilMetin)
                                    if !member.memberNumber.isEmpty {
                                        Text("Üye no: \(member.memberNumber)")
                                            .foregroundStyle(KitapTema.ikincilMetin)
                                    }
                                }
                                .frame(minHeight: 44)
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .onChange(of: text) { _, value in
            if let id = selectedMemberID,
               MemberStore.all().first(where: { $0.id == id })?.name != value {
                // Karttan/programdan gelen ad değişimi ebeveynin yeni öğrenci seçimini temizlememeli.
                // Elle düzenleme editableText setter üzerinden kimliği zaten sıfırlar.
                selectedMemberID = nil
            }
        }
    }
}
