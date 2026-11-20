import XCTest

/// Her menü öğesine dokunur; bir ekran/sayfa açılıp açılmadığını denetler ve kapatır.
@MainActor final class TumDugmelerUITesti: XCTestCase {
    var app: XCUIApplication!
    var sonuclar: [String] = []

    override func setUp() async throws {
        continueAfterFailure = true
        // P3.10: hermetik (sahte model, animasyonsuz, bellek içi hafıza); gerçek modele/ağa çıkmaz.
        app = XCUIApplication.hermetik()
        app.launch()
    }

    private var giris: XCUIElement { app.descendants(matching: .any).matching(identifier: "mesaj-girisi").firstMatch }

    /// Açılan sayfayı kapatır; ana ekrana dönemezse false.
    private func kapat() -> Bool {
        for _ in 0..<3 {
            if giris.waitForExistence(timeout: 1), giris.isHittable { return true }
            for ad in ["Tamam", "Kapat", "Vazgeç", "Bitti", "İptal", "Cancel", "Geri", "Kapat ✕"] {
                let b = app.buttons[ad].firstMatch
                if b.exists, b.isHittable { b.tap(); break }
            }
            if giris.waitForExistence(timeout: 1), giris.isHittable { return true }
            // Sayfayı aşağı kaydırarak kapat.
            let ust = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
            ust.press(forDuration: 0.05, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        }
        return giris.waitForExistence(timeout: 2) && giris.isHittable
    }

    private func dene(_ menu: String, _ oge: String, gecikme: TimeInterval = 4) {
        let m = app.buttons[menu].firstMatch
        guard m.waitForExistence(timeout: 3) else { sonuclar.append("✗ [\(menu)] menü düğmesi yok"); return }
        m.tap()
        let b = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", oge)).firstMatch
        guard b.waitForExistence(timeout: 3) else {
            sonuclar.append("✗ [\(menu)] '\(oge)' menüde yok"); app.windows.firstMatch.tap(); return
        }
        b.tap()
        sonuclandir(menu, oge, gecikme: gecikme)
    }

    private func sonuclandir(_ menu: String, _ oge: String, gecikme: TimeInterval) {
        // Açıldı kabulü: giriş alanı artık dokunulabilir değil (sayfa/sunum üstte) ya da gezinme çubuğu var.
        let acildi = kosulBekle(timeout: gecikme, aralik: 0.3) { !(self.giris.exists && self.giris.isHittable) || self.app.navigationBars.count > 0 }
        let baslik = app.navigationBars.allElementsBoundByIndex.map(\.identifier).joined(separator: "/")
        let ok = kapat()
        sonuclar.append("\(acildi ? "✓" : "✗") [\(menu)] \(oge)\(acildi ? "" : " — AÇILMADI")\(baslik.isEmpty ? "" : " → \(baslik)")\(ok ? "" : " (kapanmadı!)")")
        if !ok { app.terminate(); app.launch() }
    }

    func testEkleMenusu() {
        for oge in ["Bağlantı indir", "Dosyalarımda ara", "Ofis, PDF, metin veya kod ekle", "Dosyayı başka biçime dönüştür",
                    "ZIP oluştur veya RAR aç", "Araştırma, kod ve görsel atölyesi", "Fotoğraf çek", "Fotoğraf seç"] {
            dene("Dosya veya fotoğraf ekle", oge, gecikme: 6)
        }
        print("DUGME-SONUC\n" + sonuclar.joined(separator: "\n"))
        XCTAssertFalse(sonuclar.contains { $0.hasPrefix("✗") }, sonuclar.filter { $0.hasPrefix("✗") }.joined(separator: "\n"))
    }

    func testUstMenu() {
        for oge in ["Gelen Kutusu", "Atölye", "İndirmeler", "Dosya dönüştür", "ZIP / RAR", "Üretkenlik",
                    "Telefon işlemleri", "Görünümü düzenle", "Kişisel alanım"] {
            app.aracAc(oge)
            sonuclandir("Çekmece › Araçlar", oge, gecikme: 4)
        }
        print("DUGME-SONUC\n" + sonuclar.joined(separator: "\n"))
        XCTAssertFalse(sonuclar.contains { $0.hasPrefix("✗") }, sonuclar.filter { $0.hasPrefix("✗") }.joined(separator: "\n"))
    }

    func testAyarlarVeAltSayfalari() {
        app.ayarlariAc()
        XCTAssertTrue(app.navigationBars["Ayarlar"].waitForExistence(timeout: 4), "Ayarlar açılmadı")
        var sonuc: [String] = []
        // P2.4: alt ekranlar Ayarlar aramasıyla açılır (başlık → ASCII arama terimi; arama Türkçe karakter duyarsızdır).
        let ogeler: [(String, String)] = [
            ("Görünüm stüdyosu", "gorunum"), ("Komutlarım ve kaydedilenler", "komut"), ("Sağlık ve hız merkezi", "saglik"),
            ("Beceriler", "beceri"), ("MCP sunucuları", "mcp"), ("Çalışma alanı (SOUL · USER · AGENTS)", "soul"),
            ("Nabız (proaktif kontrol)", "nabiz"), ("Hey Asistan ve diğer uygulamalardan erişim", "hey asistan"), ("İzinler", "izinler"),
        ]
        for (baslik, terim) in ogeler {
            guard app.ayarAramasindanAc(baslik, terim: terim) else { sonuc.append("✗ Ayarlar › \(baslik) bulunamadı"); continue }
            func acildi() -> Bool { kosulBekle(timeout: 5, aralik: 0.2) {
                self.app.navigationBars.count > 0 && !self.app.navigationBars["Ayarlar"].exists
                    && self.app.navigationBars.buttons.firstMatch.exists
            } }
            var ac = acildi()
            if !ac, app.navigationBars["Ayarlar"].exists {
                let satir = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "ayar-sonuc-", baslik)).firstMatch
                if satir.exists && satir.isHittable {
                    print("AYARLAR: ilk dokunuş geçiş başlatmadı, yeniden deneniyor: \(baslik)")
                    satir.tap(); ac = acildi()
                }
            }
            sonuc.append("\(ac ? "✓" : "✗") Ayarlar › \(baslik)")
            guard ac else { XCTFail("Alt ekran açılmadı: \(baslik)\n\(app.debugDescription)"); return }
            let geri = app.navigationBars.buttons.firstMatch
            if geri.exists { geri.tap() }
            guard app.navigationBars["Ayarlar"].waitForExistence(timeout: 5) else {
                XCTFail("Ayarlar'a dönülemedi: \(baslik)"); return
            }
        }
        // Diğer alt sayfalar gibi Hakkında'yı da aramayla aç. Bu ekran kökteki
        // sürüm bileşenini paylaşır; klavye açıkken arka formu kaydırmaya dayanmaz.
        XCTAssertTrue(app.ayarAramasindanAc("Hakkında", terim: "surum"))
        XCTAssertTrue(app.navigationBars["Hakkında"].waitForExistence(timeout: 5))
        let surum = app.descendants(matching: .any)["surum-satiri"]
        if surum.waitForExistence(timeout: 4) {
            let metin = "\((surum.value as? String) ?? "") \(surum.label)"
            let uygun = metin.contains("(") && metin.range(of: #"\d+\.\d+\.\d+ \("#, options: .regularExpression) != nil
            sonuc.append("\(uygun ? "✓" : "✗") Ayarlar › Hakkında › Sürüm (\(metin))")
        } else {
            sonuc.append("✗ Ayarlar › Hakkında › Sürüm satırı bulunamadı")
        }
        print("DUGME-SONUC\n" + sonuc.joined(separator: "\n"))
        XCTAssertFalse(sonuc.contains { $0.hasPrefix("✗") }, sonuc.filter { $0.hasPrefix("✗") }.joined(separator: "\n"))
    }

    func testModMenusuVeMikrofon() {
        app.cekmeceAc()
        for mod in ["Normal", "Eller serbest", "Live"] { XCTAssertTrue(app.buttons[mod].waitForExistence(timeout: 3), "\(mod) yok") }
        app.cekmeceKapat()
        XCTAssertTrue(app.buttons["ses-yuvarlagi"].waitForExistence(timeout: 3), "mikrofon düğmesi yok")
    }

    /// Fotoğraf seç → ilk fotoğrafa dokun → girdi çubuğunda "Fotoğraf eklendi" görünmeli.
    func testFotografSecimiEklenir() {
        let ekle = app.buttons["Dosya veya fotoğraf ekle"]
        XCTAssertTrue(ekle.waitForExistence(timeout: 3)); ekle.tap()
        let sec = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fotoğraf seç")).firstMatch
        XCTAssertTrue(sec.waitForExistence(timeout: 3)); sec.tap()
        XCTAssertTrue(app.navigationBars["Fotoğraflar"].waitForExistence(timeout: 6), "seçici açılmadı")
        let foto = app.scrollViews.images.firstMatch
        XCTAssertTrue(foto.waitForExistence(timeout: 6), "seçicide fotoğraf yok\n\(app.debugDescription)")
        foto.tap()
        let ekleDugme = app.buttons.matching(NSPredicate(format: "label IN %@", ["Ekle", "Add", "Bitti", "Done"])).firstMatch
        if ekleDugme.waitForExistence(timeout: 2) { ekleDugme.tap() }
        XCTAssertTrue(app.staticTexts["Fotoğraf eklendi"].waitForExistence(timeout: 8), "seçilen fotoğraf eklenmedi\n\(app.debugDescription)")
        // Gönderince fotoğraf mesaj balonunda görünmeli.
        app.buttons["Gönder"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["mesaj-resmi"].waitForExistence(timeout: 8), "yüklenen fotoğraf mesajda görünmedi\n\(app.debugDescription)")
        // Çift dokunuşla fotoğraf büyür, kapat ile döner.
        app.descendants(matching: .any)["mesaj-resmi"].doubleTap()
        XCTAssertTrue(app.images["foto-buyuk"].waitForExistence(timeout: 5), "çift dokunuşla büyük görüntü açılmadı")
        app.images["foto-buyuk"].doubleTap()          // yakınlaştır
        XCTAssertTrue(app.images["foto-buyuk"].bekle("isHittable", 2), "büyük görüntü yakınlaştırmadan sonra erişilemez")
        app.images["foto-buyuk"].doubleTap()          // uzaklaştır
        app.buttons["foto-kapat"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["mesaj-resmi"].waitForExistence(timeout: 5), "büyük görüntü kapanmadı")
        // Seçici arka plana düşürse bile cevap gelmeli (yerel proxy ölmüş olabilir): süre etiketi görünür, hata yok.
        let etiket = app.buttons.matching(identifier: "yeniden-uret").firstMatch
        XCTAssertTrue(etiket.waitForExistence(timeout: 10), "fotoğrafa cevap gelmedi\n\(app.debugDescription)")
        XCTAssertFalse(app.staticTexts["Bağlantı yok ya da sunucuya ulaşılamadı."].exists, "bağlantı hatası göründü")
        print("FOTO CEVAP ETIKETI: \(etiket.label)")
    }

    /// İstek sürerken uygulama arka plana alınır; dönünce cevap gelmiş ve hata olmamalı.
    /// Sahte senaryoda "galatasaray" yanıtı 3 sn gecikmeli başlar: istek arka plana geçişten önce yola çıkmış olur.
    func testArkaPlanaGidipDonuncaCevapTamamlanir() {
        XCTAssertTrue(giris.waitForExistence(timeout: 10))
        let soru = "Galatasaray'ın bir sonraki maçı ne zaman?"
        giris.tap(); giris.typeText(soru)
        app.buttons["Gönder"].tap()
        XCTAssertTrue(app.staticTexts[soru].waitForExistence(timeout: 5), "istek balonu görünmedi")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10) || app.wait(for: .runningBackgroundSuspended, timeout: 5), "uygulama arka plana geçmedi")
        // Bilinçli tek bekleme: istek arka planda sürerken sahte yanıtın gecikmesi (3 sn) dolsun.
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "arka planda bekleme")], timeout: 4)
        app.activate()
        let etiket = app.buttons.matching(identifier: "yeniden-uret").firstMatch
        XCTAssertTrue(etiket.waitForExistence(timeout: 15), "arka plandan dönünce cevap yok\n\(app.debugDescription)")
        for hata in ["Bağlantı yok ya da sunucuya ulaşılamadı.", "Hata:"] {
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", hata)).firstMatch.exists, "hata göründü: \(hata)")
        }
        print("ARKA PLAN ETIKETI: \(etiket.label)")
    }

    /// P2.4: Ayarlar alt ekranlarına arama alanından gidilir (`terim` ASCII arama sözcüğü).
    private func ayarlardaAc(_ baslik: String, terim: String) -> Bool {
        app.ayarAramasindanAc(baslik, terim: terim)
    }

    /// Kullanım sayacı gerçek isteklerle artar; izleme ve hafıza ekranları açılır; hafızaya olgu eklenip silinir.
    func testKullanimIzlemeVeHafizaEkranlari() {
        XCTAssertTrue(giris.waitForExistence(timeout: 10))
        giris.tap(); giris.typeText("Fotosentezi tek cümleyle açıkla.")
        app.buttons["Gönder"].tap()
        let etiket = app.buttons.matching(identifier: "yeniden-uret").firstMatch
        XCTAssertTrue(etiket.waitForExistence(timeout: 10), "model cevabı gelmedi")

        app.ayarlariAc()
        XCTAssertTrue(app.navigationBars["Ayarlar"].waitForExistence(timeout: 4))
        // Kullanım ve kota
        XCTAssertTrue(ayarlardaAc("Kullanım ve kota", terim: "kota"), "Kullanım ve kota satırı yok")
        XCTAssertTrue(app.navigationBars["Kullanım ve kota"].waitForExistence(timeout: 4))
        let toplam = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", #"^Toplam, [1-9]\d* istek$"#)).firstMatch
        XCTAssertTrue(toplam.waitForExistence(timeout: 5), "kullanım sayacı artmadı\n\(app.debugDescription)")
        print("KULLANIM TOPLAM: \(toplam.label)")
        XCTAssertTrue(app.staticTexts["Paralel yarış"].exists || app.staticTexts["PARALEL YARIŞ"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        // Çökme ve performans
        XCTAssertTrue(ayarlardaAc("Çökme ve performans", terim: "cokme"), "Çökme ve performans satırı yok")
        XCTAssertTrue(app.navigationBars["Çökme ve performans"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Son 30 gün"].exists || app.staticTexts["SON 30 GÜN"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        // Hafıza: olgu ekle → görünür → sil
        XCTAssertTrue(ayarlardaAc("Asistan seni böyle tanıyor", terim: "taniyor"), "Hafıza satırı yok")
        XCTAssertTrue(app.navigationBars["Hafıza"].waitForExistence(timeout: 4))
        let olguMetni = "UITEST-olgusu-98765"
        func olguyuSil() -> Bool {
            let satir = app.staticTexts[olguMetni]
            guard satir.waitForExistence(timeout: 2) else { return false }
            satir.swipeLeft()
            let sil = app.buttons["Delete"].waitForExistence(timeout: 2) ? app.buttons["Delete"] : app.buttons["Sil"]
            guard sil.waitForExistence(timeout: 3) else { return false }
            sil.tap()
            return true
        }
        // Önceki yarım kalmış çalıştırmadan kalan test olgusu temizlenir (depo aynı metni yinelemez).
        while app.staticTexts[olguMetni].exists { XCTAssertTrue(olguyuSil(), "eski test olgusu silinemedi") }
        let alan = app.textFields["Yeni olgu ekle…"]
        XCTAssertTrue(alan.waitForExistence(timeout: 4)); alan.tap(); alan.typeText(olguMetni)
        app.buttons["Ekle"].tap()
        // Ekle'den sonra klavye kapanmalı; açık kalırsa satırı örtüyordu.
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1.5) && app.keyboards.firstMatch.isHittable, "Ekle sonrası klavye kapanmadı")
        XCTAssertTrue(app.staticTexts[olguMetni].waitForExistence(timeout: 5), "olgu eklenmedi")
        XCTAssertTrue(olguyuSil(), "silme düğmesi yok")
        XCTAssertFalse(app.staticTexts[olguMetni].waitForExistence(timeout: 2), "olgu silinmedi")
    }

    /// Cevabın yanındaki ↻ menüsünden başka modelle yeniden üretme.
    func testYenidenUretMenusu() {
        XCTAssertTrue(giris.waitForExistence(timeout: 10))
        giris.tap(); giris.typeText("Fotosentezi tek cümleyle açıkla.")
        app.buttons["Gönder"].tap()
        let menu = app.buttons["yeniden-uret"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "ilk cevap (model adı) gelmedi")
        menu.tap()
        let opus = app.buttons["claude-opus-5-5"].firstMatch
        XCTAssertTrue(opus.waitForExistence(timeout: 4), "model listesi açılmadı\n\(app.debugDescription)")
        opus.tap()
        let yeni = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Model: claude-opus-5-5")).firstMatch
        XCTAssertTrue(yeni.waitForExistence(timeout: 15), "Opus ile yeniden üretilmedi")
        XCTAssertTrue(app.staticTexts["↻ claude-opus-5-5 ile yeniden"].exists, "yeniden üretim isteği balonda görünmeli")
        print("YENIDEN URET ETIKETI: \(yeni.label)")
    }
}
