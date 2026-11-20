import CoreSpotlight
import SwiftData
import SwiftUI
import UserNotifications

@main
struct IkraApp: App {
    @State private var app: AppState
    private let notifications = NotificationRouter()

    init() {
        // Gezinme çubuğu görünümü ilk ekran kurulmadan uygulanmalı; sonradan değişince açık çubuklar güncellenmez.
        QSModelPlan.installAutoIfNeeded()
        VisionRoot.applyAppearance()
        // Depolar açılmadan önce: eski Ders Video uygulamasının ortak klasöre bırakılan kayıtları (soru arşivi, anlatımlar,
        // konu videoları, tekrar kartları, yanlışlar) buraya alınır.
        let imported = OkuImport.runIfNeeded()
        // Gömülü Claude anahtarı Keychain'e alınır; Release paketine anahtar konmaz (Ayarlar'dan da girilebilir).
        ClaudeKey.seedFromBundleIfNeeded()
        let state = AppState()
        if let imported, imported > 0 { state.notice = "Ders Video'daki \(imported) sorun, anlatımların, konu videoların, tekrar kartların ve yanlışların buraya taşındı." }
        _app = State(initialValue: state)
        UNUserNotificationCenter.current().delegate = notifications
        // Soru Çöz: kesintisiz üretim (madde 13) ve toplu video kuyruğu arka plan görevleri; açılışta kaydolmalı.
        QSContinuedWork.register()
        QSBatchBackground.register()
        // Arka plan görevi ilk sahneden önce kaydolmalı.
        ChannelRefresh.register()
        ChannelRefresh.schedule()
        NotificationActions.registerCategories()   // P3
        // Koçluk kaldırıldı: daha önce kurulmuş haftalık koç bildirimi iptal edilir.
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["coach-weekly"])
        ListeningHooks.install()                   // P5
        PodcastLearning.install()                  // P6
        LibraryHooks.install()                     // P7
        MacBackup.install()                        // P7
        QSDeviceSyncCenter.shared.install()        // İsteğe bağlı cihaz sürümü önizlemesi; yayımlama kullanıcı kararıdır.
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .debugNarrowScreen()
                .environment(app)
                .environment(app.player)
                .environment(app.generator)
                .tint(.accentColor)
                // Görme kolaylığı (17 Eki 2026): yazı boyutu kademesi, kalın yazı, mavi–sarı bileşenler.
                .modifier(VisionRoot())
                .environment(\.defaultMinListRowHeight, 52)
                .onAppear { notifications.app = app }
                .onOpenURL { url in
                    // "İkra’da Aç": sistem dosyayı uygulamanın Inbox klasörüne kopyalar; kocum:// bağlantıları DeepLink'e.
                    if url.isFileURL { app.incomingFiles.append(url) } else { DeepLink.handle(url) }
                }
                .onContinueUserActivity(CSSearchableItemActionType) { SpotlightIndex.handle($0) }
        }
        .modelContainer(AppDataStore.container)
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if app.needsToken {
                ServerSetupView(isInitialSetup: true)
            } else {
                MainTabs().podcastLearningOverlay()
                    .task {
                        // Yarım kalmış sınıf kaydı geçici sesleri (7 günden eski) temizlenir.
                        Task.detached(priority: .utility) { UploadStash.prune() }
                        #if DEBUG
                        // Telefondaki CLI Proxy doğrulaması (Mac'ten: devicectl ... launch com.mehmetderin.derspodcast --cliproxy-sinama)
                        if CommandLine.arguments.contains("--cliproxy-sinama") { Task.detached { await PhoneProxy.selfTest() } }
                        if CommandLine.arguments.contains("--tutor-sinama") { Task { await TutorDiagnostics.run() } }
                        LibraryDemo.seedIfRequested(context: modelContext)
                        CoursesDemo.seedIfRequested(context: modelContext)
                        #endif
                        // Uygulama kapalıyken biten odak oturumu, Çalış sekmesi açılmadan da kaydedilsin.
                        FocusTimer.reconcileSaved(context: modelContext)
                        await app.refreshStatus()
                        await checkChannels()
                    }
                    .onChange(of: scenePhase) { _, phase in
                        switch phase {
                        case .active:
                            FocusTimer.reconcileSaved(context: modelContext)
                            QSBatchCenter.shared.enterForeground()
                            // Otomasyon planı varsa Soru Çöz ekranı açılmadan da sürer.
                            if QSAutomationCenter.shared.working { QSAutomationCenter.shared.attach(QuestionStore.shared) }
                            Task { await app.refreshStatusIfStale(); await checkChannels() }
                        case .background:
                            ChannelRefresh.schedule()
                            QSBatchCenter.shared.scheduleBackgroundIfNeeded()
                        default: break
                        }
                    }
                    // Sunucu hatası sürdükçe (yalnız ön planda) aralığı açılan yeniden deneme: afiş kendiliğinden kalkar.
                    .task(id: "\(app.serverError != nil)|\(scenePhase == .active)") {
                        guard app.serverError != nil, scenePhase == .active else { return }
                        var attempt = 0
                        while !Task.isCancelled, app.serverError != nil {
                            try? await Task.sleep(for: .seconds(AppState.statusRetryDelay(attempt: attempt)))
                            guard !Task.isCancelled else { return }
                            await app.refreshStatus(keepLastKnown: true)
                            attempt += 1
                        }
                        // Başarıda kimlik değişip bu görev iptal edilir; kanal denetimi ayrı görevde sürsün.
                        if app.serverError == nil { Task { await checkChannels() } }
                    }
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: app.needsToken)
        .alert("Kayıtların taşındı", isPresented: Binding(get: { app.notice != nil }, set: { if !$0 { app.notice = nil } })) {
            Button("Tamam") { app.notice = nil }
        } message: { Text(app.notice ?? "") }
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
    }

    /// Takip edilen kanallarda yeni video var mı bak (en fazla 30 dakikada bir); otomatik işlenecekler kuyrukta başlar.
    private func checkChannels() async {
        guard !app.needsToken, app.server != nil else { return }
        await ChannelWatcher.checkAll(context: modelContext)
        app.importQueue.kick(context: modelContext)
    }
}

/// Bildirime dokununca ilgili ekranı aç (ör. günlük tekrar).
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    weak var app: AppState?

    // Tamamlama işleyicili sürümler: async sürümde tamamlama ana iş parçacığı dışında bildiriliyor ve UIKit
    // (durum geri yükleme anlık görüntüsü) uygulamayı kapatıyordu. Tamamlama ana iş parçacığında çağrılır.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let info = response.notification.request.content.userInfo
        let route = info["route"] as? String
        let episodeID = (info["episodeID"] as? String).flatMap(UUID.init(uuidString:))
        let action = response.actionIdentifier
        Task { @MainActor in
            // Önce bildirim eylemleri (P3); işlenmezse eski rota yolu. Soğuk açılışta görünüm henüz atamamış olabilir: genel örneği kullan.
            let handled = await NotificationActions.handle(actionIdentifier: action, episodeID: episodeID)
            if !handled { (self.app ?? AppState.current)?.pendingRoute = route }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        DispatchQueue.main.async { completionHandler([.banner, .sound]) }
    }
}
