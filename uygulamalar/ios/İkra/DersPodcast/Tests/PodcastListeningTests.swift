import AVFoundation
import Foundation
import Testing
import SwiftData
@testable import Ikra

/// P5: dinleme, kontrol, Siri/Kısayollar/Spotlight, canlı soru.
@MainActor
@Suite(.serialized)
struct PodcastListeningTests {
    // MARK: - Yardımcılar

    /// Kapsayıcılar test boyunca yaşar (ARC erken bırakırsa bağlam SwiftData'da çöker).
    private static var containers: [ModelContainer] = []

    private func container() throws -> ModelContainer {
        let c = try ModelContainer(for: Schema(AppDataStore.modelTypes), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        Self.containers.append(c)
        return c
    }

    /// Sessiz WAV'lı hazır bölüm (konular `chapters` başlangıçlarında).
    private func episode(_ title: String, seconds: Double = 4, chapters: [Double] = [0], context: ModelContext,
                         series: UUID? = nil, index: Int = 0) throws -> Episode {
        let script = PodcastScript(title: title, summary: "", keyPoints: [], chapters: [], sourceNotes: "Notlar")
        let e = Episode(script: script, settings: PodcastSettings(), sourceNames: [], jobToken: "t")
        e.status = .ready
        e.audioFileName = "audio.wav"
        e.duration = seconds
        e.seriesID = series
        e.seriesIndex = index
        let turns = chapters.enumerated().map { i, start in
            TimedTurn(id: i, chapterIndex: i, speaker: .a, text: "Konu \(i + 1) anlatımı burada", start: start,
                      end: chapters[safe: i + 1] ?? seconds)
        }
        e.timeline = Timeline(chapters: chapters.enumerated().map { TimedChapter(id: $0, title: "Konu \($0 + 1)", start: $1) },
                              turns: turns, duration: seconds)
        context.insert(e)
        try WAV.encode(PCMClip.silence(seconds: seconds, sampleRate: 8000)).write(to: try #require(e.audioURL))
        return e
    }

    @MainActor private final class Gate { var open = false }

    /// Kuyruğu uygulamanın kalıcı kuyruğundan ayrı tutan oynatıcı.
    private func makePlayer(_ store: UserDefaults? = nil) -> PlayerController {
        let player = PlayerController()
        // Ayrı alan: testler uygulamanın kalıcı kuyruğuna (`player.queue`) dokunmaz.
        player.queueStore = store ?? UserDefaults(suiteName: "p5.player")!
        player.setQueue([])
        return player
    }

    private func cleanup(_ episodes: Episode...) {
        for e in episodes { EpisodeFiles.remove(episode: e.id) }
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() { try? await Task.sleep(for: .milliseconds(20)) }
    }

    // MARK: - #16 göz atma

    @Test func browsingNeverLoadsWithoutRequest() throws {
        let a = UUID(), b = UUID()
        // İstek yokken durum değişse de (generating → ready) hiçbir şey yüklenmez.
        #expect(EpisodeBrowse.action(pending: nil, episodeID: a, isReady: true, isCurrent: false) == .none)
        #expect(EpisodeBrowse.action(pending: nil, episodeID: a, isReady: false, isCurrent: false) == .none)
        // Başka bölümün isteği bu ekranı ilgilendirmez.
        let other = AppState.PendingPlayback(episodeID: b, time: 10, play: true)
        #expect(EpisodeBrowse.action(pending: other, episodeID: a, isReady: true, isCurrent: false) == .none)
        // Hazır olmayan bölümde istek bekler.
        let mine = AppState.PendingPlayback(episodeID: a, time: 12, play: true)
        #expect(EpisodeBrowse.action(pending: mine, episodeID: a, isReady: false, isCurrent: false) == .none)
        #expect(EpisodeBrowse.action(pending: mine, episodeID: a, isReady: true, isCurrent: false) == .play(12))
        // Çalmadan konuma git: çalan bu bölümse sar, değilse yalnız metni o ana getir.
        let seekOnly = AppState.PendingPlayback(episodeID: a, time: 30, play: false)
        #expect(EpisodeBrowse.action(pending: seekOnly, episodeID: a, isReady: true, isCurrent: true) == .seek(30))
        #expect(EpisodeBrowse.action(pending: seekOnly, episodeID: a, isReady: true, isCurrent: false) == .focus(30))
    }

    @Test func playSwitchesOnlyOnExplicitRequest() throws {
        let c = try container()
        let context = c.mainContext
        let a = try episode("A", context: context), b = try episode("B", seconds: 6, context: context)
        defer { cleanup(a, b) }
        let player = makePlayer()
        player.play(a, at: nil, context: context)
        #expect(player.episode?.id == a.id && player.isPlaying)
        // B'ye göz atmak (istek yok) çalanı değiştirmez.
        #expect(EpisodeBrowse.action(pending: nil, episodeID: b.id, isReady: true, isCurrent: false) == .none)
        #expect(player.episode?.id == a.id)
        // "Bunu çal": B, istenen andan.
        player.play(b, at: 2, context: context)
        #expect(player.episode?.id == b.id && player.isPlaying)
        #expect(abs(player.currentTime - 2) < 0.01)
        player.close()
    }

    // MARK: - #50 dinleme süresi

    @Test func listeningTimeIsWrittenToThePreviousEpisode() throws {
        let c = try container()
        let context = c.mainContext
        let a = try episode("A", context: context), b = try episode("B", context: context)
        defer { cleanup(a, b) }
        let player = makePlayer()
        player.load(a, context: context, autoplay: false)
        player.listenedPending = 7
        player.load(b, context: context, autoplay: false)
        #expect(player.listenedPending == 0)
        let key = ListeningDay.key()
        var day = try #require(context.fetch(FetchDescriptor<ListeningDay>(predicate: #Predicate { $0.day == key })).first)
        #expect(day.seconds == 7)
        #expect(try JSONDecoder().decode([UUID].self, from: #require(day.episodesData)) == [a.id])

        player.listenedPending = 3
        player.close()
        day = try #require(context.fetch(FetchDescriptor<ListeningDay>(predicate: #Predicate { $0.day == key })).first)
        #expect(day.seconds == 10)
        #expect(try JSONDecoder().decode([UUID].self, from: #require(day.episodesData)) == [a.id, b.id])
    }

    // MARK: - #17 kilit ekranı

    @Test func finishedEpisodeRestartsFromTheBeginning() throws {
        let c = try container()
        let context = c.mainContext
        let a = try episode("A", context: context)
        defer { cleanup(a) }
        let player = makePlayer()
        player.autoplayNext = false
        player.load(a, context: context, autoplay: false)
        player.seek(to: 3.5)
        player.finished()
        #expect(a.isFinished && !player.isPlaying)
        player.play()
        #expect(player.isPlaying && !a.isFinished)
        #expect(player.currentTime < 0.01)
        player.close()
    }

    @Test func chapterNavigationTargets() {
        let timeline = Timeline(chapters: [TimedChapter(id: 0, title: "Giriş", start: 0), TimedChapter(id: 1, title: "Zar", start: 60),
                                           TimedChapter(id: 2, title: "Taşıma", start: 120)], turns: [], duration: 180)
        #expect(PlayerController.chapterTarget(from: 70, timeline: timeline, forward: true) == 120)
        #expect(PlayerController.chapterTarget(from: 130, timeline: timeline, forward: true) == nil)      // son konu
        #expect(PlayerController.chapterTarget(from: 70, timeline: timeline, forward: false) == 60)       // konunun başına
        #expect(PlayerController.chapterTarget(from: 61, timeline: timeline, forward: false) == 0)        // ilk saniyelerde bir önceki
        #expect(PlayerController.chapterTarget(from: 0.5, timeline: timeline, forward: false) == nil)
        #expect(PlayerController.chapterTarget(from: 10, timeline: nil, forward: true) == nil)
        #expect(PlayerController.chapterLabel(index: 2, count: 8) == "Konu 3/8")
        #expect(PlayerController.chapterLabel(index: 0, count: 1) == nil)
    }

    @Test func nextAndPreviousTrackMoveBetweenChapters() throws {
        let c = try container()
        let context = c.mainContext
        let a = try episode("A", seconds: 30, chapters: [0, 10, 20], context: context)
        defer { cleanup(a) }
        let player = makePlayer()
        player.load(a, context: context, autoplay: false)
        player.route(.nextChapter)
        #expect(player.currentChapterIndex == 1 && abs(player.currentTime - 10) < 0.01)
        player.route(.nextChapter)
        #expect(player.currentChapterIndex == 2)
        player.seek(to: 21)
        player.route(.previousChapter)                         // konunun ilk 3 sn'si: bir önceki konu
        #expect(player.currentChapterIndex == 1)
        player.seek(to: 16)
        player.route(.previousChapter)                         // konunun ortası: konunun başı
        #expect(player.currentChapterIndex == 1 && abs(player.currentTime - 10) < 0.01)
        player.close()
    }

    @Test func rateIsPersistedAndFormatted() {
        #expect(Float(1).rateText == "1×")
        #expect(Float(1.25).rateText == "1,25×")
        #expect(Float(0.75).rateText == "0,75×")
        #expect(Float(1.5).rateText == "1,5×")
        #expect(Float(2).rateText == "2×")
        let suite = "p5.rate.\(UUID().uuidString)"
        let defaults = try! #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(PlayerController.storedRate(defaults) == 1.0)
        defaults.set(Float(1.5), forKey: PlayerController.rateKey)
        #expect(PlayerController.storedRate(defaults) == 1.5)
        defaults.set(Float(9), forKey: PlayerController.rateKey)        // bozuk değer
        #expect(PlayerController.storedRate(defaults) == 1.0)
    }

    @Test func interruptionResumesOnlyWhenPlayingBefore() async throws {
        let c = try container()
        let context = c.mainContext
        let a = try episode("A", context: context)
        defer { cleanup(a) }
        let player = makePlayer()
        player.load(a, context: context, autoplay: true)
        let began: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        let ended: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                                         AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue]
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: began)
        await waitUntil { !player.isPlaying }
        #expect(!player.isPlaying)
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: ended)
        await waitUntil { player.isPlaying }
        #expect(player.isPlaying)
        // Kullanıcı duraklatmışsa kesinti sonrası çalmaz.
        player.pause()
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: began)
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: ended)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!player.isPlaying)
        player.close()
    }

    // MARK: - #36 / #23 düşünme payı

    @Test func relaxedModeSkipsThinkPauses() {
        let pauses = [ThinkPause(turnID: 3, start: 10, end: 15), ThinkPause(turnID: 8, start: 40, end: 44)]
        #expect(ListeningSkip.thinkTarget(at: 10.2, pauses: pauses) == 15)
        #expect(ListeningSkip.thinkTarget(at: 41, pauses: pauses) == 44)
        #expect(ListeningSkip.thinkTarget(at: 9, pauses: pauses) == nil)
        #expect(ListeningSkip.thinkTarget(at: 14.9, pauses: pauses) == nil)      // sona çok yakın: atlama yok
        #expect(ListeningSkip.thinkTarget(at: 20, pauses: pauses) == nil)
        // Tek kaynak politika: Rahat'ta pay çalınmaz, Aktif ve Sınav'da çalınır.
        #expect(!ListeningMode.rahat.policy.playThinkPauses)
        #expect(ListeningMode.aktif.policy.playThinkPauses && ListeningMode.sinav.policy.playThinkPauses)
        // Pay atlaması kapalıyken yalnız sessizlik kuralı çalışır.
        #expect(ListeningSkip.target(at: 10.2, thinkPauses: pauses, skipThink: false, silences: []) == nil)
        #expect(ListeningSkip.target(at: 10.2, thinkPauses: pauses, skipThink: true, silences: []) == 15)
        let silences = [FollowAlong.Pause(start: 20, end: 22)]
        #expect(ListeningSkip.target(at: 20.5, thinkPauses: [], skipThink: false, silences: silences) == 22 - SilenceSkip.lead)
    }

    /// Aktif/Sınav + "Sessizliği atla": payın sessizliği (SpeechPauses onu da bulur) atlanmaz; diğerleri atlanır.
    @Test func silenceSkipKeepsThinkPausesInActiveMode() {
        let think = [ThinkPause(turnID: 3, start: 10, end: 15)]
        let silences = [FollowAlong.Pause(start: 4, end: 6),          // sıradan sessizlik
                        FollowAlong.Pause(start: 10.05, end: 14.9),   // payın kendisi
                        FollowAlong.Pause(start: 20, end: 22)]
        // Aktif/Sınav: pay çalınır (geri sayım #23 açık kalır), diğer sessizlikler atlanır.
        #expect(ListeningSkip.target(at: 11, thinkPauses: think, skipThink: false, silences: silences) == nil)
        #expect(ListeningSkip.target(at: 4.5, thinkPauses: think, skipThink: false, silences: silences) == 6 - SilenceSkip.lead)
        #expect(ListeningSkip.target(at: 20.5, thinkPauses: think, skipThink: false, silences: silences) == 22 - SilenceSkip.lead)
        // Rahat: payın sonuna atlanır.
        #expect(ListeningSkip.target(at: 11, thinkPauses: think, skipThink: true, silences: silences) == 15)
    }

    @Test func thinkCountdownHidesTheAnswer() {
        let turns = [TimedTurn(id: 0, chapterIndex: 0, speaker: .a, text: "Soru?", start: 5, end: 10),
                     TimedTurn(id: 1, chapterIndex: 0, speaker: .b, text: "Cevap.", start: 15, end: 20)]
        let pauses = [ThinkPause(turnID: 0, start: 10, end: 15)]
        #expect(ThinkReveal.hiddenTurns(at: 4, pauses: pauses, turns: turns).isEmpty)
        #expect(ThinkReveal.hiddenTurns(at: 7, pauses: pauses, turns: turns) == [1])
        #expect(ThinkReveal.hiddenTurns(at: 14.9, pauses: pauses, turns: turns) == [1])
        #expect(ThinkReveal.hiddenTurns(at: 15, pauses: pauses, turns: turns).isEmpty)
        #expect(ThinkReveal.countdown(at: 11.2, pauses: pauses)?.seconds == 4)
        #expect(ThinkReveal.countdown(at: 9, pauses: pauses) == nil)
    }

    // MARK: - #45/#46 bağlantılar

    // MARK: - #41 kuyruk

    @Test func deepLinksRoute() throws {
        let previous = AppState.current
        defer { AppState.current = previous }
        let app = AppState()
        let id = UUID()
        DeepLink.apply(.episode(id, time: 30, play: true), to: app)
        #expect(app.selectedTab == .library && app.pendingOpenEpisode == id)
        #expect(app.pendingPlayback == AppState.PendingPlayback(episodeID: id, time: 30, play: true))

        let generation = UUID()
        DeepLink.apply(.generation(generation), to: app)
        #expect(app.pendingOpenEpisode == generation && app.pendingPlayback == nil)

        app.selectedTab = .library
        DeepLink.apply(.route("coach"), to: app)
        // Eski koç bağlantısı (koçluk kaldırıldı) Çalış sekmesini açar.
        #expect(app.selectedTab == .study && app.pendingRoute == nil)
        DeepLink.apply(.route("review"), to: app)
        #expect(app.pendingRoute == "review")

        // URL üzerinden (AppLink ayrıştırır).
        AppState.current = app
        #expect(DeepLink.handle(AppLink.episode(id, time: 75, play: false).url))
        #expect(app.pendingPlayback == AppState.PendingPlayback(episodeID: id, time: 75, play: false))
        #expect(!DeepLink.handle(try #require(URL(string: "https://example.com/episode/x"))))
        #expect(!DeepLink.handle(try #require(URL(string: "kocum://episode/bozuk"))))

        // Spotlight öğe kimlikleri: konu bağlantısı ya da bölüm UUID'si.
        #expect(SpotlightIndex.link(for: AppLink.episode(id, time: 60, play: true).url.absoluteString) == .episode(id, time: 60, play: true))
        #expect(SpotlightIndex.link(for: id.uuidString) == .episode(id, time: nil, play: false))
        #expect(SpotlightIndex.link(for: "rastgele") == nil)
    }

    @Test func queueEncodingAndPersistence() throws {
        let a = UUID(), b = UUID()
        let items: [PlaybackQueueItem] = [.audio(fileName: "brifing.m4a", title: "Günün brifingi"), .episode(a), .episode(b)]
        #expect(PlaybackQueue.decode(PlaybackQueue.encode(items)) == items)
        #expect(PlaybackQueue.encode([]) == nil)
        #expect(PlaybackQueue.decode(Data("bozuk".utf8)) == [])
        #expect(PlaybackQueue.appending(.episode(a), to: items) == items)                       // aynı öğe iki kez girmez
        #expect(PlaybackQueue.removing(episodeID: a, from: items) == [items[0], .episode(b)])
        let suite = "p5.queue.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        PlaybackQueue.save(items, defaults)
        #expect(PlaybackQueue.load(defaults) == items)
        PlaybackQueue.save([], defaults)
        #expect(defaults.data(forKey: PlaybackQueue.key) == nil)
    }

    @Test func playerQueuePlaysInOrderAndFallsBackToSeries() throws {
        let c = try container()
        let context = c.mainContext
        let series = UUID()
        let a = try episode("A", context: context, series: series, index: 1)
        let b = try episode("B", context: context, series: series, index: 2)
        let x = try episode("X", context: context)
        defer { cleanup(a, b, x) }
        let suite = "p5.queue.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        let player = makePlayer(store)
        player.load(a, context: context, autoplay: false)
        #expect(player.nextUp()?.id == b.id)                  // kuyruk boş: seri
        player.enqueue(.episode(x.id))
        player.enqueue(.episode(x.id))
        #expect(player.upNext == [.episode(x.id)])
        #expect(player.nextUp()?.id == x.id)                  // kuyruk seriden önce
        #expect(PlaybackQueue.load(store) == [.episode(x.id)])  // kalıcı
        player.playNext()
        #expect(player.episode?.id == x.id && player.upNext.isEmpty)

        player.playQueue([.episode(b.id), .episode(a.id)], context: context)
        #expect(player.episode?.id == b.id && player.upNext == [.episode(a.id)])
        player.removeFromQueue(episodeID: a.id)
        #expect(player.upNext.isEmpty)
        player.close()
    }

    // MARK: - #25 interlude

    @Test func interludeStateMachine() throws {
        let c = try container()
        let context = c.mainContext
        let a = try episode("A", seconds: 6, chapters: [0, 3], context: context)
        defer { cleanup(a) }
        let player = makePlayer()
        #expect(!player.beginInterlude())                    // yüklü bölüm yok
        player.load(a, context: context, autoplay: true)
        #expect(player.beginInterlude())
        #expect(player.isInInterlude && !player.isPlaying)
        #expect(!player.beginInterlude())                    // iç içe yok

        var received: [RemoteCommand] = []
        player.interludeRemoteHandler = { command in
            received.append(command)
            return command == .nextChapter                    // "bilemedim"
        }
        player.route(.nextChapter)
        #expect(received == [.nextChapter] && player.currentChapterIndex == 0)   // tüketildi: konu değişmedi

        player.endInterlude(resume: true)
        #expect(!player.isInInterlude && player.isPlaying && player.interludeRemoteHandler == nil)
        player.route(.nextChapter)                            // artık oynatıcıya gider
        #expect(player.currentChapterIndex == 1)

        // Duraklatılmışken başlayan ara ses bitince podcast kendiliğinden çalmaz.
        player.pause()
        #expect(player.beginInterlude())
        player.endInterlude(resume: true)
        #expect(!player.isPlaying)
        player.close()
    }

    // MARK: - #19 komut eşlemesi

    @Test func playbackCommandMapping() throws {
        let c = try container()
        let context = c.mainContext
        #expect(ListeningHooks.perform(.bookmark, player: nil, context: context) == "Ders Podcast’i açıp yeniden dene.")
        let player = makePlayer()
        #expect(ListeningHooks.perform(.bookmark, player: player, context: context) == ListeningHooks.nothingPlaying)
        #expect(ListeningHooks.perform(.back15, player: player, context: context) == ListeningHooks.nothingPlaying)
        #expect(ListeningHooks.perform(.resume, player: player, context: context) == "Dinlenecek bölüm bulunamadı.")

        let old = try episode("Eski", seconds: 30, chapters: [0, 10, 20], context: context)
        let recent = try episode("Yeni", seconds: 30, chapters: [0, 10, 20], context: context)
        defer { cleanup(old, recent) }
        old.lastPlayedAt = .now.addingTimeInterval(-3600)
        recent.lastPlayedAt = .now
        // "Sürdür": çalan yoksa en son dinleneni kendisi yükler.
        #expect(ListeningHooks.perform(.resume, player: player, context: context) == "Yeni kaldığı yerden çalıyor.")
        #expect(player.episode?.id == recent.id && player.isPlaying)

        player.seek(to: 12)
        #expect(ListeningHooks.perform(.bookmark, player: player, context: context) == "İşaretlendi: 0:12.")
        let marks = try context.fetch(FetchDescriptor<Bookmark>())
        #expect(marks.count == 1 && marks[0].kind == "siri" && marks[0].chapterIndex == 1 && marks[0].episodeID == recent.id)

        #expect(ListeningHooks.perform(.back15, player: player, context: context) == "15 saniye geri alındı.")
        #expect(player.currentTime < 0.01)
        #expect(ListeningHooks.perform(.nextChapter, player: player, context: context) == "Sonraki konu: Konu 2.")
        #expect(player.currentChapterIndex == 1)
        #expect(Set(PlaybackCommand.allCases) == [.bookmark, .back15, .nextChapter, .resume])
        player.close()
    }

    // MARK: - #26 bölüm sonu sırası

    @Test func episodeFinishedIsPostedBeforeAutoplayAndHoldIsRespected() throws {
        let c = try container()
        let context = c.mainContext
        let series = UUID()
        let a = try episode("A", context: context, series: series, index: 1)
        let b = try episode("B", context: context, series: series, index: 2)
        defer { cleanup(a, b) }
        let player = makePlayer()
        player.load(a, context: context, autoplay: false)

        var log: [String] = []
        let token = PodcastEvent.observe(PodcastEvent.episodeFinished) { info in
            guard info.episodeID == a.id else { return }
            log.append("finished:\(player.episode?.title ?? "-")")
            player.holdAutoplay = true                          // P6 ön planda kart gösterir
        }
        defer { NotificationCenter.default.removeObserver(token) }
        player.finished()
        #expect(log == ["finished:A"])                          // olay, geçiş kararından önce (henüz A)
        #expect(player.episode?.id == a.id)                     // bekletildi
        #expect(!player.holdAutoplay)                           // yalnız o bitiş için
        player.playNext()                                       // kart sayacı bitti
        #expect(player.episode?.id == b.id)

        // Bekletme yoksa sıradaki kendiliğinden başlar.
        NotificationCenter.default.removeObserver(token)
        player.load(a, context: context, autoplay: false)
        player.finished()
        #expect(player.episode?.id == b.id)
        player.close()
    }

    // MARK: - #22/#33 kesitler, işaretler, döngü

    @Test func clipsPlayInOrderAndWaitForTheQuestion() async throws {
        let c = try container()
        let context = c.mainContext
        let a = try episode("A", seconds: 6, context: context)
        defer { cleanup(a) }
        let player = makePlayer()
        let clips = [PodcastClip(episodeID: a.id, start: 0.5, end: 1.0, reason: "yanlış"),
                     PodcastClip(episodeID: UUID(), start: 0, end: 1, reason: "silinmiş bölüm"),
                     PodcastClip(episodeID: a.id, start: 3, end: 4, reason: "anlamadım")]
        var ended: [Double] = []
        player.playClips(clips, context: context) { clip in ended.append(clip.start) }
        #expect(player.clipProgress?.index == 1 && player.clipProgress?.count == 3)
        #expect(abs(player.currentTime - 0.5) < 0.01 && player.isPlaying)
        player.finished()                                       // kesit sonu (bölüm sonuna dayandı)
        await waitUntil { player.clipProgress?.index == 3 }
        #expect(ended == [0.5])
        #expect(abs(player.currentTime - 3) < 0.01)             // silinmiş bölümün kesiti atlandı
        player.finished()
        await waitUntil { player.clipProgress == nil }
        #expect(ended == [0.5, 3])
        #expect(!player.isPlayingClips)
        player.close()
    }

    /// Kesit oturumu bölümün kaldığı yerini bozmaz: oturum bitince oynatıcı duraklar ve eski konuma döner.
    @Test func clipSessionKeepsResumePoint() async throws {
        let c = try container()
        let context = c.mainContext
        let a = try episode("A", seconds: 8, context: context)
        defer { cleanup(a) }
        let player = makePlayer()
        player.load(a, context: context, autoplay: false)
        player.seek(to: 6)
        player.playClips([PodcastClip(episodeID: a.id, start: 1, end: 2, reason: "kart")], context: context) { _ in }
        #expect(abs(player.currentTime - 1) < 0.01 && player.isPlaying)
        #expect(abs(a.lastPosition - 6) < 0.01)                 // oturum kurulmadan yazıldı
        player.pause()                                          // kesit içinde duraklatmak konumu yazmaz
        #expect(abs(a.lastPosition - 6) < 0.01)
        player.play()
        player.finished()                                       // kesit sonu
        await waitUntil { player.clipProgress == nil }
        #expect(!player.isPlayingClips && !player.isPlaying)
        #expect(abs(a.lastPosition - 6) < 0.01)
        #expect(abs(player.currentTime - 6) < 0.01)
        player.close()
        #expect(abs(a.lastPosition - 6) < 0.01)
    }

    /// Kesit "dinlendi" bölümü yarım göstermez, hiç dinlenmemiş bölümü "son dinlenen" yapmaz; oturumu kapatmak
    /// sesi durdurur. Bölüm sonradan olağan çalınırsa dinleme sayılır.
    @Test func clipLeavesFinishedFlagAndLastPlayed() throws {
        let c = try container()
        let context = c.mainContext
        let b = try episode("B", seconds: 6, context: context)
        defer { cleanup(b) }
        b.isFinished = true                                     // elle "dinlendi": kaldığı yer saklı durur
        b.lastPosition = 2
        #expect(b.lastPlayedAt == nil)
        let player = makePlayer()
        player.playClips([PodcastClip(episodeID: b.id, start: 3, end: 4, reason: "kart")], context: context) { _ in }
        #expect(player.isPlaying && b.isFinished && b.lastPlayedAt == nil)
        player.endClipSession()                                 // "Kapat"
        #expect(!player.isPlaying && !player.isPlayingClips)
        #expect(b.isFinished && b.lastPlayedAt == nil && b.lastPosition == 2)
        #expect(player.currentTime == 0)                        // dinlenmiş bölüm baştan başlar
        player.pause()                                          // çalınmadan gelen kayıt saklı konumu silmez
        #expect(b.lastPosition == 2)
        player.play()
        #expect(!b.isFinished && b.lastPlayedAt != nil)
        player.close()
    }

    /// Başka bölümün kesiti: çalan bölümün kaldığı yer saklanır, kesitin bölümü de dokunulmadan kalır.
    @Test func clipFromAnotherEpisodeKeepsBothResumePoints() async throws {
        let c = try container()
        let context = c.mainContext
        let a = try episode("A", seconds: 8, context: context)
        let b = try episode("B", seconds: 8, context: context)
        defer { cleanup(a, b) }
        b.lastPosition = 4
        let player = makePlayer()
        player.load(a, context: context, autoplay: false)
        player.seek(to: 5)
        player.playClips([PodcastClip(episodeID: b.id, start: 1, end: 2, reason: "kart")], context: context) { _ in }
        #expect(player.episode?.id == b.id && abs(player.currentTime - 1) < 0.01)
        #expect(abs(a.lastPosition - 5) < 0.01 && b.lastPlayedAt == nil)
        player.finished()
        await waitUntil { player.clipProgress == nil }
        #expect(abs(b.lastPosition - 4) < 0.01 && abs(player.currentTime - 4) < 0.01 && b.lastPlayedAt == nil)
        #expect(abs(a.lastPosition - 5) < 0.01)
        player.close()
    }

    /// Kesit sürerken bölümde bir satıra atlamak oturumu bitirir; dinleme oradan olağan sürer (geri sarılmaz).
    @Test func jumpingInsideEpisodeEndsClipSession() async throws {
        let c = try container()
        let context = c.mainContext
        let a = try episode("A", seconds: 30, chapters: [0, 4], context: context)
        defer { cleanup(a) }
        let player = makePlayer()
        player.playClips([PodcastClip(episodeID: a.id, start: 1, end: 2, reason: "kart")], context: context) { _ in }
        #expect(player.isPlayingClips && a.lastPlayedAt == nil)
        player.jump(toTurn: 1)
        #expect(!player.isPlayingClips && player.isPlaying && abs(player.currentTime - 4) < 0.01)
        #expect(a.lastPlayedAt != nil)
        // Oturum biterken oynatıcı aynı blokta duraklayıp çaldı: durum gözlemcisinin geciken "durdu" bildirimi
        // işlendikten sonra da çalıyor görünmeli (ses bu arada gerçekten ilerler; bölüm o yüzden uzun).
        try await Task.sleep(for: .milliseconds(100))
        #expect(player.isPlaying)
        player.close()
        #expect(a.lastPosition > 3.9 && a.lastPosition < 20)    // atlanan yerden sürdü; başa ya da kesite dönmedi
    }

    /// Kesit çalarken aynı bölüm için yeniden kesit başlatmak (Tekrar'da "O anı dinle"ye ikinci basış): oturum bitip
    /// yeniden kurulurken oynatıcı aynı blokta duraklayıp çalar; arayüz "duraklatıldı"ya dönmez (yoksa kesit sonu işlemez).
    @Test func restartingClipsOnSameEpisodeKeepsPlaying() async throws {
        let c = try container()
        let context = c.mainContext
        let a = try episode("A", seconds: 30, context: context)
        defer { cleanup(a) }
        let player = makePlayer()
        let clip = PodcastClip(episodeID: a.id, start: 1, end: 25, reason: "kart")
        player.playClips([clip], context: context) { _ in }
        try await Task.sleep(for: .milliseconds(100))
        #expect(player.isPlaying)                               // ilk başlatma: çalıyor
        player.playClips([clip], context: context) { _ in }
        #expect(player.isPlaying && player.isPlayingClips)
        try await Task.sleep(for: .milliseconds(100))
        #expect(player.isPlaying && player.isPlayingClips)
        player.close()
    }

    /// Açık kesit oturumunda kesitin gerisine gezinmek (çubuk, önceki konu) oturumu bitirir: dinleme konumu yeniden
    /// yazılır, kesit sonunda eski yere sarılmaz. Kesit başında tek "15 sn geri" oturumu bozmaz.
    @Test func seekingOutsideClipEndsSession() throws {
        let c = try container()
        let context = c.mainContext
        let a = try episode("A", seconds: 30, context: context)
        defer { cleanup(a) }
        let player = makePlayer()
        player.load(a, context: context, autoplay: false)
        player.seek(to: 12)
        player.playClips([PodcastClip(episodeID: a.id, start: 20, end: 25, reason: "kart")], context: context) { _ in }
        player.pause()                                          // duraklatmak oturumu kapatmaz
        player.skip(-15)                                        // 20 → 5: pay içinde
        #expect(player.isPlayingClips && abs(player.currentTime - 5) < 0.01)
        player.seek(to: 2)
        #expect(!player.isPlayingClips && player.clipProgress == nil && !player.isPlaying)
        #expect(abs(player.currentTime - 2) < 0.01)
        player.play()
        player.close()
        #expect(abs(a.lastPosition - 2) < 0.5)                  // kesit öncesi konuma (12) dönülmedi
    }

    /// Çalarken kesit sonunun ötesine gezinmek (±15, ilerideki not): oturum biter, çalma hedeften sürer.
    @Test func seekingPastClipEndWhilePlayingKeepsPlaying() async throws {
        let c = try container()
        let context = c.mainContext
        let a = try episode("A", seconds: 30, context: context)
        defer { cleanup(a) }
        let player = makePlayer()
        player.load(a, context: context, autoplay: false)
        player.seek(to: 25)
        player.playClips([PodcastClip(episodeID: a.id, start: 1, end: 2, reason: "kart")], context: context) { _ in }
        player.skip(3)                                          // 1 → 4
        #expect(!player.isPlayingClips && player.isPlaying && abs(player.currentTime - 4) < 0.01)
        try await Task.sleep(for: .milliseconds(100))
        #expect(player.isPlaying && !player.isPlayingClips)     // geciken "durdu" bildirimi çalmayı duraklatılmış göstermez
        player.close()
        #expect(a.lastPosition > 3.9 && a.lastPosition < 20)    // kesit öncesi konuma (25) dönülmedi
    }

    /// Kesitin içinde gezinmek oturumu sürdürür; konum yazılmaz, oturum bitince eski yere dönülür.
    @Test func seekingInsideClipKeepsSession() throws {
        let c = try container()
        let context = c.mainContext
        let a = try episode("A", seconds: 8, context: context)
        defer { cleanup(a) }
        let player = makePlayer()
        player.load(a, context: context, autoplay: false)
        player.seek(to: 6)
        player.playClips([PodcastClip(episodeID: a.id, start: 1, end: 3, reason: "kart")], context: context) { _ in }
        player.seek(to: 2.5)
        #expect(player.isPlayingClips && player.isPlaying && abs(player.currentTime - 2.5) < 0.01)
        #expect(abs(a.lastPosition - 6) < 0.01)
        player.endClipSession()
        #expect(abs(player.currentTime - 6) < 0.01)
        player.close()
        #expect(abs(a.lastPosition - 6) < 0.01)
    }

    /// Sırada kesit varken kesit sonunun ötesine atlamak oturumu bitirmez: kesit bitmiş sayılır, sıradaki çalar.
    @Test func seekingPastClipEndMovesToNextClip() async throws {
        let c = try container()
        let context = c.mainContext
        let a = try episode("A", seconds: 8, context: context)
        defer { cleanup(a) }
        let player = makePlayer()
        let clips = [PodcastClip(episodeID: a.id, start: 1, end: 2, reason: "yanlış"),
                     PodcastClip(episodeID: a.id, start: 5, end: 7, reason: "anlamadım")]
        player.playClips(clips, context: context) { _ in }
        player.skip(2)                                          // 1 → 3: ilk kesitin sonunu aşar
        #expect(player.isPlayingClips)
        await waitUntil { player.clipProgress?.index == 2 }
        #expect(player.isPlayingClips && player.clipProgress?.index == 2 && abs(player.currentTime - 5) < 0.5)
        player.endClipSession()
        player.close()
    }

    /// Açık kesit oturumunda seride sıradaki bölüme geçmek (son konuda "sonraki konu") oturumu bitirir: yeni bölümde
    /// konum yazılır, kesit etiketi takılı kalmaz.
    @Test func seriesAdvanceEndsClipSession() throws {
        let c = try container()
        let context = c.mainContext
        let series = UUID()
        let a = try episode("A", seconds: 8, context: context, series: series, index: 1)
        let b = try episode("B", context: context, series: series, index: 2)
        defer { cleanup(a, b) }
        let player = makePlayer()
        player.load(a, context: context, autoplay: false)
        player.seek(to: 6)
        player.playClips([PodcastClip(episodeID: a.id, start: 1, end: 2, reason: "kart")], context: context) { _ in }
        #expect(player.nextChapter())                           // tek konulu bölüm: sıradaki bölüme geçilir
        #expect(player.episode?.id == b.id && !player.isPlayingClips && player.clipProgress == nil)
        #expect(abs(a.lastPosition - 6) < 0.01 && b.lastPlayedAt != nil)
        player.close()
    }

    @Test func bookmarksAndLoop() throws {
        let c = try container()
        let context = c.mainContext
        let a = try episode("A", seconds: 8, chapters: [0, 4], context: context)
        defer { cleanup(a) }
        let player = makePlayer()
        #expect(player.addBookmark(kind: "confused") == nil)
        player.load(a, context: context, autoplay: false)
        player.seek(to: 5)
        let mark = try #require(player.addBookmark(kind: "confused"))
        #expect(mark.kind == "confused" && mark.chapterIndex == 1 && mark.time == 5)
        #expect(mark.text == "Konu 2 anlatımı burada")

        player.seek(to: 1)
        player.cycleLoop()                                      // A
        #expect(player.loopStart == 1 && player.loop == nil)
        player.seek(to: 3)
        player.cycleLoop()                                      // B: döngü başlar, A'ya döner
        #expect(player.loop == ABLoop(start: 1, end: 3) && abs(player.currentTime - 1) < 0.01)
        player.cycleLoop()                                      // kapat
        #expect(player.loop == nil && player.loopStart == nil)
        player.close()
    }

    // MARK: - #21 durumlar, #8 kaynak, #13 rozet, #20 kelime, #30 canlı soru

    @Test func actionRowStatuses() {
        let open = ScriptIssue(index: 2, severity: "uydurma", reason: "", correction: nil)
        var fixed = open
        fixed.fixedAt = .now
        #expect(EpisodeActionStatus.verification([open, open, fixed], error: nil) == "2 uyarı")
        #expect(EpisodeActionStatus.verification([fixed], error: nil) == "Sorun yok")
        #expect(EpisodeActionStatus.verification(nil, error: nil) == nil)
        #expect(EpisodeActionStatus.verification(nil, error: "ağ") == "Doğrulanamadı")
        #expect(EpisodeActionStatus.feed(true) == "Akışta" && EpisodeActionStatus.feed(false) == nil)
        // #7: onay yalnız üretimdeki bölümde görünür (işlemler sayfası hazır bölümde açılır; durum ••• menüsünde).
        #expect(EpisodeActionStatus.approval(true, status: .generating) == "Onay bekliyor")
        #expect(EpisodeActionStatus.approval(false, status: .generating) == nil)
        #expect(EpisodeActionStatus.approval(true, status: .ready) == nil)
        #expect(EpisodeActionStatus.approval(true, status: .failed) == nil)
        #expect(EpisodeActionStatus.audio([AudioIssue(scene: 1, reasons: ["kesik"])]) == "Ses metinle uyuşmuyor")
        #expect(EpisodeActionStatus.audio([]) == nil)
        #expect(EpisodeActionStatus.wordSync(.ready) == "Hazır")
        #expect(EpisodeActionStatus.wordSync(.denied) == "Konuşma tanıma izni yok")
        // #20: elle hazırlık yalnız `.ready` olunca açık sayfaya kelime zamanlarını yeniden yükletir.
        #expect(EpisodeActionStatus.reloadsWordTimes(.ready))
        #expect(!EpisodeActionStatus.reloadsWordTimes(.denied) && !EpisodeActionStatus.reloadsWordTimes(nil))
        #expect(!EpisodeActionStatus.reloadsWordTimes(.failed("ağ")))
    }

    @Test func sourcePageOpensPDFOrImage() throws {
        let pdf = SourceDocRef(name: "Kitap", kind: "pdf", url: URL(fileURLWithPath: "/tmp/a.pdf"), pageCount: 20)
        let pdf2 = SourceDocRef(name: "Föy", kind: "pdf", url: URL(fileURLWithPath: "/tmp/b.pdf"), pageCount: 5)
        let img1 = SourceDocRef(name: "Foto 1", kind: "image", url: URL(fileURLWithPath: "/tmp/1.jpg"), pageCount: 1)
        let img2 = SourceDocRef(name: "Foto 2", kind: "image", url: URL(fileURLWithPath: "/tmp/2.jpg"), pageCount: 1)
        #expect(SourcePageResolution.resolve(page: 12, documents: [pdf, pdf2]) == .pdf(pdf.url, page: 12))
        #expect(SourcePageResolution.resolve(page: 3, documents: [pdf, pdf2]) == .choosePDF([pdf, pdf2], page: 3))
        #expect(SourcePageResolution.resolve(page: 2, documents: [img1, img2]) == .image(img2.url))
        #expect(SourcePageResolution.resolve(page: 9, documents: [img1, img2]) == .image(img1.url))
        #expect(SourcePageResolution.resolve(page: 30, documents: [pdf2, img1]) == .image(img1.url))   // PDF o sayfaya erişmiyor
        #expect(SourcePageResolution.resolve(page: 1, documents: []) == .missing)
    }

    @Test func audioIssueTurnsAndWordSpans() {
        let turn = { (t: String) in ScriptTurn(speaker: .a, text: t, style: "") }
        let script = PodcastScript(title: "T", summary: "", keyPoints: [], chapters: [
            ScriptChapter(title: "1", scenes: [ScriptScene(turns: [turn("a"), turn("b")]), ScriptScene(turns: [turn("c")])]),
            ScriptChapter(title: "2", scenes: [ScriptScene(turns: [turn("d"), turn("e")])]),
        ], sourceNotes: "")
        #expect(TranscriptView.audioIssueTurns([AudioIssue(scene: 2, reasons: [])], script: script) == [3: 2, 4: 2])
        #expect(TranscriptView.audioIssueTurns([], script: script).isEmpty)

        let timed = TimedTurn(id: 0, chapterIndex: 0, speaker: .a, text: "Hücre zarı seçici geçirgendir", start: 10, end: 13)
        #expect(FollowAlong.exactSpans(turn: timed, times: [10, 10.6, 11.2, 12]).first?.times == [10, 10.6, 11.2, 12])
        #expect(FollowAlong.exactSpans(turn: timed, times: [10, 11]).isEmpty)       // sayı tutmuyor: tahmin
        #expect(FollowAlong.exactSpans(turn: timed, times: nil).isEmpty)
        let timing = FollowAlong.Timing(text: timed.text, start: 10, end: 13, spans: FollowAlong.exactSpans(turn: timed, times: [10, 10.6, 11.2, 12]))
        #expect(timing.times == [10, 10.6, 11.2, 12])
        #expect(WordSyncRunner.shouldAutoPrepare(duration: 20 * 60, auto: true, hasTimes: false))
        #expect(!WordSyncRunner.shouldAutoPrepare(duration: 45 * 60, auto: true, hasTimes: false))      // uzun: düğmeyle
        #expect(!WordSyncRunner.shouldAutoPrepare(duration: 20 * 60, auto: false, hasTimes: false))
        #expect(!WordSyncRunner.shouldAutoPrepare(duration: 20 * 60, auto: true, hasTimes: true))
    }

    @Test func liveAskUsesViewedEpisodeAndLearn2Fields() throws {
        let c = try container()
        let context = c.mainContext
        let e = try episode("Hücre", seconds: 6, chapters: [0, 3], context: context)
        defer { cleanup(e) }
        let history = (0..<8).map { i in
            LiveExchange(episodeID: e.id, episodeTitle: "Hücre", question: "Soru \(i) " + String(repeating: "x", count: 600),
                         answer: "Cevap \(i)", chapterIndex: 0, time: nil, mode: "ask")
        }
        let old = LiveAskContext.request(episode: e, chapterIndex: 1, mode: "teach", history: history, learn2: false)
        #expect(old.chapterTitle == "Konu 2" && old.chapterText == "Konu 2 anlatımı burada")
        #expect(old.mode == nil && old.history == nil)         // eski sunucu aynı isteği görür
        let new = LiveAskContext.request(episode: e, chapterIndex: 1, mode: "teach", history: history, learn2: true)
        #expect(new.mode == "teach")
        #expect(new.history?.count == 6 && new.history?.first?.a == "Cevap 2" && new.history?.first?.q.count == 500)
        let json = String(decoding: try JSONEncoder().encode(old), as: UTF8.self)
        #expect(!json.contains("\"mode\"") && !json.contains("\"history\""))
    }

    /// #30 "Bana anlat": sunucuda dinleyici anlatır, model öğrencidir. İlk sözü yapay zekâ aldığından oturum açılınca tek bir
    /// açılış sözü gider; "Soru sor"da gitmez. Geçmişte kullanıcı balonu "Sen anlattın" olur.
    @Test func liveTeachModeSendsOpeningTurn() throws {
        #expect(LiveAskContext.openingTurn(mode: "ask") == nil)
        #expect(LiveAskContext.openingTurn(mode: nil) == nil)
        #expect(LiveAskContext.openingTurn(mode: "teach") == "Başla")
        #expect(LiveAskContext.userBubbleTitle(mode: "teach") == "Sen anlattın")
        #expect(LiveAskContext.userBubbleTitle(mode: "ask") == "Sen")
    }

    /// Sunucu (zod) UTF-16 birimi sayar: emojili uzun cevap sınırı aşmaz, grafem bölünmez.
    @Test func liveAskHistoryIsClippedByUTF16() throws {
        let emoji = String(repeating: "🧬", count: 1000)                // 1000 grafem, 2000 UTF-16
        let clipped = LiveAskContext.clip(emoji, utf16: 1500)
        #expect(clipped.utf16.count == 1500 && clipped.count == 750)
        let odd = "a" + emoji
        #expect(LiveAskContext.clip(odd, utf16: 1500).utf16.count == 1499)  // yarım vekil çift kalmaz
        #expect(LiveAskContext.clip("İğdır", utf16: 500) == "İğdır")
        let c = try container()
        let context = c.mainContext
        let e = try episode("Hücre", seconds: 6, chapters: [0, 3], context: context)
        defer { cleanup(e) }
        let history = [LiveExchange(episodeID: e.id, episodeTitle: "Hücre", question: String(repeating: "👩‍🔬", count: 400),
                                    answer: emoji, chapterIndex: 0, time: nil, mode: "ask")]
        let request = LiveAskContext.request(episode: e, chapterIndex: 0, mode: "ask", history: history, learn2: true)
        let qa = try #require(request.history?.first)
        #expect(qa.q.utf16.count <= 500 && qa.a.utf16.count <= 1500 && !qa.q.isEmpty)
    }

    // MARK: - İnceleme düzeltmeleri

    /// #17: kulaklık çıkınca (sistem durdurdu) sonraki arama bitince podcast kendiliğinden başlamaz.
    @Test func routeLossClearsResumeIntent() async throws {
        let c = try container()
        let context = c.mainContext
        let a = try episode("A", context: context)
        defer { cleanup(a) }
        let player = makePlayer()
        player.load(a, context: context, autoplay: true)
        #expect(player.isPlaying)
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil,
                                        userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        let began: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        let ended: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                                         AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue]
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: began)
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: ended)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!player.isPlaying)
        player.close()
    }

    /// #22/#17: soru beklenirken "oynat" sonraki kesite geçer (bölüm kesit dışına çalmaz); eski soru sonra
    /// cevaplanırsa ikinci kez ilerletmez. Kesit sonu duraklatması kesinti sonrası sürdürülmez.
    @Test func playWhileWaitingForQuestionMovesToNextClip() async throws {
        let c = try container()
        let context = c.mainContext
        let a = try episode("A", seconds: 6, context: context)
        defer { cleanup(a) }
        let player = makePlayer()
        let clips = [PodcastClip(episodeID: a.id, start: 0.5, end: 1.0, reason: "yanlış"),
                     PodcastClip(episodeID: a.id, start: 2, end: 2.5, reason: "anlamadım"),
                     PodcastClip(episodeID: a.id, start: 4, end: 4.5, reason: "anlamadım")]
        let gate = Gate()
        player.playClips(clips, context: context) { _ in
            while !gate.open { try? await Task.sleep(for: .milliseconds(10)) }
        }
        player.finished()                                       // 1. kesit bitti: soru bekleniyor
        #expect(!player.isPlaying && player.clipProgress?.index == 1)
        // Arama geldi ve bitti: kesit sonu duraklaması sürdürülmez.
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
                                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
                                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                                                   AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue])
        try await Task.sleep(for: .milliseconds(50))
        #expect(!player.isPlaying && player.clipProgress?.index == 1)
        player.play()                                           // kilit ekranından "oynat"
        #expect(player.clipProgress?.index == 2 && player.isPlaying && abs(player.currentTime - 2) < 0.01)
        gate.open = true                                        // eski soru geç cevaplandı
        try await Task.sleep(for: .milliseconds(100))
        #expect(player.clipProgress?.index == 2)
        player.endClipSession()
        player.close()
    }

    /// #16: kuyruk/seri geçişi gezinmeyi zorlamaz; yalnız olay yayılır (görünüm karar verir).
    @Test func queueAdvanceDoesNotForceNavigation() throws {
        let previous = AppState.current
        defer { AppState.current = previous }
        let app = AppState()
        let c = try container()
        let context = c.mainContext
        let series = UUID()
        let a = try episode("A", context: context, series: series, index: 1)
        let b = try episode("B", context: context, series: series, index: 2)
        defer { cleanup(a, b) }
        let player = makePlayer()
        player.load(a, context: context, autoplay: false)
        player.playNext()
        #expect(player.episode?.id == b.id)
        #expect(player.lastAdvance?.from == a.id && player.lastAdvance?.to == b.id)
        #expect(app.pendingOpenEpisode == nil)
        player.close()
    }

    /// #43: açılış tazelemesi yalnız değişen bölümleri yeniden dizinler; haftalık tam tazeleme.
    @Test func spotlightReindexesOnlyChangedEpisodes() throws {
        let c = try container()
        let context = c.mainContext
        let a = try episode("A", context: context)
        let b = try episode("B", context: context)
        defer { cleanup(a, b) }
        let suite = "p5.spotlight.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        let now = Date.now
        #expect(Set(SpotlightIndex.changedEpisodes([a, b], store: store, now: now).map(\.id)) == [a.id, b.id])
        #expect(SpotlightIndex.changedEpisodes([a, b], store: store, now: now).isEmpty)
        a.audioRevision += 1                                    // konu çıkarıldı / sahne düzenlendi
        #expect(SpotlightIndex.changedEpisodes([a, b], store: store, now: now).map(\.id) == [a.id])
        b.title = "B2"
        #expect(SpotlightIndex.changedEpisodes([a, b], store: store, now: now).map(\.id) == [b.id])
        let later = now.addingTimeInterval(SpotlightIndex.fullRefreshInterval + 1)
        #expect(SpotlightIndex.changedEpisodes([a, b], store: store, now: later).count == 2)
    }

    @Test func speakerColorsAndNames() {
        #expect(Theme.hostColor(.c) != Theme.hostColor(.a) && Theme.hostColor(.c) != Theme.hostColor(.b))
        var settings = PodcastSettings()
        settings.guest = Host(name: "Doç. Dr. İpek", voice: "Charon")
        #expect(settings.displayName(for: .c) == "Doç. Dr. İpek")
    }

    // MARK: - Dalga 2: uyku zamanlayıcısı, seri sırası

    /// Süreli zamanlayıcı ara ses içinde dolarsa (tik yalnız çalarken gelir) ara ses bitince podcast sürmez.
    @Test func sleepTimerExpiredDuringInterludeDoesNotResume() throws {
        let c = try container()
        let context = c.mainContext
        let a = try episode("A", seconds: 6, context: context)
        defer { cleanup(a) }
        let player = makePlayer()
        player.load(a, context: context, autoplay: true)
        #expect(player.beginInterlude())
        player.setSleepTimer(minutes: 0)                        // ara ses sürerken doldu
        player.endInterlude(resume: true)
        #expect(!player.isInInterlude && !player.isPlaying && player.sleepTimer == nil)
        player.play()                                           // kullanıcının kendi "oynat"ı çalar
        #expect(player.isPlaying)
        // Süresi dolmamış zamanlayıcı ara sesten sonra sürmeyi engellemez.
        #expect(player.beginInterlude())
        player.setSleepTimer(minutes: 5)
        player.endInterlude(resume: true)
        #expect(player.isPlaying && player.sleepTimer != nil)
        player.cancelSleepTimer()
        player.close()
    }

    /// Süreli zamanlayıcı kesinti (arama, alarm) sürerken dolarsa kesinti bitince çalma sürmez.
    @Test func sleepTimerExpiredDuringInterruptionDoesNotResume() async throws {
        let c = try container()
        let context = c.mainContext
        let a = try episode("A", context: context)
        defer { cleanup(a) }
        let player = makePlayer()
        player.load(a, context: context, autoplay: true)
        let began: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        let ended: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                                         AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue]
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: began)
        await waitUntil { !player.isPlaying }
        #expect(!player.isPlaying)
        player.setSleepTimer(minutes: 0)                        // kesinti sürerken doldu
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: ended)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!player.isPlaying && player.sleepTimer == nil)
        // Zamanlayıcı durdurdu: sonraki kesinti de kendiliğinden başlatmaz.
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: began)
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: ended)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!player.isPlaying)
        player.close()
    }

    /// Seri sırası boşlukluysa (1, 3: aradaki bölüm silinmiş ya da taşınmış) sıradaki bölüm yine bulunur.
    @Test func seriesAdvanceSkipsNumberingGap() throws {
        let c = try container()
        let context = c.mainContext
        let series = UUID()
        let a = try episode("A", context: context, series: series, index: 1)
        let third = try episode("C", context: context, series: series, index: 3)
        defer { cleanup(a, third) }
        let player = makePlayer()
        player.load(a, context: context, autoplay: false)
        #expect(player.nextUp()?.id == third.id)
        player.playNext()
        #expect(player.episode?.id == third.id)
        #expect(player.nextUp() == nil)                         // son bölüm
        player.close()
    }
}
