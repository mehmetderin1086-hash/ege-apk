import XCTest

/// Ek tanı akışı: Yönetim'in Asistan ve Yapay zekâ araçları satırlarını dört yazı boyutunda denetler.
/// Kontrast denetimi `GorunurAlan.kenardaKalanMetinKontrasti` ile, KitapBulUITests'teki yedi denetimle
/// aynı dar istisnayı kullanır: yalnız sekme içeriğinin kenarında tam çizilmeyen başka satır metinleri
/// muaf tutulur, hedef satırın kendi metinleri hiç muaf tutulmaz. Diğer denetim türlerinde istisna yoktur.
/// All data are the ordinary -ui-testing temporary fixture; no production records are used.
final class AccessibilityAttributionUITests: XCTestCase {
    private let bundleID = "com.mehmetderin.kitapkatalogu"

    func testYonetimNormalYaziBoyutu() throws { try denetle("Normal", "UICTContentSizeCategoryL") }
    func testYonetimEnBuyukStandartYaziBoyutu() throws { try denetle("EnBuyukStandart", "UICTContentSizeCategoryXXXL") }
    func testYonetimAX2YaziBoyutu() throws { try denetle("AX2", "UICTContentSizeCategoryAccessibilityL") }
    func testYonetimAX5YaziBoyutu() throws { try denetle("AX5", "UICTContentSizeCategoryAccessibilityXXXL") }

    /// Denetim bulguları ve görünür alan ölçümleri düz metin yerine JSON eki olarak saklanır.
    private var records: [[String: String]] = []

    private func record(_ kind: String, _ fields: [String: String]) {
        var entry = fields; entry["tur"] = kind
        records.append(entry)
    }

    private func attachRecords(_ name: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]) else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Denetim-\(name).json"; attachment.lifetime = .keepAlways; add(attachment)
        records = []
    }

    private func denetle(_ name: String, _ category: String) throws {
        continueAfterFailure = true
        defer { attachRecords(name) }
        let app = XCUIApplication(bundleIdentifier: bundleID)
        app.launchArguments = [
            "-ui-testing", "-ui-testing-reset-navigation", "-onboardingShown", "YES",
            "-lastSeenWhatsNewVersion", "1.0", "-roleLockEnabled", "NO",
            "-visualEffectsEnabled", "NO", "-edgeSwipeTabs", "NO", "-simpleMode", "NO",
            "-appearanceMode", "dark", "-UIPreferredContentSizeCategoryName", category,
            "-a11y-font-diagnostics"
        ]
        app.launch()
        let management = app.tabBars.buttons["Yönetim"]
        guard management.waitForExistence(timeout: 30) else {
            XCTFail("\(name): Yönetim sekmesi açılmadı"); app.terminate(); return
        }
        management.tap()
        let search = app.searchFields.firstMatch
        guard search.waitForExistence(timeout: 8) else {
            XCTFail("\(name): gerçek Yönetim araması bulunamadı"); app.terminate(); return
        }
        // This is the product's real search operation, not a debug-only filtered screen.
        search.tap()
        if let existing = search.value as? String, !existing.isEmpty, existing != "Ara" {
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        for character in "asistan" { search.typeText(String(character)) }
        XCTAssertEqual(search.value as? String, "asistan")
        search.typeText("\n")
        if app.keyboards.firstMatch.exists {
            // Yönetim'in ScrollView'u `.scrollDismissesKeyboard(.immediately)` taşır: gerçek bir
            // kaydırma klavyeyi kapatır. Bu değiştirici kalkarsa aşağıdaki klavye adımı kırılır.
            app.swipeUp()
        }
        let keyboardGone = NSPredicate { _, _ in !app.keyboards.firstMatch.exists }
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: keyboardGone, object: nil)], timeout: 5) == .completed,
            "\(name): denetimden önce klavye kapanmalı")
        if app.keyboards.firstMatch.exists {
            capture(app, "\(name)-KeyboardStillVisible"); app.terminate(); return
        }
        let assistant = app.buttons["management.assistant"]
        let ai = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Yapay zekâ araçları")).firstMatch
        let targets: [(String, XCUIElement, [String])] = [
            ("Asistan", assistant, ["Asistan", "Yazıyla veya sesle sor; değişiklikleri incele"]),
            ("AI", ai, ["Yapay zekâ araçları", "Öneri, analiz ve kitap kartı"])
        ]
        for (targetName, target, completeTexts) in targets {
            // Satır görünür alandan uzunsa üstü hizalanır ve denetim görünen kısımda yine çalışır.
            guard GorunurAlan.satiriGoster(target, in: app) != .getirilemedi else {
                capture(app, "\(name)-\(targetName)-NotFullyVisible")
                XCTFail("\(name): \(targetName) satırının tümü gerçek görünür alana getirilemedi")
                continue
            }
            for text in completeTexts {
                XCTAssertTrue(target.label.contains(text), "\(name): tam erişilebilir açıklama korunmalı: \(text)")
            }
            capture(app, "\(name)-\(targetName)-BeforeAudit")
            // Kontrast önce, satır görünür alana getirildiği konumda ölçülür: Dynamic Type denetimi
            // yazı boyutunu değiştirirken kaydırma konumunu sıfırlayabiliyor.
            let hedefCercevesi = target.frame
            var kenardakiler = Set<String>()
            do {
                try app.performAccessibilityAudit(for: [.contrast]) { issue in
                    self.record("audit", ["boyut": name, "hedef": targetName, "ozet": issue.compactDescription,
                        "oge": issue.element?.label ?? "-", "cerceve": "\(issue.element?.frame ?? .zero)", "ayrinti": issue.detailedDescription])
                    // Dar istisna: kenarda kırpılan ya da arama alanının altına giren başka satır metni.
                    // Hedef satır (üstü hizalanıp alt kısmı kırpılsa da) muaf değildir; öğesi
                    // bilinmeyen bulgu ve çubuk öğeleri de sayılır.
                    let muaf = GorunurAlan.kenardaKalanMetinKontrasti(issue, in: app, korunan: hedefCercevesi)
                    if muaf, let etiket = issue.element?.label { kenardakiler.insert(etiket) }
                    return muaf
                }
                // Muaf tutulan kenar metinleri kaydırılıp tam görünür alanda yeniden denetlenir;
                // istisna yalnız ilk geçişte kırpılmış metni örter, kontrastı sonsuza dek gizlemez.
                for etiket in kenardakiler.sorted() {
                    let metin = app.staticTexts.matching(NSPredicate(format: "label == %@", etiket)).firstMatch
                    guard metin.exists, GorunurAlan.satiriGoster(metin, in: app) != .getirilemedi else {
                        self.record("kenar-yeniden-denetim", ["boyut": name, "etiket": etiket, "durum": "kaydirilamadi"])
                        continue
                    }
                    try app.performAccessibilityAudit(for: [.contrast]) { issue in
                        // Yalnız yeniden denetlenen metnin kendi bulgusu sayılır.
                        guard issue.element?.label == etiket else { return true }
                        self.record("kenar-yeniden-denetim", ["boyut": name, "etiket": etiket, "durum": "bulgu", "ozet": issue.compactDescription])
                        return false
                    }
                }
                try app.performAccessibilityAudit(for: [.dynamicType, .textClipped]) { issue in
                    self.record("audit", ["boyut": name, "hedef": targetName, "ozet": issue.compactDescription,
                        "oge": issue.element?.label ?? "-", "cerceve": "\(issue.element?.frame ?? .zero)", "ayrinti": issue.detailedDescription])
                    // No nil, offscreen, toolbar, or text issue is ignored.
                    return false
                }
            } catch {
                XCTFail("\(name)-\(targetName) denetimi: \(error)")
            }
            capture(app, "\(name)-\(targetName)-AfterAudit")
        }
        app.terminate()
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        record("viewport", ["ad": name, "gorunur": "\(GorunurAlan.sinirlar(app))", "sekmeCubugu": "\(app.tabBars.firstMatch.frame)"])
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = name; screen.lifetime = .keepAlways; add(screen)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + "-Hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
    }
}
