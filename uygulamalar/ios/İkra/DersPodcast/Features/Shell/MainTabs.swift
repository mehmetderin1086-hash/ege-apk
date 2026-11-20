import SwiftData
import SwiftUI

/// Ana Sayfa + yedi modül + Ayarlar; eski sekme kimlikleri bildirimler ve bağlantılar için korunur.
struct MainTabs: View {
    /// Çalış sekmesinde açılan bildirim rotaları (diğerleri kütüphaneye gider). "coach" eski bildirimlerden kalmış olabilir.
    static let studyRoutes: Set<String> = ["coach", "study", "focus", "report", "mistakes"]

    @Environment(AppState.self) private var app
    @Environment(PlayerController.self) private var player
    @Environment(\.modelContext) private var context
    @State private var sheet: MainSheet?
    /// Bir kez açılan modüller canlı tutulur; hiç açılmayan modül kurulmaz. Kütüphane açılışta (görünmeden) kurulur:
    /// bildirim rotaları, gelen dosyalar ve geri yükleme önerisi orada işlenir (eski sekme düzeninde de açılış sekmesiydi).
    @State private var visited: Set<AppState.MainTab> = [.library]
    /// Alt menü açık mı (kullanıcının son tercihi hatırlanır); klavye açıkken menü gizlenir.
    @AppStorage("ui.bottomMenuOpen") private var menuOpen = false
    @State private var keyboardShown = false

    /// Modülden bağımsız açılan ekranlar: kanal bildirimi, Kısayollar'dan gelen bağlantı.
    enum MainSheet: Identifiable {
        case channels, videos
        /// Bağlantılar `AppState.pendingImportLinks`'te birikir; açık içe aktarma ekranı okuyup boşaltır (sheet kimliği sabit).
        case importLinks

        var id: String {
            switch self {
            case .channels: "channels"
            case .videos: "videos"
            case .importLinks: "importLinks"
            }
        }
    }

    /// Kütüphane dışındaki modüllerde de çalan bölüm görünür; dokununca kütüphanede açılır.
    @ViewBuilder private var miniPlayer: some View {
        // #41: brifing (bölüm dışı kuyruk sesi) çalarken de görünür; dokununca yalnız bölüm açılır.
        if player.isActive {
            MiniPlayer { if let id = player.episode?.id { app.selectedTab = .library; app.pendingOpenEpisode = id } }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
        }
    }

    @ViewBuilder private var batchBar: some View {
        let center = QSBatchCenter.shared
        if center.working, !center.paused {
            Button { app.selectedTab = .questions; app.batchRequested += 1 } label: {
                HStack(spacing: 10) {
                    ProgressView(value: center.progress).frame(width: 64).tint(Theme.yellow)
                    Text("Toplu video · " + center.summary).font(.subheadline.weight(.bold)).lineLimit(1)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 9).frame(maxWidth: .infinity)
                .background(Theme.navy)
            }.buttonStyle(.plain).accessibilityLabel("Toplu video kuyruğu: " + center.summary)
        }
    }

    /// Bir modülün ekranı. Kütüphane, Soru Çöz, Sınav Oku ve Görseller oynatıcıyı kendileri gösterir (önceki sekme düzeniyle aynı).
    @ViewBuilder private func screen(_ tab: AppState.MainTab) -> some View {
        switch tab {
        case .home: HomeView().safeAreaInset(edge: .bottom) { miniPlayer }
        case .library: LibraryView()
        case .questions: QuestionHub()
        case .topics:
            NavigationStack { TopicVideoListView().scrollContentBackground(.hidden).background(Theme.canvas) }
                .safeAreaInset(edge: .bottom) { miniPlayer }
        case .study: StudyHub().safeAreaInset(edge: .bottom) { miniPlayer }
        case .courses: CoursesView().safeAreaInset(edge: .bottom) { miniPlayer }
        // Sınav Oku (16 Eki 2026): el yazısı sınav kâğıtlarını cevap anahtarına göre okur ve puanlar.
        case .exams: ExamHub()
        // Görsel kütüphane (16 Eki 2026): kitaplardan kesilen, yüklenen ve videolarda üretilen resimler; ders ders, konu konu.
        case .visuals: VisualLibraryView()
        case .settings: SettingsView(showsDone: false)
        }
    }

    var body: some View {
        // Sistem TabView'ı yerine kendi kabımız (17 Eki 2026): iPhone'da 5'ten fazla sekme "Diğer" sarmalayıcısına düşüp
        // çift gezinme çubuğu açıyordu. Açılan modüller canlı kalır (gezinme yığını ve kaydırma korunur); görünmeyen
        // modül dokunuşa ve VoiceOver'a kapalıdır, `isModuleActive` ile yoklama gibi işlerini durdurur.
        ZStack {
            ForEach(AppState.MainTab.allCases, id: \.self) { tab in
                if visited.contains(tab) {
                    let active = app.selectedTab == tab
                    screen(tab)
                        .environment(\.isModuleActive, active)
                        .opacity(active ? 1 : 0)
                        .allowsHitTesting(active)
                        .accessibilityHidden(!active)
                        .zIndex(active ? 1 : 0)
                }
            }
        }
        // Süren toplu video kuyruğu her modülde görünür; dokununca Soru Çöz'de kuyruk açılır.
        .safeAreaInset(edge: .top, spacing: 0) { batchBar }
        // Açılır kapanır alt menü (17 Eki 2026): kapalıyken ince bir tutamak, açıkken bütün modüller büyük düğmelerle.
        // Güvenli alan olarak eklenir: içerik menünün altına girmez, üst üste binme olmaz.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardShown {
                BottomMenu(open: $menuOpen, selected: app.selectedTab) { app.selectedTab = $0 }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardShown = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardShown = false }
        .onChange(of: app.selectedTab, initial: true) { _, next in
            visited.insert(next)
            // Gizlenen modüldeki metin alanı ilk yanıtlayıcı kalıp klavyeyi açık tutmasın.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .onChange(of: app.settingsRoute) { _, route in if route != nil { app.selectedTab = .settings } }
        // Bölüm açma isteği gelince kütüphaneye geç (oradaki NavigationStack bölümü iter).
        .onChange(of: app.pendingOpenEpisode, initial: true) { _, id in
            // Seri otomatik ilerlemesinde oynatıcı zaten o bölümü çalıyor: kullanıcıyı bulunduğu modülden koparma.
            guard let id, player.episode?.id != id || app.selectedTab == .library else { return }
            app.selectedTab = .library
        }
        .onChange(of: app.pendingRoute, initial: true) { _, route in
            guard let route else { return }
            // Kanal bildirimi ve hazır ders bildirimi modül değiştirmez; ilgili ekran açılır.
            if route == "channels" || route == "videos" {
                app.pendingRoute = nil
                sheet = route == "channels" ? .channels : .videos
                return
            }
            app.selectedTab = MainTabs.studyRoutes.contains(route) ? .study : .library
        }
        .onChange(of: app.pendingImportLinks, initial: true) { _, text in
            guard let text, !text.isEmpty else { return }
            // Ekran zaten açıksa yeni bağlantıyı o okur (kütüphane/içe aktarma ekranı `pendingImportLinks`'i izler).
            if case .importLinks = sheet { return }
            sheet = .importLinks
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .channels: FollowedChannelsView()
            case .videos: VideoLibraryView()
            case .importLinks: VideoLibraryView(openImport: true)
            }
        }
        .onChange(of: app.incomingFiles.count, initial: true) { _, n in if n > 0 { app.selectedTab = .library } }
        // Sunucu ön plandayken bağlanınca bekleyen üretim isteği Kütüphane sekmesinin açılmasını beklemesin.
        // Kütüphane açıksa oradaki dürtmeyle çakışır; kuyruk işleyicisi yeniden girişe dayanıklıdır (ikinci çağrı bir tur daha döndürür).
        .onChange(of: app.server != nil) { _, connected in
            if connected { app.generator.continueQueue(context: context) }
        }
        .task {
            #if DEBUG
            let target = DebugArg.value("openTab").flatMap { AppState.MainTab(rawValue: $0) }
            if FollowDemo.isRequested {
                // Demo kütüphane sekmesinde tohumlanır; istenen sekmeye oynatma başladıktan sonra geç.
                app.selectedTab = .library
                guard let target else { return }
                try? await Task.sleep(for: .seconds(5))
                app.selectedTab = target
            } else if let target {
                app.selectedTab = target
            }
            #endif
        }
    }
}

/// Açılır kapanır alt menü. Kapalı: tam genişlikte tutamak ("Menü" ve açık modülün adı). Açık: Ana Sayfa, yedi modül ve
/// Ayarlar 3 sütunlu büyük düğmeler; seçili olan sarı çerçeveyle ve kalın yazıyla belirtilir. Seçim yapınca menü kapanır.
struct BottomMenu: View {
    /// Kapalı menünün yüksekliği (üst pay 8 + tutamak 50 + alt pay 4): tam ekran asistanın giriş çubuğu bunun üstünde kalır.
    static let closedHeight: CGFloat = 62
    @Binding var open: Bool
    let selected: AppState.MainTab
    let select: (AppState.MainTab) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var items: [AppState.MainTab] { [.home] + AppState.MainTab.modules + [.settings] }

    private func toggle() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { open.toggle() }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Image(systemName: "square.grid.3x3.fill").font(.headline.weight(.bold)).accessibilityHidden(true)
                    Text(open ? "Menüyü kapat" : "Menü").font(.headline.weight(.heavy))
                    if !open {
                        Text("· " + selected.title).font(.headline.weight(.semibold)).foregroundStyle(Theme.navy.opacity(0.8))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: open ? "chevron.down" : "chevron.up").font(.headline.weight(.bold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Theme.navy)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Theme.warmGradient, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .accessibilityLabel(open ? "Menüyü kapat" : "Menüyü aç, şu an " + selected.title)

            if open {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 2 : 3)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(items, id: \.self) { tab in
                        let isSelected = tab == selected
                        Button {
                            select(tab)
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { open = false }
                        } label: {
                            VStack(spacing: 6) {
                                ModuleIconTile(tab: tab, size: 46)
                                Text(tab.title).font(.subheadline.weight(isSelected ? .heavy : .semibold))
                                    .foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity, minHeight: 86)
                            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(isSelected ? Theme.amber : Theme.border, lineWidth: isSelected ? 3 : 1)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(PressableCardStyle(reduceMotion: reduceMotion))
                        .accessibilityLabel(tab.title)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 6)
        .background(Theme.card)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border.opacity(2.5)).frame(height: 1.5) }
        .shadow(color: .black.opacity(0.08), radius: 6, y: -2)
    }
}

