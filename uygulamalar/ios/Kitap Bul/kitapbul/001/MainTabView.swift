import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

/// Uygulamanın sekmeli kabuğu: iPhone'da 5 sekme; geniş ekranda Asistan, Yapay zekâ araçları ve Ayarlar da
/// sekme olur. iPhone'da alt sekme çubuğu, iPad/Mac'te kenar çubuğuna
/// dönüşür (`sidebarAdaptable`). Her sekmenin kendi rengi ve erişilebilirlik etiketi var.
struct MainTabView: View {
    enum Sekme: String, CaseIterable {
        case anaSayfa, katalog, kitaplar, odunc, yonetim, asistan, araclar, ayarlar

        /// Kenardan kaydırmada gezilen sıra (sekme çubuğundaki sırayla; geniş ekrana özgü sekmeler hariç)
        static let kaydirmaSirasi: [Sekme] = [.anaSayfa, .kitaplar, .katalog, .odunc, .yonetim]

        /// Bir hedefin nerede açılacağı. Telefonda (compact) Asistan, Yapay zekâ araçları ve Ayarlar
        /// sekme çubuğunda yoktur; sayfa olarak açılır.
        enum Cozum: Equatable {
            case sekme(Sekme)
            case asistanSayfasi, araclarSayfasi, ayarlarSayfasi
        }

        static func coz(_ hedef: Sekme, compact: Bool) -> Cozum {
            guard compact else { return .sekme(hedef) }
            switch hedef {
            case .asistan: return .asistanSayfasi
            case .araclar: return .araclarSayfasi
            case .ayarlar: return .ayarlarSayfasi
            case .anaSayfa, .katalog, .kitaplar, .odunc, .yonetim: return .sekme(hedef)
            }
        }
    }

    /// Pencere başına saklanır: iPad'de iki pencere farklı sekmede durabilir.
    @SceneStorage("selectedTab") private var selectedRaw = Sekme.anaSayfa.rawValue
    @Environment(\.horizontalSizeClass) private var boyutSinifi
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(Tasarim.sadeModAnahtari) private var sadeMod = false
    @AppStorage(Tasarim.efektAnahtari) private var effects = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    private let derinBaglanti = DerinBaglanti.shared
    @AppStorage(Yenilikler.anahtar) private var lastSeenWhatsNew = ""
    @AppStorage("onboardingShown") private var onboardingShown = false
    @State private var isShowingWhatsNew = false
    @State private var isShowingOnboarding = false
    @State private var assistantOpen = false
    @State private var aiToolsOpen = false
    @State private var ayarlarOpen = false
    @State private var catalogLease: ActiveCatalogLease?
    /// Günlük arşiv, ilk sekme etkileşiminden kısa süre sonra başlar (sabit bekleme yok).
    @State private var arsivZamanlayici = AcilisArsivZamanlayici()

    /// A mounted root never adopts a later catalog for already-started work.
    private func currentCatalogLease() -> ActiveCatalogLease? {
        do {
            if catalogLease == nil { catalogLease = try ActiveCatalogLease.captureCurrent(context: modelContext) }
            guard let lease = catalogLease else { return nil }
            try lease.requireCurrent(context: modelContext)
            return lease
        } catch { return nil }
    }

    private var selection: Binding<Sekme> {
        Binding(
            get: { Sekme(rawValue: selectedRaw) ?? .anaSayfa },
            set: { selectedRaw = $0.rawValue }
        )
    }

    var body: some View {
        TabView(selection: selection) {
            Tab("Ana Sayfa", systemImage: "house.fill", value: .anaSayfa) {
                AnaSayfa()
                    .sekmeninOkunurIcerikAlani()
            }
            .accessibilityHint("Özet, hızlı işlemler, kitap rafları")
            .accessibilityIdentifier("tab.anaSayfa")

            Tab("Kitaplar", systemImage: "books.vertical.fill", value: .kitaplar) {
                KitaplarSekmesi()
                    .sekmeninOkunurIcerikAlani()
            }
            .accessibilityHint("Kapak ızgarası, kategoriler, seriler ve ayrıntılar")
            .accessibilityIdentifier("tab.kitaplar")

            Tab("Ekle", systemImage: "plus.viewfinder", value: .katalog) {
                ContentView()
                    .sekmeninOkunurIcerikAlani()
            }
            .accessibilityHint("Barkod, kapak, ses ya da dosyadan kitap ekleme")
            .accessibilityIdentifier("tab.katalog")

            Tab("Ödünç", systemImage: "person.badge.clock.fill", value: .odunc) {
                OduncSekmesi()
                    .sekmeninOkunurIcerikAlani()
            }
            .accessibilityHint("Etkin ödünçler, gecikenler, sıra; barkodla ödünç verme ve iade alma")
            .accessibilityIdentifier("tab.odunc")

            Tab("Yönetim", systemImage: "square.grid.2x2.fill", value: .yonetim) {
                YonetimSayfasi()
                    .sekmeninOkunurIcerikAlani()
            }
            .accessibilityHint("Öğrenciler, raporlar, sayım, katalog bakımı, yedek ve ayarlar")
            .accessibilityIdentifier("tab.yonetim")

            Tab("Asistan", systemImage: "waveform.and.mic", value: .asistan) {
                AIAssistantView()
            }
            .hidden(boyutSinifi == .compact)
            .accessibilityHint("Sesli yapay zekâ asistanı")
            .accessibilityIdentifier("tab.asistan")

            // iPhone'da Yapay zekâ araçları Ana Sayfa, Yönetim ve Asistan'dan açılır (sekme çubuğu 5 sekmede kalsın)
            Tab("Yapay zekâ araçları", systemImage: "sparkles", value: .araclar) {
                AIToolsView()
            }
            .hidden(boyutSinifi == .compact)
            .accessibilityHint("Gemini ile tarama, tamamlama, öneri ve kitap kartı")
            .accessibilityIdentifier("tab.araclar")

            // iPhone'da Ayarlar Ana Sayfa'daki dişli düğmesindedir; iPad kenar çubuğunda sekme olarak durur
            Tab("Ayarlar", systemImage: "gearshape.fill", value: .ayarlar) {
                YoneticiKilidi(baslik: "Ayarlar", sadeModAnahtari: true) { SettingsView() }
            }
            .hidden(boyutSinifi == .compact)
            .accessibilityIdentifier("tab.ayarlar")

        }
        .tabViewStyle(.sidebarAdaptable)
        // Günlük görevlerin beş sekmesi kaydırırken de erişilebilir kalır.
        .tabBarMinimizeBehavior(.never)
        .environment(\.sekmeDegistir) { yon in
            let sira = Sekme.kaydirmaSirasi
            guard let i = sira.firstIndex(of: selection.wrappedValue) else { return }
            let yeni = i + yon
            guard sira.indices.contains(yeni) else { return }
            withAnimation(reduceMotion || !effects ? nil : .snappy) { selection.wrappedValue = sira[yeni] }
        }
        // Sade mod: küçük sınıflar için yazılar en az "çok büyük" boyutta
        .dynamicTypeSize(sadeMod ? .xxLarge ... .accessibility5 : .xSmall ... .accessibility5)
        .onChange(of: derinBaglanti.hedefSekme, initial: true) { _, hedef in
            guard let hedef else { return }
            switch Sekme.coz(hedef, compact: boyutSinifi == .compact) {
            case .sekme(let sekme): selection.wrappedValue = sekme
            case .asistanSayfasi: assistantOpen = true
            case .araclarSayfasi: aiToolsOpen = true
            case .ayarlarSayfasi: ayarlarOpen = true
            }
            derinBaglanti.hedefSekme = nil
        }
        .onChange(of: boyutSinifi) { _, sinif in
            // iPhone'a geçerken gizli Ayarlar sekmesinde kalınmasın
            if sinif == .compact && [.ayarlar, .araclar, .asistan].contains(Sekme(rawValue: selectedRaw) ?? .anaSayfa) { selection.wrappedValue = .anaSayfa }
        }
        // Sekme vurgusu yalnız sekme çubuğu ve sekme içerikleri içindir; aşağıdaki sayfalar (sheet)
        // sekmeye göre değişmeyen sabit ana rengi alır.
        .tint(tabTint)
        // Veri paylaşım onayı yalnızca yapay zekâ sekmelerine geçildiğinde, tek yerden sorulur
        // Açılışta: eski kayıtlara arama anahtarı (bir kez), bekleyen AI zenginleştirmeleri
        .task {
            guard let lease = currentCatalogLease() else { return }
            let context = modelContext
            let check: @MainActor @Sendable () throws -> Void = { @MainActor @Sendable in
                try lease.requireCurrent(context: context)
            }
            // Birim/UI testlerinde ve salt okunur UI testinde veriye dokunan açılış işleri yapılmaz.
            if Self.testOrtami {
                await CatalogSearchIndex.backfillIfNeeded(context: modelContext, requireCurrent: check)
                return
            }
            // Güncellemeden sonra bir kez "Yenilikler"; yeni kurulumda tanıtım yeterli.
            // Tanıtım burada, açılan ilk ekranın (Ana Sayfa) üstünde açılır; Ekle sekmesini ya da
            // Yönetim'deki bir aracı beklemez.
            switch AcilisPlani.yap(onboardingShown: onboardingShown, sonGorulen: lastSeenWhatsNew, surum: Yenilikler.surum) {
            case .yenilikler:
                isShowingWhatsNew = true
            case .tanitim:
                lastSeenWhatsNew = Yenilikler.surum
                isShowingOnboarding = true
            case .hic:
                break
            }
            // Veri güvenliği: bütünlük denetimi, süresi dolan çöpler, günlük tam arşiv
            IntegrityCheck.run(context: modelContext)
            TrashStore.purgeExpired()
            LoanReminders.gecikenOzetiniYenile(context: modelContext)
            await CatalogSearchIndex.backfillIfNeeded(context: modelContext, requireCurrent: check)
            do { try check() } catch { return }
            await EnrichmentQueue.process(context: modelContext, requireCurrent: check)
            // Günlük arşiv açılışı yavaşlatmasın: ilk sekme etkileşiminden 5 sn sonra (etkileşim yoksa
            // üst sınırda) başlar; kısa oturumda ise uygulama etkin olmaktan çıkarken zaten alınır.
            do {
                while !arsivZamanlayici.vadesiGeldi() {
                    try await Task.sleep(for: .seconds(1))
                }
                try check()
            } catch { return }
            await ArkaPlanArsivi.calistir(kontrol: check)
        }
        // İlk sekme etkileşimi arşiv zamanlayıcısını başlatır
        .onChange(of: selectedRaw) { _, _ in arsivZamanlayici.etkilesimOldu() }
        // Uygulamaya dönüldüğünde (internet gelmiş olabilir) kuyruk yeniden denenir
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { YetkiDurumu.shared.arkaPlanaGecti() }
            if phase == .active { YetkiDurumu.shared.onePlanaDondu() }
            guard let lease = currentCatalogLease() else { return }
            let context = modelContext
            let check: @MainActor @Sendable () throws -> Void = { @MainActor @Sendable in
                try lease.requireCurrent(context: context)
            }
            if phase == .active && !Self.testOrtami {
                Task { @MainActor in
                    do { try check() } catch { return }
                    // Gün değişmiş olabilir: gecikenler özeti bir hafta ileriye yeniden kurulur
                    LoanReminders.gecikenOzetiniYenile(context: context)
                    await EnrichmentQueue.process(context: context, requireCurrent: check)
                }
            }
            // Etkin olmaktan çıkarken (kısa oturum ya da arka plana geçiş) gün değişmişse arşiv alınır.
            // iOS arka planda yalnız kısa süre tanır: iş beginBackgroundTask ile sarılır, süre dolunca iptal edilir.
            if (phase == .inactive || phase == .background) && !Self.testOrtami {
                ArkaPlanArsivi.baslat(kontrol: check)
            }
        }
        // Root retains cold-launch URLs until the verified catalogue is ready.
        // Initial hedefSekme consumption above also handles a pre-mounted route.
        .sheet(isPresented: $assistantOpen) {
            KapatilabilirSayfa { AIAssistantView() }
                .geminiConsentGate(isRelevant: true)
                .sayfaVurgusu()
        }
        .sheet(isPresented: $aiToolsOpen) {
            KapatilabilirSayfa { AIToolsView() }
                .geminiConsentGate(isRelevant: true)
                .sayfaVurgusu()
        }
        .sheet(isPresented: $ayarlarOpen) {
            YoneticiKilidi(baslik: "Ayarlar", sadeModAnahtari: true) { SettingsView() }
                .sayfaVurgusu()
        }
        .onAppear {
            if boyutSinifi == .compact && [.asistan, .araclar, .ayarlar].contains(selection.wrappedValue) {
                selection.wrappedValue = .anaSayfa
            }
        }
        .sheet(isPresented: $isShowingWhatsNew, onDismiss: { lastSeenWhatsNew = Yenilikler.surum }) {
            YeniliklerSayfasi()
                .sayfaVurgusu()
        }
        // Aşağı çekerek kapatma da tanıtımı görülmüş sayar; her açılışta yeniden çıkmaz.
        .sheet(isPresented: $isShowingOnboarding, onDismiss: { onboardingShown = true }) {
            OnboardingView()
                .sayfaVurgusu()
        }
        .geminiConsentGate(isRelevant: selection.wrappedValue == .asistan || selection.wrappedValue == .araclar)
        .animation(reduceMotion || !effects ? nil : .default, value: selectedRaw)
    }

    /// XCTest ana uygulamayı barındırıcı olarak açtığında ağır açılış işleri atlanır.
    static var testOrtami: Bool { TestEnvironment.suppressesLaunchSideEffects }

    /// Sekmeye göre vurgu rengi — hangi bölümde olduğunuzu renkten de anlarsınız.
    private var tabTint: Color {
        let renk: Color = switch selection.wrappedValue {
        case .anaSayfa: KitapTema.ana
        case .odunc: KitapTema.amazon
        case .katalog: KitapTema.ana
        case .kitaplar: KitapTema.toplu
        case .asistan: KitapTema.amazon
        case .araclar: KitapTema.foto
        case .ayarlar, .yonetim: KitapTema.dosya
        }
        return KitapTema.erisilebilirVurgu(renk, scheme: colorScheme)
    }
}

// MARK: - Açılış arşivi zamanlaması

/// Günlük arşivin ne zaman başlayacağı: ilk sekme etkileşiminden 5 sn sonra. Hiç etkileşim olmazsa
/// açılıştan 90 sn sonra (uygulama açık bırakılıp kullanılmıyorsa da arşiv alınsın). Saf değer tipi.
nonisolated struct AcilisArsivZamanlayici: Equatable, Sendable {
    static let etkilesimdenSonra: TimeInterval = 5
    static let etkilesimsizUstSinir: TimeInterval = 90

    let baslangic: Date
    private(set) var ilkEtkilesim: Date?

    init(baslangic: Date = .now) { self.baslangic = baslangic }

    /// Yalnız ilk etkileşim sayılır.
    mutating func etkilesimOldu(_ an: Date = .now) {
        if ilkEtkilesim == nil { ilkEtkilesim = an }
    }

    var vade: Date {
        if let ilkEtkilesim { return ilkEtkilesim.addingTimeInterval(Self.etkilesimdenSonra) }
        return baslangic.addingTimeInterval(Self.etkilesimsizUstSinir)
    }

    func vadesiGeldi(_ simdi: Date = .now) -> Bool { simdi >= vade }
}

// MARK: - Arka plan arşivi

/// Günlük arşivi çalıştırır. Arka plana geçerken iOS yalnız kısa süre tanır: iş `beginBackgroundTask` ile
/// sarılır; süre dolarsa görev iptal edilir ve yazıcı yarım dosyayı bırakmadan çıkar (`AutoArchive.run`).
@MainActor
enum ArkaPlanArsivi {
    private static var calisan: Task<Void, Never>?

    /// Ön plandaki çağrı: iptal edilebilir, arka plan görevi sarmaz.
    static func calistir(kontrol: @MainActor @Sendable () throws -> Void) async {
        do { try kontrol() } catch { return }
        sonucuGunlukle(await AutoArchive.run(cancellable: true))
    }

    /// Etkin olmaktan çıkarken çağrılır; zaten çalışan bir iş varsa ikincisi başlamaz.
    static func baslat(kontrol: @escaping @MainActor @Sendable () throws -> Void) {
        guard calisan == nil else { return }
#if os(iOS)
        let kutu = ArkaPlanIsi()
        kutu.kimlik = UIApplication.shared.beginBackgroundTask(withName: "gunluk-arsiv") {
            kutu.gorev?.cancel()
            // Yazıcı iptale yanıt verene dek kısa pay; sonra görev mutlaka bitirilir.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                kutu.bitir()
            }
        }
        calisan = Task { @MainActor in
            defer { calisan = nil; kutu.bitir() }
            await calistir(kontrol: kontrol)
        }
        kutu.gorev = calisan
#else
        calisan = Task { @MainActor in
            defer { calisan = nil }
            await calistir(kontrol: kontrol)
        }
#endif
    }

    private static func sonucuGunlukle(_ sonuc: AutoArchive.Outcome) {
        if case .basarisiz(let neden) = sonuc { AppLog.write("Günlük arşiv alınamadı: \(neden)") }
    }

#if os(iOS)
    @MainActor
    private final class ArkaPlanIsi {
        var kimlik = UIBackgroundTaskIdentifier.invalid
        var gorev: Task<Void, Never>?
        func bitir() {
            guard kimlik != .invalid else { return }
            UIApplication.shared.endBackgroundTask(kimlik)
            kimlik = .invalid
        }
    }
#endif
}
