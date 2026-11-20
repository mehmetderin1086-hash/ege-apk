import Foundation
import SwiftData
import Testing
@testable import Ikra

/// Sunum stüdyosu ve sesli soru iyileştirmeleri (dalga 1): saf mantık, tel biçimi ve sorgu süzgeci.
@MainActor
@Suite struct ImproveDesteCanliTests {
    // MARK: - Sesli soru

    /// Biten oturumda sayfadan çıkmadan yeniden başlatma; mikrofon izni yoksa Ayarlar (yeniden başlatmak aynı hatayla biter).
    @Test func endedSessionOffersRestartOrSettings() {
        #expect(LiveAskContext.endedAction(micDenied: false, mode: "ask") == .restart("Yeni soru sor"))
        #expect(LiveAskContext.endedAction(micDenied: false, mode: "teach") == .restart("Yeniden anlat"))
        #expect(LiveAskContext.endedAction(micDenied: true, mode: "ask") == .openSettings)
        #expect(LiveAskContext.endedAction(micDenied: true, mode: "teach") == .openSettings)
    }

    /// Görünümün sorgusu yalnız kendi bölümünün kayıtlarını getirir (bölümsüz ve başka bölüm kayıtları karışmaz).
    @Test func liveExchangeFilterSeparatesEpisodes() throws {
        let container = try ModelContainer(for: Schema(AppDataStore.modelTypes), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let first = UUID(), second = UUID()
        for (index, owner) in [first, second, first, nil].enumerated() {
            context.insert(LiveExchange(episodeID: owner, episodeTitle: "T", question: "Soru \(index)", answer: "Cevap \(index)",
                                        chapterIndex: 0, time: nil, mode: "ask"))
        }
        try context.save()
        let mine = try context.fetch(FetchDescriptor<LiveExchange>(predicate: LiveAskContext.exchangeFilter(episodeID: first)))
        #expect(mine.count == 2)
        #expect(Set(mine.map(\.question)) == ["Soru 0", "Soru 2"])
        #expect(try context.fetch(FetchDescriptor<LiveExchange>(predicate: LiveAskContext.exchangeFilter(episodeID: UUID()))).isEmpty)
    }

    // MARK: - PowerPoint tel biçimi

    /// Sunucu şeması `chapterIndex` ve `chart.unit` anahtarlarını zorunlu tutar (değer null olabilir); diğer boş alanlar yazılmaz.
    @Test func pptxWireWritesRequiredNullKeys() throws {
        var deck = StudioPreview.deck
        var chart = DeckSlide(kind: "chart", title: "Verim", chapterIndex: 0, sourcePages: [], notes: "")
        chart.chart = DeckChart(type: "bar", title: "Verim", unit: nil, labels: ["A", "B"], series: [.init(name: "Seri", values: [1, 2])])
        var withUnit = chart
        withUnit.chart?.unit = "%"
        deck.slides += [chart, withUnit]
        let request = PPTXWireRequest(deck: PPTXWireDeck(DeckAssets.exportSafe(deck)), images: [:], theme: deck.palette.exportTheme)
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        let wire = try #require(json["deck"] as? [String: Any])
        #expect(Set(wire.keys) == ["title", "subtitle", "slides"])       // tema/görsel düzeyi tel biçimine girmez
        let slides = try #require(wire["slides"] as? [[String: Any]])
        #expect(slides.count == deck.slides.count)
        #expect(deck.slides[0].chapterIndex == nil && slides[0]["chapterIndex"] is NSNull)   // kapak: anahtar var, değer null
        #expect(slides[0]["bullets"] == nil && slides[0]["chart"] == nil)                    // boş isteğe bağlı alan hiç yok
        #expect(slides[1]["chapterIndex"] as? Int == 0)
        #expect((slides[1]["bullets"] as? [String])?.count == 4)
        let units = slides.suffix(2).compactMap { $0["chart"] as? [String: Any] }
        #expect(units.count == 2 && units[0]["unit"] is NSNull && units[1]["unit"] as? String == "%")
        #expect((units[0]["series"] as? [[String: Any]])?.first?["name"] as? String == "Seri")
    }

    /// Dışa aktarma kopyası sunucu sınırlarına uyar; sınır içindeki deste değişmez.
    @Test func exportSafeFitsServerLimits() {
        let slide = DeckSlide(kind: "figure", title: String(repeating: "ş", count: 180), chapterIndex: nil, sourcePages: [0, 3],
                              notes: String(repeating: "n", count: 1700), bullets: [String(repeating: "🧬", count: 150)],
                              figureId: "kf1", caption: String(repeating: "c", count: 400))
        let safe = DeckAssets.exportSafe(Deck(title: String(repeating: "t", count: 250), subtitle: "Alt", slides: [slide]))
        #expect(safe.title.utf16.count == 200 && safe.subtitle == "Alt")
        #expect(safe.slides[0].title.utf16.count == 150)
        #expect(safe.slides[0].notes.utf16.count == 1500)
        #expect(safe.slides[0].sourcePages == [3])                         // video karesinin `0` sayfası atılır
        #expect(safe.slides[0].bullets?.first?.utf16.count == 200)         // emoji: 100 grafem = 200 UTF-16
        #expect(safe.slides[0].caption?.utf16.count == 300)
        #expect(safe.slides[0].figureId == "kf1" && safe.slides[0].kind == "figure")
        let many = DeckSlide(kind: "bullets", title: "Sayfalar", chapterIndex: 0, sourcePages: Array(1...25), notes: "", bullets: ["a", "b"])
        #expect(DeckAssets.exportSafe(Deck(title: "T", subtitle: "", slides: [many])).slides[0].sourcePages == Array(1...20))
        let deck = StudioPreview.deck
        #expect(DeckAssets.exportSafe(deck) == deck)
    }

    // MARK: - İstek sınırları (UTF-16)

    /// Sunucu (zod) UTF-16 birimi sayar: ayrışık (NFD) harfli ve emojili metin grafem sayısıyla kırpılınca sınırı aşıyordu.
    @Test func deckAndVerifyRequestsClipByUTF16() {
        let nfd = String(repeating: "o\u{308}", count: 15_000)             // 15.000 grafem, 30.000 UTF-16
        #expect(String(nfd.prefix(15_000)).utf16.count == 30_000)          // eski kırpmanın gönderdiği
        let emoji = String(repeating: "🧬", count: 6_000)                  // 6.000 grafem, 12.000 UTF-16
        let timeline = Timeline(
            chapters: (0..<17).map { TimedChapter(id: $0, title: $0 == 0 ? String(repeating: "🧬", count: 300) : "Konu \($0)", start: Double($0)) },
            turns: [TimedTurn(id: 0, chapterIndex: 0, speaker: .a, text: emoji, sourcePage: nil, start: 0, end: 1),
                    TimedTurn(id: 1, chapterIndex: 1, speaker: .b, text: "Zar", sourcePage: nil, start: 1, end: 2),
                    TimedTurn(id: 2, chapterIndex: 1, speaker: .a, text: "geçirgendir", sourcePage: nil, start: 2, end: 3)],
            duration: 3)
        let figure = SourceFigure(id: "kf1", kind: "figure", caption: String(repeating: "ş", count: 400), page: 0, documentName: "Video", table: nil)
        let request = DeckAssets.deckRequest(title: String(repeating: "t", count: 400), sourceNotes: nfd, timeline: timeline, slideCount: 14,
                                             language: "tr", includeImages: false, figures: [figure])
        #expect(request.title.utf16.count == 300)
        #expect(request.sourceNotes.utf16.count <= 15_000 && request.sourceNotes.unicodeScalars.count <= 15_000 && !request.sourceNotes.isEmpty)
        #expect(request.chapters.count == 15)                              // sunucu en fazla 15 konu kabul eder
        #expect(request.chapters[0].title.utf16.count == 300 && request.chapters[0].text.utf16.count == 6_000)
        #expect(request.chapters[1].title == "Konu 1" && request.chapters[1].text == "Zar geçirgendir")
        #expect(request.figures?.first?.caption.utf16.count == 300 && request.figures?.first?.page == 0)
        #expect(request.slideCount == 14 && request.language == "tr" && !request.includeImages)
        #expect(DeckAssets.deckRequest(title: "T", sourceNotes: "", timeline: timeline, slideCount: 8, language: "en",
                                       includeImages: true, figures: []).figures == nil)

        let verify = DeckVerifier.request(sourceNotes: nfd, deck: StudioPreview.deck)
        #expect(verify.sourceNotes.utf16.count <= 15_000 && !verify.sourceNotes.isEmpty)
        // Yalnız madde, istatistik ya da tablo içeren slaytlar denetlenir; indeks destedeki sıradır.
        #expect(!verify.slides.isEmpty && verify.slides.allSatisfy { $0.bullets?.isEmpty == false || $0.stat != nil || $0.table != nil })
        #expect(verify.slides.first?.index == 1)
    }

    // MARK: - Yeniden oluşturma formu

    @Test func suggestedSlideCountFollowsCurrentDeck() {
        func deck(_ count: Int) -> Deck {
            Deck(title: "T", subtitle: "", slides: Array(repeating: DeckSlide(kind: "bullets", title: "S", chapterIndex: 0, sourcePages: [], notes: ""), count: count))
        }
        #expect(DeckAssets.suggestedSlideCount(deck(9)) == 10)
        #expect(DeckAssets.suggestedSlideCount(deck(14)) == 14)
        #expect(DeckAssets.suggestedSlideCount(deck(24)) == 24)             // 24 slaytlık deste 14'e dönmez
        #expect(DeckAssets.suggestedSlideCount(deck(31)) == 30)
        #expect(DeckAssets.suggestedSlideCount(deck(5)) == 8)
        #expect(DeckAssets.suggestedSlideCount(deck(0)) == 8)
    }

    // MARK: - Slayt metni

    @Test func chapterBadgeUppercasesWithEpisodeLanguage() {
        #expect(DeckAssets.chapterBadge("geçiş ilişkisi", language: "tr") == "GEÇİŞ İLİŞKİSİ")
        #expect(DeckAssets.chapterBadge("Hücre zarı ve madde geçişi", language: "tr") == "HÜCRE ZARI VE MADDE GEÇİŞİ")
        #expect(DeckAssets.chapterBadge("ısı", language: "tr") == "ISI")
        #expect(DeckAssets.chapterBadge("mitosis", language: "en") == "MITOSIS")
    }

    /// Video karesinden gelen şekillerde sayfa yoktur (`page` 0): rozette ve kaynak sayfalarında "s. 0" görünmez.
    @Test func videoFrameFiguresHaveNoPageZero() {
        let caption = String(repeating: "ş", count: 190)
        let frame = SourceFigure(id: "kf1", kind: "figure", caption: caption, page: 0, documentName: "Hücre videosu", table: nil)
        let table = DeckTable(headers: ["Evre", "Yer"], rows: [["Calvin", "Stroma"]])
        let frameTable = SourceFigure(id: "kf2", kind: "table", caption: "", page: 0, documentName: "Hücre videosu", table: table)
        let paged = SourceFigure(id: "p1", kind: "photo", caption: "Yaprak", page: 4, documentName: "a.pdf", table: nil)
        #expect(frame.sourceLabel == "Hücre videosu")
        #expect(paged.sourceLabel == "a.pdf · s. 4")

        let deck = Deck(title: "T", subtitle: "", slides: [
            DeckSlide(kind: "figure", title: "Tablo", chapterIndex: 0, sourcePages: [], notes: "", figureId: "kf2"),
            DeckSlide(kind: "summary", title: "Özet", chapterIndex: nil, sourcePages: [], notes: "", bullets: ["x", "y"]),
        ])
        let result = DeckAssets.reconcile(deck, figures: [frame, frameTable, paged])
        #expect(result.slides.map(\.kind) == ["table", "figure", "figure", "summary"])
        #expect(result.slides[0].table == table && result.slides[0].sourcePages.isEmpty)   // tabloya çevrilen video karesi
        #expect(result.slides[1].figureId == "kf1" && result.slides[1].sourcePages.isEmpty)
        #expect(result.slides[1].title.utf16.count == 150 && result.slides[1].caption == caption)   // başlık sınırı 150
        #expect(result.slides[2].figureId == "p1" && result.slides[2].sourcePages == [4])

        // Nota taşınan maddeler sunucunun 1500 sınırını aşmaz.
        let crowded = Deck(title: "T", subtitle: "", slides: [
            DeckSlide(kind: "figure", title: "Foto", chapterIndex: 0, sourcePages: [], notes: String(repeating: "n", count: 1400),
                      bullets: [String(repeating: "b", count: 200), "c"], figureId: "p1"),
        ])
        let moved = DeckAssets.reconcile(crowded, figures: [paged]).slides[0]
        #expect(moved.bullets == nil && moved.notes.utf16.count == 1500 && moved.notes.hasPrefix("nnn"))
    }

    // MARK: - Dalga 2: video zamanlaması

    private func plainSlide(_ kind: String, _ chapter: Int?) -> DeckSlide {
        DeckSlide(kind: kind, title: kind, chapterIndex: chapter, sourcePages: [], notes: "")
    }

    /// Araya giren bölümsüz slayt komşularının arasına yerleşir; sonraki bölümün slaydı kendi zamanında çıkar
    /// (eskiden ara slayt sona atılıyor, sıra koruma geçişi sonraki bütün slaytları son dakikaya itiyordu: [0, 3, 164, 167, 188]).
    @Test func scheduleInterpolatesChapterlessSlideBetweenChapters() {
        let chapters = [TimedChapter(id: 0, title: "A", start: 0), TimedChapter(id: 1, title: "B", start: 100)]
        let slides = [plainSlide("title", nil), plainSlide("bullets", 0), plainSlide("quote", nil), plainSlide("bullets", 1), plainSlide("summary", nil)]
        let t = DeckVideo.schedule(slides: slides, chapters: chapters, duration: 200)
        #expect(t.count == 5 && t[0] == 0)
        #expect(t[3] == 100)
        #expect(t[1] < t[2] && t[2] < t[3])
        #expect(t[4] > 100 && t[4] < 200)
        #expect(zip(t, t.dropFirst()).allSatisfy { $1 >= $0 + 3 })

        // Bölümü zaman çizelgesinde olmayan slayt da (chapterIndex 7, iki bölüm var) aynı biçimde araya yerleşir.
        var unknown = slides
        unknown[2].chapterIndex = 7
        let u = DeckVideo.schedule(slides: unknown, chapters: chapters, duration: 200)
        #expect(u[3] == 100 && u[1] < u[2] && u[2] < u[3] && u[4] > 100 && u[4] < 200)
    }

    /// Baş ve son kuralları değişmedi: baştaki bölümsüz slaytlar ilk bölümden önce, sondaki özet sonda.
    @Test func scheduleKeepsLeadAndTailRules() {
        let chapters = [TimedChapter(id: 0, title: "A", start: 10), TimedChapter(id: 1, title: "B", start: 100)]
        let slides = [plainSlide("title", nil), plainSlide("agenda", nil), plainSlide("bullets", 0), plainSlide("table", 0),
                      plainSlide("bullets", 1), plainSlide("summary", nil)]
        let t = DeckVideo.schedule(slides: slides, chapters: chapters, duration: 200)
        #expect(t == [0, 5, 10, 55, 100, 188])
        // Hiç bölüm eşleşmiyorsa slaytlar baştan sırayla, en az 3 sn arayla dizilir.
        let none = DeckVideo.schedule(slides: [plainSlide("title", nil), plainSlide("bullets", nil), plainSlide("summary", nil)], chapters: [], duration: 60)
        #expect(none == [0, 3, 6])
        #expect(DeckVideo.schedule(slides: [], chapters: chapters, duration: 200).isEmpty)
    }

    // MARK: - Dalga 2: ders videosu

    @Test func videoExportErrorsAreReadable() {
        #expect(DeckVideo.ExportError.noAudio.errorDescription?.isEmpty == false)
        #expect(DeckVideo.ExportError.noSlides.errorDescription?.isEmpty == false)
        // Bilinen durum kendi cümlesiyle; başka hata "Video oluşturulamadı" önekiyle.
        #expect(DeckVideo.failureMessage(DeckVideo.ExportError.noAudio) == DeckVideo.ExportError.noAudio.errorDescription)
        #expect(DeckVideo.failureMessage(CocoaError(.fileWriteUnknown)).hasPrefix("Video oluşturulamadı: "))
    }

    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "deste-canli-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Modele dokunmayan görsel yolu: kaynak şekli varsa o, yoksa üretilmiş görsel, hiçbiri yoksa nil.
    @Test func slideImageURLResolvesFromDirectory() throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let figure = SourceFigure(id: "ab12cd-1", kind: "figure", caption: "Şekil", page: 2, documentName: "a.pdf", table: nil)
        let slide = DeckSlide(kind: "figure", title: "Şekil", chapterIndex: 0, sourcePages: [], notes: "", figureId: figure.id)
        #expect(DeckAssets.imageURL(for: slide, index: 3, directory: directory, figures: [figure]) == nil)

        let generated = directory.appending(path: "deck_3.png")
        try Data([1]).write(to: generated)
        #expect(DeckAssets.imageURL(for: slide, index: 3, directory: directory, figures: [figure])?.lastPathComponent == "deck_3.png")

        let cropped = FigureExtractor.figureFile(figure.id, in: directory)
        try Data([2]).write(to: cropped)
        #expect(cropped.lastPathComponent == "figure_ab12cd-1.png")
        #expect(DeckAssets.imageURL(for: slide, index: 3, directory: directory, figures: [figure])?.lastPathComponent == "figure_ab12cd-1.png")
        // Listede olmayan şekil kimliği dosyası dursa da kullanılmaz (üretilmiş görsele düşer).
        #expect(DeckAssets.imageURL(for: slide, index: 3, directory: directory, figures: [])?.lastPathComponent == "deck_3.png")
        #expect(DeckAssets.imageURL(for: plainSlide("bullets", 0), index: 9, directory: directory, figures: [figure]) == nil)
    }

    // MARK: - Dalga 2: kaynak şekiller

    private func figure(_ id: String, page: Int = 1) -> SourceFigure {
        SourceFigure(id: id, kind: "figure", caption: id, page: page, documentName: "Kaynak", table: nil)
    }

    /// Yeni belge şekilleri eskilerin yerine geçer; video kareleri (yeniden çıkarılamaz) korunur.
    @Test func figureMergeKeepsVideoFrames() {
        let frame = figure(TranscriptFormat.figureID("k1"), page: 0)
        #expect(FigureExtractor.isVideoFrame(frame.id) && !FigureExtractor.isVideoFrame("ab12cd-1") && !FigureExtractor.isVideoFrame("3"))
        let existing = [frame, figure("1"), figure("2")]
        let fresh = [figure("ab12cd-1"), figure("ab12cd-2")]
        #expect(FigureExtractor.merged(existing: existing, extracted: fresh).map(\.id) == [frame.id, "ab12cd-1", "ab12cd-2"])
        #expect(FigureExtractor.merged(existing: existing, extracted: []).map(\.id) == [frame.id])

        // Belge şekli yoksa ya da liste eskimişse yeniden kesilir.
        #expect(FigureExtractor.needsExtraction(existing: [], stale: false))
        #expect(FigureExtractor.needsExtraction(existing: [frame], stale: false))
        #expect(!FigureExtractor.needsExtraction(existing: existing, stale: false))
        #expect(FigureExtractor.needsExtraction(existing: existing, stale: true))
    }

    /// Eksik tarama: bulunanlar kullanılır ve not düşülür; hiçbir şey taranamadıysa eldeki şekiller yerinde kalır.
    @Test func partialExtractionKeepsWorkingFiguresAndExplains() {
        let frame = figure(TranscriptFormat.figureID("k1"), page: 0)
        let existing = [frame, figure("1")]
        let fresh = [figure("ab12cd-1")]
        func extraction(_ figures: [SourceFigure], failed: Int, total: Int) -> FigureExtractor.Extraction {
            FigureExtractor.Extraction(figures: figures, failedBatches: failed, totalBatches: total, run: "ab12cd")
        }
        let full = extraction(fresh, failed: 0, total: 3)
        #expect(FigureExtractor.figures(after: full, existing: existing).map(\.id) == [frame.id, "ab12cd-1"])
        #expect(FigureExtractor.note(for: full) == nil)

        let partial = extraction(fresh, failed: 1, total: 3)
        #expect(FigureExtractor.figures(after: partial, existing: existing).map(\.id) == [frame.id, "ab12cd-1"])
        #expect(FigureExtractor.note(for: partial)?.contains("(1/3)") == true)

        let allFailed = extraction([], failed: 3, total: 3)
        #expect(FigureExtractor.figures(after: allFailed, existing: existing) == existing)
        #expect(FigureExtractor.note(for: allFailed)?.contains("(3/3)") == true)
        #expect(FigureExtractor.note(for: allFailed) != FigureExtractor.note(for: extraction(fresh, failed: 3, total: 3)))

        // Taranacak sayfa bulunamadı (belge açılamadı): hiçbir şey değişmez.
        #expect(FigureExtractor.figures(after: extraction([], failed: 0, total: 0), existing: existing) == existing)
        // Tarama tam ve şekil yok: belge şekilleri boşalır, video karesi kalır.
        #expect(FigureExtractor.figures(after: extraction([], failed: 0, total: 2), existing: existing) == [frame])
    }

    /// Kaynak satırı: video karelerinden gelen şekiller varken "kaynak belge yok" uyarısı gösterilmez.
    @Test func sourceSummaryDoesNotWarnForVideoFrames() {
        let frames = [figure(TranscriptFormat.figureID("k1"), page: 0), figure(TranscriptFormat.figureID("k2"), page: 0)]
        let none = FigureExtractor.sourceSummary(documents: 0, figures: [])
        #expect(none.warning && none.text.contains("fotoğrafını ekle"))
        let video = FigureExtractor.sourceSummary(documents: 0, figures: frames)
        #expect(!video.warning && video.text == "2 kaynak görseli (video kareleri)")
        #expect(FigureExtractor.sourceSummary(documents: 0, figures: [figure("1")]).text == "1 kaynak görseli")
        let cut = FigureExtractor.sourceSummary(documents: 2, figures: frames + [figure("ab12cd-1")])
        #expect(!cut.warning && cut.text == "2 kaynak belge · 3 şekil kesildi")
        #expect(FigureExtractor.sourceSummary(documents: 1, figures: []).text == "1 kaynak belge · şekiller deste oluşturulurken kesilir")
    }

    /// Deste isteğine en fazla 30 şekil girer (sunucu sınırı); sıra korunur.
    @Test func deckFiguresRespectServerLimit() {
        let many = (0..<37).map { figure("f\($0)") }
        #expect(DeckAssets.deckFigures(many).map(\.id) == many.prefix(30).map(\.id))
        #expect(DeckAssets.deckFigures([figure("a")]).map(\.id) == ["a"])
    }

    /// Sınır aşılınca belge şekilleri önceliklidir: 30 kareli video dersine eklenen fotoğrafın şekilleri desteye girer
    /// (liste kareleri başta tutar; baştan kırpmak fotoğrafın şekillerini hep dışarıda bırakıyordu).
    @Test func deckFiguresPreferDocumentFiguresOverVideoFrames() {
        func frames(_ count: Int) -> [SourceFigure] { (0..<count).map { figure(TranscriptFormat.figureID("k\($0)"), page: 0) } }
        func documents(_ count: Int) -> [SourceFigure] { (1...count).map { figure("ab12cd-\($0)") } }
        func isFrame(_ figure: SourceFigure) -> Bool { FigureExtractor.isVideoFrame(figure.id) }

        // 30 kare + fotoğraftan 4 şekil (FigureExtractor.merged sırası: kareler başta).
        let full = FigureExtractor.merged(existing: frames(30), extracted: documents(4))
        let used = DeckAssets.deckFigures(full)
        #expect(used.count == 30)
        #expect(used.filter { !isFrame($0) }.map(\.id) == ["ab12cd-1", "ab12cd-2", "ab12cd-3", "ab12cd-4"])
        let usedIDs = Set(used.map(\.id))
        #expect(used.map(\.id) == full.map(\.id).filter { usedIDs.contains($0) })              // özgün sıra
        // Kalan 26 yer karelere dersin bütününe yayılır: baştan ve sondan kare vardır, düşenler bir uçta toplanmaz.
        let kept = used.filter(isFrame).map(\.id)
        #expect(kept.count == 26 && kept.first == TranscriptFormat.figureID("k0"))
        #expect(kept.contains(TranscriptFormat.figureID("k28")) || kept.contains(TranscriptFormat.figureID("k29")))
        let dropped = full.map(\.id).filter { !usedIDs.contains($0) }
        #expect(dropped.count == 4 && dropped.allSatisfy { FigureExtractor.isVideoFrame($0) })
        #expect(Set(dropped) != Set((26..<30).map { TranscriptFormat.figureID("k\($0)") }))

        // 26 kare + 10 şekil: şekillerin tamamı girer, kalan 20 yer karelerindir.
        let mixed = DeckAssets.deckFigures(frames(26) + documents(10))
        #expect(mixed.count == 30 && mixed.filter { !isFrame($0) }.count == 10 && mixed.filter(isFrame).count == 20)
        // Sınırın altında liste olduğu gibi kalır.
        let fits = frames(26) + documents(4)
        #expect(DeckAssets.deckFigures(fits) == fits)
        // Belge şekilleri tek başına sınırı aşarsa kareye yer kalmaz; ilk 30 şekil alınır.
        let crowded = DeckAssets.deckFigures(frames(3) + documents(33))
        #expect(crowded.map(\.id) == (1...30).map { "ab12cd-\($0)" })
        // Aynı kimlik iki kez gelse de sınır aşılmaz (sunucu 30'dan fazlasını 400 ile reddeder).
        let repeated = DeckAssets.deckFigures(Array(repeating: figure(TranscriptFormat.figureID("k0"), page: 0), count: 40))
        #expect(repeated.count == 30)
        #expect(DeckAssets.deckFigures(full, limit: 6).map(\.id)
                == [TranscriptFormat.figureID("k0"), TranscriptFormat.figureID("k15"), "ab12cd-1", "ab12cd-2", "ab12cd-3", "ab12cd-4"])
        #expect(DeckAssets.deckFigures(full, limit: 0).isEmpty)
    }

    /// Kırpma sessiz kalmaz: desteye girmeyen görsel sayısı ve türü not olarak döner; hepsi girdiyse not yok.
    @Test func deckFiguresNoteReportsDroppedFigures() {
        let frames = (0..<30).map { figure(TranscriptFormat.figureID("k\($0)"), page: 0) }
        let full = frames + (1...4).map { figure("ab12cd-\($0)") }
        #expect(DeckAssets.deckFiguresNote(all: frames, used: DeckAssets.deckFigures(frames)) == nil)
        #expect(DeckAssets.deckFiguresNote(all: full, used: DeckAssets.deckFigures(full))
                == "Bir deste en fazla 30 kaynak görseli alır; 4 video karesi bu desteye girmedi.")
        let documents = (0..<37).map { figure("f\($0)") }
        #expect(DeckAssets.deckFiguresNote(all: documents, used: DeckAssets.deckFigures(documents))
                == "Bir deste en fazla 30 kaynak görseli alır; 7 görsel bu desteye girmedi.")
    }

    /// Budama yalnız listede olmayan belge şekillerini siler; video kareleri ve başka dosyalar yerinde kalır.
    /// Etiket önbelleği duran şekil (figure_3) de kalır: etiket tekrar kartları şekli eski kimlikle açar.
    @Test func figurePruneDiscardAndStaleMarker() throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameID = TranscriptFormat.figureID("k1")
        let names = ["figure_ab12cd-1.png", "figure_ab12cd-2.png", "figure_3.png", "figure_4.png", "figure_\(frameID).png",
                     "figuremap.json", "labels_3.json", "deck_0.png", "figures.json"]
        for name in names { try Data([0]).write(to: directory.appending(path: name)) }
        func present() -> Set<String> { Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []) }

        #expect(FigureExtractor.figureID(ofFile: directory.appending(path: "figure_ab12cd-1.png")) == "ab12cd-1")
        #expect(FigureExtractor.figureID(ofFile: directory.appending(path: "figuremap.json")) == nil)
        #expect(FigureExtractor.figureID(ofFile: directory.appending(path: "deck_0.png")) == nil)

        FigureExtractor.prune(in: directory, keeping: ["ab12cd-1", "ab12cd-2"])
        #expect(present() == Set(names).subtracting(["figure_4.png"]))      // listede olmayan video karesi de durur

        // Kalıcı yapılmayan çıkarım yalnız kendi dosyalarını siler.
        let abandoned = FigureExtractor.Extraction(figures: [figure("ab12cd-2")], failedBatches: 0, totalBatches: 1, run: "ab12cd")
        FigureExtractor.discard(abandoned, in: directory)
        #expect(present() == Set(names).subtracting(["figure_4.png", "figure_ab12cd-2.png"]))

        #expect(!FigureExtractor.isStale(directory))
        FigureExtractor.markStale(directory)
        #expect(FigureExtractor.isStale(directory))
        FigureExtractor.markStale(directory)                                   // ikinci işaret sorun çıkarmaz
        FigureExtractor.clearStale(directory)
        #expect(!FigureExtractor.isStale(directory))
        FigureExtractor.clearStale(directory)                                  // işaret yokken de güvenli
        #expect(present() == Set(names).subtracting(["figure_4.png", "figure_ab12cd-2.png"]))
    }

    /// Yeniden kesimde kimlikler değişir ("3" → "<run>-<sıra>"): etiket kartının şekli ve kutuları eski kimlikle
    /// açıldığı için budamadan sağ çıkmalıdır; önbelleği olmayan eski şekil silinir.
    @Test func pruneKeepsFiguresUsedByLabelCards() throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for id in ["1", "2", "3", "ab12cd-1"] { try Data([0]).write(to: FigureExtractor.figureFile(id, in: directory)) }
        try Data("[]".utf8).write(to: FigureExtractor.labelCacheFile("3", in: directory))
        func exists(_ id: String) -> Bool { FileManager.default.fileExists(atPath: FigureExtractor.figureFile(id, in: directory).path) }

        FigureExtractor.prune(in: directory, keeping: ["ab12cd-1"])
        #expect(exists("3") && exists("ab12cd-1"))
        #expect(!exists("1") && !exists("2"))
        #expect(FileManager.default.fileExists(atPath: FigureExtractor.labelCacheFile("3", in: directory).path))
        // Bir sonraki kesimde de korunur (kart silinene dek değil, bölüm klasörü silinene dek).
        FigureExtractor.prune(in: directory, keeping: ["ff00aa-1"])
        #expect(exists("3") && !exists("ab12cd-1"))

        // Önbellek adı etiket sınavının yazdığı dosyayla aynı olmalı; ayrışırsa koruma sessizce işlemez.
        let episodeID = UUID()
        let cache = LabelCard.cacheURL(episodeID: episodeID, figureID: "ab12cd-7")
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        #expect(cache.lastPathComponent == FigureExtractor.labelCacheFile("ab12cd-7", in: directory).lastPathComponent)
    }

    /// Bırakılan (kalıcı yapılmayan) çıkarımın şekilleri silinir: "bulunan şekiller kullanıldı" notu kalmaz.
    /// Hiç şekil bulunamadıysa silinen bir şey yoktur, "eklenmedi" notu doğru kalır.
    @Test func discardedExtractionDropsUsedFiguresNote() {
        func extraction(_ figures: [SourceFigure], failed: Int) -> FigureExtractor.Extraction {
            FigureExtractor.Extraction(figures: figures, failedBatches: failed, totalBatches: 3, run: "ab12cd")
        }
        let partial = extraction([figure("ab12cd-1")], failed: 1)
        #expect(FigureExtractor.note(for: partial)?.contains("Bulunan şekiller kullanıldı") == true)
        #expect(FigureExtractor.note(afterDiscarding: partial) == nil)
        let allFailed = extraction([], failed: 3)
        #expect(FigureExtractor.note(afterDiscarding: allFailed) == FigureExtractor.note(for: allFailed))
        #expect(FigureExtractor.note(afterDiscarding: allFailed)?.contains("eklenmedi") == true)
        #expect(FigureExtractor.note(afterDiscarding: extraction([figure("ab12cd-1")], failed: 0)) == nil)
    }

    /// "Desteyi yeniden oluştur" formu destenin ayarlarıyla açılır; saklanan genel varsayılan değişmez (vazgeçince geri yazılır).
    @Test func reconfigureFormStartsFromDeckWithoutLosingDefaults() {
        let defaults = DeckFormDefaults(imageLevel: 0, palette: DeckPalette.studio.rawValue, style: DeckIllustrationStyle.textbook.rawValue)
        var deck = Deck(title: "T", subtitle: "", slides: [], theme: "ocean", imageStyle: "cutaway", imageLevel: 2)
        let form = defaults.reconfiguring(deck)
        #expect(form == DeckFormDefaults(imageLevel: 2, palette: "ocean", style: "cutaway"))
        #expect(defaults == DeckFormDefaults(imageLevel: 0, palette: "studio", style: "textbook"))   // geri yazılacak kopya
        // Ayarı kayıtlı olmayan eski deste varsayılanı ezmez; sınır dışı düzey 0...2'ye çekilir; bilinmeyen tema varsayılana düşer.
        #expect(defaults.reconfiguring(Deck(title: "T", subtitle: "", slides: [])) == defaults)
        deck.imageLevel = 9
        deck.theme = "yok"
        #expect(defaults.reconfiguring(deck) == DeckFormDefaults(imageLevel: 2, palette: "studio", style: "cutaway"))
    }

    // MARK: - Dalga 2: kaynakla doğrulama

    /// Yalnız madde, istatistik ve tablo slaytları gönderilir (kapak, şema, görsel gönderilmez).
    @Test func verifyRequestSlidesSkipUncheckableKinds() {
        let deck = StudioPreview.deck
        let indexes = DeckVerifier.requestSlides(deck).map(\.index)
        let checkable: Set<String> = ["agenda", "bullets", "table", "summary"]
        #expect(indexes == deck.slides.indices.filter { checkable.contains(deck.slides[$0].kind) })
        #expect(!indexes.isEmpty && !indexes.contains(0))
        #expect(deck.slides.contains { $0.kind == "diagram" } && deck.slides.contains { $0.kind == "image" })
        #expect(indexes.allSatisfy { !["title", "diagram", "image"].contains(deck.slides[$0].kind) })
    }

    /// 30'dan fazla denetlenebilir slayt sessizce kırpılmaz: sunucu sınırına göre partilere bölünür.
    @Test func verifyBatchesCoverEverySlide() {
        let slide = DeckSlide(kind: "bullets", title: "S", chapterIndex: 0, sourcePages: [], notes: "", bullets: ["a", "b"])
        let deck = Deck(title: "T", subtitle: "", slides: Array(repeating: slide, count: 65))
        let batches = DeckVerifier.batches(DeckVerifier.requestSlides(deck))
        #expect(batches.map(\.count) == [30, 30, 5])
        #expect(batches.flatMap { $0.map(\.index) } == Array(0..<65))
        let requests = DeckVerifier.requests(sourceNotes: "Not", deck: deck)
        #expect(requests.map(\.slides.count) == [30, 30, 5] && requests.allSatisfy { $0.sourceNotes == "Not" })
        #expect(DeckVerifier.request(sourceNotes: "Not", deck: deck).slides.count == 30)
        // Denetlenecek slayt yoksa istek de yok (sunucu en az bir slayt ister).
        let bare = Deck(title: "T", subtitle: "", slides: [plainSlide("title", nil), plainSlide("image", 0)])
        #expect(DeckVerifier.requests(sourceNotes: "Not", deck: bare).isEmpty)
        #expect(DeckVerifier.batches([]).isEmpty)
    }

    /// Denetlenmeyen slayt "temiz" görünmez; eski kayıtta (checked yok) uyarısız slayt temiz sayılmaya devam eder.
    @Test func verifyStatusSeparatesUncheckedFromClean() throws {
        let issue = DeckIssue(slideIndex: 2, text: "%40", kind: "number", note: "Kaynakta %30")
        let late = DeckIssue(slideIndex: 9, text: "x", kind: "unsupported", note: "")
        let result = DeckVerification(signature: "s", issues: [issue, late, issue], checked: [1, 2])
        #expect(DeckVerifier.status(page: 2, in: result) == .issues([issue, issue]))
        #expect(DeckVerifier.status(page: 1, in: result) == .clean)
        #expect(DeckVerifier.status(page: 5, in: result) == .unchecked)
        #expect(DeckVerifier.flaggedPages(result, slideCount: 10) == [2, 9])
        #expect(DeckVerifier.flaggedPages(result, slideCount: 6) == [2])       // deste dışına taşan indeks atılır

        // Eski biçimli deckissues.json: `checked` alanı yok.
        let legacy = try JSONDecoder().decode(DeckVerification.self, from: Data(#"""
        {"signature":"abc","issues":[{"slideIndex":2,"text":"%40","kind":"number","note":"Kaynakta %30"}]}
        """#.utf8))
        #expect(legacy.signature == "abc" && legacy.issues == [issue] && legacy.checked == nil)
        #expect(DeckVerifier.status(page: 5, in: legacy) == .clean)
        #expect(DeckVerifier.status(page: 2, in: legacy) == .issues([issue]))
        // Yeni kayıt gidiş-dönüş.
        let round = try JSONDecoder().decode(DeckVerification.self, from: JSONEncoder().encode(result))
        #expect(round.checked == [1, 2] && round.issues.count == 3)
    }

    // MARK: - Dalga 2: bölüm etiketi

    @Test func chapterTitleUsesGivenChapters() {
        let chapters = [TimedChapter(id: 0, title: "Giriş", start: 0), TimedChapter(id: 3, title: "hücre zarı", start: 40)]
        #expect(DeckAssets.chapterTitle(for: plainSlide("bullets", 3), chapters: chapters, language: "tr") == "HÜCRE ZARI")
        #expect(DeckAssets.chapterTitle(for: plainSlide("bullets", 0), chapters: chapters, language: "tr") == "GİRİŞ")
        #expect(DeckAssets.chapterTitle(for: plainSlide("bullets", 0), chapters: chapters, language: "en") == "GIRIŞ")
        #expect(DeckAssets.chapterTitle(for: plainSlide("title", nil), chapters: chapters, language: "tr") == nil)
        #expect(DeckAssets.chapterTitle(for: plainSlide("bullets", 7), chapters: chapters, language: "tr") == nil)
        #expect(DeckAssets.chapterTitle(for: plainSlide("bullets", 0), chapters: [], language: "tr") == nil)
    }
}
