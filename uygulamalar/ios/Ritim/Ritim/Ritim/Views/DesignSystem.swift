import SwiftUI
import AVKit

/// One complete colour scheme. Everything in the app reads its colours through `RitimTheme`.
struct ThemeStyle: Identifiable, Equatable {
    let id: String
    let name: String
    let accent: Color
    let second: Color
    let background: Color
    let surface: Color
    let elevated: Color
    let palettes: [[Color]]

    private static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    static let all: [ThemeStyle] = [
        ThemeStyle(id: "nane", name: "Nane", accent: c(0.65, 0.96, 0.63), second: c(0.72, 0.65, 1),
                   background: c(0.045, 0.055, 0.075), surface: c(0.095, 0.11, 0.14), elevated: c(0.14, 0.16, 0.20),
                   palettes: [[c(0.28, 0.16, 0.60), c(0.80, 0.53, 0.77)], [c(0.05, 0.38, 0.38), c(0.61, 0.89, 0.63)],
                              [c(0.52, 0.20, 0.15), c(1, 0.69, 0.43)], [c(0.12, 0.28, 0.64), c(0.47, 0.76, 0.96)],
                              [c(0.42, 0.15, 0.38), c(0.99, 0.58, 0.65)]]),
        ThemeStyle(id: "okyanus", name: "Okyanus", accent: c(0.36, 0.84, 1), second: c(0.55, 0.62, 1),
                   background: c(0.03, 0.06, 0.11), surface: c(0.07, 0.12, 0.19), elevated: c(0.11, 0.18, 0.27),
                   palettes: [[c(0.03, 0.25, 0.55), c(0.35, 0.85, 0.95)], [c(0.10, 0.20, 0.60), c(0.62, 0.55, 1)],
                              [c(0.00, 0.35, 0.45), c(0.45, 0.95, 0.85)], [c(0.15, 0.15, 0.50), c(0.40, 0.70, 1)],
                              [c(0.05, 0.30, 0.50), c(0.70, 0.90, 1)]]),
        ThemeStyle(id: "gunbatimi", name: "Gün batımı", accent: c(1, 0.62, 0.32), second: c(1, 0.42, 0.62),
                   background: c(0.085, 0.045, 0.05), surface: c(0.15, 0.085, 0.09), elevated: c(0.22, 0.13, 0.13),
                   palettes: [[c(0.65, 0.18, 0.12), c(1, 0.72, 0.30)], [c(0.60, 0.10, 0.35), c(1, 0.55, 0.45)],
                              [c(0.45, 0.10, 0.40), c(1, 0.45, 0.62)], [c(0.70, 0.30, 0.05), c(1, 0.85, 0.40)],
                              [c(0.50, 0.12, 0.20), c(1, 0.60, 0.50)]]),
        ThemeStyle(id: "orman", name: "Orman", accent: c(0.50, 0.92, 0.45), second: c(0.95, 0.85, 0.40),
                   background: c(0.04, 0.07, 0.05), surface: c(0.08, 0.13, 0.09), elevated: c(0.12, 0.20, 0.13),
                   palettes: [[c(0.05, 0.35, 0.18), c(0.65, 0.95, 0.45)], [c(0.15, 0.40, 0.10), c(0.95, 0.88, 0.40)],
                              [c(0.00, 0.30, 0.30), c(0.55, 0.95, 0.70)], [c(0.30, 0.35, 0.05), c(0.85, 0.95, 0.40)],
                              [c(0.08, 0.28, 0.20), c(0.60, 0.85, 0.55)]]),
        ThemeStyle(id: "gul", name: "Gül", accent: c(1, 0.50, 0.72), second: c(0.75, 0.55, 1),
                   background: c(0.08, 0.04, 0.07), surface: c(0.14, 0.08, 0.13), elevated: c(0.21, 0.12, 0.19),
                   palettes: [[c(0.55, 0.10, 0.40), c(1, 0.60, 0.80)], [c(0.35, 0.15, 0.55), c(0.90, 0.60, 1)],
                              [c(0.65, 0.15, 0.35), c(1, 0.70, 0.65)], [c(0.45, 0.10, 0.50), c(1, 0.50, 0.85)],
                              [c(0.30, 0.12, 0.45), c(0.80, 0.65, 1)]]),
        // Every cover gets a different, saturated pair; the accent is a bright yellow.
        ThemeStyle(id: "rengarenk", name: "Rengârenk", accent: c(1, 0.84, 0.25), second: c(1, 0.35, 0.75),
                   background: c(0.05, 0.04, 0.09), surface: c(0.11, 0.09, 0.17), elevated: c(0.17, 0.14, 0.25),
                   palettes: [[c(0.90, 0.15, 0.30), c(1, 0.80, 0.20)], [c(0.10, 0.65, 0.95), c(0.55, 1, 0.55)],
                              [c(0.60, 0.15, 0.95), c(1, 0.40, 0.75)], [c(0.00, 0.80, 0.55), c(0.95, 0.95, 0.25)],
                              [c(1, 0.45, 0.10), c(0.95, 0.20, 0.65)], [c(0.20, 0.30, 1), c(0.20, 0.95, 0.90)]])
    ]

    static func style(id: String?) -> ThemeStyle { all.first { $0.id == id } ?? all[0] }
}

enum RitimTheme {
    /// Set by `ThemeStore`; the app root is rebuilt when it changes.
    nonisolated(unsafe) static var style = ThemeStyle.style(id: UserDefaults.standard.string(forKey: ThemeStore.key))
    static var background: Color { style.background }
    static var surface: Color { style.surface }
    static var elevated: Color { style.elevated }
    static var mint: Color { style.accent }
    static var lavender: Color { style.second }
    static let muted = Color(red: 0.62, green: 0.66, blue: 0.71)
    static var palettes: [[Color]] { style.palettes }
}

@MainActor
final class ThemeStore: ObservableObject {
    nonisolated static let key = "ritim.theme"
    @Published private(set) var selectedID: String
    /// Bumped on every change; the app root uses it as its identity so every view re-reads the colours.
    @Published private(set) var version = 0
    /// Where to land after the rebuild (the settings sheet that triggered it stays open).
    var resume: (tab: String, settings: Bool)?
    var lastTab = "Keşfet"

    init() { selectedID = ThemeStyle.style(id: UserDefaults.standard.string(forKey: Self.key)).id }

    func select(_ id: String, reopenSettings: Bool) {
        let style = ThemeStyle.style(id: id)
        guard style.id != selectedID else { return }
        selectedID = style.id
        UserDefaults.standard.set(style.id, forKey: Self.key)
        RitimTheme.style = style
        resume = (lastTab, reopenSettings)
        version += 1
    }
}

/// A calm playback-state indicator, not an audio amplitude meter.
struct PlayingBars: View {
    let isPlaying: Bool
    var color: Color = RitimTheme.mint

    var body: some View {
        LiveWaveSymbol(isPlaying: isPlaying, color: color)
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }
}

/// Keeps custom button hit areas and padding intact.
struct RitimPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct CoverArt: View {
    let track: MediaTrack?
    var radius: CGFloat = 16
    var animated = false
    var level: Double = 0
    /// Stable per-track seed (FNV-1a over the id bytes) so generated art never changes between launches.
    private var seed: UInt64 {
        guard let id = track?.id else { return 7 }
        return withUnsafeBytes(of: id.uuid) { $0.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 } }
    }
    var body: some View {
        let palette = RitimTheme.palettes[(track?.colorIndex ?? 0) % RitimTheme.palettes.count]
        GeometryReader { geometry in
            ZStack {
                GenerativeCoverBackdrop(seed: seed, palette: palette, animated: animated, level: level)
                Image(systemName: track?.kind == .video ? "play.rectangle.fill" : "waveform")
                    .font(.system(size: geometry.size.width * 0.28, weight: .light))
                    .foregroundStyle(.white.opacity(0.8)).rotationEffect(.degrees(-10))
                TrackArtwork(track: track)
            }
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct SectionTitle: View {
    let title: String
    var caption: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold()).foregroundStyle(.white)
            Spacer()
            if let caption { Text(caption).font(.caption).foregroundStyle(RitimTheme.muted) }
        }
    }
}

struct Pill: View {
    let title: String
    var icon: String? = nil
    var selected = false
    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon) }
            Text(title)
        }
        .font(.subheadline.weight(.semibold)).padding(.horizontal, 16).padding(.vertical, 11)
        .foregroundStyle(selected ? RitimTheme.background : .white)
        .background(selected ? RitimTheme.mint : RitimTheme.surface, in: Capsule())
    }
}

struct EmptyLibrary: View {
    let title: String
    let message: String
    var icon = "music.note.list"
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 36, weight: .light)).foregroundStyle(RitimTheme.mint)
            Text(title).font(.headline).foregroundStyle(.white)
            Text(message).font(.subheadline).foregroundStyle(RitimTheme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 42)
    }
}

struct TrackRow: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackStore
    let track: MediaTrack
    let context: [MediaTrack]
    var playlist: MediaPlaylist? = nil
    @State private var choosePlaylist = false
    @State private var confirmDelete = false
    @State private var rename = false
    @State private var editedTitle = ""
    @State private var editedArtist = ""
    var body: some View {
        HStack(spacing: 12) {
            Button { playback.play(track, in: context) } label: {
                HStack(spacing: 12) {
                    CoverArt(track: track, radius: 10).frame(width: 54, height: 54)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title).font(.subheadline.weight(.semibold))
                            .foregroundStyle(playback.current?.id == track.id ? RitimTheme.mint : .white).lineLimit(1)
                        HStack(spacing: 4) {
                            if track.kind == .video { Image(systemName: "video.fill").font(.caption2) }
                            Text(track.subtitle).font(.caption).lineLimit(1)
                        }.foregroundStyle(RitimTheme.muted)
                    }
                    Spacer(minLength: 0)
                    if playback.current?.id == track.id && playback.isPlaying {
                        PlayingBars(isPlaying: playback.isPlaying)
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(track.title), çal")
            Menu {
                Button { library.toggleFavorite(track) } label: {
                    Label(track.isFavorite ? "Beğenilerden kaldır" : "Beğen", systemImage: track.isFavorite ? "heart.slash" : "heart")
                }
                Button { playback.enqueueNext(track) } label: { Label("Sıradaki çal", systemImage: "text.line.first.and.arrowtriangle.forward") }
                Button { playback.enqueue(track) } label: { Label("En sona ekle", systemImage: "text.line.last.and.arrowtriangle.forward") }
                Button { choosePlaylist = true } label: { Label("Listeye ekle", systemImage: "text.badge.plus") }
                Button { editedTitle = track.title; editedArtist = track.artist; rename = true } label: { Label("Bilgileri düzenle", systemImage: "pencil") }
                if let playlist {
                    Button(role: .destructive) { library.remove(track, from: playlist) } label: { Label("Listeden kaldır", systemImage: "minus.circle") }
                }
                ShareLink(item: library.url(for: track)) { Label("Dosyayı paylaş", systemImage: "square.and.arrow.up") }
                Button(role: .destructive) { confirmDelete = true } label: { Label("Kütüphaneden sil", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").font(.title3).foregroundStyle(RitimTheme.muted).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("\(track.title) seçenekleri")
        }
        .padding(.vertical, 5)
        .sheet(isPresented: $choosePlaylist) { AddToPlaylistView(track: track) }
        .confirmationDialog("Bu dosya kütüphaneden ve cihazdan silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Dosyayı sil", role: .destructive) { library.delete(track) }
        }
        .alert("Parça bilgileri", isPresented: $rename) {
            TextField("Başlık", text: $editedTitle)
            TextField("Sanatçı", text: $editedArtist)
            Button("Kaydet") { library.rename(track, title: editedTitle, artist: editedArtist) }
            Button("Vazgeç", role: .cancel) {}
        }
    }
}

struct AddToPlaylistView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let track: MediaTrack
    @State private var newName = ""
    @State private var failure: String?
    var body: some View {
        NavigationStack {
            List {
                Section("Yeni liste") {
                    TextField("Liste adı", text: $newName)
                    Button("Oluştur ve ekle") {
                        do { _ = try library.createPlaylist(name: newName, trackIDs: [track.id]); dismiss() }
                        catch { failure = error.localizedDescription }
                    }.disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("Listelerin") {
                    ForEach(library.playlists) { playlist in
                        Button {
                            if library.add([track], to: playlist) { dismiss() }
                            else { failure = library.errorMessage ?? "Liste güncellenemedi." }
                        } label: {
                            HStack { Label(playlist.name, systemImage: "music.note.list"); Spacer(); if playlist.trackIDs.contains(track.id) { Image(systemName: "checkmark") } }
                        }
                    }
                }
                if let failure { Text(failure).foregroundStyle(.orange) }
            }.navigationTitle("Listeye ekle").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
        }.tint(RitimTheme.mint).preferredColorScheme(.dark)
    }
}

struct BatchAddToPlaylistView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let tracks: [MediaTrack]
    let onAdded: () -> Void
    @State private var newName = ""
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                Section("\(tracks.count) parça") {
                    TextField("Yeni liste adı", text: $newName)
                    Button("Yeni liste oluştur") {
                        do {
                            _ = try library.createPlaylist(name: newName, trackIDs: tracks.map(\.id))
                            onAdded(); dismiss()
                        } catch { failure = error.localizedDescription }
                    }.disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || tracks.isEmpty)
                }
                Section("Listelerin") {
                    if library.playlists.isEmpty { Text("Henüz bir liste yok.").foregroundStyle(RitimTheme.muted) }
                    ForEach(library.playlists) { playlist in
                        Button {
                            if library.add(tracks, to: playlist) { onAdded(); dismiss() }
                            else { failure = library.errorMessage ?? "Liste güncellenemedi." }
                        } label: { Label(playlist.name, systemImage: "music.note.list") }
                    }
                }
                if let failure { Text(failure).foregroundStyle(.orange) }
            }.navigationTitle("Listeye ekle").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
        }.tint(RitimTheme.mint).preferredColorScheme(.dark)
    }
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = UIColor(RitimTheme.mint)
        view.prioritizesVideoDevices = false
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

func timeLabel(_ seconds: Double) -> String {
    let seconds = seconds.isFinite ? max(0, Int(seconds)) : 0
    return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) : String(format: "%d:%02d", seconds / 60, seconds % 60)
}
