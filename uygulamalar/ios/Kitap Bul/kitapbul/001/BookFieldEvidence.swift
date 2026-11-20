import SwiftUI
import SwiftData

nonisolated struct BookFieldEvidence: Codable, Sendable, Equatable {
    var source: String
    var confidence: Double? = nil
    var isLocked: Bool = false
}

nonisolated enum BookFieldMetadata {
    static let fields = ["title", "author", "isbn", "publisher", "publicationYear", "edition", "pageCount", "category", "language", "notes", "cabinet", "shelf", "series", "volume", "tags", "readingLevel", "contentWarning", "coverData"]
    static let labels = ["title": "Kitap adı", "author": "Yazar", "isbn": "ISBN", "publisher": "Yayınevi", "publicationYear": "Yıl", "edition": "Baskı", "pageCount": "Sayfa", "category": "Kategori", "language": "Dil", "notes": "Not / özet", "cabinet": "Dolap", "shelf": "Raf", "series": "Seri", "volume": "Cilt", "tags": "Etiketler", "readingLevel": "Okuma düzeyi", "contentWarning": "İçerik uyarısı", "coverData": "Kapak"]
    static func decode(_ raw: String?) -> [String: BookFieldEvidence] {
        guard let raw, !raw.isEmpty else { return [:] }
        if let data = raw.data(using: .utf8), let values = try? JSONDecoder().decode([String: BookFieldEvidence].self, from: data) { return values }
        // Hasarlı kaynak bilgisi, otomatik tamamlamada korunan alanları sessizce açamaz.
        return Dictionary(uniqueKeysWithValues: fields.map { ($0, BookFieldEvidence(source: "unknown", isLocked: true)) })
    }
    static func encode(_ values: [String: BookFieldEvidence]) -> String? {
        (try? JSONEncoder().encode(values)).flatMap { String(data: $0, encoding: .utf8) }
    }
    static func isLocked(_ field: String, metadata: String?) -> Bool {
        guard let metadata, !metadata.isEmpty else { return false }
        guard let data = metadata.data(using: .utf8), let values = try? JSONDecoder().decode([String: BookFieldEvidence].self, from: data) else { return true }
        return values[field]?.isLocked == true
    }
    @MainActor static func isLocked(_ field: String, on book: CatalogBook) -> Bool {
        isLocked(field, metadata: book.fieldMetadata)
    }
    static func sourceName(_ value: String) -> String {
        ["manual": "Elle / kullanıcı", "barcode": "Doğrulanmış barkod", "vision": "Cihazda OCR", "gemini": "Yapay zekâ", "api": "Kitap veri servisi", "voice": "Sesli kayıt", "unknown": "Eski kayıt; kaynak bilinmiyor"][value] ?? "Kaynak belirtilmemiş"
    }
    static func value(_ field: String, in book: Book) -> String {
        switch field {
        case "title": book.title
        case "author": book.author
        case "isbn": book.isbn ?? ""
        case "publisher": book.publisher ?? ""
        case "publicationYear": book.publicationYear ?? ""
        case "edition": book.edition ?? ""
        case "pageCount": book.pageCount ?? ""
        case "category": book.category ?? ""
        case "language": book.language ?? ""
        case "notes": book.notes
        case "cabinet": book.cabinet ?? ""
        case "shelf": book.shelf ?? ""
        case "series": book.series ?? ""
        case "volume": book.volume.map(String.init) ?? ""
        case "tags": book.tags ?? ""
        case "readingLevel": book.readingLevel ?? ""
        case "contentWarning": book.contentWarning ?? ""
        case "coverData": book.coverData == nil ? "" : "Kapak görseli"
        default: ""
        }
    }
    /// Mevcut alan kanıtları korunur; değişen elle girişler kullanıcı kilidi alır.
    static func stampChanges(before: Book?, after: Book, source: String) -> Book {
        var result = after
        let prior = decode(before?.fieldMetadata)
        var metadata = prior
        let incoming = decode(after.fieldMetadata)
        for (field, evidence) in incoming { metadata[field] = evidence }
        for field in fields {
            let changed: Bool
            if field == "coverData" { changed = before.map { $0.coverData != after.coverData } ?? (after.coverData != nil) }
            else { changed = before.map { value(field, in: $0) != value(field, in: after) } ?? !value(field, in: after).isEmpty }
            if changed, incoming[field] == nil || incoming[field] == prior[field] {
                metadata[field] = BookFieldEvidence(source: source, isLocked: source == "manual")
            }
        }
        result.fieldMetadata = encode(metadata)
        return result
    }
}

struct BookFieldEvidencePanel: View {
    let book: CatalogBook
    @Environment(\.modelContext) private var context
    @State private var error: String?
    private var metadata: [String: BookFieldEvidence] { BookFieldMetadata.decode(book.fieldMetadata) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kilitli alanlar otomatik tamamlamada korunur. Güven puanı, modelin tahminidir.").font(.footnote).foregroundStyle(.secondary)
            if let raw = book.fieldMetadata, !raw.isEmpty,
               raw.data(using: .utf8).flatMap({ try? JSONDecoder().decode([String: BookFieldEvidence].self, from: $0) }) == nil {
                Text("Kaynak bilgisi okunamadı. Alanlar güvenle kilitlendi; gerekli alanı tek tek açabilirsiniz.").font(.footnote).foregroundStyle(.orange)
            }
            ForEach(BookFieldMetadata.fields, id: \.self) { field in
                let evidence = metadata[field] ?? .init(source: "unknown")
                Toggle(isOn: Binding(get: { metadata[field]?.isLocked == true }, set: { setLock($0, field: field) })) {
                    VStack(alignment: .leading) {
                        Text(BookFieldMetadata.labels[field] ?? field)
                        Text(BookFieldMetadata.sourceName(evidence.source) + (evidence.confidence.map { " · Tahminî güven \(Int(min(1, max(0, $0)) * 100))%" } ?? ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(!YetkiDurumu.shared.yonetici)
            }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
    }
    private func setLock(_ locked: Bool, field: String) {
        guard YetkiDurumu.shared.yonetici else { return }
        var values = metadata
        var evidence = values[field] ?? .init(source: "manual")
        evidence.isLocked = locked; values[field] = evidence
        let previous = book.fieldMetadata
        book.fieldMetadata = BookFieldMetadata.encode(values)
        do { try context.save(); error = nil }
        catch { book.fieldMetadata = previous; self.error = "Alan kilidi kaydedilemedi: \(error.localizedDescription)" }
    }
}
