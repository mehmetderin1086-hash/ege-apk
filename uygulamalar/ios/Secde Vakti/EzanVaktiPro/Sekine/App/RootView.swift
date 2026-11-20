import SwiftUI
import StoreKit

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var speechPlayer = AdhanPlayer.shared
    @State private var triggeredAlarmPrayer: Prayer?

    var body: some View {
        Group {
            if settings.hasCompletedOnboarding, settings.location != nil {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .alert("Stüdyo seslendirme", isPresented: Binding(
            get: { speechPlayer.speechError != nil },
            set: { if !$0 { speechPlayer.speechError = nil } }
        )) { Button("Tamam", role: .cancel) { speechPlayer.speechError = nil } }
        message: { Text(speechPlayer.speechError ?? "") }
        .dynamicTypeSize(settings.fontScale.dynamicTypeSize)
        .onReceive(NotificationCenter.default.publisher(for: .triggerFullScreenVakitAlarm)) { note in
            if let raw = note.object as? String, let p = Prayer(rawValue: raw) {
                triggeredAlarmPrayer = p
            } else {
                triggeredAlarmPrayer = .maghrib
            }
        }
        .fullScreenCover(item: $triggeredAlarmPrayer) { prayer in
            FullScreenAdhanAlarmView(prayer: prayer)
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: PrayerTimeStore
    @State private var selection: String = MainTabView.initialTab
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Vakitler", systemImage: "sun.max.fill") }.tag("home")
            VideoSpiritualFeedView()
                .tabItem { Label("Videolar", systemImage: "play.tv.fill") }.tag("video")
            QuranAndLibraryView()
                .tabItem { Label("Kur'an", systemImage: "book.fill") }.tag("quran")
            QiblaView()
                .tabItem { Label("Kıble", systemImage: "location.north.line.fill") }.tag("qibla")
            SpiritualView()
                .tabItem { Label("Keşfet", systemImage: "circle.grid.cross.fill") }.tag("spiritual")
        }
        .task { await maybeAskForReview() }
        .alert(
            "Konum değişti mi?",
            isPresented: Binding(
                get: { settings.pendingLocationSuggestion != nil },
                set: { if !$0 { settings.pendingLocationSuggestion = nil } }
            ),
            presenting: settings.pendingLocationSuggestion
        ) { suggestion in
            Button("Güncelle") {
                settings.location = suggestion
                Task { await store.refresh(location: suggestion, settings: settings) }
            }
            Button("Hayır", role: .cancel) {
                settings.declinedLocationDistrictID = suggestion.diyanetDistrictID
                settings.pendingLocationSuggestion = nil
            }
        } message: { suggestion in
            Text("Şu an \(suggestion.name) konumunda görünüyorsunuz. Namaz vakitlerini buna göre güncelleyelim mi?")
        }
    }

    private func maybeAskForReview() async {
        let prompt = ReviewPrompt()
        prompt.recordOpen()
        let version = ReviewPrompt.currentVersion
        guard prompt.shouldAsk(version: version, positiveMoment: false) else { return }

        try? await Task.sleep(for: .seconds(4))
        guard settings.pendingLocationSuggestion == nil else { return }

        prompt.markAsked(version: version)
        requestReview()
    }

    static var initialTab: String {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-uiTestTab"), i + 1 < args.count {
            return args[i + 1]
        }
        #endif
        return "home"
    }
}
