import XCTest

/// P1.8: önizleme sohbetindeki hava kartı (ağa gidilmez): kart yanıt balonunda görünür,
/// "Yağış" sekmesine dokununca saatlik yağış olasılığı (%) etiketleri çıkar.
@MainActor final class HavaKartiUITestleri: XCTestCase {
    var app: XCUIApplication!
    override func setUp() async throws {
        await MainActor.run {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = ["--asistan-ui-onizleme", "--ek-kartlari"]
            app.launch()
        }
    }

    func testHavaKartiYagisSekmesi() {
        XCTAssertTrue(app.descendants(matching: .any)["tablo-karti"].waitForExistence(timeout: 8), "önizleme kartları yüklendi")
        let kart = app.descendants(matching: .any)["hava-karti"]
        // Hava kartı ekler dizisinin en sonunda (eylem kartından da sonra): görünene kadar kaydır.
        for _ in 0..<8 where !(kart.exists && kart.isHittable) { app.swipeUp() }
        XCTAssertTrue(kart.waitForExistence(timeout: 4), "hava kartı")
        XCTAssertTrue(app.staticTexts["İstanbul"].exists, "şehir adı")
        XCTAssertTrue(app.staticTexts["18°"].exists, "yuvarlanmış sıcaklık")
        let yagis = app.buttons["Yağış"]
        XCTAssertTrue(yagis.waitForExistence(timeout: 3), "Yağış sekmesi")
        yagis.tap()
        let yuzde = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "%")).firstMatch
        XCTAssertTrue(yuzde.waitForExistence(timeout: 3), "yağış olasılığı etiketi")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "hava-karti"; shot.lifetime = .keepAlways; add(shot)
    }
}
