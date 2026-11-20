import Foundation
import Testing
@testable import Ikra

/// Oynatıcı iyileştirmeleri (dalga 1 ve 2): saf mantık. Oynatıcının kendisini süren testler (kesit oturumu, ara ses,
/// kesinti, seri geçişi) sessiz ses dosyası ve sıralı çalışma gerektirdiği için `PodcastListeningTests` içindedir.
@MainActor
@Suite struct ImproveOynaticiTests {
    // MARK: - Konu başlığı büyük harfi

    @Test func chapterTitleUsesTurkishUppercase() {
        #expect(ChapterTitleCase.upper("Bitki hücresi ve iyonlar", language: .tr) == "BİTKİ HÜCRESİ VE İYONLAR")
        #expect(ChapterTitleCase.upper("ışık", language: nil) == "IŞIK")            // dili bilinmeyen bölüm Türkçe sayılır
        #expect(ChapterTitleCase.upper("", language: .tr) == "")
    }

    @Test func chapterTitleKeepsEnglishRules() {
        #expect(ChapterTitleCase.upper("Mitosis in plants", language: .en) == "MITOSIS IN PLANTS")
    }

    // MARK: - Kaydedilmemiş telaffuz

    @Test func pendingPronunciationIsTrimmedPair() throws {
        let pending = try #require(Pronunciations.pending(word: " sklera ", spoken: "sık-le-ra\n", list: []))
        #expect(pending.from == "sklera" && pending.to == "sık-le-ra")
    }

    @Test func pendingPronunciationNeedsBothFields() {
        #expect(Pronunciations.pending(word: "sklera", spoken: "", list: []) == nil)
        #expect(Pronunciations.pending(word: "sklera", spoken: "   ", list: []) == nil)
        #expect(Pronunciations.pending(word: "  ", spoken: "sık-le-ra", list: []) == nil)
    }

    @Test func pendingPronunciationRespectsFullDictionary() throws {
        let full = (0..<Pronunciations.limit).map { Pronunciation(from: "kelime\($0)", to: "okunuş") }
        #expect(Pronunciations.pending(word: "yeni", spoken: "ye-ni", list: full) == nil)
        // Var olan kelimenin (Türkçe katlamayla aynı kayıt) okunuşu dolu sözlükte de güncellenir.
        let update = try #require(Pronunciations.pending(word: "Kelime3", spoken: "ke-li-me", list: full))
        #expect(update.from == "Kelime3" && update.to == "ke-li-me")
        // Sonuç sözlüğe yazılınca kayıt sayısı değişmez, yeni okunuş başa gelir.
        let updated = Pronunciations.updated(full, from: update.from, to: update.to)
        #expect(updated.count == Pronunciations.limit && updated.first?.to == "ke-li-me")
    }

    // MARK: - İşlemler sayfası

    @Test func exportFailureIsSilentOnUserCancel() {
        #expect(EpisodeActionStatus.exportFailure(CocoaError(.userCancelled)) == nil)
        #expect(EpisodeActionStatus.exportFailure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)) == nil)
        let message = EpisodeActionStatus.exportFailure(CocoaError(.fileWriteNoPermission))
        #expect(message?.hasPrefix("Kaydedilemedi: ") == true)
    }

    // MARK: - Sahne stüdyosu kapatma onayı

    @Test func studioAsksBeforeDiscardingWork() {
        let a = ScriptTurn(speaker: .a, text: "Merhaba", style: "", sourcePage: nil)
        var edited = a
        edited.text = "Merhaba, bugün hücreyi konuşacağız"
        #expect(!SceneStudioView.hasUnsavedWork(turns: [a], original: [a], hasRendered: false))
        #expect(SceneStudioView.hasUnsavedWork(turns: [edited], original: [a], hasRendered: false))
        // Metin aynı kalsa da seslendirilmiş ama uygulanmamış hâl kaybolacak iştir.
        #expect(SceneStudioView.hasUnsavedWork(turns: [a], original: [a], hasRendered: true))
        #expect(SceneStudioView.discardMessage(hasRendered: true) != SceneStudioView.discardMessage(hasRendered: false))
    }

    // MARK: - Dalga 2: uyku zamanlayıcısı

    @Test func sleepExpiryCountsOnlyTimedTimers() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(PlayerController.sleepExpired(.until(now.addingTimeInterval(-1)), now: now))
        #expect(PlayerController.sleepExpired(.until(now), now: now))
        #expect(!PlayerController.sleepExpired(.until(now.addingTimeInterval(60)), now: now))
        // Konu/bölüm sonu zamanlayıcıları süreyle dolmaz.
        #expect(!PlayerController.sleepExpired(.endOfEpisode, now: now))
        #expect(!PlayerController.sleepExpired(.endOfChapter(2), now: now))
        #expect(!PlayerController.sleepExpired(nil, now: now))
    }

    // MARK: - Dalga 2: seri sırası

    @Test func seriesOrderSkipsNumberingGaps() {
        let a = UUID(), b = UUID(), d = UUID(), e = UUID()
        let members: [SeriesOrder.Member] = [(a, 1, .ready), (b, 2, .ready), (d, 4, .ready), (e, 5, .ready)]
        #expect(SeriesOrder.next(after: 1, members: members) == b)
        #expect(SeriesOrder.next(after: 2, members: members) == d)      // 3. bölüm silinmiş
        #expect(SeriesOrder.next(after: 5, members: members) == nil)    // son bölüm
        #expect(SeriesOrder.next(after: 2, members: Array(members.reversed())) == d)   // girdi sırası önemsiz
        #expect(SeriesOrder.next(after: 2, members: []) == nil)
    }

    @Test func seriesOrderWaitsForGeneratingAndSkipsFailed() {
        let c = UUID(), d = UUID()
        #expect(SeriesOrder.next(after: 2, members: [(c, 3, .generating), (d, 4, .ready)]) == nil)
        #expect(SeriesOrder.next(after: 2, members: [(c, 3, .failed), (d, 4, .ready)]) == d)
        #expect(SeriesOrder.next(after: 2, members: [(c, 3, .failed)]) == nil)
    }

    @Test func seriesOrderPicksFirstReadyAmongSharedIndex() {
        let first = UUID(), second = UUID(), later = UUID()
        #expect(SeriesOrder.next(after: 2, members: [(first, 3, .ready), (second, 3, .ready)]) == first)
        #expect(SeriesOrder.next(after: 2, members: [(first, 3, .generating), (second, 3, .ready)]) == second)
        #expect(SeriesOrder.next(after: 2, members: [(first, 3, .failed), (second, 3, .generating), (later, 4, .ready)]) == nil)
    }

    // MARK: - Dalga 2: konu çıkarma

    @Test func chapterRemovalShiftsResumePosition() {
        #expect(ChapterRemoval.position(100, removing: 200...300) == 100)   // kesimden önce: aynı
        #expect(ChapterRemoval.position(250, removing: 200...300) == 200)   // kesimin içinde: kesimin başı
        #expect(ChapterRemoval.position(300, removing: 200...300) == 200)
        #expect(ChapterRemoval.position(600, removing: 0...240) == 360)     // sonrasında: kesim kadar geri
        #expect(ChapterRemoval.position(0, removing: 0...240) == 0)
    }

    /// Kaydırma, sesin kesildiği aralığın aynısını kullanır: sonraki konunun başı yeni başlangıcına denk gelir.
    @Test func chapterRemovalFollowsTheEditorCut() throws {
        let starts: [Double] = [0, 240, 600]
        let turns = starts.enumerated().map { i, start in
            TimedTurn(id: i, chapterIndex: i, speaker: .a, text: "Konu \(i + 1) anlatımı", start: start, end: starts[safe: i + 1] ?? 900)
        }
        let timeline = Timeline(chapters: starts.enumerated().map { TimedChapter(id: $0, title: "Konu \($0 + 1)", start: $1) },
                                turns: turns, duration: 900)
        let first = try #require(AudioEditor.chapterCut(timeline, chapterIndex: 0))
        #expect(ChapterRemoval.position(240, removing: first) == 0)         // 2. konu başa gelir
        #expect(ChapterRemoval.position(420, removing: first) == 180)       // 2. konunun ortası
        let middle = try #require(AudioEditor.chapterCut(timeline, chapterIndex: 1))
        #expect(ChapterRemoval.position(120, removing: middle) == 120)
        #expect(ChapterRemoval.position(420, removing: middle) == 240)      // çıkarılan konudaydı: sonrakinin başı
        #expect(ChapterRemoval.position(700, removing: middle) == 340)
    }

    // MARK: - Dalga 2: notlar

    @Test func bookmarkFilterMatchesKindAndNote() {
        #expect(BookmarkFilter.confused.matches(kind: "confused", note: "", hasAudio: false))
        #expect(!BookmarkFilter.confused.matches(kind: "flag", note: "tekrar dinle", hasAudio: true))
        #expect(!BookmarkFilter.noted.matches(kind: "flag", note: "", hasAudio: false))
        #expect(!BookmarkFilter.noted.matches(kind: "flag", note: " \n", hasAudio: false))   // boşluk not sayılmaz
        #expect(BookmarkFilter.noted.matches(kind: "flag", note: "", hasAudio: true))
        #expect(BookmarkFilter.noted.matches(kind: "confused", note: "formülü ezberle", hasAudio: false))
        for kind in ["note", "confused", "flag", "siri", ""] {
            #expect(BookmarkFilter.all.matches(kind: kind, note: "", hasAudio: false))
        }
        #expect(BookmarkFilter.allCases.map(\.title) == ["Tümü", "Notlu", "Anlamadım"])
    }

    @Test func voiceNoteFileGoesOnlyWhenNoRecordKeepsIt() {
        #expect(VoiceNotes.unreferenced(["a.m4a", "b.m4a"], keptBy: [nil, "c.m4a"]) == ["a.m4a", "b.m4a"])
        // Aynı dosyayı gösteren başka kayıt varsa dosya kalır.
        #expect(VoiceNotes.unreferenced(["a.m4a", "b.m4a"], keptBy: ["a.m4a", nil]) == ["b.m4a"])
        #expect(VoiceNotes.unreferenced(["a.m4a", "a.m4a"], keptBy: []) == ["a.m4a"])
        #expect(VoiceNotes.unreferenced([], keptBy: ["a.m4a"]).isEmpty)
    }

    // MARK: - İnceleme düzeltmeleri: kesit oturumu

    /// Kesit oturumunu bitirip hemen çalan yollarda (aynı blokta pause() ardından play()) gözlemcinin yakaladığı
    /// "durdu" bilgisi bayattır: oynatıcı çalıyorsa arayüz duraklatılmış işaretlenmez.
    @Test func stalePauseObservationIsIgnoredWhilePlaying() {
        #expect(!PlayerController.confirmsPause(observedPaused: true, isPlaying: true, samePlayer: true, liveRate: 1, fading: false))
        #expect(!PlayerController.confirmsPause(observedPaused: true, isPlaying: true, samePlayer: true, liveRate: 0.75, fading: false))
        // Oynatıcı gerçekten durduysa (ses oturumunu başka bir özellik kapattı) işaretlenir.
        #expect(PlayerController.confirmsPause(observedPaused: true, isPlaying: true, samePlayer: true, liveRate: 0, fading: false))
        // Önceki koşullar aynen geçerli: bildirim "durdu" değil, zaten duraklatılmış, eski oynatıcı, ses kısılıyor.
        #expect(!PlayerController.confirmsPause(observedPaused: false, isPlaying: true, samePlayer: true, liveRate: 0, fading: false))
        #expect(!PlayerController.confirmsPause(observedPaused: true, isPlaying: false, samePlayer: true, liveRate: 0, fading: false))
        #expect(!PlayerController.confirmsPause(observedPaused: true, isPlaying: true, samePlayer: false, liveRate: 0, fading: false))
        #expect(!PlayerController.confirmsPause(observedPaused: true, isPlaying: true, samePlayer: true, liveRate: 0, fading: true))
    }

    /// "O anı dinle" (tek kesit, 29:57–30:45): kesitin dışına gezinmek oturumu bitirir.
    @Test func seekOutsideClipLeavesSession() {
        let start = 1797.0, end = 1845.0
        #expect(ClipSeek.leaves(300, clipStart: start, clipEnd: end, hasNext: false))          // çubukla 5:00'e dönüş
        #expect(ClipSeek.leaves(end, clipStart: start, clipEnd: end, hasNext: false))          // kesit sonu
        #expect(ClipSeek.leaves(2000, clipStart: start, clipEnd: end, hasNext: false))         // ilerideki nota dokunma
        #expect(!ClipSeek.leaves(1810, clipStart: start, clipEnd: end, hasNext: false))        // kesitin içi
        #expect(!ClipSeek.leaves(end - 0.1, clipStart: start, clipEnd: end, hasNext: false))
        // Kesit başında tek "15 sn geri" oturumu bozmaz; daha gerisi bozar.
        #expect(!ClipSeek.leaves(start - ClipSeek.backSlack, clipStart: start, clipEnd: end, hasNext: false))
        #expect(ClipSeek.leaves(start - ClipSeek.backSlack - 0.5, clipStart: start, clipEnd: end, hasNext: false))
        // Bölümün ilk saniyelerindeki kesitte pay sıfırın altına iner: geriye gidilecek "dışarı" yoktur.
        #expect(!ClipSeek.leaves(0, clipStart: 10, clipEnd: 58, hasNext: false))
    }

    /// Sırada kesit varken kesit sonunu aşmak oturumu bitirmez (kesit bitmiş sayılır, sıradaki gelir).
    @Test func seekPastClipEndWithMoreClipsCountsAsClipEnd() {
        #expect(!ClipSeek.leaves(70, clipStart: 10, clipEnd: 58, hasNext: true))
        #expect(ClipSeek.leaves(70, clipStart: 10, clipEnd: 58, hasNext: false))
        #expect(ClipSeek.leaves(100, clipStart: 200, clipEnd: 248, hasNext: true))             // geriye gitmek her zaman bitirir
    }
}
