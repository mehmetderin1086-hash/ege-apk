import Testing
import Foundation
import SwiftData
@testable import _01

@MainActor
struct OduncOgrenciTestleri {
    private func baglam() throws -> ModelContext {
        ModelContext(try KitapVeritabani.makeContainer(inMemory: true))
    }

    @Test func iadedeRezervasyonSiradakineGider() throws {
        let ctx = try baglam()
        let kitap = CatalogBook(book: Book(title: "Simyacı", author: "Coelho", quantity: 1))
        ctx.insert(kitap)
        let loan = ActiveLoan(bookID: kitap.id, bookTitleSnapshot: kitap.title, studentName: "Ali", studentClass: "6-A",
                              dueDate: .now.addingTimeInterval(86_400))
        ctx.insert(loan)
        try ctx.save()

        // Bu akış kayıtlı öğrenci seçimi değil, açıkça elle girilmiş okur kuyruğudur.
        let ilk = try OduncMerkezi.rezerveEt(book: kitap, student: "Ayşe", className: "6-B", context: ctx, resolveKnownStudent: false)
        let ayni = try OduncMerkezi.rezerveEt(book: kitap, student: "ayse", className: "6-B", context: ctx, resolveKnownStudent: false)
        #expect(ilk.id == ayni.id)   // aynı elle girilmiş okur iki kez sıraya girmez
        try OduncMerkezi.rezerveEt(book: kitap, student: "Can", className: "", context: ctx, resolveKnownStudent: false)
        #expect(throws: OduncMerkezi.OduncHatasi.self) { try OduncMerkezi.rezerveEt(book: kitap, student: " ", className: "", context: ctx, resolveKnownStudent: false) }

        let bildirim = OduncMerkezi.iadeAl(loan, context: ctx)
        #expect(bildirim?.contains("Ayşe") == true)
        #expect(try ctx.fetchCount(FetchDescriptor<ActiveLoan>()) == 0)
        #expect(ilk.notifiedAt != nil)
        // Haber verilen sırayı tıkamaz: sonraki iade sıradaki öğrenciye (Can) gider
        #expect(OduncMerkezi.rezervasyonuBildir(bookID: kitap.id, title: kitap.title, context: ctx)?.contains("Can") == true)
        #expect(OduncMerkezi.rezervasyonuBildir(bookID: kitap.id, title: kitap.title, context: ctx) == nil)
    }

    @Test func uzatmaKurallari() throws {
        let ctx = try baglam()
        let kitap = CatalogBook(book: Book(title: "A", author: ""))
        ctx.insert(kitap)
        let simdi = Date(timeIntervalSince1970: 1_800_000_000)
        let loan = ActiveLoan(bookID: kitap.id, bookTitleSnapshot: "A", studentName: "Ali", studentClass: "", dueDate: simdi)
        ctx.insert(loan)
        try ctx.save()

        let bir = try OduncMerkezi.uzat(loan, context: ctx, defaultDays: 10, now: simdi)
        #expect(Calendar.current.dateComponents([.day], from: simdi, to: bir).day == 10)
        _ = try OduncMerkezi.uzat(loan, context: ctx, defaultDays: 10, now: simdi)
        #expect(loan.extensionCount == 2)
        #expect(throws: OduncMerkezi.OduncHatasi.self) { try OduncMerkezi.uzat(loan, context: ctx, now: simdi) }

        // Rezervasyon bekleyen kitap uzatılamaz
        let loan2 = ActiveLoan(bookID: kitap.id, bookTitleSnapshot: "A", studentName: "Can", studentClass: "", dueDate: simdi)
        ctx.insert(loan2)
        try OduncMerkezi.rezerveEt(book: kitap, student: "Ece", className: "", context: ctx)
        #expect(throws: OduncMerkezi.OduncHatasi.self) { try OduncMerkezi.uzat(loan2, context: ctx, now: simdi) }
    }

    @Test func kayipAdetDusurVeTutanakUretir() throws {
        let ctx = try baglam()
        let cok = CatalogBook(book: Book(title: "Çok Nüsha", author: "Y", isbn: "9789750718434", quantity: 3, accessionCode: "D-7"))
        let tek = CatalogBook(book: Book(title: "Tek Nüsha", author: "Z", quantity: 1))
        ctx.insert(cok)
        ctx.insert(tek)
        let l1 = ActiveLoan(bookID: cok.id, bookTitleSnapshot: cok.title, studentName: "Ali", studentClass: "7-C", dueDate: .now)
        let l2 = ActiveLoan(bookID: tek.id, bookTitleSnapshot: tek.title, studentName: "Veli", studentClass: "", dueDate: .now)
        ctx.insert(l1)
        ctx.insert(l2)
        try ctx.save()

        let tutanak = OduncMerkezi.kayipBildir(l1, context: ctx)
        #expect(cok.quantity == 2)
        #expect(tutanak.contains("KAYIP KİTAP TUTANAĞI"))
        #expect(tutanak.contains("D-7"))
        #expect(tutanak.contains("Ali (7-C)"))
        _ = OduncMerkezi.kayipBildir(l2, context: ctx)
        #expect(tek.isWithdrawn)
        #expect(tek.withdrawnReason == "Kayıp")
        #expect(try ctx.fetchCount(FetchDescriptor<ActiveLoan>()) == 0)
    }

    @Test func veliMesajiGecikmeyiYazar() {
        let simdi = Date(timeIntervalSince1970: 1_800_000_000)
        let mesaj = OduncMerkezi.veliMesaji(ogrenci: "Ali", sinif: "5-A", kitap: "Nutuk",
                                            sonGun: simdi.addingTimeInterval(-3 * 86_400), okul: "Atatürk Ortaokulu", now: simdi)
        #expect(mesaj.contains("Ali (5-A)"))
        #expect(mesaj.contains("“Nutuk”"))
        #expect(mesaj.contains("3 gün gecikti"))
        #expect(mesaj.contains("Atatürk Ortaokulu Kütüphanesi"))
    }

    /// Son günü gelmemiş ödünçte mesaj "iade etmeliydi" demez; gecikme takvim günüyle sayılır.
    @Test func veliMesajiVadesiGelmemisOduncteHatirlatir() {
        let takvim = Calendar.current
        let bugun = takvim.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let sabah = bugun.addingTimeInterval(9 * 3_600)
        let ileri = OduncMerkezi.veliMesaji(ogrenci: "Ali", sinif: "", kitap: "Nutuk", sonGun: bugun.addingTimeInterval(14 * 86_400), now: sabah)
        #expect(ileri.contains("tarihine kadar iade etmelidir"))
        #expect(!ileri.contains("etmeliydi"))
        #expect(!ileri.contains("gecikti"))
        // Dün 15:00 son gün, bugün 09:00 → 24 saat dolmadı ama takvimde 1 gün gecikti
        let dun = OduncMerkezi.veliMesaji(ogrenci: "Ali", sinif: "", kitap: "Nutuk", sonGun: bugun.addingTimeInterval(-9 * 3_600), now: sabah)
        #expect(dun.contains("1 gün gecikti"))
    }

    /// Gecikme engeli de ekranlar gibi gün sonunu bekler: son gün içinde engellenmez.
    @Test func gecikmeEngeliSonGunIcindeEngellemez() throws {
        let bugun = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let loans = [ActiveLoan(bookID: UUID(), bookTitleSnapshot: "A", studentName: "Ali", studentClass: "5-A", dueDate: bugun.addingTimeInterval(10 * 3_600))]
        try OduncKotasi.denetle(kisi: "Ali", sinif: "5-A", loans: loans, now: bugun.addingTimeInterval(11 * 3_600), kurallar: [], genelSinir: 0, gecikmeEngeli: true)
        #expect(throws: OduncMerkezi.OduncHatasi.self) {
            try OduncKotasi.denetle(kisi: "Ali", sinif: "5-A", loans: loans, now: bugun.addingTimeInterval(35 * 3_600), kurallar: [], genelSinir: 0, gecikmeEngeli: true)
        }
    }

    @Test func okumaPuaniTekrarSismez() {
        let a = UUID(), b = UUID(), ali = UUID(), ayse = UUID()
        let olaylar = [
            LoanEvent(bookID: a, bookTitle: "A", person: "Ali", kind: .returned, date: .now, studentID: ali, readingCompleted: true),
            LoanEvent(bookID: a, bookTitle: "A", person: "ALİ", kind: .returned, date: .now, studentID: ali, readingCompleted: true),   // aynı kitap tekrar
            LoanEvent(bookID: b, bookTitle: "B", person: "Ali", kind: .returned, date: .now, wasLate: true, studentID: ali, readingCompleted: true),
            LoanEvent(bookID: b, bookTitle: "B", person: "Ayşe", kind: .returned, date: .now, studentID: ayse, readingCompleted: true),
            LoanEvent(bookID: b, bookTitle: "B", person: "Ayşe", kind: .lent, date: .now),
            LoanEvent(bookID: a, bookTitle: "A", person: "Can", kind: .lost, date: .now)
        ]
        let sira = OkumaPuani.siralama(olaylar)
        #expect(sira.first?.ad.lowercased().hasPrefix("al") == true)
        #expect(sira.first?.puan == 13)
        #expect(sira.first?.kitapSayisi == 2)
        #expect(OkumaPuani.puan(for: "Ayşe", events: olaylar) == 10)
        #expect(OkumaPuani.puan(for: "Can", events: olaylar) == 0)
    }

    @Test func sinifAtlatmaKurallari() {
        #expect(SinifAtlatma.sonrakiSinif("5-A", sonKademe: 8) == "6-A")
        #expect(SinifAtlatma.sonrakiSinif("9/B", sonKademe: 12) == "10/B")
        #expect(SinifAtlatma.sonrakiSinif("11A", sonKademe: 12) == "12A")
        #expect(SinifAtlatma.sonrakiSinif("8-C", sonKademe: 8) == nil)
        #expect(SinifAtlatma.sonrakiSinif("Anasınıfı", sonKademe: 8) == "Anasınıfı")

        let plan = SinifAtlatma.plan([
            Student(name: "A", className: "7-A"), Student(name: "B", className: "8-A"), Student(name: "C", className: "")
        ], sonKademe: 8)
        #expect(plan.map(\.yeniSinif) == ["8-A", nil, ""])
    }

    @Test func csvBasligindaOgrenciNoAdSanilmaz() {
        let tahmin = OgrenciCSVEslestirme.tahmin(["Öğrenci No", "Adı Soyadı", "Sınıfı"])
        #expect(tahmin.no == 0)
        #expect(tahmin.ad == 1)
        #expect(tahmin.sinif == 2)
    }

    @Test func eskiYedektekiKimliksizKayitKararliKimlikAlir() {
        let json = #"[{"title":"A","author":"B","notes":"","addedAt":"2024-01-01T00:00:00Z"}]"#
        let bir = CatalogBackup.decode(Data(json.utf8)).first?.id
        let iki = CatalogBackup.decode(Data(json.utf8)).first?.id
        #expect(bir != nil && bir == iki)
    }

    @Test func csvSutunlariTahminVeEsleme() {
        let csv = "Okul No;Adı Soyadı;Şube\n101;Ali Yılmaz;5-A\n102;Ayşe Demir;5-B\n;;\n103;;5-C\n"
        let satirlar = OgrenciCSVEslestirme.satirlar(Data(csv.utf8))
        // Önizleme hatayı özgün satır numarasıyla göstermeli; boş veri satırı korunur.
        #expect(satirlar.count == 5)
        #expect(satirlar[3] == ["", "", ""])
        let tahmin = OgrenciCSVEslestirme.tahmin(satirlar[0])
        #expect(tahmin.ad == 1)
        #expect(tahmin.no == 0)
        #expect(tahmin.sinif == 2)
        let ogrenciler = OgrenciCSVEslestirme.ogrenciler(satirlar, ad: 1, no: 0, sinif: 2, baslikVar: true)
        #expect(ogrenciler.map(\.name) == ["Ali Yılmaz", "Ayşe Demir"])   // adsız satır atlanır
        #expect(ogrenciler.first?.number == "101")
        #expect(ogrenciler.last?.className == "5-B")
    }

    @Test func sonGunMetniTakvimGunuyleVeTurkce() {
        let simdi = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_800_000_000))!
        let gun = { (fark: Int) in Calendar.current.date(byAdding: .day, value: fark, to: simdi)! }
        #expect(OduncMerkezi.gecikmeGunu(sonGun: gun(-12), now: simdi) == 12)
        #expect(OduncMerkezi.sonGunMetni(gun(-12), now: simdi) == "12 gün gecikti")
        // Son gün bugünse saatten bağımsız olarak gecikme yok.
        #expect(OduncMerkezi.sonGunMetni(Calendar.current.startOfDay(for: simdi), now: simdi) == "Bugün son gün")
        let ileri = OduncMerkezi.sonGunMetni(gun(3), now: simdi)
        #expect(ileri.hasPrefix("Son gün: "))
        // Tarih cihaz dilinden bağımsız Türkçe ay adıyla yazılır.
        let turkceAylar = ["Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"]
        #expect(turkceAylar.contains { ileri.contains($0) })
    }

    @Test func kioskPINVarsayilanVeKisaPINKabulEdilmez() {
        #expect(!KioskPIN.gecerli(""))
        #expect(!KioskPIN.gecerli(KioskPIN.varsayilan))
        #expect(!KioskPIN.gecerli("123"))
        #expect(!KioskPIN.gecerli("123456789"))
        #expect(!KioskPIN.gecerli("12a4"))
        #expect(!KioskPIN.gecerli("١٢٣٤٥"))   // yalnız 0-9 rakamları
        #expect(KioskPIN.gecerli("4826"))
        #expect(KioskPIN.gecerli("90817263"))
        #expect(KioskPIN.sorun("1234") == "1234 herkesçe bilinir; başka bir PIN seçin.")
        #expect(KioskPIN.sorun("4826", tekrar: "4827") == "İki PIN aynı değil.")
        #expect(KioskPIN.sorun("4826", tekrar: "4826") == nil)
    }
}
