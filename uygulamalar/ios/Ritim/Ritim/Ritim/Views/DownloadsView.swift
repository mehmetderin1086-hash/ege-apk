import SwiftUI

private enum DownloadInputMode: String, CaseIterable, Identifiable {
    case single = "Tek bağlantı", multiple = "Toplu", playlist = "Oynatma listesi"
    var id: String { rawValue }
}

private enum QueueFilter: String, CaseIterable, Identifiable {
    case all = "Tümü", active = "Etkin", completed = "Biten", failed = "Hata/İptal"
    var id: String { rawValue }
    func includes(_ entry: DownloadEntry) -> Bool {
        switch self {
        case .all: true
        case .active: entry.isActive
        case .completed: entry.status == .completed
        case .failed: entry.status == .failed || entry.status == .cancelled
        }
    }
}

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadStore
    let openSettings: () -> Void
    @State private var mode: DownloadInputMode = .single
    @SceneStorage("ritim.download.url") private var url = ""
    @SceneStorage("ritim.download.links") private var links = ""
    @State private var batchName = ""
    @SceneStorage("ritim.download.playlistURL") private var playlistURL = ""
    @State private var playlistSearch = ""
    @State private var selectedPlaylistIDs = Set<String>()
    @State private var format: DownloadFormat = .mp3
    @State private var filter: QueueFilter = .all
    @State private var selectedBatchID: UUID?
    @State private var confirmCancelAll = false
    @State private var selectingJobs = false
    @State private var selectedJobs = Set<UUID>()
    @State private var confirmCancelSelected = false
    @State private var confirmClearFinished = false
    @SceneStorage("ritim.download.search") private var queueSearch = ""
    @FocusState private var focusedInput: InputField?

    private enum InputField: Hashable { case single, multiple, batch, playlist, search, queue }
    private var activeCount: Int { downloads.entries.filter(\.isActive).count }
    private var nonemptyURL: Bool { !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var pastedLinkCount: Int { links.split(whereSeparator: \.isWhitespace).count }
    private var queueEntries: [DownloadEntry] {
        let query = queueSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return downloads.entries.filter {
            filter.includes($0) && (selectedBatchID == nil || $0.batchID == selectedBatchID) &&
            (query.isEmpty || $0.title.localizedStandardContains(query) || ($0.artist?.localizedStandardContains(query) ?? false) || ($0.batchName?.localizedStandardContains(query) ?? false))
        }
    }
    private var playlistItems: [PlaylistItem] { downloads.playlistPreview?.items ?? [] }
    private var selectedItems: [PlaylistItem] { playlistItems.filter { selectedPlaylistIDs.contains($0.id) } }
    private var matchingPlaylistItems: [PlaylistItem] {
        let query = playlistSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? playlistItems : playlistItems.filter {
            $0.title.localizedStandardContains(query) || $0.artist.localizedStandardContains(query)
        }
    }
    private var batchGroups: [(id: UUID, name: String, total: Int, completed: Int)] {
        var orderedIDs: [UUID] = []
        var groups: [UUID: (name: String, total: Int, completed: Int)] = [:]
        for entry in downloads.entries {
            guard let id = entry.batchID else { continue }
            if groups[id] == nil {
                orderedIDs.append(id)
                groups[id] = (entry.batchName ?? "Toplu indirme", 0, 0)
            }
            groups[id]?.total += 1
            if entry.status == .completed { groups[id]?.completed += 1 }
        }
        return orderedIDs.compactMap { id in groups[id].map { (id, $0.name, $0.total, $0.completed) } }
    }

    @State private var section = "link"
    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                heading
                if !downloads.entries.isEmpty {
                    Button {
                        focusedInput = nil
                        proxy.scrollTo("downloadQueue", anchor: .top)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: downloads.isQueuePaused ? "pause.circle.fill" : "arrow.down.circle.fill")
                                .font(.title2).foregroundStyle(RitimTheme.mint)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(downloads.isQueuePaused ? "İndirme sırası duraklatıldı" : "İndirme sıran")
                                    .font(.subheadline.bold()).foregroundStyle(.white)
                                Text("\(downloads.runningCount) işleniyor · \(downloads.pendingCount) sırada · \(downloads.completedCount) tamamlandı")
                                    .font(.caption).foregroundStyle(RitimTheme.muted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down").foregroundStyle(RitimTheme.muted)
                        }.padding(14).background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain).accessibilityIdentifier("queue.jump")
                }
                Picker("Bölüm", selection: $section) {
                    Text("Bağlantı").tag("link")
                    Text("YouTube’da ara").tag("search")
                }.pickerStyle(.segmented).accessibilityIdentifier("downloads.section")
                if section == "link" {
                    inputCard
                    if let notice = downloads.bulkNotice, !notice.isEmpty {
                        Label(notice, systemImage: "info.circle.fill")
                            .font(.subheadline).foregroundStyle(RitimTheme.mint)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RitimTheme.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityIdentifier("bulk.notice")
                    }
                } else {
                    YouTubeDiscoverCard()
                }
                queueSection.id("downloadQueue")
                Text("Kendi içeriklerini veya indirme iznin olan içerikleri kaydet.")
                    .font(.caption2).foregroundStyle(RitimTheme.muted)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }.padding(.horizontal, 20).padding(.bottom, 24).contentShape(Rectangle())
        }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if focusedInput != nil {
                HStack {
                    Spacer()
                    Button("Bitti") { focusedInput = nil }
                        .font(.subheadline.bold()).padding(.horizontal, 20).frame(minHeight: 44)
                        .accessibilityIdentifier("download.dismissKeyboard")
                }.background(RitimTheme.surface)
            }
        }
        .confirmationDialog("Seçilen indirmeleri iptal et?", isPresented: $confirmCancelSelected) {
            Button("Seçilenleri iptal et", role: .destructive) { downloads.cancelAll(ids: selectedJobs); selectedJobs.removeAll() }
            Button("Vazgeç", role: .cancel) {}
        }
        .confirmationDialog("Bekleyen tüm indirmeler iptal edilsin mi?", isPresented: $confirmCancelAll, titleVisibility: .visible) {
            Button("Tümünü iptal et", role: .destructive) { downloads.cancelAll() }
            Button("Vazgeç", role: .cancel) { }
        } message: {
            Text("Sıradaki ve devam eden \(activeCount) indirme iptal edilir. Kütüphanene eklenen dosyalar korunur.")
        }
        .confirmationDialog("İndirme geçmişi temizlensin mi?", isPresented: $confirmClearFinished, titleVisibility: .visible) {
            Button("Geçmişi temizle", role: .destructive) { downloads.clearFinished() }
            Button("Vazgeç", role: .cancel) { }
        } message: {
            Text("Tamamlanan, hatalı ve iptal edilen kayıtlar kaldırılır. Kütüphanedeki dosyalar ve etkin indirmeler korunur.")
        }
        .onChange(of: downloads.playlistPreview?.items) { _, items in
            selectedPlaylistIDs = Set((items ?? []).map(\.id))
        }
        .onChange(of: downloads.entries.map(\.batchID)) { _, ids in
            if let selectedBatchID, !ids.contains(selectedBatchID) { self.selectedBatchID = nil }
        }
        .onAppear { loadUITestInputIfRequested() }
    }

    private func loadUITestInputIfRequested() {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard environment["RITIM_UI_TEST_MODE"] == "1",
              let value = environment["RITIM_UI_TEST_BULK_LINKS"], let count = Int(value),
              (1...1000).contains(count), links.isEmpty else { return }
        // Only fills the editor. The UI test must pause and enqueue through real controls.
        links = (0..<count).map { "https://www.youtube.com/watch?v=T" + String(format: "%010d", $0) }.joined(separator: "\n")
        #endif
    }

    private var heading: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Yanına al.").font(.largeTitle.bold())
                Text("Bağlantı yapıştır ya da YouTube’da ara.")
                    .font(.subheadline).foregroundStyle(RitimTheme.muted)
            }
            Spacer(minLength: 0)
            Button(action: openSettings) {
                Image(systemName: "gearshape").font(.title3).frame(width: 44, height: 44)
            }.accessibilityLabel("İndirme ayarları").accessibilityIdentifier("downloads.settings")
        }.padding(.top, 12)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("İndirme kaynağı", selection: $mode) {
                ForEach(DownloadInputMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }.pickerStyle(.segmented).accessibilityIdentifier("bulk.mode")
            switch mode {
            case .single: singleInput
            case .multiple: multipleInput
            case .playlist: playlistInput
            }
            Picker("İndirme biçimi", selection: $format) {
                ForEach(DownloadFormat.allCases) { format in Text(format == .mp3 ? "MP3 · Ses" : "MP4 · Video").tag(format) }
            }.pickerStyle(.segmented).accessibilityIdentifier("download.format")
            DownloadQualityPicker(format: format)
            Text("Biçim seçimi YouTube içindir. Doğrudan medya dosyaları özgün biçimiyle kaydedilir.")
                .font(.caption).foregroundStyle(RitimTheme.muted).fixedSize(horizontal: false, vertical: true)
            switch mode {
            case .single:
                primaryButton("İndirmeyi başlat", icon: "arrow.down.to.line", enabled: nonemptyURL, identifier: "download.start") {
                    focusedInput = nil
                    downloads.start(url: url.trimmingCharacters(in: .whitespacesAndNewlines), format: format)
                }
            case .multiple:
                primaryButton("\(pastedLinkCount) bağlantıyı sıraya ekle", icon: "text.badge.plus", enabled: pastedLinkCount > 0, identifier: "bulk.enqueue") {
                    focusedInput = nil
                    downloads.enqueueText(links, format: format, batchName: batchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Toplu indirme" : batchName)
                    filter = .active
                    selectedBatchID = nil
                }
            case .playlist:
                if downloads.playlistPreview?.status == "completed" && !downloads.isResolvingPlaylist {
                    primaryButton("\(selectedItems.count) parçayı \(format.rawValue.uppercased()) indir", icon: "arrow.down.to.line", enabled: !selectedItems.isEmpty, identifier: "playlist.enqueue") {
                        focusedInput = nil
                        downloads.enqueuePlaylist(items: selectedItems, title: downloads.playlistPreview?.title ?? "YouTube listesi", format: format)
                        filter = .active
                        selectedBatchID = nil
                    }
                    Text("İndirilenler aynı adla kütüphanende bir çalma listesinde toplanır.")
                        .font(.caption).foregroundStyle(RitimTheme.muted)
                }
            }
        }.padding(20).background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 22))
    }

    private var singleInput: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("YouTube veya doğrudan medya bağlantısı", systemImage: "link")
                .font(.subheadline.bold()).foregroundStyle(RitimTheme.mint)
            HStack(alignment: .center, spacing: 6) {
                TextField("https://…", text: $url, axis: .vertical)
                    .font(.subheadline).keyboardType(.URL).textContentType(.URL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .lineLimit(1...3).focused($focusedInput, equals: .single).accessibilityIdentifier("download.url")
                if !url.isEmpty {
                    Button { url = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(RitimTheme.muted).frame(width: 30, height: 36)
                    }.accessibilityLabel("Bağlantıyı temizle").accessibilityIdentifier("download.clear")
                }
                PasteButton(payloadType: String.self) { values in if let value = values.first { url = value } }
                    .labelStyle(.iconOnly).buttonBorderShape(.capsule)
            }.padding(14).background(RitimTheme.background, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var multipleInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Yüzlerce bağlantı, tek sıra", systemImage: "square.stack.3d.up")
                .font(.subheadline.bold()).foregroundStyle(RitimTheme.mint)
            Text("Bağlantıları alt alta veya aralarında boşlukla yapıştır. En fazla \(DownloadStore.queueLimit) bekleyen indirme; aynı bağlantı ve biçim tekrar eklenmez.")
                .font(.caption).foregroundStyle(RitimTheme.muted).fixedSize(horizontal: false, vertical: true)
            TextField("Grup adı (isteğe bağlı)", text: $batchName)
                .font(.subheadline).focused($focusedInput, equals: .batch).accessibilityIdentifier("bulk.name")
                .padding(12).background(RitimTheme.background, in: RoundedRectangle(cornerRadius: 12))
            ZStack(alignment: .topLeading) {
                if links.isEmpty {
                    Text("https://www.youtube.com/watch?v=…\nhttps://youtu.be/…\nhttps://…/dosya.mp3")
                        .font(.caption).foregroundStyle(RitimTheme.muted).padding(.horizontal, 12).padding(.top, 15)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                TextEditor(text: $links)
                    .font(.system(.caption, design: .monospaced)).scrollContentBackground(.hidden)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focusedInput, equals: .multiple).padding(6).frame(height: 138)
                    .accessibilityLabel("Toplu indirme bağlantıları").accessibilityIdentifier("bulk.links")
            }.background(RitimTheme.background, in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Text("\(pastedLinkCount) bağlantı").font(.caption).monospacedDigit().foregroundStyle(RitimTheme.muted)
                    .accessibilityIdentifier("bulk.linkCount")
                Spacer()
                if !links.isEmpty {
                    Button("Temizle") { links = "" }.font(.caption).accessibilityIdentifier("bulk.clear")
                }
                PasteButton(payloadType: String.self) { values in
                    let pasted = values.joined(separator: "\n")
                    links = links.isEmpty ? pasted : links + "\n" + pasted
                }.labelStyle(.iconOnly).buttonBorderShape(.capsule).accessibilityLabel("Bağlantıları yapıştır")
            }
        }
    }

    private var playlistInput: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("YouTube oynatma listesini getir", systemImage: "music.note.list")
                .font(.subheadline.bold()).foregroundStyle(RitimTheme.mint)
            Text("Önce listedeki parçaları gör, sonra istediklerini seç. Tarama sırasında müzik veya video indirilmez.")
                .font(.caption).foregroundStyle(RitimTheme.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                TextField("Liste veya video bağlantısı", text: $playlistURL, axis: .vertical)
                    .font(.subheadline).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .lineLimit(1...3).focused($focusedInput, equals: .playlist).accessibilityIdentifier("playlist.url")
                PasteButton(payloadType: String.self) { values in if let value = values.first { playlistURL = value } }
                    .labelStyle(.iconOnly).buttonBorderShape(.capsule)
            }.padding(14).background(RitimTheme.background, in: RoundedRectangle(cornerRadius: 12))
            if downloads.isResolvingPlaylist {
                HStack(spacing: 10) {
                    ProgressView().tint(RitimTheme.mint)
                    Text("Liste taranıyor…").font(.subheadline)
                    Spacer(minLength: 0)
                    Button("İptal et") { downloads.cancelPlaylistResolution() }.font(.subheadline)
                        .accessibilityIdentifier("playlist.cancel")
                }.padding(.vertical, 6)
            } else {
                Button {
                    focusedInput = nil
                    playlistSearch = ""
                    selectedPlaylistIDs.removeAll()
                    Task { await downloads.resolvePlaylist(url: playlistURL) }
                } label: {
                    Label("Listeyi tara", systemImage: "magnifyingglass")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(12)
                        .background(RitimTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).accessibilityIdentifier("playlist.resolve")
                    .disabled(playlistURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let preview = downloads.playlistPreview, !downloads.isResolvingPlaylist {
                Color.clear.frame(height: 0).onAppear {
                    if preview.items.count == 1, selectedPlaylistIDs.isEmpty { selectedPlaylistIDs = [preview.items[0].id] }
                }
                if preview.status == "completed" {
                    playlistPreview(preview)
                } else if preview.status == "failed", let error = preview.error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                } else if preview.status == "cancelled" {
                    Text("Tarama iptal edildi. Yeni bir liste tarayabilirsin.").font(.caption).foregroundStyle(RitimTheme.muted)
                }
            }
        }
    }

    private func playlistPreview(_ preview: PlaylistPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(preview.title.isEmpty ? "YouTube oynatma listesi" : preview.title).font(.headline).accessibilityIdentifier("playlist.title")
                Text("\(preview.items.count) parça · \(selectedItems.count) seçili")
                    .font(.caption).foregroundStyle(RitimTheme.mint).monospacedDigit()
                    .accessibilityIdentifier("playlist.selectionCount")
            }
            if preview.skipped > 0 || preview.truncated {
                Text(previewNote(preview)).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if URLComponents(string: playlistURL)?.queryItems?.first(where: { $0.name == "list" })?.value?.hasPrefix("RD") == true {
                Text("Mix listeleri zamanla değişebilir. Burada son taramada bulunan parçalar gösterilir.")
                    .font(.caption).foregroundStyle(RitimTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(RitimTheme.muted)
                TextField("Listede parça veya sanatçı ara", text: $playlistSearch)
                    .font(.subheadline).focused($focusedInput, equals: .search).accessibilityIdentifier("playlist.search")
                if !playlistSearch.isEmpty {
                    Button { playlistSearch = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(RitimTheme.muted) }
                        .accessibilityLabel("Liste aramasını temizle")
                }
            }.padding(12).background(RitimTheme.background, in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Button("Tümünü seç") { focusedInput = nil; selectedPlaylistIDs = Set(preview.items.map(\.id)) }
                    .accessibilityIdentifier("playlist.selectAll")
                Spacer()
                Button("Seçimi temizle") { focusedInput = nil; selectedPlaylistIDs.removeAll() }
                    .accessibilityIdentifier("playlist.clearSelection")
            }.font(.caption.bold())
            if preview.items.isEmpty {
                Text("Bu listede indirilebilir parça bulunamadı.").font(.subheadline).foregroundStyle(RitimTheme.muted)
            } else if matchingPlaylistItems.isEmpty {
                Text("Aramana uygun parça yok.").font(.subheadline).foregroundStyle(RitimTheme.muted)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(matchingPlaylistItems) { item in
                            PlaylistSelectionRow(item: item, selected: selectedPlaylistIDs.contains(item.id)) {
                                focusedInput = nil
                                if !selectedPlaylistIDs.insert(item.id).inserted { selectedPlaylistIDs.remove(item.id) }
                            }
                            Divider().overlay(RitimTheme.elevated)
                        }
                    }
                }.frame(height: min(330, CGFloat(matchingPlaylistItems.count) * 68))
                    .background(RitimTheme.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("playlist.items")
            }
        }
    }

    private func previewNote(_ preview: PlaylistPreview) -> String {
        var notes: [String] = []
        if preview.skipped > 0 { notes.append("\(preview.skipped) yinelenen veya erişilemeyen kayıt atlandı.") }
        if preview.truncated { notes.append("Uzun listenin tarama sınırına kadar bulunan \(preview.items.count) parçası gösteriliyor.") }
        return notes.joined(separator: " ")
    }

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionTitle(title: "İndirme sıran", caption: activeCount > 0 ? "\(activeCount) / \(DownloadStore.queueLimit) bekleyen" : nil)
                Spacer(minLength: 0)
                if downloads.entries.contains(where: { !$0.isActive }) {
                    Button("Geçmişi temizle") { confirmClearFinished = true }.font(.caption).accessibilityIdentifier("queue.clearFinished")
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 4) {
                    QueueMetric(title: "Sırada", count: downloads.pendingCount, color: RitimTheme.muted, identifier: "queue.pending")
                    QueueMetric(title: "İşleniyor", count: downloads.runningCount, color: RitimTheme.mint, identifier: "queue.running")
                    QueueMetric(title: "Bitti", count: downloads.completedCount, color: RitimTheme.lavender, identifier: "queue.completed")
                    QueueMetric(title: "Hatalı", count: downloads.failedCount, color: .orange, identifier: "queue.failed")
                }
                Button {
                    focusedInput = nil
                    if downloads.isQueuePaused { downloads.resumeQueue() } else { downloads.pauseQueue() }
                } label: {
                    Label(downloads.isQueuePaused ? "Sırayı devam ettir" : "Sırayı duraklat", systemImage: downloads.isQueuePaused ? "play.fill" : "pause.fill")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(13)
                        .background(RitimTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).accessibilityIdentifier(downloads.isQueuePaused ? "queue.resume" : "queue.pause")
                Text(downloads.isQueuePaused
                     ? "Sıra duraklatıldı. Başlamış dosyalar tamamlanır; yeni indirmeler devam ettirmeni bekler."
                     : "Aynı anda en fazla \(downloads.maxConcurrentDownloads) dosya işlenir. Sıran otomatik kaydedilir.")
                    .font(.caption).foregroundStyle(RitimTheme.muted).fixedSize(horizontal: false, vertical: true)
                if downloads.failedCount > 0 || activeCount > 0 {
                    HStack {
                        if downloads.failedCount > 0 {
                            Button { downloads.retryFailed() } label: { Label("Hatalıları yeniden dene", systemImage: "arrow.clockwise") }
                                .accessibilityIdentifier("queue.retryFailed")
                        }
                        Spacer(minLength: 0)
                        if activeCount > 0 {
                            Button("Tümünü iptal et", role: .destructive) { confirmCancelAll = true }
                                .accessibilityIdentifier("queue.cancelAll")
                        }
                    }.font(.caption.bold())
                }
            }.padding(16).background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            if activeCount > 0 || mode != .single {
                Label("Hazırlanmış YouTube indirmeleri arka planda aktarılabilir. Dönüştürmeyi iOS uygun zamanda çalıştırır; bekleyen işler uygulamayı açtığında sürer.", systemImage: "iphone")
                    .font(.caption).foregroundStyle(RitimTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
            if downloads.entries.isEmpty {
                EmptyLibrary(title: "Bir bağlantıyla başlar", message: "Tek bir parça veya yüzlerce bağlantı ekle. Tamamlanan dosyalar otomatik olarak kütüphanene gelir.", icon: "arrow.down.circle")
            } else {
                queueFilters
                HStack {
                    Button(selectingJobs ? "Seçimi bitir" : "İş seç") { selectingJobs.toggle(); selectedJobs.removeAll() }
                    if selectingJobs {
                        Button("Görünenleri seç") { selectedJobs.formUnion(queueEntries.map(\.id)) }
                        Menu("\(selectedJobs.count) iş") {
                            Button("Öncelik ver") { downloads.prioritize(ids: selectedJobs) }
                            Button("Başarısız / iptal edilenleri dene") { downloads.retryFailed(ids: selectedJobs) }
                            Button("Seçilenleri iptal et", role: .destructive) { confirmCancelSelected = true }
                        }.disabled(selectedJobs.isEmpty)
                    }
                }.font(.caption).buttonStyle(.bordered)
                if let id = selectedBatchID, let group = batchGroups.first(where: { $0.id == id }) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(group.name) · \(group.completed) / \(group.total) tamamlandı").font(.caption).foregroundStyle(RitimTheme.muted)
                        ProgressView(value: Double(group.completed), total: Double(max(1, group.total))).tint(RitimTheme.mint)
                    }.accessibilityIdentifier("queue.batchProgress")
                }
                if queueEntries.isEmpty {
                    Text(queueSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Bu görünümde indirme yok." : "Eşleşen indirme bulunamadı.")
                        .font(.subheadline).foregroundStyle(RitimTheme.muted).padding(.vertical, 18)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(queueEntries) { entry in
                            HStack(alignment: .top) {
                                if selectingJobs {
                                    Button {
                                        if selectedJobs.contains(entry.id) { selectedJobs.remove(entry.id) } else { selectedJobs.insert(entry.id) }
                                    } label: { Image(systemName: selectedJobs.contains(entry.id) ? "checkmark.circle.fill" : "circle").frame(width: 44, height: 44) }
                                    .accessibilityLabel("Seç: " + entry.title)
                                    .accessibilityValue(selectedJobs.contains(entry.id) ? "Seçili" : "Seçili değil")
                                }
                                DownloadCard(entry: entry)
                            }
                        }
                    }
                        .accessibilityIdentifier("queue.items")
                }
            }
        }
    }

    private var queueFilters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(RitimTheme.muted)
                TextField("İndirmelerde ara", text: $queueSearch)
                    .focused($focusedInput, equals: .queue).submitLabel(.search)
                    .onSubmit { focusedInput = nil }
                    .accessibilityIdentifier("queue.search")
                if !queueSearch.isEmpty {
                    Button { queueSearch = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("İndirme aramasını temizle")
                }
            }.padding(12).background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            Picker("İndirme durumunu filtrele", selection: $filter) {
                ForEach(QueueFilter.allCases) { filter in Text(filter.rawValue).tag(filter) }
            }.pickerStyle(.segmented).accessibilityIdentifier("queue.filter")
            if !batchGroups.isEmpty {
                Menu {
                    Button("Tüm gruplar") { selectedBatchID = nil }
                    ForEach(batchGroups, id: \.id) { group in
                        Button("\(group.name) · \(group.completed)/\(group.total)") { selectedBatchID = group.id }
                    }
                } label: {
                    HStack {
                        Label(batchGroups.first(where: { $0.id == selectedBatchID })?.name ?? "Tüm gruplar", systemImage: "square.stack").lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.down")
                    }.font(.caption.bold()).padding(12).background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                }.accessibilityIdentifier("queue.group")
            }
        }
    }

    private func primaryButton(_ title: String, icon: String, enabled: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.subheadline.bold()).foregroundStyle(RitimTheme.background)
                .frame(maxWidth: .infinity).padding(16)
                .background(RitimTheme.mint, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.45).accessibilityIdentifier(identifier)
    }
}

struct DownloadQualityPicker: View {
    @EnvironmentObject private var downloads: DownloadStore
    let format: DownloadFormat
    var identifier = "download.quality"

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("İndirme kalitesi").font(.caption.weight(.semibold)).foregroundStyle(RitimTheme.muted)
            Picker("İndirme kalitesi", selection: $downloads.downloadQuality) {
                Text(DownloadQuality.highest.title).tag(DownloadQuality.highest)
                Text(DownloadQuality.standard.title).tag(DownloadQuality.standard)
            }.pickerStyle(.segmented).accessibilityIdentifier(identifier)
            Text(downloads.downloadQuality.detail(for: format))
                .font(.caption.weight(.semibold)).foregroundStyle(RitimTheme.mint)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier + ".detail")
            Text("Kalite kaynakla sınırlıdır; görüntü yapay olarak büyütülmez. Dosya başına en fazla 512 MB.")
                .font(.caption2).foregroundStyle(RitimTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PlaylistSelectionRow: View {
    let item: PlaylistItem
    let selected: Bool
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(selected ? RitimTheme.mint : RitimTheme.muted)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.subheadline).foregroundStyle(.white).lineLimit(1)
                    Text(item.artist.isEmpty ? "YouTube" : item.artist).font(.caption).foregroundStyle(RitimTheme.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let duration = item.duration, duration.isFinite, duration > 0, duration < Double(Int.max) {
                    Text("\(Int(duration) / 60):\(String(format: "%02d", Int(duration) % 60))")
                        .font(.caption).monospacedDigit().foregroundStyle(RitimTheme.muted)
                }
            }.padding(.horizontal, 10).frame(minHeight: 66).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("\(item.title), \(item.artist)")
            .accessibilityValue(selected ? "Seçili" : "Seçili değil")
            .accessibilityIdentifier("playlist.item.\(item.id)")
    }
}

private struct QueueMetric: View {
    let title: String
    let count: Int
    let color: Color
    let identifier: String
    var body: some View {
        VStack(spacing: 4) {
            Text(count.formatted(.number.grouping(.never))).font(.title3.bold()).monospacedDigit().foregroundStyle(color)
                .accessibilityIdentifier(identifier)
            Text(title).font(.caption2).foregroundStyle(RitimTheme.muted)
        }.frame(maxWidth: .infinity)
    }
}

private struct DownloadCard: View {
    @EnvironmentObject private var downloads: DownloadStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playback: PlaybackStore
    let entry: DownloadEntry
    private var track: MediaTrack? { library.tracks.first { $0.id == entry.trackID } }
    private var failed: Bool { entry.status == .failed }
    private var qualityDescription: String {
        guard let source = URL(string: entry.sourceURL), MediaURLPolicy.isYouTube(source) else { return "Özgün dosya" }
        return entry.effectiveQuality.detail(for: entry.format)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: entry.format == .mp3 ? "music.note" : "video.fill")
                    .font(.title3).foregroundStyle(entry.format == .mp3 ? RitimTheme.mint : RitimTheme.lavender)
                    .frame(width: 44, height: 44).background(RitimTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title.isEmpty ? "Medya hazırlanıyor" : entry.title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(2)
                    Text("\(entry.format.rawValue.uppercased()) · \(entry.status.title)").font(.caption).foregroundStyle(failed ? .orange : RitimTheme.muted)
                    Text(entry.resolvedQuality ?? qualityDescription).font(.caption2).foregroundStyle(RitimTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let name = entry.batchName { Text(name).font(.caption2).foregroundStyle(RitimTheme.lavender).lineLimit(1) }
                }
                Spacer(minLength: 0)
                if entry.isActive {
                    Button { downloads.cancel(entry) } label: { Image(systemName: "xmark").frame(width: 36, height: 44) }
                        .accessibilityLabel("İndirmeyi iptal et").accessibilityIdentifier("download.cancel.\(entry.id.uuidString)")
                } else if entry.status == .failed || entry.status == .cancelled {
                    Button { downloads.retry(entry) } label: { Image(systemName: "arrow.clockwise").frame(width: 36, height: 44) }.accessibilityLabel("Yeniden dene")
                } else if let track {
                    Button { playback.play(track, in: library.tracks) } label: { Image(systemName: "play.fill").frame(width: 36, height: 44) }
                        .accessibilityLabel("İndirilen parçayı çal").accessibilityIdentifier("download.play.\(entry.format.rawValue)")
                }
            }
            if entry.status == .preparing || entry.status == .downloading {
                ProgressView(value: min(1, max(0, entry.progress))).tint(RitimTheme.mint)
                HStack {
                    Text(entry.stage?.title ?? (entry.status == .preparing ? "Kaynak hazırlanıyor…" : "Genel işlem ilerlemesi"))
                    Spacer()
                    Text("%\(Int(min(1, max(0, entry.progress)) * 100))").monospacedDigit()
                }.font(.caption2).foregroundStyle(RitimTheme.muted)
            } else if entry.status == .queued {
                Label(downloads.isQueuePaused ? "Duraklatılan sırada bekliyor" : (downloads.resourceWaitMessage ?? "Sırası geldiğinde başlayacak"), systemImage: "clock")
                    .font(.caption2).foregroundStyle(RitimTheme.muted)
            }
            if entry.status == .queued {
                Button { downloads.prioritize(entry) } label: {
                    Label((entry.priority ?? 0) > 0 ? "Normal sıraya al" : "Öncelik ver", systemImage: "arrow.up.to.line")
                }.font(.caption).buttonStyle(.borderless)
            }
            if let received = entry.receivedBytes, entry.status == .downloading, entry.stage != .converting, entry.stage != .saving {
                Text(ByteCountFormatter.string(fromByteCount: received, countStyle: .file) + (entry.expectedBytes.map { " / " + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""))
                    .font(.caption2).monospacedDigit().foregroundStyle(RitimTheme.muted)
                if let speed = entry.bytesPerSecond, speed.isFinite, speed > 0, speed < Double(Int64.max) {
                    Text("Geçerli kaynak: " + ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/sn")
                        .font(.caption2).foregroundStyle(RitimTheme.muted)
                    if let total = entry.expectedBytes, total > received {
                        let seconds = min(86_400, max(1, Double(total - received) / speed))
                        Text("Yaklaşık \(Int(seconds)) sn aktarım kaldı; dönüştürme hariç")
                            .font(.caption2).foregroundStyle(RitimTheme.muted)
                    }
                }
            }
            if let note = entry.qualityNote { Text(note).font(.caption2).foregroundStyle(RitimTheme.muted) }
            if let error = entry.error, !error.isEmpty {
                Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(16).background(RitimTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SettingsView: View {
    @EnvironmentObject private var downloads: DownloadStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var assistant: AIAssistantStore
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @State private var archiveURL: URL?
    @State private var archiveBusy = false
    @State private var archiveMessage: String?
    @State private var showRestore = false
    @State private var pendingRestore: URL?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(ThemeStyle.all) { style in
                                Button { theme.select(style.id, reopenSettings: true) } label: {
                                    VStack(spacing: 8) {
                                        Circle().fill(LinearGradient(colors: [style.accent, style.second], startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .frame(width: 46, height: 46)
                                            .overlay(Circle().strokeBorder(.white, lineWidth: theme.selectedID == style.id ? 3 : 0))
                                            .overlay { if theme.selectedID == style.id { Image(systemName: "checkmark").font(.headline.bold()).foregroundStyle(style.background) } }
                                        Text(style.name).font(.caption2.weight(.semibold)).foregroundStyle(theme.selectedID == style.id ? .white : RitimTheme.muted)
                                    }.frame(minWidth: 60)
                                }.buttonStyle(.plain).accessibilityIdentifier("settings.theme.\(style.id)")
                                    .accessibilityAddTraits(theme.selectedID == style.id ? .isSelected : [])
                            }
                        }.padding(.vertical, 6)
                    }
                } header: { Text("Tema ve renkler") }.listRowBackground(RitimTheme.surface)
                Section {
                    HStack(spacing: 15) {
                        Image(systemName: "waveform").font(.system(size: 30, weight: .bold)).foregroundStyle(RitimTheme.background)
                            .frame(width: 64, height: 64).background(RitimTheme.mint, in: RoundedRectangle(cornerRadius: 18))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ritim").font(.title.bold())
                            Text("Müziğin hep yanında.").font(.caption).foregroundStyle(RitimTheme.muted)
                        }
                    }.padding(.vertical, 8)
                }.listRowBackground(RitimTheme.surface)
                Section {
                    Label("Doğrudan iPhone’a indir", systemImage: "iphone.gen3.radiowaves.left.and.right")
                        .accessibilityIdentifier("settings.nativeDownloads")
                    Text("YouTube bağlantıları bu cihazda çözülür. Ses MP3’e çevrilir; video ve ses MP4 olarak birleştirilir. Mac veya indirme sunucusu gerekmez.")
                        .font(.caption).foregroundStyle(RitimTheme.muted)
                } header: { Text("iPhone’da indirme") } footer: {
                    Text("Yeni indirmeler internet kullanır. Tamamlanan müzik ve videolar çevrimdışı çalar.")
                }.listRowBackground(RitimTheme.surface)
                Section {
                    Picker("İndirme kalitesi", selection: $downloads.downloadQuality) {
                        Text(DownloadQuality.highest.title).tag(DownloadQuality.highest)
                        Text(DownloadQuality.standard.title).tag(DownloadQuality.standard)
                    }.pickerStyle(.menu).accessibilityIdentifier("settings.downloadQuality")
                        .accessibilityValue(downloads.downloadQuality.title)
                } header: { Text("Ses ve video kalitesi") } footer: {
                    Text("En yüksek: 320 kbps MP3 ve bu iPhone’un işleyebildiği en yüksek video (en fazla 4K). Bazı YouTube videolarında uyumlu kaynak 1080p ile sınırlıdır. Standart: 192 kbps MP3, en fazla 1080p. Seçimin yeni indirmelere uygulanır. Kalite kaynakla sınırlıdır; dosya başına en fazla 512 MB.")
                }.listRowBackground(RitimTheme.surface)
                Section {
                    Toggle("İndirme sırasında ekranı açık tut", isOn: $downloads.keepScreenAwake)
                        .accessibilityIdentifier("settings.keepScreenAwake")
                    LabeledContent("Şu anki iş sınırı", value: "\(downloads.effectiveConcurrency)")
                    if let reason = downloads.resourceWaitMessage { Text(reason).font(.caption).foregroundStyle(.orange) }
                    LabeledContent("Bekleyen indirme kapasitesi", value: "\(DownloadStore.queueLimit) dosya")
                    Picker("Eşzamanlı indirme", selection: $downloads.maxConcurrentDownloads) {
                        ForEach(DownloadStore.concurrencyOptions, id: \.self) { count in
                            Text("\(count) dosya").tag(count)
                        }
                    }.pickerStyle(.menu).accessibilityIdentifier("settings.concurrentDownloads")
                        .accessibilityValue("\(downloads.maxConcurrentDownloads) dosya")
                } header: { Text("Toplu indirme") } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tüm dosyalar doğrudan bu iPhone’da hazırlanır. Sıra çalışırken eşzamanlı indirme sayısını artırınca sıradaki dosyalar hemen başlar. Azaltınca başlamış dosyalar tamamlanır; yeni indirmeler seçtiğin sınıra göre ilerler.")
                        Text("Ekranı açık tutma, Ritim öndeyken etkin indirmeler için çalışır. Çözümlenmiş kaynaklar arka planda aktarılabilir; iOS bekleyen işlerin ve dönüştürmenin çalışma zamanını belirler. Kuyruğu duraklat düğmesi yalnız yeni işleri bekletir.")
                    }
                }.listRowBackground(RitimTheme.surface)
                Section {
                    if !assistant.excludedTrackIDs.isEmpty {
                        Button("Önerilmeyen parçaları sıfırla (\(assistant.excludedTrackIDs.count))") { assistant.resetRecommendationExclusions() }
                    }
                    Toggle("Günün karışımını kendiliğinden hazırla", isOn: $assistant.proactiveEnabled)
                        .accessibilityIdentifier("settings.aiProactive")
                    LabeledContent("Model", value: assistant.selectedModel?.name ?? (assistant.selectedModelID.isEmpty ? "Seçilmedi" : assistant.selectedModelID))
                } header: { Text("Yapay zekâ") } footer: {
                    Text("Açıkken ana sayfa günde bir kez seçtiğin modelden sana özel bir karışım ister. AI DJ, parça notu ve sohbet yalnızca dokunduğunda çalışır. Modele ses dosyası ve dosya yolu gönderilmez; parça adı, sanatçı, süre, favori ve dinleme sayısı, saat ve gün bölümü, şimdi çalan parça, son dinlediklerin, çalma sıran ile liste adları ve parça sayıları gönderilir. Asistan çalmayı başlatabilir veya sıraya ekleyebilir; indirme ve liste kaydı yalnız senin onayınla yapılır.")
                }.listRowBackground(RitimTheme.surface)
                Section("Cihazındaki kütüphane") {
                    LabeledContent("Parçalar", value: "\(library.tracks.count)")
                    LabeledContent("Çalma listeleri", value: "\(library.playlists.count)")
                    LabeledContent("Kullanılan alan", value: ByteCountFormatter.string(fromByteCount: library.storageBytes, countStyle: .file))
                    Label("İndirilen dosyalar çevrimdışı çalınır", systemImage: "checkmark.circle").font(.caption).foregroundStyle(RitimTheme.muted)
                }.listRowBackground(RitimTheme.surface)
                Section("Yedek ve bakım") {
                    Button("Kütüphane bilgilerini yedekle", systemImage: "doc") { makeBackup(media: false) }
                    Button("Medya dahil tam yedek", systemImage: "externaldrive") { makeBackup(media: true) }
                    if let archiveURL { ShareLink("Yedeği Dosyalar’a kaydet", item: archiveURL) }
                    Button("Yedeği birleştirerek geri yükle", systemImage: "arrow.counterclockwise") { showRestore = true }
                    Button("Eksik ve yinelenen dosyaları denetle", systemImage: "checkmark.shield") {
                        archiveBusy = true
                        Task { archiveMessage = await library.inspectStorage(); archiveBusy = false }
                    }
                    if archiveBusy { ProgressView("İşlem sürüyor…") }
                    if let archiveMessage { Text(archiveMessage).font(.caption).foregroundStyle(RitimTheme.muted) }
                    Text("Bilgi yedeği medya içermez; yalnız bu cihazda bulunan parçalarla listeleri birleştirir. Tam yedek ses ve videoları da içerir. Mevcut parçalar ve listeler korunur.").font(.caption).foregroundStyle(RitimTheme.muted)
                }.disabled(archiveBusy).listRowBackground(RitimTheme.surface)
                Section("Ritim hakkında") {
                    Text("Müzik, video, favoriler ve çalma listeleri. Kilit ekranı kontrolleri, arka planda ses, AirPlay ve uyku zamanlayıcısıyla kendi kütüphanenin keyfini çıkar.").font(.subheadline)
                    Text("İlk açılışta sunulan kısa özgün kayıtlar Ritim Studio tarafından uygulama demosu için üretilmiştir.").font(.caption).foregroundStyle(RitimTheme.muted)
                    Text("Sürüm \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                        .font(.caption).foregroundStyle(RitimTheme.muted)
                }.listRowBackground(RitimTheme.surface)
            }.scrollContentBackground(.hidden).background(RitimTheme.background)
                .navigationTitle("Ayarlar").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
        }.preferredColorScheme(.dark).tint(RitimTheme.mint)
            .fileImporter(isPresented: $showRestore, allowedContentTypes: [.data]) { result in
                switch result {
                case .success(let url): pendingRestore = url
                case .failure(let error): archiveMessage = error.localizedDescription
                }
            }
            .confirmationDialog("Yedeği mevcut kitaplığınla birleştir?", isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })) {
                Button("Birleştir") {
                    guard let url = pendingRestore else { return }
                    pendingRestore = nil; archiveBusy = true
                    Task {
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() }; archiveBusy = false }
                        do { let count = try await library.restoreBackup(url); archiveMessage = "Yedek birleştirildi: \(count) yeni parça." }
                        catch { archiveMessage = error.localizedDescription }
                    }
                }
                Button("Vazgeç", role: .cancel) { pendingRestore = nil }
            } message: { Text("Önce yedek doğrulanır. Mevcut müzikler ve listeler değiştirilmez.") }
    }
    private func makeBackup(media: Bool) {
        archiveBusy = true; archiveMessage = nil
        Task {
            defer { archiveBusy = false }
            do {
                let newURL = try await library.exportBackup(includeMedia: media)
                if let old = archiveURL { try? FileManager.default.removeItem(at: old) }
                archiveURL = newURL
                archiveMessage = "Yedek hazır. Kalıcı saklamak için Dosyalar’a kaydet."
            } catch { archiveMessage = error.localizedDescription }
        }
    }
}
