import Foundation
import Testing
@testable import Asistan

@Suite("Ses modu ve dokunarak gönderim") @MainActor
struct SesModuTestleri {
    @Test func yinelenenKapatmaAraDurumuKapaliYapar() async {
        let d = SesDinleyici(); d.otomatikGonder = false
        await d.durdur()
        // Önceki çözümleyici kapanırken geç gelen durum güncellemesini temsil eder.
        d.sinamaSonucu("Geç gelen sonuç")
        #expect(d.durum == .dinliyor)
        await d.durdur()
        #expect(d.durum == .kapali)
        #expect(!d.gonder())
    }
    @Test func normalModSessizlikteGondermezDokunustaBirKezGonderir() async {
        let d = SesDinleyici(); d.otomatikGonder = false
        var metinler: [String] = []
        d.kesinlesti = { m, _, _ in metinler.append(m) }
        d.sinamaSonucu("Merhaba Mehmet")
        try? await Task.sleep(for: .milliseconds(1300))
        #expect(metinler.isEmpty)
        #expect(d.gonder())
        #expect(!d.gonder())
        #expect(metinler == ["Merhaba Mehmet"])
        await d.durdur()
    }
    @Test func durdurGondermezVeGecikmisZamanlayiciCalismaz() async {
        let d = SesDinleyici(); d.sessizlikMs = 50
        var adet = 0
        d.kesinlesti = { _, _, _ in adet += 1 }
        d.sinamaSonucu("Bunu gönderme")
        await d.durdur()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(adet == 0)
        #expect(!d.gonder())
        #expect(d.canliMetin.isEmpty)
    }
    @Test func otomatikModdaCumleBirKezTeslimEdilir() async {
        let d = SesDinleyici(); d.sessizlikMs = 50
        var metinler: [String] = []
        d.kesinlesti = { m, _, _ in metinler.append(m) }
        d.sinamaSonucu("Merhaba")
        d.sinamaSonucu("Merhaba asistan")
        try? await Task.sleep(for: .milliseconds(200))
        #expect(metinler == ["Merhaba asistan"])
        #expect(!d.gonder())
        await d.durdur()
    }
    @Test func liveKesinSonucuEkSessizlikBeklemedenTeslimEder() async {
        let d = SesDinleyici()
        d.sessizlikMs = 1_000
        d.kesinSonucuHemenGonder = true
        var metinler: [String] = []
        d.kesinlesti = { m, _, _ in metinler.append(m) }
        d.sinamaSonucu("Canlı konuşma", kesin: true)
        #expect(metinler == ["Canlı konuşma"])
        #expect(!d.gonder())
        await d.durdur()
    }
}

@Suite("Live görsel durumu ve gerçek ses ölçümü")
struct CanliGorselTestleri {
    @Test func sesUretilirkenKonusuyorGosterilmez() {
        #expect(CanliGorselDurum.sec(baglaniyor: false, dinliyor: false, sesCaliyor: false,
                                   yanitBekleniyor: true, hata: false) == .dusunuyor)
        #expect(CanliGorselDurum.sec(baglaniyor: false, dinliyor: false, sesCaliyor: true,
                                   yanitBekleniyor: true, hata: false) == .konusuyor)
    }

    @Test func baglantiVeEtkinMotorEskiHatadanOnceGelir() {
        #expect(CanliGorselDurum.sec(baglaniyor: true, dinliyor: true, sesCaliyor: false,
                                   yanitBekleniyor: false, hata: true) == .baglaniyor)
        #expect(CanliGorselDurum.sec(baglaniyor: false, dinliyor: true, sesCaliyor: false,
                                   yanitBekleniyor: false, hata: true) == .dinliyor)
        #expect(CanliGorselDurum.sec(baglaniyor: false, dinliyor: false, sesCaliyor: false,
                                   yanitBekleniyor: false, hata: true) == .hata)
    }

    @Test func yalnizEtkinSesYonuOlculur() {
        #expect(CanliGorselDurum.dinliyor.duzey(girisDb: -100, cikisDb: 0) == 0)
        #expect(CanliGorselDurum.konusuyor.duzey(girisDb: 0, cikisDb: -100) == 0)
        #expect(CanliGorselDurum.dinliyor.duzey(girisDb: -10, cikisDb: -100) == 1)
        for durum in [CanliGorselDurum.hazir, .baglaniyor, .dusunuyor, .hata] {
            #expect(durum.duzey(girisDb: 0, cikisDb: 0) == 0)
        }
    }

    @Test func bozukOlcumlerVeSinirlarGuvenli() {
        for db in [Double.nan, .infinity, -.infinity, -120, -55] {
            #expect(CanliGorselDurum.dinliyor.duzey(girisDb: db, cikisDb: 0) == 0)
        }
        #expect(CanliGorselDurum.dinliyor.duzey(girisDb: 20, cikisDb: -100) == 1)
        let sessiz = CanliGorselDurum.dinliyor.duzey(girisDb: -45, cikisDb: -100)
        let yuksek = CanliGorselDurum.dinliyor.duzey(girisDb: -25, cikisDb: -100)
        #expect(sessiz > 0 && sessiz < yuksek && yuksek < 1)
    }

    @Test func gercekPcmRmsOlcumu() {
        let sessiz: [Float] = [0, 0, 0, 0]
        let yarim: [Float] = [0.5, -0.5, 0.5, -0.5]
        let tam: [Float] = [1, -1]
        #expect(sessiz.withUnsafeBufferPointer { CanliSesIO.desibel($0) } == -100)
        #expect(abs(yarim.withUnsafeBufferPointer { CanliSesIO.desibel($0) } + 6.0206) < 0.001)
        #expect(tam.withUnsafeBufferPointer { CanliSesIO.desibel($0) } == 0)
    }

    @Test func bosVeBozukPcmSessizSayilir() {
        for ornekler: [Float] in [[], [.nan], [.infinity], [0.5, -.infinity]] {
            #expect(ornekler.withUnsafeBufferPointer { CanliSesIO.desibel($0) } == -100)
        }
    }
}

@Suite("Live ses seçimi ve sağlayıcı yedeği")
struct CanliSesSecimiTestleri {
    @Test func birSesteHataDigerSesleriEngellemez() {
        var devreler = BulutSesDevreleri()
        let simdi = Date()
        devreler.hata(kimlik: "azure:Elif", simdi: simdi)
        devreler.hata(kimlik: "azure:Elif", simdi: simdi)
        #expect(devreler.yerelMi(kimlik: "azure:Elif", simdi: simdi))
        #expect(!devreler.yerelMi(kimlik: "chatgpt:Marin", simdi: simdi))
        #expect(!devreler.yerelMi(kimlik: "azure:Aydın", simdi: simdi))
        devreler.basari(kimlik: "azure:Elif")
        #expect(!devreler.yerelMi(kimlik: "azure:Elif", simdi: simdi))
    }

    @Test func yenidenDenemeBaskaSesinBeklemesiniSilmez() {
        var devreler = BulutSesDevreleri()
        let simdi = Date()
        for kimlik in ["azure:Elif", "chatgpt:Marin"] {
            devreler.hata(kimlik: kimlik, simdi: simdi)
            devreler.hata(kimlik: kimlik, simdi: simdi)
        }
        devreler.basari(kimlik: "chatgpt:Marin")
        #expect(devreler.yerelMi(kimlik: "azure:Elif", simdi: simdi))
        #expect(!devreler.yerelMi(kimlik: "chatgpt:Marin", simdi: simdi))
    }
}

@Suite("Live ses tercihi göçü") @MainActor
struct CanliSesTercihiTestleri {
    @Test func elifBirKezTasinirSonrakiSecimKorunur() {
        let ad = "live-ses-" + UUID().uuidString
        let d = UserDefaults(suiteName: ad)!
        defer { d.removePersistentDomain(forName: ad) }
        d.set("azure:Elif", forKey: "ayar.sesKimligi")
        let ilk = Ayarlar(defaults: d)
        #expect(ilk.sesKimligi == "claude:Kore")
        ilk.sesKimligi = "azure:Elif"
        #expect(Ayarlar(defaults: d).sesKimligi == "azure:Elif")
    }

    @Test func baskaSesSecimiKorunur() {
        let ad = "live-ses-" + UUID().uuidString
        let d = UserDefaults(suiteName: ad)!
        defer { d.removePersistentDomain(forName: ad) }
        d.set("chatgpt:Marin", forKey: "ayar.sesKimligi")
        #expect(Ayarlar(defaults: d).sesKimligi == "chatgpt:Marin")
    }
}
