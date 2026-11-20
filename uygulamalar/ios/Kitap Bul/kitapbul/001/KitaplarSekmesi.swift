import SwiftUI
import UIKit
import SwiftData

// MARK: - Filtre ve sıralama

nonisolated enum KitapSiralama: String, CaseIterable, Identifiable {
    case ad = "Ada göre"
    case yazar = "Yazara göre"
    case yeni = "Yeni eklenen"
    case yil = "Yayın yılı"
    case yer = "Dolap / raf"

    var id: Self { self }

    var ikon: String {
        switch self {
        case .ad: "textformat"
        case .yazar: "person"
        case .yeni: "clock"
        case .yil: "calendar"
        case .yer: "square.grid.3x3"
        }
    }
}

enum KitapDurumFiltresi: String, CaseIterable, Identifiable, Codable {
    case tumu = "Tümü"
    /// Ekranda "Rafta"; kayıtlı ham değer "Boşta" kalır (kayıtlı filtreler ve sahne durumu çözülsün).
    case rafta = "Boşta"
    case oduncte = "Ödünçte"
    case gecikmis = "Gecikmiş"
    case eksik = "Eksik bilgi"
    case kapaksiz = "Kapaksız"
    case dusulen = "Düşülenler"

    var id: Self { self }

    /// Kullanıcıya görünen ad (tek ad sözlüğü: "Boşta" yerine "Rafta").
    var ad: String { self == .rafta ? "Rafta" : rawValue }

    /// Filtreler düğmesinin altındaki tek dokunuşluk durum çipleri.
    static let cipler: [KitapDurumFiltresi] = [.tumu, .rafta, .oduncte, .gecikmis]

    var renk: Color {
        switch self {
        case .rafta: KitapTema.basari
        case .oduncte: KitapTema.amazon
        case .gecikmis: .red
        default: KitapTema.ana
        }
    }

    var ikon: String {
        switch self {
        case .tumu: "books.vertical"
        case .rafta: "books.vertical.circle"
        case .oduncte: "person.badge.clock"
        case .gecikmis: "exclamationmark.circle"
        case .eksik: "exclamationmark.triangle"
        case .kapaksiz: "photo.badge.exclamationmark"
        case .dusulen: "archivebox"
        }
    }
}

/// Filtre sayfasındaki tek dokunuşluk hazır süzgeçler.
enum HazirFiltre: String, CaseIterable, Identifiable {
    case isbnEksik, kapaksiz, yerYok, yeniEklenen, uzunSuredirOduncYok
    var id: String { rawValue }

    var ad: String {
        switch self {
        case .isbnEksik: "ISBN’i eksik olanlar"
        case .kapaksiz: "Kapağı olmayanlar"
        case .yerYok: "Dolabı atanmamışlar"
        case .yeniEklenen: "Son 30 günde eklenenler"
        case .uzunSuredirOduncYok: "90 gündür ödünç verilmeyenler"
        }
    }

    var ikon: String {
        switch self {
        case .isbnEksik: "barcode"
        case .kapaksiz: "photo.badge.exclamationmark"
        case .yerYok: "cabinet"
        case .yeniEklenen: "sparkles"
        case .uzunSuredirOduncYok: "eye.slash"
        }
    }

    var filtre: KitapFiltresi {
        switch self {
        case .isbnEksik: KitapFiltresi(eksikAlan: "ISBN")
        case .kapaksiz: KitapFiltresi(eksikAlan: "Kapak")
        case .yerYok: KitapFiltresi(eksikAlan: "Dolap")
        case .yeniEklenen: KitapFiltresi(eklenmeSonGun: 30)
        case .uzunSuredirOduncYok: KitapFiltresi(sonOduncGun: 90)
        }
    }
}

/// Kitaplar sekmesinin filtre durumu (bellek içi süzme; arama veritabanında yapılır).
struct KitapFiltresi: Equatable, Codable {
    var durum: KitapDurumFiltresi = .tumu
    var kategori: String?
    var dolap: String?
    var okuma: String?
    var etiket: String?
    var duzey: String?
    var seri: String?
    /// `SchoolLibraryService.missingFields` anahtarı ("ISBN", "Kapak", "Dolap" …). Eski kayıtlarda yoktur.
    var eksikAlan: String?
    /// Son N gündür hiç ödünç verilmemiş kitaplar.
    var sonOduncGun: Int?
    /// Son N günde eklenen kitaplar.
    var eklenmeSonGun: Int?

    var aktifSayisi: Int {
        [kategori, dolap, okuma, etiket, duzey, seri, eksikAlan].compactMap { $0 }.count + (durum == .tumu ? 0 : 1)
            + (sonOduncGun == nil ? 0 : 1) + (eklenmeSonGun == nil ? 0 : 1)
    }

    /// Son `gun` günde ödünç verilmiş (olay ya da şu an ödünçte) kitapların kimlikleri.
    static func yakinOduncler(events: [LoanEvent], loans: [ActiveLoan], gun: Int, now: Date = .now) -> Set<UUID> {
        let sinir = Calendar.current.date(byAdding: .day, value: -gun, to: now) ?? now
        return Set(events.filter { $0.kind == .lent && $0.date >= sinir }.map(\.bookID)).union(loans.map(\.bookID))
    }

    /// Filtre ve sıralamayı uygular. `oduncSayilari`: kitap kimliği → aktif ödünç sayısı.
    func uygula(_ kitaplar: [CatalogBook], oduncSayilari: [UUID: Int], siralama: KitapSiralama, gecikmisKitaplar: Set<UUID> = [], stoklar: [UUID: LibraryStock] = [:], yakinOduncler: Set<UUID> = [], now: Date = .now) -> [CatalogBook] {
        let suzulmus = suz(kitaplar, oduncSayilari: oduncSayilari, gecikmisKitaplar: gecikmisKitaplar, stoklar: stoklar, yakinOduncler: yakinOduncler, now: now)
        let sirali = KitapSiralayici.sirala(suzulmus.map(SiralamaOgesi.init), siralama: siralama, seriSecili: seri != nil)
        let kimlikli = Dictionary(suzulmus.map { ($0.id, $0) }, uniquingKeysWith: { ilk, _ in ilk })
        return sirali.compactMap { kimlikli[$0] }
    }

    /// Yalnız süzme (sıralamasız): sıralama arka planda yapılabilsin diye ayrıdır.
    func suz(_ kitaplar: [CatalogBook], oduncSayilari: [UUID: Int], gecikmisKitaplar: Set<UUID> = [], stoklar: [UUID: LibraryStock] = [:], yakinOduncler: Set<UUID> = [], now: Date = .now) -> [CatalogBook] {
        let eklenmeSiniri = eklenmeSonGun.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: now) }
        return kitaplar.filter { kitap in
            if durum == .dusulen { guard kitap.isWithdrawn else { return false } } else if kitap.isWithdrawn { return false }
            if let kategori, kitap.kategoriAdi != kategori { return false }
            if let dolap, (kitap.cabinet ?? "") != dolap { return false }
            if let okuma, (kitap.readingStatus ?? "") != okuma { return false }
            if let etiket, !kitap.tagList.contains(where: { $0.caseInsensitiveCompare(etiket) == .orderedSame }) { return false }
            if let duzey, (kitap.readingLevel ?? "") != duzey { return false }
            if let seri, (kitap.series ?? "") != seri { return false }
            if let eksikAlan, !SchoolLibraryService.missingFields(kitap).contains(eksikAlan) { return false }
            if sonOduncGun != nil, yakinOduncler.contains(kitap.id) { return false }
            if let eklenmeSiniri, kitap.addedAt < eklenmeSiniri { return false }
            let disarida = (oduncSayilari[kitap.id] ?? 0) + ((kitap.loanedTo ?? "").isEmpty ? 0 : 1)
            switch durum {
            case .tumu, .dusulen: return true
            case .rafta: return (stoklar[kitap.id]?.available ?? max(0, (kitap.quantity ?? 1) - disarida)) > 0
            case .oduncte: return (stoklar[kitap.id]?.loaned ?? disarida) > 0
            case .gecikmis: return gecikmisKitaplar.contains(kitap.id) || kitap.isOverdue
            case .eksik: return !SchoolLibraryService.missingFields(kitap).isEmpty
            case .kapaksiz: return kitap.coverData == nil
            }
        }
    }
}

// MARK: - Sekme

/// Kitap listesi sekmesi: veritabanında arama (ad, yazar, yayınevi, kategori, ISBN),
/// filtre çipleri, sıralama, liste/kapak görünümü ve ayrıntı sayfası.
struct KitaplarSekmesi: View {
    @Query private var loans: [ActiveLoan]
    @Environment(\.modelContext) private var modelContext

    /// Arama sahne içinde korunur (arka plana gidip dönünce kalır) ama uygulama yeniden açılınca boş başlar;
    /// eski sürümde kalıcıydı ve ertesi gün tek kitaplık liste "kitaplar silindi" izlenimi veriyordu.
    @SceneStorage("kitaplarSearch") private var aramaMetni = ""
    /// Barkodla yapılan aramanın metni: ayrıntıdan dönünce yalnız bu otomatik arama temizlenir.
    @State private var barkodAramaMetni: String?
    @State private var etkinArama = ""
    @State private var filtre = KitapFiltresi()
    @AppStorage("kitaplarSiralama") private var siralamaRaw = KitapSiralama.ad.rawValue
    @AppStorage("kitaplarKapakGorunumu2") private var kapakGorunumu = true
    @State private var secimModu = false
    @State private var secililer = Set<UUID>()
    @State private var yol: [UUID] = []
    private let derinBaglanti = DerinBaglanti.shared
    @State private var aramaGecmisi = AramaGecmisi.hepsi()
    @State private var kayitliFiltreler = KayitliFiltreStore.hepsi()
    @State private var filtreAdiSoruluyor = false
    @State private var yeniFiltreAdi = ""
    @State private var barkodlaAra = false
    /// Arama terimine uyan demirbaşın kitap(lar)ı: listenin üstünde gösterilir. Ara'ya basınca ayrıntı
    /// yalnız kod tek kitaba uyuyor ve arama başka kitap bulmuyorsa açılır.
    @State private var demirbasEslesmeleri: [DemirbasEslesmesi] = []
    @State private var bilgiMesaji: String?
    @SceneStorage("kitaplarFilterState") private var filterJSON = ""
    @State private var restoredFilter = false
    @Environment(\.dynamicTypeSize) private var yaziBoyutu
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Tasarim.efektAnahtari) private var effects = true

    private var siralama: KitapSiralama { KitapSiralama(rawValue: siralamaRaw) ?? .ad }

    @Environment(\.horizontalSizeClass) private var boyutSinifi
    @Namespace private var kapakAlani
    @SceneStorage("kitaplarSection") private var sectionRaw = KitaplarGorunumu.kitaplar.rawValue
    private var gorunum: KitaplarGorunumu { KitaplarGorunumu(rawValue: sectionRaw) ?? .kitaplar }
    private var gorunumBinding: Binding<KitaplarGorunumu> { Binding(get: { gorunum }, set: { sectionRaw = $0.rawValue }) }
    /// iPad (geniş ekran): sol listede seçilen kitap sağda açılır
    @State private var seciliKitapID: UUID?
    @State private var detayYolu: [UUID] = []

    var body: some View {
        Group {
            if boyutSinifi == .regular {
                NavigationSplitView {
                    listeSayfasi(bolunmus: true)
                } detail: {
                    NavigationStack(path: $detayYolu) {
                        Group {
                            if let seciliKitapID {
                                KitapDetaySayfasi(kitapID: seciliKitapID)
                                    .id(seciliKitapID)
                            } else {
                                ContentUnavailableView("Bir kitap seçin", systemImage: "book",
                                                       description: Text("Soldaki listeden bir kitaba dokunun."))
                            }
                        }
                        .navigationDestination(for: UUID.self) { id in
                            KitapDetaySayfasi(kitapID: id)
                        }
                    }
                }
            } else {
                NavigationStack(path: $yol) {
                    listeSayfasi(bolunmus: false)
                        .navigationDestination(for: UUID.self) { id in
                            // Listedeki sırayla sağa-sola kaydırarak kitap kitap gezilir
                            KitapSayfalari(baslangic: id)
                                .zoomHedefi(id, kapakAlani)
                        }
                }
            }
        }
        // QR kartından gelen kitap ayrıntısı
        .onChange(of: derinBaglanti.bekleyenKitapID, initial: true) { _, id in
            guard let id else { return }
            kitabiAc(id)
            derinBaglanti.bekleyenKitapID = nil
        }
    }

    /// Ayrıntıyı doğrudan açar: iPad'de sağ sütunda, iPhone'da gezinme yığınında.
    private func kitabiAc(_ id: UUID) {
        if boyutSinifi == .regular {
            seciliKitapID = id
            detayYolu = []
        } else {
            yol = [id]
        }
    }

    private func listeSayfasi(bolunmus: Bool) -> some View {
        KitapSorgusu(arama: etkinArama) { kitaplar in
            VStack(spacing: 0) {
            // Libib tarzı üst bölümler: Kitaplar / Kategoriler / Seriler
            if boyutSinifi == .compact || yaziBoyutu >= .xxLarge {
                Menu {
                    Picker("Katalog bölümü", selection: gorunumBinding) {
                        ForEach(KitaplarGorunumu.allCases) { bolum in
                            Label(bolum.rawValue, systemImage: bolum.ikon).tag(bolum)
                        }
                    }
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: gorunum.ikon)
                            .accessibilityHidden(true)
                        Text(gorunum.rawValue)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.up.chevron.down")
                            .accessibilityHidden(true)
                    }
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Katalog bölümü")
                .accessibilityValue(gorunum.rawValue)
                .accessibilityHint("Kitaplar, Kategoriler, Seriler veya Raflar bölümünü seçin.")
                .accessibilityIdentifier("catalog.section.menu")
                .padding(.horizontal)
                .padding(.top, 6)
            } else {
                Picker("Görünüm", selection: gorunumBinding.animation(reduceMotion || !effects ? nil : .snappy)) { ForEach(KitaplarGorunumu.allCases) { Label($0.rawValue, systemImage: $0.ikon).tag($0) } }
                    .pickerStyle(.segmented).padding(.horizontal).padding(.top, 6)
            }
            switch gorunum {
            case .kategoriler:
                KategoriIzgarasi(kitaplar: kitaplar.filter { !$0.isWithdrawn }) { kategori in
                    filtre.kategori = kategori
                    withAnimation(reduceMotion || !effects ? nil : .snappy) { sectionRaw = KitaplarGorunumu.kitaplar.rawValue }
                }
            case .seriler:
                SeriListesi(kitaplar: kitaplar.filter { !$0.isWithdrawn }) { seri in
                    filtre.seri = seri
                    withAnimation(reduceMotion || !effects ? nil : .snappy) { sectionRaw = KitaplarGorunumu.kitaplar.rawValue }
                }
            case .raflar:
                RafKonumListesi(kitaplar: kitaplar.filter { !$0.isWithdrawn }, loans: loans,
                                onSelect: bolunmus ? { id in seciliKitapID = id; detayYolu = [] } : nil)
            case .kitaplar:
            if !demirbasEslesmeleri.isEmpty { demirbasSeritleri }
            KitapListesiIcerigi(
                tumKitaplar: kitaplar,
                loans: loans,
                filtre: $filtre,
                siralamaRaw: $siralamaRaw,
                kapakGorunumu: kapakGorunumu && !secimModu && !yaziBoyutu.isAccessibilitySize,
                arama: etkinArama,
                demirbasBulundu: !demirbasEslesmeleri.isEmpty,
                secimModu: secimModu,
                onToggleSelection: {
                    withAnimation(reduceMotion || !effects ? nil : .snappy) {
                        secimModu.toggle()
                        secililer.removeAll()
                    }
                },
                secililer: $secililer,
                onSec: bolunmus ? { id in
                    seciliKitapID = id
                    detayYolu = []
                } : nil,
                seciliID: bolunmus ? seciliKitapID : nil,
                kapakAlani: kapakAlani,
                isActive: bolunmus || yol.isEmpty
            )
            }
            }
        }
        .navigationTitle("Kitaplar")
        .navigationBarTitleDisplayMode(.inline)
        .kenardanSekmeKaydir()
        // İstem kısa kalır: uzun yer tutucu metin büyük yazıda kırpılıyor (erişilebilirlik denetimi).
        // Nelerde arandığı arama açılınca öneri satırında yazar.
        .searchable(text: $aramaMetni, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Ara")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .searchSuggestions {
            if aramaMetni.isEmpty {
                Label("Ad, yazar, ISBN veya demirbaş yazın", systemImage: "info.circle")
                    .foregroundStyle(KitapTema.ikincilMetin)
            }
            if aramaMetni.isEmpty && !aramaGecmisi.isEmpty {
                Section("Son aramalar") {
                    ForEach(aramaGecmisi, id: \.self) { terim in
                        Label(terim, systemImage: "clock.arrow.circlepath").searchCompletion(terim)
                    }
                    Button("Geçmişi temizle", role: .destructive) {
                        AramaGecmisi.temizle()
                        aramaGecmisi = []
                    }
                }
            }
        }
        .onSubmit(of: .search) {
            AramaGecmisi.ekle(aramaMetni)
            aramaGecmisi = AramaGecmisi.hepsi()
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            // Demirbaş kodu tek kitaba uyuyorsa ayrıntı doğrudan açılır. Yazarken değil, Ara'ya basınca:
            // "D-12" yazılırken "D-1" nüshası kendiliğinden açılmasın. Demirbaşlar çoğu okulda düz sayıdır
            // (1, 2 … 1984): arama başka kitap da buluyorsa ("1984" romanı) seçim şeritte kullanıcıya kalır.
            if let kitap = DemirbasArama.kitap(aramaMetni, context: modelContext),
               !aramaBaskaKitapBulur(aramaMetni, haric: kitap.id) {
                kitabiAc(kitap.id)
            }
        }
        .onChange(of: yol) { eski, yeni in
            guard yeni.isEmpty, !eski.isEmpty, let barkod = barkodAramaMetni else { return }
            if aramaMetni == barkod { aramaMetni = ""; etkinArama = "" }
            barkodAramaMetni = nil
        }
        .onChange(of: etkinArama, initial: true) { _, terim in
            demirbasEslesmeleri = DemirbasArama.kitaplar(terim, context: modelContext).map {
                DemirbasEslesmesi(kod: terim, kitapID: $0.id, baslik: $0.title)
            }
        }
        .task(id: aramaMetni) {
            // Yazma bitince ara (her harfte 50 bin kayıt sorgulanmasın)
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            etkinArama = aramaMetni.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .onAppear {
            if !restoredFilter {
                if let data = filterJSON.data(using: .utf8), let saved = try? JSONDecoder().decode(KitapFiltresi.self, from: data) { filtre = saved }
                restoredFilter = true
            }
            applyPendingRoute()
        }
        .onChange(of: KutuphaneRotasi.shared.kitapFiltresi) { _, _ in applyPendingRoute() }
        .onChange(of: KitapFiltreRotasi.shared.bekleyen) { _, _ in applyPendingRoute() }
        .onChange(of: KutuphaneRotasi.shared.kitapAramasi) { _, _ in applyPendingRoute() }
        .onChange(of: filtre) { _, value in
            if let data = try? JSONEncoder().encode(value) { filterJSON = String(decoding: data, as: UTF8.self) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { barkodlaAra = true } label: { Label("Barkodla ara", systemImage: "barcode.viewfinder") }
                    .accessibilityIdentifier("books.barcodeSearch")
                Menu {
                    Menu("Kitap ekle", systemImage: "plus.circle") {
                        ForEach(HizliEylem.allCases) { action in
                            Button(action.baslik, systemImage: action.ikon) {
                                derinBaglanti.bekleyenEylem = action
                                derinBaglanti.hedefSekme = .katalog
                            }
                        }
                    }
                    Button(kapakGorunumu ? "Liste görünümü" : "Kapak görünümü", systemImage: kapakGorunumu ? "list.bullet" : "square.grid.2x2") { kapakGorunumu.toggle() }
                    if !kayitliFiltreler.isEmpty {
                        Section("Kayıtlı filtreler") {
                            ForEach(kayitliFiltreler) { saved in
                                Button(saved.ad) { filtre = saved.filtre; siralamaRaw = saved.siralama }
                            }
                        }
                        Menu("Kayıtlı filtreyi sil") {
                            ForEach(kayitliFiltreler) { saved in
                                Button(saved.ad, role: .destructive) { kayitliFiltreyiSil(saved) }
                            }
                        }
                    }
                    Button("Bu filtreyi kaydet…", systemImage: "bookmark") { yeniFiltreAdi = ""; filtreAdiSoruluyor = true }
                        .disabled(filtre.aktifSayisi == 0)
                } label: { Label("Kitap seçenekleri", systemImage: "ellipsis.circle") }
                    .accessibilityIdentifier("books.options")
            }
        }
        .fullScreenCover(isPresented: $barkodlaAra) {
            ZStack(alignment: .topTrailing) {
                LiveISBNScannerView { kod in
                    barkodlaAra = false
                    barkodSonucu(kod)
                } onCancel: {
                    barkodlaAra = false
                }
                .ignoresSafeArea()
                Button {
                    barkodlaAra = false
                } label: {
                    Label("Kapat", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                }
                .padding()
                .accessibilityLabel("Barkod aramasını kapat")
            }
        }
        .alert("Filtreyi kaydet", isPresented: $filtreAdiSoruluyor) {
            TextField("Ad (örn. 5. sınıf romanları)", text: $yeniFiltreAdi)
            Button("Kaydet") {
                let ad = yeniFiltreAdi.trimmingCharacters(in: .whitespaces)
                guard !ad.isEmpty else { return }
                KayitliFiltreStore.ekle(KayitliFiltre(ad: ad, filtre: filtre, siralama: siralamaRaw))
                kayitliFiltreler = KayitliFiltreStore.hepsi()
            }
            Button("Vazgeç", role: .cancel) { }
        } message: {
            Text("Şu anki filtre ve sıralama tek dokunuşla yeniden uygulanabilir.")
        }
        .alert("İşlem tamamlanamadı", isPresented: Binding(get: { bilgiMesaji != nil }, set: { if !$0 { bilgiMesaji = nil } })) {
            Button("Tamam", role: .cancel) { }
        } message: {
            Text(bilgiMesaji ?? "")
        }
    }

    /// Kod birden çok kitapta kayıtlıysa her biri ayrı şerittir ve uyarı yazılır; hiçbiri kendiliğinden açılmaz.
    private var demirbasSeritleri: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(demirbasEslesmeleri, id: \.kitapID) { demirbasSeridi($0) }
            if demirbasEslesmeleri.count > 1 {
                Label("Bu demirbaş \(demirbasEslesmeleri.count) kitapta kayıtlı. Demirbaş defterinden düzeltin.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(KitapTema.ikincilMetin)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
                    .padding(.top, 6)
            }
        }
    }

    /// "Demirbaş 2024-0153 · Kitap adı": aranan kod bir nüshanın ya da kitabın demirbaşıdır.
    private func demirbasSeridi(_ eslesme: DemirbasEslesmesi) -> some View {
        Button { kitabiAc(eslesme.kitapID) } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Demirbaş \(eslesme.kod)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(KitapTema.ikincilMetin)
                    Text(eslesme.baslik.isEmpty ? "Adsız kayıt" : eslesme.baslik)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            } icon: {
                Image(systemName: "number.square.fill").foregroundStyle(KitapTema.ana)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.top, 6)
        .accessibilityHint("Kitabın ayrıntısını açar")
        .accessibilityIdentifier("books.accessionMatch")
    }

    /// Arama terimi (Ara'ya basılan haliyle) verilen kitaptan başka bir kitap buluyor mu? En çok iki kayıt okunur.
    private func aramaBaskaKitapBulur(_ terim: String, haric: UUID) -> Bool {
        guard let kosul = KitapAramaKosulu.predicate(for: terim.trimmingCharacters(in: .whitespacesAndNewlines)) else { return true }
        var istek = FetchDescriptor<CatalogBook>(predicate: kosul)
        istek.fetchLimit = 2
        return ((try? modelContext.fetch(istek)) ?? []).contains { $0.id != haric }
    }

    /// Barkodla arama: demirbaş etiketi ya da tek kayda uyan ISBN ayrıntıyı doğrudan açar. Eşleşme
    /// yoksa kod aramada kalır; boş sonuçta "Bu ISBN ile kataloğa ekle" sunulur. Demirbaş birden çok
    /// kitapta kayıtlıysa açılmaz: şeritler ve uyarı görünür.
    private func barkodSonucu(_ kod: String) {
        let isbn = ISBNFormatter.repair(kod)
        aramaMetni = isbn.isEmpty ? kod : isbn
        barkodAramaMetni = aramaMetni
        filtre = KitapFiltresi()
        sectionRaw = KitaplarGorunumu.kitaplar.rawValue
        if let kitap = DemirbasArama.kitap(kod, context: modelContext) { kitabiAc(kitap.id); return }
        let barkod = ISBNFormatter.isValidISBN13(isbn) ? isbn : ISBNFormatter.normalize(kod)
        // Düşülmüş kayıt da bulunur: aynı ISBN ile yeni kayıt açılmasın, ayrıntıda "Düşüldü" görünsün.
        let adaylar = (try? OkutCozumleyici.isbnAdaylari(barkod, dusulenlerDahil: true, context: modelContext)) ?? []
        if adaylar.count == 1, let kitap = adaylar.first { kitabiAc(kitap.id) }
    }

    private func kayitliFiltreyiSil(_ kayit: KayitliFiltre) {
        Task {
            guard await YetkiDurumu.shared.yoneticiOl() else {
                bilgiMesaji = YetkiDurumu.shared.hata ?? "Kayıtlı filtreyi silmek için yönetici kimliği gerekir."
                return
            }
            KayitliFiltreStore.sil(kayit.id)
            kayitliFiltreler = KayitliFiltreStore.hepsi()
        }
    }

    private func applyPendingRoute() {
        if let hazir = KitapFiltreRotasi.shared.bekleyen {
            filtre = hazir
            aramaMetni = ""
            etkinArama = ""
            sectionRaw = KitaplarGorunumu.kitaplar.rawValue
            KitapFiltreRotasi.shared.bekleyen = nil
        }
        if let status = KutuphaneRotasi.shared.kitapFiltresi {
            filtre = KitapFiltresi(durum: status)
            aramaMetni = ""
            etkinArama = ""
            sectionRaw = KitaplarGorunumu.kitaplar.rawValue
            KutuphaneRotasi.shared.kitapFiltresi = nil
        }
        if let search = KutuphaneRotasi.shared.kitapAramasi {
            aramaMetni = search
            etkinArama = search
            filtre = KitapFiltresi()
            sectionRaw = KitaplarGorunumu.kitaplar.rawValue
            KutuphaneRotasi.shared.kitapAramasi = nil
        }
    }
}

/// Arama terimine uyan demirbaşın kitabı (kod birden çok kitapta kayıtlıysa her biri ayrı eşleşme).
struct DemirbasEslesmesi: Equatable {
    let kod: String
    let kitapID: UUID
    let baslik: String
}

/// Kitaplar sekmesinin arama koşulu. Tüm ifadeler SwiftData'nın SQL'e çevirebildiği
/// biçimde yazılmıştır (isteğe bağlı alanlarda `?.contains(...) ?? false`); testler bunu korur.
enum KitapAramaKosulu {
    /// Terim boşsa `nil` (tüm katalog).
    static func predicate(for arama: String) -> Predicate<CatalogBook>? {
        let terim = CatalogMatcher.normalize(arama)
        var rakamlar = arama.filter(\.isNumber)
        if terim.isEmpty && rakamlar.isEmpty { return nil }
        // Barkod araması mı, yazılan rakam sayısıyla karar verilir (aşağıdaki kısaltma kararı değiştirmez).
        let barkodAramasi = rakamlar.count >= 5 && rakamlar.count * 2 >= arama.count
        // Elle yazılan geçerli ISBN-10, ISBN-13 olarak saklanan kayıtta yalnız ilk 9 hanesiyle
        // geçer (kontrol haneleri farklıdır). Kontrol hanesi tutmayan 10 rakam olduğu gibi aranır.
        if rakamlar.count == 10, BookEditorValidation.normalizedISBN(arama) != nil { rakamlar = String(rakamlar.prefix(9)) }
        // Tersi de: elle yazılan 978'li ISBN-13, ISBN-10 olarak saklanan kayıtta yalnız ortadaki 9 hanesiyle geçer.
        if rakamlar.count == 13, rakamlar.hasPrefix("978"), ISBNFormatter.isValidISBN13(rakamlar) { rakamlar = String(rakamlar.dropFirst(3).prefix(9)) }
        if barkodAramasi {
            // Barkod/ISBN araması (tireli yazım da eşleşsin diye yalnız rakamlar)
            return #Predicate<CatalogBook> { ($0.isbn?.contains(rakamlar) ?? false) }
        }
        // Çok kelimeli sorguda kelimeler ayrı ayrı aranır: "tolstoy savas" da
        // "savas ve baris … tolstoy" anahtarını bulur (sıra ve bitişiklik şartı yok).
        let kelimeler = CatalogMatcher.aramaKelimeleri(terim)
        switch kelimeler.count {
        case 2:
            let a = kelimeler[0], b = kelimeler[1]
            return #Predicate<CatalogBook> {
                (($0.searchKey?.contains(a) ?? false) && ($0.searchKey?.contains(b) ?? false))
                    || $0.title.localizedStandardContains(arama)
            }
        case 3:
            let a = kelimeler[0], b = kelimeler[1], c = kelimeler[2]
            return #Predicate<CatalogBook> {
                (($0.searchKey?.contains(a) ?? false) && ($0.searchKey?.contains(b) ?? false)
                    && ($0.searchKey?.contains(c) ?? false))
                    || $0.title.localizedStandardContains(arama)
            }
        default:
            // Tek kelime ("seker seker" gibi yinelenen yazım da tek kelimedir)
            let tek = kelimeler.first ?? terim
            return #Predicate<CatalogBook> {
                ($0.searchKey?.contains(tek) ?? false) || $0.title.localizedStandardContains(arama)
            }
        }
    }
}

/// Arama terimini veritabanı sorgusuna çevirir: `searchKey` (aksansız ad/yazar/kategori/yayınevi)
/// ve ISBN üzerinde. Terim boşsa tüm katalog.
private struct KitapSorgusu<Icerik: View>: View {
    @Query private var kitaplar: [CatalogBook]
    private let icerik: ([CatalogBook]) -> Icerik

    init(arama: String, @ViewBuilder icerik: @escaping ([CatalogBook]) -> Icerik) {
        self.icerik = icerik
        if let kosul = KitapAramaKosulu.predicate(for: arama) {
            _kitaplar = Query(filter: kosul, sort: \CatalogBook.title)
        } else {
            _kitaplar = Query(sort: \CatalogBook.title)
        }
    }

    var body: some View { icerik(kitaplar) }
}

/// Kitaplar listesinin kaydırma izi: görünen kitaplar, sıraları ve kaydırma evresi. Gözlenmeyen bir
/// sınıftır; kaydırırken değişmesi görünümü yeniden çizdirmez. (Önce bunlar @State ve @AppStorage
/// idi: her kapak görünür olup çıktıkça 2.500+ kitabın Türkçe sıralaması ve stok hesabı yeniden
/// yapılıyor, kapak ızgarası kaydırırken donuyordu.)
private final class KitapKaydirmaIzi {
    /// Son görülen kitap; ayrıntıdan dönüşte ve yeniden açılışta oradan devam edilir.
    static let capaAnahtari = "kitaplarScrollAnchor"
    var gorunen = Set<UUID>()
    var sira: [UUID: Int] = [:]
    /// Geri yükleme bitti; bundan sonraki kaydırmalar kullanıcınındır.
    var hazir = false
    var kullaniciKaydiriyor = false

    var capa: String {
        get { UserDefaults.standard.string(forKey: Self.capaAnahtari) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.capaAnahtari) }
    }

    /// Görünen sıra değişti (arama, filtre, sıralama, veri): çapa listede yoksa bırakılır.
    func sirayiKur(_ ids: [UUID]) {
        var yeniSira: [UUID: Int] = [:]
        yeniSira.reserveCapacity(ids.count)
        for (sira, id) in ids.enumerated() where yeniSira[id] == nil { yeniSira[id] = sira }
        sira = yeniSira
        gorunen.formIntersection(yeniSira.keys)
        if let kayitli = UUID(uuidString: capa), yeniSira[kayitli] == nil { capa = "" }
        hazir = false
    }

    func gorunurluk(_ id: UUID, _ gorunur: Bool, etkin: Bool) {
        if gorunur { gorunen.insert(id) } else { gorunen.remove(id) }
        if etkin, hazir, kullaniciKaydiriyor { gorunenCapayiKaydet() }
    }

    func evre(_ evre: ScrollPhase, etkin: Bool) {
        guard etkin, hazir else { return }
        switch evre {
        case .interacting, .decelerating, .animating:
            // .tracking yalnız dokunma olabilir; NavigationLink'e dokunmak kaydırma sayılmaz.
            kullaniciKaydiriyor = true
        case .idle:
            if kullaniciKaydiriyor { gorunenCapayiKaydet() }
            kullaniciKaydiriyor = false
        case .tracking:
            break
        @unknown default:
            break
        }
    }

    func durdur() {
        hazir = false
        kullaniciKaydiriyor = false
    }

    private func gorunenCapayiKaydet() {
        guard let ilk = gorunen.min(by: { sira[$0, default: .max] < sira[$1, default: .max] }) else { return }
        let metin = ilk.uuidString
        if capa != metin { capa = metin }
    }
}

/// Kaydırma konumunu (geri yükleme ve çapa) taşıyan sarmalayıcı. Konum bağlamı kaydırırken
/// sık değişir; bu yüzden yalnız bu küçük görünüm yeniden çizilir, liste içeriği değer olarak
/// hazır gelir ve katalog hesapları yinelenmez.
private struct KitapKaydirmaKonumu<Icerik: View>: View {
    let ids: [UUID]
    let isActive: Bool
    let iz: KitapKaydirmaIzi
    let icerik: Icerik
    @State private var konum: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            icerik
                .scrollPosition(id: $konum, anchor: .top)
                .onScrollPhaseChange { _, evre in iz.evre(evre, etkin: isActive) }
                .task(id: isActive ? ids : []) {
                    guard isActive else { return }
                    await geriYukle(proxy)
                }
                .onChange(of: konum) { _, yeni in
                    if isActive, iz.hazir, iz.kullaniciKaydiriyor, let yeni, iz.sira[yeni] != nil {
                        iz.capa = yeni.uuidString
                    }
                }
                .onChange(of: isActive) { _, etkin in if !etkin { iz.durdur() } }
                .onDisappear { iz.durdur() }
        }
    }

    /// Liste ve kapak görünümü aynı kitap kimliğine döner; silinen/filtrelenen kimlik ilk satıra düşer.
    private func geriYukle(_ proxy: ScrollViewProxy) async {
        iz.durdur()
        iz.gorunen = []
        let kayitli = UUID(uuidString: iz.capa)
        let hedef = kayitli.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first
        konum = hedef
        await Task.yield()
        guard !Task.isCancelled else { return }
        if let hedef { proxy.scrollTo(hedef, anchor: .top) }
        await Task.yield()
        guard !Task.isCancelled else { return }
        iz.hazir = true
    }
}

private struct KitapListesiIcerigi: View {
    let tumKitaplar: [CatalogBook]
    let loans: [ActiveLoan]
    @Binding var filtre: KitapFiltresi
    @Binding var siralamaRaw: String
    let kapakGorunumu: Bool
    /// Etkin arama terimi; boş sonuçta "Kataloğa ekle" yolunu belirler.
    let arama: String
    /// Terim bir demirbaşa uydu ve kitap listenin üstündeki şeritte: boş liste "bulunamadı" demez.
    var demirbasBulundu = false
    var secimModu = false
    var onToggleSelection: (() -> Void)? = nil
    @Binding var secililer: Set<UUID>
    /// iPad bölünmüş görünüm: dokunulan kitap yan sütunda açılır (gezinme yerine)
    var onSec: ((UUID) -> Void)? = nil
    var seciliID: UUID? = nil
    var kapakAlani: Namespace.ID? = nil
    /// Telefon ayrıntısı açıkken katalog görünürlük olayları konumu değiştirmemeli.
    var isActive = true

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var yaziBoyutu
    @Query private var copies: [BookCopy]
    @Query private var reservations: [Reservation]
    @State private var filtreAcik = false
    @State private var topluSoru: TopluSoru?
    @State private var topluMetin1 = ""
    @State private var topluMetin2 = ""
    @State private var silmeOnayi = false
    @State private var dusmeOnayi = false
    @State private var topluMesaj: String?
    /// Son toplu işlemin kalıcı geri alma kaydı (uygulama kapanınca da durur).
    @State private var geriAlmaKaydi: CatalogBulkUndoRecord? = CatalogBulkUndoStore.oku()
    /// Filtre, sıralama ve stok hesabı: girdi anahtarı değişmedikçe yeniden yapılmaz, sıralama arka planda koşar.
    @State private var hesap: ListeHesabi?
    @State private var baskiListesi: [CatalogBook] = []
    @State private var csvListesi: [CatalogBook] = []
    /// Kaydırma izi gözlenmeyen bir nesnede: kaydırırken değişmesi bu görünümü (dolayısıyla
    /// tüm kataloğun süzme, Türkçe sıralama ve stok hesabını) yeniden çalıştırmaz.
    @State private var iz = KitapKaydirmaIzi()

    fileprivate enum TopluSoru: String, Identifiable {
        case kategori, yer, etiket
        var id: String { rawValue }
    }

    private var siralama: KitapSiralama { KitapSiralama(rawValue: siralamaRaw) ?? .ad }
    private var aramaVar: Bool { !arama.isEmpty }
    private var oduncSayilari: [UUID: Int] { SchoolLibraryService.loanCounts(loans) }

    private var hesapAnahtari: HesapAnahtari {
        HesapAnahtari.kur(filtre: filtre, siralama: siralamaRaw, kitaplar: tumKitaplar, loans: loans,
                          copies: copies, reservations: reservations)
    }

    /// Senkron hesap: yalnız ilk çizimde ve sıralama bitene kadar kullanılır.
    private func anindaHesap(_ anahtar: HesapAnahtari) -> ListeHesabi {
        let gecikmis = SchoolLibraryService.overdueBookIDs(loans, books: tumKitaplar)
        let stoklar = SchoolLibraryService.stockByBook(books: tumKitaplar, loans: loans, copies: copies, reservations: reservations)
        let kitaplar = filtre.uygula(tumKitaplar, oduncSayilari: oduncSayilari, siralama: siralama,
                                     gecikmisKitaplar: gecikmis, stoklar: stoklar, yakinOduncler: yakinOduncler())
        return ListeHesabi(anahtar: anahtar, kitaplar: kitaplar, stoklar: stoklar, gecikmis: gecikmis)
    }

    private func yakinOduncler() -> Set<UUID> {
        guard let gun = filtre.sonOduncGun else { return [] }
        return KitapFiltresi.yakinOduncler(events: LoanHistoryStore.all, loans: loans, gun: gun)
    }

    private func hesabiYenile(_ anahtar: HesapAnahtari) async {
        guard ListeHesabi.yenidenGerekli(mevcut: hesap, anahtar: anahtar) else { return }
        let gecikmis = SchoolLibraryService.overdueBookIDs(loans, books: tumKitaplar)
        let stoklar = SchoolLibraryService.stockByBook(books: tumKitaplar, loans: loans, copies: copies, reservations: reservations)
        let suzulmus = filtre.suz(tumKitaplar, oduncSayilari: oduncSayilari, gecikmisKitaplar: gecikmis,
                                  stoklar: stoklar, yakinOduncler: yakinOduncler())
        let ogeler = suzulmus.map(SiralamaOgesi.init)
        let secilen = siralama
        let seriSecili = filtre.seri != nil
        // Modeller arka plana geçmez; yalnız (kimlik, ad, yazar …) değerleri sıralanır.
        let sira = await Task.detached(priority: .userInitiated) {
            KitapSiralayici.sirala(ogeler, siralama: secilen, seriSecili: seriSecili)
        }.value
        guard !Task.isCancelled else { return }
        let kimlikli = Dictionary(suzulmus.map { ($0.id, $0) }, uniquingKeysWith: { ilk, _ in ilk })
        hesap = ListeHesabi(anahtar: anahtar, kitaplar: sira.compactMap { kimlikli[$0] }, stoklar: stoklar, gecikmis: gecikmis)
    }

    /// Ekranda gösterilen sıralı liste. Silinmiş modeller son hesaptan elenir.
    private var guncelKitaplar: [CatalogBook] {
        hesap?.kitaplar.filter { !$0.isDeleted && $0.modelContext != nil } ?? anindaHesap(hesapAnahtari).kitaplar
    }
    private var kategoriler: [String] {
        // Türkçe alfabe: Çocuk C'den sonra, Şiir S'den sonra gelsin
        Array(Set(tumKitaplar.map(\.kategoriAdi)))
            .sorted { $0.compare($1, locale: Locale(identifier: "tr_TR")) == .orderedAscending }
    }
    private var etiketler: [String] {
        Array(Set(tumKitaplar.flatMap(\.tagList)))
            .sorted { $0.compare($1, locale: Locale(identifier: "tr_TR")) == .orderedAscending }
    }
    private var seriler: [String] {
        Array(Set(tumKitaplar.compactMap(\.series).filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private var dolaplar: [String] {
        // "D9" "D12"den önce gelsin (sayısal karşılaştırma)
        Array(Set(tumKitaplar.compactMap(\.cabinet).filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        // Gecikme ve stok tabloları çizim başına bir kez kurulur; satırlar hazır tablodan okur
        // (önceden her satır tüm ödünç/nüsha/rezervasyon dizilerini yeniden süzüyordu)
        let anahtar = hesapAnahtari
        let guncel = hesap ?? anindaHesap(anahtar)
        let baglam = SatirBaglami(stoklar: guncel.stoklar, gecikmis: guncel.gecikmis)
        let liste = hesap == nil ? guncel.kitaplar : guncelKitaplar
        let ids = liste.map(\.id)
        VStack(spacing: 0) {
            filtreCubugu
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(liste.count) başlık")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    siralamaMenusu
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if let onToggleSelection {
                    Button(action: onToggleSelection) {
                        Text(secimModu ? "Bitti" : "Seç")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("books.selection")
                    .accessibilityHint("Birden çok kitabı seçip toplu işlem yapın")
                }
                NavigationLink {
                    RaporMerkezi(kitaplar: liste)
                } label: {
                    Label("Raporlar ve dışa aktarım", systemImage: "doc.richtext")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Bu listeyi raporla, CSV'ye aktar ya da etiket bas")
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            if liste.isEmpty && demirbasBulundu && filtre.aktifSayisi == 0 {
                // Kitap şeritte bulundu; "Sonuç yok · Kataloğa ekle" onu yalanlamasın (var olan kitap yeniden eklenmesin).
                Spacer()
            } else if liste.isEmpty {
                bosDurum
                    .frame(maxHeight: .infinity)
            } else if kapakGorunumu {
                KitapKaydirmaKonumu(ids: ids, isActive: isActive, iz: iz, icerik:
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 12)], spacing: 16) {
                        ForEach(liste) { kitap in
                            Group {
                            if let onSec {
                                Button { onSec(kitap.id) } label: {
                                    KapakHucresi(kitap: kitap, stok: baglam.stok(kitap), gecikmis: baglam.gecikmis.contains(kitap.id))
                                        .zoomKaynagi(kitap.id, kapakAlani)
                                }
                                .buttonStyle(.kitapSade)
                            } else {
                                NavigationLink(value: kitap.id) {
                                    KapakHucresi(kitap: kitap, stok: baglam.stok(kitap), gecikmis: baglam.gecikmis.contains(kitap.id))
                                        .zoomKaynagi(kitap.id, kapakAlani)
                                }
                                .buttonStyle(.kitapSade)
                            }
                            }
                            .id(kitap.id)
                            .onScrollVisibilityChange(threshold: 0.5) { visible in iz.gorunurluk(kitap.id, visible, etkin: isActive) }
                        }
                    }
                    .scrollTargetLayout()
                    .padding()
                }
                .contentMargins(.bottom, 12, for: .scrollContent)
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("books.scroll.grid"))
            } else {
                KitapKaydirmaKonumu(ids: ids, isActive: isActive, iz: iz, icerik:
                List(selection: $secililer) {
                    if let seri = filtre.seri {
                        seriOzeti(seri, liste)
                    }
                    if bolumlu {
                        // A–Z bölümleri ve sağ kenarda harf dizini (Türkçe harfler ayrı)
                        ForEach(AlfabeBolumleri.grupla(liste, anahtar: siralama == .yazar ? { $0.author } : { $0.title }), id: \.harf) { bolum in
                            Section(bolum.harf) {
                                ForEach(bolum.kitaplar) { satir($0, baglam) }
                            }
                            .sectionIndexLabel(bolum.harf)
                        }
                    } else {
                        ForEach(liste) { satir($0, baglam) }
                    }
                }
                .listStyle(.plain)
                // Son satır yüzen + düğmesinin altında kalmasın
                .contentMargins(.bottom, 12, for: .scrollContent)
                .listSectionIndexVisibility(bolumlu ? .visible : .hidden)
                .environment(\.editMode, .constant(secimModu ? .active : .inactive))
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("books.scroll.list"))
            }
        }
        .background(Color(.systemGroupedBackground))
        .task(id: anahtar) { await hesabiYenile(anahtar) }
        .safeAreaInset(edge: .bottom) {
            if secimModu { topluIslemCubugu(liste) }
        }
        // Ayrıntı sayfasında sağa-sola gezinme için görünen sıra paylaşılır
        .onChange(of: ids, initial: true) { _, gorunen in
            KitapSirasi.shared.ids = gorunen
            iz.sirayiKur(gorunen)
        }
        // Filtre ya da arama değişince görünmeyen seçimler bırakılır
        .onChange(of: ids) { _, gorunen in
            let kume = Set(gorunen)
            if !secililer.isSubset(of: kume) { secililer.formIntersection(kume) }
        }
        .alert(topluSoruBasligi, isPresented: Binding(get: { topluSoru != nil }, set: { if !$0 { topluSoru = nil } })) {
            switch topluSoru {
            case .yer:
                TextField("Dolap", text: $topluMetin1)
                TextField("Raf", text: $topluMetin2)
            default:
                TextField(topluSoru == .etiket ? "Etiket(ler), virgülle" : "Kategori", text: $topluMetin1)
            }
            Button("Uygula") { topluSoruUygula() }
            Button("Vazgeç", role: .cancel) { }
        } message: {
            if topluSoru == .yer {
                Text("Boş bırakılan alan değişmez. Dolabı ya da rafı boşaltmak için İşlemler menüsündeki “Yeri temizle” seçeneğini kullanın.")
            }
        }
        .confirmationDialog("\(secililer.count) kitap çöp kutusuna taşınsın mı?", isPresented: $silmeOnayi, titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                topluUygula("silindi (30 gün çöp kutusunda)") { try TopluKitapIslemi.silVerified($0, context: modelContext) }
            }
            Button("Vazgeç", role: .cancel) { }
        }
        .confirmationDialog("\(secililer.count) kitap koleksiyondan düşülsün mü?", isPresented: $dusmeOnayi, titleVisibility: .visible) {
            ForEach(["Yıpranmış", "Kayıp", "Bağış", "Güncelliğini yitirmiş"], id: \.self) { neden in
                Button(neden) {
                    topluUygulaOzetli { TopluKitapIslemi.dus($0, neden: neden, context: modelContext).mesaj(neden: neden) }
                }
            }
            Button("Vazgeç", role: .cancel) { }
        }
        .sheet(isPresented: Binding(get: { !baskiListesi.isEmpty }, set: { if !$0 { baskiListesi = [] } })) {
            KapatilabilirSayfa { BaskiSayfasi(kitaplar: baskiListesi) }
        }
        .sheet(isPresented: Binding(get: { !csvListesi.isEmpty }, set: { if !$0 { csvListesi = [] } })) {
            KapatilabilirSayfa { CSVDisaAktarSayfasi(kitaplar: csvListesi) }
        }
        .sensoryFeedback(.success, trigger: topluMesaj)
        .alert("Toplu işlem", isPresented: Binding(get: { topluMesaj != nil }, set: { if !$0 { topluMesaj = nil } })) {
            Button("Tamam", role: .cancel) { }
        } message: {
            Text(topluMesaj ?? "")
        }
    }

    /// Ada/yazara göre sıralı listede harf bölümleri gösterilir (seri görünümünde cilt sırası bozulmasın diye değil).
    private var bolumlu: Bool {
        (siralama == .ad || siralama == .yazar) && filtre.seri == nil
    }

    @ViewBuilder
    private func satir(_ kitap: CatalogBook, _ baglam: SatirBaglami) -> some View {
        Group {
            if let onSec, !secimModu {
                Button { onSec(kitap.id) } label: {
                    KitapSatiri(kitap: kitap, stok: baglam.stok(kitap), gecikmis: baglam.gecikmis.contains(kitap.id))
                        .zoomKaynagi(kitap.id, kapakAlani)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .listRowBackground(seciliID == kitap.id ? KitapTema.ana.opacity(0.15) : nil)
            } else {
                NavigationLink(value: kitap.id) {
                    KitapSatiri(kitap: kitap, stok: baglam.stok(kitap), gecikmis: baglam.gecikmis.contains(kitap.id))
                        .zoomKaynagi(kitap.id, kapakAlani)
                }
            }
        }
        .tag(kitap.id)
        .id(kitap.id)
        .onScrollVisibilityChange(threshold: 0.5) { visible in iz.gorunurluk(kitap.id, visible, etkin: isActive) }
        .swipeActions(edge: .leading) { okumaDugmesi(kitap) }
        .contextMenu { baglamMenusu(kitap) }
    }

    @ViewBuilder
    private func seriOzeti(_ seri: String, _ liste: [CatalogBook]) -> some View {
        let eksik = SeriAnalizi.eksikCiltler(liste.compactMap(\.volume))
        Section {
            Label("\(liste.count) cilt katalogda", systemImage: "books.vertical")
            if !eksik.isEmpty {
                Label("Eksik ciltler: " + eksik.map(String.init).joined(separator: ", "), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(KitapTema.vurgu)
            }
        } header: {
            Text("Seri: \(seri)")
        }
    }

    /// Sayaç satırındaki sıralama: yazı aynı yerde, dokununca seçenekler açılır.
    private var siralamaMenusu: some View {
        Menu {
            Picker("Sıralama", selection: $siralamaRaw) {
                ForEach(KitapSiralama.allCases) { Label($0.rawValue, systemImage: $0.ikon).tag($0.rawValue) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(siralama.rawValue)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.primary)
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(.rect)
        }
        .accessibilityLabel("Sıralama")
        .accessibilityValue(siralama.rawValue)
        .accessibilityIdentifier("books.sort")
    }

    /// Boş liste her zaman bir çıkış yolu gösterir: filtreleri temizle, kayıtlı kitabı aç ya da kataloğa ekle.
    /// Terim bir demirbaşa uyduysa (kitap şeritte) ekleme önerilmez.
    private var bosDurum: some View {
        let filtreli = filtre.aktifSayisi > 0
        let isbn = ISBNFormatter.repair(arama)
        let isbnAramasi = aramaVar && ISBNFormatter.isValidISBN13(isbn) && !InternalBarcode.isInternal(isbn)
        // Kayıt tireli saklanmış ya da koleksiyondan düşülmüş olabilir (liste düşülenleri göstermez):
        // liste bulamasa da barkod kuralı bulur, yeniden eklemeye yönlendirilmez.
        let kayitli = isbnAramasi ? ((try? OkutCozumleyici.isbnAdaylari(isbn, dusulenlerDahil: true, context: modelContext)) ?? []) : []
        var eylemler: [BosDurumEylemi] = []
        if filtreli {
            eylemler.append(BosDurumEylemi(ad: "Filtreleri temizle (\(filtre.aktifSayisi))", ikon: "line.3.horizontal.decrease.circle",
                                           kimlik: "books.empty.clearFilters") { filtre = KitapFiltresi() })
        }
        if let kitap = kayitli.first {
            eylemler.append(BosDurumEylemi(ad: "Kitabı aç", ikon: "book", kimlik: "books.empty.open") {
                DerinBaglanti.shared.bekleyenKitapID = kitap.id
            })
        } else if !demirbasBulundu {
            // Kitap üstteki demirbaş şeridindeyse yeniden eklemeye yönlendirilmez.
            if isbnAramasi {
                eylemler.append(BosDurumEylemi(ad: "Bu ISBN ile kataloğa ekle", ikon: "barcode", kimlik: "books.empty.add") {
                    // Ekle yalnız kendi sayfasında karşılar; ISBN künye aramasıyla forma gelir.
                    DerinBaglanti.shared.bekleyenISBN = isbn
                    DerinBaglanti.shared.hedefSekme = .katalog
                })
            } else if aramaVar || !filtreli {
                eylemler.append(BosDurumEylemi(ad: "Kataloğa ekle", ikon: "plus.circle", kimlik: "books.empty.add") {
                    DerinBaglanti.shared.hedefSekme = .katalog
                })
            }
        }
        let kayitAciklamasi = kayitli.first.map { kitap in
            kitap.isWithdrawn ? "Bu ISBN koleksiyondan düşülmüş “\(kitap.title)” kaydında; liste düşülen kitapları göstermez."
                : "Bu ISBN “\(kitap.title)” kaydında farklı yazımla (örneğin tireli) kayıtlı."
        }
        let baslik = filtreli ? "Bu filtrelerle kitap yok" : (kayitAciklamasi != nil ? "Kitap katalogda" : (aramaVar ? "Sonuç yok" : "Kitap yok"))
        let aciklama = filtreli
            ? "Etkin filtreler: \(aktifFiltreOzeti)."
            : (kayitAciklamasi ?? (aramaVar ? "“\(arama)” katalogda bulunamadı. Yazımı denetleyin ya da kitabı ekleyin." : "Katalogda henüz kitap yok."))
        return BosDurum(baslik: baslik, aciklama: aciklama, ikon: aramaVar ? "magnifyingglass" : "books.vertical", eylemler: eylemler)
    }

    // MARK: Toplu işlemler

    private var topluSoruBasligi: String {
        switch topluSoru {
        case .kategori: "Kategori ata"
        case .yer: "Yer ata"
        case .etiket: "Etiket ekle"
        case nil: ""
        }
    }

    /// Yalnız ekranda görünen (filtreden geçen) seçili kitaplar: gizlenmiş kitaplara toplu işlem yapılmaz.
    private func secilenKitaplar() -> [CatalogBook] {
        guncelKitaplar.filter { secililer.contains($0.id) }
    }

    private func topluUygula(_ ozet: String, _ islem: @escaping ([CatalogBook]) throws -> Void) {
        topluUygulaOzetli { selected in
            try islem(selected)
            return "\(selected.count) kitap \(ozet)."
        }
    }

    /// İşlem sonucunu kendi özetiyle bildirir (düşme gibi bazı kitapların atlanabildiği işlemler için).
    private func topluUygulaOzetli(_ islem: @escaping ([CatalogBook]) throws -> String) {
        let selected = secilenKitaplar()
        guard !selected.isEmpty else { return }
        Task {
            guard await YetkiDurumu.shared.yoneticiOl() else { topluMesaj = YetkiDurumu.shared.hata ?? "Yönetici kimliği gerekir."; return }
            let before = Dictionary(selected.map { ($0.id, $0.book.hafif) }, uniquingKeysWith: { ilk, _ in ilk })
            do {
                let mesaj = try islem(selected)
                try modelContext.save()
                // Geri alma kaydı kayıt başarılı olduktan sonra, hafif (kapaksız) biçimde yazılır.
                let degisimler = TopluGeriAlma.degisimler(before: before, after: selected.filter { !$0.isDeleted }.map { $0.book.hafif })
                if !degisimler.isEmpty {
                    let kayit = CatalogBulkUndoRecord(ozet: mesaj, degisimler: degisimler)
                    if CatalogBulkUndoStore.kaydet(kayit) { geriAlmaKaydi = kayit }
                    else { geriAlmaKaydi = nil; AppLog.write("Toplu işlem geri alma kaydı yazılamadı") }
                }
                if let all = try? modelContext.fetch(FetchDescriptor<CatalogBook>()) { CatalogBackup.saveLight(all, force: true) }
                topluMesaj = mesaj
                secililer.removeAll()
            } catch {
                modelContext.rollback()
                topluMesaj = "İşlem kaydedilemedi: \(error.localizedDescription)"
            }
        }
    }

    private func undoBulk() {
        guard let kayit = geriAlmaKaydi else { return }
        Task {
            guard await YetkiDurumu.shared.yoneticiOl() else { return }
            do {
                let kimlikler = Set(kayit.degisimler.map(\.after.id))
                let simdikiler = try modelContext.fetch(FetchDescriptor<CatalogBook>()).filter { kimlikler.contains($0.id) }
                let plan = TopluGeriAlma.plan(kayit.degisimler, guncel: Dictionary(simdikiler.map { ($0.id, $0.book) }, uniquingKeysWith: { ilk, _ in ilk }))
                let modeller = Dictionary(simdikiler.map { ($0.id, $0) }, uniquingKeysWith: { ilk, _ in ilk })
                for geri in plan.uygulanan { modeller[geri.id]?.update(from: geri) }
                try modelContext.save()
                geriAlmaKaydi = nil
                CatalogBulkUndoStore.temizle()
                topluMesaj = "\(plan.uygulanan.count) kitap geri alındı." + (plan.atlanan > 0 ? " Sonradan değişen ya da silinen \(plan.atlanan) kayıt korundu." : "")
                if let all = try? modelContext.fetch(FetchDescriptor<CatalogBook>()) { CatalogBackup.saveLight(all, force: true) }
            } catch { modelContext.rollback(); topluMesaj = "Geri alma kaydedilemedi: \(error.localizedDescription)" }
        }
    }

    private func topluYerTemizle(_ alanlar: Set<TopluKitapIslemi.YerAlani>) {
        topluUygulaOzetli { secilen in
            let ozet = TopluKitapIslemi.yer(dolap: "", raf: "", temizle: alanlar, secilen)
            return "\(secilen.count) kitabın yeri güncellendi. \(ozet)."
        }
    }

    private func topluSoruUygula() {
        let a = topluMetin1.trimmingCharacters(in: .whitespaces)
        let b = topluMetin2.trimmingCharacters(in: .whitespaces)
        switch topluSoru {
        case .kategori where !a.isEmpty:
            topluUygula("“\(a)” kategorisine alındı") { TopluKitapIslemi.kategori(a, $0) }
        case .yer where !(a.isEmpty && b.isEmpty):
            topluUygulaOzetli { secilen in
                let ozet = TopluKitapIslemi.yer(dolap: a, raf: b, secilen)
                return "\(secilen.count) kitap taşındı. \(ozet)."
            }
        case .etiket where !a.isEmpty:
            topluUygula("etiketlendi") { TopluKitapIslemi.etiketEkle(a, $0) }
        default:
            break
        }
        topluMetin1 = ""
        topluMetin2 = ""
    }

    private func topluIslemCubugu(_ liste: [CatalogBook]) -> some View {
        let layout = yaziBoyutu.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Button(secililer.count == liste.count ? "Seçimi kaldır" : "Tümünü seç") {
                secililer = secililer.count == liste.count ? [] : Set(liste.map(\.id))
            }
            .buttonStyle(.kitapTonlu(KitapTema.ana))
            Spacer()
            Text("\(secililer.count) seçili")
                .font(.subheadline.weight(.semibold))
                .accessibilityLabel("\(secililer.count) kitap seçili")
            Spacer()
            Menu {
                if geriAlmaKaydi != nil { Button("Son toplu işlemi geri al", systemImage: "arrow.uturn.backward") { undoBulk() } }
                Menu("Kategori", systemImage: "tag") {
                    ForEach(kategoriler.filter { $0 != "Kategorisiz" }, id: \.self) { ad in
                        Button(ad) { topluUygula("“\(ad)” kategorisine alındı") { TopluKitapIslemi.kategori(ad, $0) } }
                    }
                    Button("Yeni kategori…") { topluSoru = .kategori }
                }
                Button("Yer ata (dolap/raf)…", systemImage: "cabinet") { topluSoru = .yer }
                Menu("Yeri temizle", systemImage: "eraser") {
                    Button("Dolabı temizle") { topluYerTemizle([.dolap]) }
                    Button("Rafı temizle") { topluYerTemizle([.raf]) }
                    Button("Dolap ve rafı temizle") { topluYerTemizle([.dolap, .raf]) }
                }
                Button("Etiket ekle…", systemImage: "number") { topluSoru = .etiket }
                Menu("Okuma durumu", systemImage: "bookmark") {
                    ForEach(["Okunacak", "Okunuyor", "Okundu"], id: \.self) { durum in
                        Button(durum) { topluUygula("“\(durum)” yapıldı") { TopluKitapIslemi.okuma(durum, $0) } }
                    }
                }
                Menu("Okuma düzeyi", systemImage: "graduationcap") {
                    ForEach(OkumaDuzeyi.liste, id: \.self) { duzey in
                        Button(duzey) { topluUygula("“\(duzey)” düzeyine alındı") { TopluKitapIslemi.duzey(duzey, $0) } }
                    }
                    Button("Düzeyi kaldır") { topluUygula("düzeysiz yapıldı") { TopluKitapIslemi.duzey("", $0) } }
                }
                Button("Etiket / QR kart bas", systemImage: "printer") {
                    baskiListesi = secilenKitaplar()
                }
                Button("CSV'ye aktar", systemImage: "tablecells") {
                    csvListesi = secilenKitaplar()
                }
                Divider()
                Button("Koleksiyondan düş…", systemImage: "archivebox") {
                    Task { if await YetkiDurumu.shared.yoneticiOl() { dusmeOnayi = true } }
                }
                Button("Sil…", systemImage: "trash", role: .destructive) {
                    Task { if await YetkiDurumu.shared.yoneticiOl() { silmeOnayi = true } }
                }
            } label: {
                Label("İşlemler", systemImage: "square.stack.3d.up")
            }
            .buttonStyle(.kitapDolu(KitapTema.ana))
            .disabled(secililer.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: Filtre çipleri

    private var filtreCubugu: some View {
        VStack(alignment: .leading, spacing: 6) {
            if yaziBoyutu.isAccessibilitySize {
                // Büyük yazıda düğme ve çipler tek kayan satırda: liste ekranın altına itilmesin.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        filtreDugmeleri
                        durumCipleri
                    }
                    .padding(.horizontal)
                }
            } else {
                HStack {
                    filtreDugmeleri
                    Spacer()
                }.padding(.horizontal)
                // Rafta / Ödünçte / Gecikmiş tek dokunuşla; sığmazsa yatay kayar.
                ViewThatFits(in: .horizontal) {
                    durumCipleri.padding(.horizontal)
                    ScrollView(.horizontal, showsIndicators: false) { durumCipleri.padding(.horizontal) }
                }
            }
            if filtre.aktifSayisi > 0 {
                Text(aktifFiltreOzeti).font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                    .accessibilityLabel("Etkin filtreler: \(aktifFiltreOzeti)")
            }
        }
        .padding(.top, 6)
        .sheet(isPresented: $filtreAcik) {
            NavigationStack {
                Form {
                    Section("Hazır filtreler") {
                        ForEach(HazirFiltre.allCases) { hazir in
                            Button(hazir.ad, systemImage: hazir.ikon) { filtre = hazir.filtre }
                                .accessibilityIdentifier("books.preset.\(hazir.rawValue)")
                        }
                    }
                    Section("Durum") {
                        Picker("Kitap durumu", selection: $filtre.durum) { ForEach(KitapDurumFiltresi.allCases) { Text($0.ad).tag($0) } }
                    }
                    Section("Kategori ve konum") {
                        optionalPicker("Kategori", values: kategoriler, selection: $filtre.kategori)
                        optionalPicker("Dolap", values: dolaplar, selection: $filtre.dolap)
                    }
                    Section("Okuma ve seri") {
                        optionalPicker("Etiket", values: etiketler, selection: $filtre.etiket)
                        optionalPicker("Düzey", values: OkumaDuzeyi.liste, selection: $filtre.duzey)
                        optionalPicker("Seri", values: seriler, selection: $filtre.seri)
                        optionalPicker("Okuma durumu", values: ["Okunacak", "Okunuyor", "Okundu"], selection: $filtre.okuma)
                    }
                    Button("Filtreleri temizle") { filtre = KitapFiltresi() }
                }
                .navigationTitle("Kitap filtreleri")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Göster") { filtreAcik = false } } }
            }
        }
    }
    @ViewBuilder
    private var filtreDugmeleri: some View {
        Button { filtreAcik = true } label: {
            Label(filtre.aktifSayisi > 0 ? "Filtreler (\(filtre.aktifSayisi))" : "Filtreler", systemImage: "line.3.horizontal.decrease")
        }.buttonStyle(.kitapTonlu()).accessibilityIdentifier("books.filters")
        if filtre.aktifSayisi > 0 {
            Button("Temizle") { filtre = KitapFiltresi() }.frame(minWidth: 44, minHeight: 44)
        }
    }
    private var durumCipleri: some View {
        HStack(spacing: 6) {
            ForEach(KitapDurumFiltresi.cipler) { durum in
                Cip(ad: durum.ad, ikon: durum.ikon, secili: filtre.durum == durum, renk: durum.renk) { filtre.durum = durum }
                    .accessibilityIdentifier("books.status.\(durum)")
            }
        }
    }
    private var aktifFiltreOzeti: String {
        ([filtre.durum == .tumu ? nil : filtre.durum.ad, filtre.kategori, filtre.dolap.map { "Dolap \($0)" }, filtre.okuma, filtre.etiket, filtre.duzey, filtre.seri,
          filtre.eksikAlan.map { "\($0) eksik" },
          filtre.sonOduncGun.map { "Son \($0) gündür ödünç yok" },
          filtre.eklenmeSonGun.map { "Son \($0) günde eklendi" }]).compactMap { $0 }.joined(separator: " · ")
    }
    private func optionalPicker(_ title: String, values: [String], selection: Binding<String?>) -> some View {
        Picker(title, selection: selection) {
            Text("Tümü").tag(String?.none)
            ForEach(values, id: \.self) { Text($0).tag(Optional($0)) }
        }
    }

    // MARK: Hızlı işlemler

    @ViewBuilder
    private func okumaDugmesi(_ kitap: CatalogBook) -> some View {
        let sonraki = kitap.readingStatus == "Okundu" ? "Okunacak" : (kitap.readingStatus == "Okunuyor" ? "Okundu" : "Okunuyor")
        Button {
            setReadingStatus(sonraki, book: kitap)
        } label: {
            Label(sonraki, systemImage: "bookmark")
        }
        .tint(KitapTema.toplu)
    }

    private func setReadingStatus(_ status: String, book: CatalogBook) {
        Task {
            guard await YetkiDurumu.shared.yoneticiOl() else { topluMesaj = YetkiDurumu.shared.hata ?? "Yönetici kimliği gerekir."; return }
            book.readingStatus = status
            do { try modelContext.save() }
            catch { modelContext.rollback(); topluMesaj = "Okuma durumu kaydedilemedi: \(error.localizedDescription)" }
        }
    }
    @ViewBuilder
    private func baglamMenusu(_ kitap: CatalogBook) -> some View {
        ForEach(["Okunacak", "Okunuyor", "Okundu"], id: \.self) { durum in
            Button {
                setReadingStatus(durum, book: kitap)
            } label: {
                Label(durum, systemImage: kitap.readingStatus == durum ? "checkmark" : "bookmark")
            }
        }
        if let isbn = kitap.isbn, !isbn.isEmpty {
            Button {
                UIPasteboard.general.string = isbn
            } label: {
                Label("ISBN'i Kopyala", systemImage: "doc.on.doc")
            }
        }
        ShareLink(item: KitapDetaySayfasi.paylasimMetni(kitap)) {
            Label("Paylaş", systemImage: "square.and.arrow.up")
        }
    }
}

// MARK: - Satır ve hücreler

/// Liste çizimi başına bir kez kurulan stok ve gecikme tabloları.
fileprivate struct SatirBaglami {
    let stoklar: [UUID: LibraryStock]
    let gecikmis: Set<UUID>

    func stok(_ kitap: CatalogBook) -> LibraryStock {
        let adet = max(1, kitap.quantity ?? 1)
        return stoklar[kitap.id] ?? LibraryStock(total: adet, available: kitap.isWithdrawn ? 0 : adet)
    }
}

/// Kitabın tek durum sözcüğü (ad sözlüğü): Düşüldü, Gecikmiş, Rafta ya da "2/3 rafta", Ödünçte,
/// Sırada. Liste satırı, kapak hücresi, ayrıntı ve Ana Sayfa araması aynı kuralı kullanır.
enum KitapDurumu {
    static func rozet(_ kitap: CatalogBook, stok: LibraryStock, gecikmis: Bool = false) -> (metin: String, renk: Color, ikon: String) {
        if kitap.isWithdrawn { return ("Düşüldü", .gray, "archivebox.fill") }
        if gecikmis || kitap.isOverdue { return ("Gecikmiş", .red, "exclamationmark.circle.fill") }
        if stok.available == 0 { return rafDisi(stok) }
        if stok.total > 1 { return ("\(stok.available)/\(stok.total) rafta", KitapTema.basari, "checkmark.circle.fill") }
        return ("Rafta", KitapTema.basari, "checkmark.circle.fill")
    }

    /// Birden çok kitabın rozeti tek hesapta (satır başına sorgu yok). Stok `stockByBook` ile kurulur:
    /// nüsha durumu (kayıp, onarımda), bildirilmiş rezervasyon ve kayıtlı nüsha sayısı ayrıntıyla aynı sayılır.
    static func rozetler(_ kitaplar: [CatalogBook], loans: [ActiveLoan], copies: [BookCopy], reservations: [Reservation],
                         now: Date = .now) -> [UUID: (metin: String, renk: Color, ikon: String)] {
        let stoklar = SchoolLibraryService.stockByBook(books: kitaplar, loans: loans, copies: copies, reservations: reservations, now: now)
        let gecikmis = SchoolLibraryService.overdueBookIDs(loans, books: kitaplar, now: now)
        return Dictionary(kitaplar.map { kitap in
            (kitap.id, rozet(kitap, stok: stoklar[kitap.id] ?? LibraryStock(total: max(1, kitap.quantity ?? 1)), gecikmis: gecikmis.contains(kitap.id)))
        }, uniquingKeysWith: { ilk, _ in ilk })
    }

    /// Raflar satırı: "3 nüsha · 1 ödünçte". Ödünç yoksa "rafta", eksikse "1 rafta"; hiç yoksa nedeni
    /// ("kayıp", "sırada"). Ödünç sayısı nüsha sayısını aşmaz (eski `loanedTo` ile etkin ödünç üst üste binse de).
    static func rafSatiri(_ stok: LibraryStock) -> String {
        let nusha = max(1, stok.total)
        let oduncte = min(stok.loaned, nusha)
        let durum = if oduncte > 0 { "\(oduncte) ödünçte" }
            else if stok.available == 0 { rafDisi(stok).metin.lowercased(with: Locale(identifier: "tr_TR")) }
            else if stok.available < nusha { "\(stok.available) rafta" }
            else { "rafta" }
        return "\(nusha) nüsha · \(durum)"
    }

    /// Rafta nüsha kalmadığında nedeni: "Ödünçte" yalnız gerçekten ödünçte nüsha varsa yazılır;
    /// kayıp/onarımdaki ya da rezervasyona ayrılmış nüsha ödünçte gösterilmez.
    static func rafDisi(_ stok: LibraryStock) -> (metin: String, renk: Color, ikon: String) {
        if stok.loaned > 0 { return ("Ödünçte", KitapTema.vurgu, "person.badge.clock.fill") }
        if stok.reserved > 0 { return ("Sırada", KitapTema.amazon, "bookmark.fill") }
        if stok.lost > 0 && stok.repair > 0 { return ("Kayıp / onarımda", .gray, "xmark.circle.fill") }
        if stok.lost > 0 { return ("Kayıp", .gray, "xmark.circle.fill") }
        if stok.repair > 0 { return ("Onarımda", .gray, "wrench.and.screwdriver.fill") }
        return ("Rafta değil", .gray, "xmark.circle.fill")
    }

    /// "Ödünç ver" pasifken altında yazan neden, örneğin "Uygun nüsha yok · 2 ödünçte".
    /// Ödünç verilebiliyorsa `nil` (ayrılmış nüsha sıradaki kişiye verilebilir).
    static func oduncEngeli(_ kitap: CatalogBook, stok: LibraryStock) -> String? {
        if kitap.isWithdrawn { return "Koleksiyondan düşüldü; ödünç verilemez." }
        guard stok.available + stok.reserved == 0 else { return nil }
        return ["Uygun nüsha yok", stok.loaned > 0 ? "\(stok.loaned) ödünçte" : nil,
                stok.lost > 0 ? "\(stok.lost) kayıp" : nil, stok.repair > 0 ? "\(stok.repair) onarımda" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// Liste satırı: büyük kapak, kalın ad, renkli durum şeridi ve rozetler.
private struct KitapSatiri: View {
    let kitap: CatalogBook
    let stok: LibraryStock
    var gecikmis = false

    private var durum: (metin: String, renk: Color, ikon: String) { KitapDurumu.rozet(kitap, stok: stok, gecikmis: gecikmis) }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            KapakGorseli(kitap: kitap, genislik: 54, yukseklik: 80, kose: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(kitap.title.isEmpty ? "Adsız kayıt" : kitap.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(kitap.author.isEmpty ? "Yazar yok" : kitap.author)
                    .font(.subheadline)
                    .foregroundStyle(KitapTema.ikincilMetin)
                    .lineLimit(1)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                    Rozet(metin: durum.metin, renk: durum.renk, ikon: durum.ikon)
                    if let kategori = kitap.category, !kategori.isEmpty {
                        Rozet(metin: kategori, renk: KitapTema.kitapRengi(kategori), ikon: "tag.fill")
                    }
                    if let konum = kitap.konumMetni { Rozet(metin: konum, renk: KitapTema.amazon, ikon: "cabinet.fill") }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Rozet(metin: durum.metin, renk: durum.renk, ikon: durum.ikon)
                        if let category = kitap.category { Text(category).font(.caption).fixedSize(horizontal: false, vertical: true) }
                        if let konum = kitap.konumMetni { Rozet(metin: konum, renk: KitapTema.amazon, ikon: "cabinet.fill", satirSiniri: nil) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Ortak kapak görseli: kapak yoksa adın rengine göre gradyan + ad.
struct KapakGorseli: View {
    let kitap: CatalogBook
    var genislik: CGFloat? = nil
    var yukseklik: CGFloat = 150
    var kose: CGFloat = 14
    /// Arka planda çözülen küçük kapak ve hangi kapağa ait olduğu (hücre başka kitaba geçebilir)
    @State private var cozulen: (anahtar: CoverImageDecoder.KucukKapakAnahtari, gorsel: CGImage)?

    var body: some View {
        let anahtar = kitap.coverData.map {
            CoverImageDecoder.KucukKapakAnahtari(kitap: kitap.id, bayt: $0.count, piksel: Int(max(yukseklik, genislik ?? 0) * 3))
        }
        // Önbellekteki kapak hemen çizilir; yoksa arka planda çözülür, kaydırırken ana iş parçacığı beklemez
        let gorsel = anahtar.flatMap { anahtar in
            CoverImageDecoder.onbellektekiKucukKapak(anahtar) ?? (cozulen?.anahtar == anahtar ? cozulen?.gorsel : nil)
        }
        // Ölçüyü yalnız renkli zemin belirler; kapak üstüne bindirilir. Geniş (yatay) bir fotoğraf
        // scaledToFill ile kendi genişliğini dayatıp ızgarada komşu kapakların üstüne taşamaz.
        // Kapak çözülürken yalnız kitabın rengi görünür (başlık yazısı yanıp sönmesin).
        Rectangle()
            .fill(KitapTema.kitapRengi(kitap.title).gradient)
            .frame(width: genislik, height: yukseklik)
            .frame(maxWidth: genislik == nil ? .infinity : nil)
            .overlay {
                if let gorsel {
                    Image(decorative: gorsel, scale: 1).resizable().scaledToFill()
                } else if anahtar == nil {
                    ZStack {
                        Rectangle().fill(Color.black.opacity(0.45))
                        VStack(spacing: 4) {
                            Image(systemName: "book.closed.fill").font(yukseklik > 100 ? .title2 : .caption)
                            if yukseklik > 100 {
                                Text(kitap.title)
                                    .font(.caption.weight(.bold))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(4)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(6)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: kose))
        .overlay(RoundedRectangle(cornerRadius: kose).strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
        .accessibilityHidden(true)
        .task(id: anahtar) {
            guard let anahtar, CoverImageDecoder.onbellektekiKucukKapak(anahtar) == nil,
                  let data = kitap.coverData else { return }
            let gorsel = await Task.detached(priority: .userInitiated) {
                CoverImageDecoder.kucukKapak(data, anahtar: anahtar)
            }.value
            guard !Task.isCancelled, let gorsel else { return }
            cozulen = (anahtar, gorsel)
        }
    }
}

/// Izgara hücresi: gölgeli kapak, köşede durum işareti, altta konum rozeti.
private struct KapakHucresi: View {
    let kitap: CatalogBook
    let stok: LibraryStock
    var gecikmis = false

    /// Köşe işareti yalnız dikkat isteyen durumda: düşülmüş, gecikmiş ya da rafta nüsha yok.
    private var isaret: (metin: String, renk: Color, ikon: String)? {
        kitap.isWithdrawn || gecikmis || kitap.isOverdue || stok.available == 0
            ? KitapDurumu.rozet(kitap, stok: stok, gecikmis: gecikmis) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                KapakGorseli(kitap: kitap, yukseklik: 164)
                if let isaret { durumIkonu(isaret.ikon, isaret.renk) }
            }
            Text(kitap.title).font(.caption.weight(.bold)).lineLimit(2).foregroundStyle(Color.primary)
            Text(kitap.author).font(.caption2).foregroundStyle(KitapTema.ikincilMetin).lineLimit(1)
            if let konum = kitap.konumMetni {
                Rozet(metin: konum, renk: KitapTema.amazon, ikon: "cabinet.fill", satirSiniri: 2)
            }
        }
        .accessibilityElement(children: .combine)
        // Etiket kitap adıyla başlar (kaydırma konumu UI testi buna dayanır): ad, yazar, durum, konum.
        .accessibilityLabel([kitap.title, kitap.author, isaret?.metin ?? "", kitap.konumMetni ?? ""]
            .filter { !$0.isEmpty }.joined(separator: ", "))
    }

    private func durumIkonu(_ ikon: String, _ renk: Color) -> some View {
        Image(systemName: ikon)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(6)
            .background(renk, in: .circle)
            .shadow(radius: 2)
            .padding(6)
            .accessibilityHidden(true)
    }
}

// MARK: - Ayrıntı sayfası

/// Ödünç hareketlerinin yeniden okunmasını tetikleyen girdiler.
private struct HareketAnahtari: Equatable {
    let kitap: UUID
    let odunc: Int
}

struct KitapDetaySayfasi: View {
    let kitapID: UUID
    @Query private var copies: [BookCopy]
    @Query private var reservations: [Reservation]
    @State private var yeniOdunc = false
    /// Sayfalayıcı içindeyken başlık ve üst araç çubuğu dıştaki sayfalayıcıya bırakılır
    var sayfalamada = false

    @Environment(\.modelContext) private var modelContext
    @Query private var loans: [ActiveLoan]
    @Query private var bulunan: [CatalogBook]
    @State private var duzenlenen: BookDraft?
    @State private var benzerler: [CatalogBook] = []
    @State private var seriKitaplari: [CatalogBook] = []
    @State private var kapakRengi: Color?
    @State private var editError: String?
    @State private var yerSoruluyor = false
    @State private var yeniDolap = ""
    @State private var yeniRaf = ""
    /// Ödünç hareketleri çizim başına değil, kitap ya da kayıt sayısı değişince bir kez okunur.
    @State private var hareketler: [LoanEvent] = []
    @State private var geriAlinacak: CatalogBook?
    @Environment(\.dynamicTypeSize) private var yaziBoyutu

    init(kitapID: UUID, sayfalamada: Bool = false) {
        self.kitapID = kitapID
        self.sayfalamada = sayfalamada
        _bulunan = Query(filter: #Predicate<CatalogBook> { $0.id == kitapID })
        // Yalnız bu kitabın kayıtları okunur (önceden tüm nüsha, ödünç ve rezervasyonlar çekiliyordu).
        _copies = Query(filter: #Predicate<BookCopy> { $0.bookID == kitapID })
        _reservations = Query(filter: #Predicate<Reservation> { $0.bookID == kitapID })
        _loans = Query(filter: #Predicate<ActiveLoan> { $0.bookID == kitapID })
    }

    static func paylasimMetni(_ kitap: CatalogBook) -> String {
        [kitap.title, kitap.author, kitap.publisher, kitap.isbn.map { "ISBN \($0)" }]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
    }

    var body: some View {
        if let kitap = bulunan.first, !kitap.isDeleted {
            icerik(kitap)
        } else {
            ContentUnavailableView("Kitap bulunamadı", systemImage: "book.closed")
        }
    }

    private func icerik(_ kitap: CatalogBook) -> some View {
        let kitapOduncleri = loans.filter { $0.bookID == kitap.id }
        let stock = SchoolLibraryService.stock(for: kitap, loans: loans, copies: copies, reservations: reservations)
        let disarida = stock.loaned
        let durum = KitapDurumu.rozet(kitap, stok: stock, gecikmis: kitapOduncleri.contains(where: \.isOverdue))
        let oduncEngeli = KitapDurumu.oduncEngeli(kitap, stok: stock)
        let konum = kitap.konumMetni ?? CatalogBook.yerAtanmamis
        let ikincilDuzen = yaziBoyutu.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return List {
            // Kahraman başlık: kapağın baskın renginden gradyan, büyük kapak, rozetler, cam düğmeler
            Section {
                VStack(spacing: 14) {
                    KapakGorseli(kitap: kitap, genislik: 132, yukseklik: 196, kose: 16)
                        .shadow(color: (kapakRengi ?? KitapTema.ana).opacity(0.5), radius: 16, y: 8)
                    VStack(spacing: 4) {
                        Text(kitap.title)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text(kitap.author)
                            .font(.headline)
                            .foregroundStyle(KitapTema.ikincilMetin)
                    }
                    HStack(spacing: 6) {
                        Rozet(metin: durum.metin, renk: durum.renk, ikon: durum.ikon)
                        if let kategori = kitap.category { Rozet(metin: kategori, renk: KitapTema.kitapRengi(kategori), ikon: "tag.fill") }
                        if let duzey = kitap.readingLevel, !duzey.isEmpty {
                            Rozet(metin: duzey, renk: KitapTema.dosya, ikon: "graduationcap.fill")
                        }
                    }
                    // Kitap nerede: konum ayrıntıya kaydırmadan, büyük yazıyla okunur.
                    Label(konum, systemImage: "cabinet.fill")
                        .font(.title3.weight(.semibold))
                        .labelStyle(RenkliIkonEtiketi(renk: KitapTema.amazon))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Konum: \(konum)")
                        .accessibilityIdentifier("book.location")
                    GlassEffectContainer(spacing: 10) {
                        VStack(spacing: 10) {
                            // Birincil iş: book.lend kimliği yalnız bu düğmededir.
                            Button { yeniOdunc = true } label: {
                                Label("Ödünç ver", systemImage: "person.badge.plus").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent)
                            .tint(KitapTema.ana)
                            .disabled(oduncEngeli != nil)
                            .accessibilityIdentifier("book.lend")
                            ikincilDuzen {
                                Button {
                                    duzenlemeyiBaslat(kitap)
                                } label: {
                                    Label("Düzenle", systemImage: "pencil").frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.glass)
                                ShareLink(item: Self.paylasimMetni(kitap)) {
                                    Label("Paylaş", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.glass)
                            }
                        }
                    }
                    if let oduncEngeli {
                        Text(oduncEngeli)
                            .font(.footnote)
                            .foregroundStyle(KitapTema.ikincilMetin)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .listRowBackground(
                    LinearGradient(colors: [(kapakRengi ?? KitapTema.ana).opacity(0.35), Color(.secondarySystemGroupedBackground)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .accessibilityElement(children: .contain)
            }

            Section("Kütüphane işlemleri") {
                Button("Yer değiştir…", systemImage: "cabinet") {
                    yeniDolap = kitap.cabinet ?? ""
                    yeniRaf = kitap.shelf ?? ""
                    yerSoruluyor = true
                }
                .accessibilityIdentifier("book.move")
                LabeledContent("Nüshalar", value: "\(stock.total) toplam · \(stock.available) rafta · \(stock.loaned) ödünçte")
                if stock.reserved > 0 { LabeledContent("Sırada bekleyene ayrılmış", value: "\(stock.reserved)") }
                if stock.lost + stock.repair > 0 { LabeledContent("Kayıp / onarımda", value: "\(stock.lost) / \(stock.repair)") }
                if disarida > 0 {
                    Button("Ödünçleri ve iadeleri aç", systemImage: "arrow.uturn.left") {
                        KutuphaneRotasi.shared.oduncAramasi = kitap.title
                        KutuphaneRotasi.shared.oduncBolumu = .etkin
                        DerinBaglanti.shared.hedefSekme = .odunc
                    }
                }
            }

            if kitap.isWithdrawn {
                Section {
                    LabeledContent("Neden", value: (kitap.withdrawnReason ?? "").isEmpty ? "Belirtilmemiş" : kitap.withdrawnReason ?? "")
                    if let tarih = kitap.withdrawnDate {
                        LabeledContent("Tarih", value: tarih.formatted(date: .abbreviated, time: .omitted))
                    }
                    Button("Koleksiyona geri al", systemImage: "arrow.uturn.backward") { geriAlinacak = kitap }
                        .accessibilityIdentifier("book.restore")
                } header: {
                    Text("Düşüldü")
                } footer: {
                    Text("Düşülen kitap listede görünmez ve ödünç verilemez. Geri alınca yeniden rafa döner.")
                }
            }

            if let uyari = kitap.contentWarning, !uyari.isEmpty {
                Section {
                    Label(uyari, systemImage: "exclamationmark.bubble")
                        .foregroundStyle(KitapTema.vurgu)
                } header: {
                    Text("İçerik uyarısı")
                }
            }

            if !kitap.tagList.isEmpty {
                Section("Etiketler") {
                    FlowChips(items: kitap.tagList.map { "#\($0)" }, color: KitapTema.vurgu)
                }
            }

            if let seri = kitap.series, !seri.isEmpty {
                Section {
                    let eksik = SeriAnalizi.eksikCiltler(seriKitaplari.compactMap(\.volume))
                    ForEach(seriKitaplari) { ciltKitap in
                        NavigationLink(value: ciltKitap.id) {
                            HStack {
                                Text(ciltKitap.volume.map { "\($0). cilt" } ?? "Cilt ?")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 64, alignment: .leading)
                                Text(ciltKitap.title)
                                    .fontWeight(ciltKitap.id == kitap.id ? .bold : .regular)
                            }
                        }
                        .disabled(ciltKitap.id == kitap.id)
                    }
                    if !eksik.isEmpty {
                        Label("Eksik ciltler: " + eksik.map(String.init).joined(separator: ", "), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(KitapTema.vurgu)
                    }
                } header: {
                    Text("Seri: \(seri)")
                }
            }

            Section("Okuma durumu") {
                Picker("Durum", selection: Binding(
                    get: { kitap.readingStatus ?? "Okunacak" },
                    set: { status in
                        Task {
                            guard await YetkiDurumu.shared.yoneticiOl() else { editError = YetkiDurumu.shared.hata ?? "Yönetici kimliği gerekir."; return }
                            kitap.readingStatus = status
                            do { try modelContext.save() } catch { modelContext.rollback(); editError = error.localizedDescription }
                        }
                    }
                )) {
                    ForEach(["Okunacak", "Okunuyor", "Okundu"], id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Künye") {
                satir("Yayınevi", kitap.publisher)
                satir("Yıl", kitap.publicationYear)
                satir("Baskı", kitap.edition)
                satir("Sayfa", kitap.pageCount)
                satir("Dil", kitap.language)
                satir("ISBN", kitap.isbn)
                satir("Demirbaş", kitap.accessionCode)
            }

            NushaBolumu(kitap: kitap)
            Section("Bilgi kaynakları ve alan kilitleri") { DisclosureGroup("Kaynakları incele ve alanları kilitle") { BookFieldEvidencePanel(book: kitap) } }

            RezervasyonBolumu(kitap: kitap)

            if disarida > 0 {
                Section("Ödünçte") {
                    if let kisi = kitap.loanedTo, !kisi.isEmpty {
                        LabeledContent(kisi, value: kitap.loanDueDate?.formatted(date: .abbreviated, time: .omitted) ?? "")
                            .foregroundStyle(kitap.isOverdue ? .red : .primary)
                    }
                    ForEach(kitapOduncleri) { odunc in
                        LabeledContent("\(odunc.studentName) (\(odunc.studentClass))",
                                       value: odunc.dueDate.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(odunc.isOverdue ? .red : .primary)
                    }
                }
            }

            if !kitap.notes.isEmpty {
                Section("Notlar / Özet") { Text(kitap.notes).textSelection(.enabled) }
            }

            if !hareketler.isEmpty {
                Section {
                    ForEach(hareketler.prefix(20)) { hareket in
                        HStack(spacing: 10) {
                            Image(systemName: hareket.kind == .lent ? "arrow.up.right.circle.fill" : "arrow.down.left.circle.fill")
                                .foregroundStyle(hareket.kind == .lent ? KitapTema.amazon : KitapTema.basari)
                            VStack(alignment: .leading) {
                                Text("\(hareket.person) — \(hareket.kind.rawValue)")
                                Text(hareket.date.formatted(date: .abbreviated, time: .shortened)
                                     + (hareket.wasLate ? " · gecikmeli" : ""))
                                    .font(.caption)
                                    .foregroundStyle(hareket.wasLate ? .red : .secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Ödünç geçmişi (\(hareketler.count))")
                }
            }

            if !benzerler.isEmpty {
                Section("Benzer kitaplar") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(benzerler) { benzer in
                                NavigationLink(value: benzer.id) {
                                    VStack(spacing: 4) {
                                        CoverThumb(data: benzer.coverData, size: 60)
                                        Text(benzer.title)
                                            .font(.caption2)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                            .frame(width: 80)
                                    }
                                }
                                .buttonStyle(.kitapSade)
                                .accessibilityLabel("Benzer kitap: \(benzer.title)")
                            }
                        }
                    }
                }
            }
        }
        // Sayfalayıcıdayken başlık verilmez: dıştaki "2 / 3" sayacı görünsün
        .modifier(KosulluBaslik(baslik: sayfalamada ? nil : kitap.title))
        .task(id: HareketAnahtari(kitap: kitap.id, odunc: loans.count)) {
            hareketler = LoanHistoryStore.events(forBook: kitap.id)
        }
        .task(id: kitap.id) {
            kapakRengi = await KapakRengi.baskinArkaPlanda(id: kitap.id, data: kitap.coverData)
            benzerler = BenzerKitaplar.bul(kitap, adaylar: BenzerKitaplar.adaylar(for: kitap, context: modelContext))
            if let seri = kitap.series, !seri.isEmpty {
                seriKitaplari = SeriAnalizi.seriKitaplari(seri, context: modelContext)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !sayfalamada { Button("Düzenle") { duzenlemeyiBaslat(kitap) } }
            }
        }
        .alert("İşlem tamamlanamadı", isPresented: Binding(get: { editError != nil }, set: { if !$0 { editError = nil } })) { Button("Tamam", role: .cancel) { } } message: { Text(editError ?? "") }
        .alert("Yer değiştir", isPresented: $yerSoruluyor) {
            TextField("Dolap", text: $yeniDolap)
            TextField("Raf", text: $yeniRaf)
            Button("Uygula") { yerDegistir(kitap) }
            Button("Vazgeç", role: .cancel) { }
        } message: {
            Text("Şu anki yer: \(konum). Boş bırakılan alan değişmez.")
        }
        .confirmationDialog("Kitap koleksiyona geri alınsın mı?", isPresented: Binding(get: { geriAlinacak != nil }, set: { if !$0 { geriAlinacak = nil } }), titleVisibility: .visible) {
            Button("Koleksiyona geri al") { koleksiyonaGeriAl() }
            Button("Vazgeç", role: .cancel) { }
        } message: {
            Text("Düşülme nedeni ve tarihi silinir; kitap yeniden ödünç verilebilir.")
        }
        .sheet(isPresented: $yeniOdunc) { KitapOduncFormu(kitap: kitap) }
        .sheet(item: $duzenlenen) { taslak in
            BookEditorView(validating: taslak, save: { duzenli in
                // Düzenleyicinin bilmediği demirbaş/ödünç/düşülme bilgisi korunur
                do {
                    try SchoolLibraryService.requireAdmin()
                    let before = kitap.book
                    let preserved = kitap.preservingRecordFields(of: duzenli)
                    kitap.update(from: BookFieldMetadata.stampChanges(before: before, after: preserved, source: "manual"))
                    try modelContext.save()
                    return .updated
                } catch { modelContext.rollback(); return .failed(error.localizedDescription) }
            })
        }
    }

    private func koleksiyonaGeriAl() {
        guard let kitap = geriAlinacak else { return }
        geriAlinacak = nil
        Task {
            guard await YetkiDurumu.shared.yoneticiOl() else { editError = YetkiDurumu.shared.hata ?? "Yönetici kimliği gerekir."; return }
            TopluKitapIslemi.koleksiyonaGeriAl(kitap)
            do {
                try modelContext.save()
                if let all = try? modelContext.fetch(FetchDescriptor<CatalogBook>()) { CatalogBackup.saveLight(all, force: true) }
            } catch { modelContext.rollback(); editError = "Geri alınamadı: \(error.localizedDescription)" }
        }
    }

    /// Rol kilidi açıkken kimlik doğrulama önce istenir; kullanıcı formu doldurup kaydederken reddedilmez.
    private func duzenlemeyiBaslat(_ kitap: CatalogBook) {
        Task {
            guard await YetkiDurumu.shared.yoneticiOl() else {
                editError = YetkiDurumu.shared.hata ?? "Düzenlemek için yönetici kimliği gerekir."
                return
            }
            duzenlenen = DuzenlemeTaslagi.taslak(kitap: kitap.id) ?? BookDraft(book: kitap.book)
        }
    }

    /// Yalnız dolap ve raf değişir; tam düzenleme formu açılmaz. Yazma yönetici kimliği ister.
    private func yerDegistir(_ kitap: CatalogBook) {
        let dolap = yeniDolap.trimmingCharacters(in: .whitespacesAndNewlines)
        let raf = yeniRaf.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(dolap.isEmpty && raf.isEmpty) else { return }
        Task {
            guard await YetkiDurumu.shared.yoneticiOl() else { editError = YetkiDurumu.shared.hata ?? "Yönetici kimliği gerekir."; return }
            TopluKitapIslemi.yer(dolap: dolap, raf: raf, [kitap])
            do { try modelContext.save() }
            catch { modelContext.rollback(); editError = "Yer kaydedilemedi: \(error.localizedDescription)" }
        }
    }

    @ViewBuilder
    private func satir(_ ad: String, _ deger: String?) -> some View {
        if let deger, !deger.isEmpty {
            LabeledContent(ad, value: deger)
                .textSelection(.enabled)
        }
    }
}

/// Kitabın nüshaları: her nüshanın demirbaş kodu, durumu (yeni/iyi/yıpranmış) ve rafta/onarımda/kayıp bilgisi.
private struct NushaBolumu: View {
    let kitap: CatalogBook
    @Environment(\.modelContext) private var context
    @Query private var nushalar: [BookCopy]
    @Query private var loans: [ActiveLoan]
    @State private var selected: BookCopy?
    @State private var deleteCandidate: BookCopy?
    @State private var error: String?

    init(kitap: CatalogBook) {
        self.kitap = kitap
        let id = kitap.id
        _nushalar = Query(filter: #Predicate<BookCopy> { $0.bookID == id }, sort: \BookCopy.addedAt)
    }
    var body: some View {
        Section {
            ForEach(nushalar) { copy in
                Button { selected = copy } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(copy.accessionCode.isEmpty ? "Demirbaş kodu belirtilmemiş" : copy.accessionCode).font(.body.monospaced()).foregroundStyle(Color.primary)
                        Text(copy.condition + " · " + copy.status + (loans.contains { $0.copyID == copy.id } ? " · Ödünçte" : "")).font(.subheadline).foregroundStyle(KitapTema.ikincilMetin)
                        if !copy.effectivePlace(for: kitap).isEmpty { Text(copy.effectivePlace(for: kitap)).font(.subheadline).foregroundStyle(.primary) }
                    }.padding(.vertical, 4).frame(minHeight: 44)
                }.accessibilityElement(children: .combine)
                    .swipeActions {
                        Button("Kaydı sil", systemImage: "trash", role: .destructive) { deleteCandidate = copy }
                    }
            }
            Button("Nüsha kaydı ekle", systemImage: "plus.square.on.square") {
                Task {
                    guard await YetkiDurumu.shared.yoneticiOl() else { error = YetkiDurumu.shared.hata ?? "Yönetici kimliği gerekir."; return }
                    var ordinal = nushalar.count + 1
                    let prefix = kitap.accessionCode ?? ""
                    var code = prefix.isEmpty ? "" : "\(prefix)-\(ordinal)"
                    while !code.isEmpty && nushalar.contains(where: { $0.accessionCode == code }) { ordinal += 1; code = "\(prefix)-\(ordinal)" }
                    let copy = BookCopy(bookID: kitap.id, accessionCode: code)
                    context.insert(copy)
                    if nushalar.count + 1 > (kitap.quantity ?? 1) { kitap.quantity = nushalar.count + 1 }
                    do { try context.save(); selected = copy }
                    catch { context.rollback(); self.error = error.localizedDescription }
                }
            }
        } header: { Text("Nüsha kayıtları (\(nushalar.count))") }
          footer: { Text("Her fiziksel nüshanın demirbaşını ve durumunu ayrı izleyin. Nüsha kaydını silmek toplam kitap adedini değiştirmez; ödünçteki nüsha silinemez.") }
        .sheet(item: $selected) { copy in NushaDuzenlemeSayfasi(copy: copy) }
        .confirmationDialog("Nüsha kaydı silinsin mi?", isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }), titleVisibility: .visible) {
            Button("Nüsha kaydını sil", role: .destructive) {
                Task {
                    guard let copy = deleteCandidate else { return }
                    guard await YetkiDurumu.shared.yoneticiOl() else { error = YetkiDurumu.shared.hata ?? "Yönetici kimliği gerekir."; return }
                    guard !loans.contains(where: { $0.copyID == copy.id }) else { error = "Ödünçteki nüshanın kaydı silinemez. Önce iade alın."; deleteCandidate = nil; return }
                    context.delete(copy)
                    do { try context.save(); deleteCandidate = nil }
                    catch { context.rollback(); self.error = error.localizedDescription }
                }
            }
        } message: { Text("Demirbaş ve durum bilgisi silinir. Katalogdaki fiziksel toplam adet korunur.") }
        .alert("İşlem tamamlanamadı", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Tamam", role: .cancel) { } } message: { Text(error ?? "") }
    }
}

// MARK: - Görünümler, sayfalayıcı, kategori ızgarası, seri listesi

enum KitaplarGorunumu: String, CaseIterable, Identifiable {
    case kitaplar = "Kitaplar"
    case kategoriler = "Kategoriler"
    case seriler = "Seriler"
    case raflar = "Raflar"
    var id: String { rawValue }
    var ikon: String {
        switch self {
        case .kitaplar: "books.vertical"
        case .kategoriler: "square.grid.2x2"
        case .seriler: "rectangle.stack"
        case .raflar: "cabinet"
        }
    }
}

/// Kitaplar listesinin o anki (filtreli, sıralı) sırası: ayrıntıda sağa-sola gezinmek için.
@Observable
final class KitapSirasi {
    static let shared = KitapSirasi()
    var ids: [UUID] = []
}

/// Ayrıntı sayfaları arasında yatay sayfa sayfa gezinme (Fotoğraflar gibi).
struct KitapSayfalari: View {
    let ids: [UUID]
    @State private var konum: UUID

    init(baslangic: UUID) {
        let sira = KitapSirasi.shared.ids
        ids = sira.contains(baslangic) ? sira : [baslangic]
        _konum = State(initialValue: baslangic)
    }

    private var sayac: String {
        guard ids.count > 1, let i = ids.firstIndex(of: konum) else { return "" }
        return "\(i + 1) / \(ids.count)"
    }

    var body: some View {
        TabView(selection: $konum) {
            ForEach(ids, id: \.self) { id in
                Group {
                    if konum == id {
                        KitapDetaySayfasi(kitapID: id, sayfalamada: true)
                    } else {
                        // UIKit List hücreleri komşu sayfadan AX'e sızmasın.
                        Color.clear.accessibilityHidden(true)
                    }
                }
                .tag(id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle(sayac)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: konum)
        .accessibilityAdjustableAction { direction in
            guard let index = ids.firstIndex(of: konum) else { return }
            switch direction {
            case .increment where ids.indices.contains(index + 1): konum = ids[index + 1]
            case .decrement where ids.indices.contains(index - 1): konum = ids[index - 1]
            default: break
            }
        }
        .accessibilityHint(ids.count > 1 ? "Sağa ya da sola kaydırarak önceki veya sonraki kitaba geçin" : "")
    }
}

/// Kategoriler: renkli, sayılı kartlar; dokununca o kategori süzülür.
struct KategoriIzgarasi: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let kitaplar: [CatalogBook]
    let sec: (String) -> Void

    var body: some View {
        let dagilim = KategoriDagilimi.hesapla(kitaplar)
        if dagilim.isEmpty {
            ContentUnavailableView("Kategori yok", systemImage: "square.grid.2x2",
                                   description: Text("Kitap eklendikçe kategoriler burada renkli kartlar olarak görünür."))
                .frame(maxHeight: .infinity)
        } else {
        ScrollView {
            LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                ForEach(dagilim, id: \.ad) { kategori in
                    Button { sec(kategori.ad) } label: {
                        RenkliKart(baslik: kategori.ad, altBaslik: "\(kategori.baslik) başlık · \(kategori.nusha) nüsha",
                                   ikon: "tag.fill", renk: KitapTema.kitapRengi(kategori.ad))
                    }
                    .buttonStyle(.kitapSade)
                    .kaydirmaEfekti()
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        }
    }
}

/// Seriler: kaç cilt var, eksik ciltler; dokununca seri süzülür (cilt sırasıyla).
struct SeriListesi: View {
    let kitaplar: [CatalogBook]
    let sec: (String) -> Void

    var body: some View {
        let seriler = SeriAnalizi.ozet(kitaplar)
        if seriler.isEmpty {
            ContentUnavailableView("Seri yok", systemImage: "rectangle.stack",
                                   description: Text("Kitap düzenlerken seri adı ve cilt girin."))
                .frame(maxHeight: .infinity)
        } else {
            List(seriler, id: \.seri) { satir in
                Button { sec(satir.seri) } label: {
                    HStack {
                        Image(systemName: "rectangle.stack.fill")
                            .foregroundStyle(KitapTema.kitapRengi(satir.seri))
                        VStack(alignment: .leading) {
                            Text(satir.seri).font(.headline)
                            Text("\(satir.sayi) cilt")
                                .font(.caption)
                                .foregroundStyle(KitapTema.ikincilMetin)
                            // Eksik cilt yalnız turuncu renkle değil, uyarı ikonuyla belirtilir
                            if !satir.eksik.isEmpty {
                                Label("Eksik cilt: " + satir.eksik.map(String.init).joined(separator: ", "),
                                      systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .labelStyle(RenkliIkonEtiketi(renk: KitapTema.vurgu))
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(Color.primary)
            }
        }
    }
}

private struct KosulluBaslik: ViewModifier {
    let baslik: String?
    func body(content: Content) -> some View {
        if let baslik {
            content.navigationTitle(baslik).navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }
}
