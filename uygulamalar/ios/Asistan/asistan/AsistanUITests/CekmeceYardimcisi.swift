import XCTest

extension XCUIApplication {
    /// Sol çekmeceyi açar (zaten açıksa dokunmaz).
    func cekmeceAc() {
        if !buttons["cekmece-ayarlar"].exists { buttons["menu-dugmesi"].tap() }
        _ = buttons["cekmece-ayarlar"].waitForExistence(timeout: 3)
    }
    /// Çekmece → "Araçlar" menüsü → öğeye dokun.
    func aracAc(_ ad: String) {
        cekmeceAc()
        buttons["cekmece-araclar"].tap()
        let oge = buttons[ad].firstMatch
        XCTAssertTrue(oge.waitForExistence(timeout: 3), "\(ad) araçlar menüsünde yok")
        oge.tap()
    }
    func ayarlariAc() { cekmeceAc(); buttons["cekmece-ayarlar"].tap() }
    /// Çekmeceyi sağ taraftaki perdeye dokunarak kapatır.
    func cekmeceKapat() { coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap() }
}
