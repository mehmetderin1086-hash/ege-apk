import XCTest

/// P1.9: son yanıtın altındaki eylem satırı (kopyala, sesli oku, yeniden üret, paylaş) ve kısa bildirim (tost).
@MainActor final class YanitEylemUITestleri: XCTestCase {
    var app: XCUIApplication!
    override func setUp() async throws {
        await MainActor.run {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = ["--asistan-ui-onizleme", "--sohbet"]
            app.launch()
        }
    }

    private func yokOlmasiniBekle(_ oge: XCUIElement, sure: TimeInterval = 4) -> Bool {
        let bitti = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: oge)
        return XCTWaiter().wait(for: [bitti], timeout: sure) == .completed
    }

    func testKopyalaTostGosterir() {
        let kopyala = app.buttons["yanit-kopyala"]
        XCTAssertTrue(kopyala.waitForExistence(timeout: 5), "son yanıtın altında kopyala düğmesi")
        XCTAssertTrue(app.buttons["yanit-sesli-oku"].exists)
        XCTAssertTrue(app.buttons["yanit-paylas"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["yanit-eylemleri"].exists)
        // Model adı menüsü korunur (UI testleri yanıt bitti işareti olarak kullanır).
        XCTAssertTrue(app.buttons["yeniden-uret"].firstMatch.exists)
        kopyala.tap()
        let tost = app.descendants(matching: .any)["tost"]
        XCTAssertTrue(tost.waitForExistence(timeout: 3), "kopyalayınca tost çıkmalı")
        XCTAssertTrue(tost.label.contains("Kopyalandı"), "tost metni: \(tost.label)")
        XCTAssertTrue(yokOlmasiniBekle(tost, sure: 6), "tost kendiliğinden kapanmalı")
    }

    func testYenidenUretMenusuBaskaModelSunar() {
        let dugme = app.buttons["yanit-yeniden-uret"]
        XCTAssertTrue(dugme.waitForExistence(timeout: 5))
        dugme.tap()
        XCTAssertTrue(app.descendants(matching: .any)["Başka modelle"].firstMatch.waitForExistence(timeout: 3), "menüde 'Başka modelle' bölümü")
        XCTAssertTrue(app.buttons["gemini-3.8-flash"].firstMatch.exists, "başka model seçenekleri")
        // Menüyü seçim yapmadan kapat.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertTrue(app.buttons["yanit-kopyala"].waitForExistence(timeout: 3))
    }

    func testEylemSatiriTemadanKapatilir() {
        XCTAssertTrue(app.buttons["yanit-kopyala"].waitForExistence(timeout: 5))
        app.aracAc("Görünümü düzenle")
        XCTAssertTrue(app.navigationBars["Görünüm stüdyosu"].waitForExistence(timeout: 5))
        let anahtar = app.switches["tema-eylem-satiri"]
        for _ in 0..<10 where !(anahtar.exists && anahtar.isHittable) { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(anahtar.exists, "Mesaj biçimi bölümünde eylem satırı anahtarı")
        XCTAssertEqual(anahtar.value as? String, "1", "varsayılan açık")
        anahtar.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(anahtar.value as? String, "0")
        app.buttons["Tamam"].tap()
        XCTAssertTrue(app.buttons["menu-dugmesi"].waitForExistence(timeout: 3))
        XCTAssertTrue(yokOlmasiniBekle(app.buttons["yanit-kopyala"]), "eylem satırı kapanınca kopyala düğmesi yok")
        XCTAssertTrue(app.buttons["yeniden-uret"].firstMatch.exists, "model adı menüsü yerinde kalır")
        // Satırda Kaydet yok (kaydetme uzun basma menüsünde).
        XCTAssertFalse(app.buttons["yanit-kaydet"].exists)
    }
}
