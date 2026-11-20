import XCTest

final class DashboardUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testMeasuredListeningPersistsAndDashboardActionsWork() throws {
        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        app.launch()
        let total = app.staticTexts["dashboard.totalTime"]
        // The shelves sit above the listening card now, so scroll down to it first.
        reveal(total, in: app)
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        XCTAssertEqual(measuredSeconds(total), 0, "Eski çalma sayıları dinleme süresi olarak uydurulmamalı")
        let play = app.buttons["Kütüphaneyi çal"]
        reveal(play, in: app)
        XCTAssertTrue(play.isHittable)
        play.tap()
        let accumulating = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            measuredSeconds(total) >= 3
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [accumulating], timeout: 10), .completed)
        let pause = app.buttons["miniPlayer.playPause"]
        XCTAssertEqual(pause.label, "Duraklat")
        pause.tap()
        XCTAssertEqual(pause.label, "Çal")
        let measured = measuredSeconds(total)
        let staysPaused = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            measuredSeconds(total) > measured + 1
        }, object: nil)
        staysPaused.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [staysPaused], timeout: 2), .completed)
        capture(app, name: "Dashboard-Gercek-Dinleme")

        app.terminate()
        app.launchEnvironment["RITIM_UI_TEST_PRESERVE_FIXTURES"] = "1"
        app.launch()
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(measuredSeconds(total), measured)
        let period30 = app.buttons["dashboard.period30"]
        reveal(period30, in: app)
        period30.tap()
        XCTAssertGreaterThanOrEqual(measuredSeconds(total), measured)
        let library = app.buttons["dashboard.libraryCount"]
        reveal(library, in: app)
        XCTAssertEqual(library.value as? String, "3")
        library.tap()
        let close = app.buttons["dashboard.collection.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()
        let downloads = app.buttons["dashboard.downloads"]
        reveal(downloads, in: app)
        capture(app, name: "Dashboard-Kitaplik-ve-Indirmeler")
        downloads.tap()
        XCTAssertTrue(app.buttons["download.start"].waitForExistence(timeout: 4))
        app.buttons["tab.home"].tap()
        let assistant = app.buttons["home.assistant"]
        reveal(assistant, in: app)
        assistant.tap()
        XCTAssertTrue(app.buttons["tab.assistant"].isSelected)
    }

    @MainActor
    func testLibrarySearchAndBatchPlaylist() throws {
        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        app.launch()
        app.buttons["tab.library"].tap()
        let search = app.textFields["library.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Gece")
        app.keyboards.buttons["Search"].tap()
        let select = app.buttons["library.select"]
        reveal(select, in: app)
        select.tap()
        let chooseAll = app.buttons["Görünenleri seç"]
        reveal(chooseAll, in: app)
        chooseAll.tap()
        let add = app.buttons["library.batch.playlist"]
        reveal(add, in: app)
        XCTAssertTrue(add.isEnabled)
        add.tap()
        let name = app.textFields["Yeni liste adı"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Gece listesi")
        app.buttons["Yeni liste oluştur"].tap()
        XCTAssertTrue(app.buttons["Gece listesi"].waitForExistence(timeout: 5))
    }

    private func measuredSeconds(_ element: XCUIElement) -> Int {
        Int(element.value as? String ?? "-1") ?? -1
    }

    @MainActor
    func testDashboardAtAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let play = app.buttons["Kütüphaneyi çal"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        for identifier in ["tab.home", "tab.search", "tab.library", "tab.downloads", "tab.assistant"] {
            let tab = app.buttons[identifier]
            assertContained(tab, in: app)
            XCTAssertLessThanOrEqual(tab.frame.height, 80, "Alt gezinme büyük yazıda ekranı kaplamamalı")
        }
        reveal(play, in: app)
        assertContained(play, in: app)
        let period = app.buttons["dashboard.period30"]
        reveal(period, in: app)
        assertContained(period, in: app)
        period.tap()
        let metric = app.buttons["dashboard.libraryCount"]
        reveal(metric, in: app)
        assertContained(metric, in: app)
        capture(app, name: "Dashboard-Buyuk-Yazi")
        metric.tap()
        XCTAssertTrue(app.buttons["dashboard.collection.close"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func assertContained(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX - 1, file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX + 1, file: file, line: line)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<12 {
            if element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - 100 && element.frame.minY > app.frame.minY + 60 { return }
            let upwards = !element.exists || element.frame.midY > app.frame.midY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: upwards ? 0.72 : 0.35))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: upwards ? 0.35 : 0.72))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Panel denetimine erişilemedi: \(element.identifier)", file: file, line: line)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
