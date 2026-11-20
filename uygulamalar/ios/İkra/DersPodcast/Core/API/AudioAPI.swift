import Foundation

nonisolated struct SpeakRequest: Encodable, Sendable {
    /// "chirp" | "xtts" | "edge" | "huggingface"
    var engine: String
    var voice: String?
    var pace: PodcastPace?
    var style: String?
    var text: String
    var replacements: [Pronunciation]?
}

nonisolated struct PronunciationSuggestRequest: Encodable, Sendable {
    var text: String
    var known: [String]
}

nonisolated struct PronunciationSuggestion: Codable, Hashable, Sendable {
    var from: String
    var to: String
    var why: String
}

nonisolated private struct PronunciationSuggestResponse: Decodable, Sendable { var items: [PronunciationSuggestion] }

extension APIClient {
    /// #14/#41: kısa metni seslendirir (base64 WAV).
    func speak(_ request: SpeakRequest) async throws -> TTSResponse {
        try await post("/v1/speak", request)
    }

    func pronunciationSuggest(_ request: PronunciationSuggestRequest) async throws -> [PronunciationSuggestion] {
        let response: PronunciationSuggestResponse = try await post("/v1/pronunciation-suggest", request)
        return response.items
    }
}
