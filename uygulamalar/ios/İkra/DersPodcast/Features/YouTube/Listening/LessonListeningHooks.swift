import SwiftData
import SwiftUI

/// İzleme süresi kaydı (#33): ders, çalışma oturumu (`StudySession(kind: "video")`) ve günlük dinleme süresi.
enum WatchRecorder {
    /// ≥ 10 sn'lik parçayı kaydeder. Silinmiş ya da kayıtsız derse dokunulmaz.
    static func record(start: Date, seconds: Double, lesson: VideoLesson?) {
        guard let lesson, let context = lesson.modelContext, !lesson.isDeleted, seconds >= WatchAccumulator.minChunk else { return }
        lesson.watchedSeconds += seconds
        context.insert(StudySession(startedAt: start, seconds: seconds, courseID: lesson.courseID, episodeID: lesson.id,
                                    kind: "video", completed: true))
        let key = ListeningDay.key()
        let day = (try? context.fetch(FetchDescriptor<ListeningDay>(predicate: #Predicate { $0.day == key })).first) ?? {
            let new = ListeningDay(day: key)
            context.insert(new)
            return new
        }()
        day.seconds += seconds
        try? context.save()
    }

    /// Geri sarma anını dersin ısı haritasına ekler (kopyala-değiştir-ata).
    static func recordRewind(_ moment: Double, lesson: VideoLesson?) {
        guard let lesson, let context = lesson.modelContext, !lesson.isDeleted else { return }
        lesson.rewindTimes = RewindHeat.appending(moment, to: lesson.rewindTimes)
        try? context.save()
    }

    /// Ders başına hızı hatırlar.
    static func recordRate(_ rate: Double, lesson: VideoLesson?) {
        guard let lesson, let context = lesson.modelContext, !lesson.isDeleted,
              rate.isFinite, rate > 0, abs(lesson.playbackRate - rate) > 0.001 else { return }
        lesson.playbackRate = rate
        try? context.save()
    }
}

/// Ders ekranına dinleme özelliklerini bağlar: oynatıcı geri çağrıları (izleme süresi, geri sarma, hız), bölüm başlangıçları,
/// indirilen videoya geçiş ve Odakla izle (odak başlayınca ders çalar, molada durur).
struct LessonListeningHooks: ViewModifier {
    var lesson: VideoLesson
    var player: VideoPlayerModel
    var chapterStarts: [Double]
    var notify: (String) -> Void

    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content
            .onAppear(perform: wire)
            .onChange(of: chapterStarts, initial: true) { _, starts in player.chapterStarts = starts }
            .onChange(of: lesson.videoFileName) { _, _ in videoFileChanged() }
            .onChange(of: FocusTimer.shared.phase) { _, phase in focusPhaseChanged(phase) }
            .task { await watchFocusClock() }
    }

    private func wire() {
        // Kaydedilmiş hız: geri çağrı bağlanmadan uygulanır (aynı değeri geri yazmasın).
        if lesson.playbackRate > 0, abs(lesson.playbackRate - player.rate) > 0.001 { player.rate = lesson.playbackRate }
        let target = lesson
        player.onWatched = { [weak target] start, seconds in WatchRecorder.record(start: start, seconds: seconds, lesson: target) }
        player.onRewind = { [weak target] moment in WatchRecorder.recordRewind(moment, lesson: target) }
        player.onRateChange = { [weak target] rate in WatchRecorder.recordRate(rate, lesson: target) }
        #if DEBUG
        seedDemo()
        #endif
    }

    /// Video dosyası indirildi ya da silindi (çevrimdışı video ekranı): oynatıcı kaynağını değiştirir.
    private func videoFileChanged() {
        if lesson.videoFileName != nil, lesson.hasVideoFile, let url = lesson.videoURL {
            player.useVideo(file: url, autoplay: player.isPlaying)
        } else {
            player.videoRemoved()
        }
    }

    // MARK: - Odakla izle

    private var focusIsForThisLesson: Bool { FocusTimer.shared.isRunning && FocusTimer.shared.episodeID == lesson.id }

    private func focusPhaseChanged(_ phase: FocusTimer.Phase) {
        guard FocusTimer.shared.episodeID == lesson.id else { return }
        switch phase {
        case .focus: player.play()
        case .shortBreak, .longBreak: player.pause()
        case .idle: break
        }
    }

    /// Süre dolunca aşamayı kendiliğinden geçirir: odak biterse oturum kaydedilir ve mola başlar (ders durur);
    /// mola biterse yeni odak başlar (ders çalar).
    private func watchFocusClock() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            let timer = FocusTimer.shared
            guard focusIsForThisLesson, timer.remaining == 0 else { continue }
            let next = timer.nextPhase
            let wasFocus = timer.phase == .focus
            timer.finish(context: context, completed: true)
            timer.start(next)
            if wasFocus { notify("Odak bitti, mola zamanı") }
        }
    }

    #if DEBUG
    /// Yalnızca Debug, simülatörde ekran denemesi için (`-followDemo` ile birlikte):
    /// `-demoVideo` Documents/follow-demo/video.mp4'ü dersin indirilmiş videosu yapar, `-demoRewinds` ısı şeridi için geri sarma anları ekler,
    /// `-demoStudent` bazı altyazı satırlarını öğrenci konuşması işaretler, `-demoLoop` 20–35 sn döngü, `-demoSleep` 10 dk uyku kurar.
    private func seedDemo() {
        guard FollowDemo.isRequested else { return }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demoVideo"), !lesson.hasVideoFile {
            let source = URL.documentsDirectory.appending(path: "follow-demo/video.mp4")
            let target = VideoFiles.directory(for: lesson.id).appending(path: "video.mp4")
            if FileManager.default.fileExists(atPath: source.path) {
                try? FileManager.default.removeItem(at: target)
                if (try? FileManager.default.copyItem(at: source, to: target)) != nil {
                    lesson.videoFileName = "video.mp4"
                    try? context.save()
                }
            }
        }
        if args.contains("-demoRewinds") {
            lesson.rewindTimes = [30, 31, 32, 33, 34, 120, 121, 122, 400, 401, 640, 700, 701, 702, 703, 704, 705]
            try? context.save()
        }
        if args.contains("-demoStudent"), let count = lesson.transcript?.segments.count, count > 6 {
            // Altyazı satırı düzeyinde: ikinci ve yedinci satır öğrenci.
            SpeakerAnalysis.save(LessonSpeakers(count: count, student: [2, 6]), lesson: lesson.id)
        }
        if args.contains("-demoLoop") { player.setLoop(start: 20, end: 35, play: false) }
        if args.contains("-demoSleep") { player.setSleep(minutes: 10) }
    }
    #endif
}
