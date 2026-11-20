import Testing
import Foundation
import SwiftData
import PDFKit
@testable import _01

@MainActor
struct RaporBaskiTestleri {
    private func baglam(_ kitaplar: [Book]) throws -> (ModelContext, [CatalogBook]) {
        let ctx = ModelContext(try KitapVeritabani.makeContainer(inMemory: true))
        let kayitlar = kitaplar.map(CatalogBook.init(book:))
        kayitlar.forEach { ctx.insert($0) }
        try ctx.save()
        return (ctx, kayitlar)
    }

    @Test func aylikSayilarDogruAyaDuser() {
        let takvim = Calendar.current
        let simdi = takvim.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 12))!
        let gecenAy = takvim.date(byAdding: .month, value: -1, to: simdi)!
        let id = UUID()
        let olaylar = [
            LoanEvent(bookID: id, bookTitle: "A", person: "x", kind: .lent, date: simdi),
            LoanEvent(bookID: id, bookTitle: "A", person: "x", kind: .returned, date: simdi),
            LoanEvent(bookID: id, bookTitle: "A", person: "x", kind: .lent, date: gecenAy),
            LoanEvent(bookID: id, bookTitle: "A", person: "x", kind: .lent, date: takvim.date(byAdding: .year, value: -2, to: simdi)!)
        ]
        let aylar = RaporMotoru.aylikSayilar(events: olaylar, eklenmeTarihleri: [simdi, simdi, gecenAy], now: simdi)
        #expect(aylar.count == 12)
        #expect(aylar.last?.verilen == 1)
        #expect(aylar.last?.iade == 1)
        #expect(aylar.last?.eklenen == 2)
        #expect(aylar[10].verilen == 1)
        #expect(aylar.reduce(0) { $0 + $1.verilen } == 2)   // 2 yıl önceki sayılmaz
    }

    @Test func okunmayanlarVeKategoriDagilimi() throws {
        let (_, k) = try baglam([
            Book(title: "Okunan", author: "", category: "Roman", quantity: 2),
            Book(title: "Şu an ödünçte", author: "", category: "Roman"),
            Book(title: "Hiç", author: "", category: "Bilim", addedAt: .now.addingTimeInterval(-200 * 86_400)),
            Book(title: "Yeni hiç", author: "", addedAt: .now),
            Book(title: "Düşülmüş", author: "", category: "Bilim", isWithdrawn: true)
        ])
        let olaylar = [LoanEvent(bookID: k[0].id, bookTitle: "Okunan", person: "a", kind: .lent, date: .now)]
        let odunc = [ActiveLoan(bookID: k[1].id, bookTitleSnapshot: "", studentName: "b", studentClass: "", dueDate: .now)]
        #expect(RaporMotoru.okunmayanlar(k, events: olaylar, loans: odunc).map(\.title) == ["Hiç", "Yeni hiç"])
        #expect(RaporMotoru.okunmayanlar(k, events: olaylar, loans: odunc, enAzGun: 90).map(\.title) == ["Hiç"])

        let dagilim = RaporMotoru.kategoriDagilimi(k)
        #expect(dagilim.first?.ad == "Roman")
        #expect(dagilim.first?.sayi == 3)
        #expect(dagilim.contains { $0.ad == "Kategorisiz" && $0.sayi == 1 })
        #expect(dagilim.first { $0.ad == "Bilim" }?.sayi == 1)   // düşülen sayılmaz
    }

    @Test func donemRaporuPDFUretilir() throws {
        let (_, k) = try baglam([Book(title: "Nutuk", author: "Atatürk", category: "Tarih")])
        let olaylar = [LoanEvent(bookID: k[0].id, bookTitle: "Nutuk", person: "Ali", kind: .lent, date: .now),
                       LoanEvent(bookID: k[0].id, bookTitle: "Nutuk", person: "Ali", kind: .returned, date: .now)]
        let bolumler = RaporMotoru.donemBolumleri(kitaplar: k, events: olaylar, loans: [],
                                                   baslangic: .now.addingTimeInterval(-86_400), bitis: .now.addingTimeInterval(60))
        #expect(bolumler.count == 5)
        #expect(bolumler[1].rows.first?.1 == "1")
        #expect(bolumler[2].rows.first?.0 == "Nutuk")
        let pdf = PDFReportBuilder.build(title: "RAPOR", subtitle: "", sections: bolumler, signatures: ["Müdür", "Sorumlu"])
        let belge = try #require(PDFDocument(data: pdf))
        #expect(belge.pageCount >= 1)
        #expect(belge.string?.contains("Müdür") == true)
    }

    @Test func donemOkurSayisiAyniAdliUyeleriKimlikleAyirir() {
        let bookID = UUID(), memberOne = UUID(), memberTwo = UUID(), date = Date.now
        let events = [
            LoanEvent(bookID: bookID, bookTitle: "Eser", person: "Aynı Ad", kind: .lent, date: date, memberID: memberOne),
            LoanEvent(bookID: bookID, bookTitle: "Eser", person: "Aynı Ad", kind: .lent, date: date, memberID: memberOne),
            LoanEvent(bookID: bookID, bookTitle: "Eser", person: "Aynı Ad", kind: .lent, date: date, memberID: memberTwo),
            LoanEvent(bookID: bookID, bookTitle: "Eser", person: "Aynı Ad", kind: .lent, date: date, studentID: memberOne)
        ]
        let sections = RaporMotoru.donemBolumleri(kitaplar: [], events: events, loans: [],
            baslangic: date.addingTimeInterval(-1), bitis: date.addingTimeInterval(1))
        #expect(sections.flatMap(\.rows).first { $0.0 == "Kitap alan farklı okur" }?.1 == "3")
    }

    @Test func csvSutunlariVeKacis() throws {
        let (_, k) = try baglam([
            Book(title: "Ad; noktalı virgül", author: "Yazar \"Tırnak\"", isbn: "978", quantity: 2),
            Book(title: "=HYPERLINK(\"x\")", author: "Z")
        ])
        let csv = KitapCSV.olustur(k, sutunlar: [.ad, .yazar, .adet])
        #expect(csv.hasPrefix("\u{FEFF}Kitap Adı;Yazar;Adet"))
        #expect(csv.contains("\"Ad; noktalı virgül\";\"Yazar \"\"Tırnak\"\"\";2"))
        #expect(csv.contains("\"'=HYPERLINK(\"\"x\"\")\""))   // formül çalışmaz
    }

    @Test func qrBaglantisiGidipGelir() {
        let id = UUID()
        let url = KitapQR.url(for: id)
        #expect(url.absoluteString.hasPrefix("kitapbul://kitap/"))
        #expect(KitapQR.kitapID(from: url) == id)
        #expect(KitapQR.kitapID(from: URL(string: "https://kitap/\(id)")!) == nil)
        #expect(KitapQR.kitapID(from: URL(string: "kitapbul://kitap/bozuk")!) == nil)
        #expect(KitapQR.goruntu(url.absoluteString) != nil)
    }

    @Test func qrKartVeEtiketSablonlariPDF() throws {
        let kartlar = (0..<9).map { KitapKartiPDF.Kart(id: UUID(), baslik: "Kitap \($0)", yazar: "Yazar", yer: "Dolap A") }
        let kartPDF = try #require(PDFDocument(data: KitapKartiPDF.olustur(kartlar)))
        #expect(kartPDF.pageCount == 2)   // sayfada 8 kart

        let etiketler = (0..<30).map {
            SpineLabelBuilder.LabelInfo(callNumber: "813.4 / ALİ", title: "K\($0)", accessionCode: "D\($0)",
                                        barcodeValue: "9789750718434", category: "Roman", bookID: UUID())
        }
        for sablon in EtiketSablonu.allCases {
            let belge = try #require(PDFDocument(data: SpineLabelBuilder.build(etiketler, template: sablon)))
            let sayfada = sablon.izgara.sutun * sablon.izgara.satir
            #expect(belge.pageCount == (30 + sayfada - 1) / sayfada)
        }
    }

    @Test func deweyVeRenkKararli() {
        #expect(EtiketRengi.dewey("813") == "813")
        #expect(EtiketRengi.dewey("894.35") == "894.35")
        #expect(EtiketRengi.dewey("B-3") == nil)
        #expect(EtiketRengi.dewey("81") == nil)
        #expect(EtiketRengi.dewey("813.") == nil)
        #expect(SpineLabelBuilder.callNumber(category: "Roman", author: "Sabahattin Ali", location: "894.35") == "894.35 / ALİ")
        #expect(SpineLabelBuilder.callNumber(category: "Roman", author: "Sabahattin Ali", location: "B-3") == "ROM / ALİ")
        #expect(EtiketRengi.renk(for: "Roman") == EtiketRengi.renk(for: "roman"))
    }
}
