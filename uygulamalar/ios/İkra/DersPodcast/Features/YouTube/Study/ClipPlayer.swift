import AVFoundation
import SwiftData
import SwiftUI

/// Sesli kart (#21, #31): kartın bağlı olduğu ders sesi kesitini çalar. Ses dosyası yerelden okunur.
@MainActor
@Observable
final class ClipPlayer {
    enum State: Equatable {
        case idle
        case playing
        case unavailable(String)
    }

    private(set) var state: State = .idle
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var watcher: Task<Void, Never>?

    var isPlaying: Bool { state == .playing }

    /// Kartın kesitini çalar; çalıyorsa durdurur. Ders sesi yoksa nedenini `state`e yazar.
    func toggle(card: ReviewCard, context: ModelContext) {
        if isPlaying {
            stop()
            return
        }
        guard let lessonID = card.clipLessonID else { return }
        var descriptor = FetchDescriptor<VideoLesson>(predicate: #Predicate { $0.id == lessonID })
        descriptor.fetchLimit = 1
        guard let lesson = try? context.fetch(descriptor).first, lesson.modelContext != nil else {
            state = .unavailable("Bu kartın dersi silinmiş.")
            return
        }
        guard lesson.hasAudioFile, let url = lesson.audioURL else {
            state = .unavailable("Dersin sesi indirilmemiş. Ders ekranında “Sesi uygulamada dinle” ile indirebilirsin.")
            return
        }
        play(url: url, start: card.clipStart, end: card.clipEnd)
    }

    func play(url: URL, start: Double, end: Double) {
        stop()
        guard end > start else {
            state = .unavailable("Kesit aralığı geçersiz.")
            return
        }
        AppState.current?.player.pause()
        // Oturum zaten .playback ise dokunulmaz (ana oynatıcının uzun biçimli ses politikası ezilmesin).
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback { try? session.setCategory(.playback, mode: .spokenAudio) }
        try? session.setActive(true)

        let item = AVPlayerItem(url: url)
        item.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
        let player = AVPlayer(playerItem: item)
        self.player = player
        state = .playing
        let target = CMTime(seconds: start, preferredTimescale: 600)
        watcher = Task { [weak self] in
            // Önce kesitin başına git, sonra çal; bitişi yoklayarak izle (geri çağrı kuyruğu gerekmez).
            _ = await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            guard !Task.isCancelled else { return }
            player.play()
            let deadline = Date.now.addingTimeInterval(end - start + 8)
            var started = false
            var failed = false
            while !Task.isCancelled, Date.now < deadline {
                try? await Task.sleep(for: .milliseconds(250))
                if item.status == .failed || player.error != nil {
                    failed = true
                    break
                }
                let current = player.currentTime().seconds
                if current > start + 0.2 { started = true }
                if current >= end - 0.1 { break }
            }
            guard !Task.isCancelled else { return }
            // Hiç ilerlemediyse ya da öğe bozuksa dosya çalınamadı sayılır.
            self?.finish(failed: failed || !started)
        }
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
        player?.pause()
        player = nil
        if state == .playing { state = .idle }
    }

    private func finish(failed: Bool) {
        player?.pause()
        player = nil
        watcher = nil
        guard state == .playing else { return }
        state = failed ? .unavailable("Ses dosyası çalınamadı; sesi yeniden indir.") : .idle
    }
}

/// Tekrar ekranında kartın arka yüzünde "Dinle": ders sesinden o kesiti çalar.
struct ClipListenButton: View {
    var card: ReviewCard
    @Environment(\.modelContext) private var context
    @State private var clip = ClipPlayer()

    var body: some View {
        if card.clipLessonID != nil {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    clip.toggle(card: card, context: context)
                } label: {
                    Label(clip.isPlaying ? "Durdur" : "Öğretmenden dinle (\(Int(max(1, card.clipEnd - card.clipStart))) sn)",
                          systemImage: clip.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                .buttonStyle(.bordered)
                if case .unavailable(let message) = clip.state {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            .onDisappear { clip.stop() }
            .onChange(of: card.id) { clip.stop() }
        }
    }
}
