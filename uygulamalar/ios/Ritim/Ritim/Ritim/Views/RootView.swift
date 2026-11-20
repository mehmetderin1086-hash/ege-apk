import SwiftUI
import UniformTypeIdentifiers

private enum MainTab: String, CaseIterable {
    case home = "Keşfet", search = "Ara", library = "Kitaplığım", downloads = "İndir", assistant = "Asistan"
    var icon: String {
        switch self { case .home: return "square.grid.2x2.fill"; case .search: return "magnifyingglass"; case .library: return "square.stack.fill"; case .downloads: return "arrow.down.circle.fill"; case .assistant: return "sparkles" }
    }
    var identifier: String {
        switch self { case .home: return "tab.home"; case .search: return "tab.search"; case .library: return "tab.library"; case .downloads: return "tab.downloads"; case .assistant: return "tab.assistant" }
    }
}

struct RootView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var downloads: DownloadStore
    @EnvironmentObject private var assistant: AIAssistantStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var tabNamespace
    @State private var tab: MainTab = .home
    @State private var tabBounce = 0
    @State private var tabShift: CGFloat = 0
    @State private var showPlayer = false
    @State private var showSettings = false
    @State private var showImporter = false
    @State private var importError: String?
    @State private var isImporting = false
    @State private var showError = false
    @State private var presentedError = ""
    private var errorText: String? { importError ?? library.errorMessage ?? playback.errorMessage ?? downloads.errorMessage }

    var body: some View {
        ZStack {
            RitimTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Group {
                    switch tab {
                    case .home: DashboardView(importFiles: { showImporter = true }, openDownloads: { tab = .downloads }, openSettings: { showSettings = true }, openAssistant: { tab = .assistant })
                    case .search: SearchView()
                    case .library: LibraryView(importFiles: { showImporter = true }, openSettings: { showSettings = true })
                    case .downloads: DownloadsView(openSettings: { showSettings = true })
                    case .assistant: AIAssistantView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(tab)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(x: tabShift, y: 6)), removal: .opacity))
                    .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86), value: tab)
                if let current = playback.current, !showPlayer {
                    MiniPlayer(track: current, expand: { showPlayer = true }).padding(.horizontal, 12).padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                HStack(spacing: 0) {
                    ForEach(MainTab.allCases, id: \.self) { item in
                        Button {
                            guard tab != item else { return }
                            tabShift = (MainTab.allCases.firstIndex(of: item) ?? 0) > (MainTab.allCases.firstIndex(of: tab) ?? 0) ? 40 : -40
                            withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.8)) { tab = item }
                            tabBounce += 1
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: item.icon).font(.system(size: 20, weight: .semibold))
                                    .frame(height: 24)
                                    .symbolEffect(.bounce, options: .nonRepeating, value: tab == item ? tabBounce : 0)
                                    .overlay(alignment: .topTrailing) {
                                        if item == .assistant && assistant.dj != nil {
                                            Circle().fill(RitimTheme.mint).frame(width: 7, height: 7).offset(x: 5, y: -3)
                                                .accessibilityHidden(true)
                                        }
                                    }
                                Text(item.rawValue).font(.caption2.weight(.semibold))
                                    .lineLimit(1).minimumScaleFactor(0.75)
                            }.foregroundStyle(tab == item ? RitimTheme.mint : RitimTheme.muted)
                                .dynamicTypeSize(.xSmall ... .xxxLarge)
                                .frame(maxWidth: .infinity).frame(minHeight: 56)
                                .background(alignment: .top) {
                                    if tab == item {
                                        Capsule().fill(RitimTheme.mint).frame(width: 22, height: 3)
                                            .matchedGeometryEffect(id: "tab.indicator", in: tabNamespace)
                                            .shadow(color: RitimTheme.mint.opacity(0.6), radius: 6)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier(item.identifier)
                            .accessibilityAddTraits(tab == item ? .isSelected : [])
                    }
                }.padding(.top, 2).background(RitimTheme.background)
                    .sensoryFeedback(.selection, trigger: tab)
            }
            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86), value: playback.current?.id)
            .accessibilityElement(children: .contain)
            .accessibilityHidden(showPlayer || showSettings || showImporter)
            if isImporting {
                VStack(spacing: 12) { ProgressView().tint(RitimTheme.mint); Text("Dosyalar ekleniyor…").font(.subheadline) }
                    .padding(24).background(RitimTheme.elevated, in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .preferredColorScheme(.dark).tint(RitimTheme.mint)
        .fullScreenCover(isPresented: $showPlayer) { FullPlayerView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onChange(of: tab) { _, value in theme.lastTab = value.rawValue }
        .onAppear {
            // A theme change rebuilds this view; return to the same tab and settings sheet.
            guard let resume = theme.resume else { return }
            theme.resume = nil
            tab = MainTab(rawValue: resume.tab) ?? .home
            showSettings = resume.settings
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio, .movie], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task { isImporting = true; await library.importFiles(urls); isImporting = false }
            case .failure(let error): importError = error.localizedDescription
            }
        }
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                presentErrorIfNeeded(errorText)
            }
        }
        .onChange(of: errorText) { _, message in
            presentErrorIfNeeded(message)
        }
        .alert("İşlem tamamlanamadı", isPresented: $showError) {
            Button("Tamam") {
                Task { @MainActor in clearErrors() }
            }
        } message: { Text(presentedError) }
    }

    private func clearErrors() {
        importError = nil; library.errorMessage = nil; playback.errorMessage = nil; downloads.errorMessage = nil
    }

    private func presentErrorIfNeeded(_ message: String?) {
        guard let message else { return }
        presentedError = message
        showError = true
    }
}

private struct SearchView: View {
    @EnvironmentObject private var library: LibraryStore
    @SceneStorage("ritim.search.query") private var query = ""
    @SceneStorage("ritim.search.scope") private var scope = "Tümü"
    @State private var matchingArtists: [MediaArtistGroup] = []
    @State private var matchingAlbums: [MediaAlbumGroup] = []
    @State private var matchingLists: [MediaPlaylist] = []
    @State private var selectedList: MediaPlaylist?
    private func refreshGroups() {
        let key = LibrarySearch.key(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !key.isEmpty else { matchingArtists = []; matchingAlbums = []; matchingLists = []; return }
        matchingArtists = MediaLibraryGrouping.artists(library.tracks).filter { LibrarySearch.key($0.name).contains(key) }
        matchingAlbums = MediaLibraryGrouping.albums(library.tracks).filter { LibrarySearch.key($0.name).contains(key) }
        matchingLists = library.playlists.filter { LibrarySearch.key($0.name).contains(key) }
    }
    private var results: [MediaTrack] {
        library.tracks.filter {
            (scope == "Tümü" || (scope == "Müzik" ? $0.kind == .audio : $0.kind == .video)) &&
            (LibrarySearch.matches($0, query: query))
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Bir ses ara.").font(.largeTitle.bold()).padding(.top, 12)
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(RitimTheme.muted)
                    TextField("Parça, sanatçı veya albüm", text: $query).autocorrectionDisabled().submitLabel(.search)
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(RitimTheme.muted) }.accessibilityLabel("Aramayı temizle") }
                }.padding(16).background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                HStack(spacing: 8) {
                    ForEach(["Tümü", "Müzik", "Video"], id: \.self) { item in Button { scope = item } label: { Pill(title: item, selected: scope == item) } }
                }.buttonStyle(.plain)
                if !matchingLists.isEmpty {
                    SectionTitle(title: "Çalma listeleri", caption: "\(matchingLists.count) liste")
                    ForEach(matchingLists) { playlist in
                        Button { selectedList = playlist } label: { Label(playlist.name, systemImage: "music.note.list").frame(maxWidth: .infinity, alignment: .leading) }
                    }
                }
                if !matchingArtists.isEmpty {
                    SectionTitle(title: "Sanatçılar", caption: "\(matchingArtists.count) sanatçı")
                    ForEach(matchingArtists) { artist in
                        DisclosureGroup(artist.name) { LazyVStack { ForEach(artist.tracks) { TrackRow(track: $0, context: artist.tracks) } } }
                    }
                }
                if !matchingAlbums.isEmpty {
                    SectionTitle(title: "Albümler", caption: "\(matchingAlbums.count) albüm")
                    ForEach(matchingAlbums) { album in
                        DisclosureGroup(album.name) { LazyVStack { ForEach(album.tracks) { TrackRow(track: $0, context: album.tracks) } } }
                    }
                }
                SectionTitle(title: query.isEmpty ? "Kütüphaneni keşfet" : "Arama sonuçları", caption: "\(results.count) parça")
                if results.isEmpty { EmptyLibrary(title: "Henüz bir sonuç yok", message: "Başka bir parça veya sanatçı adı dene.", icon: "magnifyingglass") }
                LazyVStack(spacing: 6) { ForEach(results) { TrackRow(track: $0, context: results) } }
            }.padding(.horizontal, 20).padding(.bottom, 24)
        }.scrollDismissesKeyboard(.interactively)
            .onAppear { refreshGroups() }
            .onChange(of: query) { _, _ in refreshGroups() }
            .onChange(of: library.tracks) { _, _ in refreshGroups() }
            .onChange(of: library.playlists) { _, _ in refreshGroups() }
            .sheet(item: $selectedList) { PlaylistView(playlistID: $0.id) }
    }
}

private struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackStore
    let importFiles: () -> Void
    let openSettings: () -> Void
    @SceneStorage("ritim.library.filter") private var filter = "Tümü"
    @SceneStorage("ritim.library.sort") private var sort = "Son eklenen"
    @SceneStorage("ritim.library.query") private var query = ""
    @State private var cachedTracks: [MediaTrack] = []
    @FocusState private var searchFocused: Bool
    @SceneStorage("ritim.library.selecting") private var selecting = false
    @SceneStorage("ritim.library.selectedIDs") private var savedSelection = ""
    @SceneStorage("ritim.library.mediaFilter") private var mediaFilter = "Tümü"
    @SceneStorage("ritim.library.qualityFilter") private var qualityFilter = "Tümü"
    @State private var selectedIDs: Set<UUID> = []
    @State private var showBatchPlaylist = false
    @State private var showBatchMetadata = false
    @State private var batchArtist = ""
    @State private var batchAlbum = ""
    @State private var newPlaylist = false
    @State private var playlistName = ""
    @State private var selectedPlaylist: MediaPlaylist?
    @State private var deletePlaylist: MediaPlaylist?
    @State private var showArtistsAlbums = false
    @State private var showSmartCollections = false
    private func refreshTracks() {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = library.tracks.filter {
            (filter == "Tümü" || (filter == "Beğeniler" ? $0.isFavorite : $0.kind == .video)) &&
            (mediaFilter == "Tümü" || (mediaFilter == "Ses" ? $0.kind == .audio : $0.kind == .video)) &&
            (qualityFilter == "Tümü" || $0.downloadQuality?.rawValue == qualityFilter) &&
            LibrarySearch.matches($0, query: search)
        }
        switch sort {
        case "A–Z": cachedTracks = items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case "En çok çalınan": cachedTracks = items.sorted { $0.playCount > $1.playCount }
        default: cachedTracks = items.sorted { $0.addedAt > $1.addedAt }
        }
    }
    private var tracks: [MediaTrack] { cachedTracks }
    private var selectedTracks: [MediaTrack] {
        let visible = tracks.filter { selectedIDs.contains($0.id) }
        let visibleIDs = Set(visible.map(\.id))
        return visible + library.tracks.filter { selectedIDs.contains($0.id) && !visibleIDs.contains($0.id) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Kitaplığım").font(.largeTitle.bold())
                        Text("\(library.tracks.count) parça • \(library.playlists.count) liste").font(.caption).foregroundStyle(RitimTheme.muted)
                    }
                    Spacer()
                    Menu {
                        Button(action: importFiles) { Label("Dosya ekle", systemImage: "square.and.arrow.down") }
                        Button { playlistName = ""; newPlaylist = true } label: { Label("Yeni çalma listesi", systemImage: "text.badge.plus") }
                        Button(action: openSettings) { Label("Ayarlar", systemImage: "gearshape") }
                    } label: {
                        Image(systemName: "plus").font(.title2).frame(width: 44, height: 44).foregroundStyle(RitimTheme.mint)
                    }.accessibilityLabel("Kütüphaneye ekle")
                }
                .padding(18)
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [RitimTheme.palettes[0][0].opacity(0.8), RitimTheme.palettes[0][1].opacity(0.38), RitimTheme.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "music.note.list").font(.system(size: 62, weight: .bold))
                                .foregroundStyle(.white.opacity(0.08)).padding(12).accessibilityHidden(true)
                        }
                }.padding(.top, 12)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(RitimTheme.mint)
                    TextField("Parça, sanatçı veya albüm ara", text: $query)
                        .focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }
                        .accessibilityIdentifier("library.search")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .accessibilityLabel("Aramayı temizle")
                    }
                }.padding(14).background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                HStack(spacing: 10) {
                    Button { showArtistsAlbums = true } label: {
                        Label("Albüm / Sanatçı", systemImage: "square.stack").font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    }.accessibilityIdentifier("library.artistsAlbums")
                    Button { showSmartCollections = true } label: {
                        Label("Sana özel", systemImage: "sparkles").font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    }.accessibilityIdentifier("library.smartCollections")
                }.buttonStyle(.plain).foregroundStyle(RitimTheme.mint)
                HStack {
                    Picker("Tür", selection: $mediaFilter) {
                        ForEach(["Tümü", "Ses", "Video"], id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Kalite", selection: $qualityFilter) {
                        Text("Tüm kaliteler").tag("Tümü")
                        ForEach(DownloadQuality.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }.pickerStyle(.menu)
                if !library.playlists.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(library.playlists.sorted { ($0.isPinned ?? false) != ($1.isPinned ?? false) ? ($0.isPinned ?? false) : $0.createdAt > $1.createdAt }) { playlist in
                                Button { selectedPlaylist = playlist } label: {
                                    PlaylistCard(playlist: playlist, tracks: library.tracks(in: playlist))
                                }.buttonStyle(.plain).accessibilityLabel(playlist.name)
                                    .accessibilityValue("\(library.tracks(in: playlist).count) parça")
                                    .accessibilityIdentifier("playlist.card").contextMenu {
                                    Button { library.togglePinned(playlist) } label: { Label(playlist.isPinned == true ? "Sabitlemeyi kaldır" : "Sabitle", systemImage: "pin") }
                                    Button(role: .destructive) { deletePlaylist = playlist } label: { Label("Listeyi sil", systemImage: "trash") }
                                }
                            }
                        }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["Tümü", "Beğeniler", "Videolar"], id: \.self) { item in
                            Button { filter = item } label: { Pill(title: item, icon: item == "Beğeniler" ? "heart.fill" : nil, selected: filter == item) }
                        }
                    }.buttonStyle(.plain)
                }
                HStack {
                    Menu {
                        ForEach(["Son eklenen", "A–Z", "En çok çalınan"], id: \.self) { option in Button(option) { sort = option } }
                    } label: { Label(sort, systemImage: "arrow.up.arrow.down").font(.caption).foregroundStyle(RitimTheme.muted) }
                    Spacer()
                    Button(selecting ? "Bitti" : "Seç") {
                        selecting.toggle()
                        if !selecting { selectedIDs.removeAll() }
                    }.accessibilityIdentifier("library.select")
                    Button { if let first = tracks.randomElement() { playback.shuffleEnabled = true; playback.play(first, in: tracks) } } label: {
                        Label("Karışık çal", systemImage: "shuffle").font(.caption.bold())
                    }.disabled(tracks.isEmpty)
                }
                if selecting {
                    HStack {
                        Button("Görünenleri seç") { selectedIDs.formUnion(tracks.map(\.id)) }
                            .disabled(tracks.isEmpty)
                        Spacer()
                        Text("\(selectedTracks.count) seçili").foregroundStyle(RitimTheme.muted)
                        Button("Temizle") { selectedIDs.removeAll() }.disabled(selectedIDs.isEmpty)
                    }.font(.caption.weight(.semibold))
                    HStack(spacing: 10) {
                        Button { showBatchPlaylist = true } label: { Label("Listeye ekle", systemImage: "text.badge.plus").frame(maxWidth: .infinity) }
                            .accessibilityIdentifier("library.batch.playlist")
                        Button {
                            let ordered = selectedTracks
                            if let first = ordered.first { playback.play(first, in: ordered) }
                            selecting = false; selectedIDs.removeAll()
                        } label: { Label("Seçilenleri çal", systemImage: "play.fill").frame(maxWidth: .infinity) }
                            .accessibilityIdentifier("library.batch.play")
                    }.buttonStyle(.bordered).disabled(selectedTracks.isEmpty)
                    HStack {
                        Button("Beğenilere ekle", systemImage: "heart") { library.setFavorites(selectedIDs, value: true) }
                        Button("Beğenilerden çıkar", systemImage: "heart.slash") { library.setFavorites(selectedIDs, value: false) }
                        Button("Bilgileri düzenle", systemImage: "pencil") { batchArtist = ""; batchAlbum = ""; showBatchMetadata = true }
                    }.font(.caption).buttonStyle(.bordered).disabled(selectedTracks.isEmpty)
                }
                if tracks.isEmpty {
                    EmptyLibrary(title: !query.isEmpty ? "Sonuç bulunamadı" : (filter == "Beğeniler" ? "Sevdiklerin burada" : "Yeni seslere yer var"), message: !query.isEmpty ? "Başka bir parça, sanatçı veya albüm adı dene." : (filter == "Beğeniler" ? "Bir parçanın kalbine dokun; burada buluşalım." : "Dosyalar uygulamasından müzik veya video ekle."))
                    if query.isEmpty && library.tracks.isEmpty { Button(action: importFiles) { Label("Dosya ekle", systemImage: "plus").frame(maxWidth: .infinity).padding(16) }.buttonStyle(.bordered).accessibilityIdentifier("import.files") }
                }
                LazyVStack(spacing: 6) {
                    ForEach(tracks) { track in
                        if selecting {
                            Button {
                                if selectedIDs.contains(track.id) { selectedIDs.remove(track.id) } else { selectedIDs.insert(track.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedIDs.contains(track.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedIDs.contains(track.id) ? RitimTheme.mint : RitimTheme.muted)
                                    CoverArt(track: track, radius: 10).frame(width: 50, height: 50)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(track.title).foregroundStyle(.white).lineLimit(1)
                                        Text(track.subtitle).font(.caption).foregroundStyle(RitimTheme.muted).lineLimit(1)
                                    }
                                    Spacer()
                                }.contentShape(Rectangle()).padding(.vertical, 4)
                            }.buttonStyle(.plain).accessibilityLabel(track.title)
                                .accessibilityValue(selectedIDs.contains(track.id) ? "Seçili" : "Seçili değil")
                                .accessibilityIdentifier("library.selection.\(track.id.uuidString)")
                        } else { TrackRow(track: track, context: tracks) }
                    }
                }
            }.padding(.horizontal, 20).padding(.bottom, 24)
        }
        .alert("Yeni çalma listesi", isPresented: $newPlaylist) {
            TextField("Liste adı", text: $playlistName)
            Button("Oluştur") { library.createPlaylist(name: playlistName) }
            Button("Vazgeç", role: .cancel) {}
        }
        .confirmationDialog("Çalma listesi silinsin mi? Parçalar kütüphanende kalır.", isPresented: Binding(get: { deletePlaylist != nil }, set: { if !$0 { deletePlaylist = nil } }), titleVisibility: .visible) {
            Button("Listeyi sil", role: .destructive) { if let playlist = deletePlaylist { library.deletePlaylist(playlist) }; deletePlaylist = nil }
        }
        .sheet(item: $selectedPlaylist) { PlaylistView(playlistID: $0.id) }
        .sheet(isPresented: $showArtistsAlbums) { ArtistsAlbumsView() }
        .sheet(isPresented: $showSmartCollections) { SmartCollectionsView() }
        .sheet(isPresented: $showBatchPlaylist) {
            BatchAddToPlaylistView(tracks: selectedTracks) { selecting = false; selectedIDs.removeAll() }
        }
        .alert("Seçilenlerin bilgileri", isPresented: $showBatchMetadata) {
            TextField("Sanatçı (boşsa korunur)", text: $batchArtist)
            TextField("Albüm (boşsa korunur)", text: $batchAlbum)
            Button("Vazgeç", role: .cancel) {}
            Button("Kaydet") { library.updateMetadata(selectedIDs, artist: batchArtist, album: batchAlbum) }
        } message: { Text("Boş bıraktığın alanlar ve parça başlıkları korunur.") }
        .onAppear {
            selectedIDs = Set(savedSelection.split(separator: ",").compactMap { UUID(uuidString: String($0)) }).intersection(library.tracks.map(\.id))
            refreshTracks()
        }
        .onChange(of: selectedIDs) { _, value in savedSelection = value.map(\.uuidString).sorted().joined(separator: ",") }
        .onChange(of: library.tracks) { _, _ in refreshTracks() }
        .onChange(of: query) { _, _ in refreshTracks() }
        .onChange(of: filter) { _, _ in refreshTracks() }
        .onChange(of: sort) { _, _ in refreshTracks() }
        .onChange(of: mediaFilter) { _, _ in refreshTracks() }
        .onChange(of: qualityFilter) { _, _ in refreshTracks() }
    }
}

private struct PlaylistView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackStore
    @Environment(\.dismiss) private var dismiss
    let playlistID: UUID
    @State private var editingDetails = false
    @State private var editedName = ""
    @State private var editedDetail = ""
    private var playlist: MediaPlaylist? { library.playlists.first { $0.id == playlistID } }
    var body: some View {
        NavigationStack {
            ScrollView {
                if let playlist {
                    let tracks = library.tracks(in: playlist)
                    VStack(alignment: .leading, spacing: 20) {
                        PlaylistHeader(playlist: playlist, tracks: tracks)
                        HStack {
                            Button("Bilgileri düzenle", systemImage: "pencil") {
                                editedName = playlist.name; editedDetail = playlist.detail ?? ""; editingDetails = true
                            }
                            Menu("Kapak seç", systemImage: "photo") {
                                Button("Otomatik mozaik") { library.setPlaylistCover(playlist, trackID: nil) }
                                ForEach(tracks) { track in Button(track.title) { library.setPlaylistCover(playlist, trackID: track.id) } }
                            }
                        }.font(.caption).buttonStyle(.bordered)

                        if tracks.isEmpty { EmptyLibrary(title: "Bu liste seni bekliyor", message: "Kütüphanedeki bir parçanın seçeneklerinden “Listeye ekle”yi seç.") }
                        ForEach(tracks) { TrackRow(track: $0, context: tracks, playlist: playlist) }
                    }.padding(20)
                }
            }.background(RitimTheme.background).navigationTitle("Çalma listesi").navigationBarTitleDisplayMode(.inline)
                .alert("Liste bilgileri", isPresented: $editingDetails) {
                    TextField("Liste adı", text: $editedName)
                    TextField("Açıklama", text: $editedDetail)
                    Button("Vazgeç", role: .cancel) {}
                    Button("Kaydet") { library.updatePlaylist(playlistID, name: editedName, detail: editedDetail) }
                }

                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
        }.preferredColorScheme(.dark).tint(RitimTheme.mint)
    }
}
