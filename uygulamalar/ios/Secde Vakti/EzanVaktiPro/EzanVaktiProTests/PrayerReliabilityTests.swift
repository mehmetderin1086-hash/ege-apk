import MapKit
import AVFoundation
import UIKit
import CoreText
import XCTest
import UserNotifications
@testable import EzanVaktiPro

final class PrayerReliabilityTests: XCTestCase {
    @MainActor
    func testThemeContrastAndPersistence() {
        func luminance(_ hex: UInt) -> Double {
            let rgb = [Double((hex >> 16) & 255), Double((hex >> 8) & 255), Double(hex & 255)].map { value -> Double in
                let x = value / 255
                return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
            }
            return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722
        }
        func contrast(_ a: UInt, _ b: UInt) -> Double {
            let x = luminance(a), y = luminance(b)
            return (max(x, y) + 0.05) / (min(x, y) + 0.05)
        }
        XCTAssertEqual(ColorTheme.allCases.count, 12)
        for theme in ColorTheme.allCases {
            XCTAssertGreaterThanOrEqual(contrast(0xFFFFFF, theme.hero.1), 4.5, theme.rawValue)
            XCTAssertGreaterThanOrEqual(contrast(0x1A1C18, theme.background.0), 4.5, theme.rawValue)
            XCTAssertGreaterThanOrEqual(contrast(0xF2F1EA, theme.background.1), 4.5, theme.rawValue)
        }
        let settings = AppSettings()
        let original = (settings.colorTheme, settings.patternEnabled, settings.cardStyle, settings.highContrast)
        defer {
            settings.colorTheme = original.0; settings.patternEnabled = original.1
            settings.cardStyle = original.2; settings.highContrast = original.3
        }
        settings.colorTheme = .ayasofya; settings.patternEnabled = false
        settings.cardStyle = "outlined"; settings.highContrast = true
        let restored = AppSettings()
        XCTAssertEqual(restored.colorTheme, .ayasofya)
        XCTAssertFalse(restored.patternEnabled)
        XCTAssertEqual(restored.cardStyle, "outlined")
        XCTAssertTrue(restored.highContrast)
    }

    func testAllNotificationSoundsArePlayableAndUnderThirtySeconds() async throws {
        XCTAssertEqual(NotificationSound.allCases.count, 25)
        for sound in NotificationSound.allCases {
            XCTAssertTrue(sound.isAvailable, sound.rawValue)
            guard let file = sound.fileName else { continue }
            let url = try XCTUnwrap(Bundle.main.url(forResource: (file as NSString).deletingPathExtension, withExtension: "caf"))
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            let playable = try await asset.load(.isPlayable)
            XCTAssertTrue(playable, file)
            XCTAssertGreaterThan(duration, 0, file)
            XCTAssertLessThan(duration, 30, file)
        }
    }

    @MainActor
    func testBundledReadingFontsAndTurkishCharacters() {
        CustomFontRegistrar.registerBundledFontsIfNeeded()
        for name in ["NotoNaskhArabic-Regular", "NotoSansArabic-Regular", "Lora-Regular", "SourceSerif4Roman-Regular", "Roboto-Regular"] {
            XCTAssertNotNil(UIFont(name: name, size: 24), name)
        }
        for name in ["NotoNaskhArabic-Regular", "NotoSansArabic-Regular"] {
            let font = CTFontCreateWithName(name as CFString, 30, nil)
            let chars = CTFontCopyCharacterSet(font) as CharacterSet
            for c in "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ".unicodeScalars { XCTAssertTrue(chars.contains(c), "\(name): \(c)") }
        }
        for name in ["Lora-Regular", "SourceSerif4Roman-Regular", "Roboto-Regular"] {
            let font = CTFontCreateWithName(name as CFString, 24, nil)
            let chars = CTFontCopyCharacterSet(font) as CharacterSet
            for c in "çÇğĞıİöÖşŞüÜ".unicodeScalars { XCTAssertTrue(chars.contains(c), "\(name): \(c)") }
        }
    }

    func testSourceLabelsDoNotClaimOfficialDataForFallbacks() {
        XCTAssertEqual(schedule(source: "diyanet").sourceTitle, "Diyanet vakitleri")
        for source in ["local-adhan", "aladhan-13", "unknown"] {
            XCTAssertTrue(schedule(source: source).sourceTitle.lowercased(with: Locale(identifier: "tr_TR")).contains("yaklaşık"))
            XCTAssertFalse(schedule(source: source).sourceTitle.contains("Diyanet"))
        }
    }

    func testDaySelectionUsesDestinationTimeZoneAcrossMidnight() {
        let schedule = schedule(source: "diyanet")
        // 21:30 UTC is already the next calendar day in Istanbul.
        let now = ISO8601DateFormatter().date(from: "2026-10-25T21:30:00Z")!
        XCTAssertEqual(schedule.day(containing: now)?.dayStart, schedule.days[0].dayStart)
        XCTAssertEqual(schedule.nextTime(after: now)?.prayer, .fajr)
    }

    @MainActor
    func testSlowerOldCityCannotOverwriteNewSelection() async {
        let provider = ControlledProvider()
        let store = PrayerTimeStore(providers: [provider], scheduler: RollingScheduler(center: SilentCenter()))
        let settings = AppSettings()
        let old = Task { await store.refresh(location: SavedLocation(name: "Eski", latitude: 41, longitude: 29), settings: settings) }
        await provider.waitUntilStarted("Eski")
        let new = Task { await store.refresh(location: SavedLocation(name: "Yeni", latitude: 40, longitude: 32), settings: settings) }
        await provider.waitUntilStarted("Yeni")
        await provider.finish("Yeni", result: schedule(source: "diyanet", place: "Yeni"))
        await new.value
        await provider.finish("Eski", result: schedule(source: "local-adhan", place: "Eski"))
        await old.value
        XCTAssertEqual(store.schedule?.placeName, "Yeni")
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isLoading)
    }

    func testEnglishWordIsNotPresentedAsTurkish() throws {
        let data = Data(#"{"id":1,"position":1,"char_type_name":"word","text_uthmani":"بَيْنَ","translation":{"text":"before it","language_name":"english"},"transliteration":{"text":"bayna","language_name":"english"}}"#.utf8)
        let word = try JSONDecoder().decode(KBWord.self, from: data)
        XCTAssertFalse(word.hasTurkishMeaning)
        XCTAssertEqual(word.turkishMeaning, "Türkçe anlam henüz yok")
        XCTAssertEqual(word.arabicDisplay, "بَيْنَ")
    }

    func testLoanwordsDoNotReceiveInventedRoots() {
        XCTAssertTrue(ArabicRootExtractor.extractRoot(from: "وَٱلْإِنجِيلَ").isEmpty)
        XCTAssertTrue(ArabicRootExtractor.extractRoot(from: "ٱلتَّوْرَىٰةَ").isEmpty)
        XCTAssertEqual(String(ArabicRootExtractor.extractRoot(from: "ٱلرَّحْمَٰنِ")), "رحم")
    }

    func testBundledVersesContainOnlyDiyanetTranslation() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "kuran_bilmek_offline", withExtension: "json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let chapters = try XCTUnwrap(object["bundled_verses"] as? [String: [[String: Any]]])
        XCTAssertFalse(chapters.isEmpty)
        for verses in chapters.values {
            for verse in verses {
                let translations = try XCTUnwrap(verse["translations"] as? [[String: Any]])
                XCTAssertEqual(translations.count, 1)
                XCTAssertEqual(translations.first?["resource_id"] as? Int, 77)
            }
        }
    }

    func testOfficialAudioCatalogHasDistinctPublisherTracks() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "official_meal_audio", withExtension: "json"))
        let tracks = try JSONDecoder().decode([OfficialMealTrack].self, from: Data(contentsOf: url))
        XCTAssertEqual(tracks.count, 1137)
        XCTAssertEqual(Set(tracks.map(\.id)).count, tracks.count)
        XCTAssertEqual(Set(tracks.map(\.voice)).count, 11)
        XCTAssertEqual(tracks.filter { $0.provider == "Diyanet Kur’an Radyo" }.count, 30)
        for track in tracks { XCTAssertEqual(URL(string: track.url)?.scheme, "https") }
    }

    @MainActor func testCompleteSurahIndexAndCorrectOfflineFallback() {
        let surahs = QuranAndLibraryView.allSurahs
        XCTAssertEqual(surahs.map(\.number), Array(1...114))
        XCTAssertEqual(surahs.reduce(0) { $0 + $1.ayahCount }, 6236)
        XCTAssertTrue(QuranAndLibraryView.offlineFallbackAyahs(for: 6).isEmpty,
                      "An unavailable En’am must never show Fatiha instead")
        let yasin = QuranAndLibraryView.offlineFallbackAyahs(for: 36)
        XCTAssertEqual(yasin.count, 83)
        XCTAssertEqual(yasin.first?.globalNumber, 3706)
        XCTAssertEqual(QuranAndLibraryView.offlineFallbackAyahs(for: 1).count, 7)
    }

    @MainActor func testTurkishAndForeignRecitersResolveTheirOwnAudio() throws {
        let center = IkraAudioAndRadioCenter.shared
        let turkish = center.famousArabicReciters.filter(\.isTurkish)
        XCTAssertEqual(turkish.count, 5)
        XCTAssertEqual(Set(turkish.compactMap { $0.ayahURL(surah: 6, ayah: 2) }).count, 5)
        for reciter in turkish {
            let url = try XCTUnwrap(reciter.ayahURL(surah: 6, ayah: 2))
            XCTAssertEqual(url.host, "kuran.diyanet.gov.tr")
            XCTAssertEqual(url.lastPathComponent, "6_2.mp3")
        }
        let ghamdi = try XCTUnwrap(center.famousArabicReciters.first { $0.id == "ar.ghamadi" })
        XCTAssertTrue(try XCTUnwrap(ghamdi.ayahURL(surah: 1, ayah: 1)).path.contains("Ghamadi_40kbps"))
        XCTAssertEqual(Set(center.liveRadioStations.map(\.id)), ["diyanet_kuran_radyo", "vav_radyo"])
    }

    private func schedule(source: String, place: String = "İstanbul") -> PrayerSchedule {
        let start = ISO8601DateFormatter().date(from: "2026-10-25T21:00:00Z")!
        return PrayerSchedule(placeName: place, latitude: 41, longitude: 29,
            timeZoneIdentifier: "Europe/Istanbul", source: source, fetchedAt: Date(),
            days: [PrayerDay(dayStart: start, times: [.init(prayer: .fajr, date: start.addingTimeInterval(6 * 3600))])])
    }
}

private actor ControlledProvider: PrayerTimeProvider {
    nonisolated let sourceIdentifier = "test"
    private var requests: [String: CheckedContinuation<PrayerSchedule, Error>] = [:]
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    func fetchSchedule(for location: SavedLocation) async throws -> PrayerSchedule {
        try await withCheckedThrowingContinuation { continuation in
            requests[location.name] = continuation
            waiters.removeValue(forKey: location.name)?.resume()
        }
    }
    func waitUntilStarted(_ name: String) async {
        if requests[name] != nil { return }
        await withCheckedContinuation { waiters[name] = $0 }
    }
    func finish(_ name: String, result: PrayerSchedule) {
        requests.removeValue(forKey: name)?.resume(returning: result)
    }
}

private struct SilentCenter: NotificationScheduling {
    func pendingNotificationRequests() async -> [UNNotificationRequest] { [] }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
    func add(_ request: UNNotificationRequest) async throws {}
}

final class StudioSpeechTests: XCTestCase {
    func testLongTurkishNarrationPreservesWordsAndBoundsRequests() {
        let text = Array(repeating: "Allah’ım, gönlüme huzur ver. Şükür ve dua ile.", count: 150).joined(separator: " ")
        let chunks = StudioSpeech.chunks(text)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { !$0.isEmpty && $0.count <= 900 })
        XCTAssertEqual(chunks.joined(separator: " "), text)
    }
    func testEmptyAndOversizedArabicToken() {
        XCTAssertTrue(StudioSpeech.chunks("  \n ").isEmpty)
        let token = String(repeating: "اللَّه", count: 800)
        let chunks = StudioSpeech.chunks(token)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 900 })
        XCTAssertEqual(chunks.joined(), token)
    }
    @MainActor func testStopCancelsPendingStudioPlayback() async {
        let player = AdhanPlayer()
        player.speakTurkish(text: "Secde Vakti. Kalbiniz huzurla, gününüz dua ile dolsun.")
        XCTAssertTrue(player.isPreparing)
        player.stop()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(player.isPreparing)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.mode, .none)
        XCTAssertNil(player.speechError)
    }
}

final class ElifBaTests: XCTestCase {
    func testCurriculumAndQuestionIntegrity() {
        XCTAssertEqual(EBCurriculum.letters.count, 28)
        XCTAssertEqual(Set(EBCurriculum.letters.map(\.id)).count, 28)
        XCTAssertEqual(EBCurriculum.letters.filter { !$0.joinsNext }.count, 6)
        XCTAssertEqual(EBCurriculum.lessons.count, 12)
        XCTAssertEqual(EBCurriculum.lessons.flatMap(\.checks).count, 36)
        for check in EBCurriculum.lessons.flatMap(\.checks) {
            XCTAssertTrue(check.choices.indices.contains(check.answer))
            XCTAssertEqual(Set(check.choices).count, check.choices.count)
        }
        for _ in 0..<20 {
            let questions = EBQuestion.make(pool: EBCurriculum.letters)
            XCTAssertEqual(questions.count, 10)
            XCTAssertEqual(Set(questions.map(\.id)).count, 10)
            for question in questions {
                XCTAssertEqual(Set(question.options.map(\.id)).count, 4)
                XCTAssertEqual(question.options.filter { $0.id == question.letter.id }.count, 1)
            }
        }
    }
    func testReviewSelectionPreservesPriorityAndEmptyPool() {
        let pool = Array(EBCurriculum.letters.prefix(12))
        let selected = EBQuestion.make(pool: pool, prioritize: true)
        XCTAssertEqual(Set(selected.map(\.id)), Set(pool.prefix(10).map(\.id)))
        XCTAssertTrue(EBQuestion.make(pool: []).isEmpty)
    }
    func testSpacedReviewIntervalsAndMistakeReset() {
        var record = EBReviewRecord()
        let now = Date(timeIntervalSince1970: 1700000000)
        for days in [1, 3, 7, 14, 30, 30] {
            record.answer(true, now: now)
            XCTAssertEqual(record.due.timeIntervalSince(now), Double(days * 86400), accuracy: 0.1)
        }
        record.answer(false, now: now)
        XCTAssertEqual(record.streak, 0)
        XCTAssertEqual(record.attempts, 7)
        XCTAssertEqual(record.correct, 6)
        XCTAssertEqual(record.due.timeIntervalSince(now), 600, accuracy: 0.1)
        record.answer(true, now: now)
        XCTAssertEqual(record.due.timeIntervalSince(now), 86400, accuracy: 0.1)
    }
    @MainActor func testProgressPersistsWithoutChangingOtherSettings() {
        let suite = "ElifBaTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("kept", forKey: "existing-user-setting")
        let store = EBStudyStore(defaults: defaults)
        store.answer(letter: "ba", correct: true)
        store.complete(1); store.complete(1)
        store.favorite("ba")
        let restored = EBStudyStore(defaults: defaults)
        XCTAssertEqual(restored.progress.completedLessons, [1])
        XCTAssertEqual(restored.progress.letters["ba"]?.attempts, 1)
        XCTAssertEqual(restored.todayAnswers, 1)
        XCTAssertTrue(restored.progress.favoriteLetters.contains("ba"))
        XCTAssertEqual(defaults.string(forKey: "existing-user-setting"), "kept")
    }
    func testAllOfflineLetterRecordingsAreDecodable() throws {
        for letter in EBCurriculum.letters {
            let url = try XCTUnwrap(Bundle.main.url(forResource: letter.id, withExtension: "mp3", subdirectory: "ElifBaAudio"), letter.id)
            let player = try AVAudioPlayer(contentsOf: url)
            XCTAssertGreaterThan(player.duration, 0.1, letter.id)
            XCTAssertLessThan(player.duration, 30, letter.id)
        }
    }
}

final class QuranSynchronizedTimingTests: XCTestCase {
    func testMediaTimeBoundariesGapsAndGroupedWords() {
        let row = QFTimingRow(surah: 1, ayah: 1, segments: [[0, 1, 100, 500], [1, 3, 700, 1200], [3, 4, 1300, 1800]])
        XCTAssertEqual(row.positions(at: 99, wordCount: 4), [])
        XCTAssertEqual(row.positions(at: 100, wordCount: 4), [1])
        XCTAssertEqual(row.positions(at: 499, wordCount: 4), [1])
        XCTAssertEqual(row.positions(at: 500, wordCount: 4), [])
        XCTAssertEqual(row.positions(at: 800, wordCount: 4), [2, 3])
        XCTAssertEqual(row.positions(at: 1800, wordCount: 4), [])
        XCTAssertEqual(row.startTime(position: 3), 0.7)
        XCTAssertNil(row.startTime(position: 5))
    }
    func testMismatchedTextDoesNotInventWordAlignment() {
        let row = QFTimingRow(surah: 1, ayah: 1, segments: [[0, 1, 0, 1000], [1, 2, 1000, 2000]])
        XCTAssertTrue(row.positions(at: 100, wordCount: 3).isEmpty)
        let invalid = QFTimingRow(surah: 1, ayah: 1, segments: [[], [-1, 2, 0, 1000], [1, 1, 1000, 2000]])
        XCTAssertTrue(invalid.positions(at: 100, wordCount: 2).isEmpty)
    }
    func testThreeBundledTimingTablesCoverQuranAndHaveValidRanges() throws {
        for reciter in QFSyncReciter.all {
            let url = try XCTUnwrap(Bundle.main.url(forResource: reciter.id, withExtension: "json", subdirectory: "QuranTiming"))
            let rows = try JSONDecoder().decode([QFTimingRow].self, from: Data(contentsOf: url))
            XCTAssertEqual(rows.count, 6236, reciter.id)
            XCTAssertEqual(Set(rows.map(\.key)).count, 6236, reciter.id)
            for row in rows {
                for s in row.segments {
                    XCTAssertEqual(s.count, 4)
                    guard s.count == 4 else { continue }
                    XCTAssertGreaterThanOrEqual(s[0], 0)
                    XCTAssertGreaterThan(s[1], s[0])
                    XCTAssertGreaterThanOrEqual(s[2], 0)
                    XCTAssertGreaterThan(s[3], s[2])
                }
            }
        }
    }
    @MainActor func testStopInvalidatesPendingFollowRequest() async {
        let sync = QFSyncPlayer()
        sync.start(verses: [])
        XCTAssertFalse(sync.isActive)
        sync.setRate(4)
        XCTAssertEqual(sync.rate, 1.25)
        sync.setRate(0.1)
        XCTAssertEqual(sync.rate, 0.5)
        sync.stop()
        XCTAssertFalse(sync.isLoading)
        XCTAssertTrue(sync.positions.isEmpty)
        XCTAssertNil(sync.focusedWordID)
    }
}

final class AyahSearchTests: XCTestCase {
    func testTurkishAndArabicNormalization() {
        XCTAssertEqual(KBAyahSearch.normalize("SABIR"), KBAyahSearch.normalize("sabır"))
        XCTAssertEqual(KBAyahSearch.normalize("İmân"), "iman")
        XCTAssertTrue(KBAyahSearch.matches("الرَّحْمَٰنِ", query: KBAyahSearch.normalize("الرحمن")))
        XCTAssertFalse(KBAyahSearch.matches("أي", query: ""))
        XCTAssertFalse(KBAyahSearch.matches("الرَّحْمَٰنِ", query: "sabir"))
    }

    func testReferencesAndBounds() throws {
        struct Database: Decodable { let chapters: [KBChapter] }
        let url = try XCTUnwrap(Bundle.main.url(forResource: "kuran_bilmek_offline", withExtension: "json"))
        let chapters = try JSONDecoder().decode(Database.self, from: Data(contentsOf: url)).chapters
        for query in ["Bakara 255", "2:255", "2/255", "Bakara suresi 255"] {
            let ref = KBAyahSearch.reference(query, chapters: chapters)
            XCTAssertEqual(ref?.surah, 2, query)
            XCTAssertEqual(ref?.ayah, 255, query)
        }
        XCTAssertEqual(KBAyahSearch.reference("Âl-i İmrân 3", chapters: chapters)?.surah, 3)
        XCTAssertNil(KBAyahSearch.reference("2:287", chapters: chapters))
        XCTAssertNil(KBAyahSearch.reference("1:0", chapters: chapters))
        XCTAssertNil(KBAyahSearch.reference("sabır", chapters: chapters))
    }

    @MainActor func testLocalReferenceAndClearResetResults() async throws {
        let store = KuranBilmekStore()
        for _ in 0..<100 where store.chapters.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        await store.performSearch(query: "Fatiha 1")
        XCTAssertEqual(store.searchResults.map(\.id), ["1:1"])
        XCTAssertEqual(store.searchTotalCount, 1)
        await store.performSearch(query: " ")
        XCTAssertTrue(store.searchResults.isEmpty)
        XCTAssertEqual(store.searchTotalCount, 0)
        XCTAssertFalse(store.isSearching)
    }
}

final class FullQuranSearchTests: XCTestCase {
    func testCompleteCorpusAndReferences() throws {
        let index = try XCTUnwrap(KBFullQuranIndex.load())
        struct Chapters: Decodable { let chapters: [KBChapter] }
        let url = try XCTUnwrap(Bundle.main.url(forResource: "kuran_bilmek_offline", withExtension: "json"))
        let chapters = try JSONDecoder().decode(Chapters.self, from: Data(contentsOf: url)).chapters
        XCTAssertEqual(index.verses.count, 6236)
        XCTAssertEqual(index.byKey.count, 6236)
        for chapter in chapters {
            let rows = index.verses.filter { $0.surah == chapter.id }
            XCTAssertEqual(rows.map(\.number), Array(1...chapter.verses_count), chapter.turkishName)
            XCTAssertTrue(rows.allSatisfy { !$0.arabic_text.isEmpty && !$0.translation.isEmpty })
        }
        XCTAssertEqual(index.search(query: "Bakara 255", chapters: chapters).map(\.id), ["2:255"])
        XCTAssertEqual(index.search(query: "Yasin 9", chapters: chapters).map(\.id), ["36:9"])
        XCTAssertEqual(index.search(query: "114:6", chapters: chapters).map(\.id), ["114:6"])
        XCTAssertTrue(index.search(query: " ", chapters: chapters).isEmpty)
        XCTAssertTrue(index.search(query: "2:287", chapters: chapters).isEmpty)
        XCTAssertFalse(index.search(query: "sabır", chapters: chapters).isEmpty)
        XCTAssertTrue(index.search(query: "الرحمن", chapters: chapters).contains { $0.id == "1:1" })
    }
    @MainActor func testFullStoreSearchAndNavigation() async throws {
        let store = KuranBilmekStore()
        for _ in 0..<100 where store.fullSearchCount == 0 { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(store.fullSearchCount, 6236)
        await store.performSearch(query: "Bakara 255")
        XCTAssertEqual(store.searchResults.map(\.id), ["2:255"])
        let ayah = try XCTUnwrap(store.fullAyah(for: "2:255"))
        XCTAssertEqual(store.adjacentFullAyah(ayah, offset: 1)?.id, "2:256")
        XCTAssertEqual(store.adjacentFullAyah(ayah, offset: -1)?.id, "2:254")
        XCTAssertNil(store.adjacentFullAyah(try XCTUnwrap(store.fullAyah(for: "1:1")), offset: -1))
        XCTAssertNil(store.adjacentFullAyah(try XCTUnwrap(store.fullAyah(for: "114:6")), offset: 1))
        XCTAssertTrue(store.searchStatus.contains("Çevrimdışı"))
    }
}

final class AyahSearchRefinementTests: XCTestCase {
    func testHistoryDeduplicatesBoundsAndIgnoresEmpty() {
        XCTAssertEqual(KBAyahSearch.updatedHistory(["sabır", "rahmet"], adding: " SABIR "), ["SABIR", "rahmet"])
        XCTAssertEqual(KBAyahSearch.updatedHistory(["rahmet"], adding: "  "), ["rahmet"])
        let history = (0..<20).reduce([String]()) { KBAyahSearch.updatedHistory($0, adding: "sorgu \($1)") }
        XCTAssertEqual(history.count, 12)
        XCTAssertEqual(history.first, "sorgu 19")
    }
    func testCommonNameSurahAndFilteredResults() throws {
        let index = try XCTUnwrap(KBFullQuranIndex.load())
        struct Chapters: Decodable { let chapters: [KBChapter] }
        let url = try XCTUnwrap(Bundle.main.url(forResource: "kuran_bilmek_offline", withExtension: "json"))
        let chapters = try JSONDecoder().decode(Chapters.self, from: Data(contentsOf: url)).chapters
        for query in ["Ayetel Kürsi", "AYETEL KURSI", "Bakara suresi 255. ayet"] {
            XCTAssertEqual(index.search(query: query, chapters: chapters).map(\.id), ["2:255"])
        }
        XCTAssertTrue(index.search(query: "Ayetel Kürsi", chapters: chapters, surahID: 1).isEmpty)
        let yasin = index.search(query: "Yasin", chapters: chapters)
        XCTAssertEqual(yasin.count, 83)
        XCTAssertTrue(yasin.allSatisfy { $0.surah == 36 })
        let results = index.search(query: "Allah", chapters: chapters, surahID: 1)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.surah == 1 })
    }
}

final class ElifBaFamilyTests: XCTestCase {
    func testFamiliesAndDistractorsStayWithinGroup() {
        XCTAssertEqual(EBLetterFamily.all.count, 9)
        for family in EBLetterFamily.all {
            XCTAssertEqual(family.letters.count, family.letterIDs.count)
            XCTAssertEqual(Set(family.letterIDs).count, family.letterIDs.count)
            let questions = EBQuestion.make(pool: family.letters, familyOnly: true)
            XCTAssertEqual(Set(questions.map(\.id)), Set(family.letterIDs))
            for question in questions {
                XCTAssertEqual(Set(question.options.map(\.id)), Set(family.letterIDs))
                XCTAssertTrue(question.options.contains { $0.id == question.letter.id })
            }
        }
    }
}

final class ElifBaVowelTests: XCTestCase {
    func testJoiningFormsAndQuizTargets() {
        XCTAssertEqual(Set(EBCurriculum.letters.filter { !$0.joinsNext }.map(\.id)), Set(["alif", "dal", "dhal", "ra", "zay", "waw"]))
        let questions = EBQuestion.make(pool: EBCurriculum.letters, formPractice: true)
        XCTAssertEqual(questions.count, 10)
        for question in questions {
            XCTAssertTrue((1...3).contains(question.formIndex))
            XCTAssertEqual(question.letter.forms.count, 4)
            XCTAssertFalse(question.letter.forms[question.formIndex].isEmpty)
            XCTAssertTrue(question.options.contains { $0.id == question.letter.id })
        }
    }

    func testBalancedQuestionsAndMarks() {
        let questions = EBVowelQuestion.make()
        XCTAssertEqual(questions.count, 9)
        XCTAssertEqual(Set(questions.map(\.id)).count, 9)
        for vowel in EBVowel.allCases {
            XCTAssertEqual(questions.filter { $0.vowel == vowel }.count, 3)
            XCTAssertTrue(questions.filter { $0.vowel == vowel }.allSatisfy { $0.text.unicodeScalars.last == vowel.mark.unicodeScalars.first })
        }
        XCTAssertEqual(EBVowel.fatha.text(for: EBCurriculum.letters[0]), "أَ")
    }
    @MainActor func testVowelProgressPersistsSeparately() throws {
        let suite = "vowel-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = EBVowelStore(defaults: defaults)
        store.record(.kasra, correct: false)
        store.record(.kasra, correct: true)
        let restored = EBVowelStore(defaults: defaults)
        XCTAssertEqual(restored.scores["kasra"]?.attempts, 2)
        XCTAssertEqual(restored.scores["kasra"]?.correct, 1)
        XCTAssertNil(defaults.data(forKey: "elifba.progress.v1"))
    }
}

final class ElifBaAssessmentTests: XCTestCase {
    func testAllLessonQuestionsAndAnswerBounds() {
        let questions = EBAssessmentQuestion.make(lessons: EBCurriculum.lessons)
        XCTAssertEqual(questions.count, 36)
        XCTAssertEqual(Set(questions.map(\.id)).count, 36)
        for question in questions {
            XCTAssertTrue(question.check.choices.indices.contains(question.check.answer))
            XCTAssertFalse(question.check.explanation.isEmpty)
        }
        let workshop = EBAssessmentQuestion.make(lessons: EBCurriculum.lessons.filter { [6,7,8,9].contains($0.id) })
        XCTAssertEqual(workshop.count, 12)
    }
    @MainActor func testRecommendationsPersistenceAndSessionLimit() throws {
        let suite = "assessment-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = EBAssessmentStore(defaults: defaults)
        store.record(lessonID: 6, correct: false)
        XCTAssertEqual(store.recommendedLessons.map(\.id), [6])
        for _ in 0..<4 { store.record(lessonID: 6, correct: true) }
        XCTAssertTrue(store.recommendedLessons.isEmpty)
        for _ in 0..<25 { store.finish(title: "Cezim", correct: 2, total: 3) }
        let restored = EBAssessmentStore(defaults: defaults)
        XCTAssertEqual(restored.progress.scores[6]?.attempts, 5)
        XCTAssertEqual(restored.progress.scores[6]?.correct, 4)
        XCTAssertEqual(restored.progress.sessions.count, 20)
        XCTAssertNil(defaults.data(forKey: "elifba.progress.v1"))
    }
}

final class HomeCustomizationTests: XCTestCase {
    func testQuickActionsRemainUniqueAndRecoverInvalidPreferences() {
        XCTAssertEqual(HomeQuickAction.selected(""), [.quran, .elifba, .tesbih])
        XCTAssertEqual(HomeQuickAction.selected("dua,dua,missing,qibla"), [.dua, .qibla, .quran])
        XCTAssertEqual(HomeQuickAction.selected("calendar,tesbih,elifba,dua"), [.calendar, .tesbih, .elifba])
        XCTAssertEqual(Set(HomeQuickAction.selected("quran,quran")).count, 3)
    }
}

final class MosqueSearchTests: XCTestCase {
    func testDistanceBoundaryDeduplicationAndSorting() {
        let center = CLLocationCoordinate2D(latitude: 41.10, longitude: 29.15)
        func item(_ name: String, _ latitude: Double, _ longitude: Double) -> MKMapItem {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: latitude, longitude: longitude)))
            item.name = name
            return item
        }
        let results = MosqueSearch.nearby([
            item("Cami", 40.82, 29.30), // Tuzla: far outside requested radius
            item("İkinci Cami", 41.12, 29.15),
            item("Yakın Cami", 41.101, 29.15),
            item("Yakın Cami", 41.101, 29.15)
        ], center: center, radius: 5000)
        XCTAssertEqual(results.map(\.name), ["Yakın Cami", "İkinci Cami"])
        XCTAssertTrue(results.allSatisfy { ($0.distanceMeters ?? .infinity) <= 5000 })
        XCTAssertTrue(MosqueSearch.nearby([item("Uzak", 40.82, 29.30)], center: center, radius: 2000).isEmpty)
    }

    @MainActor
    func testLiveBeykozSearch() async throws {
        let results = try await MosqueSearch.find(center: .init(latitude: 41.10, longitude: 29.21), radius: 5000)
        XCTAssertFalse(results.isEmpty, "Live provider should find mosques around Cumhuriyetköy")
        XCTAssertTrue(results.allSatisfy { ($0.distanceMeters ?? .infinity) <= 5000 })
        print("BEYKOZ_LIVE_RESULTS", results.map { "\($0.name):\(Int($0.distanceMeters ?? 0))m" })
    }
}
