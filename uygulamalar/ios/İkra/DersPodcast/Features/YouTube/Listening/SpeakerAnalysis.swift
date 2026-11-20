import Foundation

// Öğrenci konuşması (#8): sunucu `POST /v1/youtube/speakers { segments: [{ i, text }] }` (≤ 400 parça) → `{ student: [int] }`.
// Parçalar altyazı SATIRLARIdır (~2–3 sn): ders paragrafları 30–90 sn olup öğretmenle öğrenciyi karıştırır.
// Sonuç ders klasöründe `speakers.json` (sürüm 2) olarak durur; ders ekranı o satırların kelimelerini farklı renkte gösterir.
// Sürüm 1 (paragraf düzeyli) kayıtlar yok sayılır.

nonisolated struct SpeakerSegment: Codable, Hashable, Sendable {
    var i: Int
    var text: String
}

nonisolated struct SpeakersRequest: Encodable, Sendable {
    var segments: [SpeakerSegment]
}

nonisolated struct SpeakersResponse: Decodable, Sendable {
    var student: [Int]

    private enum CodingKeys: String, CodingKey { case student }

    init(student: [Int]) { self.student = student }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        student = try c.decodeIfPresent([Int].self, forKey: .student) ?? []
    }
}

/// Bir dersin kayıtlı konuşmacı çözümlemesi: `count` çözümlenen altyazı satırı sayısı (transkript değişirse eskimiş sayılır),
/// `student` öğrenci satırlarının sırası (`TranscriptFormat.orderedSegments` sıralamasında).
nonisolated struct LessonSpeakers: Codable, Hashable, Sendable {
    /// 2: altyazı satırı düzeyi. 1 (paragraf düzeyi) artık geçersiz.
    static let currentVersion = 2

    var version = LessonSpeakers.currentVersion
    var count: Int
    var student: [Int]

    /// Kayıt güncel sürümde ve bu satır sayısıyla uyumlu mu.
    func matches(segmentCount: Int) -> Bool { version == Self.currentVersion && count == segmentCount }
}

nonisolated enum SpeakerAnalysis {
    /// Sunucu sınırı: istek başına en fazla 400 parça.
    static let batchSize = 400
    /// Parça başına gönderilen en çok karakter (uzun satırlar kırpılır).
    static let maxTextLength = 500

    // MARK: - Dosya

    /// Yan etkisiz yol (klasör oluşturmaz).
    static func url(lesson id: UUID) -> URL {
        URL.applicationSupportDirectory.appending(path: "Videos", directoryHint: .isDirectory)
            .appending(path: id.uuidString, directoryHint: .isDirectory)
            .appending(path: "speakers.json")
    }

    /// Güncel sürümdeki kayıt; eski (paragraf düzeyli, sürüm 1) ya da okunamayan kayıt nil.
    static func load(lesson id: UUID) -> LessonSpeakers? {
        guard let data = try? Data(contentsOf: url(lesson: id)),
              let saved = try? JSONDecoder().decode(LessonSpeakers.self, from: data),
              saved.version == LessonSpeakers.currentVersion else { return nil }
        return saved
    }

    static func save(_ speakers: LessonSpeakers, lesson id: UUID) {
        _ = VideoFiles.directory(for: id)
        guard let data = try? JSONEncoder().encode(speakers) else { return }
        try? data.write(to: url(lesson: id), options: .atomic)
    }

    static func delete(lesson id: UUID) {
        try? FileManager.default.removeItem(at: url(lesson: id))
    }

    // MARK: - İstek

    /// Altyazı satırlarını (başlangıca göre sıralı) ≤ 400'lük gruplara böler; `i` satırın sıra numarasıdır
    /// (`TranscriptFormat.orderedSegments` sıralamasında, öğrenci satırı sırasıyla aynı).
    static func requests(segments: [TranscriptSegment]) -> [SpeakersRequest] {
        let lines = TranscriptFormat.orderedSegments(segments).enumerated().map {
            SpeakerSegment(i: $0.offset, text: String($0.element.text.prefix(maxTextLength)))
        }
        return stride(from: 0, to: lines.count, by: batchSize).map {
            SpeakersRequest(segments: Array(lines[$0..<min($0 + batchSize, lines.count)]))
        }
    }

    /// Yanıtları birleştirir: yalnızca gönderilen sıra numaraları geçerlidir, yinelenenler atılır, sıralı döner.
    static func merge(_ responses: [SpeakersResponse], segmentCount: Int) -> [Int] {
        Array(Set(responses.flatMap(\.student).filter { $0 >= 0 && $0 < segmentCount })).sorted()
    }

    /// Sunucuya sorar, sonucu ders klasörüne yazar.
    static func run(segments: [TranscriptSegment], lesson id: UUID) async throws -> LessonSpeakers {
        var responses: [SpeakersResponse] = []
        for request in requests(segments: segments) {
            try Task.checkCancellation()
            responses.append(try await APIClient.shared.youtubeSpeakers(request))
        }
        let result = LessonSpeakers(count: segments.count, student: merge(responses, segmentCount: segments.count))
        save(result, lesson: id)
        return result
    }
}

extension APIClient {
    @concurrent
    nonisolated func youtubeSpeakers(_ request: SpeakersRequest) async throws -> SpeakersResponse {
        try await post("/v1/youtube/speakers", request)
    }
}
