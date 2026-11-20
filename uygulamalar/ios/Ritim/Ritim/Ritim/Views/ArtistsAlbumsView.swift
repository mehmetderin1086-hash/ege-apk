import SwiftUI

/// Transparent when a file has no embedded cover; overlay the existing generated art.
struct TrackArtwork: View {
    @EnvironmentObject private var library: LibraryStore
    let track: MediaTrack?
    @State private var image: UIImage?
    private var url: URL? { track.flatMap { library.artworkURL(for: $0) } }

    var body: some View {
        GeometryReader { geometry in
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }
        }
        .task(id: url) {
            image = nil
            guard let url else { return }
            let loaded = await MediaArtworkImages.shared.image(at: url)
            guard !Task.isCancelled else { return }
            image = loaded
        }
        .accessibilityHidden(true)
    }
}

struct ArtistsAlbumsView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = "Sanatçılar"
    @State private var query = ""

    private var artists: [MediaArtistGroup] {
        MediaLibraryGrouping.artists(library.tracks).filter { query.isEmpty || $0.name.localizedStandardContains(query) }
    }
    private var albums: [MediaAlbumGroup] {
        MediaLibraryGrouping.albums(library.tracks).filter {
            query.isEmpty || $0.name.localizedStandardContains(query) || $0.artist.localizedStandardContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Görünüm", selection: $selection) {
                        Text("Sanatçılar").tag("Sanatçılar")
                        Text("Albümler").tag("Albümler")
                    }.pickerStyle(.segmented)
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                Section {
                    if library.isScanningMetadata {
                        ProgressView(value: library.metadataScanProgress)
                        Button("Taramayı durdur") { library.cancelMetadataScan() }
                    } else {
                        Button { Task { await library.scanEmbeddedMetadata() } } label: {
                            Label("Bilgileri tara", systemImage: "arrow.triangle.2.circlepath")
                        }.disabled(library.tracks.isEmpty || scenePhase != .active)
                            .accessibilityIdentifier("metadata.scan")
                    }
                    if let message = library.metadataScanMessage {
                        Text(message).font(.caption).foregroundStyle(RitimTheme.muted)
                    }
                } footer: {
                    Text("Dosyalardaki albüm ve kapak bilgilerini okur. Parça ve sanatçı adların korunur. Tarama uygulama açıkken çalışır.")
                }
                if selection == "Sanatçılar" {
                    Section("\(artists.count) sanatçı") {
                        ForEach(artists) { artist in
                            NavigationLink {
                                MediaCollectionView(title: artist.name, artistID: artist.id, albumID: nil)
                            } label: { collectionRow(name: artist.name, detail: "\(artist.tracks.count) parça", track: artist.tracks.first) }
                        }
                    }
                } else {
                    Section("\(albums.count) albüm") {
                        ForEach(albums) { album in
                            NavigationLink {
                                MediaCollectionView(title: album.name, artistID: nil, albumID: album.id)
                            } label: { collectionRow(name: album.name, detail: "\(album.artist) • \(album.tracks.count) parça", track: album.tracks.first) }
                        }
                        if albums.isEmpty {
                            Text(query.isEmpty ? "Albüm bilgisi henüz yok. Gömülü bilgileri olan dosyaların için Bilgileri tara seçeneğini kullan." : "Eşleşen albüm bulunamadı.")
                                .font(.subheadline).foregroundStyle(RitimTheme.muted)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(RitimTheme.background)
            .navigationTitle("Albüm ve sanatçı").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Sanatçı veya albüm")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
        }
        .preferredColorScheme(.dark).tint(RitimTheme.mint)
        .onChange(of: scenePhase) { _, phase in if phase != .active { library.cancelMetadataScan() } }
        .onDisappear { library.cancelMetadataScan() }
    }

    private func collectionRow(name: String, detail: String, track: MediaTrack?) -> some View {
        HStack(spacing: 12) {
            CoverArt(track: track, radius: 10).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 5) {
                Text(name).font(.headline).lineLimit(2)
                Text(detail).font(.caption).foregroundStyle(RitimTheme.muted).lineLimit(2)
            }
        }.padding(.vertical, 3)
    }
}

private struct MediaCollectionView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackStore
    let title: String
    let artistID: String?
    let albumID: String?
    private var tracks: [MediaTrack] {
        if let artistID { return MediaLibraryGrouping.artists(library.tracks).first { $0.id == artistID }?.tracks ?? [] }
        return MediaLibraryGrouping.albums(library.tracks).first { $0.id == albumID }?.tracks ?? []
    }

    var body: some View {
        List {
            if let first = tracks.first {
                Button { playback.play(first, in: tracks) } label: { Label("Tümünü çal", systemImage: "play.fill") }
            }
            ForEach(tracks) { TrackRow(track: $0, context: tracks) }
        }
        .scrollContentBackground(.hidden).background(RitimTheme.background)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}
