import XCTest

final class PlaybackEnduranceUITests: XCTestCase {
    private let demoTitles = ["Gece Yolu", "Kıyı", "Yörünge"]
    private let demoDuration: Double = 32

    private struct Sample: Codable {
        let uptime: Double
        let title: String
        let trackIndex: Int
        let position: Int
        let listeningSeconds: Int
    }

    private struct Checkpoint: Codable {
        let backgroundSeconds: Double
        let wallSeconds: Double
        let mediaSecondsAdvanced: Double
        let naturalTransitions: Int
        let measuredListeningDelta: Int
        let before: Sample
        let after: Sample
    }

    override func setUpWithError() throws { continueAfterFailure = false }

    /// Real, bundled 32-second audio fixtures run at normal speed. Only Home and
    /// foreground activation happen during the endurance interval: no seeks,
    /// next-track presses, or transport recovery can hide a playback failure.
    /// Extend via the test runner's RITIM_UI_TEST_PLAYBACK_ENDURANCE_SECONDS=600.
    @MainActor
    func testRepeatAllKeepsPlayingAcrossNaturalTransitionsInBackground() async throws {
        let rawDuration = ProcessInfo.processInfo.environment["RITIM_UI_TEST_PLAYBACK_ENDURANCE_SECONDS"] ?? "150"
        let requestedDuration = try XCTUnwrap(Double(rawDuration), "Dayanıklılık süresi saniye cinsinden olmalı")
        XCTAssertTrue(requestedDuration.isFinite && (150...43_200).contains(requestedDuration),
                      "Dayanıklılık süresi 150–43200 saniye arasında olmalı")

        let app = XCUIApplication()
        app.launchEnvironment["RITIM_UI_TEST_MODE"] = "1"
        // Reset only Caches/RitimUITestFixtures, never the user's Documents media.
        app.launchEnvironment["RITIM_UI_TEST_PRESERVE_FIXTURES"] = "0"
        app.launchEnvironment["RITIM_SERVER_URL"] = "http://127.0.0.1:1"
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()

        var checkpoints: [Checkpoint] = []
        defer {
            let report = XCTAttachment(string: reportJSON(requestedDuration: requestedDuration, checkpoints: checkpoints))
            report.name = "Arkaplan-oynatma-dayaniklilik-olcumleri.json"
            report.lifetime = .keepAlways
            add(report)
            if app.state == .runningBackground || app.state == .runningBackgroundSuspended { app.activate() }
            if app.state == .runningForeground {
                let pause = app.buttons["miniPlayer.playPause"]
                if pause.exists && pause.label == "Duraklat" { pause.tap() }
            }
        }

        let start = app.buttons["Kütüphaneyi çal"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        XCTAssertTrue(app.buttons["player.expand"].waitForExistence(timeout: 5))
        app.buttons["player.expand"].tap()
        let repeatMode = app.buttons["player.repeat"]
        XCTAssertTrue(repeatMode.waitForExistence(timeout: 5))
        reveal(repeatMode, in: app)
        XCTAssertEqual(repeatMode.value as? String, "Kapalı")
        repeatMode.tap()
        XCTAssertEqual(repeatMode.value as? String, "Tümü")
        XCTAssertEqual(app.buttons["player.shuffle"].value as? String, "Kapalı")
        XCTAssertEqual(app.buttons["player.rate"].value as? String, "1×")
        let collapse = app.buttons["Çaları küçült"]
        reveal(collapse, in: app)
        collapse.tap()

        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Duraklat"),
                                                object: app.buttons["miniPlayer.playPause"])
        let playingResult = await XCTWaiter.fulfillment(of: [playing], timeout: 6)
        XCTAssertEqual(playingResult, .completed)
        XCTAssertEqual(app.staticTexts["dashboard.resume.queueCount"].value as? String, "3")
        var previous = try sample(app)
        let initial = previous
        capture(app, name: "Dayaniklilik-baslangic")
        var backgroundTotal: Double = 0
        var totalTransitions = 0

        while backgroundTotal < requestedDuration {
            let interval = min(75, requestedDuration - backgroundTotal)
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5) || app.state == .runningBackgroundSuspended,
                          "Ses çalarken uygulama arka plana geçmeli")
            let backgroundStart = ProcessInfo.processInfo.systemUptime
            // No app queries or activation inside this wait. Short suspensions
            // keep the test runner responsive without touching the media app.
            try await waitInBackground(seconds: interval)
            let actualBackground = ProcessInfo.processInfo.systemUptime - backgroundStart
            let stateBeforeActivation = app.state
            print("Ritim endurance: background=\(actualBackground)s, state=\(stateBeforeActivation)")
            // XCUITest can report suspended while system audio is active. The
            // media position and measured player heartbeats below decide whether
            // playback actually continued; process termination always fails.
            let state = XCTAttachment(string: "backgroundSeconds=\(actualBackground), applicationState=\(stateBeforeActivation)")
            state.name = "Arkaplan-uygulama-durumu-\(checkpoints.count + 1)"
            state.lifetime = .keepAlways
            add(state)
            XCTAssertTrue(stateBeforeActivation == .runningBackground || stateBeforeActivation == .runningBackgroundSuspended,
                          "Arka plan ses uygulaması kapanmış olmamalı")
            app.activate()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
            XCTAssertTrue(app.buttons["miniPlayer.playPause"].waitForExistence(timeout: 4))
            XCTAssertEqual(app.buttons["miniPlayer.playPause"].label, "Duraklat",
                           "Öne gelince kullanıcı yeniden Çal'a basmadan ses devam etmeli")
            XCTAssertFalse(app.alerts["İşlem tamamlanamadı"].exists)
            let current = try sample(app)
            let wall = current.uptime - previous.uptime
            XCTAssertLessThan(wall, demoDuration * Double(demoTitles.count),
                              "Ölçüm aralığı bir tam sıra döngüsünden kısa olmalı; aksi hâlde geçiş sayısı belirsizleşir")
            // Each background block is shorter than a whole 96-second queue.
            // The queue index and actual media position reveal natural advances,
            // including last -> first; measured listening independently checks
            // continuity so a merely changing title cannot pass this test.
            var transitions = current.trackIndex - previous.trackIndex
            var advanced = Double(transitions) * demoDuration + Double(current.position - previous.position)
            if advanced < -1 { transitions += demoTitles.count; advanced += demoDuration * Double(demoTitles.count) }
            let listened = current.listeningSeconds - previous.listeningSeconds
            let checkpoint = Checkpoint(backgroundSeconds: actualBackground, wallSeconds: wall,
                                        mediaSecondsAdvanced: advanced, naturalTransitions: transitions,
                                        measuredListeningDelta: listened, before: previous, after: current)
            checkpoints.append(checkpoint)
            backgroundTotal += actualBackground
            totalTransitions += transitions
            XCTContext.runActivity(named: "Arka plan \(Int(backgroundTotal)) sn · \(current.title) · \(totalTransitions) doğal geçiş") { activity in
                let attachment = XCTAttachment(string: encode(checkpoint))
                attachment.name = "Arkaplan-kontrol-\(checkpoints.count).json"
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
            XCTAssertGreaterThanOrEqual(advanced, wall - 4, "Gerçek medya konumu arka plandaki süre kadar ilerlemeli")
            XCTAssertLessThanOrEqual(advanced, wall + 4, "Parçalar kendiliğinden atlanmamalı")
            XCTAssertGreaterThanOrEqual(Double(listened), wall - 3,
                                        "AVPlayer kalp atışıyla ölçülen gerçek dinleme arka planda kesilmemeli")
            if checkpoints.count <= 3 || checkpoints.count.isMultiple(of: 15) || backgroundTotal >= requestedDuration {
                capture(app, name: "Dayaniklilik-\(Int(backgroundTotal))-saniye")
            }
            previous = current
        }

        XCTAssertGreaterThanOrEqual(totalTransitions, 3, "En az üç doğal parça geçişi ve sıra döngüsü sınanmalı")
        let totalWall = previous.uptime - initial.uptime
        XCTAssertGreaterThanOrEqual(Double(previous.listeningSeconds - initial.listeningSeconds),
                                    totalWall - max(6, totalWall * 0.02),
                                    "Toplam dinleme kısa kontroller arasındaki birikimli kesintileri de yakalamalı")
        XCTAssertEqual(app.buttons["miniPlayer.playPause"].label, "Duraklat")
        app.buttons["player.expand"].tap()
        XCTAssertTrue(repeatMode.waitForExistence(timeout: 4))
        XCTAssertEqual(repeatMode.value as? String, "Tümü")
        XCTAssertEqual(app.buttons["player.shuffle"].value as? String, "Kapalı")
        XCTAssertEqual(app.buttons["player.rate"].value as? String, "1×")
        reveal(app.buttons["Çaları küçült"], in: app)
        app.buttons["Çaları küçült"].tap()
    }

    @MainActor
    private func sample(_ app: XCUIApplication) throws -> Sample {
        let title = app.staticTexts["dashboard.resume.title"]
        let elapsed = app.staticTexts["dashboard.resume.elapsed"]
        // The seven-day fixture total also works when an hours-long run crosses
        // midnight; today's counter would correctly reset and look like a stall.
        let listening = app.staticTexts["dashboard.totalTime"]
        XCTAssertTrue(title.waitForExistence(timeout: 4))
        if !listening.exists { reveal(listening, in: app) }
        XCTAssertTrue(listening.exists, "Gerçek dinleme sayacı görünür olmalı")
        for _ in 0..<3 {
            let observedTitle = title.label
            let position = try seconds(try XCTUnwrap(elapsed.value as? String))
            let listened = try XCTUnwrap(Int(listening.value as? String ?? ""))
            guard observedTitle == title.label else { continue }
            let index = try XCTUnwrap(demoTitles.firstIndex(of: observedTitle), "Yalnızca izole özgün demo parçaları kullanılmalı")
            return Sample(uptime: ProcessInfo.processInfo.systemUptime, title: observedTitle,
                          trackIndex: index, position: position, listeningSeconds: listened)
        }
        throw NSError(domain: "PlaybackEnduranceUITests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Parça değişimi sırasında tutarlı konum örneği alınamadı"])
    }

    private func seconds(_ text: String) throws -> Int {
        let parts = text.split(separator: ":")
        XCTAssertTrue((2...3).contains(parts.count))
        return try parts.reduce(0) { try $0 * 60 + XCTUnwrap(Int($1)) }
    }

    private func waitInBackground(seconds: Double) async throws {
        let end = ProcessInfo.processInfo.systemUptime + seconds
        while ProcessInfo.processInfo.systemUptime < end {
            try await Task.sleep(for: .seconds(min(20, end - ProcessInfo.processInfo.systemUptime)))
        }
    }

    private func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return "JSON ölçüm kaydı oluşturulamadı" }
        return String(decoding: data, as: UTF8.self)
    }

    private func reportJSON(requestedDuration: Double, checkpoints: [Checkpoint]) -> String {
        struct Report: Encodable {
            let requestedBackgroundSeconds: Double
            let completedBackgroundSeconds: Double
            let observedNaturalTransitions: Int
            let checkpoints: [Checkpoint]
        }
        return encode(Report(requestedBackgroundSeconds: requestedDuration,
                             completedBackgroundSeconds: checkpoints.reduce(0) { $0 + $1.backgroundSeconds },
                             observedNaturalTransitions: checkpoints.reduce(0) { $0 + $1.naturalTransitions }, checkpoints: checkpoints))
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
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
