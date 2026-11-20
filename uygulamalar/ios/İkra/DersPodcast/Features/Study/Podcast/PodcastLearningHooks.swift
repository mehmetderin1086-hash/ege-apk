import SwiftData
import SwiftUI

/// Bölüm ekranının öğrenme kancaları. Konu sonu kararı uygulama genelindeki tek hakemdedir
/// (`PodcastLearning`, `.chapterFinished`); burada "bu bölümün detayı açık" bilgisi verilir, hakemin kurduğu
/// dinlerken quiz bu ekrandan sunulur ve sınav modunda ön test önerilir. `player.onChapterBoundary` kullanılmaz.
struct PodcastLearningHooks: ViewModifier {
    var episode: Episode
    @State private var token: UUID?
    @State private var center = LearningCenter.shared

    /// Bu bölümün dinlerken quiz'i (konu sonu hakemi kurar).
    private var inlineQuiz: Binding<LearningSheet?> {
        Binding(get: {
            if case let .inlineQuiz(id, _, _, _) = center.sheet, id == episode.id { return center.sheet }
            return nil
        }, set: { new in
            if new == nil, center.sheet?.isInlineQuiz == true { center.sheet = nil }
        })
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: inlineQuiz, onDismiss: { center.sheetDismissed() }) { sheet in
                LearningSheetView(sheet: sheet)
            }
            .onAppear {
                if let token { LearningCenter.shared.detailDisappeared(token) }
                token = LearningCenter.shared.detailAppeared(episode.id)
                LearningCenter.shared.offerPretestIfNeeded(episode)
            }
            .onDisappear {
                if let token { LearningCenter.shared.detailDisappeared(token) }
                token = nil
            }
            .onChange(of: episode.id) { _, new in
                if let token { LearningCenter.shared.detailDisappeared(token) }
                token = LearningCenter.shared.detailAppeared(new)
            }
    }
}

extension View {
    /// Bölüm ekranının öğrenme kancalarını bağlar (P6).
    func podcastLearningHooks(episode: Episode) -> some View {
        modifier(PodcastLearningHooks(episode: episode))
    }
}
