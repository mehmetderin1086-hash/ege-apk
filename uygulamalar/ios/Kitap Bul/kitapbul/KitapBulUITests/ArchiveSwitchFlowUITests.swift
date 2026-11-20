import XCTest

/// Normal Yönetim araçları, doğrulanmış ZIP önizlemesi ve root @Query/modelContext
/// değişimini birlikte sınar. Uygulama içindeki servisler doğrudan çağrılmaz.
final class ArchiveSwitchFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.mehmetderin.kitapkatalogu")
        app.launchArguments = ["-ui-testing", "-ui-testing-reset-navigation", "-onboardingShown", "YES", "-lastSeenWhatsNewVersion", "1.0", "-roleLockEnabled", "NO", "-visualEffectsEnabled", "NO", "-edgeSwipeTabs", "NO", "-appearanceMode", "light"]
        app.launch()
    }

    override func tearDownWithError() throws { app?.terminate() }

    func testYonetimdenAyriKatalogVeOncekiUcEserGeriDoner() {
        app.terminate()
        app.launchArguments += ["-ui-testing-archive-switch"]
        app.launch()

        tab("Kitaplar")
        assertOriginalBooks()
        XCTAssertFalse(book("Arşiv Deneme Eseri").exists)
        capture("Arsiv-Gecisi-Oncesi-Uc-Eser")

        openBackupHistory()
        XCTAssertTrue(app.staticTexts["1 eser · 0 nüsha · 0 açık ödünç"].waitForExistence(timeout: 15))
        openFirstPreviewAndConfirm()
        closeReceipt()

        // Yeni root konteyneri gerçek kitap sorgusunu değiştirmiş olmalı.
        tab("Kitaplar")
        XCTAssertTrue(book("Arşiv Deneme Eseri").waitForExistence(timeout: 10))
        for title in ["Deneme Kitabı", "Geciken Kitap", "Bugün İade"] {
            XCTAssertFalse(book(title).exists, "Eski @Query/konteyner görünümü kaldı: \(title)")
        }
        capture("Arsiv-Gecisi-Yeni-Tek-Eser")

        openBackupHistory()
        // Bu satır seed dosyasında yoktur; birinci gerçek geçişin sakladığı tam
        // üç eser/two loan ZIP'i yeniden listelenmiş ve doğrulanmış olmalı.
        XCTAssertTrue(app.staticTexts["3 eser · 0 nüsha · 2 açık ödünç"].waitForExistence(timeout: 15))
        openFirstPreviewAndConfirm()
        closeReceipt()
        tab("Kitaplar")
        assertOriginalBooks()
        XCTAssertFalse(book("Arşiv Deneme Eseri").exists, "Önceki kataloğa dönüşte yeni depo sorgusu kaldı")
        capture("Arsiv-Gecisi-Onceki-Katalog-Geri-Geldi")
    }

    private func tab(_ name: String) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 8), "Sekme bulunamadı: \(name)")
        button.tap()
    }

    private func book(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
    }

    private func assertOriginalBooks() {
        for title in ["Deneme Kitabı", "Geciken Kitap", "Bugün İade"] {
            XCTAssertTrue(book(title).waitForExistence(timeout: 10), "Özgün eser bulunamadı: \(title)")
        }
    }

    private func openBackupHistory() {
        tab("Yönetim")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        // UIKit arama görünümü sekmeler arasında sorguyu koruyabilir.
        // Her geçişte aynı gerçek Yönetim aramasını yeniden uygula.
        if let existing = search.value as? String, !existing.isEmpty, existing != "Ara" {
            for _ in existing { search.typeText(XCUIKeyboardKey.delete.rawValue) }
        }
        for character in "yedekleri" { search.typeText(String(character)) }
        let backups = app.buttons["management.archiveSwitchBackups"]
        XCTAssertTrue(backups.waitForExistence(timeout: 5))
        reveal(backups)
        backups.tap()
        XCTAssertTrue(app.navigationBars["Katalog geçişi yedekleri"].waitForExistence(timeout: 10))
    }

    private func openFirstPreviewAndConfirm() {
        let preview = app.buttons.matching(identifier: "archive.switch.backup.preview").firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 15))
        reveal(preview)
        preview.tap()
        XCTAssertTrue(app.navigationBars["Ayrı katalog önizlemesi"].waitForExistence(timeout: 10))
        let apply = app.buttons["archive.switch.apply"]
        reveal(apply)
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        let confirm = app.buttons["Doğrulanmış yedekten sonra aç"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
    }

    private func closeReceipt() {
        let summary = app.staticTexts["archive.switch.receipt.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 30), "Doğrulanmış yeni root katalog sonucu gösterilmedi")
        let close = app.buttons["archive.switch.receipt.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        let missing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !close.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [missing], timeout: 10), .completed)
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Kontrol kaydırmayla erişilemedi: \(element.identifier)")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
