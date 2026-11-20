import AVFoundation
import MediaPlayer
import Observation
import SwiftData
import SwiftUI
import UIKit

/// Kilit ekranı / kulaklık komutu.
nonisolated enum RemoteCommand: Sendable, Equatable {
    case play, pause, toggle
    case skip(Double)
    case seek(Double)
    /// Kilit ekranı/kulaklık sonraki/önceki parça: podcast'te sonraki/önceki konu.
    case nextChapter, previousChapter
}

/// Kilit ekranı komutlarını ve Now Playing'i geçici olarak devralan başka bir oynatıcı (ör. YouTube dersinin ses kipi).
/// Komut hedefleri ana oynatıcıda tek kez bağlıdır; devralan varken komutlar ona gider, bırakınca ana oynatıcıya döner.
@MainActor
protocol RemoteCommandOwner: AnyObject {
    func handleRemote(_ command: RemoteCommand)
}

/// Kuyruktan çalan bölüm dışı ses (ör. günün brifingi).
nonisolated struct QueueAudio: Hashable, Sendable {
    var fileName: String
    var title: String
}

/// Kesit oturumu başlamadan önce bölümün dinleme durumu; oturum bitince geri yazılır (kesit, kaldığın yeri bozmaz).
nonisolated struct ClipResume: Equatable, Sendable {
    var position: Double
    var finished: Bool
    var lastPlayedAt: Date?
}

@Observable
final class PlayerController {
    private(set) var episode: Episode?
    private(set) var timeline: Timeline?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var currentTurnIndex: Int?
    private(set) var currentChapterIndex = 0
    /// Bölüm sesindeki sessizlikler (okurken takip yalnızca konuşulan süreye dağıtılır); ölçülene dek boş.
    private(set) var pauses: [FollowAlong.Pause] = []
    private var pausesTask: Task<Void, Never>?
    /// #17: hız kalıcıdır (`player.rate`).
    var rate: Float = PlayerController.storedRate() {
        didSet {
            if isPlaying { player?.rate = rate }
            UserDefaults.standard.set(rate, forKey: Self.rateKey)
            updateNowPlaying()
        }
    }

    static let rates: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    nonisolated static let rateKey = "player.rate"
    nonisolated static let skipSilenceKey = "player.skipSilence"

    nonisolated static func storedRate(_ defaults: UserDefaults = .standard) -> Float {
        guard let value = defaults.object(forKey: rateKey) as? Float, value >= 0.5, value <= 3 else { return 1.0 }
        return value
    }

    nonisolated enum SleepTimer: Equatable, Sendable {
        case until(Date)
        case endOfChapter(Int)
        case endOfEpisode
    }

    /// Süreli zamanlayıcının süresi doldu mu (saf). Tik yalnız çalarken geldiği için ara ses ya da kesinti içinde
    /// dolan süre, çalmayı kendiliğinden sürdüren yollarda bununla yakalanır.
    nonisolated static func sleepExpired(_ timer: SleepTimer?, now: Date = .now) -> Bool {
        if case let .until(date) = timer { return date <= now }
        return false
    }

    /// Durum gözlemcisi "oynatıcı durdu" dediğinde arayüz de duraklatılmış işaretlensin mi (saf). Gözlemcinin
    /// yakaladığı değer bayatlayabilir: aynı blokta pause() ardından play() gelirse (kesit oturumunu bitirip hemen
    /// çalan yollar) bildirim çalma başladıktan sonra işlenir. Bu yüzden oynatıcının o anki hızına bakılır.
    nonisolated static func confirmsPause(observedPaused: Bool, isPlaying: Bool, samePlayer: Bool, liveRate: Float, fading: Bool) -> Bool {
        observedPaused && isPlaying && samePlayer && liveRate == 0 && !fading
    }

    /// Uyku zamanlayıcısı; nil = kapalı.
    private(set) var sleepTimer: SleepTimer?
    /// Seride bir bölüm bitince sıradakini otomatik çal.
    var autoplayNext = true
    /// #26: true iken bölüm sonunda otomatik geçiş yapılmaz (yalnız o bitiş için; sonra kendiliğinden kalkar).
    var holdAutoplay = false
    /// #25: interlude süresince kulaklık komutları önce buna sorulur (true = tüketildi).
    @ObservationIgnored var interludeRemoteHandler: ((RemoteCommand) -> Bool)?

    /// #22: uzun sessizlikleri atla.
    var skipSilence: Bool = UserDefaults.standard.bool(forKey: PlayerController.skipSilenceKey) {
        didSet { UserDefaults.standard.set(skipSilence, forKey: Self.skipSilenceKey) }
    }
    /// #22: A–B döngüsü; `loopStart` A seçilip B beklenirken doludur.
    private(set) var loop: ABLoop?
    private(set) var loopStart: Double?
    /// #41: sıradakiler (`player.queue`).
    private(set) var queue: [PlaybackQueueItem] = PlaybackQueue.load()
    /// #41: çalan bölüm dışı ses (brifing).
    private(set) var audioItem: QueueAudio?
    /// #25: ara ses (eller serbest yoklama) sürüyor.
    private(set) var interludeActive = false
    /// #22/#33: kesit oturumu ilerlemesi (1 tabanlı sıra, toplam).
    private(set) var clipProgress: (index: Int, count: Int)?

    func setSleepTimer(minutes: Int) {
        sleepTimer = .until(.now.addingTimeInterval(Double(minutes) * 60))
    }

    func setSleepTimerEndOfChapter() { sleepTimer = .endOfChapter(currentChapterIndex) }
    func setSleepTimerEndOfEpisode() { sleepTimer = .endOfEpisode }
    func cancelSleepTimer() {
        sleepTimer = nil
        cancelFade()
    }

    private func trackListening() {
        let now = Date.now
        defer { listenTickAt = isPlaying ? now : nil }
        guard isPlaying, let last = listenTickAt else { return }
        listenedPending += min(1.5, now.timeIntervalSince(last))
        if listenedPending >= 10 { flushListening(at: now) }
    }

    /// #50: biriken dinleme süresini ÇALAN bölüme yazar ve boşaltır (bölüm değişmeden önce çağrılır).
    func flushListening(at now: Date = .now) {
        defer { listenedPending = 0 }
        guard listenedPending > 0, let context else { return }
        let key = ListeningDay.key(for: now)
        let day = (try? context.fetch(FetchDescriptor<ListeningDay>(predicate: #Predicate { $0.day == key })).first) ?? {
            let new = ListeningDay(day: key)
            context.insert(new)
            return new
        }()
        day.seconds += listenedPending
        if let id = episode?.id {
            var ids = (day.episodesData.flatMap { try? JSONDecoder().decode([UUID].self, from: $0) }) ?? []
            if !ids.contains(id) { ids.append(id); day.episodesData = try? JSONEncoder().encode(ids) }
        }
        try? context.save()
    }

    private func cancelFade() {
        fadeTask?.cancel()
        fadeTask = nil
        player?.volume = 1
    }

    var sleepRemaining: TimeInterval? {
        if case let .until(date) = sleepTimer { return max(0, date.timeIntervalSinceNow) }
        return nil
    }

    /// Mini oynatıcı ve kilit ekranı için: bir bölüm ya da kuyruk sesi yüklü mü.
    var isActive: Bool { episode != nil || audioItem != nil }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private(set) var context: ModelContext?
    private var lastSavedPosition: Double = 0
    private var fadeTask: Task<Void, Never>?
    private var statusObservation: NSKeyValueObservation?
    /// Dinleme istatistiği (öneri 5): gerçek geçen süre, 10 sn'de bir günlük kayda yazılır.
    @ObservationIgnored private var listenTickAt: Date?
    @ObservationIgnored var listenedPending: Double = 0
    /// seek sonrası ilk tick'te konu sınırı "doğal ilerleme" sayılmaz (dinlerken quiz, konu sonu zamanlayıcısı).
    @ObservationIgnored private var suppressBoundary = false
    /// Komutları geçici olarak devralan oynatıcı; varken Now Playing'e de bu denetleyici yazmaz.
    @ObservationIgnored private weak var remoteOwner: (any RemoteCommandOwner)?
    /// Kullanıcı çalmak istiyor mu (kesinti bitince sürdürmek için; sistem duraklatması bunu silmez).
    @ObservationIgnored private var playIntent = false
    @ObservationIgnored private var resumeAfterInterruption = false
    /// Bölüm sonuna gelindi: sonraki "oynat" baştan başlar.
    @ObservationIgnored private var reachedEnd = false
    @ObservationIgnored private var interludeWasPlaying = false
    @ObservationIgnored private var artworkCache: (id: String, artwork: MPMediaItemArtwork)?
    @ObservationIgnored private var clipState: ClipState?
    /// Bölüm kesit oturumunda yüklendi ("son dinlenen" yazılmadı): olağan ilk oynatmada yazılır.
    @ObservationIgnored private var needsPlayedStamp = false
    /// #16/#41: kuyruk/seri bir sonraki bölüme geçti. Gezinme kararı görünümündür (yalnız eski bölümün sayfası
    /// en üstteyse ve üstünde kapak/sayfa yoksa takip eder; göz atan kullanıcı yerinden oynatılmaz).
    private(set) var lastAdvance: QueueAdvance?

    struct QueueAdvance: Equatable {
        let from: UUID?
        let to: UUID
        let token = UUID()
    }

    /// Kuyruğun saklandığı yer (testler ayrı bir alan verir).
    @ObservationIgnored var queueStore: UserDefaults = .standard

    private struct ClipState {
        var clips: [PodcastClip]
        var index: Int
        var waiting: Bool
        var onClipEnd: @MainActor (PodcastClip) async -> Void
        /// Oturumun dokunduğu bölümlerin önceki durumu (bölüm başına ilk kesitte bir kez alınır).
        var resume: [UUID: ClipResume] = [:]
    }

    /// Kilit ekranı komutlarını başka bir oynatıcıya verir (Now Playing'i o yazar).
    func lendRemoteCommands(to owner: any RemoteCommandOwner) {
        remoteOwner = owner
    }

    /// Komutlar (ve Now Playing) şu an bu oynatıcıda mı.
    func ownsRemoteCommands(_ owner: any RemoteCommandOwner) -> Bool { remoteOwner === owner }

    /// Komutları geri alır; yalnızca o anki devralan bırakabilir. Now Playing ana oynatıcının bölümüne döner.
    func reclaimRemoteCommands(from owner: any RemoteCommandOwner) {
        guard remoteOwner === owner else { return }
        remoteOwner = nil
        if isActive { updateNowPlaying() } else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
    }

    init() {
        configureRemoteCommands()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            MainActor.assumeIsolated {
                if type == .began { self?.interruptionBegan() }
                if type == .ended { self?.interruptionEnded(shouldResume: options.contains(.shouldResume)) }
            }
        }
        // #17: kulaklık çıkarıldı / araç Bluetooth'u koptu: sistem durdurur; bu "kullanıcı durdurdu" sayılır
        // (sonraki bir arama bitince podcast hoparlörden kendiliğinden başlamasın).
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            MainActor.assumeIsolated {
                if reason == .oldDeviceUnavailable { self?.routeDeviceLost() }
            }
        }
    }

    func load(_ episode: Episode, context: ModelContext, autoplay: Bool = true) {
        if self.episode?.id == episode.id {
            if autoplay, !isPlaying { play() }
            return
        }
        endClipSession()
        loadEpisode(episode, context: context, autoplay: autoplay)
    }

    private func loadEpisode(_ episode: Episode, context: ModelContext, autoplay: Bool) {
        guard let url = episode.audioURL, FileManager.default.fileExists(atPath: url.path) else { return }
        saveProgress()
        teardown()

        self.episode = episode
        audioItem = nil
        self.context = context
        timeline = episode.timeline
        duration = episode.duration
        // Kesit oturumu "son dinlenen"i değiştirmez (hiç dinlenmemiş bölüm "Devam et"e çıkmasın).
        if clipState == nil { episode.lastPlayedAt = .now }
        needsPlayedStamp = clipState != nil
        let id = episode.id
        pausesTask = Task { [weak self] in
            let found = await SpeechPauses.load(audioURL: url)
            guard let self, !Task.isCancelled, self.episode?.id == id else { return }
            self.pauses = found
        }
        attach(url: url)

        let start = episode.isFinished || episode.lastPosition > episode.duration - 3 ? 0 : episode.lastPosition
        move(to: start)
        if autoplay { play() }
    }

    /// #41: bölüm dışı kuyruk sesi (brifing).
    private func loadAudio(_ item: QueueAudio, context: ModelContext?) {
        let url = BriefingFiles.directory.appending(path: item.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        saveProgress()
        teardown()
        episode = nil
        timeline = nil
        audioItem = item
        if let context { self.context = context }
        duration = (try? AVAudioFile(forReading: url)).map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0
        attach(url: url)
        play()
    }

    private func attach(url: URL) {
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain
        let player = AVPlayer(playerItem: item)
        self.player = player
        // Ses oturumu başka bir özellik tarafından kapatılırsa oynatıcı durur: arayüz "çalıyor" göstermesin.
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let paused = player.timeControlStatus == .paused
            Task { @MainActor in
                guard let self, PlayerController.confirmsPause(observedPaused: paused, isPlaying: self.isPlaying,
                                                               samePlayer: self.player === player, liveRate: player.rate,
                                                               fading: self.fadeTask != nil) else { return }
                self.markPaused()
            }
        }

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finished() }
        }
    }

    func play() {
        guard let player else { return }
        // #22: kesit sonu sorusu beklenirken "oynat" (kilit ekranı, mini oynatıcı): soru geçilir, sonraki kesit çalar
        // (bölüm kesit dışına doğru çalmaz).
        if clipState?.waiting == true { return advanceClip() }
        // Komutları tutan başka oynatıcı (ders sesi) susar; kilit ekranı bu bölüme döner (iki ses üst üste binmesin).
        if let owner = remoteOwner {
            reclaimRemoteCommands(from: owner)
            owner.handleRemote(.pause)
        }
        cancelFade()
        // #17: bitmiş bölümde "oynat" baştan başlar.
        if reachedEnd { move(to: 0) }
        // Duraklatılmışken süresi dolmuş zamanlayıcı, devam edince hemen kesmesin.
        if case let .until(date) = sleepTimer, date <= .now { sleepTimer = nil }
        // Kesit dinlemek "dinlendi" bölümü yarım göstermez.
        if clipState == nil {
            episode?.isFinished = false
            if needsPlayedStamp {
                needsPlayedStamp = false
                episode?.lastPlayedAt = .now
            }
        }
        activateSession()
        player.playImmediately(atRate: rate)
        isPlaying = true
        playIntent = true
        updateNowPlaying()
    }

    func pause() {
        player?.pause()
        playIntent = false
        markPaused()
    }

    func toggle() { isPlaying ? pause() : play() }

    /// Kullanıcı gezinmesi (çubuk, ±15, konu ileri/geri, not, kelime, kilit ekranı). Açık kesit oturumunda hedef
    /// kesitin dışına düşerse oturum biter ve dinleme hedeften olağan sürer (konum yeniden yazılır, kesit sonunda
    /// geri sarılmaz).
    func seek(to time: Double) {
        let target = min(max(0, time), max(duration - 0.1, 0))
        let resume = leaveClipSession(seekingTo: target)
        move(to: target)
        if resume { play() }
    }

    /// İç atlama (kesit başı, oturum sonu geri sarma, yükleme, döngü): kesit oturumuna dokunmaz.
    private func move(to time: Double) {
        let clamped = min(max(0, time), max(duration - 0.1, 0))
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        reachedEnd = false
        suppressBoundary = true
        tick(clamped)
        updateNowPlaying()
    }

    /// Hedef çalan kesitin dışındaysa oturumu bitirir (`ClipSeek.leaves`). Döner: çalma sürdürülmeli mi
    /// (`endClipSession` sesi durdurur).
    private func leaveClipSession(seekingTo time: Double) -> Bool {
        guard let state = clipState, !state.waiting, let clip = state.clips[safe: state.index], episode?.id == clip.episodeID,
              ClipSeek.leaves(time, clipStart: clip.start, clipEnd: clip.end, hasNext: state.index + 1 < state.clips.count)
        else { return false }
        let wasPlaying = isPlaying
        endClipSession()
        return wasPlaying
    }

    /// Doğal ilerleme sayılan atlama (düşünme payı/sessizlik atlama): konu sınırı olayları susturulmaz.
    private func advance(to time: Double) {
        let clamped = min(max(0, time), max(duration - 0.1, 0))
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
    }

    func skip(_ seconds: Double) { seek(to: currentTime + seconds) }

    func jump(toChapter index: Int) {
        guard let chapter = timeline?.chapters[safe: index] else { return }
        endClipSession()   // `play(_:at:)` gibi: bölümde gezinmek kesit oturumunu bitirir
        seek(to: chapter.start)
        if !isPlaying { play() }
    }

    func jump(toTurn index: Int) {
        guard let turn = timeline?.turns[safe: index] else { return }
        endClipSession()
        seek(to: turn.start)
        if !isPlaying { play() }
    }

    /// #17: konu ileri/geri hedefi (kilit ekranı, kulaklık, Siri). Konu yoksa nil.
    nonisolated static func chapterTarget(from time: Double, timeline: Timeline?, forward: Bool) -> Double? {
        guard let chapters = timeline?.chapters, !chapters.isEmpty else { return nil }
        return ChapterNav.target(from: time, starts: chapters.map(\.start), forward: forward)
    }

    /// Sonraki konu; son konudaysa sıradaki bölüm (varsa). Döner: gidildi mi.
    @discardableResult
    func nextChapter() -> Bool {
        if let target = Self.chapterTarget(from: currentTime, timeline: timeline, forward: true) {
            seek(to: target)
            return true
        }
        guard nextUp() != nil || !queue.isEmpty else { return false }
        playNext()
        return true
    }

    @discardableResult
    func previousChapter() -> Bool {
        guard let target = Self.chapterTarget(from: currentTime, timeline: timeline, forward: false) else { return false }
        seek(to: target)
        return true
    }

    func close() {
        endClipSession()
        saveProgress()
        teardown()
        episode = nil
        audioItem = nil
        timeline = nil
        if remoteOwner == nil { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
    }

    /// Sesli soru için: oynatıcı duraklar, oturum serbest kalır.
    func suspendForLiveSession() {
        pause()
        saveProgress()
    }

    /// Sesi değişen bölümü (sahne düzenleme, konu çıkarma) aynı konumdan yeniden yükler.
    func reloadIfLoaded(_ id: UUID) {
        guard let episode, episode.id == id, let context else { return }
        let wasPlaying = isPlaying
        let position = currentTime
        saveProgress()
        teardown()
        self.episode = nil
        loadEpisode(episode, context: context, autoplay: false)
        if self.episode != nil {
            move(to: min(position, max(0, duration - 1)))
            if wasPlaying { play() }
        }
    }

    // MARK: - #18/#19/#22 işaretler

    /// Çalan ana yer imi koyar. `kind`: "note" | "confused" | "flag" | "siri".
    @discardableResult
    func addBookmark(kind: String, note: String = "") -> Bookmark? {
        guard let episode, let context else { return nil }
        let text = timeline.flatMap { t in currentTurnIndex.flatMap { t.turns[safe: $0]?.text } } ?? ""
        let mark = Bookmark(episode: episode, time: currentTime, text: text, note: note)
        mark.kind = kind
        mark.chapterIndex = timeline == nil ? nil : currentChapterIndex
        context.insert(mark)
        try? context.save()
        return mark
    }

    // MARK: - #22 A–B döngüsü

    /// Tek düğme: A'yı koy → B'yi koy (döngü başlar) → kapat. B, A'ya çok yakınsa döngü kurulmaz.
    func cycleLoop() {
        if loop != nil {
            clearLoop()
        } else if let start = loopStart {
            if currentTime - start >= ABLoop.minLength { setLoop(start: start, end: currentTime) } else { clearLoop() }
        } else {
            loopStart = currentTime
        }
    }

    func setLoop(start: Double, end: Double) {
        loopStart = nil
        loop = ABLoop(start: start, end: end)
        if let loop { seek(to: loop.start) }
    }

    func clearLoop() {
        loop = nil
        loopStart = nil
    }

    // MARK: - #25 interlude (ara ses)

    /// Konu sonunda ara sesi başlatmak için oynatıcıyı duraklatır (oturum açık kalır). Mümkün değilse false.
    func beginInterlude() -> Bool {
        guard episode != nil, player != nil, !interludeActive, clipState == nil else { return false }
        interludeActive = true
        interludeWasPlaying = isPlaying
        player?.pause()
        isPlaying = false
        saveProgress()
        updateNowPlaying()
        return true
    }

    /// Ara ses bitti: istenirse ve öncesinde çalıyorsa podcast sürer.
    func endInterlude(resume: Bool) {
        guard interludeActive else { return }
        interludeActive = false
        interludeRemoteHandler = nil
        // Zamanlayıcı ara ses sürerken dolduysa podcast kendiliğinden sürmez (`play()` dolmuş zamanlayıcıyı siler).
        let expired = Self.sleepExpired(sleepTimer)
        if expired { sleepTimer = nil }
        let shouldPlay = resume && interludeWasPlaying && !expired
        interludeWasPlaying = false
        if shouldPlay { play() } else {
            playIntent = false
            updateNowPlaying()
        }
    }

    // MARK: - #22/#33 kesitler

    func startClips(_ clips: [PodcastClip], context: ModelContext, onClipEnd: @escaping @MainActor (PodcastClip) async -> Void) {
        endClipSession()
        // Oturum boyunca konum kaydı kapalıdır: yüklü bölümün kaldığı yer şimdi yazılır.
        saveProgress()
        let playable = clips.filter { $0.end > $0.start }
        guard !playable.isEmpty else { return }
        clipState = ClipState(clips: playable, index: -1, waiting: false, onClipEnd: onClipEnd)
        self.context = context
        advanceClip()
    }

    private func advanceClip() {
        guard var state = clipState, let context else { return endClipSession() }
        state.index += 1
        state.waiting = false
        clipState = state
        guard let clip = state.clips[safe: state.index] else { return endClipSession() }
        clipProgress = (state.index + 1, state.clips.count)
        let id = clip.episodeID
        guard let target = try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })).first,
              target.status == .ready else { return advanceClip() }
        if state.resume[target.id] == nil {
            state.resume[target.id] = ClipResume(position: target.lastPosition, finished: target.isFinished,
                                                 lastPlayedAt: target.lastPlayedAt)
            clipState = state
        }
        if episode?.id != target.id { loadEpisode(target, context: context, autoplay: false) }
        guard episode?.id == target.id else { return advanceClip() }
        move(to: clip.start)
        play()
    }

    /// Kesit bitti mi: duraklat, soruyu bekle, sonrakine geç. Döner: tik işlendi mi.
    private func handleClipEnd(_ time: Double) -> Bool {
        guard var state = clipState, !state.waiting, let clip = state.clips[safe: state.index],
              episode?.id == clip.episodeID, time >= clip.end else { return false }
        state.waiting = true
        clipState = state
        player?.pause()
        playIntent = false   // #17: soru beklerken gelen arama bitince bölüm kesit dışına çalmasın
        markPaused()
        let handler = state.onClipEnd
        let index = state.index
        Task { [weak self] in
            await handler(clip)
            // Bu arada kesit geçildiyse (oynat ile) ya da oturum bittiyse bir şey yapma.
            guard let self, let current = self.clipState, current.waiting, current.index == index else { return }
            self.advanceClip()
        }
        return true
    }

    /// Oturumu bitirir. Yüklü bölüm kesit öncesindeki hâline döner: ses durur (kesitin ötesine çalmaz),
    /// kaldığı yer, "dinlendi" ve "son dinlenen" geri yazılır. Ardından gelen yükleme/atlama bunun üstüne yazar.
    func endClipSession() {
        guard let state = clipState else {
            clipProgress = nil
            return
        }
        clipState = nil
        clipProgress = nil
        guard let episode, let resume = state.resume[episode.id] else { return }
        player?.pause()
        playIntent = false
        isPlaying = false
        episode.isFinished = resume.finished
        episode.lastPlayedAt = resume.lastPlayedAt
        move(to: resume.finished ? 0 : resume.position)
        episode.lastPosition = resume.position
        lastSavedPosition = currentTime
        try? context?.save()
        updateNowPlaying()
    }

    var isPlayingClips: Bool { clipState != nil }

    // MARK: - #41 kuyruk

    func addToQueue(_ item: PlaybackQueueItem) {
        queue = PlaybackQueue.appending(item, to: queue)
        PlaybackQueue.save(queue, queueStore)
    }

    func setQueue(_ items: [PlaybackQueueItem]) {
        queue = items
        PlaybackQueue.save(queue, queueStore)
    }

    func removeFromQueue(at offsets: IndexSet) {
        var items = queue
        items.remove(atOffsets: offsets)
        setQueue(items)
    }

    func removeFromQueue(episodeID: UUID) {
        setQueue(PlaybackQueue.removing(episodeID: episodeID, from: queue))
    }

    /// Kuyruktaki ilk çalınabilir öğeyi çalar; kuyruk boşsa serideki sıradaki bölüm. Döner: bir şey başladı mı.
    @discardableResult
    func advanceQueue(context explicit: ModelContext? = nil) -> Bool {
        holdAutoplay = false
        let previous = episode?.id
        let context = explicit ?? self.context
        if let explicit { self.context = explicit }
        while let item = queue.first {
            setQueue(Array(queue.dropFirst()))
            switch item {
            case let .episode(id):
                guard let context,
                      let next = try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })).first,
                      next.status == .ready else { continue }
                endClipSession()
                loadEpisode(next, context: context, autoplay: true)
                guard episode?.id == next.id else { continue }
                lastAdvance = QueueAdvance(from: previous, to: next.id)
                return true
            case let .audio(fileName, title):
                endClipSession()
                loadAudio(QueueAudio(fileName: fileName, title: title), context: context)
                if audioItem?.fileName == fileName { return true }
            }
        }
        if let next = nextInSeries(), let context {
            endClipSession()
            loadEpisode(next, context: context, autoplay: true)
            guard episode?.id == next.id else { return false }
            lastAdvance = QueueAdvance(from: previous, to: next.id)
            return true
        }
        return false
    }

    /// Sıradaki bölüm (kuyruk önce, sonra seri); P6'nın bölüm sonu kartı gösterir.
    func upcomingEpisode() -> Episode? {
        guard let context else { return nil }
        for case let .episode(id) in queue {
            if let next = try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })).first,
               next.status == .ready { return next }
        }
        return nextInSeries()
    }

    // MARK: - İç işleyiş

    private func tick(_ time: Double) {
        guard time.isFinite else { return }
        trackListening()
        currentTime = time
        if let timeline {
            let turn = timeline.turnIndex(at: time)
            if turn != currentTurnIndex { currentTurnIndex = turn }
            let chapter = timeline.chapterIndex(at: time)
            if chapter != currentChapterIndex {
                let previous = currentChapterIndex
                currentChapterIndex = chapter
                updateNowPlaying()
                let natural = !suppressBoundary && isPlaying && chapter == previous + 1 && clipState == nil
                if case let .endOfChapter(target) = sleepTimer, previous == target || chapter != target {
                    // Zamanlayıcının konusundan çıkıldı: doğal ilerlemede dur, atlamada zamanlayıcıyı bırak.
                    sleepTimer = nil
                    if natural {
                        pause()
                        suppressBoundary = false
                        return
                    }
                }
                if natural {
                    if let id = episode?.id { PodcastEvent.post(PodcastEvent.chapterFinished, episodeID: id, chapter: previous) }
                }
            }
        }
        suppressBoundary = false
        if case let .until(date) = sleepTimer, date <= .now, isPlaying {
            sleepTimer = nil
            fadeOutAndPause()
        }
        if abs(time - lastSavedPosition) > 10 { saveProgress() }
        guard isPlaying else { return }
        if handleClipEnd(time) { return }
        if let loop {
            switch loop.action(at: time) {
            case let .wrap(to): move(to: to); return
            case .cancel: self.loop = nil
            case .none: break
            }
        }
        let thinkPauses = timeline?.thinkPauses ?? []
        let skipThink = !thinkPauses.isEmpty && !ListeningMode.current.policy.playThinkPauses
        if let target = ListeningSkip.target(at: time, thinkPauses: thinkPauses, skipThink: skipThink,
                                              silences: skipSilence ? pauses : []) {
            advance(to: target)
        }
    }

    /// Bölüm sonu. Önce `.episodeFinished` yayılır (P6 `holdAutoplay` kurabilir), sonra otomatik geçiş kararı verilir.
    func finished() {
        isPlaying = false
        playIntent = false
        reachedEnd = true
        if clipState != nil {
            // Kesit bölüm sonuna dayandı: kesit bitmiş sayılır (bölüm "dinlendi" sayılmaz, olay yayılmaz).
            _ = handleClipEnd(.infinity)
            return
        }
        currentTime = 0
        episode?.isFinished = true
        episode?.lastPosition = 0
        lastSavedPosition = 0
        try? context?.save()
        updateNowPlaying()
        if let id = episode?.id { PodcastEvent.post(PodcastEvent.episodeFinished, episodeID: id, sleepTimer: sleepTimer != nil) }
        let hold = holdAutoplay
        holdAutoplay = false
        // Herhangi bir uyku zamanlayıcısı kuruluysa bölüm sonunda dur; sıradakine geçme.
        if sleepTimer != nil {
            sleepTimer = nil
            return
        }
        if autoplayNext, !hold, !interludeActive {
            advanceQueue()
        }
    }

    /// Aynı serideki sıradaki hazır bölüm. Sıra boşluklu olabilir (silinen ya da taşınan bölüm seriyi yeniden
    /// numaralamaz): hangi bölümün sıradaki olduğuna `SeriesOrder.next` karar verir.
    func nextInSeries() -> Episode? {
        guard let episode, let series = episode.seriesID, let context else { return nil }
        let current = episode.seriesIndex
        let descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.seriesID == series && $0.seriesIndex > current })
        guard let later = try? context.fetch(descriptor),
              let next = SeriesOrder.next(after: current, members: later.map { (id: $0.id, index: $0.seriesIndex, status: $0.status) })
        else { return nil }
        return later.first { $0.id == next }
    }

    /// Uyku zamanlayıcısı: 4 sn'de sesi kısıp duraklat.
    private func fadeOutAndPause() {
        guard let player else { return }
        fadeTask?.cancel()
        fadeTask = Task { [weak self] in
            for step in stride(from: 1.0, through: 0.0, by: -0.1) {
                guard !Task.isCancelled, self?.player === player else { return }
                player.volume = Float(step)
                try? await Task.sleep(for: .milliseconds(400))
            }
            guard !Task.isCancelled, let self, self.player === player else { return }
            self.pause()
            player.volume = 1
            self.fadeTask = nil
        }
    }

    private func markPaused() {
        isPlaying = false
        saveProgress()
        updateNowPlaying()
    }

    private func interruptionBegan() {
        resumeAfterInterruption = playIntent
        markPaused()
    }

    /// Çıkış aygıtı kayboldu: sistem duraklatması kullanıcı duraklatması gibi sayılır.
    func routeDeviceLost() {
        playIntent = false
        resumeAfterInterruption = false
    }

    /// #17: kesinti (arama, alarm) bitince sistem "sürdür" diyorsa ve öncesinde çalıyorsa devam.
    func interruptionEnded(shouldResume: Bool) {
        defer { resumeAfterInterruption = false }
        guard shouldResume, resumeAfterInterruption, player != nil, !interludeActive else { return }
        // Zamanlayıcı kesinti sürerken dolduysa çalma sürmez; sonraki bir kesinti de kendiliğinden başlatmaz.
        if Self.sleepExpired(sleepTimer) {
            sleepTimer = nil
            playIntent = false
            return
        }
        play()
    }

    /// Kesit oturumunda yazılmaz: kesitin konumu bölümün kaldığı yer değildir. "Dinlendi" bölüm başta beklerken de
    /// yazılmaz: elle işaretlenmiş bölümün sakladığı konum, bölüm çalınmadan sıfırlanmasın.
    private func saveProgress() {
        guard let episode, clipState == nil, !(episode.isFinished && currentTime == 0) else { return }
        episode.lastPosition = currentTime
        lastSavedPosition = currentTime
        try? context?.save()
    }

    private func teardown() {
        flushListening()
        listenTickAt = nil
        statusObservation?.invalidate()
        statusObservation = nil
        fadeTask?.cancel()
        fadeTask = nil
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player = nil
        isPlaying = false
        playIntent = false
        resumeAfterInterruption = false
        currentTime = 0
        currentTurnIndex = nil
        currentChapterIndex = 0
        reachedEnd = false
        loop = nil
        loopStart = nil
        if interludeActive {
            interludeActive = false
            interludeRemoteHandler = nil
        }
        pausesTask?.cancel()
        pausesTask = nil
        pauses = []
        needsPlayedStamp = false
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
        try? session.setActive(true)
    }

    // MARK: - Now Playing (#17)

    /// "Konu 3/8" (1 tabanlı); tek konulu bölümde nil.
    nonisolated static func chapterLabel(index: Int, count: Int) -> String? {
        count > 1 ? "Konu \(min(index + 1, count))/\(count)" : nil
    }

    private func updateNowPlaying() {
        guard remoteOwner == nil else { return }
        if let audioItem {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [
                MPMediaItemPropertyTitle: audioItem.title,
                MPMediaItemPropertyArtist: "Ders Podcast",
                MPMediaItemPropertyPlaybackDuration: duration,
                MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
                MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0,
                MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
                MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            ]
            return
        }
        guard let episode else { return }
        let chapterCount = timeline?.chapters.count ?? 0
        let chapterTitle = timeline?.chapters[safe: currentChapterIndex]?.title
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: interludeActive ? "Ara soru" : (chapterTitle ?? episode.title),
            MPMediaItemPropertyAlbumTitle: episode.title,
            MPMediaItemPropertyArtist: Self.chapterLabel(index: currentChapterIndex, count: chapterCount).map { "\($0) · Ders Podcast" } ?? "Ders Podcast",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if chapterCount > 1 {
            info[MPNowPlayingInfoPropertyChapterNumber] = currentChapterIndex
            info[MPNowPlayingInfoPropertyChapterCount] = chapterCount
        }
        if let artwork = artwork(for: episode) {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Bölüm kapağı bölüm başına bir kez çizilir (kapak yoksa başlıktan türetilen desen).
    private func artwork(for episode: Episode) -> MPMediaItemArtwork? {
        let key = "\(episode.id.uuidString)#\(episode.visuals?.cover.title ?? "")"
        if let artworkCache, artworkCache.id == key { return artworkCache.artwork }
        let renderer = ImageRenderer(content: EpisodeArtwork(title: episode.title, size: 600, cover: episode.visuals?.cover)
            .environment(\.colorScheme, .dark))
        renderer.scale = 1
        guard let image = renderer.uiImage ?? UIImage(named: "Artwork") else { return nil }
        let artwork = Self.makeArtwork(image)
        artworkCache = (key, artwork)
        return artwork
    }

    /// MediaPlayer görsel isteğini arka plan kuyruğundan çağırır; closure MainActor'e bağlanmamalı.
    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        let handler: @Sendable (CGSize) -> UIImage = { _ in image }
        return MPMediaItemArtwork(boundsSize: image.size, requestHandler: handler)
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        Self.bind(center.playCommand) { [weak self] _ in self?.route(.play) }
        Self.bind(center.pauseCommand) { [weak self] _ in self?.route(.pause) }
        Self.bind(center.togglePlayPauseCommand) { [weak self] _ in self?.route(.toggle) }
        center.skipForwardCommand.preferredIntervals = [15]
        Self.bind(center.skipForwardCommand) { [weak self] _ in self?.route(.skip(15)) }
        center.skipBackwardCommand.preferredIntervals = [15]
        Self.bind(center.skipBackwardCommand) { [weak self] _ in self?.route(.skip(-15)) }
        Self.bind(center.changePlaybackPositionCommand) { [weak self] position in
            if let position { self?.route(.seek(position)) }
        }
        // ±15 düğmeleri açıkken iOS kilit ekranında parça düğmelerini göstermez; kulaklık ve Siri bunları kullanır.
        Self.bind(center.nextTrackCommand) { [weak self] _ in self?.route(.nextChapter) }
        Self.bind(center.previousTrackCommand) { [weak self] _ in self?.route(.previousChapter) }
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
    }

    /// Komutu devralana ya da bu oynatıcıya iletir (hedefler iki kez bağlanmaz; iki ses aynı anda başlamaz).
    func route(_ command: RemoteCommand) {
        if let remoteOwner {
            remoteOwner.handleRemote(command)
            return
        }
        if interludeActive, let handler = interludeRemoteHandler, handler(command) { return }
        switch command {
        case .play: play()
        case .pause: pause()
        case .toggle: toggle()
        case .skip(let seconds): skip(seconds)
        case .seek(let time): seek(to: time)
        case .nextChapter: nextChapter()
        case .previousChapter: previousChapter()
        }
    }

    /// Komut hangi kuyruktan gelirse gelsin işi ana aktöre aktarır (Swift 6 çalışma zamanı izolasyon denetimi).
    nonisolated private static func bind(_ command: MPRemoteCommand,
                                         _ action: @escaping @MainActor @Sendable (Double?) -> Void) {
        let handler: @Sendable (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus = { event in
            let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime
            Task { @MainActor in action(position) }
            return .success
        }
        command.addTarget(handler: handler)
    }
}

/// Açık kesit oturumunda kullanıcı gezinmesi: hedef oturumu bitirir mi.
nonisolated enum ClipSeek {
    /// Geri yönde pay: kesit başında tek "15 sn geri" oturumu bozmaz (kesit yine sonunda durur, eski yere döner).
    static let backSlack: Double = 15

    /// Kesitin gerisine (payın ötesine) gitmek oturumu bitirir. Kesit sonunu aşmak yalnız sırada kesit yokken
    /// bitirir; sırada kesit varken eskisi gibi "bu kesit bitti" sayılır (ilk tikte soru ve sonraki kesit gelir).
    static func leaves(_ time: Double, clipStart: Double, clipEnd: Double, hasNext: Bool) -> Bool {
        time < clipStart - backSlack || (time >= clipEnd && !hasNext)
    }
}

/// Otomatik atlamalar: Rahat modda düşünme payı (#36), "Sessizliği atla" (#22).
nonisolated enum ListeningSkip {
    /// Payın sonundan bu kadar önce atlanmaz (sonraki turun başı kesilmesin).
    static let tail = 0.15

    /// `time` bir düşünme payının içindeyse payın sonu; değilse nil.
    static func thinkTarget(at time: Double, pauses: [ThinkPause]) -> Double? {
        guard time.isFinite else { return nil }
        guard let pause = pauses.first(where: { time >= $0.start - 0.05 && time < $0.end - tail }) else { return nil }
        return pause.end
    }

    /// `skipThink` false iken (Aktif/Sınav) düşünme payı fiilen çalınır: payla çakışan sessizlikler
    /// "Sessizliği atla" açık olsa da atlanmaz (geri sayım ve cevabın gizlenmesi #23 pay boyunca sürer).
    static func target(at time: Double, thinkPauses: [ThinkPause], skipThink: Bool, silences: [FollowAlong.Pause]) -> Double? {
        if skipThink, let target = thinkTarget(at: time, pauses: thinkPauses) { return target }
        guard !silences.isEmpty else { return nil }
        if skipThink || thinkPauses.isEmpty { return SilenceSkip.target(at: time, pauses: silences) }
        // Sıra korunur (SilenceSkip başlangıca göre sıralı liste bekler).
        let free = silences.filter { s in !thinkPauses.contains { $0.start < s.end && s.start < $0.end } }
        return SilenceSkip.target(at: time, pauses: free)
    }
}

/// #23: düşünme payı geri sayımı ve cevabın gizlenmesi (transkript).
nonisolated enum ThinkReveal {
    /// `time` bir payın içindeyse kalan saniye (yukarı yuvarlanmış).
    static func countdown(at time: Double, pauses: [ThinkPause]) -> (turnID: Int, seconds: Int)? {
        guard let pause = pauses.first(where: { time >= $0.start && time < $0.end }) else { return nil }
        return (pause.turnID, max(1, Int((pause.end - time).rounded(.up))))
    }

    /// Soru turundan sonraki tur (cevap) pay bitene dek gizli: soru başlamış, pay bitmemiş.
    static func hiddenTurns(at time: Double, pauses: [ThinkPause], turns: [TimedTurn]) -> Set<Int> {
        var hidden = Set<Int>()
        for pause in pauses {
            guard let question = turns.first(where: { $0.id == pause.turnID }) else { continue }
            if time >= question.start, time < pause.end { hidden.insert(pause.turnID + 1) }
        }
        return hidden
    }
}
