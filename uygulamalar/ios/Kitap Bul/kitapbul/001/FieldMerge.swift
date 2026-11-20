import SwiftUI
import SwiftData

/// Benzer Adları Birleştir: aynı yayınevi/yazar/kategori farklı yazımlarla
/// girilmişse ("İş Bankası" / "TÜRKİYE İŞ BANKASI KÜLTÜR YAYINLARI") tespit eder,
/// kullanıcı kanonik adı seçer, tüm kayıtlara tek seferde uygulanır.
struct FieldMergeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var books: [CatalogBook]

    private typealias Field = FieldMaintenanceField

    private struct Group: Identifiable {
        let id = UUID()
        var values: [String]
        var canonical: String
        let bookCount: Int
    }

    @State private var field: Field = .publisher
    @State private var groups: [Group] = []
    @State private var isScanning = false
    @State private var preview: Group?
    @State private var message: String?
    @State private var error: String?
    @State private var scanID = UUID()
    @State private var undoReceipt: FieldMaintenanceReceipt?
    @State private var reviewReceipts: [FieldMaintenanceReceipt] = []
    @State private var dismissedReviews = Set<UUID>()
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Alan", selection: $field) {
                    ForEach(Field.allCases) { Text($0.rawValue).tag($0) }
                }
                .disabled(isWorking)
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: field) { rescan() }

                if let message {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        if undoReceipt != nil { Button("Son alan bakımını geri al") { Task { await undo() } }.disabled(isWorking).frame(minHeight: 44).accessibilityIdentifier("fieldMerge.undo") }
                    }.padding().background(Color(.secondarySystemGroupedBackground))
                }
                ForEach(reviewReceipts.filter { !dismissedReviews.contains($0.id) }) { receipt in reviewCard(receipt) }
                if isScanning {
                    Spacer()
                    ProgressView("Taranıyor…")
                    Spacer()
                } else if groups.isEmpty {
                    ContentUnavailableView {
                        Label("Benzer ad bulunamadı", systemImage: "checkmark.seal")
                    } description: {
                        Text("\(field.rawValue) alanında birleştirilecek benzer yazım yok.")
                    }
                } else {
                    List {
                        ForEach($groups) { $group in
                            Section {
                                Picker("Kanonik ad", selection: $group.canonical) {
                                    ForEach(group.values, id: \.self) { Text($0).tag($0) }
                                }
                                Button {
                                    preview = group
                                } label: {
                                    Label(
                                        "\(group.values.count) yazımı \"\(group.canonical)\" olarak birleştir",
                                        systemImage: "arrow.triangle.merge"
                                    )
                                }
                            } header: {
                                Text("\(group.bookCount) kayıt · \(affectedCount(group)) değişecek")
                            }
                        }
                    }
                }
            }
            // Yönetim ve araç panelindeki adla aynı (tek ad kaynağı: KatalogAraci.fieldMerge)
            .navigationTitle(KatalogAraci.fieldMerge.aracBasligi ?? "")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }.disabled(isWorking)
                }
            }
            .task { loadUndo(); rescan() }
            .alert("İşlem tamamlanamadı", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Tamam", role: .cancel) { } } message: { Text(error ?? "") }
            .sheet(item: $preview) { group in
                NavigationStack {
                    List {
                        Section("Değişiklik") {
                            LabeledContent("Alan", value: field.rawValue)
                            LabeledContent("Yeni ad", value: group.canonical)
                            Text("\(affectedCount(group)) kayıt etkilenecek. Yalnız bu alan ve bu alanın kaynak/kilidi değişir.").font(.footnote)
                        }
                        Section("Önce → sonra") {
                            ForEach(books.filter { group.values.contains(fieldValue($0)) && fieldValue($0) != group.canonical }) { book in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(book.title).font(.headline)
                                    Text("\(fieldValue(book)) → \(group.canonical)").font(.subheadline).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .navigationTitle("Birleştirmeyi incele")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { preview = nil }.disabled(isWorking) }
                        ToolbarItem(placement: .confirmationAction) { Button("Uygula") { Task { await apply(group) } }.disabled(isWorking) }
                    }
                }
                .interactiveDismissDisabled(isWorking)
            }
            .interactiveDismissDisabled(isWorking)
        }
    }

    /// Yarım kalan işlemin kayıtları ne öncesine ne sonrasına uyuyor: etkilenen kitaplar ve bugünkü değerleri gösterilir.
    private func reviewCard(_ receipt: FieldMaintenanceReceipt) -> some View {
        let byID = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return VStack(alignment: .leading, spacing: 8) {
            Label("İncelenmesi gereken işlem", systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(.orange)
            Text("\(receipt.field.rawValue) birleştirmesi yarıda kalmış ve kayıtlar ne öncesine ne sonrasına uyuyor. \(receipt.createdAt.formatted(date: .abbreviated, time: .shortened)).")
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            ForEach(receipt.changes.prefix(5), id: \.bookID) { change in
                VStack(alignment: .leading, spacing: 2) {
                    Text(change.title).font(.subheadline.weight(.semibold))
                    Text("Önce: \(change.before ?? "boş") · Sonra: \(change.after ?? "boş") · Şimdi: \(byID[change.bookID].flatMap { value($0, field: receipt.field) } ?? "kayıt yok")")
                        .font(.footnote).fixedSize(horizontal: false, vertical: true)
                }
            }
            if receipt.changes.count > 5 { Text("… ve \(receipt.changes.count - 5) kitap daha").font(.footnote) }
            HStack {
                Button("Uygulanmış say") { Task { await resolve(receipt, applied: true) } }.frame(minHeight: 44).accessibilityIdentifier("fieldMerge.review.applied")
                Button("Uygulanmamış say") { Task { await resolve(receipt, applied: false) } }.frame(minHeight: 44).accessibilityIdentifier("fieldMerge.review.notApplied")
                Button("Kapat") { dismissedReviews.insert(receipt.id) }.frame(minHeight: 44)
            }.buttonStyle(.bordered).disabled(isWorking)
        }
        .padding().background(Color(.secondarySystemGroupedBackground))
    }

    private func resolve(_ receipt: FieldMaintenanceReceipt, applied: Bool) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        guard await YetkiDurumu.shared.yoneticiOl(neden: "Yarım kalan alan bakımı için karar vermek üzere kimliğinizi doğrulayın") else {
            error = YetkiDurumu.shared.hata ?? "Yönetici kimliği gerekir."; return
        }
        do {
            try FieldMaintenanceService.resolveReview(receiptID: receipt.id, applied: applied, context: modelContext)
            message = applied ? "İşlem uygulanmış sayıldı." : "İşlem uygulanmamış sayıldı."
            loadUndo()
        } catch { self.error = "Karar kaydedilemedi: " + error.localizedDescription }
    }

    private func affectedCount(_ group: Group) -> Int {
        books.filter { group.values.contains(fieldValue($0)) && fieldValue($0) != group.canonical }.count
    }

    private func fieldValue(_ book: CatalogBook) -> String { value(book, field: field) ?? "" }

    private func value(_ book: CatalogBook, field: Field) -> String? {
        FieldMaintenanceService.value(book, field: field)
    }

    private func loadUndo() {
        do {
            reviewReceipts = try FieldMaintenanceService.pendingReviews(context: modelContext)
            undoReceipt = try FieldMaintenanceService.latest(context: modelContext)
            if message == nil, let receipt = undoReceipt {
                message = "Son alan bakımı: \(receipt.changes.count) kaydın \(receipt.field.rawValue.lowercased()) alanı. \(receipt.createdAt.formatted(date: .abbreviated, time: .shortened))."
            }
        } catch { self.error = "Alan bakım günlüğü okunamadı; dosya korunuyor. " + error.localizedDescription }
    }

    private func rescan() {
        isScanning = true
        let requestID = UUID()
        scanID = requestID
        let requestedField = field
        let values = books.map { value($0, field: requestedField) ?? "" }.filter { !$0.isEmpty }
        Task { @MainActor in
            let found = await Task.detached(priority: .userInitiated) {
                Self.bucketedGroups(values)
            }.value
            guard scanID == requestID, field == requestedField else { return }
            groups = found.map { values in
                Group(values: values, canonical: values.max(by: { $0.count < $1.count }) ?? values[0],
                      bookCount: books.filter { values.contains(fieldValue($0)) }.count)
            }
            isScanning = false
        }
    }

    /// Benzersiz değerleri, ilk iki normalize karaktere göre kovalayıp kova içinde
    /// bulanık karşılaştırma yapar — alan değeri sayısı (genelde yüzler) küçük
    /// olduğundan bu, kitap sayısından bağımsız hızlı çalışır.
    nonisolated private static func bucketedGroups(_ values: [String]) -> [[String]] {
        let distinct = Array(Set(values))
        var used = Set<String>()
        var buckets: [String: [String]] = [:]
        for value in distinct {
            let key = String(CatalogMatcher.normalize(value).prefix(2))
            buckets[key, default: []].append(value)
        }

        var groups: [[String]] = []
        for bucket in buckets.values {
            for (index, value) in bucket.enumerated() {
                guard !used.contains(value) else { continue }
                var group = [value]
                for other in bucket[(index + 1)...] where !used.contains(other) {
                    if CatalogMatcher.isSimilar(value, other) {
                        group.append(other)
                        used.insert(other)
                    }
                }
                if group.count > 1 {
                    groups.append(group)
                    used.insert(value)
                }
            }
        }
        return groups
    }

    private func apply(_ group: Group) async {
        guard !isWorking else { return }
        let selectedField = field
        isWorking = true
        defer { isWorking = false }
        guard await YetkiDurumu.shared.yoneticiOl(neden: "Yazar, yayınevi veya kategori adlarını birleştirmek için kimliğinizi doğrulayın") else {
            error = YetkiDurumu.shared.hata ?? "Yönetici kimliği gerekir."; return
        }
        do {
            if let result = try FieldMaintenanceService.apply(field: selectedField, allowedValues: group.values,
                                                              canonical: group.canonical, context: modelContext) {
                undoReceipt = result.receipt
                message = "\(result.receipt.changes.count) kaydın \(selectedField.rawValue.lowercased()) alanı birleştirildi. Geri alma kaydı kalıcıdır."
                if let warning = result.warning { message = (message ?? "") + " " + warning }
            } else { message = "Seçili adlar artık değişiklik gerektirmiyor." }
            preview = nil
            CatalogBackup.saveLight(books, force: true)
            rescan()
        } catch { self.error = "Birleştirme kaydedilemedi: " + error.localizedDescription }
    }
    private func undo() async {
        guard !isWorking, let receipt = undoReceipt else { return }
        isWorking = true
        defer { isWorking = false }
        guard await YetkiDurumu.shared.yoneticiOl() else {
            error = YetkiDurumu.shared.hata ?? "Yönetici kimliği gerekir."; return
        }
        do {
            let result = try FieldMaintenanceService.undo(receiptID: receipt.id, context: modelContext)
            message = "\(result.receipt.changes.count) kaydın \(receipt.field.rawValue.lowercased()) alanı ve önceki alan kilidi geri alındı."
            if let warning = result.warning { message = (message ?? "") + " " + warning }
            undoReceipt = nil
            loadUndo()
            CatalogBackup.saveLight(books, force: true)
            rescan()
        } catch { self.error = "Geri alma kaydedilemedi: " + error.localizedDescription }
    }
}
