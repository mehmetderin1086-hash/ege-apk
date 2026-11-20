import XCTest

/// P4.7: Ayarlar → Sürüş kipi sayfası açılır; "Arabaya bağlanınca sürüş kipi" anahtarı varsayılan AÇIK,
/// "Sürüş kipini şimdi aç" varsayılan KAPALI (hermetik kipte her açılış temiz ayar alanıyla başlar). Ayar değiştirilmez.
@MainActor final class Gelistirme_P4_7_SurusKipiUITestleri: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication.hermetik()
        app.launch()
    }

    func testSurusKipiAnahtariVarsayilanAcik() {
        app.ayarlariAc()
        XCTAssertTrue(app.navigationBars["Ayarlar"].waitForExistence(timeout: 5), "Ayarlar açılmadı")
        let satir = app.descendants(matching: .any)["ayarlar-surus-kipi"]
        var k = 0
        while !(satir.exists && satir.isHittable), k < 8 { app.swipeUp(); k += 1 }
        XCTAssertTrue(satir.exists, "Sürüş kipi satırı yok\n\(app.debugDescription)")
        satir.tap()
        XCTAssertTrue(app.navigationBars["Sürüş kipi"].waitForExistence(timeout: 4), "Sürüş kipi sayfası açılmadı")

        let otomatik = app.switches["surus-kipi-anahtari"]
        XCTAssertTrue(otomatik.waitForExistence(timeout: 3), "Otomatik sürüş kipi anahtarı yok")
        XCTAssertEqual(otomatik.value as? String, "1", "Otomatik sürüş kipi varsayılan açık olmalı")
        let elle = app.switches["surus-kipi-elle"]
        XCTAssertTrue(elle.exists, "Elle sürüş kipi anahtarı yok")
        XCTAssertEqual(elle.value as? String, "0", "Elle sürüş kipi varsayılan kapalı olmalı")
        // Simülatörde CarPlay yolu yok ve elle kapalı: "Şu an sürüş kipinde" satırı görünmez.
        XCTAssertFalse(app.descendants(matching: .any)["surus-kipi-durum"].exists, "Sürüş kipi kendiliğinden açık görünüyor")
    }
}
