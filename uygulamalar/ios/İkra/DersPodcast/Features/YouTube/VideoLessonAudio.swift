import SwiftData
import SwiftUI
import UIKit

// MARK: - Ses indirme

/// Dersin sesini sunucudan (POST /v1/youtube/audio) indirip ders klasörüne yazar.
/// Sunucu sesi YouTube'dan alırken hiç bayt gelmez ("hazırlanıyor"); yanıt akınca bayt ilerlemesi gösterilir.
@Observable
final class LessonAudioDownload {
    enum Phase: Equatable {
        case idle
        /// Sunucu sesi YouTube'dan alıyor (henüz bayt yok).
        case preparing(since: Date)
        /// Yanıt akıyor: oran (bilinmiyorsa nil) ve alınan bayt.
        case receiving(fraction: Double?, received: Int64)
        case saving
        case failed(String)
    }

    /// Sunucu sınırı: en fazla 3 saatlik video (aksi 413).
    static let maxDuration: Double = 3 * 3600

    private(set) var phase: Phase = .idle
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Her start'ta artar; eski (iptal edilmiş) görevin temizliği yenisinin ayarlarını bozmasın diye.
    @ObservationIgnored private var generation = 0

    var isRunning: Bool {
        switch phase {
        case .preparing, .receiving, .saving: true
        case .idle, .failed: false
        }
    }

    /// İndirir, `audioFileName`'i kaydeder ve dosya yolunu verir. Ders bu sırada silinirse dosya da silinir.
    func start(lesson: VideoLesson, context: ModelContext, completion: @escaping (URL) -> Void) {
        guard !isRunning else { return }
        // await'ler boyunca ders silinebilir: gerekenler önceden yerele alınır, sonra ders kimlikle yeniden çekilir.
        let lessonID = lesson.id
        let url = YouTubeLink.watchURL(videoID: lesson.videoID)?.absoluteString ?? lesson.url
        let progress = TransferProgress()
        phase = .preparing(since: .now)
        // Sıradan (arka plan olmayan) istek uygulama askıya alınınca kopar: indirme sürerken ekran kilitlenmesin,
        // uygulama yine de arka plana geçerse iOS'tan kısa ek süre istenir.
        UIApplication.shared.isIdleTimerDisabled = true
        let background = BackgroundTaskToken()
        background.id = UIApplication.shared.beginBackgroundTask(withName: "Ders sesi indirme") { background.end() }
        generation += 1
        let current = generation
        task = Task { [weak self] in
            let monitor = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(300))
                    self?.observe(progress)
                }
            }
            defer {
                monitor.cancel()
                background.end()
                // İptalden sonra yeni indirme başladıysa ekran kilidi ayarı onundur.
                if self == nil || self?.generation == current { UIApplication.shared.isIdleTimerDisabled = false }
            }
            let audio: YouTubeAudio
            do {
                audio = try await APIClient.shared.youtubeAudio(url: url, progress: progress)
                try Task.checkCancellation()
            } catch is CancellationError {
                return
            } catch {
                self?.phase = .failed(Self.failureMessage(error))
                return
            }
            self?.phase = .saving
            do {
                let name = try await VideoFiles.saveAudio(audio.data, lesson: lessonID)
                guard let live = VideoLessonView.liveLesson(id: lessonID, in: context) else {
                    VideoFiles.remove(lesson: lessonID)
                    self?.phase = .idle
                    return
                }
                live.audioFileName = name
                try? context.save()
                guard !Task.isCancelled else { return }
                self?.phase = .idle
                completion(VideoFiles.audioURL(lesson: lessonID, name: name))
            } catch {
                self?.phase = .failed("Ses kaydedilemedi: \(error.localizedDescription)")
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if isRunning { phase = .idle }
    }

    /// İndirme hatasının kullanıcı metni. Bağlantı koptuysa (çoğunlukla uygulama arka plana geçip askıya alındı)
    /// sunucu indirmeyi sürdürüp sonucu 10 dk önbellekte tutar: yeniden denemenin hızlı döneceği söylenir.
    nonisolated static func failureMessage(_ error: Error) -> String {
        guard let api = error as? APIError else { return error.localizedDescription }
        guard api.code == "network" else { return api.message }
        return "\(api.message) Uygulama arka plana geçince indirme kesilebilir; sunucu sesi hazırladıysa “Tekrar dene” hızlı sürer."
    }

    private func observe(_ progress: TransferProgress) {
        switch phase {
        case .preparing, .receiving: break
        default: return
        }
        let bytes = progress.bytes
        guard bytes.received > 0 else { return }
        let fraction = bytes.expected > 0 ? min(1, Double(bytes.received) / Double(bytes.expected)) : nil
        phase = .receiving(fraction: fraction, received: bytes.received)
    }

    #if DEBUG
    /// Ekran denetimi (`-offerAudioDemo=failed`): kartın en uzun hata metnini sunucusuz gösterir.
    func debugFail() {
        phase = .failed(Self.failureMessage(APIError(status: 0, code: "network", message: "Sunucuya ulaşılamadı.")))
    }
    #endif
}

// MARK: - Ses tercihi

/// Gömülebilir derste "Sesi uygulamada dinle" seçildiyse ders sonraki açılışlarda da sesle başlar (kilit ekranı, çevrimdışı,
/// zayıf bağlantıda web oynatıcının zaman aşımı beklenmez). Model alanı eklemeden, cihazda ders kimlikleri olarak tutulur.
nonisolated enum LessonAudioPreference {
    static let key = "lesson.prefersAudio"

    static func get(_ id: UUID, defaults: UserDefaults = .standard) -> Bool {
        (defaults.stringArray(forKey: key) ?? []).contains(id.uuidString)
    }

    static func set(_ id: UUID, _ value: Bool, defaults: UserDefaults = .standard) {
        var ids = defaults.stringArray(forKey: key) ?? []
        guard ids.contains(id.uuidString) != value else { return }
        if value { ids.append(id.uuidString) } else { ids.removeAll { $0 == id.uuidString } }
        defaults.set(ids, forKey: key)
    }
}

#if DEBUG
/// Yalnızca Debug: `-offerAudioDemo` dersi gömülemez ve sessiz/videosuz sayar ("Sesi uygulamada dinle" kartı dar ekranda
/// denetlenir); `-offerAudioDemo=failed` kartı indirme hatasıyla açar.
enum OfferAudioDemo {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains { $0 == "-offerAudioDemo" || $0.hasPrefix("-offerAudioDemo=") }
    }
    static var failed: Bool { DebugArg.value("offerAudioDemo") == "failed" }
}
#endif

// MARK: - "Sesi uygulamada dinle" kartı

/// Gömme yasak ya da web oynatıcı açılamadı: sesi indirip uygulamada dinleme önerisi; indirme ilerlemesi, hata ve iptal.
struct LessonAudioCard: View {
    var message: String
    var download: LessonAudioDownload
    var duration: Double
    /// Gömülebilir derste videoya dönüş / yeniden deneme düğmesinin adı; nil = gösterme.
    var videoButtonTitle: String?
    var onListen: () -> Void
    var onOpenYouTube: () -> Void
    var onVideo: () -> Void

    private var tooLong: Bool { duration > LessonAudioDownload.maxDuration }

    var body: some View {
        VStack(spacing: 8) {
            switch download.phase {
            case .idle, .failed:
                offer
            case .preparing(let since):
                ProgressView().tint(.white)
                Text("Ses sunucuda hazırlanıyor…").font(.callout.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                // Sayaç ve açıklama alt alta: 320 pt'de tek satıra zorlanınca %70'e küçülüp kesiliyordu.
                VStack(spacing: 2) {
                    Text(since, style: .timer).monospacedDigit()
                    Text("Uzun derslerde birkaç dakika sürebilir.")
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                cancelButton
            case .receiving(let fraction, let received):
                if let fraction {
                    ProgressView(value: fraction).tint(.white).frame(maxWidth: 240)
                } else {
                    ProgressView().tint(.white)
                }
                Text(Self.receivingText(fraction: fraction, received: received))
                    .font(.callout.weight(.semibold).monospacedDigit())
                cancelButton
            case .saving:
                ProgressView().tint(.white)
                Text("Kaydediliyor…").font(.callout.weight(.semibold))
            }
        }
        .foregroundStyle(.white)
        .padding()
        // Yükseklik içeriğe göre: kart 16:9 kutuya sıkıştırılmaz (çağıran üst sınırı uygular, sığmazsa kaydırır).
        .frame(maxWidth: .infinity, minHeight: Self.minHeight)
        .background(Color.black)
    }

    nonisolated static let minHeight: CGFloat = 150

    /// Oynatıcı alanında kartın yüksekliği: içerik kadar; ölçülene dek en az yükseklik, üst sınırı aşarsa sınır (kart kaydırılır).
    nonisolated static func fittedHeight(content: CGFloat, limit: CGFloat) -> CGFloat {
        min(max(content, minHeight), max(limit, minHeight))
    }

    @ViewBuilder
    private var offer: some View {
        Image(systemName: "headphones").font(.title2)
        // Metinler kesilmez ve küçültülmez: uzun ağ hatası da tam okunur, kart gerektiği kadar uzar.
        Text(message)
            .font(.callout)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        if case .failed(let error) = download.phase {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else if tooLong {
            Text("Ses indirme en fazla 3 saatlik videolarda kullanılabilir.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { buttons }
            VStack(spacing: 6) { buttons }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var buttons: some View {
        Button(download.phase == .idle ? "Sesi uygulamada dinle" : "Tekrar dene",
               systemImage: download.phase == .idle ? "headphones" : "arrow.clockwise", action: onListen)
            .buttonStyle(.borderedProminent)
            .disabled(tooLong)
        Button("YouTube’da aç", systemImage: "arrow.up.right.square", action: onOpenYouTube)
            .buttonStyle(.bordered)
            .tint(.white)
        if let videoButtonTitle {
            Button(videoButtonTitle, systemImage: "play.rectangle", action: onVideo)
                .buttonStyle(.bordered)
                .tint(.white)
        }
    }

    private var cancelButton: some View {
        Button("İptal", systemImage: "xmark", role: .cancel) { download.cancel() }
            .buttonStyle(.bordered)
            .tint(.white)
            .controlSize(.small)
    }

    static func receivingText(fraction: Double?, received: Int64) -> String {
        let size = ByteCountFormatter.string(fromByteCount: received, countStyle: .file)
        guard let fraction else { return "İndiriliyor · \(size)" }
        return "İndiriliyor %\(Int((fraction * 100).rounded(.down))) · \(size)"
    }
}

// MARK: - Ses kipi görseli

/// Ses kipinde oynatıcı alanı: o anki tahta/slayt karesi (yoksa küçük resim), "Ses" rozeti, oynat düğmesi, hata hâli.
struct LessonAudioArtwork: View {
    var player: VideoPlayerModel
    var lessonID: UUID
    /// Zamana göre sıralı kareler.
    var frames: [Keyframe]
    var thumbnailURL: URL?
    var onRedownload: () -> Void
    var onOpenYouTube: () -> Void

    @State private var image: UIImage?
    /// Görüntülenen karenin kimliği: kare değişince eski kare solarak yenisine geçer (kare akışı).
    @State private var shownID: String?

    var body: some View {
        let frameID = Self.frameID(at: player.currentTime, in: frames)
        ZStack {
            Color.black
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .id(shownID)
                    .transition(.opacity)
            } else {
                AsyncImage(url: thumbnailURL) { picture in
                    picture.resizable().scaledToFill().opacity(0.5)
                } placeholder: {
                    Image(systemName: "headphones").font(.largeTitle).foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            if case .failed(let message) = player.status {
                failure(message)
            } else if player.status == .loading {
                ProgressView().tint(.white)
            } else if !player.isPlaying {
                Button { player.play() } label: {
                    Image(systemName: "play.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .accessibilityLabel("Oynat")
            }
        }
        .overlay(alignment: .bottomLeading) {
            Label("Ses · çevrimdışı", systemImage: "headphones")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(8)
        }
        .clipped()
        .task(id: frameID) {
            guard let frameID else {
                withAnimation(.easeInOut(duration: 0.4)) { image = nil; shownID = nil }
                return
            }
            let loaded = await LessonFiles.thumbnail(VideoFiles.keyframeURL(lesson: lessonID, frame: frameID), maxPixel: 1280)
            // Yüklenen kare hazır olunca yumuşak geçiş (yükleme sırasında önceki kare ekranda kalır).
            if !Task.isCancelled { withAnimation(.easeInOut(duration: 0.6)) { image = loaded; shownID = frameID } }
        }
    }

    private func failure(_ message: String) -> some View {
        // 16:9 kutu 320 pt'de 180 pt: düğmeler alt alta inince sığsın diye boşluklar dar, ileti en çok iki satır.
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.title2)
            Text(message).font(.callout).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
            // İki kenarlıklı düğme 288 pt'ye yan yana sığmıyordu (yazılar kesiliyordu): sığmazsa alt alta.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { failureButtons }
                VStack(spacing: 6) { failureButtons }
            }
            .controlSize(.small)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.85))
    }

    @ViewBuilder
    private var failureButtons: some View {
        Button("Sesi yeniden indir", systemImage: "arrow.down.circle", action: onRedownload)
            .buttonStyle(.borderedProminent)
        Button("YouTube’da aç", systemImage: "arrow.up.right.square", action: onOpenYouTube)
            .buttonStyle(.bordered)
            .tint(.white)
    }

    /// O ana kadar gösterilmiş son kare (sıralı dizide); ilk kareden önce nil.
    nonisolated static func frameID(at time: Double, in frames: [Keyframe]) -> String? {
        frames.last { $0.time <= time + 0.5 }?.id
    }
}
