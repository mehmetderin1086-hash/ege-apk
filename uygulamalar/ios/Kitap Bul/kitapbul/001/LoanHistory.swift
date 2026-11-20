import Foundation
import SwiftUI

/// Tek bir ödünç hareketi (ver/iade) kaydı.
nonisolated struct LoanEvent: Codable, Identifiable, Equatable, Sendable {
    nonisolated enum Kind: String, Codable {
        case lent = "Ödünç verildi"
        case returned = "İade alındı"
        case lost = "Kayıp bildirildi"
        case extended = "Süre uzatıldı"
        case identityCorrected = "Kimlik düzeltildi"
    }

    var id = UUID()
    var bookID: UUID
    var bookTitle: String
    var person: String
    var kind: Kind
    var date: Date
    var dueDate: Date?
    /// İade sırasında gecikme olmuş muydu?
    var wasLate: Bool = false
    var studentID: UUID? = nil
    var memberID: UUID? = nil
    var identitySource: String? = nil
    var copyID: UUID? = nil
    var classSnapshot: String? = nil
    var loanKind: String? = nil
    var periodSnapshot: String? = nil
    var returnedCondition: String? = nil
    var memberKindSnapshot: String? = nil
    var previousDueDate: Date? = nil
    var loanID: UUID? = nil
    var studentNumberSnapshot: String? = nil
    /// Düzeltmeden önceki canlı ödünç; kişi/nüsha değişikliği denetlenebilir kalır.
    var identityCorrectionBefore: Data? = nil
    /// nil = okuma hakkında bilgi yok. Fiziksel iade tek başına tamamlanmış okuma sayılmaz.
    var readingCompleted: Bool? = nil
}

/// Ödünç geçmişi: tüm ver/iade hareketleri diskte saklanır, kişi bazında özet çıkarır.
enum LoanHistoryStore {
    static var directoryOverride: URL?

    private static var events: [LoanEvent] = []
    private static var loadedPath: String?
    private static var loadFailure: Error?
    /// Okunan dosyanın parmak izi; dosya dışarıdan değişirse (geri yükleme) yeniden okunur.
    private static var loadedPrint: DefterParmakIzi?
    /// Tarihe göre azalan sıralı önbellek; `events` değişince "kirli" olur ve bir sonraki okumada bir kez kurulur.
    private static var sortedCache: [LoanEvent]?
    private static var bookIndex: [UUID: [LoanEvent]]?

    private static var url: URL? {
        if let directoryOverride { return directoryOverride.appendingPathComponent("OduncGecmisi.json") }
        // Kişisel veri klasörü Veri paketinin göçüyle değişir (eski yol okunur, göçten sonra yeni yol); her çağrıda türetilir.
        return MetadataRelocation.metadataDirectory.appendingPathComponent("OduncGecmisi.json")
    }

    static func invalidateCache() { loadedPath = nil; loadedPrint = nil; loadFailure = nil; events = []; markDirty() }
    /// Geri yükleme gibi dışarıdan dosya değişikliklerinden sonra çağrılır (Veri paketi sözleşmesi).
    static func invalidate() { invalidateCache() }

    private static func markDirty() { sortedCache = nil; bookIndex = nil }

    static var storageURL: URL? { url }

    static var all: [LoanEvent] { (try? allVerified(reload: false)) ?? [] }

    /// Bir kitabın hareketleri (en yeni başta); indeks önbellekten gelir, her çağrıda tüm geçmiş taranmaz.
    static func events(forBook bookID: UUID) -> [LoanEvent] {
        if bookIndex == nil { bookIndex = Dictionary(grouping: all, by: \.bookID) }
        return bookIndex?[bookID] ?? []
    }

    /// `reload: true` dosyanın parmak izi değiştiyse diskten okur; değişmediyse bellekteki sıralı önbelleği verir.
    static func allVerified(reload: Bool = true) throws -> [LoanEvent] {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        let mevcutIz = DefterParmakIzi.of(url)
        if loadedPath != url.path || (reload && mevcutIz != loadedPrint) {
            loadedPath = url.path; events = []; loadFailure = nil; markDirty()
            loadedPrint = mevcutIz
            if mevcutIz != nil {
                do {
                    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                    events = try decoder.decode([LoanEvent].self, from: Data(contentsOf: url))
                } catch { loadFailure = error }
            }
        }
        if let loadFailure { throw loadFailure }
        if let sortedCache { return sortedCache }
        let sirali = events.sorted { $0.date > $1.date }
        sortedCache = sirali
        return sirali
    }

    static func record(_ event: LoanEvent) {
        do { try recordVerified(event) } catch { AppLog.write("Ödünç geçmişi kaydedilemedi") }
    }

    static func recordVerified(_ event: LoanEvent) throws {
        let previous = try allVerified()
        guard !previous.contains(where: { $0.id == event.id }) else { return }
        try replaceAll(previous + [event])
    }

    static func events(for studentID: UUID) -> [LoanEvent] {
        all.filter { $0.studentID == studentID && $0.memberID == nil }
    }

    static func replaceAll(_ incoming: [LoanEvent]) throws {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(incoming).write(to: url, options: .atomic)
        events = incoming
        loadedPath = url.path; loadFailure = nil
        loadedPrint = DefterParmakIzi.of(url)
        markDirty()
    }

    static func reassignBook(from oldID: UUID, to newID: UUID, title: String) {
        do {
            var reassigned = try allVerified()
            for index in reassigned.indices where reassigned[index].bookID == oldID {
                reassigned[index].bookID = newID; reassigned[index].bookTitle = title
            }
            try replaceAll(reassigned)
        } catch { AppLog.write("Ödünç geçmişi bağlantıları taşınamadı") }
    }

    static func events(for person: String) -> [LoanEvent] {
        let key = CatalogMatcher.normalize(person)
        return all.filter { CatalogMatcher.normalize($0.person) == key }
    }

    /// Kişi bazında özet: kaç kitap aldı, kaç kez geciktirdi.
    static func people() -> [PersonSummary] {
        var summaries: [String: PersonSummary] = [:]
        for event in all {
            let key = event.memberID.map { "member:" + $0.uuidString } ?? event.studentID?.uuidString ?? (CatalogMatcher.normalize(event.person) + "|" + (event.classSnapshot ?? ""))
            guard !key.isEmpty else { continue }
            var summary = summaries[key] ?? PersonSummary(name: event.person, studentID: event.studentID, memberID: event.memberID, classSnapshot: event.classSnapshot)
            if event.kind == .lent {
                summary.totalLoans += 1
            } else if event.kind == .returned {
                summary.totalReturns += 1
                if event.wasLate { summary.lateReturns += 1 }
            } else if event.kind == .lost { summary.totalLost += 1 }
            summary.lastActivity = max(summary.lastActivity, event.date)
            summaries[key] = summary
        }
        return summaries.values.sorted { $0.lastActivity > $1.lastActivity }
    }

    static func reset() {
        do { try replaceAll([]) } catch { AppLog.write("Ödünç geçmişi sıfırlanamadı") }
    }

    /// Arşivden gelen hareketler aynı kimlikle iki kez eklenmez; başarısız yazım sayılmaz.
    @discardableResult
    static func merge(_ incoming: [LoanEvent]) -> Int {
        do {
            let previous = try allVerified()
            let known = Set(previous.map(\.id))
            let fresh = incoming.filter { !known.contains($0.id) }
            guard !fresh.isEmpty else { return 0 }
            try replaceAll(previous + fresh)
            return fresh.count
        } catch { AppLog.write("Ödünç geçmişi birleştirilemedi; dosya korundu"); return 0 }
    }

    private static func save() {
        do { _ = try allVerified(); try replaceAll(events) }
        catch { AppLog.write("Ödünç geçmişi yazılamadı; dosya korundu") }
    }

}

struct PersonSummary: Identifiable {
    var id: String { memberID.map { "member:" + $0.uuidString } ?? studentID?.uuidString ?? (CatalogMatcher.normalize(name) + "|" + (classSnapshot ?? "")) }
    var name: String
    var studentID: UUID? = nil
    var memberID: UUID? = nil
    var classSnapshot: String? = nil
    var totalLoans = 0
    var totalReturns = 0
    var lateReturns = 0
    var totalLost = 0
    var lastActivity: Date = .distantPast

    var activeCount: Int { max(0, totalLoans - totalReturns - totalLost) }
}

// MARK: - Geçmiş ekranı

struct LoanHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPerson: PersonSummary?
    @State private var search = ""
    private var identityIndex: LibraryIdentitySearchIndex { LibraryIdentitySearchIndex(students: StudentStore.all(), members: MemberStore.all()) }
    private var people: [PersonSummary] {
        let term = CatalogMatcher.normalize(search), index = identityIndex
        guard !term.isEmpty else { return LoanHistoryStore.people() }
        let matchingIDs = Set(events.map { $0.memberID.map { "member:" + $0.uuidString } ?? $0.studentID?.uuidString ?? (CatalogMatcher.normalize($0.person) + "|" + ($0.classSnapshot ?? "")) })
        return LoanHistoryStore.people().filter { person in
            matchingIDs.contains(person.id) || CatalogMatcher.normalize(index.text(name: person.name, className: person.classSnapshot ?? "", studentID: person.studentID, memberID: person.memberID, numberSnapshot: nil)).contains(term)
        }
    }
    private var events: [LoanEvent] {
        let term = CatalogMatcher.normalize(search), index = identityIndex
        return LoanHistoryStore.all.filter { term.isEmpty || CatalogMatcher.normalize(index.text(for: $0)).contains(term) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if events.isEmpty {
                    ContentUnavailableView {
                        Label("Geçmiş boş", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("Ödünç verip iade aldıkça hareketler burada birikir.")
                    }
                } else {
                    List {
                        Section {
                            ForEach(people) { person in
                                Button {
                                    selectedPerson = person
                                } label: {
                                    personRow(person)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Label("Kişiler (\(people.count))", systemImage: "person.2")
                                .foregroundStyle(KitapTema.amazon)
                        }

                        Section {
                            ForEach(events.prefix(100)) { event in
                                eventRow(event)
                            }
                        } header: {
                            Label("Son hareketler", systemImage: "clock")
                                .foregroundStyle(KitapTema.ana)
                        }
                    }
                }
            }
            .navigationTitle("Ödünç Geçmişi")
            .searchable(text: $search, prompt: "Ad, kitap veya okul numarası")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .sheet(item: $selectedPerson) { person in
                PersonDetailView(person: person)
            }
        }
    }

    private func personRow(_ person: PersonSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(.headline)
                Text("\(person.totalLoans) ödünç • \(person.activeCount) elinde")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if person.lateReturns > 0 {
                Text("\(person.lateReturns) gecikme")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.15), in: .capsule)
                    .foregroundStyle(.red)
            }
        }
    }

    private func eventRow(_ event: LoanEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.bookTitle.isEmpty ? "Kitap" : event.bookTitle)
                .font(.subheadline.weight(.medium))
            HStack(spacing: 6) {
                Image(systemName: event.kind == .lent
                      ? "arrow.up.circle" : "arrow.down.circle")
                    .foregroundStyle(event.kind == .lent ? KitapTema.vurgu : KitapTema.basari)
                Text("\(event.kind.rawValue) — \(event.person)")
                Spacer()
                Text(event.date.formatted(date: .abbreviated, time: .omitted))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct PersonDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let person: PersonSummary
    private var personEvents: [LoanEvent] {
        if let id = person.studentID { return LoanHistoryStore.events(for: id) }
        if let id = person.memberID { return LoanHistoryStore.all.filter { $0.memberID == id } }
        return LoanHistoryStore.all.filter {
            $0.studentID == nil && $0.memberID == nil && CatalogMatcher.normalize($0.person) == CatalogMatcher.normalize(person.name)
                && ($0.classSnapshot ?? "") == (person.classSnapshot ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Toplam ödünç", value: "\(person.totalLoans)")
                    LabeledContent("İade edilen", value: "\(person.totalReturns)")
                    LabeledContent("Şu an elinde", value: "\(person.activeCount)")
                    LabeledContent("Geciken iade", value: "\(person.lateReturns)")
                }

                Section("Hareketler") {
                    ForEach(personEvents) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.bookTitle.isEmpty ? "Kitap" : event.bookTitle)
                                .font(.subheadline.weight(.medium))
                            Text("\(event.kind.rawValue) • \(event.date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(event.wasLate ? .red : .secondary)
                        }
                    }
                }
            }
            .navigationTitle(person.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}
