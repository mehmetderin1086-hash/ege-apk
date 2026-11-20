import Foundation
import Testing
@testable import Ikra

/// YouTube dersi iyileştirmeleri: kütüphane satırının dar ekran düzeni, içe aktarmada önizleme–bağlantı eşleşmesi,
/// süren işte kapatma onayı.
@Suite @MainActor
struct ImproveYoutubeDersTests {
    // MARK: - Madde 1: kütüphane satırı

    @Test func rowStacksTitleOnNarrowRows() {
        #expect(VideoLessonRow.stacksTitle(rowWidth: 240, accessibilitySize: false))
        #expect(!VideoLessonRow.stacksTitle(rowWidth: 310, accessibilitySize: false))
        // Eşik dahil değil: tam 290 pt yan yana kalır.
        #expect(VideoLessonRow.stacksTitle(rowWidth: 289, accessibilitySize: false))
        #expect(!VideoLessonRow.stacksTitle(rowWidth: 290, accessibilitySize: false))
    }

    @Test func rowKeepsSideBySideUntilMeasured() {
        // Genişlik ölçülmeden (0) dar sayılmaz; yoksa her satır ilk çizimde yığılı görünürdü.
        #expect(!VideoLessonRow.stacksTitle(rowWidth: 0, accessibilitySize: false))
    }

    @Test func rowStacksTitleAtAccessibilitySizes() {
        #expect(VideoLessonRow.stacksTitle(rowWidth: 400, accessibilitySize: true))
        #expect(VideoLessonRow.stacksTitle(rowWidth: 0, accessibilitySize: true))
    }

    // MARK: - Madde 2: önizleme hangi bağlantıya ait

    @Test func previewBelongsOnlyToItsOwnLink() {
        #expect(!YouTubeImportLogic.previewIsCurrent(infoLink: nil, link: "a"))
        #expect(YouTubeImportLogic.previewIsCurrent(infoLink: "a", link: "a"))
        #expect(!YouTubeImportLogic.previewIsCurrent(infoLink: "a", link: "b"))
    }

    @Test func previewIsNeverCurrentWithoutLoadedInfo() {
        // Bilgi hiç gelmediyse boş alan da "güncel önizleme" sayılmaz.
        #expect(!YouTubeImportLogic.previewIsCurrent(infoLink: nil, link: ""))
        #expect(!YouTubeImportLogic.previewIsCurrent(infoLink: "https://youtu.be/abc", link: "https://youtu.be/abd"))
    }

    // MARK: - Madde 6: süren işte kapatma

    @Test func closeChoiceOffersBackgroundWhenJobIsFollowed() {
        let single = YouTubeImportLogic.closeChoice(hasActiveJob: true, index: 1, total: 1)
        #expect(single.canDetach)
        #expect(single.message.contains("Yarım kalan işlemler"))
        // Tek videoda sıradaki yok: sayı cümlesi eklenmez.
        #expect(!single.message.contains("başlatılmaz"))
    }

    @Test func closeChoiceCountsVideosThatWillNotStart() {
        let batch = YouTubeImportLogic.closeChoice(hasActiveJob: true, index: 2, total: 5)
        #expect(batch.canDetach)
        #expect(batch.message.contains("3 video başlatılmaz"))
        let last = YouTubeImportLogic.closeChoice(hasActiveJob: true, index: 5, total: 5)
        #expect(!last.message.contains("başlatılmaz"))
    }

    @Test func closeChoiceWithoutJobCannotDetach() {
        // İş kimliği yokken (sıraya alma, sınıf kaydı yükleme) sunucuda sürdürülecek bir şey yok.
        let queued = YouTubeImportLogic.closeChoice(hasActiveJob: false, index: 1, total: 1)
        #expect(!queued.canDetach)
        #expect(!queued.message.contains("Arka planda sürdür"))
        let between = YouTubeImportLogic.closeChoice(hasActiveJob: false, index: 2, total: 5)
        #expect(!between.canDetach)
        #expect(between.message.contains("3 video başlatılmaz"))
    }

    @Test func closeChoiceIgnoresInconsistentCounts() {
        // Sıra toplamı aşarsa (olmamalı) eksi sayı yazılmaz.
        let odd = YouTubeImportLogic.closeChoice(hasActiveJob: true, index: 3, total: 1)
        #expect(!odd.message.contains("başlatılmaz"))
    }

    // MARK: - İnceleme 2: arka plana bırakmada sıradaki videolar, kaydetme anında kapatma

    @Test func inlineDetachAsksWhenVideosWouldBeDropped() {
        // 'Video 2/5' sırasında çalışma bölümündeki düğme tek dokunuşla ayrılır, sıradaki 3 videoyu uyarısız düşürürdü.
        #expect(YouTubeImportLogic.detachNeedsConfirm(index: 2, total: 5))
        // Kaybedilecek bir şey yoksa tek dokunuş kalır.
        #expect(!YouTubeImportLogic.detachNeedsConfirm(index: 5, total: 5))
        #expect(!YouTubeImportLogic.detachNeedsConfirm(index: 1, total: 1))
        // Sıra toplamı aşarsa (olmamalı) onay açılmaz.
        #expect(!YouTubeImportLogic.detachNeedsConfirm(index: 3, total: 1))
    }

    @Test func inlineDetachAsksWhenLessonWouldMissItsCourse() {
        // Listenin son videosunda da: arka plana bırakılan video derse bağlanmaz.
        #expect(YouTubeImportLogic.detachNeedsConfirm(index: 5, total: 5, linksCourse: true))
        #expect(YouTubeImportLogic.detachNeedsConfirm(index: 1, total: 1, linksCourse: true))
    }

    @Test func runningFooterTellsHowManyVideosWillNotStart() {
        let batch = YouTubeImportLogic.runningFooter(index: 2, total: 5)
        #expect(batch.contains("sıradaki 3 video başlatılmaz"))
        #expect(batch.contains("Yarım kalan işlemler"))
        for (index, total) in [(1, 1), (5, 5), (3, 1)] {
            let quiet = YouTubeImportLogic.runningFooter(index: index, total: total)
            #expect(!quiet.contains("başlatılmaz"))
            #expect(quiet.contains("Yarım kalan işlemler"))
        }
    }

    @Test func closeChoiceWarnsDetachedVideoSkipsCourse() {
        let linked = YouTubeImportLogic.closeChoice(hasActiveJob: true, index: 2, total: 5, linksCourse: true)
        #expect(linked.canDetach)
        #expect(linked.message.contains("3 video başlatılmaz"))
        #expect(linked.message.contains("derse kendiliğinden bağlanmaz"))
        // Derse bağlanmıyorsa ya da arka plana bırakma sunulmuyorsa cümle eklenmez.
        #expect(!YouTubeImportLogic.closeChoice(hasActiveJob: true, index: 2, total: 5).message.contains("bağlanmaz"))
        #expect(!YouTubeImportLogic.closeChoice(hasActiveJob: false, index: 2, total: 5, linksCourse: true).message.contains("bağlanmaz"))
    }

    @Test func closeChoiceWhileSavingDoesNotClaimJobHasNotStarted() {
        // Kaydederken iş kimliği bırakılır; onay bitmiş işi "henüz sunucuda başlamadı" diye anlatırdı.
        let saving = YouTubeImportLogic.closeChoice(hasActiveJob: false, index: 1, total: 1, saving: true)
        #expect(!saving.canDetach)
        #expect(!saving.message.contains("başlamadı"))
        #expect(saving.message.contains("kaydediliyor"))
        #expect(saving.message.contains("kütüphanede kalır"))
        // Toplu işte sıradakiler yine başlatılmaz.
        let batch = YouTubeImportLogic.closeChoice(hasActiveJob: false, index: 2, total: 5, saving: true)
        #expect(batch.message.contains("3 video başlatılmaz"))
        // Kaydetme anında sürdürülecek iş yoktur (kimlik henüz bırakılmamış olsa bile): arka plan seçeneği ve ders uyarısı çıkmaz.
        let racing = YouTubeImportLogic.closeChoice(hasActiveJob: true, index: 1, total: 1, linksCourse: true, saving: true)
        #expect(!racing.canDetach)
        #expect(!racing.message.contains("Arka planda sürdür"))
        #expect(!racing.message.contains("bağlanmaz"))
    }

    // MARK: - Madde 7: Sor sekmesi geçmişi

    private func answered(_ n: Int) -> AskEntry {
        AskEntry(question: "Soru \(n)", answer: YouTubeAskResponse(answer: "Cevap \(n)", citations: [AskCitation(time: Double(n), quote: "Alıntı \(n)")]),
                 askedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(n)))
    }

    @Test func askHistoryPersistsOnlyAnswersAndKeepsNewest() {
        // 45 kayıt, 3'ü hata (5., 20. ve 44. sırada): 42 cevaptan son 40'ı sırayla kalır.
        let entries = (0..<45).map { n in [5, 20, 44].contains(n) ? AskEntry(question: "Soru \(n)", error: "Sunucuya ulaşılamadı") : answered(n) }
        let kept = AskHistory.persistable(entries)
        #expect(kept.count == AskHistory.limit)
        #expect(kept.allSatisfy { $0.answer != nil && $0.error == nil })
        let expected = entries.filter { $0.answer != nil }.suffix(40).map(\.id)
        #expect(kept.map(\.id) == expected)
        #expect(kept.first?.question == "Soru 2" && kept.last?.question == "Soru 43")
        // Sınırın altındaysa hiçbir cevap atılmaz.
        #expect(AskHistory.persistable([answered(1), answered(2)]).map(\.question) == ["Soru 1", "Soru 2"])
        #expect(AskHistory.persistable([]).isEmpty)
    }

    @Test func askEntriesSurviveJSONRoundTrip() throws {
        let entries = [answered(1), answered(2)]
        let decoded = try JSONDecoder().decode([AskEntry].self, from: JSONEncoder().encode(entries))
        #expect(decoded == entries)
        #expect(decoded[1].answer?.citations == [AskCitation(time: 2, quote: "Alıntı 2")])
        #expect(decoded[0].askedAt == Date(timeIntervalSince1970: 1_700_000_001))
    }

    @Test func askEntryDecodesRecordWithMissingFields() throws {
        // Kimliği ve zamanı olmayan kayıt da çözülür (bir kayıt yüzünden bütün geçmiş atılmasın).
        let json = #"[{"question":"Mitoz nedir?","answer":{"answer":"Hücre bölünmesi.","citations":[{"time":12.5,"quote":"mitoz"}]}}]"#
        let decoded = try JSONDecoder().decode([AskEntry].self, from: Data(json.utf8))
        #expect(decoded.count == 1)
        #expect(decoded[0].question == "Mitoz nedir?" && decoded[0].askedAt == nil && decoded[0].error == nil)
        #expect(decoded[0].answer?.citations.first?.time == 12.5)
    }

    @Test func askHistorySkipsOnlyTheBrokenRecord() {
        // Türü bozuk tek kayıt atlanır; sağlam kayıtlar kalır (yoksa geçmiş boş görünür, sonraki cevap dosyayı ezerdi).
        let json = #"[{"question":"İlk","answer":{"answer":"A"}},{"question":42},"çöp",{"question":"Son","answer":{"answer":"B","citations":[]}}]"#
        #expect(AskHistory.decode(Data(json.utf8)).map(\.question) == ["İlk", "Son"])
        // Dizi olmayan ya da bozuk içerik: boş geçmiş, çökme yok.
        #expect(AskHistory.decode(Data(#"{"question":"x"}"#.utf8)).isEmpty)
        #expect(AskHistory.decode(Data("bozuk".utf8)).isEmpty)
    }

    @Test func askHistoryWritesIntoExistingLessonFolder() throws {
        let folder = URL.temporaryDirectory.appending(path: "ask-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: AskHistory.fileName)
        #expect(AskHistory.read(url).isEmpty)                       // dosya yokken boş geçmiş
        let entries = [answered(1), AskEntry(question: "Hatalı", error: "Zaman aşımı"), answered(2)]
        #expect(AskHistory.write(entries, to: url))
        #expect(AskHistory.read(url) == [entries[0], entries[2]])   // hata kaydı diske girmez
    }

    @Test func askHistoryDoesNotRecreateDeletedLessonFolder() {
        // Ders silinmiş (klasörü yok): geç gelen cevap klasörü ve dosyayı yeniden oluşturmaz.
        let folder = URL.temporaryDirectory.appending(path: "ask-missing-\(UUID().uuidString)", directoryHint: .isDirectory)
        let url = folder.appending(path: AskHistory.fileName)
        #expect(!AskHistory.write([answered(1)], to: url))
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(AskHistory.read(url).isEmpty)
    }

    @Test func askHistoryFilePathIsInsideLessonFolder() {
        let id = UUID()
        let url = AskHistory.fileURL(lesson: id)
        #expect(url.lastPathComponent == "ask.json")
        #expect(url.deletingLastPathComponent() == VideoFiles.audioURL(lesson: id).deletingLastPathComponent())
    }

    @Test func askCopyTextJoinsQuestionAndAnswer() {
        #expect(AskHistory.copyText(answered(3)) == "Soru 3\n\nCevap 3")
        #expect(AskHistory.copyText(AskEntry(question: "Yalnız soru", error: "Hata")) == "Yalnız soru")
        #expect(AskHistory.copyText(AskEntry(question: "Boş cevap", answer: YouTubeAskResponse(answer: "", citations: []))) == "Boş cevap")
    }

    // MARK: - Madde 8: ses kartının yüksekliği

    @Test func audioCardHeightFollowsContentWithinLimit() {
        #expect(LessonAudioCard.fittedHeight(content: 0, limit: 420) == LessonAudioCard.minHeight)   // ölçülmeden önce
        #expect(LessonAudioCard.fittedHeight(content: 226, limit: 420) == 226)
        #expect(LessonAudioCard.fittedHeight(content: 500, limit: 420) == 420)                         // aşan kart kaydırılır
        #expect(LessonAudioCard.fittedHeight(content: 300, limit: 210) == 210)                         // yatay konum sınırı
    }

    // MARK: - Madde 9: çalan kare

    @Test func playingFrameIsLastFrameAtOrBeforeTime() {
        let starts: [Double] = [10, 50, 90]
        #expect(TranscriptFormat.index(at: 60, starts: starts) == 1)
        #expect(TranscriptFormat.index(at: 5, starts: starts) == nil)
        #expect(TranscriptFormat.index(at: 90, starts: starts) == 2)
        // Kareler sekmesi bitişsiz izler: son kareden sonra da son kare işaretli kalır.
        #expect(TranscriptFormat.currentParagraph(at: 5000, starts: starts, lastEnd: nil) == 2)
        #expect(TranscriptFormat.currentParagraph(at: 5, starts: starts, lastEnd: nil) == nil)
    }

    // MARK: - Madde 10: kütüphane sırası

    private func item(_ title: String, created: Double, opened: Double? = nil, progress: Double = 0) -> VideoLibraryOrder.Item {
        VideoLibraryOrder.Item(id: UUID(), title: title, createdAt: Date(timeIntervalSince1970: created),
                               openedAt: opened.map { Date(timeIntervalSince1970: $0) }, progress: progress)
    }

    private func titles(_ items: [VideoLibraryOrder.Item], _ sort: VideoLibrarySort) -> [String] {
        let byID = Dictionary(items.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        return VideoLibraryOrder.sorted(items, by: sort).compactMap { byID[$0] }
    }

    @Test func librarySortsByAddedDate() {
        let items = [item("Eski", created: 100), item("Yeni", created: 300), item("Orta", created: 200)]
        #expect(titles(items, .added) == ["Yeni", "Orta", "Eski"])
    }

    @Test func librarySortsRecentlyOpenedFirstAndNeverOpenedLast() {
        let items = [item("Hiç açılmadı (yeni)", created: 400), item("Dün açıldı", created: 100, opened: 900),
                     item("Bugün açıldı", created: 50, opened: 1000), item("Hiç açılmadı (eski)", created: 200)]
        #expect(titles(items, .opened) == ["Bugün açıldı", "Dün açıldı", "Hiç açılmadı (yeni)", "Hiç açılmadı (eski)"])
    }

    @Test func librarySortsUnfinishedFirst() {
        let items = [item("Başlanmadı", created: 300, progress: 0), item("Bitti", created: 400, opened: 950, progress: 1.0),
                     item("Yarım", created: 100, opened: 500, progress: 0.4), item("Yarım, daha yeni açıldı", created: 50, opened: 800, progress: 0.7)]
        #expect(titles(items, .unfinished) == ["Yarım, daha yeni açıldı", "Yarım", "Bitti", "Başlanmadı"])
        #expect(!VideoLibraryOrder.isUnfinished(0) && !VideoLibraryOrder.isUnfinished(0.01))
        #expect(VideoLibraryOrder.isUnfinished(0.5))
        #expect(!VideoLibraryOrder.isUnfinished(0.95) && !VideoLibraryOrder.isUnfinished(1))
    }

    @Test func librarySortsTitlesInTurkishOrder() {
        let items = ["Çözelti", "Atom", "İyon", "Hücre"].enumerated().map { item($0.element, created: Double($0.offset)) }
        #expect(titles(items, .title) == ["Atom", "Çözelti", "Hücre", "İyon"])
        // Türkçede ç ayrı harftir ve c'den sonra gelir (İngilizce sırada "Çay", "Cuma"dan önce olurdu).
        let turkish = ["Çay", "Dalga", "Cuma"].enumerated().map { item($0.element, created: Double($0.offset)) }
        #expect(titles(turkish, .title) == ["Cuma", "Çay", "Dalga"])
        // Büyük/küçük harf sırayı değiştirmez; sayılar değerine göre sıralanır.
        let mixed = ["ders 10", "Ders 2", "atom"].enumerated().map { item($0.element, created: Double($0.offset)) }
        #expect(titles(mixed, .title) == ["atom", "Ders 2", "ders 10"])
    }

    @Test func librarySortRawValuesStayStable() {
        // Seçim @AppStorage'da ham değerle saklanır: adlar değişirse kayıtlı tercih sessizce sıfırlanır.
        #expect(VideoLibrarySort.allCases.map(\.rawValue) == ["added", "opened", "unfinished", "title"])
        #expect(VideoLibrarySort.key == "youtube.librarySort")
    }

    // MARK: - Madde 11: podcast dönüşümü bitince

    @Test func conversionFinishDependsOnWhatUserIsDoing() {
        #expect(ConversionFinish.decide(onScreen: true, isPlaying: false) == .open)
        #expect(ConversionFinish.decide(onScreen: true, isPlaying: true) == .offer)
        #expect(ConversionFinish.decide(onScreen: false, isPlaying: false) == .silent)
        #expect(ConversionFinish.decide(onScreen: false, isPlaying: true) == .silent)
        // Duraklatılmış ama bir araç sayfasında / okuma ekranında: yine yerinden edilmez.
        #expect(ConversionFinish.decide(onScreen: true, isPlaying: false, busyElsewhere: true) == .offer)
        #expect(ConversionFinish.decide(onScreen: false, isPlaying: false, busyElsewhere: true) == .silent)
    }

    // MARK: - Madde 12: ses tercihi

    @Test func audioPreferenceWinsOnlyWhenFileExists() {
        #expect(PlayerBackend.choose(embeddable: true, webFailed: false, hasAudioFile: true, preferAudio: true) == .audio)
        #expect(PlayerBackend.choose(embeddable: true, webFailed: false, hasAudioFile: false, preferAudio: true) == .web)
        #expect(PlayerBackend.choose(embeddable: false, webFailed: false, hasAudioFile: false, preferAudio: true) == .offerAudio)
        // Tercih yokken eski davranış aynen sürer.
        #expect(PlayerBackend.choose(embeddable: true, webFailed: false, hasAudioFile: true) == .web)
        #expect(PlayerBackend.choose(embeddable: true, webFailed: false, hasAudioFile: true, preferAudio: false) == .web)
        #expect(PlayerBackend.choose(embeddable: true, webFailed: true, hasAudioFile: true) == .audio)
    }

    @Test func playerOpensInAudioWhenPreferred() throws {
        let file = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
        try Data([0]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(VideoPlayerModel(videoID: "EKGRs8q7HlA", embeddable: true, audioURL: file, preferAudio: true).backend == .audio)
        #expect(VideoPlayerModel(videoID: "EKGRs8q7HlA", embeddable: true, audioURL: file).backend == .web)
        // Tercih var ama dosya yok (silinmiş): web oynatıcı.
        let missing = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
        #expect(VideoPlayerModel(videoID: "EKGRs8q7HlA", embeddable: true, audioURL: missing, preferAudio: true).backend == .web)
    }

    @Test func audioPreferenceIsRememberedPerLesson() throws {
        let suite = "improve.youtube.audioPreference.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = UUID(), second = UUID()
        #expect(!LessonAudioPreference.get(first, defaults: defaults))
        LessonAudioPreference.set(first, true, defaults: defaults)
        LessonAudioPreference.set(first, true, defaults: defaults)     // yinelenen kayıt eklenmez
        #expect(LessonAudioPreference.get(first, defaults: defaults))
        #expect(!LessonAudioPreference.get(second, defaults: defaults))
        #expect(defaults.stringArray(forKey: LessonAudioPreference.key) == [first.uuidString])
        LessonAudioPreference.set(second, true, defaults: defaults)
        LessonAudioPreference.set(first, false, defaults: defaults)
        #expect(!LessonAudioPreference.get(first, defaults: defaults))
        #expect(LessonAudioPreference.get(second, defaults: defaults))
    }
}
