import SwiftUI

/// Spotify-style home: greeting, filter chips, a two-column grid of quick tiles and
/// horizontal shelves of square covers. Tapping anything starts playback right away.
struct HomeShelves: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackStore
    @State private var filter = 0
    private static let filters = ["Tümü", "Müzik", "Video"]

    private var pool: [MediaTrack] {
        library.tracks.filter { filter == 0 || (filter == 1 ? $0.kind == .audio : $0.kind == .video) }
    }
    private var recent: [MediaTrack] {
        pool.filter { $0.lastPlayedAt != nil }.sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
    }
    private var quick: [MediaTrack] {
        var seen = Set<UUID>(), items: [MediaTrack] = []
        for track in pool.filter(\.isFavorite) + recent + pool.sorted(by: { $0.addedAt > $1.addedAt }) where seen.insert(track.id).inserted {
            items.append(track)
            if items.count == 6 { break }
        }
        return items
    }
    private var mostPlayed: [MediaTrack] { Array(pool.filter { $0.playCount > 0 }.sorted { $0.playCount > $1.playCount }.prefix(12)) }
    private var added: [MediaTrack] { Array(pool.sorted { $0.addedAt > $1.addedAt }.prefix(12)) }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Günaydın"
        case 12..<18: return "İyi günler"
        case 18..<23: return "İyi akşamlar"
        default: return "İyi geceler"
        }
    }

    var body: some View {
        if !library.tracks.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text(greeting).font(.title2.bold()).accessibilityIdentifier("home.greeting")
                chips
                if quick.isEmpty {
                    Text("Bu türde henüz parça yok.").font(.subheadline).foregroundStyle(RitimTheme.muted)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(Array(quick.enumerated()), id: \.element.id) { index, track in
                            tile(track, context: quick).accessibilityIdentifier("home.tile.\(index)").staggeredAppear(index)
                        }
                    }
                }
                shelf("Son çaldıkların", id: "recent", tracks: Array(recent.prefix(12)))
                shelf("Çok çaldıkların", id: "most", tracks: mostPlayed)
                shelf("Yeni eklenenler", id: "added", tracks: added)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: filter)
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            ForEach(Array(Self.filters.enumerated()), id: \.offset) { index, title in
                Button { filter = index } label: { Pill(title: title, selected: filter == index) }
                    .buttonStyle(RitimPressStyle()).accessibilityIdentifier("home.filter.\(index)")
                    .accessibilityAddTraits(filter == index ? .isSelected : [])
            }
        }
    }

    private func tile(_ track: MediaTrack, context: [MediaTrack]) -> some View {
        Button { playback.play(track, in: context) } label: {
            HStack(spacing: 10) {
                CoverArt(track: track, radius: 0).frame(width: 52, height: 52)
                Text(track.title).font(.footnote.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if playback.current?.id == track.id { LiveWaveSymbol(isPlaying: playback.isPlaying).padding(.trailing, 8) }
            }
            .frame(maxWidth: .infinity, alignment: .leading).frame(height: 52)
            .background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }.buttonStyle(RitimPressStyle()).foregroundStyle(.white)
    }

    @ViewBuilder private func shelf(_ title: String, id: String, tracks: [MediaTrack]) -> some View {
        if !tracks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.title3.bold())
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            Button { playback.play(track, in: tracks) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    CoverArt(track: track, radius: 10).frame(width: 144, height: 144)
                                    Text(track.title).font(.footnote.weight(.semibold)).lineLimit(1)
                                    Text(track.artist).font(.caption).foregroundStyle(RitimTheme.muted).lineLimit(1)
                                }.frame(width: 144, alignment: .leading)
                            }.buttonStyle(RitimPressStyle()).foregroundStyle(.white)
                                .accessibilityIdentifier("home.shelf.\(id).\(index)")
                                .scrollFlow(horizontal: true)
                        }
                    }.scrollTargetLayout()
                }.scrollTargetBehavior(.viewAligned)
            }
        }
    }
}
