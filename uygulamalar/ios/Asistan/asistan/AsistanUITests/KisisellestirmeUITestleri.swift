import XCTest

@MainActor final class KisisellestirmeUITestleri: XCTestCase {
    var app: XCUIApplication!
    /// Arıza modu testi anahtarları açtığında true olur: anahtarlar UserDefaults'ta 30 dk yaşar, simülatörde kalıcı arıza kalmamalı.
    var arizaTemizlenecek = false
    override func tearDown() async throws {
        await MainActor.run {
            guard arizaTemizlenecek, let app else { return }
            let kapat = app.buttons["ariza-hepsini-kapat"]
            for _ in 0..<4 where !kapat.exists { app.swipeUp() }
            if kapat.exists, kapat.isEnabled { kapat.tap() }
        }
    }
    override func setUp() async throws {
        await MainActor.run {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--asistan-ui-onizleme", "--sohbet", "--rahat"]
        app.launch()
        }
    }
    func testIndirmeEkrani() {
        app.aracAc("İndirmeler")
        XCTAssertTrue(app.navigationBars["İndirmeler"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["indirme-adres"].exists)
        XCTAssertFalse(app.buttons["indirme-baslat"].isEnabled)
        XCTAssertFalse(app.buttons["web-kazima-ac"].isEnabled)
        app.textFields["indirme-adres"].tap()
        app.textFields["indirme-adres"].typeText("https://example.com")
        XCTAssertTrue(app.buttons["web-kazima-ac"].isEnabled)
        app.buttons["web-kazima-ac"].tap()
        XCTAssertTrue(app.navigationBars["Web verisi çıkar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Sayfayı tara"].exists)
        let hazir = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Sayfa hazır")).firstMatch
        XCTAssertTrue(hazir.waitForExistence(timeout: 10))
        app.buttons["Sayfayı tara"].tap()
        let cikti = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "öğe çıkarıldı")).firstMatch
        XCTAssertTrue(cikti.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["JSON"].exists)
        XCTAssertTrue(app.buttons["CSV"].exists)
        let kazimaShot = XCTAttachment(screenshot: app.screenshot())
        kazimaShot.name = "web-verisi-cikarma"
        kazimaShot.lifetime = .keepAlways
        add(kazimaShot)
        app.buttons["Kapat"].tap()
        app.buttons["Ses"].tap()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        app.buttons["Tamam"].tap()
        XCTAssertTrue(app.buttons["menu-dugmesi"].exists)
    }
    func testGorunumDegistirmeVeGeriAlma() {
        app.aracAc("Görünümü düzenle")
        XCTAssertTrue(app.navigationBars["Görünüm stüdyosu"].waitForExistence(timeout: 5))
        // P1.6: tek hazır görünüm seti sohbet temalarıdır (üstte, yatay şerit).
        let gece = app.buttons["sohbet-tema-Gece"]
        XCTAssertTrue(gece.waitForExistence(timeout: 5))
        for _ in 0..<3 where !gece.isHittable { app.buttons["sohbet-tema-Telegram"].swipeLeft() }
        gece.tap()
        XCTAssertTrue(kosulBekle(timeout: 3) { gece.isSelected }, "Gece teması seçilmeli")
        // Varsayılana dönüş, geri alınabilir bir değişikliktir (geri al düğmesi profil bölümünde).
        let varsayilan = app.buttons["Varsayılan görünüme dön (Karma)"]
        for _ in 0..<12 where !(varsayilan.exists && varsayilan.isHittable) { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(varsayilan.exists)
        varsayilan.tap()
        let geriAl = app.buttons["Son görünüm değişikliğini geri al"]
        for _ in 0..<3 where !(geriAl.exists && geriAl.isHittable) { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(geriAl.exists)
        geriAl.tap()
        XCTAssertFalse(geriAl.exists, "geri alındıktan sonra düğme kalkar")
        // Kaldırılan bölümler: eski hazır görünümler ve "Ana ekran" anahtarları (form sonuna kadar kaydırıldı).
        XCTAssertFalse(app.staticTexts["Ana ekran"].exists)
        XCTAssertFalse(app.buttons["Gece görünümünü uygula"].exists)
        XCTAssertFalse(app.buttons["Son hazır görünüm değişikliğini geri al"].exists)
        // Geri alma Gece temasını geri getirdi.
        for _ in 0..<12 where !(gece.exists && gece.isHittable) { app.collectionViews.firstMatch.swipeDown() }
        XCTAssertTrue(kosulBekle(timeout: 3) { gece.isSelected }, "geri alma Gece temasını geri getirmeli")
        app.buttons["Tamam"].tap()
        XCTAssertTrue(app.buttons["menu-dugmesi"].waitForExistence(timeout: 3))
    }
    func testHizliKomutSeridiYokVeBosEkranBos() {
        // Sade tasarım: kısayol satırı kaldırıldı.
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Günümü planla")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Evet, duyuyorum."].exists)
    }
    func testSohbetAramaVeKaydetme() {
        // İkon satırı yok: kaydetme uzun basma menüsünde; alt satırda yalnız model adı.
        XCTAssertFalse(app.buttons["yanit-kaydet"].exists, "ikon satırı gizli olmalı")
        XCTAssertTrue(app.buttons["yeniden-uret"].firstMatch.waitForExistence(timeout: 3), "model adı (model değiştirme) görünmeli")
        app.staticTexts["Evet, duyuyorum."].press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Kaydet"].waitForExistence(timeout: 3), "uzun basma menüsü"); app.buttons["Kaydet"].tap()
        app.staticTexts["Evet, duyuyorum."].press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Kaydedildi"].waitForExistence(timeout: 3), "kaydedilince menüde Kaydedildi")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        app.buttons["Sohbet menüsü"].tap(); app.buttons["Sohbette ara"].tap()
        app.textFields["Bu sohbette ara"].tap(); app.textFields["Bu sohbette ara"].typeText("duyuyorum")
        // Arama listeyi süzmez: eşleşme sayacı ve önceki/sonraki gezinme düğmeleri görünür.
        let sayac = app.staticTexts["arama-sayaci"]
        XCTAssertTrue(sayac.waitForExistence(timeout: 3), "arama sayacı görünmeli")
        XCTAssertEqual(sayac.label, "1/1")
        XCTAssertTrue(app.buttons["arama-onceki"].exists, "önceki eşleşme düğmesi")
        XCTAssertTrue(app.buttons["arama-sonraki"].exists, "sonraki eşleşme düğmesi")
        XCTAssertTrue(app.staticTexts["Evet, duyuyorum."].exists)
    }
    func testKendiKomutunuOlusturVeTaslakAc() {
        app.aracAc("Kişisel alanım")
        app.buttons["Komut ekle"].tap()
        app.textFields["Başlık"].tap(); app.textFields["Başlık"].typeText("Deneme komutum")
        app.textViews["Komut metni"].tap(); app.textViews["Komut metni"].typeText("Bu benim ozel komutum.")
        app.buttons["Kaydet"].tap()
        let search = app.searchFields.firstMatch
        if !search.isHittable { app.swipeDown() }
        search.tap(); search.typeText("Deneme komutum")
        app.buttons["Taslağa ekle"].tap()
        let alan = app.descendants(matching: .any).matching(identifier: "mesaj-girisi").firstMatch
        XCTAssertTrue(alan.waitForExistence(timeout: 3))
        // iOS 27 simülatörü çok satırlı TextField'ın erişilebilirlik `value`
        // alanını boş döndürebiliyor. Gönder düğmesi yalnız taslak gerçekten
        // doluysa oluşturulduğu için kullanıcıya görünen sonucu doğrular.
        XCTAssertTrue(app.buttons["Gönder"].waitForExistence(timeout: 3))
    }

    func testUygulamaKataloguAramaVeEklemeDosyasi() {
        app.aracAc("Telefon işlemleri")
        app.buttons["Telefondaki uygulamalar"].tap()
        XCTAssertTrue(app.navigationBars["Telefondaki uygulamalar"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("Telegram")
        XCTAssertTrue((search.value as? String ?? "").localizedCaseInsensitiveContains("Telegram"))
        app.buttons["Tüm uygulamalar için köprüyü ekle"].tap()
        XCTAssertTrue(app.buttons["uygulama-koprusu-paylas"].waitForExistence(timeout: 5))
    }

    func testSesModlariMenudeMikrofonGirdiCubugunda() {
        // Tam ekran akan sohbet: üstte mod seçici, ortada küre ve ipucu metni yok.
        XCTAssertFalse(app.segmentedControls["ses-modu"].exists)
        XCTAssertFalse(app.staticTexts["Söz almak için yuvarlağa dokun"].exists)
        XCTAssertFalse(app.staticTexts["Konuşmak için yuvarlağa dokun"].exists)
        XCTAssertTrue(app.buttons["ses-yuvarlagi"].exists)
        XCTAssertEqual(app.buttons["ses-yuvarlagi"].label, "Konuşmaya başla")
        XCTAssertTrue(app.buttons["menu-dugmesi"].exists); XCTAssertTrue(app.buttons["sohbet-menusu"].exists)
        app.cekmeceAc()
        XCTAssertTrue(app.segmentedControls["ses-modu"].waitForExistence(timeout: 3), "konuşma modu çekmecede")
        XCTAssertTrue(app.buttons["Normal"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Eller serbest"].exists)
        XCTAssertTrue(app.buttons["Live"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "mod-menusu"; shot.lifetime = .keepAlways; add(shot)
    }


    func testCekmeceYapisi() {
        app.cekmeceAc()
        XCTAssertTrue(app.buttons["cekmece-yeni"].exists, "Yeni sohbet")
        XCTAssertTrue(app.textFields["cekmece-ara"].exists, "arama kutusu")
        XCTAssertTrue(app.buttons["cekmece-kota"].exists, "kota/kullanım satırı")
        XCTAssertTrue(app.buttons["cekmece-ayarlar"].exists, "profil/ayarlar")
        XCTAssertTrue(app.segmentedControls["ses-modu"].exists, "ses modu şeridi")
        app.buttons["cekmece-araclar"].tap()
        XCTAssertTrue(app.buttons["İndirmeler"].waitForExistence(timeout: 3), "Araçlar menüsü öğeleri göstermeli")
        app.buttons["İndirmeler"].tap()
        XCTAssertTrue(app.navigationBars["İndirmeler"].waitForExistence(timeout: 5))
        app.navigationBars["İndirmeler"].swipeDown(velocity: .fast)   // sayfayı kapat; çekmece seçimle zaten kapandı
        XCTAssertTrue(app.buttons["menu-dugmesi"].waitForExistence(timeout: 5))
        app.cekmeceAc()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "cekmece"; shot.lifetime = .keepAlways; add(shot)
        app.cekmeceKapat()
        XCTAssertTrue(app.buttons["menu-dugmesi"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["cekmece-ayarlar"].isHittable, "kapanınca çekmece erişilemez olmalı")
        // Soldan kenar kaydırma ile aç.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
        XCTAssertTrue(app.buttons["cekmece-ayarlar"].waitForExistence(timeout: 3), "kenar kaydırma çekmeceyi açmalı")
    }

    /// Gerçek sohbet kaydedilir; yeni sohbette ekran boşalır; çekmeceden eski sohbet yeniden açılır.
    func testSohbetCekmecedenYenidenAcilir() {
        // P3.10: hermetik (sahte model "Sahte yanıt." verir); çekmece arama/kaydetme aynı süreçteki bellek içi depoda sınanır.
        let app2 = XCUIApplication.hermetik()
        app2.launch()
        let alan = app2.descendants(matching: .any).matching(identifier: "mesaj-girisi").firstMatch
        XCTAssertTrue(alan.waitForExistence(timeout: 10))
        let ozgun = "Merhaba cekmece\(Int.random(in: 100...999))"
        alan.tap(); alan.typeText(ozgun); app2.buttons["Gönder"].tap()
        XCTAssertTrue(app2.staticTexts[ozgun].waitForExistence(timeout: 10))
        XCTAssertTrue(app2.descendants(matching: .any)["yanit-tamam"].waitForExistence(timeout: 10), "yanıt tamamlanmalı")
        app2.cekmeceAc(); app2.buttons["cekmece-yeni"].tap()
        XCTAssertFalse(app2.staticTexts[ozgun].waitForExistence(timeout: 2), "yeni sohbet boş olmalı")
        app2.cekmeceAc()
        let ara = app2.textFields["cekmece-ara"]; ara.tap(); ara.typeText(ozgun)
        let satir = app2.buttons.matching(identifier: "cekmece-sohbet").firstMatch
        XCTAssertTrue(satir.waitForExistence(timeout: 5), "kaydedilen sohbet çekmecede aranınca bulunmalı")
        satir.tap()
        XCTAssertTrue(app2.staticTexts[ozgun].waitForExistence(timeout: 5), "eski sohbet yeniden açılmalı")
    }

    /// "+" ek sayfası: büyük eylemler ve dosya işleri; kapat düğmesi.
    func testEkSayfasi() {
        app.buttons["Dosya veya fotoğraf ekle"].tap()
        XCTAssertTrue(app.navigationBars["Ekle"].waitForExistence(timeout: 4), "ek sayfası açılmalı")
        for ad in ["Fotoğraf çek", "Fotoğraf seç", "Ofis, PDF, metin veya kod ekle", "Ürün barkodu okut", "Bağlantı indir", "ZIP oluştur veya RAR aç"] {
            XCTAssertTrue(app.buttons[ad].exists, "\(ad) yok")
        }
        app.buttons["Bağlantı indir"].tap()
        XCTAssertTrue(app.navigationBars["İndirmeler"].waitForExistence(timeout: 6), "seçim sayfa kapanınca açılmalı")
    }

    /// Önizleme şeridi: iki ek görünür; dokununca düzenleyici açılır, kırpılır; çarpı ile kaldırılır.
    func testEkSeridiVeDuzenleyici() {
        app.terminate(); app.launchArguments = ["--ek-ornek"]; app.launch()
        let onizleme = app.buttons.matching(identifier: "ek-onizleme")
        XCTAssertTrue(onizleme.firstMatch.waitForExistence(timeout: 6))
        XCTAssertEqual(onizleme.count, 2)
        XCTAssertTrue(app.staticTexts["2 görsel eklendi · düzenlemek için dokun"].exists)
        XCTAssertFalse(app.buttons["ses-yuvarlagi"].exists, "ek varken gönder düğmesi görünmeli")
        onizleme.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Düzenle"].waitForExistence(timeout: 5), "düzenleyici açılmalı")
        let kose = app.otherElements.matching(NSPredicate(format: "label == %@", "Kırpma köşesi")).firstMatch
        if kose.exists { kose.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))) }
        app.buttons["Döndür"].tap()
        app.segmentedControls["duzenle-kip"].buttons["Çiz"].tap()
        XCTAssertTrue(app.otherElements["cizim-tuvali"].waitForExistence(timeout: 3) || app.scrollViews["cizim-tuvali"].exists, "çizim tuvali")
        app.buttons["duzenle-bitti"].tap()
        XCTAssertTrue(onizleme.firstMatch.waitForExistence(timeout: 5))
        app.buttons.matching(identifier: "ek-kaldir").firstMatch.tap()
        // İlk (fotoğraf) ek kaldırıldı; örnekteki ikinci ek taranmış sayfadır.
        XCTAssertTrue(app.staticTexts["Sayfa eklendi"].waitForExistence(timeout: 3), "bir ek kalmalı\n\(app.debugDescription)")
        app.buttons.matching(identifier: "ek-kaldir").firstMatch.tap()
        XCTAssertTrue(app.buttons["ses-yuvarlagi"].waitForExistence(timeout: 3), "ekler bitince mikrofon döner")
    }

    /// Live seçilince tam ekran konuşma görünümü açılır; tek "Bitir" düğmesi normal moda döndürür.
    func testCanliTamEkran() {
        app.menudenSec("sohbet-menusu", secenek: "Live sesli diyalog")
        XCTAssertTrue(app.buttons["canli-bitir"].waitForExistence(timeout: 8), "Live tam ekranı açılmalı")
        XCTAssertTrue(app.buttons["canli-kure"].exists, "büyük küre")
        XCTAssertTrue(app.staticTexts["canli-durum"].exists, "durum satırı")
        XCTAssertTrue(app.staticTexts["canli-ipucu"].exists, "duruma uygun dokunma açıklaması")
        XCTAssertTrue(app.buttons["canli-kure"].isHittable, "küre ekrana sığmalı")
        XCTAssertTrue(app.buttons["canli-bitir"].isHittable, "çıkış düğmesi görünür kalmalı")
        let altyazi = app.buttons["canli-altyazi"]
        XCTAssertEqual(altyazi.label, "Altyazıyı gizle")
        altyazi.tap()
        XCTAssertEqual(altyazi.label, "Altyazıyı göster")
        altyazi.tap()
        XCTAssertEqual(altyazi.label, "Altyazıyı gizle")
        app.buttons["canli-ses-sec"].tap()
        XCTAssertTrue(app.navigationBars["Live sesi"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["canli-ses-azure:Elif"].exists)
        let kore = app.buttons["canli-ses-claude:Kore"]
        XCTAssertTrue(kore.exists)
        XCTAssertTrue(kosulBekle(timeout: 20) { kore.isEnabled }, "boş turda ses seçilebilir olmalı")
        kore.tap()
        XCTAssertTrue(kosulBekle(timeout: 5) { !app.navigationBars["Live sesi"].exists })
        XCTAssertTrue(app.buttons["canli-ses-sec"].exists)
        XCTAssertFalse(app.textFields["mesaj-girisi"].isHittable, "Live sırasında yazı alanı arkada kalmalı")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "canli-ekran"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["canli-bitir"].tap()
        XCTAssertTrue(app.buttons["ses-yuvarlagi"].waitForExistence(timeout: 8), "Bitir sohbete dönmeli")
        XCTAssertFalse(app.buttons["canli-bitir"].exists)
        // Çekmecedeki mod şeridinden de açılır ve mod Normal'e dönmüş olmalı.
        app.cekmeceAc()
        XCTAssertTrue(app.buttons["Normal"].isSelected, "Bitir sonrası mod Normal")
        app.buttons["Live"].tap()
        XCTAssertTrue(app.buttons["canli-bitir"].waitForExistence(timeout: 8), "şeritten Live açılmalı")
        app.buttons["canli-bitir"].tap()
        XCTAssertFalse(app.buttons["canli-bitir"].waitForExistence(timeout: 3))
    }

    /// Görünüm stüdyosundan sohbet teması değişir: Telegram'da başlık hapı ve ayrık giriş, Claude'da model hapı.
    func testSohbetTemasiAyarlardanDegisir() {
        XCTAssertTrue(app.buttons["model-hapi"].waitForExistence(timeout: 5), "Claude teması: tek kutu giriş + model hapı")
        XCTAssertFalse(app.otherElements["baslik-hapi"].exists)
        app.aracAc("Görünümü düzenle")
        let telegram = app.buttons["sohbet-tema-Telegram"]
        XCTAssertTrue(telegram.waitForExistence(timeout: 5)); telegram.tap()
        XCTAssertTrue(app.staticTexts["Sohbet renkleri"].exists || app.buttons["Düzenlenen"].exists || app.segmentedControls["palet-secimi"].exists)
        app.buttons["Tamam"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["baslik-hapi"].waitForExistence(timeout: 5), "Telegram teması: başlık hapı")
        XCTAssertFalse(app.buttons["model-hapi"].exists, "ayrık girişte model hapı yok")
        app.aracAc("Görünümü düzenle")
        app.buttons["sohbet-tema-Claude"].tap(); app.buttons["Tamam"].tap()
        XCTAssertTrue(app.buttons["model-hapi"].waitForExistence(timeout: 5), "Claude'a geri dönüldü")
    }

    /// Ajan merkezi: bütçeler, davranış anahtarları ve araç izinleri görünür; izin değiştirilebilir.
    func testAjanMerkezi() {
        app.aracAc("Ajan merkezi")
        XCTAssertTrue(app.navigationBars["Ajan merkezi"].waitForExistence(timeout: 5))
        let butce = app.descendants(matching: .any)["adim-butcesi"]
        for _ in 0..<6 where !butce.exists { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(butce.exists, "adım bütçesi")
        let elestirmen = app.descendants(matching: .any)["elestirmen"]
        for _ in 0..<6 where !elestirmen.exists { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(elestirmen.exists, "eleştirmen anahtarı")
        let izin = app.descendants(matching: .any)["izin-takvim"]
        for _ in 0..<10 where !(izin.exists && izin.isHittable) { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(izin.exists, "takvim izin satırı")
        app.buttons["Tamam"].tap()
        XCTAssertTrue(app.buttons["menu-dugmesi"].waitForExistence(timeout: 3))
    }

    /// Tetikleyici oluşturma ve proje ekleme ekranları çalışır.
    func testTetikleyiciVeProje() {
        app.aracAc("Tetikleyiciler")
        XCTAssertTrue(app.navigationBars["Tetikleyiciler"].waitForExistence(timeout: 5))
        app.buttons["Sabah özeti"].tap()
        XCTAssertTrue(app.buttons["tetik-kaydet"].waitForExistence(timeout: 4))
        app.buttons["tetik-kaydet"].tap()
        XCTAssertTrue(app.buttons.matching(identifier: "tetik-satiri").firstMatch.waitForExistence(timeout: 4), "tetik listeye eklenmeli")
        app.buttons.matching(identifier: "tetik-satiri").firstMatch.swipeLeft(); app.buttons["Sil"].tap()
        app.buttons["Kapat"].tap()
        app.aracAc("Projeler")
        XCTAssertTrue(app.navigationBars["Projeler"].waitForExistence(timeout: 5))
        app.buttons["proje-yeni"].tap()
        let alan = app.alerts.textFields.firstMatch
        XCTAssertTrue(alan.waitForExistence(timeout: 3)); alan.typeText("UITEST Proje")
        app.alerts.buttons["Ekle"].tap()
        XCTAssertTrue(app.buttons.matching(identifier: "proje-satiri").firstMatch.waitForExistence(timeout: 3))
        app.buttons["Kapat"].tap()
        XCTAssertTrue(app.buttons["proje-cipi"].waitForExistence(timeout: 4), "etkin proje çipi yazma alanının üstünde")
        app.buttons["Projeyi kaldır"].tap()
        XCTAssertFalse(app.buttons["proje-cipi"].waitForExistence(timeout: 2))
        app.aracAc("Projeler")
        app.buttons.matching(identifier: "proje-satiri").firstMatch.swipeLeft(); app.buttons["Sil"].tap()
        app.buttons["Kapat"].tap()
    }

    /// Live: kamera düğmesi görünür (simülatörde kamera yok; açılmaması çökme değildir).
    func testCanliKameraDugmesi() {
        app.menudenSec("sohbet-menusu", secenek: "Live sesli diyalog")
        XCTAssertTrue(app.buttons["canli-kamera"].waitForExistence(timeout: 8))
        app.buttons["canli-kamera"].tap()
        XCTAssertTrue(app.buttons["canli-bitir"].exists, "kamera denemesinden sonra ekran yerinde")
        app.buttons["canli-bitir"].tap()
        XCTAssertTrue(app.buttons["ses-yuvarlagi"].waitForExistence(timeout: 8))
    }

    /// Önizleme kartları: tablo (tam ekran), dosya (Hızlı Bakış), kaynaklar gizli.
    func testOnizlemeKartlari() {
        app.terminate(); app.launchArguments = ["--asistan-ui-onizleme", "--ek-kartlari"]; app.launch()
        let tablo = app.descendants(matching: .any)["tablo-karti"]
        XCTAssertTrue(tablo.waitForExistence(timeout: 8), "tablo kartı")
        app.buttons["tablo-tumu"].tap()
        XCTAssertTrue(app.navigationBars["Fiyatlar"].waitForExistence(timeout: 5), "tam ekran tablo")
        XCTAssertTrue(app.staticTexts["Kiraz"].exists)
        app.buttons["Kapat"].tap()
        XCTAssertFalse(app.buttons["kaynaklar-dugmesi"].exists, "kaynak kartı gizli olmalı")
        XCTAssertFalse(app.buttons.matching(identifier: "kaynak-satiri").firstMatch.exists)
        app.buttons.matching(identifier: "ek-onizle").firstMatch.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 6), "Hızlı Bakış önizlemesi")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "onizleme"; shot.lifetime = .keepAlways; add(shot)
        let kapat = app.buttons.matching(NSPredicate(format: "label IN %@ OR identifier IN %@", ["Bitti", "Done", "Kapat", "Close", "Kapat düğmesi"], ["QLOverlayDoneButtonAccessibilityIdentifier"])).firstMatch
        if kapat.waitForExistence(timeout: 2) { kapat.tap() } else { app.swipeDown(velocity: .fast) }
        _ = app.descendants(matching: .any)["tablo-karti"].waitForExistence(timeout: 4)
        // Medya kartı: belge geçici indirilip Hızlı Bakış'ta önizlenir.
        let medya = app.descendants(matching: .any)["medya-karti"]
        for _ in 0..<4 where !(medya.exists && medya.isHittable) { app.swipeUp() }
        XCTAssertTrue(medya.exists, "medya kartı")
        XCTAssertTrue(app.buttons.matching(identifier: "medya-oynat").firstMatch.exists, "video/ses oynat düğmesi")
        app.buttons["belge-onizle"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 20), "uzak PDF önizlemesi")
    }

    /// Uçtan uca (gerçek model + ağ): asistan tabloyu kazır, mesajda tablo kartı gösterir.
    func testAsistanTabloKaziyipKartGosterir() throws {
        try canliKapisi()   // P3.10: Wikipedia + gerçek model; Canlı planda
        let app2 = XCUIApplication(); app2.launchEnvironment = ["ASISTAN_TEST": "1"]; app2.launchArguments = ["--sohbet-gercek"]; app2.launch()
        let alan = app2.descendants(matching: .any).matching(identifier: "mesaj-girisi").firstMatch
        XCTAssertTrue(alan.waitForExistence(timeout: 10))
        alan.tap(); alan.typeText("https://en.wikipedia.org/wiki/List_of_largest_cities sayfasındaki şehir tablosunu çıkar.")
        app2.buttons["Gönder"].tap()
        XCTAssertTrue(app2.descendants(matching: .any)["tablo-karti"].waitForExistence(timeout: 150), "tablo kartı gelmedi\n\(app2.debugDescription)")
        let shot = XCTAttachment(screenshot: app2.screenshot()); shot.name = "e2e-tablo"; shot.lifetime = .keepAlways; add(shot)
    }

    /// Şarkı "indir" isteği (20 Eki 2026 kararı): ret ya da Apple Music yerine indirme yoluna gider;
    /// net aday varsa indirme kartı gelir, belirsizse asistan hangisini indireceğini sorar. Telif reddi olmamalı.
    func testTelifliSarkiIstegiYasalYolaGider() throws {
        try canliKapisi()   // P3.10: gerçek model + YouTube araması; Canlı planda
        let app2 = XCUIApplication(); app2.launchEnvironment = ["ASISTAN_TEST": "1"]; app2.launchArguments = ["--sohbet-gercek"]; app2.launch()
        let alan = app2.descendants(matching: .any).matching(identifier: "mesaj-girisi").firstMatch
        XCTAssertTrue(alan.waitForExistence(timeout: 10))
        alan.tap(); alan.typeText("Dua lipa şarkısını indir en çok dinlenen")
        app2.buttons["Gönder"].tap()
        XCTAssertTrue(app2.descendants(matching: .any)["yanit-tamam"].waitForExistence(timeout: 150), "yanıt tamamlanmalı\n\(app2.debugDescription)")
        let kart = app2.descendants(matching: .any)["indirme-karti"].exists || app2.descendants(matching: .any)["dosya-karti"].exists
        let soru = app2.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "indir")).count > 1
        XCTAssertTrue(kart || soru, "indirme kartı ya da hangisinin indirileceği sorusu gelmeli\n\(app2.debugDescription)")
        XCTAssertFalse(app2.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "telif")).firstMatch.exists, "telif reddi olmamalı")
        let shot = XCTAttachment(screenshot: app2.screenshot()); shot.name = "telifli-sarki"; shot.lifetime = .keepAlways; add(shot)
    }

    /// İETT hızlı yolu: tablo kartları + PDF dosya kartı; plan/işlem satırı üst çubuğun altına girmez.
    func testIettSeferleriVePdf() throws {
        try canliKapisi()   // P3.10: İETT sitesine bağlı; sahtelenmez, Canlı planda
        let app2 = XCUIApplication(); app2.launchEnvironment = ["ASISTAN_TEST": "1"]; app2.launchArguments = ["--sohbet-gercek"]; app2.launch()
        let alan = app2.descendants(matching: .any).matching(identifier: "mesaj-girisi").firstMatch
        XCTAssertTrue(alan.waitForExistence(timeout: 10))
        alan.tap(); alan.typeText("11r 138 9h 138b bu iett seferleri bul indir PDF çevir ver")
        app2.buttons["Gönder"].tap()
        XCTAssertTrue(app2.descendants(matching: .any)["dosya-karti"].waitForExistence(timeout: 60), "PDF dosya kartı gelmedi\n\(app2.debugDescription)")
        XCTAssertTrue(app2.descendants(matching: .any).matching(identifier: "tablo-karti").count >= 1, "tablo kartı")
        XCTAssertFalse(app2.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "&#")).firstMatch.exists, "HTML varlığı çözülmeli")
        let shot = XCTAttachment(screenshot: app2.screenshot()); shot.name = "iett"; shot.lifetime = .keepAlways; add(shot)
    }

    /// İETT devam isteği ("PDF renkli tekrar yap"): kod yazılmaz, yeni PDF dosya kartı gelir; denetim notu çıkmaz.
    func testIettDevamIstegiYeniPdfVerir() throws {
        try canliKapisi()   // P3.10: İETT sitesine bağlı; sahtelenmez, Canlı planda
        let app2 = XCUIApplication(); app2.launchEnvironment = ["ASISTAN_TEST": "1"]; app2.launchArguments = ["--sohbet-gercek"]; app2.launch()
        let alan = app2.descendants(matching: .any).matching(identifier: "mesaj-girisi").firstMatch
        XCTAssertTrue(alan.waitForExistence(timeout: 10))
        alan.tap(); alan.typeText("11r 138 bu iett seferleri bul PDF ver"); app2.buttons["Gönder"].tap()
        XCTAssertTrue(app2.descendants(matching: .any)["dosya-karti"].waitForExistence(timeout: 60), "ilk PDF")
        let ikinciIstek = "PDF renkli ve daha düzgün tablolu olsun tekrar yap ver"
        alan.tap(); alan.typeText(ikinciIstek); app2.buttons["Gönder"].tap()
        // İkinci yanıt ilkiyle aynı görünür (aynı tablolar, aynı PDF adı) ve ekrandan uzundur: alt uca kayınca
        // ikinci istek balonu yukarıda kalıp LazyVStack ağacından çıkar. Bu yüzden önce balonun göründüğü,
        // sonra balonun altında ya da balon kaydırılıp gittikten sonra yeni bir dosya kartı geldiği doğrulanır.
        let balon = app2.staticTexts[ikinciIstek]
        // Yanıt çok hızlı gelebilir: balonu sık yokla (waitForExistence ilk anı kaçırabiliyor). Bilinçli istisna: kosulBekle 0,1 sn.
        let balonGoruldu = kosulBekle(timeout: 10, aralik: 0.1) { balon.exists }
        XCTAssertTrue(balonGoruldu, "ikinci istek balonu görünmedi (mesaj kayboldu)")
        let kartlar = app2.descendants(matching: .any).matching(identifier: "dosya-karti")
        func yeniKartVar() -> Bool {
            guard app2.descendants(matching: .any)["yanit-tamam"].firstMatch.exists, app2.buttons["Gönder"].exists || app2.buttons["ses-yuvarlagi"].exists else { return false }
            if !balon.exists { return kartlar.allElementsBoundByIndex.contains { $0.exists && $0.isHittable } }
            let ust = balon.frame.maxY
            return kartlar.allElementsBoundByIndex.contains { $0.exists && $0.frame.minY > ust && $0.isHittable }
        }
        kosulBekle(timeout: 60, aralik: 0.5) { yeniKartVar() }
        XCTAssertTrue(yeniKartVar(), "ikinci PDF dosya kartı ikinci istekten sonra görünmedi\n\(app2.debugDescription)")
        XCTAssertFalse(app2.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "reportlab")).firstMatch.exists, "kod yazılmamalı")
        XCTAssertFalse(app2.descendants(matching: .any)["kontrol-notu"].exists, "hızlı yolda denetim notu olmamalı")
    }

    /// Mesajlar arası bağlam: ikinci mesaj ilkine atıf yapar, Durdur'dan sonra da bağlam sürer.
    /// Gerçek model; hermetik eşi SahteModelUITestleri.testSahteBaglamSurer.
    func testMesajlarArasiBaglamSurer() throws {
        try canliKapisi()
        let app2 = XCUIApplication(); app2.launchEnvironment = ["ASISTAN_TEST": "1"]; app2.launchArguments = ["--sohbet-gercek"]; app2.launch()
        let alan = app2.descendants(matching: .any).matching(identifier: "mesaj-girisi").firstMatch
        XCTAssertTrue(alan.waitForExistence(timeout: 10))
        alan.tap(); alan.typeText("Benim kedimin adı Pamuk ve 3 yaşında."); app2.buttons["Gönder"].tap()
        XCTAssertTrue(app2.descendants(matching: .any).matching(identifier: "yanit-tamam").firstMatch.waitForExistence(timeout: 60), "ilk yanıt")
        alan.tap(); alan.typeText("Peki kaç yaşındaydı?"); app2.buttons["Gönder"].tap()
        let ikinci = app2.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@ AND label CONTAINS[c] %@", "Pamuk", "3")).firstMatch
        XCTAssertTrue(ikinci.waitForExistence(timeout: 60), "ikinci yanıt önceki mesajı bilmeli\n\(app2.debugDescription)")
        // Durdur sonrası: yeni istek sırasında Durdur'a basılır, üçüncü mesaj yine bağlamı bilmeli.
        alan.tap(); alan.typeText("Bana uzun bir hikaye anlat"); app2.buttons["Gönder"].tap()
        if app2.buttons["Sesli oturumu ve yanıtı durdur"].waitForExistence(timeout: 5) { app2.buttons["Sesli oturumu ve yanıtı durdur"].tap() }
        alan.tap(); alan.typeText("Kedimin adı neydi?"); app2.buttons["Gönder"].tap()
        let ucuncu = app2.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@ AND NOT label CONTAINS[c] %@", "Pamuk", "kaç yaş")).element(boundBy: 2)
        XCTAssertTrue(ucuncu.waitForExistence(timeout: 60), "Durdur sonrası bağlam kaybolmamalı\n\(app2.debugDescription)")
    }

    /// Denetim verisi bulunan yanıtta not ve düzeltme düğmesi gizli kalır.
    func testDuzeltilmisYanitDugmesi() {
        app.terminate(); app.launchArguments = ["--asistan-ui-onizleme", "--zengin"]; app.launch()
        // Denetim notlu örnek yanıt yüklendi; not ve düzeltilmiş yanıt düğmesi sohbeti kalabalıklaştırmaz.
        let ornek = app.descendants(matching: .any).containing(NSPredicate(format: "label CONTAINS %@", "Ekvator")).firstMatch
        XCTAssertTrue(ornek.waitForExistence(timeout: 10), "denetim notlu örnek yanıt")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "kontrol-notu").firstMatch.exists)
        XCTAssertFalse(app.buttons["duzeltilmis-yanit"].exists)
    }

    /// P3.10-arıza (yalnız DEBUG): Ayarlar → Geliştirici → Arıza modu; 429 anahtarı açılıp kapanır, sınama kayıtları tablosu vardır.
    func testArizaModuAnahtariVeSinamaKayitlari() {
        app.ayarlariAc()
        XCTAssertTrue(app.navigationBars["Ayarlar"].waitForExistence(timeout: 5), "Ayarlar açılmadı")
        let giris = app.buttons["gelistirici-ariza-modu"]
        for _ in 0..<12 where !(giris.exists && giris.isHittable) { app.swipeUp() }
        XCTAssertTrue(giris.exists, "Geliştirici bölümü (Debug) yok")
        giris.tap()
        XCTAssertTrue(app.navigationBars["Arıza modu"].waitForExistence(timeout: 5))
        let anahtar = app.switches["ariza-modelKota429"]
        arizaTemizlenecek = true   // test hangi adımda düşerse düşsün tearDown anahtarları kapatır
        XCTAssertTrue(anahtar.waitForExistence(timeout: 5), "429 anahtarı")
        if anahtar.value as? String == "1" { anahtar.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        XCTAssertEqual(anahtar.value as? String, "0", "başlangıçta kapalı")
        anahtar.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(kosulBekle(timeout: 3) { anahtar.value as? String == "1" }, "anahtar açılmalı")
        anahtar.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(kosulBekle(timeout: 3) { anahtar.value as? String == "0" }, "anahtar kapanmalı")
        let hepsi = app.buttons["ariza-hepsini-kapat"]
        if hepsi.exists, hepsi.isEnabled { hepsi.tap() }
        let kayitlar = app.descendants(matching: .any)["sinama-kayitlari"]
        for _ in 0..<8 where !kayitlar.exists { app.swipeUp() }
        XCTAssertTrue(kayitlar.exists, "sınama kayıtları tablosu")
    }

    /// P3.3: bitmiş asistan yanıtının altında beğen/beğenme; beğenme neden sorar, seçince diyalog kapanır ve simge seçili olur.
    /// Önizleme (--zengin) yanıtlarında `sure` dolu olduğundan düğmeler görünür; kayıt testte geçici kalite dosyasına yazılır.
    func testBegenmeNedenSorar() {
        app.terminate(); app.launchArguments = ["--asistan-ui-onizleme", "--zengin"]; app.launch()
        let begen = app.buttons["begen"].firstMatch
        let begenme = app.buttons["begenme"].firstMatch
        XCTAssertTrue(begenme.waitForExistence(timeout: 10), "beğenme düğmesi\n\(app.debugDescription)")
        XCTAssertTrue(begen.exists, "beğen düğmesi")
        if !begenme.isHittable { app.swipeDown() }
        begenme.tap()
        let neden = app.buttons["Yanlış bilgi"]
        XCTAssertTrue(neden.waitForExistence(timeout: 5), "neden diyaloğu\n\(app.debugDescription)")
        XCTAssertTrue(app.buttons["İşi yapmadı"].exists, "neden seçenekleri")
        neden.tap()
        XCTAssertTrue(kosulBekle(timeout: 5) { !app.buttons["Yanlış bilgi"].exists }, "diyalog kapanmalı")
        XCTAssertTrue(kosulBekle(timeout: 3) { (begenme.value as? String) == "seçili" }, "beğenme seçili görünmeli: \(String(describing: begenme.value))")
    }
}
