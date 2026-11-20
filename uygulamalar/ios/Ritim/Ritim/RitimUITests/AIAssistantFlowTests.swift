import XCTest

final class AIAssistantFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    private func launch() throws -> XCUIApplication {
        guard ProcessInfo.processInfo.environment["RITIM_UI_TEST_AI"] == "1" else {
            throw XCTSkip("Canlı CLIProxy testi için RITIM_UI_TEST_AI=1 ve iPhone güvenli alanında asistan bağlantısı gerekli.")
        }
        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        // Intentionally unreachable legacy Mac endpoint: all AI and YouTube requests must go directly from iPhone.
        app.launchEnvironment["RITIM_SERVER_URL"] = "http://127.0.0.1:1"
        app.launch()
        XCTAssertTrue(app.buttons["tab.assistant"].waitForExistence(timeout: 10))
        app.buttons["tab.assistant"].tap()
        XCTAssertTrue(app.buttons["ai.models"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.staticTexts["iPhone’dan doğrudan · İnternet bağlantısıyla"].exists)
        return app
    }

    @MainActor
    private func select(_ name: String, in app: XCUIApplication) {
        app.buttons["ai.models"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText(name)
        let option = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        XCTAssertTrue((app.buttons["ai.models"].value as? String)?.contains(name) == true)
    }

    @MainActor
    private func selectID(_ id: String, in app: XCUIApplication) {
        app.buttons["ai.models"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText(id)
        let option = app.buttons["ai.model.\(id)"]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Canlı katalog modeli eksik: \(id)")
        if !option.isHittable { app.swipeUp() }
        option.tap()
        XCTAssertTrue(app.buttons["ai.models"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func send(_ message: String, in app: XCUIApplication) {
        let field = app.textFields["ai.prompt"].exists ? app.textFields["ai.prompt"] : app.textViews["ai.prompt"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(message)
        app.buttons["ai.send"].tap()
        XCTAssertTrue(app.staticTexts["ai.message.reply"].firstMatch.waitForExistence(timeout: 170))
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - 145 { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34)))
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    @MainActor
    func testDirectAssistantConnectionSettings() throws {
        let app = try launch()
        app.buttons["ai.connection"].tap()
        let address = app.textFields["ai.connection.url"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        XCTAssertTrue((address.value as? String)?.hasPrefix("https://") == true)
        XCTAssertTrue(app.staticTexts["Doğrudan iPhone bağlantısı"].exists)
        app.buttons["ai.connection.check"].tap()
        XCTAssertTrue(app.staticTexts["ai.connection.success"].waitForExistence(timeout: 25))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "AI-dogrudan-iPhone-baglantisi"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Bitti"].tap()
    }

    @MainActor
    func testLivePlaylistSavePlayAndRealYouTubeSearch() throws {
        let app = try launch()
        select("GPT-6 Luna", in: app)
        send("Kitapligimdaki ilk iki parcadan 'Telefon Listesi' adli bir liste oner. Tek cumle yanitla. Ayrica Adele Easy On Me icin bir YouTube aramasi oner.", in: app)
        let create = app.buttons["ai.playlist.create"]
        reveal(create, in: app)
        create.tap()
        let play = app.buttons["ai.playlist.play"]
        reveal(play, in: app)
        play.tap()
        XCTAssertTrue(app.buttons["player.expand"].waitForExistence(timeout: 5))
        let search = app.buttons["ai.search"].firstMatch
        reveal(search, in: app)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "AI-telefon-liste-ve-oynatma"; attachment.lifetime = .keepAlways; add(attachment)
        search.tap()
        let results = app.buttons["ai.download.selected"]
        // Lazy content only materializes while scrolling. Wait for search to finish first.
        _ = app.staticTexts["YouTube’da aranıyor…"].waitForExistence(timeout: 3)
        let searchDone = NSPredicate { _, _ in !app.staticTexts["YouTube’da aranıyor…"].exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: searchDone, object: app)], timeout: 65), .completed)
        reveal(results, in: app)
        XCTAssertTrue(results.isEnabled)
        XCTAssertFalse(results.label.hasPrefix("0 "))
        let found = XCTAttachment(screenshot: app.screenshot())
        found.name = "AI-gercek-YouTube-sonuclari"; found.lifetime = .keepAlways; add(found)
        app.buttons["tab.library"].tap()
        XCTAssertTrue(app.staticTexts["Kitaplığım"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLiveAstraClaudeGeminiAndPersistentModelChoice() throws {
        let app = try launch()
        for model in ["GPT-6 Astra", "Claude Sonnet 5.5", "Gemini 3.8 Flash"] {
            if app.buttons["ai.clear"].isEnabled { app.buttons["ai.clear"].tap() }
            select(model, in: app)
            send("Muzik dinlemek icin tek cumlelik kisa bir oneride bulun. Liste veya arama onerme.", in: app)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "AI-\(model)"; shot.lifetime = .keepAlways; add(shot)
        }
        app.terminate()
        app.launchEnvironment["RITIM_UI_TEST_PRESERVE_FIXTURES"] = "1"
        app.launch()
        app.buttons["tab.assistant"].tap()
        XCTAssertTrue(app.buttons["ai.models"].waitForExistence(timeout: 25))
        XCTAssertTrue((app.buttons["ai.models"].value as? String)?.contains("Gemini") == true)
    }

    @MainActor
    func testLatestStrongModelsRespondThroughDirectCLIProxy() throws {
        let app = try launch()
        let configured = ProcessInfo.processInfo.environment["RITIM_UI_TEST_AI_MODELS"] ?? "gpt-6.1-sol,claude-opus-5-5,gemini-4-argon"
        let ids = configured.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        XCTAssertFalse(ids.isEmpty)
        let count = app.staticTexts["ai.models.count"]
        XCTAssertGreaterThan(Int(count.value as? String ?? "0") ?? 0, 4, "Eski dört model sınırı kaldırılmalı")
        for id in ids {
            if app.buttons["ai.clear"].isEnabled { app.buttons["ai.clear"].tap() }
            selectID(id, in: app)
            send("Muzik dinlemek icin tek cumlelik kisa bir oneride bulun. Liste veya arama onerme.", in: app)
            let model = app.staticTexts["ai.message.model"].firstMatch
            reveal(model, in: app)
            XCTAssertEqual(model.value as? String, id, "Yanıt seçilen modelden gelmeli")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "AI-guclu-\(id)"; shot.lifetime = .keepAlways; add(shot)
        }
        let selectedName = app.buttons["ai.models"].value as? String
        app.terminate()
        app.launchEnvironment["RITIM_UI_TEST_PRESERVE_FIXTURES"] = "1"
        app.launch()
        app.buttons["tab.assistant"].tap()
        XCTAssertTrue(app.buttons["ai.models"].waitForExistence(timeout: 25))
        XCTAssertEqual(app.buttons["ai.models"].value as? String, selectedName)
    }
}
