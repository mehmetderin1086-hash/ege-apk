import Testing
import Foundation
import SwiftData
import UIKit
@testable import _01

@MainActor
struct KatalogYardimciTestleri {
    private func baglam(_ kitaplar: [Book]) throws -> (ModelContext, [CatalogBook]) {
        let ctx = ModelContext(try KitapVeritabani.makeContainer(inMemory: true))
        let kayitlar = kitaplar.map(CatalogBook.init(book:))
        kayitlar.forEach { ctx.insert($0) }
        try ctx.save()
        return (ctx, kayitlar)
    }

    @Test func mukerrerISBNveAdBulunur() throws {
        let (ctx, kayitlar) = try baglam([
            Book(title: "Şeker Portakalı", author: "Vasconcelos", isbn: "978-975-07-1843-4", cabinet: "B"),
            Book(title: "Kürk Mantolu Madonna", author: "Sabahattin Ali")
        ])
        let isbnle = MukerrerDenetimi.eslesmeler(title: "", isbn: "9789750718434", haric: nil, context: ctx)
        #expect(isbnle.map(\.title) == ["Şeker Portakalı"])
        #expect(isbnle.first?.detail.contains("Dolap B") == true)

        let adla = MukerrerDenetimi.eslesmeler(title: "kurk mantolu madonna", isbn: "", haric: nil, context: ctx)
        #expect(adla.map(\.title) == ["Kürk Mantolu Madonna"])

        // Düzenlenen kaydın kendisi uyarı vermez; kısmi ad eşleşmesi de mükerrer sayılmaz
        #expect(MukerrerDenetimi.eslesmeler(title: "Kürk Mantolu Madonna", isbn: "", haric: kayitlar[1].id, context: ctx).isEmpty)
        #expect(MukerrerDenetimi.eslesmeler(title: "Kürk", isbn: "", haric: nil, context: ctx).isEmpty)
    }

    @Test func eksikCiltlerHesaplanir() {
        #expect(SeriAnalizi.eksikCiltler([1, 2, 4, 7]) == [3, 5, 6])
        #expect(SeriAnalizi.eksikCiltler([]) == [])
        #expect(SeriAnalizi.eksikCiltler([0, 0]) == [])
        #expect(SeriAnalizi.eksikCiltler([10_000]) == [])   // saçma cilt numarası listeyi patlatmaz
    }

    @Test func seriOzetiVeSiralama() throws {
        let (ctx, _) = try baglam([
            Book(title: "HP 3", author: "Rowling", series: "Harry Potter", volume: 3),
            Book(title: "HP 1", author: "Rowling", series: "Harry Potter", volume: 1),
            Book(title: "Tek", author: "X")
        ])
        #expect(SeriAnalizi.seriKitaplari("Harry Potter", context: ctx).map(\.title) == ["HP 1", "HP 3"])
        let ozet = SeriAnalizi.ozet(try ctx.fetch(FetchDescriptor<CatalogBook>()))
        #expect(ozet.count == 1)
        #expect(ozet.first?.eksik == [2])
    }

    @Test func benzerKitaplarSiralanir() throws {
        let (ctx, k) = try baglam([
            Book(title: "Kaynak", author: "Ahmet Ümit", category: "Roman", tags: "polisiye, istanbul"),
            Book(title: "Aynı yazar", author: "Ahmet Umit", category: "Roman"),
            Book(title: "Ortak etiket", author: "Başka", tags: "Polisiye"),
            Book(title: "Sadece kategori", author: "Z", category: "Roman"),
            Book(title: "İlgisiz", author: "Q", category: "Bilim"),
            Book(title: "Düşülmüş", author: "Ahmet Ümit", isWithdrawn: true)
        ])
        let sonuc = BenzerKitaplar.bul(k[0], adaylar: BenzerKitaplar.adaylar(for: k[0], context: ctx))
        #expect(sonuc.first?.title == "Aynı yazar")
        #expect(sonuc.contains { $0.title == "Ortak etiket" })
        #expect(sonuc.contains { $0.title == "Sadece kategori" })
        #expect(!sonuc.contains { $0.title == "İlgisiz" || $0.title == "Düşülmüş" || $0.title == "Kaynak" })
    }

    @Test func turkceBasHarfBolumleri() {
        #expect(AlfabeBolumleri.basHarf("çalıkuşu") == "Ç")
        #expect(AlfabeBolumleri.basHarf("istanbul") == "İ")
        #expect(AlfabeBolumleri.basHarf("ılgaz") == "I")
        #expect(AlfabeBolumleri.basHarf("1984") == "#")
        #expect(AlfabeBolumleri.basHarf("  ") == "#")
    }

    @Test func topluEtiketVeFiltre() throws {
        let (_, k) = try baglam([
            Book(title: "A", author: "", tags: "macera"),
            Book(title: "B", author: "", readingLevel: "Ortaokul"),
            Book(title: "C", author: "", series: "Seri", volume: 2),
            Book(title: "D", author: "", series: "Seri", volume: 1)
        ])
        TopluKitapIslemi.etiketEkle("Macera, dostluk", Array(k.prefix(2)))
        #expect(k[0].tagList == ["macera", "dostluk"])   // aynı etiket iki kez eklenmez
        #expect(k[1].tagList == ["Macera", "dostluk"])

        var filtre = KitapFiltresi()
        filtre.etiket = "DOSTLUK"
        #expect(filtre.uygula(k, oduncSayilari: [:], siralama: .ad).map(\.title) == ["A", "B"])
        filtre = KitapFiltresi(duzey: "Ortaokul")
        #expect(filtre.uygula(k, oduncSayilari: [:], siralama: .ad).map(\.title) == ["B"])
        filtre = KitapFiltresi(seri: "Seri")
        #expect(filtre.uygula(k, oduncSayilari: [:], siralama: .ad).map(\.title) == ["D", "C"])   // cilt sırası
        #expect(filtre.aktifSayisi == 1)
    }

    @Test func kayitliFiltreKodlanir() throws {
        let kayit = KayitliFiltre(ad: "5. sınıf", filtre: KitapFiltresi(durum: .rafta, kategori: "Roman", duzey: "3-4. sınıf"),
                                  siralama: KitapSiralama.yazar.rawValue)
        let cozulen = try JSONDecoder().decode(KayitliFiltre.self, from: JSONEncoder().encode(kayit))
        #expect(cozulen == kayit)
    }

    @Test func kapakRengiOrtalamaAlinir() throws {
        let resim = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        let png = try #require(resim.pngData())
        let renk = try #require(KapakRengi.hesapla(png))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        renk.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(r > 0.8 && g < 0.2 && b < 0.2)
        #expect(KapakRengi.hesapla(Data([1, 2, 3])) == nil)
    }

    /// Konumun tek biçimi: "Oda · Dolap 3 · Raf 2"; boş parçalar atlanır, hiçbiri yoksa nil.
    @Test func konumMetniTekKaynaktan() throws {
        let tam = CatalogBook(book: Book(title: "A", author: "Y", location: "Okuma salonu", shelf: "2", cabinet: "3"))
        #expect(tam.konumMetni == "Okuma salonu · Dolap 3 · Raf 2")
        #expect(CatalogBook(book: Book(title: "B", author: "Y", cabinet: " 4 ")).konumMetni == "Dolap 4")
        #expect(CatalogBook(book: Book(title: "C", author: "Y", location: "", shelf: "  ", cabinet: nil)).konumMetni == nil)
        #expect(CatalogBook.yerAtanmamis == "Yer atanmamış")

        // Nüshanın kendi dolap/rafı kitabınkini ezer; yoksa kitabınki kullanılır.
        let rafli = BookCopy(bookID: tam.id, cabinet: "5", shelf: "1")
        #expect(tam.konumMetni(nusha: rafli) == "Okuma salonu · Dolap 5 · Raf 1")
        #expect(tam.konumMetni(nusha: BookCopy(bookID: tam.id)) == tam.konumMetni)
        #expect(tam.konumMetni(nusha: nil) == tam.konumMetni)

        // Nüsha ve sayım yeri aynı ayracı kullanır.
        #expect(BookCopy.place(cabinet: "B", shelf: "2") == "Dolap B · Raf 2")
        #expect(BookCopy.place(cabinet: nil, shelf: "") == "")
        let kitap = CatalogBook(book: Book(title: "D", author: "Y", shelf: "1", cabinet: "A"))
        #expect(BookCopy(bookID: kitap.id, shelf: "7").effectivePlace(for: kitap) == "Dolap A · Raf 7")
    }

    /// Demirbaş kodu birebir uyarsa kitap bulunur (nüsha ya da kitap demirbaşı); önek eşleşmez.
    @Test func demirbasBirebirBulunur() throws {
        let (ctx, kayitlar) = try baglam([
            Book(title: "Kitap Demirbaşlı", author: "Y", accessionCode: "K-7"),
            Book(title: "Nüsha Demirbaşlı", author: "Y")
        ])
        ctx.insert(BookCopy(bookID: kayitlar[1].id, accessionCode: "2024-0153"))
        try ctx.save()
        #expect(DemirbasArama.kitap("2024-0153", context: ctx)?.id == kayitlar[1].id)
        #expect(DemirbasArama.kitap(" 2024-0153 ", context: ctx)?.id == kayitlar[1].id)
        #expect(DemirbasArama.kitap("2024-015", context: ctx) == nil)
        #expect(DemirbasArama.kitap("K-7", context: ctx)?.id == kayitlar[0].id)
        #expect(DemirbasArama.kitap("k-7", context: ctx)?.id == kayitlar[0].id)
        #expect(DemirbasArama.kitap("   ", context: ctx) == nil)
    }

    /// Arama barkod masasının kuralını kullanır: harf ve ayraç farkı sayılmaz; kod birden çok kitapta
    /// kayıtlıysa hepsi döner ve tek kitap seçilmez (ayrıntı kendiliğinden açılmaz).
    @Test func demirbasBarkodMasasiylaAyniKural() throws {
        let (ctx, kayitlar) = try baglam([
            Book(title: "Küçük Harfli", author: "Y"),
            Book(title: "Mükerrer A", author: "Y"),
            Book(title: "Mükerrer B", author: "Y"),
            Book(title: "İki Nüsha", author: "Y", quantity: 2),
            Book(title: "Harfli Kod", author: "Y", accessionCode: "abc")
        ])
        ctx.insert(BookCopy(bookID: kayitlar[0].id, accessionCode: "d-12"))
        ctx.insert(BookCopy(bookID: kayitlar[1].id, accessionCode: "77"))
        ctx.insert(BookCopy(bookID: kayitlar[2].id, accessionCode: "77"))
        ctx.insert(BookCopy(bookID: kayitlar[3].id, accessionCode: "K-5"))
        ctx.insert(BookCopy(bookID: kayitlar[3].id, accessionCode: "K5"))
        try ctx.save()

        for yazim in ["D-12", "d-12", "D12", " D-12 "] {
            #expect(DemirbasArama.kitap(yazim, context: ctx)?.id == kayitlar[0].id, "\(yazim)")
        }
        #expect(DemirbasArama.kitap("D-1", context: ctx) == nil)
        #expect(DemirbasArama.kitap("21", context: ctx) == nil, "Rakam sırası da tutmalı")
        #expect(try OkutCozumleyici.demirbasNushalari("D12", context: ctx).count == 1)

        #expect(DemirbasArama.kitap("77", context: ctx) == nil)
        #expect(DemirbasArama.kitaplar("77", context: ctx).map(\.title) == ["Mükerrer A", "Mükerrer B"])
        if case .hata(let ileti) = OkutCozumleyici.coz("77", context: ctx) {
            #expect(ileti.contains("birden çok nüshada"))
        } else { Issue.record("Barkod masası mükerrer demirbaşı reddetmeli") }

        // Aynı kitabın iki nüshası aynı kodu taşısa da kitap tektir.
        #expect(DemirbasArama.kitap("k5", context: ctx)?.id == kayitlar[3].id)
        // Rakamsız kod yalnız birebir ya da büyük/küçük harf farkıyla bulunur; sözcük aramasında nüsha taranmaz.
        #expect(DemirbasArama.kitap("ABC", context: ctx)?.id == kayitlar[4].id)
        #expect(DemirbasArama.kitaplar("orwell", context: ctx).isEmpty)
    }

    @Test func aramaGecmisiTekilVeSinirli() {
        AramaGecmisi.temizle()
        defer { AramaGecmisi.temizle() }
        for i in 0..<15 { AramaGecmisi.ekle("terim \(i)") }
        AramaGecmisi.ekle("TERIM 3")
        AramaGecmisi.ekle("a")   // çok kısa, eklenmez
        let liste = AramaGecmisi.hepsi()
        #expect(liste.count == AramaGecmisi.enFazla)
        #expect(liste.first == "TERIM 3")
        #expect(liste.filter { $0.lowercased() == "terim 3" }.count == 1)
    }
}

struct TopluBulDegistirTestleri {
    /// Bul-değiştir Türkçe harf eşlemesiyle büyük/küçük harf duyarsızdır.
    @Test func turkceHarflerdeEslesir() {
        #expect(BulkTextReplace.replacing("iş bankası", with: "İş Bankası Kültür", in: "İş Bankası Yayınları") == "İş Bankası Kültür Yayınları")
        #expect(BulkTextReplace.replacing("YAYINLARI", with: "Yayınları", in: "Can yayınları") == "Can Yayınları")
        #expect(BulkTextReplace.replacing("ışık", with: "Işık", in: "IŞIK Yayınevi") == "Işık Yayınevi")
        // Düz Latin i/I eşlemesi de korunur
        #expect(BulkTextReplace.replacing("penguin", with: "Penguin", in: "PENGUIN BOOKS") == "Penguin BOOKS")
        #expect(BulkTextReplace.replacing("yayinlari", with: "Yayınları", in: "Can YAYINLARI") == "Can Yayınları")
    }

    @Test func tumGecislerDegisirVeBosArananDokunmaz() {
        #expect(BulkTextReplace.replacing("a", with: "", in: "banana") == "bnn")
        #expect(BulkTextReplace.replacing("", with: "x", in: "Roman") == "Roman")
        #expect(BulkTextReplace.replacing("yok", with: "x", in: "Roman") == "Roman")
        #expect(BulkTextReplace.replacing("aa", with: "a", in: "aaaa") == "aa")
    }
}
