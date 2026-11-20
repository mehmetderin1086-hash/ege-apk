import SwiftUI

/// Katalog araçları panelinden seçilen eylem. ContentView bunları kendi sayfa/işlem
/// bayraklarına çevirir; panel hiçbir iç duruma doğrudan dokunmaz.
enum KatalogAraci: Hashable {
    case saveView
    case applySavedView(UUID)
    case clearSavedViews
    case amazonComplete
    case duplicates
    case loans
    case students
    case classLoan
    case textbooks
    case champions
    case usageReport
    case studentCards
    case accessionRegister
    case statistics
    case reportCenter
    case excelExport
    case dataQuality
    case fieldMerge
    case inventory
    case shelfScan
    case batchQueue
    case undoSession
    case undoBulk
    case csvImport
    case restoreBackup
    case archiveExport
    case archiveImport
    case settings
}

/// Tek ad kaynağı: Yönetim listesi ve Katalog Yönetimi'ndeki araç paneli aracın adını,
/// açıklamasını ve ikonunu buradan okur; aynı araç iki ekranda farklı adla anılmaz.
/// Görünüm kaydetme, uygulama ve temizleme birer araç değildir: başlıkları `nil` döner.
extension KatalogAraci {
    var aracBasligi: String? {
        switch self {
        case .saveView, .applySavedView, .clearSavedViews: nil
        case .amazonComplete: "Eksik bilgileri tamamla"
        case .duplicates: "Mükerrerleri incele"
        case .loans: "Ödünç listesi"
        case .students: "Öğrenciler"
        case .classLoan: "Sınıfa toplu ödünç"
        case .textbooks: "Ders kitabı dağıtımı"
        case .champions: "Okuma şampiyonları"
        case .usageReport: "Kullanım raporu"
        case .studentCards: "Öğrenci kartları"
        case .accessionRegister: "Demirbaş defteri"
        case .statistics: "Katalog istatistikleri"
        case .reportCenter: "Rapor merkezi"
        case .excelExport: "Excel’e aktar"
        case .dataQuality: "Eksik alan panosu"
        case .fieldMerge: "Yazar ve yayınevi adları"
        case .inventory: "Raf sayımı"
        // Ekle'deki kartla aynı ad
        case .shelfScan: "Raf sırtları"
        case .batchQueue: "Bekleyen taramalar"
        case .undoSession: "Son eklemeleri geri al"
        case .undoBulk: "Son toplu işi geri al"
        case .csvImport: "Tablodan içe aktar"
        case .restoreBackup: "Eski yedeği yükle"
        case .archiveExport: "Tam arşiv oluştur"
        case .archiveImport: "Arşivden geri yükle"
        case .settings: "Ayarlar"
        }
    }

    /// Kısa açıklama: Yönetim satırında ve panel kartında kesilmeden gösterilir.
    /// Teknik dosya kısaltmaları (XLSX, ZIP, JSON) yok.
    var aciklama: String {
        switch self {
        case .saveView, .applySavedView, .clearSavedViews: ""
        case .amazonComplete: "ISBN’li kayıtların eksiklerini bul"
        case .duplicates: "Aynı kitapları ve farklı baskıları karşılaştır"
        case .loans: "Ödünç sekmesini açar: ver, iade al, uzat"
        case .students: "Öğrenci ve sınıf listeleri, içe aktarma"
        case .classLoan: "Sınıfa kitap dağıtımı ve takibi"
        case .textbooks: "Sınıf bazında dağıtım"
        case .champions: "Okuma etkinliği ve öğrenci sıralaması"
        case .usageReport: "Resmî, imzaya hazır PDF"
        case .studentCards: "Barkodlu kartları önizle ve bas"
        case .accessionRegister: "Yazdırılabilir kayıt defteri ve tablo"
        case .statistics: "Kitap başlıkları ve okuma durumu"
        case .reportCenter: "Filtreli liste, grafik, etiket ve tablo"
        case .excelExport: "Kapaklı Excel tablosu"
        case .dataQuality: "ISBN, yazar, yayınevi, kategori ve kapak"
        case .fieldMerge: "Farklı yazımları birleştir"
        case .inventory: "Raf raf barkod sayımı ve tutanak"
        case .shelfScan: "Raf fotoğrafından kitapları oku ve say"
        case .batchQueue: "Onaylanmamış taslakları incele"
        case .undoSession: "Son ekleme oturumundaki kayıtlar"
        case .undoBulk: "Bu sayfadaki son toplu değişiklik"
        case .csvImport: "Excel ya da CSV listesinden kitaplar"
        case .restoreBackup: "Önceki sürümlerin yedek dosyası"
        case .archiveExport: "Kapak, öğrenci, nüsha ve ödünçlerle tek dosya"
        case .archiveImport: "Tam arşiv dosyasını incele ve yükle"
        case .settings: "Görünüm, tarama, güvenlik ve yardım"
        }
    }

    var ikon: String {
        switch self {
        case .saveView: "square.and.arrow.down.on.square"
        case .applySavedView: "bookmark"
        case .clearSavedViews: "trash"
        case .amazonComplete: "wand.and.stars"
        case .duplicates: "arrow.triangle.merge"
        case .loans: "person.badge.clock"
        case .students: "person.3"
        case .classLoan: "person.3.sequence"
        case .textbooks: "backpack"
        case .champions: "trophy"
        case .usageReport: "doc.badge.clock"
        case .studentCards: "person.text.rectangle"
        case .accessionRegister: "list.number"
        case .statistics: "chart.bar"
        case .reportCenter: "doc.richtext"
        case .excelExport: "tablecells"
        case .dataQuality: "chart.bar.doc.horizontal"
        case .fieldMerge: "text.badge.checkmark"
        case .inventory: "checklist"
        case .shelfScan: "books.vertical.circle"
        case .batchQueue: "tray.full"
        case .undoSession: "arrow.uturn.backward"
        case .undoBulk: "arrow.uturn.backward.circle"
        case .csvImport: "square.and.arrow.down"
        case .restoreBackup: "arrow.clockwise.icloud"
        case .archiveExport: "archivebox"
        case .archiveImport: "archivebox.fill"
        case .settings: "gearshape"
        }
    }

    /// Araç Katalog Yönetimi sayfasının durumuna (seçim, görünüm, kuyruk, ekleme oturumu,
    /// dışa aktarma işçisi) bağlı mı? Bağlı olmayanları Yönetim, o sayfayı açmadan doğrudan sunar.
    /// Ödünç listesi sekmeye, Ayarlar kendi kilitli sayfasına gider; ikisi de bağlam istemez.
    var katalogBaglamiGerekir: Bool {
        switch self {
        case .students, .classLoan, .textbooks, .champions, .usageReport, .studentCards, .reportCenter,
             .dataQuality, .fieldMerge, .inventory, .duplicates, .shelfScan, .loans, .settings:
            false
        case .saveView, .applySavedView, .clearSavedViews, .amazonComplete, .accessionRegister, .statistics,
             .excelExport, .batchQueue, .undoSession, .undoBulk, .csvImport, .restoreBackup, .archiveExport, .archiveImport:
            true
        }
    }
}

/// Eski 35 maddelik açılır menünün yerini alan kartlı, aranabilir araç paneli.
/// Görünüm/filtre/sıralama üstte çip olarak; araçlar bölümlere ayrılmış, aranabilir,
/// renkli kartlar hâlinde. Telefonda 2, tablette 3–4 sütun.
struct KatalogAraclarPaneli: View {
    @Binding var layout: CatalogLayout
    @Binding var filter: CatalogFilter
    @Binding var sort: CatalogSort

    let savedViews: [SavedView]
    let pendingQueueCount: Int
    let undoSessionCount: Int
    let bulkUndoCount: Int
    let isBusy: Bool
    let catalogEmpty: Bool
    let onAction: (KatalogAraci) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var search = ""
    @State private var temizlemeOnayi = false

    /// Ad, açıklama ve ikon tek kaynaktan (`KatalogAraci`); panel yalnız renk ve durum ekler.
    fileprivate struct Arac: Identifiable {
        let eylem: KatalogAraci
        let renk: Color
        var rozet: String? = nil
        var kapali = false
        var yikici = false
        var id: KatalogAraci { eylem }
        var baslik: String { eylem.aracBasligi ?? "" }
        var altBaslik: String { eylem.aciklama }
        var ikon: String { eylem.ikon }
    }

    private struct Bolum: Identifiable {
        let baslik: String
        let ikon: String
        let renk: Color
        let araclar: [Arac]
        var id: String { baslik }
    }

    private var bolumler: [Bolum] {
        [
            Bolum(baslik: "Ödünç ve Öğrenciler", ikon: "person.2.fill", renk: KitapTema.amazon, araclar: [
                Arac(eylem: .loans, renk: KitapTema.amazon),
                Arac(eylem: .classLoan, renk: KitapTema.amazon),
                Arac(eylem: .students, renk: KitapTema.amazon),
                Arac(eylem: .textbooks, renk: KitapTema.amazon),
                Arac(eylem: .champions, renk: KitapTema.vurgu)
            ]),
            Bolum(baslik: "Raporlar ve Baskı", ikon: "printer.fill", renk: KitapTema.dosya, araclar: [
                Arac(eylem: .statistics, renk: KitapTema.dosya, kapali: catalogEmpty),
                Arac(eylem: .reportCenter, renk: KitapTema.dosya, kapali: catalogEmpty),
                Arac(eylem: .excelExport, renk: KitapTema.basari, kapali: catalogEmpty || isBusy),
                Arac(eylem: .usageReport, renk: KitapTema.dosya),
                Arac(eylem: .accessionRegister, renk: KitapTema.dosya),
                Arac(eylem: .studentCards, renk: KitapTema.dosya)
            ]),
            Bolum(baslik: "Katalog Bakımı", ikon: "wrench.and.screwdriver.fill", renk: KitapTema.foto, araclar: [
                Arac(eylem: .amazonComplete, renk: KitapTema.foto, kapali: isBusy),
                Arac(eylem: .dataQuality, renk: KitapTema.foto),
                Arac(eylem: .duplicates, renk: KitapTema.foto),
                Arac(eylem: .fieldMerge, renk: KitapTema.foto),
                Arac(eylem: .inventory, renk: KitapTema.foto, kapali: catalogEmpty),
                Arac(eylem: .shelfScan, renk: KitapTema.foto),
                Arac(eylem: .batchQueue, renk: KitapTema.vurgu,
                     rozet: pendingQueueCount > 0 ? "\(pendingQueueCount)" : nil, kapali: pendingQueueCount == 0),
                Arac(eylem: .undoSession, renk: .red,
                     rozet: undoSessionCount > 0 ? "\(undoSessionCount)" : nil, kapali: undoSessionCount == 0, yikici: true),
                Arac(eylem: .undoBulk, renk: .red,
                     rozet: bulkUndoCount > 0 ? "\(bulkUndoCount)" : nil, kapali: bulkUndoCount == 0, yikici: true)
            ]),
            Bolum(baslik: "Yedek ve Aktarım", ikon: "externaldrive.fill", renk: KitapTema.ana, araclar: [
                Arac(eylem: .csvImport, renk: KitapTema.ana),
                Arac(eylem: .archiveExport, renk: KitapTema.ana, kapali: catalogEmpty || isBusy),
                Arac(eylem: .archiveImport, renk: KitapTema.ana),
                Arac(eylem: .restoreBackup, renk: KitapTema.ana),
                Arac(eylem: .settings, renk: .gray)
            ])
        ]
    }

    private var aramaTerimi: String { CatalogMatcher.normalize(search) }

    private func suzulmus(_ bolum: Bolum) -> [Arac] {
        guard !aramaTerimi.isEmpty else { return bolum.araclar }
        return bolum.araclar.filter {
            CatalogMatcher.normalize($0.baslik + " " + $0.altBaslik).contains(aramaTerimi)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if aramaTerimi.isEmpty {
                        gorunumBolumu
                        kayitliGorunumler
                    }
                    ForEach(bolumler) { bolum in
                        let araclar = suzulmus(bolum)
                        if !araclar.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(bolum.baslik, systemImage: bolum.ikon)
                                    .font(.headline)
                                    .foregroundStyle(bolum.renk)
                                    .accessibilityAddTraits(.isHeader)
                                // Tembel değil: büyük yazıda ekran dışı kartlar erişilebilirlik ağacından düşmez.
                                EsitSutunIzgara(sutun: typeSize.isAccessibilitySize ? 1 : nil,
                                                enKucukGenislik: typeSize >= .xxLarge ? 280 : 160) {
                                    ForEach(araclar) { arac in
                                        Button {
                                            sec(arac.eylem)
                                        } label: {
                                            AracKarti(arac: arac)
                                        }
                                        .buttonStyle(.kitapKart(arac.renk))
                                        .disabled(arac.kapali)
                                        .accessibilityLabel(arac.baslik + (arac.rozet.map { ", \($0)" } ?? ""))
                                        .accessibilityHint(arac.altBaslik)
                                    }
                                }
                            }
                        }
                    }
                    if !aramaTerimi.isEmpty, bolumler.allSatisfy({ suzulmus($0).isEmpty }) {
                        ContentUnavailableView.search(text: search)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Araçlar")
            .navigationBarTitleDisplayMode(.inline)
            // Arama üstte sabit: alttaki varsayılan çubuk son kart sırasının üzerine biniyordu
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Araç ara (ödünç, rapor, yedek…)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }

    // MARK: Görünüm çipleri

    private var gorunumBolumu: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Görünüm", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(KitapTema.ana)
                .accessibilityAddTraits(.isHeader)
            SecimCipleri(baslik: "Düzen", secim: $layout, renk: KitapTema.ana) { ($0.rawValue, $0.icon) }
            SecimCipleri(baslik: "Filtre", secim: $filter, renk: KitapTema.vurgu) { ($0.rawValue, $0.icon) }
            SecimCipleri(baslik: "Sıralama", secim: $sort, renk: KitapTema.amazon) { ($0.rawValue, $0.icon) }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private var kayitliGorunumler: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Kayıtlı Görünümler", systemImage: "bookmark.square")
                .font(.headline)
                .foregroundStyle(KitapTema.toplu)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        sec(.saveView)
                    } label: {
                        Label("Bu Görünümü Kaydet", systemImage: "square.and.arrow.down.on.square")
                    }
                    .buttonStyle(.kitapTonlu(KitapTema.toplu))
                    ForEach(savedViews) { view in
                        Button {
                            sec(.applySavedView(view.id))
                        } label: {
                            Label(view.name, systemImage: "bookmark")
                        }
                        .buttonStyle(.kitapTonlu(KitapTema.toplu))
                    }
                    if !savedViews.isEmpty {
                        Button(role: .destructive) {
                            temizlemeOnayi = true
                        } label: {
                            Label("Temizle", systemImage: "trash")
                        }
                        .buttonStyle(.kitapTonlu(.red))
                        .confirmationDialog("\(savedViews.count) kayıtlı görünüm silinsin mi? Bu işlem geri alınamaz.",
                                            isPresented: $temizlemeOnayi, titleVisibility: .visible) {
                            Button("Tümünü Sil", role: .destructive) { sec(.clearSavedViews) }
                            Button("Vazgeç", role: .cancel) { }
                        }
                    }
                }
            }
        }
    }

    private func sec(_ eylem: KatalogAraci) {
        onAction(eylem)
        dismiss()
    }
}

/// Panel kartı: renkli ikon karesi, ad, açıklama ve isteğe bağlı sayı rozeti.
private struct AracKarti: View {
    let arac: KatalogAraclarPaneli.Arac

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: arac.ikon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(arac.renk.gradient, in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                // Metin küçülmez ve kesilmez; uzun açıklamada ya da büyük yazıda kart uzar
                Text(arac.baslik)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(arac.yikici ? .red : .primary)
                    .allowsTightening(true)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(arac.altBaslik)
                    .font(.caption)
                    .foregroundStyle(KitapTema.ikincilMetin)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let rozet = arac.rozet {
                Text(rozet)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(arac.renk, in: .capsule)
            }
        }
        .padding(12)
        // Kısa kart da en az 96 pt: komşusunun yanında belirgin kısa kalmasın.
        // Açıklamalar Yönetim listesiyle ortaktır; dar kartta dört satıra uzayabilir, kesilmez.
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
    }
}

/// Tek seçimli çip sırası (görünüm/filtre/sıralama).
struct SecimCipleri<T: CaseIterable & Hashable & Identifiable>: View where T.AllCases: RandomAccessCollection {
    let baslik: String
    @Binding var secim: T
    let renk: Color
    let etiket: (T) -> (String, String)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(baslik)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(T.allCases)) { deger in
                        let (ad, ikon) = etiket(deger)
                        let secili = deger == secim
                        Button {
                            secim = deger
                        } label: {
                            Label(ad, systemImage: ikon)
                                .font(.footnote.weight(secili ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(minHeight: 44)
                                .background(secili ? renk : renk.opacity(0.12), in: .capsule)
                                .foregroundStyle(secili ? .white : renk)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(secili ? [.isSelected] : [])
                        .accessibilityLabel("\(baslik): \(ad)")
                    }
                }
            }
        }
    }
}
