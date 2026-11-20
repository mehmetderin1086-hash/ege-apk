import SwiftUI

struct SmartCollectionsView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(SmartCollection.allCases) { collection in
                        NavigationLink {
                            SmartCollectionDetailView(collection: collection)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: collection.icon).font(.title2).foregroundStyle(RitimTheme.mint).frame(width: 32)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(collection.title).font(.headline)
                                    Text("\(collection.tracks(in: library.tracks).count) parça").font(.caption).foregroundStyle(RitimTheme.muted)
                                }
                            }.padding(.vertical, 8)
                        }.accessibilityIdentifier("smart.\(collection.rawValue)")
                    }
                } footer: { Text("Bu koleksiyonlar kütüphanendeki değişikliklere göre kendiliğinden güncellenir.") }
            }
            .navigationTitle("Sana özel")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
        }.preferredColorScheme(.dark).tint(RitimTheme.mint)
    }
}

private struct SmartCollectionDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackStore
    let collection: SmartCollection
    @State private var showSave = false
    @State private var playlistName = ""
    @State private var saveError: String?
    @State private var saved = false
    private var tracks: [MediaTrack] { collection.tracks(in: library.tracks) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(collection.detail).foregroundStyle(RitimTheme.muted)
                HStack {
                    Button {
                        if let first = tracks.first { playback.shuffleEnabled = false; playback.play(first, in: tracks) }
                    } label: { Label("Çal", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                    Button {
                        if let first = tracks.randomElement() { playback.shuffleEnabled = true; playback.play(first, in: tracks) }
                    } label: { Label("Karıştır", systemImage: "shuffle").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                }.disabled(tracks.isEmpty)
                if tracks.isEmpty {
                    EmptyLibrary(title: "Şimdilik boş", message: collection.detail, icon: collection.icon)
                } else {
                    LazyVStack(spacing: 6) { ForEach(tracks) { TrackRow(track: $0, context: tracks) } }
                }
            }.padding(20)
        }
        .background(RitimTheme.background)
        .navigationTitle(collection.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { playlistName = collection.title; showSave = true } label: { Image(systemName: "text.badge.plus") }
                    .accessibilityLabel("Liste olarak kaydet").disabled(tracks.isEmpty)
            }
        }
        .alert("Liste olarak kaydet", isPresented: $showSave) {
            TextField("Liste adı", text: $playlistName)
            Button("Kaydet") {
                do { _ = try library.createPlaylist(name: playlistName, trackIDs: tracks.map(\.id)); saved = true }
                catch { saveError = error.localizedDescription }
            }.disabled(playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Vazgeç", role: .cancel) {}
        } message: { Text("Şu anki parçalar normal bir çalma listesine kaydedilir.") }
        .alert("Liste kaydedildi", isPresented: $saved) { Button("Tamam", role: .cancel) {} }
        .alert("Liste kaydedilemedi", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("Tamam", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
    }
}
