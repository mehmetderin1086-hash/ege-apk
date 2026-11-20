import XCTest

/// P3.2: önizleme sohbetindeki eylem kartı (takvim, kimlik "onizleme"): Aç / Geri al görünür,
/// Geri al EventKit'e gitmeden "Geri alınamadı" yazar.
@MainActor final class EylemKartiUITestleri: XCTestCase {
    var app: XCUIApplication!
    override func setUp() async throws {
        await MainActor.run {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = ["--asistan-ui-onizleme", "--ek-kartlari"]
            app.launch()
        }
    }

    func testEylemKartiGeriAlOnizlemede() {
        XCTAssertTrue(app.descendants(matching: .any)["tablo-karti"].waitForExistence(timeout: 8), "önizleme kartları yüklendi")
        let kart = app.descendants(matching: .any)["eylem-karti"]
        // Eylem kartı ekler dizisinin en sonunda: görünene kadar kaydır.
        for _ in 0..<6 where !(kart.exists && kart.isHittable) { app.swipeUp() }
        XCTAssertTrue(kart.waitForExistence(timeout: 4), "eylem kartı")
        XCTAssertTrue(app.buttons["eylem-ac"].exists, "Aç düğmesi")
        XCTAssertTrue(app.buttons["eylem-duzenle"].exists, "tek kimlikli takvimde Düzenle")
        let geriAl = app.buttons["eylem-geri-al"]
        XCTAssertTrue(geriAl.exists, "Geri al düğmesi (süre içinde)")
        geriAl.tap()
        let durum = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Geri alınamadı")).firstMatch
        XCTAssertTrue(durum.waitForExistence(timeout: 5), "önizleme kimliği bulunamaz")
        XCTAssertFalse(app.buttons["eylem-geri-al"].exists, "sonuçtan sonra düğme kalkar")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "eylem-karti"; shot.lifetime = .keepAlways; add(shot)
    }
}
