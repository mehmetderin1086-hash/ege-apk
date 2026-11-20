import SwiftUI

/// Search box for the Downloads tab: the user's words plus the model's similar searches.
struct YouTubeDiscoverCard: View {
    @EnvironmentObject private var assistant: AIAssistantStore
    @EnvironmentObject private var library: LibraryStore
    @State private var query = ""
    @AppStorage("discover.similar") private var includeSimilar = true
    @FocusState private var focused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle.magnifyingglass").font(.title3).foregroundStyle(RitimTheme.mint)
                    .symbolEffect(.pulse, options: .repeating, isActive: assistant.isExpandingSearch)
                VStack(alignment: .leading, spacing: 2) {
                    Text("YouTube’da ara").font(.headline)
                    Text("Şarkı, sanatçı veya tür yaz; yapay zekâ benzerlerini de bulsun.")
                        .font(.caption).foregroundStyle(RitimTheme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(RitimTheme.muted)
                TextField("örn. Barış Manço, lo-fi çalışma, 90'lar pop", text: $query)
                    .font(.subheadline).submitLabel(.search).focused($focused)
                    .onSubmit(start).accessibilityIdentifier("discover.query")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(RitimTheme.muted) }
                        .accessibilityLabel("Aramayı temizle")
                }
            }.padding(14).background(RitimTheme.background, in: RoundedRectangle(cornerRadius: 12))
            Toggle(isOn: $includeSimilar) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Benzerlerini de bul").font(.subheadline.weight(.semibold))
                    Text(assistant.isReady ? "Yapay zekâ \(assistant.selectedModel?.name ?? "model") ile 3 benzer arama ekler."
                                           : "Asistan bağlanınca benzer aramalar eklenir; şimdilik yalnız senin araman yapılır.")
                        .font(.caption2).foregroundStyle(RitimTheme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }.tint(RitimTheme.mint).accessibilityIdentifier("discover.similar")
            Button(action: start) {
                Label(assistant.isSearching ? "Aranıyor…" : "Ara", systemImage: includeSimilar && assistant.isReady ? "sparkles" : "magnifyingglass")
                    .font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundStyle(RitimTheme.background).background(RitimTheme.mint, in: Capsule())
            }.buttonStyle(.plain).disabled(trimmed.isEmpty || assistant.isSearching).opacity(trimmed.isEmpty ? 0.45 : 1)
                .accessibilityIdentifier("discover.go")
            if assistant.searchQuery != nil || assistant.isSearching {
                YouTubeDiscoverResults(idPrefix: "discover", playlistTitle: "Keşif · \(assistant.searchQuery ?? trimmed)")
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18).background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 22))
        .aiGlow(radius: 22, active: assistant.isExpandingSearch)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: assistant.searchQuery)
        .accessibilityElement(children: .contain).accessibilityIdentifier("discover.card")
    }

    private func start() {
        guard !trimmed.isEmpty, !assistant.isSearching else { return }
        focused = false
        let text = trimmed
        Task {
            if includeSimilar { await assistant.discover(text, library: library) } else { await assistant.search(text) }
        }
    }
}

/// Results shared by the Downloads tab and the assistant: query chips, selectable rows, format and download.
struct YouTubeDiscoverResults: View {
    @EnvironmentObject private var assistant: AIAssistantStore
    @EnvironmentObject private var downloads: DownloadStore
    @EnvironmentObject private var library: LibraryStore
    let idPrefix: String
    var playlistTitle = "Yapay zekâ keşfi"
    @State private var selected = Set<String>()
    @State private var filter: String?
    @State private var format = DownloadFormat.mp3
    @State private var notice: String?
    @State private var page = 0
    private static let pageSize = 10

    private var pageCount: Int { max(1, (visible.count + Self.pageSize - 1) / Self.pageSize) }
    private var pageItems: ArraySlice<PlaylistItem> {
        let start = min(page * Self.pageSize, visible.count)
        return visible[start..<min(start + Self.pageSize, visible.count)]
    }

    private var visible: [PlaylistItem] {
        guard let filter else { return assistant.searchResults }
        return assistant.searchResults.filter { assistant.searchSources[$0.id] == filter }
    }
    private var selectedItems: [PlaylistItem] { assistant.searchResults.filter { selected.contains($0.id) } }
    private var libraryVideoIDs: Set<String> {
        Set(library.tracks.compactMap { track in
            track.sourceURL.flatMap { try? MediaURLPolicy.canonicalInput($0) }
                .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if assistant.searchQueries.count > 1 || assistant.isExpandingSearch { queryChips }
            if assistant.isExpandingSearch {
                HStack(spacing: 8) {
                    TypingDots()
                    Text("Yapay zekâ benzer aramaları hazırlıyor…").font(.caption).foregroundStyle(RitimTheme.muted)
                }.accessibilityIdentifier("\(idPrefix).expanding")
            }
            if let note = assistant.searchNote {
                Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("\(idPrefix).note")
            }
            if assistant.searchResults.isEmpty {
                if assistant.isSearching {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 10).fill(RitimTheme.elevated).frame(height: 58).shimmer()
                    }
                } else {
                    Text(assistant.errorMessage ?? "Sonuç bulunamadı. Başka bir ifade dene.")
                        .font(.subheadline).foregroundStyle(RitimTheme.muted).accessibilityIdentifier("\(idPrefix).empty")
                }
            } else {
                HStack {
                    Text("\(selectedItems.count) / \(assistant.searchResults.count) seçili").font(.caption).monospacedDigit()
                        .foregroundStyle(RitimTheme.muted).accessibilityIdentifier("\(idPrefix).selectionCount")
                    Spacer()
                    let allVisible = Set(visible.map(\.id))
                    Button(allVisible.isSubset(of: selected) ? "Seçimi kaldır" : "Tümünü seç") {
                        if allVisible.isSubset(of: selected) { selected.subtract(allVisible) } else { selected.formUnion(allVisible) }
                    }.font(.caption.bold()).foregroundStyle(RitimTheme.mint).accessibilityIdentifier("\(idPrefix).selectAll")
                }
                let owned = libraryVideoIDs
                ForEach(Array(pageItems.enumerated()), id: \.element.id) { index, item in
                    YouTubeResultRow(item: item, selected: selected.contains(item.id), inLibrary: owned.contains(item.id),
                                     viaAI: assistant.searchSources[item.id].map { $0 != assistant.searchQuery } ?? false) {
                        if !selected.insert(item.id).inserted { selected.remove(item.id) }
                    }
                    .accessibilityIdentifier("\(idPrefix).result.\(index)")
                    .staggeredAppear(min(index, 8))
                }
                pager
                if assistant.canFindMore {
                    Button { Task { await assistant.findMore() } } label: {
                        Label("Daha fazla bul", systemImage: "plus.magnifyingglass").font(.subheadline.bold())
                            .frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(RitimTheme.mint)
                            .background(RitimTheme.mint.opacity(0.12), in: Capsule())
                    }.buttonStyle(.plain).accessibilityIdentifier("\(idPrefix).more")
                } else if assistant.isSearching {
                    HStack(spacing: 8) { TypingDots(); Text("Aranıyor…").font(.caption).foregroundStyle(RitimTheme.muted) }
                }
                Picker("İndirme biçimi", selection: $format) {
                    Text("MP3 · Ses").tag(DownloadFormat.mp3)
                    Text("MP4 · Video").tag(DownloadFormat.mp4)
                }.pickerStyle(.segmented).accessibilityIdentifier("\(idPrefix).download.format")
                DownloadQualityPicker(format: format, identifier: "\(idPrefix).download.quality")
                Button(action: enqueue) {
                    Label("\(selectedItems.count) parçayı \(format.rawValue.uppercased()) indir", systemImage: "arrow.down.circle.fill")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 46)
                        .foregroundStyle(RitimTheme.background).background(RitimTheme.mint, in: Capsule())
                }.buttonStyle(.plain).disabled(selectedItems.isEmpty).opacity(selectedItems.isEmpty ? 0.45 : 1)
                    .accessibilityIdentifier("\(idPrefix).download.selected")
                    .sensoryFeedback(.success, trigger: notice)
                Text("Seçtiklerin indirme sırasına eklenir ve “\(playlistTitle)” listesinde toplanır.")
                    .font(.caption2).foregroundStyle(RitimTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
            if let notice {
                Label(notice, systemImage: "arrow.down.circle").font(.caption).foregroundStyle(RitimTheme.mint)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("\(idPrefix).notice")
            }
        }
        .onChange(of: assistant.searchQuery) { _, _ in selected = []; filter = nil; notice = nil; page = 0 }
        .onChange(of: filter) { _, _ in page = 0 }
        .onChange(of: assistant.searchResults.count) { _, _ in page = min(page, pageCount - 1) }
        .onChange(of: assistant.searchResults) { old, results in
            // The user's own query is preselected; the model's similar finds wait for a tap.
            let primary = assistant.searchQuery
            let fresh = results.filter { item in !old.contains { $0.id == item.id } && assistant.searchSources[item.id] == primary }
            selected.formUnion(fresh.prefix(Self.pageSize).map(\.id))
        }
    }

    @ViewBuilder private var pager: some View {
        if pageCount > 1 {
            HStack {
                Button { withAnimation(.easeInOut(duration: 0.2)) { page -= 1 } } label: {
                    Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44)
                }.disabled(page == 0).accessibilityLabel("Önceki sayfa").accessibilityIdentifier("\(idPrefix).page.prev")
                Spacer()
                Text("Sayfa \(page + 1) / \(pageCount) · \(visible.count) sonuç").font(.caption.monospacedDigit())
                    .foregroundStyle(RitimTheme.muted).accessibilityIdentifier("\(idPrefix).page.label")
                Spacer()
                Button { withAnimation(.easeInOut(duration: 0.2)) { page += 1 } } label: {
                    Image(systemName: "chevron.right").font(.headline).frame(width: 44, height: 44)
                }.disabled(page >= pageCount - 1).accessibilityLabel("Sonraki sayfa").accessibilityIdentifier("\(idPrefix).page.next")
            }.foregroundStyle(RitimTheme.mint)
        }
    }

    private var queryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Tümü", icon: "square.grid.2x2", active: filter == nil) { filter = nil }
                    .accessibilityIdentifier("\(idPrefix).filter.all")
                ForEach(Array(assistant.searchQueries.enumerated()), id: \.offset) { index, query in
                    chip(query, icon: index == 0 ? "magnifyingglass" : "sparkles", active: filter == query) {
                        filter = filter == query ? nil : query
                    }.accessibilityIdentifier("\(idPrefix).filter.\(index)")
                }
                if assistant.isExpandingSearch {
                    Capsule().fill(RitimTheme.elevated).frame(width: 110, height: 32).shimmer()
                }
            }
        }
    }

    private func chip(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.caption.weight(.semibold)).lineLimit(1)
                .padding(.horizontal, 12).frame(height: 32)
                .foregroundStyle(active ? RitimTheme.background : .white)
                .background(active ? RitimTheme.mint : RitimTheme.elevated, in: Capsule())
        }.buttonStyle(.plain)
    }

    private func enqueue() {
        downloads.enqueuePlaylist(items: selectedItems, title: playlistTitle, format: format)
        withAnimation { notice = downloads.errorMessage ?? downloads.bulkNotice ?? "\(selectedItems.count) parça indirme sırasına eklendi." }
        selected = []
    }
}

struct YouTubeResultRow: View {
    let item: PlaylistItem
    let selected: Bool
    let inLibrary: Bool
    let viaAI: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 11) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(item.id)/mqdefault.jpg")) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        RitimTheme.elevated.overlay(Image(systemName: "play.rectangle").foregroundStyle(RitimTheme.muted))
                    }
                    .frame(width: 84, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
                    if let duration = item.duration, duration.isFinite, duration > 0, duration < 86_400 {
                        Text("\(Int(duration) / 60):\(String(format: "%02d", Int(duration) % 60))")
                            .font(.system(size: 9, weight: .bold).monospacedDigit()).padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 3)).padding(3)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
                    HStack(spacing: 6) {
                        if viaAI { Image(systemName: "sparkles").font(.caption2).foregroundStyle(RitimTheme.mint) }
                        Text(item.artist.isEmpty ? "YouTube" : item.artist).font(.caption).foregroundStyle(RitimTheme.muted).lineLimit(1)
                        if inLibrary {
                            Text("Kitaplıkta").font(.caption2.bold()).foregroundStyle(RitimTheme.mint)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(RitimTheme.mint.opacity(0.15), in: Capsule())
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(selected ? RitimTheme.mint : RitimTheme.muted)
                    .contentTransition(.symbolEffect(.replace))
            }.padding(.vertical, 6).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("\(item.title), \(item.artist)\(inLibrary ? ", kitaplıkta" : "")\(viaAI ? ", yapay zekâ önerisi" : "")")
            .accessibilityValue(selected ? "Seçili" : "Seçili değil")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
