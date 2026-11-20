import XCTest

final class DownloadQualityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    /// The caller provisions a verified 4K MP4 in the isolated fixture library.
    /// No network request or production-library mutation is involved.
    @MainActor
    func testFourKFixturePlayback() throws {
        guard ProcessInfo.processInfo.environment["RITIM_UI_TEST_4K"] == "1" else {
            throw XCTSkip("4K oynatma testi için RITIM_UI_TEST_4K=1 ve hazırlanmış test kitaplığı gerekli.")
        }
        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        app.launchEnvironment["RITIM_UI_TEST_PRESERVE_FIXTURES"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["tab.library"].waitForExistence(timeout: 10))
        app.buttons["tab.library"].tap()
        let track = app.buttons.matching(NSPredicate(format: "label == %@", "Ritim 4K Kalite Testi, çal")).firstMatch
        reveal(track, in: app)
        track.tap()
        XCTAssertTrue(app.buttons["player.expand"].waitForExistence(timeout: 3))
        app.buttons["player.expand"].tap()
        let elapsed = app.staticTexts["player.elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 3))
        let remaining = app.staticTexts["player.remaining"]
        XCTAssertTrue(remaining.exists)
        let total = seconds(in: elapsed.label) + seconds(in: remaining.label)
        XCTAssertTrue((7...9).contains(total), "Hazırlanmış 8 saniyelik 4K video oynatıcıda yüklenmeli")
        // Device UI automation may take a few seconds to expand the player.
        // Seek back so the short clip has enough time left for the assertion.
        app.sliders["Çalma konumu"].adjust(toNormalizedSliderPosition: 0)
        let rewound = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            seconds(in: elapsed.label) <= 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rewound], timeout: 3), .completed)
        if app.buttons["player.playPause"].label == "Çal" { app.buttons["player.playPause"].tap() }
        let initial = seconds(in: elapsed.label)
        let progressed = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            seconds(in: elapsed.label) > initial
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [progressed], timeout: 4), .completed, "4K videonun gerçek oynatma süresi ilerlemeli")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "4K-iPhone-Oynatma"
        shot.lifetime = .keepAlways
        add(shot)
        if app.buttons["player.playPause"].label == "Duraklat" { app.buttons["player.playPause"].tap() }
        XCTAssertEqual(app.buttons["player.playPause"].label, "Çal")
    }

    @MainActor
    func testQualityDefaultsSharedModesAndPersistentSettings() throws {
        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        app.launch()
        openDownloads(in: app)
        let quality = app.segmentedControls["download.quality"]
        reveal(quality, in: app)
        XCTAssertTrue(quality.buttons["En yüksek"].isSelected)
        XCTAssertEqual(app.staticTexts["download.quality.detail"].label, "320 kbps MP3")
        quality.buttons["Standart"].tap()
        XCTAssertTrue(quality.buttons["Standart"].isSelected)
        XCTAssertEqual(app.staticTexts["download.quality.detail"].label, "192 kbps MP3")

        let modes = app.segmentedControls["bulk.mode"]
        for name in ["Toplu", "Oynatma listesi", "Tek bağlantı"] {
            reveal(modes, in: app)
            modes.buttons[name].tap()
            reveal(quality, in: app)
            XCTAssertTrue(quality.buttons["Standart"].isSelected, "Kalite seçimi tüm indirme yollarında ortak olmalı")
        }
        let format = app.segmentedControls["download.format"]
        reveal(format, in: app)
        format.buttons["MP4 · Video"].tap()
        XCTAssertEqual(app.staticTexts["download.quality.detail"].label, "Kaynakta varsa 1080p")

        // Only the isolated UI test folder is retained. No production download
        // queue or library is edited, and this test never enqueues media.
        app.terminate()
        app.launchEnvironment["RITIM_UI_TEST_PRESERVE_FIXTURES"] = "1"
        app.launch()
        openDownloads(in: app)
        reveal(quality, in: app)
        XCTAssertTrue(quality.buttons["Standart"].isSelected)
        let settings = app.buttons["downloads.settings"]
        reveal(settings, in: app)
        settings.tap()
        let setting = app.buttons["settings.downloadQuality"]
        reveal(setting, in: app)
        XCTAssertEqual(setting.value as? String, "Standart")
        setting.tap()
        let highest = app.buttons.matching(NSPredicate(format: "label == %@", "En yüksek")).firstMatch
        XCTAssertTrue(highest.waitForExistence(timeout: 3))
        highest.tap()
        XCTAssertEqual(setting.value as? String, "En yüksek")
        app.buttons["Bitti"].tap()
        reveal(quality, in: app)
        XCTAssertTrue(quality.buttons["En yüksek"].isSelected)
        reveal(format, in: app)
        format.buttons["MP4 · Video"].tap()
        XCTAssertEqual(app.staticTexts["download.quality.detail"].label, "iPhone’a uygun en yüksek video kalitesi")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "En-yuksek-ses-ve-video-kalitesi"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    private func openDownloads(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["tab.downloads"].waitForExistence(timeout: 10))
        app.buttons["tab.downloads"].tap()
    }

    private func seconds(in label: String) -> Int {
        label.replacingOccurrences(of: "−", with: "").split(separator: ":")
            .compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let safeTop = app.frame.minY + (element.identifier == "downloads.settings" ? 60 : 175)
        let safeBottom = app.frame.maxY - 160
        for _ in 0..<12 {
            var upwards = true
            if element.exists {
                let frame = element.frame
                if element.isHittable && frame.minY >= safeTop && frame.maxY <= safeBottom { return }
                upwards = frame.midY >= (safeTop + safeBottom) / 2
            }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: upwards ? 0.68 : 0.42))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: upwards ? 0.48 : 0.62))
            start.press(forDuration: 0.10, thenDragTo: end)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Kalite denetimine erişilemedi: \(element.identifier)", file: file, line: line)
    }
}
