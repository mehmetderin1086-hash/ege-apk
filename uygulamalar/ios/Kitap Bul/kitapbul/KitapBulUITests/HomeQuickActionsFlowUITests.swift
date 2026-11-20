import XCTest

/// Yalnız -ui-testing bellek/JSON fixture'ı ve ayrı DEBUG tercih anahtarıyla çalışır.
/// Tercih yeniden açılışında yeni katalog fixture'ı kurulur; düzen book UUID'lerine bağlı değildir.
final class HomeQuickActionsFlowUITests: XCTestCase {
    private var app: XCUIApplication!
    private let baseArguments = [
        "-ui-testing", "-ui-testing-reset-navigation", "-onboardingShown", "YES",
        "-lastSeenWhatsNewVersion", "1.0", "-roleLockEnabled", "NO",
        "-visualEffectsEnabled", "NO", "-edgeSwipeTabs", "NO", "-appearanceMode", "light",
        "-simpleMode", "NO", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.mehmetderin.kitapkatalogu")
        app.launchArguments = baseArguments + ["-ui-testing-home-actions-reset"]
        app.launch()
        app.launchArguments = baseArguments // Sonraki launch gerçek kayıtlı tercihi okur.
        openHome()
    }

    override func tearDownWithError() throws {
        // Başarısız testte de yalnız UI-test anahtarı temizlenir. Gerçek tercih dokunulmaz.
        if let app {
            app.terminate()
            app.launchArguments = baseArguments + ["-ui-testing-home-actions-reset"]
            app.launch()
            app.terminate()
        }
        app = nil
    }

    func testSabitGorevlerVeIptalKaydetYenidenAcilis() {
        assertFirstScreenTasks(findBookVisible: true)

        openConfiguration()
        tap(orderButton("Kapak", "yukarı"))
        tap(removeButton("Barkod"))
        app.navigationBars.buttons["Vazgeç"].tap()
        let discard = app.buttons["Kaydetmeden kapat"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5)); discard.tap()
        waitForConfigurationToClose()

        // İptal edilmiş taslak uygulama kapanınca kalıcı seçim/sırayı değiştirmemeli.
        restart()
        openConfiguration()
        let barcodeUp = orderButton("Barkod", "yukarı")
        reveal(removeButton("Barkod")) // Disabled Yukarı kontrolünün hittable olması gerekmez.
        XCTAssertTrue(barcodeUp.exists)
        XCTAssertFalse(barcodeUp.isEnabled, "Varsayılan ilk kısayol iptalden sonra Barkod olmalı")
        XCTAssertTrue(removeButton("Barkod").exists)
        XCTAssertTrue(orderButton("Kapak", "yukarı").isEnabled)

        tap(orderButton("Kapak", "yukarı"))
        tap(removeButton("Barkod"))
        saveConfiguration()
        assertComesBefore("Kapak", "Sesle")

        restart()
        openConfiguration()
        let coverUp = orderButton("Kapak", "yukarı")
        reveal(removeButton("Kapak"))
        XCTAssertTrue(coverUp.exists)
        XCTAssertFalse(coverUp.isEnabled, "Kaydedilen Kapak ilk sırada yeniden açılmalı")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "home.configure.selected.barcode").firstMatch.exists)
        reveal(app.buttons["home.configure.add.barcode"])
        XCTAssertTrue(app.buttons["home.configure.add.barcode"].exists, "Kaldırılan Barkod yeniden eklenebilir olmalı")
    }

    func testSadeModIlkUcSecimiGosterirTamDuzendeSecimKaybolmaz() {
        openConfiguration()
        tap(removeButton("Barkod"))
        tap(orderButton("Sesle", "yukarı"))
        saveConfiguration() // Seçili sıra: Sesle, Kapak, Seri, Elle, Asistan, Yönetim.

        restart(simpleMode: true)
        assertComesBefore("Sesle", "Kapak")
        reveal(app.buttons["home.action.Seri"])
        XCTAssertTrue(app.buttons["home.action.Seri"].exists)
        for hidden in ["Elle", "Asistan", "Yönetim"] {
            XCTAssertFalse(app.buttons["home.action.\(hidden)"].exists, "Sade mod yalnız seçili ilk üç ek kısayolu çizer")
        }
        // Gizlemek kaydı kısaltmamalı: yeni katalog fixture'ıyla tam düzen geri açılır.
        restart(simpleMode: false)
        assertComesBefore("Sesle", "Kapak")
        for restored in ["Seri", "Elle", "Asistan", "Yönetim"] {
            let action = app.buttons["home.action.\(restored)"]
            reveal(action)
            XCTAssertTrue(action.exists, "Tam tercih yeniden açılışta korunmalı: \(restored)")
        }
    }

    /// Sade modda (en az xxLarge) ve büyük yazıda da üç görev ilk ekranda kalır; "Kitap nerede?"
    /// satırı görevlerden sonra, istatistiklerden önce gelir ve görevleri aşağı itmez.
    func testIlkEkranSadeModVeBuyukYazidaKorunur() {
        let durumlar: [(sade: Bool, boyut: String, satirGorunur: Bool)] = [
            (true, "UICTContentSizeCategoryL", true),
            (false, "UICTContentSizeCategoryXXXL", true),
            (false, "UICTContentSizeCategoryAccessibilityXXXL", false)
        ]
        for durum in durumlar {
            restart(simpleMode: durum.sade, contentSize: durum.boyut)
            assertFirstScreenTasks(findBookVisible: durum.satirGorunur, context: "sade=\(durum.sade) \(durum.boyut)")
        }
    }

    /// Kaydırmadan üç görev ilk ekranda ve sırayla; ardından "Kitap nerede?", sonra istatistikler.
    private func assertFirstScreenTasks(findBookVisible: Bool, context: String = "varsayılan",
                                        file: StaticString = #filePath, line: UInt = #line) {
        let tasks = ["lend", "returnLoan", "addBook"].map { app.buttons["home.task.\($0)"] }
        for task in tasks {
            XCTAssertTrue(task.waitForExistence(timeout: 5), file: file, line: line)
            XCTAssertTrue(isVisibleAndHittable(task), "Ana görev ilk ekranda görünür olmalı (\(context))", file: file, line: line)
        }
        XCTAssertLessThan(tasks[0].frame.minY, tasks[1].frame.minY, file: file, line: line)
        XCTAssertLessThan(tasks[1].frame.minY, tasks[2].frame.minY, file: file, line: line)
        let findBook = app.buttons["home.findBook"]
        XCTAssertTrue(findBook.waitForExistence(timeout: 5), file: file, line: line)
        if findBookVisible {
            XCTAssertTrue(isVisibleAndHittable(findBook), "Kitap nerede? ilk ekranda görünür olmalı (\(context))", file: file, line: line)
        }
        let stats = app.buttons["home.titles"]
        XCTAssertTrue(stats.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertLessThanOrEqual(tasks[2].frame.maxY, findBook.frame.minY, "Kitap nerede? görevlerden sonra gelmeli (\(context))", file: file, line: line)
        XCTAssertLessThanOrEqual(findBook.frame.maxY, stats.frame.minY, "Kitap nerede? istatistiklerden önce gelmeli (\(context))", file: file, line: line)
    }

    private func openHome() {
        let home = app.tabBars.buttons["Ana Sayfa"]
        XCTAssertTrue(home.waitForExistence(timeout: 8)); home.tap()
    }
    private func openConfiguration() {
        openHome()
        let edit = app.buttons["home.actions.edit"]
        guard reveal(edit) else { return }
        XCTAssertGreaterThanOrEqual(edit.frame.width, 44, "Düzenle düğmesinin gerçek dokunma alanı en az 44 pt geniş olmalı")
        XCTAssertGreaterThanOrEqual(edit.frame.height, 44, "Düzenle düğmesinin gerçek dokunma alanı en az 44 pt yüksek olmalı")
        edit.tap()
        XCTAssertTrue(app.navigationBars["Hızlı işlemleri düzenle"].waitForExistence(timeout: 5))
    }
    private func saveConfiguration() {
        let save = app.navigationBars.buttons["Kaydet"]
        XCTAssertTrue(save.waitForExistence(timeout: 5)); save.tap()
        waitForConfigurationToClose()
    }
    private func waitForConfigurationToClose() {
        let closed = NSPredicate { _, _ in !self.app.navigationBars["Hızlı işlemleri düzenle"].exists }
        expectation(for: closed, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
    }
    private func restart(simpleMode: Bool = false, contentSize: String? = nil) {
        app.terminate()
        var args = baseArguments
        if let index = args.firstIndex(of: "-simpleMode") { args[index + 1] = simpleMode ? "YES" : "NO" }
        if let contentSize, let index = args.firstIndex(of: "-UIPreferredContentSizeCategoryName") { args[index + 1] = contentSize }
        app.launchArguments = args // reset-home flag ve raw tercihi maskeleyen launch argümanı yok.
        app.launch()
        openHome()
    }
    private func orderButton(_ title: String, _ direction: String) -> XCUIElement {
        app.buttons["\(title) kısayolunu \(direction) taşı"]
    }
    private func removeButton(_ title: String) -> XCUIElement { app.buttons["\(title) kısayolunu kaldır"] }
    private func tap(_ element: XCUIElement) {
        guard reveal(element) else { return }
        XCTAssertTrue(element.isEnabled)
        element.tap()
    }

    /// Lazy satırları büyük fling hareketleriyle aşmadan, gerçek görünür alan içinde arar.
    /// Eksik düğümün identifier/frame getter'ı çağrılmaz; hata asıl görünürlük iddiasını korur.
    @discardableResult
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        var searchedFromTop = false
        for _ in 0..<16 {
            if isVisibleAndHittable(element) { return true }
            let viewport = visibleScrollFrame()
            if element.exists {
                let frame = element.frame
                if frame.maxY <= viewport.minY + 1 {
                    shortDrag(up: false)
                } else if frame.minY < viewport.minY {
                    shortDrag(up: false)
                } else {
                    shortDrag(up: true)
                }
            } else if !searchedFromTop {
                resetToTop()
                searchedFromTop = true
            } else {
                shortDrag(up: true)
            }
        }
        if !isVisibleAndHittable(element) {
            // Görsel kontrol ile AX türü/kimliği ayrılır; başarısızlık yine gerçek assertion'dır.
            print("HOME_ACTIONS_AX|\(app.debugDescription)")
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Home-QuickActions-Reveal-Failure"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertTrue(isVisibleAndHittable(element), "Kontrol kısa kaydırmalarla görünür olmadı", file: file, line: line)
        return false
    }

    private func activeScrollRoot() -> XCUIElement {
        // Düzenleme formu native List; Ana Sayfa ilk dikey ScrollView'dır.
        if app.navigationBars["Hızlı işlemleri düzenle"].exists, app.collectionViews.firstMatch.exists {
            return app.collectionViews.firstMatch
        }
        let root = app.scrollViews.firstMatch
        return root.exists ? root : app
    }

    private func visibleScrollFrame() -> CGRect {
        let nav = app.navigationBars.firstMatch
        let top = nav.exists ? nav.frame.maxY : app.frame.minY
        let bar = app.tabBars.firstMatch
        let bottom = bar.exists ? bar.frame.minY : app.frame.maxY - 20
        let visibleWindow = CGRect(x: app.frame.minX + 16, y: top + 4,
                                   width: app.frame.width - 32, height: max(1, bottom - top - 8))
        let rootFrame = activeScrollRoot().frame.intersection(visibleWindow)
        return rootFrame.isNull || rootFrame.height < 80 ? visibleWindow : rootFrame
    }

    private func shortDrag(up: Bool) {
        let viewport = visibleScrollFrame()
        let fromY = viewport.minY + viewport.height * (up ? 0.70 : 0.40)
        let toY = viewport.minY + viewport.height * (up ? 0.40 : 0.70)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: viewport.midX - app.frame.minX, dy: fromY - app.frame.minY))
        let finish = origin.withOffset(CGVector(dx: viewport.midX - app.frame.minX, dy: toY - app.frame.minY))
        start.press(forDuration: 0.05, thenDragTo: finish)
    }

    private func resetToTop() {
        for _ in 0..<10 {
            if !app.navigationBars["Hızlı işlemleri düzenle"].exists,
               isVisibleAndHittable(app.buttons["home.task.lend"]) { return }
            shortDrag(up: false)
        }
    }

    private func isVisibleAndHittable(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let frame = element.frame
        guard !frame.isEmpty else { return false }
        let viewport = visibleScrollFrame()
        return frame.minY >= viewport.minY - 5 && frame.maxY <= viewport.maxY + 5
    }

    private func assertComesBefore(_ firstTitle: String, _ secondTitle: String) {
        resetToTop()
        let first = app.buttons["home.action.\(firstTitle)"]
        let second = app.buttons["home.action.\(secondTitle)"]
        guard reveal(first) else { return }
        // İlk iki kısayol aynı doğal satırda bulunur. İki frame de aynı scroll konumunda okunur.
        XCTAssertTrue(isVisibleAndHittable(second), "İlk iki seçili kısayol birlikte görünür olmalı")
        guard first.exists, second.exists, isVisibleAndHittable(second) else { return }
        let firstFrame = first.frame
        let secondFrame = second.frame
        if abs(firstFrame.minY - secondFrame.minY) < 2 {
            XCTAssertLessThan(firstFrame.minX, secondFrame.minX)
        } else {
            XCTAssertLessThan(firstFrame.minY, secondFrame.minY)
        }
    }
}
