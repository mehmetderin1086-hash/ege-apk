import SwiftData
import SwiftUI

/// #38: satırdan hızlı işlemler (uzun basma menüsü); çalan bölümü kesmez.
struct EpisodeQuickActions: View {
    let episode: Episode
    var rename: () -> Void
    var organize: () -> Void
    var delete: () -> Void
    /// Akış durumu ve işlemi üst görünümdedir: menü kapandıktan sonra da ilerleme, sonuç ve hata satırda görünür.
    var published = false
    var feedBusy = false
    var toggleFeed: () -> Void = {}
    @Environment(PlayerController.self) private var player
    @Environment(GenerationCoordinator.self) private var generator
    @Environment(\.modelContext) private var context

    var body: some View {
        if episode.status == .ready {
            Button("Sıraya ekle", systemImage: "text.line.last.and.arrowtriangle.forward") {
                player.enqueue(.episode(episode.id))
            }
            Button(episode.isFinished ? "Dinlenmedi olarak işaretle" : "Dinlendi olarak işaretle",
                   systemImage: episode.isFinished ? "circle" : "checkmark.circle") {
                QuickActions.setFinished(episode, !episode.isFinished)
                try? context.save()
            }
        }
        if QuickActions.canRetry(status: episode.status, hasScript: episode.script != nil, hasSettings: episode.settings != nil) {
            Button("Yeniden dene", systemImage: "arrow.clockwise") { generator.recoverAudio(episode, context: context) }
        }
        Button("Yeniden adlandır", systemImage: "pencil", action: rename)
        Button("Seri, ders ve akış…", systemImage: "folder", action: organize)
        if episode.status == .ready {
            Button(feedBusy ? "Podcast akışı güncelleniyor…" : published ? "Podcast akışından çıkar" : "Podcast akışına ekle",
                   systemImage: "dot.radiowaves.left.and.right", action: toggleFeed)
                .disabled(feedBusy)
        }
        Divider()
        Button("Sil", systemImage: "trash", role: .destructive, action: delete)
    }
}

enum QuickActions {
    /// `.episodeFinished` yayılmaz: o olay oynatıcının bölüm sonu içindir (P6 bölüm sonu kartı, otomatik geçiş).
    static func setFinished(_ episode: Episode, _ finished: Bool, defaults: UserDefaults = .standard, now: Date = .now) {
        episode.isFinished = finished
        // Baştan dinlemek için: "dinlenmedi" işaretinde sondaki konum sıfırlanır.
        if !finished, episode.lastPosition >= episode.duration - 1 { episode.lastPosition = 0 }
    }

    /// Başarısız bölümde senaryo ve ayarlar duruyorsa seslendirme kaldığı yerden sürdürülebilir.
    static func canRetry(status: EpisodeStatus, hasScript: Bool, hasSettings: Bool) -> Bool {
        status == .failed && hasScript && hasSettings
    }
}
