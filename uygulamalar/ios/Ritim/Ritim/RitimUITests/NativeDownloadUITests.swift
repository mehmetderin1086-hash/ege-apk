import XCTest

final class NativeDownloadUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testNativeBackgroundHandoffAndForegroundCompletion() throws {
        guard ProcessInfo.processInfo.environment["RITIM_UI_TEST_NATIVE"] == "1" else { throw XCTSkip("Canlı YouTube testi etkin değil.") }
        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        app.launchEnvironment["RITIM_UI_TEST_HANDOFF"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["tab.downloads"].waitForExistence(timeout: 15))
        app.buttons["tab.downloads"].tap()
        let field = app.textFields["download.url"].exists ? app.textFields["download.url"] : app.textViews["download.url"]
        field.tap()
        field.typeText("https://www.youtube.com/watch?v=jNQXAC9IVRw")
        dismissKeyboard(in: app)
        let start = app.buttons["download.start"]
        reveal(start, in: app, upwards: true)
        start.tap()
        reveal(app.segmentedControls["queue.filter"], in: app, upwards: true)
        for _ in 0..<3 { scroll(app, upwards: true) }
        XCTAssertTrue(app.staticTexts["İndirme sürüyor"].waitForExistence(timeout: 90), "Gerçek kaynak çözümlenmiş olmalı")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 35)
        app.activate()
        let play = app.buttons["download.play.mp3"].firstMatch
        let deadline = Date().addingTimeInterval(180)
        while !play.exists && Date() < deadline {
            if play.waitForExistence(timeout: 4) { break }
            scroll(app, upwards: true)
        }
        XCTAssertTrue(play.exists, "Arka plandan dönüşte MP3 tamamlanmalı")
    }

    @MainActor
    private func launch(preserve: Bool = false) throws -> XCUIApplication {
        guard ProcessInfo.processInfo.environment["RITIM_UI_TEST_NATIVE"] == "1" else {
            throw XCTSkip("Canlı iPhone YouTube indirmesi için RITIM_UI_TEST_NATIVE=1 gerekli.")
        }
        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        if preserve { app.launchEnvironment["RITIM_UI_TEST_PRESERVE_FIXTURES"] = "1" }
        // A legacy Mac service cannot possibly prepare these files through iPhone loopback.
        app.launchEnvironment["RITIM_SERVER_URL"] = "http://127.0.0.1:1"
        app.launch()
        XCTAssertTrue(app.buttons["tab.downloads"].waitForExistence(timeout: 10))
        app.buttons["tab.downloads"].tap()
        return app
    }

    @MainActor
    func testNativeMP3AndMP4DownloadHighestQualityAndLocalPlayback() throws {
        let app = try launch()
        let field = app.textFields["download.url"].exists ? app.textFields["download.url"] : app.textViews["download.url"]
        field.tap()
        field.typeText(ProcessInfo.processInfo.environment["RITIM_UI_TEST_NATIVE_URL"] ?? "https://www.youtube.com/watch?v=jNQXAC9IVRw")
        dismissKeyboard(in: app)
        // Both conversion formats are obtained from the same short real video.
        // The caller also inspects exported fixture files with ffprobe.
        for (label, format) in [("MP3 · Ses", "mp3"), ("MP4 · Video", "mp4")] {
            let formats = app.segmentedControls["download.format"]
            reveal(formats, in: app, upwards: false)
            formats.buttons[label].tap()
            let quality = app.segmentedControls["download.quality"]
            reveal(quality, in: app, upwards: true)
            quality.buttons["En yüksek"].tap()
            if format == "mp3" { XCTAssertEqual(app.staticTexts["download.quality.detail"].label, "320 kbps MP3") }
            let start = app.buttons["download.start"]
            reveal(start, in: app, upwards: true)
            start.tap()
            reveal(app.segmentedControls["queue.filter"], in: app, upwards: true)
            // Queue cards are lazy. Bring their container fully into view before
            // waiting for a completed row to materialize in accessibility.
            for _ in 0..<3 { scroll(app, upwards: true) }
            capture(app, name: "Dogrudan-\(format)-indirme-sirasi")
            let play = app.buttons["download.play.\(format)"].firstMatch
            let deadline = Date().addingTimeInterval(240)
            while !play.exists && Date() < deadline {
                if play.waitForExistence(timeout: 4) { break }
                scroll(app, upwards: true)
            }
            let completed = play.exists
            if !completed { capture(app, name: "Dogrudan-\(format)-indirme-hatasi"); attachTree(app) }
            XCTAssertTrue(completed, "YouTube \(format.uppercased()) iPhone’da hazırlanıp yerel kitaplığa eklenmeli")
            reveal(play, in: app, upwards: true)
            capture(app, name: "Dogrudan-iPhone-\(format)-indirildi")
            play.tap()
            XCTAssertTrue(app.buttons["player.expand"].waitForExistence(timeout: 5))
            app.buttons["player.expand"].tap()
            assertPlayback(in: app, format: format)
            app.buttons["Çaları küçült"].tap()
        }
        app.terminate()
        app.launchEnvironment["RITIM_UI_TEST_PRESERVE_FIXTURES"] = "1"
        app.launch()
        app.buttons["tab.downloads"].tap()
        reveal(app.segmentedControls["queue.filter"], in: app, upwards: true)
        for _ in 0..<3 { scroll(app, upwards: true) }
        XCTAssertTrue(app.buttons["download.play.mp3"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["download.play.mp4"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["İşlem tamamlanamadı"].exists)
        capture(app, name: "Dogrudan-indirmeler-yeniden-acilista-korundu")
    }

    @MainActor
    func testUserMixPreviewDirectlyOnIPhone() throws {
        // Preserve the preceding native download fixtures for file inspection.
        let app = try launch(preserve: true)
        let modes = app.segmentedControls["bulk.mode"]
        modes.buttons["Oynatma listesi"].tap()
        let field = app.textFields["playlist.url"].exists ? app.textFields["playlist.url"] : app.textViews["playlist.url"]
        field.tap()
        field.typeText("https://youtube.com/playlist?list=RDEMTPfPURSbYpb0YHCKyIG37Q")
        dismissKeyboard(in: app)
        app.buttons["playlist.resolve"].tap()
        let count = app.staticTexts["playlist.selectionCount"]
        let found = count.waitForExistence(timeout: 90)
        if !found { capture(app, name: "Dogrudan-Mix-hatasi"); attachTree(app) }
        XCTAssertTrue(found)
        let numbers = count.label.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        XCTAssertTrue(numbers.contains(where: { $0 >= 2 }), "Gerçek kullanıcı listesinden birden fazla parça alınmalı")
        reveal(app.buttons["playlist.clearSelection"], in: app, upwards: true)
        app.buttons["playlist.clearSelection"].tap()
        XCTAssertTrue(count.label.contains("0 seçili"))
        capture(app, name: "Kullanicinin-Mix-listesi-dogrudan-iPhone")
        // Metadata scan does not enqueue hundreds of user videos during acceptance.
        XCTAssertFalse(app.alerts["İşlem tamamlanamadı"].exists)
    }

    @MainActor
    private func assertPlayback(in app: XCUIApplication, format: String) {
        let elapsed = app.staticTexts["player.elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
        app.sliders["Çalma konumu"].adjust(toNormalizedSliderPosition: 0)
        if app.buttons["player.playPause"].label == "Çal" { app.buttons["player.playPause"].tap() }
        let initial = seconds(elapsed.label)
        let progress = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            seconds(elapsed.label) > initial
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [progress], timeout: 8), .completed)
        XCTAssertEqual(app.buttons["player.playPause"].label, "Duraklat")
        capture(app, name: "Dogrudan-iPhone-\(format)-yerel-oynatma")
        app.buttons["player.playPause"].tap()
    }

    private func seconds(_ value: String) -> Int {
        value.split(separator: ":").compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool) {
        for _ in 0..<10 {
            if element.exists && element.isHittable && element.frame.minY >= app.frame.minY + 65 && element.frame.maxY <= app.frame.maxY - 130 { return }
            scroll(app, upwards: upwards)
        }
        capture(app, name: "Kontrol-bulunamadi-\(element.identifier)")
        attachTree(app)
        XCTAssertTrue(element.exists && element.isHittable, "Kontrol bulunamadı: \(element.identifier)")
    }

    @MainActor
    private func dismissKeyboard(in app: XCUIApplication) {
        if !app.keyboards.firstMatch.exists { return }
        let done = app.buttons["download.dismissKeyboard"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !app.keyboards.firstMatch.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 4), .completed, "İndirme kontrollerinden önce klavye kapanmalı")
    }

    @MainActor
    private func scroll(_ app: XCUIApplication, upwards: Bool) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: upwards ? 0.78 : 0.32))
            .press(forDuration: 0.08, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: upwards ? 0.32 : 0.78)))
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor
    private func attachTree(_ app: XCUIApplication) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Dogrudan-indirme-erisebilirlik"; tree.lifetime = .keepAlways; add(tree)
    }
}
