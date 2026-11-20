import Foundation
import SwiftUI
import SwiftData

// MARK: - Sıralama

enum CatalogSort: String, CaseIterable, Identifiable {
    case dateAdded = "Eklenme (yeni → eski)"
    case title = "Ada göre"
    case author = "Yazara göre"
    case year = "Yıla göre (yeni → eski)"

    var id: Self { self }

    var icon: String {
        switch self {
        case .dateAdded: "clock"
        case .title: "textformat"
        case .author: "person"
        case .year: "calendar"
        }
    }

    func apply(_ books: [CatalogBook]) -> [CatalogBook] {
        switch self {
        case .dateAdded:
            books.sorted { $0.addedAt > $1.addedAt }
        case .title:
            books.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .author:
            books.sorted { $0.author.localizedStandardCompare($1.author) == .orderedAscending }
        case .year:
            books.sorted { ($0.publicationYear ?? "") > ($1.publicationYear ?? "") }
        }
    }
}

// MARK: - Kayıtlı görünümler

/// Görünüm + filtre + sıralama + arama birleşimini adlandırıp kaydeder
/// ("B dolabı eksikleri" gibi) — tek dokunuşla geri çağrılır.
struct SavedView: Codable, Identifiable {
    var id = UUID()
    var name: String
    var layout: String
    var filter: String
    var sort: String
    var searchText: String
}

enum SavedViewStore {
    private static var url: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("KayitliGorunumler.json")
    }

    static func all() -> [SavedView] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SavedView].self, from: data)) ?? []
    }

    static func add(_ view: SavedView) {
        var list = all()
        list.removeAll { $0.name == view.name }
        list.append(view)
        save(list)
    }

    static func remove(id: UUID) {
        save(all().filter { $0.id != id })
    }

    private static func save(_ list: [SavedView]) {
        guard let url, let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - Toplu atama

struct BulkAssignment {
    var location = ""
    var cabinet = ""
    var shelf = ""
    var category = ""
}

struct BulkAssignSheet: View {
    @Environment(\.dismiss) private var dismiss
    let count: Int
    let onApply: (BulkAssignment) -> Void

    @State private var assignment = BulkAssignment()

    var body: some View {
        NavigationStack {
            Form {
                Section("Konum") {
                    TextField("Oda / Genel konum", text: $assignment.location)
                    TextField("Dolap", text: $assignment.cabinet)
                    TextField("Raf", text: $assignment.shelf)
                }
                Section("Kategori") {
                    TextField("Kategori", text: $assignment.category)
                }
                Section {
                    Text("Boş bırakılan alanlar değiştirilmez. Seçili \(count) kitaba uygulanacak.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Toplu Ata")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uygula") {
                        onApply(assignment)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Mükerrer temizleyici

private struct DuplicateCandidate: Sendable {
    let id: UUID
    let isbn: String
    let title: String
    let author: String
}

/// "Farklı baskı, bir daha gösterme" kararları: kimlik çiftleri JSON olarak saklanır.
enum AyriTutBellegi {
    private static var url: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AyriTutCiftleri.json")
    }

    nonisolated static func anahtar(_ ids: [UUID]) -> String { ids.map(\.uuidString).sorted().joined(separator: "|") }

    static func hepsi() -> Set<String> {
        guard let url, let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(list)
    }

    static func ekle(_ ids: [UUID]) {
        guard let url else { return }
        var set = hepsi(); set.insert(anahtar(ids))
        if let data = try? JSONEncoder().encode(set.sorted()) { try? data.write(to: url, options: .atomic) }
    }

    /// Grup, ayrı tutulmak istenen bir kimlik kümesinin tamamını içeriyorsa gizlenir.
    nonisolated static func gizli(_ group: [UUID], bellek: Set<String>) -> Bool {
        bellek.contains(anahtar(group))
    }
}

private struct MergeGroupPreview: Identifiable {
    var id = UUID()
    var books: [Book]
    var loans: Int
    var copies: Int
    var reservations: Int
    var receipts: Int
    /// Ana kayıttan farklı demirbaş kodları; birleştirmede nüsha kaydına dönüşür.
    var accessionCodes: [String] = []
    var canMerge: Bool {
        Set(books.compactMap { ISBNFormatter.isValidISBN13($0.isbn ?? "") ? ISBNFormatter.normalize($0.isbn ?? "") : nil }).count <= 1
            && Set(books.compactMap(\.volume)).count <= 1
    }
}

struct DuplicateCleanerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CatalogBook.addedAt) private var books: [CatalogBook]

    /// Büyük kataloglarda tarama saniyeler sürebilir; arka planda hesaplanır.
    @State private var groups: [[CatalogBook]] = []
    @State private var isScanning = true
    @State private var mergeNotice: String?
    @State private var mergePreview: MergeGroupPreview?
    @State private var undoSummary: String?
    @State private var showingUndoConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if isScanning {
                    ProgressView("Mükerrerler taranıyor…")
                } else if groups.isEmpty {
                    ContentUnavailableView {
                        Label("Mükerrer kayıt yok", systemImage: "checkmark.seal")
                    } description: {
                        Text("Katalogda birbirine benzeyen kayıt bulunamadı.")
                    }
                } else {
                    List {
                        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                            Section {
                                ForEach(group) { book in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(book.title).font(.headline)
                                        if !book.author.isEmpty {
                                            Text(book.author)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text("ISBN: \(book.isbn ?? "—") • \(book.quantity ?? 1) adet")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Button {
                                    prepareMerge(group)
                                } label: {
                                    Label("Bu grubu birleştir (\(group.count) kayıt)", systemImage: "arrow.triangle.merge")
                                }
                                Button {
                                    AyriTutBellegi.ekle(group.map(\.id))
                                    groups.removeAll { AyriTutBellegi.anahtar($0.map(\.id)) == AyriTutBellegi.anahtar(group.map(\.id)) }
                                } label: {
                                    Label("Farklı baskı, bir daha gösterme", systemImage: "eye.slash")
                                }
                            }
                        }
                    }
                }
            }
            // Yönetim ve araç panelindeki adla aynı (tek ad kaynağı: KatalogAraci.duplicates)
            .navigationTitle(KatalogAraci.duplicates.aracBasligi ?? "")
            .sheet(item: $mergePreview) { preview in
                NavigationStack {
                    Form {
                        ForEach(preview.books) { book in
                            Section(book.title) {
                                LabeledContent("Yazar", value: book.author)
                                LabeledContent("ISBN", value: book.isbn ?? "Eksik")
                                LabeledContent("Yayınevi", value: book.publisher ?? "Eksik")
                                LabeledContent("Baskı / yıl", value: [book.edition, book.publicationYear].compactMap { $0 }.joined(separator: " · "))
                                LabeledContent("Cilt", value: book.volume.map(String.init) ?? "—")
                                LabeledContent("Adet", value: String(max(1, book.quantity ?? 1)))
                                LabeledContent("Dolap / raf", value: [book.cabinet, book.shelf].compactMap { $0 }.joined(separator: " / "))
                            }
                        }
                        Section("Birleştirme etkisi") {
                            Text("En dolu kayıt korunacak; adetler toplanacak ve kilitli alanlar korunacak.")
                            Text("\(preview.loans) ödünç, \(preview.copies) nüsha, \(preview.reservations) rezervasyon ve \(preview.receipts) tarama işlemi ana kayda bağlanacak.")
                            if !preview.accessionCodes.isEmpty {
                                Text("\(preview.accessionCodes.count) demirbaş kodu nüsha kaydına dönüştürülecek: \(preview.accessionCodes.joined(separator: ", "))")
                            }
                            Text("Sonraki bir işlem bu kayıtları değiştirmeden önce birleştirme geri alınabilir.")
                            if !preview.canMerge {
                                Text("Farklı ISBN veya ciltler bulundu. Bu kayıtları ayrı baskı olarak tutun.")
                                    .font(.headline)
                            }
                        }
                        Button("Birleştirmeyi Uygula") { applyMerge(preview) }
                            .disabled(!preview.canMerge)
                            .accessibilityIdentifier("merge.confirm")
                    }
                    .navigationTitle("Baskı ve ilişki önizlemesi")
                    .toolbar { Button("Vazgeç") { mergePreview = nil } }
                }
            }
            .confirmationDialog("Son kitap birleştirmesini geri al", isPresented: $showingUndoConfirmation, titleVisibility: .visible) {
                Button("Birleştirmeyi Geri Al", role: .destructive) { undoMerge() }
                Button("Vazgeç", role: .cancel) { }
            } message: { Text(undoSummary ?? "") }
            .alert("Birleştirme", isPresented: Binding(get: { mergeNotice != nil }, set: { if !$0 { mergeNotice = nil } })) { Button("Tamam", role: .cancel) { } } message: { Text(mergeNotice ?? "") }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Birleştirmeyi Geri Al", systemImage: "arrow.uturn.backward") { showingUndoConfirmation = true }
                        .disabled(undoSummary == nil)
                        .accessibilityIdentifier("merge.undo")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .task {
                refreshUndoSummary()
                await scanForDuplicates()
            }
        }
    }

    /// Mükerrer taramasını arka planda başlatır. Katalog büyükse (binlerce kayıt)
    /// bu işlem ana akışı kilitlemeden birkaç saniye sürebilir.
    private func scanForDuplicates() async {
        let currentBooks = (try? modelContext.fetch(FetchDescriptor<CatalogBook>())) ?? books.filter { !$0.isDeleted }
        let candidates = currentBooks.map {
            DuplicateCandidate(id: $0.id, isbn: $0.isbn ?? "", title: $0.title, author: $0.author)
        }
        let idGroups = await Task.detached(priority: .userInitiated) {
            Self.bucketedDuplicateGroups(candidates)
        }.value

        let byID = Dictionary(uniqueKeysWithValues: currentBooks.map { ($0.id, $0) })
        let ayrilan = AyriTutBellegi.hepsi()
        groups = idGroups.compactMap { ids in
            guard !AyriTutBellegi.gizli(ids, bellek: ayrilan) else { return nil }
            let resolved = ids.compactMap { byID[$0] }
            return resolved.count > 1 ? resolved : nil
        }
        isScanning = false
    }

    /// ISBN'e göre kesin eşleşme + başlığın ilk iki normalize karakterine göre
    /// KOVALARA ayrılmış bulanık eşleştirme. Tam O(n²) tarama yerine, yalnızca
    /// aynı kovadaki kayıtlar karşılaştırılır — 2.500+ kayıtlı katalogda saniyeler
    /// yerine anında sonuç verir.
    nonisolated private static func bucketedDuplicateGroups(
        _ candidates: [DuplicateCandidate]
    ) -> [[UUID]] {
        var used = Set<UUID>()
        var groups: [[UUID]] = []

        // 1) Kesin ISBN eşleşmesi
        var byISBN: [String: [DuplicateCandidate]] = [:]
        for candidate in candidates {
            let isbn = ISBNFormatter.normalize(candidate.isbn)
            guard !isbn.isEmpty else { continue }
            byISBN[isbn, default: []].append(candidate)
        }
        for group in byISBN.values where group.count > 1 {
            groups.append(group.map(\.id))
            group.forEach { used.insert($0.id) }
        }

        // 2) Kalanlar için başlığın ilk iki karakterine göre kovalama + bulanık eşleştirme
        let remaining = candidates.filter { !used.contains($0.id) }
        var buckets: [String: [DuplicateCandidate]] = [:]
        for candidate in remaining {
            let normalized = CatalogMatcher.normalize(candidate.title)
            let key = String(normalized.prefix(2))
            buckets[key, default: []].append(candidate)
        }

        for bucket in buckets.values {
            for (index, candidate) in bucket.enumerated() {
                guard !used.contains(candidate.id) else { continue }
                var group = [candidate]
                for other in bucket[(index + 1)...] where !used.contains(other.id) {
                    // Cilt/sınıf numarası farklı adlar ("Türkçe 5" / "Türkçe 6") mükerrer sayılmaz
                    let fuzzyMatch = CatalogMatcher.isSimilarTitle(candidate.title, other.title)
                        && (candidate.author.isEmpty || other.author.isEmpty
                            || CatalogMatcher.isSimilar(candidate.author, other.author))
                    if fuzzyMatch {
                        group.append(other)
                        used.insert(other.id)
                    }
                }
                if group.count > 1 {
                    groups.append(group.map(\.id))
                    used.insert(candidate.id)
                }
            }
        }
        return groups
    }

    private func prepareMerge(_ group: [CatalogBook]) {
        do {
            let ids = Set(group.map(\.id))
            let kodlar = Set(group.compactMap { $0.accessionCode?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            mergePreview = MergeGroupPreview(books: group.map(\.book),
                loans: try modelContext.fetch(FetchDescriptor<ActiveLoan>()).filter { ids.contains($0.bookID) }.count,
                copies: try modelContext.fetch(FetchDescriptor<BookCopy>()).filter { ids.contains($0.bookID) }.count,
                reservations: try modelContext.fetch(FetchDescriptor<Reservation>()).filter { ids.contains($0.bookID) }.count,
                receipts: try modelContext.fetch(FetchDescriptor<ScanWriteReceipt>()).filter { ids.contains($0.bookID) }.count,
                accessionCodes: kodlar.count > 1 ? kodlar.sorted().dropFirst().map { $0 } : [])
        } catch { mergeNotice = error.localizedDescription }
    }

    private func applyMerge(_ preview: MergeGroupPreview) {
        do {
            let current = try modelContext.fetch(FetchDescriptor<CatalogBook>())
            let group = current.filter { book in preview.books.contains { $0.id == book.id } }
            guard group.count == preview.books.count,
                  group.allSatisfy({ book in preview.books.first { $0.id == book.id } == book.book }) else {
                throw SchoolLibraryService.OperationError(message: "Önizlemeden sonra kayıt değişmiş; baskıları yeniden karşılaştırın.")
            }
            _ = try CatalogMaintenance.merge(group, context: modelContext)
            mergePreview = nil
            refreshUndoSummary()
            CatalogBackup.saveLight(try modelContext.fetch(FetchDescriptor<CatalogBook>()), force: true)
            mergeNotice = "Kayıtlar ve ilişkiler birleştirildi; son birleştirme geri alınabilir."
            Task { await scanForDuplicates() }
        } catch { mergePreview = nil; mergeNotice = error.localizedDescription }
    }

    private func refreshUndoSummary() {
        do { undoSummary = try CatalogMaintenance.undoSummary(context: modelContext) }
        catch { undoSummary = nil; mergeNotice = error.localizedDescription }
    }

    private func undoMerge() {
        do {
            let restored = try CatalogMaintenance.undoLastMerge(context: modelContext)
            refreshUndoSummary()
            mergeNotice = "\(restored) kitap kaydı ve önceki ilişkileri geri getirildi."
            CatalogBackup.saveLight(try modelContext.fetch(FetchDescriptor<CatalogBook>()), force: true)
            Task { await scanForDuplicates() }
        } catch { mergeNotice = error.localizedDescription }
    }
}

// MARK: - CSV içe aktarma

enum CSVImporter {
    /// CSV/TSV dosyasından kitap listesi üretir. İlk satır başlık olmalıdır;
    /// Türkçe ve İngilizce başlıklar tanınır. Ayraç (';' ',' veya sekme) otomatik saptanır.
    static func parse(_ data: Data) -> [Book] { parseDetayli(data).books }

    /// İçe aktarma sonucu: kitaplar + geçerli ISBN'e çevrilemeyen satırlar (satır no 1 tabanlı, başlık dahil).
    struct Sonuc {
        var books: [Book] = []
        var atlananISBN: [(satir: Int, ham: String)] = []
    }

    static func parseDetayli(_ data: Data) -> Sonuc {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1254)
            ?? String(data: data, encoding: .isoLatin1) else { return Sonuc() }

        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard let firstLine = normalized.split(separator: "\n").first else { return Sonuc() }

        let delimiter: Character
        let semicolons = firstLine.filter { $0 == ";" }.count
        let tabs = firstLine.filter { $0 == "\t" }.count
        let commas = firstLine.filter { $0 == "," }.count
        if tabs >= semicolons && tabs >= commas { delimiter = "\t" }
        else if semicolons >= commas { delimiter = ";" }
        else { delimiter = "," }

        let rows = parseRows(normalized, delimiter: delimiter)
        guard rows.count >= 2 else { return Sonuc() }

        let headers = rows[0].map { normalizeHeader($0) }
        let headerWords = headers.map { $0.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init) }
        /// Anahtarlar öncelik sırasıyla denenir: önce tam başlık, sonra sözcük düzeyinde eşleşme
        /// (başlık sözcüğü anahtarla başlar: "yili" ← "yil"). Alt dize aranmaz; yoksa "ad"
        /// anahtarı "Adet" ve "Yazar Adı" sütunlarını kitap adı sanar.
        func column(_ keys: [String], excluding: [String] = []) -> Int? {
            for key in keys {
                if let index = headers.firstIndex(of: key) { return index }
            }
            for key in keys {
                let keyWords = key.split(separator: " ").map(String.init)
                let match = headerWords.firstIndex { words in
                    guard words.count >= keyWords.count,
                          !words.contains(where: { word in excluding.contains { word.hasPrefix($0) } }) else { return false }
                    return (0...(words.count - keyWords.count)).contains { start in
                        zip(words[start...], keyWords).allSatisfy { word, key in key.count >= 3 ? word.hasPrefix(key) : word == key }
                    }
                }
                if let match { return match }
            }
            return nil
        }

        guard let titleColumn = column(["kitap adi", "kitabin adi", "eser adi", "yayin adi", "yayinin adi", "kitap", "eser", "baslik", "title", "adi", "ad"],
                                       excluding: ["yazar", "author", "yayin", "publisher"]) else {
            return Sonuc()
        }
        let authorColumn = column(["yazar", "author"])
        let publisherColumn = column(["yayinevi", "yayinci", "yayin evi", "publisher"])
        let isbnColumn = column(["isbn"])
        let yearColumn = column(["basim yili", "yayin yili", "yil", "year"])
        let editionColumn = column(["baski", "edition"])
        let pageColumn = column(["sayfa", "page"])
        let categoryColumn = column(["kategori", "category"])
        let languageColumn = column(["dil", "language"])
        let locationColumn = column(["oda", "konum", "location"])
        let cabinetColumn = column(["dolap", "cabinet"])
        let shelfColumn = column(["raf", "shelf"])
        let quantityColumn = column(["adet", "quantity"])
        let statusColumn = column(["okuma durumu", "durum", "status"])
        let ratingColumn = column(["puan", "rating"])
        let notesColumn = column(["not", "notes"])

        func value(_ row: [String], _ index: Int?) -> String {
            guard let index, index < row.count else { return "" }
            return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var books: [Book] = []
        var atlananISBN: [(satir: Int, ham: String)] = []
        for (index, row) in rows.enumerated().dropFirst() {
            let title = value(row, titleColumn)
            guard !title.isEmpty else { continue }

            let quantity = Int(value(row, quantityColumn)) ?? 1
            let rating = Int(value(row, ratingColumn)) ?? 0
            let hamISBN = value(row, isbnColumn)
            let isbn = ISBNFormatter.normalize(hamISBN)
            var notes = value(row, notesColumn)
            if isbn.isEmpty, !hamISBN.isEmpty {
                // Ham değer kaybolmaz: not alanına ve atlananISBN listesine yazılır.
                atlananISBN.append((satir: index + 1, ham: hamISBN))
                let oneri = ISBNOnarici.oneriler(hamISBN, enFazla: 1).first.map { " · Olası ISBN: \($0)" } ?? ""
                let ek = "Ham ISBN: \(hamISBN)\(oneri)"
                notes = notes.isEmpty ? ek : notes + "\n" + ek
            }

            books.append(
                Book(
                    title: title,
                    author: value(row, authorColumn),
                    publisher: emptyToNil(value(row, publisherColumn)),
                    isbn: isbn.isEmpty ? nil : isbn,
                    publicationYear: emptyToNil(value(row, yearColumn)),
                    edition: emptyToNil(value(row, editionColumn)),
                    pageCount: emptyToNil(value(row, pageColumn)),
                    notes: notes,
                    category: emptyToNil(value(row, categoryColumn)),
                    location: emptyToNil(value(row, locationColumn)),
                    language: emptyToNil(value(row, languageColumn)),
                    readingStatus: emptyToNil(value(row, statusColumn)) ?? "Okunacak",
                    rating: rating == 0 ? nil : rating,
                    quantity: max(1, quantity),
                    shelf: emptyToNil(value(row, shelfColumn)),
                    cabinet: emptyToNil(value(row, cabinetColumn))
                )
            )
        }
        return Sonuc(books: books, atlananISBN: atlananISBN)
    }

    /// Tırnaklı alanları destekleyen basit CSV ayrıştırıcı.
    private static func parseRows(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false
        var characters = text.makeIterator()

        while let character = characters.next() {
            if insideQuotes {
                if character == "\"" {
                    insideQuotes = false
                } else {
                    currentField.append(character)
                }
            } else {
                switch character {
                case "\"":
                    insideQuotes = true
                case delimiter:
                    currentRow.append(currentField)
                    currentField = ""
                case "\n":
                    currentRow.append(currentField)
                    currentField = ""
                    if currentRow.contains(where: { !$0.isEmpty }) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                default:
                    currentField.append(character)
                }
            }
        }
        currentRow.append(currentField)
        if currentRow.contains(where: { !$0.isEmpty }) {
            rows.append(currentRow)
        }
        return rows
    }

    private static func normalizeHeader(_ header: String) -> String {
        // Türkçe büyük I → "ı" tuzağına düşmemek için en_US kurallarıyla küçült,
        // aksanları kaldır, kalan noktasız ı'yı elle i'ye çevir.
        header
            .lowercased(with: Locale(identifier: "en_US"))
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "ı", with: "i")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func emptyToNil(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}

// MARK: - Otomatik yerel yedek

enum CatalogBackup {
    private static var lastSaved: Date = .distantPast

    /// Kataloğu (kapak görselleri hariç, hafif) JSON olarak Belgeler klasörüne yazar.
    /// Dosya, Dosyalar uygulamasından görülebilir: "KitapKatalogu-Yedek.json".
    /// Büyük kataloglarda diski yormamak için en fazla dakikada bir yazar;
    /// oturum sonlarında `force: true` ile hemen yazdırılır.
    static func save(_ books: [Book], force: Bool = false) {
        guard force || Date.now.timeIntervalSince(lastSaved) > 60 else { return }
        lastSaved = .now
        write(books)
    }

    /// Kapak verilerini hiç kopyalamadan yedek alır (büyük kataloglarda hızlı yol).
    /// 2.500+ kitapta kapaklarla birlikte kopyalamak onlarca MB'lık gereksiz iş demekti.
    static func saveLight(_ books: [CatalogBook], force: Bool = false) {
        guard force || Date.now.timeIntervalSince(lastSaved) > 60 else { return }
        lastSaved = .now

        let snapshot: [Book] = books.map { book in
            Book(
                id: book.id,
                title: book.title,
                author: book.author,
                publisher: book.publisher,
                isbn: book.isbn,
                publicationYear: book.publicationYear,
                edition: book.edition,
                pageCount: book.pageCount,
                notes: book.notes,
                category: book.category,
                location: book.location,
                language: book.language,
                readingStatus: book.readingStatus,
                rating: book.rating,
                quantity: book.quantity,
                shelf: book.shelf,
                cabinet: book.cabinet,
                coverData: nil,
                backCoverData: nil,
                imprintData: nil,
                // Demirbaş, düşüm ve ders kitabı bilgileri de yedeğe girer;
                // önceden eksikti ve geri yüklemede kayboluyordu.
                accessionCode: book.accessionCode,
                isWithdrawn: book.isWithdrawn,
                withdrawnReason: book.withdrawnReason,
                withdrawnDate: book.withdrawnDate,
                isTextbook: book.isTextbook,
                loanedTo: book.loanedTo,
                loanDueDate: book.loanDueDate,
                series: book.series,
                volume: book.volume,
                tags: book.tags,
                readingLevel: book.readingLevel,
                contentWarning: book.contentWarning,
                // Alan kilitleri/kaynakları yedekten geri yüklemede kaybolmasın
                fieldMetadata: book.fieldMetadata,
                addedAt: book.addedAt
            )
        }
        write(snapshot)

        // Spotlight araması: bu tek merkezden tüm kayıt/silme/toplu işlem
        // akışları kapsanır (ayrıca her fonksiyona tek tek dokunmaya gerek yok).
        SpotlightIndexer.reindex(books.map {
            SpotlightIndexer.Entry(
                id: $0.id.uuidString,
                title: $0.title,
                author: $0.author,
                isbn: $0.isbn ?? "",
                isWithdrawn: $0.isWithdrawn
            )
        })
    }

    /// Yedek dosyasından kitapları okur (Dosyalar'dan seçilen JSON ya da kendi yedeğimiz).
    static func load(from url: URL) -> [Book] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return decode(data)
    }

    /// Arka planda (arşiv açma) da çağrılır; ana aktöre bağlı değildir.
    nonisolated static func decode(_ data: Data) -> [Book] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let books = try? decoder.decode([Book].self, from: data) {
            return books
        }
        // Eski yedekler farklı tarih biçimi kullanmış olabilir
        let fallback = JSONDecoder()
        return (try? fallback.decode([Book].self, from: data)) ?? []
    }

    /// Uygulamanın kendi yazdığı son yedeğin adresi (varsa).
    static var localBackupURL: URL? {
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("KitapKatalogu-Yedek.json")
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private static var revizyon = 0

    private static func write(_ books: [Book]) {
        var lightBooks = books
        for index in lightBooks.indices {
            lightBooks[index].coverData = nil
        }
        revizyon += 1
        let no = revizyon
        guard let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("KitapKatalogu-Yedek.json") else { return }
        let yazilacak = lightBooks
        Task {
            switch await BackupWriter.shared.yaz(revizyon: no, books: yazilacak, url: url) {
            case .yazildi:
                if LibrarySyncStatus.shared.warning == uyariMetni { LibrarySyncStatus.shared.warning = nil }
            case .atlandi:
                break
            case .hata(let mesaj):
                AppLog.write("Katalog yedeği yazılamadı: \(mesaj)")
                if LibrarySyncStatus.shared.warning == nil { LibrarySyncStatus.shared.warning = uyariMetni }
            }
        }
    }

    private static let uyariMetni = "Katalog yedeği yazılamadı; depolama alanını kontrol edin."
}

/// Yedek yazımları tek aktörde sıralanır; eski revizyon yeni dosyanın üzerine yazılmaz.
actor BackupWriter {
    static let shared = BackupWriter()

    enum Sonuc: Equatable { case yazildi, atlandi, hata(String) }

    private var enSonRevizyon = 0

    func yaz(revizyon: Int, books: [Book], url: URL) -> Sonuc {
        guard revizyon > enSonRevizyon else { return .atlandi }
        enSonRevizyon = revizyon
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(books).write(to: url, options: .atomic)
            return .yazildi
        } catch { return .hata(error.localizedDescription) }
    }

}
