import AVFoundation
import Combine
import MediaPlayer
import UIKit

enum RepeatMode: String, CaseIterable, Codable {
    case off, all, one
}

/// A single player is shared by the full-screen video view and audio controls.
@MainActor
final class PlaybackStore: ObservableObject {
    @Published private(set) var current: MediaTrack?
    /// The active collection, including the currently selected track.
    @Published private(set) var queue: [MediaTrack] = []
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var shuffleEnabled = false {
        didSet {
            guard oldValue != shuffleEnabled else { return }
            resetShuffle()
            updateRemoteCommands()
            persistSession()
        }
    }
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var playbackRate: Float = 1
    @Published private(set) var sleepDeadline: Date?
    @Published private(set) var sleepAtTrackEnd = false
    @Published private(set) var loopStart: Double?
    @Published private(set) var loopEnd: Double?
    @Published var errorMessage: String?

    let player = AVPlayer()

    private let library: LibraryStore
    private let listening: ListeningStore?
    private var subscriptions = Set<AnyCancellable>()
    private var playerObservation: NSKeyValueObservation?
    private var itemObservations: [NSKeyValueObservation] = []
    private var periodicObserver: Any?
    private var remoteTargets: [(command: MPRemoteCommand, target: Any)] = []
    private var sleepTask: Task<Void, Never>?
    private var sleepGeneration = UUID()
    private var shuffleRemaining: [UUID] = []
    private var shuffleHistory: [UUID] = []
    private var wantsPlayback = false
    private var watchdogTask: Task<Void, Never>?
    private var stallMonitor = PlaybackStallMonitor()
    private var interruptionActive = false
    private var resumeAfterInterruption = false
    private var lastUnexpectedPause: TimeInterval?
    private var countedCurrentPlay = false
    private var pendingSeek: Double?
    private var seekGeneration = UUID()
    private var isSeeking = false
    /// Activating the shared session blocks the main thread on device; do it once per
    /// activation instead of on every track change. Interruptions and resets clear it.
    private var audioSessionActive = false
    #if DEBUG
    private var diagnosticTask: Task<Void, Never>?
    #endif
    private struct Session: Codable, Equatable {
        var version = 1
        var currentID: UUID
        var queueIDs: [UUID]
        var elapsed: Double
        var rate: Float
        var repeatMode: RepeatMode
        var shuffleEnabled: Bool
        var shuffleRemaining: [UUID]
        var shuffleHistory: [UUID]
    }
    private let sessionURL: URL
    private let uptime: () -> TimeInterval
    private var lastSessionWrite: TimeInterval = 0
    private var lastSavedSession: Session?
    private var restoringSession = false
    private var canWriteSession = true

    init(library: LibraryStore, listening: ListeningStore? = nil,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.library = library
        self.listening = listening
        self.uptime = uptime
        self.sessionURL = library.directory.deletingLastPathComponent().appendingPathComponent("playback-session.json")
        player.automaticallyWaitsToMinimizeStalling = true
        observePlayer()
        observeNotifications()
        watchdogTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                self?.checkPlaybackProgress()
            }
        }
        configureRemoteCommands()
        library.$tracks.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] tracks in
            self?.synchronizeLibrary(tracks)
        }.store(in: &subscriptions)
        restoreSession()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ritim-acceptance-playback") {
            diagnosticTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                if let self, !self.isPlaying {
                    if self.current != nil { self.togglePlayPause() }
                    else if let first = self.library.tracks.first { self.play(first, in: self.library.tracks) }
                }
                while !Task.isCancelled {
                    guard let self else { return }
                    let report: [String: Any] = [
                        "uptime": ProcessInfo.processInfo.systemUptime,
                        "position": self.player.currentTime().seconds.isFinite ? self.player.currentTime().seconds : 0,
                        "status": self.player.timeControlStatus.rawValue,
                        "itemStatus": self.player.currentItem?.status.rawValue ?? -1,
                        "wantsPlayback": self.wantsPlayback,
                        "isPlaying": self.isPlaying,
                        "appState": UIApplication.shared.applicationState.rawValue,
                        "audioSessionActive": self.audioSessionActive,
                        "hasError": self.errorMessage != nil
                    ]
                    if let data = try? JSONSerialization.data(withJSONObject: report),
                       let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                        try? data.write(to: cache.appendingPathComponent("ritim-playback-diagnostic.json"), options: .atomic)
                    }
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        }
        #endif
    }

    deinit {
        #if DEBUG
        diagnosticTask?.cancel()
        #endif
        watchdogTask?.cancel()
        sleepTask?.cancel()
        playerObservation?.invalidate()
        itemObservations.forEach { $0.invalidate() }
        if let periodicObserver { player.removeTimeObserver(periodicObserver) }
        for entry in remoteTargets { entry.command.removeTarget(entry.target) }
    }

    func play(_ track: MediaTrack, in tracks: [MediaTrack]) {
        var seen = Set<UUID>()
        var collection = tracks.filter { seen.insert($0.id).inserted }
        if !collection.contains(where: { $0.id == track.id }) { collection.insert(track, at: 0) }
        queue = collection
        load(track, autoPlay: true)
        resetShuffle()
        persistSession()
    }

    func togglePlayPause() {
        if isPlaying || wantsPlayback || resumeAfterInterruption { pause() } else { resume() }
    }

    func next() { advance(automatically: false) }

    func previous() {
        guard let current else { return }
        if elapsed > 3 { seek(to: 0); return }
        if shuffleEnabled {
            while let previousID = shuffleHistory.popLast() {
                guard let previousTrack = queue.first(where: { $0.id == previousID }) else { continue }
                shuffleRemaining.removeAll { $0 == current.id || $0 == previousID }
                shuffleRemaining.insert(current.id, at: 0)
                load(previousTrack, autoPlay: true)
                return
            }
            seek(to: 0)
        } else if let index = queue.firstIndex(where: { $0.id == current.id }), index > 0 {
            load(queue[index - 1], autoPlay: true)
        } else if repeatMode == .all, let last = queue.last {
            load(last, autoPlay: true)
        } else {
            seek(to: 0)
        }
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite, seconds >= 0, player.currentItem != nil else { return }
        pendingSeek = duration > 0 ? min(seconds, duration) : seconds
        elapsed = pendingSeek ?? 0
        // Invalidate an older completion before issuing the replacement seek.
        seekGeneration = UUID()
        isSeeking = false
        updateNowPlaying()
        persistSession()
        performPendingSeek()
    }

    private func performPendingSeek() {
        guard let requested = pendingSeek, !isSeeking,
              let item = player.currentItem, item.status == .readyToPlay else { return }
        let target = duration > 0 ? min(requested, duration) : requested
        pendingSeek = target
        let generation = UUID()
        seekGeneration = generation
        isSeeking = true
        updateListeningPlayback()
        elapsed = target
        updateNowPlaying()
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak item] finished in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item,
                      self.seekGeneration == generation else { return }
                self.isSeeking = false
                self.updateListeningPlayback()
                guard finished else { return }
                self.pendingSeek = nil
                let actual = self.player.currentTime().seconds
                if actual.isFinite { self.elapsed = max(0, actual) }
                if self.wantsPlayback { self.player.playImmediately(atRate: self.playbackRate) }
                self.updateNowPlaying()
                self.persistSession()
            }
        }
    }

    func enqueue(_ track: MediaTrack) {
        guard current?.id != track.id else { return }
        queue.removeAll { $0.id == track.id }
        queue.append(track)
        if shuffleEnabled {
            shuffleRemaining.removeAll { $0 == track.id }
            shuffleRemaining.append(track.id)
        }
        if current == nil { load(track, autoPlay: false); resetShuffle() }
        updateRemoteCommands()
        persistSession()
    }

    /// An explicit next selection takes priority over the remaining shuffle bag.
    /// Moving an existing entry keeps both the queue and the active AVPlayerItem intact.
    func enqueueNext(_ track: MediaTrack) {
        guard let current else { enqueue(track); return }
        guard current.id != track.id else { return }
        queue.removeAll { $0.id == track.id }
        let index = queue.firstIndex { $0.id == current.id } ?? (queue.count - 1)
        queue.insert(track, at: index + 1)
        if shuffleEnabled {
            shuffleRemaining.removeAll { $0 == track.id }
            shuffleRemaining.insert(track.id, at: 0)
        }
        updateRemoteCommands()
        persistSession()
    }

    func removeFromQueue(at offsets: IndexSet) {
        let validOffsets = offsets.filter { queue.indices.contains($0) }
        guard !validOffsets.isEmpty else { return }
        let oldIndex = current.flatMap { selected in queue.firstIndex { $0.id == selected.id } } ?? 0
        let removed = Set(validOffsets.map { queue[$0].id })
        let shouldContinue = wantsPlayback || isPlaying
        queue = queue.enumerated().filter { !validOffsets.contains($0.offset) }.map(\.element)
        shuffleRemaining.removeAll { removed.contains($0) }
        shuffleHistory.removeAll { removed.contains($0) }
        guard !queue.isEmpty else { stop(); return }
        if let current, removed.contains(current.id) {
            let survivingIndex = oldIndex - validOffsets.filter { $0 < oldIndex }.count
            load(queue[min(survivingIndex, queue.count - 1)], autoPlay: shouldContinue)
            resetShuffle()
        }
        updateRemoteCommands()
        persistSession()
    }

    func moveQueue(from offsets: IndexSet, to destination: Int) {
        let valid = offsets.filter { queue.indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.sorted().map { queue[$0] }
        var remaining = queue.enumerated().filter { !valid.contains($0.offset) }.map(\.element)
        let adjusted = destination - valid.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: max(0, min(adjusted, remaining.count)))
        queue = remaining
        updateRemoteCommands()
        persistSession()
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        updateRemoteCommands()
        persistSession()
    }

    func setRate(_ value: Float) {
        guard value.isFinite else { return }
        playbackRate = min(2, max(0.5, value))
        if wantsPlayback, pendingSeek == nil, !isSeeking { player.rate = playbackRate }
        updateNowPlaying()
        persistSession()
    }

    /// Pauses after the current track instead of at a clock time.
    func setSleepAtTrackEnd(_ enabled: Bool) {
        setSleepTimer(minutes: nil)
        sleepAtTrackEnd = enabled
    }

    /// Skips relative to the playhead (podcast-style ±15 s).
    func skip(by seconds: Double) {
        guard current != nil else { return }
        seek(to: max(0, elapsed + seconds))
    }

    /// A–B repeat: first call marks A, second marks B, third clears the loop.
    func cycleLoop() {
        guard current != nil else { return }
        if loopStart == nil { loopStart = elapsed }
        else if loopEnd == nil, elapsed > (loopStart ?? 0) + 1 { loopEnd = elapsed }
        else { loopStart = nil; loopEnd = nil }
    }

    func setSleepTimer(minutes: Int?) {
        sleepTask?.cancel()
        sleepTask = nil
        sleepDeadline = nil
        sleepAtTrackEnd = false
        sleepGeneration = UUID()
        guard let minutes, minutes > 0 else { return }
        let interval = Double(min(minutes, 1440)) * 60
        let generation = sleepGeneration
        sleepDeadline = Date().addingTimeInterval(interval)
        sleepTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(interval)) } catch { return }
            guard !Task.isCancelled, let self, self.sleepGeneration == generation else { return }
            self.pause()
            self.sleepDeadline = nil
            self.sleepTask = nil
        }
    }

    func stop() {
        listening?.updatePlayback(trackID: nil, isPlaying: false)
        wantsPlayback = false
        resumeAfterInterruption = false
        lastUnexpectedPause = nil
        player.pause()
        itemObservations.forEach { $0.invalidate() }
        itemObservations.removeAll()
        player.currentItem?.cancelPendingSeeks()
        player.replaceCurrentItem(with: nil)
        current = nil
        queue = []
        isPlaying = false
        elapsed = 0
        duration = 0
        pendingSeek = nil
        seekGeneration = UUID()
        isSeeking = false
        shuffleRemaining = []
        shuffleHistory = []
        setSleepTimer(minutes: nil)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        updateRemoteCommands()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        audioSessionActive = false
        clearSession()
    }

    private func load(_ track: MediaTrack, autoPlay: Bool, resumeAt seconds: Double? = nil) {
        defer { persistSession() }
        listening?.updatePlayback(trackID: nil, isPlaying: false)
        errorMessage = nil
        loopStart = nil
        loopEnd = nil
        wantsPlayback = autoPlay
        resumeAfterInterruption = false
        lastUnexpectedPause = nil
        itemObservations.forEach { $0.invalidate() }
        itemObservations.removeAll()
        player.currentItem?.cancelPendingSeeks()
        seekGeneration = UUID()
        isSeeking = false
        player.pause()
        current = track
        duration = track.duration.isFinite ? max(0, track.duration) : 0
        pendingSeek = seconds.flatMap { $0.isFinite && $0 >= 0 ? (duration > 0 ? min($0, duration) : $0) : nil }
        elapsed = pendingSeek ?? 0
        countedCurrentPlay = false
        let url = library.url(for: track)
        guard FileManager.default.fileExists(atPath: url.path) else {
            player.replaceCurrentItem(with: nil)
            wantsPlayback = false
            isPlaying = false
            errorMessage = "Bu parçanın dosyası bulunamadı. Dosyayı yeniden içe aktarın."
            updateNowPlaying()
            updateRemoteCommands()
            return
        }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        itemObservations = [
            item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                Task { @MainActor [weak self, weak item] in
                    guard let self, let item, self.player.currentItem === item else { return }
                    self.itemStatusChanged(item)
                }
            },
            item.observe(\.duration, options: [.initial, .new]) { [weak self] item, _ in
                Task { @MainActor [weak self, weak item] in
                    guard let self, let item, self.player.currentItem === item else { return }
                    self.updateDuration(item)
                }
            }
        ]
        if autoPlay { resume() } else { isPlaying = false }
        updateNowPlaying()
        updateRemoteCommands()
    }

    private func resume() {
        guard current != nil else { return }
        lastUnexpectedPause = nil
        // AVPlayer cannot recover a failed item by calling play again.
        if player.currentItem == nil || player.currentItem?.status == .failed {
            if let current { load(current, autoPlay: true, resumeAt: elapsed) }
            return
        }
        do {
            if !audioSessionActive {
                let session = AVAudioSession.sharedInstance()
                if session.category != .playback || session.mode != .default { try session.setCategory(.playback, mode: .default) }
                try session.setActive(true)
                audioSessionActive = true
            }
            errorMessage = nil
            wantsPlayback = true
            isPlaying = true
            if duration > 0, elapsed >= duration - 0.15 { seek(to: 0) }
            performPendingSeek()
            if pendingSeek == nil, !isSeeking { player.playImmediately(atRate: playbackRate) }
            updateNowPlaying()
            persistSession()
        } catch {
            wantsPlayback = false
            isPlaying = false
            errorMessage = "Ses çıkışı başlatılamadı: \(error.localizedDescription)"
        }
    }

    private func pause(userInitiated: Bool = true) {
        if userInitiated {
            stallMonitor = PlaybackStallMonitor()
            resumeAfterInterruption = false
            lastUnexpectedPause = nil
        }
        listening?.updatePlayback(trackID: current?.id, isPlaying: false)
        wantsPlayback = false
        isPlaying = false
        player.pause()
        captureCurrentPosition()
        updateNowPlaying()
        persistSession()
    }

    private func advance(automatically: Bool) {
        guard let current else { return }
        if automatically && sleepAtTrackEnd {
            sleepAtTrackEnd = false
            pause()
            if duration > 0 { elapsed = duration }
            updateNowPlaying()
            persistSession()
            return
        }
        if automatically && repeatMode == .one {
            seek(to: 0)
            resume()
            return
        }
        var selected: MediaTrack?
        if shuffleEnabled {
            if shuffleRemaining.isEmpty && repeatMode == .all {
                shuffleRemaining = queue.map(\.id).filter { $0 != current.id }.shuffled()
                if shuffleRemaining.isEmpty { shuffleRemaining = [current.id] }
            }
            while !shuffleRemaining.isEmpty && selected == nil {
                let id = shuffleRemaining.removeFirst()
                selected = queue.first { $0.id == id }
            }
            if selected != nil { shuffleHistory.append(current.id) }
        } else if let index = queue.firstIndex(where: { $0.id == current.id }) {
            if queue.indices.contains(index + 1) { selected = queue[index + 1] }
            else if repeatMode == .all { selected = queue.first }
        }
        if let selected { load(selected, autoPlay: true) }
        else {
            pause()
            if automatically, duration > 0 { elapsed = duration }
            updateNowPlaying()
            persistSession()
        }
    }

    private func resetShuffle() {
        shuffleHistory = []
        shuffleRemaining = queue.map(\.id).filter { $0 != current?.id }.shuffled()
    }

    private func synchronizeLibrary(_ tracks: [MediaTrack]) {
        let available = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let oldIndex = current.flatMap { track in queue.firstIndex { $0.id == track.id } } ?? 0
        let survivingIndex = queue.prefix(oldIndex).filter { available[$0.id] != nil }.count
        let keepPlaying = wantsPlayback || isPlaying
        queue = queue.compactMap { available[$0.id] }
        shuffleHistory.removeAll { available[$0] == nil }
        shuffleRemaining.removeAll { available[$0] == nil }
        if let selected = current {
            if let updated = available[selected.id] { current = updated }
            else if !queue.isEmpty {
                load(queue[min(survivingIndex, queue.count - 1)], autoPlay: keepPlaying)
                resetShuffle()
            } else { stop() }
        }
        updateNowPlaying()
        updateRemoteCommands()
        persistSession()
    }

    private func itemStatusChanged(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            updateDuration(item)
            performPendingSeek()
            if wantsPlayback, pendingSeek == nil, !isSeeking { player.playImmediately(atRate: playbackRate) }
        case .failed:
            playbackFailed(item.error)
        case .unknown: break
        @unknown default: break
        }
        updateRemoteCommands()
    }

    private func updateDuration(_ item: AVPlayerItem) {
        let seconds = item.duration.seconds
        if seconds.isFinite && seconds > 0 { duration = seconds }
        updateNowPlaying()
    }

    private func playbackFailed(_ error: Error?) {
        pause()
        errorMessage = "Parça oynatılamadı. \(error?.localizedDescription ?? "Dosya biçimi desteklenmiyor veya dosya eksik.")"
    }

    private func checkPlaybackProgress() {
        guard let current else { return }
        let eligible = current.kind == .audio && !interruptionActive && audioSessionActive &&
            (wantsPlayback || lastUnexpectedPause != nil) && pendingSeek == nil && !isSeeking &&
            player.currentItem?.status == .readyToPlay && (duration <= 0 || elapsed < duration - 1)
        switch stallMonitor.sample(track: current.id, position: player.currentTime().seconds, now: uptime(), eligible: eligible) {
        case .none: break
        case .recover:
            let position = elapsed, a = loopStart, b = loopEnd, counted = countedCurrentPlay
            load(current, autoPlay: true, resumeAt: position)
            loopStart = a; loopEnd = b; countedCurrentPlay = counted
        case .stop:
            pause()
            errorMessage = "Oynatma ilerlemiyor. Parça durduruldu; yeniden çalmayı deneyebilirsin."
        }
    }

    private func observePlayer() {
        playerObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.current != nil else { return }
                switch self.player.timeControlStatus {
                case .playing:
                    self.lastUnexpectedPause = nil
                    self.wantsPlayback = true
                    self.isPlaying = true
                    if !self.countedCurrentPlay, let track = self.current {
                        self.countedCurrentPlay = true
                        self.library.recordPlay(track)
                    }
                case .waitingToPlayAtSpecifiedRate:
                    self.isPlaying = self.wantsPlayback
                case .paused:
                    if self.player.currentItem?.status == .readyToPlay, self.pendingSeek == nil, !self.isSeeking {
                        // VideoPlayer exposes its own pause control directly on AVPlayer;
                        // treat that as a user pause instead of replaying it later.
                        if self.current?.kind == .audio, self.wantsPlayback || self.isPlaying {
                            self.lastUnexpectedPause = self.uptime()
                        }
                        self.wantsPlayback = false
                        self.isPlaying = false
                        self.captureCurrentPosition()
                        self.persistSession()
                    }
                @unknown default: break
                }
                self.updateListeningPlayback()
                self.updateNowPlaying()
            }
        }
        periodicObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, self.current != nil else { return }
                if let a = self.loopStart, let b = self.loopEnd, time.seconds >= b { self.seek(to: a) }
                self.updateListeningPlayback()
                self.listening?.tick()
                self.captureCurrentPosition()
                if let item = self.player.currentItem { self.updateDuration(item) }
                self.updateNowPlaying()
                self.persistSession(throttled: true)
            }
        }
    }

    private func observeNotifications() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.updateListeningPlayback()
                self?.listening?.flush()
                self?.captureCurrentPosition()
                self?.persistSession()
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.listening?.flush()
                self?.captureCurrentPosition()
                self?.persistSession()
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] notification in
                guard let self, let item = notification.object as? AVPlayerItem,
                      self.player.currentItem === item else { return }
                self.advance(automatically: true)
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVPlayerItem.timeJumpedNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] notification in
                guard let self, let item = notification.object as? AVPlayerItem,
                      self.player.currentItem === item, self.pendingSeek == nil, !self.isSeeking else { return }
                // VideoPlayer's own transport controls can seek without using seek(to:).
                self.captureCurrentPosition()
                self.updateNowPlaying()
                self.persistSession()
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] notification in
                guard let self, let item = notification.object as? AVPlayerItem,
                      self.player.currentItem === item else { return }
                self.playbackFailed(notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] notification in
                guard let self,
                      let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
                let raw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                self.handleInterruption(type, options: AVAudioSession.InterruptionOptions(rawValue: raw))
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] notification in
                let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                if raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.pause() }
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self else { return }
                self.audioSessionActive = false
                guard let current = self.current else { return }
                self.load(current, autoPlay: self.wantsPlayback || self.isPlaying, resumeAt: self.elapsed)
            }.store(in: &subscriptions)
    }

    /// The player can report its system pause just before the interruption notification.
    func handleInterruption(_ type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions = []) {
        switch type {
        case .began:
            interruptionActive = true
            let recentlyPaused = lastUnexpectedPause.map { uptime() - $0 >= 0 && uptime() - $0 <= 2 } ?? false
            audioSessionActive = false
            resumeAfterInterruption = wantsPlayback || isPlaying || recentlyPaused
            lastUnexpectedPause = nil
            pause(userInitiated: false)
        case .ended:
            interruptionActive = false
            let shouldResume = resumeAfterInterruption && options.contains(.shouldResume)
            resumeAfterInterruption = false
            if shouldResume { resume() }
        @unknown default: break
        }
    }

    private func captureCurrentPosition() {
        // A pending or in-flight seek owns the displayed and saved position. AVPlayer
        // can still report zero (or the old item position) until it completes.
        guard current != nil, pendingSeek == nil, !isSeeking,
              player.currentItem?.status == .readyToPlay else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { return }
        elapsed = duration > 0 ? min(max(0, seconds), duration) : max(0, seconds)
    }

    private func restoreSession() {
        guard FileManager.default.fileExists(atPath: sessionURL.path) else { return }
        restoringSession = true
        defer { restoringSession = false }
        do {
            let state = try JSONDecoder().decode(Session.self, from: Data(contentsOf: sessionURL))
            guard state.version == 1, state.elapsed.isFinite, state.elapsed >= 0,
                  state.rate.isFinite, state.rate > 0, state.queueIDs.contains(state.currentID) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let available = Dictionary(uniqueKeysWithValues: library.tracks.filter {
                FileManager.default.fileExists(atPath: library.url(for: $0).path)
            }.map { ($0.id, $0) })
            var seen = Set<UUID>()
            queue = state.queueIDs.compactMap { id in
                guard seen.insert(id).inserted else { return nil }
                return available[id]
            }
            playbackRate = min(2, max(0.5, state.rate))
            repeatMode = state.repeatMode
            shuffleEnabled = state.shuffleEnabled
            // Deleted or unavailable tracks never get resurrected from the session.
            // If selection vanished, select the next surviving row at position zero.
            guard !queue.isEmpty else { updateRemoteCommands(); return }
            let previousIndex = state.queueIDs.firstIndex(of: state.currentID) ?? 0
            let survivingIndex = state.queueIDs.prefix(previousIndex).filter { available[$0] != nil }.count
            let selected = available[state.currentID] ?? queue[min(survivingIndex, queue.count - 1)]
            load(selected, autoPlay: false, resumeAt: selected.id == state.currentID ? state.elapsed : 0)
            let queueIDs = Set(queue.map(\.id))
            var remainingSeen = Set<UUID>()
            shuffleRemaining = state.shuffleRemaining.filter {
                queueIDs.contains($0) && $0 != selected.id && remainingSeen.insert($0).inserted
            }
            shuffleHistory = state.shuffleHistory.filter { queueIDs.contains($0) }
            lastSavedSession = state
            lastSessionWrite = uptime()
            updateRemoteCommands()
        } catch {
            // Keep the only copy of unreadable state. New sessions may be saved only
            // after a recovery copy succeeds; initialization itself never rewrites it.
            let backup = sessionURL.deletingLastPathComponent()
                .appendingPathComponent("playback-session-corrupt-\(UUID().uuidString).json")
            do { try FileManager.default.copyItem(at: sessionURL, to: backup) }
            catch { canWriteSession = false }
            errorMessage = canWriteSession
                ? "Son çalma oturumu okunamadı. Önceki kayıt korundu."
                : "Son çalma oturumu okunamadı; mevcut kayıt korunuyor."
        }
    }

    private func persistSession(throttled: Bool = false) {
        guard !restoringSession, canWriteSession, let current else { return }
        let now = uptime()
        guard !throttled || now - lastSessionWrite >= 10 else { return }
        let position = pendingSeek ?? elapsed
        guard position.isFinite, position >= 0 else { return }
        let state = Session(currentID: current.id, queueIDs: queue.map(\.id), elapsed: position,
                            rate: playbackRate, repeatMode: repeatMode, shuffleEnabled: shuffleEnabled,
                            shuffleRemaining: shuffleRemaining, shuffleHistory: shuffleHistory)
        guard state != lastSavedSession else { return }
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: sessionURL, options: .atomic)
            lastSavedSession = state
        } catch {
            errorMessage = "Çalma oturumu kaydedilemedi: \(error.localizedDescription)"
        }
        lastSessionWrite = now
    }

    private func clearSession() {
        lastSavedSession = nil
        do {
            if FileManager.default.fileExists(atPath: sessionURL.path) {
                try FileManager.default.removeItem(at: sessionURL)
            }
        } catch {
            errorMessage = "Çalma oturumu temizlenemedi: \(error.localizedDescription)"
        }
    }

    private func updateListeningPlayback() {
        listening?.updatePlayback(trackID: current?.id,
                                  isPlaying: player.timeControlStatus == .playing,
                                  isSeeking: isSeeking || pendingSeek != nil)
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        register(center.playCommand) { $0.resume() }
        register(center.pauseCommand) { $0.pause() }
        register(center.togglePlayPauseCommand) { $0.togglePlayPause() }
        register(center.nextTrackCommand) { $0.next() }
        register(center.previousTrackCommand) { $0.previous() }
        register(center.stopCommand) { $0.stop() }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]
        register(center.skipForwardCommand) { $0.seek(to: $0.elapsed + 15) }
        register(center.skipBackwardCommand) { $0.seek(to: max(0, $0.elapsed - 15)) }
        let seekTarget = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor [weak self] in self?.seek(to: position) }
            return .success
        }
        remoteTargets.append((center.changePlaybackPositionCommand, seekTarget))
        center.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 0.75, 1, 1.25, 1.5, 2]
        let rateTarget = center.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            let rate = event.playbackRate
            Task { @MainActor [weak self] in self?.setRate(rate) }
            return .success
        }
        remoteTargets.append((center.changePlaybackRateCommand, rateTarget))
        let repeatTarget = center.changeRepeatModeCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
            let type = event.repeatType
            Task { @MainActor [weak self] in
                self?.repeatMode = type == .one ? .one : (type == .all ? .all : .off)
                self?.updateRemoteCommands()
                self?.persistSession()
            }
            return .success
        }
        remoteTargets.append((center.changeRepeatModeCommand, repeatTarget))
        let shuffleTarget = center.changeShuffleModeCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangeShuffleModeCommandEvent else { return .commandFailed }
            let enabled = event.shuffleType != .off
            Task { @MainActor [weak self] in self?.shuffleEnabled = enabled }
            return .success
        }
        remoteTargets.append((center.changeShuffleModeCommand, shuffleTarget))
        updateRemoteCommands()
    }

    private func register(_ command: MPRemoteCommand, action: @escaping @MainActor (PlaybackStore) -> Void) {
        let target = command.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in if let self { action(self) } }
            return .success
        }
        remoteTargets.append((command, target))
    }

    private func updateRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        let hasTrack = current != nil
        center.playCommand.isEnabled = hasTrack
        center.pauseCommand.isEnabled = hasTrack
        center.togglePlayPauseCommand.isEnabled = hasTrack
        center.stopCommand.isEnabled = hasTrack
        center.nextTrackCommand.isEnabled = hasTrack && (queue.count > 1 || repeatMode == .all)
        center.previousTrackCommand.isEnabled = hasTrack
        center.changePlaybackPositionCommand.isEnabled = hasTrack && duration > 0
        center.skipForwardCommand.isEnabled = hasTrack && duration > 0
        center.skipBackwardCommand.isEnabled = hasTrack && duration > 0
        center.changePlaybackRateCommand.isEnabled = hasTrack
        center.changeRepeatModeCommand.isEnabled = hasTrack
        center.changeShuffleModeCommand.isEnabled = hasTrack
        center.changeRepeatModeCommand.currentRepeatType = repeatMode == .one ? .one : (repeatMode == .all ? .all : .off)
        center.changeShuffleModeCommand.currentShuffleType = shuffleEnabled ? .items : .off
    }

    private func updateNowPlaying() {
        guard let current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.artist.isEmpty ? "Ritim" : current.artist,
            MPMediaItemPropertyAlbumTitle: "Ritim Kitaplığı",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: playbackRate,
            MPNowPlayingInfoPropertyIsLiveStream: false,
            MPNowPlayingInfoPropertyMediaType: current.kind == .video ? MPNowPlayingInfoMediaType.video.rawValue : MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let index = queue.firstIndex(where: { $0.id == current.id }) {
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
