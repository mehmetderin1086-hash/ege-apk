import XCTest

/// P3.8: Ayarlar → Dikte sözlüğü (ekle → listede görünür → kaydırarak sil) ve Hafıza ekranındaki "Onay bekleyenler" bölümü.
@MainActor final class Gelistirme_P3_8_DikteSozluguUITestleri: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--sohbet"]
        app.launch()
    }

    /// P2.4: Dikte sözlüğü Ses ve Live'a, hafıza bağlantısı Hafıza alt sayfasına taşındı; aramadan doğrudan açılır.
    private func ayarlardaAc(_ baslik: String) -> Bool {
        app.ayarAramasindanAc(baslik, terim: baslik == "Dikte sözlüğü" ? "dikte sozlugu" : "taniyor")
    }

    func testDikteSozluguEkleVeSil() {
        app.ayarlariAc()
        XCTAssertTrue(app.navigationBars["Ayarlar"].waitForExistence(timeout: 5))
        XCTAssertTrue(ayarlardaAc("Dikte sözlüğü"), "Dikte sözlüğü satırı yok\n\(app.debugDescription)")
        XCTAssertTrue(app.navigationBars["Dikte sözlüğü"].waitForExistence(timeout: 4))

        let yanlis = "uitestmitos", dogru = "uitestmitoz"
        // Yalnız liste satırı ('dikte-kayit'): "Eklendi: … → …" bilgi metni de aynı etiketi içerir ve kaydırılabilir bir satır değildir.
        let satir = app.staticTexts.matching(identifier: "dikte-kayit")
            .matching(NSPredicate(format: "label CONTAINS %@", "\(yanlis) → \(dogru)")).firstMatch
        let liste = app.collectionViews["dikte-sozlugu"]
        func sil() -> Bool {
            guard satir.waitForExistence(timeout: 2) else { return false }
            // Ekle sonrası klavye açık kalır ve alttaki satırı örter: satır görünür olana dek klavyenin üstünde yukarı sürüklenir.
            var k = 0
            while !satir.isHittable, k < 4 {
                liste.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
                    .press(forDuration: 0.1, thenDragTo: liste.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
                k += 1
            }
            satir.swipeLeft()
            let dugme = app.buttons["Delete"].waitForExistence(timeout: 2) ? app.buttons["Delete"] : app.buttons["Sil"]
            guard dugme.waitForExistence(timeout: 3) else { return false }
            dugme.tap(); return true
        }
        // Önceki yarım kalmış çalıştırmadan kalan kayıt temizlenir.
        while satir.exists { XCTAssertTrue(sil(), "eski test kaydı silinemedi") }

        let alanY = app.textFields["dikte-yanlis"], alanD = app.textFields["dikte-dogru"]
        XCTAssertTrue(alanY.waitForExistence(timeout: 4))
        alanY.tap(); alanY.typeText(yanlis)
        alanD.tap(); alanD.typeText(dogru)
        app.buttons["dikte-ekle"].tap()
        XCTAssertTrue(satir.waitForExistence(timeout: 5), "düzeltme listede görünmedi\n\(app.debugDescription)")
        XCTAssertTrue(sil(), "düzeltme silinemedi")
        XCTAssertFalse(satir.waitForExistence(timeout: 2), "silinen düzeltme hâlâ listede")
    }

    func testHafizaEkraniOnayBekleyenlerBolumuTutarli() {
        app.ayarlariAc()
        XCTAssertTrue(app.navigationBars["Ayarlar"].waitForExistence(timeout: 5))
        XCTAssertTrue(ayarlardaAc("Asistan seni böyle tanıyor"), "Hafıza satırı yok")
        XCTAssertTrue(app.navigationBars["Hafıza"].waitForExistence(timeout: 4))
        // Bölüm yalnız bekleyen olgu varken görünür: boş depoda başlık yok, başlık varsa en az bir bekleyen satır var.
        let baslik = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Onay bekleyenler")).firstMatch
        let bekleyen = app.descendants(matching: .any).matching(identifier: "olgu-bekleyen-satiri").firstMatch
        XCTAssertEqual(baslik.waitForExistence(timeout: 2), bekleyen.exists, "Onay bekleyenler başlığı bekleyen olguyla tutarlı değil")
    }
}
