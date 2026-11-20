import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Demirbaş defterinde her satır kendi kalıcı kimliği olan fiziksel nüshadır.
struct AccessionRegisterView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var copies: [BookCopy]
    @Query private var loans: [ActiveLoan]
    let books: [CatalogBook]
    @State private var isExportingCSV = false
    @State private var isExportingPDF = false
    @State private var isPreparing = false
    @State private var csvData = Data()
    @State private var pdfData = Data()
    @State private var limit = 100
    @State private var statusFilter = ""
    @State private var search = ""
    @State private var cabinetFilter = ""
    @State private var shelfFilter = ""
    @State private var resultMessage: String?

    private var locationFilter: LibraryReportFilter { LibraryReportFilter(cabinet: cabinetFilter, shelf: shelfFilter) }
    private var baseRows: [CopyRegisterEngine.Row] { CopyRegisterEngine.rows(books: books, copies: copies, loans: loans) }
    private var allRows: [CopyRegisterEngine.Row] { CopyRegisterEngine.rows(books: books, copies: copies, loans: loans, filter: locationFilter) }
    private var cabinets: [String] { Array(Set(baseRows.map(\.cabinet) + books.compactMap(\.cabinet)).filter { !$0.isEmpty }).sorted() }
    private var shelves: [String] { Array(Set(baseRows.map(\.shelf) + books.compactMap(\.shelf)).filter { !$0.isEmpty }).sorted() }
    private var rows: [CopyRegisterEngine.Row] {
        let query = CatalogMatcher.normalize(search)
        return allRows.filter { row in
            (statusFilter.isEmpty || row.status == statusFilter)
                && (query.isEmpty || CatalogMatcher.normalize([row.code, row.title, row.author, row.id.uuidString, row.cabinet, row.shelf, row.place].joined(separator: " ")).contains(query))
        }
    }
    private var untracked: [(book: CatalogBook, count: Int)] {
        guard statusFilter.isEmpty else { return [] }
        let term = CatalogMatcher.normalize(search)
        return CopyRegisterEngine.untracked(books: books, copies: copies, filter: locationFilter).filter {
            term.isEmpty || CatalogMatcher.normalize([$0.book.title, $0.book.author, $0.book.id.uuidString, $0.book.cabinet ?? "", $0.book.shelf ?? ""].joined(separator: " ")).contains(term)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Kimliği kayıtlı nüsha", value: "\(allRows.count)")
                    LabeledContent("Demirbaş kodu eksik nüsha", value: "\(allRows.filter { $0.code.isEmpty }.count)")
                    LabeledContent("Henüz tekil nüshaya dönüştürülmemiş adet", value: "\(untracked.reduce(0) { $0 + $1.count })")
                    Picker("Dolap", selection: $cabinetFilter) {
                        Text("Tüm dolaplar").tag(""); ForEach(cabinets, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Raf", selection: $shelfFilter) {
                        Text("Tüm raflar").tag(""); ForEach(shelves, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Nüsha durumu", selection: $statusFilter) {
                        Text("Tüm durumlar").tag("")
                        ForEach(Array(Set(allRows.map(\.status))).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    Text("\(rows.count) nüsha gösteriliyor; dışa aktarım bu arama ve durum kapsamını kullanır.")
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    if isPreparing { ProgressView("Defter hazırlanıyor…") }
                    if let resultMessage { Text(resultMessage).fixedSize(horizontal: false, vertical: true) }
                } header: { Text("Nüsha kapsamı").foregroundStyle(.primary) }
                Section {
                    ForEach(rows.prefix(limit)) { row in
                        if let book = books.first(where: { $0.id == row.bookID }) {
                            NavigationLink { KitapDetaySayfasi(kitapID: book.id) } label: { copyRow(row) }
                        } else { copyRow(row) }
                    }
                    if rows.count > limit { Button("Sonraki 100 nüshayı göster") { limit += 100 }.frame(minHeight: 44) }
                    if rows.isEmpty { Text("Bu kapsamda kayıtlı nüsha yok.") }
                } header: { Text("Gerçek nüsha kayıtları").foregroundStyle(.primary) }
                if !untracked.isEmpty {
                    Section {
                        ForEach(untracked, id: \.book.id) { item in
                            NavigationLink { KitapDetaySayfasi(kitapID: item.book.id) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.book.title)
                                    Text("\(item.count) adet için nüsha kimliği henüz oluşturulmamış").font(.subheadline)
                                }.foregroundStyle(.primary)
                            }
                        }
                    } header: { Text("Nüsha kimliği bekleyen adetler").foregroundStyle(.primary) } footer: {
                        Text("Bu adetler toplam stokta korunur. Eser ayrıntısında fiziksel nüsha kaydı oluşturulunca deftere kendi kimliğiyle girer; burada sahte nüsha kimliği üretilmez.")
                    }
                }
            }
            .searchable(text: $search, prompt: "Demirbaş, kitap, konum veya nüsha kimliği")
            .navigationTitle("Demirbaş Defteri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button { prepare(then: .csv) } label: { Label("CSV", systemImage: "tablecells") }.disabled(isPreparing)
                    Button { prepare(then: .pdf) } label: { Label("PDF", systemImage: "doc.richtext") }.disabled(isPreparing)
                }
            }
            .onChange(of: search) { _, _ in limit = 100 }
            .onChange(of: statusFilter) { _, _ in limit = 100 }
            .onChange(of: cabinetFilter) { _, _ in limit = 100 }
            .onChange(of: shelfFilter) { _, _ in limit = 100 }
            .fileExporter(isPresented: $isExportingCSV,
                document: InventoryReportDocument(text: String(data: csvData, encoding: .utf8) ?? ""),
                contentType: .commaSeparatedText, defaultFilename: "Demirbas-Nusha-Defteri") { result in
                    exportFinished(result)
                }
            .fileExporter(isPresented: $isExportingPDF, document: PDFDocumentFile(data: pdfData),
                contentType: .pdf, defaultFilename: "Demirbas-Nusha-Defteri") { result in
                    exportFinished(result)
                }
        }
    }

    private func copyRow(_ row: CopyRegisterEngine.Row) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(row.code.isEmpty ? "Demirbaş kodu eksik" : row.code).font(.subheadline.monospaced().weight(.semibold))
            Text(row.title).font(.body.weight(.semibold))
            Text(row.author).font(.subheadline)
            Text("\(row.status) · \(row.condition) · \(row.place.isEmpty ? CatalogBook.yerAtanmamis : row.place)")
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            if !row.activeLoans.isEmpty { Text("Ödünç: " + row.activeLoans).font(.subheadline).fixedSize(horizontal: false, vertical: true) }
            Text("Nüsha: " + row.id.uuidString).font(.caption.monospaced()).fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(.primary).padding(.vertical, 3)
    }

    private enum ExportKind { case csv, pdf }
    private func prepare(then kind: ExportKind) {
        isPreparing = true; resultMessage = nil
        let snapshot = rows
        let pending = untracked.map { ($0.book.id.uuidString, $0.book.title, $0.count) }
        let scope = "Arama: \(search.isEmpty ? "Tümü" : search) · Durum: \(statusFilter.isEmpty ? "Tümü" : statusFilter) · Dolap: \(cabinetFilter.isEmpty ? "Tümü" : cabinetFilter) / Raf: \(shelfFilter.isEmpty ? "Tümü" : shelfFilter)"
        Task { @MainActor in
            defer { isPreparing = false }
            switch kind {
            case .csv:
                csvData = await Task.detached(priority: .userInitiated) {
                    ReportTableExporter.csv([CopyRegisterEngine.headers] + snapshot.map(\.fields))
                }.value
                isExportingCSV = true
            case .pdf:
                pdfData = await Task.detached(priority: .userInitiated) {
                    Self.buildPDF(snapshot, pending: pending, scope: scope)
                }.value
                if pdfData.isEmpty { resultMessage = "Defter hazırlanamadı; tekrar deneyin." }
                else { isExportingPDF = true }
            }
        }
    }

    nonisolated private static func buildPDF(_ rows: [CopyRegisterEngine.Row], pending: [(String, String, Int)], scope: String) -> Data {
        var sections = rows.map { row in
            PDFReportBuilder.Section(title: row.code.isEmpty ? "Demirbaş kodu eksik nüsha" : "Demirbaş: " + row.code, rows: [
                ("Nüsha kimliği", row.id.uuidString), ("Eser kimliği", row.bookID.uuidString),
                ("Kitap", row.title), ("Yazar / ISBN", row.author + " / " + row.isbn),
                ("Durum / fiziksel durum", row.status + " / " + row.condition),
                ("Dolap / raf", row.cabinet + " / " + row.shelf), ("Etkin konum", row.place),
                ("Etkin ödünç", row.activeLoans.isEmpty ? "Yok" : row.activeLoans),
                ("Eklenme", row.addedAt.formatted(date: .numeric, time: .omitted))])
        }
        if !pending.isEmpty {
            sections.append(PDFReportBuilder.Section(title: "Nüsha kimliği oluşturulmamış adetler (stokta korunur)",
                rows: pending.map { ($0.1 + " · Eser " + $0.0, "\($0.2) adet") }))
        }
        return PDFReportBuilder.build(title: "DEMİRBAŞ NÜSHA DEFTERİ", subtitle: scope + " · \(rows.count) gerçek nüsha",
            sections: sections, signatures: ["Kütüphane Sorumlusu"])
    }
    private func exportFinished(_ result: Result<URL, Error>) {
        switch result {
        case .success: resultMessage = "Demirbaş defteri dışa aktarıldı."
        case .failure(let error): resultMessage = "Dışa aktarım tamamlanamadı: \(error.localizedDescription)"
        }
    }
}
