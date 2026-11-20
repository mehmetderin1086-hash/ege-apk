import Foundation

/// #3: senaryo aşamasının ilerlemesi (sunucu işi yoklamasından).
nonisolated struct ScriptProgress: Equatable, Sendable {
    /// "plan" | "chapters" | "check" | "done"
    var stage: String = "plan"
    var chaptersDone = 0
    var chaptersTotal = 0
    /// Sunucunun önceden ürettiği sahneler (prerender).
    var scenesDone: Int?
    var scenesTotal: Int?

    init(stage: String = "plan", chaptersDone: Int = 0, chaptersTotal: Int = 0, scenesDone: Int? = nil, scenesTotal: Int? = nil) {
        self.stage = stage
        self.chaptersDone = chaptersDone
        self.chaptersTotal = chaptersTotal
        self.scenesDone = scenesDone
        self.scenesTotal = scenesTotal
    }

    init(status: ScriptJobStatus) {
        stage = status.stage ?? (status.state == "queued" ? "plan" : "chapters")
        chaptersTotal = status.chaptersTotal ?? status.plan?.chapters.count ?? 0
        chaptersDone = min(status.chaptersDone ?? 0, max(chaptersTotal, status.chaptersDone ?? 0))
        scenesDone = status.prerender?.done
        scenesTotal = status.prerender?.total
    }

    /// Senaryo aşaması içindeki gerçek oran (0…1): plan → konular → denetim.
    var fraction: Double {
        switch stage {
        case "plan": chaptersTotal > 0 ? 0.15 : 0.05
        case "chapters": 0.15 + 0.75 * Double(min(chaptersDone, chaptersTotal)) / Double(max(chaptersTotal, 1))
        case "check": 0.93
        case "done": 1
        default: 0.05
        }
    }

    /// "Plan çıkarıldı · Konu 6/14"
    var text: String {
        switch stage {
        case "plan": chaptersTotal > 0 ? "Plan çıkarıldı" : "Plan çıkarılıyor"
        case "chapters": chaptersTotal > 0 ? "Plan çıkarıldı · Konu \(min(chaptersDone, chaptersTotal))/\(chaptersTotal)" : "Konular yazılıyor"
        case "check": "Senaryo denetleniyor"
        case "done": "Senaryo hazır"
        default: "Senaryo yazılıyor"
        }
    }
}

/// İlerleme metni ve oranları (saf; test edilir).
nonisolated enum GenerationProgress {
    /// "Plan çıkarıldı · Konu 6/14 · Sahne 18/52". Sahne sayısı yoksa yalnız senaryo kısmı.
    static func text(script: ScriptProgress?, scenesDone: Int?, scenesTotal: Int?) -> String {
        var parts: [String] = []
        if let script { parts.append(script.text) }
        if let total = scenesTotal, total > 0 {
            parts.append("Sahne \(min(scenesDone ?? 0, total))/\(total)")
        }
        return parts.isEmpty ? "Hazırlanıyor" : parts.joined(separator: " · ")
    }
}

/// #4: yeniden deneme kuralları (saf; test edilir).
nonisolated enum RetryPolicy {
    /// Üstel bekleme: 30 sn → 2 → 5 → 15 dk.
    static let steps: [TimeInterval] = [30, 120, 300, 900]

    /// `attempt` 0 tabanlı. Sunucu `Retry-After` verdiyse o kullanılır (en az 5 sn, en çok 6 sa).
    static func delay(attempt: Int, retryAfter: Double?) -> TimeInterval {
        if let retryAfter, retryAfter > 0 { return min(max(retryAfter, 5), 6 * 3600) }
        return steps[min(max(attempt, 0), steps.count - 1)]
    }

    /// Sunucunun geçici hata kodları (functions/src/errors.ts `ErrorCode` + iş kaydındaki `server_restarted`).
    static let transientCodes: Set<String> = ["server_restarted", "upstream_error", "internal"]
    /// Kota kodları (Retry-After ya da üstel beklemeyle yeniden denenir).
    static let quotaCodes: Set<String> = ["rate_limited", "daily_limit"]
    /// Geçici sunucu hatasında (kota ve ağ hariç) en çok bu kadar otomatik deneme; sonra kullanıcı karar verir.
    static let maxServerAttempts = 6

    /// Kota, ağ ya da geçici sunucu hatası mı (otomatik yeniden denenir)?
    static func isRetryable(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return error is URLError }
        if api.code == "network" || api.status == 429 || api.status == 408 { return true }
        if (500...599).contains(api.status) && api.status != 501 { return true }
        return transientCodes.contains(api.code) || quotaCodes.contains(api.code)
    }

    /// `attempts`: bu istek için önceki otomatik deneme sayısı. Ağ ve kota her zaman beklenir;
    /// süreğen sunucu hatası (ör. hep `internal`) sonsuz denenmez.
    static func shouldAutoRetry(_ error: Error, attempts: Int) -> Bool {
        guard isRetryable(error) else { return false }
        if let api = error as? APIError, api.code != "network", api.status != 429, !quotaCodes.contains(api.code) {
            return attempts < maxServerAttempts
        }
        return true
    }

    /// Kısa otomatik beklemede (≤ 2 dk) sistem arka plan görevi açık tutulur: kilitliyken tek bir geçici hata uygulamayı
    /// askıya aldırmasın. Daha uzun beklemede görev kapanır (ilerlemeyen görevi sistem zaten sonlandırır).
    static func keepsBackgroundTask(delay: TimeInterval) -> Bool { delay <= 120 }

    /// Kalıcı hata: tekrar denemek boşuna (yalnız kullanıcı düzeltebilir).
    static func isFatalForAudio(_ error: Error) -> Bool {
        ["budget_exceeded", "job_token_invalid", "scene_attempts_exceeded"].contains((error as? APIError)?.code ?? "")
    }
}

/// Otomatik yeniden deneme beklemesi dilimlenir (saf; test edilir): tek parça uyumak yerine en çok 1 sn'lik dilimlerle
/// beklenir; "Şimdi dene" bitiş anını öne çekince bekleme en geç bir dilim sonra biter.
nonisolated enum RetryWait {
    /// Sıradaki uyku dilimi (sn); bitiş anı geldiyse nil.
    static func next(until: Date, now: Date) -> Double? {
        let remaining = until.timeIntervalSince(now)
        return remaining > 0 ? min(remaining, 1) : nil
    }
}

/// Senaryo işi uçları (testte sahtesi verilir).
@MainActor
struct ScriptJobAPI {
    var start: (ScriptStartRequest) async throws -> String
    var status: (String) async throws -> ScriptJobStatus
    var result: (String) async throws -> ScriptJobResult

    static var live: ScriptJobAPI {
        ScriptJobAPI(start: { try await APIClient.shared.scriptStart($0).jobId },
                     status: { try await APIClient.shared.scriptStatus(jobId: $0) },
                     result: { try await APIClient.shared.scriptResult(jobId: $0) })
    }
}

/// #3: sunucudaki senaryo işini başlatır, yoklar ve sonucunu alır. Uygulama ölse de `jobID` ile sürer.
@MainActor
enum ScriptJobClient {
    /// İşi bulur ya da başlatır, bitene dek yoklar. `makeStart` yalnız iş yoksa (ya da sunucu işi kaybettiyse) çağrılır.
    /// `onJob(nil)`: iş bırakıldı (bitti ya da kayboldu); çağıran kayıttaki iş kimliğini silmeli.
    /// `sleep`: yoklama beklemeleri (testte beklemesiz verilir).
    static func run(existingJobID: String?,
                    api: ScriptJobAPI = .live,
                    makeStart: () async throws -> ScriptStartRequest,
                    onJob: (String?) -> Void,
                    onProgress: (ScriptJobStatus) -> Void,
                    sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) async throws -> ScriptJobResult {
        var jobID = existingJobID
        var restarts = 0
        var failures = 0
        // Sonuç ucunun hataları ayrı sayılır: `failures` her başarılı durum yoklamasında sıfırlandığından, durumu "done"
        // olup sonucu sürekli hata veren iş sonsuza dek yoklanırdı.
        var resultFailures = 0
        var polls = 0
        while true {
            try Task.checkCancellation()
            if jobID == nil {
                let request = try await makeStart()
                let started = try await api.start(request)
                jobID = started
                onJob(started)
            }
            guard let id = jobID else { continue }
            let status: ScriptJobStatus
            do {
                status = try await api.status(id)
                failures = 0
            } catch let error as APIError where error.code == "not_found" || error.status == 404 {
                // Sunucu işi kaybetti (süresi doldu ya da yeniden başladı): aynı kimlikle yeniden açılır (hak çift düşmez).
                guard restarts < 2 else { throw error }
                restarts += 1
                jobID = nil
                onJob(nil)
                continue
            } catch let error as APIError where isTransientPollError(error) {
                // Yoklama sırasında ağ koptu (ör. uygulama askıya alındı): kısa beklemeyle sürdür.
                failures += 1
                guard failures <= 8 else { throw error }
                try await sleep(.seconds(min(30, 3 * failures)))
                continue
            }
            onProgress(status)
            switch status.state {
            case "done", "partial":
                do {
                    return try await api.result(id)
                } catch let error as APIError {
                    guard isTransientPollError(error), resultFailures < 8 else { throw error }
                    resultFailures += 1
                    try await sleep(.seconds(min(30, 3 * resultFailures)))
                }
            case "error":
                // §5.1: biten (error|canceled) iş bırakılır; sonraki deneme aynı clientRequestId ile YENİ iş açar
                // (aksi hâlde aynı ölü iş 48 sa boyunca yoklanıp hep aynı hatayı verir). Hak sunucuda iade edilmiştir.
                let error = status.error ?? .init(code: "script_failed", message: "Senaryo yazılamadı.", retryAfterSec: nil)
                jobID = nil
                onJob(nil)
                guard error.code == "server_restarted", restarts < 2 else { throw jobError(error) }
                restarts += 1
            case "canceled":
                jobID = nil
                onJob(nil)
                throw APIError(status: 0, code: "canceled", message: "Senaryo işi iptal edildi.")
            default:
                polls += 1
                try await sleep(.seconds(polls < 10 ? 3 : 5))
            }
        }
    }

    /// Yoklamada geçici sayılan hata (kota hariç; kota bekleme ister).
    static func isTransientPollError(_ error: APIError) -> Bool {
        RetryPolicy.isRetryable(error) && error.status != 429
    }

    /// İş hatasını uygulama hatasına çevirir; `retryAfterSec` varsa kota sayılır (otomatik yeniden denenir).
    /// Kodlar sunucunun `ErrorCode` kümesiyle hizalı (functions/src/errors.ts); durumlar oradaki tabloya uyar.
    static func jobError(_ error: ScriptJobStatus.JobError) -> APIError {
        if let after = error.retryAfterSec {
            return APIError(status: 429, code: error.code, message: error.message, retryAfter: after)
        }
        if RetryPolicy.quotaCodes.contains(error.code) { return APIError(status: 429, code: error.code, message: error.message) }
        if RetryPolicy.transientCodes.contains(error.code) { return APIError(status: 503, code: error.code, message: error.message) }
        let status = switch error.code {
        case "invalid_request", "too_large": 400
        case "unauthorized": 401
        case "job_token_invalid", "budget_exceeded", "scene_attempts_exceeded": 403
        case "not_found": 404
        case "conflict": 409
        default: 422
        }
        return APIError(status: status, code: error.code, message: error.message)
    }
}

/// #2: kısmi senaryonun sunucu iş kimliği (konuyu yeniden denemek için; 48 sa geçerli).
nonisolated enum ScriptJobMemory {
    private static func key(_ id: UUID) -> String { "scriptJob.\(id.uuidString)" }
    static func save(_ jobID: String?, for id: UUID) {
        if let jobID { UserDefaults.standard.set(jobID, forKey: key(id)) } else { UserDefaults.standard.removeObject(forKey: key(id)) }
    }
    static func jobID(for id: UUID) -> String? { UserDefaults.standard.string(forKey: key(id)) }
}

/// Kuyruktaki isteğin PDF sayfa aralıkları (belge kütüphanesi tüm PDF'i saklar; aralık burada korunur).
/// Kayıt: belge kimliği → [alt, üst] (eski biçim; aynı belgede son aralık kalır) ve `order` → `QueuedRequest.documentIDs`
/// ile hizalı [[alt, üst] ya da []] dizisi: aynı belgeden iki aralık (kitabın iki bölümü) birbirini ezmez.
nonisolated enum QueuedPageRanges {
    private static func key(_ id: UUID) -> String { "queue.ranges.\(id.uuidString)" }
    private static let orderKey = "order"

    /// `documentIDs[i]` = `sources[i]`'nin belge kimliği (kaydedilemediyse nil); dizi kaynaklarla hizalı olmalı.
    /// Kaydedilemeyen kaynak `order`'a girmez (`QueuedRequest.documentIDs`'te de yoktur).
    static func save(_ sources: [ImportedSource], documentIDs: [UUID?], for id: UUID) {
        var record: [String: Any] = [:]
        var order: [[Int]] = []
        for (source, doc) in zip(sources, documentIDs) {
            guard let doc else { continue }
            let bounds = source.pageRange.map { [$0.lowerBound, $0.upperBound] } ?? []
            order.append(bounds)
            if !bounds.isEmpty { record[doc.uuidString] = bounds }
        }
        guard !record.isEmpty else {
            UserDefaults.standard.removeObject(forKey: key(id))
            return
        }
        record[orderKey] = order
        UserDefaults.standard.set(record, forKey: key(id))
    }

    private static func range(_ bounds: [Int]?) -> ClosedRange<Int>? {
        guard let bounds, bounds.count == 2, bounds[0] <= bounds[1] else { return nil }
        return bounds[0]...bounds[1]
    }

    /// `QueuedRequest.documentIDs[index]`'in aralığı (nil = tüm sayfalar). Sıra kaydı varsa o esastır; yoksa (eski
    /// kayıt) belge kimliğine bakılır.
    static func range(at index: Int, document: UUID, for id: UUID) -> ClosedRange<Int>? {
        guard let record = UserDefaults.standard.dictionary(forKey: key(id)) else { return nil }
        if let order = record[orderKey] as? [[Int]], order.indices.contains(index) { return range(order[index]) }
        return range(record[document.uuidString] as? [Int])
    }

    /// Belge kimliğine göre (eski biçim): aynı belge isteğe bir kez girdiyse yeterlidir.
    static func apply(to sources: [ImportedSource], for id: UUID) -> [ImportedSource] {
        guard let record = UserDefaults.standard.dictionary(forKey: key(id)) else { return sources }
        return sources.map { source in
            var s = source
            if let doc = source.documentID?.uuidString, let r = range(record[doc] as? [Int]) { s.pageRange = r }
            return s
        }
    }

    static func clear(_ id: UUID) { UserDefaults.standard.removeObject(forKey: key(id)) }
}

/// Kuyruktan yüklenen kaynakların adları (saf; test edilir): kaynak ekranında verilen ad (`QueuedRequest.sourceNames`)
/// esastır, belge kütüphanesindeki belgenin adı değişmez. Sayılar tutmuyorsa (kopyalanamamış ya da silinmiş belge)
/// eşleme güvenli değildir; dokunulmaz.
nonisolated enum QueuedSourceNames {
    static func apply(_ names: [String], to sources: [ImportedSource]) -> [ImportedSource] {
        guard names.count == sources.count else { return sources }
        return zip(sources, names).map { source, name in
            var named = source
            if !name.isEmpty { named.name = name }
            return named
        }
    }
}
