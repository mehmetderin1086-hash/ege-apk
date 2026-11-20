import Testing
import Foundation
@testable import _01

@MainActor
struct ArayuzUrunTestleri {
    @Test func temaRengiVarsayilanVeSecim() {
        let eski = UserDefaults.standard.string(forKey: TemaRengi.anahtar)
        defer { UserDefaults.standard.set(eski, forKey: TemaRengi.anahtar) }
        UserDefaults.standard.removeObject(forKey: TemaRengi.anahtar)
        #expect(TemaRengi.secili == .indigo)
        UserDefaults.standard.set(TemaRengi.yesil.rawValue, forKey: TemaRengi.anahtar)
        #expect(TemaRengi.secili == .yesil)
        UserDefaults.standard.set("bozuk", forKey: TemaRengi.anahtar)
        #expect(TemaRengi.secili == .indigo)
    }

    @Test func kotaVeGecikmeEngeli() throws {
        let simdi = Date(timeIntervalSince1970: 1_800_000_000)
        let loans = [
            ActiveLoan(bookID: UUID(), bookTitleSnapshot: "A", studentName: "Ali", studentClass: "5-A", dueDate: simdi.addingTimeInterval(86_400)),
            ActiveLoan(bookID: UUID(), bookTitleSnapshot: "B", studentName: "Ali", studentClass: "5-A", dueDate: simdi.addingTimeInterval(-86_400))
        ]
        let kural = [GradeLoanRule(gradePrefix: "5", maxConcurrentLoans: 2, loanDurationDays: 10)]
        // Kural yok, genel sınır yok, engel kapalı → serbest
        try OduncKotasi.denetle(kisi: "Ali", sinif: "7-A", loans: loans, now: simdi, kurallar: [], genelSinir: 0, gecikmeEngeli: false)
        // Kademe kuralı 2 → dolu
        #expect(throws: OduncMerkezi.OduncHatasi.self) {
            try OduncKotasi.denetle(kisi: "Ali", sinif: "5-A", loans: loans, now: simdi, kurallar: kural, genelSinir: 0, gecikmeEngeli: false)
        }
        // Genel sınır 3 → serbest; gecikme engeli açık → engel
        try OduncKotasi.denetle(kisi: "Ali", sinif: "", loans: loans, now: simdi, kurallar: [], genelSinir: 3, gecikmeEngeli: false)
        #expect(throws: OduncMerkezi.OduncHatasi.self) {
            try OduncKotasi.denetle(kisi: "Ali", sinif: "", loans: loans, now: simdi, kurallar: [], genelSinir: 0, gecikmeEngeli: true)
        }
        // Başka öğrenci etkilenmez
        try OduncKotasi.denetle(kisi: "Ayşe", sinif: "5-A", loans: loans, now: simdi, kurallar: kural, genelSinir: 1, gecikmeEngeli: true)
        #expect(GradeLoanRuleStore.explicitRule(for: "", rules: kural) == nil)
    }

    @Test func yeniliklerYalnizGuncellemedeGosterilir() {
        #expect(!Yenilikler.gosterilmeli(sonGorulen: nil, surum: "1.1", tanitimGoruldu: false))   // yeni kurulum
        #expect(Yenilikler.gosterilmeli(sonGorulen: "", surum: "1.1", tanitimGoruldu: true))
        #expect(Yenilikler.gosterilmeli(sonGorulen: "1.0", surum: "1.1", tanitimGoruldu: true))
        #expect(!Yenilikler.gosterilmeli(sonGorulen: "1.1", surum: "1.1", tanitimGoruldu: true))
    }

    @Test func widgetVeQRBaglantilariCozulur() {
        let id = UUID()
        #expect(KitapQR.hedef(from: KitapQR.url(for: id)) == .kitap(id))
        #expect(KitapQR.hedef(from: URL(string: "kitapbul://ekle/barkod")!) == .ekle("barkod"))
        #expect(KitapQR.hedef(from: URL(string: "kitapbul://asistan")!) == .asistan)
        #expect(KitapQR.hedef(from: URL(string: "kitapbul://bilinmeyen")!) == nil)
        #expect(KitapQR.hedef(from: URL(string: "https://ekle/barkod")!) == nil)
    }

    @Test func rolKilidiKapaliykenHerkesYonetici() {
        let yetki = YetkiDurumu.shared
        let eski = yetki.kilitEtkin
        defer { yetki.kilitEtkin = eski }
        yetki.kilitEtkin = false
        #expect(yetki.yonetici)
        #expect(yetki.rol == .yonetici)
        yetki.kilitEtkin = true
        #expect(!yetki.yonetici)   // kimlik doğrulanmadan görevli
        #expect(yetki.rol == .gorevli)
    }
}

/// Tek ad sözlüğü: Yönetim, Katalog Yönetimi'nin araç paneli ve Ekle aynı adları kullanır.
@MainActor
struct AracAdKaynagiTestleri {
    private let araclar: [KatalogAraci] = [
        .amazonComplete, .duplicates, .loans, .students, .classLoan, .textbooks, .champions, .usageReport,
        .studentCards, .accessionRegister, .statistics, .reportCenter, .excelExport, .dataQuality, .fieldMerge,
        .inventory, .shelfScan, .batchQueue, .undoSession, .undoBulk, .csvImport, .restoreBackup, .archiveExport,
        .archiveImport, .settings
    ]

    @Test func herAracinTekAdiAciklamasiVeIkonuVar() {
        for arac in araclar {
            #expect(arac.aracBasligi?.isEmpty == false, "Adsız araç: \(arac)")
            #expect(!arac.aciklama.isEmpty, "Açıklamasız araç: \(arac)")
            #expect(!arac.ikon.isEmpty, "İkonsuz araç: \(arac)")
        }
        let basliklar = araclar.compactMap(\.aracBasligi)
        #expect(Set(basliklar).count == basliklar.count, "Aynı ad iki araçta kullanılmamalı")
        // Görünüm kaydetme, uygulama ve temizleme birer araç değildir
        #expect(KatalogAraci.saveView.aracBasligi == nil)
        #expect(KatalogAraci.applySavedView(UUID()).aracBasligi == nil)
        #expect(KatalogAraci.clearSavedViews.aracBasligi == nil)
        // Ekle kartıyla ve Ana Sayfa'daki "Ödünç grafikleri"nden ayrışan adlar
        #expect(KatalogAraci.shelfScan.aracBasligi == "Raf sırtları")
        #expect(KatalogAraci.statistics.aracBasligi == "Katalog istatistikleri")
    }

    @Test func aracMetinlerindeTeknikKisaltmaYok() {
        for arac in araclar {
            let metin = (arac.aracBasligi ?? "") + " " + arac.aciklama
            for kisaltma in ["XLSX", "ZIP", "JSON", "(AI)"] {
                #expect(!metin.localizedCaseInsensitiveContains(kisaltma), "\(arac): \(kisaltma)")
            }
        }
    }

    @Test func arsivAramasiOgrencileriGetirmez() {
        // testYonetimAramasindaArsivBulunur'un dayandığı metinler: iki arşiv aracı bulunur, Öğrenciler bulunmaz
        func metin(_ arac: KatalogAraci) -> String { CatalogMatcher.normalize((arac.aracBasligi ?? "") + " " + arac.aciklama) }
        #expect(metin(.archiveExport).contains("arsiv"))
        #expect(metin(.archiveImport).contains("arsiv"))
        #expect(!metin(.students).contains("arsiv"))
    }

    @Test func dogrudanAcilanAraclarKatalogBaglamiIstemez() {
        let dogrudan: [KatalogAraci] = [.students, .classLoan, .textbooks, .champions, .usageReport, .studentCards,
                                         .reportCenter, .dataQuality, .fieldMerge, .inventory, .duplicates, .shelfScan]
        #expect(dogrudan.allSatisfy { !$0.katalogBaglamiGerekir })
        let baglamli: [KatalogAraci] = [.statistics, .accessionRegister, .batchQueue, .csvImport, .restoreBackup,
                                         .archiveImport, .archiveExport, .excelExport, .amazonComplete, .undoSession,
                                         .undoBulk, .saveView, .clearSavedViews, .applySavedView(UUID())]
        #expect(baglamli.allSatisfy { $0.katalogBaglamiGerekir })
    }

    @Test func hizliEylemGorunenAdlariEkleKartlariylaAyni() {
        // Ham değerler kimlik sözleşmesidir, değişmez; görünen ad Ekle kartlarıyla aynıdır
        #expect(HizliEylem.allCases.map(\.rawValue) == ["Barkod okut", "Seri tarama", "Canlı kapak", "Kamerayla tara", "Sesle kaydet", "Elle gir"])
        #expect(HizliEylem.allCases.map(\.baslik) == ["Barkodla ekle", "Seri tarama", "Canlı Kapak", "Belge Tara", "Sesle", "Elle"])
    }

    @Test func hizliIslemBasliklariKorunurIpucuEklenir() {
        // home.action.<başlık> kimlikleri başlıktan üretilir: başlıklar değişmez, ne yaptığını ipucu söyler
        #expect(HomeQuickAction.allCases.map(\.title) == ["Barkod", "Kapak", "Sesle", "Ödünç", "Seri", "Elle", "Asistan", "Yönetim"])
        #expect(HomeQuickAction.barcode.ipucu == "Barkodla kitap ekler")
        #expect(HomeQuickAction.allCases.allSatisfy { !$0.ipucu.isEmpty })
    }
}

@MainActor
struct AnaSayfaTestleri {
    private func olay(_ gunOnce: Int, _ simdi: Date, kind: LoanEvent.Kind = .lent) -> LoanEvent {
        LoanEvent(bookID: UUID(), bookTitle: "K", person: "A", kind: kind,
                  date: Calendar.current.date(byAdding: .day, value: -gunOnce, to: simdi)!)
    }

    @Test func okumaSerisiHaftaSonunuAtlar() {
        // 2026-10-05 Pazartesi
        let simdi = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12))!
        #expect(RaporMotoru.okumaSerisi(events: [], now: simdi) == 0)
        // Pazartesi + Cuma + Perşembe (hafta sonu boş) → 3
        let olaylar = [olay(0, simdi), olay(3, simdi), olay(4, simdi)]
        #expect(RaporMotoru.okumaSerisi(events: olaylar, now: simdi) == 3)
        // Bugün yoksa dünden sayılır; iadeler sayılmaz
        let dunden = [olay(3, simdi), olay(0, simdi, kind: .returned)]
        #expect(RaporMotoru.okumaSerisi(events: dunden, now: simdi) == 1)
        // Hafta içi boş gün seriyi keser
        let kesik = [olay(0, simdi), olay(5, simdi)]
        #expect(RaporMotoru.okumaSerisi(events: kesik, now: simdi) == 1)
    }

    @Test func enCokOkunanlarSiralanir() {
        let a = UUID(), b = UUID()
        let olaylar = [
            LoanEvent(bookID: a, bookTitle: "A", person: "x", kind: .lent, date: .now),
            LoanEvent(bookID: b, bookTitle: "B", person: "x", kind: .lent, date: .now),
            LoanEvent(bookID: b, bookTitle: "B", person: "y", kind: .lent, date: .now),
            LoanEvent(bookID: a, bookTitle: "A", person: "x", kind: .lent, date: .now.addingTimeInterval(-400 * 86_400))
        ]
        #expect(RaporMotoru.enCokOkunanlar(events: olaylar) == [b, a])
    }

    @Test func sekmeKaydirmaSirasi() {
        #expect(MainTabView.Sekme.kaydirmaSirasi.first == .anaSayfa)
        // Geniş ekrana özgü sekmeler (iPhone'da gizli) kenardan kaydırmada gezilmez
        #expect(MainTabView.Sekme.kaydirmaSirasi == [.anaSayfa, .kitaplar, .katalog, .odunc, .yonetim])
        #expect(MainTabView.Sekme(rawValue: "ara") == nil)
        #expect(AyarBolumu.allCases.count == 9)
    }

    @Test func derinBaglantiRotalariQRVeKuyrukIleUyumlu() {
        for route in DeepLinkRoute.allCases {
            // odunc/iade barkod masasını açar; QR hedefi değil, yalnız açılış kuyruğu tanır
            if route != .odunc && route != .iade {
                #expect(KitapQR.hedef(from: route.url) != nil, "\(route.rawValue) QR'da çözülmüyor")
            }
            let kuyruk = LibraryLaunchLinkQueue()
            kuyruk.enqueue(route.url)
            #expect(kuyruk.pendingURL == route.url, "\(route.rawValue) açılış kuyruğunda reddedildi")
        }
        #expect(DeepLinkRoute.widgetRoutes.allSatisfy { KitapQR.hedef(from: $0.url) != nil })
    }
}
