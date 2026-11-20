import Foundation
import Speech
import SwiftData

/// Dinleme tarafının uygulama açılışı kancaları: Siri/Denetim Merkezi işleyicisi (#19), Spotlight (#43),
/// ses değişince oynatıcıyı tazeleme. Uygulama intent ile arka planda açılmış olabilir: SwiftUI ortamına dayanmaz.
enum ListeningHooks {
    static func install() {
        PlaybackCommandCenter.handler = { command in
            perform(command, player: AppState.current?.player, context: AppDataStore.container.mainContext)
        }
        PodcastEvent.observe(PodcastEvent.episodeReady) { info in
            guard let id = info.episodeID else { return }
            SpotlightIndex.index(episodeID: id, context: AppDataStore.container.mainContext)
        }
        PodcastEvent.observe(PodcastEvent.episodeDeleted) { info in
            guard let id = info.episodeID else { return }
            SpotlightIndex.remove(episodeID: id)
            AppState.current?.player.removeFromQueue(episodeID: id)
        }
        PodcastEvent.observe(PodcastEvent.audioChanged) { info in
            guard let id = info.episodeID else { return }
            AppState.current?.player.reloadIfLoaded(id)
            // Konu başlangıçları kaydı/konu çıktı: Spotlight'taki konu öğeleri yenilenir.
            SpotlightIndex.index(episodeID: id, context: AppDataStore.container.mainContext)
        }
        // Açılışı yavaşlatmadan Spotlight dizinini tazele.
        Task(priority: .background) { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            SpotlightIndex.reindex(context: AppDataStore.container.mainContext)
        }
    }

    static let nothingPlaying = "Şu an çalan bir podcast yok."

    /// #19 komut eşlemesi. Döner: Siri'nin söyleyeceği kısa cevap.
    static func perform(_ command: PlaybackCommand, player: PlayerController?, context: ModelContext) -> String {
        guard let player else { return "Ders Podcast’i açıp yeniden dene." }
        switch command {
        case .bookmark:
            guard let mark = player.addBookmark(kind: "siri") else { return nothingPlaying }
            return "İşaretlendi: \(mark.time.clockText)."
        case .back15:
            guard player.isActive else { return nothingPlaying }
            player.skip(-15)
            return "15 saniye geri alındı."
        case .nextChapter:
            guard player.episode != nil else { return nothingPlaying }
            let before = player.episode?.id
            let chapter = player.currentChapterIndex
            guard player.nextChapter() else { return "Bu son konu." }
            if player.episode?.id == before, player.currentChapterIndex != chapter,
               let title = player.timeline?.chapters[safe: player.currentChapterIndex]?.title {
                return "Sonraki konu: \(title)."
            }
            return "Sıradaki bölüme geçildi."
        case .resume:
            if player.isActive {
                if !player.isPlaying { player.play() }
                return "\(player.episode?.title ?? player.audioItem?.title ?? "Podcast") çalıyor."
            }
            guard let latest = latestEpisode(context: context) else { return "Dinlenecek bölüm bulunamadı." }
            player.load(latest, context: context, autoplay: true)
            return player.episode?.id == latest.id ? "\(latest.title) kaldığı yerden çalıyor." : "Bölümün sesi bulunamadı."
        }
    }

    /// En son dinlenen (yoksa en yeni) hazır bölüm.
    static func latestEpisode(context: ModelContext) -> Episode? {
        let ready = EpisodeStatus.ready.rawValue
        let episodes = (try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.statusRaw == ready }))) ?? []
        return episodes.max { ($0.lastPlayedAt ?? $0.createdAt) < ($1.lastPlayedAt ?? $1.createdAt) }
    }
}

/// #20: kelime senkronunu yalnız ön planda ve bölüm başına bir kez hazırlar.
enum WordSyncRunner {
    static let autoKey = "wordSync.auto"
    /// Bundan uzun bölümlerde otomatik değil, düğmeyle.
    static let autoLimit: Double = 30 * 60
    private(set) static var running = Set<UUID>()

    static var isAuto: Bool { UserDefaults.standard.object(forKey: autoKey) as? Bool ?? true }

    static func shouldAutoPrepare(duration: Double, auto: Bool, hasTimes: Bool) -> Bool {
        auto && !hasTimes && duration > 0 && duration <= autoLimit
    }

    /// Konuşma tanıma izni yalnız kullanıcı istediğinde sorulur (`askPermission`; Bölüm işlemleri → kelime senkronu).
    /// Otomatik hazırlık izin verilmemişse sessizce atlanır: bölüm açılır açılmaz açıklamasız sistem penceresi çıkmasın.
    static func prepare(_ episode: Episode, askPermission: Bool = true) async -> WordSyncOutcome? {
        guard !running.contains(episode.id), let url = episode.audioURL,
              let timeline = episode.timeline, let script = episode.script else { return nil }
        guard askPermission || SFSpeechRecognizer.authorizationStatus() == .authorized else { return nil }
        guard await WordSync.isSupported else { return .unsupported("Bu cihazda Türkçe kelime senkronu desteklenmiyor; tahmini takip sürüyor.") }
        let status = await SpeechRecorder.speechAuthorization()
        guard status == .authorized else { return .denied }
        running.insert(episode.id)
        defer { running.remove(episode.id) }
        return await WordSync.prepare(episodeID: episode.id, audioURL: url, timeline: timeline, script: script,
                                      language: episode.settings?.language)
    }
}
