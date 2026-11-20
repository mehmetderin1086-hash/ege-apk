import XCTest

final class RitimUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testOfflinePlaybackAndNavigation() throws {
        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        app.launchEnvironment["RITIM_UI_TEST_LONG_TITLE"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 10))
        capture(app, name: "01-Kesfet")

        app.buttons["Kütüphaneyi çal"].tap()
        XCTAssertTrue(app.buttons["player.expand"].waitForExistence(timeout: 5))
        app.buttons["player.expand"].tap()
        XCTAssertTrue(app.buttons["Çaları küçült"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.sliders["Çalma konumu"].exists)
        XCTAssertTrue(app.buttons["Çalma sırası"].exists)
        for label in ["Çaları küçült", "Dosyayı paylaş", "Beğen", "Karışık çal", "Önceki parça", "Sonraki parça", "Tekrar kapalı, değiştir", "Çalma sırası", "Çalma hızı", "Uyku zamanlayıcısı"] {
            assertHorizontallyContained(app.buttons[label], in: app)
        }
        assertHorizontallyContained(app.sliders["Çalma konumu"], in: app)
        assertHorizontallyContained(app.staticTexts["player.remaining"], in: app)
        XCTAssertEqual(app.buttons.matching(identifier: "player.playPause").count, 1)
        let miniRemoved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["miniPlayer.playPause"])
        XCTAssertEqual(XCTWaiter.wait(for: [miniRemoved], timeout: 3), .completed)
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Duraklat"), object: app.buttons["player.playPause"])
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 5), .completed)
        let elapsed = app.staticTexts["player.elapsed"]
        XCTAssertTrue(elapsed.exists)
        let initialTime = seconds(in: elapsed.label)
        let progressed = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            seconds(in: elapsed.label) > initialTime
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [progressed], timeout: 6), .completed, "Gerçek oynatma süresi ilerlemeli")
        capture(app, name: "02-Oynatici")
        app.buttons["player.playPause"].tap()
        let paused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Çal"), object: app.buttons["player.playPause"])
        XCTAssertEqual(XCTWaiter.wait(for: [paused], timeout: 3), .completed)
        app.buttons["Çaları küçült"].tap()

        app.buttons["tab.search"].tap()
        let search = app.textFields["Parça, sanatçı veya albüm"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("no-results-ritim-9876")
        XCTAssertTrue(app.staticTexts["Henüz bir sonuç yok"].waitForExistence(timeout: 3))
        app.buttons["Aramayı temizle"].tap()
        app.buttons["tab.library"].tap()
        XCTAssertTrue(app.staticTexts["Kitaplığım"].waitForExistence(timeout: 3))
        capture(app, name: "03-Kitaplik")

        app.buttons["tab.downloads"].tap()
        XCTAssertTrue(app.buttons["download.start"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["download.start"].isEnabled)
        capture(app, name: "04-Indirmeler")
    }

    private func seconds(in label: String) -> Int {
        label.split(separator: ":").compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
    }

    @MainActor
    private func assertHorizontallyContained(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.exists, file: file, line: line)
        XCTAssertGreaterThan(element.frame.width, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX - 1, "Sol kenar ekran dışına taşmamalı: \(element.label)", file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX + 1, "Sağ kenar ekran dışına taşmamalı: \(element.label)", file: file, line: line)
    }

    @MainActor
    func testInvalidDownloadShowsActionableError() throws {
        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        app.launch()
        app.buttons["tab.downloads"].tap()
        let url = app.textFields["download.url"].exists ? app.textFields["download.url"] : app.textViews["download.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 3))
        url.tap()
        url.typeText("invalid-link")
        app.buttons["download.start"].tap()
        XCTAssertTrue(app.alerts["İşlem tamamlanamadı"].waitForExistence(timeout: 3))
        app.alerts.buttons["Tamam"].tap()
        XCTAssertTrue(app.buttons["download.start"].exists)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
