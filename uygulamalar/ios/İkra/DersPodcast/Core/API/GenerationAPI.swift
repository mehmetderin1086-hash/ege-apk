import Foundation

// #3/#2/#5: sunucudaki senaryo işleri (/v1/script/*) ve senaryo düzeltme (/v1/fix-turns). Sözleşme: §5.1.

nonisolated struct ScriptPrerender: Encodable, Sendable {
    /// "chirp" | "xtts" | "edge" | "huggingface"
    var engine: String
    var replacements: [Pronunciation]?
}

nonisolated struct ScriptStartRequest: Encodable, Sendable {
    /// İleride oluşacak `Episode.id` (= `QueuedRequest.id`), küçük harfli UUID.
    var clientRequestId: String
    var settings: PodcastSettings
    var sources: [SourcePayload]
    var prerender: ScriptPrerender?
}

nonisolated struct ScriptStartResponse: Decodable, Sendable { var jobId: String }

nonisolated struct ScriptJobRef: Encodable, Sendable { var jobId: String }
nonisolated struct ScriptRetryChapterRequest: Encodable, Sendable { var jobId: String; var index: Int }

nonisolated struct ScriptJobStatus: Decodable, Sendable, Equatable {
    nonisolated struct PlanChapter: Decodable, Sendable, Equatable {
        var title: String
        var targetMinutes: Double?
        var style: String?
        var guest: Bool?
    }
    nonisolated struct Plan: Decodable, Sendable, Equatable {
        var title: String?
        var chapters: [PlanChapter]
    }
    nonisolated struct Prerender: Decodable, Sendable, Equatable { var done: Int; var total: Int }
    nonisolated struct JobError: Decodable, Sendable, Equatable {
        var code: String
        var message: String
        var retryAfterSec: Double?
    }

    var jobId: String
    /// "queued" | "running" | "done" | "partial" | "error" | "canceled"
    var state: String
    /// "plan" | "chapters" | "check" | "done"
    var stage: String?
    var chaptersTotal: Int?
    var chaptersDone: Int?
    var chapterErrors: [ChapterError]?
    var plan: Plan?
    var prerender: Prerender?
    var error: JobError?
}

nonisolated struct ScriptJobResult: Decodable, Sendable {
    var jobToken: String
    var script: PodcastScript
    var model: String?
}

nonisolated private struct ScriptJobOK: Decodable, Sendable { var ok: Bool? }

// MARK: - #5 fix-turns

nonisolated struct FixTurnsIssue: Encodable, Sendable {
    var severity: String
    var reason: String
    var correction: String?

    /// verify-script'in gerekçe/düzeltmesinde sınır yok; fix-turns `reason ≤ 600`, `correction ≤ 1500` ister (UTF-16).
    init(severity: String, reason: String, correction: String?) {
        self.severity = severity
        self.reason = ServerText.prefix(reason, 600)
        self.correction = correction.map { ServerText.prefix($0, 1500) }
    }

    init(_ issue: ScriptIssue) {
        self.init(severity: issue.severity, reason: issue.reason, correction: issue.correction)
    }
}

nonisolated struct FixTurnsTurn: Encodable, Sendable {
    var index: Int
    var speaker: Speaker
    var text: String
    var style: String
    /// Sunucu yalnız bu sayfaları koyar (`pagesFor`); yoksa bütün sayfalar gider.
    var sourcePage: Int?
    var issue: FixTurnsIssue

    /// Sunucu sınırlarına uymayan tur (metin > 1500, stil > 200 UTF-16) düzeltmeye gönderilmez: kırpılsa dönen
    /// düzeltme turun geri kalanını silerdi.
    static func make(index: Int, turn: ScriptTurn, issue: ScriptIssue) -> FixTurnsTurn? {
        let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf16.count <= 1500 else { return nil }
        return FixTurnsTurn(index: index, speaker: turn.speaker, text: text, style: ServerText.prefix(turn.style, 200),
                            sourcePage: turn.sourcePage.flatMap { $0 > 0 ? $0 : nil }, issue: FixTurnsIssue(issue))
    }
}

nonisolated struct FixTurnsSettings: Encodable, Sendable {
    var level: PodcastLevel
    var tone: PodcastTone
    var format: PodcastFormat
    var language: PodcastLanguage
    var pace: PodcastPace
    var depth: PodcastDepth
    var hostA: Host
    var hostB: Host
    var guest: Host?

    init(_ s: PodcastSettings) {
        level = s.level; tone = s.tone; format = s.format; language = s.language
        pace = s.pace; depth = s.depth; hostA = s.hostA; hostB = s.hostB; guest = s.guest
    }
}

nonisolated struct FixTurnsRequest: Encodable, Sendable {
    var title: String
    var sourceNotes: String
    var pages: [PageText]?
    var settings: FixTurnsSettings
    var turns: [FixTurnsTurn]
}

nonisolated struct FixedTurn: Decodable, Sendable, Equatable {
    var index: Int
    var text: String
    var style: String?
}

nonisolated private struct FixTurnsResponse: Decodable, Sendable { var turns: [FixedTurn] }

extension APIClient {
    func scriptStart(_ request: ScriptStartRequest) async throws -> ScriptStartResponse {
        try await post("/v1/script/start", request)
    }

    func scriptStatus(jobId: String) async throws -> ScriptJobStatus {
        try await post("/v1/script/status", ScriptJobRef(jobId: jobId))
    }

    func scriptResult(jobId: String) async throws -> ScriptJobResult {
        try await post("/v1/script/result", ScriptJobRef(jobId: jobId))
    }

    func scriptRetryChapter(jobId: String, index: Int) async throws {
        let _: ScriptJobOK = try await post("/v1/script/retry-chapter", ScriptRetryChapterRequest(jobId: jobId, index: index))
    }

    func scriptCancel(jobId: String) async throws {
        let _: ScriptJobOK = try await post("/v1/script/cancel", ScriptJobRef(jobId: jobId))
    }

    func fixTurns(_ request: FixTurnsRequest) async throws -> [FixedTurn] {
        let response: FixTurnsResponse = try await post("/v1/fix-turns", request)
        return response.turns
    }
}
