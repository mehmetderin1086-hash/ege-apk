import XCTest

/// Testler yalnız ayrı bellek deposu ve geçici JSON dosyaları ile çalışır.
final class KitapBulUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.mehmetderin.kitapkatalogu")
        app.launchArguments = ["-ui-testing", "-ui-testing-reset-navigation", "-onboardingShown", "YES", "-lastSeenWhatsNewVersion", "1.0", "-roleLockEnabled", "NO", "-visualEffectsEnabled", "NO", "-edgeSwipeTabs", "NO", "-appearanceMode", "light"]
        app.launch()
    }
    private func launchPreference(_ key: String, _ value: String) {
        if let index = app.launchArguments.firstIndex(of: key), index + 1 < app.launchArguments.count {
            app.launchArguments.removeSubrange(index...(index + 1))
        }
        app.launchArguments += [key, value]
    }
    /// Sekme düğmesi önce kararlı `tab.<sekme>` kimliğiyle, yoksa görünen adla bulunur.
    private static let tabIdentifiers = ["Ana Sayfa": "anaSayfa", "Kitaplar": "kitaplar", "Ekle": "katalog",
                                         "Ödünç": "odunc", "Yönetim": "yonetim"]
    private func tab(_ name: String) {
        var button = app.tabBars.buttons[name]
        if let id = Self.tabIdentifiers[name], app.buttons["tab." + id].waitForExistence(timeout: 1) {
            button = app.buttons["tab." + id]
        }
        XCTAssertTrue(button.waitForExistence(timeout: 8), "Sekme bulunamadı: \(name)")
        button.tap()
    }
    /// Seçenek kimliği `student.option.<uuid>` olarak da, eski `student.option.<ad>.<sınıf>.<no>` olarak da çözülür.
    private func studentOption(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'student.option.' AND label CONTAINS[c] %@", name)).firstMatch
    }
    private func audit(_ page: String) throws {
        // Kontrast, Dynamic Type denetimi yazı boyutunu değiştirip düzeni yeniden kurmadan önce,
        // ekranın açıldığı düzende ölçülür; ardından kalan bütün denetim türleri koşulur.
        try app.performAccessibilityAudit(for: [.contrast]) { issue in
            self.recordAudit(issue, page: page)
            // Araç, gezinme ve sekme çubuğu öğeleri ya da ekran konumu topluca muaf tutulmaz. Tek dar
            // istisna: kaydırılan sekme içeriğinde kenarda kırpılan, yani tam çizilmeyen metnin kontrast
            // bulgusu (koşulları GorunurAlan.kenardaKalanMetinKontrasti'nde).
            return GorunurAlan.kenardaKalanMetinKontrasti(issue, in: self.app)
        }
        try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(.contrast)) { issue in
            self.recordAudit(issue, page: page)
            // Sistemin A–Z dizin çubuğu (UIIndexBarAccessoryView) uygulamanın denetimi dışındadır;
            // yalnız bu sistem görünümünün kendi küçük dokunma alanı bulgusu atlanır.
            return issue.auditType == .hitRegion && issue.detailedDescription.contains("UIIndexBarAccessoryView")
        }
    }
    private func recordAudit(_ issue: XCUIAccessibilityAuditIssue, page: String) {
        print("AUDIT|\(page)|\(issue.compactDescription)|\(issue.element?.label ?? "-")|\(issue.element?.frame ?? .zero)")
        print("AUDIT_DETAIL|\(page)|\(issue.detailedDescription)")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Audit-\(page)-\(issue.compactDescription)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    private func button(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }
    private func waitUntilMissing(_ element: XCUIElement) {
        let predicate = NSPredicate { _, _ in !element.exists }
        expectation(for: predicate, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
    }
    func testBesAnaSekme() {
        for name in ["Ana Sayfa", "Kitaplar", "Ekle", "Ödünç", "Yönetim"] { tab(name) }
        XCTAssertTrue(app.buttons["management.settings"].exists || app.buttons["management.assistant"].exists)
    }
    func testAnaSayfaErisilebilir() throws {
        tab("Ana Sayfa")
        let scroll = app.scrollViews.firstMatch
        let bar = app.tabBars.firstMatch
        if scroll.exists {
            // Kaydırma alanının alt kenarı çubuğun üst kenarını geçiyorsa içerik çubuğun arkasına uzanıyor demektir.
            print("HOME_VIEWPORT|scroll=\(scroll.frame)|tabbar=\(bar.frame)|scrollMaxY=\(scroll.frame.maxY)|barMinY=\(bar.frame.minY)|ortusme=\(scroll.frame.maxY - bar.frame.minY)")
        }
        try audit("Ana Sayfa")
    }
    func testKitaplarErisilebilir() throws { tab("Kitaplar"); try audit("Kitaplar") }
    func testEkleErisilebilir() throws { tab("Ekle"); try audit("Ekle") }
    func testOduncErisilebilir() throws { tab("Ödünç"); try audit("Ödünç") }
    func testYonetimErisilebilir() throws { tab("Yönetim"); try audit("Yönetim") }

    func testGecikenKartiDogruListeyiAcar() {
        tab("Ana Sayfa")
        let overdue = app.buttons["home.overdue"]
        for _ in 0..<6 where !overdue.exists || !overdue.isHittable { app.swipeUp() }
        XCTAssertTrue(overdue.waitForExistence(timeout: 5))
        overdue.tap()
        let delayed = button(containing: "Geciken Kitap")
        XCTAssertTrue(delayed.waitForExistence(timeout: 5))
        XCTAssertFalse(button(containing: "Bugün İade").exists)
    }
    func testBugunIadeKartiDogruListeyiAcar() {
        tab("Ana Sayfa")
        let due = app.buttons["home.dueToday"]
        for _ in 0..<6 where !due.exists || !due.isHittable { app.swipeUp() }
        XCTAssertTrue(due.waitForExistence(timeout: 5))
        due.tap()
        XCTAssertTrue(button(containing: "Bugün İade").waitForExistence(timeout: 5))
        XCTAssertFalse(button(containing: "Geciken Kitap").exists)
    }
    func testYonetimAramasindaArsivBulunur() {
        tab("Yönetim")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        for character in "arsiv" { search.typeText(String(character)) }
        XCTAssertEqual(search.value as? String, "arsiv")
        XCTAssertTrue(app.buttons["management.archiveExport"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["management.archiveImport"].exists)
        XCTAssertFalse(app.buttons["management.students"].exists)
    }
    /// Kendi başına çalışan araç, boş "Katalog Yönetimi" katmanı ve bekleme olmadan tek sayfada açılır.
    func testYonetimOgrencilerTekKatmandaAcilir() {
        tab("Yönetim")
        let students = app.buttons["management.students"]
        XCTAssertTrue(students.waitForExistence(timeout: 5))
        XCTAssertTrue(students.isHittable, "Öğrenciler, Sık kullanılanlar bölümünde kaydırmadan görünmeli")
        students.tap()
        let studentsBar = app.navigationBars["Öğrenciler"]
        XCTAssertTrue(studentsBar.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Katalog Yönetimi"].exists)
        // Bugün alttaki sayfa da sorguda görünüyor (yukarıdaki denetim eski yolda kırmızıydı).
        // Bu davranışa bağlı kalmamak için: kapatınca doğrudan Yönetim'e dönülmeli; eski çift
        // katmanda burada boş Katalog Yönetimi sayfası açık kalıyordu.
        studentsBar.buttons["Kapat"].tap()
        waitUntilMissing(studentsBar)
        XCTAssertTrue(app.navigationBars["Yönetim"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Katalog Yönetimi"].waitForExistence(timeout: 2))
        XCTAssertTrue(students.isHittable)
    }
    /// Görevli modunda Ayarlar kilitliyken yazıyı büyütmek (Sade mod) yönetici kimliği istemez.
    /// Anahtara dokunulmaz: tercih kalıcıdır ve sonraki testlerin düzenini değiştirirdi.
    func testKilitliAyarlardaSadeModAnahtariVar() {
        app.terminate(); launchPreference("-roleLockEnabled", "YES"); app.launch()
        tab("Ana Sayfa")
        let gear = app.navigationBars.buttons["Ayarlar"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5)); gear.tap()
        XCTAssertTrue(app.buttons["Face ID ile Kilidi Aç"].waitForExistence(timeout: 5))
        let simpleMode = app.switches["lock.simpleMode"]
        XCTAssertTrue(simpleMode.exists)
        XCTAssertTrue(simpleMode.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Kilitli-Ayarlar-SadeMod"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    /// En büyük yazıda kilit ekranı sayfaya sığmaz; ContentUnavailableView kendi içinde kaydırılır
    /// ve anahtar kaydırılarak erişilebilir kalmalı.
    func testKilitliAyarlardaSadeModAnahtariEnBuyukYazida() {
        app.terminate()
        launchPreference("-roleLockEnabled", "YES")
        launchPreference("-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL")
        app.launch()
        tab("Ana Sayfa")
        let gear = app.navigationBars.buttons["Ayarlar"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5)); gear.tap()
        XCTAssertTrue(app.buttons["Face ID ile Kilidi Aç"].waitForExistence(timeout: 5))
        let simpleMode = app.switches["lock.simpleMode"]
        XCTAssertTrue(simpleMode.exists)
        // isHittable tek başına yetmez: anahtarın yalnız birkaç noktalık şeridi pencerenin
        // altında kaldığında da dokunulabilir sayılıyor. Anahtarın tamamı pencerede görünmeli.
        let pencere = app.windows.firstMatch.frame
        for _ in 0..<4 where !pencere.contains(simpleMode.frame) { app.swipeUp() }
        XCTAssertTrue(pencere.contains(simpleMode.frame),
                      "Sade mod anahtarına kaydırarak ulaşılabilmeli: \(simpleMode.frame) ⊄ \(pencere)")
        XCTAssertTrue(simpleMode.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Kilitli-Ayarlar-SadeMod-AX5"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testKitapOduncVerVeIadeAl() {
        tab("Kitaplar")
        let book = button(containing: "Deneme Kitabı")
        XCTAssertTrue(book.waitForExistence(timeout: 5)); book.tap()
        let lend = app.buttons["book.lend"]
        if !lend.isHittable { app.swipeUp() }
        XCTAssertTrue(lend.waitForExistence(timeout: 5)); lend.tap()
        app.buttons["lend.selectStudent"].tap()
        let student = studentOption("Deneme Öğrencisi")
        XCTAssertTrue(student.waitForExistence(timeout: 5)); student.tap()
        let save = app.buttons["lend.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5)); XCTAssertTrue(save.isEnabled); save.tap()
        waitUntilMissing(save)
        tab("Ödünç")
        let active = app.segmentedControls.buttons["Etkin"]
        if active.exists { active.tap() }
        let loan = button(containing: "Deneme Kitabı")
        // Yeni vade sırasındaki kayıt, özet ve mevcut ödünçlerin altında olabilir.
        for _ in 0..<5 where !loan.exists { app.swipeUp() }
        XCTAssertTrue(loan.waitForExistence(timeout: 5)); loan.tap()
        let completed = app.buttons["loan.readingCompleted"]
        for _ in 0..<5 where !completed.exists || !completed.isHittable { app.swipeUp() }
        XCTAssertTrue(completed.waitForExistence(timeout: 5)); completed.tap()
        let finished = app.buttons["Tamamladı"]
        XCTAssertTrue(finished.waitForExistence(timeout: 5)); finished.tap()
        let giveBack = app.buttons["loan.return"]
        for _ in 0..<5 where !giveBack.exists || !giveBack.isHittable { app.swipeUp() }
        XCTAssertTrue(giveBack.waitForExistence(timeout: 5)); giveBack.tap()
        waitUntilMissing(giveBack)
        waitUntilMissing(button(containing: "Deneme Kitabı"))
    }
    /// Barkod masası: Ana Sayfa'dan ödünç verilir, "İade al" masayı iade modunda açar ve kitap
    /// öğrenci seçmeden iade alınır. Simülatörde kamera olmadığından kod elle girilir.
    func testBarkodlaIadeOgrenciSecmedenCalisir() {
        let isbn = "9786053607021"
        let result = app.descendants(matching: .any).matching(identifier: "quickLoan.result").firstMatch
        // Sonuç satırı ve "Bitti" panel kaydırılmadan tümüyle görünmeli: masa açıkken her ek kitap 0 dokunuş.
        func sonucKaydirmadanGorunur(_ asama: String) {
            let panel = app.scrollViews.containing(.textField, identifier: "quickLoan.code").firstMatch
            let bitti = app.buttons["Bitti"]
            let ekran = app.frame.height
            // Panel ekranın yarısından kısadır; daha büyük bir kaydırma alanı eşleşirse denetim boşa çıkmasın.
            let gorunur = NSPredicate { _, _ in
                panel.exists && panel.frame.height < ekran / 2 && panel.frame.contains(result.frame) && bitti.isHittable
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gorunur, object: nil)], timeout: 3), .completed,
                           "\(asama) sonucu kaydırmadan görünmeli: sonuç \(result.frame), panel \(panel.frame)")
        }
        tab("Ana Sayfa")
        let lendTask = app.buttons["home.task.lend"]
        XCTAssertTrue(lendTask.waitForExistence(timeout: 5)); lendTask.tap()
        let student = app.buttons["quickLoan.student"]
        XCTAssertTrue(student.waitForExistence(timeout: 5)); student.tap()
        let option = studentOption("Deneme Öğrencisi")
        XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
        // Öğrencinin elindeki ve geciken kitap okutmadan önce görünür (fikstürde 1 gecikmiş).
        let summary = app.descendants(matching: .any).matching(identifier: "quickLoan.studentSummary").firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("1 gecikmiş"), "Öğrenci özeti: \(summary.label)")
        let code = app.textFields["quickLoan.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5)); code.tap(); code.typeText(isbn + "\n")
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("Deneme Öğrencisi"), "Ödünç sonucu: \(result.label)")
        sonucKaydirmadanGorunur("Ödünç")
        app.buttons["Bitti"].tap()
        waitUntilMissing(code)

        let returnTask = app.buttons["home.task.returnLoan"]
        XCTAssertTrue(returnTask.waitForExistence(timeout: 5)); returnTask.tap()
        let mode = app.segmentedControls["quickLoan.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        XCTAssertTrue(mode.buttons["İade al"].isSelected, "Ana Sayfa'daki İade al masayı iade modunda açmalı")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "quickLoan.returnBanner").firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "quickLoan.studentSummary").firstMatch.exists)
        XCTAssertTrue(code.waitForExistence(timeout: 5)); code.tap(); code.typeText(isbn + "\n")
        // Deneme Kitabı'nın üç nüshası var ve demirbaş okutulmadı: tek aday da onaylatılır.
        let candidate = app.buttons["quickLoan.candidate"].firstMatch
        XCTAssertTrue(candidate.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Kimin iadesi?"].exists)
        XCTAssertTrue(candidate.label.contains("Deneme Öğrencisi"), "Aday: \(candidate.label)")
        candidate.tap()
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("İade alındı") && result.label.contains("Deneme Öğrencisi"), "İade sonucu: \(result.label)")
        sonucKaydirmadanGorunur("İade")
        app.buttons["Bitti"].tap()
        waitUntilMissing(code)
    }
    /// "Kitap nerede?" tek dokunuşla aranır: sonuç satırında yer ve durum ayrıntı açılmadan okunur.
    /// Ayrıntıda konum üst bölümde, "Ödünç ver" kaydırmadan; Kitaplar'da aynı konum hücrede görünür.
    func testKitapNeredeKonumuGosterir() {
        tab("Kitaplar")
        let cell = button(containing: "Deneme Kitabı")
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        XCTAssertTrue(cell.label.hasPrefix("Deneme Kitabı"), "Hücre etiketi kitap adıyla başlamalı: \(cell.label)")
        XCTAssertTrue(cell.label.contains("Dolap 3 · Raf 2"), "Kitaplar hücresinde konum: \(cell.label)")

        tab("Ana Sayfa")
        let find = app.buttons["home.findBook"]
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        XCTAssertTrue(find.isHittable, "Kitap nerede? satırı ilk ekranda dokunulabilir olmalı")
        find.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap()
        for character in "Deneme Kit" { search.typeText(String(character)) }
        let result = app.buttons.matching(identifier: "search.result").matching(NSPredicate(format: "label CONTAINS %@", "Deneme Kitabı")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("Dolap 3 · Raf 2"), "Sonuç satırında konum: \(result.label)")
        XCTAssertTrue(result.label.contains("3/3 rafta"), "Sonuç satırında durum: \(result.label)")
        result.tap()
        let location = app.descendants(matching: .any).matching(identifier: "book.location").firstMatch
        XCTAssertTrue(location.waitForExistence(timeout: 5))
        XCTAssertTrue(location.label.contains("Dolap 3 · Raf 2"), "Ayrıntıdaki konum: \(location.label)")
        let lend = app.buttons["book.lend"]
        XCTAssertTrue(lend.waitForExistence(timeout: 5))
        XCTAssertTrue(lend.isHittable, "Ödünç ver ayrıntının üst bölümünde kaydırmadan görünmeli")
    }
    func testYeniKitapFormuDuzeltmeyiKaybetmez() {
        tab("Ekle")
        let manual = app.buttons["add.manual"]
        if !manual.isHittable { app.swipeUp() }
        XCTAssertTrue(manual.waitForExistence(timeout: 5)); manual.tap()
        // Alanın üstünde "Kitap adı" yazısı da durduğundan alan kimliğiyle bulunur
        let title = app.textFields["editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Geçici deneme")
        app.buttons["editor.cancel"].tap()
        // iOS 27'deki onay penceresi iptal rolündeki "Devam Et" düğmesini göstermiyor; pencerenin
        // dışına dokunmak düzenlemeye döner. (Eski sorgu Ekle'deki oturum panelinin "Devam Et"
        // düğmesine denk geliyordu; o düğmenin adı "Kontrole Devam Et" oldu.)
        let discard = app.buttons["Kaydetmeden Kapat"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        let dialog = app.sheets["Kaydedilmemiş değişiklikler var"]
        let keep = dialog.buttons["Devam Et"]
        let keepByID = app.buttons["editor.keepEditing"]
        if keepByID.exists && keepByID.isHittable {
            keepByID.tap()
        } else if keep.exists && keep.isHittable {
            keep.tap()
        } else {
            let frame = dialog.exists ? dialog.frame : discard.frame
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: frame.midX, dy: max(140, frame.minY - 150))).tap()
        }
        waitUntilMissing(discard)
        XCTAssertEqual(title.value as? String, "Geçici deneme")
        app.buttons["editor.cancel"].tap()
        app.buttons["Kaydetmeden Kapat"].tap()
        waitUntilMissing(app.buttons["editor.save"])
    }
    /// Editör sade açılır: seyrek alanlar katlı "Diğer bilgiler" grubundadır; son yeni kaydın
    /// konumu "Son konumu kullan" ile tek dokunuşta gelir (değer başlatma argümanından okunur, yazılmaz).
    func testYeniKitapFormuSonKonumVeDigerBilgiler() {
        app.terminate()
        launchPreference("-sonKonum.yer", "Kütüphane")
        launchPreference("-sonKonum.dolap", "3")
        launchPreference("-sonKonum.raf", "2")
        app.launch()
        tab("Ekle")
        let manual = app.buttons["add.manual"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5)); manual.tap()
        XCTAssertTrue(app.textFields["editor.title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["editor.publicationYear"].exists, "Basım yılı katlı grupta durmalı")

        let sonKonum = app.buttons["editor.useLastLocation"]
        for _ in 0..<4 where !sonKonum.isHittable { app.swipeUp() }
        XCTAssertTrue(sonKonum.waitForExistence(timeout: 5))
        XCTAssertTrue(sonKonum.label.contains("Kütüphane · Dolap 3 · Raf 2"), "Düğme: \(sonKonum.label)")
        sonKonum.tap()
        XCTAssertEqual(app.textFields["editor.location"].value as? String, "Kütüphane")
        XCTAssertEqual(app.textFields["editor.cabinet"].value as? String, "3")
        waitUntilMissing(sonKonum)
        // Form satırları ekrana girince oluşur; raf alanı için biraz kaydırılır
        let raf = app.textFields["editor.shelf"]
        for _ in 0..<3 where !raf.isHittable { app.swipeUp() }
        XCTAssertEqual(raf.value as? String, "2")

        let diger = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Diğer bilgiler")).firstMatch
        for _ in 0..<3 where !diger.isHittable { app.swipeUp() }
        XCTAssertTrue(diger.waitForExistence(timeout: 5)); diger.tap()
        let yil = app.textFields["editor.publicationYear"]
        for _ in 0..<3 where !yil.exists { app.swipeUp() }
        XCTAssertTrue(yil.waitForExistence(timeout: 5), "Grup açılınca basım yılı görünmeli")

        app.buttons["editor.cancel"].tap()
        app.buttons["Kaydetmeden Kapat"].tap()
        waitUntilMissing(app.buttons["editor.save"])
    }
    /// Ekle'de en sık iki yol (barkod ve elle) ilk grupta: kaydırmadan, sekme çubuğunun üstünde dokunulabilir.
    func testEkleIlkGruptaBarkodVeElle() {
        tab("Ekle")
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        for kimlik in ["add.barcode", "add.manual"] {
            let kart = app.buttons[kimlik]
            XCTAssertTrue(kart.waitForExistence(timeout: 5), "Kart bulunamadı: \(kimlik)")
            XCTAssertTrue(kart.isHittable, "\(kimlik) kaydırmadan dokunulabilir olmalı")
            XCTAssertLessThanOrEqual(kart.frame.maxY, bar.frame.minY, "\(kimlik) sekme çubuğunun arkasında kalmamalı")
        }
        // Barkod kartı menü açmaz; toplu modlar ayrı kartta, Canlı Kapak Ekle'de de var
        XCTAssertTrue(app.descendants(matching: .any)["add.barcodeModes"].exists, "Toplu tarama menüsü ayrı kart olmalı")
        XCTAssertTrue(app.descendants(matching: .any)["add.liveCover"].exists, "Canlı Kapak kartı Ekle'de olmalı")
    }
    /// Kayıttan sonra altta görünür onay şeridi çıkar; "Geri al" yalnız bu kaydı geri alır.
    func testEkleKayittanSonraSeritGeriAlinir() {
        tab("Ekle")
        let manual = app.buttons["add.manual"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5)); manual.tap()
        let title = app.textFields["editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Şerit Deneme Kitabı")
        let save = app.buttons["editor.save"]
        XCTAssertTrue(save.isEnabled); save.tap()
        waitUntilMissing(save)

        let serit = app.descendants(matching: .any).matching(identifier: "add.lastSaved").firstMatch
        XCTAssertTrue(serit.waitForExistence(timeout: 5), "Kayıttan sonra şerit görünmeli")
        XCTAssertTrue(serit.label.contains("Şerit Deneme Kitabı") && serit.label.contains("eklendi"), "Şerit: \(serit.label)")
        let undo = app.buttons["add.lastSaved.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(undo.isHittable, "Geri al sekme çubuğunun üstünde dokunulabilir olmalı")
        undo.tap()
        let geriAlindi = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@", "add.lastSaved", "geri alındı")).firstMatch
        XCTAssertTrue(geriAlindi.waitForExistence(timeout: 5), "Geri almadan sonra şerit bunu söylemeli")
        XCTAssertFalse(undo.exists, "Geri alınan kayıt ikinci kez geri alınmaz")

        tab("Kitaplar")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap()
        for character in "Şerit Deneme" { search.typeText(String(character)) }
        XCTAssertFalse(button(containing: "Şerit Deneme Kitabı").waitForExistence(timeout: 2), "Geri alınan kitap katalogda kalmamalı")
    }
    func testKatalogAramaVeKaydirmaKonumuGeriGelir() {
        app.terminate()
        app.launchArguments += ["-ui-testing-scroll-catalog", "-kitaplarKapakGorunumu2", "YES"]
        app.launch()
        tab("Kitaplar")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap()
        // Sorgu görünümü güncellenirken tek otomasyon olayında harf düşmesini önle.
        let query = "Kaydirma"
        for character in query { search.typeText(String(character)) }
        XCTAssertEqual(search.value as? String, query)
        search.typeText("\n")
        waitUntilMissing(app.keyboards.firstMatch)
        let scroll = app.scrollViews["books.scroll.grid"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for _ in 0..<4 { scroll.swipeUp() }
        let region = scroll.frame.intersection(app.frame)
        let visible = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Kaydırma Kitabı")).allElementsBoundByIndex.filter {
            $0.isHittable && region.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
        }
        guard let selected = visible.first else { XCTFail("Kaydırmadan sonra görünür kitap bulunamadı"); return }
        let title = selected.label
        XCTAssertFalse(title.contains("Kitabı 01"), "Test gerçekten aşağı kaydırmalı")
        selected.tap()
        let back = app.navigationBars.buttons["Kitaplar"]
        XCTAssertTrue(back.waitForExistence(timeout: 5)); back.tap()
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[title].isHittable, "Ayrıntıdan dönünce kitap aynı bölgede kalmalı")
        XCUIDevice.shared.press(.home)
        app.launchArguments.removeAll { $0 == "-ui-testing-reset-navigation" }
        app.terminate(); app.launch()
        tab("Kitaplar")
        // Arama artık sahne içinde kalır (@SceneStorage); uygulama sonlandırılıp açılınca boş başlar.
        XCTAssertNotEqual(app.searchFields.firstMatch.value as? String, query)
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[title].isHittable, "Yeniden açılışta kayıtlı kitap kimliğine dönülmeli")
    }
    /// Dar iPhone ekranında normal ve büyük standart yazıda bölüm başlıkları tam kalmalı.
    func testBuyukStandartYazidaKatalogBolumuTamBasliklaSecilir() {
        for category in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryXXL"] {
            app.terminate()
            launchPreference("-UIPreferredContentSizeCategoryName", category)
            app.launch()
            tab("Kitaplar")
            let sectionMenu = app.buttons["catalog.section.menu"]
            XCTAssertTrue(sectionMenu.waitForExistence(timeout: 8))
            XCTAssertTrue(sectionMenu.isHittable)

            func chooseSection(_ title: String) {
                sectionMenu.tap()
                let choices = app.buttons.matching(NSPredicate(format: "label == %@", title))
                // “Kitaplar” ayrıca gerçek alt sekmede bulunur; yalnız açılan menü seçeneğine basılır.
                let menuOptionReady = NSPredicate { _, _ in
                    choices.allElementsBoundByIndex.contains {
                        $0.isHittable && !$0.frame.intersects(self.app.tabBars.firstMatch.frame)
                    }
                }
                expectation(for: menuOptionReady, evaluatedWith: nil)
                waitForExpectations(timeout: 5)
                guard let option = choices.allElementsBoundByIndex.first(where: {
                    $0.isHittable && !$0.frame.intersects(app.tabBars.firstMatch.frame)
                }) else {
                    XCTFail("Açılan menüde gerçek seçenek bulunamadı: \(title)")
                    return
                }
                option.tap()
                XCTAssertEqual(sectionMenu.value as? String, title)
            }

            chooseSection("Kitaplar")
            XCTAssertTrue(button(containing: "Deneme Kitabı").waitForExistence(timeout: 5))
            chooseSection("Kategoriler")
            // Fixture'daki üç eser kategorisizdir; kitap listesi yerine gerçek kategori kartı görünür.
            XCTAssertTrue(button(containing: "Kategorisiz").waitForExistence(timeout: 5))
            XCTAssertFalse(button(containing: "Deneme Kitabı").exists)
            XCTAssertEqual(sectionMenu.value as? String, "Kategoriler")
            chooseSection("Kitaplar")
            XCTAssertTrue(button(containing: "Deneme Kitabı").waitForExistence(timeout: 5))
            XCTAssertFalse(button(containing: "Kategorisiz").exists)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = category + "-Katalog-Bolum-Secimi"; screenshot.lifetime = .keepAlways; add(screenshot)
        }
    }

    func testBuyukYazidaAnaEkranlar() throws {
        app.terminate()
        launchPreference("-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL")
        app.launch()
        for name in ["Ana Sayfa", "Kitaplar", "Ekle", "Ödünç", "Yönetim"] {
            tab(name)
            try app.performAccessibilityAudit(for: [.dynamicType, .textClipped]) { issue in
                self.recordAudit(issue, page: "BuyukYazi-\(name)")
                return false
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "AX5-\(name)"; screenshot.lifetime = .keepAlways; add(screenshot)
        }
    }
    /// Kitaplar sekmesi en büyük yazıda tüm denetim türleriyle (kontrast dahil) taranır.
    func testKitaplarBuyukYazidaErisilebilir() throws {
        app.terminate()
        launchPreference("-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL")
        app.launch()
        tab("Kitaplar")
        try audit("Kitaplar-AX5")
    }
    /// Tarayıcı paneli (simülatörde kamera yok; panel kimlikleriyle yoklanır) en büyük yazıda taşmamalı.
    func testBuyukYazidaTaramaPaneli() throws {
        app.terminate()
        launchPreference("-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL")
        app.launch()
        tab("Ekle")
        let barcode = app.buttons["add.barcode"]
        for _ in 0..<4 where !barcode.exists || !barcode.isHittable { app.swipeUp() }
        XCTAssertTrue(barcode.waitForExistence(timeout: 5)); barcode.tap()
        let panel = app.descendants(matching: .any)["scanner.panel"]
        try XCTSkipUnless(panel.waitForExistence(timeout: 8), "Tarayıcı paneli (scanner.panel) bu derlemede yok")
        try app.performAccessibilityAudit(for: [.dynamicType, .textClipped]) { issue in
            self.recordAudit(issue, page: "AX5-TaramaPaneli")
            return false
        }
        let close = app.buttons["scanner.close"]
        if close.exists { close.tap() }
    }
    /// Tema değişince açık Ayarlar sayfası kapanmaz.
    func testTemaDegisinceAyarlarAcikKalir() {
        tab("Ana Sayfa")
        let gear = app.navigationBars.buttons["Ayarlar"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5)); gear.tap()
        XCTAssertTrue(app.navigationBars["Ayarlar"].waitForExistence(timeout: 5))
        let card = app.buttons["settings.card.gorunum"]
        XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
        let accent = app.buttons["settings.themeAccent"]
        XCTAssertTrue(accent.waitForExistence(timeout: 5), "Görünüm sayfası açılmadı")
        let theme = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tema'")).firstMatch
        XCTAssertTrue(theme.waitForExistence(timeout: 5)); theme.tap()
        let dark = app.buttons["Koyu"]
        XCTAssertTrue(dark.waitForExistence(timeout: 5)); dark.tap()
        XCTAssertTrue(app.buttons["settings.themeAccent"].waitForExistence(timeout: 5), "Tema değişince Ayarlar kapanmamalı")
    }

    func testKoyuGorunumdeAnaEkranlar() throws {
        let previousFailurePolicy = continueAfterFailure
        continueAfterFailure = true
        defer { continueAfterFailure = previousFailurePolicy }
        app.terminate(); launchPreference("-appearanceMode", "dark"); app.launch()
        for name in ["Ana Sayfa", "Kitaplar", "Ekle", "Ödünç", "Yönetim"] {
            tab(name)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Koyu-\(name)"; screenshot.lifetime = .keepAlways; add(screenshot)
            do {
                try audit("Koyu-\(name)")
            } catch {
                XCTFail("Koyu görünüm denetimi: \(name): \(error)")
            }
        }
    }

    /// İlk AX5 ekranının altında kalan yönetim satırları ayrıca doğrulanır.
    func testKoyuBuyukYazidaYonetimAsistanMetinleri() throws {
        app.terminate()
        launchPreference("-appearanceMode", "dark")
        launchPreference("-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL")
        app.launch()
        tab("Yönetim")
        let assistant = app.buttons["management.assistant"]
        // Yalnız dokunulabilir olana kadar kaydırmak satırın altını çubuğun arkasında bırakıyordu;
        // satır tümüyle (uzunsa üstü hizalanarak) görünür alana getirilir.
        let gorunum = GorunurAlan.satiriGoster(assistant, in: app, etiket: "ASSISTANT")
        XCTAssertNotEqual(gorunum, .getirilemedi, "Asistan satırı görünür alana getirilmeli")
        XCTAssertTrue(assistant.exists, "Asistan satırı büyük yazıda bulunmalı")
        XCTAssertTrue(assistant.isHittable, "Asistan satırına büyük yazıda kaydırarak erişilmeli")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Koyu-AX5-Yonetim-Asistan"; screenshot.lifetime = .keepAlways; add(screenshot)
        try app.performAccessibilityAudit(for: [.dynamicType, .textClipped]) { issue in
            self.recordAudit(issue, page: "Koyu-AX5-Yonetim-Asistan")
            return false
        }
    }
}
