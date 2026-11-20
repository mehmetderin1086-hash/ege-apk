import Foundation
import AVFoundation

protocol NativeDownloadProviding: Sendable {
    func download(entry: DownloadEntry, directory: URL,
                  metadata: @escaping @MainActor @Sendable (NativeYouTubeMedia) -> Void,
                  progress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> URL
}

struct NativeYouTubeDownloader: NativeDownloadProviding {
    var transferMetrics: (@MainActor @Sendable (Int64, Int64) -> Void)?
    static let fileLimit: Int64 = 512 * 1_024 * 1_024

    // Only completely downloaded, size-checked sources get a checkpoint.
    // It deliberately contains no expiring stream URL or request headers.
    struct Checkpoint: Codable, Equatable {
        let source: String
        let format: DownloadFormat
        let quality: DownloadQuality
        let codec: String
        let bitrate: Int
        let resolution: Int?
        let fileExtension: String
        let size: Int64
    }

    static func checkpointURL(_ directory: URL, kind: String) -> URL {
        directory.appendingPathComponent("\(kind).checkpoint.json")
    }

    static func checkpointFile(_ directory: URL, kind: String) -> URL {
        directory.appendingPathComponent(kind == "audio" ? "audio.m4a" : "video.mp4")
    }

    static func checkpointMatches(_ directory: URL, kind: String, entry: DownloadEntry, stream: NativeYouTubeStream) -> Bool {
        guard let data = try? Data(contentsOf: checkpointURL(directory, kind: kind)),
              let saved = try? JSONDecoder().decode(Checkpoint.self, from: data),
              let size = try? checkpointFile(directory, kind: kind).resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, Int64(size) <= fileLimit else { return false }
        return saved == Checkpoint(source: entry.sourceURL, format: entry.format, quality: entry.effectiveQuality,
                                   codec: stream.codec, bitrate: stream.bitrate, resolution: stream.resolution,
                                   fileExtension: stream.fileExtension, size: Int64(size))
    }

    static func verifiedCheckpoint(_ directory: URL, kind: String, entry: DownloadEntry) -> URL? {
        guard let data = try? Data(contentsOf: checkpointURL(directory, kind: kind)),
              let saved = try? JSONDecoder().decode(Checkpoint.self, from: data),
              saved.source == entry.sourceURL, saved.format == entry.format, saved.quality == entry.effectiveQuality,
              saved.fileExtension == (kind == "audio" ? "m4a" : "mp4"),
              let size = try? checkpointFile(directory, kind: kind).resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, Int64(size) == saved.size, Int64(size) <= fileLimit else { return nil }
        return checkpointFile(directory, kind: kind)
    }

    static func saveCheckpoint(_ directory: URL, kind: String, entry: DownloadEntry, stream: NativeYouTubeStream, downloaded: URL) throws -> URL {
        let file = checkpointFile(directory, kind: kind)
        let marker = checkpointURL(directory, kind: kind)
        let size = Int64(try downloaded.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard size > 0, size <= fileLimit else { throw RitimError.message("İndirilen dosya doğrulanamadı.") }
        try? FileManager.default.removeItem(at: marker)
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: downloaded, to: file)
        let record = Checkpoint(source: entry.sourceURL, format: entry.format, quality: entry.effectiveQuality,
                                codec: stream.codec, bitrate: stream.bitrate, resolution: stream.resolution,
                                fileExtension: stream.fileExtension, size: size)
        try JSONEncoder().encode(record).write(to: marker, options: .atomic)
        return file
    }

    func download(entry: DownloadEntry, directory: URL,
                  metadata: @escaping @MainActor @Sendable (NativeYouTubeMedia) -> Void,
                  progress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> URL {
        guard let url = URL(string: entry.sourceURL) else { throw RitimError.message("YouTube bağlantısı geçersiz.") }
        let media = try await NativeYouTubeExtractor.shared.extract(url: url, format: entry.format, quality: entry.effectiveQuality)
        try Task.checkCancellation()
        await metadata(media)
        #if DEBUG
        // Give device UI automation time to background a real resolved source.
        if ProcessInfo.processInfo.environment["RITIM_UI_TEST_HANDOFF"] == "1" {
            try await Task.sleep(for: .seconds(20))
        }
        #endif
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // This directory belongs only to this queued entry; never touch the media library.
        let scratch = directory.appendingPathComponent("checkpoint", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        // Stream URLs expire and LTE drops connections; a stale URL is re-extracted and the transfer resumes at its offset.
        let reextract = { try await NativeYouTubeExtractor.shared.extract(url: url, format: entry.format, quality: entry.effectiveQuality) }
        let audio: URL
        if Self.checkpointMatches(scratch, kind: "audio", entry: entry, stream: media.audio) {
            audio = Self.checkpointFile(scratch, kind: "audio")
            await progress(media.video == nil ? 0.75 : 0.25)
        } else {
            let temporary = scratch.appendingPathComponent("audio-\(UUID().uuidString).m4a")
            defer { try? FileManager.default.removeItem(at: temporary) }
            let downloaded = try await transfer(media.audio, to: temporary,
                                       refresh: { try await reextract().audio }, metrics: transferMetrics) { value in
                await progress(0.05 + value * (media.video == nil ? 0.70 : 0.20))
            }
            audio = try Self.saveCheckpoint(scratch, kind: "audio", entry: entry, stream: media.audio, downloaded: downloaded)
        }
        var video: URL?
        if let source = media.video {
            if Self.checkpointMatches(scratch, kind: "video", entry: entry, stream: source) {
                video = Self.checkpointFile(scratch, kind: "video")
                await progress(0.75)
            } else {
                let temporary = scratch.appendingPathComponent("video-\(UUID().uuidString).mp4")
                defer { try? FileManager.default.removeItem(at: temporary) }
                let downloaded = try await transfer(source, to: temporary,
                                       refresh: {
                guard let fresh = try await reextract().video, fresh.resolution == source.resolution, fresh.codec == source.codec else {
                    throw RitimError.message("YouTube video kaynağı aktarım sırasında değişti. Yeniden dene.")
                }
                return fresh
            }, metrics: transferMetrics) { value in
                await progress(0.25 + value * 0.50)
            }
                video = try Self.saveCheckpoint(scratch, kind: "video", entry: entry, stream: source, downloaded: downloaded)
            }
        }
        try Task.checkCancellation()
        let result = try await NativeMediaConverter.convert(audio: audio, video: video, format: entry.format,
                                                             quality: entry.effectiveQuality, outputDirectory: directory) { value in
            Task { @MainActor in progress(0.75 + value * 0.23) }
        }
        do {
            try Task.checkCancellation()
            let size = try result.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= Self.fileLimit else {
                throw RitimError.message("Hazırlanan dosya 512 MB sınırını aşıyor. Daha kısa bir video veya Standart kalite seç.")
            }
            if entry.format == .mp4, let track = try await AVURLAsset(url: result).loadTracks(withMediaType: .video).first {
                let naturalSize = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let actualHeight = Int(abs(naturalSize.applying(transform).height).rounded())
                // YouTube's format tier can say 360p for an original 240p upload.
                // Show the actual encoded output dimensions, never the tier label.
                await metadata(NativeYouTubeMedia(title: media.title, artist: media.artist, audio: media.audio, video: media.video,
                                                 actualResolution: actualHeight,
                                                 sourceHighestResolution: media.qualityNote == nil ? actualHeight : media.sourceHighestResolution,
                                                 sourceAudioBitrate: media.sourceAudioBitrate))
            }
            try Task.checkCancellation()
            return result
        } catch {
            try? FileManager.default.removeItem(at: result)
            throw error
        }
    }

    /// Holds the current stream URL so several in-flight ranges share one refresh after an expiry.
    private actor SourceBox {
        private(set) var stream: NativeYouTubeStream
        private var generation = 0
        private var refreshes = 0
        private var refreshTask: Task<NativeYouTubeStream, Error>?
        init(_ stream: NativeYouTubeStream) { self.stream = stream }
        func current() -> (NativeYouTubeStream, Int) { (stream, generation) }
        /// False when the refresh budget is spent; true when a fresh URL is (already) in place.
        func refresh(seen: Int, using refresh: @escaping @Sendable () async throws -> NativeYouTubeStream) async throws -> Bool {
            if generation != seen { return true }
            if let refreshTask {
                let fresh = try await refreshTask.value
                if generation == seen { stream = fresh; generation += 1 }
                return true
            }
            guard refreshes < 2 else { return false }
            refreshes += 1
            let task = Task { try await refresh() }
            refreshTask = task
            do {
                let fresh = try await task.value
                if generation == seen { stream = fresh; generation += 1 }
                refreshTask = nil
                return true
            } catch {
                refreshTask = nil
                throw error
            }
        }
    }

    /// One verified byte range, retried on transient network errors; an expired URL (403/410) is refreshed.
    private func fetchRange(_ offset: Int64, _ end: Int64, source: SourceBox, session: URLSession,
                            refresh: (@Sendable () async throws -> NativeYouTubeStream)?,
                            retryDelay: @Sendable (Int) async throws -> Void) async throws -> (URL, HTTPURLResponse) {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            let (stream, generation) = await source.current()
            var request = stream.request
            request.setValue("bytes=\(offset)-\(end)", forHTTPHeaderField: "Range")
            let status: Int
            do {
                let (temporary, response) = try await session.download(for: request, delegate: NativeTransferGuard(limit: Self.fileLimit))
                guard let http = response as? HTTPURLResponse else {
                    try? FileManager.default.removeItem(at: temporary)
                    throw RitimError.message("YouTube medya yanıtı okunamadı.")
                }
                status = http.statusCode
                if status == 206 || status == 200 { return (temporary, http) }
                try? FileManager.default.removeItem(at: temporary)
            } catch let error as URLError where Self.isTransient(error) && attempt < Self.maxAttempts - 1 {
                if Task.isCancelled { throw CancellationError() }
                try await retryDelay(attempt); attempt += 1
                continue
            } catch let error as URLError where error.code == .cancelled {
                throw Task.isCancelled ? CancellationError() : RitimError.message("Aktarım durdu veya 512 MB sınırı aşıldı. Yeniden dene.")
            } catch let error as URLError where Self.isTransient(error) {
                throw RitimError.message("İnternet bağlantısı kesildi; YouTube aktarımı \(Self.maxAttempts) denemede tamamlanamadı. Bağlantını kontrol edip yeniden dene.")
            }
            if [403, 410].contains(status), let refresh, try await source.refresh(seen: generation, using: refresh) {
                continue
            } else if (status == 429 || (500..<600).contains(status)) && attempt < Self.maxAttempts - 1 {
                try await retryDelay(attempt); attempt += 1
            } else {
                throw RitimError.message("YouTube aktarımı tamamlanamadı (HTTP \(status)). Bağlantıyı yenilemek için yeniden dene.")
            }
        }
    }

    /// The first range reveals the size; the rest then download side by side (`parallel` ranges at a time)
    /// and are written at their own offsets, which is several times faster than one range after another.
    func transfer(_ initial: NativeYouTubeStream, to destination: URL,
                  refresh: (@Sendable () async throws -> NativeYouTubeStream)? = nil,
                  chunkSize: Int64 = 4 * 1_024 * 1_024, parallel: Int = 4,
                  initialChunkSize: Int64 = 256 * 1_024,
                  retryDelay: @escaping @Sendable (Int) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64(1 << $0) * 700_000_000) },
                  protocolClasses: [AnyClass]? = nil,
                  metrics: (@MainActor @Sendable (Int64, Int64) -> Void)? = nil,
                  progress: @escaping @Sendable (Double) async -> Void) async throws -> URL {
        let configuration = URLSessionConfiguration.ephemeral
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 7_200
        configuration.httpMaximumConnectionsPerHost = max(4, parallel + 1)
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw RitimError.message("İndirme dosyası oluşturulamadı.") }
        let file = try FileHandle(forWritingTo: destination)
        defer { try? file.close() }
        let source = SourceBox(initial)

        func write(_ temporary: URL, at offset: Int64) throws -> Int64 {
            defer { try? FileManager.default.removeItem(at: temporary) }
            let input = try FileHandle(forReadingFrom: temporary)
            defer { try? input.close() }
            try file.seek(toOffset: UInt64(offset))
            var written: Int64 = 0
            while let bytes = try input.read(upToCount: 256 * 1_024), !bytes.isEmpty {
                try Task.checkCancellation()
                try file.write(contentsOf: bytes)
                written += Int64(bytes.count)
            }
            return written
        }
        let mismatch = RitimError.message("Video boyutu veya aktarım aralığı doğrulanamadı; 512 MB sınırını kontrol et.")

        // First range: learns the total size.
        let firstEnd = max(1, min(initialChunkSize, chunkSize, Self.fileLimit)) - 1
        let (firstFile, firstResponse) = try await fetchRange(0, firstEnd, source: source, session: session, refresh: refresh, retryDelay: retryDelay)
        let firstSize = Int64(try firstFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        let total: Int64
        if firstResponse.statusCode == 206 {
            guard let range = Self.contentRange(firstResponse.value(forHTTPHeaderField: "Content-Range")),
                  range.start == 0, range.end <= firstEnd, range.end + 1 == firstSize,
                  range.total > range.end, range.total <= Self.fileLimit else {
                try? FileManager.default.removeItem(at: firstFile)
                throw mismatch
            }
            total = range.total
        } else if firstSize > 0, firstSize <= Self.fileLimit {
            total = firstSize
        } else {
            try? FileManager.default.removeItem(at: firstFile)
            throw RitimError.message("YouTube aktarımı tamamlanamadı (HTTP \(firstResponse.statusCode)). Bağlantıyı yenilemek için yeniden dene.")
        }
        var done = try write(firstFile, at: 0)
        await metrics?(done, total)
        await progress(Double(done) / Double(max(1, total)))
        guard done < total else { try file.synchronize(); return destination }

        var ranges: [(Int64, Int64)] = []
        var start = done
        while start < total { ranges.append((start, min(start + chunkSize, total) - 1)); start += chunkSize }
        try await withThrowingTaskGroup(of: (Int64, Int64, URL, HTTPURLResponse).self) { group in
            var next = 0
            func launch() {
                guard next < ranges.count else { return }
                let (from, to) = ranges[next]; next += 1
                group.addTask { [self] in
                    let (temporary, response) = try await fetchRange(from, to, source: source, session: session, refresh: refresh, retryDelay: retryDelay)
                    return (from, to, temporary, response)
                }
            }
            for _ in 0..<max(1, min(parallel, ranges.count)) { launch() }
            while let (from, to, temporary, response) = try await group.next() {
                let size = Int64(try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                guard response.statusCode == 206,
                      let range = Self.contentRange(response.value(forHTTPHeaderField: "Content-Range")),
                      range.start == from, range.end == to, size == to - from + 1, range.total == total else {
                    try? FileManager.default.removeItem(at: temporary)
                    throw mismatch
                }
                done += try write(temporary, at: from)
                await metrics?(done, total)
                await progress(Double(done) / Double(max(1, total)))
                launch()
            }
        }
        try file.synchronize()
        return destination
    }

    static let maxAttempts = 4

    static func isTransient(_ error: URLError) -> Bool {
        [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
         .dnsLookupFailed, .secureConnectionFailed, .resourceUnavailable, .internationalRoamingOff,
         .callIsActive, .dataNotAllowed, .backgroundSessionWasDisconnected].contains(error.code)
    }

    static func contentRange(_ value: String?) -> (start: Int64, end: Int64, total: Int64)? {
        guard let value, value.range(of: #"^bytes [0-9]+-[0-9]+/[0-9]+$"#, options: .regularExpression) != nil else { return nil }
        let fields = value.dropFirst(6).split(whereSeparator: { $0 == "-" || $0 == "/" })
        guard fields.count == 3, let start = Int64(fields[0]), let end = Int64(fields[1]), let total = Int64(fields[2]), start >= 0, end >= start, total > end else { return nil }
        return (start, end, total)
    }
}

private final class NativeTransferGuard: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let limit: Int64
    init(limit: Int64) { self.limit = limit }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) { }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > limit || totalBytesExpectedToWrite > limit { downloadTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let host = request.url?.host?.lowercased() ?? ""
        completionHandler(request.url?.scheme == "https" && (host == "googlevideo.com" || host.hasSuffix(".googlevideo.com")) ? request : nil)
    }
}
