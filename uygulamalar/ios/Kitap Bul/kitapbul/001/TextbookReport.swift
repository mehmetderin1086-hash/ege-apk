import Foundation
import SwiftUI
import SwiftData

nonisolated struct TextbookReportFilter: Equatable {
    var start: Date = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now
    var end: Date = .now
    var period = ""
    var className = ""
    var query = ""
}

/// Teslim ve iade yalnız aynı ödünç kimliğinde eşleşir. Eser/kişi adı eşleştirme anahtarı değildir.
enum TextbookReportEngine {
    struct Row: Identifiable {
        let id: String
        let loanID: UUID?
        let bookID: UUID
        let title: String
        let person: String
        let studentNumber: String
        let className: String
        let period: String
        let copy: String
        let deliveredAt: Date?
        let dueDate: Date?
        let returnedAt: Date?
        let condition: String
        let status: String
        let note: String

        var fields: [String] {
            [period, className, studentNumber, person, title, copy, loanID?.uuidString ?? "Kimlik yok",
             date(deliveredAt), date(dueDate), date(returnedAt), condition, status, note]
        }
        private func date(_ value: Date?) -> String {
            value?.formatted(date: .numeric, time: .omitted) ?? ""
        }
    }

    struct Snapshot {
        let filter: TextbookReportFilter
        let rows: [Row]
        let generatedAt: Date
        var table: [[String]] { [headers] + rows.map(\.fields) }
        var sections: [PDFReportBuilder.Section] {
            let summary: [(String, String)] = [
                ("Tarih aralığı", "\(filter.start.formatted(date: .numeric, time: .omitted)) – \(filter.end.formatted(date: .numeric, time: .omitted))"),
                ("Dağıtım dönemi", filter.period.isEmpty ? "Tüm dönemler" : filter.period),
                ("Sınıf", filter.className.isEmpty ? "Tüm sınıflar" : filter.className),
                ("Arama", filter.query.isEmpty ? "Tüm öğrenciler ve kitaplar" : filter.query),
                ("Teslim / iade / henüz iade edilmedi / kayıp", "\(rows.filter { $0.deliveredAt != nil }.count) / \(rows.filter { $0.status == "İade alındı" }.count) / \(rows.filter { $0.status == "Henüz iade edilmedi" }.count) / \(rows.filter { $0.status == "Kayıp bildirildi" }.count)"),
                ("Yıpranmış / onarım gerekli iade", "\(rows.filter { $0.status == "İade alındı" && ["Yıpranmış", "Onarım gerekli"].contains($0.condition) }.count)"),
                ("Eşleştirme gerektiren kayıt", "\(rows.filter { $0.status == "Eşleştirme gerekli" }.count)"),
                ("Kapsam", "Aralıkta teslim/iade/kayıp hareketi olan kayıtlar ile bitiş tarihinde henüz iade edilmemiş teslimler. Durum bitiş tarihine göredir; teslim sınıfı ve okul numarası tarihsel kayıttan gelir. Kimliksiz hareketler birleştirilmez.")]
            return [PDFReportBuilder.Section(title: "Ders Kitabı Çizelgesi Kapsamı", rows: summary)] + rows.enumerated().map { index, row in
                PDFReportBuilder.Section(title: "\(index + 1). \(row.person) · \(row.title)", rows: zip(headers, row.fields).map { ($0.0, $0.1) })
            }
        }
    }

    static let headers = ["Dağıtım dönemi", "Teslim sınıfı", "Okul numarası", "Öğrenci / okur", "Kitap",
        "Nüsha / demirbaş", "Ödünç kimliği", "Teslim tarihi", "Son teslim tarihi", "İade tarihi", "İade durumu", "İşlem durumu", "Doğrulama notu"]

    static func snapshot(events: [LoanEvent], loans: [ActiveLoan], copies: [BookCopy], filter: TextbookReportFilter, now: Date = .now) -> Snapshot {
        let history = events.filter { $0.loanKind == "textbook" && $0.date <= filter.end }
        let grouped = Dictionary(grouping: history.filter { $0.loanID != nil }, by: { $0.loanID! })
        let active = Dictionary(loans.filter { $0.kind == "textbook" && $0.loanedAt <= filter.end }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let accession = Dictionary(copies.map { ($0.id, $0.accessionCode.isEmpty ? $0.id.uuidString : $0.accessionCode) }, uniquingKeysWith: { a, _ in a })
        var rows: [Row] = []
        for id in Set(grouped.keys).union(active.keys) {
            let movements = (grouped[id] ?? []).sorted(by: movementBefore)
            let delivery = movements.first { $0.kind == .lent }
            let correction = movements.last { $0.kind == .identityCorrected }
            let terminal = movements.last { $0.kind == .returned || $0.kind == .lost }
            let live = active[id]
            guard let anchor = correction ?? delivery ?? movements.first else {
                if let live {
                    rows.append(row(live, accession: accession, note: "Teslim hareketi bulunamadı; etkin ödünç kaydı kullanıldı."))
                }
                continue
            }
            let bookIDs = Set(movements.map(\.bookID)).union(live.map { [$0.bookID] } ?? [])
            let validLink = bookIDs.count == 1 && (delivery != nil || live != nil) && validChain(movements, loanID: id)
            let deliveredAt = delivery?.date ?? live?.loanedAt
            let within = movements.contains { $0.date >= filter.start && ($0.kind == .lent || $0.kind == .returned || $0.kind == .lost) }
            guard within || (terminal == nil && deliveredAt != nil) else { continue }
            let copyID = correction?.copyID ?? delivery?.copyID ?? live?.copyID ?? terminal?.copyID
            let status = !validLink ? "Eşleştirme gerekli" : terminal?.kind == .returned ? "İade alındı" : terminal?.kind == .lost ? "Kayıp bildirildi" : "Henüz iade edilmedi"
            rows.append(Row(id: id.uuidString, loanID: id, bookID: anchor.bookID, title: delivery?.bookTitle ?? anchor.bookTitle,
                person: anchor.person, studentNumber: delivery?.studentNumberSnapshot ?? anchor.studentNumberSnapshot ?? "", className: delivery?.classSnapshot ?? anchor.classSnapshot ?? "",
                period: delivery?.periodSnapshot ?? anchor.periodSnapshot ?? live?.periodSnapshot ?? "", copy: copyID.map { accession[$0] ?? $0.uuidString } ?? "Tekil nüsha belirtilmemiş",
                deliveredAt: deliveredAt, dueDate: movements.last(where: { $0.dueDate != nil })?.dueDate ?? live?.dueDate,
                returnedAt: validLink && terminal?.kind == .returned ? terminal?.date : nil, condition: validLink && terminal?.kind == .returned ? terminal?.returnedCondition ?? "Belirtilmemiş" : "",
                status: status, note: validLink ? (delivery == nil ? "Teslim hareketi bulunamadı; etkin ödünç kaydı kullanıldı." : "") : "Ödünç kimliği eksik veya birden çok eserle çelişiyor; kayıt doğrulanmalı."))
        }
        for event in history where event.loanID == nil && event.date >= filter.start && [.lent, .returned, .lost].contains(event.kind) {
            rows.append(Row(id: "event:" + event.id.uuidString, loanID: nil, bookID: event.bookID, title: event.bookTitle, person: event.person,
                studentNumber: event.studentNumberSnapshot ?? "", className: event.classSnapshot ?? "", period: event.periodSnapshot ?? "",
                copy: event.copyID.map { accession[$0] ?? $0.uuidString } ?? "Tekil nüsha belirtilmemiş", deliveredAt: event.kind == .lent ? event.date : nil,
                dueDate: event.dueDate, returnedAt: event.kind == .returned ? event.date : nil, condition: event.returnedCondition ?? "", status: "Eşleştirme gerekli",
                note: "Eski hareket: \(event.kind.rawValue). Ödünç kimliği yok; başka teslim/iade ile eşleştirilmedi."))
        }
        let query = CatalogMatcher.normalize(filter.query)
        rows = rows.filter { row in
            (filter.period.isEmpty || row.period == filter.period) && (filter.className.isEmpty || row.className == filter.className)
                && (query.isEmpty || CatalogMatcher.normalize([row.person, row.studentNumber, row.title, row.copy].joined(separator: " ")).contains(query))
        }.sorted { a, b in
            let keyA = [a.period, a.className, a.studentNumber, a.person, a.title, a.id].joined(separator: "|")
            let keyB = [b.period, b.className, b.studentNumber, b.person, b.title, b.id].joined(separator: "|")
            return keyA.localizedStandardCompare(keyB) == .orderedAscending
        }
        return Snapshot(filter: filter, rows: filter.start > filter.end ? [] : rows, generatedAt: now)
    }

    nonisolated private static func movementBefore(_ a: LoanEvent, _ b: LoanEvent) -> Bool {
        if a.date != b.date { return a.date < b.date }
        func order(_ kind: LoanEvent.Kind) -> Int {
            switch kind { case .lent: 0; case .identityCorrected: 1; case .extended: 2; case .returned, .lost: 3 }
        }
        if order(a.kind) != order(b.kind) { return order(a.kind) < order(b.kind) }
        return a.id.uuidString < b.id.uuidString
    }

    /// Bir loanID'nin her hareketi aynı kişi/nüsha zincirini taşır. Yalnız kaydedilmiş
    /// kimlik düzeltmesi kişi veya nüsha geçişine izin verir; isim benzerliği eşleştirme yapmaz.
    private static func validChain(_ events: [LoanEvent], loanID: UUID) -> Bool {
        guard events.filter({ $0.kind == .lent }).count <= 1,
              events.filter({ $0.kind == .returned || $0.kind == .lost }).count <= 1,
              Set(events.map(\.id)).count == events.count,
              events.allSatisfy({ $0.studentID == nil || $0.memberID == nil }) else { return false }
        guard var current = events.first else { return true }
        var ended = false
        func identityMatches(_ event: LoanEvent, _ other: LoanEvent) -> Bool {
            if event.studentID != nil || other.studentID != nil || event.memberID != nil || other.memberID != nil {
                return event.studentID == other.studentID && event.memberID == other.memberID
            }
            return event.person == other.person && event.classSnapshot == other.classSnapshot
        }
        for (index, event) in events.enumerated() {
            guard !ended else { return false }
            if event.kind == .identityCorrected {
                guard event.studentID != nil || event.memberID != nil,
                      let data = event.identityCorrectionBefore,
                      let before = try? JSONDecoder().decode(ArchivedLoan.self, from: data),
                      before.id == loanID, before.bookID == event.bookID,
                      before.studentID == nil || before.memberID == nil else { return false }
                if index > 0 {
                    guard before.studentID == current.studentID, before.memberID == current.memberID,
                          before.copyID == current.copyID,
                          before.studentID != nil || before.memberID != nil || before.studentName == current.person else { return false }
                }
                current = event
            } else if index > 0 {
                guard identityMatches(event, current), event.copyID == current.copyID,
                      event.kind != .lent else { return false }
                current = event
            }
            if event.kind == .returned || event.kind == .lost { ended = true }
        }
        return true
    }

    private static func row(_ loan: ActiveLoan, accession: [UUID: String], note: String) -> Row {
        Row(id: loan.id.uuidString, loanID: loan.id, bookID: loan.bookID, title: loan.bookTitleSnapshot, person: loan.studentName,
            studentNumber: loan.studentNumberSnapshot ?? "", className: loan.studentClass, period: loan.periodSnapshot ?? "",
            copy: loan.copyID.map { accession[$0] ?? $0.uuidString } ?? "Tekil nüsha belirtilmemiş", deliveredAt: loan.loanedAt, dueDate: loan.dueDate,
            returnedAt: nil, condition: "", status: "Henüz iade edilmedi", note: note)
    }
}

struct TextbookReportView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("schoolName") private var schoolName = ""
    @State private var filter = TextbookReportFilter()
    @State private var periods: [String] = []
    @State private var classes: [String] = []
    @State private var snapshot: TextbookReportEngine.Snapshot?
    @State private var pdfURL: URL?
    @State private var csvURL: URL?
    @State private var excelURL: URL?
    @State private var error: String?

    var body: some View {
        Form {
            Section("Çizelge kapsamı") {
                DatePicker("Başlangıç", selection: $filter.start, displayedComponents: .date)
                DatePicker("Bitiş", selection: $filter.end, displayedComponents: .date)
                Picker("Dağıtım dönemi", selection: $filter.period) {
                    Text("Tüm dönemler").tag(""); ForEach(periods, id: \.self) { Text($0).tag($0) }
                }
                Picker("Teslim sınıfı", selection: $filter.className) {
                    Text("Tüm sınıflar").tag(""); ForEach(classes, id: \.self) { Text($0).tag($0) }
                }
                TextField("Ad, okul numarası, kitap veya demirbaş ara", text: $filter.query)
                TextField("Okul adı", text: $schoolName)
            }
            Section {
                Button("Çizelgeyi Hazırla", action: prepare).frame(minHeight: 44).disabled(filter.start > filter.end)
                if let pdfURL { ShareLink(item: pdfURL) { Label("PDF paylaş / yazdır", systemImage: "printer") } }
                if let csvURL { ShareLink(item: csvURL) { Label("CSV paylaş", systemImage: "tablecells") } }
                if let excelURL { ShareLink(item: excelURL) { Label("Excel paylaş", systemImage: "tablecells") } }
                if filter.start > filter.end { Text("Başlangıç tarihi bitişten sonra olamaz.").foregroundStyle(.red) }
                if let error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            } footer: {
                Text("Önizleme ve üç dosya aynı kayıtlarla hazırlanır. İade edilmemiş ve kayıp kayıtlar ayrıdır. Eski kimliksiz hareketlerde eşleştirme yapılmaz.")
            }
            if let snapshot {
                Section("\(snapshot.rows.count) kayıt") {
                    if snapshot.rows.isEmpty { Text("Bu kapsamda ders kitabı kaydı yok.") }
                    ForEach(snapshot.rows) { row in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(row.person + " · " + row.title).font(.headline)
                            Text([row.className, row.studentNumber, row.period].filter { !$0.isEmpty }.joined(separator: " · "))
                            Text(row.status + (row.condition.isEmpty ? "" : " · " + row.condition))
                            if !row.note.isEmpty { Text(row.note).font(.subheadline).foregroundStyle(.secondary) }
                        }.fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .navigationTitle("Ders Kitabı Çizelgesi")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                let events = try SchoolLibraryService.historySnapshot(context: context)
                let loans = try context.fetch(FetchDescriptor<ActiveLoan>()).filter { $0.kind == "textbook" }
                periods = Array(Set(events.filter { $0.loanKind == "textbook" }.compactMap(\.periodSnapshot) + loans.compactMap(\.periodSnapshot)).filter { !$0.isEmpty }).sorted()
                classes = Array(Set(events.filter { $0.loanKind == "textbook" }.compactMap(\.classSnapshot) + loans.map(\.studentClass)).filter { !$0.isEmpty }).sorted()
            } catch { self.error = error.localizedDescription }
        }
        .onChange(of: filter) { _, _ in clear() }
        .onChange(of: schoolName) { _, _ in clear() }
        // Öğrenci adı içeren çizelge dosyaları ekran kapanınca silinir.
        .onDisappear { clear() }
    }

    private func clear() { GeciciDosya.sil([pdfURL, csvURL, excelURL]); snapshot = nil; pdfURL = nil; csvURL = nil; excelURL = nil }
    private func prepare() {
        clear(); error = nil
        do {
            var scope = filter
            scope.start = Calendar.current.startOfDay(for: scope.start)
            scope.end = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: scope.end) ?? scope.end
            let value = TextbookReportEngine.snapshot(events: try SchoolLibraryService.historySnapshot(context: context),
                loans: try context.fetch(FetchDescriptor<ActiveLoan>()), copies: try context.fetch(FetchDescriptor<BookCopy>()), filter: scope)
            let token = UUID().uuidString
            let pdf = PDFReportBuilder.build(title: "DERS KİTABI TESLİM VE İADE ÇİZELGESİ", subtitle: schoolName,
                sections: value.sections, signatures: ["Kütüphane Sorumlusu", "Okul Müdürü"])
            guard !pdf.isEmpty, let p = GeciciDosya.yaz(pdf, ad: "DersKitabi-\(token).pdf"),
                  let c = GeciciDosya.yaz(ReportTableExporter.csv(value.table), ad: "DersKitabi-\(token).csv"),
                  let x = GeciciDosya.yaz(ReportTableExporter.excel(value.table), ad: "DersKitabi-\(token).xlsx") else {
                throw SchoolLibraryService.OperationError(message: "Çizelge dosyalarının tümü yazılamadı; yeniden deneyin.")
            }
            snapshot = value; pdfURL = p; csvURL = c; excelURL = x
        } catch { self.error = error.localizedDescription }
    }
}
