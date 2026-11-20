import XCTest

/// Önizleme verisi olmadan gerçek akış: mesaj yaz → gönder → asistanın yanıtı ekrana gelir.
/// Gerçek Claude çağrısı yapar (ücretli, tek kısa istek): P3.10'dan beri yalnız `ASISTAN_CANLI=1` ile (Canlı test planı) koşar.
/// Hermetik eşi: SahteModelUITestleri.testSahteYanitGelir.
@MainActor final class GercekYanitUITesti: XCTestCase {
    func testMesajGonderYanitGelir() throws {
        try canliKapisi()
        let app = XCUIApplication()
        app.launchEnvironment = ["ASISTAN_TEST": "1"]
        app.launchArguments = ["--sohbet"]
        app.launch()
        let alan = app.descendants(matching: .any).matching(identifier: "mesaj-girisi").firstMatch
        XCTAssertTrue(alan.waitForExistence(timeout: 10), "mesaj alanı yok\n\(app.debugDescription)")
        alan.tap()
        alan.typeText("Yedi artı beş kaç eder? Sadece sayıyı yaz.")
        let gonder = app.buttons["Gönder"]
        XCTAssertTrue(gonder.waitForExistence(timeout: 3), "Gönder düğmesi yok")
        gonder.tap()
        let yanit = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "12")).firstMatch
        XCTAssertTrue(yanit.waitForExistence(timeout: 60), "60 sn içinde yanıt gelmedi\n\(app.debugDescription)")
        // Süre etiketi: "Düşünüyor · … çaba" yok, bitince cevabın altında "x,y sn" var.
        let sure = app.descendants(matching: .any).matching(identifier: "yanit-tamam").firstMatch
        XCTAssertTrue(sure.waitForExistence(timeout: 5), "cevap süresi görünmedi\n\(app.debugDescription)")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Düşünüyor")).firstMatch.exists)
        print("SURE ETIKETI: \(sure.label)")
    }

    func testArtArdaUcMesajBaglamiKorur() throws {
        try canliKapisi()
        let app = XCUIApplication()
        app.launchEnvironment = ["ASISTAN_TEST": "1"]
        app.launchArguments = ["--sohbet"]
        app.launch()
        let alan = app.descendants(matching: .any).matching(identifier: "mesaj-girisi").firstMatch
        XCTAssertTrue(alan.waitForExistence(timeout: 15))
        let sorular = ["Bu testte seçtiğim renk mercan. Yalnız mercan diyerek onayla.",
                       "Seçtiğim renk neydi? Yalnız rengin adını söyle.",
                       "Bir önceki rengimi tekrar söyle; tek kelime."]
        for (indeks, soru) in sorular.enumerated() {
            alan.tap(); alan.typeText(soru); app.buttons["Gönder"].tap()
            let tamam = app.descendants(matching: .any).matching(identifier: "yanit-tamam")
            XCTAssertTrue(kosulBekle(timeout: 90, aralik: 0.5) { tamam.count >= indeks + 1 }, "\(indeks + 1). yanıt tamamlanmadı")
            let son = tamam.element(boundBy: indeks)
            let metinler = [son.label] + son.descendants(matching: .staticText).allElementsBoundByIndex.map(\.label)
            XCTAssertTrue(metinler.contains { $0.localizedCaseInsensitiveContains("mercan") }, "Bu turun renk yanıtı yok")
            let resim = XCTAttachment(screenshot: app.screenshot())
            resim.name = "Ardışık yanıt \(indeks + 1)"; resim.lifetime = .keepAlways; add(resim)
        }
    }

    /// Tanı testi: gerçek web aramalı Claude çağrısı (ücretli). Yalnız ASISTAN_CANLI=1 ile koşar.
    func testIkiMesajAcikSoruTani() throws {
        try canliKapisi()
        let app = XCUIApplication()
        app.launchEnvironment = ["ASISTAN_TEST": "1"]
        app.launchArguments = ["--sohbet"]
        app.launch()
        let alan = app.descendants(matching: .any).matching(identifier: "mesaj-girisi").firstMatch
        XCTAssertTrue(alan.waitForExistence(timeout: 10))
        for soru in ["Fenerbahçe'nin önümüzdeki hafta maçı kiminle"] {
            alan.tap(); alan.typeText(soru)
            app.buttons["Gönder"].tap()
            let bas = Date()
            var son = ""
            kosulBekle(timeout: 90, aralik: 1) {
                let metinler = app.staticTexts.allElementsBoundByIndex.map(\.label)
                son = metinler.joined(separator: " | ")
                return metinler.contains(where: { $0.contains("Hata") || $0.contains("Slavia") || $0.contains("Ekim") })
            }
            print("TANI [\(soru)] \(Int(Date().timeIntervalSince(bas))) sn: \(son.prefix(1200))")
            // Yapısal doğrulama (içerik zamana bağlı olduğundan metne bakılmaz): yanıt tamamlanmalı, hata balonu çıkmamalı.
            let kalan = max(1, 90 - Date().timeIntervalSince(bas))
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "yanit-tamam").firstMatch.waitForExistence(timeout: kalan), "90 sn içinde yanıt tamamlanmadı: \(son.prefix(400))")
            for hata in ["Bağlantı yok ya da sunucuya ulaşılamadı.", "Hata:"] {
                XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", hata)).firstMatch.exists, "hata göründü: \(hata)")
            }
        }
    }

    func testModelEtiketleri() throws {
        try canliKapisi()
        let app = XCUIApplication()
        app.launchEnvironment = ["ASISTAN_TEST": "1"]
        app.launchArguments = ["--sohbet"]
        app.launch()
        let alan = app.descendants(matching: .any).matching(identifier: "mesaj-girisi").firstMatch
        XCTAssertTrue(alan.waitForExistence(timeout: 10))
        let etiket = NSPredicate(format: "label MATCHES %@", #"^\d+([,]\d)? sn · .*"#)
        var beklenen = 0
        for soru in ["Fotosentezi tek cümleyle açıkla.", "Beykoz'da hava durumu nedir?"] {
            alan.tap(); alan.typeText(soru)
            app.buttons["Gönder"].tap()
            beklenen += 1
            kosulBekle(timeout: 90, aralik: 0.5) { app.descendants(matching: .any).matching(identifier: "yanit-tamam").count >= beklenen }
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "yanit-tamam").count, beklenen, "etiket gelmedi: \(soru)")
        }
        print("ETIKETLER: \(app.descendants(matching: .any).matching(identifier: "yanit-tamam").allElementsBoundByIndex.map(\.label))")
    }
}
