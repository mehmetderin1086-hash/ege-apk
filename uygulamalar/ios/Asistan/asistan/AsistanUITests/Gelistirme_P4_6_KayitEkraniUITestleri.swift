import XCTest

/// P4.6 Toplantı kaydı: Üretkenlik → "Toplantı kaydı ve tutanak" açılır; rıza anahtarı açılmadan `kayit-baslat`
/// devre dışıdır, açılınca etkinleşir. Kayda başlanmaz (mikrofon izni ve ses oturumu sınanmaz).
@MainActor final class Gelistirme_P4_6_KayitEkraniUITestleri: XCTestCase {
    override func setUp() async throws { continueAfterFailure = false }

    func testRizaAcilmadanKayitBaslamaz() {
        let app = XCUIApplication.hermetik(); app.launch()
        app.aracAc("Üretkenlik")
        let giris = app.buttons["uretkenlik-toplanti-kaydi"]
        XCTAssertTrue(giris.waitForExistence(timeout: 5), "Toplantı kaydı düğmesi yok\n\(app.debugDescription)")
        giris.tap()

        let baslat = app.buttons["kayit-baslat"]
        XCTAssertTrue(baslat.waitForExistence(timeout: 5), "Kayda başla düğmesi görünmedi\n\(app.debugDescription)")
        XCTAssertFalse(baslat.isEnabled, "rıza açılmadan kayıt başlatılabiliyor")

        let riza = app.switches["kayit-riza"]
        XCTAssertTrue(riza.waitForExistence(timeout: 3), "rıza anahtarı yok")
        riza.tap()
        // SwiftUI Toggle'da öğenin ortasına dokunmak bazen anahtarı çevirmez: sağ uçtaki anahtara dokunulur.
        if !baslat.bekle("isEnabled == true", 2) {
            riza.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertTrue(baslat.bekle("isEnabled == true", 3), "rıza açılınca kayıt düğmesi etkinleşmedi")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "toplanti-kaydi-riza"; shot.lifetime = .keepAlways; add(shot)
    }
}
