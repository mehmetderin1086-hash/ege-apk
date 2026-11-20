import XCTest

final class ReadingFlowTests: XCTestCase {
    func testHomeLightLargeTextLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedIstanbul", "-uiTestTab", "home", "-settings.theme", "light", "-uiTestFontScale", "extraLarge", "-home.layout.v2", "2"]
        app.launch()
        XCTAssertTrue(app.buttons["customizeHome"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "compactPrayerHero").firstMatch.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Açık tema büyük yazı ana ekran"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testHomeShortcutPersistsAcrossLaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedIstanbul", "-uiTestTab", "home"]
        app.launch()
        let customize = app.buttons["customizeHome"]
        XCTAssertTrue(customize.waitForExistence(timeout: 15)); customize.tap()
        let picker = app.buttons["homeShortcutPicker-0"]
        for _ in 0..<4 where !picker.isHittable { app.swipeUp() }
        XCTAssertTrue(picker.isHittable); picker.tap()
        app.buttons["Dualar"].tap()
        app.buttons["Bitti"].tap()
        XCTAssertTrue(app.buttons["homeShortcut-dua"].waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["homeShortcut-dua"].waitForExistence(timeout: 15))
        app.buttons["homeShortcut-dua"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
    }

    func testHomeLayoutsAndLearningShortcut() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedIstanbul", "-uiTestTab", "home"]
        app.launch()
        let customize = app.buttons["customizeHome"]
        XCTAssertTrue(customize.waitForExistence(timeout: 15)); customize.tap()
        let reset = app.buttons["Varsayılan düzene dön"]
        for _ in 0..<5 where !reset.isHittable { app.swipeUp() }
        reset.tap()
        let cards = app.buttons["homeLayout-2"]
        for _ in 0..<5 where !cards.isHittable { app.swipeDown() }
        cards.tap(); app.buttons["Bitti"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "compactPrayerHero").firstMatch.waitForExistence(timeout: 10))
        let cardShot = XCTAttachment(screenshot: app.screenshot()); cardShot.name = "Ana ekran kartlar"; cardShot.lifetime = .keepAlways; add(cardShot)
        customize.tap()
        XCTAssertEqual(app.buttons["homeLayout-2"].value as? String, "Seçili")
        app.buttons["homeLayout-0"].tap(); app.buttons["Bitti"].tap()
        let balancedShot = XCTAttachment(screenshot: app.screenshot()); balancedShot.name = "Ana ekran dengeli"; balancedShot.lifetime = .keepAlways; add(balancedShot)
        let elifba = app.buttons["homeShortcut-elifba"]
        XCTAssertTrue(elifba.waitForExistence(timeout: 10)); elifba.tap()
        XCTAssertTrue(app.segmentedControls.buttons["Gelişim"].waitForExistence(timeout: 10))
    }

    func testReadingWorkshopAssessmentAndProgress() {
        let app = XCUIApplication(); openElifBaPractice(app)
        let entry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Okumaya geçiş atölyesi")).firstMatch
        for _ in 0..<5 where !entry.isHittable { app.swipeUp() }
        entry.tap()
        let start = app.buttons["workshopQuiz-6"]
        for _ in 0..<5 where !start.isHittable { app.swipeUp() }
        start.tap()
        for round in 0..<3 {
            let prompt = app.staticTexts["assessmentPrompt"]
            XCTAssertTrue(prompt.waitForExistence(timeout: 10))
            let correct: Int
            if prompt.label.contains("Cezimli be") { correct = 1 }
            else if prompt.label.contains("yeni ünlü") { correct = 0 }
            else { correct = 2 }
            let answer = app.buttons["assessmentOption-\(round == 0 ? (correct + 1) % 3 : correct)"]
            for _ in 0..<3 where !answer.isHittable { app.swipeUp() }
            answer.tap()
            let next = app.buttons[round == 2 ? "Sonucu gör" : "Sonraki soru"]
            for _ in 0..<4 where !next.isHittable { app.swipeUp() }
            next.tap()
        }
        XCTAssertTrue(app.staticTexts["2 / 3 doğru"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["assessmentRetry"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let progress = app.segmentedControls.buttons["Gelişim"]
        for _ in 0..<4 where !progress.isHittable { app.swipeDown() }
        progress.tap()
        XCTAssertTrue(app.staticTexts["Çalışma yolculuğun"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Elif Bâ gelişim ekranı"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    private func openElifBaPractice(_ app: XCUIApplication) {
        app.launchArguments = ["-uiTestSeedIstanbul", "-uiTestTab", "quran"]
        app.launch()
        let entry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Kur’an Öğreniyorum · Elif Bâ")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 15)); entry.tap()
        let practice = app.segmentedControls.buttons["Alıştırma"]
        XCTAssertTrue(practice.waitForExistence(timeout: 10)); practice.tap()
    }
    func testJoiningShapeQuiz() {
        let app = XCUIApplication(); openElifBaPractice(app)
        let entry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Birleşik şekilleri tanı")).firstMatch
        for _ in 0..<5 where !entry.isHittable { app.swipeUp() }
        entry.tap()
        let start = app.buttons["Birleşik şekil testine başla"]
        for _ in 0..<5 where !start.isHittable { app.swipeUp() }
        start.tap()
        let target = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "elifbaTarget-")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        let answer = app.buttons[target.identifier.replacingOccurrences(of: "elifbaTarget-", with: "elifbaOption-")]
        for _ in 0..<3 where !answer.isHittable { app.swipeUp() }
        answer.tap()
        XCTAssertTrue(app.staticTexts["Doğru!"].waitForExistence(timeout: 10))
    }
    func testChooseVowelForm() {
        let app = XCUIApplication(); openElifBaPractice(app)
        let entry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Harekeleri ayırt et")).firstMatch
        for _ in 0..<5 where !entry.isHittable { app.swipeUp() }
        entry.tap()
        let start = app.buttons["İstenen harekeli harfi bul"]
        for _ in 0..<5 where !start.isHittable { app.swipeUp() }
        start.tap()
        let target = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "vowelTarget-")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        let answer = app.buttons[target.identifier.replacingOccurrences(of: "vowelTarget-", with: "vowelOption-")]
        for _ in 0..<3 where !answer.isHittable { app.swipeUp() }
        answer.tap()
        XCTAssertTrue(app.staticTexts["Doğru!"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Harekeli harfi seç"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testVowelPracticeAndRetry() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedIstanbul", "-uiTestTab", "quran"]
        app.launch()
        let entry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Kur’an Öğreniyorum · Elif Bâ")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 15)); entry.tap()
        let practice = app.segmentedControls.buttons["Alıştırma"]
        XCTAssertTrue(practice.waitForExistence(timeout: 10)); practice.tap()
        let vowels = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Harekeleri ayırt et")).firstMatch
        for _ in 0..<4 where !vowels.isHittable { app.swipeUp() }
        vowels.tap()
        let start = app.buttons["9 soruluk hareke testi"]
        for _ in 0..<5 where !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.isHittable); start.tap()
        for round in 0..<9 {
            let target = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "vowelTarget-")).firstMatch
            XCTAssertTrue(target.waitForExistence(timeout: 10))
            let correctID = target.identifier.replacingOccurrences(of: "vowelTarget-", with: "vowelOption-")
            let answer = round == 0 ? app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@", "vowelOption-", correctID)).firstMatch : app.buttons[correctID]
            for _ in 0..<3 where !answer.isHittable { app.swipeUp() }
            answer.tap()
            let next = app.buttons[round == 8 ? "Sonucu gör" : "Sonraki soru"]
            for _ in 0..<4 where !next.isHittable { app.swipeUp() }
            next.tap()
        }
        XCTAssertTrue(app.staticTexts["8 / 9 doğru"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Hareke testi ve yanlışları tekrar"
        screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["vowelRetry"].tap()
        XCTAssertTrue(app.staticTexts["Soru 1 / 1"].waitForExistence(timeout: 10))
    }

    func testElifBaFamilyQuizAndMistakeRetry() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedIstanbul", "-uiTestTab", "quran"]
        app.launch()
        let entry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Kur’an Öğreniyorum · Elif Bâ")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
        let practice = app.segmentedControls.buttons["Alıştırma"]
        XCTAssertTrue(practice.waitForExistence(timeout: 10))
        practice.tap()
        let families = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Benzer harfleri ayırt et")).firstMatch
        for _ in 0..<4 where !families.isHittable { app.swipeUp() }
        families.tap()
        app.buttons["elifbaFamily-ba"].tap()
        let start = app.buttons["Bu harflerle çalış"]
        for _ in 0..<5 where !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.isHittable)
        start.tap()
        for round in 0..<3 {
            let target = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "elifbaTarget-")).firstMatch
            XCTAssertTrue(target.waitForExistence(timeout: 10))
            let correctID = target.identifier.replacingOccurrences(of: "elifbaTarget-", with: "elifbaOption-")
            let answer = round == 0
                ? app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@", "elifbaOption-", correctID)).firstMatch
                : app.buttons[correctID]
            for _ in 0..<3 where !answer.isHittable { app.swipeUp() }
            answer.tap()
            let next = app.buttons[round == 2 ? "Sonucu gör" : "Sonraki soru"]
            for _ in 0..<4 where !next.isHittable { app.swipeUp() }
            next.tap()
        }
        let retry = app.buttons["elifbaRetryMistakes"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        for _ in 0..<3 where !retry.isHittable { app.swipeUp() }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Elif Bâ yanlış harfi tekrar çalış"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        retry.tap()
        XCTAssertTrue(app.staticTexts["Soru 1 / 1"].waitForExistence(timeout: 10))
    }

    func testSearchHistoryAndSurahFilter() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedIstanbul", "-uiTestTab", "quran", "-uiTestSurah", "1"]
        app.launch()
        XCTAssertTrue(app.buttons["Kelime"].waitForExistence(timeout: 15))
        app.buttons["Kelime"].tap()
        let search = app.buttons["Kur’an’da ara"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        XCTAssertTrue(app.buttons["2:255"].waitForExistence(timeout: 10))
        app.buttons["2:255"].tap()
        let detail = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "DETAY GÖSTER")).firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        app.buttons["searchSurahFilter"].tap()
        app.buttons["1. Fâtiha"].tap()
        XCTAssertTrue(app.staticTexts["Sonuç bulunamadı"].waitForExistence(timeout: 10))
        app.buttons["X"].tap()
        XCTAssertTrue(app.staticTexts["Son aramalar"].waitForExistence(timeout: 10))
        app.buttons["Geçmişi temizle"].tap()
        XCTAssertFalse(app.staticTexts["Son aramalar"].exists)
    }

    func testFullOfflineAyahDetailAndNextVerse() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedIstanbul", "-uiTestTab", "quran", "-uiTestSurah", "1"]
        app.launch()
        XCTAssertTrue(app.buttons["Kelime"].waitForExistence(timeout: 15))
        app.buttons["Kelime"].tap()
        let search = app.buttons["Kur’an’da ara"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        let suggestion = app.buttons["2:255"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10))
        suggestion.tap()
        let detail = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "DETAY GÖSTER")).firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        detail.tap()
        let reference = app.staticTexts["fullAyahReference"]
        XCTAssertTrue(reference.waitForExistence(timeout: 10))
        XCTAssertTrue(reference.label.contains("2:255"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Tam çevrimdışı Bakara 255"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Sonraki ayet"].tap()
        XCTAssertTrue(reference.label.contains("2:256"))
        app.buttons["Önceki ayet"].tap()
        XCTAssertTrue(reference.label.contains("2:255"))
    }

    func testAyahSearchAndOpenResult() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedIstanbul", "-uiTestTab", "quran", "-uiTestSurah", "1"]
        app.launch()
        XCTAssertTrue(app.buttons["Kelime"].waitForExistence(timeout: 15))
        app.buttons["Kelime"].tap()
        let search = app.buttons["Kur’an’da ara"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        let suggestion = app.buttons["Fatiha 1"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10))
        suggestion.tap()
        let detail = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "DETAY GÖSTER")).firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Ayet arama sonucu"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        detail.tap()
        let reader = app.buttons["Kelime okuyucusunda aç"]
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        for _ in 0..<4 where !reader.isHittable { app.swipeUp() }
        reader.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["quran-word-1:1-1"].waitForExistence(timeout: 10))
    }

    func testSynchronizedRecitationHighlightsAndPauses() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedIstanbul", "-uiTestTab", "quran", "-uiTestSurah", "1", "-kb.sync.lastVerse", "1:1", "-kb.sync.reciter", "Alafasy_128kbps"]
        app.launch()
        let words = app.buttons["Kelime"]
        XCTAssertTrue(words.waitForExistence(timeout: 15))
        words.tap()
        let start = app.buttons["syncStart"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        let highlighted = app.descendants(matching: .any).matching(NSPredicate(format: "value == %@", "Şimdi okunuyor")).firstMatch
        XCTAssertTrue(highlighted.waitForExistence(timeout: 60))
        let pause = app.buttons["Takibi duraklat"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        pause.tap()
        XCTAssertTrue(app.buttons["Takibe devam et"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Sesle eşzamanlı ok ve kelime vurgusu"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Takibe devam et"].tap()
        app.buttons["Takibi durdur"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
    }

    func testElifBaLetterAndWritingFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedIstanbul", "-uiTestTab", "quran"]
        app.launch()
        let entry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Kur’an Öğreniyorum · Elif Bâ")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
        let letters = app.segmentedControls.buttons["Harfler"]
        XCTAssertTrue(letters.waitForExistence(timeout: 10))
        letters.tap()
        let ba = app.buttons["Be harfini öğren"]
        XCTAssertTrue(ba.waitForExistence(timeout: 10))
        for _ in 0..<2 where !ba.isHittable { app.swipeUp() }
        ba.tap()
        XCTAssertTrue(app.buttons["Harf adını dinle"].waitForExistence(timeout: 10))
        app.buttons["Harf adını dinle"].tap()
        let write = app.buttons["Parmağınla yaz"]
        for _ in 0..<5 where !write.isHittable { app.swipeUp() }
        XCTAssertTrue(write.isHittable)
        write.tap()
        XCTAssertTrue(app.staticTexts["Şeklin üzerinden parmağınla geç."].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Elif Bâ · Be yazma alanı"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Bitti"].tap()
    }

    func testStudioVoicePlaybackAndPause() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedIstanbul", "-uiTestTab", "home", "-uiTestScrollTo", "studio"]
        app.launch()
        let settings = app.buttons["Ayarlar ve bildirimler"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        let preview = app.buttons["Sesi dinle"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        for _ in 0..<3 where !preview.isHittable { app.swipeUp() }
        preview.tap()
        let pause = app.buttons["Duraklat"]
        XCTAssertTrue(pause.waitForExistence(timeout: 180))
        pause.tap()
        let resume = app.buttons["Devam et"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()
        app.buttons["Durdur"].tap()
        XCTAssertFalse(pause.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Stüdyo ses ayarları"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testThemeGallerySelectionAndDarkMode() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedIstanbul", "-uiTestTab", "home", "-uiTestScrollTo", "appearance"]
        app.launch()
        let settings = app.buttons["Ayarlar ve bildirimler"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        let gallery = app.buttons["Tema galerisi · 12 görünüm"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 10))
        gallery.tap()
        let theme = app.buttons["Ayasofya teması"]
        for _ in 0..<3 where !theme.isHittable { app.swipeUp() }
        XCTAssertTrue(theme.isHittable)
        theme.tap()
        XCTAssertEqual(theme.value as? String, "Seçili")
        app.swipeDown()
        let dark = app.buttons["Koyu"]
        for _ in 0..<3 where !dark.isHittable { app.swipeDown() }
        dark.tap()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Ayasofya teması koyu görünüm"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testThinFontReaderAndOfficialRadios() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedIstanbul", "-uiTestTab", "quran", "-uiTestFontScale", "large"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Diyanet ve Vav · Canlı Radyo"].waitForExistence(timeout: 15))
        app.buttons["Fâtiha’yı oku"].tap()
        XCTAssertTrue(app.buttons["Arapça Tilavet"].firstMatch.waitForExistence(timeout: 15))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "İnce Amiri hattı ve normal ağırlıkta Türkçe meal"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testReaderRemainsResponsiveAfterRepeatedScrolling() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedIstanbul", "-uiTestTab", "quran", "-uiTestSurah", "36", "-uiTestFontScale", "large"]
        app.launch()
        let words = app.buttons["Kelime"]
        XCTAssertTrue(words.waitForExistence(timeout: 15))
        words.tap()
        let scroll = app.scrollViews["quranReaderScroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        let initial = XCTAttachment(screenshot: app.screenshot())
        initial.name = "Büyük yazıyla Arapça ve Türkçe okuma"
        initial.lifetime = .keepAlways
        add(initial)
        scroll.pinch(withScale: 1.5, velocity: 1)
        XCTAssertFalse(app.buttons["Kapat"].exists, "Pinch must not open navigation")
        scroll.pinch(withScale: 0.8, velocity: -1)
        for _ in 0..<5 { scroll.swipeUp(velocity: .fast) }
        for _ in 0..<5 { scroll.swipeDown(velocity: .fast) }
        let library = app.buttons["Kütüphane"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()
        XCTAssertTrue(app.staticTexts["Okumaya başlayın"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Kur’an kütüphanesi, kaydırma sonrası"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
