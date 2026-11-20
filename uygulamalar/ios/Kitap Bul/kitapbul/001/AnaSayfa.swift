import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

/// Ana sayfa (pano): karşılama, üç ana görev, istatistik kartları, hızlı işlemler, geciken
/// ödünçler, araç kartları ve yatay kaydırılan kapak rafları (raflar yatayda kapak kapak kayar).
struct AnaSayfa: View {
    @Query(sort: \CatalogBook.addedAt, order: .reverse) private var kitaplar: [CatalogBook]
    @Query(sort: \ActiveLoan.dueDate) private var loans: [ActiveLoan]
    @Query private var copies: [BookCopy]
    @Query private var reservations: [Reservation]
    @AppStorage(Tasarim.sadeModAnahtari) private var sadeMod = false
    @AppStorage("schoolName") private var okulAdi = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Tasarim.efektAnahtari) private var effects = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.sekmeDegistir) private var sekmeDegistir
    /// Büyük yazı boyutunda sütun sayısı azalır: yazılar kırpılmadan sığar
    @Environment(\.dynamicTypeSize) private var yaziBoyutu
    private var buyukYazi: Bool { sadeMod || yaziBoyutu >= .xxLarge }
    @Namespace private var kapakAlani
    /// Türetilmiş özetler (sayılar, raflar) girdiler değişince bir kez hesaplanır; gövde yalnız okur.
    @State private var panel = HomeDashboardModel()
    /// Sekme her görününce artar; panel en çok dakikada bir yeniden hesaplanır.
    @State private var gorunumSayaci = 0
    /// Masa modu: ekran kapanmaz; kütüphane masasında sürekli tarama için.
    @State private var masaModu = false

    @State private var ayarlarAcik = false
    @State private var aramaAcik = false
    /// Barkod masası hangi modda açık (ödünç ya da iade); `nil` kapalı.
    @State private var hizliOduncModu: HizliOduncSayfasi.Mode?
    @State private var yol: [UUID] = []
    @State private var selectedLoan: ActiveLoan?
    @AppStorage(HomeQuickActionPreferences.storageKey) private var quickActionsRaw = HomeQuickActionPreferences.defaultRaw
    @State private var quickActionsConfigurationOpen = false
    private var quickActionPreferences: HomeQuickActionPreferences { .load(quickActionsRaw) }
    private var visibleQuickActions: [HomeQuickAction] { quickActionPreferences.visibleActions(simpleMode: sadeMod) }

    private let derinBaglanti = DerinBaglanti.shared

    private var girdi: HomeInputs {
        HomeInputs(kitaplar: kitaplar, loans: loans, copies: copies, gorunumSayaci: gorunumSayaci)
    }

    var body: some View {
        NavigationStack(path: $yol) {
            ScrollView {
                // Tembel değil: büyük yazıda ekranın altına itilen bölümler erişilebilirlik ağacında kalır
                VStack(alignment: .leading, spacing: 18) {
                    karsilama
                    birincilGorevler
                    istatistikler
                        .kaydirmaEfekti()
                    hizliIslemler
                        .kaydirmaEfekti()
                    if !panel.gecikenler.isEmpty { gecikenBolumu.kaydirmaEfekti() }
                    // Araçlar raflardan önce: kapak rafları uzun, araç kartları ilk kaydırmada görünsün
                    if !sadeMod { araclar.kaydirmaEfekti() }
                    if !sadeMod { raflar }
                }
                .scrollTargetLayout()
                .padding(.bottom, 30)
            }
            .okunurAltKaydirmaKenari()
            // Günlük görevler serbestçe kaydırılır; bölüm başına zorunlu durak yok.
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ana Sayfa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        ayarlarAcik = true
                    } label: {
                        Label("Ayarlar", systemImage: "gearshape.fill")
                    }
                    .tint(.primary)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                KitapDetaySayfasi(kitapID: id)
                    .zoomHedefi(id, kapakAlani)
            }
            .sheet(isPresented: $ayarlarAcik) {
                YoneticiKilidi(baslik: "Ayarlar", sadeModAnahtari: true) { SettingsView() }
                    .sayfaVurgusu()
            }
            .sheet(item: $selectedLoan) { OduncDetaySayfasi(loan: $0) }
            .sheet(isPresented: $quickActionsConfigurationOpen) {
                HomeQuickActionsConfiguration(rawPreferences: $quickActionsRaw)
            }
            .sheet(isPresented: $aramaAcik) { AramaSekmesi() }
            .fullScreenCover(item: $hizliOduncModu) { HizliOduncSayfasi(baslangic: $0) }
            .task(id: girdi) { panel.guncelle(girdi: girdi, books: kitaplar, copies: copies, loans: loans) }
            .onAppear { gorunumSayaci += 1; masaModunuUygula() }
            .onDisappear { Self.ekranKapanmasin(false) }
            .onChange(of: masaModu) { masaModunuUygula() }
            .onChange(of: scenePhase) { _, faz in if faz == .active { gorunumSayaci += 1 } }
            // kitapbul://odunc ve kitapbul://iade: barkod masası ilgili kipte açılır
            .onChange(of: KutuphaneRotasi.shared.bekleyenOduncModu, initial: true) { _, mod in
                guard let mod else { return }
                KutuphaneRotasi.shared.bekleyenOduncModu = nil
                hizliOduncModu = mod
            }
        }
    }

    private func masaModunuUygula() { Self.ekranKapanmasin(masaModu) }

    private static func ekranKapanmasin(_ acik: Bool) {
#if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = acik
#endif
    }

    // MARK: Karşılama

    private var selam: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Günaydın"
        case 12..<18: "İyi günler"
        default: "İyi akşamlar"
        }
    }

    private var karsilama: some View {
        ZStack(alignment: .bottomLeading) {
            // Kısa başlık: hızlı işlemler ilk ekranda sekme çubuğunun üstünde kalsın
            CanliGradyan()
                .frame(minHeight: sadeMod ? 104 : 116)
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(selam)
                    .font(.system(.title, design: .rounded, weight: .bold))
                if !okulAdi.isEmpty {
                    // Uzun okul adı küçülmek yerine iki satıra sarar
                    Text(okulAdi)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(Date.now.formatted(.dateTime.day().month(.wide).weekday(.abbreviated).locale(Locale(identifier: "tr_TR"))))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.3), radius: 4)
            .padding(16)
        }
        .clipShape(.rect(cornerRadius: 26))
        .padding(.horizontal)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    // MARK: İstatistikler

    private var istatistikler: some View {
        let kpi = panel.kpi
        return VStack(alignment: .leading, spacing: 12) {
            bolumBasligi("Kütüphane ve bugün", ikon: "chart.bar.xaxis")
            EsitSutunIzgara(sutun: yaziBoyutu.isAccessibilitySize ? 1 : (buyukYazi ? 2 : 3)) {
                Button { kitaplaraGit(.tumu) } label: {
                    IstatistikKarti(deger: kpi.baslik, baslik: "Kitap başlığı", ikon: "books.vertical.fill", renk: KitapTema.ana)
                }.accessibilityIdentifier("home.titles")
                Button { kitaplaraGit(.tumu) } label: {
                    IstatistikKarti(deger: kpi.nusha, baslik: "Fiziksel nüsha", ikon: "square.stack.3d.up.fill", renk: KitapTema.toplu)
                }.accessibilityIdentifier("home.copies")
                Button { odunceGit(.etkin) } label: {
                    IstatistikKarti(deger: kpi.odunc, baslik: "Ödünçte", ikon: "person.badge.clock.fill", renk: KitapTema.amazon)
                }.accessibilityIdentifier("home.loans")
                Button { odunceGit(.geciken) } label: {
                    IstatistikKarti(deger: kpi.geciken, baslik: "Gecikmiş", ikon: "exclamationmark.circle.fill", renk: .red)
                }.accessibilityIdentifier("home.overdue")
                Button { odunceGit(.etkin, bugun: true) } label: {
                    IstatistikKarti(deger: kpi.bugunIade, baslik: "Bugün iade", ikon: "calendar.badge.clock", renk: KitapTema.dosya)
                }.accessibilityIdentifier("home.dueToday")
                if !sadeMod {
                    Button { kitaplaraGit(.eksik) } label: {
                        IstatistikKarti(deger: kpi.eksik, baslik: "Eksik bilgi", ikon: "text.badge.checkmark", renk: KitapTema.vurgu)
                    }
                }
            }
            .buttonStyle(.kitapSade)
        }
        .padding(.horizontal)
    }

    private func odunceGit(_ bolum: OduncSekmesi.Bolum, bugun: Bool = false) {
        KutuphaneRotasi.shared.oduncBolumu = bolum
        KutuphaneRotasi.shared.bugunIadeler = bugun
        sekmeyeGit(.odunc)
    }
    private func kitaplaraGit(_ filtre: KitapDurumFiltresi) {
        KutuphaneRotasi.shared.kitapFiltresi = filtre
        sekmeyeGit(.kitaplar)
    }

    // MARK: Hızlı işlemler

    /// Üç ana görev tercihlerden bağımsız, istatistiklerden önce gelir. Altındaki "Kitap nerede?"
    /// satırı bir görev değildir (`HomePrimaryTask`'a girmez); aramayı tek dokunuşla açar.
    private var birincilGorevler: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(HomeQuickActionPreferences.primaryTasks) { task in
                Button { performPrimaryTask(task) } label: {
                    Label(task.title, systemImage: task.icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.task.\(task.rawValue)")
            }
            kitapNerede
            Toggle(isOn: $masaModu) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Masa modu").font(.body.weight(.semibold))
                    Text("Ekran kapanmaz; kütüphane masasında sürekli tarama için")
                        .font(.subheadline).foregroundStyle(KitapTema.ikincilMetin)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 44)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            .accessibilityIdentifier("home.deskMode")
        }
        .padding(.horizontal)
    }

    private var kitapNerede: some View {
        Button { aramaAcik = true } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kitap nerede?")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Text("Ad, yazar, ISBN, demirbaş")
                        .font(.subheadline)
                        .foregroundStyle(KitapTema.ikincilMetin)
                }
            } icon: {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Kitabın yerini ve rafta olup olmadığını gösterir")
        .accessibilityIdentifier("home.findBook")
    }

    private func performPrimaryTask(_ task: HomePrimaryTask) {
        switch task {
        case .lend: hizliOduncModu = .lend
        // Elde kitapla iade: liste yerine barkod masası iade modunda, öğrenci seçmeden açılır.
        case .returnLoan: hizliOduncModu = .giveBack
        case .addBook: sekmeyeGit(.katalog)
        }
    }

    private var hizliIslemler: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                bolumBasligi("Hızlı işlemler", ikon: "bolt.fill")
                Spacer(minLength: 4)
                Button { quickActionsConfigurationOpen = true } label: {
                    Label("Düzenle", systemImage: "slider.horizontal.3")
                        .font(.body)
                        .foregroundStyle(Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hızlı işlemleri düzenle")
                .accessibilityIdentifier("home.actions.edit")
            }
            if visibleQuickActions.isEmpty {
                Text("Ek kısayol seçilmedi. Düzenle ile ekleyebilirsiniz.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let actions = visibleQuickActions
                let columnCount = yaziBoyutu.isAccessibilitySize ? 1 : (buyukYazi ? 2 : 4)
                // En fazla sekiz kontrol: iç içe lazy grid yerine bütün düğmelerin kimliği korunur.
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    ForEach(Array(stride(from: 0, to: actions.count, by: columnCount)), id: \.self) { start in
                        GridRow {
                            ForEach(Array(actions.dropFirst(start).prefix(columnCount))) { action in
                                HizliDugme(ad: action.title, ikon: action.icon, renk: action.tint, ipucu: action.ipucu, sade: sadeMod) {
                                    performQuickAction(action)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }

    /// Sekiz eski route tek noktada tutulur; kişiselleştirme callback kopyalamaz.
    private func performQuickAction(_ action: HomeQuickAction) {
        switch action {
        case .barcode: ekle(.barkod)
        case .cover: ekle(.canliKapak)
        case .voice: ekle(.ses)
        case .loan: hizliOduncModu = .lend
        case .serial: ekle(.seri)
        case .manual: ekle(.elle)
        case .assistant:
            derinBaglanti.asistanDinle = true
            sekmeyeGit(.asistan)
        case .management: sekmeyeGit(.yonetim)
        }
    }

    private func ekle(_ eylem: HizliEylem) {
        derinBaglanti.bekleyenEylem = eylem
        sekmeyeGit(.katalog)
    }

    private func sekmeyeGit(_ sekme: MainTabView.Sekme) {
        derinBaglanti.hedefSekme = sekme
    }

    // MARK: Raflar

    private var raflar: some View {
        VStack(alignment: .leading, spacing: 22) {
            raf("Yeni gelenler", ikon: "sparkles", renk: KitapTema.ana, kitaplar: panel.yeniGelenler)
            if !panel.populer.isEmpty {
                raf("En çok ödünç verilenler", ikon: "flame.fill", renk: KitapTema.vurgu, kitaplar: panel.populer)
            }
            if !panel.okunmayan.isEmpty {
                raf("Keşfedilmeyi bekleyenler", ikon: "eye.slash", renk: KitapTema.foto, kitaplar: panel.okunmayan)
            }
            ForEach(panel.kategoriRaflari, id: \.ad) { kategori in
                raf(kategori.ad, ikon: "tag.fill", renk: KitapTema.kitapRengi(kategori.ad), kitaplar: kategori.kitaplar)
            }
        }
    }

    @ViewBuilder
    private func raf(_ baslik: String, ikon: String, renk: Color, kitaplar: [CatalogBook]) -> some View {
        if !kitaplar.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                bolumBasligi(baslik, ikon: ikon, renk: renk)
                    .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(kitaplar) { kitap in
                            NavigationLink(value: kitap.id) {
                                RafKapagi(kitap: kitap)
                                    .zoomKaynagi(kitap.id, kapakAlani)
                            }
                            .buttonStyle(.kitapSade)
                            .yatayKaydirmaEfekti()
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
                // Kapak kapak durur (yatay sayfa sayfa)
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    // MARK: Gecikenler

    private var gecikenBolumu: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { odunceGit(.geciken) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    bolumBasligi("Geciken ödünçler (\(panel.gecikenler.count))", ikon: "exclamationmark.triangle.fill", renk: .red)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.forward")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Gecikenlerin tümünü gör")
            .accessibilityValue("\(panel.gecikenler.count) gecikmiş ödünç")
            VStack(spacing: 0) {
                // En çok üç satır; tümü başlıktaki düğmeyle Ödünç sekmesinde
                ForEach(panel.gecikenler.prefix(3)) { loan in
                    Button { selectedLoan = loan } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(loan.bookTitleSnapshot).font(.subheadline.weight(.semibold))
                                Text("\(loan.studentName)\(loan.studentClass.isEmpty ? "" : " · \(loan.studentClass)")")
                                    .font(.caption).foregroundStyle(KitapTema.ikincilMetin)
                                Text(loan.dueDate, format: .relative(presentation: .named))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.red)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "person.crop.circle.badge.exclamationmark")
                                .foregroundStyle(.red)
                                .symbolEffect(.pulse, isActive: !reduceMotion && effects)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.loan.\(loan.id.uuidString)")
                    Divider().padding(.leading, 44)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        }
        .padding(.horizontal)
    }

    // MARK: Araç kartları

    private var araclar: some View {
        VStack(alignment: .leading, spacing: 12) {
            bolumBasligi("Araçlar", ikon: "square.grid.2x2.fill")
            // Tembel değil: kısa ekranda ya da az içerikte ilk görünüme girerse büyük yazıda düşmez
            EsitSutunIzgara(sutun: yaziBoyutu.isAccessibilitySize ? 1 : nil, enKucukGenislik: 160,
                            yatayAralik: 14, dikeyAralik: 14) {
                Button { aiAraclariAcik = true } label: {
                    RenkliKart(baslik: "Yapay zekâ araçları", altBaslik: "Tara, öner, soru üret, analiz", ikon: "sparkles", renk: KitapTema.foto)
                }
                NavigationLink { IstatistikGrafikleri() } label: {
                    // Katalog istatistiklerinden (Yönetim) ayrı: ödünç hareketlerinin grafikleri
                    RenkliKart(baslik: "Ödünç grafikleri", altBaslik: "Aylık ödünç, kategori halkası", ikon: "chart.pie.fill", renk: KitapTema.dosya)
                }
                Button { ogrencilerAcik = true } label: {
                    RenkliKart(baslik: "Öğrenciler", altBaslik: "Profil, sınıf panosu, puan", ikon: "person.3.fill", renk: KitapTema.amazon)
                }
                NavigationLink { RezervasyonlarSayfasi() } label: {
                    RenkliKart(baslik: "Rezervasyon sırası", altBaslik: "Sıradaki öğrenciler", ikon: "bookmark.fill", renk: KitapTema.toplu)
                }
                NavigationLink { DonemRaporuSayfasi() } label: {
                    RenkliKart(baslik: "Dönem Raporu", altBaslik: "İmzaya hazır PDF", ikon: "doc.text.fill", renk: KitapTema.basari)
                }
            }
            .buttonStyle(.kitapSade)
        }
        .padding(.horizontal)
        .sheet(isPresented: $ogrencilerAcik) { StudentsView() }
        .sheet(isPresented: $aiAraclariAcik) { AIToolsView() }
    }

    @State private var ogrencilerAcik = false
    @State private var aiAraclariAcik = false

    private func bolumBasligi(_ baslik: String, ikon: String, renk: Color? = nil) -> some View {
        BolumBasligi(baslik: baslik, ikon: ikon, renk: renk, sade: sadeMod)
    }
}

/// Bölüm başlığı; ana rengi ortamdan okur, böylece tema değişince yerinde güncellenir.
private struct BolumBasligi: View {
    let baslik: String
    let ikon: String
    var renk: Color? = nil
    let sade: Bool
    @Environment(\.temaAna) private var temaAna

    var body: some View {
        Label(baslik, systemImage: ikon)
            .font(sade ? .title2.weight(.bold) : .title3.weight(.bold))
            .foregroundStyle(Color.primary)
            .fixedSize(horizontal: false, vertical: true)
            .labelStyle(RenkliIkonEtiketi(renk: renk ?? temaAna))
            .accessibilityAddTraits(.isHeader)
    }
}

/// Hızlı işlem düğmesi. Basılma tepkisi kendi durumunda tutulur: bir düğmeye basmak bütün
/// Ana Sayfa gövdesini yeniden hesaplatmaz.
private struct HizliDugme: View {
    let ad: String
    let ikon: String
    let renk: Color
    let ipucu: String
    let sade: Bool
    let eylem: () -> Void

    @State private var tetik = 0
    /// İkon etiketle birlikte büyür (sabit 24 pt büyük yazıda küçük kalıyordu).
    @ScaledMetric(relativeTo: .title2) private var hizliIkon: CGFloat = 24
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Tasarim.efektAnahtari) private var effects = true
    @AppStorage("scanHapticsEnabled") private var haptics = true

    var body: some View {
        Button {
            tetik += 1
            eylem()
        } label: {
            VStack(spacing: 6) {
                let ikonBoyu = sade ? hizliIkon * 1.25 : hizliIkon
                Image(systemName: ikon)
                    .font(.system(size: ikonBoyu, weight: .semibold))
                    .foregroundStyle(renk)
                    .symbolEffect(.bounce, value: tetik)
                    .symbolEffectsRemoved(reduceMotion || !effects)
                    .frame(minHeight: ikonBoyu * 1.35)
                Text(ad)
                    .font(sade ? .headline : .footnote.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: sade ? 88 : 66)
            .padding(.vertical, 6)
            .background(renk.opacity(0.13), in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(renk.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: tetik) { _, _ in haptics }
        .accessibilityLabel(ad)
        .accessibilityHint(ipucu)
        .accessibilityIdentifier("home.action.\(ad)")
    }
}

// MARK: - Pano verileri

/// Ana Sayfa özet sayıları. Yönetim sayfası da aynı formülü kullanır (tek kaynak).
struct HomeKPI: Equatable {
    var baslik = 0
    var nusha = 0
    var odunc = 0
    var geciken = 0
    var bugunIade = 0
    var eksik = 0

    /// Düşülmüş kitaplar sayılmaz. Nüsha: kitap başına kayıtlı adet (en az 1) ile gerçek nüsha
    /// kaydı sayısından büyüğü; `SchoolLibraryService.stock` toplamıyla aynı kural.
    static func hesapla(books: [CatalogBook], copies: [BookCopy], loans: [ActiveLoan], now: Date = .now,
                        eksikleriSay: Bool = true) -> HomeKPI {
        let etkin = books.filter { !$0.isWithdrawn }
        let nushaSayilari = Dictionary(copies.map { ($0.bookID, 1) }, uniquingKeysWith: +)
        let nusha = etkin.reduce(0) { $0 + max(max(1, $1.quantity ?? 1), nushaSayilari[$1.id] ?? 0) }
        let bugun = Calendar.current
        return HomeKPI(
            baslik: etkin.count,
            nusha: nusha,
            odunc: loans.count,
            geciken: LoanKindFilter.gecikenKutuphane(loans: loans).count,
            bugunIade: loans.filter { bugun.isDate($0.dueDate, inSameDayAs: now) }.count,
            eksik: eksikleriSay ? etkin.filter { !SchoolLibraryService.missingFields($0).isEmpty }.count : 0
        )
    }
}

/// Panelin yeniden hesaplanmasını tetikleyen ucuz girdiler. Tam içerik karşılaştırması yerine
/// sayı, toplam ve parmak izi kullanılır; değişmediyse pahalı özetler yeniden kurulmaz.
struct HomeInputs: Equatable {
    var kitapSayisi: Int
    var etkinSayisi: Int
    var sonEkleme: Date?
    var miktarToplami: Int
    var oduncSayisi: Int
    var oduncImzasi: Int
    var nushaSayisi: Int
    var gun: Date
    var gorunumSayaci: Int

    init(kitaplar: [CatalogBook], loans: [ActiveLoan], copies: [BookCopy], gorunumSayaci: Int, simdi: Date = .now) {
        kitapSayisi = kitaplar.count
        etkinSayisi = kitaplar.reduce(0) { $0 + ($1.isWithdrawn ? 0 : 1) }
        sonEkleme = kitaplar.first?.addedAt
        miktarToplami = kitaplar.reduce(0) { $0 + ($1.quantity ?? 1) }
        oduncSayisi = loans.count
        var hasher = Hasher()
        for loan in loans { hasher.combine(loan.id); hasher.combine(loan.dueDate) }
        oduncImzasi = hasher.finalize()
        nushaSayisi = copies.count
        gun = Calendar.current.startOfDay(for: simdi)
        self.gorunumSayaci = gorunumSayaci
    }

    /// Görünüm sayacı dışındaki her girdi aynı mı?
    func veriAyni(_ diger: HomeInputs) -> Bool {
        var kopya = diger
        kopya.gorunumSayaci = gorunumSayaci
        return kopya == self
    }
}

/// Ana Sayfa'nın türetilmiş verileri: sayılar ve kapak rafları. Girdi değişmedikçe (ve en çok
/// dakikada bir) yeniden hesaplanmaz; gövde her çizimde binlerce kaydı süzmez.
@MainActor @Observable
final class HomeDashboardModel {
    typealias KategoriRafi = (ad: String, kitaplar: [CatalogBook])

    private(set) var kpi = HomeKPI()
    private(set) var gecikenler: [ActiveLoan] = []
    private(set) var yeniGelenler: [CatalogBook] = []
    private(set) var populer: [CatalogBook] = []
    private(set) var okunmayan: [CatalogBook] = []
    private(set) var kategoriRaflari: [KategoriRafi] = []

    @ObservationIgnored private var sonGirdi: HomeInputs?
    @ObservationIgnored private var sonHesap: Date?
    static let tazelikSuresi: TimeInterval = 60

    func guncelle(girdi: HomeInputs, books: [CatalogBook], copies: [BookCopy], loans: [ActiveLoan], simdi: Date = .now) {
        // Sekme yeniden görününce (sayaç değişir) veri aynıysa ve hesap tazeyse yeniden kurulmaz.
        if let sonGirdi, sonGirdi.veriAyni(girdi), let sonHesap, simdi.timeIntervalSince(sonHesap) < Self.tazelikSuresi { return }
        sonGirdi = girdi; sonHesap = simdi
        let etkin = books.filter { !$0.isWithdrawn }
        kpi = HomeKPI.hesapla(books: books, copies: copies, loans: loans, now: simdi)
        gecikenler = LoanKindFilter.gecikenKutuphane(loans: loans)
        yeniGelenler = Array(etkin.prefix(15))
        let olaylar = LoanHistoryStore.all
        let sozluk = Dictionary(etkin.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        populer = RaporMotoru.enCokOkunanlar(events: olaylar).compactMap { sozluk[$0] }
        okunmayan = Array(RaporMotoru.okunmayanlar(Array(etkin.prefix(3_000)), events: olaylar, loans: loans).prefix(15))
        kategoriRaflari = RaporMotoru.kategoriDagilimi(etkin).prefix(3).map { kategori in
            (ad: kategori.ad,
             kitaplar: Array(etkin.lazy.filter { ($0.category ?? "Kategorisiz") == kategori.ad || ($0.category == nil && kategori.ad == "Kategorisiz") }.prefix(15)))
        }
    }
}

// MARK: - Arama sekmesi

/// Sekme çubuğundaki arama: her yerden hızlı kitap araması (son aramalar + sonuçlar).
struct AramaSekmesi: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @Environment(\.modelContext) private var modelContext
    @State private var metin = ""
    @State private var etkin = ""
    /// Terim bir demirbaşa uyuyorsa o kitap(lar) sonuçların en üstünde gösterilir.
    @State private var demirbasKitaplari: [CatalogBook] = []
    @State private var gecmis = AramaGecmisi.hepsi()
    @Namespace private var alan

    var body: some View {
        NavigationStack {
            Group {
                if etkin.isEmpty {
                    List {
                        if !gecmis.isEmpty {
                            Section("Son aramalar") {
                                ForEach(gecmis, id: \.self) { terim in
                                    Button {
                                        metin = terim
                                    } label: {
                                        Label(terim, systemImage: "clock.arrow.circlepath")
                                    }
                                    .foregroundStyle(Color.primary)
                                }
                            }
                        }
                        Section {
                            Label("Ad, yazar, yayınevi, kategori, etiket, ISBN ya da demirbaş yazın; sonuçta yer ve durum görünür", systemImage: "magnifyingglass")
                                .foregroundStyle(KitapTema.ikincilMetin)
                        }
                    }
                } else {
                    AramaSonuclari(arama: etkin, demirbasKitaplari: demirbasKitaplari, alan: alan)
                }
            }
            .navigationTitle("Kitap nerede?")
            .toolbar {
                if isPresented {
                    ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } }
                }
            }
            .searchable(text: $metin, placement: .navigationBarDrawer(displayMode: .always), prompt: "Kitap ara")
            .onSubmit(of: .search) {
                AramaGecmisi.ekle(metin)
                gecmis = AramaGecmisi.hepsi()
            }
            .task(id: metin) {
                // İptal edilen (yeni tuşla geçersizleşen) bekleme sorguyu tetiklemez
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                let terim = metin.trimmingCharacters(in: .whitespacesAndNewlines)
                // Sonuçlarla aynı anda güncellenir: demirbaş satırı boş durumun ardından belirmez.
                demirbasKitaplari = DemirbasArama.kitaplar(terim, context: modelContext)
                etkin = terim
            }
            .navigationDestination(for: UUID.self) { id in
                KitapDetaySayfasi(kitapID: id)
                    .zoomHedefi(id, alan)
                    // Sonuca dokunarak açılan arama da geçmişe girer (yalnız klavyede Ara değil).
                    .onAppear {
                        AramaGecmisi.ekle(etkin)
                        gecmis = AramaGecmisi.hepsi()
                    }
            }
        }
    }
}

private struct AramaSonuclari: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var sonuclar: [CatalogBook]
    /// Durum rozeti ayrıntı ve Kitaplar listesiyle aynı stok kuralından gelir (nüsha durumu, rezervasyon,
    /// kayıtlı nüsha sayısı); tablolar birer kez okunur, satır başına sorgu açılmaz.
    @Query private var loans: [ActiveLoan]
    @Query private var copies: [BookCopy]
    @Query private var reservations: [Reservation]
    @Environment(\.dynamicTypeSize) private var yaziBoyutu
    let alan: Namespace.ID
    let arama: String
    let demirbasKitaplari: [CatalogBook]

    init(arama: String, demirbasKitaplari: [CatalogBook], alan: Namespace.ID) {
        self.alan = alan
        self.arama = arama
        self.demirbasKitaplari = demirbasKitaplari
        var descriptor = KitapAramaKosulu.predicate(for: arama).map { FetchDescriptor<CatalogBook>(predicate: $0, sortBy: [SortDescriptor(\.title)]) }
            ?? FetchDescriptor<CatalogBook>(sortBy: [SortDescriptor(\.title)])
        descriptor.fetchLimit = 201
        _sonuclar = Query(descriptor)
    }

    var body: some View {
        if sonuclar.isEmpty && demirbasKitaplari.isEmpty {
            BosDurum(baslik: "Sonuç yok", aciklama: "“\(arama)” katalogda bulunamadı. Kitaplar’da filtrelerle arayın ya da kitabı ekleyin.",
                     ikon: "magnifyingglass", eylemler: [
                        BosDurumEylemi(ad: "Kitaplar’da ara", ikon: "books.vertical", kimlik: "search.empty.books") { kitaplardaAra() },
                        BosDurumEylemi(ad: "Kataloğa ekle", ikon: "plus.circle", kimlik: "search.empty.add") {
                            DerinBaglanti.shared.hedefSekme = .katalog
                            dismiss()
                        }
                     ])
        } else {
            let gosterilen = Array(sonuclar.prefix(200))
            let demirbasIDleri = Set(demirbasKitaplari.map(\.id))
            let rozetler = KitapDurumu.rozetler(demirbasKitaplari + gosterilen.filter { !demirbasIDleri.contains($0.id) },
                                                loans: loans, copies: copies, reservations: reservations)
            List {
                if !demirbasKitaplari.isEmpty {
                    Section {
                        ForEach(demirbasKitaplari) { satir($0, durum: rozetler[$0.id]) }
                    } header: {
                        Text("Demirbaş \(arama)")
                    } footer: {
                        if demirbasKitaplari.count > 1 {
                            Text("Bu demirbaş \(demirbasKitaplari.count) kitapta kayıtlı. Demirbaş defterinden düzeltin.")
                        }
                    }
                }
                if sonuclar.count > 200 {
                    Section {
                        Button("İlk 200 sonuç gösteriliyor. Tümünü Kitaplar’da ara") { kitaplardaAra() }
                    }
                }
                ForEach(gosterilen.filter { !demirbasIDleri.contains($0.id) }) { kitap in
                    satir(kitap, durum: rozetler[kitap.id])
                }
            }
        }
    }

    private func kitaplardaAra() {
        KutuphaneRotasi.shared.kitapAramasi = arama
        DerinBaglanti.shared.hedefSekme = .kitaplar
        dismiss()
    }

    /// Sonuç satırı: ayrıntıyı açmadan yer ve Rafta/Ödünçte durumu okunur.
    private func satir(_ kitap: CatalogBook, durum hazir: (metin: String, renk: Color, ikon: String)?) -> some View {
        let durum = hazir ?? KitapDurumu.rozet(kitap, stok: LibraryStock(total: max(1, kitap.quantity ?? 1)))
        return NavigationLink(value: kitap.id) {
            HStack(spacing: 12) {
                // Büyük yazıda küçük kapak yer ve durum metnine yer bırakır (sözcük ortadan bölünmesin).
                if !yaziBoyutu.isAccessibilitySize {
                    CoverThumb(data: kitap.coverData, size: 44)
                        .zoomKaynagi(kitap.id, alan)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(kitap.title).font(.subheadline.weight(.semibold))
                    Text(kitap.author).font(.caption).foregroundStyle(KitapTema.ikincilMetin)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            Rozet(metin: durum.metin, renk: durum.renk, ikon: durum.ikon)
                            Rozet(metin: kitap.konumMetni ?? CatalogBook.yerAtanmamis, renk: KitapTema.amazon, ikon: "cabinet.fill")
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Rozet(metin: durum.metin, renk: durum.renk, ikon: durum.ikon)
                            Rozet(metin: kitap.konumMetni ?? CatalogBook.yerAtanmamis, renk: KitapTema.amazon, ikon: "cabinet.fill", satirSiniri: nil)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("search.result")
    }
}
