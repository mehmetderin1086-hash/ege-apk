import SwiftData
import SwiftUI

/// Günlük çalışma ve niyete göre erişilen araçlar. Veri ve çalışma yolları ortaktır.
struct StudyHub: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isModuleActive) private var moduleActive
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query private var cards: [ReviewCard]
    @Query private var mistakes: [MistakeEntry]
    @Query(sort: \Episode.createdAt, order: .reverse) private var episodes: [Episode]
    @Query(filter: #Predicate<EpisodeProbe> { $0.completedAt == nil }) private var openProbes: [EpisodeProbe]
    @State private var sheet: Sheet?
    @State private var pickFor: PickKind?
    @State private var tool: ToolKind?
    @State private var toolBadges: [ToolKind: Int] = [:]
    @State private var showCatalog = false
    @State private var search = ""
    @State private var category: CatalogGroup = .all

    enum Sheet: String, Identifiable { case continuity, continueLearning, tutor, today, review, mistakes, notes, bookNotebook, focus, plan, workout, ask, exam, stats, vocab, diagnostics, youtube, youtubeNew, listening, probes, topics; var id: String { rawValue } }
    enum PickKind: String, Identifiable { case labelQuiz, quiz, feynman, socratic; var id: String { rawValue } }

    private enum CatalogGroup: String, CaseIterable, Identifiable {
        case all = "Tüm araçlar", review = "Tekrar ve kartlar", questions = "Soru ve sınav"
        case understand = "Anla ve anlat", sources = "Not ve kaynak", plan = "Plan ve odak"
        case brain = "Zihin antrenmanı", utility = "Pratik araçlar"
        var id: String { rawValue }
    }
    private enum Route {
        case sheet(Sheet), pick(PickKind), tool(ToolKind)
        var id: String {
            switch self {
            case .sheet(let value): "sheet." + value.rawValue
            case .pick(let value): "pick." + value.rawValue
            case .tool(let value): "tool." + value.rawValue
            }
        }
    }
    private struct CatalogItem: Identifiable {
        var title: String
        var detail: String
        var symbol: String
        var tint: Color
        var group: CatalogGroup
        var route: Route
        var id: String { route.id }
    }

    private var dueProbeCount: Int {
        ProbeScheduler.dueEpisodeCount(openProbes.map { (episodeID: $0.episodeID, due: $0.dueDate) }, endOfToday: ProbeScheduler.endOfDay(.now))
    }
    private var readyEpisodes: [Episode] { episodes.filter { $0.status == .ready } }
    private var todayPlan: StudyTodayPlan {
        StudyTodayPlan(counts: [.cards: cards.filter(\.isDue).count, .mistakes: mistakes.filter { !$0.resolved }.count, .probes: dueProbeCount])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    Button { sheet = .tutor } label: {
                        BigRow(title: "Öğrenme Merkezi", detail: "14 ders · AI öğretmen · Sokratik öğrenme · sınava hazırlık", symbol: "graduationcap.fill", tone: .sky)
                    }
                    .buttonStyle(PressableCardStyle(reduceMotion: false))
                    .accessibilityIdentifier("study.tutor")
                    intent("Öğrenme geçmişim", "Soru, ses, kart, yazılı ve deney çalışmalarını birlikte gör.", "brain.head.profile", .sky, .sheet(.continuity))
                    quickActions
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Nasıl çalışmak istersin?", detail: "Bir hedef seç, hemen başla.")
                        if cards.isEmpty {
                            intent("İlk kartını oluştur", "Kendi kartını yaz veya hazır kartlarını içe aktar.", "rectangle.stack.badge.plus", .blue, .tool(.cardCreate))
                        } else {
                            intent("Kartlarla tekrar", "\(cards.filter(\.isDue).count) kartın bugün tekrar zamanı geldi.", "rectangle.on.rectangle.angled", .blue, .sheet(.review))
                        }
                        intent("Dinlediğini sına", readyEpisodes.isEmpty ? "Hazır bir podcast bölümünden kısa quiz oluştur." : "\(readyEpisodes.count) hazır bölüm arasından seç ve quiz çöz.", "headphones", .yellow, .pick(.quiz))
                        intent("Okuduğunu hatırla", "Kitap alıntılarını ve notlarını çalışma kartlarına dönüştür.", "book.closed.circle", .navy, .sheet(.bookNotebook))
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Çalışma araçların", detail: "Notlar, odak, sınav ve daha fazlası.")
                        Button { showCatalog = true } label: {
                            BigRow(title: "Tüm araçları keşfet", detail: "\(catalogItems.count) araç içinde ara veya kategori seç.", symbol: "square.grid.2x2", tone: .sky)
                        }
                        .buttonStyle(PressableCardStyle(reduceMotion: false))
                        .accessibilityIdentifier("study.catalog")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(Theme.canvas)
            .navigationTitle("Çalış")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { ToolbarItem(placement: .topBarLeading) { HomeButton() }; ToolbarItem(placement: .topBarTrailing) { ModuleMenu(module: .study) { EmptyView() } } }
            .navigationDestination(isPresented: $showCatalog) { catalog }
            .onAppear {
                if sheet == nil, let raw = DebugArg.value("openSheet"), let value = Sheet(rawValue: raw) { sheet = value }
                if tool == nil, let raw = DebugArg.value("openTool"), let value = ToolKind(rawValue: raw) { tool = value }
                if pickFor == nil, let raw = DebugArg.value("openPick"), let value = PickKind(rawValue: raw) { pickFor = value }
                refreshToolBadges()
                FocusTimer.reconcileSaved(context: context)
            }
            .onChange(of: tool) { refreshToolBadges() }
            // Canlı tutulan modüle dönülünce onAppear tetiklenmez: rozetler burada tazelenir.
            .onChange(of: moduleActive) { _, active in if active { refreshToolBadges() } }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                refreshToolBadges()
                FocusTimer.reconcileSaved(context: context)
            }
            .sheet(item: $tool) { $0.destination }
            .sheet(item: $sheet) { which in
                switch which {
                case .continuity: LearningContinuityView()
                case .continueLearning: LearningContinueView()
                case .tutor: TutorHub()
                case .today: TodayReviewView()
                case .review: ReviewView()
                case .mistakes: MistakeBookView()
                case .notes: CornellNotesView()
                case .bookNotebook: BookNotebookView()
                case .focus: FocusTimerView()
                case .plan: StudyPlanView()
                case .workout: DailyWorkoutView()
                case .ask: LibraryAskView()
                case .exam: ExamSimulatorView()
                case .stats: ProgressChartsView()
                case .vocab: FormulaCardsView()
                case .diagnostics: DiagnosticsView()
                case .youtube: VideoLibraryView()
                case .youtubeNew: VideoLibraryView(openImport: true)
                case .listening: LearningSettingsView()
                case .probes: ProbeListView()
                case .topics: NavigationStack { TopicTreeView() }
                }
            }
            .sheet(item: $pickFor) { kind in EpisodePicker(kind: kind, episodes: readyEpisodes) }
        }
    }

    private var hero: some View {
        let plan = todayPlan
        let summary = plan.steps.map { step in
            let name: String = switch step { case .cards: "kart"; case .mistakes: "yanlış"; case .probes: "yoklama" }
            return "\(plan.counts[step] ?? 0) \(name)"
        }.joined(separator: " · ")
        return ScreenHero(eyebrow: "Çalış",
                          title: plan.total > 0 ? summary : "Bugün bekleyen tekrarın yok.",
                          subtitle: plan.total > 0 ? "Kartlar, yanlışlar ve sorular tek çalışma akışında." : "Yeni bir konu seçebilir veya kendi hızında çalışabilirsin.",
                          symbol: plan.total > 0 ? "arrow.triangle.2.circlepath" : "checkmark.seal")
    }

    private var quickActions: some View {
        let plan = todayPlan
        let columns = typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            BigActionButton(title: plan.total > 0 ? "Tekrara başla" : "Tekrar durumunu gör", symbol: "arrow.right", style: .yellow) { sheet = .today }
                .accessibilityIdentifier("study.today")
                .accessibilityHint("Kartlar, yanlışlar, yoklamalar ve sorular sırayla açılır")
            BigActionButton(title: "Odak oturumu", symbol: "timer", style: .blue) { sheet = .focus }
            BigActionButton(title: "Deneme sınavı", symbol: "stopwatch", style: .outline) { sheet = .exam }
            BigActionButton(title: "Yanlış defteri", symbol: "xmark.circle", style: .outline) { sheet = .mistakes }
        }
    }

    private func intent(_ title: String, _ detail: String, _ symbol: String, _ tone: BigRow.Tone, _ route: Route) -> some View {
        Button { open(route) } label: {
            BigRow(title: title, detail: detail, symbol: symbol, tone: tone)
        }
        .buttonStyle(PressableCardStyle(reduceMotion: false))
        .accessibilityIdentifier("study." + route.id)
    }

    private var catalog: some View {
        List {
            Section {
                Menu {
                    Picker("Kategori", selection: $category) {
                        ForEach(CatalogGroup.allCases) { group in Text(group.rawValue).tag(group) }
                    }
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Kategori").font(.caption).foregroundStyle(.secondary)
                            Text(category.rawValue).font(.headline).foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "line.3.horizontal.decrease").accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Kategori, \(category.rawValue)")
                .accessibilityIdentifier("study.catalog.category")
            }
            let matched = catalogItems.filter {
                (category == .all || $0.group == category) && StudySearch.matches([$0.title, $0.detail, $0.group.rawValue], query: search)
            }
            if matched.isEmpty {
                ContentUnavailableView.search(text: search)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(CatalogGroup.allCases.filter { $0 != .all }) { group in
                    let items = matched.filter { $0.group == group }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { item in
                                Button { open(item.route) } label: {
                                    OkuRouteLabel(title: item.title, detail: detail(for: item), symbol: item.symbol, tint: item.tint)
                                        .padding(.vertical, 5)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("study.catalog." + item.id)
                            }
                        } header: { Text(group.rawValue).accessibilityAddTraits(.isHeader) }
                    }
                }
            }
        }
        .navigationTitle("Çalışma araçları")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Araç veya çalışma biçimi ara")
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
    }

    private func open(_ route: Route) {
        switch route {
        case .sheet(let value): sheet = value
        case .pick(let value): pickFor = value
        case .tool(let value): tool = value
        }
    }

    private func detail(for item: CatalogItem) -> String {
        let count: Int = switch item.route {
        case .sheet(.review): cards.filter(\.isDue).count
        case .sheet(.mistakes): mistakes.filter { !$0.resolved }.count
        case .sheet(.probes): dueProbeCount
        case .tool(let value): toolBadges[value] ?? 0
        default: 0
        }
        return count > 0 ? "\(count) bekleyen · \(item.detail)" : item.detail
    }

    private func refreshToolBadges() {
        toolBadges = Dictionary(uniqueKeysWithValues: ToolKind.allCases.map { ($0, $0.badge) })
    }

    private var catalogItems: [CatalogItem] {
        let core: [CatalogItem] = [
            .init(title: "Kitap defterim", detail: "Kitap alıntıları, yer imleri ve kaynağa bağlı çalışma kartları.", symbol: "book.closed.circle", tint: .accentColor, group: .sources, route: .sheet(.bookNotebook)),
            .init(title: "Bugünkü tekrar", detail: "Zamanı gelen bütün çalışmalarını sırayla tamamla.", symbol: "checklist", tint: .accentColor, group: .review, route: .sheet(.today)),
            .init(title: "Aralıklı tekrar", detail: "Zamanı gelen kartları hatırla ve değerlendir.", symbol: "rectangle.on.rectangle.angled", tint: Theme.blueInk, group: .review, route: .sheet(.review)),
            .init(title: "Yanlış defteri", detail: "Takıldığın sorulara yeniden dön.", symbol: "xmark.circle", tint: .red, group: .review, route: .sheet(.mistakes)),
            .init(title: "Yoklamalar", detail: "Dinlediğin konuları kısa sorularla hatırla.", symbol: "checklist.checked", tint: Theme.goldInk, group: .review, route: .sheet(.probes)),
            .init(title: "Kavram ve formül kartları", detail: "Temel kavramları ve formülleri gözden geçir.", symbol: "function", tint: Theme.goldInk, group: .review, route: .sheet(.vocab)),
            .init(title: "Deneme sınavı", detail: "Süre tutarak kendini sınava hazırla.", symbol: "stopwatch", tint: .red, group: .questions, route: .sheet(.exam)),
            .init(title: "Bölüm quizi", detail: "Hazır podcast bölümünü seç, öğrendiklerini sına.", symbol: "checklist", tint: Theme.goldInk, group: .understand, route: .pick(.quiz)),
            .init(title: "Feynman: sen anlat", detail: "Seçtiğin bölümü kendi cümlelerinle anlat.", symbol: "person.wave.2", tint: Theme.goldInk, group: .understand, route: .pick(.feynman)),
            .init(title: "Sokratik sınama", detail: "Bölümdeki fikirleri yönlendirici sorularla tartış.", symbol: "bubble.left.and.text.bubble.right", tint: Theme.blueInk, group: .understand, route: .pick(.socratic)),
            .init(title: "Etiketleri tahmin et", detail: "Kaynak şekillerin gizlenen etiketlerini bul.", symbol: "photo.badge.magnifyingglass", tint: .orange, group: .understand, route: .pick(.labelQuiz)),
            .init(title: "Cornell notları", detail: "İpuçlarını, notlarını ve özetini birlikte tut.", symbol: "note.text", tint: .brown, group: .sources, route: .sheet(.notes)),
            .init(title: "Kütüphaneye sor", detail: "Kitaplığındaki içeriklerden yanıt ara.", symbol: "questionmark.bubble", tint: Theme.goldInk, group: .sources, route: .sheet(.ask)),
            .init(title: "YouTube dersleri", detail: "Kaydettiğin videoları ve derslerini aç.", symbol: "play.rectangle", tint: .red, group: .sources, route: .sheet(.youtube)),
            .init(title: "YouTube videosu ekle", detail: "Bir bağlantıdan yeni ders kaynağı ekle.", symbol: "plus.rectangle.on.rectangle", tint: .orange, group: .sources, route: .sheet(.youtubeNew)),
            .init(title: "Konularım", detail: "Konuları ve alt başlıklarını bir arada gör.", symbol: "list.bullet.indent", tint: .orange, group: .sources, route: .sheet(.topics)),
            .init(title: "Odak oturumu", detail: "Bir süre belirle ve çalışmaya odaklan.", symbol: "timer", tint: .blue, group: .plan, route: .sheet(.focus)),
            .init(title: "Çalışma planı", detail: "Hangi gün ne çalışacağını düzenle.", symbol: "calendar.badge.clock", tint: Theme.blueInk, group: .plan, route: .sheet(.plan)),
            .init(title: "Günlük antrenman", detail: "Günlük çalışma oturumunu başlat.", symbol: "figure.walk", tint: .green, group: .plan, route: .sheet(.workout)),
            .init(title: "Gelişim ve rapor", detail: "Çalışma süreni ve ilerlemeni incele.", symbol: "chart.bar", tint: .green, group: .plan, route: .sheet(.stats)),
            .init(title: "Tanı ve bağlantı kontrolü", detail: "Uygulamanın hizmet ve bağlantı durumunu denetle.", symbol: "stethoscope", tint: .gray, group: .utility, route: .sheet(.diagnostics))
        ]
        return core + ToolKind.allCases.map { kind in
            CatalogItem(title: kind.title, detail: toolDetail(kind), symbol: kind.symbol, tint: kind.color, group: toolGroup(kind), route: .tool(kind))
        }
    }

    private func toolGroup(_ kind: ToolKind) -> CatalogGroup {
        switch kind {
        case .mockExams, .questionLog, .questionTimer: .questions
        case .grades, .absences, .countdowns, .habits, .goals, .todos, .revisions, .badges, .heatMap: .plan
        case .journal, .reading: .sources
        case .cardBrowser, .cardCreate, .typeReview, .matchGame: .review
        case .mentalMath, .speedRead, .schulte, .digitSpan, .breathing: .brain
        case .calculator, .units, .periodicTable, .whiteboard, .quotes: .utility
        }
    }

    private func toolDetail(_ kind: ToolKind) -> String {
        switch kind {
        case .mockExams: "Deneme sonuçlarını kaydet, değişimi takip et."
        case .grades: "Ders notlarını ve ortalamanı hesapla."
        case .absences: "Devamsızlık kayıtlarını bir arada tut."
        case .countdowns: "Yaklaşan sınavlarına kalan zamanı gör."
        case .questionLog: "Çözdüğün soruları derslere göre kaydet."
        case .questionTimer: "Bir soruya ayırdığın süreyi ölç."
        case .habits: "Tekrarlanan çalışma alışkanlıklarını takip et."
        case .goals: "Hedeflerini tanımla ve ilerlemeni kaydet."
        case .todos: "İşlerini önem ve aciliyete göre sırala."
        case .journal: "Bugün öğrendiklerini ve düşüncelerini yaz."
        case .revisions: "Konuların tekrar günlerini planla."
        case .reading: "Okuduğun kitapları ve sayfaları kaydet."
        case .badges: "Çalışma başarılarını ve rozetlerini gör."
        case .heatMap: "Çalıştığın günleri takvim üzerinde incele."
        case .cardBrowser: "Bütün kartlarını ara, gözden geçir ve düzenle."
        case .cardCreate: "Kendi kartını yaz veya kart dosyası içe aktar."
        case .typeReview: "Kartın yanıtını yazarak hatırla."
        case .matchGame: "Birbiriyle ilişkili kartları eşleştir."
        case .mentalMath: "Kısa işlem sorularıyla alıştırma yap."
        case .speedRead: "Metin üzerinde okuma alıştırması yap."
        case .schulte: "Tablodaki sayıları sırayla bul."
        case .digitSpan: "Gösterilen sayı dizisini hatırla."
        case .breathing: "Çalışmaya kısa bir nefes molası ver."
        case .calculator: "Çalışırken gerekli hesaplamaları yap."
        case .units: "Ölçü birimleri arasında dönüştürme yap."
        case .periodicTable: "Elementlerin özelliklerini incele."
        case .whiteboard: "Düşüncelerini çizimle düzenle."
        case .quotes: "Kaydettiğin sözleri gözden geçir."
        }
    }
}

/// Bölüm seçtir, sonra ilgili aracı aç.
struct EpisodePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    var kind: StudyHub.PickKind
    var episodes: [Episode]
    @State private var chosen: Episode?
    @State private var query = ""
    /// Şekil ve soru sayıları: her satır çiziminde diskten/JSON'dan yeniden okunmasın diye bir kez hesaplanır.
    @State private var info: [UUID: (figures: Int, questions: Int)] = [:]

    private var title: String {
        switch kind {
        case .labelQuiz: "Şekil için bölüm seç"
        case .quiz: "Quiz için bölüm seç"
        case .feynman: "Anlatacağın bölümü seç"
        case .socratic: "Sınama için bölüm seç"
        }
    }

    struct Row: Equatable {
        var note: String?
        /// Not bir eksiği bildiriyor (turuncu).
        var warns = false
        var locked = false
    }

    /// Satırın alt metni ve kilidi. Sayılar henüz okunmadıysa (nil) satır kilitlenmez.
    /// Quiz hiç kilitlenmez: paketi olmayan bölüm açılınca "Oluştur" ekranı gelir.
    static func row(kind: StudyHub.PickKind, figures: Int?, questions: Int?) -> Row {
        switch kind {
        case .labelQuiz:
            guard let figures else { return Row() }
            return figures == 0 ? Row(note: "Kaynak şekli yok (deste ekranından kitap fotoğrafı ekle)", warns: true, locked: true)
                                : Row(note: "\(figures) şekil")
        case .quiz:
            guard let questions else { return Row() }
            return Row(note: questions == 0 ? "Quiz henüz yok, açınca oluşturabilirsin" : "\(questions) soru")
        case .socratic:
            return questions == 0 ? Row(note: "Önce bu bölümün quiz'ini oluştur", warns: true, locked: true) : Row()
        case .feynman:
            return Row()
        }
    }

    var body: some View {
        NavigationStack {
            let shown = episodes.filter { StudySearch.matches([$0.title], query: query) }
            List {
                if episodes.isEmpty {
                    ContentUnavailableView {
                        Label("Henüz hazır bölüm yok", systemImage: "headphones")
                    } description: {
                        Text("Kitaplık'ta bir podcast oluştur. Hazır olduğunda burada seçip onunla çalışabilirsin.")
                    } actions: {
                        Button("Kitaplığa git") {
                            app.selectedTab = .library
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(minHeight: 44)
                    }
                } else if shown.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
                ForEach(shown) { episode in
                    let row = Self.row(kind: kind, figures: info[episode.id]?.figures, questions: info[episode.id]?.questions)
                    Button {
                        chosen = episode
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(episode.title).font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            if let note = row.note {
                                Text(note).font(.caption).foregroundStyle(row.warns ? .orange : .secondary)
                            }
                        }
                        .frame(minHeight: 44, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                    .disabled(row.locked)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } } }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Bölüm ara")
            // Açılışta ve açılan araç kapanınca (yeni quiz oluşturulmuş olabilir) yenilenir.
            .task(id: chosen?.id) { if chosen == nil { loadInfo() } }
            .sheet(item: $chosen) { episode in
                switch kind {
                case .labelQuiz: LabelQuizView(episode: episode)
                case .quiz:
                    NavigationStack {
                        StudyView(episode: episode, initialMode: .quiz)
                            .navigationTitle(episode.title)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { chosen = nil } } }
                            .debugNarrowScreen()
                    }
                case .feynman: FeynmanView(episode: episode)
                case .socratic: NavigationStack { CoachHub(episode: episode) }
                }
            }
            .debugNarrowScreen()
        }
    }

    private func loadInfo() {
        var out: [UUID: (figures: Int, questions: Int)] = [:]
        for episode in episodes {
            out[episode.id] = (figures: kind == .labelQuiz ? episode.sourceFigures.count : 0,
                               questions: kind == .quiz || kind == .socratic ? (episode.study?.quiz.count ?? 0) : 0)
        }
        info = out
    }
}
