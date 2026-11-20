import Testing
import Foundation
import SwiftData
@testable import _01

/// Paket 4 (Dolaşım) geliştirme turu: kiosk oturumu ve PIN, nüsha doğruluğu, yıllık liste, rezervasyon
/// süresi, toplu işlem ve önbellek davranışları.
@MainActor
@Suite(.serialized)
struct DolasimGelistirmeTests {
    private func context() throws -> ModelContext { ModelContext(try KitapVeritabani.makeContainer(inMemory: true)) }

    /// Öğrenci/üye/geçmiş/kural dosyalarını geçici klasöre yönlendirir.
    private func izole(_ islem: () throws -> Void) throws {
        let dizin = FileManager.default.temporaryDirectory.appendingPathComponent("dolasim-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dizin, withIntermediateDirectories: true)
        let geri = StoreLocations.install(.isolated(root: dizin))
        StudentStore.invalidateCaches(); MemberStore.invalidateCaches()
        defer {
            geri()
            StudentStore.invalidateCaches(); MemberStore.invalidateCaches()
            try? FileManager.default.removeItem(at: dizin)
        }
        try islem()
    }

    private func takvim() -> Calendar {
        var takvim = Calendar(identifier: .gregorian)
        takvim.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return takvim
    }
    private func an(_ yil: Int, _ ay: Int, _ gun: Int, _ saat: Int = 14) -> Date {
        takvim().date(from: DateComponents(year: yil, month: ay, day: gun, hour: saat, minute: 0))!
    }

    // MARK: Kiosk oturumu ve PIN

    @Test func kioskKisiOturumuIslemSonrasiVeHareketsizlikteSifirlanir() {
        let baslangic = Date(timeIntervalSince1970: 1_800_000_000)
        var oturum = KioskKisiOturumu(sonEtkilesim: baslangic)
        oturum.kartOkundu(Student(name: "Ali Kaya", number: "17", className: "5-A"), now: baslangic)
        #expect(oturum.kisiVar && oturum.sinif == "5-A" && oturum.studentID != nil)
        #expect(!oturum.suresiDoldu(now: baslangic.addingTimeInterval(44)))
        #expect(oturum.suresiDoldu(now: baslangic.addingTimeInterval(45)))
        // Etkileşim süreyi yeniler
        oturum.etkilesim(now: baslangic.addingTimeInterval(40))
        #expect(!oturum.suresiDoldu(now: baslangic.addingTimeInterval(80)))
        oturum.temizle(now: baslangic.addingTimeInterval(80))
        #expect(!oturum.kisiVar && oturum.studentID == nil && oturum.sinif.isEmpty && oturum.ad.isEmpty)
        // Kişi yokken zaman aşımı sayılmaz
        #expect(!oturum.suresiDoldu(now: baslangic.addingTimeInterval(500)))
    }

    private final class BellekDeposu: KioskPINDeposu {
        var veri: Data?
        var yazmaHatasi = false
        func oku() -> Data? { veri }
        func yaz(_ veri: Data) throws {
            if yazmaHatasi { throw SchoolLibraryService.OperationError(message: "yazılamadı") }
            self.veri = veri
        }
        func sil() { veri = nil }
    }

    private func pinOrtami(_ islem: (BellekDeposu, UserDefaults) throws -> Void) rethrows {
        let eski = KioskPIN.depo
        let deposu = BellekDeposu()
        KioskPIN.depo = deposu
        let adi = "kiosk-pin-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: adi)!
        defer { KioskPIN.depo = eski; defaults.removePersistentDomain(forName: adi) }
        try islem(deposu, defaults)
    }

    @Test func kioskPINOzetSaklarDogrularYanlisiReddeder() throws {
        try pinOrtami { depo, defaults in
            #expect(!KioskPIN.ayarli(defaults: defaults))
            try KioskPIN.kaydet("4826", defaults: defaults)
            #expect(KioskPIN.ayarli(defaults: defaults))
            #expect(KioskPIN.dogrula("4826", defaults: defaults))
            #expect(!KioskPIN.dogrula("4827", defaults: defaults))
            #expect(!KioskPIN.dogrula("", defaults: defaults))
            // Düz metin saklanmaz
            let veri = try #require(depo.veri)
            #expect(!String(decoding: veri, as: UTF8.self).contains("4826"))
            // Geçersiz PIN kaydedilmez
            #expect(throws: SchoolLibraryService.OperationError.self) { try KioskPIN.kaydet("1234", defaults: defaults) }
            #expect(KioskPIN.dogrula("4826", defaults: defaults))
        }
    }

    @Test func kioskPINEskiUserDefaultsDegeriniOzeteTasir() {
        pinOrtami { depo, defaults in
            defaults.set("90817263", forKey: KioskPIN.anahtar)
            #expect(KioskPIN.dogrula("90817263", defaults: defaults))
            // Özet yazıldı ve düz metin silindi
            #expect(depo.veri != nil)
            #expect(defaults.string(forKey: KioskPIN.anahtar) == nil)
            #expect(KioskPIN.dogrula("90817263", defaults: defaults))
            #expect(!KioskPIN.dogrula("1234", defaults: defaults))
        }
    }

    @Test func kioskPINGocBasarisizsaEskiDegerKorunurVeKiosKilitlenmez() {
        pinOrtami { depo, defaults in
            depo.yazmaHatasi = true
            defaults.set("4826", forKey: KioskPIN.anahtar)
            #expect(KioskPIN.ayarli(defaults: defaults))
            #expect(KioskPIN.dogrula("4826", defaults: defaults))
            #expect(defaults.string(forKey: KioskPIN.anahtar) == "4826")
            #expect(!KioskPIN.dogrula("0000", defaults: defaults))
        }
    }

    @Test func kioskPINVarsayilanDegerAyarliSayilmaz() {
        pinOrtami { _, defaults in
            defaults.set("1234", forKey: KioskPIN.anahtar)
            #expect(!KioskPIN.ayarli(defaults: defaults))
            #expect(!KioskPIN.dogrula("1234", defaults: defaults))
        }
    }

    // MARK: Ders kitabı teslimi

    private func dersKitabiOdunc(_ ctx: ModelContext, durum: String) throws -> (CatalogBook, BookCopy, ActiveLoan) {
        let kitap = CatalogBook(book: Book(title: "Biyoloji 9", author: "MEB", quantity: 1))
        ctx.insert(kitap)
        let nusha = BookCopy(bookID: kitap.id, accessionCode: "DK-1", condition: durum)
        ctx.insert(nusha)
        try ctx.save()
        let odunc = try SchoolLibraryService.lend(book: kitap, person: "Ali", className: "9-A", context: ctx, copyID: nusha.id, kind: "textbook")
        return (kitap, nusha, odunc)
    }

    @Test func dersKitabiTeslimindeDurumBelirtilmediyseNushaDurumuDegismez() throws {
        try izole {
            let ctx = try context()
            let (_, nusha, odunc) = try dersKitabiOdunc(ctx, durum: "Yıpranmış")
            let sonuc = try TextbookOperations.collect(loanIDs: [odunc.id], conditions: [:], context: ctx)
            #expect(sonuc.collectedIDs == [odunc.id])
            #expect(nusha.condition == "Yıpranmış")
            #expect(nusha.status == "Rafta")
        }
    }

    @Test func dersKitabiTeslimindeBilincliIyiSecimiDurumuYazar() throws {
        try izole {
            let ctx = try context()
            let (_, nusha, odunc) = try dersKitabiOdunc(ctx, durum: "Yıpranmış")
            _ = try TextbookOperations.collect(loanIDs: [odunc.id], conditions: [odunc.id: "İyi"], context: ctx)
            #expect(nusha.condition == "İyi")
        }
    }

    // MARK: Kayıp ve nüsha doğruluğu

    @Test func kayipNushaBagliysaNushaKayipOlurAdetDegismez() throws {
        try izole {
            let ctx = try context()
            let kitap = CatalogBook(book: Book(title: "Çok", author: "Y", quantity: 3))
            ctx.insert(kitap)
            let a = BookCopy(bookID: kitap.id, accessionCode: "A-1"), b = BookCopy(bookID: kitap.id, accessionCode: "A-2")
            ctx.insert(a); ctx.insert(b); try ctx.save()
            let odunc = try SchoolLibraryService.lend(book: kitap, person: "Ali", className: "", context: ctx, copyID: a.id)
            let tutanak = try SchoolLibraryService.reportLost(odunc, context: ctx)
            #expect(tutanak.contains("A-1"))
            #expect(a.status == "Kayıp" && b.status == "Rafta")
            #expect(kitap.quantity == 3)
        }
    }

    @Test func kayipNushasizOduncteNushaKaydiVarsaHataVerirAdetDusmez() throws {
        try izole {
            let ctx = try context()
            let kitap = CatalogBook(book: Book(title: "Çok", author: "Y", quantity: 3))
            ctx.insert(kitap)
            let nusha = BookCopy(bookID: kitap.id, accessionCode: "A-1")
            ctx.insert(nusha)
            let odunc = ActiveLoan(bookID: kitap.id, bookTitleSnapshot: kitap.title, studentName: "Ali", studentClass: "", dueDate: .now)
            ctx.insert(odunc); try ctx.save()
            do {
                _ = try SchoolLibraryService.reportLost(odunc, context: ctx)
                Issue.record("Nüshasız ödünçte kayıp bildirimi hata vermeliydi")
            } catch let hata as SchoolLibraryService.OperationError {
                #expect(hata.kod == .kayipNushaGerekli)
            }
            #expect(kitap.quantity == 3 && nusha.status == "Rafta")
            #expect(try ctx.fetchCount(FetchDescriptor<ActiveLoan>()) == 1)
        }
    }

    @Test func kayipNushaKaydiYoksaAdetDuserVeTekAdetteDusulur() throws {
        try izole {
            let ctx = try context()
            let cok = CatalogBook(book: Book(title: "Çok", author: "Y", quantity: 3))
            let tek = CatalogBook(book: Book(title: "Tek", author: "Y", quantity: 1))
            ctx.insert(cok); ctx.insert(tek)
            let l1 = ActiveLoan(bookID: cok.id, bookTitleSnapshot: cok.title, studentName: "Ali", studentClass: "", dueDate: .now)
            let l2 = ActiveLoan(bookID: tek.id, bookTitleSnapshot: tek.title, studentName: "Veli", studentClass: "", dueDate: .now)
            ctx.insert(l1); ctx.insert(l2); try ctx.save()
            _ = try SchoolLibraryService.reportLost(l1, context: ctx)
            _ = try SchoolLibraryService.reportLost(l2, context: ctx)
            #expect(cok.quantity == 2)
            #expect(tek.isWithdrawn && tek.withdrawnReason == "Kayıp")
        }
    }

    @Test func gorevliModundaYoneticiKapilariOperationErrorVerir() throws {
        try izole {
            let ctx = try context()
            let kilit = YetkiDurumu.shared.kilitEtkin
            defer { YetkiDurumu.shared.kilitEtkin = kilit }
            let ogrenci = Student(name: "Ali", number: "1", className: "5-A")
            let uye = Member(name: "Hoca")
            try StudentStore.replaceAllVerified([ogrenci]); try MemberStore.replaceAllVerified([uye])
            let kitap = CatalogBook(book: Book(title: "K", author: "Y", quantity: 1))
            ctx.insert(kitap)
            let odunc = ActiveLoan(bookID: kitap.id, bookTitleSnapshot: kitap.title, studentName: "Ali", studentClass: "5-A", dueDate: .now)
            ctx.insert(odunc); try ctx.save()
            YetkiDurumu.shared.kilitEtkin = true; YetkiDurumu.shared.gorevliyeGec()
            #expect(!YetkiDurumu.shared.yonetici)
            #expect(throws: SchoolLibraryService.OperationError.self) { try SchoolLibraryService.reportLost(odunc, context: ctx) }
            #expect(throws: SchoolLibraryService.OperationError.self) { try StudentStore.removeVerified(id: ogrenci.id, context: ctx) }
            #expect(throws: SchoolLibraryService.OperationError.self) { try MemberStore.removeVerified(id: uye.id, context: ctx) }
            #expect(throws: SchoolLibraryService.OperationError.self) { try MemberStore.updateKind(id: uye.id, kind: .teacher) }
            #expect(throws: SchoolLibraryService.OperationError.self) { try SchoolLibraryService.batchLend(book: kitap, students: [ogrenci], className: "5-A", context: ctx) }
            #expect(try ctx.fetchCount(FetchDescriptor<ActiveLoan>()) == 1)
        }
    }

    @Test func lendBirdenCokBosNushadaSorarTekNushadaOtomatikSecer() throws {
        try izole {
            let ctx = try context()
            let kitap = CatalogBook(book: Book(title: "Çok", author: "Y", quantity: 2))
            ctx.insert(kitap)
            let a = BookCopy(bookID: kitap.id, accessionCode: "A-1"), b = BookCopy(bookID: kitap.id, accessionCode: "A-2")
            ctx.insert(a); ctx.insert(b); try ctx.save()
            do {
                _ = try SchoolLibraryService.lend(book: kitap, person: "Ali", className: "", context: ctx, nusha: .sor)
                Issue.record("İki boş nüshada soru beklenirdi")
            } catch let hata as SchoolLibraryService.OperationError { #expect(hata.kod == .nushaBelirsiz) }
            #expect(try ctx.fetchCount(FetchDescriptor<ActiveLoan>()) == 0)
            // Demirbaş verilirse sorulmaz
            let ilk = try SchoolLibraryService.lend(book: kitap, person: "Ali", className: "", context: ctx, copyID: b.id, nusha: .sor)
            #expect(ilk.copyID == b.id)
            // Geriye tek boş nüsha kaldı: otomatik
            let ikinci = try SchoolLibraryService.lend(book: kitap, person: "Veli", className: "", context: ctx, nusha: .sor)
            #expect(ikinci.copyID == a.id)
        }
    }

    @Test func lendNushasizKaydetDemirbassizAdetOlarakYazar() throws {
        try izole {
            let ctx = try context()
            let kitap = CatalogBook(book: Book(title: "Çok", author: "Y", quantity: 2))
            ctx.insert(kitap)
            ctx.insert(BookCopy(bookID: kitap.id, accessionCode: "A-1")); ctx.insert(BookCopy(bookID: kitap.id, accessionCode: "A-2"))
            try ctx.save()
            let odunc = try SchoolLibraryService.lend(book: kitap, person: "Ali", className: "", context: ctx, nusha: .nushasiz)
            #expect(odunc.copyID == nil)
        }
    }

    @Test func aynıEserIkinciKezAyniOkuraVerilmezYineDeVerGecer() throws {
        try izole {
            let ctx = try context()
            let ogrenci = Student(name: "Ali", number: "1", className: "5-A")
            try StudentStore.replaceAllVerified([ogrenci])
            let kitap = CatalogBook(book: Book(title: "Çok", author: "Y", quantity: 3))
            ctx.insert(kitap); try ctx.save()
            _ = try SchoolLibraryService.lend(book: kitap, person: ogrenci.name, className: ogrenci.className, context: ctx, studentID: ogrenci.id)
            do {
                _ = try SchoolLibraryService.lend(book: kitap, person: ogrenci.name, className: ogrenci.className, context: ctx, studentID: ogrenci.id)
                Issue.record("Aynı eser ikinci kez verilmemeliydi")
            } catch let hata as SchoolLibraryService.OperationError { #expect(hata.kod == .zatenElinde) }
            #expect(try ctx.fetchCount(FetchDescriptor<ActiveLoan>()) == 1)
            _ = try SchoolLibraryService.lend(book: kitap, person: ogrenci.name, className: ogrenci.className, context: ctx, studentID: ogrenci.id, yineDeVer: true)
            #expect(try ctx.fetchCount(FetchDescriptor<ActiveLoan>()) == 2)
        }
    }

    @Test func dersKitabiSetiAyniOkuraIkiKezVerilebilir() throws {
        try izole {
            let ctx = try context()
            let ogrenci = Student(name: "Ali", number: "1", className: "5-A")
            try StudentStore.replaceAllVerified([ogrenci])
            let kitap = CatalogBook(book: Book(title: "Matematik", author: "MEB", quantity: 3))
            ctx.insert(kitap); try ctx.save()
            for _ in 0..<2 {
                _ = try SchoolLibraryService.lend(book: kitap, person: ogrenci.name, className: ogrenci.className, context: ctx, studentID: ogrenci.id, kind: "textbook")
            }
            #expect(try ctx.fetchCount(FetchDescriptor<ActiveLoan>()) == 2)
        }
    }

    // MARK: Rezervasyon süresi

    @Test func ayirmaSuresiOkulGunuyleSayilirCumaCumartesiPazarıAtlar() {
        let cuma = an(2026, 10, 23)
        #expect(ReservationPolicy.holdExpiry(from: cuma, schoolDays: 2, calendar: takvim()) == an(2026, 10, 27))
        // Salı 14:00 + 2 gün = Perşembe 14:00 (eski 48 saat ile aynı)
        #expect(ReservationPolicy.holdExpiry(from: an(2026, 10, 20), schoolDays: 2, calendar: takvim()) == an(2026, 10, 22))
        #expect(ReservationPolicy.holdExpiry(from: cuma, schoolDays: 1, calendar: takvim()) == an(2026, 10, 26))
    }

    @Test func ayirmaSuresiTatilAraliginiAtlar() {
        let tatil = DateInterval(start: an(2026, 10, 26, 0), end: an(2026, 10, 27, 0))
        // Cuma + 2 okul günü, Pazartesi-Salı tatil → Çarşamba(1), Perşembe(2)
        #expect(ReservationPolicy.holdExpiry(from: an(2026, 10, 23), schoolDays: 2, holidays: [tatil], calendar: takvim()) == an(2026, 10, 29))
    }

    // MARK: Yıllık öğrenci listesi

    private func csv(_ satirlar: [[String]]) -> [[String]] { satirlar }

    @Test func tekAdayVeNumaraEslesmesiVarsayilanOlarakKimligiKorur() throws {
        try izole {
            let ctx = try context()
            let ali = Student(name: "Ali Kaya", number: "17", className: "5-A")
            try StudentStore.replaceAllVerified([ali])
            let onizleme = try StudentImportService.preview(rows: [["Ad", "No", "Sınıf"], ["Ali Kaya", "17", "6-A"], ["Yeni Öğrenci", "99", "6-A"]],
                                                           mapping: .init(nameColumn: 0, numberColumn: 1, classColumn: 2))
            #expect(onizleme.conflicts.isEmpty)
            #expect(onizleme.autoUpdates.count == 1)
            let satir = try #require(onizleme.rows.first { $0.line == 2 })
            #expect(satir.defaultResolution == .update(ali.id))
            #expect(satir.issue?.contains("5-A → 6-A") == true)
            let sonuc = try StudentImportService.apply(onizleme, context: ctx)
            #expect(sonuc.updated == 1 && sonuc.added == 1)
            let liste = try StudentStore.allVerified()
            #expect(liste.first { $0.id == ali.id }?.className == "6-A")
            #expect(liste.count == 2)
        }
    }

    @Test func cokAdayVeyaCiftNumaraKararListesinedGirer() throws {
        try izole {
            let a = Student(name: "Ali", number: "17", className: "5-A")
            let b = Student(name: "Ali", number: "18", className: "5-A")
            try StudentStore.replaceAllVerified([a, b])
            // Ad+sınıf iki kişiye uyuyor, numara yok: belirsiz
            let belirsiz = try StudentImportService.preview(rows: [["Ali", "", "5-A"]], mapping: .init(nameColumn: 0, numberColumn: 1, classColumn: 2, hasHeader: false))
            #expect(belirsiz.conflicts.count == 1 && belirsiz.autoUpdates.isEmpty)
            // Dosyada aynı numara iki kişide
            let cift = try StudentImportService.preview(rows: [["Ali", "17", "6-A"], ["Veli", "17", "6-B"]], mapping: .init(nameColumn: 0, numberColumn: 1, classColumn: 2, hasHeader: false))
            #expect(cift.autoUpdates.isEmpty)
            #expect(cift.conflicts.count == 2)
        }
    }

    @Test func sinifSutunuYoksaKimlikGuncellemesiSinifiSilmez() throws {
        try izole {
            let ctx = try context()
            let ali = Student(name: "Ali", number: "17", className: "5-A")
            try StudentStore.replaceAllVerified([ali])
            let onizleme = try StudentImportService.preview(rows: [["Ali Veli", "17"]], mapping: .init(nameColumn: 0, numberColumn: 1, classColumn: nil, hasHeader: false))
            #expect(onizleme.autoUpdates.count == 1)
            _ = try StudentImportService.apply(onizleme, context: ctx)
            let guncel = try #require(StudentStore.allVerified().first)
            #expect(guncel.id == ali.id && guncel.name == "Ali Veli" && guncel.className == "5-A")
        }
    }

    @Test func geriAlmaGuncellenenKimlikteAcikOduncuEngellemezVeSinifiGeriYazar() throws {
        try izole {
            let ctx = try context()
            let ali = Student(name: "Ali", number: "17", className: "5-A")
            try StudentStore.replaceAllVerified([ali])
            let kitap = CatalogBook(book: Book(title: "K", author: "Y", quantity: 2))
            ctx.insert(kitap); try ctx.save()
            let odunc = try SchoolLibraryService.lend(book: kitap, person: ali.name, className: ali.className, context: ctx, studentID: ali.id)
            let onizleme = try StudentImportService.preview(rows: [["Ali", "17", "6-A"]], mapping: .init(nameColumn: 0, numberColumn: 1, classColumn: 2, hasHeader: false))
            _ = try StudentImportService.apply(onizleme, context: ctx)
            #expect(odunc.studentClass == "6-A")
            #expect(try StudentImportService.undoLast(context: ctx) == 1)
            #expect(try StudentStore.allVerified().first?.className == "5-A")
            #expect(odunc.studentClass == "5-A")
        }
    }

    @Test func geriAlmaYalnizYeniEklenenKimliktekiAcikOduncuEngeller() throws {
        try izole {
            let ctx = try context()
            let onizleme = try StudentImportService.preview(rows: [["Ayşe", "18", "5-A"]], mapping: .init(nameColumn: 0, numberColumn: 1, classColumn: 2, hasHeader: false))
            _ = try StudentImportService.apply(onizleme, context: ctx)
            let ayse = try #require(StudentStore.allVerified().first)
            let kitap = CatalogBook(book: Book(title: "K", author: "Y", quantity: 2))
            ctx.insert(kitap); try ctx.save()
            _ = try SchoolLibraryService.lend(book: kitap, person: ayse.name, className: ayse.className, context: ctx, studentID: ayse.id)
            #expect(throws: SchoolLibraryService.OperationError.self) { try StudentImportService.undoLast(context: ctx) }
            #expect(try StudentStore.allVerified().count == 1)
        }
    }

    @Test func aktarimGunluguSonOnMakbuzuTutarVeSecilenMakbuzGeriAlinir() throws {
        try izole {
            let ctx = try context()
            var makbuzlar: [UUID] = []
            for sira in 0..<12 {
                let onizleme = try StudentImportService.preview(rows: [["Öğrenci \(sira)", "\(100 + sira)", "5-A"]], mapping: .init(nameColumn: 0, numberColumn: 1, classColumn: 2, hasHeader: false))
                makbuzlar.append(try #require(StudentImportService.apply(onizleme, context: ctx).receiptID))
            }
            #expect(try StudentImportStore.allVerified().count == StudentImportStore.enFazlaMakbuz)
            // Eski bir makbuzu (sondan 3.) seçip geri al
            #expect(try StudentImportService.undo(receiptID: makbuzlar[9], context: ctx) == 1)
            #expect(try StudentStore.allVerified().count == 11)
            #expect(StudentImportService.geriAlinabilirMakbuzlar().count == StudentImportStore.enFazlaMakbuz - 1)
        }
    }

    // MARK: Okuma puanı ve sınıf atlatma

    private func iadeOlayi(_ ogrenci: UUID, kitap: UUID, sinif: String, tarih: Date) -> LoanEvent {
        var olay = LoanEvent(bookID: kitap, bookTitle: "K", person: "Ali", kind: .returned, date: tarih, dueDate: tarih, studentID: ogrenci, classSnapshot: sinif)
        olay.readingCompleted = true
        olay.identitySource = "student"
        return olay
    }

    @Test func okumaPuaniCokYilliOgrencideSinifiEnYeniOlaydanAlir() {
        let ogrenci = UUID()
        let olaylar = [
            iadeOlayi(ogrenci, kitap: UUID(), sinif: "5-A", tarih: Date(timeIntervalSince1970: 1_600_000_000)),
            iadeOlayi(ogrenci, kitap: UUID(), sinif: "6-A", tarih: Date(timeIntervalSince1970: 1_650_000_000)),
            iadeOlayi(ogrenci, kitap: UUID(), sinif: "7-A", tarih: Date(timeIntervalSince1970: 1_700_000_000))
        ]
        // Girdi sırası sonucu değiştirmemeli
        #expect(OkumaPuani.siralama(olaylar).first?.classSnapshot == "7-A")
        #expect(OkumaPuani.siralama(olaylar.reversed()).first?.classSnapshot == "7-A")
        #expect(OkumaPuani.siralama(olaylar).first?.kitapSayisi == 3)
    }

    @Test func sinifAtlatmaAcikRezervasyonunSinifiniGunceller() throws {
        try izole {
            let ctx = try context()
            let ali = Student(name: "Ali", number: "1", className: "5-A")
            try StudentStore.replaceAllVerified([ali])
            let kitap = CatalogBook(book: Book(title: "K", author: "Y", quantity: 1))
            ctx.insert(kitap)
            let rezervasyon = Reservation(bookID: kitap.id, bookTitleSnapshot: kitap.title, studentName: ali.name, studentClass: ali.className)
            rezervasyon.studentID = ali.id
            ctx.insert(rezervasyon); try ctx.save()
            _ = try SinifAtlatma.uygulaVerified(SinifAtlatma.plan([ali], sonKademe: 8), context: ctx)
            #expect(rezervasyon.studentClass == "6-A")
        }
    }

    // MARK: Önbellek ve toplu işlem

    @Test func ogrenciDefteriOnbellegiDosyaDegisinceYenilenir() throws {
        try izole {
            let ali = Student(name: "Ali", number: "1", className: "5-A")
            try StudentStore.replaceAllVerified([ali])
            #expect(StudentStore.all().count == 1)
            // Dışarıdan (geri yükleme gibi) farklı boyutta içerik yazılır
            let url = try #require(StudentStore.storageURL)
            try JSONEncoder().encode([ali, Student(name: "Veli", number: "2", className: "5-B")]).write(to: url, options: .atomic)
            #expect(StudentStore.all().count == 2)
            StudentStore.invalidateCaches()
            #expect(StudentStore.all().count == 2)
            try FileManager.default.removeItem(at: url)
            #expect(StudentStore.all().isEmpty)
        }
    }

    @Test func gecmisKitapIndeksiYazimdaYenilenir() throws {
        try izole {
            let kitap = UUID(), baska = UUID()
            var a = LoanEvent(bookID: kitap, bookTitle: "A", person: "Ali", kind: .lent, date: Date(timeIntervalSince1970: 100), dueDate: nil)
            a.id = UUID()
            let b = LoanEvent(bookID: baska, bookTitle: "B", person: "Veli", kind: .lent, date: Date(timeIntervalSince1970: 200), dueDate: nil)
            try LoanHistoryStore.replaceAll([a, b])
            #expect(LoanHistoryStore.events(forBook: kitap).map(\.id) == [a.id])
            let c = LoanEvent(bookID: kitap, bookTitle: "A", person: "Ayşe", kind: .lent, date: Date(timeIntervalSince1970: 300), dueDate: nil)
            try LoanHistoryStore.recordVerified(c)
            #expect(LoanHistoryStore.events(forBook: kitap).map(\.id) == [c.id, a.id])
            #expect(LoanHistoryStore.all.first?.id == c.id)
        }
    }

    @Test(.timeLimit(.minutes(3))) func yuzlerceOduncVeIadeTekGecmisAktarimiylaYazilir() throws {
        try izole {
            let ctx = try context()
            ctx.autosaveEnabled = false
            let ogrenciler = (0..<300).map { Student(name: "Öğrenci \($0)", number: "\($0 + 1)", className: "9-A") }
            try StudentStore.replaceAllVerified(ogrenciler)
            let kitap = CatalogBook(book: Book(title: "Matematik 9", author: "MEB", quantity: 300))
            ctx.insert(kitap); try ctx.save()
            let verilen = try SchoolLibraryService.batchLend(book: kitap, students: ogrenciler, className: "9-A", kind: "textbook", context: ctx)
            #expect(verilen.loans.count == 300 && verilen.failures.isEmpty)
            #expect(try ctx.fetchCount(FetchDescriptor<ActiveLoan>()) == 300)
            // Outbox tek aktarımla boşalmış, geçmiş yazılmış olmalı
            #expect(try ctx.fetchCount(FetchDescriptor<LibraryEventOutbox>()) == 0)
            #expect(LoanHistoryStore.all.filter { $0.kind == .lent }.count == 300)
            let alinan = try SchoolLibraryService.batchReturn(verilen.loans, context: ctx)
            #expect(alinan.returned.count == 300 && alinan.failures.isEmpty)
            #expect(try ctx.fetchCount(FetchDescriptor<ActiveLoan>()) == 0)
            #expect(try ctx.fetchCount(FetchDescriptor<LibraryEventOutbox>()) == 0)
            #expect(LoanHistoryStore.all.filter { $0.kind == .returned }.count == 300)
        }
    }

    @Test func topluOduncZatenElindekiniAtlarDigerleriniYazar() throws {
        try izole {
            let ctx = try context()
            let ali = Student(name: "Ali", number: "1", className: "5-A"), veli = Student(name: "Veli", number: "2", className: "5-A")
            try StudentStore.replaceAllVerified([ali, veli])
            let kitap = CatalogBook(book: Book(title: "K", author: "Y", quantity: 3))
            ctx.insert(kitap); try ctx.save()
            _ = try SchoolLibraryService.lend(book: kitap, person: ali.name, className: ali.className, context: ctx, studentID: ali.id)
            let sonuc = try SchoolLibraryService.batchLend(book: kitap, students: [ali, veli], className: "5-A", context: ctx)
            #expect(sonuc.skipped == ["Ali"])
            #expect(sonuc.loans.map(\.studentName) == ["Veli"])
            #expect(try ctx.fetchCount(FetchDescriptor<ActiveLoan>()) == 2)
        }
    }

    @Test func topluIadeGecersizSatiriAtlarGecerliSatiriKaydeder() throws {
        try izole {
            let ctx = try context()
            let kitap = CatalogBook(book: Book(title: "K", author: "Y", quantity: 2))
            ctx.insert(kitap); try ctx.save()
            let a = try SchoolLibraryService.lend(book: kitap, person: "Ali", className: "", context: ctx)
            let b = try SchoolLibraryService.lend(book: kitap, person: "Veli", className: "", context: ctx)
            let sonuc = try SchoolLibraryService.batchReturn([a, b], conditions: [b.id: "Geçersiz"], context: ctx)
            #expect(sonuc.returned == [a.id])
            #expect(sonuc.failures[b.id] != nil)
            #expect(try ctx.fetchCount(FetchDescriptor<ActiveLoan>()) == 1)
        }
    }

    // MARK: Kimlikler, dönem, filtre, mesajlar

    @Test func ogrenciKartiOgridNumaraVeCiftNumaraKurallari() throws {
        try izole {
            let ali = Student(name: "Ali", number: "101", className: "9-A")
            let veli = Student(name: "Veli", number: "202", className: "9-B")
            let cift1 = Student(name: "Can", number: "303", className: "9-A"), cift2 = Student(name: "Cem", number: "303", className: "9-B")
            try StudentStore.replaceAllVerified([ali, veli, cift1, cift2])
            let hex = ali.id.uuidString.replacingOccurrences(of: "-", with: "")
            #expect(try SchoolLibraryService.student(forCard: "OGRID" + hex).id == ali.id)
            #expect(try SchoolLibraryService.student(forCard: "ogr202").id == veli.id)
            #expect(throws: SchoolLibraryService.OperationError.self) { try SchoolLibraryService.student(forCard: "OGR303") }
            #expect(throws: SchoolLibraryService.OperationError.self) { try SchoolLibraryService.student(forCard: "OGR999") }
            #expect(throws: SchoolLibraryService.OperationError.self) { try SchoolLibraryService.student(forCard: "OGRID" + String(repeating: "0", count: 32)) }
        }
    }

    @Test func ogretimYiliSiniriAgustostaDegisir() {
        let takvim = takvim()
        let temmuz = takvim.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 12))!
        let agustos = takvim.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12))!
        #expect(!TextbookOperations.isPastPeriod("2025–2026", now: temmuz))
        #expect(TextbookOperations.isPastPeriod("2025–2026", now: agustos))
        #expect(!TextbookOperations.isPastPeriod("1. Dönem", now: agustos))
    }

    @Test func gecikenKutuphaneDersKitabiniSaymaz() {
        let dun = Calendar.current.date(byAdding: .day, value: -2, to: .now)!
        let kutuphane = ActiveLoan(bookID: UUID(), bookTitleSnapshot: "A", studentName: "Ali", studentClass: "5-A", dueDate: dun)
        let ders = ActiveLoan(bookID: UUID(), bookTitleSnapshot: "B", studentName: "Veli", studentClass: "5-A", dueDate: dun)
        ders.kind = "textbook"
        let gelecek = ActiveLoan(bookID: UUID(), bookTitleSnapshot: "C", studentName: "Can", studentClass: "5-A", dueDate: .now.addingTimeInterval(5 * 86_400))
        let loans = [kutuphane, ders, gelecek]
        #expect(LoanKindFilter.gecikenKutuphane(loans: loans).map(\.studentName) == ["Ali"])
        #expect(LoanKindFilter.dersKitabi.uygula(loans).count == 1)
        #expect(LoanKindFilter.kutuphane.uygula(loans).count == 2)
        #expect(LoanKindFilter.tumu.uygula(loans).count == 3)
        #expect(LoanKindFilter.dersKitabiBekleyen(loans: loans) == 1)
    }

    @Test func veliMesajiDersKitabiSablonuVeSinifTopluMesaji() {
        let simdi = Date(timeIntervalSince1970: 1_800_000_000)
        let ders = OduncMerkezi.veliMesaji(ogrenci: "Ali", sinif: "9-A", kitap: "Biyoloji 9", sonGun: simdi.addingTimeInterval(-86_400 * 3), okul: "Atatürk Lisesi", kind: "textbook", now: simdi)
        #expect(ders.contains("ders kitabını") && ders.contains("teslim"))
        #expect(ders.contains("Atatürk Lisesi Kütüphanesi") && ders.contains("Kütüphane sorumlusu"))
        let a1 = ActiveLoan(bookID: UUID(), bookTitleSnapshot: "Nutuk", studentName: "Ali", studentClass: "9-A", dueDate: simdi.addingTimeInterval(-86_400 * 3))
        let a2 = ActiveLoan(bookID: UUID(), bookTitleSnapshot: "Simyacı", studentName: "Ali", studentClass: "9-A", dueDate: simdi.addingTimeInterval(-86_400 * 2))
        let b1 = ActiveLoan(bookID: UUID(), bookTitleSnapshot: "Çalıkuşu", studentName: "Ayşe", studentClass: "9-A", dueDate: simdi.addingTimeInterval(-86_400))
        let toplu = OduncMerkezi.sinifVeliMesajlari([a1, a2, b1], okul: "Atatürk Lisesi", now: simdi)
        #expect(toplu.contains("• Nutuk") && toplu.contains("• Simyacı"))
        #expect(toplu.contains("Çalıkuşu"))
        #expect(toplu.components(separatedBy: "Sayın Veli").count - 1 == 2)
    }
}
