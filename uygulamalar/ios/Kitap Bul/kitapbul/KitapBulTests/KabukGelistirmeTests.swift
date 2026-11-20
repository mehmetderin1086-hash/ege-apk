import Testing
import Foundation
@testable import _01

/// Kabuk-Tema paketi: sekme çözümü, açılış planı, KPI formülü, yönetici hoşgörüsü, tema durumu,
/// arşiv zamanlayıcısı ve derin bağlantılar. Saf kararlar, uygulama açılmadan sınanır.
@MainActor
struct KabukGelistirmeTests {
    private func izoleVarsayilanlar() -> UserDefaults {
        let ad = "kitapbul.kabuk.test." + UUID().uuidString
        let d = UserDefaults(suiteName: ad)!
        d.removePersistentDomain(forName: ad)
        return d
    }

    // MARK: Sekme.coz

    @Test func genisEkrandaHerHedefKendiSekmesidir() {
        for sekme in MainTabView.Sekme.allCases {
            #expect(MainTabView.Sekme.coz(sekme, compact: false) == .sekme(sekme))
        }
    }

    @Test func telefondaGizliSekmelerSayfaOlarakAcilir() {
        #expect(MainTabView.Sekme.coz(.asistan, compact: true) == .asistanSayfasi)
        #expect(MainTabView.Sekme.coz(.araclar, compact: true) == .araclarSayfasi)
        #expect(MainTabView.Sekme.coz(.ayarlar, compact: true) == .ayarlarSayfasi)
    }

    @Test func telefondaCubuktakiBesSekmeDegismez() {
        for sekme in MainTabView.Sekme.kaydirmaSirasi {
            #expect(MainTabView.Sekme.coz(sekme, compact: true) == .sekme(sekme))
        }
    }

    // MARK: AcilisPlani

    @Test func yeniKurulumdaTanitimAcilir() {
        #expect(AcilisPlani.yap(onboardingShown: false, sonGorulen: "", surum: "1.0") == .tanitim)
    }

    @Test func guncellemedeYenliklerAcilir() {
        #expect(AcilisPlani.yap(onboardingShown: true, sonGorulen: "0.9", surum: "1.0") == .yenilikler)
        #expect(AcilisPlani.yap(onboardingShown: true, sonGorulen: "", surum: "1.0") == .yenilikler)
    }

    @Test func gorulmusSurumdeHicbirSeyAcilmaz() {
        #expect(AcilisPlani.yap(onboardingShown: true, sonGorulen: "1.0", surum: "1.0") == .hic)
    }

    @Test func yenilikleriTanitimdanOnceGelirVeBirlikteAcilmaz() {
        // Tanıtım görülmemişse yenilikler hiç sayılmaz; görülmüşse tanıtım hiç sayılmaz.
        for gorulen in [true, false] {
            let plan = AcilisPlani.yap(onboardingShown: gorulen, sonGorulen: "0.1", surum: "1.0")
            #expect(plan == (gorulen ? .yenilikler : .tanitim))
        }
    }

    // MARK: Yenilikler

    @Test func bilinmeyenSurumSonGirdiyiGosterir() {
        let bilinen = Yenilikler.maddeler(surum: "1.0")
        #expect(!bilinen.isEmpty)
        #expect(Yenilikler.maddeler(surum: "99.0").map(\.baslik) == bilinen.map(\.baslik))
    }

    // MARK: HomeKPI

    @Test func kpiNushaFormuluYonetimdekiStokToplamiylaAyni() {
        let yok = CatalogBook(book: Book(title: "A", author: "X"))                          // adet yok → 1
        let sifir = CatalogBook(book: Book(title: "B", author: "X", quantity: 0))           // 0 → en az 1
        let uc = CatalogBook(book: Book(title: "C", author: "X", quantity: 3))              // 3
        let nushaFazla = CatalogBook(book: Book(title: "D", author: "X", quantity: 1))      // 1 ama 4 nüsha kaydı
        let dusulmus = CatalogBook(book: Book(title: "E", author: "X", quantity: 9))
        dusulmus.isWithdrawn = true
        let kitaplar = [yok, sifir, uc, nushaFazla, dusulmus]
        let nushalar = (0..<4).map { BookCopy(bookID: nushaFazla.id, accessionCode: "N\($0)") }
            + [BookCopy(bookID: dusulmus.id, accessionCode: "DUS")]

        let kpi = HomeKPI.hesapla(books: kitaplar, copies: nushalar, loans: [])
        let etkin = kitaplar.filter { !$0.isWithdrawn }
        let stok = SchoolLibraryService.stockByBook(books: etkin, loans: [], copies: nushalar, reservations: [])
        #expect(kpi.baslik == 4)
        #expect(kpi.nusha == 1 + 1 + 3 + 4)
        #expect(kpi.nusha == stok.values.reduce(0) { $0 + $1.total })
    }

    @Test func kpiOduncGecikenVeBugunIade() {
        let simdi = Date()
        let gun = Calendar.current.startOfDay(for: simdi)
        let kitap = CatalogBook(book: Book(title: "A", author: "X"))
        let dun = ActiveLoan(bookID: kitap.id, bookTitleSnapshot: "A", studentName: "Ali", studentClass: "5-A",
                             dueDate: gun.addingTimeInterval(-86_400))
        let bugun = ActiveLoan(bookID: kitap.id, bookTitleSnapshot: "A", studentName: "Ayşe", studentClass: "5-A",
                               dueDate: gun.addingTimeInterval(3_600))
        let kpi = HomeKPI.hesapla(books: [kitap], copies: [], loans: [dun, bugun], now: simdi)
        #expect(kpi.odunc == 2)
        #expect(kpi.geciken == 1)
        #expect(kpi.bugunIade == 1)
    }

    @Test func eksikBilgiSayisiAtlanabilir() {
        let kitap = CatalogBook(book: Book(title: "A", author: "X"))
        #expect(HomeKPI.hesapla(books: [kitap], copies: [], loans: []).eksik == 1)
        #expect(HomeKPI.hesapla(books: [kitap], copies: [], loans: [], eksikleriSay: false).eksik == 0)
    }

    @Test func panelGirdisindeGorunumSayaciVeriyiDegistirmez() {
        let a = HomeInputs(kitaplar: [], loans: [], copies: [], gorunumSayaci: 1)
        let b = HomeInputs(kitaplar: [], loans: [], copies: [], gorunumSayaci: 2)
        #expect(a != b)
        #expect(a.veriAyni(b))
    }

    // MARK: YetkiDurumu hoşgörüsü

    @Test func hosgoruSuresiIcindeYoneticiKalir() {
        let yetki = YetkiDurumu(defaults: izoleVarsayilanlar())
        yetki.kilitEtkin = true
        yetki.yoneticiOturumuBaslat()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        yetki.arkaPlanaGecti(simdi: t0)
        #expect(yetki.onePlanaDondu(simdi: t0.addingTimeInterval(89)) == false)
        #expect(yetki.yonetici)
    }

    @Test func hosgoruSuresiAsilincaGorevliyeDonulur() {
        let yetki = YetkiDurumu(defaults: izoleVarsayilanlar())
        yetki.kilitEtkin = true
        yetki.yoneticiOturumuBaslat()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        yetki.arkaPlanaGecti(simdi: t0)
        #expect(yetki.onePlanaDondu(simdi: t0.addingTimeInterval(91)) == true)
        #expect(!yetki.yonetici)
    }

    @Test func hosgoruSifirsaArkaPlandaHemenKapanir() {
        let yetki = YetkiDurumu(defaults: izoleVarsayilanlar())
        yetki.kilitEtkin = true
        yetki.hosgoruSaniye = 0
        yetki.yoneticiOturumuBaslat()
        yetki.arkaPlanaGecti()
        #expect(!yetki.yonetici)
    }

    @Test func kilitKapaliykenHosgoruBirseyDegistirmez() {
        let yetki = YetkiDurumu(defaults: izoleVarsayilanlar())
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        yetki.arkaPlanaGecti(simdi: t0)
        #expect(yetki.onePlanaDondu(simdi: t0.addingTimeInterval(10_000)) == false)
        #expect(yetki.yonetici)
    }

    @Test func hosgoruAyariKalicidirVeGecersizDegerVarsayilanaDoner() {
        let d = izoleVarsayilanlar()
        let ilk = YetkiDurumu(defaults: d)
        #expect(ilk.hosgoruSaniye == 90)
        ilk.hosgoruSaniye = 300
        #expect(YetkiDurumu(defaults: d).hosgoruSaniye == 300)
        d.set(7, forKey: YetkiDurumu.hosgoruAnahtari)
        #expect(YetkiDurumu(defaults: d).hosgoruSaniye == 90)
    }

    // MARK: GradeLoanRule.imza

    @Test func kademeImzasiSiraVeIcerigeDuyarli() {
        let a = GradeLoanRule(gradePrefix: "5", maxConcurrentLoans: 2, loanDurationDays: 10)
        let b = GradeLoanRule(gradePrefix: "9", maxConcurrentLoans: 3, loanDurationDays: 15)
        #expect(GradeLoanRule.imza([a, b]) == GradeLoanRule.imza([a, b]))
        #expect(GradeLoanRule.imza([a, b]) != GradeLoanRule.imza([b, a]))
        var degisen = a
        degisen.loanDurationDays = 11
        #expect(GradeLoanRule.imza([a]) != GradeLoanRule.imza([degisen]))
        #expect(GradeLoanRule.imza([]) == "")
    }

    // MARK: TemaDurumu

    @Test func temaDurumuKayitliSecimiYansitir() {
        let d = izoleVarsayilanlar()
        let tema = TemaDurumu(defaults: d)
        #expect(tema.secili == .indigo)
        d.set(TemaRengi.yesil.rawValue, forKey: TemaRengi.anahtar)
        tema.yenile()
        #expect(tema.secili == .yesil)
        d.set("bozuk", forKey: TemaRengi.anahtar)
        tema.yenile()
        #expect(tema.secili == .indigo)
    }

    // MARK: AcilisArsivZamanlayici

    @Test func arsivEtkilesimdenBesSaniyeSonraBaslar() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var z = AcilisArsivZamanlayici(baslangic: t0)
        #expect(!z.vadesiGeldi(t0.addingTimeInterval(30)))   // eski sabit 30 sn artık yok
        z.etkilesimOldu(t0.addingTimeInterval(10))
        #expect(!z.vadesiGeldi(t0.addingTimeInterval(14.9)))
        #expect(z.vadesiGeldi(t0.addingTimeInterval(15)))
    }

    @Test func yalnizIlkEtkilesimSayilir() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var z = AcilisArsivZamanlayici(baslangic: t0)
        z.etkilesimOldu(t0.addingTimeInterval(10))
        z.etkilesimOldu(t0.addingTimeInterval(60))
        #expect(z.ilkEtkilesim == t0.addingTimeInterval(10))
    }

    @Test func etkilesimYoksaUstSinirdaBaslar() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let z = AcilisArsivZamanlayici(baslangic: t0)
        #expect(!z.vadesiGeldi(t0.addingTimeInterval(89)))
        #expect(z.vadesiGeldi(t0.addingTimeInterval(90)))
    }

    // MARK: Canlı gradyan

    @Test func gradyanYalnizHerSartSaglanincaAnimasyonluDur() {
        #expect(CanliGradyan.animasyonluMu(azaltilmisHareket: false, efektler: true, etkin: true, dusukGuc: false, gorunur: true))
        #expect(!CanliGradyan.animasyonluMu(azaltilmisHareket: true, efektler: true, etkin: true, dusukGuc: false, gorunur: true))
        #expect(!CanliGradyan.animasyonluMu(azaltilmisHareket: false, efektler: false, etkin: true, dusukGuc: false, gorunur: true))
        #expect(!CanliGradyan.animasyonluMu(azaltilmisHareket: false, efektler: true, etkin: false, dusukGuc: false, gorunur: true))
        #expect(!CanliGradyan.animasyonluMu(azaltilmisHareket: false, efektler: true, etkin: true, dusukGuc: true, gorunur: true))
        #expect(!CanliGradyan.animasyonluMu(azaltilmisHareket: false, efektler: true, etkin: true, dusukGuc: false, gorunur: false))
    }

    // MARK: Derin bağlantılar

    @Test func oduncVeIadeBaglantilariKipeCevrilir() throws {
        #expect(LibraryLaunchLinkQueue.oduncModu(from: try #require(URL(string: "kitapbul://odunc"))) == .lend)
        #expect(LibraryLaunchLinkQueue.oduncModu(from: try #require(URL(string: "kitapbul://iade"))) == .giveBack)
        #expect(LibraryLaunchLinkQueue.oduncModu(from: try #require(URL(string: "kitapbul://asistan"))) == nil)
        #expect(LibraryLaunchLinkQueue.oduncModu(from: try #require(URL(string: "baska://odunc"))) == nil)
    }

    @Test func oduncBaglantisiAnaSayfayaYonlendirir() throws {
        let rota = KutuphaneRotasi.shared
        let derin = DerinBaglanti.shared
        let eskiMod = rota.bekleyenOduncModu, eskiHedef = derin.hedefSekme
        defer { rota.bekleyenOduncModu = eskiMod; derin.hedefSekme = eskiHedef }
        rota.bekleyenOduncModu = nil; derin.hedefSekme = nil

        let kuyruk = LibraryLaunchLinkQueue()
        kuyruk.enqueue(try #require(URL(string: "kitapbul://iade")))
        #expect(kuyruk.pendingURL != nil)
        kuyruk.dispatchPending()
        #expect(kuyruk.pendingURL == nil)
        #expect(rota.bekleyenOduncModu == .giveBack)
        #expect(derin.hedefSekme == .anaSayfa)
    }
}
