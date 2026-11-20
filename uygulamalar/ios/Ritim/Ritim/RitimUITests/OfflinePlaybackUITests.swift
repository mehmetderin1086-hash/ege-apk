import XCTest

final class OfflinePlaybackUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    /// Caller provisions local MP3 and MP4 fixtures. Only the test library is used.
    @MainActor
    func testLocalAudioAndVideoWithUnavailableServer() throws {
        guard ProcessInfo.processInfo.environment["RITIM_UI_TEST_OFFLINE"] == "1" else {
            throw XCTSkip("Yerel MP3/MP4 test dosyaları hazırlanmalı.")
        }
        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        app.launchEnvironment["RITIM_UI_TEST_PRESERVE_FIXTURES"] = "1"
        // iPhone loopback port 1 has no media service. Keep remote test transport available.
        app.launchEnvironment["RITIM_SERVER_URL"] = "http://127.0.0.1:1"
        app.launch()
        XCTAssertTrue(app.buttons["Ayarlar"].waitForExistence(timeout: 10))
        app.buttons["Ayarlar"].tap()
        XCTAssertTrue(app.staticTexts["settings.nativeDownloads"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["Sunucu adresi"].exists)
        capture(app, name: "Cevrimdisi-Dogrudan-iPhone-Ayarlari")
        app.buttons["Bitti"].tap()
        app.buttons["tab.library"].tap()
        for title in ["Çevrimdışı Ses Testi", "Çevrimdışı Video Testi"] {
            let row = app.buttons["\(title), çal"]
            XCTAssertTrue(row.waitForExistence(timeout: 4))
            row.tap()
            app.buttons["player.expand"].tap()
            let elapsed = app.staticTexts["player.elapsed"]
            XCTAssertTrue(elapsed.waitForExistence(timeout: 4))
            XCTAssertTrue(app.staticTexts[title].exists)
            let initial = seconds(elapsed.label)
            let progress = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
                seconds(elapsed.label) > initial
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [progress], timeout: 6), .completed, "Yerel medya sunucusuz oynatılmalı")
            XCTAssertEqual(app.buttons["player.playPause"].label, "Duraklat")
            capture(app, name: title)
            app.buttons["player.playPause"].tap()
            app.buttons["Çaları küçült"].tap()
        }
        XCTAssertFalse(app.alerts["İşlem tamamlanamadı"].exists)
    }

    private func seconds(_ label: String) -> Int {
        label.split(separator: ":").compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
