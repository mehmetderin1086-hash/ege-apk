import SwiftUI

/// Ekranın altında çalan bölüm çubuğu: −15 · oynat · +15 · İşaretle (#18) ve "Sıradakiler" (#41).
/// Dar ekranda (320 pt, büyük yazı) düğmeler ikinci satıra iner; her düğme en az 44×44 ve etiketlidir.
/// Kapatma: iki satırlı düzende duraklatılmışken ✕; her düzende uzun basınca menü ve VoiceOver eylemi.
struct MiniPlayer: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dynamicTypeSize) private var typeSize
    var open: () -> Void
    @State private var showQueue = false
    @State private var marked = false

    var body: some View {
        if player.isActive {
            ViewThatFits(in: .horizontal) {
                if !typeSize.isAccessibilitySize {
                HStack(spacing: 8) {
                    artwork
                    info.frame(width: 96, alignment: .leading)
                    Spacer(minLength: 0)
                    controls
                }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        artwork
                        info
                        Spacer(minLength: 0)
                        // Yalnız duraklatılmışken: çalarken yanlış dokunuş dinlemeyi kesmesin.
                        if !player.isPlaying { closeButton }
                    }
                    .frame(minHeight: 44)
                    controls.frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(.primary)
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    Capsule()
                        .fill(.tint)
                        .frame(width: geo.size.width * (player.duration > 0 ? min(1, player.currentTime / player.duration) : 0), height: 3)
                }
                .frame(height: 3)
                .padding(.horizontal, 14)
                .padding(.bottom, 2)
            }
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .contentShape(Rectangle())
            .onTapGesture { if player.episode != nil { open() } }
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contextMenu {
                if player.episode != nil { Button("Bölümü aç", systemImage: "arrow.up.forward.square", action: open) }
                Button("Oynatıcıyı kapat", systemImage: "xmark", role: .destructive) { player.close() }
            }
            .sheet(isPresented: $showQueue) { UpNextSheet().presentationDetents([.medium, .large]) }
        }
    }

    @ViewBuilder private var artwork: some View {
        if let episode = player.episode {
            EpisodeArtwork(title: episode.title, size: 42, cover: episode.visuals?.cover)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.warmGradient)
                .frame(width: 42, height: 42)
                .overlay { Image(systemName: "sun.max.fill").foregroundStyle(.white) }
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(player.episode?.title ?? player.audioItem?.title ?? "").font(.subheadline.bold()).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
        }
        // Kartın dokunma hareketi VoiceOver'a düğme olarak görünmez: başlık tek öğe olur, eylemler ona bağlanır.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(player.episode != nil ? .isButton : [])
        .accessibilityAction { if player.episode != nil { open() } }
        .accessibilityActions {
            if player.episode != nil { Button("Bölümü aç", action: open) }
            Button("Oynatıcıyı kapat") { player.close() }
        }
    }

    private var subtitle: String {
        if let clip = player.clipProgress { return "Kesit \(clip.index)/\(clip.count)" }
        if player.isInInterlude { return "Ara soru" }
        if let chapter = player.timeline?.chapters[safe: player.currentChapterIndex]?.title { return chapter }
        return player.upNext.isEmpty ? "" : "Sırada \(player.upNext.count) öğe"
    }

    private var controls: some View {
        HStack(spacing: 2) {
            iconButton("gobackward.15", label: "15 saniye geri") { player.skip(-15) }
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(player.isPlaying ? "Duraklat" : "Oynat")
            iconButton("goforward.15", label: "15 saniye ileri") { player.skip(15) }
            if player.episode != nil {
                iconButton(marked ? "bookmark.fill" : "bookmark", label: "İşaretle") {
                    guard player.addBookmark(kind: "flag") != nil else { return }
                    marked = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        marked = false
                    }
                }
            }
            if !player.upNext.isEmpty {
                iconButton("list.bullet", label: "Sıradakiler, \(player.upNext.count) öğe") { showQueue = true }
                    .overlay(alignment: .topTrailing) {
                        Text("\(player.upNext.count)")
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .background(Capsule().fill(.tint))
                            .accessibilityHidden(true)
                    }
            }
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// Çubuğu kaldırır; konum kaydedilir, sıradakiler listesi yerinde kalır (`PlayerController.close`).
    private var closeButton: some View {
        iconButton("xmark", label: "Oynatıcıyı kapat") { player.close() }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}
