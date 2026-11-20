import SwiftUI

/// Alan değişiklikleri önce gösterilir; kaydetme hatası formu kapatmaz.
struct BulkFindReplaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let count: Int
    var books: [Book] = []
    let onApply: (_ field: BulkEditableField, _ find: String, _ replace: String) throws -> Void
    @State private var field: BulkEditableField = .publisher
    @State private var find = ""
    @State private var replace = ""
    @State private var error: String?
    @State private var discard = false
    @State private var preview = false
    private var dirty: Bool { !find.isEmpty || !replace.isEmpty }
    private var changes: [(id: UUID, title: String, before: String, after: String)] {
        books.compactMap { book in
            let old = field.value(in: book)
            let new = BulkTextReplace.replacing(find, with: replace, in: old)
            guard !find.isEmpty, new != old else { return nil }
            return (book.id, book.title, old, new)
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Alan", selection: $field) { ForEach(BulkEditableField.allCases) { Text($0.rawValue).tag($0) } }
                    TextField("Aranan metin", text: $find)
                    TextField("Yeni metin (boş = sil)", text: $replace)
                } footer: { Text("Seçili \(count) kitapta yalnız \(field.rawValue.lowercased()) alanı değiştirilir. Büyük/küçük harf duyarsızdır.") }
                if let error { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) } }
                Section {
                    if books.isEmpty { Text("İşlem seçili \(count) kayıt için uygulanacak.") }
                    else { LabeledContent("Değişecek kayıt", value: "\(changes.count) / \(count)") }
                    Button("Değişiklikleri incele", systemImage: "eye") { preview = true }.disabled(find.isEmpty || (!books.isEmpty && changes.isEmpty))
                }
            }
            .navigationTitle("Toplu bul-değiştir")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { if dirty { discard = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button("İncele") { preview = true }.disabled(find.isEmpty || (!books.isEmpty && changes.isEmpty)) }
            }
            .interactiveDismissDisabled(dirty)
            .confirmationDialog("Değişiklikler kaydedilmeden kapatılsın mı?", isPresented: $discard, titleVisibility: .visible) {
                Button("Kaydetmeden kapat", role: .destructive) { dismiss() }
                Button("Devam et", role: .cancel) { }
            }
            .sheet(isPresented: $preview) {
                NavigationStack {
                    List {
                        Section("Önce → sonra") {
                            if books.isEmpty { Text("\(field.rawValue): “\(find)” → “\(replace)”; seçili \(count) kayıt.") }
                            ForEach(changes, id: \.id) { change in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(change.title).font(.headline)
                                    Text(change.before).foregroundStyle(.secondary)
                                    Text(change.after.isEmpty ? "Alan boşaltılacak" : change.after).fontWeight(.semibold)
                                }.fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .navigationTitle("Değişikliği incele")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { preview = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Uygula") {
                                Task {
                                    guard await YetkiDurumu.shared.yoneticiOl() else { error = YetkiDurumu.shared.hata ?? "Yönetici kimliği gerekir."; preview = false; return }
                                    do { try onApply(field, find, replace); dismiss() }
                                    catch { self.error = error.localizedDescription; preview = false }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Toplu bul-değiştirin tek eşleştirme kuralı: önizleme ve uygulama aynı işlevi kullanır.
/// Büyük/küçük harf duyarsızdır; hem Türkçe harf eşlemesi ("iş" → "İş", "yayınları" → "YAYINLARI")
/// hem de düz Latin eşlemesi ("penguin" → "PENGUIN") geçerlidir: her adımda en erken başlayan eşleşme alınır.
nonisolated enum BulkTextReplace {
    static func replacing(_ find: String, with replacement: String, in text: String) -> String {
        guard !find.isEmpty else { return text }
        let turkish = Locale(identifier: "tr_TR")
        var result = "", cursor = text.startIndex
        while cursor < text.endIndex {
            let scope = cursor..<text.endIndex
            let candidates = [
                text.range(of: find, options: .caseInsensitive, range: scope, locale: turkish),
                text.range(of: find, options: .caseInsensitive, range: scope, locale: nil)
            ].compactMap { $0 }.filter { !$0.isEmpty }
            guard let range = candidates.min(by: { $0.lowerBound < $1.lowerBound }) else { break }
            result += text[cursor..<range.lowerBound]
            result += replacement
            cursor = range.upperBound
        }
        return result + text[cursor...]
    }
}

enum BulkEditableField: String, CaseIterable, Identifiable {
    case title = "Kitap Adı", author = "Yazar", publisher = "Yayınevi", category = "Kategori", notes = "Notlar"
    var id: Self { self }
    func value(in book: Book) -> String {
        switch self {
        case .title: book.title
        case .author: book.author
        case .publisher: book.publisher ?? ""
        case .category: book.category ?? ""
        case .notes: book.notes
        }
    }
}
