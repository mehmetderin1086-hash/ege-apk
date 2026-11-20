import XCTest

/// P2.12: Ayarlar → Sana özel → İmzam ekranı açılır; tuval ve Kaydet / Temizle düğmeleri görünür.
/// Kayıtlı imzaya dokunulmaz (çizim yapılmaz, Kaydet'e basılmaz).
@MainActor final class Gelistirme_P2_12_ImzaUITestleri: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.hermetik()
        app.launch()
    }

    func testImzamEkraniAcilir() {
        app.ayarlariAc()
        XCTAssertTrue(app.navigationBars["Ayarlar"].waitForExistence(timeout: 5), "Ayarlar açılmadı")
        // P2.4: İmzam artık Ayarlar → Asistan → Sana özel'de.
        app.buttons["ayarlar-bolum-asistan"].tap()
        let satir = app.descendants(matching: .any)["ayar-imzam"]
        var k = 0
        while !(satir.exists && satir.isHittable), k < 8 { app.swipeUp(); k += 1 }
        XCTAssertTrue(satir.exists, "İmzam satırı yok\n\(app.debugDescription)")
        satir.tap()
        XCTAssertTrue(app.navigationBars["İmzam"].waitForExistence(timeout: 4), "İmzam ekranı açılmadı")
        XCTAssertTrue(app.buttons["imza-kaydet"].waitForExistence(timeout: 3), "Kaydet düğmesi yok")
        XCTAssertTrue(app.buttons["imza-temizle"].exists, "Temizle düğmesi yok")
        // Boş tuvalde Kaydet kapalı.
        XCTAssertFalse(app.buttons["imza-kaydet"].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["imza-tuval"].exists, "İmza tuvali yok")
    }
}
