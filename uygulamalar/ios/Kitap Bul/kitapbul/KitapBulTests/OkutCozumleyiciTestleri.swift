import Testing
import Foundation
import SwiftData
@testable import _01

/// Barkod masasının saf çözücüleri: okutulan kodun sırası ve barkodla iadede aday seçimi.
@MainActor
struct OkutCozumleyiciTestleri {
    private func baglam() throws -> ModelContext {
        ModelContext(try KitapVeritabani.makeContainer(inMemory: true))
    }
    private func odunc(_ kitap: CatalogBook, _ ad: String, sinif: String = "7/A", studentID: UUID? = nil, memberID: UUID? = nil,
                       copyID: UUID? = nil, tur: String = "library", kaynak: String? = nil, gun: Int = 5, ctx: ModelContext) -> ActiveLoan {
        let loan = ActiveLoan(bookID: kitap.id, bookTitleSnapshot: kitap.title, studentName: ad, studentClass: sinif,
                              dueDate: Calendar.current.date(byAdding: .day, value: gun, to: .now)!)
        loan.studentID = studentID; loan.memberID = memberID; loan.copyID = copyID
        loan.kind = tur; loan.identitySource = kaynak
        ctx.insert(loan)
        return loan
    }
    private func kitapID(_ sonuc: OkutCozumleyici.Sonuc) -> (UUID, UUID?, OkutCozumleyici.Kaynak)? {
        if case .kitap(let kitap, let nusha, let kaynak) = sonuc { return (kitap.id, nusha?.id, kaynak) }
        return nil
    }
    private func hata(_ sonuc: OkutCozumleyici.Sonuc) -> String? {
        if case .hata(let mesaj) = sonuc { return mesaj }
        return nil
    }

    // MARK: Çözüm sırası

    @Test func ogrenciKartiOnceCozulur() throws {
        let ctx = try baglam()
        let ali = Student(name: "Ali", number: "101", className: "7/A")
        var okunan: String?
        let sonuc = OkutCozumleyici.coz(" ogr101 ", context: ctx) { kod in okunan = kod; return ali }
        guard case .ogrenci(let bulunan) = sonuc else { Issue.record("Öğrenci kartı çözülmedi"); return }
        #expect(bulunan.id == ali.id)
        #expect(okunan == "ogr101")
        let tanimsiz = OkutCozumleyici.coz("OGRID12", context: ctx) { _ in throw SchoolLibraryService.OperationError(message: "Öğrenci kartının kimliği geçersiz.") }
        #expect(hata(tanimsiz) == "Öğrenci kartının kimliği geçersiz.")
    }

    @Test func demirbasIsbndenOnceGelirVeNushayiDondurur() throws {
        let ctx = try baglam()
        let kitap = CatalogBook(book: Book(title: "Simyacı", author: "Coelho", isbn: "9789750718434", quantity: 2))
        ctx.insert(kitap)
        let nusha = BookCopy(bookID: kitap.id, accessionCode: "D-7")
        ctx.insert(nusha); ctx.insert(BookCopy(bookID: kitap.id, accessionCode: "D-8"))
        try ctx.save()
        // Yazım farkı (küçük harf, tire) demirbaşı değiştirmez.
        let sonuc = try #require(kitapID(OkutCozumleyici.coz(" d7 ", context: ctx)))
        #expect(sonuc.0 == kitap.id && sonuc.1 == nusha.id && sonuc.2 == .demirbas)
        let isbn = try #require(kitapID(OkutCozumleyici.coz("978-975-07-1843-4", context: ctx)))
        #expect(isbn.0 == kitap.id && isbn.1 == nil && isbn.2 == .isbn)
    }

    @Test func ayniDemirbasIkiNushadaBelirsizdir() throws {
        let ctx = try baglam()
        let a = CatalogBook(book: Book(title: "A", author: "Y")), b = CatalogBook(book: Book(title: "B", author: "Y"))
        ctx.insert(a); ctx.insert(b)
        ctx.insert(BookCopy(bookID: a.id, accessionCode: "K-1")); ctx.insert(BookCopy(bookID: b.id, accessionCode: "K-1"))
        try ctx.save()
        #expect(hata(OkutCozumleyici.coz("K-1", context: ctx))?.contains("birden çok nüshada") == true)
    }

    @Test func isbn10OlarakSaklananKitapIsbn13IleBulunur() throws {
        let ctx = try baglam()
        let kitap = CatalogBook(book: Book(title: "Eski kayıt", author: "Y", isbn: "6053607029"))
        ctx.insert(kitap); try ctx.save()
        let sonuc = try #require(kitapID(OkutCozumleyici.coz("9786053607021", context: ctx)))
        #expect(sonuc.0 == kitap.id && sonuc.2 == .isbn)
    }

    @Test func ayracliSaklananEskiIsbnDeBulunur() throws {
        let ctx = try baglam()
        // Eski arşivden gelen kayıtlar tire/boşlukla saklanmış olabilir; hızlı arama bunları kaçırır.
        let on3 = CatalogBook(book: Book(title: "Tireli 13", author: "Y", isbn: "978-605-360-702-1"))
        let on = CatalogBook(book: Book(title: "Tireli 10", author: "Y", isbn: "0-8044-2957-X"))
        let bosluklu = CatalogBook(book: Book(title: "Boşluklu", author: "Y", isbn: "978 975 07 1843 4"))
        ctx.insert(on3); ctx.insert(on); ctx.insert(bosluklu); try ctx.save()
        #expect(try #require(kitapID(OkutCozumleyici.coz("9786053607021", context: ctx))).0 == on3.id)
        #expect(try #require(kitapID(OkutCozumleyici.coz("9780804429573", context: ctx))).0 == on.id)
        #expect(try #require(kitapID(OkutCozumleyici.coz("9789750718434", context: ctx))).0 == bosluklu.id)
    }

    @Test func icBarkodAyriKaynakOlarakCozulur() throws {
        let ctx = try baglam()
        let kod = InternalBarcode.generate(existingCodes: [])
        let kitap = CatalogBook(book: Book(title: "ISBN'siz", author: "Y", isbn: kod))
        ctx.insert(kitap); try ctx.save()
        let sonuc = try #require(kitapID(OkutCozumleyici.coz(kod, context: ctx)))
        #expect(sonuc.0 == kitap.id && sonuc.2 == .icBarkod)
        // Kayıtlı olmayan iç barkod kitap açmaz.
        #expect(hata(OkutCozumleyici.coz(InternalBarcode.generate(existingCodes: [kod]), context: ctx)) == "Katalogda kitap veya nüsha bulunamadı.")
    }

    @Test func dusulmusKitapVeIkiKayitAyrilir() throws {
        let ctx = try baglam()
        let dusulmus = CatalogBook(book: Book(title: "Eski baskı", author: "Y", isbn: "9789750718434", isWithdrawn: true))
        let etkin = CatalogBook(book: Book(title: "Yeni baskı", author: "Y", isbn: "9789750718434"))
        ctx.insert(dusulmus); ctx.insert(etkin); try ctx.save()
        // Düşülen kayıt aday sayılmaz; tek etkin kayıt kalır.
        #expect(try #require(kitapID(OkutCozumleyici.coz("9789750718434", context: ctx))).0 == etkin.id)
        ctx.insert(CatalogBook(book: Book(title: "Mükerrer", author: "Y", isbn: "9789750718434"))); try ctx.save()
        #expect(hata(OkutCozumleyici.coz("9789750718434", context: ctx))?.contains("Birden fazla katalog kaydı") == true)
        #expect(hata(OkutCozumleyici.coz("kitap adı", context: ctx))?.contains("Kod tanınmadı") == true)
        #expect(hata(OkutCozumleyici.coz("9786053607021", context: ctx)) == "Katalogda kitap veya nüsha bulunamadı.")
    }

    /// Kitaplar'daki barkodla arama düşülmüş kaydı da bulur; ödünç/iade çözümü bulmaz.
    @Test func isbnAdaylariDusulenleriIsteyeBagliSayar() throws {
        let ctx = try baglam()
        let dusulmus = CatalogBook(book: Book(title: "Eski", author: "Y", isbn: "978-605-360-702-1", isWithdrawn: true))
        ctx.insert(dusulmus); try ctx.save()
        #expect(try OkutCozumleyici.isbnAdaylari("9786053607021", context: ctx).isEmpty)
        #expect(try OkutCozumleyici.isbnAdaylari("9786053607021", dusulenlerDahil: true, context: ctx).map(\.id) == [dusulmus.id])
    }

    @Test func nushaSayisiVeKonum() throws {
        let ctx = try baglam()
        let kitap = CatalogBook(book: Book(title: "A", author: "Y", quantity: 1, shelf: "2", cabinet: "3"))
        ctx.insert(kitap)
        let rafli = BookCopy(bookID: kitap.id, accessionCode: "N-1", cabinet: "5", shelf: "1")
        ctx.insert(rafli); ctx.insert(BookCopy(bookID: kitap.id))
        try ctx.save()
        #expect(OkutCozumleyici.nushaSayisi(kitap, context: ctx) == 2)
        // Karar satırının yeri ortak konum kaynağından gelir (KatalogYardimciTestleri ayrıca sınar).
        #expect(kitap.konumMetni(nusha: nil) == "Dolap 3 · Raf 2")
        #expect(kitap.konumMetni(nusha: rafli) == "Dolap 5 · Raf 1")
        #expect(CatalogBook(book: Book(title: "B", author: "Y", shelf: " ")).konumMetni == nil)
    }

    // MARK: Barkodla iadede adaylar

    @Test func tekNushadaDogrudanCokNushadaOnayla() throws {
        let ctx = try baglam()
        let tek = CatalogBook(book: Book(title: "Tek", author: "Y", quantity: 1))
        let cok = CatalogBook(book: Book(title: "Çok", author: "Y", quantity: 3))
        ctx.insert(tek); ctx.insert(cok)
        let a = odunc(tek, "Ali", studentID: UUID(), ctx: ctx)
        let b = odunc(cok, "Ece", studentID: UUID(), ctx: ctx)
        try ctx.save()
        let tekSonuc = SchoolLibraryService.iadeAdaylari(loans: [a, b], bookID: tek.id, copyID: nil, student: nil, nushaSayisi: 1)
        #expect(tekSonuc.adaylar.map(\.id) == [a.id] && !tekSonuc.onayGerekir)
        // Çok nüshalı kitapta ISBN okutulunca tek aday da "Kimin iadesi?" ile onaylatılır.
        let cokSonuc = SchoolLibraryService.iadeAdaylari(loans: [a, b], bookID: cok.id, copyID: nil, student: nil, nushaSayisi: 3)
        #expect(cokSonuc.adaylar.map(\.id) == [b.id] && cokSonuc.onayGerekir)
    }

    @Test func demirbasOkutuluncaAdayDaralirVeOnaySorulmaz() throws {
        let ctx = try baglam()
        let kitap = CatalogBook(book: Book(title: "Çok", author: "Y", quantity: 3))
        ctx.insert(kitap)
        let n1 = BookCopy(bookID: kitap.id, accessionCode: "N-1"), n2 = BookCopy(bookID: kitap.id, accessionCode: "N-2")
        ctx.insert(n1); ctx.insert(n2)
        let a = odunc(kitap, "Ali", studentID: UUID(), copyID: n1.id, ctx: ctx)
        let b = odunc(kitap, "Ece", studentID: UUID(), copyID: n2.id, ctx: ctx)
        try ctx.save()
        let sonuc = SchoolLibraryService.iadeAdaylari(loans: [a, b], bookID: kitap.id, copyID: n2.id, student: nil, nushaSayisi: 3)
        #expect(sonuc.adaylar.map(\.id) == [b.id] && !sonuc.onayGerekir)
    }

    @Test func nushasizVerilenOduncDemirbasOkutuluncaBulunur() throws {
        let ctx = try baglam()
        let kitap = CatalogBook(book: Book(title: "Çok", author: "Y", quantity: 3))
        ctx.insert(kitap)
        let ali = Student(name: "Ali", number: "1", className: "7/A")
        // Ödünç, nüshalar demirbaş defterine işlenmeden verilmiş (nüshasız); nüshalar sonradan kaydedilmiş.
        let eski = odunc(kitap, "Ali", studentID: ali.id, ctx: ctx)
        let n1 = BookCopy(bookID: kitap.id, accessionCode: "N-1"), n2 = BookCopy(bookID: kitap.id, accessionCode: "N-2")
        ctx.insert(n1); ctx.insert(n2)
        let bagli = odunc(kitap, "Ece", studentID: UUID(), copyID: n2.id, ctx: ctx)
        try ctx.save()
        // N-1 hiçbir ödünce bağlı değil: nüshasız ödünç aday olur; kişi belli olmadığından sorulur.
        let ogrencisiz = SchoolLibraryService.iadeAdaylari(loans: [eski, bagli], bookID: kitap.id, copyID: n1.id, student: nil, nushaSayisi: 3)
        #expect(ogrencisiz.adaylar.map(\.id) == [eski.id] && ogrencisiz.onayGerekir)
        // Kart okutulmuşsa kişi belli: tek aday doğrudan iade edilir.
        let kartla = SchoolLibraryService.iadeAdaylari(loans: [eski, bagli], bookID: kitap.id, copyID: n1.id, student: ali, nushaSayisi: 3)
        #expect(kartla.adaylar.map(\.id) == [eski.id] && !kartla.onayGerekir)
        // N-2'nin kendi ödüncü var: nüshasız kayıt karışmaz, başka öğrenci seçiliyse aday çıkmaz.
        let kendi = SchoolLibraryService.iadeAdaylari(loans: [eski, bagli], bookID: kitap.id, copyID: n2.id, student: nil, nushaSayisi: 3)
        #expect(kendi.adaylar.map(\.id) == [bagli.id] && !kendi.onayGerekir)
        #expect(SchoolLibraryService.iadeAdaylari(loans: [eski, bagli], bookID: kitap.id, copyID: n2.id, student: ali, nushaSayisi: 3).adaylar.isEmpty)
    }

    @Test func ogrenciSeciliykenBugunkuDaraltmaKorunur() throws {
        let ctx = try baglam()
        let kitap = CatalogBook(book: Book(title: "Çok", author: "Y", quantity: 5))
        ctx.insert(kitap)
        let ali = Student(name: "Ali Kaya", number: "7", className: "7/A")
        let kimlikli = odunc(kitap, "Ali Kaya", studentID: ali.id, ctx: ctx)
        let eskiAdla = odunc(kitap, "ali kaya", kaynak: "legacy", gun: 9, ctx: ctx)
        let elleYazilmis = odunc(kitap, "Ali Kaya", kaynak: "manual", ctx: ctx)
        let baskaSinif = odunc(kitap, "Ali Kaya", sinif: "8/B", kaynak: "legacy", ctx: ctx)
        let uye = odunc(kitap, "Ali Kaya", sinif: "", memberID: UUID(), ctx: ctx)
        let baskasi = odunc(kitap, "Ece", studentID: UUID(), ctx: ctx)
        try ctx.save()
        let hepsi = [kimlikli, eskiAdla, elleYazilmis, baskaSinif, uye, baskasi]
        let sonuc = SchoolLibraryService.iadeAdaylari(loans: hepsi, bookID: kitap.id, copyID: nil, student: ali, nushaSayisi: 5)
        // Son güne göre sıralı: önce kimlikli (5 gün), sonra adla eşleşen eski kayıt (9 gün).
        #expect(sonuc.adaylar.map(\.id) == [kimlikli.id, eskiAdla.id])
        #expect(sonuc.onayGerekir)
        let yalniz = SchoolLibraryService.iadeAdaylari(loans: [kimlikli, uye, baskasi], bookID: kitap.id, copyID: nil, student: ali, nushaSayisi: 5)
        // Öğrenci seçiliyken tek aday doğrudan iade edilir; kişi zaten belli.
        #expect(yalniz.adaylar.map(\.id) == [kimlikli.id] && !yalniz.onayGerekir)
    }

    @Test func ogrencisizIadeUyeOdunculeriniDeBulur() throws {
        let ctx = try baglam()
        let kitap = CatalogBook(book: Book(title: "Tek", author: "Y", quantity: 1))
        ctx.insert(kitap)
        let uye = odunc(kitap, "Veli Bey", sinif: "", memberID: UUID(), ctx: ctx)
        try ctx.save()
        let sonuc = SchoolLibraryService.iadeAdaylari(loans: [uye], bookID: kitap.id, copyID: nil, student: nil, nushaSayisi: 1)
        #expect(sonuc.adaylar.first?.studentName == "Veli Bey" && !sonuc.onayGerekir)
        let ogrenciyle = SchoolLibraryService.iadeAdaylari(loans: [uye], bookID: kitap.id, copyID: nil,
                                                           student: Student(name: "Veli Bey", className: ""), nushaSayisi: 1)
        #expect(ogrenciyle.adaylar.isEmpty)
    }

    @Test func dersKitabiCokNushaOlduguIcinOnaylanir() throws {
        let ctx = try baglam()
        let ders = CatalogBook(book: Book(title: "Matematik 7", author: "MEB", quantity: 30, isTextbook: true))
        ctx.insert(ders)
        let ali = Student(name: "Ali", number: "1", className: "7/A")
        let loan = odunc(ders, "Ali", studentID: ali.id, tur: "textbook", ctx: ctx)
        try ctx.save()
        let ogrencisiz = SchoolLibraryService.iadeAdaylari(loans: [loan], bookID: ders.id, copyID: nil, student: nil, nushaSayisi: 30)
        #expect(ogrencisiz.adaylar.count == 1 && ogrencisiz.onayGerekir)
        let kartla = SchoolLibraryService.iadeAdaylari(loans: [loan], bookID: ders.id, copyID: nil, student: ali, nushaSayisi: 30)
        #expect(kartla.adaylar.map(\.id) == [loan.id] && !kartla.onayGerekir)
    }

    @Test func ayniIsbnIkiOkurdaykenOkurSorulur() throws {
        let ctx = try baglam()
        let kitap = CatalogBook(book: Book(title: "Çok", author: "Y", isbn: "9789750718434", quantity: 2))
        ctx.insert(kitap)
        let ali = Student(name: "Ali", number: "1", className: "7/A")
        let a = odunc(kitap, "Ali", studentID: ali.id, gun: 2, ctx: ctx)
        let b = odunc(kitap, "Ece", studentID: UUID(), gun: 4, ctx: ctx)
        try ctx.save()
        let sonuc = SchoolLibraryService.iadeAdaylari(loans: [b, a], bookID: kitap.id, copyID: nil, student: nil, nushaSayisi: 2)
        #expect(sonuc.adaylar.map(\.id) == [a.id, b.id] && sonuc.onayGerekir)
        let aliyle = SchoolLibraryService.iadeAdaylari(loans: [a, b], bookID: kitap.id, copyID: nil, student: ali, nushaSayisi: 2)
        #expect(aliyle.adaylar.map(\.id) == [a.id] && !aliyle.onayGerekir)
    }

    // MARK: Aynı kod süzgeci

    @Test func ayniKodUcSaniyeIcindeYokSayilir() {
        var suzgec = TekrarSuzgeci()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let okumalar: [(kod: String, saniye: TimeInterval)] = [
            ("9789750718434", 0), (" 9789750718434 ", 2.9), ("9789750718434", 3),
            // Araya başka kod girince aynı kitap yeniden okunabilir (kart → kitap → kart → kitap).
            ("OGR101", 3.5), ("9789750718434", 4), ("9789750718434", 5)
        ]
        let kabul = okumalar.map { suzgec.kabulEt($0.kod, an: t0.addingTimeInterval($0.saniye)) }
        #expect(kabul == [true, false, true, true, true, false])
    }
}
