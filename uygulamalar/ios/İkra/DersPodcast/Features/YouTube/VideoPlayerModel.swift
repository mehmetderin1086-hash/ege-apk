import AVFoundation
import AVKit
import MediaPlayer
import Observation
import SwiftUI
import UIKit
import WebKit

/// Ders oynatıcısının arka ucu.
nonisolated enum PlayerBackend: Equatable, Sendable {
    /// Gömülü YouTube oynatıcısı (WKWebView).
    case web
    /// İndirilmiş ses (AVPlayer); çevrimdışı ve kilit ekranında da çalışır.
    case audio
    /// "Sesi uygulamada dinle" kartı: gömme yasak ya da web oynatıcı açılamadı, ses henüz indirilmedi.
    case offerAudio

    /// Gömülebilir ve web oynatıcı sorunsuzsa video; değilse indirilmiş ses, o da yoksa ses önerisi.
    /// `preferAudio`: kullanıcı bu derste sesle dinlemeyi seçmiş; ses dosyası yerindeyse web oynatıcı hiç denenmez.
    static func choose(embeddable: Bool, webFailed: Bool, hasAudioFile: Bool, preferAudio: Bool = false) -> PlayerBackend {
        if preferAudio && hasAudioFile { return .audio }
        guard !embeddable || webFailed else { return .web }
        return hasAudioFile ? .audio : .offerAudio
    }
}

/// Ders oynatıcısı: gömülü YouTube (JS her 0,5 sn'de konumu bildirir) ya da indirilmiş ses (AVPlayer).
/// İki arka uç aynı API'yi sunar (currentTime, isPlaying, duration, rate, seek, play, pause, skip); sekmeler arka uçtan habersizdir.
@Observable
final class VideoPlayerModel: RemoteCommandOwner {
    enum Status: Equatable {
        case loading
        case ready
        case failed(String)
    }

    let videoID: String
    /// Gömülü oynatmaya izin var mı (ders kaydından).
    let embeddable: Bool
    private(set) var backend: PlayerBackend
    private(set) var currentTime: Double
    private(set) var duration: Double
    private(set) var isPlaying = false {
        didSet { if oldValue && !isPlaying { endWatchSegment() } }
    }
    /// Video bu oturumda en az bir kez oynatıldı mı (öncesinde oynatıcı konumu 0 bildirir; kayıtlı konum ezilmesin).
    private(set) var hasStarted = false
    /// Geçerli yüklemede oynatma başladı mı; yeniden yüklenen oynatıcının ilk "0" bildirimi konumu ezmesin.
    @ObservationIgnored private var playingSinceLoad = false
    /// Etkin arka ucun durumu (ses önerisi kartında anlamı yok).
    private(set) var status: Status = .loading
    /// Web oynatıcının son hatası (ses önerisi kartında gösterilir); nil = hata yok.
    private(set) var webError: String?
    /// Oynatma hızı (0,25–2). Atanınca etkin arka uca iletilir.
    var rate: Double = 1 {
        didSet { if oldValue != rate { applyRate(); onRateChange?(rate) } }
    }
    /// Ses arka ucu yerel video dosyasını mı oynatıyor (indirilmiş video: görüntü + resim içinde resim).
    private(set) var isVideoFile = false
    /// Yerel video kipinde görüntüyü gösteren AVPlayer (görünüm bunu bağlar).
    private(set) var videoPlayer: AVPlayer?
    /// A–B döngü: konum bitişe gelince başa sarar.
    private(set) var loop: ABLoop?
    /// Ses kipinde ≥ 0,6 sn'lik sessizlikleri atla.
    var skipSilence: Bool = UserDefaults.standard.bool(forKey: VideoPlayerModel.skipSilenceKey) {
        didSet {
            UserDefaults.standard.set(skipSilence, forKey: Self.skipSilenceKey)
            if skipSilence { loadPauses() }
        }
    }
    /// Uyku zamanlayıcısı; nil = kapalı.
    private(set) var sleep: LessonSleep?

    /// Kilit ekranı (Now Playing) bilgileri.
    @ObservationIgnored var nowPlayingTitle = ""
    @ObservationIgnored var nowPlayingArtist = ""
    /// Ses kipinde konum kaydı: duraklatınca, bitince ve oynarken ~15 sn'de bir çağrılır.
    @ObservationIgnored var onCheckpoint: ((Double) -> Void)?
    /// İzleme süresi parçası (≥ 10 sn): başlangıç ve saniye. Kayıt ders ekranında yapılır.
    @ObservationIgnored var onWatched: ((Date, Double) -> Void)?
    /// Geri sarma (10 sn geri, geri sürükleme): zorlanılan an.
    @ObservationIgnored var onRewind: ((Double) -> Void)?
    /// Hız değişti (ders başına hız kaydı için).
    @ObservationIgnored var onRateChange: ((Double) -> Void)?
    /// Bölüm başlangıçları (kilit ekranı sonraki/önceki bölüm ve uyku zamanlayıcısı için).
    @ObservationIgnored var chapterStarts: [Double] = []

    @ObservationIgnored private var startAt: Double
    @ObservationIgnored private(set) var webView: WKWebView?
    @ObservationIgnored private var delegate: PlayerWebDelegate?
    @ObservationIgnored private var timeout: Task<Void, Never>?
    /// Oynatıcı hazır olmadan istenen konum (hazır olunca uygulanır).
    @ObservationIgnored private var pendingSeek: Double?
    @ObservationIgnored private var pendingPlay = false
    /// Konum bildiriminin seek'ten hemen sonra eski değeri geri yazmaması için.
    @ObservationIgnored private var seekGuardUntil = Date.distantPast

    @ObservationIgnored private var audioURL: URL?
    @ObservationIgnored private var videoFileURL: URL?
    /// AVPlayer'ın çaldığı dosya: yerel video kipinde video, değilse ses.
    private var mediaURL: URL? { isVideoFile ? videoFileURL : audioURL }
    @ObservationIgnored private var pauses: [FollowAlong.Pause] = []
    @ObservationIgnored private var pausesFor: URL?
    /// Resim içinde resim açık (yerleşik video denetleyicisi bildirir). Ders ekranı kapansa da oynatma sürer.
    @ObservationIgnored private(set) var isPictureInPictureActive = false
    @ObservationIgnored private var pipController: AVPlayerViewController?
    @ObservationIgnored private var suspendedInPictureInPicture = false
    @ObservationIgnored private var watch = WatchAccumulator()
    @ObservationIgnored private var audioPlayer: AVPlayer?
    @ObservationIgnored private var audioObservers: AudioObservers?
    @ObservationIgnored private var lastCheckpoint: Double = 0

    static let baseURL = URL(string: "https://www.youtube-nocookie.com")!
    static let rates: [Double] = [0.75, 1, 1.25, 1.5, 1.75, 2]
    static let skipSilenceKey = "lesson.skipSilence"

    /// Hafif: web görünümü ve AVPlayer burada kurulmaz (SwiftUI init'i sık çağırır); ses `activate` ile hazırlanır.
    init(videoID: String, startAt: Double = 0, duration: Double = 0, embeddable: Bool = true, audioURL: URL? = nil,
         videoURL: URL? = nil, preferAudio: Bool = false) {
        self.videoID = videoID
        self.embeddable = embeddable
        let start = duration > 0 && startAt > duration - 5 ? 0 : max(0, startAt)
        self.startAt = start
        currentTime = start
        self.duration = duration
        let hasAudio = audioURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        self.audioURL = hasAudio ? audioURL : nil
        let hasVideo = videoURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        videoFileURL = hasVideo ? videoURL : nil
        // İndirilmiş video varsa her zaman o (çevrimdışı, resim içinde resim); yoksa ses/web seçimi.
        isVideoFile = hasVideo
        backend = hasVideo ? .audio : PlayerBackend.choose(embeddable: embeddable, webFailed: false, hasAudioFile: hasAudio,
                                                           preferAudio: preferAudio)
    }

    // MARK: - Arka uç geçişleri

    /// Ekran görününce: ses kipindeyse oynatıcıyı hazırlar.
    func activate() {
        if backend == .audio { prepareAudio() }
    }

    /// Ekrandan çıkınca: duraklatır; ses oynatıcısı ve gözlemcileri sökülür, kilit ekranı komutları ana oynatıcıya döner.
    func suspend() {
        if isPictureInPictureActive {
            // Resim içinde resim sürüyor: oynatma ve kilit ekranı kalır, yalnızca konum kaydedilir; PiP kapanınca sökülür.
            suspendedInPictureInPicture = true
            if hasStarted { onCheckpoint?(currentTime) }
            PictureInPictureKeeper.hold(self)
            return
        }
        pause()
        endWatchSegment()
        teardownAudio()
    }

    func pictureInPictureStarted(_ controller: AVPlayerViewController) {
        isPictureInPictureActive = true
        pipController = controller
    }

    /// PiP kapandı (kullanıcı kapattı, uygulamaya döndü ya da açılamadı). Ders ekranı çoktan kapanmışsa oynatıcı sökülür.
    func pictureInPictureStopped() {
        isPictureInPictureActive = false
        pipController = nil
        PictureInPictureKeeper.release(self)
        guard suspendedInPictureInPicture else { return }
        suspendedInPictureInPicture = false
        pause()
        endWatchSegment()
        teardownAudio()
    }

    /// Sesle sürdürür (indirme bitti ya da dosya zaten var). Konum korunur.
    func useAudio(file url: URL, autoplay: Bool) {
        audioURL = url
        if backend == .audio && (audioPlayer != nil || isVideoFile) {
            if audioPlayer == nil { prepareAudio() }
            if autoplay { play() }
            return
        }
        if backend == .web { pause() }
        dropWebView()
        isVideoFile = false
        backend = .audio
        status = .loading
        prepareAudio()
        if autoplay { play() }
    }

    /// Ses önerisi kartına geçer (kullanıcı seçti); ses indirilmişse doğrudan ses kipi.
    func showAudioOffer() {
        if let audioURL, FileManager.default.fileExists(atPath: audioURL.path) {
            isVideoFile = false
            useAudio(file: audioURL, autoplay: false)
            return
        }
        pause()
        dropWebView()
        teardownAudio()
        isVideoFile = false
        backend = .offerAudio
    }

    /// Videoya döner ya da web oynatıcıyı yeniden dener (kaldığı yerden).
    func useWeb() {
        pause()
        teardownAudio()
        isVideoFile = false
        webError = nil
        backend = .web
        startAt = currentTime
        pendingSeek = nil
        if webView != nil { load() } else { status = .loading }   // görünüm yoksa makeWebView yükler
    }

    /// İndirilen ses silindi: ses kipinden çıkılır.
    func audioRemoved() {
        audioURL = nil
        guard backend == .audio, !isVideoFile else { return }
        teardownAudio()
        if embeddable && webError == nil {
            useWeb()
        } else {
            backend = .offerAudio
        }
    }

    /// İndirilmiş videoyu görüntüyle oynatır (resim içinde resim; kilit ekranı ve konum aynen korunur).
    func useVideo(file url: URL, autoplay: Bool) {
        videoFileURL = url
        if backend == .audio && isVideoFile && audioPlayer != nil {
            if autoplay { play() }
            return
        }
        if backend == .web { pause() }
        dropWebView()
        teardownAudio()
        isVideoFile = true
        backend = .audio
        status = .loading
        prepareAudio()
        if autoplay { play() }
    }

    /// İndirilen video silindi: ses varsa sesle, yoksa web oynatıcıyla (ya da ses önerisiyle) sürer.
    func videoRemoved() {
        videoFileURL = nil
        guard isVideoFile else { return }
        let wasPlaying = isPlaying
        pause()
        teardownAudio()
        isVideoFile = false
        if let audioURL, FileManager.default.fileExists(atPath: audioURL.path) {
            backend = .audio
            status = .loading
            prepareAudio()
        } else if embeddable && webError == nil {
            useWeb()
        } else {
            backend = .offerAudio
        }
        if wasPlaying { play() }
    }

    // MARK: - Web görünümü

    /// Tek web görünümü; SwiftUI görünümü yeniden oluşsa da oynatıcı yeniden yüklenmez.
    func makeWebView() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        let controller = WKUserContentController()
        // Zayıf referanslı vekil: içerik denetleyicisi işleyiciyi güçlü tutar, vekil modeli tutmaz → döngü yok.
        controller.add(WeakScriptMessageProxy(target: self), name: "player")
        config.userContentController = controller

        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        let delegate = PlayerWebDelegate(target: self)
        web.navigationDelegate = delegate
        web.uiDelegate = delegate
        self.delegate = delegate
        webView = web
        load()
        return web
    }

    private func load() {
        status = .loading
        playingSinceLoad = false
        webView?.loadHTMLString(Self.html(videoID: videoID, start: Int(startAt)), baseURL: Self.baseURL)
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.backend == .web, self.status == .loading else { return }
            self.webDidFail("Oynatıcı yüklenemedi. İnternet bağlantını kontrol et.")
        }
    }

    /// Hata sonrası yeniden dener (kaldığı yerden).
    func reload() {
        startAt = currentTime
        if webView == nil { _ = makeWebView() } else { load() }
    }

    /// Ses kipine geçerken web oynatıcısı durdurulup bırakılır (gizli görünüm ses çalmasın, konum bildirmesin).
    private func dropWebView() {
        timeout?.cancel()
        pendingPlay = false
        guard let webView else { return }
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "player")
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        self.webView = nil
        delegate = nil
        playingSinceLoad = false
        if backend == .web { isPlaying = false }
    }

    /// Gömme yasağı ya da yükleme hatası: ses indirilmişse sesle sürer, yoksa ses önerisi kartı gösterilir.
    private func webDidFail(_ message: String) {
        timeout?.cancel()
        isPlaying = false
        pendingPlay = false
        webError = message
        status = .failed(message)
        let hasAudio = audioURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        switch PlayerBackend.choose(embeddable: embeddable, webFailed: true, hasAudioFile: hasAudio) {
        case .audio:
            // Vekil/JS geri çağrısının içindeyiz: web görünümü bir sonraki turda bırakılır.
            backend = .offerAudio
            Task { [weak self] in
                guard let self, self.backend == .offerAudio, let url = self.audioURL else { return }
                self.useAudio(file: url, autoplay: false)
            }
        case .offerAudio, .web:
            backend = .offerAudio
        }
    }

    // MARK: - Denetim

    func seek(to seconds: Double) {
        let target = max(0, duration > 0 ? min(seconds, duration) : seconds)
        currentTime = target
        seekGuardUntil = .now.addingTimeInterval(1.2)
        refreshSleep(at: target)
        // Duraklatılmışken döngünün çok dışına atlandı: döngü kapanır (çip geride kalmasın).
        if let loop, loop.action(at: target) == .cancel { self.loop = nil }
        switch backend {
        case .audio:
            if let audioPlayer {
                audioPlayer.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            }
            updateNowPlaying()
        case .web:
            if status == .ready { run("seek(\(Self.number(target)))") } else { pendingSeek = target; startAt = target }
        case .offerAudio:
            startAt = target
        }
    }

    func play() {
        clearExpiredSleep()
        switch backend {
        case .web: if status == .ready { run("play()") } else { pendingPlay = true }
        case .audio: playAudio()
        case .offerAudio: break
        }
    }

    func pause() {
        pendingPlay = false
        switch backend {
        case .web:
            run("pause()")
        case .audio:
            guard let audioPlayer else { isPlaying = false; return }
            audioPlayer.pause()
            if isPlaying {
                isPlaying = false
                checkpoint()
            }
            updateNowPlaying()
        case .offerAudio:
            isPlaying = false
        }
    }

    func togglePlay() { isPlaying ? pause() : play() }

    /// Dahili atlama (döngü başa sarma, sessizlik atlama): kısa konum koruması; geri sarma sayılmaz.
    private func jump(to seconds: Double) {
        let target = max(0, duration > 0 ? min(seconds, duration) : seconds)
        seek(to: target)
        seekGuardUntil = .now.addingTimeInterval(backend == .audio ? 0.35 : 0.8)
    }

    func skip(_ delta: Double) {
        let from = currentTime
        seek(to: from + delta)
        recordRewind(from: from)
    }

    /// İlerleme çubuğundan bırakılan konum: geriye sürüklenmişse geri sarma kaydedilir.
    func scrub(to seconds: Double) {
        let from = currentTime
        seek(to: seconds)
        recordRewind(from: from)
    }

    private func recordRewind(from: Double) {
        if let moment = RewindHeat.moment(from: from, to: currentTime) { onRewind?(moment) }
    }

    // MARK: - Döngü, bölüm, uyku, sessizlik

    /// A–B döngüsünü kurar ve başa götürür. Bitiş, süre biliniyorsa videonun sonundan 0,1 sn önceye kırpılır.
    /// Döngü geçersizse (1 sn'den kısa) kapatır ve false döner; çağıran kullanıcıya bildirir.
    @discardableResult
    func setLoop(start: Double, end: Double, play startPlaying: Bool = true) -> Bool {
        let limit = duration > 0 ? duration - 0.1 : end
        guard let new = ABLoop(start: start, end: min(end, limit)) else {
            loop = nil
            return false
        }
        loop = new
        seek(to: new.start)
        if startPlaying { play() }
        return true
    }

    func clearLoop() { loop = nil }

    func nextChapter() {
        if let target = ChapterNav.target(from: currentTime, starts: chapterStarts, forward: true) { seek(to: target) }
    }

    func previousChapter() {
        if let target = ChapterNav.target(from: currentTime, starts: chapterStarts, forward: false) { seek(to: target) }
    }

    func setSleep(minutes: Int) { sleep = .until(.now.addingTimeInterval(Double(minutes) * 60)) }

    /// Çalan bölüm bitince durdurur (bölüm bilgisi yoksa video sonunda).
    func setSleepEndOfChapter() {
        guard let end = ChapterNav.chapterEnd(at: currentTime, starts: chapterStarts, duration: duration) else { return }
        sleep = .endOfChapter(end)
    }

    func cancelSleep() { sleep = nil }

    /// Süresi geçmiş zamanlayıcı (duraklatılmışken dolmuş) devam edince hemen kesmesin.
    private func clearExpiredSleep() {
        if case .until(let date) = sleep, date <= .now { sleep = nil }
    }

    /// Kullanıcı başka bir yere gidince "bölüm sonunda dur" yeni bölümün bitişine taşınır (bölüm yoksa kapanır).
    private func refreshSleep(at time: Double) {
        guard case .endOfChapter = sleep else { return }
        sleep = ChapterNav.chapterEnd(at: time, starts: chapterStarts, duration: duration).map { .endOfChapter($0) }
    }

    /// Kalan uyku süresi (sn); bölüm sonu ya da kapalıysa nil.
    var sleepRemaining: TimeInterval? {
        if case .until(let date) = sleep { return max(0, date.timeIntervalSinceNow) }
        return nil
    }

    /// Sessizlik atlama kullanılabilir mi: AVPlayer kipi (ses ya da indirilmiş video) ve ölçülecek dosya var.
    var canSkipSilence: Bool { backend == .audio && mediaURL != nil }

    /// Çalan dosyanın (ses ya da yerel video) sessizliklerini ölçer/okur (önbellekli, ana iş parçacığı dışında).
    private func loadPauses() {
        guard let url = mediaURL, pausesFor != url else { return }
        pausesFor = url
        Task { [weak self] in
            let found = await PauseMeasurement.load(url)
            guard let self, self.pausesFor == url else { return }
            self.pauses = found
        }
    }

    /// Oynarken her konum bildiriminde (0,1–0,2 sn): izleme süresi, döngü, sessizlik atlama, uyku.
    private func playbackTicked() {
        guard isPlaying else { return }
        if let chunk = watch.tick(now: .now) { onWatched?(chunk.start, chunk.seconds) }
        if let loop {
            switch loop.action(at: currentTime) {
            case .wrap(let start): jump(to: start); return
            case .cancel: self.loop = nil
            case .none: break
            }
        }
        if skipSilence, backend == .audio, let target = SilenceSkip.target(at: currentTime, pauses: pauses) {
            jump(to: target)
            return
        }
        if let sleep, sleep.isDue(time: currentTime, now: .now) {
            self.sleep = nil
            pause()
        }
    }

    private func endWatchSegment() {
        if let chunk = watch.stop(now: .now) { onWatched?(chunk.start, chunk.seconds) }
    }

    private func applyRate() {
        switch backend {
        case .web: run("setRate(\(Self.number(rate)))")
        case .audio:
            audioPlayer?.defaultRate = Float(rate)   // yerleşik denetimlerle oynatınca da bu hızda başlasın
            if isPlaying { audioPlayer?.rate = Float(rate) }
            updateNowPlaying()
        case .offerAudio: break
        }
    }

    private func run(_ script: String) {
        guard backend == .web, let webView, status == .ready else { return }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private static func number(_ value: Double) -> String {
        value.isFinite ? String(format: "%.3f", value) : "0"
    }

    // MARK: - Ses arka ucu

    private func prepareAudio() {
        guard backend == .audio, audioPlayer == nil else { return }
        guard let mediaURL, FileManager.default.fileExists(atPath: mediaURL.path) else {
            status = .failed(isVideoFile ? "Video dosyası bulunamadı. Yeniden indirebilirsin." : "Ses dosyası bulunamadı. Yeniden indirebilirsin.")
            return
        }
        status = .loading
        let item = AVPlayerItem(url: mediaURL)
        item.audioTimePitchAlgorithm = .timeDomain
        let player = AVPlayer(playerItem: item)
        player.defaultRate = Float(rate)
        audioPlayer = player
        if isVideoFile { videoPlayer = player }
        if skipSilence { loadPauses() }
        audioObservers = AudioObservers(
            player: player, item: item,
            onStatus: { [weak self] in self?.audioItemChanged() },
            onPlayback: { [weak self] in self?.audioPlaybackChanged() },
            onTime: { [weak self] time in self?.audioTick(time) },
            onEnd: { [weak self] in self?.audioFinished() })
        if currentTime > 0 {
            player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        lastCheckpoint = currentTime
    }

    private func playAudio() {
        if audioPlayer == nil { prepareAudio() }
        guard let audioPlayer, audioPlayer.currentItem?.status != .failed else { return }
        // Ders sesi başlayınca podcast oynatıcısı sussun (iki ses üst üste binmesin).
        if let podcast = AppState.current?.player, podcast.isPlaying { podcast.pause() }
        Self.activateSession()
        if duration > 0, currentTime >= duration - 0.5 { seek(to: 0) }   // bitmişse baştan
        audioPlayer.playImmediately(atRate: Float(rate))
        isPlaying = true
        hasStarted = true
        AppState.current?.player.lendRemoteCommands(to: self)
        updateNowPlaying()
    }

    /// Oynatma yerel video denetimlerinden (yerleşik oynat düğmesi, resim içinde resim) başlatıldı.
    private func startedExternally() {
        clearExpiredSleep()
        hasStarted = true
        if let podcast = AppState.current?.player, podcast.isPlaying { podcast.pause() }
        Self.activateSession()
        AppState.current?.player.lendRemoteCommands(to: self)
    }

    private func audioItemChanged() {
        guard backend == .audio, let item = audioPlayer?.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            let seconds = item.duration.seconds
            if seconds.isFinite, seconds > 0, abs(seconds - duration) > 0.5 { duration = seconds }
            if status != .ready {
                status = .ready
                // Hazır olmadan istenen konum yok sayılmış olabilir: kaldığı yere bir kez daha git.
                if let audioPlayer, abs(audioPlayer.currentTime().seconds - currentTime) > 1 {
                    audioPlayer.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
            updateNowPlaying()
        case .failed:
            isPlaying = false
            status = .failed("Ses oynatılamadı (\(item.error?.localizedDescription ?? "dosya bozuk olabilir")). Sesi yeniden indirebilirsin.")
        default:
            break
        }
    }

    /// Kesinti, kulaklık çıkarma ya da sistemin durdurması: arayüz "çalıyor" göstermesin. Canlı değer okunur (eski bildirim ezmesin).
    private func audioPlaybackChanged() {
        guard backend == .audio, let audioPlayer else { return }
        // Yerleşik video denetimlerinden (hız menüsü) gelen hız değişimi modele yansır.
        if audioPlayer.rate > 0, abs(Double(audioPlayer.rate) - rate) > 0.01 { rate = Double(audioPlayer.rate) }
        let playing = audioPlayer.timeControlStatus != .paused
        guard playing != isPlaying else { return }
        isPlaying = playing
        if playing { startedExternally() } else { checkpoint() }
        updateNowPlaying()
    }

    private func audioTick(_ time: Double) {
        guard backend == .audio, time.isFinite, Date.now >= seekGuardUntil else { return }
        if abs(time - currentTime) > 0.05 { currentTime = time }
        if isPlaying, abs(currentTime - lastCheckpoint) >= 15 { checkpoint() }
        playbackTicked()
    }

    private func audioFinished() {
        guard backend == .audio else { return }
        isPlaying = false
        if duration > 0 { currentTime = duration }
        checkpoint()
        updateNowPlaying()
        // Döngü medyanın sonuna dayanıyorsa bitiş döngüyü başa sarar (çip takılı kalmasın).
        if let loop {
            seek(to: loop.start)
            playAudio()
        }
    }

    private func checkpoint() {
        lastCheckpoint = currentTime
        if hasStarted { onCheckpoint?(currentTime) }
    }

    private func teardownAudio() {
        if let audioPlayer {
            audioPlayer.pause()
            audioObservers?.invalidate()
            audioObservers = nil
            self.audioPlayer = nil
            videoPlayer = nil
            if backend == .audio {
                isPlaying = false
                status = .loading
            }
        }
        AppState.current?.player.reclaimRemoteCommands(from: self)
    }

    private static func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
        try? session.setActive(true)
    }

    // MARK: - Kilit ekranı

    func handleRemote(_ command: RemoteCommand) {
        guard backend == .audio else { return }
        switch command {
        case .play: play()
        case .pause: pause()
        case .toggle: togglePlay()
        case .skip(let seconds): skip(seconds)
        case .seek(let time): scrub(to: time)
        case .nextChapter: nextChapter()
        case .previousChapter: previousChapter()
        }
    }

    /// Yalnızca komutlar bu oynatıcıdayken yazar (ana oynatıcının bölüm bilgisini ezmez).
    private func updateNowPlaying() {
        guard backend == .audio, let main = AppState.current?.player, main.ownsRemoteCommands(self) else { return }
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlayingTitle.isEmpty ? "YouTube dersi" : nowPlayingTitle,
            MPMediaItemPropertyArtist: nowPlayingArtist,
            MPMediaItemPropertyAlbumTitle: "YouTube dersi",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - JS'ten gelen iletiler

    fileprivate func receive(_ body: Any) {
        // Ses kipine geçildiyse gizli web görünümünün bildirimleri konumu ezmesin.
        guard backend == .web, let message = body as? [String: Any], let type = message["type"] as? String else { return }
        switch type {
        case "ready":
            timeout?.cancel()
            status = .ready
            webError = nil
            if let d = message["d"] as? Double, d > 0 { duration = d }
            if rate != 1 { run("setRate(\(Self.number(rate)))") }
            if let seek = pendingSeek {
                pendingSeek = nil
                run("seek(\(Self.number(seek)))")
            }
            if pendingPlay {
                pendingPlay = false
                run("play()")
            }
        case "time":
            if let d = message["d"] as? Double, d > 0, abs(d - duration) > 0.5 { duration = d }
            if playingSinceLoad, let t = message["t"] as? Double, t.isFinite, Date.now >= seekGuardUntil, abs(t - currentTime) > 0.05 {
                currentTime = t
            }
            if let s = message["s"] as? Int { apply(state: s) }
            playbackTicked()
        case "state":
            if let s = message["s"] as? Int { apply(state: s) }
        case "rate":
            if let r = message["r"] as? Double, r > 0, r != rate { rate = r }
        case "error":
            webDidFail(Self.errorText(message["code"] as? Int ?? -1))
        default:
            break
        }
    }

    /// YT.PlayerState: -1 başlamadı, 0 bitti, 1 oynuyor, 2 durdu, 3 arabellek, 5 hazır.
    private func apply(state: Int) {
        if state == 1 || state == 3 {
            hasStarted = true
            playingSinceLoad = true
        }
        if state == 0, let loop {   // video bitti: döngü başa sarar
            seek(to: loop.start)
            run("play()")
        }
        let playing = state == 1 || (state == 3 && isPlaying)
        guard playing != isPlaying else { return }
        isPlaying = playing
        // Video başlayınca podcast oynatıcısı sussun (iki ses üst üste binmesin).
        if playing, let podcast = AppState.current?.player, podcast.isPlaying { podcast.pause() }
    }

    fileprivate func navigationFailed(_ error: Error) {
        guard backend == .web, status == .loading else { return }
        webDidFail("Oynatıcı yüklenemedi: \(error.localizedDescription)")
    }

    fileprivate func webContentTerminated() {
        guard backend == .web else { return }
        isPlaying = false
        reload()
    }

    static func errorText(_ code: Int) -> String {
        switch code {
        case 2: "Video bağlantısı geçersiz."
        case 5: "Video bu cihazda oynatılamıyor."
        case 100: "Video bulunamadı ya da kaldırılmış."
        case 101, 150: "Video sahibi gömülü oynatmaya izin vermiyor."
        case 152, 153: "YouTube gömülü oynatıcıyı açmadı."
        default: "Oynatıcı yüklenemedi."
        }
    }

    // MARK: - HTML

    static func html(videoID: String, start: Int) -> String {
        let id = YouTubeLink.isValidID(videoID) ? videoID : ""
        let origin = baseURL.absoluteString
        let src = "https://www.youtube-nocookie.com/embed/\(id)?enablejsapi=1&playsinline=1&rel=0&modestbranding=1&hl=tr"
            + "&start=\(max(0, start))&origin=\(origin)&widget_referrer=\(origin)"
        return """
        <!DOCTYPE html>
        <html><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>
        html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: #000; overflow: hidden; }
        iframe { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
        </style>
        </head><body>
        <iframe id="player" src="\(src)" allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
          allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe>
        <script>
        var post = function (m) { try { window.webkit.messageHandlers.player.postMessage(m); } catch (e) {} };
        var player = null, ready = false;
        function tick() {
          if (!ready || !player || !player.getCurrentTime) return;
          post({ type: 'time', t: player.getCurrentTime() || 0, d: player.getDuration() || 0, s: player.getPlayerState() });
        }
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player', {
            events: {
              onReady: function () { ready = true; post({ type: 'ready', d: player.getDuration() || 0 }); setInterval(tick, 200); },
              onStateChange: function (e) { post({ type: 'state', s: e.data }); tick(); },
              onPlaybackRateChange: function (e) { post({ type: 'rate', r: e.data }); },
              onError: function (e) { post({ type: 'error', code: e.data }); }
            }
          });
        }
        function seek(t) { if (ready) { player.seekTo(t, true); setTimeout(tick, 150); } }
        function play() { if (ready) player.playVideo(); }
        function pause() { if (ready) player.pauseVideo(); }
        function setRate(r) { if (ready) player.setPlaybackRate(r); }
        var tag = document.createElement('script');
        tag.src = 'https://www.youtube.com/iframe_api';
        tag.onerror = function () { post({ type: 'error', code: -1 }); };
        document.head.appendChild(tag);
        </script>
        </body></html>
        """
    }
}

// MARK: - Köprü sınıfları

/// İçerik denetleyicisi işleyicisini güçlü tutar; bu vekil modeli zayıf tutar (retain döngüsü yok).
final class WeakScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: VideoPlayerModel?

    init(target: VideoPlayerModel) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.receive(message.body)
    }
}

/// Oynatıcı dışına giden bağlantılar (YouTube logosu, "YouTube'da izle") Safari/YouTube uygulamasında açılır.
final class PlayerWebDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var target: VideoPlayerModel?

    init(target: VideoPlayerModel) {
        self.target = target
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame?.isMainFrame == true, navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { UIApplication.shared.open(url) }
        return nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        target?.navigationFailed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        target?.navigationFailed(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        target?.webContentTerminated()
    }
}

/// SwiftUI sarmalayıcısı: web görünümünü modelden alır (yeniden yükleme yok).
struct YouTubePlayerView: UIViewRepresentable {
    var model: VideoPlayerModel

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        attach(to: container)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        if container.subviews.first !== model.webView { attach(to: container) }
    }

    private func attach(to container: UIView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        let web = model.makeWebView()
        web.removeFromSuperview()
        web.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(web)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            web.topAnchor.constraint(equalTo: container.topAnchor),
            web.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}

// MARK: - Ses gözlemcileri

/// AVPlayer gözlemcileri (öğe durumu, oynatma durumu, zaman, bitiş). Kapanışlar ana aktöre bağlı olmayan bağlamda kurulur:
/// KVO bildirimi hangi kuyruktan gelirse gelsin çalışma zamanı izolasyon denetimi çökmesin; iş ana aktöre aktarılır.
/// Sahibi `invalidate` ile hepsini kaldırır (blok tabanlı bildirim gözlemcisi kendiliğinden kalkmaz).
final class AudioObservers {
    private let player: AVPlayer
    private var observations: [NSKeyValueObservation]
    private var timeToken: Any?
    private var endToken: NSObjectProtocol?

    init(player: AVPlayer, item: AVPlayerItem,
         onStatus: @escaping @MainActor @Sendable () -> Void,
         onPlayback: @escaping @MainActor @Sendable () -> Void,
         onTime: @escaping @MainActor @Sendable (Double) -> Void,
         onEnd: @escaping @MainActor @Sendable () -> Void) {
        self.player = player
        observations = Self.observe(player: player, item: item, onStatus: onStatus, onPlayback: onPlayback)
        timeToken = Self.addTimeObserver(player, onTime)
        endToken = Self.addEndObserver(item, onEnd)
    }

    /// Sahibi `invalidate`i çağırmadan düşse bile zaman gözlemcisi ve bildirim gözlemcisi AVPlayer'da/NotificationCenter'da kalmasın.
    isolated deinit { invalidate() }

    func invalidate() {
        observations.forEach { $0.invalidate() }
        observations = []
        if let timeToken { player.removeTimeObserver(timeToken) }
        timeToken = nil
        if let endToken { NotificationCenter.default.removeObserver(endToken) }
        endToken = nil
    }

    nonisolated private static func observe(player: AVPlayer, item: AVPlayerItem,
                                            onStatus: @escaping @MainActor @Sendable () -> Void,
                                            onPlayback: @escaping @MainActor @Sendable () -> Void) -> [NSKeyValueObservation] {
        let status = item.observe(\.status, options: [.initial, .new]) { _, _ in
            Task { @MainActor in onStatus() }
        }
        let playback = player.observe(\.timeControlStatus, options: [.new]) { _, _ in
            Task { @MainActor in onPlayback() }
        }
        let rate = player.observe(\.rate, options: [.new]) { _, _ in
            Task { @MainActor in onPlayback() }
        }
        return [status, playback, rate]
    }

    /// Ana kuyrukta 0,1 sn'de bir (kelime takibi sesin gerisinde kalmasın); kuyruk ana olduğu için ana aktörde olduğumuz kesindir.
    nonisolated private static func addTimeObserver(_ player: AVPlayer,
                                                    _ onTime: @escaping @MainActor @Sendable (Double) -> Void) -> Any {
        player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { time in
            let seconds = time.seconds
            MainActor.assumeIsolated { onTime(seconds) }
        }
    }

    nonisolated private static func addEndObserver(_ item: AVPlayerItem,
                                                   _ onEnd: @escaping @MainActor @Sendable () -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { _ in
            MainActor.assumeIsolated { onEnd() }
        }
    }
}
