import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import _01

@MainActor
struct KitaplarSekmesiTestleri {
    private func baglam() throws -> (ModelContext, [CatalogBook]) {
        let container = try ModelContainer(for: CatalogBook.self, ActiveLoan.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let kitaplar = [
            CatalogBook(book: Book(title: "Şeker Portakalı", author: "Vasconcelos", publisher: "Can", isbn: "9789750718434",
                                   category: "Roman", quantity: 2, cabinet: "B")),
            CatalogBook(book: Book(title: "Kuyucaklı Yusuf", author: "Sabahattin Ali", category: "Roman", cabinet: "A")),
            CatalogBook(book: Book(title: "Uzay Atlası", author: "", category: nil)),
            CatalogBook(book: Book(title: "Eski Sözlük", author: "TDK", isWithdrawn: true))
        ]
        kitaplar.forEach { ctx.insert($0) }
        try ctx.save()
        return (ctx, kitaplar)
    }

    private func ara(_ ctx: ModelContext, _ terim: String) throws -> [String] {
        let descriptor = KitapAramaKosulu.predicate(for: terim).map { FetchDescriptor<CatalogBook>(predicate: $0) }
            ?? FetchDescriptor<CatalogBook>()
        return try ctx.fetch(descriptor).map(\.title).sorted()
    }

    @Test func aramaAdYazarYayineviVeISBN() throws {
        let (ctx, _) = try baglam()
        #expect(try ara(ctx, "seker") == ["Şeker Portakalı"])
        #expect(try ara(ctx, "SABAHATTİN") == ["Kuyucaklı Yusuf"])
        #expect(try ara(ctx, "can") == ["Şeker Portakalı"])
        #expect(try ara(ctx, "978-975-07") == ["Şeker Portakalı"])
        #expect(try ara(ctx, "roman").count == 2)
        #expect(try ara(ctx, "").count == 4)
    }

    /// Kelimeler sırasız ve aralıklı yazılsa da (yazar + ad, ad + yayınevi) kayıt bulunur.
    @Test func cokKelimeliAramaSiradanBagimsiz() throws {
        let (ctx, _) = try baglam()
        #expect(try ara(ctx, "seker portakali") == ["Şeker Portakalı"])
        #expect(try ara(ctx, "vasconcelos seker") == ["Şeker Portakalı"])
        #expect(try ara(ctx, "portakali can") == ["Şeker Portakalı"])
        #expect(try ara(ctx, "ali kuyucakli sabahattin") == ["Kuyucaklı Yusuf"])
        #expect(try ara(ctx, "roman yusuf ali sabahattin kuyucakli") == ["Kuyucaklı Yusuf"])
        #expect(try ara(ctx, "seker yusuf").isEmpty, "Her kelime aynı kayıtta geçmeli")
        #expect(try ara(ctx, "seker  seker") == ["Şeker Portakalı"])
    }

    @Test func aramaKelimeleriEnUzunUcuSecer() {
        #expect(CatalogMatcher.aramaKelimeleri("") == [])
        #expect(CatalogMatcher.aramaKelimeleri("seker") == ["seker"])
        #expect(CatalogMatcher.aramaKelimeleri("ve ve savas") == ["ve", "savas"])
        #expect(Set(CatalogMatcher.aramaKelimeleri("savas ve baris tolstoy")) == ["savas", "baris", "tolstoy"])
    }

    @Test func ekleSekmesiAramasiCokKelimeli() throws {
        let (ctx, _) = try baglam()
        func ekleAra(_ terim: String) throws -> [String] {
            try ctx.fetch(FetchDescriptor<CatalogBook>(predicate: CatalogQueryView<EmptyView>.searchPredicate(term: terim)))
                .map(\.title).sorted()
        }
        #expect(try ekleAra("vasconcelos seker") == ["Şeker Portakalı"])
        #expect(try ekleAra("ali kuyucakli sabahattin") == ["Kuyucaklı Yusuf"])
        #expect(try ekleAra("seker yusuf").isEmpty)
    }

    /// SQL'e çevrilemeyen koşul uygulamayı çökertirdi; sorunlu girdiler güvenli olmalı.
    @Test(arguments: ["%", "_", "'", "İ", "📚", "12345", "a % b", "x ' y _ z", String(repeating: "a", count: 2000)])
    func sorunluAramaCokmez(terim: String) throws {
        let (ctx, _) = try baglam()
        _ = try ara(ctx, terim)
    }

    @Test func filtrelerVeSiralama() throws {
        let (ctx, kitaplar) = try baglam()
        let odunc = ActiveLoan(bookID: kitaplar[1].id, bookTitleSnapshot: "Kuyucaklı Yusuf",
                               studentName: "S", studentClass: "5", dueDate: .now.addingTimeInterval(86_400))
        ctx.insert(odunc)
        let sayilar = AssistantContext.loanCounts([odunc])

        var filtre = KitapFiltresi()
        #expect(filtre.uygula(kitaplar, oduncSayilari: sayilar, siralama: .ad).map(\.title)
                == ["Kuyucaklı Yusuf", "Şeker Portakalı", "Uzay Atlası"], "Düşülenler varsayılan olarak gizli")

        filtre.durum = .oduncte
        #expect(filtre.uygula(kitaplar, oduncSayilari: sayilar, siralama: .ad).map(\.title) == ["Kuyucaklı Yusuf"])
        filtre.durum = .rafta
        #expect(!filtre.uygula(kitaplar, oduncSayilari: sayilar, siralama: .ad).map(\.title).contains("Kuyucaklı Yusuf"))
        filtre.durum = .eksik
        #expect(filtre.uygula(kitaplar, oduncSayilari: sayilar, siralama: .ad).map(\.title).contains("Uzay Atlası"))
        filtre.durum = .dusulen
        #expect(filtre.uygula(kitaplar, oduncSayilari: sayilar, siralama: .ad).map(\.title) == ["Eski Sözlük"])

        filtre = KitapFiltresi(kategori: "Kategorisiz")
        #expect(filtre.uygula(kitaplar, oduncSayilari: sayilar, siralama: .ad).map(\.title) == ["Uzay Atlası"])
        filtre = KitapFiltresi(dolap: "B")
        #expect(filtre.aktifSayisi == 1)
        #expect(filtre.uygula(kitaplar, oduncSayilari: sayilar, siralama: .ad).map(\.title) == ["Şeker Portakalı"])

        let yerSirali = KitapFiltresi().uygula(kitaplar, oduncSayilari: [:], siralama: .yer).map(\.title)
        #expect(yerSirali.first == "Kuyucaklı Yusuf", "A dolabı B'den önce")
    }

    /// Tek ad sözlüğü: "Boşta" ekranda "Rafta" olur, kayıtlı eski filtre yine çözülür.
    @Test func raftaFiltresiEskiKaydiCozer() throws {
        #expect(KitapDurumFiltresi.rafta.ad == "Rafta")
        #expect(KitapDurumFiltresi.cipler == [.tumu, .rafta, .oduncte, .gecikmis])
        let eski = Data(#"{"durum":"Boşta","kategori":"Roman"}"#.utf8)
        let filtre = try JSONDecoder().decode(KitapFiltresi.self, from: eski)
        #expect(filtre.durum == .rafta && filtre.kategori == "Roman")
    }

    /// Liste, kapak, ayrıntı ve Ana Sayfa araması aynı durum sözcüğünü kullanır.
    @Test func kitapDurumuTekSozluk() {
        let kitap = CatalogBook(book: Book(title: "A", author: "Y", quantity: 3))
        #expect(KitapDurumu.rozet(kitap, stok: LibraryStock(total: 3, loaned: 1, available: 2)).metin == "2/3 rafta")
        #expect(KitapDurumu.rozet(kitap, stok: LibraryStock(total: 1, available: 1)).metin == "Rafta")
        #expect(KitapDurumu.rozet(kitap, stok: LibraryStock(total: 3, loaned: 3)).metin == "Ödünçte")
        #expect(KitapDurumu.rozet(kitap, stok: LibraryStock(total: 1, reserved: 1)).metin == "Sırada")
        #expect(KitapDurumu.rozet(kitap, stok: LibraryStock(total: 2, loaned: 1, available: 1), gecikmis: true).metin == "Gecikmiş")
        #expect(KitapDurumu.rozet(kitap, stok: LibraryStock(total: 1, lost: 1)).metin == "Kayıp")
        let dusulmus = CatalogBook(book: Book(title: "B", author: "Y", isWithdrawn: true))
        #expect(KitapDurumu.rozet(dusulmus, stok: LibraryStock(total: 1, withdrawn: 1)).metin == "Düşüldü")

        // "Ödünç ver" pasifse nedeni yazılır; ayrılmış nüsha sıradakine verilebildiği için engel değildir.
        #expect(KitapDurumu.oduncEngeli(kitap, stok: LibraryStock(total: 3, loaned: 2, lost: 1)) == "Uygun nüsha yok · 2 ödünçte · 1 kayıp")
        #expect(KitapDurumu.oduncEngeli(kitap, stok: LibraryStock(total: 1, reserved: 1)) == nil)
        #expect(KitapDurumu.oduncEngeli(kitap, stok: LibraryStock(total: 1, available: 1)) == nil)
        #expect(KitapDurumu.oduncEngeli(dusulmus, stok: LibraryStock(total: 1)) != nil)
    }

    /// Ana Sayfa araması ayrıntıyla aynı stok kuralını kullanır: nüsha durumu, bildirilmiş rezervasyon
    /// ve kayıtlı nüsha sayısı rozete girer (yalnız ödünç sayısı ve adet yetmez).
    @Test func aramaRozetiNushaVeRezervasyonuSayar() {
        let kayip = CatalogBook(book: Book(title: "Kayıp", author: "Y", quantity: 1))
        let onarim = CatalogBook(book: Book(title: "Onarım", author: "Y", quantity: 1))
        let sirada = CatalogBook(book: Book(title: "Sırada", author: "Y", quantity: 1))
        let ucNusha = CatalogBook(book: Book(title: "Üç Nüsha", author: "Y", quantity: 1))
        let rafta = CatalogBook(book: Book(title: "Rafta", author: "Y", quantity: 2))
        let copies = [BookCopy(bookID: kayip.id, status: "Kayıp"), BookCopy(bookID: onarim.id, status: "Onarımda")]
            + (0..<3).map { _ in BookCopy(bookID: ucNusha.id) }
        let rezervasyon = Reservation(bookID: sirada.id, bookTitleSnapshot: "Sırada", studentName: "S", studentClass: "5")
        rezervasyon.notifiedAt = .now
        let odunc = ActiveLoan(bookID: rafta.id, bookTitleSnapshot: "Rafta", studentName: "S", studentClass: "5",
                               dueDate: .now.addingTimeInterval(86_400))
        let rozetler = KitapDurumu.rozetler([kayip, onarim, sirada, ucNusha, rafta], loans: [odunc], copies: copies,
                                            reservations: [rezervasyon])
        #expect(rozetler[kayip.id]?.metin == "Kayıp")
        #expect(rozetler[onarim.id]?.metin == "Onarımda")
        #expect(rozetler[sirada.id]?.metin == "Sırada")
        #expect(rozetler[ucNusha.id]?.metin == "3/3 rafta")
        #expect(rozetler[rafta.id]?.metin == "1/2 rafta")
    }

    /// Raflar satırı aynı stoktan kurulur; ödünç sayısı nüsha sayısını aşmaz.
    @Test func rafSatiriStoktanKurulur() {
        #expect(KitapDurumu.rafSatiri(LibraryStock(total: 3, loaned: 1, available: 2)) == "3 nüsha · 1 ödünçte")
        #expect(KitapDurumu.rafSatiri(LibraryStock(total: 1, available: 1)) == "1 nüsha · rafta")
        #expect(KitapDurumu.rafSatiri(LibraryStock(total: 3, available: 1, lost: 2)) == "3 nüsha · 1 rafta")
        #expect(KitapDurumu.rafSatiri(LibraryStock(total: 1, lost: 1)) == "1 nüsha · kayıp")
        #expect(KitapDurumu.rafSatiri(LibraryStock(total: 1, reserved: 1)) == "1 nüsha · sırada")
        #expect(KitapDurumu.rafSatiri(LibraryStock(total: 1, loaned: 2)) == "1 nüsha · 1 ödünçte")
    }

    /// Elle yazılan ISBN-13, ISBN-10 olarak saklanan kaydı da bulur (tersi zaten bulunuyordu).
    /// Uzun yazımda ("ISBN: 978-…") barkod araması kararı yazılan rakamlarla verilir.
    @Test func isbn13AramasiIsbn10KaydiBulur() throws {
        let (ctx, _) = try baglam()
        ctx.insert(CatalogBook(book: Book(title: "On Haneli", author: "Y", isbn: "6053607020")))
        try ctx.save()
        #expect(try ara(ctx, "9786053607021") == ["On Haneli"])
        #expect(try ara(ctx, "ISBN: 978-605-360-702-1") == ["On Haneli"])
        #expect(try ara(ctx, "9789750718434") == ["Şeker Portakalı"])
    }

    /// Düzenleyiciden gelen kayıt demirbaş, ödünç ve düşülme bilgisini silmemeli.
    @Test func duzenlemeKayitAlanlariniKorur() throws {
        let (ctx, kitaplar) = try baglam()
        let kitap = kitaplar[0]
        kitap.accessionCode = "D-0042"
        kitap.loanedTo = "Ali"
        kitap.loanDueDate = .now
        try ctx.save()

        var duzenli = kitap.book
        duzenli.title = "Şeker Portakalı (Yeni Baskı)"
        duzenli.accessionCode = nil
        duzenli.loanedTo = nil
        duzenli.loanDueDate = nil
        kitap.update(from: kitap.preservingRecordFields(of: duzenli))

        #expect(kitap.title == "Şeker Portakalı (Yeni Baskı)")
        #expect(kitap.accessionCode == "D-0042")
        #expect(kitap.loanedTo == "Ali")
        #expect(kitap.loanDueDate != nil)
        #expect(kitap.searchKey?.contains("yeni baski") == true, "Arama anahtarı güncellenir")
    }
}
