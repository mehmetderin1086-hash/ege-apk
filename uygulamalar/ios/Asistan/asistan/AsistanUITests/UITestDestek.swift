import XCTest

/// P3.10 hermetik UI testi yardımcıları.
/// - Yeni UI testi `XCUIApplication.hermetik(senaryo:)` ile başlar: sahte model sunucusu, animasyonsuz, bellek içi hafıza.
/// - Gerçek modele/ağa çıkan test `try canliKapisi()` ile başlar (yalnız `ASISTAN_CANLI=1`, Canlı test planı).
/// - `Thread.sleep` yerine `bekle(_:_:)` / `kosulBekle(timeout:aralik:_:)`.
extension XCUIApplication {
    /// `ASISTAN_TEST=1` verir: hafıza bellek içi açılır, ama `OnayKapisi.testte` de true olur (zorunlu onaylar otomatik
    /// karara uyar). Onay diyaloğunu sınayan test bunu kullanmamalı; `ek:` ile kendi bayrağını geçirmeli ya da ayrı başlatıcı kurmalı.
    /// `senaryo`: `ASISTAN_SAHTE_SENARYO` JSON'u (SahteSenaryo); nil ise yerleşik senaryo. Kısmi JSON'da yerleşik kurallar arkaya eklenir.
    static func hermetik(senaryo: String? = nil, ek: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--sohbet", "--sahte-model", "--animasyonsuz"] + ek
        var ortam = ["ASISTAN_TEST": "1"]
        if let senaryo { ortam["ASISTAN_SAHTE_SENARYO"] = senaryo }
        app.launchEnvironment = ortam
        return app
    }
}

/// Gerçek modele/ağa çıkan (ücretli ya da dış siteye bağlı) testlerin kapısı.
func canliKapisi() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1", "canlı test: yalnız ASISTAN_CANLI=1")
}

extension XCUIElement {
    /// Koşul gerçekleşene kadar bekler: "exists", "isHittable", "!exists", "!isHittable" ya da "label CONTAINS <metin>".
    /// Bilinmeyen koşul doğrudan NSPredicate biçimi olarak kullanılır.
    @discardableResult
    func bekle(_ kosul: String, _ timeout: TimeInterval) -> Bool {
        let yuklem: NSPredicate
        switch kosul {
        case "exists": yuklem = NSPredicate(format: "exists == true")
        case "!exists": yuklem = NSPredicate(format: "exists == false")
        case "isHittable": yuklem = NSPredicate(format: "exists == true AND hittable == true")
        case "!isHittable": yuklem = NSPredicate(format: "exists == false OR hittable == false")
        default:
            if kosul.hasPrefix("label CONTAINS ") {
                yuklem = NSPredicate(format: "label CONTAINS %@", String(kosul.dropFirst("label CONTAINS ".count)))
            } else {
                yuklem = NSPredicate(format: kosul)
            }
        }
        let beklenti = XCTNSPredicateExpectation(predicate: yuklem, object: self)
        return XCTWaiter().wait(for: [beklenti], timeout: timeout) == .completed
    }
}

/// Sık yoklamalı bekleme (`RunLoop.current.run(until:)`): çok kısa görünen durumu yakalamak için
/// (XCTNSPredicateExpectation ~1 sn aralıkla yokladığından hızlı geçen balonu kaçırabilir). Bilinçli istisnadır;
/// olağan beklemede `bekle(_:_:)` ya da `waitForExistence` kullan.
@MainActor @discardableResult
func kosulBekle(timeout: TimeInterval, aralik: TimeInterval = 0.1, _ kosul: () -> Bool) -> Bool {
    let sinir = Date().addingTimeInterval(timeout)
    while Date() < sinir {
        if kosul() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(aralik))
    }
    return kosul()
}

@MainActor extension XCUIApplication {
    /// İlk dokunuş klavye/başlangıç geçişine denk gelirse menüyü bir kez daha açar.
    func menudenSec(_ kimlik: String, secenek: String) {
        let menu = buttons[kimlik], hedef = buttons[secenek]
        XCTAssertTrue(menu.waitForExistence(timeout: 8))
        menu.tap()
        if !hedef.waitForExistence(timeout: 3) {
            print("MENÜ: ilk dokunuşta açılmadı, ikinci deneme: \(kimlik)")
            menu.tap()
        }
        XCTAssertTrue(hedef.waitForExistence(timeout: 5), "Menü seçeneği açılmadı: \(secenek)")
        if hedef.exists { hedef.tap() }
    }
}
