import SwiftUI

extension MediaPlaylist {
    /// Stable per-playlist colour pair taken from the active theme.
    var palette: [Color] { RitimTheme.palettes[Int(id.uuid.0) % RitimTheme.palettes.count] }
}

/// A colourful playlist cover: up to four track covers in a mosaic over the playlist's own gradient.
struct PlaylistCover: View {
    let playlist: MediaPlaylist
    let tracks: [MediaTrack]
    var radius: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            ZStack {
                LinearGradient(colors: playlist.palette, startPoint: .topLeading, endPoint: .bottomTrailing)
                if let selected = tracks.first(where: { $0.id == playlist.coverTrackID }) {
                    CoverArt(track: selected, radius: 0).frame(width: side, height: side)
                } else if tracks.count >= 4 {
                    let cell = side / 2
                    VStack(spacing: 0) {
                        HStack(spacing: 0) { mosaic(0, cell); mosaic(1, cell) }
                        HStack(spacing: 0) { mosaic(2, cell); mosaic(3, cell) }
                    }.opacity(0.92)
                } else if let first = tracks.first {
                    CoverArt(track: first, radius: 0).frame(width: side, height: side).opacity(0.92)
                } else {
                    Image(systemName: "music.note.list").font(.system(size: side * 0.38, weight: .light))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }.frame(width: side, height: side).clipped()
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityHidden(true)
    }

    private func mosaic(_ index: Int, _ cell: CGFloat) -> some View {
        CoverArt(track: tracks[index], radius: 0).frame(width: cell, height: cell)
    }
}

/// Library shelf card: gradient wash in the playlist's colours with the mosaic and a play affordance.
struct PlaylistCard: View {
    let playlist: MediaPlaylist
    let tracks: [MediaTrack]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlaylistCover(playlist: playlist, tracks: tracks, radius: 14).frame(width: 138, height: 138)
                .shadow(color: playlist.palette[0].opacity(0.55), radius: 14, y: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                Text("\(tracks.count) parça").font(.caption).foregroundStyle(playlist.palette[1])
            }
        }
        .frame(width: 138, alignment: .leading)
        .padding(10).background(
            LinearGradient(colors: [playlist.palette[0].opacity(0.32), RitimTheme.surface], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(playlist.palette[1].opacity(0.22)))
    }
}

/// Header of the playlist screen: big cover on a gradient backdrop, counts and play / shuffle buttons.
struct PlaylistHeader: View {
    @EnvironmentObject private var playback: PlaybackStore
    let playlist: MediaPlaylist
    let tracks: [MediaTrack]
    @State private var showMix = false

    private var totalDuration: String {
        let minutes = Int(tracks.reduce(0) { $0 + $1.duration } / 60)
        return minutes >= 60 ? "\(minutes / 60) sa \(minutes % 60) dk" : "\(max(minutes, tracks.isEmpty ? 0 : 1)) dk"
    }

    var body: some View {
        VStack(spacing: 16) {
            PlaylistCover(playlist: playlist, tracks: tracks, radius: 22).frame(width: 190, height: 190)
                .shadow(color: playlist.palette[0].opacity(0.6), radius: 24, y: 12)
            VStack(spacing: 4) {
                Text(playlist.name).font(.title.bold()).multilineTextAlignment(.center)
                    .accessibilityIdentifier("playlist.header.title")
                if let detail = playlist.detail, !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(RitimTheme.muted).multilineTextAlignment(.center) }
                Text("\(tracks.count) parça · \(totalDuration)").font(.subheadline).foregroundStyle(playlist.palette[1])
            }
            HStack(spacing: 12) {
                Button { if let first = tracks.first { playback.shuffleEnabled = false; playback.play(first, in: tracks) } } label: {
                    Label("Çal", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(RitimTheme.background).background(playlist.palette[1], in: Capsule())
                }.accessibilityIdentifier("playlist.play")
                Button {
                    if let random = tracks.randomElement() { playback.shuffleEnabled = true; playback.play(random, in: tracks) }
                } label: {
                    Label("Karıştır", systemImage: "shuffle").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(.white).background(.white.opacity(0.12), in: Capsule())
                }.accessibilityIdentifier("playlist.shuffle")
            }.buttonStyle(RitimPressStyle()).disabled(tracks.isEmpty).opacity(tracks.isEmpty ? 0.5 : 1)
            Button { showMix = true } label: {
                Label("Akıllı mix · yeni şarkılar bul", systemImage: "sparkles").font(.subheadline.bold())
                    .frame(maxWidth: .infinity, minHeight: 46).foregroundStyle(playlist.palette[1])
                    .background(playlist.palette[1].opacity(0.16), in: Capsule())
                    .overlay(Capsule().strokeBorder(playlist.palette[1].opacity(0.35)))
            }.buttonStyle(RitimPressStyle()).accessibilityIdentifier("playlist.smartMix")
        }
        .sheet(isPresented: $showMix) { PlaylistMixSheet(playlist: playlist, tracks: tracks) }
        .padding(.vertical, 22).padding(.horizontal, 18).frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [playlist.palette[0].opacity(0.55), RitimTheme.background], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

/// "Akıllı mix": the model proposes searches similar to the playlist's artists; the user picks new songs
/// and they are downloaded straight into this playlist.
struct PlaylistMixSheet: View {
    @EnvironmentObject private var assistant: AIAssistantStore
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let playlist: MediaPlaylist
    let tracks: [MediaTrack]
    @State private var round = 0

    /// Most frequent artists first; the round rotates which ones seed the search so "yeniden" gives new ideas.
    private var seed: String {
        var counts: [String: Int] = [:]
        for track in tracks where !track.artist.isEmpty && track.artist != "Bilinmeyen sanatçı" { counts[track.artist, default: 0] += 1 }
        let artists = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        guard !artists.isEmpty else { return playlist.name }
        let start = (round * 2) % artists.count
        let picked = (0..<min(2, artists.count)).map { artists[(start + $0) % artists.count] }
        return picked.joined(separator: " ") + " benzeri şarkılar"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        PlaylistCover(playlist: playlist, tracks: tracks, radius: 12).frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(playlist.name).font(.headline)
                            Text(assistant.searchQuery ?? seed).font(.caption).foregroundStyle(RitimTheme.muted).lineLimit(2)
                                .accessibilityIdentifier("mix.query")
                        }
                        Spacer(minLength: 0)
                        Button { round += 1; Task { await assistant.discover(seed, library: library) } } label: {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.title3).frame(width: 44, height: 44)
                        }.accessibilityLabel("Yeniden karıştır").accessibilityIdentifier("mix.reshuffle").disabled(assistant.isSearching)
                    }
                    YouTubeDiscoverResults(idPrefix: "mix", playlistTitle: playlist.name)
                }.padding(20)
            }
            .background(RitimTheme.background)
            .navigationTitle("Akıllı mix").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
        }
        .preferredColorScheme(.dark).tint(RitimTheme.mint)
        .task { await assistant.discover(seed, library: library) }
        .onDisappear { assistant.clearSearch() }
    }
}
