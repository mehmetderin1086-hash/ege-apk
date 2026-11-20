import AVFoundation
import SwiftUI

/// Ders videosu: slaytlar bölüm sesine göre zamanlanır, 1920×1080 H.264 + AAC MP4 olarak yazılır.
enum DeckVideo {
    /// Her slaydın başlangıç saniyesi. Bölüme bağlı slaytlar o bölümün süresine eşit dağıtılır;
    /// bölümsüz slaytlar başta (başlık/plan) ya da sonda (özet) kısa süre gösterilir, iki bölümlü slaydın arasında
    /// kalanlar komşularının arasına yerleşir. Sıra korunur, en az 3 sn.
    static func schedule(slides: [DeckSlide], chapters: [TimedChapter], duration: Double) -> [Double] {
        guard !slides.isEmpty, duration > 0 else { return [] }
        let sorted = chapters.sorted { $0.start < $1.start }
        func chapterRange(_ id: Int) -> (Double, Double)? {
            guard let i = sorted.firstIndex(where: { $0.id == id }) else { return nil }
            return (sorted[i].start, i + 1 < sorted.count ? sorted[i + 1].start : duration)
        }
        let groups = Dictionary(grouping: slides.indices.filter { slides[$0].chapterIndex != nil }) { slides[$0].chapterIndex! }
        var times = Array(repeating: Double.nan, count: slides.count)
        for (chapter, idx) in groups {
            guard let (a, b) = chapterRange(chapter) else { continue }
            let step = (b - a) / Double(idx.count)
            for (k, i) in idx.enumerated() { times[i] = a + Double(k) * step }
        }
        // Zamanı bölümden gelmeyen slaytlar (bölümsüz ya da bölümü zaman çizelgesinde yok). Aradakiler sona atılırsa
        // sıra koruma geçişi sonraki bütün bölümleri videonun son dakikasına iter; bu yüzden komşuların arasına konur.
        // Referans yalnız bölümden gelen zamanlardır: ara değerler ayrı diziye yazılır.
        let known = slides.indices.filter { !times[$0].isNaN }
        let lead = known.first ?? slides.count
        var filled = times
        for i in slides.indices where times[i].isNaN {
            if let p = known.last(where: { $0 < i }) {
                if let q = known.first(where: { $0 > i }) {
                    filled[i] = times[p] + (times[q] - times[p]) * Double(i - p) / Double(q - p)
                } else {
                    filled[i] = max(0, duration - Double(slides.count - i) * 12)
                }
            } else {
                filled[i] = Double(i) * min(8, (sorted.first?.start ?? 0) / Double(max(1, lead)))
            }
        }
        times = filled
        // Sıra korunsun, her slayt en az 3 sn görünsün, süreyi aşmasın.
        for i in slides.indices {
            if i > 0 { times[i] = max(times[i], times[i - 1] + 3) }
            times[i] = min(times[i], max(0, duration - Double(slides.count - i) * 0.5))
        }
        times[0] = 0
        return times
    }

    @MainActor
    static func frame(_ slide: DeckSlide, deck: Deck, index: Int, image: UIImage?, figure: SourceFigure?, chapterTitle: String?) -> CGImage? {
        let view = SlideCanvas(slide: slide, deck: deck, index: index, image: image, figure: figure, chapterTitle: chapterTitle).content
            .frame(width: SlideCanvas.size.width, height: SlideCanvas.size.height)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(SlideCanvas.size)
        renderer.scale = 1.5   // 1280×720 → 1920×1080
        return renderer.cgImage
    }

    /// Kullanıcıya gösterilen dışa aktarma hataları (sistem metni "dosya yok" yerine ne yapılacağını söyler).
    nonisolated enum ExportError: LocalizedError, Equatable {
        case noAudio, noSlides
        var errorDescription: String? {
            switch self {
            case .noAudio: "Bu bölümün sesi bulunamadı; video için önce ses hazır olmalı."
            case .noSlides: "Destede slayt yok."
            }
        }
    }

    /// Sayfada gösterilecek hata metni: bilinen durumlar kendi cümlesiyle, diğerleri sistem açıklamasıyla.
    nonisolated static func failureMessage(_ error: Error) -> String {
        (error as? ExportError)?.errorDescription ?? "Video oluşturulamadı: \(error.localizedDescription)"
    }

    @MainActor
    static func export(episode: Episode, deck: Deck, progress: @escaping (Double) -> Void) async throws -> URL {
        guard !deck.slides.isEmpty else { throw ExportError.noSlides }
        guard let audioURL = episode.audioURL, FileManager.default.fileExists(atPath: audioURL.path),
              let timeline = episode.timeline else { throw ExportError.noAudio }
        // Modelden gereken her şey baştan alınır: dışa aktarma sürerken bölüm silinirse modele bir daha dokunulmaz.
        let figures = episode.sourceFigures
        let directory = episode.directory
        let language = episode.settings?.language.rawValue ?? "tr"
        let audio = AVURLAsset(url: audioURL)
        let duration = try await audio.load(.duration).seconds
        let times = schedule(slides: deck.slides, chapters: timeline.chapters, duration: duration)

        let silent = URL.temporaryDirectory.appending(path: "video-\(UUID().uuidString).mp4")
        // Sessiz ara dosya her çıkışta (başarı, hata, iptal) silinir.
        defer { try? FileManager.default.removeItem(at: silent) }
        let writer = try AVAssetWriter(outputURL: silent, fileType: .mp4)
        let size = CGSize(width: 1920, height: 1080)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_000_000],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)

        do {
            var lastBuffer: CVPixelBuffer?
            for (index, slide) in deck.slides.enumerated() {
                try Task.checkCancellation()
                let imageURL = DeckAssets.imageURL(for: slide, index: index, directory: directory, figures: figures)
                let image = imageURL.flatMap { UIImage(contentsOfFile: $0.path) }
                guard let cg = frame(slide, deck: deck, index: index, image: image, figure: figures.first { $0.id == slide.figureId },
                                     chapterTitle: DeckAssets.chapterTitle(for: slide, chapters: timeline.chapters, language: language)),
                      let buffer = pixelBuffer(cg, size: size, pool: adaptor.pixelBufferPool) else { continue }
                while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
                adaptor.append(buffer, withPresentationTime: CMTime(seconds: times[safe: index] ?? 0, preferredTimescale: 600))
                lastBuffer = buffer
                progress(Double(index + 1) / Double(deck.slides.count) * 0.7)
            }
            // Son kare videonun sonuna kadar kalsın.
            if let lastBuffer {
                while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
                adaptor.append(lastBuffer, withPresentationTime: CMTime(seconds: max(0, duration - 0.05), preferredTimescale: 600))
            }
            try Task.checkCancellation()
        } catch {
            writer.cancelWriting()   // yarım yazım bırakılır (iptal ya da hata)
            throw error
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }

        // Ses + görüntü birleştir.
        let composition = AVMutableComposition()
        let video = AVURLAsset(url: silent)
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600))
        if let v = try await video.loadTracks(withMediaType: .video).first,
           let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let vDuration = try await video.load(.duration)
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: min(vDuration, range.duration)), of: v, at: .zero)
        }
        if let a = try await audio.loadTracks(withMediaType: .audio).first,
           let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try track.insertTimeRange(range, of: a, at: .zero)
        }
        let name = String(deck.title.map { "/\\:?%*|\"<>".contains($0) ? "-" : $0 }.prefix(60))
        let output = URL.temporaryDirectory.appending(path: "\(name).mp4")
        try? FileManager.default.removeItem(at: output)
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else { throw CocoaError(.fileWriteUnknown) }
        progress(0.85)
        try await session.export(to: output, as: .mp4)
        progress(1)
        return output
    }

    private static func pixelBuffer(_ image: CGImage, size: CGSize, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        if let pool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) }
        if buffer == nil {
            CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, nil, &buffer)
        }
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}

struct DeckVideoSheet: View {
    @Environment(\.dismiss) private var dismiss
    var episode: Episode
    @State private var progress = 0.0
    @State private var phase = Phase.working
    /// "Yeniden dene" sayacı: değişince `.task(id:)` işi yeniden başlatır (sayfa kapanınca kendiliğinden iptal olur).
    @State private var attempt = 0

    private enum Phase { case working, done(URL), failed(String) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if episode.deck == nil {
                    ContentUnavailableView("Önce slayt destesi oluştur", systemImage: "rectangle.stack",
                                           description: Text("Video, destedeki slaytlar ve bölümün sesiyle hazırlanır."))
                } else {
                    switch phase {
                    case .done(let url):
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
                        Text("Video hazır").font(.headline)
                        ShareLink(item: url) { Label("Paylaş / Kaydet", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent)
                    case .failed(let message):
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 44)).foregroundStyle(.orange)
                        Text(message).font(.subheadline).multilineTextAlignment(.center)
                        Button("Yeniden dene", systemImage: "arrow.clockwise") { attempt += 1 }.buttonStyle(.borderedProminent)
                    case .working:
                        ProgressView(value: progress) { Text(progress < 0.7 ? "Slaytlar çiziliyor…" : "Ses ekleniyor…") }
                        Text("1920×1080 · slaytlar konuya göre sesle eşlenir").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("Ders videosu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
            // Yapılandırılmış iş: sayfa "Kapat" ile de aşağı çekilerek de kapansa kare çizimi durur.
            .task(id: attempt) { await run() }
        }
    }

    private func run() async {
        guard let deck = episode.deck else { return }
        if case .done = phase { return }   // paylaşım sayfasından dönüşte yeniden üretme
        phase = .working
        progress = 0
        do {
            phase = .done(try await DeckVideo.export(episode: episode, deck: deck) { progress = $0 })
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            phase = .failed(DeckVideo.failureMessage(error))
        }
    }
}
