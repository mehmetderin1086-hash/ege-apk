import SwiftUI
import UIKit

/// #18 Yolda modu: büyük düğmeler, ekran kararmaz. Bakmadan dokunulabilsin diye her düğme geniş ve etiketlidir.
struct OnTheRoadView: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var feedback: String?

    var body: some View {
        // Yükseklik sabit öğelerden oluşur: kısa ekranda (SE, Ekran Büyütme) ve büyük yazıda önce sıkı ölçüye,
        // o da sığmazsa kaydırmaya geçer. Kapatma/hız satırı her durumda üstte sabit kalır.
        ViewThatFits(in: .vertical) {
            controls(.regular)
            controls(.compact)
            ScrollView { controls(.compact) }
                .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .safeAreaInset(edge: .top, spacing: 8) { topBar }
        .foregroundStyle(.white)
        .background(Color.black.ignoresSafeArea())
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .debugNarrowScreen()
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.title2.weight(.semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Yolda modunu kapat")
            Spacer()
            Button { cycleRate() } label: {
                Text(player.rate.rateText)
                    .font(.title3.bold().monospacedDigit())
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(.white.opacity(0.15), in: Capsule())
            }
            .accessibilityLabel("Oynatma hızı \(player.rate.rateText), değiştir")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(Color.black)
    }

    private func controls(_ m: RoadMetrics) -> some View {
        VStack(spacing: m.spacing) {
            VStack(spacing: 4) {
                Text(player.episode?.title ?? player.audioItem?.title ?? "Çalan bölüm yok")
                    .font(.title3.bold())
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if let chapter = chapterText {
                    Text(chapter).font(.headline).foregroundStyle(.white.opacity(0.75)).lineLimit(2).multilineTextAlignment(.center)
                }
            }
            .minimumScaleFactor(0.7)

            Spacer(minLength: 4)

            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: m.playIcon, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: m.playHeight)
                    .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(player.isPlaying ? "Duraklat" : "Oynat")

            Grid(horizontalSpacing: 12, verticalSpacing: m.spacing - 2) {
                GridRow {
                    big("gobackward.15", "15 sn geri", m) { player.skip(-15) }
                    big("goforward.15", "15 sn ileri", m) { player.skip(15) }
                }
                GridRow {
                    big("backward.end.fill", "Önceki konu", m) { player.previousChapter() }
                    big("forward.end.fill", "Sonraki konu", m) { player.nextChapter() }
                }
                GridRow {
                    big("bookmark.fill", "İşaretle", m) { mark(kind: "flag", message: "İşaretlendi") }
                    big("questionmark.circle.fill", "Anlamadım", m) { mark(kind: "confused", message: "Not edildi: tekrar dinle") }
                }
            }
            .disabled(player.episode == nil)

            Text(feedback ?? " ")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
                .accessibilityHidden(feedback == nil)
        }
    }

    private var chapterText: String? {
        guard let timeline = player.timeline, let chapter = timeline.chapters[safe: player.currentChapterIndex] else { return nil }
        let label = PlayerController.chapterLabel(index: player.currentChapterIndex, count: timeline.chapters.count)
        return [label, chapter.title].compactMap { $0 }.joined(separator: " · ")
    }

    private func big(_ symbol: String, _ title: String, _ m: RoadMetrics, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: m.compact ? 2 : 6) {
                Image(systemName: symbol).font(.system(size: m.tileIcon, weight: .semibold))
                Text(title).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, m.compact ? 6 : 0)
            .frame(maxWidth: .infinity, minHeight: m.tileHeight)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
    }

    private func cycleRate() {
        let rates = PlayerController.rates
        let next = rates.first { $0 > player.rate + 0.01 } ?? rates.first ?? 1
        player.rate = next
    }

    private func mark(kind: String, message: String) {
        guard player.addBookmark(kind: kind) != nil else { return }
        feedback = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            feedback = nil
        }
    }
}

/// Yolda modu ölçüleri: önce geniş, sığmazsa sıkı (kısa ekran / büyük yazı). Düğmeler 44 pt'nin çok üstünde kalır.
nonisolated struct RoadMetrics: Equatable {
    var spacing: CGFloat
    var playHeight: CGFloat
    var playIcon: CGFloat
    var tileHeight: CGFloat
    var tileIcon: CGFloat
    var compact: Bool

    static let regular = RoadMetrics(spacing: 14, playHeight: 140, playIcon: 64, tileHeight: 92, tileIcon: 34, compact: false)
    static let compact = RoadMetrics(spacing: 10, playHeight: 96, playIcon: 52, tileHeight: 68, tileIcon: 26, compact: true)
}
