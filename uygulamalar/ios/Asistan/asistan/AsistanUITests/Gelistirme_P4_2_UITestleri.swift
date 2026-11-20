import XCTest

/// P4.2: Ayarlar → Ses ve Live'da "Live arka planda sürsün" anahtarı görünür ve varsayılan kapalıdır. Hermetik (sahte model).
@MainActor final class Gelistirme_P4_2_UITestleri: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        await MainActor.run { continueAfterFailure = false }
        app = XCUIApplication.hermetik()
        app.launch()
        app.ayarlariAc()
        XCTAssertTrue(app.navigationBars["Ayarlar"].waitForExistence(timeout: 5), "Ayarlar açılmadı")
    }

    func testLiveArkaPlanAnahtariGorunurVeKapali() {
        XCTAssertTrue(app.ayarAramasindanAc("Live arka planda", terim: "arka plan"), "arama 'Live arka planda sürsün' sonucunu getirmedi")
        let anahtar = app.switches["ayar-live-arka-plan"]
        var k = 0
        while !(anahtar.exists && anahtar.isHittable), k < 6 { app.swipeUp(); k += 1 }
        XCTAssertTrue(anahtar.waitForExistence(timeout: 3), "Live arka planda sürsün anahtarı yok\n\(app.debugDescription)")
        XCTAssertEqual(anahtar.value as? String, "0", "varsayılan kapalı olmalı")
    }
}
