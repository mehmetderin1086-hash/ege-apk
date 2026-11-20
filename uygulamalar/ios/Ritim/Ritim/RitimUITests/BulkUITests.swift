import XCTest

final class BulkUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testConcurrentDownloadMenuPersistsSelection() throws {
        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        app.launch()
        openConcurrentDownloadSetting(in: app)
        let picker = app.buttons["settings.concurrentDownloads"]
        expectValue("10 dosya", on: picker)

        for count in [2, 4, 6] {
            picker.tap()
            let option = app.buttons.matching(NSPredicate(format: "label == %@", "\(count) dosya")).firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 3))
            option.tap()
            expectValue("\(count) dosya", on: picker)
        }
        capture(app, name: "Eszamanli-indirme-6-dosya")

        // Preserve only the isolated UI-test fixture folder, never a user's
        // production download queue or library.
        app.terminate()
        app.launchEnvironment["RITIM_UI_TEST_PRESERVE_FIXTURES"] = "1"
        app.launch()
        openConcurrentDownloadSetting(in: app)
        expectValue("6 dosya", on: app.buttons["settings.concurrentDownloads"])
        capture(app, name: "Eszamanli-indirme-secimi-korundu")
    }

    @MainActor
    private func openConcurrentDownloadSetting(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.buttons["tab.downloads"].waitForExistence(timeout: 10), file: file, line: line)
        app.buttons["tab.downloads"].tap()
        app.buttons["downloads.settings"].tap()
        let picker = app.buttons["settings.concurrentDownloads"]
        let safeTop = app.frame.minY + 160
        let safeBottom = app.frame.maxY - 80
        for _ in 0..<10 {
            var scrollUp = true
            if picker.exists {
                let frame = picker.frame
                if picker.isHittable && frame.minY >= safeTop && frame.maxY <= safeBottom { return }
                // A fast full-page swipe can carry this short row above the
                // navigation bar. Read its actual position and recover down.
                scrollUp = frame.midY >= (safeTop + safeBottom) / 2
            }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: scrollUp ? 0.68 : 0.42))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: scrollUp ? 0.48 : 0.62))
            start.press(forDuration: 0.15, thenDragTo: end)
        }
        capture(app, name: "Eszamanli-indirme-secici-bulunamadi")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Eszamanli-indirme-erisebilirlik-agaci"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTAssertTrue(picker.exists && picker.isHittable, "Eşzamanlı indirme seçimi görünmeli", file: file, line: line)
    }

    @MainActor
    private func expectValue(_ expected: String, on element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed, file: file, line: line)
    }

    /// Exercises the real editor -> parser -> persisted queue path. The editor
    /// fixture avoids sending 25,000 individual UI keystrokes. Pausing through
    /// the real control prevents any of the 500 placeholder videos being fetched.
    @MainActor
    func testFiveHundredLinksPersistAndDeduplicateWhilePaused() throws {
        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        app.launchEnvironment["RITIM_UI_TEST_BULK_LINKS"] = "500"
        app.launch()
        XCTAssertTrue(app.buttons["tab.downloads"].waitForExistence(timeout: 10))
        app.buttons["tab.downloads"].tap()
        reveal(app.buttons["queue.pause"], in: app, upwards: true)
        app.buttons["queue.pause"].tap()
        XCTAssertTrue(app.buttons["queue.resume"].waitForExistence(timeout: 3))

        let modes = app.segmentedControls["bulk.mode"]
        reveal(modes, in: app, upwards: false)
        modes.buttons["Toplu"].tap()
        XCTAssertTrue(app.textViews["bulk.links"].exists)
        XCTAssertTrue((app.textViews["bulk.links"].value as? String)?.contains("T0000000499") == true)
        reveal(app.buttons["bulk.enqueue"], in: app, upwards: true)
        XCTAssertTrue(app.buttons["bulk.enqueue"].isEnabled)
        app.buttons["bulk.enqueue"].tap()
        reveal(app.staticTexts["queue.pending"], in: app, upwards: true)
        expectLabel("500", on: app.staticTexts["queue.pending"])
        expectLabel("0", on: app.staticTexts["queue.running"])
        capture(app, name: "Toplu-500-duraklatilmis-sira")

        // The same links and format must never multiply the queue.
        reveal(app.buttons["bulk.enqueue"], in: app, upwards: false)
        app.buttons["bulk.enqueue"].tap()
        reveal(app.staticTexts["queue.pending"], in: app, upwards: true)
        expectLabel("500", on: app.staticTexts["queue.pending"])
        XCTAssertTrue(app.buttons["queue.resume"].exists)

        app.terminate()
        app.launchEnvironment["RITIM_UI_TEST_PRESERVE_FIXTURES"] = "1"
        app.launchEnvironment.removeValue(forKey: "RITIM_UI_TEST_BULK_LINKS")
        app.launch()
        XCTAssertTrue(app.buttons["tab.downloads"].waitForExistence(timeout: 10))
        app.buttons["tab.downloads"].tap()
        reveal(app.staticTexts["queue.pending"], in: app, upwards: true)
        expectLabel("500", on: app.staticTexts["queue.pending"])
        expectLabel("0", on: app.staticTexts["queue.running"])
        XCTAssertTrue(app.buttons["queue.resume"].exists, "Duraklatma yeniden açılışta korunmalı")
        capture(app, name: "Toplu-500-yeniden-acilis")

        reveal(app.buttons["queue.cancelAll"], in: app, upwards: true)
        app.buttons["queue.cancelAll"].tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Tümünü iptal et", "queue.cancelAll")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.tap()
        expectLabel("0", on: app.staticTexts["queue.pending"])
        expectLabel("0", on: app.staticTexts["queue.running"])
    }

    @MainActor
    func testEmptyPlaylistRequiresURLAndModeSwitchPreservesSingleInput() throws {
        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["tab.downloads"].waitForExistence(timeout: 10))
        app.buttons["tab.downloads"].tap()
        let modes = app.segmentedControls["bulk.mode"]
        modes.buttons["Oynatma listesi"].tap()
        XCTAssertTrue(app.buttons["playlist.resolve"].exists)
        XCTAssertFalse(app.buttons["playlist.resolve"].isEnabled)
        XCTAssertFalse(app.buttons["playlist.enqueue"].exists)
        capture(app, name: "Oynatma-listesi-tarama")
        modes.buttons["Toplu"].tap()
        reveal(app.buttons["bulk.enqueue"], in: app, upwards: true)
        XCTAssertFalse(app.buttons["bulk.enqueue"].isEnabled)
        reveal(modes, in: app, upwards: false)
        modes.buttons["Tek bağlantı"].tap()
        XCTAssertTrue(app.buttons["download.start"].exists)
        XCTAssertFalse(app.buttons["download.start"].isEnabled)
    }

    @MainActor
    func testQueueSearchJumpAndHistoryConfirmation() throws {
        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        app.launchEnvironment["RITIM_UI_TEST_BULK_LINKS"] = "3"
        app.launch()
        app.buttons["tab.downloads"].tap()
        reveal(app.buttons["queue.pause"], in: app, upwards: true)
        app.buttons["queue.pause"].tap()
        let modes = app.segmentedControls["bulk.mode"]
        reveal(modes, in: app, upwards: false)
        modes.buttons["Toplu"].tap()
        reveal(app.buttons["bulk.enqueue"], in: app, upwards: true)
        app.buttons["bulk.enqueue"].tap()
        expectLabel("3", on: app.staticTexts["queue.pending"])
        app.terminate()
        app.launchEnvironment["RITIM_UI_TEST_PRESERVE_FIXTURES"] = "1"
        app.launch()
        app.buttons["tab.downloads"].tap()
        XCTAssertTrue(app.buttons["queue.jump"].waitForExistence(timeout: 5))
        app.buttons["queue.jump"].tap()
        let search = app.textFields["queue.search"]
        reveal(search, in: app, upwards: true)
        search.tap(); search.typeText("bulunmayan parca")
        app.keyboards.buttons["Search"].tap()
        XCTAssertTrue(app.staticTexts["Eşleşen indirme bulunamadı."].waitForExistence(timeout: 5))
        reveal(app.buttons["İndirme aramasını temizle"], in: app, upwards: false)
        app.buttons["İndirme aramasını temizle"].tap()
        reveal(app.buttons["queue.cancelAll"], in: app, upwards: false)
        app.buttons["queue.cancelAll"].tap()
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Tümünü iptal et", "queue.cancelAll")).firstMatch.tap()
        let clear = app.buttons["queue.clearFinished"]
        reveal(clear, in: app, upwards: false)
        clear.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Geçmişi temizle", "queue.clearFinished")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        let dismiss = app.buttons["Vazgeç"]
        if dismiss.waitForExistence(timeout: 2) { dismiss.tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1)).tap() }
        XCTAssertTrue(clear.exists, "Vazgeç geçmişi korumalı")
    }

    /// Opt-in live metadata discovery. It never downloads playlist media: the
    /// queue is paused before scan and only two selected entries are enqueued.
    @MainActor
    func testLivePlaylistSearchSelectionAndPausedEnqueue() throws {
        guard let playlistURL = ProcessInfo.processInfo.environment["RITIM_UI_TEST_PLAYLIST_URL"], !playlistURL.isEmpty else {
            throw XCTSkip("Canlı liste önizleme testi için RITIM_UI_TEST_PLAYLIST_URL ayarla.")
        }
        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["tab.downloads"].waitForExistence(timeout: 10))
        app.buttons["tab.downloads"].tap()
        reveal(app.buttons["queue.pause"], in: app, upwards: true)
        app.buttons["queue.pause"].tap()
        let modes = app.segmentedControls["bulk.mode"]
        reveal(modes, in: app, upwards: false)
        modes.buttons["Oynatma listesi"].tap()
        let urlField = app.textFields["playlist.url"].exists ? app.textFields["playlist.url"] : app.textViews["playlist.url"]
        urlField.tap()
        urlField.typeText(playlistURL)
        app.buttons["playlist.resolve"].tap()
        allowLocalNetworkIfNeeded()
        XCTAssertTrue(app.staticTexts["playlist.selectionCount"].waitForExistence(timeout: 120))
        let playlistName = app.staticTexts["playlist.title"].label
        reveal(app.buttons["playlist.clearSelection"], in: app, upwards: true)
        app.buttons["playlist.clearSelection"].tap()

        let search = app.textFields["playlist.search"]
        reveal(search, in: app, upwards: false)
        search.tap()
        search.typeText("ritim-no-match-987654321")
        XCTAssertTrue(app.staticTexts["Aramana uygun parça yok."].waitForExistence(timeout: 3))
        app.buttons["Liste aramasını temizle"].tap()
        app.buttons["playlist.selectAll"].tap()
        app.buttons["playlist.clearSelection"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "playlist.item."))
        XCTAssertGreaterThanOrEqual(rows.count, 2)
        reveal(rows.element(boundBy: 0), in: app, upwards: true)
        rows.element(boundBy: 0).tap()
        reveal(rows.element(boundBy: 1), in: app, upwards: true)
        rows.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["playlist.selectionCount"].label.contains("2 seçili"))
        reveal(app.buttons["playlist.enqueue"], in: app, upwards: true)
        XCTAssertTrue(app.buttons["playlist.enqueue"].isEnabled)
        app.buttons["playlist.enqueue"].tap()
        reveal(app.staticTexts["queue.pending"], in: app, upwards: true)
        expectLabel("2", on: app.staticTexts["queue.pending"])
        expectLabel("0", on: app.staticTexts["queue.running"])
        XCTAssertTrue(app.buttons["queue.resume"].exists)
        capture(app, name: "YouTube-liste-2-secili-duraklatilmis")
        app.buttons["tab.library"].tap()
        XCTAssertTrue(app.staticTexts[playlistName].waitForExistence(timeout: 5), "İndirme grubu için yerel çalma listesi oluşmalı")
    }

    @MainActor
    private func allowLocalNetworkIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 2) {
            for label in ["İzin Ver", "İzin ver", "Allow", "Tamam", "OK"] {
                if springboard.alerts.buttons[label].exists { springboard.alerts.buttons[label].tap(); break }
            }
        }
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<7 {
            if element.exists && element.isHittable { return }
            // Drag in the outer margin so nested playlist/text-editor scrolls
            // cannot consume the gesture intended for the downloads page.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: upwards ? 0.80 : 0.30))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: upwards ? 0.30 : 0.80))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        if !(element.exists && element.isHittable) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "Kuyruk-erisim-agaci"; tree.lifetime = .keepAlways; add(tree)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Kontrol ekranda bulunamadı: \(element)", file: file, line: line)
    }

    @MainActor
    private func expectLabel(_ expected: String, on element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension BulkUITests {
    @MainActor
    func testLocalBackupCreationAndStorageAudit() throws {
        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        app.launch()
        openConcurrentDownloadSetting(in: app)
        let export = app.buttons["Kütüphane bilgilerini yedekle"]
        for _ in 0..<10 {
            if export.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(export.isHittable)
        export.tap()
        let share = app.buttons["Yedeği Dosyalar’a kaydet"]
        for _ in 0..<5 {
            if share.waitForExistence(timeout: 2) { break }
            app.swipeUp()
        }
        XCTAssertTrue(share.exists)
        let audit = app.buttons["Eksik ve yinelenen dosyaları denetle"]
        if !audit.isHittable { app.swipeUp() }
        audit.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Hiçbir dosya silinmedi")).firstMatch.waitForExistence(timeout: 10))
    }
}
