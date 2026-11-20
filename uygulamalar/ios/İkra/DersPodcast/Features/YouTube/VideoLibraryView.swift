import SwiftData
import SwiftUI

/// YouTube dersleri listesinin sırası (seçim cihazda hatırlanır).
nonisolated enum VideoLibrarySort: String, CaseIterable, Identifiable, Sendable {
    case added, opened, unfinished, title

    static let key = "youtube.librarySort"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .added: "Son eklenen"
        case .opened: "Son açılan"
        case .unfinished: "Yarım kalanlar önce"
        case .title: "Başlık (A→Z)"
        }
    }
}

/// Liste sırasının saf hesabı (model nesnelerinden bağımsız; sınanabilir).
nonisolated enum VideoLibraryOrder {
    struct Item: Sendable {
        var id: UUID
        var title: String
        var createdAt: Date
        /// Son açılış (LessonOpenLog); hiç açılmadıysa nil.
        var openedAt: Date?
        /// İzlenen oran (0…1).
        var progress: Double
    }

    /// Yarım kalmış: başlanmış ama bitmemiş (hiç açılmamış ve sonuna gelinmiş dersler dışarıda).
    static func isUnfinished(_ progress: Double) -> Bool {
        progress > 0.01 && progress < 0.95
    }

    static func sorted(_ items: [Item], by sort: VideoLibrarySort) -> [UUID] {
        let ordered: [Item]
        switch sort {
        case .added:
            ordered = items.sorted { $0.createdAt > $1.createdAt }
        case .opened:
            ordered = items.sorted(by: recentlyOpenedFirst)
        case .unfinished:
            ordered = items.filter { isUnfinished($0.progress) }.sorted(by: recentlyOpenedFirst)
                + items.filter { !isUnfinished($0.progress) }.sorted { $0.createdAt > $1.createdAt }
        case .title:
            // Türkçe alfabe sırası (ç, c'den; ı, i'den ayrı harf); cihaz dili ne olursa olsun aynı.
            let locale = Locale(identifier: "tr_TR")
            ordered = items.sorted { a, b in
                let result = a.title.compare(b.title, options: [.caseInsensitive, .numeric, .widthInsensitive], range: nil, locale: locale)
                return result == .orderedSame ? a.createdAt > b.createdAt : result == .orderedAscending
            }
        }
        return ordered.map(\.id)
    }

    /// Açılanlar açılış zamanına göre (en yeni üstte); hiç açılmayanlar sonda, eklenme tarihine göre.
    private static func recentlyOpenedFirst(_ a: Item, _ b: Item) -> Bool {
        switch (a.openedAt, b.openedAt) {
        case let (x?, y?): return x != y ? x > y : a.createdAt > b.createdAt
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none): return a.createdAt > b.createdAt
        }
    }
}

/// "YouTube dersleri": Ders Stüdyosu'nda işlenmiş videolar.
struct VideoLibraryView: View {
    /// Açılır açılmaz "Yeni video" ekranını göster.
    var openImport = false
    /// Açılır açılmaz bu dersi aç (hata ayıklama demosu).
    var openLesson: UUID? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Query(sort: \VideoLesson.createdAt, order: .reverse) private var lessons: [VideoLesson]
    @State private var search = ""
    @State private var favoritesOnly = false
    @State private var showImport = false
    @State private var didAutoOpen = false
    @State private var path: [UUID] = []
    @State private var toDelete: VideoLesson?
    @State private var pendingCount = 0
    @State private var tagFilter: String?
    @State private var tool: LibraryTool?
    @AppStorage(VideoLibrarySort.key) private var sort: VideoLibrarySort = .added
    /// Derslerin son açılış zamanları (LessonOpenLog'un sakladığı sözlük). Her çizimde UserDefaults okunmasın diye
    /// ekran görününce ve bir dersten dönünce bir kez alınır.
    @State private var opened: [String: Double] = [:]
    #if DEBUG
    @State private var demoSheet: DemoSheet?

    private struct DemoSheet: Identifiable {
        let id = UUID()
        let sheet: LessonSheet
        let player: VideoPlayerModel
    }
    #endif

    /// Kütüphane araçları (menüden açılan sayfalar).
    private enum LibraryTool: String, Identifiable {
        case search, channels, storage
        var id: String { rawValue }
    }

    private static var debugLinks: String? {
        #if DEBUG
        DebugArg.value("libLinks")?.replacingOccurrences(of: "|", with: "\n")
        #else
        nil
        #endif
    }

    private var filtered: [VideoLesson] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let matching = lessons.filter { lesson in
            if favoritesOnly && !lesson.favorite { return false }
            if let tagFilter, !lesson.tags.contains(tagFilter) { return false }
            guard !query.isEmpty else { return true }
            return lesson.title.localizedStandardContains(query) || lesson.channel.localizedStandardContains(query)
                || lesson.tags.contains { $0.localizedStandardContains(query) }
        }
        // Sorgu zaten eklenme tarihine göre sıralı gelir.
        guard sort != .added else { return matching }
        let items = matching.map { lesson in
            VideoLibraryOrder.Item(id: lesson.id, title: lesson.title.isEmpty ? lesson.url : lesson.title, createdAt: lesson.createdAt,
                                   openedAt: opened[lesson.id.uuidString].map { Date(timeIntervalSince1970: $0) },
                                   progress: lesson.duration > 0 ? min(1, max(0, lesson.lastPosition / lesson.duration)) : 0)
        }
        let byID = Dictionary(matching.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return VideoLibraryOrder.sorted(items, by: sort).compactMap { byID[$0] }
    }

    private func refreshOpened() {
        opened = (UserDefaults.standard.dictionary(forKey: LessonOpenLog.key) as? [String: Double]) ?? [:]
    }

    private var clearFiltersButton: some View {
        Button("Süzgeci temizle", systemImage: "line.3.horizontal.decrease.circle") {
            tagFilter = nil
            favoritesOnly = false
        }
        .buttonStyle(.bordered)
    }

    private var allTags: [(tag: String, count: Int)] { TagLogic.counts(lessons.map(\.tags)) }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if lessons.isEmpty && pendingCount == 0 {
                    ContentUnavailableView {
                        Label("Henüz YouTube dersi yok", systemImage: "play.rectangle")
                    } description: {
                        Text("Bir ders videosunun bağlantısını ekle: zaman damgalı transkript, bölümler, ders notu ve tahta/slayt kareleri hazırlansın.")
                    } actions: {
                        Button("Yeni video", systemImage: "plus") { showImport = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    list
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Videolar")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                if let lesson = lessons.first(where: { $0.id == id }) {
                    VideoLessonView(lesson: lesson, closeStudio: { dismiss() })
                        .onAppear { LessonOpenLog.touch(id) }
                } else {
                    ContentUnavailableView("Ders bulunamadı", systemImage: "questionmark.video")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if !lessons.isEmpty {
                        Button(favoritesOnly ? "Tümünü göster" : "Yalnızca favoriler",
                               systemImage: favoritesOnly ? "star.fill" : "star") { favoritesOnly.toggle() }
                    }
                    Menu {
                        if lessons.count > 1 {
                            Section("Sırala") {
                                Picker("Sırala", selection: $sort) {
                                    ForEach(VideoLibrarySort.allCases) { Text($0.label).tag($0) }
                                }
                            }
                        }
                        Button("Kütüphanede ara", systemImage: "magnifyingglass") { tool = .search }
                        Button("Takip edilen kanallar", systemImage: "dot.radiowaves.left.and.right") { tool = .channels }
                        Button("Depolama", systemImage: "internaldrive") { tool = .storage }
                    } label: {
                        Label("Daha fazla", systemImage: "ellipsis.circle")
                    }
                    Button("Yeni video", systemImage: "plus") { showImport = true }
                }
            }
            .sheet(isPresented: $showImport, onDismiss: refreshPending) {
                YouTubeImportView(initialURL: Self.debugLinks) { lesson in
                    showImport = false
                    path = [lesson.id]
                }
            }
            .sheet(item: $tool) { which in
                switch which {
                case .search:
                    LibrarySearchView(lessons: lessons) { id, time in
                        tool = nil
                        if let lesson = lessons.first(where: { $0.id == id }), time > 0 {
                            lesson.lastPosition = time
                            try? context.save()
                        }
                        path = [id]
                    }
                case .channels: FollowedChannelsView()
                case .storage: StorageView()
                }
            }
            .confirmationDialog("Video dersi silinsin mi?",
                                isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Sil", role: .destructive) {
                    if let lesson = toDelete { delete(lesson) }
                }
            } message: {
                Text("Transkript, notlar, kaydedilen kareler ve indirilen ses bu cihazdan kalıcı olarak silinir.")
            }
            #if DEBUG
            .sheet(item: $demoSheet) { item in
                if let lesson = lessons.first(where: { $0.title.contains("Demo ·") }), let transcript = lesson.transcript {
                    LessonSheetHost(sheet: item.sheet, context: LessonContext(lesson: lesson, transcript: transcript, player: item.player, update: { _ in }))
                }
            }
            .task {
                guard LibraryDemo.isRequested else { return }
                try? await Task.sleep(for: .seconds(1))
                if let name = LibraryDemo.libraryTool { tool = LibraryTool(rawValue: name) }
                if Self.debugLinks != nil { showImport = true }
                if let name = LibraryDemo.lessonTool, let item = LibraryDemo.sheet(for: name),
                   let lesson = lessons.first(where: { $0.title.contains("Demo ·") }) {
                    demoSheet = DemoSheet(sheet: item, player: VideoPlayerModel(videoID: lesson.videoID, startAt: 0, duration: lesson.duration,
                                                                               embeddable: true, audioURL: nil, videoURL: nil))
                }
            }
            #endif
            // Kısayollar'dan gelen bağlantı: ekran açıksa "Yeni video" ekranı açılır (içe aktarma ekranı bağlantıyı alır).
            .onChange(of: app.pendingImportLinks, initial: true) { _, text in
                if text?.isEmpty == false { showImport = true }
            }
            // Dersten dönülünce açılış zamanları yenilenir: "Son açılan" sırasında o ders üste çıkar.
            .onChange(of: path) { _, new in
                if new.isEmpty { refreshOpened() }
            }
            .onAppear {
                refreshPending()
                refreshOpened()
                if openImport && !didAutoOpen {
                    didAutoOpen = true
                    showImport = true
                }
                if let openLesson, !didAutoOpen {
                    didAutoOpen = true
                    path = [openLesson]
                }
            }
        }
        .debugNarrowScreen()
    }

    private var list: some View {
        // Süzme, sıralama ve etiket sayımı çizim başına bir kez yapılır.
        let shown = filtered
        let tags = allTags
        return List {
            if search.isEmpty && !favoritesOnly && tagFilter == nil,
               let recent = lessons.filter({ $0.lastPosition > 0 && ($0.duration <= 0 || $0.lastPosition < $0.duration - 5) && opened[$0.id.uuidString] != nil })
                .max(by: { (opened[$0.id.uuidString] ?? 0) < (opened[$1.id.uuidString] ?? 0) }) {
                Section("Kaldığın yerden") {
                    NavigationLink(value: recent.id) {
                        OkuRouteLabel(title: recent.title, detail: "\(recent.lastPosition.clockText) konumundan devam et", symbol: "play.fill")
                    }.listRowInsets(EdgeInsets())
                }
            }
            queueBanner
            if !tags.isEmpty {
                Section {
                    Menu {
                        Picker("Etiket", selection: $tagFilter) {
                            Text("Tümü").tag(String?.none)
                            ForEach(tags, id: \.tag) { item in
                                Text("\(item.tag) (\(item.count))").tag(String?.some(item.tag))
                            }
                        }
                    } label: {
                        Label(tagFilter ?? "Etikete göre süz", systemImage: "tag")
                    }
                }
            }
            if pendingCount > 0 {
                Section {
                    Button {
                        showImport = true
                    } label: {
                        Label("\(pendingCount) yarım kalan işlem var — sonucu al", systemImage: "clock.arrow.circlepath")
                    }
                }
            }
            Section {
                ForEach(shown) { lesson in
                    NavigationLink(value: lesson.id) {
                        VideoLessonRow(lesson: lesson)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Sil", systemImage: "trash", role: .destructive) { toDelete = lesson }
                    }
                    .swipeActions(edge: .leading) {
                        Button(lesson.favorite ? "Favoriden çıkar" : "Favori", systemImage: lesson.favorite ? "star.slash" : "star") {
                            lesson.favorite.toggle()
                            try? context.save()
                        }
                        .tint(.yellow)
                    }
                    .contextMenu {
                        Button(lesson.favorite ? "Favoriden çıkar" : "Favorilere ekle", systemImage: "star") {
                            lesson.favorite.toggle()
                            try? context.save()
                        }
                        if let url = YouTubeLink.watchURL(videoID: lesson.videoID, at: lesson.lastPosition) {
                            Link(destination: url) { Label("YouTube’da aç", systemImage: "arrow.up.right.square") }
                        }
                        Button("Sil", systemImage: "trash", role: .destructive) { toDelete = lesson }
                    }
                }
            } footer: {
                if !lessons.isEmpty {
                    Text("\(lessons.count) video · toplam \(VideoTime.string(lessons.reduce(0) { $0 + $1.duration }))")
                }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Başlık veya kanal ara")
        .overlay {
            if shown.isEmpty && !lessons.isEmpty {
                if search.isEmpty && tagFilter != nil {
                    ContentUnavailableView {
                        Label("Bu etikette video yok", systemImage: "tag")
                    } actions: {
                        clearFiltersButton
                    }
                } else if search.isEmpty {
                    ContentUnavailableView {
                        Label("Favori video yok", systemImage: "star")
                    } description: {
                        Text("Bir satırı sağa kaydırıp favorilere ekleyebilirsin.")
                    } actions: {
                        clearFiltersButton
                    }
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
        // Seçili etiketi taşıyan son ders silinir ya da etiketi kaldırılırsa etiket menüsü de kaybolabilir:
        // süzgeç takılı kalıp listeyi boş bırakmasın.
        .onChange(of: tags.map(\.tag), initial: true) { _, names in
            if let tagFilter, !names.contains(tagFilter) { self.tagFilter = nil }
        }
    }

    /// Takip edilen kanallardan gelen videoların otomatik işlenmesi.
    @ViewBuilder
    private var queueBanner: some View {
        let runner = app.importQueue
        if runner.isRunning, let title = runner.currentTitle {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Otomatik işleniyor (\(runner.queued) video sırada)", systemImage: "bolt.fill").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    Text(title).font(.subheadline).lineLimit(2)
                    ProgressView(value: runner.progress)
                    Text(runner.step).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        } else if runner.queued > 0 {
            Section {
                Button {
                    runner.kick(context: context)
                } label: {
                    Label("\(runner.queued) yeni video işlenmeyi bekliyor — başlat", systemImage: "bolt.badge.clock")
                }
            }
        }
    }

    private func refreshPending() {
        pendingCount = YouTubePendingJobs.all.count
    }

    private func delete(_ lesson: VideoLesson) {
        path.removeAll { $0 == lesson.id }
        LessonOpenLog.forget(lesson.id)
        LessonAudioPreference.set(lesson.id, false)
        AskHistory.forget(lesson: lesson.id)
        lesson.removeFiles()
        context.delete(lesson)
        try? context.save()
        toDelete = nil
    }
}

struct VideoLessonRow: View {
    var lesson: VideoLesson
    /// Satıra önerilen genişlik (ölçülene dek 0 = yan yana düzen).
    @State private var rowWidth: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Dar satırda (Ekran Büyütme: 320 pt) ya da erişilebilirlik yazı boyutunda başlık tam genişliğe çıkar; küçük resim ve
    /// ayrıntılar altına iner. Yan yana düzende başlığa ~15 karakterlik sütun kalıyor, aynı kanalın dersleri ayırt edilemiyordu.
    nonisolated static func stacksTitle(rowWidth: CGFloat, accessibilitySize: Bool) -> Bool {
        accessibilitySize || (rowWidth > 0 && rowWidth < 290)
    }

    var body: some View {
        let stacked = Self.stacksTitle(rowWidth: rowWidth, accessibilitySize: typeSize.isAccessibilitySize)
        // Küçük resim iki düzende de aynı yerde durur (yalnız başlık yer değiştirir): düzen değişince resim yeniden yüklenmez.
        VStack(alignment: .leading, spacing: 6) {
            if stacked { titleLine }
            HStack(alignment: stacked ? .top : .center, spacing: stacked ? 10 : 12) {
                thumbnail(width: stacked ? 80 : 96)
                VStack(alignment: .leading, spacing: 3) {
                    if !stacked { titleLine }
                    meta
                }
            }
        }
        // Ölçülen, içeriğin değil satıra önerilen genişliktir (kısa başlıklı satır dar sayılmasın).
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func thumbnail(width: CGFloat) -> some View {
        AsyncImage(url: lesson.thumbnailURL.flatMap { URL(string: $0) } ?? YouTubeLink.thumbnailURL(videoID: lesson.videoID)) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Rectangle().fill(.quaternary)
                Image(systemName: "play.rectangle").foregroundStyle(.secondary)
            }
        }
        .frame(width: width, height: width * 9 / 16)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottomTrailing) {
            Text(VideoTime.string(lesson.duration))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                .padding(3)
        }
    }

    private var titleLine: some View {
        HStack(alignment: .top, spacing: 4) {
            Text(lesson.title.isEmpty ? lesson.url : lesson.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(3)
            if lesson.favorite {
                Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
            }
        }
    }

    @ViewBuilder
    private var meta: some View {
        if !lesson.channel.isEmpty {
            Text(lesson.channel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        if !lesson.tags.isEmpty {
            Label(lesson.tags.prefix(3).joined(separator: " · "), systemImage: "tag")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        // Sığarsa tam rozetler; sığmazsa yalnız simge; o da sığmazsa alt alta (dar ekran, büyük yazı).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { badges(compact: false) }
            HStack(spacing: 6) { badges(compact: true) }
            VStack(alignment: .leading, spacing: 4) { badges(compact: true) }
        }
    }

    @ViewBuilder
    private func badges(compact: Bool) -> some View {
        if !lesson.source.isEmpty {
            Text(lesson.sourceTitle)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(badgeColor.opacity(0.15), in: Capsule())
                .foregroundStyle(badgeColor)
        }
        if lesson.audioFileName != nil {
            Group {
                if compact {
                    Image(systemName: "headphones")
                } else {
                    Label("Çevrimdışı ses", systemImage: "headphones").lineLimit(1)
                }
            }
            .font(.caption2.weight(.semibold))
            .fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.goldInk.opacity(0.15), in: Capsule())
            .foregroundStyle(Theme.goldInk)
            .accessibilityLabel("Çevrimdışı ses indirildi")
        }
        if lesson.lastPosition > 5 && lesson.duration > 0 {
            let percent = Int(min(1, lesson.lastPosition / lesson.duration) * 100)
            Text(compact ? "%\(percent)" : "%\(percent) izlendi")
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).fixedSize()
                .accessibilityLabel("Yüzde \(percent) izlendi")
        }
    }

    private var badgeColor: Color {
        switch lesson.source {
        case "captions": .green
        case "auto-captions": .blue
        default: Theme.blueInk
        }
    }
}
