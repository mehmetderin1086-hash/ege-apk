import SwiftUI
import UIKit
import BackgroundTasks

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: DownloadStore.processingIdentifier, using: nil) { task in
            guard let processing = task as? BGProcessingTask else { task.setTaskCompleted(success: false); return }
            Task { @MainActor in
                guard let store = DownloadStore.activeInstance else { processing.setTaskCompleted(success: false); return }
                store.runBackgroundProcessing(processing)
            }
        }
        return true
    }
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        DownloadStore.backgroundCompletion = completionHandler
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        #if DEBUG
        // A handled or tilted phone must not rotate the UI under coordinate-based automation.
        if ProcessInfo.processInfo.environment["RITIM_UI_TEST_MODE"] == "1" { return .portrait }
        #endif
        return UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }
}

@main
struct RitimApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var theme = ThemeStore()
    @StateObject private var library: LibraryStore
    @StateObject private var playback: PlaybackStore
    @StateObject private var downloads: DownloadStore
    @StateObject private var assistant: AIAssistantStore
    @StateObject private var listening: ListeningStore
    @StateObject private var lyrics: LyricsStore
    #if DEBUG
    @State private var acceptanceResumed = false
    #endif
    init() {
        let library: LibraryStore
        let sessionIdentifier: String
        #if DEBUG
        if ProcessInfo.processInfo.environment["RITIM_UI_TEST_MODE"] == "1" {
            UIApplication.shared.isIdleTimerDisabled = true
            // UI automation owns this fixture folder; user media is never reset.
            let fixture = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("RitimUITestFixtures")
            if ProcessInfo.processInfo.environment["RITIM_UI_TEST_PRESERVE_FIXTURES"] != "1" {
                try? FileManager.default.removeItem(at: fixture)
            }
            library = LibraryStore(directory: fixture.appendingPathComponent("Media"))
            if ProcessInfo.processInfo.environment["RITIM_UI_TEST_LONG_TITLE"] == "1", let track = library.tracks.first {
                library.rename(track, title: "Adele - Easy On Me (Official Lyric Video)", artist: "Adele")
            }
            sessionIdentifier = "com.mehmetderin.ritim.downloads.uitests"
        } else {
            library = LibraryStore()
            sessionIdentifier = "com.mehmetderin.ritim.downloads"
        }
        #else
        library = LibraryStore()
        sessionIdentifier = "com.mehmetderin.ritim.downloads"
        #endif
        let downloads = DownloadStore(library: library, sessionIdentifier: sessionIdentifier)
        let listening = ListeningStore(directory: library.directory.deletingLastPathComponent())
        _listening = StateObject(wrappedValue: listening)
        _lyrics = StateObject(wrappedValue: LyricsStore(directory: library.directory.deletingLastPathComponent().appendingPathComponent("Lyrics"), networkEnabled: ProcessInfo.processInfo.environment["RITIM_UI_TEST_MODE"] != "1"))
        _library = StateObject(wrappedValue: library)
        _playback = StateObject(wrappedValue: PlaybackStore(library: library, listening: listening))
        _downloads = StateObject(wrappedValue: downloads)
        var assistant: AIAssistantStore?
        #if DEBUG
        if ProcessInfo.processInfo.environment["RITIM_UI_TEST_AI_STUB"] == "1" {
            // Offline AI for UI automation: deterministic replies, no network, no Keychain access.
            let stubConnection = AIConnectionSettings(baseURL: "https://stub.ritim.invalid/v1", defaultModelID: StubAIClient.modelID)
            assistant = AIAssistantStore(directory: library.directory.deletingLastPathComponent(), connection: stubConnection,
                                         tokenProvider: { "stub" }, searchProvider: StubYouTubeSearch.search, client: StubAIClient())
        }
        #endif
        #if DEBUG
        if assistant == nil, ProcessInfo.processInfo.environment["RITIM_UI_TEST_MODE"] == "1" {
            // UI runs start with a fresh fixture folder; never spend real model quota on an automatic daily mix.
            let live = AIAssistantStore(directory: library.directory.deletingLastPathComponent())
            live.proactiveEnabled = false
            assistant = live
        }
        #endif
        _assistant = StateObject(wrappedValue: assistant ?? AIAssistantStore(directory: library.directory.deletingLastPathComponent()))
    }
    var body: some Scene {
        WindowGroup {
            RootView()
                .id(theme.version)
                .environmentObject(theme)
                .environmentObject(library).environmentObject(playback).environmentObject(downloads)
                .environmentObject(assistant).environmentObject(listening).environmentObject(lyrics)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active {
                        downloads.applicationDidBecomeActive()
                        #if DEBUG
                        // Explicit, one-shot device acceptance request; ordinary launches never trigger it.
                        if !acceptanceResumed {
                            if ProcessInfo.processInfo.arguments.contains("--ritim-acceptance-resume") {
                                acceptanceResumed = true
                                downloads.resumeQueue()
                            } else if ProcessInfo.processInfo.arguments.contains("--ritim-acceptance-video"),
                                      ProcessInfo.processInfo.environment["RITIM_UI_TEST_MODE"] == "1" {
                                acceptanceResumed = true
                                downloads.downloadQuality = .standard
                                let videoURL = ProcessInfo.processInfo.environment["RITIM_TEST_VIDEO_URL"] ?? "https://www.youtube.com/watch?v=jNQXAC9IVRw"
                                downloads.start(url: videoURL, format: .mp4)
                            }
                            if ProcessInfo.processInfo.arguments.contains("--ritim-acceptance-playback") {
                                acceptanceResumed = true
                                if !playback.isPlaying {
                                    if playback.current != nil { playback.togglePlayPause() }
                                    else if let first = library.tracks.first { playback.play(first, in: library.tracks) }
                                }
                            }
                        }
                        #endif
                    } else {
                        listening.flush()
                        if phase == .background { downloads.applicationDidEnterBackground() }
                    }
                    updateIdleTimer()
                }
                .onChange(of: downloads.runningCount) { _, _ in updateIdleTimer() }
                .onChange(of: downloads.pendingCount) { _, _ in updateIdleTimer() }
                .onChange(of: downloads.isQueuePaused) { _, _ in updateIdleTimer() }
                .onChange(of: downloads.keepScreenAwake) { _, _ in updateIdleTimer() }
                .onOpenURL { url in
                    if url.isFileURL { Task { await library.importFiles([url]) } }
                }
        }
    }

    private func updateIdleTimer() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["RITIM_UI_TEST_MODE"] == "1" {
            UIApplication.shared.isIdleTimerDisabled = true
            return
        }
        #endif
        let hasWork = downloads.runningCount > 0 || (!downloads.isQueuePaused && downloads.pendingCount > 0)
        UIApplication.shared.isIdleTimerDisabled = scenePhase == .active && downloads.keepScreenAwake && hasWork
    }
}
