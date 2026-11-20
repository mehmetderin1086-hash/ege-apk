import XCTest

final class PlaybackResumeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testPlaybackSessionRestoresPausedAndResumesFromDashboard() throws {
        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        app.launch()
        let start = app.buttons["Kütüphaneyi çal"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["dashboard.resume"].exists)
        start.tap()
        XCTAssertTrue(app.buttons["player.expand"].waitForExistence(timeout: 5))
        app.buttons["player.expand"].tap()
        XCTAssertTrue(app.staticTexts["player.title"].waitForExistence(timeout: 4))
        // A different current track catches a relaunch that simply starts the library again.
        let firstTitle = app.staticTexts["player.title"].label
        app.buttons["Sonraki parça"].tap()
        waitUntil { app.staticTexts["player.title"].label != firstTitle }
        let title = app.staticTexts["player.title"].label
        let elapsed = app.staticTexts["player.elapsed"]
        waitUntil { self.seconds(elapsed.label) >= 2 }
        XCTAssertEqual(app.buttons["player.playPause"].label, "Duraklat")
        app.buttons["player.playPause"].tap()
        waitUntil { app.buttons["player.playPause"].label == "Çal" }
        app.sliders["player.position"].adjust(toNormalizedSliderPosition: 0.35)
        waitUntil { self.seconds(elapsed.label) >= 8 }

        let shuffle = app.buttons["player.shuffle"]
        reveal(shuffle, in: app)
        shuffle.tap()
        XCTAssertEqual(shuffle.value as? String, "Açık")
        let repeatMode = app.buttons["player.repeat"]
        repeatMode.tap()
        repeatMode.tap()
        XCTAssertEqual(repeatMode.value as? String, "Tek parça")
        let rate = app.buttons["player.rate"]
        reveal(rate, in: app)
        rate.tap()
        let faster = app.buttons["player.rate.1.5"]
        XCTAssertTrue(faster.waitForExistence(timeout: 3))
        let expectedRate = faster.label
        faster.tap()
        let savedRate = rate.value as? String
        XCTAssertEqual(savedRate, expectedRate)
        let queue = queueIdentifiers(in: app)
        XCTAssertEqual(queue.count, 3)
        let savedElapsed = seconds(elapsed.label)
        XCTAssertGreaterThanOrEqual(savedElapsed, 8)
        reveal(app.buttons["Çaları küçült"], in: app)
        app.buttons["Çaları küçült"].tap()

        app.terminate()
        app.launchEnvironment["RITIM_UI_TEST_PRESERVE_FIXTURES"] = "1"
        app.launch()
        let resume = app.buttons["dashboard.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        XCTAssertTrue(resume.isHittable, "Kaldığın yerden kartı ana ekranın başında bulunmalı")
        XCTAssertEqual(resume.label, "Dinlemeye devam et")
        XCTAssertEqual(app.staticTexts["dashboard.resume.title"].label, title)
        XCTAssertEqual(app.staticTexts["dashboard.resume.queueCount"].value as? String, "3")
        XCTAssertFalse(app.buttons["Kütüphaneyi çal"].exists, "Kayıtlı oturum varken ana eylem kütüphaneyi baştan başlatmamalı")
        let dashboardElapsed = app.staticTexts["dashboard.resume.elapsed"]
        waitUntil { abs(self.seconds(dashboardElapsed.value as? String ?? "") - savedElapsed) <= 1 }
        let pausedTime = seconds(dashboardElapsed.value as? String ?? "")
        let unexpectedPlayback = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            seconds(dashboardElapsed.value as? String ?? "") > pausedTime + 1 || resume.label != "Dinlemeye devam et"
        }, object: nil)
        unexpectedPlayback.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [unexpectedPlayback], timeout: 3), .completed,
                       "Yeniden açılan oturum kullanıcı devam edene kadar duraklatılmış kalmalı")
        capture(app, name: "Kaldigin-Yerden-Yeniden-Acilis")

        app.buttons["player.expand"].tap()
        XCTAssertTrue(app.staticTexts["player.title"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.staticTexts["player.title"].label, title)
        XCTAssertEqual(app.buttons["player.playPause"].label, "Çal")
        XCTAssertEqual(app.buttons["player.shuffle"].value as? String, "Açık")
        XCTAssertEqual(app.buttons["player.repeat"].value as? String, "Tek parça")
        XCTAssertEqual(app.buttons["player.rate"].value as? String, savedRate)
        XCTAssertEqual(queueIdentifiers(in: app), queue, "Çalma sırası ve parça kimlikleri korunmalı")
        reveal(app.buttons["Çaları küçült"], in: app)
        app.buttons["Çaları küçült"].tap()
        resume.tap()
        waitUntil { resume.label == "Dinlemeyi duraklat" }
        waitUntil { self.seconds(dashboardElapsed.value as? String ?? "") > savedElapsed + 1 }
        XCTAssertEqual(app.staticTexts["dashboard.resume.title"].label, title)

        // Termination during playback must also restore silently. The resume action
        // remains reachable at the largest accessibility text size.
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        XCTAssertEqual(resume.label, "Dinlemeye devam et")
        XCTAssertEqual(app.staticTexts["dashboard.resume.title"].label, title)
        reveal(resume, in: app)
        XCTAssertGreaterThanOrEqual(resume.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(resume.frame.maxX, app.frame.maxX)
        capture(app, name: "Kaldigin-Yerden-Buyuk-Yazi")
        resume.tap()
        waitUntil { resume.label == "Dinlemeyi duraklat" }
        resume.tap()
        waitUntil { resume.label == "Dinlemeye devam et" }
        XCTAssertFalse(app.alerts["İşlem tamamlanamadı"].exists)
    }

    @MainActor
    private func queueIdentifiers(in app: XCUIApplication) -> [String] {
        let openQueue = app.buttons["Çalma sırası"]
        reveal(openQueue, in: app)
        openQueue.tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "player.queue.track."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 3))
        let identifiers = rows.allElementsBoundByIndex.map(\.identifier)
        app.buttons["Kapat"].tap()
        return identifiers
    }

    private func seconds(_ text: String) -> Int {
        guard !text.isEmpty else { return -1 }
        return text.split(separator: ":").compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval = 6, file: StaticString = #filePath, line: UInt = #line,
                           _ condition: @escaping () -> Bool) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: timeout), .completed, file: file, line: line)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<12 {
            if element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - 20 && element.frame.minY > app.frame.minY + 30 { return }
            let upwards = !element.exists || element.frame.midY > app.frame.midY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: upwards ? 0.72 : 0.35))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: upwards ? 0.35 : 0.72))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Denetime erişilemedi: \(element.identifier)", file: file, line: line)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
