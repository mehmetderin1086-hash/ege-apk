import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import _01

/// Katalog aramasının veritabanı koşulu, SwiftData'nın SQL'e çevirebildiği
/// ifadelerden kurulmalı. `(book.isbn ?? "")` yazımı uygulamayı arama kutusuna
/// yazılan ilk harfte çökertiyordu ("unimplemented SQL generation for
/// predicate: TERNARY(...) CONTAINS"); bu testler o hatayı yakalar.
@MainActor
struct KatalogAramaKosuluTestleri {
    private func bellekIciBaglam() throws -> ModelContext {
        let kap = try ModelContainer(
            for: CatalogBook.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let baglam = ModelContext(kap)
        let isbnli = Book(title: "Şeker Portakalı", author: "Vasconcelos", isbn: "9789750718434")
        // ISBN'i olmayan kayıt: çökmeye yol açan durum tam buydu
        let isbnsiz = Book(title: "Tutunamayanlar", author: "Oğuz Atay", isbn: nil)
        baglam.insert(CatalogBook(book: isbnli))
        baglam.insert(CatalogBook(book: isbnsiz))
        try baglam.save()
        return baglam
    }

    private func adlar(_ baglam: ModelContext, terim: String) throws -> [String] {
        let kosul = CatalogQueryView<EmptyView>.searchPredicate(term: terim)
        let sonuc = try baglam.fetch(FetchDescriptor<CatalogBook>(predicate: kosul))
        return sonuc.map(\.title).sorted()
    }

    /// Metin araması çökmeden çalışmalı (ISBN'i nil olan kayıt varken bile).
    @Test func metinAramasiCokmez() throws {
        let baglam = try bellekIciBaglam()
        #expect(try adlar(baglam, terim: "Ş") == ["Şeker Portakalı"])
        #expect(try adlar(baglam, terim: "şeker") == ["Şeker Portakalı"])
        #expect(try adlar(baglam, terim: "oğuz") == ["Tutunamayanlar"])
        #expect(try adlar(baglam, terim: "bulunmayan").isEmpty)
    }

    /// ISBN parçasıyla arama da veritabanı koşulundan geçmeli.
    @Test func isbnParcasiEslesir() throws {
        let baglam = try bellekIciBaglam()
        #expect(try adlar(baglam, terim: "97897") == ["Şeker Portakalı"])
        #expect(try adlar(baglam, terim: "0718434") == ["Şeker Portakalı"])
    }
}

@MainActor
struct ISBNTestleri {
    @Test func gecerliISBN13Dogrulanir() {
        #expect(ISBNFormatter.isValidISBN13("9789750718533"))
        #expect(ISBNFormatter.isValidISBN13("9786050962970"))
    }

    @Test func bozukKontrolBasamagiReddedilir() {
        #expect(!ISBNFormatter.isValidISBN13("9789750718534"))
        #expect(!ISBNFormatter.isValidISBN13("12345"))
        #expect(!ISBNFormatter.isValidISBN13(""))
    }

    @Test func isbn10dan13eCevrilir() {
        #expect(ISBNFormatter.normalize("9750718533") == "9789750718533")
    }

    /// Barkodla arama: rakam ağırlıklı metin barkod sayılır, kitap adları sayılmaz.
    @Test func barkodAramasiTaninir() {
        #expect(ISBNFormatter.isBarcodeQuery("9789753638029"))
        #expect(ISBNFormatter.isBarcodeQuery("978-975-363-802-9"))
        #expect(ISBNFormatter.isBarcodeQuery("2000000000012"))
        #expect(!ISBNFormatter.isBarcodeQuery("1984"))
        #expect(!ISBNFormatter.isBarcodeQuery("Yüzbaşının Kızı"))
        #expect(!ISBNFormatter.isBarcodeQuery("Fahrenheit 451 roman baskı 2020"))
    }

    @Test func ocrHarfHatalariOnarilir() {
        // O→0 gibi OCR karışıklıkları düzeltilmeli
        #expect(ISBNFormatter.repair("978-6O5-O9-6297-O") == "9786050962970")
        #expect(ISBNFormatter.repair("ISBN yok") == "")
    }
}

@MainActor
struct EslestirmeTestleri {
    @Test func aksanFarkiAyniKitaptir() {
        #expect(CatalogMatcher.isSimilar("Yüzbaşının Kızı", "Yüzbasının Kızı"))
        #expect(CatalogMatcher.isSimilar("Suç ve Ceza", "SUÇ VE CEZA"))
    }

    @Test func tekHarfHatasiAyniKitaptir() {
        #expect(CatalogMatcher.isSimilar("Kürk Mantolu Madonna", "Kürk Mantolu Madona"))
    }

    @Test func farkliKitaplarKaristirilmaz() {
        #expect(!CatalogMatcher.isSimilar("Suç ve Ceza", "Savaş ve Barış"))
        #expect(!CatalogMatcher.isSimilar("1984", "1985"))
        #expect(!CatalogMatcher.isSimilar("", "Deneme"))
    }
}

@MainActor
struct DuzeltmeBellegiTestleri {
    @Test func benzerDuzeltmeOgrenilirVeUygulanir() {
        CorrectionMemory.reset()
        CorrectionMemory.learn(ocrText: "Yüzbasının Kızı", correctedText: "Yüzbaşının Kızı")
        #expect(CorrectionMemory.correct("Yüzbasının Kızı") == "Yüzbaşının Kızı")
        // Aksan farkı dışında aynı yazım da düzeltilmiş hâli bulur
        #expect(CorrectionMemory.correct("yüzbasinin kizi") == "Yüzbaşının Kızı")
        CorrectionMemory.reset()
    }

    @Test func tamamenFarkliMetinOgrenilmez() {
        CorrectionMemory.reset()
        CorrectionMemory.learn(ocrText: "Suç ve Ceza", correctedText: "Savaş ve Barış")
        #expect(CorrectionMemory.correct("Suç ve Ceza") == "Suç ve Ceza")
        #expect(CorrectionMemory.count == 0)
    }

    @Test func kisaVeAyniMetinlerAtlanir() {
        CorrectionMemory.reset()
        CorrectionMemory.learn(ocrText: "abc", correctedText: "abd")
        CorrectionMemory.learn(ocrText: "Aynı Metin", correctedText: "Aynı Metin")
        #expect(CorrectionMemory.count == 0)
    }
}

@MainActor
struct SirtEtiketiTestleri {
    @Test func yerNumarasiKategoriVeYazardanUretilir() {
        let number = SpineLabelBuilder.callNumber(category: "Tarih", author: "Ahmet Ümit")
        // Büyütme artık cihaz yerelinden bağımsız Türkçe kuralla yapılır (i → İ)
        #expect(number == "TAR / ÜMİ")
    }

    @Test func kategoriYoksaGenelKullanilir() {
        let number = SpineLabelBuilder.callNumber(category: nil, author: "Orhan Pamuk")
        #expect(number.hasPrefix("GEN"))
    }

    @Test func yazarBosSaAltCizgiKullanilir() {
        let number = SpineLabelBuilder.callNumber(category: "Roman", author: "")
        #expect(number.contains("___"))
    }
}

@MainActor
struct ArsivTestleri {
    /// Kapaklar dahil ZIP arşivi yazılıp aynı içerikle geri okunmalı.
    @Test func zipArsiviYazilipGeriOkunur() throws {
        let cover = Data([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3, 4])
        let books = [
            Book(title: "Kürk Mantolu Madonna", author: "Sabahattin Ali",
                 isbn: "9789750718533", coverData: cover),
            Book(title: "Kapaksız Kitap", author: "Deneme Yazar")
        ]

        let archive = FullArchive.build(books: books)
        #expect(archive.count > 100)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-arsiv-\(UUID().uuidString).zip")
        try archive.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let restored = FullArchive.restore(from: url)
        #expect(restored.count == 2)

        let withCover = restored.first { $0.title == "Kürk Mantolu Madonna" }
        #expect(withCover?.isbn == "9789750718533")
        #expect(withCover?.coverData == cover)

        let withoutCover = restored.first { $0.title == "Kapaksız Kitap" }
        #expect(withoutCover?.coverData == nil)
    }

    @Test func bozukArsivBosDoner() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bozuk-\(UUID().uuidString).zip")
        try? Data("bu bir zip değil".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(FullArchive.restore(from: url).isEmpty)
    }
}

@MainActor
struct SayimVeGorunumTestleri {
    @Test func sayimOturumuDiskeYazilipOkunur() {
        InventorySessionStore.clear()
        let session = InventorySession(
            scanned: ["9789750718533": 2],
            unknown: ["1234567890128": 1],
            location: "Depo A",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        InventorySessionStore.save(session)

        let loaded = InventorySessionStore.load()
        #expect(loaded.scanned["9789750718533"] == 2)
        #expect(loaded.unknown["1234567890128"] == 1)
        #expect(loaded.location == "Depo A")
        #expect(loaded.startedAt == Date(timeIntervalSince1970: 1_700_000_000))

        InventorySessionStore.clear()
        #expect(InventorySessionStore.load().scanned.isEmpty)
    }

    @Test func kayitliGorunumEklenirVeSilinir() {
        for view in SavedViewStore.all() { SavedViewStore.remove(id: view.id) }

        let view = SavedView(
            name: "B dolabı eksikleri",
            layout: "Liste",
            filter: "Eksik Bilgi",
            sort: "Ada göre",
            searchText: "B"
        )
        SavedViewStore.add(view)
        #expect(SavedViewStore.all().count == 1)
        #expect(SavedViewStore.all().first?.filter == "Eksik Bilgi")

        // Aynı ad tekrar kaydedilince çoğaltmaz, güncellenir
        SavedViewStore.add(
            SavedView(name: "B dolabı eksikleri", layout: "Raflar",
                      filter: "Tümü", sort: "Ada göre", searchText: "")
        )
        #expect(SavedViewStore.all().count == 1)
        #expect(SavedViewStore.all().first?.layout == "Raflar")

        for saved in SavedViewStore.all() { SavedViewStore.remove(id: saved.id) }
        #expect(SavedViewStore.all().isEmpty)
    }
}

@MainActor
struct OgrenciTestleri {
    @Test func csvdenOgrenciIceAktarilir() {
        for s in StudentStore.all() { StudentStore.remove(id: s.id) }
        let csv = "Ad;Numara;Sınıf\nAyşe Yılmaz;101;9-A\nMehmet Kaya;102;9-A\nZeynep Ak;201;10-B\n"
        let satirlar = OgrenciCSVEslestirme.satirlar(Data(csv.utf8))
        let count = (try? StudentStore.importVerified(OgrenciCSVEslestirme.ogrenciler(satirlar, ad: 0, no: 1, sinif: 2, baslikVar: true))) ?? 0
        #expect(count == 3)
        #expect(StudentStore.classNames() == ["10-B", "9-A"])
        #expect(StudentStore.students(in: "9-A").count == 2)
        for s in StudentStore.all() { StudentStore.remove(id: s.id) }
    }

    @Test func kartBarkoduNumaradanUretilir() {
        let withNumber = Student(name: "Ayşe Yılmaz", number: "101", className: "9-A")
        #expect(StudentCardBuilder.barcodeValue(for: withNumber) == "OGRID" + withNumber.id.uuidString.replacingOccurrences(of: "-", with: ""))

        let withoutNumber = Student(name: "Mehmet Kaya", number: "", className: "9-A")
        let value = StudentCardBuilder.barcodeValue(for: withoutNumber)
        #expect(value.hasPrefix("OGR"))
        #expect(value.count > 3)
    }
}

@MainActor
struct KademeKuraliTestleri {
    @Test func enUzunOnekEslesir() {
        GradeLoanRuleStore.save([
            GradeLoanRule(gradePrefix: "9", maxConcurrentLoans: 2, loanDurationDays: 10),
            GradeLoanRule(gradePrefix: "9-A", maxConcurrentLoans: 5, loanDurationDays: 20)
        ])
        let rule = GradeLoanRuleStore.rule(for: "9-A")
        #expect(rule.loanDurationDays == 20)
        #expect(rule.maxConcurrentLoans == 5)

        let other = GradeLoanRuleStore.rule(for: "9-B")
        #expect(other.loanDurationDays == 10)

        GradeLoanRuleStore.save([])
    }

    /// "1" önekli kural 1. sınıflara uyar; "10-A", "11-B" gibi sınıflara taşmaz.
    @Test func rakamOnekiSonrakiBasamagaTasmaz() {
        let kurallar = [GradeLoanRule(gradePrefix: "1", maxConcurrentLoans: 1, loanDurationDays: 7)]
        #expect(GradeLoanRuleStore.explicitRule(for: "1-A", rules: kurallar)?.maxConcurrentLoans == 1)
        #expect(GradeLoanRuleStore.explicitRule(for: "1A", rules: kurallar)?.maxConcurrentLoans == 1)
        #expect(GradeLoanRuleStore.explicitRule(for: "10-A", rules: kurallar) == nil)
        #expect(GradeLoanRuleStore.explicitRule(for: "12/C", rules: kurallar) == nil)
    }

    @Test func kuralYoksaVarsayilanDoner() {
        GradeLoanRuleStore.save([])
        let rule = GradeLoanRuleStore.rule(for: "11-C")
        #expect(rule.loanDurationDays == 15)
        #expect(rule.maxConcurrentLoans == 3)
    }
}

@MainActor
struct UyeTestleri {
    @Test func ayniAdIkiKezEklenmez() {
        for m in MemberStore.all() { MemberStore.remove(id: m.id) }
        MemberStore.add(Member(name: "Ayşe Yılmaz"))
        MemberStore.add(Member(name: "ayşe yılmaz")) // aynı ad, farklı harf
        #expect(MemberStore.all().count == 1)
        for m in MemberStore.all() { MemberStore.remove(id: m.id) }
    }

    @Test func onerilerYazilanMetneGoreSuzulur() {
        for m in MemberStore.all() { MemberStore.remove(id: m.id) }
        MemberStore.add(Member(name: "Ayşe Yılmaz"))
        MemberStore.add(Member(name: "Mehmet Kaya"))
        let suggestions = MemberStore.suggestions(matching: "ays")
        #expect(suggestions.contains { $0.name == "Ayşe Yılmaz" })
        #expect(!suggestions.contains { $0.name == "Mehmet Kaya" })
        for m in MemberStore.all() { MemberStore.remove(id: m.id) }
    }
}

@MainActor
struct OduncGecmisiTestleri {
    @Test func kisiOzetiVerVeIadeSayar() {
        LoanHistoryStore.reset()
        let bookID = UUID()
        LoanHistoryStore.record(
            LoanEvent(bookID: bookID, bookTitle: "Deneme", person: "Ayşe",
                      kind: .lent, date: .now)
        )
        LoanHistoryStore.record(
            LoanEvent(bookID: bookID, bookTitle: "Deneme", person: "Ayşe",
                      kind: .returned, date: .now, wasLate: true)
        )

        let people = LoanHistoryStore.people()
        #expect(people.count == 1)
        #expect(people.first?.totalLoans == 1)
        #expect(people.first?.totalReturns == 1)
        #expect(people.first?.lateReturns == 1)
        #expect(people.first?.activeCount == 0)
        LoanHistoryStore.reset()
    }

    @Test func elindekiKitapSayisiHesaplanir() {
        LoanHistoryStore.reset()
        for index in 1...3 {
            LoanHistoryStore.record(
                LoanEvent(bookID: UUID(), bookTitle: "Kitap \(index)", person: "Mehmet",
                          kind: .lent, date: .now)
            )
        }
        LoanHistoryStore.record(
            LoanEvent(bookID: UUID(), bookTitle: "Kitap 1", person: "Mehmet",
                      kind: .returned, date: .now)
        )
        #expect(LoanHistoryStore.people().first?.activeCount == 2)
        LoanHistoryStore.reset()
    }
}

@MainActor
struct CSVTestleri {
    @Test func turkceBasliklarVeNoktaliVirgul() {
        let csv = "Kitap Adı;Yazar;Yayınevi;ISBN-13;Basım Yılı;Sayfa Sayısı;Adet;Raf\nSuç ve Ceza;Dostoyevski;İş Bankası;9786053320531;2019;687;2;A3\n"
        let books = CSVImporter.parse(Data(csv.utf8))
        #expect(books.count == 1)
        #expect(books.first?.title == "Suç ve Ceza")
        #expect(books.first?.isbn == "9786053320531")
        #expect(books.first?.publicationYear == "2019")
        #expect(books.first?.pageCount == "687")
        #expect(books.first?.quantity == 2)
        #expect(books.first?.shelf == "A3")
    }

    @Test func tirnakIcindekiVirgulKorunur() {
        let csv = "Title,Author\n\"Kürk Mantolu, Madonna\",Sabahattin Ali\n"
        let books = CSVImporter.parse(Data(csv.utf8))
        #expect(books.count == 1)
        #expect(books.first?.title == "Kürk Mantolu, Madonna")
        #expect(books.first?.author == "Sabahattin Ali")
    }

    /// Sütun eşleme başlık sırasına değil anahtar önceliğine bakar; "ad" anahtarı
    /// "Yazar Adı" ya da "Adet" sütununu kitap adı sanmaz, "Yayıncı" tanınır.
    @Test func sutunEslemeAltDizeyeAldanmaz() {
        let csv = "Yazar Adı;Adet;Kitap Adı;Yayıncı;Yayın Yılı\nDostoyevski;2;Suç ve Ceza;İş Bankası;2019\n"
        let books = CSVImporter.parse(Data(csv.utf8))
        #expect(books.count == 1)
        #expect(books.first?.title == "Suç ve Ceza")
        #expect(books.first?.author == "Dostoyevski")
        #expect(books.first?.quantity == 2)
        #expect(books.first?.publisher == "İş Bankası")
        #expect(books.first?.publicationYear == "2019")
    }

    /// Okul katalog dışa aktarımlarındaki "Yayın Adı" başlığı kitap adı sayılır.
    @Test func yayinAdiBasligiKitapAdidir() {
        let csv = "Yayın Adı;Yazar;Yayınevi\nNutuk;Atatürk;YKY\n"
        let books = CSVImporter.parse(Data(csv.utf8))
        #expect(books.first?.title == "Nutuk")
        #expect(books.first?.publisher == "YKY")
    }

    @Test func kisaVeEkliBasliklarTaninir() {
        let csv = "Adı;Yazarı;Rafı;Notlar\nNutuk;Atatürk;B2;imzalı\n"
        let books = CSVImporter.parse(Data(csv.utf8))
        #expect(books.first?.title == "Nutuk")
        #expect(books.first?.author == "Atatürk")
        #expect(books.first?.shelf == "B2")
        #expect(books.first?.notes == "imzalı")
    }

    @Test func adiOlmayanSatirAtlanir() {
        let csv = "Kitap Adı;Yazar\n;Adsız Yazar\nGerçek Kitap;Yazar Adı\n"
        let books = CSVImporter.parse(Data(csv.utf8))
        #expect(books.count == 1)
        #expect(books.first?.title == "Gerçek Kitap")
    }
}

@MainActor
struct AmazonAyristirmaTestleri {
    /// Amazon'ın yeni ürün sayfası düzeni (rpi-attribute blokları) — gerçek sayfadan alınmış parça.
    @Test func yeniDuzendenSayfaVeYayinevi() {
        let html = """
        <span id="productTitle">Türkiye'nin Bütün Ağaçları ve Çalıları</span>
        <div class="rpi-attribute-label"> <span>Baskı Uzunluğu</span></div>
        <div class="a-section a-text-center rpi-attribute-value"> <span>1368 sayfa</span> </div>
        <div class="rpi-attribute-label"> <span>Dil</span></div>
        <div class="rpi-attribute-value"> <span>Türkçe</span> </div>
        <div class="rpi-attribute-label"> <span>Yayıncı</span></div>
        <div class="rpi-attribute-value"> <span>İş Bankası Kültür Yayınları</span> </div>
        <div class="rpi-attribute-label"> <span>Yayınlanma Tarihi</span></div>
        <div class="rpi-attribute-value"> <span>9 Ocak 2021</span> </div>
        <div class="rpi-attribute-label"> <span>ISBN-13</span></div>
        <div class="rpi-attribute-value"> <span>978-6254051722</span> </div>
        """
        let meta = AmazonBookScraper.parseProduct(html: html, fallbackISBN: "")

        #expect(meta.title == "Türkiye'nin Bütün Ağaçları ve Çalıları")
        #expect(meta.pageCount == "1368")
        #expect(meta.publisher == "İş Bankası Kültür Yayınları")
        #expect(meta.publicationYear == "2021")
        #expect(meta.language == "Türkçe")
        #expect(meta.isbn == "9786254051722")
    }

    /// Kapak adresindeki boyut belirteci kaldırılıp tam çözünürlük istenmeli.
    @Test func kapakAdresiTamCozunurlukOlur() {
        #expect(
            AmazonBookScraper.fullResolutionImageURL(
                "https://m.media-amazon.com/images/I/81nEOUjMQ4L._SY522_.jpg"
            ) == "https://m.media-amazon.com/images/I/81nEOUjMQ4L.jpg"
        )
        #expect(
            AmazonBookScraper.fullResolutionImageURL(
                "https://m.media-amazon.com/images/I/71abcd._SL500_.jpg"
            ) == "https://m.media-amazon.com/images/I/71abcd.jpg"
        )
        #expect(
            AmazonBookScraper.fullResolutionImageURL(
                "https://m.media-amazon.com/images/I/71abcd.jpg"
            ) == "https://m.media-amazon.com/images/I/71abcd.jpg"
        )
    }

    /// Eski düzen (detay listesi) çalışmaya devam etmeli.
    @Test func eskiDuzenBozulmadi() {
        let html = """
        <span id="productTitle">Deneme Kitabı</span>
        <div id="detailBullets_feature_div"><ul>
        <li><span class="a-list-item">Yayıncı : Deneme Yayınları</span></li>
        <li><span class="a-list-item">Baskı uzunluğu : 352 sayfa</span></li>
        </ul>
        """
        let meta = AmazonBookScraper.parseProduct(html: html, fallbackISBN: "")
        #expect(meta.pageCount == "352")
        #expect(meta.publisher == "Deneme Yayınları")
    }
}

@MainActor
struct KitapyurduAyristirmaTestleri {
    /// Kitapyurdu ürün sayfası düzeni: başlık, yazar, yayınevi ve özellik tablosu.
    @Test func urunSayfasindanTumAlanlarCikar() {
        let html = """
        <h1 class="pr_header__heading">Kürk Mantolu Madonna</h1>
        <div class="pr_producers__manufacturer"><a href="/yazar/sabahattin-ali/1.html">Sabahattin Ali</a></div>
        <div class="pr_producers__publisher"><a href="/yayinevi/yky/2.html">Yapı Kredi Yayınları</a></div>
        <meta property="og:image" content="https://img.kitapyurdu.com/v1/getImage/fn:11439806/wh:true/wi:220">
        <div class="attributes"><table>
        <tr><td class="attr-name">Sayfa Sayısı:</td><td>160</td></tr>
        <tr><td class="attr-name">İlk Basım Yılı:</td><td>1943</td></tr>
        <tr><td class="attr-name">Basım Tarihi:</td><td>Ocak 2021</td></tr>
        <tr><td class="attr-name">ISBN:</td><td>9789753638029</td></tr>
        <tr><td class="attr-name">Dil:</td><td>TÜRKÇE</td></tr>
        </table></div>
        """
        let meta = KitapyurduScraper.parseProduct(html: html, fallbackISBN: "")

        #expect(meta.title == "Kürk Mantolu Madonna")
        #expect(meta.author == "Sabahattin Ali")
        #expect(meta.publisher == "Yapı Kredi Yayınları")
        #expect(meta.pageCount == "160")
        #expect(meta.publicationYear == "1943")
        #expect(meta.isbn == "9789753638029")
        #expect(meta.language == "Türkçe")
        #expect(meta.coverURL?.absoluteString == "https://img.kitapyurdu.com/v1/getImage/fn:11439806/wh:true/wi:800")
    }

    /// Başlık etiketi bulunamazsa og:title yedeği devreye girmeli.
    @Test func baslikYedegiOgTitle() {
        let html = #"<meta property="og:title" content="Şeker Portakalı">"#
        let meta = KitapyurduScraper.parseProduct(html: html, fallbackISBN: "9789750718434")
        #expect(meta.title == "Şeker Portakalı")
        #expect(meta.isbn == "9789750718434")
    }

    /// Görsel adresindeki genişlik belirteci büyütülmeli, belirteçsiz adres bozulmamalı.
    @Test func kapakAdresiBuyukBoyIster() {
        #expect(
            KitapyurduScraper.highResolutionImageURL("https://img.kitapyurdu.com/v1/getImage/fn:123/wh:true/wi:220")
                == "https://img.kitapyurdu.com/v1/getImage/fn:123/wh:true/wi:800"
        )
        #expect(
            KitapyurduScraper.highResolutionImageURL("https://img.kitapyurdu.com/v1/getImage/fn:123")
                == "https://img.kitapyurdu.com/v1/getImage/fn:123"
        )
        // Güncel düzen genişliği miw/mih ile veriyor
        #expect(
            KitapyurduScraper.highResolutionImageURL("https://img.kitapyurdu.com/v1/getImage/fn:123/wh:abc/miw:200/mih:200")
                == "https://img.kitapyurdu.com/v1/getImage/fn:123/wh:abc/miw:800/mih:800"
        )
    }

    /// Kitapyurdu ISBN aramasına sonuç vermiyor: sorgular ad + yazar + yayınevi
    /// ile kurulmalı ve en belirleyiciden en genişe doğru denenmeli.
    @Test func aramaSorgulariAdYazarYayineviIle() {
        let queries = KitapyurduScraper.searchQueries(
            title: "Kürk Mantolu Madonna",
            author: "Sabahattin Ali, Hazırlayan",
            publisher: "Yapı Kredi Yayınları"
        )
        #expect(queries == [
            "Kürk Mantolu Madonna Sabahattin Ali Yapı Kredi Yayınları",
            "Kürk Mantolu Madonna Sabahattin Ali",
            "Kürk Mantolu Madonna Yapı Kredi Yayınları",
            "Kürk Mantolu Madonna"
        ])
        // Yalnız ad varsa tek sorgu üretilir (aynı istek iki kez ağa çıkmaz)
        #expect(KitapyurduScraper.searchQueries(title: "Tutunamayanlar", author: "", publisher: "") == ["Tutunamayanlar"])
    }

    /// Arama sayfası satırlarından ad, yazar, yayınevi ve adres çıkmalı.
    @Test func aramaSonuclariAyristirilir() {
        let results = KitapyurduScraper.parseSearchResults(html: aramaHTML)

        #expect(results.count == 3)
        #expect(results.first?.title == "Kürk Mantolu Madonna")
        #expect(results.first?.author == "Sabahattin Ali")
        #expect(results.first?.publisher == "YAPI KREDİ YAYINLARI")
        #expect(results.last?.title == "Kuyucaklı Yusuf")
    }

    /// Gerçek sonuç adresleri kısa ömürlü arama belirteci taşıyor; aynı ürünün
    /// kapak ve ad bağlantıları sorgusuz adreste tek kayıtta birleşmeli.
    @Test func urunAdresiAramaParametrelerindenArindirilir() {
        let results = KitapyurduScraper.parseSearchResults(html: aramaHTML)
        #expect(results.first?.url.absoluteString == "https://www.kitapyurdu.com/kitap/kurk-mantolu-madonna/12064.html")
    }

    /// Aynı ad birden çok yayınevinden çıkıyorsa yayınevi eşleşen baskı seçilmeli.
    @Test func yayineviEslesenBaskiSecilir() {
        let best = KitapyurduScraper.bestMatch(
            in: KitapyurduScraper.parseSearchResults(html: aramaHTML),
            title: "Kürk Mantolu Madonna",
            author: "Sabahattin Ali",
            publisher: "Kapra Yayıncılık"
        )
        #expect(best?.publisher == "KAPRA YAYINCILIK")
        #expect(best?.url.absoluteString == "https://www.kitapyurdu.com/kitap/kurk-mantolu-madonna-ciltli/569235.html")
    }

    /// Yayınevi bilgisi yoksa yazar eşleşmesi yeterli; ada fazladan sözcük
    /// ekleyen baskı ("Ciltli") birebir addan geride kalmalı.
    @Test func yayineviYoksaBirebirAdKazanir() {
        let best = KitapyurduScraper.bestMatch(
            in: KitapyurduScraper.parseSearchResults(html: aramaHTML),
            title: "Kürk Mantolu Madonna",
            author: "Sabahattin Ali"
        )
        #expect(best?.url.absoluteString == "https://www.kitapyurdu.com/kitap/kurk-mantolu-madonna/12064.html")
    }

    /// Arayüzdeki baskı listesi için tüm uyan sonuçlar sıralı dönmeli; aranan adla
    /// baştan eşleşen kayıtlar, adı içinde geçiren başka kitaplardan önce gelmeli.
    @Test func adiBastanEslesenKayitlarOneGelir() {
        let html = """
        <a class="ky-product-title" href="https://www.kitapyurdu.com/kitap/aska-tutunamayanlar/1.html">Aşka Tutunamayanlar</a>
        <span class="ky-product-author"><a href="https://www.kitapyurdu.com/yazar/mubeccel-ozturk/5.html">Mübeccel Öztürk</a></span>
        <a class="ky-product-title" href="https://www.kitapyurdu.com/kitap/tutunamayanlar/2.html">Tutunamayanlar / Bütün Eserleri 1</a>
        <span class="ky-product-author"><a href="https://www.kitapyurdu.com/yazar/oguz-atay/9.html">Oğuz Atay</a></span>
        """
        let parsed = KitapyurduScraper.parseSearchResults(html: html)
        let ranked = KitapyurduScraper.rankedMatches(in: parsed, title: "Tutunamayanlar")

        #expect(ranked.count == 2)
        #expect(ranked.first?.title == "Tutunamayanlar / Bütün Eserleri 1")
        #expect(ranked.last?.title == "Aşka Tutunamayanlar")
        // bestMatch, listenin ilk kaydıyla aynı olmalı
        #expect(KitapyurduScraper.bestMatch(in: parsed, title: "Tutunamayanlar") == ranked.first)
    }

    /// Karşılaştırma biçimi sözcük sırasını korur (birebir eşleşme ölçümü için).
    @Test func sadeBicimSozcukSirasiniKorur() {
        #expect(KitapyurduScraper.normalizedPhrase("Kürk Mantolu Madonna (Ciltli)") == "kurk mantolu madonna ciltli")
        #expect(KitapyurduScraper.normalizedPhrase("  İÇİMİZDEKİ ŞEYTAN  ") == "icimizdeki seytan")
    }

    /// Kategori, ürün sayfasındaki "İlgili Kategoriler" yolundan en özel basamak
    /// olarak alınmalı; birden çok kategori varsa birincil yol esas alınır.
    @Test func kategoriIlgiliKategorilerYolundanCikar() {
        let html = """
        <h1 class="ky-pd-title">Kürk Mantolu Madonna</h1>
        <div class="ky-pd-attributes__categories">
          <p class="ky-pd-attributes__categories-title">İlgili Kategoriler:</p>
          <div class="ky-pd-attributes__category">
            <a href="https://www.kitapyurdu.com/kategori/kitap-edebiyat-roman-yerli/1_128_129.html" class="ky-pd-attributes__category-link">
              <span class="ky-pd-attributes__category-item">Kitap</span>
              <i class="fa fa-angle-right ky-pd-attributes__category-arrow"></i>
              <span class="ky-pd-attributes__category-item">Edebiyat</span>
              <i class="fa fa-angle-right ky-pd-attributes__category-arrow"></i>
              <span class="ky-pd-attributes__category-item ky-pd-attributes__category-item--last">Roman (Yerli)</span>
            </a>
          </div>
          <div class="ky-pd-attributes__category">
            <a href="https://www.kitapyurdu.com/kategori/kitap-cok-satanlar/1_9.html" class="ky-pd-attributes__category-link">
              <span class="ky-pd-attributes__category-item">Kitap</span>
              <span class="ky-pd-attributes__category-item ky-pd-attributes__category-item--last">Çok Satanlar</span>
            </a>
          </div>
        </div>
        """
        #expect(KitapyurduScraper.parseProduct(html: html, fallbackISBN: "").category == "Roman (Yerli)")
        // Kategori bölümü olmayan sayfada alan boş kalır (uydurma değer yazılmaz)
        #expect(KitapyurduScraper.parseCategory(html: "<h1 class=\"ky-pd-title\">X</h1>").isEmpty)

        // Özellik listesinde "Kategori:" satırı varsa oradan da okunur
        let etiketli = """
        <h1 class="ky-pd-title">Şeker Portakalı</h1>
        <div class="ky-pd-attributes__item">
          <span class="ky-pd-attributes__label">Kategori:</span>
          <span class="ky-pd-attributes__value">Çocuk Kitapları</span>
        </div>
        """
        #expect(KitapyurduScraper.parseProduct(html: etiketli, fallbackISBN: "").category == "Çocuk Kitapları")
    }

    /// Kitapyurdu kesme işaretini "&#039;" gibi sayısal varlık olarak veriyor;
    /// başlıklarda ham varlık kodu görünmemeli.
    @Test func htmlVarliklariCozulur() {
        #expect(KitapyurduScraper.decodeEntities("Orhun Yazıtları&#039;ndan") == "Orhun Yazıtları'ndan")
        #expect(KitapyurduScraper.decodeEntities("Joyce&#39;a") == "Joyce'a")
        #expect(KitapyurduScraper.decodeEntities("Shakespeare&#x27;den") == "Shakespeare'den")
        #expect(KitapyurduScraper.decodeEntities("Tutunamayanlar&#8217;da") == "Tutunamayanlar’da")
        #expect(KitapyurduScraper.decodeEntities("A &amp; B &quot;C&quot;") == "A & B \"C\"")
        // İki kez kodlanmış metin bozulmamalı ("&amp;" en sona bırakılır)
        #expect(KitapyurduScraper.decodeEntities("X&amp;#039;y") == "X&#039;y")

        let html = #"<a class="ky-product-title" href="https://www.kitapyurdu.com/kitap/x/1.html">Ölülerle Konuşmak &amp; Shakespeare&#039;den Joyce&#039;a</a>"#
        #expect(
            KitapyurduScraper.parseSearchResults(html: html).first?.title
                == "Ölülerle Konuşmak & Shakespeare'den Joyce'a"
        )
    }

    /// Ad örtüşmüyorsa yanlış kitap yazılmasın diye hiçbir sonuç seçilmemeli.
    @Test func adTutmazsaSonucSecilmez() {
        let results = KitapyurduScraper.parseSearchResults(html: aramaHTML)
        #expect(KitapyurduScraper.bestMatch(in: results, title: "Sefiller", author: "Victor Hugo") == nil)
    }

    /// Eşleştirme Türkçe karakter ve büyük/küçük harf farkına takılmamalı.
    @Test func eslestirmeTurkceKarakterDuyarsiz() {
        #expect(KitapyurduScraper.tokens("Kürk MANTOLU Madonna") == KitapyurduScraper.tokens("kurk mantolu madonna"))
        let results = KitapyurduScraper.parseSearchResults(html: aramaHTML)
        #expect(KitapyurduScraper.bestMatch(in: results, title: "kurk mantolu madonna")?.title == "Kürk Mantolu Madonna")
    }

    /// Sitenin güncel düzeninde alanlar schema.org JSON-LD düğümünden okunmalı.
    @Test func yeniDuzendeJSONLDdenAlanlarCikar() {
        let html = """
        <h1 class="ky-pd-title">Kürk Mantolu Madonna</h1>
        <script type="application/ld+json">
        {"@context":"https://schema.org","@graph":[
        {"@type":["Organization","OnlineStore"],"name":"Kitapyurdu"},
        {"@type":"Book","name":"Kürk Mantolu Madonna","image":"https://img.kitapyurdu.com/v1/getImage/fn:10515023/wi:200/wh:1f6b",
        "description":"Raif Efendi: kısa bir tanıtım.","isbn":"9786257999267","numberOfPages":176,
        "author":{"@type":"Person","name":"Sabahattin Ali"},
        "publisher":{"@type":"Organization","name":"TÜRKİYE İŞ BANKASI KÜLTÜR YAYINLARI"},
        "inLanguage":"tr","datePublished":"2023-04-13"}]}
        </script>
        """
        let meta = KitapyurduScraper.parseProduct(html: html, fallbackISBN: "")

        #expect(meta.title == "Kürk Mantolu Madonna")
        #expect(meta.author == "Sabahattin Ali")
        #expect(meta.publisher == "TÜRKİYE İŞ BANKASI KÜLTÜR YAYINLARI")
        #expect(meta.isbn == "9786257999267")
        #expect(meta.pageCount == "176")
        #expect(meta.publicationYear == "2023")
        #expect(meta.language == "Türkçe")
        // Tanıtım metninde noktalama korunur
        #expect(meta.notes == "Raif Efendi: kısa bir tanıtım.")
        #expect(meta.coverURL?.absoluteString == "https://img.kitapyurdu.com/v1/getImage/fn:10515023/wi:800/wh:1f6b")
    }

    /// JSON-LD kaldırılırsa güncel düzenin etiket/değer listesi ve bağlantıları yetmeli.
    @Test func yeniDuzenOzellikListesiOkunur() {
        let html = """
        <h1 class="ky-pd-title">Kuyucaklı Yusuf</h1>
        <span class="ky-pd-heading__author"><a href="https://www.kitapyurdu.com/yazar/sabahattin-ali/10306.html">Sabahattin Ali</a></span>
        <span class="ky-pd-heading__publisher"><a href="https://www.kitapyurdu.com/yayinevi/yky/2.html">Yapı Kredi Yayınları</a></span>
        <div class="ky-pd-attributes__grid">
          <div class="ky-pd-attributes__item">
            <span class="ky-pd-attributes__label">Yayın Tarihi:</span>
            <span class="ky-pd-attributes__value">13.04.2023</span>
          </div>
          <div class="ky-pd-attributes__item">
            <span class="ky-pd-attributes__label">ISBN:</span>
            <span class="ky-pd-attributes__value">9789753638029</span>
          </div>
          <div class="ky-pd-attributes__item">
            <span class="ky-pd-attributes__label">Sayfa Sayısı:</span>
            <span class="ky-pd-attributes__value">224</span>
          </div>
          <div class="ky-pd-attributes__item">
            <span class="ky-pd-attributes__label">Dil:</span>
            <span class="ky-pd-attributes__value">TÜRKÇE</span>
          </div>
        </div>
        """
        let meta = KitapyurduScraper.parseProduct(html: html, fallbackISBN: "")

        #expect(meta.title == "Kuyucaklı Yusuf")
        #expect(meta.author == "Sabahattin Ali")
        #expect(meta.publisher == "Yapı Kredi Yayınları")
        #expect(meta.isbn == "9789753638029")
        #expect(meta.pageCount == "224")
        #expect(meta.publicationYear == "2023")
        #expect(meta.language == "Türkçe")
    }

    /// Arama adla yapıldığı için sayfadaki baskının ISBN'i katalogdakini ezmemeli.
    @Test func katalogISBNiKorunur() {
        let html = """
        <h1 class="ky-pd-title">Kürk Mantolu Madonna</h1>
        <div class="ky-pd-attributes__item">
          <span class="ky-pd-attributes__label">ISBN:</span>
          <span class="ky-pd-attributes__value">9786257999267</span>
        </div>
        """
        let meta = KitapyurduScraper.parseProduct(html: html, fallbackISBN: "9789750718434")
        #expect(meta.isbn == "9789750718434")
    }

    /// Kitapyurdu'nun güncel arama sonucu düzeni: kapak + ad bağlantısı,
    /// yayınevi ve yazar span'leri (adreslerde arama belirteçleri var).
    private var aramaHTML: String {
        """
        <div class="ky-products-container">
        <div class="ky-product" data-product-id="12064">
          <a href="https://www.kitapyurdu.com/kitap/kurk-mantolu-madonna/12064.html?filter_name=k%C3%BCrk+mantolu&amp;s_token=abc&amp;s_time=1" class="ky-product-cover"><img src="k1.jpg" alt="Kürk Mantolu Madonna" /></a>
          <a class="ky-product-title" href="https://www.kitapyurdu.com/kitap/kurk-mantolu-madonna/12064.html?filter_name=K%C3%BCrk+Mantolu&amp;s_token=abc&amp;s_time=1">Kürk Mantolu Madonna</a>
          <div class="ky-product-labels">
            <span class="ky-product-publisher"><a href="https://www.kitapyurdu.com/yayinevi/yapi-kredi-yayinlari/2.html">YAPI KREDİ YAYINLARI</a></span>
            <span class="ky-product-author"><a href="https://www.kitapyurdu.com/yazar/sabahattin-ali/10306.html"> Sabahattin Ali</a></span>
          </div>
        </div>
        <div class="ky-product" data-product-id="569235">
          <a href="https://www.kitapyurdu.com/kitap/kurk-mantolu-madonna-ciltli/569235.html?filter_name=K%C3%BCrk+Mantolu&amp;s_token=abc" class="ky-product-cover"><img src="k2.jpg" alt="Kürk Mantolu Madonna (Ciltli)" /></a>
          <a class="ky-product-title" href="https://www.kitapyurdu.com/kitap/kurk-mantolu-madonna-ciltli/569235.html">Kürk Mantolu Madonna (Ciltli)</a>
          <div class="ky-product-labels">
            <span class="ky-product-publisher"><a href="https://www.kitapyurdu.com/yayinevi/kapra-yayincilik/10491.html">KAPRA YAYINCILIK</a></span>
            <span class="ky-product-author"><a href="https://www.kitapyurdu.com/yazar/sabahattin-ali/10306.html"> Sabahattin Ali</a></span>
          </div>
        </div>
        <div class="ky-product" data-product-id="18252">
          <a class="ky-product-title" href="https://www.kitapyurdu.com/kitap/kuyucakli-yusuf/18252.html">Kuyucaklı Yusuf</a>
          <div class="ky-product-labels">
            <span class="ky-product-publisher"><a href="https://www.kitapyurdu.com/yayinevi/yapi-kredi-yayinlari/2.html">YAPI KREDİ YAYINLARI</a></span>
            <span class="ky-product-author"><a href="https://www.kitapyurdu.com/yazar/sabahattin-ali/10306.html"> Sabahattin Ali</a></span>
          </div>
        </div>
        </div>
        """
    }
}

@MainActor
struct OCRAyiklamaTestleri {
    private func line(_ text: String, _ height: CGFloat = 0) -> OCRLine {
        OCRLine(text: text, height: height, confidence: 1)
    }

    /// Gerçek bir künye taramasının birebir satırları: tüm alanlar doğru çıkmalı.
    @Test func kunyedenTumAlanlarCikartilir() {
        let lines = [
            line("Yüzbasının Kızı"),
            line("Aleksandr Sergeyeviç"),
            line("Puşkin"),
            line("© Doğan Egmont Yayıncılık"),
            line("Mayıs 2019"),
            line("8. ~askı/ Temmuz 2021"),
            line("ISBN 978-605-09-6297-0"),
            line("Her 2000 adet bir baskı"),
            line("Sertifika no: 11940"),
            line("Tel: (212) 446 05 99"),
            line("Yüzbaşının Kızı | Puşkin", 0.017),
            line("Seferi ve Pugaçov savaşının sonunu anlatacak değilim.", 0.029),
            line("I52", 0.016)
        ]
        let draft = BookOCRExtractor.draft(from: BookOCRResult(lines: lines, barcodeISBN: nil))

        #expect(draft.title == "Yüzbaşının Kızı")
        #expect(draft.author == "Aleksandr Sergeyeviç Puşkin")
        #expect(draft.isbn == "9786050962970")
        #expect(draft.publisher == "Doğan Egmont Yayıncılık")
        #expect(draft.publicationYear == "2021")
        #expect(draft.edition == "8")
        #expect(draft.pageCount == "152")
        #expect(draft.lowConfidenceFields.contains("pageCount"))
    }

    /// Büyük harfli künye ("45. BASKI", "SAYFA SAYISI: 320") Türkçe I/ı eşlemesiyle okunur.
    @Test func buyukHarfliBaskiVeSayfaSayisiOkunur() {
        let lines = [
            line("Kürk Mantolu Madonna", 0.06),
            line("Sabahattin Ali", 0.03),
            line("45. BASKI"),
            line("SAYFA SAYISI: 320")
        ]
        let draft = BookOCRExtractor.draft(from: BookOCRResult(lines: lines, barcodeISBN: nil))
        #expect(draft.edition == "45")
        #expect(draft.pageCount == "320")
        #expect(!draft.lowConfidenceFields.contains("pageCount"))

        let ingilizce = BookOCRExtractor.draft(from: BookOCRResult(lines: [line("Animal Farm", 0.06), line("3rd EDITION 2"), line("112 PAGES")], barcodeISBN: nil))
        #expect(ingilizce.pageCount == "112")
    }

    /// Kapak düzeni: en büyük yazı kitap adı, isim desenindeki satır yazar olmalı.
    @Test func kapaktanAdVeYazarCikartilir() {
        let lines = [
            line("SABAHATTİN ALİ", 0.03),
            line("Kürk Mantolu", 0.06),
            line("Madonna", 0.06),
            line("ISBN: 978-975-07-1853-3", 0.013),
            line("Yapı Kredi Yayınları", 0.02)
        ]
        let draft = BookOCRExtractor.draft(from: BookOCRResult(lines: lines, barcodeISBN: nil))

        #expect(draft.title == "Kürk Mantolu Madonna")
        #expect(draft.author == "SABAHATTİN ALİ")
        #expect(draft.isbn == "9789750718533")
        #expect(draft.publisher == "Yapı Kredi Yayınları")
    }

    /// Tiraj, sertifika ve yıl satırları sayfa sayısı sanılmamalı.
    @Test func sayfaSayisiTuzaklariAtlanir() {
        let lines = [
            line("Deneme Kitabı"),
            line("Her 2000 adet bir baskı"),
            line("2019"),
            line("Sertifika no: 11940"),
            line("No: 6/13")
        ]
        let draft = BookOCRExtractor.draft(from: BookOCRResult(lines: lines, barcodeISBN: nil))
        #expect(draft.pageCount.isEmpty)
    }

    /// Gerçek bir PDF taramasının birebir satırları (Ağaçlar kitabı): çok satırlı ad
    /// birleşmeli, "yayınevinden..." cümlesi yayınevi sanılmamalı, logo yazar olmamalı.
    @Test func pdfKitabindanTumAlanlarCikartilir() {
        let lines = [
            line("Türkiye'nin", 0.058),
            line("Bütün", 0.037),
            line("Ağaçlari ve Çaliları", 0.061),
            line("Editör: Prof. Dr. Ünal Akkemik", 0.041),
            line("TEMA O", 0.047),
            line("TÜRKİYE S BANKASI", 0.046),
            line("Kültür Yayınları", 0.018),
            line("Ağaçları ve Çalıları"),
            line("TÜRKİYE'NİN BÜTÜN AĞAÇLARI VE ÇALILARI", 0.025),
            line("© TÜRKİYE İŞ BANKASI KÜLTÜR YAYINLARI, 2020", 0.024),
            line("Sertifika No: 40077", 0.019),
            line("ÜNAL AKKEMİK", 0.018),
            line("Editör", 0.016),
            line("2. Basım: Ağustos 2021", 0.019),
            line("1. Basım: Aralık 2020", 0.015),
            line("ISBN 978-625-405-172-2", 0.015),
            line("Bu kitabın tüm yayın haklan saklıdır.", 0.021),
            line("yayınevinden izin alınmadan hiçbir yolla çoğaltılamaz,", 0.025)
        ]
        let draft = BookOCRExtractor.draft(
            from: BookOCRResult(lines: lines, barcodeISBN: "9786254051722")
        )

        #expect(draft.title == "Türkiye'nin Bütün Ağaçları ve Çalıları")
        #expect(draft.author == "Prof. Dr. Ünal Akkemik")
        #expect(draft.isbn == "9786254051722")
        #expect(draft.publisher == "TÜRKİYE İŞ BANKASI KÜLTÜR YAYINLARI")
        #expect(draft.publicationYear == "2021")
        #expect(draft.edition == "2")
    }

    /// Çok fotoğraflı birleşik tarama: ad parçalı gelse de künyedeki tam satır seçilmeli,
    /// ve o satır listenin ilerisinde (gövde metninden sonra) olsa bile bulunmalı.
    @Test func cokFotografliTaramadaTamAdSecilir() {
        var lines = [
            line("Türkiye'nin", 0.047),
            line("Bütün", 0.022),
            line("Ağaçları ve Çalıları", 0.041),
            line("Editör: Prof. Dr. Ünal Akkemik", 0.035)
        ]
        for index in 1...30 {
            lines.append(line("Dolgu metin satırı numara \(index) ile devam ediyor", 0.012))
        }
        lines.append(line("TÜRKİYE'NİN BÜTÜN AGAÇLARI VE ÇALILARI", 0.027))
        lines.append(line("2. Basım: Agustos 2021", 0.019))
        lines.append(line("1. Basım: Aralık 2020", 0.015))

        let draft = BookOCRExtractor.draft(
            from: BookOCRResult(lines: lines, barcodeISBN: "9786254051722")
        )
        #expect(draft.title == "TÜRKİYE'NİN BÜTÜN AGAÇLARI VE ÇALILARI")
        #expect(draft.author == "Prof. Dr. Ünal Akkemik")
        // Aksansız ay adı ("Agustos") da tanınmalı
        #expect(draft.publicationYear == "2021")
    }

    /// Barkoddan gelen ISBN metinden okunan her şeye baskın olmalı.
    @Test func barkodISBNOncelikli() {
        let lines = [line("Kitap Adı Örneği", 0.05)]
        let draft = BookOCRExtractor.draft(
            from: BookOCRResult(lines: lines, barcodeISBN: "9789750718533")
        )
        #expect(draft.isbn == "9789750718533")
    }
}
