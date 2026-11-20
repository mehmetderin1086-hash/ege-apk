import SwiftUI

@main struct IETTAsistanApp: App {
    @State private var model = AppModel()
    @AppStorage("appearance") private var appearance = 0
    @Environment(\.scenePhase) private var scenePhase
    init() { BackgroundRefresh.register() }
    var body: some Scene {
        WindowGroup {
            RootView().environment(model).tint(Theme.accent)
                .preferredColorScheme(appearance == 1 ? .light : appearance == 2 ? .dark : nil)
                .task { model.loadDemoIfRequested(); if !model.isDemo { await model.load() } }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.rescheduleAlerts() } }
                    if phase == .background { BackgroundRefresh.schedule() }
                }
                .onOpenURL { url in if let route = Route(url: url) { NotificationCenter.default.post(name: .openRoute, object: route) } }
        }
    }
}

extension Notification.Name { static let openRoute = Notification.Name("iett.openRoute") }

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var zoom
    @State private var tab = RootView.debugTab
    @State private var navs = [Navigator(), Navigator(), Navigator(), Navigator(), Navigator()]

    /// Yalnız Debug: `-openTab=N` sekmeyi, `-openRoute=line:500T` ya da `timetable:500T` / `info:500T` / `stop:CODE` / `settings` / `notes` hedefi açar.
    static var debugTab: Int {
        #if DEBUG
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix("-openTab=") }.flatMap { Int($0.dropFirst(9)) } ?? 0
        #else
        0
        #endif
    }
    static var debugRoute: Route? {
        #if DEBUG
        guard let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-openRoute=") }) else { return nil }
        let parts = arg.dropFirst(11).split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first, parts.last) {
        case ("line", let code?): return .line(code: code, stop: nil)
        case ("timetable", let code?): return .timetable(code: code, direction: nil, stop: nil)
        case ("info", let code?): return .lineInfo(code: code)
        case ("stop", let code?): return Int(code).map { .stop(code: $0) }
        case ("settings", _): return .settings
        case ("notes", _): return .notes
        default: return nil
        }
        #else
        return nil
        #endif
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Takip", systemImage: "bus.fill", value: 0) { TabStack(nav: navs[0]) { FavoritesView() } }
            Tab("Hatlar", systemImage: "list.bullet.rectangle", value: 1) { TabStack(nav: navs[1]) { LinesView() } }
            Tab("Yakınımda", systemImage: "location.fill", value: 2) { TabStack(nav: navs[2]) { NearbyView() } }
            Tab("Asistan", systemImage: "sparkles", value: 3) { TabStack(nav: navs[3]) { AssistantView() } }
            Tab("Ekran", systemImage: "display", value: 4) { TabStack(nav: navs[4]) { StopBoardView() } }
        }
        .environment(\.zoomNamespace, zoom)
        .onReceive(NotificationCenter.default.publisher(for: .openRoute)) { note in
            if let route = note.object as? Route { tab = 0; navs[0].home(); navs[0].push(route) }
        }
        .sensoryFeedback(.selection, trigger: tab)
        .overlay(alignment: .top) {
            if let error = model.loadError {
                Text(error).font(.footnote).padding(8).frame(maxWidth: .infinity).background(.red.opacity(0.85)).foregroundStyle(.white)
            }
        }
        .task {
            #if DEBUG
            if let route = Self.debugRoute {
                try? await Task.sleep(for: .milliseconds(900))
                navs[min(max(tab, 0), 4)].push(route)
            }
            #endif
        }
    }
}

/// Dakika rozeti (widget/yedek kullanım): büyük sayı + "dk".
struct ETABadge: View {
    let eta: BusETA?
    var body: some View { ETARing(eta: eta, size: 62) }
}
