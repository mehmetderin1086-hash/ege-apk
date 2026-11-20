import XCTest

/// P2.3: giriş çubuğunun üstündeki tek durum şeridi (`--durum-ornek`: kota türünde örnek model hatası).
@MainActor final class Gelistirme_P2_3_DurumSeridiUITestleri: XCTestCase {
    var app: XCUIApplication!
    override func setUp() async throws {
        await MainActor.run {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = ["--asistan-ui-onizleme", "--sohbet", "--durum-ornek"]
            app.launch()
        }
    }

    func testTekSeritGorunurVeKapatilir() {
        let seritler = app.descendants(matching: .any).matching(identifier: "durum-seridi")
        let serit = seritler.firstMatch
        XCTAssertTrue(serit.waitForExistence(timeout: 8), "durum şeridi görünmeli\n\(app.debugDescription)")
        XCTAssertEqual(seritler.count, 1, "tek durum şeridi olmalı")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "429")).firstMatch.exists, "kota metni")
        XCTAssertTrue(app.descendants(matching: .any)["durum-eylem-yenidenDene"].exists, "Yeniden dene düğmesi")
        XCTAssertTrue(app.descendants(matching: .any)["durum-eylem-baskaModel"].exists, "Başka model menüsü")
        let kapat = app.buttons["durum-kapat"]
        XCTAssertTrue(kapat.exists, "kapat düğmesi")
        kapat.tap()
        XCTAssertTrue(serit.bekle("!exists", 4), "kapatınca şerit kaybolmalı")
    }

    func testBaskaModelMenusuModelleriSunar() {
        let menu = app.descendants(matching: .any)["durum-eylem-baskaModel"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 8))
        menu.tap()
        XCTAssertTrue(app.buttons["gemini-3.8-flash"].firstMatch.waitForExistence(timeout: 3), "menüde model seçenekleri")
    }
}
