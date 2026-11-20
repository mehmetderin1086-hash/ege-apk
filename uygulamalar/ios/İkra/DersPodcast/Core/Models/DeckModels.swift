import Foundation

// Slayt destesi (sunucu: /v1/deck, /v1/deck-image, /v1/deck/pptx).

nonisolated struct Deck: Codable, Hashable, Sendable {
    var title: String
    var subtitle: String
    var slides: [DeckSlide]
    /// JSON alanları opsiyoneldir; önceki desteler değişmeden açılır.
    var theme: String?
    var imageStyle: String?
    var imageLevel: Int?

    var palette: DeckPalette { DeckPalette(rawValue: theme ?? "") ?? .studio }
    var illustrationStyle: DeckIllustrationStyle { DeckIllustrationStyle(rawValue: imageStyle ?? "") ?? .textbook }
}

nonisolated enum DeckPalette: String, CaseIterable, Codable, Identifiable, Sendable {
    case studio, ocean, forest, ember
    var id: String { rawValue }
    var title: String {
        switch self { case .studio: "Stüdyo"; case .ocean: "Okyanus"; case .forest: "Orman"; case .ember: "Toprak" }
    }
    var accentHex: String {
        switch self { case .studio: "#5942C8"; case .ocean: "#086B83"; case .forest: "#236A52"; case .ember: "#A3482B" }
    }
    var secondaryHex: String {
        switch self { case .studio: "#C05B38"; case .ocean: "#A4532A"; case .forest: "#95601B"; case .ember: "#286B78" }
    }
    var surfaceHex: String {
        switch self { case .studio: "#F7F5FC"; case .ocean: "#F1F8FA"; case .forest: "#F3F8F3"; case .ember: "#FCF6F0" }
    }
}

nonisolated enum DeckIllustrationStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case textbook, isometric, cutaway
    var id: String { rawValue }
    var title: String {
        switch self { case .textbook: "Ders kitabı"; case .isometric: "İzometrik"; case .cutaway: "Kesit ve detay" }
    }
    var direction: String {
        switch self {
        case .textbook: "Açık zeminde temiz, düz renkli ders kitabı çizimi."
        case .isometric: "Bilimsel ilişkileri koruyan izometrik eğitim çizimi; yumuşak gölge, sade arka plan."
        case .cutaway: "Kaynakta anlatılan iç yapıyı gösteren büyütülmüş kesit veya detay çizimi; olmayan parça ekleme."
        }
    }
}

nonisolated struct DeckSlide: Codable, Hashable, Sendable {
    var kind: String          // title | bullets | table | chart | diagram | image | quote | summary
    var title: String
    var chapterIndex: Int?
    var sourcePages: [Int]
    var notes: String
    var bullets: [String]?
    var table: DeckTable?
    var chart: DeckChart?
    var diagram: DeckDiagram?
    var imagePrompt: String?
    var quote: String?
    // Geliştirilmiş türler
    var subtitle: String?
    var stat: DeckStat?
    var timeline: [DeckTimelineItem]?
    var figureId: String?
    var caption: String?
}

nonisolated struct DeckStat: Codable, Hashable, Sendable { var value: String; var label: String; var context: String }
nonisolated struct DeckTimelineItem: Codable, Hashable, Sendable { var label: String; var title: String; var detail: String }

/// Kaynak belgeden çıkarılan şekil/tablo/fotoğraf (kırpılmış ve iyileştirilmiş hali bölüm klasöründe figure_<id>.png).
nonisolated struct SourceFigure: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var kind: String          // figure | chart | table | photo | diagram
    var caption: String
    var page: Int
    var documentName: String
    var table: DeckTable?
}

nonisolated struct FigureRef: Encodable, Sendable { var id: String; var kind: String; var caption: String; var page: Int }
nonisolated struct FigurePage: Encodable, Sendable { var page: Int; var image: String; var width: Int; var height: Int }
nonisolated struct FiguresRequest: Encodable, Sendable { var pages: [FigurePage] }
nonisolated struct DetectedFigure: Decodable, Sendable {
    var page: Int
    var kind: String
    var box: [Double]
    var caption: String
    var table: DeckTable?
}
nonisolated struct FiguresResponse: Decodable, Sendable { var figures: [DetectedFigure] }

nonisolated struct DeckTable: Codable, Hashable, Sendable {
    var headers: [String]
    var rows: [[String]]
}

nonisolated struct DeckChart: Codable, Hashable, Sendable {
    struct Series: Codable, Hashable, Sendable { var name: String; var values: [Double] }
    var type: String          // bar | line | pie
    var title: String
    var unit: String?
    var labels: [String]
    var series: [Series]
}

nonisolated struct DeckDiagram: Codable, Hashable, Sendable {
    struct Node: Codable, Hashable, Sendable { var title: String; var detail: String }
    var layout: String        // steps | cycle | hierarchy | compare
    var nodes: [Node]
}

nonisolated struct DeckRequest: Encodable, Sendable {
    var title: String
    var sourceNotes: String
    var chapters: [SlideChapter]
    var slideCount: Int
    var language: String
    var includeImages: Bool
    var figures: [FigureRef]?
}

nonisolated struct DeckResponse: Decodable, Sendable { var deck: Deck; var model: String? }
nonisolated struct DeckImageRequest: Encodable, Sendable {
    struct Reference: Encodable, Sendable { var data: String; var mimeType: String }
    var prompt: String; var aspect: String
    /// Üslup örneği (aynı videonun hazır bir çizimi, küçültülmüş JPEG): sonraki çizimler aynı elden çıkmış görünür. Ders Video kullanır.
    var reference: Reference?
}
nonisolated struct DeckImageResponse: Decodable, Sendable { var image: String; var mimeType: String; var model: String?; var via: String? }
nonisolated struct DeckImagePayload: Encodable, Sendable { var data: String; var mimeType: String }
nonisolated struct DeckTheme: Encodable, Sendable {
    var accent: String
    var secondary: String?
    var background: String?
}
nonisolated struct DeckPPTXRequest: Encodable, Sendable { var deck: Deck; var images: [String: DeckImagePayload]; var theme: DeckTheme }
nonisolated struct DeckPPTXResponse: Decodable, Sendable { var pptx: String }

extension APIClient {
    func deck(_ request: DeckRequest) async throws -> DeckResponse { try await post("/v1/deck", request) }
    func deckImage(_ request: DeckImageRequest) async throws -> DeckImageResponse { try await post("/v1/deck-image", request) }
    func figures(_ request: FiguresRequest) async throws -> [DetectedFigure] {
        let response: FiguresResponse = try await post("/v1/figures", request)
        return response.figures
    }
    func deckPPTX(_ request: DeckPPTXRequest) async throws -> Data {
        let response: DeckPPTXResponse = try await post("/v1/deck/pptx", request)
        guard let data = Data(base64Encoded: response.pptx) else {
            throw APIError(status: 0, code: "decode", message: "PowerPoint dosyası okunamadı.")
        }
        return data
    }
}
