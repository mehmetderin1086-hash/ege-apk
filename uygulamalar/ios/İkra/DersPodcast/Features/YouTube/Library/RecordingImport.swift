import AVFoundation
import UniformTypeIdentifiers

// #4: Sınıf kaydı (ses/video dosyası) → gerekirse cihazda AAC 48 kbps mono → PUT /v1/upload/{id} → start(uploadId).

/// Dosyalar'dan seçilen URL'nin güvenlik kapsamı: açılışta başlar, `release()` ile tam bir kez kapanır (kopyalar paylaşır).
nonisolated final class SecurityScope: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var active: Bool

    init(url: URL) {
        self.url = url
        active = url.startAccessingSecurityScopedResource()
    }

    func release() {
        let wasActive = lock.withLock { () -> Bool in
            defer { active = false }
            return active
        }
        if wasActive { url.stopAccessingSecurityScopedResource() }
    }

    deinit { release() }
}

/// Seçilen kayıt dosyası (Dosyalar'dan / Ses Kaydı'ndan). Dosya yerinde okunur; güvenlik kapsamı iş bitene, iptal edilene ya da
/// hata alınana dek açık tutulur (`release()` her çıkış yolunda çağrılır).
struct RecordingDraft: Identifiable {
    let id: String
    let url: URL
    let name: String
    let bytes: Int64
    let isVideo: Bool
    var title: String
    /// Saniye; okunamadıysa 0.
    var duration: Double = 0
    private let scope: SecurityScope

    init?(url: URL) {
        let scope = SecurityScope(url: url)
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 0 else {
            scope.release()
            return nil
        }
        self.id = UUID().uuidString.lowercased()
        self.url = url
        self.name = url.lastPathComponent
        self.bytes = Int64(size)
        self.isVideo = RecordingPlan.isVideo(fileExtension: url.pathExtension)
        self.title = RecordingPlan.displayTitle(fileName: url.lastPathComponent)
        self.scope = scope
    }

    func release() { scope.release() }

    var plan: RecordingPlan.Plan { RecordingPlan.plan(bytes: bytes, fileExtension: url.pathExtension, isVideo: isVideo) }

    /// Yükleme sınırını aşıyor mu (dönüştürme sonrası tahmin dahil).
    var tooLarge: Bool {
        let plan = plan
        if plan.uploadVideo { return !RecordingPlan.fitsUpload(bytes) }
        if !plan.convertToAAC { return !RecordingPlan.fitsUpload(bytes) }
        // Dönüştürülecek: çıktı tahmini sınırı aşıyor mu (süre biliniyorsa).
        return duration > 0 && !RecordingPlan.fitsUpload(RecordingPlan.estimatedAACBytes(duration: duration))
    }
}

/// Cihazda hazırlanan dersin sesi, sunucu işi bitip ders kaydedilene kadar burada bekler (uygulama kapanırsa da yaşar).
nonisolated enum UploadStash {
    /// Klasör iCloud yedeğine girmez (içindeki ses işin sonunda ders klasörüne taşınır ya da silinir).
    static var directory: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "PendingUploads", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        VideoFiles.excludeFromBackup(dir)
        return dir
    }

    /// İş hiç başlamadı, iptal edildi ya da hata verdi: geçici ses silinir.
    static func remove(uploadID: String) {
        try? FileManager.default.removeItem(at: audioURL(uploadID: uploadID))
    }

    static func audioURL(uploadID: String) -> URL {
        directory.appending(path: "\(VideoFiles.safeName(uploadID)).m4a")
    }

    /// Bekleyen sesi dersin klasörüne taşır; dosya adını döndürür (yoksa nil).
    static func adopt(uploadID: String, into lesson: UUID) -> String? {
        let source = audioURL(uploadID: uploadID)
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        let destination = VideoFiles.audioURL(lesson: lesson)
        _ = VideoFiles.directory(for: lesson)
        try? FileManager.default.removeItem(at: destination)
        guard (try? FileManager.default.moveItem(at: source, to: destination)) != nil else { return nil }
        VideoFiles.excludeFromBackup(destination)
        return VideoFiles.audioFileName
    }

    /// 7 günden eski artıkları temizler (iş hiç tamamlanmamışsa).
    static func prune(olderThan days: Double = 7) {
        let limit = Date.now.addingTimeInterval(-days * 86_400)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture
            if date < limit { try? FileManager.default.removeItem(at: file) }
        }
    }
}

nonisolated enum AudioConverter {
    /// Ses kanalını AAC-LC 48 kbps mono m4a'ya dönüştürür (konuşma için yeterli; ~6 KB/sn). Video dosyalarından yalnız ses alınır.
    @concurrent
    static func convertToAAC(source: URL, destination: URL, progress: @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: source)
        let track: AVAssetTrack?
        do {
            track = try await asset.loadTracks(withMediaType: .audio).first
        } catch {
            throw APIError(status: 0, code: "unreadable", message: "Bu dosya biçimi okunamadı. m4a, mp3, wav, mp4 ya da mov dosyası seç.")
        }
        guard let track else {
            throw APIError(status: 0, code: "no_audio", message: "Dosyada ses kanalı bulunamadı.")
        }
        let duration = (try? await asset.load(.duration).seconds) ?? 0

        try? FileManager.default.removeItem(at: destination)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .m4a)
        func aacSettings(_ rate: Double) -> [String: Any] {
            [AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 1, AVSampleRateKey: rate, AVEncoderBitRateKey: 48_000]
        }
        let rate: Double = writer.canApply(outputSettings: aacSettings(32_000), forMediaType: .audio) ? 32_000 : 44_100
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: rate,
        ])
        guard reader.canAdd(output) else { throw APIError(status: 0, code: "reader", message: "Ses dosyası okunamadı.") }
        reader.add(output)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings(rate))
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw APIError(status: 0, code: "writer", message: "Ses dönüştürülemedi.") }
        writer.add(input)
        guard reader.startReading(), writer.startWriting() else {
            throw reader.error ?? writer.error ?? APIError(status: 0, code: "convert", message: "Ses dönüştürme başlatılamadı.")
        }
        writer.startSession(atSourceTime: .zero)

        func abort() {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destination)
        }
        while reader.status == .reading {
            if Task.isCancelled { abort(); throw CancellationError() }
            guard input.isReadyForMoreMediaData else {
                try await Task.sleep(for: .milliseconds(5))
                continue
            }
            guard let buffer = output.copyNextSampleBuffer() else { break }
            if duration > 0 { progress(min(1, CMSampleBufferGetPresentationTimeStamp(buffer).seconds / duration)) }
            if !input.append(buffer) { break }
        }
        if reader.status == .failed {
            let error = reader.error
            abort()
            throw error ?? APIError(status: 0, code: "convert", message: "Ses dönüştürülemedi.")
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            let error = writer.error
            abort()
            throw error ?? APIError(status: 0, code: "convert", message: "Ses dönüştürülemedi.")
        }
        progress(1)
    }

    /// Dosyanın süresi (sn); okunamazsa 0.
    @concurrent
    static func duration(of url: URL) async -> Double {
        let seconds = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
        return seconds.isFinite ? max(0, seconds) : 0
    }
}

/// Kaydı sunucuya hazırlar: gerekirse dönüştürür, yükler ve `start` isteğini döndürür.
nonisolated enum RecordingUploader {
    struct Options: Sendable {
        var translate: Bool
        var keyframes: Bool
        var notes: Bool
    }

    /// İlerleme (0...1, adım metni) aşamalara bölünür: dönüştürme %0–45, yükleme %45–100.
    @concurrent
    static func prepare(source: URL, id: String, title: String, isVideo: Bool, plan: RecordingPlan.Plan, options: Options,
                        progress onProgress: @escaping @MainActor @Sendable (Double, String) -> Void) async throws -> YouTubeStartRequest {
        let progress: @Sendable (Double, String) -> Void = { value, step in Task { @MainActor in onProgress(value, step) } }
        let stash = UploadStash.audioURL(uploadID: id)
        // 1) Dersin çevrimdışı sesi: dönüştür ya da (küçük m4a) olduğu gibi kopyala.
        if plan.convertToAAC {
            progress(0, "Ses dönüştürülüyor (AAC 48 kbps mono)")
            try await AudioConverter.convertToAAC(source: source, destination: stash) { progress($0 * 0.45, "Ses dönüştürülüyor (AAC 48 kbps mono)") }
        } else {
            try? FileManager.default.removeItem(at: stash)
            try FileManager.default.copyItem(at: source, to: stash)
        }
        VideoFiles.excludeFromBackup(stash)
        try Task.checkCancellation()

        // 2) Yüklenecek dosya: video (kareler için) ya da hazırlanan ses.
        let uploadFile = plan.uploadVideo ? source : stash
        let size = (try? FileManager.default.attributesOfItem(atPath: uploadFile.path)[.size] as? Int64) ?? 0
        guard RecordingPlan.fitsUpload(size) else {
            throw APIError(status: 413, code: "too_large", message: "Dosya sunucunun 500 MB sınırını aşıyor.")
        }
        let type = plan.uploadVideo
            ? (UTType(filenameExtension: source.pathExtension)?.preferredMIMEType ?? "video/mp4")
            : "audio/mp4"
        let monitor = TransferMonitor()
        let poll = Task {
            while !Task.isCancelled {
                progress(0.45 + monitor.uploadFraction * 0.55, "Sunucuya yükleniyor")
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        defer { poll.cancel() }
        progress(0.45, "Sunucuya yükleniyor")
        _ = try await APIClient.shared.uploadRecording(file: uploadFile, id: id, contentType: type, monitor: monitor)
        progress(1, "Yüklendi")

        return YouTubeStartRequest(url: "", mode: .ai, language: nil, translateTo: options.translate ? "tr" : nil,
                                   start: nil, end: nil, keyframes: isVideo && plan.uploadVideo && options.keyframes, notes: options.notes,
                                   uploadId: id, title: title)
    }
}
