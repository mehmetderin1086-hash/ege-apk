import XCTest

/// P3.10 Duman çekirdeği: gerçek modele ve ağa çıkmadan (`--sahte-model`) mesaj → yanıt akışı.
/// Yanıtlar uygulama içindeki sahte model sunucusunun senaryosundan gelir (SahteSenaryo.yerlesik).
@MainActor final class SahteModelUITestleri: XCTestCase {
    override func setUp() async throws { continueAfterFailure = false }

    private func giris(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "mesaj-girisi").firstMatch
    }

    private func gonder(_ app: XCUIApplication, _ metin: String) {
        let alan = giris(app)
        XCTAssertTrue(alan.waitForExistence(timeout: 10), "mesaj alanı yok\n\(app.debugDescription)")
        alan.tap(); alan.typeText(metin)
        let g = app.buttons["Gönder"]
        XCTAssertTrue(g.bekle("isHittable", 5), "Gönder düğmesi yok")
        g.tap()
    }

    private func hataYok(_ app: XCUIApplication, dosya: StaticString = #filePath, satir: UInt = #line) {
        for hata in ["Bağlantı yok ya da sunucuya ulaşılamadı.", "Hata:"] {
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", hata)).firstMatch.exists,
                           "hata göründü: \(hata)", file: dosya, line: satir)
        }
    }

    func testSahteYanitGelir() {
        let app = XCUIApplication.hermetik(); app.launch()
        gonder(app, "Yedi artı beş kaç eder? Sadece sayıyı yaz.")
        let yanit = app.staticTexts.matching(NSPredicate(format: "label == %@", "12")).firstMatch
        XCTAssertTrue(yanit.waitForExistence(timeout: 10), "sahte yanıt 10 sn içinde gelmedi\n\(app.debugDescription)")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "yanit-tamam").firstMatch.waitForExistence(timeout: 10), "yanıt tamamlanmadı")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Düşünüyor")).firstMatch.exists, "'Düşünüyor' kaldı")
        hataYok(app)
    }

    /// Yarıştaki ilk aday modeller 429 döner (hem Antigravity önceliği hem doğrudan liste); yanıt yine gelir.
    func testSahteKotaHatasindaYedekModel() {
        let senaryo = #"{"kurallar":[{"icerir":"yedi artı beş","model":"antigravity-gemini-3-flash","durum":429},{"icerir":"yedi artı beş","model":"claude-haiku-4-5","durum":429}]}"#
        let app = XCUIApplication.hermetik(senaryo: senaryo); app.launch()
        gonder(app, "Yedi artı beş kaç eder? Sadece sayıyı yaz.")
        let yanit = app.staticTexts.matching(NSPredicate(format: "label == %@", "12")).firstMatch
        XCTAssertTrue(yanit.waitForExistence(timeout: 15), "429 sonrası yedek modelden yanıt gelmedi\n\(app.debugDescription)")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "yanit-tamam").firstMatch.waitForExistence(timeout: 10), "yanıt tamamlanmadı")
        hataYok(app)
    }

    /// Kisisellestirme.testMesajlarArasiBaglamSurer'in hermetik kopyası: sahte sunucu yalnız önceki mesajlarda
    /// "Pamuk" geçiyorsa "Bağlamdan: …" yanıtı verir; yani bağlam gerçekten istekle gidiyor mu sınanır.
    func testSahteBaglamSurer() {
        let app = XCUIApplication.hermetik(); app.launch()
        gonder(app, "Benim kedimin adı Pamuk ve 3 yaşında.")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "yanit-tamam").firstMatch.waitForExistence(timeout: 10), "ilk yanıt")
        gonder(app, "Peki kaç yaşındaydı?")
        let ikinci = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Bağlamdan: Pamuk 3 yaşında")).firstMatch
        XCTAssertTrue(ikinci.waitForExistence(timeout: 10), "ikinci yanıt önceki mesajı bilmeli\n\(app.debugDescription)")
        // Durdur sonrası: uzun (yavaş akan) hikaye sırasında Durdur'a basılır, sonraki mesaj yine bağlamı bilmeli.
        gonder(app, "Bana uzun bir hikaye anlat")
        let durdur = app.buttons["Sesli oturumu ve yanıtı durdur"]
        if durdur.waitForExistence(timeout: 5) { durdur.tap() }
        gonder(app, "Kedimin adı neydi?")
        let ucuncu = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Bağlamdan: kedinin adı Pamuk")).firstMatch
        XCTAssertTrue(ucuncu.waitForExistence(timeout: 15), "Durdur sonrası bağlam kaybolmamalı\n\(app.debugDescription)")
        hataYok(app)
    }
}
