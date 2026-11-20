import XCTest

extension XCUIApplication {
    /// P2.4: Ayarlar'daki arama alanı ("Ayarlarda ara"). `.searchable` alanına kimlik verilemediği için istem metniyle bulunur.
    var ayarAramaAlani: XCUIElement { searchFields["Ayarlarda ara"] }

    /// Arama alanını temizleyip `terim` yazar. Alan görünmüyorsa (eski sürümlerde katlı durur) önce aşağı çeker.
    func ayarlardaAra(_ terim: String) {
        let alan = ayarAramaAlani
        if !(alan.exists && alan.isHittable) { swipeDown() }
        _ = alan.waitForExistence(timeout: 3)
        alan.tap()
        ayarAramasiniTemizle(kapat: false)
        alan.typeText(terim)
    }

    /// Alandaki metni temizleme düğmesiyle siler; `kapat` ise arama kipinden de çıkar (İptal/Cancel).
    func ayarAramasiniTemizle(kapat: Bool = true) {
        let alan = ayarAramaAlani
        guard alan.exists else { return }
        let temizle = alan.buttons.firstMatch
        if temizle.exists && temizle.isHittable { temizle.tap() }
        if kapat {
            for ad in ["Cancel", "İptal", "Vazgeç"] where buttons[ad].exists {
                buttons[ad].firstMatch.tap(); break
            }
        }
    }

    /// Ayarlarda `terim` ile arar ve etiketi `baslik` içeren sonuca dokunur; bulamazsa false.
    @discardableResult
    func ayarAramasindanAc(_ baslik: String, terim: String) -> Bool {
        ayarlardaAra(terim)
        let sonuc = buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "ayar-sonuc-", baslik)).firstMatch
        guard sonuc.waitForExistence(timeout: 4) else { return false }
        sonuc.tap()
        return true
    }
}

/// P2.4: sadeleşmiş Ayarlar: 6 başlık, katlı Gelişmiş, arama ve Kurulum durumu. Hermetik (sahte model, ağ yok).
@MainActor final class AyarlarUITestleri: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        await MainActor.run { continueAfterFailure = false }
        app = XCUIApplication.hermetik()
        app.launch()
        app.ayarlariAc()
        XCTAssertTrue(app.navigationBars["Ayarlar"].waitForExistence(timeout: 5), "Ayarlar açılmadı")
    }

    func testAltiBaslikVeKatliGelismis() {
        for b in ["asistan", "model", "sesLive", "gorunum", "hafiza", "baglanti"] {
            XCTAssertTrue(app.buttons["ayarlar-bolum-\(b)"].waitForExistence(timeout: 3), "başlık yok: \(b)")
        }
        for ad in ["Asistan", "Model", "Ses ve Live", "Görünüm", "Hafıza", "Bağlantı ve kota"] {
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", ad)).firstMatch.exists, "başlık metni yok: \(ad)")
        }
        let gelismis = app.buttons["ayarlar-gelismis"]
        var k = 0
        while !(gelismis.exists && gelismis.isHittable), k < 4 { app.swipeUp(); k += 1 }
        XCTAssertTrue(gelismis.exists, "Gelişmiş grubu yok")
        let mcp = app.buttons["ayarlar-mcp"]
        XCTAssertFalse(mcp.exists, "MCP sunucuları Gelişmiş açılmadan görünmemeli")
        gelismis.tap()
        // Liste tembel çizilir: Gelişmiş ekranın altındayken açılan satırlar ancak kaydırınca erişilebilirlik ağacına girer.
        let motor = app.buttons["ayarlar-indirme-motoru"]
        var j = 0
        while !mcp.exists, j < 4 { app.swipeUp(); j += 1 }
        XCTAssertTrue(mcp.waitForExistence(timeout: 3), "Gelişmiş açılınca MCP sunucuları görünmeli")
        j = 0
        while !motor.exists, j < 4 { app.swipeUp(); j += 1 }
        XCTAssertTrue(motor.waitForExistence(timeout: 3), "İndirme motoru satırı")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "ayarlar-gelismis"; shot.lifetime = .keepAlways; add(shot)
    }

    func testYtDlpAramasiIndirmeMotorunuGetirir() {
        app.ayarlardaAra("yt-dlp")
        let sonuc = app.buttons["ayar-sonuc-yt-dlp"]
        XCTAssertTrue(sonuc.waitForExistence(timeout: 4), "yt-dlp araması İndirme motoru satırını getirmedi\n\(app.debugDescription)")
        // Gelişmiş katlı olsa da aramadan doğrudan açılır.
        sonuc.tap()
        XCTAssertTrue(app.navigationBars["İndirme motoru"].waitForExistence(timeout: 4), "İndirme motoru ekranı açılmadı")
    }

    func testBulunmayanAramaBosDurumGosterir() {
        app.ayarlardaAra("zzqqxx")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ayar-sonuc-")).firstMatch.waitForExistence(timeout: 2),
                       "anlamsız aramada sonuç olmamalı")
        app.ayarAramasiniTemizle()
        XCTAssertTrue(app.buttons["ayarlar-bolum-asistan"].waitForExistence(timeout: 3), "arama temizlenince başlıklar dönmeli")
    }

    func testKurulumEkraniAcilir() {
        let satir = app.buttons["ayarlar-kurulum"]
        XCTAssertTrue(satir.waitForExistence(timeout: 4), "Kurulum durumu satırı yok")
        satir.tap()
        XCTAssertTrue(app.navigationBars["Kurulum durumu"].waitForExistence(timeout: 4), "Kurulum ekranı açılmadı")
        // Beş adım okununca her biri satır olarak görünür (durum değeri: tamam / eksik / bilinmiyor).
        let baglanti = app.descendants(matching: .any)["kurulum-adim-baglanti"]
        XCTAssertTrue(baglanti.waitForExistence(timeout: 8), "Bağlantı adımı görünmedi")
        for id in ["izinler", "ses", "kontrol", "siri"] {
            let adim = app.descendants(matching: .any)["kurulum-adim-\(id)"]
            var k = 0
            while !adim.exists, k < 3 { app.swipeUp(); k += 1 }
            XCTAssertTrue(adim.exists, "adım yok: \(id)")
        }
        let yenile = app.buttons["kurulum-yenile"]
        var k = 0
        while !yenile.exists, k < 3 { app.swipeUp(); k += 1 }
        XCTAssertTrue(yenile.exists, "Yeniden denetle düğmesi")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "kurulum-durumu"; shot.lifetime = .keepAlways; add(shot)
    }
}
