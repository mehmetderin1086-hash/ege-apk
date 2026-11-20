import Foundation
import SwiftData

/// Bekleyen işlerin başlatma istekleri: sunucu işi unutursa (404) aynı istekle yeniden gönderilir (#42).
/// `PendingYouTubeJob` Core/Models'ta olduğundan istek yan depoda, iş kimliğiyle eşlenerek tutulur.
enum YouTubePendingRequests {
    static let key = "youtube.pendingRequests"

    private static var stored: [String: YouTubeStartRequest] {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([String: YouTubeStartRequest].self, from: $0) } ?? [:]
    }

    static func request(for jobId: String) -> YouTubeStartRequest? { stored[jobId] }

    /// Kaydeder; bekleyen iş listesinde olmayan eski girdiler temizlenir.
    static func save(_ request: YouTubeStartRequest, for jobId: String) {
        var all = stored
        all[jobId] = request
        let alive = Set(YouTubePendingJobs.all.map(\.jobId)).union([jobId])
        all = all.filter { alive.contains($0.key) }
        UserDefaults.standard.set(try? JSONEncoder().encode(all), forKey: key)
    }

    static func remove(_ jobId: String) {
        var all = stored
        guard all.removeValue(forKey: jobId) != nil else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(all), forKey: key)
    }
}

/// Sunucu işini başlatır, yoklar ve sonucu `VideoLesson` olarak kaydeder. İçe aktarma ekranı ve otomatik kuyruk ortak kullanır.
@MainActor
enum LessonImporter {
    /// Yoklama aralığı (sn).
    static let pollInterval: Double = 1.5

    /// Arayüze geri bildirimler.
    struct Hooks {
        var progress: (Double, String) -> Void = { _, _ in }
        /// Sunucu işi unutup yeniden gönderilince yeni iş kimliği.
        var jobChanged: (String) -> Void = { _ in }
        /// Sonuç alındı, kayda geçmeden hemen önce (durdurma artık sunucuda bir şeyi iptal etmez).
        var willSave: () -> Void = {}
    }

    /// İşi başlatır ve bekleyenlere (istekle birlikte) yazar. Başlatma isteği iptalden yalıtılır (yapılandırılmamış görev dış
    /// iptali devralmaz): istek sunucuya ulaştıysa iş orada başlar; yanıt okunmadan kesilirse iş kimliği kaybolurdu.
    static func start(_ request: YouTubeStartRequest, url: String, title: String) async throws -> String {
        let jobId = try await Task { try await APIClient.shared.youtubeStart(request) }.value
        YouTubePendingJobs.add(PendingYouTubeJob(jobId: jobId, url: url, title: title, startedAt: .now))
        YouTubePendingRequests.save(request, for: jobId)
        return jobId
    }

    /// İş kesin olarak öldü (hata, iptal, sunucuda yok): sınıf kaydıysa cihazdaki geçici ses de silinir.
    /// `forget`'ten ÖNCE çağrılmalı (yükleme kimliği kayıtlı istekten okunur).
    static func discardStash(for jobId: String) {
        if let uploadID = YouTubePendingRequests.request(for: jobId)?.uploadId { UploadStash.remove(uploadID: uploadID) }
    }

    /// Bekleyen işin kaydı + isteği temizlenir.
    static func forget(_ jobId: String) {
        YouTubePendingJobs.remove(jobId)
        YouTubePendingRequests.remove(jobId)
    }

    /// Kaybolan işi yeniden gönderme hatası kalıcı mı (geçersiz istek, bulunamadı…). Ağ, kota, sunucu ve oturum hataları
    /// geçicidir; iptal de hata sayılmaz.
    nonisolated static func resendFailureIsPermanent(_ error: Error) -> Bool {
        !(error is CancellationError) && ImportQueuePolicy.kind(of: error) == .item
    }

    /// İşi yoklar; bitince kareleri dosyaya yazıp dersi kaydeder. İş sunucuda bulunamazsa (404: sunucu yeniden başlamış)
    /// ve kayıtlı istek varsa aynı istekle yeniden gönderir (sunucu yarım işi önbellekten sürdürür).
    static func follow(jobId initialJobId: String, url: String, title: String, preview: VideoInfo?,
                       context: ModelContext, hooks: Hooks = Hooks()) async throws -> VideoLesson {
        var jobId = initialJobId
        var networkFailures = 0
        var resends = 0
        while true {
            try await Task.sleep(for: .seconds(pollInterval))
            let status: YouTubeJobStatus
            do {
                status = try await APIClient.shared.youtubeStatus(jobId: jobId)
                networkFailures = 0
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as APIError where error.status == 404 {
                guard resends < 2, let request = YouTubePendingRequests.request(for: jobId) else {
                    discardStash(for: jobId)
                    forget(jobId)
                    throw APIError(status: 404, code: "not_found",
                                   message: "İş sunucuda bulunamadı (sunucu yeniden başlamış ya da sonucun süresi dolmuş olabilir).")
                }
                resends += 1
                hooks.progress(0, "Sunucu işi kaybetmiş; yeniden gönderiliyor…")
                let newID: String
                do {
                    newID = try await start(request, url: url, title: title)
                } catch {
                    // Eski iş sunucuda yok; yeniden gönderme de kalıcı olarak reddedildiyse kaydı "Yarım kalan işlemler"de
                    // takılı kalmasın. Geçici hatada kayıt durur: sonra aynı istekle yeniden denenebilir.
                    if resendFailureIsPermanent(error) { forget(jobId) }
                    throw error
                }
                forget(jobId)
                jobId = newID
                hooks.jobChanged(newID)
                continue
            } catch let error as APIError where error.status == 401 || error.status == 400 {
                throw error
            } catch {
                // Geçici bağlantı kopması (ör. uygulama arka plandaydı): birkaç kez daha dene.
                networkFailures += 1
                if networkFailures >= 8 { throw error }
                hooks.progress(0, "Bağlantı bekleniyor…")
                try await Task.sleep(for: .seconds(2))
                continue
            }
            hooks.progress(status.progress, status.step.isEmpty ? (status.state == .queued ? "Sırada bekliyor" : "İşleniyor") : status.step)
            switch status.state {
            case .queued, .running:
                continue
            case .error:
                discardStash(for: jobId)
                forget(jobId)
                throw APIError(status: 0, code: "job", message: status.error ?? "İşlem başarısız oldu.")
            case .cancelled:
                discardStash(for: jobId)
                forget(jobId)
                throw APIError(status: 0, code: "cancelled", message: YouTubeImportLogic.cancelledText)
            case .done:
                guard let result = status.result else {
                    discardStash(for: jobId)
                    forget(jobId)
                    throw APIError(status: 0, code: "decode", message: "Sunucu sonucu göndermedi.")
                }
                // Yanıt gelirken durdurulduysa kaydetme: iptal isteği "done" döner ve sonuç 'Yarım kalan işlemler'de kalır.
                try Task.checkCancellation()
                hooks.willSave()
                hooks.progress(1, "Kaydediliyor")
                let lesson = await save(result, url: url, preview: preview, context: context)
                forget(jobId)
                return lesson
            }
        }
    }

    /// Sonucu ders olarak kaydeder (kareler diske, görselsiz JSON kayda) ve arka planda kare yazısı/etiket işlerini başlatır.
    static func save(_ incoming: VideoTranscript, url: String, preview: VideoInfo?, context: ModelContext) async -> VideoLesson {
        // Küresel terim sözlüğü (Terim düzeltme) yeni derse de uygulanır.
        let result = TermDictionary.apply(to: incoming)
        var video = result.video
        // Sonuçta gömme bilgisi yoksa önizlemedeki (aynı video) kullanılır.
        if video.embeddable == nil, let preview, preview.id == video.id { video.embeddable = preview.embeddable }
        let lesson = VideoLesson(url: video.url.isEmpty ? url : video.url, info: video)
        // Kareleri yaz + görselsiz JSON'u kodla: ana iş parçacığı dışında.
        let data = await VideoFiles.store(result, lesson: lesson.id)
        lesson.language = result.language
        lesson.source = result.source
        lesson.transcriptData = data
        // Sınıf kaydı: cihazda hazırlanan ses dersin çevrimdışı sesi olur (bu videonun indirilecek bir adresi yok).
        if video.id.hasPrefix("upload-"), let name = UploadStash.adopt(uploadID: String(video.id.dropFirst("upload-".count)), into: lesson.id) {
            lesson.audioFileName = name
        }
        context.insert(lesson)
        try? context.save()
        postProcess(lesson, transcript: result, context: context)
        return lesson
    }

    /// Kaydın ardından en iyi çabayla çalışan işler: karelerde yazı tanıma (#10) ve yapay zekâ etiketi (#40).
    static func postProcess(_ lesson: VideoLesson, transcript: VideoTranscript, context: ModelContext) {
        let id = lesson.id
        let frames = transcript.keyframes.map { FrameRef(id: $0.id, time: $0.time) }
        if !frames.isEmpty {
            Task { _ = await FrameTextScanner.scan(lesson: id, frames: frames) }
        }
        Task { await autoTag(lesson, transcript: transcript, context: context) }
    }

    /// Etiket yoksa `/v1/youtube/tags` ile üretir; hata (kota, ağ) sessizce yutulur — elle de eklenebilir.
    static func autoTag(_ lesson: VideoLesson, transcript: VideoTranscript, context: ModelContext) async {
        guard lesson.tags.isEmpty else { return }
        let summary = LessonTagging.summary(for: transcript)
        guard !summary.isEmpty else { return }
        guard let response = try? await APIClient.shared.youtubeTags(YouTubeTagsRequest(title: lesson.title, summary: summary)) else { return }
        let tags = TagLogic.normalize(subject: response.subject, topics: response.topics)
        guard !tags.isEmpty, lesson.modelContext != nil, !lesson.isDeleted, lesson.tags.isEmpty else { return }
        lesson.tags = tags
        try? context.save()
    }
}

/// Etiket isteği için ders özeti.
nonisolated enum LessonTagging {
    static let maxSummary = 1500

    static func summary(for transcript: VideoTranscript) -> String {
        if let summary = transcript.notes?.summary.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return String(summary.prefix(maxSummary))
        }
        let text = transcript.paragraphs.prefix(12).map(\.text).joined(separator: " ")
        return String(text.prefix(maxSummary))
    }
}
