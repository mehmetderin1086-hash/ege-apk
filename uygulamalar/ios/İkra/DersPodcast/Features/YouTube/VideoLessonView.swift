import Accessibility
import SwiftData
import SwiftUI

/// YouTube Ders Stüdyosu'nda işlenmiş bir videonun çalışma ekranı:
/// gömülü oynatıcı (gömme yasaksa indirilen ses) + Transkript · Bölümler · Notlar · Kareler · Sor, araçlar (podcast, dışa aktarma).
struct VideoLessonView: View {
    var lesson: VideoLesson
    /// Ders Stüdyosu sayfasını tümüyle kapatır (podcast'e dönüştürünce kütüphaneye geçmek için).
    var closeStudio: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var player: VideoPlayerModel
    @State private var transcript: VideoTranscript?
    @State private var loading = true
    @State private var tab: LessonTab = .transcript
    @State private var toast: LessonToast?
    @State private var shareURL: URL?
    @State private var busy: String?
    @State private var converting = false
    /// #40: "Podcast'e dönüştür" önce hızlı ayarları sorar (P7).
    @State private var convertSettings: PodcastSettings?
    @State private var errorText: String?
    @State private var audioDownload = LessonAudioDownload()
    /// Kareler sekmesinde tam ekran büyütülen kare (kapak açıkken onDisappear gerçek çıkış değildir).
    @State private var zoomedFrame: Keyframe?
    /// Tam ekran okuma açık (kapak ekranı gizler ama çıkış değildir; ses çalmaya devam eder).
    @State private var reading = false
    /// Çalış / Araçlar menülerinden açılan ek sayfa.
    @State private var sheet: LessonSheet?
    /// Ekran gerçekten görünüyor mu (podcast dönüşümü bitince bakılır).
    @State private var presence = LessonPresence()
    /// Dönüşüm bitti ama kullanıcı dersle meşguldü: "Podcast hazır" kapsülünün açacağı bölüm.
    @State private var readyEpisode: UUID?

    init(lesson: VideoLesson, closeStudio: (() -> Void)? = nil) {
        self.lesson = lesson
        self.closeStudio = closeStudio
        #if DEBUG
        let offerDemo = OfferAudioDemo.isRequested
        #else
        let offerDemo = false
        #endif
        _player = State(initialValue: VideoPlayerModel(videoID: lesson.videoID, startAt: lesson.lastPosition, duration: lesson.duration,
                                                       embeddable: offerDemo ? false : lesson.embeddable,
                                                       audioURL: offerDemo ? nil : lesson.audioURL,
                                                       videoURL: !offerDemo && lesson.hasVideoFile ? lesson.videoURL : nil,
                                                       preferAudio: LessonAudioPreference.get(lesson.id)))
    }

    /// Oynatıcı alanının üst sınırı (yatay konumda sekmelere yer kalsın).
    private var playerMaxHeight: CGFloat { verticalSizeClass == .compact ? 210 : 420 }

    var body: some View {
        VStack(spacing: 0) {
            LessonPlayerSection(player: player, download: audioDownload, offerMessage: audioOfferMessage,
                                lessonID: lesson.id, frames: sortedFrames,
                                thumbnailURL: lesson.thumbnailURL.flatMap { URL(string: $0) } ?? YouTubeLink.thumbnailURL(videoID: lesson.videoID),
                                maxHeight: playerMaxHeight,
                                onOpenYouTube: openInYouTube, onListen: listenToAudio, onRedownload: redownloadAudio, onVideo: backToVideo)
                .frame(maxHeight: playerMaxHeight)
            LessonPlayerControls(player: player, rewindTimes: lesson.rewindTimes, lessonID: lesson.id, courseID: lesson.courseID)
            LessonTabBar(tab: $tab)
                .padding(.bottom, 8)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Sayfa genişliği ekrana sabit: bir satır taşsa bile video ve sekmeler yana kaymaz.
        .pinnedToScreenWidth()
        .navigationTitle(lesson.title.isEmpty ? "Video dersi" : lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Anlamadım", systemImage: "questionmark.bubble") { sheet = .explain(time: player.currentTime) }
                    .disabled(transcript == nil)
                LessonStudyMenu(open: { sheet = $0 }, currentChapter: { currentChapter })
                    .disabled(transcript == nil)
                toolsMenu
            }
        }
        .overlay(alignment: .bottom) { statusOverlay }
        // Kalıcı kapsül içeriğin üstüne binmez, altında yer ayırır: transkriptin son satırları ve Sor alanı kapanmasın.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let readyEpisode {
                PodcastReadyBanner(open: { openEpisode(readyEpisode) }, close: { withAnimation { self.readyEpisode = nil } })
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $shareURL) { url in ShareSheet(items: [url]) }
        .sheet(isPresented: Binding(get: { convertSettings != nil }, set: { if !$0 { convertSettings = nil } })) {
            if let initial = convertSettings {
                QuickSettingsSheet(initial: initial, title: "Podcast’e dönüştür") { confirmed in
                    convertSettings = nil
                    Task { await convertToPodcast(settings: confirmed) }
                }
            }
        }
        .sheet(item: $sheet) { item in
            if let lessonContext { LessonSheetHost(sheet: item, context: lessonContext) }
        }
        .modifier(ChapterQuizTrigger(context: lessonContext, present: { sheet = $0 }))
        .modifier(LessonListeningHooks(lesson: lesson, player: player, chapterStarts: chapterStarts, notify: showToast))
        .alert("İşlem tamamlanamadı", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
        .task { await load() }
        .onAppear(perform: activatePlayer)
        .onAppear { presence.onScreen = true }
        .onAppear { if let raw = DebugArg.value("lessonTab"), let value = LessonTab(rawValue: raw) { tab = value } }
        .task {
            #if DEBUG
            if OfferAudioDemo.failed { audioDownload.debugFail() }
            if FollowDemo.autoplay, lesson.hasAudioFile, let url = lesson.audioURL {
                try? await Task.sleep(for: .seconds(1))
                player.useAudio(file: url, autoplay: true)
            }
            #endif
        }
        .task(id: toast) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(2.2))
            if !Task.isCancelled { withAnimation { toast = nil } }
        }
        .onDisappear {
            savePosition()
            // Tam ekran kare kapağı ekranı gizler ama ekrandan çıkılmış olmaz: ses çalmaya, indirme sürmeye devam eder.
            guard zoomedFrame == nil, !reading else { return }
            presence.onScreen = false
            player.suspend()
            audioDownload.cancel()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { savePosition() }
        }
    }

    // MARK: - İçerik

    @ViewBuilder
    private var content: some View {
        if loading {
            ProgressView("Transkript yükleniyor…")
        } else if let transcript {
            switch tab {
            case .transcript:
                if transcript.paragraphs.isEmpty {
                    ContentUnavailableView("Transkript boş", systemImage: "text.badge.xmark",
                                           description: Text("Bu videodan yazıya dökülmüş metin çıkmadı."))
                } else {
                    TranscriptTab(transcript: transcript, player: player, notify: showToast,
                                  onAddCard: addCard, onAddNote: addNote,
                                  lessonID: lesson.id, onCorrectTerm: applyTerm, reader: $reading)
                }
            case .chapters:
                // Son bölüm, aralıkla işlenmiş derslerde videonun sonunda değil işlenen kısmın sonunda biter.
                ChaptersTab(chapters: transcript.chapters.sorted { $0.start < $1.start },
                            duration: TranscriptFormat.chaptersEnd(
                                videoDuration: transcript.video.duration > 0 ? transcript.video.duration : lesson.duration,
                                transcript: transcript),
                            player: player)
            case .notes:
                NotesTab(notes: transcript.notes, warnings: transcript.warnings, player: player, onAddAll: addAllNoteCards)
            case .frames:
                FramesTab(lessonID: lesson.id, frames: transcript.keyframes.sorted { $0.time < $1.time }, player: player,
                          zoomed: $zoomedFrame)
            case .ask:
                AskTab(lessonID: lesson.id, title: lesson.title, paragraphs: transcript.paragraphs, player: player, notify: showToast)
            }
        } else {
            ContentUnavailableView("Transkript bulunamadı", systemImage: "text.badge.xmark",
                                   description: Text("Bu ders için kayıtlı transkript yok. Videoyu YouTube Ders Stüdyosu’nda yeniden işleyebilirsin."))
        }
    }

    /// Ek araçların ortak bağlamı (transkript yüklenince).
    private var lessonContext: LessonContext? {
        transcript.map { current in
            var lessonContext = LessonContext(lesson: lesson, transcript: current, player: player) { updated in
                lesson.transcript = updated
                transcript = updated
                try? context.save()
            }
            lessonContext.closeStudio = closeStudio
            return lessonContext
        }
    }

    /// Çalan bölümün sırası (bölüm yoksa nil).
    private var currentChapter: Int? {
        guard let chapters = transcript?.chapters.sorted(by: { $0.start < $1.start }), !chapters.isEmpty else { return nil }
        return chapters.lastIndex { $0.start <= player.currentTime } ?? 0
    }

    /// Bölüm başlangıçları (kilit ekranı sonraki/önceki bölüm düğmeleri ve uyku zamanlayıcısı için).
    private var chapterStarts: [Double] {
        (transcript?.chapters ?? []).map(\.start).sorted()
    }

    /// Transkriptte seçilen terimi sözlüğe ekler ve bu dersin tüm metinlerinde düzeltir.
    private func applyTerm(from: String, to: String) {
        guard let rule = TermDictionary.add(from: from, to: to), let current = transcript else { return }
        let updated = TermDictionary.apply(to: current, rules: [rule])
        guard updated != current else { showToast("Sözlüğe eklendi; bu derste eşleşme yok"); return }
        lesson.transcript = updated
        transcript = updated
        try? context.save()
        showToast("“\(rule.from)” → “\(rule.to)” düzeltildi")
    }

    private var toolsMenu: some View {
        Menu {
            Button("Podcast’e dönüştür", systemImage: "waveform.badge.plus") {
                convertSettings = ((try? JSONDecoder().decode(PodcastSettings.self, from: UserDefaults.standard.data(forKey: "lastSettings") ?? Data()))
                    ?? PodcastSettings()).reusable.withAppVoice
            }
            .disabled(converting || transcript?.paragraphs.isEmpty ?? true)
            Menu("Dışa aktar", systemImage: "square.and.arrow.up") {
                Button("Altyazı (SRT)", systemImage: "captions.bubble") { export(.srt) }
                Button("Metin (TXT)", systemImage: "doc.plaintext") { export(.txt) }
                Button("Ders notu (Markdown)", systemImage: "doc.richtext") { export(.markdown) }
                Button("Ders notu (PDF)", systemImage: "doc.text") { exportPDF() }
            }
            .disabled(transcript == nil || busy != nil)
            Button("YouTube’da aç", systemImage: "arrow.up.right.square", action: openInYouTube)
            audioMenu
            if transcript != nil { LessonMoreItems(open: { sheet = $0 }) }
            Button(lesson.favorite ? "Favoriden çıkar" : "Favorilere ekle",
                   systemImage: lesson.favorite ? "star.slash" : "star") {
                lesson.favorite.toggle()
                try? context.save()
                showToast(lesson.favorite ? "Favorilere eklendi" : "Favoriden çıkarıldı")
            }
        } label: {
            Label("Araçlar", systemImage: "ellipsis.circle")
        }
    }

    @ViewBuilder
    private var audioMenu: some View {
        switch player.backend {
        case .web:
            if lesson.hasVideoFile, let url = lesson.videoURL {
                Button("İndirilen videoyu oynat", systemImage: "play.rectangle.on.rectangle") { player.useVideo(file: url, autoplay: true) }
            }
            Button("Sesi uygulamada dinle", systemImage: "headphones", action: listenToAudio)
                .disabled(audioDownload.isRunning)
        case .audio:
            if lesson.embeddable {
                Button(player.isVideoFile ? "YouTube videosuna geç" : "Videoya dön", systemImage: "play.rectangle", action: backToVideo)
            }
        case .offerAudio:
            EmptyView()
        }
        if lesson.audioFileName != nil {
            Button("İndirilen sesi sil", systemImage: "trash", role: .destructive, action: deleteAudio)
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if converting {
            ConversionBanner()
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let busy {
            HStack(spacing: 10) {
                ProgressView()
                Text(busy).font(.callout)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .padding()
        } else if let toast {
            Text(toast.text)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
        }
    }

    // MARK: - Yükleme ve konum

    private func load() async {
        guard transcript == nil else { return }
        if let data = lesson.transcriptData {
            transcript = await LessonFiles.decodeTranscript(data)
        }
        // Henüz izlenmemiş ders özetle açılır: konu başlıkları ve ana noktalar ilk bakışta görünsün.
        if tab == .transcript, DebugArg.value("lessonTab") == nil, transcript?.notes != nil, lesson.lastPosition < 5, lesson.watchedSeconds < 5 { tab = .notes }
        // Aralıkla işlenmiş ve hiç izlenmemiş ders: oynatıcı transkriptin başladığı yerden açılır.
        // lastPosition'a yazılmaz; kütüphanedeki "izlendi" oranı ancak gerçekten oynatınca değişir.
        if let transcript, !player.hasStarted, lesson.modelContext != nil,
           let start = TranscriptFormat.initialSeek(lastPosition: lesson.lastPosition, transcript: transcript) {
            player.seek(to: start)
        }
        loading = false
    }

    private func activatePlayer() {
        let target = lesson
        player.nowPlayingTitle = target.title
        player.nowPlayingArtist = target.channel
        player.onCheckpoint = { [weak target] time in Self.store(position: time, in: target) }
        player.activate()
    }

    private func savePosition() {
        guard player.hasStarted else { return }
        Self.store(position: player.currentTime, in: lesson)
    }

    /// Konumu kaydeder (ses kipinde oynatıcı da duraklatınca / ~15 sn'de bir çağırır). Silinmiş derse dokunulmaz.
    private static func store(position time: Double, in lesson: VideoLesson?) {
        guard let lesson, let context = lesson.modelContext, !lesson.isDeleted else { return }
        guard time.isFinite, abs(time - lesson.lastPosition) >= 1 else { return }
        lesson.lastPosition = time
        try? context.save()
    }

    // MARK: - Ses (gömme yasaksa uygulama içinde dinleme)

    private var sortedFrames: [Keyframe] {
        (transcript?.keyframes ?? []).sorted { $0.time < $1.time }
    }

    private var audioOfferMessage: String {
        if !player.embeddable {
            return "Video sahibi uygulama içinde oynatmaya izin vermiyor. Sesini indirip burada dinleyebilirsin; transkript sesle birlikte ilerler."
        }
        if let error = player.webError {
            return "\(error) Sesini indirip uygulamada dinleyebilirsin."
        }
        return "Dersin sesini indirip çevrimdışı dinleyebilirsin; transkript sesle birlikte ilerler."
    }

    /// İndirilmişse ses kipine geçer; değilse kartı gösterip indirmeyi başlatır (bitince kendiliğinden çalar).
    /// Seçim hatırlanır: ders sonraki açılışta da sesle başlar. Web hatasından sonraki otomatik ses yedeği buradan
    /// geçmez, tercihi değiştirmez.
    private func listenToAudio() {
        LessonAudioPreference.set(lesson.id, true)
        if lesson.hasAudioFile, let url = lesson.audioURL {
            player.useAudio(file: url, autoplay: true)
            return
        }
        guard !audioDownload.isRunning else { return }
        if lesson.audioFileName != nil {   // kayıt var, dosya yok
            lesson.audioFileName = nil
            try? context.save()
        }
        player.showAudioOffer()
        guard lesson.duration <= LessonAudioDownload.maxDuration else { return }
        audioDownload.start(lesson: lesson, context: context) { [player] url in
            player.useAudio(file: url, autoplay: true)
        }
    }

    /// Videoya döner (ya da web oynatıcıyı yeniden dener); ses tercihi kalkar.
    private func backToVideo() {
        LessonAudioPreference.set(lesson.id, false)
        player.useWeb()
    }

    private func deleteAudio() {
        guard let name = lesson.audioFileName else { return }
        LessonAudioPreference.set(lesson.id, false)
        player.audioRemoved()
        VideoFiles.removeAudio(lesson: lesson.id, name: name)
        lesson.audioFileName = nil
        try? context.save()
        showToast("İndirilen ses silindi")
    }

    /// Ses dosyası bozuk/eksik: silip yeniden indirir.
    private func redownloadAudio() {
        if let name = lesson.audioFileName { VideoFiles.removeAudio(lesson: lesson.id, name: name) }
        lesson.audioFileName = nil
        try? context.save()
        listenToAudio()   // dosya yok → kart + indirme (oynatıcı sökülür)
    }

    private func showToast(_ text: String) {
        withAnimation { toast = LessonToast(text: text) }
        // Kısa süre görünen bildirim VoiceOver'da kaçmasın.
        AccessibilityNotification.Announcement(text).post()
    }

    private func openInYouTube() {
        let time = player.currentTime > 0 ? player.currentTime : lesson.lastPosition
        guard let url = TranscriptFormat.shareURL(videoID: lesson.videoID, at: time)
                ?? URL(string: lesson.url) else { return }
        player.pause()
        openURL(url)
    }

    // MARK: - Kartlar ve notlar

    private func addCard(_ row: TranscriptRow) {
        let added = LessonStudy.addCard(TranscriptFormat.cardContent(for: row), lesson: lesson, context: context,
                                        clip: ClipRange(start: row.start, end: row.end))
        showToast(added ? "Kartlara eklendi" : "Bu kart zaten var")
    }

    private func addNote(_ row: TranscriptRow) {
        LessonStudy.appendToCornell(time: row.start, quote: row.secondary ?? row.text, lesson: lesson, context: context)
        showToast("Cornell notuna eklendi")
    }

    private func addAllNoteCards() {
        guard let notes = transcript?.notes else { return }
        let count = LessonStudy.addNoteCards(notes, lesson: lesson, context: context)
        showToast(count > 0 ? "\(count) kart eklendi" : "Kartlar zaten ekli")
    }

    // MARK: - Dışa aktarma

    private func export(_ kind: LessonFiles.TextExport) {
        guard let transcript, busy == nil else { return }
        let title = lesson.title, channel = lesson.channel
        let link = TranscriptFormat.shareURL(videoID: lesson.videoID)?.absoluteString ?? lesson.url
        busy = "Dışa aktarılıyor…"
        Task {
            defer { busy = nil }
            do {
                shareURL = try await LessonFiles.exportText(kind, transcript: transcript, title: title, channel: channel, url: link)
            } catch {
                errorText = "Dosya yazılamadı: \(error.localizedDescription)"
            }
        }
    }

    private func exportPDF() {
        guard let transcript, busy == nil else { return }
        busy = "PDF hazırlanıyor…"
        // await'ler boyunca ders silinebilir: model özellikleri önceden yerele alınır.
        let lessonID = lesson.id, title = lesson.title, channel = lesson.channel
        Task {
            defer { busy = nil }
            var images: [String: UIImage] = [:]
            for frame in transcript.keyframes {
                let url = VideoFiles.keyframeURL(lesson: lessonID, frame: frame.id)
                if let image = await LessonFiles.thumbnail(url, maxPixel: 800) { images[frame.id] = image }
            }
            let url = LessonFiles.exportURL(TranscriptFormat.fileName(title, suffix: " - Ders notu", ext: "pdf"))
            if LessonPDF.render(title: title, channel: channel, transcript: transcript, frames: images, to: url) {
                shareURL = url
            } else {
                errorText = "PDF oluşturulamadı."
            }
        }
    }

    // MARK: - Podcast'e dönüştür

    private func convertToPodcast(settings chosen: PodcastSettings) async {
        guard let transcript, !converting, let app = AppState.current else { return }
        converting = true
        readyEpisode = nil
        defer { converting = false }
        player.pause()
        // Senaryo yazılırken (dakikalar sürebilir) kullanıcı geri dönüp bu dersi silebilir; silinip kaydedilmiş
        // modele dokunmak SwiftData'da çöker. Gereken her şey await'ten ÖNCE yerele alınır, sonra ders kimlikle yeniden çekilir.
        let lessonID = lesson.id
        let title = lesson.title
        let text = TranscriptFormat.podcastSource(title: title, channel: lesson.channel, transcript: transcript)
        let figures = TranscriptFormat.sourceFigures(from: transcript.keyframes, title: title)
        let frameSources = transcript.keyframes.map { (figureID: TranscriptFormat.figureID($0.id), url: lesson.keyframeURL($0.id)) }
        // #40: türev bağı (kaynak ders ve o an) ve dersin Derslerim bağı bölüme işlenir.
        var settings = chosen
        let videoTime = player.currentTime
        settings.derivation = Derivation(kind: "video", parentEpisodeID: nil, sourceLessonID: lessonID,
                                         sourceVideoTime: videoTime > 5 ? videoTime : nil, courseID: lesson.courseID)
        do {
            let episode = try await app.generator.start(sources: [ImportedSource(name: title.isEmpty ? "YouTube dersi" : title,
                                                                                 kind: .text(text))],
                                                        settings: settings, context: context)
            // Kareler bölümün kaynak şekilleri olur (figure_<id>.png). Ders silindiyse kare dosyaları da gitmiştir.
            let jobs = frameSources.compactMap { frame -> LessonFiles.FigureCopy? in
                guard FileManager.default.fileExists(atPath: frame.url.path) else { return nil }
                return LessonFiles.FigureCopy(figureID: frame.figureID, source: frame.url, destination: episode.figureURL(frame.figureID))
            }
            let written = await LessonFiles.copyFigures(jobs)
            let kept = figures.filter { written.contains($0.id) }
            if !kept.isEmpty, episode.modelContext != nil { episode.sourceFigures = kept }
            if let live = Self.liveLesson(id: lessonID, in: context), !live.episodeIDs.contains(episode.id) {
                var ids = live.episodeIDs   // SwiftData dizisi: kopyala-değiştir-ata
                ids.append(episode.id)
                live.episodeIDs = ids
            }
            try? context.save()

            // Dakikalar geçti: kullanıcı beklemiyorsa (dersi izliyor, bir araçta ya da ekrandan çıkmış) yerinden edilmez.
            let id = episode.id
            switch ConversionFinish.decide(onScreen: presence.onScreen, isPlaying: player.isPlaying,
                                           busyElsewhere: sheet != nil || shareURL != nil || reading || zoomedFrame != nil) {
            case .open:
                openEpisode(id)
            case .offer:
                withAnimation { readyEpisode = id }
                AccessibilityNotification.Announcement("Podcast hazır").post()
            case .silent:
                break
            }
        } catch {
            // Ekrandan çıkıldıysa uyarı gösterilecek yer yok (başka bir dersin üstünde belirmesin).
            if presence.onScreen { errorText = error.localizedDescription }
        }
    }

    /// Ders Stüdyosu'nu kapatıp bölümü podcast kütüphanesinde açar.
    private func openEpisode(_ id: UUID) {
        guard let app = AppState.current else { return }
        readyEpisode = nil
        if let closeStudio { closeStudio() } else { dismiss() }
        app.selectedTab = .library
        app.pendingOpenEpisode = id
    }

    /// Dersi kimliğiyle yeniden çeker; silinmişse (ya da bağlamdan kopmuşsa) nil. Uzun bir await'ten sonra
    /// eldeki model nesnesine güvenilmez: silinip kaydedilince `isDeleted` yeniden false döner ve
    /// çözülmemiş özelliklere erişmek çöker.
    static func liveLesson(id: UUID, in context: ModelContext) -> VideoLesson? {
        var descriptor = FetchDescriptor<VideoLesson>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let lesson = try? context.fetch(descriptor).first, lesson.modelContext != nil, !lesson.isDeleted else { return nil }
        return lesson
    }
}

// MARK: - Yardımcı türler ve parçalar

enum LessonTab: String, CaseIterable, Identifiable {
    // Sıra ekrandaki sıradır: özet önce gelir, az kullanılan kareler sonda.
    case notes, transcript, chapters, ask, frames
    var id: String { rawValue }
    var title: String {
        switch self {
        case .transcript: "Metin"
        case .chapters: "Bölümler"
        case .notes: "Özet"
        case .frames: "Kareler"
        case .ask: "Sor"
        }
    }
}

struct LessonToast: Equatable {
    let id = UUID()
    var text: String
}

/// Ders ekranı şu an gerçekten ekranda mı. Dakikalar süren podcast dönüşümü bitince bakılır; o sırada görünüm kapanmış
/// olabileceği için değer görünümün kendi durumunda değil, paylaşılan bir nesnede durur.
final class LessonPresence {
    var onScreen = false
}

/// Podcast dönüşümü bitince ne yapılacağı.
nonisolated enum ConversionFinish: Equatable, Sendable {
    /// Kullanıcı ders ekranında bekliyor: podcast kütüphanesine geçilir.
    case open
    /// Kullanıcı dersle meşgul (oynatıyor ya da bir araç/okuma ekranında): yerinden edilmez, "Podcast hazır" kapsülü çıkar.
    case offer
    /// Ders ekranından çıkılmış: hiçbir şey açılmaz (bölüm zaten podcast kütüphanesinde).
    case silent

    static func decide(onScreen: Bool, isPlaying: Bool, busyElsewhere: Bool = false) -> ConversionFinish {
        guard onScreen else { return .silent }
        return isPlaying || busyElsewhere ? .offer : .open
    }
}

/// Dönüşüm bitti ama kullanıcı dersle meşgul: yerinden etmeden haber verir. "Aç" podcast kütüphanesine geçer.
private struct PodcastReadyBanner: View {
    var open: () -> Void
    var close: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Podcast hazır")
                .font(.callout.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: open) {
                Text("Aç").frame(minWidth: 28, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Podcast’i aç")
            Button(action: close) {
                Image(systemName: "xmark").font(.footnote.weight(.semibold))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("Bildirimi kapat")
        }
        .padding(.leading, 14)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }
}

/// Oynatıcı alanı: gömülü video, ses kipi (o anki kare) ya da "Sesi uygulamada dinle" kartı.
private struct LessonPlayerSection: View {
    var player: VideoPlayerModel
    var download: LessonAudioDownload
    var offerMessage: String
    var lessonID: UUID
    var frames: [Keyframe]
    var thumbnailURL: URL?
    /// Alanın üst sınırı (çağıranın uyguladığı çerçeveyle aynı): ses kartı bunu aşarsa kart içinde kaydırılır.
    var maxHeight: CGFloat
    var onOpenYouTube: () -> Void
    var onListen: () -> Void
    var onRedownload: () -> Void
    var onVideo: () -> Void
    /// Ses kartının içeriğe göre ölçülen yüksekliği.
    @State private var cardHeight: CGFloat = 0

    var body: some View {
        if player.backend == .offerAudio {
            // Kart 16:9'a zorlanmaz: 320 pt'de o kutu 180 pt kalıyor, ileti ve hata metni küçülüp kesiliyor, alt alta düğmeler
            // ilerleme çubuğuna taşıyordu. Alan kartın ölçülen yüksekliği kadar olur; üst sınırı aşan kart kaydırılır.
            ZStack {
                Color.black
                ScrollView {
                    LessonAudioCard(message: offerMessage, download: download, duration: player.duration,
                                    videoButtonTitle: player.embeddable ? (player.webError == nil ? "Videoya dön" : "Yeniden dene") : nil,
                                    onListen: onListen, onOpenYouTube: onOpenYouTube, onVideo: onVideo)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: LessonAudioCard.fittedHeight(content: cardHeight, limit: maxHeight))
            }
            .frame(maxWidth: .infinity)
        } else {
            ZStack {
                Color.black
                switch player.backend {
                case .web:
                    YouTubePlayerView(model: player)
                    if player.status == .loading {
                        ProgressView().tint(.white).allowsHitTesting(false)
                    }
                case .audio:
                    if player.isVideoFile {
                        // İndirilmiş video: yerleşik oynatıcı (resim içinde resim).
                        LocalVideoPlayerView(model: player)
                        if player.status == .loading {
                            ProgressView().tint(.white).allowsHitTesting(false)
                        } else if case .failed(let message) = player.status {
                            LocalVideoFailure(message: message, onOpenYouTube: onOpenYouTube)
                        }
                    } else {
                        LessonAudioArtwork(player: player, lessonID: lessonID, frames: frames, thumbnailURL: thumbnailURL,
                                           onRedownload: onRedownload, onOpenYouTube: onOpenYouTube)
                    }
                case .offerAudio:
                    EmptyView()
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Oynat/duraklat, ±10 sn, konum ve hız. Konum her 0,5 sn değiştiği için ayrı görünüm (yalnızca bu çizilir).
private struct LessonPlayerControls: View {
    var player: VideoPlayerModel
    var rewindTimes: [Double]
    var lessonID: UUID
    var courseID: UUID?

    var body: some View {
        VStack(spacing: 4) {
            LessonProgressBar(player: player, rewindTimes: rewindTimes)
                .disabled(player.status != .ready)
                .padding(.horizontal, 16)
            LessonPlaybackStatusRow(player: player)
            // Sığarsa tek satır; sığmazsa (dar ekran, Düğme Şekilleri, kalın/büyük yazı) süre ve hız üst satıra çıkar.
            // Eskiden süre "0…" diye kesiliyor, hız düğmesi boş görünüyordu.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    // 44 pt'lik dokunma alanının yan payı yerleşime sayılmaz: simgeler eski yerinde kalır, tek satır eskisi kadar yer tutar.
                    buttons.padding(.horizontal, -12)
                    timeLabel
                    Spacer(minLength: 4)
                    rateMenu
                    playbackMenu
                }
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        timeLabel
                        Spacer(minLength: 8)
                        rateMenu
                        playbackMenu
                    }
                    buttons
                }
                VStack(spacing: 6) {
                    timeLabel
                    HStack(spacing: 8) {
                        rateMenu
                        playbackMenu
                    }
                    buttons
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .disabled(player.status != .ready)
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }

    private var playbackMenu: some View {
        LessonPlaybackMenu(player: player, lessonID: lessonID, courseID: courseID)
    }

    /// Her düğme 44×44 pt dokunma alanı (eskiden yalnız simge kadardı; ıskalanan dokunuş hiçbir şey yapmıyordu).
    private var buttons: some View {
        HStack(spacing: 0) {
            Button { player.skip(-10) } label: { Image(systemName: "gobackward.10").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .accessibilityLabel("10 saniye geri")
            Button { player.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(player.isPlaying ? "Duraklat" : "Oynat")
            Button { player.skip(10) } label: { Image(systemName: "goforward.10").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .accessibilityLabel("10 saniye ileri")
        }
        .fixedSize()
        // Alanın 4 pt'si üstteki/alttaki boşluğa taşar: kontrol satırı 44 yerine 36 pt yer tutar (dar ekranda transkripte yer kalsın).
        .padding(.vertical, -4)
    }

    /// Konum her tikte değişir: yalnızca bu küçük görünüm yeniden çizilsin (kontroller değil).
    private var timeLabel: some View {
        LessonTimeLabel(player: player)
    }

    private var rateMenu: some View {
        Menu {
            Picker("Oynatma hızı", selection: Binding(get: { player.rate }, set: { player.rate = $0 })) {
                ForEach(VideoPlayerModel.rates, id: \.self) { Text(Self.rateTitle($0)).tag($0) }
            }
        } label: {
            Text(Self.rateTitle(player.rate))
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .accessibilityLabel("Oynatma hızı \(Self.rateTitle(player.rate))")
    }

    static func rateTitle(_ rate: Double) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "tr_TR"))) + "×"
    }
}

/// Sabit genişlik ("00:00:00 / 00:00:00" kadar): yazı her saniye değişince düzen gidip gelmesin.
private struct LessonTimeLabel: View {
    var player: VideoPlayerModel

    var body: some View {
        Text("\(TranscriptFormat.timestamp(player.currentTime)) / \(TranscriptFormat.timestamp(player.duration))")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }
}

/// Podcast üretimi sürerken üretim aşaması.
private struct ConversionBanner: View {
    var body: some View {
        let phase = AppState.current?.generator.draftPhase
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text(phase?.title ?? "Podcast hazırlanıyor").font(.callout.weight(.semibold))
                Text(phase?.detail ?? "Transkript podcast senaryosuna dönüştürülüyor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Sekme çubuğu: sığarsa eşit genişlikte; sığmazsa (Ekran Büyütme, büyük yazı) yana kaydırılır.
/// Segmentli seçici dar ekranda "Trans…", "Bölüm…" diye kesiyordu.
struct LessonTabBar: View {
    @Binding var tab: LessonTab

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { chips(stretch: true) }
                .padding(.horizontal, 12)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) { chips(stretch: false) }
                        .padding(.horizontal, 12)
                }
                .onChange(of: tab, initial: true) { _, value in
                    withAnimation { proxy.scrollTo(value, anchor: .center) }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func chips(stretch: Bool) -> some View {
        ForEach(LessonTab.allCases) { item in
            let selected = item == tab
            Button { tab = item } label: {
                // Seçili sekme kalınlaşınca genişlemesin (çubuk sığan/kayan düzenler arasında zıplıyordu):
                // yerleşim her zaman kalın yazının genişliğine göre yapılır.
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .hidden()
                    .overlay { Text(item.title).font(.subheadline.weight(selected ? .semibold : .regular)) }
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: stretch ? .infinity : nil)
                    .background(Capsule().fill(selected ? Color.accentColor.opacity(0.16) : Color(.secondarySystemBackground)))
                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.plain)
            .id(item)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}
