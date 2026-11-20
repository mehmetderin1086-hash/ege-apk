import XCTest
@testable import BilgiArena

final class SettingsVoiceTests: XCTestCase {
    private let planet = Question(text:"Hangi gezegen kızıl gezegendir?",options:["Venüs","Mars","Dünya","Jüpiter"],answer:1,explanation:"Mars kızıl gezegen olarak bilinir.",category:.science,difficulty:.easy)
    private func suite() -> UserDefaults {
        let name = "SettingsVoiceTests-"+UUID().uuidString
        let defaults = UserDefaults(suiteName:name)!; defaults.removePersistentDomain(forName:name); return defaults
    }

    func testResolverStripsFillerWordsAndUnderstandsOrdinals() {
        XCTAssertEqual(VoiceAnswerResolver.resolve("Bence C şıkkı olsun.",for:planet),.choice(2))
        XCTAssertEqual(VoiceAnswerResolver.resolve("Sanırım cevap B'dir",for:planet),.choice(1))
        XCTAssertEqual(VoiceAnswerResolver.resolve("İkinci seçenek",for:planet),.choice(1))
        XCTAssertEqual(VoiceAnswerResolver.resolve("dördüncü şık",for:planet),.choice(3))
        XCTAssertEqual(VoiceAnswerResolver.resolve("İlk şıkkı seçiyorum",for:planet),.choice(0))
        XCTAssertEqual(VoiceAnswerResolver.resolve("Ce",for:planet),.choice(2))
        XCTAssertNil(VoiceAnswerResolver.resolve("A ya da B",for:planet))
        XCTAssertNil(VoiceAnswerResolver.resolve("bilmiyorum",for:planet))
    }

    func testNumberedOptionsKeepTextMeaningOverOrdinal() {
        let numbers = Question(text:"Üçgenin kaç kenarı vardır?",options:["4","3","2","1"],answer:1,explanation:"Üç kenar.",category:.science,difficulty:.easy)
        XCTAssertEqual(VoiceAnswerResolver.resolve("3",for:numbers),.choice(1))
        XCTAssertEqual(VoiceAnswerResolver.resolve("ikinci şık",for:numbers),.choice(1))
    }

    func testResolverForgivesSmallTranscriptionErrorsOnlyWhenUnambiguous() {
        XCTAssertEqual(VoiceAnswerResolver.resolve("Jupiterr",for:planet),.choice(3))
        XCTAssertEqual(VoiceAnswerResolver.resolve("Dünyaa",for:planet),.choice(2))
        let close = Question(text:"Hangisi?",options:["Kalem","Kelam","Masa","Kitap"],answer:0,explanation:"",category:.science,difficulty:.easy)
        XCTAssertNil(VoiceAnswerResolver.resolve("Kalam",for:close))
        XCTAssertEqual(VoiceAnswerResolver.distance("mars","marss"),1)
    }

    func testDigitsAndNumbersNeverPickAnotherNumericOption() {
        let sides = Question(text:"Karenin kaç kenarı var?",options:["3 kenar","4 kenar","5 kenar","6 kenar"],answer:1,explanation:"",category:.science,difficulty:.easy)
        XCTAssertNil(VoiceAnswerResolver.resolve("4",for:sides))
        XCTAssertEqual(VoiceAnswerResolver.resolve("4 kenar",for:sides),.choice(1))
        XCTAssertEqual(VoiceAnswerResolver.resolve("4. şık",for:sides),.choice(3))
        let powers = Question(text:"2 üzeri 2?",options:["1","2","4","8"],answer:2,explanation:"",category:.science,difficulty:.easy)
        XCTAssertNil(VoiceAnswerResolver.resolve("3",for:powers))
        let years = Question(text:"İstanbul'un fethi?",options:["1453","1071","1299","1923"],answer:0,explanation:"",category:.history,difficulty:.easy)
        XCTAssertNil(VoiceAnswerResolver.resolve("1920",for:years))
        XCTAssertEqual(VoiceAnswerResolver.resolve("1453",for:years),.choice(0))
        XCTAssertEqual(VoiceAnswerResolver.resolve("2",for:planet),.choice(1))
    }

    func testFillersNegationAndShortOptionsStayAmbiguous() {
        XCTAssertNil(VoiceAnswerResolver.resolve("Bence de",for:planet))
        XCTAssertNil(VoiceAnswerResolver.resolve("Aa.",for:planet))
        XCTAssertNil(VoiceAnswerResolver.resolve("Mars değildir",for:planet))
        XCTAssertNil(VoiceAnswerResolver.resolve("Venüs hariç",for:planet))
        let heat = Question(text:"Enerji türü?",options:["Ses","Isı","Işık","Elektrik"],answer:1,explanation:"",category:.science,difficulty:.easy)
        XCTAssertNil(VoiceAnswerResolver.resolve("Isıı",for:heat))
        let letters = Question(text:"Hangisi?",options:["0","AB","A","B"],answer:0,explanation:"",category:.science,difficulty:.easy)
        XCTAssertEqual(VoiceAnswerResolver.resolve("A şıkkı",for:letters),.choice(0))
    }

    func testLiveCommandsAcceptNaturalVariants() {
        XCTAssertEqual(LiveQuizController.command("Atla"),.skip)
        XCTAssertEqual(LiveQuizController.command("sonraki soru"),.skip)
        XCTAssertEqual(LiveQuizController.command("Bir daha oku."),.repeatQuestion)
        XCTAssertEqual(LiveQuizController.command("Bekle"),.pause)
        XCTAssertNil(LiveQuizController.command("B şıkkı"))
    }

    func testEndpointUsesConfiguredSilenceAndMaximum() {
        var short = VoiceEndpointDetector(limits:.init(silence:0.8,maximum:20))
        for _ in 0..<3 { XCTAssertFalse(short.sample(db:-20,seconds:0.1)) }
        for _ in 0..<7 { XCTAssertFalse(short.sample(db:-70,seconds:0.1)) }
        XCTAssertTrue(short.sample(db:-70,seconds:0.15))
        var bounded = VoiceEndpointDetector(limits:.init(silence:2,maximum:8))
        var elapsed = 0.0, ended = false
        while !ended && elapsed < 30 { ended = bounded.sample(db:-20,seconds:0.5); elapsed += 0.5 }
        XCTAssertEqual(elapsed,8,accuracy:0.01)
    }

    func testPreferencesDefaultsRejectUnknownValuesAndReset() {
        let defaults = suite()
        XCTAssertTrue(ArenaPreferences.haptics(defaults)); XCTAssertTrue(ArenaPreferences.voiceAutoStart(defaults))
        XCTAssertTrue(ArenaPreferences.voiceAutoStop(defaults)); XCTAssertFalse(ArenaPreferences.voiceAutoSubmit(defaults))
        XCTAssertEqual(ArenaPreferences.liveReviewSeconds(defaults),3); XCTAssertEqual(ArenaPreferences.speechRate(defaults),1)
        XCTAssertEqual(ArenaPreferences.endpoint(defaults),.init(silence:1.2,maximum:12))
        defaults.set(2.0,forKey:ArenaPreferences.Key.voiceSilence); defaults.set(20,forKey:ArenaPreferences.Key.voiceMaxSeconds)
        defaults.set(0,forKey:ArenaPreferences.Key.liveReviewSeconds); defaults.set(false,forKey:ArenaPreferences.Key.haptics)
        XCTAssertEqual(ArenaPreferences.endpoint(defaults),.init(silence:2,maximum:20))
        XCTAssertEqual(ArenaPreferences.liveReviewSeconds(defaults),0); XCTAssertFalse(ArenaPreferences.haptics(defaults))
        defaults.set(9.5,forKey:ArenaPreferences.Key.voiceSilence); defaults.set(7,forKey:ArenaPreferences.Key.liveReviewSeconds); defaults.set(3.0,forKey:ArenaPreferences.Key.speechRate)
        XCTAssertEqual(ArenaPreferences.endpoint(defaults).silence,1.2); XCTAssertEqual(ArenaPreferences.liveReviewSeconds(defaults),3); XCTAssertEqual(ArenaPreferences.speechRate(defaults),1)
        ArenaPreferences.reset(defaults)
        XCTAssertTrue(ArenaPreferences.haptics(defaults)); XCTAssertEqual(ArenaPreferences.endpoint(defaults).maximum,12)
    }

    func testFeedbackCanSkipExplanation() {
        let full = QuizNarration.feedback(planet,correct:true,last:false).map(\.text).joined(separator:" ")
        let short = QuizNarration.feedback(planet,correct:true,last:false,explain:false).map(\.text).joined(separator:" ")
        XCTAssertTrue(full.contains("kızıl gezegen")); XCTAssertFalse(short.contains("kızıl gezegen"))
        XCTAssertTrue(short.contains("Doğru cevap.")); XCTAssertTrue(short.contains("Sıradaki soruya"))
    }

    @MainActor func testResetProgressKeepsSavedCardsAndPacks() throws {
        let defaults = suite()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let pool = DailyQuestionPool(defaults:defaults,database:try QuestionPoolDatabase(url:folder.appendingPathComponent("pool.sqlite")))
        let game = GameStore(defaults:defaults,startTimer:false,pool:pool)
        game.results = [.init(id:UUID(),date:Date(),score:40,correct:2,total:3,source:"test")]
        game.history = [.init(question:planet,chosen:1,points:20)]
        game.reviews = [.init(question:planet,due:Date(),interval:1,attempts:1,correct:0)]
        game.saved = [planet]; game.persist()
        XCTAssertGreaterThan(game.totalXP,0)
        game.resetProgress()
        XCTAssertEqual(game.totalXP,0); XCTAssertEqual(game.level,1); XCTAssertTrue(game.history.isEmpty); XCTAssertTrue(game.dueCards.isEmpty)
        XCTAssertEqual(game.saved.count,1)
        let reloaded = GameStore(defaults:defaults,startTimer:false,pool:pool)
        XCTAssertTrue(reloaded.results.isEmpty); XCTAssertEqual(reloaded.saved.count,1)
    }

    @MainActor func testResetPreferencesRestoresAudioDefaults() throws {
        let defaults = suite()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let pool = DailyQuestionPool(defaults:defaults,database:try QuestionPoolDatabase(url:folder.appendingPathComponent("pool.sqlite")))
        let game = GameStore(defaults:defaults,startTimer:false,pool:pool)
        game.soundEnabled = false; game.voiceEnabled = true
        defaults.set(false,forKey:ArenaPreferences.Key.haptics); defaults.set(true,forKey:ArenaPreferences.Key.voiceAutoSubmit)
        game.resetPreferences()
        XCTAssertTrue(game.soundEnabled); XCTAssertFalse(game.voiceEnabled)
        XCTAssertTrue(ArenaPreferences.haptics(defaults)); XCTAssertFalse(ArenaPreferences.voiceAutoSubmit(defaults))
        XCTAssertTrue(defaults.bool(forKey:"soundEnabled"))
    }

    func testVoiceCacheClearRemovesOnlyCacheFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = root.appendingPathComponent("QuestionAudio"), keep = root.appendingPathComponent("keep.txt")
        try FileManager.default.createDirectory(at:cache,withIntermediateDirectories:true)
        try Data(repeating:1,count:2048).write(to:cache.appendingPathComponent("a.audio")); try Data("x".utf8).write(to:keep)
        defer { try? FileManager.default.removeItem(at:root) }
        XCTAssertEqual(QuestionVoiceAPI.cacheBytes(in:cache),2048)
        QuestionVoiceAPI.clearCache(in:cache)
        XCTAssertEqual(QuestionVoiceAPI.cacheBytes(in:cache),0); XCTAssertTrue(FileManager.default.fileExists(atPath:keep.path))
    }
}
