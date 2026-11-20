import XCTest

final class MusicLibraryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testSmartCollectionSavesPlaylistAndArtistBrowserOpens() throws {
        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["tab.library"].waitForExistence(timeout: 10))
        app.buttons["tab.library"].tap()
        app.buttons["library.smartCollections"].tap()
        let recent = app.buttons["smart.recent"]
        XCTAssertTrue(recent.waitForExistence(timeout: 4))
        capture(app, "Akilli-Koleksiyonlar")
        recent.tap()
        let save = app.buttons["Liste olarak kaydet"]
        XCTAssertTrue(save.waitForExistence(timeout: 4))
        save.tap()
        let alert = app.alerts["Liste olarak kaydet"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["Kaydet"].tap()
        XCTAssertTrue(app.alerts["Liste kaydedildi"].waitForExistence(timeout: 4))
        app.alerts["Liste kaydedildi"].buttons["Tamam"].tap()
        capture(app, "Yeni-Eklenenler")

        app.terminate()
        app.launchEnvironment["RITIM_UI_TEST_PRESERVE_FIXTURES"] = "1"
        app.launch()
        app.buttons["tab.library"].tap()
        XCTAssertTrue(app.staticTexts["Yeni eklenenler"].waitForExistence(timeout: 4))
        app.buttons["library.artistsAlbums"].tap()
        XCTAssertTrue(app.navigationBars["Albüm ve sanatçı"].waitForExistence(timeout: 4))
        capture(app, "Album-Sanatci")
        XCTAssertFalse(app.alerts["İşlem tamamlanamadı"].exists)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
