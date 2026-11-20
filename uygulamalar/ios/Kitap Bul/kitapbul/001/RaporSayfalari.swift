import SwiftUI
import SwiftData
import Charts
import UserNotifications

// MARK: - Derin bağlantı (QR → kitap ayrıntısı)

/// Ekle sekmesinde başlatılacak ekleme yolu (Ana Sayfa kısayolları, Kitaplar'daki "Kitap ekle"
/// menüsü, kitapbul://ekle/… bağlantısı). Ham değer kimlik sözleşmesidir, değişmez; görünen ad `baslik`.
enum HizliEylem: String, CaseIterable, Identifiable {
    case barkod = "Barkod okut"
    case seri = "Seri tarama"
    case canliKapak = "Canlı kapak"
    case kamera = "Kamerayla tara"
    case ses = "Sesle kaydet"
    case elle = "Elle gir"

    var id: String { rawValue }

    var ikon: String {
        switch self {
        case .barkod: "barcode.viewfinder"
        case .seri: "barcode"
        case .canliKapak: "text.viewfinder"
        case .kamera: "doc.viewfinder"
        case .ses: "mic.fill"
        case .elle: "square.and.pencil"
        }
    }

    /// Görünen ad: Ekle sekmesindeki kartla aynı (tek ad sözlüğü).
    var baslik: String {
        switch self {
        case .barkod: "Barkodla ekle"
        case .seri: "Seri tarama"
        case .canliKapak: "Canlı Kapak"
        case .kamera: "Belge Tara"
        case .ses: "Sesle"
        case .elle: "Elle"
        }
    }
}

@Observable
final class DerinBaglanti {
    static let shared = DerinBaglanti()
    var bekleyenKitapID: UUID?
    var bekleyenEylem: HizliEylem?
    /// Kitaplar'daki "Bu ISBN ile kataloğa ekle": yalnız Ekle sayfası (`.add` sunumu) karşılar.
    var bekleyenISBN: String?
    /// MainTabView dinler: başka bir ekrandan sekme değişimi istenirse
    var hedefSekme: MainTabView.Sekme?
    /// Asistan sekmesi açılınca dinlemeye hemen başlasın
    var asistanDinle = false
}

// MARK: - Aylık rapor hatırlatıcısı

enum AylikRaporHatirlatici {
    static let anahtar = "monthlyReportReminder"
    private static let kimlik = "aylik-rapor"

    static func ayarla(_ acik: Bool) {
        let merkez = UNUserNotificationCenter.current()
        merkez.removePendingNotificationRequests(withIdentifiers: [kimlik])
        guard acik else { return }
        Task {
            await LoanReminders.requestPermissionIfNeeded()
            let icerik = UNMutableNotificationContent()
            icerik.title = "Aylık kütüphane raporu"
            icerik.body = "Geçen ayın dönem raporunu hazırlayıp okul yönetimine gönderebilirsiniz."
            icerik.sound = .default
            var bilesen = DateComponents()
            bilesen.day = 1
            bilesen.hour = 9
            let istek = UNNotificationRequest(identifier: kimlik, content: icerik,
                                              trigger: UNCalendarNotificationTrigger(dateMatching: bilesen, repeats: true))
            try? await merkez.add(istek)
        }
    }
}

/// PDF/CSV verisini paylaşılabilir geçici dosyaya yazar.
/// Dosyalar `Caches/Paylasim/<UUID>/` altına, her yazımda ayrı bir klasöre gider: aynı adlı eski rapor üzerine
/// yazılmaz, öğrenci adı içeren çıktılar tek yerde toplanır ve süreç başına ilk kullanımda klasör boşaltılır.
nonisolated enum GeciciDosya {
    static var kok: URL {
        (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Paylasim", isDirectory: true)
    }
    /// Süreç başına bir kez (ilk yazımdan önce): önceki oturumdan kalan paylaşım dosyalarını siler.
    private static let acilisTemizligi: Void = { try? FileManager.default.removeItem(at: kok) }()

    static func yaz(_ veri: Data, ad: String) -> URL? {
        _ = acilisTemizligi
        let guvenliAd = ad.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let klasor = kok.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = klasor.appendingPathComponent(guvenliAd)
        do {
            try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
            try veri.write(to: url, options: .atomic)
            return url
        } catch {
            try? FileManager.default.removeItem(at: klasor)
            return nil
        }
    }

    /// Verilen dosyaları ve onları saran token klasörünü siler (yalnız paylaşım kökü altındakileri).
    static func sil(_ dosyalar: [URL?]) {
        for dosya in dosyalar.compactMap({ $0 }) {
            let klasor = dosya.deletingLastPathComponent()
            if klasor.deletingLastPathComponent().standardizedFileURL == kok.standardizedFileURL {
                try? FileManager.default.removeItem(at: klasor)
            } else {
                try? FileManager.default.removeItem(at: dosya)
            }
        }
    }

    /// Tüm paylaşım klasörünü boşaltır (uygulama açılışı).
    static func temizle() { try? FileManager.default.removeItem(at: kok) }
}

/// Dönem raporunun üç dosyasını ana iş parçacığı dışında üretir ve yazar; iptal edilirse hiçbir dosya bırakmaz.
nonisolated struct RaporPaketi: Sendable {
    let pdf: URL
    let csv: URL
    let excel: URL
}

nonisolated enum RaporHazirlayici {
    static func uret(title: String, subtitle: String, sections: [PDFReportBuilder.Section], table: [[String]],
                     signatures: [String], onEk: String = "Donem") async throws -> RaporPaketi {
        try Task.checkCancellation()
        let gorev = Task.detached(priority: .userInitiated) { () throws -> RaporPaketi in
            try Task.checkCancellation()
            let pdf = PDFReportBuilder.build(title: title, subtitle: subtitle, sections: sections, signatures: signatures)
            try Task.checkCancellation()
            let csv = ReportTableExporter.csv(table)
            try Task.checkCancellation()
            let excel = ReportTableExporter.excel(table)
            try Task.checkCancellation()
            let token = UUID().uuidString
            guard !pdf.isEmpty, let pdfFile = GeciciDosya.yaz(pdf, ad: "\(onEk)-\(token).pdf"),
                  let csvFile = GeciciDosya.yaz(csv, ad: "\(onEk)-\(token).csv"),
                  let excelFile = GeciciDosya.yaz(excel, ad: "\(onEk)-\(token).xlsx") else {
                throw CocoaError(.fileWriteUnknown)
            }
            if Task.isCancelled {
                GeciciDosya.sil([pdfFile, csvFile, excelFile])
                throw CancellationError()
            }
            return RaporPaketi(pdf: pdfFile, csv: csvFile, excel: excelFile)
        }
        return try await withTaskCancellationHandler { try await gorev.value } onCancel: { gorev.cancel() }
    }
}

// MARK: - Rapor merkezi

struct RaporMerkezi: View {
    /// Kitaplar sekmesinde süzülmüş liste (CSV/etiket/QR için); nil ise tüm katalog
    var kitaplar: [CatalogBook]? = nil

    var body: some View {
        // Renkli kart ızgarası (liste yerine)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(kitaplar.map { "Kitaplar sekmesindeki süzülmüş \($0.count) kitap kullanılır." } ?? "Tüm katalog kullanılır.")
                    .font(.subheadline)
                    .foregroundStyle(KitapTema.ikincilMetin)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], spacing: 14) {
                    NavigationLink { DonemRaporuSayfasi() } label: {
                        RenkliKart(baslik: "Dönem Raporu", altBaslik: "Resmî, imzaya hazır PDF", ikon: "doc.text.fill", renk: KitapTema.basari)
                    }
                    NavigationLink { TextbookReportView() } label: {
                        RenkliKart(baslik: "Ders Kitabı Çizelgesi", altBaslik: "Öğrenci, teslim, iade ve eksik", ikon: "list.clipboard", renk: KitapTema.toplu)
                    }
                    NavigationLink { IstatistikGrafikleri() } label: {
                        RenkliKart(baslik: "Ödünç grafikleri", altBaslik: "Aylık ödünç, kategori halkası", ikon: "chart.xyaxis.line", renk: KitapTema.dosya)
                    }
                    NavigationLink { OkunmayanlarRaporu() } label: {
                        RenkliKart(baslik: "Hiç Ödünç Verilmeyenler", altBaslik: "Tanıtılacak kitaplar", ikon: "book.closed.fill", renk: KitapTema.foto)
                    }
                    NavigationLink { CSVDisaAktarSayfasi(kitaplar: kitaplar) } label: {
                        RenkliKart(baslik: "CSV'ye Aktar", altBaslik: "Sütunları siz seçin", ikon: "tablecells.fill", renk: KitapTema.amazon)
                    }
                    NavigationLink { PrintCalibrationView() } label: {
                        RenkliKart(baslik: "Baskı Profilleri", altBaslik: "Ölçü, kişisel bilgi ve prova", ikon: "ruler", renk: KitapTema.dosya)
                    }
                    NavigationLink { BaskiSayfasi(kitaplar: kitaplar) } label: {
                        RenkliKart(baslik: "Etiket ve QR Kart", altBaslik: "Sırt etiketi, QR kitap kartı", ikon: "printer.fill", renk: KitapTema.toplu)
                    }
                }
                .buttonStyle(.kitapSade)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        // Yönetim ve araç panelindeki adla aynı (tek ad kaynağı: KatalogAraci.reportCenter)
        .navigationTitle(KatalogAraci.reportCenter.aracBasligi ?? "")
    }
}

// MARK: - Dönem raporu

struct DonemRaporuSayfasi: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AylikRaporHatirlatici.anahtar) private var hatirlatici = false
    @AppStorage("schoolName") private var okulAdi = ""
    @Query private var kitaplar: [CatalogBook]
    @Query private var nushalar: [BookCopy]
    @State private var filter = LibraryReportFilter()
    @State private var periodID = "custom"
    @State private var history: [LoanEvent] = []
    @State private var classNames: [String] = []
    @State private var pdfURL: URL?
    @State private var csvURL: URL?
    @State private var excelURL: URL?
    @State private var hazirlaniyor = false
    @State private var hazirlamaGorevi: Task<Void, Never>?
    @State private var hazirlamaKimligi = UUID()
    @State private var hata: String?
    @State private var preview: [PDFReportBuilder.Section] = []
    @State private var preparedScope = ""
    let reportTitle: String
    let screenTitle: String

    init(reportTitle: String = "KÜTÜPHANE DÖNEM RAPORU", screenTitle: String = "Dönem Raporu") {
        self.reportTitle = reportTitle
        self.screenTitle = screenTitle
    }

    private var periods: [EducationalReportPeriod] { EducationalReportPeriod.choices() }
    private var categories: [String] { Array(Set(kitaplar.map(\.kategoriAdi))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    private var cabinets: [String] { Array(Set((kitaplar.compactMap(\.cabinet) + nushalar.compactMap(\.cabinet)).filter { !$0.isEmpty })).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    private var shelves: [String] {
        Array(Set((kitaplar.compactMap(\.shelf) + nushalar.compactMap(\.shelf)).filter { !$0.isEmpty })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        Form {
            Section {
                Picker("Eğitim dönemi", selection: Binding(get: { periodID }, set: applyPeriod)) {
                    Text("Özel tarih aralığı").tag("custom")
                    ForEach(periods) { Text($0.title).tag($0.id) }
                }
                DatePicker("Başlangıç", selection: dateBinding(start: true), displayedComponents: .date)
                DatePicker("Bitiş", selection: dateBinding(start: false), displayedComponents: .date)
                Button("Geçen ay") {
                    let calendar = Calendar.current
                    let first = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
                    filter.start = calendar.date(byAdding: .month, value: -1, to: first) ?? first
                    filter.end = first.addingTimeInterval(-1)
                    filter.academicPeriodLabel = "Geçen ay"; periodID = "custom"
                }.frame(minHeight: 44)
            } header: { Text("Dönem").foregroundStyle(.primary) } footer: {
                Text("Eğitim dönemi seçenekleri Eylül–Ağustos, Eylül–Ocak ve Şubat–Haziran tarihlerini başlangıç olarak kullanır. Okulunuzun kesin tarihlerine göre başlangıç ve bitişi değiştirebilirsiniz.")
            }
            Section {
                Picker("Sınıf", selection: $filter.className) {
                    Text("Tüm sınıflar").tag("")
                    ForEach(classNames, id: \.self) { Text($0).tag($0) }
                }
                Picker("Okur türü", selection: $filter.readerKind) {
                    ForEach(LibraryReaderKind.allCases) { Text($0.title).tag($0) }
                }
                Picker("Kategori", selection: $filter.category) {
                    Text("Tüm kategoriler").tag("")
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                Picker("Dolap", selection: $filter.cabinet) {
                    Text("Tüm dolaplar").tag("")
                    ForEach(cabinets, id: \.self) { Text($0).tag($0) }
                }
                Picker("Raf", selection: $filter.shelf) {
                    Text("Tüm raflar").tag("")
                    ForEach(shelves, id: \.self) { Text($0).tag($0) }
                }
            } header: { Text("Kapsam").foregroundStyle(.primary) } footer: {
                Text("Sınıf, hareket tarihindeki sınıf kaydından; okur, öğrenci veya üye kimliğinden belirlenir. Kategori eser bilgisini; dolap ve raf fiziksel nüshanın etkin konumunu kullanır. Tekil kimliği olmayan adet ve eski hareketlerde eser konumu esas alınır. Eksik eski kimlikler ayrı tutulur.")
            }
            Section {
                TextField("Okul adı (rapor başlığı)", text: $okulAdi)
                Toggle("Her ayın 1'inde hatırlat", isOn: $hatirlatici)
                    .onChange(of: hatirlatici) { _, acik in AylikRaporHatirlatici.ayarla(acik) }
            }
            Section {
                Button(action: hazirla) {
                    Label(hazirlaniyor ? "Hazırlanıyor…" : "Raporu Hazırla", systemImage: "doc.badge.gearshape")
                }
                .buttonStyle(.kitapDolu(KitapTema.dosya))
                .disabled(hazirlaniyor || filter.start > filter.end)
                if hazirlaniyor {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Rapor hazırlanıyor…").font(.subheadline)
                        Spacer()
                        Button("İptal", role: .cancel) { hazirlamaGorevi?.cancel() }.frame(minHeight: 44)
                    }
                }
                if let pdfURL { ShareLink(item: pdfURL) { Label("PDF'i Paylaş / Yazdır", systemImage: "square.and.arrow.up") } }
                if let csvURL { ShareLink(item: csvURL) { Label("Aynı raporu CSV paylaş", systemImage: "tablecells") } }
                if let excelURL { ShareLink(item: excelURL) { Label("Aynı raporu Excel paylaş", systemImage: "tablecells.badge.ellipsis") } }
                if filter.start > filter.end { Text("Başlangıç tarihi bitişten sonra olamaz.").foregroundStyle(.red) }
                if let hata { Text(hata).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            } footer: {
                Text("Üç dosya ve aşağıdaki önizleme aynı veri anlık görüntüsünden hazırlanır. Süre uzatma ve ders kitabı dağıtımı okuma sıralamasına eklenmez.")
            }
            if !preview.isEmpty {
                Section { Text(preparedScope).fixedSize(horizontal: false, vertical: true) } header: { Text("Hazırlanan raporun kapsamı").foregroundStyle(.primary) }
                ForEach(preview.indices, id: \.self) { index in
                    Section {
                        if preview[index].rows.isEmpty { Text("Bu kapsamda kayıt yok.") }
                        ForEach(preview[index].rows.indices, id: \.self) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preview[index].rows[row].0).fixedSize(horizontal: false, vertical: true)
                                Text(preview[index].rows[row].1).font(.subheadline).foregroundStyle(KitapTema.ikincilMetin)
                                    .fixedSize(horizontal: false, vertical: true)
                            }.padding(.vertical, 2)
                        }
                    } header: { Text(preview[index].title).foregroundStyle(.primary) }
                }
            }
        }
        .navigationTitle(screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { loadOptions() }
        .onChange(of: filter) { _, _ in clearPrepared() }
        .onChange(of: okulAdi) { _, _ in clearPrepared() }
        // Öğrenci adı içeren rapor dosyaları ekran kapanınca silinir.
        .onDisappear { hazirlamaGorevi?.cancel(); clearPrepared() }
        .onChange(of: filter.cabinet) { _, _ in
            if !filter.shelf.isEmpty && !shelves.contains(filter.shelf) { filter.shelf = "" }
        }
    }

    private func dateBinding(start: Bool) -> Binding<Date> {
        Binding(get: { start ? filter.start : filter.end }, set: { date in
            if start { filter.start = date } else { filter.end = date }
            periodID = "custom"; filter.academicPeriodLabel = "Özel tarih aralığı"
        })
    }

    private func applyPeriod(_ id: String) {
        periodID = id
        if let period = periods.first(where: { $0.id == id }) {
            filter.start = period.start; filter.end = period.end; filter.academicPeriodLabel = period.title
        } else { filter.academicPeriodLabel = "Özel tarih aralığı" }
    }

    private func loadOptions() {
        do {
            history = try SchoolLibraryService.historySnapshot(context: modelContext)
            classNames = Array(Set(try StudentStore.allVerified().map(\.className) + history.compactMap(\.classSnapshot)).filter { !$0.isEmpty }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        } catch { hata = "Rapor kaynakları okunamadı: \(error.localizedDescription)" }
    }

    private func clearPrepared() {
        // Öğrenci adı içeren eski rapor dosyaları paylaşım klasöründe birikmesin
        GeciciDosya.sil([pdfURL, csvURL, excelURL])
        pdfURL = nil; csvURL = nil; excelURL = nil; preview = []; preparedScope = ""
    }

    /// Veri anlık görüntüsü ana aktörde alınır (SwiftData nesneleri aktör dışına çıkmaz); PDF, CSV ve XLSX
    /// üretimi ve dosya yazımı arka planda yapılır. İptal edilen ya da ekranı terk edilen iş ekran durumunu yazmaz.
    private func hazirla() {
        hazirlamaGorevi?.cancel()
        hata = nil; clearPrepared()
        let kapsam: LibraryReportFilter
        let snapshot: LibraryReportEngine.Snapshot
        let document: LibraryReportEngine.Document
        do {
            let books = try modelContext.fetch(FetchDescriptor<CatalogBook>())
            let loans = try modelContext.fetch(FetchDescriptor<ActiveLoan>())
            let copies = try modelContext.fetch(FetchDescriptor<BookCopy>())
            let reservations = try modelContext.fetch(FetchDescriptor<Reservation>())
            let events = try SchoolLibraryService.historySnapshot(context: modelContext)
            let memberKinds = Dictionary(try MemberStore.allVerified().compactMap { member in
                member.kind.map { (member.id, $0.rawValue) }
            }, uniquingKeysWith: { a, _ in a })
            var scope = filter
            scope.start = Calendar.current.startOfDay(for: scope.start)
            scope.end = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: scope.end) ?? scope.end
            snapshot = try LibraryReportEngine.snapshot(books: books, events: events, loans: loans, copies: copies,
                reservations: reservations, filter: scope, memberKinds: memberKinds)
            document = snapshot.document(title: reportTitle, schoolName: okulAdi)
            kapsam = scope
        } catch { hata = "Rapor hazırlanamadı: \(error.localizedDescription)"; return }
        hazirlaniyor = true
        let kimlik = UUID()
        hazirlamaKimligi = kimlik
        let table = document.table
        let sections = snapshot.sections
        let ozet = document.title + " · " + document.subtitle + " · " + kapsam.scopeDescription
        let gorev = Task {
            defer { if hazirlamaKimligi == kimlik { hazirlaniyor = false; hazirlamaGorevi = nil } }
            do {
                let paket = try await RaporHazirlayici.uret(title: document.title, subtitle: document.subtitle,
                    sections: document.sections, table: table, signatures: ["Kütüphane Sorumlusu", "Okul Müdürü"])
                guard !Task.isCancelled, hazirlamaKimligi == kimlik else { GeciciDosya.sil([paket.pdf, paket.csv, paket.excel]); return }
                pdfURL = paket.pdf; csvURL = paket.csv; excelURL = paket.excel
                preview = sections; preparedScope = ozet
            } catch is CancellationError {
                // Kullanıcı iptal etti ya da ekrandan ayrıldı; ekran durumu değişmez.
            } catch { hata = "Rapor dosyalarının tümü yazılamadı; tekrar deneyin." }
        }
        hazirlamaGorevi = gorev
    }
}

// MARK: - İstatistik grafikleri

struct IstatistikGrafikleri: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var kitaplar: [CatalogBook]
    @Query private var nushalar: [BookCopy]
    @Query private var loans: [ActiveLoan]
    @State private var history: [LoanEvent] = []
    @State private var memberKinds: [UUID: String] = [:]
    @State private var filter = LibraryReportFilter(start: Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now,
        academicPeriodLabel: "Son 12 ay")
    @State private var periodID = "custom"
    @State private var selectedMonth: Date?
    @State private var selectedAddedMonth: Date?
    @State private var selectedCategoryAngle: Int?
    @State private var detail: RaporListeKapsami?
    @State private var hata: String?
    @State private var loading = true

    /// Filtreye bağlı türetilmiş veriler: yalnız filtre ya da kaynak veri değişince bir kez hesaplanır
    /// (eskiden her çizimde süzme, gruplama ve ay sayımı yeniden yapılırdı).
    private struct GrafikVerisi {
        var books: [CatalogBook] = []
        var events: [LoanEvent] = []
        var loans: [ActiveLoan] = []
        var months: [RaporMotoru.AySayisi] = []
        var distribution: [(ad: String, sayi: Int)] = []
        var unread: [CatalogBook] = []
    }
    @State private var veri = GrafikVerisi()
    private var selectedBooks: [CatalogBook] { veri.books }
    private var selectedEvents: [LoanEvent] { veri.events }
    private var selectedLoans: [ActiveLoan] { veri.loans }
    private var kaynakImzasi: [Int] { [kitaplar.count, nushalar.count, loans.count, history.count] }

    private func yenidenHesapla() {
        let books = LibraryReportEngine.filteredBooks(kitaplar, filter: filter, copies: nushalar)
        let scope = dayScope
        let events = LibraryReportEngine.filteredEvents(history, bookIDs: Set(books.map(\.id)), filter: scope, memberKinds: memberKinds, books: kitaplar, copies: nushalar)
        let secilenOdunc = LibraryReportEngine.filteredLoans(loans, books: kitaplar, copies: nushalar, filter: filter, memberKinds: memberKinds)
        veri = GrafikVerisi(
            books: books, events: events, loans: secilenOdunc,
            months: RaporMotoru.aylikSayilar(events: events,
                eklenmeTarihleri: books.filter { $0.addedAt >= scope.start && $0.addedAt <= scope.end }.map(\.addedAt),
                baslangic: scope.start, now: scope.end),
            distribution: RaporMotoru.kategoriDagilimi(LibraryReportEngine.quantityBooks(kitaplar, copies: nushalar, filter: filter)),
            unread: RaporMotoru.okunmayanlar(books, events: history, loans: loans))
    }
    private var dayScope: LibraryReportFilter {
        var value = filter
        value.start = Calendar.current.startOfDay(for: value.start)
        value.end = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: value.end) ?? value.end
        return value
    }
    private var classNames: [String] { Array(Set(history.compactMap(\.classSnapshot) + loans.map(\.studentClass)).filter { !$0.isEmpty }).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    private var categories: [String] { Array(Set(kitaplar.map(\.kategoriAdi))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    private var cabinets: [String] { Array(Set((kitaplar.compactMap(\.cabinet) + nushalar.compactMap(\.cabinet)).filter { !$0.isEmpty })).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    private var shelves: [String] { Array(Set((kitaplar.compactMap(\.shelf) + nushalar.compactMap(\.shelf)).filter { !$0.isEmpty })).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }

    var body: some View {
        let months = veri.months
        let distribution = veri.distribution
        let aylikBirim: Calendar.Component = (months.first?.ayAdedi ?? 1) > 1 ? .quarter : .month
        let aralikBasligi = aylikBirim == .quarter ? "Üç aylık ödünç ve iade (\(months.count) çeyrek)" : "Aylık ödünç ve iade (\(months.count) ay)"
        List {
            Section {
                DisclosureGroup("Grafik kapsamı") {
                    Picker("Eğitim dönemi", selection: Binding(get: { periodID }, set: { id in
                        periodID = id
                        if let value = EducationalReportPeriod.choices().first(where: { $0.id == id }) {
                            filter.start = value.start; filter.end = value.end; filter.academicPeriodLabel = value.title
                        } else { filter.academicPeriodLabel = "Özel tarih aralığı" }
                    })) {
                        Text("Özel tarih aralığı").tag("custom")
                        ForEach(EducationalReportPeriod.choices()) { Text($0.title).tag($0.id) }
                    }
                    DatePicker("Başlangıç", selection: $filter.start, displayedComponents: .date)
                    DatePicker("Bitiş", selection: $filter.end, displayedComponents: .date)
                    Picker("Sınıf", selection: $filter.className) {
                        Text("Tüm sınıflar").tag(""); ForEach(classNames, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Okur türü", selection: $filter.readerKind) { ForEach(LibraryReaderKind.allCases) { Text($0.title).tag($0) } }
                    Picker("Kategori", selection: $filter.category) {
                        Text("Tüm kategoriler").tag(""); ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Dolap", selection: $filter.cabinet) {
                        Text("Tüm dolaplar").tag(""); ForEach(cabinets, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Raf", selection: $filter.shelf) {
                        Text("Tüm raflar").tag(""); ForEach(shelves, id: \.self) { Text($0).tag($0) }
                    }
                }
                Text(dayScope.scopeDescription).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            } footer: { Text("Grafikte bir ayı veya kategori dilimini seçin; aynı filtreye uyan gerçek kayıtlar açılır. Altındaki düğmeler VoiceOver ve büyük yazıyla aynı listeleri açar.") }
            if loading { ProgressView("Rapor geçmişi okunuyor…") }
            else if let hata { Text(hata).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            else if filter.start > filter.end { Text("Başlangıç tarihi bitişten sonra olamaz.").foregroundStyle(.red) }
            else {
                Section {
                    Chart {
                        ForEach(months) { month in
                            BarMark(x: .value("Ay", month.ay, unit: aylikBirim), y: .value("Sayı", month.verilen))
                                .foregroundStyle(by: .value("Tür", "Verilen")).position(by: .value("Tür", "Verilen"))
                            BarMark(x: .value("Ay", month.ay, unit: aylikBirim), y: .value("Sayı", month.iade))
                                .foregroundStyle(by: .value("Tür", "İade")).position(by: .value("Tür", "İade"))
                        }
                    }
                    .chartForegroundStyleScale(["Verilen": KitapTema.amazon, "İade": KitapTema.basari])
                    .chartXSelection(value: $selectedMonth)
                    .frame(height: 220)
                    .accessibilityLabel("Seçili aralıkta \(months.reduce(0) { $0 + $1.verilen }) ödünç, \(months.reduce(0) { $0 + $1.iade }) iade")
                    ForEach(months.reversed()) { month in
                        Button { showMonth(month.ay, added: false) } label: {
                            HStack {
                                Text(dilimAdi(month))
                                Spacer()
                                Text("\(month.verilen) ödünç · \(month.iade) iade").font(.subheadline)
                            }.foregroundStyle(.primary).frame(minHeight: 44)
                        }
                    }
                } header: { Text(aralikBasligi).foregroundStyle(.primary) }
                Section {
                    Chart(months) { month in
                        LineMark(x: .value("Ay", month.ay, unit: aylikBirim), y: .value("Eklenen", month.eklenen))
                            .interpolationMethod(.catmullRom).foregroundStyle(KitapTema.ana)
                        AreaMark(x: .value("Ay", month.ay, unit: aylikBirim), y: .value("Eklenen", month.eklenen))
                            .foregroundStyle(KitapTema.ana.opacity(0.15).gradient)
                    }
                    .chartXSelection(value: $selectedAddedMonth)
                    .frame(height: 160)
                    ForEach(months.reversed()) { month in
                        Button { showMonth(month.ay, added: true) } label: {
                            HStack { Text(dilimAdi(month)); Spacer(); Text("\(month.eklenen) eser") }
                                .foregroundStyle(.primary).frame(minHeight: 44)
                        }
                    }
                } header: { Text("Kataloğa eklenen eserler").foregroundStyle(.primary) }
                Section {
                    Chart(distribution, id: \.ad) { row in
                        SectorMark(angle: .value("Nüsha", row.sayi), innerRadius: .ratio(0.55), angularInset: 1)
                            .foregroundStyle(by: .value("Kategori", row.ad))
                    }
                    .chartAngleSelection(value: $selectedCategoryAngle)
                    .chartLegend(.hidden)
                    .frame(height: 240)
                    .accessibilityLabel(distribution.map { "\($0.ad) \($0.sayi)" }.joined(separator: ", "))
                    ForEach(distribution, id: \.ad) { row in
                        Button { showCategory(row.ad) } label: {
                            HStack { Text(row.ad); Spacer(); Text("\(row.sayi) nüsha") }.foregroundStyle(.primary).frame(minHeight: 44)
                        }
                    }
                } header: { Text("Kategori dağılımı (nüsha)").foregroundStyle(.primary) }
                Section {
                    Button {
                        detail = RaporListeKapsami(title: "Ödünç serisindeki hareketler", events: selectedEvents.filter { $0.kind == .lent && $0.loanKind != "textbook" })
                    } label: { LabeledContent("Ödünç serisi", value: "\(RaporMotoru.okumaSerisi(events: selectedEvents)) gün").foregroundStyle(.primary).frame(minHeight: 44) }
                    Button { detail = RaporListeKapsami(title: "Seçili okurlarda ödünçte", loans: selectedLoans) } label: {
                        LabeledContent("Ödünçte", value: "\(selectedLoans.count)").foregroundStyle(.primary).frame(minHeight: 44)
                    }
                    Button { detail = RaporListeKapsami(title: "Seçili okurlarda gecikmiş", loans: selectedLoans.filter(\.isOverdue)) } label: {
                        LabeledContent("Gecikmiş", value: "\(selectedLoans.filter(\.isOverdue).count)").foregroundStyle(.primary).frame(minHeight: 44)
                    }
                    let unread = veri.unread
                    Button { detail = RaporListeKapsami(title: "Seçili koleksiyonda hiç okunmamış", books: unread) } label: {
                        LabeledContent("Hiç okunmamış", value: "\(unread.count)").foregroundStyle(.primary).frame(minHeight: 44)
                    }
                } header: { Text("Şu an / seçili kapsam").foregroundStyle(.primary) }
            }
        }
        .navigationTitle("Ödünç grafikleri")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                history = try SchoolLibraryService.historySnapshot(context: modelContext)
                memberKinds = Dictionary(try MemberStore.allVerified().compactMap { member in member.kind.map { (member.id, $0.rawValue) } }, uniquingKeysWith: { a, _ in a })
            } catch { hata = "Rapor geçmişi okunamadı: \(error.localizedDescription)" }
            yenidenHesapla()
            loading = false
        }
        .onChange(of: kaynakImzasi) { _, _ in yenidenHesapla() }
        .sheet(item: $detail) { scope in NavigationStack { RaporDetayListesi(scope: scope) } }
        .onChange(of: selectedMonth) { _, date in if let date { showMonth(date, added: false) } }
        .onChange(of: selectedAddedMonth) { _, date in if let date { showMonth(date, added: true) } }
        .onChange(of: selectedCategoryAngle) { _, angle in
            if let angle {
                var total = 0
                for row in distribution {
                    total += row.sayi
                    if angle < total { showCategory(row.ad); break }
                }
            }
        }
        .onChange(of: filter) { _, _ in selectedMonth = nil; selectedAddedMonth = nil; selectedCategoryAngle = nil; yenidenHesapla() }
        .onChange(of: memberKinds) { _, _ in yenidenHesapla() }
    }

    /// Dilim bir ay ya da (çok uzun aralıkta) bir çeyrek olabilir.
    private func dilimAraligi(_ date: Date) -> (baslangic: Date, bitis: Date, baslik: String)? {
        let takvim = Calendar.current
        guard let dilim = veri.months.first(where: { month in
            guard let bit = takvim.date(byAdding: .month, value: month.ayAdedi, to: month.ay) else { return false }
            return date >= month.ay && date < bit
        }), let bit = takvim.date(byAdding: .month, value: dilim.ayAdedi, to: dilim.ay) else {
            guard let aralik = takvim.dateInterval(of: .month, for: date) else { return nil }
            return (aralik.start, aralik.end, date.formatted(.dateTime.month(.wide).year()))
        }
        return (dilim.ay, bit, dilimAdi(dilim))
    }
    private func dilimAdi(_ dilim: RaporMotoru.AySayisi) -> String {
        guard dilim.ayAdedi > 1, let son = Calendar.current.date(byAdding: .month, value: dilim.ayAdedi - 1, to: dilim.ay) else {
            return dilim.ay.formatted(.dateTime.month(.wide).year())
        }
        return dilim.ay.formatted(.dateTime.month(.abbreviated)) + " – " + son.formatted(.dateTime.month(.abbreviated).year())
    }

    private func showMonth(_ date: Date, added: Bool) {
        guard let aralik = dilimAraligi(date) else { return }
        let title = aralik.baslik
        if added {
            detail = RaporListeKapsami(title: title + " / eklenen eserler", books: selectedBooks.filter {
                $0.addedAt >= aralik.baslangic && $0.addedAt < aralik.bitis && $0.addedAt >= dayScope.start && $0.addedAt <= dayScope.end
            })
        } else {
            detail = RaporListeKapsami(title: title + " / hareketler", events: selectedEvents.filter { $0.date >= aralik.baslangic && $0.date < aralik.bitis })
        }
    }
    private func showCategory(_ category: String) {
        detail = RaporListeKapsami(title: category, books: selectedBooks.filter { $0.kategoriAdi == category })
    }
}

private struct RaporListeKapsami: Identifiable {
    let id = UUID()
    let title: String
    var books: [CatalogBook] = []
    var events: [LoanEvent] = []
    var loans: [ActiveLoan] = []
}

private struct RaporDetayListesi: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allBooks: [CatalogBook]
    let scope: RaporListeKapsami
    @State private var limit = 100
    var body: some View {
        List {
            Text("\(scope.books.count + scope.events.count + scope.loans.count) kayıt")
            ForEach(scope.books.prefix(limit)) { book in
                NavigationLink { KitapDetaySayfasi(kitapID: book.id) } label: {
                    bookRow(book)
                }
            }
            ForEach(scope.events.sorted { $0.date > $1.date }.prefix(limit)) { event in
                if let book = allBooks.first(where: { $0.id == event.bookID }) {
                    NavigationLink { KitapDetaySayfasi(kitapID: book.id) } label: { eventRow(event) }
                } else { eventRow(event) }
            }
            ForEach(scope.loans.prefix(limit)) { loan in
                NavigationLink { OduncDetaySayfasi(loan: loan) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loan.bookTitleSnapshot); Text(loan.studentName + " · " + loan.studentClass)
                        Text("Son gün: \(loan.dueDate.formatted(date: .numeric, time: .omitted))").font(.subheadline)
                    }.foregroundStyle(.primary)
                }
            }
            if max(scope.books.count, max(scope.events.count, scope.loans.count)) > limit {
                Button("Sonraki 100 kaydı göster") { limit += 100 }.frame(minHeight: 44)
            }
            if scope.books.isEmpty && scope.events.isEmpty && scope.loans.isEmpty { Text("Bu kapsamda kayıt yok.") }
        }
        .navigationTitle(scope.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
    }
    private func bookRow(_ book: CatalogBook) -> some View {
        let location = (book.cabinet ?? "") + " / " + (book.shelf ?? "")
        let metadata = book.kategoriAdi + " · " + location
        return VStack(alignment: .leading, spacing: 4) {
            Text(book.title)
            Text(book.author).font(.subheadline)
            Text(metadata).font(.caption)
        }.foregroundStyle(.primary)
    }
    private func eventRow(_ event: LoanEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.bookTitle).font(.body.weight(.semibold))
            Text(event.kind.rawValue + " · " + event.date.formatted(date: .numeric, time: .shortened)).font(.subheadline)
            Text(event.person + " · " + (event.classSnapshot ?? "Sınıf belirtilmemiş"))
            Text(event.studentID.map { "Öğrenci: " + $0.uuidString } ?? event.memberID.map { "Üye: " + $0.uuidString } ?? "Eski / elle girilmiş kimlik")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(.primary)
    }
}

// MARK: - Hiç okunmayanlar

struct OkunmayanlarRaporu: View {
    @Query private var kitaplar: [CatalogBook]
    @Query private var loans: [ActiveLoan]
    @Environment(\.modelContext) private var modelContext
    @State private var enAzGun = 90
    @State private var csvURL: URL?
    @State private var history: [LoanEvent]?
    @State private var hata: String?

    var body: some View {
        // Geçmiş okunamadıysa "hiç ödünç verilmemiş" denemez: liste boş kalır, hata gösterilir
        let liste = history.map { RaporMotoru.okunmayanlar(kitaplar, events: $0, loans: loans, enAzGun: enAzGun) } ?? []
        List {
            if let hata {
                Section { Label(hata, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            Section {
                Stepper("En az \(enAzGun) gündür katalogda", value: $enAzGun, in: 0...1095, step: 30)
                Button("Listeyi CSV olarak hazırla", systemImage: "doc.badge.gearshape") {
                    csvURL = KitapCSV.dosya(KitapCSV.olustur(liste, sutunlar: [.ad, .yazar, .kategori, .dolap, .raf, .eklenme]), ad: "Okunmayanlar")
                }
                .disabled(liste.isEmpty)
                if let csvURL {
                    ShareLink(item: csvURL) { Label("Listeyi Paylaş (CSV)", systemImage: "square.and.arrow.up") }
                }
            } footer: {
                Text("Hiç ödünç verilmemiş kitaplar: vitrine koymak, tanıtmak ya da ayıklama kararı için.")
            }
            Section("\(liste.count) kitap") {
                ForEach(liste.prefix(500)) { kitap in
                    VStack(alignment: .leading) {
                        Text(kitap.title)
                        Text([kitap.author, kitap.category ?? "", "Eklenme: \(kitap.addedAt.formatted(date: .abbreviated, time: .omitted))"]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Hiç Ödünç Verilmeyenler")
        .onChange(of: enAzGun) { _, _ in GeciciDosya.sil([csvURL]); csvURL = nil }
        .onDisappear { GeciciDosya.sil([csvURL]); csvURL = nil }
        .task {
            do { history = try SchoolLibraryService.historySnapshot(context: modelContext); hata = nil }
            catch { history = nil; hata = "Ödünç geçmişi okunamadı; liste gösterilmiyor: \(error.localizedDescription)" }
        }
    }
}

// MARK: - Sütun seçmeli CSV

struct CSVDisaAktarSayfasi: View {
    /// nil = tüm katalog; boş dizi = hiç kitap (tüm katalog DEĞİL)
    let kitaplar: [CatalogBook]?
    @Query private var tumu: [CatalogBook]
    @AppStorage("csvExportColumns") private var kayitliSutunlar = KitapSutunu.varsayilan.map(\.rawValue).joined(separator: "|")

    private var secili: [KitapSutunu] {
        let adlar = Set(kayitliSutunlar.split(separator: "|").map(String.init))
        return KitapSutunu.allCases.filter { adlar.contains($0.rawValue) }
    }

    @State private var csvURL: URL?

    var body: some View {
        let kaynak = kitaplar ?? tumu
        Form {
            Section("Sütunlar (\(secili.count))") {
                ForEach(KitapSutunu.allCases) { sutun in
                    Toggle(sutun.rawValue, isOn: Binding(
                        get: { secili.contains(sutun) },
                        set: { acik in
                            var yeni = secili
                            if acik { yeni.append(sutun) } else { yeni.removeAll { $0 == sutun } }
                            kayitliSutunlar = KitapSutunu.allCases.filter { yeni.contains($0) }.map(\.rawValue).joined(separator: "|")
                        }
                    ))
                }
            }
            Section {
                // Dosya her çizimde değil, dokununca üretilir
                Button("\(kaynak.count) kitap için CSV hazırla", systemImage: "doc.badge.gearshape") {
                    csvURL = KitapCSV.dosya(KitapCSV.olustur(kaynak, sutunlar: secili))
                }
                .disabled(secili.isEmpty || kaynak.isEmpty)
                if let csvURL {
                    ShareLink(item: csvURL) {
                        Label("CSV'yi paylaş", systemImage: "square.and.arrow.up")
                    }
                }
            } footer: {
                Text("Excel'de Türkçe karakterlerle doğru açılır (UTF-8, noktalı virgül).")
            }
        }
        .navigationTitle("CSV'ye Aktar")
        .onChange(of: kayitliSutunlar) { _, _ in GeciciDosya.sil([csvURL]); csvURL = nil }
        .onDisappear { GeciciDosya.sil([csvURL]); csvURL = nil }
    }
}

// MARK: - Etiket ve QR kart baskısı

struct BaskiSayfasi: View {
    let kitaplar: [CatalogBook]?
    @Query private var tumu: [CatalogBook]
    @AppStorage(EtiketSablonu.anahtar) private var sablonRaw = EtiketSablonu.standart.rawValue
    @State private var etiketURL: URL?
    @State private var kartURL: URL?
    @State private var etiketHazirlaniyor = false
    @State private var kartHazirlaniyor = false

    var body: some View {
        let kaynak = (kitaplar ?? tumu).filter { !$0.isWithdrawn }
        Form {
            Section {
                Picker("Etiket şablonu", selection: $sablonRaw) {
                    ForEach(EtiketSablonu.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Button("\(kaynak.count) Etiket Hazırla", systemImage: "tag") {
                    let bilgiler = kaynak.map { kitap in
                        SpineLabelBuilder.LabelInfo(
                            callNumber: SpineLabelBuilder.callNumber(category: kitap.category, author: kitap.author, location: kitap.location),
                            title: kitap.title, accessionCode: kitap.accessionCode ?? "",
                            barcodeValue: ISBNFormatter.normalize(kitap.isbn ?? ""), category: kitap.category ?? "", bookID: kitap.id)
                    }
                    let sablon = EtiketSablonu(rawValue: sablonRaw) ?? .standart
                    let profil = LibraryPrintProfile.load(LibraryPrintProfile.labelsKey)
                    etiketURL = nil; etiketHazirlaniyor = true
                    // Binlerce barkod/QR çizimi ana iş parçacığını dondurmasın
                    Task { @MainActor in
                        defer { etiketHazirlaniyor = false }
                        let veri = await Task.detached(priority: .userInitiated) {
                            SpineLabelBuilder.build(bilgiler, template: sablon, profile: profil)
                        }.value
                        // Üretim sürerken şablon değiştiyse eski şablonun PDF'i sunulmaz
                        guard sablonRaw == sablon.rawValue, !veri.isEmpty else { return }
                        etiketURL = GeciciDosya.yaz(veri, ad: "Etiketler.pdf")
                    }
                }
                .disabled(kaynak.isEmpty || etiketHazirlaniyor)
                if etiketHazirlaniyor { ProgressView("Etiketler hazırlanıyor…") }
                if let etiketURL { ShareLink(item: etiketURL) { Label("Etiketleri Paylaş / Yazdır", systemImage: "printer") } }
            } header: {
                Text("Sırt etiketleri")
            } footer: {
                Text("Yer numarası Dewey biçimindeyse (ör. 813.4) etikete o yazılır. Sırt şablonunda üstteki renk bandı kategoriyi gösterir.")
            }
            Section {
                Button("\(kaynak.count) QR Kart Hazırla", systemImage: "qrcode") {
                    let kartlar = kaynak.map { kitap in
                        KitapKartiPDF.Kart(id: kitap.id, baslik: kitap.title, yazar: kitap.author,
                                           yer: kitap.konumMetni ?? "")
                    }
                    kartURL = nil; kartHazirlaniyor = true
                    Task { @MainActor in
                        defer { kartHazirlaniyor = false }
                        let veri = await Task.detached(priority: .userInitiated) { KitapKartiPDF.olustur(kartlar) }.value
                        guard !veri.isEmpty else { return }
                        kartURL = GeciciDosya.yaz(veri, ad: "QR-Kartlar.pdf")
                    }
                }
                .disabled(kaynak.isEmpty || kartHazirlaniyor)
                if kartHazirlaniyor { ProgressView("Kartlar hazırlanıyor…") }
                if let kartURL { ShareLink(item: kartURL) { Label("Kartları Paylaş / Yazdır", systemImage: "printer") } }
            } header: {
                Text("QR kitap kartları")
            } footer: {
                Text("Kartı iPhone kamerasıyla okutmak kitabı Kitap Bul'da doğrudan açar (vitrin, raf başı, tanıtım panosu için).")
            }
        }
        .navigationTitle("Etiket ve QR Kart")
        .onChange(of: sablonRaw) { _, _ in GeciciDosya.sil([etiketURL]); etiketURL = nil }
        .onDisappear { GeciciDosya.sil([etiketURL, kartURL]); etiketURL = nil; kartURL = nil }
    }
}
