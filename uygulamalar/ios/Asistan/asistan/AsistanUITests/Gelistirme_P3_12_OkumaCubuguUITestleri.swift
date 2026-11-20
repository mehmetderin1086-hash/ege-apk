import XCTest

/// P3.12: okuma çubuğu giriş çubuğunun üstünde görünür ve düğmeleri dokunulabilir. Simülatörde ses gerçekten
/// çalmadığından çubuk `--okuma-cubugu-sinama` (yalnız Debug) ile zorlanır; hermetik (sahte model, ağsız).
@MainActor final class Gelistirme_P3_12_OkumaCubuguUITestleri: XCTestCase {
    func testOkumaCubuguGorunurVeDuraklatDokunulabilir() {
        continueAfterFailure = false
        let app = XCUIApplication.hermetik(ek: ["--okuma-cubugu-sinama"])
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["okuma-cubugu"].waitForExistence(timeout: 10))
        let duraklat = app.buttons["okuma-duraklat"]
        XCTAssertTrue(duraklat.bekle("isHittable", 5))
        duraklat.tap()
        XCTAssertTrue(app.buttons["okuma-durdur"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["okuma-hiz"].exists)
        // Giriş çubuğu yerinde kalır.
        XCTAssertTrue(app.descendants(matching: .any)["mesaj-girisi"].exists)
    }
}
