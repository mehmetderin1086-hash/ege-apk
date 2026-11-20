import Foundation
import YouTubeKit

/// Only public YouTube endpoints are contacted. No extraction server or remote fallback is used.
struct NativeYouTubeStream: Sendable {
    let url: URL
    let headers: [String: String]
    let fileExtension: String
    let codec: String
    let bitrate: Int
    let resolution: Int?
    let includesAudio: Bool

    var request: URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 120)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }
}

struct NativeYouTubeMedia: Sendable {
    let title: String
    let artist: String
    let audio: NativeYouTubeStream
    let video: NativeYouTubeStream?
    /// The selected source, not a promise to upscale or recover information absent from that source.
    let actualResolution: Int?
    let sourceHighestResolution: Int?
    let sourceAudioBitrate: Int

    var qualityNote: String? {
        guard let actualResolution, let sourceHighestResolution,
              sourceHighestResolution > actualResolution else { return nil }
        return "Bu iPhone ile uyumlu kaynak: \(actualResolution)p."
    }
}

/// YouTubeKit's player-script cache is process-wide. Serializing extraction avoids concurrent
/// mutations while transfers and media conversion remain free to run concurrently.
actor NativeYouTubeExtractor {
    static let shared = NativeYouTubeExtractor()
    private var previousExtraction: Task<Void, Never>?

    func extract(url: URL, format: DownloadFormat, quality: DownloadQuality) async throws -> NativeYouTubeMedia {
        let previous = previousExtraction
        let work = Task {
            if let previous { await previous.value }
            try Task.checkCancellation()
            // One quiet retry covers a dropped mobile connection during the player/script fetch.
            do {
                return try await Self.resolve(url: url, format: format, quality: quality, finalAttempt: false)
            } catch let error as URLError where NativeYouTubeDownloader.isTransient(error) {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                return try await Self.resolve(url: url, format: format, quality: quality, finalAttempt: true)
            }
        }
        previousExtraction = Task { _ = try? await work.value }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }

    private static func resolve(url: URL, format: DownloadFormat, quality: DownloadQuality, finalAttempt: Bool = true) async throws -> NativeYouTubeMedia {
        let canonical = try MediaURLPolicy.canonicalInput(url.absoluteString)
        guard MediaURLPolicy.isYouTube(canonical) else {
            throw RitimError.message("YouTube video bağlantısı bekleniyor.")
        }
        // Kepçe's bundled yt-dlp resolves the source on this device. Keep the
        // existing native resolver as a fallback when no compatible source exists.
        do {
            let media = try await Self.resolveWithKepce(url: canonical, format: format, quality: quality)
            try Task.checkCancellation()
            UserDefaults.standard.set("kepce", forKey: "ritim.lastYouTubeResolver")
            return media
        } catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            UserDefaults.standard.set("native-fallback", forKey: "ritim.lastYouTubeResolver")
        }
        do {
            let video = YouTube(url: canonical, methods: [.local])
            async let oembed = metadata(for: canonical)
            let streams = try await video.streams
            try Task.checkCancellation()
            guard let audio = streams
                .filter({ $0.includesAudioTrack && !$0.includesVideoTrack && $0.isNativelyPlayable && $0.fileExtension == .m4a })
                .max(by: { ($0.averageBitrate ?? $0.bitrate ?? 0) < ($1.averageBitrate ?? $1.bitrate ?? 0) }) else {
                throw RitimError.message("Bu videoda iPhone ile uyumlu indirilebilir ses bulunamadı.")
            }
            let limit = quality == .highest ? 2160 : 1080
            let selectedVideo: YouTubeKit.Stream?
            if format == .mp4 {
                selectedVideo = streams.filter {
                    $0.includesVideoTrack && $0.isNativelyPlayable && $0.fileExtension == .mp4
                        && ($0.videoResolution ?? Int.max) <= limit && isSDR($0.videoCodec)
                }.max {
                    if $0.videoResolution != $1.videoResolution {
                        return ($0.videoResolution ?? 0) < ($1.videoResolution ?? 0)
                    }
                    return ($0.averageBitrate ?? $0.bitrate ?? 0) < ($1.averageBitrate ?? $1.bitrate ?? 0)
                }
                guard selectedVideo != nil else {
                    throw RitimError.message("Bu videoda iPhone ile uyumlu indirilebilir MP4 bulunamadı.")
                }
            } else {
                selectedVideo = nil
            }
            let embed = await oembed
            let fallbackTitle = (try? await video.metadata)?.title
            try Task.checkCancellation()
            return NativeYouTubeMedia(
                title: embed?.title ?? fallbackTitle ?? "YouTube videosu",
                artist: embed?.authorName ?? "YouTube",
                audio: try descriptor(audio),
                video: try selectedVideo.map(descriptor),
                actualResolution: selectedVideo?.videoResolution,
                sourceHighestResolution: streams.compactMap(\.videoResolution).filter { $0 <= limit }.max(),
                sourceAudioBitrate: audio.averageBitrate ?? audio.bitrate ?? 0
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as RitimError {
            throw error
        } catch let error as YouTubeKitError {
            let message: String
            switch error {
            case .videoPrivate: message = "Bu video gizli; herkese açık bir bağlantı kullan."
            case .membersOnly: message = "Bu video yalnızca kanal üyelerine açık."
            case .videoAgeRestricted: message = "Bu video yaş doğrulaması gerektiriyor."
            case .videoRegionBlocked: message = "Bu video bulunduğun bölgede kullanılamıyor."
            case .videoUnavailable, .recordingUnavailable: message = "YouTube videosu kullanılamıyor veya kaldırılmış."
            case .liveStreamError: message = "Devam eden canlı yayınlar indirilemiyor."
            default: message = "YouTube bağlantısı iPhone’da çözümlenemedi. Biraz sonra yeniden dene."
            }
            throw RitimError.message(message)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if let network = error as? URLError, NativeYouTubeDownloader.isTransient(network) {
                if !finalAttempt { throw network }
                throw RitimError.message("İnternet bağlantısı zayıf; YouTube videosu hazırlanamadı. Bağlantını kontrol edip yeniden dene.")
            }
            throw RitimError.message("YouTube bağlantısı hazırlanamadı: \(error.localizedDescription)")
        }
    }

    static func resolveWithKepce(url: URL, format: DownloadFormat, quality: DownloadQuality) async throws -> NativeYouTubeMedia {
        // A stuck extractor must not occupy an active queue slot indefinitely.
        // Cancelling the caller does not interrupt an already-running Python
        // operation; its own serial queue remains responsible for that work.
        let info = try await withThrowingTaskGroup(of: MedyaBilgisi.self) { group in
            group.addTask { try await PythonMotoru.shared.coz(url.absoluteString) }
            group.addTask {
                try await Task.sleep(for: .seconds(20))
                throw RitimError.message("Kepçe motoru zamanında yanıt vermedi.")
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw RitimError.message("Medya bilgisi alınamadı.") }
            return result
        }
        try Task.checkCancellation()
        let formats = (info.formats ?? []).filter { $0.hasDRM != true && $0.dogrudan }
        func safe(_ item: Bicim) -> Bool {
            guard let text = item.url, let url = URL(string: text), url.scheme?.lowercased() == "https",
                  url.user == nil, url.password == nil, let host = url.host?.lowercased() else { return false }
            return host == "googlevideo.com" || host.hasSuffix(".googlevideo.com")
        }
        guard let audio = formats.filter({ safe($0) && $0.ext?.lowercased() == "m4a" && $0.sesVar && !$0.videoVar && $0.sesKodegi == "aac" })
            .max(by: { ($0.abr ?? 0) < ($1.abr ?? 0) }) else {
            throw RitimError.message("Uyumlu ses kaynağı bulunamadı.")
        }
        let limit = quality == .highest ? 2160 : 1080
        let videos = formats.filter { safe($0) && $0.ext?.lowercased() == "mp4" && $0.videoVar && $0.videoKodegi == "avc1" && ($0.height ?? Int.max) <= limit }
        let video = format == .mp4 ? videos.max { ($0.height ?? 0, $0.tbr ?? 0) < ($1.height ?? 0, $1.tbr ?? 0) } : nil
        if format == .mp4 && video == nil { throw RitimError.message("Uyumlu video kaynağı bulunamadı.") }
        func stream(_ item: Bicim, video: Bool) throws -> NativeYouTubeStream {
            guard let text = item.url, let url = URL(string: text) else { throw RitimError.message("Medya bağlantısı geçersiz.") }
            return NativeYouTubeStream(url: url, headers: item.httpHeaders ?? [:], fileExtension: video ? "mp4" : "m4a",
                                       codec: (video ? item.vcodec : item.acodec) ?? (video ? "avc1" : "mp4a"),
                                       bitrate: Int((video ? item.tbr : item.abr) ?? 0) * 1000,
                                       resolution: video ? item.height : nil, includesAudio: item.sesVar)
        }
        return NativeYouTubeMedia(title: info.title ?? "YouTube videosu", artist: info.yazar ?? "YouTube",
                                  audio: try stream(audio, video: false), video: try video.map { try stream($0, video: true) },
                                  actualResolution: video?.height, sourceHighestResolution: videos.compactMap(\.height).max(),
                                  sourceAudioBitrate: Int(audio.abr ?? 0) * 1000)
    }

    private static func descriptor(_ stream: YouTubeKit.Stream) throws -> NativeYouTubeStream {
        let host = stream.url.host?.lowercased() ?? ""
        guard stream.url.scheme?.lowercased() == "https",
              host == "googlevideo.com" || host.hasSuffix(".googlevideo.com"),
              stream.url.user == nil, stream.url.password == nil else {
            throw RitimError.message("YouTube güvenli bir medya bağlantısı döndürmedi.")
        }
        let codec: String
        if let video = stream.videoCodec {
            switch video {
            case .avc1(let version): codec = "avc1.\(version)"
            case .av1(let version): codec = "av01.\(version)"
            case .mp4v(let version): codec = "mp4v.\(version)"
            case .vp9(let version): codec = "vp09.\(version)"
            case .unknown(let value): codec = value
            }
        } else {
            switch stream.audioCodec {
            case .mp4a(let version): codec = "mp4a.\(version)"
            case .opus: codec = "opus"
            case .ec3: codec = "ec-3"
            case .ac3: codec = "ac-3"
            case .unknown(let value): codec = value
            case nil: codec = "unknown"
            }
        }
        return NativeYouTubeStream(url: stream.url, headers: [:], fileExtension: stream.fileExtension.rawValue,
                                   codec: codec, bitrate: stream.averageBitrate ?? stream.bitrate ?? 0,
                                   resolution: stream.videoResolution, includesAudio: stream.includesAudioTrack)
    }

    private static func isSDR(_ codec: VideoCodec?) -> Bool {
        switch codec {
        case .avc1, .mp4v: return true
        case .av1(let version): return version.split(separator: ".").last == "08"
        default: return false
        }
    }

    private struct OEmbed: Decodable {
        let title: String
        let authorName: String
        enum CodingKeys: String, CodingKey { case title; case authorName = "author_name" }
    }

    private static func metadata(for url: URL) async -> OEmbed? {
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString), URLQueryItem(name: "format", value: "json")]
        guard let endpoint = components.url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: endpoint, timeoutInterval: 15))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(OEmbed.self, from: data)
        } catch { return nil }
    }
}
