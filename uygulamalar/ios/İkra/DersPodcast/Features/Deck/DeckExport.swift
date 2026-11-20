import Foundation

// MARK: - /v1/deck/pptx tel biçimi

/// Sunucu şeması (functions/src/tools/deckSchema.ts) `chapterIndex` ve `chart.unit` anahtarlarını zorunlu tutar: değer null
/// olabilir, anahtar eksik olamaz. Sentezlenen Encodable nil alanı hiç yazmadığından (kapak/plan/özet slaytlarında
/// `chapterIndex` yok → 400) bu iki alan açıkça kodlanır. Saklanan `Deck` biçimi değişmez.
nonisolated struct PPTXWireRequest: Encodable, Sendable {
    var deck: PPTXWireDeck
    var images: [String: DeckImagePayload]
    var theme: DeckTheme
}

nonisolated struct PPTXWireDeck: Encodable, Sendable {
    var title: String
    var subtitle: String
    var slides: [PPTXWireSlide]

    init(_ deck: Deck) {
        title = deck.title
        subtitle = deck.subtitle
        slides = deck.slides.map { PPTXWireSlide($0) }
    }
}

nonisolated struct PPTXWireSlide: Encodable, Sendable {
    var slide: DeckSlide

    init(_ slide: DeckSlide) { self.slide = slide }

    private enum CodingKeys: String, CodingKey {
        case kind, title, chapterIndex, sourcePages, notes, bullets, table, chart, diagram, imagePrompt, quote
        case subtitle, stat, timeline, figureId, caption
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(slide.kind, forKey: .kind)
        try c.encode(slide.title, forKey: .title)
        if let chapter = slide.chapterIndex { try c.encode(chapter, forKey: .chapterIndex) } else { try c.encodeNil(forKey: .chapterIndex) }
        try c.encode(slide.sourcePages, forKey: .sourcePages)
        try c.encode(slide.notes, forKey: .notes)
        try c.encodeIfPresent(slide.bullets, forKey: .bullets)
        try c.encodeIfPresent(slide.table, forKey: .table)
        try c.encodeIfPresent(slide.chart.map { PPTXWireChart($0) }, forKey: .chart)
        try c.encodeIfPresent(slide.diagram, forKey: .diagram)
        try c.encodeIfPresent(slide.imagePrompt, forKey: .imagePrompt)
        try c.encodeIfPresent(slide.quote, forKey: .quote)
        try c.encodeIfPresent(slide.subtitle, forKey: .subtitle)
        try c.encodeIfPresent(slide.stat, forKey: .stat)
        try c.encodeIfPresent(slide.timeline, forKey: .timeline)
        try c.encodeIfPresent(slide.figureId, forKey: .figureId)
        try c.encodeIfPresent(slide.caption, forKey: .caption)
    }
}

nonisolated struct PPTXWireChart: Encodable, Sendable {
    var chart: DeckChart

    init(_ chart: DeckChart) { self.chart = chart }

    private enum CodingKeys: String, CodingKey { case type, title, unit, labels, series }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(chart.type, forKey: .type)
        try c.encode(chart.title, forKey: .title)
        if let unit = chart.unit { try c.encode(unit, forKey: .unit) } else { try c.encodeNil(forKey: .unit) }
        try c.encode(chart.labels, forKey: .labels)
        try c.encode(chart.series, forKey: .series)
    }
}

// MARK: - Saf yardımcılar (test edilir)

extension DeckAssets {
    /// /v1/deck isteği. Sunucu sınırları UTF-16 birimiyle ölçülür (`ServerText`): grafem sayan `prefix`, emojili ya da
    /// ayrışık (NFD) metinde sınırı aşıp 400 döndürüyordu. En fazla 15 konu gönderilir.
    nonisolated static func deckRequest(title: String, sourceNotes: String, timeline: Timeline, slideCount: Int, language: String,
                                        includeImages: Bool, figures: [SourceFigure]) -> DeckRequest {
        let chapters = timeline.chapters.prefix(15).map { chapter in
            SlideChapter(title: ServerText.prefix(chapter.title, 300),
                         text: ServerText.prefix(timeline.turns.filter { $0.chapterIndex == chapter.id }.map(\.text).joined(separator: " "), 6000))
        }
        return DeckRequest(
            title: ServerText.prefix(title, 300), sourceNotes: ServerText.prefix(sourceNotes, 15_000), chapters: chapters,
            slideCount: slideCount, language: language, includeImages: includeImages,
            figures: figures.isEmpty ? nil : figures.map { FigureRef(id: $0.id, kind: $0.kind, caption: ServerText.prefix($0.caption, 300), page: $0.page) })
    }

    /// Sunucunun /v1/deck isteğinde kabul ettiği en fazla şekil sayısı (fazlası 400 döndürür).
    nonisolated static let deckFigureLimit = 30

    /// Desteye girecek kaynak şekilleri. Video kareleriyle belge şekilleri birlikte sınırı aşarsa belge şekilleri
    /// (kullanıcının eklediği sayfa/fotoğraf) önceliklidir: liste kareleri başta tuttuğu için baştan kırpmak yeni
    /// eklenen fotoğrafın şekillerini desteye hiç sokmuyordu. Kalan yer karelere dersin bütününe yayılarak verilir.
    /// Liste sırası korunur; istek ve uzlaştırma aynı kırpılmış listeyi kullanır.
    nonisolated static func deckFigures(_ figures: [SourceFigure], limit: Int = deckFigureLimit) -> [SourceFigure] {
        let limit = max(0, limit)
        guard figures.count > limit else { return figures }
        let documents = figures.indices.filter { !FigureExtractor.isVideoFrame(figures[$0].id) }.prefix(limit)
        let frames = figures.indices.filter { FigureExtractor.isVideoFrame(figures[$0].id) }
        let room = limit - documents.count
        var keep = Set(documents)
        // Yer kaldıysa bütün belge şekilleri girmiştir, yani kare sayısı kalan yerden fazladır: dizinler ayrık ve aralıkta.
        for slot in 0..<room { keep.insert(frames[slot * frames.count / room]) }
        return figures.indices.filter { keep.contains($0) }.map { figures[$0] }
    }

    /// Sınır yüzünden desteye girmeyen kaynak görselleri için not (kırpma sessiz kalmasın); hepsi girdiyse nil.
    nonisolated static func deckFiguresNote(all: [SourceFigure], used: [SourceFigure]) -> String? {
        let dropped = all.count - used.count
        guard dropped > 0 else { return nil }
        let usedIDs = Set(used.map(\.id))
        let onlyFrames = all.allSatisfy { usedIDs.contains($0.id) || FigureExtractor.isVideoFrame($0.id) }
        return "Bir deste en fazla \(deckFigureLimit) kaynak görseli alır; \(dropped) \(onlyFrames ? "video karesi" : "görsel") bu desteye girmedi."
    }

    /// PowerPoint isteği için sunucu sınırlarına (deckSchema) uydurulmuş kopya; saklanan deste değişmez.
    /// Video karesi şekillerinden kalan `0` sayfası atılır (şema pozitif ister); uzun şekil başlığı, birleştirilmiş not
    /// ve elle düzenlenmiş metinler UTF-16 sınırına kırpılır (düzenleyici grafem sayar, sunucu UTF-16).
    nonisolated static func exportSafe(_ deck: Deck) -> Deck {
        var deck = deck
        deck.title = ServerText.prefix(deck.title, 200)
        deck.subtitle = ServerText.prefix(deck.subtitle, 300)
        deck.slides = deck.slides.map { original in
            var slide = original
            slide.title = ServerText.prefix(slide.title, 150)
            slide.notes = ServerText.prefix(slide.notes, 1500)
            slide.sourcePages = Array(slide.sourcePages.filter { $0 > 0 }.prefix(20))
            slide.bullets = slide.bullets.map { $0.map { ServerText.prefix($0, 200) } }
            slide.caption = slide.caption.map { ServerText.prefix($0, 300) }
            return slide
        }
        return deck
    }

    /// "Desteyi yeniden oluştur" formunun başlangıç hedefi: şimdiki destenin boyu (8...30, çift; Stepper adımıyla uyumlu).
    nonisolated static func suggestedSlideCount(_ deck: Deck) -> Int {
        min(30, max(8, (deck.slides.count + 1) / 2 * 2))
    }

    /// Slayttaki bölüm etiketi. Yerel ayarsız `uppercased()` Türkçede "geçişi" → "GEÇIŞI" yazar.
    nonisolated static func chapterBadge(_ title: String, language: String) -> String {
        title.uppercased(with: Locale(identifier: language == "en" ? "en_US" : "tr_TR"))
    }
}

/// Kurulum formunun kalıcı ayarları (deck.imageLevel / deck.palette / deck.style): sonraki destelerin varsayılanıdır.
nonisolated struct DeckFormDefaults: Equatable, Sendable {
    var imageLevel: Int
    var palette: String
    var style: String

    /// "Desteyi yeniden oluştur" formunun açılış değerleri: destede kayıtlı ayar varsa o, yoksa şimdiki varsayılan.
    /// Çağıran, formdan vazgeçilirse geri yazmak üzere şimdiki değeri saklar.
    func reconfiguring(_ deck: Deck) -> DeckFormDefaults {
        DeckFormDefaults(imageLevel: deck.imageLevel.map { min(2, max(0, $0)) } ?? imageLevel,
                         palette: deck.theme != nil ? deck.palette.rawValue : palette,
                         style: deck.imageStyle != nil ? deck.illustrationStyle.rawValue : style)
    }
}

nonisolated extension SourceFigure {
    /// Şekil rozetinin metni. Video karesinden gelen şekillerde sayfa yoktur (`page` 0): yalnız kaynak adı.
    var sourceLabel: String { page > 0 ? "\(documentName) · s. \(page)" : documentName }
}
