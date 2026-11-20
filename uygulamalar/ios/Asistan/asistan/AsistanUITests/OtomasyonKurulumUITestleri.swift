import XCTest

final class OtomasyonKurulumUITestleri: XCTestCase {
    @MainActor func testEksikMailTaslaginiTemizle() throws {
        guard ProcessInfo.processInfo.environment["ASISTAN_OTOMASYON_KAYNAK"] == "temizle" else {
            throw XCTSkip("Yalnız fiziksel iPhone otomasyon temizliğinde çalışır.")
        }
        let kestirmeler = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        kestirmeler.activate()
        XCTAssertTrue(kestirmeler.wait(for: .runningForeground, timeout: 10))
        if kestirmeler.buttons["İşlemi Sil"].exists {
            kestirmeler.buttons["İşlemi Sil"].tap()
            sleep(1)
            if kestirmeler.buttons["BackButton"].exists { kestirmeler.buttons["BackButton"].tap() }
            XCTAssertTrue(kestirmeler.navigationBars["Otomasyon"].waitForExistence(timeout: 5))
            let kalan = kestirmeler.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Bu otomasyonu etkinleştirmek için")).firstMatch
            XCTAssertFalse(kalan.exists, "Eksik Mail otomasyonu temizlenemedi")
            return
        }
        let taslak = kestirmeler.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Bu otomasyonu etkinleştirmek için")).firstMatch
        guard taslak.waitForExistence(timeout: 5) else { return }
        taslak.swipeLeft()
        sleep(2)
        print("SHORTCUTS_AX_BEGIN\n\(kestirmeler.debugDescription)\nSHORTCUTS_AX_END")
        let belge = XCTAttachment(screenshot: kestirmeler.screenshot()); belge.name = "Kestirmeler-Mail-Taslak-Temizlik"; belge.lifetime = .keepAlways; add(belge)
    }

    @MainActor func testEksikBildirimOtomasyonlariniKur() throws {
        guard ProcessInfo.processInfo.environment["ASISTAN_OTOMASYON_KAYNAK"] == "tum" else {
            throw XCTSkip("Yalnız fiziksel iPhone otomasyon kurulumunda çalışır.")
        }
        let kestirmeler = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        kestirmeler.activate()
        XCTAssertTrue(kestirmeler.wait(for: .runningForeground, timeout: 10))
        anaOtomasyonListesineDon(kestirmeler)

        kurBildirimOtomasyonu(kestirmeler, uygulama: "Mail", eylem: "Mail iletisini kaydet")
        kurBildirimOtomasyonu(kestirmeler, uygulama: "Mesajlar", eylem: "Mesajlar iletisini kaydet")

        let whatsapp = kestirmeler.switches.matching(NSPredicate(format: "label CONTAINS %@", "WhatsApp bildirimi aldığımda")).firstMatch
        let mail = kestirmeler.switches.matching(NSPredicate(format: "label CONTAINS %@", "Mail bildirimi aldığımda")).firstMatch
        let mesajlar = kestirmeler.switches.matching(NSPredicate(format: "label CONTAINS %@", "Mesajlar bildirimi aldığımda")).firstMatch
        XCTAssertTrue(whatsapp.exists, "WhatsApp otomasyonu listede bulunamadı")
        XCTAssertTrue(mail.exists, "Mail otomasyonu listede bulunamadı")
        XCTAssertTrue(mesajlar.exists, "Mesajlar otomasyonu listede bulunamadı")
        XCTAssertEqual(whatsapp.value as? String, "1")
        XCTAssertEqual(mail.value as? String, "1")
        XCTAssertEqual(mesajlar.value as? String, "1")
        print("SHORTCUTS_FINAL_AX_BEGIN\n\(kestirmeler.debugDescription)\nSHORTCUTS_FINAL_AX_END")
        let belge = XCTAttachment(screenshot: kestirmeler.screenshot()); belge.name = "Mehmet-Asistan-Uc-Otomasyon"; belge.lifetime = .keepAlways; add(belge)
    }

    @MainActor private func anaOtomasyonListesineDon(_ uygulama: XCUIApplication) {
        if uygulama.navigationBars["WFRecipientFieldView"].exists {
            uygulama.buttons["Vazgeç"].tap()
            sleep(1)
        }
        if uygulama.buttons["Vazgeç"].exists, !uygulama.navigationBars["Otomasyon"].exists {
            uygulama.buttons["Vazgeç"].tap()
            sleep(1)
        }
        if !uygulama.navigationBars["Otomasyon"].exists, uygulama.buttons["BackButton"].exists {
            uygulama.buttons["BackButton"].tap()
            sleep(2)
        }
        XCTAssertTrue(uygulama.navigationBars["Otomasyon"].waitForExistence(timeout: 5), "Otomasyon listesine dönülemedi")
    }

    @MainActor private func kurBildirimOtomasyonu(_ uygulama: XCUIApplication, uygulama adi: String, eylem: String) {
        let varOlan = uygulama.switches.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "\(adi) bildirimi aldığımda", eylem)).firstMatch
        if varOlan.exists { return }

        let ekle = uygulama.buttons["main.button.newshortcut"]
        XCTAssertTrue(ekle.waitForExistence(timeout: 5)); ekle.tap()
        XCTAssertTrue(uygulama.searchFields["Arayın"].waitForExistence(timeout: 5))
        XCTAssertTrue(uygulama.buttons["Otomasyon"].waitForExistence(timeout: 5)); uygulama.buttons["Otomasyon"].tap()
        XCTAssertTrue(uygulama.cells["Bildirim"].waitForExistence(timeout: 5)); uygulama.cells["Bildirim"].tap()

        XCTAssertTrue(uygulama.buttons["enum"].waitForExistence(timeout: 5)); uygulama.buttons["enum"].tap()
        XCTAssertTrue(uygulama.navigationBars["Uygulama"].waitForExistence(timeout: 5))
        let uygulamaAramasi = uygulama.searchFields.element(boundBy: max(0, uygulama.searchFields.count - 1))
        uygulamaAramasi.tap(); uygulamaAramasi.typeText(adi)
        let uygulamaSonucu = uygulama.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", adi)).firstMatch
        XCTAssertTrue(uygulamaSonucu.waitForExistence(timeout: 5)); uygulamaSonucu.tap()

        let eylemAramasi = uygulama.searchFields["Arayın"]
        XCTAssertTrue(eylemAramasi.waitForExistence(timeout: 5)); eylemAramasi.tap(); eylemAramasi.typeText(eylem)
        XCTAssertTrue(uygulama.cells[eylem].waitForExistence(timeout: 5)); uygulama.cells[eylem].tap()

        let metin = uygulama.buttons["textInput"]
        XCTAssertTrue(metin.waitForExistence(timeout: 5)); metin.tap()
        XCTAssertTrue(uygulama.buttons["Bildirim"].waitForExistence(timeout: 5)); uygulama.buttons["Bildirim"].tap()
        XCTAssertTrue(uygulama.buttons["xmark"].waitForExistence(timeout: 5)); uygulama.buttons["xmark"].tap()
        XCTAssertTrue(uygulama.buttons["BackButton"].waitForExistence(timeout: 5)); uygulama.buttons["BackButton"].tap()
        XCTAssertTrue(uygulama.navigationBars["Otomasyon"].waitForExistence(timeout: 8))

        let kayit = uygulama.switches.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "\(adi) bildirimi aldığımda", eylem)).firstMatch
        XCTAssertTrue(kayit.waitForExistence(timeout: 5), "\(adi) otomasyonu kaydedilemedi")
        XCTAssertEqual(kayit.value as? String, "1", "\(adi) otomasyonu etkin değil")
    }

    @MainActor func testMailOtomasyonunuKesfet() throws {
        guard ProcessInfo.processInfo.environment["ASISTAN_OTOMASYON_KAYNAK"] == "mail" else {
            throw XCTSkip("Yalnız Mail otomasyonu kurulumunda çalışır.")
        }
        let kestirmeler = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        kestirmeler.activate()
        XCTAssertTrue(kestirmeler.wait(for: .runningForeground, timeout: 10))
        sleep(2)
        if kestirmeler.buttons["contact"].exists {
            kestirmeler.buttons["contact"].tap()
            sleep(2)
            print("SHORTCUTS_AX_BEGIN\n\(kestirmeler.debugDescription)\nSHORTCUTS_AX_END")
            let belge = XCTAttachment(screenshot: kestirmeler.screenshot()); belge.name = "Kestirmeler-Mail-Gonderen"; belge.lifetime = .keepAlways; add(belge)
            return
        }
        let ek = kestirmeler.buttons["main.button.newshortcut"]
        XCTAssertTrue(ek.waitForExistence(timeout: 5))
        ek.tap()
        XCTAssertTrue(kestirmeler.searchFields["Arayın"].waitForExistence(timeout: 5))
        kestirmeler.buttons["Otomasyon"].tap()
        XCTAssertTrue(kestirmeler.cells["E-posta"].waitForExistence(timeout: 5))
        kestirmeler.cells["E-posta"].tap()
        sleep(2)
        print("SHORTCUTS_AX_BEGIN\n\(kestirmeler.debugDescription)\nSHORTCUTS_AX_END")
        let belge = XCTAttachment(screenshot: kestirmeler.screenshot()); belge.name = "Kestirmeler-Mail-Tetikleyici"; belge.lifetime = .keepAlways; add(belge)
    }

    @MainActor func testKestirmelerArayuzunuKesfet() throws {
        guard ProcessInfo.processInfo.environment["ASISTAN_OTOMASYON_KUR"] == "1" else {
            throw XCTSkip("Yalnız fiziksel iPhone otomasyon kurulumunda çalışır.")
        }
        let kestirmeler = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        kestirmeler.activate()
        XCTAssertTrue(kestirmeler.wait(for: .runningForeground, timeout: 10))
        sleep(2)
        if kestirmeler.otherElements["inputView"].exists,
           ((kestirmeler.textViews.firstMatch.value as? String)?.isEmpty == false) {
            kestirmeler.buttons["xmark"].tap()
            sleep(2)
            print("SHORTCUTS_AX_BEGIN\n\(kestirmeler.debugDescription)\nSHORTCUTS_AX_END")
            let belge = XCTAttachment(screenshot: kestirmeler.screenshot()); belge.name = "Kestirmeler-WhatsApp-Hazir"; belge.lifetime = .keepAlways; add(belge)
            return
        }
        if kestirmeler.buttons["textInput"].exists,
           ((kestirmeler.buttons["textInput"].value as? String)?.isEmpty == false),
           !kestirmeler.otherElements["inputView"].exists {
            kestirmeler.buttons["BackButton"].tap()
            sleep(3)
            print("SHORTCUTS_AX_BEGIN\n\(kestirmeler.debugDescription)\nSHORTCUTS_AX_END")
            let belge = XCTAttachment(screenshot: kestirmeler.screenshot()); belge.name = "Kestirmeler-WhatsApp-Kayit"; belge.lifetime = .keepAlways; add(belge)
            return
        }
        if kestirmeler.otherElements["inputView"].exists,
           kestirmeler.buttons["Bildirim"].exists {
            kestirmeler.buttons["Bildirim"].tap()
            sleep(2)
            print("SHORTCUTS_AX_BEGIN\n\(kestirmeler.debugDescription)\nSHORTCUTS_AX_END")
            let belge = XCTAttachment(screenshot: kestirmeler.screenshot()); belge.name = "Kestirmeler-Bildirim-Degiskeni"; belge.lifetime = .keepAlways; add(belge)
            return
        }
        if kestirmeler.buttons["textInput"].exists,
           ((kestirmeler.buttons["enum"].value as? String)?.contains("WhatsApp") == true) {
            kestirmeler.buttons["textInput"].tap()
            sleep(2)
            print("SHORTCUTS_AX_BEGIN\n\(kestirmeler.debugDescription)\nSHORTCUTS_AX_END")
            let belge = XCTAttachment(screenshot: kestirmeler.screenshot()); belge.name = "Kestirmeler-Degisken-Secimi"; belge.lifetime = .keepAlways; add(belge)
            return
        }
        if kestirmeler.cells["WhatsApp bildirimini kaydet"].exists,
           ((kestirmeler.searchFields["Arayın"].value as? String)?.contains("WhatsApp bildirimi") == true) {
            kestirmeler.cells["WhatsApp bildirimini kaydet"].tap()
            sleep(2)
            print("SHORTCUTS_AX_BEGIN\n\(kestirmeler.debugDescription)\nSHORTCUTS_AX_END")
            let belge = XCTAttachment(screenshot: kestirmeler.screenshot()); belge.name = "Kestirmeler-WhatsApp-Eylem-Eklendi"; belge.lifetime = .keepAlways; add(belge)
            return
        }
        if kestirmeler.navigationBars["Uygulama"].exists {
            let whatsapp = kestirmeler.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "WhatsApp")).firstMatch
            if whatsapp.exists {
                whatsapp.tap()
                sleep(2)
                print("SHORTCUTS_AX_BEGIN\n\(kestirmeler.debugDescription)\nSHORTCUTS_AX_END")
                let belge = XCTAttachment(screenshot: kestirmeler.screenshot()); belge.name = "Kestirmeler-WhatsApp-Secildi"; belge.lifetime = .keepAlways; add(belge)
                return
            }
            let alanlar = kestirmeler.searchFields
            let ara = alanlar.element(boundBy: max(0, alanlar.count - 1))
            ara.tap()
            ara.typeText("WhatsApp")
            sleep(2)
            print("SHORTCUTS_AX_BEGIN\n\(kestirmeler.debugDescription)\nSHORTCUTS_AX_END")
            let belge = XCTAttachment(screenshot: kestirmeler.screenshot()); belge.name = "Kestirmeler-WhatsApp-Arama"; belge.lifetime = .keepAlways; add(belge)
            return
        }
        if let deger = kestirmeler.buttons["enum"].value as? String,
           deger.contains("WhatsApp") {
            let ara = kestirmeler.searchFields["Arayın"]
            ara.tap()
            ara.typeText("WhatsApp bildirimini kaydet")
            sleep(2)
            print("SHORTCUTS_AX_BEGIN\n\(kestirmeler.debugDescription)\nSHORTCUTS_AX_END")
            let belge = XCTAttachment(screenshot: kestirmeler.screenshot()); belge.name = "Kestirmeler-WhatsApp-Eylem-Arama"; belge.lifetime = .keepAlways; add(belge)
            return
        }
        if kestirmeler.buttons["enum"].exists {
            kestirmeler.buttons["enum"].tap()
            sleep(2)
            print("SHORTCUTS_AX_BEGIN\n\(kestirmeler.debugDescription)\nSHORTCUTS_AX_END")
            let belge = XCTAttachment(screenshot: kestirmeler.screenshot()); belge.name = "Kestirmeler-Uygulama-Secimi"; belge.lifetime = .keepAlways; add(belge)
            return
        }
        if kestirmeler.buttons["Vazgeç"].exists, kestirmeler.cells["Bildirim"].exists {
            kestirmeler.cells["Bildirim"].tap()
            sleep(2)
            print("SHORTCUTS_AX_BEGIN\n\(kestirmeler.debugDescription)\nSHORTCUTS_AX_END")
            let belge = XCTAttachment(screenshot: kestirmeler.screenshot()); belge.name = "Kestirmeler-Otomasyon"; belge.lifetime = .keepAlways; add(belge)
            return
        }
        if kestirmeler.buttons["textInput"].exists {
            kestirmeler.buttons["BackButton"].tap()
            sleep(2)
        }
        let ek = kestirmeler.buttons["main.button.newshortcut"]
        if ek.waitForExistence(timeout: 2) { ek.tap() }
        let ara = kestirmeler.searchFields["Arayın"]
        XCTAssertTrue(ara.waitForExistence(timeout: 5))
        let otomasyon = kestirmeler.buttons["Otomasyon"]
        XCTAssertTrue(otomasyon.waitForExistence(timeout: 5))
        otomasyon.tap()
        sleep(2)
        print("SHORTCUTS_AX_BEGIN\n\(kestirmeler.debugDescription)\nSHORTCUTS_AX_END")
        let belge = XCTAttachment(screenshot: kestirmeler.screenshot()); belge.name = "Kestirmeler-Otomasyon"; belge.lifetime = .keepAlways; add(belge)
    }
}
