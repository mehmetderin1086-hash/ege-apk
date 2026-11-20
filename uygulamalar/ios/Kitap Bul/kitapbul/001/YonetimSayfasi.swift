import SwiftUI
import SwiftData

/// Günlük görevlerden ayrı, bütün yönetim araçlarının tek ve aranabilir girişi.
/// Kendi başına çalışan araçlar doğrudan kendi sayfasında açılır; yalnız Katalog Yönetimi'nin
/// durumuna bağlı araçlar (`KatalogAraci.katalogBaglamiGerekir`) o sayfanın içinden açılır.
struct YonetimSayfasi: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var books: [CatalogBook]
    @Query private var loans: [ActiveLoan]
    @Query private var copies: [BookCopy]
    /// Arama metni kalıcı değildir: Yönetim'e her dönüşte temiz liste açılır.
    @State private var search = ""
    /// Son açılan üç aracın kimlikleri (`Tool.kimlik`), en yenisi başta.
    @AppStorage("managementRecentTools") private var sonKullanilanRaw = ""
    @State private var yarimArsivSayisi = 0
    @State private var bekleyenTaramaSayisi = 0
    /// Katalog Yönetimi sayfasının içinden açılan araç
    @State private var selected: KatalogAraci?
    /// Katalog Yönetimi katmanı ve bekleme olmadan, tek sayfa olarak açılan araç
    @State private var dogrudan: KatalogAraci?
    @State private var advancedCatalog = false
    @State private var aiTools = false
    @State private var settings = false
    @State private var archiveSwitchBackups = false
    /// İlk araç açılışında yakalanır; bu ekran sonradan açılan başka bir kataloğa araç açmaz
    @State private var katalogKirasi: ActiveCatalogLease?
    @State private var katalogHatasi: String?

    /// Satırın açtığı yer: bir katalog aracı ya da Yönetim'e özgü bir sayfa.
    private enum Hedef: Hashable {
        case arac(KatalogAraci)
        case asistan, yapayZeka, katalogYonetimi, katalogGecisiYedekleri
    }
    private struct Tool: Identifiable {
        let hedef: Hedef
        let title: String
        let detail: String
        let icon: String
        /// Görünmeyen ek arama sözcükleri
        var aramaSozcukleri = ""
        var id: Hedef { hedef }

        /// Ad, açıklama ve ikon tek kaynaktan: Katalog Yönetimi'ndeki araç paneliyle aynı.
        static func arac(_ action: KatalogAraci, aramaSozcukleri: String = "") -> Tool {
            Tool(hedef: .arac(action), title: action.aracBasligi ?? "", detail: action.aciklama, icon: action.ikon,
                 aramaSozcukleri: aramaSozcukleri)
        }
        /// `management.<araç>` kimlikleri UI testlerinin sözleşmesidir.
        var kimlik: String {
            switch hedef {
            case .arac(let action): "management.\(String(describing: action))"
            case .asistan: "management.assistant"
            case .yapayZeka: "management.aiTools"
            case .katalogYonetimi: "management.catalog"
            case .katalogGecisiYedekleri: "management.archiveSwitchBackups"
            }
        }
        /// Büyük yazı tanılaması yalnız erişilebilirlik testlerinin izlediği satırlarda
        var taniKimligi: String? {
            switch hedef {
            case .asistan, .yapayZeka: kimlik
            default: nil
            }
        }
    }
    private struct Group: Identifiable {
        let title: String
        let tools: [Tool]
        var id: String { title }
    }
    /// En üstte öğretmenin en sık açtıkları. Bir satır yalnız bir bölümde durur (kimlikler tekil kalır).
    /// Ayarlar'ın açıklamasında geçmeyen bölümleri (otomatik yedek, Gemini bağlantısı, kiosk) aramada bulunur.
    private let sikKullanilanlar = Group(title: "Sık kullanılanlar", tools: [
        .arac(.students), .arac(.reportCenter), .arac(.inventory),
        .arac(.settings, aramaSozcukleri: "yedek bağlantı Gemini yapay zeka kiosk sade yazı tema")
    ])
    private let groups: [Group] = [
        Group(title: "Asistan", tools: [
            Tool(hedef: .asistan, title: "Asistan", detail: "Yazıyla veya sesle sor; değişiklikleri incele", icon: "waveform.and.mic",
                 aramaSozcukleri: "ses yapay zeka AI"),
            Tool(hedef: .yapayZeka, title: "Yapay zekâ araçları", detail: "Öneri, analiz ve kitap kartı", icon: "sparkles",
                 aramaSozcukleri: "AI")
        ]),
        Group(title: "Öğrenciler ve ödünç", tools: [
            .arac(.classLoan), .arac(.loans), .arac(.textbooks), .arac(.champions), .arac(.studentCards)
        ]),
        Group(title: "Raporlar ve baskı", tools: [
            .arac(.statistics), .arac(.usageReport), .arac(.accessionRegister), .arac(.excelExport)
        ]),
        Group(title: "Raf, sayım ve katalog kalitesi", tools: [
            .arac(.shelfScan), .arac(.dataQuality), .arac(.amazonComplete), .arac(.duplicates), .arac(.fieldMerge), .arac(.batchQueue),
            Tool(hedef: .katalogYonetimi, title: "Katalog yönetimi", detail: "Raf görünümü, toplu işlemler, kayıtlı görünümler",
                 icon: "slider.horizontal.3", aramaSozcukleri: "toplu raf kayıtlı görünüm filtre sıralama")
        ]),
        // Katalog geçişi yedekleri de bir yedektir; arama sözcükleri ("yedekleri", "arşiv") korunur
        Group(title: "Yedek ve aktarım", tools: [
            .arac(.csvImport), .arac(.archiveExport), .arac(.archiveImport), .arac(.restoreBackup),
            Tool(hedef: .katalogGecisiYedekleri, title: "Katalog geçişi yedekleri", detail: "Önceki tam arşivleri paylaş ve yeniden aç",
                 icon: "clock.arrow.circlepath", aramaSozcukleri: "arşiv geri dönüş önceki katalog")
        ]),
        // Geri dönüşü zor işler en altta, ayrı bölümde. "Son toplu işi geri al" burada yok: toplu işin
        // geri alma kaydı Katalog Yönetimi sayfasında tutulur, oradaki Araçlar panelinde durur.
        Group(title: "Geri alma", tools: [.arac(.undoSession)])
    ]
    /// Yönetici kimliği isteyen doğrudan araçlar (Katalog Yönetimi'ndeki kapının aynısı)
    private static let yoneticiGerekenler: Set<KatalogAraci> = [.fieldMerge, .duplicates]

    private var term: String { CatalogMatcher.normalize(search) }
    private func filtered(_ group: Group) -> [Tool] {
        guard !term.isEmpty else { return group.tools }
        return group.tools.filter {
            CatalogMatcher.normalize(group.title + " " + $0.title + " " + $0.detail + " " + $0.aramaSozcukleri).contains(term)
        }
    }

    var body: some View {
        NavigationStack {
            // Tembel değil (List yerine VStack): büyük yazıda ekranın altına itilen satırlar
            // erişilebilirlik ağacında kalır. List hücreleri ekrandan çıkınca düşüyordu ve
            // erişilebilirlik denetimi bunları "Dynamic Type kısmen desteklenmiyor" sayıyordu.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    bolum(sikKullanilanlar)
                    if term.isEmpty { bolum(sonKullanilanlar, kimlikOnEki: "recent.") }
                    if term.isEmpty {
                        YonetimBolumu(baslik: "Kütüphane") {
                            // Ana Sayfa ile aynı formül (HomeKPI): iki ekran aynı sayıyı gösterir.
                            let kpi = HomeKPI.hesapla(books: books, copies: copies, loans: loans, eksikleriSay: false)
                            summaryRow("Kitap başlığı", "\(kpi.baslik)")
                            summaryRow("Fiziksel nüsha", "\(kpi.nusha)")
                            summaryRow("Etkin ödünç", "\(kpi.odunc)")
                        }
                    }
                    ForEach(groups) { bolum($0) }
                    if !term.isEmpty && ([sikKullanilanlar] + groups).allSatisfy({ filtered($0).isEmpty }) {
                        ContentUnavailableView.search(text: search)
                            .padding(.top, 40)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.immediately)
            .okunurAltKaydirmaKenari()
            .buttonStyle(YonetimSatirStili())
            .navigationTitle("Yönetim")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Ara")
            .accessibilityHint("Öğrenci, rapor, sayım veya yedek arayın")
            .task {
                yarimArsivSayisi = AutoArchive.staleTemporaryCount().count
                bekleyenTaramaSayisi = await Task.detached { BekleyenTaramaSayaci.say() }.value
            }
            // Onboarding'in "Tablodan içe aktar" düğmesi gibi dış istekler Yönetim açılınca karşılanır.
            .onChange(of: KutuphaneRotasi.shared.bekleyenYonetimAraci, initial: true) { _, arac in
                guard let arac else { return }
                KutuphaneRotasi.shared.bekleyenYonetimAraci = nil
                // Önceki sayfa (tanıtım) kapanırken yeni sayfa açılırsa SwiftUI isteği düşürür.
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    aracAc(arac)
                }
            }
            .sheet(item: $selected) { tool in
                ContentView(presentation: .management, initialTool: tool).sayfaVurgusu()
            }
            .sheet(item: $dogrudan) { tool in
                dogrudanSayfa(tool).sayfaVurgusu()
            }
            .sheet(isPresented: $advancedCatalog) { ContentView(presentation: .management).sayfaVurgusu() }
            .sheet(isPresented: $aiTools) { KapatilabilirSayfa { AIToolsView() }.sayfaVurgusu() }
            .sheet(isPresented: $settings) {
                YoneticiKilidi(baslik: "Ayarlar", sadeModAnahtari: true) { SettingsView() }
                    .sayfaVurgusu()
            }
            .sheet(isPresented: $archiveSwitchBackups) {
                YoneticiKilidi(baslik: "Katalog geçişi yedekleri") { ArchiveSwitchBackupHistoryView(context: modelContext) }
                    .sayfaVurgusu()
            }
            .alert("Araç açılamadı", isPresented: Binding(get: { katalogHatasi != nil }, set: { if !$0 { katalogHatasi = nil } })) {
                Button("Tamam") { katalogHatasi = nil }
            } message: {
                Text(katalogHatasi ?? "")
            }
        }
    }

    @ViewBuilder
    private func bolum(_ group: Group, kimlikOnEki: String = "") -> some View {
        let tools = filtered(group)
        if !tools.isEmpty {
            YonetimBolumu(baslik: group.title) {
                ForEach(tools) { tool in
                    Button { ac(tool.hedef) } label: {
                        toolLabel(tool.title, tool.detail, tool.icon, rozet: rozet(tool.hedef), diagnosticID: tool.taniKimligi)
                    }
                    // Aynı araç iki bölümde görünse de `management.*` kimlikleri tekil kalır.
                    .accessibilityIdentifier(kimlikOnEki + tool.kimlik)
                }
            }
        }
    }

    // MARK: Son açılanlar ve rozetler

    private var tumAraclar: [Tool] { sikKullanilanlar.tools + groups.flatMap(\.tools) }

    private var sonKullanilanlar: Group {
        let kimlikler = sonKullanilanRaw.split(separator: ",").map(String.init)
        let araclar = kimlikler.compactMap { kimlik in tumAraclar.first { $0.kimlik == kimlik } }
        return Group(title: "Son açılanlar", tools: Array(araclar.prefix(3)))
    }

    private func sonKullanilanaEkle(_ tool: Tool) {
        var kimlikler = sonKullanilanRaw.split(separator: ",").map(String.init).filter { $0 != tool.kimlik }
        kimlikler.insert(tool.kimlik, at: 0)
        sonKullanilanRaw = kimlikler.prefix(3).joined(separator: ",")
    }

    /// Araç satırının bağlam rozeti: bekleyen iş varsa sayısı. Boşsa satır sade kalır.
    private func rozet(_ hedef: Hedef) -> String? {
        switch hedef {
        case .arac(.loans):
            let n = LoanKindFilter.gecikenKutuphane(loans: loans).count
            return n > 0 ? "\(n) gecikmiş" : nil
        case .arac(.batchQueue):
            return bekleyenTaramaSayisi > 0 ? "\(bekleyenTaramaSayisi) bekliyor" : nil
        case .arac(.archiveExport):
            return yarimArsivSayisi > 0 ? "\(yarimArsivSayisi) yarım arşiv dosyası" : nil
        default:
            return nil
        }
    }

    private func ac(_ hedef: Hedef) {
        if let tool = tumAraclar.first(where: { $0.hedef == hedef }) { sonKullanilanaEkle(tool) }
        switch hedef {
        case .asistan: DerinBaglanti.shared.hedefSekme = .asistan
        case .yapayZeka: aiTools = true
        case .katalogYonetimi: advancedCatalog = true
        case .katalogGecisiYedekleri: archiveSwitchBackups = true
        case .arac(let action): aracAc(action)
        }
    }

    private func aracAc(_ action: KatalogAraci) {
        switch action {
        case .loans:
            // Ödünç listesi Katalog Yönetimi katmanını açmadan doğrudan Ödünç sekmesine götürür.
            KutuphaneRotasi.shared.oduncBolumu = .etkin
            DerinBaglanti.shared.hedefSekme = .odunc
        case .settings:
            settings = true
        case _ where action.katalogBaglamiGerekir:
            selected = action
        default:
            guard katalogGuncel() else { return }
            if Self.yoneticiGerekenler.contains(action) && !YetkiDurumu.shared.yonetici {
                Task {
                    if await YetkiDurumu.shared.yoneticiOl(), katalogGuncel() { dogrudan = action }
                }
                return
            }
            dogrudan = action
        }
    }

    /// Kök sekmeyle aynı desen (`MainTabView.currentCatalogLease`): katalog ilk kullanımda yakalanır;
    /// arada başka bir kataloğa geçildiyse eski ekrandan araç açılmaz.
    private func katalogGuncel() -> Bool {
        do {
            if katalogKirasi == nil { katalogKirasi = try ActiveCatalogLease.captureCurrent(context: modelContext) }
            try katalogKirasi?.requireCurrent(context: modelContext)
            return true
        } catch {
            katalogHatasi = error.localizedDescription
            return false
        }
    }

    /// Katalog Yönetimi'nin sunduğu sayfaların aynısı, ara katman olmadan.
    @ViewBuilder
    private func dogrudanSayfa(_ action: KatalogAraci) -> some View {
        switch action {
        case .students: StudentsView()
        case .classLoan: ClassLoanView()
        case .textbooks: TextbookDistributionView()
        case .champions: ReadingChampionsView()
        case .usageReport: UsageReportView()
        case .studentCards: StudentCardsView()
        case .reportCenter: KapatilabilirSayfa { RaporMerkezi() }
        case .dataQuality: DataQualityDashboardView()
        case .fieldMerge: FieldMergeView()
        case .inventory: InventoryCountView()
        case .duplicates: DuplicateCleanerView()
        case .shelfScan: KapatilabilirSayfa { ShelfScanPage() }
        // Doğrudan sayfası olmayan araç eski yoldan açılır
        default: ContentView(presentation: .management, initialTool: action)
        }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        LabeledContent { Text(value).foregroundStyle(KitapTema.ikincilMetin) } label: { Text(title).foregroundStyle(Color.primary) }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
    private func toolLabel(_ title: String, _ detail: String, _ icon: String, rozet: String? = nil, diagnosticID: String? = nil) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFontLayoutDiagnostic(diagnosticID.map { $0 + ".title" })
                Text(detail).font(.subheadline).foregroundStyle(KitapTema.ikincilMetin).fixedSize(horizontal: false, vertical: true)
                    .accessibilityFontLayoutDiagnostic(diagnosticID.map { $0 + ".detail" })
                if let rozet {
                    // Okuyucuya ayrı "değer" olarak verilir; metin tekrarlanmasın diye görsel rozet gizlenir.
                    Rozet(metin: rozet, renk: KitapTema.vurgu, ikon: "exclamationmark.circle", satirSiniri: nil)
                        .accessibilityHidden(true)
                }
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(KitapTema.ana)
        }
        .labelStyle(YonetimAracEtiketiStili())
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityValue(rozet ?? "")
    }
}

/// Bekleyen tarama taslağı sayısı. `PendingQueueStore.load` bozuk dosyayı yan klasöre taşıdığı için
/// kullanılmaz: burada yalnız okunur, hiçbir dosya değişmez.
private nonisolated enum BekleyenTaramaSayaci {
    static func say() -> Int {
        let dizin = PendingQueueStore.directoryOverride ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let url = dizin?.appendingPathComponent("BekleyenKuyruk.json"),
              let veri = try? Data(contentsOf: url) else { return 0 }
        return PendingQueueStore.decode(veri)?.count ?? 0
    }
}

/// Gruplu liste görünümündeki bölüm: başlık ve köşeleri yuvarlatılmış satır kutusu,
/// satırlar arasında ayraç. Tembel değildir; Yönetim'deki sabit araç listesi için yeterince kısa.
private struct YonetimBolumu<Icerik: View>: View {
    let baslik: String?
    @ViewBuilder var icerik: Icerik

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let baslik {
                Text(baslik)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0) {
                Group(subviews: icerik) { satirlar in
                    ForEach(Array(satirlar.enumerated()), id: \.element.id) { indeks, satir in
                        if indeks > 0 { Divider().padding(.leading, 16) }
                        satir
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 26))
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}

/// Liste satırı gibi davranan düğme: satırın tamamı dokunulabilir, basılıyken hafif vurgu.
private struct YonetimSatirStili: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .background(configuration.isPressed ? Color(.systemFill) : Color.clear)
    }
}

/// İkon ayrı bir sütundur; bütün metin satırları kendi doğal kutusunda sarılır.
/// Varsayılan Label akışı büyük yazıda devam satırlarını ikonun altına taşıyabiliyor;
/// açık sütunlar çizilen metinle erişilebilir metin kutusunu aynı yerde tutar.
private struct YonetimAracEtiketiStili: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 12) {
            configuration.icon.font(.body)
            configuration.title.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension KatalogAraci: Identifiable {
    var id: Self { self }
}

/// Ekranlar arası filtre geçişleri, ilgili sekme açılınca tek sefer tüketilir.
@Observable
final class KutuphaneRotasi {
    static let shared = KutuphaneRotasi()
    var oduncBolumu: OduncSekmesi.Bolum?
    var oduncAramasi: String?
    var kitapFiltresi: KitapDurumFiltresi?
    var kitapAramasi: String?
    var bugunIadeler = false
    /// Onboarding gibi dış ekranların Yönetim'de açtırdığı araç; Yönetim açılınca tek sefer tüketilir.
    var bekleyenYonetimAraci: KatalogAraci?
    /// kitapbul://odunc ve kitapbul://iade: Ana Sayfa barkod masasını bu kipte açar (tek sefer).
    var bekleyenOduncModu: HizliOduncSayfasi.Mode?
}
