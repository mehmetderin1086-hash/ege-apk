import Foundation
import SwiftData

/// YouTube Ders Stüdyosu'nda işlenmiş bir video: zaman damgalı transkript, notlar, kareler.
/// Kareler (JPEG) ve indirilen ses (audio.m4a) Application Support/Videos/<id>/ altında; transcriptData'daki image alanları boştur.
@Model
final class VideoLesson {
    var id: UUID = UUID()
    var url: String = ""
    var videoID: String = ""
    var title: String = ""
    var channel: String = ""
    var duration: Double = 0
    var thumbnailURL: String? = nil
    var language: String = ""
    var source: String = ""
    var createdAt: Date = Date.now
    var lastPosition: Double = 0
    var transcriptData: Data? = nil
    var episodeIDs: [UUID] = []
    var favorite: Bool = false
    /// Gömülü oynatmaya izin var mı; yoksa ders ekranı web oynatıcı yerine sesi önerir.
    var embeddable: Bool = true
    /// Uygulama içi dinleme için indirilen ses ("audio.m4a", ders klasöründe); nil = indirilmedi.
    var audioFileName: String? = nil
    /// Çevrimdışı izleme için indirilen video ("video.mp4", ders klasöründe); nil = indirilmedi.
    var videoFileName: String? = nil
    /// Bağlı ders (Derslerim); Koç görevleri ve istatistikler bu dersle eşlenir.
    var courseID: UUID? = nil
    /// Konu etiketleri (ilk öğe ders/alan adı).
    var tags: [String] = []
    /// Geri sarılan anlar (sn): zorlanılan yerlerin ısı haritası.
    var rewindTimes: [Double] = []
    /// Bu ders için hatırlanan oynatma hızı (0 = ayarlanmadı).
    var playbackRate: Double = 0
    /// Toplam izleme/dinleme süresi (sn).
    var watchedSeconds: Double = 0

    init(url: String = "", info: VideoInfo? = nil) {
        self.url = url
        if let info { apply(info: info) }
    }

    /// Transkript (kareler görselsiz). Atanırken görseller her zaman boşaltılır.
    var transcript: VideoTranscript? {
        get { transcriptData.flatMap { try? JSONDecoder().decode(VideoTranscript.self, from: $0) } }
        set { transcriptData = newValue.flatMap { try? JSONEncoder().encode($0.withoutImages) } }
    }

    /// Video bilgisini kayda yansıtır (başlık, kanal, süre, küçük resim).
    func apply(info: VideoInfo) {
        videoID = info.id
        if url.isEmpty { url = info.url }
        title = info.title
        channel = info.channel
        duration = info.duration
        if let value = info.embeddable { embeddable = value }
        thumbnailURL = info.thumbnail ?? YouTubeLink.thumbnailURL(videoID: info.id)?.absoluteString
        if let lang = info.language, language.isEmpty { language = lang }
    }

    /// Sunucu sonucunu kayda yansıtır; kareler önceden `VideoFiles.saveKeyframes` ile yazılmış olmalı.
    func apply(transcript: VideoTranscript) {
        apply(info: transcript.video)
        language = transcript.language
        source = transcript.source
        self.transcript = transcript
    }

    var sourceTitle: String { VideoTranscript.sourceTitle(source) }
    var directory: URL { VideoFiles.directory(for: id) }
    func keyframeURL(_ frameID: String) -> URL { VideoFiles.keyframeURL(lesson: id, frame: frameID) }
    func removeFiles() { VideoFiles.remove(lesson: id) }

    /// İndirilmiş sesin yolu (dosya var mı denetlenmez; klasör oluşturmaz).
    var audioURL: URL? { audioFileName.map { VideoFiles.audioURL(lesson: id, name: $0) } }
    /// Ses indirildi ve dosya yerinde.
    var hasAudioFile: Bool { audioURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
    /// İndirilmiş videonun yolu (dosya var mı denetlenmez).
    var videoURL: URL? { videoFileName.map { VideoFiles.directory(for: id).appending(path: $0) } }
    /// Video indirildi ve dosya yerinde.
    var hasVideoFile: Bool { videoURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
}

// MARK: - Dosyalar

nonisolated enum VideoFiles {
    static var root: URL {
        let base = URL.applicationSupportDirectory.appending(path: "Videos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func directory(for id: UUID) -> URL {
        let dir = root.appending(path: id.uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// "frame_<id>.jpg"; kimlik dosya adına güvenli karakterlere indirgenir.
    static func keyframeURL(lesson id: UUID, frame frameID: String) -> URL {
        directory(for: id).appending(path: "frame_\(safeName(frameID)).jpg")
    }

    static func safeName(_ raw: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let cleaned = String(raw.map { allowed.contains($0) ? $0 : "_" }.prefix(64))
        return cleaned.isEmpty ? "frame" : cleaned
    }

    static func remove(lesson id: UUID) {
        try? FileManager.default.removeItem(at: root.appending(path: id.uuidString))
    }

    static let audioFileName = "audio.m4a"

    /// Ses dosyasının yolu; yan etkisiz (klasör oluşturmaz), satır çizimlerinde de çağrılabilir.
    static func audioURL(lesson id: UUID, name: String = audioFileName) -> URL {
        URL.applicationSupportDirectory.appending(path: "Videos", directoryHint: .isDirectory)
            .appending(path: id.uuidString, directoryHint: .isDirectory)
            .appending(path: safeAudioName(name))
    }

    /// Kayıtlı ad yalnızca dosya adı olabilir (yol parçası taşımaz).
    static func safeAudioName(_ name: String) -> String {
        let last = (name as NSString).lastPathComponent
        return last.isEmpty || last == "." || last == ".." ? audioFileName : last
    }

    /// Sesi ders klasörüne yazar (ana iş parçacığı dışında); iCloud yedeğine girmez (yeniden indirilebilir). Dosya adını döndürür.
    @concurrent
    static func saveAudio(_ data: Data, lesson id: UUID) async throws -> String {
        _ = directory(for: id)
        let url = audioURL(lesson: id)
        try data.write(to: url, options: .atomic)
        excludeFromBackup(url)
        return audioFileName
    }

    /// Dosyayı iCloud yedeğinden hariç tutar (yeniden indirilebilen ders sesi).
    static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Uygulama yedeğinden gelen ders dosyasını yerine kopyalar. Kopya kaynağın "yedeğe girmez" özniteliğini
    /// taşımaz: ses (m4a) yeniden hariç tutulur, yoksa geri yüklemeden sonra iCloud yedeğine girer.
    static func restoreFile(_ source: URL, to destination: URL) {
        try? FileManager.default.removeItem(at: destination)
        guard (try? FileManager.default.copyItem(at: source, to: destination)) != nil else { return }
        if destination.pathExtension.lowercased() == "m4a" { excludeFromBackup(destination) }
    }

    static func removeAudio(lesson id: UUID, name: String) {
        try? FileManager.default.removeItem(at: audioURL(lesson: id, name: name))
    }

    /// base64 JPEG'leri diske yazar (ana iş parçacığı dışında). Yazılan kare kimliklerini döndürür.
    @concurrent
    static func saveKeyframes(_ frames: [Keyframe], lesson id: UUID) async -> [String] {
        var saved: [String] = []
        for frame in frames where !frame.image.isEmpty {
            var base64 = frame.image
            if base64.hasPrefix("data:"), let comma = base64.firstIndex(of: ",") { base64 = String(base64[base64.index(after: comma)...]) }
            guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters), !data.isEmpty else { continue }
            do {
                try data.write(to: keyframeURL(lesson: id, frame: frame.id), options: .atomic)
                saved.append(frame.id)
            } catch {
                continue
            }
        }
        return saved
    }

    /// Kareleri yazar ve görselsiz transkripti kodlar; ikisi de ana iş parçacığı dışında.
    @concurrent
    static func store(_ transcript: VideoTranscript, lesson id: UUID) async -> Data? {
        _ = await saveKeyframes(transcript.keyframes, lesson: id)
        return try? JSONEncoder().encode(transcript.withoutImages)
    }
}

// MARK: - Zaman biçimi ve dışa aktarma

nonisolated enum VideoTime {
    /// 75 → "1:15", 3725 → "1:02:05".
    static func string(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds : 0))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "90" → 90, "1:30" → 90, "1:02:05" → 3725; geçersizse nil.
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: ":")
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && Int($0) != nil }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        if numbers.count > 1, numbers.dropFirst().contains(where: { $0 >= 60 }) { return nil }
        return Double(numbers.reduce(0) { $0 * 60 + $1 })
    }

    /// SRT zaman damgası: "00:01:02,500".
    static func srt(_ seconds: Double) -> String {
        let ms = max(0, Int((seconds.isFinite ? seconds : 0) * 1000))
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
    }
}

nonisolated enum TranscriptExport {
    /// SubRip (.srt) altyazı dosyası metni.
    static func srt(_ segments: [TranscriptSegment]) -> String {
        segments.enumerated().map { index, s in
            let end = max(s.end, s.start + 0.5)
            return "\(index + 1)\n\(VideoTime.srt(s.start)) --> \(VideoTime.srt(end))\n\(s.text.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        }.joined(separator: "\n")
    }
}

// MARK: - Bağlantı yardımcıları

nonisolated enum YouTubeLink {
    private static func url(from text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        if !trimmed.lowercased().hasPrefix("http://"), !trimmed.lowercased().hasPrefix("https://") { trimmed = "https://" + trimmed }
        return URL(string: trimmed)
    }

    /// youtube.com (www., m., music.), youtube-nocookie.com ve youtu.be bağlantıları.
    static func isYouTube(_ text: String) -> Bool {
        guard let host = url(from: text)?.host()?.lowercased() else { return false }
        return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
            || host == "youtube-nocookie.com" || host.hasSuffix(".youtube-nocookie.com")
    }

    /// Video kimliği (11 karakter) varsa.
    static func videoID(_ text: String) -> String? {
        guard isYouTube(text), let url = url(from: text) else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = url.pathComponents.filter { $0 != "/" }
        var candidate: String?
        if url.host()?.lowercased() == "youtu.be" {
            candidate = path.first
        } else if let v = components?.queryItems?.first(where: { $0.name == "v" })?.value {
            candidate = v
        } else if path.count >= 2, ["shorts", "live", "embed", "v"].contains(path[0]) {
            candidate = path[1]
        }
        guard let id = candidate, isValidID(id) else { return nil }
        return id
    }

    static func playlistID(_ text: String) -> String? {
        guard isYouTube(text), let url = url(from: text) else { return nil }
        let list = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "list" }?.value
        return list?.isEmpty == false ? list : nil
    }

    static func isValidID(_ id: String) -> Bool {
        id.count == 11 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    static func thumbnailURL(videoID: String) -> URL? {
        guard isValidID(videoID) else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
    }

    /// Belirli saniyeden açan YouTube bağlantısı.
    static func watchURL(videoID: String, at seconds: Double = 0) -> URL? {
        guard isValidID(videoID) else { return nil }
        let t = Int(max(0, seconds))
        return URL(string: "https://www.youtube.com/watch?v=\(videoID)" + (t > 0 ? "&t=\(t)s" : ""))
    }
}

// MARK: - Yarım kalan işler

/// Ekran kapanınca yoklama durur ama sunucudaki iş sürer; sonucu 2 saat içinde yeniden almak için kayıt.
nonisolated struct PendingYouTubeJob: Codable, Hashable, Identifiable, Sendable {
    var jobId: String
    var url: String
    var title: String
    var startedAt: Date
    var id: String { jobId }
}

enum YouTubePendingJobs {
    static let key = "youtube.pendingJobs"
    /// Sunucu sonucu iş bitince 2 saat tutar; işin kendisi de sürebilir.
    static let lifetime: TimeInterval = 4 * 3600

    static var all: [PendingYouTubeJob] {
        let stored = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([PendingYouTubeJob].self, from: $0) } ?? []
        return stored.filter { $0.startedAt > Date.now.addingTimeInterval(-lifetime) }
    }

    static func add(_ job: PendingYouTubeJob) {
        save(all.filter { $0.jobId != job.jobId } + [job])
    }

    static func remove(_ jobId: String) {
        save(all.filter { $0.jobId != jobId })
    }

    private static func save(_ jobs: [PendingYouTubeJob]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(jobs), forKey: key)
    }
}
