import Combine
import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerController.self) private var player
    @Environment(GenerationCoordinator.self) private var generator
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Episode.createdAt, order: .reverse) private var episodes: [Episode]
    @Query private var reviewCards: [ReviewCard]
    @Query private var queued: [QueuedRequest]
    @Query private var documents: [SourceDocument]
    @Query private var videos: [VideoLesson]

    @State private var showNew = false
    @State private var podcastsOnly = false
    @State private var showBooks = false
    @State private var importVideo = false
    @State private var path: [UUID] = []
    @State private var episodeToDelete: Episode?
    @State private var showReview = false
    @State private var showNotes = false
    @State private var showBookNotebook = false
    @State private var showStats = false
    @State private var showDocuments = false
    @State private var showAsk = false
    @State private var showWorkout = false
    @State private var showPlan = false
    @State private var showVideos = false
    @State private var demoLesson: UUID?
    // #37/#38: arama, filtre, sıralama, hızlı işlemler
    @State private var searchText = ""
    @State private var hits: [EpisodeSearch.Hit] = []
    @State private var searching = false
    @State private var filter: LibraryFilter = .all
    @AppStorage(LibrarySort.key) private var sortRaw = LibrarySort.newest.rawValue
    @State private var renameTarget: Episode?
    @State private var renameText = ""
    @State private var organizeTarget: Episode?
    @State private var showTopics = false
    @State private var showMacBackup = false
    @State private var quickError: String?
    @State private var searchIndex = EpisodeSearchIndex()
    /// Akıştaki bölümler (`PodcastFeed.changed` ile yenilenir) ve akışa gönderimi/çıkarılması süren bölümler.
    @State private var inFeed = PodcastFeed.published
    @State private var feedBusy: Set<UUID> = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if podcastsOnly {
                        Button("Tüm kaynaklar", systemImage: "arrow.left") { podcastsOnly = false; searchText = "" }
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }
                    if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        searchResults
                    } else if podcastsOnly {
                        podcastCollection
                    } else {
                        libraryOverview
                    }
                    DraftBanner()
                    QueueBanner()
                    if podcastsOnly { ServerBanner() }
                    MacRestoreBanner()
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
            }
            .id(podcastsOnly)
            .navigationTitle(podcastsOnly ? "Podcast’ler" : "Kitaplık")
            .navigationBarTitleDisplayMode(.large)
            .background(Theme.canvas)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: podcastsOnly ? "Podcast başlığı veya içeriği ara" : "Kitap veya podcast ara")
            .task(id: searchText) { await runSearch() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { HomeButton() }
                // Ekleme eylemleri ekrandaki büyük düğmelerde, araçlar Çalış'ta, sunucu yedeği Ayarlar'da: menüde tekrar yok.
                ToolbarItem(placement: .topBarTrailing) { ModuleMenu(module: .library) { EmptyView() } }
            }
            .navigationDestination(isPresented: $showBooks) { MEBLibraryView() }
            .navigationDestination(for: UUID.self) { id in
                if let episode = episodes.first(where: { $0.id == id }) {
                    EpisodeDetailView(episode: episode)
                } else if queued.contains(where: { $0.id == id }) || generator.drafts[id] != nil {
                    // #50: senaryosu yazılan (taslak kimliği = bölüm kimliği) ya da kuyruktaki bölüm.
                    PendingGenerationView(id: id)
                } else {
                    ContentUnavailableView("Bölüm silinmiş", systemImage: "trash.slash",
                                           description: Text("Bu bölüm artık kütüphanende yok."))
                }
            }
            .refreshable { await app.refreshStatus() }
            .onReceive(NotificationCenter.default.publisher(for: PodcastFeed.changed).receive(on: RunLoop.main)) { _ in
                inFeed = PodcastFeed.published
            }
            // Hızlı işlemde akışa ekleme/çıkarma hatası (menü kapandıktan sonra gelir).
            .alert("Podcast akışı", isPresented: Binding(get: { quickError != nil }, set: { if !$0 { quickError = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(quickError ?? "")
            }
        }
        .safeAreaInset(edge: .bottom) {
            // #41: brifing çalarken (`episode` nil) de görünür.
            if player.isActive, player.episode == nil || path.last != player.episode?.id {
                MiniPlayer { if let id = player.episode?.id { path = [id] } }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: player.episode?.id)
        .animation(reduceMotion ? nil : .smooth, value: player.isActive)
        .sheet(isPresented: $showNew) {
            NewPodcastView { episode in
                showNew = false
                path = [episode.id]
            }
        }
        .sheet(isPresented: $showReview) { ReviewView() }
        .sheet(isPresented: $showBookNotebook) { BookNotebookView() }
        .sheet(isPresented: $showStats) { StatsView() }
        .sheet(isPresented: $showAsk) { LibraryAskView() }
        .sheet(isPresented: $showWorkout) { DailyWorkoutView() }
        .sheet(isPresented: $showPlan) { StudyPlanView() }
        .sheet(isPresented: $showDocuments) { DocumentLibraryView() }
        .sheet(isPresented: $showVideos) { VideoLibraryView(openImport: importVideo, openLesson: demoLesson) }
        .sheet(isPresented: $showTopics) { NavigationStack { TopicTreeView() } }
        .sheet(isPresented: $showMacBackup) { MacBackupView() }
        .sheet(item: $organizeTarget) { EpisodeOrganizeSheet(episode: $0) }
        .alert("Yeniden adlandır", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Bölüm adı", text: $renameText)
                .onChange(of: renameText) { _, text in
                    if text.count > EpisodeTitle.maxLength { renameText = String(text.prefix(EpisodeTitle.maxLength)) }
                }
            Button("Vazgeç", role: .cancel) {}
            Button("Kaydet") {
                if let target = renameTarget, let name = EpisodeTitle.cleaned(renameText) { target.title = name; try? context.save() }
            }
        }
        .onChange(of: app.server != nil) { _, connected in
            if connected {
                Task {
                    await OfflineQueue.process(context: context, generator: generator)
                    await WeeklyRecap.runIfDue(context: context, generator: generator)
                }
            }
        }
        .sheet(isPresented: $showNotes) {
            NavigationStack {
                EpisodeNotesView(episodeID: nil)
                    .navigationTitle("Notlarım")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { showNotes = false } } }
            }
        }
        .onChange(of: app.pendingOpenEpisode, initial: true) { _, id in
            guard let id else { return }
            closeSheets()
            path = [id]
            app.pendingOpenEpisode = nil
        }
        .onChange(of: app.pendingRoute, initial: true) { _, route in
            guard let route, !MainTabs.studyRoutes.contains(route) else { return }
            closeSheets()
            switch route {
            case "review": showReview = true
            case "notes": showNotes = true
            case "new": showNew = true
            case "stats": showStats = true
            case "plan": showPlan = true
            case let named where named.hasPrefix("play:"):
                // Asistan: adı geçen hazır bölümü çal (18 Eki 2026).
                let ready = episodes.filter { $0.status == .ready }
                if let index = AssistantActions.match(String(named.dropFirst(5)), titles: ready.map(\.title)) {
                    player.load(ready[index], context: context, autoplay: true)
                    path = [ready[index].id]
                }
            case "playLatest":
                let latest = episodes.filter { $0.status == .ready }
                    .max { ($0.lastPlayedAt ?? $0.createdAt) < ($1.lastPlayedAt ?? $1.createdAt) }
                if let latest {
                    player.load(latest, context: context, autoplay: true)
                    path = [latest.id]
                }
            default: break
            }
            app.pendingRoute = nil
        }
        .onChange(of: app.incomingFiles, initial: true) { _, files in
            guard !files.isEmpty, !showNew else { return }
            closeSheets()
            showNew = true
        }
        .confirmationDialog("Bölüm silinsin mi?", isPresented: Binding(get: { episodeToDelete != nil }, set: { if !$0 { episodeToDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                if let episode = episodeToDelete { delete(episode) }
            }
        } message: {
            Text("Ses dosyası, transkript ve quiz bu cihazdan kalıcı olarak silinir.")
        }
        .task {
            MEBLibrary.shared.reload()
            GenerationQueue.resumeOnLaunch(episodes: episodes, context: context, generator: generator)
            #if DEBUG
            P7Demo.seed(context: context)
            switch DebugArg.value("p7Sheet") {
            case "topics": showTopics = true
            case "backup": showMacBackup = true
            case "organize": organizeTarget = episodes.first
            case "documents": P7Demo.seedDocument(context: context); showDocuments = true
            default: break
            }
            if ProcessInfo.processInfo.arguments.contains("-offlineSpeechPlayback"),
               let episode = episodes.first(where: { $0.status == .ready && $0.settings?.engine.isNeuralOnDevice == true }) {
                player.load(episode, context: context, autoplay: true)
                path = [episode.id]
            }
            if let verified = await OfflineSpeechVerification.run(context: context, generator: generator) {
                path = [verified.id]
            }
            if FollowDemo.isRequested {
                let seeded = FollowDemo.seed(context: context)
                switch FollowDemo.open {
                case "podcast":
                    if let e = seeded.episode { player.load(e, context: context, autoplay: FollowDemo.autoplay); path = [e.id] }
                case "video":
                    if let l = seeded.lesson { demoLesson = l.id; showVideos = true }
                default: break
                }
            }
            if let demo = await DebugSeed.seedIfRequested(context: context) {
                path = [demo.id]
                if (ProcessInfo.processInfo.arguments.contains("-deviceSpeechEpisode") || ProcessInfo.processInfo.arguments.contains("-chirpEpisode") || ProcessInfo.processInfo.arguments.contains("-edgeEpisode") || ProcessInfo.processInfo.arguments.contains("-hfEpisode")), demo.status == .generating {
                    generator.resume(demo, context: context)
                }
            }
            #endif
        }
    }

    private var bookCount: Int { MEBLibrary.shared.downloaded.filter { $0.id.hasPrefix("kitap-") }.count }

    private var actionColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    @ViewBuilder private var libraryOverview: some View {
        ScreenHero(eyebrow: "Kitaplık", title: "Kitapların, podcast’lerin ve videoların burada.",
                   subtitle: "\(bookCount) kitap · \(episodes.count) podcast · \(documents.count) belge · \(videos.count) video",
                   symbol: "books.vertical.fill")
        LazyVGrid(columns: actionColumns, spacing: 12) {
            BigActionButton(title: "Podcast oluştur", symbol: "plus.circle.fill", style: .yellow) { showNew = true }
            BigActionButton(title: "MEB kitabı bul", symbol: "book.closed", style: .blue) { showBooks = true }
            BigActionButton(title: "YouTube videosu ekle", symbol: "play.rectangle", style: .outline) { importVideo = true; showVideos = true }
        }
        if MEBLibrary.shared.recentFile != nil || continueEpisode != nil {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Kaldığın yer")
                if let book = MEBLibrary.shared.recentFile { MEBContinueCard(file: book) }
                if let resume = continueEpisode {
                    ContinueCard(episode: resume) {
                        player.load(resume, context: context, autoplay: true); path = [resume.id]
                    }
                }
            }
        }
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Kaynakların", detail: "Oku, dinle veya izle.")
            Button { showBooks = true } label: {
                BigRow(title: "Kitaplar", detail: "\(bookCount) cihazda · MEB kataloğu", symbol: "book.closed", tone: .blue)
            }
            Button { podcastsOnly = true } label: {
                BigRow(title: "Podcast’ler", detail: "\(episodes.count) bölüm", symbol: "headphones", tone: .yellow)
            }
            Button { showDocuments = true } label: {
                BigRow(title: "Belgeler", detail: "\(documents.count) kayıtlı kaynak", symbol: "doc.text", tone: .navy)
            }
            Button { importVideo = false; showVideos = true } label: {
                BigRow(title: "Videolar", detail: "\(videos.count) video dersi", symbol: "play.rectangle", tone: .sky)
            }
        }.buttonStyle(PressableCardStyle(reduceMotion: false))
        if !episodes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Son podcast’ler")
                ForEach(Array(episodes.prefix(3))) { episodeLink($0) }
                Button { podcastsOnly = true } label: {
                    BigRow(title: "Tüm podcast’ler", detail: "\(episodes.count) bölüm", symbol: "arrow.right", tone: .sky)
                }.buttonStyle(PressableCardStyle(reduceMotion: false))
            }
        }
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Çalışma araçların")
            Button { showBookNotebook = true } label: {
                BigRow(title: "Kitap defterim", detail: BookStudyStore.shared.entries.isEmpty ? "Alıntılarını ve yer imlerini biriktir, karta dönüştür." : "\(BookStudyStore.shared.entries.count) kayıt · alıntı, not ve yer imi", symbol: "book.closed.circle", tone: .blue)
            }
            .accessibilityIdentifier("library.bookNotebook")
            Button { showNotes = true } label: {
                BigRow(title: "Notlarım", detail: "Dinlerken kaydettiğin noktalar", symbol: "bookmark", tone: .yellow)
            }
            if !episodes.isEmpty {
                Button { showAsk = true } label: {
                    BigRow(title: "Kaynaklarına sor", detail: "Podcast’lerin üzerinden yanıt bul", symbol: "bubble.left.and.bubble.right", tone: .navy)
                }
            }
        }.buttonStyle(PressableCardStyle(reduceMotion: false))
    }

    @ViewBuilder private var searchResults: some View {
        if !podcastsOnly {
            let books = MEBBookQuery.results(catalog: .shared, query: searchText)
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Kitaplar", detail: "\(books.count) başlık eşleşti")
                ForEach(Array(books.prefix(8))) { book in
                    if let file = MEBFile(book: book) { MEBFileRow(file: file).padding(14).okuSurface() }
                }
                if books.count > 8 {
                    NavigationLink { MEBLibraryView(query: searchText) } label: {
                        Text("\(books.count) kitabın tümünü gör").font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }
                }
            }
        }
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Podcast’ler", detail: "Başlık, kaynak ve transkript içinde")
            EpisodeSearchResults(hits: hits, searching: searching) { hit in
                app.open(hit.episodeID, at: hit.time)
            }
        }
    }

    @ViewBuilder private var podcastCollection: some View {
        ScreenHero(eyebrow: "Podcast’ler", title: "Dinlemeye kaldığın yerden devam et.",
                   subtitle: "\(episodes.count) bölüm", symbol: "headphones")
        BigActionButton(title: "Podcast oluştur", symbol: "plus.circle.fill", style: .yellow) { showNew = true }
        if let resume = continueEpisode {
            ContinueCard(episode: resume) {
                player.load(resume, context: context, autoplay: true); path = [resume.id]
            }
        }
        if episodes.isEmpty {
            EmptyLibrary()
        } else {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(title: "\(episodes.count) bölüm")
                Spacer(minLength: 8)
                LibrarySortMenu(sort: sortBinding)
            }
            LibraryFilterBar(filter: $filter, counts: filterCounts)
            let rows = libraryRows
            let byID = episodeByID
            if rows.isEmpty { Text("Bu filtrede bölüm yok.").foregroundStyle(.secondary) }
            LazyVStack(spacing: 12) {
                ForEach(rows) { row in
                    switch row {
                    case let .episode(id, children):
                        if let episode = byID[id] {
                            VStack(alignment: .leading, spacing: 4) {
                                episodeLink(episode)
                                DerivedChildren(ids: children) { child in
                                    if let item = byID[child] { episodeLink(item) }
                                }
                            }
                        }
                    case let .series(seriesID):
                        let members = episodes.filter { $0.seriesID == seriesID }
                        NavigationLink { SeriesView(seriesID: seriesID) } label: {
                            SeriesCard(title: members.first?.seriesTitle ?? "Seri", items: members.map { EpisodeListItem($0) },
                                       cover: members.min { $0.seriesIndex < $1.seriesIndex }?.visuals?.cover)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Aynı anda tek sayfa gösterilebilir: yeni rota öncesi açık olanları kapat.
    private func closeSheets() {
        showReview = false
        showNotes = false
        showBookNotebook = false
        showStats = false
        showDocuments = false
        showAsk = false
        showWorkout = false
        showPlan = false
        showVideos = false
        showNew = false
        showTopics = false
        showMacBackup = false
        organizeTarget = nil
        showBooks = false
        importVideo = false
    }

    // MARK: - #37–#40 liste

    private var sortBinding: Binding<LibrarySort> {
        Binding(get: { LibrarySort(rawValue: sortRaw) ?? .newest }, set: { sortRaw = $0.rawValue })
    }

    private var episodeByID: [UUID: Episode] { Dictionary(episodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }

    private var libraryItems: [EpisodeListItem] {
        let due = Set(reviewCards.filter(\.isDue).map(\.episodeID))
        return episodes.map { EpisodeListItem($0, dueEpisodes: due) }
    }

    private var filterCounts: [LibraryFilter: Int] {
        let items = libraryItems
        return Dictionary(uniqueKeysWithValues: LibraryFilter.allCases.map { f in (f, items.filter { LibraryQuery.matches($0, f) }.count) })
    }

    /// Filtre "Tümü" iken seri tek kart; diğer filtrelerde bölümler tek tek.
    private var libraryRows: [LibraryRow] {
        let ordered = LibraryQuery.sorted(libraryItems.filter { LibraryQuery.matches($0, filter) }, by: LibrarySort(rawValue: sortRaw) ?? .newest)
        return LibraryGrouping.rows(ordered, collapseSeries: filter == .all)
    }

    private func episodeLink(_ episode: Episode) -> some View {
        NavigationLink(value: episode.id) {
            EpisodeRow(episode: episode, inFeed: inFeed.contains(episode.id), feedBusy: feedBusy.contains(episode.id))
        }
        .buttonStyle(.plain)
        .contextMenu {
            EpisodeQuickActions(episode: episode,
                                rename: { renameText = episode.title; renameTarget = episode },
                                organize: { organizeTarget = episode },
                                delete: { episodeToDelete = episode },
                                published: inFeed.contains(episode.id),
                                feedBusy: feedBusy.contains(episode.id),
                                toggleFeed: { toggleFeed(episode) })
        }
    }

    /// Akışa ekleme/çıkarma menü kapandıktan sonra sürer (ses yüklenir): satır ilerlemeyi, bitince "Akışta" simgesini gösterir.
    private func toggleFeed(_ episode: Episode) {
        let id = episode.id
        guard !feedBusy.contains(id) else { return }
        let removing = inFeed.contains(id)
        feedBusy.insert(id)
        Task {
            // Bildirim bir tur sonra gelir: simge, ilerleme kalktığı anda görünsün diye durum burada da okunur.
            defer { feedBusy.remove(id); inFeed = PodcastFeed.published }
            do {
                // Çıkarma kimlikle yapılır: bölüm bu arada silindiyse modele dokunulmaz.
                if removing { try await PodcastFeed.remove(id: id) } else { try await PodcastFeed.publish(episode) }
            } catch {
                quickError = (removing ? "Akıştan çıkarılamadı: " : "Akışa eklenemedi: ") + error.localizedDescription
            }
        }
    }

    /// Yazarken kısa bekleme; transkriptler ana iş parçacığı dışında taranır.
    private func runSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { hits = []; searching = false; return }
        searching = true
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        // Transkript yalnız yeni ya da sesi değişen bölümde okunur; katlanmış dizin arka planda önbellekte tutulur.
        let found = await searchIndex.search(query, episodes: episodes)
        guard !Task.isCancelled else { return }
        hits = found
        searching = false
    }

    /// En son dinlenen, bitmemiş hazır bölüm.
    private var continueEpisode: Episode? {
        episodes
            .filter { $0.status == .ready && !$0.isFinished && $0.lastPosition > 5 && $0.lastPlayedAt != nil }
            .max { ($0.lastPlayedAt ?? .distantPast) < ($1.lastPlayedAt ?? .distantPast) }
            .flatMap { player.episode?.id == $0.id ? nil : $0 }
    }

    private func delete(_ episode: Episode) {
        if player.episode?.id == episode.id { player.close() }
        Task { await generator.delete(episode, context: context) }
    }
}

/// Yalnızca sunucuya ulaşılamadığında görünür.
struct ServerBanner: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if let error = app.serverError {
            // Dar ekranda düğme metin sütununu daraltmasın diye altta.
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sunucuya ulaşılamıyor").font(.subheadline.bold())
                            .fixedSize(horizontal: false, vertical: true)
                        Text(error).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(ServerPlace.connectionHint(host: Config.apiBaseURL.host())).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button("Tekrar dene") { Task { await app.refreshStatus() } }
                    .font(.caption.bold())
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// Sunucu adresi ev ağında mı (yerel makine, mDNS adı, özel ya da CGNAT IPv4 aralığı)? Bağlantı ipucunu seçer.
nonisolated enum ServerPlace {
    static func isLocal(host: String?) -> Bool {
        guard let host = host?.lowercased(), !host.isEmpty else { return false }
        if host == "localhost" || host == "::1" || host.hasSuffix(".local") { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) ?? -1 }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        let (a, b) = (parts[0], parts[1])
        return a == 10 || a == 127 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) || (a == 100 && (64...127).contains(b))
    }

    static func connectionHint(host: String?) -> String {
        isLocal(host: host)
            ? "Sunucunun çalıştığı bilgisayar açık ve telefonla aynı ağda mı?"
            : "İnternet bağlantını ve Ayarlar → Sunucu adresini denetle."
    }
}

private struct ContinueCard: View {
    var episode: Episode
    var play: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: play) {
            HStack(spacing: 14) {
                if !typeSize.isAccessibilitySize { EpisodeArtwork(title: episode.title, size: 52, cover: episode.visuals?.cover).accessibilityHidden(true) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dinlemeye devam et").font(.subheadline.weight(.heavy)).foregroundStyle(Theme.blueInk)
                    Text(episode.title).font(.subheadline.bold()).lineLimit(typeSize.isAccessibilitySize ? nil : 2).multilineTextAlignment(.leading)
                    ProgressView(value: episode.lastPosition, total: max(episode.duration, 1))
                    Text("\(max(0, episode.duration - episode.lastPosition).minutesText) kaldı")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if !typeSize.isAccessibilitySize { Image(systemName: "play.circle.fill").font(.system(size: 36)).foregroundStyle(Theme.gradient).accessibilityHidden(true) }
            }
            .padding(14)
            .okuSurface()
        }
        .buttonStyle(.plain)
    }
}

private struct ReviewCard_Banner: View {
    var due: Int
    var total: Int
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.warmGradient)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(due > 0 ? "Bugün \(due) kart tekrar bekliyor" : "Bugünkü tekrarlar tamam")
                        .font(.subheadline.bold())
                    Text("Destende \(total) kart var · aralıklı tekrar").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct NewPodcastCard: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Yeni podcast oluştur")
                        .font(.title3.bold())
                    Text("PDF, Word veya fotoğraf ekle; iki sunucu senin için anlatsın.")
                        .font(.subheadline)
                        .opacity(0.9)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 44))
            }
            .foregroundStyle(.white)
            .padding(20)
            .background(Theme.gradient, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .shadow(color: Theme.blueInk.opacity(0.3), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyLibrary: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text("Henüz podcast yok")
                .font(.headline)
            Text("Bir ders notu, kitap bölümü ya da makale ekleyerek ilk bölümünü oluştur.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

struct EpisodeRow: View {
    var episode: Episode
    /// Bölüm podcast akışında mı; akışa gönderimi ya da çıkarılması sürüyor mu (durum üst görünümde tutulur).
    var inFeed = false
    var feedBusy = false
    @Environment(GenerationCoordinator.self) private var generator
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 14) {
            if !typeSize.isAccessibilitySize { EpisodeArtwork(title: episode.title, cover: episode.visuals?.cover).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 4) {
                if let series = episode.seriesTitle {
                    // Sıra başta: uzun seri adı kırpılınca ayırt edici "N. bölüm" kaybolmasın.
                    Text("\(episode.seriesIndex). bölüm · \(series)")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.blueInk)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                }
                DerivedBadge(kind: episode.derivedKind)
                Text(episode.title)
                    .font(.headline)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.leading)
                subtitle
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .okuSurface()
        .contentShape(Rectangle())
    }

    @ViewBuilder private var subtitle: some View {
        switch episode.status {
        case .ready:
            VStack(alignment: .leading, spacing: 4) {
                (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 6))) {
                    Text(episode.duration.minutesText)
                    if episode.isFinished {
                        Label("Dinlendi", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon)
                    } else if episode.lastPosition > 5 {
                        Text("· \(Int(episode.lastPosition / max(episode.duration, 1) * 100))% dinlendi")
                    }
                    if inFeed, !feedBusy {
                        Image(systemName: "dot.radiowaves.left.and.right").accessibilityLabel("Akışta")
                    }
                }
                if feedBusy {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(inFeed ? "Akıştan çıkarılıyor…" : "Akışa gönderiliyor…")
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        case .generating:
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: episode.progress)
                Text(generator.progressText(for: episode.id) ?? (generator.isRunning(episode) ? "Seslendiriliyor · \(episode.scenesDone)/\(episode.scenesTotal)" : "Yarıda kaldı · devam etmek için dokun"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            Label("Oluşturulamadı", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
