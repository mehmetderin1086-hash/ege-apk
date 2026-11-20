import XCTest

final class LyricsUITests: XCTestCase {
    // Original test verses only; no provider, copyrighted lyrics, or network needed.
    private let timedText = """
    [00:00.00]Ritim için yeni bir gün
    [00:08.00]Yol boyunca notalar
    [00:16.00]Kendi melodimle yürürüm
    [00:24.00]Sesim güne karışır
    """
    private let plainText = "Yeni bir sabah\nKendi sesimle başlar\nRitim benimle yürür"

    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testOriginalTimedLyricsSeekFollowOffsetAndOfflinePersistence() throws {
        let app = launch()
        openLyrics(in: app, startPlayback: true)
        let add = app.buttons["lyrics.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 6))
        add.tap()
        enter(timedText, in: app)
        let third = app.buttons["lyrics.line.2"]
        XCTAssertTrue(third.waitForExistence(timeout: 5))
        XCTAssertEqual(third.label, "Kendi melodimle yürürüm")
        XCTAssertTrue(app.staticTexts["lyrics.offline"].exists)
        reveal(third, in: app)
        third.tap()
        waitUntil { self.seconds(app.staticTexts["lyrics.elapsed"].label) == 16 }
        XCTAssertEqual(third.value as? String, "Etkin satır")
        XCTAssertEqual(app.buttons["lyrics.playPause"].label, "Çal", "Söz satırına dokunmak duraklatılmış parçayı başlatmamalı")

        let follow = app.buttons["lyrics.follow"]
        XCTAssertEqual(follow.value as? String, "Açık")
        follow.tap()
        XCTAssertEqual(follow.value as? String, "Kapalı")
        let timing = app.buttons["lyrics.timing"]
        XCTAssertTrue(timing.exists)
        XCTAssertEqual(timing.value as? String, "Kapalı")
        timing.tap()
        XCTAssertEqual(timing.value as? String, "Açık")
        let later = app.buttons["lyrics.offset.increase"]
        XCTAssertTrue(later.waitForExistence(timeout: 3))
        later.tap()
        XCTAssertEqual(app.staticTexts["lyrics.offset.value"].value as? String, "0.5")
        capture(app, name: "Sozler-zamanli-satir-ve-zamanlama")

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 3) || app.state == .runningBackgroundSuspended)
        app.activate()
        XCTAssertTrue(app.buttons["lyrics.close"].waitForExistence(timeout: 5))
        XCTAssertEqual(follow.value as? String, "Kapalı", "Öne dönmek kullanıcının takip tercihini değiştirmemeli")
        XCTAssertEqual(app.staticTexts["lyrics.offset.value"].value as? String, "0.5")

        app.buttons["lyrics.options"].tap()
        app.buttons["lyrics.edit"].tap()
        let editor = app.textViews["lyrics.editor.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, timedText, "Düzenleyici özgün LRC zamanlarını korumalı")
        app.buttons["Vazgeç"].tap()
        app.buttons["lyrics.close"].tap()
        app.terminate()
        app.launchEnvironment["RITIM_UI_TEST_PRESERVE_FIXTURES"] = "1"
        app.launch()
        openLyrics(in: app, startPlayback: false)
        XCTAssertTrue(app.buttons["lyrics.line.2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["lyrics.offline"].exists)
        XCTAssertEqual(app.buttons["lyrics.line.2"].label, "Kendi melodimle yürürüm")
        app.buttons["lyrics.timing"].tap()
        XCTAssertEqual(app.staticTexts["lyrics.offset.value"].value as? String, "0.5")
        app.buttons["lyrics.timing"].tap()
        let second = app.buttons["lyrics.line.1"]
        reveal(second, in: app)
        second.tap()
        waitUntil { self.seconds(app.staticTexts["lyrics.elapsed"].label) == 8 }
        app.buttons["lyrics.playPause"].tap()
        waitUntil { self.seconds(app.staticTexts["lyrics.elapsed"].label) >= 10 }
        XCTAssertEqual(app.buttons["lyrics.playPause"].label, "Duraklat")
        app.buttons["lyrics.playPause"].tap()
        capture(app, name: "Sozler-cevrimdisi-yeniden-acilis")
    }

    @MainActor
    func testPlainLyricsHaveNoInventedTimingAndQueueCanBeSaved() throws {
        let app = launch()
        openLyrics(in: app, startPlayback: true)
        let originalTrackTitle = app.staticTexts["lyrics.track"].label
        XCTAssertTrue(app.buttons["lyrics.add"].waitForExistence(timeout: 6))
        app.buttons["lyrics.add"].tap()
        enter(plainText, in: app)
        let displayed = app.staticTexts["lyrics.plainText"]
        XCTAssertTrue(displayed.waitForExistence(timeout: 5))
        XCTAssertEqual(displayed.label, plainText)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "lyrics.line.")).count, 0)
        XCTAssertFalse(app.buttons["lyrics.follow"].exists)
        XCTAssertFalse(app.buttons["lyrics.offset.increase"].exists)
        XCTAssertTrue(app.staticTexts["lyrics.offline"].exists)
        capture(app, name: "Sozler-duz-metin")
        XCTAssertEqual(app.staticTexts["lyrics.track"].label, originalTrackTitle, "Söz düzenlenirken seçili parça değişmemeli")
        XCTAssertEqual(app.buttons["lyrics.playPause"].label, "Çal", "Söz düzenlemek duraklatılmış parçayı başlatmamalı")
        app.buttons["lyrics.options"].tap()
        app.buttons["lyrics.remove"].tap()
        // SwiftUI exposes both the action and its wrapper as buttons in a
        // confirmation dialog. Scope to this dialog and use its first match.
        let dialog = app.sheets["Eklediğin sözler kaldırılsın mı?"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 3))
        let remove = dialog.buttons.matching(identifier: "lyrics.remove.confirm").firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        remove.tap()
        XCTAssertTrue(app.buttons["lyrics.add"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["lyrics.plainText"].exists)
        app.buttons["lyrics.close"].tap()
        let queue = app.buttons["Çalma sırası"]
        reveal(queue, in: app)
        queue.tap()
        XCTAssertTrue(app.buttons["player.queue.save"].waitForExistence(timeout: 4))
        app.buttons["player.queue.save"].tap()
        app.alerts.buttons["Kaydet"].tap()
        XCTAssertTrue(app.staticTexts["player.queue.saved"].waitForExistence(timeout: 4))
    }

    @MainActor
    private func launch() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        app.launchEnvironment["RITIM_UI_TEST_LYRICS_OFFLINE"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func openLyrics(in app: XCUIApplication, startPlayback: Bool) {
        if startPlayback { app.buttons["Kütüphaneyi çal"].tap() }
        XCTAssertTrue(app.buttons["player.expand"].waitForExistence(timeout: 5))
        app.buttons["player.expand"].tap()
        let pause = app.buttons["player.playPause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        if startPlayback {
            waitUntil { pause.label == "Duraklat" }
            reveal(pause, in: app)
            pause.tap()
            waitUntil { pause.label == "Çal" }
        }
        let open = app.buttons["player.lyrics"]
        reveal(open, in: app)
        open.tap()
        XCTAssertTrue(app.buttons["lyrics.close"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func enter(_ text: String, in app: XCUIApplication) {
        let editor = app.textViews["lyrics.editor.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()
        editor.typeText(text)
        app.buttons["lyrics.editor.save"].tap()
    }

    private func seconds(_ text: String) -> Int {
        text.split(separator: ":").compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
    }

    @MainActor
    private func waitUntil(_ condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 6), .completed)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable && element.frame.minY > app.frame.minY + 40 && element.frame.maxY < app.frame.maxY - 25 { return }
            let upwards = !element.exists || element.frame.midY > app.frame.midY
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: upwards ? 0.73 : 0.35))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: upwards ? 0.35 : 0.73)))
        }
        XCTAssertTrue(element.exists && element.isHittable, "Denetime erişilemedi: \(element.identifier)")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
