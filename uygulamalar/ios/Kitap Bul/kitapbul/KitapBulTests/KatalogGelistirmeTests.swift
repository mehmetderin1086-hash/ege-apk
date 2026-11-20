import Testing
import Foundation
import SwiftData
@testable import _01

@MainActor
@Suite(.serialized)
struct KatalogGelistirmeTests {
    private func izole(_ is_: (ModelContext) throws -> Void) throws {
        let container = try KitapVeritabani.makeContainer(inMemory: true)
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        context.autosaveEnabled = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let oldHistory = LoanHistoryStore.directoryOverride
        let oldStudents = StudentStore.directoryOverride
        let oldMembers = MemberStore.directoryOverride
        LoanHistoryStore.directoryOverride = directory
        StudentStore.directoryOverride = directory
        MemberStore.directoryOverride = directory
        LoanHistoryStore.invalidateCache()
        defer {
            LoanHistoryStore.directoryOverride = oldHistory
            StudentStore.directoryOverride = oldStudents
            MemberStore.directoryOverride = oldMembers
            LoanHistoryStore.invalidateCache()
            try? FileManager.default.removeItem(at: directory)
        }
        try is_(context)
    }

    private func geciciURL(_ ad: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + ad)
    }

    // MARK: Düşme

    @Test func dusmeOduncluKitabiAtlarVeSayar() throws {
        try izole { context in
            let oduncte = CatalogBook(book: Book(title: "Ödünçte", author: "A"))
            let rafta = CatalogBook(book: Book(title: "Rafta", author: "B"))
            context.insert(oduncte); context.insert(rafta)
            context.insert(ActiveLoan(bookID: oduncte.id, bookTitleSnapshot: oduncte.title, studentName: "Ali", studentClass: "5/A", dueDate: .now))
            try context.save()
            let sonuc = TopluKitapIslemi.dus([oduncte, rafta], neden: "Kayıp", context: context)
            #expect(sonuc.dusulen == 1)
            #expect(sonuc.atlananOdunc == 1)
            #expect(!oduncte.isWithdrawn)
            #expect(rafta.isWithdrawn)
            #expect(rafta.withdrawnReason == "Kayıp")
            #expect(sonuc.mesaj(neden: "Kayıp").contains("1 ödünçlü kitap atlandı"))
        }
    }

    @Test func dusulenKitapKoleksiyonaGeriAlinir() throws {
        try izole { context in
            let kitap = CatalogBook(book: Book(title: "Eser", author: "A"))
            context.insert(kitap)
            _ = TopluKitapIslemi.dus([kitap], neden: "Bağış", context: context)
            #expect(kitap.isWithdrawn)
            TopluKitapIslemi.koleksiyonaGeriAl(kitap)
            #expect(!kitap.isWithdrawn)
            #expect(kitap.withdrawnReason == nil)
            #expect(kitap.withdrawnDate == nil)
        }
    }

    // MARK: Birleştirme

    @Test func birlestirmedeFarkliDemirbasKoduNushayaDonusurVeGeriAlincaSilinir() throws {
        try izole { context in
            let ilk = CatalogBook(book: Book(title: "Eser", author: "Y", publisher: "P", quantity: 1, shelf: "1", cabinet: "A", accessionCode: "D-1"))
            let ikinci = CatalogBook(book: Book(title: "Eser", author: "Y", quantity: 1, shelf: "1", cabinet: "A", accessionCode: "D-2"))
            context.insert(ilk); context.insert(ikinci)
            try context.save()
            let ana = try CatalogMaintenance.merge([ilk, ikinci], context: context)
            let nushalar = try context.fetch(FetchDescriptor<BookCopy>()).filter { $0.bookID == ana.id }
            let kodlar = Set(nushalar.map(\.accessionCode)).union([ana.accessionCode ?? ""])
            #expect(kodlar == ["D-1", "D-2"])
            #expect(nushalar.count == 1)
            #expect(nushalar.first?.accessionCode != ana.accessionCode)
            #expect(ana.quantity == 2)

            _ = try CatalogMaintenance.undoLastMerge(context: context)
            #expect(try context.fetchCount(FetchDescriptor<BookCopy>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<CatalogBook>()) == 2)
        }
    }

    @Test func ayriTutAnahtariSiradanBagimsizdir() {
        let a = UUID(), b = UUID()
        #expect(AyriTutBellegi.anahtar([a, b]) == AyriTutBellegi.anahtar([b, a]))
        #expect(AyriTutBellegi.gizli([b, a], bellek: [AyriTutBellegi.anahtar([a, b])]))
        #expect(!AyriTutBellegi.gizli([a], bellek: [AyriTutBellegi.anahtar([a, b])]))
    }

    // MARK: Toplu yer

    @Test func yerBosAlaniKorurTemizleKumesiSiler() throws {
        try izole { context in
            let kitap = CatalogBook(book: Book(title: "Eser", author: "Y", shelf: "7", cabinet: "A"))
            context.insert(kitap)
            let ozet = TopluKitapIslemi.yer(dolap: "C", raf: "", [kitap])
            #expect(kitap.cabinet == "C")
            #expect(kitap.shelf == "7")
            #expect(ozet == "Dolap C, raf değişmedi")

            let temiz = TopluKitapIslemi.yer(dolap: "", raf: "", temizle: [.raf], [kitap])
            #expect(kitap.cabinet == "C")
            #expect(kitap.shelf == nil)
            #expect(temiz == "Dolap değişmedi, raf temizlendi")
        }
    }

    // MARK: Toplu geri alma

    @Test func topluGeriAlmaUygulanirBayatVeKayipAyrilir() {
        let kapak = Data([1, 2, 3])
        let eski = Book(title: "Eski ad", author: "A")
        var yeni = eski
        yeni.title = "Yeni ad"
        let degisim = TopluGeriAlma.Degisim(before: eski.hafif, after: yeni.hafif)

        var simdi = yeni
        simdi.coverData = kapak
        let uygulanan = TopluGeriAlma.plan([degisim], guncel: [yeni.id: simdi])
        #expect(uygulanan.uygulanan.count == 1)
        #expect(uygulanan.uygulanan.first?.title == "Eski ad")
        #expect(uygulanan.uygulanan.first?.coverData == kapak)

        var sonradan = yeni
        sonradan.author = "Başka"
        let bayat = TopluGeriAlma.plan([degisim], guncel: [yeni.id: sonradan])
        #expect(bayat.uygulanan.isEmpty)
        #expect(bayat.bayat == [yeni.id])

        let kayip = TopluGeriAlma.plan([degisim], guncel: [:])
        #expect(kayip.kayip == [yeni.id])
        #expect(kayip.atlanan == 1)
    }

    @Test func degisimlerYalnizGercektenDegisenleriAlir() {
        let ilk = Book(title: "Değişen", author: "A")
        let ikinci = Book(title: "Aynı", author: "B")
        var ilkSonra = ilk
        ilkSonra.category = "Roman"
        let sonuc = TopluGeriAlma.degisimler(before: [ilk.id: ilk, ikinci.id: ikinci], after: [ilkSonra, ikinci])
        #expect(sonuc.count == 1)
        #expect(sonuc.first?.after.id == ilk.id)
    }

    @Test func geriAlmaKaydiDiskeYazilipOkunur() {
        let url = geciciURL("toplu.json")
        defer { try? FileManager.default.removeItem(at: url) }
        let kitap = Book(title: "Eser", author: "A")
        let kayit = CatalogBulkUndoRecord(ozet: "1 kitap taşındı.", degisimler: [.init(before: kitap, after: kitap)])
        #expect(CatalogBulkUndoStore.kaydet(kayit, to: url))
        #expect(CatalogBulkUndoStore.oku(from: url)?.ozet == "1 kitap taşındı.")
        CatalogBulkUndoStore.temizle(at: url)
        #expect(CatalogBulkUndoStore.oku(from: url) == nil)
    }

    // MARK: Kategori

    @Test func kategoriAdiBosuKategorisizYapar() throws {
        try izole { context in
            let nil_ = CatalogBook(book: Book(title: "a", author: "", category: nil))
            let bos = CatalogBook(book: Book(title: "b", author: "", category: ""))
            let bosluk = CatalogBook(book: Book(title: "c", author: "", category: "  "))
            let roman = CatalogBook(book: Book(title: "d", author: "", category: " Roman "))
            [nil_, bos, bosluk, roman].forEach { context.insert($0) }
            #expect(nil_.kategoriAdi == "Kategorisiz")
            #expect(bos.kategoriAdi == "Kategorisiz")
            #expect(bosluk.kategoriAdi == "Kategorisiz")
            #expect(roman.kategoriAdi == "Roman")
            let dagilim = KategoriDagilimi.hesapla([nil_, bos, bosluk, roman])
            #expect(dagilim.first?.ad == "Kategorisiz")
            #expect(dagilim.first?.baslik == 3)
            // Boş kategorili kitap "Kategorisiz" süzgecinden geçer.
            let suzulen = KitapFiltresi(kategori: "Kategorisiz").suz([nil_, bos, bosluk, roman], oduncSayilari: [:])
            #expect(suzulen.count == 3)
        }
    }

    // MARK: CSV

    @Test func csvGecersizISBNAtlananlaraDuserVeHamDegerNottaKalir() {
        let csv = "Kitap Adı;ISBN\nBir;9789750718435\nİki;9789750718434\nÜç;123\n"
        let sonuc = CSVImporter.parseDetayli(Data(csv.utf8))
        #expect(sonuc.books.count == 3)
        #expect(sonuc.atlananISBN.count == 2)
        #expect(sonuc.atlananISBN.first?.satir == 2)
        #expect(sonuc.atlananISBN.first?.ham == "9789750718435")
        #expect(sonuc.books[0].isbn == nil)
        #expect(sonuc.books[0].notes.contains("Ham ISBN: 9789750718435"))
        #expect(sonuc.books[1].isbn == "9789750718434")
        #expect(CSVImporter.parse(Data(csv.utf8)).count == 3)
    }

    // MARK: Filtre

    @Test func filtreEskiKayitlarYeniAlanlarOlmadanCozulur() throws {
        let eski = Data(#"{"durum":"Tümü","kategori":"Roman"}"#.utf8)
        let filtre = try JSONDecoder().decode(KitapFiltresi.self, from: eski)
        #expect(filtre.kategori == "Roman")
        #expect(filtre.eksikAlan == nil)
        #expect(filtre.sonOduncGun == nil)
        #expect(filtre.eklenmeSonGun == nil)
        let yeni = KitapFiltresi(eksikAlan: "ISBN", sonOduncGun: 90, eklenmeSonGun: 30)
        let tur = try JSONDecoder().decode(KitapFiltresi.self, from: JSONEncoder().encode(yeni))
        #expect(tur == yeni)
        #expect(yeni.aktifSayisi == 3)
    }

    @Test func eksikAlanSonOduncVeEklenmeSuzgecleri() throws {
        try izole { context in
            let isbnli = CatalogBook(book: Book(title: "A", author: "x", isbn: "9789750718434"))
            let isbnsiz = CatalogBook(book: Book(title: "B", author: "x"))
            context.insert(isbnli); context.insert(isbnsiz)
            let eksikler = KitapFiltresi(eksikAlan: "ISBN").suz([isbnli, isbnsiz], oduncSayilari: [:])
            #expect(eksikler.map(\.title) == ["B"])

            let yakin = Set([isbnli.id])
            let oduncsuz = KitapFiltresi(sonOduncGun: 90).suz([isbnli, isbnsiz], oduncSayilari: [:], yakinOduncler: yakin)
            #expect(oduncsuz.map(\.title) == ["B"])

            let yeniler = KitapFiltresi(eklenmeSonGun: 1).suz([isbnli, isbnsiz], oduncSayilari: [:])
            #expect(yeniler.count == 2)
            let uzak = Calendar.current.date(byAdding: .day, value: 10, to: .now) ?? .now
            #expect(KitapFiltresi(eklenmeSonGun: 1).suz([isbnli], oduncSayilari: [:], now: uzak).isEmpty)
        }
    }

    @Test func hazirFiltrelerGecerliSuzgecUretir() {
        for hazir in HazirFiltre.allCases { #expect(hazir.filtre.aktifSayisi == 1) }
    }

    // MARK: Sıralama ve liste hesabı

    @Test func siralayiciAdYazarVeSeriSirasi() {
        let a = SiralamaOgesi(id: UUID(), title: "Zeytin", author: "Ali", cilt: 2)
        let b = SiralamaOgesi(id: UUID(), title: "Armut", author: "Zeki", cilt: 1)
        #expect(KitapSiralayici.sirala([a, b], siralama: .ad, seriSecili: false) == [b.id, a.id])
        #expect(KitapSiralayici.sirala([a, b], siralama: .yazar, seriSecili: false) == [a.id, b.id])
        #expect(KitapSiralayici.sirala([a, b], siralama: .ad, seriSecili: true) == [b.id, a.id])
    }

    @Test func listeHesabiAyniAnahtardaYenidenHesaplanmaz() {
        let anahtar = HesapAnahtari(filtre: KitapFiltresi(), siralama: "Ada göre", kitapSayisi: 3, loanSayisi: 0,
                                    copySayisi: 0, reservationSayisi: 0, parmakIzi: 1)
        let hesap = ListeHesabi(anahtar: anahtar, kitaplar: [], stoklar: [:], gecikmis: [])
        #expect(!ListeHesabi.yenidenGerekli(mevcut: hesap, anahtar: anahtar))
        var degisen = anahtar
        degisen.parmakIzi = 2
        #expect(ListeHesabi.yenidenGerekli(mevcut: hesap, anahtar: degisen))
        #expect(ListeHesabi.yenidenGerekli(mevcut: nil, anahtar: anahtar))
    }

    @Test func hesapAnahtariAdDegisiminiYakalar() throws {
        try izole { context in
            let kitap = CatalogBook(book: Book(title: "Eski", author: "A"))
            context.insert(kitap)
            let once = HesapAnahtari.kur(filtre: KitapFiltresi(), siralama: "x", kitaplar: [kitap], loans: [], copies: [], reservations: [])
            kitap.title = "Yeni"
            let sonra = HesapAnahtari.kur(filtre: KitapFiltresi(), siralama: "x", kitaplar: [kitap], loans: [], copies: [], reservations: [])
            #expect(once != sonra)
            #expect(once.kitapSayisi == sonra.kitapSayisi)
        }
    }

    // MARK: Öneriler

    @Test func enSikOneriBosuAtarBuyukKucukHarfiBirlestirir() {
        let sonuc = KategoriOnerileri.enSik(["Roman", "roman", nil, "", "Şiir", "Tarih", "Tarih", "Tarih"], limit: 2)
        #expect(sonuc == ["Tarih", "Roman"])
    }

    // MARK: Spotlight

    @Test func spotlightFarkiEklenenDegisenVeSilinenleriAyirir() {
        let a = SpotlightIndexer.Entry(id: "a", title: "A", author: "x", isbn: "", isWithdrawn: false)
        let b = SpotlightIndexer.Entry(id: "b", title: "B", author: "y", isbn: "", isWithdrawn: false)
        let eski = ["a": SpotlightIndexer.ozet(a)]

        let ayni = SpotlightIndexer.fark(eski: eski, yeni: [a])
        #expect(ayni.eklenecek.isEmpty && ayni.silinecek.isEmpty)

        let eklendi = SpotlightIndexer.fark(eski: eski, yeni: [a, b])
        #expect(eklendi.eklenecek == [b])

        let degisen = SpotlightIndexer.Entry(id: "a", title: "A2", author: "x", isbn: "", isWithdrawn: false)
        #expect(SpotlightIndexer.fark(eski: eski, yeni: [degisen]).eklenecek == [degisen])

        #expect(SpotlightIndexer.fark(eski: eski, yeni: [b]).silinecek == ["a"])
        let dusen = SpotlightIndexer.Entry(id: "a", title: "A", author: "x", isbn: "", isWithdrawn: true)
        #expect(SpotlightIndexer.fark(eski: eski, yeni: [dusen]).silinecek == ["a"])
    }

    // MARK: Yedek yazıcı

    @Test func yedekYaziciEskiRevizyonuYenininUzerineYazmaz() async throws {
        let url = geciciURL("yedek.json")
        defer { try? FileManager.default.removeItem(at: url) }
        let yazici = BackupWriter()
        let yeni = [Book(title: "Revizyon 2", author: "A")]
        let eski = [Book(title: "Revizyon 1", author: "A")]
        #expect(await yazici.yaz(revizyon: 2, books: yeni, url: url) == .yazildi)
        #expect(await yazici.yaz(revizyon: 1, books: eski, url: url) == .atlandi)
        let icerik = CatalogBackup.decode(try Data(contentsOf: url))
        #expect(icerik.first?.title == "Revizyon 2")
    }

    @Test func yedekYaziciHatayiGorunurKilar() async {
        let yazici = BackupWriter()
        let gecersiz = URL(fileURLWithPath: "/var/empty/olmayan-klasor/yedek.json")
        let sonuc = await yazici.yaz(revizyon: 1, books: [], url: gecersiz)
        if case .hata = sonuc {} else { Issue.record("Yazma hatası .hata olarak dönmeli: \(sonuc)") }
    }
}
