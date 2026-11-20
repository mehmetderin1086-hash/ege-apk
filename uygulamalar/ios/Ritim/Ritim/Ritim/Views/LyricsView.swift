import SwiftUI
import UniformTypeIdentifiers

struct LyricsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var lyrics: LyricsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var followsPlayback = true
    @State private var plainMode = false
    @State private var timingExpanded = false
    @State private var isVisible = false
    @State private var editingTrack: MediaTrack?
    @State private var searchingTrack: MediaTrack?
    @State private var importingTrack: MediaTrack?
    @State private var removingTrack: MediaTrack?
    @State private var showImporter = false
    @State private var localError: String?
    @State private var displayedTrackID: UUID?

    private struct LoadIdentity: Equatable {
        let trackID: UUID?
        let foreground: Bool
    }

    private var document: TrackLyrics? {
        // A background track transition must not decode another track's cache
        // on every playback heartbeat while this sheet is out of sight.
        guard scenePhase == .active, let track = playback.current else { return nil }
        return lyrics.currentTrackID == track.id ? lyrics.current : lyrics.record(for: track)
    }
    private var activeIndex: Int? {
        guard let document else { return nil }
        return document.lines.lastIndex { $0.time + document.offset <= playback.elapsed }
    }
    private var mayFollow: Bool {
        isVisible && scenePhase == .active && followsPlayback && !plainMode &&
        editingTrack == nil && searchingTrack == nil && !showImporter
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let track = playback.current {
                    trackHeader(track)
                    if let error = localError ?? lyrics.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20).padding(.bottom, 12).accessibilityIdentifier("lyrics.error")
                    }
                    if let document {
                        if document.isInstrumental {
                            emptyState(title: "Enstrümantal parça", detail: "Bu kayıt sözsüz olarak işaretlenmiş. Başka bir sürüm için eşleşme arayabilir veya kendi sözlerini ekleyebilirsin.", track: track)
                        } else {
                            if !document.lines.isEmpty {
                                Picker("Söz görünümü", selection: $plainMode) {
                                    Text("Zamanlı").tag(false)
                                    Text("Düz metin").tag(true)
                                }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.bottom, 12)
                                    .accessibilityIdentifier("lyrics.mode")
                            }
                            if document.lines.isEmpty || plainMode {
                                ScrollView {
                                    Text(document.plainText).font(.title3).lineSpacing(9)
                                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                                        .padding(22).accessibilityIdentifier("lyrics.plainText")
                                }
                            } else { timedLyrics(document) }
                        }
                    } else if lyrics.isLoading {
                        VStack(spacing: 14) {
                            ProgressView().tint(RitimTheme.mint)
                            Text("Şarkı sözleri aranıyor…").font(.subheadline).foregroundStyle(RitimTheme.muted)
                            Button("Kendi sözlerimi ekle") { editingTrack = track }.accessibilityIdentifier("lyrics.add")
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        emptyState(title: "Şarkı sözleri henüz yok", detail: lyrics.statusMessage ?? "Bir eşleşme ara veya LRC / TXT dosyasından söz ekle. Zaman bilgisi olmayan sözler düz metin olarak gösterilir.", track: track)
                    }
                } else {
                    EmptyLibrary(title: "Bir parça seç", message: "Şarkı sözlerini görmek için kitaplığından bir parça aç.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(RitimTheme.background)
            .safeAreaInset(edge: .bottom, spacing: 0) { if playback.current != nil { playbackFooter } }
            .navigationTitle("Şarkı sözleri").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }.accessibilityIdentifier("lyrics.close")
                }
                ToolbarItem(placement: .primaryAction) {
                    if let track = playback.current {
                        Menu {
                            Button("Sözleri düzenle", systemImage: "square.and.pencil") { editingTrack = track }
                                .accessibilityIdentifier("lyrics.edit")
                            Button("LRC / TXT içe aktar", systemImage: "doc.badge.plus") { importingTrack = track; showImporter = true }
                                .accessibilityIdentifier("lyrics.import")
                            Button("Eşleşme ara", systemImage: "magnifyingglass") { searchingTrack = track }
                                .accessibilityIdentifier("lyrics.search")
                            Button("Otomatik eşleşmeyi yenile", systemImage: "arrow.clockwise") {
                                Task { await lyrics.load(for: track, fileURL: library.url(for: track), refresh: true) }
                            }.disabled(lyrics.isLoading).accessibilityIdentifier("lyrics.refresh")
                            if document?.hasUserEdits == true {
                                Button("Eklediğim sözleri kaldır", systemImage: "trash", role: .destructive) { removingTrack = track }
                                    .accessibilityIdentifier("lyrics.remove")
                            }
                        } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                            .accessibilityLabel("Şarkı sözü seçenekleri").accessibilityIdentifier("lyrics.options")
                    }
                }
            }
        }
        .preferredColorScheme(.dark).tint(RitimTheme.mint)
        .task(id: LoadIdentity(trackID: playback.current?.id, foreground: scenePhase == .active)) {
            // Cancelling on background also cancels the store's metadata/network
            // task. The next foreground appearance can use the persisted cache.
            guard scenePhase == .active else { return }
            if displayedTrackID != playback.current?.id {
                followsPlayback = true; plainMode = false; localError = nil
                displayedTrackID = playback.current?.id
            }
            if let track = playback.current { await lyrics.load(for: track, fileURL: library.url(for: track)) }
        }
        .onAppear { isVisible = true }.onDisappear { isVisible = false }
        .sheet(item: $editingTrack) { track in LyricsEditor(track: track).environmentObject(lyrics) }
        .sheet(item: $searchingTrack) { track in LyricsSearchView(track: track).environmentObject(lyrics) }
        .confirmationDialog("Eklediğin sözler kaldırılsın mı?", isPresented: Binding(get: { removingTrack != nil }, set: { if !$0 { removingTrack = nil } }), titleVisibility: .visible) {
            if let track = removingTrack {
                Button("Bu parçanın sözlerini kaldır", role: .destructive) {
                    do { try lyrics.removeUserLyrics(for: track); localError = nil }
                    catch { localError = error.localizedDescription }
                    removingTrack = nil
                }.accessibilityIdentifier("lyrics.remove.confirm")
            }
        } message: {
            if let track = removingTrack { Text("“\(track.title)” için eklediğin sözler ve zamanlama ayarı kaldırılır. Varsa kayıtlı özgün eşleşmeye dönülür.") }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText, UTType(filenameExtension: "lrc") ?? .data]) { result in
            guard let track = importingTrack else { return }
            defer { importingTrack = nil }
            do {
                let url = try result.get()
                guard ["lrc", "txt"].contains(url.pathExtension.lowercased()) else {
                    throw RitimError.message("LRC veya TXT uzantılı bir söz dosyası seç.")
                }
                try lyrics.importLyrics(from: url, for: track)
                localError = nil
            } catch { localError = error.localizedDescription }
        }
    }

    private func trackHeader(_ track: MediaTrack) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(track.title).font(.headline).lineLimit(2).accessibilityIdentifier("lyrics.track")
            Text(track.artist).font(.caption).foregroundStyle(RitimTheme.muted).lineLimit(1)
            if let document {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { source(document); offlineLabel }
                    VStack(alignment: .leading, spacing: 5) { source(document); offlineLabel }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 14)
    }

    @ViewBuilder private func source(_ document: TrackLyrics) -> some View {
        if let address = document.sourceURL, let url = URL(string: address), url.scheme == "https" {
            Link(document.sourceName, destination: url).font(.caption).accessibilityIdentifier("lyrics.source")
        } else {
            Text(document.sourceName).font(.caption).foregroundStyle(RitimTheme.lavender).accessibilityIdentifier("lyrics.source")
        }
    }

    private var offlineLabel: some View {
        Label("Cihazında kayıtlı", systemImage: "checkmark.circle")
            .font(.caption2).foregroundStyle(RitimTheme.muted).accessibilityIdentifier("lyrics.offline")
    }

    private func timedLyrics(_ document: TrackLyrics) -> some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(document.lines.enumerated()), id: \.offset) { index, line in
                        Button {
                            playback.seek(to: max(0, line.time + document.offset))
                        } label: {
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.title2.weight(activeIndex == index ? .bold : .medium))
                                .foregroundStyle(activeIndex == index ? RitimTheme.mint : RitimTheme.muted)
                                .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 13).padding(.horizontal, 16)
                                .background(activeIndex == index ? RitimTheme.mint.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 14))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).id(index)
                            .accessibilityIdentifier("lyrics.line.\(index)")
                            .accessibilityLabel(line.text.isEmpty ? "Müzik arası" : line.text)
                            .accessibilityValue(activeIndex == index ? "Etkin satır" : "\(timeLabel(line.time + document.offset)) konumuna git")
                            .accessibilityAddTraits(activeIndex == index ? .isSelected : [])
                    }
                }.padding(.horizontal, 6).padding(.vertical, 18)
            }.accessibilityIdentifier("lyrics.synced")
                .onAppear { scrollToActive(reader) }
                .onChange(of: activeIndex) { _, _ in scrollToActive(reader) }
                .onChange(of: mayFollow) { _, _ in scrollToActive(reader) }
        }
    }

    private func scrollToActive(_ reader: ScrollViewProxy) {
        guard mayFollow, let activeIndex else { return }
        // Follow only actual line changes from the player's existing heartbeat.
        // There is no lyrics timer, display link, or background animation loop.
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { reader.scrollTo(activeIndex, anchor: .center) }
    }

    private var playbackFooter: some View {
        VStack(spacing: 12) {
            if let document, !document.lines.isEmpty, !plainMode {
                HStack {
                    Button { followsPlayback.toggle() } label: {
                        Label(followsPlayback ? "Takip açık" : "Takip kapalı", systemImage: followsPlayback ? "text.line.first.and.arrowtriangle.forward" : "hand.draw")
                            .font(.caption.weight(.semibold))
                    }.accessibilityLabel("Satırı takip et").accessibilityValue(followsPlayback ? "Açık" : "Kapalı")
                        .accessibilityIdentifier("lyrics.follow")
                    Spacer(minLength: 12)
                    Text(timeLabel(playback.elapsed)).font(.caption.monospacedDigit()).foregroundStyle(RitimTheme.muted)
                        .accessibilityIdentifier("lyrics.elapsed")
                    playbackButton
                }
                Button { timingExpanded.toggle() } label: {
                    HStack {
                        Text("Zamanlama").font(.caption.weight(.semibold))
                        Spacer()
                        Image(systemName: timingExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold)).accessibilityHidden(true)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel("Zamanlama")
                    .accessibilityValue(timingExpanded ? "Açık" : "Kapalı")
                    .accessibilityHint("Sözlerin zamanlama ayarlarını gösterir veya gizler")
                    .accessibilityIdentifier("lyrics.timing")
                if timingExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 18) {
                            Button { changeOffset(document.offset - 0.5) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
                                .accessibilityLabel("Sözleri yarım saniye erkene al").accessibilityIdentifier("lyrics.offset.decrease")
                                .disabled(document.offset <= -30)
                            Text(document.offset.formatted(.number.precision(.fractionLength(1))) + " sn")
                                .monospacedDigit().frame(maxWidth: .infinity)
                                .accessibilityIdentifier("lyrics.offset.value").accessibilityValue(String(document.offset))
                            Button { changeOffset(document.offset + 0.5) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                                .accessibilityLabel("Sözleri yarım saniye geciktir").accessibilityIdentifier("lyrics.offset.increase")
                                .disabled(document.offset >= 30)
                            Button("Sıfırla") { changeOffset(0) }.font(.caption).accessibilityIdentifier("lyrics.offset.reset")
                        }
                        Text("Artı değer sözleri daha geç gösterir. Bu parça için −30 ile +30 saniye arasında ayarlanır.")
                            .font(.caption2).foregroundStyle(RitimTheme.muted)
                    }
                }
            } else {
                HStack {
                    Text(document?.isInstrumental == true ? "Enstrümantal parça" : (document?.lines.isEmpty == false ? "Düz metin görünümü" : "Zaman bilgisi bulunmuyor"))
                        .font(.caption).foregroundStyle(RitimTheme.muted).frame(maxWidth: .infinity, alignment: .leading)
                    Text(timeLabel(playback.elapsed)).font(.caption.monospacedDigit()).accessibilityIdentifier("lyrics.elapsed")
                    playbackButton
                }
            }
        }.padding(.horizontal, 20).padding(.vertical, 12).background(RitimTheme.surface)
    }

    private var playbackButton: some View {
        Button { playback.togglePlayPause() } label: {
            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").font(.headline)
                .frame(width: 44, height: 44).foregroundStyle(RitimTheme.background).background(RitimTheme.mint, in: Circle())
        }.accessibilityLabel(playback.isPlaying ? "Duraklat" : "Çal").accessibilityIdentifier("lyrics.playPause")
    }

    private func changeOffset(_ value: Double) {
        guard let track = playback.current else { return }
        do { try lyrics.setOffset(min(30, max(-30, value)), for: track); localError = nil }
        catch { localError = error.localizedDescription }
    }

    private func emptyState(title: String, detail: String, track: MediaTrack) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "text.quote").font(.largeTitle).foregroundStyle(RitimTheme.lavender)
                Text(title).font(.title3.bold())
                Text(detail).font(.subheadline).foregroundStyle(RitimTheme.muted).multilineTextAlignment(.center)
                Button("Söz ekle") { editingTrack = track }.buttonStyle(.borderedProminent).accessibilityIdentifier("lyrics.add")
                Button("Eşleşme ara") { searchingTrack = track }.accessibilityIdentifier("lyrics.search.empty")
                Button("LRC / TXT içe aktar") { importingTrack = track; showImporter = true }.accessibilityIdentifier("lyrics.import.empty")
            }.frame(maxWidth: .infinity).padding(28)
        }.frame(maxHeight: .infinity)
    }
}

private struct LyricsEditor: View {
    @EnvironmentObject private var lyrics: LyricsStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    @FocusState private var focused: Bool
    let track: MediaTrack

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(track.title).font(.headline)
                    Text("Düz metin veya [00:12.50] biçiminde zamanlı LRC satırları yapıştır. Eklediğin sözler bu cihazda saklanır.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $text).frame(minHeight: 250).focused($focused)
                        .accessibilityLabel("Şarkı sözü metni").accessibilityIdentifier("lyrics.editor.text")
                    if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                }
            }.navigationTitle("Söz ekle / düzenle").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Kaydet") {
                            do { try lyrics.saveUserLyrics(text, for: track); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("lyrics.editor.save")
                    }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Bitti") { focused = false } }
                }
                .onAppear { text = lyrics.record(for: track)?.rawText ?? "" }
        }.preferredColorScheme(.dark).tint(RitimTheme.mint)
    }
}

private struct LyricsSearchView: View {
    @EnvironmentObject private var lyrics: LyricsStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var choosing = false
    @State private var searched = false
    let track: MediaTrack

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Sanatçı ve şarkı adı", text: $query).autocorrectionDisabled()
                        .accessibilityIdentifier("lyrics.search.query")
                    Button {
                        searched = true
                        Task { await lyrics.search(query: query) }
                    } label: {
                        HStack { Text("Ara"); Spacer(); if lyrics.isSearching { ProgressView() } }
                    }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || lyrics.isSearching || choosing)
                        .accessibilityIdentifier("lyrics.search.submit")
                }
                if let error = lyrics.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
                if searched, let status = lyrics.statusMessage {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                if searched && !lyrics.isSearching && lyrics.candidates.isEmpty && lyrics.statusMessage == nil { Text("Eşleşme bulunamadı. Sanatçı ve şarkı adını değiştirerek yeniden ara.").font(.subheadline) }
                ForEach(searched && !lyrics.isSearching ? lyrics.candidates : []) { candidate in
                    Button {
                        choosing = true
                        Task {
                            await lyrics.choose(candidate, for: track)
                            choosing = false
                            if lyrics.errorMessage == nil && lyrics.currentTrackID == track.id && lyrics.current != nil { dismiss() }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(candidate.title).font(.headline).foregroundStyle(.primary)
                            Text(candidate.artist).font(.subheadline).foregroundStyle(.secondary)
                            if !candidate.album.isEmpty { Text(candidate.album).font(.caption).foregroundStyle(.secondary) }
                            Text("\(timeLabel(candidate.duration)) · \(candidate.isInstrumental ? "Enstrümantal" : (candidate.hasSynced ? "Zamanlı sözler" : "Düz metin"))")
                                .font(.caption).foregroundStyle(RitimTheme.lavender)
                        }.padding(.vertical, 5)
                    }.disabled(choosing || lyrics.isSearching).accessibilityIdentifier("lyrics.candidate.\(candidate.id)")
                }
            }.navigationTitle("Söz eşleşmesi ara").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
                .onAppear { query = "\(track.artist) \(track.title)" }
        }.preferredColorScheme(.dark).tint(RitimTheme.mint)
    }
}
