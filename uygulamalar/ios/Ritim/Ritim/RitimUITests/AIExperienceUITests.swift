import XCTest

/// End-to-end checks for the proactive AI features with the offline stub model
/// (`RITIM_UI_TEST_AI_STUB=1`): no quota, no network, deterministic replies.
final class AIExperienceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    private func launch(preserve: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        app.launchEnvironment["RITIM_UI_TEST_AI_STUB"] = "1"
        app.launchEnvironment["RITIM_UI_TEST_LYRICS_OFFLINE"] = "1"
        if preserve { app.launchEnvironment["RITIM_UI_TEST_PRESERVE_FIXTURES"] = "1" }
        app.launch()
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    func testDailyMixAIDJAndTrackInsightFromHome() throws {
        let app = launch()
        let dailyTitle = app.staticTexts["daily.title"]
        reveal(app.otherElements["home.ai"], in: app)
        XCTAssertTrue(dailyTitle.waitForExistence(timeout: 15), "Günün karışımı kendiliğinden hazırlanmalı")
        XCTAssertEqual(dailyTitle.label, "Günün ritmi")
        capture(app, name: "AI-01-Gunun-Karisimi")

        let play = app.buttons["daily.play"]
        reveal(play, in: app)
        play.tap()
        let expand = app.buttons["player.expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))

        let preset = app.buttons["dj.preset.favorites"]
        reveal(preset, in: app)
        preset.tap()
        let note = app.staticTexts["dj.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 10), "AI DJ seti başlamalı")
        // The stub either opens the set or, with a two-track set, already extends it.
        XCTAssertTrue(note.label.contains("DJ") || note.label.contains("Set devam"), "DJ notu: \(note.label)")
        capture(app, name: "AI-02-DJ-Yayinda")

        expand.tap()
        let header = app.staticTexts["player.header"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertEqual(header.label, "AI DJ YAYINDA")
        let title = app.staticTexts["player.title"]
        XCTAssertTrue(title.exists)
        capture(app, name: "AI-03-DJ-Oynatici")

        // Skipping to the last track of the set makes the DJ append new picks.
        app.buttons["Sonraki parça"].tap()
        let insight = app.buttons["player.insight"]
        reveal(insight, in: app)
        insight.tap()
        let text = app.staticTexts["insight.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 10), "Yapay zekâ notu gelmeli")
        capture(app, name: "AI-04-Parca-Notu")
        let queue = app.buttons["insight.queueSimilar"]
        if queue.waitForExistence(timeout: 2) {
            queue.tap()
            XCTAssertTrue(app.staticTexts["insight.queued"].waitForExistence(timeout: 3) || app.images["insight.queued"].exists
                          || app.otherElements["insight.queued"].exists)
        }
        app.buttons["insight.close"].tap()

        let stop = app.buttons["player.dj.stop"]
        reveal(stop, in: app)
        stop.tap()
        let normal = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "ŞİMDİ ÇALIYOR"), object: header)
        XCTAssertEqual(XCTWaiter.wait(for: [normal], timeout: 4), .completed)
        let pause = app.buttons["player.playPause"]
        reveal(pause, in: app)
        if pause.label == "Duraklat" { pause.tap() }
    }

    @MainActor
    func testAssistantPlayActionAppliesAndConversationSurvivesRelaunch() throws {
        var app = launch()
        app.buttons["tab.assistant"].tap()
        XCTAssertTrue(app.buttons["ai.models"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["dj.preset.favorites"].waitForExistence(timeout: 3), "Karşılama ekranında AI DJ şeridi olmalı")
        capture(app, name: "AI-05-Asistan-Karsilama")
        let field = app.textFields["ai.prompt"].exists ? app.textFields["ai.prompt"] : app.textViews["ai.prompt"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Kitaplığımdan sakin bir şey çal")
        app.buttons["ai.send"].tap()
        XCTAssertTrue(app.staticTexts["ai.message.reply"].firstMatch.waitForExistence(timeout: 10))
        let applied = app.staticTexts["ai.message.applied"].firstMatch
        XCTAssertTrue(applied.waitForExistence(timeout: 3) || app.otherElements["ai.message.applied"].exists)
        XCTAssertTrue(app.buttons["player.expand"].waitForExistence(timeout: 5), "Asistan eylemi çalmayı başlatmalı")
        capture(app, name: "AI-06-Asistan-Calmaya-Basladi")
        let mini = app.buttons["miniPlayer.playPause"]
        if mini.label == "Duraklat" { mini.tap() }

        app.terminate()
        app = launch(preserve: true)
        app.buttons["tab.assistant"].tap()
        XCTAssertTrue(app.staticTexts["ai.message.reply"].firstMatch.waitForExistence(timeout: 8), "Sohbet yeniden açılışta korunmalı")
        XCTAssertTrue(app.staticTexts["ai.message.user"].firstMatch.exists)
        app.buttons["ai.clear"].tap()
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["ai.message.reply"].firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 3), .completed)
    }

    @MainActor
    func testAnimatedTabBarAndMiniPlayerSwipeSkipsTrack() throws {
        let app = launch()
        for identifier in ["tab.search", "tab.library", "tab.downloads", "tab.assistant", "tab.home"] {
            app.buttons[identifier].tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: app.buttons[identifier])
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 2), .completed, identifier)
        }
        app.buttons["Kütüphaneyi çal"].tap()
        let expand = app.buttons["player.expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        let before = expand.label
        expand.swipeLeft()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", before), object: expand)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 4), .completed, "Mini çalarda sola kaydırma sonraki parçaya geçmeli")
        capture(app, name: "AI-07-Mini-Calar-Kaydirma")
        expand.tap()
        XCTAssertTrue(app.buttons["Çaları küçült"].waitForExistence(timeout: 5))
        let artwork = app.otherElements["player.artwork"].exists ? app.otherElements["player.artwork"] : app.images["player.artwork"]
        let title = app.staticTexts["player.title"]
        let titleBefore = title.label
        if artwork.exists {
            artwork.swipeLeft()
            let next = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", titleBefore), object: title)
            XCTAssertEqual(XCTWaiter.wait(for: [next], timeout: 4), .completed, "Kapakta kaydırma sonraki parçaya geçmeli")
        }
        let pause = app.buttons["player.playPause"]
        if pause.label == "Duraklat" { pause.tap() }
        app.buttons["Çaları küçült"].tap()
    }

    @MainActor
    func testYouTubeDiscoverWithAIExpandsSearchAndLetsMeSelectResults() throws {
        let app = launch()
        app.buttons["tab.downloads"].tap()
        app.segmentedControls["downloads.section"].buttons["YouTube’da ara"].tap()
        let query = app.textFields["discover.query"]
        reveal(query, in: app)
        XCTAssertTrue(query.waitForExistence(timeout: 5), "İndir sekmesinde YouTube arama kutusu olmalı")
        query.tap(); query.typeText("sakin gitar")
        app.buttons["discover.go"].tap()

        let first = app.buttons["discover.result.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10), "Kullanıcının kendi araması sonuç vermeli")
        // The stub model proposes three similar searches that appear as filter chips.
        XCTAssertTrue(app.buttons["discover.filter.3"].waitForExistence(timeout: 10), "Yapay zekâ benzer aramalar önermeli")
        XCTAssertEqual(first.value as? String, "Seçili", "Kullanıcının kendi araması seçili başlar")
        capture(app, name: "AI-08-YouTube-Arama-Benzer")

        let count = app.staticTexts["discover.selectionCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 3))
        let before = count.label
        app.buttons["discover.filter.1"].tap()
        app.buttons["discover.selectAll"].tap()
        let more = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", before), object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [more], timeout: 3), .completed, "Benzer aramanın sonuçları da seçilebilmeli")

        let format = app.segmentedControls["discover.download.format"]
        reveal(format, in: app)
        format.buttons["MP4 · Video"].tap()
        let download = app.buttons["discover.download.selected"]
        reveal(download, in: app)
        XCTAssertTrue(download.isEnabled)
        XCTAssertTrue(download.label.contains("MP4"), download.label)
        capture(app, name: "AI-09-YouTube-Indir-MP4")
    }

    @MainActor
    func testColourfulPlaylistCardOpensHeaderWithPlayAndShuffle() throws {
        let app = launch()
        app.buttons["tab.library"].tap()
        app.buttons["Kütüphaneye ekle"].tap()
        app.buttons["Yeni çalma listesi"].tap()
        let field = app.textFields["Liste adı"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Renkli liste")
        app.buttons["Oluştur"].tap()
        let card = app.buttons["Renkli liste"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Yeni liste kartı kitaplıkta görünmeli")
        capture(app, name: "Liste-Karti-Renkli")
        card.tap()
        XCTAssertTrue(app.staticTexts["playlist.header.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["playlist.play"].exists)
        XCTAssertTrue(app.buttons["playlist.shuffle"].exists)
        XCTAssertFalse(app.buttons["playlist.play"].isEnabled, "Boş listede çal kapalı olmalı")
        capture(app, name: "Liste-Detay-Renkli")

        app.buttons["playlist.smartMix"].tap()
        XCTAssertTrue(app.buttons["mix.result.0"].waitForExistence(timeout: 10), "Akıllı mix yeni şarkı önermeli")
        XCTAssertTrue(app.buttons["mix.download.selected"].waitForExistence(timeout: 5))
        capture(app, name: "Liste-Akilli-Mix")
    }

    @MainActor
    func testChangingThemeKeepsSettingsAndTabOpen() throws {
        let app = launch()
        app.buttons["tab.downloads"].tap()
        app.buttons["downloads.settings"].tap()
        let theme = app.buttons["settings.theme.rengarenk"]
        XCTAssertTrue(theme.waitForExistence(timeout: 5), "Ayarlarda tema seçimi olmalı")
        theme.tap()
        let again = app.buttons["settings.theme.rengarenk"]
        XCTAssertTrue(again.waitForExistence(timeout: 5), "Tema değişince ayarlar açık kalmalı")
        XCTAssertTrue(again.isSelected)
        capture(app, name: "Tema-Rengarenk-Ayarlar")
        app.buttons["Bitti"].firstMatch.tap()
        XCTAssertTrue(app.buttons["tab.downloads"].isSelected, "Tema sonrası aynı sekmeye dönmeli")
        app.buttons["tab.home"].tap()
        capture(app, name: "Tema-Rengarenk-Ana-Ekran")
    }

    @MainActor
    func testYouTubeResultsPageForwardBackAndFindMore() throws {
        let app = launch()
        app.buttons["tab.downloads"].tap()
        app.segmentedControls["downloads.section"].buttons["YouTube’da ara"].tap()
        let query = app.textFields["discover.query"]
        reveal(query, in: app)
        query.tap(); query.typeText("sayfa gitar")
        app.buttons["discover.go"].tap()
        let next = app.buttons["discover.page.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "10’dan fazla sonuçta sayfa düğmeleri çıkmalı")
        reveal(next, in: app)
        let label = app.staticTexts["discover.page.label"]
        XCTAssertTrue(label.label.contains("Sayfa 1"), label.label)
        next.tap()
        XCTAssertTrue(label.label.contains("Sayfa 2"), label.label)
        app.buttons["discover.page.prev"].tap()
        XCTAssertTrue(label.label.contains("Sayfa 1"), label.label)
        let more = app.buttons["discover.more"]
        reveal(more, in: app)
        XCTAssertTrue(more.exists, "Daha fazla bul düğmesi olmalı")
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - 150 && element.frame.minY > app.frame.minY + 60 { return }
            let upwards = !element.exists || element.frame.midY > app.frame.midY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: upwards ? 0.7 : 0.35))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: upwards ? 0.4 : 0.65))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
