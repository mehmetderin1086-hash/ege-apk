import XCTest
final class FlowTests: XCTestCase {
    func testLocalRoundShowsFeedbackAndNextQuestion() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-new-round"]; app.launch()
        app.buttons["startLocal"].tap()
        XCTAssertTrue(app.staticTexts["question"].waitForExistence(timeout: 5))
        app.buttons["answer0"].tap()
        XCTAssertTrue(app.buttons["nextQuestion"].waitForExistence(timeout: 5))
        app.buttons["nextQuestion"].tap()
        XCTAssertTrue(app.staticTexts["question"].exists)
    }
    func testLiveAIGeneratesPlayableQuestions() throws {
        guard ProcessInfo.processInfo.environment["BILGI_LIVE_UI"] == "1" else { throw XCTSkip("Gerçek iPhone CLI Proxy hesapları gerektirir") }
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-new-round"]
        app.launch()
        if app.alerts.firstMatch.waitForExistence(timeout: 2) { XCTFail("Başlangıç uyarısı: \(app.alerts.firstMatch.debugDescription)"); return }
        let start = app.buttons["startAI"]
        if !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.waitForExistence(timeout: 5)); start.tap()
        XCTAssertTrue(app.staticTexts["question"].waitForExistence(timeout: 140), "AI soru ekranı açılmadı: \(app.alerts.firstMatch.label)")
        app.buttons["answer0"].tap()
        XCTAssertTrue(app.buttons["nextQuestion"].waitForExistence(timeout: 5))
    }
}

extension FlowTests {
    func testVisualTourShowsEveryKindAndSupportsEnlargement() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-new-round"]; app.launch()
        app.buttons["startVisualTour"].tap()
        let kinds = ["diagram","image","table","barChart","lineChart"]
        for kind in kinds {
            XCTAssertTrue(app.staticTexts["question"].waitForExistence(timeout:5))
            XCTAssertTrue(app.descendants(matching:.any)["questionVisual-"+kind].firstMatch.waitForExistence(timeout:5))
            let inline = XCTAttachment(screenshot:app.screenshot()); inline.name = "Soru-"+kind; inline.lifetime = .keepAlways; add(inline)
            app.buttons["Büyüt"].firstMatch.tap()
            XCTAssertTrue(app.buttons["closeVisual"].waitForExistence(timeout:5))
            let zoom = app.sliders["Görsel büyütme oranı"]
            zoom.adjust(toNormalizedSliderPosition:0.5); zoom.adjust(toNormalizedSliderPosition:0)
            let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Gorsel-"+kind; shot.lifetime = .keepAlways; add(shot)
            app.buttons["closeVisual"].tap()
            app.buttons["answer0"].tap()
            XCTAssertTrue(app.buttons["nextQuestion"].waitForExistence(timeout:5))
            app.buttons["nextQuestion"].tap()
        }
        app.swipeDown(); app.swipeDown()
        app.buttons["Oyundan çık"].tap(); XCTAssertTrue(app.buttons["Turdan çık"].waitForExistence(timeout:5)); app.buttons["Turdan çık"].tap()
        XCTAssertTrue(app.buttons["startVisualTour"].waitForExistence(timeout:5))
    }

    func testVisualTrainingRoundThroughResult() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-new-round"]; app.launch()
        func capture(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
        capture("01-Ana-Ekran")
        app.swipeUp()
        app.buttons["Öğren"].tap()
        app.swipeDown()
        let science = app.buttons["Bilim"]
        for _ in 0..<6 {
            if science.exists && science.frame.minY > 100 && science.frame.maxY < app.frame.height-130 { break }
            if science.exists && science.frame.minY < 100 { app.swipeDown(velocity:.slow) }
            else { app.swipeUp(velocity:.slow) }
        }
        app.buttons["Bilim"].tap()
        XCTAssertTrue(app.buttons["Bilim"].isSelected)
        capture("01b-Kategoriler")
        app.buttons["startLocal"].tap()
        XCTAssertTrue(app.staticTexts["question"].waitForExistence(timeout: 5))
        capture("02-Soru")
        for index in 0..<6 {
            XCTAssertTrue(app.staticTexts["question"].isHittable, "Yeni soru görünür olmalı")
            app.buttons["answer0"].tap()
            XCTAssertTrue(app.buttons["nextQuestion"].waitForExistence(timeout: 5))
            if index == 0 { capture("03-Cevap") }
            app.buttons["nextQuestion"].tap()
        }
        XCTAssertTrue(app.staticTexts["roundResult"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Yeni oyun"].exists)
        capture("04-Sonuc")
    }

    func testTrainingAndPhoneModelCenter() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-new-round"]; app.launch()
        app.swipeUp()
        app.buttons["Öğren"].tap()
        app.buttons["startLocal"].tap()
        XCTAssertTrue(app.staticTexts["question"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Süresiz öğrenme"].firstMatch.exists)
        app.buttons["Oyundan çık"].tap()
        app.buttons["Turdan çık"].tap()
        app.tabBars.buttons["Modeller"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["iPhone → sağlayıcı"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.secureTextFields.count, 0)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Model-Merkezi"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testQuestionPoolSearchShowsBundledContent() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-new-round"]; app.launch()
        app.buttons["openQuestionPool"].tap()
        XCTAssertTrue(app.switches["automaticPool"].waitForExistence(timeout:5))
        let field = app.textFields["poolSearch"]
        field.tap(); field.typeText("Tutunamayanlar\n")
        let question = app.staticTexts["Tutunamayanlar romanının yazarı kimdir?"]
        XCTAssertTrue(question.waitForExistence(timeout:5))
        question.tap()
        XCTAssertTrue(app.staticTexts["Doğru cevap: Oğuz Atay"].waitForExistence(timeout:5))
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Soru-Havuzu-Arama"; shot.lifetime = .keepAlways; add(shot)
    }
}

extension FlowTests {
    func testSessionModesAudioSettingsAndStageTransitions() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-new-round"]; app.launch()
        func reach(_ button: XCUIElement) {
            for _ in 0..<8 { if button.exists && button.isHittable && button.frame.minY > 100 && button.frame.maxY < app.frame.height-110 { return }; if button.exists && button.frame.minY < 100 { app.swipeDown(velocity:.slow) } else { app.swipeUp(velocity:.slow) } }
        }
        let short = app.buttons["Kısa Tur"]; reach(short); short.tap()
        let settings = app.buttons["Süre ayarları"]; reach(settings); settings.tap()
        XCTAssertTrue(app.buttons["roundMinutes"].waitForExistence(timeout:5))
        app.tabBars.buttons["Ayarlar"].tap()
        XCTAssertTrue(app.switches["voiceAlerts"].waitForExistence(timeout:5))
        let voice = app.switches["voiceAlerts"]
        if voice.value as? String == "0" { voice.coordinate(withNormalizedOffset:CGVector(dx:0.92,dy:0.5)).tap() }
        app.buttons["testGameSound"].tap()
        let engine = app.buttons["questionVoiceEngine"]; reach(engine); XCTAssertTrue(engine.exists)
        let preview = app.buttons["previewQuestionVoice"]; reach(preview); XCTAssertTrue(preview.exists)
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Sure-Ses-Ayarlari"; shot.lifetime = .keepAlways; add(shot)
        reach(voice); voice.coordinate(withNormalizedOffset:CGVector(dx:0.92,dy:0.5)).tap()
        app.tabBars.buttons["Oyna"].tap()
        let start = app.buttons["startLocal"]; reach(start); start.tap()
        XCTAssertTrue(app.staticTexts["question"].waitForExistence(timeout:5))
        XCTAssertTrue(app.descendants(matching:.any)["roundClock"].firstMatch.exists)
        app.buttons["Duraklat"].tap()
        XCTAssertTrue(app.buttons["Oyuna devam et"].exists)
        app.buttons["Oyundan çık"].tap(); XCTAssertTrue(app.buttons["Turdan çık"].waitForExistence(timeout:5)); app.buttons["Turdan çık"].tap()
        app.terminate(); app.launch()
        let stages = app.buttons["Etaplı Tur"]; reach(stages); stages.tap()
        reach(start); start.tap()
        XCTAssertTrue(app.staticTexts["stageLabel"].waitForExistence(timeout:5))
        for index in 0..<10 {
            app.buttons["answer0"].tap(); app.buttons["nextQuestion"].tap()
            if index == 3 || index == 6 {
                XCTAssertTrue(app.staticTexts["stageBreak"].waitForExistence(timeout:5))
                XCTAssertTrue(app.staticTexts["stageBreak"].label.contains(index == 3 ? "Odak" : "Final"))
                let stageShot = XCTAttachment(screenshot:app.screenshot()); stageShot.name = "Etap-\(index)"; stageShot.lifetime = .keepAlways; add(stageShot)
                let next = app.buttons["Devam et"]; reach(next); next.tap()
            }
        }
        XCTAssertTrue(app.staticTexts["roundResult"].waitForExistence(timeout:5))
        app.buttons["Yeni oyun"].tap()
    }
}

extension FlowTests {
    func testListeningOrderingAndMatchingTour() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-new-round"]; app.launch()
        app.buttons["startActivityTour"].tap()
        let answer = app.buttons["answer0"]
        XCTAssertTrue(answer.waitForExistence(timeout:5)); XCTAssertFalse(answer.isEnabled)
        XCTAssertFalse(app.staticTexts["listeningTranscript"].exists)
        app.buttons["playQuestionAudio"].tap()
        let enabled = NSPredicate(format:"enabled == true")
        expectation(for:enabled,evaluatedWith:answer)
        waitForExpectations(timeout:25)
        XCTAssertFalse(app.staticTexts["questionAudioError"].exists)
        let listening = XCTAttachment(screenshot:app.screenshot()); listening.name = "Dinleme-Hazir"; listening.lifetime = .keepAlways; add(listening)
        app.buttons["playQuestionAudio"].tap()
        XCTAssertFalse(answer.isEnabled)
        app.buttons["showListeningTranscript"].tap()
        XCTAssertTrue(app.staticTexts["listeningTranscript"].exists); XCTAssertTrue(answer.isEnabled)
        answer.tap(); app.buttons["nextQuestion"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["activityBoard-ordering"].firstMatch.waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["submitActivity"].isEnabled)
        for number in ["10","20","30","40"] { app.buttons[number].tap() }
        let ordering = XCTAttachment(screenshot:app.screenshot()); ordering.name = "Siralama-Yanit"; ordering.lifetime = .keepAlways; add(ordering)
        app.buttons["submitActivity"].tap()
        XCTAssertTrue(app.staticTexts["Harika, doğru cevap!"].waitForExistence(timeout:5))
        app.buttons["nextQuestion"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["activityBoard-matching"].firstMatch.waitForExistence(timeout:5))
        for pair in [("Cat","Kedi"),("Book","Kitap"),("Water","Su"),("Sun","Güneş")] {
            app.buttons["Sol: "+pair.0].tap(); app.buttons["Sağ: "+pair.1].tap()
        }
        let matching = XCTAttachment(screenshot:app.screenshot()); matching.name = "Eslestirme-Yanit"; matching.lifetime = .keepAlways; add(matching)
        app.buttons["submitActivity"].tap()
        XCTAssertTrue(app.staticTexts["Harika, doğru cevap!"].waitForExistence(timeout:5))
        app.buttons["Oyundan çık"].tap(); XCTAssertTrue(app.buttons["Turdan çık"].waitForExistence(timeout:5)); app.buttons["Turdan çık"].tap()
        XCTAssertTrue(app.buttons["startActivityTour"].waitForExistence(timeout:5))
    }
}

extension FlowTests {
    func testVoiceAnswerPreviewSheetKeepsRound() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-new-round"]; app.launch()
        app.buttons["startActivityTour"].tap()
        app.buttons["showListeningTranscript"].tap()
        let voice = app.buttons["openVoiceAnswer"]
        if !voice.isHittable { app.swipeUp() }
        voice.tap()
        XCTAssertTrue(app.staticTexts["Cihazda Whisper"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["prepareWhisper"].exists)
        XCTAssertFalse(app.buttons["confirmVoiceAnswer"].exists)
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Sesli-Cevap"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Kapat"].tap()
        XCTAssertTrue(app.staticTexts["question"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["answer0"].isEnabled)
    }
    func testLessonChoiceAndPoolExport() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-new-round"]; app.launch()
        func reach(_ element: XCUIElement) {
            for _ in 0..<12 {
                if element.exists && element.isHittable && element.frame.minY > 100 && element.frame.maxY < app.frame.height-100 { return }
                if element.exists && element.frame.minY < 100 { app.swipeDown(velocity:.slow) } else { app.swipeUp(velocity:.slow) }
            }
        }
        let exam = app.buttons["Sınav Hazırlık"]; reach(exam); exam.tap()
        let examPicker = app.buttons["studyExam"]; reach(examPicker); examPicker.tap(); app.buttons["TYT"].firstMatch.tap()
        let lesson = app.buttons["studyLesson"]; reach(lesson); lesson.tap(); app.buttons["Biyoloji"].tap()
        XCTAssertTrue(lesson.label.contains("Biyoloji"))
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Ders-Secimi"; shot.lifetime = .keepAlways; add(shot)
        let pool = app.buttons["openQuestionPool"]; reach(pool); pool.tap()
        let transfer = app.buttons["Paylaşım ve toplu içe aktarma"]; reach(transfer); transfer.tap()
        let export = app.buttons["exportWholePool"]; reach(export); export.tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout:10),app.debugDescription)
        let share = XCTAttachment(screenshot:app.screenshot()); share.name = "Havuzu-Paylas"; share.lifetime = .keepAlways; add(share)
    }
}


extension FlowTests {
    func testSingleQuestionExportOpensSystemShareSheet() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-new-round"]; app.launch()
        app.buttons["startLocal"].tap()
        XCTAssertTrue(app.staticTexts["question"].waitForExistence(timeout:5))
        app.buttons["answer0"].tap()
        let share = app.buttons["Soruyu paylaş"]
        if !share.isHittable { app.swipeUp() }
        share.tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout:5))
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Tek-Soru-Paylas"; shot.lifetime = .keepAlways; add(shot)
    }
}

extension FlowTests {
    func testLiveQuizReadsListensReviewsAndAdvancesToResult() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-new-round","--ui-test-live"]; app.launch()
        let start = app.buttons["startLiveQuiz"]
        for _ in 0..<8 { if start.exists && start.isHittable && start.frame.maxY < app.frame.height-100 { break }; app.swipeUp() }
        start.tap()
        XCTAssertTrue(app.descendants(matching:.any)["liveQuizPanel"].firstMatch.waitForExistence(timeout:5))
        let status = app.staticTexts["liveDockStatus"]
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","Sunucu soruyu okuyor"),object:status)],timeout:5),.completed)
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","Seni dinliyorum"),object:status)],timeout:8),.completed)
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Canli-Dinleme"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(app.staticTexts["liveQuizPreview"].waitForExistence(timeout:8))
        let review = XCTAttachment(screenshot:app.screenshot()); review.name = "Canli-Yanit-Onizleme"; review.lifetime = .keepAlways; add(review)
        XCTAssertTrue(app.staticTexts["roundResult"].waitForExistence(timeout:30))
    }
    func testLiveQuizPauseAndResumePreservesCurrentQuestion() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-new-round","--ui-test-live"]; app.launch()
        let start = app.buttons["startLiveQuiz"]
        for _ in 0..<8 { if start.exists && start.isHittable && start.frame.maxY < app.frame.height-100 { break }; app.swipeUp() }
        start.tap()
        XCTAssertTrue(app.buttons["liveDockPause"].waitForExistence(timeout:5)); app.swipeUp()
        XCTAssertTrue(app.staticTexts["liveDockStatus"].isHittable); app.buttons["liveDockPause"].tap()
        XCTAssertEqual(app.staticTexts["liveDockStatus"].label,"Canlı tur duraklatıldı")
        XCTAssertFalse(app.staticTexts["liveQuizPreview"].exists)
        app.buttons["liveDockResume"].tap()
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","Sunucu soruyu okuyor"),object:app.staticTexts["liveDockStatus"])],timeout:5),.completed)
    }

    func testSettingsTabVoiceAnswerAndDataControls() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-new-round"]; app.launch()
        func reach(_ element: XCUIElement) {
            for _ in 0..<12 {
                if element.exists && element.isHittable && element.frame.minY > 100 && element.frame.maxY < app.frame.height-100 { return }
                if element.exists && element.frame.minY < 100 { app.swipeDown(velocity:.slow) } else { app.swipeUp(velocity:.slow) }
            }
        }
        app.tabBars.buttons["Ayarlar"].tap()
        XCTAssertTrue(app.switches["hapticsEnabled"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["speechRate"].exists)
        let status = app.staticTexts["whisperStatus"]; reach(status); XCTAssertTrue(status.exists)
        let autoSubmit = app.switches["voiceAutoSubmit"]; reach(autoSubmit)
        let before = autoSubmit.value as? String
        autoSubmit.coordinate(withNormalizedOffset:CGVector(dx:0.92,dy:0.5)).tap()
        XCTAssertNotEqual(autoSubmit.value as? String,before)
        autoSubmit.coordinate(withNormalizedOffset:CGVector(dx:0.92,dy:0.5)).tap()
        XCTAssertTrue(app.buttons["voiceSilence"].exists); XCTAssertTrue(app.buttons["voiceMaxSeconds"].exists)
        let live = app.buttons["liveEngine"]; reach(live); XCTAssertTrue(live.exists)
        XCTAssertTrue(app.buttons["liveReviewSeconds"].exists)
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Ayarlar-Sesli-Yanit"; shot.lifetime = .keepAlways; add(shot)
        let reset = app.buttons["resetProgress"]; reach(reset); reset.tap()
        let confirm = app.buttons.matching(NSPredicate(format:"label == %@ AND identifier != %@","İlerlemeyi sıfırla","resetProgress")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout:5)); confirm.tap()
        XCTAssertTrue(app.staticTexts["settingsNotice"].waitForExistence(timeout:5))
        let privacy = app.buttons["Gizlilik"]; reach(privacy); privacy.tap()
        XCTAssertTrue(app.navigationBars["Gizlilik"].waitForExistence(timeout:5))
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["İlerleme"].tap()
        XCTAssertTrue(app.tabBars.buttons["İlerleme"].isSelected)
    }
}
