import XCTest

final class CalismaAlaniUITestleri: XCTestCase {
    @MainActor func testSohbettenDosyaKasasinaGecisVeGeriDonus() {
        let app = XCUIApplication.hermetik()
        app.launch()
        let ekle = app.buttons["Dosya veya fotoğraf ekle"]
        XCTAssertTrue(ekle.waitForExistence(timeout: 15)); ekle.tap()
        let kasa = app.buttons["Büyük dosya yükle · Dosya kasası"]
        XCTAssertTrue(kasa.waitForExistence(timeout: 5))
        if !kasa.isHittable { app.swipeUp() }
        kasa.tap()
        XCTAssertTrue(app.staticTexts["kasa-sinir"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["kasa-dosya-sec"].exists)
        app.navigationBars["Dosya kasası"].buttons["Tamam"].tap()
        XCTAssertTrue(ekle.waitForExistence(timeout: 5))
        XCTAssertTrue(ekle.isHittable)
    }

    @MainActor func testBuyukDosyaKasasiVeIslemeSinirlariGorunur() {
        let app = XCUIApplication.hermetik()
        app.launch()
        XCTAssertTrue(app.buttons["menu-dugmesi"].waitForExistence(timeout: 15))
        app.aracAc("Atölye")
        let alan = app.buttons["atolye-calisma"]
        XCTAssertTrue(alan.waitForExistence(timeout: 5)); alan.tap()
        let kasa = app.buttons["calisma-dosya-kasasi"]
        XCTAssertTrue(kasa.waitForExistence(timeout: 5)); kasa.tap()
        XCTAssertTrue(app.staticTexts["kasa-sinir"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["kasa-dosya-sec"].exists)
        XCTAssertTrue(app.staticTexts["Dosya başına 10 GB’a kadar"].exists)
    }

    @MainActor func testTuvalOlusturKaydetVeGecmis() throws {
        let app = XCUIApplication.hermetik()
        app.launch()
        XCTAssertTrue(app.buttons["menu-dugmesi"].waitForExistence(timeout: 15))
        app.aracAc("Atölye")
        let alan = app.buttons["atolye-calisma"]
        XCTAssertTrue(alan.waitForExistence(timeout: 5)); alan.tap()
        let tuval = app.buttons["calisma-tuval"]
        XCTAssertTrue(tuval.waitForExistence(timeout: 5)); tuval.tap()
        app.buttons["tuval-yeni"].tap()
        let ad = "Deneme \(UUID().uuidString.prefix(6))"
        let baslik = app.textFields["tuval-yeni-baslik"]
        XCTAssertTrue(baslik.waitForExistence(timeout: 5)); baslik.tap(); baslik.typeText(ad)
        app.buttons["tuval-olustur"].tap()
        let editor = app.textViews["tuval-metin"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        let ekran = XCTAttachment(screenshot: app.screenshot()); ekran.name = "Tuval düzenleyici odağı"; ekran.lifetime = .keepAlways; add(ekran)
        editor.typeText("İstanbul için ilk rapor.")
        app.buttons["tuval-kaydet"].tap()
        XCTAssertFalse(app.buttons["tuval-kaydet"].isEnabled)
        editor.tap(); editor.typeText(" İkinci sürüm.")
        app.buttons["tuval-kaydet"].tap()
        app.menudenSec("tuval-menu", secenek: "Sürüm geçmişi")
        XCTAssertTrue(app.navigationBars["Sürüm geçmişi"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["İlk sürüm"].exists)
    }
}
