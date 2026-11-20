import XCTest

/// P1.10: önizleme sohbetindeki izin kartı ve Ayarlar > İzinler ekranı. İzin düğmesine dokunulmaz (sistem sorusu açılmasın).
@MainActor final class IzinUITestleri: XCTestCase {
    var app: XCUIApplication!
    override func setUp() async throws {
        await MainActor.run { continueAfterFailure = false }
    }

    private func baslat(_ argumanlar: [String]) {
        app = XCUIApplication()
        app.launchArguments = argumanlar
        app.launch()
    }

    func testIzinKartiOnizlemede() {
        baslat(["--asistan-ui-onizleme", "--ek-kartlari"])
        XCTAssertTrue(app.descendants(matching: .any)["tablo-karti"].waitForExistence(timeout: 8), "önizleme kartları yüklendi")
        let kart = app.descendants(matching: .any)["izin-karti"]
        // İzin kartı ekler dizisinin en sonunda (hava kartından da sonra): görünene kadar kaydır.
        for _ in 0..<10 where !(kart.exists && kart.isHittable) { app.swipeUp() }
        XCTAssertTrue(kart.waitForExistence(timeout: 4), "izin kartı")
        let dugme = app.descendants(matching: .any)["izin-dugmesi"]
        let verildi = app.staticTexts["İzin verildi; isteğini yeniden söyleyebilirsin."]
        // Simülatörde takvim izni çoğunlukla sorulmamıştır ("İzin ver"); daha önce verildiyse düğme yerine bilgi satırı çıkar.
        XCTAssertTrue(kosulBekle(timeout: 4) { dugme.exists || verildi.exists }, "izin düğmesi ya da verildi notu")
        if dugme.exists {
            XCTAssertTrue(["İzin ver", "Ayarlar'ı aç"].contains(dugme.label), "düğme metni: \(dugme.label)")
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "izin-karti"; shot.lifetime = .keepAlways; add(shot)
    }

    func testAyarlarIzinlerEkrani() {
        baslat(["--asistan-ui-onizleme", "--sohbet"])
        app.ayarlariAc()
        // P2.4: İzinler satırı Ayarlar → Asistan alt sayfasında.
        let asistan = app.buttons["ayarlar-bolum-asistan"]
        XCTAssertTrue(asistan.waitForExistence(timeout: 5), "Ayarlar > Asistan başlığı")
        asistan.tap()
        let satir = app.descendants(matching: .any)["ayarlar-izinler"]
        XCTAssertTrue(satir.waitForExistence(timeout: 5), "Ayarlar > İzinler satırı")
        satir.tap()
        XCTAssertTrue(app.navigationBars["İzinler"].waitForExistence(timeout: 5), "İzinler ekranı")
        XCTAssertTrue(app.staticTexts["Mikrofon"].waitForExistence(timeout: 4), "Mikrofon satırı")
        XCTAssertTrue(app.staticTexts["Takvim"].exists, "Takvim satırı")
        // Durumlar okununca her satırda bir durum etiketi olur (Açık/Kapalı/Sorulmadı/Sınırlı).
        let durumEtiketi = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["Açık", "Kapalı", "Sorulmadı", "Sınırlı"])).firstMatch
        XCTAssertTrue(durumEtiketi.waitForExistence(timeout: 5), "izin durumu okundu")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "izinler-ekrani"; shot.lifetime = .keepAlways; add(shot)
    }
}
