import XCTest

final class DownloadFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testNativeDownloadSettingsHaveNoMacPairing() throws {
        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["tab.downloads"].waitForExistence(timeout: 10))
        app.buttons["tab.downloads"].tap()
        app.buttons["downloads.settings"].tap()
        XCTAssertTrue(app.staticTexts["settings.nativeDownloads"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["Sunucu adresi"].exists)
        XCTAssertFalse(app.secureTextFields["Erişim anahtarı"].exists)
        XCTAssertFalse(app.buttons["Bağlantıyı sına"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Dogrudan-iPhone-indirme-ayarlari"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Bitti"].tap()
    }
}
