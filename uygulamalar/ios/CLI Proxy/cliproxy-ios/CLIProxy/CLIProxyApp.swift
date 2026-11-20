import SwiftUI

@main
struct CLIProxyApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.launch() }
        }
        .onChange(of: phase) { _, p in model.scenePhaseChanged(p) }
    }
}
