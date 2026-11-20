import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// #16: bölüm ekranı yalnız göz atar; oynatıcıyı kendiliğinden yüklemez. Başka bölüm çalarken bu bölümün metni
/// `episode.timeline`'dan gösterilir, "Bunu çal" ile çalınır.
struct EpisodeDetailView: View {
    @Bindable var episode: Episode
    @Environment(AppState.self) private var app
    @Environment(PlayerController.self) private var player
    @Environment(GenerationCoordinator.self) private var generator
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab = Tab.transcript
    @State private var showAsk = false
    @State private var showActions = false
    @State private var showDeck = false
    @State private var onTheRoad = false
    /// Sayfa şu an görünür mü (üstüne başka sayfa itilmemiş, başka sekmede değil).
    @State private var onScreen = false
    /// Kitaplık canlı tutulur: başka modüldeyken seri ilerlemesi bu sayfayı yeni bölüme çevirmesin.
    @Environment(\.isModuleActive) private var moduleActive
    @State private var confirmDelete = false
    @State private var noteTarget: TimedTurn?
    @State private var rewriteScene: Int?
    @State private var studioScene: Int?
    @State private var fixTarget: FixTarget?
    @State private var clipTarget: ClipTarget?
    @State private var pdfPage: PDFTarget?
    @State private var imagePage: URL?
    @State private var pdfChoices: PDFChoice?
    @State private var pageError: String?
    /// "Konuma git" isteği (çalmadan): metin oraya kayar, "Bunu çal" oradan başlar.
    @State private var focusTime: Double?
    @State private var wordTimes: [Int: [Double]]?
    /// #20: elle "Kelime senkronunu hazırla" bitince artar; kelime zamanları yeniden yüklenir.
    @State private var wordSyncToken = 0
    /// #21: işlemler sayfasından istenen sunum; sayfa tamamen kapandıktan sonra (`onDismiss`) açılır.
    @State private var afterActions: EpisodeActionsFollowUp?
    @AppStorage("showSlides") private var showSlides = true

    enum Tab: String, CaseIterable, Identifiable {
        case transcript = "Metin", chapters = "Bölümler", notes = "Notlar", study = "Çalış"
        var id: String { rawValue }
    }

    private var isCurrent: Bool { player.episode?.id == episode.id }

    /// Bu sayfanın üstünde açık bir kapak, sayfa ya da onay var mı.
    private var isPresenting: Bool {
        showActions || afterActions != nil || showDeck || showAsk || onTheRoad || confirmDelete || noteTarget != nil
            || rewriteScene != nil || studioScene != nil || fixTarget != nil || clipTarget != nil
            || pdfPage != nil || imagePage != nil || pdfChoices != nil || pageError != nil
    }

    var body: some View {
        Group {
            switch episode.status {
            case .ready: readyView
            case .generating: GeneratingEpisodeView(episode: episode)
            case .failed: FailedEpisodeView(episode: episode, onDelete: { confirmDelete = true })
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if episode.status == .ready {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sunum stüdyosu", systemImage: "rectangle.stack.badge.play") { showDeck = true }
                }
                ToolbarItem(placement: .topBarTrailing) { SleepTimerMenu() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if episode.status == .ready {
                    Button { showActions = true } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("Bölüm işlemleri")
                } else {
                    let approval = EpisodeActionStatus.approval(episode.needsApproval, status: episode.status)
                    Menu {
                        // #7: onay ekranı bu sayfanın kendisidir (üretim önizlemesi); menü yalnız durumu yazar.
                        if let approval {
                            Section("Seslendirme onayı") { Label(approval, systemImage: "checkmark.circle") }
                        }
                        Button("Bölümü sil", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: approval == nil ? "ellipsis.circle" : "ellipsis.circle.fill")
                    }
                    .accessibilityLabel(approval.map { "Bölüm işlemleri, seslendirme onayı: \($0)" } ?? "Bölüm işlemleri")
                }
            }
        }
        .sheet(isPresented: $showActions, onDismiss: runAfterActions) {
            EpisodeActionsSheet(episode: episode,
                                onTheRoad: { afterActions = .road },
                                onDelete: { afterActions = .delete },
                                onWordSyncReady: { wordSyncToken += 1 })
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showDeck) { DeckView(episode: episode) }
        .sheet(isPresented: $showAsk) { LiveAskView(episode: episode, chapterIndex: viewedChapter) }
        .fullScreenCover(isPresented: $onTheRoad) { OnTheRoadView() }
        .sheet(item: Binding(get: { rewriteScene.map(SceneTarget.init) }, set: { rewriteScene = $0?.index })) { target in
            SceneRewriteSheet(episode: episode, sceneIndex: target.index)
        }
        .sheet(item: Binding(get: { studioScene.map(SceneTarget.init) }, set: { studioScene = $0?.index })) { target in
            SceneStudioView(episode: episode, sceneIndex: target.index)
        }
        .sheet(item: $fixTarget) { VerifyFixSheet(episode: episode, focusTurn: $0.turn) }
        .sheet(item: $clipTarget) { ClipShareSheet(episode: episode, start: $0.start) }
        .sheet(item: $pdfPage) { target in PDFPageSheet(url: target.url, page: target.page) }
        .sheet(item: $imagePage) { SourceImageSheet(url: $0) }
        .confirmationDialog("Hangi belgenin \(pdfChoices?.page ?? 0). sayfası?", isPresented: Binding(get: { pdfChoices != nil }, set: { if !$0 { pdfChoices = nil } }),
                            titleVisibility: .visible) {
            ForEach(pdfChoices?.documents ?? [], id: \.1) { doc in
                Button(doc.0) { if let page = pdfChoices?.page { pdfPage = PDFTarget(url: doc.1, page: page) } }
            }
        }
        .alert("Kaynak açılamadı", isPresented: Binding(get: { pageError != nil }, set: { if !$0 { pageError = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(pageError ?? "") }
        .podcastLearningHooks(episode: episode)
        .sheet(item: $noteTarget) { turn in
            BookmarkEditor(time: turn.start, text: turn.text) { note, audio in
                let mark = Bookmark(episode: episode, time: turn.start, text: turn.text, note: note)
                mark.audioFileName = audio
                mark.chapterIndex = turn.chapterIndex
                context.insert(mark)
                try? context.save()
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog("Bölüm silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Sil", role: .destructive) { delete() }
        }
        // #16: istenen konum/çalma (bildirim, Spotlight, "Bu kısmı dinle"). Durum değişimi kendiliğinden yükleme yapmaz.
        .onChange(of: app.pendingPlayback, initial: true) { _, _ in consumePending() }
        .onChange(of: episode.statusRaw) { _, _ in consumePending() }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        // #16/#41: kuyruk/seri sonraki bölüme geçti. Yalnız bu sayfa önceki çalan bölümse, görünürse ve üstünde
        // Yolda modu ya da başka bir sayfa yoksa yeni bölüme geçilir; göz atan kullanıcı yerinden oynatılmaz.
        .onChange(of: player.lastAdvance) { _, advance in
            guard let advance, advance.from == episode.id, player.episode?.id == advance.to,
                  onScreen, moduleActive, !isPresenting else { return }
            AppState.current?.pendingOpenEpisode = advance.to
        }
        .task {
            #if DEBUG
            // Ekran taraması: -p5=play | actions | road | ask | actionsRoad | actionsDelete
            // (son ikisi işlemler sayfasındaki dokunuşun yolunu izler: istek + sayfayı kapat → onDismiss'te sunum).
            guard episode.status == .ready, let mode = DebugArg.value("p5") else { return }
            if !mode.hasPrefix("actions") { player.play(episode, at: nil, context: context) }
            switch mode {
            case "actions": showActions = true
            case "road": onTheRoad = true
            case "actionsRoad", "actionsDelete":
                showActions = true
                try? await Task.sleep(for: .seconds(1.5))
                afterActions = mode == "actionsRoad" ? .road : .delete
                showActions = false
            default: break
            }
            #endif
        }
        .task(id: WordSyncKey(id: episode.id, revision: episode.audioRevision, ready: episode.status == .ready,
                              active: scenePhase == .active, token: wordSyncToken)) {
            await refreshWordSync()
        }
    }

    // MARK: - Hazır bölüm

    private var readyView: some View {
        VStack(spacing: 0) {
            header
            Picker("Görünüm", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .onAppear { if let raw = DebugArg.value("episodeTab"), let value = Tab.allCases.first(where: { "\($0)" == raw }) { tab = value } }
            .modifier(AccessiblePickerStyle())
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Group {
                switch tab {
                case .transcript:
                    VStack(spacing: 8) {
                        if showSlides { SlideCard(episode: episode, focusChapter: viewedChapter) }
                        FigureCard(episode: episode, focusChapter: viewedChapter)
                        TranscriptView(episode: episode,
                                       onNote: { noteTarget = $0 },
                                       onRewrite: { turn in rewriteScene = scene(for: turn) },
                                       onStudio: { turn in studioScene = scene(for: turn) ?? 0 },
                                       onPage: { openPage($0) },
                                       onFix: { fixTarget = FixTarget(turn: $0) },
                                       onClip: { clipTarget = ClipTarget(start: $0) },
                                       issues: issues,
                                       focusTime: focusTime,
                                       wordTimes: wordTimes)
                    }
                case .chapters: ChapterListView(episode: episode)
                case .notes: EpisodeNotesView(episodeID: episode.id)
                case .study: StudyView(episode: episode)
                }
            }
            .frame(maxHeight: .infinity)

            if isCurrent {
                PlayerControls(ask: { showAsk = true }, onTheRoad: { onTheRoad = true })
            } else {
                PlayThisBar(episode: episode, startAt: focusTime) {
                    player.play(episode, at: focusTime, context: context)
                    focusTime = nil
                }
            }
        }
        // Sayfa genişliği ekrana sabit: bir satır taşsa bile oynatıcı sayfası yana kaymaz.
        .pinnedToScreenWidth()
    }

    private var header: some View {
        HStack(spacing: 14) {
            EpisodeArtwork(title: episode.title, size: 64, cover: episode.visuals?.cover)
            VStack(alignment: .leading, spacing: 4) {
                if let series = episode.seriesTitle {
                    // Kütüphane satırıyla aynı sıra: uzun seri adı kırpılınca "N. bölüm" kaybolmasın.
                    Text("\(episode.seriesIndex). bölüm · \(series)")
                        .font(.caption.bold())
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                }
                Text(episode.title)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(episode.duration.minutesText) · \(hostsText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                SourceVideoChip(episode: episode)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var hostsText: String {
        guard let settings = episode.settings else { return "" }
        guard settings.format.usesTwoHosts else { return settings.displayName(for: .a) }
        var names = "\(settings.displayName(for: .a)) & \(settings.displayName(for: .b))"
        if settings.guest != nil { names += " + \(settings.displayName(for: .c))" }
        return "\(names) · \(settings.format.title)"
    }

    private var issues: [Int: ScriptIssue] {
        Dictionary((episode.verification ?? []).filter { $0.fixedAt == nil }.map { ($0.index, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Görüntülenen konu: çalıyorsa oynatıcının konusu, değilse istenen/kalınan yerin konusu.
    private var viewedChapter: Int {
        if isCurrent { return player.currentChapterIndex }
        let time = focusTime ?? (episode.isFinished ? 0 : episode.lastPosition)
        return episode.timeline?.chapterIndex(at: time) ?? 0
    }

    private func scene(for turn: TimedTurn) -> Int? {
        episode.script.flatMap { AudioEditor.sceneIndex(forTurn: turn.id, script: $0) }
    }

    private func consumePending() {
        let action = EpisodeBrowse.action(pending: app.pendingPlayback, episodeID: episode.id, isReady: episode.status == .ready,
                                          isCurrent: isCurrent)
        guard action != .none else { return }
        app.pendingPlayback = nil
        switch action {
        case .none: break
        case let .play(time): player.play(episode, at: time, context: context)
        case let .seek(time): player.seek(to: time)
        case let .focus(time): focusTime = time
        }
    }

    /// #20: kelime zamanları; yoksa (≤30 dk, ön planda, `wordSync.auto`) hazırlanır.
    private func refreshWordSync() async {
        guard episode.status == .ready else { return }
        let id = episode.id
        wordTimes = await Task.detached(priority: .utility) { WordSync.load(episodeID: id) }.value
        guard scenePhase == .active,
              WordSyncRunner.shouldAutoPrepare(duration: episode.duration, auto: WordSyncRunner.isAuto, hasTimes: wordTimes != nil),
              await WordSyncRunner.prepare(episode, askPermission: false) == .ready else { return }
        wordTimes = await Task.detached(priority: .utility) { WordSync.load(episodeID: id) }.value
    }

    /// Transkriptteki "s. N" etiketi: PDF kaynağı o sayfada, görsel kaynak görsel olarak açılır (#8).
    private func openPage(_ page: Int) {
        let docs = (episode.sourceDocumentIDs ?? []).compactMap { DocumentLibrary.fetch($0, context: context) }
            .filter { FileManager.default.fileExists(atPath: $0.url.path) }
            .map { SourceDocRef(name: $0.name, kind: $0.kindRaw, url: $0.url, pageCount: $0.pageCount) }
        switch SourcePageResolution.resolve(page: page, documents: docs) {
        case let .pdf(url, page): pdfPage = PDFTarget(url: url, page: page)
        case let .choosePDF(pdfs, page): pdfChoices = PDFChoice(page: page, documents: pdfs.map { ($0.name, $0.url) })
        case let .image(url): imagePage = url
        case .missing: pageError = "Bu bölümün kaynağı cihazda saklanmamış (belge kütüphanesinden önce oluşturulmuş olabilir)."
        }
    }

    /// #21: işlemler sayfası kapandı; istenen sunum şimdi açılır (kapanırken istenirse UIKit reddedebilir).
    private func runAfterActions() {
        guard let follow = afterActions else { return }
        afterActions = nil
        switch follow {
        case .road: onTheRoad = true
        case .delete: confirmDelete = true
        }
    }

    private func delete() {
        if player.episode?.id == episode.id { player.close() }
        player.removeFromQueue(episodeID: episode.id)
        dismiss()
        Task { await generator.delete(episode, context: context) }
    }
}

/// #16: bölüm ekranının bekleyen çalma isteğine kararı (saf; test edilir). İstek yoksa hiçbir şey yüklenmez.
nonisolated enum EpisodeBrowse: Equatable {
    case none
    case play(Double?)
    case seek(Double)
    case focus(Double)

    static func action(pending: AppState.PendingPlayback?, episodeID: UUID, isReady: Bool, isCurrent: Bool) -> EpisodeBrowse {
        guard let pending, pending.episodeID == episodeID, isReady else { return .none }
        if pending.play { return .play(pending.time) }
        guard let time = pending.time else { return .none }
        return isCurrent ? .seek(time) : .focus(time)
    }
}

private struct WordSyncKey: Hashable {
    var id: UUID
    var revision: Int
    var ready: Bool
    var active: Bool
    var token: Int
}

/// #21: işlemler sayfasından istenen ve sayfa kapandıktan sonra açılacak sunum.
enum EpisodeActionsFollowUp: Equatable {
    case road, delete
}

struct FixTarget: Identifiable { var turn: Int?; var id: Int { turn ?? -1 } }
struct ClipTarget: Identifiable { var start: Double; var id: Double { start } }

/// Başka bölüm çalarken (ya da hiçbir şey yüklü değilken) bu bölümü çalma çubuğu.
private struct PlayThisBar: View {
    var episode: Episode
    var startAt: Double?
    var play: () -> Void
    @Environment(PlayerController.self) private var player

    private var detail: String {
        if let startAt { return "\(startAt.clockText) anından başlar" }
        if !episode.isFinished, episode.lastPosition > 5 { return "Kaldığın yer: \(episode.lastPosition.clockText)" }
        if let other = player.episode?.title ?? player.audioItem?.title { return "Şu an çalan: \(other)" }
        return episode.duration.minutesText
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                info
                Spacer(minLength: 0)
                button
            }
            VStack(alignment: .leading, spacing: 8) {
                info
                button.frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Göz atıyorsun").font(.caption.bold()).foregroundStyle(.secondary)
            Text(detail).font(.subheadline).lineLimit(2)
        }
    }

    private var button: some View {
        Button(action: play) {
            Label("Bunu çal", systemImage: "play.fill")
                .font(.headline)
                .padding(.horizontal, 6)
                .frame(minHeight: 36)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHint("Çalan bölüm durur, bu bölüm başlar")
    }
}

extension QuizItem: Identifiable {
    var id: String { question }
}

/// Ses dosyasını "Dosyalar'a kaydet" ile dışa aktarmak için. SwiftUI fileWrapper'ı arka plandan çağırdığı için
/// tür ana aktöre bağlı olmamalı; dosya belleğe okunmaz, doğrudan diskten verilir.
nonisolated struct AudioFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.mpeg4Audio]
    let url: URL

    init(url: URL) { self.url = url }
    init(configuration: ReadConfiguration) throws { throw CocoaError(.featureUnsupported) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { try FileWrapper(url: url, options: .immediate) }
}

// MARK: - Transkript

struct TranscriptView: View {
    /// Görüntülenen bölüm (çalan bölümle aynı olmayabilir).
    var episode: Episode
    /// Uzun basma menüsünden "Not ekle" seçilince.
    var onNote: (TimedTurn) -> Void = { _ in }
    var onRewrite: (TimedTurn) -> Void = { _ in }
    var onStudio: (TimedTurn) -> Void = { _ in }
    var onPage: (Int) -> Void = { _ in }
    /// #5/#6: doğrulama rozetine dokununca düzeltme sayfası (tur indeksi).
    var onFix: (Int) -> Void = { _ in }
    /// #44: "Klip paylaş" (başlangıç anı).
    var onClip: (Double) -> Void = { _ in }
    /// Doğrulamada işaretlenen turlar (Timeline.turns indeksi → sorun).
    var issues: [Int: ScriptIssue] = [:]
    /// Okuma modunda: tam ekran düğmesi gizli.
    var compactSearch = false
    /// Çalmadan "konuma git": o anın turuna kaydırılır.
    var focusTime: Double? = nil
    /// #20: kelime zamanları (TimedTurn.id → mutlak sn).
    var wordTimes: [Int: [Double]]? = nil
    @Environment(PlayerController.self) private var player
    @Environment(GenerationCoordinator.self) private var generator
    @Environment(\.modelContext) private var context
    @State private var query = ""
    @State private var savedTurn: Int?
    @State private var pronounceTurn: TimedTurn?
    @State private var follower = ReadingFollower()
    @State private var reader = false
    /// Okuma modundan istenen sunum; kapak tamamen kapanınca (`onDismiss`) çalışır.
    @State private var afterReader: (() -> Void)?
    @State private var browseTimeline: Timeline?
    @State private var audioIssueTurns: [Int: Int] = [:]

    private var isCurrent: Bool { player.episode?.id == episode.id }
    private var timeline: Timeline? { isCurrent ? (player.timeline ?? browseTimeline) : browseTimeline }

    var body: some View {
        Group {
            if let timeline {
                VStack(spacing: 6) {
                    searchBar
                    if query.trimmingCharacters(in: .whitespaces).count >= 2 {
                        searchResults(timeline)
                    } else {
                        fullTranscript(timeline)
                    }
                }
                .overlay(alignment: .bottom) {
                    if savedTurn != nil {
                        Label("İşaretlendi", systemImage: "bookmark.fill")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.smooth, value: savedTurn)
            } else {
                Color.clear
            }
        }
        .task(id: TimelineKey(id: episode.id, size: episode.timelineData?.count ?? 0, issues: episode.audioIssuesData?.count ?? 0)) {
            browseTimeline = episode.timeline
            audioIssueTurns = Self.audioIssueTurns(episode.audioIssues, script: episode.script)
        }
    }

    private var searchBar: some View {
        // Simge düğmeleri 36×36 (bitişik; yanlış simgeye dokunulmasın). Çubuğun yüksekliği ve simgelerin kenar
        // payı eskisiyle aynı kalsın diye dikey boşluk metin alanına, sağ boşluk düğme çerçevesine taşındı.
        HStack(spacing: 2) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).padding(.trailing, 6)
            TextField("Transkriptte ara", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.vertical, 7)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        .frame(minWidth: Self.searchIconTarget, minHeight: Self.searchIconTarget).contentShape(Rectangle())
                }
                .accessibilityLabel("Aramayı temizle")
            }
            ReadingSizeMenu(minTarget: Self.searchIconTarget)
            if !compactSearch {
                Button { reader = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(.secondary)
                        .frame(minWidth: Self.searchIconTarget, minHeight: Self.searchIconTarget).contentShape(Rectangle())
                }
                .accessibilityLabel("Tam ekran oku")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)   // çok büyük yazıda simgeler satırı taşırmasın
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 1)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .padding(.horizontal, 16)
    }

    private static let searchIconTarget: CGFloat = 36

    /// Ses kalite kapısından geçemeyen sahnelerin turları (#13): tur → küresel sahne.
    static func audioIssueTurns(_ issues: [AudioIssue], script: PodcastScript?) -> [Int: Int] {
        guard !issues.isEmpty, let script else { return [:] }
        let bad = Set(issues.map(\.scene))
        var result: [Int: Int] = [:]
        var cursor = 0
        for (sceneIndex, item) in script.flatScenes.enumerated() {
            if bad.contains(sceneIndex) { for t in cursor..<(cursor + item.scene.turns.count) { result[t] = sceneIndex } }
            cursor += item.scene.turns.count
        }
        return result
    }

    private func play(from turn: TimedTurn) {
        if isCurrent { player.jump(toTurn: turn.id) } else { player.play(episode, at: turn.start, context: context) }
    }

    private func searchResults(_ timeline: Timeline) -> some View {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased(with: Locale(identifier: "tr"))
        let hits = timeline.turns.filter { $0.text.lowercased(with: Locale(identifier: "tr")).contains(needle) }
        return List {
            Section("\(hits.count) sonuç") {
                ForEach(hits) { turn in
                    Button {
                        query = ""
                        play(from: turn)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(turn.start.clockText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text(highlighted(turn.text, needle)).foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func highlighted(_ text: String, _ needle: String) -> AttributedString {
        var attributed = AttributedString(text)
        let lower = text.lowercased(with: Locale(identifier: "tr"))
        var searchStart = lower.startIndex
        while let range = lower.range(of: needle, range: searchStart..<lower.endIndex) {
            let start = lower.distance(from: lower.startIndex, to: range.lowerBound)
            let length = lower.distance(from: range.lowerBound, to: range.upperBound)
            let a = attributed.index(attributed.startIndex, offsetByCharacters: start)
            let b = attributed.index(a, offsetByCharacters: length)
            attributed[a..<b].backgroundColor = .yellow.opacity(0.5)
            attributed[a..<b].font = .body.bold()
            searchStart = range.upperBound
        }
        return attributed
    }

    private func fullTranscript(_ timeline: Timeline) -> some View {
        fullTranscriptBody(timeline)
            .sheet(item: $pronounceTurn) { turn in
                PronunciationEditor(text: turn.text) {
                    // Sözlük değişti: bu sahneyi yeni telaffuzla yeniden seslendir (önbellek anahtarı değiştiği için gerçekten yeni ses).
                    guard let script = episode.script,
                          let scene = AudioEditor.sceneIndex(forTurn: turn.id, script: script),
                          let item = script.flatScenes[safe: scene] else { return }
                    try await generator.replaceScene(episode, sceneIndex: scene, turns: item.scene.turns, context: context)
                }
            }
    }

    private func fullTranscriptBody(_ timeline: Timeline) -> some View {
        let settings = episode.settings
        let names: [Speaker: String] = [.a: settings?.displayName(for: .a) ?? "A", .b: settings?.displayName(for: .b) ?? "B",
                                        .c: settings?.displayName(for: .c) ?? "Konuk"]
        let thinkPauses = isCurrent && ListeningMode.current.policy.playThinkPauses ? (timeline.thinkPauses ?? []) : []
        let pauseByQuestion = Dictionary(thinkPauses.map { ($0.turnID, $0) }, uniquingKeysWith: { a, _ in a })
        let chapterStarts = Dictionary(timeline.chapters.map { (Int(($0.start * 100).rounded()), $0) }, uniquingKeysWith: { a, _ in a })
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(timeline.turns) { turn in
                    if let chapter = chapterStarts[Int((turn.start * 100).rounded())] {
                        Text(ChapterTitleCase.upper(chapter.title, language: settings?.language))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.top, 14)
                            .padding(.horizontal, 12)
                    }
                    let isPlayingTurn = isCurrent && player.currentTurnIndex == turn.id
                    let gate = pauseByQuestion[turn.id - 1].flatMap { pause in
                        timeline.turns[safe: pause.turnID].map { ThinkGate(questionStart: $0.start, pauseEnd: pause.end) }
                    }
                    TurnRow(turn: turn, isCurrent: isPlayingTurn, hostName: names[turn.speaker] ?? "",
                            issue: issues[turn.id], audioScene: audioIssueTurns[turn.id],
                            questionPause: pauseByQuestion[turn.id], answerGate: gate,
                            wordTimes: isPlayingTurn ? wordTimes?[turn.id] : nil,
                            onPage: onPage, onFix: { onFix(turn.id) }, onStudio: { onStudio(turn) })
                        .rowWidthLocked(horizontalPadding: 8)
                        .id(turn.id)
                        .reportsReadingFrame(row: turn.id, to: follower, isCurrent: isPlayingTurn)
                        .onTapGesture { if isCurrent { player.jump(toTurn: turn.id) } }
                        .contextMenu {
                            Button("Buradan çal", systemImage: "play.fill") { play(from: turn) }
                            Button("İşaretle", systemImage: "bookmark") { bookmark(turn) }
                            Button("Not ekle", systemImage: "square.and.pencil") { onNote(turn) }
                            Button("Klip paylaş (60 sn)", systemImage: "scissors") { onClip(turn.start) }
                            Button("Sahne stüdyosu", systemImage: "slider.horizontal.3") { onStudio(turn) }
                            Button("Sahneyi yeniden yaz", systemImage: "wand.and.stars") { onRewrite(turn) }
                            Button("Kopyala", systemImage: "doc.on.doc") { UIPasteboard.general.string = turn.text }
                            Button("Telaffuz düzelt", systemImage: "character.bubble") { pronounceTurn = turn }
                        }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 16)
            .lockedToScrollWidth()
        }
        .readingFollower(follower)
        // Kelimeye dokununca o ana atla (#20; bağlantılar dersseek://tur/kelime).
        .environment(\.openURL, OpenURLAction { url in
            guard isCurrent, let hit = WordSeek.parse(url), let turn = timeline.turns[safe: hit.row] else { return .systemAction }
            let timing = FollowAlong.Timing(text: turn.text, start: turn.start, end: turn.end,
                                            spans: FollowAlong.exactSpans(turn: turn, times: wordTimes?[turn.id]), pauses: player.pauses)
            guard let time = timing.times[safe: hit.word] else { return .handled }
            player.seek(to: time)
            return .handled
        })
        // Okunan kelimeyi takip: her oynatma tikinde ölçülen çerçeveye göre (yalnızca bu görünüm tiki izler).
        .background {
            if isCurrent { PodcastReadingTick(timeline: timeline, follower: follower, wordTimes: wordTimes) }
        }
        .fullScreenCover(isPresented: $reader, onDismiss: runAfterReader) {
            PodcastReaderView(episode: episode,
                              onNote: { turn in fromReader { onNote(turn) } },
                              onRewrite: { turn in fromReader { onRewrite(turn) } },
                              onStudio: { turn in fromReader { onStudio(turn) } },
                              onPage: { page in fromReader { onPage(page) } },
                              onFix: { index in fromReader { onFix(index) } },
                              onClip: { start in fromReader { onClip(start) } },
                              issues: issues, wordTimes: wordTimes)
        }
        .onAppear {
            #if DEBUG
            if !compactSearch, ProcessInfo.processInfo.arguments.contains("-readerDemo") { reader = true }
            #endif
            scrollToFocus(timeline)
        }
        .onChange(of: focusTime) { _, _ in scrollToFocus(timeline) }
    }

    /// Okuma modundaki istek bölüm sayfasına bağlı bir sayfa açar; aynı sayfa okuma kapağını sunarken ikinci sunum
    /// bekletilir (dokunuş tepkisiz görünür). İstek saklanır, kapak kapatılır, kapanınca çalıştırılır (#21 deseni).
    private func fromReader(_ action: @escaping () -> Void) {
        afterReader = action
        reader = false
    }

    private func runAfterReader() {
        let run = afterReader
        afterReader = nil
        run?()
    }

    private func scrollToFocus(_ timeline: Timeline) {
        guard !isCurrent, let time = focusTime ?? (episode.lastPosition > 5 && !episode.isFinished ? episode.lastPosition : nil),
              let index = timeline.turnIndex(at: time) else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            follower.position.scrollTo(id: index, anchor: .top)
        }
    }

    private func bookmark(_ turn: TimedTurn) {
        let mark = Bookmark(episode: episode, time: turn.start, text: turn.text)
        mark.kind = "flag"
        mark.chapterIndex = turn.chapterIndex
        context.insert(mark)
        try? context.save()
        savedTurn = turn.id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            savedTurn = nil
        }
    }
}

/// Konu başlığını bölümün diline göre büyük harfe çevirir: yerel ayarsız `uppercased()` Türkçede "i"yi "I" yapar
/// ("BITKI"); dili bilinmeyen (eski) bölüm Türkçe sayılır.
nonisolated enum ChapterTitleCase {
    static func upper(_ title: String, language: PodcastLanguage?) -> String {
        title.uppercased(with: Locale(identifier: (language ?? .tr).rawValue))
    }
}

private struct TimelineKey: Hashable {
    var id: UUID
    var size: Int
    var issues: Int
}

/// #23: cevap turunun gizlenme aralığı (soru başladıktan düşünme payı bitene dek).
struct ThinkGate: Equatable {
    var questionStart: Double
    var pauseEnd: Double

    /// `ThinkReveal.hiddenTurns` ile aynı kural (tek tur için).
    func hides(at time: Double) -> Bool { time >= questionStart && time < pauseEnd }
}

extension FollowAlong {
    /// #20: tur için kesin kelime zamanları (sayı metindeki kelime sayısıyla tutarsa); yoksa boş (tahmin).
    nonisolated static func exactSpans(turn: TimedTurn, times: [Double]?) -> [Span] {
        guard let times, !times.isEmpty, times.count == words(in: turn.text).count else { return [] }
        return [Span(start: turn.start, end: turn.end, words: times.count, times: times)]
    }
}

private struct TurnRow: View {
    var turn: TimedTurn
    var isCurrent: Bool
    var hostName: String
    var issue: ScriptIssue?
    /// #13: bu turun sahnesi ses denetiminden geçemedi (küresel sahne).
    var audioScene: Int?
    /// #23: bu soru turundan sonra düşünme payı var.
    var questionPause: ThinkPause?
    /// #23: bu tur bir cevap; pay bitene dek gizli.
    var answerGate: ThinkGate?
    var wordTimes: [Double]?
    var onPage: (Int) -> Void = { _ in }
    var onFix: () -> Void = {}
    var onStudio: () -> Void = {}
    @AppStorage(ReadingSize.key) private var readingSize = ReadingSize.defaultSize

    /// Çiplerin dokunma alanı aşağı doğru ne kadar taşar: altında "Düzelt" rozeti varsa onun üstüne binmez.
    private var chipReach: CGFloat { issue == nil ? 12 : 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(hostName)
                    .font(.caption.bold())
                    .foregroundStyle(Theme.hostColor(turn.speaker))
                    .lineLimit(1)
                if let page = turn.sourcePage {
                    Button { onPage(page) } label: {
                        Text("s. \(page)")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary.opacity(0.7), in: Capsule())
                            .foregroundStyle(.secondary)
                            .expandedTapArea(bottom: chipReach)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Kaynak sayfa \(page), aç")
                }
                if audioScene != nil {
                    Button(action: onStudio) {
                        Label("Ses uyuşmuyor", systemImage: "waveform.badge.exclamationmark")
                            .font(.caption2.bold())
                            .foregroundStyle(.red)
                            .lineLimit(1)
                            .expandedTapArea(bottom: chipReach)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Sahne stüdyosunda aç")
                }
            }
            if let issue { IssueBadge(issue: issue, onFix: onFix) }
            if let answerGate {
                GatedTurnText(turn: turn, gate: answerGate, isCurrent: isCurrent, wordTimes: wordTimes)
            } else if isCurrent {
                LiveTurnText(turn: turn, wordTimes: wordTimes)
            } else {
                Text(turn.text)
                    .font(.system(size: readingSize))
                    .foregroundStyle(.secondary)
            }
            if isCurrent, let questionPause { ThinkCountdown(pause: questionPause) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isCurrent ? Theme.hostColor(turn.speaker).opacity(0.12) : .clear,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .animation(.smooth(duration: 0.25), value: isCurrent)
    }
}

/// #5/#6: doğrulama rozeti; belgedeki alıntı ve sayfa görünür, dokununca düzeltme sayfası açılır.
private struct IssueBadge: View {
    var issue: ScriptIssue
    var onFix: () -> Void

    private var title: String {
        switch issue.severity {
        case "uydurma": "Kaynakta yok"
        case "hatali": "Hatalı olabilir"
        default: "Belirsiz"
        }
    }

    var body: some View {
        Button(action: onFix) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Label(title, systemImage: "exclamationmark.triangle.fill")
                    if let page = issue.page { Text("· s. \(page)") }
                    Text("· Düzelt")
                }
                .font(.caption2.bold())
                .foregroundStyle(issue.severity == "belirsiz" ? .yellow : .orange)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                if let quote = issue.quote, !quote.isEmpty {
                    Text("Belgede: “\(quote)”")
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .expandedTapArea(top: 2)   // üstündeki çip satırına binmez
        }
        .buttonStyle(.plain)
        .accessibilityHint("Düzeltme önerisini aç")
    }
}

private extension View {
    /// Düzeni değiştirmeden dokunma alanını büyütür: satır içi küçük çipin birkaç nokta yanına düşen dokunuş satırın
    /// "bu tura atla" hareketine gitmesin. Satır yüksekliği (ve okuma takibinin ölçtüğü çerçeve) aynı kalır.
    func expandedTapArea(top: CGFloat = 12, bottom: CGFloat = 12, horizontal: CGFloat = 6) -> some View {
        padding(EdgeInsets(top: top, leading: horizontal, bottom: bottom, trailing: horizontal))
            .contentShape(Rectangle())
            .padding(EdgeInsets(top: -top, leading: -horizontal, bottom: -bottom, trailing: -horizontal))
    }
}

/// #23: soru turunun altında düşünme payı geri sayımı (yalnız bu görünüm zamanı izler).
private struct ThinkCountdown: View {
    var pause: ThinkPause
    @Environment(PlayerController.self) private var player

    var body: some View {
        if let countdown = ThinkReveal.countdown(at: player.currentTime, pauses: [pause]) {
            Label("Düşün: \(countdown.seconds) sn", systemImage: "hourglass")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(.tint)
                .padding(.top, 4)
                .accessibilityLabel("Düşünme payı, \(countdown.seconds) saniye")
        }
    }
}

/// #23: cevap turu pay bitene dek gizli.
private struct GatedTurnText: View {
    var turn: TimedTurn
    var gate: ThinkGate
    var isCurrent: Bool
    var wordTimes: [Double]?
    @Environment(PlayerController.self) private var player
    @AppStorage(ReadingSize.key) private var readingSize = ReadingSize.defaultSize

    var body: some View {
        if gate.hides(at: player.currentTime) {
            Label("Cevap düşünme payından sonra açılır", systemImage: "eye.slash")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        } else if isCurrent {
            LiveTurnText(turn: turn, wordTimes: wordTimes)
        } else {
            Text(turn.text).font(.system(size: readingSize)).foregroundStyle(.secondary)
        }
    }
}

/// Oynatıcı tikini takipçiye iletir (yalnızca bu görünüm her tikte yeniden çizilir).
private struct PodcastReadingTick: View {
    var timeline: Timeline
    var follower: ReadingFollower
    var wordTimes: [Int: [Double]]?
    @Environment(PlayerController.self) private var player

    var body: some View {
        let time = player.currentTime
        Color.clear
            .onChange(of: time, initial: true) { _, time in
                guard let index = player.currentTurnIndex, let turn = timeline.turns.first(where: { $0.id == index }) else { return }
                let timing = FollowAlong.Timing(text: turn.text, start: turn.start, end: turn.end,
                                                spans: FollowAlong.exactSpans(turn: turn, times: wordTimes?[turn.id]), pauses: player.pauses)
                let reading = FollowAlong.readingTime(time, rate: Double(player.rate))
                follower.follow(row: index, progress: timing.textProgress(at: reading), playing: player.isPlaying)
                FollowAlong.logSync(time: time, text: turn.text, timing: timing, reading: reading)
            }
    }
}

/// Tam ekran okuma: yalnızca transkript + küçük oynatma çubuğu.
struct PodcastReaderView: View {
    var episode: Episode
    var onNote: (TimedTurn) -> Void
    var onRewrite: (TimedTurn) -> Void
    var onStudio: (TimedTurn) -> Void = { _ in }
    var onPage: (Int) -> Void
    var onFix: (Int) -> Void = { _ in }
    var onClip: (Double) -> Void = { _ in }
    var issues: [Int: ScriptIssue]
    var wordTimes: [Int: [Double]]?
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var player

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.down").font(.title3.weight(.semibold)).frame(width: 44, height: 44) }
                    .accessibilityLabel("Okuma modundan çık")
                Spacer()
                Text(episode.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            TranscriptView(episode: episode, onNote: onNote, onRewrite: onRewrite, onStudio: onStudio, onPage: onPage,
                           onFix: onFix, onClip: onClip, issues: issues, compactSearch: true, wordTimes: wordTimes)
            if player.episode?.id == episode.id { MiniTransport() }
        }
        .pinnedToScreenWidth()
        .background(Color(.systemBackground))
        .debugNarrowScreen()
    }
}

/// Küçük oynatma çubuğu: −15 · oynat/duraklat · +15 · hız · süre.
struct MiniTransport: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        ReaderTransportBar(
            timeText: player.currentTime.clockText,
            progress: player.duration > 0 ? player.currentTime / player.duration : 0,
            isPlaying: player.isPlaying,
            rateText: player.rate.rateText,
            rates: PlayerController.rates.map { Double($0) },
            back: { player.skip(-15) },
            toggle: { player.toggle() },
            forward: { player.skip(15) },
            setRate: { player.rate = Float($0) },
            skipSeconds: 15,
            rateLabel: { Float($0).rateText },
            currentRate: Double(player.rate))
    }
}

/// Çalan tur: kelime kelime takip (yalnızca bu görünüm oynatıcı zamanını izler). Kelime zamanı varsa kelimeye dokununca atlanır.
private struct LiveTurnText: View {
    var turn: TimedTurn
    var wordTimes: [Double]?
    @Environment(PlayerController.self) private var player
    @AppStorage(ReadingSize.key) private var size = ReadingSize.defaultSize

    var body: some View {
        let spans = FollowAlong.exactSpans(turn: turn, times: wordTimes)
        FollowAlongText(text: turn.text, start: turn.start, end: turn.end,
                        time: FollowAlong.readingTime(player.currentTime, rate: Double(player.rate)), font: .system(size: size),
                        spans: spans, pauses: player.pauses,
                        link: spans.isEmpty ? nil : { WordSeek.url(row: turn.id, word: $0) })
    }
}

// MARK: - Bölümler

struct ChapterListView: View {
    var episode: Episode
    @Environment(PlayerController.self) private var player
    @Environment(GenerationCoordinator.self) private var generator
    @Environment(\.modelContext) private var context
    @State private var toDelete: TimedChapter?
    @State private var working = false
    @State private var error: String?

    private var isCurrent: Bool { player.episode?.id == episode.id }

    var body: some View {
        if let timeline = isCurrent ? player.timeline : episode.timeline {
            List {
                ForEach(timeline.chapters) { chapter in
                    Button {
                        if isCurrent { player.jump(toChapter: chapter.id) } else { player.play(episode, at: chapter.start, context: context) }
                    } label: {
                        let active = isCurrent && player.currentChapterIndex == chapter.id
                        HStack(spacing: 12) {
                            Text("\(chapter.id + 1)")
                                .font(.subheadline.monospacedDigit().bold())
                                .frame(width: 28, height: 28)
                                .background(active ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(.quaternary), in: Circle())
                                .foregroundStyle(active ? .white : .primary)
                            Text(chapter.title)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Text(chapter.start.clockText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        if timeline.chapters.count > 1 {
                            Button("Çıkar", systemImage: "scissors", role: .destructive) { toDelete = chapter }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .disabled(working)
            .overlay { if working { ProgressView("Konu çıkarılıyor…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .confirmationDialog("\"\(toDelete?.title ?? "")\" bölümden çıkarılsın mı?",
                                isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
                Button("Çıkar", role: .destructive) { if let chapter = toDelete { Task { await remove(chapter) } } }
            } message: {
                Text("Konu ses dosyasından ve transkriptten kalıcı olarak silinir; podcast kısalır. Bu konudaki notlar da silinir.")
            }
            .alert("Çıkarılamadı", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private func remove(_ chapter: TimedChapter) async {
        working = true
        defer { working = false }
        // `removeChapter` kilit içinde çalan bölümü kapatır (kaldığı yer eski zaman çizelgesiyle yazılır): durum
        // önceden alınır, iş bitince bölüm yeniden yüklenir. Kesit oturumu sürdürülmez (bölüm duraklatılmış döner).
        let wasCurrent = isCurrent, wasPlaying = wasCurrent && player.isPlaying && !player.isPlayingClips
        let cut = episode.timeline.flatMap { AudioEditor.chapterCut($0, chapterIndex: chapter.id) }
        let revision = episode.audioRevision
        do {
            try await generator.removeChapter(episode, chapterIndex: chapter.id, context: context)
            // Ses gerçekten değiştiyse (`audioRevision`) kalınan yer çıkarılan süre kadar kayar; yoksa eski sesteki
            // konum yeni seste çıkarılan konu kadar ilerisine denk gelirdi.
            if let cut, episode.audioRevision != revision {
                episode.lastPosition = ChapterRemoval.position(episode.lastPosition, removing: cut)
                try? context.save()
            }
        } catch {
            self.error = error.localizedDescription
        }
        // Hata yolunda da geri yüklenir (ses değişmediyse eski yerinden). Bu arada başka bir şey çalmaya başladıysa ya da
        // bölüm hiç kapanmadıysa ("meşgul" hatası) dokunulmaz.
        if wasCurrent, !player.isActive { player.load(episode, context: context, autoplay: wasPlaying) }
    }
}

/// Konu çıkarılınca eski zaman çizelgesindeki bir konumun yeni sesteki karşılığı (saf; test edilir): kesimden önceki
/// konum aynı kalır, kesimin içindeki konum kesimin başına (sonraki konunun yeni başlangıcı) gelir, sonrası kesim
/// süresi kadar geri kayar.
nonisolated enum ChapterRemoval {
    static func position(_ p: Double, removing cut: ClosedRange<Double>) -> Double {
        if p < cut.lowerBound { return p }
        if p <= cut.upperBound { return cut.lowerBound }
        return p - (cut.upperBound - cut.lowerBound)
    }
}

// MARK: - Kontroller

struct PlayerControls: View {
    var ask: () -> Void
    /// #18: Yolda modu (nil ise araç satırında görünmez).
    var onTheRoad: (() -> Void)? = nil
    @Environment(PlayerController.self) private var player
    @State private var scrubbing: Double?
    @State private var confused = false

    var body: some View {
        VStack(spacing: 10) {
            toolRow

            VStack(spacing: 2) {
                Slider(value: Binding(get: { scrubbing ?? player.currentTime }, set: { scrubbing = $0 }),
                       in: 0...max(player.duration, 1)) { editing in
                    if !editing, let value = scrubbing {
                        player.seek(to: value)
                        scrubbing = nil
                    }
                }
                HStack {
                    Text((scrubbing ?? player.currentTime).clockText)
                    Spacer()
                    Text("-" + max(0, player.duration - (scrubbing ?? player.currentTime)).clockText)
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            // Beş eşit sütun: genişlik ne olursa olsun (Ekran Büyütme, Düğme Şekilleri, büyük yazı) satır taşmaz.
            // Simgeler yazı boyutuyla sınırlı ölçüde büyür (dynamicTypeSize üst sınırı).
            HStack(spacing: 4) {
                Menu {
                    ForEach(PlayerController.rates, id: \.self) { rate in
                        Button {
                            player.rate = rate
                        } label: {
                            if rate == player.rate { Label(rate.rateText, systemImage: "checkmark") } else { Text(rate.rateText) }
                        }
                    }
                } label: {
                    Text(player.rate.rateText)
                        .font(.subheadline.bold().monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 8)
                        .frame(minWidth: 40, minHeight: 36)
                        .background(.quaternary.opacity(0.6), in: Capsule())
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Oynatma hızı \(player.rate.rateText)")

                Button { player.skip(-15) } label: {
                    Image(systemName: "gobackward.15").font(.title2).frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityLabel("15 saniye geri")

                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .frame(width: 60, height: 60)
                        .background(Theme.gradient, in: Circle())
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(player.isPlaying ? "Duraklat" : "Oynat")

                Button { player.skip(15) } label: {
                    Image(systemName: "goforward.15").font(.title2).frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityLabel("15 saniye ileri")

                Button(action: ask) {
                    VStack(spacing: 1) {
                        Image(systemName: "mic.fill").font(.headline)
                        Text("Sor").font(.caption2.bold()).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(width: 48, height: 44)
                    .background(Theme.warmGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Sunuculara sesli soru sor")
            }
            .buttonStyle(.plain)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.bar)
    }

    /// Araç satırı (#22, #36, #18): yatay kayar, dar ekranda taşmaz.
    private var toolRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(confused ? "Not edildi" : "Anlamadım", systemImage: "questionmark.circle", active: confused) {
                    guard player.addBookmark(kind: "confused") != nil else { return }
                    confused = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        confused = false
                    }
                }
                .accessibilityHint("Bu anı tekrar dinlemek için işaretler")
                ListeningModePicker()
                    .background(.quaternary.opacity(0.6), in: Capsule())
                chip(loopTitle, systemImage: "repeat", active: player.loop != nil || player.loopStart != nil) { player.cycleLoop() }
                    .accessibilityLabel("A–B döngüsü: \(loopTitle)")
                chip("Sessizliği atla", systemImage: "waveform.path", active: player.skipSilence) { player.skipSilence.toggle() }
                    .accessibilityValue(player.skipSilence ? "Açık" : "Kapalı")
                if let onTheRoad {
                    chip("Yolda", systemImage: "car.fill", active: false, action: onTheRoad)
                        .accessibilityLabel("Yolda modu")
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private var loopTitle: String {
        if let loop = player.loop { return "\(loop.start.clockText)–\(loop.end.clockText) ✕" }
        if let start = player.loopStart { return "A \(start.clockText) · B?" }
        return "A–B"
    }

    private func chip(_ title: String, systemImage: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(active ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(.quaternary.opacity(0.6)), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

extension Float {
    var rateText: String {
        var text = String(format: "%.2f", self)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text.replacingOccurrences(of: ".", with: ",") + "×"
    }
}

struct SceneTarget: Identifiable { var index: Int; var id: Int { index } }
struct PDFTarget: Identifiable { var url: URL; var page: Int; var id: String { "\(url.path)#\(page)" } }

struct PDFChoice { var page: Int; var documents: [(String, URL)] }
