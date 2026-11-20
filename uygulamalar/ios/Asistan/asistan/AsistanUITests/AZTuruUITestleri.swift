import XCTest

/// 28 Ekim A–Z turu: çekmeceden "Her yerde ara".
final class AZTuruUITestleri: XCTestCase {
    @MainActor func testHerYerdeAraCekmecedenAcilirVeSuzer() {
        let app = XCUIApplication.hermetik()
        app.launch()
        XCTAssertTrue(app.buttons["menu-dugmesi"].waitForExistence(timeout: 15))
        app.aracAc("Her yerde ara")
        let alan = app.searchFields.firstMatch
        XCTAssertTrue(alan.waitForExistence(timeout: 5), "arama alanı yok")
        let suzgec = app.buttons["arama-suzgec-hafiza"]
        XCTAssertTrue(suzgec.waitForExistence(timeout: 3))
        alan.tap(); alan.typeText("zzqxyy")
        XCTAssertTrue(app.staticTexts["“zzqxyy” için sonuç yok"].waitForExistence(timeout: 5)
                      || app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "zzqxyy")).firstMatch.waitForExistence(timeout: 2))
        app.buttons["Kapat"].firstMatch.tap()
        XCTAssertTrue(app.buttons["menu-dugmesi"].waitForExistence(timeout: 5))
    }

}


/// 29 Ekim: Telefon işlemleri → Sistem ayarları köprü kurulumu.
final class SistemKoprusuUITestleri: XCTestCase {
    @MainActor func testSistemAyarlariKurulumEkraniAcilir() throws {
        let app = XCUIApplication.hermetik()
        app.launch()
        XCTAssertTrue(app.buttons["menu-dugmesi"].waitForExistence(timeout: 15))
        app.open(try XCTUnwrap(URL(string: "asistan://telefon")))
        let giris = app.buttons["telefon-sistem-ayarlari"]
        XCTAssertTrue(giris.waitForExistence(timeout: 8), "Telefon işlemlerinde Sistem ayarları yok")
        giris.tap()
        XCTAssertTrue(app.descendants(matching: .any)["sistem-koprusu-durum"].waitForExistence(timeout: 5))
        let hazirla = app.buttons["sistem-koprusu-hazirla"]
        XCTAssertTrue(hazirla.waitForExistence(timeout: 3)); hazirla.tap()
        XCTAssertTrue(app.descendants(matching: .any)["sistem-koprusu-paylas"].waitForExistence(timeout: 5), "paket içinde imzalı köprü yok")
        XCTAssertTrue(app.buttons["sistem-koprusu-dene"].exists)
    }
}
