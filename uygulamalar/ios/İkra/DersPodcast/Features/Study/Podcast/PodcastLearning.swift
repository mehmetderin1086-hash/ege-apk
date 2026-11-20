import SwiftData
import SwiftUI
import UserNotifications

/// P6 kancaları: konu sonu tek hakemi (`.chapterFinished`) ve bölüm sonu (`.episodeFinished`).
/// Sunum uygulama genelindeki `.podcastLearningOverlay()` ile yapılır.
enum PodcastLearning {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        PodcastEvent.observe(PodcastEvent.chapterFinished) { LearningCenter.shared.chapterFinished($0) }
        PodcastEvent.observe(PodcastEvent.episodeFinished) { LearningCenter.shared.episodeFinished($0) }
        PodcastEvent.observe(PodcastEvent.episodeDeleted) { info in
            if let id = info.episodeID { InterludeBuilder.remove(episodeID: id); LearningCenter.shared.forget(id) }
        }
        LearningCenter.shared.watchPlayer()
    }
}

/// #25 eller serbest ayarı (Çalış → Dinlerken öğrenme).
enum HandsFree {
    static let key = "handsFree.enabled"
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Uygulama genelinde gösterilen öğrenme sayfaları.
enum LearningSheet: Identifiable, Equatable {
    case inlineQuiz(episodeID: UUID, chapter: Int, item: QuizItem, think: Double)
    case recall(episodeID: UUID, chapter: Int)
    case endCard(episodeID: UUID)
    case pretest(episodeID: UUID)

    /// Dinlerken quiz bölüm ekranından sunulur (kullanıcı oradadır); diğerleri uygulama genelinden.
    var isInlineQuiz: Bool { if case .inlineQuiz = self { true } else { false } }

    var id: String {
        switch self {
        case let .inlineQuiz(id, chapter, item, _): "quiz-\(id)-\(chapter)-\(item.question.hashValue)"
        case let .recall(id, chapter): "recall-\(id)-\(chapter)"
        case let .endCard(id): "end-\(id)"
        case let .pretest(id): "pre-\(id)"
        }
    }
}

/// Kısa öneri şeridi (kendiliğinden kaybolur).
struct LearningBanner: Identifiable, Equatable {
    let id = UUID()
    var symbol: String
    var text: String
    var action: String
    var sheet: LearningSheet
    /// Kabul edilince podcast duraklatılsın mı.
    var pausesPlayer: Bool

    /// Soru başta, başlık kısaltılmış: dar ekranda kesilen kısım soru olmasın.
    static func endCardText(title: String, limit: Int = 40) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let short = trimmed.count > limit
            ? String(trimmed.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
            : trimmed
        return short.isEmpty ? "Bölüm bitti. Ne öğrendin?" : "Ne öğrendin? “\(short)” bitti."
    }
}

@Observable
final class LearningCenter {
    static let shared = LearningCenter()

    var sheet: LearningSheet?
    var banner: LearningBanner?

    @ObservationIgnored private var detailTokens: [UUID: UUID] = [:]
    @ObservationIgnored private var prepared: [String: PreparedInterlude] = [:]
    @ObservationIgnored private var preparing: Set<String> = []
    @ObservationIgnored private var asked: [UUID: Set<String>] = [:]
    @ObservationIgnored private(set) var interlude: InterludeSession?
    @ObservationIgnored private var resumeAfterSheet = false
    /// #26: bölüm sonu kartı açıkken tutulan otomatik geçiş (kart sıradakinin adını buradan okur).
    private(set) var nextHold = NextUpHold()
    @ObservationIgnored private var pendingEndCard: (id: UUID, at: Date)?
    @ObservationIgnored private var watchRetries = 0
    /// Gerçekten ekrana gelen sayfalar (başka bir sayfa açıkken sunum sessizce başarısız olabilir).
    @ObservationIgnored private var shownSheetID: String?

    private var player: PlayerController? { AppState.current?.player }
    private var context: ModelContext { AppDataStore.container.mainContext }
    private var isForeground: Bool { UIApplication.shared.applicationState == .active }

    // MARK: Bölüm ekranı

    /// Bölüm detayı göründü: konu sonu sorusu yalnız ilgili detay açıkken sorulur.
    func detailAppeared(_ episodeID: UUID) -> UUID {
        let token = UUID()
        detailTokens[token] = episodeID
        return token
    }

    func detailDisappeared(_ token: UUID) { detailTokens[token] = nil }

    func isDetailOpen(_ episodeID: UUID) -> Bool { detailTokens.values.contains(episodeID) }

    func forget(_ episodeID: UUID) {
        prepared = prepared.filter { $0.value.episodeID != episodeID }
        asked[episodeID] = nil
    }

    // MARK: Konu başı: ara sesi hazırla (#25)

    func watchPlayer() {
        guard let player else {
            watchRetries += 1
            guard watchRetries < 30 else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                LearningCenter.shared.watchPlayer()
            }
            return
        }
        withObservationTracking {
            _ = player.episode?.id
            _ = player.currentChapterIndex
        } onChange: {
            Task { @MainActor in
                LearningCenter.shared.chapterStarted()
                LearningCenter.shared.watchPlayer()
            }
        }
    }

    /// Yeni konu başladı: eller serbest açıksa bu konunun sonu için tek ses dosyası hazırlanır.
    private func chapterStarted() {
        guard let player, let episode = player.episode, !episode.isDeleted else { return }
        let policy = ListeningMode.current.policy
        guard policy.handsFree, HandsFree.isEnabled, let quiz = episode.study?.quiz, !quiz.isEmpty else { return }
        let chapter = player.currentChapterIndex
        let chapterCount = player.timeline?.chapters.count ?? 0
        guard chapter < chapterCount - 1 else { return }   // son konu bölüm sonunda ele alınır
        let key = "\(episode.id)-\(chapter)"
        guard prepared[key] == nil, !preparing.contains(key),
              let item = QuestionPicker.forChapter(quiz, chapter: chapter, asked: asked[episode.id] ?? []) else { return }
        if prepared.values.contains(where: { $0.episodeID != episode.id }) {
            prepared = prepared.filter { $0.value.episodeID == episode.id }
            InterludeBuilder.purge(except: episode.id)
        }
        preparing.insert(key)
        let id = episode.id
        let language = episode.settings?.language == .en ? "en-US" : "tr-TR"
        let think = ThinkTiming.seconds(for: item, script: episode.script)
        Task { @MainActor in
            let ready = await InterludeBuilder.build(item: item, episodeID: id, chapter: chapter, language: language, thinkSeconds: think)
            LearningCenter.shared.preparing.remove(key)
            if let ready { LearningCenter.shared.prepared[key] = ready }
        }
    }

    // MARK: Konu sonu hakemi

    func chapterFinished(_ info: PodcastEventInfo) {
        guard let id = info.episodeID, let chapter = info.chapter, let player, let episode = player.episode,
              episode.id == id, interlude == nil else { return }
        let quizItem = QuestionPicker.forChapter(episode.study?.quiz ?? [], chapter: chapter, asked: asked[id] ?? [])
        let ready = prepared["\(id)-\(chapter)"]
        let input = ChapterEndArbiter.Input(
            isForeground: isForeground, detailOpen: isDetailOpen(id), policy: ListeningMode.current.policy,
            handsFreeEnabled: HandsFree.isEnabled, hasChapterQuestion: quizItem != nil, interludeReady: ready != nil,
            learn2: AppState.current?.serverSupports("learn2") == true,
            hasChapterTurns: episode.timeline?.turns.contains { $0.chapterIndex == chapter } == true)
        switch ChapterEndArbiter.decide(input) {
        case .inlineQuiz:
            guard let quizItem, sheet == nil else { return }
            asked[id, default: []].insert(quizItem.question)
            player.pause()
            resumeAfterSheet = true
            banner = nil
            let quiz = LearningSheet.inlineQuiz(episodeID: id, chapter: chapter, item: quizItem, think: ThinkTiming.seconds(for: quizItem, script: episode.script))
            sheet = quiz
            confirmShown(quiz)
        case .handsFree:
            guard let ready else { return }
            startInterlude(ready, player: player)
        case .recallPrompt:
            guard sheet == nil else { return }
            banner = LearningBanner(symbol: "text.bubble", text: "Konu bitti. 45 saniyede aklında kalanları anlat.",
                                    action: "Anlat", sheet: .recall(episodeID: id, chapter: chapter), pausesPlayer: true)
        case .none:
            break
        }
    }

    private func startInterlude(_ ready: PreparedInterlude, player: PlayerController) {
        let session = InterludeSession(prepared: ready, host: player, audio: AVInterludeAudio())
        session.onDontKnow = { ready in LearningCenter.shared.recordHandsFree(ready, dontKnow: true) }
        session.onFinish = { ready, dontKnow, _ in
            if !dontKnow { LearningCenter.shared.recordHandsFree(ready, dontKnow: false) }
            LearningCenter.shared.interlude = nil
            LearningCenter.shared.prepared["\(ready.episodeID)-\(ready.chapter)"] = nil
            try? FileManager.default.removeItem(at: ready.url)
        }
        asked[ready.episodeID, default: []].insert(ready.item.question)
        interlude = session
        guard session.start() else { interlude = nil; return }
        watchInterlude(session, player: player)
        guardInterlude(session)
    }

    /// Ara ses sürerken oynatıcı dışarıdan değişirse oturum kapanır (sonraki konu sonu kararları takılmasın):
    /// oynatıcı ara sesi bıraktıysa (yeni bölüm, yeniden yükleme) ses susar; podcast uygulamadan sürdürüldüyse
    /// ara ses biter ve podcast sürer (iki ses üst üste binmez).
    private func watchInterlude(_ session: InterludeSession, player: PlayerController) {
        withObservationTracking {
            _ = player.isInInterlude
            _ = player.isPlaying
        } onChange: {
            Task { @MainActor in
                guard LearningCenter.shared.interlude === session, session.state == .playing else { return }
                if !player.isInInterlude {
                    session.abandon()
                } else if player.isPlaying {
                    session.complete(resume: true)
                } else {
                    LearningCenter.shared.watchInterlude(session, player: player)
                }
            }
        }
    }

    /// Bekçi: bitiş haberi kaybolursa (ses ne çalıyor ne kesintide bekliyor) ara ses kapanır.
    private func guardInterlude(_ session: InterludeSession) {
        Task { @MainActor in
            while true {
                try? await Task.sleep(for: .seconds(5))
                guard LearningCenter.shared.interlude === session, session.watchdog() else { return }
            }
        }
    }

    /// Eller serbest sonucu: "bilemedim" karta ve yanlış defterine yazılır; sessiz geçen soru sonuçsuz kaydedilir.
    private func recordHandsFree(_ ready: PreparedInterlude, dontKnow: Bool) {
        guard let episode = fetchEpisode(ready.episodeID) else { return }
        let item = ready.item
        RecallLog.record(RecallLog.entry(item, source: "handsfree", outcome: QuestionOutcome(isCorrect: dontKnow ? false : nil)),
                         episode: episode, context: context)
        guard dontKnow else { return }
        ReviewDeck.addWrong(item, episode: episode, context: context, origin: "handsfree")
        MistakeBook.record(item, myAnswer: "Bilemedim", episode: episode, source: "handsfree", context: context,
                           podcastTime: ListenAnchor.time(for: item, timeline: episode.timeline), chapterIndex: item.chapterIndex ?? ready.chapter)
    }

    // MARK: Bölüm sonu (#26, #28)

    func episodeFinished(_ info: PodcastEventInfo) {
        guard let id = info.episodeID, let episode = fetchEpisode(id) else { return }
        ProbeAdvisor.scheduleProbes(for: episode, context: context)
        ProbeAdvisor.completeRelisten(episodeID: id, context: context)
        prepared = prepared.filter { $0.value.episodeID != id }
        guard !info.sleepTimer, ListeningMode.current.policy.endCard else { return }
        if isForeground {
            guard sheet == nil else { return }
            nextHold = NextUpHold()
            // P5 `finished()` bu olaydan hemen sonra `holdAutoplay`'i okuyup sıfırlar; sıradakinin adı burada saklanır.
            if let player, player.autoplayNext, let title = NextUpPeek.title(
                queue: player.queue,
                readyEpisodeTitle: { [self] id in fetchEpisode(id).flatMap { $0.status == .ready ? $0.title : nil } },
                seriesNext: { player.nextInSeries()?.title }) {
                player.holdAutoplay = true
                nextHold.begin(title: title)
            }
            banner = nil
            let card = LearningSheet.endCard(episodeID: id)
            sheet = card
            confirmShown(card)
        } else {
            // Arka planda sıradaki hemen başlar; kart bildirimle gelir.
            pendingEndCard = (id, .now)
            EndCardNotification.post(episode)
        }
    }

    /// Ön plana dönüldü: arka planda biten bölümün kartı öneri olarak gösterilir.
    func becameActive() {
        guard let pending = pendingEndCard else { return }
        pendingEndCard = nil
        guard Date.now.timeIntervalSince(pending.at) < 3 * 3600, sheet == nil, let episode = fetchEpisode(pending.id) else { return }
        banner = LearningBanner(symbol: "checkmark.seal", text: LearningBanner.endCardText(title: episode.title), action: "Göster",
                                sheet: .endCard(episodeID: pending.id), pausesPlayer: false)
    }

    /// Ekran kilitlendi / uygulama arka plana geçti. Bölüm sonu kartının sayacı `Task.sleep` ile işler ve ses
    /// çalmadığından iOS uygulamayı askıya alınca donar: "Bekle" denmediyse sıradaki, arka plana geçişte
    /// tanınan kısa sürede hemen başlar (sürekli dinleme kopmaz). Kart dönüşte öneri şeridi olarak gelir.
    func enteredBackground() {
        guard let id = NextUpHold.backgroundAdvance(sheet: sheet, hold: nextHold) else { return }
        pendingEndCard = (id, .now)
        playNextFromEndCard()
    }

    // MARK: Ön test (#26, sınav modu)

    func offerPretestIfNeeded(_ episode: Episode) {
        guard ListeningMode.current.policy.preTest, sheet == nil, banner == nil, !episode.isFinished, episode.lastPosition < 30,
              QuestionPicker.spread(episode.study?.quiz ?? [], count: 5).count >= 3,
              !PretestStore.declined(episode.id), PretestStore.attempts(episodeID: episode.id, context: context).isEmpty else { return }
        banner = LearningBanner(symbol: "checklist", text: "Sınav modu: dinlemeden önce 5 soruluk ön test?", action: "Başla",
                                sheet: .pretest(episodeID: episode.id), pausesPlayer: true)
    }

    // MARK: Sunum

    func accept(_ banner: LearningBanner) {
        self.banner = nil
        if banner.pausesPlayer, let player, player.isPlaying {
            player.pause()
            resumeAfterSheet = true
        }
        sheet = banner.sheet
    }

    func decline(_ banner: LearningBanner) {
        if case let .pretest(id) = banner.sheet { PretestStore.decline(id) }
        if self.banner == banner { self.banner = nil }
    }

    /// Sayfa kapandı: tutulan otomatik geçiş bırakılır, duraklatılan podcast sürer.
    func sheetShown(_ sheet: LearningSheet) { shownSheetID = sheet.id }

    /// Başka bir sayfa açıkken sunulamadıysa: tutulan otomatik geçiş bırakılır, duraklatılan podcast sürer (takılı kalmaz).
    private func confirmShown(_ target: LearningSheet) {
        shownSheetID = nil
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            let center = LearningCenter.shared
            guard center.sheet == target, center.shownSheetID != target.id else { return }
            center.sheet = nil
            center.sheetDismissed()
        }
    }

    /// Sayfa kapandı ("Kapat", kaydırma, sayaç): tutulan otomatik geçiş "Bekle" denmediyse sıradakini başlatır;
    /// duraklatılan podcast sürer.
    func sheetDismissed() {
        player?.holdAutoplay = false
        if nextHold.release() {
            resumeAfterSheet = false
            player?.playNext()
            return
        }
        if resumeAfterSheet {
            resumeAfterSheet = false
            player?.play()
        }
    }

    /// "Bekle" ya da karttan başka bir ana gidiliyor: bu bitiş için otomatik geçiş yapılmaz.
    func waitForNext() { nextHold.wait() }

    #if DEBUG
    /// `-learnDemo=endcard`: sayaç satırını görmek için sahte "sıradaki".
    func debugHoldNext(_ title: String) { nextHold.begin(title: title) }
    #endif

    /// Bölüm sonu kartı: sayaç bitti ya da "Şimdi başlat".
    func playNextFromEndCard() {
        _ = nextHold.release()   // kapanışta (sheetDismissed) ikinci kez başlatılmasın
        player?.holdAutoplay = false
        sheet = nil
        player?.playNext()
    }

    func fetchEpisode(_ id: UUID) -> Episode? {
        try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })).first
    }
}

/// Ön test kayıtları ve "geç" seçimi.
enum PretestStore {
    private static let key = "pretest.declined"

    static func declined(_ id: UUID) -> Bool {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(id.uuidString)
    }

    static func decline(_ id: UUID) {
        let list = (UserDefaults.standard.stringArray(forKey: key) ?? []).suffix(200) + [id.uuidString]
        UserDefaults.standard.set(Array(list), forKey: key)
    }

    static func attempts(episodeID: UUID, context: ModelContext) -> [RecallAttempt] {
        let id: UUID? = episodeID
        let all = (try? context.fetch(FetchDescriptor<RecallAttempt>(predicate: #Predicate { $0.episodeID == id }))) ?? []
        return all.filter { $0.source == "pretest" }.sorted { $0.createdAt < $1.createdAt }
    }
}

/// Arka planda biten bölümün kartı bildirimle gelir.
enum EndCardNotification {
    static func post(_ episode: Episode) {
        let points = (episode.script?.keyPoints ?? []).prefix(3)
        let title = episode.title
        let id = episode.id.uuidString
        let body = points.isEmpty ? "Ne öğrendin? Üç hızlı soruyla pekiştir." : "Ne öğrendin? " + points.enumerated().map { "\($0.offset + 1)) \($0.element)" }.joined(separator: " ")
        Task {
            let center = UNUserNotificationCenter.current()
            guard await NotificationGate.request(center, options: [.alert, .sound]) else { return }
            let content = UNMutableNotificationContent()
            content.title = "Bölüm bitti: \(title)"
            content.body = String(body.prefix(300))
            content.userInfo = ["episodeID": id]
            try? await center.add(UNNotificationRequest(identifier: "endcard-\(id)", content: content, trigger: nil))
        }
    }
}

// MARK: - Uygulama geneli sunum

private struct PodcastLearningOverlay: ViewModifier {
    @State private var center = LearningCenter.shared
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let banner = center.banner {
                    LearningBannerView(banner: banner)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: banner.id) {
                            try? await Task.sleep(for: .seconds(15))
                            if center.banner?.id == banner.id { center.banner = nil }
                        }
                }
            }
            .animation(.smooth, value: center.banner)
            .sheet(item: Binding(get: { center.sheet?.isInlineQuiz == true ? nil : center.sheet },
                                 set: { if $0 == nil, center.sheet?.isInlineQuiz != true { center.sheet = nil } }),
                   onDismiss: { center.sheetDismissed() }) { sheet in
                LearningSheetView(sheet: sheet)
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active: center.becameActive()
                case .background: center.enteredBackground()
                default: break
                }
            }
            #if DEBUG
            .task { LearningDebug.showIfRequested() }
            #endif
    }
}

private struct LearningBannerView: View {
    var banner: LearningBanner

    var body: some View {
        // Geniş ekranda tek satır; metne ~160 pt kalmıyorsa (320 pt, büyük yazı) metin kendi satırında, düğme altında.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                icon
                text(lines: 3).frame(minWidth: 0, idealWidth: 160, maxWidth: .infinity, alignment: .leading)
                actionButton
                closeButton
            }
            .padding(.leading, 12)
            .padding(.vertical, 4)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .top, spacing: 10) {
                    icon.padding(.top, 12)
                    text(lines: 4).padding(.top, 12).frame(maxWidth: .infinity, alignment: .leading)
                    closeButton
                }
                actionButton.padding(.trailing, 12)
            }
            .padding(.leading, 12)
            .padding(.bottom, 10)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private var icon: some View {
        Image(systemName: banner.symbol).font(.title3).foregroundStyle(.tint).accessibilityHidden(true)
    }

    private func text(lines: Int) -> some View {
        Text(banner.text).font(.subheadline.weight(.semibold)).lineLimit(lines).minimumScaleFactor(0.85)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actionButton: some View {
        Button(banner.action) { LearningCenter.shared.accept(banner) }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
    }

    private var closeButton: some View {
        Button {
            LearningCenter.shared.decline(banner)
        } label: {
            Image(systemName: "xmark").font(.subheadline.bold()).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Geç")
    }
}

struct LearningSheetView: View {
    var sheet: LearningSheet
    @Environment(\.modelContext) private var context

    var body: some View {
        content
            .debugNarrowSheet()   // yalnız DEBUG: sayfalar da 320 pt denetlensin
            .onAppear { LearningCenter.shared.sheetShown(sheet) }
    }

    @ViewBuilder private var content: some View {
        switch sheet {
        case let .inlineQuiz(id, chapter, item, think):
            if let episode = LearningCenter.shared.fetchEpisode(id) {
                InlineQuizSheet(item: item, thinkSeconds: think, episode: episode,
                                showConfidence: ListeningMode.current.policy.confidence,
                                onOutcome: { outcome in
                                    InlineQuizResult.record(item, outcome: outcome, chapter: chapter, episode: episode, context: context)
                                },
                                done: { _ in LearningCenter.shared.sheet = nil })
                .presentationDetents([.medium, .large])
                .interactiveDismissDisabled()
            }
        case let .recall(id, chapter):
            if let episode = LearningCenter.shared.fetchEpisode(id) {
                RecallPromptView(episode: episode, chapter: chapter)
            }
        case let .endCard(id):
            if let episode = LearningCenter.shared.fetchEpisode(id) {
                EpisodeEndCard(episode: episode)
            }
        case let .pretest(id):
            if let episode = LearningCenter.shared.fetchEpisode(id) {
                PretestView(episode: episode)
            }
        }
    }
}

/// Dinlerken quiz sonucu: günlük + (yanlışsa) kart ve yanlış defteri (an ve konu ile).
enum InlineQuizResult {
    static func record(_ item: QuizItem, outcome: QuestionOutcome, chapter: Int, episode: Episode, context: ModelContext) {
        var entry = RecallLog.entry(item, source: "inline", outcome: outcome)
        entry.chapterIndex = item.chapterIndex ?? chapter
        RecallLog.record(entry, episode: episode, context: context)
        guard outcome.isCorrect == false else { return }
        ReviewDeck.addWrong(item, episode: episode, context: context, origin: "inline")
        let mine = outcome.chosenIndex.flatMap { item.options[safe: $0] } ?? outcome.answerText ?? ""
        MistakeBook.record(item, myAnswer: mine, episode: episode, source: "inline", context: context,
                           podcastTime: ListenAnchor.time(for: item, timeline: episode.timeline), chapterIndex: item.chapterIndex ?? chapter)
    }
}

extension View {
    /// Uygulama geneli öğrenme sunumu (dinlerken quiz, anlatarak hatırla, bölüm sonu kartı, ön test).
    func podcastLearningOverlay() -> some View { modifier(PodcastLearningOverlay()) }
}

extension View {
    /// `-narrow320`: sayfa içeriği 320 pt'ye sığdırılır (yazı boyu sunan ekrandan gelir; sayfa zemini korunur). Release'te etkisiz.
    @ViewBuilder func debugNarrowSheet() -> some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-narrow320") {
            frame(width: 320).frame(maxWidth: .infinity)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if DEBUG
/// Ekran görüntüsü denetimi: `-learnDemo=endcard|recall|quiz|pretest|banner|endbanner` son hazır bölümle sayfayı açar.
enum LearningDebug {
    static func showIfRequested() {
        guard let which = DebugArg.value("learnDemo"), LearningCenter.shared.sheet == nil else { return }
        let context = AppDataStore.container.mainContext
        var descriptor = FetchDescriptor<Episode>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 20
        let ready = ((try? context.fetch(descriptor)) ?? []).filter { $0.status == .ready }
        guard let episode = ready.first(where: { $0.study != nil }) ?? ready.first else { return }
        let item = episode.study?.quiz.first ?? QuizItem(question: "Hücre zarının seçici geçirgenliği neyi sağlar?",
                                                         options: ["Madde alışverişini denetler", "Enerji üretir", "Protein sentezler", "Bölünmeyi başlatır"],
                                                         answerIndex: 0, explanation: "Zar, hangi maddelerin geçeceğini belirler.", chapterIndex: 0, turnIndex: 0)
        switch which {
        case "endcard":
            if episode.study == nil {
                let more = [QuizItem(question: "Kornea neden saydamdır?", options: ["Damarsızdır", "Pigment içerir", "Kas içerir", "Sinir uçları yoktur"],
                                     answerIndex: 0, explanation: "Damar yoktur; ışık engellenmez.", chapterIndex: 1, turnIndex: 2),
                            QuizItem(question: "Işık göze girerken ilk nerede kırılır?", options: ["Göz merceği", "Kornea", "Retina", "Camsı cisim"],
                                     answerIndex: 1, explanation: "İlk kırılma korneada olur.", chapterIndex: 1, turnIndex: 2)]
                episode.study = StudyPack(quiz: [item] + more, flashcards: [], concepts: nil, formulas: nil)
            }
            LearningCenter.shared.debugHoldNext("Gözün iç tabakası: retina, çubuklar ve koniler")
            LearningCenter.shared.sheet = .endCard(episodeID: episode.id)
        case "recall": LearningCenter.shared.sheet = .recall(episodeID: episode.id, chapter: 0)
        case "quiz":
            // Dinlerken quiz bölüm ekranından sunulur: önce bölüm açılır.
            AppState.current?.open(episode.id)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                LearningCenter.shared.sheet = .inlineQuiz(episodeID: episode.id, chapter: 0, item: item, think: 5)
            }
        case "pretest": LearningCenter.shared.sheet = .pretest(episodeID: episode.id)
        case "endbanner":
            // Arka planda biten bölümün dönüş şeridi (en uzun metin: bölüm başlığı).
            LearningCenter.shared.banner = LearningBanner(symbol: "checkmark.seal", text: LearningBanner.endCardText(title: episode.title),
                                                          action: "Göster", sheet: .endCard(episodeID: episode.id), pausesPlayer: false)
        default:
            LearningCenter.shared.banner = LearningBanner(symbol: "text.bubble", text: "Konu bitti. 45 saniyede aklında kalanları anlat.",
                                                          action: "Anlat", sheet: .recall(episodeID: episode.id, chapter: 0), pausesPlayer: true)
        }
    }
}
#endif
