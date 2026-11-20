import SwiftUI
import SwiftData
import Combine

@main struct MyApp: App {
    @State private var container: ModelContainer?
    @State private var storeFailure: String?
    @State private var storeGeneration = UUID()
    @State private var isBootstrapping = true
    @State private var bootstrapStarted = false
    @State private var launchLinks = LibraryLaunchLinkQueue()

    init() {
        // Do not initialize model-dependent views or load archived preferences
        // before interrupted-switch recovery has completed.
        KitapVeritabani.shared = nil
#if DEBUG
        // Hosted unit tests start running after App.init. A later production
        // bootstrap would race their temporary global path overrides. The host
        // gets only an empty in-memory container; it never opens journal/metadata.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil,
           !TestEnvironment.isUITesting {
            do {
                let host = try KitapVeritabani.makeContainer(inMemory: true)
                _container = State(initialValue: host); KitapVeritabani.shared = host
                _isBootstrapping = State(initialValue: false)
                _bootstrapStarted = State(initialValue: true)
            } catch {
                _storeFailure = State(initialValue: error.localizedDescription)
                _isBootstrapping = State(initialValue: false)
                _bootstrapStarted = State(initialValue: true)
            }
        }
#endif
        CrashReportCollector.shared.start()
        // BGTaskScheduler işleyicileri uygulama açılışı bitmeden kaydedilmelidir; bootstrap sonrası geç kalır.
        if !MainTabView.testOrtami { AutoArchive.registerBackgroundTask() }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isBootstrapping {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Katalog güvenle açılıyor…").font(.headline)
                        Text("Yarım kalan bir geçiş varsa veriler doğrulanıp geri alınacak.")
                            .font(.body).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("store.bootstrap.loading")
                } else {
                    LibraryReadyRoot(container: $container, storeFailure: $storeFailure, storeGeneration: $storeGeneration, launchLinks: launchLinks) {
                        Task { @MainActor in await bootstrapStore() }
                    }
                }
            }
            .onOpenURL { launchLinks.enqueue($0) }
            .task { await bootstrapStore() }
        }
    }

    @MainActor
    private func bootstrapStore() async {
        guard !bootstrapStarted else { return }
        bootstrapStarted = true; isBootstrapping = true
        defer { isBootstrapping = false }
        do {
            try Task.checkCancellation()
#if DEBUG
            // UI fixtures must never open real recovery metadata or journal paths.
            let fixture = TestEnvironment.isUITesting
            if !fixture { try await ArchiveSwitchJournal.recoverPendingBeforeStoreOpenAsync() }
#else
            try await ArchiveSwitchJournal.recoverPendingBeforeStoreOpenAsync()
#endif
            try Task.checkCancellation()
            // Read/migrate appearance only after archived preferences are restored.
            let defaults = UserDefaults.standard
            if defaults.object(forKey: "appearanceMode") == nil,
               let legacy = defaults.object(forKey: "followSystemTheme") as? Bool {
                defaults.set(legacy ? "system" : "light", forKey: "appearanceMode")
            }
            // Kap açılışı tek güvenli kapıdan geçer: işaretçi doğrulanır, geçmiş aktarımı ve rezervasyonlar işlenir.
            let store: ModelContainer
#if DEBUG
            if fixture {
                store = try LibraryUITestFixture.makeContainer()
                do { try SchoolLibraryService.flushHistoryOutbox(context: store.mainContext) }
                catch { LibrarySyncStatus.shared.warning = "Ödünç işlemleri depoda korunuyor; geçmiş aktarımı bekliyor: \(error.localizedDescription)" }
                try SchoolLibraryService.migrateLegacyLoans(context: store.mainContext)
                try SchoolLibraryService.refreshReservations(context: store.mainContext)
            } else { store = try StoreRecovery.openVerifiedContainer(sync: false) }
#else
            store = try StoreRecovery.openVerifiedContainer(sync: false)
#endif
            ActiveCatalogGeneration.didActivate()
            KitapVeritabani.shared = store
            // Önceki oturumda yarım kalmış arşiv geçici dosyaları (10 dk'dan eski) temizlenir.
            if !MainTabView.testOrtami {
                AutoArchive.sweepStaleTemporaries(olderThan: 600)
            }
            container = store; storeFailure = nil; storeGeneration = UUID()
        } catch {
            // No MainTab/query/write path is created on validation failure or
            // cancellation. The explicit retry repeats the complete opening gate.
            KitapVeritabani.shared = nil; container = nil
            storeFailure = error is CancellationError
                ? "Güvenli açılış iptal edildi. Yeniden deneyin; kayıtlı depo ve geçiş günlüğü korunuyor."
                : error.localizedDescription
            bootstrapStarted = false
        }
    }
}

/// Created only after startup rollback. AppStorage therefore starts with the
/// restored preferences; both observable status singletons are memory-only.
private struct LibraryReadyRoot: View {
    @Binding var container: ModelContainer?
    @Binding var storeFailure: String?
    @Binding var storeGeneration: UUID
    let launchLinks: LibraryLaunchLinkQueue
    let retryBootstrap: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var syncState = LibrarySyncStatus.shared
    @State private var switchState = LibraryStoreSwitchStatus.shared
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage(TemaRengi.anahtar) private var themeAccent = TemaRengi.indigo.rawValue
    private var tema: TemaDurumu { TemaDurumu.shared }

    var body: some View {
        Group {
            if let container {
                // Kimlik yalnız depo kuşağına bağlı: ana renk değişince ağaç yeniden kurulmaz,
                // açık sayfalar (Ayarlar) yerinde kalır ve renk gözlemle güncellenir.
                MainTabView()
                    .id(storeGeneration.uuidString)
                    .modelContainer(container)
                    .safeAreaInset(edge: .top) {
                        if let warning = syncState.warning {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(warning).font(.footnote).fixedSize(horizontal: false, vertical: true)
                                Button("Geçmiş aktarımını yeniden dene") {
                                    do { try SchoolLibraryService.flushHistoryOutbox(context: container.mainContext) }
                                    catch { syncState.warning = error.localizedDescription }
                                }.frame(minHeight: 44)
                            }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.yellow.opacity(0.12))
                        }
                    }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active && !MainTabView.testOrtami {
                            do { try SchoolLibraryService.refreshReservations(context: container.mainContext) }
                            catch { AppLog.write("Rezervasyon durumları yenilenemedi: \(error.localizedDescription)") }
                            do { try SchoolLibraryService.flushHistoryOutbox(context: container.mainContext) }
                            catch { syncState.warning = "Geçmiş aktarımı bekliyor: \(error.localizedDescription)" }
                        }
                    }
            } else {
                StoreRecoveryView(failure: storeFailure ?? "Kalıcı depo kullanılamıyor.") { restored in
                    ActiveCatalogGeneration.didActivate()
                    KitapVeritabani.shared = restored
                    container = restored; storeFailure = nil; storeGeneration = UUID()
                }
                .safeAreaInset(edge: .top) {
                    Button("Açılışı yeniden dene", action: retryBootstrap).frame(minHeight: 44)
                        .accessibilityIdentifier("store.bootstrap.retry")
                }
            }
        }
        .onChange(of: launchLinks.pendingURL, initial: true) { _, _ in
            if container != nil { launchLinks.dispatchPending() }
        }
        .onChange(of: container != nil) { _, ready in
            if ready { launchLinks.dispatchPending() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryStoreActivated)) { notification in
            MainActor.assertIsolated()
            guard let activation = notification.object as? LibraryStoreActivation else { return }
            container = activation.container; KitapVeritabani.shared = activation.container
            storeFailure = nil; storeGeneration = UUID(); switchState.receipt = activation.receipt
        }
        .sheet(item: $switchState.receipt) { receipt in
            if let container { LibraryStoreSwitchReceiptView(receipt: receipt, context: container.mainContext) }
        }
        .preferredColorScheme(appearanceMode == "light" ? .light : appearanceMode == "dark" ? .dark : nil)
        .environment(\.temaAna, tema.ana)
        .tint(tema.ana)
        .onChange(of: themeAccent, initial: true) { _, _ in tema.yenile() }
    }
}
