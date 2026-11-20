import XCTest

/// Canlı kataloğda yalnız okuma ve gezinme; hiçbir dolaşım kaydı oluşturulmaz. Uygulama
/// `-ui-testing-readonly` ile açılır: bütünlük onarımı, çöp temizliği, bildirim ve otomatik arşiv atlanır.
/// 'Cihaz Kabul' test planında koşar; beklenen sayılar isteğe bağlı olarak
/// `KITAPBUL_EXPECTED_BOOKS` / `KITAPBUL_EXPECTED_COPIES` ortam değişkenlerinden gelir.
final class PhysicalDeviceSmokeTests: XCTestCase {
    /// "2.579 kitap", "2,579" ya da "2579" biçimindeki ilk sayıyı döndürür.
    private func count(in label: String) -> Int? {
        guard let range = label.range(of: "[0-9][0-9.,]*", options: .regularExpression) else { return nil }
        return Int(label[range].filter(\.isNumber))
    }

    private func verifyCount(_ element: XCUIElement, expectedKey: String, noun: String) {
        let value = count(in: element.label)
        XCTAssertNotNil(value, "\(noun) sayısı okunamadı; görülen: \(element.label)")
        XCTAssertGreaterThan(value ?? 0, 0, "\(noun) sayısı sıfır; görülen: \(element.label)")
        if let raw = ProcessInfo.processInfo.environment[expectedKey], let expected = Int(raw) {
            XCTAssertEqual(value, expected, "Beklenen \(expected) \(noun); görülen: \(element.label)")
        }
    }

    func testLiveCatalogKeepsCountsAndOpensFiveTabs() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil, "Bu kabul fiziksel cihaz gerektirir.")
        let app = XCUIApplication(bundleIdentifier: "com.mehmetderin.kitapkatalogu")
        app.launchArguments = ["-ui-testing-readonly", "-onboardingShown", "YES", "-lastSeenWhatsNewVersion", "1.0"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Ana Sayfa"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Ana Sayfa"].tap()
        let books = app.buttons["home.titles"]
        // Gerçek cihazın büyük yazı tercihi özet kartlarını ilk ekranın altına
        // taşıyabilir; sayı doğrulanmadan önce gerçek kaydırmayla kartı bul.
        for _ in 0..<10 where !books.exists || !books.isHittable { app.swipeUp() }
        XCTAssertTrue(books.waitForExistence(timeout: 15))
        verifyCount(books, expectedKey: "KITAPBUL_EXPECTED_BOOKS", noun: "kitap")
        let copies = app.buttons["home.copies"]
        for _ in 0..<10 where !copies.exists || !copies.isHittable { app.swipeUp() }
        XCTAssertTrue(copies.waitForExistence(timeout: 15))
        verifyCount(copies, expectedKey: "KITAPBUL_EXPECTED_COPIES", noun: "nüsha")
        for tab in ["Ana Sayfa", "Kitaplar", "Ekle", "Ödünç", "Yönetim"] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.exists); button.tap()
            XCTAssertFalse(app.staticTexts["Katalog açılamadı"].exists)
            let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Ege-" + tab; image.lifetime = .keepAlways; add(image)
        }
    }
}
