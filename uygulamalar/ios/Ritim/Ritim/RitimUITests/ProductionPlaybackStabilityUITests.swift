import XCTest

/// Explicitly opt-in acceptance against the existing user library and queue.
/// This test never resets fixtures, changes downloads, deletes media, pauses
/// playback, or terminates the app at the end.
final class ProductionPlaybackStabilityUITests: XCTestCase {
    private struct PlaybackSample: Codable {
        let uptime: Double
        let title: String
        let position: String
        let measuredListeningSeconds: Int
        let listeningPeriod: String
        let playbackControl: String
    }

    private struct ProcessSample: Codable {
        let backgroundSeconds: Double
        let applicationState: String
    }

    private struct Report: Codable {
        let requestedBackgroundSeconds: Double
        var actualBackgroundSeconds: Double = 0
        var initialShuffle: String?
        var initialRate: String?
        var before: PlaybackSample?
        var after: PlaybackSample?
        var processSamples: [ProcessSample] = []
    }

    override func setUpWithError() throws { continueAfterFailure = false }

    /// Test runner configuration:
    /// RITIM_UI_TEST_REAL_LIBRARY_STABILITY=1
    /// RITIM_UI_TEST_REAL_LIBRARY_STABILITY_SECONDS=600 (minimum 120 seconds)
    @MainActor
    func testExistingLibraryKeepsPlayingThroughoutUninterruptedBackgroundInterval() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["RITIM_UI_TEST_REAL_LIBRARY_STABILITY"] == "1" else {
            throw XCTSkip("Gerçek kullanıcı kitaplığı kabulü için RITIM_UI_TEST_REAL_LIBRARY_STABILITY=1 gerekli.")
        }
        XCTAssertNotEqual(environment["RITIM_UI_TEST_MODE"], "1", "Gerçek kitaplık testi fixture modu ile çalıştırılmamalı")
        let requested = try XCTUnwrap(Double(environment["RITIM_UI_TEST_REAL_LIBRARY_STABILITY_SECONDS"] ?? "600"))
        XCTAssertTrue(requested.isFinite && (120...43_200).contains(requested), "Süre 120–43200 saniye arasında olmalı")
        var report = Report(requestedBackgroundSeconds: requested)
        defer {
            let attachment = XCTAttachment(string: json(report))
            attachment.name = "Gercek-kitaplik-kesintisiz-arkaplan-olcumleri.json"
            attachment.lifetime = .keepAlways
            add(attachment)
            // Intentionally leave the user's playback and running app alone.
        }

        let app = XCUIApplication()
        // No RITIM_UI_TEST_MODE, fixture reset, preserve flag, or server override:
        // launch the installed application's normal persisted state.
        app.launch()
        let home = app.buttons["tab.home"]
        XCTAssertTrue(home.waitForExistence(timeout: 15))
        home.tap()
        let expand = app.buttons["player.expand"]
        if expand.exists {
            let playPause = app.buttons["miniPlayer.playPause"]
            if playPause.label == "Çal" { playPause.tap() }
        } else {
            let start = app.buttons["Kütüphaneyi çal"]
            reveal(start, in: app)
            start.tap()
        }
        XCTAssertTrue(expand.waitForExistence(timeout: 8))
        expand.tap()
        let repeatMode = app.buttons["player.repeat"]
        XCTAssertTrue(repeatMode.waitForExistence(timeout: 5))
        report.initialShuffle = app.buttons["player.shuffle"].value as? String
        report.initialRate = app.buttons["player.rate"].value as? String
        reveal(repeatMode, in: app)
        switch repeatMode.value as? String {
        case "Kapalı": repeatMode.tap()
        case "Tek parça": repeatMode.tap(); repeatMode.tap()
        case "Tümü": break
        default: XCTFail("Tekrar durumu okunamadı")
        }
        XCTAssertEqual(repeatMode.value as? String, "Tümü")
        XCTAssertEqual(app.buttons["player.shuffle"].value as? String, report.initialShuffle)
        XCTAssertEqual(app.buttons["player.rate"].value as? String, report.initialRate)
        let collapse = app.buttons["Çaları küçült"]
        reveal(collapse, in: app)
        collapse.tap()
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Duraklat"),
                                                object: app.buttons["miniPlayer.playPause"])
        let playingResult = await XCTWaiter.fulfillment(of: [playing], timeout: 10)
        XCTAssertEqual(playingResult, .completed)

        // Let the actual persisted native download queue start in foreground.
        // No test downloads or queue controls replace the user's real workload.
        let foregroundStart = try snapshot(app)
        try await Task.sleep(for: .seconds(15))
        let before = try snapshot(app)
        XCTAssertEqual(before.playbackControl, "Duraklat")
        XCTAssertEqual(before.listeningPeriod, foregroundStart.listeningPeriod)
        XCTAssertGreaterThanOrEqual(before.measuredListeningSeconds - foregroundStart.measuredListeningSeconds, 10,
                                    "Arka plan testinden önce gerçek oynatma ilerlemeli")
        report.before = before
        capture(app, name: "Gercek-kitaplik-arkaplan-oncesi")

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5) || app.state == .runningBackgroundSuspended)
        let backgroundStart = ProcessInfo.processInfo.systemUptime
        let deadline = backgroundStart + requested
        while ProcessInfo.processInfo.systemUptime < deadline {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining > 0 { try await Task.sleep(for: .seconds(min(30, remaining))) }
            // Reading process state does not activate the app or query its UI.
            // There are no screenshots, element queries, or transport operations
            // throughout this single uninterrupted background interval.
            let state = app.state
            let elapsed = ProcessInfo.processInfo.systemUptime - backgroundStart
            report.actualBackgroundSeconds = elapsed
            let sample = ProcessSample(backgroundSeconds: elapsed, applicationState: String(describing: state))
            report.processSamples.append(sample)
            print("Ritim production endurance: background=\(elapsed)s, state=\(state)")
            XCTContext.runActivity(named: "Gerçek kitaplık arka planda \(Int(elapsed)) saniye") { activity in
                let attachment = XCTAttachment(string: json(sample))
                attachment.name = "Arkaplan-islem-durumu-\(Int(elapsed)).json"
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
            XCTAssertTrue(state == .runningBackground || state == .runningBackgroundSuspended,
                          "Kesintisiz arka plan testi boyunca Ritim arka planda çalışıyor olmalı; durum: \(state)")
        }
        report.actualBackgroundSeconds = ProcessInfo.processInfo.systemUptime - backgroundStart

        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        XCTAssertTrue(app.buttons["miniPlayer.playPause"].waitForExistence(timeout: 5))
        // Never tap Play here: a stopped process or paused session must fail.
        XCTAssertEqual(app.buttons["miniPlayer.playPause"].label, "Duraklat")
        let after = try snapshot(app)
        report.after = after
        capture(app, name: "Gercek-kitaplik-arkaplan-sonrasi")
        XCTAssertEqual(after.listeningPeriod, before.listeningPeriod, "Ölçümler aynı dinleme dönemiyle karşılaştırılmalı")
        let listened = Double(after.measuredListeningSeconds - before.measuredListeningSeconds)
        let wall = after.uptime - before.uptime
        XCTAssertGreaterThanOrEqual(listened, max(report.actualBackgroundSeconds - 5, wall * 0.95 - 2),
                                    "Ölçülen gerçek dinleme kesintisiz arka plan süresini karşılamalı")
        XCTAssertLessThanOrEqual(listened, wall * 1.05 + 2, "Dinleme süresi gerçek zamanın üzerinde üretilmemeli")

        expand.tap()
        XCTAssertTrue(repeatMode.waitForExistence(timeout: 5))
        XCTAssertEqual(repeatMode.value as? String, "Tümü")
        XCTAssertEqual(app.buttons["player.shuffle"].value as? String, report.initialShuffle)
        XCTAssertEqual(app.buttons["player.rate"].value as? String, report.initialRate)
        reveal(collapse, in: app)
        collapse.tap()
        XCTAssertEqual(app.buttons["miniPlayer.playPause"].label, "Duraklat")
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication) throws -> PlaybackSample {
        let titleElement = app.staticTexts["dashboard.resume.title"]
        if !titleElement.exists { reveal(titleElement, in: app) }
        XCTAssertTrue(titleElement.exists)
        let title = titleElement.label
        let position = try XCTUnwrap(app.staticTexts["dashboard.resume.elapsed"].value as? String)
        let listening = app.staticTexts["dashboard.totalTime"]
        if !listening.exists { reveal(listening, in: app) }
        let measured = try XCTUnwrap(Int(listening.value as? String ?? ""), "Gerçek dinleme sayacı okunamadı")
        return PlaybackSample(uptime: ProcessInfo.processInfo.systemUptime, title: title, position: position,
                              measuredListeningSeconds: measured, listeningPeriod: listening.label,
                              playbackControl: app.buttons["miniPlayer.playPause"].label)
    }

    private func json<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return "Ölçüm kaydı oluşturulamadı" }
        return String(decoding: data, as: UTF8.self)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable && element.frame.minY > app.frame.minY + 30 && element.frame.maxY < app.frame.maxY - 20 { return }
            let upwards = !element.exists || element.frame.midY > app.frame.midY
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: upwards ? 0.72 : 0.35))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: upwards ? 0.35 : 0.72)))
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



